import {
  authenticateCaller,
  generateInvitationToken,
  handler,
  hashInvitationToken,
  isAllowedCorsOrigin,
  type SendInvitationRuntime,
} from "./index.ts";

const invitationId = "11111111-1111-4111-8111-111111111111";
const tenantId = "22222222-2222-4222-8222-222222222222";
const callerId = "33333333-3333-4333-8333-333333333333";
const fixedToken = "abcdefghijklmnopqrstuvwxyzABCDEFGH012345678";

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

async function assertRejectsCode(
  callback: () => Promise<unknown>,
  expectedCode: string,
  message: string,
) {
  try {
    await callback();
  } catch (error) {
    const code = error && typeof error === "object"
      ? (error as Record<string, unknown>).code
      : null;
    assertEquals(code, expectedCode, message);
    return;
  }
  throw new Error(`${message}: expected promise to reject`);
}

function callerAuthClients(input: {
  profileRows?: unknown[];
  profileError?: unknown;
}) {
  const evidence: {
    select: string | null;
    filters: Array<[string, unknown]>;
  } = { select: null, filters: [] };
  const userClient = {
    auth: {
      getUser: () =>
        Promise.resolve({
          data: { user: { id: callerId } },
          error: null,
        }),
    },
  };
  const serviceClient = {
    from: (table: string) => {
      if (table !== "user_profiles") {
        throw new Error(`unexpected table: ${table}`);
      }
      const query = {
        select: (columns: string) => {
          evidence.select = columns;
          return query;
        },
        eq: (column: string, value: unknown) => {
          evidence.filters.push([column, value]);
          return query;
        },
        limit: (_count: number) =>
          Promise.resolve({
            data: input.profileRows ?? [],
            error: input.profileError ?? null,
          }),
      };
      return query;
    },
  };
  return { userClient, serviceClient, evidence };
}

interface RuntimeEvidence {
  loadedTenantIds: string[];
  rotations: Array<Record<string, string>>;
  emails: Array<{ to: string; subject: string; html: string; text: string }>;
}

function createRuntime(
  evidence: RuntimeEvidence,
  overrides: {
    invitationFound?: boolean;
    emailSent?: boolean;
  } = {},
): SendInvitationRuntime {
  return {
    authenticate: () => Promise.resolve({ userId: callerId, tenantId }),
    loadInvitation: (_requestedInvitationId, requestedTenantId) => {
      evidence.loadedTenantIds.push(requestedTenantId);
      if (overrides.invitationFound === false) return Promise.resolve(null);
      return Promise.resolve({
        id: invitationId,
        email: "invitee@example.invalid",
        role: "manager",
        tenant_id: tenantId,
        metadata: { first_name: "Invitada" },
        tenants: { shop_name: "Tienda Segura" },
      });
    },
    rotateInvitationToken: (input) => {
      evidence.rotations.push({ ...input });
      return Promise.resolve(true);
    },
    sendEmail: (email) => {
      evidence.emails.push(email);
      return Promise.resolve(overrides.emailSent !== false);
    },
    invitationBaseUrl: () => "https://project-vinabike.web.app",
    now: () => new Date("2026-07-26T12:00:00.000Z"),
    generateToken: () => fixedToken,
  };
}

function invitationRequest(origin = "https://project-vinabike.web.app") {
  return new Request("https://example.supabase.co/functions/v1/send-invitation", {
    method: "POST",
    headers: {
      authorization: "Bearer user-jwt-fixture",
      "content-type": "application/json",
      origin,
    },
    body: JSON.stringify({ invitationId }),
  });
}

Deno.test("invitation caller authorization joins one matching active tenant", async () => {
  const { userClient, serviceClient, evidence } = callerAuthClients({
    profileRows: [{
      tenant_id: tenantId,
      role: "manager",
      permissions: {},
      tenants: { id: tenantId, is_active: true },
    }],
  });

  assertEquals(
    await authenticateCaller(userClient, serviceClient),
    { userId: callerId, tenantId },
    "active manager requires its matching active tenant",
  );
  assertEquals(
    evidence,
    {
      select: "tenant_id, role, permissions, tenants!inner(id, is_active)",
      filters: [
        ["user_id", callerId],
        ["is_active", true],
        ["tenants.is_active", true],
      ],
    },
    "profile and tenant activity are checked in one joined authorization query",
  );
});

