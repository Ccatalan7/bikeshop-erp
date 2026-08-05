import {
  accessEmailRedirect,
  assertActiveEmployeeForInvitation,
  assertEmployeeLinkTargetAllowed,
  assertInvitationEmailNotActiveStaff,
  assertPendingInvitationInTenant,
  assertPermissionGrantAllowed,
  assertReusableWorkerOrphan,
  assertRoleAssignmentAllowed,
  assertSingleAccountMembership,
  assertStaffTargetMutationAllowed,
  assertStoredInvitationAuthorityAllowed,
  assertUserBelongsToTenant,
  authorizeStaffAssignment,
  beginWorkerPasswordCredentialIssue,
  buildCustomerAuthMetadata,
  buildWorkerAuthMetadata,
  buildWorkerLoginEmail,
  buildWorkerPasswordResetMarker,
  canonicalizeRequestedPermissions,
  checkInternalInvitationIdentity,
  createCustomerAccount,
  createInternalInvitation,
  deactivateAccountPreservingMessagingHistory,
  deleteInternalAccount,
  derivePrincipalOwnerIdentity,
  detachedAccountResult,
  evaluateInvitationIdentity,
  finishWorkerPasswordCredentialIssue,
  getCallerContext,
  getEmployeeAccessStates,
  getMessagingDeletionEvidence,
  getWorkerPortalAccess,
  hasAuthoritativeWorkerIdentity,
  isAllowedCorsOrigin,
  isPublicStoreCustomerForTenant,
  isStrongAdminPassword,
  linkInternalUserEmployee,
  mapEmployeeAccessError,
  mergeWorkerAppMetadata,
  persistNewWorkerPortalAccount,
  preservedMessagingHistoryResult,
  resendCustomerVerification,
  resolveCustomerProvisioningEmail,
  resolveTrustedStoreOrigin,
  revokeWorkerPortalSessions,
  sanitizeWorkerDisplayMetadata,
  selectAccessEmailDelivery,
  sendInvitationEmail,
  setWorkerPortalAccess,
  unlinkInternalUserEmployee,
  updateInternalUser,
} from "./index.ts";

function assertEquals(actual: unknown, expected: unknown, message: string) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(
      `${message}: expected ${expectedJson}, received ${actualJson}`,
    );
  }
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertThrowsCode(
  callback: () => unknown,
  expectedCode: string,
  message: string,
) {
  try {
    callback();
  } catch (error) {
    const code = error && typeof error === "object"
      ? (error as Record<string, unknown>).code
      : null;
    assertEquals(code, expectedCode, message);
    return;
  }
  throw new Error(`${message}: expected function to throw`);
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

interface RecordedUpdate {
  table: string;
  payload: Record<string, unknown>;
  filters: Array<[string, unknown]>;
}

interface RecordedRead {
  table: string;
  filters: Array<[string, unknown]>;
}

function callerContextClients(input: {
  profileRows?: unknown[];
  profileError?: unknown;
  userEmail?: string;
  appMetadata?: Record<string, unknown>;
}) {
  const evidence: {
    accessToken: string | undefined;
    table: string | null;
    select: string | null;
    filters: Array<[string, unknown]>;
    limit: number | null;
  } = {
    accessToken: undefined,
    table: null,
    select: null,
    filters: [],
    limit: null,
  };
  const userClient = {
    auth: {
      getUser: (accessToken?: string) => {
        evidence.accessToken = accessToken;
        return Promise.resolve({
          data: {
            user: {
              id: "11111111-1111-4111-8111-111111111111",
              email: input.userEmail ?? "manager@example.invalid",
              app_metadata: input.appMetadata ?? {},
            },
          },
          error: null,
        });
      },
    },
  };
  const serviceClient = {
    from: (table: string) => {
      evidence.table = table;
      const query = {
        select: (columns: string) => {
          evidence.select = columns;
          return query;
        },
        eq: (column: string, value: unknown) => {
          evidence.filters.push([column, value]);
          return query;
        },
        limit: (count: number) => {
          evidence.limit = count;
          return Promise.resolve({
            data: input.profileRows ?? [],
            error: input.profileError ?? null,
          });
        },
      };
      return query;
    },
  };
  return { userClient, serviceClient, evidence };
}

class FakeQuery {
  readonly filters: Array<[string, unknown]> = [];
  private payload: Record<string, unknown> | null = null;

  constructor(
    private readonly client: FakeServiceClient,
    readonly table: string,
  ) {}

  select(_columns: string) {
    return this;
  }

  or(filter: string) {
    this.filters.push(["or", filter]);
    return this;
  }

  eq(column: string, value: unknown) {
    this.filters.push([column, value]);
    return this;
  }

  not(column: string, operator: string, value: unknown) {
    this.filters.push([`${column}.${operator}`, value]);
    return this;
  }

  order(column: string) {
    this.filters.push(["order", column]);
    return this;
  }

  update(payload: Record<string, unknown>) {
    this.payload = payload;
    return this;
  }

  limit(_count: number) {
    this.client.reads.push({
      table: this.table,
      filters: [...this.filters],
    });
    const error = this.client.queryErrors.get(this.table) ?? null;
    const data = this.client.rows.get(this.table) ??
      (this.client.evidenceTables.has(this.table) ? [{ id: `${this.table}-evidence` }] : []);
    return Promise.resolve({ data, error });
  }

  maybeSingle() {
    this.client.reads.push({
      table: this.table,
      filters: [...this.filters],
    });
    const error = this.client.queryErrors.get(this.table) ?? null;
    const explicitRow = this.client.singleRows.get(this.table);
    const data = explicitRow ??
      (this.client.evidenceTables.has(this.table)
        ? this.table === "user_invitations"
          ? {
            id: `${this.table}-evidence`,
            role: "cashier",
            permissions: {
              access_pos: false,
              create_invoices: false,
              edit_prices: false,
              delete_invoices: false,
              access_accounting: false,
              manage_users: false,
              edit_settings: false,
            },
          }
          : { id: `${this.table}-evidence` }
        : null);
    return Promise.resolve({ data, error });
  }

  then<TResult1 = unknown, TResult2 = never>(
    onfulfilled?:
      | ((
        value: { data: unknown[] | null; error: unknown },
      ) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    if (this.payload != null) {
      this.client.updates.push({
        table: this.table,
        payload: this.payload,
        filters: [...this.filters],
      });
    }
    this.client.reads.push({
      table: this.table,
      filters: [...this.filters],
    });
    return Promise.resolve({
      data: this.client.rows.get(this.table) ?? null,
      error: this.client.queryErrors.get(this.table) ?? null,
    }).then(
      onfulfilled,
      onrejected,
    );
  }
}

class FakeServiceClient {
  readonly evidenceTables = new Set<string>();
  readonly rows = new Map<string, Record<string, unknown>[]>();
  readonly singleRows = new Map<string, Record<string, unknown>>();
  readonly authUsers = new Map<string, Record<string, unknown>>();
  readonly queryErrors = new Map<string, { message: string }>();
  readonly updates: RecordedUpdate[] = [];
  readonly reads: RecordedRead[] = [];
  readonly authUpdates: Array<{
    userId: string;
    payload: Record<string, unknown>;
  }> = [];
  readonly rpcCalls: Array<{
    name: string;
    args: Record<string, unknown>;
  }> = [];
  readonly rpcResults = new Map<
    string,
    { data: unknown; error: unknown }
  >();

  readonly auth = {
    admin: {
      getUserById: (userId: string) =>
        Promise.resolve({
          data: { user: this.authUsers.get(userId) ?? null },
          error: null,
        }),
      listUsers: ({ page }: { page: number; perPage: number }) =>
        Promise.resolve({
          data: {
            users: page === 1 ? [...this.authUsers.values()] : [],
          },
          error: null,
        }),
      updateUserById: (
        userId: string,
        payload: Record<string, unknown>,
      ) => {
        this.authUpdates.push({ userId, payload });
        return Promise.resolve({ data: null, error: null });
      },
    },
  };

  from(table: string) {
    return new FakeQuery(this, table);
  }

  rpc(name: string, args: Record<string, unknown>) {
    this.rpcCalls.push({ name, args });
    if (name === "resolve_auth_user_id_by_email") {
      const normalizedEmail = String(args.p_email ?? "").trim().toLowerCase();
      const authUser = [...this.authUsers.values()].find((candidate) =>
        String(candidate.email ?? "").trim().toLowerCase() === normalizedEmail
      );
      return Promise.resolve({ data: authUser?.id ?? null, error: null });
    }
    return Promise.resolve(
      this.rpcResults.get(name) ?? {
        data: null,
        error: { message: `Unexpected RPC: ${name}` },
      },
    );
  }
}

function workerSagaClient(input: {
  insertError?: unknown;
  insertedId?: string;
  linkedId?: string;
  linkReadError?: unknown;
  authUser?: Record<string, unknown> | null;
  membershipTables?: string[];
  deleteError?: unknown;
}) {
  const deletedUserIds: string[] = [];
  const authReads: string[] = [];
  const insertedPayloads: Record<string, unknown>[] = [];
  const membershipTables = new Set(input.membershipTables ?? []);
  const client = {
    auth: {
      admin: {
        getUserById: (userId: string) => {
          authReads.push(userId);
          return Promise.resolve({
            data: { user: input.authUser ?? null },
            error: null,
          });
        },
        deleteUser: (userId: string) => {
          deletedUserIds.push(userId);
          return Promise.resolve({
            data: null,
            error: input.deleteError ?? null,
          });
        },
      },
    },
    from: (table: string) => {
      let operation: "read" | "insert" = "read";
      const query = {
        insert: (payload: Record<string, unknown>) => {
          operation = "insert";
          insertedPayloads.push(payload);
          return query;
        },
        select: (_columns: string) => query,
        eq: (_column: string, _value: unknown) => query,
        single: () =>
          Promise.resolve({
            data: input.insertedId ? { id: input.insertedId } : null,
            error: input.insertError ?? null,
          }),
        maybeSingle: () =>
          Promise.resolve({
            data: table === "employee_portal_accounts" && input.linkedId
              ? { id: input.linkedId }
              : null,
            error: input.linkReadError ?? null,
          }),
        limit: (_count: number) =>
          Promise.resolve({
            data: operation === "read" && membershipTables.has(table)
              ? [{ id: `${table}-membership` }]
              : [],
            error: null,
          }),
      };
      return query;
    },
  };
  return {
    client,
    deletedUserIds,
    authReads,
    insertedPayloads,
  };
}

function customerProvisioningClient() {
  const customerId = "55555555-5555-4555-8555-555555555555";
  const authUserId = "66666666-6666-4666-8666-666666666666";
  let invitationCount = 0;
  let databaseMutationCount = 0;
  let recoveryCount = 0;
  const client = {
    auth: {
      admin: {
        getUserById: (_userId: string) =>
          Promise.resolve({
            data: {
              user: {
                id: authUserId,
                email: "customer@example.invalid",
                email_confirmed_at: "2026-07-26T12:00:00.000Z",
              },
            },
            error: null,
          }),
        inviteUserByEmail: () => {
          invitationCount += 1;
          return Promise.resolve({ data: null, error: null });
        },
      },
      resetPasswordForEmail: () => {
        recoveryCount += 1;
        return Promise.resolve({ data: null, error: null });
      },
    },
    from: (table: string) => {
      let operation: "read" | "update" = "read";
      const query = {
        select: (_columns: string) => query,
        update: (_payload: Record<string, unknown>) => {
          operation = "update";
          databaseMutationCount += 1;
          return query;
        },
        eq: (_column: string, _value: unknown) => query,
        is: (_column: string, _value: unknown) => query,
        ilike: (_column: string, _value: unknown) => query,
        maybeSingle: () => {
          if (table === "tenants") {
            return Promise.resolve({
              data: { custom_domain: "vinabike.cl", subdomain: "vinabike" },
              error: null,
            });
          }
          if (table === "customers" && operation === "update") {
            return Promise.resolve({
              data: { id: customerId, auth_user_id: authUserId },
              error: null,
            });
          }
          return Promise.resolve({
            data: {
              id: customerId,
              name: "Cliente",
              email: "customer@example.invalid",
              phone: null,
              is_active: true,
              auth_user_id: authUserId,
            },
            error: null,
          });
        },
        then<TResult1 = unknown, TResult2 = never>(
          onfulfilled?:
            | ((value: { data: null; error: null }) => TResult1 | PromiseLike<TResult1>)
            | null,
          onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
        ): Promise<TResult1 | TResult2> {
          return Promise.resolve({ data: null, error: null }).then(
            onfulfilled,
            onrejected,
          );
        },
      };
      return query;
    },
  };
  return {
    client,
    customerId,
    authUserId,
    counts: () => ({
      invitationCount,
      databaseMutationCount,
      recoveryCount,
    }),
  };
}

Deno.test("caller authorization joins one matching active tenant", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const { userClient, serviceClient, evidence } = callerContextClients({
    profileRows: [{
      tenant_id: tenantId,
      role: "manager",
      permissions: {},
      tenants: {
        id: tenantId,
        is_active: true,
        owner_email: "owner@example.invalid",
      },
    }],
  });

  assertEquals(
    await getCallerContext(
      userClient,
      serviceClient,
      "freshly-issued-access-token",
    ),
    {
      userId: "11111111-1111-4111-8111-111111111111",
      tenantId,
      role: "manager",
      permissions: {},
      isPrincipalOwner: false,
      tenantOwnerEmail: "owner@example.invalid",
    },
    "an active profile is authorized only with its matching active tenant",
  );
  assertEquals(
    evidence,
    {
      accessToken: "freshly-issued-access-token",
      table: "user_profiles",
      select: "tenant_id, role, permissions, tenants!inner(id, is_active, owner_email)",
      filters: [
        ["user_id", "11111111-1111-4111-8111-111111111111"],
        ["is_active", true],
        ["tenants.is_active", true],
      ],
      limit: 2,
    },
    "profile and active tenant must be checked in one joined authorization query",
  );
});

Deno.test("caller authorization rejects an inactive tenant", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const { userClient, serviceClient } = callerContextClients({
    profileRows: [{
      tenant_id: tenantId,
      role: "manager",
      permissions: {},
      tenants: { id: tenantId, is_active: false },
    }],
  });

  await assertRejectsCode(
    () => getCallerContext(userClient, serviceClient),
    "tenant_context_invalid",
    "a suspended tenant cannot retain service-role-backed administration",
  );
});

