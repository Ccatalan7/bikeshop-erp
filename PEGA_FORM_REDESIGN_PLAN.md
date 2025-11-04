# Pega Form Redesign - Implementation Plan

## Overview
Redesign `mechanic_job_form_page.dart` to match `invoice_form_page.dart` 2-column layout

## Layout Structure (Wide Screens >1180px)

### Left Column (Expanded, Scrollable)
1. **Detalle de la Pega** section card
   - Status dropdown
   - Priority dropdown
   - Dates (arrival, deadline, started, completed, delivered)
   - Diagnosis (multiline)
   - Work performed (multiline)
   - Notes (multiline)
   - Checkboxes (requires approval, warranty job)
   
2. **Productos y Servicios** section card
   - Product autocomplete with ad-hoc items
   - Table with columns:
     - # (index)
     - Producto/Servicio (name)
     - Cantidad (editable number)
     - **Precio Unit. (editable number)** ← NEW: Allow editing
     - Total (calculated)
     - Actions (delete, reorder arrows on hover)
   - Add labor button
   - Labor items mixed in same table with hours/rate instead of qty/price

### Right Column (Fixed 360px width, Scrollable)
1. **Cliente y Bicicleta** section card
   - Customer selector (disabled in edit mode)
   - Bike selector
   - "Nueva Bici" and "Gestionar Bicis" buttons
   - Display customer info (name, email, phone)
   - Display bike info (brand, model, year)

2. **Resumen de Costos** section card
   - Parts cost (subtotal of all parts)
   - Labor cost (subtotal of all labor)
   - Subtotal (parts + labor)
   - Discount (editable percentage or amount)
   - Tax/IVA (calculated 19%)
   - **Total** (bold, larger font)

3. **Factura Vinculada** section card (only if invoice_id != null)
   - Invoice number
   - Invoice status badge
   - Link button to view invoice
   - Creation date

## Key Changes

### 1. Make Prices Editable
Current: Unit price is read-only from product catalog
New: Unit price prefills from catalog but can be edited per line

### 2. Responsive Layout
- Wide (>1180px): 2 columns side-by-side
- Narrow (≤1180px): Single column stacked vertically

### 3. Visual Consistency
- Same section card styling as invoice form
- Same table styling (hover effects, borders, spacing)
- Same color scheme and typography
- Same button placement and hierarchy

## Implementation Steps

1. ✅ Read current structure and understand data models
2. Refactor `build()` method with LayoutBuilder
3. Create left column widgets (Detalle + Productos)
4. Create right column widgets (Cliente + Resumen + Factura)
5. Update parts table to allow price editing
6. Test responsive behavior
7. Test save/load with edited prices

## Files to Modify
- `lib/modules/bikeshop/pages/mechanic_job_form_page.dart` (main file)

## Testing Checklist
- [ ] Layout adapts on window resize
- [ ] Product price editing works and saves
- [ ] Labor items display correctly in table
- [ ] Cost calculations update in real-time
- [ ] Linked invoice section shows when invoice exists
- [ ] Form validation still works
- [ ] Save preserves edited prices
- [ ] No visual regressions on narrow screens
