import 'website_block_capabilities.dart';
import 'website_block_geometry.dart';
import 'website_block_public_visibility.dart';
import 'website_block_registry.dart';
import 'website_block_type.dart';
import 'website_responsive_authoring.dart';
import 'website_responsive_projection.dart';

/// Explicit presentation mode for one website page composition.
///
/// Edit is the only mode that keeps hidden blocks in the projection so the
/// editor can repair them. Preview and public deliberately share the same
/// visibility semantics.
enum WebsitePageCompositionMode {
  edit,
  preview,
  public,
}

/// Canonical geometry capability for a registered website block type.
///
/// The registry remains the owner of block definitions and their defaults.
/// This profile adds the page-composition behavior that the current registry
/// does not yet model explicitly.
class WebsitePageBlockGeometryProfile {
  const WebsitePageBlockGeometryProfile({
    required this.heightBehavior,
    required this.defaultFullBleed,
  });

  final WebsitePageBlockHeightBehavior heightBehavior;
  final bool defaultFullBleed;

  static WebsitePageBlockGeometryProfile forType(WebsiteBlockType? type) {
    if (type == null) {
      return const WebsitePageBlockGeometryProfile(
        heightBehavior: WebsitePageBlockHeightBehavior.intrinsic,
        defaultFullBleed: false,
      );
    }

    final definition = WebsiteBlockRegistry.definitionFor(type);
    final registeredFullBleed =
        _parseBoolean(definition.defaultData['fullBleed']);

    return WebsitePageBlockGeometryProfile(
      heightBehavior:
          WebsiteBlockCapabilityRegistry.profileFor(type).heightBehavior,
      defaultFullBleed: registeredFullBleed ??
          switch (type) {
            WebsiteBlockType.hero ||
            WebsiteBlockType.carousel ||
            WebsiteBlockType.categoryGrid ||
            WebsiteBlockType.videoBanner ||
            WebsiteBlockType.partnersBanner =>
              true,
            _ => false,
          },
    );
  }
}

/// Normalized, mode-independent geometry for one projected page block.
class WebsitePageBlockGeometry {
  const WebsitePageBlockGeometry({
    required this.spacingAfter,
    required this.fullBleed,
    required this.heightBehavior,
    required this.blockHeight,
  });

  final double spacingAfter;
  final bool fullBleed;
  final WebsitePageBlockHeightBehavior heightBehavior;

  /// A finite positive height for exact/minimum profiles, otherwise `null`.
  final double? blockHeight;

  double? get exactHeight =>
      heightBehavior == WebsitePageBlockHeightBehavior.exact
          ? blockHeight
          : null;

  double? get minimumHeight =>
      heightBehavior == WebsitePageBlockHeightBehavior.minimum
          ? blockHeight
          : null;
}

/// Immutable projection of one persisted/draft block.
class WebsitePageCompositionBlock {
  const WebsitePageCompositionBlock({
    required this.sourceBlock,
    required this.blockData,
    required this.id,
    required this.blockType,
    required this.type,
    required this.orderIndex,
    required this.sourceIndex,
    required this.isGloballyVisible,
    required this.responsiveVisibility,
    required this.geometry,
  });

  /// Deep, unmodifiable copy of the complete input row.
  final Map<String, dynamic> sourceBlock;

  /// Deep, unmodifiable copy of `block_data`.
  final Map<String, dynamic> blockData;

  final String id;
  final String blockType;
  final WebsiteBlockType? type;
  final int orderIndex;

  /// Original position, used as the deterministic tie-breaker for equal order.
  final int sourceIndex;

  /// Mirrors the canonical public helper: only the boolean value `false`
  /// globally hides a block.
  final bool isGloballyVisible;
  final Map<String, bool> responsiveVisibility;
  final WebsitePageBlockGeometry geometry;
}

/// Pure, immutable page projection shared by Edit, Preview and public modes.
///
/// This model owns no provider, service, URL state, loading lifecycle or
/// persistence. Consumers resolve the active document first, then project it
/// through this value.
class WebsitePageComposition {
  WebsitePageComposition._({
    required this.mode,
    required this.breakpoint,
    required this.logicalWidth,
    required this.blocks,
  });

