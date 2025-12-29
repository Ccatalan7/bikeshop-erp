#!/bin/bash

# Sync SEO Settings from Supabase to index.html before deployment
# This script reads SEO settings from the database and updates web/index.html
#
# Usage: ./scripts/sync_seo_index.sh
# Called automatically by the deploy workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INDEX_FILE="$PROJECT_ROOT/web/index.html"

# Supabase configuration
SUPABASE_URL="https://xzdvtzdqjeyqxnkqprtf.supabase.co"
TENANT_ID="5443b130-cc28-45af-a420-cd500b288890"  # Viñabike production

echo "🔄 Syncing SEO settings from Supabase to index.html..."

# Fetch SEO settings from Supabase
SETTINGS=$(curl -s "${SUPABASE_URL}/rest/v1/website_settings?tenant_id=eq.${TENANT_ID}&select=key,value" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAwNjQyMzUsImV4cCI6MjA3NTY0MDIzNX0.q5OswWMx6C00dbSHlFSOKlv6BA6GKx36VtVSy8ohxAM" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAwNjQyMzUsImV4cCI6MjA3NTY0MDIzNX0.q5OswWMx6C00dbSHlFSOKlv6BA6GKx36VtVSy8ohxAM")

# Parse settings using jq (with fallbacks)
get_setting() {
  local key=$1
  local default=$2
  local value=$(echo "$SETTINGS" | jq -r ".[] | select(.key == \"$key\") | .value // empty" 2>/dev/null)
  echo "${value:-$default}"
}

# Get SEO values with fallbacks to legacy keys
BUSINESS_NAME=$(get_setting "seo_business_name" "$(get_setting "store_name" "Vinabike")")
PHONE=$(get_setting "seo_phone" "$(get_setting "contact_phone" "+56998357797")")
EMAIL=$(get_setting "seo_email" "$(get_setting "contact_email" "vinabikechile@gmail.com")")
ADDRESS_STREET=$(get_setting "seo_address_street" "$(get_setting "contact_address" "Álvarez 32, Local 17")")
ADDRESS_CITY=$(get_setting "seo_address_city" "Viña del Mar")
ADDRESS_COUNTRY=$(get_setting "seo_address_country" "Chile")
META_TITLE=$(get_setting "seo_meta_title" "$(get_setting "meta_title" "$BUSINESS_NAME - Tienda de Bicicletas")")
META_DESCRIPTION=$(get_setting "seo_meta_description" "$(get_setting "meta_description" "Tu tienda especializada en ciclismo, repuestos y servicio técnico.")")
CANONICAL_URL=$(get_setting "seo_canonical_url" "$(get_setting "store_url" "https://vinabike.cl")")
OG_IMAGE=$(get_setting "seo_og_image" "")
REFUND_URL=$(get_setting "seo_refund_policy_url" "/politica-de-reembolso")
TERMS_URL=$(get_setting "seo_terms_url" "/terminos-y-condiciones")
SHIPPING_URL=$(get_setting "seo_shipping_policy_url" "/politica-de-envios")
PRIVACY_URL=$(get_setting "seo_privacy_policy_url" "/politica-de-privacidad")
GA_ID=$(get_setting "seo_ga_id" "G-FR5Q37BW43")

# Full address
FULL_ADDRESS="$ADDRESS_STREET, $ADDRESS_CITY, $ADDRESS_COUNTRY"

echo "✅ Fetched settings:"
echo "   Business: $BUSINESS_NAME"
echo "   Phone: $PHONE"
echo "   Email: $EMAIL"
echo "   Address: $FULL_ADDRESS"
echo "   Meta Title: $META_TITLE"

# Create updated index.html content
cat > "$INDEX_FILE" << HEREDOC
<!DOCTYPE html>
<html lang="es">

<head>
  <base href="\$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  
  <!-- Primary Meta Tags -->
  <title>$META_TITLE</title>
  <meta name="title" content="$META_TITLE">
  <meta name="description" content="$META_DESCRIPTION">
  
  <!-- Canonical -->
  <link rel="canonical" href="$CANONICAL_URL">
  
  <!-- Open Graph / Facebook -->
  <meta property="og:type" content="website">
  <meta property="og:url" content="$CANONICAL_URL">
  <meta property="og:title" content="$META_TITLE">
  <meta property="og:description" content="$META_DESCRIPTION">
  <meta property="og:site_name" content="$BUSINESS_NAME">
  ${OG_IMAGE:+<meta property="og:image" content="$OG_IMAGE">}
  
  <!-- Twitter -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:url" content="$CANONICAL_URL">
  <meta name="twitter:title" content="$META_TITLE">
  <meta name="twitter:description" content="$META_DESCRIPTION">
  ${OG_IMAGE:+<meta name="twitter:image" content="$OG_IMAGE">}

  <!-- Google Analytics GA4 -->
  <script async src="https://www.googletagmanager.com/gtag/js?id=$GA_ID"></script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag() { dataLayer.push(arguments); }
    gtag('js', new Date());
    gtag('config', '$GA_ID');
  </script>

  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="$BUSINESS_NAME">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png" />
  <link rel="manifest" href="manifest.json">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <link rel="preload" href="flutter_bootstrap.js" as="script">
  
  <style>
    html,
    body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      overscroll-behavior-x: none;
      background: #ffffff;
    }

    body {
      touch-action: pan-y pinch-zoom;
    }

    /* Minimal loading - just white page, Flutter takes over */
    #app-shell {
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: #ffffff;
      z-index: 9999;
      transition: opacity 0.2s ease-out;
    }

    #app-shell.hidden {
      opacity: 0;
      pointer-events: none;
    }

    /* Visually hidden SEO content (for Merchant Center bots) */
    .sr-only {
      position: absolute;
      width: 1px;
      height: 1px;
      padding: 0;
      margin: -1px;
      overflow: hidden;
      clip: rect(0, 0, 0, 0);
      border: 0;
      white-space: nowrap;
    }
  </style>
  
  <!-- JSON-LD Structured Data for LocalBusiness -->
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "LocalBusiness",
    "name": "$BUSINESS_NAME",
    "telephone": "$PHONE",
    "email": "$EMAIL",
    "url": "$CANONICAL_URL",
    "address": {
      "@type": "PostalAddress",
      "streetAddress": "$ADDRESS_STREET",
      "addressLocality": "$ADDRESS_CITY",
      "addressCountry": "$ADDRESS_COUNTRY"
    }
  }
  </script>
