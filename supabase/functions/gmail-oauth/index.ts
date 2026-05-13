import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

const provider = 'gmail'
const gmailApiOrigin = 'https://www.googleapis.com'
const gmailAccountsOrigin = 'https://accounts.google.com'
const defaultGmailScopes = [
  'https://www.googleapis.com/auth/gmail.readonly',
  'https://www.googleapis.com/auth/gmail.send',
  'https://www.googleapis.com/auth/gmail.modify',
].join(' ')

serve(async (req) => {
  const url = new URL(req.url)

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method === 'GET') {
    return handleOAuthRedirect(url)
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  try {
    const body = await req.json().catch(() => ({}))
    const authContext = await requireAuthContext(req)
    const admin = adminClient()

    if (body.action) {
      return await handleAction(admin, authContext, body)
    }

    if (body.grant_type) {
      if (body.grant_type === 'authorization_code') {
        return await handleAuthorizationCode(admin, authContext, body)
      }
      if (body.grant_type === 'refresh_token') {
        const account = await requireAccount(admin, authContext.userId)
        const accessToken = await refreshStoredAccessToken(admin, account)
        return jsonResponse({
          connected: true,
          account: redactAccount({ ...account, access_token: accessToken }),
        })
      }
      return jsonResponse({ error: `Unsupported grant_type: ${body.grant_type}` }, 400)
    }

    if (body.proxy_url) {
      return await handleProxy(admin, authContext, body)
    }

    return jsonResponse({ error: 'Invalid request' }, 400)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    const status = message === 'Unauthorized' ? 401 : 400
    console.error('Gmail Edge Function Error:', message)
    return jsonResponse({ error: message }, status)
  }
})

function handleOAuthRedirect(url: URL) {
  const code = url.searchParams.get('code')
  const error = url.searchParams.get('error')
  const state = url.searchParams.get('state')
  const isMobile = state === 'mobile'

  const frontendBase = 'https://project-vinabike.web.app'
  const mobileDeepLink = 'vinabike://mail/oauth'

  if (error) {
    if (isMobile) {
      return Response.redirect(`${mobileDeepLink}?provider=gmail&error=${encodeURIComponent(error)}`, 302)
    }
    return Response.redirect(`${frontendBase}?gmail_error=${encodeURIComponent(error)}#/mail`, 302)
  }

  if (code) {
    if (isMobile) {
      return Response.redirect(`${mobileDeepLink}?provider=gmail&oauth_code=${encodeURIComponent(code)}`, 302)
    }
    return Response.redirect(`${frontendBase}?gmail_code=${encodeURIComponent(code)}#/mail`, 302)
  }

  return new Response('Method not allowed', { status: 405 })
}

async function handleAction(
  admin: ReturnType<typeof createClient>,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const action = cleanText(body.action)

  if (action === 'status') {
    const account = await loadAccount(admin, authContext.userId)
    return jsonResponse({
      connected: Boolean(account?.is_active),
      account: account ? redactAccount(account) : null,
    })
  }

  if (action === 'authorization_url') {
    const redirectUriValue = cleanText(body.redirect_uri)
    if (!redirectUriValue) return jsonResponse({ error: 'Missing redirect_uri' }, 400)

    const authUrl = new URL(`${gmailAccountsOrigin}/o/oauth2/v2/auth`)
    authUrl.searchParams.set('client_id', clientId())
    authUrl.searchParams.set('redirect_uri', redirectUriValue)
    authUrl.searchParams.set('response_type', 'code')
    authUrl.searchParams.set('scope', cleanText(body.scope) || defaultGmailScopes)
    authUrl.searchParams.set('access_type', 'offline')
    authUrl.searchParams.set('prompt', 'consent')
    const state = cleanText(body.state)
    if (state) authUrl.searchParams.set('state', state)

    return jsonResponse({ authorization_url: authUrl.toString() })
  }

  if (action === 'refresh') {
    const account = await requireAccount(admin, authContext.userId)
    const accessToken = await refreshStoredAccessToken(admin, account)
    return jsonResponse({
      connected: true,
      account: redactAccount({ ...account, access_token: accessToken }),
    })
  }

  if (action === 'list_inbox') {
    return await handleInboxList(admin, authContext, body)
  }

  if (action === 'disconnect') {
    await admin
      .from('email_accounts')
      .delete()
      .eq('user_id', authContext.userId)
      .eq('provider', provider)

    await admin
      .from('email_push_subscriptions')
      .delete()
      .eq('user_id', authContext.userId)
      .eq('provider', provider)

    return jsonResponse({ connected: false, account: null })
  }

  return jsonResponse({ error: `Unknown action: ${action}` }, 400)
}

