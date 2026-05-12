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
        website_name,
        sku,
        description,
        website_description,
        website_merchant_title,
        website_merchant_description,
        website_merchant_brand,
        website_merchant_gtin,
        website_merchant_mpn,
        website_google_product_category,
        price,
        website_price,
        price_currency,
        stock_quantity,
        image_url,
        website_image_url,
        website_image_url_optimized,
        image_urls,
        website_image_urls,
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
      firstNonEmpty(p.website_image_url, p.image_url) ||
      firstNonEmpty(p.website_image_url_optimized, null) ||
      ((p.website_image_urls?.length || 0) > 0) ||
      ((p.image_urls?.length || 0) > 0)
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
  
  const gallery = product.website_image_urls?.length
    ? product.website_image_urls
    : (product.image_urls || [])

  // Image - website override first, then optimized/base product imagery.
  const imageUrl = firstNonEmpty(
    product.website_image_url,
    product.website_image_url_optimized,
    product.image_url,
    gallery?.[0],
  )
  
  // Additional images (skip first if it's the same as main)
  const additionalImages = (gallery || [])
    .filter((img: string) => img !== imageUrl)
    .slice(0, 9) // Google allows max 10 images total
  
  // Title - fix excessive caps (convert ALL CAPS to Title Case)
  const rawTitle = firstNonEmpty(
    product.website_merchant_title,
    product.website_name,
    product.name,
  )
  const title = fixExcessiveCaps(rawTitle)
  
  // Description - must be at least 150 characters for Google
  // If too short, expand with brand, category, and store info
  let description = firstNonEmpty(
    product.website_merchant_description,
    product.website_description,
    product.description,
  )
  if (description.length < 150) {
    // Build a proper description
    const brand = firstNonEmpty(product.website_merchant_brand) ||
      (product.brand_id && brandsMap.has(product.brand_id)
      ? brandsMap.get(product.brand_id)! 
      : (product.brand || storeName))
    const category = product.category_id && categoriesMap.has(product.category_id)
      ? categoriesMap.get(product.category_id)!
      : (product.category_name || 'Ciclismo')
    
    description = `${title}. ${description ? description + '. ' : ''}Producto de la marca ${brand}, categoría ${category}. Disponible en ${storeName}, tu tienda de bicicletas y accesorios en Chile. Envíos a todo el país.`
  }
  // Ensure minimum 150 chars
  while (description.length < 150) {
    description += ` Compra online en ${storeName}.`
  }
  
  // Price with currency (default CLP)
  const currency = product.price_currency || 'CLP'
  const price = `${Math.round(product.website_price || product.price)} ${currency}`
  
  // Availability based on stock
  const availability = product.stock_quantity > 0 ? 'in_stock' : 'out_of_stock'
  
  // Brand resolution: brand_id → brands table → product.brand → store name
  let brand = firstNonEmpty(product.website_merchant_brand)
  if (!brand && product.brand_id && brandsMap.has(product.brand_id)) {
    brand = brandsMap.get(product.brand_id)!
  } else if (!brand && product.brand) {
    brand = product.brand
  } else if (!brand) {
    brand = storeName
  }
  
  // Category path from categories table
  let categoryPath = ''
  if (product.category_id && categoriesMap.has(product.category_id)) {
    categoryPath = categoriesMap.get(product.category_id)!
  } else if (product.category_name) {
    categoryPath = product.category_name
  }
  
  // GTIN: prefer gtin field, fallback to barcode
  const gtin = firstNonEmpty(
    product.website_merchant_gtin,
    product.gtin,
    product.barcode,
  )
  
  // MPN: use SKU
  const mpn = firstNonEmpty(product.website_merchant_mpn, product.sku)

  // Build item XML
  let itemXml = `    <item>
      <g:id>${escapeXml(product.id)}</g:id>
      <g:title>${escapeXml(title)}</g:title>
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
  if (gtin && gtin.length >= 8) {
    itemXml += `\n      <g:gtin>${escapeXml(gtin)}</g:gtin>`
  } else {
    // No valid GTIN - must explicitly mark identifier_exists as false
    itemXml += `\n      <g:identifier_exists>false</g:identifier_exists>`
  }
  
  // Add MPN (SKU) - always add if available
  if (mpn) {
    itemXml += `\n      <g:mpn>${escapeXml(mpn)}</g:mpn>`
  }
  
  // Add category path as product_type (merchant's own category)
  if (categoryPath) {
    itemXml += `\n      <g:product_type>${escapeXml(categoryPath)}</g:product_type>`
  }
  
  // Google product category - USE NUMERIC ID, not text!
  // 3618 = Sporting Goods > Outdoor Recreation > Cycling > Bicycle Parts & Accessories
  // 1085 = Sporting Goods > Outdoor Recreation > Cycling > Bicycles
  // For general cycling products, use the parent category ID
  // See: https://www.google.com/basepages/producttype/taxonomy-with-ids.en-US.txt
  itemXml += `\n      <g:google_product_category>${escapeXml(firstNonEmpty(product.website_google_product_category, '3618'))}</g:google_product_category>`
  
  itemXml += `\n    </item>`
  
  return itemXml
}

// Fix titles with excessive capitalization (ALL CAPS → Title Case)
function fixExcessiveCaps(text: string): string {
  if (!text) return ''
  
  // Count uppercase vs lowercase letters
  const letters = text.replace(/[^a-zA-Z]/g, '')
  const upperCount = (letters.match(/[A-Z]/g) || []).length
  const lowerCount = (letters.match(/[a-z]/g) || []).length
  
  // If more than 60% uppercase, convert to Title Case
  if (letters.length > 0 && upperCount / letters.length > 0.6) {
    return text
      .toLowerCase()
      .split(' ')
      .map(word => {
        if (word.length === 0) return word
        // Keep certain words lowercase (Spanish articles/prepositions)
        const lowercaseWords = ['de', 'del', 'la', 'el', 'las', 'los', 'y', 'e', 'o', 'u', 'a', 'con', 'sin', 'para', 'por']
        if (lowercaseWords.includes(word)) return word
        // Capitalize first letter
        return word.charAt(0).toUpperCase() + word.slice(1)
      })
      .join(' ')
      // Ensure first character is always uppercase
      .replace(/^./, c => c.toUpperCase())
  }
  
  return text
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

function firstNonEmpty(...values: Array<string | null | undefined>): string {
  for (const value of values) {
    const text = String(value ?? '').trim()
    if (text.length > 0) return text
  }
  return ''
}
