import 'package:flutter/foundation.dart';

import '../models/website_block_definition.dart';
import '../models/website_canvas_responsive_document.dart';
import '../models/website_responsive_authoring.dart';
import '../models/website_responsive_field_state.dart';
import '../providers/website_edit_mode_provider.dart';

/// The one authority the Canvas inspector uses for a responsive field.
///
/// It is to Canvas what `WebsiteResponsiveScalarBinding` is to a schema block,
/// and it deliberately owns no resolution of its own: the visible value comes
/// from the 7A projection, the policy comes from
/// [WebsiteCanvasResponsivePolicy], and every write goes through the atomic
/// commands. One binding serves the block root and a layer, standalone or
/// inside a carousel slide — the target is just an address.
///
/// What it adds over calling the commands directly is the authoring state a
/// `ResponsiveFieldShell` needs — inherited / customised / unavailable — plus
/// the per-field transient scope, so "Personalizar" on one property does not
/// silently promote the next write of another.
/// What ONE Canvas document still carries from the pre-7A model.
///
/// The analysis itself is unchanged — [WebsiteCanvasMigration.analyze] remains
/// the only authority on what is legacy — but the inspector resolves dozens of
/// fields per rebuild against the same document, and running a whole document
/// analysis once per field is the difference between a cheap surface and a
/// visible stall. A surface computes this once and hands it to every binding.
@immutable
class WebsiteCanvasLegacyInventory {
  const WebsiteCanvasLegacyInventory({required this.twinLayerIds});

  /// A document with nothing legacy in it.
  static const WebsiteCanvasLegacyInventory none =
      WebsiteCanvasLegacyInventory(twinLayerIds: <String>{});

  /// Layer identities that reach their values through a legacy
  /// `_desktop`/`_mobile` twin — merged pairs and the ambiguous ones alike.
  ///
  /// `analyze` is the owner's pure inspection: it reports, it never migrates
  /// and it never writes.
  factory WebsiteCanvasLegacyInventory.of(Map<String, dynamic> document) {
    final analysis = WebsiteCanvasMigration.analyze(document);
    final ids = <String>{};
    for (final issue in analysis.issues) {
      ids.addAll(issue.layerIds);
    }
    for (final stem in analysis.mergedStems) {
      ids.add('$stem${WebsiteCanvasMigration.desktopSuffix}');
      ids.add('$stem${WebsiteCanvasMigration.mobileSuffix}');
    }
    return WebsiteCanvasLegacyInventory(
      twinLayerIds: Set<String>.unmodifiable(ids),
    );
  }

  final Set<String> twinLayerIds;

  bool isTwinLayer(String layerId) => twinLayerIds.contains(layerId.trim());
}

class WebsiteCanvasFieldBinding<T> {
  const WebsiteCanvasFieldBinding({
    required this.state,
    required this.write,
    required this.writeMany,
    required this.customize,
    required this.reset,
    required this.scopeKey,
    required this.isLegacyValue,
  });

  /// Resolved inheritance for the field. Feeds `ResponsiveFieldShell`.
  final WebsiteResponsiveFieldState<T> state;

  /// Persists this property at the scope the state resolved.
  final ValueChanged<Object?> write;

  /// Persists SEVERAL properties as one transaction — `x`+`y`, `w`+`h` and
  /// focal `x`+`y` are single operations, not two writes the operator can
  /// undo apart.
  final void Function(Map<String, Object?> values) writeMany;

  /// Promotes the next write of THIS field to a viewport override.
  final VoidCallback customize;

  /// Removes the override and returns the field to the shared value. It never
  /// copies the shared value over the override.
  final VoidCallback reset;

  /// Identity of the transient scope: block + slide + root/layer + property.
  final String scopeKey;

  /// Whether the effective value reaches this field through a legacy alias or
  /// twin rather than the canonical branch.
  ///
  /// 7B-3A is read-only about legacy: the value stays visible and is reported
  /// as earlier configuration, and the ambiguous mutation is blocked instead
  /// of being resolved by guesswork. The deliberate migration is 7B-3B.
  final bool isLegacyValue;

  /// The effective value for the previewed viewport.
  T? get value => state.resolved.value;

