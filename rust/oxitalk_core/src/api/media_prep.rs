//! Getting a picture ready to send: its size, and with compression a smaller JPEG.

use std::io::Cursor;

use image::{
    DynamicImage, ImageDecoder, ImageFormat, ImageReader, codecs::jpeg::JpegEncoder,
    imageops::FilterType,
};

/// The longest side of a compressed photo, as Element X sends them.
const MAX_SIDE: u32 = 2048;
/// Smaller files are sent as they are, even when compressing.
const SMALL_ENOUGH: usize = 1024 * 1024;
const JPEG_QUALITY: u8 = 85;

#[derive(Debug)]
pub(crate) struct PreparedImage {
    pub(crate) data: Vec<u8>,
    pub(crate) filename: String,
    pub(crate) mime_type: String,
    pub(crate) width: Option<u32>,
    pub(crate) height: Option<u32>,
}

/// The image's size, and with `compress` a big photo scaled to [`MAX_SIDE`] (turned upright
/// as its camera recorded) and saved as JPEG, if that is smaller. A GIF stays as it is (it
/// may move), and so does anything that can't be decoded.
pub(crate) fn prepare_image(
    data: Vec<u8>,
    filename: String,
    mime_type: String,
    compress: bool,
) -> PreparedImage {
    let Some(image) = decode_upright(&data) else {
        return PreparedImage {
            data,
            filename,
            mime_type,
            width: None,
            height: None,
        };
    };
    let original = PreparedImage {
        width: Some(image.width()),
        height: Some(image.height()),
        data,
        filename,
        mime_type,
    };
    let big = image.width().max(image.height()) > MAX_SIDE || original.data.len() > SMALL_ENOUGH;
    if !compress || !big || original.mime_type == "image/gif" {
        return original;
    }
    let scaled = if image.width().max(image.height()) > MAX_SIDE {
        image.resize(MAX_SIDE, MAX_SIDE, FilterType::Lanczos3)
    } else {
        image
    };
    let mut jpeg = Vec::new();
    let encoded = JpegEncoder::new_with_quality(&mut jpeg, JPEG_QUALITY)
        .encode_image(&DynamicImage::ImageRgb8(scaled.to_rgb8()));
    if encoded.is_err() || jpeg.len() >= original.data.len() {
        return original;
    }
    let stem = std::path::Path::new(&original.filename)
        .file_stem()
        .map_or_else(
            || "image".to_owned(),
            |stem| stem.to_string_lossy().into_owned(),
        );
    PreparedImage {
        data: jpeg,
        filename: format!("{stem}.jpg"),
        mime_type: "image/jpeg".to_owned(),
        width: Some(scaled.width()),
        height: Some(scaled.height()),
    }
}

fn decode_upright(data: &[u8]) -> Option<DynamicImage> {
    let mut decoder = ImageReader::new(Cursor::new(data))
        .with_guessed_format()
        .ok()?
        .into_decoder()
        .ok()?;
    let orientation = decoder.orientation().ok();
    let mut image = DynamicImage::from_decoder(decoder).ok()?;
    if let Some(orientation) = orientation {
        image.apply_orientation(orientation);
    }
    Some(image)
}

/// A picture of an image file no bigger than `side` on its longest side, for showing it small:
/// turned upright, as JPEG (PNG if it has transparency). `None` when the file should be shown
/// as it is: it's already that small, it's a GIF (it may move), or it can't be decoded.
pub(crate) fn shrink_for_preview(data: &[u8], side: u32) -> Option<Vec<u8>> {
    let reader = ImageReader::new(Cursor::new(data))
        .with_guessed_format()
        .ok()?;
    if reader.format() == Some(ImageFormat::Gif) {
        return None;
    }
    let image = decode_upright(data)?;
    if image.width().max(image.height()) <= side {
        return None;
    }
    let image = image.resize(side, side, FilterType::Triangle);
    let mut encoded = Vec::new();
    if image.color().has_alpha() {
        DynamicImage::ImageRgba8(image.to_rgba8())
            .write_to(&mut Cursor::new(&mut encoded), ImageFormat::Png)
            .ok()?;
    } else {
        JpegEncoder::new_with_quality(&mut encoded, JPEG_QUALITY)
            .encode_image(&DynamicImage::ImageRgb8(image.to_rgb8()))
            .ok()?;
    }
    Some(encoded)
}

/// The longest side of a video's thumbnail.
const THUMBNAIL_SIDE: u32 = 800;

