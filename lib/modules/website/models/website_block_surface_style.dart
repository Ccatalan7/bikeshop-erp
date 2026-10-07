import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_surface_spec.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart'
    show WebsiteRgba;

import 'website_block_definition.dart';
import 'website_block_type.dart';
import 'website_responsive_authoring.dart';

/// Canonical schema and storage bridge for a block's authored surface.
///
/// Shared values deliberately remain in the historical map consumed by older
/// clients: `block_data.style` when that value is a map. A standalone Button
/// already owns the scalar `style` key as its action variant, so its surface
/// map lives under `surfaceStyle` instead. The scalar is never interpreted as
/// a surface and is never replaced.
///
/// Padding is the only responsive surface family. Its viewport overrides are
/// namespaced at the block root (`responsive.mobile.surfacePaddingTop`, etc.)
/// while the shared/base number remains in the compatible map (`style
/// .paddingTop`). This lets an older client edit the base and round-trip the
/// unknown override without creating a second shared authority.
///
/// Authoring choices come from DesignSync project `ERP Bikeshop UI Mockups`,
/// `Website Builder · Estilo de bloque.dc.html`, turn t19 (frames 19a-19k).
/// Values outside these closed choices remain readable and render unchanged;
/// opening the inspector never normalizes a historical document.
abstract final class WebsiteBlockSurfaceFields {
  static const String legacyMapKey = 'style';
  static const String scalarSafeMapKey = 'surfaceStyle';

  static const List<double> verticalPaddingChoices = <double>[0, 32, 48, 64];
  static const List<double> horizontalPaddingChoices = <double>[0, 16, 24, 32];
  static const List<double> borderWidthChoices = <double>[0, 1];
  static const List<double> borderRadiusChoices = <double>[0, 4, 10, 14];

  static const Map<String, Map<String, Object?>> depthChoices =
      <String, Map<String, Object?>>{
    'none': <String, Object?>{'shadowEnabled': false},
    'raised': <String, Object?>{
      'shadowEnabled': true,
      'shadowOffsetX': 0.0,
      'shadowOffsetY': 1.0,
      'shadowBlur': 2.0,
      'shadowSpread': 0.0,
      'shadowColor': 'rgba(12,37,55,0.06)',
    },
    'popover': <String, Object?>{
      'shadowEnabled': true,
      'shadowOffsetX': 0.0,
      'shadowOffsetY': 6.0,
      'shadowBlur': 22.0,
      'shadowSpread': 0.0,
      'shadowColor': 'rgba(12,37,55,0.13)',
    },
    'overlay': <String, Object?>{
      'shadowEnabled': true,
      'shadowOffsetX': 0.0,
      'shadowOffsetY': 12.0,
      'shadowBlur': 40.0,
      'shadowSpread': 0.0,
      'shadowColor': 'rgba(12,37,55,0.22)',
    },
  };

  static const WebsiteBlockFieldSchema paddingTop = WebsiteBlockFieldSchema(
    key: 'surfacePaddingTop',
    label: 'Relleno superior',
    type: WebsiteBlockFieldType.number,
    min: 0,
    max: 64,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
    propertyFamily: WebsiteResponsivePropertyFamily.spacing,
    authoringSurfaces: {
      WebsiteAuthoringSurface.contextSheet,
      WebsiteAuthoringSurface.inspector,
    },
  );

  static const WebsiteBlockFieldSchema paddingRight = WebsiteBlockFieldSchema(
    key: 'surfacePaddingRight',
    label: 'Relleno derecho',
    type: WebsiteBlockFieldType.number,
    min: 0,
    max: 32,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
    propertyFamily: WebsiteResponsivePropertyFamily.spacing,
    authoringSurfaces: {
      WebsiteAuthoringSurface.contextSheet,
      WebsiteAuthoringSurface.inspector,
    },
  );

