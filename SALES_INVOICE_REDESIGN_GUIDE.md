# Sales Invoice List Page - Complete Redesign (Zoho-Inspired)

## Overview
This document contains the complete redesigned `invoice_list_page.dart` based on Zoho Books interface patterns.

## Key Features

### 1. **Clean Table Layout with Resizable Columns**
- Compact row height (48px per row)
- Resizable column widths (drag handle on hover)
- Customizable column visibility
- Sortable headers

### 2. **Split-Pane View**
- Left: Shrunken table with same headers
- Right: PDF-style invoice preview
- Resizable divider between panes

### 3. **Summary Cards at Top**
- Total accounts receivable
- Overdue invoices
- Due in 30 days
- Overdue count

### 4. **Search and Filter**
- Real-time search (invoice number, customer name, RUT)
- Column visibility menu
- Refresh button

### 5. **Invoice Preview (Right Pane)**
- Action bar (Edit, Email, Share, PDF/Print, Close)
- PDF-style document with company info
- Line items table
- Totals breakdown
- "PAGADO" ribbon for paid invoices

## File Location
`lib/modules/sales/pages/invoice_list_page.dart`

## Dependencies Used
- `shared_preferences` - Column widths and pane width persistence
- `provider` - State management via SalesService
- Existing `Invoice` and `InvoiceItem` models
- `ChileanUtils` for currency and date formatting

## Code Structure

```dart
class _InvoiceListPageState extends State<InvoiceListPage> {
  // State variables
  - _searchTerm: String
  - _selectedInvoice: Invoice?
  - _listPaneWidth: double (resizable)
  - _columnWidths: Map<String, double> (resizable per column)
  - _visibleColumns: Map<String, bool> (customizable visibility)
  - _sortColumn: String
  - _sortAscending: bool
  
  // Main widgets
  - _buildFullListView() -> Full-width table when no selection
  - _buildSplitView() -> Split pane when invoice selected
  - _buildInvoiceTable() -> Table with headers and rows
  - _buildInvoicePreview() -> PDF-style invoice preview
  - _buildActionBar() -> Top actions (Edit, Email, etc.)
  - _buildInvoiceDocument() -> Invoice content (logo, customer, items, totals)
}
```

## Implementation Notes

### Resizable Columns
```dart
MouseRegion(
  cursor: SystemMouseCursors.resizeColumn,
  child: GestureDetector(
    onHorizontalDragUpdate: (details) {
      setState(() {
        _columnWidths[column] = (_columnWidths[column]! + details.delta.dx)
            .clamp(80.0, 400.0);
      });
    },
    onHorizontalDragEnd: (_) => _saveColumnWidth(column, _columnWidths[column]!),
  ),
)
```

### Resizable Split Pane
```dart
MouseRegion(
  cursor: SystemMouseCursors.resizeColumn,
  child: GestureDetector(
    onHorizontalDragUpdate: (details) {
      setState(() {
        _listPaneWidth = (_listPaneWidth + details.delta.dx)
            .clamp(_minListPaneWidth, _maxListPaneWidth);
      });
    },
  ),
)
```

### Invoice Selection
```dart
InkWell(
  onTap: () {
    setState(() {
      _selectedInvoice = isSelected ? null : invoice;
    });
  },
  // ... row content
)
```

## Mapping to Existing Models

### Invoice Model Fields Used:
- `id`, `invoiceNumber`, `customerName`, `customerRut`
- `date`, `dueDate`
- `status` (draft, sent, confirmed, paid, overdue, cancelled)
- `subtotal`, `ivaAmount`, `total`, `paidAmount`, `balance`
- `items: List<InvoiceItem>`

### InvoiceItem Model Fields Used:
- `productName`, `description`
- `quantity`, `unitPrice`, `discount`, `lineTotal`

## Status Chips Mapping
```dart
InvoiceStatus.draft -> Grey "Borrador"
InvoiceStatus.sent -> Blue "Enviada"
InvoiceStatus.confirmed -> Purple "Confirmada"
InvoiceStatus.paid -> Green "Pagado"
InvoiceStatus.overdue -> Red "Vencida"
InvoiceStatus.cancelled -> Red "Anulada"
```

## Differences from Zoho (Intentional)

###  ✅ What We Kept:
1. Clean table with resizable columns
2. Split-pane view on selection
3. PDF-style invoice preview
4. Action bar (Edit, Email, Share, PDF)
5. Summary cards at top
6. Search and column customization

### ❌ What We Skipped:
1. "View Zia's Insights" (no AI assistant in our app)
2. Complex dropdown filters (simple search is enough)
3. Batch operations UI (checkbox selection ready, but no batch actions yet)
4. Email templates (placeholder for future)
5. Multiple currency support (only CLP)

## Next Steps to Implement

1. **Navigation Integration**
   - Wire up "Nuevo" button to invoice creation page
   - Wire up "Editar" button to invoice editing page
   - Add proper routing with `go_router`

2. **PDF Export**
   - Implement actual PDF generation using `pdf` package
   - Use existing invoice document widget as template

3. **Email Integration**
   - Add email sending functionality
   - Use invoice preview HTML for email body

4. **Batch Operations**
   - Implement "select all" checkbox
   - Add bulk delete, bulk status change

5. **Advanced Filters**
   - Date range picker
   - Status filter dropdown
   - Customer filter

## Testing Checklist

- [ ] Table loads with invoices from SalesService
- [ ] Search filters invoices correctly
- [ ] Column resize persists after reload
- [ ] Pane width persists after reload
- [ ] Column visibility toggle works
- [ ] Sorting works for all columns
- [ ] Invoice selection opens preview
- [ ] Close button hides preview
- [ ] Summary cards calculate correctly
- [ ] Status chips show correct colors
- [ ] Line items display in preview

## Performance Considerations

- ✅ ListView.builder for virtualization
- ✅ Shared Preferences for persistence (async load on init)
- ✅ setState only for local UI state
- ✅ Provider watch for global invoice list
- ⚠️ No pagination yet (add if >100 invoices)

## Known Limitations

1. **Line items might not load** - The current Invoice.fromJson may not include items
   - FIX: Verify SalesService loads items with invoice
   - May need to fetch items separately in preview

2. **Navigation placeholders** - Buttons log to console instead of navigating
   - FIX: Add go_router paths for /sales/invoices/new and /sales/invoices/:id/edit

3. **No PDF/Email functionality** - Placeholders show snackbar
   - FIX: Implement in future iterations

## Deployment

Since the file is large (~1000 lines), you have two options:

### Option 1: Manual Copy-Paste
1. Back up current file
2. Delete old invoice_list_page.dart  
3. Create new file with code from FULL_CODE.md (create this next)

### Option 2: Incremental Replace
1. Use VSCode "Replace All in File"
2. Replace entire class definition section by section

---

## Full Code Ready to Deploy

See next artifact for complete dart file content...
