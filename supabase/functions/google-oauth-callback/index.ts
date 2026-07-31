import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const integrationKey = "search_console";
const searchConsoleScope = "https://www.googleapis.com/auth/webmasters";
const userEmailScope = "https://www.googleapis.com/auth/userinfo.email";
const googleFetchTimeoutMs = 10_000;
const googleJsonMaxBytes = 512 * 1024;
const requestJsonMaxBytes = 32 * 1024;
const defaultCorsOrigins = [
  "https://project-vinabike.web.app",
  "https://project-vinabike.firebaseapp.com",
] as const;
const firebasePreviewOrigin = /^https:\/\/project-vinabike--[a-z0-9-]+\.web\.app$/;

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export async function handler(req: Request) {
  if (!isAllowedCorsRequest(req)) {
    return jsonResponse(req, { error: "Origin not allowed" }, 403);
  }
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: responseHeaders(req),
    });
  }

  try {
    if (req.method === "GET") return await handleCallback(req);
    if (req.method === "POST") return await handlePost(req);
    return jsonResponse(req, { error: "Use GET or POST" }, 405);
  } catch (error) {
    if (!(error instanceof HttpError) || error.status >= 500) {
      console.error("google-oauth-callback error", error);
    }
    return req.method === "GET"
      ? htmlResponse(
        "No se pudo completar la conexión con Google. Vuelve al ERP e inténtalo nuevamente.",
        error instanceof HttpError ? error.status : 500,
      )
      : jsonResponse(
        req,
        { error: errorMessage(error) },
        error instanceof HttpError ? error.status : 500,
      );
  }
}

if (import.meta.main) {
  serve(handler);
}

async function handlePost(req: Request) {
  const body = await readJsonRequest(req);
  const auth = await requireWebsiteSeoEditor(req);
  const action = cleanText(body.action || "start");
  const admin = adminClient();

  if (action === "status") {
    const storeUrl = await tenantStoreUrl(auth.tenantId);
    const siteUrl = searchConsoleSiteUrl(storeUrl, auth.tenantId);
    const { data, error } = await admin
      .from("google_oauth_tenant_connections")
      .select(
        "account_email, scope, expires_at, updated_at, site_url, generation",
      )
      .eq("tenant_id", auth.tenantId)
      .eq("integration_key", integrationKey)
      .eq("site_url", siteUrl)
      .maybeSingle();
    if (error) throw error;

    return jsonResponse(req, {
      connected: Boolean(data),
      connection: data || null,
    });
  }

  if (action !== "start") {
    return jsonResponse(req, { error: `Unknown action: ${action}` }, 400);
  }

  const storeUrl = await tenantStoreUrl(auth.tenantId);
  const siteUrl = searchConsoleSiteUrl(storeUrl, auth.tenantId);
  const state = randomOAuthState();
  const stateHash = await sha256Hex(state);
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();

  const { error } = await admin.rpc("create_google_oauth_state", {
    p_actor_id: auth.userId,
    p_tenant_id: auth.tenantId,
    p_integration_key: integrationKey,
    p_state_hash: stateHash,
    p_site_url: siteUrl,
    p_expires_at: expiresAt,
  });
  if (error) throw error;

  const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authUrl.searchParams.set("client_id", clientId());
  authUrl.searchParams.set("redirect_uri", redirectUri());
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set(
    "scope",
    `${searchConsoleScope} ${userEmailScope}`,
  );
  authUrl.searchParams.set("access_type", "offline");
  authUrl.searchParams.set("prompt", "consent select_account");
  authUrl.searchParams.set("include_granted_scopes", "true");
  authUrl.searchParams.set("state", state);
  const loginHint = cleanText(
    Deno.env.get("GOOGLE_SEARCH_CONSOLE_LOGIN_HINT"),
  );
  if (loginHint) authUrl.searchParams.set("login_hint", loginHint);

  return jsonResponse(req, {
    authUrl: authUrl.toString(),
    expiresAt,
    siteUrl,
  });
}

