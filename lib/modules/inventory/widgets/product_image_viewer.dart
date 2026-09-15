import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_surface_icon_button.dart';

/// Visor grande de las imágenes de un producto.
///
/// Se abre desde la imagen del panel de detalle de Productos. Muestra una
/// imagen a la vez con zoom y arrastre, pasa de una a otra con las flechas del
/// teclado o los botones laterales, y ofrece las miniaturas abajo cuando el
/// producto tiene más de una. El catálogo sigue visible detrás del velo.
///
/// La envoltura del diálogo (insets, ancho/alto máximos y el radio 12 del
/// recorte) es la misma que usan Archivos y el comparador de OCR para su vista
/// previa grande. `GUÍA GENERAL` no publica un visor de imágenes, así que ese
/// envoltorio se hereda del código existente y no de un valor de Design; los
/// controles de adentro sí son `A-02` y el separador es el hairline `F-04`.
class ProductImageViewer extends StatefulWidget {
  const ProductImageViewer({
    super.key,
    required this.title,
    required this.imageUrls,
    this.initialIndex = 0,
  }) : assert(imageUrls.length > 0, 'El visor necesita al menos una imagen.');

  static const Key dialogKey = Key('product-image-viewer');
  static const Key closeKey = Key('product-image-viewer-close');
  static const Key previousKey = Key('product-image-viewer-previous');
  static const Key nextKey = Key('product-image-viewer-next');
  static Key thumbnailKey(int index) =>
      Key('product-image-viewer-thumb-$index');

  /// `F-04` · radio `tag 4` para la miniatura, como el thumbnail de la fila.
  static const double thumbnailSize = 40;
  static const double thumbnailRadius = 4;

  /// Envoltura heredada de la vista previa grande de Archivos (no es un valor
  /// de la guía; ver la nota de la clase).
  static const double envelopeRadius = 12;

  final String title;
  final List<String> imageUrls;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    if (imageUrls.isEmpty) return Future<void>.value();
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierLabel: 'Cerrar imagen',
      builder: (_) => ProductImageViewer(
        title: title,
        imageUrls: imageUrls,
        initialIndex: initialIndex.clamp(0, imageUrls.length - 1),
      ),
    );
  }

  @override
  State<ProductImageViewer> createState() => _ProductImageViewerState();
}

class _ProductImageViewerState extends State<ProductImageViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasSeveral => widget.imageUrls.length > 1;

  void _show(int index) {
    if (index < 0 || index >= widget.imageUrls.length) return;
    _controller.jumpToPage(index);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _show(_index - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _show(_index + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalInset = screenSize.width < 760 ? 12.0 : 42.0;
    final verticalInset = screenSize.height < 720 ? 12.0 : 24.0;
    final dialogWidth = (screenSize.width - horizontalInset * 2)
        .clamp(320.0, 1180.0)
        .toDouble();
    final dialogHeight =
        (screenSize.height - verticalInset * 2).clamp(360.0, 920.0).toDouble();
    final counterStyle = GoogleFonts.ibmPlexMono(
      fontSize: theme.textTheme.bodySmall?.fontSize,
      color: roles.faintForeground,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return Dialog(
      key: ProductImageViewer.dialogKey,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      backgroundColor: Colors.transparent,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(ProductImageViewer.envelopeRadius),
            child: Material(
              color: scheme.surface,
              child: Column(
                children: [
                  // Cabecera: nombre + «n de N» + cerrar. Padding 12/18 (F-04).
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: roles.hairline)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_hasSeveral) ...[
                          const SizedBox(width: 12),
                          Text(
                            '${_index + 1} de ${widget.imageUrls.length}',
                            style: counterStyle,
                          ),
                        ],
                        const SizedBox(width: 12),
                        VbSurfaceIconButton(
                          buttonKey: ProductImageViewer.closeKey,
                          icon: Icons.close,
                          tooltip: 'Cerrar imagen',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: PageView.builder(
                            controller: _controller,
                            itemCount: widget.imageUrls.length,
                            onPageChanged: (index) =>
                                setState(() => _index = index),
                            itemBuilder: (context, index) {
                              final url = widget.imageUrls[index];
                              return Semantics(
                                image: true,
                                label: 'Imagen ${index + 1} de '
                                    '${widget.imageUrls.length}: ${widget.title}',
                                child: InteractiveViewer(
                                  key: ValueKey<String>('product-image-$url'),
                                  minScale: 1,
                                  maxScale: 6,
                                  // «Ver imagen grande»: la foto ocupa todo el
                                  // visor aunque el archivo sea chico; contain
                                  // conserva la proporción.
                                  child: SizedBox.expand(
                                    child: Image.network(
                                      url,
                                      fit: BoxFit.contain,
                                      loadingBuilder:
                                          (context, child, progress) {
                                        if (progress == null) return child;
                                        return const Center(
                                          child: SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        );
                                      },
                                      errorBuilder: (_, __, ___) =>
                                          _ImageUnavailable(theme: theme),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_hasSeveral) ...[
                          Positioned(
                            left: 12,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _FloatingControl(
                                child: VbSurfaceIconButton(
                                  buttonKey: ProductImageViewer.previousKey,
                                  icon: Icons.chevron_left,
                                  tooltip: 'Imagen anterior',
                                  onPressed: _index > 0
                                      ? () => _show(_index - 1)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 12,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _FloatingControl(
                                child: VbSurfaceIconButton(
                                  buttonKey: ProductImageViewer.nextKey,
                                  icon: Icons.chevron_right,
                                  tooltip: 'Imagen siguiente',
                                  onPressed:
                                      _index < widget.imageUrls.length - 1
                                          ? () => _show(_index + 1)
                                          : null,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_hasSeveral)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: roles.hairline)),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < widget.imageUrls.length; i++)
                              Padding(
                                padding: EdgeInsets.only(
                                  right:
                                      i == widget.imageUrls.length - 1 ? 0 : 8,
                                ),
                                child: ProductImageThumbnail(
                                  key: ProductImageViewer.thumbnailKey(i),
                                  imageUrl: widget.imageUrls[i],
                                  selected: i == _index,
                                  semanticLabel: 'Ver imagen ${i + 1}',
                                  onTap: () => _show(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Miniatura cuadrada de 40 con radio `tag 4`; seleccionada con el borde de
/// acento (`accentBorder`), sin relleno de color.
class ProductImageThumbnail extends StatelessWidget {
  const ProductImageThumbnail({
    super.key,
    required this.imageUrl,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final String imageUrl;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ProductImageViewer.thumbnailRadius),
        child: Container(
          width: ProductImageViewer.thumbnailSize,
          height: ProductImageViewer.thumbnailSize,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius:
                BorderRadius.circular(ProductImageViewer.thumbnailRadius),
            border: Border.all(
              color: selected ? roles.accentBorder : roles.hairline,
              // F-04 · trazo hairline 1 · check 1.5: la selección usa el 1.5.
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.broken_image_outlined,
              size: 16,
              color: roles.faintForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingControl extends StatelessWidget {
  const _FloatingControl({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    // El control flota sobre la imagen: una superficie propia con hairline para
    // que el glifo se lea sobre cualquier foto (F-05: sin sombra nueva).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(VbSurfaceIconButton.radius),
        border: Border.all(color: roles.hairline),
      ),
      child: child,
    );
  }
}

class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(
          'No se pudo cargar la imagen',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
