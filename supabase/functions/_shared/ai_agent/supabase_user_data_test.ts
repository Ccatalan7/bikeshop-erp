import {
  canonicalJson,
  createSupabaseRuntimeStoreClient,
  createSupabaseUserDataClient,
  SupabaseUserDataError,
} from "./supabase_user_data.ts";

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}

Deno.test("attested canonical JSON carries fixed-point technical measurements", () => {
  assertEquals(
    canonicalJson({ width: 2.25, minimum: 0.001, wheel: 29, negativeZero: -0 }),
    '{"minimum":0.001,"negativeZero":0,"wheel":29,"width":2.25}',
    "technical decimals share one fixed-point representation",
  );

  for (const invalid of [Number.NaN, Number.POSITIVE_INFINITY, 0.0000001, 1e16]) {
    let rejected = false;
    try {
      canonicalJson({ value: invalid });
    } catch (error) {
      rejected = error instanceof Error && error.message === "Attested JSON number is invalid";
    }
    assertEquals(rejected, true, `${String(invalid)} stays outside the attested numeric subset`);
  }
});

Deno.test("caller data transport keeps publishable key and user JWT together", async () => {
  let headers: Headers | null = null;
  const client = createSupabaseUserDataClient({
    supabaseUrl: "https://project.supabase.co",
    publishableKey: "sb_publishable_test",
    authorization: "Bearer caller.jwt.value",
    fetchImpl: (_input, init) => {
      headers = new Headers(init?.headers);
      return Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }));
    },
  });
  await client.rpc(
    "assistant_search_inventory_v5",
    {
      p_query: "cadena",
      p_category: null,
      p_availability: "any",
      p_technical_predicates: [],
    },
    new AbortController().signal,
  );
  const callerHeaders = headers as Headers | null;
  if (!callerHeaders) throw new Error("caller request was not sent");
  assertEquals(callerHeaders.get("apikey"), "sb_publishable_test", "publishable apikey used");
  assertEquals(callerHeaders.get("authorization"), "Bearer caller.jwt.value", "caller JWT used");
});

Deno.test("runtime mutation uses caller JWT plus an exact Unicode HMAC attestation", async () => {
  let url = "";
  let headers: Headers | null = null;
  let requestBody: Record<string, string> | null = null;
  const now = new Date("2026-08-11T12:00:00.000Z");
  const nonce = "44444444-4444-4444-8444-444444444444";
  const parameters = {
    p_tenant_id: "11111111-1111-4111-8111-111111111111",
    p_actor_user_id: "22222222-2222-4222-8222-222222222222",
    p_authority_fingerprint: "a".repeat(64),
    p_run_id: "33333333-3333-4333-8333-333333333333",
    p_lease_token: "55555555-5555-4555-8555-555555555555",
    p_fence_token: 7,
    p_lease_ttl_seconds: 110,
    p_unicode_note: "Mañana 🚲",
  };
  const client = createSupabaseRuntimeStoreClient({
    supabaseUrl: "https://project.supabase.co",
    publishableKey: "sb_publishable_test",
    authorization: "Bearer caller.jwt.value",
    attestationKeyId: "runtime-2026-08",
    attestationKeyHex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
    attestationAudience: "supabase:projectref:assistant-runtime",
    now: () => now,
    randomUuid: () => nonce,
    fetchImpl: (input, init) => {
      url = input.toString();
      headers = new Headers(init?.headers);
      requestBody = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }));
    },
  });
  await client.rpc("assistant_heartbeat_run_v2", parameters, new AbortController().signal);
  const runtimeHeaders = headers as Headers | null;
  if (!runtimeHeaders) throw new Error("runtime request was not sent");
  assertEquals(
    runtimeHeaders.get("apikey"),
    "sb_publishable_test",
    "runtime apikey is publishable",
  );
  assertEquals(
    runtimeHeaders.get("authorization"),
    "Bearer caller.jwt.value",
    "original caller JWT is retained",
  );
  assertEquals(
    runtimeHeaders.get("content-profile"),
    "assistant_runtime",
    "runtime write schema fixed",
  );
  assertEquals(
    runtimeHeaders.get("accept-profile"),
    "assistant_runtime",
    "runtime read schema fixed",
  );
  assertEquals(
    url.endsWith("/rest/v1/rpc/assistant_heartbeat_run_v2"),
    true,
    "fixed mutation endpoint",
  );
  const sent = requestBody as Record<string, string> | null;
  if (!sent) throw new Error("attested request body was not sent");
  const expectedBody =
    '{"p_actor_user_id":"22222222-2222-4222-8222-222222222222","p_authority_fingerprint":"' +
    "a".repeat(64) +
    '","p_fence_token":7,"p_lease_token":"55555555-5555-4555-8555-555555555555","p_lease_ttl_seconds":110,"p_run_id":"33333333-3333-4333-8333-333333333333","p_tenant_id":"11111111-1111-4111-8111-111111111111","p_unicode_note":"Mañana 🚲"}';
  assertEquals(sent.p_body, expectedBody, "Unicode body has one deterministic canonical form");
  const issuedAt = Math.floor(now.getTime() / 1000);
  const expectedEnvelope = [
    "VINABIKE-AI-ATTESTATION-V1",
    "kid=runtime-2026-08",
    "aud=supabase:projectref:assistant-runtime",
    "iss=ai-agent-gateway",
    "op=assistant_heartbeat_run_v2",
    `nonce=${nonce}`,
    `iat=${issuedAt}`,
    `exp=${issuedAt + 60}`,
    "sub=22222222-2222-4222-8222-222222222222",
    "tenant=11111111-1111-4111-8111-111111111111",
    `authority=${"a".repeat(64)}`,
    "run=33333333-3333-4333-8333-333333333333",
    "lease=55555555-5555-4555-8555-555555555555",
    "fence=7",
    `body-bytes=${new TextEncoder().encode(expectedBody).byteLength}`,
  ].join("\n");
  assertEquals(sent.p_envelope, expectedEnvelope, "attestation envelope is exact and has no LF");
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from({ length: 32 }, (_, index) => index),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const material = new TextEncoder().encode(`${expectedEnvelope}\0${expectedBody}`);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, material));
  assertEquals(
    sent.p_mac_hex,
    [...mac].map((byte) => byte.toString(16).padStart(2, "0")).join(""),
    "MAC covers envelope, NUL separator and exact UTF-8 body",
  );
});

