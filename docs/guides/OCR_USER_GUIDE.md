# 📸 OCR Feature - User Guide

**How to Scan Purchase Invoices Automatically**

---

## 🎯 What is OCR?

**OCR (Optical Character Recognition)** automatically reads text from images. Instead of manually typing invoice data, just take a photo and the app extracts:

- ✅ Supplier name
- ✅ RUT (tax ID)
- ✅ Invoice number
- ✅ Date
- ✅ Total amount
- ✅ Product list

**Saves time:** 2 minutes of typing → 10 seconds of scanning!

---

## 📱 How to Use

### Step 1: Open New Purchase Invoice

Navigate to: **Compras** → **Facturas de Compra** → **+ Nueva Factura**

### Step 2: Click Document Scanner Button

Look for the **📄 document scanner icon** in the header toolbar (next to the QR code scanner).

```
┌──────────────────────────────────────────────────┐
│ ← Nueva factura de compra                       │
│                                                  │
│   [📄]  [QR]  [Guardar]                         │
│    ↑                                            │
│    └─ Click here!                              │
└──────────────────────────────────────────────────┘
```

### Step 3: Choose Image Source

A bottom sheet opens with two options:

```
┌──────────────────────────────────────┐
│     Escanear Factura                 │
│                                      │
│  Toma una foto o selecciona una     │
│  imagen para extraer los datos      │
│  automáticamente                     │
│                                      │
│     📷           🖼️                  │
│   Cámara      Galería                │
│                                      │
└──────────────────────────────────────┘
```

**Cámara:** Take a new photo with your device camera  
**Galería:** Select an existing image from your device

### Step 4: Take Photo / Select Image

**For Camera:**
1. Point camera at invoice
2. Make sure text is readable (not blurry)
3. Avoid shadows and glare
4. Take photo

**For Gallery:**
1. Browse your device photos
2. Select invoice image
3. Confirm selection

**💡 Tips for Best Results:**
- ✅ Good lighting
- ✅ Flat surface (avoid wrinkles)
- ✅ Straight angle (not tilted)
- ✅ Close enough to read text

### Step 5: Wait for Processing

The app analyzes the image and extracts text.

```
┌──────────────────────────────────────┐
│     🔄 Procesando imagen...          │
└──────────────────────────────────────┘
```

**Processing time:**
- Mobile: 1-2 seconds
- Web: 2-4 seconds

### Step 6: Review Extracted Data

The app shows a preview of what it found:

```
┌──────────────────────────────────────┐
│ ✅ Datos Extraídos                   │
│                                      │
│ Proveedor    Comercial ABC Ltda.    │
│ RUT          76.123.456-7           │
│ N° Factura   12345                  │
│ Fecha        09/11/2025             │
│ Total        $119.000               │
│ Productos    3                      │
│                                      │
│  [Reintentar]  [Usar Datos] ←       │
└──────────────────────────────────────┘
```

**Check the data:**
- ✅ Is the supplier name correct?
- ✅ Is the invoice number correct?
- ✅ Is the date correct?
- ✅ Is the total correct?

**Options:**
- **Reintentar:** Take another photo (if data is wrong)
- **Usar Datos:** Apply extracted data to form (if data looks good)

### Step 7: Form Auto-Fills

After clicking "Usar Datos", the form automatically populates:

```
┌──────────────────────────────────────────────────┐
│ Nueva factura de compra                          │
│                                                  │
│ Proveedor: [Comercial ABC Ltda.] ← Auto-filled  │
│ N° Factura: [12345] ← Auto-filled               │
│ Fecha: [09/11/2025] ← Auto-filled               │
│                                                  │
│ Productos:                                       │
│  1. Bicicleta MTB 29    2 × $450.000           │
│  2. Casco Protección    5 × $15.000            │
│                                                  │
│ Total: $119.000 ← Auto-calculated               │
│                                                  │
│ ✅ Datos extraídos: RUT, N° Factura, Fecha...  │
└──────────────────────────────────────────────────┘
```

### Step 8: Verify and Save

1. **Check** extracted fields are correct
2. **Edit** any incorrect data manually
3. **Add** missing information (notes, reference, etc.)
4. **Click** "Guardar" to save invoice

Done! 🎉

---

## ❓ Troubleshooting

### "No se pudo extraer texto de la imagen"

**Problem:** Image quality too poor for OCR  
**Solutions:**
- Retake photo with better lighting
- Hold phone steady (avoid blur)
- Try a closer shot
- Use flash if needed

### "Proveedor no encontrado"

**Problem:** Supplier not in database  
**Solutions:**
- Check extracted name (might be incomplete)
- Manually select supplier from dropdown
- Create new supplier with full name

### "Productos no detectados"

**Problem:** Product descriptions don't match inventory  
**Solutions:**
- Manually add products after OCR
- Update product names to match invoice terminology
- OCR still extracted total (use that)

### "Button doesn't work on Windows/macOS"

**Problem:** OCR not supported on desktop yet  
**Solutions:**
- Use mobile device (Android/iOS)
- Or use web browser on mobile
- Desktop support coming in future update

---

## 📋 Supported Invoice Formats

### ✅ Works Best With:
- **Chilean DTE** (Documentos Tributarios Electrónicos)
- **Printed invoices** (laser/inkjet printer)
- **Thermal receipts** (from POS systems)
- **PDF invoices** (screenshot or print)

### ⚠️ May Not Work Well With:
- **Handwritten invoices** (hard to read)
- **Very faded receipts** (thermal paper degrades)
- **Crumpled/torn documents** (missing text)
- **Non-Spanish text** (optimized for Latin script)

---

## 💡 Pro Tips

### For Fastest Scanning:
1. Keep invoice flat on table
2. Use good overhead lighting
3. Take photo straight-on (90° angle)
4. Crop to just the invoice (no background)

### For Best Accuracy:
1. Clean invoice (no coffee stains 😄)
2. High-contrast text (black on white)
3. Standard DTE format (most predictable)
4. Recent invoice (text not faded)

### For Bulk Invoices:
1. Scan multiple invoices one by one
2. Each scan takes ~10 seconds
3. Much faster than manual typing
4. Can process 10-15 invoices/minute

---

## 🎓 What Gets Extracted?

| Field | Accuracy | Example |
|-------|----------|---------|
| **RUT** | ⭐⭐⭐⭐ (85-95%) | `76.123.456-7` |
| **Invoice #** | ⭐⭐⭐⭐⭐ (90-95%) | `12345` |
| **Date** | ⭐⭐⭐⭐⭐ (90-95%) | `09/11/2025` |
| **Total** | ⭐⭐⭐⭐ (85-90%) | `$119.000` |
| **Supplier** | ⭐⭐⭐⭐ (80-85%) | `Comercial ABC` |
| **Products** | ⭐⭐⭐ (60-70%) | `Bicicleta MTB` |

**Note:** Even if some fields fail, OCR saves time vs manual entry!

---

## 🔮 Coming Soon

- **Expense Receipts:** Scan gas receipts, restaurant bills
- **Batch Scanning:** Upload 10+ invoices at once
- **Document Storage:** View original scan from invoice
- **Desktop Support:** Windows/macOS OCR

---

## 📞 Need Help?

If OCR isn't working as expected:
1. Check your internet connection (web only)
2. Update app to latest version
3. Try different lighting/angle
4. Contact support with screenshot

---

**🎉 Happy Scanning!**

OCR makes invoice entry 10x faster. Give it a try on your next purchase invoice!
