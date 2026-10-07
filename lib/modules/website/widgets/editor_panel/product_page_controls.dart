part of '../website_editor_panel.dart';

/// The inspector of one section of the product page: the template every
/// product page draws (approved proposal, 2026-10-06: «Ficha de producto ·
/// una plantilla»). Every control stages into the editor's draft, saved by
/// «Guardar» with the rest of the site; the product's own data is edited in
/// Inventario.
class _ProductPageSectionControls extends StatelessWidget {
  const _ProductPageSectionControls({
    super.key,
    required this.provider,
    required this.target,
    this.showHeader = true,
  });

  final WebsiteEditModeProvider provider;
  final WebsiteProductSectionTarget target;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final value = provider.effectiveProductPageTemplate;
    final canvas = provider.productCanvas;
    void stage(WebsiteProductPageTemplate next) =>
        provider.stageProductPageTemplate(next);

    final children = switch (target.section) {
      WebsiteProductPageSection.buy => _buy(context, value, canvas, stage),
      WebsiteProductPageSection.sheet => _sheet(value, canvas, stage),
      WebsiteProductPageSection.related => _related(value, canvas, stage),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 10),
            child: Row(
              children: [
                Tooltip(
                  message: 'Volver a las secciones',
                  child: InkWell(
                    key: const ValueKey('product-section-back'),
                    onTap: () => provider.selectBlock(null),
                    borderRadius: BorderRadius.circular(6),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: 40, minWidth: 40),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back_rounded,
                              size: 16,
                              color: Colors.white60,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Ficha de producto',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Colors.white38,
                  ),
                ),
                Expanded(
                  child: Text(
                    target.section.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
        ],
        Expanded(
          child: ListView(
            key: PageStorageKey<String>(
              'website_product_inspector_${target.selectionId}',
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              const _ProductTemplateScope(),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buy(
    BuildContext context,
    WebsiteProductPageTemplate value,
    WebsiteProductCanvasContext? canvas,
    ValueChanged<WebsiteProductPageTemplate> stage,
  ) {
    String site(String key) => provider.getEffectiveSiteSetting(key, '');
    String savedSite(String key) {
      try {
        return context.read<WebsiteService>().getSetting(key, '').trim();
      } catch (_) {
        return '';
      }
    }

    final address = savedSite('contact_address').replaceAll('\n', ', ');
    return [
      _CollapsibleSection(
        title: 'Fotos',
        icon: Icons.photo_library_outlined,
        children: [
          VbSegmented<WebsiteProductPhotoSide>(
            groupLabel: 'Fotos en el escritorio',
            value: value.photoSide,
            options: [
              for (final side in WebsiteProductPhotoSide.values)
                VbSegmentedOption(value: side, label: side.label),
            ],
            onChanged: (side) => stage(value.copyWith(photoSide: side)),
          ),
          const _CatalogHelp(
            'En el teléfono las fotos van siempre arriba, y la compra debajo.',
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Precio',
        icon: Icons.sell_outlined,
        children: [
          _EditorTextField(
            key: const ValueKey('product-tax-note'),
            label: 'Nota bajo el precio',
            value: value.taxNote,
            hint: 'Vacía, no se muestra',
            onChanged: (text) => stage(value.copyWith(taxNote: text)),
          ),
          const SizedBox(height: 4),
          _EditorToggle(
            key: const ValueKey('product-show-highlights'),
            label: 'Datos clave junto al precio',
            value: value.showHighlights,
            onChanged: (show) => stage(value.copyWith(showHighlights: show)),
          ),
          _CatalogHelp(
            canvas == null
                ? 'Los que dicen más de cada producto, de su ficha técnica.'
                : canvas.highlightCount == 0
                    ? '${canvas.productName} no tiene datos clave: se muestran '
                        'en los productos con ficha técnica.'
                    : '${canvas.highlightCount} en ${canvas.productName}, de '
                        'su ficha técnica.',
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Botones',
        icon: Icons.shopping_cart_outlined,
        children: [
          _EditorTextField(
            key: const ValueKey('product-add-label'),
            label: 'Botón para agregar al carrito',
            value: value.addToCartLabel,
            hint: WebsiteProductPageTemplate.defaultAddToCartLabel,
            onChanged: (text) => stage(value.copyWith(addToCartLabel: text)),
          ),
          const SizedBox(height: 4),
          _EditorToggle(
            key: const ValueKey('product-show-buy-now'),
            label: 'Botón para comprar de inmediato',
            value: value.showBuyNow,
            onChanged: (show) => stage(value.copyWith(showBuyNow: show)),
          ),
          if (value.showBuyNow)
            _EditorTextField(
              key: const ValueKey('product-buy-now-label'),
              label: 'Su texto',
              value: value.buyNowLabel,
              hint: WebsiteProductPageTemplate.defaultBuyNowLabel,
              onChanged: (text) => stage(value.copyWith(buyNowLabel: text)),
            ),
          const _CatalogHelp(
            'Agotado, la ficha dice «No disponible» en lugar de los botones.',
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Despacho y retiro',
        icon: Icons.local_shipping_outlined,
        initiallyExpanded: false,
        children: [
          _EditorToggle(
            key: const ValueKey('product-show-promises'),
            label: 'Mostrar despacho y retiro',
            value: value.showPromises,
            onChanged: (show) => stage(value.copyWith(showPromises: show)),
          ),
          if (value.showPromises) ...[
            const SizedBox(height: 8),
            _EditorTextField(
              key: const ValueKey('product-shipping-title'),
              label: 'Despacho: título',
              value: site('shipping_promise_title'),
              hint: 'Despacho a domicilio',
              onChanged: (text) =>
                  provider.updateSiteSetting('shipping_promise_title', text),
            ),
            const SizedBox(height: 12),
            _EditorTextField(
              key: const ValueKey('product-shipping-detail'),
              label: 'Despacho: detalle',
              value: site('shipping_promise_detail'),
              hint: 'Vacío: el envío más barato del checkout',
              maxLines: 2,
              onChanged: (text) =>
                  provider.updateSiteSetting('shipping_promise_detail', text),
            ),
            const SizedBox(height: 12),
            _EditorTextField(
              key: const ValueKey('product-pickup-detail'),
              label: 'Retiro en tienda',
              value: site('pickup_promise_detail'),
              hint: address.isEmpty ? 'La dirección de la tienda' : address,
              maxLines: 2,
              onChanged: (text) =>
                  provider.updateSiteSetting('pickup_promise_detail', text),
            ),
            const _CatalogHelp(
              'Son del sitio: los mismos textos en todas las fichas. Vacío, el '
              'retiro dice la dirección de la tienda.',
            ),
          ],
        ],
      ),
      _ProductSourceNote(provider: provider, canvas: canvas),
    ];
  }

  List<Widget> _sheet(
    WebsiteProductPageTemplate value,
    WebsiteProductCanvasContext? canvas,
    ValueChanged<WebsiteProductPageTemplate> stage,
  ) {
    final technical = canvas?.technical ?? true;
    return [
      _CollapsibleSection(
        title: 'Título',
        icon: Icons.title_rounded,
        children: [
          const _CatalogHelp('También se escribe directo en la página.'),
          _EditorTextField(
            key: const ValueKey('product-sheet-title'),
            label: 'Título de la sección',
            value: value.sheetTitle,
            hint: 'Ficha técnica, o Detalles del producto si no tiene datos',
            onChanged: (text) => stage(value.copyWith(sheetTitle: text)),
          ),
          const SizedBox(height: 4),
          _EditorToggle(
            key: const ValueKey('product-show-origin'),
            label: 'Nota de dónde salen los datos',
            value: value.showOriginNote,
            onChanged: (show) => stage(value.copyWith(showOriginNote: show)),
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Tarjeta de ayuda',
        icon: Icons.support_agent_outlined,
        children: [
          _EditorToggle(
            key: const ValueKey('product-show-help'),
            label: 'Mostrar la tarjeta junto a la ficha',
            value: value.showHelp,
            onChanged: (show) => stage(value.copyWith(showHelp: show)),
          ),
          if (value.showHelp) ...[
            const SizedBox(height: 8),
            _EditorTextField(
              key: const ValueKey('product-help-title'),
              label: 'Pregunta',
              value: value.helpTitle,
              hint: value
                  .copyWith(helpTitle: '')
                  .resolvedHelpTitle(technical: technical),
              onChanged: (text) => stage(value.copyWith(helpTitle: text)),
            ),
            const SizedBox(height: 12),
            _EditorTextField(
              key: const ValueKey('product-help-text'),
              label: 'Texto',
              value: value.helpText,
              hint: value
                  .copyWith(helpText: '')
                  .resolvedHelpText(technical: technical),
              maxLines: 3,
              onChanged: (text) => stage(value.copyWith(helpText: text)),
            ),
            const _CatalogHelp(
              'Vacíos, dicen lo suyo según el producto: con ficha técnica '
              'pregunta por la bicicleta; sin ella, si hay dudas. El botón '
              'abre WhatsApp con el producto.',
            ),
          ],
        ],
      ),
      _ProductSourceNote(provider: provider, canvas: canvas),
    ];
  }

  List<Widget> _related(
    WebsiteProductPageTemplate value,
    WebsiteProductCanvasContext? canvas,
    ValueChanged<WebsiteProductPageTemplate> stage,
  ) {
    return [
      _CollapsibleSection(
        title: 'Relacionados',
        icon: Icons.grid_view_rounded,
        children: [
          _EditorToggle(
            key: const ValueKey('product-show-related'),
            label: 'Mostrar productos relacionados',
            value: value.showRelated,
            onChanged: (show) => stage(value.copyWith(showRelated: show)),
          ),
          if (value.showRelated) ...[
            const SizedBox(height: 8),
            _EditorTextField(
              key: const ValueKey('product-related-title'),
              label: 'Título',
              value: value.relatedTitle,
              hint: WebsiteProductPageTemplate.defaultRelatedTitle,
              onChanged: (text) => stage(value.copyWith(relatedTitle: text)),
            ),
          ],
          _CatalogHelp(
            canvas == null || canvas.relatedCount == 0
                ? 'Salen de la misma categoría, hasta cuatro.'
                : '${canvas.relatedCount} de la misma categoría que '
                    '${canvas.productName}.',
          ),
        ],
      ),
    ];
  }
}

/// Above every product-page section: the page is one template for every
/// product, and the product itself is not edited here.
class _ProductTemplateScope extends StatelessWidget {
  const _ProductTemplateScope();

  @override
  Widget build(BuildContext context) {
    final accent = websiteEditorAccent(context);
    return Container(
      key: const ValueKey('product-template-scope'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.copy_all_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Plantilla · cambia todas las fichas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Cada producto se ve con este diseño. Lo que cambies aquí cambia '
            'en la página de todos.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// «Lo que viene del catálogo» on a product page: the product drawn is an
/// example; its name, price, photos, stock and sheet are edited in Inventario.
class _ProductSourceNote extends StatelessWidget {
  const _ProductSourceNote({required this.provider, required this.canvas});

  final WebsiteEditModeProvider provider;
  final WebsiteProductCanvasContext? canvas;

  @override
  Widget build(BuildContext context) {
    final name = canvas?.productName;
    final noun = canvas?.service == true ? 'servicio' : 'producto';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _CatalogSourceNote(
        provider: provider,
        text: name == null
            ? 'El nombre, el precio, las fotos, el stock y la ficha técnica de '
                'cada $noun se cambian en Inventario.'
            : 'Se ve con $name de ejemplo. Su nombre, precio, fotos, stock y '
                'ficha técnica se cambian en Inventario, no aquí.',
      ),
    );
  }
}
