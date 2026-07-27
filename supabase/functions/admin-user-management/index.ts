import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const defaultAllowedOrigins = [
  "https://project-vinabike.web.app",
  "https://project-vinabike.firebaseapp.com",
  "http://localhost:54330",
  "http://127.0.0.1:54330",
] as const;

const firebasePreviewOrigin = /^https:\/\/project-vinabike--[a-z0-9-]+\.web\.app$/;

type SupabaseClient = any;
type EnvReader = (name: string) => string | undefined;

interface InvitationDeliveryOptions {
  fetchImpl?: typeof fetch;
  getEnv?: EnvReader;
}

interface RequestBody {
  action?: string;
  search?: string;
  userId?: string;
  customerId?: string;
  employeeId?: string;
  invitationId?: string;
  email?: string;
  name?: string;
  phone?: string;
  username?: string;
  role?: string;
  permissions?: Record<string, boolean>;
  isActive?: boolean;
  password?: string;
  deleteCustomerRecord?: boolean;
}

interface CallerContext {
  userId: string;
  tenantId: string;
  role: string;
  permissions: Record<string, unknown>;
  isPrincipalOwner?: boolean;
  tenantOwnerEmail?: string | null;
}

type StaffRole =
  | "admin"
  | "manager"
  | "cashier"
  | "accountant"
  | "mechanic";

type AuthorityRole = "owner" | StaffRole;

interface StaffTargetContext {
  userId: string;
  role: StaffRole;
  permissions: Record<string, unknown>;
  isActive: boolean;
  updatedAt: string;
  isPrincipalOwner: boolean;
}

export interface MessagingDeletionEvidence {
  hasEvidence: boolean;
  sources: string[];
}

export interface AccountDeletionResult {
  success: true;
  authDeleted: boolean;
  authBanned: boolean;
  authDetachedOnly: boolean;
  accountDeactivated: boolean;
  preservedForMessagingHistory: boolean;
  outcome:
    | "tenant_access_detached"
    | "deactivated_preserved_messaging_history";
  messagingEvidence: string[];
}

export type AccountDeletionScope = "internal" | "customer";

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly publicMessage: string,
  ) {
    super(publicMessage);
  }
}

const rolePermissions: Record<StaffRole, Record<string, boolean>> = {
  admin: {
    access_pos: true,
    create_invoices: true,
    edit_prices: true,
    delete_invoices: true,
    access_accounting: true,
    manage_users: true,
    edit_settings: true,
  },
  manager: {
    access_pos: true,
    create_invoices: true,
    edit_prices: true,
    delete_invoices: true,
    access_accounting: true,
    manage_users: true,
    edit_settings: true,
  },
  cashier: {
    access_pos: true,
    create_invoices: true,
    edit_prices: false,
    delete_invoices: false,
    access_accounting: false,
    manage_users: false,
    edit_settings: false,
  },
  mechanic: {
    access_pos: false,
    create_invoices: false,
    edit_prices: false,
    delete_invoices: false,
    access_accounting: false,
    manage_users: false,
    edit_settings: false,
  },
  accountant: {
    access_pos: false,
    create_invoices: false,
    edit_prices: false,
    delete_invoices: false,
    access_accounting: true,
    manage_users: false,
    edit_settings: false,
  },
};

const canonicalPermissionKeys = [
  "access_pos",
  "create_invoices",
  "edit_prices",
  "delete_invoices",
  "access_accounting",
  "manage_users",
  "edit_settings",
] as const;

const canonicalPermissionKeySet = new Set<string>(canonicalPermissionKeys);

const roleRank: Record<AuthorityRole, number> = {
  owner: 400,
  admin: 300,
  manager: 200,
  cashier: 100,
  accountant: 100,
  mechanic: 100,
};

export async function handler(req: Request) {
  const configuredOrigins = configuredCorsOrigins();
  const origin = req.headers.get("origin");
  const respond = (data: unknown, status = 200) => json(req, data, status, configuredOrigins);

  if (origin && !isAllowedCorsOrigin(origin, configuredOrigins)) {
    return respond(
      { error: "Origin not allowed", code: "origin_not_allowed" },
      403,
    );
  }

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(req, configuredOrigins),
    });
  }

  if (req.method !== "POST") {
    return respond({ error: "Method not allowed", code: "method_not_allowed" }, 405);
  }

  try {
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!/^Bearer\s+\S+$/i.test(authHeader)) {
      return respond({ error: "Authentication required", code: "invalid_session" }, 401);
    }
    const accessToken = authHeader.replace(/^Bearer\s+/i, "");

    const serviceClient = createClient(supabaseUrl, serviceRoleKey);
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const caller = await getCallerContext(
      userClient,
      serviceClient,
      accessToken,
    );
    const body = (await req.json()) as RequestBody;
    const action = body.action ?? "overview";

    switch (action) {
      case "overview":
        return respond(await getOverview(serviceClient, caller, body.search ?? ""));
      case "get_worker_portal_access":
        return respond(await getWorkerPortalAccess(serviceClient, caller, body));
      case "create_internal_invitation":
        return respond(
          await createInternalInvitation(serviceClient, caller, body, authHeader, req),
        );
      case "resend_internal_invitation":
        return respond(
          await sendInvitationEmail(
            serviceClient,
            caller,
            body.invitationId,
            authHeader,
            req,
          ),
        );
      case "cancel_internal_invitation":
        return respond(await cancelInternalInvitation(serviceClient, caller, body));
      case "update_internal_user":
        return respond(await updateInternalUser(serviceClient, caller, body));
      case "update_internal_identity":
        return respond(await updateInternalIdentity(serviceClient, caller, body));
      case "set_internal_access":
        return respond(await setInternalAccess(serviceClient, caller, body));
      case "delete_internal_account":
        return respond(
          await deleteInternalAccount(
            userClient,
            serviceClient,
            caller,
            body,
          ),
        );
      case "link_internal_user_employee":
        return respond(
          await linkInternalUserEmployee(
            userClient,
            serviceClient,
            caller,
            body,
          ),
        );
      case "unlink_internal_user_employee":
        return respond(
          await unlinkInternalUserEmployee(
            userClient,
            serviceClient,
            caller,
            body,
          ),
        );
      case "create_worker_portal_account":
        return respond(await createWorkerPortalAccount(serviceClient, caller, body));
      case "reset_worker_portal_password":
        return respond(await resetWorkerPortalPassword(serviceClient, caller, body));
      case "set_worker_portal_access":
        return respond(await setWorkerPortalAccess(serviceClient, caller, body));
      case "create_customer_account":
        return respond(await createCustomerAccount(serviceClient, caller, body));
      case "set_customer_access":
        return respond(await setCustomerAccess(serviceClient, caller, body));
      case "delete_customer_account":
        return respond(await deleteCustomerAccount(serviceClient, caller, body));
      case "resend_customer_verification":
        return respond(
          await resendCustomerVerification(serviceClient, caller, body),
        );
      case "send_password_reset":
        return respond(await sendPasswordReset(serviceClient, caller, body, req));
      default:
        return respond({ error: "Unsupported action", code: "unsupported_action" }, 400);
    }
  } catch (error) {
    const safeError = toHttpError(error);
    if (safeError.status >= 500) {
      console.error("admin-user-management request failed", { code: safeError.code });
    }
    return respond(
      { error: safeError.publicMessage, code: safeError.code },
      safeError.status,
    );
  }
}

if (import.meta.main) {
  Deno.serve(handler);
}

function toErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (error && typeof error === "object") {
    const record = error as Record<string, unknown>;
    for (const key of ["message", "error", "details", "msg"]) {
      const value = record[key];
      if (typeof value === "string" && value.trim().length > 0) return value;
      if (value && typeof value === "object") return toErrorMessage(value);
    }

    try {
      return JSON.stringify(error);
    } catch (_) {
      return String(error);
    }
  }
  return String(error);
}

function toHttpError(error: unknown): HttpError {
  if (error instanceof HttpError) return error;

  const message = toErrorMessage(error);
  const containsSensitiveValue =
    /https?:\/\/|[?&](?:token|code|access_token|refresh_token)=|[\w.+-]+@[\w.-]+\.[a-z]{2,}|\bBearer\s+\S+|\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|\b(?:token|secret|password|link)\b/i
      .test(message);
  const safeMessage = !containsSensitiveValue && message.length > 0 && message.length <= 240
    ? message
    : "Unable to complete account management";

  return new HttpError(500, "account_management_failed", safeMessage);
}

export async function getCallerContext(
  userClient: SupabaseClient,
  serviceClient: SupabaseClient,
  accessToken?: string,
): Promise<CallerContext> {
  const { data: userData, error: userError } = await userClient.auth.getUser(
    accessToken,
  );
  const user = userData?.user;

  if (userError || !user) {
    throw new HttpError(401, "invalid_session", "Authentication required");
  }

  const { data, error: profileError } = await serviceClient
    .from("user_profiles")
    .select(
      "tenant_id, role, permissions, tenants!inner(id, is_active, owner_email)",
    )
    .eq("user_id", user.id)
    .eq("is_active", true)
    .eq("tenants.is_active", true)
    .limit(2);

  if (profileError) {
    throw new HttpError(
      503,
      "authorization_unavailable",
      "Unable to verify account access",
    );
  }

  const profiles = Array.isArray(data) ? data : [];
  if (profiles.length !== 1) {
    throw new HttpError(
      403,
      "tenant_context_invalid",
      "A single active tenant is required",
    );
  }

  const profile = profiles[0];
  const tenantRelation = Array.isArray(profile.tenants) ? profile.tenants : [profile.tenants];
  const activeTenants = tenantRelation.filter((tenant: unknown) => {
    if (!tenant || typeof tenant !== "object") return false;
    const record = tenant as Record<string, unknown>;
    return record.id === profile.tenant_id && record.is_active === true;
  });
  if (
    typeof profile.tenant_id !== "string" ||
    profile.tenant_id.trim().length === 0 ||
    activeTenants.length !== 1
  ) {
    throw new HttpError(
      403,
      "tenant_context_invalid",
      "A valid active tenant is required",
    );
  }
  const callerRole = requireCanonicalStoredRole(profile.role);
  const permissions = profile.permissions &&
      typeof profile.permissions === "object" &&
      !Array.isArray(profile.permissions)
    ? profile.permissions as Record<string, unknown>
    : {};
  const tenant = activeTenants[0] as Record<string, unknown>;
  const tenantOwnerEmail = normalizeOptionalEmail(tenant.owner_email);
  const isPrincipalOwner = derivePrincipalOwnerIdentity({
    tenantId: profile.tenant_id,
    tenantOwnerEmail,
    authUser: user,
  });
  const canManage = isPrincipalOwner ||
    ["admin", "manager"].includes(callerRole) ||
    permissions.manage_users === true;

  if (!canManage) {
    throw new HttpError(
      403,
      "forbidden",
      "User management permission is required",
    );
  }

  return {
    userId: user.id,
    tenantId: profile.tenant_id,
    role: callerRole,
    permissions,
    isPrincipalOwner,
    tenantOwnerEmail,
  };
}

async function getOverview(serviceClient: SupabaseClient, caller: CallerContext, search: string) {
  const searchTerm = search.trim();
  const [
    staffUsers,
    invitations,
    customerAccounts,
    employeeAccessStates,
    summary,
  ] = await Promise.all([
    getStaffUsers(serviceClient, caller.tenantId),
    getPendingInvitations(serviceClient, caller.tenantId),
    getCustomerAccounts(serviceClient, caller.tenantId, searchTerm),
    getEmployeeAccessStates(serviceClient, caller.tenantId),
    getSummary(serviceClient, caller.tenantId),
  ]);

  return {
    staffUsers,
    invitations,
    customerAccounts,
    employeeAccessStates,
    summary,
  };
}

export async function getWorkerPortalAccess(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const employeeId = required(body.employeeId, "employeeId");
  const { data: employee, error: employeeError } = await serviceClient
    .from("employees")
    .select("id")
    .eq("id", employeeId)
    .eq("tenant_id", caller.tenantId)
    .maybeSingle();

  if (employeeError) {
    throw new HttpError(
      503,
      "employee_lookup_failed",
      "Unable to verify the employee",
    );
  }
  if (!employee) {
    throw new HttpError(
      404,
      "employee_not_found",
      "Employee not found in this tenant",
    );
  }

  const { data: account, error: accountError } = await serviceClient
    .from("employee_portal_accounts")
    .select(
      "employee_id, auth_user_id, username, is_active, must_reset_password, last_login_at",
    )
    .eq("tenant_id", caller.tenantId)
    .eq("employee_id", employeeId)
    .maybeSingle();

  if (accountError) {
    throw new HttpError(
      503,
      "worker_access_lookup_failed",
      "Unable to verify worker access",
    );
  }

  const authUser = account?.auth_user_id
    ? await getAuthUser(serviceClient, account.auth_user_id)
    : null;
  const identityHealthy = account == null ||
    (authUser != null &&
      hasAuthoritativeWorkerIdentity(authUser, caller.tenantId, employeeId));

  return {
    employeeId,
    hasAccess: account != null,
    username: account?.username ?? null,
    isActive: account?.is_active === true,
    mustResetPassword: account?.must_reset_password === true,
    lastLoginAt: account?.last_login_at ?? null,
    identityHealthy,
  };
}

