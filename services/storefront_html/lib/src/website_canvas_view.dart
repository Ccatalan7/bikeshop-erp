import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'css_values.dart';
import 'website_blocks_view.dart';

/// The width a canvas document's coordinates are written in when it does
/// not say (`CanvasBlock._kReferenceWidth`).
const canvasReferenceWidth = 1200.0;

/// The layer kinds [CanvasLayersView] draws. A product card or a product
/// gallery reads products the page does not load yet.
bool canvasLayerIsCovered(Map<String, dynamic> layer) {
  final kind = WebsiteCanvasLayerKind.fromRaw(layer['type']);
  return switch (kind) {
    WebsiteCanvasLayerKind.text ||
    WebsiteCanvasLayerKind.shape ||
    WebsiteCanvasLayerKind.button => true,
    WebsiteCanvasLayerKind.image => !_usesProductImage(layer),
    _ => false,
  };
}

/// Every layer of [document] the HTML storefront can draw, in every
/// viewport.
bool canvasDocumentIsCovered(Map<String, dynamic> document) {
  final viewports = _viewportsOf(document);
  for (final viewport in viewports) {
    for (final layer in WebsiteCanvasResponsiveDocument.visibleLayers(
      data: document,
      viewport: viewport,
    )) {
      if (!canvasLayerIsCovered(layer.data)) return false;
    }
  }
  return true;
}

bool _usesProductImage(Map<String, dynamic> layer) {
  final productId = (layer['productId'] ?? '').toString().trim();
  final source =
      (layer['imageSource'] ?? (productId.isNotEmpty ? 'product' : 'manual'))
          .toString();
  return productId.isNotEmpty && source != 'manual';
}

/// The viewports a canvas switches between: the shared 600/900 bands for a
/// canonical document, phone and the rest for a legacy one
/// (`viewportForRenderedCanvasWidth`).
List<WebsiteViewport> _viewportsOf(Map<String, dynamic> document) =>
    WebsiteCanvasResponsiveDocument.isCanonical(document)
    ? const [
        WebsiteViewport.mobile,
        WebsiteViewport.tablet,
        WebsiteViewport.desktop,
      ]
    : const [WebsiteViewport.mobile, WebsiteViewport.desktop];

/// `CanvasBlock` as a visitor sees it: each layer placed in the document's
/// design width, scaled down to fit a narrower canvas (never up) and
/// centered in a wider one. Text keeps its size; boxes, radii, borders and
/// button labels scale.
///
/// One set of layers per viewport the document draws differently, shown by
/// the width of the canvas (a container query): the stylesheet does the
/// scaling with container units, so the same HTML is right at every width.
class CanvasLayersView extends StatelessComponent {
  const CanvasLayersView(
    this.document,
    this.context, {
    this.deferImages = false,
    this.slide,
    super.key,
  });

  final Map<String, dynamic> document;
  final BlockRenderContext context;

  /// For the editor's draft, the carousel slide these layers are of (its
  /// stored position), or `null` for a canvas block's own.
  final int? slide;

  /// Images name their file in `data-src`, for a script to load when they
  /// are about to show (a carousel's later slides).
  final bool deferImages;