  /// Builds the binding for one Canvas property.
  ///
  /// [layerId] null addresses the block root; [slideIndex] null addresses a
  /// standalone Canvas block.
  static WebsiteCanvasFieldBinding<T>? resolve<T>({
    required WebsiteEditModeProvider provider,
    required String blockId,
    required String propertyKey,
    required String label,
    required WebsiteResponsiveDecoder<T> decode,
    int? slideIndex,
    String? layerId,
    WebsiteBlockFieldType type = WebsiteBlockFieldType.text,
    WebsiteCanvasLegacyInventory? legacyInventory,
  }) {
    final document = provider.canvasDocument(blockId, slideIndex: slideIndex);
    if (document == null) return null;

    final viewport = provider.previewViewport;
    final isLayer = layerId != null;

    Map<String, dynamic>? source;
    Map<String, dynamic>? effective;
    WebsiteResponsivePropertyPolicy policy;
    String? unavailableReason;

    if (isLayer) {
      final raw = document[WebsiteCanvasResponsivePolicy.elementsKey];
      if (raw is! List) return null;
      for (final item in raw) {
        if (item is Map && item['id']?.toString().trim() == layerId.trim()) {
          source = Map<String, dynamic>.from(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          break;
        }
      }
      if (source == null) return null;

      // The visible value is the PROJECTED one, never the raw base.
      for (final projected in WebsiteCanvasResponsiveDocument.projectLayers(
        data: document,
        viewport: viewport,
      )) {
        if (projected.id == layerId.trim()) {
          effective = projected.data;
          // Effective visibility is a resolved fact of the projection, not a
          // key the layer necessarily carries: a legacy `hideOnMobile` layer
          // has no `visible` at all and would otherwise read as null.
          if (propertyKey == WebsiteCanvasResponsivePolicy.visibleKey) {
            effective = <String, dynamic>{
              ...effective,
              WebsiteCanvasResponsivePolicy.visibleKey: projected.visible,
            };
          }
          break;
        }
      }
      final kind = WebsiteCanvasLayerKind.fromRaw(source['type']);
      policy = WebsiteCanvasResponsivePolicy.layerPolicyFor(kind, propertyKey);
      if (policy.supportsViewportOverride &&
          !WebsiteCanvasResponsivePolicy.isOverridableForLayer(
            source,
            propertyKey,
          )) {
        unavailableReason =
            'Esta capa toma su imagen del producto, así que no puede tener '
            'una versión distinta por dispositivo.';
      }
    } else {
      source = document;
      effective = WebsiteCanvasResponsiveDocument.project(
        data: document,
        viewport: viewport,
      );
      policy = WebsiteCanvasResponsivePolicy.rootPolicyFor(propertyKey);
    }
    effective ??= source;

    final hasOverride = policy.supportsViewportOverride &&
        WebsiteResponsiveDataCodec.hasOverride(source, propertyKey, viewport);
    final legacyAlias = isLayer
        ? null
        : WebsiteCanvasResponsivePolicy.legacyRootMobileAliases[propertyKey];
    // A layer that belongs to a `_desktop`/`_mobile` pair carries EVERY one of
    // its values through that twin, not just its visibility, so any field of
    // it is legacy. The inventory is the owner's own pure analysis — it
    // inspects, it never migrates — resolved once per surface when the caller
    // supplies it and lazily otherwise.
    final isTwinLayer = isLayer &&
        (legacyInventory ?? WebsiteCanvasLegacyInventory.of(document))
            .isTwinLayer(layerId);
    final hasLegacy = !hasOverride &&
        (isTwinLayer ||
            (policy.supportsViewportOverride &&
                viewport == WebsiteViewport.mobile &&
                ((legacyAlias != null && source.containsKey(legacyAlias)) ||
                    (isLayer &&
                        propertyKey ==
                            WebsiteCanvasResponsivePolicy.visibleKey &&
                        WebsiteCanvasResponsivePolicy.legacyLayerVisibilityKeys
                            .any(source.containsKey)))));

    final resolved = WebsiteResolvedResponsiveValue<T>(
      shared:
          source.containsKey(propertyKey) ? decode(source[propertyKey]) : null,
      value: decode(effective[propertyKey]),
      viewport: viewport,
      isOverride: hasOverride || hasLegacy,
      isLegacyOverride: hasLegacy,
    );

    final scopeKey = provider.canvasFieldScopeKey(
      blockId: blockId,
      slideIndex: slideIndex,
      layerId: layerId,
      propertyKey: propertyKey,
      viewport: viewport,
    );
    final context = WebsiteAuthoringContext(
      hostClass: WebsiteAuthoringHostClass.desktop,
      previewViewport: viewport,
      writeScope: provider.canvasFieldScope(
        scopeKey,
        policy: policy,
        viewport: viewport,
      ),
    );

    // A legacy value is readable but not safely mutable in this round: which
    // branch a write should land in is exactly the ambiguity 7B-3B resolves.
    final blocked = unavailableReason ??
        (hasLegacy
            ? 'Este valor viene de una configuración anterior. Revísalo en la '
                'migración antes de cambiarlo por dispositivo.'
            : null);

    final state = WebsiteResponsiveFieldState<T>.resolve(
      schema: WebsiteBlockFieldSchema(
        key: propertyKey,
        label: label,
        type: type,
        responsivePolicy: policy,
      ),
      context: context,
      resolved: resolved,
      unavailableReason: blocked,
    );

    void writeMany(Map<String, Object?> values) {
      if (blocked != null || values.isEmpty) return;
      // Resolved AT WRITE TIME, not captured when the binding was built, so
      // `customize()` followed by `write()` on the same instance lands in the
      // viewport branch the user just asked for.
      final scope = provider.canvasFieldScope(
        scopeKey,
        policy: policy,
        viewport: viewport,
      );
      if (isLayer) {
        provider.setCanvasLayerProperties(
          blockId,
          layerId,
          values,
          slideIndex: slideIndex,
          scope: scope,
          viewport: viewport,
        );
        return;
      }
      provider.setCanvasRootProperties(
        blockId,
        values,
        slideIndex: slideIndex,
        scope: scope,
        viewport: viewport,
      );
    }

    return WebsiteCanvasFieldBinding<T>(
      state: state,
      scopeKey: scopeKey,
      isLegacyValue: hasLegacy,
      write: (value) => writeMany(<String, Object?>{propertyKey: value}),
      writeMany: writeMany,
      customize: () => provider.setCanvasFieldScope(
        scopeKey,
        WebsiteWriteScope.viewport,
        policy: policy,
        viewport: viewport,
      ),
      reset: () {
        if (blocked != null) return;
        if (isLayer) {
          provider.clearCanvasLayerOverrides(
            blockId,
            layerId,
            <String>[propertyKey],
            slideIndex: slideIndex,
            viewport: viewport,
          );
        } else {
          provider.clearCanvasRootOverrides(
            blockId,
            <String>[propertyKey],
            slideIndex: slideIndex,
            viewport: viewport,
          );
        }
        provider.setCanvasFieldScope(
          scopeKey,
          WebsiteWriteScope.shared,
          policy: policy,
          viewport: viewport,
        );
      },
    );
  }
}
