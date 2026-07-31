#!/bin/bash

# Sync SEO Settings from Supabase to index.html before deployment
# This script reads SEO settings from the database and updates web/index.html
#
# Usage: ./scripts/sync_seo_index.sh [--check]
# Called automatically by the deploy workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INDEX_FILE="$PROJECT_ROOT/web/index.html"
CHECK_ONLY=false

if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 64
fi

# Supabase configuration
SUPABASE_URL="https://xzdvtzdqjeyqxnkqprtf.supabase.co"
TENANT_ID="5443b130-cc28-45af-a420-cd500b288890"  # Viñabike production

resolve_supabase_api_key() {
  # CI already injects the independently managed secret key for this step.
  # Keep that explicit process-variable fallback until a dedicated protected
  # publishable variable exists; never obtain either key by listing project keys.
  local key="${SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_ANON_KEY:-${SUPABASE_SECRET_KEY:-}}}"

  if [[ -n "$key" ]]; then
    SUPABASE_API_KEY="$key"
    SUPABASE_API_KEY_SOURCE="environment"
    return 0
  fi

  if command -v security >/dev/null 2>&1; then
    key="$(security find-generic-password \
      -s 'Vinabike ERP Supabase publishable key' \
      -a supabase -w 2>/dev/null || true)"
    if [[ -n "$key" ]]; then
      SUPABASE_API_KEY="$key"
      SUPABASE_API_KEY_SOURCE="macOS Keychain"
      return 0
    fi
  fi

  echo "Could not load a Supabase API key for the SEO sync." >&2
  echo "Set SUPABASE_PUBLISHABLE_KEY (preferred), legacy SUPABASE_ANON_KEY, or the CI-only SUPABASE_SECRET_KEY in the process environment; otherwise install the documented publishable-key macOS Keychain entry." >&2
  exit 64
}

for required_command in curl jq perl; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "$required_command is required for the SEO sync." >&2
    exit 127
  fi
done

resolve_supabase_api_key

echo "🔄 Syncing SEO settings from Supabase to index.html..."

# Fetch SEO settings from Supabase
SETTINGS=$(curl --fail --show-error --silent \
  "${SUPABASE_URL}/rest/v1/website_settings?tenant_id=eq.${TENANT_ID}&select=key,value" \
  -H "apikey: ${SUPABASE_API_KEY}")

if ! echo "$SETTINGS" | jq -e 'type == "array" and length > 0' >/dev/null; then
  echo "Supabase returned no usable SEO settings; index.html was not changed." >&2
  exit 65
fi
if ! echo "$SETTINGS" | jq -e '
  all(.[]; (.key | type) == "string" and (.value == null or (.value | type) == "string"))
  and (group_by(.key) | all(.[]; length == 1))
' >/dev/null; then
  echo "Supabase returned duplicated or malformed website settings; index.html was not changed." >&2
  exit 65
fi

# Parse settings using jq (with fallbacks)
get_setting() {
  local key=$1
  local default=$2
  local value
  value=$(echo "$SETTINGS" | jq -r ".[] | select(.key == \"$key\") | .value // empty" 2>/dev/null)
  echo "${value:-$default}"
}

