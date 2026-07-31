import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hasSupportedEcommerceTaxRate } from "../_shared/ecommerce_tax.ts";
import { projectPublicCommerceProduct } from "../_shared/google_merchant_feed.ts";
import {
  mergeCanonicalAvailableQuantities,
  resolveAvailableProductQuantity,
} from "../_shared/product_availability.ts";
import {
  isFetchableMerchantDataSource,
  merchantDataSourceFetchUrl,
  merchantDataSourcesUrl,
  merchantProductSummary,
  merchantProductUrl,
} from "../_shared/google_merchant_api.ts";

const merchantScope = "https://www.googleapis.com/auth/content";
const searchConsoleIntegrationKey = "search_console";
const siteFetchTimeoutMs = 8_000;
const googleFetchTimeoutMs = 10_000;
const googleJsonMaxBytes = 2 * 1024 * 1024;
const requestJsonMaxBytes = 32 * 1024;
const releaseEvidenceMaxBytes = 64 * 1024;
const robotsEvidenceMaxBytes = 256 * 1024;
const sitemapEvidenceMaxBytes = 2 * 1024 * 1024;
const merchantPageLimit = 4;
const merchantDataSourceLimit = 8;
const merchantRequestLimit = 13;
const merchantOperationDeadlineMs = 25_000;
const merchantRefreshRateWindowMs = 60_000;
const merchantRefreshRateLimit = 3;
const defaultCorsOrigins = [
  "https://project-vinabike.web.app",
  "https://project-vinabike.firebaseapp.com",
] as const;
const firebasePreviewOrigin = /^https:\/\/project-vinabike--[a-z0-9-]+\.web\.app$/;
export const storeArtifactDnsSafetyBoundary =
  "Standard Edge fetch cannot pin a preflight DNS answer to the TLS connection. " +
  "Only exact server-owned origins are eligible, every redirect is blocked, and DNS is checked immediately before the bounded artifact batch. " +
  "True DNS-answer pinning requires an operator-owned egress proxy that validates TLS Host/SNI.";
const activeMerchantRefreshTenants = new Set<string>();
const merchantRefreshWindows = new Map<
  string,
  { startedAt: number; count: number }
>();

export function searchConsoleSetupNotes(siteUrl: string): string[] {
  return [
    `Connect the exact tenant/site OAuth credential for ${siteUrl} from the SEO center.`,
    `Only when using the project service-account fallback, grant it full Search Console access to ${siteUrl}.`,
    "Merchant Center diagnostics require the configured service account to have product read access.",
  ];
}

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

  if (req.method !== "POST") {
    return jsonResponse(req, { error: "Use POST" }, 405);
  }

  try {
    const body = await readJsonRequest(req);
    const auth = await requireWebsiteSeoEditor(req);
    const action = cleanText(body.action || "inspect");
    const productUrl = cleanText(body.productUrl);
    const offerId = cleanText(body.offerId || body.productId);
    const storeUrl = await tenantStoreUrl(auth.tenantId);
    const siteUrl = searchConsoleSiteUrl(storeUrl, auth.tenantId);
    const sitemapUrl = new URL("sitemap.xml", ensureTrailingSlash(storeUrl))
      .toString();

    if (action === "site_status") {
      const [artifacts, searchConsole] = await Promise.all([
        collectSiteArtifactStatus(storeUrl, { tenantId: auth.tenantId }),
        inspectSearchConsoleSitemap({
          tenantId: auth.tenantId,
          siteUrl,
          sitemapUrl,
        }),
      ]);
      return jsonResponse(req, {
        ok: true,
        observedAt: new Date().toISOString(),
        origin: new URL(storeUrl).origin,
        siteUrl,
        artifacts,
        searchConsole,
        indexingDisclaimer:
          "Este estado confirma evidencia HTTP y datos reportados por Search Console al momento de la consulta; no solicita ni garantiza rastreo o indexación.",
      });
    }

    if (action === "submit_sitemap") {
      return jsonResponse(
        req,
        await submitSearchConsoleSitemap({
          tenantId: auth.tenantId,
          siteUrl,
          sitemapUrl,
        }),
      );
    }

    if (action === "refresh_merchant_feed") {
      return jsonResponse(
        req,
        await refreshMerchantFeeds(auth.tenantId),
      );
    }

    if (!productUrl) {
      return jsonResponse(req, { error: "Missing productUrl" }, 400);
    }
    assertStoreUrl(productUrl, storeUrl);

    const requiredSecrets = [
      "GOOGLE_SEARCH_CONSOLE_SITE_URL",
      "GOOGLE_SEARCH_CONSOLE_SITE_TENANT_ID",
      "GOOGLE_SERVICE_ACCOUNT_EMAIL",
      "GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY",
      "GOOGLE_MERCHANT_ACCOUNT_ID",
      "GOOGLE_MERCHANT_TENANT_ID",
    ];

    const email = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL") || "";
    const privateKey = normalizePrivateKey(
      Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY") || "",
    );
    const merchantConfig = merchantIntegrationForTenant(auth.tenantId);

    const hasServiceAccount = Boolean(email && privateKey);
    const feedEligibility = offerId
      ? await getMerchantFeedEligibility(offerId, auth.tenantId)
      : null;

    const [searchConsole, searchConsoleSitemap, merchant] = await Promise.all([
      inspectSearchConsole({
        tenantId: auth.tenantId,
        siteUrl,
        productUrl,
      }),
      inspectSearchConsoleSitemap({
        tenantId: auth.tenantId,
        siteUrl,
        sitemapUrl,
      }),
      hasServiceAccount && merchantConfig.configured && offerId
        ? inspectMerchant({
          email,
          privateKey,
          merchantAccountId: merchantConfig.accountId,
          offerId,
          feedEligibility,
        })
        : Promise.resolve({
          configured: false,
          feedEligibility,
          requiredSecrets: [
            ...(hasServiceAccount ? [] : [
              "GOOGLE_SERVICE_ACCOUNT_EMAIL",
              "GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY",
            ]),
            ...merchantConfig.requiredSecrets,
          ],
          error: merchantConfig.error || null,
        }),
    ]);

    return jsonResponse(req, {
      ok: true,
      generatedAt: new Date().toISOString(),
      productUrl,
      offerId,
      searchConsole,
      searchConsoleSitemap,
      merchant,
      setup: {
        requiredSecrets,
        notes: searchConsoleSetupNotes(siteUrl),
      },
    });
  } catch (error) {
    if (!(error instanceof HttpError) || error.status >= 500) {
      console.error("google-product-diagnostics error", error);
    }
    return jsonResponse(
      req,
      { error: errorMessage(error) },
      error instanceof HttpError ? error.status : 500,
    );
  }
}

if (import.meta.main) {
  serve(handler);
}

type SiteArtifactFetchOptions = {
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
  now?: () => Date;
  dnsResolver?: DnsResolver;
  serverOwnedOrigins?: readonly string[];
  serverOwnedBaseDomain?: string;
  tenantId?: string;
};

type DnsResolver = (hostname: string) => Promise<string[]>;

type NetworkBudget = {
  deadlineAt: number;
  maxRequests: number;
  requestsUsed: number;
};

type RpcResult = {
  data: unknown;
  error: { message?: string } | null;
};

type RpcInvoker = (
  functionName: string,
  args: Record<string, unknown>,
) => Promise<RpcResult>;

type GoogleOAuthConnectionSnapshot = {
  access_token?: unknown;
  refresh_token?: unknown;
  expires_at?: unknown;
  scope?: unknown;
  generation?: unknown;
  credential_version?: unknown;
};

type GoogleOAuthConnectionReader = (
  tenantId: string,
  siteUrl: string,
) => Promise<GoogleOAuthConnectionSnapshot | null>;

type TextEvidence = {
  url: string;
  observedAt: string;
  reachable: boolean;
  httpOk: boolean;
  status: number | null;
  durationMs: number;
  contentType: string | null;
  etag: string | null;
  lastModified: string | null;
  timedOut: boolean;
  error: string | null;
  body: string;
};

export async function collectSiteArtifactStatus(
  storeUrl: string,
  options: SiteArtifactFetchOptions = {},
) {
  const origin = validatedPublicStoreOrigin(storeUrl);
  // Exact server-owned origin configuration is the primary SSRF boundary and
  // DNS is a second fail-closed signal. Standard Edge fetch cannot bind the
  // checked answer to its TLS connection, so post-check DNS rebinding remains
  // an explicit operator/DNS risk documented by storeArtifactDnsSafetyBoundary.
  assertServerOwnedArtifactOrigin(origin, options);
  await assertPublicDnsResolution(
    new URL(origin).hostname,
    options.dnsResolver || resolvePublicDnsAddresses,
  );
  const root = ensureTrailingSlash(origin);
  const releaseUrl = new URL("release.json", root).toString();
  const sitemapUrl = new URL("sitemap.xml", root).toString();
  const robotsUrl = new URL("robots.txt", root).toString();
  const [release, sitemap, robots] = await Promise.all([
    inspectReleaseEvidence(
      releaseUrl,
      artifactFetchOptions(options, "application/json", releaseEvidenceMaxBytes),
    ),
    inspectSitemapEvidence(
      sitemapUrl,
      origin,
      artifactFetchOptions(options, "application/xml,text/xml", sitemapEvidenceMaxBytes),
    ),
    inspectRobotsEvidence(
      robotsUrl,
      sitemapUrl,
      artifactFetchOptions(options, "text/plain", robotsEvidenceMaxBytes),
    ),
  ]);

  return {
    origin,
    release,
    sitemap,
    robots,
    summary: {
      allReachable: release.reachable && sitemap.reachable && robots.reachable,
      allHttpOk: release.httpOk && sitemap.httpOk && robots.httpOk,
      allDocumentsValid: release.documentValid &&
        sitemap.documentValid &&
        robots.documentValid,
    },
  };
}