Deno.test("caller authorization rejects a missing joined tenant row", async () => {
  const { userClient, serviceClient } = callerContextClients({
    profileRows: [{
      tenant_id: "22222222-2222-4222-8222-222222222222",
      role: "manager",
      permissions: {},
      tenants: null,
    }],
  });

  await assertRejectsCode(
    () => getCallerContext(userClient, serviceClient),
    "tenant_context_invalid",
    "an orphaned profile cannot authorize without its tenant row",
  );
});

Deno.test("caller authorization fails closed when active tenant lookup errors", async () => {
  const { userClient, serviceClient } = callerContextClients({
    profileError: { code: "XX000", message: "lookup unavailable" },
  });

  await assertRejectsCode(
    () => getCallerContext(userClient, serviceClient),
    "authorization_unavailable",
    "tenant lookup errors cannot fall through to service-role operations",
  );
});

Deno.test("principal owner identity uses authoritative email or exact Auth claims", () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  assertEquals(
    derivePrincipalOwnerIdentity({
      tenantId,
      tenantOwnerEmail: "owner@example.invalid",
      authUser: {
        email: "OWNER@example.invalid",
        app_metadata: {
          account_type: "erp_staff",
          tenant_id: tenantId,
        },
      },
    }),
    true,
    "the normalized Auth email matching tenants.owner_email proves the principal",
  );
  assertEquals(
    derivePrincipalOwnerIdentity({
      tenantId,
      tenantOwnerEmail: "old-owner@example.invalid",
      authUser: {
        email: "updated-owner@example.invalid",
        app_metadata: {
          account_type: "erp_owner",
          tenant_id: tenantId,
        },
      },
    }),
    true,
    "an owner with an updated email remains protected by exact server-owned claims",
  );
  assertEquals(
    derivePrincipalOwnerIdentity({
      tenantId,
      tenantOwnerEmail: "owner@example.invalid",
      authUser: {
        email: "attacker@example.invalid",
        app_metadata: {
          account_type: "erp_owner",
          tenant_id: "99999999-9999-4999-8999-999999999999",
        },
      },
    }),
    false,
    "neither a wrong email nor a claim for another tenant can prove ownership",
  );
});

Deno.test("strict role hierarchy blocks peer admins and manager elevation", () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const manager = {
    userId: "11111111-1111-4111-8111-111111111111",
    tenantId,
    role: "manager",
    permissions: {
      access_pos: true,
      create_invoices: true,
      manage_users: true,
    },
  };
  assertThrowsCode(
    () => authorizeStaffAssignment(manager, "admin", undefined),
    "role_assignment_forbidden",
    "a manager cannot create an admin invitation",
  );

  const delegatedManager = {
    ...manager,
    role: "cashier",
  };
  assertThrowsCode(
    () => authorizeStaffAssignment(delegatedManager, "manager", undefined),
    "role_assignment_forbidden",
    "manage_users delegates management but never a manager promotion",
  );
  assertThrowsCode(
    () =>
      authorizeStaffAssignment(delegatedManager, "cashier", {
        manage_users: true,
      }),
    "role_assignment_forbidden",
    "a delegated manager cannot create a same-rank manager disguised as an operational role",
  );
  assertEquals(
    authorizeStaffAssignment(delegatedManager, "cashier", undefined),
    {
      role: "cashier",
      permissions: {
        access_pos: true,
        create_invoices: true,
        edit_prices: false,
        delete_invoices: false,
        access_accounting: false,
        manage_users: false,
        edit_settings: false,
      },
    },
    "a delegated manager retains normal lower-role management",
  );

  const admin = {
    ...manager,
    role: "admin",
  };
  assertThrowsCode(
    () => assertRoleAssignmentAllowed(admin, "admin"),
    "role_assignment_forbidden",
    "an admin cannot create or assign a peer admin",
  );
  assertThrowsCode(
    () =>
      assertStaffTargetMutationAllowed(admin, {
        userId: "33333333-3333-4333-8333-333333333333",
        role: "admin",
        permissions: {},
        isActive: true,
        updatedAt: "2026-07-26T12:00:00.000Z",
        isPrincipalOwner: false,
      }),
    "staff_hierarchy_forbidden",
    "an admin cannot demote, suspend or detach another admin",
  );
  assertThrowsCode(
    () =>
      assertStaffTargetMutationAllowed(manager, {
        userId: "44444444-4444-4444-8444-444444444444",
        role: "cashier",
        permissions: { manage_users: true },
        isActive: true,
        updatedAt: "2026-07-26T12:00:00.000Z",
        isPrincipalOwner: false,
      }),
    "staff_hierarchy_forbidden",
    "a manager cannot mutate a delegated same-rank manager",
  );
});

Deno.test("permission grants use only canonical booleans within caller authority", () => {
  assertThrowsCode(
    () =>
      canonicalizeRequestedPermissions({
        access_pos: true,
        root_access: true,
      }),
    "invalid_permissions",
    "arbitrary permission keys must be rejected",
  );
  assertThrowsCode(
    () =>
      canonicalizeRequestedPermissions({
        access_pos: "yes",
      }),
    "invalid_permissions",
    "permission values must be booleans",
  );

  const delegatedAdmin = {
    userId: "11111111-1111-4111-8111-111111111111",
    tenantId: "22222222-2222-4222-8222-222222222222",
    role: "admin",
    permissions: { manage_users: true },
  };
  assertThrowsCode(
    () =>
      assertPermissionGrantAllowed(
        delegatedAdmin,
        canonicalizeRequestedPermissions({ edit_settings: true }),
      ),
    "permission_grant_forbidden",
    "an admin cannot grant a permission absent from its DB authority",
  );
  assertThrowsCode(
    () =>
      assertStoredInvitationAuthorityAllowed(delegatedAdmin, {
        role: "cashier",
        permissions: { edit_settings: true },
      }),
    "permission_grant_forbidden",
    "an existing elevated invitation cannot be resent or cancelled by a lesser caller",
  );
  assertThrowsCode(
    () =>
      assertStoredInvitationAuthorityAllowed(
        {
          ...delegatedAdmin,
          role: "manager",
        },
        {
          role: "cashier",
          permissions: { manage_users: true },
        },
      ),
    "role_assignment_forbidden",
    "a manager cannot relay a same-rank delegated-manager invitation",
  );
});

Deno.test("self elevation and principal-owner mutation are blocked", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const caller = {
    userId: "11111111-1111-4111-8111-111111111111",
    tenantId,
    role: "manager",
    permissions: { manage_users: true },
  };
  await assertRejectsCode(
    () =>
      updateInternalUser(
        new FakeServiceClient(),
        caller,
        { userId: caller.userId, role: "admin" },
      ),
    "self_role_change_forbidden",
    "a manager cannot elevate itself",
  );
  assertThrowsCode(
    () =>
      assertStaffTargetMutationAllowed(caller, {
        userId: "33333333-3333-4333-8333-333333333333",
        role: "admin",
        permissions: {},
        isActive: true,
        updatedAt: "2026-07-26T12:00:00.000Z",
        isPrincipalOwner: true,
      }),
    "principal_owner_protected",
    "the principal owner cannot be degraded, deactivated or detached",
  );
});

Deno.test("principal owner can legitimately manage an admin and canonical permissions", () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const owner = {
    userId: "11111111-1111-4111-8111-111111111111",
    tenantId,
    role: "admin",
    permissions: {},
    isPrincipalOwner: true,
    tenantOwnerEmail: "owner@example.invalid",
  };
  const allPermissions = {
    access_pos: true,
    create_invoices: true,
    edit_prices: true,
    delete_invoices: true,
    access_accounting: true,
    manage_users: true,
    edit_settings: true,
  };
  assertEquals(
    authorizeStaffAssignment(owner, "admin", allPermissions),
    { role: "admin", permissions: allPermissions },
    "only the principal owner can assign the highest stored staff role",
  );
  assertStaffTargetMutationAllowed(owner, {
    userId: "33333333-3333-4333-8333-333333333333",
    role: "admin",
    permissions: allPermissions,
    isActive: true,
    updatedAt: "2026-07-26T12:00:00.000Z",
    isPrincipalOwner: false,
  });
});

Deno.test("employee link target policy permits owner self-link but protects another principal", () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const owner = {
    userId: "11111111-1111-4111-8111-111111111111",
    tenantId,
    role: "admin",
    permissions: {},
    isPrincipalOwner: true,
  };
  assertEmployeeLinkTargetAllowed(owner, {
    userId: owner.userId,
    role: "admin",
    permissions: {},
    isActive: true,
    updatedAt: "2026-07-26T12:00:00.000Z",
    isPrincipalOwner: true,
  });
  assertThrowsCode(
    () =>
      assertEmployeeLinkTargetAllowed(
        { ...owner, userId: "99999999-9999-4999-8999-999999999999" },
        {
          userId: "33333333-3333-4333-8333-333333333333",
          role: "admin",
          permissions: {},
          isActive: true,
          updatedAt: "2026-07-26T12:00:00.000Z",
          isPrincipalOwner: true,
        },
      ),
    "principal_owner_protected",
    "a different administrator cannot attach the tenant principal to HR data",
  );
});

Deno.test("explicit employee link actions use caller JWT RPCs and verify exact receipts", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const userId = "33333333-3333-4333-8333-333333333333";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  const caller = {
    userId: "11111111-1111-4111-8111-111111111111",
    tenantId,
    role: "admin",
    permissions: {},
    isPrincipalOwner: true,
    tenantOwnerEmail: "owner@example.invalid",
  };
  const serviceClient = new FakeServiceClient();
  serviceClient.singleRows.set("user_profiles", {
    user_id: userId,
    role: "cashier",
    permissions: {},
    is_active: true,
    updated_at: "2026-07-26T12:00:00.000Z",
  });
  serviceClient.authUsers.set(userId, {
    id: userId,
    email: "staff@example.invalid",
    app_metadata: {
      account_type: "erp_staff",
      tenant_id: tenantId,
    },
  });

  const userClient = new FakeServiceClient();
  userClient.rpcResults.set("link_erp_user_to_employee", {
    data: {
      success: true,
      linked: true,
      userId,
      employeeId,
    },
    error: null,
  });
  assertEquals(
    await linkInternalUserEmployee(
      userClient,
      serviceClient,
      caller,
      { userId, employeeId },
    ),
    {
      success: true,
      linked: true,
      userId,
      employeeId,
    },
    "link action verifies the exact database receipt",
  );
  assertEquals(
    userClient.rpcCalls[0],
    {
      name: "link_erp_user_to_employee",
      args: {
        p_user_id: userId,
        p_employee_id: employeeId,
      },
    },
    "link action uses only the authenticated canonical RPC",
  );

  serviceClient.singleRows.set("user_profiles", {
    user_id: userId,
    role: "cashier",
    permissions: {},
    is_active: false,
    updated_at: "2026-07-26T12:05:00.000Z",
  });
  userClient.rpcResults.set("unlink_erp_user_from_employee", {
    data: {
      success: true,
      linked: false,
      userId,
      employeeId,
    },
    error: null,
  });
  assertEquals(
    await unlinkInternalUserEmployee(
      userClient,
      serviceClient,
      caller,
      { userId, employeeId },
    ),
    {
      success: true,
      linked: false,
      userId,
      employeeId,
    },
    "unlink action verifies the exact database receipt",
  );
  assertEquals(
    userClient.rpcCalls[1],
    {
      name: "unlink_erp_user_from_employee",
      args: {
        p_user_id: userId,
        p_employee_id: employeeId,
      },
    },
    "unlink action cannot select or detach a different employee",
  );
});

