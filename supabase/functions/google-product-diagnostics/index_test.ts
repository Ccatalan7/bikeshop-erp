import {
  assert,
  assertEquals,
  assertFalse,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  acquireDurableMerchantRefreshLease,
  beginMerchantRefresh,
  claimNetworkBudget,
  collectSiteArtifactStatus,
  configuredSearchConsoleSiteForTenant,
  createNetworkBudget,
  handler,
  isPrivateOrReservedIp,
  merchantIntegrationForTenant,
  persistOrReuseConcurrentGoogleOAuthRefresh,
  releaseDurableMerchantRefreshLease,
  renewDurableMerchantRefreshLease,
  resolveTenantStoreOrigin,
  searchConsoleAccessToken,
  searchConsoleSetupNotes,
  storeArtifactDnsSafetyBoundary,
} from "./index.ts";

const publicDns = () => Promise.resolve(["93.184.216.34"]);
const serverOwnedOrigins = ["https://shop.example.com"] as const;

Deno.test("diagnostics rejects untrusted browser origins before authorization", async () => {
  const response = await handler(
    new Request("https://edge.example.com/google-product-diagnostics", {
      method: "POST",
      headers: { Origin: "https://attacker.example.net" },
      body: "{}",
    }),
  );
  assertEquals(response.status, 403);
  assertEquals(response.headers.get("access-control-allow-origin"), null);
  assertEquals(response.headers.get("cache-control"), "no-store, max-age=0");
});