function artifactFetchOptions(
  options: SiteArtifactFetchOptions,
  accept: string,
  maxBytes: number,
) {
  return {
    ...options,
    accept,
    maxBytes,
  };
}

async function inspectReleaseEvidence(
  url: string,
  options: SiteArtifactFetchOptions & { accept: string; maxBytes: number },
) {
  const fetched = await fetchTextEvidence(url, options);
  const { body, ...http } = fetched;
  let payload: Record<string, unknown> | null = null;
  let parseError: string | null = null;
  if (fetched.httpOk) {
    try {
      const parsed = JSON.parse(body);
      if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
        throw new Error("release.json must contain a JSON object");
      }
      payload = parsed as Record<string, unknown>;
    } catch (error) {
      parseError = errorMessage(error);
    }
  }

  const commit = cleanText(payload?.commit);
  const run = cleanText(payload?.run);
  const builtAt = cleanText(payload?.built_at);
  const target = cleanText(payload?.target);
  const source = cleanText(payload?.source);
  const dirty = typeof payload?.dirty === "boolean" ? payload.dirty : null;
  const publicationRaw = payload?.publication;
  const publication = publicationRaw && typeof publicationRaw === "object" &&
      !Array.isArray(publicationRaw)
    ? publicationRaw as Record<string, unknown>
    : null;
  const publicationTracked = publication != null;
  const publicationRequestId = cleanText(publication?.request_id);
  const publicationOwnerRevision = Number(publication?.owner_revision);
  const publicationOwnerSourceSha256 = cleanText(
    publication?.owner_source_sha256,
  );
  const publicationBuildInputSha256 = cleanText(
    publication?.build_input_sha256,
  );
  const publicationInvalidReasons = publicationTracked
    ? [
      ...(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          .test(publicationRequestId)
        ? ["request_id_invalid"]
        : []),
      ...(!Number.isSafeInteger(publicationOwnerRevision) ||
          publicationOwnerRevision <= 0
        ? ["owner_revision_invalid"]
        : []),
      ...(!/^[0-9a-f]{64}$/i.test(publicationOwnerSourceSha256)
        ? ["owner_source_sha256_invalid"]
        : []),
      ...(!/^[0-9a-f]{64}$/i.test(publicationBuildInputSha256)
        ? ["build_input_sha256_invalid"]
        : []),
    ]
    : publicationRaw == null
    ? []
    : ["publication_not_object_or_null"];
  const publicationValid = publicationTracked &&
    publicationInvalidReasons.length === 0;
  const commitValid = /^[0-9a-f]{40}$/i.test(commit);
  const builtAtValid = Boolean(builtAt) &&
    Number.isFinite(new Date(builtAt).getTime());
  const builtAtNotFuture = builtAtValid &&
    new Date(builtAt).getTime() <=
      (options.now || (() => new Date()))().getTime() + 5 * 60 * 1000;
  const invalidReasons = [
    ...(!commitValid ? ["commit_not_full_sha"] : []),
    ...(!run ? ["run_missing"] : []),
    ...(!builtAtValid ? ["built_at_invalid"] : []),
    ...(builtAtValid && !builtAtNotFuture ? ["built_at_future"] : []),
    ...(target !== "store" ? ["target_not_store"] : []),
    ...(!source ? ["source_missing"] : []),
    ...(dirty !== false ? ["dirty_or_unknown_build"] : []),
    ...publicationInvalidReasons.map((reason) => `publication_${reason}`),
  ];
  return {
    ...http,
    documentValid: fetched.httpOk && !parseError && invalidReasons.length === 0,
    parseError,
    commit: commit || null,
    commitValid,
    run: run || null,
    builtAt: builtAt || null,
    builtAtValid,
    builtAtNotFuture,
    target: target || null,
    source: source || null,
    dirty,
    publication: publicationTracked
      ? {
        requestId: publicationRequestId || null,
        ownerRevision: Number.isSafeInteger(publicationOwnerRevision)
          ? publicationOwnerRevision
          : null,
        ownerSourceSha256: publicationOwnerSourceSha256 || null,
        buildInputSha256: publicationBuildInputSha256 || null,
      }
      : null,
    publicationTracked,
    publicationValid,
    publicationInvalidReasons,
    invalidReasons,
  };
}

async function inspectSitemapEvidence(
  url: string,
  expectedOrigin: string,
  options: SiteArtifactFetchOptions & { accept: string; maxBytes: number },
) {
  const fetched = await fetchTextEvidence(url, options);
  const { body, ...http } = fetched;
  const locationMatches = fetched.httpOk
    ? [...body.matchAll(/<loc\b[^>]*>([\s\S]*?)<\/loc>/gi)]
    : [];
  const locations = locationMatches.map((match) => decodeXmlText(cleanText(match[1])));
  let invalidLocationCount = 0;
  let foreignOriginCount = 0;
  for (const location of locations) {
    try {
      const parsed = new URL(location);
      if (parsed.origin !== expectedOrigin) foreignOriginCount += 1;
    } catch (_) {
      invalidLocationCount += 1;
    }
  }
  const urlEntryCount = fetched.httpOk ? (body.match(/<url(?:\s|>)/gi) || []).length : 0;
  const hasUrlset = fetched.httpOk && /<urlset(?:\s|>)/i.test(body);
  const locationsMatchEntries = locations.length === urlEntryCount;

  return {
    ...http,
    documentValid: fetched.httpOk &&
      hasUrlset &&
      locationsMatchEntries &&
      invalidLocationCount === 0 &&
      foreignOriginCount === 0,
    hasUrlset,
    urlEntryCount,
    locationCount: locations.length,
    locationsMatchEntries,
    invalidLocationCount,
    foreignOriginCount,
    canonicalOriginConsistent: invalidLocationCount === 0 &&
      foreignOriginCount === 0,
  };
}

