import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  buildMercadoPagoRefundEvidence,
  matchesCorrection,
  parseMercadoPagoRefundRequest,
  providerHttpOutcomeIsUnknown,
} from "../_shared/mercadopago_refund.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function safeError(error: unknown): string {
  const message = error instanceof Error ? error.message : "Unknown error";
  return message.replace(/Bearer\s+\S+/gi, "Bearer [redacted]").slice(0, 280);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authorization = req.headers.get("Authorization")?.trim() ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey || !authorization) {
    return jsonResponse({ error: "Authenticated staff session required" }, 401);
  }

  let correctionId = "";
  let providerRequestId = "";
  const service = createClient(supabaseUrl, serviceKey);
  try {
    const parsed = parseMercadoPagoRefundRequest(await req.json());
    correctionId = parsed.correctionId;
    const staff = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: authData, error: authError } = await staff.auth.getUser();
    if (authError || !authData.user) {
      return jsonResponse({ error: "Authenticated staff session required" }, 401);
    }

    // This RPC is stricter than read RLS: cashiers may inspect correction
    // evidence, but only authorized accounting actors can move provider money.
    // It also validates controls, invoice/payment linkage, exact remaining
    // line balances and physical-return provenance before credentials are read.
    const { data: authorized, error: correctionError } = await staff.rpc(
      "authorize_online_order_refund_execution",
      { p_correction_id: correctionId },
    );
    const correction = authorized as Record<string, any> | null;
    if (correctionError || !correction || correction.provider !== "mercadopago") {
      return jsonResponse({ error: "Correction not found or access denied" }, 404);
    }
    if (correction.processing_state === "applied") {
      return jsonResponse({ correction, replay: true });
    }

    if (correction.provider_state !== "succeeded") {
      const { data: setting, error: settingError } = await service
        .from("website_settings")
        .select("value")
        .eq("tenant_id", correction.tenant_id)
        .eq("key", "mercadopago_access_token")
        .limit(1)
        .maybeSingle();
      if (settingError || !setting?.value) {
        return jsonResponse({ error: "Mercado Pago is not configured" }, 409);
      }

      const paymentId = correction.provider_payment_id?.toString() ?? "";
      const expectedAmount = Number(correction.requested_amount);
      if (!paymentId || !Number.isFinite(expectedAmount) || expectedAmount <= 0) {
        return jsonResponse({ error: "Correction provider data is incomplete" }, 409);
      }
      providerRequestId = `provider:${correction.provider_idempotency_key}`;

      let providerResponse: Response;
      try {
        providerResponse = await fetch(
          `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}/refunds`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${setting.value}`,
              "Content-Type": "application/json",
              "X-Idempotency-Key": correction.provider_idempotency_key,
            },
            body: JSON.stringify({ amount: expectedAmount }),
          },
        );
      } catch (error) {
        await service.rpc("record_online_order_refund_provider_result", {
          p_correction_id: correction.id,
          p_result: "unknown",
          p_provider_refund_id: null,
          p_provider_status: null,
          p_amount: null,
          p_currency: correction.currency,
          p_refunded_at: null,
          p_provider_evidence: {},
          p_request_id: `${providerRequestId}:unknown`,
          p_error_code: "provider_outcome_unknown",
          p_error_message:
            "No se recibió confirmación del proveedor. Reintentar conserva la misma clave idempotente.",
        });
        console.error("[MercadoPago refund] Provider outcome unknown", safeError(error));
        return jsonResponse({
          error: "Provider outcome is unknown; retry is safe",
          action_required: true,
        }, 503);
      }

      let rawRefund: unknown = {};
      try {
        rawRefund = await providerResponse.json();
      } catch {
        // An invalid success body is an unknown outcome; an invalid failure
        // body remains a provider rejection without persisting its raw body.
      }
      if (!providerResponse.ok) {
        const code = rawRefund && typeof rawRefund === "object"
          ? (rawRefund as Record<string, unknown>).cause?.toString() ??
            (rawRefund as Record<string, unknown>).error?.toString() ??
            `provider_http_${providerResponse.status}`
          : `provider_http_${providerResponse.status}`;
        const outcomeUnknown = providerHttpOutcomeIsUnknown(providerResponse.status);
        await service.rpc("record_online_order_refund_provider_result", {
          p_correction_id: correction.id,
          p_result: outcomeUnknown ? "unknown" : "failed",
          p_provider_refund_id: null,
          p_provider_status: "rejected",
          p_amount: null,
          p_currency: correction.currency,
          p_refunded_at: null,
          p_provider_evidence: {},
          p_request_id: `${providerRequestId}:${
            outcomeUnknown ? "unknown" : "failed"
          }:${providerResponse.status}`,
          p_error_code: code.slice(0, 96),
          p_error_message: outcomeUnknown
            ? "Mercado Pago no confirmó el resultado; el reintento conserva la misma clave idempotente."
            : "Mercado Pago rechazó la solicitud de reembolso.",
        });
        if (outcomeUnknown) {
          return jsonResponse({
            error: "Provider outcome is unknown; retry is safe",
            action_required: true,
          }, 503);
        }
        return jsonResponse({
          error: "Mercado Pago rejected the refund",
          action_required: true,
        }, 409);
      }

      let evidence;
      try {
        evidence = buildMercadoPagoRefundEvidence(rawRefund);
      } catch (error) {
        await service.rpc("record_online_order_refund_provider_result", {
          p_correction_id: correction.id,
          p_result: "unknown",
          p_provider_refund_id: null,
          p_provider_status: null,
          p_amount: null,
          p_currency: correction.currency,
          p_refunded_at: null,
          p_provider_evidence: {},
          p_request_id: `${providerRequestId}:invalid-success`,
          p_error_code: "provider_success_evidence_invalid",
          p_error_message: "Mercado Pago respondió, pero la evidencia no pudo validarse.",
        });
        console.error("[MercadoPago refund] Invalid success evidence", safeError(error));
        return jsonResponse({ error: "Provider evidence is invalid", action_required: true }, 502);
      }
      if (!matchesCorrection(evidence, paymentId, expectedAmount)) {
        await service.rpc("record_online_order_refund_provider_result", {
          p_correction_id: correction.id,
          p_result: "unknown",
          p_provider_refund_id: evidence.id,
          p_provider_status: evidence.status,
          p_amount: evidence.amount,
          p_currency: correction.currency,
          p_refunded_at: evidence.date_created,
          p_provider_evidence: evidence,
          p_request_id: `${providerRequestId}:mismatch:${evidence.id}`,
          p_error_code: "provider_refund_mismatch",
          p_error_message: "La respuesta no coincide con el pago o monto solicitado.",
        });
        return jsonResponse({
          error: "Provider refund does not match correction",
          action_required: true,
        }, 409);
      }

      const { error: providerRecordError } = await service.rpc(
        "record_online_order_refund_provider_result",
        {
          p_correction_id: correction.id,
          p_result: "succeeded",
          p_provider_refund_id: evidence.id,
          p_provider_status: evidence.status,
          p_amount: evidence.amount,
          p_currency: correction.currency,
          p_refunded_at: evidence.date_created,
          p_provider_evidence: evidence,
          p_request_id: `${providerRequestId}:succeeded:${evidence.id}`,
          p_error_code: null,
          p_error_message: null,
        },
      );
      if (providerRecordError) {
        console.error(
          "[MercadoPago refund] Durable provider record failed",
          safeError(providerRecordError),
        );
        return jsonResponse({
          error: "Refund succeeded but durable evidence requires reconciliation",
          action_required: true,
        }, 503);
      }
    }

    // This is intentionally a second transaction. If it fails, the provider
    // success remains durable and a replay only retries internal effects.
    const applyRequestId = `apply:${correction.provider_idempotency_key}`;
    const { data: applied, error: applyError } = await staff.rpc(
      "apply_online_order_correction",
      { p_correction_id: correction.id, p_request_id: applyRequestId },
    );
    if (applyError) {
      await service.rpc("record_online_order_correction_apply_failure", {
        p_correction_id: correction.id,
        p_request_id: `${applyRequestId}:failed`,
        p_error_code: "internal_effects_failed",
        p_error_message: "El dinero fue reembolsado, pero stock/contabilidad requieren reintento.",
      });
      console.error("[MercadoPago refund] Internal apply failed", safeError(applyError));
      return jsonResponse({
        error: "Refund succeeded; internal effects require retry",
        action_required: true,
      }, 409);
    }
    return jsonResponse({ correction: applied, action_required: false });
  } catch (error) {
    console.error("[MercadoPago refund] Request failed", safeError(error));
    return jsonResponse({ error: "Refund workflow failed" }, 400);
  }
});
