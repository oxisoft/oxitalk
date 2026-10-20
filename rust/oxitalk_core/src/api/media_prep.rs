//! Getting a picture ready to send: its size, and with compression a smaller JPEG.

use std::io::Cursor;

use image::{
    DynamicImage, ImageDecoder, ImageReader, codecs::jpeg::JpegEncoder, imageops::FilterType,
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

#[cfg(test)]
mod tests {
    use image::{ImageFormat, RgbImage};

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
}
