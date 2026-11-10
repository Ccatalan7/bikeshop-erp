import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  metaMediaSourcesFromGraph,
  metaMediaSourcesFromWebhook,
  trustedMetaMediaUrl,
} from "./meta_media_sources.ts";

const IG_PHOTO = "https://lookaside.fbsbx.com/ig_messaging_cdn/?asset_id=1&signature=abc";

Deno.test("a file is fetched only over HTTPS from Meta's own hosts", () => {
  assertEquals(trustedMetaMediaUrl(IG_PHOTO), IG_PHOTO);
  assertEquals(
    trustedMetaMediaUrl("https://scontent.xx.fbcdn.net/v/t1/photo.jpg?oh=1"),
    "https://scontent.xx.fbcdn.net/v/t1/photo.jpg?oh=1",
  );
  assertEquals(
    trustedMetaMediaUrl("https://scontent.cdninstagram.com/v/photo.jpg"),
    "https://scontent.cdninstagram.com/v/photo.jpg",
  );
  for (
    const refused of [
      "http://lookaside.fbsbx.com/ig_messaging_cdn/?asset_id=1",
      "https://cdn.example/private-photo.jpg?access_token=secret",
      // A trusted name as a label of somebody else's host.
      "https://lookaside.fbsbx.com.attacker.example/photo.jpg",
      "https://notfbcdn.net/photo.jpg",
      "https://user:pass@lookaside.fbsbx.com/photo.jpg",
      "https://lookaside.fbsbx.com:8443/photo.jpg",
      // The project's own services and the machine itself.
      "https://localhost/photo.jpg",
      "https://169.254.169.254/latest/meta-data",
      "file:///etc/passwd",
      "not a url",
      "",
      null,
      7,
      `https://lookaside.fbsbx.com/${"a".repeat(5_000)}`,
    ]
  ) {
    assertEquals(trustedMetaMediaUrl(refused), null, String(refused).slice(0, 60));
  }
});

Deno.test("a webhook message names its storable files in order", () => {
  assertEquals(
    metaMediaSourcesFromWebhook([
      { type: "image", payload: { url: IG_PHOTO } },
      { type: "VIDEO", payload: { url: "https://video.xx.fbcdn.net/v/clip.mp4" } },
      { type: "audio", payload: { url: "https://cdn.fbsbx.com/v/voice.mp4" } },
      { type: "file", payload: { url: "https://cdn.fbsbx.com/v/boleta.pdf" } },
    ]),
    [
      { kind: "image", url: IG_PHOTO },
      { kind: "video", url: "https://video.xx.fbcdn.net/v/clip.mp4" },
      { kind: "audio", url: "https://cdn.fbsbx.com/v/voice.mp4" },
      { kind: "file", url: "https://cdn.fbsbx.com/v/boleta.pdf" },
    ],
  );
});

// A story, a reel, a shared post or a view-once photo is not a file the ERP
// keeps: it stays the text placeholder.
Deno.test("what is not a file, or not on Meta's hosts, is not a source", () => {
  assertEquals(
    metaMediaSourcesFromWebhook([
      { type: "story_mention", payload: { url: IG_PHOTO } },
      { type: "ig_reel", payload: { url: IG_PHOTO, title: "Reel" } },
      { type: "share", payload: { url: IG_PHOTO } },
      { type: "ephemeral" },
      { type: "image", payload: { url: "https://cdn.example/photo.jpg" } },
      { type: "image", payload: {} },
      { type: "image" },
      "image",
      null,
    ]),
    [],
  );
  assertEquals(metaMediaSourcesFromWebhook(undefined), []);
  assertEquals(metaMediaSourcesFromWebhook({ type: "image" }), []);
});

Deno.test("a message read back from Meta names its files", () => {
  assertEquals(
    metaMediaSourcesFromGraph({
      id: "mid-1",
      attachments: {
        data: [
          { image_data: { url: IG_PHOTO, preview_url: IG_PHOTO, width: 1080, height: 1350 } },
          { video_data: { url: "https://video.xx.fbcdn.net/v/clip.mp4" } },
          { file_url: "https://cdn.fbsbx.com/v/voice.mp4", mime_type: "audio/mp4" },
          { file_url: "https://cdn.fbsbx.com/v/boleta.pdf", mime_type: "application/pdf" },
          { file_url: "https://cdn.fbsbx.com/v/desconocido" },
        ],
      },
    }),
    [
      { kind: "image", url: IG_PHOTO },
      { kind: "video", url: "https://video.xx.fbcdn.net/v/clip.mp4" },
      { kind: "audio", url: "https://cdn.fbsbx.com/v/voice.mp4" },
      { kind: "file", url: "https://cdn.fbsbx.com/v/boleta.pdf" },
      { kind: "file", url: "https://cdn.fbsbx.com/v/desconocido" },
    ],
  );
});

Deno.test("a message without files, or with files elsewhere, names none", () => {
  for (
    const message of [
      null,
      {},
      { id: "mid-1", message: "Hola" },
      { attachments: {} },
      { attachments: { data: "x" } },
      { attachments: { data: [{}, null, { image_data: {} }] } },
      { attachments: { data: [{ image_data: { url: "https://cdn.example/photo.jpg" } }] } },
    ]
  ) {
    assertEquals(metaMediaSourcesFromGraph(message), [], JSON.stringify(message));
  }
});
