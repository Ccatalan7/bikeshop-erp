import { assertEquals, assert } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { TrustedWhatsAppOutbox } from "../whatsapp-send/index.ts";

// Synthetic provider/DB only: these tests never contact Supabase or Meta.
Deno.env.set("SUPABASE_URL", "https://outbox-test.invalid");
Deno.env.set("WHATSAPP_ACCESS_TOKEN", "synthetic-test-token");
const { handleWhatsAppSend } = await import("../whatsapp-send/index.ts");
const tenant = "9f032200-0000-4000-8000-000000000001";
const conversation = "9f032200-0000-4000-8000-000000000141";
const actor = "9f032200-0000-4000-8000-000000000091";
const message = "9f032200-0000-4000-8000-000000000151";
const attachment = "9f032200-0000-4000-8000-000000000161";

function fakeDatabase(options: { audio?: boolean; reply?: string; missingReply?: boolean } = {}) {
  return {
    from(table: string) {
      let selection = "";
      let updating = false;
      const filters: Record<string, unknown> = {};
      const result = () => {
        if (updating) return { data: null, error: null };
        if (table === "messages") {
          assertEquals(filters.tenant_id, tenant);
          assertEquals(filters.conversation_id, conversation);
          assertEquals(filters.external_provider, "whatsapp");
          assertEquals(filters.external_message_id, options.reply);
          return { data: options.missingReply ? null : { id: "original" }, error: null };
        }
        if (table === "conversations") return { data: { id: conversation, tenant_id: tenant }, error: null };
        if (table === "whatsapp_channels") return {
          data: { id: "channel", phone_number_id: "synthetic-channel", is_active: true }, error: null,
        };
        if (table === "messaging_attachments" && selection.includes("declared_mime_type") && options.audio) {
          return { data: {
            id: attachment, tenant_id: tenant, conversation_id: conversation,
            storage_bucket: "chat-attachments", storage_path: `${tenant}/${conversation}/${attachment}.m4a`,
            original_filename: "synthetic.m4a", extension: "m4a", declared_mime_type: "audio/mp4",
            size_bytes: 4, status: "attached", created_by: actor, message_id: message,
          }, error: null };
        }
        return { data: [], error: null };
      };
      const query = {
        select(value: string) { selection = value; return query; },
        update(_value: unknown) { updating = true; return query; },
        eq(key: string, value: unknown) { filters[key] = value; return query; },
        in(_key: string, _value: unknown) { return query; },
        lt(_key: string, _value: unknown) { return query; },
        limit(_value: number) { return query; },
        maybeSingle() { return Promise.resolve(result()); },
        then(resolve: (value: unknown) => unknown) { return Promise.resolve(result()).then(resolve); },
      };
      return query;
    },
    rpc(name: string) {
      return Promise.resolve({ data: name === "ensure_whatsapp_conversation_binding"
        ? { binding_id: "binding", conversation_id: conversation } : null, error: null });
    },
    storage: { from: () => ({ download: () => Promise.resolve({ data: new Blob([new Uint8Array(4)]), error: null }) }) },
  } as unknown as TrustedWhatsAppOutbox["adminClient"];
}

async function exercise(options: {
  provider: typeof fetch;
  audio?: boolean;
  allowSend?: boolean;
  reply?: string;
  missingReply?: boolean;
}) {
  const previousFetch = globalThis.fetch;
  const events: string[] = [];
  const patches: Parameters<TrustedWhatsAppOutbox["persist"]>[0][] = [];
  globalThis.fetch = ((...args: Parameters<typeof fetch>) => {
    events.push(String(args[0]).endsWith("/media") ? "media" : "meta");
    return options.provider(...args);
  }) as typeof fetch;
  try {
    const response = await handleWhatsAppSend(new Request("https://outbox-test.invalid", {
      method: "POST", body: JSON.stringify({
        conversationId: conversation, phoneNumber: "+56911112222", type: options.audio ? "audio" : "text",
        replyToMessageId: options.reply,
        text: "Synthetic", attachmentId: options.audio ? attachment : undefined,
        metadata: { client_message_id: "one", external_status: "read", whatsapp_status: "read" },
      }),
    }), {
      adminClient: fakeDatabase(options), userId: actor, tenantId: tenant, messageId: message,
      beforeProviderSend: async () => { events.push("fence"); return options.allowSend !== false; },
      persist: async (patch) => { events.push("persist"); patches.push(patch); },
    });
    return { response, events, patches };
  } finally {
    globalThis.fetch = previousFetch;
  }
}

