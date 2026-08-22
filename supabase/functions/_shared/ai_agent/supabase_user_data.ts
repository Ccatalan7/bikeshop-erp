import type { JsonObject } from "./contracts.ts";

const DEFAULT_MAX_RESPONSE_BYTES = 256 * 1024;
const MAX_ERROR_RESPONSE_BYTES = 4 * 1024;

export type SupabaseUserDataOutcome =
  | "unavailable"
  | "invalid_response"
  | "request_aborted"
  | "idempotency_conflict"
  | "forbidden"
  | "quota_exceeded";

export class SupabaseUserDataError extends Error {
  constructor(
    readonly code: "rpc_unavailable" | "rpc_invalid_response" | "request_aborted",
    readonly retryable: boolean,
    readonly outcome: SupabaseUserDataOutcome = code === "rpc_unavailable"
      ? "unavailable"
      : code === "request_aborted"
      ? "request_aborted"
      : "invalid_response",
    /// Qué RPC falló. Es un identificador interno con forma cerrada
    /// (`^[a-z][a-z0-9_]{2,63}$`), nunca dato del operador, y sin él un fallo
    /// de este tipo obliga a bisectar en producción para saber dónde ocurrió.
    readonly rpcName?: string,
  ) {
    super(
      rpcName
        ? `Supabase caller-scoped RPC failed ${rpcName}`
        : "Supabase caller-scoped RPC failed",
    );
    this.name = "SupabaseUserDataError";
  }
}

export interface AgentRpcClient {
  rpc(name: string, parameters: JsonObject, signal: AbortSignal): Promise<unknown>;
}

export interface SupabaseUserDataConfig {
  supabaseUrl: string;
  publishableKey: string;
  authorization: string;
  fetchImpl?: typeof fetch;
  maxResponseBytes?: number;
  profile?: "assistant_runtime";
}

export interface SupabaseRuntimeStoreConfig {
  supabaseUrl: string;
  publishableKey: string;
  authorization: string;
  attestationKeyId: string;
  attestationKeyHex: string;
  attestationAudience: string;
  fetchImpl?: typeof fetch;
  maxResponseBytes?: number;
  now?: () => Date;
  randomUuid?: () => string;
}

const runtimeStoreRpcs = new Set([
  "assistant_heartbeat_run_v2",
  "assistant_record_provider_attempt_v2",
  "assistant_record_tool_receipt_v2",
  "assistant_complete_run_v2",
]);

export function createSupabaseRuntimeStoreClient(
  config: SupabaseRuntimeStoreConfig,
): AgentRpcClient {
  const publishableKey = requireValue(config.publishableKey, "Supabase publishable key");
  const authorization = requireBearer(config.authorization);
  const keyId = requireAttestationKeyId(config.attestationKeyId);
  const keyBytes = decodeAttestationKey(config.attestationKeyHex);
  const audience = requireAttestationAudience(config.attestationAudience);
  const now = config.now ?? (() => new Date());
  const randomUuid = config.randomUuid ?? (() => crypto.randomUUID());
  const isolated = createSupabaseUserDataClient({
    supabaseUrl: config.supabaseUrl,
    publishableKey,
    authorization,
    fetchImpl: config.fetchImpl,
    maxResponseBytes: config.maxResponseBytes,
    profile: "assistant_runtime",
  });
  const signingKey = crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return Object.freeze({
    async rpc(name: string, parameters: JsonObject, signal: AbortSignal) {
      if (!runtimeStoreRpcs.has(name)) {
        throw new SupabaseUserDataError("rpc_invalid_response", false, undefined, name);
      }
      const binding = runtimeAttestationBinding(parameters);
      const body = canonicalJson(parameters);
      const bodyBytes = new TextEncoder().encode(body);
      const issuedAt = Math.floor(now().getTime() / 1000);
      if (!Number.isSafeInteger(issuedAt) || issuedAt < 1) {
        throw new Error("AI runtime attestation clock is invalid");
      }
      const nonce = randomUuid().toLowerCase();
      if (!isUuidV4(nonce)) throw new Error("AI runtime attestation nonce is invalid");
      const envelope = [
        "VINABIKE-AI-ATTESTATION-V1",
        `kid=${keyId}`,
        `aud=${audience}`,
        "iss=ai-agent-gateway",
        `op=${name}`,
        `nonce=${nonce}`,
        `iat=${issuedAt}`,
        `exp=${issuedAt + 60}`,
        `sub=${binding.actorUserId}`,
        `tenant=${binding.tenantId}`,
        `authority=${binding.authorityFingerprint}`,
        `run=${binding.runId}`,
        `lease=${binding.leaseToken}`,
        `fence=${binding.fenceToken}`,
        `body-bytes=${bodyBytes.byteLength}`,
      ].join("\n");
      const envelopeBytes = new TextEncoder().encode(envelope);
      const signed = new Uint8Array(envelopeBytes.byteLength + 1 + bodyBytes.byteLength);
      signed.set(envelopeBytes);
      signed[envelopeBytes.byteLength] = 0;
      signed.set(bodyBytes, envelopeBytes.byteLength + 1);
      const mac = new Uint8Array(
        await crypto.subtle.sign("HMAC", await signingKey, signed),
      );
      return isolated.rpc(name, {
        p_envelope: envelope,
        p_body: body,
        p_mac_hex: [...mac].map((byte) => byte.toString(16).padStart(2, "0")).join(""),
      }, signal);
    },
  });
}