  @override
  Component build(BuildContext _) {
    final canonical = WebsiteCanvasResponsiveDocument.isCanonical(document);
    // viewport names → (design width, layers), merged when identical.
    final sets =
        <String, ({double width, List<Map<String, dynamic>> layers})>{};
    final names = <String, List<String>>{};
    for (final viewport in _viewportsOf(document)) {
      final projected = WebsiteCanvasResponsiveDocument.project(
        data: document,
        viewport: viewport,
      );
      final declared = numberValue(projected['designWidth']);
      final width = declared != null && declared > 0
          ? declared
          : canvasReferenceWidth;
      final layers = [
        for (final layer in WebsiteCanvasResponsiveDocument.visibleLayers(
          data: document,
          viewport: viewport,
        ))
          layer.data,
      ];
      final key = jsonEncode([width, layers]);
      sets.putIfAbsent(key, () => (width: width, layers: layers));
      final drawn = names.putIfAbsent(key, () => []);
      drawn.add(viewport.wireName);
      // A legacy document has no tablet of its own: its «desktop» starts at
      // 600.
      if (!canonical && viewport == WebsiteViewport.desktop) {
        drawn.add(WebsiteViewport.tablet.wireName);
      }
    }
    // For the editor's draft, how a dragged layer lands, as `CanvasBlock`
    // does: the grid it snaps to (0 when the document turns snapping off),
    // the distance in pixels that pulls it, and whether it may bleed past
    // the design area.
    final grid = document['snap'] == false
        ? 0.0
        : numberValue(document['gridSize']) ?? 8.0;
    final pull = numberValue(document['snapDistance']) ?? 6.0;
    return div(
      classes: 'cnv',
      attributes: context.draft
          ? {
              'data-canvas-slide': slide == null ? 'root' : '$slide',
              'data-grid': cssNum(grid > 0 ? grid : 0),
              'data-pull': cssNum(pull > 0 ? pull : 0),
              if (document['constrainElementsToSafeArea'] == false)
                'data-bleed': '',
            }
          : const {},
      [
        for (final MapEntry(:key, :value) in sets.entries)
          div(
            classes: 'cnv-set',
            attributes: {
              'data-vp': names[key]!.join(' '),
              'style': '--dw:${cssNum(value.width)}',
            },
            [
              for (final layer in value.layers)
                if (canvasLayerIsCovered(layer)) ?_layer(layer),
            ],
          ),
      ],
    );
  }

  Component? _layer(Map<String, dynamic> layer) {
    final kind = WebsiteCanvasLayerKind.fromRaw(layer['type']);
    final x = numberValue(layer['x']) ?? 20;
    final y = numberValue(layer['y']) ?? 20;
    final w = numberValue(layer['w']) ?? 240;
    final h = numberValue(layer['h']) ?? 56;
    final rotation = numberValue(layer['rotation']) ?? 0;
    final anim = (layer['anim'] ?? 'none').toString();
    final duration = (numberValue(layer['animDurationMs']) ?? 420.0).clamp(
      120.0,
      2000.0,
    );
    final box = [
      '--x:${cssNum(x)}',
      '--y:${cssNum(y)}',
      '--w:${cssNum(w)}',
      '--h:${cssNum(h)}',
      if (rotation != 0) 'rotate:${cssNum(rotation)}deg',
      if (anim == 'fade' || anim == 'fadeUp') '--ad:${cssNum(duration)}ms',
    ];
    final classes = [
      'cl',
      if (anim == 'fade' || anim == 'fadeUp') 'cl-a-$anim',
    ];
    final mark = context.editLayer(layer['id']);
    switch (kind) {
      case WebsiteCanvasLayerKind.text:
        return _text(layer, classes, box, mark);
      case WebsiteCanvasLayerKind.shape:
        return _shape(layer, classes, box, mark);
      case WebsiteCanvasLayerKind.image:
        return _image(layer, classes, box, mark);
      case WebsiteCanvasLayerKind.button:
        return _button(layer, classes, box, mark);
      default:
        return null;
    }
  }

