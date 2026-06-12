import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const WHATSAPP_ACCESS_TOKEN = Deno.env.get('WHATSAPP_ACCESS_TOKEN') ?? ''
const WHATSAPP_API_VERSION = Deno.env.get('WHATSAPP_API_VERSION') ?? 'v23.0'

type JsonRecord = Record<string, unknown>

// Honest lifecycle states. Meta accepting an upsert (returning a product id and
// visibility=published) does NOT mean the product is visible to customers in
// WhatsApp. Customer visibility is gated by the asynchronous per-product review
// field capability_to_review_status[WHATSAPP] == APPROVED. Until Meta approves,
// the product stays under_review and remains hidden from the catalog customers
// see in chat. See refreshProductReview() / fetchWhatsappReviewValue().
type CatalogSyncStatus =
  | 'pending'
  | 'syncing'
  | 'synced'
  | 'under_review'
  | 'customer_visible'
  | 'rejected'
  | 'removed'
  | 'failed'

interface SyncRequest {
  productId?: string
  // 'sync' (default) publishes/removes. 'refresh' only re-reads Meta's review
  // state for an already-uploaded product without re-uploading it.
  mode?: string
}

function createAdminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
}

type AdminClient = ReturnType<typeof createAdminClient>

async function updateSyncStatus(
  adminClient: AdminClient,
  productId: string,
  status: CatalogSyncStatus,
  options: {
    error?: string | null
    metaProductId?: string | null
  } = {},
) {
  const values: JsonRecord = {
    whatsapp_catalog_sync_status: status,
    whatsapp_catalog_sync_error: options.error ?? null,
  }
  // Any state where Meta actually responded about the product is a successful
  // round-trip worth timestamping, even if the product is not customer-visible
  // yet (under_review) or was rejected.
  const reachedMeta =
    status === 'synced' ||
    status === 'removed' ||
    status === 'under_review' ||
    status === 'customer_visible' ||
    status === 'rejected'
  if (reachedMeta) {
    values.whatsapp_catalog_synced_at = new Date().toISOString()
  }
  if (options.metaProductId !== undefined) {
    values.whatsapp_catalog_meta_product_id = options.metaProductId
  }

  const { error } = await adminClient
    .from('products')
    .update(values)
    .eq('id', productId)

  if (error) {
    console.error('Could not persist WhatsApp catalog sync status', error)
  }
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

function stringValue(value: unknown) {
  if (typeof value !== 'string') return ''
  return value.trim()
}

function firstNonEmpty(values: unknown[]) {
  for (const value of values) {
    const text = stringValue(value)
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

function arrayValue(value: unknown) {
  return Array.isArray(value) ? value : []
}

function recordValue(value: unknown): JsonRecord {
  return value && typeof value === 'object' ? value as JsonRecord : {}
}

function decodeBase64Url(value: string) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '=',
  )
  return atob(padded)
}

function resolveJwtPayload(authHeader: string) {
  const [scheme, token] = authHeader.split(/\s+/)
  if (scheme?.toLowerCase() !== 'bearer' || !token) return null

  const payloadPart = token.split('.')[1]
  if (!payloadPart) return null

  try {
    return JSON.parse(decodeBase64Url(payloadPart)) as JsonRecord
  } catch (_) {
    return null
  }
}

async function graphRequest(path: string, options: RequestInit = {}) {
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
    // Keep non-JSON Meta responses available for diagnostics.
  }

  return {
    ok: response.ok,
    status: response.status,
    payload,
  }
}

async function resolveCallerTenant(
  adminClient: AdminClient,
  authHeader: string,
  productTenantId: string,
) {
  const bearer = authHeader.replace(/^Bearer\s+/i, '')
  if (bearer === SUPABASE_SERVICE_ROLE_KEY) return productTenantId

  // The Edge Function gateway verifies the JWT before this code runs.
  const jwtPayload = resolveJwtPayload(authHeader)
  if (stringValue(jwtPayload?.role) === 'service_role') return productTenantId

  const userId = stringValue(jwtPayload?.sub)
  if (!userId) return null

  const { data: profile, error } = await adminClient
    .from('user_profiles')
    .select('tenant_id, is_active')
    .eq('user_id', userId)
    .maybeSingle()

  const profileRecord = profile as unknown as JsonRecord | null
  if (error || !profileRecord || profileRecord.is_active === false) return null
  return stringValue(profileRecord.tenant_id) || null
}

