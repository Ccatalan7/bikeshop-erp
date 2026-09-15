import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  assertAllowedGmailProxyRequest,
  buildGmailMessageDetailUrl,
  buildKnownGmailInboxMarkers,
  GMAIL_API_ORIGIN,
  gmailRateLimitRetryAt,
  parseKnownGmailIds,
  selectUnknownGmailInboxDetailIds,
} from "../_shared/gmail_mail_contract.ts";
import {
  activeMailProviderRateLimitUntil,
  advanceMailProviderRateLimit,
  withMailProviderRateLimit,
  withoutMailProviderRateLimit,
} from "../_shared/mail_provider_rate_limit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const provider = "gmail";
const gmailAccountsOrigin = "https://accounts.google.com";
const gmailPushTopic = "projects/vinabikeapp/topics/gmail-push-notifications";
const gmailSnapshotSize = 500;
const gmailDetailConcurrency = 4;
const gmailLargeKnownSnapshotThreshold = 400;
type AdminClient = ReturnType<typeof adminClient>;
const defaultGmailScopes = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.send",
  "https://www.googleapis.com/auth/gmail.modify",
].join(" ");

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
    const status = message === "Unauthorized" ? 401 : 400;
    console.error("Gmail Edge Function Error:", message);
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
        `${mobileDeepLink}?provider=gmail&error=${encodeURIComponent(error)}`,
        302,
      );
    }
    return Response.redirect(`${frontendBase}?gmail_error=${encodeURIComponent(error)}#/mail`, 302);
  }

  if (code) {
    if (isMobile) {
      return Response.redirect(
        `${mobileDeepLink}?provider=gmail&oauth_code=${encodeURIComponent(code)}`,
        302,
      );
    }
    return Response.redirect(`${frontendBase}?gmail_code=${encodeURIComponent(code)}#/mail`, 302);
  }

  return new Response("Method not allowed", { status: 405 });
}