Deno.test("deleting linked ERP staff unlinks through the caller JWT before suspension", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const userId = "33333333-3333-4333-8333-333333333333";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  const caller = {
    userId: "11111111-1111-4111-8111-111111111111",
    tenantId,
    role: "admin",
    permissions: {},
    isPrincipalOwner: true,
    tenantOwnerEmail: "owner@example.invalid",
  };
  const serviceClient = new FakeServiceClient();
  serviceClient.singleRows.set("user_profiles", {
    user_id: userId,
    role: "cashier",
    permissions: {},
    is_active: true,
    updated_at: "2026-07-26T12:00:00.000Z",
  });
  serviceClient.authUsers.set(userId, {
    id: userId,
    email: "staff@example.invalid",
    app_metadata: {
      account_type: "erp_staff",
      tenant_id: tenantId,
    },
  });
  const userClient = new FakeServiceClient();
  userClient.rpcResults.set("deactivate_and_unlink_erp_user", {
    data: {
      success: true,
      deactivated: true,
      unlinked: true,
      userId,
      employeeId,
    },
    error: null,
  });

  assertEquals(
    await deleteInternalAccount(
      userClient,
      serviceClient,
      caller,
      { userId },
    ),
    {
      success: true,
      authDeleted: false,
      authBanned: false,
      authDetachedOnly: true,
      accountDeactivated: true,
      preservedForMessagingHistory: false,
      outcome: "tenant_access_detached",
      messagingEvidence: [],
    },
    "linked staff deletion returns the canonical detached receipt",
  );
  assertEquals(
    userClient.rpcCalls,
    [{
      name: "deactivate_and_unlink_erp_user",
      args: {
        p_user_id: userId,
        p_tenant_id: tenantId,
      },
    }],
    "delete atomically unlinks and deactivates through the authenticated RPC",
  );
  assert(
    serviceClient.updates.every((update) =>
      update.table !== "employees" || !("user_id" in update.payload)
    ),
    "delete never bypasses the canonical RPC with a service-role link write",
  );
});

Deno.test("employee access overview exposes inactive exact links and every access mode", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const client = new FakeServiceClient();
  client.rows.set("employees", [
    {
      id: "employee-erp",
      first_name: "Erp",
      last_name: "Linked",
      email: "erp@example.invalid",
      status: "inactive",
      user_id: "user-erp",
    },
    {
      id: "employee-worker",
      first_name: "Worker",
      last_name: "Active",
      email: null,
      status: "active",
      user_id: null,
    },
    {
      id: "employee-pending",
      first_name: "Invite",
      last_name: "Pending",
      email: "pending@example.invalid",
      status: "active",
      user_id: null,
    },
    {
      id: "employee-suspended-worker",
      first_name: "Worker",
      last_name: "Suspended",
      email: null,
      status: "active",
      user_id: null,
    },
  ]);
  client.rows.set("user_profiles", [
    {
      user_id: "user-erp",
      employee_id: "employee-erp",
      is_active: false,
    },
  ]);
  client.rows.set("employee_portal_accounts", [
    {
      employee_id: "employee-worker",
      username: "worker",
      is_active: true,
    },
    {
      employee_id: "employee-suspended-worker",
      username: "suspended",
      is_active: false,
    },
  ]);
  client.rows.set("user_invitations", [
    { employee_id: "employee-pending" },
  ]);

  const states = await getEmployeeAccessStates(client, tenantId);
  assertEquals(
    states.map((state: any) => ({
      employeeId: state.employeeId,
      status: state.status,
      linkState: state.linkState,
      erpProfileActive: state.erpProfileActive,
    })),
    [
      {
        employeeId: "employee-erp",
        status: "inactive",
        linkState: "erp_linked",
        erpProfileActive: false,
      },
      {
        employeeId: "employee-worker",
        status: "active",
        linkState: "worker_active",
        erpProfileActive: false,
      },
      {
        employeeId: "employee-pending",
        status: "active",
        linkState: "pending_invitation",
        erpProfileActive: false,
      },
      {
        employeeId: "employee-suspended-worker",
        status: "active",
        linkState: "worker_suspended",
        erpProfileActive: false,
      },
    ],
    "overview preserves inactive ERP links so administrators can explicitly unlink them",
  );
});

Deno.test("employee access database conflicts map to stable tenant-safe API codes", () => {
  for (
    const [databaseError, expectedCode] of [
      [{ code: "P0001", message: "worker_access_conflict" }, "worker_access_conflict"],
      [{ code: "P0001", message: "worker_identity_conflict" }, "worker_identity_conflict"],
      [
        {
          code: "23505",
          message: "duplicate",
          constraint: "employees_one_erp_user_uidx",
        },
        "employee_erp_link_conflict",
      ],
      [
        { code: "P0001", message: "employee_erp_link_inconsistent" },
        "employee_erp_link_state_changed",
      ],
      [
        {
          code: "23505",
          message: "duplicate",
          constraint: "user_profiles_one_erp_employee_uidx",
        },
        "employee_erp_link_conflict",
      ],
      [{ code: "P0001", message: "employee_not_found" }, "employee_not_found"],
      [{ code: "42501", message: "principal_owner_protected" }, "principal_owner_protected"],
      [{ code: "42501", message: "staff_hierarchy_forbidden" }, "staff_hierarchy_forbidden"],
    ] as const
  ) {
    assertThrowsCode(
      () => {
        throw mapEmployeeAccessError(databaseError);
      },
      expectedCode,
      `database conflict maps to ${expectedCode}`,
    );
  }
});

Deno.test("an active tenant staff email must use direct employee linking, never another invitation", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const email = "staff@example.invalid";
  const userId = "33333333-3333-4333-8333-333333333333";
  const client = new FakeServiceClient();
  client.authUsers.set(userId, {
    id: userId,
    email,
    app_metadata: {
      account_type: "erp_staff",
      tenant_id: tenantId,
    },
  });
  client.rows.set("user_profiles", [{
    user_id: userId,
    tenant_id: tenantId,
    is_active: true,
  }]);

  await assertRejectsCode(
    () => assertInvitationEmailNotActiveStaff(client, tenantId, email),
    "active_staff_email_requires_direct_link",
    "active staff email preflight returns the direct-link conflict",
  );
  await assertRejectsCode(
    () =>
      createInternalInvitation(
        client,
        {
          userId: "11111111-1111-4111-8111-111111111111",
          tenantId,
          role: "admin",
          permissions: {},
          isPrincipalOwner: true,
          tenantOwnerEmail: "owner@example.invalid",
        },
        {
          email,
          role: "cashier",
          permissions: {},
        },
        "Bearer caller-user-jwt",
        new Request(
          "https://example.supabase.co/functions/v1/admin-user-management",
        ),
      ),
    "active_staff_email_requires_direct_link",
    "invitation creation cannot silently target an existing active member",
  );
  assertEquals(
    client.updates.length,
    0,
    "denied active-staff invitations do not mutate state",
  );

  const inactiveClient = new FakeServiceClient();
  inactiveClient.authUsers.set(userId, {
    id: userId,
    email,
  });
  inactiveClient.rows.set("user_profiles", [{
    user_id: userId,
    tenant_id: tenantId,
    is_active: false,
  }]);
  await assertRejectsCode(
    () =>
      assertInvitationEmailNotActiveStaff(
        inactiveClient,
        tenantId,
        email,
      ),
    "staff_membership_inactive",
    "a suspended same-tenant membership must be reactivated or detached",
  );

  const foreignActiveClient = new FakeServiceClient();
  foreignActiveClient.authUsers.set(userId, {
    id: userId,
    email,
  });
  foreignActiveClient.rows.set("user_profiles", [{
    user_id: userId,
    tenant_id: "99999999-9999-4999-8999-999999999999",
    is_active: true,
  }]);
  await assertRejectsCode(
    () =>
      assertInvitationEmailNotActiveStaff(
        foreignActiveClient,
        tenantId,
        email,
      ),
    "staff_identity_tenant_conflict",
    "an Auth identity with another active ERP tenant cannot receive an impossible invitation",
  );

  const workerIdentityClient = new FakeServiceClient();
  workerIdentityClient.authUsers.set(userId, {
    id: userId,
    email,
  });
  workerIdentityClient.rows.set("employee_portal_accounts", [{
    tenant_id: tenantId,
    is_active: false,
  }]);
  await assertRejectsCode(
    () =>
      assertInvitationEmailNotActiveStaff(
        workerIdentityClient,
        tenantId,
        email,
      ),
    "worker_identity_conflict",
    "even a suspended Worker identity cannot receive an unusable ERP invitation",
  );

  const historicalEmployeeClient = new FakeServiceClient();
  historicalEmployeeClient.authUsers.set(userId, {
    id: userId,
    email,
  });
  historicalEmployeeClient.rows.set("employees", [{
    id: "historical-employee",
    tenant_id: "99999999-9999-4999-8999-999999999999",
  }]);
  await assertRejectsCode(
    () =>
      assertInvitationEmailNotActiveStaff(
        historicalEmployeeClient,
        tenantId,
        email,
      ),
    "historical_employee_identity_conflict",
    "an Auth identity already reserved by any employee cannot receive even an unbound invitation",
  );
  await assertRejectsCode(
    () =>
      createInternalInvitation(
        historicalEmployeeClient,
        {
          userId: "11111111-1111-4111-8111-111111111111",
          tenantId,
          role: "admin",
          permissions: {},
          isPrincipalOwner: true,
          tenantOwnerEmail: "owner@example.invalid",
        },
        {
          email,
          role: "cashier",
          permissions: {},
        },
        "Bearer caller-user-jwt",
        new Request(
          "https://example.supabase.co/functions/v1/admin-user-management",
        ),
      ),
    "historical_employee_identity_conflict",
    "the unbound invitation route rejects a globally reserved employee identity before email",
  );
});

Deno.test("invitation preflight and submit share one customer-safe identity evaluator", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const email = "customer@example.invalid";
  const userId = "33333333-3333-4333-8333-333333333333";
  const client = new FakeServiceClient();
  client.authUsers.set(userId, { id: userId, email });
  client.rows.set("customers", [{ id: "customer-1" }]);

  const direct = await evaluateInvitationIdentity(client, tenantId, email);
  assertEquals(
    direct,
    {
      eligible: true,
      status: "available_existing_customer",
      hasExistingAuthIdentity: true,
      isExistingCustomer: true,
    },
    "an existing storefront customer remains eligible for staff invitation",
  );

  const preflight = await checkInternalInvitationIdentity(
    client,
    {
      userId: "11111111-1111-4111-8111-111111111111",
      tenantId,
      role: "admin",
      permissions: {},
    },
    { email },
  );
  assertEquals(
    preflight,
    direct,
    "the public preflight exposes the same safe eligibility projection",
  );
  await assertInvitationEmailNotActiveStaff(client, tenantId, email);
  assertEquals(client.updates.length, 0, "identity checks never mutate records");
  assertEquals(client.authUpdates.length, 0, "identity checks never mutate Auth");
});

