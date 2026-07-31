import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { constantTimeEqual } from "../_shared/transactional_email/crypto.ts";

const vinabikeTenantId = "5443b130-cc28-45af-a420-cd500b288890";
const githubRepository = "Ccatalan7/bikeshop-erp";
const githubWorkflow = "firebase-hosting-store.yml";
const githubRef = "main";
const githubApi = "https://api.github.com";
const requestTimeoutMs = 12_000;
const reconciliationRetrySeconds = 300;

type JsonRecord = Record<string, unknown>;

type RpcResult = {
  data: unknown;
  error: { message: string } | null;
};

export type StorefrontPublicationRpcClient = {
  rpc(
    name: string,
    params: Record<string, unknown>,
  ): PromiseLike<RpcResult>;
};

type ClaimedPublication = {
  claim_action: "dispatch" | "reconcile";
  request_id: string;
  attempt_id: string;
  tenant_id?: string;
  target_key?: string;
  lease_token: string;
  lease_fence: number;
};

type InstallationToken = {
  token: string;
};

export type StorefrontPublicationDispatcherDependencies = {
  env(name: string): string;
  rpcClient(url: string, serviceRoleKey: string): StorefrontPublicationRpcClient;
  fetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response>;
  randomUUID(): string;
  createAppJwt(appId: string, privateKey: string): Promise<string>;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function asRecord(value: unknown): JsonRecord | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : null;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function positiveInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

function cleanError(value: unknown): string {
  const message = value instanceof Error ? value.message : String(value ?? "");
  return message.replaceAll(/[\r\n\t]+/g, " ").replaceAll(/\s+/g, " ").trim()
    .slice(0, 512) || "Unknown dispatcher error";
}

function retryAfterSeconds(response: Response): number | null {
  const raw = response.headers.get("retry-after")?.trim() ?? "";
  if (!/^\d+$/.test(raw)) return null;
  return Math.max(1, Math.min(3600, Number(raw)));
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    /=+$/g,
    "",
  );
}

function encodeJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function decodePemPrivateKey(value: string): ArrayBuffer {
  const normalized = value.replaceAll("\\n", "\n").trim();
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s+/g, "");
  if (!base64 || !normalized.includes("BEGIN PRIVATE KEY")) {
    throw new Error("GitHub App private key must be PKCS#8 PEM");
  }
  const binary = atob(base64);
  return Uint8Array.from(
    binary,
    (character) => character.charCodeAt(0),
  ).buffer;
}

export async function createGitHubAppJwt(
  appId: string,
  privateKey: string,
  now = new Date(),
): Promise<string> {
  if (!/^\d+$/.test(appId)) throw new Error("GitHub App ID is invalid");
  const issuedAt = Math.floor(now.getTime() / 1000) - 30;
  const expiresAt = issuedAt + 9 * 60;
  const encodedHeader = encodeJson({ alg: "RS256", typ: "JWT" });
  const encodedPayload = encodeJson({
    iat: issuedAt,
    exp: expiresAt,
    iss: appId,
  });
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePemPrivateKey(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function defaultDependencies(): StorefrontPublicationDispatcherDependencies {
  return {
    env: (name) => Deno.env.get(name)?.trim() ?? "",
    rpcClient: (url, serviceRoleKey) =>
      createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      }) as unknown as StorefrontPublicationRpcClient,
    fetch: globalThis.fetch.bind(globalThis),
    randomUUID: () => crypto.randomUUID(),
    createAppJwt: createGitHubAppJwt,
  };
}