async function handleAction(
  admin: AdminClient,
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

    const authUrl = new URL(`${gmailAccountsOrigin}/o/oauth2/v2/auth`);
    authUrl.searchParams.set("client_id", clientId());
    authUrl.searchParams.set("redirect_uri", redirectUriValue);
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("scope", cleanText(body.scope) || defaultGmailScopes);
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

  if (action === "list_inbox") {
    return await handleInboxList(admin, authContext, body);
  }

  if (action === "setup_push") {
    return await handlePushSetup(admin, authContext);
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
  admin: AdminClient,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const code = cleanText(body.code);
  const redirectUriValue = cleanText(body.redirect_uri);
  if (!code || !redirectUriValue) throw new Error("Missing code or redirect_uri");

  const tokenPayload = await exchangeCode(code, redirectUriValue);
  const accessToken = cleanText(tokenPayload.access_token);
  if (!accessToken) throw new Error("Gmail did not return an access token");

  const profile = await fetchGmailProfile(accessToken);
  const accountEmail = cleanText(profile.emailAddress);
  if (!accountEmail) throw new Error("Could not resolve Gmail account email");

  const existing = await loadAccount(admin, authContext.userId);
  const refreshTokenValue = cleanText(tokenPayload.refresh_token) ||
    cleanText(existing?.refresh_token);
  if (!refreshTokenValue) {
    throw new Error("Gmail did not return a refresh token. Reconnect and approve offline access.");
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
      provider_account_id: accountEmail,
      access_token: accessToken,
      refresh_token: refreshTokenValue,
      token_type: cleanText(tokenPayload.token_type),
      scope: cleanText(tokenPayload.scope),
      token_expires_at: expiresAt,
      provider_metadata: profile,
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
  admin: AdminClient,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const proxyUrl = cleanText(body.proxy_url);
  assertAllowedGmailProxyRequest(proxyUrl, cleanText(body.method) || "GET");

  const account = await requireAccount(admin, authContext.userId);
  const activeRateLimitUntil = gmailRateLimitUntil(account);
  if (activeRateLimitUntil) {
    return gmailRateLimitResponse(activeRateLimitUntil);
  }

  let accessToken = await ensureValidAccessToken(admin, account);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const response = await fetchWithToken(proxyUrl, body, accessToken);
    if (response.status !== 401 || attempt > 0) {
      return await finalizeGmailProxyResponse(admin, account, response);
    }
    accessToken = await refreshStoredAccessToken(admin, account);
  }

  throw new Error("Gmail authorization retry was exhausted");
}

async function handleInboxList(
  admin: AdminClient,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const account = await requireAccount(admin, authContext.userId);
  const knownIds = parseKnownGmailIds(body.known_ids);
  const activeRateLimitUntil = gmailRateLimitUntil(account);
  if (activeRateLimitUntil) {
    return knownIds.size > 0
      ? jsonResponse(deferredKnownInboxPayload(knownIds, activeRateLimitUntil))
      : jsonResponse({
        error: "Gmail rate limit cooldown is active",
        retry_after: activeRateLimitUntil,
      }, 429);
  }

  const firstToken = await ensureValidAccessToken(admin, account);
  let attempt = await fetchInboxMetadata(firstToken, body);

  if (attempt.status === 401) {
    const refreshedToken = await refreshStoredAccessToken(admin, account);
    attempt = await fetchInboxMetadata(refreshedToken, body);
  }

  if (attempt.status === 429) {
    const providerRetryAt = gmailRateLimitRetryAt(attempt.payload);
    const cooldown = await rememberGmailRateLimit(
      admin,
      account,
      providerRetryAt,
    );
    const effectiveRetryAt = gmailEffectiveRateLimitUntil(cooldown.retryAt);
    console.warn("gmail_provider_rate_limited", {
      operation: "list_inbox",
      provider_retry_after: providerRetryAt,
      effective_retry_after: effectiveRetryAt,
      consecutive_attempts: cooldown.attempts,
    });
    if (knownIds.size > 0) {
      return jsonResponse(
        deferredKnownInboxPayload(knownIds, effectiveRetryAt),
      );
    }
  } else if (attempt.status >= 200 && attempt.status < 300) {
    await clearGmailRateLimit(admin, account);
    console.info("gmail_inbox_sync_success", {
      known_count: knownIds.size,
      returned_count: Array.isArray(attempt.payload.messages) ? attempt.payload.messages.length : 0,
      snapshot_complete: attempt.payload.snapshotComplete === true,
    });
  }

  return jsonResponse(attempt.payload, attempt.status);
}

function deferredKnownInboxPayload(
  knownIds: ReadonlySet<string>,
  retryAfter: string,
) {
  return {
    // No labelIds means the released client deliberately keeps its cached
    // read state. Returning every key also prevents its multi-page refresh
    // loop from trying another Gmail request during the cooldown.
    messages: Array.from(knownIds, (id) => ({ id, known: true })),
    nextPageToken: null,
    resultSizeEstimate: knownIds.size,
    snapshotComplete: false,
    deferred: true,
    retryAfter,
  };
}

function gmailRateLimitResponse(
  retryAt: string,
  providerPayload?: unknown,
) {
  const retrySeconds = Math.max(
    1,
    Math.ceil((Date.parse(retryAt) - Date.now()) / 1000),
  );
  return jsonResponse(
    {
      code: "provider_rate_limited",
      provider,
      error: "Gmail rate limit cooldown is active",
      retry_after: retryAt,
      provider_error: providerPayload ?? null,
    },
    429,
    { "Retry-After": String(retrySeconds) },
  );
}

function gmailRateLimitUntil(account: EmailAccount): string | null {
  return activeMailProviderRateLimitUntil(
    account.provider_metadata,
    provider,
  );
}

function gmailEffectiveRateLimitUntil(retryAt: string): string {
  return activeMailProviderRateLimitUntil(
    withMailProviderRateLimit({}, provider, retryAt),
    provider,
  ) ?? retryAt;
}

async function finalizeGmailProxyResponse(
  admin: AdminClient,
  account: EmailAccount,
  response: Response,
) {
  if (response.status === 429) {
    const payload = await response.clone().json().catch(() => ({}));
    const retryAt = gmailRateLimitRetryAt(
      payload,
      Date.now(),
      response.headers.get("Retry-After"),
    );
    const cooldown = await rememberGmailRateLimit(admin, account, retryAt);
    const effectiveRetryAt = gmailEffectiveRateLimitUntil(cooldown.retryAt);
    console.warn("gmail_provider_rate_limited", {
      operation: "proxy",
      provider_retry_after: retryAt,
      effective_retry_after: effectiveRetryAt,
      consecutive_attempts: cooldown.attempts,
    });
    return gmailRateLimitResponse(effectiveRetryAt, payload);
  }

  if (response.ok) await clearGmailRateLimit(admin, account);
  return response;
}

async function rememberGmailRateLimit(
  admin: AdminClient,
  account: EmailAccount,
  providerRetryAt: string,
) {
  const cooldown = advanceMailProviderRateLimit(
    account.provider_metadata,
    provider,
    providerRetryAt,
  );
  const { error } = await admin
    .from("email_accounts")
    .update({
      provider_metadata: cooldown.metadata,
      last_error: "gmail_rate_limited",
      updated_at: new Date().toISOString(),
    })
    .eq("id", account.id);
  if (error) throw error;
  return cooldown;
}

async function clearGmailRateLimit(
  admin: AdminClient,
  account: EmailAccount,
) {
  const cleared = withoutMailProviderRateLimit(
    account.provider_metadata,
    provider,
  );
  if (!cleared.changed) return;
  const { error } = await admin
    .from("email_accounts")
    .update({
      provider_metadata: cleared.metadata,
      last_error: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", account.id);
  if (error) throw error;
}

async function handlePushSetup(
  admin: AdminClient,
  authContext: AuthContext,
) {
  const account = await requireAccount(admin, authContext.userId);
  const activeRateLimitUntil = gmailRateLimitUntil(account);
  if (activeRateLimitUntil) {
    return gmailRateLimitResponse(activeRateLimitUntil);
  }

  const firstToken = await ensureValidAccessToken(admin, account);
  let watch = await requestGmailWatch(firstToken);

  if (watch.status === 401) {
    const refreshedToken = await refreshStoredAccessToken(admin, account);
    watch = await requestGmailWatch(refreshedToken);
  }
  if (watch.status === 429) {
    const providerRetryAt = gmailRateLimitRetryAt(watch.payload);
    const cooldown = await rememberGmailRateLimit(
      admin,
      account,
      providerRetryAt,
    );
    const effectiveRetryAt = gmailEffectiveRateLimitUntil(cooldown.retryAt);
    console.warn("gmail_provider_rate_limited", {
      operation: "setup_push",
      provider_retry_after: providerRetryAt,
      effective_retry_after: effectiveRetryAt,
      consecutive_attempts: cooldown.attempts,
    });
    return gmailRateLimitResponse(effectiveRetryAt, watch.payload);
  }
  if (watch.status < 200 || watch.status >= 300) {
    return jsonResponse(watch.payload, watch.status);
  }
  await clearGmailRateLimit(admin, account);

  const historyId = cleanText(watch.payload.historyId);
  const expiration = cleanText(watch.payload.expiration);
  const expirationMs = Number(expiration);
  const expirationDate = Number.isFinite(expirationMs) && expirationMs > 0
    ? new Date(expirationMs).toISOString()
    : null;
  const now = new Date().toISOString();
  const { error } = await admin.from("email_push_subscriptions").upsert({
    user_id: authContext.userId,
    tenant_id: authContext.tenantId,
    provider,
    email_address: account.account_email,
    gmail_history_id: historyId || null,
    gmail_expiration: expirationDate,
    is_active: true,
    error_message: null,
    updated_at: now,
  }, { onConflict: "user_id,provider" });
  if (error) throw error;

  return jsonResponse({
    push_configured: true,
    history_id: historyId || null,
    expiration: expirationDate,
  });
}

async function requestGmailWatch(accessToken: string) {
  const response = await fetch(
    `${GMAIL_API_ORIGIN}/gmail/v1/users/me/watch`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        topicName: gmailPushTopic,
        labelIds: ["INBOX"],
      }),
    },
  );
  return {
    status: response.status,
    payload: await response.json().catch(() => ({})) as Record<
      string,
      unknown
    >,
  };
}

