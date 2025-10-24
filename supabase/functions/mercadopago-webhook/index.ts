import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const body = await req.json()
    console.log('Webhook received:', JSON.stringify(body, null, 2))

    const { type, action, data } = body

    // Get MercadoPago access token
    const { data: settings } = await supabase
      .from('website_settings')
      .select('value')
      .eq('key', 'mercadopago_access_token')
      .single()

    const accessToken = settings?.value

    if (!accessToken) {
      console.error('No access token found in website_settings')
      return new Response('Configuration error', { status: 500 })
    }

    // Handle merchant_order events
    if (type === 'merchant_order' || body.topic === 'merchant_order') {
      const orderId = data?.id
      if (!orderId) {
        return new Response('ok', { status: 200 })
      }

      // Fetch merchant order details
      const mpResponse = await fetch(`https://api.mercadopago.com/merchant_orders/${orderId}`, {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
        },
      })

      if (!mpResponse.ok) {
        console.error('MercadoPago API error:', await mpResponse.text())
        return new Response('MercadoPago API error', { status: mpResponse.status })
      }

      const merchantOrder = await mpResponse.json()
      
      // Get payment info from the merchant order
      const payments = merchantOrder.payments || []
      if (payments.length > 0) {
        const payment = payments[0]
        await processPayment(supabase, payment.id, accessToken)
      }

      return new Response('ok', { status: 200 })
    }

    // Handle payment events
    if (type === 'payment') {
      const paymentId = data?.id
      if (!paymentId) {
        return new Response('ok', { status: 200 })
      }

      await processPayment(supabase, paymentId, accessToken)
      return new Response('ok', { status: 200 })
    }

    // Unknown event type
    return new Response('ok', { status: 200 })
  } catch (error) {
    console.error('Webhook error:', error)
    return new Response('error', { status: 500 })
  }
})

async function processPayment(supabase: any, paymentId: string, accessToken: string) {
  // Fetch payment details from MercadoPago
  const mpResponse = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
    },
  })

  if (!mpResponse.ok) {
    console.error('MercadoPago payment API error:', await mpResponse.text())
    throw new Error('Failed to fetch payment details')
  }

  const payment = await mpResponse.json()
  console.log('Payment details:', JSON.stringify(payment, null, 2))

  // Update order based on payment status
  const orderId = payment.external_reference
  const status = payment.status // approved, pending, rejected, etc.

  let paymentStatus = 'pending'
  if (status === 'approved') {
    paymentStatus = 'paid'
  } else if (status === 'rejected' || status === 'cancelled') {
    paymentStatus = 'failed'
  }

  // Update online order
  await supabase
    .from('online_orders')
    .update({
      payment_status: paymentStatus,
      payment_method: 'mercadopago',
      payment_reference: paymentId.toString(),
      paid_at: status === 'approved' ? new Date().toISOString() : null,
    })
    .eq('id', orderId)

  // If approved, process the order (create invoice + payment)
  if (status === 'approved') {
    await supabase.rpc('process_online_order', { p_order_id: orderId })
  }
}
