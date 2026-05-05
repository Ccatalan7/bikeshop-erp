# AliExpress Invoice Generator Chrome Extension

Small Manifest V3 Chrome extension for turning a visible AliExpress order page into an OCR-friendly purchase invoice document.

The generated document is intentionally plain and text-heavy so the existing purchase invoice OCR flow can extract:

- supplier name
- order / invoice number
- date
- total
- subtotal and shipping when AliExpress exposes them
- line items with SKU, description, quantity, unit price, and line total
- line item images when the order page exposes usable product thumbnails

## Install locally

1. Open Chrome and go to `chrome://extensions`.
2. Enable `Developer mode`.
3. Click `Load unpacked`.
4. Select this folder:

   `tools/chrome-extensions/aliexpress-invoice-generator`

5. Pin `AliExpress Invoice Generator` from the Chrome extensions menu.

## Use

1. Open an AliExpress order detail or order history page.
2. Click the extension icon.
3. Click `Extraer`.
4. Review and correct the fields in the popup.
5. Click `Generar PDF`.
6. In the generated invoice tab, click `Imprimir / Guardar PDF` and choose `Save as PDF`.
7. Upload that PDF in the ERP purchase invoice OCR widget.

## Notes

- AliExpress changes its page markup frequently, so the extractor uses visible text and product-link heuristics. Always review the popup before generating the PDF.
- If AliExpress changes the HTML and regular extraction misses rows, use `AI OCR visible`: paste a Gemini API key, save it, scroll the purchased product rows into view, then click the AI button. This captures the visible page area, sends it to Gemini Vision, and merges the AI-read line items with any product images/links the DOM extractor can still see.
- The Gemini key is stored locally in Chrome extension storage. The visible page screenshot is sent to Google only when you click `AI OCR visible`.
- The generated invoice is formatted as CLP for the ERP OCR flow. If the AliExpress page is showing another currency, adjust the numeric amounts in the popup before generating the PDF.
- The supplier defaults to `AliExpress Marketplace`. Add a supplier Tax ID only if you have a real value. Do not invent a RUT just to satisfy OCR.
- The printable invoice follows the ERP purchase invoice PDF layout and keeps currency text minimal so OCR reads the clean peso amounts.

## Files

- `manifest.json` - Chrome extension manifest.
- `content.js` - Extracts visible AliExpress order data from the active tab.
- `popup.html`, `popup.css`, `popup.js` - Review/edit UI.
- `invoice.html`, `invoice.css`, `invoice.js` - Printable OCR invoice page.