Deno.test("runtime transport rejects every authority and business RPC before fetch", async () => {
  let fetchCalls = 0;
  const client = createSupabaseRuntimeStoreClient({
    supabaseUrl: "https://project.supabase.co",
    publishableKey: "sb_publishable_test",
    authorization: "Bearer caller.jwt.value",
    attestationKeyId: "runtime-test",
    attestationKeyHex: "11".repeat(32),
    attestationAudience: "supabase:projectref:assistant-runtime",
    fetchImpl: () => {
      fetchCalls++;
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  });
  for (
    const rpc of [
      "assistant_begin_run_v1",
      "assistant_get_authority_v1",
      "assistant_search_inventory_v5",
      "assistant_heartbeat_run_v1",
    ]
  ) {
    let rejected = false;
    try {
      await client.rpc(rpc, {}, new AbortController().signal);
    } catch (error) {
      rejected = error instanceof SupabaseUserDataError && !error.retryable;
    }
    assertEquals(rejected, true, `${rpc} is forbidden to privileged transport`);
  }
  assertEquals(fetchCalls, 0, "no privileged business read leaves Edge");
});

Deno.test("caller RPC errors discard upstream details", async () => {
  const secret = "sensitive-upstream-details";
  const client = createSupabaseUserDataClient({
    supabaseUrl: "https://project.supabase.co",
    publishableKey: "sb_publishable_test",
    authorization: "Bearer caller.jwt.value",
    fetchImpl: () => Promise.resolve(new Response(secret, { status: 500 })),
  });
  try {
    await client.rpc("assistant_search_inventory_v5", {}, new AbortController().signal);
  } catch (error) {
    assertEquals(error instanceof SupabaseUserDataError, true, "typed transport error");
    assertEquals(String(error).includes(secret), false, "body never reaches the error");
    return;
  }
  throw new Error("RPC error unexpectedly succeeded");
});

Deno.test("PostgREST SQLSTATE outcomes are closed and never expose server prose", async () => {
  const cases = [
    ["22023", "idempotency_conflict"],
    ["42501", "forbidden"],
    ["P0001", "quota_exceeded"],
  ] as const;
  for (const [sqlstate, outcome] of cases) {
    const secret = `secret-${sqlstate}`;
    const client = createSupabaseUserDataClient({
      supabaseUrl: "https://project.supabase.co",
      publishableKey: "sb_publishable_test",
      authorization: "Bearer caller.jwt.value",
      fetchImpl: () =>
        Promise.resolve(
          new Response(
            JSON.stringify({
              code: sqlstate,
              message: secret,
              details: `details-${secret}`,
              hint: `hint-${secret}`,
            }),
            { status: 400 },
          ),
        ),
    });
    try {
      await client.rpc("assistant_begin_run_v1", {}, new AbortController().signal);
    } catch (error) {
      assertEquals(error instanceof SupabaseUserDataError, true, "typed transport error");
      if (!(error instanceof SupabaseUserDataError)) throw error;
      assertEquals(error.outcome, outcome, `${sqlstate} has a closed outcome`);
      assertEquals(String(error).includes(secret), false, "message/details/hint never escape");
      continue;
    }
    throw new Error(`${sqlstate} unexpectedly succeeded`);
  }
});

Deno.test("unknown, malformed and oversized PostgREST errors stay generic", async () => {
  const bodies = [
    JSON.stringify({ code: "XX999", message: "sensitive unknown" }),
    "not-json-sensitive",
    JSON.stringify({ code: "22023", message: "x".repeat(5_000) }),
  ];
  for (const body of bodies) {
    const client = createSupabaseUserDataClient({
      supabaseUrl: "https://project.supabase.co",
      publishableKey: "sb_publishable_test",
      authorization: "Bearer caller.jwt.value",
      fetchImpl: () => Promise.resolve(new Response(body, { status: 500 })),
    });
    try {
      await client.rpc("assistant_begin_run_v1", {}, new AbortController().signal);
    } catch (error) {
      assertEquals(error instanceof SupabaseUserDataError, true, "error remains typed");
      if (!(error instanceof SupabaseUserDataError)) throw error;
      assertEquals(error.outcome, "unavailable", "unrecognized body maps only to generic outage");
      assertEquals(String(error).includes("sensitive"), false, "raw body never escapes");
      continue;
    }
    throw new Error("unknown error unexpectedly succeeded");
  }
});
