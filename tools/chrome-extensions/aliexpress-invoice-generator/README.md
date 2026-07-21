# AliExpress Invoice Generator Chrome Extension

Manifest V3 Chrome extension for collecting every AliExpress purchase from a selected day and turning it into one OCR-friendly consolidated purchase invoice.

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

1. Open AliExpress `Account > Orders`.
2. Click the extension icon and stay in the `Factura` tab.
3. Choose the purchase day and click `Buscar compras`.
4. Review the detected orders and click `Crear factura para OCR`.
5. Save the generated document as PDF and upload it to the ERP purchase-invoice OCR.

## Bulk from the orders list

1. Open AliExpress `Account > Orders` and let the order list load.
2. Open the extension side panel, choose `Un día` (or `Un rango` when needed), set the date(s), and click `Buscar compras`.
3. Review the purchases and click `Crear factura para OCR`. One consolidated invoice is the default.
4. Manual extraction, JSON export and advanced settings live under `Más`; AI Vision is isolated in its own fallback tab.

## Settings

The side panel includes `Ajustes` for saved defaults:

- default date mode (`Rango` or `Dia exacto`)
- default range length in days
- default output mode (`Una factura por orden` or `Factura consolidada`)
- whether collected orders start selected
- whether selected orders are re-read from detail pages before JSON/PDF output
- maximum separate invoice tabs to open in one run

## Notes

- AliExpress changes its page markup frequently, so the extractor uses visible text, order-detail links and product-link heuristics. Version 0.4.6 keeps one shared `invoice.js` / `invoice.css` document contract for the Chrome invoice and the ERP PDF preview, including compact names, images, variant identity and the complete landed-cost table. It also rejects store IDs and message URLs as order details, collapses image/no-image observations into one product, and deduplicates orders again before consolidation. It prints a structured `[AE-DEBUG]` trace and retains the latest run in `chrome.storage.local` as `aliexpressInvoiceLastDebugRun`. Always review the detected orders before generating the PDF.
- Bulk collection reads the AliExpress orders list and automatically opens the `View orders` / load-more control while walking past the selected start date, so boundary dates and exact-day scans do not get cut off early. When generating invoices or exporting JSON, selected orders are opened in background detail tabs and re-extracted there so multi-product orders and images use the richer detail-page parser.
- The bulk panel has a progress bar for collection, detail enrichment, JSON export, PDF generation, and failures.
- Bulk progress is saved in extension storage and the long-running scan/generation flow runs from the persistent Chrome side panel. There is no popup workflow; the toolbar button opens the panel directly. Older Chrome builds may fall back to a normal extension tab only if the side panel API is unavailable.
- Consolidated bulk mode sums selected order totals as the source of truth, preserves known shipping/tax/discount values when available, and adds a clear adjustment line if AliExpress only exposes a grand total for some orders.
- If AliExpress changes a detail page and regular extraction misses rows, open the separate `AI Vision` tab, paste a Gemini API key, save it, scroll the purchased product rows into view, then click `Leer área visible`. This sends only that visible screenshot to Gemini Vision and merges the AI-read lines with product images/links the DOM extractor can still see.
- The Gemini key is stored locally in Chrome extension storage. The visible page screenshot is sent to Google only when you explicitly click `Leer área visible`.
- The generated invoice is formatted as CLP for the ERP OCR flow. If the AliExpress page is showing another currency, adjust the numeric amounts in the popup before generating the PDF.
- The supplier defaults to `AliExpress Marketplace`. Add a supplier Tax ID only if you have a real value. Do not invent a RUT just to satisfy OCR.
- The printable invoice follows the ERP purchase invoice PDF layout and keeps currency text minimal so OCR reads the clean peso amounts.

## Files

- `manifest.json` - Chrome extension manifest.
- `content.js` - Extracts visible AliExpress order data from the active tab.
- `background.js` - Opens the Chrome side panel from the extension toolbar button.
- `sidepanel.html`, `popup.css`, `popup.js` - Review/edit side panel app.
- `invoice.html`, `invoice.css`, `invoice.js` - Printable OCR invoice page.
