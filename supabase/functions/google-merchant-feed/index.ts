// Supabase Edge Function: Google Merchant Center Product Feed
// Deploy with: supabase functions deploy google-merchant-feed
//
// Usage:
//   GET /google-merchant-feed?tenant=vinabike     (by subdomain)
//   GET /google-merchant-feed?domain=vinabike.cl  (by custom domain)

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
    const url = new URL(req.url)
    const tenantSubdomain = url.searchParams.get('tenant')
    const customDomain = url.searchParams.get('domain')

    if (!tenantSubdomain && !customDomain) {
      return new Response(
        JSON.stringify({ 
          error: 'Missing tenant parameter',
          usage: 'Add ?tenant=your-subdomain or ?domain=your-domain.com'
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase client with service role (bypasses RLS)
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Step 1: Resolve tenant ID from subdomain or custom domain
    let tenantQuery = supabase.from('tenants').select('id, shop_name, subdomain, custom_domain')
    
    if (tenantSubdomain) {
      tenantQuery = tenantQuery.eq('subdomain', tenantSubdomain)
    } else if (customDomain) {
      tenantQuery = tenantQuery.eq('custom_domain', customDomain)
    }

    const { data: tenant, error: tenantError } = await tenantQuery.single()

    if (tenantError || !tenant) {
      // Debug: log what we're looking for
      console.error('Tenant lookup failed:', { 
        subdomain: tenantSubdomain, 
        customDomain, 
        error: tenantError?.message 
      })
      return new Response(
        JSON.stringify({ 
          error: 'Tenant not found',
          debug: {
            searchedSubdomain: tenantSubdomain,
            searchedDomain: customDomain,
            dbError: tenantError?.message
          }
        }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const tenantId = tenant.id

    // Step 2: Get website settings for this tenant
    const { data: settings } = await supabase
      .from('website_settings')
      .select('key, value')
      .eq('tenant_id', tenantId)

    const settingsMap = new Map(
      (settings || []).map((s: any) => [s.key, s.value])
    )

    // Build store URL from custom domain or subdomain
    let storeUrl: string
    if (tenant.custom_domain) {
      storeUrl = `https://${tenant.custom_domain}`
    } else if (tenant.subdomain) {
      // Use Firebase hosting pattern or configured URL
      storeUrl = settingsMap.get('store_url') || `https://${tenant.subdomain}.vinabike.cl`
    } else {
      storeUrl = settingsMap.get('store_url') || 'https://vinabike.cl'
    }

    const storeName = settingsMap.get('store_name') || tenant.shop_name || 'Tienda'
    const storeDescription = settingsMap.get('store_description') || `${storeName} - Bicicletas y accesorios`

    // Step 3: Get all active, published products for this tenant that are enabled for Google Merchant
    const { data: products, error: productsError } = await supabase
      .from('products')
      .select(`
        id,
        name,
        sku,
        description,
        price,
        price_currency,
        stock_quantity,
        image_url,
        image_urls,
        brand,
        brand_id,
        category_id,
        category_name,
        barcode,
        gtin,
        is_active,
        is_published,
        is_google_merchant,
        lifecycle_status
      `)
      .eq('tenant_id', tenantId)
      .eq('is_active', true)
      .eq('is_published', true)
      .eq('is_google_merchant', true)
      .eq('lifecycle_status', 'active')
      .gt('price', 0)
      .order('name')

    if (productsError) {
      console.error('Products error:', productsError)
      throw productsError
    }

    // Step 4: Get brand names for products with brand_id
    const brandIds = [...new Set(products?.filter(p => p.brand_id).map(p => p.brand_id))]
    let brandsMap = new Map<string, string>()
    
    if (brandIds.length > 0) {
      const { data: brands } = await supabase
        .from('product_brands')
        .select('id, name')
        .in('id', brandIds)
      
      brandsMap = new Map((brands || []).map((b: any) => [b.id, b.name]))
    }

    // Step 5: Get category paths for products with category_id
    const categoryIds = [...new Set(products?.filter(p => p.category_id).map(p => p.category_id))]
    let categoriesMap = new Map<string, string>()
    
    if (categoryIds.length > 0) {
      const { data: categories } = await supabase
        .from('product_categories')
        .select('id, full_path')
        .in('id', categoryIds)
      
      categoriesMap = new Map((categories || []).map((c: any) => [c.id, c.full_path]))
    }

    // Step 6: Filter products that have at least an image
    const validProducts = (products || []).filter(p => 
      p.image_url || (p.image_urls && p.image_urls.length > 0)
    )

    // Step 7: Generate XML feed
    const feed = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:g="http://base.google.com/ns/1.0">
  <channel>
    <title>${escapeXml(storeName)}</title>
    <link>${escapeXml(storeUrl)}</link>
    <description>${escapeXml(storeDescription)}</description>
${validProducts.map(p => generateProductItem(p, storeUrl, storeName, brandsMap, categoriesMap)).join('\n')}
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

function generateProductItem(
  product: any, 
  storeUrl: string, 
  storeName: string,
  brandsMap: Map<string, string>,
  categoriesMap: Map<string, string>
): string {
  // Product URL - uses /productos/ path (Spanish)
  const productUrl = `${storeUrl}/productos/${product.id}`
  
  // Image - prefer image_url, fallback to first in array
  const imageUrl = product.image_url || (product.image_urls?.[0]) || ''
  
  // Additional images (skip first if it's the same as main)
  const additionalImages = (product.image_urls || [])
    .filter((img: string) => img !== imageUrl)
    .slice(0, 9) // Google allows max 10 images total
  
  // Description - fallback to name if empty
  const description = product.description || product.name
  
  // Price with currency (default CLP)
  const currency = product.price_currency || 'CLP'
  const price = `${Math.round(product.price)} ${currency}`
  
  // Availability based on stock
  const availability = product.stock_quantity > 0 ? 'in_stock' : 'out_of_stock'
  
  // Brand resolution: brand_id → brands table → product.brand → store name
  let brand = storeName
  if (product.brand_id && brandsMap.has(product.brand_id)) {
    brand = brandsMap.get(product.brand_id)!
  } else if (product.brand) {
    brand = product.brand
  }
  
  // Category path from categories table
  let categoryPath = ''
  if (product.category_id && categoriesMap.has(product.category_id)) {
    categoryPath = categoriesMap.get(product.category_id)!
  } else if (product.category_name) {
    categoryPath = product.category_name
  }
  
  // GTIN: prefer gtin field, fallback to barcode
  const gtin = product.gtin || product.barcode || ''
  
  // MPN: use SKU
  const mpn = product.sku || ''

  // Build item XML
  let itemXml = `    <item>
      <g:id>${escapeXml(product.id)}</g:id>
      <g:title>${escapeXml(product.name)}</g:title>
      <g:description>${escapeXml(description)}</g:description>
      <g:link>${escapeXml(productUrl)}</g:link>
      <g:image_link>${escapeXml(imageUrl)}</g:image_link>`
  
  // Add additional images
  for (const img of additionalImages) {
    itemXml += `\n      <g:additional_image_link>${escapeXml(img)}</g:additional_image_link>`
  }
  
  itemXml += `
      <g:availability>${availability}</g:availability>
      <g:price>${price}</g:price>
      <g:brand>${escapeXml(brand)}</g:brand>
      <g:condition>new</g:condition>`
  
  // Add GTIN if available (preferred by Google)
  if (gtin) {
    itemXml += `\n      <g:gtin>${escapeXml(gtin)}</g:gtin>`
  }
  
  // Add MPN (required if no GTIN)
  if (mpn) {
    itemXml += `\n      <g:mpn>${escapeXml(mpn)}</g:mpn>`
  }
  
  // If no GTIN and no MPN, mark as identifier_exists = false
  if (!gtin && !mpn) {
    itemXml += `\n      <g:identifier_exists>false</g:identifier_exists>`
  }
  
  // Add category path as product_type
  if (categoryPath) {
    itemXml += `\n      <g:product_type>${escapeXml(categoryPath)}</g:product_type>`
  }
  
  // Google product category for cycling
  itemXml += `\n      <g:google_product_category>Sporting Goods &gt; Cycling</g:google_product_category>`
  
  itemXml += `\n    </item>`
  
  return itemXml
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