async function resolveCatalogId(
  adminClient: AdminClient,
  tenantId: string,
) {
  const { data: channel, error } = await adminClient
    .from('whatsapp_channels')
    .select('business_account_id')
    .eq('tenant_id', tenantId)
    .eq('is_active', true)
    .limit(1)
    .maybeSingle()

  if (error) throw error
  const channelRecord = channel as unknown as JsonRecord | null
  const businessAccountId = stringValue(channelRecord?.business_account_id)
  if (!businessAccountId) {
    throw new Error('No active WhatsApp business account is configured for this tenant')
  }

  const result = await graphRequest(
    `${businessAccountId}/product_catalogs?fields=id,name,vertical,product_count&limit=20`,
  )
  if (!result.ok) {
    throw new Error(metaErrorMessage(result.payload, 'Meta could not load the connected WhatsApp catalog'))
  }

  const catalogs = arrayValue(recordValue(result.payload).data)
    .map(recordValue)
    .filter((catalog) => stringValue(catalog.id))

  if (catalogs.length === 0) {
    throw new Error('No product catalog is connected to the active WhatsApp business account')
  }
  if (catalogs.length > 1) {
    throw new Error('Multiple WhatsApp product catalogs are connected; catalog selection is ambiguous')
  }

  return stringValue(catalogs[0].id)
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
  const stock = product.stock_quantity === null || product.stock_quantity === undefined
    ? numberValue(product.inventory_qty)
    : numberValue(product.stock_quantity)
  const retailerId = firstNonEmpty([product.sku, product.id])

  return {
    retailer_id: retailerId,
    name: title,
    description,
    image_url: imageUrl,
    url: `https://vinabike.cl/productos/${String(product.id)}`,
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

function metaErrorMessage(payload: unknown, fallback: string) {
  const error = recordValue(recordValue(payload).error)
  return stringValue(error.message) || fallback
}

// Maps Meta's WhatsApp review value to our honest lifecycle status.
// APPROVED is the only value that means the product is visible to customers.
function mapWhatsappReviewStatus(reviewValue: string): CatalogSyncStatus {
  switch (reviewValue.toUpperCase()) {
    case 'APPROVED':
      return 'customer_visible'
    case 'REJECTED':
      return 'rejected'
    default:
      // NO_REVIEW, PENDING, OUTDATED, or unknown -> still awaiting Meta review.
      return 'under_review'
  }
}

// capability_to_review_status is an array of { key, value } entries. We only
// care about the WHATSAPP capability for customer visibility in chat.
function extractWhatsappReviewValue(payload: unknown): string {
  const capabilities = arrayValue(
    recordValue(payload).capability_to_review_status,
  ).map(recordValue)
  for (const capability of capabilities) {
    if (stringValue(capability.key) === 'WHATSAPP') {
      return stringValue(capability.value)
    }
  }
  return ''
}

async function fetchWhatsappReviewValue(metaProductId: string): Promise<string> {
  if (!metaProductId) return ''
  const result = await graphRequest(
    `${metaProductId}?fields=capability_to_review_status`,
  )
  if (!result.ok) return ''
  return extractWhatsappReviewValue(result.payload)
}

async function upsertProduct(
  adminClient: AdminClient,
  catalogId: string,
  product: JsonRecord,
) {
  const payload = buildCatalogProductPayload(product)
  const missing = [
    payload.name.length >= 10 ? '' : 'title',
    payload.description.length >= 20 ? '' : 'description',
    payload.image_url ? '' : 'image',
    payload.price > 0 ? '' : 'price',
  ].filter(Boolean) as string[]

  if (missing.length > 0) {
    await updateSyncStatus(
      adminClient,
      stringValue(product.id),
      'failed',
      { error: `Faltan datos obligatorios: ${missing.join(', ')}` },
    )
    return jsonResponse({
      error: 'Faltan datos obligatorios para publicar en WhatsApp',
      missing,
    }, 422)
  }

  const body = new URLSearchParams()
  for (const [key, value] of Object.entries(payload)) {
    body.set(key, String(value))
  }
  body.set('allow_upsert', 'true')

  const result = await graphRequest(`${catalogId}/products`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })

  if (!result.ok) {
    const error = metaErrorMessage(result.payload, 'Meta rejected the WhatsApp catalog product')
    await updateSyncStatus(
      adminClient,
      stringValue(product.id),
      'failed',
      { error },
    )
    return jsonResponse({
      error,
      details: result.payload,
    }, 502)
  }

  const metaProductId = stringValue(recordValue(result.payload).id) || null
  // Meta accepted the upsert, but acceptance is not customer visibility. Read
  // back the WhatsApp review capability so the ERP reports the real state
  // instead of falsely claiming the product is live for customers.
  const reviewValue = await fetchWhatsappReviewValue(metaProductId ?? '')
  const syncStatus = metaProductId
    ? mapWhatsappReviewStatus(reviewValue)
    : 'under_review'
  await updateSyncStatus(
    adminClient,
    stringValue(product.id),
    syncStatus,
    { metaProductId },
  )
  return jsonResponse({
    ok: true,
    action: 'upserted',
    catalogId,
    productId: product.id,
    retailerId: payload.retailer_id,
    metaProductId,
    syncStatus,
    whatsappReview: reviewValue || 'NO_REVIEW',
  })
}

async function findCatalogProduct(
  catalogId: string,
  retailerId: string,
  fields = 'id,retailer_id',
) {
  let after = ''

  for (let page = 0; page < 100; page += 1) {
    const cursor = after ? `&after=${encodeURIComponent(after)}` : ''
    const result = await graphRequest(
      `${catalogId}/products?fields=${fields}&limit=100${cursor}`,
    )
    if (!result.ok) {
      throw new Error(metaErrorMessage(result.payload, 'Meta could not inspect catalog products'))
    }

    const payload = recordValue(result.payload)
    for (const item of arrayValue(payload.data).map(recordValue)) {
      if (stringValue(item.retailer_id) === retailerId) return item
    }

    const paging = recordValue(payload.paging)
    const cursors = recordValue(paging.cursors)
    after = stringValue(cursors.after)
    if (!stringValue(paging.next) || !after) break
  }

  return null
}

async function removeProduct(
  adminClient: AdminClient,
  catalogId: string,
  product: JsonRecord,
) {
  const retailerId = firstNonEmpty([product.sku, product.id])
  const catalogProduct = await findCatalogProduct(catalogId, retailerId)
  if (!catalogProduct) {
    await updateSyncStatus(
      adminClient,
      stringValue(product.id),
      'removed',
      { metaProductId: null },
    )
    return jsonResponse({
      ok: true,
      action: 'already_absent',
      catalogId,
      productId: product.id,
      retailerId,
    })
  }

  const metaProductId = stringValue(catalogProduct.id)
  const result = await graphRequest(metaProductId, { method: 'DELETE' })
  if (!result.ok) {
    const error = metaErrorMessage(result.payload, 'Meta rejected removing the WhatsApp catalog product')
    await updateSyncStatus(
      adminClient,
      stringValue(product.id),
      'failed',
      { error },
    )
    return jsonResponse({
      error,
      details: result.payload,
    }, 502)
  }

  await updateSyncStatus(
    adminClient,
    stringValue(product.id),
    'removed',
    { metaProductId: null },
  )
  return jsonResponse({
    ok: true,
    action: 'removed',
    catalogId,
    productId: product.id,
    retailerId,
    metaProductId,
  })
}

// Re-reads Meta's current WhatsApp review state for an already-uploaded product
// WITHOUT re-uploading it. Powers the ERP "re-verificar estado" action and any
// scheduled polling so the stored status converges to real customer visibility.
async function refreshProductReview(
  adminClient: AdminClient,
  catalogId: string,
  product: JsonRecord,
) {
  const retailerId = firstNonEmpty([product.sku, product.id])
  const shouldPublish =
    product.is_whatsapp_catalog === true &&
    product.is_active !== false &&
    product.is_published !== false

  const catalogProduct = await findCatalogProduct(
    catalogId,
    retailerId,
    'id,retailer_id,capability_to_review_status',
  )

  if (!catalogProduct) {
    if (shouldPublish) {
      await updateSyncStatus(adminClient, stringValue(product.id), 'pending', {
        error: 'Aún no está en el catálogo de WhatsApp. Vuelve a sincronizar.',
      })
      return jsonResponse({
        ok: true,
        action: 'absent',
        catalogId,
        productId: product.id,
        retailerId,
        syncStatus: 'pending',
      })
    }
    await updateSyncStatus(adminClient, stringValue(product.id), 'removed', {
      metaProductId: null,
    })
    return jsonResponse({
      ok: true,
      action: 'removed',
      catalogId,
      productId: product.id,
      retailerId,
      syncStatus: 'removed',
    })
  }

  const metaProductId = stringValue(catalogProduct.id) || null
  const reviewValue = extractWhatsappReviewValue(catalogProduct)
  const syncStatus = mapWhatsappReviewStatus(reviewValue)
  await updateSyncStatus(adminClient, stringValue(product.id), syncStatus, {
    metaProductId,
  })
  return jsonResponse({
    ok: true,
    action: 'refreshed',
    catalogId,
    productId: product.id,
    retailerId,
    metaProductId,
    syncStatus,
    whatsappReview: reviewValue || 'NO_REVIEW',
  })
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !WHATSAPP_ACCESS_TOKEN) {
    return jsonResponse({ error: 'Missing required environment variables' }, 500)
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Missing Authorization header' }, 401)
  }

  let request: SyncRequest
  try {
    request = await req.json()
  } catch (_) {
    return jsonResponse({ error: 'Invalid JSON body' }, 400)
  }

  const productId = stringValue(request.productId)
  if (!productId) {
    return jsonResponse({ error: 'productId is required' }, 400)
  }
  const mode = stringValue(request.mode) === 'refresh' ? 'refresh' : 'sync'

  const adminClient = createAdminClient()
  let canPersistFailure = false
  try {
    const { data: product, error } = await adminClient
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
      .eq('id', productId)
      .maybeSingle()

    if (error) throw error
    if (!product) return jsonResponse({ error: 'Product not found' }, 404)

    const productRecord = product as unknown as JsonRecord
    const productTenantId = stringValue(productRecord.tenant_id)
    const callerTenantId = await resolveCallerTenant(
      adminClient,
      authHeader,
      productTenantId,
    )
    if (!callerTenantId || callerTenantId !== productTenantId) {
      return jsonResponse({ error: 'Unauthorized for this product tenant' }, 403)
    }

    canPersistFailure = true
    const catalogId = await resolveCatalogId(adminClient, productTenantId)

    if (mode === 'refresh') {
      return await refreshProductReview(adminClient, catalogId, productRecord)
    }

    await updateSyncStatus(adminClient, productId, 'syncing')
    const shouldPublish = productRecord.is_whatsapp_catalog === true &&
      productRecord.is_active !== false &&
      productRecord.is_published !== false

    return shouldPublish
      ? await upsertProduct(adminClient, catalogId, productRecord)
      : await removeProduct(adminClient, catalogId, productRecord)
  } catch (error) {
    console.error('whatsapp-catalog-sync error', error)
    if (canPersistFailure) {
      await updateSyncStatus(
        adminClient,
        productId,
        'failed',
        { error: error instanceof Error ? error.message : String(error) },
      )
    }
    return jsonResponse({
      error: error instanceof Error ? error.message : String(error),
    }, 500)
  }
})
