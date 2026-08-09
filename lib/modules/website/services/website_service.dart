import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/website_block_document_sanitizer.dart';
import '../models/website_editor_capability.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_action.dart';
import '../models/website_catalog_presentation.dart';
import '../models/website_models.dart';
import '../models/website_seo_settings_aliases.dart';
import '../models/public_order_access.dart';
import '../models/public_shipping_quote.dart';
import '../models/online_order_correction.dart';
import '../models/website_page_models.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_tax_treatment.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/web_data_bridge.dart';

part 'website_service_support.dart';
part 'website_page_snapshot_cache.dart';

const String _publicStoreCacheNamespace = 'website_public_v2';
final RegExp _sensitivePublicWebsiteSettingKey = RegExp(
  r'(access[_-]?token|refresh[_-]?token|secret|password|private|credential|api[_-]?key)',
  caseSensitive: false,
);

/// Re-validation hook a save installs for the duration of one command:
/// invoked immediately before EVERY internal mutable request of a composite
/// operation (and therefore after any preceding read). Throws when the
/// saving authority is no longer current.
typedef WebsiteEditorWriteGuard = void Function();

/// One-shot authority for a Website Builder command that crosses an async
/// boundary before issuing a remote write.
///
/// The widget owns the live identity evidence (provider/service instances,
/// entry-lease generations and host revision). This class owns the state
/// machine: validate -> consume the operation-specific claim -> validate,
/// then expose the same validator as the service's pre/post-write guard.
/// Reusing an authority or losing any captured owner is a typed supersession,
/// never an ordinary persistence error that could be shown in a new session.
class WebsiteEditorRemoteWriteAuthority {
  WebsiteEditorRemoteWriteAuthority({
    required String tenantId,
    required bool Function() claimOwner,
    required bool Function() isCurrent,
    required String operation,
  })  : tenantId = tenantId.trim(),
        _claimOwner = claimOwner,
        _isCurrent = isCurrent,
        _operation = operation {
    if (this.tenantId.isEmpty) {
      throw const WebsiteEditorWriteSupersededException(
        'La operación remota no tiene un tenant editor vigente.',
      );
    }
  }

  final String tenantId;
  final bool Function() _claimOwner;
  final bool Function() _isCurrent;
  final String _operation;
  bool _claimed = false;

  /// Read-only checkpoint for awaits that precede the remote write.
  void ensureCurrent() {
    bool current;
    try {
      current = _isCurrent();
    } catch (_) {
      current = false;
    }
    if (!current) {
      throw WebsiteEditorWriteSupersededException(
        'La autoridad de $_operation cambió antes de completarse.',
      );
    }
  }

  /// Consumes the operation-specific owner exactly once and returns the guard
  /// that the service invokes around every mutable request.
  WebsiteEditorWriteGuard claimForWrite() {
    if (_claimed) {
      throw WebsiteEditorWriteSupersededException(
        'La autoridad de $_operation ya fue consumida.',
      );
    }
    _claimed = true;
    ensureCurrent();

    bool claimed;
    try {
      claimed = _claimOwner();
    } catch (_) {
      claimed = false;
    }
    if (!claimed) {
      throw WebsiteEditorWriteSupersededException(
        'La autoridad de $_operation fue reemplazada antes del guardado.',
      );
    }

    ensureCurrent();
    return ensureCurrent;
  }
}

/// FIFO owner for remote commands whose result order is user-visible.
///
/// Each scheduled operation receives its own result/error, while the private
/// tail always completes successfully so one failed command cannot skip or
/// reorder the next command.
class WebsiteEditorRemoteWriteSerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> schedule<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

/// Service for managing website content, banners, featured products, and online orders
class WebsiteService extends ChangeNotifier {
  WebsiteService({
    SupabaseClient? supabase,
    TenantService? tenantService,
    http.Client? httpClient,
    WebsitePreloadedStoreDataLoader? preloadedStoreDataLoader,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService(),
        _httpClient = httpClient ?? http.Client(),
        _preloadedStoreDataLoader = preloadedStoreDataLoader ??
            ((expectedTenantId) => WebDataBridge.getPreloadedStoreData(
                  expectedTenantId: expectedTenantId,
                )) {
    // The standalone storefront (main_store.dart) provides no TenantService
    // and nothing rebuilds on auth events by itself, so this service owns
    // that lifecycle: subscribe the identity owner idempotently and relay
    // each auth/cache notification as one rebuild trigger plus one CMS
    // origin revalidation. Every `watch<WebsiteService>` consumer then
    // re-evaluates the editor-entry lease on the next frame (logout or a
    // user switch revokes editor context without any other interaction).
    _tenantService.initialize();
    _tenantService.addListener(_onTenantIdentityChanged);
  }

  final SupabaseClient _supabase;
  final TenantService _tenantService;
  final http.Client _httpClient;
  final WebsitePreloadedStoreDataLoader _preloadedStoreDataLoader;
  final Set<String> _legacyPublicCacheEvictionStarted = <String>{};

  // Perf logs are enabled in debug, or in release via:
  // flutter build web --release --dart-define=STORE_PERF_LOGS=true
  static bool get _perfLogsEnabled =>
      kDebugMode || const bool.fromEnvironment('STORE_PERF_LOGS');

  // ============================================================
  // BLOCK NORMALIZATION (Phase 2 - Jan 2026)
  // ============================================================
  static const int _currentBlockSchemaVersion = 1;
  static const String _orderItemProductContextSelect =
      'id,name,sku,category_name,stock_quantity,inventory_qty,is_active,'
      'is_published,product_type,track_stock,purchase_treatment,'
      'is_set,parent_set_id';

  bool get canRetryOnlineOrderPaymentProcessing =>
      _tenantService.hasAnyRole(const ['admin', 'manager', 'cashier']) ||
      _tenantService.hasPermission('create_invoices');

  Map<String, dynamic> _deepMergeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> override,
  ) {
    final result = <String, dynamic>{...base};
    override.forEach((key, value) {
      final baseValue = result[key];
      if (value is Map && baseValue is Map) {
        result[key] = _deepMergeMaps(
          Map<String, dynamic>.from(baseValue),
          Map<String, dynamic>.from(value),
        );
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  Map<String, dynamic> _normalizeBlockData({
    required String blockTypeRaw,
    required Object? rawBlockData,
  }) {
    final rawMap = rawBlockData is Map
        ? Map<String, dynamic>.from(rawBlockData)
        : <String, dynamic>{};

    final parsedType = parseWebsiteBlockType(
      blockTypeRaw,
      fallback: WebsiteBlockType.hero,
    );
    final definition = WebsiteBlockRegistry.definitionFor(parsedType);

    final normalized = _deepMergeMaps(
      Map<String, dynamic>.from(definition.defaultData),
      rawMap,
    );

    dynamic cloneValue(dynamic value) {
      if (value is Map) {
        return value.map(
          (key, nested) => MapEntry(key.toString(), cloneValue(nested)),
        );
      }
      if (value is List) return value.map(cloneValue).toList();
      return value;
    }

    void syncCollectionAliases(
      String canonicalKey,
      List<String> aliases,
    ) {
      Object? source;
      if (rawMap.containsKey(canonicalKey)) {
        source = rawMap[canonicalKey];
      } else {
        for (final alias in aliases) {
          if (rawMap.containsKey(alias)) {
            source = rawMap[alias];
            break;
          }
        }
      }
      if (source is! List) return;
      final next = cloneValue(source);
      normalized[canonicalKey] = next;
      for (final alias in aliases) {
        normalized[alias] = cloneValue(next);
      }
    }

    void syncScalarAliases(
      String canonicalKey,
      List<String> aliases,
    ) {
      Object? source;
      var found = false;
      if (rawMap.containsKey(canonicalKey)) {
        source = rawMap[canonicalKey];
        found = true;
      } else {
        for (final alias in aliases) {
          if (rawMap.containsKey(alias)) {
            source = rawMap[alias];
            found = true;
            break;
          }
        }
      }
      if (!found) return;
      normalized[canonicalKey] = cloneValue(source);
      for (final alias in aliases) {
        normalized[alias] = cloneValue(source);
      }
    }

    void syncCollectionItemAliases(
      String collectionKey,
      Map<String, List<String>> fieldAliases, {
      List<String> collectionAliases = const [],
    }) {
      final rawItems = normalized[collectionKey];
      if (rawItems is! List) return;
      final next = <dynamic>[];
      for (final rawItem in rawItems) {
        if (rawItem is! Map) {
          next.add(cloneValue(rawItem));
          continue;
        }
        final item = Map<String, dynamic>.from(rawItem);
        for (final entry in fieldAliases.entries) {
          Object? source;
          var found = false;
          if (item.containsKey(entry.key)) {
            source = item[entry.key];
            found = true;
          } else {
            for (final alias in entry.value) {
              if (item.containsKey(alias)) {
                source = item[alias];
                found = true;
                break;
              }
            }
          }
          if (!found) continue;
          item[entry.key] = cloneValue(source);
          for (final alias in entry.value) {
            item[alias] = cloneValue(source);
          }
        }
        next.add(item);
      }
      normalized[collectionKey] = next;
      for (final alias in collectionAliases) {
        normalized[alias] = cloneValue(next);
      }
    }

    // Canonical collection presence wins even when it is intentionally empty.
    // This must happen before defaults can hide a legacy-only persisted list.
    final collectionType = blockTypeRaw.trim().toLowerCase();
    if (collectionType == 'features') {
      syncCollectionAliases('features', const ['items']);
    } else if (collectionType == 'services') {
      syncCollectionAliases('services', const ['items']);
    } else if (collectionType == 'testimonials') {
      syncCollectionAliases('testimonials', const ['items']);
      syncCollectionItemAliases(
        'testimonials',
        const {
          'comment': ['quote', 'text'],
        },
        collectionAliases: const ['items'],
      );
    } else if (collectionType == 'pricing') {
      syncCollectionAliases('plans', const ['items']);
      syncCollectionItemAliases(
        'plans',
        const {
          'ctaText': ['buttonText'],
          'ctaLink': ['buttonLink'],
          'highlighted': ['isFeatured'],
        },
        collectionAliases: const ['items'],
      );
    } else if (collectionType == 'team') {
      syncScalarAliases('description', const ['subtitle']);
      syncCollectionAliases('members', const ['team', 'items']);
      syncCollectionItemAliases(
        'members',
        const {
          'avatarUrl': ['image'],
        },
        collectionAliases: const ['team', 'items'],
      );
    } else if (collectionType == 'stats') {
      syncCollectionAliases('metrics', const ['stats', 'items']);
    }

    // Schema version convention (noop-first; enables safe future migrations)
    normalized['schemaVersion'] =
        (normalized['schemaVersion'] as int?) ?? _currentBlockSchemaVersion;

    void syncPrimaryAction(
      Map<String, dynamic> target, {
      Map<String, dynamic>? rawSource,
      required List<String> labelKeys,
      required List<String> hrefKeys,
      String defaultLabel = 'Ver más',
      String defaultHref = '',
      WebsiteActionVariant defaultVariant = WebsiteActionVariant.filled,
      bool enabled = true,
      String? variantKey,
    }) {
      final source = rawSource ?? target;
      final hasExplicitHref = hrefKeys.any(
        (key) =>
            source.containsKey(key) &&
            (source[key]?.toString().trim().isNotEmpty ?? false),
      );
      final hasStructuredAction = source['actions'] is List &&
          (source['actions'] as List).whereType<Map>().isNotEmpty;
      final resolutionData = Map<String, dynamic>.from(target);
      if (!hasExplicitHref && hasStructuredAction) {
        for (final key in hrefKeys) {
          resolutionData.remove(key);
        }
        for (final key in labelKeys) {
          resolutionData.remove(key);
        }
        resolutionData['actions'] = source['actions'];
      }

      final action = WebsiteActionValue.resolvePrimary(
        resolutionData,
        labelKeys: labelKeys,
        hrefKeys: hrefKeys,
        variantKeys:
            variantKey == null ? const ['actionVariant'] : [variantKey],
        defaultLabel: defaultLabel,
        defaultHref: defaultHref,
        defaultVariant: variantKey == null
            ? defaultVariant
            : WebsiteActionVariant.fromStorage(
                target[variantKey]?.toString(),
                fallback: defaultVariant,
              ),
        enabled: enabled,
      );
      final effective = action ??
          WebsiteActionValue(
            label: defaultLabel,
            href: '',
            variant: defaultVariant,
          );
      target['actions'] = WebsiteActionValue.mergePrimary(
        target['actions'],
        effective,
      );
      if (action == null) return;
      for (final key in labelKeys) {
        target[key] = action.label;
      }
      for (final key in hrefKeys) {
        target[key] = action.href;
      }
      if (variantKey != null) {
        target[variantKey] = action.variant.storageValue;
      }
    }

    // --- Targeted legacy migrations (keep minimal, safe) ---
    final rawTypeLower = blockTypeRaw.trim().toLowerCase();
    if (rawTypeLower == 'about') {
      final content = (normalized['content'] ?? '').toString().trim();
      final legacyDescription =
          (normalized['description'] ?? '').toString().trim();
      if (content.isEmpty && legacyDescription.isNotEmpty) {
        normalized['content'] = legacyDescription;
      }

      if ((normalized['imageUrl'] == null ||
              normalized['imageUrl'].toString().trim().isEmpty) &&
          normalized['image'] != null) {
        normalized['imageUrl'] = normalized['image'];
      }
    }

    if (rawTypeLower == 'button') {
      final label = (normalized['label'] ?? '').toString().trim();
      final legacyText = (normalized['text'] ?? '').toString().trim();
      if (label.isEmpty && legacyText.isNotEmpty) {
        normalized['label'] = legacyText;
      }

      if (normalized['style'] == null && normalized['variant'] != null) {
        final variant = normalized['variant'].toString();
        normalized['style'] = switch (variant) {
          'outline' => 'outline',
          'text' => 'text',
          'secondary' => 'filled',
          _ => 'filled',
        };
      }
    }

    if (rawTypeLower == 'cta') {
      final subtitle = (normalized['subtitle'] ?? '').toString().trim();
      final description = (normalized['description'] ?? '').toString().trim();
      if (subtitle.isEmpty && description.isNotEmpty) {
        normalized['subtitle'] = description;
      }

      // Formatting legacy alias
      if (normalized['subtitleFormatting'] == null &&
          normalized['descriptionFormatting'] != null) {
        normalized['subtitleFormatting'] = normalized['descriptionFormatting'];
      }
    }

    if (rawTypeLower == 'categorygrid') {
      final rawCategories = normalized['categories'];
      if (rawCategories is List) {
        final next = <Map<String, dynamic>>[];
        for (final item in rawCategories) {
          if (item is! Map) continue;
          final normalizedItem = Map<String, dynamic>.from(item);

          final ctaLink = (normalizedItem['ctaLink'] ?? '').toString().trim();
          final link = (normalizedItem['link'] ?? '').toString().trim();
          if (ctaLink.isEmpty && link.isNotEmpty) {
            normalizedItem['ctaLink'] = link;
          }
          if (link.isEmpty && ctaLink.isNotEmpty) {
            normalizedItem['link'] = ctaLink;
          }

          final ctaText = (normalizedItem['ctaText'] ?? '').toString().trim();
          final legacyButtonText =
              (normalizedItem['buttonText'] ?? '').toString().trim();
          if (ctaText.isEmpty && legacyButtonText.isNotEmpty) {
            normalizedItem['ctaText'] = legacyButtonText;
          }
          if (legacyButtonText.isEmpty && ctaText.isNotEmpty) {
            normalizedItem['buttonText'] = ctaText;
          }

          next.add(normalizedItem);
        }
        normalized['categories'] = next;
      }
    }

    if (rawTypeLower == 'videobanner') {
      if ((normalized['imageUrl'] == null ||
              normalized['imageUrl'].toString().trim().isEmpty) &&
          normalized['posterImage'] != null) {
        normalized['imageUrl'] = normalized['posterImage'];
      }

      final ctaText = (normalized['ctaText'] ?? '').toString().trim();
      final legacyButtonText =
          (normalized['buttonText'] ?? '').toString().trim();
      if (ctaText.isEmpty && legacyButtonText.isNotEmpty) {
        normalized['ctaText'] = legacyButtonText;
      }

      final ctaLink = (normalized['ctaLink'] ?? '').toString().trim();
      final legacyButtonLink =
          (normalized['buttonLink'] ?? '').toString().trim();
      if (ctaLink.isEmpty && legacyButtonLink.isNotEmpty) {
        normalized['ctaLink'] = legacyButtonLink;
      }

      if (normalized['showCta'] == null) {
        normalized['showCta'] = true;
      }
    }

    if (rawTypeLower == 'hero') {
      // Background image: legacy key was backgroundImage.
      if ((normalized['imageUrl'] == null ||
              normalized['imageUrl'].toString().trim().isEmpty) &&
          normalized['backgroundImage'] != null) {
        normalized['imageUrl'] = normalized['backgroundImage'];
      }
      if ((normalized['backgroundImage'] == null ||
              normalized['backgroundImage'].toString().trim().isEmpty) &&
          normalized['imageUrl'] != null) {
        normalized['backgroundImage'] = normalized['imageUrl'];
      }

      // CTA: legacy keys were buttonText/buttonLink.
      final ctaText = (normalized['ctaText'] ?? '').toString().trim();
      final legacyButtonText =
          (normalized['buttonText'] ?? '').toString().trim();
      if (ctaText.isEmpty && legacyButtonText.isNotEmpty) {
        normalized['ctaText'] = legacyButtonText;
      }
      if (legacyButtonText.isEmpty && ctaText.isNotEmpty) {
        normalized['buttonText'] = ctaText;
      }

      final ctaLink = (normalized['ctaLink'] ?? '').toString().trim();
      final legacyButtonLink =
          (normalized['buttonLink'] ?? '').toString().trim();
      if (ctaLink.isEmpty && legacyButtonLink.isNotEmpty) {
        normalized['ctaLink'] = legacyButtonLink;
      }
      if (legacyButtonLink.isEmpty && ctaLink.isNotEmpty) {
        normalized['buttonLink'] = ctaLink;
      }
    }

    // Every visible CTA is normalized into the same action contract. Legacy
    // aliases remain synchronized so old saved pages and newer editor controls
    // cannot disagree about what the visitor clicks.
    if (rawTypeLower == 'hero' ||
        rawTypeLower == 'cta' ||
        rawTypeLower == 'videobanner') {
      syncPrimaryAction(
        normalized,
        rawSource: rawMap,
        labelKeys: const ['ctaText', 'buttonText'],
        hrefKeys: const ['ctaLink', 'buttonLink'],
        defaultHref: rawTypeLower == 'cta' ? '/contacto' : '/productos',
        defaultVariant: WebsiteActionVariant.outline,
        enabled:
            rawTypeLower != 'videobanner' || normalized['showCta'] != false,
        variantKey: 'actionVariant',
      );
    } else if (rawTypeLower == 'button') {
      syncPrimaryAction(
        normalized,
        rawSource: rawMap,
        labelKeys: const ['label', 'text'],
        hrefKeys: const ['link'],
        defaultLabel: 'Botón',
        defaultHref: '/productos',
        variantKey: 'style',
      );
    } else if (rawTypeLower == 'products') {
      syncPrimaryAction(
        normalized,
        rawSource: rawMap,
        labelKeys: const ['viewAllText'],
        hrefKeys: const ['viewAllLink'],
        defaultLabel: 'Ver todos los productos',
        defaultHref: '/productos',
        defaultVariant: WebsiteActionVariant.outline,
        enabled: normalized['showViewAll'] != false,
        variantKey: 'actionVariant',
      );
    }

    void syncNestedActions(
      String collectionKey, {
      required List<String> labelKeys,
      required List<String> hrefKeys,
      String defaultLabel = 'Ver más',
      String defaultHref = '/productos',
      WebsiteActionVariant defaultVariant = WebsiteActionVariant.filled,
      String? variantKey,
    }) {
      final items = normalized[collectionKey];
      if (items is! List) return;
      final rawItems = rawMap[collectionKey] is List
          ? rawMap[collectionKey] as List
          : const <dynamic>[];
      normalized[collectionKey] = <Map<String, dynamic>>[
        for (var index = 0; index < items.length; index++)
          if (items[index] is Map)
            (() {
              final item = Map<String, dynamic>.from(items[index] as Map);
              final rawItem = index < rawItems.length && rawItems[index] is Map
                  ? Map<String, dynamic>.from(rawItems[index] as Map)
                  : item;
              syncPrimaryAction(
                item,
                rawSource: rawItem,
                labelKeys: labelKeys,
                hrefKeys: hrefKeys,
                defaultLabel: defaultLabel,
                defaultHref: defaultHref,
                defaultVariant: defaultVariant,
                variantKey: variantKey,
              );
              return item;
            })(),
      ];
    }

    if (rawTypeLower == 'carousel') {
      syncNestedActions(
        'slides',
        labelKeys: const ['ctaText', 'buttonText'],
        hrefKeys: const ['ctaLink', 'buttonLink'],
        defaultVariant: WebsiteActionVariant.outline,
        variantKey: 'actionVariant',
      );
    } else if (rawTypeLower == 'pricing') {
      syncNestedActions(
        'plans',
        labelKeys: const ['ctaText', 'buttonText'],
        hrefKeys: const ['ctaLink', 'buttonLink'],
        defaultLabel: 'Seleccionar',
        variantKey: 'actionVariant',
      );
      if (normalized['plans'] is List) {
        normalized['items'] = cloneValue(normalized['plans']);
      }
    }

    return sanitizeWebsiteBlockDataForPersistence(
      blockType: rawTypeLower,
      data: normalized,
    );
  }

  @visibleForTesting
  Map<String, dynamic> normalizeBlockDataForTesting({
    required String blockType,
    required Object? blockData,
  }) =>
      _normalizeBlockData(
        blockTypeRaw: blockType,
        rawBlockData: blockData,
      );

  List<Map<String, dynamic>> _normalizeBlocksList(
    List<Map<String, dynamic>> blocks,
  ) {
    return blocks.map((block) {
      final next = Map<String, dynamic>.from(block);
      final blockType =
          (next['block_type'] ?? next['type'] ?? '').toString().trim();
      final rawData = next['block_data'] ?? next['data'];

      if (blockType.isEmpty) return next;

      final normalized = _normalizeBlockData(
        blockTypeRaw: blockType,
        rawBlockData: rawData,
      );

      // Keep both key styles in sync when present.
      if (next.containsKey('block_data') || !next.containsKey('data')) {
        next['block_data'] = normalized;
      }
      if (next.containsKey('data')) {
        next['data'] = normalized;
      }

      return next;
    }).toList();
  }

  List<WebsiteBanner> _banners = [];
  List<FeaturedProduct> _featuredProducts = [];
  List<WebsiteContent> _contents = [];
  Map<String, String> _settings = {};
  List<ThemePreset> _themePresets = [];
  List<OnlineOrder> _orders = [];
  List<Map<String, dynamic>> _blocks = []; // Visual Editor blocks

  bool _isLoading = false;
  bool _isInitializing = false;
  String? _error;
  String? _ordersLoadError;
  String? _ordersEnrichmentWarning;
  bool _disposed = false; // Track disposal state
  bool _notifyScheduled = false;
  bool _hasLoadedForTenant =
      false; // Track if loadBlocksForTenant completed (even with no blocks)
  bool _hasLoadedPublicStoreDataForTenant = false;

  String? _boundTenantId;
  String? _settingsProjectionTenantId;
  int _tenantScopeGeneration = 0;
  _WebsiteScopedLoad<void>? _publicStoreLoad;
  _WebsiteScopedLoad<List<Map<String, dynamic>>>? _blocksLoad;
  _WebsiteScopedLoad<Map<String, String>>? _settingsLoad;
  final Map<String, _WebsiteScopedLoad<void>> _pageLoadsByTenant = {};
  _WebsiteScopedLoad<bool>? _navigationLoad;

  // Realtime subscriptions
  RealtimeChannel? _ordersChannel;

  // ============================================================
  // PAGE SNAPSHOTS - instant paint, followed by mandatory origin revalidation
  // ============================================================
  static const Duration _cacheTTL = Duration(seconds: 30);
  static final WebsitePageSnapshotCache _pageCache = WebsitePageSnapshotCache(
    ttl: _cacheTTL,
    retainFor: const Duration(hours: 24),
  );
  final ValueNotifier<int> _cmsPageFreshnessSignal = ValueNotifier<int>(0);

  /// Requests an origin revalidation from the currently visible CMS page.
  ///
  /// This signal is deliberately separate from [notifyListeners]: periodic
  /// freshness checks must not rebuild the entire storefront shell. Route
  /// owners listen to it and revalidate only while they are ticker-enabled.
  ValueListenable<int> get cmsPageFreshnessSignal => _cmsPageFreshnessSignal;

  void requestActiveCmsPageOriginRevalidation() {
    if (_disposed) return;
    _cmsPageFreshnessSignal.value = _cmsPageFreshnessSignal.value + 1;
  }

  /// Clear all cached pages (call when content is edited)
  static void clearPageCache() => _pageCache.clear();

  /// Clear cache for a specific slug
  static void invalidatePageCache(String slug, {String? tenantId}) {
    final normalizedSlug = _normalizePageSlug(slug);
    _pageCache.invalidateWhere((key) {
      final separator = key.indexOf('\u0000');
      if (separator < 0) return false;
      final keyTenantId = key.substring(0, separator);
      final keySlug = key.substring(separator + 1);
      return keySlug == normalizedSlug &&
          (tenantId == null || tenantId == keyTenantId);
    });
  }

  static String _normalizePageSlug(String slug) {
    var normalized = slug.trim().toLowerCase();
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String _pageCacheKey(String tenantId, String slug) =>
      '$tenantId\u0000${_normalizePageSlug(slug)}';

  List<WebsiteBanner> get banners => _banners;
  List<FeaturedProduct> get featuredProducts => _featuredProducts;
  List<WebsiteContent> get contents => _contents;
  Map<String, String> get settings => _settings;
  List<ThemePreset> get themePresets => List.unmodifiable(_themePresets);
  List<OnlineOrder> get orders => _orders;
  List<Map<String, dynamic>> get blocks => _blocks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get ordersLoadError => _ordersLoadError;
  String? get ordersEnrichmentWarning => _ordersEnrichmentWarning;
  bool get hasLoadedForTenant => _hasLoadedForTenant;
  bool hasSettingsForTenant(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    return normalizedTenantId.isNotEmpty &&
        _boundTenantId == normalizedTenantId &&
        _settingsProjectionTenantId == normalizedTenantId;
  }

  _WebsiteTenantScopeLease _bindTenantScope(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw ArgumentError.value(tenantId, 'tenantId', 'No puede estar vacío.');
    }

    if (_boundTenantId != normalizedTenantId) {
      _boundTenantId = normalizedTenantId;
      _tenantScopeGeneration++;
      _clearTenantOwnedProjections();
    }

    return _WebsiteTenantScopeLease(
      tenantId: normalizedTenantId,
      generation: _tenantScopeGeneration,
    );
  }

  bool _ownsTenantScope(_WebsiteTenantScopeLease lease) {
    return _boundTenantId == lease.tenantId &&
        _tenantScopeGeneration == lease.generation;
  }

  _WebsiteTenantScopeLease? _leaseForBoundTenant(String tenantId) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty || _boundTenantId != normalizedTenantId) {
      return null;
    }
    return _WebsiteTenantScopeLease(
      tenantId: normalizedTenantId,
      generation: _tenantScopeGeneration,
    );
  }

  bool isTenantProjectionActive(String tenantId) {
    return _leaseForBoundTenant(tenantId) != null;
  }

  bool _sameTenantScope(
    _WebsiteTenantScopeLease first,
    _WebsiteTenantScopeLease second,
  ) {
    return first.tenantId == second.tenantId &&
        first.generation == second.generation;
  }

  void _clearTenantOwnedProjections() {
    _banners = [];
    _featuredProducts = [];
    _contents = [];
    _settings = {};
    _themePresets = [];
    _orders = [];
    _blocks = [];
    _pages = [];
    _navigation = [];

    _hasLoadedForTenant = false;
    _hasLoadedPublicStoreDataForTenant = false;
    _settingsProjectionTenantId = null;
    _authoritativePagesTenantId = null;
    _hasAuthoritativePagePublication = false;
    _hasLoadedNavigationForTenant = false;
    _loadedNavigationTenantId = null;

    _publicStoreLoad = null;
    _blocksLoad = null;
    _settingsLoad = null;
    _pageLoadsByTenant.clear();
    _navigationLoad = null;

    _isLoading = false;
    _error = null;
    _ordersLoadError = null;
    _ordersEnrichmentWarning = null;

    final ordersChannel = _ordersChannel;
    _ordersChannel = null;
    if (ordersChannel != null) {
      unawaited(ordersChannel.unsubscribe());
    }

    // A blank projection is safer than rendering the previous tenant while
    // the new tenant's cache/origin request is in flight.
    _safeNotifyListeners();
  }

  /// Safe version of notifyListeners that checks disposal state
  void _safeNotifyListeners() {
    if (_disposed) return;

    // If we notify while Flutter is building/layouting/painting, Provider will
    // attempt to mark dependents dirty during the same build pass and can throw.
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inBuild = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (inBuild) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (_disposed) return;
        notifyListeners();
      });
      return;
    }

    notifyListeners();
  }