async function getStaffUsers(serviceClient: SupabaseClient, tenantId: string) {
  const { data, error } = await serviceClient
    .from("user_profiles")
    .select("id, user_id, role, permissions, is_active, created_at, updated_at, employee_id")
    .eq("tenant_id", tenantId)
    .order("created_at", { ascending: false });

  if (error) throw error;

  const rows = data ?? [];
  return await Promise.all(rows.map(async (profile: any) => {
    const authUser = await getAuthUser(serviceClient, profile.user_id);
    const employee = profile.employee_id
      ? await getEmployeeName(serviceClient, profile.employee_id, tenantId)
      : null;

    return {
      kind: "staff",
      id: profile.user_id,
      profileId: profile.id,
      email: authUser?.email ?? "Sin email",
      displayName: getDisplayName(authUser) ?? employee ?? authUser?.email ?? "Usuario interno",
      role: profile.role,
      permissions: profile.permissions ?? {},
      isActive: profile.is_active !== false && !isBanned(authUser),
      profileActive: profile.is_active !== false,
      accessRestricted: profile.is_active === false || isBanned(authUser),
      emailConfirmed: Boolean(authUser?.email_confirmed_at),
      lastSignInAt: authUser?.last_sign_in_at ?? null,
      createdAt: authUser?.created_at ?? profile.created_at,
      employeeId: profile.employee_id,
      employeeName: employee,
      bannedUntil: authUser?.banned_until ?? null,
    };
  }));
}

export async function getEmployeeAccessStates(
  serviceClient: SupabaseClient,
  tenantId: string,
) {
  const [
    { data: employees, error: employeeError },
    { data: profiles, error: profileError },
    { data: workerAccounts, error: workerError },
    { data: invitations, error: invitationError },
  ] = await Promise.all([
    serviceClient
      .from("employees")
      .select("id, first_name, last_name, email, status, user_id")
      .eq("tenant_id", tenantId)
      .order("last_name")
      .order("first_name"),
    serviceClient
      .from("user_profiles")
      .select("user_id, employee_id, is_active")
      .eq("tenant_id", tenantId)
      .not("employee_id", "is", null),
    serviceClient
      .from("employee_portal_accounts")
      .select("employee_id, username, is_active")
      .eq("tenant_id", tenantId),
    serviceClient
      .from("user_invitations")
      .select("employee_id")
      .eq("tenant_id", tenantId)
      .eq("status", "pending")
      .not("employee_id", "is", null),
  ]);

  if (employeeError || profileError || workerError || invitationError) {
    throw new HttpError(
      503,
      "employee_access_lookup_failed",
      "Unable to load employee access state",
    );
  }

  const profileRows = Array.isArray(profiles) ? profiles : [];
  const workerRows = Array.isArray(workerAccounts) ? workerAccounts : [];
  const pendingEmployeeIds = new Set(
    (Array.isArray(invitations) ? invitations : [])
      .map((row: any) => row.employee_id)
      .filter((value: unknown): value is string => typeof value === "string" && value.length > 0),
  );

  return (Array.isArray(employees) ? employees : []).map((employee: any) => {
    const employeeProfiles = profileRows.filter((profile: any) =>
      profile.employee_id === employee.id
    );
    const exactProfile = employeeProfiles.find((profile: any) =>
      profile.user_id === employee.user_id
    ) ?? null;
    const activeProfiles = employeeProfiles.filter((profile: any) => profile.is_active === true);
    const worker = workerRows.find((account: any) => account.employee_id === employee.id) ?? null;
    const workerAccessActive = worker?.is_active === true;
    const hasPendingInvitation = pendingEmployeeIds.has(employee.id);
    const hasEmployeeSide = typeof employee.user_id === "string" &&
      employee.user_id.length > 0;
    const hasProfileSide = employeeProfiles.length > 0;
    const exactBidirectionalLink = hasEmployeeSide && exactProfile != null;
    const inconsistent = (
      (hasEmployeeSide || hasProfileSide) && !exactBidirectionalLink
    ) ||
      employeeProfiles.length > 1 ||
      activeProfiles.length > 1 ||
      (workerAccessActive && (hasEmployeeSide || hasProfileSide)) ||
      (hasPendingInvitation && (hasEmployeeSide || hasProfileSide || workerAccessActive));

    let linkState:
      | "available"
      | "pending_invitation"
      | "erp_linked"
      | "worker_active"
      | "worker_suspended"
      | "inconsistent";
    if (inconsistent) {
      linkState = "inconsistent";
    } else if (exactBidirectionalLink) {
      linkState = "erp_linked";
    } else if (workerAccessActive) {
      linkState = "worker_active";
    } else if (hasPendingInvitation) {
      linkState = "pending_invitation";
    } else if (worker) {
      linkState = "worker_suspended";
    } else {
      linkState = "available";
    }

    return {
      employeeId: employee.id,
      employeeName: `${employee.first_name ?? ""} ${employee.last_name ?? ""}`.trim(),
      email: employee.email ?? null,
      status: employee.status,
      erpUserId: employee.user_id ??
        (employeeProfiles.length === 1 ? employeeProfiles[0].user_id : null),
      erpProfileActive: exactProfile?.is_active === true,
      pendingInvitation: hasPendingInvitation,
      workerAccessExists: worker != null,
      workerAccessActive,
      workerUsername: worker?.username ?? null,
      linkState,
    };
  });
}

async function getPendingInvitations(serviceClient: SupabaseClient, tenantId: string) {
  const { data, error } = await serviceClient
    .from("user_invitations")
    .select("id, email, role, permissions, status, expires_at, created_at, metadata, employee_id")
    .eq("tenant_id", tenantId)
    .eq("status", "pending")
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data ?? [];
}

async function getCustomerAccounts(
  serviceClient: SupabaseClient,
  tenantId: string,
  search: string,
) {
  let query = serviceClient
    .from("customers")
    .select("id, name, email, phone, is_active, auth_user_id, created_at, updated_at")
    .eq("tenant_id", tenantId)
    .order("updated_at", { ascending: false });

  if (search.length > 0) {
    const escaped = search.replaceAll(",", " ");
    query = query.or(`name.ilike.%${escaped}%,email.ilike.%${escaped}%,phone.ilike.%${escaped}%`)
      .limit(120);
  } else {
    query = query.not("auth_user_id", "is", null).limit(120);
  }

  const { data, error } = await query;
  if (error) throw error;

  const rows = data ?? [];
  const customerAccounts = await Promise.all(rows.map(async (customer: any) => {
    const authUser = customer.auth_user_id
      ? await getAuthUser(serviceClient, customer.auth_user_id)
      : null;
    const isStaffAuthUser = authUser
      ? await isStaffUserInTenant(serviceClient, tenantId, authUser.id)
      : false;

    return {
      kind: "customer",
      id: customer.auth_user_id ?? customer.id,
      customerId: customer.id,
      authUserId: customer.auth_user_id,
      email: authUser?.email ?? customer.email ?? "",
      displayName: customer.name ?? getDisplayName(authUser) ?? customer.email ?? "Cliente web",
      phone: customer.phone,
      hasAuth: Boolean(customer.auth_user_id),
      hasCustomerProfile: true,
      isWebsiteOnlyAuth: false,
      isStaffAuthUser,
      isActive: customer.is_active !== false && !isBanned(authUser),
      customerActive: customer.is_active !== false,
      accessRestricted: customer.is_active === false || isBanned(authUser),
      emailConfirmed: Boolean(authUser?.email_confirmed_at),
      lastSignInAt: authUser?.last_sign_in_at ?? null,
      createdAt: authUser?.created_at ?? customer.created_at,
      updatedAt: customer.updated_at,
      bannedUntil: authUser?.banned_until ?? null,
    };
  }));

  const orphanWebsiteAccounts = await getOrphanWebsiteAuthAccounts(
    serviceClient,
    tenantId,
    search,
  );

  return [...orphanWebsiteAccounts, ...customerAccounts];
}

async function getOrphanWebsiteAuthAccounts(
  serviceClient: SupabaseClient,
  tenantId: string,
  search: string,
) {
  const linkedAuthIds = await getLinkedCustomerAuthIds(serviceClient, tenantId);
  const searchTerm = search.trim().toLowerCase();
  const accounts = [];
  let page = 1;

  while (page <= 10) {
    const { data, error } = await serviceClient.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;

    for (const user of data.users) {
      if (!isPublicStoreCustomerForTenant(user, tenantId)) continue;
      if (linkedAuthIds.has(user.id)) continue;

      const displayName = getDisplayName(user) ?? user.email ?? "Cliente web sin ficha CRM";
      const phone = user.user_metadata?.phone ?? null;
      const haystack = `${displayName} ${user.email ?? ""} ${phone ?? ""}`.toLowerCase();
      if (searchTerm && !haystack.includes(searchTerm)) continue;

      accounts.push({
        kind: "customer",
        id: user.id,
        customerId: null,
        authUserId: user.id,
        email: user.email ?? "",
        displayName,
        phone,
        hasAuth: true,
        hasCustomerProfile: false,
        isWebsiteOnlyAuth: true,
        isStaffAuthUser: false,
        isActive: !isBanned(user),
        customerActive: null,
        accessRestricted: isBanned(user),
        emailConfirmed: Boolean(user.email_confirmed_at),
        lastSignInAt: user.last_sign_in_at ?? null,
        createdAt: user.created_at,
        updatedAt: user.updated_at ?? user.created_at,
        bannedUntil: user.banned_until ?? null,
      });
    }

    if (data.users.length < 1000) break;
    page += 1;
  }

  return accounts;
}

async function getLinkedCustomerAuthIds(serviceClient: SupabaseClient, tenantId: string) {
  const { data, error } = await serviceClient
    .from("customers")
    .select("auth_user_id")
    .eq("tenant_id", tenantId)
    .not("auth_user_id", "is", null)
    .limit(10000);

  if (error) throw error;
  return new Set((data ?? []).map((row: any) => row.auth_user_id).filter(Boolean));
}

async function getSummary(serviceClient: SupabaseClient, tenantId: string) {
  const [
    staffCount,
    invitationCount,
    customerCount,
    linkedCustomerCount,
    orphanWebsiteAccountCount,
    workerPortalAccountCount,
  ] = await Promise.all([
    countRows(serviceClient, "user_profiles", tenantId),
    countRows(serviceClient, "user_invitations", tenantId, { status: "pending" }),
    countRows(serviceClient, "customers", tenantId),
    countRows(serviceClient, "customers", tenantId, { auth_user_id: "not-null" }),
    countOrphanWebsiteAuthAccounts(serviceClient, tenantId),
    safeCountRows(serviceClient, "employee_portal_accounts", tenantId),
  ]);

  return {
    staffCount,
    pendingInvitationCount: invitationCount,
    customerCount,
    linkedCustomerCount,
    orphanWebsiteAccountCount,
    workerPortalAccountCount,
  };
}

async function countOrphanWebsiteAuthAccounts(serviceClient: SupabaseClient, tenantId: string) {
  return (await getOrphanWebsiteAuthAccounts(serviceClient, tenantId, "")).length;
}