Deno.test("invitation caller rejects an inactive tenant", async () => {
  const { userClient, serviceClient } = callerAuthClients({
    profileRows: [{
      tenant_id: tenantId,
      role: "manager",
      permissions: {},
      tenants: { id: tenantId, is_active: false },
    }],
  });

  await assertRejectsCode(
    () => authenticateCaller(userClient, serviceClient),
    "tenant_context_invalid",
    "a suspended tenant cannot rotate or email invitation capabilities",
  );
});

Deno.test("invitation caller rejects a missing joined tenant row", async () => {
  const { userClient, serviceClient } = callerAuthClients({
    profileRows: [{
      tenant_id: tenantId,
      role: "manager",
      permissions: {},
      tenants: null,
    }],
  });

  await assertRejectsCode(
    () => authenticateCaller(userClient, serviceClient),
    "tenant_context_invalid",
    "an orphaned profile cannot deliver invitations",
  );
});

Deno.test("invitation caller fails closed when active tenant lookup errors", async () => {
  const { userClient, serviceClient } = callerAuthClients({
    profileError: { code: "XX000", message: "lookup unavailable" },
  });

  await assertRejectsCode(
    () => authenticateCaller(userClient, serviceClient),
    "authorization_unavailable",
    "tenant lookup errors cannot reach invitation service-role operations",
  );
});

Deno.test("invitation token uses 256 random bits and SHA-256 hex storage", async () => {
  const first = generateInvitationToken();
  const second = generateInvitationToken();

  assert(/^[A-Za-z0-9_-]{43}$/.test(first), "token must be 32-byte base64url");
  assert(first !== second, "independent tokens must not repeat");
  assert(
    /^[0-9a-f]{64}$/.test(await hashInvitationToken(first)),
    "stored verifier must be SHA-256 hex",
  );
});

Deno.test("authorized delivery rotates only the hash and never returns the capability", async () => {
  const evidence: RuntimeEvidence = {
    loadedTenantIds: [],
    rotations: [],
    emails: [],
  };
  const response = await handler(invitationRequest(), {
    runtime: createRuntime(evidence),
    allowedOrigins: [],
  });
  const responseText = await response.text();
  const payload = JSON.parse(responseText);

  assertEquals(response.status, 200, "delivery should succeed");
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    "https://project-vinabike.web.app",
    "known browser origin must be echoed exactly",
  );
  assertEquals(evidence.loadedTenantIds, [tenantId], "lookup must use caller tenant");
  assertEquals(evidence.rotations.length, 1, "token must rotate once");
  assertEquals(evidence.rotations[0].tenantId, tenantId, "RPC must receive caller tenant");
  assertEquals(
    evidence.rotations[0].tokenHash,
    await hashInvitationToken(fixedToken),
    "RPC must receive only the token hash",
  );
  assert(evidence.rotations[0].tokenHash !== fixedToken, "plain token cannot reach storage");
  assertEquals(evidence.emails.length, 1, "one email must be attempted");
  assert(evidence.emails[0].html.includes(fixedToken), "only email CTA receives plain token");
  assert(
    evidence.emails[0].html.includes(
      `/accept-invitation.html#token=${fixedToken}`,
    ),
    "email CTA must keep the token in the URL fragment",
  );
  assert(
    !evidence.emails[0].html.includes("?token=") &&
      !evidence.emails[0].text.includes("?token="),
    "capability token cannot appear in a query string",
  );
  assertEquals(payload.emailSent, true, "response must report delivery");
  assert(!responseText.includes(fixedToken), "response cannot expose the token");
  assert(!responseText.includes("invitee@example.invalid"), "response cannot expose email");
  assert(!responseText.includes("invitationLink"), "response cannot expose a link field");
});

