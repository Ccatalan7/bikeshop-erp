import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

    // Get MercadoPago access token (use .limit(1) instead of .single() for reliability)
    console.log('🔔 [WEBHOOK] Step 3: Fetching MercadoPago access token...')
    const { data: settings, error: settingsError } = await supabase
      .from('website_settings')
      .select('value')
      .eq('key', 'mercadopago_access_token')
      .limit(1)

    if (settingsError) {
      console.error('🔔 [WEBHOOK] Step 3: ❌ Settings query error:', settingsError)
      return new Response(JSON.stringify({ error: 'Settings query failed', details: settingsError }), { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const accessToken = settings?.[0]?.value
    console.log('🔔 [WEBHOOK] Step 3: ✅ Access token found:', accessToken ? 'YES (hidden)' : 'NO')

    if (!accessToken) {
      console.error('🔔 [WEBHOOK] Step 3: ❌ No access token in website_settings')
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
      const mpResponse = await fetch(`https://api.mercadopago.com/merchant_orders/${orderId}`, {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
        },
      })

      if (!mpResponse.ok) {
        const errorText = await mpResponse.text()
        console.error('🔔 [WEBHOOK] Step 4a: ❌ MercadoPago API error:', errorText)
        return new Response(JSON.stringify({ error: 'MercadoPago API error', details: errorText }), { 
          status: mpResponse.status,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      const merchantOrder = await mpResponse.json()
      console.log('🔔 [WEBHOOK] Step 4a: ✅ Merchant order fetched, payments:', merchantOrder.payments?.length || 0)
      
      const payments = merchantOrder.payments || []
      if (payments.length > 0) {
        const payment = payments[0]
        console.log('🔔 [WEBHOOK] Step 4b: Processing payment ID:', payment.id)
        await processPayment(supabase, payment.id, accessToken)
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
      await processPayment(supabase, paymentId, accessToken)
      
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

async function processPayment(supabase: any, paymentId: string, accessToken: string) {
  console.log('💳 [PROCESS_PAYMENT] ========== START ==========')
  console.log('💳 [PROCESS_PAYMENT] Payment ID:', paymentId)

  // Fetch payment details from MercadoPago
  console.log('💳 [PROCESS_PAYMENT] Step 1: Fetching payment from MP API...')
  const mpResponse = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
    },
  })

  if (!mpResponse.ok) {
    const errorText = await mpResponse.text()
    console.error('💳 [PROCESS_PAYMENT] Step 1: ❌ MP API error:', errorText)
    throw new Error(`Failed to fetch payment details: ${errorText}`)
  }

  const payment = await mpResponse.json()
  console.log('💳 [PROCESS_PAYMENT] Step 1: ✅ Payment fetched')
  console.log('💳 [PROCESS_PAYMENT] - Status:', payment.status)
  console.log('💳 [PROCESS_PAYMENT] - External Reference (Order ID):', payment.external_reference)
  console.log('💳 [PROCESS_PAYMENT] - Amount:', payment.transaction_amount)
  console.log('💳 [PROCESS_PAYMENT] - Payer Email:', payment.payer?.email)

  const orderId = payment.external_reference
  const status = payment.status

  if (!orderId) {
    console.error('💳 [PROCESS_PAYMENT] ❌ No external_reference (order ID) in payment!')
    throw new Error('Payment has no external_reference')
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