/**
 * RFC-8259 JSON subset used by the runtime attestation. Object keys are ASCII
 * and sorted bytewise, arrays retain order, and numbers are safe integers.
 * Optional values must be represented explicitly as null by the caller.
 */
export function canonicalJson(value: unknown): string {
  if (value === null) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) throw new Error("Attested JSON number is invalid");
    return JSON.stringify(value);
  }
  if (typeof value === "string") {
    rejectUnpairedSurrogates(value);
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (!isRecord(value)) throw new Error("Attested JSON value is invalid");
  const keys = Object.keys(value).sort(asciiCompare);
  for (const key of keys) {
    if (!/^[A-Za-z0-9_]+$/.test(key)) throw new Error("Attested JSON key is invalid");
    if (value[key] === undefined) throw new Error("Attested JSON must use explicit null");
  }
  return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
}

function asciiCompare(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function rejectUnpairedSurrogates(value: string): void {
  for (let index = 0; index < value.length; index++) {
    const unit = value.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        throw new Error("Attested JSON string is invalid");
      }
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw new Error("Attested JSON string is invalid");
    }
  }
}

function runtimeAttestationBinding(parameters: JsonObject): {
  actorUserId: string;
  tenantId: string;
  authorityFingerprint: string;
  runId: string;
  leaseToken: string;
  fenceToken: number;
} {
  const actorUserId = parameters.p_actor_user_id;
  const tenantId = parameters.p_tenant_id;
  const authorityFingerprint = parameters.p_authority_fingerprint;
  const runId = parameters.p_run_id;
  const leaseToken = parameters.p_lease_token;
  const fenceToken = parameters.p_fence_token;
  if (
    !isUuid(actorUserId) || !isUuid(tenantId) ||
    typeof authorityFingerprint !== "string" || !/^[0-9a-f]{64}$/.test(authorityFingerprint) ||
    !isUuid(runId) || !isUuid(leaseToken) ||
    typeof fenceToken !== "number" || !Number.isSafeInteger(fenceToken) || fenceToken < 1
  ) {
    throw new Error("AI runtime attestation binding is invalid");
  }
  return { actorUserId, tenantId, authorityFingerprint, runId, leaseToken, fenceToken };
}

function requireAttestationKeyId(value: string): string {
  const resolved = value.trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(resolved)) {
    throw new Error("AI runtime attestation key id is invalid");
  }
  return resolved;
}