export async function createInternalInvitation(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  authHeader: string,
  req: Request,
) {
  const email = normalizeEmail(required(body.email, "email"));
  const { role, permissions } = authorizeStaffAssignment(
    caller,
    body.role ?? "cashier",
    body.permissions,
  );
  const employeeId = body.employeeId == null ? null : required(body.employeeId, "employeeId");
  await assertInvitationEmailNotActiveStaff(
    serviceClient,
    caller.tenantId,
    email,
  );
  if (employeeId) {
    await assertActiveEmployeeForInvitation(
      serviceClient,
      caller.tenantId,
      employeeId,
    );
  }

  const { data: existing, error: existingError } = await serviceClient
    .from("user_invitations")
    .select("id, role, permissions, employee_id")
    .eq("tenant_id", caller.tenantId)
    .eq("email", email)
    .eq("status", "pending")
    .maybeSingle();

  if (existingError) throw existingError;
  if (existing) {
    const storedAuthority = assertStoredInvitationAuthorityAllowed(
      caller,
      existing,
    );
    const storedEmployeeId = existing.employee_id == null
      ? null
      : typeof existing.employee_id === "string" &&
          existing.employee_id.trim().length > 0
      ? existing.employee_id
      : undefined;
    if (
      storedEmployeeId === undefined ||
      storedAuthority.role !== role ||
      !sameCanonicalPermissions(storedAuthority.permissions, permissions) ||
      storedEmployeeId !== employeeId
    ) {
      throw new HttpError(
        409,
        "pending_invitation_exists",
        "A pending invitation already exists with different access",
      );
    }
  }

  let invitationId = existing?.id;
  if (!invitationId) {
    if (employeeId) {
      const { data: employeeInvitation, error: employeeInvitationError } = await serviceClient
        .from("user_invitations")
        .select("id")
        .eq("tenant_id", caller.tenantId)
        .eq("employee_id", employeeId)
        .eq("status", "pending")
        .maybeSingle();
      if (employeeInvitationError) {
        throw new HttpError(
          503,
          "invitation_lookup_failed",
          "Unable to verify pending employee invitations",
        );
      }
      if (employeeInvitation) {
        throw new HttpError(
          409,
          "pending_invitation_exists",
          "A pending invitation already exists for this employee",
        );
      }
    }

    const { data, error } = await serviceClient
      .from("user_invitations")
      .insert({
        tenant_id: caller.tenantId,
        email,
        role,
        permissions,
        invited_by: caller.userId,
        status: "pending",
        employee_id: employeeId,
        expires_at: addDays(7),
        metadata: {
          first_name: body.name?.trim() || email.split("@")[0],
          last_name: "",
          invited_from: "settings_user_management",
        },
      })
      .select("id")
      .single();

    if (error) throw mapEmployeeAccessError(error);
    invitationId = data.id;
  }

  const emailResult = await sendInvitationEmail(
    serviceClient,
    caller,
    invitationId,
    authHeader,
    req,
  );
  return emailResult;
}

export async function assertInvitationEmailNotActiveStaff(
  serviceClient: SupabaseClient,
  tenantId: string,
  email: string,
) {
  let authUser: any;
  try {
    authUser = await findAuthUserByEmail(serviceClient, email);
  } catch {
    throw new HttpError(
      503,
      "staff_identity_lookup_failed",
      "Unable to verify whether this email already has ERP access",
    );
  }
  if (!authUser?.id) return;

  const [
    { data: profileMemberships, error: profileError },
    { data: workerMemberships, error: workerError },
    { data: employeeMemberships, error: employeeError },
  ] = await Promise.all([
    serviceClient
      .from("user_profiles")
      .select("tenant_id, is_active")
      .eq("user_id", authUser.id)
      .limit(100),
    serviceClient
      .from("employee_portal_accounts")
      .select("tenant_id, is_active")
      .eq("auth_user_id", authUser.id)
      .limit(100),
    serviceClient
      .from("employees")
      .select("id, tenant_id")
      .eq("user_id", authUser.id)
      .limit(100),
  ]);

  if (profileError || workerError || employeeError) {
    throw new HttpError(
      503,
      "staff_identity_lookup_failed",
      "Unable to verify whether this email already has ERP access",
    );
  }
  const memberships = Array.isArray(profileMemberships) ? profileMemberships : [];
  if (
    (
      Array.isArray(workerMemberships) &&
      workerMemberships.length > 0
    ) ||
    (
      Array.isArray(employeeMemberships) &&
      employeeMemberships.length > 0
    )
  ) {
    console.warn("Invitation identity unavailable", {
      reason: Array.isArray(workerMemberships) &&
          workerMemberships.length > 0
        ? "worker_identity"
        : "historical_employee_identity",
    });
    throw new HttpError(
      409,
      "identity_unavailable",
      "This identity is unavailable for a new ERP invitation",
    );
  }
  if (
    memberships.some((membership: any) => membership.tenant_id !== tenantId)
  ) {
    console.warn("Invitation identity unavailable", {
      reason: "external_erp_membership",
    });
    throw new HttpError(
      409,
      "identity_unavailable",
      "This identity is unavailable for a new ERP invitation",
    );
  }
  if (
    memberships.some((membership: any) =>
      membership.tenant_id === tenantId && membership.is_active === true
    )
  ) {
    throw new HttpError(
      409,
      "active_staff_email_requires_direct_link",
      "This email already has active ERP access; use the employee link action",
    );
  }
  if (
    memberships.some((membership: any) =>
      membership.tenant_id === tenantId && membership.is_active === false
    )
  ) {
    throw new HttpError(
      409,
      "staff_membership_inactive",
      "This email has suspended ERP access; reactivate or detach that membership",
    );
  }
  if (memberships.length > 0) {
    console.warn("Invitation identity unavailable", {
      reason: "external_erp_history",
    });
    throw new HttpError(
      409,
      "identity_unavailable",
      "This identity is unavailable for a new ERP invitation",
    );
  }
}

export async function assertActiveEmployeeForInvitation(
  serviceClient: SupabaseClient,
  tenantId: string,
  employeeId: string,
) {
  const { data, error } = await serviceClient
    .from("employees")
    .select("id, user_id")
    .eq("id", employeeId)
    .eq("tenant_id", tenantId)
    .eq("status", "active")
    .maybeSingle();

  if (error) {
    throw new HttpError(
      503,
      "employee_lookup_failed",
      "Unable to verify the invitation employee",
    );
  }
  if (!data) {
    throw new HttpError(
      404,
      "employee_not_found",
      "Active employee not found in this tenant",
    );
  }

  const [
    { data: workerAccount, error: workerError },
    { data: profileLinks, error: profileError },
  ] = await Promise.all([
    serviceClient
      .from("employee_portal_accounts")
      .select("id")
      .eq("employee_id", employeeId)
      .eq("tenant_id", tenantId)
      .eq("is_active", true)
      .maybeSingle(),
    serviceClient
      .from("user_profiles")
      .select("id")
      .eq("employee_id", employeeId)
      .eq("tenant_id", tenantId)
      .limit(1),
  ]);

  if (workerError || profileError) {
    throw new HttpError(
      503,
      "employee_access_lookup_failed",
      "Unable to verify employee access",
    );
  }
  if (workerAccount) {
    throw new HttpError(
      409,
      "worker_access_conflict",
      "The employee already has active worker access",
    );
  }
  if (
    typeof data.user_id === "string" ||
    (Array.isArray(profileLinks) && profileLinks.length > 0)
  ) {
    throw new HttpError(
      409,
      "employee_erp_link_conflict",
      "The employee is already linked to an ERP user",
    );
  }

  return data;
}

export async function sendInvitationEmail(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  invitationId: string | undefined,
  authHeader: string,
  req: Request,
  options: InvitationDeliveryOptions = {},
) {
  if (!invitationId?.trim()) {
    throw new HttpError(400, "invalid_invitation", "A valid invitation is required");
  }

  const normalizedInvitationId = invitationId.trim();
  const invitation = await assertPendingInvitationInTenant(
    serviceClient,
    caller.tenantId,
    normalizedInvitationId,
  );
  assertStoredInvitationAuthorityAllowed(caller, invitation);

  const getEnv = options.getEnv ?? ((name: string) => Deno.env.get(name));
  const fetchImpl = options.fetchImpl ?? fetch;
  const supabaseUrl = requiredEnvFrom(getEnv, "SUPABASE_URL");
  const anonKey = requiredEnvFrom(getEnv, "SUPABASE_ANON_KEY");
  const headers = new Headers({
    Authorization: authHeader,
    apikey: anonKey,
    "Content-Type": "application/json",
  });
  const origin = req.headers.get("origin");
  if (origin) headers.set("origin", origin);

  const response = await fetchImpl(`${supabaseUrl}/functions/v1/send-invitation`, {
    method: "POST",
    headers,
    body: JSON.stringify({ invitationId: normalizedInvitationId }),
  });

  const data = await response.json().catch(() => ({}));
  if (
    response.status === 429 &&
    data?.code === "invitation_rate_limited"
  ) {
    throw new HttpError(
      429,
      "invitation_rate_limited",
      "Please wait before sending this invitation again",
    );
  }
  if (!response.ok || data?.success !== true || data?.emailSent !== true) {
    throw new HttpError(
      502,
      "invitation_delivery_failed",
      "The invitation email could not be delivered",
    );
  }

  return {
    success: true,
    emailSent: true,
    invitationId: normalizedInvitationId,
    expiresAt: typeof data?.expiresAt === "string" ? data.expiresAt : null,
  };
}

export async function assertPendingInvitationInTenant(
  serviceClient: SupabaseClient,
  tenantId: string,
  invitationId: string,
) {
  const { data, error } = await serviceClient
    .from("user_invitations")
    .select("id, role, permissions")
    .eq("id", invitationId)
    .eq("tenant_id", tenantId)
    .eq("status", "pending")
    .maybeSingle();

  if (error) {
    throw new HttpError(
      503,
      "invitation_lookup_failed",
      "Unable to verify the invitation",
    );
  }
  if (!data) {
    throw new HttpError(404, "invitation_not_found", "Invitation not found");
  }
  return data;
}

async function cancelInternalInvitation(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const invitationId = required(body.invitationId, "invitationId");
  const invitation = await assertPendingInvitationInTenant(
    serviceClient,
    caller.tenantId,
    invitationId,
  );
  assertStoredInvitationAuthorityAllowed(caller, invitation);
  const { data, error } = await serviceClient
    .from("user_invitations")
    .update({ status: "expired" })
    .eq("id", invitationId)
    .eq("tenant_id", caller.tenantId)
    .eq("status", "pending")
    .eq("role", invitation.role)
    .select("id")
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    throw new HttpError(404, "invitation_not_found", "Invitation not found");
  }
  return { success: true };
}

export async function updateInternalUser(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const userId = required(body.userId, "userId");
  if (userId === caller.userId) {
    throw new HttpError(
      403,
      "self_role_change_forbidden",
      "You cannot change your own role or permissions",
    );
  }
  const target = await getStaffTargetContext(
    serviceClient,
    caller,
    userId,
  );
  assertStaffTargetMutationAllowed(caller, target);
  const { role, permissions } = authorizeStaffAssignment(
    caller,
    body.role ?? target.role,
    body.permissions,
  );

  const { data, error } = await serviceClient
    .from("user_profiles")
    .update({ role, permissions, updated_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("tenant_id", caller.tenantId)
    .eq("role", target.role)
    .eq("is_active", target.isActive)
    .eq("updated_at", target.updatedAt)
    .select("user_id")
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    throw new HttpError(
      404,
      "staff_user_not_found",
      "Staff user not found in this tenant",
    );
  }
  return { success: true };
}

async function updateInternalIdentity(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const userId = required(body.userId, "userId");
  const name = required(body.name, "name");
  const target = await getStaffTargetContext(
    serviceClient,
    caller,
    userId,
  );
  assertStaffTargetMutationAllowed(caller, target);
  await assertSingleAccountMembership(serviceClient, userId);

  const authUser = await getAuthUser(serviceClient, userId);
  const { error } = await serviceClient.auth.admin.updateUserById(userId, {
    user_metadata: {
      ...(authUser?.user_metadata ?? {}),
      full_name: name,
      name,
      display_name: name,
    },
  });

  if (error) throw error;
  return { success: true };
}

async function setInternalAccess(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const userId = required(body.userId, "userId");
  const isActive = body.isActive === true;
  if (userId === caller.userId && !isActive) {
    throw new HttpError(
      403,
      "self_deactivation_forbidden",
      "You cannot suspend your own account",
    );
  }

  const target = await getStaffTargetContext(
    serviceClient,
    caller,
    userId,
  );
  assertStaffTargetMutationAllowed(caller, target);
  const { data, error } = await serviceClient
    .from("user_profiles")
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("tenant_id", caller.tenantId)
    .eq("role", target.role)
    .eq("is_active", target.isActive)
    .eq("updated_at", target.updatedAt)
    .select("user_id")
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    throw new HttpError(
      409,
      "staff_state_changed",
      "Staff account authority changed; retry the operation",
    );
  }
  return { success: true, authBanned: false };
}

export async function deleteInternalAccount(
  userClient: SupabaseClient,
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const userId = required(body.userId, "userId");
  if (userId === caller.userId) {
    throw new HttpError(
      403,
      "self_detach_forbidden",
      "You cannot detach your own account",
    );
  }

  const target = await getStaffTargetContext(
    serviceClient,
    caller,
    userId,
  );
  assertStaffTargetMutationAllowed(caller, target);

  const messagingEvidence = await getMessagingDeletionEvidence(serviceClient, userId);
  const { data: detachResult, error: detachError } = await userClient.rpc(
    "deactivate_and_unlink_erp_user",
    {
      p_user_id: userId,
      p_tenant_id: caller.tenantId,
    },
  );
  if (detachError) throw mapEmployeeAccessError(detachError);
  requireEmployeeDetachResult(detachResult, userId);

  return messagingEvidence.hasEvidence
    ? preservedMessagingHistoryResult(messagingEvidence)
    : detachedAccountResult();
}