// The only system labels a client may list. A request naming anything else —
// a user label, CATEGORY_*, or garbage — falls back to INBOX instead of
// erroring, so an older or tampered client never widens the surface.
const allowedListLabels = new Set(["INBOX", "SENT", "DRAFT", "SPAM", "TRASH"]);

function resolveListLabel(value: unknown): string {
  const label = cleanText(value)?.toUpperCase();
  return label && allowedListLabels.has(label) ? label : "INBOX";
}

async function fetchInboxMetadata(accessToken: string, body: Record<string, unknown>) {
  const rawLimit = Number(body.limit ?? 30);
  const limit = Number.isFinite(rawLimit) ? Math.min(Math.max(Math.trunc(rawLimit), 1), 50) : 30;
  const knownIds = parseKnownGmailIds(body.known_ids);
  const pageToken = cleanText(body.page_token);
  const searchQuery = cleanText(body.search_query);
  const labelId = resolveListLabel(body.label_id);
  const rawStart = Number(body.start ?? 0);
  const start = Number.isFinite(rawStart) ? Math.max(Math.trunc(rawStart), 0) : 0;

  // A normal Inbox refresh used to issue one messages.get (20 quota units) for
  // every cached row. At the 500-row cache boundary that costs more than
  // Gmail's per-user minute budget before any other client can make a request.
  // Reconcile the bounded cache from two cheap ID lists instead. The large-
  // cache branch also catches the second page requested by older clients while
  // they perform the one-time attachment metadata migration.
  const shouldUseKnownSnapshot = labelId === "INBOX" &&
    !searchQuery &&
    knownIds.size > 0 &&
    (start === 0 || !pageToken || knownIds.size >= gmailLargeKnownSnapshotThreshold);
  if (shouldUseKnownSnapshot) {
    return await fetchKnownInboxSnapshot(accessToken, {
      knownIds,
      limit,
      stopPagination: knownIds.size >= gmailLargeKnownSnapshotThreshold,
    });
  }

  const listAttempt = await requestGmailMessageList(accessToken, {
    maxResults: limit,
    labelIds: [labelId],
    pageToken,
    searchQuery,
  });
  if (listAttempt.status < 200 || listAttempt.status >= 300) {
    return listAttempt;
  }

  const listPayload = listAttempt.payload;
  const messageIds = messageIdsFromPayload(listPayload);
  const detailsAttempt = await fetchGmailMessageDetails(
    accessToken,
    messageIds,
    knownIds,
  );
  if (detailsAttempt.status < 200 || detailsAttempt.status >= 300) {
    return detailsAttempt;
  }

  return {
    status: 200,
    payload: {
      messages: detailsAttempt.messages,
      nextPageToken: listPayload.nextPageToken ?? null,
      resultSizeEstimate: listPayload.resultSizeEstimate ?? null,
    },
  };
}