function decodeAttestationKey(value: string): Uint8Array<ArrayBuffer> {
  const resolved = value.trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(resolved)) {
    throw new Error("AI runtime attestation key must be 32-byte hex");
  }
  const bytes = new Uint8Array(resolved.length / 2);
  for (let index = 0; index < bytes.length; index++) {
    bytes[index] = Number.parseInt(resolved.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function requireAttestationAudience(value: string): string {
  const resolved = value.trim();
  if (!/^supabase:[a-z0-9][a-z0-9_-]{2,63}:assistant-runtime$/.test(resolved)) {
    throw new Error("AI runtime attestation audience is invalid");
  }
  return resolved;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function isUuidV4(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
    value,
  );
}

export function createSupabaseUserDataClient(config: SupabaseUserDataConfig): AgentRpcClient {
  const baseUrl = requireHttpsOrLocalUrl(config.supabaseUrl);
  const publishableKey = requireValue(config.publishableKey, "Supabase publishable key");
  const authorization = requireBearer(config.authorization);
  const fetchImpl = config.fetchImpl ?? fetch;
  const maxResponseBytes = boundedInteger(
    config.maxResponseBytes,
    DEFAULT_MAX_RESPONSE_BYTES,
    1024,
    1024 * 1024,
  );

  return {
    async rpc(name, parameters, signal) {
      if (!/^[a-z][a-z0-9_]{2,63}$/.test(name)) {
        throw new SupabaseUserDataError("rpc_invalid_response", false, undefined, name);
      }
      if (signal.aborted) throw new SupabaseUserDataError("request_aborted", false, undefined, name);
      let response: Response;
      try {
        const headers = new Headers({
          apikey: publishableKey,
          Authorization: authorization,
          Accept: "application/json",
          "Content-Type": "application/json",
        });
        if (config.profile) {
          headers.set("Accept-Profile", config.profile);
          headers.set("Content-Profile", config.profile);
        }
        response = await fetchImpl(new URL(`/rest/v1/rpc/${name}`, baseUrl), {
          method: "POST",
          headers,
          body: JSON.stringify(parameters),
          signal,
        });
      } catch (_) {
        if (signal.aborted) throw new SupabaseUserDataError("request_aborted", false, undefined, name);
        throw new SupabaseUserDataError("rpc_unavailable", true, undefined, name);
      }
      if (!response.ok) {
        throw await sanitizedRpcFailure(response, signal, name);
      }
      return await readBoundedJson(response, maxResponseBytes, signal);
    },
  };
}

async function sanitizedRpcFailure(
  response: Response,
  signal: AbortSignal,
  name?: string,
): Promise<SupabaseUserDataError> {
  try {
    const value = await readBoundedJson(response, MAX_ERROR_RESPONSE_BYTES, signal);
    if (isRecord(value) && typeof value.code === "string") {
      if (value.code === "22023") {
        return new SupabaseUserDataError("rpc_invalid_response", false, "idempotency_conflict", name);
      }
      if (value.code === "42501") {
        return new SupabaseUserDataError("rpc_invalid_response", false, "forbidden", name);
      }
      if (value.code === "P0001") {
        return new SupabaseUserDataError("rpc_unavailable", false, "quota_exceeded", name);
      }
    }
  } catch (error) {
    if (error instanceof SupabaseUserDataError && error.outcome === "request_aborted") {
      return error;
    }
  }
  return new SupabaseUserDataError(
    "rpc_unavailable",
    response.status === 408 || response.status === 429 || response.status >= 500,
  );
}

async function readBoundedJson(
  response: Response,
  maxBytes: number,
  signal: AbortSignal,
): Promise<unknown> {
  const length = Number(response.headers.get("content-length"));
  if (Number.isFinite(length) && length > maxBytes) {
    await discardBody(response);
    throw new SupabaseUserDataError("rpc_invalid_response", false, undefined, name);
  }
  const reader = response.body?.getReader();
  if (!reader) throw new SupabaseUserDataError("rpc_invalid_response", false, undefined, name);
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      if (signal.aborted) throw new SupabaseUserDataError("request_aborted", false, undefined, name);
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel("response_too_large");
        throw new SupabaseUserDataError("rpc_invalid_response", false, undefined, name);
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof SupabaseUserDataError) throw error;
    throw new SupabaseUserDataError("rpc_invalid_response", false, undefined, name);
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch (_) {
    throw new SupabaseUserDataError("rpc_invalid_response", false, undefined, name);
  }
}

async function discardBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch (_) {
    // Upstream bodies are intentionally discarded and never logged.
  }
}

function requireHttpsOrLocalUrl(value: string): URL {
  const url = new URL(value);
  const local = ["localhost", "127.0.0.1", "::1"].includes(url.hostname);
  if (url.protocol !== "https:" && !(local && url.protocol === "http:")) {
    throw new Error("Supabase URL must use HTTPS");
  }
  return url;
}

function requireValue(value: string, label: string): string {
  if (!value.trim()) throw new Error(`${label} is not configured`);
  return value;
}

function requireBearer(value: string): string {
  if (!/^Bearer\s+\S+$/i.test(value) || value.length > 8_200) {
    throw new Error("Caller authorization is invalid");
  }
  return value;
}

function boundedInteger(
  value: number | undefined,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const resolved = value ?? fallback;
  if (!Number.isSafeInteger(resolved) || resolved < minimum || resolved > maximum) {
    throw new Error("Supabase response limit is invalid");
  }
  return resolved;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