export async function linkInternalUserEmployee(
  userClient: SupabaseClient,
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const userId = required(body.userId, "userId");
  const employeeId = required(body.employeeId, "employeeId");
  const target = await getStaffTargetContext(
    serviceClient,
    caller,
    userId,
  );
  assertEmployeeLinkTargetAllowed(caller, target);
  if (!target.isActive) {
    throw new HttpError(
      409,
      "employee_erp_link_conflict",
      "Only an active ERP user can be linked to an employee",
    );
  }

  const { data, error } = await userClient.rpc(
    "link_erp_user_to_employee",
    {
      p_user_id: userId,
      p_employee_id: employeeId,
    },
  );
  if (error) throw mapEmployeeAccessError(error);

  return requireEmployeeLinkResult(data, {
    userId,
    employeeId,
    linked: true,
  });
}

export async function unlinkInternalUserEmployee(
  userClient: SupabaseClient,
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const userId = required(body.userId, "userId");
  const employeeId = required(body.employeeId, "employeeId");
  const target = await getStaffTargetContext(
    serviceClient,
    caller,
    userId,
  );
  assertEmployeeLinkTargetAllowed(caller, target);

  const { data, error } = await userClient.rpc(
    "unlink_erp_user_from_employee",
    {
      p_user_id: userId,
      p_employee_id: employeeId,
    },
  );
  if (error) throw mapEmployeeAccessError(error);

  return requireEmployeeLinkResult(data, {
    userId,
    employeeId,
    linked: false,
  });
}

function requireEmployeeLinkResult(
  value: unknown,
  expected: {
    userId: string;
    employeeId: string;
    linked: boolean;
  },
) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    throw new HttpError(
      503,
      "employee_erp_link_unverified",
      "Unable to verify the ERP employee link",
    );
  }

  const result = value as Record<string, unknown>;
  if (
    result.success !== true ||
    result.linked !== expected.linked ||
    result.userId !== expected.userId ||
    result.employeeId !== expected.employeeId
  ) {
    throw new HttpError(
      503,
      "employee_erp_link_unverified",
      "Unable to verify the ERP employee link",
    );
  }

  return {
    success: true,
    linked: expected.linked,
    userId: expected.userId,
    employeeId: expected.employeeId,
  };
}

function requireEmployeeDetachResult(
  value: unknown,
  expectedUserId: string,
) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    throw new HttpError(
      503,
      "employee_access_detach_unverified",
      "Unable to verify tenant access removal",
    );
  }
  const result = value as Record<string, unknown>;
  if (
    result.success !== true ||
    result.deactivated !== true ||
    typeof result.unlinked !== "boolean" ||
    result.userId !== expectedUserId ||
    !(
      result.employeeId === null ||
      typeof result.employeeId === "string"
    )
  ) {
    throw new HttpError(
      503,
      "employee_access_detach_unverified",
      "Unable to verify tenant access removal",
    );
  }
  return result;
}

export function mapEmployeeAccessError(error: unknown): HttpError {
  const message = toErrorMessage(error);
  const record = error && typeof error === "object" ? error as Record<string, unknown> : {};
  const databaseCode = typeof record.code === "string" ? record.code : "";
  const constraint = typeof record.constraint === "string" ? record.constraint : "";
  const evidence = `${message} ${databaseCode} ${constraint}`;

  if (evidence.includes("worker_access_conflict")) {
    return new HttpError(
      409,
      "worker_access_conflict",
      "The employee already has active worker access",
    );
  }
  if (evidence.includes("worker_identity_conflict")) {
    return new HttpError(
      409,
      "worker_identity_conflict",
      "This Auth identity belongs to the Worker portal",
    );
  }
  if (
    evidence.includes("employee_erp_link_conflict") ||
    evidence.includes("employees_one_erp_user_uidx") ||
    evidence.includes("user_profiles_one_erp_employee_uidx") ||
    evidence.includes("user_invitations_one_pending_employee_uidx")
  ) {
    return new HttpError(
      409,
      "employee_erp_link_conflict",
      "The ERP user or employee already has another access link",
    );
  }
  if (
    evidence.includes("employee_erp_link_state_changed") ||
    evidence.includes("employee_erp_link_inconsistent")
  ) {
    return new HttpError(
      409,
      "employee_erp_link_state_changed",
      "The ERP employee link changed; reload and retry",
    );
  }
  if (evidence.includes("employee_not_found")) {
    return new HttpError(
      404,
      "employee_not_found",
      "Active employee not found in this tenant",
    );
  }
  if (evidence.includes("staff_user_not_found")) {
    return new HttpError(
      404,
      "staff_user_not_found",
      "Active ERP user not found in this tenant",
    );
  }
  if (evidence.includes("principal_owner_protected")) {
    return new HttpError(
      403,
      "principal_owner_protected",
      "Only the tenant principal can change their own employee link",
    );
  }
  if (evidence.includes("staff_hierarchy_forbidden")) {
    return new HttpError(
      403,
      "staff_hierarchy_forbidden",
      "You cannot change that staff account",
    );
  }
  if (databaseCode === "42501") {
    return new HttpError(
      403,
      "forbidden",
      "User management permission is required",
    );
  }

  return new HttpError(
    503,
    "employee_access_update_failed",
    "Unable to update employee access",
  );
}

async function createWorkerPortalAccount(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const employeeId = required(body.employeeId, "employeeId");
  const username = normalizeWorkerUsername(required(body.username, "username"));
  const password = requireStrongAdminPassword(body.password);
  const employee = await getEmployeeForPortal(serviceClient, caller.tenantId, employeeId);
  const loginEmail = await buildWorkerLoginEmail(caller.tenantId, username);

  const { data: existingRows, error: existingError } = await serviceClient
    .from("employee_portal_accounts")
    .select("id, employee_id, auth_user_id, username, login_email, is_active")
    .eq("tenant_id", caller.tenantId)
    .or(`employee_id.eq.${employeeId},username.eq.${username}`);

  if (existingError) throw existingError;

  const rows = existingRows ?? [];
  const usernameConflict = rows.find((row: any) =>
    row.username === username && row.employee_id !== employeeId
  );
  if (usernameConflict) {
    throw new Error("Ese nombre de usuario ya esta asignado a otro trabajador");
  }

  const existingForEmployee = rows.find((row: any) => row.employee_id === employeeId) ?? null;
  let authUser = null;
  let createdAuthUserId: string | null = null;
  let reusedOrphanAuth = false;
  if (existingForEmployee?.auth_user_id) {
    authUser = await getAuthUser(serviceClient, existingForEmployee.auth_user_id);
    if (
      !authUser ||
      !hasAuthoritativeWorkerIdentity(authUser, caller.tenantId, employeeId)
    ) {
      throw new HttpError(
        409,
        "worker_identity_conflict",
        "The worker login identity cannot be safely reused",
      );
    }
  } else {
    const existingAuthUser = await findAuthUserByEmail(
      serviceClient,
      loginEmail,
    );
    if (existingAuthUser) {
      authUser = await assertReusableWorkerOrphan(
        serviceClient,
        existingAuthUser,
        caller.tenantId,
        employeeId,
        loginEmail,
      );
      reusedOrphanAuth = true;
    }
  }

  const metadata = buildWorkerAuthMetadata({
    tenantId: caller.tenantId,
    employeeId,
    username,
    name: `${employee.first_name ?? ""} ${employee.last_name ?? ""}`.trim(),
  });

  if (!authUser) {
    const { data, error } = await serviceClient.auth.admin.createUser({
      email: loginEmail,
      password,
      email_confirm: true,
      user_metadata: metadata.userMetadata,
      app_metadata: metadata.appMetadata,
    });
    if (error) throw error;
    authUser = data.user;
    if (
      !authUser ||
      typeof authUser.id !== "string" ||
      authUser.id.trim().length === 0
    ) {
      throw new HttpError(
        502,
        "worker_auth_create_failed",
        "The worker login identity could not be created",
      );
    }
    createdAuthUserId = authUser.id;
  } else if (reusedOrphanAuth) {
    const { error } = await serviceClient.auth.admin.updateUserById(
      authUser.id,
      {
        email: loginEmail,
        password,
        email_confirm: true,
        user_metadata: sanitizeWorkerDisplayMetadata(
          authUser.user_metadata,
          metadata.userMetadata,
        ),
        app_metadata: mergeWorkerAppMetadata(
          authUser.app_metadata,
          metadata.appMetadata,
        ),
      },
    );
    if (error) {
      throw new HttpError(
        503,
        "worker_orphan_reuse_failed",
        "The worker login identity could not be reconciled",
      );
    }
  }

  const basePayload = {
    tenant_id: caller.tenantId,
    employee_id: employeeId,
    auth_user_id: authUser.id,
    username,
    login_email: loginEmail,
    is_active: true,
  };

  let portalAccountId: string;
  if (existingForEmployee) {
    const passwordResetRequiredAt = await beginWorkerPasswordCredentialIssue(
      serviceClient,
      existingForEmployee.id,
      caller.tenantId,
    );
    const { data, error } = await serviceClient
      .from("employee_portal_accounts")
      .update({
        ...basePayload,
        updated_at: passwordResetRequiredAt,
      })
      .eq("id", existingForEmployee.id)
      .eq("tenant_id", caller.tenantId)
      .select("id")
      .single();
    if (error) throw error;
    portalAccountId = data.id;

    const { error: authError } = await serviceClient.auth.admin.updateUserById(
      authUser.id,
      {
        email: loginEmail,
        password,
        email_confirm: true,
        user_metadata: sanitizeWorkerDisplayMetadata(
          authUser.user_metadata,
          metadata.userMetadata,
        ),
        app_metadata: mergeWorkerAppMetadata(
          authUser.app_metadata,
          metadata.appMetadata,
        ),
      },
    );
    if (authError) throw authError;

    await revokeWorkerPortalSessions(
      serviceClient,
      existingForEmployee.id,
      caller.tenantId,
    );
    await finishWorkerPasswordCredentialIssue(
      serviceClient,
      existingForEmployee.id,
      caller.tenantId,
      passwordResetRequiredAt,
    );
  } else {
    const passwordResetRequiredAt = new Date().toISOString();
    portalAccountId = await persistNewWorkerPortalAccount(
      serviceClient,
      {
        payload: {
          ...basePayload,
          ...buildWorkerPasswordResetMarker(
            passwordResetRequiredAt,
            passwordResetRequiredAt,
          ),
          created_by: caller.userId,
          updated_at: passwordResetRequiredAt,
        },
        tenantId: caller.tenantId,
        employeeId,
        username,
        loginEmail,
        authUserId: authUser.id,
        createdAuthUserId,
      },
    );
  }

  return {
    success: true,
    portalAccountId,
    authUserId: authUser.id,
    employeeId,
    username,
    passwordConfigured: true,
  };
}

async function resetWorkerPortalPassword(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const account = await getWorkerPortalAccount(serviceClient, caller.tenantId, body);
  if (!account.auth_user_id) throw new Error("El trabajador no tiene usuario Auth vinculado");

  const password = requireStrongAdminPassword(body.password);
  const employee = await getEmployeeForPortal(
    serviceClient,
    caller.tenantId,
    account.employee_id,
  );
  const authUser = await getAuthUser(serviceClient, account.auth_user_id);
  if (!authUser) throw new Error("El trabajador no tiene usuario Auth disponible");
  if (
    !hasAuthoritativeWorkerIdentity(
      authUser,
      caller.tenantId,
      account.employee_id,
    )
  ) {
    throw new HttpError(
      409,
      "worker_identity_conflict",
      "The worker login identity cannot be safely updated",
    );
  }
  const metadata = buildWorkerAuthMetadata({
    tenantId: caller.tenantId,
    employeeId: account.employee_id,
    username: account.username,
    name: `${employee.first_name ?? ""} ${employee.last_name ?? ""}`.trim(),
  });

  const passwordResetRequiredAt = await beginWorkerPasswordCredentialIssue(
    serviceClient,
    account.id,
    caller.tenantId,
  );
  const { data: markedAccount, error: updateError } = await serviceClient
    .from("employee_portal_accounts")
    .update({
      is_active: true,
      updated_at: passwordResetRequiredAt,
    })
    .eq("id", account.id)
    .eq("tenant_id", caller.tenantId)
    .select("id")
    .maybeSingle();
  if (updateError) throw updateError;
  if (!markedAccount) {
    throw new HttpError(
      404,
      "worker_portal_account_not_found",
      "The worker portal account is no longer available",
    );
  }

  const { error } = await serviceClient.auth.admin.updateUserById(account.auth_user_id, {
    password,
    user_metadata: sanitizeWorkerDisplayMetadata(
      authUser.user_metadata,
      metadata.userMetadata,
    ),
    app_metadata: mergeWorkerAppMetadata(
      authUser.app_metadata,
      metadata.appMetadata,
    ),
  });
  if (error) throw error;

  await revokeWorkerPortalSessions(
    serviceClient,
    account.id,
    caller.tenantId,
  );
  await finishWorkerPasswordCredentialIssue(
    serviceClient,
    account.id,
    caller.tenantId,
    passwordResetRequiredAt,
  );

  return {
    success: true,
    employeeId: account.employee_id,
    username: account.username,
    passwordUpdated: true,
  };
}

