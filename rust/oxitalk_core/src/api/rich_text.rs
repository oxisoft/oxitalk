//! Formatted message text: the HTML of `formatted_body`, cleaned as the Matrix specification
//! says and flattened into blocks of styled runs the app draws with its own widgets.

use flutter_rust_bridge::frb;
use matrix_sdk::ruma::{
    MatrixToUri,
    html::{
        Html, NodeRef, SanitizerConfig,
        matrix::{AnchorUri, MatrixElement},
    },
    matrix_uri::MatrixId,
};

/// A block of text: a paragraph, heading, list item, code block or rule, perhaps in a quote.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RichBlock {
    pub kind: BlockKind,
    /// How many quotes it is in.
    pub quote_depth: u32,
    pub spans: Vec<RichSpan>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BlockKind {
    Paragraph,
    /// Level 1 to 6.
    Heading {
        level: u8,
    },
    /// `number` is `None` for a bullet; `depth` 1 for a top-level list.
    ListItem {
        number: Option<u32>,
        depth: u32,
    },
    /// Text as it is, in a monospace box.
    Code {
        language: Option<String>,
    },
    Rule,
}

/// A run of text with one style.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent styles, one flag each, as a text style has them"
)]
pub struct RichSpan {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
    pub strike: bool,
    pub underline: bool,
    pub code: bool,
    /// Hidden until clicked.
    pub spoiler: bool,
    pub link: Option<String>,
    /// A user mentioned: their user ID.
    pub mention: Option<String>,
    /// A CSS colour like `#ff0000`.
    pub color: Option<String>,
}

/// The blocks of `html`, after taking out what the specification doesn't allow and the
/// reply quote older clients put at the start.
pub(crate) fn rich_text(html: &str) -> Vec<RichBlock> {
    let document = Html::parse(html);
    document.sanitize_with(
        &SanitizerConfig::compat()
            .remove_reply_fallback()
            // Gone with their text, as Element drops them.
            .remove_elements(["script", "style", "title", "head"]),
    );
    let mut builder = Builder::default();
    for child in document.children() {
        builder.node(&child, &RichSpan::default());
    }
    builder.finish()
}

/// Walks the HTML; internal to the core.
#[frb(ignore)]
#[derive(Default)]
struct Builder {
    blocks: Vec<RichBlock>,
    /// The block being filled, if any.
    current: Option<RichBlock>,
    quote_depth: u32,
    /// For each list we are in: the next item's number, or `None` for bullets.
    lists: Vec<Option<u32>>,
    /// Inside `<pre>`: text kept as it is.
    preformatted: bool,
    /// The kind for the next block a list item or heading starts.
    pending_kind: Option<BlockKind>,
}

impl Builder {
    fn node(&mut self, node: &NodeRef, style: &RichSpan) {
        if let Some(text) = node.as_text() {
            self.text(&text.borrow(), style);
            return;
        }
        let Some(element) = node.as_element() else {
            self.children(node, style);
            return;
        };
        let element = element.to_matrix().element;
        let mut inner = style.clone();
        if inline_style(&element, &mut inner, self.preformatted) {
            self.children(node, &inner);
        } else {
            self.element(element, node, style, inner);
        }
    }

    /// An element that isn't only a style: a block, a break, an image, or a table cell.
    fn element(
        &mut self,
        element: MatrixElement,
        node: &NodeRef,
        style: &RichSpan,
        mut inner: RichSpan,
    ) {
        match element {
            MatrixElement::Br => self.text_raw("\n", style),
            MatrixElement::Hr => {
                self.flush();
                self.push(BlockKind::Rule, Vec::new());
            }
            MatrixElement::Img(image) => {
                // An inline image (custom emoji): its alt text.
                let alt = image.alt.map_or_else(String::new, |alt| alt.to_string());
                self.text(&alt, style);
            }
            MatrixElement::P | MatrixElement::Div(_) | MatrixElement::Tr => {
                self.block(node, &inner, None);
            }
            MatrixElement::Td | MatrixElement::Th => {
                // A table row reads as cells separated by bars.
                if self.current.as_ref().is_some_and(|b| !b.spans.is_empty()) {
                    self.text_raw(" | ", style);
                }
                inner.bold |= matches!(element, MatrixElement::Th);
                self.children(node, &inner);
            }
            MatrixElement::H(heading) => {
                let level = heading.level.value();
                self.block(node, &inner, Some(BlockKind::Heading { level }));
            }
            MatrixElement::Blockquote => {
                self.quote_depth += 1;
                self.block(node, &inner, None);
                self.quote_depth -= 1;
            }
            MatrixElement::Ul | MatrixElement::Ol(_) => {
                let start = match element {
                    MatrixElement::Ol(list) => Some(
                        list.start
                            .and_then(|start| u32::try_from(start).ok())
                            .unwrap_or(1),
                    ),
                    _ => None,
                };
                self.lists.push(start);
                self.block(node, &inner, None);
                self.lists.pop();
            }
            MatrixElement::Li => {
                let depth = u32::try_from(self.lists.len()).unwrap_or(u32::MAX);
                let number = self.lists.last_mut().and_then(|next| {
                    let number = *next;
                    if let Some(n) = next {
                        *n += 1;
                    }
                    number
                });
                let kind = BlockKind::ListItem {
                    number,
                    depth: depth.max(1),
                };
                self.block(node, &inner, Some(kind));
            }
            MatrixElement::Pre => {
                let language = node.children().find_map(|child| {
                    match child.as_element()?.to_matrix().element {
                        MatrixElement::Code(code) => code.language.map(|l| l.to_string()),
                        _ => None,
                    }
                });
                self.preformatted = true;
                self.block(node, &inner, Some(BlockKind::Code { language }));
                self.preformatted = false;
            }
            _ => self.children(node, &inner),
        }
    }

