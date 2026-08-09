import 'website_responsive_authoring.dart';

/// Canvas layer types the editor can create today.
///
/// An unrecognised `type` is not an error: it keeps every property shared, so
/// a document written by a newer editor can never lose data through this
/// layer.
enum WebsiteCanvasLayerKind {
  text,
  button,
  image,
  shape,
  product,
  productsGallery,
  unknown;

  static WebsiteCanvasLayerKind fromRaw(Object? raw) {
    final value = raw?.toString().trim();
    return switch (value) {
      'text' => WebsiteCanvasLayerKind.text,
      'button' => WebsiteCanvasLayerKind.button,
      'image' => WebsiteCanvasLayerKind.image,
      'shape' => WebsiteCanvasLayerKind.shape,
      'product' => WebsiteCanvasLayerKind.product,
      'productsGallery' => WebsiteCanvasLayerKind.productsGallery,
      _ => WebsiteCanvasLayerKind.unknown,
    };
  }
}

/// The declared responsive policy of every Canvas property.
///
/// Two rules make this table safe to extend:
///
/// * an **unknown key is shared**, so a property nobody classified can never
///   silently become a per-viewport value; and
/// * a property is responsive only when the real Canvas consumer already
///   honours it — the table below was written against `canvas_block.dart` and
///   `canvas_element_factory.dart`, not against what would be convenient.
abstract final class WebsiteCanvasResponsivePolicy {
  /// The persisted collection of layers. It is NEVER a responsive override:
  /// a viewport may reposition, restyle or hide a layer, never own a second
  /// list.
  static const String elementsKey = 'elements';

  /// Canonical typed visibility, which replaces the contradictory
  /// `hideOnMobile`/`showOnMobile` pair.
  static const String visibleKey = 'visible';

  /// Per-viewport z-order EXCEPTION.
  ///
  /// The base order is the layer's position in [elementsKey] — one authority,
  /// the one every existing reorder path already writes. This key exists only
  /// inside a viewport override and only when a legacy pair proved the two
  /// viewports really were ordered differently. Nothing reads or writes it at
  /// the top level.
  static const String orderKey = 'order';

  /// Keys that may never live INSIDE a viewport override.
  ///
  /// The list is deliberately the one key with a proven transient owner rather
  /// than a plausible scrub list: `sanitizeWebsiteBlockDataForPersistence`
  /// already established that `activeElementId` is editor selection at a
  /// Canvas root and at a Carousel slide, while the same key is legitimate
  /// authored content inside a layer. A per-viewport selection, however, is
  /// meaningless anywhere, so it is removed from override maps at every depth
  /// — and never from a layer's own top level, which is not this owner's rule
  /// to make.
  static const Set<String> transientOverrideKeys = <String>{
    'activeElementId',
  };

  /// Legacy keys the read adapter understands and the canonical form absorbs.
  static const Set<String> legacyLayerVisibilityKeys = <String>{
    'hideOnMobile',
    'showOnMobile',
  };

  /// The override keys this owner accepts for the block root.
  static Set<String> allowedRootOverrideKeys() => <String>{
        for (final entry in _rootPolicies.entries)
          if (entry.value.supportsViewportOverride) entry.key,
      };

  /// The override keys this owner accepts for a layer of [kind].
  static Set<String> allowedLayerOverrideKeys(WebsiteCanvasLayerKind kind) =>
      <String>{
        for (final entry in layerPolicies(kind).entries)
          if (entry.value.supportsViewportOverride) entry.key,
      };

  static const Map<String, String> legacyRootMobileAliases = <String, String>{
    'designWidth': 'mobileDesignWidth',
    'focalPointX': 'mobileFocalPointX',
    'focalPointY': 'mobileFocalPointY',
  };

  static const Map<String, WebsiteResponsivePropertyPolicy> _rootPolicies =
      <String, WebsiteResponsivePropertyPolicy>{
    // Geometry of the block and of its coordinate space.
    'designWidth': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'blockHeight': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'heightMode': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'vhPct': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'focalPointX': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'focalPointY': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    // Background media and its presentation: art direction of the same
    // section, which is exactly what a phone frame needs.
    'backgroundColor': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'backgroundImageUrl': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'backgroundVideoUrl': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'backgroundYoutubeId': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'backgroundFit': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'overlayEnabled': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'overlayOpacity': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'overlayColor': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'fullBleed': WebsiteResponsivePropertyPolicy.responsiveOptional,
    // Description of the same subject, authoring rules and the collection
    // itself stay common.
    'backgroundImageAltText': WebsiteResponsivePropertyPolicy.sharedOnly,
    'showGrid': WebsiteResponsivePropertyPolicy.sharedOnly,
    'gridSize': WebsiteResponsivePropertyPolicy.sharedOnly,
    'snap': WebsiteResponsivePropertyPolicy.sharedOnly,
    'snapDistance': WebsiteResponsivePropertyPolicy.sharedOnly,
    'constrainElementsToSafeArea': WebsiteResponsivePropertyPolicy.sharedOnly,
    elementsKey: WebsiteResponsivePropertyPolicy.sharedOnly,
  };

  static const Map<String, WebsiteResponsivePropertyPolicy> _commonLayer =
      <String, WebsiteResponsivePropertyPolicy>{
    'x': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'y': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'w': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'h': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    'rotation': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    orderKey: WebsiteResponsivePropertyPolicy.perViewportGeometry,
    visibleKey: WebsiteResponsivePropertyPolicy.responsiveVisibility,
    'anim': WebsiteResponsivePropertyPolicy.responsiveOptional,
    'id': WebsiteResponsivePropertyPolicy.sharedOnly,
    'type': WebsiteResponsivePropertyPolicy.sharedOnly,
    'locked': WebsiteResponsivePropertyPolicy.sharedOnly,
  };

  static const Map<WebsiteCanvasLayerKind,
          Map<String, WebsiteResponsivePropertyPolicy>> _byKind =
      <WebsiteCanvasLayerKind, Map<String, WebsiteResponsivePropertyPolicy>>{
    WebsiteCanvasLayerKind.text: <String, WebsiteResponsivePropertyPolicy>{
      'text': WebsiteResponsivePropertyPolicy.sharedOnly,
      'fontRole': WebsiteResponsivePropertyPolicy.sharedOnly,
      'fontSize': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'fontWeight': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'color': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'align': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'letterSpacing': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'lineHeight': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'uppercase': WebsiteResponsivePropertyPolicy.responsiveOptional,
    },
    WebsiteCanvasLayerKind.button: <String, WebsiteResponsivePropertyPolicy>{
      'label': WebsiteResponsivePropertyPolicy.sharedOnly,
      'link': WebsiteResponsivePropertyPolicy.sharedOnly,
      'style': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'inheritTheme': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'bgColor': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'fgColor': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'radius': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'fontSize': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'letterSpacing': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'uppercase': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'shadow': WebsiteResponsivePropertyPolicy.responsiveOptional,
    },
    WebsiteCanvasLayerKind.image: <String, WebsiteResponsivePropertyPolicy>{
      'productId': WebsiteResponsivePropertyPolicy.sharedOnly,
      'imageSource': WebsiteResponsivePropertyPolicy.sharedOnly,
      'altText': WebsiteResponsivePropertyPolicy.sharedOnly,
      'imageUrl': WebsiteResponsivePropertyPolicy.responsiveOptional,
      // These three describe the state of the EFFECTIVE `imageUrl`, so they
      // must diverge exactly where it can. Left shared, removing or restoring
      // a background on a phone that carries its own picture would rewrite the
      // desktop layer's provenance and its restore target.
      'backgroundRemovalActive':
          WebsiteResponsivePropertyPolicy.responsiveOptional,
      'backgroundRemovalOriginalUrl':
          WebsiteResponsivePropertyPolicy.responsiveOptional,
      'backgroundRemovalMethod':
          WebsiteResponsivePropertyPolicy.responsiveOptional,
      'fit': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'radius': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'focalPointX': WebsiteResponsivePropertyPolicy.perViewportGeometry,
      'focalPointY': WebsiteResponsivePropertyPolicy.perViewportGeometry,
    },
    WebsiteCanvasLayerKind.shape: <String, WebsiteResponsivePropertyPolicy>{
      'shape': WebsiteResponsivePropertyPolicy.sharedOnly,
      'fillColor': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'borderColor': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'borderWidth': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'radius': WebsiteResponsivePropertyPolicy.responsiveOptional,
    },
    WebsiteCanvasLayerKind.product: <String, WebsiteResponsivePropertyPolicy>{
      'productId': WebsiteResponsivePropertyPolicy.sharedOnly,
      'showPrice': WebsiteResponsivePropertyPolicy.sharedOnly,
    },
    WebsiteCanvasLayerKind.productsGallery:
        <String, WebsiteResponsivePropertyPolicy>{
      'mode': WebsiteResponsivePropertyPolicy.sharedOnly,
      'productIds': WebsiteResponsivePropertyPolicy.sharedOnly,
      'maxProducts': WebsiteResponsivePropertyPolicy.sharedOnly,
      'showPrice': WebsiteResponsivePropertyPolicy.sharedOnly,
      'layout': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'columns': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'cardWidth': WebsiteResponsivePropertyPolicy.responsiveOptional,
    },
    WebsiteCanvasLayerKind.unknown: <String, WebsiteResponsivePropertyPolicy>{},
  };

  static WebsiteResponsivePropertyPolicy rootPolicyFor(String key) =>
      _rootPolicies[key] ?? WebsiteResponsivePropertyPolicy.sharedOnly;

  static WebsiteResponsivePropertyPolicy layerPolicyFor(
    WebsiteCanvasLayerKind kind,
    String key,
  ) {
    final common = _commonLayer[key];
    if (common != null) return common;
    return _byKind[kind]?[key] ?? WebsiteResponsivePropertyPolicy.sharedOnly;
  }

  static Map<String, WebsiteResponsivePropertyPolicy> rootPolicies() =>
      Map<String, WebsiteResponsivePropertyPolicy>.unmodifiable(_rootPolicies);

  static Map<String, WebsiteResponsivePropertyPolicy> layerPolicies(
    WebsiteCanvasLayerKind kind,
  ) {
    return Map<String, WebsiteResponsivePropertyPolicy>.unmodifiable({
      ..._commonLayer,
      ...?_byKind[kind],
    });
  }

  /// Whether THIS layer can really override [key] right now.
  ///
  /// The schema policy answers "may this property diverge at all". This adds
  /// the one instance condition the Canvas consumer imposes: a product-bound
  /// image resolves its asset from the product, so an art-directed URL would
  /// change nothing on screen. The later inspector shows it unavailable with
  /// that reason instead of offering a control that does nothing.
  static bool isOverridableForLayer(Map<String, dynamic> layer, String key) {
    final kind = WebsiteCanvasLayerKind.fromRaw(layer['type']);
    if (!layerPolicyFor(kind, key).supportsViewportOverride) return false;
    if (kind == WebsiteCanvasLayerKind.image && key == 'imageUrl') {
      final productId = layer['productId']?.toString().trim() ?? '';
      final source =
          (layer['imageSource'] ?? (productId.isEmpty ? 'manual' : 'product'))
              .toString();
      if (productId.isNotEmpty && source != 'manual') return false;
    }
    return true;
  }
}

/// One layer, resolved for a viewport.
class WebsiteCanvasLayerProjection {
  const WebsiteCanvasLayerProjection({
    required this.id,
    required this.kind,
    required this.data,
    required this.visible,
    required this.order,
  });

  final String id;
  final WebsiteCanvasLayerKind kind;

  /// The effective values for this viewport. Business content is the shared
  /// one; presentation may be the override.
  final Map<String, dynamic> data;
  final bool visible;