  static const double defaultSectionSpacing = 64;
  static const double minimumSpacing = 0;
  static const double maximumSpacing = 200;

  static double resolveSectionSpacing(dynamic raw) {
    return _normalizeSpacing(raw, fallback: defaultSectionSpacing);
  }

  static double resolveSpacingAfter(
    dynamic raw, {
    required double sectionSpacing,
  }) {
    return _normalizeSpacing(
      raw,
      fallback: resolveSectionSpacing(sectionSpacing),
    );
  }

  final WebsitePageCompositionMode mode;
  final String breakpoint;
  final double? logicalWidth;
  final List<WebsitePageCompositionBlock> blocks;

  /// Projects blocks that are reachable on at least one public breakpoint.
  ///
  /// Trust/index eligibility needs this broader view than one active viewport,
  /// but ordering and visibility must still remain owned by this compositor.
  static List<WebsitePageCompositionBlock> projectPubliclyReachableBlocks(
    Iterable<Map<String, dynamic>> blocks, {
    double sectionSpacing = defaultSectionSpacing,
  }) {
    final reachable = blocks.where(
      (block) => websitePublicBreakpoints.any(
        (breakpoint) =>
            isWebsiteBlockVisibleAtPublicBreakpoint(block, breakpoint),
      ),
    );
    return WebsitePageComposition.project(
      blocks: reachable,
      mode: WebsitePageCompositionMode.edit,
      breakpoint: 'desktop',
      sectionSpacing: sectionSpacing,
    ).blocks;
  }

  factory WebsitePageComposition.project({
    required Iterable<Map<String, dynamic>> blocks,
    required WebsitePageCompositionMode mode,
    required String breakpoint,
    double? logicalWidth,
    double sectionSpacing = defaultSectionSpacing,
  }) {
    final normalizedBreakpoint = breakpoint.trim().toLowerCase();
    if (!websitePublicBreakpoints.contains(normalizedBreakpoint)) {
      throw ArgumentError.value(
        breakpoint,
        'breakpoint',
        'Expected one of ${websitePublicBreakpoints.join(', ')}.',
      );
    }
    if (logicalWidth != null && (!logicalWidth.isFinite || logicalWidth <= 0)) {
      throw ArgumentError.value(
        logicalWidth,
        'logicalWidth',
        'Expected a finite positive storefront-canvas width.',
      );
    }

    final normalizedSectionSpacing = resolveSectionSpacing(sectionSpacing);
    final projected = <WebsitePageCompositionBlock>[];

    var sourceIndex = 0;
    for (final inputBlock in blocks) {
      final copiedBlock = _deepCopyStringMap(inputBlock);
      final copiedDataValue = copiedBlock['block_data'];
      final copiedData = copiedDataValue is Map<String, dynamic>
          ? copiedDataValue
          : const <String, dynamic>{};

      final shouldInclude = mode == WebsitePageCompositionMode.edit ||
          (logicalWidth != null
              ? isWebsiteBlockVisibleAtLogicalWidth(
                  copiedBlock,
                  logicalWidth,
                )
              : isWebsiteBlockVisibleAtPublicBreakpoint(
                  copiedBlock,
                  normalizedBreakpoint,
                ));

      if (shouldInclude) {
        final rawType = (copiedBlock['block_type'] ?? '').toString().trim();
        final type = _tryParseWebsiteBlockType(rawType);
        final profile = WebsitePageBlockGeometryProfile.forType(type);
        final layoutData = logicalWidth == null
            ? copiedData
            : WebsiteResponsiveBlockProjection.projectMeta(
                data: copiedData,
                viewport: WebsiteResponsiveDataCodec.viewportForDocumentWidth(
                  copiedData,
                  logicalWidth,
                ),
              );
        final explicitFullBleed = _parseBoolean(layoutData['fullBleed']);
        final rawBlockHeight = _finiteDouble(layoutData['blockHeight']);
        final normalizedBlockHeight =
            profile.heightBehavior == WebsitePageBlockHeightBehavior.intrinsic
                ? null
                : rawBlockHeight != null && rawBlockHeight > 0
                    ? rawBlockHeight
                    : null;

        projected.add(
          WebsitePageCompositionBlock(
            sourceBlock: copiedBlock,
            blockData: copiedData,
            id: (copiedBlock['id'] ?? '').toString(),
            blockType: rawType,
            type: type,
            orderIndex: _resolveOrderIndex(copiedBlock),
            sourceIndex: sourceIndex,
            isGloballyVisible: copiedBlock['is_visible'] != false,
            responsiveVisibility: normalizeWebsiteBlockPublicVisibility(
              copiedData['visibility'],
            ),
            geometry: WebsitePageBlockGeometry(
              spacingAfter: resolveSpacingAfter(
                layoutData['spacingAfter'],
                sectionSpacing: normalizedSectionSpacing,
              ),
              fullBleed: explicitFullBleed ?? profile.defaultFullBleed,
              heightBehavior: profile.heightBehavior,
              blockHeight: normalizedBlockHeight,
            ),
          ),
        );
      }

      sourceIndex += 1;
    }

    projected.sort((left, right) {
      final byOrder = left.orderIndex.compareTo(right.orderIndex);
      if (byOrder != 0) return byOrder;
      return left.sourceIndex.compareTo(right.sourceIndex);
    });

    return WebsitePageComposition._(
      mode: mode,
      breakpoint: normalizedBreakpoint,
      logicalWidth: logicalWidth,
      blocks: List<WebsitePageCompositionBlock>.unmodifiable(projected),
    );
  }
}

