# 📱 SUPER SIMPLE SETUP - NO READING REQUIRED

## What You Get:
- ✅ Mobile APK ready to install
- ✅ **ZERO manual configuration** - scan QR and it auto-configures everything!

---

## Step 1: Install APK on Your Phone (1 minute)

The APK is here:
```
/Users/Claudio/Dev/vinabike_scanner/build/app/outputs/flutter-apk/app-release.apk
```

**Option A - USB Transfer:**
```bash
# Connect phone via USB, then:
adb install /Users/Claudio/Dev/vinabike_scanner/build/app/outputs/flutter-apk/app-release.apk
```

**Option B - Share File:**
- AirDrop the APK to your phone
- Or upload to Google Drive and download on phone
- Or WhatsApp it to yourself

---

## Step 2: Run Windows ERP (30 seconds)

```bash
cd /Users/Claudio/Dev/bikeshop-erp
flutter run -d macos  # or windows if you're on Windows
```

Then in the app:
1. **Configuración** (sidebar)
2. **Escáner Remoto (Celular)**
3. Click **"Iniciar"**

A QR code appears 📱

---

## Step 3: Pair & Scan (10 seconds)

1. Open **Vinabike Scanner** app on phone
2. Point camera at QR code on computer
3. **BOOM! Auto-configured!** 🎉
4. Now scan any barcode
5. Watch it appear on Windows instantly

---

## That's It!

No Supabase config to copy-paste.
No manual setup.
No markdown guides to read.

Just:
1. Install APK
2. Run ERP → show QR
3. Scan QR with phone
4. Start scanning barcodes

**Total time: 2 minutes max.** ⚡

---

## Troubleshooting (if needed)

**APK won't install?**
- Enable "Install from unknown sources" in Android settings

**Camera permission?**
- App will ask - just tap "Allow"

**QR won't scan?**
- Make sure it's bright enough
- Get closer to screen

**Scans not appearing?**
- Check phone has internet (WiFi or data)
- Reopen the app and scan QR again

---

**APK Location:**
`/Users/Claudio/Dev/vinabike_scanner/build/app/outputs/flutter-apk/app-release.apk`

**Transfer to phone and you're done!** 🚀
