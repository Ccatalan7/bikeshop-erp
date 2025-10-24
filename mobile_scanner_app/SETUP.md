# 🚀 Quick Setup Guide

## 1. Create the Flutter project

```bash
cd /Users/Claudio/Dev
flutter create vinabike_scanner
cd vinabike_scanner
```

## 2. Replace files

Copy all files from `mobile_scanner_app/` into the newly created project:

```bash
# From the bikeshop-erp directory
cp -r mobile_scanner_app/lib/* vinabike_scanner/lib/
cp mobile_scanner_app/pubspec.yaml vinabike_scanner/pubspec.yaml
```

## 3. Configure Supabase

Open `vinabike_scanner/lib/main.dart` and replace:

```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL_HERE',  // ← Replace this
  anonKey: 'YOUR_SUPABASE_ANON_KEY_HERE',  // ← And this
);
```

With your actual credentials from the main ERP project.

## 4. Install dependencies

```bash
cd vinabike_scanner
flutter pub get
```

## 5. Run on your phone

```bash
# Android
flutter run

# iOS (requires Mac + Xcode)
flutter run
```

## 6. Pair with Windows ERP

1. On Windows ERP: Go to `Configuración → Dispositivos → Escáner Remoto`
2. Click "Iniciar" to start listening
3. On your phone: Scan the QR code shown on Windows
4. Start scanning barcodes! 📱→💻

---

## Platform-Specific Setup

### Android

Add camera permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" />
<uses-feature android:name="android.hardware.camera.autofocus" />
```

### iOS

Add camera permission to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to scan barcodes</string>
```

---

## Troubleshooting

**Build errors?**
- Run `flutter clean && flutter pub get`
- Make sure Flutter SDK is up to date: `flutter upgrade`

**Camera not working?**
- Check permissions in phone settings
- Restart the app

**Scans not reaching Windows?**
- Verify Supabase credentials match
- Check both devices are online
- Ensure "Escáner Remoto" is listening on Windows

---

## Next Steps

- Customize app icon (optional)
- Build APK for distribution: `flutter build apk`
- Test with multiple phones simultaneously
- Add custom vibration patterns (optional)

Enjoy your wireless barcode scanner! 🎉
