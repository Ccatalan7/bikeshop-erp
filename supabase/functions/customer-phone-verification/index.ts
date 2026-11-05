// Manda por WhatsApp el código con que una cuenta del portal confirma su
// teléfono (20261105010000). La cuenta llama con su sesión; la base decide si
// puede pedir otro (límites por cuenta y por número) y entrega el código sólo
// a esta función, que lo manda con la plantilla de autenticación y anota lo
// que respondió Meta. El código nunca vuelve a quien llama ni queda en el
// chat: lo confirma `confirm_customer_phone_verification_v1`.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  acceptedMessageId,
  parsePhoneVerificationRequest,
  type PhoneVerificationAnswer,
  phoneVerificationMessage,
  phoneVerificationRefusal,
} from "../_shared/customer_phone_verification.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-region",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WHATSAPP_ACCESS_TOKEN = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
const WHATSAPP_API_VERSION = Deno.env.get("WHATSAPP_API_VERSION") ?? "v23.0";

function answer(body: PhoneVerificationAnswer | Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return answer({ status: "invalid" }, 405);
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !WHATSAPP_ACCESS_TOKEN) {
    console.error("[PHONE-VERIFY] missing environment");
    return answer({ status: "unavailable" }, 500);
  }

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return answer({ status: "not_signed_in" }, 401);
  const request = parsePhoneVerificationRequest(await req.json().catch(() => null));
  if (!request) return answer({ status: "invalid" }, 400);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const userId = userData?.user?.id;
  if (userError || !userId) return answer({ status: "not_signed_in" }, 401);

  const { data: started, error: startError } = await admin.rpc(
    "start_customer_phone_verification_internal",
    { p_tenant_id: request.tenantId, p_auth_user_id: userId, p_phone: request.phone },
  );
  if (startError || !started || typeof started !== "object") {
    console.error("[PHONE-VERIFY] start failed", startError?.code ?? "no_answer");
    return answer({ status: "unavailable" });
  }
  const issued = started as Record<string, unknown>;
  const refusal = phoneVerificationRefusal(issued);
  if (refusal) return answer(refusal);

  const verificationId = String(issued.verification_id);
  const finish = (sent: boolean, messageId: string | null, error: string | null) =>
    admin.rpc("finish_customer_phone_verification_send_internal", {
      p_verification_id: verificationId,
      p_sent: sent,
      p_provider_message_id: messageId,
      p_error: error,
    });

  const { data: channel } = await admin
    .from("whatsapp_channels")
    .select("phone_number_id")
    .eq("tenant_id", request.tenantId)
    .eq("is_active", true)
    .limit(1)
    .maybeSingle();
  const phoneNumberId = channel?.phone_number_id ? String(channel.phone_number_id) : "";
  if (!phoneNumberId) {
    await finish(false, null, "no_channel");
    return answer({ status: "unavailable" });
  }

  let result: unknown = null;
  let ok = false;
  try {
    const response = await fetch(
      `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${phoneNumberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(
          phoneVerificationMessage(String(issued.phone), String(issued.code)),
        ),
        signal: AbortSignal.timeout(20_000),
      },
    );
    ok = response.ok;
    result = await response.json().catch(() => null);
  } catch (error) {
    // Sin respuesta no se sabe si llegó: se anota como no enviado y la
    // cuenta pide otro pasado el minuto.
    console.error("[PHONE-VERIFY] Graph request failed", String(error));
  }
  const messageId = ok ? acceptedMessageId(result) : null;
  const metaError = result && typeof result === "object"
    ? (result as Record<string, unknown>).error
    : null;
  await finish(
    messageId !== null,
    messageId,
    messageId ? null : JSON.stringify(metaError ?? { error: "no_answer" }),
  );
  if (!messageId) {
    console.error("[PHONE-VERIFY] Meta refused", JSON.stringify(metaError ?? {}).slice(0, 300));
    return answer({ status: "not_sent" });
  }
  return answer({
    status: "sent",
    phone_hint: String(issued.phone_hint ?? ""),
    expires_at: String(issued.expires_at ?? ""),
  });
});
