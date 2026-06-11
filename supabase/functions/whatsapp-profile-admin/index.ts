import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-admin-token, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const WHATSAPP_ACCESS_TOKEN = Deno.env.get('WHATSAPP_ACCESS_TOKEN') ?? ''
const WHATSAPP_API_VERSION = Deno.env.get('WHATSAPP_API_VERSION') ?? 'v23.0'
const WHATSAPP_PROFILE_ADMIN_TOKEN = Deno.env.get('WHATSAPP_PROFILE_ADMIN_TOKEN') ?? ''

type JsonRecord = Record<string, unknown>

interface AdminRequest {
  action?:
    | 'inspect'
    | 'inspect_token'
    | 'inspect_catalog'
    | 'inspect_catalog_id'
    | 'inspect_catalog_assets'
    | 'graph_get'
    | 'graph_post'
    | 'connect_catalog'
    | 'upsert_catalog_product'
    | 'update_profile'
    | 'upload_profile_picture'
  tenantId?: string
  phoneNumberId?: string
  productId?: string
  catalogId?: string
  path?: string
  body?: JsonRecord
  profile?: JsonRecord
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}

function isAuthorized(req: Request) {
  const adminToken = req.headers.get('x-admin-token') ?? ''
  if (WHATSAPP_PROFILE_ADMIN_TOKEN && adminToken === WHATSAPP_PROFILE_ADMIN_TOKEN) {
    return true
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  const bearerToken = authHeader.replace(/^Bearer\s+/i, '')
  return Boolean(SUPABASE_SERVICE_ROLE_KEY && bearerToken === SUPABASE_SERVICE_ROLE_KEY)
}

async function graphRequest(
  path: string,
  options: RequestInit = {},
) {
  const response = await fetch(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${path}`,
    {
      ...options,
      headers: {
        Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
        ...(options.headers ?? {}),
      },
    },
  )

  const text = await response.text()
  let payload: unknown = text
  try {
    payload = text ? JSON.parse(text) : null
  } catch (_) {
    payload = text
  }

  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      payload,
    }
  }

  return {
    ok: true,
    status: response.status,
    payload,
  }
}

async function graphJsonRequest(
  url: string,
  options: RequestInit = {},
) {
  const response = await fetch(url, options)
  const text = await response.text()
  let payload: unknown = text
  try {
    payload = text ? JSON.parse(text) : null
  } catch (_) {
    payload = text
  }

  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      payload,
    }
  }

  return {
    ok: true,
    status: response.status,
    payload,
  }
}

async function resolveChannel(request: AdminRequest) {
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  let query = adminClient
    .from('whatsapp_channels')
    .select('id, tenant_id, phone_number_id, business_account_id, display_name, display_phone_number, is_active, created_at, updated_at')
    .eq('is_active', true)

  if (request.tenantId) {
    query = query.eq('tenant_id', request.tenantId)
  }
  if (request.phoneNumberId) {
    query = query.eq('phone_number_id', request.phoneNumberId)
  }

  const { data, error } = await query.limit(1).maybeSingle()
  if (error) throw error
  return data as JsonRecord | null
}

async function loadProduct(tenantId: string, productId: string) {
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const { data, error } = await adminClient
    .from('products')
    .select([
      'id',
      'tenant_id',
      'name',
      'sku',
      'description',
      'brand',
      'category_name',
      'price',
      'inventory_qty',
      'stock_quantity',
      'is_active',
      'is_published',
      'is_whatsapp_catalog',
      'whatsapp_catalog_title',
      'whatsapp_catalog_description',
      'whatsapp_catalog_price',
      'website_name',
      'website_description',
      'website_price',
      'website_image_url',
      'website_image_url_optimized',
      'image_url',
      'image_url_optimized',
    ].join(','))
    .eq('tenant_id', tenantId)
    .eq('id', productId)
    .maybeSingle()

  if (error) throw error
  return data as JsonRecord | null
}

function sanitizedProfile(input: JsonRecord = {}) {
  const allowedKeys = [
    'about',
    'address',
    'description',
    'email',
    'profile_picture_handle',
    'vertical',
    'websites',
  ]
  const profile: JsonRecord = {}

  for (const key of allowedKeys) {
    if (input[key] === undefined) continue
    profile[key] = input[key]
  }

  return profile
}

async function inspectProfile(channel: JsonRecord) {
  const phoneNumberId = String(channel.phone_number_id)
  const businessAccountId = channel.business_account_id
    ? String(channel.business_account_id)
    : ''

  const profileFields = [
    'about',
    'address',
    'description',
    'email',
    'profile_picture_url',
    'websites',
    'vertical',
  ].join(',')
  const phoneFields = [
    'id',
    'display_phone_number',
    'verified_name',
    'quality_rating',
    'messaging_limit_tier',
    'status',
    'code_verification_status',
    'platform_type',
    'throughput',
  ].join(',')

  const [profile, phoneNumber, businessAccount, templates] = await Promise.all([
    graphRequest(
      `${phoneNumberId}/whatsapp_business_profile?fields=${encodeURIComponent(profileFields)}`,
    ),
    graphRequest(`${phoneNumberId}?fields=${encodeURIComponent(phoneFields)}`),
    businessAccountId
      ? graphRequest(`${businessAccountId}?fields=id,name,currency,timezone_id,message_template_namespace`)
      : Promise.resolve(null),
    businessAccountId
      ? graphRequest(`${businessAccountId}/message_templates?fields=name,status,category,language,quality_score&limit=50`)
      : Promise.resolve(null),
  ])

  return {
    channel,
    phoneNumber,
    profile,
    businessAccount,
    templates,
  }
}

async function inspectToken() {
  const [me, app, debugToken, permissions] = await Promise.all([
    graphRequest('me?fields=id,name'),
    graphRequest('app?fields=id,name'),
    graphRequest(`debug_token?input_token=${encodeURIComponent(WHATSAPP_ACCESS_TOKEN)}`),
    graphRequest('me/permissions'),
  ])

  return {
    me,
    app,
    debugToken,
    permissions,
  }
}

function getObjectValue(payload: unknown, key: string): string | null {
  if (!payload || typeof payload !== 'object') return null
  const value = (payload as JsonRecord)[key]
  return typeof value === 'string' && value ? value : null
}

function getArrayValue(payload: unknown, key: string): unknown[] {
  if (!payload || typeof payload !== 'object') return []
  const value = (payload as JsonRecord)[key]
  return Array.isArray(value) ? value : []
}

function firstNonEmpty(values: unknown[]) {
  for (const value of values) {
    if (value === null || value === undefined) continue
    const text = String(value).trim()
    if (text) return text
  }
  return ''
}

function numberValue(value: unknown) {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string') {
    const parsed = Number(value.replace(',', '.'))
    if (Number.isFinite(parsed)) return parsed
  }
  return 0
}

function buildCatalogProductPayload(product: JsonRecord) {
  const productId = String(product.id)
  const title = firstNonEmpty([
    product.whatsapp_catalog_title,
    product.website_name,
    product.name,
  ])
  const description = firstNonEmpty([
    product.whatsapp_catalog_description,
    product.website_description,
    product.description,
    title,
  ])
  const imageUrl = firstNonEmpty([
    product.website_image_url_optimized,
    product.website_image_url,
    product.image_url_optimized,
    product.image_url,
  ])
  const price = numberValue(product.whatsapp_catalog_price) ||
    numberValue(product.website_price) ||
    numberValue(product.price)
  const stock = numberValue(product.stock_quantity) || numberValue(product.inventory_qty)
  const retailerId = firstNonEmpty([product.sku, product.id])

  return {
    retailer_id: retailerId,
    name: title,
    description,
    image_url: imageUrl,
    url: `https://vinabike.cl/productos/${productId}`,
    availability: stock > 0 ? 'in stock' : 'out of stock',
    condition: 'new',
    currency: 'CLP',
    price: Math.round(price * 100),
    inventory: Math.max(0, Math.round(stock)),
    brand: firstNonEmpty([product.brand, 'Vinabike']),
    product_type: firstNonEmpty([product.category_name, 'Bicicletas y accesorios']),
    visibility: 'published',
  }
}

async function inspectCatalog(channel: JsonRecord) {
  const phoneNumberId = String(channel.phone_number_id)
  const businessAccountId = channel.business_account_id ? String(channel.business_account_id) : ''
  const [commerceSettings, phoneCatalogs, wabaCatalogs] = await Promise.all([
    graphRequest(`${phoneNumberId}/whatsapp_commerce_settings?fields=is_cart_enabled,is_catalog_visible,catalog_id`),
    graphRequest(`${phoneNumberId}/product_catalogs?fields=id,name,vertical,product_count,commerce_merchant_settings`),
    businessAccountId
      ? graphRequest(`${businessAccountId}/product_catalogs?fields=id,name,vertical,product_count`)
      : Promise.resolve(null),
  ])

  return {
    commerceSettings,
    phoneCatalogs,
    wabaCatalogs,
  }
}

async function inspectCatalogAssets(channel: JsonRecord) {
  const businessAccountId = channel.business_account_id ? String(channel.business_account_id) : ''
  const businessFields = [
    'id',
    'name',
    'owned_product_catalogs.limit(20){id,name,vertical,product_count}',
    'client_product_catalogs.limit(20){id,name,vertical,product_count}',
  ].join(',')
  const wabaFields = [
    'id',
    'name',
    'currency',
    'timezone_id',
    'owner_business_info',
    'primary_funding_id',
  ].join(',')

  const [me, businesses, waba] = await Promise.all([
    graphRequest('me?fields=id,name'),
    graphRequest(`me/businesses?fields=${encodeURIComponent(businessFields)}&limit=20`),
    businessAccountId
      ? graphRequest(`${businessAccountId}?fields=${encodeURIComponent(wabaFields)}`)
      : Promise.resolve(null),
  ])

  return {
    me,
    businesses,
    waba,
  }
}

async function inspectCatalogId(request: AdminRequest) {
  const catalogId = request.catalogId
  if (!catalogId) {
    return {
      ok: false,
      status: 400,
      payload: { error: 'catalogId is required' },
    }
  }

  const fields = [
    'id',
    'name',
    'vertical',
    'product_count',
    'commerce_merchant_settings',
  ].join(',')

  const [catalog, products] = await Promise.all([
    graphRequest(`${catalogId}?fields=${encodeURIComponent(fields)}`),
    graphRequest(`${catalogId}/products?fields=id,retailer_id,name,availability,price,currency&limit=5`),
  ])

  return {
    catalogId,
    catalog,
    products,
  }
}

async function connectCatalog(request: AdminRequest, channel: JsonRecord) {
  const catalogId = request.catalogId
  if (!catalogId) {
    return {
      ok: false,
      status: 400,
      payload: { error: 'catalogId is required' },
    }
  }

  const phoneNumberId = String(channel.phone_number_id)
  const body = new URLSearchParams()
  body.set('catalog_id', catalogId)
  body.set('is_catalog_visible', 'true')
  body.set('is_cart_enabled', 'true')

  const result = await graphRequest(`${phoneNumberId}/whatsapp_commerce_settings`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  })

  return {
    ok: result.ok,
    status: result.ok ? 200 : 502,
    payload: {
      catalogId,
      result,
      commerceSettings: await inspectCatalog(channel),
    },
  }
}