async function fetchKnownInboxSnapshot(
  accessToken: string,
  options: {
    knownIds: Set<string>;
    limit: number;
    stopPagination: boolean;
  },
) {
  // Do not burst the provider at the exact end of a throttle window. These
  // list calls are cheap, but Gmail applies the per-user rolling window to
  // concurrent requests as well as their aggregate quota cost.
  const visibleAttempt = options.stopPagination
    ? null
    : await requestGmailMessageList(accessToken, {
      maxResults: options.limit,
      labelIds: ["INBOX"],
    });
  if (
    visibleAttempt != null &&
    (visibleAttempt.status < 200 || visibleAttempt.status >= 300)
  ) {
    return visibleAttempt;
  }

  const inboxAttempt = await requestGmailMessageList(accessToken, {
    maxResults: gmailSnapshotSize,
    labelIds: ["INBOX"],
  });
  if (inboxAttempt.status < 200 || inboxAttempt.status >= 300) {
    return inboxAttempt;
  }

  const unreadAttempt = await requestGmailMessageList(accessToken, {
    maxResults: gmailSnapshotSize,
    labelIds: ["INBOX", "UNREAD"],
  });
  if (unreadAttempt.status < 200 || unreadAttempt.status >= 300) {
    return unreadAttempt;
  }

  const inboxIds = messageIdsFromPayload(inboxAttempt.payload);
  const visibleIds = inboxIds.slice(0, options.limit);
  const unreadIds = new Set(messageIdsFromPayload(unreadAttempt.payload));
  const unknownDetailIds = selectUnknownGmailInboxDetailIds(
    inboxIds,
    visibleIds,
    options.knownIds,
    options.limit,
  );
  const detailsAttempt = await fetchGmailMessageDetails(
    accessToken,
    unknownDetailIds,
    new Set<string>(),
  );
  if (detailsAttempt.status < 200 || detailsAttempt.status >= 300) {
    return detailsAttempt;
  }

  const byId = new Map<string, Record<string, unknown>>();
  for (
    const marker of buildKnownGmailInboxMarkers(
      inboxIds,
      unreadIds,
      options.knownIds,
    )
  ) {
    byId.set(cleanText(marker.id), marker);
  }
  for (const message of detailsAttempt.messages) {
    const id = cleanText(message.id);
    if (id) byId.set(id, message);
  }

  return {
    status: 200,
    payload: {
      messages: inboxIds.map((id) => byId.get(id)).filter(Boolean),
      nextPageToken: options.stopPagination ? null : visibleAttempt?.payload.nextPageToken ?? null,
      resultSizeEstimate: inboxAttempt.payload.resultSizeEstimate ?? null,
      snapshotComplete: true,
    },
  };
}

