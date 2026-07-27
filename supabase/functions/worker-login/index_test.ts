import {
  buildWorkerLoginRuntime,
  handler,
  isAllowedCorsOrigin,
  type WorkerLoginRuntime,
} from "./index.ts";

const workerEmail = "wp-2222222222-bWVjYW5pY28@worker-login.invalid";
const validPassword = "CorrectHorse!9";
const invalidResponse = {
  success: false,
  error: "Credenciales inválidas",
  code: "invalid_credentials",
};

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown, message: string) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(
      `${message}: expected ${expectedJson}, received ${actualJson}`,
    );
  }
}

interface Evidence {
  resolutions: Array<{ tenant: string; username: string }>;
  signIns: Array<{ email: string; password: string }>;
}

function createRuntime(
  evidence: Evidence,
  options: {
    resolvedEmail?: string | null;
    acceptedPassword?: string;
  } = {},
): WorkerLoginRuntime {
  return {
    resolveLoginEmail: (tenant, username) => {
      evidence.resolutions.push({ tenant, username });
      return Promise.resolve(
        options.resolvedEmail === undefined ? workerEmail : options.resolvedEmail,
      );
    },
    signInWithPassword: (email, password) => {
      evidence.signIns.push({ email, password });
      if (
        email === workerEmail &&
        password === (options.acceptedPassword ?? validPassword)
      ) {
        return Promise.resolve({ refreshToken: "refresh-session-fixture" });
      }
      return Promise.resolve(null);
    },
  };
}

function loginRequest(
  body: Record<string, unknown>,
  origin = "https://project-vinabike.web.app",
) {
  return new Request("https://example.supabase.co/functions/v1/worker-login", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin,
    },
    body: JSON.stringify(body),
  });
}

Deno.test("valid worker credentials return only a refresh session capability", async () => {
  const evidence: Evidence = { resolutions: [], signIns: [] };
  const response = await handler(
    loginRequest({
      tenant: " vinabike ",
      username: " Mecanico ",
      password: validPassword,
    }),
    {
      runtime: createRuntime(evidence),
      allowedOrigins: [],
    },
  );
  const responseText = await response.text();

  assertEquals(response.status, 200, "valid credentials succeed");
  assertEquals(
    JSON.parse(responseText),
    { success: true, refreshToken: "refresh-session-fixture" },
    "response contract contains no email, user record or access token",
  );
  assertEquals(
    evidence.resolutions,
    [{ tenant: "vinabike", username: "mecanico" }],
    "bounded normalized identifiers reach only the server-side resolver",
  );
  assertEquals(
    evidence.signIns,
    [{ email: workerEmail, password: validPassword }],
    "the resolved synthetic email never leaves the function",
  );
  assert(!responseText.includes(workerEmail), "worker email cannot reach the response");
  assert(!responseText.includes(validPassword), "password cannot reach the response");
});

Deno.test("legacy registrable worker-login domains fail closed", async () => {
  const evidence: Evidence = { resolutions: [], signIns: [] };
  const response = await handler(
    loginRequest({
      tenant: "vinabike",
      username: "mecanico",
      password: validPassword,
    }),
    {
      runtime: createRuntime(evidence, {
        resolvedEmail: "wp-2222222222-bWVjYW5pY28@worker-login.vinabike.app",
      }),
      allowedOrigins: [],
    },
  );

  assertEquals(response.status, 401, "legacy worker login is rejected");
  assertEquals(
    evidence.signIns[0]?.email,
    "no-account@worker.invalid",
    "a legacy registrable domain must never reach the real password grant",
  );
});

Deno.test("unknown worker and wrong password are response-identical", async () => {
  const unknownEvidence: Evidence = { resolutions: [], signIns: [] };
  const unknown = await handler(
    loginRequest({
      tenant: "vinabike",
      username: "no-existe",
      password: validPassword,
    }),
    {
      runtime: createRuntime(unknownEvidence, { resolvedEmail: null }),
      allowedOrigins: [],
    },
  );
  const unknownBody = await unknown.text();

  const wrongPasswordEvidence: Evidence = { resolutions: [], signIns: [] };
  const wrongPassword = await handler(
    loginRequest({
      tenant: "vinabike",
      username: "mecanico",
      password: "WrongPassword!9",
    }),
    {
      runtime: createRuntime(wrongPasswordEvidence),
      allowedOrigins: [],
    },
  );
  const wrongPasswordBody = await wrongPassword.text();

  assertEquals(unknown.status, 401, "unknown worker is unauthorized");
  assertEquals(wrongPassword.status, 401, "wrong password is unauthorized");
  assertEquals(unknownBody, wrongPasswordBody, "credential failures are indistinguishable");
  assertEquals(JSON.parse(unknownBody), invalidResponse, "stable generic error");
  assertEquals(
    unknownEvidence.signIns[0]?.email,
    "no-account@worker.invalid",
    "unknown users still execute the provider password grant with a dummy identity",
  );
});