  /// `responsive.<viewport>.order` when the document declares one, otherwise
  /// the layer's position in the persisted list.
  final int order;
}

/// The pure Canvas responsive owner: read, project, normalise and write.
///
/// It touches no widget, no provider and no persistence. Every function takes
/// a document and returns a NEW document; the input map, its lists and its
/// nested maps are never mutated.
abstract final class WebsiteCanvasResponsiveDocument {
  /// The Canvas renderer's own compact threshold, kept here as the documented
  /// fact it is: legacy Canvas presentation switches at 600 logical px while
  /// canonical responsive authoring uses the shared 600/900 bands. The
  /// renderer and command owner both consume
  /// [viewportForRenderedCanvasWidth], so there is no second classifier.
  static const double legacyCanvasCompactWidth = 600;

  /// The persisted marker that says "this Canvas speaks the canonical
  /// contract".
  ///
  /// It exists because a document can be fully canonical and still carry no
  /// override at all — identical twins merge into one layer with nothing to
  /// override, and normalisation correctly removes the empty container. Without
  /// its own marker such a document would fall back to the legacy bands and
  /// silently change what a 620 px canvas shows. It is a single authority: an
  /// artificial empty `responsive` map is never written to stand in for it.
  static const String schemaVersionKey = 'canvasResponsiveVersion';
  static const int schemaVersion = 2;

  /// The Canvas document one composed Carousel slide exposes to authoring.
  ///
  /// A Carousel slide owns campaign fields as well as a nested Canvas. The
  /// renderer historically synthesized this Canvas inline while the command
  /// binding read the raw slide map, so an optimistic touch lease compared two
  /// different vocabularies and failed closed. This pure projection is now the
  /// single read owner used by renderer, binding and provider.
  ///
  /// [showGrid] is transient renderer state. Direct manipulation exists only
  /// in Edit, where all three transaction participants pass `true`; Preview
  /// and Public may render `false` because they own no manipulation lease.
  static Map<String, dynamic> carouselAuthoringDocument({
    required Map<String, dynamic> slide,
    required bool showGrid,
  }) {
    final rawElements = slide[WebsiteCanvasResponsivePolicy.elementsKey];
    final elements = rawElements is List
        ? rawElements
            .whereType<Map>()
            .map(
              (element) => _deepCopyMap(
                Map<String, dynamic>.from(element),
              ),
            )
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return <String, dynamic>{
      'backgroundColor': '#00000000',
      'showGrid': showGrid,
      'snap': true,
      'designWidth': (slide['designWidth'] as num?)?.toDouble() ?? 1200.0,
      'mobileDesignWidth':
          (slide['mobileDesignWidth'] as num?)?.toDouble() ?? 390.0,
      'constrainElementsToSafeArea':
          slide['constrainElementsToSafeArea'] != false,
      'blockHeight': (slide['designHeight'] as num?)?.toDouble() ?? 750.0,
      WebsiteCanvasResponsivePolicy.elementsKey: elements,
      ..._carouselResponsiveContract(slide),
    };
  }

  /// Forwards only the nested Canvas root override vocabulary.
  ///
  /// An unversioned legacy responsive container is deliberately ignored: its
  /// aliases belong to the slide, not automatically to the nested Canvas.
  static Map<String, dynamic> _carouselResponsiveContract(
    Map<String, dynamic> slide,
  ) {
    final marker = slide[schemaVersionKey];
    final rawContainer = slide[WebsiteResponsiveDataCodec.containerKey];
    final containerVersion = rawContainer is Map
        ? rawContainer[WebsiteResponsiveDataCodec.versionKey]
        : null;
    final declaresCanonical =
        (marker is num && marker.toInt() >= schemaVersion) ||
            (containerVersion is num &&
                containerVersion.toInt() >=
                    WebsiteResponsiveDataCodec.schemaVersion);
    if (!declaresCanonical) return const <String, dynamic>{};

    final contract = <String, dynamic>{};
    if (marker is num) contract[schemaVersionKey] = marker.toInt();
    if (rawContainer is! Map) return contract;

    final allowed = WebsiteCanvasResponsivePolicy.allowedRootOverrideKeys();
    final container = <String, dynamic>{};
    for (final viewport in WebsiteViewport.values) {
      if (!viewport.supportsOverride) continue;
      final branch = rawContainer[viewport.wireName];
      if (branch is! Map) continue;
      final values = <String, dynamic>{};
      for (final entry in branch.entries) {
        final key = entry.key.toString();
        if (allowed.contains(key)) values[key] = _deepCopy(entry.value);
      }
      if (values.isNotEmpty) container[viewport.wireName] = values;
    }
    if (container.isEmpty) return contract;
    if (containerVersion is num) {
      container[WebsiteResponsiveDataCodec.versionKey] =
          containerVersion.toInt();
    }
    contract[WebsiteResponsiveDataCodec.containerKey] = container;
    return contract;
  }

  /// Stamps the marker. The surface that authors a canonical Canvas — the
  /// migration here, and the editor in 7B — is the one that declares it.
  ///
  /// A version already declared and NEWER than this one is left alone: the
  /// marker belongs to the document, and downgrading it would make a payload
  /// written by a later schema look older than it is.
  static Map<String, dynamic> markCanonical(Map<String, dynamic> data) {
    final next = _deepCopyMap(data);
    final declared = next[schemaVersionKey];
    if (declared is num && declared.toInt() >= schemaVersion) return next;
    next[schemaVersionKey] = schemaVersion;
    return next;
  }

  static bool isCanonical(Map<String, dynamic> data) {
    final declared = data[schemaVersionKey];
    if (declared is num && declared.toInt() >= schemaVersion) return true;
    // A document that already carries canonical overrides is canonical even if
    // an older writer never stamped the marker.
    return WebsiteResponsiveDataCodec.usesCanonicalSchema(data);
  }

  /// The viewport a canvas width belongs to.
  ///
  /// Derived from the CANVAS width and the document's own schema — never from
  /// the ERP window. A canonical document uses the product's 600/900 owner; a
  /// legacy one keeps the approved 640/1024 bands until an explicit migration
  /// stamps [schemaVersionKey].
  static WebsiteViewport viewportForCanvasWidth(
    Map<String, dynamic> data,
    double canvasWidth,
  ) {
    if (isCanonical(data)) {
      return WebsiteViewport.fromLogicalWidth(canvasWidth);
    }
    return WebsiteResponsiveDataCodec.viewportForDocumentWidth(
      data,
      canvasWidth,
    );
  }

  /// The viewport an editable Canvas actually renders at [canvasWidth].
  ///
  /// Canonical documents use the shared 600/900 bands. Legacy Canvas data is
  /// deliberately kept on its historical compact split until an explicit
  /// migration stamps the canonical schema: its mobile aliases and flags have
  /// no independent tablet representation. This is the single projection
  /// rule consumed by both the renderer and the editor command owner.
  static WebsiteViewport viewportForRenderedCanvasWidth(
    Map<String, dynamic> data,
    double canvasWidth,
  ) {
    if (isCanonical(data)) {
      return viewportForCanvasWidth(data, canvasWidth);
    }
    return canvasWidth < legacyCanvasCompactWidth
        ? WebsiteViewport.mobile
        : WebsiteViewport.desktop;
  }

  /// The whole block projected for [viewport]: root presentation resolved and
  /// `elements` replaced by their effective values, in effective order.
  ///
  /// Hidden layers are NOT dropped: Edit must keep them selectable and
  /// repairable. Visitor surfaces filter with [visibleLayers].
  static Map<String, dynamic> project({
    required Map<String, dynamic> data,
    required WebsiteViewport viewport,
  }) {
    final projected = _deepCopyMap(data);
    for (final entry in WebsiteCanvasResponsivePolicy.rootPolicies().entries) {
      if (entry.key == WebsiteCanvasResponsivePolicy.elementsKey) continue;
      final resolved = _resolveProperty(
        source: data,
        key: entry.key,
        policy: entry.value,
        viewport: viewport,
        legacyMobileAlias:
            WebsiteCanvasResponsivePolicy.legacyRootMobileAliases[entry.key],
      );
      if (resolved.exists) projected[entry.key] = _deepCopy(resolved.value);
    }
    projected.remove(WebsiteResponsiveDataCodec.containerKey);

    final layers = projectLayers(data: data, viewport: viewport);
    projected[WebsiteCanvasResponsivePolicy.elementsKey] =
        layers.map((layer) => _deepCopyMap(layer.data)).toList(growable: false);
    return projected;
  }

  /// Every layer resolved for [viewport], ordered by effective z-order.
  static List<WebsiteCanvasLayerProjection> projectLayers({
    required Map<String, dynamic> data,
    required WebsiteViewport viewport,
  }) {
    final raw = data[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List) return const <WebsiteCanvasLayerProjection>[];

    final resolved = <(
      int index,
      int? requested,
      WebsiteCanvasLayerProjection projection
    )>[];
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];
      if (item is! Map) continue;
      final layer = _stringKeyedMap(item)!;
      final kind = WebsiteCanvasLayerKind.fromRaw(layer['type']);

      final effective = _deepCopyMap(layer);
      for (final key
          in WebsiteCanvasResponsivePolicy.layerPolicies(kind).keys) {
        if (key == WebsiteCanvasResponsivePolicy.orderKey) continue;
        final resolved = _resolveProperty(
          source: layer,
          key: key,
          policy: WebsiteCanvasResponsivePolicy.layerPolicyFor(kind, key),
          viewport: viewport,
        );
        if (resolved.exists) effective[key] = _deepCopy(resolved.value);
      }
      effective.remove(WebsiteResponsiveDataCodec.containerKey);

