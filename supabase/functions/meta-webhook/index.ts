import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type MetaWebhookEvent, parseMetaWebhookEvents } from "../_shared/meta_webhook_events.ts";
import { verifyMetaWebhookSignature } from "../_shared/meta_webhook_signature.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-hub-signature-256",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const META_APP_SECRET = Deno.env.get("META_APP_SECRET") ?? "";
const META_WEBHOOK_VERIFY_TOKEN = Deno.env.get("META_WEBHOOK_VERIFY_TOKEN") ?? "";

type JsonRecord = Record<string, unknown>;
// deno-lint-ignore no-explicit-any -- Edge Functions use the runtime schema.
type SupabaseClientLike = ReturnType<typeof createClient<any>>;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function asTimestamp(value: string | null) {
  if (!value) return null;
  if (/^\d+$/.test(value)) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric <= 0) return null;
    const milliseconds = numeric >= 10_000_000_000 ? numeric : numeric * 1_000;
    return new Date(milliseconds).toISOString();
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

async function requireRpc(
  client: SupabaseClientLike,
  name: string,
  args: JsonRecord,
) {
  const { data, error } = await client.rpc(name, args);
  if (error) {
    throw new Error(`${name}:${error.code ?? "rpc_error"}`);
  }
  return (data ?? {}) as JsonRecord;
}

async function processEvent(
  client: SupabaseClientLike,
  event: MetaWebhookEvent,
) {
  if (event.kind === "message") {
    return await requireRpc(client, "ingest_meta_message", {
      p_provider: event.provider,
      p_external_account_id: event.accountId,
      p_event_key: event.eventKey,
      p_external_message_id: event.externalMessageId,
      p_external_user_id: event.externalUserId,
      p_contact_name: null,
      p_username: null,
      p_message_type: event.messageType,
      p_message_body: event.text,
      p_occurred_at: event.occurredAt,
      p_payload: event.payload,
    });
  }
  if (event.kind === "echo") {
    return await requireRpc(client, "record_meta_echo_event", {
      p_provider: event.provider,
      p_external_account_id: event.accountId,
      p_event_key: event.eventKey,
      p_external_message_id: event.externalMessageId,
      p_external_user_id: event.externalUserId,
      p_occurred_at: event.occurredAt,
      p_payload: event.payload,
    });
  }
  if (event.kind === "delivery") {
    const messageIds = event.externalMessageIds.length > 0 ? event.externalMessageIds : [null];
    const results: JsonRecord[] = [];
    for (const messageId of messageIds) {
      results.push(
        await requireRpc(client, "record_meta_message_status", {
          p_provider: event.provider,
          p_external_account_id: event.accountId,
          p_event_key: messageId
            ? `${event.eventKey}:${encodeURIComponent(messageId)}`
            : event.eventKey,
          p_external_user_id: event.externalUserId,
          p_external_message_id: messageId,
          p_status: "delivered",
          p_watermark: asTimestamp(event.watermark),
          p_occurred_at: event.occurredAt,
          p_payload: event.payload,
        }),
      );
    }
    return { statuses: results };
  }
  if (event.kind === "read") {
    return await requireRpc(client, "record_meta_message_status", {
      p_provider: event.provider,
      p_external_account_id: event.accountId,
      p_event_key: event.eventKey,
      p_external_user_id: event.externalUserId,
      p_external_message_id: event.externalMessageId,
      p_status: "read",
      p_watermark: asTimestamp(event.watermark),
      p_occurred_at: event.occurredAt,
      p_payload: event.payload,
    });
  }
  return await requireRpc(client, "ingest_meta_interaction", {
    p_provider: event.provider,
    p_external_account_id: event.accountId,
    p_event_key: event.eventKey,
    p_interaction_type: event.interactionType,
    p_external_user_id: event.actorId ?? "",
    p_external_object_id: event.externalObjectId,
    p_parent_object_id: event.parentObjectId,
    p_actor_name: event.actorName,
    p_body: event.text,
    p_permalink: event.permalink,
    p_occurred_at: event.occurredAt,
    p_payload: event.payload,
  });
}

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  if (request.method === "GET") {
    const url = new URL(request.url);
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");
    if (
      mode === "subscribe" && challenge && META_WEBHOOK_VERIFY_TOKEN &&
      token === META_WEBHOOK_VERIFY_TOKEN
    ) {
      return new Response(challenge, { status: 200 });
    }
    return jsonResponse({ ok: false, error: "verification_failed" }, 403);
  }

  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !META_APP_SECRET) {
    console.error("[META-WEBHOOK] Required server configuration is absent");
    return jsonResponse({ ok: false, error: "server_not_configured" }, 503);
  }

  const rawBody = await request.text();
  const signatureValid = await verifyMetaWebhookSignature({
    signatureHeader: request.headers.get("x-hub-signature-256"),
    rawBody,
    appSecret: META_APP_SECRET,
  });
  if (!signatureValid) {
    return jsonResponse({ ok: false, error: "invalid_signature" }, 401);
  }

  let events: MetaWebhookEvent[];
  try {
    events = parseMetaWebhookEvents(JSON.parse(rawBody));
  } catch (error) {
    const code = error instanceof Error ? error.message : "invalid_payload";
    console.warn("[META-WEBHOOK] Deterministic payload rejection", code);
    return jsonResponse({ ok: true, ignored: true, reason: code }, 200);
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  let processed = 0;
  const failures: string[] = [];
  for (const event of events) {
    try {
      await processEvent(client, event);
      processed += 1;
    } catch (error) {
      const code = error instanceof Error ? error.message : "processing_error";
      failures.push(`${event.kind}:${code}`.slice(0, 240));
      console.error("[META-WEBHOOK] Durable processing failed", event.kind, code);
    }
  }

  if (failures.length > 0) {
    return jsonResponse({
      ok: false,
      processed,
      failed: failures.length,
      errors: failures,
    }, 500);
  }
  return jsonResponse({ ok: true, received: events.length, processed });
});
