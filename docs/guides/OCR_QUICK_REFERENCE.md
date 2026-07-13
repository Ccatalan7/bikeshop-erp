# 📸 OCR Quick Reference - For Developers

## 🚀 Quick Start

### 1. Add OCR to Any Form

```dart
import '../../../shared/widgets/ocr_upload_widget.dart';
import '../../../shared/services/invoice_parser_service.dart';

// Add button to header/toolbar
IconButton(
  onPressed: _openOCRScanner,
  icon: const Icon(Icons.document_scanner_outlined),
  tooltip: 'Escanear Documento',
)

// Handler method
Future<void> _openOCRScanner() async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24, right: 24, top: 24,
      ),
      child: OCRUploadWidget(
        documentType: OCRDocumentType.invoice, // or .receipt
        showPreview: true,
        onComplete: (parsedInvoice) {
          Navigator.of(context).pop();
          _applyOCRData(parsedInvoice);
        },
      ),
    ),
  );
}

// Apply extracted data
void _applyOCRData(ParsedInvoice parsedInvoice) {
  setState(() {
    if (parsedInvoice.invoiceNumber != null) {
      _invoiceNumberController.text = parsedInvoice.invoiceNumber!;
    }
    if (parsedInvoice.date != null) {
      _issueDate = parsedInvoice.date!;
    }
    if (parsedInvoice.total != null) {
      _totalController.text = parsedInvoice.total!.toStringAsFixed(0);
    }
    // ... apply other fields
  });
}
```

---

## 📦 Available Services

### OCRService - Text Extraction
```dart
import '../../../shared/services/ocr_service.dart';

// Extract text from image
final text = await OCRService().extractText('/path/to/image.jpg');

// Get structured data (blocks, lines, elements)
final recognizedText = await OCRService().processImage('/path/to/image.jpg');
for (var block in recognizedText.blocks) {
  print('Block: ${block.text}');
  for (var line in block.lines) {
    print('  Line: ${line.text}');
  }
}
```

### InvoiceParserService - Data Extraction
```dart
import '../../../shared/services/invoice_parser_service.dart';

final parser = InvoiceParserService();

// Parse full invoice
final invoice = parser.parseInvoice(recognizedText);
print('RUT: ${invoice.rut}');
print('Total: ${invoice.total}');

// Parse simple receipt
final receipt = parser.parseReceipt(recognizedText);
print('Vendor: ${receipt.supplierName}');
```

---

## 🎨 OCRUploadWidget Options

```dart
OCRUploadWidget(
  // Document type: invoice (full) or receipt (simple)
  documentType: OCRDocumentType.invoice, // or .receipt
  
  // Show preview before returning data
  showPreview: true,
  
  // Called when extraction successful and user confirms
  onComplete: (parsedInvoice) {
    // parsedInvoice.rut
    // parsedInvoice.invoiceNumber
    // parsedInvoice.date
    // parsedInvoice.total
    // parsedInvoice.supplierName
    // parsedInvoice.lineItems
  },
  
  // Called when OCR fails
  onError: (error) {
    // Show custom error message
  },
)
```

---

## 📋 ParsedInvoice Fields

```dart
class ParsedInvoice {
  final String? rut;              // "12.345.678-9"
  final String? invoiceNumber;    // "12345"
  final DateTime? date;           // DateTime(2025, 11, 9)
  final double? total;            // 119000.0
  final String? supplierName;     // "Comercial ABC Ltda."
  final List<ParsedLineItem> lineItems; // List of products
  final String rawText;           // Full extracted text
}

class ParsedLineItem {
  final String description;       // "Bicicleta MTB 29"
  final double? quantity;         // 2.0
  final double? unitPrice;        // 450000.0
  final double? total;            // 900000.0
}
```

---

## 🔍 Common Patterns

