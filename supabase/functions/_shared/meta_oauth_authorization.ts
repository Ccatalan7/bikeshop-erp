export interface MetaOAuthAuthorizationUrlOptions {
  graphVersion: string;
  appId: string;
  redirectUri: string;
  state: string;
  loginConfigId: string;
}

export interface MetaSystemUserTokenExchangeUrlOptions {
  graphVersion: string;
  appId: string;
  appSecret: string;
  redirectUri: string;
  code: string;
}

export interface MetaSystemUserBusinessIdentity {
  id: string;
  clientBusinessId: string;
}

export interface MetaGranularScope {
  scope: string;
  targetIds: readonly string[];
}

export interface MetaDebugTokenEvidence {
  grantedScopes: readonly string[];
  granularScopes: readonly MetaGranularScope[] | null;
  tokenExpiresAt: string | null;
  hasExpiresAtEvidence: boolean;
  expiresAt: string | null;
  dataAccessExpiresAt: string | null;
  profileId: string | null;
  subjectId: string | null;
}

export interface MetaDebugTokenEvidenceOptions {
  expectedAppId: string;
  nowMilliseconds: number;
}

const META_IDENTIFIER_PATTERN = /^[0-9]{1,32}$/;
const META_SCOPE_PATTERN = /^[a-z][a-z0-9_]{0,127}$/;
const TOKEN_EXPIRY_CONFLICT_TOLERANCE_MILLISECONDS = 5 * 60 * 1_000;
const REQUIRED_META_PAGE_TASKS = ["MESSAGING", "MODERATE"] as const;

export function parseMetaLoginConfigId(value: string | undefined): string | null {
  if (!value || !META_IDENTIFIER_PATTERN.test(value)) return null;
  return value;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function unixSecondsExpiresAt(
  value: unknown,
  nowMilliseconds: number,
): string | null {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    throw new Error("invalid_system_user_token_expiry");
  }
  if (value === 0) return null;
  const expiresAtMilliseconds = (value as number) * 1_000;
  if (
    !Number.isSafeInteger(expiresAtMilliseconds) ||
    expiresAtMilliseconds <= nowMilliseconds
  ) {
    throw new Error("invalid_system_user_token_expiry");
  }
  const expiresAt = new Date(expiresAtMilliseconds);
  if (Number.isNaN(expiresAt.getTime())) {
    throw new Error("invalid_system_user_token_expiry");
  }
  return expiresAt.toISOString();
}

function relativeSecondsExpiresAt(
  tokenPayload: unknown,
  tokenReceivedAtMilliseconds: number,
): string | null {
  const payload = asRecord(tokenPayload);
  if (!payload) {
    throw new Error("invalid_system_user_token_payload");
  }
  if (!("expires_in" in payload)) {
    throw new Error("missing_system_user_token_expiry");
  }
  if (payload.expires_in === 0) return null;
  if (
    !Number.isSafeInteger(payload.expires_in) ||
    (payload.expires_in as number) < 1 ||
    !Number.isSafeInteger(tokenReceivedAtMilliseconds) ||
    tokenReceivedAtMilliseconds < 0
  ) {
    throw new Error("invalid_system_user_token_expiry");
  }
  const expiresAtMilliseconds = tokenReceivedAtMilliseconds +
    (payload.expires_in as number) * 1_000;
  if (!Number.isSafeInteger(expiresAtMilliseconds)) {
    throw new Error("invalid_system_user_token_expiry");
  }
  const expiresAt = new Date(expiresAtMilliseconds);
  if (Number.isNaN(expiresAt.getTime())) {
    throw new Error("invalid_system_user_token_expiry");
  }
  return expiresAt.toISOString();
}

function parseScope(value: unknown): string {
  if (typeof value !== "string" || !META_SCOPE_PATTERN.test(value)) {
    throw new Error("invalid_system_user_token_scopes");
  }
  return value;
}

