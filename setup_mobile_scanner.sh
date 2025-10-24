#!/bin/bash

# 📱 Vinabike Mobile Scanner - Quick Setup Script
# This script automates the mobile app creation process

set -e  # Exit on error

echo "📱 Vinabike Mobile Scanner - Quick Setup"
echo "========================================"
echo ""

# Step 1: Check Flutter
echo "🔍 Checking Flutter installation..."
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter first."
    echo "   Visit: https://flutter.dev/docs/get-started/install"
    exit 1
fi

flutter --version
echo "✅ Flutter found"
echo ""

# Step 2: Navigate to Dev folder
DEV_DIR="$HOME/Dev"
if [ ! -d "$DEV_DIR" ]; then
    echo "📁 Creating $DEV_DIR folder..."
    mkdir -p "$DEV_DIR"
fi

cd "$DEV_DIR"
echo "📁 Working in: $(pwd)"
echo ""

# Step 3: Create Flutter project
APP_NAME="vinabike_scanner"
if [ -d "$APP_NAME" ]; then
    echo "⚠️  Project '$APP_NAME' already exists."
    read -p "   Delete and recreate? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Deleting existing project..."
        rm -rf "$APP_NAME"
    else
        echo "❌ Aborted."
        exit 1
    fi
fi

echo "🏗️  Creating Flutter project: $APP_NAME..."
flutter create "$APP_NAME" --platforms=android,ios
echo "✅ Project created"
echo ""

# Step 4: Copy template files
TEMPLATE_DIR="$HOME/Dev/bikeshop-erp/mobile_scanner_app"
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "❌ Template not found at: $TEMPLATE_DIR"
    echo "   Make sure you have the bikeshop-erp project with mobile_scanner_app folder."
    exit 1
fi

echo "📋 Copying template files..."
cp -r "$TEMPLATE_DIR/lib/"* "$APP_NAME/lib/"
cp "$TEMPLATE_DIR/pubspec.yaml" "$APP_NAME/pubspec.yaml"
echo "✅ Template files copied"
echo ""

# Step 5: Get dependencies
echo "📦 Installing dependencies..."
cd "$APP_NAME"
flutter pub get
echo "✅ Dependencies installed"
echo ""

# Step 6: Add Android permissions
echo "🔧 Adding Android permissions..."
ANDROID_MANIFEST="android/app/src/main/AndroidManifest.xml"
if ! grep -q "android.permission.CAMERA" "$ANDROID_MANIFEST"; then
    # Insert permissions before <application> tag
    sed -i.bak '/<application/i\
    <uses-permission android:name="android.permission.CAMERA" />\
    <uses-feature android:name="android.hardware.camera" />\
    <uses-feature android:name="android.hardware.camera.autofocus" />\
' "$ANDROID_MANIFEST"
    echo "✅ Android permissions added"
else
    echo "ℹ️  Android permissions already exist"
fi
echo ""

# Step 7: Add iOS permissions
echo "🔧 Adding iOS permissions..."
IOS_PLIST="ios/Runner/Info.plist"
if ! grep -q "NSCameraUsageDescription" "$IOS_PLIST"; then
    # Insert before closing </dict>
    sed -i.bak '/<\/dict>/i\
\	<key>NSCameraUsageDescription</key>\
\	<string>We need camera access to scan barcodes</string>
' "$IOS_PLIST"
    echo "✅ iOS permissions added"
else
    echo "ℹ️  iOS permissions already exist"
fi
echo ""

# Step 8: Prompt for Supabase credentials
echo "🔑 Supabase Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Please enter your Supabase credentials from the main ERP:"
echo "(You can find these in bikeshop-erp/lib/main.dart)"
echo ""

read -p "Supabase URL: " SUPABASE_URL
read -p "Supabase Anon Key: " SUPABASE_ANON_KEY

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo "⚠️  Credentials not provided. You'll need to add them manually to lib/main.dart"
else
    # Update main.dart with credentials
    sed -i.bak "s|YOUR_SUPABASE_URL_HERE|$SUPABASE_URL|g" "lib/main.dart"
    sed -i.bak "s|YOUR_SUPABASE_ANON_KEY_HERE|$SUPABASE_ANON_KEY|g" "lib/main.dart"
    echo "✅ Supabase credentials configured"
fi
echo ""

# Step 9: Build APK (optional)
echo "🏗️  Build Options"
echo "━━━━━━━━━━━━━━━━"
echo ""
echo "Would you like to:"
echo "1) Build APK for Android (takes ~5-10 minutes)"
echo "2) Skip and run on connected device"
echo "3) Exit (configure manually later)"
echo ""

read -p "Enter choice (1/2/3): " -n 1 -r
echo
echo ""

case $REPLY in
    1)
        echo "🔨 Building APK..."
        flutter build apk --release
        echo ""
        echo "✅ APK built successfully!"
        echo "📁 Location: build/app/outputs/flutter-apk/app-release.apk"
        echo ""
        echo "📲 To install on your phone:"
        echo "   adb install build/app/outputs/flutter-apk/app-release.apk"
        ;;
    2)
        echo "📱 Running on connected device..."
        flutter run
        ;;
    3)
        echo "👋 Setup complete. Run 'flutter run' when ready."
        ;;
    *)
        echo "⚠️  Invalid choice. Run 'flutter run' manually when ready."
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📱 App Location: $DEV_DIR/$APP_NAME"
echo ""
echo "📖 Next Steps:"
echo "   1. Open Windows ERP → Configuración → Escáner Remoto"
echo "   2. Click 'Iniciar' to start listening"
echo "   3. Launch the mobile app on your phone"
echo "   4. Scan the QR code to pair"
echo "   5. Start scanning barcodes!"
echo ""
echo "📚 Documentation:"
echo "   - MOBILE_SCANNER_COMPLETE_GUIDE.md (full guide)"
echo "   - mobile_scanner_app/SETUP.md (setup details)"
echo "   - BARCODE_SCANNER_GUIDE.md (all scanner types)"
echo ""
echo "✨ Enjoy your wireless barcode scanner!"
echo ""
