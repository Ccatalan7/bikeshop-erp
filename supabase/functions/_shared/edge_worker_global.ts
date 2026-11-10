// ogg-opus-decoder's bundle reads the global `Worker` while it loads, to build
// the class behind its OggOpusDecoderWebWorker. The Supabase edge runtime has
// no Web Workers, so that read threw «Worker is not defined» and took down
// every request to whatsapp-media, OPTIONS included (2026-11-09). The
// main-thread OggOpusDecoder that voice notes use never starts a worker; this
// stand-in only lets the module load, and refuses loudly if anything ever
// tries to start one. It must be imported before the decoder.
const globals = globalThis as Record<string, unknown>;

if (typeof globals.Worker === "undefined") {
  class UnavailableWorker {
    constructor() {
      throw new Error("Web Workers are not available in the edge runtime");
    }
  }
  Object.defineProperty(globalThis, "Worker", {
    value: UnavailableWorker,
    configurable: true,
    writable: true,
  });
}

export {};