Deno.test("invitation preflight returns typed conflict evidence without foreign tenant details", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const email = "legacy@example.invalid";
  const userId = "33333333-3333-4333-8333-333333333333";
  const client = new FakeServiceClient();
  client.authUsers.set(userId, { id: userId, email });
  client.rows.set("user_profiles", [{
    tenant_id: "99999999-9999-4999-8999-999999999999",
    is_active: true,
  }]);

  const result = await checkInternalInvitationIdentity(
    client,
    {
      userId: "11111111-1111-4111-8111-111111111111",
      tenantId,
      role: "admin",
      permissions: {},
    },
    { email },
  );
  assertEquals(
    result,
    {
      eligible: false,
      status: "staff_identity_tenant_conflict",
      hasExistingAuthIdentity: true,
      isExistingCustomer: false,
    },
    "preflight returns only the safe conflict category",
  );
  assert(
    !JSON.stringify(result).includes("99999999"),
    "preflight must not leak a foreign tenant identifier",
  );
});

Deno.test("all internal invitation and staff mutation routes enforce hierarchy", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const invitationCreate = source.slice(
    source.indexOf("async function createInternalInvitation"),
    source.indexOf("export async function assertActiveEmployeeForInvitation"),
  );
  assert(
    invitationCreate.includes("authorizeStaffAssignment") &&
      invitationCreate.includes("assertStoredInvitationAuthorityAllowed"),
    "new and existing invitations must enforce role and permission ceilings",
  );
  const invitationRelay = source.slice(
    source.indexOf("export async function sendInvitationEmail"),
    source.indexOf("export async function assertPendingInvitationInTenant"),
  );
  assert(
    invitationRelay.includes("assertStoredInvitationAuthorityAllowed"),
    "resending an invitation must revalidate its stored authority",
  );
  const invitationCancel = source.slice(
    source.indexOf("async function cancelInternalInvitation"),
    source.indexOf("export async function updateInternalUser"),
  );
  assert(
    invitationCancel.includes("assertStoredInvitationAuthorityAllowed"),
    "cancelling an invitation must revalidate its stored authority",
  );
  for (
    const [start, end, label] of [
      [
        "export async function updateInternalUser",
        "async function updateInternalIdentity",
        "role update",
      ],
      [
        "async function updateInternalIdentity",
        "async function setInternalAccess",
        "identity update",
      ],
      [
        "async function setInternalAccess",
        "async function deleteInternalAccount",
        "access update",
      ],
      [
        "async function deleteInternalAccount",
        "async function createWorkerPortalAccount",
        "tenant detach",
      ],
    ] as const
  ) {
    const flow = source.slice(source.indexOf(start), source.indexOf(end));
    assert(
      flow.includes("getStaffTargetContext") &&
        flow.includes("assertStaffTargetMutationAllowed"),
      `${label} must load authoritative target identity and enforce hierarchy`,
    );
  }
});

Deno.test("manager cannot relay a stored admin invitation", async () => {
  const client = new FakeServiceClient();
  client.singleRows.set("user_invitations", {
    id: "11111111-1111-4111-8111-111111111111",
    role: "admin",
    permissions: {},
  });
  let fetchCalled = false;
  await assertRejectsCode(
    () =>
      sendInvitationEmail(
        client,
        {
          userId: "33333333-3333-4333-8333-333333333333",
          tenantId: "22222222-2222-4222-8222-222222222222",
          role: "manager",
          permissions: { manage_users: true },
        },
        "11111111-1111-4111-8111-111111111111",
        "Bearer caller-user-jwt",
        new Request(
          "https://example.supabase.co/functions/v1/admin-user-management",
        ),
        {
          fetchImpl: (() => {
            fetchCalled = true;
            return Promise.resolve(new Response("{}", { status: 200 }));
          }) as typeof fetch,
          getEnv: () => "unused",
        },
      ),
    "role_assignment_forbidden",
    "a manager cannot resend a higher-role invitation",
  );
  assertEquals(fetchCalled, false, "denied invitation cannot reach delivery");
});

Deno.test("pending invitation reuse rejects changed role, permissions or employee", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const owner = {
    userId: "33333333-3333-4333-8333-333333333333",
    tenantId,
    role: "admin",
    permissions: {},
    isPrincipalOwner: true,
    tenantOwnerEmail: "owner@example.invalid",
  };
  const cases = [
    {
      label: "role",
      existing: {
        id: "11111111-1111-4111-8111-111111111111",
        role: "admin",
        permissions: {},
        employee_id: null,
      },
      body: {
        email: "invitee@example.invalid",
        role: "cashier",
        permissions: {},
      },
    },
    {
      label: "permissions",
      existing: {
        id: "11111111-1111-4111-8111-111111111111",
        role: "cashier",
        permissions: { edit_settings: true },
        employee_id: null,
      },
      body: {
        email: "invitee@example.invalid",
        role: "cashier",
        permissions: {},
      },
    },
    {
      label: "employee",
      existing: {
        id: "11111111-1111-4111-8111-111111111111",
        role: "cashier",
        permissions: {},
        employee_id: "44444444-4444-4444-8444-444444444444",
      },
      body: {
        email: "invitee@example.invalid",
        role: "cashier",
        permissions: {},
        employeeId: "55555555-5555-4555-8555-555555555555",
      },
    },
  ] as const;

  for (const testCase of cases) {
    const client = new FakeServiceClient();
    client.singleRows.set("user_invitations", testCase.existing);
    if ("employeeId" in testCase.body) {
      client.singleRows.set("employees", { id: testCase.body.employeeId });
    }
    await assertRejectsCode(
      () =>
        createInternalInvitation(
          client,
          owner,
          testCase.body,
          "Bearer caller-user-jwt",
          new Request(
            "https://example.supabase.co/functions/v1/admin-user-management",
          ),
        ),
      "pending_invitation_exists",
      `pending invitation ${testCase.label} mismatch must fail closed`,
    );
  }
});

Deno.test("messaging evidence covers authorship, participation and durable commands", async () => {
  const client = new FakeServiceClient();
  client.evidenceTables.add("conversations");
  client.evidenceTables.add("conversation_participants");
  client.evidenceTables.add("conversation_contexts");
  client.evidenceTables.add("messages");
  client.evidenceTables.add("messaging_attachments");
  client.evidenceTables.add("messaging_command_receipts");
  client.evidenceTables.add("messaging_participant_reconciliation_audit");

  const evidence = await getMessagingDeletionEvidence(
    client,
    "11111111-1111-4111-8111-111111111111",
  );

  assertEquals(
    evidence,
    {
      hasEvidence: true,
      sources: [
        "conversations",
        "conversation_participants",
        "conversation_contexts",
        "messages",
        "messaging_attachments",
        "messaging_command_receipts",
        "messaging_participant_reconciliation_audit",
      ],
    },
    "all retained messaging identity surfaces must block Auth deletion",
  );
});

Deno.test("messaging evidence lookup fails closed when a source cannot be verified", async () => {
  const client = new FakeServiceClient();
  client.queryErrors.set("conversation_contexts", {
    message: "relation unavailable",
  });

  let error: unknown = null;
  try {
    await getMessagingDeletionEvidence(
      client,
      "11111111-1111-4111-8111-111111111111",
    );
  } catch (caught) {
    error = caught;
  }

  assert(error instanceof Error, "an incomplete evidence check must throw");
  assert(
    error.message.includes("conversation_contexts"),
    "the failed evidence surface must be named",
  );
});

Deno.test("history-preserving deactivation remains tenant-local", async () => {
  const client = new FakeServiceClient();
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const userId = "11111111-1111-4111-8111-111111111111";

  const result = await deactivateAccountPreservingMessagingHistory(
    client,
    tenantId,
    userId,
    "internal",
  );

  assertEquals(result, { authBanned: false }, "global Auth remains untouched");
  assertEquals(client.authUpdates, [], "tenant deactivation cannot mutate global Auth");
  assertEquals(
    client.updates.map((update) => update.table),
    ["user_profiles"],
    "only the requested internal membership is deactivated",
  );
  for (const update of client.updates) {
    assertEquals(update.payload.is_active, false, `${update.table} is inactive`);
    assert(
      update.filters.some(([column, value]) => column === "tenant_id" && value === tenantId),
      `${update.table} remains tenant scoped`,
    );
  }
});

Deno.test("customer deactivation does not inspect or mutate other memberships", async () => {
  const client = new FakeServiceClient();
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const userId = "11111111-1111-4111-8111-111111111111";

  const result = await deactivateAccountPreservingMessagingHistory(
    client,
    tenantId,
    userId,
    "customer",
  );

  assertEquals(result, { authBanned: false }, "global Auth must remain usable");
  assertEquals(client.authUpdates, [], "global Auth is not mutated");
  assertEquals(
    client.updates.map((update) => update.table),
    ["customers"],
    "only the requested customer membership is deactivated",
  );
  assert(
    !client.reads.some((read) =>
      read.table === "user_profiles" ||
      read.table === "employee_portal_accounts"
    ),
    "a tenant-local lifecycle action must not inspect global memberships",
  );
});

Deno.test("deletion results preserve Auth and report tenant-local outcomes", () => {
  assertEquals(
    preservedMessagingHistoryResult(
      {
        hasEvidence: true,
        sources: ["messages"],
      },
    ),
    {
      success: true,
      authDeleted: false,
      authBanned: false,
      authDetachedOnly: false,
      accountDeactivated: true,
      preservedForMessagingHistory: true,
      outcome: "deactivated_preserved_messaging_history",
      messagingEvidence: ["messages"],
    },
    "preserved result contract",
  );
  assertEquals(
    detachedAccountResult(),
    {
      success: true,
      authDeleted: false,
      authBanned: false,
      authDetachedOnly: true,
      accountDeactivated: true,
      preservedForMessagingHistory: false,
      outcome: "tenant_access_detached",
      messagingEvidence: [],
    },
    "tenant-only detach result contract",
  );
});

Deno.test("admin deletion never nulls immutable messaging authorship", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );

  for (
    const forbiddenMutation of [
      "update({ created_by: null })",
      "update({ accepted_by: null })",
      "update({ added_by: null })",
      "update({ sender_id: null })",
    ]
  ) {
    assert(
      !source.includes(forbiddenMutation),
      `forbidden audit mutation remains: ${forbiddenMutation}`,
    );
  }
  assert(
    !source.includes("clearCustomerAuthReferencesForDelete"),
    "legacy destructive cleanup helper must stay removed",
  );
});

