import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildMercadoPagoPaymentEvidence } from "../_shared/mercadopago_payment_evidence.ts";
import { recordMercadoPagoPaymentVoucherIfAvailable } from "../_shared/mercadopago_payment_voucher.ts";
import {
  paymentOrderIdentity,
  preferenceBelongsToOrder,
} from "../_shared/mercadopago_preference.ts";
import { summarizeMercadoPagoApiError } from "../_shared/mercadopago_webhook_resources.ts";
import {
  authorizePublicOrderAccess,
  PublicOrderAccessDeniedError,
} from "../_shared/public_order_access.ts";

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

function mapPaymentStatus(status: string): string {
  if (status === "approved") return "paid";
  if (status === "rejected" || status === "cancelled") return "failed";
  return "pending";
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const requestBody = await req.json();
    const paymentId = typeof requestBody?.payment_id === "string"
      ? requestBody.payment_id.trim()
      : "";
    if (!paymentId || paymentId.length > 160) {
      return jsonResponse({ error: "Invalid payment request" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Authorize the browser's token before selecting the order, tenant payment
    // credential, or making any provider request.
    const { orderId } = await authorizePublicOrderAccess(supabase, requestBody);

    const { data: order, error: orderError } = await supabase
      .from("online_orders")
      .select("id, tenant_id, total")
      .eq("id", orderId)
      .maybeSingle();

    if (orderError) {
      throw new Error(`Order query failed: ${orderError.message}`);
    }
    if (!order) {
      throw new PublicOrderAccessDeniedError();
    }

    const { data: settings, error: settingsError } = await supabase
      .from("website_settings")
      .select("value")
      .eq("tenant_id", order.tenant_id)
      .eq("key", "mercadopago_access_token")
      .limit(1);

    if (settingsError) {
      throw new Error(`Settings query failed: ${settingsError.message}`);
    }

    const accessToken = settings?.[0]?.value;
    if (!accessToken) {
      return jsonResponse({ error: "MercadoPago not configured for this tenant" }, 400);
    }

    const mpResponse = await fetch(
      `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );

    let payment: Record<string, unknown> | null = null;
    try {
      const decoded = await mpResponse.json();
      if (decoded && typeof decoded === "object" && !Array.isArray(decoded)) {
        payment = decoded as Record<string, unknown>;
      }
    } catch {
      if (mpResponse.ok) {
        throw new Error("MercadoPago returned an invalid success response");
      }
    }

    if (!mpResponse.ok) {
      const providerError = summarizeMercadoPagoApiError(
        payment,
        "payment",
        mpResponse.status,
      );
      console.error("[MercadoPago] Payment fetch failed", providerError);
      return jsonResponse({ error: "MercadoPago API error" }, mpResponse.status);
    }

    const externalReference = payment?.external_reference?.toString() ?? "";
    const paymentIdentity = paymentOrderIdentity(payment);
    if (
      !paymentIdentity ||
      !preferenceBelongsToOrder(externalReference, order.tenant_id, orderId) ||
      paymentIdentity.orderId !== orderId ||
      (paymentIdentity.tenantId && paymentIdentity.tenantId !== order.tenant_id)
    ) {
      return jsonResponse({ error: "Payment does not match order" }, 409);
    }

    const providerStatus = payment?.status?.toString() ?? "";
    const paymentStatus = mapPaymentStatus(providerStatus);
    const paidAmount = Number(payment?.transaction_amount);
    if (!Number.isFinite(paidAmount)) {
      return jsonResponse({ error: "Payment amount is invalid" }, 409);
    }

    // Phase 1 is an independent RPC/transaction: preserve provider truth
    // before attempting invoice, stock, payment-ledger, or accounting effects.
    const { data: eventResult, error: eventError } = await supabase.rpc(
      "record_mercadopago_payment_observation",
      {
        p_order_id: order.id,
        p_tenant_id: order.tenant_id,
        p_payment_id: paymentId,
        p_provider_status: providerStatus,
        p_amount: paidAmount,
        p_currency: payment?.currency_id?.toString() ?? "",
        p_paid_at: payment?.date_approved ?? null,
        p_provider_payload: buildMercadoPagoPaymentEvidence(payment),
      },
    );

    if (eventError) {
      throw new Error(`Payment observation failed: ${eventError.message}`);
    }

    const paymentEventId = eventResult?.event_id;
    if (paymentEventId == null) {
      throw new Error("Payment observation returned no durable event identifier");
    }

    // Phase 2 is deliberately another RPC/transaction. Expected business
    // failures return action_required while the approved payment stays durable.
    const { data: processingResult, error: processingError } = await supabase.rpc(
      "process_mercadopago_payment_observation",
      { p_payment_event_id: paymentEventId },
    );

    if (processingError) {
      throw new Error(`Payment processing retry failed: ${processingError.message}`);
    }

    const eventOutcome = eventResult?.outcome?.toString() ?? "";
    if (eventOutcome.startsWith("rejected_")) {
      return jsonResponse({
        error: eventResult?.validation_error ?? "Payment validation failed",
        event: eventResult,
        processing: processingResult,
      }, 409);
    }

    const paymentVoucher = await recordMercadoPagoPaymentVoucherIfAvailable({
      supabase,
      payment,
      tenantId: order.tenant_id,
      orderId: order.id,
      eventResult,
      processingResult,
    });

    return jsonResponse({
      id: payment?.id?.toString() ?? paymentId,
      status: providerStatus,
      status_detail: payment?.status_detail ?? null,
      order_id: paymentIdentity.orderId,
      payment_status: paymentStatus,
      event: eventResult,
      processing: processingResult,
      payment_voucher: paymentVoucher,
    });
  } catch (error) {
    if (error instanceof PublicOrderAccessDeniedError) {
      return jsonResponse({ error: "Order access denied" }, 403);
    }
    console.error("[MercadoPago] Get payment error", error);
    return jsonResponse({ error: "Unable to verify payment" }, 500);
  }
});
