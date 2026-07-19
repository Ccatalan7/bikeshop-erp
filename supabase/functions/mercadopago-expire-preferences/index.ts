import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  expireMercadoPagoPreferencePayload,
  parseRecoverableMercadoPagoPreference,
  preferenceSearchIds,
} from "../_shared/mercadopago_preference_lifecycle.ts";
import { summarizeMercadoPagoApiError } from "../_shared/mercadopago_webhook_resources.ts";

type JsonRecord = Record<string, unknown>;

function json(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  const length = Math.max(a.length, b.length);
  let mismatch = a.length ^ b.length;
  for (let index = 0; index < length; index += 1) {
    mismatch |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return mismatch === 0;
}

function authorized(request: Request, secret: string): boolean {
  if (!secret) return false;
  const supplied = request.headers.get("x-mercadopago-preference-worker-secret") ?? "";
  return constantTimeEqual(supplied, secret);
}

function record(value: unknown): JsonRecord {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : {};
}

async function providerJson(response: Response): Promise<JsonRecord> {
  try {
    return record(await response.json());
  } catch {
    return {};
  }
}

async function recoverProviderId(params: {
  accessToken: string;
  externalReference: string;
  amount: number;
  expiresAt: string;
}): Promise<string | null> {
  const url = new URL("https://api.mercadopago.com/checkout/preferences/search");
  url.searchParams.set("external_reference", params.externalReference);
  url.searchParams.set("limit", "20");
  const search = await fetch(url, {
    headers: { Authorization: `Bearer ${params.accessToken}` },
  });
  const payload = await providerJson(search);
  if (!search.ok) {
    throw new Error(
      summarizeMercadoPagoApiError(payload, "preference expiration recovery", search.status),
    );
  }

  const candidateIds = preferenceSearchIds(payload);
  for (const candidateId of candidateIds) {
    const response = await fetch(
      `https://api.mercadopago.com/checkout/preferences/${encodeURIComponent(candidateId)}`,
      { headers: { Authorization: `Bearer ${params.accessToken}` } },
    );
    const candidate = await providerJson(response);
    if (response.status === 404) continue;
    if (!response.ok) {
      throw new Error(
        summarizeMercadoPagoApiError(candidate, "preference recovery", response.status),
      );
    }
    const recovered = parseRecoverableMercadoPagoPreference(candidate, params);
    if (recovered) return recovered.id;
  }
  if (candidateIds.length > 0) {
    throw new Error("Provider preference candidates conflict with durable order evidence");
  }
  return null;
}

async function complete(supabase: any, row: JsonRecord, params: {
  result: "expired" | "provider_absent" | "retry";
  providerPreferenceId?: string | null;
  errorCode?: string;
  errorMessage?: string;
  providerStatus?: number;
}) {
  const { error } = await supabase.rpc(
    "complete_mercadopago_preference_expiration",
    {
      p_preference_record_id: row.id,
      p_lease_token: row.lease_token,
      p_result: params.result,
      p_provider_preference_id: params.providerPreferenceId ?? null,
      p_error_code: params.errorCode ?? null,
      p_error_message: params.errorMessage ?? null,
      p_provider_status: params.providerStatus ?? null,
    },
  );
  if (error) throw new Error(`Expiration completion failed: ${error.message}`);
}

serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const workerSecret = Deno.env.get("MERCADOPAGO_PREFERENCE_WORKER_SECRET") ?? "";
  if (!authorized(request, workerSecret)) return json({ error: "Unauthorized" }, 401);

  let requestedLimit = 20;
  try {
    const payload = record(await request.json());
    if (payload.action !== "process") return json({ error: "Invalid action" }, 400);
    requestedLimit = Math.min(50, Math.max(1, Math.trunc(Number(payload.limit) || 20)));
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const workerId = `mercadopago-expiry:${crypto.randomUUID()}`;
  const { data, error } = await supabase.rpc(
    "claim_mercadopago_preference_expirations",
    { p_worker_id: workerId, p_limit: requestedLimit, p_lease_seconds: 90 },
  );
  if (error) return json({ error: "Could not claim preference expirations" }, 500);

  const rows = Array.isArray(data) ? data.map(record) : [];
  let expired = 0;
  let absent = 0;
  let retry = 0;

  for (const row of rows) {
    let providerPreferenceId = typeof row.provider_preference_id === "string"
      ? row.provider_preference_id.trim()
      : "";
    try {
      const tenantId = row.tenant_id?.toString() ?? "";
      const { data: settings, error: settingsError } = await supabase
        .from("website_settings")
        .select("value")
        .eq("tenant_id", tenantId)
        .eq("key", "mercadopago_access_token")
        .limit(1);
      if (settingsError) throw new Error("Tenant payment credential lookup failed");
      const accessToken = settings?.[0]?.value?.trim() ?? "";
      if (!accessToken) throw new Error("Tenant Mercado Pago credential is unavailable");

      if (!providerPreferenceId) {
        providerPreferenceId = await recoverProviderId({
          accessToken,
          externalReference: row.external_reference?.toString() ?? "",
          amount: Number(row.amount),
          expiresAt: row.expires_at?.toString() ?? "",
        }) ?? "";
      }

      if (!providerPreferenceId) {
        await complete(supabase, row, { result: "provider_absent" });
        absent += 1;
        continue;
      }

      const response = await fetch(
        `https://api.mercadopago.com/checkout/preferences/${
          encodeURIComponent(providerPreferenceId)
        }`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(expireMercadoPagoPreferencePayload(
            new Date(),
            row.effective_from?.toString() ?? null,
          )),
        },
      );
      const payload = await providerJson(response);
      if (response.ok) {
        await complete(supabase, row, {
          result: "expired",
          providerPreferenceId,
          providerStatus: response.status,
        });
        expired += 1;
        continue;
      }
      if (response.status === 404) {
        await complete(supabase, row, {
          result: "provider_absent",
          providerPreferenceId,
          providerStatus: response.status,
        });
        absent += 1;
        continue;
      }

      const summary = summarizeMercadoPagoApiError(
        payload,
        "preference expiration",
        response.status,
      );
      await complete(supabase, row, {
        result: "retry",
        providerPreferenceId,
        errorCode: `provider_http_${response.status}`,
        errorMessage: summary,
        providerStatus: response.status,
      });
      retry += 1;
    } catch (workerError) {
      const message = workerError instanceof Error
        ? workerError.message.slice(0, 320)
        : "Unexpected preference expiration error";
      try {
        await complete(supabase, row, {
          result: "retry",
          providerPreferenceId: providerPreferenceId || null,
          errorCode: "worker_unexpected_error",
          errorMessage: message,
        });
      } catch {
        // The lease may have been recovered by another invocation. Do not leak
        // row/provider details in the HTTP response or logs.
      }
      retry += 1;
    }
  }

  return json({ claimed: rows.length, expired, provider_absent: absent, retry });
});
