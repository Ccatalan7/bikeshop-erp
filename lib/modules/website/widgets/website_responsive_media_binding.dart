import 'package:flutter/widgets.dart';

import '../models/website_block_definition.dart';
import '../models/website_responsive_authoring.dart';
import '../models/website_responsive_field_state.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_responsive_scalar_binding.dart';

/// Resolves one image field — asset plus framing — for any inspector.
///
/// The generic schema control and the Carousel slide control compose the SAME
/// state here instead of each interpreting inheritance again; that divergence
/// is what produced four different rules for one mobile focal point.
///
/// It owns persistence semantics only. The visual control stays pure and never
/// sees a serialized key.
///
/// Focal support is a declared capability, not an assumption: a schema without
/// [WebsiteBlockFieldSchema.hasFocalPointControl] — a logo, an avatar, inline
/// media — gets [focalState] `null`, and the control then offers no reframing
/// and writes no focal key at all.
@immutable
class WebsiteResponsiveMediaBinding {
  const WebsiteResponsiveMediaBinding({
    required this.urlState,
    required this.focalState,
    required this.writeUrl,
    required this.writeFocal,
    required this.customizeUrl,
    required this.resetUrl,
    required this.customizeFocal,
    required this.resetFocal,
  });

  final WebsiteResponsiveFieldState<String> urlState;

  /// Null when the schema declares no focal capability.
  final WebsiteResponsiveFieldState<Offset>? focalState;

  final ValueChanged<String> writeUrl;
  final void Function(double x, double y)? writeFocal;
  final VoidCallback customizeUrl;
  final VoidCallback resetUrl;
  final VoidCallback? customizeFocal;
  final VoidCallback? resetFocal;

  bool get supportsFocalPoint => focalState != null;