Deno.test("internal invitation relay verifies the authoritative tenant and forwards caller JWT", async () => {
  const client = new FakeServiceClient();
  client.evidenceTables.add("user_invitations");
  const invitationId = "11111111-1111-4111-8111-111111111111";
  const tenantId = "22222222-2222-4222-8222-222222222222";
  let forwardedHeaders: Headers | null = null;
  let forwardedBody: Record<string, unknown> | null = null;

  const fetchImpl = ((_input: RequestInfo | URL, init?: RequestInit) => {
    forwardedHeaders = new Headers(init?.headers);
    forwardedBody = JSON.parse(init?.body?.toString() ?? "{}");
    return Promise.resolve(
      new Response(
        JSON.stringify({
          success: true,
          emailSent: true,
          invitationId,
          expiresAt: "2026-08-02T12:00:00.000Z",
          invitationLink: "https://must-not-be-relayed.invalid/?token=secret",
          token: "secret",
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch;

  const result = await sendInvitationEmail(
    client,
    {
      userId: "33333333-3333-4333-8333-333333333333",
      tenantId,
      role: "admin",
      permissions: { manage_users: true },
    },
    invitationId,
    "Bearer caller-user-jwt",
    new Request("https://example.supabase.co/functions/v1/admin-user-management", {
      headers: { origin: "https://project-vinabike.web.app" },
    }),
    {
      fetchImpl,
      getEnv: (name) => {
        if (name === "SUPABASE_URL") return "https://example.supabase.co";
        if (name === "SUPABASE_ANON_KEY") return "public-anon-key";
        return undefined;
      },
    },
  );

  const invitationRead = client.reads.find((read) => read.table === "user_invitations");
  assert(invitationRead, "invitation must be verified before relay");
  assert(
    invitationRead.filters.some(([key, value]) => key === "tenant_id" && value === tenantId),
    "invitation lookup must use authoritative caller tenant",
  );
  assert(
    invitationRead.filters.some(([key, value]) => key === "status" && value === "pending"),
    "only pending invitations can be relayed",
  );
  const capturedHeaders = forwardedHeaders as Headers | null;
  assert(capturedHeaders !== null, "relay request headers must be captured");
  assertEquals(
    capturedHeaders.get("authorization"),
    "Bearer caller-user-jwt",
    "relay must forward caller JWT instead of service role",
  );
  assertEquals(
    capturedHeaders.get("apikey"),
    "public-anon-key",
    "relay must use only the public gateway key",
  );
  assertEquals(
    forwardedBody,
    { invitationId },
    "relay body must contain only the scoped invitation id",
  );
  assertEquals(result.emailSent, true, "delivery evidence must be retained");
  assert(
    !Object.hasOwn(result, "invitationLink"),
    "relay response cannot return invitation links",
  );
  assert(!Object.hasOwn(result, "token"), "relay response cannot return tokens");
});

Deno.test("cross-tenant invitation id fails before invoking email delivery", async () => {
  const client = new FakeServiceClient();
  let fetchCalled = false;

  try {
    await sendInvitationEmail(
      client,
      {
        userId: "33333333-3333-4333-8333-333333333333",
        tenantId: "22222222-2222-4222-8222-222222222222",
        role: "admin",
        permissions: { manage_users: true },
      },
      "11111111-1111-4111-8111-111111111111",
      "Bearer caller-user-jwt",
      new Request("https://example.supabase.co/functions/v1/admin-user-management"),
      {
        fetchImpl: (() => {
          fetchCalled = true;
          return Promise.resolve(new Response("{}", { status: 200 }));
        }) as typeof fetch,
        getEnv: () => "unused",
      },
    );
    throw new Error("cross-tenant invitation should have failed");
  } catch (error) {
    assert(
      error instanceof Error && error.message === "Invitation not found",
      "cross-tenant ids must be indistinguishable from missing invitations",
    );
  }

  assertEquals(fetchCalled, false, "cross-tenant invitation cannot reach sender");
});

Deno.test("invitation relay preserves the safe cooldown response", async () => {
  const client = new FakeServiceClient();
  client.evidenceTables.add("user_invitations");
  let caught: unknown = null;

  try {
    await sendInvitationEmail(
      client,
      {
        userId: "33333333-3333-4333-8333-333333333333",
        tenantId: "22222222-2222-4222-8222-222222222222",
        role: "admin",
        permissions: { manage_users: true },
      },
      "11111111-1111-4111-8111-111111111111",
      "Bearer caller-user-jwt",
      new Request("https://example.supabase.co/functions/v1/admin-user-management"),
      {
        fetchImpl: (() =>
          Promise.resolve(
            new Response(
              JSON.stringify({
                error: "Please wait before sending this invitation again",
                code: "invitation_rate_limited",
              }),
              { status: 429 },
            ),
          )) as typeof fetch,
        getEnv: (name) => {
          if (name === "SUPABASE_URL") return "https://example.supabase.co";
          if (name === "SUPABASE_ANON_KEY") return "public-anon-key";
          return undefined;
        },
      },
    );
  } catch (error) {
    caught = error;
  }

  assert(caught instanceof Error, "cooldown must reject the relay");
  assertEquals(
    (caught as Error & { status?: number }).status,
    429,
    "relay must not turn a cooldown into a provider failure",
  );
  assertEquals(
    (caught as Error & { code?: string }).code,
    "invitation_rate_limited",
    "relay exposes only the stable cooldown code",
  );
});

Deno.test("invitation tenant assertion and CORS both fail closed", async () => {
  const client = new FakeServiceClient();
  await assertPendingInvitationInTenant(
    client,
    "22222222-2222-4222-8222-222222222222",
    "11111111-1111-4111-8111-111111111111",
  ).then(
    () => {
      throw new Error("missing invitation should fail");
    },
    (error) => {
      assert(
        error instanceof Error && error.message === "Invitation not found",
        "tenant assertion must hide missing/cross-tenant rows",
      );
    },
  );

  assertEquals(
    isAllowedCorsOrigin("https://project-vinabike--security-test.web.app", []),
    true,
    "owned preview origin should be allowed",
  );
  assertEquals(
    isAllowedCorsOrigin("https://attacker.example", []),
    false,
    "unrelated origin must be rejected",
  );
});

Deno.test("internal invitation employee must be active in the caller tenant", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  const missingClient = new FakeServiceClient();
  let caught: unknown = null;

  try {
    await assertActiveEmployeeForInvitation(
      missingClient,
      tenantId,
      employeeId,
    );
  } catch (error) {
    caught = error;
  }
  assert(caught instanceof Error, "missing or cross-tenant employee must fail");
  assertEquals(
    (caught as Error & { status?: number }).status,
    404,
    "employee mismatch is hidden as not found",
  );
  const employeeRead = missingClient.reads.find((read) => read.table === "employees");
  assert(
    employeeRead?.filters.some(([column, value]) => column === "tenant_id" && value === tenantId),
    "employee lookup must use the caller tenant",
  );
  assert(
    employeeRead?.filters.some(([column, value]) => column === "status" && value === "active"),
    "only active employees can be invited",
  );

  const activeClient = new FakeServiceClient();
  activeClient.evidenceTables.add("employees");
  await assertActiveEmployeeForInvitation(
    activeClient,
    tenantId,
    employeeId,
  );

  const workerClient = new FakeServiceClient();
  workerClient.evidenceTables.add("employees");
  workerClient.singleRows.set("employee_portal_accounts", {
    id: "55555555-5555-4555-8555-555555555555",
  });
  await assertRejectsCode(
    () =>
      assertActiveEmployeeForInvitation(
        workerClient,
        tenantId,
        employeeId,
      ),
    "worker_access_conflict",
    "an employee with active worker access cannot receive ERP access",
  );

  const linkedClient = new FakeServiceClient();
  linkedClient.singleRows.set("employees", {
    id: employeeId,
    user_id: "66666666-6666-4666-8666-666666666666",
  });
  await assertRejectsCode(
    () =>
      assertActiveEmployeeForInvitation(
        linkedClient,
        tenantId,
        employeeId,
      ),
    "employee_erp_link_conflict",
    "an employee already linked to ERP cannot receive another invitation",
  );
});

Deno.test("tenant-scoped staff update returns 404 when no profile changes", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const userId = "11111111-1111-4111-8111-111111111111";
  const caller = {
    userId: "33333333-3333-4333-8333-333333333333",
    tenantId,
    role: "admin",
    permissions: { manage_users: true },
    tenantOwnerEmail: "owner@example.invalid",
  };
  const missingClient = new FakeServiceClient();
  let caught: unknown = null;

  try {
    await updateInternalUser(
      missingClient,
      caller,
      { userId, role: "cashier" },
    );
  } catch (error) {
    caught = error;
  }
  assert(caught instanceof Error, "unmatched tenant update must fail");
  assertEquals(
    (caught as Error & { status?: number }).status,
    404,
    "unmatched tenant update must return not found",
  );
  const profileRead = missingClient.reads.find((read) => read.table === "user_profiles");
  assert(
    profileRead?.filters.some(([column, value]) => column === "tenant_id" && value === tenantId),
    "update remains scoped to the caller tenant",
  );

  const existingClient = new FakeServiceClient();
  existingClient.singleRows.set("user_profiles", {
    user_id: userId,
    role: "cashier",
    permissions: {},
    is_active: true,
    updated_at: "2026-07-26T12:00:00.000Z",
  });
  existingClient.authUsers.set(userId, {
    id: userId,
    email: "cashier@example.invalid",
    app_metadata: {
      account_type: "erp_staff",
      tenant_id: tenantId,
    },
  });
  assertEquals(
    await updateInternalUser(
      existingClient,
      caller,
      { userId, role: "cashier" },
    ),
    { success: true },
    "existing tenant profile can be updated",
  );
  assert(
    existingClient.reads.some((read) =>
      read.table === "user_profiles" &&
      read.filters.some(([column, value]) =>
        column === "updated_at" &&
        value === "2026-07-26T12:00:00.000Z"
      )
    ),
    "the write must compare the authority snapshot timestamp",
  );
});

Deno.test("account email flows do not mint or return recovery capability links", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );

  assert(
    source.includes("auth.resetPasswordForEmail"),
    "recovery must use the provider email delivery flow",
  );
  assert(
    !source.includes("auth.admin.generateLink"),
    "admin function cannot mint raw recovery links",
  );
  assert(
    !source.includes("invitationLink:"),
    "admin function cannot relay invitation links",
  );
  assert(
    !source.includes("accessLink:"),
    "admin function cannot return recovery links",
  );
  assert(
    !source.includes("temporaryPassword"),
    "admin function cannot return or generate temporary passwords",
  );
  assert(
    !source.includes("generatePassword"),
    "password generation must remain outside API responses and runtime",
  );
  assert(
    !source.includes("'Access-Control-Allow-Origin': '*'"),
    "authenticated admin CORS cannot use a wildcard",
  );
});

Deno.test("worker password policy requires an explicit strong unmodified secret", () => {
  assertEquals(
    isStrongAdminPassword("CorrectHorse!9"),
    true,
    "valid password should pass",
  );
  for (
    const weakPassword of [
      undefined,
      "",
      "Short!9Aa",
      "alllowercase!9",
      "ALLUPPERCASE!9",
      "NoDigitsHere!",
      "NoSymbolsHere9",
      "WhitespaceOnly 9A",
      "ControlChar!9Aa\n",
      `${"A".repeat(129)}a!9`,
    ]
  ) {
    assertEquals(
      isStrongAdminPassword(weakPassword),
      false,
      "weak or malformed password must fail",
    );
  }
});

Deno.test("worker synthetic email keeps full tenant entropy within RFC limits", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const samePrefixTenantId = "22222222-2222-4222-8222-333333333333";
  const maximumUsername = "a".repeat(32);

  const email = await buildWorkerLoginEmail(tenantId, maximumUsername);
  const repeatedEmail = await buildWorkerLoginEmail(
    tenantId,
    maximumUsername,
  );
  const otherTenantEmail = await buildWorkerLoginEmail(
    samePrefixTenantId,
    maximumUsername,
  );
  const [localPart, domain] = email.split("@");

  assertEquals(email, repeatedEmail, "synthetic identity must be deterministic");
  assertEquals(
    domain,
    "worker-login.invalid",
    "worker identities remain in the dedicated synthetic domain",
  );
  assert(
    localPart.startsWith(`wp-${tenantId.replaceAll("-", "")}-`),
    "the local part must retain all 128 tenant UUID bits",
  );
  assertEquals(
    localPart.length,
    63,
    "the longest accepted username must remain below the 64-byte local-part limit",
  );
  assert(
    email !== otherTenantEmail,
    "tenants sharing the old short prefix cannot collide",
  );
});

Deno.test("worker password reset marker records the complete issuance evidence", () => {
  const requiredAt = "2026-07-26T09:15:30.000Z";
  const issuedAt = "2026-07-26T09:15:31.000Z";
  assertEquals(
    buildWorkerPasswordResetMarker(requiredAt, issuedAt),
    {
      must_reset_password: true,
      password_reset_required_at: requiredAt,
      password_credential_issued_at: issuedAt,
      password_reset_challenge_started_at: null,
    },
    "new worker writes record a completed credential issue with no challenge",
  );
  assertEquals(
    buildWorkerPasswordResetMarker(requiredAt, null),
    {
      must_reset_password: true,
      password_reset_required_at: requiredAt,
      password_credential_issued_at: null,
      password_reset_challenge_started_at: null,
    },
    "phase one remains fail closed until Auth Admin succeeds",
  );
});

Deno.test("worker credential RPC helpers use exact tenant-scoped CAS arguments", async () => {
  const requiredAt = "2026-07-26T09:15:30.000Z";
  const issuedAt = "2026-07-26T09:15:31.000Z";
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return Promise.resolve({
        data: name.startsWith("begin_") ? requiredAt : issuedAt,
        error: null,
      });
    },
  };

  assertEquals(
    await beginWorkerPasswordCredentialIssue(client, "portal-1", "tenant-1"),
    requiredAt,
    "begin returns the database reset version",
  );
  assertEquals(
    await finishWorkerPasswordCredentialIssue(
      client,
      "portal-1",
      "tenant-1",
      requiredAt,
    ),
    issuedAt,
    "finish returns the database credential timestamp",
  );
  assertEquals(
    calls,
    [
      {
        name: "begin_worker_password_credential_issue",
        args: {
          p_portal_account_id: "portal-1",
          p_tenant_id: "tenant-1",
        },
      },
      {
        name: "finish_worker_password_credential_issue",
        args: {
          p_portal_account_id: "portal-1",
          p_tenant_id: "tenant-1",
          p_password_reset_required_at: requiredAt,
        },
      },
    ],
    "both service-role RPC calls remain tenant and version scoped",
  );

  const conflictClient = new FakeServiceClient();
  conflictClient.rpcResults.set("begin_worker_password_credential_issue", {
    data: null,
    error: { code: "P0001", message: "worker_access_conflict" },
  });
  await assertRejectsCode(
    () =>
      beginWorkerPasswordCredentialIssue(
        conflictClient,
        "portal-1",
        "tenant-1",
      ),
    "worker_access_conflict",
    "worker reactivation preserves the database ERP-access conflict",
  );
});