  // ============================================================================
  // UNIFIED PUBLIC STORE DATA LOADER (PERFORMANCE OPTIMIZED)
  // ============================================================================

  // Cloudflare edge cache URL - caches Supabase responses at edge nodes
  static const String _edgeCacheUrl =
      'https://vinabike-edge-cache.vinabike.workers.dev';

  // Local cache refresh TTL for public store bootstrap.
  // If we have recent cached settings+blocks, skip the immediate network refresh.
  static const Duration _publicStoreBootstrapRefreshTTL = Duration(seconds: 30);
  static const Duration _publicStoreBootstrapRetainTTL = Duration(hours: 24);

  /// Load ALL public store data - tries edge cache first, falls back to Supabase
  /// Edge cache: ~50ms (cache hit) vs Supabase direct: ~700ms
  Future<void> loadPublicStoreDataUnified(
    String tenantId, {
    bool forceRefresh = false,
  }) async {
    final lease = _bindTenantScope(tenantId);

    // Preserve the zero-I/O happy path, but only after the requested tenant is
    // bound and any prior tenant projection has been cleared.
    if (_hasLoadedPublicStoreDataForTenant && !forceRefresh) {
      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] loadPublicStoreDataUnified skipped (already loaded)');
      }
      return;
    }

    final existing = _publicStoreLoad;
    if (existing != null && _sameTenantScope(existing.lease, lease)) {
      await existing.future;
      return;
    }

    final load = _loadPublicStoreDataUnifiedWithinScope(
      lease,
      forceRefresh: forceRefresh,
    );
    final scopedLoad = _WebsiteScopedLoad<void>(lease: lease, future: load);
    _publicStoreLoad = scopedLoad;
    try {
      await load;
    } finally {
      if (identical(_publicStoreLoad, scopedLoad)) {
        _publicStoreLoad = null;
      }
    }
  }

  Map<String, dynamic>? _validatedPublicStorePayload(
    Object? candidate,
    _WebsiteTenantScopeLease lease, {
    required String source,
  }) {
    if (!_ownsTenantScope(lease) || candidate is! Map) return null;

    final payload = Map<String, dynamic>.from(candidate);
    final payloadTenantId = payload['tenant_id']?.toString().trim() ?? '';
    if (payloadTenantId != lease.tenantId ||
        payload['settings'] is! Map ||
        payload['blocks'] is! List) {
      debugPrint(
        '⚠️ [WebsiteService] Rejected $source public-store payload: '
        'tenant identity or shape mismatch.',
      );
      return null;
    }

    return payload;
  }

  Future<void> _loadPublicStoreDataUnifiedWithinScope(
    _WebsiteTenantScopeLease lease, {
    required bool forceRefresh,
  }) async {
    final swTotal = Stopwatch()..start();
    final tenantId = lease.tenantId;
    if (!_ownsTenantScope(lease)) return;

    // The unified payload owns fast settings and home blocks, but page-level
    // SEO remains editor-owned by website_pages. Load that small public list in
    // parallel so hydration cannot replace deploy-time metadata with generic
    // fallbacks on Home, Contact, or another dedicated public route.
    if (forceRefresh ||
        _pages.isEmpty ||
        _authoritativePagesTenantId != tenantId) {
      // The public wrapper owns best-effort error handling; it binds
      // synchronously to this same lease before the first await.
      unawaited(loadPagesForTenant(tenantId));
    }

    // If we already have recent cached settings+blocks, skip immediate network refresh.
    // This is especially important on mobile where TLS/DNS can cost ~1s.
    if (!forceRefresh && _hasFreshPublicStoreCache(tenantId)) {
      final settingsLoaded = _loadSettingsFromSynchronousCacheInternal(
        lease,
        notify: false,
        parseThemePresets: false,
      );
      final blocksLoaded = _loadBlocksFromSynchronousCacheInternal(
        lease,
        notify: false,
      );

      // A refresh timestamp without both payloads is not a usable fast path.
      if (!settingsLoaded || !blocksLoaded || !_ownsTenantScope(lease)) {
        if (_perfLogsEnabled) {
          debugPrint(
              '⚠️ [PublicStorePerf] Fresh cache marker had an incomplete payload');
        }
      } else {
        // Ensure navigation is available too (sync cache first, then background refresh).
        _loadNavigationFromSynchronousCacheInternal(lease, notify: false);
        if (hasVisibleHeaderNavigation) {
          // Fire-and-forget refresh: navigation changes are rare, but we still
          // want the header/footer to be correct when settings+blocks are fresh.
          unawaited(
            _loadNavigationForTenantWithinScope(
              lease,
              notify: true,
              forceRefresh: true,
            ),
          );
        } else {
          await _loadNavigationForTenantWithinScope(
            lease,
            notify: true,
            forceRefresh: true,
          );
        }

        if (!_ownsTenantScope(lease)) return;
        _hasLoadedForTenant = true;
        _hasLoadedPublicStoreDataForTenant = true;
        _safeNotifyListeners();
        if (_perfLogsEnabled) {
          debugPrint(
              '⏱️ [PublicStorePerf] loadPublicStoreDataUnified skipped (fresh local cache)');
          debugPrint(
              '⏱️ [PublicStorePerf] Total loadPublicStoreDataUnified: ${swTotal.elapsedMilliseconds}ms (source=LOCAL_CACHE_FRESH)');
        }
        return;
      }
    }

    try {
      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] loadPublicStoreDataUnified start tenant=$tenantId');
      }

      // Try edge cache first (Cloudflare Worker - 5 min TTL)
      // Cache HIT: ~100ms, Cache MISS: ~1000ms
      Map<String, dynamic>? response;
      String source = 'unknown';

      // 1. Try PRE-FETCHED data (injected by index.html)
      // This is the fastest path (0ms wait if download is faster than app load)
      // NOTE: For explicit user refresh (logo/home), skip prefetch to avoid
      // reusing stale boot-time data.
      if (!forceRefresh) {
        try {
          final swPrefetch = Stopwatch()..start();
          final preloaded = await _preloadedStoreDataLoader(tenantId);
          if (!_ownsTenantScope(lease)) return;
          if (preloaded != null) {
            response = _validatedPublicStorePayload(
              preloaded,
              lease,
              source: 'PREFETCH_JS',
            );
            if (response != null) {
              source = 'PREFETCH_JS';
              if (_perfLogsEnabled) {
                debugPrint(
                    '⏱️ [PublicStorePerf] Source=$source step=${swPrefetch.elapsedMilliseconds}ms');
              }
            }
          }
          if (response == null) {
            if (_perfLogsEnabled) {
              debugPrint(
                  '⏱️ [PublicStorePerf] Prefetch miss: ${swPrefetch.elapsedMilliseconds}ms');
            }
          }
        } catch (e) {
          if (_perfLogsEnabled) {
            debugPrint('⏱️ [PublicStorePerf] Prefetch error: $e');
          }
        }
      }

      // 2. Try edge cache (if pre-fetch missed)
      // Explicit force refreshes should bypass cached worker responses.
      if (response == null && !forceRefresh) {
        try {
          final swEdge = Stopwatch()..start();
          final cacheResponse = await _tryEdgeCache(tenantId);
          if (!_ownsTenantScope(lease)) return;
          if (cacheResponse != null) {
            response = _validatedPublicStorePayload(
              cacheResponse,
              lease,
              source: 'EDGE_CACHE',
            );
            if (response != null) {
              source = cacheResponse['_cache'] == 'HIT'
                  ? 'EDGE_CACHE_HIT'
                  : 'EDGE_CACHE_MISS';
              if (_perfLogsEnabled) {
                debugPrint(
                    '⏱️ [PublicStorePerf] Source=$source step=${swEdge.elapsedMilliseconds}ms');
              }
            }
          }
          if (response == null) {
            if (_perfLogsEnabled) {
              debugPrint(
                  '⏱️ [PublicStorePerf] Edge cache miss/null: ${swEdge.elapsedMilliseconds}ms');
            }
          }
        } catch (e) {
          if (_perfLogsEnabled) {
            debugPrint('⏱️ [PublicStorePerf] Edge cache error: $e');
          }
        }
      }

      // Fallback to direct Supabase RPC if edge cache fails
      if (response == null) {
        final swRpc = Stopwatch()..start();
        final directResponse = await _supabase
            .rpc('get_public_store_data', params: {'p_tenant_id': tenantId});
        if (!_ownsTenantScope(lease)) return;
        response = _validatedPublicStorePayload(
          directResponse,
          lease,
          source: 'SUPABASE_DIRECT',
        );
        if (response == null) {
          throw StateError(
            'La proyección pública no declaró el tenant solicitado.',
          );
        }
        source = 'SUPABASE_DIRECT';

        if (_perfLogsEnabled) {
          debugPrint(
              '⏱️ [PublicStorePerf] Source=$source step=${swRpc.elapsedMilliseconds}ms');
        }
      }

      // debugPrint(
      //     '⏱️ [WebsiteService] Data loaded ($source): ${sw.elapsedMilliseconds}ms');

      // Parse settings/blocks.
      // NOTE: On the public store we don't need theme presets, so avoid
      // decoding them here (saves work on the UI isolate).
      final settingsData = filterPublicWebsiteSettingsForCache(
        response['settings'] is Map
            ? Map<String, dynamic>.from(response['settings'] as Map)
            : const <String, dynamic>{},
      );
      final blocksData = response['blocks'] as List? ?? [];

      // If we already rendered from sync cache and the network returns the
      // exact same payload, avoid triggering a full rebuild.
      final prefs = _prefs;
      final cachedSettingsJson = prefs?.getString(
        _publicStoreCacheKey('settings', tenantId),
      );
      final cachedBlocksJson = prefs?.getString(
        _publicStoreCacheKey('blocks', tenantId),
      );
      final hasExistingData = _settings.isNotEmpty || _blocks.isNotEmpty;

      bool isSameAsCache = false;
      if (cachedSettingsJson != null && cachedBlocksJson != null) {
        try {
          final newSettingsJson = jsonEncode(settingsData);
          final newBlocksJson = jsonEncode(blocksData);
          isSameAsCache = hasExistingData &&
              cachedSettingsJson == newSettingsJson &&
              cachedBlocksJson == newBlocksJson;
        } catch (_) {
          // If encoding fails for any reason, just treat as changed.
          isSameAsCache = false;
        }
      }

      if (isSameAsCache) {
        // Even if settings/blocks haven't changed, we still need navigation.
        // Load from cache instantly and refresh in background when we already
        // have usable header navigation; otherwise wait for one real fetch.
        _loadNavigationFromSynchronousCacheInternal(lease, notify: false);
        if (hasVisibleHeaderNavigation) {
          unawaited(
            _loadNavigationForTenantWithinScope(
              lease,
              notify: true,
              forceRefresh: true,
            ),
          );
        } else {
          await _loadNavigationForTenantWithinScope(
            lease,
            notify: true,
            forceRefresh: true,
          );
        }

        if (!_ownsTenantScope(lease)) return;
        await _persistPublicStoreLastRefresh(lease);
        if (!_ownsTenantScope(lease)) return;
        _hasLoadedForTenant = true;
        _hasLoadedPublicStoreDataForTenant = true;

        if (_perfLogsEnabled) {
          debugPrint(
              '⏱️ [PublicStorePerf] Network payload matches cache; skipping notify');
          debugPrint(
              '⏱️ [PublicStorePerf] Total loadPublicStoreDataUnified: ${swTotal.elapsedMilliseconds}ms (source=$source)');
        }
        return;
      }

      _settings = settingsData.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      _settingsProjectionTenantId = tenantId;

      _blocks = _normalizeBlocksList(
        blocksData
            .whereType<Map>()
            .map((block) => Map<String, dynamic>.from(block))
            .toList(growable: false),
      );

      if (_perfLogsEnabled) {
        debugPrint('⏱️ [PublicStorePerf] Parsed data: '
            '${_settings.length} settings, ${_blocks.length} blocks');
      }

      // Persist caches and refresh time BEFORE we log completion.
      // This makes the next app launch able to skip the edge-cache call.
      await _persistSettingsToLocalCache(lease, settingsData);
      await _persistBlocksToLocalCache(lease, _blocks);
      await _persistPublicStoreLastRefresh(lease);
      if (!_ownsTenantScope(lease)) return;

      // Navigation is NOT included in get_public_store_data yet, so load it
      // separately. Do not block settings/blocks completion if a usable
      // header is already present from cache or bootstrap preflight.
      if (hasVisibleHeaderNavigation) {
        unawaited(
          _loadNavigationForTenantWithinScope(
            lease,
            notify: true,
            forceRefresh: true,
          ),
        );
      } else {
        await _loadNavigationForTenantWithinScope(
          lease,
          notify: false,
          forceRefresh: true,
        );
      }

      if (!_ownsTenantScope(lease)) return;
      if (_perfLogsEnabled) {
        debugPrint('✅ [WebsiteService] Load complete ($source): '
            '${_settings.length} settings, ${_blocks.length} blocks');
      }

      if (!_ownsTenantScope(lease)) return;
      _hasLoadedForTenant = true;
      _hasLoadedPublicStoreDataForTenant = true;
      _safeNotifyListeners();

      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] Total loadPublicStoreDataUnified: ${swTotal.elapsedMilliseconds}ms (source=$source)');
      }
    } catch (e) {
      if (!_ownsTenantScope(lease)) return;
      debugPrint(
          '⚠️ [WebsiteService] All methods failed, falling back to separate queries: $e');

      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] Unified load failed after ${swTotal.elapsedMilliseconds}ms: $e');
      }

      // Fallback to separate queries if RPC doesn't exist yet
      await Future.wait([
        _loadSettingsForTenantWithinScope(lease),
        _loadBlocksForTenantWithinScope(lease),
        _loadNavigationForTenantWithinScope(
          lease,
          notify: false,
          forceRefresh: true,
        ),
      ]);
      if (!_ownsTenantScope(lease)) return;
      _hasLoadedForTenant = true;
      _hasLoadedPublicStoreDataForTenant = true;
      _safeNotifyListeners();
    }
  }

  // Shared preferences instance (injected from main)
  static SharedPreferences? _prefs;

  static void setSharedPreferences(SharedPreferences prefs) {
    _prefs = prefs;
  }

  void _evictLegacyPublicStoreCache(String tenantId) {
    final prefs = _prefs;
    final normalizedTenantId = tenantId.trim();
    if (prefs == null ||
        normalizedTenantId.isEmpty ||
        !_legacyPublicCacheEvictionStarted.add(normalizedTenantId)) {
      return;
    }

    // The legacy namespace predates the public settings projection. Never
    // hydrate it, even during the stale-while-revalidate paint path.
    unawaited(
      Future.wait<bool>([
        prefs.remove('website_settings_$normalizedTenantId'),
        prefs.remove('website_blocks_$normalizedTenantId'),
        prefs.remove('website_navigation_$normalizedTenantId'),
        prefs.remove('website_public_store_last_refresh_$normalizedTenantId'),
      ]),
    );
  }

  bool _hasFreshPublicStoreCache(String tenantId) {
    return _hasPublicStoreCacheWithin(
      tenantId,
      _publicStoreBootstrapRefreshTTL,
    );
  }

  bool _hasRetainedPublicStoreCache(String tenantId) {
    return _hasPublicStoreCacheWithin(
      tenantId,
      _publicStoreBootstrapRetainTTL,
    );
  }

  bool _hasPublicStoreCacheWithin(String tenantId, Duration maxAge) {
    if (_prefs == null) return false;
    _evictLegacyPublicStoreCache(tenantId);

    final settingsKey = _publicStoreCacheKey('settings', tenantId);
    final blocksKey = _publicStoreCacheKey('blocks', tenantId);
    final lastRefreshKey = _publicStoreCacheKey('last_refresh', tenantId);

    final hasSettings = _prefs!.getString(settingsKey) != null;
    final hasBlocks = _prefs!.getString(blocksKey) != null;
    if (!hasSettings || !hasBlocks) return false;

    final lastRefreshMs = _prefs!.getInt(lastRefreshKey);
    if (lastRefreshMs == null) return false;

    final lastRefresh = DateTime.fromMillisecondsSinceEpoch(lastRefreshMs);
    return DateTime.now().difference(lastRefresh) < maxAge;
  }

  Future<void> _persistPublicStoreLastRefresh(
    _WebsiteTenantScopeLease lease,
  ) async {
    if (!_ownsTenantScope(lease)) return;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      if (!_ownsTenantScope(lease)) return;
      _prefs = prefs;
      final key = _publicStoreCacheKey('last_refresh', lease.tenantId);
      await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Ignore cache write errors
    }
  }

  /// Loads BOTH settings + blocks from the synchronous cache and notifies once.
  /// This reduces boot-time rebuild churn (helps avoid skipped frames).
  bool preloadPublicStoreFromSynchronousCache(String tenantId) {
    final lease = _bindTenantScope(tenantId);

    // Paint a bounded stale snapshot immediately. The bootstrap always starts
    // a direct origin revalidation when this returns true, so retention never
    // becomes freshness authority.
    if (!_hasRetainedPublicStoreCache(lease.tenantId)) {
      return false;
    }

    final settingsLoaded = _loadSettingsFromSynchronousCacheInternal(
      lease,
      notify: false,
      parseThemePresets: false,
    );
    final blocksLoaded = _loadBlocksFromSynchronousCacheInternal(
      lease,
      notify: false,
    );

    final navLoaded = _loadNavigationFromSynchronousCacheInternal(
      lease,
      notify: false,
    );

    if (settingsLoaded && _perfLogsEnabled) {
      debugPrint('💾 [WebsiteService] Loaded settings from SYNC cache (0ms)');
    }
    if (blocksLoaded && _perfLogsEnabled) {
      debugPrint('💾 [WebsiteService] Loaded blocks from SYNC cache (0ms)');
    }
    if (navLoaded && _perfLogsEnabled) {
      debugPrint('💾 [WebsiteService] Loaded navigation from SYNC cache (0ms)');
    }

    if (settingsLoaded || blocksLoaded || navLoaded) {
      _safeNotifyListeners();
    }

    return settingsLoaded || blocksLoaded || navLoaded;
  }

  /// Try to load settings from synchronous cache (0ms wait)
  /// Returns true if settings were successfully loaded
  bool loadSettingsFromSynchronousCache(String tenantId) {
    final lease = _bindTenantScope(tenantId);
    return _loadSettingsFromSynchronousCacheInternal(lease, notify: true);
  }

  bool _loadSettingsFromSynchronousCacheInternal(
    _WebsiteTenantScopeLease lease, {
    required bool notify,
    bool parseThemePresets = true,
  }) {
    if (_prefs == null || !_ownsTenantScope(lease)) return false;
    final tenantId = lease.tenantId;
    _evictLegacyPublicStoreCache(tenantId);

    try {
      final cacheKey = _publicStoreCacheKey('settings', tenantId);
      final cachedJson = _prefs!.getString(cacheKey);

      if (cachedJson != null) {
        final decoded = Map<String, dynamic>.from(
          jsonDecode(cachedJson) as Map,
        );
        final settingsData = filterPublicWebsiteSettingsForCache(decoded);
        if (settingsData.length != decoded.length) {
          unawaited(_prefs!.setString(cacheKey, jsonEncode(settingsData)));
        }
        if (!_ownsTenantScope(lease)) return false;
        _settings =
            settingsData.map((k, v) => MapEntry(k, v?.toString() ?? ''));
        _settingsProjectionTenantId = tenantId;
        if (parseThemePresets) {
          _themePresets = _parseThemePresets(_settings['theme_presets']);
        }

        if (notify) {
          debugPrint(
              '💾 [WebsiteService] Loaded settings from SYNC cache (0ms)');
          _safeNotifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ [WebsiteService] Failed to load sync cache: $e');
    }
    return false;
  }

  /// Try to load blocks from synchronous cache (0ms wait)
  /// Returns true if blocks were successfully loaded
  bool loadBlocksFromSynchronousCache(String tenantId) {
    final lease = _bindTenantScope(tenantId);
    return _loadBlocksFromSynchronousCacheInternal(lease, notify: true);
  }

  bool _loadBlocksFromSynchronousCacheInternal(
    _WebsiteTenantScopeLease lease, {
    required bool notify,
  }) {
    if (_prefs == null || !_ownsTenantScope(lease)) return false;
    final tenantId = lease.tenantId;
    _evictLegacyPublicStoreCache(tenantId);

    try {
      final cacheKey = _publicStoreCacheKey('blocks', tenantId);
      final cachedJson = _prefs!.getString(cacheKey);

      if (cachedJson != null) {
        final blocksData = jsonDecode(cachedJson) as List<dynamic>;
        if (!_ownsTenantScope(lease)) return false;
        _blocks = _normalizeBlocksList(
          blocksData
              .whereType<Map>()
              .map((block) => Map<String, dynamic>.from(block))
              .toList(growable: false),
        );

        if (notify) {
          debugPrint('💾 [WebsiteService] Loaded blocks from SYNC cache (0ms)');
          _safeNotifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ [WebsiteService] Failed to load blocks sync cache: $e');
    }
    return false;
  }

  /// Load settings from local device cache (SharedPreferences)
  /// Returns true if settings were successfully loaded
  Future<bool> loadSettingsFromLocalCache(String tenantId) async {
    final lease = _bindTenantScope(tenantId);

    // If we have sync cache, try that first
    if (_prefs != null) {
      return _loadSettingsFromSynchronousCacheInternal(lease, notify: true);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs; // Store for future sync access
      if (!_ownsTenantScope(lease)) return false;
      return _loadSettingsFromSynchronousCacheInternal(lease, notify: true);
    } catch (e) {
      debugPrint('⚠️ [WebsiteService] Failed to load local cache: $e');
    }
    return false;
  }

  Future<void> _persistSettingsToLocalCache(
    _WebsiteTenantScopeLease lease,
    Map<String, dynamic> settingsData,
  ) async {
    if (!_ownsTenantScope(lease)) return;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      if (!_ownsTenantScope(lease)) return;
      _prefs = prefs;
      final cacheKey = _publicStoreCacheKey('settings', lease.tenantId);
      final publicSettings = filterPublicWebsiteSettingsForCache(settingsData);
      await prefs.setString(cacheKey, jsonEncode(publicSettings));
    } catch (e) {
      // Ignore cache write errors
    }
  }

  Future<void> _persistBlocksToLocalCache(
    _WebsiteTenantScopeLease lease,
    List<Map<String, dynamic>> blocks,
  ) async {
    if (!_ownsTenantScope(lease)) return;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      if (!_ownsTenantScope(lease)) return;
      _prefs = prefs;
      final cacheKey = _publicStoreCacheKey('blocks', lease.tenantId);
      await prefs.setString(cacheKey, jsonEncode(blocks));
    } catch (e) {
      // Ignore cache write errors
    }
  }

  /// Try to fetch data from Cloudflare edge cache
  /// Returns null if cache is unavailable, otherwise returns the cached data
  Future<Map<String, dynamic>?> _tryEdgeCache(String tenantId) async {
    try {
      final uri = Uri.parse('$_edgeCacheUrl/cache/public-store-data');

      final response = await _httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'p_tenant_id': tenantId}),
          )
          .timeout(const Duration(seconds: 5)); // Don't wait too long

      if (response.statusCode == 200) {
        // Avoid blocking the UI isolate on mobile.
        // compute() uses a background isolate on native platforms.
        return await compute(_decodeJsonMap, response.body);
      }
      debugPrint(
          '⚠️ [WebsiteService] Edge cache returned status: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('⚠️ [WebsiteService] Edge cache request failed: $e');
      return null;
    }
  }

  static Map<String, dynamic> _decodeJsonMap(String body) {
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Opens a quick connection to the edge-cache host to warm up DNS/TLS.
  /// This can shave noticeable time off the first real request on mobile.
  Future<void> warmUpEdgeCacheHost() async {
    if (kIsWeb) return; // Web uses preconnect/prefetch in index.html.
    try {
      final uri = Uri.parse(_edgeCacheUrl);
      await _httpClient.get(uri).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignore warmup errors
    }
  }

  // ============================================================================
  // BANNERS (DEPRECATED - Use website_blocks instead)
  // ============================================================================
  // Note: These methods are kept for backward compatibility with old code
  // but are no longer used in the public store. Hero sections now use
  // website_blocks with block_type='hero' or 'carousel'.

  @Deprecated('Use loadBlocks() and filter for block_type="hero" instead')
  Future<void> loadBanners() async {
    _WebsiteTenantScopeLease? lease;

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }
      lease = _bindTenantScope(tenantId);
      _isLoading = true;
      _error = null;
      if (!_isInitializing) _safeNotifyListeners();

      final response = await _supabase
          .from('website_banners')
          .select()
          .eq('tenant_id', tenantId)
          .order('order_index');
      if (!_ownsTenantScope(lease)) return;

      _banners = (response as List)
          .map((json) => WebsiteBanner.fromJson(json))
          .toList();

      _error = null;
    } catch (e) {
      if (lease == null || _ownsTenantScope(lease)) {
        _error = 'Error al cargar banners: $e';
        debugPrint(_error);
      }
    } finally {
      if (lease == null || _ownsTenantScope(lease)) {
        _isLoading = false;
        _safeNotifyListeners();
      }
    }
  }

  @Deprecated('Use saveBlocks() with block_type="hero" instead')
  Future<void> saveBanner(WebsiteBanner banner) async {
    try {
      final tenantId =
          await _tenantService.getTenantId(); // ✅ Use async version
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      final data = banner.toJson();
      data['tenant_id'] = tenantId; // ✅ Add tenant_id
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('website_banners').upsert(data);

      await loadBanners();
    } catch (e) {
      _error = 'Error al guardar banner: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  @Deprecated('Use the page-block editor and saveBlocks() instead')
  Future<void> deleteBanner(String id) async {
    try {
      await _supabase.from('website_banners').delete().eq('id', id);

      await loadBanners();
    } catch (e) {
      _error = 'Error al eliminar banner: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  @Deprecated('Block reordering is handled via saveBlocks()')
  Future<void> reorderBanners(List<WebsiteBanner> reorderedBanners) async {
    try {
      for (int i = 0; i < reorderedBanners.length; i++) {
        await _supabase
            .from('website_banners')
            .update({'order_index': i}).eq('id', reorderedBanners[i].id);
      }

      await loadBanners();
    } catch (e) {
      _error = 'Error al reordenar banners: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // WEBSITE BLOCKS (Odoo-style Visual Editor)
  // ============================================================================

  /// Load blocks for the HOME page only (legacy method for Odoo editor)
  /// This ensures the editor doesn't mix blocks from all pages
  Future<void> loadBlocks() async {
    debugPrint('[WebsiteService] loadBlocks started');
    _WebsiteTenantScopeLease? lease;

    try {
      // Get current tenant_id
      debugPrint('[WebsiteService] Getting tenant ID...');
      final tenantId = await _tenantService.getTenantId();
      debugPrint('[WebsiteService] Got tenant ID: $tenantId');
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }
      lease = _bindTenantScope(tenantId);
      _isLoading = true;
      _error = null;
      if (!_isInitializing) _safeNotifyListeners();

      // First, find the home page ID
      String? homePageId;
      await _loadPagesForTenantWithinScope(lease); // Ensure pages are loaded
      if (!_ownsTenantScope(lease)) return;
      final homePage = _pages.firstWhere(
        (p) => p.isHome && p.isPublished,
        orElse: () => _pages.isNotEmpty
            ? _pages.first
            : throw Exception('No pages found'),
      );
      homePageId = homePage.id;
      debugPrint('[WebsiteService] Home page ID: $homePageId');

      debugPrint(
          '[WebsiteService] Querying website_blocks for home page only...');
      final response = await _supabase
          .from('website_blocks')
          .select()
          .eq('tenant_id', tenantId) // ✅ Filter by tenant
          .eq('page_id', homePageId) // ✅ Filter by HOME PAGE ONLY
          .order('order_index', ascending: true);
      if (!_ownsTenantScope(lease)) return;
      debugPrint(
          '[WebsiteService] Query complete, got ${(response as List).length} blocks');

      final data = List<Map<String, dynamic>>.from(response);
      data.sort(
        (a, b) => (a['order_index'] ?? 0).compareTo(b['order_index'] ?? 0),
      );

      _blocks = _normalizeBlocksList(data);
      _hasLoadedForTenant = true; // Also mark as loaded for ERP preview mode
      _error = null;
    } catch (e) {
      if (lease == null || _ownsTenantScope(lease)) {
        _error = 'Error al cargar bloques: $e';
        debugPrint(_error);
        _hasLoadedForTenant = true; // Mark loaded even on error
      }
    } finally {
      if (lease == null || _ownsTenantScope(lease)) {
        _isLoading = false;
        debugPrint('[WebsiteService] loadBlocks complete');
        _safeNotifyListeners();
      }
    }
  }

  /// Load blocks for a specific tenant's HOME PAGE (used by public store for anonymous visitors)
  /// This method does NOT require authentication - it uses the provided tenant_id
  /// from subdomain detection (PublicStoreTenantProvider)
  ///
  /// OPTIMIZED: Uses a single query with JOIN to get home page + blocks together

  Future<List<Map<String, dynamic>>> loadBlocksForTenant(
      String tenantId) async {
    final lease = _bindTenantScope(tenantId);

    // A cache hit is valid only after binding has proved that `_blocks`
    // belongs to this exact tenant generation.
    if (_hasLoadedForTenant) {
      debugPrint(
          '[WebsiteService] Already loaded for tenant, returning cached blocks: ${_blocks.length}');
      return _blocks;
    }

    return _loadBlocksForTenantWithinScope(lease);
  }

  Future<List<Map<String, dynamic>>> _loadBlocksForTenantWithinScope(
    _WebsiteTenantScopeLease lease,
  ) async {
    if (!_ownsTenantScope(lease)) return const [];

    final existing = _blocksLoad;
    if (existing != null && _sameTenantScope(existing.lease, lease)) {
      return existing.future;
    }

    final load = _loadBlocksForTenantFromOrigin(lease);
    final scopedLoad = _WebsiteScopedLoad<List<Map<String, dynamic>>>(
      lease: lease,
      future: load,
    );
    _blocksLoad = scopedLoad;
    try {
      return await load;
    } finally {
      if (identical(_blocksLoad, scopedLoad)) {
        _blocksLoad = null;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadBlocksForTenantFromOrigin(
    _WebsiteTenantScopeLease lease,
  ) async {
    final sw = Stopwatch()..start();
    final tenantId = lease.tenantId;

    try {
      debugPrint('[WebsiteService] Loading blocks for tenant: $tenantId');

      // OPTIMIZED: Single query with JOIN - get home page with its blocks in one round trip
      final pagesWithBlocks = await _supabase
          .from('website_pages')
          .select('id, website_blocks(*)')
          .eq('tenant_id', tenantId)
          .eq('is_home', true)
          .eq('is_published', true)
          .limit(1);
      if (!_ownsTenantScope(lease)) return const [];

      debugPrint(
          '⏱️ [WebsiteService] Pages+Blocks JOIN query: ${sw.elapsedMilliseconds}ms');

      List<Map<String, dynamic>> data = [];

      if ((pagesWithBlocks as List).isNotEmpty) {
        final homePage = pagesWithBlocks[0];
        final homePageId = homePage['id']?.toString();
        debugPrint('[WebsiteService] Found home page: $homePageId');

        // Extract blocks from the JOIN result
        final blocks = homePage['website_blocks'] as List? ?? [];
        data = List<Map<String, dynamic>>.from(blocks);
      } else {
        // Fallback: try first published page
        final firstPageWithBlocks = await _supabase
            .from('website_pages')
            .select('id, website_blocks(*)')
            .eq('tenant_id', tenantId)
            .eq('is_published', true)
            .order('created_at', ascending: true)
            .limit(1);
        if (!_ownsTenantScope(lease)) return const [];

        if ((firstPageWithBlocks as List).isNotEmpty) {
          final blocks =
              firstPageWithBlocks[0]['website_blocks'] as List? ?? [];
          data = List<Map<String, dynamic>>.from(blocks);
        }
      }

      if (data.isEmpty) {
        debugPrint('[WebsiteService] No blocks found for tenant $tenantId');
        if (!_ownsTenantScope(lease)) return const [];
        _blocks = [];
        _hasLoadedForTenant = true;
        _safeNotifyListeners();
        return _blocks;
      }

      // Sort by order_index
      data.sort(
        (a, b) => (a['order_index'] ?? 0).compareTo(b['order_index'] ?? 0),
      );

      debugPrint(
          '⏱️ [WebsiteService] Total loadBlocksForTenant: ${sw.elapsedMilliseconds}ms (${data.length} blocks)');

      // Cache the blocks for reuse (normalized)
      final normalizedBlocks = _normalizeBlocksList(data);
      if (!_ownsTenantScope(lease)) return const [];
      _blocks = normalizedBlocks;
      _hasLoadedForTenant = true;
      _safeNotifyListeners();

      return normalizedBlocks;
    } catch (e) {
      if (!_ownsTenantScope(lease)) return const [];
      debugPrint('[WebsiteService] Error loading blocks for tenant: $e');
      _hasLoadedForTenant = true; // Mark as loaded even on error
      _safeNotifyListeners();
      return const [];
    }
  }

  Future<void> saveBlocks(List<Map<String, dynamic>> blocks,
      {String? tenantId}) async {
    try {
      final effectiveTenantId = tenantId ?? await _tenantService.getTenantId();
      if (effectiveTenantId == null) {
        throw Exception('No tenant ID found');
      }
      final homePage = await getHomePageForTenant(
            effectiveTenantId,
            rethrowErrors: true,
          ) ??
          await createPage(
            WebsitePage(
              id: '',
              tenantId: effectiveTenantId,
              slug: 'home',
              title: 'Inicio',
              isPublished: true,
              isHome: true,
              isSystem: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            tenantId: effectiveTenantId,
          );

      _blocks = await replacePageBlocks(
        tenantId: effectiveTenantId,
        pageId: homePage.id,
        blocks: blocks,
      );
      _hasLoadedForTenant = true;
      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al guardar bloques: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  /// Canonical page-block persistence operation.
  ///
  /// PostgreSQL validates the entire payload before the scoped DELETE and
  /// performs DELETE + INSERT in one transaction. The returned rows are the
  /// database-confirmed document and therefore require no fallible readback.
  Future<List<Map<String, dynamic>>> replacePageBlocks({
    required String tenantId,
    required String pageId,
    required List<Map<String, dynamic>> blocks,
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    final lease = _leaseForBoundTenant(tenantId);
    try {
      writeGuard?.call();
      final payload = blocks.map((block) {
        final blockType =
            (block['type'] ?? block['block_type'] ?? '').toString().trim();
        final rawBlockData = block['data'] ?? block['block_data'] ?? {};
        final normalizedBlockData = blockType.isNotEmpty
            ? _normalizeBlockData(
                blockTypeRaw: blockType,
                rawBlockData: rawBlockData,
              )
            : (rawBlockData is Map
                ? Map<String, dynamic>.from(rawBlockData)
                : <String, dynamic>{});
        final id = block['id']?.toString().trim() ?? '';

        return <String, dynamic>{
          if (id.isNotEmpty) 'id': id,
          'block_type': blockType,
          'block_data': normalizedBlockData,
          'is_visible': block['isVisible'] ?? block['is_visible'] ?? true,
        };
      }).toList(growable: false);

      final response = await _supabase.rpc(
        'replace_page_blocks',
        params: {
          'p_tenant_id': tenantId,
          'p_page_id': pageId,
          'p_blocks': payload,
        },
      );
      // Post-response guard BEFORE any parse/cache/publication: A's late
      // result may be durable server-side but never touches B locally.
      writeGuard?.call();
      if (response is! List) {
        throw StateError(
          'replace_page_blocks devolvió una respuesta no válida.',
        );
      }

      final rows = response
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      rows.sort(
        (left, right) =>
            ((left['order_index'] as num?)?.toInt() ?? 0).compareTo(
          (right['order_index'] as num?)?.toInt() ?? 0,
        ),
      );
      final normalized = _normalizeBlocksList(rows);
      WebsiteService.clearPageCache();
      return normalized;
    } catch (e) {
      // A late failure (5xx/network/malformed) after an identity change
      // reclassifies as SUPERSEDED before any error publication.
      if (e is! WebsiteEditorWriteSupersededException) {
        writeGuard?.call();
      }
      if (e is! WebsiteEditorWriteSupersededException &&
          lease != null &&
          _ownsTenantScope(lease)) {
        _error = 'Error al reemplazar bloques de página: $e';
        debugPrint(_error);
        _safeNotifyListeners();
      }
      rethrow;
    }
  }

  // ============================================================================
  // FEATURED PRODUCTS
  // ============================================================================

  Future<void> loadFeaturedProducts() async {
    _WebsiteTenantScopeLease? lease;

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }
      lease = _bindTenantScope(tenantId);
      _isLoading = true;
      _error = null;
      if (!_isInitializing) _safeNotifyListeners();

      final response = await _supabase
          .from('featured_products')
          .select()
          .eq('tenant_id', tenantId)
          .order('order_index');
      if (!_ownsTenantScope(lease)) return;

      _featuredProducts = (response as List)
          .map((json) => FeaturedProduct.fromJson(json))
          .toList();

      _error = null;
    } catch (e) {
      if (lease == null || _ownsTenantScope(lease)) {
        _error = 'Error al cargar productos destacados: $e';
        debugPrint(_error);
      }
    } finally {
      if (lease == null || _ownsTenantScope(lease)) {
        _isLoading = false;
        _safeNotifyListeners();
      }
    }
  }

  /// Load featured products for a specific tenant (used by public store for anonymous visitors)
  /// This method does NOT require authentication
  Future<List<FeaturedProduct>> loadFeaturedProductsForTenant(
      String tenantId) async {
    final lease = _bindTenantScope(tenantId);
    try {
      final response = await _supabase
          .from('featured_products')
          .select()
          .eq('tenant_id', lease.tenantId)
          .order('order_index');
      if (!_ownsTenantScope(lease)) return const [];

      final products = (response as List)
          .map((json) => FeaturedProduct.fromJson(json))
          .toList();

      // Also update internal state
      _featuredProducts = products;

      return products;
    } catch (e) {
      return const [];
    }
  }

  Future<void> addFeaturedProduct(String productId) async {
    try {
      final tenantId =
          await _tenantService.getTenantId(); // ✅ Use async version
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      // Get current max order index
      int maxOrder = 0;
      if (_featuredProducts.isNotEmpty) {
        maxOrder = _featuredProducts
            .map((fp) => fp.orderIndex)
            .reduce((a, b) => a > b ? a : b);
      }

      await _supabase.from('featured_products').insert({
        'tenant_id': tenantId, // ✅ Add tenant_id
        'product_id': productId,
        'active': true,
        'order_index': maxOrder + 1,
      });

      await loadFeaturedProducts();
    } catch (e) {
      _error = 'Error al agregar producto destacado: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<void> removeFeaturedProduct(String id) async {
    try {
      await _supabase.from('featured_products').delete().eq('id', id);

      await loadFeaturedProducts();
    } catch (e) {
      _error = 'Error al eliminar producto destacado: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<void> reorderFeaturedProducts(List<FeaturedProduct> reordered) async {
    try {
      for (int i = 0; i < reordered.length; i++) {
        await _supabase
            .from('featured_products')
            .update({'order_index': i}).eq('id', reordered[i].id);
      }

      await loadFeaturedProducts();
    } catch (e) {
      _error = 'Error al reordenar productos destacados: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // CONTENT
  // ============================================================================

  Future<void> loadContents() async {
    _WebsiteTenantScopeLease? lease;

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }
      lease = _bindTenantScope(tenantId);
      _isLoading = true;
      _error = null;
      if (!_isInitializing) _safeNotifyListeners();

      final response = await _supabase
          .from('website_content')
          .select()
          .eq('tenant_id', tenantId);
      if (!_ownsTenantScope(lease)) return;

      _contents = (response as List)
          .map((json) => WebsiteContent.fromJson(json))
          .toList();

      _error = null;
    } catch (e) {
      if (lease == null || _ownsTenantScope(lease)) {
        _error = 'Error al cargar contenido: $e';
        debugPrint(_error);
      }
    } finally {
      if (lease == null || _ownsTenantScope(lease)) {
        _isLoading = false;
        _safeNotifyListeners();
      }
    }
  }

  Future<void> saveContent(WebsiteContent content) async {
    try {
      final tenantId =
          await _tenantService.getTenantId(); // ✅ Use async version
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      final data = content.toJson();
      data['tenant_id'] = tenantId; // ✅ Add tenant_id
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('website_content').upsert(data);

      await loadContents();
    } catch (e) {
      _error = 'Error al guardar contenido: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  WebsiteContent? getContentById(String id) {
    try {
      return _contents.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  // ============================================================================
  // SETTINGS
  // ============================================================================

  Future<void> loadSettings() async {
    _WebsiteTenantScopeLease? lease;

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant ID available');
      }
      lease = _bindTenantScope(tenantId);
      _isLoading = true;
      _error = null;
      if (!_isInitializing) _safeNotifyListeners();

      await _loadSettingsForTenantWithinScope(lease);
      if (_ownsTenantScope(lease)) _error = null;
    } catch (e) {
      if (lease == null || _ownsTenantScope(lease)) {
        _error = 'Error al cargar configuración: $e';
        debugPrint(_error);
      }
    } finally {
      if (lease == null || _ownsTenantScope(lease)) {
        _isLoading = false;
        _safeNotifyListeners();
      }
    }
  }

  /// Load settings for a specific tenant (used by public store for anonymous visitors)
  /// This method does NOT require authentication
  Future<Map<String, String>> loadSettingsForTenant(
    String tenantId, {
    bool rethrowErrors = false,
  }) async {
    final lease = _bindTenantScope(tenantId);
    try {
      return await _loadSettingsForTenantWithinScope(lease);
    } catch (e) {
      if (!_ownsTenantScope(lease)) return const {};
      debugPrint('⏱️ [WebsiteService] Settings ERROR: $e');
      if (rethrowErrors) rethrow;
      return const {};
    }
  }

  Future<Map<String, String>> _loadSettingsForTenantWithinScope(
    _WebsiteTenantScopeLease lease,
  ) async {
    if (!_ownsTenantScope(lease)) return const {};

    final existing = _settingsLoad;
    if (existing != null && _sameTenantScope(existing.lease, lease)) {
      return existing.future;
    }

    final load = _loadSettingsForTenantFromOrigin(lease);
    final scopedLoad = _WebsiteScopedLoad<Map<String, String>>(
      lease: lease,
      future: load,
    );
    _settingsLoad = scopedLoad;
    try {
      return await load;
    } finally {
      if (identical(_settingsLoad, scopedLoad)) {
        _settingsLoad = null;
      }
    }
  }

  Future<Map<String, String>> _loadSettingsForTenantFromOrigin(
    _WebsiteTenantScopeLease lease,
  ) async {
    final sw = Stopwatch()..start();
    final tenantId = lease.tenantId;
    final response = await _supabase
        .from('website_settings')
        .select()
        .eq('tenant_id', tenantId);
    if (!_ownsTenantScope(lease)) return const {};

    debugPrint(
        '⏱️ [WebsiteService] Settings query: ${sw.elapsedMilliseconds}ms');

    final settings = <String, String>{};
    for (final row in response as List) {
      settings[row['key'] as String] = row['value'] as String? ?? '';
    }

    // Apply the same normalization as the editor path without temporarily
    // assigning this response to global state. A stale response therefore has
    // no write window, even while aliases are being computed.
    final normalizedForTenant = _normalizeWebsiteSettingsForSeoConsistency(
      const <String, dynamic>{},
      baseSettings: settings,
    );
    for (final entry in normalizedForTenant.entries) {
      settings[entry.key] = entry.value?.toString() ?? '';
    }

    if (!_ownsTenantScope(lease)) return const {};
    _settings = settings;
    _settingsProjectionTenantId = tenantId;
    _themePresets = _parseThemePresets(_settings['theme_presets']);

    debugPrint(
        '⏱️ [WebsiteService] Settings total: ${sw.elapsedMilliseconds}ms (${settings.length} settings)');
    return settings;
  }

  Future<void> saveSetting(String key, String value) async {
    await _upsertSettings(
      {key: value},
      errorContext: 'Error al guardar configuración',
    );
  }

  /// Save multiple settings at once
  Future<void> saveSettings(Map<String, String> settings) async {
    await _upsertSettings(
      settings,
      errorContext: 'Error al guardar configuraciones',
    );
  }

  /// Tenant-explicit settings write used by the Website Builder save command.
  ///
  /// The editor can be mounted under the public-store host, so its detected
  /// tenant must remain explicit throughout the whole save instead of being
  /// resolved independently for every bucket.
  Future<void> saveSettingsForTenant(
    String tenantId,
    Map<String, String> settings, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    await _upsertSettings(
      settings,
      tenantId: tenantId,
      writeGuard: writeGuard,
      errorContext: 'Error al guardar configuraciones',
    );
  }

  String getSetting(String key, [String defaultValue = '']) {
    return _settings[key] ?? defaultValue;
  }

  WebsiteCatalogPresentationRegistry get catalogPresentationRegistry =>
      WebsiteCatalogPresentationRegistry.decode(
        _settings[websiteCatalogPresentationsSettingKey],
      );

  /// Saves presentation owned by one real category or canonical catalog root.
  ///
  /// Taxonomy and publication remain on `product_categories`; this operation
  /// persists only public collection presentation in website settings so it is
  /// included in the existing website backup and restore workflow.
  Future<void> saveCatalogPresentation(
    WebsiteCatalogPresentation presentation,
  ) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se pudo determinar el tenant activo.');
    }
    final normalized = presentation.normalizedForOwner();
    if (normalized.ownerId.trim().isEmpty || normalized.slug.isEmpty) {
      throw Exception('El propietario y su ruta pública son obligatorios.');
    }

    final root = normalized.catalogRoot;
    if (root != null) {
      if (!presentation.hasSamePersistedValue(normalized)) {
        throw Exception(
          'El catálogo raíz sólo admite densidad, filtros y SEO configurables.',
        );
      }
    }

    // This setting is a registry. Refresh before the read-modify-write so a
    // workspace opened from a direct route cannot overwrite entries that were
    // not yet present in this service instance's cache.
    await loadSettings();
    if (_error != null) {
      throw Exception(
        'No se pudo recargar la configuración antes de guardar.',
      );
    }
    final registry = catalogPresentationRegistry;
    final validation = normalized.isCategoryPresentation
        ? await _catalogPresentationRegistryWithFallbacks(
            tenantId: tenantId,
            registry: registry,
          )
        : null;
    if (normalized.isCategoryPresentation &&
        !validation!.activeCategoryIds.contains(normalized.ownerId)) {
      throw Exception('La categoría ya no existe en el catálogo activo.');
    }
    final prepared =
        (validation?.registry ?? registry).prepareForSave(normalized);

    await saveSetting(
      websiteCatalogPresentationsSettingKey,
      registry.put(prepared).encode(),
    );
  }

  Future<void> removeCatalogPresentation(String ownerId) async {
    final id = ownerId.trim();
    if (id.isEmpty) return;
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se pudo determinar el tenant activo.');
    }
    await loadSettings();
    if (_error != null) {
      throw Exception(
        'No se pudo recargar la configuración antes de restablecer.',
      );
    }
    final registry = catalogPresentationRegistry;
    final next = registry.remove(id);
    final isCategoryOwner = WebsiteCatalogRootX.fromPresentationId(id) == null;
    if (isCategoryOwner) {
      final validation = await _catalogPresentationRegistryWithFallbacks(
        tenantId: tenantId,
        registry: next,
      );
      final fallback = validation.registry.forCategory(id);
      if (fallback != null) {
        validation.registry.prepareForSave(fallback);
      }
    }
    await saveSetting(
      websiteCatalogPresentationsSettingKey,
      next.encode(),
    );
  }

  Future<
      ({
        WebsiteCatalogPresentationRegistry registry,
        Set<String> activeCategoryIds,
      })> _catalogPresentationRegistryWithFallbacks({
    required String tenantId,
    required WebsiteCatalogPresentationRegistry registry,
  }) async {
    final response = await _supabase
        .from('product_categories')
        .select('id,name')
        .eq('tenant_id', tenantId)
        .eq('is_active', true);
    var validationRegistry = registry;
    final activeCategoryIds = <String>{};
    for (final rawRow in response as List) {
      final row = Map<String, dynamic>.from(rawRow as Map);
      final categoryId = row['id']?.toString().trim() ?? '';
      final categoryName = row['name']?.toString().trim() ?? '';
      if (categoryId.isEmpty || categoryName.isEmpty) continue;
      activeCategoryIds.add(categoryId);
      if (validationRegistry.forCategory(categoryId) == null) {
        validationRegistry = validationRegistry.put(
          WebsiteCatalogPresentation.fallback(
            categoryId: categoryId,
            categoryName: categoryName,
          ),
        );
      }
    }
    return (
      registry: validationRegistry,
      activeCategoryIds: Set<String>.unmodifiable(activeCategoryIds),
    );
  }

  List<ThemePreset> _parseThemePresets(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);

      List<ThemePreset> presets = [];

      if (decoded is List) {
        presets = decoded
            .whereType<Map<String, dynamic>>()
            .map(ThemePreset.fromJson)
            .toList();
      } else if (decoded is Map<String, dynamic>) {
        presets = [ThemePreset.fromJson(decoded)];
      }

      presets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return presets;
    } catch (e) {
      debugPrint('Error al parsear theme_presets: $e');
    }

    return [];
  }

  Future<void> saveThemePreset(ThemePreset preset) async {
    final now = DateTime.now().toUtc();
    final updatedPreset = preset.copyWith(updatedAt: now);

    final updatedPresets = [
      ..._themePresets.where((existing) => existing.id != updatedPreset.id),
      updatedPreset,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    await _persistThemePresets(updatedPresets,
        errorContext: 'Error al guardar el preset de tema');
  }

  Future<void> deleteThemePreset(String presetId) async {
    final updatedPresets =
        _themePresets.where((preset) => preset.id != presetId).toList();

    await _persistThemePresets(updatedPresets,
        errorContext: 'Error al eliminar el preset de tema');
  }

  Future<void> _persistThemePresets(
    List<ThemePreset> presets, {
    required String errorContext,
  }) async {
    final encoded =
        jsonEncode(presets.map((preset) => preset.toJson()).toList());

    await _upsertSettings(
      {'theme_presets': encoded},
      errorContext: errorContext,
    );
  }

  Future<void> _upsertSettings(
    Map<String, dynamic> values, {
    String? tenantId,
    required String errorContext,
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    if (values.isEmpty) {
      debugPrint(
          '⚠️ [WebsiteService] _upsertSettings called with empty values - skipping');
      return;
    }

    _WebsiteTenantScopeLease? lease;
    final hasExplicitTenant = tenantId != null;
    try {
      tenantId ??= await _tenantService.getTenantId();
      debugPrint(
          '💾 [WebsiteService] _upsertSettings: tenantId=$tenantId, ${values.length} settings to save');
      if (tenantId == null) {
        throw Exception('No tenant ID available');
      }
      lease = hasExplicitTenant
          ? _leaseForBoundTenant(tenantId)
          : _bindTenantScope(tenantId);

      // --------------------------------------------------------------------
      // SINGLE SOURCE OF TRUTH (Editor → DB → Public Store + index.html)
      //
      // An explicit editor save must never rebind a service that has already
      // switched to another tenant. Use the active projection only when its
      // lease still matches; otherwise obtain a tenant-scoped normalization
      // baseline without publishing it locally.
      // --------------------------------------------------------------------
      Map<String, String> normalizationBaseline;
      if (lease != null &&
          _ownsTenantScope(lease) &&
          _settingsProjectionTenantId == tenantId) {
        normalizationBaseline = Map<String, String>.from(_settings);
      } else {
        final existingRows = await _supabase
            .from('website_settings')
            .select('key,value')
            .eq('tenant_id', tenantId);
        normalizationBaseline = <String, String>{
          for (final rawRow in existingRows as List)
            if (rawRow is Map && rawRow['key'] != null)
              rawRow['key'].toString(): rawRow['value']?.toString() ?? '',
        };
      }
      values = _normalizeWebsiteSettingsForSeoConsistency(
        values,
        baseSettings: normalizationBaseline,
      );

      final timestamp = DateTime.now().toIso8601String();
      final normalizedValues = <String, String>{
        for (final entry in values.entries)
          entry.key: entry.value?.toString() ?? '',
      };
      final rows = normalizedValues.entries
          .map(
            (entry) => <String, dynamic>{
              'tenant_id': tenantId,
              'key': entry.key,
              'value': entry.value,
              'updated_at': timestamp,
            },
          )
          .toList(growable: false);

      // Re-validate the saving authority AFTER the baseline read and
      // immediately BEFORE the mutable statement.
      writeGuard?.call();
      // `website_settings_tenant_key_unique` makes this one PostgreSQL
      // statement. Either every normalized owner value is persisted or none
      // is; a failed request can no longer leave the public site half old and
      // half new.
      await _supabase
          .from('website_settings')
          .upsert(rows, onConflict: 'tenant_id,key');
      // Re-validate AFTER the response, BEFORE any local projection: A's
      // durable write may exist server-side, but B's projection/drafts stay
      // completely untouched when the authority moved mid-flight.
      writeGuard?.call();
      if (lease == null || !_ownsTenantScope(lease)) return;

      // Commit the local projection only after the database statement
      // succeeds. This prevents a failed save from presenting unsaved values
      // as canonical editor state.
      _settings.addAll(normalizedValues);
      _settingsProjectionTenantId = tenantId;

      if (writeGuard == null) {
        await _loadSettingsForTenantWithinScope(lease);
      }
      // Under a save guard the projection uses the CONFIRMED values above:
      // a readback could publish during another unguarded await.
    } catch (e) {
      // A late failure after an identity change reclassifies as SUPERSEDED
      // before any error publication; a SUPERSEDED write never publishes
      // into (nor notifies) the NEW session's projection.
      if (e is! WebsiteEditorWriteSupersededException) {
        writeGuard?.call();
      }
      if (e is! WebsiteEditorWriteSupersededException &&
          lease != null &&
          _ownsTenantScope(lease)) {
        _error = '$errorContext: $e';
        debugPrint(_error);
        _safeNotifyListeners();
      }
      rethrow;
    }
  }

  Map<String, dynamic> _normalizeWebsiteSettingsForSeoConsistency(
    Map<String, dynamic> raw, {
    Map<String, String>? baseSettings,
  }) {
    // Convert pending updates to string values (this table stores strings).
    final pending = WebsiteSeoSettingsAliases.normalize(raw);

    // Overlay pending on the in-memory settings to compute an effective view.
    final effective = <String, String>{
      ...(baseSettings ?? _settings),
      ...pending,
    };

    String firstNonEmpty(List<String> keys) {
      for (final key in keys) {
        final v = (effective[key] ?? '').trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    String explicitOrEffective(List<String> keys) {
      for (final key in keys) {
        if (pending.containsKey(key)) return pending[key]!.trim();
      }
      return firstNonEmpty(keys);
    }

    bool hasExplicitUpdate(List<String> keys) => keys.any(pending.containsKey);

    // 1) Email: keep `seo_email` and `contact_email` in sync.
    const emailKeys = ['seo_email', 'contact_email'];
    final email = explicitOrEffective(emailKeys);
    if (email.isNotEmpty || hasExplicitUpdate(emailKeys)) {
      pending['seo_email'] = email;
      pending['contact_email'] = email;
    }

    // 2) Phone: keep `seo_phone` and `contact_phone` in sync.
    const phoneKeys = ['seo_phone', 'contact_phone'];
    final phone = explicitOrEffective(phoneKeys);
    if (phone.isNotEmpty || hasExplicitUpdate(phoneKeys)) {
      pending['seo_phone'] = phone;
      pending['contact_phone'] = phone;
    }

    // 3) Business name: keep `store_name` and `seo_business_name` in sync.
    const businessNameKeys = [
      'seo_business_name',
      'store_name',
      'meta_site_name',
    ];
    final businessName = explicitOrEffective(businessNameKeys);
    if (businessName.isNotEmpty || hasExplicitUpdate(businessNameKeys)) {
      pending['store_name'] = businessName;
      pending['seo_business_name'] = businessName;
    }

    // 4) Address normalization.
    // Goal: avoid duplicated locality/country in index.html/JSON-LD. We treat
    // `seo_address_*` as the structured source and also mirror a consistent
    // human-readable `contact_address`.
    String normalizeLocality(String rawCity, String country) {
      final cityRaw = rawCity.trim();
      if (cityRaw.isEmpty) return '';

      final normalizedCountry = _normalizeCountry(country);

      // If the city field accidentally contains multiple comma parts (e.g.
      // "Viña del Mar, Chile"), strip any part that equals the country.
      final parts = cityRaw
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      if (parts.length <= 1) {
        // Also handle whitespace duplicate like "Chile Chile".
        if (normalizedCountry.isNotEmpty &&
            _equalsIgnoreCase(cityRaw, normalizedCountry)) {
          return '';
        }
        return cityRaw;
      }

      final cleaned = <String>[];
      for (final p in parts) {
        if (normalizedCountry.isNotEmpty &&
            _equalsIgnoreCase(p, normalizedCountry)) {
          continue;
        }
        if (cleaned.isEmpty || !_equalsIgnoreCase(cleaned.last, p)) {
          cleaned.add(p);
        }
      }

      final joined = cleaned.join(', ').trim();
      if (normalizedCountry.isNotEmpty &&
          _equalsIgnoreCase(joined, normalizedCountry)) {
        return '';
      }
      return joined;
    }

    var street = (effective['seo_address_street'] ?? '').trim();
    var city = (effective['seo_address_city'] ?? '').trim();
    var country = _normalizeCountry(effective['seo_address_country'] ?? '');

    final contactAddress = (effective['contact_address'] ?? '').trim();

    // If the user explicitly edited the footer address (contact_address), treat
    // it as authoritative and re-derive structured fields unless the user is
    // also explicitly editing structured seo_address_* keys in the same save.
    final pendingContactAddress = (pending['contact_address'] ?? '').trim();
    final pendingSeoStreet = (pending['seo_address_street'] ?? '').trim();
    final pendingSeoCity = (pending['seo_address_city'] ?? '').trim();
    final pendingSeoCountry = (pending['seo_address_country'] ?? '').trim();

    final hasExplicitSeoPartsInThisSave = pendingSeoStreet.isNotEmpty ||
        pendingSeoCity.isNotEmpty ||
        pendingSeoCountry.isNotEmpty;

    if (pendingContactAddress.isNotEmpty && !hasExplicitSeoPartsInThisSave) {
      final parsed = _parseChileanAddressLoose(pendingContactAddress);
      street = parsed.street.trim();
      city = parsed.city.trim();
      country = _normalizeCountry(parsed.country);
    } else {
      // Fallback: only fill missing structured parts from the best available address.
      final addressToParse = contactAddress.isNotEmpty
          ? contactAddress
          : (street.isNotEmpty ? street : '');

      if ((street.isEmpty || city.isEmpty || country.isEmpty) &&
          addressToParse.isNotEmpty) {
        final parsed = _parseChileanAddressLoose(addressToParse);
        street = street.isNotEmpty ? street : parsed.street;
        city = city.isNotEmpty ? city : parsed.city;
        country = country.isNotEmpty ? country : parsed.country;
      }

      country = _normalizeCountry(country);
    }

    // Always sanitize locality against country to prevent "..., Chile, Chile".
    city = normalizeLocality(city, country);
    country = _normalizeCountry(country);

    if (street.isNotEmpty) pending['seo_address_street'] = street;
    if (city.isNotEmpty) pending['seo_address_city'] = city;
    if (country.isNotEmpty) pending['seo_address_country'] = country;

    final normalizedContactAddress = _joinAddress(street, city, country);
    if (normalizedContactAddress.isNotEmpty) {
      pending['contact_address'] = normalizedContactAddress;
    }

    return pending;
  }

  _LooseAddressParts _parseChileanAddressLoose(String raw) {
    final rawParts =
        raw.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    // Collapse adjacent duplicates (e.g., "Chile, Chile").
    final parts = <String>[];
    for (final p in rawParts) {
      if (parts.isEmpty || !_equalsIgnoreCase(parts.last, p)) {
        parts.add(p);
      }
    }

    if (parts.length >= 3) {
      final country = _normalizeCountry(parts.last);
      final city = parts[parts.length - 2];
      final street = parts.sublist(0, parts.length - 2).join(', ');

      // If city and country ended up the same (legacy "..., Chile, Chile"),
      // shift city left if possible.
      if (_equalsIgnoreCase(city, country) && parts.length >= 4) {
        final shiftedCity = parts[parts.length - 3];
        final shiftedStreet = parts.sublist(0, parts.length - 3).join(', ');
        return _LooseAddressParts(
          street: shiftedStreet,
          city: shiftedCity,
          country: country,
        );
      }

      return _LooseAddressParts(
        street: street,
        city: city,
        country: country,
      );
    }

    if (parts.length == 2) {
      return _LooseAddressParts(
        street: parts.first,
        city: parts.last,
        country: 'Chile',
      );
    }

    return _LooseAddressParts(
      street: raw.trim(),
      city: '',
      country: '',
    );
  }

  String _joinAddress(String street, String city, String country) {
    final tokens = <String>[];
    final streetT = street.trim();
    final cityT = city.trim();
    final countryT = _normalizeCountry(country);

    if (streetT.isNotEmpty) tokens.add(streetT);
    if (cityT.isNotEmpty) tokens.add(cityT);
    if (countryT.isNotEmpty) tokens.add(countryT);

    // Collapse adjacent duplicates (case-insensitive).
    final deduped = <String>[];
    for (final t in tokens) {
      if (deduped.isEmpty || !_equalsIgnoreCase(deduped.last, t)) {
        deduped.add(t);
      }
    }

    // If city == country, drop the city.
    if (deduped.length >= 2 &&
        _equalsIgnoreCase(deduped[deduped.length - 2], deduped.last)) {
      deduped.removeAt(deduped.length - 2);
    }

    return deduped.join(', ');
  }

  bool _equalsIgnoreCase(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  String _normalizeCountry(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    // Handle comma-separated duplicates like "Chile, Chile".
    final commaParts =
        s.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (commaParts.isNotEmpty) {
      final cleaned = <String>[];
      for (final p in commaParts) {
        if (cleaned.isEmpty || !_equalsIgnoreCase(cleaned.last, p)) {
          cleaned.add(p);
        }
      }
      s = cleaned.isNotEmpty ? cleaned.last : s;
    }

    // Handle whitespace duplicates like "Chile Chile".
    final words = s
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length >= 2 &&
        words.every((w) => _equalsIgnoreCase(w, words.first))) {
      s = words.first;
    }

    // Standardize common case.
    if (s.toLowerCase() == 'chile') return 'Chile';
    return s;
  }

  // ============================================================================
  // ORDERS
  // ============================================================================

  Future<void> loadOrders() async {
    _WebsiteTenantScopeLease? lease;

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found for current user');
      }
      lease = _bindTenantScope(tenantId);
      _isLoading = true;
      _error = null;
      _ordersLoadError = null;
      _ordersEnrichmentWarning = null;
      if (!_isInitializing) _safeNotifyListeners();

      // Load orders with items in a SINGLE query (no N+1 problem)
      // Limit to recent 100 orders for performance - use pagination for full list
      final response = await _supabase
          .from('online_orders')
          .select('''
            *,
            online_order_items (*)
          ''')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(100);
      if (!_ownsTenantScope(lease)) return;

      final loadedOrders =
          (response as List).map((json) => OnlineOrder.fromJson(json)).toList();
      final ordersWithProducts =
          await _attachProductContextToOrders(loadedOrders, tenantId);
      if (!_ownsTenantScope(lease)) return;
      // Payment-processing metadata is an operational enrichment, not the
      // authoritative order list. Keep the base orders visible if that
      // projection is temporarily unavailable (for example during a staged
      // backend rollout) and tell the operator exactly what is incomplete.
      _orders = ordersWithProducts;
      try {
        final enrichedOrders = await _attachPaymentProcessingToOrders(
          ordersWithProducts,
          tenantId,
        );
        if (!_ownsTenantScope(lease)) return;
        _orders = enrichedOrders;
      } catch (enrichmentError) {
        if (!_ownsTenantScope(lease)) return;
        _ordersEnrichmentWarning =
            'Los pedidos están cargados, pero el estado operativo de algunos '
            'pagos no está disponible. Actualiza nuevamente en unos minutos.';
        debugPrint(
          '⚠️ [WebsiteService] Payment processing enrichment unavailable: '
          '$enrichmentError',
        );
      }

      _error = null;
    } catch (e) {
      if (lease == null || _ownsTenantScope(lease)) {
        _error = 'Error al cargar pedidos online: $e';
        _ordersLoadError =
            'No se pudieron cargar los pedidos. Revisa la conexión o los permisos '
            'y vuelve a intentarlo.';
        debugPrint(_error);
      }
    } finally {
      if (lease == null || _ownsTenantScope(lease)) {
        _isLoading = false;
        _safeNotifyListeners();
      }
    }
  }

  Future<List<OnlineOrderItem>> _loadOrderItems(String orderId) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return [];

      final response = await _supabase
          .from('online_order_items')
          .select()
          .eq('tenant_id', tenantId)
          .eq('order_id', orderId);

      final items = (response as List)
          .map((json) => OnlineOrderItem.fromJson(json))
          .toList();
      return _attachProductContextToItems(items, tenantId);
    } catch (e) {
      debugPrint('Error loading order items: $e');
      return [];
    }
  }

  Future<List<OnlineOrder>> _attachPaymentProcessingToOrders(
    List<OnlineOrder> orders,
    String tenantId,
  ) async {
    if (orders.isEmpty) return orders;

    final response = await _supabase
        .from('online_order_payment_processing_status_view')
        .select('''
          order_id,
          payment_event_id,
          provider_status,
          validation_outcome,
          processing_state,
          attempt_count,
          last_attempted_at,
          action_required_at,
          last_error_code,
          last_error_message,
          requires_refund_review,
          updated_at
        ''')
        .eq('tenant_id', tenantId)
        .inFilter('order_id', orders.map((order) => order.id).toList())
        .order('updated_at', ascending: false);

    int operationalPriority(Map<String, dynamic> row) {
      if (row['processing_state'] == 'action_required') return 3;
      if (row['processing_state'] == 'pending' &&
          row['provider_status'] == 'approved' &&
          row['validation_outcome'] == 'payment_validated') {
        return 2;
      }
      if (row['provider_status'] == 'approved') return 1;
      return 0;
    }

    // An unresolved approved-payment incident must not disappear merely
    // because a later stale/pending provider notification was received.
    final operationalByOrder = <String, Map<String, dynamic>>{};
    for (final rawRow in response as List) {
      final row = Map<String, dynamic>.from(rawRow as Map);
      final orderId = row['order_id']?.toString();
      if (orderId != null && orderId.isNotEmpty) {
        final current = operationalByOrder[orderId];
        if (current == null ||
            operationalPriority(row) > operationalPriority(current)) {
          operationalByOrder[orderId] = row;
        }
      }
    }

    return orders.map((order) {
      final processing = operationalByOrder[order.id];
      if (processing == null) return order;
      return order.copyWith(
        paymentProcessingEventId:
            (processing['payment_event_id'] as num?)?.toInt(),
        paymentProviderStatus: processing['provider_status']?.toString(),
        paymentValidationOutcome: processing['validation_outcome']?.toString(),
        paymentProcessingState: processing['processing_state']?.toString(),
        paymentProcessingAttemptCount:
            (processing['attempt_count'] as num?)?.toInt() ?? 0,
        paymentProcessingLastAttemptedAt:
            processing['last_attempted_at'] == null
                ? null
                : DateTime.parse(processing['last_attempted_at'] as String),
        paymentProcessingActionRequiredAt:
            processing['action_required_at'] == null
                ? null
                : DateTime.parse(processing['action_required_at'] as String),
        paymentProcessingErrorCode: processing['last_error_code']?.toString(),
        paymentProcessingErrorMessage:
            processing['last_error_message']?.toString(),
        paymentProcessingRequiresRefundReview:
            processing['requires_refund_review'] as bool? ?? false,
      );
    }).toList();
  }

  Future<List<OnlineOrder>> _attachProductContextToOrders(
    List<OnlineOrder> orders,
    String tenantId,
  ) async {
    final allItems = orders.expand((order) => order.items).toList();
    if (allItems.isEmpty) return orders;

    final enrichedItems =
        await _attachProductContextToItems(allItems, tenantId);
    final itemsByOrder = <String, List<OnlineOrderItem>>{};
    for (final item in enrichedItems) {
      itemsByOrder.putIfAbsent(item.orderId, () => []).add(item);
    }

    return orders
        .map((order) => order.copyWith(
              items: itemsByOrder[order.id] ?? const [],
            ))
        .toList();
  }

  Future<List<OnlineOrderItem>> _attachProductContextToItems(
    List<OnlineOrderItem> items,
    String tenantId,
  ) async {
    final productIds = items
        .map((item) => item.productId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final productsById = <String, Map<String, dynamic>>{};
    if (productIds.isNotEmpty) {
      try {
        final response = await _supabase
            .from('products')
            .select(_orderItemProductContextSelect)
            .eq('tenant_id', tenantId)
            .inFilter('id', productIds.toList());

        for (final row in response as List) {
          final product = Map<String, dynamic>.from(row as Map);
          final id = product['id']?.toString();
          if (id != null && id.isNotEmpty) {
            productsById[id] = product;
          }
        }
        for (final product in productsById.values
            .where((product) => product['is_set'] == true)) {
          final available = await _loadSetAvailability(
            product['id']?.toString() ?? '',
          );
          if (available != null) {
            product['inventory_qty'] = available;
            product['stock_quantity'] = available;
          }
        }
      } catch (e) {
        debugPrint('Error loading order product context: $e');
        return items;
      }
    }

    return items.map((item) {
      final productId = item.productId?.trim();
      if (productId == null || productId.isEmpty) {
        return item.copyWith(
          productContextLoaded: true,
          productExists: false,
        );
      }

      final product = productsById[productId];
      if (product == null) {
        return item.copyWith(
          productContextLoaded: true,
          productExists: false,
        );
      }

      return item.copyWith(
        productContextLoaded: true,
        productExists: true,
        liveProductName: product['name']?.toString(),
        liveProductSku: product['sku']?.toString(),
        productCategoryName: product['category_name']?.toString(),
        productStockQuantity: _intFromProductValue(
          product['stock_quantity'] ?? product['inventory_qty'],
        ),
        productIsActive: product['is_active'] as bool?,
        productIsPublished: product['is_published'] as bool?,
        productTracksStock: product['track_stock'] as bool?,
        productType: product['product_type']?.toString(),
        productPurchaseTreatment: product['purchase_treatment']?.toString(),
      );
    }).toList();
  }

  int? _intFromProductValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<OnlineOrder?> getOrderById(String id) async {
    try {
      debugPrint('🎉 [WebsiteService] getOrderById($id) called');
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return null;

      final response = await _supabase
          .from('online_orders')
          .select()
          .eq('tenant_id', tenantId)
          .eq('id', id)
          .single();
      debugPrint('🎉 [WebsiteService] Order response received');

      final order = OnlineOrder.fromJson(response);
      debugPrint('🎉 [WebsiteService] Order parsed: ${order.orderNumber}');

      final items = await _loadOrderItems(order.id);
      debugPrint('🎉 [WebsiteService] Order items loaded: ${items.length}');

      final enriched = order.copyWith(items: items);
      return (await _attachPaymentProcessingToOrders(
        [enriched],
        tenantId,
      ))
          .single;
    } catch (e, stackTrace) {
      debugPrint('❌ [WebsiteService] Error loading order: $e');
      debugPrint('❌ [WebsiteService] Stack trace: $stackTrace');
      return null;
    }
  }

  Future<OnlineOrder?> getPublicOrderById({
    required String orderId,
    required String accessToken,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_public_online_order_by_access_token',
        params: {'p_token': accessToken},
      );

      if (response == null) return null;

      return onlineOrderFromPublicAccessResponse(
        response,
        expectedOrderId: orderId,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [WebsiteService] Error loading public order: $e');
      debugPrint('❌ [WebsiteService] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Create a new online order from the public store
  Future<PublicOrderCheckoutAccess> createOrder(
    Map<String, dynamic> orderData,
    List<Map<String, dynamic>> orderItems,
  ) async {
    try {
      debugPrint('🛒 [WebsiteService] createOrder() called');

      final orderId = await _supabase.rpc(
        'create_public_online_order_with_access',
        params: {
          'p_order_data': orderData,
          'p_order_items': orderItems,
        },
      );

      final result = PublicOrderCheckoutAccess.fromRpc(orderId);
      debugPrint('🛒 [WebsiteService] Secure checkout completed');
      return result;
    } catch (e) {
      _error = 'Error al crear pedido: $e';
      debugPrint('🛒 [WebsiteService] ❌ createOrder() error: $_error');
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<PublicShippingQuote> quotePublicShipping({
    required String tenantId,
    required String deliveryType,
    required int itemGross,
  }) async {
    final response = await _supabase.rpc(
      'quote_public_online_shipping',
      params: {
        'p_tenant_id': tenantId,
        'p_delivery_type': deliveryType,
        'p_item_gross': itemGross,
        'p_country_code': 'CL',
      },
    );
    return PublicShippingQuote.fromRpc(response);
  }

  Future<String?> updateOrderStatus(
    String orderId,
    String status, {
    required int expectedVersion,
    String? operationKey,
    String? trackingNumber,
    String? trackingUrl,
    String? carrier,
    String? notes,
  }) async {
    try {
      final response = await _supabase.rpc(
        'transition_online_order_status',
        params: {
          'p_order_id': orderId,
          'p_new_status': status,
          'p_expected_version': expectedVersion,
          'p_operation_key': operationKey ?? const Uuid().v4(),
          'p_tracking_number': trackingNumber,
          'p_tracking_url': trackingUrl,
          'p_carrier': carrier,
          'p_notes': notes,
        },
      );

      await loadOrders();
      if (response is Map && response['invoice_id'] != null) {
        return response['invoice_id'].toString();
      }
      return null;
    } catch (e) {
      _error = 'Error al actualizar estado del pedido: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<void> updateOrderNotes(
    String orderId, {
    required int expectedVersion,
    String? operationKey,
    String? internalNotes,
  }) async {
    try {
      await _supabase.rpc(
        'update_online_order_internal_notes',
        params: {
          'p_order_id': orderId,
          'p_internal_notes': internalNotes,
          'p_expected_version': expectedVersion,
          'p_operation_key': operationKey ?? const Uuid().v4(),
        },
      );

      await loadOrders();
    } catch (e) {
      _error = 'Error al actualizar notas del pedido: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<String?> confirmOrderPayment(
    String orderId, {
    String? paymentReference,
    required DateTime paymentDate,
  }) async {
    try {
      final response = await _supabase.rpc(
        'confirm_online_order_payment',
        params: {
          'p_order_id': orderId,
          'p_payment_reference': paymentReference,
          'p_payment_date': paymentDate.toIso8601String(),
        },
      );

      await loadOrders();
      return response?.toString();
    } catch (e) {
      _error = 'Error al confirmar pago del pedido: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<String?> processOrder(String orderId) async {
    try {
      final response = await _supabase
          .rpc('process_online_order', params: {'p_order_id': orderId});

      await loadOrders();
      return response as String?;
    } catch (e) {
      _error = 'Error al procesar pedido: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> retryMercadoPagoPaymentProcessing(
    int paymentEventId,
  ) async {
    try {
      if (!canRetryOnlineOrderPaymentProcessing) {
        throw StateError(
          'Tu perfil no está autorizado para generar la venta y sus movimientos.',
        );
      }
      final response = await _supabase.rpc(
        'process_mercadopago_payment_observation',
        params: {'p_payment_event_id': paymentEventId},
      );
      if (response is! Map) {
        throw StateError('El procesamiento no devolvió un resultado válido.');
      }

      final result = Map<String, dynamic>.from(response);
      await loadOrders();
      return result;
    } catch (e) {
      _error = 'Error al reintentar el procesamiento de Mercado Pago: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<OnlineOrderCorrectionPreview> loadOnlineOrderCorrectionPreview(
    String orderId,
  ) async {
    final response = await _supabase.rpc(
      'get_online_order_correction_preview',
      params: {'p_order_id': orderId},
    );
    if (response is! Map) {
      throw StateError('La vista previa de corrección no es válida.');
    }
    return OnlineOrderCorrectionPreview.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  Future<OnlineOrderCorrectionRecord?> loadLatestOnlineOrderCorrection(
    String orderId,
  ) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) {
      throw StateError('No existe una tienda activa para esta sesión.');
    }
    final response = await _supabase
        .from('online_order_correction_status_view')
        .select()
        .eq('tenant_id', tenantId)
        .eq('order_id', orderId)
        .maybeSingle();
    if (response == null) return null;
    return OnlineOrderCorrectionRecord.fromJson(response);
  }

  Future<OnlineOrderCorrectionRecord> requestOnlineOrderCorrection({
    required String orderId,
    required int expectedVersion,
    required List<OnlineOrderCorrectionLineRequest> lines,
    required String reason,
    required String operationKey,
    String correctionIntent = 'return',
  }) async {
    final response = await _supabase.rpc(
      'request_online_order_correction',
      params: {
        'p_order_id': orderId,
        'p_expected_order_version': expectedVersion,
        'p_lines': lines.map((line) => line.toJson()).toList(growable: false),
        'p_reason': reason,
        'p_operation_key': operationKey,
        'p_correction_intent': correctionIntent,
      },
    );
    if (response is! Map) {
      throw StateError('La solicitud no devolvió un recibo durable.');
    }
    return OnlineOrderCorrectionRecord.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  Future<OnlineOrderCorrectionRecord> executeOnlineOrderCorrection(
    OnlineOrderCorrectionRecord correction, {
    String? manualReference,
    DateTime? manualRefundedAt,
  }) async {
    if (correction.provider == 'mercadopago') {
      final response = await _supabase.functions.invoke(
        'mercadopago-refund-payment',
        body: {'correction_id': correction.id},
      );
      if (response.status < 200 || response.status >= 300) {
        final detail = response.data is Map
            ? (response.data as Map)['error']?.toString()
            : null;
        throw StateError(
          detail ?? 'Mercado Pago no pudo completar la corrección.',
        );
      }
      final payload = response.data;
      if (payload is Map && payload['correction'] is Map) {
        await loadOrders();
        return OnlineOrderCorrectionRecord.fromJson(
          Map<String, dynamic>.from(payload['correction'] as Map),
        );
      }
      final refreshed =
          await loadLatestOnlineOrderCorrection(correction.orderId);
      if (refreshed == null) {
        throw StateError('No se pudo recuperar la corrección aplicada.');
      }
      await loadOrders();
      return refreshed;
    }

    await _supabase.rpc(
      'authorize_online_order_refund_execution',
      params: {'p_correction_id': correction.id},
    );
    if (correction.needsManualEvidence) {
      final reference = manualReference?.trim() ?? '';
      if (reference.isEmpty) {
        throw StateError('La referencia del reembolso es obligatoria.');
      }
      await _supabase.rpc(
        'record_manual_online_order_refund_evidence',
        params: {
          'p_correction_id': correction.id,
          'p_reference': reference,
          'p_refunded_at':
              (manualRefundedAt ?? DateTime.now()).toUtc().toIso8601String(),
          'p_request_id': 'manual:${const Uuid().v4()}',
        },
      );
    }
    dynamic response;
    try {
      response = await _supabase.rpc(
        'apply_online_order_correction',
        params: {
          'p_correction_id': correction.id,
          'p_request_id': 'apply:${const Uuid().v4()}',
        },
      );
    } catch (error) {
      try {
        await _supabase.rpc(
          'record_online_order_correction_apply_failure',
          params: {
            'p_correction_id': correction.id,
            'p_request_id': 'apply-failure:${const Uuid().v4()}',
            'p_error_code': 'internal_effects_failed',
            'p_error_message':
                'El dinero fue devuelto, pero los efectos internos requieren revisión.',
          },
        );
      } catch (_) {
        // Preserve the original apply failure for the operator. The correction
        // remains replay-safe even if recording this secondary receipt fails.
      }
      rethrow;
    }
    if (response is! Map) {
      throw StateError('La corrección no devolvió un recibo durable.');
    }
    await loadOrders();
    return OnlineOrderCorrectionRecord.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  // ============================================================================
  // PRODUCT WEBSITE VISIBILITY
  // ============================================================================

  Future<void> _assertTaxClassificationForWebPublication({
    required List<String> productIds,
    String? tenantId,
  }) async {
    if (productIds.isEmpty) return;

    dynamic query = _supabase.from('products').select('id,tax_rate');
    if (tenantId != null && tenantId.trim().isNotEmpty) {
      query = query.eq('tenant_id', tenantId.trim());
    }
    final response = await query.inFilter('id', productIds);
    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final returnedIds = rows.map((row) => row['id']?.toString()).toSet();
    if (productIds.any((id) => !returnedIds.contains(id))) {
      throw StateError(
        'No se pudo validar la clasificación tributaria de todos los productos.',
      );
    }

    final unclassified = rows
        .where((row) => !hasSupportedProductTaxRate(row['tax_rate']))
        .length;
    if (unclassified > 0) {
      throw StateError(
        '$unclassified producto${unclassified == 1 ? '' : 's'} sin IVA 19% o Exento no puede${unclassified == 1 ? '' : 'n'} publicarse.',
      );
    }
  }

  Future<void> updateProductWebsiteVisibility({
    required String productId,
    required bool showOnWebsite,
    String? websiteDescription,
    bool? websiteFeatured,
  }) async {
    try {
      if (showOnWebsite) {
        await _assertTaxClassificationForWebPublication(
          productIds: [productId],
        );
      }
      final updates = <String, dynamic>{
        'show_on_website': showOnWebsite,
        'is_published': showOnWebsite,
      };

      if (websiteDescription != null) {
        updates['website_description'] = websiteDescription;
      }

      if (websiteFeatured != null) {
        updates['website_featured'] = websiteFeatured;
      }

      await _supabase.from('products').update(updates).eq('id', productId);

      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al actualizar visibilidad del producto: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  /// Canonical bulk command used by every Website Builder catalog surface.
  /// Product publication owns both flags; inventory forms may display them but
  /// must not implement a competing website-publisher workflow.
  Future<void> updateProductWebsiteVisibilityBatch({
    required String tenantId,
    required Iterable<String> productIds,
    required bool showOnWebsite,
  }) async {
    final ids = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;

    try {
      const chunkSize = 200;
      final now = DateTime.now().toUtc().toIso8601String();
      for (var start = 0; start < ids.length; start += chunkSize) {
        final chunk = ids.skip(start).take(chunkSize).toList(growable: false);
        if (showOnWebsite) {
          await _assertTaxClassificationForWebPublication(
            productIds: chunk,
            tenantId: tenantId,
          );
        }
        await _supabase
            .from('products')
            .update({
              'show_on_website': showOnWebsite,
              'is_published': showOnWebsite,
              'updated_at': now,
            })
            .eq('tenant_id', tenantId)
            .inFilter('id', chunk);
      }
      _safeNotifyListeners();
    } catch (error) {
      _error = 'Error al actualizar publicación web de productos: $error';
      _safeNotifyListeners();
      rethrow;
    }
  }

  /// Canonical replacement command for public category inclusion.
  Future<void> replaceWebsiteCategoryVisibility({
    required String tenantId,
    required Iterable<String> visibleCategoryIds,
  }) async {
    final selected = visibleCategoryIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    try {
      await _supabase.rpc(
        'replace_website_category_visibility',
        params: {
          'p_tenant_id': tenantId,
          'p_visible_category_ids': selected,
        },
      );
      _safeNotifyListeners();
    } catch (error) {
      _error = 'Error al actualizar categorías públicas: $error';
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<List<Product>> getWebsiteProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select(Product.storefrontPreviewSelect)
          .eq('show_on_website', true)
          .eq('is_published', true)
          .eq('is_active', true)
          .order('name');

      final products = (response as List)
          .map((json) => Product.fromJson(json))
          .toList(growable: false);
      final hydrated = <Product>[];
      for (final product in products) {
        final available =
            product.isSet ? await _loadSetAvailability(product.id) : null;
        final setAware = available == null
            ? product
            : product.copyWith(fullSetsAvailable: available);
        if (!setAware.tracksInventory || setAware.availableStockQuantity > 0) {
          hydrated.add(setAware);
        }
      }
      return hydrated;
    } catch (e) {
      debugPrint('Error loading website products: $e');
      return [];
    }
  }

  Future<int?> _loadSetAvailability(String productId) async {
    if (productId.isEmpty) return null;
    try {
      final response = await _supabase.rpc(
        'preview_product_stock_impact',
        params: {'p_product_id': productId, 'p_quantity': 1},
      );
      final payload = response is Map
          ? Map<String, dynamic>.from(response)
          : response is List && response.length == 1 && response.first is Map
              ? Map<String, dynamic>.from(response.first as Map)
              : null;
      return (payload?['available_quantity'] as num?)?.toInt();
    } catch (error) {
      debugPrint('Error loading set availability for $productId: $error');
      return null;
    }
  }

  // ============================================================================
  // VISUAL EDITOR METHODS
  // ============================================================================

  /// Update hero section content
  Future<void> updateHeroSection({
    required String title,
    required String subtitle,
    String? imageUrl,
  }) async {
    final values = <String, dynamic>{
      'hero_title': title,
      'hero_subtitle': subtitle,
    };

    if (imageUrl != null) {
      values['hero_image_url'] = imageUrl;
    }

    await _upsertSettings(
      values,
      errorContext: 'Error al actualizar sección hero',
    );
  }

  /// Update contact information
  Future<void> updateContactInfo({
    required String phone,
    required String email,
    required String address,
  }) async {
    await _upsertSettings(
      {
        'contact_phone': phone,
        'contact_email': email,
        'contact_address': address,
      },
      errorContext: 'Error al actualizar información de contacto',
    );
  }

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  // ============================================================================
  // WEBSITE PAGES (Multi-page Support - Dec 2025)
  // ============================================================================

  List<WebsitePage> _pages = [];
  List<WebsiteNavigation> _navigation = [];
  String? _authoritativePagesTenantId;
  bool _hasAuthoritativePagePublication = false;

  List<WebsitePage> get pages => _pages;
  List<WebsiteNavigation> get navigation => _navigation;

  bool hasAuthoritativePagePublicationForTenant(String tenantId) =>
      _hasAuthoritativePagePublication &&
      _authoritativePagesTenantId == tenantId;

  /// Load all pages for the current tenant (requires authentication)
  Future<void> loadPages() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }

      await loadPagesForTenant(tenantId);
    } catch (e) {
      _error = 'Error al cargar páginas: $e';
      debugPrint(_error);
    }
  }

  /// Load all pages for a specific tenant (public - no auth required)
  /// Used by public store for anonymous visitors
  Future<void> loadPagesForTenant(
    String tenantId, {
    bool rethrowErrors = false,
  }) async {
    final lease = _bindTenantScope(tenantId);

    try {
      await _loadPagesForTenantWithinScope(lease);
    } catch (e) {
      if (!_ownsTenantScope(lease)) return;
      _error = 'Error al cargar páginas: $e';
      if (_authoritativePagesTenantId == lease.tenantId ||
          _authoritativePagesTenantId == null) {
        _hasAuthoritativePagePublication = false;
      }
      debugPrint(_error);
      _safeNotifyListeners();
      if (rethrowErrors) rethrow;
    }
  }

  Future<void> _loadPagesForTenantWithinScope(
    _WebsiteTenantScopeLease lease,
  ) async {
    if (!_ownsTenantScope(lease)) return;

    final existing = _pageLoadsByTenant[lease.tenantId];
    if (existing != null && _sameTenantScope(existing.lease, lease)) {
      await existing.future;
      return;
    }

    final load = _loadPagesForTenantFromOrigin(lease);
    final scopedLoad = _WebsiteScopedLoad<void>(lease: lease, future: load);
    _pageLoadsByTenant[lease.tenantId] = scopedLoad;
    try {
      await load;
    } finally {
      if (identical(_pageLoadsByTenant[lease.tenantId], scopedLoad)) {
        _pageLoadsByTenant.remove(lease.tenantId);
      }
    }
  }

  Future<void> _loadPagesForTenantFromOrigin(
    _WebsiteTenantScopeLease lease,
  ) async {
    final tenantId = lease.tenantId;
    final response = await _supabase
        .from('website_pages')
        .select()
        .eq('tenant_id', tenantId)
        .order('is_home', ascending: false)
        .order('title', ascending: true);
    if (!_ownsTenantScope(lease)) return;

    final pages =
        (response as List).map((json) => WebsitePage.fromJson(json)).toList();
    if (!_ownsTenantScope(lease)) return;
    _pages = pages;
    _authoritativePagesTenantId = tenantId;
    _hasAuthoritativePagePublication = true;

    debugPrint(
        '[WebsiteService] Loaded ${_pages.length} pages for tenant $tenantId');

    _safeNotifyListeners();
  }

  /// Get a page by ID
  Future<WebsitePage?> getPageById(String pageId) async {
    try {
      final response = await _supabase
          .from('website_pages')
          .select()
          .eq('id', pageId)
          .maybeSingle();

      if (response != null) {
        return WebsitePage.fromJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting page by ID: $e');
      return null;
    }
  }

  Future<WebsitePage?> getPageByIdForTenant(
    String pageId,
    String tenantId, {
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _supabase
          .from('website_pages')
          .select()
          .eq('tenant_id', tenantId)
          .eq('id', pageId)
          .maybeSingle();
      return response == null ? null : WebsitePage.fromJson(response);
    } catch (e) {
      debugPrint('Error getting tenant page by ID: $e');
      if (rethrowErrors) rethrow;
      return null;
    }
  }

  /// Get a page by slug
  /// If [tenantId] is provided, uses that instead of the current user's tenant
  /// (useful for public store where visitors may not be logged in)
  Future<WebsitePage?> getPageBySlug(
    String slug, {
    String? tenantId,
    bool rethrowErrors = false,
  }) async {
    try {
      final effectiveTenantId = tenantId ?? await _tenantService.getTenantId();
      if (effectiveTenantId == null) return null;

      final response = await _supabase
          .from('website_pages')
          .select()
          .eq('tenant_id', effectiveTenantId)
          .eq('slug', slug)
          .maybeSingle();

      if (response != null) {
        return WebsitePage.fromJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting page by slug: $e');
      if (rethrowErrors) rethrow;
      return null;
    }
  }

  /// Get the home page for the current tenant
  Future<WebsitePage?> getHomePage() async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) return null;
    return getHomePageForTenant(tenantId);
  }

  Future<WebsitePage?> getHomePageForTenant(
    String tenantId, {
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _supabase
          .from('website_pages')
          .select()
          .eq('tenant_id', tenantId)
          .eq('is_home', true)
          .maybeSingle();

      if (response != null) {
        return WebsitePage.fromJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting home page: $e');
      if (rethrowErrors) rethrow;
      return null;
    }
  }

  /// Create a new page
  Future<WebsitePage> createPage(
    WebsitePage page, {
    String? tenantId,
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    _WebsiteTenantScopeLease? lease;
    final hasExplicitTenant = tenantId != null;
    try {
      final effectiveTenantId = tenantId ?? await _tenantService.getTenantId();
      if (effectiveTenantId == null) {
        throw Exception('No tenant_id found');
      }
      if (page.tenantId.trim().isNotEmpty &&
          page.tenantId != effectiveTenantId) {
        throw StateError('La página no pertenece al tenant del guardado.');
      }
      lease = hasExplicitTenant
          ? _leaseForBoundTenant(effectiveTenantId)
          : _bindTenantScope(effectiveTenantId);

      final data = page.toInsertJson();
      data['tenant_id'] = effectiveTenantId;

      // A page creation is an externally visible mutation. Revalidate after
      // every preceding await and immediately before the insert so an editor
      // that moved from A to B cannot resolve B's tenant implicitly or create
      // under an already-superseded navigation decision.
      writeGuard?.call();
      final response =
          await _supabase.from('website_pages').insert(data).select().single();
      // The server may already have durably accepted A's request; the
      // post-response guard still prevents its result, cache invalidation and
      // local page adoption from crossing into B.
      writeGuard?.call();

      final newPage = WebsitePage.fromJson(response);
      WebsiteService.clearPageCache();
      if (lease != null && _ownsTenantScope(lease)) {
        _pages.add(newPage);
        _safeNotifyListeners();
      }

      return newPage;
    } catch (e) {
      if (e is! WebsiteEditorWriteSupersededException) {
        writeGuard?.call();
      }
      if (e is! WebsiteEditorWriteSupersededException &&
          lease != null &&
          _ownsTenantScope(lease)) {
        _error = 'Error al crear página: $e';
        debugPrint(_error);
      }
      rethrow;
    }
  }

  /// Update an existing page
  Future<WebsitePage> updatePage(
    WebsitePage page, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    final lease = _leaseForBoundTenant(page.tenantId);
    try {
      writeGuard?.call();
      final response = await _supabase
          .from('website_pages')
          .update(page.toUpdateJson())
          .eq('id', page.id)
          .eq('tenant_id', page.tenantId)
          .select()
          .single();
      // Post-response guard: never project A's result into B locally.
      writeGuard?.call();

      final updatedPage = WebsitePage.fromJson(response);

      // Update local cache
      if (lease != null && _ownsTenantScope(lease)) {
        final index = _pages.indexWhere((p) => p.id == page.id);
        if (index >= 0) {
          _pages[index] = updatedPage;
        }
        _safeNotifyListeners();
      }
      WebsiteService.clearPageCache();

      return updatedPage;
    } catch (e) {
      // A late failure after an identity change reclassifies as SUPERSEDED
      // before any error publication.
      if (e is! WebsiteEditorWriteSupersededException) {
        writeGuard?.call();
      }
      if (e is! WebsiteEditorWriteSupersededException &&
          lease != null &&
          _ownsTenantScope(lease)) {
        _error = 'Error al actualizar página: $e';
        debugPrint(_error);
      }
      rethrow;
    }
  }

  /// Delete a page (fails for system pages)
  Future<void> deletePage(String pageId) async {
    try {
      await _supabase.from('website_pages').delete().eq('id', pageId);

      _pages.removeWhere((p) => p.id == pageId);
      WebsiteService.clearPageCache();
      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al eliminar página: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Publish or unpublish a page
  Future<void> togglePagePublished(String pageId, bool published) async {
    try {
      await _supabase.from('website_pages').update({
        'is_published': published,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', pageId);

      WebsiteService.clearPageCache();
      await loadPages();
    } catch (e) {
      _error = 'Error al publicar página: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Set a page as home page
  Future<void> setHomePage(String pageId) async {
    try {
      await _supabase.from('website_pages').update({
        'is_home': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', pageId);

      WebsiteService.clearPageCache();
      await loadPages();
    } catch (e) {
      _error = 'Error al establecer página de inicio: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Load blocks for a specific page
  Future<List<Map<String, dynamic>>> loadBlocksForPage(
    String pageId, {
    String? tenantId,
  }) async {
    try {
      // Allow explicit tenant for public store (anonymous visitors)
      final effectiveTenantId = tenantId ?? await _tenantService.getTenantId();
      if (effectiveTenantId == null) {
        throw Exception('No tenant_id found');
      }

      final response = await _supabase
          .from('website_blocks')
          .select()
          .eq('tenant_id', effectiveTenantId)
          .eq('page_id', pageId)
          .order('order_index', ascending: true);

      final data = List<Map<String, dynamic>>.from(response as List);
      return _normalizeBlocksList(data);
    } catch (e) {
      _error = 'Error al cargar bloques de página: $e';
      debugPrint(_error);
      return [];
    }
  }

  /// Save blocks for a specific page
  Future<void> saveBlocksForPage(
    String pageId,
    List<Map<String, dynamic>> blocks, {
    String? tenantId,
  }) async {
    final effectiveTenantId = tenantId ?? await _tenantService.getTenantId();
    if (effectiveTenantId == null) {
      throw Exception('No tenant ID found');
    }

    await replacePageBlocks(
      tenantId: effectiveTenantId,
      pageId: pageId,
      blocks: blocks,
    );
    _safeNotifyListeners();
  }

  // ==========================================================================
  // PUBLIC-STORE NAVIGATION CACHE (tenantId-scoped)
  // ==========================================================================

  bool _hasLoadedNavigationForTenant = false;
  String? _loadedNavigationTenantId;

  final Set<String> _attemptedDefaultFooterSeedForTenant = {};

  Future<void> _seedDefaultFooterNavigationIfNeeded(
    _WebsiteTenantScopeLease lease,
    List<WebsiteNavigation> navigation,
  ) async {
    // Only seed when authenticated (public/anon store must never attempt inserts).
    if (_supabase.auth.currentUser == null) return;
    if (!_ownsTenantScope(lease)) return;
    final tenantId = lease.tenantId;
    if (_attemptedDefaultFooterSeedForTenant.contains(tenantId)) return;

    final hasFooter =
        navigation.any((n) => n.menuLocation == MenuLocation.footer);
    if (hasFooter) return;

    // A storefront customer session is authenticated too, but it does not own
    // Website Builder defaults. Only the active ERP tenant may seed them.
    final activeTenantId = await _tenantService.getTenantId();
    if (!_ownsTenantScope(lease) || activeTenantId != tenantId) return;

    _attemptedDefaultFooterSeedForTenant.add(tenantId);

    try {
      if (!_ownsTenantScope(lease)) return;
      final result = await _supabase.rpc(
        'ensure_default_footer_navigation',
        params: {'p_tenant_id': tenantId},
      );
      if (!_ownsTenantScope(lease)) return;

      final resultMap = result is Map
          ? Map<String, dynamic>.from(result)
          : const <String, dynamic>{};
      if (resultMap['tenant_id']?.toString() != tenantId) {
        throw StateError(
          'El footer devuelto no pertenece al tenant solicitado.',
        );
      }

      debugPrint(
        resultMap['created'] == true
            ? '✅ [WebsiteService] Seeded default footer navigation'
            : 'ℹ️ [WebsiteService] Default footer navigation already exists',
      );
    } catch (e) {
      // The failed attempt belongs to `tenantId`, even if another tenant
      // became active while the RPC was in flight. Always release that key so
      // returning to the original tenant can retry the idempotent command.
      _attemptedDefaultFooterSeedForTenant.remove(tenantId);
      debugPrint('⚠️ [WebsiteService] Failed to seed default footer nav: $e');
    }
  }

  bool _loadNavigationFromSynchronousCacheInternal(
    _WebsiteTenantScopeLease lease, {
    required bool notify,
  }) {
    if (_prefs == null || !_ownsTenantScope(lease)) return false;
    final tenantId = lease.tenantId;
    _evictLegacyPublicStoreCache(tenantId);

    try {
      final cacheKey = _publicStoreCacheKey('navigation', tenantId);
      final cachedJson = _prefs!.getString(cacheKey);
      if (cachedJson == null) return false;

      final navData = jsonDecode(cachedJson) as List<dynamic>;
      final cachedNavigation = navData
          .map((e) =>
              WebsiteNavigation.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      if (!_containsVisibleHeaderNavigation(cachedNavigation)) {
        debugPrint(
          '⚠️ [WebsiteService] Ignoring stale navigation cache without visible header items',
        );
        unawaited(_prefs!.remove(cacheKey));
        return false;
      }

      if (!_ownsTenantScope(lease)) return false;
      _navigation = cachedNavigation;
      _buildNavigationHierarchy();

      _hasLoadedNavigationForTenant = true;
      _loadedNavigationTenantId = tenantId;

      if (notify) {
        debugPrint(
            '💾 [WebsiteService] Loaded navigation from SYNC cache (0ms)');
        _safeNotifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint(
          '⚠️ [WebsiteService] Failed to load navigation sync cache: $e');
      return false;
    }
  }

  Future<void> _persistNavigationToLocalCache(
    _WebsiteTenantScopeLease lease,
    List<WebsiteNavigation> navigation,
  ) async {
    if (!_ownsTenantScope(lease)) return;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      if (!_ownsTenantScope(lease)) return;
      _prefs = prefs;
      final cacheKey = _publicStoreCacheKey('navigation', lease.tenantId);
      await prefs.setString(
        cacheKey,
        jsonEncode(navigation.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Ignore cache write errors
    }
  }

  /// Try to load navigation from synchronous cache (0ms wait)
  bool loadNavigationFromSynchronousCache(String tenantId) {
    final lease = _bindTenantScope(tenantId);
    return _loadNavigationFromSynchronousCacheInternal(lease, notify: true);
  }

  Future<void> _resolveLegacyNavigationPageIds(
    String tenantId,
    List<WebsiteNavigation> navigation,
  ) async {
    final legacyIds = <String>{};
    for (final nav in navigation) {
      if (nav.linkType != NavLinkType.page) continue;
      final raw = (nav.linkValue ?? '').trim();
      if (raw.isEmpty) continue;

      // Newer UI stores '/slug'. Older seeds stored UUIDs.
      if (raw.startsWith('/')) continue;
      if (raw.length < 20 || !raw.contains('-')) continue;
      legacyIds.add(raw);
    }

    if (legacyIds.isEmpty) return;

    try {
      final pagesResp = await _supabase
          .from('website_pages')
          .select(
              'id,tenant_id,slug,title,is_published,is_home,is_system,template,created_at,updated_at')
          .eq('tenant_id', tenantId)
          .inFilter('id', legacyIds.toList());

      final pages = (pagesResp as List)
          .map((e) => WebsitePage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final pageMap = <String, WebsitePage>{
        for (final p in pages) p.id: p,
      };

      for (final nav in navigation) {
        if (nav.linkType != NavLinkType.page) continue;
        final raw = (nav.linkValue ?? '').trim();
        final page = pageMap[raw];
        if (page == null) continue;
        nav.linkedPage = page;
      }
    } catch (e) {
      debugPrint(
          '⚠️ [WebsiteService] Failed to resolve legacy nav page IDs: $e');
    }
  }
  // ============================================================================
  // WEBSITE NAVIGATION (Menu Management - Dec 2025)
  // ============================================================================

  /// Load all navigation items for the current tenant
  Future<void> loadNavigation() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }

      await loadNavigationForTenant(tenantId, notify: true);
    } catch (e) {
      _error = 'Error al cargar navegación: $e';
      debugPrint(_error);
    }
  }

  /// Load navigation for a specific tenant.
  ///
  /// This is required for the public store (anonymous users don't have access
  /// to `_tenantService.getTenantId()`).
  Future<void> loadNavigationForTenant(
    String tenantId, {
    required bool notify,
    bool forceRefresh = false,
  }) async {
    final lease = _bindTenantScope(tenantId);
    await _loadNavigationForTenantWithinScope(
      lease,
      notify: notify,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _loadNavigationForTenantWithinScope(
    _WebsiteTenantScopeLease lease, {
    required bool notify,
    required bool forceRefresh,
  }) async {
    if (!_ownsTenantScope(lease)) return;
    final tenantId = lease.tenantId;

    // Cache hit
    if (!forceRefresh &&
        _hasLoadedNavigationForTenant &&
        _loadedNavigationTenantId == tenantId) {
      return;
    }

    final existing = _navigationLoad;
    if (existing != null && _sameTenantScope(existing.lease, lease)) {
      final didChange = await existing.future;
      if (notify && didChange && _ownsTenantScope(lease)) {
        _safeNotifyListeners();
      }
      return;
    }

    final load = _loadNavigationForTenantFromOrigin(lease);
    final scopedLoad = _WebsiteScopedLoad<bool>(lease: lease, future: load);
    _navigationLoad = scopedLoad;
    try {
      final didChange = await load;
      if (notify && didChange && _ownsTenantScope(lease)) {
        _safeNotifyListeners();
      }
    } catch (e) {
      if (!_ownsTenantScope(lease)) return;
      _error = 'Error al cargar navegación: $e';
      debugPrint(_error);
      rethrow;
    } finally {
      if (identical(_navigationLoad, scopedLoad)) {
        _navigationLoad = null;
      }
    }
  }

  Future<bool> _loadNavigationForTenantFromOrigin(
    _WebsiteTenantScopeLease lease,
  ) async {
    final tenantId = lease.tenantId;
    final previousTenantId = _loadedNavigationTenantId;
    final previousFingerprint =
        jsonEncode(_navigation.map((item) => item.toJson()).toList());
    final response = await _supabase
        .from('website_navigation')
        .select()
        .eq('tenant_id', tenantId)
        .order('order_index', ascending: true);
    if (!_ownsTenantScope(lease)) return false;

    var navigation = (response as List)
        .map((json) => WebsiteNavigation.fromJson(json))
        .toList();

    // If footer navigation isn't configured yet, seed sensible defaults (auth only).
    await _seedDefaultFooterNavigationIfNeeded(lease, navigation);
    if (!_ownsTenantScope(lease)) return false;
    if (navigation.isEmpty ||
        !navigation.any((n) => n.menuLocation == MenuLocation.footer)) {
      final refreshed = await _supabase
          .from('website_navigation')
          .select()
          .eq('tenant_id', tenantId)
          .order('order_index', ascending: true);
      if (!_ownsTenantScope(lease)) return false;
      navigation = (refreshed as List)
          .map((json) => WebsiteNavigation.fromJson(json))
          .toList();
    }

    await _resolveLegacyNavigationPageIds(tenantId, navigation);
    if (!_ownsTenantScope(lease)) return false;
    _buildNavigationHierarchyFor(navigation);

    final nextFingerprint =
        jsonEncode(navigation.map((item) => item.toJson()).toList());
    final didChange =
        previousTenantId != tenantId || previousFingerprint != nextFingerprint;

    if (!_ownsTenantScope(lease)) return false;
    _navigation = navigation;
    _hasLoadedNavigationForTenant = true;
    _loadedNavigationTenantId = tenantId;

    if (didChange) {
      await _persistNavigationToLocalCache(lease, navigation);
    }

    return _ownsTenantScope(lease) && didChange;
  }

  /// Build parent-child hierarchy for navigation items
  void _buildNavigationHierarchy() {
    _buildNavigationHierarchyFor(_navigation);
  }

  void _buildNavigationHierarchyFor(List<WebsiteNavigation> navigation) {
    // Clear any previous hierarchy to avoid duplicate children.
    for (final item in navigation) {
      item.children.clear();
    }

    // Create a map for quick lookup
    final Map<String, WebsiteNavigation> navMap = {};
    for (final item in navigation) {
      navMap[item.id] = item;
    }

    // Assign children to parents
    for (final item in navigation) {
      if (item.parentId != null && navMap.containsKey(item.parentId)) {
        navMap[item.parentId]!.children.add(item);
      }
    }

    // Sort children by order_index
    for (final item in navigation) {
      item.children.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    }
  }

  /// Get navigation items for a specific menu location
  List<WebsiteNavigation> getNavigationByLocation(MenuLocation location) {
    return _navigation
        .where((nav) => nav.menuLocation == location && nav.isTopLevel)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  bool _containsVisibleHeaderNavigation(List<WebsiteNavigation> navigation) {
    return navigation.any(
      (nav) =>
          nav.menuLocation == MenuLocation.header &&
          nav.isTopLevel &&
          nav.isVisible,
    );
  }

  bool get hasVisibleHeaderNavigation =>
      _containsVisibleHeaderNavigation(_navigation);

  /// Get navigation items for header menu
  List<WebsiteNavigation> get headerNavigation =>
      getNavigationByLocation(MenuLocation.header);

  /// Get navigation items for footer menu
  List<WebsiteNavigation> get footerNavigation =>
      getNavigationByLocation(MenuLocation.footer);

  /// Create a new navigation item
  Future<WebsiteNavigation> createNavigation(WebsiteNavigation nav) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }

      final data = nav.toInsertJson();
      data['tenant_id'] = tenantId;

      // Normalize page links to '/slug' style in the payload (do not mutate nav).
      if (nav.linkType == NavLinkType.page && data['link_value'] != null) {
        final raw = data['link_value'].toString().trim();
        if (raw.isNotEmpty && !raw.startsWith('/') && !raw.contains('-')) {
          data['link_value'] = '/$raw';
        }
      }

      final response = await _supabase
          .from('website_navigation')
          .insert(data)
          .select()
          .single();

      final newNav = WebsiteNavigation.fromJson(response);
      _navigation.add(newNav);
      _buildNavigationHierarchy();
      _safeNotifyListeners();

      return newNav;
    } catch (e) {
      _error = 'Error al crear navegación: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  Future<WebsiteNavigation?> getNavigationByIdForTenant(
    String navId,
    String tenantId,
  ) async {
    final response = await _supabase
        .from('website_navigation')
        .select()
        .eq('tenant_id', tenantId)
        .eq('id', navId)
        .maybeSingle();
    return response == null ? null : WebsiteNavigation.fromJson(response);
  }

  /// Idempotent create used only for editor drafts.
  ///
  /// The persisted UUID comes from the durable draft ID, so retrying after a
  /// later failure updates the same row instead of inserting a duplicate.
  Future<WebsiteNavigation> upsertNavigationForTenant({
    required String tenantId,
    required String persistedId,
    required WebsiteNavigation navigation,
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    final lease = _leaseForBoundTenant(tenantId);
    if (navigation.tenantId.trim().isNotEmpty &&
        navigation.tenantId != tenantId) {
      throw StateError('La navegación no pertenece al tenant del guardado.');
    }

    final data = navigation.toInsertJson()
      ..['id'] = persistedId
      ..['tenant_id'] = tenantId
      ..['updated_at'] = DateTime.now().toIso8601String();
    if (navigation.linkType == NavLinkType.page && data['link_value'] != null) {
      final raw = data['link_value'].toString().trim();
      if (raw.isNotEmpty && !raw.startsWith('/') && !raw.contains('-')) {
        data['link_value'] = '/$raw';
      }
    }

    writeGuard?.call();
    final Map<String, dynamic> response;
    try {
      response = await _supabase
          .from('website_navigation')
          .upsert(data, onConflict: 'id')
          .select()
          .single();
    } catch (e) {
      // Reclassify a late failure after an identity change as SUPERSEDED.
      if (e is! WebsiteEditorWriteSupersededException) writeGuard?.call();
      rethrow;
    }
    // Post-response guard: never project A's result into B locally.
    writeGuard?.call();
    final saved = WebsiteNavigation.fromJson(response);
    if (lease != null && _ownsTenantScope(lease)) {
      final index = _navigation.indexWhere((item) => item.id == saved.id);
      if (index >= 0) {
        _navigation[index] = saved;
      } else {
        _navigation.add(saved);
      }
      _buildNavigationHierarchy();
      _safeNotifyListeners();
    }
    return saved;
  }

  /// Update an existing navigation item
  Future<WebsiteNavigation> updateNavigation(WebsiteNavigation nav) async {
    try {
      final updateData = nav.toUpdateJson();
      // Normalize page links to '/slug' style in the payload (do not mutate nav).
      if (nav.linkType == NavLinkType.page &&
          updateData['link_value'] != null) {
        final raw = updateData['link_value'].toString().trim();
        if (raw.isNotEmpty && !raw.startsWith('/') && !raw.contains('-')) {
          updateData['link_value'] = '/$raw';
        }
      }

      final response = await _supabase
          .from('website_navigation')
          .update(updateData)
          .eq('id', nav.id)
          .select()
          .single();

      final updatedNav = WebsiteNavigation.fromJson(response);

      // Update local cache
      final index = _navigation.indexWhere((n) => n.id == nav.id);
      if (index >= 0) {
        _navigation[index] = updatedNav;
      }
      _buildNavigationHierarchy();
      _safeNotifyListeners();

      return updatedNav;
    } catch (e) {
      _error = 'Error al actualizar navegación: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  Future<WebsiteNavigation> updateNavigationForTenant(
    WebsiteNavigation nav,
    String tenantId, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    final lease = _leaseForBoundTenant(tenantId);
    if (nav.tenantId != tenantId) {
      throw StateError('La navegación no pertenece al tenant del guardado.');
    }
    final updateData = nav.toUpdateJson();
    if (nav.linkType == NavLinkType.page && updateData['link_value'] != null) {
      final raw = updateData['link_value'].toString().trim();
      if (raw.isNotEmpty && !raw.startsWith('/') && !raw.contains('-')) {
        updateData['link_value'] = '/$raw';
      }
    }

    writeGuard?.call();
    final Map<String, dynamic> response;
    try {
      response = await _supabase
          .from('website_navigation')
          .update(updateData)
          .eq('tenant_id', tenantId)
          .eq('id', nav.id)
          .select()
          .single();
    } catch (e) {
      // Reclassify a late failure after an identity change as SUPERSEDED.
      if (e is! WebsiteEditorWriteSupersededException) writeGuard?.call();
      rethrow;
    }
    // Post-response guard: never project A's result into B locally.
    writeGuard?.call();
    final saved = WebsiteNavigation.fromJson(response);
    if (lease != null && _ownsTenantScope(lease)) {
      final index = _navigation.indexWhere((item) => item.id == saved.id);
      if (index >= 0) {
        _navigation[index] = saved;
      }
      _buildNavigationHierarchy();
      _safeNotifyListeners();
    }
    return saved;
  }

  Future<void> deleteNavigationForTenant(
    String navId,
    String tenantId, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    final lease = _leaseForBoundTenant(tenantId);
    writeGuard?.call();
    // Authority-bound idempotent command: a stale grant raises 42501
    // instead of silently filtering to 0 rows, and a retry after a lost
    // response converges on 'already_absent'.
    final Object? outcome;
    try {
      outcome = await _supabase.rpc(
        'delete_website_navigation',
        params: {
          'p_tenant_id': tenantId,
          'p_navigation_id': navId,
        },
      );
    } catch (e) {
      // Reclassify a late failure after an identity change as SUPERSEDED.
      if (e is! WebsiteEditorWriteSupersededException) writeGuard?.call();
      rethrow;
    }
    // Post-response guard BEFORE validating the outcome: a late
    // already_absent from A can never become B's confirmation.
    writeGuard?.call();
    if (outcome != 'deleted' && outcome != 'already_absent') {
      throw StateError(
        'delete_website_navigation devolvió un resultado inesperado: '
        '$outcome',
      );
    }
    if (lease != null && _ownsTenantScope(lease)) {
      _navigation.removeWhere(
        (item) =>
            item.tenantId == tenantId &&
            (item.id == navId || item.parentId == navId),
      );
      _buildNavigationHierarchy();
      _safeNotifyListeners();
    }
  }

  /// Reorder navigation items
  Future<void> reorderNavigation(
      MenuLocation location, List<String> orderedIds) async {
    try {
      // Keep signature (location param) for API compatibility.
      // Batch update to avoid N sequential network calls.
      await reorderNavigationIds(orderedIds);
      await loadNavigation();
    } catch (e) {
      _error = 'Error al reordenar navegación: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Reorder an arbitrary set of navigation items by id.
  ///
  /// This is used by editor UIs for drag-and-drop ordering without triggering
  /// multiple rebuilds/notifications mid-gesture.
  Future<void> reorderNavigationIds(List<String> orderedIds) async {
    try {
      if (orderedIds.isEmpty) return;

      // De-dup defensively (drag/drop code should already do this).
      final uniqueOrderedIds = <String>[];
      final seen = <String>{};
      for (final id in orderedIds) {
        final trimmed = id.trim();
        if (trimmed.isEmpty) continue;
        if (seen.add(trimmed)) uniqueOrderedIds.add(trimmed);
      }
      if (uniqueOrderedIds.isEmpty) return;

      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      // Build payload using cached tenant_id (guards against accidental inserts).
      final navById = <String, WebsiteNavigation>{
        for (final nav in _navigation) nav.id: nav,
      };

      final payload = <Map<String, dynamic>>[];
      for (int i = 0; i < uniqueOrderedIds.length; i++) {
        final id = uniqueOrderedIds[i];
        final nav = navById[id];

        final row = <String, dynamic>{
          'id': id,
          'order_index': i,
          'updated_at': nowIso,
        };

        // Only include tenant_id if we have it (avoids sending empty string).
        final tenantId = nav?.tenantId.trim() ?? '';
        if (tenantId.isNotEmpty) {
          row['tenant_id'] = tenantId;
        }

        payload.add(row);
      }

      try {
        // One request: PostgREST upsert with merge semantics.
        await _supabase
            .from('website_navigation')
            .upsert(payload, onConflict: 'id');
      } catch (e) {
        // Fallback to per-row updates if upsert is unsupported by the backend.
        for (int i = 0; i < uniqueOrderedIds.length; i++) {
          await _supabase.from('website_navigation').update({
            'order_index': i,
            'updated_at': nowIso,
          }).eq('id', uniqueOrderedIds[i]);
        }
      }

      // Update local cache (no extra fetch)
      for (int i = 0; i < uniqueOrderedIds.length; i++) {
        final localIndex =
            _navigation.indexWhere((n) => n.id == uniqueOrderedIds[i]);
        if (localIndex >= 0) {
          _navigation[localIndex] = _navigation[localIndex].copyWith(
            orderIndex: i,
            updatedAt: now,
          );
        }
      }

      _buildNavigationHierarchy();
      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al reordenar navegación: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Tenant-scoped, fail-closed ordering used by the editor save coordinator.
  Future<void> reorderNavigationIdsForTenant(
    String tenantId,
    List<String> orderedIds, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    final lease = _leaseForBoundTenant(tenantId);
    final uniqueIds = <String>[];
    final seen = <String>{};
    for (final rawId in orderedIds) {
      final id = rawId.trim();
      if (id.isNotEmpty && seen.add(id)) uniqueIds.add(id);
    }

    final now = DateTime.now();
    for (var index = 0; index < uniqueIds.length; index++) {
      // Re-validate before EVERY one of the N internal updates: an identity
      // switch mid-reorder stops the remaining writes.
      writeGuard?.call();
      final Object? response;
      try {
        response = await _supabase
            .from('website_navigation')
            .update({
              'order_index': index,
              'updated_at': now.toIso8601String(),
            })
            .eq('tenant_id', tenantId)
            .eq('id', uniqueIds[index])
            .select('id')
            .maybeSingle();
      } catch (e) {
        // Reclassify a late failure after an identity change as SUPERSEDED.
        if (e is! WebsiteEditorWriteSupersededException) writeGuard?.call();
        rethrow;
      }
      // Post-response guard BEFORE the null validation: a late null after
      // A -> B is a superseded outcome, never B's missing-row error.
      writeGuard?.call();
      if (response == null) {
        throw StateError(
          'No existe la navegación ${uniqueIds[index]} en el tenant activo.',
        );
      }

      if (lease != null && _ownsTenantScope(lease)) {
        final localIndex =
            _navigation.indexWhere((item) => item.id == uniqueIds[index]);
        if (localIndex >= 0) {
          _navigation[localIndex] = _navigation[localIndex].copyWith(
            orderIndex: index,
            updatedAt: now,
          );
        }
      }
    }
    writeGuard?.call();
    if (lease != null && _ownsTenantScope(lease)) {
      _buildNavigationHierarchy();
      _safeNotifyListeners();
    }
  }

  /// Link navigation items to pages (populate linkedPage field)
  Future<void> linkNavigationToPages() async {
    final Map<String, WebsitePage> pageMap = {};
    for (final page in _pages) {
      pageMap[page.id] = page;
    }

    for (final nav in _navigation) {
      if (nav.linkType == NavLinkType.page && nav.linkValue != null) {
        nav.linkedPage = pageMap[nav.linkValue];
      }
    }

    _safeNotifyListeners();
  }

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  Future<void> initialize() async {
    _isInitializing = true;
    try {
      await Future.wait([
        loadFeaturedProducts(),
        loadContents(),
        loadSettings(),
        // Orders are lazy-loaded when OnlineOrdersPage is opened (performance)
        loadBlocks(), // Load Odoo-style blocks
        loadPages(), // Load multi-page support
        loadNavigation(), // Load navigation menus
      ]);

      // Link navigation items to their pages
      await linkNavigationToPages();

      // Realtime subscriptions setup deferred until needed
    } finally {
      _isInitializing = false;
      _safeNotifyListeners();
    }
  }

  /// Initialize orders (call this when OnlineOrdersPage opens)
  Future<void> initializeOrders() async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) {
      throw Exception('No tenant_id found for current user');
    }
    final lease = _bindTenantScope(tenantId);
    if (_orders.isNotEmpty) return; // Already loaded
    await loadOrders();
    if (!_ownsTenantScope(lease)) return;
    await _setupOrdersRealtime(lease);
  }

  /// Set up realtime subscription for online orders
  Future<void> _setupOrdersRealtime(_WebsiteTenantScopeLease lease) async {
    try {
      if (!_ownsTenantScope(lease)) return;
      final activeTenantId = await _tenantService.getTenantId();
      if (!_ownsTenantScope(lease) || activeTenantId != lease.tenantId) {
        debugPrint('⚠️ [WebsiteService] Cannot setup realtime: no tenant_id');
        return;
      }

      // Unsubscribe from existing channel if any
      await _ordersChannel?.unsubscribe();
      if (!_ownsTenantScope(lease)) return;

      final channel = _supabase
          .channel(
            'online_orders_changes_${lease.tenantId}_${lease.generation}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'online_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: lease.tenantId,
            ),
            callback: (payload) {
              if (!_ownsTenantScope(lease)) return;
              debugPrint(
                  '🔔 [WebsiteService] Online order changed: ${payload.eventType}');
              unawaited(loadOrders()); // Reload orders list
            },
          )
          .subscribe();
      if (!_ownsTenantScope(lease)) {
        await channel.unsubscribe();
        return;
      }
      _ordersChannel = channel;

      debugPrint(
          '✅ [WebsiteService] Realtime subscription active for online_orders');
    } catch (e) {
      debugPrint('❌ [WebsiteService] Failed to setup realtime: $e');
    }
  }

  // ============================================================================
  // CACHED PAGE LOADING - For public store policy pages
  // ============================================================================

  /// Revalidate a public page snapshot against the origin.
  ///
  /// Call [peekPageWithBlocks] before this method when an immediate paint is
  /// possible. This method deliberately does not short-circuit on a cache hit:
  /// every real navigation refreshes the canonical CMS state in the
  /// background. Concurrent refreshes for the same tenant and slug share one
  /// joined Supabase request.
  Future<CachedPageSnapshot?> loadPageWithBlocks(
    String slug, {
    required String tenantId,
  }) async =>
      (await loadPageWithBlocksResult(
        slug,
        tenantId: tenantId,
      ))
          .snapshot;

  /// Same origin revalidation as [loadPageWithBlocks], with provenance.
  ///
  /// A caller that renders retained content after a transient network failure
  /// must keep it `noindex`; an authoritative `null` means the page is no
  /// longer public and local state must be cleared.
  Future<PageSnapshotLoadResult> loadPageWithBlocksResult(
    String slug, {
    required String tenantId,
  }) async {
    final cacheKey = _pageCacheKey(tenantId, slug);
    final fallback = _pageCache.peek(cacheKey);

    try {
      final refreshed = await _pageCache.revalidate(
        cacheKey,
        () => _loadPageWithBlocksFromOrigin(
          slug,
          tenantId: tenantId,
        ),
      );
      return refreshed == null
          ? const PageSnapshotLoadResult.originMissing()
          : PageSnapshotLoadResult.origin(refreshed);
    } on PageSnapshotInvalidatedException {
      // An editor save invalidated this request while it was in flight. That
      // is an unknown/stale result, never authoritative proof that the public
      // page was deleted.
      return PageSnapshotLoadResult.staleFallback(fallback);
    } catch (e) {
      debugPrint('Error loading page with blocks: $e');
      // A transient origin failure must not blank already rendered CMS
      // content. Provenance keeps that retained copy out of the index until
      // the next successful origin revalidation.
      return PageSnapshotLoadResult.staleFallback(fallback);
    }
  }

  /// Single editor-capability truth for every untrusted entry command
  /// (`?edit=true`/`?preview=true` deep links, the OAuth editor restore) and
  /// for the editor data loaders: an authenticated profile, an active tenant
  /// matching the storefront tenant, and admin or `edit_settings` authority.
  ///
  /// The returned snapshot carries an identity fingerprint
  /// (user|activeTenant|storefrontTenant|authority) so the consumer lease is
  /// revoked the moment any of those change (logout, user switch, tenant
  /// switch, role/permission change). Fails closed on any missing piece.
  /// Database RLS remains the final enforcement boundary; this gate protects
  /// the client-side editor projection (chrome, drafts, unpublished-site
  /// bypass).
  ///
  /// [editorCapabilitySync] answers from the warmed identity caches only and
  /// returns null when the profile cache is cold (an async resolve is then
  /// required); [resolveEditorCapability] always answers.
  WebsiteEditorCapabilitySnapshot? editorCapabilitySync(
    String? storefrontTenantId,
  ) {
    final requestedTenantId = storefrontTenantId?.trim() ?? '';
    final userId = _tenantService.currentAuthUserId;
    if (userId == null) {
      return WebsiteEditorCapabilitySnapshot(
        identity: 'anon',
        activeTenantId: '',
        storefrontTenantId: requestedTenantId,
        hasAuthority: false,
        authorityEpoch: _identityEpoch,
      );
    }
    final activeTenantId = _tenantService.currentTenantId;
    if (activeTenantId == null) {
      if (_tenantService.hasResolvedProfileForCurrentUser) {
        // DURABLE: the profile resolved and this user has no active tenant.
        return WebsiteEditorCapabilitySnapshot(
          identity: userId,
          activeTenantId: 'none',
          storefrontTenantId: requestedTenantId,
          hasAuthority: false,
          authorityEpoch: _identityEpoch,
        );
      }
      return null; // Cold cache: resolve async.
    }
    final hasAuthority = _tenantService.hasRole('admin') ||
        _tenantService.hasPermission('edit_settings');
    // `granted` is DERIVED by the snapshot from these typed fields.
    final snapshot = WebsiteEditorCapabilitySnapshot(
      identity: userId,
      activeTenantId: activeTenantId,
      storefrontTenantId: requestedTenantId,
      hasAuthority: hasAuthority,
      authorityEpoch: _identityEpoch,
    );
    // A server-classified authority rejection outranks the stale local
    // grant for this exact fingerprint: the denial holds until NEW identity
    // evidence (an auth lifecycle refresh) replaces the caches, so a
    // rejected ?edit=true cannot loop revoke -> re-grant -> reopen.
    if (snapshot.granted &&
        _editorAuthorityDenialFingerprints[requestedTenantId] ==
            snapshot.fingerprint) {
      return WebsiteEditorCapabilitySnapshot(
        identity: userId,
        activeTenantId: activeTenantId,
        storefrontTenantId: requestedTenantId,
        hasAuthority: false,
        authorityEpoch: _identityEpoch,
      );
    }
    return snapshot;
  }

  /// Server-evidenced denials keyed by storefront tenant: value is the
  /// GRANTED fingerprint the server rejected. Cleared on every auth
  /// lifecycle notification (new identity evidence).
  final Map<String, String> _editorAuthorityDenialFingerprints = {};

  /// Sync identity component for capability request keys (never null).
  String get editorCapabilityRequestIdentity =>
      _tenantService.currentAuthUserId ?? 'anon';

  Future<WebsiteEditorCapabilitySnapshot> resolveEditorCapability(
    String? storefrontTenantId,
  ) async {
    final sync = editorCapabilitySync(storefrontTenantId);
    if (sync != null) return sync;
    await _tenantService.getTenantId(); // Warm the identity caches.
    final warmed = editorCapabilitySync(storefrontTenantId);
    if (warmed != null) return warmed;
    // The profile lookup failed transiently (the cache is still cold for
    // this user). Surface it as unresolved so consumers SUSPEND and retain
    // drafts; a fabricated durable denial here would consume the entry
    // command and discard recoverable sessions.
    throw const WebsiteEditorCapabilityUnresolvedException(
      'No se pudo resolver la identidad del editor; reintenta.',
    );
  }

  Future<bool> canOpenEditorForTenant(String? storefrontTenantId) async =>
      (await resolveEditorCapability(storefrontTenantId)).granted;

  /// Loads a CMS page for the authenticated Website Builder.
  ///
  /// Public callers may only read published rows, while an authorized editor
  /// must be able to open and repair a draft. The capability check is the
  /// same single truth used by the editor entry gate; database RLS remains
  /// the final enforcement boundary.
  Future<CachedPageSnapshot?> loadEditorPageWithBlocks(
    String slug, {
    required String tenantId,
  }) async {
    // Captured BEFORE the FIRST await: the capability resolve itself can
    // span an identity switch, so the whole read is keyed to the identity
    // context present at entry.
    final requestEpoch = identityEpoch;
    final requestIdentity = editorCapabilityRequestIdentity;
    final preGateFingerprint = editorCapabilitySync(tenantId)?.fingerprint;
    if (!await canOpenEditorForTenant(tenantId)) {
      if (identityEpoch != requestEpoch ||
          editorCapabilityRequestIdentity != requestIdentity) {
        throw const WebsiteEditorReadSupersededException(
          'La lectura del editor pertenece a una identidad anterior.',
        );
      }
      throw const WebsiteEditorAuthorityException(
        'No tienes autorización para abrir esta página en el editor.',
      );
    }
    if (identityEpoch != requestEpoch ||
        editorCapabilityRequestIdentity != requestIdentity ||
        (preGateFingerprint != null &&
            editorCapabilitySync(tenantId)?.fingerprint !=
                preGateFingerprint)) {
      throw const WebsiteEditorReadSupersededException(
        'La lectura del editor pertenece a una identidad anterior.',
      );
    }
    // The warm gate fixed the fingerprint for the (unchanged) identity.
    final requestFingerprint = editorCapabilitySync(tenantId)?.fingerprint;
    final Object? response;
    try {
      // The ONLY private read path is the authority-bound RPC: the server
      // re-validates tenant + edit_settings authority and raises 42501.
      // The REST origin loader stays public and published-only.
      response = await _supabase.rpc(
        'load_editor_page_with_blocks',
        params: {
          'p_tenant_id': tenantId,
          'p_slug': _normalizePageSlug(slug),
        },
      );
    } catch (error) {
      if (_editorReadSuperseded(tenantId, requestEpoch, requestFingerprint)) {
        // Identity A's late rejection can neither latch a denial for B nor
        // revoke B; the completion is discarded by the consumer.
        throw WebsiteEditorReadSupersededException(
          'La lectura del editor pertenece a una identidad anterior.',
          cause: error,
        );
      }
      // A cached grant can outlive a remote role/permission edit; the
      // server is the enforcement boundary, so ONLY classified auth/RLS
      // rejections convert into authority loss. Anything transient rethrows
      // unchanged and must never revoke the lease or drafts.
      if (isEditorAuthorityRejection(error)) {
        // Install the durable typed denial BEFORE throwing so the very next
        // capability read already reports it (no re-adoption window).
        recordEditorAuthorityRejectionForTenant(tenantId);
        throw WebsiteEditorAuthorityException(
          'El servidor rechazó la autorización del editor.',
          cause: error,
        );
      }
      rethrow;
    }
    if (_editorReadSuperseded(tenantId, requestEpoch, requestFingerprint)) {
      // A late SUCCESS is equally obsolete: never adopt data across an
      // identity change (A -> B or A -> B -> A).
      throw const WebsiteEditorReadSupersededException(
        'La lectura del editor pertenece a una identidad anterior.',
      );
    }
    if (response == null) return null;
    if (response is! Map) {
      throw const WebsiteCmsReadContractException(
        'La respuesta del editor no es un objeto de página válido.',
      );
    }
    final Map<String, dynamic> row;
    try {
      row = Map<String, dynamic>.from(response);
    } catch (error) {
      throw WebsiteCmsReadContractException(
        'La respuesta del editor no se pudo interpretar.',
        cause: error,
      );
    }
    return _snapshotFromJoinedPageRow(row, tenantId: tenantId);
  }

  /// Latches the durable typed denial for [tenantId] after a
  /// server-classified authority rejection — shared by the read AND write
  /// paths, so a 42501 during Guardar closes the session exactly like one
  /// during a load.
  void recordEditorAuthorityRejectionForTenant(String tenantId) {
    final current = editorCapabilitySync(tenantId);
    if (current != null && current.granted) {
      _editorAuthorityDenialFingerprints[tenantId.trim()] = current.fingerprint;
    }
  }

  bool _editorReadSuperseded(
    String tenantId,
    int requestEpoch,
    String? requestFingerprint,
  ) {
    if (identityEpoch != requestEpoch) return true;
    return editorCapabilitySync(tenantId)?.fingerprint != requestFingerprint;
  }

  /// ALLOWLIST classifier for durable authority loss on editor reads. Only
  /// explicit auth/RLS evidence qualifies: 42501 (Postgres
  /// insufficient_privilege), PGRST301/PGRST302 (PostgREST JWT), explicit
  /// 401/403 statuses, a missing session or an invalid JWT. Every ambiguous
  /// shape — retryable fetches, unknown wrappers without an explicit status,
  /// 5xx, timeouts, base AuthException without status — stays transient so
  /// consumers suspend and retain drafts while the server remains the
  /// fail-closed boundary for content.
  static bool isEditorAuthorityRejection(Object error) {
    // Network-ish AuthException subtypes first: never durable.
    if (error is AuthRetryableFetchException) return false;
    if (error is AuthSessionMissingException) return true;
    if (error is AuthInvalidJwtException) return true;
    if (error is AuthException) {
      // AuthApiException / AuthUnknownException / base AuthException may
      // wrap network failures: only an EXPLICIT auth status or JWT/session
      // code is durable evidence.
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 401 || status == 403) return true;
      final code = error.code?.trim() ?? '';
      return code == 'invalid_jwt' ||
          code == 'session_expired' ||
          code == 'session_not_found';
    }
    if (error is PostgrestException) {
      final code = error.code?.trim() ?? '';
      return code == '42501' ||
          code == 'PGRST301' ||
          code == 'PGRST302' ||
          code == '401' ||
          code == '403';
    }
    return false;
  }

  /// Warm a page snapshot without issuing another request when it is already
  /// cached. A subsequent real navigation still calls [loadPageWithBlocks] and
  /// therefore revalidates the origin.
  Future<CachedPageSnapshot?> prefetchPageWithBlocks(
    String slug, {
    required String tenantId,
  }) {
    final cacheKey = _pageCacheKey(tenantId, slug);
    final cached = peekPageWithBlocks(slug, tenantId: tenantId);
    if (cached != null && _pageCache.isFresh(cacheKey)) {
      return Future.value(cached);
    }
    return loadPageWithBlocks(slug, tenantId: tenantId);
  }

  Future<CachedPageSnapshot?> _loadPageWithBlocksFromOrigin(
    String slug, {
    required String tenantId,
  }) async {
    final normalizedSlug = _normalizePageSlug(slug);

    // website_blocks is linked to website_pages by
    // website_blocks_page_id_fkey. Fetching both owners together removes the
    // old page-list -> page lookup -> blocks waterfall.
    final Map<String, dynamic>? response;
    if (normalizedSlug.isEmpty) {
      final query = _supabase
          .from('website_pages')
          .select('*, website_blocks(*)')
          .eq('tenant_id', tenantId);
      // Structurally public: ONLY published rows can leave this loader.
      response = await query
          .eq('is_published', true)
          .order('is_home', ascending: false)
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();
    } else {
      final query = _supabase
          .from('website_pages')
          .select('*, website_blocks(*)')
          .eq('tenant_id', tenantId)
          .eq('slug', normalizedSlug);
      // Structurally public: ONLY published rows can leave this loader.
      response = await query.eq('is_published', true).limit(1).maybeSingle();
    }

    if (response == null) return null;
    return _snapshotFromJoinedPageRow(response, tenantId: tenantId);
  }

  /// One parser for every joined page+blocks row (public REST origin and
  /// the editor RPC alike). Blocks order deterministically by
  /// (order_index, id) regardless of transport ordering.
  CachedPageSnapshot _snapshotFromJoinedPageRow(
    Map<String, dynamic> response, {
    required String tenantId,
  }) {
    try {
      return _snapshotFromJoinedPageRowUnsafe(response, tenantId: tenantId);
    } on WebsiteCmsReadContractException {
      rethrow;
    } catch (error) {
      // ANY parse/cast/sort/normalization failure is a typed CONTRACT
      // violation (fail closed), never a leaked TypeError/FormatException.
      throw WebsiteCmsReadContractException(
        'La proyección de página no se pudo interpretar.',
        cause: error,
      );
    }
  }

  CachedPageSnapshot _snapshotFromJoinedPageRowUnsafe(
    Map<String, dynamic> response, {
    required String tenantId,
  }) {
    final WebsitePage page;
    try {
      page = WebsitePage.fromJson(response);
    } catch (error) {
      // A malformed page row (bad types/dates) is a CONTRACT violation, not
      // a leaked TypeError/FormatException.
      throw WebsiteCmsReadContractException(
        'La página de la respuesta no se pudo interpretar.',
        cause: error,
      );
    }
    // FAIL CLOSED: a contract violation is an error, never a silent filter
    // that could hide a cross-tenant or malformed row.
    if (page.id.trim().isEmpty) {
      throw const WebsiteCmsReadContractException(
        'La página de la respuesta no tiene id válido.',
      );
    }
    if (page.tenantId != tenantId) {
      throw const WebsiteCmsReadContractException(
        'La página no pertenece al tenant solicitado.',
      );
    }
    final rawBlocks = response['website_blocks'];
    if (rawBlocks is! List) {
      throw const WebsiteCmsReadContractException(
        'La respuesta no incluye una lista de bloques válida.',
      );
    }
    final blocks = <Map<String, dynamic>>[];
    for (final rawBlock in rawBlocks) {
      if (rawBlock is! Map) {
        throw const WebsiteCmsReadContractException(
          'Un bloque de la respuesta no es un objeto válido.',
        );
      }
      final blockId = rawBlock['id']?.toString() ?? '';
      if (blockId.isEmpty) {
        throw const WebsiteCmsReadContractException(
          'Un bloque de la respuesta no tiene id válido.',
        );
      }
      if (rawBlock['tenant_id']?.toString() != tenantId ||
          rawBlock['page_id']?.toString() != page.id) {
        throw const WebsiteCmsReadContractException(
          'Un bloque de la respuesta no pertenece a la página/tenant.',
        );
      }
      if (rawBlock['block_data'] is! Map) {
        // Normalization would silently coerce this to an empty map: at the
        // READ boundary a corrupt payload is a contract violation instead.
        throw const WebsiteCmsReadContractException(
          'Un bloque de la respuesta tiene block_data inválido.',
        );
      }
      blocks.add(Map<String, dynamic>.from(rawBlock));
    }
    blocks.sort((a, b) {
      final byOrder = ((a['order_index'] as num?)?.toInt() ?? 0)
          .compareTo(((b['order_index'] as num?)?.toInt() ?? 0));
      if (byOrder != 0) return byOrder;
      return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
    });

    return CachedPageSnapshot(
      page: page,
      blocks: _normalizeBlocksList(blocks),
    );
  }

  /// Synchronously peek the in-memory cache for a page+blocks.
  ///
  /// Use this to render CMS pages instantly without showing a 1-frame loading
  /// spinner when the data is already cached. Always follow it with
  /// [loadPageWithBlocks] so public content is origin-revalidated.
  CachedPageSnapshot? peekPageWithBlocks(
    String slug, {
    required String tenantId,
  }) {
    return _pageCache.peek(_pageCacheKey(tenantId, slug));
  }

  /// Monotonic auth-identity epoch: bumped on EVERY TenantService identity
  /// notification. Coalesced A→B→A auth events leave the user id equal but
  /// never the epoch, so async consumers (lease resolution, OAuth restore)
  /// key their in-flight work on it and drop stale completions.
  int get identityEpoch => _identityEpoch;
  int _identityEpoch = 0;

  void _onTenantIdentityChanged() {
    if (_disposed) return;
    _identityEpoch++;
    // New identity evidence replaces any server-evidenced denial.
    _editorAuthorityDenialFingerprints.clear();
    // Wake consumers ONLY. The rebuild lets the layout's lease sync observe
    // the identity change, and that lease transition is the single owner of
    // the CMS revalidation signal — emitting here too would double every
    // reload on one auth event.
    _safeNotifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tenantService.removeListener(_onTenantIdentityChanged);
    _ordersChannel?.unsubscribe();
    _cmsPageFreshnessSignal.dispose();
    _httpClient.close();
    super.dispose();
  }
}
