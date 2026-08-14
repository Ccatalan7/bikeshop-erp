import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  isAuthorizedZohoSender,
  normalizeZohoNumericId,
  resolveAuthorizedZohoSenderIdentities,
  resolveZohoOrganizationId,
  resolveZohoUserId,
  zohoDataRecord,
  type ZohoSenderIdentity,
} from "../_shared/zoho_sender_identities.ts";
import { assertAllowedZohoMailProxyRequest } from "../_shared/zoho_mail_proxy_contract.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const provider = "zoho";
const zohoAccountsOrigin = Deno.env.get("ZOHO_ACCOUNTS_ORIGIN") ?? "https://accounts.zoho.com";
const zohoMailOrigin = Deno.env.get("ZOHO_MAIL_ORIGIN") ?? "https://mail.zoho.com";
const defaultZohoScopes = [
  "ZohoMail.messages.READ",
  "ZohoMail.messages.CREATE",
  "ZohoMail.messages.UPDATE",
  "ZohoMail.accounts.READ",
  "ZohoMail.folders.READ",
  "ZohoMail.organization.groups.READ",
].join(",");

serve(async (req) => {
  const url = new URL(req.url);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method === "GET") {
    return handleOAuthRedirect(url);
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const authContext = await requireAuthContext(req);
    const admin = adminClient();

    if (body.action) {
      return await handleAction(admin, authContext, body);
    }

    if (body.grant_type) {
      if (body.grant_type === "authorization_code") {
        return await handleAuthorizationCode(admin, authContext, body);
      }
      if (body.grant_type === "refresh_token") {
        const account = await requireAccount(admin, authContext.userId);
        const accessToken = await refreshStoredAccessToken(admin, account);
        return jsonResponse({
          connected: true,
          account: redactAccount({ ...account, access_token: accessToken }),
        });
      }
      return jsonResponse({ error: `Unsupported grant_type: ${body.grant_type}` }, 400);
    }

    if (body.proxy_url) {
      return await handleProxy(admin, authContext, body);
    }

    return jsonResponse({ error: "Invalid request" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = statusForError(error, message);
    console.error("Zoho Edge Function Error:", message);
    return jsonResponse({ error: message }, status);
  }
});

function handleOAuthRedirect(url: URL) {
  const code = url.searchParams.get("code");
  const error = url.searchParams.get("error");
  const state = url.searchParams.get("state");
  const isMobile = state === "mobile";

  const frontendBase = "https://project-vinabike.web.app";
  const mobileDeepLink = "vinabike://mail/oauth";

  if (error) {
    if (isMobile) {
      return Response.redirect(
        `${mobileDeepLink}?provider=zoho&error=${encodeURIComponent(error)}`,
        302,
      );
    }
    return Response.redirect(`${frontendBase}?zoho_error=${encodeURIComponent(error)}#/mail`, 302);
  }

  if (code) {
    if (isMobile) {
      return Response.redirect(
        `${mobileDeepLink}?provider=zoho&oauth_code=${encodeURIComponent(code)}`,
        302,
      );
    }
    return Response.redirect(`${frontendBase}?zoho_code=${encodeURIComponent(code)}#/mail`, 302);
  }

  return new Response("Method not allowed", { status: 405 });
}

async function handleAction(
  admin: SupabaseAdminClient,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const action = cleanText(body.action);

  if (action === "status") {
    const account = await loadAccount(admin, authContext.userId);
    return jsonResponse({
      connected: Boolean(account?.is_active),
      account: account ? redactAccount(account) : null,
    });
  }

  if (action === "authorization_url") {
    const redirectUriValue = cleanText(body.redirect_uri);
    if (!redirectUriValue) return jsonResponse({ error: "Missing redirect_uri" }, 400);

    const authUrl = new URL(`${zohoAccountsOrigin}/oauth/v2/auth`);
    authUrl.searchParams.set("client_id", clientId());
    authUrl.searchParams.set("redirect_uri", redirectUriValue);
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("scope", cleanText(body.scope) || defaultZohoScopes);
    authUrl.searchParams.set("access_type", "offline");
    authUrl.searchParams.set("prompt", "consent");
    const state = cleanText(body.state);
    if (state) authUrl.searchParams.set("state", state);

    return jsonResponse({ authorization_url: authUrl.toString() });
  }

  if (action === "refresh") {
    const account = await requireAccount(admin, authContext.userId);
    const accessToken = await refreshStoredAccessToken(admin, account);
    return jsonResponse({
      connected: true,
      account: redactAccount({ ...account, access_token: accessToken }),
    });
  }

  if (action === "sender_identities") {
    const account = await requireAccount(admin, authContext.userId);
    const result = await loadCurrentZohoSenderIdentities(admin, account, {
      requireGroups: true,
    });
    return jsonResponse({
      sender_identities: result.identities.map(sanitizeSenderIdentity),
    });
  }

  if (action === "disconnect") {
    await admin
      .from("email_accounts")
      .delete()
      .eq("user_id", authContext.userId)
      .eq("provider", provider);

    await admin
      .from("email_push_subscriptions")
      .delete()
      .eq("user_id", authContext.userId)
      .eq("provider", provider);

    return jsonResponse({ connected: false, account: null });
  }

  return jsonResponse({ error: `Unknown action: ${action}` }, 400);
}

async function handleAuthorizationCode(
  admin: SupabaseAdminClient,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const code = cleanText(body.code);
  const redirectUriValue = cleanText(body.redirect_uri);
  if (!code || !redirectUriValue) throw new Error("Missing code or redirect_uri");

  const tokenPayload = await exchangeCode(code, redirectUriValue);
  const accessToken = cleanText(tokenPayload.access_token);
  if (!accessToken) throw new Error("Zoho did not return an access token");

  const accountInfo = await fetchZohoAccountInfo(accessToken);
  const accountId = cleanText(
    accountInfo.accountId ?? accountInfo.account_id ?? accountInfo.ACCOUNT_ID,
  );
  const accountEmail = resolveZohoEmail(accountInfo);
  if (!accountId) throw new Error("Could not resolve Zoho account ID");
  if (!accountEmail) throw new Error("Could not resolve Zoho account email");

  const existing = await loadAccount(admin, authContext.userId);
  const refreshTokenValue = cleanText(tokenPayload.refresh_token) ||
    cleanText(existing?.refresh_token);
  if (!refreshTokenValue) {
    throw new Error("Zoho did not return a refresh token. Reconnect and approve offline access.");
  }

  const expiresAt = new Date(Date.now() + Number(tokenPayload.expires_in || 3600) * 1000)
    .toISOString();
  const now = new Date().toISOString();

  const { data, error } = await admin
    .from("email_accounts")
    .upsert({
      tenant_id: authContext.tenantId,
      user_id: authContext.userId,
      provider,
      account_email: accountEmail,
      provider_account_id: accountId,
      access_token: accessToken,
      refresh_token: refreshTokenValue,
      token_type: cleanText(tokenPayload.token_type),
      scope: cleanText(tokenPayload.scope),
      token_expires_at: expiresAt,
      provider_metadata: accountInfo,
      is_active: true,
      last_connected_at: now,
      last_error: null,
      updated_at: now,
    }, { onConflict: "user_id,provider" })
    .select("*")
    .single();

  if (error) throw error;

  return jsonResponse({ connected: true, account: redactAccount(data) });
}

async function handleProxy(
  admin: SupabaseAdminClient,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const proxyUrl = cleanText(body.proxy_url);
  const account = await requireAccount(admin, authContext.userId);
  const providerAccountId = normalizeZohoNumericId(account.provider_account_id);
  if (!providerAccountId) throw new Error("Stored Zoho account ID is invalid");
  const proxyKind = assertAllowedZohoMailProxyRequest(
    proxyUrl,
    cleanText(body.method) || "GET",
    zohoMailOrigin,
    providerAccountId,
  );
  const accessToken = await ensureValidAccessToken(admin, account);

  try {
    const response = await fetchAuthorizedProxyRequest(
      proxyUrl,
      body,
      account,
      accessToken,
      proxyKind === "send",
    );
    if (response.status !== 401) return response;
  } catch (error) {
    if (!(error instanceof ZohoApiError) || error.status !== 401) throw error;
  }

  const refreshedToken = await refreshStoredAccessToken(admin, account);
  return await fetchAuthorizedProxyRequest(
    proxyUrl,
    body,
    account,
    refreshedToken,
    proxyKind === "send",
  );
}

async function fetchAuthorizedProxyRequest(
  proxyUrl: string,
  body: Record<string, unknown>,
  account: EmailAccount,
  accessToken: string,
  requiresSenderAuthorization: boolean,
) {
  if (requiresSenderAuthorization) {
    await assertAuthorizedZohoSend(body, account, accessToken);
  }
  return await fetchWithToken(proxyUrl, body, accessToken);
}

async function assertAuthorizedZohoSend(
  body: Record<string, unknown>,
  account: EmailAccount,
  accessToken: string,
) {
  const providerAccountId = normalizeZohoNumericId(account.provider_account_id);
  if (!providerAccountId) throw new Error("Stored Zoho account ID is invalid");

  const requestBody = asRecord(body.body);
  const requestedAddress = cleanText(requestBody?.fromAddress);
  if (!requestedAddress) throw new Error("Missing Zoho From address");

  const accountPayload = await fetchZohoJson(
    `${zohoMailOrigin}/api/accounts/${providerAccountId}`,
    accessToken,
  );
  assertZohoAccountMatches(accountPayload, providerAccountId);
  const mailboxIdentities = resolveAuthorizedZohoSenderIdentities({ accountPayload });
  if (isAuthorizedZohoSender(mailboxIdentities, requestedAddress)) return;

  const groupIdentities = await loadGroupSenderIdentities(
    accountPayload,
    accessToken,
    { requireGroups: true },
  );
  if (!isAuthorizedZohoSender(groupIdentities, requestedAddress)) {
    throw new ZohoPermissionError("Zoho no autorizó esa dirección remitente");
  }
}

async function fetchWithToken(
  proxyUrl: string,
  body: Record<string, unknown>,
  accessToken: string,
) {
  const fetchOptions: RequestInit = {
    method: cleanText(body.method) || "GET",
    headers: {
      "Authorization": `Zoho-oauthtoken ${accessToken}`,
      "Accept": cleanText(body.accept) || "application/json",
      "Content-Type": "application/json",
    },
  };

  if (body.body) fetchOptions.body = JSON.stringify(body.body);

  const response = await fetch(proxyUrl, fetchOptions);
  if (cleanText(body.response_type).toLowerCase() === "base64") {
    const bytes = new Uint8Array(await response.arrayBuffer());
    return new Response(
      JSON.stringify({
        base64: bytesToBase64(bytes),
        contentType: response.headers.get("content-type") ?? null,
        contentLength: response.headers.get("content-length") ?? null,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: response.status,
      },
    );
  }

  const responseText = await response.text();
  let responseData: unknown;
  try {
    responseData = JSON.parse(responseText);
  } catch (_) {
    responseData = { text: responseText };
  }

  return new Response(JSON.stringify(responseData), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status: response.status,
  });
}

async function loadCurrentZohoSenderIdentities(
  admin: SupabaseAdminClient,
  account: EmailAccount,
  options: { requireGroups: boolean },
): Promise<{ identities: ZohoSenderIdentity[] }> {
  const providerAccountId = normalizeZohoNumericId(account.provider_account_id);
  if (!providerAccountId) throw new Error("Stored Zoho account ID is invalid");

  let accessToken = await ensureValidAccessToken(admin, account);
  try {
    return await loadZohoSenderIdentitiesWithToken(
      providerAccountId,
      accessToken,
      options,
    );
  } catch (error) {
    if (!(error instanceof ZohoApiError) || error.status !== 401) throw error;
  }

  accessToken = await refreshStoredAccessToken(admin, account);
  return await loadZohoSenderIdentitiesWithToken(
    providerAccountId,
    accessToken,
    options,
  );
}

async function loadZohoSenderIdentitiesWithToken(
  providerAccountId: string,
  accessToken: string,
  options: { requireGroups: boolean },
) {
  const accountPayload = await fetchZohoJson(
    `${zohoMailOrigin}/api/accounts/${providerAccountId}`,
    accessToken,
  );
  assertZohoAccountMatches(accountPayload, providerAccountId);

  return {
    identities: await loadGroupSenderIdentities(
      accountPayload,
      accessToken,
      options,
    ),
  };
}

async function loadGroupSenderIdentities(
  accountPayload: unknown,
  accessToken: string,
  options: { requireGroups: boolean },
): Promise<ZohoSenderIdentity[]> {
  const mailboxIdentities = resolveAuthorizedZohoSenderIdentities({ accountPayload });
  const zoid = resolveZohoOrganizationId(accountPayload);
  const zuid = resolveZohoUserId(accountPayload);
  if (!zoid || !zuid) return mailboxIdentities;

  let groupsPayload: unknown;
  try {
    groupsPayload = await fetchZohoJson(
      `${zohoMailOrigin}/api/organization/${zoid}/groups`,
      accessToken,
    );
  } catch (error) {
    if (!options.requireGroups) return mailboxIdentities;
    if (error instanceof ZohoApiError && isZohoPermissionFailure(error)) {
      throw new ZohoPermissionError(
        "Permisos Zoho insuficientes: falta el scope ZohoMail.organization.groups.READ. Reconecta Zoho.",
      );
    }
    throw error;
  }

  return resolveAuthorizedZohoSenderIdentities({
    accountPayload,
    groupsPayload,
  });
}

async function fetchZohoJson(url: string, accessToken: string): Promise<unknown> {
  const response = await fetch(url, {
    headers: {
      "Authorization": `Zoho-oauthtoken ${accessToken}`,
      "Accept": "application/json",
      "Content-Type": "application/json",
    },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new ZohoApiError(response.status, zohoApiErrorMessage(payload));
  }
  return payload;
}

function assertZohoAccountMatches(payload: unknown, expectedAccountId: string) {
  const providerAccountId = normalizeZohoNumericId(zohoDataRecord(payload)?.accountId);
  if (providerAccountId !== expectedAccountId) {
    throw new Error("Zoho returned a different account than the connected account");
  }
}

function sanitizeSenderIdentity(identity: ZohoSenderIdentity) {
  return {
    address: identity.address,
    ...(identity.displayName ? { display_name: identity.displayName } : {}),
  };
}

function zohoApiErrorMessage(payload: unknown) {
  const root = asRecord(payload);
  const error = asRecord(root?.error) ?? asRecord(root?.data);
  const providerStatus = asRecord(root?.status);
  return cleanText(
    error?.message ??
      error?.errorCode ??
      error?.moreInfo ??
      root?.message ??
      root?.error ??
      providerStatus?.description ??
      "Zoho API request failed",
  );
}

function isZohoPermissionFailure(error: ZohoApiError) {
  const message = error.message.toLowerCase();
  return error.status === 401 ||
    error.status === 403 ||
    message.includes("oauthscope") ||
    message.includes("scope") ||
    message.includes("permission") ||
    message.includes("not authorized") ||
    message.includes("access denied");
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function statusForError(error: unknown, message: string) {
  if (message === "Unauthorized") return 401;
  if (error instanceof ZohoPermissionError) return 403;
  if (error instanceof ZohoApiError) {
    return error.status >= 400 && error.status <= 599 ? error.status : 502;
  }
  return 400;
}

class ZohoApiError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "ZohoApiError";
  }
}

class ZohoPermissionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ZohoPermissionError";
  }
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(binary);
}