Deno.test("worker session revocation is exact, tenant-scoped and fail-closed", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return Promise.resolve({ data: 11, error: null });
    },
  };

  assertEquals(
    await revokeWorkerPortalSessions(client, "portal-1", "tenant-1"),
    11,
    "the helper returns the authoritative deleted-session count",
  );
  assertEquals(
    calls,
    [{
      name: "revoke_worker_portal_sessions",
      args: {
        p_portal_account_id: "portal-1",
        p_tenant_id: "tenant-1",
      },
    }],
    "session revocation must identify both portal account and tenant",
  );

  for (
    const result of [
      { data: null, error: null },
      { data: "11", error: null },
      { data: -1, error: null },
      { data: 1.5, error: null },
      { data: 0, error: { message: "database unavailable" } },
    ]
  ) {
    await assertRejectsCode(
      () =>
        revokeWorkerPortalSessions(
          { rpc: () => Promise.resolve(result) },
          "portal-1",
          "tenant-1",
        ),
      "worker_session_revocation_failed",
      "ambiguous or failed revocation cannot be reported as success",
    );
  }
});

Deno.test("worker reset brackets Auth password mutation with begin and finish", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const createFlow = source.slice(
    source.indexOf("async function createWorkerPortalAccount"),
    source.indexOf("async function resetWorkerPortalPassword"),
  );
  assert(
    createFlow.includes(
      "buildWorkerPasswordResetMarker(",
    ),
    "new worker creation must persist the complete issued credential marker",
  );
  const existingCreateFlow = createFlow.slice(
    createFlow.indexOf(
      "if (existingForEmployee) {",
      createFlow.indexOf("const basePayload"),
    ),
  );
  const existingCreateMarkerIndex = existingCreateFlow.indexOf(
    "beginWorkerPasswordCredentialIssue",
  );
  const existingCreateAuthIndex = existingCreateFlow.indexOf(
    "auth.admin.updateUserById",
  );
  const existingCreateRevocationIndex = existingCreateFlow.indexOf(
    "revokeWorkerPortalSessions",
  );
  const existingCreateFinishIndex = existingCreateFlow.indexOf(
    "finishWorkerPasswordCredentialIssue",
  );
  assert(
    existingCreateMarkerIndex >= 0 && existingCreateAuthIndex >= 0 &&
      existingCreateRevocationIndex >= 0 && existingCreateFinishIndex >= 0 &&
      existingCreateMarkerIndex < existingCreateAuthIndex &&
      existingCreateAuthIndex < existingCreateRevocationIndex &&
      existingCreateRevocationIndex < existingCreateFinishIndex,
    "recreating a worker must begin DB state, change Auth, revoke old sessions, then CAS-finish DB state",
  );

  const resetFlow = source.slice(
    source.indexOf("async function resetWorkerPortalPassword"),
    source.indexOf("async function setWorkerPortalAccess"),
  );
  const databaseMarkerIndex = resetFlow.indexOf(
    "beginWorkerPasswordCredentialIssue",
  );
  const authPasswordIndex = resetFlow.indexOf(
    "auth.admin.updateUserById",
  );
  const sessionRevocationIndex = resetFlow.indexOf(
    "revokeWorkerPortalSessions",
  );
  const databaseFinishIndex = resetFlow.indexOf(
    "finishWorkerPasswordCredentialIssue",
  );
  assert(
    databaseMarkerIndex >= 0 && authPasswordIndex >= 0 &&
      sessionRevocationIndex >= 0 && databaseFinishIndex >= 0 &&
      databaseMarkerIndex < authPasswordIndex &&
      authPasswordIndex < sessionRevocationIndex &&
      sessionRevocationIndex < databaseFinishIndex,
    "reset must begin DB state, change Auth, revoke old sessions, then CAS-finish DB state",
  );
  assert(
    resetFlow.includes('.eq("tenant_id", caller.tenantId)'),
    "the reset marker update must remain tenant scoped",
  );
  assert(
    resetFlow.includes('.select("id")') &&
      resetFlow.includes(".maybeSingle()"),
    "the reset must fail closed if the tenant account disappeared",
  );
  assert(
    !source.includes("must_reset_password: false"),
    "only the authenticated completion RPC may clear the reset requirement",
  );
});

Deno.test("worker suspension revokes sessions and reactivation requires a password", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  const account = {
    id: "55555555-5555-4555-8555-555555555555",
    employee_id: employeeId,
    auth_user_id: "66666666-6666-4666-8666-666666666666",
    username: "mecanico",
    login_email: "worker@example.invalid",
    is_active: true,
  };
  const caller = {
    userId: "33333333-3333-4333-8333-333333333333",
    tenantId,
    role: "admin",
    permissions: { manage_users: true },
  };
  const suspendedClient = new FakeServiceClient();
  suspendedClient.singleRows.set("employee_portal_accounts", account);
  suspendedClient.rpcResults.set("revoke_worker_portal_sessions", {
    data: 4,
    error: null,
  });

  assertEquals(
    await setWorkerPortalAccess(
      suspendedClient,
      caller,
      { employeeId, isActive: false },
    ),
    { success: true, authBanned: false, revokedSessions: 4 },
    "suspension reports the exact session revocation result",
  );
  assertEquals(
    suspendedClient.updates.map((update) => ({
      table: update.table,
      isActive: update.payload.is_active,
      filters: update.filters,
    })),
    [{
      table: "employee_portal_accounts",
      isActive: false,
      filters: [
        ["id", account.id],
        ["tenant_id", tenantId],
      ],
    }],
    "the portal is disabled in the caller tenant before revocation",
  );
  assertEquals(
    suspendedClient.rpcCalls,
    [{
      name: "revoke_worker_portal_sessions",
      args: {
        p_portal_account_id: account.id,
        p_tenant_id: tenantId,
      },
    }],
    "suspension revokes every Auth session through the scoped RPC",
  );

  const reactivationClient = new FakeServiceClient();
  reactivationClient.singleRows.set("employee_portal_accounts", {
    ...account,
    is_active: false,
  });
  await assertRejectsCode(
    () =>
      setWorkerPortalAccess(
        reactivationClient,
        caller,
        { employeeId, isActive: true },
      ),
    "worker_reactivation_requires_password",
    "a boolean toggle cannot reactivate a worker with an old credential",
  );
  assertEquals(
    reactivationClient.updates,
    [],
    "rejected reactivation cannot mutate the portal",
  );
  assertEquals(
    reactivationClient.rpcCalls,
    [],
    "rejected reactivation does not perform a misleading session operation",
  );
});

Deno.test("worker access status is tenant-scoped, redacted and identity-aware", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  const authUserId = "66666666-6666-4666-8666-666666666666";
  const client = new FakeServiceClient();
  client.singleRows.set("employees", { id: employeeId });
  client.singleRows.set("employee_portal_accounts", {
    employee_id: employeeId,
    auth_user_id: authUserId,
    username: "mecanico",
    login_email: "must-not-leak@example.invalid",
    is_active: true,
    must_reset_password: true,
    last_login_at: "2026-07-26T12:00:00.000Z",
  });
  client.authUsers.set(authUserId, {
    id: authUserId,
    app_metadata: {
      account_type: "worker_portal",
      tenant_id: tenantId,
      employee_id: employeeId,
      role: "worker",
    },
  });

  const result = await getWorkerPortalAccess(
    client,
    {
      userId: "33333333-3333-4333-8333-333333333333",
      tenantId,
      role: "admin",
      permissions: { manage_users: true },
    },
    { employeeId },
  );

  assertEquals(
    result,
    {
      employeeId,
      hasAccess: true,
      username: "mecanico",
      isActive: true,
      mustResetPassword: true,
      lastLoginAt: "2026-07-26T12:00:00.000Z",
      identityHealthy: true,
    },
    "the client receives only the operational worker access projection",
  );
  assert(
    !("authUserId" in result) &&
      !("loginEmail" in result) &&
      !JSON.stringify(result).includes("must-not-leak"),
    "Auth identity and synthetic email remain server-only",
  );
  assertEquals(
    client.reads.map((read) => ({
      table: read.table,
      filters: read.filters,
    })),
    [
      {
        table: "employees",
        filters: [
          ["id", employeeId],
          ["tenant_id", tenantId],
        ],
      },
      {
        table: "employee_portal_accounts",
        filters: [
          ["tenant_id", tenantId],
          ["employee_id", employeeId],
        ],
      },
    ],
    "both the employee and worker account reads stay in the caller tenant",
  );

  client.authUsers.set(authUserId, {
    id: authUserId,
    app_metadata: {
      account_type: "worker_portal",
      tenant_id: "77777777-7777-4777-8777-777777777777",
      employee_id: employeeId,
      role: "worker",
    },
  });
  const drifted = await getWorkerPortalAccess(
    client,
    {
      userId: "33333333-3333-4333-8333-333333333333",
      tenantId,
      role: "admin",
      permissions: { manage_users: true },
    },
    { employeeId },
  );
  assertEquals(
    drifted.identityHealthy,
    false,
    "metadata drift must disable credential-management actions",
  );
});

Deno.test("worker Auth metadata keeps tenant authority in app_metadata", () => {
  const metadata = buildWorkerAuthMetadata({
    tenantId: "22222222-2222-4222-8222-222222222222",
    employeeId: "44444444-4444-4444-8444-444444444444",
    username: "mecanico.uno",
    name: "Mecánico Uno",
  });

  assertEquals(
    metadata.appMetadata,
    {
      account_type: "worker_portal",
      tenant_id: "22222222-2222-4222-8222-222222222222",
      employee_id: "44444444-4444-4444-8444-444444444444",
      role: "worker",
    },
    "app_metadata must contain only authoritative worker claims",
  );
  assert(
    !Object.hasOwn(metadata.appMetadata, "username"),
    "mutable username cannot become an authorization claim",
  );
  assertEquals(
    metadata.userMetadata,
    {
      username: "mecanico.uno",
      name: "Mecánico Uno",
    },
    "user metadata contains display fields only",
  );
  assertEquals(
    sanitizeWorkerDisplayMetadata(
      {
        account_type: "worker_portal",
        tenant_id: "legacy-tenant",
        employee_id: "legacy-employee",
        role: "worker",
        invitation_token: "must-be-removed",
        locale: "es-CL",
      },
      metadata.userMetadata,
    ),
    {
      locale: "es-CL",
      username: "mecanico.uno",
      name: "Mecánico Uno",
    },
    "worker updates scrub legacy authority and capability data from user_metadata",
  );
});

Deno.test("worker Auth updates preserve shared identity and provider metadata", async () => {
  const authoritative = buildWorkerAuthMetadata({
    tenantId: "22222222-2222-4222-8222-222222222222",
    employeeId: "33333333-3333-4333-8333-333333333333",
    username: "mecanico",
    name: "Trabajador Compartido",
  }).appMetadata;
  const customerMemberships = {
    "44444444-4444-4444-8444-444444444444": "55555555-5555-4555-8555-555555555555",
  };

  assertEquals(
    mergeWorkerAppMetadata(
      {
        account_type: "public_store_customer",
        tenant_id: "wrong-tenant",
        employee_id: "wrong-employee",
        role: "customer",
        customer_memberships: customerMemberships,
        provider: "email",
        providers: ["email", "google"],
        provider_subject: "durable-provider-metadata",
      },
      authoritative,
    ),
    {
      account_type: "worker_portal",
      tenant_id: "22222222-2222-4222-8222-222222222222",
      employee_id: "33333333-3333-4333-8333-333333333333",
      role: "worker",
      customer_memberships: customerMemberships,
      provider: "email",
      providers: ["email", "google"],
      provider_subject: "durable-provider-metadata",
    },
    "shared memberships and provider metadata survive while worker authority wins",
  );

  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(
    source.match(/app_metadata: mergeWorkerAppMetadata/g)?.length ?? 0,
    3,
    "orphan retry, existing-worker recreation and password reset must merge app_metadata",
  );
  const newWorkerCreate = source.slice(
    source.indexOf("auth.admin.createUser"),
    source.indexOf("const basePayload"),
  );
  assert(
    newWorkerCreate.includes("app_metadata: metadata.appMetadata"),
    "a brand-new worker keeps a clean authoritative metadata payload",
  );
});

