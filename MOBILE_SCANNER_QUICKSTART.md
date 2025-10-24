# 📱 Mobile Barcode Scanner - Quick Start

## 🎯 What is This?

Turn your **Android or iOS phone** into a **wireless barcode scanner** for your Windows ERP. No hardware purchase needed!

---

## ⚡ Super Quick Setup (5 minutes)

### Option 1: Automated Script (Recommended)

```bash
cd /Users/Claudio/Dev/bikeshop-erp
./setup_mobile_scanner.sh
```

The script will:
1. ✅ Check Flutter installation
2. ✅ Create new Flutter project
3. ✅ Copy template files
4. ✅ Install dependencies
5. ✅ Add platform permissions
6. ✅ Configure Supabase
7. ✅ Build APK (optional)

---

### Option 2: Manual Setup

```bash
# 1. Create project
cd ~/Dev
flutter create vinabike_scanner
cd vinabike_scanner

# 2. Copy template
cp -r ~/Dev/bikeshop-erp/mobile_scanner_app/lib/* lib/
cp ~/Dev/bikeshop-erp/mobile_scanner_app/pubspec.yaml pubspec.yaml

# 3. Install dependencies
flutter pub get

# 4. Edit lib/main.dart - add your Supabase credentials

# 5. Run
flutter run
```

---

## 📖 Full Documentation

- **`MOBILE_SCANNER_COMPLETE_GUIDE.md`** - Complete implementation guide with architecture, features, troubleshooting
- **`mobile_scanner_app/SETUP.md`** - Detailed step-by-step setup
- **`BARCODE_SCANNER_GUIDE.md`** - Comparison of all scanner types (USB, Bluetooth, Remote)

---

## 🚀 How to Use

### On Windows ERP:

1. Open **Configuración → Dispositivos → Escáner Remoto**
2. Click **"Iniciar"**
3. QR code appears on screen

### On Your Phone:

1. Launch **Vinabike Scanner** app
2. Scan the QR code
3. Start scanning barcodes!

Scans appear **instantly** on Windows ERP 🎉

---

## 📦 What You Get

### Windows ERP Features:
- ✅ Real-time scan receiving
- ✅ QR code pairing
- ✅ Recent scans list
- ✅ Multi-device support
- ✅ Module targeting

### Mobile App Features:
- ✅ Camera barcode scanning
- ✅ QR pairing
- ✅ Scan history
- ✅ Module selector
- ✅ Dark mode
- ✅ Haptic feedback

---

## 🎯 Use Cases

- **Inventory** - Walk around warehouse scanning products
- **POS** - Multiple cashiers with phones, one Windows terminal
- **Receiving** - Scan incoming shipments
- **Maintenance** - Scan parts in bike workshop
- **Low Budget** - No hardware purchase needed ($0)

---

## 🔧 Requirements

- **Windows ERP**: Running with Supabase configured
- **Phone**: Android 5.0+ or iOS 11.0+
- **Internet**: WiFi or mobile data
- **Flutter**: For building the mobile app (already installed)

---

## 💰 Cost Comparison

| Scanner Type | Cost | Setup Time | Devices |
|-------------|------|------------|---------|
| USB Scanner | $25-150 | 1 min | 1 |
| Bluetooth Scanner | $40-300 | 5 min | 1 |
| **Phone Scanner** | **$0** | **5 min** | **Unlimited** |

---

## 🐛 Troubleshooting

**Scans not appearing?**
- Check both devices have internet
- Verify Supabase credentials match
- Ensure Windows ERP is "listening"

**Camera not working?**
- Grant camera permissions
- Restart app
- Check good lighting

**See full troubleshooting guide in `MOBILE_SCANNER_COMPLETE_GUIDE.md`**

---

## 📱 Distribution

### Build APK:
```bash
cd vinabike_scanner
flutter build apk --release
```

APK location: `build/app/outputs/flutter-apk/app-release.apk`

### Install on Phone:
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Or share APK file via WhatsApp, Google Drive, etc.

---

## ✨ Key Benefits

| Feature | Benefit |
|---------|---------|
| **$0 Cost** | Use phones you already have |
| **Unlimited Range** | Works anywhere with internet |
| **Multi-Device** | Connect as many phones as needed |
| **Easy Setup** | QR code pairing in seconds |
| **Real-Time** | Instant transmission via Supabase |
| **Cross-Platform** | Android + iOS mobile, Windows desktop |

---

## 📞 Support

Questions? Check:
1. `MOBILE_SCANNER_COMPLETE_GUIDE.md` - Full technical guide
2. `BARCODE_SCANNER_GUIDE.md` - All scanner options
3. `mobile_scanner_app/SETUP.md` - Setup details

---

## 🎉 Ready to Start?

```bash
./setup_mobile_scanner.sh
```

That's it! Your wireless barcode scanner will be ready in **5 minutes**. 🚀

---

**Built for Vinabike ERP** 🚴‍♂️  
*Professional wireless scanning at $0 cost*