async function requestGmailMessageList(
  accessToken: string,
  options: {
    maxResults: number;
    labelIds: string[];
    pageToken?: string;
    searchQuery?: string;
  },
) {
  const listUrl = new URL(`${GMAIL_API_ORIGIN}/gmail/v1/users/me/messages`);
  listUrl.searchParams.set("maxResults", String(options.maxResults));
  for (const labelId of options.labelIds) {
    listUrl.searchParams.append("labelIds", labelId);
  }
  if (options.pageToken) listUrl.searchParams.set("pageToken", options.pageToken);
  if (options.searchQuery) listUrl.searchParams.set("q", options.searchQuery);

  const listResponse = await fetch(listUrl, {
    headers: { "Authorization": `Bearer ${accessToken}` },
  });
  return {
    status: listResponse.status,
    payload: await listResponse.json().catch(() => ({})) as Record<string, unknown>,
  };
}

function messageIdsFromPayload(payload: Record<string, unknown>): string[] {
  const refs = Array.isArray(payload.messages)
    ? payload.messages as Array<Record<string, unknown>>
    : [];
  return refs.map((message) => cleanText(message.id)).filter(Boolean);
}

async function fetchGmailMessageDetails(
  accessToken: string,
  messageIds: string[],
  knownIds: ReadonlySet<string>,
): Promise<{
  status: number;
  payload: Record<string, unknown>;
  messages: Array<Record<string, unknown>>;
}> {
  let failure: { status: number; payload: Record<string, unknown> } | null = null;
  const messages = await mapWithConcurrency(
    messageIds,
    gmailDetailConcurrency,
    async (id) => {
      if (failure) return null;

      const known = knownIds.has(id);
      const detailUrl = buildGmailMessageDetailUrl(id, known);

      const detailResponse = await fetch(detailUrl, {
        headers: { "Authorization": `Bearer ${accessToken}` },
      });
      const detailPayload = await detailResponse.json().catch(() => ({}));

      if (!detailResponse.ok) {
        console.error(
          "Gmail inbox metadata fetch failed:",
          id,
          detailResponse.status,
          detailPayload,
        );
        if (detailResponse.status !== 404 && failure === null) {
          failure = {
            status: detailResponse.status,
            payload: detailPayload as Record<string, unknown>,
          };
        }
        return null;
      }

      const typedPayload = detailPayload as Record<string, unknown>;
      return known ? { ...typedPayload, known: true } : typedPayload;
    },
  );

  const capturedFailure = failure as {
    status: number;
    payload: Record<string, unknown>;
  } | null;
  if (capturedFailure !== null) {
    return {
      status: capturedFailure.status,
      payload: capturedFailure.payload,
      messages: [],
    };
  }
  return {
    status: 200,
    payload: {},
    messages: messages.filter((message): message is Record<string, unknown> => message !== null),
  };
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  mapper: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      results[currentIndex] = await mapper(items[currentIndex], currentIndex);
    }
  }

  const workerCount = Math.min(concurrency, items.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
  return results;
}

