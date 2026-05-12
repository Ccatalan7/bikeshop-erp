import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type SupabaseClient = ReturnType<typeof createClient>

interface RequestBody {
  action?: string
  search?: string
  userId?: string
  customerId?: string
  employeeId?: string
  invitationId?: string
  email?: string
  name?: string
  phone?: string
  role?: string
  permissions?: Record<string, boolean>
  isActive?: boolean
  password?: string
  mode?: 'invite' | 'temporary_password'
  confirmEmail?: boolean
  deleteCustomerRecord?: boolean
}

interface CallerContext {
  userId: string
  tenantId: string
  role: string
  permissions: Record<string, unknown>
}

const rolePermissions: Record<string, Record<string, boolean>> = {
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
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const supabaseUrl = requiredEnv('SUPABASE_URL')
    const serviceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? serviceRoleKey
    const authHeader = req.headers.get('Authorization') ?? ''

    if (!authHeader.startsWith('Bearer ')) {
      return json({ error: 'Missing authorization header' }, 401)
    }

    const serviceClient = createClient(supabaseUrl, serviceRoleKey)
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    const caller = await getCallerContext(userClient, serviceClient)
    const body = (await req.json()) as RequestBody
    const action = body.action ?? 'overview'

    switch (action) {
      case 'overview':
        return json(await getOverview(serviceClient, caller, body.search ?? ''))
      case 'create_internal_invitation':
        return json(await createInternalInvitation(serviceClient, caller, body, req))
      case 'resend_internal_invitation':
        return json(await sendInvitationEmail(serviceClient, body.invitationId, req))
      case 'cancel_internal_invitation':
        return json(await cancelInternalInvitation(serviceClient, caller, body))
      case 'update_internal_user':
        return json(await updateInternalUser(serviceClient, caller, body))
      case 'update_internal_identity':
        return json(await updateInternalIdentity(serviceClient, caller, body))
      case 'set_internal_access':
        return json(await setInternalAccess(serviceClient, caller, body))
      case 'delete_internal_account':
        return json(await deleteInternalAccount(serviceClient, caller, body))
      case 'create_customer_account':
        return json(await createCustomerAccount(serviceClient, caller, body, req))
      case 'set_customer_access':
        return json(await setCustomerAccess(serviceClient, caller, body))
      case 'delete_customer_account':
        return json(await deleteCustomerAccount(serviceClient, caller, body))
      case 'resend_customer_verification':
        return json(await resendCustomerVerification(serviceClient, caller, body))
      case 'confirm_email':
        return json(await confirmUserEmail(serviceClient, caller, body))
      case 'send_password_reset':
        return json(await sendPasswordReset(serviceClient, caller, body, req))
      default:
        return json({ error: `Unsupported action: ${action}` }, 400)
    }
  } catch (error) {
    console.error('admin-user-management error', error)
    return json({ error: toErrorMessage(error) }, 500)
  }
})

function toErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message
  if (typeof error === 'string') return error
  if (error && typeof error === 'object') {
    const record = error as Record<string, unknown>
    for (const key of ['message', 'error', 'details', 'msg']) {
      const value = record[key]
      if (typeof value === 'string' && value.trim().length > 0) return value
      if (value && typeof value === 'object') return toErrorMessage(value)
    }

    try {
      return JSON.stringify(error)
    } catch (_) {
      return String(error)
    }
  }
  return String(error)
}

async function getCallerContext(
  userClient: SupabaseClient,
  serviceClient: SupabaseClient,
): Promise<CallerContext> {
  const { data: userData, error: userError } = await userClient.auth.getUser()
  const user = userData?.user

  if (userError || !user) {
    throw new Error('Invalid session')
  }

  const { data: profile, error: profileError } = await serviceClient
    .from('user_profiles')
    .select('tenant_id, role, permissions, is_active')
    .eq('user_id', user.id)
    .maybeSingle()

  if (profileError) throw profileError
  if (!profile || profile.is_active === false) {
    throw new Error('Only active ERP users can manage accounts')
  }

  const permissions = (profile.permissions ?? {}) as Record<string, unknown>
  const canManage = ['owner', 'admin', 'manager'].includes(profile.role) || permissions.manage_users === true

  if (!canManage) {
    throw new Error('You do not have permission to manage users')
  }

  return {
    userId: user.id,
    tenantId: profile.tenant_id,
    role: profile.role,
    permissions,
  }
}