function resolveCatalogId(catalogInfo: JsonRecord) {
  const commercePayload = catalogInfo.commerceSettings &&
      typeof catalogInfo.commerceSettings === 'object'
    ? (catalogInfo.commerceSettings as JsonRecord).payload
    : null
  const commerceData = getArrayValue(commercePayload, 'data')
  for (const item of commerceData) {
    if (!item || typeof item !== 'object') continue
    const direct = getObjectValue(item, 'catalog_id')
    if (direct) return direct
  }

  const phonePayload = catalogInfo.phoneCatalogs && typeof catalogInfo.phoneCatalogs === 'object'
    ? (catalogInfo.phoneCatalogs as JsonRecord).payload
    : null
  const phoneData = getArrayValue(phonePayload, 'data')
  for (const item of phoneData) {
    if (!item || typeof item !== 'object') continue
    const id = getObjectValue(item, 'id')
    if (id) return id
  }

  const wabaPayload = catalogInfo.wabaCatalogs && typeof catalogInfo.wabaCatalogs === 'object'
    ? (catalogInfo.wabaCatalogs as JsonRecord).payload
    : null
  const wabaData = getArrayValue(wabaPayload, 'data')
  for (const item of wabaData) {
    if (!item || typeof item !== 'object') continue
    const id = getObjectValue(item, 'id')
    if (id) return id
  }

  return null
}