export async function setWorkerPortalAccess(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const account = await getWorkerPortalAccount(serviceClient, caller.tenantId, body);
  const isActive = body.isActive === true;

  if (isActive) {
    throw new HttpError(
      409,
      "worker_reactivation_requires_password",
      "Reactivate the worker by assigning a new temporary password",
    );
  }

  const { error } = await serviceClient
    .from("employee_portal_accounts")
    .update({
      is_active: isActive,
      updated_at: new Date().toISOString(),
    })
    .eq("id", account.id)
    .eq("tenant_id", caller.tenantId);

  if (error) throw error;
  const revokedSessions = await revokeWorkerPortalSessions(
    serviceClient,
    account.id,
    caller.tenantId,
  );
  return { success: true, authBanned: false, revokedSessions };
}

export async function createCustomerAccount(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const requestedEmail = normalizeEmail(required(body.email, "email"));
  let email = requestedEmail;
  const name = body.name?.trim() || requestedEmail.split("@")[0];
  const phone = body.phone?.trim() || null;

  let customer = body.customerId
    ? await getCustomer(serviceClient, caller.tenantId, body.customerId)
    : null;

  if (customer) {
    email = resolveCustomerProvisioningEmail(
      requestedEmail,
      customer.email,
    );
  }
  customer ??= await findCustomerByEmail(serviceClient, caller.tenantId, email);

  if (!customer) {
    const { data, error } = await serviceClient
      .from("customers")
      .insert({
        tenant_id: caller.tenantId,
        name,
        email,
        phone,
        is_active: true,
      })
      .select("id, name, email, phone, is_active, auth_user_id")
      .single();

    if (error) throw error;
    customer = data;
  }

  let authUser = customer.auth_user_id
    ? await getAuthUser(serviceClient, customer.auth_user_id)
    : null;
  if (
    authUser &&
    customer.auth_user_id &&
    (typeof authUser.email !== "string" ||
      authUser.email.trim().toLowerCase() !== email)
  ) {
    throw new HttpError(
      409,
      "customer_auth_email_mismatch",
      "The customer is linked to a different Auth email",
    );
  }
  authUser ??= await findAuthUserByEmail(serviceClient, email);

  const metadata = buildCustomerAuthMetadata({
    name,
    phone,
  });
  const storeOrigin = await getStoreOrigin(serviceClient, caller.tenantId);
  let newlyInvited = false;

  if (!authUser) {
    const { data, error } = await serviceClient.auth.admin.inviteUserByEmail(email, {
      data: metadata.userMetadata,
      redirectTo: accessEmailRedirect({
        delivery: "invite",
        isCustomer: true,
        erpOrigin: storeOrigin,
        storeOrigin,
      }),
    });
    if (error) throw error;
    authUser = data.user;
    if (!authUser) {
      throw new HttpError(
        502,
        "customer_invitation_failed",
        "The customer invitation could not be created",
      );
    }
    newlyInvited = true;
  }

  const delivery = selectAccessEmailDelivery({
    newlyInvited,
    emailConfirmedAt: authUser.email_confirmed_at,
  });
  const expectedAuthUserId = delivery === "recovery" ? authUser.id : null;
  const { data: updatedCustomer, error: customerError } = await serviceClient
    .from("customers")
    .update({
      auth_user_id: expectedAuthUserId,
      name,
      phone,
      is_active: true,
      updated_at: new Date().toISOString(),
    })
    .eq("id", customer.id)
    .eq("tenant_id", caller.tenantId)
    .select("id, auth_user_id")
    .maybeSingle();

  if (customerError) throw customerError;
  if (!updatedCustomer) {
    throw new HttpError(
      404,
      "customer_not_found",
      "Customer not found in this tenant",
    );
  }
  if (updatedCustomer.auth_user_id !== expectedAuthUserId) {
    throw new HttpError(
      409,
      "customer_link_state_mismatch",
      "The customer Auth link could not be verified",
    );
  }

  if (delivery === "verification") {
    await sendSignupVerificationEmail(
      serviceClient,
      email,
      accessEmailRedirect({
        delivery,
        isCustomer: true,
        erpOrigin: storeOrigin,
        storeOrigin,
      }),
    );
  } else if (delivery === "recovery") {
    await sendRecoveryEmail(
      serviceClient,
      email,
      accessEmailRedirect({
        delivery,
        isCustomer: true,
        erpOrigin: storeOrigin,
        storeOrigin,
      }),
    );
  }

  await serviceClient
    .from("online_orders")
    .update({ customer_id: customer.id, updated_at: new Date().toISOString() })
    .eq("tenant_id", caller.tenantId)
    .is("customer_id", null)
    .ilike("customer_email", email);

  return {
    success: true,
    authUserId: updatedCustomer.auth_user_id,
    customerId: customer.id,
    authLinked: updatedCustomer.auth_user_id === authUser.id,
    inviteSent: delivery === "invite",
    verificationSent: delivery === "verification",
    passwordResetSent: delivery === "recovery",
    accessEmailSent: true,
  };
}

export function resolveCustomerProvisioningEmail(
  requestedEmail: string,
  authoritativeCustomerEmail: unknown,
): string {
  const requested = normalizeEmail(requestedEmail);
  const authoritative = normalizeEmail(
    typeof authoritativeCustomerEmail === "string" ? authoritativeCustomerEmail : null,
  );
  if (requested !== authoritative) {
    throw new HttpError(
      400,
      "customer_email_mismatch",
      "Account access must use the customer email on file",
    );
  }
  return authoritative;
}

async function setCustomerAccess(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const customer = await getCustomer(
    serviceClient,
    caller.tenantId,
    required(body.customerId, "customerId"),
  );
  const isActive = body.isActive === true;

  const { error } = await serviceClient
    .from("customers")
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq("id", customer.id)
    .eq("tenant_id", caller.tenantId);

  if (error) throw error;
  return { success: true, authBanned: false };
}

async function deleteCustomerAccount(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  if (!body.customerId && body.userId) {
    throw new HttpError(
      404,
      "customer_not_found",
      "Customer not found in this tenant",
    );
  }

  const customer = await getCustomer(
    serviceClient,
    caller.tenantId,
    required(body.customerId, "customerId"),
  );
  const authUserId = customer.auth_user_id;

  if (!authUserId) {
    if (body.deleteCustomerRecord === true) {
      const { error } = await serviceClient
        .from("customers")
        .delete()
        .eq("id", customer.id)
        .eq("tenant_id", caller.tenantId);
      if (error) throw error;
    } else {
      const { error } = await serviceClient
        .from("customers")
        .update({
          is_active: false,
          updated_at: new Date().toISOString(),
        })
        .eq("id", customer.id)
        .eq("tenant_id", caller.tenantId);
      if (error) throw error;
    }
    return detachedAccountResult();
  }

  const messagingEvidence = await getMessagingDeletionEvidence(serviceClient, authUserId);
  if (messagingEvidence.hasEvidence) {
    await deactivateAccountPreservingMessagingHistory(
      serviceClient,
      caller.tenantId,
      authUserId,
      "customer",
    );
    return preservedMessagingHistoryResult(messagingEvidence);
  }

  if (body.deleteCustomerRecord === true) {
    const { error } = await serviceClient
      .from("customers")
      .delete()
      .eq("id", customer.id)
      .eq("tenant_id", caller.tenantId);
    if (error) throw error;
  } else {
    const { error } = await serviceClient
      .from("customers")
      .update({
        auth_user_id: null,
        is_active: false,
        updated_at: new Date().toISOString(),
      })
      .eq("id", customer.id)
      .eq("tenant_id", caller.tenantId);
    if (error) throw error;
  }

  return detachedAccountResult();
}

export async function getMessagingDeletionEvidence(
  serviceClient: SupabaseClient,
  userId: string,
): Promise<MessagingDeletionEvidence> {
  // Auth users are global. An administrator must not hard-delete the identity
  // when any tenant still retains messaging authorship or membership evidence.
  const checks = [
    {
      source: "conversations",
      query: serviceClient
        .from("conversations")
        .select("id")
        .or(`created_by.eq.${userId},accepted_by.eq.${userId},resolved_by.eq.${userId}`),
    },
    {
      source: "conversation_participants",
      query: serviceClient
        .from("conversation_participants")
        .select("conversation_id")
        .eq("user_id", userId),
    },
    {
      source: "conversation_contexts",
      query: serviceClient
        .from("conversation_contexts")
        .select("id")
        .eq("added_by", userId),
    },
    {
      source: "messages",
      query: serviceClient
        .from("messages")
        .select("id")
        .eq("sender_id", userId),
    },
    {
      source: "messaging_attachments",
      query: serviceClient
        .from("messaging_attachments")
        .select("id")
        .eq("created_by", userId),
    },
    {
      source: "messaging_command_receipts",
      query: serviceClient
        .from("messaging_command_receipts")
        .select("id")
        .eq("actor_id", userId),
    },
    {
      source: "messaging_participant_reconciliation_audit",
      query: serviceClient
        .from("messaging_participant_reconciliation_audit")
        .select("id")
        .eq("user_id", userId),
    },
  ];

  const results = await Promise.all(checks.map(async ({ source, query }) => {
    const { data, error } = await query.limit(1);
    if (error) {
      throw new Error(
        `No se pudo verificar el historial de mensajeria (${source}): ${toErrorMessage(error)}`,
      );
    }
    return { source, found: Array.isArray(data) && data.length > 0 };
  }));

  const sources = results
    .filter((result) => result.found)
    .map((result) => result.source);

  return { hasEvidence: sources.length > 0, sources };
}

export async function deactivateAccountPreservingMessagingHistory(
  serviceClient: SupabaseClient,
  tenantId: string,
  userId: string,
  scope: AccountDeletionScope,
) {
  const updatedAt = new Date().toISOString();
  const operations = [];
  if (scope === "internal") {
    operations.push(
      serviceClient
        .from("user_profiles")
        .update({ is_active: false, updated_at: updatedAt })
        .eq("tenant_id", tenantId)
        .eq("user_id", userId),
    );
  } else if (scope === "customer") {
    operations.push(
      serviceClient
        .from("customers")
        .update({ is_active: false, updated_at: updatedAt })
        .eq("tenant_id", tenantId)
        .eq("auth_user_id", userId),
    );
  }

  const results = await Promise.all(operations);
  for (const result of results) {
    if (result.error) throw result.error;
  }

  return { authBanned: false };
}

export async function assertSingleAccountMembership(
  serviceClient: SupabaseClient,
  userId: string,
): Promise<void> {
  const checks = [
    serviceClient
      .from("user_profiles")
      .select("id")
      .eq("user_id", userId)
      .limit(2),
    serviceClient
      .from("customers")
      .select("id")
      .eq("auth_user_id", userId)
      .limit(2),
    serviceClient
      .from("employee_portal_accounts")
      .select("id")
      .eq("auth_user_id", userId)
      .limit(2),
  ];
  const results = await Promise.all(checks);
  if (results.some((result) => result.error)) {
    throw new HttpError(
      503,
      "membership_check_failed",
      "Unable to verify the global identity scope",
    );
  }
  const membershipCount = results.reduce(
    (total, result) => total + (Array.isArray(result.data) ? result.data.length : 0),
    0,
  );
  if (membershipCount !== 1) {
    throw new HttpError(
      409,
      "shared_identity",
      "Display identity cannot be changed from a shared tenant account",
    );
  }
}

export function preservedMessagingHistoryResult(
  evidence: MessagingDeletionEvidence,
): AccountDeletionResult {
  return {
    success: true,
    authDeleted: false,
    authBanned: false,
    authDetachedOnly: false,
    accountDeactivated: true,
    preservedForMessagingHistory: true,
    outcome: "deactivated_preserved_messaging_history",
    messagingEvidence: [...evidence.sources],
  };
}