# Get SEO values with fallbacks to legacy keys
BUSINESS_NAME=$(get_setting "seo_business_name" "$(get_setting "store_name" "")")
LEGAL_NAME=$(get_setting "business_legal_name" "")
TAX_ID=$(get_setting "business_tax_id" "")
PHONE=$(get_setting "seo_phone" "$(get_setting "contact_phone" "")")
EMAIL=$(get_setting "seo_email" "$(get_setting "contact_email" "")")
ADDRESS_STREET_RAW=$(get_setting "seo_address_street" "$(get_setting "contact_address" "")")
ADDRESS_CITY=$(get_setting "seo_address_city" "$(get_setting "seo_address_locality" "")")
ADDRESS_REGION=$(get_setting "seo_address_region" "")
ADDRESS_POSTAL=$(get_setting "seo_address_postal" "")
ADDRESS_COUNTRY=$(get_setting "seo_address_country" "")
ADDRESS_COUNTRY_CODE=$(get_setting "seo_address_country_code" "")
INSTAGRAM=$(get_setting "instagram" "")
META_TITLE=$(get_setting "seo_meta_title" "$(get_setting "meta_title" "")")
META_DESCRIPTION=$(get_setting "seo_meta_description" "$(get_setting "meta_description" "$(get_setting "store_description" "")")")
# `store_url` is the unique canonical-base owner. Legacy aliases are mirrored
# when the editor saves settings, but deployment must never revive one as an
# independent fallback.
CANONICAL_URL=$(get_setting "store_url" "")
OG_IMAGE=$(get_setting "seo_og_image" "")
GA_ID=$(get_setting "seo_ga_id" "")

require_nonempty_setting() {
  local key="$1"
  local value="$2"
  if [[ -z "${value//[[:space:]]/}" ]]; then
    echo "Required website setting is empty: $key" >&2
    exit 65
  fi
}

require_nonempty_setting "seo_business_name/store_name" "$BUSINESS_NAME"
require_nonempty_setting "business_legal_name" "$LEGAL_NAME"
require_nonempty_setting "business_tax_id" "$TAX_ID"
require_nonempty_setting "seo_phone/contact_phone" "$PHONE"
require_nonempty_setting "seo_email/contact_email" "$EMAIL"
require_nonempty_setting "seo_address_street/contact_address" "$ADDRESS_STREET_RAW"
require_nonempty_setting "seo_address_city" "$ADDRESS_CITY"
require_nonempty_setting "seo_address_region" "$ADDRESS_REGION"
require_nonempty_setting "seo_address_postal" "$ADDRESS_POSTAL"
require_nonempty_setting "seo_address_country" "$ADDRESS_COUNTRY"
require_nonempty_setting "seo_meta_title/meta_title" "$META_TITLE"
require_nonempty_setting "seo_meta_description/meta_description" "$META_DESCRIPTION"
require_nonempty_setting "store_url" "$CANONICAL_URL"
require_nonempty_setting "seo_ga_id" "$GA_ID"

if [[ ! "$GA_ID" =~ ^G-[A-Z0-9]+$ ]]; then
  echo "Invalid GA4 measurement ID in website settings: $GA_ID" >&2
  exit 65
fi
GA_ID_JSON=$(jq -n --arg value "$GA_ID" '$value')