Deno.test("malformed and oversized credentials return the same generic 401", async () => {
  const evidence: Evidence = { resolutions: [], signIns: [] };
  const malformed = await handler(
    loginRequest({
      tenant: "vinabike",
      username: "x",
      password: "",
    }),
    {
      runtime: createRuntime(evidence),
      allowedOrigins: [],
    },
  );
  assertEquals(malformed.status, 401, "malformed credentials are unauthorized");
  assertEquals(await malformed.json(), invalidResponse, "malformed error is generic");
  assertEquals(evidence.resolutions, [], "invalid payload cannot reach the resolver");

  const oversized = await handler(
    loginRequest({
      tenant: "vinabike",
      username: "mecanico",
      password: "x".repeat(300),
    }),
    {
      runtime: createRuntime(evidence),
      allowedOrigins: [],
    },
  );
  assertEquals(oversized.status, 401, "oversized credentials are unauthorized");
  assertEquals(await oversized.json(), invalidResponse, "oversized error is generic");
});

Deno.test("worker login CORS is exact and rejects arbitrary browser origins", async () => {
  assertEquals(
    isAllowedCorsOrigin("https://project-vinabike--security-test.web.app", []),
    true,
    "owned Firebase preview is allowed",
  );
  assertEquals(
    isAllowedCorsOrigin("https://attacker.example", []),
    false,
    "arbitrary origin is rejected",
  );

  const evidence: Evidence = { resolutions: [], signIns: [] };
  const response = await handler(
    loginRequest({
      tenant: "vinabike",
      username: "mecanico",
      password: validPassword,
    }, "https://attacker.example"),
    {
      runtime: createRuntime(evidence),
      allowedOrigins: [],
    },
  );

  assertEquals(response.status, 403, "unknown origin fails before credential handling");
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    null,
    "rejected origin receives no CORS access",
  );
  assertEquals(evidence.resolutions, [], "rejected browser cannot reach the resolver");

  const preflight = await handler(
    new Request("https://example.supabase.co/functions/v1/worker-login", {
      method: "OPTIONS",
      headers: {
        origin: "https://project-vinabike.web.app",
        authorization: "Bearer ignored-by-public-handler",
      },
    }),
    { runtime: createRuntime(evidence), allowedOrigins: [] },
  );
  assertEquals(preflight.status, 204, "owned origin receives a preflight response");
  assertEquals(
    preflight.headers.get("access-control-allow-headers"),
    "authorization, x-client-info, apikey, content-type",
    "Supabase invoke headers are explicitly allowed",
  );
});

Deno.test("worker login separates service-role resolution from anon password grant", async () => {
  const calls: string[] = [];
  const resolverClient = {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push(`service:${name}:${JSON.stringify(args)}`);
      return Promise.resolve({ data: workerEmail, error: null });
    },
  };
  const authClient = {
    auth: {
      signInWithPassword(input: Record<string, unknown>) {
        calls.push(`anon:password:${JSON.stringify(input)}`);
        return Promise.resolve({
          data: { session: { refresh_token: "refresh-session-fixture" } },
          error: null,
        });
      },
    },
  };
  const runtime = buildWorkerLoginRuntime(resolverClient, authClient);

  assertEquals(
    await runtime.resolveLoginEmail("tenant-slug", "worker-name"),
    workerEmail,
    "service-role resolver returns the private synthetic identity",
  );
  assertEquals(
    await runtime.signInWithPassword(workerEmail, validPassword),
    { refreshToken: "refresh-session-fixture" },
    "anon client alone performs the password grant",
  );
  assertEquals(
    calls,
    [
      'service:resolve_worker_login:{"p_tenant":"tenant-slug","p_username":"worker-name"}',
      `anon:password:${
        JSON.stringify({
          email: workerEmail,
          password: validPassword,
        })
      }`,
    ],
    "each client receives only its intended operation",
  );
});

Deno.test("worker login production keys are separated and logging stays empty", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(
    source.includes('"SUPABASE_ANON_KEY"'),
    "the public password grant uses the anon project key",
  );
  assert(
    source.includes('"SUPABASE_SERVICE_ROLE_KEY"'),
    "only the private resolver loads service-role authority",
  );
  const productionRuntime = source.slice(
    source.indexOf("function createProductionRuntime"),
    source.indexOf("export function buildWorkerLoginRuntime"),
  );
  assert(
    productionRuntime.includes(
      "createClient(\n    supabaseUrl,\n    serviceRoleKey,",
    ) &&
      productionRuntime.includes(
        "createClient(supabaseUrl, anonKey, clientOptions)",
      ),
    "production constructs distinct service-role and anon clients",
  );
  const runtimeBuilder = source.slice(
    source.indexOf("export function buildWorkerLoginRuntime"),
    source.indexOf("function extractResolvedEmail"),
  );
  assert(
    runtimeBuilder.includes('resolverClient.rpc("resolve_worker_login"') &&
      runtimeBuilder.includes("authClient.auth.signInWithPassword"),
    "resolver and password grant cannot share a client",
  );
  assert(
    !source.includes("console."),
    "worker login cannot log credentials, identifiers or provider errors",
  );
  assert(
    !source.includes('req.headers.get("authorization")') &&
      !source.includes("req.headers.get('authorization')"),
    "the public handler ignores caller bearer credentials",
  );
});