async function handleCallback(req: Request) {
  const url = new URL(req.url);
  const code = cleanText(url.searchParams.get("code"));
  const googleError = cleanText(url.searchParams.get("error"));
  const rawState = cleanText(url.searchParams.get("state"));

  if (!rawState || rawState.length > 512) {
    return htmlResponse("El estado de autorización de Google no es válido.", 400);
  }

  const admin = adminClient();
  const stateHash = await sha256Hex(rawState);
  const { data: consumed, error: consumeError } = await admin.rpc(
    "consume_google_oauth_state",
    { p_state_hash: stateHash },
  );
  if (consumeError || !consumed) {
    return htmlResponse(
      "Este enlace de autorización expiró o ya fue utilizado. Vuelve al ERP y conecta Google nuevamente.",
      400,
    );
  }

  const actorId = cleanText(consumed.actor_id);
  const tenantId = cleanText(consumed.tenant_id);
  const authorizedIntegrationKey = cleanText(consumed.integration_key);
  const authorizedSiteUrl = cleanText(consumed.site_url);
  const generation = Number(consumed.generation);
  if (
    authorizedIntegrationKey !== integrationKey ||
    !Number.isSafeInteger(generation) ||
    generation <= 0
  ) {
    throw new HttpError(400, "El estado de autorización no es válido.");
  }
  await requireWebsiteSeoActor(actorId, tenantId);

  const currentStoreUrl = await tenantStoreUrl(tenantId);
  const currentSiteUrl = searchConsoleSiteUrl(currentStoreUrl, tenantId);
  if (!authorizedSiteUrl || authorizedSiteUrl !== currentSiteUrl) {
    throw new HttpError(
      409,
      "La propiedad pública cambió desde que comenzó la autorización.",
    );
  }

  if (googleError) {
    return htmlResponse(
      `Google rechazó la autorización: ${escapeHtml(googleError)}`,
      400,
    );
  }
  if (!code || code.length > 4096) {
    return htmlResponse("Falta el código de autorización de Google.", 400);
  }

  const tokens = await exchangeCode(code);
  const accessToken = cleanText(tokens.access_token);
  if (!accessToken) {
    throw new HttpError(502, "Google no devolvió un token de acceso.");
  }

  const [accountEmail, sitePermission] = await Promise.all([
    fetchGoogleEmail(accessToken),
    verifySearchConsoleSiteAccess(accessToken, authorizedSiteUrl),
  ]);
  if (!sitePermission.authorized) {
    throw new HttpError(
      403,
      `La cuenta Google no tiene acceso completo a ${authorizedSiteUrl}.`,
    );
  }

  const { data: existing, error: existingError } = await admin
    .from("google_oauth_tenant_connections")
    .select("refresh_token, generation, account_email")
    .eq("tenant_id", tenantId)
    .eq("integration_key", integrationKey)
    .eq("site_url", authorizedSiteUrl)
    .maybeSingle();
  if (existingError) throw existingError;

  let legacyConnection: {
    refresh_token?: unknown;
    updated_by?: unknown;
    account_email?: unknown;
  } | null = null;
  if (!existing) {
    const { data, error } = await admin
      .from("google_oauth_connections")
      .select("refresh_token, updated_by, account_email")
      .eq("integration_key", integrationKey)
      .is("tenant_id", null)
      .maybeSingle();
    if (error) throw error;
    if (data) {
      const legacyActorId = cleanText(data.updated_by);
      if (!legacyActorId) {
        throw new HttpError(
          409,
          "La conexión Google heredada no tiene un propietario verificable.",
        );
      }
      await requireWebsiteSeoActor(legacyActorId, tenantId);
      legacyConnection = data;
    }
  }

  const refreshToken = selectGoogleRefreshToken({
    issuedRefreshToken: tokens.refresh_token,
    authorizedAccountEmail: accountEmail,
    existingRefreshToken: existing?.refresh_token,
    existingAccountEmail: existing?.account_email,
    legacyRefreshToken: legacyConnection?.refresh_token,
    legacyAccountEmail: legacyConnection?.account_email,
  });
  if (!refreshToken) {
    throw new HttpError(
      409,
      "Google no entregó autorización renovable. Vuelve a conectar y concede acceso.",
    );
  }

  const expiresInSeconds = boundedPositiveNumber(tokens.expires_in, 3600, 86400);
  const expiresAt = new Date(Date.now() + expiresInSeconds * 1000);
  if (
    existing &&
    Number.isSafeInteger(Number(existing.generation)) &&
    Number(existing.generation) >= generation
  ) {
    throw new HttpError(
      409,
      "Una autorización Google más reciente ya controla esta conexión.",
    );
  }

  const { data: commitResult, error: commitError } = await admin.rpc(
    "commit_google_oauth_connection",
    {
      p_state_hash: stateHash,
      p_tenant_id: tenantId,
      p_integration_key: integrationKey,
      p_generation: generation,
      p_site_url: authorizedSiteUrl,
      p_provider: "google",
      p_account_email: accountEmail || null,
      p_access_token: accessToken,
      p_refresh_token: refreshToken,
      p_token_type: cleanText(tokens.token_type) || "Bearer",
      p_scope: cleanText(tokens.scope),
      p_expires_at: expiresAt.toISOString(),
    },
  );
  if (commitError) throw commitError;
  assertGoogleConnectionCommitted(commitResult);

  return htmlResponse(`
    <h1>Search Console conectado</h1>
    <p>Propiedad autorizada: <strong>${escapeHtml(authorizedSiteUrl)}</strong></p>
    <p>Cuenta autorizada: <strong>${escapeHtml(accountEmail || "Google")}</strong></p>
    <p>Ya puedes cerrar esta pestaña y volver al ERP.</p>
  `);
}

