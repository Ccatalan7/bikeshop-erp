import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseMetaWebhookEvents } from "./meta_webhook_events.ts";

Deno.test("normalizes Facebook and Instagram inbound text messages", () => {
  const facebookPayload = {
    object: "page",
    entry: [{
      id: "page-1",
      time: 1_721_000_000_000,
      messaging: [{
        sender: { id: "psid-1" },
        recipient: { id: "page-1" },
        timestamp: 1_721_000_000_123,
        message: { mid: "fb-mid-1", text: "  Hola\u0000 Facebook  " },
      }],
    }],
  };
  const instagramPayload = {
    object: "instagram",
    entry: [{
      id: "ig-business-1",
      messaging: [{
        sender: { id: "igsid-1" },
        recipient: { id: "ig-business-1" },
        timestamp: 1_721_000_100_000,
        message: { mid: "ig-mid-1", text: "Hola Instagram" },
      }],
    }],
  };

  const facebook = parseMetaWebhookEvents(facebookPayload);
  const instagram = parseMetaWebhookEvents(instagramPayload);
  assertEquals(facebook, parseMetaWebhookEvents(facebookPayload));
  assertEquals(facebook.length, 1);
  assertEquals(facebook[0].kind, "message");
  assertEquals(facebook[0].provider, "facebook_messenger");
  assertEquals(facebook[0].eventKey, "meta:facebook_messenger:message:page-1:fb-mid-1");
  if (facebook[0].kind === "message") {
    assertEquals(facebook[0].externalUserId, "psid-1");
    assertEquals(facebook[0].messageType, "text");
    assertEquals(facebook[0].text, "Hola Facebook");
  }

  assertEquals(instagram.length, 1);
  assertEquals(instagram[0].provider, "instagram");
  if (instagram[0].kind === "message") {
    assertEquals(instagram[0].accountId, "ig-business-1");
    assertEquals(instagram[0].externalMessageId, "ig-mid-1");
    assertEquals(instagram[0].text, "Hola Instagram");
  }
});

Deno.test("turns inbound media into a safe placeholder without remote URLs", () => {
  const [event] = parseMetaWebhookEvents({
    object: "instagram",
    entry: [{
      id: "ig-business-1",
      messaging: [{
        sender: { id: "igsid-1" },
        recipient: { id: "ig-business-1" },
        timestamp: 1_721_000_200_000,
        message: {
          mid: "ig-media-1",
          attachments: [{
            type: "image",
            payload: {
              id: "attachment-1",
              url: "https://cdn.example/private-photo.jpg?access_token=secret",
            },
          }],
        },
      }],
    }],
  });

  assertEquals(event.kind, "message");
  if (event.kind === "message") {
    assertEquals(event.messageType, "image");
    assertEquals(event.text, "Imagen recibida");
    assertEquals(event.payload, {
      message_id: "ig-media-1",
      message_type: "image",
      text: "Imagen recibida",
      attachment_types: ["image"],
      attachment_ids: ["attachment-1"],
    });
    assertEquals(JSON.stringify(event).includes("cdn.example"), false);
    assertEquals(JSON.stringify(event).includes("access_token"), false);
  }
});

Deno.test("discriminates outbound echoes without creating inbound events", () => {
  const events = parseMetaWebhookEvents({
    object: "page",
    entry: [{
      id: "page-1",
      messaging: [{
        sender: { id: "page-1" },
        recipient: { id: "psid-1" },
        timestamp: 1_721_000_300_000,
        message: { mid: "echo-mid-1", text: "Respuesta", is_echo: true },
      }],
    }],
  });

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "echo");
  if (events[0].kind === "echo") {
    assertEquals(events[0].direction, "outbound");
    assertEquals(events[0].externalUserId, "psid-1");
    assertEquals(events[0].eventKey, "meta:facebook_messenger:echo:page-1:echo-mid-1");
  }
});

