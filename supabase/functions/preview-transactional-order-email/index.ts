import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  renderTransactionalEmail,
  TemplateRenderError,
} from "../_shared/transactional_email/templates.ts";
import { JsonRecord, TransactionalTemplateKey } from "../_shared/transactional_email/types.ts";

// The «va en camino» email as it would leave, before the shipment is
// registered (owner, 2026-10-13: «que muestre una vista previa del email antes
// de enviarlo, como con la plantilla de WhatsApp»). The content comes from
// `preview_online_order_shipment_email`, built by the same function the queue
// uses, and is drawn with the same template the worker sends: the preview is
// the email, not a copy of it. Nothing is written.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

type RpcResult = { data: unknown; error: { message?: string; code?: string } | null };

export type PreviewRpc = (
  authHeader: string,
  orderId: string,
  shipment: JsonRecord,
) => Promise<RpcResult>;

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

const supabaseRpc: PreviewRpc = async (authHeader, orderId, shipment) => {
  // The caller's own session: the database decides tenant and permission.
  const client = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } },
  );
  const { data, error } = await client.rpc("preview_online_order_shipment_email", {
    p_order_id: orderId,
    p_shipment: shipment,
  });
  return { data, error };
};

export async function handlePreview(
  request: Request,
  rpc: PreviewRpc = supabaseRpc,
): Promise<Response> {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = request.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+$/i.test(authHeader)) {
    return json({ error: "Authentication required" }, 401);
  }

  let body: JsonRecord;
  try {
    body = record(await request.json());
  } catch {
    return json({ error: "Invalid request" }, 400);
  }
  const orderId = typeof body.orderId === "string" ? body.orderId.trim() : "";
  const shipment = record(body.shipment);
  if (!/^[0-9a-f-]{36}$/i.test(orderId) || Object.keys(shipment).length === 0) {
    return json({ error: "orderId and shipment are required" }, 400);
  }

  const { data, error } = await rpc(authHeader, orderId, shipment);
  if (error) {
    const status = error.code === "42501" ? 403 : 400;
    return json(
      { error: error.message ?? "No se pudo preparar el correo", code: error.code },
      status,
    );
  }

  const preview = record(data);
  try {
    const rendered = renderTransactionalEmail({
      templateKey: String(preview.templateKey) as TransactionalTemplateKey,
      templateVersion: Number(preview.templateVersion),
      subject: String(preview.subject ?? ""),
      payload: record(preview.payload),
    });
    return json({
      recipient: preview.recipient ?? null,
      recipientName: preview.recipientName ?? null,
      senderName: preview.senderName ?? null,
      senderEmail: preview.senderEmail ?? null,
      replyTo: preview.replyTo ?? null,
      deliveryMode: preview.deliveryMode ?? "dry_run",
      suppressed: preview.suppressed ?? null,
      subject: rendered.subject,
      html: rendered.html,
      text: rendered.text,
    });
  } catch (renderError) {
    if (renderError instanceof TemplateRenderError) {
      return json({ error: renderError.message }, 422);
    }
    throw renderError;
  }
}

if (import.meta.main) Deno.serve((request) => handlePreview(request));
