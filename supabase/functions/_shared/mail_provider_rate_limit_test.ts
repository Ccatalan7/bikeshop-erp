import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  activeMailProviderRateLimitUntil,
  advanceMailProviderRateLimit,
  mailProviderRateLimitRetryAt,
  withMailProviderRateLimit,
  withoutMailProviderRateLimit,
} from "./mail_provider_rate_limit.ts";

const now = Date.parse("2026-08-15T19:00:00.000Z");

Deno.test("provider cooldown accepts Gmail ISO payload and Zoho Retry-After header", () => {
  assertEquals(
    mailProviderRateLimitRetryAt({
      error: {
        message: "User-rate limit exceeded. Retry after 2026-08-15T19:15:00.000Z",
      },
    }, { nowMs: now }),
    "2026-08-15T19:15:00.000Z",
  );
  assertEquals(
    mailProviderRateLimitRetryAt({}, {
      nowMs: now,
      retryAfterHeader: "120",
    }),
    "2026-08-15T19:02:00.000Z",
  );
});

Deno.test("provider cooldown has a bounded fallback when duration is undisclosed", () => {
  assertEquals(
    mailProviderRateLimitRetryAt({ error: "API rate limit exceeded" }, {
      nowMs: now,
    }),
    "2026-08-15T19:05:00.000Z",
  );
  assertEquals(
    mailProviderRateLimitRetryAt({}, {
      nowMs: now,
      retryAfterHeader: "7200",
    }),
    "2026-08-15T20:00:00.000Z",
  );
});

Deno.test("provider cooldown metadata is isolated by provider and removable", () => {
  const gmailUntil = "2026-08-15T19:15:00.000Z";
  const zohoUntil = "2026-08-15T19:20:00.000Z";
  const withBoth = withMailProviderRateLimit(
    withMailProviderRateLimit({ accountId: "a-1" }, "gmail", gmailUntil),
    "zoho",
    zohoUntil,
  );

  assertEquals(
    activeMailProviderRateLimitUntil(withBoth, "gmail", now),
    "2026-08-15T19:16:00.000Z",
  );
  assertEquals(
    activeMailProviderRateLimitUntil(withBoth, "zoho", now),
    "2026-08-15T19:21:00.000Z",
  );

  assertEquals(
    activeMailProviderRateLimitUntil(
      withBoth,
      "gmail",
      Date.parse("2026-08-15T19:15:30.000Z"),
    ),
    "2026-08-15T19:16:00.000Z",
    "the durable circuit stays closed past the provider's lower bound",
  );
  assertEquals(
    activeMailProviderRateLimitUntil(
      withBoth,
      "gmail",
      Date.parse("2026-08-15T19:16:00.000Z"),
    ),
    null,
  );

  const removed = withoutMailProviderRateLimit(withBoth, "zoho");
  assertEquals(removed.changed, true);
  assertEquals(removed.metadata, {
    accountId: "a-1",
    gmail_rate_limit_until: gmailUntil,
  });
});

Deno.test("repeated provider throttles use durable exponential backoff", () => {
  const first = advanceMailProviderRateLimit(
    {},
    "gmail",
    "2026-08-15T19:15:00.000Z",
    now,
  );
  assertEquals(first.attempts, 1);
  assertEquals(first.retryAt, "2026-08-15T19:15:00.000Z");

  const second = advanceMailProviderRateLimit(
    first.metadata,
    "gmail",
    "2026-08-15T19:30:00.000Z",
    Date.parse("2026-08-15T19:15:00.000Z"),
  );
  assertEquals(second.attempts, 2);
  assertEquals(second.retryAt, "2026-08-15T19:45:00.000Z");

  const legacySecond = advanceMailProviderRateLimit(
    { gmail_rate_limit_until: "2026-08-15T19:15:00.000Z" },
    "gmail",
    "2026-08-15T19:30:00.000Z",
    Date.parse("2026-08-15T19:15:00.000Z"),
  );
  assertEquals(legacySecond.attempts, 2);
  assertEquals(legacySecond.retryAt, "2026-08-15T19:45:00.000Z");

  const removed = withoutMailProviderRateLimit(second.metadata, "gmail");
  assertEquals(removed.metadata, {});
});