function optionalMetaIdentifier(
  record: Record<string, unknown>,
  key: string,
): string | null {
  if (!(key in record)) return null;
  const value = record[key];
  if (typeof value !== "string" || !META_IDENTIFIER_PATTERN.test(value)) {
    throw new Error("invalid_debug_token_metadata");
  }
  return value;
}

function earliestExpiry(
  ...values: readonly (string | null)[]
): string | null {
  const timestamps = values
    .filter((value): value is string => value !== null)
    .map((value) => Date.parse(value));
  return timestamps.length === 0 ? null : new Date(Math.min(...timestamps)).toISOString();
}

export function earliestMetaTokenExpiresAt(
  ...values: readonly (string | null)[]
): string | null {
  for (const value of values) {
    if (value !== null && !Number.isFinite(Date.parse(value))) {
      throw new Error("invalid_meta_token_expiry");
    }
  }
  return earliestExpiry(...values);
}

export function missingRequiredMetaPageTasks(value: unknown): string[] {
  const tasks = new Set(
    (Array.isArray(value) ? value : [])
      .filter((task): task is string => typeof task === "string")
      .map((task) => task.toUpperCase()),
  );
  return REQUIRED_META_PAGE_TASKS.filter((task) => !tasks.has(task));
}

export function parseMetaSystemUserBusinessIdentity(
  payload: unknown,
  debugSubjectId: string | null,
): MetaSystemUserBusinessIdentity {
  const record = asRecord(payload);
  if (!record) throw new Error("system_user_business_identity_missing");
  const id = optionalMetaIdentifier(record, "id");
  const clientBusinessId = optionalMetaIdentifier(record, "client_business_id");
  if (!id || !clientBusinessId) {
    throw new Error("system_user_business_identity_missing");
  }
  if (debugSubjectId !== null && debugSubjectId !== id) {
    throw new Error("system_user_identity_mismatch");
  }
  return { id, clientBusinessId };
}

export function parseMetaDebugTokenEvidence(
  payload: unknown,
  options: MetaDebugTokenEvidenceOptions,
): MetaDebugTokenEvidence {
  const root = asRecord(payload);
  const data = asRecord(root?.data);
  if (!data || data.is_valid !== true) {
    throw new Error("invalid_system_user_token");
  }
  if (data.app_id !== options.expectedAppId) {
    throw new Error("debug_token_app_mismatch");
  }
  if (
    !Number.isSafeInteger(options.nowMilliseconds) ||
    options.nowMilliseconds < 0
  ) {
    throw new Error("invalid_system_user_token_expiry");
  }

  const hasExpiresAtEvidence = "expires_at" in data;
  const expiresAt = hasExpiresAtEvidence
    ? unixSecondsExpiresAt(
      data.expires_at,
      options.nowMilliseconds,
    )
    : null;
  const dataAccessExpiresAt = "data_access_expires_at" in data
    ? unixSecondsExpiresAt(
      data.data_access_expires_at,
      options.nowMilliseconds,
    )
    : null;
  const tokenExpiresAt = earliestExpiry(expiresAt, dataAccessExpiresAt);

  if ("scopes" in data && !Array.isArray(data.scopes)) {
    throw new Error("invalid_system_user_token_scopes");
  }
  const grantedScopes = new Set<string>();
  for (const scope of Array.isArray(data.scopes) ? data.scopes : []) {
    grantedScopes.add(parseScope(scope));
  }

  let granularScopes: MetaGranularScope[] | null = null;
  if ("granular_scopes" in data) {
    if (!Array.isArray(data.granular_scopes)) {
      throw new Error("invalid_system_user_token_scopes");
    }
    granularScopes = [];
    for (const rawGranularScope of data.granular_scopes) {
      const granularScope = asRecord(rawGranularScope);
      if (!granularScope) throw new Error("invalid_system_user_token_scopes");
      const scope = parseScope(granularScope.scope);
      grantedScopes.add(scope);
      const targetIds: string[] = [];
      if ("target_ids" in granularScope) {
        if (!Array.isArray(granularScope.target_ids)) {
          throw new Error("invalid_system_user_token_scopes");
        }
        for (const rawTargetId of granularScope.target_ids) {
          if (
            typeof rawTargetId !== "string" ||
            !META_IDENTIFIER_PATTERN.test(rawTargetId)
          ) {
            throw new Error("invalid_system_user_token_scopes");
          }
          if (!targetIds.includes(rawTargetId)) targetIds.push(rawTargetId);
        }
      }
      granularScopes.push({ scope, targetIds });
    }
  }

  return {
    grantedScopes: [...grantedScopes].sort(),
    granularScopes,
    tokenExpiresAt,
    hasExpiresAtEvidence,
    expiresAt,
    dataAccessExpiresAt,
    profileId: optionalMetaIdentifier(data, "profile_id"),
    subjectId: optionalMetaIdentifier(data, "user_id"),
  };
}

