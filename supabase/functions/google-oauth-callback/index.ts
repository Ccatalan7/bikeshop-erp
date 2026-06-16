import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

const integrationKey = 'search_console'
const searchConsoleScope = 'https://www.googleapis.com/auth/webmasters'
const userEmailScope = 'https://www.googleapis.com/auth/userinfo.email'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (req.method === 'GET') return handleCallback(req)
    if (req.method === 'POST') return handlePost(req)
    return jsonResponse({ error: 'Use GET or POST' }, 405)
  } catch (error) {
    console.error('google-oauth-callback error', error)
    return jsonResponse({ error: errorMessage(error) }, 500)
  }
})

async function handlePost(req: Request) {
  const body = await req.json().catch(() => ({}))
  const action = cleanText(body.action || 'start')

  if (action === 'status') {
    const admin = adminClient()
    const { data } = await admin
      .from('google_oauth_connections')
      .select('account_email, scope, expires_at, updated_at')
      .eq('integration_key', integrationKey)
      .maybeSingle()

    return jsonResponse({
      connected: Boolean(data),
      connection: data || null,
    })
  }

  if (action !== 'start') {
    return jsonResponse({ error: `Unknown action: ${action}` }, 400)
  }

  const user = await currentUser(req)
  const state = crypto.randomUUID()
  const admin = adminClient()

  const { error } = await admin.from('google_oauth_states').insert({
    state,
    created_by: user?.id || null,
  })
  if (error) throw error

  const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth')
  authUrl.searchParams.set('client_id', clientId())
  authUrl.searchParams.set('redirect_uri', redirectUri())
  authUrl.searchParams.set('response_type', 'code')
  authUrl.searchParams.set('scope', `${searchConsoleScope} ${userEmailScope}`)
  authUrl.searchParams.set('access_type', 'offline')
  authUrl.searchParams.set('prompt', 'consent select_account')
  authUrl.searchParams.set('include_granted_scopes', 'true')
  authUrl.searchParams.set('state', state)
  authUrl.searchParams.set('login_hint', 'vinabikechile@gmail.com')

  return jsonResponse({ authUrl: authUrl.toString() })
}

async function handleCallback(req: Request) {
  const url = new URL(req.url)
  const code = url.searchParams.get('code')
  const error = url.searchParams.get('error')
  const state = url.searchParams.get('state')

  if (error) {
    return htmlResponse(`Google rejected the authorization: ${escapeHtml(error)}`, 400)
  }
  if (!code || !state) {
    return htmlResponse('Missing Google authorization code or state.', 400)
  }

  const admin = adminClient()
  const { data: stateRow, error: stateError } = await admin
    .from('google_oauth_states')
    .select('state, created_by, expires_at')
    .eq('state', state)
    .maybeSingle()

  if (stateError) throw stateError
  if (!stateRow || new Date(stateRow.expires_at).getTime() < Date.now()) {
    return htmlResponse('This authorization link expired. Go back to the ERP and connect again.', 400)
  }

  const tokens = await exchangeCode(code)
  const accessToken = cleanText(tokens.access_token)
  if (!accessToken) throw new Error('Google did not return an access token')

  const accountEmail = await fetchGoogleEmail(accessToken)
  const expiresAt = new Date(Date.now() + Number(tokens.expires_in || 3600) * 1000)
  const existing = await admin
    .from('google_oauth_connections')
    .select('refresh_token')
    .eq('integration_key', integrationKey)
    .maybeSingle()

  const refreshToken = cleanText(tokens.refresh_token) ||
    cleanText(existing.data?.refresh_token)

  const { error: upsertError } = await admin
    .from('google_oauth_connections')
    .upsert({
      integration_key: integrationKey,
      provider: 'google',
      account_email: accountEmail || null,
      access_token: accessToken,
      refresh_token: refreshToken || null,
      token_type: cleanText(tokens.token_type),
      scope: cleanText(tokens.scope),
      expires_at: expiresAt.toISOString(),
      updated_by: stateRow.created_by,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'integration_key' })

  if (upsertError) throw upsertError

  await admin.from('google_oauth_states').delete().eq('state', state)

  return htmlResponse(`
    <h1>Search Console conectado</h1>
    <p>Cuenta autorizada: <strong>${escapeHtml(accountEmail || 'Google')}</strong></p>
    <p>Ya puedes cerrar esta pestaña y volver al ERP.</p>
  `)
}

async function exchangeCode(code: string) {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: clientSecret(),
      code,
      redirect_uri: redirectUri(),
      grant_type: 'authorization_code',
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(payload?.error_description || payload?.error || 'Could not exchange Google code')
  }
  return payload
}

async function fetchGoogleEmail(accessToken: string) {
  const response = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  const payload = await response.json().catch(() => ({}))
  return cleanText(payload?.email)
}

async function currentUser(req: Request) {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return null

  const client = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  )
  const { data } = await client.auth.getUser()
  return data.user
}

function adminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )
}

function clientId() {
  const value = Deno.env.get('GOOGLE_SEARCH_CONSOLE_CLIENT_ID') || ''
  if (!value) throw new Error('Missing GOOGLE_SEARCH_CONSOLE_CLIENT_ID')
  return value
}

function clientSecret() {
  const value = Deno.env.get('GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET') || ''
  if (!value) throw new Error('Missing GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET')
  return value
}

function redirectUri() {
  return Deno.env.get('GOOGLE_SEARCH_CONSOLE_REDIRECT_URI') ||
    'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-oauth-callback'
}

function cleanText(value: unknown) {
  return String(value ?? '').trim()
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}

function htmlResponse(body: string, status = 200) {
  return new Response(`<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Vinabike Google OAuth</title>
  <style>
    body { font-family: Inter, system-ui, sans-serif; margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f6f8fb; color: #14213d; }
    main { max-width: 520px; padding: 32px; background: white; border: 1px solid #dbe3ef; border-radius: 18px; box-shadow: 0 18px 45px rgba(20,33,61,.08); }
    h1 { margin-top: 0; font-size: 28px; }
    p { line-height: 1.5; color: #526176; }
  </style>
</head>
<body><main>${body}</main></body>
</html>`, {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'text/html; charset=utf-8',
    },
  })
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}