async function inspectRobotsEvidence(
  url: string,
  expectedSitemapUrl: string,
  options: SiteArtifactFetchOptions & { accept: string; maxBytes: number },
) {
  const fetched = await fetchTextEvidence(url, options);
  const { body, ...http } = fetched;
  const activeLines = fetched.httpOk
    ? body
      .split(/\r?\n/)
      .map((line) => line.replace(/#.*$/, "").trim())
      .filter(Boolean)
    : [];
  const sitemapUrls = activeLines
    .filter((line) => /^sitemap\s*:/i.test(line))
    .map((line) => cleanText(line.replace(/^sitemap\s*:/i, "")));
  const userAgents: string[] = [];
  const wildcardDisallowDirectives: string[] = [];
  let currentAgents: string[] = [];
  let groupHasDirectives = false;
  for (const line of activeLines) {
    if (/^user-agent\s*:/i.test(line)) {
      if (groupHasDirectives) {
        currentAgents = [];
        groupHasDirectives = false;
      }
      const agent = cleanText(line.replace(/^user-agent\s*:/i, ""));
      userAgents.push(agent);
      currentAgents.push(agent);
      continue;
    }
    if (/^(allow|disallow)\s*:/i.test(line)) {
      groupHasDirectives = true;
      if (
        currentAgents.includes("*") &&
        /^disallow\s*:/i.test(line)
      ) {
        wildcardDisallowDirectives.push(
          cleanText(line.replace(/^disallow\s*:/i, "")),
        );
      }
    }
  }
  const expectedSitemapDeclared = sitemapUrls.some(
    (entry) => canonicalUrlKey(entry) === canonicalUrlKey(expectedSitemapUrl),
  );
  const hasWildcardUserAgent = userAgents.includes("*");
  const invalidSitemapCount = sitemapUrls.filter((entry) => {
    try {
      const parsed = new URL(entry);
      return parsed.origin !== new URL(expectedSitemapUrl).origin;
    } catch (_) {
      return true;
    }
  }).length;
  const rootDisallowDirectivePresent = wildcardDisallowDirectives.some(
    (directive) => directive === "/" || directive === "/*",
  );

  return {
    ...http,
    documentValid: fetched.httpOk &&
      hasWildcardUserAgent &&
      expectedSitemapDeclared &&
      invalidSitemapCount === 0 &&
      !rootDisallowDirectivePresent,
    hasWildcardUserAgent,
    expectedSitemapDeclared,
    sitemapUrls,
    invalidSitemapCount,
    userAgentCount: userAgents.length,
    disallowDirectiveCount: wildcardDisallowDirectives.length,
    rootDisallowDirectivePresent,
  };
}

async function fetchTextEvidence(
  url: string,
  options: SiteArtifactFetchOptions & { accept: string; maxBytes: number },
): Promise<TextEvidence> {
  const fetchImpl = options.fetchImpl || fetch;
  const timeoutMs = options.timeoutMs || siteFetchTimeoutMs;
  const now = options.now || (() => new Date());
  const startedAt = performance.now();
  const controller = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);

  try {
    const response = await fetchImpl(url, {
      headers: {
        Accept: options.accept,
        "Cache-Control": "no-cache",
      },
      redirect: "manual",
      signal: controller.signal,
    });
    const base = {
      url,
      observedAt: now().toISOString(),
      reachable: true,
      httpOk: response.ok,
      status: response.status,
      durationMs: Math.round(performance.now() - startedAt),
      contentType: response.headers.get("content-type"),
      etag: response.headers.get("etag"),
      lastModified: response.headers.get("last-modified"),
      timedOut,
    };
    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel();
      return {
        ...base,
        httpOk: false,
        error: "Redirect blocked while collecting same-origin site evidence",
        body: "",
      };
    }
    try {
      const body = await readBoundedText(response, options.maxBytes);
      return {
        ...base,
        durationMs: Math.round(performance.now() - startedAt),
        timedOut,
        error: response.ok ? null : `HTTP ${response.status}`,
        body,
      };
    } catch (error) {
      return {
        ...base,
        httpOk: false,
        durationMs: Math.round(performance.now() - startedAt),
        timedOut,
        error: timedOut ? `Timed out after ${timeoutMs} ms` : errorMessage(error),
        body: "",
      };
    }
  } catch (error) {
    return {
      url,
      observedAt: now().toISOString(),
      reachable: false,
      httpOk: false,
      status: null,
      durationMs: Math.round(performance.now() - startedAt),
      contentType: null,
      etag: null,
      lastModified: null,
      timedOut,
      error: timedOut ? `Timed out after ${timeoutMs} ms` : errorMessage(error),
      body: "",
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function readBoundedText(response: Response, maxBytes: number) {
  const contentLength = Number(response.headers.get("content-length") || 0);
  if (contentLength > maxBytes) {
    await response.body?.cancel();
    throw new Error(`Response exceeds the ${maxBytes}-byte evidence limit`);
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
        throw new Error(`Response exceeds the ${maxBytes}-byte evidence limit`);
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
    throw new HttpError(413, "Request body exceeds the safe limit");
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
        throw new HttpError(413, "Request body exceeds the safe limit");
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
    throw new HttpError(400, "A valid JSON object is required");
  }
}

async function fetchBoundedText(
  input: Parameters<typeof fetch>[0],
  init: Parameters<typeof fetch>[1] = {},
  {
    timeoutMs = googleFetchTimeoutMs,
    maxBytes = googleJsonMaxBytes,
    budget,
  }: {
    timeoutMs?: number;
    maxBytes?: number;
    budget?: NetworkBudget;
  } = {},
) {
  const effectiveTimeoutMs = budget ? Math.min(timeoutMs, claimNetworkBudget(budget)) : timeoutMs;
  const controller = new AbortController();
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, effectiveTimeoutMs);
  try {
    const response = await fetch(input, {
      ...init,
      redirect: "error",
      signal: controller.signal,
    });
    const text = await readBoundedText(response, maxBytes);
    return { response, text };
  } catch (error) {
    if (timedOut) {
      throw new Error(`Request timed out after ${effectiveTimeoutMs} ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchGoogleJson(
  input: Parameters<typeof fetch>[0],
  init: Parameters<typeof fetch>[1] = {},
  budget?: NetworkBudget,
) {
  const { response, text } = await fetchBoundedText(input, init, { budget });
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
        throw new Error("Google returned an invalid JSON response");
      }
    }
  }
  return { response, payload, text };
}

export function createNetworkBudget(
  deadlineMs: number,
  maxRequests: number,
): NetworkBudget {
  return {
    deadlineAt: Date.now() + deadlineMs,
    maxRequests,
    requestsUsed: 0,
  };
}

export function claimNetworkBudget(budget: NetworkBudget) {
  const remainingMs = budget.deadlineAt - Date.now();
  if (remainingMs <= 0) {
    throw new HttpError(504, "Google operation deadline exceeded");
  }
  if (budget.requestsUsed >= budget.maxRequests) {
    throw new HttpError(429, "Google operation request budget exhausted");
  }
  budget.requestsUsed += 1;
  return remainingMs;
}

function decodeXmlText(value: string) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

async function inspectSearchConsole(args: {
  tenantId: string;
  siteUrl: string;
  productUrl: string;
}) {
  try {
    const tokenResult = await searchConsoleAccessToken({
      tenantId: args.tenantId,
      siteUrl: args.siteUrl,
    });
    if (!tokenResult.ok) {
      return {
        configured: false,
        connectRequired: true,
        reconnectRequired: tokenResult.reconnectRequired === true,
        error: tokenResult.error,
        requiredSecrets: tokenResult.requiredSecrets || [],
      };
    }

    const { response, payload } = await fetchGoogleJson(
      "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${tokenResult.accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          inspectionUrl: args.productUrl,
          siteUrl: args.siteUrl,
          languageCode: "es-CL",
        }),
      },
    );
    if (!response.ok) {
      const visibleSites = response.status === 403
        ? await listSearchConsoleSites(
          tokenResult.accessToken,
          args.siteUrl,
        )
        : null;
      const permissionDenied = response.status === 403;
      const usesServiceAccount = tokenResult.source === "service_account";

      return {
        configured: true,
        ok: false,
        status: response.status,
        errorCode: payload?.error?.status || payload?.error?.code || null,
        error: permissionDenied
          ? usesServiceAccount
            ? `Agrega la cuenta técnica ${tokenResult.serviceAccountEmail} como usuario con acceso completo a ${args.siteUrl}.`
            : `La cuenta Google conectada no tiene acceso a ${args.siteUrl}. Reconecta Search Console usando una cuenta propietaria o con acceso completo.`
          : payload?.error?.message || JSON.stringify(payload),
        googleError: payload?.error?.message || null,
        authSource: tokenResult.source,
        serviceAccountEmail: tokenResult.serviceAccountEmail || null,
        grantServiceAccountRequired: permissionDenied && usesServiceAccount,
        connectRequired: permissionDenied && !usesServiceAccount,
        reconnectRequired: permissionDenied && !usesServiceAccount,
        searchedSiteUrl: args.siteUrl,
        availableSites: visibleSites?.sites || [],
        availableSitesError: visibleSites?.error || null,
      };
    }

    const indexStatus = payload?.inspectionResult?.indexStatusResult || {};
    const richResults = payload?.inspectionResult?.richResultsResult || {};

    return {
      configured: true,
      ok: true,
      verdict: indexStatus.verdict,
      coverageState: indexStatus.coverageState,
      robotsTxtState: indexStatus.robotsTxtState,
      indexingState: indexStatus.indexingState,
      pageFetchState: indexStatus.pageFetchState,
      lastCrawlTime: indexStatus.lastCrawlTime,
      googleCanonical: indexStatus.googleCanonical,
      userCanonical: indexStatus.userCanonical,
      canonicalMatches: canonicalUrlKey(indexStatus.userCanonical) ===
          canonicalUrlKey(args.productUrl) &&
        (!cleanText(indexStatus.googleCanonical) ||
          canonicalUrlKey(indexStatus.googleCanonical) ===
            canonicalUrlKey(args.productUrl)),
      authSource: tokenResult.source,
      serviceAccountEmail: tokenResult.serviceAccountEmail || null,
      sitemap: indexStatus.sitemap,
      richResultsVerdict: richResults.verdict,
      raw: payload,
    };
  } catch (error) {
    return {
      configured: true,
      ok: false,
      error: errorMessage(error),
    };
  }
}

async function inspectSearchConsoleSitemap(args: {
  tenantId: string;
  siteUrl: string;
  sitemapUrl: string;
}) {
  const observedAt = new Date().toISOString();
  try {
    const tokenResult = await searchConsoleAccessToken({
      tenantId: args.tenantId,
      siteUrl: args.siteUrl,
    });
    if (!tokenResult.ok) {
      return {
        observedAt,
        configured: false,
        connectRequired: true,
        reconnectRequired: tokenResult.reconnectRequired === true,
        error: tokenResult.error,
      };
    }
    const { response, payload } = await fetchGoogleJson(
      `https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(args.siteUrl)}/sitemaps`,
      {
        headers: {
          Authorization: `Bearer ${tokenResult.accessToken}`,
          Accept: "application/json",
        },
      },
    );
    if (!response.ok) {
      const permissionDenied = response.status === 403;
      const usesServiceAccount = tokenResult.source === "service_account";
      return {
        observedAt,
        configured: true,
        ok: false,
        status: response.status,
        error: permissionDenied
          ? usesServiceAccount
            ? `Agrega la cuenta técnica ${tokenResult.serviceAccountEmail} como usuario con acceso completo a ${args.siteUrl}.`
            : `La cuenta Google conectada no tiene acceso al sitemap de ${args.siteUrl}. Reconecta Search Console usando una cuenta propietaria o con acceso completo.`
          : payload?.error?.message || JSON.stringify(payload),
        googleError: payload?.error?.message || null,
        authSource: tokenResult.source,
        serviceAccountEmail: tokenResult.serviceAccountEmail || null,
        grantServiceAccountRequired: permissionDenied && usesServiceAccount,
        connectRequired: permissionDenied && !usesServiceAccount,
        reconnectRequired: permissionDenied && !usesServiceAccount,
      };
    }
    const sitemaps = Array.isArray(payload?.sitemap) ? payload.sitemap : [];
    const sitemap = sitemaps.find(
      (entry: Record<string, unknown>) => cleanText(entry?.path) === args.sitemapUrl,
    );
    return {
      observedAt,
      configured: true,
      ok: Boolean(sitemap),
      submitted: Boolean(sitemap),
      sitemapUrl: args.sitemapUrl,
      lastSubmitted: sitemap?.lastSubmitted || null,
      lastDownloaded: sitemap?.lastDownloaded || null,
      isPending: sitemap?.isPending ?? null,
      warnings: sitemap?.warnings ?? null,
      errors: sitemap?.errors ?? null,
      authSource: tokenResult.source,
      serviceAccountEmail: tokenResult.serviceAccountEmail || null,
      raw: sitemap || null,
    };
  } catch (error) {
    return {
      observedAt,
      configured: true,
      ok: false,
      error: errorMessage(error),
    };
  }
}

async function submitSearchConsoleSitemap(args: {
  tenantId: string;
  siteUrl: string;
  sitemapUrl: string;
}) {
  try {
    const tokenResult = await searchConsoleAccessToken({
      tenantId: args.tenantId,
      siteUrl: args.siteUrl,
      requireWrite: true,
    });
    if (!tokenResult.ok) {
      return {
        ok: false,
        configured: false,
        connectRequired: true,
        reconnectRequired: tokenResult.reconnectRequired === true,
        error: tokenResult.error,
      };
    }
    if (
      !tokenResult.scope
        .split(/\s+/)
        .includes("https://www.googleapis.com/auth/webmasters")
    ) {
      return {
        ok: false,
        configured: true,
        reconnectRequired: true,
        error: "Reconecta Search Console una vez para autorizar el envío del sitemap.",
        currentScope: tokenResult.scope,
      };
    }

    const { response, text: payload } = await fetchBoundedText(
      `https://www.googleapis.com/webmasters/v3/sites/${
        encodeURIComponent(args.siteUrl)
      }/sitemaps/${encodeURIComponent(args.sitemapUrl)}`,
      {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${tokenResult.accessToken}`,
        },
      },
    );
    const permissionDenied = !response.ok && response.status === 403;
    const usesServiceAccount = tokenResult.source === "service_account";
    return {
      ok: response.ok,
      configured: true,
      siteUrl: args.siteUrl,
      sitemapUrl: args.sitemapUrl,
      status: response.status,
      error: response.ok
        ? null
        : permissionDenied
        ? usesServiceAccount
          ? `Agrega la cuenta técnica ${tokenResult.serviceAccountEmail} como usuario con acceso completo a ${args.siteUrl}.`
          : `La cuenta Google conectada no puede enviar el sitemap de ${args.siteUrl}. Reconecta Search Console usando una cuenta propietaria o con acceso completo.`
        : payload,
      googleError: response.ok ? null : payload,
      authSource: tokenResult.source,
      serviceAccountEmail: tokenResult.serviceAccountEmail || null,
      grantServiceAccountRequired: permissionDenied && usesServiceAccount,
      connectRequired: permissionDenied && !usesServiceAccount,
      reconnectRequired: permissionDenied && !usesServiceAccount,
    };
  } catch (error) {
    return {
      ok: false,
      configured: false,
      reconnectRequired: true,
      error: errorMessage(error),
    };
  }
}