async function fetchWithTimeout(
  deps: StorefrontPublicationDispatcherDependencies,
  input: RequestInfo | URL,
  init: RequestInit,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);
  try {
    return await deps.fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

async function installationToken(params: {
  deps: StorefrontPublicationDispatcherDependencies;
  appId: string;
  installationId: string;
  privateKey: string;
}): Promise<string> {
  const appJwt = await params.deps.createAppJwt(
    params.appId,
    params.privateKey,
  );
  const response = await fetchWithTimeout(
    params.deps,
    `${githubApi}/app/installations/${params.installationId}/access_tokens`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${appJwt}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "vinabike-storefront-publication-dispatcher",
      },
    },
  );
  if (!response.ok) {
    throw new Error(`GitHub installation token failed with HTTP ${response.status}`);
  }
  const body = asRecord(await response.json());
  const token = typeof body?.token === "string" ? body.token.trim() : "";
  if (!token) throw new Error("GitHub installation token response was malformed");
  return (body as InstallationToken).token;
}

function claimedPublication(value: unknown): ClaimedPublication | null {
  const row = asRecord(value);
  if (
    !row || (row.claim_action !== "dispatch" &&
      row.claim_action !== "reconcile") ||
    !isUuid(row.request_id) || !isUuid(row.attempt_id) ||
    !isUuid(row.lease_token) || !positiveInteger(row.lease_fence)
  ) {
    return null;
  }
  if (
    row.tenant_id != null && row.tenant_id !== vinabikeTenantId
  ) {
    return null;
  }
  if (row.target_key != null && row.target_key !== "vinabike-store") {
    return null;
  }
  return row as unknown as ClaimedPublication;
}

function publicationRunTitle(requestId: string): string {
  return `Storefront publication · ${requestId}`;
}

async function completeDispatch(
  client: StorefrontPublicationRpcClient,
  claim: ClaimedPublication,
  workerId: string,
  outcome: "dispatched" | "retry" | "dispatch_unknown" | "permanent_failure",
  options: {
    httpStatus?: number | null;
    errorClass?: string;
    errorMessage?: string;
    retryAfterSeconds?: number | null;
  } = {},
): Promise<void> {
  const { error } = await client.rpc(
    "complete_storefront_publication_dispatch",
    {
      p_request_id: claim.request_id,
      p_attempt_id: claim.attempt_id,
      p_worker_id: workerId,
      p_lease_token: claim.lease_token,
      p_lease_fence: claim.lease_fence,
      p_outcome: outcome,
      p_http_status: options.httpStatus ?? null,
      p_error_class: options.errorClass ?? null,
      p_error_message: options.errorMessage ?? null,
      p_retry_after_seconds: options.retryAfterSeconds ?? null,
    },
  );
  if (error) {
    throw new Error(`Could not complete publication dispatch: ${error.message}`);
  }
}