  static const WebsiteBlockFieldSchema paddingBottom = WebsiteBlockFieldSchema(
    key: 'surfacePaddingBottom',
    label: 'Relleno inferior',
    type: WebsiteBlockFieldType.number,
    min: 0,
    max: 64,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
    propertyFamily: WebsiteResponsivePropertyFamily.spacing,
    authoringSurfaces: {
      WebsiteAuthoringSurface.contextSheet,
      WebsiteAuthoringSurface.inspector,
    },
  );

  static const WebsiteBlockFieldSchema paddingLeft = WebsiteBlockFieldSchema(
    key: 'surfacePaddingLeft',
    label: 'Relleno izquierdo',
    type: WebsiteBlockFieldType.number,
    min: 0,
    max: 32,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
    propertyFamily: WebsiteResponsivePropertyFamily.spacing,
    authoringSurfaces: {
      WebsiteAuthoringSurface.contextSheet,
      WebsiteAuthoringSurface.inspector,
    },
  );

  static const WebsiteBlockFieldSchema backgroundType = WebsiteBlockFieldSchema(
    key: 'surfaceBackgroundType',
    label: 'Tipo de fondo',
    type: WebsiteBlockFieldType.select,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.color,
  );

  static const WebsiteBlockFieldSchema backgroundColor =
      WebsiteBlockFieldSchema(
    key: 'surfaceBackgroundColor',
    label: 'Color de fondo',
    type: WebsiteBlockFieldType.color,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.color,
  );

  static const WebsiteBlockFieldSchema gradientColor1 = WebsiteBlockFieldSchema(
    key: 'surfaceGradientColor1',
    label: 'Color inicial',
    type: WebsiteBlockFieldType.color,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.color,
  );

  static const WebsiteBlockFieldSchema gradientColor2 = WebsiteBlockFieldSchema(
    key: 'surfaceGradientColor2',
    label: 'Color final',
    type: WebsiteBlockFieldType.color,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.color,
  );

