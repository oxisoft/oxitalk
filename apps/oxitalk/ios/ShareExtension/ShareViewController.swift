import UIKit
import UniformTypeIdentifiers

/// OxiTalk in the share sheet. No Flutter in here (an extension gets about 120 MB): it copies
/// what was shared into the App Group's container, `ShareInbox/<id>/`, with `manifest.json`
/// last (`{"files": [names], "text": "..."}`), then opens OxiTalk with `oxitalk-share://`,
/// which takes the share on start or resume (AppDelegate's io.oxisoft.oxitalk/share channel)
/// and shows "Send to…". If iOS doesn't let the extension open the app, it says to open
/// OxiTalk; the share waits there.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
  private static let appGroup = "group.io.oxisoft.oxitalk"
  private static let appURL = URL(string: "oxitalk-share://share")!

  private let label = UILabel()
  private let button = UIButton(type: .system)
  private var started = false

  override func viewDidLoad() {
    super.viewDidLoad()
    // Brand ink and yellow, as the app.
    view.backgroundColor = UIColor(red: 11 / 255, green: 11 / 255, blue: 18 / 255, alpha: 1)
    label.text = "Getting it ready…"
    label.textColor = .white
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = .preferredFont(forTextStyle: .headline)
    button.setTitle("Done", for: .normal)
    button.tintColor = UIColor(red: 252 / 255, green: 238 / 255, blue: 10 / 255, alpha: 1)
    button.isHidden = true
    button.addTarget(self, action: #selector(finish), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [label, button])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    Task { @MainActor in await self.receive() }
  }

  @objc private func finish() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }

  private func show(_ message: String) {
    label.text = message
    button.isHidden = false
  }

  @MainActor
  private func receive() async {
    let files = FileManager.default
    guard
      let container = files.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroup)
    else {
      show("OxiTalk can’t take this share on this device.")
      return
    }
    let id = UUID().uuidString
    let dir = container.appendingPathComponent("ShareInbox", isDirectory: true)
      .appendingPathComponent(id, isDirectory: true)
    do {
      try files.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      show("OxiTalk can’t take this share: no space for it.")
      return
    }
    var names: [String] = []
    var texts: [String] = []
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    for item in items {
      for provider in item.attachments ?? [] {
        switch await load(provider, into: dir) {
        case .file(let name): names.append(name)
        case .text(let text): if !texts.contains(text) { texts.append(text) }
        case nil: break
        }
      }
    }
    if names.isEmpty && texts.isEmpty {
      try? files.removeItem(at: dir)
      show("Nothing here OxiTalk can send.")
      return
    }
    let manifest: [String: Any] = ["files": names, "text": texts.joined(separator: "\n")]
    do {
      let data = try JSONSerialization.data(withJSONObject: manifest)
      try data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
    } catch {
      try? files.removeItem(at: dir)
      show("OxiTalk can’t take this share: no space for it.")
      return
    }
    if openApp(Self.appURL) {
      finish()
    } else {
      show("Open OxiTalk to choose the chat.")
    }
  }

  private enum Loaded {
    case file(String)
    case text(String)
  }

  /// One attachment: a web link or a piece of text as text, anything else as a file copied
  /// into [dir] (streamed from disk, never whole in memory).
  private func load(_ provider: NSItemProvider, into dir: URL) async -> Loaded? {
    let types = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
    let isFile = types.contains { $0.conforms(to: .fileURL) }
    if !isFile, types.contains(where: { $0.conforms(to: .url) }) {
      if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
        as? URL, !url.isFileURL
      {
        return .text(url.absoluteString)
      }
    }
    // Text typed or selected in another app, not a text file.
    if !isFile, provider.suggestedName == nil,
      types.allSatisfy({ $0.conforms(to: .text) || $0.conforms(to: .url) }),
      types.contains(where: { $0.conforms(to: .plainText) })
    {
      if let text = try? await provider.loadItem(
        forTypeIdentifier: UTType.plainText.identifier) as? String
      {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : .text(trimmed)
      }
    }
    // The most specific data type the attachment has: the file's own format.
    guard
      let type = types.first(where: {
        $0.conforms(to: .data) && !$0.conforms(to: .url)
      }) ?? types.first(where: { $0.conforms(to: .item) && !$0.conforms(to: .url) })
    else { return nil }
    if let name = await copyFile(provider, type: type, into: dir) { return .file(name) }
    return nil
  }

  private func copyFile(_ provider: NSItemProvider, type: UTType, into dir: URL) async
    -> String?
  {
    await withCheckedContinuation { continuation in
      _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
        // The file is gone when this returns: copy it now.
        guard let url else {
          continuation.resume(returning: nil)
          return
        }
        let name = Self.fileName(provider.suggestedName, from: url, type: type)
        let target = Self.unique(name, in: dir)
        do {
          try FileManager.default.copyItem(at: url, to: target)
          continuation.resume(returning: target.lastPathComponent)
        } catch {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  // Called from the item provider's queue.
  nonisolated private static func fileName(_ suggested: String?, from url: URL, type: UTType) -> String {
    var name = (suggested?.isEmpty == false ? suggested! : url.lastPathComponent)
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
    if name.isEmpty || name == "." || name == ".." { name = "file" }
    if (name as NSString).pathExtension.isEmpty {
      let ext = url.pathExtension.isEmpty ? type.preferredFilenameExtension : url.pathExtension
      if let ext, !ext.isEmpty { name += ".\(ext)" }
    }
    return name
  }

  nonisolated private static func unique(_ name: String, in dir: URL) -> URL {
    var target = dir.appendingPathComponent(name)
    var n = 1
    while FileManager.default.fileExists(atPath: target.path) {
      target = dir.appendingPathComponent("\(n)-\(name)")
      n += 1
    }
    return target
  }

  /// Opens the containing app from the extension. `UIApplication.shared` isn't available
  /// in extensions and `openURL:` stopped working in iOS 18, so the application is found up
  /// the responder chain and asked with `open(_:options:completionHandler:)` by selector.
  private func openApp(_ url: URL) -> Bool {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication, application.responds(to: selector) {
        typealias Open = @convention(c) (
          AnyObject, Selector, NSURL, NSDictionary, AnyObject?
        ) -> Void
        let open = unsafeBitCast(application.method(for: selector), to: Open.self)
        open(application, selector, url as NSURL, NSDictionary(), nil)
        return true
      }
      responder = current.next
    }
    return false
  }
}