async function reconcileDispatch(params: {
  deps: StorefrontPublicationDispatcherDependencies;
  client: StorefrontPublicationRpcClient;
  claim: ClaimedPublication;
  workerId: string;
  githubToken: string;
}): Promise<Response> {
  const runsUrl = new URL(
    `${githubApi}/repos/${githubRepository}/actions/workflows/${githubWorkflow}/runs`,
  );
  runsUrl.searchParams.set("event", "workflow_dispatch");
  runsUrl.searchParams.set("branch", githubRef);
  runsUrl.searchParams.set("per_page", "100");

  let response: Response;
  try {
    response = await fetchWithTimeout(params.deps, runsUrl, {
      method: "GET",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${params.githubToken}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "vinabike-storefront-publication-dispatcher",
      },
    });
  } catch (error) {
    await completeDispatch(
      params.client,
      params.claim,
      params.workerId,
      "dispatch_unknown",
      {
        errorClass: "dispatch_reconciliation_inconclusive",
        errorMessage: cleanError(error),
        retryAfterSeconds: reconciliationRetrySeconds,
      },
    );
    return json({
      claimed: 1,
      request_id: params.claim.request_id,
      outcome: "dispatch_unknown",
    });
  }

  if (!response.ok) {
    await completeDispatch(
      params.client,
      params.claim,
      params.workerId,
      "dispatch_unknown",
      {
        httpStatus: response.status,
        errorClass: "dispatch_reconciliation_inconclusive",
        errorMessage: `GitHub workflow reconciliation returned HTTP ${response.status}`,
        retryAfterSeconds: retryAfterSeconds(response) ?? reconciliationRetrySeconds,
      },
    );
    return json({
      claimed: 1,
      request_id: params.claim.request_id,
      outcome: "dispatch_unknown",
    });
  }

  let body: JsonRecord | null = null;
  try {
    body = asRecord(await response.json());
  } catch {
    body = null;
  }
  const runs = Array.isArray(body?.workflow_runs) ? body.workflow_runs : null;
  if (runs == null) {
    await completeDispatch(
      params.client,
      params.claim,
      params.workerId,
      "dispatch_unknown",
      {
        httpStatus: response.status,
        errorClass: "dispatch_reconciliation_inconclusive",
        errorMessage: "GitHub workflow reconciliation response was malformed",
        retryAfterSeconds: reconciliationRetrySeconds,
      },
    );
    return json({
      claimed: 1,
      request_id: params.claim.request_id,
      outcome: "dispatch_unknown",
    });
  }

  const expectedTitle = publicationRunTitle(params.claim.request_id);
  const matchingRun = runs
    .map(asRecord)
    .find((run) =>
      run?.display_title === expectedTitle &&
      run?.event === "workflow_dispatch" &&
      run?.head_branch === githubRef
    );
  if (matchingRun) {
    await completeDispatch(
      params.client,
      params.claim,
      params.workerId,
      "dispatched",
      { httpStatus: 204 },
    );
    return json({
      claimed: 1,
      request_id: params.claim.request_id,
      outcome: "dispatched",
      reconciled: true,
    });
  }

  // GitHub's run listing is eventually consistent. Absence from one bounded
  // read is not proof that workflow_dispatch was rejected, so retain the
  // ambiguous state and retry reconciliation later. Never redispatch here.
  await completeDispatch(
    params.client,
    params.claim,
    params.workerId,
    "dispatch_unknown",
    {
      httpStatus: response.status,
      errorClass: "dispatch_reconciliation_inconclusive",
      errorMessage: "No exact workflow run is visible yet",
      retryAfterSeconds: reconciliationRetrySeconds,
    },
  );
  return json({
    claimed: 1,
    request_id: params.claim.request_id,
    outcome: "dispatch_unknown",
    reconciled: false,
  });
}

