# 📱 Bluetooth Barcode Scanner Integration

## Overview
The app now supports connecting to Bluetooth barcode scanners for fast product lookup and inventory management.

## Features
- 🔍 **Auto-scan** for nearby Bluetooth devices
- 🔗 **One-tap connection** to barcode scanners
- 📊 **Real-time scanning** with instant feedback
- 🔔 **Visual notifications** when codes are scanned
- 📋 **Last scanned code** display with copy function
- 🔄 **Auto-reconnect** on app restart (coming soon)

## Supported Devices
Any HID-compatible Bluetooth barcode scanner that emits keyboard input, including:
- Honeywell scanners
- Zebra scanners
- Generic Bluetooth barcode readers
- Bluetooth-enabled inventory scanners

## How to Use

### Setup
1. Navigate to **Settings** → **Dispositivos** → **Lector de Código de Barras**
2. Turn on your Bluetooth barcode scanner
3. Tap **"Buscar lectores Bluetooth"**
4. Select your device from the list
5. Tap **"Conectar"**

### Scanning
Once connected:
- Simply scan any barcode
- The code will appear automatically
- A green notification will show the scanned code
- The code is also displayed in the status card

### Integration Points
The scanner service can be integrated into:
- ✅ **Inventory management** - Quick product lookup
- ✅ **POS system** - Fast product addition to cart
- ✅ **Stock receiving** - Rapid inventory intake
- ✅ **Product editing** - Quick navigation to product details

## Technical Details

### Service Location
`lib/shared/services/bluetooth_scanner_service.dart`

### Key Methods
```dart
// Check permissions
await scannerService.checkPermissions();

// Scan for devices
await scannerService.startScan();

// Connect to device
await scannerService.connect(device);

// Listen to scanned barcodes
scannerService.barcodeStream.listen((barcode) {
  print('Scanned: $barcode');
});

// Disconnect
await scannerService.disconnect();
```

### Permissions
**Android:**
- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION`

**iOS:**
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`

## Installation Steps

1. **Add dependencies** (already done):
```yaml
dependencies:
  flutter_blue_plus: ^1.32.12
  permission_handler: ^11.3.1
```

2. **Install packages**:
```bash
flutter pub get
```

3. **For Android**: Permissions already added to `AndroidManifest.xml`

4. **For iOS**: Permissions already added to `Info.plist`

## Usage Example

### In Product Search
```dart
final scannerService = BluetoothScannerService();

// Listen for barcodes
scannerService.barcodeStream.listen((barcode) {
  // Search product by barcode
  searchProductByBarcode(barcode);
});
```

### In POS
```dart
scannerService.barcodeStream.listen((barcode) {
  // Add product to cart
  addProductToCart(barcode);
});
```

## Troubleshooting

### Scanner not appearing
- Ensure Bluetooth is enabled
- Make sure scanner is in pairing mode
- Grant location permissions (Android)
- Check scanner battery

### Connection fails
- Unpair device from system Bluetooth settings
- Restart scanner
- Try scanning again

### Codes not detected
- Check scanner is in HID/SPP mode
- Verify scanner sends newline/return after code
- Ensure scanner is properly configured

## Future Enhancements
- [ ] Auto-reconnect on app startup
- [ ] Multiple scanner support
- [ ] Scanner configuration settings
- [ ] Scan history log
- [ ] Custom scan triggers
- [ ] QR code support
- [ ] Batch scanning mode

## Notes
- Scanner must be in Bluetooth mode (not USB/wired)
- Some scanners require specific configuration
- Web platform not supported (Bluetooth unavailable)
- Desktop support varies by platform