async function getOverview(serviceClient: SupabaseClient, caller: CallerContext, search: string) {
  const searchTerm = search.trim()
  const [staffUsers, invitations, customerAccounts, summary] = await Promise.all([
    getStaffUsers(serviceClient, caller.tenantId),
    getPendingInvitations(serviceClient, caller.tenantId),
    getCustomerAccounts(serviceClient, caller.tenantId, searchTerm),
    getSummary(serviceClient, caller.tenantId),
  ])

  return {
    staffUsers,
    invitations,
    customerAccounts,
    summary,
  }
}

async function getStaffUsers(serviceClient: SupabaseClient, tenantId: string) {
  const { data, error } = await serviceClient
    .from('user_profiles')
    .select('id, user_id, role, permissions, is_active, created_at, updated_at, employee_id')
    .eq('tenant_id', tenantId)
    .order('created_at', { ascending: false })

  if (error) throw error

  const rows = data ?? []
  return await Promise.all(rows.map(async (profile) => {
    const authUser = await getAuthUser(serviceClient, profile.user_id)
    const employee = profile.employee_id
      ? await getEmployeeName(serviceClient, profile.employee_id, tenantId)
      : null

    return {
      kind: 'staff',
      id: profile.user_id,
      profileId: profile.id,
      email: authUser?.email ?? 'Sin email',
      displayName: getDisplayName(authUser) ?? employee ?? authUser?.email ?? 'Usuario interno',
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
    }
  }))
}

async function getPendingInvitations(serviceClient: SupabaseClient, tenantId: string) {
  const { data, error } = await serviceClient
    .from('user_invitations')
    .select('id, email, role, permissions, status, expires_at, created_at, metadata, employee_id')
    .eq('tenant_id', tenantId)
    .eq('status', 'pending')
    .order('created_at', { ascending: false })

  if (error) throw error
  return data ?? []
}

async function getCustomerAccounts(serviceClient: SupabaseClient, tenantId: string, search: string) {
  let query = serviceClient
    .from('customers')
    .select('id, name, email, phone, is_active, auth_user_id, created_at, updated_at')
    .eq('tenant_id', tenantId)
    .order('updated_at', { ascending: false })

  if (search.length > 0) {
    const escaped = search.replaceAll(',', ' ')
    query = query.or(`name.ilike.%${escaped}%,email.ilike.%${escaped}%,phone.ilike.%${escaped}%`)
      .limit(120)
  } else {
    query = query.not('auth_user_id', 'is', null).limit(120)
  }

  const { data, error } = await query
  if (error) throw error

  const rows = data ?? []
  const customerAccounts = await Promise.all(rows.map(async (customer) => {
    const authUser = customer.auth_user_id
      ? await getAuthUser(serviceClient, customer.auth_user_id)
      : null
    const isStaffAuthUser = authUser
      ? await isStaffUserInTenant(serviceClient, tenantId, authUser.id)
      : false

    return {
      kind: 'customer',
      id: customer.auth_user_id ?? customer.id,
      customerId: customer.id,
      authUserId: customer.auth_user_id,
      email: authUser?.email ?? customer.email ?? '',
      displayName: customer.name ?? getDisplayName(authUser) ?? customer.email ?? 'Cliente web',
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
    }
  }))

  const orphanWebsiteAccounts = await getOrphanWebsiteAuthAccounts(
    serviceClient,
    tenantId,
    search,
  )

  return [...orphanWebsiteAccounts, ...customerAccounts]
}