async function getMerchantFeedEligibility(offerId: string, tenantId: string) {
  if (!isUuid(offerId)) {
    return {
      known: false,
      eligible: false,
      reasons: [
        "El offer id no es un UUID de producto local, así que no se pudo validar contra el feed ERP.",
      ],
    };
  }

  const client = adminClient();
  const { data, error } = await client
    .from("products")
    .select(
      "id, tenant_id, name, website_name, website_merchant_title, sku, description, website_description, website_merchant_description, is_active, is_published, show_on_website, is_google_merchant, lifecycle_status, product_type, price, website_price, price_currency, stock_quantity, inventory_qty, track_stock, is_set, tax_rate, image_url, image_url_optimized, website_image_url, website_image_url_optimized, image_urls, website_image_urls, brand_id, brand, website_merchant_brand, website_merchant_gtin, gtin, barcode, website_merchant_mpn, category_id, website_google_product_category",
    )
    .eq("id", offerId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (error) {
    return {
      known: false,
      eligible: false,
      reasons: ["No se pudo revisar si el producto entra al feed Merchant."],
      error: error.message,
    };
  }

  if (!data) {
    return {
      known: true,
      eligible: false,
      reasons: ["El producto no existe en la base local."],
    };
  }
  const { data: availabilityRows, error: availabilityError } = await client
    .rpc("get_product_available_quantities", {
      p_tenant_id: data.tenant_id,
      p_product_ids: [data.id],
    });
  const canonicalProduct = mergeCanonicalAvailableQuantities(
    [data],
    (availabilityRows || []) as unknown as Array<Record<string, unknown>>,
  )[0];
  const { data: publicRows, error: publicCatalogError } = await client.rpc(
    "get_public_products",
    {
      p_tenant_id: data.tenant_id,
      p_product_ids: [data.id],
      p_only_in_stock: true,
      p_sort_by: "name",
      p_limit: 1,
      p_offset: 0,
    },
  );

  const reasons: string[] = [];
  if (availabilityError) {
    reasons.push("No se pudo calcular la disponibilidad vendible del producto.");
  }
  if (publicCatalogError) {
    reasons.push(
      "No se pudo verificar la misma regla pública que usa la landing del producto.",
    );
  } else if (
    !(publicRows || []).some((row: { id?: unknown }) => cleanText(row.id) === cleanText(data.id))
  ) {
    reasons.push(
      "Las reglas actuales del catálogo web no mantienen una landing pública para este producto.",
    );
  }
  if (data.is_active !== true) reasons.push("El producto no esta activo.");
  if (data.is_published !== true) {
    reasons.push("El producto no esta publicado en la tienda online.");
  }
  if (data.show_on_website !== true) {
    reasons.push("El producto no esta incluido en el catalogo web.");
  }
  if (data.is_google_merchant !== true) {
    reasons.push("Google Merchant esta desactivado para este producto.");
  }
  if (data.lifecycle_status !== "active") {
    reasons.push(
      `El ciclo de vida es ${cleanText(data.lifecycle_status) || "desconocido"}, no active.`,
    );
  }
  if (data.product_type !== "product") {
    reasons.push("Solo los productos fisicos entran al feed Merchant.");
  }
  if (!hasSupportedEcommerceTaxRate(data.tax_rate)) {
    reasons.push("La clasificación tributaria debe ser exenta (0) o afecta a IVA (19).");
  }
  let linkedBrand = "";
  if (cleanText(data.brand_id)) {
    const { data: brandRow } = await client
      .from("product_brands")
      .select("name, tenant_id, is_active")
      .eq("id", data.brand_id)
      .eq("is_active", true)
      .or(`tenant_id.eq.${data.tenant_id},tenant_id.is.null`)
      .maybeSingle();
    linkedBrand = cleanText(brandRow?.name);
  }
  const commerce = projectPublicCommerceProduct(canonicalProduct, {
    resolvedBrand: linkedBrand,
  });
  const issueMessages: Record<string, string> = {
    missing_identity: "El producto no tiene una identidad local válida.",
    missing_title: "El producto necesita un título público.",
    missing_description: "El producto necesita una descripción pública.",
    invalid_price: "El precio efectivo de la tienda debe ser mayor a 0.",
    missing_image: "El producto necesita una imagen pública HTTP(S).",
    missing_brand:
      "El producto necesita una marca de fabricante verificable; origen, marketplace o Genérico no sirven como marca.",
    missing_product_identifiers:
      "El producto necesita un GTIN válido o la combinación de marca y MPN del fabricante.",
  };
  reasons.push(
    ...commerce.merchant_issues.map((issue) =>
      issueMessages[issue] || `El producto no cumple la regla Merchant: ${issue}.`
    ),
  );

  const currency = commerce.currency;
  if (currency !== "CLP") {
    reasons.push("La moneda de la tienda para Chile debe ser CLP.");
  }
  const availableQuantity = resolveAvailableProductQuantity(canonicalProduct);
  const hasPublicImage = commerce.image_urls.length > 0;
  const hasExplicitBrand = !commerce.merchant_issues.includes("missing_brand");

  return {
    known: true,
    eligible: reasons.length === 0,
    reasons,
    product: {
      id: data.id,
      name: commerce.title,
      isActive: data.is_active === true,
      isPublished: data.is_published === true,
      showOnWebsite: data.show_on_website === true,
      isGoogleMerchant: data.is_google_merchant === true,
      lifecycleStatus: data.lifecycle_status,
      productType: data.product_type,
      price: commerce.price,
      currency,
      stockQuantity: availableQuantity,
      hasPublicImage,
      hasExplicitBrand,
      merchantBrand: commerce.brand || null,
      taxRate: data.tax_rate,
    },
  };
}

async function listSearchConsoleSites(
  accessToken: string,
  expectedSiteUrl: string,
): Promise<{
  sites: Array<{ siteUrl: string; permissionLevel: string }>;
  error?: string | null;
}> {
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
    return {
      sites: [],
      error: payload?.error?.message || JSON.stringify(payload),
    };
  }

  const siteEntry = Array.isArray(payload?.siteEntry) ? payload.siteEntry : [];
  return {
    sites: siteEntry
      .map((site: Record<string, unknown>) => ({
        siteUrl: cleanText(site?.siteUrl),
        permissionLevel: cleanText(site?.permissionLevel),
      }))
      .filter(
        (site: { siteUrl: string }) => site.siteUrl === expectedSiteUrl,
      ),
    error: null,
  };
}

