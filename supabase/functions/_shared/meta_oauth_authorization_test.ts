import { assertEquals, assertThrows } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildMetaDebugTokenUrl,
  buildMetaOAuthAuthorizationUrl,
  buildMetaSystemUserTokenExchangeUrl,
  earliestMetaTokenExpiresAt,
  missingRequiredMetaPageTasks,
  parseMetaDebugTokenEvidence,
  parseMetaLoginConfigId,
  parseMetaSystemUserBusinessIdentity,
  resolveMetaSystemUserTokenExpiresAt,
} from "./meta_oauth_authorization.ts";

Deno.test("accepts only bounded decimal Meta login config IDs", () => {
  assertEquals(parseMetaLoginConfigId("1234567890123456"), "1234567890123456");
  assertEquals(parseMetaLoginConfigId(undefined), null);
  assertEquals(parseMetaLoginConfigId(""), null);
  assertEquals(parseMetaLoginConfigId(" 1234567890123456"), null);
  assertEquals(parseMetaLoginConfigId("1234567890123456 "), null);
  assertEquals(parseMetaLoginConfigId("+1234567890123456"), null);
  assertEquals(parseMetaLoginConfigId("1234567890123456&scope=email"), null);
  assertEquals(parseMetaLoginConfigId("1".repeat(33)), null);
});

Deno.test("builds the v25.0 Business Login authorization URL with config_id", () => {
  const url = buildMetaOAuthAuthorizationUrl({
    graphVersion: "v25.0",
    appId: "99999999999999999",
    redirectUri: "https://example.supabase.co/functions/v1/meta-oauth/callback",
    state: "opaque-state",
    loginConfigId: "1234567890123456",
  });

  assertEquals(url.origin, "https://www.facebook.com");
  assertEquals(url.pathname, "/v25.0/dialog/oauth");
  assertEquals(url.searchParams.get("client_id"), "99999999999999999");
  assertEquals(
    url.searchParams.get("redirect_uri"),
    "https://example.supabase.co/functions/v1/meta-oauth/callback",
  );
  assertEquals(url.searchParams.get("state"), "opaque-state");
  assertEquals(url.searchParams.get("response_type"), "code");
  assertEquals(url.searchParams.has("scope"), false);
  assertEquals(url.searchParams.has("auth_type"), false);
  assertEquals(url.searchParams.get("config_id"), "1234567890123456");
  assertEquals(url.searchParams.get("override_default_response_type"), "true");
});

Deno.test("refuses to build a Business Login URL without a valid config_id", () => {
  assertThrows(
    () =>
      buildMetaOAuthAuthorizationUrl({
        graphVersion: "v25.0",
        appId: "99999999999999999",
        redirectUri: "https://example.supabase.co/functions/v1/meta-oauth/callback",
        state: "opaque-state",
        loginConfigId: "invalid-config-id",
      }),
    Error,
    "invalid_meta_login_config_id",
  );
});

Deno.test("builds one system-user code exchange without a long-token grant", () => {
  const url = buildMetaSystemUserTokenExchangeUrl({
    graphVersion: "v25.0",
    appId: "99999999999999999",
    appSecret: "test-only-app-secret",
    redirectUri: "https://example.supabase.co/functions/v1/meta-oauth/callback",
    code: "single-use-code",
  });

  assertEquals(url.origin, "https://graph.facebook.com");
  assertEquals(url.pathname, "/v25.0/oauth/access_token");
  assertEquals(url.searchParams.get("code"), "single-use-code");
  assertEquals(url.searchParams.has("grant_type"), false);
  assertEquals(url.searchParams.has("fb_exchange_token"), false);
});

Deno.test("builds the v25.0 debug_token URL without changing the token", () => {
  const url = buildMetaDebugTokenUrl("v25.0", "opaque-test-token");
  assertEquals(url.origin, "https://graph.facebook.com");
  assertEquals(url.pathname, "/v25.0/debug_token");
  assertEquals(url.searchParams.get("input_token"), "opaque-test-token");
});

Deno.test("parses valid debug evidence and uses the earliest absolute expiry", () => {
  const now = Date.UTC(2026, 6, 21, 12, 0, 0);
  const nowSeconds = now / 1_000;
  const evidence = parseMetaDebugTokenEvidence({
    data: {
      app_id: "99999999999999999",
      is_valid: true,
      expires_at: nowSeconds + 3_600,
      data_access_expires_at: nowSeconds + 1_800,
      scopes: ["pages_messaging", "pages_show_list"],
      granular_scopes: [{
        scope: "instagram_manage_messages",
        target_ids: ["111111111111111"],
      }],
      user_id: "222222222222222",
    },
  }, {
    expectedAppId: "99999999999999999",
    nowMilliseconds: now,
  });

  assertEquals(evidence.tokenExpiresAt, "2026-07-21T12:30:00.000Z");
  assertEquals(evidence.expiresAt, "2026-07-21T13:00:00.000Z");
  assertEquals(evidence.dataAccessExpiresAt, "2026-07-21T12:30:00.000Z");
  assertEquals(evidence.grantedScopes, [
    "instagram_manage_messages",
    "pages_messaging",
    "pages_show_list",
  ]);
  assertEquals(evidence.subjectId, "222222222222222");
  assertEquals(evidence.profileId, null);
});

