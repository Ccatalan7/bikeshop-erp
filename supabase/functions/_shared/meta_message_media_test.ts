import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  fetchMetaMessageMediaSources,
  hydrateFreshMetaMessageMedia,
  metaMessageMediaUrl,
  resolveDueMetaMessageMedia,
  sniffContentType,
  storedContentType,
  storeMetaMessageMedia,
} from "./meta_message_media.ts";

type Call = { name: string; args: Record<string, unknown> };
type Upload = { bucket: string; path: string; type: string; upsert: boolean; size: number };

function fakeClient(
  responses: Record<string, unknown>,
  options: { failing?: string[]; uploadError?: unknown } = {},
) {
  const calls: Call[] = [];
  const uploads: Upload[] = [];
  const removed: string[] = [];
  return {
    calls,
    uploads,
    removed,
    client: {
      rpc(name: string, args: Record<string, unknown>) {
        calls.push({ name, args });
        return Promise.resolve(
          options.failing?.includes(name)
            ? { data: null, error: { code: "23514" } }
            : { data: name in responses ? responses[name] : {}, error: null },
        );
      },
      storage: {
        from(bucket: string) {
          return {
            upload(
              path: string,
              body: Blob,
              uploadOptions: { contentType: string; upsert: boolean },
            ) {
              uploads.push({
                bucket,
                path,
                type: uploadOptions.contentType,
                upsert: uploadOptions.upsert,
                size: body.size,
              });
              return Promise.resolve({ error: options.uploadError ?? null });
            },
            remove(paths: string[]) {
              removed.push(...paths);
              return Promise.resolve({ error: null });
            },
          };
        },
      },
    },
  };
}

type Answer = { status?: number; body?: BodyInit | null; headers?: Record<string, string> };

function network(answers: Record<string, Answer | (() => Promise<Response>)>) {
  const requests: { url: string; authorization: string | null; redirect: string | undefined }[] =
    [];
  const fetchImpl = (url: string, init?: RequestInit) => {
    requests.push({
      url,
      authorization: new Headers(init?.headers).get("authorization"),
      redirect: init?.redirect,
    });
    const answer = answers[url];
    if (typeof answer === "function") return answer();
    return Promise.resolve(
      answer
        ? new Response(answer.body ?? null, {
          status: answer.status ?? 200,
          headers: answer.headers,
        })
        : new Response("{}", { status: 404 }),
    );
  };
  return { requests, fetchImpl };
}

const MESSAGE = {
  messageId: "11111111-1111-4111-8111-111111111111",
  tenantId: "22222222-2222-4222-8222-222222222222",
  conversationId: "33333333-3333-4333-8333-333333333333",
  externalMessageId: "mid-photo",
  mediaType: "image",
};
const CLAIM_ITEM = {
  message_id: MESSAGE.messageId,
  tenant_id: MESSAGE.tenantId,
  conversation_id: MESSAGE.conversationId,
  external_message_id: MESSAGE.externalMessageId,
  media_type: "image",
};
const PHOTO_URL = "https://lookaside.fbsbx.com/ig_messaging_cdn/?asset_id=1&signature=s";
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70]);
const MP4 = new Uint8Array([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x6d, 0x70, 0x34, 0x32]);
const PATH = new RegExp(
  `^${MESSAGE.tenantId}/${MESSAGE.conversationId}/[0-9a-f-]{36}\\.jpg$`,
);

