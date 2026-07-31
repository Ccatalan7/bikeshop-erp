import {
  handleStorefrontPublicationDispatcher,
  StorefrontPublicationDispatcherDependencies,
  StorefrontPublicationRpcClient,
} from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const requestId = "11111111-1111-4111-8111-111111111111";
const attemptId = "22222222-2222-4222-8222-222222222222";
const leaseToken = "33333333-3333-4333-8333-333333333333";
const workerSecret = "storefront-worker-test-secret";

type RecordedRpc = {
  name: string;
  params: Record<string, unknown>;
};

function testHarness(options: {
  claim?: unknown[];
  githubDispatch?: () => Promise<Response>;
  githubRuns?: () => Promise<Response>;
  tokenResponse?: Response;
  omitEnv?: string;
}) {
  const rpcs: RecordedRpc[] = [];
  const fetches: Array<{ url: string; init?: RequestInit }> = [];
  const claim = options.claim ?? [{
    claim_action: "dispatch",
    request_id: requestId,
    attempt_id: attemptId,
    tenant_id: "5443b130-cc28-45af-a420-cd500b288890",
    target_key: "vinabike-store",
    lease_token: leaseToken,
    lease_fence: 7,
  }];
  const client: StorefrontPublicationRpcClient = {
    rpc(name, params) {
      rpcs.push({ name, params });
      if (name === "claim_storefront_publication_requests") {
        return Promise.resolve({ data: claim, error: null });
      }
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  const env: Record<string, string> = {
    STOREFRONT_PUBLICATION_DISPATCH_SECRET: workerSecret,
    SUPABASE_URL: "https://project.example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-test",
    STOREFRONT_PUBLICATION_GITHUB_APP_ID: "12345",
    STOREFRONT_PUBLICATION_GITHUB_INSTALLATION_ID: "67890",
    STOREFRONT_PUBLICATION_GITHUB_PRIVATE_KEY: "private-key-test",
  };
  if (options.omitEnv) delete env[options.omitEnv];

  const dependencies: Partial<StorefrontPublicationDispatcherDependencies> = {
    env: (name) => env[name] ?? "",
    rpcClient: () => client,
    randomUUID: () => "44444444-4444-4444-8444-444444444444",
    createAppJwt: async () => "app-jwt-test",
    fetch: async (input, init) => {
      const url = String(input);
      fetches.push({ url, init });
      if (url.includes("/access_tokens")) {
        return options.tokenResponse ??
          new Response(JSON.stringify({ token: "installation-token-test" }), {
            status: 201,
            headers: { "Content-Type": "application/json" },
          });
      }
      if (url.includes(`/actions/workflows/firebase-hosting-store.yml/runs?`)) {
        return options.githubRuns
          ? await options.githubRuns()
          : new Response(JSON.stringify({ workflow_runs: [] }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          });
      }
      if (options.githubDispatch) return await options.githubDispatch();
      return new Response(null, { status: 204 });
    },
  };
  return { dependencies, rpcs, fetches };
}

function tickRequest(options: {
  secret?: string;
  body?: unknown;
  method?: string;
} = {}) {
  return new Request(
    "https://project.example.supabase.co/functions/v1/dispatch-storefront-publication",
    {
      method: options.method ?? "POST",
      headers: {
        "Content-Type": "application/json",
        ...(options.secret === null ? {} : {
          "x-storefront-publication-dispatch-secret": options.secret ?? workerSecret,
        }),
      },
      body: (options.method ?? "POST") === "POST"
        ? JSON.stringify(options.body ?? { action: "tick" })
        : undefined,
    },
  );
}

Deno.test("dispatcher rejects non-POST and missing dedicated secret", async () => {
  const harness = testHarness({});
  const wrongMethod = await handleStorefrontPublicationDispatcher(
    tickRequest({ method: "GET" }),
    harness.dependencies,
  );
  assert(wrongMethod.status === 405, "GET was accepted");

  const unauthorized = await handleStorefrontPublicationDispatcher(
    tickRequest({ secret: null as unknown as string }),
    harness.dependencies,
  );
  assert(unauthorized.status === 401, "missing worker secret was accepted");
  assert(harness.rpcs.length === 0, "unauthorized request reached the database");
});

Deno.test("dispatcher accepts only the exact tick body", async () => {
  const harness = testHarness({});
  const response = await handleStorefrontPublicationDispatcher(
    tickRequest({ body: { action: "tick", tenant_id: "attacker-controlled" } }),
    harness.dependencies,
  );
  assert(response.status === 400, "caller-controlled target data was accepted");
  assert(harness.rpcs.length === 0, "invalid body reached the database");
});

Deno.test("missing GitHub configuration fails before claiming work", async () => {
  const harness = testHarness({
    omitEnv: "STOREFRONT_PUBLICATION_GITHUB_PRIVATE_KEY",
  });
  const response = await handleStorefrontPublicationDispatcher(
    tickRequest(),
    harness.dependencies,
  );
  assert(response.status === 503, "missing GitHub configuration was accepted");
  assert(harness.rpcs.length === 0, "work was claimed before configuration check");
});

Deno.test("no claim performs no GitHub request", async () => {
  const harness = testHarness({ claim: [] });
  const response = await handleStorefrontPublicationDispatcher(
    tickRequest(),
    harness.dependencies,
  );
  const body = await response.json();
  assert(response.status === 200 && body.claimed === 0, "idle tick was not honest");
  assert(harness.fetches.length === 0, "idle tick called GitHub");
});

Deno.test("204 dispatch sends only fixed ref and opaque request id", async () => {
  const harness = testHarness({});
  const response = await handleStorefrontPublicationDispatcher(
    tickRequest(),
    harness.dependencies,
  );
  const body = await response.json();
  assert(body.outcome === "dispatched", "204 was not recorded as dispatched");
  assert(harness.fetches.length === 2, "unexpected GitHub request count");
  const dispatch = harness.fetches[1];
  assert(
    dispatch.url.endsWith(
      "/repos/Ccatalan7/bikeshop-erp/actions/workflows/firebase-hosting-store.yml/dispatches",
    ),
    "workflow target was not fixed server-side",
  );
  const payload = JSON.parse(String(dispatch.init?.body));
  assert(payload.ref === "main", "workflow ref was not fixed");
  assert(
    JSON.stringify(payload.inputs) === JSON.stringify({ request_id: requestId }),
    "workflow inputs contained more than request_id",
  );
  const completion = harness.rpcs.at(-1);
  assert(
    completion?.name === "complete_storefront_publication_dispatch" &&
      completion.params.p_outcome === "dispatched",
    "database did not record the acknowledged dispatch",
  );
});

Deno.test("ambiguous dispatch transport failure is never retried blindly", async () => {
  const harness = testHarness({
    githubDispatch: () => Promise.reject(new Error("network timeout")),
  });
  const response = await handleStorefrontPublicationDispatcher(
    tickRequest(),
    harness.dependencies,
  );
  const body = await response.json();
  assert(body.outcome === "dispatch_unknown", "timeout was treated as a safe retry");
  assert(
    harness.rpcs.at(-1)?.params.p_outcome === "dispatch_unknown",
    "ambiguous outcome was not persisted",
  );
});

Deno.test("reconciliation recognizes an exact run and never redispatches", async () => {
  const harness = testHarness({
    claim: [{
      claim_action: "reconcile",
      request_id: requestId,
      attempt_id: attemptId,
      lease_token: leaseToken,
      lease_fence: 7,
    }],
    githubRuns: async () =>
      new Response(
        JSON.stringify({
          workflow_runs: [{
            id: 9876,
            display_title: `Storefront publication · ${requestId}`,
            event: "workflow_dispatch",
            head_branch: "main",
          }],
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      ),
  });

  const response = await handleStorefrontPublicationDispatcher(
    tickRequest(),
    harness.dependencies,
  );
  const body = await response.json();
  assert(
    body.outcome === "dispatched" && body.reconciled === true,
    "exact run was not reconciled",
  );
  assert(harness.fetches.length === 2, "reconcile made an extra GitHub request");
  assert(
    harness.fetches[1].init?.method === "GET",
    "reconcile called workflow_dispatch",
  );
  assert(
    harness.rpcs.at(-1)?.params.p_outcome === "dispatched",
    "reconciled dispatch was not acknowledged",
  );
});

Deno.test("inconclusive reconciliation stays unknown and never redispatches", async () => {
  const harness = testHarness({
    claim: [{
      claim_action: "reconcile",
      request_id: requestId,
      attempt_id: attemptId,
      lease_token: leaseToken,
      lease_fence: 7,
    }],
    githubRuns: async () =>
      new Response(JSON.stringify({ workflow_runs: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
  });

  const response = await handleStorefrontPublicationDispatcher(
    tickRequest(),
    harness.dependencies,
  );
  const body = await response.json();
  assert(
    body.outcome === "dispatch_unknown" && body.reconciled === false,
    "absence was treated as authoritative rejection",
  );
  assert(harness.fetches.length === 2, "reconcile made an extra GitHub request");
  assert(
    harness.fetches[1].init?.method === "GET",
    "inconclusive reconcile called workflow_dispatch",
  );
  const completion = harness.rpcs.at(-1);
  assert(
    completion?.params.p_outcome === "dispatch_unknown" &&
      completion.params.p_retry_after_seconds === 300,
    "inconclusive reconcile did not preserve ambiguity",
  );
});

Deno.test("GitHub 5xx retries while 422 is permanent", async () => {
  const retryHarness = testHarness({
    githubDispatch: async () =>
      new Response("temporary", {
        status: 503,
        headers: { "Retry-After": "17" },
      }),
  });
  await handleStorefrontPublicationDispatcher(
    tickRequest(),
    retryHarness.dependencies,
  );
  assert(
    retryHarness.rpcs.at(-1)?.params.p_outcome === "retry" &&
      retryHarness.rpcs.at(-1)?.params.p_retry_after_seconds === 17,
    "5xx retry classification was incorrect",
  );

  const permanentHarness = testHarness({
    githubDispatch: async () => new Response("invalid", { status: 422 }),
  });
  await handleStorefrontPublicationDispatcher(
    tickRequest(),
    permanentHarness.dependencies,
  );
  assert(
    permanentHarness.rpcs.at(-1)?.params.p_outcome === "permanent_failure",
    "422 was not treated as permanent configuration failure",
  );
});

Deno.test("foreign or malformed claim identity stops before GitHub", async () => {
  const harness = testHarness({
    claim: [{
      claim_action: "dispatch",
      request_id: requestId,
      attempt_id: attemptId,
      tenant_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      target_key: "foreign-store",
      lease_token: leaseToken,
      lease_fence: 1,
    }],
  });
  const response = await handleStorefrontPublicationDispatcher(
    tickRequest(),
    harness.dependencies,
  );
  assert(response.status === 500, "foreign claim identity was accepted");
  assert(harness.fetches.length === 0, "foreign claim reached GitHub");
});