      resolved.add((
        index,
        _requestedOrder(layer, viewport),
        WebsiteCanvasLayerProjection(
          id: layer['id']?.toString() ?? '',
          kind: kind,
          data: effective,
          visible: _resolveVisibility(layer, effective, viewport),
          order: index,
        ),
      ));
    }

    return _placeInEffectiveOrder(resolved);
  }

  /// Turns the sparse per-viewport order into a total one.
  ///
  /// The base order is the list position, so a viewport override is an
  /// EXCEPTION that has to move a layer without colliding with the layers that
  /// kept their place: a requested slot is honoured first, and everything else
  /// falls into the remaining slots in list order. Comparing the two numbers
  /// directly would let one override tie with a base index and change nothing.
  static List<WebsiteCanvasLayerProjection> _placeInEffectiveOrder(
    List<(int, int?, WebsiteCanvasLayerProjection)> resolved,
  ) {
    final total = resolved.length;
    final slots = List<WebsiteCanvasLayerProjection?>.filled(total, null);

    final requested =
        resolved.where((entry) => entry.$2 != null).toList(growable: false)
          ..sort((a, b) {
            final byOrder = a.$2!.compareTo(b.$2!);
            return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
          });
    for (final entry in requested) {
      var slot = entry.$2!.clamp(0, total - 1);
      var attempts = 0;
      while (slots[slot] != null && attempts < total) {
        slot = (slot + 1) % total;
        attempts++;
      }
      if (slots[slot] == null) slots[slot] = entry.$3;
    }

    final placed = <WebsiteCanvasLayerProjection>{
      for (final slot in slots)
        if (slot != null) slot,
    };
    var cursor = 0;
    for (final entry in resolved) {
      if (placed.contains(entry.$3)) continue;
      while (cursor < total && slots[cursor] != null) {
        cursor++;
      }
      if (cursor >= total) break;
      slots[cursor] = entry.$3;
    }

    final ordered = <WebsiteCanvasLayerProjection>[];
    for (var slot = 0; slot < total; slot++) {
      final projection = slots[slot];
      if (projection == null) continue;
      ordered.add(
        WebsiteCanvasLayerProjection(
          id: projection.id,
          kind: projection.kind,
          data: projection.data,
          visible: projection.visible,
          order: slot,
        ),
      );
    }
    return List<WebsiteCanvasLayerProjection>.unmodifiable(ordered);
  }

  static List<WebsiteCanvasLayerProjection> visibleLayers({
    required Map<String, dynamic> data,
    required WebsiteViewport viewport,
  }) {
    return projectLayers(data: data, viewport: viewport)
        .where((layer) => layer.visible)
        .toList(growable: false);
  }

  /// Effective visibility, canonical first and legacy pair after.
  ///
  /// The legacy reading reproduces exactly what the storefront draws today:
  /// `showOnMobile` marks a mobile-only layer, `hideOnMobile` a layer the
  /// phone must not show, and a layer with both is hidden everywhere.
  static bool _resolveVisibility(
    Map<String, dynamic> layer,
    Map<String, dynamic> effective,
    WebsiteViewport viewport,
  ) {
    final canonical = effective[WebsiteCanvasResponsivePolicy.visibleKey];
    if (canonical is bool) return canonical;
    return WebsiteLegacyResponsiveAdapters.canvasLayerVisible(layer, viewport);
  }

  /// What this layer SHOWS today in [viewport], standalone.
  ///
  /// Same rule as [_resolveVisibility] — typed authority first, the legacy
  /// pair only as a fallback — resolved from the layer alone, without
  /// projecting the whole document. A migration reads it to preserve what is
  /// on screen: during the rollout a legacy layer can already carry a typed
  /// `visible`, written by the canonical inspector, and that value is the one
  /// Edit, Preview and Public are drawing.
  static bool effectiveVisibility(
    Map<String, dynamic> layer,
    WebsiteViewport viewport,
  ) {
    final resolved = WebsiteResponsiveDataCodec.resolve<bool>(
      data: layer,
      propertyKey: WebsiteCanvasResponsivePolicy.visibleKey,
      viewport: viewport,
      decode: (raw) => raw is bool ? raw : null,
    );
    final canonical = resolved.value;
    if (canonical != null) return canonical;
    return WebsiteLegacyResponsiveAdapters.canvasLayerVisible(layer, viewport);
  }

  /// The slot this layer asks for in [viewport], or null when it keeps its
  /// place in the persisted list.
  static int? _requestedOrder(
    Map<String, dynamic> layer,
    WebsiteViewport viewport,
  ) {
    final override = WebsiteResponsiveDataCodec.overrideEntry<num>(
      data: layer,
      propertyKey: WebsiteCanvasResponsivePolicy.orderKey,
      viewport: viewport,
      decode: (raw) => raw is num ? raw : num.tryParse('$raw'),
    );
    if (override.exists && override.value != null) {
      return override.value!.toInt();
    }
    return null;
  }

  static WebsiteResponsiveEntry<Object?> _resolveProperty({
    required Map<String, dynamic> source,
    required String key,
    required WebsiteResponsivePropertyPolicy policy,
    required WebsiteViewport viewport,
    String? legacyMobileAlias,
  }) {
    final hasShared = source.containsKey(key);
    final hasOverride = policy.supportsViewportOverride &&
        WebsiteResponsiveDataCodec.hasOverride(source, key, viewport);
    final hasLegacy = policy.supportsViewportOverride &&
        legacyMobileAlias != null &&
        viewport == WebsiteViewport.mobile &&
        source.containsKey(legacyMobileAlias);
    if (!hasShared && !hasOverride && !hasLegacy) {
      return const WebsiteResponsiveEntry<Object?>.absent();
    }
    if (!policy.supportsViewportOverride) {
      return WebsiteResponsiveEntry<Object?>.present(_deepCopy(source[key]));
    }

    final resolved = WebsiteResponsiveDataCodec.resolve<Object?>(
      data: source,
      propertyKey: key,
      viewport: viewport,
      decode: _deepCopy,
      readLegacyOverride: legacyMobileAlias == null
          ? null
          : WebsiteLegacyResponsiveAdapters.mobileAlias<Object?>(
              legacyMobileAlias,
              _deepCopy,
            ),
    );
    return WebsiteResponsiveEntry<Object?>.present(resolved.value);
  }

  // ------------------------------------------------------------- writes

  /// Writes a root property at the given scope. Pure: returns a new document.
  static Map<String, dynamic> setRootProperty({
    required Map<String, dynamic> data,
    required String key,
    required Object? value,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    final policy = WebsiteCanvasResponsivePolicy.rootPolicyFor(key);
    final effectiveScope = WebsiteAuthoringContext(
      hostClass: WebsiteAuthoringHostClass.desktop,
      previewViewport: viewport,
      writeScope: scope,
    ).effectiveWriteScope(policy);
    final next = effectiveScope == WebsiteWriteScope.shared
        ? WebsiteResponsiveDataCodec.setShared(
            data: data,
            propertyKey: key,
            value: value,
            policies: {key: policy},
          )
        : WebsiteResponsiveDataCodec.setForViewport(
            data: data,
            propertyKey: key,
            value: value,
            viewport: viewport,
            policy: policy,
          );
    return normalize(next);
  }

  /// Writes SEVERAL root properties as one pure operation.
  ///
  /// Each key still answers to its own policy, so a single call may
  /// legitimately land part of its values on the shared base and part on the
  /// viewport override. There is no intermediate document to observe: the
  /// caller gets one result or, if a key violates the contract, the exception
  /// and its unchanged input.
  static Map<String, dynamic> setRootProperties({
    required Map<String, dynamic> data,
    required Map<String, Object?> values,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    if (values.isEmpty) return _deepCopyMap(data);
    var next = _deepCopyMap(data);
    for (final entry in values.entries) {
      next = setRootProperty(
        data: next,
        key: entry.key,
        value: entry.value,
        scope: scope,
        viewport: viewport,
      );
    }
    return next;
  }

  /// Writes one property of ONE layer, addressed by its canonical identity.
  static Map<String, dynamic> setLayerProperty({
    required Map<String, dynamic> data,
    required String layerId,
    required String key,
    required Object? value,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    return setLayerProperties(
      data: data,
      layerId: layerId,
      values: <String, Object?>{key: value},
      scope: scope,
      viewport: viewport,
    );
  }

  /// Writes SEVERAL properties of ONE layer as a single pure operation.
  ///
  /// Identity is validated once, and every value lands inside the same layer
  /// transform, so a pair like `x`/`y` can never be observed half-applied.
  static Map<String, dynamic> setLayerProperties({
    required Map<String, dynamic> data,
    required String layerId,
    required Map<String, Object?> values,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    if (values.isEmpty) return _deepCopyMap(data);
    _validateLayerGeometryValues(values);
    return _transformLayer(data, layerId, (layer) {
      var next = layer;
      for (final entry in values.entries) {
        next = _writeLayerProperty(
          layer: next,
          key: entry.key,
          value: entry.value,
          scope: scope,
          viewport: viewport,
        );
      }
      return next;
    });
  }

  /// Geometry entering the document must remain renderable regardless of
  /// which control produced it. Gesture-specific minimum sizes are UI policy,
  /// not document policy: small authored layers are valid, but non-finite
  /// coordinates/rotation and non-positive extents are not.
  static void _validateLayerGeometryValues(Map<String, Object?> values) {
    for (final entry in values.entries) {
      final isExtent = entry.key == 'w' || entry.key == 'h';
      final isGeometry = isExtent ||
          entry.key == 'x' ||
          entry.key == 'y' ||
          entry.key == 'rotation';
      if (!isGeometry) continue;
      final value = entry.value;
      if (value is! num || !value.toDouble().isFinite) {
        throw StateError('Canvas geometry must be a finite number.');
      }
      if (isExtent && value.toDouble() <= 0) {
        throw StateError('Canvas width and height must be greater than zero.');
      }
    }
  }

  static Map<String, dynamic> _writeLayerProperty({
    required Map<String, dynamic> layer,
    required String key,
    required Object? value,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    final kind = WebsiteCanvasLayerKind.fromRaw(layer['type']);
    final policy = WebsiteCanvasResponsivePolicy.layerPolicyFor(kind, key);
    final allowed = WebsiteCanvasResponsivePolicy.isOverridableForLayer(
      layer,
      key,
    );
    final effectiveScope = WebsiteAuthoringContext(
      hostClass: WebsiteAuthoringHostClass.desktop,
      previewViewport: viewport,
      writeScope: allowed ? scope : WebsiteWriteScope.shared,
    ).effectiveWriteScope(policy);

    // The base z-order has exactly one authority — the position of the layer
    // in `elements` — so a shared write of `order` would create a second
    // one. It fails closed instead of persisting a top-level `order`; moving
    // a layer in the base is a list operation, and it comes with its own
    // explicit command.
    if (key == WebsiteCanvasResponsivePolicy.orderKey &&
        effectiveScope == WebsiteWriteScope.shared) {
      throw StateError(
        'The base Canvas z-order is the position in '
        '"${WebsiteCanvasResponsivePolicy.elementsKey}". Write '
        '"${WebsiteCanvasResponsivePolicy.orderKey}" only as a tablet or '
        'mobile override, or reorder the list.',
      );
    }

    if (effectiveScope == WebsiteWriteScope.shared) {
      return WebsiteResponsiveDataCodec.setShared(
        data: layer,
        propertyKey: key,
        value: value,
        policies: {key: policy},
      );
    }
    return WebsiteResponsiveDataCodec.setForViewport(
      data: layer,
      propertyKey: key,
      value: value,
      viewport: viewport,
      policy: policy,
    );
  }

  static Map<String, dynamic> clearLayerOverride({
    required Map<String, dynamic> data,
    required String layerId,
    required String key,
    required WebsiteViewport viewport,
  }) {
    return clearLayerOverrides(
      data: data,
      layerId: layerId,
      keys: <String>[key],
      viewport: viewport,
    );
  }

  /// Resets SEVERAL viewport overrides of ONE layer in a single operation.
  ///
  /// A reset removes the exception; it never writes the inherited value, so
  /// the layer goes back to reading the shared base.
  static Map<String, dynamic> clearLayerOverrides({
    required Map<String, dynamic> data,
    required String layerId,
    required Iterable<String> keys,
    required WebsiteViewport viewport,
  }) {
    final ordered = keys.toList(growable: false);
    if (ordered.isEmpty) return _deepCopyMap(data);
    return _transformLayer(data, layerId, (layer) {
      var next = layer;
      for (final key in ordered) {
        final kind = WebsiteCanvasLayerKind.fromRaw(next['type']);
        next = WebsiteResponsiveDataCodec.clearOverride(
          data: next,
          propertyKey: key,
          viewport: viewport,
          policies: {
            key: WebsiteCanvasResponsivePolicy.layerPolicyFor(kind, key),
          },
        );
      }
      return next;
    });
  }

  static Map<String, dynamic> clearRootOverride({
    required Map<String, dynamic> data,
    required String key,
    required WebsiteViewport viewport,
  }) {
    return normalize(
      WebsiteResponsiveDataCodec.clearOverride(
        data: data,
        propertyKey: key,
        viewport: viewport,
        policies: {key: WebsiteCanvasResponsivePolicy.rootPolicyFor(key)},
      ),
    );
  }

  /// Resets SEVERAL root viewport overrides in a single operation.
  static Map<String, dynamic> clearRootOverrides({
    required Map<String, dynamic> data,
    required Iterable<String> keys,
    required WebsiteViewport viewport,
  }) {
    final ordered = keys.toList(growable: false);
    if (ordered.isEmpty) return _deepCopyMap(data);
    var next = _deepCopyMap(data);
    for (final key in ordered) {
      next = clearRootOverride(data: next, key: key, viewport: viewport);
    }
    return next;
  }

  /// Moves one layer in the z-order.
  ///
  /// Shared scope — and every desktop write, which the policy coerces to
  /// shared — moves the layer inside `elements`, because the base order has
  /// exactly one authority and that authority is the list. A tablet or mobile
  /// write records the typed `order` EXCEPTION instead and leaves the base
  /// list untouched, so resetting the override restores the base order.
  ///
  /// [targetIndex] is clamped into the list, matching how the projection
  /// places a requested slot.
  static Map<String, dynamic> reorderLayer({
    required Map<String, dynamic> data,
    required String layerId,
    required int targetIndex,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    final policy = WebsiteCanvasResponsivePolicy.layerPolicyFor(
      WebsiteCanvasLayerKind.unknown,
      WebsiteCanvasResponsivePolicy.orderKey,
    );
    final effectiveScope = WebsiteAuthoringContext(
      hostClass: WebsiteAuthoringHostClass.desktop,
      previewViewport: viewport,
      writeScope: scope,
    ).effectiveWriteScope(policy);

    if (effectiveScope == WebsiteWriteScope.viewport) {
      return setLayerProperties(
        data: data,
        layerId: layerId,
        values: <String, Object?>{
          WebsiteCanvasResponsivePolicy.orderKey: targetIndex,
        },
        scope: WebsiteWriteScope.viewport,
        viewport: viewport,
      );
    }
    return _moveLayerInList(data, layerId, targetIndex);
  }

  // ------------------------------------------------------------- lifecycle
  //
  // Structure is SHARED. Creating, removing or duplicating a layer changes the
  // document's common identity set; what a viewport owns is presentation and
  // visibility, never a second list of its own. A layer a phone should not
  // show is one identity with `visible: false`, not an identity missing from
  // a phone-only list.

  /// Inserts an already-canonical layer at [index].
  ///
  /// The caller builds the layer with the element factory, so this owns only
  /// the contract: the new id must be usable and must not collide with an
  /// identity the document already carries. Everything else is preserved
  /// exactly.
  static Map<String, dynamic> insertLayer({
    required Map<String, dynamic> data,
    required Map<String, dynamic> layer,
    required int index,
  }) {
    final next = _deepCopyMap(data);
    final raw = next[WebsiteCanvasResponsivePolicy.elementsKey];
    final current = raw is List ? List<dynamic>.from(raw) : <dynamic>[];
    _assertUsableIdentities(current);

    final id = layer['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw StateError(
        'A new Canvas layer needs an id. One identity per layer is the '
        'contract, and it is the trimmed id.',
      );
    }
    for (final item in current) {
      if (item is Map && item['id']?.toString().trim() == id) {
        throw StateError(
          'Canvas layer id "$id" already exists. A new layer needs a new '
          'identity.',
        );
      }
    }

    current.insert(
      index.clamp(0, current.length).toInt(),
      _deepCopyMap(layer),
    );
    next[WebsiteCanvasResponsivePolicy.elementsKey] = current;
    return normalize(next);
  }

  /// Removes exactly one identity, and with it every responsive branch it
  /// owned — the overrides live inside the layer, so they leave with it.
  static Map<String, dynamic> removeLayer({
    required Map<String, dynamic> data,
    required String layerId,
  }) {
    final next = _deepCopyMap(data);
    final raw = next[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List) {
      throw StateError('This Canvas document has no layers to write.');
    }
    final target = _resolveLayerIndex(raw, layerId);
    final remaining = List<dynamic>.from(raw)..removeAt(target);
    next[WebsiteCanvasResponsivePolicy.elementsKey] = remaining;
    return normalize(next);
  }

  /// Duplicates one layer under [newLayerId].
  ///
  /// The copy is deep and complete: content, bindings and EVERY viewport
  /// override travel with it, so the duplicate keeps its relative shape on the
  /// phone and the tablet too. To avoid landing exactly on top of the
  /// original, the historical +20 offset is applied to the base `x`/`y` and to
  /// each `x`/`y` a viewport ALREADY declares. An override the original never
  /// had is not invented here: that would give the copy a per-viewport
  /// exception its source never owned.
  static Map<String, dynamic> duplicateLayer({
    required Map<String, dynamic> data,
    required String layerId,
    required String newLayerId,
    double offset = 20,
  }) {
    final next = _deepCopyMap(data);
    final raw = next[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List) {
      throw StateError('This Canvas document has no layers to write.');
    }
    final source = _resolveLayerIndex(raw, layerId);

    final id = newLayerId.trim();
    if (id.isEmpty) {
      throw StateError('A duplicated Canvas layer needs a new id.');
    }
    for (final item in raw) {
      if (item is Map && item['id']?.toString().trim() == id) {
        throw StateError(
          'Canvas layer id "$id" already exists. A duplicate needs a new '
          'identity.',
        );
      }
    }

    final copy = _stringKeyedMap(raw[source] as Map)!;
    copy['id'] = id;
    _offsetPoint(copy, offset);

    final container = copy[WebsiteResponsiveDataCodec.containerKey];
    if (container is Map) {
      for (final viewport in WebsiteViewport.values) {
        if (!viewport.supportsOverride) continue;
        final branch = container[viewport.wireName];
        if (branch is Map) _offsetPoint(branch, offset);
      }
    }

    final grown = List<dynamic>.from(raw)..insert(source + 1, copy);
    next[WebsiteCanvasResponsivePolicy.elementsKey] = grown;
    return normalize(next);
  }

  /// Shifts whichever of `x`/`y` this map ALREADY declares.
  static void _offsetPoint(Map<dynamic, dynamic> target, double offset) {
    for (final key in const <String>['x', 'y']) {
      final value = target[key];
      if (value is num) target[key] = value.toDouble() + offset;
    }
  }

  /// An id no current identity uses.
  ///
  /// The Canvas used to stamp a microsecond timestamp and hope; two layers
  /// created inside the same microsecond, or a paste of an already-stamped
  /// id, would collide and make the whole document unwritable by the
  /// fail-closed identity rule.
  static String nextLayerId(
    Map<String, dynamic> data, {
    required String seed,
  }) {
    final taken = <String>{};
    final raw = data[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final id = item['id']?.toString().trim() ?? '';
          if (id.isNotEmpty) taken.add(id);
        }
      }
    }
    if (!taken.contains(seed)) return seed;
    for (var suffix = 2;; suffix++) {
      final candidate = '${seed}_$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  static Map<String, dynamic> _moveLayerInList(
    Map<String, dynamic> data,
    String layerId,
    int targetIndex,
  ) {
    final next = _deepCopyMap(data);
    final raw = next[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List) {
      throw StateError('This Canvas document has no layers to write.');
    }
    final from = _resolveLayerIndex(raw, layerId);
    final moved = List<dynamic>.from(raw);
    final layer = moved.removeAt(from);
    moved.insert(targetIndex.clamp(0, moved.length).toInt(), layer);
    next[WebsiteCanvasResponsivePolicy.elementsKey] = moved;
    return normalize(next);
  }

  /// The only accepted persisted shape.
  ///
  /// Deep-copies, drops transient editor state at every depth, removes empty
  /// or disallowed override maps and normalises each layer with its own
  /// policies. Authored values outside the responsive container survive
  /// untouched.
  static Map<String, dynamic> normalize(Map<String, dynamic> data) {
    // Only the override maps are filtered here. Which top-level key is
    // editor selection is a type-aware decision that already has an owner in
    // `sanitizeWebsiteBlockDataForPersistence`; a second rule would corrupt
    // the authored `activeElementId` that owner deliberately preserves.
    final next = _pruneUnknownOverrides(
      WebsiteResponsiveDataCodec.normalize(
        _deepCopyMap(data),
        policies: WebsiteCanvasResponsivePolicy.rootPolicies(),
        transientPropertyKeys:
            WebsiteCanvasResponsivePolicy.transientOverrideKeys,
      ),
      WebsiteCanvasResponsivePolicy.allowedRootOverrideKeys(),
    );

    final raw = next[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List) return next;
    next[WebsiteCanvasResponsivePolicy.elementsKey] = raw
        .map<dynamic>((item) => item is Map ? normalizeLayer(item) : item)
        .toList(growable: false);
    return next;
  }

  static Map<String, dynamic> normalizeLayer(Map<dynamic, dynamic> raw) {
    final layer = _stringKeyedMap(raw)!;
    final kind = WebsiteCanvasLayerKind.fromRaw(layer['type']);
    return _pruneUnknownOverrides(
      WebsiteResponsiveDataCodec.normalize(
        layer,
        policies: WebsiteCanvasResponsivePolicy.layerPolicies(kind),
        transientPropertyKeys:
            WebsiteCanvasResponsivePolicy.transientOverrideKeys,
      ),
      WebsiteCanvasResponsivePolicy.allowedLayerOverrideKeys(kind),
    );
  }

  /// Strict allow-list INSIDE the responsive container.
  ///
  /// The generic codec keeps a key it has no policy for, which is the right
  /// default for a schema that grows elsewhere. Canvas cannot afford it: a
  /// property nobody classified would become a silent per-viewport value, and
  /// the whole "unknown key is shared" rule would be decorative. The value at
  /// the TOP level is never touched — only its override.
  static Map<String, dynamic> _pruneUnknownOverrides(
    Map<String, dynamic> data,
    Set<String> allowed,
  ) {
    final container =
        _stringKeyedMap(data[WebsiteResponsiveDataCodec.containerKey]);
    if (container == null) return data;

    final next = _deepCopyMap(data);
    final pruned = <String, dynamic>{
      WebsiteResponsiveDataCodec.versionKey:
          WebsiteResponsiveDataCodec.schemaVersion,
    };
    for (final viewport in const <WebsiteViewport>[
      WebsiteViewport.tablet,
      WebsiteViewport.mobile,
    ]) {
      final values = _stringKeyedMap(container[viewport.wireName]);
      if (values == null) continue;
      final kept = <String, dynamic>{
        for (final entry in values.entries)
          if (allowed.contains(entry.key)) entry.key: _deepCopy(entry.value),
      };
      if (kept.isNotEmpty) pruned[viewport.wireName] = kept;
    }

    if (pruned.length == 1) {
      next.remove(WebsiteResponsiveDataCodec.containerKey);
    } else {
      next[WebsiteResponsiveDataCodec.containerKey] = pruned;
    }
    return next;
  }

  /// Fails unless EVERY layer has one usable identity.
  ///
  /// The same canonical semantics the migration uses: an id is what it is
  /// after trimming, it may not be blank, and no two layers may share it.
  /// Checking only the addressed id would still let a write land on a document
  /// where `'a'` and `' a '` are two layers — the migration would refuse to
  /// touch it, and a writer must not be more permissive than the contract it
  /// writes for.
  static void _assertUsableIdentities(Object? rawLayers) {
    if (rawLayers is! List) return;
    final seen = <String, int>{};
    for (var index = 0; index < rawLayers.length; index++) {
      final item = rawLayers[index];
      if (item is! Map) continue;
      final id = item['id']?.toString().trim() ?? '';
      if (id.isEmpty) {
        throw StateError(
          'Canvas layer at position $index has no id. One identity per layer '
          'is the contract; repair it before writing.',
        );
      }
      final previous = seen[id];
      if (previous != null) {
        throw StateError(
          'Canvas layers at positions $previous and $index share the id '
          '"$id". One identity per layer is the contract; repair it before '
          'writing.',
        );
      }
      seen[id] = index;
    }
  }

  /// The single position [layerId] addresses, or a contract violation.
  ///
  /// Shared by every write so "which layer did I just edit" has one answer:
  /// an unusable identity anywhere in the list, a missing id and a duplicated
  /// id all fail closed before anything is written.
  ///
  /// Addressing uses the SAME canonical identity that
  /// [_assertUsableIdentities] validates — the trimmed id. Comparing the raw
  /// string there and the trimmed one here would leave a layer that the
  /// contract already considers canonical impossible to address, and would let
  /// `" a"` and `"a "` pass as two identities while the validator counts them
  /// as one.
  static int _resolveLayerIndex(List<dynamic> rawLayers, String layerId) {
    _assertUsableIdentities(rawLayers);

    final target = layerId.trim();
    if (target.isEmpty) {
      throw StateError(
        'A blank id addresses no Canvas layer. One identity per layer is the '
        'contract, and it is the trimmed id.',
      );
    }

    final matches = <int>[];
    for (var index = 0; index < rawLayers.length; index++) {
      final item = rawLayers[index];
      if (item is! Map) continue;
      if (item['id']?.toString().trim() == target) matches.add(index);
    }
    if (matches.isEmpty) {
      throw StateError('No Canvas layer with id "$target".');
    }
    if (matches.length > 1) {
      throw StateError(
        'Canvas layer id "$target" is used by ${matches.length} layers. One '
        'identity per layer is the contract; fix the duplicate before '
        'writing.',
      );
    }
    return matches.single;
  }

  /// Applies [transform] to EXACTLY one layer.
  ///
  /// Addressing a layer that does not exist, or an id two layers share, is a
  /// contract violation and not a no-op: writing "the first match" would edit
  /// a layer the caller never named, and writing all matches would edit
  /// several. Both fail closed and loudly.
  static Map<String, dynamic> _transformLayer(
    Map<String, dynamic> data,
    String layerId,
    Map<String, dynamic> Function(Map<String, dynamic> layer) transform,
  ) {
    final next = _deepCopyMap(data);
    final raw = next[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List) {
      throw StateError('This Canvas document has no layers to write.');
    }
    final target = _resolveLayerIndex(raw, layerId);
    next[WebsiteCanvasResponsivePolicy.elementsKey] = <dynamic>[
      for (var index = 0; index < raw.length; index++)
        if (index == target)
          transform(_stringKeyedMap(raw[index] as Map)!)
        else
          raw[index],
    ];
    return normalize(next);
  }
}

/// Why a legacy Canvas document could not be migrated safely.
enum WebsiteCanvasMigrationIssueCode {
  differingSharedValue,
  duplicateStem,
  missingPair,
  incompatibleType,

  /// Two layers share one persisted id, or a layer has none. Nothing can be
  /// addressed or rolled back exactly, so no layer is migrated.
  conflictingIdentity,

  /// The twins are not a complementary desktop/mobile pair.
  nonComplementaryVisibility,
  uncertainOrder,
}

/// A typed finding, ready for the later Layers/inspector surface.
///
/// It is returned, never persisted: a log-only flag would leave the operator
/// with a document nobody explains.
class WebsiteCanvasMigrationIssue {
  const WebsiteCanvasMigrationIssue({
    required this.code,
    required this.stem,
    required this.layerIds,
    this.propertyKey,
  });

  final WebsiteCanvasMigrationIssueCode code;
  final String stem;
  final List<String> layerIds;
  final String? propertyKey;

  @override
  String toString() =>
      'WebsiteCanvasMigrationIssue(${code.name}, $stem, $layerIds, '
      '$propertyKey)';
}

class WebsiteCanvasMigrationResult {
  const WebsiteCanvasMigrationResult({
    required this.document,
    required this.issues,
    required this.mergedStems,
    required this.changed,
  });

  final Map<String, dynamic> document;
  final List<WebsiteCanvasMigrationIssue> issues;
  final List<String> mergedStems;
  final bool changed;
}

/// What a Canvas document IS, as one word, for the surface that shows it.
///
/// The inspector must not re-derive this from issue codes, provenance keys and
/// `changed` flags: three surfaces reading the same tea leaves is how a state
/// ends up meaning something different in each of them.
enum WebsiteCanvasMigrationState {
  /// Already speaks the canonical contract. Nothing to offer.
  canonical,

  /// Legacy, and every twin can be merged without a single judgement call.
  safe,

  /// Legacy with typed ambiguities, but every identity is addressable, so the
  /// operator can deliberately keep the layers separate.
  ambiguous,

  /// A blank or duplicated persisted id. Addressing and rollback cannot be
  /// guaranteed, so nothing is migrated from any surface.
  blocked,

  /// Migrated by this owner, with enough provenance to restore the original.
  migrated,
}

/// The read-only verdict on one Canvas document.
class WebsiteCanvasMigrationStatus {
  const WebsiteCanvasMigrationStatus({
    required this.state,
    required this.issues,
    required this.mergedStems,
  });

  final WebsiteCanvasMigrationState state;

  /// Every reason the operator has to see, typed. Empty for [canonical],
  /// [safe] and [migrated].
  final List<WebsiteCanvasMigrationIssue> issues;

  /// The stems a migration would merge without asking anything.
  final List<String> mergedStems;

  /// Whether this document still carries values from the pre-canonical model.
  bool get isLegacy =>
      state == WebsiteCanvasMigrationState.safe ||
      state == WebsiteCanvasMigrationState.ambiguous ||
      state == WebsiteCanvasMigrationState.blocked;

  /// Whether an unattended merge is legitimate. False for everything else,
  /// including [ambiguous] — there the operator decides, explicitly.
  bool get canMigrateSafely => state == WebsiteCanvasMigrationState.safe;

  /// Whether the deliberate "keep both layers" conversion is available.
  bool get canMigrateKeepingLayers =>
      state == WebsiteCanvasMigrationState.ambiguous;

  /// Whether the original document can be restored exactly.
  bool get canRestore => state == WebsiteCanvasMigrationState.migrated;
}

/// Versioned, idempotent and reversible migration of the legacy Canvas twins.
///
/// Nothing here persists: [analyze] never returns a changed document and
/// [migrate] returns a new one for an explicit, authorised operation to save.
abstract final class WebsiteCanvasMigration {
  static const String provenanceKey = 'canvasMigration';
  static const int version = 2;
  static const String desktopSuffix = '_desktop';
  static const String mobileSuffix = '_mobile';

  /// Reads a document and reports what a migration WOULD do. Pure.
  static WebsiteCanvasMigrationResult analyze(Map<String, dynamic> data) {
    final result = _plan(data);
    return WebsiteCanvasMigrationResult(
      document: _deepCopyMap(data),
      issues: result.issues,
      mergedStems: result.mergedStems,
      changed: result.changed,
    );
  }

  /// Produces the canonical document. Idempotent: a document that already
  /// carries version [version] provenance comes back unchanged.
  ///
  /// It is deliberately PARTIAL: safe pairs merge and ambiguous layers are left
  /// exactly as they are, reported in [WebsiteCanvasMigrationResult.issues].
  /// That is useful to a technical caller inspecting the plan, and dangerous to
  /// persist: the result would carry provenance — which makes a later [analyze]
  /// return nothing — while the ambiguous layers still hold their legacy flags.
  /// Every surface therefore goes through [migrateKeepDistinct] or fails
  /// closed; see `WebsiteEditModeProvider.migrateCanvasDocument`.
  static WebsiteCanvasMigrationResult migrate(Map<String, dynamic> data) =>
      _plan(_healed(data));

  /// A partially migrated document is planned from its ORIGINAL.
  ///
  /// Provenance stamped over something still legacy is not a resting state:
  /// planning on top of it would overwrite the record that describes the first
  /// step, and the resulting rollback would stop halfway. Restoring first means
  /// one decision, one provenance and one exact way back. A clean migrated
  /// document is not touched, so idempotence is unchanged.
  static Map<String, dynamic> _healed(Map<String, dynamic> data) =>
      _isPartiallyMigrated(data) ? expandToLegacy(data) : data;

  /// The deliberate resolution for an AMBIGUOUS document: merge what is safe,
  /// and convert every remaining legacy layer on its own.
  ///
  /// It resolves nothing the operator has not resolved. Both identities
  /// survive with their own content, destinations, bindings and place in the
  /// z-order; the only thing that changes is HOW each layer states its
  /// visibility — the contradictory `hideOnMobile`/`showOnMobile` pair becomes
  /// the typed property, computed from what the storefront draws today, so the
  /// effective visibility per viewport is identical before and after.
  ///
  /// The result carries no legacy flag, which is what makes it honest to stamp
  /// provenance on: unlike a partial [migrate], nothing ambiguous is left
  /// hidden behind the canonical marker. Every converted layer records its
  /// original key list and flags, so [expandToLegacy] returns the document
  /// byte for byte.
  ///
  /// A [WebsiteCanvasMigrationIssueCode.conflictingIdentity] still fails
  /// closed: the input comes back untouched and unmarked.
  static WebsiteCanvasMigrationResult migrateKeepDistinct(
    Map<String, dynamic> data,
  ) {
    final planned = _plan(_healed(data), keepDistinct: true);
    final blocked = planned.issues.any(
      (issue) =>
          issue.code == WebsiteCanvasMigrationIssueCode.conflictingIdentity,
    );
    if (!blocked) return planned;
    return WebsiteCanvasMigrationResult(
      document: _deepCopyMap(data),
      issues: planned.issues,
      mergedStems: const <String>[],
      changed: false,
    );
  }

  /// The one verdict every surface reads. Pure.
  static WebsiteCanvasMigrationStatus inspect(Map<String, dynamic> data) {
    final residualLegacy = _carriesLegacy(data);
    if (_hasProvenance(data) && !residualLegacy) {
      return const WebsiteCanvasMigrationStatus(
        state: WebsiteCanvasMigrationState.migrated,
        issues: <WebsiteCanvasMigrationIssue>[],
        mergedStems: <String>[],
      );
    }

    // A document that already speaks the canonical contract is canonical, full
    // stop. Two layers whose ids happen to end in `_desktop` and `_mobile` are
    // two layers with those names — reading the suffix as a legacy twin there
    // would offer a migration for something that was never legacy.
    if (!residualLegacy && WebsiteCanvasResponsiveDocument.isCanonical(data)) {
      return const WebsiteCanvasMigrationStatus(
        state: WebsiteCanvasMigrationState.canonical,
        issues: <WebsiteCanvasMigrationIssue>[],
        mergedStems: <String>[],
      );
    }

    // Provenance is not proof: a partial migration stamped it while leaving
    // legacy layers behind, and reading it as "done" is exactly how an
    // ambiguity disappears from every surface. The plan is therefore run
    // against what the document actually holds.
    final planned = _plan(data, ignoreProvenance: true);
    final issues = planned.issues;
    if (issues.any((issue) =>
        issue.code == WebsiteCanvasMigrationIssueCode.conflictingIdentity)) {
      return WebsiteCanvasMigrationStatus(
        state: WebsiteCanvasMigrationState.blocked,
        issues: issues,
        mergedStems: const <String>[],
      );
    }
    if (issues.isNotEmpty) {
      return WebsiteCanvasMigrationStatus(
        state: WebsiteCanvasMigrationState.ambiguous,
        issues: issues,
        mergedStems: planned.mergedStems,
      );
    }
    return WebsiteCanvasMigrationStatus(
      state: planned.changed
          ? WebsiteCanvasMigrationState.safe
          : WebsiteCanvasMigrationState.canonical,
      issues: const <WebsiteCanvasMigrationIssue>[],
      mergedStems: planned.mergedStems,
    );
  }

  static bool _hasProvenance(Map<String, dynamic> data) {
    final provenance = _stringKeyedMap(data[provenanceKey]);
    return provenance != null && _intOf(provenance['version']) >= version;
  }

  /// Anything the pre-canonical model still owns in this document: a layer
  /// visibility flag, or a flat `mobile…` alias at the root.
  static bool _carriesLegacy(Map<String, dynamic> data) =>
      carriesLegacyLayerFlags(data) || _carriesLegacyRootAliases(data);

  /// Stamped as migrated, and still holding something legacy. Never a valid
  /// resting state: it is what a persisted partial [migrate] would look like.
  static bool _isPartiallyMigrated(Map<String, dynamic> data) =>
      _hasProvenance(data) && _carriesLegacy(data);

  /// Whether the root still carries a flat `mobile…` alias.
  static bool _carriesLegacyRootAliases(Map<String, dynamic> data) =>
      WebsiteCanvasResponsivePolicy.legacyRootMobileAliases.values
          .any(data.containsKey);

  /// Whether any layer still states its visibility with the legacy pair.
  ///
  /// The guard a writer uses before stamping the canonical marker: a document
  /// that still carries these keys is not canonical, whatever its provenance
  /// says.
  static bool carriesLegacyLayerFlags(Map<String, dynamic> data) {
    final raw = data[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List) return false;
    for (final item in raw) {
      if (item is! Map) continue;
      for (final key
          in WebsiteCanvasResponsivePolicy.legacyLayerVisibilityKeys) {
        if (item.containsKey(key)) return true;
      }
    }
    return false;
  }

  /// Rebuilds the exact legacy document a migrated pair came from.
  ///
  /// Values AND absences are reconstructed from the recorded key lists and
  /// flag maps, never inferred from a name. A canonical-native layer carries a
  /// `placement` record — its position, nothing else — so it comes back
  /// unchanged and in its original slot; it never gets a fake legacy twin. The
  /// canonical marker is withdrawn, because the restored document is legacy
  /// again.
  static Map<String, dynamic> expandToLegacy(Map<String, dynamic> data) {
    final provenance = _stringKeyedMap(data[provenanceKey]);
    if (provenance == null) return _deepCopyMap(data);
    final entries = provenance['layers'];
    if (entries is! List || entries.isEmpty) {
      // Only the root aliases were migrated; the layers were already
      // canonical and come back untouched.
      final rootOnly = _deepCopyMap(data)..remove(provenanceKey);
      return _restoreRootAliases(
        _restoreMarker(rootOnly, provenance['marker']),
        provenance['rootAliases'],
      );
    }

    final layersById = <String, Map<String, dynamic>>{};
    final raw = data[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final layer = _stringKeyedMap(item)!;
        final id = layer['id']?.toString();
        if (id != null) layersById[id] = layer;
      }
    }

    final restored = <int, Map<String, dynamic>>{};
    final consumed = <String>{};
    for (final entry in entries) {
      final record = _stringKeyedMap(entry);
      if (record == null) continue;
      final id = record['id']?.toString();
      final layer = id == null ? null : layersById[id];
      if (layer == null) continue;
      consumed.add(id!);

      switch (record['kind']) {
        case 'pair':
          restored[_intOf(record['desktopOrder'])] = _rebuildTwin(
            layer: layer,
            id: record['desktopId']?.toString() ?? id,
            keys: _stringList(record['desktopKeys']),
            flags: _stringKeyedMap(record['desktopFlags']) ??
                const <String, dynamic>{},
            viewport: null,
          );
          restored[_intOf(record['mobileOrder'])] = _rebuildTwin(
            layer: layer,
            id: record['mobileId']?.toString() ?? id,
            keys: _stringList(record['mobileKeys']),
            flags: _stringKeyedMap(record['mobileFlags']) ??
                const <String, dynamic>{},
            viewport: WebsiteViewport.mobile,
          );
        case 'single':
          restored[_intOf(record['order'])] = _rebuildTwin(
            layer: layer,
            id: id,
            keys: _stringList(record['keys']),
            flags:
                _stringKeyedMap(record['flags']) ?? const <String, dynamic>{},
            viewport: null,
          );
        default:
          // A canonical-native layer only ever had its PLACEMENT recorded, so
          // rollback returns it exactly as it is today. It never had a legacy
          // twin and never gets one invented.
          restored[_intOf(record['order'])] = _deepCopyMap(layer);
      }
    }

    final rebuilt = <Map<String, dynamic>>[];
    final orderedSlots = restored.keys.toList()..sort();
    for (final slot in orderedSlots) {
      rebuilt.add(restored[slot]!);
    }
    // A canonical-native layer keeps its place at the end of the list; it has
    // no legacy form to restore.
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final layer = _stringKeyedMap(item)!;
        final id = layer['id']?.toString();
        if (id == null || consumed.contains(id)) continue;
        rebuilt.add(layer);
      }
    }

    final next = _deepCopyMap(data)..remove(provenanceKey);
    next[WebsiteCanvasResponsivePolicy.elementsKey] = rebuilt;
    return _restoreRootAliases(
      _restoreMarker(next, provenance['marker']),
      provenance['rootAliases'],
    );
  }

  /// Puts the canonical marker back exactly as the input had it.
  ///
  /// Without a record — a document migrated before this contract existed —
  /// the marker is withdrawn, which is what that migration would have done.
  static Map<String, dynamic> _restoreMarker(
    Map<String, dynamic> data,
    Object? rawRecord,
  ) {
    const markerKey = WebsiteCanvasResponsiveDocument.schemaVersionKey;
    final next = _deepCopyMap(data);
    final record = _stringKeyedMap(rawRecord);
    if (record == null) {
      next.remove(markerKey);
      return next;
    }
    if (record['present'] == true) {
      next[markerKey] = _deepCopy(record['value']);
    } else {
      next.remove(markerKey);
    }
    return next;
  }

  /// Puts back the flat root aliases exactly as they were — value AND absence.
  ///
  /// Only the overrides this migration created are withdrawn; an override the
  /// author had already written in canonical form survives.
  static Map<String, dynamic> _restoreRootAliases(
    Map<String, dynamic> data,
    Object? rawRecords,
  ) {
    if (rawRecords is! List || rawRecords.isEmpty) return data;
    final next = _deepCopyMap(data);
    final container =
        _stringKeyedMap(next[WebsiteResponsiveDataCodec.containerKey]);
    final mobile = _stringKeyedMap(
          container?[WebsiteViewport.mobile.wireName],
        ) ??
        <String, dynamic>{};

    for (final raw in rawRecords) {
      final record = _stringKeyedMap(raw);
      if (record == null) continue;
      final alias = record['alias']?.toString();
      final key = record['key']?.toString();
      if (alias == null || key == null) continue;
      if (record['createdOverride'] == true) mobile.remove(key);
      if (record['present'] == true) next[alias] = _deepCopy(record['value']);
    }

    if (container == null) return next;
    if (mobile.isEmpty) {
      container.remove(WebsiteViewport.mobile.wireName);
    } else {
      container[WebsiteViewport.mobile.wireName] = mobile;
    }
    if (container.keys
        .every((key) => key == WebsiteResponsiveDataCodec.versionKey)) {
      next.remove(WebsiteResponsiveDataCodec.containerKey);
    } else {
      next[WebsiteResponsiveDataCodec.containerKey] = container;
    }
    return next;
  }

  /// Absorbs `mobileDesignWidth` / `mobileFocalPointX/Y` into the canonical
  /// mobile override, recording enough to restore them byte-for-byte.
  static (Map<String, dynamic>, List<Map<String, dynamic>>) _absorbRootAliases(
    Map<String, dynamic> data,
  ) {
    final records = <Map<String, dynamic>>[];
    var next = _deepCopyMap(data);
    for (final entry
        in WebsiteCanvasResponsivePolicy.legacyRootMobileAliases.entries) {
      final key = entry.key;
      final alias = entry.value;
      if (!next.containsKey(alias)) continue;

      final value = next[alias];
      final alreadyCanonical = WebsiteResponsiveDataCodec.hasOverride(
        next,
        key,
        WebsiteViewport.mobile,
      );
      records.add(<String, dynamic>{
        'alias': alias,
        'key': key,
        'present': true,
        'value': _deepCopy(value),
        'createdOverride': !alreadyCanonical,
      });
      next.remove(alias);
      if (alreadyCanonical) continue;
      next = WebsiteResponsiveDataCodec.setForViewport(
        data: next,
        propertyKey: key,
        value: value,
        viewport: WebsiteViewport.mobile,
        policy: WebsiteCanvasResponsivePolicy.rootPolicyFor(key),
      );
    }
    return (next, records);
  }

  /// The values a rollback cannot read back off the migrated layer.
  ///
  /// Three of them:
  ///
  /// * the legacy flags, because the canonical form drops them;
  /// * the whole responsive container, because the migration may write a
  ///   visibility override inside a container the layer already owned;
  /// * the SHARED value of every property that layer overrode for the phone.
  ///   The merged branch carries what the phone draws — the effective value —
  ///   so reading the twin's top level back out of it would restore the
  ///   override where the shared value belongs.
  ///
  /// Without them `expandToLegacy` would hand back the document as the
  /// migration left it, and the round trip would not be exact.
  static Map<String, dynamic> _restorableValues(Map<String, dynamic> layer) {
    return <String, dynamic>{
      for (final key in WebsiteCanvasResponsivePolicy.legacyLayerVisibilityKeys)
        if (layer.containsKey(key)) key: _deepCopy(layer[key]),
      for (final key in _viewportOverrides(layer, WebsiteViewport.mobile).keys)
        if (layer.containsKey(key)) key: _deepCopy(layer[key]),
      if (layer.containsKey(WebsiteResponsiveDataCodec.containerKey))
        WebsiteResponsiveDataCodec.containerKey:
            _deepCopy(layer[WebsiteResponsiveDataCodec.containerKey]),
    };
  }

  static Map<String, dynamic> _rebuildTwin({
    required Map<String, dynamic> layer,
    required String id,
    required List<String> keys,
    required Map<String, dynamic> flags,
    required WebsiteViewport? viewport,
  }) {
    final overrides = viewport == null
        ? const <String, dynamic>{}
        : _viewportOverrides(layer, viewport);
    final twin = <String, dynamic>{};
    for (final key in keys) {
      if (key == 'id') {
        twin['id'] = id;
        continue;
      }
      if (flags.containsKey(key)) {
        twin[key] = _deepCopy(flags[key]);
        continue;
      }
      if (overrides.containsKey(key)) {
        twin[key] = _deepCopy(overrides[key]);
        continue;
      }
      if (layer.containsKey(key)) twin[key] = _deepCopy(layer[key]);
    }
    return twin;
  }

  /// One layer as the PHONE draws it: its shared values with its own mobile
  /// overrides applied on top.
  ///
  /// The container itself is dropped — what comes out is a flat picture of the
  /// effective values, which is what a merge has to reproduce. An override
  /// whose value is an explicit `null` survives as `null`, because that is the
  /// unset the phone is drawing.
  static Map<String, dynamic> _mobileProjection(Map<String, dynamic> layer) {
    final projected = <String, dynamic>{};
    for (final entry in layer.entries) {
      if (entry.key == WebsiteResponsiveDataCodec.containerKey) continue;
      projected[entry.key] = _deepCopy(entry.value);
    }
    for (final entry
        in _viewportOverrides(layer, WebsiteViewport.mobile).entries) {
      projected[entry.key] = _deepCopy(entry.value);
    }
    return projected;
  }

  static Map<String, dynamic> _viewportOverrides(
    Map<String, dynamic> layer,
    WebsiteViewport viewport,
  ) {
    final container =
        _stringKeyedMap(layer[WebsiteResponsiveDataCodec.containerKey]);
    return _stringKeyedMap(container?[viewport.wireName]) ??
        const <String, dynamic>{};
  }

  /// [keepDistinct] converts an AMBIGUOUS layer instead of leaving it legacy.
  /// It changes nothing else: the pairing, the issue list and the provenance
  /// are the same plan, so the two operations cannot drift apart.
  ///
  /// [ignoreProvenance] answers "what does this document hold RIGHT NOW",
  /// which is the only honest question to ask of a partially migrated one.
  static WebsiteCanvasMigrationResult _plan(
    Map<String, dynamic> data, {
    bool keepDistinct = false,
    bool ignoreProvenance = false,
  }) {
    final source = _deepCopyMap(data);

    final existing =
        ignoreProvenance ? null : _stringKeyedMap(source[provenanceKey]);
    if (existing != null && _intOf(existing['version']) >= version) {
      return WebsiteCanvasMigrationResult(
        document: source,
        issues: const <WebsiteCanvasMigrationIssue>[],
        mergedStems: const <String>[],
        changed: false,
      );
    }

    final (withRoot, rootAliasRecords) = _absorbRootAliases(source);
    final raw = withRoot[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List || raw.isEmpty) {
      return _finish(
        source: source,
        next: withRoot,
        layerRecords: const <Map<String, dynamic>>[],
        rootAliasRecords: rootAliasRecords,
        mergedStems: const <String>[],
        issues: const <WebsiteCanvasMigrationIssue>[],
        touchedLayers: false,
      );
    }

    final layers = <int, Map<String, dynamic>>{};
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];
      if (item is Map) layers[index] = _stringKeyedMap(item)!;
    }

    // 0 · one persisted identity per layer, or nothing is migrated.
    //
    // A blank or duplicated id makes both addressing and rollback ambiguous,
    // and a migration that cannot be reversed exactly is not a migration. The
    // root aliases are absorbed anyway: their reversibility does not depend on
    // any layer.
    final identityIssues = _identityIssues(layers);
    if (identityIssues.isNotEmpty) {
      return _finish(
        source: source,
        next: withRoot,
        layerRecords: const <Map<String, dynamic>>[],
        rootAliasRecords: rootAliasRecords,
        mergedStems: const <String>[],
        issues: identityIssues,
        touchedLayers: false,
      );
    }

    // 1 · group candidates by canonical stem.
    final desktopByStem = <String, List<int>>{};
    final mobileByStem = <String, List<int>>{};
    for (final entry in layers.entries) {
      final id = entry.value['id']?.toString() ?? '';
      if (id.endsWith(desktopSuffix)) {
        desktopByStem
            .putIfAbsent(
              id.substring(0, id.length - desktopSuffix.length),
              () => <int>[],
            )
            .add(entry.key);
      } else if (id.endsWith(mobileSuffix)) {
        mobileByStem
            .putIfAbsent(
              id.substring(0, id.length - mobileSuffix.length),
              () => <int>[],
            )
            .add(entry.key);
      }
    }

    final issues = <WebsiteCanvasMigrationIssue>[];
    final pairs = <String, (int desktop, int mobile)>{};
    final stems = <String>{...desktopByStem.keys, ...mobileByStem.keys};
    for (final stem in stems.toList()..sort()) {
      final desktops = desktopByStem[stem] ?? const <int>[];
      final mobiles = mobileByStem[stem] ?? const <int>[];
      final ids = <String>[
        for (final index in desktops) layers[index]!['id'].toString(),
        for (final index in mobiles) layers[index]!['id'].toString(),
      ];

      if (desktops.length > 1 || mobiles.length > 1) {
        issues.add(
          WebsiteCanvasMigrationIssue(
            code: WebsiteCanvasMigrationIssueCode.duplicateStem,
            stem: stem,
            layerIds: ids,
          ),
        );
        continue;
      }
      if (desktops.isEmpty || mobiles.isEmpty) {
        issues.add(
          WebsiteCanvasMigrationIssue(
            code: WebsiteCanvasMigrationIssueCode.missingPair,
            stem: stem,
            layerIds: ids,
          ),
        );
        continue;
      }

      final desktop = layers[desktops.single]!;
      final mobile = layers[mobiles.single]!;
      if (desktop['type']?.toString() != mobile['type']?.toString()) {
        issues.add(
          WebsiteCanvasMigrationIssue(
            code: WebsiteCanvasMigrationIssueCode.incompatibleType,
            stem: stem,
            layerIds: ids,
          ),
        );
        continue;
      }
      if (!_hasComplementaryVisibility(desktop, mobile)) {
        issues.add(
          WebsiteCanvasMigrationIssue(
            code: WebsiteCanvasMigrationIssueCode.nonComplementaryVisibility,
            stem: stem,
            layerIds: ids,
          ),
        );
        continue;
      }

      final differing = _firstDifferingSharedKey(desktop, mobile);
      if (differing != null) {
        issues.add(
          WebsiteCanvasMigrationIssue(
            code: WebsiteCanvasMigrationIssueCode.differingSharedValue,
            stem: stem,
            layerIds: ids,
            propertyKey: differing,
          ),
        );
        continue;
      }

      pairs[stem] = (desktops.single, mobiles.single);
    }

    // 2 · a reversed relative order is NOT ambiguous: the explicit viewport
    // order override exists exactly to carry it. What is ambiguous is a layer
    // that already declares a competing base `order`, because then two
    // authorities claim the same z-order and neither can be trusted.
    for (final stem in pairs.keys.toList()) {
      final pair = pairs[stem]!;
      final desktop = layers[pair.$1]!;
      final mobile = layers[pair.$2]!;
      if (!desktop.containsKey(WebsiteCanvasResponsivePolicy.orderKey) &&
          !mobile.containsKey(WebsiteCanvasResponsivePolicy.orderKey)) {
        continue;
      }
      pairs.remove(stem);
      issues.add(
        WebsiteCanvasMigrationIssue(
          code: WebsiteCanvasMigrationIssueCode.uncertainOrder,
          stem: stem,
          layerIds: <String>[
            desktop['id'].toString(),
            mobile['id'].toString(),
          ],
          propertyKey: WebsiteCanvasResponsivePolicy.orderKey,
        ),
      );
    }

    // 3 · merge, preserving both z-orders explicitly.
    final consumed = <int>{
      for (final pair in pairs.values) ...<int>[pair.$1, pair.$2],
    };
    final desktopSequence = <int>[
      for (final index in layers.keys.toList()..sort())
        if (!consumed.contains(index) ||
            pairs.values.any((pair) => pair.$1 == index))
          index,
    ];
    final mobileSequence = <int>[
      for (final index in layers.keys.toList()..sort())
        if (!consumed.contains(index) ||
            pairs.values.any((pair) => pair.$2 == index))
          index,
    ];

    final stemByDesktopIndex = <int, String>{
      for (final entry in pairs.entries) entry.value.$1: entry.key,
    };
    final stemByMobileIndex = <int, String>{
      for (final entry in pairs.entries) entry.value.$2: entry.key,
    };

    final desktopPosition = <String, int>{};
    for (var position = 0; position < desktopSequence.length; position++) {
      final index = desktopSequence[position];
      final key = stemByDesktopIndex[index] ?? 'index:$index';
      desktopPosition[key] = position;
    }
    final mobilePosition = <String, int>{};
    for (var position = 0; position < mobileSequence.length; position++) {
      final index = mobileSequence[position];
      final key = stemByMobileIndex[index] ?? 'index:$index';
      mobilePosition[key] = position;
    }

    final blockedIds = <String>{
      for (final issue in issues) ...issue.layerIds,
    };
    final provenanceEntries = <Map<String, dynamic>>[];
    final merged = <Map<String, dynamic>>[];
    var convertedSingle = false;
    for (final index in desktopSequence) {
      final stem = stemByDesktopIndex[index];
      if (stem == null) {
        final layer = layers[index]!;
        final id = layer['id']?.toString() ?? 'index:$index';
        final hasLegacyFlags = WebsiteCanvasResponsivePolicy
            .legacyLayerVisibilityKeys
            .any(layer.containsKey);
        // An ambiguous layer is normally left exactly as it is. The deliberate
        // "keep both layers" resolution converts it too — separately, on its
        // own identity — which is the whole point: nothing is merged, nothing
        // is chosen, and no legacy flag survives behind a canonical marker.
        //
        // It converts an ambiguous layer even when that layer carries no
        // legacy flag at all. A twin pair that never used the flags is still
        // legacy — it is read with the legacy bands and states no visibility
        // of its own — so leaving it untouched would make the CTA the status
        // just offered do nothing. Conversion writes the typed visibility the
        // legacy adapter was inferring, which is why the pixels do not move.
        final convertible =
            blockedIds.contains(id) ? keepDistinct : hasLegacyFlags;
        if (!convertible) {
          // Either the layer is part of an ambiguity — and stays exactly as it
          // is — or it is already canonical. Neither gets legacy provenance or
          // an invented visibility; only its placement is remembered so a
          // rollback can put it back where it was.
          provenanceEntries.add(<String, dynamic>{
            'id': id,
            'kind': 'placement',
            'order': index,
          });
          merged.add(_deepCopyMap(layer));
          continue;
        }
        provenanceEntries.add(<String, dynamic>{
          'id': id,
          'kind': 'single',
          'order': index,
          'keys': layer.keys.toList(growable: false),
          'flags': _restorableValues(layer),
        });
        merged.add(_canonicalSingle(layer));
        convertedSingle = true;
        continue;
      }

      final pair = pairs[stem]!;
      final desktop = layers[pair.$1]!;
      final mobile = layers[pair.$2]!;
      final mobileKey = 'index:${pair.$2}';
      final desktopKey = stem;
      final mobileOrder =
          mobilePosition[desktopKey] ?? mobilePosition[mobileKey];

      provenanceEntries.add(<String, dynamic>{
        'id': stem,
        'kind': 'pair',
        'desktopId': desktop['id']?.toString(),
        'mobileId': mobile['id']?.toString(),
        'desktopOrder': pair.$1,
        'mobileOrder': pair.$2,
        'desktopKeys': desktop.keys.toList(growable: false),
        'mobileKeys': mobile.keys.toList(growable: false),
        'desktopFlags': _restorableValues(desktop),
        'mobileFlags': _restorableValues(mobile),
      });

      merged.add(
        _mergedLayer(
          stem: stem,
          desktop: desktop,
          mobile: mobile,
          desktopPosition: desktopPosition[desktopKey]!,
          mobilePosition: mobileOrder,
        ),
      );
    }

    final next = _deepCopyMap(withRoot);
    next[WebsiteCanvasResponsivePolicy.elementsKey] = merged;
    return _finish(
      source: source,
      next: next,
      layerRecords: provenanceEntries,
      rootAliasRecords: rootAliasRecords,
      mergedStems: pairs.keys.toList()..sort(),
      issues: issues,
      touchedLayers: pairs.isNotEmpty || convertedSingle,
    );
  }

  /// Closes a plan: nothing to do means the ORIGINAL document, byte for byte.
  static WebsiteCanvasMigrationResult _finish({
    required Map<String, dynamic> source,
    required Map<String, dynamic> next,
    required List<Map<String, dynamic>> layerRecords,
    required List<Map<String, dynamic>> rootAliasRecords,
    required List<String> mergedStems,
    required List<WebsiteCanvasMigrationIssue> issues,
    required bool touchedLayers,
  }) {
    final frozenIssues = List<WebsiteCanvasMigrationIssue>.unmodifiable(issues);
    if (!touchedLayers && rootAliasRecords.isEmpty) {
      return WebsiteCanvasMigrationResult(
        document: source,
        issues: frozenIssues,
        mergedStems: const <String>[],
        changed: false,
      );
    }

    // The marker is data too: a document that already declared itself
    // canonical must come back with that declaration, and only the one this
    // migration stamped may be withdrawn.
    const markerKey = WebsiteCanvasResponsiveDocument.schemaVersionKey;
    final hadMarker = source.containsKey(markerKey);
    final document = _deepCopyMap(next);
    document[provenanceKey] = <String, dynamic>{
      'version': version,
      'marker': <String, dynamic>{
        'present': hadMarker,
        if (hadMarker) 'value': _deepCopy(source[markerKey]),
        'created': !hadMarker,
      },
      if (rootAliasRecords.isNotEmpty) 'rootAliases': rootAliasRecords,
      if (touchedLayers) 'layers': layerRecords,
    };
    // The marker travels with the migration: a merged pair with nothing to
    // override would otherwise be indistinguishable from a legacy document and
    // fall back to the 640/1024 bands.
    return WebsiteCanvasMigrationResult(
      document: WebsiteCanvasResponsiveDocument.normalize(
        WebsiteCanvasResponsiveDocument.markCanonical(document),
      ),
      issues: frozenIssues,
      mergedStems: List<String>.unmodifiable(mergedStems),
      changed: true,
    );
  }

  /// One layer, canonical: legacy flags become the typed [visibleKey], and the
  /// mobile twin's differing presentation becomes its override.
  static Map<String, dynamic> _mergedLayer({
    required String stem,
    required Map<String, dynamic> desktop,
    required Map<String, dynamic> mobile,
    required int desktopPosition,
    required int? mobilePosition,
  }) {
    final kind = WebsiteCanvasLayerKind.fromRaw(desktop['type']);
    final base = <String, dynamic>{};
    for (final entry in desktop.entries) {
      if (WebsiteCanvasResponsivePolicy.legacyLayerVisibilityKeys
          .contains(entry.key)) {
        continue;
      }
      base[entry.key] = _deepCopy(entry.value);
    }
    base['id'] = stem;
    // The base is what DESKTOP shows today — never an assumed `true`. A twin
    // the operator had already hidden with the typed property stays hidden.
    final baseVisible = WebsiteCanvasResponsiveDocument.effectiveVisibility(
      desktop,
      WebsiteViewport.desktop,
    );
    base[WebsiteCanvasResponsivePolicy.visibleKey] = baseVisible;

    // What the phone draws is the mobile twin's PROJECTION, not its top level:
    // the twin may already carry its own `responsive.mobile`, written by the
    // canonical inspector, and those are the values on screen. Reading only the
    // top level would silently drop them — the pair still merges, and the
    // campaign changes size on the phone.
    final mobileProjection = _mobileProjection(mobile);

    final overrides = <String, dynamic>{};
    for (final entry in mobileProjection.entries) {
      final key = entry.key;
      if (key == 'id' ||
          WebsiteCanvasResponsivePolicy.legacyLayerVisibilityKeys
              .contains(key)) {
        continue;
      }
      if (!WebsiteCanvasResponsivePolicy.layerPolicyFor(kind, key)
          .supportsViewportOverride) {
        continue;
      }
      if (base.containsKey(key) &&
          websiteResponsiveDeepEquals(base[key], entry.value)) {
        continue;
      }
      overrides[key] = _deepCopy(entry.value);
    }
    // A presentation key the DESKTOP twin carried and the mobile twin did not
    // is not an inheritance: the phone used the renderer's own default. It
    // becomes an explicit unset, so the canonical mobile keeps drawing what it
    // drew. Its absence in the twin is recorded in provenance, so a rollback
    // restores the missing key rather than a null.
    for (final key in base.keys.toList()) {
      if (key == 'id' ||
          key == WebsiteCanvasResponsivePolicy.visibleKey ||
          key == WebsiteResponsiveDataCodec.containerKey ||
          mobileProjection.containsKey(key)) {
        continue;
      }
      if (!WebsiteCanvasResponsivePolicy.layerPolicyFor(kind, key)
          .supportsViewportOverride) {
        continue;
      }
      if (base[key] == null) continue;
      overrides[key] = null;
    }

    if (mobilePosition != null && mobilePosition != desktopPosition) {
      overrides[WebsiteCanvasResponsivePolicy.orderKey] = mobilePosition;
    }

    // What the PHONE shows is the mobile twin's own effective visibility, and
    // it may live in its typed shared value or in its own override rather than
    // in a flag. It is resolved once, last, so neither source is missed.
    final mobileVisible = WebsiteCanvasResponsiveDocument.effectiveVisibility(
      mobile,
      WebsiteViewport.mobile,
    );
    if (mobileVisible != baseVisible) {
      overrides[WebsiteCanvasResponsivePolicy.visibleKey] = mobileVisible;
    } else {
      overrides.remove(WebsiteCanvasResponsivePolicy.visibleKey);
    }

    // The TABLET keeps reading the desktop twin — that is the layer it draws —
    // so that twin's own tablet branch survives untouched, and the only thing
    // synthesised is a visibility it did not state typed.
    final container = _stringKeyedMap(
          base[WebsiteResponsiveDataCodec.containerKey],
        ) ??
        <String, dynamic>{};
    final tabletVisible = WebsiteCanvasResponsiveDocument.effectiveVisibility(
      desktop,
      WebsiteViewport.tablet,
    );
    if (tabletVisible != baseVisible) {
      final tablet =
          _stringKeyedMap(container[WebsiteViewport.tablet.wireName]) ??
              <String, dynamic>{};
      tablet[WebsiteCanvasResponsivePolicy.visibleKey] = tabletVisible;
      container[WebsiteViewport.tablet.wireName] = tablet;
    }
    // The phone branch is REPLACED, not merged: on mobile the visitor sees the
    // mobile twin, so an override the desktop twin carried for a viewport it
    // never showed on must not leak into what the phone now draws.
    if (overrides.isEmpty) {
      container.remove(WebsiteViewport.mobile.wireName);
    } else {
      container[WebsiteViewport.mobile.wireName] = overrides;
    }

    container.remove(WebsiteResponsiveDataCodec.versionKey);
    if (container.isEmpty) {
      base.remove(WebsiteResponsiveDataCodec.containerKey);
      return base;
    }
    base[WebsiteResponsiveDataCodec.containerKey] = <String, dynamic>{
      WebsiteResponsiveDataCodec.versionKey:
          WebsiteResponsiveDataCodec.schemaVersion,
      ...container,
    };
    return base;
  }

  /// A layer with no twin keeps its identity and states, typed, exactly the
  /// visibility it already has.
  ///
  /// Typed authority is never overwritten: a `visible` the inspector already
  /// wrote — shared or per viewport — is what the layer shows, so it survives
  /// untouched and only a viewport with no typed authority gets its value
  /// synthesised from the legacy flags. The rest of the responsive container
  /// is preserved as well; it holds geometry and presentation this migration
  /// has no business rewriting.
  static Map<String, dynamic> _canonicalSingle(Map<String, dynamic> layer) {
    var next = <String, dynamic>{};
    for (final entry in layer.entries) {
      if (WebsiteCanvasResponsivePolicy.legacyLayerVisibilityKeys
          .contains(entry.key)) {
        continue;
      }
      next[entry.key] = _deepCopy(entry.value);
    }

    const visibleKey = WebsiteCanvasResponsivePolicy.visibleKey;
    final baseVisible = WebsiteCanvasResponsiveDocument.effectiveVisibility(
      layer,
      WebsiteViewport.desktop,
    );
    next[visibleKey] = baseVisible;

    for (final viewport in const <WebsiteViewport>[
      WebsiteViewport.tablet,
      WebsiteViewport.mobile,
    ]) {
      final effective = WebsiteCanvasResponsiveDocument.effectiveVisibility(
        layer,
        viewport,
      );
      if (effective == baseVisible) continue;
      next = WebsiteResponsiveDataCodec.setForViewport(
        data: next,
        propertyKey: visibleKey,
        value: effective,
        viewport: viewport,
        policy: WebsiteResponsivePropertyPolicy.responsiveVisibility,
      );
    }
    return next;
  }

  /// Blank and duplicated persisted ids, as typed findings.
  static List<WebsiteCanvasMigrationIssue> _identityIssues(
    Map<int, Map<String, dynamic>> layers,
  ) {
    final issues = <WebsiteCanvasMigrationIssue>[];
    final byId = <String, List<int>>{};
    for (final entry in layers.entries) {
      final raw = entry.value['id'];
      final id = raw?.toString().trim() ?? '';
      if (id.isEmpty) {
        issues.add(
          WebsiteCanvasMigrationIssue(
            code: WebsiteCanvasMigrationIssueCode.conflictingIdentity,
            stem: 'index:${entry.key}',
            layerIds: const <String>[],
            propertyKey: 'id',
          ),
        );
        continue;
      }
      byId.putIfAbsent(id, () => <int>[]).add(entry.key);
    }
    for (final entry in byId.entries) {
      if (entry.value.length < 2) continue;
      issues.add(
        WebsiteCanvasMigrationIssue(
          code: WebsiteCanvasMigrationIssueCode.conflictingIdentity,
          stem: entry.key,
          layerIds: <String>[
            for (var i = 0; i < entry.value.length; i++) entry.key
          ],
          propertyKey: 'id',
        ),
      );
    }
    return issues;
  }

  /// Whether the two twins really divide the devices between them.
  ///
  /// Measured on EFFECTIVE visibility, not on the legacy flags: a layer that
  /// already carries a typed `visible` is drawn by that value, so a pair can
  /// look complementary in its flags and overlap on screen. Merging an overlap
  /// would delete one of two layers the visitor sees at the same time, which is
  /// a pixel change, not a migration.
  ///
  /// A twin that is deliberately hidden everywhere does NOT block the merge:
  /// nothing overlaps, and the merged layer reproduces that hidden state per
  /// viewport.
  static bool _hasComplementaryVisibility(
    Map<String, dynamic> desktop,
    Map<String, dynamic> mobile,
  ) {
    final mobileCrossesOver =
        WebsiteCanvasResponsiveDocument.effectiveVisibility(
                mobile, WebsiteViewport.desktop) ||
            WebsiteCanvasResponsiveDocument.effectiveVisibility(
              mobile,
              WebsiteViewport.tablet,
            );
    final desktopCrossesOver =
        WebsiteCanvasResponsiveDocument.effectiveVisibility(
      desktop,
      WebsiteViewport.mobile,
    );
    return !mobileCrossesOver && !desktopCrossesOver;
  }

  /// The first business/content value the twins disagree on.
  ///
  /// A single difference is enough to refuse the merge: two layers that say
  /// different things are two layers, not one layer with a phone variant.
  static String? _firstDifferingSharedKey(
    Map<String, dynamic> desktop,
    Map<String, dynamic> mobile,
  ) {
    final kind = WebsiteCanvasLayerKind.fromRaw(desktop['type']);
    final keys = <String>{...desktop.keys, ...mobile.keys}
      ..removeAll(WebsiteCanvasResponsivePolicy.legacyLayerVisibilityKeys)
      ..remove('id');
    final ordered = keys.toList()..sort();
    for (final key in ordered) {
      if (WebsiteCanvasResponsivePolicy.layerPolicyFor(kind, key)
          .supportsViewportOverride) {
        continue;
      }
      if (!websiteResponsiveDeepEquals(desktop[key], mobile[key])) return key;
    }
    return null;
  }
}

int _intOf(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw') ?? 0;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw.map((item) => item.toString()).toList(growable: false);
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  return value.map(
    (key, nested) => MapEntry(key.toString(), _deepCopy(nested)),
  );
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) =>
    source.map((key, value) => MapEntry(key, _deepCopy(value)));

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