Deno.test("the bytes say what a file is", () => {
  assertEquals(sniffContentType(JPEG), "image/jpeg");
  assertEquals(
    sniffContentType(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
    "image/png",
  );
  assertEquals(sniffContentType(new TextEncoder().encode("GIF89a")), "image/gif");
  assertEquals(sniffContentType(new TextEncoder().encode("RIFF0000WEBPVP8 ")), "image/webp");
  assertEquals(sniffContentType(new TextEncoder().encode("%PDF-1.7")), "application/pdf");
  assertEquals(sniffContentType(new TextEncoder().encode("OggS")), "audio/ogg");
  assertEquals(sniffContentType(MP4), "video/mp4");
  assertEquals(sniffContentType(new TextEncoder().encode("<html>")), null);
  assertEquals(sniffContentType(new Uint8Array()), null);
});

Deno.test("the stored type follows the bytes, not the header of the CDN", () => {
  // Meta's CDN often answers a photo as a generic download.
  assertEquals(storedContentType("image", "application/octet-stream", JPEG), "image/jpeg");
  assertEquals(storedContentType("image", null, JPEG), "image/jpeg");
  assertEquals(storedContentType("image", "image/png", JPEG), "image/jpeg");
  // A voice message and a video share the MP4 container.
  assertEquals(storedContentType("audio", "video/mp4", MP4), "audio/mp4");
  assertEquals(storedContentType("video", "video/mp4", MP4), "video/mp4");
  assertEquals(storedContentType("file", "audio/mp4", MP4), "audio/mp4");
  assertEquals(storedContentType("video", "video/3gpp", MP4), "video/3gpp");
  // What the bytes do not say is left to the header.
  assertEquals(
    storedContentType("file", "text/plain; charset=utf-8", new TextEncoder().encode("hola")),
    "text/plain",
  );
});

Deno.test("a photo is downloaded, stored privately and attached to its message", async () => {
  const { client, calls, uploads, removed } = fakeClient({
    attach_meta_message_media: { attached: true },
  });
  const { requests, fetchImpl } = network({
    [PHOTO_URL]: { body: JPEG, headers: { "content-type": "application/octet-stream" } },
  });
  const outcome = await storeMetaMessageMedia({
    client,
    message: MESSAGE,
    source: { kind: "image", url: PHOTO_URL },
    fetchImpl,
  });
  assertEquals(outcome, { ok: true });
  assertEquals(uploads.length, 1);
  assertEquals(uploads[0].bucket, "chat-attachments");
  assert(PATH.test(uploads[0].path), uploads[0].path);
  assertEquals(uploads[0].type, "image/jpeg");
  assertEquals(uploads[0].upsert, false);
  assertEquals(uploads[0].size, JPEG.byteLength);
  const attachmentId = uploads[0].path.split("/")[2].replace(".jpg", "");
  assertEquals(calls, [{
    name: "attach_meta_message_media",
    args: {
      p_message_id: MESSAGE.messageId,
      p_attachment_id: attachmentId,
      p_original_filename: "imagen.jpg",
      p_extension: "jpg",
      p_declared_mime_type: "image/jpeg",
      p_size_bytes: JPEG.byteLength,
      p_has_playback_twin: false,
      p_more_files: 0,
    },
  }]);
  assertEquals(removed, []);
  // The Page token never travels to the CDN, and redirects are not followed
  // blindly.
  assertEquals(requests, [{ url: PHOTO_URL, authorization: null, redirect: "manual" }]);
});

Deno.test("a redirect is followed only to another of Meta's hosts", async () => {
  const onward = "https://scontent.xx.fbcdn.net/v/t1/photo.jpg?oh=1";
  const allowed = fakeClient({ attach_meta_message_media: { attached: true } });
  const followed = network({
    [PHOTO_URL]: { status: 302, headers: { location: onward } },
    [onward]: { body: JPEG, headers: { "content-type": "image/jpeg" } },
  });
  assertEquals(
    await storeMetaMessageMedia({
      client: allowed.client,
      message: MESSAGE,
      source: { kind: "image", url: PHOTO_URL },
      fetchImpl: followed.fetchImpl,
    }),
    { ok: true },
  );
  assertEquals(followed.requests.map((request) => request.url), [PHOTO_URL, onward]);

  for (
    const location of [
      "https://attacker.example/photo.jpg",
      "http://169.254.169.254/latest/meta-data",
      "https://localhost/photo.jpg",
    ]
  ) {
    const refused = fakeClient({});
    const escaped = network({
      [PHOTO_URL]: { status: 302, headers: { location } },
      [location]: { body: JPEG, headers: { "content-type": "image/jpeg" } },
    });
    assertEquals(
      await storeMetaMessageMedia({
        client: refused.client,
        message: MESSAGE,
        source: { kind: "image", url: PHOTO_URL },
        fetchImpl: escaped.fetchImpl,
      }),
      { ok: false, error: "untrusted_media_host", retrySoon: false },
      location,
    );
    assertEquals(escaped.requests.map((request) => request.url), [PHOTO_URL]);
    assertEquals(refused.uploads.length, 0);
    assertEquals(refused.calls.length, 0);
  }
});

Deno.test("a source that is not on Meta's hosts is never fetched", async () => {
  const { client, uploads } = fakeClient({});
  const { requests, fetchImpl } = network({});
  assertEquals(
    await storeMetaMessageMedia({
      client,
      message: MESSAGE,
      source: { kind: "image", url: "https://cdn.example/photo.jpg" },
      fetchImpl,
    }),
    { ok: false, error: "untrusted_media_host", retrySoon: false },
  );
  assertEquals(requests.length, 0);
  assertEquals(uploads.length, 0);
});

Deno.test("what cannot be stored is refused before anything is uploaded", async () => {
  const cases: [string, Answer, string, boolean][] = [
    ["an expired URL", { status: 403 }, "download_403", false],
    ["an outage", { status: 503 }, "download_503", true],
    ["a rate limit", { status: 429 }, "download_429", true],
    [
      "a page instead of a file",
      { body: "<html>login</html>", headers: { "content-type": "text/html" } },
      "unsupported_attachment_type",
      false,
    ],
    [
      "a declared size over the cap",
      { body: JPEG, headers: { "content-type": "image/jpeg", "content-length": "99999999" } },
      "attachment_too_large",
      false,
    ],
    [
      "an empty answer",
      { body: null, headers: { "content-type": "image/jpeg" } },
      "invalid_attachment_size",
      false,
    ],
  ];
  for (const [label, answer, error, retrySoon] of cases) {
    const { client, calls, uploads } = fakeClient({});
    const { fetchImpl } = network({ [PHOTO_URL]: answer });
    assertEquals(
      await storeMetaMessageMedia({
        client,
        message: MESSAGE,
        source: { kind: "image", url: PHOTO_URL },
        fetchImpl,
      }),
      { ok: false, error, retrySoon },
      label,
    );
    assertEquals(uploads.length, 0, label);
    assertEquals(calls.length, 0, label);
  }
});

Deno.test("a photo larger than a photo may be is cut off while it downloads", async () => {
  const { client, uploads } = fakeClient({});
  const chunk = new Uint8Array(1024 * 1024).fill(0xff);
  let sent = 0;
  const { fetchImpl } = network({
    [PHOTO_URL]: () =>
      Promise.resolve(
        new Response(
          new ReadableStream<Uint8Array>({
            pull(controller) {
              sent += 1;
              // No content-length: the reader has to stop on its own.
              if (sent > 64) controller.close();
              else controller.enqueue(chunk);
            },
          }),
          { headers: { "content-type": "image/jpeg" } },
        ),
      ),
  });
  assertEquals(
    await storeMetaMessageMedia({
      client,
      message: MESSAGE,
      source: { kind: "image", url: PHOTO_URL },
      fetchImpl,
    }),
    { ok: false, error: "attachment_too_large", retrySoon: false },
  );
  assert(sent <= 8, `stopped after ${sent} MiB, not the whole file`);
  assertEquals(uploads.length, 0);
});

Deno.test("a network failure is retried soon", async () => {
  const { client } = fakeClient({});
  assertEquals(
    await storeMetaMessageMedia({
      client,
      message: MESSAGE,
      source: { kind: "image", url: PHOTO_URL },
      fetchImpl: () => Promise.reject(new Error("offline")),
    }),
    { ok: false, error: "download_network", retrySoon: true },
  );
});

Deno.test("a file the database does not attach is not left in storage", async () => {
  const refused = fakeClient({}, { failing: ["attach_meta_message_media"] });
  const { fetchImpl } = network({
    [PHOTO_URL]: { body: JPEG, headers: { "content-type": "image/jpeg" } },
  });
  assertEquals(
    await storeMetaMessageMedia({
      client: refused.client,
      message: MESSAGE,
      source: { kind: "image", url: PHOTO_URL },
      fetchImpl,
    }),
    { ok: false, error: "attach_23514", retrySoon: false },
  );
  assertEquals(refused.removed, [refused.uploads[0].path]);

  // Another run attached its copy first: this one is discarded, and the
  // message has its file all the same.
  const raced = fakeClient({
    attach_meta_message_media: { attached: false, reason: "already_attached" },
  });
  assertEquals(
    await storeMetaMessageMedia({
      client: raced.client,
      message: MESSAGE,
      source: { kind: "image", url: PHOTO_URL },
      fetchImpl,
    }),
    { ok: true },
  );
  assertEquals(raced.removed, [raced.uploads[0].path]);

  const noStorage = fakeClient({}, { uploadError: new Error("storage down") });
  assertEquals(
    await storeMetaMessageMedia({
      client: noStorage.client,
      message: MESSAGE,
      source: { kind: "image", url: PHOTO_URL },
      fetchImpl,
    }),
    { ok: false, error: "storage_upload_failed", retrySoon: true },
  );
  assertEquals(noStorage.calls.length, 0);
});

Deno.test("a voice message is stored as sound and a video as video", async () => {
  const voiceUrl = "https://cdn.fbsbx.com/v/voice.mp4";
  for (
    const [kind, filename, type] of [
      ["audio", "audio.m4a", "audio/mp4"],
      ["video", "video.mp4", "video/mp4"],
    ] as const
  ) {
    const { client, calls, uploads } = fakeClient({
      attach_meta_message_media: { attached: true },
    });
    const { fetchImpl } = network({
      [voiceUrl]: { body: MP4, headers: { "content-type": "video/mp4" } },
    });
    assertEquals(
      await storeMetaMessageMedia({
        client,
        message: MESSAGE,
        source: { kind, url: voiceUrl },
        moreFiles: 2,
        fetchImpl,
      }),
      { ok: true },
    );
    assertEquals(uploads[0].type, type);
    assertEquals(calls[0].args.p_original_filename, filename);
    assertEquals(calls[0].args.p_declared_mime_type, type);
    // Meta sent three files in the message: the bubble will say so.
    assertEquals(calls[0].args.p_more_files, 2);
  }
});

Deno.test("the webhook stores the file of the message it just received", async () => {
  const { client, calls, uploads } = fakeClient({
    claim_meta_message_media: CLAIM_ITEM,
    attach_meta_message_media: { attached: true },
  });
  const { fetchImpl } = network({
    [PHOTO_URL]: { body: JPEG, headers: { "content-type": "image/jpeg" } },
  });
  const outcome = await hydrateFreshMetaMessageMedia({
    client,
    messageId: MESSAGE.messageId,
    sources: [
      { kind: "image", url: PHOTO_URL },
      { kind: "image", url: "https://lookaside.fbsbx.com/ig_messaging_cdn/?asset_id=2" },
    ],
    fetchImpl,
  });
  assertEquals(outcome, "attached");
  assertEquals(calls.map((call) => call.name), [
    "claim_meta_message_media",
    "attach_meta_message_media",
  ]);
  assertEquals(calls[0].args, { p_message_id: MESSAGE.messageId });
  assertEquals(calls[1].args.p_more_files, 1);
  assertEquals(uploads.length, 1);
});

Deno.test("a message somebody else holds, or without a usable URL, is left alone", async () => {
  const held = fakeClient({ claim_meta_message_media: null });
  const { requests, fetchImpl } = network({});
  assertEquals(
    await hydrateFreshMetaMessageMedia({
      client: held.client,
      messageId: MESSAGE.messageId,
      sources: [{ kind: "image", url: PHOTO_URL }],
      fetchImpl,
    }),
    "not_due",
  );
  assertEquals(requests.length, 0);

  // Nobody is claimed, so the sweep can ask Meta for the file.
  const noSource = fakeClient({});
  assertEquals(
    await hydrateFreshMetaMessageMedia({
      client: noSource.client,
      messageId: MESSAGE.messageId,
      sources: [],
      fetchImpl,
    }),
    "no_source",
  );
  assertEquals(noSource.calls.length, 0);
});

// The URL of the event is good for minutes. When it fails, the sweep asks
// Meta for a fresh one on its next run instead of waiting a day.
Deno.test("a download the webhook could not finish is handed to the sweep", async () => {
  const { client, calls } = fakeClient({ claim_meta_message_media: CLAIM_ITEM });
  const { fetchImpl } = network({ [PHOTO_URL]: { status: 403 } });
  assertEquals(
    await hydrateFreshMetaMessageMedia({
      client,
      messageId: MESSAGE.messageId,
      sources: [{ kind: "image", url: PHOTO_URL }],
      fetchImpl,
    }),
    "download_403",
  );
  assertEquals(calls.at(-1), {
    name: "fail_meta_message_media",
    args: { p_message_id: MESSAGE.messageId, p_error: "download_403", p_retry_soon: true },
  });
});

Deno.test("a file the ERP does not keep is not handed to the sweep at once", async () => {
  const { client, calls } = fakeClient({ claim_meta_message_media: CLAIM_ITEM });
  const { fetchImpl } = network({
    [PHOTO_URL]: { body: "<html>", headers: { "content-type": "text/html" } },
  });
  assertEquals(
    await hydrateFreshMetaMessageMedia({
      client,
      messageId: MESSAGE.messageId,
      sources: [{ kind: "image", url: PHOTO_URL }],
      fetchImpl,
    }),
    "unsupported_attachment_type",
  );
  assertEquals(calls.at(-1)?.args.p_retry_soon, false);
});

Deno.test("Meta is asked for a stored message by its id, with the token in the header", async () => {
  assertEquals(
    metaMessageMediaUrl("v25.0", "aWdfZAG1/mid=="),
    "https://graph.facebook.com/v25.0/aWdfZAG1%2Fmid%3D%3D?fields=attachments",
  );
  const url = metaMessageMediaUrl("v25.0", "mid-photo");
  const { requests, fetchImpl } = network({
    [url]: {
      body: JSON.stringify({ attachments: { data: [{ image_data: { url: PHOTO_URL } }] } }),
    },
  });
  assertEquals(
    await fetchMetaMessageMediaSources({
      graphVersion: "v25.0",
      externalMessageId: "mid-photo",
      accessToken: "page-token",
      fetchImpl,
    }),
    { ok: true, sources: [{ kind: "image", url: PHOTO_URL }] },
  );
  assertEquals(requests[0].authorization, "Bearer page-token");
  assertEquals(requests[0].url.includes("page-token"), false);
});

Deno.test("a refusal of Meta is a code, and a message without files says so", async () => {
  const url = metaMessageMediaUrl("v25.0", "mid-photo");
  const ask = (answer: Answer) =>
    fetchMetaMessageMediaSources({
      graphVersion: "v25.0",
      externalMessageId: "mid-photo",
      accessToken: "page-token",
      fetchImpl: network({ [url]: answer }).fetchImpl,
    });
  // Older than the 20 newest of its conversation, or no access yet.
  assertEquals(
    await ask({ status: 400, body: JSON.stringify({ error: { code: 100, error_subcode: 33 } }) }),
    { ok: false, error: "graph_100_33", retrySoon: false },
  );
  assertEquals(
    await ask({ status: 400, body: JSON.stringify({ error: { code: 10 } }) }),
    { ok: false, error: "graph_10", retrySoon: false },
  );
  assertEquals(
    await ask({ status: 500, body: JSON.stringify({ error: { code: 2 } }) }),
    { ok: false, error: "graph_2", retrySoon: true },
  );
  assertEquals(
    await ask({ body: JSON.stringify({ id: "mid-photo" }) }),
    { ok: false, error: "no_media_in_message", retrySoon: false },
  );
  assertEquals(
    await fetchMetaMessageMediaSources({
      graphVersion: "v25.0",
      externalMessageId: "mid-photo",
      accessToken: "page-token",
      fetchImpl: () => Promise.reject(new Error("offline")),
    }),
    { ok: false, error: "network", retrySoon: true },
  );
});

Deno.test("the sweep fetches what is due and records why not for the rest", async () => {
  const second = {
    ...CLAIM_ITEM,
    message_id: "44444444-4444-4444-8444-444444444444",
    external_message_id: "mid-old",
  };
  const { client, calls, uploads } = fakeClient({
    claim_meta_message_media_due: {
      channel_id: "channel-1",
      provider: "instagram",
      messages: [CLAIM_ITEM, second, { message_id: "broken" }],
    },
    get_meta_channel_access_token: { access_token: "page-token" },
    attach_meta_message_media: { attached: true },
  });
  const { fetchImpl } = network({
    [metaMessageMediaUrl("v25.0", "mid-photo")]: {
      body: JSON.stringify({ attachments: { data: [{ image_data: { url: PHOTO_URL } }] } }),
    },
    [metaMessageMediaUrl("v25.0", "mid-old")]: {
      status: 400,
      body: JSON.stringify({ error: { code: 100, error_subcode: 33 } }),
    },
    [PHOTO_URL]: { body: JPEG, headers: { "content-type": "image/jpeg" } },
  });
  const sweep = await resolveDueMetaMessageMedia({
    client,
    provider: "instagram",
    accountId: "ig-account",
    graphVersion: "v25.0",
    fetchImpl,
  });
  assertEquals(sweep, { claimed: 2, attached: 1, errors: ["graph_100_33"] });
  assertEquals(calls[0], {
    name: "claim_meta_message_media_due",
    args: { p_provider: "instagram", p_external_account_id: "ig-account", p_limit: 3 },
  });
  assertEquals(uploads.length, 1);
  assertEquals(
    calls.filter((call) => call.name === "fail_meta_message_media").map((call) => call.args),
    [{ p_message_id: second.message_id, p_error: "graph_100_33", p_retry_soon: false }],
  );
});

Deno.test("nothing due means no token is read and Meta is not called", async () => {
  const { client, calls } = fakeClient({
    claim_meta_message_media_due: { channel_id: "channel-1", messages: [] },
  });
  const { requests, fetchImpl } = network({});
  assertEquals(
    await resolveDueMetaMessageMedia({
      client,
      provider: "instagram",
      accountId: "ig-account",
      graphVersion: "v25.0",
      fetchImpl,
    }),
    { claimed: 0, attached: 0, errors: [] },
  );
  assertEquals(calls.map((call) => call.name), ["claim_meta_message_media_due"]);
  assertEquals(requests.length, 0);
});

Deno.test("without the channel token the messages wait and Meta is not called", async () => {
  const { client, calls } = fakeClient(
    { claim_meta_message_media_due: { channel_id: "channel-1", messages: [CLAIM_ITEM] } },
    { failing: ["get_meta_channel_access_token"] },
  );
  const { requests, fetchImpl } = network({});
  assertEquals(
    await resolveDueMetaMessageMedia({
      client,
      provider: "instagram",
      accountId: "ig-account",
      graphVersion: "v25.0",
      fetchImpl,
    }),
    { claimed: 1, attached: 0, errors: ["credential_unavailable"] },
  );
  assertEquals(requests.length, 0);
  assertEquals(calls.at(-1)?.args, {
    p_message_id: MESSAGE.messageId,
    p_error: "credential_unavailable",
    p_retry_soon: false,
  });
});

Deno.test("the sweep never throws into the webhook", async () => {
  const { client } = fakeClient({});
  assertEquals(
    await resolveDueMetaMessageMedia({
      client: {
        ...client,
        rpc() {
          throw new Error("database unreachable");
        },
      },
      provider: "instagram",
      accountId: "ig-account",
      graphVersion: "v25.0",
    }),
    { claimed: 0, attached: 0, errors: ["sweep_failed"] },
  );
});
