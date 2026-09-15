import 'package:flutter/material.dart';

import '../models/purchase_order_document.dart';
import 'purchase_visual_language.dart';

/// **El pedido como se va a ver, dibujado en vivo.**
///
/// No es una imagen del PDF. Rasterizar en cada tecla tarda cientos de
/// milisegundos y la hoja parpadea: el operador ve un archivo recargándose en
/// vez de un documento armándose. Acá el mismo [PurchaseOrderDocument] que
/// alimenta el PDF se dibuja con widgets, así que agregar una línea es una
/// animación y no una espera.
///
/// Y por eso es **interactivo**: cada línea de la hoja se puede sacar desde la
/// hoja misma. Obligar a volver a la lista para quitar algo que se está mirando
/// acá es justo lo que el dueño no quiere.
class PurchaseOrderDocumentPreview extends StatelessWidget {
  const PurchaseOrderDocumentPreview({
    super.key,
    required this.document,
    required this.onRemoveLine,
    required this.highlightedProductId,
  });

  final PurchaseOrderDocument document;
  final ValueChanged<String> onRemoveLine;

  /// La línea recién agregada. Se destaca un instante para que el ojo la
  /// encuentre en la hoja sin buscarla.
  final String? highlightedProductId;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        // La hoja es blanca en claro y en oscuro: es papel, y el proveedor lo
        // va a recibir así. Fingir un documento oscuro engañaría sobre lo que
        // se está por mandar.
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: DefaultTextStyle(
          style: PurchaseType.meta.copyWith(color: const Color(0xFF1A1A1A)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _head(),
              const SizedBox(height: 16),
              _parties(),
              const SizedBox(height: 16),
              _lines(),
              const SizedBox(height: 12),
              _totals(),
              if (document.paymentTerms != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Condiciones de pago: ${document.paymentTerms}',
                  style: PurchaseType.meta.copyWith(
                    color: const Color(0xFF444444),
                  ),
                ),
              ],
              if (document.unverifiedCostLines > 0) ...[
                const SizedBox(height: 12),
                Text(
                  document.unverifiedCostLines == 1
                      ? '1 línea lleva un precio de referencia interna, no uno '
                          'ya cotizado. Confirmar antes de despachar.'
                      : '${document.unverifiedCostLines} líneas llevan un '
                          'precio de referencia interna, no uno ya cotizado. '
                          'Confirmar antes de despachar.',
                  style: PurchaseType.meta.copyWith(
                    color: const Color(0xFF8A6D00),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _head() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            document.buyerName.toUpperCase(),
            style: PurchaseType.sectionTitle.copyWith(
              color: const Color(0xFF1B4C8C),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'PEDIDO',
              style: PurchaseType.label.copyWith(
                color: const Color(0xFF1A1A1A),
                fontSize: 11,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              document.isDraft
                  ? 'Borrador · sin número'
                  : '# ${document.orderNumber}',
              style: PurchaseType.meta.copyWith(
                color: const Color(0xFF666666),
              ),
            ),
            Text(
              document.issuedOn,
              style: PurchaseType.meta.copyWith(
                color: const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _parties() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _party('De', document.buyerName, [document.buyerCity]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _party('Para', document.supplierName, [
            document.supplierLegalName,
            document.supplierRut,
            document.supplierContact,
          ]),
        ),
      ],
    );
  }

  Widget _party(String role, String name, List<String?> details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          role.toUpperCase(),
          style: PurchaseType.label.copyWith(color: const Color(0xFF888888)),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          style: PurchaseType.rowTitle.copyWith(
            color: const Color(0xFF1A1A1A),
          ),
        ),
        for (final detail in details)
          if (detail != null)
            Text(
              detail,
              style: PurchaseType.meta.copyWith(
                color: const Color(0xFF666666),
              ),
            ),
      ],
    );
  }

  Widget _lines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFFEFEFEF),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Row(
            children: [
              Expanded(
                flex: 50,
                child: Text('PRODUCTO',
                    style: PurchaseType.label
                        .copyWith(color: const Color(0xFF555555))),
              ),
              Expanded(
                flex: 11,
                child: Text('CANT.',
                    textAlign: TextAlign.end,
                    style: PurchaseType.label
                        .copyWith(color: const Color(0xFF555555))),
              ),
              Expanded(
                flex: 18,
                child: Text('P. UNIT.',
                    textAlign: TextAlign.end,
                    style: PurchaseType.label
                        .copyWith(color: const Color(0xFF555555))),
              ),
              Expanded(
                flex: 21,
                child: Text('NETO',
                    textAlign: TextAlign.end,
                    style: PurchaseType.label
                        .copyWith(color: const Color(0xFF555555))),
              ),
              const SizedBox(width: 24),
            ],
          ),
        ),
        for (final line in document.lines)
          _DocumentLine(
            line: line,
            highlighted: line.productId == highlightedProductId,
            onRemove: () => onRemoveLine(line.productId),
          ),
      ],
    );
  }

  Widget _totals() {
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 220,
        child: Column(
          children: [
            _totalRow('Neto', document.netTotal),
            _totalRow('IVA 19%', document.ivaAmount),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(height: 1, color: Color(0xFFCCCCCC)),
            ),
            _totalRow('Total', document.total, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String amount, {bool bold = false}) {
    final style = (bold ? PurchaseType.rowTitle : PurchaseType.meta)
        .copyWith(color: const Color(0xFF1A1A1A));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          // Los totales cambian solos cuando entra o sale una línea. El número
          // se cruza en vez de saltar, para que se vea QUE cambió.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axis: Axis.horizontal,
                axisAlignment: 1,
                child: child,
              ),
            ),
            child: Text(
              amount,
              key: ValueKey('$label-$amount'),
              style: style.copyWith(fontFeatures: PurchaseType.tabular),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentLine extends StatefulWidget {
  const _DocumentLine({
    required this.line,
    required this.highlighted,
    required this.onRemove,
  });

  final PurchaseOrderDocumentLine line;
  final bool highlighted;
  final VoidCallback onRemove;

  @override
  State<_DocumentLine> createState() => _DocumentLineState();
}

class _DocumentLineState extends State<_DocumentLine> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: widget.highlighted
              ? const Color(0xFFDCEBFF)
              : _hovering
                  ? const Color(0xFFF6F6F6)
                  : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFE4E4E4)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.line.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PurchaseType.meta
                        .copyWith(color: const Color(0xFF1A1A1A)),
                  ),
                  if (widget.line.reference != null)
                    Text(
                      widget.line.reference!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PurchaseType.meta.copyWith(
                        color: const Color(0xFF888888),
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
            _amount(widget.line.quantity, 11),
            _amount(widget.line.unitCost, 18,
                warn: widget.line.costIsFromCatalog),
            _amount(widget.line.netAmount, 21),
            SizedBox(
              width: 24,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hovering ? 1 : 0,
                child: IconButton(
                  key: ValueKey('document-remove-${widget.line.productId}'),
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close, size: 13),
                  color: const Color(0xFF888888),
                  style: IconButton.styleFrom(
                    minimumSize: Size.zero,
                    maximumSize: const Size(24, 24),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  tooltip: 'Sacar ${widget.line.name} del pedido',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amount(String value, int flex, {bool warn = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PurchaseType.meta.copyWith(
          // Un precio que nadie pagó no se disfraza de precio pactado ni
          // siquiera en la hoja.
          color: warn ? const Color(0xFF8A6D00) : const Color(0xFF1A1A1A),
          fontFeatures: PurchaseType.tabular,
        ),
      ),
    );
  }
}