async function handleAuthorizationCode(
  admin: ReturnType<typeof createClient>,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const code = cleanText(body.code)
  const redirectUriValue = cleanText(body.redirect_uri)
  if (!code || !redirectUriValue) throw new Error('Missing code or redirect_uri')

  const tokenPayload = await exchangeCode(code, redirectUriValue)
  const accessToken = cleanText(tokenPayload.access_token)
  if (!accessToken) throw new Error('Gmail did not return an access token')

  const profile = await fetchGmailProfile(accessToken)
  const accountEmail = cleanText(profile.emailAddress)
  if (!accountEmail) throw new Error('Could not resolve Gmail account email')

  const existing = await loadAccount(admin, authContext.userId)
  const refreshTokenValue = cleanText(tokenPayload.refresh_token) || cleanText(existing?.refresh_token)
  if (!refreshTokenValue) {
    throw new Error('Gmail did not return a refresh token. Reconnect and approve offline access.')
  }

  const expiresAt = new Date(Date.now() + Number(tokenPayload.expires_in || 3600) * 1000).toISOString()
  const now = new Date().toISOString()

  const { data, error } = await admin
    .from('email_accounts')
    .upsert({
      tenant_id: authContext.tenantId,
      user_id: authContext.userId,
      provider,
      account_email: accountEmail,
      provider_account_id: accountEmail,
      access_token: accessToken,
      refresh_token: refreshTokenValue,
      token_type: cleanText(tokenPayload.token_type),
      scope: cleanText(tokenPayload.scope),
      token_expires_at: expiresAt,
      provider_metadata: profile,
      is_active: true,
      last_connected_at: now,
      last_error: null,
      updated_at: now,
    }, { onConflict: 'user_id,provider' })
    .select('*')
    .single()

  if (error) throw error

  return jsonResponse({ connected: true, account: redactAccount(data) })
}

async function handleProxy(
  admin: ReturnType<typeof createClient>,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const proxyUrl = cleanText(body.proxy_url)
  assertAllowedGmailUrl(proxyUrl)

  const account = await requireAccount(admin, authContext.userId)
  const accessToken = await ensureValidAccessToken(admin, account)
  const response = await fetchWithToken(proxyUrl, body, accessToken)

  if (response.status !== 401) return response

  const refreshedToken = await refreshStoredAccessToken(admin, account)
  return await fetchWithToken(proxyUrl, body, refreshedToken)
}

async function handleInboxList(
  admin: ReturnType<typeof createClient>,
  authContext: AuthContext,
  body: Record<string, unknown>,
) {
  const account = await requireAccount(admin, authContext.userId)
  const firstToken = await ensureValidAccessToken(admin, account)
  const firstAttempt = await fetchInboxMetadata(firstToken, body)

  if (firstAttempt.status !== 401) {
    return jsonResponse(firstAttempt.payload, firstAttempt.status)
  }

  const refreshedToken = await refreshStoredAccessToken(admin, account)
  const secondAttempt = await fetchInboxMetadata(refreshedToken, body)
  return jsonResponse(secondAttempt.payload, secondAttempt.status)
}