export function resolveMetaSystemUserTokenExpiresAt(
  debugEvidence: MetaDebugTokenEvidence,
  exchangedTokenPayload: unknown,
  tokenReceivedAtMilliseconds: number,
): string | null {
  const exchangedToken = asRecord(exchangedTokenPayload);
  if (!exchangedToken) {
    throw new Error("invalid_system_user_token_payload");
  }
  if (!debugEvidence.hasExpiresAtEvidence) {
    const relativeExpiry = relativeSecondsExpiresAt(
      exchangedToken,
      tokenReceivedAtMilliseconds,
    );
    return earliestExpiry(relativeExpiry, debugEvidence.dataAccessExpiresAt);
  }
  if (!("expires_in" in exchangedToken)) return debugEvidence.tokenExpiresAt;

  const relativeExpiry = relativeSecondsExpiresAt(
    exchangedToken,
    tokenReceivedAtMilliseconds,
  );
  if (debugEvidence.expiresAt === null || relativeExpiry === null) {
    if (debugEvidence.expiresAt !== relativeExpiry) {
      throw new Error("conflicting_system_user_token_expiry");
    }
  } else {
    const difference = Math.abs(
      Date.parse(debugEvidence.expiresAt) - Date.parse(relativeExpiry),
    );
    if (difference > TOKEN_EXPIRY_CONFLICT_TOLERANCE_MILLISECONDS) {
      throw new Error("conflicting_system_user_token_expiry");
    }
  }
  return debugEvidence.tokenExpiresAt;
}

export function buildMetaOAuthAuthorizationUrl(
  options: MetaOAuthAuthorizationUrlOptions,
): URL {
  const loginConfigId = parseMetaLoginConfigId(options.loginConfigId);
  if (!loginConfigId) throw new Error("invalid_meta_login_config_id");

  const authorizeUrl = new URL(
    `https://www.facebook.com/${options.graphVersion}/dialog/oauth`,
  );
  authorizeUrl.searchParams.set("client_id", options.appId);
  authorizeUrl.searchParams.set("redirect_uri", options.redirectUri);
  authorizeUrl.searchParams.set("state", options.state);
  authorizeUrl.searchParams.set("response_type", "code");
  authorizeUrl.searchParams.set("config_id", loginConfigId);
  authorizeUrl.searchParams.set("override_default_response_type", "true");
  return authorizeUrl;
}

export function buildMetaSystemUserTokenExchangeUrl(
  options: MetaSystemUserTokenExchangeUrlOptions,
): URL {
  const tokenUrl = new URL(
    `https://graph.facebook.com/${options.graphVersion}/oauth/access_token`,
  );
  tokenUrl.searchParams.set("client_id", options.appId);
  tokenUrl.searchParams.set("client_secret", options.appSecret);
  tokenUrl.searchParams.set("redirect_uri", options.redirectUri);
  tokenUrl.searchParams.set("code", options.code);
  return tokenUrl;
}

export function buildMetaDebugTokenUrl(
  graphVersion: string,
  inputToken: string,
): URL {
  const debugUrl = new URL(
    `https://graph.facebook.com/${graphVersion}/debug_token`,
  );
  debugUrl.searchParams.set("input_token", inputToken);
  return debugUrl;
}
