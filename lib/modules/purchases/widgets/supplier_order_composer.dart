import 'package:flutter/material.dart';

import '../models/purchase_order_document.dart';
import '../models/purchase_order_summary.dart';
import '../models/supplier_catalog.dart';
import 'purchase_order_document_preview.dart';
import 'purchase_visual_language.dart';
import 'supplier_workspace_view.dart';

/// **La ficha del proveedor y el pedido que se le está armando, juntos.**
///
/// Mientras el pedido está vacío, la ficha ocupa todo el ancho: una hoja en
/// blanco al lado no ayuda a nadie. Al agregar el primer producto el panel se
/// abre en dos —lista a la izquierda, documento a la derecha— con el papel
/// entrando desde el borde, y desde ahí cada cambio se ve en la hoja al
/// instante.
///
/// La hoja no se cierra sola al sacar la última línea: cerrarse de golpe
/// mientras el operador está trabajando esconde el resultado de lo que acaba de
/// hacer. Se cierra cuando él lo pide, o cuando el pedido se envía.
class SupplierOrderComposer extends StatelessWidget {
  const SupplierOrderComposer({
    super.key,
    required this.page,
    required this.document,
    required this.open,
    required this.busy,
    required this.savedOrderNumber,
    required this.highlightedProductId,
    required this.loadingMore,
    required this.searchController,
    required this.addedProductIds,
    this.highlightedProductIds,
    required this.onBack,
    required this.onSearch,
    required this.onLoadMore,
    required this.onToggleLine,
    required this.onOpenPortal,
    required this.onAddPhoto,
    required this.onRemoveLine,
    required this.onClearOrder,
    required this.onSaveDraft,
    required this.onOpenPdf,
    required this.onSendToSupplier,
    required this.onClosePreview,
    required this.messagePreview,
    required this.pdfPreview,
    required this.openOrders,
    required this.activeOrderId,
    required this.onResumeOrder,
    required this.basis,
    required this.onBasisChanged,
  });

  final PurchaseCostBasis basis;
  final ValueChanged<PurchaseCostBasis> onBasisChanged;

  final List<PurchaseOrderSummary> openOrders;
  final String? activeOrderId;
  final ValueChanged<PurchaseOrderSummary> onResumeOrder;

  /// El paso de enviar ocupa el mismo panel derecho: revisar el mensaje no
  /// saca al operador de donde estaba, y volver al pedido es un solo toque.
  final Widget? messagePreview;

  /// **El PDF se mira donde va a vivir, no en un diálogo del sistema.**
  /// `Printing.sharePdf` abría la hoja de compartir de macOS: el operador
  /// quería revisar el papel y le salía un menú de AirDrop.
  final Widget? pdfPreview;

  final SupplierCatalogPage page;
  final PurchaseOrderDocument document;
  final bool open;
  final bool busy;

  /// Cuando ya se guardó, el número deja de ser «borrador» y las órdenes
  /// cambian: guardar otra vez no es lo mismo que guardar la primera.
  final String? savedOrderNumber;

  final String? highlightedProductId;
  final bool loadingMore;
  final TextEditingController searchController;
  final Set<String> addedProductIds;

  final VoidCallback onBack;
  final ValueChanged<String> onSearch;
  final VoidCallback onLoadMore;
  final ValueChanged<SupplierCatalogItem> onToggleLine;
  final VoidCallback onOpenPortal;
  final VoidCallback onAddPhoto;
  final ValueChanged<String> onRemoveLine;
  final VoidCallback onClearOrder;
  final VoidCallback onSaveDraft;
  final VoidCallback onOpenPdf;
  final VoidCallback onSendToSupplier;

  /// Los productos que el juicio compartido acepta destacar como coincidencia.
  final Set<String>? highlightedProductIds;

  final VoidCallback onClosePreview;