async function searchConsoleOAuthToken(
  tenantId: string,
  siteUrl: string,
): Promise<
  {
    ok: true;
    accessToken: string;
    scope: string;
  } | {
    ok: false;
    error: string;
    requiredSecrets?: string[];
    reconnectRequired?: boolean;
  }
> {
  const clientId = Deno.env.get("GOOGLE_SEARCH_CONSOLE_CLIENT_ID") || "";
  const clientSecret = Deno.env.get("GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET") || "";
  if (!clientId || !clientSecret) {
    return {
      ok: false,
      error: "Search Console OAuth is not configured.",
      requiredSecrets: [
        ...(clientId ? [] : ["GOOGLE_SEARCH_CONSOLE_CLIENT_ID"]),
        ...(clientSecret ? [] : ["GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET"]),
      ],
    };
  }

  const data = await readGoogleOAuthConnection(tenantId, siteUrl);
  if (!data) {
    return {
      ok: false,
      error: "Search Console is not connected yet.",
    };
  }
  const connectionGeneration = Number(data.generation);
  const credentialVersion = Number(data.credential_version);
  if (
    !Number.isSafeInteger(connectionGeneration) ||
    connectionGeneration < 0 ||
    !Number.isSafeInteger(credentialVersion) ||
    credentialVersion < 0
  ) {
    throw new HttpError(409, "Search Console credential version is invalid.");
  }

  const expiresAt = data.expires_at ? new Date(String(data.expires_at)).getTime() : 0;
  const currentAccessToken = cleanText(data.access_token);
  if (currentAccessToken && expiresAt > Date.now() + 120000) {
    return {
      ok: true,
      accessToken: currentAccessToken,
      scope: cleanText(data.scope),
    };
  }

  const refreshToken = cleanText(data.refresh_token);
  if (!refreshToken) {
    return {
      ok: false,
      error: "Search Console needs to be reconnected to refresh access.",
    };
  }

  let refreshed;
  try {
    refreshed = await refreshGoogleOAuthToken({
      clientId,
      clientSecret,
      refreshToken,
    });
  } catch (_) {
    return {
      ok: false,
      reconnectRequired: true,
      error: "La autorización de Search Console expiró. Reconecta Google una vez para continuar.",
    };
  }
  const expiresAtDate = new Date(
    Date.now() + Number(refreshed.expires_in || 3600) * 1000,
  );

  return await persistOrReuseConcurrentGoogleOAuthRefresh({
    tenantId,
    siteUrl,
    generation: connectionGeneration,
    expectedCredentialVersion: credentialVersion,
    refreshedAccessToken: cleanText(refreshed.access_token),
    tokenType: cleanText(refreshed.token_type) || "Bearer",
    scope: cleanText(refreshed.scope || data.scope),
    expiresAt: expiresAtDate.toISOString(),
  });
}

async function readGoogleOAuthConnection(
  tenantId: string,
  siteUrl: string,
): Promise<GoogleOAuthConnectionSnapshot | null> {
  const { data, error } = await adminClient()
    .from("google_oauth_tenant_connections")
    .select(
      "access_token, refresh_token, expires_at, scope, generation, credential_version",
    )
    .eq("tenant_id", tenantId)
    .eq("integration_key", searchConsoleIntegrationKey)
    .eq("site_url", siteUrl)
    .maybeSingle();

  if (error) throw error;
  return data as GoogleOAuthConnectionSnapshot | null;
}

export async function persistOrReuseConcurrentGoogleOAuthRefresh(
  args: {
    tenantId: string;
    siteUrl: string;
    generation: number;
    expectedCredentialVersion: number;
    refreshedAccessToken: string;
    tokenType: string;
    scope: string;
    expiresAt: string;
    nowMs?: number;
  },
  invoke: RpcInvoker = invokeAdminRpc,
  readCurrent: GoogleOAuthConnectionReader = readGoogleOAuthConnection,
): Promise<{ ok: true; accessToken: string; scope: string }> {
  const { data: refreshCommitted, error: updateError } = await invoke(
    "refresh_google_oauth_access_token",
    {
      p_tenant_id: args.tenantId,
      p_integration_key: searchConsoleIntegrationKey,
      p_site_url: args.siteUrl,
      p_generation: args.generation,
      p_expected_credential_version: args.expectedCredentialVersion,
      p_access_token: args.refreshedAccessToken,
      p_token_type: args.tokenType,
      p_scope: args.scope || null,
      p_expires_at: args.expiresAt,
    },
  );
  if (updateError) throw updateError;
  if (refreshCommitted === true) {
    return {
      ok: true,
      accessToken: args.refreshedAccessToken,
      scope: args.scope,
    };
  }

  // A same-generation winner may have refreshed first. Re-read the exact
  // tenant/site row and reuse that committed token. A reconnect changes the
  // generation and therefore still fails closed instead of mixing accounts.
  const current = await readCurrent(args.tenantId, args.siteUrl);
  const currentGeneration = Number(current?.generation);
  const currentVersion = Number(current?.credential_version);
  const currentAccessToken = cleanText(current?.access_token);
  const currentExpiresAt = current?.expires_at ? new Date(String(current.expires_at)).getTime() : 0;
  if (
    currentGeneration === args.generation &&
    Number.isSafeInteger(currentVersion) &&
    currentVersion > args.expectedCredentialVersion &&
    currentAccessToken &&
    currentExpiresAt > (args.nowMs ?? Date.now()) + 30_000
  ) {
    return {
      ok: true,
      accessToken: currentAccessToken,
      scope: cleanText(current?.scope),
    };
  }

  throw new HttpError(
    409,
    "Search Console was reconnected while its token was refreshing; retry with the current connection.",
  );
}

export async function searchConsoleAccessToken({
  tenantId,
  siteUrl,
  requireWrite = false,
}: {
  tenantId: string;
  siteUrl: string;
  requireWrite?: boolean;
}, dependencies: {
  oauthToken?: typeof searchConsoleOAuthToken;
  serviceAccountToken?: () => Promise<
    {
      accessToken: string;
      email: string;
    } | null
  >;
} = {}): Promise<
  {
    ok: true;
    accessToken: string;
    scope: string;
    source: "oauth" | "service_account";
    serviceAccountEmail?: string;
  } | {
    ok: false;
    error: string;
    requiredSecrets?: string[];
    reconnectRequired?: boolean;
  }
> {
  // The exact tenant/site OAuth connection is the primary credential. A
  // project-wide service account is only a fallback when no usable tenant
  // credential exists.
  const oauth = await (dependencies.oauthToken ?? searchConsoleOAuthToken)(
    tenantId,
    siteUrl,
  );
  if (oauth.ok && hasSearchConsoleScope(oauth.scope, requireWrite)) {
    return { ...oauth, source: "oauth" };
  }

  const serviceAccountProvider = dependencies.serviceAccountToken ??
    (async () => {
      const email = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL") || "";
      const privateKey = normalizePrivateKey(
        Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY") || "",
      );
      if (!email || !privateKey) return null;
      const accessToken = await serviceAccountAccessToken({
        email,
        privateKey,
        scopes: ["https://www.googleapis.com/auth/webmasters"],
      });
      return { accessToken, email };
    });

  try {
    const serviceAccount = await serviceAccountProvider();
    if (serviceAccount) {
      return {
        ok: true,
        accessToken: serviceAccount.accessToken,
        scope: "https://www.googleapis.com/auth/webmasters",
        source: "service_account",
        serviceAccountEmail: serviceAccount.email,
      };
    }
  } catch (_) {
    // Preserve the tenant OAuth error below; it is more actionable than a
    // project-wide service-account failure.
  }

  if (!oauth.ok) return oauth;
  return {
    ok: false,
    reconnectRequired: true,
    error: "Reconecta Search Console una vez para autorizar el envío del sitemap.",
  };
}

