//! Voice messages as Element sends them: Ogg Opus, mono, 48 kHz, with a waveform. Recorded
//! sound comes in as plain samples from any platform and leaves as one file; a voice message
//! that arrives is turned into a WAV file, which every platform's player can play.

use std::io::Cursor;

use ogg::{PacketReader, PacketWriteEndInfo, PacketWriter};
use opus_rs::{Application, OpusDecoder, OpusEncoder};

use super::error::CoreError;

/// Opus runs at 48 kHz here, in and out.
const RATE: u32 = 48_000;
/// 20 ms, the usual Opus frame.
const FRAME: usize = 960;
/// The longest Opus packet: 120 ms.
const MAX_FRAME: usize = 5_760;
/// What the encoder puts in front of the sound (libopus' lookahead at 48 kHz), which a
/// player skips.
const PRE_SKIP: u16 = 312;
/// Plenty for speech; Element Web records voice messages at the same rate.
const BITRATE: i32 = 24_000;
/// Points in a waveform, as Element sends them.
const WAVEFORM_POINTS: usize = 100;
/// The loudest point of a waveform in the event (MSC1767).
pub const WAVEFORM_MAX: u16 = 1024;
const SERIAL: u32 = 0x4f78_5461;

/// A recorded voice message, ready to send.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceClip {
    /// An Ogg Opus file.
    pub data: Vec<u8>,
    pub duration_ms: i64,
    /// [`WAVEFORM_POINTS`] points from 0 to [`WAVEFORM_MAX`], the loudest at the top.
    pub waveform: Vec<u16>,
}

/// Makes a voice message of recorded sound: interleaved 16-bit samples of `channels`
/// channels at `sample_rate`, as any platform's recorder gives them.
///
/// # Errors
///
/// [`CoreError::Internal`] for no channels or sample rate, or if the encoder fails.
// The bridge hands over owned values.
#[allow(clippy::needless_pass_by_value)]
pub fn encode_voice(
    pcm: Vec<i16>,
    sample_rate: u32,
    channels: u32,
) -> Result<VoiceClip, CoreError> {
    let channels = usize::try_from(channels).unwrap_or_default();
    if sample_rate == 0 || channels == 0 {
        return Err(CoreError::internal(&"no sample rate or channels"));
    }
    let mono = resample(&downmix(&pcm, channels), sample_rate, RATE);
    let data = ogg_opus(&mono, sample_rate).map_err(|error| CoreError::internal(&error))?;
    Ok(VoiceClip {
        data,
        duration_ms: samples_to_ms(mono.len()),
        waveform: waveform(&mono),
    })
}

/// A file every platform's player can play for an audio message: an Ogg Opus file (a voice
/// message) decoded to WAV, a WAV file as it is; `None` for anything else, which only the
/// platform may know how to play.
#[must_use]
pub fn playable_wav(data: Vec<u8>) -> Option<Vec<u8>> {
    if data.starts_with(b"RIFF") && data.get(8..12) == Some(b"WAVE") {
        return Some(data);
    }
    decode_ogg_opus(&data).ok().map(|pcm| wav(&pcm, RATE))
}

/// The size of the header [`wav`] writes.
const WAV_HEADER: usize = 44;

fn samples_to_ms(samples: usize) -> i64 {
    i64::try_from(samples as u64 * 1000 / u64::from(RATE)).unwrap_or(i64::MAX)
}

/// Mono 16-bit samples at 48 kHz as an Ogg Opus file.
fn ogg_opus(mono: &[i16], input_rate: u32) -> Result<Vec<u8>, String> {
    let mut encoder = OpusEncoder::new(48_000, 1, Application::Voip).map_err(str::to_owned)?;
    encoder.bitrate_bps = BITRATE;
    let mut data = Vec::new();
    let mut writer = PacketWriter::new(&mut data);
    let headers = [opus_head(input_rate), opus_tags()];
    for header in headers {
        writer
            .write_packet(header, SERIAL, PacketWriteEndInfo::EndPage, 0)
            .map_err(|error| error.to_string())?;
    }
    // Enough frames that the sound after the encoder's lookahead is all in them.
    let frames = (mono.len() + usize::from(PRE_SKIP)).div_ceil(FRAME);
    let mut frame = [0_i16; FRAME];
    let mut packet = [0_u8; 4_000];
    for index in 0..frames {
        let start = (index * FRAME).min(mono.len());
        let end = (start + FRAME).min(mono.len());
        frame.fill(0);
        frame[..end - start].copy_from_slice(&mono[start..end]);
        let len = encoder
            .encode_i16(&frame, FRAME, &mut packet)
            .map_err(str::to_owned)?;
        let last = index + 1 == frames;
        // The position after this packet, counting the skipped samples; the last one tells
        // the player where the sound ends.
        let granule = if last {
            u64::from(PRE_SKIP) + mono.len() as u64
        } else {
            ((index + 1) * FRAME) as u64
        };
        let end_info = if last {
            PacketWriteEndInfo::EndStream
        } else {
            PacketWriteEndInfo::NormalPacket
        };
        writer
            .write_packet(packet[..len].to_vec(), SERIAL, end_info, granule)
            .map_err(|error| error.to_string())?;
    }
    drop(writer);
    Ok(data)
}

