import 'package:flutter/material.dart';

import '../models/inventory_models.dart';
import '../pages/product_form_page.dart';

/// Presents the canonical product form without leaving the current workflow.
///
/// The dialog owns only the contextual presentation. Product loading,
/// validation, persistence, and save results remain owned by [ProductFormPage].
Future<bool?> showProductEditorDialog({
  required BuildContext context,
  required String productId,
  ProductType initialProductType = ProductType.product,
  ProductFormSection initialSection = ProductFormSection.general,
}) {
  return showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: 'Cerrar editor de producto',
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final compact = MediaQuery.sizeOf(dialogContext).width < 700;

      return SafeArea(
        minimum: EdgeInsets.all(compact ? 8 : 20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1480,
                  maxHeight: 940,
                ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Material(
                    key: const ValueKey('product-editor-dialog'),
                    color: Theme.of(context).colorScheme.surface,
                    surfaceTintColor: Colors.transparent,
                    elevation: 6,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(compact ? 10 : 14),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: ProductFormPage(
                      productId: productId,
                      showInDialog: true,
                      initialProductType: initialProductType,
                      lockProductType: true,
                      initialSection: initialSection,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
