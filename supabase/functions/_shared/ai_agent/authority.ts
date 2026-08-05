import type { AgentAuthority } from "./contracts.ts";

const canonicalStoredRoles = new Set([
  "admin",
  "manager",
  "cashier",
  "accountant",
  "mechanic",
]);

export interface AuthenticatedAgentUser {
  id: string;
  email?: string | null;
  appMetadata?: Readonly<Record<string, unknown>>;
}

export interface AgentMembershipRecord {
  tenantId: string;
  role: unknown;
  permissions: unknown;
  profileActive: boolean;
  tenantActive: boolean;
  tenantOwnerEmail?: string | null;
}

export interface AgentAuthorityDataSource {
  authenticate(accessToken: string, signal?: AbortSignal): Promise<AuthenticatedAgentUser | null>;
  activeMemberships(
    userId: string,
    signal?: AbortSignal,
  ): Promise<readonly AgentMembershipRecord[]>;
}

export interface SupabaseAuthorityConfig {
  supabaseUrl: string;
  anonKey: string;
  serviceRoleKey: string;
  fetchImpl?: typeof fetch;
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

  let user: AuthenticatedAgentUser | null;
  try {
    user = await source.authenticate(match[1], signal);
  } catch (_) {
    throw new AuthorityError(
      503,
      "authorization_unavailable",
      "Unable to verify account access",
    );
  }
  if (!user || !validUuid(user.id)) {
    throw new AuthorityError(401, "invalid_session", "Authentication required");
  }

  let memberships: readonly AgentMembershipRecord[];
  try {
    memberships = await source.activeMemberships(user.id, signal);
  } catch (_) {
    throw new AuthorityError(
      503,
      "authorization_unavailable",
      "Unable to verify account access",
    );
  }

  const active = memberships.filter((membership) =>
    membership.profileActive && membership.tenantActive
  );
  if (active.length !== 1) {
    throw new AuthorityError(
      403,
      "tenant_context_invalid",
      "A single active tenant is required",
    );
  }

  const membership = active[0];
  if (!validUuid(membership.tenantId) || !canonicalStoredRoles.has(membership.role as string)) {
    throw new AuthorityError(403, "tenant_context_invalid", "Account access is invalid");
  }

  const role = isPrincipalOwner(user, membership) ? "owner" : membership.role as string;
  return {
    userId: user.id,
    tenantId: membership.tenantId,
    role,
    permissions: normalizeStoredPermissions(membership.permissions),
  };
}

export function createSupabaseAuthorityDataSource(
  config: SupabaseAuthorityConfig,
): AgentAuthorityDataSource {
  const baseUrl = requireHttpsOrLocalUrl(config.supabaseUrl);
  const fetchImpl = config.fetchImpl ?? fetch;
  const anonKey = requireSecret(config.anonKey, "Supabase anon key");
  const serviceRoleKey = requireSecret(config.serviceRoleKey, "Supabase service role key");

  return {
    async authenticate(accessToken, signal) {
      const response = await fetchImpl(new URL("/auth/v1/user", baseUrl), {
        method: "GET",
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${accessToken}`,
        },
        signal,
      });
      if (response.status === 401 || response.status === 403) return null;
      if (!response.ok) throw new Error("auth lookup failed");
      const body = await safeJson(response);
      const id = recordString(body, "id");
      if (!id) return null;
      const record = body as Record<string, unknown>;
      const appMetadata = record.app_metadata && typeof record.app_metadata === "object" &&
          !Array.isArray(record.app_metadata)
        ? record.app_metadata as Record<string, unknown>
        : {};
      return {
        id,
        email: typeof record.email === "string" ? record.email : null,
        appMetadata,
      };
    },

    async activeMemberships(userId, signal) {
      const url = new URL("/rest/v1/user_profiles", baseUrl);
      url.searchParams.set(
        "select",
        "tenant_id,role,permissions,is_active,tenants!inner(id,is_active,owner_email)",
      );
      url.searchParams.set("user_id", `eq.${userId}`);
      url.searchParams.set("is_active", "eq.true");
      url.searchParams.set("tenants.is_active", "eq.true");
      url.searchParams.set("limit", "2");
      const response = await fetchImpl(url, {
        method: "GET",
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
          Accept: "application/json",
        },
        signal,
      });
      if (!response.ok) throw new Error("membership lookup failed");
      const body = await safeJson(response);
      if (!Array.isArray(body)) throw new Error("invalid membership response");
      return body.map(parseMembershipRecord);
    },
  };
}

function parseMembershipRecord(value: unknown): AgentMembershipRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalidMembership();
  }
  const record = value as Record<string, unknown>;
  const tenantValue = Array.isArray(record.tenants) ? record.tenants[0] : record.tenants;
  const tenant = tenantValue && typeof tenantValue === "object" && !Array.isArray(tenantValue)
    ? tenantValue as Record<string, unknown>
    : {};
  return {
    tenantId: typeof record.tenant_id === "string" ? record.tenant_id : "",
    role: record.role,
    permissions: record.permissions,
    profileActive: record.is_active === true,
    tenantActive: tenant.is_active === true && tenant.id === record.tenant_id,
    tenantOwnerEmail: typeof tenant.owner_email === "string" ? tenant.owner_email : null,
  };
}

function invalidMembership(): AgentMembershipRecord {
  return {
    tenantId: "",
    role: null,
    permissions: null,
    profileActive: false,
    tenantActive: false,
    tenantOwnerEmail: null,
  };
}

function normalizeStoredPermissions(value: unknown): Readonly<Record<string, boolean>> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return Object.freeze({});
  const entries = Object.entries(value as Record<string, unknown>)
    .filter((entry): entry is [string, boolean] =>
      /^[a-z][a-z0-9_.]{0,63}$/.test(entry[0]) && typeof entry[1] === "boolean"
    );
  return Object.freeze(Object.fromEntries(entries));
}

function validUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function isPrincipalOwner(
  user: AuthenticatedAgentUser,
  membership: AgentMembershipRecord,
): boolean {
  const authEmail = normalizeEmail(user.email);
  const ownerEmail = normalizeEmail(membership.tenantOwnerEmail);
  const metadata = user.appMetadata ?? {};
  return Boolean(authEmail && ownerEmail && authEmail === ownerEmail) ||
    (metadata.account_type === "erp_owner" && metadata.tenant_id === membership.tenantId);
}

function normalizeEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalized) ? normalized : null;
}

function requireHttpsOrLocalUrl(value: string): URL {
  const url = new URL(value);
  const local = ["localhost", "127.0.0.1", "::1"].includes(url.hostname);
  if (url.protocol !== "https:" && !(local && url.protocol === "http:")) {
    throw new Error("Supabase URL must use HTTPS");
  }
  return url;
}

function requireSecret(value: string, label: string): string {
  if (!value.trim()) throw new Error(`${label} is not configured`);
  return value;
}

async function safeJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch (_) {
    throw new Error("invalid upstream response");
  }
}

function recordString(value: unknown, key: string): string | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const field = (value as Record<string, unknown>)[key];
  return typeof field === "string" && field ? field : null;
}
