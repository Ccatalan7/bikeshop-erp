import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// The Supabase edge runtime has no Web Workers. ogg-opus-decoder's bundle
// reads the global `Worker` while it loads, so in production the import threw
// «Worker is not defined» and every request to whatsapp-media failed with
// WORKER_ERROR, OPTIONS included (2026-11-09). Local Deno does have `Worker`,
// so the test removes it before loading the module the way the edge runtime
// would see it. The import must be dynamic: a static one would be evaluated
// before the global is removed.
Deno.test("voice note transcoder loads without a Worker global", async () => {
  const globals = globalThis as Record<string, unknown>;
  const original = globals.Worker;
  delete globals.Worker;
  try {
    assertEquals(typeof globals.Worker, "undefined");
    const transcoder = await import("./voice_note_transcode.ts");
    assertEquals(transcoder.VOICE_NOTE_PLAYBACK_CONTENT_TYPE, "audio/wav");
    // Bytes that are not an Ogg/Opus stream give no playback twin instead of
    // throwing, so the original voice note is still served.
    assertEquals(
      await transcoder.transcodeOpusToWav(new TextEncoder().encode("not an ogg stream")),
      null,
    );
  } finally {
    globals.Worker = original;
  }
});
