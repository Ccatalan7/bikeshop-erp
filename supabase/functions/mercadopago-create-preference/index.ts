import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  authorizePublicOrderAccess,
  PublicOrderAccessDeniedError,
} from "../_shared/public_order_access.ts";
import {
  buildMercadoPagoCharge,
  mercadoPagoPaymentMethodPolicy,
  parseMercadoPagoExternalReference,
} from "../_shared/mercadopago_preference.ts";
import {
  expireMercadoPagoPreferencePayload,
  parseRecoverableMercadoPagoPreference,
  preferenceSearchIds,
} from "../_shared/mercadopago_preference_lifecycle.ts";
import { summarizeMercadoPagoApiError } from "../_shared/mercadopago_webhook_resources.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type JsonRecord = Record<string, unknown>;

function json(body: JsonRecord, status = 200, extraHeaders: HeadersInit = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}

function record(value: unknown): JsonRecord {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

function trustedStoreBaseUrl(
  configuredStoreUrl: unknown,
  customDomain: unknown,
): URL {
  const candidates = [
    typeof configuredStoreUrl === "string" ? configuredStoreUrl.trim() : "",
    typeof customDomain === "string" && customDomain.trim()
      ? `https://${customDomain.trim().toLowerCase()}`
      : "",
  ];

  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      const url = new URL(candidate);
      if (url.protocol !== "https:" || !url.hostname) continue;
      url.username = "";
      url.password = "";
      url.search = "";
      url.hash = "";
      return url;
    } catch {
      // Try the next server-owned candidate.
    }
  }

  throw new Error(
    "A secure public store URL must be configured before accepting Mercado Pago payments",
  );
}

function returnUrls(storeBase: URL, orderId: string) {
  const make = (status: string) => {
    const url = new URL(`/pedido/${encodeURIComponent(orderId)}`, storeBase);
    url.searchParams.set("status", status);
    return url.toString();
  };
  return {
    success: make("success"),
    pending: make("pending"),
    failure: make("failure"),
  };
}