async function getOrphanWebsiteAuthAccounts(serviceClient: SupabaseClient, tenantId: string, search: string) {
  const linkedAuthIds = await getLinkedCustomerAuthIds(serviceClient, tenantId)
  const searchTerm = search.trim().toLowerCase()
  const accounts = []
  let page = 1

  while (page <= 10) {
    const { data, error } = await serviceClient.auth.admin.listUsers({ page, perPage: 1000 })
    if (error) throw error

    for (const user of data.users) {
      if (!isPublicStoreCustomerForTenant(user, tenantId)) continue
      if (linkedAuthIds.has(user.id)) continue

      const displayName = getDisplayName(user) ?? user.email ?? 'Cliente web sin ficha CRM'
      const phone = user.user_metadata?.phone ?? null
      const haystack = `${displayName} ${user.email ?? ''} ${phone ?? ''}`.toLowerCase()
      if (searchTerm && !haystack.includes(searchTerm)) continue

      accounts.push({
        kind: 'customer',
        id: user.id,
        customerId: null,
        authUserId: user.id,
        email: user.email ?? '',
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
      })
    }

    if (data.users.length < 1000) break
    page += 1
  }

  return accounts
}

async function getLinkedCustomerAuthIds(serviceClient: SupabaseClient, tenantId: string) {
  const { data, error } = await serviceClient
    .from('customers')
    .select('auth_user_id')
    .eq('tenant_id', tenantId)
    .not('auth_user_id', 'is', null)
    .limit(10000)

  if (error) throw error
  return new Set((data ?? []).map((row) => row.auth_user_id).filter(Boolean))
}

async function getSummary(serviceClient: SupabaseClient, tenantId: string) {
  const [staffCount, invitationCount, customerCount, linkedCustomerCount, orphanWebsiteAccountCount] = await Promise.all([
    countRows(serviceClient, 'user_profiles', tenantId),
    countRows(serviceClient, 'user_invitations', tenantId, { status: 'pending' }),
    countRows(serviceClient, 'customers', tenantId),
    countRows(serviceClient, 'customers', tenantId, { auth_user_id: 'not-null' }),
    countOrphanWebsiteAuthAccounts(serviceClient, tenantId),
  ])

  return {
    staffCount,
    pendingInvitationCount: invitationCount,
    customerCount,
    linkedCustomerCount,
    orphanWebsiteAccountCount,
  }
}

async function countOrphanWebsiteAuthAccounts(serviceClient: SupabaseClient, tenantId: string) {
  return (await getOrphanWebsiteAuthAccounts(serviceClient, tenantId, '')).length
}

async function createInternalInvitation(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  req: Request,
) {
  const email = normalizeEmail(required(body.email, 'email'))
  const role = normalizeRole(body.role ?? 'cashier')
  const permissions = body.permissions ?? rolePermissions[role] ?? {}

  const { data: existing, error: existingError } = await serviceClient
    .from('user_invitations')
    .select('id')
    .eq('tenant_id', caller.tenantId)
    .eq('email', email)
    .eq('status', 'pending')
    .maybeSingle()

  if (existingError) throw existingError

  let invitationId = existing?.id
  if (!invitationId) {
    const { data, error } = await serviceClient
      .from('user_invitations')
      .insert({
        tenant_id: caller.tenantId,
        email,
        role,
        permissions,
        invited_by: caller.userId,
        status: 'pending',
        employee_id: body.employeeId ?? null,
        expires_at: addDays(7),
        metadata: {
          first_name: body.name?.trim() || email.split('@')[0],
          last_name: '',
          invited_from: 'settings_user_management',
        },
      })
      .select('id')
      .single()

    if (error) throw error
    invitationId = data.id
  }

  const emailResult = await sendInvitationEmail(serviceClient, invitationId, req)
  return { invitationId, ...emailResult }
}

