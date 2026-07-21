import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import {
  mergeCanonicalAvailableQuantities,
  resolveAvailableProductQuantity,
} from '../_shared/product_availability.ts'
import { publicProductUrl } from '../_shared/product_url.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-admin-token, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const WHATSAPP_ACCESS_TOKEN = Deno.env.get('WHATSAPP_ACCESS_TOKEN') ?? ''
const WHATSAPP_API_VERSION = Deno.env.get('WHATSAPP_API_VERSION') ?? 'v23.0'
const META_ACCESS_TOKEN = Deno.env.get('META_ACCESS_TOKEN') ?? WHATSAPP_ACCESS_TOKEN
const META_API_VERSION = Deno.env.get('META_API_VERSION') ?? WHATSAPP_API_VERSION
const PRIMARY_META_CATALOG_ID = Deno.env.get('META_CATALOG_ID') ??
  Deno.env.get('WHATSAPP_CATALOG_ID') ?? ''
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
    | 'audit_catalog_products'
    | 'publish_business_hours'
    | 'update_profile'
    | 'upload_profile_picture'
  tenantId?: string
  phoneNumberId?: string
  productId?: string
  catalogId?: string
  path?: string
  body?: JsonRecord
  profile?: JsonRecord
  businessHours?: JsonRecord
  hoursLabel?: string
  facebookPageId?: string
  repair?: boolean
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

async function isAuthorizedForRequest(req: Request, request: AdminRequest) {
  if (isAuthorized(req)) return true
  if (request.action !== 'publish_business_hours') return false

  const authHeader = req.headers.get('Authorization') ?? ''
  const bearerToken = authHeader.replace(/^Bearer\s+/i, '').trim()
  if (!bearerToken) return false

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const { data: userData, error: userError } = await adminClient.auth.getUser(bearerToken)
  if (userError || !userData.user) return false

  const { data: profile, error: profileError } = await adminClient
    .from('user_profiles')
    .select('tenant_id')
    .eq('user_id', userData.user.id)
    .maybeSingle()

  if (profileError || !profile?.tenant_id) return false
  const tenantId = String(profile.tenant_id)
  if (request.tenantId && request.tenantId !== tenantId) return false
  request.tenantId = tenantId
  return true
}

