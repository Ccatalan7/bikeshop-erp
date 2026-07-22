import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  buildMetaDebugTokenUrl,
  buildMetaOAuthAuthorizationUrl,
  buildMetaSystemUserTokenExchangeUrl,
  earliestMetaTokenExpiresAt,
  missingRequiredMetaPageTasks,
  parseMetaDebugTokenEvidence,
  parseMetaLoginConfigId,
  parseMetaSystemUserBusinessIdentity,
  resolveMetaSystemUserTokenExpiresAt,
} from "../_shared/meta_oauth_authorization.ts";
import {
  missingRequestedMetaOAuthScopes,
  missingRequiredMetaPageTokenScopes,
} from "../_shared/meta_oauth_permissions.ts";
import {
  confirmMetaPageSubscription,
  META_PAGE_SUBSCRIPTION_FIELDS,
} from "../_shared/meta_subscription_confirmation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const META_APP_ID = Deno.env.get("META_APP_ID") ?? "";
const META_APP_SECRET = Deno.env.get("META_APP_SECRET") ?? "";
const META_OAUTH_REDIRECT_URI = Deno.env.get("META_OAUTH_REDIRECT_URI") ?? "";
const META_LOGIN_CONFIG_ID = parseMetaLoginConfigId(
  Deno.env.get("META_LOGIN_CONFIG_ID"),
);
const META_ALLOWED_PAGE_IDS = new Set(
  (Deno.env.get("META_ALLOWED_PAGE_IDS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
);
const configuredVersion = Deno.env.get("META_GRAPH_VERSION") ?? "v25.0";
const META_GRAPH_VERSION = /^v\d+\.\d+$/.test(configuredVersion) ? configuredVersion : "v25.0";

type JsonRecord = Record<string, unknown>;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function htmlResponse(title: string, message: string, success: boolean) {
  return new Response(
    `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>${title}</title><style>
body{font-family:system-ui,-apple-system,sans-serif;background:#f5f7fa;color:#1d2733;display:grid;place-items:center;min-height:100vh;margin:0}
main{max-width:520px;background:white;border:1px solid #dce3ea;border-radius:16px;padding:32px;box-shadow:0 12px 36px #13213a18}
h1{font-size:22px;margin:0 0 12px;color:${
      success ? "#177245" : "#a33434"
    }}p{line-height:1.5;margin:0}
</style></head><body><main><h1>${title}</h1><p>${message}</p></main></body></html>`,
    {
      status: success ? 200 : 400,
      headers: { "Content-Type": "text/html; charset=utf-8" },
    },
  );
}

function stringValue(value: unknown, maxLength = Number.MAX_SAFE_INTEGER) {
  if (typeof value !== "string") return null;
  const result = value.trim();
  return result && result.length <= maxLength ? result : null;
}

function uuidValue(value: unknown) {
  const result = stringValue(value, 36);
  return result &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        .test(result)
    ? result.toLowerCase()
    : null;
}

function randomState() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function graphJson(url: URL, init?: RequestInit) {
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(20_000),
  });
  let data: JsonRecord = {};
  try {
    const parsed = await response.json();
    if (parsed && typeof parsed === "object") data = parsed as JsonRecord;
  } catch {
    // The caller receives only a phase/status error; provider bodies are never logged.
  }
  if (!response.ok) throw new Error(`graph_http_${response.status}`);
  return data;
}

