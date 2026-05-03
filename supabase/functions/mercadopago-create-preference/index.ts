import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function normalizeBaseUrl(value: unknown): string {
  if (typeof value !== 'string') return 'https://vinabike.cl'

  const trimmed = value.trim().replace(/\/+$/, '')
  if (!/^https:\/\//i.test(trimmed)) return 'https://vinabike.cl'
  return trimmed
}

function roundMoney(value: number): number {
  return Math.round(value * 100) / 100
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  try {
    const payload = await req.json().catch(() => null)
    const orderId = payload?.order_id?.toString() ?? ''
    const tenantId = payload?.tenant_id?.toString() ?? ''

    if (!orderId || !tenantId) {
      return jsonResponse({ error: 'order_id and tenant_id are required' }, 400)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const { data: settings, error: settingsError } = await supabase
      .from('website_settings')
      .select('key, value')
      .eq('tenant_id', tenantId)
      .in('key', ['mercadopago_access_token', 'mercadopago_test_mode', 'store_url'])

    if (settingsError) {
      throw new Error(`Settings query failed: ${settingsError.message}`)
    }

    const accessToken = settings?.find((setting: any) => setting.key === 'mercadopago_access_token')?.value
    const storeUrl = normalizeBaseUrl(settings?.find((setting: any) => setting.key === 'store_url')?.value)

    if (!accessToken) {
      return jsonResponse({ error: 'MercadoPago not configured for this tenant' }, 400)
    }

    const { data: order, error: orderError } = await supabase
      .from('online_orders')
      .select(`
        id,
        tenant_id,
        order_number,
        customer_email,
        customer_name,
        total,
        status,
        payment_status,
        payment_method,
        online_order_items (
          id,
          product_id,
          product_name,
          quantity,
          unit_price,
          subtotal
        )
      `)
      .eq('id', orderId)
      .eq('tenant_id', tenantId)
      .maybeSingle()

    if (orderError) {
      throw new Error(`Order query failed: ${orderError.message}`)
    }

    if (!order) {
      return jsonResponse({ error: 'Order not found' }, 404)
    }

    if (order.status === 'cancelled') {
      return jsonResponse({ error: 'Order is cancelled' }, 409)
    }

    if (order.payment_status === 'paid') {
      return jsonResponse({ error: 'Order is already paid' }, 409)
    }

    const orderItems = Array.isArray(order.online_order_items) ? order.online_order_items : []
    if (orderItems.length === 0) {
      return jsonResponse({ error: 'Order has no items' }, 409)
    }

    const productIds = orderItems.map((item: any) => item.product_id).filter(Boolean)
    const { data: products, error: productsError } = await supabase
      .from('products')
      .select('id, price, is_active, is_published, show_on_website, product_type, track_stock, inventory_qty, stock_quantity')
      .eq('tenant_id', tenantId)
      .in('id', productIds)

    if (productsError) {
      throw new Error(`Product validation failed: ${productsError.message}`)
    }

    const productsById = new Map((products ?? []).map((product: any) => [product.id, product]))
    let computedTotal = 0

    const preferenceItems = orderItems.map((item: any) => {
      const product = productsById.get(item.product_id)
      const quantity = Number(item.quantity)

      if (!product || product.is_active !== true || product.is_published !== true || product.show_on_website === false) {
        throw new Error(`Product is unavailable: ${item.product_id}`)
      }

      if (!Number.isInteger(quantity) || quantity < 1 || quantity > 99) {
        throw new Error(`Invalid quantity for product: ${item.product_id}`)
      }

      const unitPrice = roundMoney(Number(product.price ?? 0))
      const itemUnitPrice = roundMoney(Number(item.unit_price ?? 0))
      const itemSubtotal = roundMoney(Number(item.subtotal ?? 0))
      const expectedSubtotal = roundMoney(unitPrice * quantity)

      if (unitPrice <= 0 || Math.abs(itemUnitPrice - unitPrice) > 1 || Math.abs(itemSubtotal - expectedSubtotal) > 1) {
        throw new Error(`Order item price mismatch: ${item.product_id}`)
      }

      computedTotal = roundMoney(computedTotal + expectedSubtotal)

      return {
        title: String(item.product_name ?? 'Producto').slice(0, 120),
        quantity,
        unit_price: unitPrice,
        currency_id: 'CLP',
      }
    })

    if (Math.abs(computedTotal - Number(order.total ?? 0)) > 1) {
      return jsonResponse({ error: 'Order total mismatch' }, 409)
    }

    const backUrls = {
      success: `${storeUrl}/pedido/${order.id}?status=success`,
      failure: `${storeUrl}/pedido/${order.id}?status=failure`,
      pending: `${storeUrl}/pedido/${order.id}?status=pending`,
    }

    const mpResponse = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        items: preferenceItems,
        payer: {
          email: order.customer_email,
          name: order.customer_name,
        },
        back_urls: backUrls,
        auto_return: 'approved',
        notification_url: `${supabaseUrl.replace(/\/+$/, '')}/functions/v1/mercadopago-webhook`,
        external_reference: order.id,
        statement_descriptor: 'VINABIKE',
        metadata: {
          order_id: order.id,
          tenant_id: order.tenant_id,
          order_number: order.order_number,
        },
      }),
    })

    const preference = await mpResponse.json()

    if (!mpResponse.ok) {
      console.error('[MercadoPago] Preference creation failed', mpResponse.status, preference)
      return jsonResponse({ error: 'MercadoPago preference creation failed' }, 502)
    }

    return jsonResponse(preference)
  } catch (error) {
    console.error('[MercadoPago] Create preference error', error)
    return jsonResponse({ error: error instanceof Error ? error.message : 'Unknown error' }, 400)
  }
})