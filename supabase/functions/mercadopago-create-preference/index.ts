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

    // Get MercadoPago credentials from database
    const { data: settings } = await supabase
      .from('website_settings')
      .select('key, value')
      .in('key', ['mercadopago_access_token', 'mercadopago_test_mode'])

    const accessToken = settings?.find(s => s.key === 'mercadopago_access_token')?.value
    const isTestMode = settings?.find(s => s.key === 'mercadopago_test_mode')?.value === 'true'

    if (!accessToken) {
      throw new Error('MercadoPago not configured')
    }

    // Parse request body
    const { order_id, order_number, total, items, payer, back_urls, notification_url } = await req.json()

    // Create preference in MercadoPago
    const mpResponse = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        items: items.map((item: any) => ({
          title: item.title,
          quantity: item.quantity,
          unit_price: item.unit_price,
          currency_id: 'CLP',
        })),
        payer: {
          email: payer.email,
          name: payer.name,
        },
        back_urls: back_urls,
        auto_return: 'approved',
        notification_url: notification_url,
        external_reference: order_id,
        statement_descriptor: `Pedido ${order_number}`,
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
      JSON.stringify({ error: error.message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