export function detachedAccountResult(): AccountDeletionResult {
  return {
    success: true,
    authDeleted: false,
    authBanned: false,
    authDetachedOnly: true,
    accountDeactivated: true,
    preservedForMessagingHistory: false,
    outcome: "tenant_access_detached",
    messagingEvidence: [],
  };
}

export async function resendCustomerVerification(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  getEnv: EnvReader = (name) => Deno.env.get(name),
) {
  const customer = await getCustomer(
    serviceClient,
    caller.tenantId,
    required(body.customerId, "customerId"),
  );
  const email = normalizeEmail(customer.email);
  if (body.email && normalizeEmail(body.email) !== email) {
    throw new HttpError(
      400,
      "customer_email_mismatch",
      "Verification can only be sent to the tenant customer email",
    );
  }
  const redirectTo = `${await getStoreOrigin(
    serviceClient,
    caller.tenantId,
    getEnv,
  )}/cuenta/login?confirmed=true`;
  await sendSignupVerificationEmail(serviceClient, email, redirectTo);
  return { success: true, verificationSent: true };
}

async function sendSignupVerificationEmail(
  serviceClient: SupabaseClient,
  email: string,
  redirectTo: string,
) {
  const { error } = await serviceClient.auth.resend({
    type: "signup",
    email,
    options: { emailRedirectTo: redirectTo },
  });
  if (error) throw error;
}

async function sendPasswordReset(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  req: Request,
) {
  const email = normalizeEmail(required(body.email, "email"));
  const user = await findAuthUserByEmail(serviceClient, email);
  const accepted = { success: true, accessEmailSent: true };
  if (!user) return accepted;

  try {
    await assertUserBelongsToTenant(serviceClient, caller.tenantId, user.id);
  } catch (error) {
    if (error instanceof HttpError && error.status === 404) return accepted;
    throw error;
  }

  const { data: customer, error: customerError } = await serviceClient
    .from("customers")
    .select("id")
    .eq("tenant_id", caller.tenantId)
    .eq("auth_user_id", user.id)
    .maybeSingle();
  if (customerError) {
    throw new HttpError(
      503,
      "customer_membership_check_failed",
      "Unable to verify the customer account",
    );
  }

  const delivery = selectAccessEmailDelivery({
    newlyInvited: false,
    emailConfirmedAt: user.email_confirmed_at,
  });
  const erpOrigin = getOrigin(req);
  const storeOrigin = customer ? await getStoreOrigin(serviceClient, caller.tenantId) : erpOrigin;
  const redirectTo = accessEmailRedirect({
    delivery,
    isCustomer: Boolean(customer),
    erpOrigin,
    storeOrigin,
  });

  if (delivery === "verification") {
    await sendSignupVerificationEmail(serviceClient, email, redirectTo);
  } else {
    await sendRecoveryEmail(serviceClient, email, redirectTo);
  }

  return accepted;
}

async function sendRecoveryEmail(serviceClient: SupabaseClient, email: string, redirectTo: string) {
  const { error } = await serviceClient.auth.resetPasswordForEmail(email, {
    redirectTo,
  });
  if (error) throw error;
}

export async function getStaffTargetContext(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  userId: string,
): Promise<StaffTargetContext> {
  const { data, error } = await serviceClient
    .from("user_profiles")
    .select("user_id, role, permissions, is_active, updated_at")
    .eq("tenant_id", caller.tenantId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new HttpError(
      503,
      "authorization_unavailable",
      "Unable to verify staff authority",
    );
  }
  if (!data) {
    throw new HttpError(
      404,
      "staff_user_not_found",
      "Staff user not found in this tenant",
    );
  }
  if (data.user_id !== userId) {
    throw new HttpError(
      503,
      "authorization_unavailable",
      "Unable to verify staff authority",
    );
  }
  if (
    typeof data.updated_at !== "string" ||
    data.updated_at.trim().length === 0
  ) {
    throw new HttpError(
      503,
      "authorization_unavailable",
      "Unable to verify staff authority",
    );
  }

  let authResult: {
    data?: { user?: Record<string, unknown> | null } | null;
    error?: unknown;
  };
  try {
    authResult = await serviceClient.auth.admin.getUserById(userId);
  } catch {
    throw new HttpError(
      503,
      "authorization_unavailable",
      "Unable to verify staff identity",
    );
  }
  const authUser = authResult?.data?.user;
  if (authResult?.error || !authUser) {
    throw new HttpError(
      503,
      "authorization_unavailable",
      "Unable to verify staff identity",
    );
  }

  const permissions = data.permissions &&
      typeof data.permissions === "object" &&
      !Array.isArray(data.permissions)
    ? data.permissions as Record<string, unknown>
    : {};
  const isPrincipalOwner = derivePrincipalOwnerIdentity({
    tenantId: caller.tenantId,
    tenantOwnerEmail: caller.tenantOwnerEmail ?? null,
    authUser,
  });
  if (
    !isPrincipalOwner &&
    !normalizeOptionalEmail(caller.tenantOwnerEmail)
  ) {
    throw new HttpError(
      503,
      "authorization_unavailable",
      "Unable to verify tenant ownership",
    );
  }
  return {
    userId,
    role: requireCanonicalStoredRole(data.role),
    permissions,
    isActive: data.is_active === true,
    updatedAt: data.updated_at,
    isPrincipalOwner,
  };
}

async function deactivateInternalStaffProfile(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  target: StaffTargetContext,
) {
  const { data, error } = await serviceClient
    .from("user_profiles")
    .update({
      is_active: false,
      updated_at: new Date().toISOString(),
    })
    .eq("tenant_id", caller.tenantId)
    .eq("user_id", target.userId)
    .eq("role", target.role)
    .eq("is_active", target.isActive)
    .eq("updated_at", target.updatedAt)
    .select("user_id")
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    throw new HttpError(
      409,
      "staff_state_changed",
      "Staff account authority changed; retry the operation",
    );
  }
}

async function isStaffUserInTenant(
  serviceClient: SupabaseClient,
  tenantId: string,
  userId: string,
) {
  const { data, error } = await serviceClient
    .from("user_profiles")
    .select("user_id")
    .eq("tenant_id", tenantId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) throw error;
  return Boolean(data);
}

export async function assertUserBelongsToTenant(
  serviceClient: SupabaseClient,
  tenantId: string,
  userId: string,
) {
  const [
    { data: staff, error: staffError },
    { data: customer, error: customerError },
  ] = await Promise.all([
    serviceClient.from("user_profiles").select("user_id").eq("tenant_id", tenantId).eq(
      "user_id",
      userId,
    ).maybeSingle(),
    serviceClient.from("customers").select("id").eq("tenant_id", tenantId).eq(
      "auth_user_id",
      userId,
    ).maybeSingle(),
  ]);

  if (staffError || customerError) {
    throw new HttpError(
      503,
      "membership_check_failed",
      "Unable to verify account access",
    );
  }
  if (staff || customer) return;

  throw new HttpError(404, "account_not_found", "Account not found in this tenant");
}