#[derive(Debug)]
pub(crate) struct PreparedThumbnail {
    pub(crate) data: Vec<u8>,
    pub(crate) width: u32,
    pub(crate) height: u32,
}

/// A video's thumbnail from a photo the camera took as it started: turned upright, cut to
/// the video's shape `width` × `height` around its middle (when known), at most
/// [`THUMBNAIL_SIDE`] wide or high, as JPEG. `None` if the photo can't be read.
#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss
)]
pub(crate) fn prepare_thumbnail(
    photo: &[u8],
    width: Option<u32>,
    height: Option<u32>,
) -> Option<PreparedThumbnail> {
    let mut image = decode_upright(photo)?;
    if let (Some(width), Some(height)) = (width, height)
        && width > 0
        && height > 0
    {
        let (photo_width, photo_height) = (image.width(), image.height());
        let wanted = f64::from(width) / f64::from(height);
        let (crop_width, crop_height) = if f64::from(photo_width) / f64::from(photo_height) > wanted
        {
            // Within the photo's size, so the casts can't overflow.
            ((f64::from(photo_height) * wanted) as u32, photo_height)
        } else {
            (photo_width, (f64::from(photo_width) / wanted) as u32)
        };
        image = image.crop_imm(
            (photo_width - crop_width) / 2,
            (photo_height - crop_height) / 2,
            crop_width.max(1),
            crop_height.max(1),
        );
    }
    let image = image.resize(THUMBNAIL_SIDE, THUMBNAIL_SIDE, FilterType::Triangle);
    let mut data = Vec::new();
    JpegEncoder::new_with_quality(&mut data, JPEG_QUALITY)
        .encode_image(&DynamicImage::ImageRgb8(image.to_rgb8()))
        .ok()?;
    Some(PreparedThumbnail {
        data,
        width: image.width(),
        height: image.height(),
    })
}

/// A thumbnail to send with an image, at most [`THUMBNAIL_SIDE`] on its longest side, as
/// JPEG, so other apps (and this one) show the message without fetching the whole file.
/// `None` for a picture that small already, a GIF (it may move), one with transparency (JPEG
/// would lose it), or anything that can't be decoded.
pub(crate) fn image_thumbnail(data: &[u8]) -> Option<PreparedThumbnail> {
    let reader = ImageReader::new(Cursor::new(data))
        .with_guessed_format()
        .ok()?;
    if reader.format() == Some(ImageFormat::Gif) {
        return None;
    }
    let image = decode_upright(data)?;
    if image.width().max(image.height()) <= THUMBNAIL_SIDE || image.color().has_alpha() {
        return None;
    }
    let image = image.resize(THUMBNAIL_SIDE, THUMBNAIL_SIDE, FilterType::Triangle);
    let mut encoded = Vec::new();
    JpegEncoder::new_with_quality(&mut encoded, JPEG_QUALITY)
        .encode_image(&DynamicImage::ImageRgb8(image.to_rgb8()))
        .ok()?;
    Some(PreparedThumbnail {
        data: encoded,
        width: image.width(),
        height: image.height(),
    })
}

#[cfg(test)]
mod tests {
    use image::{RgbImage, RgbaImage};

    use super::*;

    fn png(width: u32, height: u32) -> Result<Vec<u8>, image::ImageError> {
        // Noise, so the PNG doesn't compress to almost nothing.
        let byte = |value: u32| u8::try_from(value % 256).unwrap_or_default();
        let image = RgbImage::from_fn(width, height, |x, y| {
            image::Rgb([byte(x * 7 + y * 13), byte(x ^ y), byte(x * y)])
        });
        let mut data = Vec::new();
        DynamicImage::ImageRgb8(image).write_to(&mut Cursor::new(&mut data), ImageFormat::Png)?;
        Ok(data)
    }

    #[test]
    fn a_big_photo_is_scaled_and_made_jpeg_when_compressing() -> Result<(), image::ImageError> {
        let data = png(3000, 1500)?;
        let prepared = prepare_image(data.clone(), "beach.png".into(), "image/png".into(), true);
        assert_eq!(prepared.mime_type, "image/jpeg");
        assert_eq!(prepared.filename, "beach.jpg");
        assert_eq!((prepared.width, prepared.height), (Some(2048), Some(1024)));
        assert!(prepared.data.len() < data.len());
        Ok(())
    }

    #[test]
    fn without_compressing_the_original_goes_with_its_size() -> Result<(), image::ImageError> {
        let data = png(3000, 1500)?;
        let prepared = prepare_image(data.clone(), "beach.png".into(), "image/png".into(), false);
        assert_eq!(prepared.data, data);
        assert_eq!((prepared.width, prepared.height), (Some(3000), Some(1500)));
        Ok(())
    }

