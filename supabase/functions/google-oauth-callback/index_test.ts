import {
  assert,
  assertEquals,
  assertFalse,
  assertMatch,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertGoogleConnectionCommitted,
  configuredSearchConsoleSiteForTenant,
  handler,
  randomOAuthState,
  resolveTenantStoreOrigin,
  selectGoogleRefreshToken,
  sha256Hex,
} from "./index.ts";

Deno.test("OAuth state is high-entropy base64url and persists as a SHA-256 hash", async () => {
  const rawState = randomOAuthState();
  const stateHash = await sha256Hex(rawState);

  assertMatch(rawState, /^[A-Za-z0-9_-]{43}$/);
  assertMatch(stateHash, /^[0-9a-f]{64}$/);
  assertFalse(stateHash === rawState);
  assertEquals(
    await sha256Hex("known-state"),
    "79c397a7cad00d419985e83cb8e3bb2ff444a0f328704b4e9f2ec5750f7af337",
  );
});

Deno.test("OAuth endpoint uses exact CORS origins and no-store responses", async () => {
  const previousAppUrl = Deno.env.get("APP_URL");
  const previousAllowed = Deno.env.get("CORS_ALLOWED_ORIGINS");
  const previousSupabaseUrl = Deno.env.get("SUPABASE_URL");
  try {
    Deno.env.set("APP_URL", "https://erp.example.com");
    Deno.env.delete("CORS_ALLOWED_ORIGINS");

    const denied = await handler(
      new Request("https://edge.example.com/google-oauth-callback", {
        method: "OPTIONS",
        headers: { Origin: "https://attacker.example.net" },
      }),
    );
    assertEquals(denied.status, 403);
    assertEquals(denied.headers.get("access-control-allow-origin"), null);
    assertEquals(denied.headers.get("cache-control"), "no-store, max-age=0");

    const allowed = await handler(
      new Request("https://edge.example.com/google-oauth-callback", {
        method: "OPTIONS",
        headers: { Origin: "https://erp.example.com" },
      }),
    );
    assertEquals(allowed.status, 204);
    assertEquals(
      allowed.headers.get("access-control-allow-origin"),
      "https://erp.example.com",
    );
    assertEquals(allowed.headers.get("vary"), "Origin");
    assertEquals(allowed.headers.get("cache-control"), "no-store, max-age=0");

    Deno.env.delete("APP_URL");
    Deno.env.set("SUPABASE_URL", "http://127.0.0.1:54321");
    const localPreview = await handler(
      new Request("http://127.0.0.1:54321/google-oauth-callback", {
        method: "OPTIONS",
        headers: { Origin: "http://localhost:52591" },
      }),
    );
    assertEquals(localPreview.status, 204);
    assertEquals(
      localPreview.headers.get("access-control-allow-origin"),
      "http://localhost:52591",
    );
  } finally {
    if (previousAppUrl === undefined) Deno.env.delete("APP_URL");
    else Deno.env.set("APP_URL", previousAppUrl);
    if (previousAllowed === undefined) {
      Deno.env.delete("CORS_ALLOWED_ORIGINS");
    } else {
      Deno.env.set("CORS_ALLOWED_ORIGINS", previousAllowed);
    }
    if (previousSupabaseUrl === undefined) {
      Deno.env.delete("SUPABASE_URL");
    } else {
      Deno.env.set("SUPABASE_URL", previousSupabaseUrl);
    }
  }
});

Deno.test("OAuth property origin requires an explicit server allowlist", () => {
  assertEquals(
    resolveTenantStoreOrigin({
      customDomain: "shop.example.com",
      configuredStoreUrl: "https://shop.example.com/",
      publicStoreOrigins: "https://shop.example.com",
    }),
    "https://shop.example.com/",
  );

  let failed = false;
  try {
    resolveTenantStoreOrigin({
      customDomain: "shop.example.com",
      configuredStoreUrl: "https://shop.example.com/",
    });
  } catch (error) {
    failed = String(error).includes("allowlist");
  }
  assert(failed);
});

Deno.test("legacy Search Console property has one explicit tenant owner", () => {
  const tenantA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const tenantB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  assertEquals(
    configuredSearchConsoleSiteForTenant(
      tenantA,
      "sc-domain:shop.example.com",
      tenantA,
    ),
    "sc-domain:shop.example.com",
  );
  assertEquals(
    configuredSearchConsoleSiteForTenant(
      tenantB,
      "sc-domain:shop.example.com",
      tenantA,
    ),
    "",
  );
  assertThrows(
    () =>
      configuredSearchConsoleSiteForTenant(
        tenantA,
        "sc-domain:shop.example.com",
        "",
      ),
    Error,
    "must explicitly own",
  );
});

Deno.test("a superseded OAuth callback cannot report a successful commit", () => {
  assertGoogleConnectionCommitted({ committed: true, generation: 3 });
  assertThrows(
    () =>
      assertGoogleConnectionCommitted({
        committed: false,
        reason: "superseded",
      }),
    Error,
    "reemplazada",
  );
});

Deno.test("OAuth never reuses a refresh token across Google accounts", () => {
  assertEquals(
    selectGoogleRefreshToken({
      issuedRefreshToken: "newly-issued",
      authorizedAccountEmail: "new@example.com",
      existingRefreshToken: "old",
      existingAccountEmail: "old@example.com",
    }),
    "newly-issued",
  );
  assertEquals(
    selectGoogleRefreshToken({
      authorizedAccountEmail: "SAME@example.com",
      existingRefreshToken: "same-account-token",
      existingAccountEmail: "same@example.com",
    }),
    "same-account-token",
  );
  assertEquals(
    selectGoogleRefreshToken({
      authorizedAccountEmail: "new@example.com",
      existingRefreshToken: "old-account-token",
      existingAccountEmail: "old@example.com",
      legacyRefreshToken: "legacy-old-account-token",
      legacyAccountEmail: "old@example.com",
    }),
    "",
  );
  assertEquals(
    selectGoogleRefreshToken({
      authorizedAccountEmail: "",
      existingRefreshToken: "unowned-token",
      existingAccountEmail: "",
    }),
    "",
  );
});

Deno.test("OAuth rejects an oversized JSON body before authorization", async () => {
  const response = await handler(
    new Request("https://edge.example.com/google-oauth-callback", {
      method: "POST",
      headers: {
        Origin: "https://project-vinabike.web.app",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ padding: "x".repeat(33 * 1024) }),
    }),
  );
  assertEquals(response.status, 413);
});
