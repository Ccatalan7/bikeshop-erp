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
ADDRESS_STREET_RAW=$(get_setting "seo_address_street" "$(get_setting "contact_address" "Álvarez 32, Local 17")")
ADDRESS_CITY=$(get_setting "seo_address_locality" "$(get_setting "seo_address_city" "Viña del Mar")")
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

# Theme fonts (used by WebsiteThemeBuilder via fontFamily)
HEADING_FONT=$(get_setting "theme_heading_font" "")
BODY_FONT=$(get_setting "theme_body_font" "")

# Build Google Fonts link tags for selected fonts (if any).
# We avoid bundling google_fonts; this just loads fonts via CSS.
build_google_fonts_links() {
  local heading="$1"
  local body="$2"

  # Basic skip list for system/font-stack values
  is_skippable_font() {
    local f="$1"
    if [[ -z "$f" ]]; then return 0; fi
    # If it's a stack like "Inter, system-ui, sans-serif" skip (can't map cleanly)
    if [[ "$f" == *","* ]]; then return 0; fi
    # Generic families
    local f_lc
    f_lc=$(echo "$f" | tr '[:upper:]' '[:lower:]')
    case "$f_lc" in
      system-ui|sans-serif|serif|monospace|cursive|fantasy|ui-sans-serif|ui-serif|ui-monospace)
        return 0
        ;;
    esac
    return 1
  }

  local families=()
  if ! is_skippable_font "$heading"; then families+=("$heading"); fi
  if ! is_skippable_font "$body" && [[ "$body" != "$heading" ]]; then families+=("$body"); fi

  if [[ ${#families[@]} -eq 0 ]]; then
    echo ""
    return
  fi

  local q=""
  for fam in "${families[@]}"; do
    # Replace spaces with + for URL encoding.
    local enc="${fam// /+}"
    # Request a reasonable range of weights; unsupported weights are ignored by Google Fonts.
    q+="family=${enc}:wght@300;400;500;600;700;800;900&"
  done
  q+="display=swap"

  cat << EOF
  <!-- Theme Fonts (loaded via Google Fonts; keeps Flutter bundle small) -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?${q}" rel="stylesheet">
EOF
}

GOOGLE_FONTS_LINKS=$(build_google_fonts_links "$HEADING_FONT" "$BODY_FONT")

# Normalize address pieces.
# The editor often stores a full address string (including city/country) in a single field.
# The index generator also prints city/country separately, which can cause duplicates like:
# "..., Viña del Mar, Chile, Viña del Mar, Chile".
normalize_street_address() {
  local street="$1"
  local city="$2"
  local country="$3"

  local street_clean="$street"

  # Generate ASCII/transliterated variants to handle e.g. "Vina" vs "Viña".
  local city_ascii="$city"
  local country_ascii="$country"
  if command -v iconv >/dev/null 2>&1; then
    city_ascii=$(printf '%s' "$city" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$city")
    country_ascii=$(printf '%s' "$country" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$country")
  fi

  # Strip trailing ", <country>" and ", <city>" if already present in the street field.
  for v in "$country" "$country_ascii"; do
    if [[ -n "$v" ]]; then
      street_clean=$(printf '%s' "$street_clean" | perl -pe "s/,\\s*\\Q$v\\E\\s*\$//i")
    fi
  done
  for v in "$city" "$city_ascii"; do
    if [[ -n "$v" ]]; then
      street_clean=$(printf '%s' "$street_clean" | perl -pe "s/,\\s*\\Q$v\\E\\s*\$//i")
    fi
  done

  # Final cleanup: trim trailing commas/spaces.
  street_clean=$(printf '%s' "$street_clean" | perl -pe 's/[\s,]+$//')
  printf '%s' "$street_clean"
}

normalize_country() {
  local country="$1"

  # Trim whitespace/commas.
  country=$(printf '%s' "$country" | perl -pe 's/^[\s,]+//; s/[\s,]+$//')

  # If the country field itself contains commas (e.g. "Chile, Chile"),
  # keep only the first token.
  if [[ "$country" == *","* ]]; then
    country=$(printf '%s' "$country" | awk -F',' '{print $1}')
    country=$(printf '%s' "$country" | perl -pe 's/^[\s,]+//; s/[\s,]+$//')
  fi

  # Guard against accidental duplication without commas ("Chile Chile").
  local lc
  lc=$(printf '%s' "$country" | tr '[:upper:]' '[:lower:]' | perl -pe 's/\s+/ /g')
  if [[ "$lc" == "chile chile" ]]; then
    country="Chile"
  fi

  printf '%s' "$country"
}

build_full_address() {
  local out=""
  local last_norm=""

  normalize_part() {
    local p="$1"
    p=$(printf '%s' "$p" | perl -pe 's/^[\s,]+//; s/[\s,]+$//; s/\s+/ /g')
    if command -v iconv >/dev/null 2>&1; then
      p=$(printf '%s' "$p" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$p")
    fi
    printf '%s' "$p" | tr '[:upper:]' '[:lower:]'
  }

  for part in "$@"; do
    if [[ -n "${part// }" ]]; then
      # Skip adjacent duplicates like "Chile, Chile".
      local norm
      norm=$(normalize_part "$part")
      if [[ -n "$last_norm" && "$norm" == "$last_norm" ]]; then
        continue
      fi

      if [[ -z "$out" ]]; then
        out="$part"
      else
        out="$out, $part"
      fi

      last_norm="$norm"
    fi
  done
  printf '%s' "$out"
}

ADDRESS_COUNTRY=$(normalize_country "$ADDRESS_COUNTRY")
ADDRESS_STREET=$(normalize_street_address "$ADDRESS_STREET_RAW" "$ADDRESS_CITY" "$ADDRESS_COUNTRY")

# Full address (safe from duplicates)
FULL_ADDRESS=$(build_full_address "$ADDRESS_STREET" "$ADDRESS_CITY" "$ADDRESS_COUNTRY")

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

  ${GOOGLE_FONTS_LINKS}

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
  <link rel="preconnect" href="https://vinabike-edge-cache.vinabike.workers.dev" crossorigin>
  <link rel="dns-prefetch" href="//vinabike-edge-cache.vinabike.workers.dev">
  <link rel="preload" href="flutter_bootstrap.js" as="script">
  <link rel="preload" href="main.dart.js" as="script">
  
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

    /* Loading screen with pulsing Vinabike logo */
    #app-shell {
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: #ffffff;
      z-index: 9999;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: opacity 0.3s ease-out;
    }

    #app-shell.hidden {
      opacity: 0;
      pointer-events: none;
    }

    /* Pulsing logo animation */
    #loading-logo {
      width: 200px;
      height: 200px;
      border-radius: 30px;
      animation: pulse 1.2s ease-in-out infinite;
    }

    @keyframes pulse {
      0%, 100% {
        transform: scale(0.95);
        opacity: 0.6;
      }
      50% {
        transform: scale(1.05);
        opacity: 1.0;
      }
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

  <!-- Pre-fetch public store data ASAP (overlaps Flutter engine startup) -->
  <script>
    (function () {
      try {
        // Only prefetch for Vinabike domains (avoid leaking wrong-tenant data on future multi-tenant hosts)
        var host = (window.location.host || '').toLowerCase();
        if (host.startsWith('www.')) host = host.substring(4);

        var isVinabikeHost = host === 'vinabike.cl' || host === 'vinabike-store.web.app';
        if (!isVinabikeHost) return;

        var tenantId = '$TENANT_ID';
        var edgeUrl = 'https://vinabike-edge-cache.vinabike.workers.dev/cache/public-store-data';

        // Exposed as a Promise so Flutter can await it via WebDataBridge
        window.flutter_injected_preloaded_data = (async function () {
          var controller = new AbortController();
          var timeout = setTimeout(function () { controller.abort(); }, 4500);
          try {
            var res = await fetch(edgeUrl, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ p_tenant_id: tenantId }),
              signal: controller.signal,
              credentials: 'omit',
            });

            if (!res.ok) return null;
            return await res.json();
          } catch (e) {
            return null;
          } finally {
            clearTimeout(timeout);
          }
        })();
      } catch (e) {
        // Ignore prefetch failures
      }
    })();
  </script>
</head>

<body>
  <!-- Loading screen with pulsing Vinabike logo -->
  <div id="app-shell">
    <img 
      id="loading-logo"
      src="vinabike-logo.png" 
      alt="$BUSINESS_NAME"
    />
    
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