  @override
  Widget build(BuildContext context) {
    final lista = SupplierWorkspaceView(
      page: page,
      loadingMore: loadingMore,
      searchController: searchController,
      addedProductIds: addedProductIds,
      highlightedProductIds: highlightedProductIds,
      onBack: onBack,
      onSearch: onSearch,
      onLoadMore: onLoadMore,
      onToggleLine: onToggleLine,
      onOpenPortal: onOpenPortal,
      onAddPhoto: onAddPhoto,
      openOrders: openOrders,
      activeOrderId: activeOrderId,
      onResumeOrder: onResumeOrder,
      basis: basis,
      onBasisChanged: onBasisChanged,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Bajo este ancho, dos columnas dejan ilegibles las dos. El documento
        // pasa a vivir debajo de la lista, con el mismo contenido y las mismas
        // órdenes: es la misma pantalla, no una versión recortada.
        final canSplit = constraints.maxWidth >= 940;
        if (!canSplit) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              lista,
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: open
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _Sheet(
                          document: document,
                          busy: busy,
                          savedOrderNumber: savedOrderNumber,
                          highlightedProductId: highlightedProductId,
                          height: 460,
                          messagePreview: messagePreview,
                          pdfPreview: pdfPreview,
                          onRemoveLine: onRemoveLine,
                          onClearOrder: onClearOrder,
                          onSaveDraft: onSaveDraft,
                          onOpenPdf: onOpenPdf,
                          onSendToSupplier: onSendToSupplier,
                          onClosePreview: onClosePreview,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        }
        final full = (constraints.maxWidth * 0.42).clamp(360.0, 560.0);
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: open ? 1 : 0),
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: lista),
                SizedBox(width: 18 * t),
                // El papel entra desde el borde **a su ancho definitivo**: si
                // se estirara desde cero, el documento se vería deformado toda
                // la animación.
                //
                // `Align` con `widthFactor` y no `OverflowBox`: éste hereda las
                // restricciones del padre y, dentro de un `ListView`, el alto
                // que hereda es infinito. El panel entero desaparecía y la app
                // quedaba dando vueltas en semántica.
                if (t > 0)
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: SizedBox(
                        width: full,
                        child: Opacity(
                          opacity: t,
                          child: _Sheet(
                            document: document,
                            busy: busy,
                            savedOrderNumber: savedOrderNumber,
                            highlightedProductId: highlightedProductId,
                            height: 560,
                            messagePreview: messagePreview,
                            pdfPreview: pdfPreview,
                            onRemoveLine: onRemoveLine,
                            onClearOrder: onClearOrder,
                            onSaveDraft: onSaveDraft,
                            onOpenPdf: onOpenPdf,
                            onSendToSupplier: onSendToSupplier,
                            onClosePreview: onClosePreview,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.document,
    required this.busy,
    required this.savedOrderNumber,
    required this.highlightedProductId,
    required this.height,
    required this.messagePreview,
    required this.pdfPreview,
    required this.onRemoveLine,
    required this.onClearOrder,
    required this.onSaveDraft,
    required this.onOpenPdf,
    required this.onSendToSupplier,
    required this.onClosePreview,
  });

  final PurchaseOrderDocument document;
  final bool busy;
  final String? savedOrderNumber;
  final String? highlightedProductId;
  final double height;
  final Widget? messagePreview;
  final Widget? pdfPreview;
  final ValueChanged<String> onRemoveLine;
  final VoidCallback onClearOrder;
  final VoidCallback onSaveDraft;
  final VoidCallback onOpenPdf;
  final VoidCallback onSendToSupplier;
  final VoidCallback onClosePreview;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final vacio = document.isEmpty;
    if (messagePreview != null) {
      return SizedBox(
        height: height + 92,
        child: messagePreview,
      );
    }
    if (pdfPreview != null) {
      return SizedBox(
        height: height + 92,
        child: pdfPreview,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                savedOrderNumber == null
                    ? 'Pedido en borrador'
                    : 'Pedido ${savedOrderNumber!}',
                style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
              ),
            ),
            Text(
              vacio
                  ? 'sin líneas'
                  : '${document.lines.length} '
                      '${document.lines.length == 1 ? 'línea' : 'líneas'} · '
                      '${document.unitCount} un',
              style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
            ),
            const SizedBox(width: 10),
            IconButton(
              key: const ValueKey('order-close-preview'),
              onPressed: onClosePreview,
              icon: const Icon(Icons.close, size: 15),
              style: IconButton.styleFrom(
                minimumSize: Size.zero,
                maximumSize: const Size(24, 24),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: 'Cerrar la vista del pedido',
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: vacio
              ? Container(
                  decoration: BoxDecoration(
                    color: tokens.sunken,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.hair),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'El pedido quedó vacío. Agrega un producto de la lista y '
                    'vuelve a aparecer acá.',
                    textAlign: TextAlign.center,
                    style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
                  ),
                )
              : PurchaseOrderDocumentPreview(
                  document: document,
                  onRemoveLine: onRemoveLine,
                  highlightedProductId: highlightedProductId,
                ),
        ),
        const SizedBox(height: 10),
        // Las órdenes en el orden del trabajo: guardar antes de enviar, y
        // enviar sólo lo que ya está guardado. Mandar un papel que no existe en
        // la base deja al proveedor con un folio que nadie puede buscar.
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PurchasePrimaryButton(
              key: const ValueKey('order-save-draft'),
              label: busy
                  ? 'Guardando…'
                  : savedOrderNumber == null
                      ? 'Guardar borrador'
                      : 'Guardar cambios',
              onPressed: vacio || busy ? null : onSaveDraft,
            ),
            PurchaseInlineAction(
              key: const ValueKey('order-send'),
              label: 'Enviar al proveedor',
              onPressed: vacio || busy || savedOrderNumber == null
                  ? null
                  : onSendToSupplier,
            ),
            PurchaseInlineAction(
              key: const ValueKey('order-open-pdf'),
              label: 'Ver el PDF',
              onPressed: vacio || busy ? null : onOpenPdf,
            ),
            PurchaseInlineAction(
              key: const ValueKey('order-clear'),
              label: 'Vaciar',
              onPressed: vacio || busy ? null : onClearOrder,
            ),
          ],
        ),
        if (savedOrderNumber == null && !vacio)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              'Guárdalo antes de enviarlo: el proveedor necesita un número que '
              'exista para responder por él.',
              style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
            ),
          ),
      ],
    );
  }
}