async function fetchWithToken(
  proxyUrl: string,
  body: Record<string, unknown>,
  accessToken: string,
) {
  const fetchOptions: RequestInit = {
    method: cleanText(body.method) || "GET",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
  };

  if (body.body) fetchOptions.body = JSON.stringify(body.body);

  const response = await fetch(proxyUrl, fetchOptions);
  const responseText = await response.text();
  let responseData: unknown;
  try {
    responseData = JSON.parse(responseText);
  } catch (_) {
    responseData = { text: responseText };
  }

  const responseHeaders: Record<string, string> = {
    ...corsHeaders,
    "Content-Type": "application/json",
  };
  const retryAfter = response.headers.get("Retry-After");
  if (retryAfter) responseHeaders["Retry-After"] = retryAfter;
  return new Response(JSON.stringify(responseData), {
    headers: responseHeaders,
    status: response.status,
  });
}

async function exchangeCode(code: string, redirectUriValue: string) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
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
    throw new Error(payload.error_description || payload.error || "Could not exchange Gmail code");
  }
  return payload;
}

async function refreshToken(refreshTokenValue: string) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
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
    throw new Error(payload.error_description || payload.error || "Could not refresh Gmail token");
  }
  return payload;
}

async function fetchGmailProfile(accessToken: string) {
  const profileRes = await fetch("https://www.googleapis.com/gmail/v1/users/me/profile", {
    headers: { "Authorization": `Bearer ${accessToken}` },
  });
  const profile = await profileRes.json().catch(() => ({}));
  if (!profileRes.ok) throw new Error(profile.error?.message || "Could not fetch Gmail profile");
  return profile;
}

async function ensureValidAccessToken(
  admin: AdminClient,
  account: EmailAccount,
): Promise<string> {
  const accessToken = cleanText(account.access_token);
  const expiresAt = account.token_expires_at ? new Date(account.token_expires_at).getTime() : 0;
  const refreshAt = Date.now() + 5 * 60 * 1000;

  if (accessToken && expiresAt > refreshAt) return accessToken;
  return await refreshStoredAccessToken(admin, account);
}

async function refreshStoredAccessToken(
  admin: AdminClient,
  account: EmailAccount,
): Promise<string> {
  const refreshTokenValue = cleanText(account.refresh_token);
  if (!refreshTokenValue) throw new Error("Missing stored Gmail refresh token");

  const payload = await refreshToken(refreshTokenValue);
  const accessToken = cleanText(payload.access_token);
  if (!accessToken) throw new Error("Gmail did not return a refreshed access token");

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
  admin: AdminClient,
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
  admin: AdminClient,
  userId: string,
): Promise<EmailAccount> {
  const account = await loadAccount(admin, userId);
  if (!account || account.is_active === false) throw new Error("Gmail account is not connected");
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
  const value = Deno.env.get("GMAIL_CLIENT_ID") ?? "";
  if (!value) throw new Error("Missing GMAIL_CLIENT_ID");
  return value;
}

function clientSecret() {
  const value = Deno.env.get("GMAIL_CLIENT_SECRET") ?? "";
  if (!value) throw new Error("Missing GMAIL_CLIENT_SECRET");
  return value;
}

function cleanText(value: unknown) {
  return String(value ?? "").trim();
}

function jsonResponse(
  payload: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}

type AuthContext = {
  userId: string;
  tenantId: string;
};

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
  provider_metadata?: Record<string, unknown> | null;
  is_active?: boolean | null;
  updated_at?: string | null;
};
