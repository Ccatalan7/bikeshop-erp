import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_models.dart';
import '../models/website_page_models.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/web_data_bridge.dart';

class WebsiteEditorSaveResult {
  final String? pageId;
  final String? pageSlug;
  final List<Map<String, dynamic>> freshBlocks;

  const WebsiteEditorSaveResult({
    required this.pageId,
    required this.pageSlug,
    required this.freshBlocks,
  });
}

/// Service for managing website content, banners, featured products, and online orders
class WebsiteService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TenantService _tenantService = TenantService();
  final http.Client _httpClient = http.Client();

  // Perf logs are enabled in debug, or in release via:
  // flutter build web --release --dart-define=STORE_PERF_LOGS=true
  static bool get _perfLogsEnabled =>
      kDebugMode || const bool.fromEnvironment('STORE_PERF_LOGS');

  // ============================================================
  // BLOCK NORMALIZATION (Phase 2 - Jan 2026)
  // ============================================================
  static const int _currentBlockSchemaVersion = 1;

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

    // Schema version convention (noop-first; enables safe future migrations)
    normalized['schemaVersion'] =
        (normalized['schemaVersion'] as int?) ?? _currentBlockSchemaVersion;

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

    // --- Phase 3 groundwork: normalized actions (backwards-compatible) ---
    // Keep legacy keys (buttonText/buttonLink, ctaText/ctaLink) but also
    // provide a unified `actions` array for renderers to optionally use.
    if (rawTypeLower == 'hero' ||
        rawTypeLower == 'cta' ||
        rawTypeLower == 'videobanner') {
      final showCta = rawTypeLower == 'videobanner'
          ? (normalized['showCta'] != false)
          : true;

      final legacyLabel =
          (normalized['ctaText'] ?? normalized['buttonText'] ?? '')
              .toString()
              .trim();
      final legacyTo = (normalized['ctaLink'] ?? normalized['buttonLink'] ?? '')
          .toString()
          .trim();

      final existingActionsRaw = normalized['actions'];
      final existingActions = <Map<String, dynamic>>[];
      if (existingActionsRaw is List) {
        for (final item in existingActionsRaw) {
          if (item is Map) {
            existingActions.add(Map<String, dynamic>.from(item));
          }
        }
      }

      // Only synthesize if missing/empty to avoid clobbering future editor-driven actions.
      if (existingActions.isEmpty) {
        if (showCta && legacyTo.isNotEmpty) {
          normalized['actions'] = [
            {
              'type': 'navigate',
              'label': legacyLabel.isNotEmpty ? legacyLabel : 'Ver más',
              'to': legacyTo,
            },
          ];
        } else {
          normalized['actions'] = const <Map<String, dynamic>>[];
        }
      } else {
        // Keep as-is but ensure it's a List<Map>.
        normalized['actions'] = existingActions;
      }
    }

    return normalized;
  }

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
  bool _disposed = false; // Track disposal state
  bool _hasLoadedForTenant =
      false; // Track if loadBlocksForTenant completed (even with no blocks)
  bool _isLoadingForTenant = false; // Prevent concurrent loads

  // Realtime subscriptions
  RealtimeChannel? _ordersChannel;

  // ============================================================
  // PAGE CACHE - Load once, instant on revisit (5 min TTL)
  // ============================================================
  static final Map<String, _CachedPage> _pageCache = {};
  static const Duration _cacheTTL = Duration(minutes: 5);

  /// Clear all cached pages (call when content is edited)
  static void clearPageCache() => _pageCache.clear();

  /// Clear cache for a specific slug
  static void invalidatePageCache(String slug) => _pageCache.remove(slug);

  List<WebsiteBanner> get banners => _banners;
  List<FeaturedProduct> get featuredProducts => _featuredProducts;
  List<WebsiteContent> get contents => _contents;
  Map<String, String> get settings => _settings;
  List<ThemePreset> get themePresets => List.unmodifiable(_themePresets);
  List<OnlineOrder> get orders => _orders;
  List<Map<String, dynamic>> get blocks => _blocks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLoadedForTenant => _hasLoadedForTenant;

  /// Safe version of notifyListeners that checks disposal state
  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ============================================================================
  // UNIFIED PUBLIC STORE DATA LOADER (PERFORMANCE OPTIMIZED)
  // ============================================================================

  // Cloudflare edge cache URL - caches Supabase responses at edge nodes
  static const String _edgeCacheUrl =
      'https://vinabike-edge-cache.vinabike.workers.dev';

  // Local cache refresh TTL for public store bootstrap.
  // If we have recent cached settings+blocks, skip the immediate network refresh.
  static const Duration _publicStoreBootstrapRefreshTTL = Duration(minutes: 5);

  /// Load ALL public store data - tries edge cache first, falls back to Supabase
  /// Edge cache: ~50ms (cache hit) vs Supabase direct: ~700ms
  Future<void> loadPublicStoreDataUnified(String tenantId) async {
    final swTotal = Stopwatch()..start();

    // Prevent duplicate loads
    if (_hasLoadedForTenant) {
      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] loadPublicStoreDataUnified skipped (already loaded)');
      }
      return;
    }

    // If we already have recent cached settings+blocks, skip immediate network refresh.
    // This is especially important on mobile where TLS/DNS can cost ~1s.
    if (_hasFreshPublicStoreCache(tenantId)) {
      // Ensure navigation is available too (sync cache first, then background refresh).
      _loadNavigationFromSynchronousCacheInternal(tenantId, notify: false);
      // Fire-and-forget refresh: navigation changes are rare, but we still want
      // the header/footer to be correct even when settings+blocks are fresh.
      unawaited(loadNavigationForTenant(tenantId, notify: true));

      _hasLoadedForTenant = true;
      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] loadPublicStoreDataUnified skipped (fresh local cache)');
        debugPrint(
            '⏱️ [PublicStorePerf] Total loadPublicStoreDataUnified: ${swTotal.elapsedMilliseconds}ms (source=LOCAL_CACHE_FRESH)');
      }
      return;
    }

    if (_isLoadingForTenant) {
      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] loadPublicStoreDataUnified waiting (already loading)');
      }
      while (_isLoadingForTenant && !_hasLoadedForTenant) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _isLoadingForTenant = true;

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
      try {
        final swPrefetch = Stopwatch()..start();
        final preloaded = await WebDataBridge.getPreloadedStoreData();
        if (preloaded != null) {
          response = preloaded;
          source = 'PREFETCH_JS';
          if (_perfLogsEnabled) {
            debugPrint(
                '⏱️ [PublicStorePerf] Source=$source step=${swPrefetch.elapsedMilliseconds}ms');
          }
        } else {
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

      // 2. Try edge cache (if pre-fetch missed)
      if (response == null) {
        try {
          final swEdge = Stopwatch()..start();
          final cacheResponse = await _tryEdgeCache(tenantId);
          if (cacheResponse != null) {
            response = cacheResponse;
            source = cacheResponse['_cache'] == 'HIT'
                ? 'EDGE_CACHE_HIT'
                : 'EDGE_CACHE_MISS';
            if (_perfLogsEnabled) {
              debugPrint(
                  '⏱️ [PublicStorePerf] Source=$source step=${swEdge.elapsedMilliseconds}ms');
            }
          } else {
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
        response = await _supabase
            .rpc('get_public_store_data', params: {'p_tenant_id': tenantId});
        source = 'SUPABASE_DIRECT';

        if (_perfLogsEnabled) {
          debugPrint(
              '⏱️ [PublicStorePerf] Source=$source step=${swRpc.elapsedMilliseconds}ms');
        }
      }

      // debugPrint(
      //     '⏱️ [WebsiteService] Data loaded ($source): ${sw.elapsedMilliseconds}ms');

      if (response != null) {
        // Parse settings/blocks.
        // NOTE: On the public store we don't need theme presets, so avoid
        // decoding them here (saves work on the UI isolate).
        final settingsData =
            response['settings'] as Map<String, dynamic>? ?? {};
        final blocksData = response['blocks'] as List? ?? [];

        // If we already rendered from sync cache and the network returns the
        // exact same payload, avoid triggering a full rebuild.
        final prefs = _prefs;
        final cachedSettingsJson =
            prefs?.getString('website_settings_$tenantId');
        final cachedBlocksJson = prefs?.getString('website_blocks_$tenantId');
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
          // Load from cache instantly and refresh in background.
          _loadNavigationFromSynchronousCacheInternal(tenantId, notify: false);
          unawaited(loadNavigationForTenant(tenantId, notify: false));

          await _persistPublicStoreLastRefresh(tenantId);
          _hasLoadedForTenant = true;
          _isLoadingForTenant = false;

          if (_perfLogsEnabled) {
            debugPrint(
                '⏱️ [PublicStorePerf] Network payload matches cache; skipping notify');
            debugPrint(
                '⏱️ [PublicStorePerf] Total loadPublicStoreDataUnified: ${swTotal.elapsedMilliseconds}ms (source=$source)');
          }
          return;
        }

        _settings =
            settingsData.map((k, v) => MapEntry(k, v?.toString() ?? ''));

        _blocks = List<Map<String, dynamic>>.from(blocksData);

        if (_perfLogsEnabled) {
          debugPrint('⏱️ [PublicStorePerf] Parsed data: '
              '${_settings.length} settings, ${_blocks.length} blocks');
        }

        // Persist caches and refresh time BEFORE we log completion.
        // This makes the next app launch able to skip the edge-cache call.
        await _persistSettingsToLocalCache(tenantId, settingsData);
        await _persistBlocksToLocalCache(tenantId, _blocks);
        await _persistPublicStoreLastRefresh(tenantId);

        // Navigation is NOT included in get_public_store_data yet, so load it
        // separately (public read is allowed by RLS policy when is_visible=true).
        await loadNavigationForTenant(tenantId, notify: false);

        debugPrint('✅ [WebsiteService] Load complete ($source): '
            '${_settings.length} settings, ${_blocks.length} blocks');
      }

      _hasLoadedForTenant = true;
      _isLoadingForTenant = false;
      _safeNotifyListeners();

      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] Total loadPublicStoreDataUnified: ${swTotal.elapsedMilliseconds}ms (source=$source)');
      }
    } catch (e) {
      debugPrint(
          '⚠️ [WebsiteService] All methods failed, falling back to separate queries: $e');
      _isLoadingForTenant = false;

      if (_perfLogsEnabled) {
        debugPrint(
            '⏱️ [PublicStorePerf] Unified load failed after ${swTotal.elapsedMilliseconds}ms: $e');
      }

      // Fallback to separate queries if RPC doesn't exist yet
      await Future.wait([
        loadSettingsForTenant(tenantId),
        loadBlocksForTenant(tenantId),
        loadNavigationForTenant(tenantId, notify: false),
      ]);
    }
  }

  // Shared preferences instance (injected from main)
  static SharedPreferences? _prefs;

  static void setSharedPreferences(SharedPreferences prefs) {
    _prefs = prefs;
  }

  bool _hasFreshPublicStoreCache(String tenantId) {
    if (_prefs == null) return false;

    final settingsKey = 'website_settings_$tenantId';
    final blocksKey = 'website_blocks_$tenantId';
    final lastRefreshKey = 'website_public_store_last_refresh_$tenantId';

    final hasSettings = _prefs!.getString(settingsKey) != null;
    final hasBlocks = _prefs!.getString(blocksKey) != null;
    if (!hasSettings || !hasBlocks) return false;

    final lastRefreshMs = _prefs!.getInt(lastRefreshKey);
    if (lastRefreshMs == null) return false;

    final lastRefresh = DateTime.fromMillisecondsSinceEpoch(lastRefreshMs);
    return DateTime.now().difference(lastRefresh) <
        _publicStoreBootstrapRefreshTTL;
  }

  Future<void> _persistPublicStoreLastRefresh(String tenantId) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final key = 'website_public_store_last_refresh_$tenantId';
      await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Ignore cache write errors
    }
  }

  /// Loads BOTH settings + blocks from the synchronous cache and notifies once.
  /// This reduces boot-time rebuild churn (helps avoid skipped frames).
  bool preloadPublicStoreFromSynchronousCache(String tenantId) {
    final settingsLoaded = _loadSettingsFromSynchronousCacheInternal(
      tenantId,
      notify: false,
      parseThemePresets: false,
    );
    final blocksLoaded = _loadBlocksFromSynchronousCacheInternal(
      tenantId,
      notify: false,
    );

    final navLoaded = _loadNavigationFromSynchronousCacheInternal(
      tenantId,
      notify: false,
    );

    if (settingsLoaded) {
      debugPrint('💾 [WebsiteService] Loaded settings from SYNC cache (0ms)');
    }
    if (blocksLoaded) {
      debugPrint('💾 [WebsiteService] Loaded blocks from SYNC cache (0ms)');
    }
    if (navLoaded) {
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
    return _loadSettingsFromSynchronousCacheInternal(tenantId, notify: true);
  }

  bool _loadSettingsFromSynchronousCacheInternal(
    String tenantId, {
    required bool notify,
    bool parseThemePresets = true,
  }) {
    if (_prefs == null) return false;

    try {
      final cacheKey = 'website_settings_$tenantId';
      final cachedJson = _prefs!.getString(cacheKey);

      if (cachedJson != null) {
        final settingsData = jsonDecode(cachedJson) as Map<String, dynamic>;
        _settings =
            settingsData.map((k, v) => MapEntry(k, v?.toString() ?? ''));
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
    return _loadBlocksFromSynchronousCacheInternal(tenantId, notify: true);
  }

  bool _loadBlocksFromSynchronousCacheInternal(
    String tenantId, {
    required bool notify,
  }) {
    if (_prefs == null) return false;

    try {
      final cacheKey = 'website_blocks_$tenantId';
      final cachedJson = _prefs!.getString(cacheKey);

      if (cachedJson != null) {
        final blocksData = jsonDecode(cachedJson) as List<dynamic>;
        _blocks = List<Map<String, dynamic>>.from(
          blocksData.map((e) => Map<String, dynamic>.from(e as Map)),
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
    // If we have sync cache, try that first
    if (_prefs != null) {
      return loadSettingsFromSynchronousCache(tenantId);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs; // Store for future sync access
      return loadSettingsFromSynchronousCache(tenantId);
    } catch (e) {
      debugPrint('⚠️ [WebsiteService] Failed to load local cache: $e');
    }
    return false;
  }

  Future<void> _persistSettingsToLocalCache(
      String tenantId, Map<String, dynamic> settingsData) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final cacheKey = 'website_settings_$tenantId';
      await prefs.setString(cacheKey, jsonEncode(settingsData));
    } catch (e) {
      // Ignore cache write errors
    }
  }

  Future<void> _persistBlocksToLocalCache(
      String tenantId, List<Map<String, dynamic>> blocks) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final cacheKey = 'website_blocks_$tenantId';
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
    _isLoading = true;
    _error = null;
    if (!_isInitializing) _safeNotifyListeners();

    try {
      final response =
          await _supabase.from('website_banners').select().order('order_index');

      _banners = (response as List)
          .map((json) => WebsiteBanner.fromJson(json))
          .toList();

      _error = null;
    } catch (e) {
      _error = 'Error al cargar banners: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
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

  @Deprecated('Use deleteBlock() instead')
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
    _isLoading = true;
    _error = null;
    if (!_isInitializing) _safeNotifyListeners();

    try {
      // Get current tenant_id
      debugPrint('[WebsiteService] Getting tenant ID...');
      final tenantId = await _tenantService.getTenantId();
      debugPrint('[WebsiteService] Got tenant ID: $tenantId');
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }

      // First, find the home page ID
      String? homePageId;
      await loadPages(); // Ensure pages are loaded
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
      _error = 'Error al cargar bloques: $e';
      debugPrint(_error);
      _hasLoadedForTenant = true; // Mark loaded even on error
    } finally {
      _isLoading = false;
      debugPrint('[WebsiteService] loadBlocks complete');
      _safeNotifyListeners();
    }
  }

  /// Load blocks for a specific tenant's HOME PAGE (used by public store for anonymous visitors)
  /// This method does NOT require authentication - it uses the provided tenant_id
  /// from subdomain detection (PublicStoreTenantProvider)
  ///
  /// OPTIMIZED: Uses a single query with JOIN to get home page + blocks together

  Future<List<Map<String, dynamic>>> loadBlocksForTenant(
      String tenantId) async {
    final sw = Stopwatch()..start();

    // Prevent duplicate loads - check BOTH flags
    if (_hasLoadedForTenant) {
      debugPrint(
          '[WebsiteService] Already loaded for tenant, returning cached blocks: ${_blocks.length}');
      return _blocks;
    }

    // Prevent concurrent loads
    if (_isLoadingForTenant) {
      debugPrint('[WebsiteService] Already loading, waiting...');
      // Wait for the other load to complete
      while (_isLoadingForTenant && !_hasLoadedForTenant) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _blocks;
    }

    _isLoadingForTenant = true;

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

        if ((firstPageWithBlocks as List).isNotEmpty) {
          final blocks =
              firstPageWithBlocks[0]['website_blocks'] as List? ?? [];
          data = List<Map<String, dynamic>>.from(blocks);
        }
      }

      if (data.isEmpty) {
        debugPrint('[WebsiteService] No blocks found for tenant $tenantId');
        _hasLoadedForTenant = true;
        _safeNotifyListeners();
        return [];
      }

      // Sort by order_index
      data.sort(
        (a, b) => (a['order_index'] ?? 0).compareTo(b['order_index'] ?? 0),
      );

      debugPrint(
          '⏱️ [WebsiteService] Total loadBlocksForTenant: ${sw.elapsedMilliseconds}ms (${data.length} blocks)');

      // Cache the blocks for reuse (normalized)
      final normalizedBlocks = _normalizeBlocksList(data);
      _blocks = normalizedBlocks;
      _hasLoadedForTenant = true;
      _safeNotifyListeners();

      return normalizedBlocks;
    } catch (e) {
      debugPrint('[WebsiteService] Error loading blocks for tenant: $e');
      _hasLoadedForTenant = true; // Mark as loaded even on error
      _safeNotifyListeners();
      return [];
    }
  }

  Future<void> saveBlocks(List<Map<String, dynamic>> blocks,
      {String? tenantId}) async {
    try {
      // Get tenant_id for multi-tenant isolation
      final effectiveTenantId = tenantId ?? await _tenantService.getTenantId();
      if (effectiveTenantId == null) {
        throw Exception('No tenant ID found');
      }

      // Find the home page for this tenant (required for page_id)
      String? homePageId;
      final pagesResponse = await _supabase
          .from('website_pages')
          .select('id')
          .eq('tenant_id', effectiveTenantId)
          .eq('is_home', true)
          .limit(1);

      if ((pagesResponse as List).isNotEmpty) {
        homePageId = pagesResponse[0]['id']?.toString();
      }

      // If no home page found, create one
      if (homePageId == null) {
        debugPrint('[WebsiteService] No home page found, creating one...');
        final newPageResponse = await _supabase
            .from('website_pages')
            .insert({
              'tenant_id': effectiveTenantId,
              'slug': 'home',
              'title': 'Inicio',
              'is_home': true,
              'is_published': true,
              'is_system': true,
            })
            .select('id')
            .single();
        homePageId = newPageResponse['id']?.toString();
        debugPrint('[WebsiteService] Created home page with id: $homePageId');
      }

      // Delete existing blocks FOR THIS TENANT'S HOME PAGE ONLY
      await _supabase
          .from('website_blocks')
          .delete()
          .eq('tenant_id', effectiveTenantId)
          .eq('page_id', homePageId!);

      // Insert new blocks
      if (blocks.isNotEmpty) {
        final blocksToInsert = blocks.asMap().entries.map((entry) {
          final index = entry.key;
          final block = entry.value;

          // Accept both legacy snake_case keys and new camelCase keys
          final blockType = block['type'] ?? block['block_type'];
          final blockData = block['data'] ?? block['block_data'] ?? {};
          final isVisible = block['isVisible'] ?? block['is_visible'] ?? true;
          final orderIndex =
              block['order_index'] ?? block['sort_order'] ?? index;

          return {
            'id': block['id'],
            'tenant_id': effectiveTenantId, // ✅ Add tenant_id for RLS
            'page_id': homePageId, // ✅ Add page_id for proper loading
            'block_type': blockType,
            'block_data': blockData,
            'is_visible': isVisible,
            'order_index': orderIndex,
            'updated_at': DateTime.now().toIso8601String(),
          };
        }).toList();

        await _supabase.from('website_blocks').insert(blocksToInsert);
      }

      // Content changed; invalidate any cached page snapshots.
      WebsiteService.clearPageCache();

      await loadBlocks();
    } catch (e) {
      _error = 'Error al guardar bloques: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<void> deleteBlock(String id) async {
    try {
      await _supabase.from('website_blocks').delete().eq('id', id);

      await loadBlocks();
    } catch (e) {
      _error = 'Error al eliminar bloque: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // FEATURED PRODUCTS
  // ============================================================================

  Future<void> loadFeaturedProducts() async {
    _isLoading = true;
    _error = null;
    if (!_isInitializing) _safeNotifyListeners();

    try {
      final response = await _supabase
          .from('featured_products')
          .select()
          .order('order_index');

      _featuredProducts = (response as List)
          .map((json) => FeaturedProduct.fromJson(json))
          .toList();

      _error = null;
    } catch (e) {
      _error = 'Error al cargar productos destacados: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Load featured products for a specific tenant (used by public store for anonymous visitors)
  /// This method does NOT require authentication
  Future<List<FeaturedProduct>> loadFeaturedProductsForTenant(
      String tenantId) async {
    try {
      final response = await _supabase
          .from('featured_products')
          .select()
          .eq('tenant_id', tenantId)
          .order('order_index');

      final products = (response as List)
          .map((json) => FeaturedProduct.fromJson(json))
          .toList();

      // Also update internal state
      _featuredProducts = products;

      return products;
    } catch (e) {
      return [];
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
    _isLoading = true;
    _error = null;
    if (!_isInitializing) _safeNotifyListeners();

    try {
      final response = await _supabase.from('website_content').select();

      _contents = (response as List)
          .map((json) => WebsiteContent.fromJson(json))
          .toList();

      _error = null;
    } catch (e) {
      _error = 'Error al cargar contenido: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
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
    _isLoading = true;
    _error = null;
    if (!_isInitializing) _safeNotifyListeners();

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant ID available');
      }

      final response = await _supabase
          .from('website_settings')
          .select()
          .eq('tenant_id', tenantId);

      _settings = {};
      for (final row in response as List) {
        _settings[row['key'] as String] = row['value'] as String? ?? '';
      }

      _themePresets = _parseThemePresets(_settings['theme_presets']);

      _error = null;
    } catch (e) {
      _error = 'Error al cargar configuración: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Load settings for a specific tenant (used by public store for anonymous visitors)
  /// This method does NOT require authentication
  Future<Map<String, String>> loadSettingsForTenant(String tenantId) async {
    final sw = Stopwatch()..start();
    try {
      final response = await _supabase
          .from('website_settings')
          .select()
          .eq('tenant_id', tenantId);

      debugPrint(
          '⏱️ [WebsiteService] Settings query: ${sw.elapsedMilliseconds}ms');

      final settings = <String, String>{};
      for (final row in response as List) {
        settings[row['key'] as String] = row['value'] as String? ?? '';
      }

      // Also update internal state so getSetting() works
      _settings = settings;
      _themePresets = _parseThemePresets(_settings['theme_presets']);

      debugPrint(
          '⏱️ [WebsiteService] Settings total: ${sw.elapsedMilliseconds}ms (${settings.length} settings)');
      return settings;
    } catch (e) {
      debugPrint(
          '⏱️ [WebsiteService] Settings ERROR: ${sw.elapsedMilliseconds}ms - $e');
      return {};
    }
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

  String getSetting(String key, [String defaultValue = '']) {
    return _settings[key] ?? defaultValue;
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

    _settings['theme_presets'] = encoded;
    _themePresets = presets;
  }

  Future<void> _upsertSettings(
    Map<String, dynamic> values, {
    required String errorContext,
  }) async {
    if (values.isEmpty) {
      debugPrint(
          '⚠️ [WebsiteService] _upsertSettings called with empty values - skipping');
      return;
    }

    try {
      final tenantId = await _tenantService.getTenantId();
      debugPrint(
          '💾 [WebsiteService] _upsertSettings: tenantId=$tenantId, ${values.length} settings to save');
      if (tenantId == null) {
        throw Exception('No tenant ID available');
      }

      final timestamp = DateTime.now().toIso8601String();

      // Update or insert each setting individually
      for (final entry in values.entries) {
        debugPrint(
            '💾 [WebsiteService] Upserting setting: ${entry.key} = ${entry.value} for tenant $tenantId');
        try {
          // Try UPDATE first (most common case after initial setup)
          final updateResult = await _supabase
              .from('website_settings')
              .update({
                'value': entry.value?.toString() ?? '',
                'updated_at': timestamp,
              })
              .eq('tenant_id', tenantId)
              .eq('key', entry.key)
              .select();
          debugPrint(
              '✅ [WebsiteService] Updated ${entry.key}: ${updateResult.length} rows affected');

          // If no rows were updated, insert new row
          if (updateResult.isEmpty) {
            await _supabase.from('website_settings').insert({
              'key': entry.key,
              'value': entry.value?.toString() ?? '',
              'tenant_id': tenantId,
              'updated_at': timestamp,
            });
          }
        } catch (e) {
          debugPrint('⚠️ Error upserting setting ${entry.key}: $e');
          // If INSERT fails due to conflict, try UPDATE again (race condition)
          if (e.toString().contains('409') ||
              e.toString().contains('Conflict')) {
            await _supabase
                .from('website_settings')
                .update({
                  'value': entry.value?.toString() ?? '',
                  'updated_at': timestamp,
                })
                .eq('tenant_id', tenantId)
                .eq('key', entry.key);
          } else {
            rethrow;
          }
        }
      }

      await loadSettings();
    } catch (e) {
      _error = '$errorContext: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // ORDERS
  // ============================================================================

  Future<void> loadOrders() async {
    _isLoading = true;
    _error = null;
    if (!_isInitializing) _safeNotifyListeners();

    try {
      // Load orders with items in a SINGLE query (no N+1 problem)
      // Limit to recent 100 orders for performance - use pagination for full list
      final response = await _supabase.from('online_orders').select('''
            *,
            online_order_items (*)
          ''').order('created_at', ascending: false).limit(100);

      _orders =
          (response as List).map((json) => OnlineOrder.fromJson(json)).toList();

      _error = null;
    } catch (e) {
      _error = 'Error al cargar pedidos online: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<List<OnlineOrderItem>> _loadOrderItems(String orderId) async {
    try {
      final response = await _supabase
          .from('online_order_items')
          .select()
          .eq('order_id', orderId);

      return (response as List)
          .map((json) => OnlineOrderItem.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error loading order items: $e');
      return [];
    }
  }

  Future<OnlineOrder?> getOrderById(String id) async {
    try {
      debugPrint('🎉 [WebsiteService] getOrderById($id) called');
      final response =
          await _supabase.from('online_orders').select().eq('id', id).single();
      debugPrint('🎉 [WebsiteService] Order response received');

      final order = OnlineOrder.fromJson(response);
      debugPrint('🎉 [WebsiteService] Order parsed: ${order.orderNumber}');

      final items = await _loadOrderItems(order.id);
      debugPrint('🎉 [WebsiteService] Order items loaded: ${items.length}');

      return order.copyWith(items: items);
    } catch (e, stackTrace) {
      debugPrint('❌ [WebsiteService] Error loading order: $e');
      debugPrint('❌ [WebsiteService] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Create a new online order from the public store
  Future<String> createOrder(Map<String, dynamic> orderData,
      List<Map<String, dynamic>> orderItems) async {
    try {
      debugPrint('🛒 [WebsiteService] createOrder() called');

      // Insert order and get the generated ID
      final orderResponse = await _supabase
          .from('online_orders')
          .insert(orderData)
          .select()
          .single();

      final orderId = orderResponse['id'] as String;
      debugPrint('🛒 [WebsiteService] Order inserted, id: $orderId');

      // Insert order items
      final itemsToInsert = orderItems.map((item) {
        return {
          ...item,
          'order_id': orderId,
        };
      }).toList();

      await _supabase.from('online_order_items').insert(itemsToInsert);
      debugPrint(
          '🛒 [WebsiteService] Order items inserted: ${itemsToInsert.length}');

      // DON'T call loadOrders() here - it causes a full rebuild of the widget tree
      // which triggers navigation issues in the public store.
      // The checkout page only needs the orderId to proceed.
      // Admin pages can refresh orders list separately if needed.

      debugPrint('🛒 [WebsiteService] ✅ createOrder() completed successfully');
      return orderId;
    } catch (e) {
      _error = 'Error al crear pedido: $e';
      debugPrint('🛒 [WebsiteService] ❌ createOrder() error: $_error');
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      await _supabase.from('online_orders').update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      await loadOrders();
    } catch (e) {
      _error = 'Error al actualizar estado del pedido: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<void> updatePaymentStatus(String orderId, String paymentStatus) async {
    try {
      await _supabase.from('online_orders').update({
        'payment_status': paymentStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      await loadOrders();
    } catch (e) {
      _error = 'Error al actualizar estado de pago: $e';
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

  // ============================================================================
  // PRODUCT WEBSITE VISIBILITY
  // ============================================================================

  Future<void> updateProductWebsiteVisibility({
    required String productId,
    required bool showOnWebsite,
    String? websiteDescription,
    bool? websiteFeatured,
  }) async {
    try {
      final updates = <String, dynamic>{
        'show_on_website': showOnWebsite,
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

  Future<List<Product>> getWebsiteProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .eq('show_on_website', true)
          .gt('inventory_qty', 0)
          .order('name');

      return (response as List).map((json) => Product.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading website products: $e');
      return [];
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

  /// Update theme colors
  Future<void> updateThemeColors({
    required int primaryColor,
    required int accentColor,
  }) async {
    await _upsertSettings(
      {
        'theme_primary_color': primaryColor,
        'theme_accent_color': accentColor,
      },
      errorContext: 'Error al actualizar colores',
    );
  }

  /// Update complete theme configuration
  Future<void> updateThemeSettings({
    required int primaryColor,
    required int accentColor,
    required int backgroundColor,
    required int textColor,
    required String headingFont,
    required String bodyFont,
    required double headingSize,
    required double bodySize,
    required double sectionSpacing,
    required double containerPadding,
  }) async {
    await _upsertSettings(
      {
        'theme_primary_color': primaryColor,
        'theme_accent_color': accentColor,
        'theme_background_color': backgroundColor,
        'theme_text_color': textColor,
        'theme_heading_font': headingFont,
        'theme_body_font': bodyFont,
        'theme_heading_size': headingSize,
        'theme_body_size': bodySize,
        'theme_section_spacing': sectionSpacing,
        'theme_container_padding': containerPadding,
      },
      errorContext: 'Error al actualizar configuración de tema',
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

  List<WebsitePage> get pages => _pages;
  List<WebsiteNavigation> get navigation => _navigation;

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
  Future<void> loadPagesForTenant(String tenantId) async {
    try {
      final response = await _supabase
          .from('website_pages')
          .select()
          .eq('tenant_id', tenantId)
          .order('is_home', ascending: false)
          .order('title', ascending: true);

      _pages =
          (response as List).map((json) => WebsitePage.fromJson(json)).toList();

      debugPrint(
          '[WebsiteService] Loaded ${_pages.length} pages for tenant $tenantId');

      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al cargar páginas: $e';
      debugPrint(_error);
    }
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

  /// Get a page by slug
  /// If [tenantId] is provided, uses that instead of the current user's tenant
  /// (useful for public store where visitors may not be logged in)
  Future<WebsitePage?> getPageBySlug(String slug, {String? tenantId}) async {
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
      return null;
    }
  }

  /// Get the home page for the current tenant
  Future<WebsitePage?> getHomePage() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return null;

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
      return null;
    }
  }

  /// Create a new page
  Future<WebsitePage> createPage(WebsitePage page) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }

      final data = page.toInsertJson();
      data['tenant_id'] = tenantId;

      final response =
          await _supabase.from('website_pages').insert(data).select().single();

      final newPage = WebsitePage.fromJson(response);
      _pages.add(newPage);
      _safeNotifyListeners();

      return newPage;
    } catch (e) {
      _error = 'Error al crear página: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Update an existing page
  Future<WebsitePage> updatePage(WebsitePage page) async {
    try {
      final response = await _supabase
          .from('website_pages')
          .update(page.toUpdateJson())
          .eq('id', page.id)
          .select()
          .single();

      final updatedPage = WebsitePage.fromJson(response);

      // Update local cache
      final index = _pages.indexWhere((p) => p.id == page.id);
      if (index >= 0) {
        _pages[index] = updatedPage;
      }
      _safeNotifyListeners();

      return updatedPage;
    } catch (e) {
      _error = 'Error al actualizar página: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Delete a page (fails for system pages)
  Future<void> deletePage(String pageId) async {
    try {
      await _supabase.from('website_pages').delete().eq('id', pageId);

      _pages.removeWhere((p) => p.id == pageId);
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
      String pageId, List<Map<String, dynamic>> blocks,
      {String? tenantId}) async {
    try {
      final effectiveTenantId = tenantId ?? await _tenantService.getTenantId();
      if (effectiveTenantId == null) {
        throw Exception('No tenant ID found');
      }

      // Delete existing blocks FOR THIS PAGE ONLY
      await _supabase
          .from('website_blocks')
          .delete()
          .eq('tenant_id', effectiveTenantId)
          .eq('page_id', pageId);

      // Insert new blocks
      if (blocks.isNotEmpty) {
        final blocksToInsert = blocks.asMap().entries.map((entry) {
          final index = entry.key;
          final block = entry.value;

          return {
            'id': block['id'],
            'tenant_id': effectiveTenantId,
            'page_id': pageId,
            'block_type': block['type'] ?? block['block_type'],
            'block_data': block['data'] ?? block['block_data'],
            'is_visible': block['isVisible'] ?? block['is_visible'] ?? true,
            'order_index': index,
            'updated_at': DateTime.now().toIso8601String(),
          };
        }).toList();

        await _supabase.from('website_blocks').insert(blocksToInsert);
      }

      // Content changed; invalidate any cached page snapshots.
      WebsiteService.clearPageCache();

      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al guardar bloques de página: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  // ==========================================================================
  // EDITOR SAVE PIPELINE (Shared by PublicStoreLayout + PersistentEditorShell)
  // ==========================================================================

  Future<WebsiteEditorSaveResult> saveEditorChanges({
    required String tenantId,
    required List<Map<String, dynamic>> editorBlocks,
    required Map<String, String> pendingHeaderSettings,
    required Map<String, String> pendingFooterSettings,
    required Map<String, String> pendingThemeSettings,
    List<String>? pendingFooterSectionOrder,
    Map<String, List<String>>? pendingFooterLinkOrder,
    String? pageId,
    String? pageSlug,
  }) async {
    // Save header/theme settings first (if any)
    if (pendingHeaderSettings.isNotEmpty) {
      await saveSettings(pendingHeaderSettings);
    }
    if (pendingFooterSettings.isNotEmpty) {
      await saveSettings(pendingFooterSettings);
    }
    if (pendingThemeSettings.isNotEmpty) {
      await saveSettings(pendingThemeSettings);
    }

    // Save pending footer navigation order if present
    if (pendingFooterSectionOrder != null &&
        pendingFooterSectionOrder.isNotEmpty) {
      await reorderNavigationIds(pendingFooterSectionOrder);
    }
    if (pendingFooterLinkOrder != null && pendingFooterLinkOrder.isNotEmpty) {
      for (final entry in pendingFooterLinkOrder.entries) {
        await reorderNavigationIds(entry.value);
      }
    }

    // Map provider/editor blocks to the canonical save format
    final blocksForSave = editorBlocks.asMap().entries.map((entry) {
      final index = entry.key;
      final block = entry.value;
      final blockType = block['block_type'] ?? block['type'];
      final blockData = block['block_data'] ?? block['data'] ?? {};
      final isVisible = block['is_visible'] ?? block['isVisible'] ?? true;
      final orderIndex = block['order_index'] ?? index;
      return {
        'id': block['id'],
        'type': blockType,
        'data': blockData,
        'isVisible': isVisible,
        'order_index': orderIndex,
      };
    }).toList();

    // Resolve/create page by slug if needed (prevents accidentally overwriting home)
    var resolvedPageId = pageId;
    final normalizedSlug = (pageSlug ?? '').trim();
    if (resolvedPageId == null &&
        normalizedSlug.isNotEmpty &&
        normalizedSlug.toLowerCase() != 'home') {
      final existingPage =
          await getPageBySlug(normalizedSlug, tenantId: tenantId);
      if (existingPage != null) {
        resolvedPageId = existingPage.id;
      } else {
        final created = await createPage(
          WebsitePage(
            id: '',
            tenantId: tenantId,
            slug: normalizedSlug,
            title: normalizedSlug,
            isPublished: true,
            isHome: false,
            isSystem: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        resolvedPageId = created.id;
      }
    }

    // Persist blocks
    if (resolvedPageId != null) {
      await saveBlocksForPage(resolvedPageId, blocksForSave,
          tenantId: tenantId);
    } else {
      await saveBlocks(blocksForSave, tenantId: tenantId);
    }

    // Reload fresh blocks from DB
    final List<Map<String, dynamic>> freshBlocks;
    if (resolvedPageId != null) {
      freshBlocks = await loadBlocksForPage(resolvedPageId, tenantId: tenantId);
    } else {
      freshBlocks = await loadBlocksForTenant(tenantId);
    }

    return WebsiteEditorSaveResult(
      pageId: resolvedPageId,
      pageSlug: normalizedSlug.isNotEmpty ? normalizedSlug : pageSlug,
      freshBlocks: freshBlocks,
    );
  }

  // ==========================================================================
  // PUBLIC-STORE NAVIGATION CACHE (tenantId-scoped)
  // ==========================================================================

  bool _isLoadingNavigationForTenant = false;
  bool _hasLoadedNavigationForTenant = false;
  String? _loadedNavigationTenantId;

  final Set<String> _attemptedDefaultFooterSeedForTenant = {};

  Future<void> _seedDefaultFooterNavigationIfNeeded(String tenantId) async {
    // Only seed when authenticated (public/anon store must never attempt inserts).
    if (_supabase.auth.currentUser == null) return;
    if (_attemptedDefaultFooterSeedForTenant.contains(tenantId)) return;

    final hasFooter =
        _navigation.any((n) => n.menuLocation == MenuLocation.footer);
    if (hasFooter) return;

    _attemptedDefaultFooterSeedForTenant.add(tenantId);

    try {
      // Create section: Enlaces
      final enlacesParent = await _supabase
          .from('website_navigation')
          .insert({
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Enlaces',
            'link_type': 'action',
            'link_value': '',
            'open_in_new_tab': false,
            'parent_id': null,
            'order_index': 0,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          })
          .select('id')
          .single();

      final enlacesParentId = (enlacesParent['id'] as String?) ?? '';

      if (enlacesParentId.isNotEmpty) {
        await _supabase.from('website_navigation').insert([
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Inicio',
            'link_type': 'page',
            'link_value': '/tienda',
            'open_in_new_tab': false,
            'parent_id': enlacesParentId,
            'order_index': 0,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Productos',
            'link_type': 'page',
            'link_value': '/tienda/productos',
            'open_in_new_tab': false,
            'parent_id': enlacesParentId,
            'order_index': 1,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Servicios',
            'link_type': 'page',
            'link_value': '/tienda/servicios',
            'open_in_new_tab': false,
            'parent_id': enlacesParentId,
            'order_index': 2,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Contacto',
            'link_type': 'page',
            'link_value': '/tienda/contacto',
            'open_in_new_tab': false,
            'parent_id': enlacesParentId,
            'order_index': 3,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
        ]);
      }

      // Create section: Información
      final infoParent = await _supabase
          .from('website_navigation')
          .insert({
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Información',
            'link_type': 'action',
            'link_value': '',
            'open_in_new_tab': false,
            'parent_id': null,
            'order_index': 1,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          })
          .select('id')
          .single();

      final infoParentId = (infoParent['id'] as String?) ?? '';
      if (infoParentId.isNotEmpty) {
        await _supabase.from('website_navigation').insert([
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Sobre Nosotros',
            'link_type': 'page',
            'link_value': '/nosotros',
            'open_in_new_tab': false,
            'parent_id': infoParentId,
            'order_index': 0,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Términos y Condiciones',
            'link_type': 'page',
            'link_value': '/terminos',
            'open_in_new_tab': false,
            'parent_id': infoParentId,
            'order_index': 1,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Política de Privacidad',
            'link_type': 'page',
            'link_value': '/privacidad',
            'open_in_new_tab': false,
            'parent_id': infoParentId,
            'order_index': 2,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Política de Devoluciones',
            'link_type': 'page',
            'link_value': '/devoluciones',
            'open_in_new_tab': false,
            'parent_id': infoParentId,
            'order_index': 3,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
          {
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Envíos',
            'link_type': 'page',
            'link_value': '/envios',
            'open_in_new_tab': false,
            'parent_id': infoParentId,
            'order_index': 4,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
          },
        ]);
      }

      debugPrint('✅ [WebsiteService] Seeded default footer navigation');
    } catch (e) {
      // Non-fatal: keep old fallback behavior.
      debugPrint('⚠️ [WebsiteService] Failed to seed default footer nav: $e');
    }
  }

  bool _loadNavigationFromSynchronousCacheInternal(
    String tenantId, {
    required bool notify,
  }) {
    if (_prefs == null) return false;

    try {
      final cacheKey = 'website_navigation_$tenantId';
      final cachedJson = _prefs!.getString(cacheKey);
      if (cachedJson == null) return false;

      final navData = jsonDecode(cachedJson) as List<dynamic>;
      _navigation = navData
          .map((e) =>
              WebsiteNavigation.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
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

  Future<void> _persistNavigationToLocalCache(String tenantId) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final cacheKey = 'website_navigation_$tenantId';
      await prefs.setString(
        cacheKey,
        jsonEncode(_navigation.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Ignore cache write errors
    }
  }

  /// Try to load navigation from synchronous cache (0ms wait)
  bool loadNavigationFromSynchronousCache(String tenantId) {
    return _loadNavigationFromSynchronousCacheInternal(tenantId, notify: true);
  }

  Future<void> _resolveLegacyNavigationPageIds(String tenantId) async {
    final legacyIds = <String>{};
    for (final nav in _navigation) {
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

      for (final nav in _navigation) {
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
    // Cache hit
    if (!forceRefresh &&
        _hasLoadedNavigationForTenant &&
        _loadedNavigationTenantId == tenantId) {
      return;
    }

    // Prevent concurrent loads
    if (_isLoadingNavigationForTenant) {
      while (_isLoadingNavigationForTenant) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (!forceRefresh &&
          _hasLoadedNavigationForTenant &&
          _loadedNavigationTenantId == tenantId) {
        return;
      }
    }

    _isLoadingNavigationForTenant = true;
    try {
      final response = await _supabase
          .from('website_navigation')
          .select()
          .eq('tenant_id', tenantId)
          .order('order_index', ascending: true);

      _navigation = (response as List)
          .map((json) => WebsiteNavigation.fromJson(json))
          .toList();

      // If footer navigation isn't configured yet, seed sensible defaults (auth only).
      await _seedDefaultFooterNavigationIfNeeded(tenantId);
      if (_navigation.isEmpty ||
          !_navigation.any((n) => n.menuLocation == MenuLocation.footer)) {
        final refreshed = await _supabase
            .from('website_navigation')
            .select()
            .eq('tenant_id', tenantId)
            .order('order_index', ascending: true);
        _navigation = (refreshed as List)
            .map((json) => WebsiteNavigation.fromJson(json))
            .toList();
      }

      await _resolveLegacyNavigationPageIds(tenantId);

      _buildNavigationHierarchy();

      _hasLoadedNavigationForTenant = true;
      _loadedNavigationTenantId = tenantId;

      await _persistNavigationToLocalCache(tenantId);

      if (notify) {
        _safeNotifyListeners();
      }
    } catch (e) {
      _error = 'Error al cargar navegación: $e';
      debugPrint(_error);
      rethrow;
    } finally {
      _isLoadingNavigationForTenant = false;
    }
  }

  /// Build parent-child hierarchy for navigation items
  void _buildNavigationHierarchy() {
    // Clear any previous hierarchy to avoid duplicate children.
    for (final item in _navigation) {
      item.children.clear();
      item.linkedPage = null;
    }

    // Create a map for quick lookup
    final Map<String, WebsiteNavigation> navMap = {};
    for (final item in _navigation) {
      navMap[item.id] = item;
    }

    // Assign children to parents
    for (final item in _navigation) {
      if (item.parentId != null && navMap.containsKey(item.parentId)) {
        navMap[item.parentId]!.children.add(item);
      }
    }

    // Sort children by order_index
    for (final item in _navigation) {
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

  /// Delete a navigation item and its children
  Future<void> deleteNavigation(String navId) async {
    try {
      await _supabase.from('website_navigation').delete().eq('id', navId);

      _navigation.removeWhere((n) => n.id == navId || n.parentId == navId);
      _buildNavigationHierarchy();
      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al eliminar navegación: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Reorder navigation items
  Future<void> reorderNavigation(
      MenuLocation location, List<String> orderedIds) async {
    try {
      for (int i = 0; i < orderedIds.length; i++) {
        await _supabase.from('website_navigation').update({
          'order_index': i,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', orderedIds[i]);
      }

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
      final nowIso = DateTime.now().toIso8601String();

      for (int i = 0; i < orderedIds.length; i++) {
        await _supabase.from('website_navigation').update({
          'order_index': i,
          'updated_at': nowIso,
        }).eq('id', orderedIds[i]);

        final localIndex = _navigation.indexWhere((n) => n.id == orderedIds[i]);
        if (localIndex >= 0) {
          _navigation[localIndex] = _navigation[localIndex].copyWith(
            orderIndex: i,
            updatedAt: DateTime.now(),
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
    if (_orders.isNotEmpty) return; // Already loaded
    await loadOrders();
    _setupOrdersRealtime(); // Subscribe to real-time order updates
  }

  /// Set up realtime subscription for online orders
  void _setupOrdersRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        debugPrint('⚠️ [WebsiteService] Cannot setup realtime: no tenant_id');
        return;
      }

      // Unsubscribe from existing channel if any
      await _ordersChannel?.unsubscribe();

      _ordersChannel = _supabase
          .channel('online_orders_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'online_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              debugPrint(
                  '🔔 [WebsiteService] Online order changed: ${payload.eventType}');
              loadOrders(); // Reload orders list
            },
          )
          .subscribe();

      debugPrint(
          '✅ [WebsiteService] Realtime subscription active for online_orders');
    } catch (e) {
      debugPrint('❌ [WebsiteService] Failed to setup realtime: $e');
    }
  }

  // ============================================================================
  // CACHED PAGE LOADING - For public store policy pages
  // ============================================================================

  /// Load a page by slug with caching (for instant revisits)
  /// Returns page info and blocks, or null if not found
  Future<_CachedPage?> loadPageWithBlocks(
    String slug, {
    required String tenantId,
  }) async {
    // Check cache first
    final cacheKey = '$tenantId:$slug';
    final cached = _pageCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    try {
      // Load page
      final page = await getPageBySlug(slug, tenantId: tenantId);
      if (page == null) return null;

      // Load blocks
      final blocks = await loadBlocksForPage(page.id, tenantId: tenantId);

      // Cache and return
      final result = _CachedPage(
        page: page,
        blocks: blocks,
        cachedAt: DateTime.now(),
      );
      _pageCache[cacheKey] = result;
      return result;
    } catch (e) {
      debugPrint('Error loading page with blocks: $e');
      return null;
    }
  }

  /// Synchronously peek the in-memory cache for a page+blocks.
  ///
  /// Use this to render policy pages instantly without showing a 1-frame
  /// loading spinner when the data is already cached.
  CachedPageSnapshot? peekPageWithBlocks(
    String slug, {
    required String tenantId,
  }) {
    final cacheKey = '$tenantId:$slug';
    final cached = _pageCache[cacheKey];
    if (cached == null || cached.isExpired) return null;
    return CachedPageSnapshot(page: cached.page, blocks: cached.blocks);
  }

  @override
  void dispose() {
    _disposed = true;
    _ordersChannel?.unsubscribe();
    _httpClient.close();
    super.dispose();
  }
}

/// Public snapshot of cached page data (safe to expose).
class CachedPageSnapshot {
  final WebsitePage page;
  final List<Map<String, dynamic>> blocks;

  CachedPageSnapshot({
    required this.page,
    required this.blocks,
  });
}

/// Cached page data with TTL
class _CachedPage {
  final WebsitePage page;
  final List<Map<String, dynamic>> blocks;
  final DateTime cachedAt;

  _CachedPage({
    required this.page,
    required this.blocks,
    required this.cachedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > WebsiteService._cacheTTL;
}
