# Veryfi OCR Integration

Complete guide for integrating Veryfi cloud OCR into the Bikeshop ERP.

## Quick Start

### 1. Get Veryfi Credentials

1. Sign up at [veryfi.com](https://www.veryfi.com/)
2. Create an application in the dashboard
3. Copy your **Client ID** and **API Key**

### 2. Configure Environment

Add credentials to your `.env` file:

```bash
VERYFI_CLIENT_ID=your_client_id_here
VERYFI_API_KEY=your_api_key_here
```

### 3. Test It

1. Open a Purchase Invoice form
2. Click the document scanner icon (📄)
3. Upload an invoice image or PDF
4. The widget will show "Veryfi Cloud OCR" if properly configured

---

## How It Works

### Auto-Detection

The `OCRUploadWidget` automatically detects if Veryfi is configured:

```dart
// Default behavior: auto-detect
OCRUploadWidget(
  onComplete: (invoice) => print(invoice),
)
// Uses Veryfi if configured, otherwise local OCR

// Force local OCR only
OCRUploadWidget(
  provider: OCRProvider.local,
  onComplete: (invoice) => print(invoice),
)

// Force Veryfi (will show error if not configured)
OCRUploadWidget(
  provider: OCRProvider.veryfi,
  onComplete: (invoice) => print(invoice),
)
```

### Provider Selection

| Provider | Accuracy | Speed | Offline | Cost |
|----------|----------|-------|---------|------|
| **Local (ML Kit)** | Good | Fast | ✅ Yes | Free |
| **Veryfi Cloud** | Excellent | Medium | ❌ No | 100 free/month |

---

## Files

| File | Purpose |
|------|---------|
| `veryfi_service.dart` | HTTP client for Veryfi API |
| `veryfi_config_loader.dart` | Loads credentials from .env |
| `veryfi_adapter.dart` | Converts Veryfi JSON to app models |
| `ocr_upload_widget.dart` | UI widget with auto-detection |

---

## Troubleshooting

### "Veryfi no está configurado"

Missing credentials in `.env`. Add:
```bash
VERYFI_CLIENT_ID=your_id
VERYFI_API_KEY=your_key
```

### "Error de autenticación (401)"

Invalid credentials. Check:
1. Client ID and API Key are correct
2. No extra spaces in .env values
3. API key hasn't expired

### "Acceso denegado (403)"

Monthly quota exceeded. Solutions:
1. Wait until next month (free tier: 100 docs)
2. Upgrade Veryfi plan
3. Use local OCR (`provider: OCRProvider.local`)

### Widget shows "OCR Local" even with credentials

Check:
1. `.env` file is in project root
2. App was hot-restarted after adding credentials
3. Run `flutter clean && flutter run` if still not working

---

## API Reference

### VeryfiService

```dart
final config = VeryfiConfigLoader.fromEnv();
final veryfi = VeryfiService(config);

// Process document
final result = await veryfi.parseInvoiceFromBytes(
  imageBytes,
  'invoice.jpg',
);

// Convert to app model
final invoice = VeryfiAdapter.toParsedInvoice(result);

// Cleanup
veryfi.dispose();
```

### VeryfiConfigLoader

```dart
// Load .env file
await VeryfiConfigLoader.loadEnv();

// Check if configured
if (VeryfiConfigLoader.isConfigured) {
  // Veryfi ready to use
}

// Get status message
print(VeryfiConfigLoader.statusMessage);
// "Veryfi: Configured ✓" or "Veryfi: Missing VERYFI_CLIENT_ID"
```

---

## Veryfi Response Fields

Key fields extracted by `VeryfiAdapter`:

| Field | Description |
|-------|-------------|
| `vendor.name` | Supplier name |
| `vendor_tax_number` | RUT (Chilean tax ID) |
| `invoice_number` | Invoice/folio number |
| `date` | Invoice date |
| `total` | Total amount |
| `line_items` | Product lines |

Full Veryfi API docs: https://docs.veryfi.com/

---

## Security Notes

- ⚠️ Never commit `.env` to source control
- 🔒 API keys should be kept secret
- 📊 Veryfi may store document images (check their privacy policy)
- 🛡️ Use local OCR for sensitive documents if needed