async function getCustomer(serviceClient: SupabaseClient, tenantId: string, customerId: string) {
  const { data, error } = await serviceClient
    .from("customers")
    .select("id, name, email, phone, is_active, auth_user_id")
    .eq("id", customerId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (error) throw error;
  if (!data) throw new Error("Customer not found in this tenant");
  return data;
}

async function findCustomerByEmail(serviceClient: SupabaseClient, tenantId: string, email: string) {
  const { data, error } = await serviceClient
    .from("customers")
    .select("id, name, email, phone, is_active, auth_user_id")
    .eq("tenant_id", tenantId)
    .ilike("email", email)
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  return data;
}

async function getAuthUser(serviceClient: SupabaseClient, userId: string | null) {
  if (!userId) return null;
  const { data, error } = await serviceClient.auth.admin.getUserById(userId);
  if (error) {
    console.warn("Unable to load auth user");
    return null;
  }
  return data.user;
}

async function findAuthUserByEmail(serviceClient: SupabaseClient, email: string) {
  let page = 1;
  while (page <= 10) {
    const { data, error } = await serviceClient.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const found = data.users.find((user: any) => user.email?.toLowerCase() === email.toLowerCase());
    if (found) return found;
    if (data.users.length < 1000) return null;
    page += 1;
  }
  return null;
}

async function getEmployeeName(
  serviceClient: SupabaseClient,
  employeeId: string,
  tenantId: string,
) {
  const { data } = await serviceClient
    .from("employees")
    .select("first_name, last_name")
    .eq("id", employeeId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (!data) return null;
  return `${data.first_name ?? ""} ${data.last_name ?? ""}`.trim() || null;
}

async function getEmployeeForPortal(
  serviceClient: SupabaseClient,
  tenantId: string,
  employeeId: string,
) {
  const { data, error } = await serviceClient
    .from("employees")
    .select("id, first_name, last_name, status, user_id")
    .eq("id", employeeId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (error) {
    throw new HttpError(
      503,
      "employee_access_lookup_failed",
      "Unable to verify employee access",
    );
  }
  if (!data) {
    throw new HttpError(
      404,
      "employee_not_found",
      "Employee not found in this tenant",
    );
  }
  if (data.status !== "active") {
    throw new HttpError(
      409,
      "worker_access_conflict",
      "Only active employees can have worker access",
    );
  }

  const [
    { data: profileLinks, error: profileError },
    { data: invitation, error: invitationError },
  ] = await Promise.all([
    serviceClient
      .from("user_profiles")
      .select("id")
      .eq("employee_id", employeeId)
      .eq("tenant_id", tenantId)
      .limit(1),
    serviceClient
      .from("user_invitations")
      .select("id")
      .eq("employee_id", employeeId)
      .eq("tenant_id", tenantId)
      .eq("status", "pending")
      .maybeSingle(),
  ]);

  if (profileError || invitationError) {
    throw new HttpError(
      503,
      "employee_access_lookup_failed",
      "Unable to verify employee access",
    );
  }
  if (
    typeof data.user_id === "string" ||
    (Array.isArray(profileLinks) && profileLinks.length > 0) ||
    invitation
  ) {
    throw new HttpError(
      409,
      "worker_access_conflict",
      "The employee already has ERP access or a pending ERP invitation",
    );
  }
  return data;
}

async function getWorkerPortalAccount(
  serviceClient: SupabaseClient,
  tenantId: string,
  body: RequestBody,
) {
  let query = serviceClient
    .from("employee_portal_accounts")
    .select("id, employee_id, auth_user_id, username, login_email, is_active")
    .eq("tenant_id", tenantId);

  if (body.employeeId) {
    query = query.eq("employee_id", body.employeeId);
  } else if (body.username) {
    query = query.eq("username", normalizeWorkerUsername(body.username));
  } else {
    throw new Error("employeeId or username is required");
  }

  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("Cuenta movil del trabajador no encontrada");
  return data;
}

export async function assertReusableWorkerOrphan(
  serviceClient: SupabaseClient,
  user: Record<string, unknown>,
  tenantId: string,
  employeeId: string,
  loginEmail: string,
) {
  if (
    typeof user.id !== "string" ||
    user.id.trim().length === 0 ||
    normalizeOptionalEmail(user.email) !== loginEmail ||
    !hasAuthoritativeWorkerIdentity(user, tenantId, employeeId)
  ) {
    throw new HttpError(
      409,
      "worker_login_email_conflict",
      "The worker login address is already reserved",
    );
  }

  const membershipCount = await getAuthMembershipCount(
    serviceClient,
    user.id,
  );
  if (membershipCount !== 0) {
    throw new HttpError(
      409,
      "worker_login_email_conflict",
      "The worker login address is already reserved",
    );
  }
  return user;
}

export async function persistNewWorkerPortalAccount(
  serviceClient: SupabaseClient,
  input: {
    payload: Record<string, unknown>;
    tenantId: string;
    employeeId: string;
    username: string;
    loginEmail: string;
    authUserId: string;
    createdAuthUserId: string | null;
  },
): Promise<string> {
  const { data, error } = await serviceClient
    .from("employee_portal_accounts")
    .insert(input.payload)
    .select("id")
    .single();

  if (
    !error &&
    data &&
    typeof data.id === "string" &&
    data.id.trim().length > 0
  ) {
    return data.id;
  }
  const accessError = error ? mapEmployeeAccessError(error) : null;

  const linkedAccount = await getExactWorkerPortalLink(
    serviceClient,
    input,
  );
  if (linkedAccount) return linkedAccount.id;

  if (input.createdAuthUserId) {
    if (input.createdAuthUserId !== input.authUserId) {
      throw workerIdentityReconciliationRequired();
    }
    await compensateNewWorkerAuthIdentity(
      serviceClient,
      input.createdAuthUserId,
      input.tenantId,
      input.employeeId,
      input.loginEmail,
    );
  }

  if (
    accessError?.code === "worker_access_conflict" ||
    accessError?.code === "employee_erp_link_conflict"
  ) {
    throw accessError;
  }

  throw new HttpError(
    503,
    "worker_portal_account_create_failed",
    "The worker portal account could not be created",
  );
}

async function getExactWorkerPortalLink(
  serviceClient: SupabaseClient,
  input: {
    tenantId: string;
    employeeId: string;
    username: string;
    loginEmail: string;
    authUserId: string;
  },
): Promise<{ id: string } | null> {
  const { data, error } = await serviceClient
    .from("employee_portal_accounts")
    .select("id")
    .eq("tenant_id", input.tenantId)
    .eq("employee_id", input.employeeId)
    .eq("auth_user_id", input.authUserId)
    .eq("username", input.username)
    .eq("login_email", input.loginEmail)
    .maybeSingle();

  if (error) throw workerIdentityReconciliationRequired();
  if (!data) return null;
  if (typeof data.id !== "string" || data.id.trim().length === 0) {
    throw workerIdentityReconciliationRequired();
  }
  return { id: data.id };
}

async function compensateNewWorkerAuthIdentity(
  serviceClient: SupabaseClient,
  userId: string,
  tenantId: string,
  employeeId: string,
  loginEmail: string,
) {
  let authResult: {
    data?: { user?: Record<string, unknown> | null } | null;
    error?: unknown;
  };
  try {
    authResult = await serviceClient.auth.admin.getUserById(userId);
  } catch {
    throw workerIdentityReconciliationRequired();
  }
  const authUser = authResult?.data?.user;
  if (
    authResult?.error ||
    !authUser ||
    authUser.id !== userId ||
    normalizeOptionalEmail(authUser.email) !== loginEmail ||
    !hasAuthoritativeWorkerIdentity(authUser, tenantId, employeeId)
  ) {
    throw workerIdentityReconciliationRequired();
  }

  let membershipCount: number;
  try {
    membershipCount = await getAuthMembershipCount(
      serviceClient,
      userId,
    );
  } catch {
    throw workerIdentityReconciliationRequired();
  }
  if (membershipCount !== 0) {
    throw workerIdentityReconciliationRequired();
  }

  const { error } = await serviceClient.auth.admin.deleteUser(userId);
  if (error) throw workerIdentityReconciliationRequired();
}

async function getAuthMembershipCount(
  serviceClient: SupabaseClient,
  userId: string,
): Promise<number> {
  const results = await Promise.all([
    serviceClient
      .from("user_profiles")
      .select("id")
      .eq("user_id", userId)
      .limit(1),
    serviceClient
      .from("customers")
      .select("id")
      .eq("auth_user_id", userId)
      .limit(1),
    serviceClient
      .from("employee_portal_accounts")
      .select("id")
      .eq("auth_user_id", userId)
      .limit(1),
  ]);
  if (results.some((result) => result.error)) {
    throw new HttpError(
      503,
      "worker_membership_check_failed",
      "Unable to verify the worker login identity",
    );
  }
  return results.reduce(
    (total, result) => total + (Array.isArray(result.data) ? result.data.length : 0),
    0,
  );
}

function workerIdentityReconciliationRequired() {
  return new HttpError(
    503,
    "worker_identity_reconciliation_required",
    "The worker login identity requires reconciliation",
  );
}

async function countRows(
  serviceClient: SupabaseClient,
  table: string,
  tenantId: string,
  filters: Record<string, unknown> = {},
) {
  let query = serviceClient.from(table).select("id", { count: "exact", head: true }).eq(
    "tenant_id",
    tenantId,
  );

  for (const [key, value] of Object.entries(filters)) {
    if (value === "not-null") query = query.not(key, "is", null);
    else query = query.eq(key, value);
  }

  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

async function safeCountRows(
  serviceClient: SupabaseClient,
  table: string,
  tenantId: string,
  filters: Record<string, unknown> = {},
) {
  try {
    return await countRows(serviceClient, table, tenantId, filters);
  } catch (error) {
    if (isMissingRelationError(error)) return 0;
    throw error;
  }
}

function isMissingRelationError(error: unknown) {
  if (!error || typeof error !== "object") return false;
  const value = error as { code?: unknown; message?: unknown };
  return value.code === "42P01" ||
    String(value.message ?? "").toLowerCase().includes("does not exist");
}

const staffRoleSet = new Set<string>([
  "admin",
  "manager",
  "cashier",
  "mechanic",
  "accountant",
]);

function normalizeRole(role: string): StaffRole {
  const normalized = role.trim().toLowerCase();
  if (!staffRoleSet.has(normalized)) {
    throw new HttpError(400, "invalid_role", "A valid staff role is required");
  }
  return normalized as StaffRole;
}

function requireCanonicalStoredRole(role: unknown): StaffRole {
  if (typeof role !== "string" || !staffRoleSet.has(role)) {
    throw new HttpError(
      409,
      "staff_authority_invalid",
      "Staff account authority is invalid",
    );
  }
  return role as StaffRole;
}

function normalizeOptionalEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalized)) return null;
  return normalized;
}

export function derivePrincipalOwnerIdentity(input: {
  tenantId: string;
  tenantOwnerEmail: string | null;
  authUser: unknown;
}): boolean {
  if (!input.authUser || typeof input.authUser !== "object") return false;
  const authUser = input.authUser as Record<string, unknown>;
  const ownerEmail = normalizeOptionalEmail(input.tenantOwnerEmail);
  const authEmail = normalizeOptionalEmail(authUser.email);
  const metadata = authUser.app_metadata;
  const claims = metadata &&
      typeof metadata === "object" &&
      !Array.isArray(metadata)
    ? metadata as Record<string, unknown>
    : {};
  const hasOwnerEmailIdentity = Boolean(
    ownerEmail && authEmail === ownerEmail,
  );
  const hasAuthoritativeOwnerClaim = claims.account_type === "erp_owner" &&
    claims.tenant_id === input.tenantId;
  return hasOwnerEmailIdentity || hasAuthoritativeOwnerClaim;
}

function callerAuthorityRole(caller: CallerContext): AuthorityRole {
  if (caller.isPrincipalOwner === true) return "owner";
  const callerRole = requireCanonicalStoredRole(caller.role);
  return staffAuthorityRole(callerRole, caller.permissions);
}

function staffAuthorityRole(
  role: StaffRole,
  permissions: Record<string, unknown>,
): StaffRole {
  if (role === "admin") return "admin";
  if (role === "manager" || permissions.manage_users === true) {
    return "manager";
  }
  return role;
}

export function assertRoleAssignmentAllowed(
  caller: CallerContext,
  targetRole: StaffRole,
  targetPermissions: Record<string, unknown> = {},
) {
  const actorRole = callerAuthorityRole(caller);
  const actorRank = roleRank[actorRole];
  const targetRank = roleRank[
    staffAuthorityRole(targetRole, targetPermissions)
  ];
  const canManagePeer = actorRole === "owner";
  if (
    targetRank > actorRank ||
    (targetRank === actorRank && !canManagePeer)
  ) {
    throw new HttpError(
      403,
      "role_assignment_forbidden",
      "You cannot assign that staff role",
    );
  }
}

export function canonicalizeRequestedPermissions(
  requested: unknown,
  defaults: Record<string, unknown> = {},
): Record<string, boolean> {
  const source = requested === undefined ? defaults : requested;
  if (
    !source ||
    typeof source !== "object" ||
    Array.isArray(source)
  ) {
    throw new HttpError(
      400,
      "invalid_permissions",
      "Staff permissions must be a canonical boolean object",
    );
  }

  for (const [key, value] of Object.entries(source)) {
    if (
      !canonicalPermissionKeySet.has(key) ||
      typeof value !== "boolean"
    ) {
      throw new HttpError(
        400,
        "invalid_permissions",
        "Staff permissions must use canonical boolean fields",
      );
    }
  }

  const sourceRecord = source as Record<string, unknown>;
  return Object.fromEntries(
    canonicalPermissionKeys.map((key) => [
      key,
      sourceRecord[key] === true,
    ]),
  );
}

export function assertPermissionGrantAllowed(
  caller: CallerContext,
  permissions: Record<string, boolean>,
) {
  if (caller.isPrincipalOwner === true) return;
  for (const key of canonicalPermissionKeys) {
    if (
      permissions[key] === true &&
      caller.permissions[key] !== true
    ) {
      throw new HttpError(
        403,
        "permission_grant_forbidden",
        "You cannot grant a permission you do not possess",
      );
    }
  }
}

export function authorizeStaffAssignment(
  caller: CallerContext,
  requestedRole: string,
  requestedPermissions: unknown,
) {
  const role = normalizeRole(requestedRole);

  let permissions: Record<string, boolean>;
  if (requestedPermissions === undefined) {
    const defaults = canonicalizeRequestedPermissions(
      undefined,
      rolePermissions[role],
    );
    permissions = caller.isPrincipalOwner === true ? defaults : Object.fromEntries(
      canonicalPermissionKeys.map((key) => [
        key,
        defaults[key] === true && caller.permissions[key] === true,
      ]),
    );
  } else {
    permissions = canonicalizeRequestedPermissions(requestedPermissions);
  }
  assertPermissionGrantAllowed(caller, permissions);
  assertRoleAssignmentAllowed(caller, role, permissions);
  return { role, permissions };
}

export function assertStoredInvitationAuthorityAllowed(
  caller: CallerContext,
  invitation: { role?: unknown; permissions?: unknown },
) {
  const role = requireCanonicalStoredRole(invitation.role);
  let permissions: Record<string, boolean>;
  try {
    permissions = canonicalizeRequestedPermissions(invitation.permissions);
  } catch {
    throw new HttpError(
      409,
      "invitation_authority_invalid",
      "Invitation authority is invalid",
    );
  }
  assertRoleAssignmentAllowed(caller, role, permissions);
  assertPermissionGrantAllowed(caller, permissions);
  return { role, permissions };
}

function sameCanonicalPermissions(
  left: Record<string, boolean>,
  right: Record<string, boolean>,
): boolean {
  return canonicalPermissionKeys.every((key) => left[key] === right[key]);
}

export function assertStaffTargetMutationAllowed(
  caller: CallerContext,
  target: StaffTargetContext,
) {
  if (target.isPrincipalOwner) {
    throw new HttpError(
      403,
      "principal_owner_protected",
      "The tenant principal cannot be changed through this operation",
    );
  }

  const actorRole = callerAuthorityRole(caller);
  const actorRank = roleRank[actorRole];
  const targetRank = roleRank[
    staffAuthorityRole(target.role, target.permissions)
  ];
  const canManagePeer = actorRole === "owner";
  if (
    targetRank > actorRank ||
    (targetRank === actorRank && !canManagePeer)
  ) {
    throw new HttpError(
      403,
      "staff_hierarchy_forbidden",
      "You cannot change that staff account",
    );
  }
}

export function assertEmployeeLinkTargetAllowed(
  caller: CallerContext,
  target: StaffTargetContext,
) {
  if (target.isPrincipalOwner) {
    if (caller.isPrincipalOwner === true && caller.userId === target.userId) {
      return;
    }
    throw new HttpError(
      403,
      "principal_owner_protected",
      "Only the tenant principal can link their own employee record",
    );
  }

  if (caller.userId === target.userId) return;
  assertStaffTargetMutationAllowed(caller, target);
}

function normalizeEmail(email: string | null | undefined) {
  const normalized = email?.trim().toLowerCase();
  if (!normalized || !normalized.includes("@")) throw new Error("A valid email is required");
  return normalized;
}

function normalizeWorkerUsername(username: string | null | undefined) {
  const normalized = username?.trim().toLowerCase() ?? "";
  if (!/^[a-z0-9][a-z0-9._-]{2,31}$/.test(normalized)) {
    throw new Error(
      "El usuario debe tener 3 a 32 caracteres: letras, numeros, punto, guion o guion bajo",
    );
  }
  return normalized;
}

export async function buildWorkerLoginEmail(
  tenantId: string,
  username: string,
) {
  const canonicalTenantId = tenantId.trim().toLowerCase();
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
      .test(canonicalTenantId)
  ) {
    throw new Error("A valid tenant identity is required");
  }

  const tenantToken = canonicalTenantId.replaceAll("-", "");
  const usernameDigest = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(normalizeWorkerUsername(username)),
    ),
  );
  const encodedUsername = btoa(
    String.fromCharCode(...usernameDigest.slice(0, 20)),
  )
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
  return `wp-${tenantToken}-${encodedUsername}@worker-login.invalid`;
}