  Component _text(
    Map<String, dynamic> layer,
    List<String> classes,
    List<String> box,
    Map<String, String> mark,
  ) {
    final source = (layer['text'] ?? 'Texto').toString();
    final text = layer['uppercase'] == true ? source.toUpperCase() : source;
    final size = numberValue(layer['fontSize']) ?? 24;
    final weight = switch (layer['fontWeight']?.toString()) {
      'w400' => 400,
      'w500' => 500,
      'w700' => 700,
      _ => 600,
    };
    final color = hexColor(layer['color'], const WebsiteRgba(0.87, 0, 0, 0));
    final align = switch (layer['align']?.toString()) {
      'center' => 'center',
      'right' => 'right',
      _ => 'left',
    };
    final role = (layer['fontRole'] ?? 'heading').toString();
    final family = (layer['fontFamily'] ?? '').toString().trim();
    final heading = family.isEmpty && role != 'body';
    final height = (numberValue(layer['lineHeight']) ?? 1.1).clamp(0.8, 2.0);
    final spacing = numberValue(layer['letterSpacing']) ?? 0;
    final style = [
      'font:${layer['fontStyle'] == 'italic' ? 'italic ' : ''}'
          '${heading ? 400 : weight} ${cssPx(size)}/'
          '${lineHeightPx(size, height)} '
          '${family.isNotEmpty
              ? '"$family",var(--body)'
              : heading
              ? 'var(--head)'
              : 'var(--body)'}',
      'color:${color.css}',
      'text-align:$align',
      if (spacing != 0) 'letter-spacing:${cssPx(spacing)}',
      if (layer['decoration'] == 'underline') 'text-decoration:underline',
      if (heading && weight >= 600) headingWeightCss(weight),
    ];
    final lines = text.split('\n');
    return div(
      classes: [...classes, 'cl-text', 'al-$align'].join(' '),
      attributes: {...mark, 'style': box.join(';')},
      [
        p(
          attributes: {'style': style.join(';')},
          [
            for (var index = 0; index < lines.length; index++) ...[
              if (index > 0) br(),
              .text(lines[index]),
            ],
          ],
        ),
      ],
    );
  }

  Component _shape(
    Map<String, dynamic> layer,
    List<String> classes,
    List<String> box,
    Map<String, String> mark,
  ) {
    final fill = hexColor(layer['fillColor'], WebsiteRgba.fromArgb(0xFF1F2937));
    final border = hexColor(layer['borderColor'], fill);
    final borderWidth = numberValue(layer['borderWidth']) ?? 0;
    final radius = numberValue(layer['radius']) ?? 0;
    final ellipse = layer['shape'] == 'ellipse';
    return div(
      classes: [...classes, 'cl-shape'].join(' '),
      attributes: {
        ...mark,
        'style': [
          ...box,
          'background:${fill.css}',
          if (borderWidth > 0)
            'border:calc(${cssNum(borderWidth)} * var(--s)) solid ${border.css}',
          if (ellipse)
            'border-radius:50%'
          else if (radius > 0)
            'border-radius:min(calc(${cssNum(radius)} * var(--s)),999px)',
        ].join(';'),
      },
      const [],
    );
  }

  Component _image(
    Map<String, dynamic> layer,
    List<String> classes,
    List<String> box,
    Map<String, String> mark,
  ) {
    final url = (layer['imageUrl'] ?? '').toString().trim();
    final fit = layer['fit'] == 'contain' ? 'contain' : 'cover';
    final fx = (numberValue(layer['focalPointX']) ?? 0.5).clamp(0.0, 1.0);
    final fy = (numberValue(layer['focalPointY']) ?? 0.5).clamp(0.0, 1.0);
    final radius = numberValue(layer['radius']) ?? 12;
    final style = [
      ...box,
      if (radius > 0) 'border-radius:calc(${cssNum(radius)} * var(--s))',
    ];
    if (url.isEmpty) {
      return div(
        classes: [...classes, 'cl-img', 'empty'].join(' '),
        attributes: {...mark, 'style': style.join(';')},
        const [],
      );
    }
    return Component.element(
      tag: 'img',
      classes: [...classes, 'cl-img'].join(' '),
      attributes: {
        ...mark,
        if (deferImages) 'data-src': url else 'src': url,
        'alt': (layer['altText'] ?? '').toString(),
        'loading': 'lazy',
        'decoding': 'async',
        'style': [
          ...style,
          'object-fit:$fit',
          'object-position:${cssNum(fx * 100)}% ${cssNum(fy * 100)}%',
        ].join(';'),
      },
    );
  }

  Component? _button(
    Map<String, dynamic> layer,
    List<String> classes,
    List<String> box,
    Map<String, String> mark,
  ) {
    final action =
        WebsiteActionValue.resolvePrimary(
          layer,
          labelKeys: const ['label'],
          hrefKeys: const ['link'],
          variantKeys: const ['style'],
          defaultLabel: 'Botón',
          defaultHref: '/',
          defaultVariant: WebsiteActionVariant.fromStorage(
            layer['style']?.toString(),
          ),
        ) ??
        const WebsiteActionValue(label: 'Botón', href: '/');
    final href = context.publicHref(action.href);
    if (href == null) return null;
    final style = action.variant.storageValue;
    // A button that takes the theme's look is `WebsiteActionButton` with no
    // colors of its own filling the layer: the site theme's Material button
    // (elevated, outlined or text), not the accent of the button block.
    if (layer['inheritTheme'] != false) {
      return a(
        classes: [...classes, 'cl-tbtn', 'w-btn', style].join(' '),
        href: href,
        attributes: {...mark, 'style': box.join(';')},
        [.text(action.label)],
      );
    }
    final size = numberValue(layer['fontSize']) ?? 14;
    final radius = numberValue(layer['radius']) ?? 10;
    final background = hexColor(layer['bgColor'], context.theme.accent);
    final foreground = hexColor(
      layer['fgColor'],
      const WebsiteRgba(1, 1, 1, 1),
    );
    final spacing = numberValue(layer['letterSpacing']) ?? 0;
    final label = layer['uppercase'] == true
        ? action.label.toUpperCase()
        : action.label;
    return a(
      classes: [...classes, 'cl-btn', style].join(' '),
      href: href,
      attributes: {
        ...mark,
        'style': [
          ...box,
          'font-size:calc(${cssNum(size)} * var(--s))',
          'border-radius:calc(${cssNum(radius)} * var(--s))',
          if (spacing != 0) 'letter-spacing:${cssPx(spacing)}',
          if (style == 'filled') ...[
            'background:${background.css}',
            'color:${foreground.css}',
          ] else
            'color:${background.css}',
          if (style == 'outline') 'border-color:${background.css}',
          if (style == 'filled' && layer['shadow'] == true)
            'box-shadow:0 3px 5px -1px rgb(0 0 0 / .2),0 6px 10px rgb(0 0 0 / .14),0 1px 18px rgb(0 0 0 / .12)',
        ].join(';'),
      },
      [.text(label)],
    );
  }
}