async function sendInvitationEmail(_serviceClient: SupabaseClient, invitationId: string | undefined, req: Request) {
  if (!invitationId) throw new Error('invitationId is required')

  const supabaseUrl = requiredEnv('SUPABASE_URL')
  const serviceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY')
  const response = await fetch(`${supabaseUrl}/functions/v1/send-invitation`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${serviceRoleKey}`,
      apikey: serviceRoleKey,
      'Content-Type': 'application/json',
      origin: req.headers.get('origin') ?? '',
    },
    body: JSON.stringify({ invitationId }),
  })

  const data = await response.json().catch(() => ({}))
  return {
    emailSent: response.ok && data?.success !== false,
    invitationLink: data?.invitationLink ?? null,
    emailResult: data,
  }
}

async function cancelInternalInvitation(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  const invitationId = required(body.invitationId, 'invitationId')
  const { error } = await serviceClient
    .from('user_invitations')
    .update({ status: 'expired' })
    .eq('id', invitationId)
    .eq('tenant_id', caller.tenantId)
    .eq('status', 'pending')

  if (error) throw error
  return { success: true }
}

async function updateInternalUser(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  const userId = required(body.userId, 'userId')
  const role = normalizeRole(body.role ?? 'cashier')
  const permissions = body.permissions ?? rolePermissions[role] ?? {}

  const { error } = await serviceClient
    .from('user_profiles')
    .update({ role, permissions, updated_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('tenant_id', caller.tenantId)

  if (error) throw error
  return { success: true }
}

async function updateInternalIdentity(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  const userId = required(body.userId, 'userId')
  const name = required(body.name, 'name')
  await assertStaffInTenant(serviceClient, caller.tenantId, userId)

  const authUser = await getAuthUser(serviceClient, userId)
  const { error } = await serviceClient.auth.admin.updateUserById(userId, {
    user_metadata: {
      ...(authUser?.user_metadata ?? {}),
      full_name: name,
      name,
      display_name: name,
    },
  })

  if (error) throw error
  return { success: true }
}

async function setInternalAccess(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  const userId = required(body.userId, 'userId')
  const isActive = body.isActive === true
  if (userId === caller.userId && !isActive) throw new Error('You cannot suspend your own account')

  await assertStaffInTenant(serviceClient, caller.tenantId, userId)
  await serviceClient.auth.admin.updateUserById(userId, {
    ban_duration: isActive ? 'none' : '876600h',
  })

  const { error } = await serviceClient
    .from('user_profiles')
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('tenant_id', caller.tenantId)

  if (error) throw error
  return { success: true }
}

async function deleteInternalAccount(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  const userId = required(body.userId, 'userId')
  if (userId === caller.userId) throw new Error('You cannot delete your own account')

  await assertStaffInTenant(serviceClient, caller.tenantId, userId)

  await serviceClient.from('employees').update({ user_id: null }).eq('user_id', userId).eq('tenant_id', caller.tenantId)
  const { error } = await serviceClient.auth.admin.deleteUser(userId)
  if (error) throw error

  return { success: true }
}

async function createCustomerAccount(
  serviceClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  req: Request,
) {
  const email = normalizeEmail(required(body.email, 'email'))
  const name = body.name?.trim() || email.split('@')[0]
  const phone = body.phone?.trim() || null
  const mode = body.mode ?? 'invite'

  let customer = body.customerId
    ? await getCustomer(serviceClient, caller.tenantId, body.customerId)
    : null

  customer ??= await findCustomerByEmail(serviceClient, caller.tenantId, email)

  if (!customer) {
    const { data, error } = await serviceClient
      .from('customers')
      .insert({
        tenant_id: caller.tenantId,
        name,
        email,
        phone,
        is_active: true,
      })
      .select('id, name, email, phone, is_active, auth_user_id')
      .single()

    if (error) throw error
    customer = data
  }

  let authUser = customer.auth_user_id ? await getAuthUser(serviceClient, customer.auth_user_id) : null
  authUser ??= await findAuthUserByEmail(serviceClient, email)

  if (authUser && await isStaffUserInTenant(serviceClient, caller.tenantId, authUser.id)) {
    if (customer.auth_user_id === authUser.id) {
      const { error: customerError } = await serviceClient
        .from('customers')
        .update({
          name,
          phone,
          is_active: true,
          updated_at: new Date().toISOString(),
        })
        .eq('id', customer.id)
        .eq('tenant_id', caller.tenantId)

      if (customerError) throw customerError

      return {
        success: true,
        authUserId: authUser.id,
        customerId: customer.id,
        inviteSent: false,
        temporaryPassword: null,
        sharedStaffAccount: true,
      }
    }

    throw new Error(
      'Ese email ya pertenece a un usuario interno del ERP. Usa otro email para la cuenta web o mantén este login solo como usuario de equipo.',
    )
  }

  const metadata = {
    account_type: 'public_store_customer',
    customer_tenant_id: caller.tenantId,
    customer_id: customer.id,
    role: 'customer',
    name,
    phone,
  }

  let temporaryPassword: string | null = null
  let inviteSent = false
  let passwordResetSent = false
  let passwordResetLinkGenerated = false
  let accessLink: string | null = null

  if (!authUser) {
    if (mode === 'temporary_password') {
      temporaryPassword = body.password?.trim() || generatePassword()
      const { data, error } = await serviceClient.auth.admin.createUser({
        email,
        password: temporaryPassword,
        email_confirm: body.confirmEmail === true,
        user_metadata: metadata,
      })
      if (error) throw error
      authUser = data.user
    } else {
      const { data, error } = await serviceClient.auth.admin.inviteUserByEmail(email, {
        data: metadata,
        redirectTo: `${await getStoreOrigin(serviceClient, caller.tenantId, req)}/cuenta/login`,
      })
      if (error) throw error
      authUser = data.user
      inviteSent = true
    }
  } else {
    const updatePayload: Record<string, unknown> = {
      user_metadata: {
        ...(authUser.user_metadata ?? {}),
        ...metadata,
      },
      ban_duration: 'none',
    }

    if (mode === 'temporary_password') {
      temporaryPassword = body.password?.trim() || generatePassword()
      updatePayload.password = temporaryPassword
      if (body.confirmEmail === true) updatePayload.email_confirm = true
    }

    await serviceClient.auth.admin.updateUserById(authUser.id, updatePayload)

    if (mode !== 'temporary_password') {
      accessLink = await generateRecoveryLink(
        serviceClient,
        email,
        `${await getStoreOrigin(serviceClient, caller.tenantId, req)}/cuenta/login`,
      )
      passwordResetLinkGenerated = true
    }
  }

  const { error: customerError } = await serviceClient
    .from('customers')
    .update({
      auth_user_id: authUser.id,
      name,
      phone,
      is_active: true,
      updated_at: new Date().toISOString(),
    })
    .eq('id', customer.id)
    .eq('tenant_id', caller.tenantId)

  if (customerError) throw customerError

  await serviceClient
    .from('online_orders')
    .update({ customer_id: customer.id, updated_at: new Date().toISOString() })
    .eq('tenant_id', caller.tenantId)
    .is('customer_id', null)
    .ilike('customer_email', email)

  return {
    success: true,
    authUserId: authUser.id,
    customerId: customer.id,
    inviteSent,
    passwordResetSent,
    passwordResetLinkGenerated,
    accessEmailSent: inviteSent || passwordResetSent,
    accessLink,
    temporaryPassword,
  }
}

async function setCustomerAccess(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  const customer = await getCustomer(serviceClient, caller.tenantId, required(body.customerId, 'customerId'))
  const isActive = body.isActive === true

  const authUserIsStaff = customer.auth_user_id
    ? await isStaffUserInTenant(serviceClient, caller.tenantId, customer.auth_user_id)
    : false

  if (customer.auth_user_id && !authUserIsStaff) {
    await serviceClient.auth.admin.updateUserById(customer.auth_user_id, {
      ban_duration: isActive ? 'none' : '876600h',
    })
  }

  const { error } = await serviceClient
    .from('customers')
    .update({ is_active: isActive, updated_at: new Date().toISOString() })
    .eq('id', customer.id)
    .eq('tenant_id', caller.tenantId)

  if (error) throw error
  return { success: true }
}

async function deleteCustomerAccount(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  if (!body.customerId && body.userId) {
    return await deleteOrphanWebsiteAuthAccount(serviceClient, caller, required(body.userId, 'userId'))
  }

  const customer = await getCustomer(serviceClient, caller.tenantId, required(body.customerId, 'customerId'))
  const authUserId = customer.auth_user_id

  if (!authUserId) {
    if (body.deleteCustomerRecord === true) {
      const { error } = await serviceClient
        .from('customers')
        .delete()
        .eq('id', customer.id)
        .eq('tenant_id', caller.tenantId)
      if (error) throw error
    }
    return { success: true, authDeleted: false, authDetachedOnly: true }
  }

  const isStaffUser = await isStaffUserInTenant(serviceClient, caller.tenantId, authUserId)
  if (!isStaffUser) {
    await clearCustomerAuthReferencesForDelete(
      serviceClient,
      caller.tenantId,
      authUserId,
    )

    const { error } = await serviceClient.auth.admin.deleteUser(authUserId)
    if (error) {
      console.warn('Unable to hard-delete customer auth user', authUserId, error.message)
      throw new Error(`No se pudo eliminar el usuario Auth del cliente: ${error.message}`)
    }

    if (body.deleteCustomerRecord === true) {
      const { error: customerDeleteError } = await serviceClient
        .from('customers')
        .delete()
        .eq('id', customer.id)
        .eq('tenant_id', caller.tenantId)
      if (customerDeleteError) throw customerDeleteError
    }

    return { success: true, authDeleted: true, authDetachedOnly: false }
  }

  if (body.deleteCustomerRecord === true) {
    const { error } = await serviceClient
      .from('customers')
      .delete()
      .eq('id', customer.id)
      .eq('tenant_id', caller.tenantId)
    if (error) throw error
  } else {
    const { error } = await serviceClient
      .from('customers')
      .update({ auth_user_id: null, updated_at: new Date().toISOString() })
      .eq('id', customer.id)
      .eq('tenant_id', caller.tenantId)
    if (error) throw error
  }

  return { success: true, authDeleted: false, authDetachedOnly: true }
}

async function deleteOrphanWebsiteAuthAccount(serviceClient: SupabaseClient, caller: CallerContext, authUserId: string) {
  const authUser = await getAuthUser(serviceClient, authUserId)
  if (!authUser || !isPublicStoreCustomerForTenant(authUser, caller.tenantId)) {
    throw new Error('Cuenta web no encontrada para este tenant')
  }

  if (await isStaffUserInTenant(serviceClient, caller.tenantId, authUserId)) {
    throw new Error('Esta cuenta Auth también pertenece al equipo ERP. Elimínala desde la pestaña Equipo si corresponde.')
  }

  const { data: linkedCustomer, error: customerError } = await serviceClient
    .from('customers')
    .select('id')
    .eq('tenant_id', caller.tenantId)
    .eq('auth_user_id', authUserId)
    .maybeSingle()
  if (customerError) throw customerError
  if (linkedCustomer) {
    throw new Error('Esta cuenta web ya tiene ficha CRM. Elimínala desde el cliente vinculado.')
  }

  await clearCustomerAuthReferencesForDelete(
    serviceClient,
    caller.tenantId,
    authUserId,
  )

  const { error } = await serviceClient.auth.admin.deleteUser(authUserId)
  if (error) throw new Error(`No se pudo eliminar el usuario Auth del cliente: ${error.message}`)
  return { success: true, authDeleted: true, authDetachedOnly: false }
}

async function clearCustomerAuthReferencesForDelete(
  serviceClient: SupabaseClient,
  tenantId: string,
  userId: string,
) {
  const operations = [
    serviceClient
      .from('conversations')
      .update({ created_by: null })
      .eq('tenant_id', tenantId)
      .eq('created_by', userId),
    serviceClient
      .from('conversations')
      .update({ accepted_by: null })
      .eq('tenant_id', tenantId)
      .eq('accepted_by', userId),
    serviceClient
      .from('conversation_contexts')
      .update({ added_by: null })
      .eq('tenant_id', tenantId)
      .eq('added_by', userId),
    serviceClient
      .from('messages')
      .update({ sender_id: null })
      .eq('tenant_id', tenantId)
      .eq('sender_id', userId),
  ]

  const results = await Promise.all(operations)
  for (const result of results) {
    if (result.error) throw result.error
  }
}

async function resendCustomerVerification(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  const customer = await getCustomer(serviceClient, caller.tenantId, required(body.customerId, 'customerId'))
  const email = normalizeEmail(body.email ?? customer.email)
  const { error } = await serviceClient.auth.resend({ type: 'signup', email })
  if (error) throw error
  return { success: true }
}

async function confirmUserEmail(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody) {
  const userId = required(body.userId, 'userId')
  await assertUserBelongsToTenant(serviceClient, caller.tenantId, userId)
  const { error } = await serviceClient.auth.admin.updateUserById(userId, { email_confirm: true })
  if (error) throw error
  return { success: true }
}

async function sendPasswordReset(serviceClient: SupabaseClient, caller: CallerContext, body: RequestBody, req: Request) {
  const email = normalizeEmail(required(body.email, 'email'))
  const user = await findAuthUserByEmail(serviceClient, email)
  if (user) await assertUserBelongsToTenant(serviceClient, caller.tenantId, user.id)

  let redirectTo = `${getOrigin(req)}/reset-password`
  if (user) {
    const { data: customer } = await serviceClient
      .from('customers')
      .select('id')
      .eq('tenant_id', caller.tenantId)
      .eq('auth_user_id', user.id)
      .maybeSingle()
    if (customer || isPublicStoreCustomerForTenant(user, caller.tenantId)) {
      redirectTo = `${await getStoreOrigin(serviceClient, caller.tenantId, req)}/cuenta/login`
    }
  }

  const accessLink = await generateRecoveryLink(serviceClient, email, redirectTo)
  return { success: true, passwordResetLinkGenerated: true, accessLink }
}

async function generateRecoveryLink(serviceClient: SupabaseClient, email: string, redirectTo: string) {
  const { data, error } = await serviceClient.auth.admin.generateLink({
    type: 'recovery',
    email,
    options: { redirectTo },
  })

  if (error) throw error
  const properties = (data as any)?.properties ?? {}
  const actionLink = properties.action_link ?? (data as any)?.action_link ?? null
  if (!actionLink) throw new Error('No se pudo generar el link de recuperación')
  return actionLink.toString()
}

async function assertStaffInTenant(serviceClient: SupabaseClient, tenantId: string, userId: string) {
  const { data, error } = await serviceClient
    .from('user_profiles')
    .select('user_id')
    .eq('tenant_id', tenantId)
    .eq('user_id', userId)
    .maybeSingle()

  if (error) throw error
  if (!data) throw new Error('User does not belong to this tenant staff')
}

async function isStaffUserInTenant(serviceClient: SupabaseClient, tenantId: string, userId: string) {
  const { data, error } = await serviceClient
    .from('user_profiles')
    .select('user_id')
    .eq('tenant_id', tenantId)
    .eq('user_id', userId)
    .maybeSingle()

  if (error) throw error
  return Boolean(data)
}

async function assertUserBelongsToTenant(serviceClient: SupabaseClient, tenantId: string, userId: string) {
  const [{ data: staff }, { data: customer }] = await Promise.all([
    serviceClient.from('user_profiles').select('user_id').eq('tenant_id', tenantId).eq('user_id', userId).maybeSingle(),
    serviceClient.from('customers').select('id').eq('tenant_id', tenantId).eq('auth_user_id', userId).maybeSingle(),
  ])

  if (staff || customer) return

  const authUser = await getAuthUser(serviceClient, userId)
  if (isPublicStoreCustomerForTenant(authUser, tenantId)) return

  throw new Error('User does not belong to this tenant')
}

async function getCustomer(serviceClient: SupabaseClient, tenantId: string, customerId: string) {
  const { data, error } = await serviceClient
    .from('customers')
    .select('id, name, email, phone, is_active, auth_user_id')
    .eq('id', customerId)
    .eq('tenant_id', tenantId)
    .maybeSingle()

  if (error) throw error
  if (!data) throw new Error('Customer not found in this tenant')
  return data
}

async function findCustomerByEmail(serviceClient: SupabaseClient, tenantId: string, email: string) {
  const { data, error } = await serviceClient
    .from('customers')
    .select('id, name, email, phone, is_active, auth_user_id')
    .eq('tenant_id', tenantId)
    .ilike('email', email)
    .limit(1)
    .maybeSingle()

  if (error) throw error
  return data
}

async function getAuthUser(serviceClient: SupabaseClient, userId: string | null) {
  if (!userId) return null
  const { data, error } = await serviceClient.auth.admin.getUserById(userId)
  if (error) {
    console.warn('Unable to load auth user', userId, error.message)
    return null
  }
  return data.user
}

async function findAuthUserByEmail(serviceClient: SupabaseClient, email: string) {
  let page = 1
  while (page <= 10) {
    const { data, error } = await serviceClient.auth.admin.listUsers({ page, perPage: 1000 })
    if (error) throw error
    const found = data.users.find((user) => user.email?.toLowerCase() === email.toLowerCase())
    if (found) return found
    if (data.users.length < 1000) return null
    page += 1
  }
  return null
}

async function getEmployeeName(serviceClient: SupabaseClient, employeeId: string, tenantId: string) {
  const { data } = await serviceClient
    .from('employees')
    .select('first_name, last_name')
    .eq('id', employeeId)
    .eq('tenant_id', tenantId)
    .maybeSingle()

  if (!data) return null
  return `${data.first_name ?? ''} ${data.last_name ?? ''}`.trim() || null
}

async function countRows(
  serviceClient: SupabaseClient,
  table: string,
  tenantId: string,
  filters: Record<string, unknown> = {},
) {
  let query = serviceClient.from(table).select('id', { count: 'exact', head: true }).eq('tenant_id', tenantId)

  for (const [key, value] of Object.entries(filters)) {
    if (value === 'not-null') query = query.not(key, 'is', null)
    else query = query.eq(key, value)
  }

  const { count, error } = await query
  if (error) throw error
  return count ?? 0
}

function normalizeRole(role: string) {
  const allowed = ['admin', 'manager', 'cashier', 'mechanic', 'accountant']
  if (!allowed.includes(role)) throw new Error(`Invalid role: ${role}`)
  return role
}

function normalizeEmail(email: string | null | undefined) {
  const normalized = email?.trim().toLowerCase()
  if (!normalized || !normalized.includes('@')) throw new Error('A valid email is required')
  return normalized
}

function getDisplayName(user: any) {
  return user?.user_metadata?.full_name ?? user?.user_metadata?.name ?? user?.user_metadata?.display_name ?? null
}

function isPublicStoreCustomerForTenant(user: any, tenantId: string) {
  return user?.user_metadata?.account_type === 'public_store_customer' &&
    user?.user_metadata?.customer_tenant_id === tenantId
}

function isBanned(user: any) {
  if (!user?.banned_until) return false
  return new Date(user.banned_until).getTime() > Date.now()
}

function generatePassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(18))
  const base = Array.from(bytes, (byte) => byte.toString(36).padStart(2, '0')).join('')
  return `Vina-${base.slice(0, 14)}!9`
}

function addDays(days: number) {
  const date = new Date()
  date.setDate(date.getDate() + days)
  return date.toISOString()
}

function getOrigin(req: Request) {
  const origin = req.headers.get('origin')
  if (origin) return origin
  return Deno.env.get('APP_URL') ?? 'https://project-vinabike.web.app'
}

async function getStoreOrigin(serviceClient: SupabaseClient, tenantId: string, req: Request) {
  const { data: tenant } = await serviceClient
    .from('tenants')
    .select('custom_domain, subdomain')
    .eq('id', tenantId)
    .maybeSingle()

  const customDomain = tenant?.custom_domain?.toString().trim()
  if (customDomain) {
    return customDomain.startsWith('http') ? customDomain : `https://${customDomain}`
  }

  const baseDomain = Deno.env.get('PUBLIC_STORE_BASE_DOMAIN')?.trim()
  const subdomain = tenant?.subdomain?.toString().trim()
  if (baseDomain && subdomain) {
    return `https://${subdomain}.${baseDomain}`
  }

  return getOrigin(req)
}

function required(value: string | undefined | null, name: string) {
  if (!value || !value.trim()) throw new Error(`${name} is required`)
  return value.trim()
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`${name} is not configured`)
  return value
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}