async function exchangeCode(code: string) {
  const { response, payload } = await fetchGoogleJson(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId(),
        client_secret: clientSecret(),
        code,
        redirect_uri: redirectUri(),
        grant_type: "authorization_code",
      }),
    },
  );
  if (!response.ok) {
    throw new HttpError(
      502,
      cleanText(payload?.error_description) ||
        cleanText(payload?.error) ||
        "No se pudo intercambiar el código de Google.",
    );
  }
  return payload;
}

export function assertGoogleConnectionCommitted(payload: unknown) {
  const result = payload && typeof payload === "object" ? payload as Record<string, unknown> : {};
  if (result.committed !== true) {
    throw new HttpError(
      409,
      "Esta autorización fue reemplazada por otra más reciente. La conexión vigente no fue modificada.",
    );
  }
}

export function selectGoogleRefreshToken(input: {
  issuedRefreshToken?: unknown;
  authorizedAccountEmail?: unknown;
  existingRefreshToken?: unknown;
  existingAccountEmail?: unknown;
  legacyRefreshToken?: unknown;
  legacyAccountEmail?: unknown;
}) {
  const issued = cleanText(input.issuedRefreshToken);
  if (issued) return issued;

  const authorizedEmail = cleanText(input.authorizedAccountEmail)
    .toLowerCase();
  if (!authorizedEmail) return "";

  const existingEmail = cleanText(input.existingAccountEmail).toLowerCase();
  const existingToken = cleanText(input.existingRefreshToken);
  if (
    existingToken &&
    existingEmail &&
    existingEmail === authorizedEmail
  ) {
    return existingToken;
  }

  const legacyEmail = cleanText(input.legacyAccountEmail).toLowerCase();
  const legacyToken = cleanText(input.legacyRefreshToken);
  return legacyToken && legacyEmail === authorizedEmail ? legacyToken : "";
}

async function fetchGoogleEmail(accessToken: string) {
  const { response, payload } = await fetchGoogleJson(
    "https://www.googleapis.com/oauth2/v2/userinfo",
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
      },
    },
  );
  if (!response.ok) {
    throw new HttpError(502, "Google no pudo confirmar la cuenta autorizada.");
  }
  return cleanText(payload?.email);
}