Deno.test("unknown or cross-tenant invitation fails closed before rotation", async () => {
  const evidence: RuntimeEvidence = {
    loadedTenantIds: [],
    rotations: [],
    emails: [],
  };
  const response = await handler(invitationRequest(), {
    runtime: createRuntime(evidence, { invitationFound: false }),
    allowedOrigins: [],
  });

  assertEquals(response.status, 404, "unknown tenant-scoped invitation must be hidden");
  assertEquals(evidence.loadedTenantIds, [tenantId], "lookup must stay tenant-scoped");
  assertEquals(evidence.rotations, [], "hidden invitation cannot rotate");
  assertEquals(evidence.emails, [], "hidden invitation cannot send email");
});

Deno.test("missing caller JWT is rejected before any tenant or invitation lookup", async () => {
  const evidence: RuntimeEvidence = {
    loadedTenantIds: [],
    rotations: [],
    emails: [],
  };
  const response = await handler(
    new Request("https://example.supabase.co/functions/v1/send-invitation", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        origin: "https://project-vinabike.web.app",
      },
      body: JSON.stringify({ invitationId }),
    }),
    {
      runtime: createRuntime(evidence),
      allowedOrigins: [],
    },
  );

  assertEquals(response.status, 401, "missing JWT must be unauthorized");
  assertEquals(evidence.loadedTenantIds, [], "unauthenticated request cannot read invitations");
});

Deno.test("CORS echoes known origins and rejects arbitrary browser origins", async () => {
  assertEquals(
    isAllowedCorsOrigin("https://project-vinabike--preview-123.web.app", []),
    true,
    "owned Firebase previews should be accepted",
  );
  assertEquals(
    isAllowedCorsOrigin("https://attacker.example", []),
    false,
    "arbitrary origins must be rejected",
  );

  const evidence: RuntimeEvidence = {
    loadedTenantIds: [],
    rotations: [],
    emails: [],
  };
  const rejected = await handler(invitationRequest("https://attacker.example"), {
    runtime: createRuntime(evidence),
    allowedOrigins: [],
  });
  assertEquals(rejected.status, 403, "unknown origin must fail before auth/data access");
  assertEquals(
    rejected.headers.get("access-control-allow-origin"),
    null,
    "rejected origin cannot receive CORS access",
  );
  assertEquals(evidence.loadedTenantIds, [], "rejected origin cannot query invitations");
});

Deno.test("provider failures expose no provider body, token, email or link", async () => {
  const evidence: RuntimeEvidence = {
    loadedTenantIds: [],
    rotations: [],
    emails: [],
  };
  const response = await handler(invitationRequest(), {
    runtime: createRuntime(evidence, { emailSent: false }),
    allowedOrigins: [],
  });
  const responseText = await response.text();

  assertEquals(response.status, 502, "provider failure must be a failed request");
  assert(!responseText.includes(fixedToken), "failure response cannot expose token");
  assert(!responseText.includes("invitee@example.invalid"), "failure response cannot expose email");
  assert(!responseText.includes("http"), "failure response cannot expose a link");
});

Deno.test("rotation cooldown returns 429 and discards the unsaved token", async () => {
  const evidence: RuntimeEvidence = {
    loadedTenantIds: [],
    rotations: [],
    emails: [],
  };
  const runtime = createRuntime(evidence);
  runtime.rotateInvitationToken = (input) => {
    evidence.rotations.push({ ...input });
    return Promise.reject({
      code: "55000",
      message: "Invitation token rotation is rate limited",
    });
  };

  const response = await handler(invitationRequest(), {
    runtime,
    allowedOrigins: [],
  });
  const responseText = await response.text();
  const payload = JSON.parse(responseText);

  assertEquals(response.status, 429, "cooldown must be a retryable client response");
  assertEquals(payload.code, "invitation_rate_limited", "cooldown code");
  assertEquals(evidence.rotations.length, 1, "rotation is attempted only once");
  assertEquals(evidence.emails, [], "a rejected token can never be emailed");
  assert(!responseText.includes(fixedToken), "discarded token cannot reach the response");
});