  static const WebsiteBlockFieldSchema gradientDirection =
      WebsiteBlockFieldSchema(
    key: 'surfaceGradientDirection',
    label: 'Dirección',
    type: WebsiteBlockFieldType.select,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema borderWidth = WebsiteBlockFieldSchema(
    key: 'surfaceBorderWidth',
    label: 'Grosor del borde',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema borderColor = WebsiteBlockFieldSchema(
    key: 'surfaceBorderColor',
    label: 'Color del borde',
    type: WebsiteBlockFieldType.color,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.color,
  );

  static const WebsiteBlockFieldSchema borderRadius = WebsiteBlockFieldSchema(
    key: 'surfaceBorderRadius',
    label: 'Radio de las esquinas',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema borderStyle = WebsiteBlockFieldSchema(
    key: 'surfaceBorderStyle',
    label: 'Estilo del borde',
    type: WebsiteBlockFieldType.select,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema shadowEnabled = WebsiteBlockFieldSchema(
    key: 'surfaceShadowEnabled',
    label: 'Sombra',
    type: WebsiteBlockFieldType.toggle,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema shadowOffsetX = WebsiteBlockFieldSchema(
    key: 'surfaceShadowOffsetX',
    label: 'Desplazamiento horizontal',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema shadowOffsetY = WebsiteBlockFieldSchema(
    key: 'surfaceShadowOffsetY',
    label: 'Desplazamiento vertical',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema shadowBlur = WebsiteBlockFieldSchema(
    key: 'surfaceShadowBlur',
    label: 'Difuminado',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema shadowSpread = WebsiteBlockFieldSchema(
    key: 'surfaceShadowSpread',
    label: 'Extensión',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
  );

  static const WebsiteBlockFieldSchema shadowColor = WebsiteBlockFieldSchema(
    key: 'surfaceShadowColor',
    label: 'Color de la sombra',
    type: WebsiteBlockFieldType.color,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
    propertyFamily: WebsiteResponsivePropertyFamily.color,
  );

  static const List<WebsiteBlockFieldSchema> paddingFields =
      <WebsiteBlockFieldSchema>[
    paddingTop,
    paddingRight,
    paddingBottom,
    paddingLeft,
  ];

  static const List<WebsiteBlockFieldSchema> sharedFields =
      <WebsiteBlockFieldSchema>[
    backgroundType,
    backgroundColor,
    gradientColor1,
    gradientColor2,
    gradientDirection,
    borderWidth,
    borderColor,
    borderRadius,
    borderStyle,
    shadowEnabled,
    shadowOffsetX,
    shadowOffsetY,
    shadowBlur,
    shadowSpread,
    shadowColor,
  ];

  static const Map<String, String> _legacyKeys = <String, String>{
    'surfacePaddingTop': 'paddingTop',
    'surfacePaddingRight': 'paddingRight',
    'surfacePaddingBottom': 'paddingBottom',
    'surfacePaddingLeft': 'paddingLeft',
    'surfaceBackgroundType': 'backgroundType',
    'surfaceBackgroundColor': 'backgroundColor',
    'surfaceGradientColor1': 'gradientColor1',
    'surfaceGradientColor2': 'gradientColor2',
    'surfaceGradientDirection': 'gradientDirection',
    'surfaceBorderWidth': 'borderWidth',
    'surfaceBorderColor': 'borderColor',
    'surfaceBorderRadius': 'borderRadius',
    'surfaceBorderStyle': 'borderStyle',
    'surfaceShadowEnabled': 'shadowEnabled',
    'surfaceShadowOffsetX': 'shadowOffsetX',
    'surfaceShadowOffsetY': 'shadowOffsetY',
    'surfaceShadowBlur': 'shadowBlur',
    'surfaceShadowSpread': 'shadowSpread',
    'surfaceShadowColor': 'shadowColor',
  };

  static String legacyKey(WebsiteBlockFieldSchema field) =>
      _legacyKeys[field.key]!;

  static Map<WebsiteBlockFieldSchema, Object?> depthValuesFor(String preset) {
    final values = depthChoices[preset];
    if (values == null) return const <WebsiteBlockFieldSchema, Object?>{};
    return <WebsiteBlockFieldSchema, Object?>{
      for (final field in <WebsiteBlockFieldSchema>[
        shadowEnabled,
        shadowOffsetX,
        shadowOffsetY,
        shadowBlur,
        shadowSpread,
        shadowColor,
      ])
        if (values.containsKey(legacyKey(field)))
          field: values[legacyKey(field)],
    };
  }

  static String baseMapKey(Map<String, dynamic> data) =>
      WebsiteBlockSurfaceSpec.baseMapKeyOf(data);

  static Map<String, dynamic> baseMap(Map<String, dynamic> data) =>
      WebsiteBlockSurfaceSpec.baseMap(data);

  /// Produces the complete compatible shared map for one atomic provider
  /// operation. Unknown keys are deep-copied and preserved, and [data] is
  /// never mutated. A null value explicitly removes that authored property.
  ///
  /// The caller commits the returned map under [baseMapKey]. This is
  /// intentionally a whole-map value: a style gesture has one history entry,
  /// while the provider's lease can fail closed if that shared owner changed.
  static Map<String, dynamic> sharedMapWithValues({
    required Map<String, dynamic> data,
    required Map<WebsiteBlockFieldSchema, Object?> values,
  }) {
    final result = baseMap(data);
    for (final entry in values.entries) {
      final key = legacyKey(entry.key);
      final value = entry.value;
      if (value == null) {
        result.remove(key);
      } else {
        result[key] = _deepCopy(value);
      }
    }
    return result;
  }
}

/// Established content-padding defaults for each block family.
///
/// These are the values the shared renderer already used before the surface
/// owner existed. Centralizing them lets the inspector display the exact value
/// that Edit, Preview and Public consume without manufacturing a serialized
/// base. Authored sides still override these values independently.
abstract final class WebsiteBlockSurfaceDefaults {
  static EdgeInsets paddingFor({
    required WebsiteBlockType blockType,
    required WebsiteViewport viewport,
    required Map<String, dynamic> data,
  }) =>
      _edgeInsets(
        websiteBlockSurfaceDefaultPadding(
          blockType: blockType,
          viewport: viewport,
          data: data,
        ),
      );
}

EdgeInsets _edgeInsets(WebsiteSurfaceInsets insets) => EdgeInsets.only(
      top: insets.top,
      right: insets.right,
      bottom: insets.bottom,
      left: insets.left,
    );

/// The effective surface projected for one rendered storefront viewport.
///
/// This class is the only decoder of the historical map, responsive padding
/// overrides and authored colour strings. Widgets receive typed values and do
/// not inspect serialized keys.
@immutable
class WebsiteBlockSurfaceStyle {
  const WebsiteBlockSurfaceStyle._(this._spec);

  /// Decoded by the core's [WebsiteBlockSurfaceSpec], the one reader of the
  /// stored values, which the HTML storefront writes its CSS with too.
  factory WebsiteBlockSurfaceStyle.resolve({
    required Map<String, dynamic> data,
    required WebsiteViewport viewport,
  }) =>
      WebsiteBlockSurfaceStyle._(
        WebsiteBlockSurfaceSpec.resolve(data: data, viewport: viewport),
      );

  factory WebsiteBlockSurfaceStyle.forLogicalWidth({
    required Map<String, dynamic> data,
    required double logicalWidth,
  }) {
    return WebsiteBlockSurfaceStyle.resolve(
      data: data,
      viewport: WebsiteResponsiveDataCodec.viewportForDocumentWidth(
        data,
        logicalWidth,
      ),
    );
  }

  final WebsiteBlockSurfaceSpec _spec;

  WebsiteViewport get viewport => _spec.viewport;
  String get baseMapKey => _spec.baseMapKey;
  Map<String, dynamic> get base => _spec.base;
  WebsiteResolvedResponsiveValue<double> get paddingTop => _spec.paddingTop;
  WebsiteResolvedResponsiveValue<double> get paddingRight => _spec.paddingRight;
  WebsiteResolvedResponsiveValue<double> get paddingBottom =>
      _spec.paddingBottom;
  WebsiteResolvedResponsiveValue<double> get paddingLeft => _spec.paddingLeft;

  bool get hasAuthoredPadding => _spec.hasAuthoredPadding;

  /// Whether one side has a real persisted base or viewport override.
  ///
  /// Consumers with established inner spacing use this to remove only the
  /// side now owned by surface padding. A top-only edit must not accidentally
  /// erase an unrelated horizontal content inset.
  bool isPaddingAuthored(WebsiteBlockFieldSchema field) {
    final side = switch (field.key) {
      'surfacePaddingTop' => WebsiteSurfaceSide.top,
      'surfacePaddingRight' => WebsiteSurfaceSide.right,
      'surfacePaddingBottom' => WebsiteSurfaceSide.bottom,
      'surfacePaddingLeft' => WebsiteSurfaceSide.left,
      _ => null,
    };
    return side != null && _spec.isPaddingAuthored(side);
  }

  EdgeInsets paddingWithFallback(EdgeInsets fallback) => EdgeInsets.only(
        top: paddingTop.value ?? fallback.top,
        right: paddingRight.value ?? fallback.right,
        bottom: paddingBottom.value ?? fallback.bottom,
        left: paddingLeft.value ?? fallback.left,
      );

  String get backgroundType => _spec.backgroundType;

  Color? get backgroundColor => _color(_spec.backgroundColor);

  Color? get gradientColor1 => _color(_spec.gradientColor1);

  Color? get gradientColor2 => _color(_spec.gradientColor2);

  String get gradientDirection => _spec.gradientDirection;

  double get borderWidth => _spec.borderWidth;

  Color? get borderColor => _color(_spec.borderColor);

  double get borderRadius => _spec.borderRadius;

  /// Flutter's `Border` cannot paint dashed/dotted strokes. Historical values
  /// therefore render honestly as solid instead of disappearing. The source
  /// map is untouched until the operator explicitly changes the border.
  String get borderStyle => _spec.borderStyle;

  bool get paintsBorder => _spec.paintsBorder;

  bool get shadowEnabled => _spec.shadowEnabled;

  double get shadowOffsetX => _spec.shadowOffsetX;

  double get shadowOffsetY => _spec.shadowOffsetY;

  double get shadowBlur => _spec.shadowBlur;

  double get shadowSpread => _spec.shadowSpread;

  Color get shadowColor => _color(_spec.shadowColor)!;

  /// Published F-05 depth name, or null for a historical custom shadow.
  String? get depthPreset {
    if (!shadowEnabled) return 'none';
    for (final preset in const <String>['raised', 'popover', 'overlay']) {
      final expected = WebsiteBlockSurfaceFields.depthChoices[preset]!;
      if (_matchesNumber(expected['shadowOffsetX'], shadowOffsetX) &&
          _matchesNumber(expected['shadowOffsetY'], shadowOffsetY) &&
          _matchesNumber(expected['shadowBlur'], shadowBlur) &&
          _matchesNumber(expected['shadowSpread'], shadowSpread) &&
          parseColor(expected['shadowColor']) == shadowColor) {
        return preset;
      }
    }
    return null;
  }

  bool get hasAuthoredBackground => _spec.hasAuthoredBackground;

  bool get hasAuthoredFrame => _spec.hasAuthoredFrame;

  bool get hasAuthoredDecoration => _spec.hasAuthoredDecoration;

  /// Decoration painted once by [WebsiteBlockSurface].
  ///
  /// No fallback colour is invented here: a block with no authored surface
  /// keeps its established content background. Authored gradients retain the
  /// existing editor defaults when one of their stored colours is absent.
  BoxDecoration decoration() {
    final useGradient = backgroundType == 'gradient' && hasAuthoredBackground;
    final isTransparent = backgroundType == 'transparent';
    return BoxDecoration(
      color: useGradient || isTransparent ? null : backgroundColor,
      gradient: useGradient
          ? LinearGradient(
              begin: gradientBegin(gradientDirection),
              end: gradientEnd(gradientDirection),
              colors: <Color>[
                gradientColor1 ?? Colors.white,
                gradientColor2 ?? Colors.grey.shade100,
              ],
            )
          : null,
      border: paintsBorder
          ? Border.all(
              color: borderColor ?? Colors.grey,
              width: borderWidth,
              style: BorderStyle.solid,
            )
          : null,
      borderRadius:
          borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
      boxShadow: shadowEnabled
          ? <BoxShadow>[
              BoxShadow(
                offset: Offset(shadowOffsetX, shadowOffsetY),
                blurRadius: shadowBlur,
                spreadRadius: shadowSpread,
                color: shadowColor,
              ),
            ]
          : null,
    );
  }

  /// Full authored surface plus optional cover media.
  ///
  /// Carousel slides use the same parser as block roots but own their media
  /// inside the slide. This method keeps that composition in one typed path;
  /// callers provide only the established fallback and image identity.
  BoxDecoration decorationWithMedia({
    required Color fallbackColor,
    ImageProvider<Object>? imageProvider,
    Alignment imageAlignment = Alignment.center,
    ColorFilter? imageColorFilter,
    bool preserveLegacyFallbackGradient = true,
    ImageErrorListener? onImageError,
  }) {
    final hasImage = imageProvider != null;
    final useAuthoredGradient =
        backgroundType == 'gradient' && hasAuthoredBackground && !hasImage;
    final isTransparent = backgroundType == 'transparent' && !hasImage;
    final useLegacyGradient =
        !hasImage && !hasAuthoredBackground && preserveLegacyFallbackGradient;
    return BoxDecoration(
      color: useAuthoredGradient || isTransparent
          ? null
          : hasAuthoredBackground
              ? backgroundColor
              : fallbackColor,
      image: imageProvider == null
          ? null
          : DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
              alignment: imageAlignment,
              colorFilter: imageColorFilter,
              onError: onImageError,
            ),
      gradient: useAuthoredGradient
          ? LinearGradient(
              begin: gradientBegin(gradientDirection),
              end: gradientEnd(gradientDirection),
              colors: <Color>[
                gradientColor1 ?? Colors.white,
                gradientColor2 ?? Colors.grey.shade100,
              ],
            )
          : useLegacyGradient
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    fallbackColor,
                    Color.lerp(fallbackColor, Colors.black, 0.2)!,
                  ],
                )
              : null,
      border: paintsBorder
          ? Border.all(
              color: borderColor ?? Colors.grey,
              width: borderWidth,
              style: BorderStyle.solid,
            )
          : null,
      borderRadius:
          borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
      boxShadow: shadowEnabled
          ? <BoxShadow>[
              BoxShadow(
                offset: Offset(shadowOffsetX, shadowOffsetY),
                blurRadius: shadowBlur,
                spreadRadius: shadowSpread,
                color: shadowColor,
              ),
            ]
          : null,
    );
  }

  /// Background used inside media-owning content such as Hero and CTA.
  ///
  /// When the outer surface owns an authored background, this layer is
  /// transparent so it cannot cover that surface. Media still wins and the
  /// content's established fallback remains when no surface was authored.
  BoxDecoration contentBackgroundDecoration({
    required Color fallbackColor,
    ImageProvider<Object>? imageProvider,
    Alignment imageAlignment = Alignment.center,
    bool preserveLegacyFallbackGradient = true,
    ImageErrorListener? onImageError,
  }) {
    final hasImage = imageProvider != null;
    final transparentForOuter = hasAuthoredBackground && !hasImage;
    final color = transparentForOuter ? Colors.transparent : fallbackColor;
    return BoxDecoration(
      color: color,
      image: imageProvider == null
          ? null
          : DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
              alignment: imageAlignment,
              onError: onImageError,
            ),
      gradient:
          !hasImage && !hasAuthoredBackground && preserveLegacyFallbackGradient
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    fallbackColor,
                    Color.lerp(fallbackColor, Colors.black, 0.2)!,
                  ],
                )
              : null,
    );
  }

  static Color? parseColor(Object? raw) => _color(websiteSurfaceColor(raw));

  static Alignment gradientBegin(String direction) => switch (direction) {
        'to-top' => Alignment.bottomCenter,
        'to-top-right' => Alignment.bottomLeft,
        'to-right' => Alignment.centerLeft,
        'to-bottom-right' => Alignment.topLeft,
        'to-bottom-left' => Alignment.topRight,
        'to-left' => Alignment.centerRight,
        'to-top-left' => Alignment.bottomRight,
        _ => Alignment.topCenter,
      };

  static Alignment gradientEnd(String direction) => switch (direction) {
        'to-top' => Alignment.topCenter,
        'to-top-right' => Alignment.topRight,
        'to-right' => Alignment.centerRight,
        'to-bottom-right' => Alignment.bottomRight,
        'to-bottom-left' => Alignment.bottomLeft,
        'to-left' => Alignment.centerLeft,
        'to-top-left' => Alignment.topLeft,
        _ => Alignment.bottomCenter,
      };

  static bool _matchesNumber(Object? raw, double actual) {
    final expected = _decodeDouble(raw);
    return expected != null && (expected - actual).abs() < 0.0001;
  }
}

double? _decodeDouble(Object? raw) {
  if (raw is num) {
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }
  if (raw is String) {
    final value = double.tryParse(raw.trim());
    return value?.isFinite == true ? value : null;
  }
  return null;
}

Object? _deepCopy(Object? value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _deepCopy(nested)),
    );
  }
  if (value is List) return value.map(_deepCopy).toList(growable: false);
  if (value is Set) return value.map(_deepCopy).toSet();
  return value;
}

/// A core surface color as Flutter paints it.
Color? _color(WebsiteRgba? rgba) => rgba == null
    ? null
    : Color.from(alpha: rgba.a, red: rgba.r, green: rgba.g, blue: rgba.b);
