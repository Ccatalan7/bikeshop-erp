# 📱 Vinabike Scanner - Mobile Companion App

## 🎯 Overview

A lightweight Flutter mobile app that turns your phone into a wireless barcode scanner for the Vinabike ERP system running on Windows/Desktop.

## ✨ Features

- 📷 **Camera-based barcode scanning** using ML Kit
- 📡 **Real-time transmission** via Supabase Realtime
- 🔗 **QR code pairing** for instant setup
- 📊 **Scan history** with timestamps
- 🎯 **Module targeting** (POS, Inventory, Sales, etc.)
- 🌙 **Dark mode** support
- 🔋 **Battery efficient** with auto-pause

## 🚀 Quick Start

### 1. Setup

```bash
# Create the mobile scanner app
cd /Users/Claudio/Dev
flutter create vinabike_scanner
cd vinabike_scanner

# Add dependencies
flutter pub add mobile_scanner supabase_flutter qr_code_scanner shared_preferences uuid provider intl
```

### 2. Configure Supabase

Copy your Supabase credentials from the main ERP project:

```dart
// lib/main.dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',
  anonKey: 'YOUR_SUPABASE_ANON_KEY',
);
```

### 3. Run

```bash
flutter run
```

## 📱 How to Use

1. **Launch the app** on your phone
2. **Scan the QR code** displayed on your Windows ERP
3. **Start scanning** barcodes with the camera
4. **Scanned codes appear** instantly on your Windows ERP

## 🏗️ Architecture

```
Mobile App                  Supabase Realtime              Windows ERP
┌─────────────┐            ┌──────────────────┐           ┌──────────────┐
│ Camera      │            │                  │           │ Settings →   │
│ Scanner     │  ─scan─>   │ Channel:         │ ─listen─> │ Remote       │
│             │            │ barcode_scans:   │           │ Scanner      │
│ QR Code     │            │ {device_id}      │           │              │
│ Reader      │  <─pair──  │                  │ <─emit──  │ Auto-route   │
└─────────────┘            └──────────────────┘           └──────────────┘
```

## 🔧 Project Structure

```
lib/
├── main.dart                    # App entry point
├── models/
│   └── barcode_scan_event.dart  # Scan data model
├── services/
│   └── scanner_service.dart     # Supabase broadcast service
├── screens/
│   ├── pairing_screen.dart      # QR code pairing
│   └── scanner_screen.dart      # Main scanning interface
└── widgets/
    └── scan_history_widget.dart # Recent scans list
```

## 📦 Dependencies

- `mobile_scanner` - Camera-based barcode scanning
- `supabase_flutter` - Realtime communication
- `qr_code_scanner` - QR code pairing
- `shared_preferences` - Store paired device
- `uuid` - Generate device IDs
- `provider` - State management

## 🔐 Security

- Uses Supabase Row Level Security (RLS)
- Only paired devices can communicate
- Scans are transmitted, not stored
- No authentication required (device pairing only)

## 🎨 Customization

Edit `lib/main.dart` to customize:
- App theme (colors, fonts)
- Scan beep/vibration
- Target module selector
- Scan history limit

## 📊 Supported Barcode Formats

- QR Code
- EAN-8, EAN-13
- UPC-A, UPC-E
- Code 39, Code 93, Code 128
- ITF, Codabar
- PDF417, Aztec, Data Matrix

## 🐛 Troubleshooting

**Scans not appearing on Windows:**
- Check both devices are on the same Supabase project
- Verify QR code was scanned correctly
- Ensure Windows ERP "Remote Scanner" is listening

**Camera not working:**
- Grant camera permissions in phone settings
- Restart the app
- Try on a different device

**Battery drain:**
- App auto-pauses after 2 minutes of inactivity
- Close app when not in use
- Enable battery saver mode

## 📝 License

Same as Vinabike ERP - Internal use only

---

Built with ❤️ for Vinabike ERP