    /// The element's content as blocks of their own, the first of [kind] if given.
    fn block(&mut self, node: &NodeRef, style: &RichSpan, kind: Option<BlockKind>) {
        self.flush();
        if kind.is_some() {
            self.pending_kind = kind;
        }
        self.children(node, style);
        self.flush();
    }

    fn children(&mut self, node: &NodeRef, style: &RichSpan) {
        for child in node.children() {
            self.node(&child, style);
        }
    }

    /// Text from the HTML: white space folds to single spaces, except in `<pre>`.
    fn text(&mut self, text: &str, style: &RichSpan) {
        if self.preformatted {
            self.text_raw(text, style);
            return;
        }
        let mut folded = String::with_capacity(text.len());
        let mut space = false;
        for c in text.chars() {
            if c.is_whitespace() {
                space = true;
            } else {
                if space {
                    folded.push(' ');
                }
                space = false;
                folded.push(c);
            }
        }
        if space {
            folded.push(' ');
        }
        // No space at a block's start, nor a block of white space alone.
        let at_start = self
            .current
            .as_ref()
            .is_none_or(|block| block.spans.iter().all(|s| s.text.ends_with('\n')));
        let folded = if at_start {
            folded.trim_start().to_owned()
        } else {
            folded
        };
        if !folded.is_empty() {
            self.text_raw(&folded, style);
        }
    }

    fn text_raw(&mut self, text: &str, style: &RichSpan) {
        let kind = self.pending_kind.take();
        let quote_depth = self.quote_depth;
        let block = self.current.get_or_insert_with(|| RichBlock {
            kind: kind.unwrap_or(BlockKind::Paragraph),
            quote_depth,
            spans: Vec::new(),
        });
        match block.spans.last_mut() {
            Some(last) if same_style(last, style) => last.text.push_str(text),
            _ => block.spans.push(RichSpan {
                text: text.to_owned(),
                ..style.clone()
            }),
        }
    }

    fn push(&mut self, kind: BlockKind, spans: Vec<RichSpan>) {
        self.blocks.push(RichBlock {
            kind,
            quote_depth: self.quote_depth,
            spans,
        });
    }

    /// Ends the block being filled, without the spaces at its end.
    fn flush(&mut self) {
        let Some(mut block) = self.current.take() else {
            return;
        };
        if !matches!(block.kind, BlockKind::Code { .. }) {
            while let Some(last) = block.spans.last_mut() {
                let trimmed = last.text.trim_end().len();
                last.text.truncate(trimmed);
                if last.text.is_empty() {
                    block.spans.pop();
                } else {
                    break;
                }
            }
        } else if let Some(last) = block.spans.last_mut()
            && last.text.ends_with('\n')
        {
            last.text.pop();
        }
        if !block.spans.is_empty() {
            self.blocks.push(block);
        }
    }

    fn finish(mut self) -> Vec<RichBlock> {
        self.flush();
        self.blocks
    }
}

/// Applies an element that only styles its text (bold, a link, …) to [style]; `false` for
/// any other element.
fn inline_style(element: &MatrixElement, style: &mut RichSpan, preformatted: bool) -> bool {
    match element {
        MatrixElement::B | MatrixElement::Strong => style.bold = true,
        MatrixElement::I | MatrixElement::Em => style.italic = true,
        MatrixElement::S | MatrixElement::Del => style.strike = true,
        MatrixElement::U => style.underline = true,
        // In a code block, `<code>` is the block's text, not a style.
        MatrixElement::Code(_) => style.code = !preformatted,
        MatrixElement::A(anchor) => match &anchor.href {
            Some(AnchorUri::MatrixTo(uri)) => link_or_mention(style, uri),
            Some(AnchorUri::Matrix(uri)) => style.link = Some(uri.to_string()),
            Some(AnchorUri::Other(url)) => style.link = Some(url.to_string()),
            // A scheme added to the specification later: shown as plain text.
            Some(_) | None => {}
        },
        MatrixElement::Span(span) => {
            style.spoiler |= span.spoiler.is_some();
            if let Some(color) = &span.color {
                style.color = Some(color.to_string());
            }
        }
        _ => return false,
    }
    true
}