</head>

<body>
  <!-- Minimal shell - just white background, hidden SEO content for bots -->
  <div id="app-shell">
    <!-- SEO Content (Visually Hidden for Merchant Center bots) -->
    <div class="sr-only">
      <h1>$BUSINESS_NAME - Tienda de Bicicletas en $ADDRESS_CITY</h1>
      <p>$META_DESCRIPTION</p>
      
      <!-- Navigation -->
      <nav>
        <a href="/productos">Productos</a>
        <a href="/servicios">Servicios</a>
        <a href="/contacto">Contacto</a>
      </nav>
      
      <!-- Business Contact Info -->
      <address>
        <p>Dirección: $FULL_ADDRESS</p>
        <p>Teléfono: $PHONE</p>
        <p>Email: $EMAIL</p>
      </address>
      
      <!-- Legal Links (Required by Google Merchant Center) -->
      <footer>
        <a href="$REFUND_URL">Política de Reembolso</a>
        <a href="$TERMS_URL">Términos y Condiciones</a>
        <a href="$SHIPPING_URL">Política de Envíos</a>
        <a href="$PRIVACY_URL">Política de Privacidad</a>
      </footer>
    </div>
  </div>

  <script>
    window.addEventListener('wheel', function (e) {
      if (Math.abs(e.deltaX) > 0) {
        let el = e.target, canScroll = false;
        while (el && el !== document.documentElement) {
          if (el.scrollWidth > el.clientWidth && ['auto', 'scroll'].includes(getComputedStyle(el).overflowX)) { canScroll = true; break; }
          el = el.parentElement;
        }
        if (!canScroll) e.preventDefault();
      }
    }, { passive: false });
  </script>
  <script src="flutter_bootstrap.js" async></script>
  <!-- 
    NOTE: Using default flutter_bootstrap.js loading.
    Custom renderer selection was removed because:
    1. It caused double initialization (flutter_bootstrap.js + custom load call)
    2. CanvasKit has font loading bugs (BindingError with Noto fonts)
    The app now uses Flutter's default renderer selection.
  -->
</body>

</html>
HEREDOC

echo "✅ index.html updated successfully!"
echo "📝 Generated with:"
echo "   - Business info: $BUSINESS_NAME, $PHONE, $EMAIL"
echo "   - Address: $FULL_ADDRESS"
echo "   - Legal pages: $REFUND_URL, $TERMS_URL, $SHIPPING_URL, $PRIVACY_URL"
echo "   - JSON-LD LocalBusiness schema"
echo "   - Open Graph meta tags"
echo "   - Twitter Card meta tags"
