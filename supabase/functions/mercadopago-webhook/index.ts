import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { type, data } = await req.json()

    // Only process payment notifications
    if (type !== 'payment') {
      return new Response('ok', { status: 200 })
    }

    const paymentId = data.id

    // Get MercadoPago access token
    const { data: settings } = await supabase
      .from('website_settings')
      .select('value')
      .eq('key', 'mercadopago_access_token')
      .single()

    const accessToken = settings?.value

    // Fetch payment details from MercadoPago
    const mpResponse = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
      },
    })

    const payment = await mpResponse.json()

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

    return new Response('ok', { status: 200 })
  } catch (error) {
    console.error('Webhook error:', error)
    return new Response('error', { status: 500 })
  }
})
