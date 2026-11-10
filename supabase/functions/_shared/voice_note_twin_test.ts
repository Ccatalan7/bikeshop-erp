import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  playbackPathFor,
  storeVoiceNotePlaybackTwin,
  type TwinStorage,
  VOICE_NOTE_PLAYBACK_CONTENT_TYPE,
} from "./voice_note_twin.ts";

type Upload = { bucket: string; path: string; type: string; upsert: boolean; size: number };

function recordingStorage(error: unknown = null) {
  const uploads: Upload[] = [];
  const storage: TwinStorage = {
    from(bucket) {
      return {
        upload(path, body, options) {
          uploads.push({
            bucket,
            path,
            type: options.contentType,
            upsert: options.upsert,
            size: body.size,
          });
          return Promise.resolve({ error });
        },
      };
    },
  };
  return { storage, uploads };
}

const NOTE_PATH = "tenant/conversation/attachment.ogg";
const WAV = new Uint8Array([82, 73, 70, 70]);

Deno.test("a voice note gets its twin next to the original", async () => {
  const { storage, uploads } = recordingStorage();
  const twin = await storeVoiceNotePlaybackTwin({
    storage,
    bucket: "private",
    storagePath: NOTE_PATH,
    contentType: "audio/ogg; codecs=opus",
    bytes: new Uint8Array([1, 2, 3]),
    transcode: () => Promise.resolve(WAV),
  });
  assertEquals(twin, {
    playback_storage_path: `${NOTE_PATH}.wav`,
    playback_content_type: VOICE_NOTE_PLAYBACK_CONTENT_TYPE,
  });
  assertEquals(uploads, [{
    bucket: "private",
    path: playbackPathFor(NOTE_PATH),
    type: "audio/wav",
    upsert: true,
    size: WAV.byteLength,
  }]);
});

Deno.test("only voice notes get a twin", async () => {
  const { storage, uploads } = recordingStorage();
  let transcoded = false;
  const twin = await storeVoiceNotePlaybackTwin({
    storage,
    bucket: "private",
    storagePath: "tenant/conversation/photo.jpg",
    contentType: "image/jpeg",
    bytes: new Uint8Array([1]),
    transcode: () => {
      transcoded = true;
      return Promise.resolve(WAV);
    },
  });
  assertEquals(twin, null);
  assertEquals(transcoded, false);
  assertEquals(uploads.length, 0);
});

// The webhook caps what it decodes inline, to stay inside the request's CPU
// budget. A longer note is left for whatsapp-media to twin when played.
Deno.test("a note over the cap is left for playback", async () => {
  const { storage, uploads } = recordingStorage();
  let transcoded = false;
  const twin = await storeVoiceNotePlaybackTwin({
    storage,
    bucket: "private",
    storagePath: NOTE_PATH,
    contentType: "audio/ogg",
    bytes: new Uint8Array(11),
    maxBytes: 10,
    transcode: () => {
      transcoded = true;
      return Promise.resolve(WAV);
    },
  });
  assertEquals(twin, null);
  assertEquals(transcoded, false);
  assertEquals(uploads.length, 0);
});

// The note is already stored when the twin is made: losing the twin must
// never fail the webhook or the media request that stored it.
Deno.test("a twin that cannot be made costs only the twin", async () => {
  for (
    const [label, transcode, uploadError] of [
      ["undecodable", () => Promise.resolve(null), null],
      ["decoder throws", () => Promise.reject(new Error("boom")), null],
      ["upload fails", () => Promise.resolve(WAV), new Error("storage down")],
    ] as const
  ) {
    const { storage } = recordingStorage(uploadError);
    const twin = await storeVoiceNotePlaybackTwin({
      storage,
      bucket: "private",
      storagePath: NOTE_PATH,
      contentType: "audio/ogg",
      bytes: new Uint8Array([1]),
      transcode,
    });
    assertEquals(twin, null, label);
  }
});

// Both functions that store an inbound file must make the twin. Until
// 2026-11-09 the webhook stored nearly every file and never made it, so no
// voice note could play on the Mac. A third storage path must not repeat it.
Deno.test("every function that stores a messaging file makes the twin", async () => {
  const functionsRoot = new URL("../", import.meta.url);
  const storing: string[] = [];
  const missing: string[] = [];
  for await (const entry of Deno.readDir(functionsRoot)) {
    if (!entry.isDirectory || entry.name.startsWith("_")) continue;
    let source: string;
    try {
      source = await Deno.readTextFile(new URL(`${entry.name}/index.ts`, functionsRoot));
    } catch {
      continue;
    }
    if (!source.includes("buildPrivateMessagingAttachmentPath(")) continue;
    storing.push(entry.name);
    if (!source.includes("storeVoiceNotePlaybackTwin(")) missing.push(entry.name);
  }
  assert(storing.includes("whatsapp-webhook"), "the webhook stores inbound files");
  assert(storing.includes("whatsapp-media"), "whatsapp-media stores inbound files");
  assertEquals(missing, [], "make the twin with storeVoiceNotePlaybackTwin");
});