Deno.test("accepts permanent or omitted Page-token expiry metadata", () => {
  const now = Date.UTC(2026, 6, 21, 12, 0, 0);
  const permanent = parseMetaDebugTokenEvidence({
    data: {
      app_id: "99999999999999999",
      is_valid: true,
      expires_at: 0,
      data_access_expires_at: 0,
      profile_id: "111111111111111",
    },
  }, {
    expectedAppId: "99999999999999999",
    nowMilliseconds: now,
  });
  const omitted = parseMetaDebugTokenEvidence({
    data: {
      app_id: "99999999999999999",
      is_valid: true,
      profile_id: "111111111111111",
    },
  }, {
    expectedAppId: "99999999999999999",
    nowMilliseconds: now,
  });

  assertEquals(permanent.tokenExpiresAt, null);
  assertEquals(permanent.hasExpiresAtEvidence, true);
  assertEquals(omitted.tokenExpiresAt, null);
  assertEquals(omitted.hasExpiresAtEvidence, false);
  assertEquals(omitted.profileId, "111111111111111");
});

Deno.test("fails closed on invalid debug-token identity or expiry evidence", () => {
  const now = Date.UTC(2026, 6, 21, 12, 0, 0);
  const nowSeconds = now / 1_000;
  for (
    const payload of [
      null,
      [],
      { data: { app_id: "99999999999999999", is_valid: false } },
      { data: { app_id: "wrong-app", is_valid: true } },
      {
        data: {
          app_id: "99999999999999999",
          is_valid: true,
          expires_at: nowSeconds - 1,
        },
      },
      {
        data: {
          app_id: "99999999999999999",
          is_valid: true,
          profile_id: "not-an-id",
        },
      },
    ]
  ) {
    assertThrows(
      () =>
        parseMetaDebugTokenEvidence(payload, {
          expectedAppId: "99999999999999999",
          nowMilliseconds: now,
        }),
      Error,
    );
  }
});

Deno.test("resolves SUAT expiry from debug metadata with bounded fallback", () => {
  const now = Date.UTC(2026, 6, 21, 12, 0, 0);
  const nowSeconds = now / 1_000;
  const debugEvidence = parseMetaDebugTokenEvidence({
    data: {
      app_id: "99999999999999999",
      is_valid: true,
      expires_at: nowSeconds + 3_600,
      data_access_expires_at: nowSeconds + 1_800,
    },
  }, {
    expectedAppId: "99999999999999999",
    nowMilliseconds: now,
  });
  assertEquals(
    resolveMetaSystemUserTokenExpiresAt(
      debugEvidence,
      { expires_in: 3_600 },
      now,
    ),
    "2026-07-21T12:30:00.000Z",
  );

  const noTokenExpiry = parseMetaDebugTokenEvidence({
    data: {
      app_id: "99999999999999999",
      is_valid: true,
      data_access_expires_at: nowSeconds + 1_800,
    },
  }, {
    expectedAppId: "99999999999999999",
    nowMilliseconds: now,
  });
  assertEquals(
    resolveMetaSystemUserTokenExpiresAt(
      noTokenExpiry,
      { expires_in: 3_600 },
      now,
    ),
    "2026-07-21T12:30:00.000Z",
  );
  assertThrows(
    () =>
      resolveMetaSystemUserTokenExpiresAt(
        debugEvidence,
        { expires_in: 7_200 },
        now,
      ),
    Error,
    "conflicting_system_user_token_expiry",
  );
});

Deno.test("requires exact case-insensitive Page messaging tasks", () => {
  assertEquals(missingRequiredMetaPageTasks(["messaging", "MODERATE"]), []);
  assertEquals(missingRequiredMetaPageTasks(["MESSAGING"]), ["MODERATE"]);
  assertEquals(missingRequiredMetaPageTasks(["MESSAGING_ADMIN", "MODERATE"]), [
    "MESSAGING",
  ]);
  assertEquals(missingRequiredMetaPageTasks("MESSAGING,MODERATE"), [
    "MESSAGING",
    "MODERATE",
  ]);
});

Deno.test("requires matching system-user and client business identity", () => {
  assertEquals(
    parseMetaSystemUserBusinessIdentity(
      {
        id: "222222222222222",
        client_business_id: "333333333333333",
      },
      "222222222222222",
    ),
    {
      id: "222222222222222",
      clientBusinessId: "333333333333333",
    },
  );
  assertThrows(
    () =>
      parseMetaSystemUserBusinessIdentity(
        { id: "222222222222222", client_business_id: "333333333333333" },
        "444444444444444",
      ),
    Error,
    "system_user_identity_mismatch",
  );
  assertThrows(
    () =>
      parseMetaSystemUserBusinessIdentity(
        { id: "222222222222222" },
        "222222222222222",
      ),
    Error,
  );
});

Deno.test("uses the earliest conservative SUAT or Page-token expiry", () => {
  assertEquals(
    earliestMetaTokenExpiresAt(
      "2026-09-19T12:00:00.000Z",
      "2026-08-20T12:00:00.000Z",
    ),
    "2026-08-20T12:00:00.000Z",
  );
  assertEquals(
    earliestMetaTokenExpiresAt("2026-09-19T12:00:00.000Z", null),
    "2026-09-19T12:00:00.000Z",
  );
  assertEquals(earliestMetaTokenExpiresAt(null, null), null);
  assertThrows(
    () => earliestMetaTokenExpiresAt("not-a-date"),
    Error,
    "invalid_meta_token_expiry",
  );
});
