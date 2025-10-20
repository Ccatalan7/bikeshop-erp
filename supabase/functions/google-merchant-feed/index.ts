// Supabase Edge Function: Google Merchant Center Product Feed
// Deploy with: supabase functions deploy google-merchant-feed

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase client
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Get all active products that are visible on website
    const { data: products, error } = await supabase
      .from('products')
      .select('*')
      .eq('show_on_website', true)
      .gt('stock_quantity', 0) // Only in-stock products
      .order('name')

    if (error) {
      console.error('Database error:', error)
      throw error
    }

    // Get website settings for store info
    const { data: settings } = await supabase
      .from('website_settings')
      .select('key, value')

    const settingsMap = new Map(
      (settings || []).map((s: any) => [s.key, s.value])
    )

    const storeName = settingsMap.get('store_name') || 'Vinabike'
    const storeUrl = settingsMap.get('store_url') || 'https://tienda.vinabike.cl'

    // Generate Google Shopping Feed XML
    const feed = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:g="http://base.google.com/ns/1.0">
  <channel>
    <title>${escapeXml(storeName)}</title>
    <link>${escapeXml(storeUrl)}</link>
    <description>Bicicletas y accesorios en Chile</description>
${products.map(p => generateProductItem(p, storeUrl)).join('\n')}
  </channel>
</rss>`

    return new Response(feed, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/xml; charset=utf-8',
        'Cache-Control': 'public, max-age=3600', // Cache for 1 hour
      },
    })
  } catch (error) {
    console.error('Error generating feed:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})

function generateProductItem(product: any, storeUrl: string): string {
  const productUrl = `${storeUrl}/products/${product.id}`
  const imageUrl = product.image_url || `${storeUrl}/images/placeholder.jpg`
  
  // Use website description if available, fallback to regular description
  const description = product.website_description || product.description || product.name
  
  // Price with Chilean Peso
  const price = `${product.price} CLP`
  
  // Stock availability
  const availability = product.stock_quantity > 0 ? 'in stock' : 'out of stock'
  
  // Brand (default to store name)
  const brand = product.brand || 'Vinabike'
  
  return `    <item>
      <g:id>${escapeXml(product.id)}</g:id>
      <g:title>${escapeXml(product.name)}</g:title>
      <g:description>${escapeXml(description)}</g:description>
      <g:link>${escapeXml(productUrl)}</g:link>
      <g:image_link>${escapeXml(imageUrl)}</g:image_link>
      <g:condition>new</g:condition>
      <g:availability>${availability}</g:availability>
      <g:price>${price}</g:price>
      <g:brand>${escapeXml(brand)}</g:brand>
      ${product.barcode ? `<g:gtin>${escapeXml(product.barcode)}</g:gtin>` : ''}
      <g:mpn>${escapeXml(product.sku)}</g:mpn>
      ${product.category ? `<g:product_type>${escapeXml(product.category)}</g:product_type>` : ''}
      <g:google_product_category>Sporting Goods > Cycling</g:google_product_category>
    </item>`
}

function escapeXml(unsafe: string | null | undefined): string {
  if (!unsafe) return ''
  
  return String(unsafe)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

/* Deno.serve() will automatically call serve() */