async function fetchInboxMetadata(accessToken: string, body: Record<string, unknown>) {
  const rawLimit = Number(body.limit ?? 30)
  const limit = Number.isFinite(rawLimit)
    ? Math.min(Math.max(Math.trunc(rawLimit), 1), 50)
    : 30
  const knownIds = parseKnownIds(body.known_ids)
  const pageToken = cleanText(body.page_token)
  const searchQuery = cleanText(body.search_query)

  const listUrl = new URL(`${gmailApiOrigin}/gmail/v1/users/me/messages`)
  listUrl.searchParams.set('maxResults', String(limit))
  listUrl.searchParams.append('labelIds', 'INBOX')
  if (pageToken) listUrl.searchParams.set('pageToken', pageToken)
  if (searchQuery) listUrl.searchParams.set('q', searchQuery)

  const listResponse = await fetch(listUrl, {
    headers: { 'Authorization': `Bearer ${accessToken}` },
  })
  const listPayload = await listResponse.json().catch(() => ({}))

  if (!listResponse.ok) {
    return { status: listResponse.status, payload: listPayload }
  }

  const messageRefs = Array.isArray(listPayload.messages)
    ? listPayload.messages as Array<Record<string, unknown>>
    : []

  const messages = await mapWithConcurrency(messageRefs, 8, async (messageRef) => {
    const id = cleanText(messageRef.id)
    if (!id) return null

    if (knownIds.has(id)) {
      return { id, known: true }
    }

    const detailUrl = new URL(`${gmailApiOrigin}/gmail/v1/users/me/messages/${encodeURIComponent(id)}`)
    detailUrl.searchParams.set('format', 'metadata')
    detailUrl.searchParams.append('metadataHeaders', 'From')
    detailUrl.searchParams.append('metadataHeaders', 'To')
    detailUrl.searchParams.append('metadataHeaders', 'Subject')
    detailUrl.searchParams.append('metadataHeaders', 'Date')

    const detailResponse = await fetch(detailUrl, {
      headers: { 'Authorization': `Bearer ${accessToken}` },
    })
    const detailPayload = await detailResponse.json().catch(() => ({}))

    if (!detailResponse.ok) {
      console.error('Gmail inbox metadata fetch failed:', id, detailResponse.status, detailPayload)
      return null
    }

    return detailPayload
  })

  return {
    status: 200,
    payload: {
      messages: messages.filter(Boolean),
      nextPageToken: listPayload.nextPageToken ?? null,
      resultSizeEstimate: listPayload.resultSizeEstimate ?? null,
    },
  }
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  mapper: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length)
  let nextIndex = 0

  async function worker() {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex
      nextIndex += 1
      results[currentIndex] = await mapper(items[currentIndex], currentIndex)
    }
  }

  const workerCount = Math.min(concurrency, items.length)
  await Promise.all(Array.from({ length: workerCount }, () => worker()))
  return results
}

function parseKnownIds(value: unknown): Set<string> {
  if (!Array.isArray(value)) return new Set()
  return new Set(
    value
      .map((item) => cleanText(item))
      .filter((item) => item.length > 0)
      .slice(0, 100),
  )
}

async function fetchWithToken(proxyUrl: string, body: Record<string, unknown>, accessToken: string) {
  const fetchOptions: RequestInit = {
    method: cleanText(body.method) || 'GET',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
  }

  if (body.body) fetchOptions.body = JSON.stringify(body.body)

  const response = await fetch(proxyUrl, fetchOptions)
  const responseText = await response.text()
  let responseData: unknown
  try {
    responseData = JSON.parse(responseText)
  } catch (_) {
    responseData = { text: responseText }
  }

  return new Response(JSON.stringify(responseData), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status: response.status,
  })
}

async function exchangeCode(code: string, redirectUriValue: string) {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: clientSecret(),
      code,
      redirect_uri: redirectUriValue,
      grant_type: 'authorization_code',
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok || payload.error) {
    throw new Error(payload.error_description || payload.error || 'Could not exchange Gmail code')
  }
  return payload
}

async function refreshToken(refreshTokenValue: string) {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: clientSecret(),
      refresh_token: refreshTokenValue,
      grant_type: 'refresh_token',
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok || payload.error) {
    throw new Error(payload.error_description || payload.error || 'Could not refresh Gmail token')
  }
  return payload
}

async function fetchGmailProfile(accessToken: string) {
  const profileRes = await fetch('https://www.googleapis.com/gmail/v1/users/me/profile', {
    headers: { 'Authorization': `Bearer ${accessToken}` },
  })
  const profile = await profileRes.json().catch(() => ({}))
  if (!profileRes.ok) throw new Error(profile.error?.message || 'Could not fetch Gmail profile')
  return profile
}