async function subscribePage(
  pageId: string,
  token: string,
  fields: readonly string[],
) {
  return await confirmMetaPageSubscription({
    pageId,
    token,
    fields,
    appId: META_APP_ID,
    graphVersion: META_GRAPH_VERSION,
  });
}

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (
    !SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY ||
    !META_APP_ID || !META_APP_SECRET || !META_OAUTH_REDIRECT_URI ||
    !META_LOGIN_CONFIG_ID ||
    META_ALLOWED_PAGE_IDS.size === 0
  ) {
    console.error("[META-OAUTH] Required server configuration is absent");
    return jsonResponse({ ok: false, error: "server_not_configured" }, 503);
  }

  const url = new URL(request.url);
  const action = url.searchParams.get("action") ??
    (request.method === "POST" ? "start" : "callback");
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  if (action === "start") {
    if (request.method !== "POST") {
      return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
    }
    const authorization = request.headers.get("authorization") ?? "";
    const jwt = authorization.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) return jsonResponse({ ok: false, error: "unauthorized" }, 401);
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(jwt);
    if (userError || !userData.user) {
      return jsonResponse({ ok: false, error: "unauthorized" }, 401);
    }

    let body: JsonRecord;
    try {
      const parsed = await request.json();
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error("invalid_body");
      }
      body = parsed as JsonRecord;
    } catch {
      return jsonResponse({ ok: false, error: "invalid_request" }, 400);
    }
    const tenantId = uuidValue(body.tenantId);
    if (!tenantId) {
      return jsonResponse({ ok: false, error: "invalid_tenant_id" }, 400);
    }

    const state = randomState();
    const stateHash = await sha256Hex(state);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const { error: stateError } = await adminClient.rpc("create_meta_oauth_state", {
      p_actor_id: userData.user.id,
      p_tenant_id: tenantId,
      p_state_hash: stateHash,
      p_redirect_uri: META_OAUTH_REDIRECT_URI,
      p_expires_at: expiresAt,
    });
    if (stateError) {
      const forbidden = stateError.code === "42501";
      return jsonResponse({
        ok: false,
        error: forbidden ? "admin_or_manager_required" : "oauth_state_failed",
      }, forbidden ? 403 : 500);
    }

    const authorizeUrl = buildMetaOAuthAuthorizationUrl({
      graphVersion: META_GRAPH_VERSION,
      appId: META_APP_ID,
      redirectUri: META_OAUTH_REDIRECT_URI,
      state,
      loginConfigId: META_LOGIN_CONFIG_ID,
    });
    return jsonResponse({
      ok: true,
      client_id: META_APP_ID,
      authorization_url: authorizeUrl.toString(),
      expires_at: expiresAt,
    });
  }

  if (request.method !== "GET") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }
  const state = stringValue(url.searchParams.get("state"), 200);
  if (!state) return htmlResponse("Conexión rechazada", "El estado OAuth no es válido.", false);
  const stateHash = await sha256Hex(state);
  const { data: stateData, error: stateError } = await adminClient.rpc(
    "consume_meta_oauth_state",
    { p_state_hash: stateHash },
  );
  if (stateError || !stateData) {
    return htmlResponse(
      "Conexión expirada",
      "Este enlace ya fue usado o expiró. Inicia la conexión nuevamente desde el ERP.",
      false,
    );
  }
  const oauthState = stateData as JsonRecord;
  if (oauthState.redirect_uri !== META_OAUTH_REDIRECT_URI) {
    return htmlResponse("Conexión rechazada", "La redirección OAuth no coincide.", false);
  }
  if (url.searchParams.has("error")) {
    return htmlResponse(
      "Conexión cancelada",
      "Meta no autorizó la conexión. Puedes volver al ERP e intentarlo nuevamente.",
      false,
    );
  }
  const code = stringValue(url.searchParams.get("code"), 4_000);
  if (!code) return htmlResponse("Conexión rechazada", "Meta no entregó un código.", false);

  try {
    const tokenUrl = buildMetaSystemUserTokenExchangeUrl({
      graphVersion: META_GRAPH_VERSION,
      appId: META_APP_ID,
      appSecret: META_APP_SECRET,
      redirectUri: META_OAUTH_REDIRECT_URI,
      code,
    });
    const systemUserTokenData = await graphJson(tokenUrl);
    const tokenReceivedAtMilliseconds = Date.now();
    const systemUserToken = stringValue(systemUserTokenData.access_token, 20_000);
    if (!systemUserToken) throw new Error("system_user_token_missing");

    const appAccessToken = `${META_APP_ID}|${META_APP_SECRET}`;
    const systemUserDebugData = await graphJson(
      buildMetaDebugTokenUrl(META_GRAPH_VERSION, systemUserToken),
      { headers: { Authorization: `Bearer ${appAccessToken}` } },
    );
    const systemUserEvidence = parseMetaDebugTokenEvidence(
      systemUserDebugData,
      {
        expectedAppId: META_APP_ID,
        nowMilliseconds: Date.now(),
      },
    );
    if (
      missingRequestedMetaOAuthScopes(systemUserEvidence.grantedScopes).length >
        0
    ) {
      throw new Error("system_user_required_scopes_missing");
    }
    const systemUserTokenExpiresAt = resolveMetaSystemUserTokenExpiresAt(
      systemUserEvidence,
      systemUserTokenData,
      tokenReceivedAtMilliseconds,
    );

    const businessIdentityUrl = new URL(
      `https://graph.facebook.com/${META_GRAPH_VERSION}/me`,
    );
    businessIdentityUrl.searchParams.set("fields", "id,client_business_id");
    const businessIdentityData = await graphJson(businessIdentityUrl, {
      headers: { Authorization: `Bearer ${systemUserToken}` },
    });
    parseMetaSystemUserBusinessIdentity(
      businessIdentityData,
      systemUserEvidence.subjectId,
    );

    const pagesUrl = new URL(
      `https://graph.facebook.com/${META_GRAPH_VERSION}/me/accounts`,
    );
    pagesUrl.searchParams.set(
      "fields",
      "id,name,access_token,tasks,instagram_business_account{id,username,name}",
    );
    pagesUrl.searchParams.set("limit", "100");
    const pagesData = await graphJson(pagesUrl, {
      headers: { Authorization: `Bearer ${systemUserToken}` },
    });
    const pages = Array.isArray(pagesData.data) ? pagesData.data : [];
    const tenantId = stringValue(oauthState.tenant_id, 100);
    if (!tenantId) throw new Error("oauth_tenant_missing");

    let channelsStored = 0;
    for (const rawPage of pages) {
      if (!rawPage || typeof rawPage !== "object") continue;
      const page = rawPage as JsonRecord;
      const pageId = stringValue(page.id, 512);
      const pageName = stringValue(page.name, 500);
      const pageToken = stringValue(page.access_token, 20_000);
      if (!pageId || !pageToken || !META_ALLOWED_PAGE_IDS.has(pageId)) continue;
      if (missingRequiredMetaPageTasks(page.tasks).length > 0) {
        throw new Error("page_required_tasks_missing");
      }

      const instagram = page.instagram_business_account &&
          typeof page.instagram_business_account === "object"
        ? page.instagram_business_account as JsonRecord
        : null;
      const instagramId = stringValue(instagram?.id, 512);

      const pageDebugData = await graphJson(
        buildMetaDebugTokenUrl(META_GRAPH_VERSION, pageToken),
        { headers: { Authorization: `Bearer ${appAccessToken}` } },
      );
      const pageTokenEvidence = parseMetaDebugTokenEvidence(pageDebugData, {
        expectedAppId: META_APP_ID,
        nowMilliseconds: Date.now(),
      });
      if (
        pageTokenEvidence.profileId !== null &&
        pageTokenEvidence.profileId !== pageId
      ) {
        throw new Error("page_token_profile_mismatch");
      }
      const grantedScopes = [...pageTokenEvidence.grantedScopes];
      if (
        missingRequiredMetaPageTokenScopes(
          "facebook_messenger",
          grantedScopes,
        ).length > 0
      ) {
        throw new Error("page_token_required_scopes_missing");
      }
      if (
        instagramId &&
        missingRequiredMetaPageTokenScopes("instagram", grantedScopes).length >
          0
      ) {
        throw new Error("instagram_page_token_required_scopes_missing");
      }
      const pageTokenExpiresAt = earliestMetaTokenExpiresAt(
        systemUserTokenExpiresAt,
        pageTokenEvidence.tokenExpiresAt,
      );

      if (
        !await subscribePage(
          pageId,
          pageToken,
          META_PAGE_SUBSCRIPTION_FIELDS,
        )
      ) {
        throw new Error("page_subscription_failed");
      }
      // Facebook Login for Business enables linked Instagram webhooks through
      // the confirmed Page installation. Instagram object fields are configured
      // once at the app level in Meta App Dashboard, not through
      // /{instagram-id}/subscribed_apps with this Page access token.

      const { data: pageChannel, error: pageStoreError } = await adminClient.rpc(
        "store_meta_channel_credential",
        {
          p_tenant_id: tenantId,
          p_provider: "facebook_messenger",
          p_external_account_id: pageId,
          p_display_name: pageName,
          p_username: null,
          p_access_token: pageToken,
          p_granted_scopes: grantedScopes,
          p_token_expires_at: pageTokenExpiresAt,
        },
      );
      if (pageStoreError || !pageChannel) throw new Error("page_credential_store_failed");
      channelsStored += 1;
      const { error: pageSubscriptionStoreError } = await adminClient.rpc(
        "mark_meta_channel_subscribed",
        { p_channel_id: String((pageChannel as JsonRecord).channel_id) },
      );
      if (pageSubscriptionStoreError) {
        throw new Error("page_subscription_store_failed");
      }

      if (!instagramId) continue;
      const { data: instagramChannel, error: instagramStoreError } = await adminClient.rpc(
        "store_meta_channel_credential",
        {
          p_tenant_id: tenantId,
          p_provider: "instagram",
          p_external_account_id: instagramId,
          p_display_name: stringValue(instagram?.name, 500) ?? pageName,
          p_username: stringValue(instagram?.username, 500),
          p_access_token: pageToken,
          p_granted_scopes: grantedScopes,
          p_token_expires_at: pageTokenExpiresAt,
        },
      );
      if (instagramStoreError || !instagramChannel) {
        throw new Error("instagram_credential_store_failed");
      }
      channelsStored += 1;
      const { error: instagramSubscriptionStoreError } = await adminClient.rpc(
        "mark_meta_channel_subscribed",
        { p_channel_id: String((instagramChannel as JsonRecord).channel_id) },
      );
      if (instagramSubscriptionStoreError) {
        throw new Error("instagram_subscription_store_failed");
      }
    }

    if (channelsStored === 0) {
      return htmlResponse(
        "Sin cuentas disponibles",
        "Meta autorizó el acceso, pero no devolvió Pages administrables vinculadas a esta cuenta.",
        false,
      );
    }
    return htmlResponse(
      "Meta conectado",
      `Se guardaron y suscribieron ${channelsStored} canales. Ya puedes volver al ERP.`,
      true,
    );
  } catch (error) {
    const phase = error instanceof Error ? error.message : "oauth_callback_failed";
    console.error("[META-OAUTH] Callback failed", phase);
    return htmlResponse(
      "No se pudo conectar Meta",
      "La autorización no se completó. No se expuso ninguna credencial; vuelve al ERP e inténtalo nuevamente.",
      false,
    );
  }
});