Deno.test("diagnostics rejects an oversized JSON body before authorization", async () => {
  const response = await handler(
    new Request("https://edge.example.com/google-product-diagnostics", {
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

Deno.test("tenant store origin is HTTPS and owned by tenant metadata", () => {
  assertEquals(
    resolveTenantStoreOrigin({
      customDomain: "shop.example.com",
      configuredStoreUrl: "https://shop.example.com/",
      publicStoreOrigins: "https://shop.example.com",
    }),
    "https://shop.example.com/",
  );
  assertEquals(
    resolveTenantStoreOrigin({
      subdomain: "shop",
      publicStoreBaseDomain: "stores.example.com",
    }),
    "https://shop.stores.example.com/",
  );
  assertThrows(
    () =>
      resolveTenantStoreOrigin({
        customDomain: "shop.example.com",
        configuredStoreUrl: "https://unrelated.example.net/",
        publicStoreOrigins: "https://shop.example.com",
      }),
    Error,
    "does not belong to this tenant",
  );
  assertThrows(
    () =>
      resolveTenantStoreOrigin({
        customDomain: "127.0.0.1",
        publicStoreOrigins: "https://127.0.0.1",
      }),
    Error,
    "allowlist",
  );
  assertThrows(
    () =>
      resolveTenantStoreOrigin({
        customDomain: "shop.example.com",
        configuredStoreUrl: "https://shop.example.com/",
      }),
    Error,
    "allowlist",
  );
});

Deno.test("legacy Search Console site configuration is tenant-owned", () => {
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

Deno.test("exact tenant OAuth is preferred over the global service account", async () => {
  let serviceAccountCalls = 0;
  const result = await searchConsoleAccessToken(
    {
      tenantId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      siteUrl: "sc-domain:shop.example.com",
      requireWrite: true,
    },
    {
      oauthToken: () =>
        Promise.resolve({
          ok: true as const,
          accessToken: "tenant-oauth-token",
          scope: "https://www.googleapis.com/auth/webmasters",
        }),
      serviceAccountToken: () => {
        serviceAccountCalls += 1;
        return Promise.resolve({
          accessToken: "global-service-token",
          email: "global@example.invalid",
        });
      },
    },
  );
  assert(result.ok);
  assertEquals(result.source, "oauth");
  assertEquals(result.accessToken, "tenant-oauth-token");
  assertEquals(serviceAccountCalls, 0);
});

Deno.test("setup copy describes exact tenant OAuth as the primary credential", () => {
  const notes = searchConsoleSetupNotes("sc-domain:shop.example.com");
  assert(notes[0].includes("exact tenant/site OAuth credential"));
  assert(notes[0].includes("sc-domain:shop.example.com"));
  assert(notes[1].includes("service-account fallback"));
  assertFalse(notes.some((note) => note.includes("OAuth is only a fallback")));
});

Deno.test("refresh CAS loser reuses only the fresh same-generation winner", async () => {
  const tenantId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const siteUrl = "sc-domain:shop.example.com";
  const nowMs = Date.parse("2026-07-28T20:00:00.000Z");
  const winner = await persistOrReuseConcurrentGoogleOAuthRefresh(
    {
      tenantId,
      siteUrl,
      generation: 7,
      expectedCredentialVersion: 12,
      refreshedAccessToken: "loser-network-token",
      tokenType: "Bearer",
      scope: "scope-a",
      expiresAt: "2026-07-28T21:00:00.000Z",
      nowMs,
    },
    () => Promise.resolve({ data: false, error: null }),
    () =>
      Promise.resolve({
        access_token: "winner-committed-token",
        scope: "winner-scope",
        expires_at: "2026-07-28T21:00:00.000Z",
        generation: 7,
        credential_version: 13,
      }),
  );
  assertEquals(winner.accessToken, "winner-committed-token");
  assertEquals(winner.scope, "winner-scope");

  await assertRejects(
    () =>
      persistOrReuseConcurrentGoogleOAuthRefresh(
        {
          tenantId,
          siteUrl,
          generation: 7,
          expectedCredentialVersion: 12,
          refreshedAccessToken: "must-not-be-used",
          tokenType: "Bearer",
          scope: "scope-a",
          expiresAt: "2026-07-28T21:00:00.000Z",
          nowMs,
        },
        () => Promise.resolve({ data: false, error: null }),
        () =>
          Promise.resolve({
            access_token: "reconnected-account-token",
            scope: "winner-scope",
            expires_at: "2026-07-28T21:00:00.000Z",
            generation: 8,
            credential_version: 1,
          }),
      ),
    Error,
    "was reconnected",
  );
});

Deno.test("site status fetches only fixed same-origin artifacts and reports facts", async () => {
  const calls: string[] = [];
  const fetchImpl: typeof fetch = (input, init) => {
    const url = String(input);
    calls.push(url);
    assertEquals(init?.redirect, "manual");
    if (url.endsWith("/release.json")) {
      return Promise.resolve(
        new Response(
          JSON.stringify({
            commit: "0123456789abcdef0123456789abcdef01234567",
            run: "42",
            built_at: "2026-07-28T20:00:00.000Z",
            target: "store",
            source: "workflow",
            dirty: false,
            publication: {
              request_id: "11111111-1111-4111-8111-111111111111",
              owner_revision: 42,
              owner_source_sha256: "a".repeat(64),
              build_input_sha256: "b".repeat(64),
            },
          }),
          {
            headers: {
              "content-type": "application/json",
              etag: '"release-etag"',
            },
          },
        ),
      );
    }
    if (url.endsWith("/sitemap.xml")) {
      return Promise.resolve(
        new Response(
          '<?xml version="1.0"?><urlset><url><loc>https://shop.example.com/</loc></url></urlset>',
          { headers: { "content-type": "application/xml" } },
        ),
      );
    }
    return Promise.resolve(
      new Response(
        "User-agent: *\nAllow: /\nSitemap: https://shop.example.com/sitemap.xml\n",
        { headers: { "content-type": "text/plain" } },
      ),
    );
  };

  const result = await collectSiteArtifactStatus(
    "https://shop.example.com/",
    {
      fetchImpl,
      now: () => new Date("2026-07-28T20:01:00.000Z"),
      dnsResolver: publicDns,
      serverOwnedOrigins,
    },
  );

  assertEquals(
    calls.sort(),
    [
      "https://shop.example.com/release.json",
      "https://shop.example.com/robots.txt",
      "https://shop.example.com/sitemap.xml",
    ],
  );
  assertEquals(
    result.release.commit,
    "0123456789abcdef0123456789abcdef01234567",
  );
  assertEquals(result.release.observedAt, "2026-07-28T20:01:00.000Z");
  assert(result.release.documentValid);
  assert(result.release.publicationTracked);
  assert(result.release.publicationValid);
  assertEquals(
    result.release.publication?.requestId,
    "11111111-1111-4111-8111-111111111111",
  );
  assertEquals(result.release.publication?.ownerRevision, 42);
  assertEquals(result.sitemap.urlEntryCount, 1);
  assert(result.sitemap.canonicalOriginConsistent);
  assert(result.robots.expectedSitemapDeclared);
  assert(result.summary.allDocumentsValid);
});

Deno.test("release evidence distinguishes untracked from malformed publication", async () => {
  const releaseFor = (publication: unknown) => {
    const fetchImpl: typeof fetch = (input) => {
      const url = String(input);
      if (url.endsWith("/release.json")) {
        return Promise.resolve(
          Response.json({
            commit: "0123456789abcdef0123456789abcdef01234567",
            run: "42",
            built_at: "2026-07-28T20:00:00.000Z",
            target: "store",
            source: "github-actions",
            dirty: false,
            publication,
          }),
        );
      }
      if (url.endsWith("/sitemap.xml")) {
        return Promise.resolve(
          new Response(
            "<urlset><url><loc>https://shop.example.com/</loc></url></urlset>",
          ),
        );
      }
      return Promise.resolve(
        new Response(
          "User-agent: *\nAllow: /\nSitemap: https://shop.example.com/sitemap.xml\n",
        ),
      );
    };
    return collectSiteArtifactStatus("https://shop.example.com/", {
      fetchImpl,
      dnsResolver: publicDns,
      serverOwnedOrigins,
      now: () => new Date("2026-07-28T20:01:00.000Z"),
    });
  };

  const untracked = await releaseFor(null);
  assert(untracked.release.documentValid);
  assertFalse(untracked.release.publicationTracked);
  assertFalse(untracked.release.publicationValid);

  const malformed = await releaseFor({
    request_id: "not-a-uuid",
    owner_revision: 0,
    owner_source_sha256: "short",
    build_input_sha256: "also-short",
  });
  assertFalse(malformed.release.documentValid);
  assert(malformed.release.publicationTracked);
  assertFalse(malformed.release.publicationValid);
  assert(
    malformed.release.invalidReasons.some((reason: string) => reason.startsWith("publication_")),
  );
});

Deno.test("site status blocks redirects and bounds slow artifact requests", async () => {
  const redirectingFetch: typeof fetch = () =>
    Promise.resolve(
      new Response(null, {
        status: 302,
        headers: { location: "https://unrelated.example.net/" },
      }),
    );
  const redirected = await collectSiteArtifactStatus(
    "https://shop.example.com/",
    { fetchImpl: redirectingFetch, dnsResolver: publicDns, serverOwnedOrigins },
  );
  assert(!redirected.summary.allHttpOk);
  assertEquals(
    redirected.release.error,
    "Redirect blocked while collecting same-origin site evidence",
  );

  const slowFetch: typeof fetch = (_input, init) =>
    new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => {
        reject(new DOMException("Aborted", "AbortError"));
      });
    });
  const timedOut = await collectSiteArtifactStatus(
    "https://shop.example.com/",
    {
      fetchImpl: slowFetch,
      timeoutMs: 5,
      dnsResolver: publicDns,
      serverOwnedOrigins,
    },
  );
  assert(timedOut.release.timedOut);
  assert(timedOut.sitemap.timedOut);
  assert(timedOut.robots.timedOut);
  assert(!timedOut.summary.allReachable);

  const slowBodyFetch: typeof fetch = (_input, init) =>
    Promise.resolve(
      new Response(
        new ReadableStream<Uint8Array>({
          start(controller) {
            controller.enqueue(new TextEncoder().encode("partial"));
            init?.signal?.addEventListener("abort", () => {
              controller.error(new DOMException("Aborted", "AbortError"));
            });
          },
        }),
      ),
    );
  const bodyTimedOut = await collectSiteArtifactStatus(
    "https://shop.example.com/",
    {
      fetchImpl: slowBodyFetch,
      timeoutMs: 5,
      dnsResolver: publicDns,
      serverOwnedOrigins,
    },
  );
  assert(bodyTimedOut.release.timedOut);
  assert(bodyTimedOut.sitemap.timedOut);
  assert(bodyTimedOut.robots.timedOut);
});

Deno.test("site status rejects private or mixed DNS before any HTTP fetch", async () => {
  let fetchCalls = 0;
  const fetchImpl: typeof fetch = () => {
    fetchCalls += 1;
    return Promise.resolve(new Response("unexpected"));
  };

  for (
    const addresses of [
      ["127.0.0.1"],
      ["10.0.0.1"],
      ["169.254.1.1"],
      ["172.16.0.1"],
      ["192.168.1.1"],
      ["100.64.0.1"],
      ["::1"],
      ["fd00::1"],
      ["fe80::1"],
      ["93.184.216.34", "192.168.1.1"],
    ]
  ) {
    let failed = false;
    try {
      await collectSiteArtifactStatus("https://shop.example.com/", {
        fetchImpl,
        dnsResolver: () => Promise.resolve(addresses),
        serverOwnedOrigins,
      });
    } catch (error) {
      failed = String(error).includes("private or reserved");
    }
    assert(failed);
  }
  assertEquals(fetchCalls, 0);
});

Deno.test("tenant-controlled DNS cannot cross the exact server-owned origin boundary", async () => {
  let resolverCalls = 0;
  let fetchCalls = 0;
  let failed = false;
  try {
    await collectSiteArtifactStatus("https://tenant-controlled.example.net/", {
      serverOwnedOrigins: ["https://shop.example.com"],
      dnsResolver: () => {
        resolverCalls += 1;
        return Promise.resolve(
          resolverCalls === 1 ? ["93.184.216.34"] : ["127.0.0.1"],
        );
      },
      fetchImpl: () => {
        fetchCalls += 1;
        return Promise.resolve(new Response("unexpected"));
      },
    });
  } catch (error) {
    failed = String(error).includes("exact server-owned origins");
  }
  assert(failed);
  assertEquals(resolverCalls, 0);
  assertEquals(fetchCalls, 0);
});

Deno.test("an operator-owned origin still rejects mixed public/private DNS", async () => {
  let fetchCalls = 0;
  await assertRejects(
    () =>
      collectSiteArtifactStatus("https://shop.example.com/", {
        serverOwnedOrigins,
        dnsResolver: () => Promise.resolve(["93.184.216.34", "fec0::1"]),
        fetchImpl: () => {
          fetchCalls += 1;
          return Promise.resolve(new Response("unexpected"));
        },
      }),
    Error,
    "private or reserved",
  );
  assertEquals(fetchCalls, 0);
});

Deno.test("release and robots facts fail closed on dirty builds and root blocking", async () => {
  const fetchImpl: typeof fetch = (input) => {
    const url = String(input);
    if (url.endsWith("/release.json")) {
      return Promise.resolve(
        Response.json({
          commit: "0123456789abcdef0123456789abcdef01234567",
          run: "42",
          built_at: "2026-07-28T20:00:00.000Z",
          target: "store",
          source: "workflow",
          dirty: true,
        }),
      );
    }
    if (url.endsWith("/sitemap.xml")) {
      return Promise.resolve(
        new Response(
          "<urlset><url><loc>https://shop.example.com/</loc></url></urlset>",
        ),
      );
    }
    return Promise.resolve(
      new Response(
        "User-agent: *\nDisallow: /\nSitemap: https://shop.example.com/sitemap.xml\n",
      ),
    );
  };

  const result = await collectSiteArtifactStatus(
    "https://shop.example.com/",
    {
      fetchImpl,
      dnsResolver: publicDns,
      serverOwnedOrigins,
      now: () => new Date("2026-07-28T20:01:00.000Z"),
    },
  );
  assertFalse(result.release.documentValid);
  assert(result.release.invalidReasons.includes("dirty_or_unknown_build"));
  assert(result.robots.rootDisallowDirectivePresent);
  assertFalse(result.robots.documentValid);
  assertFalse(result.summary.allDocumentsValid);
});

Deno.test("Merchant account fails closed unless its explicit tenant owner matches", () => {
  const previousAccount = Deno.env.get("GOOGLE_MERCHANT_ACCOUNT_ID");
  const previousOwner = Deno.env.get("GOOGLE_MERCHANT_TENANT_ID");
  try {
    Deno.env.set("GOOGLE_MERCHANT_ACCOUNT_ID", "123456");
    Deno.env.delete("GOOGLE_MERCHANT_TENANT_ID");
    assertFalse(
      merchantIntegrationForTenant(
        "5443b130-cc28-45af-a420-cd500b288890",
      ).configured,
    );

    Deno.env.set(
      "GOOGLE_MERCHANT_TENANT_ID",
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    );
    assertFalse(
      merchantIntegrationForTenant(
        "5443b130-cc28-45af-a420-cd500b288890",
      ).configured,
    );

    Deno.env.set(
      "GOOGLE_MERCHANT_TENANT_ID",
      "5443b130-cc28-45af-a420-cd500b288890",
    );
    assert(
      merchantIntegrationForTenant(
        "5443b130-cc28-45af-a420-cd500b288890",
      ).configured,
    );
  } finally {
    if (previousAccount === undefined) {
      Deno.env.delete("GOOGLE_MERCHANT_ACCOUNT_ID");
    } else {
      Deno.env.set("GOOGLE_MERCHANT_ACCOUNT_ID", previousAccount);
    }
    if (previousOwner === undefined) {
      Deno.env.delete("GOOGLE_MERCHANT_TENANT_ID");
    } else {
      Deno.env.set("GOOGLE_MERCHANT_TENANT_ID", previousOwner);
    }
  }
});

Deno.test("Merchant refresh has per-operation request, deadline, rate, and concurrency bounds", () => {
  const budget = createNetworkBudget(10_000, 2);
  assert(claimNetworkBudget(budget) > 0);
  assert(claimNetworkBudget(budget) > 0);
  assertThrows(
    () => claimNetworkBudget(budget),
    Error,
    "request budget exhausted",
  );
  assertThrows(
    () => claimNetworkBudget(createNetworkBudget(-1, 1)),
    Error,
    "deadline exceeded",
  );

  const tenantId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const releaseFirst = beginMerchantRefresh(tenantId);
  assertThrows(
    () => beginMerchantRefresh(tenantId),
    Error,
    "already running",
  );
  releaseFirst();
  beginMerchantRefresh(tenantId)();
  beginMerchantRefresh(tenantId)();
  assertThrows(
    () => beginMerchantRefresh(tenantId),
    Error,
    "rate limit",
  );
});

Deno.test("Merchant refresh uses the durable database lease contract", async () => {
  const tenantId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const leaseToken = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  const leaseFence = 7;
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const invoke = (
    name: string,
    args: Record<string, unknown>,
  ) => {
    calls.push({ name, args });
    return Promise.resolve({
      data: name.startsWith("acquire")
        ? {
          acquired: true,
          lease_token: leaseToken,
          lease_fence: leaseFence,
        }
        : name.startsWith("renew")
        ? {
          renewed: true,
          lease_token: leaseToken,
          lease_fence: leaseFence,
        }
        : true,
      error: null,
    });
  };

  assertEquals(
    await acquireDurableMerchantRefreshLease(tenantId, invoke),
    { token: leaseToken, fence: leaseFence },
  );
  assert(
    await renewDurableMerchantRefreshLease(
      tenantId,
      { token: leaseToken, fence: leaseFence },
      invoke,
    ),
  );
  assert(
    await releaseDurableMerchantRefreshLease(
      tenantId,
      { token: leaseToken, fence: leaseFence },
      invoke,
    ),
  );
  assertEquals(calls, [
    {
      name: "acquire_google_merchant_refresh_lease",
      args: { p_tenant_id: tenantId },
    },
    {
      name: "renew_google_merchant_refresh_lease",
      args: {
        p_tenant_id: tenantId,
        p_lease_token: leaseToken,
        p_lease_fence: leaseFence,
      },
    },
    {
      name: "release_google_merchant_refresh_lease",
      args: {
        p_tenant_id: tenantId,
        p_lease_token: leaseToken,
        p_lease_fence: leaseFence,
      },
    },
  ]);

  await assertRejects(
    () =>
      acquireDurableMerchantRefreshLease(
        tenantId,
        () =>
          Promise.resolve({
            data: { acquired: false, reason: "active" },
            error: null,
          }),
      ),
    Error,
    "already running",
  );
  await assertRejects(
    () =>
      acquireDurableMerchantRefreshLease(
        tenantId,
        () =>
          Promise.resolve({
            data: { acquired: false, reason: "rate_limited" },
            error: null,
          }),
      ),
    Error,
    "rate limit",
  );
});

Deno.test("reserved IP classifier covers public and private address families", () => {
  assert(
    storeArtifactDnsSafetyBoundary.includes(
      "cannot pin a preflight DNS answer",
    ),
  );
  assert(
    storeArtifactDnsSafetyBoundary.includes("operator-owned egress proxy"),
  );
  for (
    const address of [
      "0.0.0.0",
      "100.127.255.255",
      "127.0.0.1",
      "192.168.1.2",
      "198.51.100.8",
      "240.0.0.1",
      "255.255.255.255",
      "::",
      "::1",
      "0:0:0:0:0:0:0:1",
      "::ffff:10.0.0.1",
      "0:0:0:0:0:ffff:7f00:1",
      "0:0:0:0:ffff:0:7f00:1",
      "::127.0.0.1",
      "64:ff9b::7f00:1",
      "100::1",
      "2001:db8::1",
      "2002:7f00:1::",
      "FC00::1",
      "fdff:ffff::1",
      "fe80:0:0:0:0:0:0:1",
      "fec0::1",
      "ff02::1",
      "1fff::1",
      "4000::1",
      "8000::1",
      "invalid-address",
    ]
  ) {
    assert(isPrivateOrReservedIp(address), address);
  }
  for (
    const address of [
      "8.8.8.8",
      "93.184.216.34",
      "::ffff:8.8.8.8",
      "::8.8.8.8",
      "2001:4860:4860::8888",
      "2606:2800:220:1:248:1893:25c8:1946",
    ]
  ) {
    assertFalse(isPrivateOrReservedIp(address), address);
  }
});
