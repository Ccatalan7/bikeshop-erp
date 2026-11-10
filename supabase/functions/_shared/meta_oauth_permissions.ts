export type MetaOAuthChannelProvider = "facebook_messenger" | "instagram";

export const REQUESTED_META_OAUTH_SCOPES = [
  "business_management",
  "pages_show_list",
  "pages_messaging",
  "pages_manage_metadata",
  "pages_read_engagement",
  "pages_read_user_content",
  "instagram_basic",
  "instagram_manage_messages",
  "instagram_manage_comments",
] as const;

// What the Business Login system-user token must carry before the callback
// stores anything. business_management stays requested but is not required:
// no ERP call uses it, and since the app went live Meta stops granting it to
// the Business Integration system user while the permission has Standard Access
// (read back 2026-11-09: the token carried the other eight and the reauthorization
// failed on this one alone).
export const REQUIRED_SYSTEM_USER_SCOPES = REQUESTED_META_OAUTH_SCOPES.filter(
  (scope) => scope !== "business_management",
);

const REQUIRED_SCOPES: Record<
  MetaOAuthChannelProvider,
  readonly string[]
> = {
  facebook_messenger: [
    "business_management",
    "pages_show_list",
    "pages_messaging",
    "pages_manage_metadata",
    "pages_read_engagement",
    "pages_read_user_content",
  ],
  instagram: [
    "business_management",
    "pages_show_list",
    "pages_messaging",
    "pages_manage_metadata",
    "pages_read_engagement",
    "instagram_basic",
    "instagram_manage_messages",
    "instagram_manage_comments",
  ],
};

const REQUIRED_PAGE_TOKEN_SCOPES: Record<
  MetaOAuthChannelProvider,
  readonly string[]
> = {
  facebook_messenger: [
    "pages_show_list",
    "pages_messaging",
    "pages_manage_metadata",
    "pages_read_engagement",
    "pages_read_user_content",
  ],
  instagram: [
    "pages_show_list",
    "pages_messaging",
    "pages_manage_metadata",
    "pages_read_engagement",
    "instagram_basic",
    "instagram_manage_messages",
    "instagram_manage_comments",
  ],
};

type JsonRecord = Record<string, unknown>;

function asRecord(value: unknown): JsonRecord | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : null;
}

export function parseGrantedMetaScopes(payload: unknown): string[] {
  const root = asRecord(payload);
  const rows = Array.isArray(root?.data) ? root.data : [];
  const result = new Set<string>();
  for (const rawRow of rows) {
    const row = asRecord(rawRow);
    const permission = typeof row?.permission === "string"
      ? row.permission.trim().toLowerCase()
      : "";
    const status = typeof row?.status === "string" ? row.status.trim().toLowerCase() : "";
    if (
      status === "granted" &&
      /^[a-z][a-z0-9_]{0,127}$/.test(permission)
    ) {
      result.add(permission);
    }
  }
  return [...result].sort();
}

export function requiredMetaScopes(
  provider: MetaOAuthChannelProvider,
): readonly string[] {
  return REQUIRED_SCOPES[provider];
}

export function missingRequestedMetaOAuthScopes(
  grantedScopes: readonly string[],
): string[] {
  const granted = new Set(grantedScopes);
  return REQUESTED_META_OAUTH_SCOPES.filter((scope) => !granted.has(scope));
}

export function missingRequiredSystemUserScopes(
  grantedScopes: readonly string[],
): string[] {
  const granted = new Set(grantedScopes);
  return REQUIRED_SYSTEM_USER_SCOPES.filter((scope) => !granted.has(scope));
}

export function missingRequiredMetaScopes(
  provider: MetaOAuthChannelProvider,
  grantedScopes: readonly string[],
): string[] {
  const granted = new Set(grantedScopes);
  return REQUIRED_SCOPES[provider].filter((scope) => !granted.has(scope));
}

export function missingRequiredMetaPageTokenScopes(
  provider: MetaOAuthChannelProvider,
  grantedScopes: readonly string[],
): string[] {
  const granted = new Set(grantedScopes);
  return REQUIRED_PAGE_TOKEN_SCOPES[provider].filter((scope) => !granted.has(scope));
}