async function graphRequest(
  path: string,
  options: RequestInit = {},
) {
  const response = await fetch(
    `https://graph.facebook.com/${META_API_VERSION}/${path}`,
    {
      ...options,
      headers: {
        Authorization: `Bearer ${META_ACCESS_TOKEN}`,
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

async function hydrateProductAvailability(
  tenantId: string,
  products: JsonRecord[],
) {
  if (products.length === 0) return products
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const availabilityRows: Array<Record<string, unknown>> = []
  for (let index = 0; index < products.length; index += 500) {
    const batch = products.slice(index, index + 500)
    const { data, error } = await adminClient.rpc(
      'get_product_available_quantities',
      {
        p_tenant_id: tenantId,
        p_product_ids: batch.map((product) => String(product.id)),
      },
    )
    if (error) throw error
    availabilityRows.push(
      ...((data || []) as unknown as Array<Record<string, unknown>>),
    )
  }
  return mergeCanonicalAvailableQuantities(
    products,
    availabilityRows,
  )
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
      'track_stock',
      'is_set',
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
  if (!data) return null
  return (await hydrateProductAvailability(
    tenantId,
    [data as unknown as JsonRecord],
  ))[0]
}

async function loadEnabledCatalogProducts(tenantId: string) {
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
      'track_stock',
      'is_set',
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
    .eq('is_whatsapp_catalog', true)
    .eq('is_active', true)
    .eq('is_published', true)
    .order('name')

  if (error) throw error
  return await hydrateProductAvailability(
    tenantId,
    (data ?? []) as unknown as JsonRecord[],
  )
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
    graphRequest(`debug_token?input_token=${encodeURIComponent(META_ACCESS_TOKEN)}`),
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

function stringValue(value: unknown) {
  return typeof value === 'string' ? value.trim() : ''
}

async function loadWebsiteSettings(tenantId: string) {
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const { data, error } = await adminClient
    .from('website_settings')
    .select('key,value')
    .eq('tenant_id', tenantId)

  if (error) throw error

  const settings: Record<string, string> = {}
  for (const row of (data ?? []) as JsonRecord[]) {
    const key = stringValue(row.key)
    if (!key) continue
    settings[key] = row.value === null || row.value === undefined
      ? ''
      : String(row.value)
  }
  return settings
}

function timeLabel(rawTime: unknown) {
  if (typeof rawTime === 'string') {
    const digits = rawTime.replace(':', '').trim().padStart(4, '0')
    if (digits.length >= 4) return `${digits.slice(0, 2)}:${digits.slice(2, 4)}`
  }
  if (rawTime && typeof rawTime === 'object') {
    const time = rawTime as JsonRecord
    const hours = Number(time.hours ?? 0)
    const minutes = Number(time.minutes ?? 0)
    if (Number.isFinite(hours) && Number.isFinite(minutes)) {
      return `${String(Math.max(0, Math.min(23, Math.round(hours)))).padStart(2, '0')}:${
        String(Math.max(0, Math.min(59, Math.round(minutes)))).padStart(2, '0')
      }`
    }
  }
  return ''
}

function dayLabel(rawDay: unknown) {
  const day = stringValue(rawDay).toUpperCase()
  const labels: Record<string, string> = {
    MONDAY: 'Lunes',
    TUESDAY: 'Martes',
    WEDNESDAY: 'Miercoles',
    THURSDAY: 'Jueves',
    FRIDAY: 'Viernes',
    SATURDAY: 'Sabado',
    SUNDAY: 'Domingo',
  }
  return labels[day] ?? day
}

function businessHoursPeriods(hours: JsonRecord = {}) {
  const root = hours.opening_hours && typeof hours.opening_hours === 'object'
    ? hours.opening_hours as JsonRecord
    : hours
  const periods = Array.isArray(root.periods) ? root.periods : []
  return periods.filter((period): period is JsonRecord =>
    Boolean(period && typeof period === 'object')
  )
}

function buildHoursLabel(hours: JsonRecord = {}, fallback = '') {
  const fallbackText = fallback.trim()
  if (fallbackText) return fallbackText

  const rows: string[] = []
  for (const period of businessHoursPeriods(hours)) {
    const openDay = dayLabel(period.openDay)
    const openTime = timeLabel(period.openTime)
    const closeTime = timeLabel(period.closeTime)
    if (!openDay || !openTime || !closeTime) continue
    rows.push(`${openDay} ${openTime}-${closeTime}`)
  }
  return rows.join('; ')
}

function withHoursBlock(original: string, label: string) {
  const marker = 'Horario de atencion:'
  const cleaned = original.replace(/Horario de atenci[oó]n:[\s\S]*$/i, '').trim()
  const next = `${cleaned ? `${cleaned}\n\n` : ''}${marker}\n${label}`.trim()
  return next.slice(0, 512)
}

function facebookHoursPayload(hours: JsonRecord = {}) {
  const dayMap: Record<string, string> = {
    MONDAY: 'mon',
    TUESDAY: 'tue',
    WEDNESDAY: 'wed',
    THURSDAY: 'thu',
    FRIDAY: 'fri',
    SATURDAY: 'sat',
    SUNDAY: 'sun',
  }
  const payload: Record<string, string> = {}
  const counts: Record<string, number> = {}

  for (const period of businessHoursPeriods(hours)) {
    const openDay = stringValue(period.openDay).toUpperCase()
    const key = dayMap[openDay]
    if (!key) continue
    const index = (counts[key] ?? 0) + 1
    if (index > 2) continue
    counts[key] = index
    const openTime = timeLabel(period.openTime)
    const closeTime = timeLabel(period.closeTime)
    if (!openTime || !closeTime) continue
    payload[`${key}_${index}_open`] = openTime
    payload[`${key}_${index}_close`] = closeTime
  }

  return payload
}

async function publishBusinessHours(request: AdminRequest, channel: JsonRecord) {
  const tenantId = String(channel.tenant_id)
  const settings = await loadWebsiteSettings(tenantId)
  const hours = request.businessHours ?? parseJsonSetting(settings.business_hours_json)
  const label = buildHoursLabel(hours, request.hoursLabel ?? '')
  if (!label) {
    return {
      ok: false,
      status: 400,
      payload: { error: 'businessHours or hoursLabel is required' },
    }
  }

  const results: JsonRecord[] = []
  const phoneNumberId = String(channel.phone_number_id)
  const before = await inspectProfile(channel)
  const beforeProfile = before.profile as JsonRecord
  const profilePayload = beforeProfile.payload && typeof beforeProfile.payload === 'object'
    ? beforeProfile.payload as JsonRecord
    : {}
  const profileData = Array.isArray(profilePayload.data)
    ? profilePayload.data as JsonRecord[]
    : []
  const currentProfile = profileData[0] && typeof profileData[0] === 'object'
    ? profileData[0]
    : {}
  const description = withHoursBlock(
    firstNonEmpty([
      currentProfile.description,
      settings.whatsapp_business_description,
      settings.business_name,
      settings.store_name,
    ]),
    label,
  )
  const profile: JsonRecord = {
    description,
  }
  const address = firstNonEmpty([
    settings.contact_address,
    settings.seo_address_street,
    settings.business_address,
  ])
  if (address) profile.address = address
  const email = firstNonEmpty([settings.contact_email, settings.seo_email])
  if (email) profile.email = email
  const website = firstNonEmpty([
    settings.website_url,
    settings.public_website_url,
    settings.store_url,
  ])
  if (website) profile.websites = [website]

  const whatsapp = await graphRequest(
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
  results.push({
    destination: 'whatsapp',
    ok: whatsapp.ok,
    status: whatsapp.status,
    payload: whatsapp.payload,
  })

  const facebookPageId = firstNonEmpty([
    request.facebookPageId,
    settings.facebook_page_id,
    settings.meta_facebook_page_id,
    settings.business_facebook_page_id,
  ])
  if (facebookPageId) {
    const body = {
      hours: facebookHoursPayload(hours),
    }
    const facebook = await graphRequest(
      facebookPageId,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      },
    )
    results.push({
      destination: 'facebook',
      ok: facebook.ok,
      status: facebook.status,
      payload: facebook.payload,
    })
  } else {
    results.push({
      destination: 'facebook',
      ok: false,
      skipped: true,
      reason: 'facebook_page_id_missing',
    })
  }

  return {
    ok: results.some((result) => result.ok === true),
    status: results.some((result) => result.ok === true) ? 200 : 502,
    payload: {
      channel,
      hoursLabel: label,
      results,
      after: whatsapp.ok ? await inspectProfile(channel) : null,
    },
  }
}

function parseJsonSetting(raw: string) {
  try {
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? parsed as JsonRecord : {}
  } catch (_) {
    return {}
  }
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
  const title = firstNonEmpty([
    product.whatsapp_catalog_title,
    product.website_name,
    product.name,
  ])
  const description = firstNonEmpty([
    product.whatsapp_catalog_description,
    product.website_description,
    product.description,
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
  const stock = resolveAvailableProductQuantity(product)
  const retailerId = firstNonEmpty([product.sku, product.id])

  return {
    retailer_id: retailerId,
    name: title,
    description,
    image_url: imageUrl,
    url: publicProductUrl('https://vinabike.cl', product),
    availability: stock > 0 ? 'in stock' : 'out of stock',
    condition: 'new',
    currency: 'CLP',
    price: Math.round(price * 100),
    quantity_to_sell_on_facebook: Math.max(0, Math.round(stock)),
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
    graphRequest(`${catalogId}/products?fields=id,retailer_id,name,url,availability,price,currency,quantity_to_sell_on_facebook,capability_to_review_status&limit=100`),
  ])

  return {
    catalogId,
    catalog,
    products,
  }
}

async function fetchAllCatalogProducts(catalogId: string) {
  const products: JsonRecord[] = []
  let after = ''

  for (let page = 0; page < 100; page += 1) {
    const cursor = after ? `&after=${encodeURIComponent(after)}` : ''
    const result = await graphRequest(
      `${catalogId}/products?fields=id,retailer_id,name,url,availability,price,currency,quantity_to_sell_on_facebook,capability_to_review_status&limit=100${cursor}`,
    )
    if (!result.ok) {
      throw new Error(
        getObjectValue(
          (result.payload as JsonRecord | null)?.error,
          'message',
        ) || 'Meta could not inspect all catalog products',
      )
    }
    const payload = result.payload as JsonRecord
    products.push(
      ...getArrayValue(payload, 'data')
        .filter((item): item is JsonRecord => Boolean(item && typeof item === 'object')),
    )
    const paging = payload.paging as JsonRecord | undefined
    const cursors = paging?.cursors as JsonRecord | undefined
    after = getObjectValue(cursors, 'after') ?? ''
    if (!getObjectValue(paging, 'next') || !after) break
  }

  return products
}

function catalogPayloadMissing(payload: ReturnType<typeof buildCatalogProductPayload>) {
  return [
    payload.name.length >= 10 ? '' : 'title',
    payload.description.length >= 20 ? '' : 'description',
    payload.image_url ? '' : 'image',
    payload.price > 0 ? '' : 'price',
  ].filter(Boolean) as string[]
}

async function upsertCatalogPayload(
  catalogId: string,
  payload: ReturnType<typeof buildCatalogProductPayload>,
) {
  const body = new URLSearchParams()
  for (const [key, value] of Object.entries(payload)) {
    body.set(key, String(value))
  }
  body.set('allow_upsert', 'true')
  return graphRequest(`${catalogId}/products`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
}

async function auditCatalogProducts(request: AdminRequest, channel: JsonRecord) {
  const tenantId = request.tenantId || String(channel.tenant_id || '')
  if (!tenantId) {
    return {
      ok: false,
      status: 400,
      payload: { error: 'tenantId is required' },
    }
  }

  const catalogInfo = await inspectCatalog(channel)
  const catalogId = request.catalogId ?? resolveCatalogId(catalogInfo as JsonRecord)
  if (!catalogId) {
    return {
      ok: false,
      status: 409,
      payload: { error: 'No connected WhatsApp product catalog found' },
    }
  }

  const localProducts = await loadEnabledCatalogProducts(tenantId)
  let metaProducts = await fetchAllCatalogProducts(catalogId)
  let metaByRetailerId = new Map(
    metaProducts.map((product) => [firstNonEmpty([product.retailer_id]), product]),
  )
  const repairResults: JsonRecord[] = []

  if (request.repair === true) {
    for (const product of localProducts) {
      const expected = buildCatalogProductPayload(product)
      const observed = metaByRetailerId.get(expected.retailer_id)
      const missing = catalogPayloadMissing(expected)
      const observedUrl = firstNonEmpty([observed?.url])
      if (missing.length > 0 || observedUrl === expected.url) continue

      const repaired = await upsertCatalogPayload(catalogId, expected)
      repairResults.push({
        productId: product.id,
        retailerId: expected.retailer_id,
        expectedUrl: expected.url,
        ok: repaired.ok,
        status: repaired.status,
        result: repaired.payload,
      })
    }
    metaProducts = await fetchAllCatalogProducts(catalogId)
    metaByRetailerId = new Map(
      metaProducts.map((product) => [firstNonEmpty([product.retailer_id]), product]),
    )
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const checkedAt = new Date().toISOString()
  const products = []
  for (const product of localProducts) {
    const expected = buildCatalogProductPayload(product)
    const observed = metaByRetailerId.get(expected.retailer_id)
    const observedUrl = firstNonEmpty([observed?.url])
    const missing = catalogPayloadMissing(expected)
    const urlMatches = observedUrl === expected.url
    const status = missing.length > 0
      ? 'invalid_local_product'
      : !observed
      ? 'missing_from_meta'
      : urlMatches
      ? 'ok'
      : 'url_mismatch'

    await adminClient
      .from('products')
      .update({
        whatsapp_catalog_synced_url: observedUrl || null,
        whatsapp_catalog_url_matches: urlMatches,
        whatsapp_catalog_verified_at: checkedAt,
      })
      .eq('id', product.id)

    products.push({
      productId: product.id,
      retailerId: expected.retailer_id,
      name: expected.name,
      status,
      missing,
      expectedUrl: expected.url,
      observedUrl: observedUrl || null,
      urlMatches,
    })
  }

  const localRetailerIds = new Set(
    localProducts.map((product) => firstNonEmpty([product.sku, product.id])),
  )
  const orphanMetaProducts = metaProducts
    .filter((product) => !localRetailerIds.has(firstNonEmpty([product.retailer_id])))
    .map((product) => ({
      id: product.id,
      retailerId: product.retailer_id,
      name: product.name,
      url: product.url,
    }))

  return {
    ok: true,
    status: 200,
    payload: {
      catalogId,
      checkedAt,
      repaired: request.repair === true,
      repairResults,
      summary: {
        localEnabled: localProducts.length,
        metaProducts: metaProducts.length,
        matchingUrls: products.filter((product) => product.urlMatches).length,
        problems: products.filter((product) => product.status !== 'ok').length,
        orphanMetaProducts: orphanMetaProducts.length,
      },
      products,
      orphanMetaProducts,
    },
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
  if (PRIMARY_META_CATALOG_ID) return PRIMARY_META_CATALOG_ID

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
    payload.name.length >= 10 ? '' : 'title',
    payload.description.length >= 20 ? '' : 'description',
    payload.image_url ? '' : 'image',
    payload.price > 0 ? '' : 'price',
  ].filter(Boolean) as string[]
  if (missing.length) {
    return {
      ok: false,
      status: 422,
      payload: {
        error: 'Faltan datos obligatorios para publicar en WhatsApp',
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
  const sessionUrl = new URL(`https://graph.facebook.com/${META_API_VERSION}/${appId}/uploads`)
  sessionUrl.searchParams.set('file_name', fileName)
  sessionUrl.searchParams.set('file_length', String(fileBuffer.byteLength))
  sessionUrl.searchParams.set('file_type', fileType)
  sessionUrl.searchParams.set('access_token', META_ACCESS_TOKEN)

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
    `https://graph.facebook.com/${META_API_VERSION}/${uploadSessionId}`,
    {
      method: 'POST',
      headers: {
        Authorization: `OAuth ${META_ACCESS_TOKEN}`,
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

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !META_ACCESS_TOKEN) {
    return jsonResponse({ error: 'Missing required environment variables' }, 500)
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

  if (!(await isAuthorizedForRequest(req, request))) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
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

  if (action === 'audit_catalog_products') {
    const result = await auditCatalogProducts(request, channel)
    return jsonResponse(result.payload, result.status)
  }

  if (action === 'publish_business_hours') {
    const result = await publishBusinessHours(request, channel)
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