export async function handleStorefrontPublicationDispatcher(
  request: Request,
  injected?: Partial<StorefrontPublicationDispatcherDependencies>,
): Promise<Response> {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const defaults = defaultDependencies();
  const deps = { ...defaults, ...injected };
  const expectedSecret = deps.env("STOREFRONT_PUBLICATION_DISPATCH_SECRET");
  const suppliedSecret = request.headers.get("x-storefront-publication-dispatch-secret") ?? "";
  if (
    !expectedSecret || !suppliedSecret ||
    !constantTimeEqual(suppliedSecret, expectedSecret)
  ) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: JsonRecord | null;
  try {
    body = asRecord(await request.json());
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (
    !body || body.action !== "tick" || Object.keys(body).some((key) => key !== "action")
  ) {
    return json({ error: 'Body must be exactly {"action":"tick"}' }, 400);
  }

  const supabaseUrl = deps.env("SUPABASE_URL");
  const serviceRoleKey = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  const appId = deps.env("STOREFRONT_PUBLICATION_GITHUB_APP_ID");
  const installationId = deps.env(
    "STOREFRONT_PUBLICATION_GITHUB_INSTALLATION_ID",
  );
  const privateKey = deps.env("STOREFRONT_PUBLICATION_GITHUB_PRIVATE_KEY");
  if (
    !supabaseUrl || !serviceRoleKey || !/^\d+$/.test(appId) ||
    !/^\d+$/.test(installationId) || !privateKey
  ) {
    return json({ error: "Storefront publication worker is not configured" }, 503);
  }

  const workerId = `storefront-publication:${deps.randomUUID()}`;
  const client = deps.rpcClient(supabaseUrl, serviceRoleKey);
  const { data, error } = await client.rpc(
    "claim_storefront_publication_requests",
    {
      p_worker_id: workerId,
      p_batch_size: 1,
      p_lease_seconds: 90,
    },
  );
  if (error) return json({ error: "Could not claim publication work" }, 500);

  const rows = Array.isArray(data) ? data : [];
  if (rows.length === 0) return json({ claimed: 0, outcome: "idle" });
  if (rows.length !== 1) {
    return json({ error: "Publication claim returned an invalid batch" }, 500);
  }
  const claim = claimedPublication(rows[0]);
  if (!claim) {
    return json({ error: "Publication claim returned invalid identity" }, 500);
  }

  let githubToken: string;
  try {
    githubToken = await installationToken({
      deps,
      appId,
      installationId,
      privateKey,
    });
  } catch (tokenError) {
    const message = cleanError(tokenError);
    const permanent = claim.claim_action === "dispatch" &&
      /HTTP (401|403|404|422)\b/.test(message);
    await completeDispatch(
      client,
      claim,
      workerId,
      claim.claim_action === "reconcile"
        ? "dispatch_unknown"
        : permanent
        ? "permanent_failure"
        : "retry",
      {
        errorClass: claim.claim_action === "reconcile"
          ? "dispatch_reconciliation_inconclusive"
          : permanent
          ? "github_app_configuration"
          : "github_installation_token_unavailable",
        errorMessage: message,
        retryAfterSeconds: claim.claim_action === "reconcile" ? reconciliationRetrySeconds : null,
      },
    );
    return json({
      claimed: 1,
      request_id: claim.request_id,
      outcome: claim.claim_action === "reconcile"
        ? "dispatch_unknown"
        : permanent
        ? "permanent_failure"
        : "retry",
    });
  }

  if (claim.claim_action === "reconcile") {
    return reconcileDispatch({
      deps,
      client,
      claim,
      workerId,
      githubToken,
    });
  }

  let dispatchResponse: Response;
  try {
    dispatchResponse = await fetchWithTimeout(
      deps,
      `${githubApi}/repos/${githubRepository}/actions/workflows/${githubWorkflow}/dispatches`,
      {
        method: "POST",
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${githubToken}`,
          "Content-Type": "application/json",
          "X-GitHub-Api-Version": "2022-11-28",
          "User-Agent": "vinabike-storefront-publication-dispatcher",
        },
        body: JSON.stringify({
          ref: githubRef,
          inputs: { request_id: claim.request_id },
        }),
      },
    );
  } catch (dispatchError) {
    await completeDispatch(client, claim, workerId, "dispatch_unknown", {
      errorClass: "github_dispatch_ambiguous",
      errorMessage: cleanError(dispatchError),
    });
    return json({
      claimed: 1,
      request_id: claim.request_id,
      outcome: "dispatch_unknown",
    });
  }

  if (dispatchResponse.status === 204) {
    await completeDispatch(client, claim, workerId, "dispatched");
    return json({
      claimed: 1,
      request_id: claim.request_id,
      outcome: "dispatched",
    });
  }

  const retryable = dispatchResponse.status === 429 ||
    dispatchResponse.status >= 500;
  const outcome = retryable ? "retry" : "permanent_failure";
  await completeDispatch(client, claim, workerId, outcome, {
    errorClass: retryable ? "github_dispatch_retryable" : "github_dispatch_rejected",
    errorMessage: `GitHub workflow dispatch returned HTTP ${dispatchResponse.status}`,
    retryAfterSeconds: retryAfterSeconds(dispatchResponse),
  });
  return json({
    claimed: 1,
    request_id: claim.request_id,
    outcome,
  });
}

if (import.meta.main) {
  Deno.serve((request) => handleStorefrontPublicationDispatcher(request));
}