async function ensureValidAccessToken(admin: ReturnType<typeof createClient>, account: EmailAccount): Promise<string> {
  const accessToken = cleanText(account.access_token)
  const expiresAt = account.token_expires_at ? new Date(account.token_expires_at).getTime() : 0
  const refreshAt = Date.now() + 5 * 60 * 1000

  if (accessToken && expiresAt > refreshAt) return accessToken
  return await refreshStoredAccessToken(admin, account)
}

async function refreshStoredAccessToken(admin: ReturnType<typeof createClient>, account: EmailAccount): Promise<string> {
  const refreshTokenValue = cleanText(account.refresh_token)
  if (!refreshTokenValue) throw new Error('Missing stored Gmail refresh token')

  const payload = await refreshToken(refreshTokenValue)
  const accessToken = cleanText(payload.access_token)
  if (!accessToken) throw new Error('Gmail did not return a refreshed access token')

  const expiresAt = new Date(Date.now() + Number(payload.expires_in || 3600) * 1000).toISOString()
  const now = new Date().toISOString()

  const { error } = await admin
    .from('email_accounts')
    .update({
      access_token: accessToken,
      token_type: cleanText(payload.token_type) || account.token_type,
      scope: cleanText(payload.scope) || account.scope,
      token_expires_at: expiresAt,
      last_token_refresh_at: now,
      last_error: null,
      updated_at: now,
    })
    .eq('id', account.id)

  if (error) throw error
  return accessToken
}

async function loadAccount(admin: ReturnType<typeof createClient>, userId: string): Promise<EmailAccount | null> {
  const { data, error } = await admin
    .from('email_accounts')
    .select('*')
    .eq('user_id', userId)
    .eq('provider', provider)
    .maybeSingle()

  if (error) throw error
  return data as EmailAccount | null
}

async function requireAccount(admin: ReturnType<typeof createClient>, userId: string): Promise<EmailAccount> {
  const account = await loadAccount(admin, userId)
  if (!account || account.is_active === false) throw new Error('Gmail account is not connected')
  return account
}

async function requireAuthContext(req: Request): Promise<AuthContext> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) throw new Error('Unauthorized')

  const userClient = createClient(
    supabaseUrl(),
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  )

  const { data, error } = await userClient.auth.getUser()
  if (error || !data.user) throw new Error('Unauthorized')

  const admin = adminClient()
  const { data: profile, error: profileError } = await admin
    .from('user_profiles')
    .select('tenant_id')
    .eq('user_id', data.user.id)
    .maybeSingle()

  if (profileError) throw profileError
  const tenantId = cleanText(profile?.tenant_id)
  if (!tenantId) throw new Error('Current user has no tenant profile')

  return { userId: data.user.id, tenantId }
}

function assertAllowedGmailUrl(value: string) {
  const parsed = new URL(value)
  if (parsed.origin !== gmailApiOrigin || !parsed.pathname.startsWith('/gmail/v1/users/me/')) {
    throw new Error('Blocked Gmail proxy URL')
  }
}

function redactAccount(account: Partial<EmailAccount>) {
  return {
    provider,
    account_email: account.account_email ?? null,
    provider_account_id: account.provider_account_id ?? null,
    token_expires_at: account.token_expires_at ?? null,
    is_active: account.is_active !== false,
    updated_at: account.updated_at ?? null,
  }
}

function adminClient() {
  return createClient(supabaseUrl(), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
}

function supabaseUrl() {
  const value = Deno.env.get('SUPABASE_URL') ?? ''
  if (!value) throw new Error('Missing SUPABASE_URL')
  return value
}

function clientId() {
  const value = Deno.env.get('GMAIL_CLIENT_ID') ?? ''
  if (!value) throw new Error('Missing GMAIL_CLIENT_ID')
  return value
}

function clientSecret() {
  const value = Deno.env.get('GMAIL_CLIENT_SECRET') ?? ''
  if (!value) throw new Error('Missing GMAIL_CLIENT_SECRET')
  return value
}

function cleanText(value: unknown) {
  return String(value ?? '').trim()
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

type AuthContext = {
  userId: string
  tenantId: string
}

type EmailAccount = {
  id: string
  tenant_id: string
  user_id: string
  provider: string
  account_email: string
  provider_account_id?: string | null
  access_token?: string | null
  refresh_token?: string | null
  token_type?: string | null
  scope?: string | null
  token_expires_at?: string | null
  is_active?: boolean | null
  updated_at?: string | null
}