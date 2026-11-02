import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { constantTimeEqual, sha256Hex } from "../_shared/transactional_email/crypto.ts";
import { sendWithResend } from "../_shared/transactional_email/resend_client.ts";
import { renderTransactionalEmail } from "../_shared/transactional_email/templates.ts";
import {
  QuoteEmailRenderError,
  renderQuoteEmail,
} from "../_shared/transactional_email/quote_templates.ts";
import {
  AttachmentManifestError,
  validateAttachmentDeliveryPolicy,
} from "../_shared/transactional_email/attachment_manifest.ts";
import {
  ClaimedTransactionalEmail,
  JsonRecord,
  TransactionalTemplateKey,
  transactionalTemplateKeys,
} from "../_shared/transactional_email/types.ts";

type ProcessMode = "dry_run" | "send";

type RpcResult = {
  data: unknown;
  error: { message: string } | null;
};

type RpcClient = {
  rpc(name: string, params: Record<string, unknown>): PromiseLike<RpcResult>;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function workerAuthorized(request: Request, secret: string): boolean {
  if (!secret) return false;
  const bearer = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const explicit = request.headers.get("x-transactional-email-worker-secret") ?? "";
  return constantTimeEqual(bearer, secret) || constantTimeEqual(explicit, secret);
}

function cleanSenderName(value: string): string {
  return value.replaceAll(/[\r\n<>]/g, " ").replaceAll(/\s+/g, " ").trim();
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function templateKey(value: unknown): TransactionalTemplateKey | null {
  return typeof value === "string" &&
      (transactionalTemplateKeys as readonly string[]).includes(value)
    ? value as TransactionalTemplateKey
    : null;
}

async function completeAttempt(
  supabase: RpcClient,
  message: ClaimedTransactionalEmail,
  params: Record<string, unknown>,
) {
  const { error } = await supabase.rpc("complete_transactional_email_attempt", {
    p_outbox_id: message.id,
    p_worker_id: params.p_worker_id,
    p_lease_token: message.lease_token,
    p_outcome: params.p_outcome,
    p_provider: params.p_provider ?? null,
    p_provider_message_id: params.p_provider_message_id ?? null,
    p_error_class: params.p_error_class ?? null,
    p_error_message: params.p_error_message ?? null,
    p_retry_after_seconds: params.p_retry_after_seconds ?? null,
    p_rendered_subject: params.p_rendered_subject ?? null,
    p_rendered_html_sha256: params.p_rendered_html_sha256 ?? null,
    p_rendered_text_sha256: params.p_rendered_text_sha256 ?? null,
  });
  if (error) throw new Error(`Could not complete outbox attempt: ${error.message}`);
}

// Correos de cotización (20261102063700): la misma corrida por taller, el
// mismo remitente y la misma clave de Resend que los del pedido. Corre
// después de ellos y un error aquí nunca los afecta.
export async function processQuoteMessages(
  supabase: RpcClient,
  tenantId: string,
  workerId: string,
  resendApiKey: string,
  send: typeof sendWithResend = sendWithResend,
): Promise<Array<Record<string, unknown>>> {
  const results: Array<Record<string, unknown>> = [];
  let claimed: unknown = [];
  try {
    const { data, error } = await supabase.rpc("claim_customer_quote_messages_v1", {
      p_tenant_id: tenantId,
      p_worker_id: workerId,
      p_limit: 10,
    });
    if (error) return [{ outcome: "claim_failed" }];
    claimed = data;
  } catch {
    return [{ outcome: "claim_failed" }];
  }

  for (const raw of Array.isArray(claimed) ? claimed : []) {
    const payload = asRecord(raw);
    const id = typeof payload.messageId === "string" ? payload.messageId : "";
    if (!id) continue;
    const complete = (outcome: string, providerId: string | null, errorText: string | null) =>
      supabase.rpc("complete_customer_quote_message_v1", {
        p_message_id: id,
        p_worker_id: workerId,
        p_outcome: outcome,
        p_provider_message_id: providerId,
        p_error: errorText,
      });
    try {
      const sender = asRecord(payload.sender);
      const recipient = typeof payload.recipient === "string" ? payload.recipient : "";
      if (
        sender.enabled !== true || typeof sender.name !== "string" ||
        typeof sender.email !== "string" || !recipient
      ) {
        await complete("skipped", null, "Transactional email is not enabled for this store");
        results.push({ id, outcome: "skipped" });
        continue;
      }
      const rendered = renderQuoteEmail(payload);
      const outcome = await send({
        apiKey: resendApiKey,
        idempotencyKey: `customer-quote-message:${id}`,
        from: `${cleanSenderName(sender.name)} <${sender.email}>`,
        to: recipient,
        replyTo: typeof sender.replyTo === "string" ? sender.replyTo : undefined,
        subject: rendered.subject,
        html: rendered.html,
        text: rendered.text,
        tags: [
          { name: "quote_message_id", value: id },
          { name: "template", value: `quote_${String(payload.kind)}` },
        ],
      });
      if (outcome.kind === "submitted") {
        await complete("sent", outcome.providerMessageId, null);
      } else {
        await complete(outcome.kind === "retry" ? "retry" : "failed", null, outcome.message);
      }
      results.push({ id, outcome: outcome.kind });
    } catch (error) {
      try {
        await complete(
          error instanceof QuoteEmailRenderError ? "failed" : "retry",
          null,
          error instanceof Error ? error.message : "Unexpected quote email error",
        );
      } catch {
        // The lease expires and the message is claimed again.
      }
      results.push({ id, outcome: "error" });
    }
  }
  return results;
}

export async function handleTransactionalEmailWorker(request: Request): Promise<Response> {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const workerSecret = Deno.env.get("TRANSACTIONAL_EMAIL_WORKER_SECRET") ?? "";
  if (!workerAuthorized(request, workerSecret)) return json({ error: "Unauthorized" }, 401);

  let body: JsonRecord;
  try {
    body = asRecord(await request.json());
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (body.action === "render") {
    const key = templateKey(body.templateKey);
    if (!key) return json({ error: "Unknown template key" }, 400);
    try {
      const rendered = renderTransactionalEmail({
        templateKey: key,
        templateVersion: Number(body.templateVersion ?? 1),
        subject: typeof body.subject === "string" ? body.subject : "Vista previa",
        payload: asRecord(body.payload),
      });
      return json({
        templateKey: rendered.templateKey,
        templateVersion: rendered.templateVersion,
        subject: rendered.subject,
        html: rendered.html,
        text: rendered.text,
      });
    } catch (error) {
      return json({ error: error instanceof Error ? error.message : "Render failed" }, 422);
    }
  }

  if (body.action !== "process") return json({ error: "Unknown action" }, 400);

  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(tenantId)
  ) {
    return json({ error: "A valid worker tenant_id is required" }, 400);
  }

  if (body.mode !== "dry_run" && body.mode !== "send") {
    return json({ error: "Process mode must be dry_run or send" }, 400);
  }
  const configuredMode = Deno.env.get("TRANSACTIONAL_EMAIL_MODE") === "send" ? "send" : "dry_run";
  const requestedMode: ProcessMode = body.mode;
  if (requestedMode === "send" && configuredMode !== "send") {
    return json({ error: "Send mode is not enabled for this function" }, 409);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Supabase is not configured" }, 503);

  const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
  if (requestedMode === "send" && !resendApiKey) {
    return json({ error: "RESEND_API_KEY is not configured" }, 503);
  }

  const batchSize = Math.max(1, Math.min(50, Math.floor(Number(body.limit ?? 20) || 20)));
  const workerId = `transactional-email:${crypto.randomUUID()}`;
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase.rpc("claim_transactional_email_outbox_for_tenant", {
    p_tenant_id: tenantId,
    p_worker_id: workerId,
    p_delivery_mode: requestedMode,
    p_batch_size: batchSize,
    p_lease_seconds: 120,
  });
  if (error) return json({ error: `Could not claim outbox: ${error.message}` }, 500);

  const messages = (data ?? []) as ClaimedTransactionalEmail[];
  if (messages.some((message) => message.tenant_id !== tenantId)) {
    return json({ error: "Tenant-scoped claim returned a foreign message" }, 500);
  }
  const results: Array<Record<string, unknown>> = [];

  for (const message of messages) {
    let acknowledgedSubmission: {
      providerMessageId: string;
      renderedSubject: string;
      htmlHash: string;
      textHash: string;
    } | null = null;
    try {
      let attachmentPolicy;
      try {
        attachmentPolicy = validateAttachmentDeliveryPolicy(
          message.template_key,
          message.attachment_manifest,
          message.render_payload,
        );
      } catch (error) {
        if (!(error instanceof AttachmentManifestError)) throw error;
        await completeAttempt(supabase as unknown as RpcClient, message, {
          p_worker_id: workerId,
          p_outcome: "permanent_failure",
          p_error_class: "unsafe_attachment_manifest",
          p_error_message: error.message,
        });
        results.push({
          id: message.id,
          outcome: "permanent_failure",
          attachment_policy: "rejected",
        });
        continue;
      }

      const rendered = renderTransactionalEmail({
        templateKey: message.template_key,
        templateVersion: message.template_version,
        subject: message.subject,
        payload: message.render_payload,
      });
      const htmlHash = await sha256Hex(rendered.html);
      const textHash = await sha256Hex(rendered.text);

      if (requestedMode === "dry_run") {
        await completeAttempt(supabase as unknown as RpcClient, message, {
          p_worker_id: workerId,
          p_outcome: "rendered",
          p_rendered_subject: rendered.subject,
          p_rendered_html_sha256: htmlHash,
          p_rendered_text_sha256: textHash,
        });
        results.push({
          id: message.id,
          outcome: "rendered",
          attachment_policy: attachmentPolicy,
        });
        continue;
      }

      if (!message.sender_name || !message.sender_email) {
        await completeAttempt(supabase as unknown as RpcClient, message, {
          p_worker_id: workerId,
          p_outcome: "permanent_failure",
          p_error_class: "sender_identity_missing",
          p_error_message: "Tenant transactional sender identity is incomplete",
          p_rendered_subject: rendered.subject,
          p_rendered_html_sha256: htmlHash,
          p_rendered_text_sha256: textHash,
        });
        results.push({ id: message.id, outcome: "permanent_failure" });
        continue;
      }

      const sendOutcome = await sendWithResend({
        apiKey: resendApiKey,
        idempotencyKey: message.idempotency_key,
        from: `${cleanSenderName(message.sender_name)} <${message.sender_email}>`,
        to: message.recipient_email,
        replyTo: message.reply_to_email ?? undefined,
        subject: rendered.subject,
        html: rendered.html,
        text: rendered.text,
        tags: [
          { name: "outbox_id", value: message.id },
          { name: "order_id", value: message.order_id },
          { name: "template", value: message.template_key },
        ],
      });

      if (sendOutcome.kind === "submitted") {
        acknowledgedSubmission = {
          providerMessageId: sendOutcome.providerMessageId,
          renderedSubject: rendered.subject,
          htmlHash,
          textHash,
        };
        await completeAttempt(supabase as unknown as RpcClient, message, {
          p_worker_id: workerId,
          p_outcome: "submitted",
          p_provider: "resend",
          p_provider_message_id: sendOutcome.providerMessageId,
          p_rendered_subject: rendered.subject,
          p_rendered_html_sha256: htmlHash,
          p_rendered_text_sha256: textHash,
        });
      } else {
        await completeAttempt(supabase as unknown as RpcClient, message, {
          p_worker_id: workerId,
          p_outcome: sendOutcome.kind === "retry" ? "retry" : "permanent_failure",
          p_error_class: sendOutcome.errorClass,
          p_error_message: sendOutcome.message,
          p_retry_after_seconds: sendOutcome.kind === "retry"
            ? sendOutcome.retryAfterSeconds ?? null
            : null,
          p_rendered_subject: rendered.subject,
          p_rendered_html_sha256: htmlHash,
          p_rendered_text_sha256: textHash,
        });
      }
      results.push({
        id: message.id,
        outcome: sendOutcome.kind,
        attachment_policy: attachmentPolicy,
      });
    } catch (error) {
      if (acknowledgedSubmission) {
        try {
          // A provider acknowledgement is stronger than a transient database
          // completion error. Retry the exact submitted completion; never
          // downgrade a known Resend acknowledgement back to pending.
          await completeAttempt(supabase as unknown as RpcClient, message, {
            p_worker_id: workerId,
            p_outcome: "submitted",
            p_provider: "resend",
            p_provider_message_id: acknowledgedSubmission.providerMessageId,
            p_rendered_subject: acknowledgedSubmission.renderedSubject,
            p_rendered_html_sha256: acknowledgedSubmission.htmlHash,
            p_rendered_text_sha256: acknowledgedSubmission.textHash,
          });
        } catch {
          // Keep the recoverable lease intact. A signed provider webhook or a
          // same-key provider replay can reconcile this acknowledgement.
        }
        results.push({
          id: message.id,
          outcome: "submitted_completion_pending",
          provider: "resend",
        });
        continue;
      }
      try {
        await completeAttempt(supabase as unknown as RpcClient, message, {
          p_worker_id: workerId,
          p_outcome: "retry",
          p_error_class: "worker_unexpected_error",
          p_error_message: error instanceof Error ? error.message : "Unexpected worker error",
        });
      } catch {
        // The lease is recoverable and will be reclaimed after expiry.
      }
      results.push({ id: message.id, outcome: "retry" });
    }
  }

  const quotes = requestedMode === "send"
    ? await processQuoteMessages(
      supabase as unknown as RpcClient,
      tenantId,
      workerId,
      resendApiKey,
    )
    : [];
  return json({ mode: requestedMode, claimed: messages.length, results, quotes });
}

if (import.meta.main) Deno.serve(handleTransactionalEmailWorker);