WebsiteBlockType? _tryParseWebsiteBlockType(String raw) {
  final normalized = raw.trim().toLowerCase();
  for (final type in WebsiteBlockType.values) {
    if (type.name.toLowerCase() == normalized) return type;
  }
  return null;
}

int _resolveOrderIndex(Map<String, dynamic> block) {
  return _parseOrderIndex(block['order_index']) ??
      _parseOrderIndex(block['sort_order']) ??
      0;
}

int? _parseOrderIndex(dynamic raw) {
  if (raw is int) return raw;

  final parsed = switch (raw) {
    num value => value.toDouble(),
    String value => double.tryParse(value.trim()),
    _ => null,
  };
  if (parsed == null || !parsed.isFinite) return null;
  if (parsed != parsed.truncateToDouble()) return null;
  return parsed.toInt();
}

double _normalizeSpacing(
  dynamic raw, {
  required double fallback,
}) {
  final normalizedFallback = fallback.isFinite
      ? fallback
          .clamp(
            WebsitePageComposition.minimumSpacing,
            WebsitePageComposition.maximumSpacing,
          )
          .toDouble()
      : WebsitePageComposition.defaultSectionSpacing;
  final parsed = _finiteDouble(raw);
  if (parsed == null) return normalizedFallback;
  return parsed
      .clamp(
        WebsitePageComposition.minimumSpacing,
        WebsitePageComposition.maximumSpacing,
      )
      .toDouble();
}

double? _finiteDouble(dynamic raw) {
  final parsed = switch (raw) {
    num value => value.toDouble(),
    String value => double.tryParse(value.trim()),
    _ => null,
  };
  return parsed != null && parsed.isFinite ? parsed : null;
}

bool? _parseBoolean(dynamic raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    return switch (raw.trim().toLowerCase()) {
      'true' || '1' || 'si' || 'sí' => true,
      'false' || '0' || 'no' => false,
      _ => null,
    };
  }
  return null;
}

Map<String, dynamic> _deepCopyStringMap(Map<dynamic, dynamic> source) {
  final copy = <String, dynamic>{};
  source.forEach((key, value) {
    copy[key.toString()] = _deepCopyValue(value);
  });
  return Map<String, dynamic>.unmodifiable(copy);
}

dynamic _deepCopyValue(dynamic value) {
  if (value is Map) return _deepCopyStringMap(value);
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_deepCopyValue));
  }
  if (value is Set) {
    return Set<dynamic>.unmodifiable(value.map(_deepCopyValue));
  }
  return value;
}
