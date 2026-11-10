// A WhatsApp voice note is OGG/Opus, which Apple's players (AVPlayer, under
// `audioplayers` on macOS and iOS) cannot decode. The original stays the
// record, and a small WAV twin is stored next to it for playback. The message
// metadata points to the twin (`playback_storage_path`).
//
// Every path that stores an inbound file makes the twin through here:
// - the webhook, which stores each file on arrival;
// - whatsapp-media, which stores a file when a client asks for it first, and
//   makes the twin of a stored note that has none.
// Until 2026-11-09 only whatsapp-media made it. The webhook stores nearly
// every file first, so no voice note had a twin (0 of 3 since August) and the
// Mac could play none of them.
//
// The decoder is loaded only when a voice note arrives. A failure to load it
// costs the twin, never the webhook that imports this module.

export const VOICE_NOTE_CONTENT_TYPE = "audio/ogg";
export const VOICE_NOTE_PLAYBACK_CONTENT_TYPE = "audio/wav";

export type VoiceNoteTwinMetadata = {
  playback_storage_path: string;
  playback_content_type: string;
};

export type TwinStorage = {
  from(bucket: string): {
    upload(
      path: string,
      body: Blob,
      options: { contentType: string; upsert: boolean },
    ): Promise<{ error: unknown }>;
  };
};

export type Transcode = (input: Uint8Array) => Promise<Uint8Array | null>;

async function loadAndTranscode(input: Uint8Array): Promise<Uint8Array | null> {
  const { transcodeOpusToWav } = await import("./voice_note_transcode.ts");
  return transcodeOpusToWav(input);
}

export function isVoiceNoteContentType(contentType: string | null | undefined): boolean {
  return (contentType ?? "").split(";")[0].trim().toLowerCase() === VOICE_NOTE_CONTENT_TYPE;
}

export function playbackPathFor(storagePath: string): string {
  return `${storagePath}.wav`;
}

/** Stores the WAV twin of a voice note and returns the metadata that points
 * to it. Returns `null` when the file is not a voice note or the twin could
 * not be made. Never throws: by then the note itself is already stored. */
export async function storeVoiceNotePlaybackTwin(params: {
  storage: TwinStorage;
  bucket: string;
  storagePath: string;
  contentType: string;
  bytes: Uint8Array;
  transcode?: Transcode;
}): Promise<VoiceNoteTwinMetadata | null> {
  if (!isVoiceNoteContentType(params.contentType)) return null;
  try {
    const wav = await (params.transcode ?? loadAndTranscode)(params.bytes);
    if (!wav) return null;
    const playbackPath = playbackPathFor(params.storagePath);
    const { error } = await params.storage.from(params.bucket).upload(
      playbackPath,
      new Blob([wav.slice().buffer as ArrayBuffer], {
        type: VOICE_NOTE_PLAYBACK_CONTENT_TYPE,
      }),
      { contentType: VOICE_NOTE_PLAYBACK_CONTENT_TYPE, upsert: true },
    );
    if (error) {
      console.error("❌ [VOICE-NOTE] Playback twin upload failed", error);
      return null;
    }
    return {
      playback_storage_path: playbackPath,
      playback_content_type: VOICE_NOTE_PLAYBACK_CONTENT_TYPE,
    };
  } catch (error) {
    console.error("❌ [VOICE-NOTE] Playback twin unavailable", error);
    return null;
  }
}
