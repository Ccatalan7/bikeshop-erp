import {
  type AgentAuthority,
  agentCapabilities,
  type AgentCapability,
  type JsonObject,
} from "./contracts.ts";
import type { AgentRpcClient } from "./supabase_user_data.ts";

const canonicalRoles = new Set([
  "owner",
  "admin",
  "manager",
  "cashier",
  "accountant",
  "mechanic",
]);

export interface AgentAuthorityDataSource {
  resolve(signal?: AbortSignal): Promise<AgentAuthority>;
}

export class AuthorityError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly publicMessage: string,
  ) {
    super(publicMessage);
    this.name = "AuthorityError";
  }
}

export async function resolveAgentAuthority(
  request: Request,
  source: AgentAuthorityDataSource,
  signal?: AbortSignal,
): Promise<AgentAuthority> {
  const authorization = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!match || match[1].length > 8_192) {
    throw new AuthorityError(401, "invalid_session", "Authentication required");
  }
  try {
    const authority = await source.resolve(signal);
    validateAuthority(authority);
    return authority;
  } catch (error) {
    if (error instanceof AuthorityError) throw error;
    throw new AuthorityError(
      503,
      "authorization_unavailable",
      "Unable to verify account access",
    );
  }
}

export function createSupabaseAuthorityDataSource(
  client: AgentRpcClient,
): AgentAuthorityDataSource {
  return {
    async resolve(signal = new AbortController().signal) {
      const value = await client.rpc("assistant_get_authority_v1", {}, signal);
      if (!isRecord(value)) return invalidAuthority();
      const userId = recordString(value, "actorUserId");
      const tenantId = recordString(value, "authorityTenantId");
      const role = recordString(value, "role");
      const authorityFingerprint = recordString(value, "authorityFingerprint");
      const capabilities = normalizeCapabilities(value.capabilities);
      if (!userId || !tenantId || !role || !authorityFingerprint || !capabilities) {
        return invalidAuthority();
      }
      return {
        userId,
        tenantId,
        role,
        permissions: normalizeStoredPermissions(value.permissions),
        capabilities,
        authorityFingerprint,
      };
    },
  };
}

function validateAuthority(authority: AgentAuthority): void {
  if (
    !validUuid(authority.userId) || !validUuid(authority.tenantId) ||
    !canonicalRoles.has(authority.role) ||
    !/^[A-Za-z0-9._:-]{32,256}$/.test(authority.authorityFingerprint) ||
    !Array.isArray(authority.capabilities) ||
    authority.capabilities.some((capability) =>
      !(agentCapabilities as readonly string[]).includes(capability)
    ) || new Set(authority.capabilities).size !== authority.capabilities.length
  ) {
    throw new AuthorityError(403, "tenant_context_invalid", "Account access is invalid");
  }
  if (!isRecord(authority.permissions)) {
    throw new AuthorityError(403, "tenant_context_invalid", "Account access is invalid");
  }
}

function normalizeCapabilities(value: unknown): readonly AgentCapability[] | null {
  if (
    !Array.isArray(value) || value.length > agentCapabilities.length ||
    value.some((item) =>
      typeof item !== "string" || !(agentCapabilities as readonly string[]).includes(item)
    ) || new Set(value).size !== value.length
  ) return null;
  return Object.freeze([...value]) as readonly AgentCapability[];
}

function invalidAuthority(): never {
  throw new AuthorityError(403, "tenant_context_invalid", "Account access is invalid");
}

function normalizeStoredPermissions(value: unknown): Readonly<Record<string, boolean>> {
  if (!isRecord(value)) return Object.freeze({});
  const entries = Object.entries(value)
    .filter((entry): entry is [string, boolean] =>
      /^[a-z][a-z0-9_.]{0,63}$/.test(entry[0]) && typeof entry[1] === "boolean"
    );
  return Object.freeze(Object.fromEntries(entries));
}

function validUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function isRecord(value: unknown): value is JsonObject {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function recordString(value: Readonly<Record<string, unknown>>, key: string): string | null {
  const field = value[key];
  return typeof field === "string" && field ? field : null;
}
