#!/usr/bin/env bash
# Builds web/fonts/<font>.latin.woff2: the Latin subset of each font the HTML
# storefront declares, as WOFF2 (~20 KB against ~50 KB of the compressed
# TTF that Flutter uses). Firebase Hosting serves web/ as is, so the files
# sit at /fonts/ on the store. storefront_css.dart declares the same range,
# with the full TTF behind it for any other character; its test fails when
# the two ranges differ or a file is missing.
#
# Needs fontTools with Brotli: pip install fonttools brotli
set -euo pipefail
cd "$(dirname "$0")/../.."

# Google Fonts' «latin» range: Spanish, punctuation, €, ™ and arrows.
RANGE='U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD'

mkdir -p web/fonts
for font in Barlow-Regular Barlow-Medium Barlow-SemiBold Barlow-Bold Barlow-ExtraBold Oswald-wght; do
  # Default features plus tabular digits (prices use tabular-nums).
  pyftsubset "assets/fonts/$font.ttf" \
    --unicodes="$RANGE" \
    --layout-features+=tnum \
    --flavor=woff2 \
    --output-file="web/fonts/$font.latin.woff2"
done
ls -l web/fonts