  /// Safe URL decoder: a blank value is absent, never an override.
  static String? decodeUrl(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  static double? decodeAxis(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  /// Reads a legacy mobile-only alias so a pre-migration document keeps
  /// rendering exactly what it rendered before. Reading never migrates.
  static WebsiteLegacyResponsiveReader<T> legacyMobileReader<T>(
    List<String> aliases,
    WebsiteResponsiveDecoder<T> decode,
  ) {
    return (data, propertyKey, viewport) {
      if (viewport != WebsiteViewport.mobile) {
        return WebsiteResponsiveEntry<T>.absent();
      }
      for (final alias in aliases) {
        if (!data.containsKey(alias)) continue;
        final decoded = decode(data[alias]);
        if (decoded != null) return WebsiteResponsiveEntry<T>.present(decoded);
      }
      return WebsiteResponsiveEntry<T>.absent();
    };
  }

  /// The synthetic canonical schema for the framing pair.
  ///
  /// The user reasons about a frame, not about `focalPointX`.
  static const WebsiteBlockFieldSchema framingSchema = WebsiteBlockFieldSchema(
    key: 'focalPoint',
    label: 'Encuadre',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
  );

  static WebsiteBlockFieldSchema _axisSchema(String key) {
    return WebsiteBlockFieldSchema(
      key: key,
      label: 'Encuadre',
      type: WebsiteBlockFieldType.number,
      responsivePolicy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
    );
  }

  /// The two axes presented as one framing value.
  ///
  /// The status is the strongest of the two, so a single overridden axis still
  /// reads as customized instead of silently looking inherited.
  @visibleForTesting
  static WebsiteResponsiveFieldState<Offset> composeFocalState({
    required WebsiteResponsiveFieldState<double> x,
    required WebsiteResponsiveFieldState<double> y,
  }) {
    Offset? pair(double? a, double? b) {
      if (a == null && b == null) return null;
      return Offset(a ?? 0.5, b ?? 0.5);
    }

    return WebsiteResponsiveFieldState<Offset>.resolve(
      schema: framingSchema,
      context: x.context,
      resolved: WebsiteResolvedResponsiveValue<Offset>(
        shared: pair(x.resolved.shared, y.resolved.shared),
        value: pair(x.resolved.value, y.resolved.value),
        viewport: x.resolved.viewport,
        isOverride: x.resolved.isOverride || y.resolved.isOverride,
        isLegacyOverride:
            x.resolved.isLegacyOverride || y.resolved.isLegacyOverride,
      ),
    );
  }

  /// Root image of a block — the generic schema and Hero path.
  factory WebsiteResponsiveMediaBinding.root({
    required WebsiteEditModeProvider provider,
    required String blockId,
    required WebsiteBlockFieldSchema field,
    WebsiteAuthoringHostClass hostClass = WebsiteAuthoringHostClass.desktop,
  }) {
    // The asset half IS a scalar property, so it uses the scalar owner rather
    // than a second implementation of the same rules. That is what gives media
    // the companion contract it was missing: a shared write also updates the
    // `migrationAliases` the product still reads, atomically, while a viewport
    // write keeps writing only the canonical authority.
    final urlBinding = WebsiteResponsiveScalarBinding<String>.forField(
      provider: provider,
      blockId: blockId,
      field: field,
      owner: const WebsiteResponsiveRootField(),
      decode: decodeUrl,
      hostClass: hostClass,
    );
    final urlState = urlBinding.state;

    if (!field.hasFocalPointControl) {
      return WebsiteResponsiveMediaBinding(
        urlState: urlState,
        focalState: null,
        writeUrl: urlBinding.write,
        writeFocal: null,
        customizeUrl: urlBinding.customize,
        resetUrl: urlBinding.reset,
        customizeFocal: null,
        resetFocal: null,
      );
    }

    final xKey = field.focalPointXKey;
    final yKey = field.focalPointYKey;
    final legacyX = <String>[field.mobileFocalPointXKey];
    final legacyY = <String>[field.mobileFocalPointYKey];
    final focalPolicies = <String, WebsiteResponsivePropertyPolicy>{
      xKey: WebsiteResponsivePropertyPolicy.perViewportGeometry,
      yKey: WebsiteResponsivePropertyPolicy.perViewportGeometry,
    };

    WebsiteResponsiveFieldState<double> axis(String key, List<String> legacy) {
      return provider.responsiveFieldState<double>(
        blockId: blockId,
        schema: _axisSchema(key),
        decode: decodeAxis,
        hostClass: hostClass,
        fallback: 0.5,
        readLegacyOverride: legacyMobileReader<double>(legacy, decodeAxis),
      );
    }

    return WebsiteResponsiveMediaBinding(
      urlState: urlState,
      focalState: composeFocalState(
        x: axis(xKey, legacyX),
        y: axis(yKey, legacyY),
      ),
      writeUrl: urlBinding.write,
      // ONE history entry for the pair: X and Y are one framing decision.
      writeFocal: (x, y) => provider.setBlockResponsiveProperties(
        blockId,
        <String, Object?>{xKey: x, yKey: y},
        policies: focalPolicies,
      ),
      customizeUrl: urlBinding.customize,
      resetUrl: urlBinding.reset,
      customizeFocal: () {
        for (final key in <String>[xKey, yKey]) {
          provider.setFieldWriteScope(
            blockId: blockId,
            propertyKey: key,
            policy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
            scope: WebsiteWriteScope.viewport,
          );
        }
      },
      resetFocal: () => provider.clearBlockResponsiveOverrides(
        blockId,
        <String>[xKey, yKey],
        policies: focalPolicies,
        legacyPropertyKeys: <String, Iterable<String>>{
          xKey: legacyX,
          yKey: legacyY,
        },
      ),
    );
  }

  /// Image of one repeater item — the active Carousel slide.
  factory WebsiteResponsiveMediaBinding.repeaterItem({
    required WebsiteEditModeProvider provider,
    required String blockId,
    required WebsiteBlockFieldSchema field,
    required List<String> collectionKeys,
    required int itemIndex,
    String? identityKey,
    Object? identityValue,
    WebsiteAuthoringHostClass hostClass = WebsiteAuthoringHostClass.desktop,
  }) {
    // Same rule as the root owner, on the item's own node: one scalar owner
    // decides scope, canonical authority and shared companions.
    final urlBinding = WebsiteResponsiveScalarBinding<String>.forField(
      provider: provider,
      blockId: blockId,
      field: field,
      owner: WebsiteResponsiveRepeaterField(
        collectionKeys: collectionKeys,
        itemIndex: itemIndex,
        identityKey: identityKey,
        identityValue: identityValue,
      ),
      decode: decodeUrl,
      hostClass: hostClass,
    );
    final urlState = urlBinding.state;

    if (!field.hasFocalPointControl) {
      return WebsiteResponsiveMediaBinding(
        urlState: urlState,
        focalState: null,
        writeUrl: urlBinding.write,
        writeFocal: null,
        customizeUrl: urlBinding.customize,
        resetUrl: urlBinding.reset,
        customizeFocal: null,
        resetFocal: null,
      );
    }

    final xKey = field.focalPointXKey;
    final yKey = field.focalPointYKey;
    final legacyX = <String>[field.mobileFocalPointXKey];
    final legacyY = <String>[field.mobileFocalPointYKey];
    final focalPolicies = <String, WebsiteResponsivePropertyPolicy>{
      xKey: WebsiteResponsivePropertyPolicy.perViewportGeometry,
      yKey: WebsiteResponsivePropertyPolicy.perViewportGeometry,
    };

    WebsiteResponsiveFieldState<double> axis(String key, List<String> legacy) {
      return provider.responsiveRepeaterFieldState<double>(
        blockId: blockId,
        collectionKeys: collectionKeys,
        itemIndex: itemIndex,
        identityKey: identityKey,
        identityValue: identityValue,
        schema: _axisSchema(key),
        decode: decodeAxis,
        hostClass: hostClass,
        fallback: 0.5,
        readLegacyOverride: legacyMobileReader<double>(legacy, decodeAxis),
      );
    }

    return WebsiteResponsiveMediaBinding(
      urlState: urlState,
      focalState: composeFocalState(
        x: axis(xKey, legacyX),
        y: axis(yKey, legacyY),
      ),
      writeUrl: urlBinding.write,
      writeFocal: (x, y) => provider.setBlockRepeaterItemResponsiveProperties(
        blockId,
        collectionKeys: collectionKeys,
        itemIndex: itemIndex,
        values: <String, Object?>{xKey: x, yKey: y},
        policies: focalPolicies,
        identityKey: identityKey,
        identityValue: identityValue,
      ),
      customizeUrl: urlBinding.customize,
      resetUrl: urlBinding.reset,
      customizeFocal: () {
        for (final key in <String>[xKey, yKey]) {
          provider.setRepeaterFieldWriteScope(
            blockId: blockId,
            collectionKeys: collectionKeys,
            itemIndex: itemIndex,
            propertyKey: key,
            policy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
            scope: WebsiteWriteScope.viewport,
            identityKey: identityKey,
            identityValue: identityValue,
          );
        }
      },
      resetFocal: () => provider.clearBlockRepeaterItemResponsiveOverrides(
        blockId,
        collectionKeys: collectionKeys,
        itemIndex: itemIndex,
        propertyKeys: <String>[xKey, yKey],
        policies: focalPolicies,
        legacyPropertyKeys: <String, Iterable<String>>{
          xKey: legacyX,
          yKey: legacyY,
        },
        identityKey: identityKey,
        identityValue: identityValue,
      ),
    );
  }
}