async function upsertCatalogProduct(request: AdminRequest, channel: JsonRecord) {
  const tenantId = request.tenantId
  const productId = request.productId
  if (!tenantId || !productId) {
    return {
      ok: false,
      status: 400,
      payload: { error: 'tenantId and productId are required' },
    }
  }

  const product = await loadProduct(tenantId, productId)
  if (!product) {
    return {
      ok: false,
      status: 404,
      payload: { error: 'Product not found' },
    }
  }

  const catalogInfo = await inspectCatalog(channel)
  const catalogId = request.catalogId ?? resolveCatalogId(catalogInfo as JsonRecord)
  if (!catalogId) {
    return {
      ok: false,
      status: 409,
      payload: {
        error: 'No connected WhatsApp product catalog found',
        catalogInfo,
      },
    }
  }

  const payload = buildCatalogProductPayload(product)
  const missing = [
    payload.name ? '' : 'name',
    payload.description ? '' : 'description',
    payload.image_url ? '' : 'image_url',
    payload.price > 0 ? '' : 'price',
  ].filter(Boolean)
  if (missing.length) {
    return {
      ok: false,
      status: 422,
      payload: {
        error: 'Product is missing required catalog fields',
        missing,
        product,
        payload,
      },
    }
  }

  const body = new URLSearchParams()
  for (const [key, value] of Object.entries(payload)) {
    body.set(key, String(value))
  }
  body.set('allow_upsert', 'true')

  const upsert = await graphRequest(`${catalogId}/products`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  })

  return {
    ok: upsert.ok,
    status: upsert.ok ? 200 : 502,
    payload: {
      catalogId,
      product,
      catalogProduct: payload,
      upsert,
      catalogInfo,
    },
  }
}