function hasSearchConsoleScope(scope: string, requireWrite: boolean) {
  const scopes = scope.split(/\s+/).filter(Boolean);
  if (scopes.includes("https://www.googleapis.com/auth/webmasters")) {
    return true;
  }
  return !requireWrite &&
    scopes.includes("https://www.googleapis.com/auth/webmasters.readonly");
}

async function refreshGoogleOAuthToken(args: {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
}) {
  const { response, payload } = await fetchGoogleJson(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: args.clientId,
        client_secret: args.clientSecret,
        refresh_token: args.refreshToken,
        grant_type: "refresh_token",
      }),
    },
  );
  if (!response.ok || !payload.access_token) {
    throw new Error(
      payload?.error_description || payload?.error || "Could not refresh Google OAuth token",
    );
  }
  return payload;
}

async function inspectMerchant(args: {
  email: string;
  privateKey: string;
  merchantAccountId: string;
  offerId: string;
  feedEligibility: Awaited<ReturnType<typeof getMerchantFeedEligibility>> | null;
}) {
  try {
    if (args.feedEligibility?.known && !args.feedEligibility.eligible) {
      return {
        configured: true,
        ok: false,
        status: "not_in_feed",
        error: `Este producto no se esta enviando al feed Merchant: ${
          args.feedEligibility.reasons.join(" ")
        }`,
        feedEligibility: args.feedEligibility,
      };
    }

    const budget = createNetworkBudget(15_000, 3);
    const token = await serviceAccountAccessToken(
      {
        email: args.email,
        privateKey: args.privateKey,
        scopes: [merchantScope],
      },
      budget,
    );

    const attempts = [];
    for (const contentLanguage of ["es", "en"]) {
      const url = merchantProductUrl({
        accountId: args.merchantAccountId,
        contentLanguage,
        feedLabel: "CL",
        offerId: args.offerId,
      });
      const { response, payload } = await fetchGoogleJson(
        url,
        {
          headers: {
            Authorization: `Bearer ${token}`,
            Accept: "application/json",
          },
        },
        budget,
      );
      attempts.push({ contentLanguage, status: response.status, payload });
      if (response.status === 401 || response.status === 403) {
        const googleError = cleanText(payload?.error?.message);
        const registrationRequired = googleError.toLowerCase().includes(
          "not registered with the merchant account",
        );
        return {
          configured: true,
          ok: false,
          api: "merchant_v1",
          status: registrationRequired
            ? "merchant_api_registration_required"
            : "merchant_access_denied",
          registrationRequired,
          error: googleError ||
            "La cuenta tecnica de Google no tiene acceso a este Merchant Center. Agrega el service account como administrador en Merchant Center o corrige GOOGLE_MERCHANT_ACCOUNT_ID.",
          feedEligibility: args.feedEligibility,
          attempts,
        };
      }
      if (response.ok) {
        const summary = merchantProductSummary(payload);
        return {
          configured: true,
          ok: true,
          api: "merchant_v1",
          feedEligibility: args.feedEligibility,
          ...summary,
          raw: payload,
        };
      }
    }

    return {
      configured: true,
      ok: false,
      api: "merchant_v1",
      status: "not_found_or_not_ready",
      error: args.feedEligibility?.eligible
        ? "El producto cumple las reglas locales del feed, pero Merchant Center aun no lo encuentra. Fuerza una lectura del feed en Merchant Center o espera a que Google procese el item."
        : "Merchant product status was not found yet. It may still be processing, or the offer id/language/country differs.",
      feedEligibility: args.feedEligibility,
      attempts,
    };
  } catch (error) {
    return {
      configured: true,
      ok: false,
      api: "merchant_v1",
      error: errorMessage(error),
      feedEligibility: args.feedEligibility,
    };
  }
}

export function merchantIntegrationForTenant(tenantId: string) {
  const accountId = cleanText(Deno.env.get("GOOGLE_MERCHANT_ACCOUNT_ID"));
  const ownerTenantId = cleanText(
    Deno.env.get("GOOGLE_MERCHANT_TENANT_ID"),
  ).toLowerCase();
  const requiredSecrets = [
    ...(accountId ? [] : ["GOOGLE_MERCHANT_ACCOUNT_ID"]),
    ...(isUuid(ownerTenantId) ? [] : ["GOOGLE_MERCHANT_TENANT_ID"]),
  ];
  if (requiredSecrets.length > 0) {
    return {
      configured: false as const,
      accountId: "",
      requiredSecrets,
      error:
        "Merchant requiere una cuenta y un tenant propietario explícitos antes de consultar Google.",
    };
  }
  if (ownerTenantId !== tenantId.toLowerCase()) {
    return {
      configured: false as const,
      accountId: "",
      requiredSecrets: [],
      error: "Merchant no está autorizado para este tenant.",
    };
  }
  return {
    configured: true as const,
    accountId,
    requiredSecrets: [],
    error: null,
  };
}

export function beginMerchantRefresh(tenantId: string) {
  const now = Date.now();
  const current = merchantRefreshWindows.get(tenantId);
  const window = !current ||
      now - current.startedAt >= merchantRefreshRateWindowMs
    ? { startedAt: now, count: 0 }
    : current;
  if (window.count >= merchantRefreshRateLimit) {
    throw new HttpError(
      429,
      "Merchant refresh rate limit reached; retry in one minute",
    );
  }
  if (activeMerchantRefreshTenants.has(tenantId)) {
    throw new HttpError(
      409,
      "A Merchant refresh is already running for this tenant",
    );
  }

  window.count += 1;
  merchantRefreshWindows.set(tenantId, window);
  activeMerchantRefreshTenants.add(tenantId);
  return () => activeMerchantRefreshTenants.delete(tenantId);
}

async function invokeAdminRpc(
  functionName: string,
  args: Record<string, unknown>,
): Promise<RpcResult> {
  const { data, error } = await adminClient().rpc(functionName, args);
  return { data, error };
}

export async function acquireDurableMerchantRefreshLease(
  tenantId: string,
  invoke: RpcInvoker = invokeAdminRpc,
) {
  const { data, error } = await invoke(
    "acquire_google_merchant_refresh_lease",
    { p_tenant_id: tenantId },
  );
  if (error) {
    throw new Error(
      error.message || "Could not acquire the Merchant refresh lease",
    );
  }
  const result = data && typeof data === "object" ? data as Record<string, unknown> : {};
  if (result.acquired !== true) {
    const reason = cleanText(result.reason);
    throw new HttpError(
      reason === "rate_limited" ? 429 : 409,
      reason === "rate_limited"
        ? "Merchant refresh rate limit reached; retry later"
        : "A Merchant refresh is already running for this tenant",
    );
  }
  const leaseToken = cleanText(result.lease_token);
  if (!isUuid(leaseToken)) {
    throw new Error("Merchant refresh lease returned an invalid token");
  }
  const leaseFence = Number(result.lease_fence);
  if (!Number.isSafeInteger(leaseFence) || leaseFence <= 0) {
    throw new Error("Merchant refresh lease returned an invalid fence");
  }
  return { token: leaseToken, fence: leaseFence };
}

export async function renewDurableMerchantRefreshLease(
  tenantId: string,
  lease: { token: string; fence: number },
  invoke: RpcInvoker = invokeAdminRpc,
) {
  const { data, error } = await invoke(
    "renew_google_merchant_refresh_lease",
    {
      p_tenant_id: tenantId,
      p_lease_token: lease.token,
      p_lease_fence: lease.fence,
    },
  );
  if (error) {
    throw new Error(
      error.message || "Could not renew the Merchant refresh lease",
    );
  }
  const result = data && typeof data === "object" ? data as Record<string, unknown> : {};
  return result.renewed === true &&
    cleanText(result.lease_token) === lease.token &&
    Number(result.lease_fence) === lease.fence;
}

export async function releaseDurableMerchantRefreshLease(
  tenantId: string,
  lease: { token: string; fence: number },
  invoke: RpcInvoker = invokeAdminRpc,
) {
  const { data, error } = await invoke(
    "release_google_merchant_refresh_lease",
    {
      p_tenant_id: tenantId,
      p_lease_token: lease.token,
      p_lease_fence: lease.fence,
    },
  );
  if (error) {
    throw new Error(
      error.message || "Could not release the Merchant refresh lease",
    );
  }
  return data === true;
}