// One second of Opus silence in an Ogg stream, built here so the test needs no
// audio file: an OpusHead page, an OpusTags page and 50 packets of 20 ms that
// carry only their TOC byte (a frame the decoder renders as silence).
function oggOpusSilence(): Uint8Array {
  const crcTable = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let r = i << 24;
    for (let j = 0; j < 8; j++) r = r & 0x80000000 ? (r << 1) ^ 0x04c11db7 : r << 1;
    crcTable[i] = r >>> 0;
  }
  const pages: Uint8Array[] = [];
  const page = (packets: Uint8Array[], headerType: number, granule: number, sequence: number) => {
    const lacing: number[] = [];
    for (const packet of packets) {
      let remaining = packet.byteLength;
      while (remaining >= 255) {
        lacing.push(255);
        remaining -= 255;
      }
      lacing.push(remaining);
    }
    const payloadLength = packets.reduce((sum, packet) => sum + packet.byteLength, 0);
    const bytes = new Uint8Array(27 + lacing.length + payloadLength);
    const view = new DataView(bytes.buffer);
    bytes.set([0x4f, 0x67, 0x67, 0x53], 0);
    bytes[5] = headerType;
    view.setBigUint64(6, BigInt(granule), true);
    view.setUint32(14, 0x5643454e, true);
    view.setUint32(18, sequence, true);
    bytes[26] = lacing.length;
    bytes.set(lacing, 27);
    let offset = 27 + lacing.length;
    for (const packet of packets) {
      bytes.set(packet, offset);
      offset += packet.byteLength;
    }
    let crc = 0;
    for (const byte of bytes) crc = ((crc << 8) ^ crcTable[((crc >>> 24) ^ byte) & 0xff]) >>> 0;
    view.setUint32(22, crc, true);
    pages.push(bytes);
  };
  const text = (value: string) => new TextEncoder().encode(value);
  const head = new Uint8Array(19);
  head.set(text("OpusHead"), 0);
  head[8] = 1; // version
  head[9] = 1; // mono
  new DataView(head.buffer).setUint16(10, 312, true); // pre-skip
  new DataView(head.buffer).setUint32(12, 48000, true);
  page([head], 0x02, 0, 0);
  const vendor = text("vinabike-test");
  const tags = new Uint8Array(8 + 4 + vendor.byteLength + 4);
  tags.set(text("OpusTags"), 0);
  new DataView(tags.buffer).setUint32(8, vendor.byteLength, true);
  tags.set(vendor, 12);
  page([tags], 0x00, 0, 1);
  const silence = Array.from({ length: 50 }, () => new Uint8Array([0xf8]));
  page(silence, 0x04, 50 * 960, 2);
  const total = pages.reduce((sum, bytes) => sum + bytes.byteLength, 0);
  const stream = new Uint8Array(total);
  let offset = 0;
  for (const bytes of pages) {
    stream.set(bytes, offset);
    offset += bytes.byteLength;
  }
  return stream;
}

// The real decoder, loaded the way the edge runtime loads it: on demand and
// without a `Worker` global (see voice_note_transcode_test.ts).
Deno.test("a real Ogg/Opus note becomes a 16 kHz mono WAV twin", async () => {
  const globals = globalThis as Record<string, unknown>;
  const original = globals.Worker;
  delete globals.Worker;
  try {
    const { storage, uploads } = recordingStorage();
    let wav: Uint8Array | null = null;
    const twin = await storeVoiceNotePlaybackTwin({
      storage: {
        from(bucket) {
          const target = storage.from(bucket);
          return {
            async upload(path, body, options) {
              wav = new Uint8Array(await body.arrayBuffer());
              return target.upload(path, body, options);
            },
          };
        },
      },
      bucket: "private",
      storagePath: NOTE_PATH,
      contentType: "audio/ogg",
      bytes: oggOpusSilence(),
    });
    assertEquals(twin?.playback_storage_path, `${NOTE_PATH}.wav`);
    assertEquals(uploads.length, 1);
    const bytes = wav as Uint8Array | null;
    assert(bytes, "the twin was uploaded");
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const ascii = (offset: number) => new TextDecoder().decode(bytes.subarray(offset, offset + 4));
    assertEquals(ascii(0), "RIFF");
    assertEquals(ascii(8), "WAVE");
    assertEquals(view.getUint16(22, true), 1, "mono");
    assertEquals(view.getUint32(24, true), 16000, "16 kHz");
    const seconds = view.getUint32(40, true) / 2 / 16000;
    assert(seconds > 0.9 && seconds <= 1.0, `about one second, got ${seconds}`);
  } finally {
    globals.Worker = original;
  }
});