require_https_url() {
  local name="$1"
  local value="$2"
  local allow_empty="${3:-false}"

  if [[ -z "$value" && "$allow_empty" == true ]]; then
    return 0
  fi
  if [[ ! "$value" =~ ^https://[^[:space:]]+$ ]]; then
    echo "$name must be an HTTPS URL, got: $value" >&2
    exit 65
  fi
}

require_https_origin() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^https://([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+/?$ ]]; then
    echo "$name must be a clean HTTPS origin without credentials, paths, queries or fragments, got: $value" >&2
    exit 65
  fi
}

html_escape() {
  jq -nr --arg value "$1" '
    $value
    | gsub("&"; "&amp;")
    | gsub("<"; "&lt;")
    | gsub(">"; "&gt;")
    | gsub("\""; "&quot;")
    | gsub("\u0027"; "&#39;")
  '
}

require_https_origin "store_url" "$CANONICAL_URL"
CANONICAL_URL="${CANONICAL_URL%/}"
CANONICAL_HOST="${CANONICAL_URL#https://}"
CANONICAL_HOST_JSON=$(jq -n --arg value "$CANONICAL_HOST" '$value')
require_https_url "seo_og_image" "$OG_IMAGE" true
require_https_url "instagram" "$INSTAGRAM" true

# Theme fonts are bundled as Flutter assets so browser CSS caching does not
# diverge from Flutter's own font resolution.
GOOGLE_FONTS_LINKS=""

# Normalize address pieces.
# The editor often stores a full address string (including city/country) in a single field.
  # The index generator also prints city/country separately, which can cause
  # duplicated trailing locality/country components.
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

  # If the country field itself contains comma-separated duplicates,
  # keep only the first token.
  if [[ "$country" == *","* ]]; then
    country=$(printf '%s' "$country" | awk -F',' '{print $1}')
    country=$(printf '%s' "$country" | perl -pe 's/^[\s,]+//; s/[\s,]+$//')
  fi

  # Guard against a duplicated one-token country without commas.
  country=$(printf '%s' "$country" |
    perl -CS -pe 's/^(\S+)\s+\1$/$1/i')

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
FULL_ADDRESS=$(build_full_address "$ADDRESS_STREET" "$ADDRESS_CITY" "$ADDRESS_REGION" "$ADDRESS_POSTAL" "$ADDRESS_COUNTRY")
BUSINESS_NAME_HTML=$(html_escape "$BUSINESS_NAME")
PHONE_HTML=$(html_escape "$PHONE")
EMAIL_HTML=$(html_escape "$EMAIL")
FULL_ADDRESS_HTML=$(html_escape "$FULL_ADDRESS")
META_TITLE_HTML=$(html_escape "$META_TITLE")
META_DESCRIPTION_HTML=$(html_escape "$META_DESCRIPTION")
CANONICAL_URL_HTML=$(html_escape "$CANONICAL_URL")
OG_IMAGE_HTML=$(html_escape "$OG_IMAGE")

OG_IMAGE_OPEN_GRAPH_HTML=""
OG_IMAGE_TWITTER_HTML=""
if [[ -n "$OG_IMAGE_HTML" ]]; then
  OG_IMAGE_OPEN_GRAPH_HTML="<meta property=\"og:image\" content=\"$OG_IMAGE_HTML\">"
  OG_IMAGE_TWITTER_HTML="<meta name=\"twitter:image\" content=\"$OG_IMAGE_HTML\">"
fi

if [[ "$CHECK_ONLY" == true ]]; then
  require_index_value() {
    local label="$1"
    local expected="$2"
    if ! grep -F -- "$expected" "$INDEX_FILE" >/dev/null; then
      echo "web/index.html is stale for $label; run scripts/sync_seo_index.sh before building." >&2
      exit 65
    fi
  }

  require_index_absence() {
    local label="$1"
    local unexpected="$2"
    if grep -F -- "$unexpected" "$INDEX_FILE" >/dev/null; then
      echo "web/index.html contains stale $label; run scripts/sync_seo_index.sh before building." >&2
      exit 65
    fi
  }

  require_index_value "store_url" \
    "<link rel=\"canonical\" href=\"$CANONICAL_URL_HTML\">"
  require_index_value "seo_meta_title" \
    "<title>$META_TITLE_HTML</title>"
  require_index_value "seo_meta_title meta" \
    "<meta name=\"title\" content=\"$META_TITLE_HTML\">"
  require_index_value "seo_meta_description" \
    "<meta name=\"description\" content=\"$META_DESCRIPTION_HTML\">"
  require_index_value "Open Graph type" \
    "<meta property=\"og:type\" content=\"website\">"
  require_index_value "Open Graph URL" \
    "<meta property=\"og:url\" content=\"$CANONICAL_URL_HTML\">"
  require_index_value "Open Graph title" \
    "<meta property=\"og:title\" content=\"$META_TITLE_HTML\">"
  require_index_value "Open Graph description" \
    "<meta property=\"og:description\" content=\"$META_DESCRIPTION_HTML\">"
  require_index_value "Open Graph site name" \
    "<meta property=\"og:site_name\" content=\"$BUSINESS_NAME_HTML\">"
  require_index_value "Twitter card" \
    "<meta name=\"twitter:card\" content=\"summary_large_image\">"
  require_index_value "Twitter URL" \
    "<meta name=\"twitter:url\" content=\"$CANONICAL_URL_HTML\">"
  require_index_value "Twitter title" \
    "<meta name=\"twitter:title\" content=\"$META_TITLE_HTML\">"
  require_index_value "Twitter description" \
    "<meta name=\"twitter:description\" content=\"$META_DESCRIPTION_HTML\">"
  if [[ -n "$OG_IMAGE_HTML" ]]; then
    require_index_value "Open Graph image" \
      "<meta property=\"og:image\" content=\"$OG_IMAGE_HTML\">"
    require_index_value "Twitter image" \
      "<meta name=\"twitter:image\" content=\"$OG_IMAGE_HTML\">"
  else
    require_index_absence "Open Graph image" 'property="og:image"'
    require_index_absence "Twitter image" 'name="twitter:image"'
  fi
  require_index_value "seo_ga_id" \
    "gtag('config', \"$GA_ID\");"
  require_index_value "seo_business_name/store_name" \
    "<meta property=\"og:site_name\" content=\"$BUSINESS_NAME_HTML\">"
  require_index_value "Apple application title" \
    "<meta name=\"apple-mobile-web-app-title\" content=\"$BUSINESS_NAME_HTML\">"
  require_index_value "public fallback title" \
    "<h1>$META_TITLE_HTML</h1>"
  require_index_value "public fallback address" \
    "<p>Dirección: $FULL_ADDRESS_HTML</p>"
  require_index_value "public fallback phone" \
    "<p>Teléfono: $PHONE_HTML</p>"
  require_index_value "public fallback email" \
    "<p>Email: $EMAIL_HTML</p>"

  INDEX_MAIN_COUNT=$(perl -0777 -ne '$count = () = /<main\b/gi; print $count' "$INDEX_FILE")
  INDEX_H1_COUNT=$(perl -0777 -ne '$count = () = /<h1\b/gi; print $count' "$INDEX_FILE")
  if [[ "$INDEX_MAIN_COUNT" != "1" || "$INDEX_H1_COUNT" != "1" ]]; then
    echo "web/index.html must contain exactly one semantic main and one h1 (main=$INDEX_MAIN_COUNT, h1=$INDEX_H1_COUNT)." >&2
    exit 65
  fi

  if ! INDEX_LOCAL_BUSINESS_JSON=$(perl -0777 -ne '
    while (/<script\b[^>]*type="application\/ld\+json"[^>]*>(.*?)<\/script>/gis) {
      my $body = $1;
      if ($body =~ /"\@type"\s*:\s*"LocalBusiness"/) {
        print $body;
        $count++;
      }
    }
    END { exit(($count // 0) == 1 ? 0 : 2); }
  ' "$INDEX_FILE"); then
    echo "web/index.html must contain exactly one LocalBusiness JSON-LD node." >&2
    exit 65
  fi
  if ! printf '%s' "$INDEX_LOCAL_BUSINESS_JSON" | jq -e \
    --arg name "$BUSINESS_NAME" \
    --arg legal_name "$LEGAL_NAME" \
    --arg tax_id "$TAX_ID" \
    --arg phone "$PHONE" \
    --arg email "$EMAIL" \
    --arg url "$CANONICAL_URL" \
    --arg street "$ADDRESS_STREET" \
    --arg locality "$ADDRESS_CITY" \
    --arg region "$ADDRESS_REGION" \
    --arg postal "$ADDRESS_POSTAL" \
    --arg country "$ADDRESS_COUNTRY" \
    --arg country_code "$ADDRESS_COUNTRY_CODE" \
    --arg instagram "$INSTAGRAM" \
    '
      .["@type"] == "LocalBusiness"
      and .name == $name
      and .legalName == $legal_name
      and .taxID == $tax_id
      and .telephone == $phone
      and .email == $email
      and .url == $url
      and .address["@type"] == "PostalAddress"
      and .address.streetAddress == $street
      and .address.addressLocality == $locality
      and .address.addressRegion == $region
      and .address.postalCode == $postal
      and .address.addressCountry == $country
      and .areaServed["@type"] == "Country"
      and .areaServed.name == $country
      and .contactPoint["@type"] == "ContactPoint"
      and .contactPoint.contactType == "customer support"
      and .contactPoint.telephone == $phone
      and .contactPoint.email == $email
      and .contactPoint.availableLanguage == ["es"]
      and (
        if $country_code == ""
        then (.contactPoint | has("areaServed") | not)
        else .contactPoint.areaServed == $country_code
        end
      )
      and (
        if $instagram == ""
        then (has("sameAs") | not)
        else .sameAs == [$instagram]
        end
      )
    ' >/dev/null; then
    echo "web/index.html LocalBusiness JSON-LD is stale or does not match the canonical website settings." >&2
    exit 65
  fi

  SETTINGS_COUNT=$(echo "$SETTINGS" | jq 'length')
  echo "✅ SEO sync validation passed (${SETTINGS_COUNT} settings and a current index via ${SUPABASE_API_KEY_SOURCE})."
  exit 0
fi

JSON_LD=$(jq -cn \
  --arg name "$BUSINESS_NAME" \
  --arg legal_name "$LEGAL_NAME" \
  --arg tax_id "$TAX_ID" \
  --arg phone "$PHONE" \
  --arg email "$EMAIL" \
  --arg url "$CANONICAL_URL" \
  --arg street "$ADDRESS_STREET" \
  --arg locality "$ADDRESS_CITY" \
  --arg region "$ADDRESS_REGION" \
  --arg postal "$ADDRESS_POSTAL" \
  --arg country "$ADDRESS_COUNTRY" \
  --arg country_code "$ADDRESS_COUNTRY_CODE" \
  --arg instagram "$INSTAGRAM" \
  '({
    "@context": "https://schema.org",
    "@type": "LocalBusiness",
    name: $name,
    legalName: $legal_name,
    taxID: $tax_id,
    telephone: $phone,
    email: $email,
    url: $url,
    address: {
      "@type": "PostalAddress",
      streetAddress: $street,
      addressLocality: $locality,
      addressRegion: $region,
      postalCode: $postal,
      addressCountry: $country
    },
    areaServed: {"@type": "Country", name: $country},
    contactPoint: {
      "@type": "ContactPoint",
      contactType: "customer support",
      telephone: $phone,
      email: $email,
      availableLanguage: ["es"]
    }
  }
  | if $country_code == "" then .
    else .contactPoint.areaServed = $country_code
    end
  | if $instagram == "" then .
    else .sameAs = [$instagram]
    end)')
JSON_LD_SAFE=$(printf '%s' "$JSON_LD" |
  perl -pe 's/&/\\u0026/g; s/</\\u003c/g; s/>/\\u003e/g')

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
  <title>$META_TITLE_HTML</title>
  <meta name="title" content="$META_TITLE_HTML">
  <meta name="description" content="$META_DESCRIPTION_HTML">
  
  <!-- Canonical -->
  <link rel="canonical" href="$CANONICAL_URL_HTML">
  
  <!-- Open Graph / Facebook -->
  <meta property="og:type" content="website">
  <meta property="og:url" content="$CANONICAL_URL_HTML">
  <meta property="og:title" content="$META_TITLE_HTML">
  <meta property="og:description" content="$META_DESCRIPTION_HTML">
  <meta property="og:site_name" content="$BUSINESS_NAME_HTML">
  $OG_IMAGE_OPEN_GRAPH_HTML
  
  <!-- Twitter -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:url" content="$CANONICAL_URL_HTML">
  <meta name="twitter:title" content="$META_TITLE_HTML">
  <meta name="twitter:description" content="$META_DESCRIPTION_HTML">
  $OG_IMAGE_TWITTER_HTML

  ${GOOGLE_FONTS_LINKS}

  <!-- ERP shared-link handoff: WhatsApp opens HTTPS, this opens the desktop app. -->
  <script>
    (function () {
      try {
        var path = (window.location.pathname || '').replace(/\/+$/, '');
        if (path !== '/app/open') return;

        var params = new URLSearchParams(window.location.search || '');
        var route = params.get('route');
        if (!route) return;

        var title = params.get('title') || '';
        var appUrl = 'vinabike://app/open?route=' + encodeURIComponent(route) +
          '&title=' + encodeURIComponent(title);

        window.vinabikeAppHandoffUrl = appUrl;
        window.vinabikeAppHandoffStartedAt = Date.now();

        setTimeout(function () {
          window.location.href = appUrl;
        }, 30);
      } catch (e) {
        // Keep the Flutter fallback page available.
      }
    })();
  </script>

  <!-- Google Analytics GA4: queue immediately, fetch after critical loading. -->
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag() { dataLayer.push(arguments); }
    gtag('js', new Date());
    gtag('config', $GA_ID_JSON);

    (function () {
      var loaded = false;
      function loadGoogleAnalytics() {
        if (loaded) return;
        loaded = true;
        var script = document.createElement('script');
        script.async = true;
        script.src = 'https://www.googletagmanager.com/gtag/js?id=' +
          encodeURIComponent($GA_ID_JSON);
        document.head.appendChild(script);
      }
      function scheduleGoogleAnalytics() {
        if ('requestIdleCallback' in window) {
          window.requestIdleCallback(loadGoogleAnalytics, { timeout: 2500 });
        } else {
          window.setTimeout(loadGoogleAnalytics, 0);
        }
      }
      if (document.readyState === 'complete') {
        scheduleGoogleAnalytics();
      } else {
        window.addEventListener('load', scheduleGoogleAnalytics, { once: true });
      }
    })();
  </script>

  <!-- Meta Pixel is initialized at runtime from the tenant website setting. -->
  <script>
    (function (window, document) {
      window.vinabikeMetaPixelInit = function (pixelId) {
        var id = String(pixelId || '').trim();
        if (!/^\d+\$/.test(id)) return false;

        if (!window.fbq) {
          var fbq = window.fbq = function () {
            fbq.callMethod
              ? fbq.callMethod.apply(fbq, arguments)
              : fbq.queue.push(arguments);
          };
          if (!window._fbq) window._fbq = fbq;
          fbq.push = fbq;
          fbq.loaded = true;
          fbq.version = '2.0';
          fbq.queue = [];

          var script = document.createElement('script');
          script.async = true;
          script.src = 'https://connect.facebook.net/en_US/fbevents.js';
          var firstScript = document.getElementsByTagName('script')[0];
          firstScript.parentNode.insertBefore(script, firstScript);
        }

        if (window.__vinabikeMetaPixelId !== id) {
          window.fbq('init', id);
          window.__vinabikeMetaPixelId = id;
        }
        if (!window.__vinabikeMetaPageViewTracked) {
          window.fbq('track', 'PageView');
          window.__vinabikeMetaPageViewTracked = true;
        }
        return true;
      };

      window.vinabikeMetaPixelTrack = function (eventName, payloadJson, eventId) {
        if (!window.fbq || !window.__vinabikeMetaPixelId) return false;
        try {
          var payload = JSON.parse(payloadJson || '{}');
          if (eventId) {
            window.fbq('track', eventName, payload, { eventID: eventId });
          } else {
            window.fbq('track', eventName, payload);
          }
          return true;
        } catch (_) {
          return false;
        }
      };
    })(window, document);
  </script>

  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="$BUSINESS_NAME_HTML">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png" />
  <script>
    (function () {
      var path = window.location.pathname || '';
      var isWorkerPortal = path === '/worker' || path.indexOf('/worker/') === 0;
      var manifest = document.createElement('link');
      manifest.rel = 'manifest';
      manifest.href = isWorkerPortal ? 'manifest-worker.json' : 'manifest.json';
      document.head.appendChild(manifest);

      if (!isWorkerPortal) return;

      document.title = '$BUSINESS_NAME_HTML Trabajadores';
      var appleTitle = document.querySelector('meta[name="apple-mobile-web-app-title"]');
      if (appleTitle) appleTitle.setAttribute('content', '$BUSINESS_NAME_HTML Trabajadores');
      var themeColor = document.querySelector('meta[name="theme-color"]');
      if (themeColor) themeColor.setAttribute('content', '#0f4c5c');
      var robots = document.createElement('meta');
      robots.name = 'robots';
      robots.content = 'noindex,nofollow';
      document.head.appendChild(robots);
    })();
  </script>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <link rel="preconnect" href="https://vinabike-edge-cache.vinabike.workers.dev" crossorigin>
  <link rel="dns-prefetch" href="//vinabike-edge-cache.vinabike.workers.dev">
  <link rel="preconnect" href="https://www.gstatic.com" crossorigin>
  <link rel="dns-prefetch" href="//www.gstatic.com">
  <link rel="preconnect" href="https://xzdvtzdqjeyqxnkqprtf.supabase.co" crossorigin>
  <link rel="dns-prefetch" href="//xzdvtzdqjeyqxnkqprtf.supabase.co">
  <link rel="preload" href="main.dart.js" as="script">
  <link rel="preload" href="loading-logo.png" as="image" type="image/png" fetchpriority="high">
  
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

  </style>
  
  <!-- JSON-LD Structured Data for LocalBusiness -->
  <script type="application/ld+json">
  $JSON_LD_SAFE
  </script>

  <!-- Pre-fetch public store data ASAP (overlaps Flutter engine startup) -->
  <script>
    (function () {
      try {
        // Prefetch only for the canonical configured host.
        var host = (window.location.host || '').toLowerCase();
        if (host.startsWith('www.')) host = host.substring(4);

        var canonicalHost = $CANONICAL_HOST_JSON;
        if (host !== canonicalHost) return;

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
            var responseData = await res.json();
            if (
              !responseData ||
              typeof responseData !== 'object' ||
              Array.isArray(responseData) ||
              responseData.tenant_id !== tenantId
            ) {
              return null;
            }
            return {
              tenant_id: responseData.tenant_id,
              payload: responseData,
            };
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
      src="loading-logo.png"
      alt="$BUSINESS_NAME_HTML"
      width="200"
      height="200"
      fetchpriority="high"
    />
    
    <noscript id="storefront-nojs-fallback">
      <style>
        #app-shell {
          position: static;
          min-height: 100vh;
          box-sizing: border-box;
          overflow-y: auto;
          flex-direction: column;
          gap: 24px;
          padding: 24px;
        }

        #loading-logo {
          width: 120px;
          height: 120px;
          animation: none;
        }

        .storefront-nojs-fallback {
          width: min(100%, 720px);
          color: #111827;
          font-family: Arial, sans-serif;
          line-height: 1.5;
        }

        .storefront-nojs-fallback nav,
        .storefront-nojs-fallback footer {
          display: flex;
          flex-wrap: wrap;
          gap: 12px 20px;
          margin: 16px 0;
        }
      </style>
      <main class="storefront-nojs-fallback">
        <h1>$META_TITLE_HTML</h1>
        <p>$META_DESCRIPTION_HTML</p>

        <nav aria-label="Navegación principal">
        </nav>

        <address>
          <p>Dirección: $FULL_ADDRESS_HTML</p>
          <p>Teléfono: $PHONE_HTML</p>
          <p>Email: $EMAIL_HTML</p>
        </address>

        <footer aria-label="Información legal">
        </footer>
      </main>
    </noscript>
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
  <script>
    {{flutter_bootstrap_js}}
  </script>
  <!-- 
    NOTE: Flutter's generated default bootstrap is inlined above.
    Custom renderer selection was removed because:
    1. A second custom load call caused double initialization.
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
echo "   - Navigation links: deferred to the snapshot generator after content eligibility checks"
echo "   - JSON-LD LocalBusiness schema"
echo "   - Open Graph meta tags"
echo "   - Twitter Card meta tags"
