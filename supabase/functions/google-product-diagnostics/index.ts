import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const merchantScope = 'https://www.googleapis.com/auth/content'
const searchConsoleIntegrationKey = 'search_console'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Use POST' }, 405)
  }

  try {
    const body = await req.json().catch(() => ({}))
    const productUrl = cleanText(body.productUrl)
    const offerId = cleanText(body.offerId || body.productId)

    if (!productUrl) {
      return jsonResponse({ error: 'Missing productUrl' }, 400)
    }

    const requiredSecrets = [
      'GOOGLE_SEARCH_CONSOLE_CLIENT_ID',
      'GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET',
      'GOOGLE_SEARCH_CONSOLE_SITE_URL',
      'GOOGLE_SERVICE_ACCOUNT_EMAIL',
      'GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY',
      'GOOGLE_MERCHANT_ACCOUNT_ID',
    ]

    const email = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL') || ''
    const privateKey = normalizePrivateKey(
      Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY') || '',
    )
    const siteUrl =
      Deno.env.get('GOOGLE_SEARCH_CONSOLE_SITE_URL') || 'sc-domain:vinabike.cl'
    const merchantAccountId = Deno.env.get('GOOGLE_MERCHANT_ACCOUNT_ID') || ''

    const hasServiceAccount = Boolean(email && privateKey)
    const feedEligibility = offerId
      ? await getMerchantFeedEligibility(offerId)
      : null

    const [searchConsole, merchant] = await Promise.all([
      inspectSearchConsole({ siteUrl, productUrl }),
      hasServiceAccount && merchantAccountId && offerId
        ? inspectMerchant({
          email,
          privateKey,
          merchantAccountId,
          offerId,
          feedEligibility,
        })
        : Promise.resolve({
          configured: false,
          feedEligibility,
          requiredSecrets: [
            ...(hasServiceAccount ? [] : [
              'GOOGLE_SERVICE_ACCOUNT_EMAIL',
              'GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY',
            ]),
            ...(merchantAccountId ? [] : ['GOOGLE_MERCHANT_ACCOUNT_ID']),
          ],
        }),
    ])

    return jsonResponse({
      ok: true,
      generatedAt: new Date().toISOString(),
      productUrl,
      offerId,
      searchConsole,
      merchant,
      setup: {
        requiredSecrets,
        notes: [
          'Connect Search Console with OAuth from the ERP using a Google account that has access to vinabike.cl.',
          'Add the same service account to Merchant Center with product read access.',
        ],
      },
    })
  } catch (error) {
    console.error('google-product-diagnostics error', error)
    return jsonResponse({ error: error?.message || String(error) }, 500)
  }
})

async function inspectSearchConsole(args: {
  siteUrl: string
  productUrl: string
}) {
  try {
    const tokenResult = await searchConsoleOAuthToken()
    if (!tokenResult.ok) {
      return {
        configured: false,
        connectRequired: true,
        error: tokenResult.error,
        requiredSecrets: tokenResult.requiredSecrets || [],
      }
    }

    const response = await fetch(
      'https://searchconsole.googleapis.com/v1/urlInspection/index:inspect',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${tokenResult.accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          inspectionUrl: args.productUrl,
          siteUrl: args.siteUrl,
          languageCode: 'es-CL',
        }),
      },
    )

    const payload = await response.json().catch(() => ({}))
    if (!response.ok) {
      const visibleSites = response.status === 403
        ? await listSearchConsoleSites(tokenResult.accessToken)
        : null

      return {
        configured: true,
        ok: false,
        status: response.status,
        errorCode: payload?.error?.status || payload?.error?.code || null,
        error: payload?.error?.message || JSON.stringify(payload),
        searchedSiteUrl: args.siteUrl,
        availableSites: visibleSites?.sites || [],
        availableSitesError: visibleSites?.error || null,
      }
    }

    const indexStatus = payload?.inspectionResult?.indexStatusResult || {}
    const richResults = payload?.inspectionResult?.richResultsResult || {}

    return {
      configured: true,
      ok: true,
      verdict: indexStatus.verdict,
      coverageState: indexStatus.coverageState,
      robotsTxtState: indexStatus.robotsTxtState,
      indexingState: indexStatus.indexingState,
      pageFetchState: indexStatus.pageFetchState,
      lastCrawlTime: indexStatus.lastCrawlTime,
      googleCanonical: indexStatus.googleCanonical,
      userCanonical: indexStatus.userCanonical,
      sitemap: indexStatus.sitemap,
      richResultsVerdict: richResults.verdict,
      raw: payload,
    }
  } catch (error) {
    return {
      configured: true,
      ok: false,
      error: error?.message || String(error),
    }
  }
}

