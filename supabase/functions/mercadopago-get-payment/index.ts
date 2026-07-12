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

function mapPaymentStatus(status: string): string {
  if (status === 'approved') return 'paid'
  if (status === 'rejected' || status === 'cancelled') return 'failed'
  return 'pending'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  try {
    const { payment_id, tenant_id, order_id } = await req.json()

    if (!payment_id || !tenant_id) {
      return jsonResponse({ error: 'payment_id and tenant_id are required' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    const { data: settings, error: settingsError } = await supabase
      .from('website_settings')
      .select('value')
      .eq('tenant_id', tenant_id)
      .eq('key', 'mercadopago_access_token')
      .limit(1)

    if (settingsError) {
      throw new Error(`Settings query failed: ${settingsError.message}`)
    }

    const accessToken = settings?.[0]?.value
    if (!accessToken) {
      return jsonResponse({ error: 'MercadoPago not configured for this tenant' }, 400)
    }

    const mpResponse = await fetch(
      `https://api.mercadopago.com/v1/payments/${encodeURIComponent(payment_id)}`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    )

    const payment = await mpResponse.json()

    if (!mpResponse.ok) {
      console.error('[MercadoPago] Payment fetch failed', mpResponse.status, payment)
      return jsonResponse({ error: 'MercadoPago API error' }, mpResponse.status)
    }

    const externalReference = payment?.external_reference?.toString() ?? ''
    if (order_id && externalReference !== order_id.toString()) {
      return jsonResponse({ error: 'Payment does not match order' }, 409)
    }

    if (!externalReference) {
      return jsonResponse({ error: 'Payment has no order reference' }, 409)
    }

    const { data: order, error: orderError } = await supabase
      .from('online_orders')
      .select('id, tenant_id, total')
      .eq('id', externalReference)
      .eq('tenant_id', tenant_id)
      .maybeSingle()

    if (orderError) {
      throw new Error(`Order query failed: ${orderError.message}`)
    }

    if (!order) {
      return jsonResponse({ error: 'Order not found for payment' }, 404)
    }

    const paymentStatus = mapPaymentStatus(payment.status)
    const paidAmount = Number(payment?.transaction_amount)
    if (!Number.isFinite(paidAmount)) {
      return jsonResponse({ error: 'Payment amount is invalid' }, 409)
    }

    const { data: eventResult, error: eventError } = await supabase.rpc(
      'apply_mercadopago_payment_event',
      {
        p_order_id: order.id,
        p_tenant_id: tenant_id,
        p_payment_id: payment_id.toString(),
        p_provider_status: payment.status,
        p_amount: paidAmount,
        p_currency: payment.currency_id?.toString() ?? '',
        p_paid_at: payment.date_approved ?? null,
        p_provider_payload: {
          status_detail: payment.status_detail ?? null,
          payment_type_id: payment.payment_type_id ?? null,
          merchant_order_id: payment.order?.id ?? null,
        },
      },
    )

    if (eventError) {
      throw new Error(`Payment event failed: ${eventError.message}`)
    }

    const eventOutcome = eventResult?.outcome?.toString() ?? ''
    if (eventOutcome.startsWith('rejected_')) {
      return jsonResponse({
        error: eventResult?.validation_error ?? 'Payment validation failed',
        event: eventResult,
      }, 409)
    }

    return jsonResponse({
      id: payment.id?.toString() ?? payment_id.toString(),
      status: payment.status,
      status_detail: payment.status_detail ?? null,
      external_reference: externalReference,
      payment_status: paymentStatus,
      event: eventResult,
    })
  } catch (error) {
    console.error('[MercadoPago] Get payment error', error)
    return jsonResponse({ error: error instanceof Error ? error.message : 'Unknown error' }, 500)
  }
})