Deno.test("worker updates the accepted row only after a fenced Meta receipt", async () => {
  const { response, events, patches } = await exercise({
    provider: () => Promise.resolve(Response.json({ messages: [{ id: "wamid.synthetic" }] })),
  });
  assertEquals(events, ["fence", "meta", "persist"]);
  assertEquals(response.status, 200);
  assertEquals(patches.length, 1);
  assertEquals(patches[0].externalMessageId, "wamid.synthetic");
  assertEquals(patches[0].metadata.external_status, undefined);
  assertEquals((await response.json()).message_id, message);
});
Deno.test("network ambiguity is retained and never sends a second copy", async () => {
  const { events, patches } = await exercise({
    provider: () => Promise.reject(new Error("Synthetic lost response")),
  });
  assertEquals(events.filter((event) => event === "meta").length, 1);
  assertEquals(patches[0].externalStatus, null);
  assertEquals(patches[0].metadata.whatsapp_status, "outcome_unknown");
});
Deno.test("definite rejection records failure without inventing a provider id", async () => {
  const { patches } = await exercise({
    provider: () => Promise.resolve(Response.json({ error: { code: 131047 } }, { status: 400 })),
  });
  assertEquals(patches[0].externalStatus, "failed");
  assertEquals(patches[0].externalMessageId, undefined);
  assertEquals(patches[0].metadata.provider_http_status, 400);
});
Deno.test("expired worker cannot make a provider message request", async () => {
  const { response, events } = await exercise({
    allowSend: false, provider: () => { throw new Error("must not contact Meta"); },
  });
  assertEquals(response.status, 409);
  assertEquals(events, ["fence"]);
});
Deno.test("queued voice attachment is reused, uploaded, and sent after the fence", async () => {
  const { response, events, patches } = await exercise({ audio: true,
    provider: (url, init) => {
      if (String(url).endsWith("/media")) return Promise.resolve(Response.json({ id: "media.synthetic" }));
      const payload = JSON.parse(String(init?.body));
      assertEquals(payload.audio, { id: "media.synthetic" });
      return Promise.resolve(Response.json({ messages: [{ id: "wamid.audio.synthetic" }] }));
    },
  });
  assertEquals(response.status, 200);
  assertEquals(events, ["media", "fence", "meta", "persist"]);
  assert(patches[0].metadata.attachment_id === attachment);
});

Deno.test("quoted text reaches Meta as context and keeps its durable reference", async () => {
  const { response, patches } = await exercise({ reply: "wamid.original",
    provider: (_url, init) => {
      assertEquals(JSON.parse(String(init?.body)).context, { message_id: "wamid.original" });
      return Promise.resolve(Response.json({ messages: [{ id: "wamid.reply" }] }));
    },
  });
  assertEquals(response.status, 200);
  assertEquals(patches[0].metadata.reply_to_external_message_id, "wamid.original");
});
Deno.test("foreign or missing reply target never reaches the provider", async () => {
  const { response, events } = await exercise({ reply: "wamid.foreign", missingReply: true,
    provider: () => { throw new Error("must not contact Meta"); },
  });
  assertEquals(response.status, 400);
  assertEquals(events, []);
});
Deno.test("quoted voice note sends context as well as private media", async () => {
  const { response } = await exercise({ reply: "wamid.original", audio: true,
    provider: (url, init) => {
      if (String(url).endsWith("/media")) return Promise.resolve(Response.json({ id: "media.synthetic" }));
      assertEquals(JSON.parse(String(init?.body)).context, { message_id: "wamid.original" });
      return Promise.resolve(Response.json({ messages: [{ id: "wamid.reply-audio" }] }));
    },
  });
  assertEquals(response.status, 200);
});