async function getMerchantFeedEligibility(offerId: string) {
  if (!isUuid(offerId)) {
    return {
      known: false,
      eligible: false,
      reasons: [
        'El offer id no es un UUID de producto local, así que no se pudo validar contra el feed ERP.',
      ],
    }
  }

  const { data, error } = await adminClient()
    .from('products')
    .select('id, name, is_active, is_published, is_google_merchant, lifecycle_status, price, stock_quantity')
    .eq('id', offerId)
    .maybeSingle()

  if (error) {
    return {
      known: false,
      eligible: false,
      reasons: ['No se pudo revisar si el producto entra al feed Merchant.'],
      error: error.message,
    }
  }

  if (!data) {
    return {
      known: true,
      eligible: false,
      reasons: ['El producto no existe en la base local.'],
    }
  }

  const reasons: string[] = []
  if (data.is_active !== true) reasons.push('El producto no esta activo.')
  if (data.is_published !== true) reasons.push('El producto no esta publicado en la tienda online.')
  if (data.is_google_merchant !== true) reasons.push('Google Merchant esta desactivado para este producto.')
  if (data.lifecycle_status !== 'active') reasons.push(`El ciclo de vida es ${cleanText(data.lifecycle_status) || 'desconocido'}, no active.`)
  if (Number(data.price || 0) <= 0) reasons.push('El precio guardado debe ser mayor a 0.')

  return {
    known: true,
    eligible: reasons.length === 0,
    reasons,
    product: {
      id: data.id,
      name: data.name,
      isActive: data.is_active === true,
      isPublished: data.is_published === true,
      isGoogleMerchant: data.is_google_merchant === true,
      lifecycleStatus: data.lifecycle_status,
      price: data.price,
      stockQuantity: data.stock_quantity,
    },
  }
}

async function listSearchConsoleSites(accessToken: string): Promise<{
  sites: Array<{ siteUrl: string; permissionLevel: string }>
  error?: string | null
}> {
  const response = await fetch('https://www.googleapis.com/webmasters/v3/sites', {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: 'application/json',
    },
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    return {
      sites: [],
      error: payload?.error?.message || JSON.stringify(payload),
    }
  }

  const siteEntry = Array.isArray(payload?.siteEntry) ? payload.siteEntry : []
  return {
    sites: siteEntry
      .map((site) => ({
        siteUrl: cleanText(site?.siteUrl),
        permissionLevel: cleanText(site?.permissionLevel),
      }))
      .filter((site) => site.siteUrl.length > 0),
    error: null,
  }
}