/// An Ogg Opus file as mono 16-bit samples at 48 kHz.
fn decode_ogg_opus(data: &[u8]) -> Result<Vec<i16>, String> {
    let mut reader = PacketReader::new(Cursor::new(data));
    let head = reader
        .read_packet()
        .map_err(|error| error.to_string())?
        .ok_or("empty")?;
    if !head.data.starts_with(b"OpusHead") || head.data.len() < 19 {
        return Err("not Ogg Opus".to_owned());
    }
    let pre_skip = usize::from(u16::from_le_bytes([head.data[10], head.data[11]]));
    let serial = head.stream_serial();
    let mut decoder = OpusDecoder::new(48_000, 1).map_err(str::to_owned)?;
    let mut pcm = Vec::new();
    let mut out = vec![0_f32; MAX_FRAME];
    let mut end = None;
    let mut tags_seen = false;
    while let Some(packet) = reader.read_packet().map_err(|error| error.to_string())? {
        if packet.stream_serial() != serial {
            continue;
        }
        // The comment header comes second.
        if !tags_seen {
            tags_seen = true;
            continue;
        }
        let samples = decoder
            .decode(&packet.data, MAX_FRAME, &mut out)
            .map_err(str::to_owned)?;
        pcm.extend(out[..samples].iter().map(|sample| to_i16(*sample)));
        if packet.last_in_stream() {
            end = usize::try_from(packet.absgp_page()).ok();
            break;
        }
    }
    let mut pcm = pcm.split_off(pre_skip.min(pcm.len()));
    if let Some(end) = end {
        pcm.truncate(end.saturating_sub(pre_skip));
    }
    Ok(pcm)
}

/// A WAV file of 16-bit mono samples at `rate`.
fn wav(pcm: &[i16], rate: u32) -> Vec<u8> {
    let bytes = u32::try_from(pcm.len() * 2).unwrap_or(u32::MAX - 36);
    let mut out = Vec::with_capacity(WAV_HEADER + pcm.len() * 2);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + bytes).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16_u32.to_le_bytes());
    // PCM, one channel.
    out.extend_from_slice(&1_u16.to_le_bytes());
    out.extend_from_slice(&1_u16.to_le_bytes());
    out.extend_from_slice(&rate.to_le_bytes());
    out.extend_from_slice(&(rate * 2).to_le_bytes());
    out.extend_from_slice(&2_u16.to_le_bytes());
    out.extend_from_slice(&16_u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&bytes.to_le_bytes());
    for sample in pcm {
        out.extend_from_slice(&sample.to_le_bytes());
    }
    out
}

#[allow(clippy::cast_possible_truncation)]
fn to_i16(sample: f32) -> i16 {
    // Clamped into range first.
    (sample * 32_768.0).clamp(-32_768.0, 32_767.0) as i16
}

#[allow(clippy::cast_possible_truncation, clippy::cast_possible_wrap)]
fn downmix(pcm: &[i16], channels: usize) -> Vec<i16> {
    if channels == 1 {
        return pcm.to_vec();
    }
    // The mean of the channels stays within i16.
    pcm.chunks_exact(channels)
        .map(|frame| (frame.iter().map(|s| i32::from(*s)).sum::<i32>() / channels as i32) as i16)
        .collect()
}

/// By linear interpolation, which is plenty for speech.
#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss
)]
fn resample(pcm: &[i16], from: u32, to: u32) -> Vec<i16> {
    if from == to || pcm.is_empty() {
        return pcm.to_vec();
    }
    let len = usize::try_from(pcm.len() as u64 * u64::from(to) / u64::from(from)).unwrap_or(0);
    let step = f64::from(from) / f64::from(to);
    (0..len)
        .map(|index| {
            let position = index as f64 * step;
            let left = (position.floor() as usize).min(pcm.len() - 1);
            let right = (left + 1).min(pcm.len() - 1);
            let fraction = position - left as f64;
            // Between two i16 samples.
            (f64::from(pcm[left]) * (1.0 - fraction) + f64::from(pcm[right]) * fraction) as i16
        })
        .collect()
}