function getDisplayName(user: any) {
  return user?.user_metadata?.full_name ?? user?.user_metadata?.name ??
    user?.user_metadata?.display_name ?? null;
}

export function isPublicStoreCustomerForTenant(
  user: Record<string, unknown> | null | undefined,
  tenantId: string,
) {
  const metadata = user?.app_metadata;
  if (!metadata || typeof metadata !== "object") return false;
  const claims = metadata as Record<string, unknown>;
  if (claims.account_type !== "public_store_customer") return false;

  const memberships = claims.customer_memberships;
  if (
    !memberships ||
    typeof memberships !== "object" ||
    Array.isArray(memberships)
  ) {
    return false;
  }

  const customerId = (memberships as Record<string, unknown>)[tenantId];
  return typeof customerId === "string" && customerId.trim().length > 0;
}

function isBanned(user: any) {
  if (!user?.banned_until) return false;
  return new Date(user.banned_until).getTime() > Date.now();
}

export function isStrongAdminPassword(password: unknown): password is string {
  if (typeof password !== "string") return false;
  // deno-lint-ignore no-control-regex
  const hasControlCharacters = /[\u0000-\u001F\u007F-\u009F]/u.test(password);
  return !hasControlCharacters &&
    password.length >= 12 &&
    password.length <= 128 &&
    /[A-Z]/.test(password) &&
    /[a-z]/.test(password) &&
    /[0-9]/.test(password) &&
    /[^A-Za-z0-9\s]/u.test(password);
}

function requireStrongAdminPassword(password: unknown): string {
  if (!isStrongAdminPassword(password)) {
    throw new HttpError(
      400,
      "weak_password",
      "Password must be 12-128 characters and include uppercase, lowercase, number, and symbol",
    );
  }
  return password;
}

export function buildWorkerAuthMetadata(input: {
  tenantId: string;
  employeeId: string;
  username: string;
  name: string;
}) {
  const authoritative = {
    account_type: "worker_portal",
    tenant_id: input.tenantId,
    employee_id: input.employeeId,
    role: "worker",
  } as const;

  return {
    appMetadata: authoritative,
    userMetadata: {
      username: input.username,
      name: input.name,
    },
  };
}

export function mergeWorkerAppMetadata(
  current: unknown,
  authoritative: {
    account_type: "worker_portal";
    tenant_id: string;
    employee_id: string;
    role: "worker";
  },
): Record<string, unknown> {
  const preserved = current &&
      typeof current === "object" &&
      !Array.isArray(current)
    ? { ...(current as Record<string, unknown>) }
    : {};
  return {
    ...preserved,
    ...authoritative,
  };
}

export function buildWorkerPasswordResetMarker(
  passwordResetRequiredAt: string,
  passwordCredentialIssuedAt: string | null,
) {
  return {
    must_reset_password: true,
    password_reset_required_at: passwordResetRequiredAt,
    password_credential_issued_at: passwordCredentialIssuedAt,
    password_reset_challenge_started_at: null,
  } as const;
}

export async function beginWorkerPasswordCredentialIssue(
  serviceClient: SupabaseClient,
  portalAccountId: string,
  tenantId: string,
): Promise<string> {
  const { data, error } = await serviceClient.rpc(
    "begin_worker_password_credential_issue",
    {
      p_portal_account_id: portalAccountId,
      p_tenant_id: tenantId,
    },
  );
  if (error) {
    const accessError = mapEmployeeAccessError(error);
    if (accessError.code === "worker_access_conflict") {
      throw accessError;
    }
    throw new HttpError(
      503,
      "worker_credential_issue_begin_failed",
      "Unable to prepare the worker credential",
    );
  }
  return requireCredentialIssueTimestamp(
    data,
    "worker_credential_issue_begin_failed",
  );
}

export async function finishWorkerPasswordCredentialIssue(
  serviceClient: SupabaseClient,
  portalAccountId: string,
  tenantId: string,
  passwordResetRequiredAt: string,
): Promise<string> {
  const { data, error } = await serviceClient.rpc(
    "finish_worker_password_credential_issue",
    {
      p_portal_account_id: portalAccountId,
      p_tenant_id: tenantId,
      p_password_reset_required_at: passwordResetRequiredAt,
    },
  );
  if (error) {
    throw new HttpError(
      503,
      "worker_credential_issue_finish_failed",
      "Unable to finalize the worker credential",
    );
  }
  return requireCredentialIssueTimestamp(
    data,
    "worker_credential_issue_finish_failed",
  );
}

export async function revokeWorkerPortalSessions(
  serviceClient: SupabaseClient,
  portalAccountId: string,
  tenantId: string,
): Promise<number> {
  const { data, error } = await serviceClient.rpc(
    "revoke_worker_portal_sessions",
    {
      p_portal_account_id: portalAccountId,
      p_tenant_id: tenantId,
    },
  );
  if (
    error ||
    typeof data !== "number" ||
    !Number.isInteger(data) ||
    data < 0
  ) {
    throw new HttpError(
      503,
      "worker_session_revocation_failed",
      "Unable to revoke worker sessions",
    );
  }
  return data;
}

function requireCredentialIssueTimestamp(
  value: unknown,
  code: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim().length === 0 ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new HttpError(
      503,
      code,
      "Unable to verify the worker credential state",
    );
  }
  return value;
}

export function sanitizeWorkerDisplayMetadata(
  current: unknown,
  display: { username: string; name: string },
): Record<string, unknown> {
  const metadata = current && typeof current === "object"
    ? { ...(current as Record<string, unknown>) }
    : {};
  delete metadata.account_type;
  delete metadata.tenant_id;
  delete metadata.employee_id;
  delete metadata.role;
  delete metadata.invitation_token;
  return {
    ...metadata,
    username: display.username,
    name: display.name,
  };
}

export function hasAuthoritativeWorkerIdentity(
  user: Record<string, unknown> | null | undefined,
  tenantId: string,
  employeeId: string,
): boolean {
  const metadata = user?.app_metadata;
  if (!metadata || typeof metadata !== "object") return false;
  const claims = metadata as Record<string, unknown>;
  return claims.account_type === "worker_portal" &&
    claims.tenant_id === tenantId &&
    claims.employee_id === employeeId &&
    claims.role === "worker";
}

export function buildCustomerAuthMetadata(input: {
  name: string;
  phone: string | null;
}) {
  return {
    userMetadata: {
      name: input.name,
      phone: input.phone,
    },
  };
}

export function selectAccessEmailDelivery(input: {
  newlyInvited: boolean;
  emailConfirmedAt: unknown;
}): "invite" | "verification" | "recovery" {
  if (input.newlyInvited) return "invite";
  return typeof input.emailConfirmedAt === "string" &&
      input.emailConfirmedAt.trim().length > 0
    ? "recovery"
    : "verification";
}

export function accessEmailRedirect(input: {
  delivery: "invite" | "verification" | "recovery";
  isCustomer: boolean;
  erpOrigin: string;
  storeOrigin: string;
}): string {
  if (input.isCustomer) {
    if (input.delivery === "invite") {
      return `${input.storeOrigin}/cuenta/login?invited=true`;
    }
    if (input.delivery === "verification") {
      return `${input.storeOrigin}/cuenta/login?confirmed=true`;
    }
    return `${input.storeOrigin}/cuenta/login?recovery=true`;
  }
  return input.delivery === "verification"
    ? `${input.erpOrigin}/auth/callback`
    : `${input.erpOrigin}/reset-password`;
}

function addDays(days: number) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString();
}

function getOrigin(req: Request) {
  const origin = req.headers.get("origin");
  if (origin) {
    return normalizeOrigin(origin) ?? "https://project-vinabike.web.app";
  }
  const configured = Deno.env.get("APP_URL")?.trim() ?? "";
  return normalizeOrigin(configured) ?? "https://project-vinabike.web.app";
}

async function getStoreOrigin(
  serviceClient: SupabaseClient,
  tenantId: string,
  getEnv: EnvReader = (name) => Deno.env.get(name),
) {
  const { data: tenant, error } = await serviceClient
    .from("tenants")
    .select("custom_domain, subdomain")
    .eq("id", tenantId)
    .maybeSingle();

  if (error) {
    throw new HttpError(
      503,
      "store_origin_unavailable",
      "Unable to resolve the customer storefront",
    );
  }

  return resolveTrustedStoreOrigin({
    customDomain: tenant?.custom_domain?.toString(),
    subdomain: tenant?.subdomain?.toString(),
    publicStoreOrigins: getEnv("PUBLIC_STORE_ORIGINS"),
    publicStoreBaseDomain: getEnv("PUBLIC_STORE_BASE_DOMAIN"),
  });
}

export function resolveTrustedStoreOrigin(input: {
  customDomain?: string | null;
  subdomain?: string | null;
  publicStoreOrigins?: string | null;
  publicStoreBaseDomain?: string | null;
}): string {
  const allowedOrigins = new Set(
    (input.publicStoreOrigins ?? "")
      .split(",")
      .map((value) => strictHttpsOrigin(value))
      .filter((value): value is string => value !== null),
  );
  const customOrigin = strictHttpsOrigin(input.customDomain ?? "", true);
  if (customOrigin && allowedOrigins.has(customOrigin)) return customOrigin;

  const baseDomain = input.publicStoreBaseDomain?.trim().toLowerCase() ?? "";
  const configuredSubdomain = input.subdomain?.trim() ?? "";
  const subdomain = configuredSubdomain.toLowerCase();
  if (
    /^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$/.test(baseDomain) &&
    !baseDomain.includes("..") &&
    /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(subdomain)
  ) {
    const generated = strictHttpsOrigin(`https://${subdomain}.${baseDomain}`);
    if (generated) return generated;
  }

  const configuredCustomDomain = input.customDomain?.trim() ?? "";
  const isCanonicalVinabikeDomain = customOrigin === "https://vinabike.cl" ||
    customOrigin === "https://www.vinabike.cl";
  const hasNoConflictingCustomDomain = configuredCustomDomain.length === 0 ||
    isCanonicalVinabikeDomain;
  const isCanonicalVinabikeTenant = configuredSubdomain === "vinabike" &&
    hasNoConflictingCustomDomain;
  if (isCanonicalVinabikeTenant) {
    return "https://vinabike.cl";
  }

  throw new HttpError(
    503,
    "store_origin_unavailable",
    "Unable to resolve the customer storefront",
  );
}

function strictHttpsOrigin(
  value: string,
  assumeHttps = false,
): string | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  try {
    const parsed = new URL(
      assumeHttps && !trimmed.includes("://") ? `https://${trimmed}` : trimmed,
    );
    if (
      parsed.protocol !== "https:" ||
      parsed.username ||
      parsed.password ||
      parsed.pathname !== "/" ||
      parsed.search ||
      parsed.hash
    ) {
      return null;
    }
    return parsed.origin;
  } catch (_) {
    return null;
  }
}

function required(value: string | undefined | null, name: string) {
  if (!value || !value.trim()) throw new Error(`${name} is required`);
  return value.trim();
}

function requiredEnv(name: string) {
  return requiredEnvFrom((envName) => Deno.env.get(envName), name);
}

function requiredEnvFrom(getEnv: EnvReader, name: string) {
  const value = getEnv(name)?.trim();
  if (!value) {
    throw new HttpError(
      503,
      "service_not_configured",
      "Account management is unavailable",
    );
  }
  return value;
}

export function isAllowedCorsOrigin(
  origin: string,
  configuredOrigins: readonly string[] = configuredCorsOrigins(),
) {
  const normalized = normalizeOrigin(origin);
  if (!normalized) return false;

  const allowed = new Set([
    ...defaultAllowedOrigins,
    ...configuredOrigins
      .map(normalizeOrigin)
      .filter((value): value is string => value !== null),
  ]);

  return allowed.has(normalized) || firebasePreviewOrigin.test(normalized);
}

function configuredCorsOrigins() {
  const values = (Deno.env.get("CORS_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

  const appUrl = Deno.env.get("APP_URL")?.trim();
  if (appUrl) values.push(appUrl);
  return values;
}

function normalizeOrigin(value: string) {
  try {
    return new URL(value).origin;
  } catch (_) {
    return null;
  }
}

function corsHeaders(req: Request, configuredOrigins: readonly string[]) {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  const origin = req.headers.get("origin");
  if (origin && isAllowedCorsOrigin(origin, configuredOrigins)) {
    headers["Access-Control-Allow-Origin"] = normalizeOrigin(origin)!;
  }
  return headers;
}

function json(
  req: Request,
  data: unknown,
  status: number,
  configuredOrigins: readonly string[],
) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders(req, configuredOrigins),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
