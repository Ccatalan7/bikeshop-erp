import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { order_id, back_urls, notification_url, tenant_id } = await req.json()

    if (!order_id) {
      throw new Error('order_id is required')
    }

    // Monetary values are always loaded from the server-side order snapshot.
    // Client-supplied totals/items must never define a provider charge.
    const { data: order, error: orderError } = await supabase
      .from('online_orders')
      .select('id, tenant_id, order_number, total, customer_email, customer_name, payment_method, status')
      .eq('id', order_id)
      .maybeSingle()

    if (orderError) throw new Error(`Order lookup failed: ${orderError.message}`)
    if (!order) throw new Error('Order not found')
    if (tenant_id && tenant_id !== order.tenant_id) throw new Error('Order tenant mismatch')
    if (order.payment_method !== 'mercadopago') throw new Error('Order is not configured for MercadoPago')
    if (order.status === 'cancelled') throw new Error('Cancelled orders cannot be paid')

    const { data: orderItems, error: itemError } = await supabase
      .from('online_order_items')
      .select('product_name, quantity, unit_price, subtotal')
      .eq('order_id', order.id)
      .eq('tenant_id', order.tenant_id)

    if (itemError) throw new Error(`Order items lookup failed: ${itemError.message}`)
    if (!orderItems?.length) throw new Error('Order has no items')

    const itemTotal = orderItems.reduce(
      (sum: number, item: any) => sum + Number(item.subtotal),
      0,
    )
    if (Math.abs(itemTotal - Number(order.total)) > 0.01) {
      throw new Error('Order item total does not match order total')
    }

    // Get MercadoPago credentials from database (filtered by tenant_id)
    let query = supabase
      .from('website_settings')
      .select('key, value')
      .in('key', ['mercadopago_access_token', 'mercadopago_test_mode'])
    
    query = query.eq('tenant_id', order.tenant_id)
    
    const { data: settings } = await query

    const accessToken = settings?.find(s => s.key === 'mercadopago_access_token')?.value
    const isTestMode = settings?.find(s => s.key === 'mercadopago_test_mode')?.value === 'true'

    if (!accessToken) {
      throw new Error('MercadoPago not configured for this tenant')
    }

    // Create preference in MercadoPago
    const mpResponse = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        items: orderItems.map((item: any) => ({
          title: item.product_name,
          quantity: item.quantity,
          unit_price: item.unit_price,
          currency_id: 'CLP',
        })),
        payer: {
          email: order.customer_email,
          name: order.customer_name,
        },
        back_urls: back_urls,
        auto_return: 'approved',
        notification_url: notification_url,
        external_reference: order.id,
        statement_descriptor: `Pedido ${order.order_number}`,
      }),
    })

    const preference = await mpResponse.json()

    if (!mpResponse.ok) {
      throw new Error(`MercadoPago error: ${JSON.stringify(preference)}`)
    }

    return new Response(
      JSON.stringify(preference),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : 'Unknown error',
      }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
