# Tab State Preservation Guide

## Problem
When switching between tabs, pages reload and lose all state (scroll position, form inputs, filters, etc.)

## Solution: AutomaticKeepAliveClientMixin

Add this to ANY page where you want to preserve state when switching tabs.

### Step 1: Change StatelessWidget to StatefulWidget

```dart
// BEFORE
class ProductListPage extends StatelessWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ... your page content
  }
}

// AFTER
class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // IMPORTANT: Must call super.build()
    
    // ... your page content (same as before)
  }
}
```

### Step 2: Apply to All Important Pages

Add `AutomaticKeepAliveClientMixin` to:

- ✅ `/modules/sales/pages/invoice_list_page.dart`
- ✅ `/modules/inventory/pages/product_list_page.dart`
- ✅ `/modules/crm/pages/customer_list_page.dart`
- ✅ `/modules/purchases/pages/purchase_invoice_list_page.dart`
- ✅ `/modules/purchases/pages/smart_purchase_list_page.dart`
- ✅ `/modules/bikeshop/pages/pegas_table_page.dart`
- ✅ `/modules/hr/pages/employee_list_page.dart`
- ✅ `/modules/accounting/pages/account_list_page.dart`
- ✅ Any page with forms, filters, or user input

### What This Does

- ✅ Preserves scroll position
- ✅ Keeps form inputs filled
- ✅ Maintains filter selections
- ✅ Remembers expanded/collapsed sections
- ✅ Keeps loaded data in memory
- ✅ **Works perfectly with GoRouter tabs!**

### Example: Full Implementation

```dart
import 'package:flutter/material.dart';

class InvoiceListPage extends StatefulWidget {
  const InvoiceListPage({super.key});

  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; // This is the magic line!

  final TextEditingController _searchController = TextEditingController();
  List<Invoice> _invoices = [];
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    super.build(context); // MUST call this!
    
    return Scaffold(
      appBar: AppBar(title: const Text('Facturas')),
      body: Column(
        children: [
          // Search bar - will keep its text!
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(hintText: 'Buscar...'),
          ),
          
          // List - will keep scroll position!
          Expanded(
            child: ListView.builder(
              itemCount: _invoices.length,
              itemBuilder: (context, index) {
                return ListTile(title: Text(_invoices[index].number));
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
```

### Testing

1. Open a page in a tab (e.g., Products)
2. Scroll down the list
3. Type something in a search box
4. Switch to another tab
5. Switch back to Products tab
6. ✅ Scroll position preserved!
7. ✅ Search text still there!

### Notes

- Only use on pages that NEED state preservation (list pages, form pages)
- Don't use on simple static pages (increases memory usage)
- The `super.build(context)` call is REQUIRED at the start of build()
- Works with all Flutter widgets (TextFields, ListViews, etc.)

---

**This is the Flutter-recommended way to preserve state across navigation!**