Deno.test("ignores deleted and self-authored messages instead of fabricating inbound activity", () => {
  const events = parseMetaWebhookEvents({
    object: "instagram",
    entry: [{
      id: "ig-business-1",
      messaging: [{
        sender: { id: "igsid-1" },
        recipient: { id: "ig-business-1" },
        timestamp: 1_721_000_310_000,
        message: { mid: "ig-deleted-1", is_deleted: true },
      }, {
        sender: { id: "ig-business-1" },
        recipient: { id: "igsid-1" },
        timestamp: 1_721_000_320_000,
        message: { mid: "ig-self-1", text: "Propio", is_self: true },
      }],
    }],
  });

  assertEquals(events, []);
});

Deno.test("normalizes delivery mids and exact or watermark reads", () => {
  const events = parseMetaWebhookEvents({
    object: "page",
    entry: [{
      id: "page-1",
      messaging: [{
        sender: { id: "psid-1" },
        recipient: { id: "page-1" },
        timestamp: 1_721_000_400_000,
        delivery: {
          mids: ["mid-2", "mid-1", "mid-2"],
          watermark: 1_721_000_399_999,
        },
      }, {
        sender: { id: "psid-1" },
        recipient: { id: "page-1" },
        timestamp: 1_721_000_500_000,
        read: { mid: "mid-2", watermark: 1_721_000_499_999 },
      }, {
        sender: { id: "psid-1" },
        recipient: { id: "page-1" },
        timestamp: 1_721_000_600_000,
        read: { watermark: 1_721_000_599_999 },
      }],
    }],
  });

  assertEquals(events.map((event) => event.kind), ["delivery", "read", "read"]);
  if (events[0].kind === "delivery") {
    assertEquals(events[0].externalMessageIds, ["mid-1", "mid-2"]);
    assertEquals(events[0].watermark, "1721000399999");
  }
  if (events[1].kind === "read") {
    assertEquals(events[1].externalMessageId, "mid-2");
    assertEquals(events[1].watermark, "1721000499999");
  }
  if (events[2].kind === "read") {
    assertEquals(events[2].externalMessageId, null);
    assertEquals(events[2].watermark, "1721000599999");
  }
});

Deno.test("normalizes comments, mentions, and feed comments with minimal payloads", () => {
  const instagram = parseMetaWebhookEvents({
    object: "instagram",
    entry: [{
      id: "ig-business-1",
      time: 1_721_000_700,
      changes: [{
        field: "comments",
        value: {
          id: "ig-comment-1",
          text: "¿Está disponible?\u0000",
          from: { id: "ig-user-1", username: "ana" },
          media: {
            id: "ig-media-1",
            permalink: "https://instagram.com/p/abc/?access_token=drop-me",
            media_url: "https://cdn.example/private.jpg",
          },
        },
      }, {
        field: "mentions",
        value: {
          mention_id: "ig-mention-1",
          media_id: "ig-media-2",
          text: "@vinabike",
        },
      }],
    }],
  });
  const facebook = parseMetaWebhookEvents({
    object: "page",
    entry: [{
      id: "page-1",
      time: 1_721_000_800_000,
      changes: [{
        field: "feed",
        value: {
          item: "comment",
          verb: "add",
          comment_id: "fb-comment-1",
          post_id: "fb-post-1",
          message: "Precio, por favor",
          from: { id: "fb-user-1", name: "Bea" },
          permalink_url: "https://facebook.com/post?comment_id=fb-comment-1",
        },
      }],
    }],
  });

  assertEquals(
    instagram.map((event) => event.kind === "interaction" ? event.interactionType : event.kind),
    ["comment", "mention"],
  );
  assertEquals(facebook.length, 1);
  assertEquals(facebook[0].kind, "interaction");
  if (instagram[0].kind === "interaction") {
    assertEquals(instagram[0].externalObjectId, "ig-comment-1");
    assertEquals(instagram[0].parentObjectId, "ig-media-1");
    assertEquals(instagram[0].text, "¿Está disponible?");
    assertEquals(
      instagram[0].permalink,
      "https://instagram.com/p/abc/",
    );
    assertEquals(JSON.stringify(instagram[0]).includes("media_url"), false);
    assertEquals(JSON.stringify(instagram[0]).includes("cdn.example"), false);
  }
  if (facebook[0].kind === "interaction") {
    assertEquals(facebook[0].interactionType, "comment");
    assertEquals(facebook[0].verb, "add");
    assertEquals(facebook[0].actorName, "Bea");
    assertEquals(facebook[0].payload, {
      interaction_type: "comment",
      field: "feed",
      object_id: "fb-comment-1",
      parent_object_id: "fb-post-1",
      actor_id: "fb-user-1",
      actor_name: "Bea",
      verb: "add",
      text: "Precio, por favor",
      permalink: "https://facebook.com/post?comment_id=fb-comment-1",
    });
  }
});

