export type MailProviderId = "gmail" | "zoho";

const minimumCooldownMs = 60 * 1000;
const defaultCooldownMs = 5 * 60 * 1000;
const maximumCooldownMs = 60 * 60 * 1000;
const providerRetrySafetyMarginMs = 60 * 1000;

/**
 * Normalizes provider-specific Retry-After shapes into one bounded timestamp.
 * Gmail currently embeds an ISO timestamp in its JSON error message, while
 * Zoho may return a Retry-After header or no duration at all. The fallback is
 * deliberately durable so several installed clients cannot keep extending a
 * provider lock by polling independently.
 */
export function mailProviderRateLimitRetryAt(
  payload: unknown,
  options: {
    retryAfterHeader?: string | null;
    nowMs?: number;
    fallbackMs?: number;
  } = {},
): string {
  const nowMs = options.nowMs ?? Date.now();
  const headerMs = parseRetryAfterHeader(options.retryAfterHeader, nowMs);
  const payloadMs = parseRetryAfterPayload(payload, nowMs);
  const fallbackMs = nowMs + Math.max(
    options.fallbackMs ?? defaultCooldownMs,
    minimumCooldownMs,
  );
  const requestedMs = headerMs ?? payloadMs ?? fallbackMs;
  return new Date(
    Math.min(
      Math.max(requestedMs, nowMs + minimumCooldownMs),
      nowMs + maximumCooldownMs,
    ),
  ).toISOString();
}

export function mailProviderRateLimitMetadataKey(
  provider: MailProviderId,
): string {
  return `${provider}_rate_limit_until`;
}

function mailProviderRateLimitAttemptsKey(
  provider: MailProviderId,
): string {
  return `${provider}_rate_limit_attempts`;
}

export function advanceMailProviderRateLimit(
  metadata: unknown,
  provider: MailProviderId,
  providerRetryAt: string,
  nowMs = Date.now(),
): {
  metadata: Record<string, unknown>;
  retryAt: string;
  attempts: number;
} {
  const record = recordValue(metadata);
  const untilKey = mailProviderRateLimitMetadataKey(provider);
  const attemptsKey = mailProviderRateLimitAttemptsKey(provider);
  const storedAttempts = Number(record[attemptsKey]);
  const previousAttempts = Number.isInteger(storedAttempts) &&
      storedAttempts > 0
    ? Math.min(storedAttempts, 16)
    // A boundary written by the pre-escalation implementation is still one
    // failed provider attempt and must not restart the backoff at one.
    : cleanText(record[untilKey])
    ? 1
    : 0;
  const attempts = Math.min(previousAttempts + 1, 16);
  const providerTimestamp = Date.parse(providerRetryAt);
  const providerDelayMs = Number.isFinite(providerTimestamp)
    ? Math.max(providerTimestamp - nowMs, minimumCooldownMs)
    : defaultCooldownMs;
  const multiplier = 2 ** Math.min(attempts - 1, 6);
  const delayMs = Math.min(providerDelayMs * multiplier, maximumCooldownMs);
  const retryAt = new Date(nowMs + delayMs).toISOString();

  return {
    metadata: {
      ...record,
      [untilKey]: retryAt,
      [attemptsKey]: attempts,
    },
    retryAt,
    attempts,
  };
}

export function activeMailProviderRateLimitUntil(
  metadata: unknown,
  provider: MailProviderId,
  nowMs = Date.now(),
): string | null {
  const record = recordValue(metadata);
  const value = cleanText(record[mailProviderRateLimitMetadataKey(provider)]);
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return null;

  // Retry-After is a lower bound, not proof that a rolling quota window has
  // already drained. Waiting one minute past the provider timestamp also
  // absorbs clock skew between Google/Zoho, Supabase and installed clients.
  // Keep the raw provider boundary in metadata so the margin is applied once,
  // including to cooldowns written by an older function deployment.
  const effectiveTimestamp = timestamp + providerRetrySafetyMarginMs;
  return effectiveTimestamp > nowMs ? new Date(effectiveTimestamp).toISOString() : null;
}

export function withMailProviderRateLimit(
  metadata: unknown,
  provider: MailProviderId,
  retryAt: string,
): Record<string, unknown> {
  return {
    ...recordValue(metadata),
    [mailProviderRateLimitMetadataKey(provider)]: retryAt,
  };
}

export function withoutMailProviderRateLimit(
  metadata: unknown,
  provider: MailProviderId,
): { metadata: Record<string, unknown>; changed: boolean } {
  const next = recordValue(metadata);
  const key = mailProviderRateLimitMetadataKey(provider);
  const attemptsKey = mailProviderRateLimitAttemptsKey(provider);
  const changed = key in next || attemptsKey in next;
  if (!changed) return { metadata: next, changed: false };
  delete next[key];
  delete next[attemptsKey];
  return { metadata: next, changed: true };
}

function parseRetryAfterHeader(
  value: string | null | undefined,
  nowMs: number,
): number | null {
  const normalized = cleanText(value);
  if (!normalized) return null;
  const seconds = Number(normalized);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return nowMs + seconds * 1000;
  }
  const timestamp = Date.parse(normalized);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function parseRetryAfterPayload(payload: unknown, nowMs: number): number | null {
  const serialized = safeSerialize(payload);
  const isoMatch = /retry(?:[_ -]?after)?[\s:'"=]+(\d{4}-\d{2}-\d{2}T[0-9:.+-]+Z?)/i
    .exec(serialized);
  if (isoMatch != null) {
    const timestamp = Date.parse(isoMatch[1]);
    if (Number.isFinite(timestamp)) return timestamp;
  }

  const durationMatch = /retry(?:[_ -]?after)?[\s:'"=]+(\d+)\s*(seconds?|secs?|minutes?|mins?)/i
    .exec(serialized);
  if (durationMatch == null) return null;
  const amount = Number(durationMatch[1]);
  if (!Number.isFinite(amount)) return null;
  const multiplier = durationMatch[2].toLowerCase().startsWith("m") ? 60 * 1000 : 1000;
  return nowMs + amount * multiplier;
}

function safeSerialize(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch (_) {
    return String(value ?? "");
  }
}

function recordValue(value: unknown): Record<string, unknown> {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return { ...(value as Record<string, unknown>) };
}

function cleanText(value: unknown): string {
  return String(value ?? "").trim();
}