Deno.test("worker identity cannot be adopted from a squatted synthetic email", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  assertEquals(
    hasAuthoritativeWorkerIdentity(
      {
        user_metadata: {
          account_type: "worker_portal",
          tenant_id: tenantId,
          employee_id: employeeId,
          role: "worker",
        },
      },
      tenantId,
      employeeId,
    ),
    false,
    "user-controlled metadata cannot authorize worker reuse",
  );
  assertEquals(
    hasAuthoritativeWorkerIdentity(
      {
        app_metadata: {
          account_type: "worker_portal",
          tenant_id: tenantId,
          employee_id: employeeId,
          role: "worker",
        },
      },
      tenantId,
      employeeId,
    ),
    true,
    "server-owned exact claims authorize an already-linked worker identity",
  );

  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(
    source.includes('"worker_login_email_conflict"'),
    "pre-existing synthetic emails must become explicit conflicts",
  );
  assert(
    !source.includes("authUser ??= await findAuthUserByEmail(serviceClient, loginEmail)"),
    "a matching synthetic email alone can never be adopted",
  );
});

Deno.test("worker creation compensates only the exact newly-created Auth identity", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  const authUserId = "66666666-6666-4666-8666-666666666666";
  const loginEmail = "wp-tenant-worker@worker-login.invalid";
  const harness = workerSagaClient({
    insertError: { message: "insert failed" },
    authUser: {
      id: authUserId,
      email: loginEmail,
      app_metadata: {
        account_type: "worker_portal",
        tenant_id: tenantId,
        employee_id: employeeId,
        role: "worker",
      },
    },
  });

  await assertRejectsCode(
    () =>
      persistNewWorkerPortalAccount(
        harness.client,
        {
          payload: { tenant_id: tenantId },
          tenantId,
          employeeId,
          username: "mecanico",
          loginEmail,
          authUserId,
          createdAuthUserId: authUserId,
        },
      ),
    "worker_portal_account_create_failed",
    "a failed insert must report failure after successful compensation",
  );
  assertEquals(
    harness.deletedUserIds,
    [authUserId],
    "compensation deletes only the exact Auth id created by this invocation",
  );
});

Deno.test("worker create race preserves ERP conflict after exact Auth compensation", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  const authUserId = "66666666-6666-4666-8666-666666666666";
  const loginEmail = "wp-tenant-worker@worker-login.invalid";
  const harness = workerSagaClient({
    insertError: { code: "P0001", message: "worker_access_conflict" },
    authUser: {
      id: authUserId,
      email: loginEmail,
      app_metadata: {
        account_type: "worker_portal",
        tenant_id: tenantId,
        employee_id: employeeId,
        role: "worker",
      },
    },
  });

  await assertRejectsCode(
    () =>
      persistNewWorkerPortalAccount(
        harness.client,
        {
          payload: { tenant_id: tenantId },
          tenantId,
          employeeId,
          username: "mecanico",
          loginEmail,
          authUserId,
          createdAuthUserId: authUserId,
        },
      ),
    "worker_access_conflict",
    "a concurrent ERP reservation remains a stable worker conflict",
  );
  assertEquals(
    harness.deletedUserIds,
    [authUserId],
    "a rejected worker race compensates only its newly-created Auth identity",
  );
});

Deno.test("worker insert acknowledgement loss reconciles the exact link without deletion", async () => {
  const authUserId = "66666666-6666-4666-8666-666666666666";
  const harness = workerSagaClient({
    insertError: { message: "connection lost after commit" },
    linkedId: "77777777-7777-4777-8777-777777777777",
  });

  assertEquals(
    await persistNewWorkerPortalAccount(
      harness.client,
      {
        payload: {},
        tenantId: "22222222-2222-4222-8222-222222222222",
        employeeId: "44444444-4444-4444-8444-444444444444",
        username: "mecanico",
        loginEmail: "wp-tenant-worker@worker-login.invalid",
        authUserId,
        createdAuthUserId: authUserId,
      },
    ),
    "77777777-7777-4777-8777-777777777777",
    "an exact committed link is the authoritative success read-back",
  );
  assertEquals(
    harness.deletedUserIds,
    [],
    "an ACK-lost but committed link must preserve Auth",
  );
  assertEquals(
    harness.authReads,
    [],
    "successful reconciliation stops before compensation",
  );
});

Deno.test("worker compensation never deletes a pre-existing or mismatched identity", async () => {
  const baseInput = {
    payload: {},
    tenantId: "22222222-2222-4222-8222-222222222222",
    employeeId: "44444444-4444-4444-8444-444444444444",
    username: "mecanico",
    loginEmail: "wp-tenant-worker@worker-login.invalid",
    authUserId: "66666666-6666-4666-8666-666666666666",
  };
  const preExisting = workerSagaClient({
    insertError: { message: "insert failed" },
  });
  await assertRejectsCode(
    () =>
      persistNewWorkerPortalAccount(
        preExisting.client,
        { ...baseInput, createdAuthUserId: null },
      ),
    "worker_portal_account_create_failed",
    "a pre-existing retry identity is never compensation-owned",
  );
  assertEquals(
    preExisting.deletedUserIds,
    [],
    "pre-existing Auth is never deleted",
  );

  const mismatched = workerSagaClient({
    insertError: { message: "insert failed" },
    authUser: {
      id: baseInput.authUserId,
      email: baseInput.loginEmail,
      app_metadata: {
        account_type: "worker_portal",
        tenant_id: baseInput.tenantId,
        employee_id: "99999999-9999-4999-8999-999999999999",
        role: "worker",
      },
    },
  });
  await assertRejectsCode(
    () =>
      persistNewWorkerPortalAccount(
        mismatched.client,
        {
          ...baseInput,
          createdAuthUserId: baseInput.authUserId,
        },
      ),
    "worker_identity_reconciliation_required",
    "metadata drift blocks destructive compensation",
  );
  assertEquals(
    mismatched.deletedUserIds,
    [],
    "mismatched Auth metadata must fail closed without deletion",
  );
});

Deno.test("worker retry adopts only an exact orphan with zero memberships", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const employeeId = "44444444-4444-4444-8444-444444444444";
  const loginEmail = "wp-tenant-worker@worker-login.invalid";
  const orphan = {
    id: "66666666-6666-4666-8666-666666666666",
    email: loginEmail,
    app_metadata: {
      account_type: "worker_portal",
      tenant_id: tenantId,
      employee_id: employeeId,
      role: "worker",
    },
  };
  const clean = workerSagaClient({});
  assertEquals(
    await assertReusableWorkerOrphan(
      clean.client,
      orphan,
      tenantId,
      employeeId,
      loginEmail,
    ),
    orphan,
    "an exact unlinked orphan is safe to reuse on retry",
  );

  const linkedElsewhere = workerSagaClient({
    membershipTables: ["customers"],
  });
  await assertRejectsCode(
    () =>
      assertReusableWorkerOrphan(
        linkedElsewhere.client,
        orphan,
        tenantId,
        employeeId,
        loginEmail,
      ),
    "worker_login_email_conflict",
    "any existing membership makes orphan reuse unsafe",
  );
});

Deno.test("tenant administration deletes Auth only in isolated worker compensation", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(
    source.match(/\.deleteUser\(/g)?.length ?? 0,
    1,
    "only the worker-create compensation path may delete Auth",
  );
  const compensation = source.slice(
    source.indexOf("async function compensateNewWorkerAuthIdentity"),
    source.indexOf("async function getAuthMembershipCount"),
  );
  assert(
    compensation.includes("authUser.id !== userId") &&
      compensation.includes("hasAuthoritativeWorkerIdentity") &&
      compensation.includes("membershipCount !== 0") &&
      compensation.includes("auth.admin.deleteUser(userId)"),
    "compensation must prove exact identity and zero memberships before deletion",
  );
  assert(
    !source.includes("ban_duration:"),
    "tenant suspension, deletion, reset and recreation cannot ban or unban global Auth",
  );
});

Deno.test("global display metadata is blocked for shared identities", async () => {
  const userId = "11111111-1111-4111-8111-111111111111";
  const exclusiveClient = new FakeServiceClient();
  exclusiveClient.evidenceTables.add("user_profiles");
  await assertSingleAccountMembership(exclusiveClient, userId);

  const sharedClient = new FakeServiceClient();
  sharedClient.evidenceTables.add("user_profiles");
  sharedClient.evidenceTables.add("customers");
  let caught: unknown = null;
  try {
    await assertSingleAccountMembership(sharedClient, userId);
  } catch (error) {
    caught = error;
  }
  assert(caught instanceof Error, "shared global identity must fail closed");
  assertEquals(
    (caught as Error & { status?: number }).status,
    409,
    "shared identity must be an explicit conflict",
  );
});

Deno.test("customer Auth metadata contains display fields only", () => {
  const metadata = buildCustomerAuthMetadata({
    name: "Cliente Real",
    phone: null,
  });

  assertEquals(
    metadata,
    {
      userMetadata: {
        name: "Cliente Real",
        phone: null,
      },
    },
    "customer provisioning metadata cannot carry tenant or role claims",
  );
});

Deno.test("customerId provisioning rejects a mismatched body email before side effects", async () => {
  const harness = customerProvisioningClient();
  await assertRejectsCode(
    () =>
      createCustomerAccount(
        harness.client,
        {
          userId: "33333333-3333-4333-8333-333333333333",
          tenantId: "22222222-2222-4222-8222-222222222222",
          role: "admin",
          permissions: { manage_users: true },
        },
        {
          customerId: harness.customerId,
          email: "attacker@example.invalid",
        },
      ),
    "customer_email_mismatch",
    "a customer id cannot be provisioned with another Auth email",
  );
  assertEquals(
    harness.counts(),
    {
      invitationCount: 0,
      databaseMutationCount: 0,
      recoveryCount: 0,
    },
    "email mismatch must stop before invite, Auth delivery or database mutation",
  );
});

Deno.test("customerId provisioning accepts the exact canonical customer email", async () => {
  assertEquals(
    resolveCustomerProvisioningEmail(
      " CUSTOMER@example.invalid ",
      "customer@example.invalid",
    ),
    "customer@example.invalid",
    "the exact customer email comparison is normalized",
  );

  const harness = customerProvisioningClient();
  assertEquals(
    await createCustomerAccount(
      harness.client,
      {
        userId: "33333333-3333-4333-8333-333333333333",
        tenantId: "22222222-2222-4222-8222-222222222222",
        role: "admin",
        permissions: { manage_users: true },
      },
      {
        customerId: harness.customerId,
        email: "CUSTOMER@example.invalid",
        name: "Cliente",
      },
    ),
    {
      success: true,
      authUserId: harness.authUserId,
      customerId: harness.customerId,
      authLinked: true,
      inviteSent: false,
      verificationSent: false,
      passwordResetSent: true,
      accessEmailSent: true,
    },
    "an exact confirmed identity follows the normal recovery provisioning path",
  );
  assertEquals(
    harness.counts(),
    {
      invitationCount: 0,
      databaseMutationCount: 2,
      recoveryCount: 1,
    },
    "exact email provisioning updates the customer/order link and sends recovery",
  );
});

Deno.test("orphan website classification uses the customer membership map", () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const customerId = "55555555-5555-4555-8555-555555555555";

  assertEquals(
    isPublicStoreCustomerForTenant(
      {
        app_metadata: {
          account_type: "public_store_customer",
          customer_memberships: { [tenantId]: customerId },
        },
      },
      tenantId,
    ),
    true,
    "the canonical tenant membership classifies a customer-only identity",
  );
  assertEquals(
    isPublicStoreCustomerForTenant(
      {
        app_metadata: {
          account_type: "public_store_customer",
          customer_tenant_id: tenantId,
          role: "customer",
        },
      },
      tenantId,
    ),
    false,
    "obsolete single-tenant claims cannot classify an account",
  );
  assertEquals(
    isPublicStoreCustomerForTenant(
      {
        app_metadata: {
          account_type: "erp_staff",
          customer_memberships: { [tenantId]: customerId },
        },
      },
      tenantId,
    ),
    false,
    "a shared workforce identity is not a website-only orphan",
  );
  assertEquals(
    isPublicStoreCustomerForTenant(
      {
        app_metadata: {
          account_type: "public_store_customer",
          customer_memberships: {
            "77777777-7777-4777-8777-777777777777": customerId,
          },
        },
      },
      tenantId,
    ),
    false,
    "membership in a different tenant cannot leak into this overview",
  );
});

