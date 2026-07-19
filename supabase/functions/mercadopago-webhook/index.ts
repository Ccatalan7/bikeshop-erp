import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildMercadoPagoPaymentEvidence } from "../_shared/mercadopago_payment_evidence.ts";
import { recordMercadoPagoPaymentVoucherIfAvailable } from "../_shared/mercadopago_payment_voucher.ts";
import { paymentOrderIdentity } from "../_shared/mercadopago_preference.ts";
import { verifyMercadoPagoWebhookSignature } from "../_shared/mercadopago_webhook_signature.ts";
import {
  merchantOrderProcessingState,
  summarizeMercadoPagoApiError,
  uniqueMercadoPagoPaymentIds,
} from "../_shared/mercadopago_webhook_resources.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type MercadoPagoToken = {
  tenant_id: string | null;
  access_token: string;
  webhook_secret: string | null;
};

serve(async (req) => {
  console.log("🔔 [WEBHOOK] ========== REQUEST RECEIVED ==========");
  console.log("🔔 [WEBHOOK] Method:", req.method);
  console.log("🔔 [WEBHOOK] Time:", new Date().toISOString());

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    console.log("🔔 [WEBHOOK] CORS preflight - returning OK");
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    console.log("🔔 [WEBHOOK] Step 1: Creating Supabase client...");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    console.log("🔔 [WEBHOOK] Step 1: ✅ Supabase client created");

    console.log("🔔 [WEBHOOK] Step 2: Parsing request body...");
    const body = await req.json();
    console.log("🔔 [WEBHOOK] Step 2: ✅ Body parsed");

    const { type, action, data } = body;
    console.log("🔔 [WEBHOOK] Event type:", type, "| Action:", action, "| Data ID:", data?.id);

    console.log("🔔 [WEBHOOK] Step 3: Fetching configured MercadoPago tenant tokens...");
    const accessTokens = await loadMercadoPagoTokens(supabase);
    console.log("🔔 [WEBHOOK] Step 3: ✅ Token count:", accessTokens.length);

    if (accessTokens.length === 0) {
      console.error("🔔 [WEBHOOK] Step 3: ❌ No MercadoPago access tokens in website_settings");
      return new Response(JSON.stringify({ error: "No access token configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const requestUrl = new URL(req.url);
    const signatureDataId = requestUrl.searchParams.get("data.id") ??
      requestUrl.searchParams.get("data_id") ??
      data?.id?.toString() ??
      null;
    const globalWebhookSecret = Deno.env.get("MERCADOPAGO_WEBHOOK_SECRET")?.trim() || null;

    let verifiedTenantId: string | null = null;
    let signatureVerified = false;
    for (const token of accessTokens) {
      const usesTenantSecret = token.webhook_secret != null;
      const secret = token.webhook_secret || globalWebhookSecret;
      if (!secret) continue;
      if (
        await verifyMercadoPagoWebhookSignature({
          signatureHeader: req.headers.get("x-signature"),
          requestId: req.headers.get("x-request-id"),
          dataId: signatureDataId,
          secret,
        })
      ) {
        // A global application secret authenticates the provider but does not
        // identify a tenant. Tenant ownership is then established by fetching
        // the resource and matching its external order reference.
        verifiedTenantId = usesTenantSecret ? token.tenant_id : null;
        signatureVerified = true;
        break;
      }
    }

    if (!signatureVerified) {
      console.warn("🔔 [WEBHOOK] ❌ Invalid or unconfigured MercadoPago signature");
      return new Response(JSON.stringify({ error: "Invalid webhook signature" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const verifiedTokens = verifiedTenantId == null
      ? accessTokens
      : accessTokens.filter((token) => token.tenant_id === verifiedTenantId);

    // Handle merchant_order events
    if (type === "merchant_order" || body.topic === "merchant_order") {
      console.log("🔔 [WEBHOOK] Step 4: Processing MERCHANT_ORDER event...");
      const orderId = data?.id;
      if (!orderId) {
        console.log("🔔 [WEBHOOK] Step 4: ⚠️ No order ID in merchant_order event");
        return new Response(JSON.stringify({ status: "ok", message: "No order ID" }), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      console.log("🔔 [WEBHOOK] Step 4a: Fetching merchant order from MP API:", orderId);
      const merchantOrderResult = await fetchMercadoPagoResource(
        verifiedTokens,
        `https://api.mercadopago.com/merchant_orders/${encodeURIComponent(orderId)}`,
        "merchant_order",
      );

      if (!merchantOrderResult.ok) {
        console.error(
          "🔔 [WEBHOOK] Step 4a: ❌ MercadoPago API error:",
          merchantOrderResult.errorText,
        );
        return new Response(
          JSON.stringify({
            error: "MercadoPago API error",
            details: merchantOrderResult.errorText,
          }),
          {
            status: merchantOrderResult.status,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const merchantOrder = merchantOrderResult.data;
      console.log(
        "🔔 [WEBHOOK] Step 4a: ✅ Merchant order fetched, payments:",
        merchantOrder.payments?.length || 0,
      );

      const paymentIds = uniqueMercadoPagoPaymentIds(merchantOrder.payments);
      const processingResults: Array<{
        payment_id: string;
        processing_state: string | null;
      }> = [];
      if (paymentIds.length > 0) {
        for (const paymentId of paymentIds) {
          console.log("🔔 [WEBHOOK] Step 4b: Processing payment ID:", paymentId);
          const result = await processPayment(
            supabase,
            paymentId,
            verifiedTokens,
            merchantOrderResult.token?.tenant_id ?? verifiedTenantId,
          );
          processingResults.push({
            payment_id: paymentId,
            processing_state: result?.processing_state ?? null,
          });
        }
      } else {
        console.log("🔔 [WEBHOOK] Step 4b: ⚠️ No payments in merchant order");
      }

      const processingState = merchantOrderProcessingState(processingResults);

      console.log("🔔 [WEBHOOK] ========== MERCHANT_ORDER COMPLETE ==========");
      return new Response(
        JSON.stringify({
          status: "ok",
          processing_state: processingState,
          action_required: processingState === "action_required",
          payments: processingResults,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Handle payment events
    if (type === "payment") {
      console.log("🔔 [WEBHOOK] Step 4: Processing PAYMENT event...");
      const paymentId = data?.id;
      if (!paymentId) {
        console.log("🔔 [WEBHOOK] Step 4: ⚠️ No payment ID in event");
        return new Response(JSON.stringify({ status: "ok", message: "No payment ID" }), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      console.log("🔔 [WEBHOOK] Step 4a: Payment ID:", paymentId);
      const processingResult = await processPayment(
        supabase,
        paymentId,
        verifiedTokens,
        verifiedTenantId,
      );

      console.log("🔔 [WEBHOOK] ========== PAYMENT COMPLETE ==========");
      return new Response(
        JSON.stringify({
          status: "ok",
          processing_state: processingResult?.processing_state ?? null,
          action_required: processingResult?.processing_state === "action_required",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Unknown event type - still return 200 to acknowledge
    console.log("🔔 [WEBHOOK] ⚠️ Unknown event type:", type, "- acknowledging anyway");
    return new Response(JSON.stringify({ status: "ok", message: "Unknown event type", type }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("🔔 [WEBHOOK] ❌❌❌ FATAL ERROR:", error);
    return new Response(JSON.stringify({ error: "Webhook processing failed" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

async function loadMercadoPagoTokens(supabase: any): Promise<MercadoPagoToken[]> {
  const { data: settings, error } = await supabase
    .from("website_settings")
    .select("tenant_id, key, value")
    .in("key", ["mercadopago_access_token", "mercadopago_webhook_secret"]);

  if (error) {
    console.error("🔔 [WEBHOOK] ❌ Settings query error:", error);
    throw new Error(`Settings query failed: ${error.message}`);
  }

  const byTenant = new Map<string, MercadoPagoToken>();
  for (const setting of settings ?? []) {
    if (typeof setting.value !== "string" || !setting.value.trim()) continue;
    const tenantId = setting.tenant_id ?? null;
    const mapKey = tenantId ?? "__global__";
    const current = byTenant.get(mapKey) ?? {
      tenant_id: tenantId,
      access_token: "",
      webhook_secret: null,
    };
    if (setting.key === "mercadopago_access_token") {
      current.access_token = setting.value.trim();
    } else if (setting.key === "mercadopago_webhook_secret") {
      current.webhook_secret = setting.value.trim();
    }
    byTenant.set(mapKey, current);
  }

  return [...byTenant.values()].filter((credential) => credential.access_token.length > 0);
}

function orderedTokens(
  tokens: MercadoPagoToken[],
  preferredTenantId?: string | null,
): MercadoPagoToken[] {
  if (!preferredTenantId) return tokens;

  return [
    ...tokens.filter((token) => token.tenant_id === preferredTenantId),
    ...tokens.filter((token) => token.tenant_id !== preferredTenantId),
  ];
}

async function fetchMercadoPagoResource(
  tokens: MercadoPagoToken[],
  url: string,
  label: string,
  preferredTenantId?: string | null,
): Promise<{
  ok: boolean;
  status: number;
  data?: any;
  errorText?: string;
  token?: MercadoPagoToken;
}> {
  let lastStatus = 500;
  let lastError = "No configured MercadoPago token could fetch the resource";

  for (const token of orderedTokens(tokens, preferredTenantId)) {
    const response = await fetch(url, {
      headers: {
        "Authorization": `Bearer ${token.access_token}`,
      },
    });

    if (response.ok) {
      return {
        ok: true,
        status: response.status,
        data: await response.json(),
        token,
      };
    }

    lastStatus = response.status;
    let errorPayload: unknown = null;
    try {
      errorPayload = await response.json();
    } catch {
      // A non-JSON body is deliberately discarded. Provider response bodies
      // may contain credentials, payer data, or other untrusted details.
    }
    lastError = summarizeMercadoPagoApiError(errorPayload, label, response.status);
    console.warn(
      `🔔 [WEBHOOK] ${label} fetch failed for tenant ${token.tenant_id ?? "global"}:`,
      lastError,
    );
  }

  return {
    ok: false,
    status: lastStatus,
    errorText: lastError,
  };
}

async function processPayment(
  supabase: any,
  paymentId: string,
  accessTokens: MercadoPagoToken[],
  preferredTenantId: string | null = null,
) {
  console.log("💳 [PROCESS_PAYMENT] ========== START ==========");
  console.log("💳 [PROCESS_PAYMENT] Payment ID:", paymentId);

  // Fetch payment details from MercadoPago
  console.log("💳 [PROCESS_PAYMENT] Step 1: Fetching payment from MP API...");
  let paymentResult = await fetchMercadoPagoResource(
    accessTokens,
    `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
    "payment",
    preferredTenantId,
  );

  if (!paymentResult.ok) {
    console.error("💳 [PROCESS_PAYMENT] Step 1: ❌ MP API error:", paymentResult.errorText);
    throw new Error(`Failed to fetch payment details: ${paymentResult.errorText}`);
  }

  let payment = paymentResult.data;
  console.log("💳 [PROCESS_PAYMENT] Step 1: ✅ Payment fetched");
  console.log("💳 [PROCESS_PAYMENT] - Status:", payment.status);
  console.log("💳 [PROCESS_PAYMENT] - External Reference (Order ID):", payment.external_reference);
  console.log("💳 [PROCESS_PAYMENT] - Amount:", payment.transaction_amount);

  let paymentIdentity = paymentOrderIdentity(payment);
  let status = payment.status;

  if (!paymentIdentity) {
    console.error("💳 [PROCESS_PAYMENT] ❌ Invalid or conflicting payment order identity");
    throw new Error("Payment has no trustworthy order identity");
  }

  const orderId = paymentIdentity.orderId;

  let orderQuery = supabase
    .from("online_orders")
    .select("id, tenant_id, total")
    .eq("id", orderId);
  if (paymentIdentity.tenantId) {
    orderQuery = orderQuery.eq("tenant_id", paymentIdentity.tenantId);
  }
  const { data: order, error: orderError } = await orderQuery.maybeSingle();

  if (orderError) {
    console.error("💳 [PROCESS_PAYMENT] ❌ Order lookup error:", orderError);
    throw new Error(`Failed to look up order: ${orderError.message}`);
  }

  if (!order?.tenant_id) {
    console.error("💳 [PROCESS_PAYMENT] ❌ Order not found for external_reference:", orderId);
    throw new Error(`Order not found for external_reference: ${orderId}`);
  }

  if (paymentResult.token?.tenant_id && paymentResult.token.tenant_id !== order.tenant_id) {
    console.warn(
      "💳 [PROCESS_PAYMENT] Payment token tenant differed from order tenant; retrying exact tenant token.",
      paymentResult.token.tenant_id,
      order.tenant_id,
    );

    const tenantScopedTokens = accessTokens.filter(
      (token) => token.tenant_id === order.tenant_id || token.tenant_id === null,
    );
    const tenantPaymentResult = await fetchMercadoPagoResource(
      tenantScopedTokens,
      `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
      "payment",
      order.tenant_id,
    );

    if (
      !tenantPaymentResult.ok ||
      (tenantPaymentResult.token?.tenant_id &&
        tenantPaymentResult.token.tenant_id !== order.tenant_id)
    ) {
      throw new Error(`Payment ${paymentId} does not match order tenant ${order.tenant_id}`);
    }

    paymentResult = tenantPaymentResult;
    payment = tenantPaymentResult.data;
    paymentIdentity = paymentOrderIdentity(payment);
    if (
      !paymentIdentity ||
      paymentIdentity.orderId !== order.id ||
      (paymentIdentity.tenantId && paymentIdentity.tenantId !== order.tenant_id)
    ) {
      throw new Error(`Payment ${paymentId} changed its order identity during verification`);
    }
    status = payment.status;
  }

  const amount = Number(payment.transaction_amount);
  const currency = String(payment.currency_id ?? "");
  if (!Number.isFinite(amount)) throw new Error("Payment amount is invalid");

  console.log("💳 [PROCESS_PAYMENT] Step 2: Recording provider observation durably...");
  const { data: eventResult, error: eventError } = await supabase.rpc(
    "record_mercadopago_payment_observation",
    {
      p_order_id: orderId,
      p_tenant_id: order.tenant_id,
      p_payment_id: paymentId.toString(),
      p_provider_status: status,
      p_amount: amount,
      p_currency: currency,
      p_paid_at: payment.date_approved ?? null,
      p_provider_payload: buildMercadoPagoPaymentEvidence(payment),
    },
  );

  if (eventError) {
    console.error("💳 [PROCESS_PAYMENT] Step 2: ❌ Observation error:", eventError);
    throw new Error(`Failed to record payment observation: ${eventError.message}`);
  }

  const paymentEventId = eventResult?.event_id;
  if (paymentEventId == null) {
    throw new Error("Payment observation returned no durable event identifier");
  }

  console.log("💳 [PROCESS_PAYMENT] Step 2: ✅ Durable observation:", eventResult);
  console.log("💳 [PROCESS_PAYMENT] Step 3: Processing sale effects independently...");

  const { data: processingResult, error: processingError } = await supabase.rpc(
    "process_mercadopago_payment_observation",
    { p_payment_event_id: paymentEventId },
  );

  if (processingError) {
    console.error("💳 [PROCESS_PAYMENT] Step 3: ❌ Processing RPC error:", processingError);
    throw new Error(`Failed to process durable payment observation: ${processingError.message}`);
  }

  if (processingResult?.processing_state === "action_required") {
    console.warn(
      "💳 [PROCESS_PAYMENT] Step 3: ⚠️ Payment is durable and requires operational attention:",
      processingResult?.error_code,
    );
  } else {
    console.log("💳 [PROCESS_PAYMENT] Step 3: ✅ Sale processing complete");
  }

  const paymentVoucher = await recordMercadoPagoPaymentVoucherIfAvailable({
    supabase,
    payment,
    tenantId: order.tenant_id,
    orderId,
    eventResult,
    processingResult,
  });
  console.log(
    "💳 [PROCESS_PAYMENT] Step 4: Payment voucher producer:",
    paymentVoucher,
  );

  console.log("💳 [PROCESS_PAYMENT] ========== COMPLETE ==========");
  return processingResult;
}
