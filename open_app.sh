#!/bin/bash
# Quick script to open the built macOS app location

echo "Opening vinabike_erp.app location in Finder..."
open /Users/Claudio/Dev/bikeshop-erp/build/macos/Build/Products/Release

echo ""
echo "✅ Finder opened!"
echo ""
echo "The app is located at:"
echo "  build/macos/Build/Products/Release/vinabike_erp.app"
echo ""
echo "To install it permanently:"
echo "  1. Drag vinabike_erp.app to your Applications folder"
echo "  2. Or run: cp -r build/macos/Build/Products/Release/vinabike_erp.app /Applications/"