Deno.test("keeps an Instagram media mention whose only object id is media_id", () => {
  const events = parseMetaWebhookEvents({
    object: "instagram",
    entry: [{
      id: "ig-business-1",
      time: 1_721_000_900,
      changes: [{
        field: "mentions",
        value: { media_id: "ig-media-mention-1" },
      }],
    }],
  });

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "interaction");
  if (events[0].kind === "interaction") {
    assertEquals(events[0].interactionType, "mention");
    assertEquals(events[0].externalObjectId, "ig-media-mention-1");
    assertEquals(events[0].parentObjectId, "ig-media-mention-1");
  }
});

Deno.test("normalizes the official direct-entry Instagram comment payload", () => {
  const events = parseMetaWebhookEvents({
    object: "instagram",
    entry: [{
      id: "ig-business-1",
      time: 1_721_000_700_000,
      field: "comments",
      value: {
        id: "comment-1",
        from: { username: "ana" },
        text: "Disponible?",
        media: { id: "media-1" },
      },
    }],
  });

  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "interaction");
  if (events[0].kind === "interaction") {
    assertEquals(events[0].provider, "instagram");
    assertEquals(events[0].accountId, "ig-business-1");
    assertEquals(events[0].interactionType, "comment");
    assertEquals(events[0].externalObjectId, "comment-1");
    assertEquals(events[0].parentObjectId, "media-1");
    assertEquals(events[0].actorName, "ana");
    assertEquals(events[0].text, "Disponible?");
  }
});

Deno.test("rejects invalid or unsupported webhook roots", () => {
  assertThrows(
    () => parseMetaWebhookEvents(null),
    Error,
    "invalid_meta_webhook_payload",
  );
  assertThrows(
    () => parseMetaWebhookEvents({ object: "whatsapp_business_account", entry: [] }),
    Error,
    "unsupported_meta_webhook_object",
  );
  assertThrows(
    () => parseMetaWebhookEvents({ object: "page", entry: {} }),
    Error,
    "invalid_meta_webhook_entries",
  );
});

Deno.test("drops interaction links outside the provider host allowlist", () => {
  const events = parseMetaWebhookEvents({
    object: "instagram",
    entry: [{
      id: "ig-account",
      changes: [{
        field: "comments",
        value: {
          id: "comment-host-test",
          text: "hello",
          permalink: "https://evil.example/instagram/phish",
        },
      }],
    }],
  });
  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "interaction");
  if (events[0].kind === "interaction") {
    assertEquals(events[0].permalink, null);
    assertEquals("permalink" in events[0].payload, false);
  }
});

Deno.test("preserves Page remove verbs for non-new interaction handling", () => {
  const events = parseMetaWebhookEvents({
    object: "page",
    entry: [{
      id: "page-remove",
      time: 1_721_001_000_000,
      changes: [{
        field: "feed",
        value: {
          item: "comment",
          verb: "remove",
          comment_id: "comment-remove",
          post_id: "post-remove",
        },
      }],
    }],
  });
  assertEquals(events.length, 1);
  assertEquals(events[0].kind, "interaction");
  if (events[0].kind === "interaction") {
    assertEquals(events[0].verb, "remove");
    assertEquals(events[0].payload.verb, "remove");
  }
});
