# 📱 Android APK Installation Guide

## ✅ APK Build Complete!

Your updated Vinabike ERP app with the new **Custom Logo Feature** has been built successfully!

---

## 📦 Available APK Files

### Location: `build/app/outputs/flutter-apk/`

### Option 1: Universal APK (Recommended for Simplicity)
- **File:** `app-release.apk`
- **Size:** 55.0 MB
- **Works on:** All Android devices (any architecture)
- **Use this if:** You want one file that works everywhere

### Option 2: Split APKs (Recommended for Smaller Size)
Choose the one that matches your phone's processor:

| File | Size | Architecture | Best For |
|------|------|--------------|----------|
| `app-arm64-v8a-release.apk` | 19.3 MB | ARM 64-bit | Most modern Android phones (2017+) |
| `app-armeabi-v7a-release.apk` | 17.1 MB | ARM 32-bit | Older Android phones |
| `app-x86_64-release.apk` | 20.5 MB | x86 64-bit | Emulators, some tablets |

**💡 Most phones use ARM64 (arm64-v8a)** - try this one first!

---

## 🔌 Installation Steps via USB

### Method 1: Using ADB (Advanced)
```powershell
# Connect your phone via USB and enable USB Debugging

# Install universal APK
adb install build/app/outputs/flutter-apk/app-release.apk

# OR install specific architecture (faster, smaller)
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Method 2: Manual Transfer (Easier)
1. **Connect your phone** to your computer via USB
2. **Copy the APK file** to your phone:
   - Open File Explorer
   - Navigate to: `C:\dev\ProjectVinabike\build\app\outputs\flutter-apk\`
   - Copy `app-release.apk` (or your preferred architecture)
   - Paste it into your phone's `Downloads` folder
3. **On your phone:**
   - Open the `Files` or `My Files` app
   - Navigate to `Downloads`
   - Tap on `app-release.apk`
   - Tap **Install** (you may need to enable "Install from Unknown Sources")
4. **Done!** Open the updated Vinabike ERP app

### Method 3: Using PowerShell Script
```powershell
# Quick install script - run from project root
cd C:\dev\ProjectVinabike

# Check if device is connected
adb devices

# Install the universal APK
adb install -r build/app/outputs/flutter-apk/app-release.apk

# The -r flag replaces the existing app if already installed
```

---

## 🔑 Enable USB Debugging (if not done yet)

On your Android phone:
1. Go to **Settings** → **About Phone**
2. Tap **Build Number** 7 times (enables Developer Options)
3. Go back to **Settings** → **Developer Options**
4. Enable **USB Debugging**
5. Connect to PC and accept the "Allow USB Debugging" prompt

---

## ✨ New Features in This Build

### 🎨 Custom Company Logo
- **Location:** Configuración → Apariencia → Logo de la Empresa
- **Upload your logo** to replace the default header
- **Clickable logo** takes you to the dashboard
- **Remove anytime** to revert to default

### How It Works:
1. Open the app
2. Go to **Settings** (gear icon)
3. Tap **Apariencia**
4. Tap **Logo de la Empresa**
5. Upload your bikeshop's logo
6. It appears in the header immediately!

---

## 🐛 Troubleshooting

### "App not installed" error:
- Make sure you have enough storage space
- Uninstall the old version first if installation fails
- Try the universal APK instead of split APKs

### "Parse error" or "Invalid APK":
- Re-download/re-copy the APK file
- Make sure the file wasn't corrupted during transfer
- Try a different APK variant

### USB not recognized:
- Install your phone's USB drivers
- Try a different USB cable
- Enable "File Transfer" mode (not just "Charging")

### ADB not found:
```powershell
# Install ADB via Chocolatey
choco install adb

# Or download Android Platform Tools manually
# https://developer.android.com/studio/releases/platform-tools
```

---

## 📊 Build Information

- **Build Date:** October 14, 2025
- **Build Type:** Release (optimized, signed)
- **Flutter Version:** Latest stable
- **Minimum Android Version:** Android 5.0 (API 21)
- **Target Android Version:** Android 14 (API 34)

---

## 🚀 Quick Install Command

If you have ADB installed and your phone connected:

```powershell
adb install -r "C:\dev\ProjectVinabike\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
```

Replace `app-arm64-v8a-release.apk` with `app-release.apk` if you prefer the universal version.

---

## 📱 After Installation

1. **Launch the app** from your home screen
2. **Log in** with your credentials
3. **Test the new logo feature:**
   - Go to Settings → Apariencia
   - Upload your company logo
   - See it appear in the header
   - Tap it to navigate home!

---

## 💡 Tips

- **Backup first:** Export your data before updating (Settings → Sistema → Respaldo de Datos)
- **WiFi upload:** Make sure you're on WiFi when uploading your logo (faster, no mobile data usage)
- **Logo size:** For best results, use a logo with transparent background (PNG) or white background
- **Recommended dimensions:** 300x100 to 600x200 pixels for optimal display

---

Enjoy your personalized Vinabike ERP! 🚴‍♂️