async function verifySearchConsoleSiteAccess(
  accessToken: string,
  expectedSiteUrl: string,
) {
  const { response, payload } = await fetchGoogleJson(
    "https://www.googleapis.com/webmasters/v3/sites",
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
      },
    },
  );
  if (!response.ok) {
    throw new HttpError(
      response.status === 401 ? 401 : 502,
      "Google no pudo verificar el acceso a Search Console.",
    );
  }
  const entries = Array.isArray(payload?.siteEntry) ? payload.siteEntry : [];
  const match = entries.find(
    (entry: Record<string, unknown>) => cleanText(entry.siteUrl) === expectedSiteUrl,
  );
  const permissionLevel = cleanText(match?.permissionLevel);
  return {
    authorized: permissionLevel === "siteOwner" ||
      permissionLevel === "siteFullUser",
    permissionLevel: permissionLevel || null,
  };
}

async function fetchGoogleJson(
  input: Parameters<typeof fetch>[0],
  init: Parameters<typeof fetch>[1] = {},
) {
  const controller = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, googleFetchTimeoutMs);
  try {
    const response = await fetch(input, {
      ...init,
      redirect: "error",
      signal: controller.signal,
    });
    const text = await readBoundedText(response, googleJsonMaxBytes);
    // deno-lint-ignore no-explicit-any
    let payload: Record<string, any> = {};
    if (text) {
      try {
        const parsed = JSON.parse(text);
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
          payload = parsed;
        }
      } catch (_) {
        if (response.ok) {
          throw new HttpError(502, "Google devolvió una respuesta inválida.");
        }
      }
    }
    return { response, payload };
  } catch (error) {
    if (timedOut) {
      throw new HttpError(
        504,
        `Google no respondió dentro de ${googleFetchTimeoutMs} ms.`,
      );
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function readBoundedText(response: Response, maxBytes: number) {
  const contentLength = Number(response.headers.get("content-length") || 0);
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    await response.body?.cancel();
    throw new HttpError(502, "La respuesta de Google excede el límite seguro.");
  }
  if (!response.body) return "";

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      byteCount += value.byteLength;
      if (byteCount > maxBytes) {
        await reader.cancel();
        throw new HttpError(
          502,
          "La respuesta de Google excede el límite seguro.",
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(byteCount);
  if (byteCount === 0) return "";
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

async function readJsonRequest(req: Request) {
  const declaredLength = Number(req.headers.get("content-length") || 0);
  if (
    Number.isFinite(declaredLength) &&
    declaredLength > requestJsonMaxBytes
  ) {
    throw new HttpError(413, "Request body exceeds the safe limit.");
  }
  if (!req.body) return {} as Record<string, unknown>;

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      byteCount += value.byteLength;
      if (byteCount > requestJsonMaxBytes) {
        await reader.cancel();
        throw new HttpError(413, "Request body exceeds the safe limit.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(byteCount);
  if (byteCount === 0) return {} as Record<string, unknown>;
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
      throw new Error("JSON object required");
    }
    return parsed as Record<string, unknown>;
  } catch (_) {
    throw new HttpError(400, "A valid JSON object is required.");
  }
}

async function requireWebsiteSeoEditor(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new HttpError(401, "Unauthorized");

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new HttpError(401, "Unauthorized");

  return await requireWebsiteSeoActor(data.user.id);
}

async function requireWebsiteSeoActor(
  userId: string,
  expectedTenantId = "",
) {
  const admin = adminClient();
  const { data: profiles, error: profileError } = await admin
    .from("user_profiles")
    .select("tenant_id, role, permissions")
    .eq("user_id", userId)
    .eq("is_active", true)
    .limit(2);
  if (profileError) throw profileError;
  if (!profiles || profiles.length !== 1) {
    throw new HttpError(
      403,
      "Exactly one active tenant profile is required.",
    );
  }

  const profile = profiles[0];
  const tenantId = cleanText(profile.tenant_id);
  const permissions = profile.permissions &&
      typeof profile.permissions === "object"
    ? profile.permissions as Record<string, unknown>
    : {};
  const canEdit = cleanText(profile.role) === "admin" ||
    permissions.edit_settings === true;
  if (!tenantId || !canEdit || (expectedTenantId && tenantId !== expectedTenantId)) {
    throw new HttpError(403, "Insufficient website settings permission.");
  }

  const { data: tenant, error: tenantError } = await admin
    .from("tenants")
    .select("id")
    .eq("id", tenantId)
    .eq("is_active", true)
    .maybeSingle();
  if (tenantError) throw tenantError;
  if (!tenant) throw new HttpError(403, "The tenant is not active.");

  return { userId, tenantId };
}

async function tenantStoreUrl(tenantId: string) {
  const admin = adminClient();
  const [tenantResult, settingsResult] = await Promise.all([
    admin
      .from("tenants")
      .select("custom_domain, subdomain, is_active")
      .eq("id", tenantId)
      .maybeSingle(),
    admin
      .from("website_settings")
      .select("key, value")
      .eq("tenant_id", tenantId)
      .in("key", ["store_url", "seo_canonical_url"]),
  ]);
  if (tenantResult.error) throw tenantResult.error;
  if (settingsResult.error) throw settingsResult.error;
  if (!tenantResult.data || tenantResult.data.is_active !== true) {
    throw new HttpError(409, "The tenant public store is not active.");
  }

  const values = new Map<string, string>(
    (settingsResult.data || []).map(
      (row: { key?: unknown; value?: unknown }) =>
        [cleanText(row.key), cleanText(row.value)] as const,
    ),
  );
  return resolveTenantStoreOrigin({
    customDomain: cleanText(tenantResult.data.custom_domain),
    subdomain: cleanText(tenantResult.data.subdomain),
    publicStoreBaseDomain: cleanText(
      Deno.env.get("PUBLIC_STORE_BASE_DOMAIN"),
    ),
    configuredStoreUrl: values.get("store_url") ||
      values.get("seo_canonical_url") ||
      "",
    publicStoreOrigins: cleanText(Deno.env.get("PUBLIC_STORE_ORIGINS")),
    searchConsoleSiteUrl: configuredSearchConsoleSiteForTenant(tenantId),
  });
}

export function resolveTenantStoreOrigin(input: {
  customDomain?: string | null;
  subdomain?: string | null;
  publicStoreBaseDomain?: string | null;
  configuredStoreUrl?: string | null;
  publicStoreOrigins?: string | null;
  searchConsoleSiteUrl?: string | null;
}) {
  const allowlistedOrigins = configuredPublicStoreOrigins(
    input.publicStoreOrigins,
    input.searchConsoleSiteUrl,
  );
  const ownedOrigins = new Set<string>();
  const customOrigin = strictHttpsOrigin(input.customDomain || "", true);
  if (customOrigin && allowlistedOrigins.has(customOrigin)) {
    ownedOrigins.add(customOrigin);
  }

  const subdomain = cleanText(input.subdomain).toLowerCase();
  const baseDomain = cleanText(input.publicStoreBaseDomain).toLowerCase();
  if (
    /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(subdomain) &&
    isPublicHostname(baseDomain)
  ) {
    const subdomainOrigin = strictHttpsOrigin(
      `https://${subdomain}.${baseDomain}`,
    );
    if (subdomainOrigin) ownedOrigins.add(subdomainOrigin);
  }

  if (ownedOrigins.size === 0) {
    throw new HttpError(
      409,
      "The tenant public store URL is not in the server allowlist.",
    );
  }

  const configured = cleanText(input.configuredStoreUrl);
  if (configured) {
    const configuredOrigin = strictHttpsOrigin(configured);
    if (!configuredOrigin || !ownedOrigins.has(configuredOrigin)) {
      throw new HttpError(
        409,
        "The configured store URL does not belong to this tenant.",
      );
    }
    return ensureTrailingSlash(configuredOrigin);
  }
  return ensureTrailingSlash(
    customOrigin && ownedOrigins.has(customOrigin) ? customOrigin : [...ownedOrigins][0],
  );
}

function configuredPublicStoreOrigins(
  rawOrigins: string | null | undefined,
  rawSiteUrl: string | null | undefined,
) {
  const origins = new Set<string>();
  for (const raw of cleanText(rawOrigins).split(",")) {
    const origin = strictHttpsOrigin(raw);
    if (origin) origins.add(origin);
  }

  const siteUrl = cleanText(rawSiteUrl);
  if (siteUrl.startsWith("sc-domain:")) {
    const origin = strictHttpsOrigin(
      `https://${siteUrl.substring("sc-domain:".length)}`,
    );
    if (origin) origins.add(origin);
  } else {
    const origin = strictHttpsOrigin(siteUrl);
    if (origin) origins.add(origin);
  }
  return origins;
}

function searchConsoleSiteUrl(storeUrl: string, tenantId: string) {
  const store = new URL(storeUrl);
  const configured = configuredSearchConsoleSiteForTenant(tenantId);
  const siteUrl = configured || `sc-domain:${store.hostname}`;
  const configuredHost = siteUrl.startsWith("sc-domain:")
    ? siteUrl.substring("sc-domain:".length)
    : (() => {
      try {
        return new URL(siteUrl).hostname;
      } catch (_) {
        return "";
      }
    })();
  if (configuredHost.toLowerCase() !== store.hostname.toLowerCase()) {
    throw new HttpError(
      403,
      "Search Console is not configured for this tenant domain.",
    );
  }
  return siteUrl;
}

export function configuredSearchConsoleSiteForTenant(
  tenantId: string,
  rawSiteUrl = Deno.env.get("GOOGLE_SEARCH_CONSOLE_SITE_URL"),
  rawOwnerTenantId = Deno.env.get("GOOGLE_SEARCH_CONSOLE_SITE_TENANT_ID"),
) {
  const siteUrl = cleanText(rawSiteUrl);
  if (!siteUrl) return "";

  const ownerTenantId = cleanText(rawOwnerTenantId).toLowerCase();
  if (!isUuid(ownerTenantId)) {
    throw new HttpError(
      500,
      "GOOGLE_SEARCH_CONSOLE_SITE_TENANT_ID must explicitly own the legacy Search Console property.",
    );
  }
  return ownerTenantId === cleanText(tenantId).toLowerCase() ? siteUrl : "";
}

function strictHttpsOrigin(rawValue: string, allowBareHostname = false) {
  let raw = cleanText(rawValue);
  if (!raw) return null;
  if (allowBareHostname && !raw.includes("://")) raw = `https://${raw}`;

  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch (_) {
    return null;
  }
  if (
    parsed.protocol !== "https:" ||
    parsed.username ||
    parsed.password ||
    parsed.port ||
    (parsed.pathname !== "" && parsed.pathname !== "/") ||
    parsed.search ||
    parsed.hash ||
    !isPublicHostname(parsed.hostname)
  ) {
    return null;
  }
  return parsed.origin;
}

function isPublicHostname(hostname: string) {
  const normalized = hostname.toLowerCase();
  if (
    !normalized.includes(".") ||
    normalized === "localhost" ||
    normalized.endsWith(".localhost") ||
    normalized.endsWith(".local") ||
    normalized.endsWith(".internal") ||
    normalized.endsWith(".invalid") ||
    normalized.endsWith(".test") ||
    normalized.endsWith(".example") ||
    normalized.includes(":") ||
    /^[0-9.]+$/.test(normalized)
  ) {
    return false;
  }
  return /^[a-z0-9.-]+$/.test(normalized) && !normalized.includes("..");
}

function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

function clientId() {
  const value = Deno.env.get("GOOGLE_SEARCH_CONSOLE_CLIENT_ID") || "";
  if (!value) throw new Error("Missing GOOGLE_SEARCH_CONSOLE_CLIENT_ID");
  return value;
}

function clientSecret() {
  const value = Deno.env.get("GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET") || "";
  if (!value) throw new Error("Missing GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET");
  return value;
}

function redirectUri() {
  const configured = cleanText(
    Deno.env.get("GOOGLE_SEARCH_CONSOLE_REDIRECT_URI"),
  );
  if (configured) return configured;

  const supabaseUrl = cleanText(Deno.env.get("SUPABASE_URL"));
  if (!supabaseUrl) {
    throw new Error("Missing GOOGLE_SEARCH_CONSOLE_REDIRECT_URI");
  }
  return new URL(
    "/functions/v1/google-oauth-callback",
    ensureTrailingSlash(supabaseUrl),
  ).toString();
}

export function randomOAuthState() {
  return base64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function boundedPositiveNumber(value: unknown, fallback: number, maximum: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.min(Math.floor(parsed), maximum) : fallback;
}

function ensureTrailingSlash(value: string) {
  return value.endsWith("/") ? value : `${value}/`;
}

function cleanText(value: unknown) {
  return String(value ?? "").trim();
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

function responseHeaders(req?: Request) {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache",
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
  };
  const origin = cleanText(req?.headers.get("Origin"));
  if (origin && isAllowedCorsOrigin(origin)) {
    headers["Access-Control-Allow-Origin"] = new URL(origin).origin;
  }
  return headers;
}

function allowedCorsOrigins() {
  const origins = new Set<string>(defaultCorsOrigins);
  for (
    const raw of [
      cleanText(Deno.env.get("APP_URL")),
      ...cleanText(Deno.env.get("CORS_ALLOWED_ORIGINS")).split(","),
    ]
  ) {
    const value = cleanText(raw);
    if (!value) continue;
    try {
      const url = new URL(value);
      origins.add(url.origin);
    } catch (_) {
      // Invalid configured origins never become permissive.
    }
  }
  return origins;
}

function isAllowedCorsRequest(req: Request) {
  const origin = cleanText(req.headers.get("Origin"));
  return !origin || isAllowedCorsOrigin(origin);
}

function isAllowedCorsOrigin(rawOrigin: string) {
  let parsed: URL;
  try {
    parsed = new URL(rawOrigin);
  } catch (_) {
    return false;
  }
  const origin = parsed.origin;
  if (
    allowedCorsOrigins().has(origin) ||
    firebasePreviewOrigin.test(origin)
  ) {
    return true;
  }
  return isLocalSupabaseRuntime() &&
    (parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1") &&
    (parsed.protocol === "http:" || parsed.protocol === "https:");
}

function isLocalSupabaseRuntime() {
  try {
    const hostname = new URL(cleanText(Deno.env.get("SUPABASE_URL"))).hostname;
    return hostname === "localhost" || hostname === "127.0.0.1";
  } catch (_) {
    return false;
  }
}

function jsonResponse(req: Request, payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...responseHeaders(req),
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function htmlResponse(body: string, status = 200) {
  return new Response(
    `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Vinabike Google OAuth</title>
  <style>
    body { font-family: Inter, system-ui, sans-serif; margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f6f8fb; color: #14213d; }
    main { max-width: 520px; padding: 32px; background: white; border: 1px solid #dbe3ef; border-radius: 18px; box-shadow: 0 18px 45px rgba(20,33,61,.08); }
    h1 { margin-top: 0; font-size: 28px; }
    p { line-height: 1.5; color: #526176; }
  </style>
</head>
<body><main>${body}</main></body>
</html>`,
    {
      status,
      headers: {
        ...responseHeaders(),
        "Content-Type": "text/html; charset=utf-8",
        "Content-Security-Policy":
          "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      },
    },
  );
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