    #[test]
    fn a_small_picture_or_an_undecodable_file_stays_as_it_is() -> Result<(), image::ImageError> {
        let small = png(64, 64)?;
        let prepared = prepare_image(small.clone(), "a.png".into(), "image/png".into(), true);
        assert_eq!(prepared.data, small);
        assert_eq!(prepared.width, Some(64));
        let junk = b"not an image".to_vec();
        let prepared = prepare_image(junk.clone(), "x.png".into(), "image/png".into(), true);
        assert_eq!(prepared.data, junk);
        assert_eq!(prepared.width, None);
        Ok(())
    }

    #[test]
    fn a_video_thumbnail_takes_the_video_shape_and_a_small_size()
    -> Result<(), Box<dyn std::error::Error>> {
        let photo = png(4000, 3000)?;
        let thumbnail = prepare_thumbnail(&photo, Some(1280), Some(720)).ok_or("no thumbnail")?;
        assert_eq!((thumbnail.width, thumbnail.height), (800, 450));
        assert!(thumbnail.data.starts_with(b"\xff\xd8"));
        let portrait = prepare_thumbnail(&photo, Some(720), Some(1280));
        assert_eq!(portrait.map(|t| (t.width, t.height)), Some((450, 800)));
        let as_is = prepare_thumbnail(&photo, None, None);
        assert_eq!(as_is.map(|t| (t.width, t.height)), Some((800, 600)));
        assert!(prepare_thumbnail(b"junk", None, None).is_none());
        Ok(())
    }

    #[test]
    fn a_preview_is_shrunk_to_the_side_asked_for() -> Result<(), Box<dyn std::error::Error>> {
        let photo = png(3000, 1500)?;
        let preview = shrink_for_preview(&photo, 640).ok_or("no preview")?;
        assert!(preview.starts_with(b"\xff\xd8"));
        let image = image::load_from_memory(&preview)?;
        assert_eq!((image.width(), image.height()), (640, 320));
        Ok(())
    }

    #[test]
    fn a_transparent_picture_stays_transparent_in_its_preview()
    -> Result<(), Box<dyn std::error::Error>> {
        let image = RgbaImage::from_pixel(1000, 1000, image::Rgba([10, 20, 30, 0]));
        let mut data = Vec::new();
        DynamicImage::ImageRgba8(image).write_to(&mut Cursor::new(&mut data), ImageFormat::Png)?;
        let preview = shrink_for_preview(&data, 100).ok_or("no preview")?;
        let preview = image::load_from_memory(&preview)?;
        assert!(preview.color().has_alpha());
        assert_eq!(preview.width(), 100);
        Ok(())
    }

    #[test]
    fn a_small_picture_a_gif_or_junk_has_no_preview_of_its_own()
    -> Result<(), Box<dyn std::error::Error>> {
        assert!(shrink_for_preview(&png(300, 200)?, 640).is_none());
        let mut gif = Vec::new();
        DynamicImage::ImageRgb8(RgbImage::new(1000, 1000))
            .write_to(&mut Cursor::new(&mut gif), ImageFormat::Gif)?;
        assert!(shrink_for_preview(&gif, 640).is_none());
        assert!(shrink_for_preview(b"junk", 640).is_none());
        Ok(())
    }

    #[test]
    fn an_image_gets_a_thumbnail_to_send_unless_it_is_small_moving_or_transparent()
    -> Result<(), Box<dyn std::error::Error>> {
        let thumbnail = image_thumbnail(&png(2048, 1024)?).ok_or("no thumbnail")?;
        assert_eq!((thumbnail.width, thumbnail.height), (800, 400));
        assert!(thumbnail.data.starts_with(b"\xff\xd8"));
        assert!(image_thumbnail(&png(800, 600)?).is_none());
        let clear = RgbaImage::from_pixel(1600, 1600, image::Rgba([0, 0, 0, 0]));
        let mut data = Vec::new();
        DynamicImage::ImageRgba8(clear).write_to(&mut Cursor::new(&mut data), ImageFormat::Png)?;
        assert!(image_thumbnail(&data).is_none());
        let mut gif = Vec::new();
        DynamicImage::ImageRgb8(RgbImage::new(1600, 1600))
            .write_to(&mut Cursor::new(&mut gif), ImageFormat::Gif)?;
        assert!(image_thumbnail(&gif).is_none());
        Ok(())
    }
}
