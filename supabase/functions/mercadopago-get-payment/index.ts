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
    const { payment_id, tenant_id } = await req.json()

    if (!payment_id) {
      return new Response(
        JSON.stringify({ error: 'payment_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    let query = supabase
      .from('website_settings')
      .select('value')
      .eq('key', 'mercadopago_access_token')
      .limit(1)

    if (tenant_id) {
      query = query.eq('tenant_id', tenant_id)
    }

    const { data: settings, error: settingsError } = await query

    if (settingsError) {
      throw new Error(`Settings query failed: ${settingsError.message}`)
    }

    const accessToken = settings?.[0]?.value

    if (!accessToken) {
      return new Response(
        JSON.stringify({ error: 'MercadoPago not configured for this tenant' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const mpResponse = await fetch(
      `https://api.mercadopago.com/v1/payments/${encodeURIComponent(payment_id)}`,
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      },
    )

    const payment = await mpResponse.json()

    if (!mpResponse.ok) {
      return new Response(
        JSON.stringify({ error: 'MercadoPago API error', details: payment }),
        { status: mpResponse.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(
      JSON.stringify(payment),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