async function exchangeCode(code: string, redirectUriValue: string) {
  const response = await fetch(`${zohoAccountsOrigin}/oauth/v2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: clientSecret(),
      code,
      redirect_uri: redirectUriValue,
      grant_type: "authorization_code",
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.error) {
    throw new Error(payload.error_description || payload.error || "Could not exchange Zoho code");
  }
  return payload;
}

async function refreshToken(refreshTokenValue: string) {
  const response = await fetch(`${zohoAccountsOrigin}/oauth/v2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: clientSecret(),
      refresh_token: refreshTokenValue,
      grant_type: "refresh_token",
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.error) {
    throw new Error(payload.error_description || payload.error || "Could not refresh Zoho token");
  }
  return payload;
}

async function fetchZohoAccountInfo(accessToken: string) {
  const response = await fetch(`${zohoMailOrigin}/api/accounts`, {
    headers: { "Authorization": `Zoho-oauthtoken ${accessToken}` },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error?.message || "Could not fetch Zoho account");
  const firstAccount = Array.isArray(payload.data) ? payload.data[0] : null;
  if (!firstAccount) throw new Error("Zoho account list was empty");
  return firstAccount;
}

function resolveZohoEmail(accountInfo: Record<string, unknown>) {
  const emailAddresses = accountInfo.emailAddress;
  if (Array.isArray(emailAddresses) && emailAddresses.length > 0) {
    const first = emailAddresses[0];
    if (typeof first === "string") return cleanText(first);
    if (first && typeof first === "object") {
      return cleanText((first as Record<string, unknown>).mailId) ||
        cleanText((first as Record<string, unknown>).email);
    }
  }
  return cleanText(accountInfo.mailId) || cleanText(accountInfo.primaryEmailAddress);
}

async function ensureValidAccessToken(
  admin: SupabaseAdminClient,
  account: EmailAccount,
): Promise<string> {
  const accessToken = cleanText(account.access_token);
  const expiresAt = account.token_expires_at ? new Date(account.token_expires_at).getTime() : 0;
  const refreshAt = Date.now() + 5 * 60 * 1000;

  if (accessToken && expiresAt > refreshAt) return accessToken;
  return await refreshStoredAccessToken(admin, account);
}

async function refreshStoredAccessToken(
  admin: SupabaseAdminClient,
  account: EmailAccount,
): Promise<string> {
  const refreshTokenValue = cleanText(account.refresh_token);
  if (!refreshTokenValue) throw new Error("Missing stored Zoho refresh token");

  const payload = await refreshToken(refreshTokenValue);
  const accessToken = cleanText(payload.access_token);
  if (!accessToken) throw new Error("Zoho did not return a refreshed access token");

  const expiresAt = new Date(Date.now() + Number(payload.expires_in || 3600) * 1000).toISOString();
  const now = new Date().toISOString();

  const { error } = await admin
    .from("email_accounts")
    .update({
      access_token: accessToken,
      token_type: cleanText(payload.token_type) || account.token_type,
      scope: cleanText(payload.scope) || account.scope,
      token_expires_at: expiresAt,
      last_token_refresh_at: now,
      last_error: null,
      updated_at: now,
    })
    .eq("id", account.id);

  if (error) throw error;
  return accessToken;
}

async function loadAccount(
  admin: SupabaseAdminClient,
  userId: string,
): Promise<EmailAccount | null> {
  const { data, error } = await admin
    .from("email_accounts")
    .select("*")
    .eq("user_id", userId)
    .eq("provider", provider)
    .maybeSingle();

  if (error) throw error;
  return data as EmailAccount | null;
}

async function requireAccount(
  admin: SupabaseAdminClient,
  userId: string,
): Promise<EmailAccount> {
  const account = await loadAccount(admin, userId);
  if (!account || account.is_active === false) throw new Error("Zoho account is not connected");
  return account;
}

async function requireAuthContext(req: Request): Promise<AuthContext> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new Error("Unauthorized");

  const userClient = createClient(
    supabaseUrl(),
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new Error("Unauthorized");

  const admin = adminClient();
  const { data: profile, error: profileError } = await admin
    .from("user_profiles")
    .select("tenant_id")
    .eq("user_id", data.user.id)
    .maybeSingle();

  if (profileError) throw profileError;
  const tenantId = cleanText(profile?.tenant_id);
  if (!tenantId) throw new Error("Current user has no tenant profile");

  return { userId: data.user.id, tenantId };
}

function redactAccount(account: Partial<EmailAccount>) {
  return {
    provider,
    account_email: account.account_email ?? null,
    provider_account_id: account.provider_account_id ?? null,
    token_expires_at: account.token_expires_at ?? null,
    is_active: account.is_active !== false,
    updated_at: account.updated_at ?? null,
  };
}

function adminClient() {
  return createClient(supabaseUrl(), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
}

function supabaseUrl() {
  const value = Deno.env.get("SUPABASE_URL") ?? "";
  if (!value) throw new Error("Missing SUPABASE_URL");
  return value;
}

function clientId() {
  const value = Deno.env.get("ZOHO_CLIENT_ID") ?? "";
  if (!value) throw new Error("Missing ZOHO_CLIENT_ID");
  return value;
}

function clientSecret() {
  const value = Deno.env.get("ZOHO_CLIENT_SECRET") ?? "";
  if (!value) throw new Error("Missing ZOHO_CLIENT_SECRET");
  return value;
}

function cleanText(value: unknown) {
  return String(value ?? "").trim();
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

type AuthContext = {
  userId: string;
  tenantId: string;
};

type SupabaseAdminClient = ReturnType<typeof adminClient>;

type EmailAccount = {
  id: string;
  tenant_id: string;
  user_id: string;
  provider: string;
  account_email: string;
  provider_account_id?: string | null;
  access_token?: string | null;
  refresh_token?: string | null;
  token_type?: string | null;
  scope?: string | null;
  token_expires_at?: string | null;
  is_active?: boolean | null;
  updated_at?: string | null;
};
