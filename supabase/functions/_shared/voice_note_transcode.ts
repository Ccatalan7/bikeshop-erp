// Voice notes arrive from WhatsApp as OGG/Opus. Apple's players cannot decode
// that container, so the media function keeps the original for the record
// and stores a WAV twin for playback: 16 kHz, mono, 16-bit — plenty for
// speech, and a fraction of the size a full-rate WAV would be.
// The `?bundle` build inlines the decoder's dependencies. The plain module
// pulls a Web Worker shim that imports `node:vm`, which the edge bundler
// rejects; the worker is never used here anyway.
import { OggOpusDecoder } from "https://esm.sh/ogg-opus-decoder@1.6.1?bundle";

export const VOICE_NOTE_PLAYBACK_CONTENT_TYPE = "audio/wav";
export const VOICE_NOTE_PLAYBACK_SAMPLE_RATE = 16000;

/// Bytes of a 16 kHz mono 16-bit PCM WAV, or `null` when the input is not a
/// decodable Opus stream.
export async function transcodeOpusToWav(input: Uint8Array): Promise<Uint8Array | null> {
  const decoder = new OggOpusDecoder();
  try {
    await decoder.ready;
    const decoded = await decoder.decodeFile(input);
    const channels = decoded.channelData as Float32Array[];
    const sampleRate = Number(decoded.sampleRate) || 48000;
    if (!channels?.length || !channels[0]?.length) return null;
    const mono = mixToMono(channels);
    const resampled = resampleLinear(mono, sampleRate, VOICE_NOTE_PLAYBACK_SAMPLE_RATE);
    return encodeWav(resampled, VOICE_NOTE_PLAYBACK_SAMPLE_RATE);
  } catch (error) {
    console.error("❌ [VOICE-NOTE] Opus transcode failed", error);
    return null;
  } finally {
    try {
      decoder.free();
    } catch (_) {
      // Already freed or never initialised.
    }
  }
}

function mixToMono(channels: Float32Array[]): Float32Array {
  if (channels.length === 1) return channels[0];
  const length = channels[0].length;
  const mono = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    let sum = 0;
    for (const channel of channels) sum += channel[i] ?? 0;
    mono[i] = sum / channels.length;
  }
  return mono;
}

function resampleLinear(input: Float32Array, fromRate: number, toRate: number): Float32Array {
  if (fromRate === toRate) return input;
  const ratio = fromRate / toRate;
  const length = Math.max(1, Math.floor(input.length / ratio));
  const output = new Float32Array(length);
  for (let i = 0; i < length; i++) {
    const position = i * ratio;
    const index = Math.floor(position);
    const next = Math.min(index + 1, input.length - 1);
    const fraction = position - index;
    output[i] = input[index] * (1 - fraction) + input[next] * fraction;
  }
  return output;
}

function encodeWav(samples: Float32Array, sampleRate: number): Uint8Array {
  const bytesPerSample = 2;
  const dataLength = samples.length * bytesPerSample;
  const buffer = new ArrayBuffer(44 + dataLength);
  const view = new DataView(buffer);
  const writeString = (offset: number, value: string) => {
    for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i));
  };
  writeString(0, "RIFF");
  view.setUint32(4, 36 + dataLength, true);
  writeString(8, "WAVE");
  writeString(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * bytesPerSample, true);
  view.setUint16(32, bytesPerSample, true);
  view.setUint16(34, 16, true);
  writeString(36, "data");
  view.setUint32(40, dataLength, true);
  let offset = 44;
  for (let i = 0; i < samples.length; i++) {
    const clamped = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(offset, clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff, true);
    offset += bytesPerSample;
  }
  return new Uint8Array(buffer);
}
