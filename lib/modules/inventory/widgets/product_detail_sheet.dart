import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/inventory_models.dart';
import '../services/inventory_service.dart' as inventory_services;
import '../utils/product_set_inventory_projection.dart';
import 'product_detail_pane.dart';
import 'product_movements_tab.dart';

/// Shows the canonical product detail pane — the same `ProductDetailPane` the
/// inventory list docks on its right — as a sheet over a host that is not the
/// inventory list: a purchase or sales line that wants to know what it is
/// buying or selling without leaving its document.
///
/// The sheet loads the record itself from the product id: the hosts that use
/// it hold the shared preview model, not the inventory module's, so the id is
/// the only thing both agree on. An empty id has no page to show and opens
/// nothing.
Future<void> showProductDetailSheet({
  required BuildContext context,
  required String productId,
  required VoidCallback onEdit,
}) {
  final id = productId.trim();
  if (id.isEmpty) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar detalles del producto',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final width = math.min(
        ProductDetailSheet.width,
        MediaQuery.sizeOf(dialogContext).width * 0.92,
      );
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: ProductDetailSheet(
            productId: id,
            onClose: () => Navigator.of(dialogContext).pop(),
            onEdit: () {
              Navigator.of(dialogContext).pop();
              onEdit();
            },
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      );
    },
  );
}

class ProductDetailSheet extends StatefulWidget {
  const ProductDetailSheet({
    super.key,
    required this.productId,
    required this.onClose,
    required this.onEdit,
  });

  /// Same default width as the inventory list's detail pane.
  static const double width = 520;

  static const Key sheetKey = Key('product-detail-sheet');

  final String productId;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
  Product? _record;
  bool _loading = true;
  bool _failed = false;
  ProductSetAvailabilityProjection? _setAvailability;
  Map<String, int> _quantityInSetByComponentId = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  inventory_services.InventoryService? _inventory() {
    try {
      return context.read<inventory_services.InventoryService>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _load() async {
    final inventory = _inventory();
    Product? record;
    try {
      record = await inventory?.getProductById(widget.productId);
    } catch (_) {
      record = null;
    }
    if (!mounted) return;
    if (record == null || inventory == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }

    ProductSetAvailabilityProjection? availability;
    var quantities = const <String, int>{};
    if (record.isSet) {
      try {
        final composition =
            await inventory.getProductSetComposition(widget.productId);
        final components = await Future.wait(
          composition.components
              .map((component) => inventory.getProductById(component.id)),
        );
        quantities = {
          for (final component in composition.components)
            component.id: component.quantityInSet,
        };
        availability = projectProductSetAvailability(
          setProduct: record,
          allProducts: components.whereType<Product>(),
          quantityInSetByComponentId: quantities,
        );
      } catch (_) {
        // The pane states «Juego sin componentes» when it cannot know.
      }
    }
    if (!mounted) return;
    setState(() {
      _record = record;
      _loading = false;
      _setAvailability = availability;
      _quantityInSetByComponentId = quantities;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = _record;
    if (record == null) {
      return Material(
        key: ProductDetailSheet.sheetKey,
        color: theme.colorScheme.surface,
        child: _SheetPlaceholder(
          loading: _loading && !_failed,
          onClose: widget.onClose,
        ),
      );
    }
    final id = record.id?.trim() ?? '';
    return Material(
      key: ProductDetailSheet.sheetKey,
      color: theme.colorScheme.surface,
      child: ProductDetailPane(
        product: record,
        fullRecord: record,
        isLoadingFullRecord: false,
        isServicesScope: record.isService,
        effectiveStock: record.isSet
            ? (_setAvailability?.completeSetsAvailable ?? 0)
            : record.inventoryQty,
        setAvailability: _setAvailability,
        quantityInSetByComponentId: _quantityInSetByComponentId,
        onClose: widget.onClose,
        onEdit: widget.onEdit,
        movementsBuilder: record.isService || id.isEmpty
            ? null
            : (context) => ProductMovementsTab(productId: id),
      ),
    );
  }
}

/// What the sheet shows before the record arrives, or when it never does.
class _SheetPlaceholder extends StatelessWidget {
  const _SheetPlaceholder({required this.loading, required this.onClose});

  final bool loading;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: roles.hairline)),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: IconButton(
                key: ProductDetailPane.closeKey,
                tooltip: 'Cerrar panel',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'No se pudo cargar el producto.',
                      style: theme.textTheme.bodyMedium,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
