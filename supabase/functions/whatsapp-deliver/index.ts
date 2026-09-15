import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handleWhatsAppSend } from "../whatsapp-send/index.ts";
import {
  outboxCompletionStatus,
  runtimeSecretKey,
  validOutboxDispatch,
} from "../_shared/whatsapp_outbox.ts";

const json = (body: unknown, status: number) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json" },
});

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const raw = await req.text();
  if (raw.length > 1024) return json({ error: "Invalid dispatch" }, 400);
  let body: unknown;
  try { body = JSON.parse(raw); } catch (_) { body = null; }
  if (!validOutboxDispatch(body)) return json({ error: "Invalid dispatch" }, 400);
  let admin;
  try {
    admin = createClient(Deno.env.get("SUPABASE_URL")!, runtimeSecretKey(Deno.env.get("SUPABASE_SECRET_KEYS")), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  } catch (_) {
    return json({ error: "Worker runtime unavailable" }, 503);
  }
  const { data: job, error } = await admin.rpc("claim_whatsapp_outbox_v1", {
    p_message_id: body.message_id, p_token: body.token,
  });
  if (error) return json({ error: "Unable to claim dispatch" }, 503);
  if (!job) return json({ error: "Invalid or consumed dispatch" }, 403);

  const finish = async (status: string, patch: Record<string, unknown>) => {
    const result = await admin.rpc("finish_whatsapp_outbox_v1", {
      p_message_id: body.message_id, p_token: body.token,
      p_status: status, p_patch: patch,
    });
    if (result.error) throw result.error;
    return result.data === true;
  };
  const deliver = async () => {
    let sending = false;
    try {
      const response = await handleWhatsAppSend(new Request(req.url, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify(job.request),
      }), {
        adminClient: admin,
        userId: job.actor_id, tenantId: job.tenant_id, messageId: job.message_id,
        beforeProviderSend: async () => {
          const result = await admin.rpc("start_whatsapp_outbox_send_v1", {
            p_message_id: body.message_id, p_token: body.token,
          });
          if (result.error) throw result.error;
          sending = result.data === true;
          return sending;
        },
        persist: async (patch) => {
          if (!await finish(outboxCompletionStatus(patch), {
            content: patch.content, type: patch.type, metadata: patch.metadata,
            external_message_id: patch.externalMessageId,
          })) throw new Error("Outbox completion lease rejected");
        },
      });
      if (!response.ok) {
        const result = await response.json();
        // A handler can reject before persistence (authorization, attachment,
        // expired quote). Known Meta acceptance is recoverable without resend.
        await finish(result.provider_accepted && result.external_message_id
          ? "accepted" : sending ? "outcome_unknown" : "failed", {
          external_message_id: result.external_message_id,
          error: result.code ?? "delivery_validation_failed",
          metadata: { external_error_message: result.error ?? "No se pudo enviar el mensaje." },
        });
      }
    } catch (error) {
      console.error("[WHATSAPP-OUTBOX] Delivery failed", String(error));
      await finish(sending ? "outcome_unknown" : "retry", {
        error: "worker_interrupted",
        metadata: { external_error_message: "No se pudo confirmar el envío." },
      }).catch(() => {
        // Cron recovers the persisted lease; it never retries a sending lease.
        console.error("[WHATSAPP-OUTBOX] Completion deferred to lease recovery");
      });
    }
  };
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil: (work: Promise<unknown>) => void } }).EdgeRuntime;
  if (runtime) {
    runtime.waitUntil(deliver());
    return json({ accepted: true }, 202);
  }
  await deliver();
  return json({ accepted: true }, 200);
});