/// Whether the HTML storefront draws a canvas block: every layer it holds in
/// every viewport, and no video behind them.
bool canvasBlockIsCovered(Map<String, dynamic> data) {
  for (final viewport in _viewportsOf(data)) {
    final projected = WebsiteCanvasResponsiveDocument.project(
      data: data,
      viewport: viewport,
    );
    if ((projected['backgroundVideoUrl'] ?? '').toString().trim().isNotEmpty ||
        (projected['backgroundYoutubeId'] ?? '').toString().trim().isNotEmpty) {
      return false;
    }
  }
  return canvasDocumentIsCovered(data);
}

/// The `canvas` block (`CanvasBlock`) as a visitor sees it: its stage — the
/// background color, the photo with its focal point and fit, the veil —
/// under the layers ([CanvasLayersView]). One stage per viewport the
/// document draws differently, shown by the width of the block.
///
/// The page gives it the saved height (`blockHeight`, exact, as
/// `PageComposition` does in Flutter's Preview and store). A document
/// without one takes Flutter's own: the height scaled with the width (half
/// to double), or a share of the window.
class CanvasBlockView extends StatelessComponent {
  const CanvasBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    // The whole document: the canvas resolves its own viewports.
    final document = composed.block.blockData;
    final exact = composed.block.geometry.exactHeight != null;
    final canonical = WebsiteCanvasResponsiveDocument.isCanonical(document);
    final stages = <String, List<String>>{};
    final drawn = <String, Component>{};
    for (final viewport in _viewportsOf(document)) {
      final data = WebsiteCanvasResponsiveDocument.project(
        data: document,
        viewport: viewport,
      );
      final stage = _stage(data, document, exact: exact);
      final key = jsonEncode(stage.$1);
      drawn.putIfAbsent(key, () => stage.$2);
      final names = stages.putIfAbsent(key, () => []);
      names.add(viewport.wireName);
      if (!canonical && viewport == WebsiteViewport.desktop) {
        names.add(WebsiteViewport.tablet.wireName);
      }
    }
    return div(classes: ['cv', if (exact) 'exact'].join(' '), [
      for (final MapEntry(:key, :value) in drawn.entries)
        Component.element(
          tag: 'div',
          classes: 'cv-st',
          attributes: {'data-vp': stages[key]!.join(' ')},
          children: [value],
        ),
      CanvasLayersView(document, context),
    ]);
  }

  /// One viewport's stage: what makes it different (for merging equal
  /// stages) and what it draws.
  (List<Object?>, Component) _stage(
    Map<String, dynamic> data,
    Map<String, dynamic> document, {
    required bool exact,
  }) {
    final declared = numberValue(data['designWidth']);
    final designWidth = declared != null && declared > 0
        ? declared
        : canvasReferenceWidth;
    final viewportHeight =
        (data['heightMode'] ?? 'fixed').toString() == 'viewport';
    final share = (numberValue(data['vhPct']) ?? 0.7).clamp(0.2, 1.0);
    final height =
        numberValue(data['blockHeight']) ?? numberValue(data['height']) ?? 420;
    final background = hexColor(
      data['backgroundColor'],
      const WebsiteRgba(1, 1, 1, 1),
    );
    final image = (data['backgroundImageUrl'] ?? '').toString().trim();
    final contain =
        (data['backgroundFit'] ?? 'cover').toString().toLowerCase() ==
        'contain';
    final fx = (numberValue(data['focalPointX']) ?? 0.5).clamp(0.0, 1.0);
    final fy = (numberValue(data['focalPointY']) ?? 0.5).clamp(0.0, 1.0);
    final veil = data['overlayEnabled'] == true;
    // `withValues(alpha:)`: the opacity replaces the color's own alpha.
    final veilBase = hexColor(
      data['overlayColor'] ?? '#000000',
      const WebsiteRgba(1, 0, 0, 0),
    );
    final veilColor = WebsiteRgba(
      (numberValue(data['overlayOpacity']) ?? 0.35).clamp(0.0, 0.9),
      veilBase.r,
      veilBase.g,
      veilBase.b,
    );
    final style = [
      'background:${background.css}',
      if (!exact)
        viewportHeight
            ? 'height:calc(${cssNum(share * 100)}vh)'
            : 'height:clamp(${cssPx(height / 2)},'
                  'calc(${cssNum(height)} * 100cqw / ${cssNum(designWidth)}),'
                  '${cssPx(height * 2)})',
    ];
    final alt = (document['backgroundImageAltText'] ?? '').toString();
    return (
      [style, image, contain, fx, fy, veil, veilColor.css, alt],
      div(
        classes: 'cv-bg',
        attributes: {'style': style.join(';')},
        [
          if (image.isNotEmpty)
            Component.element(
              tag: 'img',
              attributes: {
                'src': image,
                'alt': alt,
                'loading': 'lazy',
                'decoding': 'async',
                'style':
                    'object-fit:${contain ? 'contain' : 'cover'};'
                    'object-position:${cssNum(fx * 100)}% ${cssNum(fy * 100)}%',
              },
            ),
          if (veil)
            div(
              classes: 'cv-veil',
              attributes: {'style': 'background:${veilColor.css}'},
              const [],
            ),
        ],
      ),
    );
  }
}