Deno.test("customer tenant authorization requires a database membership", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const userId = "11111111-1111-4111-8111-111111111111";
  const client = new FakeServiceClient();
  let caught: unknown = null;

  try {
    await assertUserBelongsToTenant(client, tenantId, userId);
  } catch (error) {
    caught = error;
  }
  assert(
    caught instanceof Error,
    "a forged or legacy metadata claim without a DB row must fail",
  );

  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const tenantAssertion = source.slice(
    source.indexOf("export async function assertUserBelongsToTenant"),
    source.indexOf("async function getCustomer"),
  );
  assert(
    !tenantAssertion.includes("isPublicStoreCustomerForTenant"),
    "metadata classification cannot authorize tenant membership",
  );
  const resetFlow = source.slice(
    source.indexOf("async function sendPasswordReset"),
    source.indexOf("async function sendRecoveryEmail"),
  );
  assert(
    !resetFlow.includes("isPublicStoreCustomerForTenant"),
    "password reset routing must use the tenant customer row",
  );
  assert(
    !source.includes("deleteOrphanWebsiteAuthAccount"),
    "metadata-only orphan classification cannot authorize global Auth deletion",
  );
});

Deno.test("customer link and email delivery wait for confirmation", async () => {
  assertEquals(
    selectAccessEmailDelivery({
      newlyInvited: true,
      emailConfirmedAt: null,
    }),
    "invite",
    "a newly created Auth identity uses only its initial invite",
  );
  assertEquals(
    selectAccessEmailDelivery({
      newlyInvited: false,
      emailConfirmedAt: null,
    }),
    "verification",
    "an existing unconfirmed Auth identity receives signup verification",
  );
  assertEquals(
    selectAccessEmailDelivery({
      newlyInvited: false,
      emailConfirmedAt: "2026-07-26T10:00:00.000Z",
    }),
    "recovery",
    "only an existing confirmed Auth identity receives password recovery",
  );
  assertEquals(
    accessEmailRedirect({
      delivery: "invite",
      isCustomer: true,
      erpOrigin: "https://erp.example",
      storeOrigin: "https://store.example",
    }),
    "https://store.example/cuenta/login?invited=true",
    "a new customer invite returns to password setup-aware login",
  );
  assertEquals(
    accessEmailRedirect({
      delivery: "verification",
      isCustomer: true,
      erpOrigin: "https://erp.example",
      storeOrigin: "https://store.example",
    }),
    "https://store.example/cuenta/login?confirmed=true",
    "customer verification returns to the exact storefront",
  );
  assertEquals(
    accessEmailRedirect({
      delivery: "verification",
      isCustomer: false,
      erpOrigin: "https://erp.example",
      storeOrigin: "https://store.example",
    }),
    "https://erp.example/auth/callback",
    "staff verification returns to the ERP Auth callback",
  );
  assertEquals(
    accessEmailRedirect({
      delivery: "recovery",
      isCustomer: true,
      erpOrigin: "https://erp.example",
      storeOrigin: "https://store.example",
    }),
    "https://store.example/cuenta/login?recovery=true",
    "confirmed customer recovery returns to the exact verified recovery route",
  );
  assertEquals(
    accessEmailRedirect({
      delivery: "recovery",
      isCustomer: false,
      erpOrigin: "https://erp.example",
      storeOrigin: "https://store.example",
    }),
    "https://erp.example/reset-password",
    "confirmed staff recovery returns to reset-password",
  );

  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const customerFlow = source.slice(
    source.indexOf("async function createCustomerAccount"),
    source.indexOf("async function setCustomerAccess"),
  );
  assert(
    !customerFlow.includes("app_metadata:"),
    "customer linking cannot overwrite global workforce or tenant app_metadata",
  );
  assert(
    !customerFlow.includes("updateUserById"),
    "an existing customer identity cannot receive global metadata changes from one tenant",
  );
  assert(
    !customerFlow.includes("customer_workforce_identity_conflict") &&
      !customerFlow.includes("hasAnyWorkforceMembership"),
    "a confirmed workforce identity may also acquire a customer membership",
  );
  assert(
    !customerFlow.includes("auth_user_id: authUser.id") &&
      customerFlow.includes("auth_user_id: expectedAuthUserId"),
    "new and unconfirmed identities cannot be linked prematurely",
  );
  assert(
    customerFlow.includes('.select("id, auth_user_id")') &&
      customerFlow.includes(".maybeSingle()") &&
      customerFlow.includes('"customer_link_state_mismatch"'),
    "the tenant row and exact Auth link state must be read back",
  );
  assert(
    customerFlow.includes("sendSignupVerificationEmail") &&
      customerFlow.includes('delivery === "recovery"'),
    "unconfirmed identities cannot receive a recovery email",
  );
});

Deno.test("generic access email never sends recovery to an unconfirmed identity", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const resetFlow = source.slice(
    source.indexOf("async function sendPasswordReset"),
    source.indexOf("async function sendRecoveryEmail"),
  );
  assert(
    resetFlow.includes("emailConfirmedAt: user.email_confirmed_at") &&
      resetFlow.includes('delivery === "verification"') &&
      resetFlow.includes("sendSignupVerificationEmail"),
    "the provider action must branch on authoritative confirmation state",
  );
  assert(
    resetFlow.includes("accessEmailSent: true") &&
      !resetFlow.includes("passwordResetSent"),
    "the response is generic and does not expose the account state",
  );
});

Deno.test("storefront Auth redirects reject tenant-controlled open redirects", () => {
  assertThrowsCode(
    () =>
      resolveTrustedStoreOrigin({
        customDomain: "https://attacker.example",
        publicStoreOrigins: "https://vinabike.cl",
      }),
    "store_origin_unavailable",
    "an unlisted custom domain must fail closed",
  );
  assertThrowsCode(
    () =>
      resolveTrustedStoreOrigin({
        customDomain: "trusted.example/path",
        publicStoreOrigins: "https://trusted.example",
      }),
    "store_origin_unavailable",
    "custom domains with paths cannot become Auth redirects",
  );
  assertEquals(
    resolveTrustedStoreOrigin({
      customDomain: "shop.example",
      publicStoreOrigins: "https://shop.example",
    }),
    "https://shop.example",
    "an exact environment-owned HTTPS origin is allowed",
  );
  assertEquals(
    resolveTrustedStoreOrigin({
      subdomain: "tenant-one",
      publicStoreBaseDomain: "stores.example",
    }),
    "https://tenant-one.stores.example",
    "a safe tenant label can use the controlled base domain",
  );
  assertThrowsCode(
    () =>
      resolveTrustedStoreOrigin({
        subdomain: "attacker.example/path",
        publicStoreBaseDomain: "stores.example",
      }),
    "store_origin_unavailable",
    "an injected tenant subdomain must fail closed",
  );
  assertThrowsCode(
    () =>
      resolveTrustedStoreOrigin({
        customDomain: "tenant-two.example",
        subdomain: "tenant-two",
      }),
    "store_origin_unavailable",
    "a non-Viñabike tenant without trusted environment config cannot receive Auth email",
  );
  assertEquals(
    resolveTrustedStoreOrigin({
      customDomain: "vinabike.cl",
      subdomain: "vinabike",
    }),
    "https://vinabike.cl",
    "the explicit Viñabike domain and unique slug keep the canonical fallback",
  );
  assertEquals(
    resolveTrustedStoreOrigin({
      subdomain: "vinabike",
    }),
    "https://vinabike.cl",
    "the explicit Viñabike tenant slug keeps the canonical fallback",
  );
  assertThrowsCode(
    () =>
      resolveTrustedStoreOrigin({
        customDomain: "vinabike.cl",
        subdomain: "tenant-two",
      }),
    "store_origin_unavailable",
    "a copied Viñabike custom domain cannot bypass the unique tenant slug",
  );
  assertThrowsCode(
    () =>
      resolveTrustedStoreOrigin({
        subdomain: "VINABIKE",
      }),
    "store_origin_unavailable",
    "a case-variant tenant slug cannot borrow the canonical fallback",
  );
  assertThrowsCode(
    () =>
      resolveTrustedStoreOrigin({
        customDomain: "https://attacker.example",
        subdomain: "vinabike",
      }),
    "store_origin_unavailable",
    "an untrusted explicit custom domain cannot borrow the Viñabike subdomain fallback",
  );
});

Deno.test("customer verification uses tenant customer email and storefront redirect", async () => {
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const customerId = "55555555-5555-4555-8555-555555555555";
  const reads: Array<{ table: string; filters: Array<[string, unknown]> }> = [];
  const resendCalls: unknown[] = [];
  const client = {
    auth: {
      resend: (payload: unknown) => {
        resendCalls.push(payload);
        return Promise.resolve({ data: null, error: null });
      },
    },
    from: (table: string) => {
      const filters: Array<[string, unknown]> = [];
      const query = {
        select: (_columns: string) => query,
        eq: (column: string, value: unknown) => {
          filters.push([column, value]);
          return query;
        },
        maybeSingle: () => {
          reads.push({ table, filters: [...filters] });
          if (table === "customers") {
            return Promise.resolve({
              data: {
                id: customerId,
                name: "Cliente",
                email: "customer@example.invalid",
                phone: null,
                is_active: true,
                auth_user_id: "66666666-6666-4666-8666-666666666666",
              },
              error: null,
            });
          }
          return Promise.resolve({
            data: { custom_domain: "vinabike.cl", subdomain: "vinabike" },
            error: null,
          });
        },
      };
      return query;
    },
  };

  const result = await resendCustomerVerification(
    client,
    {
      userId: "33333333-3333-4333-8333-333333333333",
      tenantId,
      role: "admin",
      permissions: { manage_users: true },
    },
    { customerId, email: "customer@example.invalid" },
    () => undefined,
  );

  assertEquals(
    result,
    { success: true, verificationSent: true },
    "verification response does not expose a link",
  );
  assertEquals(
    resendCalls,
    [{
      type: "signup",
      email: "customer@example.invalid",
      options: {
        emailRedirectTo: "https://vinabike.cl/cuenta/login?confirmed=true",
      },
    }],
    "provider receives exact customer email and storefront redirect",
  );
  const customerRead = reads.find((read) => read.table === "customers");
  assert(
    customerRead?.filters.some(([column, value]) => column === "tenant_id" && value === tenantId),
    "customer lookup remains scoped to the caller tenant",
  );
});

Deno.test("customer verification sends no email without a trusted tenant storefront", async () => {
  let resendCount = 0;
  const client = {
    auth: {
      resend: () => {
        resendCount += 1;
        return Promise.resolve({ data: null, error: null });
      },
    },
    from: (table: string) => {
      const query = {
        select: (_columns: string) => query,
        eq: (_column: string, _value: unknown) => query,
        maybeSingle: () =>
          Promise.resolve({
            data: table === "customers"
              ? {
                id: "55555555-5555-4555-8555-555555555555",
                name: "Cliente",
                email: "customer@example.invalid",
                phone: null,
                is_active: true,
                auth_user_id: null,
              }
              : {
                custom_domain: "tenant-two.example",
                subdomain: "tenant-two",
              },
            error: null,
          }),
      };
      return query;
    },
  };

  await assertRejectsCode(
    () =>
      resendCustomerVerification(
        client,
        {
          userId: "33333333-3333-4333-8333-333333333333",
          tenantId: "22222222-2222-4222-8222-222222222222",
          role: "admin",
          permissions: { manage_users: true },
        },
        {
          customerId: "55555555-5555-4555-8555-555555555555",
          email: "customer@example.invalid",
        },
        () => undefined,
      ),
    "store_origin_unavailable",
    "unconfigured non-Viñabike storefront must fail closed",
  );
  assertEquals(
    resendCount,
    0,
    "provider delivery cannot start before the storefront is trusted",
  );
});

Deno.test("admin API cannot confirm a real mailbox", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(
    !source.includes("case 'confirm_email'"),
    "confirm_email must remain unsupported",
  );
  assert(
    !source.includes("function confirmUserEmail"),
    "no administrative mailbox-confirmation helper may remain",
  );
  const customerFlow = source.slice(
    source.indexOf("async function createCustomerAccount"),
    source.indexOf("async function setCustomerAccess"),
  );
  assert(
    !customerFlow.includes("email_confirm:"),
    "customer provisioning cannot mark a real email as confirmed",
  );
});