async function getMetaAppId() {
  const app = await graphRequest('app?fields=id,name')
  if (!app.ok) return { app, appId: null }
  return {
    app,
    appId: getObjectValue(app.payload, 'id'),
  }
}

async function uploadProfilePictureHandle(file: File) {
  const { app, appId } = await getMetaAppId()
  if (!appId) {
    return {
      ok: false,
      status: 500,
      payload: {
        error: 'Could not resolve Meta app ID',
        app,
      },
    }
  }

  const fileBuffer = await file.arrayBuffer()
  const fileName = file.name || 'profile-picture.jpg'
  const fileType = file.type || 'image/jpeg'
  const sessionUrl = new URL(`https://graph.facebook.com/${WHATSAPP_API_VERSION}/${appId}/uploads`)
  sessionUrl.searchParams.set('file_name', fileName)
  sessionUrl.searchParams.set('file_length', String(fileBuffer.byteLength))
  sessionUrl.searchParams.set('file_type', fileType)
  sessionUrl.searchParams.set('access_token', WHATSAPP_ACCESS_TOKEN)

  const session = await graphJsonRequest(sessionUrl.toString(), { method: 'POST' })
  if (!session.ok) return session

  const uploadSessionId = getObjectValue(session.payload, 'id')
  if (!uploadSessionId) {
    return {
      ok: false,
      status: 502,
      payload: {
        error: 'Meta did not return an upload session ID',
        session: session.payload,
      },
    }
  }

  const upload = await graphJsonRequest(
    `https://graph.facebook.com/${WHATSAPP_API_VERSION}/${uploadSessionId}`,
    {
      method: 'POST',
      headers: {
        Authorization: `OAuth ${WHATSAPP_ACCESS_TOKEN}`,
        file_offset: '0',
      },
      body: fileBuffer,
    },
  )
  if (!upload.ok) return upload

  const handle = getObjectValue(upload.payload, 'h')
  if (!handle) {
    return {
      ok: false,
      status: 502,
      payload: {
        error: 'Meta did not return a file handle',
        upload: upload.payload,
      },
    }
  }

  return {
    ok: true,
    status: 200,
    payload: {
      app,
      session: session.payload,
      handle,
    },
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !WHATSAPP_ACCESS_TOKEN) {
    return jsonResponse({ error: 'Missing required environment variables' }, 500)
  }

  if (!isAuthorized(req)) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  let request: AdminRequest
  let profilePictureFile: File | null = null
  try {
    const contentType = req.headers.get('Content-Type') ?? ''
    if (contentType.toLowerCase().includes('multipart/form-data')) {
      const form = await req.formData()
      const formFile = form.get('file')
      if (formFile instanceof File) profilePictureFile = formFile
      request = {
        action: (form.get('action')?.toString() ?? undefined) as AdminRequest['action'],
        tenantId: form.get('tenantId')?.toString() ?? undefined,
        phoneNumberId: form.get('phoneNumberId')?.toString() ?? undefined,
        productId: form.get('productId')?.toString() ?? undefined,
        catalogId: form.get('catalogId')?.toString() ?? undefined,
      }
    } else {
      request = await req.json()
    }
  } catch (_) {
    return jsonResponse({ error: 'Invalid request body' }, 400)
  }

  const channel = await resolveChannel(request)
  if (!channel) {
    return jsonResponse({ error: 'No active WhatsApp channel found' }, 404)
  }

  const action = request.action ?? 'inspect'
  if (action === 'inspect') {
    return jsonResponse(await inspectProfile(channel))
  }

  if (action === 'inspect_token') {
    return jsonResponse(await inspectToken())
  }

  if (action === 'inspect_catalog') {
    return jsonResponse(await inspectCatalog(channel))
  }

  if (action === 'inspect_catalog_id') {
    return jsonResponse(await inspectCatalogId(request))
  }

  if (action === 'inspect_catalog_assets') {
    return jsonResponse(await inspectCatalogAssets(channel))
  }

  if (action === 'graph_get') {
    if (!request.path) {
      return jsonResponse({ error: 'path is required' }, 400)
    }
    return jsonResponse(await graphRequest(request.path))
  }

  if (action === 'graph_post') {
    if (!request.path) {
      return jsonResponse({ error: 'path is required' }, 400)
    }
    const result = await graphRequest(request.path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request.body ?? {}),
    })
    return jsonResponse(result)
  }

  if (action === 'connect_catalog') {
    const result = await connectCatalog(request, channel)
    return jsonResponse(result.payload, result.status)
  }

  if (action === 'upsert_catalog_product') {
    const result = await upsertCatalogProduct(request, channel)
    return jsonResponse(result.payload, result.status)
  }

  if (action === 'upload_profile_picture') {
    if (!profilePictureFile) {
      return jsonResponse({ error: 'Multipart field "file" is required' }, 400)
    }

    const upload = await uploadProfilePictureHandle(profilePictureFile)
    if (!upload.ok) return jsonResponse({ upload }, 502)

    const handle = getObjectValue(upload.payload, 'handle')
    if (!handle) {
      return jsonResponse({ error: 'Upload succeeded but handle was missing', upload }, 502)
    }

    const phoneNumberId = String(channel.phone_number_id)
    const update = await graphRequest(
      `${phoneNumberId}/whatsapp_business_profile`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          profile_picture_handle: handle,
        }),
      },
    )

    return jsonResponse({
      channel,
      upload: {
        ok: upload.ok,
        status: upload.status,
      },
      update,
      after: update.ok ? await inspectProfile(channel) : null,
    }, update.ok ? 200 : 502)
  }

  if (action === 'update_profile') {
    const profile = sanitizedProfile(request.profile ?? {})
    if (!Object.keys(profile).length) {
      return jsonResponse({ error: 'No supported profile fields provided' }, 400)
    }

    const phoneNumberId = String(channel.phone_number_id)
    const update = await graphRequest(
      `${phoneNumberId}/whatsapp_business_profile`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          ...profile,
        }),
      },
    )

    return jsonResponse({
      channel,
      update,
      after: update.ok ? await inspectProfile(channel) : null,
    }, update.ok ? 200 : 502)
  }

  return jsonResponse({ error: 'Unsupported action' }, 400)
})