async function refreshMerchantFeeds(tenantId: string) {
  const releaseLocalGuard = beginMerchantRefresh(tenantId);
  let durableLease: { token: string; fence: number } | null = null;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let renewalInFlight: Promise<void> | null = null;
  let leaseLost = false;
  try {
    durableLease = await acquireDurableMerchantRefreshLease(tenantId);
    if (
      !await renewDurableMerchantRefreshLease(
        tenantId,
        durableLease,
      )
    ) {
      throw new HttpError(
        409,
        "Merchant refresh lost its durable lease before starting",
      );
    }

    heartbeat = setInterval(() => {
      if (renewalInFlight || !durableLease) return;
      renewalInFlight = renewDurableMerchantRefreshLease(
        tenantId,
        durableLease,
      )
        .then((renewed) => {
          if (!renewed) leaseLost = true;
        })
        .catch((error) => {
          leaseLost = true;
          console.error("Merchant durable lease renewal failed", error);
        })
        .finally(() => {
          renewalInFlight = null;
        });
    }, 15_000);

    const result = await refreshMerchantFeedsGuarded(tenantId);
    if (renewalInFlight) await renewalInFlight;
    if (leaseLost) {
      throw new HttpError(
        409,
        "Merchant refresh lost its durable lease while running",
      );
    }
    return result;
  } finally {
    if (heartbeat !== undefined) clearInterval(heartbeat);
    if (renewalInFlight) {
      try {
        await renewalInFlight;
      } catch (_) {
        // The renewal path already records lease loss and the release below is
        // still exact-token/exact-fence and therefore safe.
      }
    }
    if (durableLease) {
      try {
        await releaseDurableMerchantRefreshLease(
          tenantId,
          durableLease,
        );
      } catch (error) {
        console.error("Merchant durable lease release failed", error);
      }
    }
    releaseLocalGuard();
  }
}

async function refreshMerchantFeedsGuarded(tenantId: string) {
  const email = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL") || "";
  const privateKey = normalizePrivateKey(
    Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY") || "",
  );
  const merchantConfig = merchantIntegrationForTenant(tenantId);
  if (!email || !privateKey || !merchantConfig.configured) {
    return {
      ok: false,
      configured: false,
      error: merchantConfig.error || "Merchant feed refresh is not configured.",
      requiredSecrets: [
        ...(email && privateKey ? [] : [
          "GOOGLE_SERVICE_ACCOUNT_EMAIL",
          "GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY",
        ]),
        ...merchantConfig.requiredSecrets,
      ],
    };
  }

  const budget = createNetworkBudget(
    merchantOperationDeadlineMs,
    merchantRequestLimit,
  );
  const token = await serviceAccountAccessToken(
    {
      email,
      privateKey,
      scopes: [merchantScope],
    },
    budget,
  );
  const feeds = [];
  let pageToken = "";
  const seenPageTokens = new Set<string>();
  let pageCount = 0;
  do {
    pageCount += 1;
    if (pageCount > merchantPageLimit) {
      return {
        ok: false,
        configured: true,
        status: "merchant_pagination_limit",
        error: "Merchant devolvió más páginas que el límite seguro.",
      };
    }
    if (pageToken) {
      if (seenPageTokens.has(pageToken)) {
        return {
          ok: false,
          configured: true,
          status: "merchant_pagination_replay",
          error: "Merchant repitió un cursor de paginación.",
        };
      }
      seenPageTokens.add(pageToken);
    }

    const listUrl = new URL(
      merchantDataSourcesUrl(merchantConfig.accountId),
    );
    if (pageToken) listUrl.searchParams.set("pageToken", pageToken);
    const { response: listResponse, payload: listPayload } = await fetchGoogleJson(
      listUrl,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
        },
      },
      budget,
    );
    if (!listResponse.ok) {
      const googleError = cleanText(listPayload?.error?.message);
      const registrationRequired = googleError.toLowerCase().includes(
        "not registered with the merchant account",
      );
      return {
        ok: false,
        configured: true,
        api: "merchant_v1",
        status: registrationRequired ? "merchant_api_registration_required" : listResponse.status,
        registrationRequired,
        error: googleError || JSON.stringify(listPayload),
      };
    }
    if (Array.isArray(listPayload?.dataSources)) {
      feeds.push(...listPayload.dataSources);
      if (feeds.length > merchantDataSourceLimit) {
        return {
          ok: false,
          configured: true,
          status: "merchant_data_source_limit",
          error: "Merchant devolvió más fuentes que el límite seguro.",
        };
      }
    }
    pageToken = cleanText(listPayload?.nextPageToken);
  } while (pageToken);

  const fetchableFeeds = feeds
    .filter(isFetchableMerchantDataSource)
    .slice(0, merchantDataSourceLimit);
  const results = [];
  for (const feed of fetchableFeeds) {
    const name = cleanText(feed?.name);
    if (!name) continue;
    const { response, payload } = await fetchGoogleJson(
      merchantDataSourceFetchUrl(name),
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: "{}",
      },
      budget,
    );
    results.push({
      id: cleanText(feed?.dataSourceId),
      name,
      displayName: cleanText(feed?.displayName),
      ok: response.ok,
      status: response.status,
      error: response.ok ? null : payload?.error?.message || JSON.stringify(payload),
    });
  }

  return {
    ok: results.length > 0 && results.every((result) => result.ok),
    configured: true,
    api: "merchant_v1",
    feedCount: results.length,
    dataSourceCount: feeds.length,
    error: results.length === 0
      ? "Merchant API no encontro una fuente URL actualizable para este comercio."
      : null,
    results,
  };
}

async function serviceAccountAccessToken(args: {
  email: string;
  privateKey: string;
  scopes: string[];
}, budget?: NetworkBudget) {
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: args.email,
    scope: args.scopes.join(" "),
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const jwt = await signJwt({ claim, privateKey: args.privateKey });
  const { response, payload } = await fetchGoogleJson(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    },
    budget,
  );
  if (!response.ok || !payload.access_token) {
    throw new Error(
      payload?.error_description || payload?.error || "Could not get Google access token",
    );
  }
  return payload.access_token as string;
}