/// The loudness (RMS) of [`WAVEFORM_POINTS`] stretches of the sound, the loudest at
/// [`WAVEFORM_MAX`]; all 0 for silence.
#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss
)]
fn waveform(pcm: &[i16]) -> Vec<u16> {
    let rms: Vec<f64> = (0..WAVEFORM_POINTS)
        .map(|point| {
            let start = point * pcm.len() / WAVEFORM_POINTS;
            let end = (point + 1) * pcm.len() / WAVEFORM_POINTS;
            let stretch = &pcm[start..end];
            if stretch.is_empty() {
                return 0.0;
            }
            let sum: f64 = stretch.iter().map(|s| f64::from(*s).powi(2)).sum();
            (sum / stretch.len() as f64).sqrt()
        })
        .collect();
    let loudest = rms.iter().copied().fold(0.0, f64::max);
    rms.iter()
        .map(|value| {
            if loudest < 1.0 {
                0
            } else {
                // From 0 to WAVEFORM_MAX.
                (value / loudest * f64::from(WAVEFORM_MAX)).round() as u16
            }
        })
        .collect()
}

/// The identification header (RFC 7845): version 1, one channel, the pre-skip, the
/// recorder's rate, no gain, mapping family 0.
fn opus_head(input_rate: u32) -> Vec<u8> {
    let mut head = Vec::with_capacity(19);
    head.extend_from_slice(b"OpusHead");
    head.extend_from_slice(&[1, 1]);
    head.extend_from_slice(&PRE_SKIP.to_le_bytes());
    head.extend_from_slice(&input_rate.to_le_bytes());
    head.extend_from_slice(&0_i16.to_le_bytes());
    head.push(0);
    head
}

/// The comment header: the vendor, no comments.
fn opus_tags() -> Vec<u8> {
    let vendor = b"OxiTalk";
    let mut tags = Vec::new();
    tags.extend_from_slice(b"OpusTags");
    tags.extend_from_slice(&7_u32.to_le_bytes());
    tags.extend_from_slice(vendor);
    tags.extend_from_slice(&0_u32.to_le_bytes());
    tags
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `seconds` of a gliding tone that swells and fades, as interleaved samples.
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_precision_loss,
        clippy::cast_sign_loss
    )]
    fn tone(rate: u32, channels: usize, seconds: f64) -> Vec<i16> {
        let count = (f64::from(rate) * seconds) as usize;
        let mut pcm = Vec::with_capacity(count * channels);
        for index in 0..count {
            let t = index as f64 / f64::from(rate);
            let envelope = (t / seconds * std::f64::consts::PI).sin();
            let sample = (std::f64::consts::TAU * (220.0 + 100.0 * t) * t).sin() * envelope;
            pcm.extend(std::iter::repeat_n((sample * 12_000.0) as i16, channels));
        }
        pcm
    }

    #[test]
    fn a_recording_becomes_ogg_opus_and_plays_back_as_long() -> Result<(), CoreError> {
        let clip = encode_voice(tone(44_100, 2, 3.0), 44_100, 2)?;
        assert!(clip.data.starts_with(b"OggS"));
        assert_eq!(&clip.data[28..36], b"OpusHead");
        assert_eq!(clip.duration_ms, 3000);
        // Small: about 24 kb/s.
        assert!(clip.data.len() < 16_000, "{} bytes", clip.data.len());
        let wav = playable_wav(clip.data).ok_or_else(|| CoreError::internal(&"not decoded"))?;
        assert!(wav.starts_with(b"RIFF"));
        assert_eq!(samples_to_ms((wav.len() - WAV_HEADER) / 2), 3000);
        Ok(())
    }

    #[test]
    fn the_waveform_follows_the_loudness() -> Result<(), CoreError> {
        let clip = encode_voice(tone(48_000, 1, 2.0), 48_000, 1)?;
        assert_eq!(clip.waveform.len(), WAVEFORM_POINTS);
        let middle = clip.waveform[50];
        assert!(middle > 900, "{middle}");
        assert!(clip.waveform[0] < 100 && clip.waveform[99] < 100);
        assert_eq!(clip.waveform.iter().max(), Some(&WAVEFORM_MAX));
        let silence = encode_voice(vec![0; 4_800], 48_000, 1)?;
        assert!(silence.waveform.iter().all(|point| *point == 0));
        assert_eq!(silence.duration_ms, 100);
        Ok(())
    }

    #[test]
    fn other_files_are_left_to_the_platform() {
        assert_eq!(playable_wav(b"ID3 an mp3".to_vec()), None);
        assert_eq!(playable_wav(Vec::new()), None);
        let wav = wav(&[1, 2, 3], RATE);
        assert_eq!(playable_wav(wav.clone()), Some(wav));
        assert!(encode_voice(vec![1, 2], 0, 1).is_err());
    }
}