async function searchConsoleOAuthToken(): Promise<{
  ok: true
  accessToken: string
} | {
  ok: false
  error: string
  requiredSecrets?: string[]
}> {
  const clientId = Deno.env.get('GOOGLE_SEARCH_CONSOLE_CLIENT_ID') || ''
  const clientSecret = Deno.env.get('GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET') || ''
  if (!clientId || !clientSecret) {
    return {
      ok: false,
      error: 'Search Console OAuth is not configured.',
      requiredSecrets: [
        ...(clientId ? [] : ['GOOGLE_SEARCH_CONSOLE_CLIENT_ID']),
        ...(clientSecret ? [] : ['GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET']),
      ],
    }
  }

  const supabase = adminClient()
  const { data, error } = await supabase
    .from('google_oauth_connections')
    .select('access_token, refresh_token, expires_at')
    .eq('integration_key', searchConsoleIntegrationKey)
    .maybeSingle()

  if (error) throw error
  if (!data) {
    return {
      ok: false,
      error: 'Search Console is not connected yet.',
    }
  }

  const expiresAt = data.expires_at
    ? new Date(data.expires_at).getTime()
    : 0
  if (data.access_token && expiresAt > Date.now() + 120000) {
    return { ok: true, accessToken: data.access_token }
  }

  if (!data.refresh_token) {
    return {
      ok: false,
      error: 'Search Console needs to be reconnected to refresh access.',
    }
  }

  const refreshed = await refreshGoogleOAuthToken({
    clientId,
    clientSecret,
    refreshToken: data.refresh_token,
  })
  const expiresAtDate = new Date(
    Date.now() + Number(refreshed.expires_in || 3600) * 1000,
  )

  const { error: updateError } = await supabase
    .from('google_oauth_connections')
    .update({
      access_token: refreshed.access_token,
      token_type: refreshed.token_type || 'Bearer',
      scope: refreshed.scope || null,
      expires_at: expiresAtDate.toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq('integration_key', searchConsoleIntegrationKey)

  if (updateError) throw updateError
  return { ok: true, accessToken: refreshed.access_token }
}

async function refreshGoogleOAuthToken(args: {
  clientId: string
  clientSecret: string
  refreshToken: string
}) {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: args.clientId,
      client_secret: args.clientSecret,
      refresh_token: args.refreshToken,
      grant_type: 'refresh_token',
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok || !payload.access_token) {
    throw new Error(payload?.error_description || payload?.error || 'Could not refresh Google OAuth token')
  }
  return payload
}

async function inspectMerchant(args: {
  email: string
  privateKey: string
  merchantAccountId: string
  offerId: string
  feedEligibility: Awaited<ReturnType<typeof getMerchantFeedEligibility>> | null
}) {
  try {
    if (args.feedEligibility?.known && !args.feedEligibility.eligible) {
      return {
        configured: true,
        ok: false,
        status: 'not_in_feed',
        error: `Este producto no se esta enviando al feed Merchant: ${args.feedEligibility.reasons.join(' ')}`,
        feedEligibility: args.feedEligibility,
      }
    }

    const token = await serviceAccountAccessToken({
      email: args.email,
      privateKey: args.privateKey,
      scopes: [merchantScope],
    })

    const encodedIds = [
      `online:es:CL:${args.offerId}`,
      `online:en:CL:${args.offerId}`,
    ].map((id) => encodeURIComponent(id))

    const attempts = []
    for (const productId of encodedIds) {
      const response = await fetch(
        `https://shoppingcontent.googleapis.com/content/v2.1/${args.merchantAccountId}/productstatuses/${productId}`,
        {
          headers: {
            Authorization: `Bearer ${token}`,
            Accept: 'application/json',
          },
        },
      )
      const payload = await response.json().catch(() => ({}))
      attempts.push({ status: response.status, payload })
      if (response.status === 401 || response.status === 403) {
        return {
          configured: true,
          ok: false,
          status: 'merchant_access_denied',
          error:
            payload?.error?.message ||
            'La cuenta tecnica de Google no tiene acceso a este Merchant Center. Agrega el service account como usuario en Merchant Center o corrige GOOGLE_MERCHANT_ACCOUNT_ID.',
          feedEligibility: args.feedEligibility,
          attempts,
        }
      }
      if (response.ok) {
        const issues = payload?.itemLevelIssues || []
        return {
          configured: true,
          ok: true,
          feedEligibility: args.feedEligibility,
          status: payload?.destinationStatuses?.[0]?.status ||
            payload?.kind ||
            'found',
          productId: payload?.productId,
          title: payload?.title,
          link: payload?.link,
          destinationStatuses: payload?.destinationStatuses || [],
          itemLevelIssues: issues,
          issueCount: issues.length,
          raw: payload,
        }
      }
    }

    return {
      configured: true,
      ok: false,
      status: 'not_found_or_not_ready',
      error:
        args.feedEligibility?.eligible
          ? 'El producto cumple las reglas locales del feed, pero Merchant Center aun no lo encuentra. Fuerza una lectura del feed en Merchant Center o espera a que Google procese el item.'
          : 'Merchant product status was not found yet. It may still be processing, or the offer id/language/country differs.',
      feedEligibility: args.feedEligibility,
      attempts,
    }
  } catch (error) {
    return {
      configured: true,
      ok: false,
      error: error?.message || String(error),
      feedEligibility: args.feedEligibility,
    }
  }
}

async function serviceAccountAccessToken(args: {
  email: string
  privateKey: string
  scopes: string[]
}) {
  const now = Math.floor(Date.now() / 1000)
  const claim = {
    iss: args.email,
    scope: args.scopes.join(' '),
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }
  const jwt = await signJwt({ claim, privateKey: args.privateKey })
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok || !payload.access_token) {
    throw new Error(payload?.error_description || payload?.error || 'Could not get Google access token')
  }
  return payload.access_token as string
}

async function signJwt(args: {
  claim: Record<string, unknown>
  privateKey: string
}) {
  const encoder = new TextEncoder()
  const header = { alg: 'RS256', typ: 'JWT' }
  const signingInput = `${base64UrlJson(header)}.${base64UrlJson(args.claim)}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(args.privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    encoder.encode(signingInput),
  )
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`
}

function base64UrlJson(value: Record<string, unknown>) {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)))
}

function base64Url(bytes: Uint8Array) {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

function pemToArrayBuffer(pem: string) {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '')
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}

function normalizePrivateKey(value: string) {
  return value.replace(/\\n/g, '\n').trim()
}

function adminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )
}

function cleanText(value: unknown) {
  return String(value ?? '').trim()
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
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