fn same_style(a: &RichSpan, b: &RichSpan) -> bool {
    RichSpan {
        text: String::new(),
        ..a.clone()
    } == RichSpan {
        text: String::new(),
        ..b.clone()
    }
}

/// A `matrix.to` link to a user is a mention; to anything else, a link.
fn link_or_mention(style: &mut RichSpan, uri: &MatrixToUri) {
    match uri.id() {
        MatrixId::User(user) => style.mention = Some(user.to_string()),
        _ => style.link = Some(uri.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn span(text: &str) -> RichSpan {
        RichSpan {
            text: text.to_owned(),
            ..RichSpan::default()
        }
    }

    fn paragraph(spans: Vec<RichSpan>) -> RichBlock {
        RichBlock {
            kind: BlockKind::Paragraph,
            quote_depth: 0,
            spans,
        }
    }

    #[test]
    fn inline_styles_become_runs() {
        let blocks = rich_text(
            "Hi <strong>bold</strong>, <em>it</em> <del>gone</del> <code>x()</code> \
             <a href=\"https://oxisoft.io\">site</a>",
        );
        assert_eq!(
            blocks,
            vec![paragraph(vec![
                span("Hi "),
                RichSpan {
                    bold: true,
                    ..span("bold")
                },
                span(", "),
                RichSpan {
                    italic: true,
                    ..span("it")
                },
                span(" "),
                RichSpan {
                    strike: true,
                    ..span("gone")
                },
                span(" "),
                RichSpan {
                    code: true,
                    ..span("x()")
                },
                span(" "),
                RichSpan {
                    link: Some("https://oxisoft.io".to_owned()),
                    ..span("site")
                },
            ])]
        );
    }

    #[test]
    fn lists_headings_quotes_and_code_become_blocks() {
        let blocks = rich_text(
            "<h2>Title</h2>\n<ul>\n<li>one</li>\n<li>two<ol start=\"3\"><li>three</li></ol></li>\n\
             </ul><blockquote><p>quoted</p></blockquote>\
             <pre><code class=\"language-rust\">fn main() {\n    go();\n}\n</code></pre><hr>",
        );
        let kinds: Vec<_> = blocks
            .iter()
            .map(|b| {
                (
                    b.kind.clone(),
                    b.quote_depth,
                    b.spans[..].first().map(|s| s.text.clone()),
                )
            })
            .collect();
        assert_eq!(
            kinds,
            vec![
                (BlockKind::Heading { level: 2 }, 0, Some("Title".to_owned())),
                (
                    BlockKind::ListItem {
                        number: None,
                        depth: 1
                    },
                    0,
                    Some("one".to_owned())
                ),
                (
                    BlockKind::ListItem {
                        number: None,
                        depth: 1
                    },
                    0,
                    Some("two".to_owned())
                ),
                (
                    BlockKind::ListItem {
                        number: Some(3),
                        depth: 2
                    },
                    0,
                    Some("three".to_owned())
                ),
                (BlockKind::Paragraph, 1, Some("quoted".to_owned())),
                (
                    BlockKind::Code {
                        language: Some("rust".to_owned())
                    },
                    0,
                    Some("fn main() {\n    go();\n}".to_owned())
                ),
                (BlockKind::Rule, 0, None),
            ]
        );
    }

    #[test]
    fn mentions_spoilers_and_line_breaks() {
        let blocks = rich_text(
            "<a href=\"https://matrix.to/#/@bob:acme.com\">Bob</a> look<br>\
             <span data-mx-spoiler>secret</span>",
        );
        assert_eq!(
            blocks,
            vec![paragraph(vec![
                RichSpan {
                    mention: Some("@bob:acme.com".to_owned()),
                    ..span("Bob")
                },
                span(" look\n"),
                RichSpan {
                    spoiler: true,
                    ..span("secret")
                },
            ])]
        );
    }

    #[test]
    fn what_is_not_allowed_goes_and_the_reply_quote_too() {
        let blocks = rich_text(
            "<mx-reply><blockquote>old</blockquote></mx-reply>\
             <script>alert(1)</script><b onclick=\"x()\">safe</b>",
        );
        assert_eq!(
            blocks,
            vec![paragraph(vec![RichSpan {
                bold: true,
                ..span("safe")
            }])]
        );
    }
}
