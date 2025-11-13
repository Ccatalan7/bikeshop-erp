#!/bin/bash

# Path to the macOS app
APP_PATH="$(pwd)/build/macos/Build/Products/Release/vinabike_erp.app"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 VinaBike ERP - macOS App"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 App Location:"
echo "   $APP_PATH"
echo ""
echo "📦 App Size:"
du -sh "$APP_PATH" | awk '{print "   " $1}'
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Ask user what to do
PS3="Choose an action: "
options=("Open App" "Show in Finder" "Copy Path to Clipboard" "Exit")
select opt in "${options[@]}"
do
    case $opt in
        "Open App")
            echo "🚀 Opening app..."
            open "$APP_PATH"
            break
            ;;
        "Show in Finder")
            echo "📂 Opening in Finder..."
            open "$(dirname "$APP_PATH")"
            break
            ;;
        "Copy Path to Clipboard")
            echo "$APP_PATH" | pbcopy
            echo "✅ Path copied to clipboard!"
            break
            ;;
        "Exit")
            echo "👋 Goodbye!"
            break
            ;;
        *) echo "❌ Invalid option $REPLY";;
    esac
done
