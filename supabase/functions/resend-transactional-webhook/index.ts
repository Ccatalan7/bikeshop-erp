import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sha256Hex, verifyResendWebhookSignature } from "../_shared/transactional_email/crypto.ts";
import { JsonRecord, resendOperationalEmailEvents } from "../_shared/transactional_email/types.ts";

type RpcResult = {
  data: unknown;
  error: { message: string } | null;
};

type WebhookRpcClient = {
  rpc(name: string, params: Record<string, unknown>): PromiseLike<RpcResult>;
};

type WebhookDependencies = {
  env(name: string): string;
  now(): Date;
  createRpcClient(url: string, serviceRoleKey: string): WebhookRpcClient;
};

const defaultDependencies: WebhookDependencies = {
  env: (name) => Deno.env.get(name) ?? "",
  now: () => new Date(),
  createRpcClient: (url, serviceRoleKey) =>
    createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
};

const maxWebhookBodyBytes = 256 * 1024;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function boundedText(value: unknown, maximumLength: number): string | null {
  const candidate = stringValue(value);
  if (!candidate) return null;
  const printable = Array.from(candidate, (character) => {
    const code = character.charCodeAt(0);
    return code < 32 || code === 127 ? " " : character;
  }).join("");
  return printable.slice(0, maximumLength).trim() || null;
}

function sanitizedProviderReason(...values: unknown[]): string | null {
  const candidate = values.map((value) => boundedText(value, 2000)).find(Boolean);
  if (!candidate) return null;
  return candidate
    .replaceAll(
      /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,
      "[redacted-email]",
    )
    .replaceAll(/\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi, "Bearer [redacted]")
    .replaceAll(/\b(access_token|api_key|token)=\S+/gi, "$1=[redacted]")
    .slice(0, 512)
    .trim() || null;
}

function isOperationalEmailEvent(value: string): boolean {
  return (resendOperationalEmailEvents as readonly string[]).includes(value);
}

function outboxHint(data: JsonRecord): string | null {
  const tags = record(data.tags);
  const direct = stringValue(tags.outbox_id);
  if (direct && uuidPattern.test(direct)) return direct;

  if (Array.isArray(data.tags)) {
    for (const rawTag of data.tags) {
      const tag = record(rawTag);
      const value = tag.name === "outbox_id" ? stringValue(tag.value) : null;
      if (value && uuidPattern.test(value)) return value;
    }
  }
  return null;
}

function sanitizedProviderPayload(event: JsonRecord): JsonRecord {
  const data = record(event.data);
  const bounce = record(data.bounce);
  const failed = record(data.failed);
  return {
    type: stringValue(event.type),
    emailId: boundedText(data.email_id, 256),
    createdAt: boundedText(event.created_at, 64),
    reason: sanitizedProviderReason(bounce.message, failed.reason, data.reason),
    bounceType: boundedText(bounce.type, 80),
    bounceSubType: boundedText(bounce.subType, 120),
    outboxId: outboxHint(data),
  };
}

export async function handleResendTransactionalWebhook(
  request: Request,
  dependencies: WebhookDependencies = defaultDependencies,
): Promise<Response> {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maxWebhookBodyBytes) {
    return json({ error: "Webhook payload is too large" }, 413);
  }

  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > maxWebhookBodyBytes) {
    return json({ error: "Webhook payload is too large" }, 413);
  }
  const signingSecret = dependencies.env("RESEND_WEBHOOK_SECRET");
  const messageId = request.headers.get("svix-id");
  const signatureValid = await verifyResendWebhookSignature({
    rawBody,
    messageId,
    timestamp: request.headers.get("svix-timestamp"),
    signature: request.headers.get("svix-signature"),
    secret: signingSecret,
    now: dependencies.now(),
  });
  if (!signatureValid) return json({ error: "Invalid webhook signature" }, 401);

  let event: JsonRecord;
  try {
    event = record(JSON.parse(rawBody));
  } catch {
    return json({ error: "Invalid JSON payload" }, 400);
  }

  const eventType = stringValue(event.type);
  const data = record(event.data);
  const providerMessageId = boundedText(data.email_id, 256);
  const occurredAtValue = stringValue(event.created_at);
  if (!messageId || messageId.length > 256 || !eventType) {
    return json({ error: "Unsupported webhook payload" }, 400);
  }
  if (!isOperationalEmailEvent(eventType)) {
    // A signed but unsubscribed engagement/domain event is acknowledged so
    // Resend does not retry it. It is deliberately not persisted because it
    // does not change transactional delivery truth.
    return json({ received: true, ignored: true, eventType });
  }
  if (!providerMessageId) {
    return json({ error: "Transactional email event has no email id" }, 400);
  }
  if (!occurredAtValue || Number.isNaN(Date.parse(occurredAtValue))) {
    return json({ error: "Transactional email event has no valid occurrence time" }, 400);
  }

  const supabaseUrl = dependencies.env("SUPABASE_URL");
  const serviceRoleKey = dependencies.env("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Supabase is not configured" }, 503);

  const sanitized = sanitizedProviderPayload(event);
  const supabase = dependencies.createRpcClient(supabaseUrl, serviceRoleKey);
  const { data: result, error } = await supabase.rpc(
    "record_transactional_email_provider_event",
    {
      p_provider: "resend",
      p_provider_event_id: messageId,
      p_provider_message_id: providerMessageId,
      p_outbox_id_hint: outboxHint(data),
      p_event_type: eventType,
      p_occurred_at: occurredAtValue,
      p_payload_sha256: await sha256Hex(rawBody),
      p_sanitized_payload: sanitized,
      // Resend defines email.bounced itself as a permanent recipient-server
      // rejection. Do not depend on an optional nested subtype to suppress it.
      p_is_permanent: eventType === "email.bounced",
    },
  );
  if (error) return json({ error: "Could not record provider event" }, 500);
  return json({ received: true, result });
}

if (import.meta.main) {
  Deno.serve((request) => handleResendTransactionalWebhook(request));
}