async function sha256Hex(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function providerJson(response: Response): Promise<JsonRecord> {
  try {
    return record(await response.json());
  } catch {
    return {};
  }
}

async function recoverPreference(params: {
  accessToken: string;
  externalReference: string;
  amount: number;
  expiresAt: string;
}) {
  const searchUrl = new URL("https://api.mercadopago.com/checkout/preferences/search");
  searchUrl.searchParams.set("external_reference", params.externalReference);
  searchUrl.searchParams.set("limit", "20");
  searchUrl.searchParams.set("offset", "0");

  const searchResponse = await fetch(searchUrl, {
    headers: { Authorization: `Bearer ${params.accessToken}` },
  });
  const searchPayload = await providerJson(searchResponse);
  if (!searchResponse.ok) {
    throw new Error(
      summarizeMercadoPagoApiError(searchPayload, "preference search", searchResponse.status),
    );
  }

  const candidateIds = preferenceSearchIds(searchPayload);
  for (const candidateId of candidateIds) {
    const response = await fetch(
      `https://api.mercadopago.com/checkout/preferences/${encodeURIComponent(candidateId)}`,
      { headers: { Authorization: `Bearer ${params.accessToken}` } },
    );
    const payload = await providerJson(response);
    if (response.status === 404) continue;
    if (!response.ok) {
      throw new Error(
        summarizeMercadoPagoApiError(payload, "preference recovery", response.status),
      );
    }

    const recovered = parseRecoverableMercadoPagoPreference(payload, params);
    if (recovered) return recovered;
  }

  if (candidateIds.length > 0) {
    throw new Error("Provider preference recovery conflicted with the server order snapshot");
  }
  return null;
}

async function completeExpiration(
  supabase: any,
  params: {
    recordId: string;
    leaseToken: string;
    result: "expired" | "retry";
    providerPreferenceId: string;
    errorCode?: string;
    errorMessage?: string;
    providerStatus?: number;
  },
) {
  const { error } = await supabase.rpc(
    "complete_mercadopago_preference_expiration",
    {
      p_preference_record_id: params.recordId,
      p_lease_token: params.leaseToken,
      p_result: params.result,
      p_provider_preference_id: params.providerPreferenceId,
      p_error_code: params.errorCode ?? null,
      p_error_message: params.errorMessage ?? null,
      p_provider_status: params.providerStatus ?? null,
    },
  );
  if (error) throw new Error(`Could not record preference expiration: ${error.message}`);
}

async function expireInline(
  supabase: any,
  params: {
    accessToken: string;
    recordId: string;
    leaseToken: string;
    providerPreferenceId: string;
    effectiveFrom: string | null;
  },
) {
  const response = await fetch(
    `https://api.mercadopago.com/checkout/preferences/${
      encodeURIComponent(params.providerPreferenceId)
    }`,
    {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${params.accessToken}`,
      },
      body: JSON.stringify(
        expireMercadoPagoPreferencePayload(new Date(), params.effectiveFrom),
      ),
    },
  );
  const payload = await providerJson(response);
  if (response.ok || response.status === 404) {
    await completeExpiration(supabase, {
      recordId: params.recordId,
      leaseToken: params.leaseToken,
      result: "expired",
      providerPreferenceId: params.providerPreferenceId,
      providerStatus: response.status,
    });
    return;
  }

  const summary = summarizeMercadoPagoApiError(
    payload,
    "preference expiration",
    response.status,
  );
  await completeExpiration(supabase, {
    recordId: params.recordId,
    leaseToken: params.leaseToken,
    result: "retry",
    providerPreferenceId: params.providerPreferenceId,
    errorCode: `provider_http_${response.status}`,
    errorMessage: summary,
    providerStatus: response.status,
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const leaseToken = crypto.randomUUID();
  let preferenceRecordId: string | null = null;
  let accessToken: string | null = null;
  let supabase: any = null;

  try {
    const requestBody = await req.json();
    supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // This is the first privileged operation. A public UUID never authorizes
    // order, tenant, reservation, preference, or credential reads by itself.
    const { orderId } = await authorizePublicOrderAccess(supabase, requestBody);

    const { data: order, error: orderError } = await supabase
      .from("online_orders")
      .select(`
        id, tenant_id, order_number, total, customer_email, customer_name,
        payment_method, payment_status, status, delivery_type, shipping_cost,
        discount_amount, shipping_address_line1, shipping_address_line2,
        shipping_city, shipping_state, shipping_postal_code, shipping_country
      `)
      .eq("id", orderId)
      .maybeSingle();
    if (orderError) throw new Error(`Order lookup failed: ${orderError.message}`);
    if (!order) throw new Error("Order not found");

    const { data: orderItems, error: itemError } = await supabase
      .from("online_order_items")
      .select("id, product_id, product_name, product_sku, quantity, unit_price, subtotal")
      .eq("order_id", order.id)
      .eq("tenant_id", order.tenant_id)
      .order("id");
    if (itemError) throw new Error(`Order items lookup failed: ${itemError.message}`);
    if (!orderItems?.length) throw new Error("Order has no items");

    const charge = buildMercadoPagoCharge(order, orderItems);

    const { data: settings, error: settingsError } = await supabase
      .from("website_settings")
      .select("key, value")
      .eq("tenant_id", order.tenant_id)
      .in("key", ["mercadopago_access_token", "store_url"]);
    if (settingsError) throw new Error(`Payment settings lookup failed: ${settingsError.message}`);
    accessToken = settings?.find((setting: any) =>
      setting.key === "mercadopago_access_token"
    )?.value?.trim() || null;
    const storeUrlSetting = settings?.find((setting: any) => setting.key === "store_url")
      ?.value;
    if (!accessToken) throw new Error("MercadoPago not configured for this tenant");

    const { data: tenant, error: tenantError } = await supabase
      .from("tenants")
      .select("custom_domain")
      .eq("id", order.tenant_id)
      .maybeSingle();
    if (tenantError) throw new Error(`Tenant lookup failed: ${tenantError.message}`);

    const storeBase = trustedStoreBaseUrl(storeUrlSetting, tenant?.custom_domain);
    const backUrls = returnUrls(storeBase, order.id);
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const notificationUrl = new URL(
      "/functions/v1/mercadopago-webhook",
      supabaseUrl,
    ).toString();
    const receiverAddress = order.delivery_type === "shipping"
      ? {
        zip_code: order.shipping_postal_code ?? undefined,
        street_name: [order.shipping_address_line1, order.shipping_address_line2]
          .filter((value) => typeof value === "string" && value.trim())
          .join(", ") || undefined,
        city_name: order.shipping_city ?? undefined,
        state_name: order.shipping_state ?? undefined,
        country_name: order.shipping_country ?? "Chile",
      }
      : null;

    const requestFingerprint = await sha256Hex({
      charge,
      payer: { email: order.customer_email, name: order.customer_name },
      receiverAddress,
      backUrls,
      notificationUrl,
      paymentMethods: mercadoPagoPaymentMethodPolicy(),
      statementDescriptor: `Pedido ${order.order_number}`,
    });

    const { data: begun, error: beginError } = await supabase.rpc(
      "begin_mercadopago_preference_creation",
      {
        p_order_id: order.id,
        p_request_fingerprint: requestFingerprint,
        p_lease_token: leaseToken,
        p_lease_owner: `edge:${leaseToken}`,
        p_lease_seconds: 45,
      },
    );
    if (beginError) throw new Error(`Payment preference unavailable: ${beginError.message}`);

    const receipt = record(begun);
    const action = receipt.action?.toString() ?? "";
    if (action === "busy") {
      const retryAfter = Math.max(1, Number(receipt.retry_after_seconds) || 2);
      return json(
        { error: "Payment checkout is already being prepared", retry_after_seconds: retryAfter },
        409,
        { "Retry-After": String(retryAfter) },
      );
    }
    if (action === "unavailable") {
      return json({ error: "Payment is not available for this order" }, 409);
    }

    preferenceRecordId = receipt.id?.toString() ?? null;
    const externalReference = receipt.external_reference?.toString() ?? "";
    const expiresAt = receipt.expires_at?.toString() ?? "";
    const effectiveFrom = receipt.effective_from?.toString() ?? "";
    const amount = Number(receipt.amount);
    const identity = parseMercadoPagoExternalReference(externalReference);
    if (
      !preferenceRecordId ||
      !identity ||
      identity.tenantId !== order.tenant_id ||
      identity.orderId !== order.id ||
      !Number.isSafeInteger(amount) ||
      amount !== charge.chargeTotal ||
      !Number.isFinite(Date.parse(expiresAt)) ||
      !Number.isFinite(Date.parse(effectiveFrom))
    ) {
      throw new Error("Payment preference receipt conflicts with the order snapshot");
    }

    if (action === "replay") {
      return json({
        id: receipt.provider_preference_id,
        init_point: receipt.init_point,
        sandbox_init_point: receipt.sandbox_init_point,
        expires_at: expiresAt,
        replay: true,
      });
    }
    if (action !== "recover_or_create") {
      throw new Error("Payment preference begin command returned an invalid action");
    }

    let providerPreference = await recoverPreference({
      accessToken,
      externalReference,
      amount,
      expiresAt,
    });

    if (!providerPreference) {
      const providerRequest = {
        items: charge.items,
        payer: { email: order.customer_email, name: order.customer_name },
        ...(receiverAddress
          ? {
            shipments: {
              local_pickup: false,
              cost: charge.shippingCost,
              receiver_address: receiverAddress,
            },
          }
          : { shipments: { local_pickup: true } }),
        back_urls: backUrls,
        auto_return: "approved",
        payment_methods: mercadoPagoPaymentMethodPolicy(),
        notification_url: notificationUrl,
        external_reference: externalReference,
        expires: true,
        expiration_date_from: effectiveFrom,
        expiration_date_to: expiresAt,
        statement_descriptor: `Pedido ${order.order_number}`,
        metadata: {
          tenant_id: order.tenant_id,
          online_order_id: order.id,
          order_number: order.order_number,
          preference_generation: identity.generation,
        },
      };

      const response = await fetch("https://api.mercadopago.com/checkout/preferences", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify(providerRequest),
      });
      const payload = await providerJson(response);
      if (!response.ok) {
        const summary = summarizeMercadoPagoApiError(
          payload,
          "preference creation",
          response.status,
        );
        await supabase.rpc("record_mercadopago_preference_create_failure", {
          p_preference_record_id: preferenceRecordId,
          p_lease_token: leaseToken,
          p_outcome: response.status >= 500 ? "outcome_unknown" : "definite_failure",
          p_error_code: `provider_http_${response.status}`,
          p_error_message: summary,
          p_provider_status: response.status,
        });
        throw new Error("MercadoPago rejected the payment preference");
      }

      providerPreference = parseRecoverableMercadoPagoPreference(payload, {
        externalReference,
        amount,
        expiresAt,
      });
      if (!providerPreference) {
        await supabase.rpc("record_mercadopago_preference_create_failure", {
          p_preference_record_id: preferenceRecordId,
          p_lease_token: leaseToken,
          p_outcome: "outcome_unknown",
          p_error_code: "invalid_provider_success",
          p_error_message: "Mercado Pago returned a success that did not match the order snapshot.",
          p_provider_status: response.status,
        });
        throw new Error("MercadoPago returned an invalid payment preference");
      }
    }

    const { data: finalized, error: finalizeError } = await supabase.rpc(
      "finalize_mercadopago_preference_creation",
      {
        p_preference_record_id: preferenceRecordId,
        p_lease_token: leaseToken,
        p_provider_preference_id: providerPreference.id,
        p_init_point: providerPreference.initPoint,
        p_sandbox_init_point: providerPreference.sandboxInitPoint,
        p_provider_created_at: providerPreference.createdAt,
        p_provider_expires_at: providerPreference.expiresAt,
      },
    );
    if (finalizeError) {
      // Provider success is an unknown local outcome. The same external
      // reference will be searched and adopted on the next request.
      throw new Error(`Payment preference could not be committed: ${finalizeError.message}`);
    }

    const finalReceipt = record(finalized);
    if (finalReceipt.payable !== true && finalReceipt.state !== "active") {
      await expireInline(supabase, {
        accessToken,
        recordId: preferenceRecordId,
        leaseToken,
        providerPreferenceId: providerPreference.id,
        effectiveFrom,
      });
      return json({ error: "Order is no longer payable" }, 409);
    }

    return json({
      id: providerPreference.id,
      init_point: providerPreference.initPoint,
      sandbox_init_point: providerPreference.sandboxInitPoint,
      expires_at: providerPreference.expiresAt,
      replay: finalReceipt.replay === true,
    });
  } catch (error) {
    const accessDenied = error instanceof PublicOrderAccessDeniedError;
    const message = error instanceof Error ? error.message : "Unknown error";

    // Network/timeout failures after the begin lease have unknown provider
    // outcome. Preserve the creating row so the next click searches by the
    // deterministic external reference before considering another POST.
    if (
      !accessDenied &&
      supabase &&
      preferenceRecordId &&
      accessToken &&
      /(network|fetch|timeout|connection|could not be committed)/i.test(message)
    ) {
      await supabase.rpc("record_mercadopago_preference_create_failure", {
        p_preference_record_id: preferenceRecordId,
        p_lease_token: leaseToken,
        p_outcome: "outcome_unknown",
        p_error_code: "provider_outcome_unknown",
        p_error_message:
          "Provider preference outcome is unknown; recovery is required before retry.",
        p_provider_status: null,
      });
    }

    const conflict = /no longer payable|reservation|already exists|unavailable/i.test(message);
    return json(
      {
        error: accessDenied
          ? "Order access denied"
          : conflict
          ? "Payment is not available for this order"
          : "Unable to prepare Mercado Pago checkout",
      },
      accessDenied ? 403 : conflict ? 409 : 400,
    );
  }
});