async function signJwt(args: {
  claim: Record<string, unknown>;
  privateKey: string;
}) {
  const encoder = new TextEncoder();
  const header = { alg: "RS256", typ: "JWT" };
  const signingInput = `${base64UrlJson(header)}.${base64UrlJson(args.claim)}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(args.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function base64UrlJson(value: Record<string, unknown>) {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToArrayBuffer(pem: string) {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function normalizePrivateKey(value: string) {
  return value.replace(/\\n/g, "\n").trim();
}

function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

async function requireWebsiteSeoEditor(req: Request) {
  const authorization = req.headers.get("Authorization");
  if (!authorization) throw new HttpError(401, "Unauthorized");

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new HttpError(401, "Unauthorized");

  const admin = adminClient();
  const { data: profiles, error: profileError } = await admin
    .from("user_profiles")
    .select("tenant_id, role, permissions")
    .eq("user_id", data.user.id)
    .eq("is_active", true)
    .limit(2);
  if (profileError) throw profileError;
  if (!profiles || profiles.length !== 1) {
    throw new HttpError(
      403,
      "Exactly one active tenant profile is required",
    );
  }

  const profile = profiles[0];
  const permissions = profile?.permissions &&
      typeof profile.permissions === "object"
    ? profile.permissions as Record<string, unknown>
    : {};
  const canEdit = cleanText(profile.role) === "admin" ||
    permissions.edit_settings === true;
  if (!profile?.tenant_id || !canEdit) {
    throw new HttpError(403, "Insufficient website settings permission");
  }
  const tenantId = cleanText(profile.tenant_id);
  const { data: tenant, error: tenantError } = await admin
    .from("tenants")
    .select("id")
    .eq("id", tenantId)
    .eq("is_active", true)
    .maybeSingle();
  if (tenantError) throw tenantError;
  if (!tenant) throw new HttpError(403, "The tenant is not active");

  return {
    userId: data.user.id,
    tenantId,
  };
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
    throw new HttpError(409, "The tenant public store is not active");
  }

  const values = new Map<string, string>(
    (settingsResult.data || []).map(
      (row: { key?: unknown; value?: unknown }) =>
        [
          cleanText(row.key),
          cleanText(row.value),
        ] as const,
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
    /^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$/.test(baseDomain) &&
    !baseDomain.includes("..")
  ) {
    const subdomainOrigin = strictHttpsOrigin(
      `https://${subdomain}.${baseDomain}`,
    );
    if (subdomainOrigin) ownedOrigins.add(subdomainOrigin);
  }

  if (ownedOrigins.size === 0) {
    throw new HttpError(
      409,
      "The tenant public store URL is not in the server allowlist",
    );
  }

  const configured = cleanText(input.configuredStoreUrl);
  if (configured) {
    const configuredOrigin = strictHttpsOrigin(configured);
    if (!configuredOrigin) {
      throw new HttpError(409, "The tenant public store URL is invalid");
    }
    if (!ownedOrigins.has(configuredOrigin)) {
      throw new HttpError(
        409,
        "The configured store URL does not belong to this tenant",
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

function validatedPublicStoreOrigin(rawUrl: string) {
  const origin = strictHttpsOrigin(rawUrl);
  if (!origin) {
    throw new HttpError(409, "The tenant public store URL is invalid");
  }
  return origin;
}

function assertServerOwnedArtifactOrigin(
  origin: string,
  options: SiteArtifactFetchOptions,
) {
  const exactOrigins = new Set<string>();
  const configuredOrigins = options.serverOwnedOrigins || [
    ...configuredPublicStoreOrigins(
      Deno.env.get("PUBLIC_STORE_ORIGINS"),
      configuredSearchConsoleSiteForTenant(options.tenantId || ""),
    ),
  ];
  for (const candidate of configuredOrigins) {
    const normalized = strictHttpsOrigin(candidate);
    if (normalized) exactOrigins.add(normalized);
  }
  if (exactOrigins.has(origin)) return;

  const baseDomain = cleanText(
    options.serverOwnedBaseDomain ||
      Deno.env.get("PUBLIC_STORE_BASE_DOMAIN"),
  ).toLowerCase();
  const hostname = new URL(origin).hostname.toLowerCase();
  if (
    isPublicHostname(baseDomain) &&
    hostname.endsWith(`.${baseDomain}`) &&
    hostname.length > baseDomain.length + 1
  ) {
    return;
  }

  throw new HttpError(
    403,
    "Site evidence fetch is limited to exact server-owned origins",
  );
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

async function resolvePublicDnsAddresses(hostname: string) {
  const results = await Promise.allSettled([
    Deno.resolveDns(hostname, "A"),
    Deno.resolveDns(hostname, "AAAA"),
  ]);
  const addresses = results.flatMap((result) => result.status === "fulfilled" ? result.value : []);
  if (addresses.length === 0) {
    throw new Error("The public store hostname did not resolve");
  }
  return addresses;
}

async function assertPublicDnsResolution(
  hostname: string,
  resolver: DnsResolver,
) {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    const addresses = await Promise.race([
      resolver(hostname),
      new Promise<string[]>((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error("Public store DNS resolution timed out")),
          4_000,
        );
      }),
    ]);
    if (
      addresses.length === 0 ||
      addresses.some((address) => isPrivateOrReservedIp(address))
    ) {
      throw new HttpError(
        403,
        "The public store DNS result is private or reserved",
      );
    }
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(
      409,
      `The public store DNS could not be verified: ${errorMessage(error)}`,
    );
  } finally {
    if (timeout !== undefined) clearTimeout(timeout);
  }
}

export function isPrivateOrReservedIp(rawAddress: string): boolean {
  const address = cleanText(rawAddress).toLowerCase();
  const ipv4 = parseIpv4(address);
  if (ipv4) {
    const value = ipv4ToNumber(ipv4);
    return ipv4Range(value, "0.0.0.0", 8) ||
      ipv4Range(value, "10.0.0.0", 8) ||
      ipv4Range(value, "100.64.0.0", 10) ||
      ipv4Range(value, "127.0.0.0", 8) ||
      ipv4Range(value, "169.254.0.0", 16) ||
      ipv4Range(value, "172.16.0.0", 12) ||
      ipv4Range(value, "192.0.0.0", 24) ||
      ipv4Range(value, "192.0.2.0", 24) ||
      ipv4Range(value, "192.88.99.0", 24) ||
      ipv4Range(value, "192.168.0.0", 16) ||
      ipv4Range(value, "198.18.0.0", 15) ||
      ipv4Range(value, "198.51.100.0", 24) ||
      ipv4Range(value, "203.0.113.0", 24) ||
      ipv4Range(value, "224.0.0.0", 4) ||
      ipv4Range(value, "240.0.0.0", 4);
  }

  const ipv6 = parseIpv6(address);
  if (!ipv6) return true;
  const [first, second] = ipv6;
  const firstFiveZero = ipv6.slice(0, 5).every((value) => value === 0);
  if (firstFiveZero && (ipv6[5] === 0 || ipv6[5] === 0xffff)) {
    const embedded = ((ipv6[6] << 16) + ipv6[7]) >>> 0;
    if (ipv6[5] === 0xffff || embedded > 1) {
      return isPrivateOrReservedIp(ipv4NumberToString(embedded));
    }
  }

  if (
    ipv6.every((value) => value === 0) ||
    (ipv6.slice(0, 7).every((value) => value === 0) && ipv6[7] === 1) ||
    (ipv6.slice(0, 4).every((value) => value === 0) &&
      ipv6[4] === 0xffff &&
      ipv6[5] === 0) ||
    (first === 0x0064 && second === 0xff9b) ||
    (first === 0x0100 && ipv6.slice(1, 4).every((value) => value === 0)) ||
    (first === 0x2001 && second <= 0x01ff) ||
    (first === 0x2001 && second === 0x0db8) ||
    first === 0x2002 ||
    (first & 0xfe00) === 0xfc00 ||
    (first & 0xffc0) === 0xfe80 ||
    (first & 0xffc0) === 0xfec0 ||
    (first & 0xff00) === 0xff00 ||
    (first & 0xfff0) === 0x3ff0 ||
    first === 0x5f00
  ) {
    return true;
  }
  // DNS artifact fetches accept ordinary global-unicast IPv6 only. IPv4
  // mapped/compatible addresses were handled explicitly above; every other
  // address outside 2000::/3 fails closed, including future/special ranges.
  return (first & 0xe000) !== 0x2000;
}

function parseIpv4(value: string) {
  if (!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(value)) return null;
  const bytes = value.split(".").map(Number);
  return bytes.every((byte) => byte >= 0 && byte <= 255)
    ? bytes as [number, number, number, number]
    : null;
}

function ipv4ToNumber(bytes: [number, number, number, number]) {
  return (
    ((bytes[0] << 24) >>> 0) +
    (bytes[1] << 16) +
    (bytes[2] << 8) +
    bytes[3]
  ) >>> 0;
}

function ipv4Range(value: number, base: string, prefixLength: number) {
  const baseBytes = parseIpv4(base);
  if (!baseBytes) return true;
  const mask = prefixLength === 0 ? 0 : (0xffffffff << (32 - prefixLength)) >>> 0;
  return (value & mask) === (ipv4ToNumber(baseBytes) & mask);
}

function ipv4NumberToString(value: number) {
  return [
    (value >>> 24) & 0xff,
    (value >>> 16) & 0xff,
    (value >>> 8) & 0xff,
    value & 0xff,
  ].join(".");
}

function parseIpv6(value: string): number[] | null {
  if (!value || value.includes("%") || value.includes(":::")) return null;
  let normalized = value;
  const ipv4Tail = normalized.match(/(\d{1,3}(?:\.\d{1,3}){3})$/);
  if (ipv4Tail) {
    const ipv4 = parseIpv4(ipv4Tail[1]);
    if (!ipv4) return null;
    normalized = normalized.slice(0, -ipv4Tail[1].length) +
      `${((ipv4[0] << 8) | ipv4[1]).toString(16)}:${((ipv4[2] << 8) | ipv4[3]).toString(16)}`;
  }

  const halves = normalized.split("::");
  if (halves.length > 2) return null;
  const left = halves[0] ? halves[0].split(":") : [];
  const right = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  if (
    [...left, ...right].some((part) => !/^[0-9a-f]{1,4}$/.test(part))
  ) {
    return null;
  }

  const omitted = 8 - left.length - right.length;
  if (
    (halves.length === 1 && omitted !== 0) ||
    (halves.length === 2 && omitted < 1)
  ) {
    return null;
  }
  return [
    ...left.map((part) => Number.parseInt(part, 16)),
    ...Array.from({ length: omitted }, () => 0),
    ...right.map((part) => Number.parseInt(part, 16)),
  ];
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
      "Search Console is not configured for this tenant domain",
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

function assertStoreUrl(rawUrl: string, storeUrl: string) {
  let candidate: URL;
  try {
    candidate = new URL(rawUrl);
  } catch (_) {
    throw new HttpError(400, "Invalid product URL");
  }
  if (candidate.origin !== new URL(storeUrl).origin) {
    throw new HttpError(403, "The inspected URL is outside the tenant store");
  }
}

function ensureTrailingSlash(value: string) {
  return value.endsWith("/") ? value : `${value}/`;
}

function cleanText(value: unknown) {
  return String(value ?? "").trim();
}

function canonicalUrlKey(value: unknown) {
  const raw = cleanText(value);
  if (!raw) return "";
  try {
    const url = new URL(raw);
    const path = url.pathname === "/" ? "" : url.pathname.replace(/\/+$/g, "");
    return `${url.protocol}//${url.host}${path}${url.search}`;
  } catch (_) {
    return raw.replace(/\/+$/g, "");
  }
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
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
      origins.add(new URL(value).origin);
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

function responseHeaders(req: Request) {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache",
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
  };
  const origin = cleanText(req.headers.get("Origin"));
  if (origin && isAllowedCorsOrigin(origin)) {
    headers["Access-Control-Allow-Origin"] = new URL(origin).origin;
  }
  return headers;
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