### Extract Supplier and Create if Missing
```dart
void _applyOCRData(ParsedInvoice parsedInvoice) {
  if (parsedInvoice.supplierName != null) {
    // Try to match existing supplier
    final matched = _supplierCache.firstWhere(
      (s) => s.name.toLowerCase().contains(
        parsedInvoice.supplierName!.toLowerCase(),
      ),
      orElse: () => null,
    );
    
    if (matched != null) {
      _selectedSupplier = matched;
    } else {
      // Create new supplier
      _createQuickSupplier(parsedInvoice.supplierName!);
    }
  }
}
```

### Match Products by Description
```dart
void _applyOCRData(ParsedInvoice parsedInvoice) {
  for (final item in parsedInvoice.lineItems) {
    final matchedProduct = _productCache.firstWhere(
      (p) => p.name.toLowerCase().contains(item.description.toLowerCase()),
      orElse: () => null,
    );
    
    if (matchedProduct != null) {
      _addLineItem(
        product: matchedProduct,
        quantity: item.quantity ?? 1,
        price: item.unitPrice ?? matchedProduct.cost,
      );
    }
  }
}
```

### Show Success Summary
```dart
void _applyOCRData(ParsedInvoice parsedInvoice) {
  setState(() {
    // Apply fields...
  });
  
  final extractedFields = <String>[];
  if (parsedInvoice.rut != null) extractedFields.add('RUT');
  if (parsedInvoice.invoiceNumber != null) extractedFields.add('N° Factura');
  if (parsedInvoice.date != null) extractedFields.add('Fecha');
  if (parsedInvoice.total != null) extractedFields.add('Total');
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('✅ Datos extraídos: ${extractedFields.join(', ')}'),
      backgroundColor: Colors.green,
    ),
  );
}
```

---

## 🐛 Error Handling

```dart
OCRUploadWidget(
  onComplete: (parsedInvoice) {
    // Check if critical fields are missing
    if (parsedInvoice.rut == null && 
        parsedInvoice.supplierName == null && 
        parsedInvoice.total == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No se pudieron extraer datos. Verifica la imagen.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Apply extracted data
    _applyOCRData(parsedInvoice);
  },
  onError: (error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ Error: $error'),
        backgroundColor: Colors.red,
      ),
    );
  },
)
```

---

## 🎯 Where to Use OCR

### Implemented
- ✅ **Purchase Invoice Form** (`purchase_invoice_form_page.dart`)
  - Extracts: RUT, invoice number, date, total, supplier, line items

### Future Modules
- **Expense Receipts Form** (when created)
  - Use `OCRDocumentType.receipt`
  - Extract: vendor name, amount, date
  
- **Sales Invoice Form** (optional)
  - Extract customer info from business cards
  - Extract product descriptions from supplier catalogs

- **Inventory Import** (batch)
  - Scan product labels/barcodes
  - Extract product specs from packaging

---

## 📱 Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Android | ✅ Working | On-device ML Kit |
| iOS | ✅ Working | On-device ML Kit |
| Web | ✅ Working | Firebase ML (requires internet) |
| Windows | ❌ Not supported | ML Kit limitation |
| macOS | ❌ Not supported | ML Kit limitation |
| Linux | ❌ Not supported | ML Kit limitation |

**Desktop Workaround:** Use mobile device to scan, then sync via cloud.

---

## ⚡ Performance Tips

```dart
// ✅ GOOD: Compress image before processing
final XFile? image = await ImagePicker().pickImage(
  source: ImageSource.camera,
  imageQuality: 85, // Compress to 85% quality
  maxWidth: 1920,   // Limit resolution
);

// ❌ BAD: Process full-resolution image (slow)
final XFile? image = await ImagePicker().pickImage(
  source: ImageSource.camera,
  // No compression = 5-10MB images = slow processing
);
```

---

## 🔗 Related Files

```
lib/
├── shared/
│   ├── services/
│   │   ├── ocr_service.dart              # Text extraction (ML Kit)
│   │   └── invoice_parser_service.dart   # Data parsing (regex)
│   └── widgets/
│       └── ocr_upload_widget.dart        # UI component (camera/gallery)
└── modules/purchases/pages/
    └── purchase_invoice_form_page.dart   # Example integration
```

---

**Need Help?** Check `OCR_IMPLEMENTATION_GUIDE.md` for detailed documentation.
