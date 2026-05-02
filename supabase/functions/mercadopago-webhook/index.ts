import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type MercadoPagoToken = {
  tenant_id: string | null
  access_token: string
}

serve(async (req) => {
  console.log('🔔 [WEBHOOK] ========== REQUEST RECEIVED ==========')
  console.log('🔔 [WEBHOOK] Method:', req.method)
  console.log('🔔 [WEBHOOK] URL:', req.url)
  console.log('🔔 [WEBHOOK] Time:', new Date().toISOString())

  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    console.log('🔔 [WEBHOOK] CORS preflight - returning OK')
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('🔔 [WEBHOOK] Step 1: Creating Supabase client...')
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )
    console.log('🔔 [WEBHOOK] Step 1: ✅ Supabase client created')

    console.log('🔔 [WEBHOOK] Step 2: Parsing request body...')
    const body = await req.json()
    console.log('🔔 [WEBHOOK] Step 2: ✅ Body parsed:', JSON.stringify(body, null, 2))

    const { type, action, data } = body
    console.log('🔔 [WEBHOOK] Event type:', type, '| Action:', action, '| Data ID:', data?.id)

    console.log('🔔 [WEBHOOK] Step 3: Fetching configured MercadoPago tenant tokens...')
    const accessTokens = await loadMercadoPagoTokens(supabase)
    console.log('🔔 [WEBHOOK] Step 3: ✅ Token count:', accessTokens.length)

    if (accessTokens.length === 0) {
      console.error('🔔 [WEBHOOK] Step 3: ❌ No MercadoPago access tokens in website_settings')
      return new Response(JSON.stringify({ error: 'No access token configured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Handle merchant_order events
    if (type === 'merchant_order' || body.topic === 'merchant_order') {
      console.log('🔔 [WEBHOOK] Step 4: Processing MERCHANT_ORDER event...')
      const orderId = data?.id
      if (!orderId) {
        console.log('🔔 [WEBHOOK] Step 4: ⚠️ No order ID in merchant_order event')
        return new Response(JSON.stringify({ status: 'ok', message: 'No order ID' }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      console.log('🔔 [WEBHOOK] Step 4a: Fetching merchant order from MP API:', orderId)
      const merchantOrderResult = await fetchMercadoPagoResource(
        accessTokens,
        `https://api.mercadopago.com/merchant_orders/${encodeURIComponent(orderId)}`,
        'merchant_order'
      )

      if (!merchantOrderResult.ok) {
        console.error('🔔 [WEBHOOK] Step 4a: ❌ MercadoPago API error:', merchantOrderResult.errorText)
        return new Response(JSON.stringify({ error: 'MercadoPago API error', details: merchantOrderResult.errorText }), {
          status: merchantOrderResult.status,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      const merchantOrder = merchantOrderResult.data
      console.log('🔔 [WEBHOOK] Step 4a: ✅ Merchant order fetched, payments:', merchantOrder.payments?.length || 0)

      const payments = merchantOrder.payments || []
      if (payments.length > 0) {
        const payment = payments[0]
        console.log('🔔 [WEBHOOK] Step 4b: Processing payment ID:', payment.id)
        await processPayment(
          supabase,
          payment.id,
          accessTokens,
          merchantOrderResult.token?.tenant_id ?? null
        )
      } else {
        console.log('🔔 [WEBHOOK] Step 4b: ⚠️ No payments in merchant order')
      }

      console.log('🔔 [WEBHOOK] ========== MERCHANT_ORDER COMPLETE ==========')
      return new Response(JSON.stringify({ status: 'ok' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Handle payment events
    if (type === 'payment') {
      console.log('🔔 [WEBHOOK] Step 4: Processing PAYMENT event...')
      const paymentId = data?.id
      if (!paymentId) {
        console.log('🔔 [WEBHOOK] Step 4: ⚠️ No payment ID in event')
        return new Response(JSON.stringify({ status: 'ok', message: 'No payment ID' }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      console.log('🔔 [WEBHOOK] Step 4a: Payment ID:', paymentId)
      await processPayment(supabase, paymentId, accessTokens)

      console.log('🔔 [WEBHOOK] ========== PAYMENT COMPLETE ==========')
      return new Response(JSON.stringify({ status: 'ok' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Unknown event type - still return 200 to acknowledge
    console.log('🔔 [WEBHOOK] ⚠️ Unknown event type:', type, '- acknowledging anyway')
    return new Response(JSON.stringify({ status: 'ok', message: 'Unknown event type', type }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  } catch (error) {
    console.error('🔔 [WEBHOOK] ❌❌❌ FATAL ERROR:', error)
    console.error('🔔 [WEBHOOK] Error stack:', error.stack)
    return new Response(JSON.stringify({ error: error.message, stack: error.stack }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})

async function loadMercadoPagoTokens(supabase: any): Promise<MercadoPagoToken[]> {
  const { data: settings, error } = await supabase
    .from('website_settings')
    .select('tenant_id, value')
    .eq('key', 'mercadopago_access_token')

  if (error) {
    console.error('🔔 [WEBHOOK] ❌ Settings query error:', error)
    throw new Error(`Settings query failed: ${error.message}`)
  }

  return (settings ?? [])
    .filter((setting: any) => typeof setting.value === 'string' && setting.value.trim().length > 0)
    .map((setting: any) => ({
      tenant_id: setting.tenant_id ?? null,
      access_token: setting.value.trim(),
    }))
}

function orderedTokens(
  tokens: MercadoPagoToken[],
  preferredTenantId?: string | null,
): MercadoPagoToken[] {
  if (!preferredTenantId) return tokens

  return [
    ...tokens.filter((token) => token.tenant_id === preferredTenantId),
    ...tokens.filter((token) => token.tenant_id !== preferredTenantId),
  ]
}

async function fetchMercadoPagoResource(
  tokens: MercadoPagoToken[],
  url: string,
  label: string,
  preferredTenantId?: string | null,
): Promise<{
  ok: boolean
  status: number
  data?: any
  errorText?: string
  token?: MercadoPagoToken
}> {
  let lastStatus = 500
  let lastError = 'No configured MercadoPago token could fetch the resource'

  for (const token of orderedTokens(tokens, preferredTenantId)) {
    const response = await fetch(url, {
      headers: {
        'Authorization': `Bearer ${token.access_token}`,
      },
    })

    if (response.ok) {
      return {
        ok: true,
        status: response.status,
        data: await response.json(),
        token,
      }
    }

    lastStatus = response.status
    lastError = await response.text()
    console.warn(
      `🔔 [WEBHOOK] ${label} fetch failed for tenant ${token.tenant_id ?? 'global'}:`,
      response.status,
      lastError,
    )
  }

  return {
    ok: false,
    status: lastStatus,
    errorText: lastError,
  }
}

async function processPayment(
  supabase: any,
  paymentId: string,
  accessTokens: MercadoPagoToken[],
  preferredTenantId: string | null = null,
) {
  console.log('💳 [PROCESS_PAYMENT] ========== START ==========')
  console.log('💳 [PROCESS_PAYMENT] Payment ID:', paymentId)

  // Fetch payment details from MercadoPago
  console.log('💳 [PROCESS_PAYMENT] Step 1: Fetching payment from MP API...')
  let paymentResult = await fetchMercadoPagoResource(
    accessTokens,
    `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
    'payment',
    preferredTenantId,
  )

  if (!paymentResult.ok) {
    console.error('💳 [PROCESS_PAYMENT] Step 1: ❌ MP API error:', paymentResult.errorText)
    throw new Error(`Failed to fetch payment details: ${paymentResult.errorText}`)
  }

  let payment = paymentResult.data
  console.log('💳 [PROCESS_PAYMENT] Step 1: ✅ Payment fetched')
  console.log('💳 [PROCESS_PAYMENT] - Status:', payment.status)
  console.log('💳 [PROCESS_PAYMENT] - External Reference (Order ID):', payment.external_reference)
  console.log('💳 [PROCESS_PAYMENT] - Amount:', payment.transaction_amount)
  console.log('💳 [PROCESS_PAYMENT] - Payer Email:', payment.payer?.email)

  const orderId = payment.external_reference
  let status = payment.status

  if (!orderId) {
    console.error('💳 [PROCESS_PAYMENT] ❌ No external_reference (order ID) in payment!')
    throw new Error('Payment has no external_reference')
  }

  const { data: order, error: orderError } = await supabase
    .from('online_orders')
    .select('id, tenant_id')
    .eq('id', orderId)
    .maybeSingle()

  if (orderError) {
    console.error('💳 [PROCESS_PAYMENT] ❌ Order lookup error:', orderError)
    throw new Error(`Failed to look up order: ${orderError.message}`)
  }

  if (!order?.tenant_id) {
    console.error('💳 [PROCESS_PAYMENT] ❌ Order not found for external_reference:', orderId)
    throw new Error(`Order not found for external_reference: ${orderId}`)
  }

  if (paymentResult.token?.tenant_id && paymentResult.token.tenant_id !== order.tenant_id) {
    console.warn(
      '💳 [PROCESS_PAYMENT] Payment token tenant differed from order tenant; retrying exact tenant token.',
      paymentResult.token.tenant_id,
      order.tenant_id,
    )

    const tenantScopedTokens = accessTokens.filter(
      (token) => token.tenant_id === order.tenant_id || token.tenant_id === null,
    )
    const tenantPaymentResult = await fetchMercadoPagoResource(
      tenantScopedTokens,
      `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
      'payment',
      order.tenant_id,
    )

    if (
      !tenantPaymentResult.ok ||
      (tenantPaymentResult.token?.tenant_id && tenantPaymentResult.token.tenant_id !== order.tenant_id)
    ) {
      throw new Error(`Payment ${paymentId} does not match order tenant ${order.tenant_id}`)
    }

    paymentResult = tenantPaymentResult
    payment = tenantPaymentResult.data
    status = payment.status
  }

  let paymentStatus = 'pending'
  if (status === 'approved') {
    paymentStatus = 'paid'
  } else if (status === 'rejected' || status === 'cancelled') {
    paymentStatus = 'failed'
  }
  console.log('💳 [PROCESS_PAYMENT] Step 2: Mapped status:', status, '->', paymentStatus)

  // Update online order
  console.log('💳 [PROCESS_PAYMENT] Step 3: Updating online_orders table...')
  const { data: updateResult, error: updateError } = await supabase
    .from('online_orders')
    .update({
      payment_status: paymentStatus,
      payment_method: 'mercadopago',
      payment_reference: paymentId.toString(),
      paid_at: status === 'approved' ? new Date().toISOString() : null,
    })
    .eq('id', orderId)
    .eq('tenant_id', order.tenant_id)
    .select()

  if (updateError) {
    console.error('💳 [PROCESS_PAYMENT] Step 3: ❌ Update error:', updateError)
    throw new Error(`Failed to update order: ${updateError.message}`)
  }
  console.log('💳 [PROCESS_PAYMENT] Step 3: ✅ Order updated:', updateResult?.length || 0, 'rows')

  // If approved, process the order (create invoice + payment)
  if (status === 'approved') {
    console.log('💳 [PROCESS_PAYMENT] Step 4: Payment APPROVED - calling process_online_order...')
    const { data: invoiceId, error: rpcError } = await supabase.rpc('process_online_order', { p_order_id: orderId })

    if (rpcError) {
      console.error('💳 [PROCESS_PAYMENT] Step 4: ❌ RPC error:', rpcError)
      throw new Error(`Failed to process order: ${rpcError.message}`)
    }
    console.log('💳 [PROCESS_PAYMENT] Step 4: ✅ Invoice ID:', invoiceId)
  } else {
    console.log('💳 [PROCESS_PAYMENT] Step 4: ⚠️ Payment NOT approved (', status, ') - skipping invoice creation')
  }

  console.log('💳 [PROCESS_PAYMENT] ========== COMPLETE ==========')
}
