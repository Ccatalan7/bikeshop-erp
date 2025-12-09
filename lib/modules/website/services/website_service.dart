import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/website_models.dart';
import '../models/website_page_models.dart';
import '../../../shared/models/product.dart';
import '../../../shared/services/tenant_service.dart';

/// Service for managing website content, banners, featured products, and online orders
class WebsiteService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TenantService _tenantService = TenantService();

  List<WebsiteBanner> _banners = [];
  List<FeaturedProduct> _featuredProducts = [];
  List<WebsiteContent> _contents = [];
  Map<String, String> _settings = {};
  List<ThemePreset> _themePresets = [];
  List<OnlineOrder> _orders = [];
  List<Map<String, dynamic>> _blocks = []; // Odoo-style editor blocks

  bool _isLoading = false;
  bool _isInitializing = false;
  String? _error;
  bool _disposed = false; // Track disposal state
  
  // Realtime subscriptions
  RealtimeChannel? _ordersChannel;

  List<WebsiteBanner> get banners => _banners;
  List<FeaturedProduct> get featuredProducts => _featuredProducts;
  List<WebsiteContent> get contents => _contents;
  Map<String, String> get settings => _settings;
  List<ThemePreset> get themePresets => List.unmodifiable(_themePresets);
  List<OnlineOrder> get orders => _orders;
  List<Map<String, dynamic>> get blocks => _blocks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Safe version of notifyListeners that checks disposal state
  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
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
      final tenantId = await _tenantService.getTenantId(); // ✅ Use async version
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
        orElse: () => _pages.isNotEmpty ? _pages.first : throw Exception('No pages found'),
      );
      homePageId = homePage.id;
      debugPrint('[WebsiteService] Home page ID: $homePageId');

      debugPrint('[WebsiteService] Querying website_blocks for home page only...');
      final response = await _supabase
          .from('website_blocks')
          .select()
          .eq('tenant_id', tenantId) // ✅ Filter by tenant
          .eq('page_id', homePageId) // ✅ Filter by HOME PAGE ONLY
          .order('order_index', ascending: true);
      debugPrint('[WebsiteService] Query complete, got ${(response as List).length} blocks');

      final data = List<Map<String, dynamic>>.from(response);
      data.sort(
        (a, b) => (a['order_index'] ?? 0).compareTo(b['order_index'] ?? 0),
      );

      _blocks = data;
      _error = null;
    } catch (e) {
      _error = 'Error al cargar bloques: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      debugPrint('[WebsiteService] loadBlocks complete');
      _safeNotifyListeners();
    }
  }

  /// Load blocks for a specific tenant's HOME PAGE (used by public store for anonymous visitors)
  /// This method does NOT require authentication - it uses the provided tenant_id
  /// from subdomain detection (PublicStoreTenantProvider)
  Future<List<Map<String, dynamic>>> loadBlocksForTenant(String tenantId) async {
    try {
      // First, find the home page for this tenant
      final pagesResponse = await _supabase
          .from('website_pages')
          .select('id')
          .eq('tenant_id', tenantId)
          .eq('is_home', true)
          .eq('is_published', true)
          .limit(1);
      
      String? homePageId;
      if ((pagesResponse as List).isNotEmpty) {
        homePageId = pagesResponse[0]['id']?.toString();
      }
      
      // If no home page found, try to get the first published page
      if (homePageId == null) {
        final firstPageResponse = await _supabase
            .from('website_pages')
            .select('id')
            .eq('tenant_id', tenantId)
            .eq('is_published', true)
            .order('created_at', ascending: true)
            .limit(1);
        
        if ((firstPageResponse as List).isNotEmpty) {
          homePageId = firstPageResponse[0]['id']?.toString();
        }
      }
      
      if (homePageId == null) {
        debugPrint('[WebsiteService] No home page found for tenant $tenantId');
        return [];
      }
      
      final response = await _supabase
          .from('website_blocks')
          .select()
          .eq('tenant_id', tenantId)
          .eq('page_id', homePageId) // ✅ Filter by HOME PAGE ONLY
          .order('order_index', ascending: true);
      
      final data = List<Map<String, dynamic>>.from(response as List);
      data.sort(
        (a, b) => (a['order_index'] ?? 0).compareTo(b['order_index'] ?? 0),
      );
      
      // Cache the blocks for reuse
      _blocks = data;
      _safeNotifyListeners();
      
      return data;
    } catch (e) {
      debugPrint('[WebsiteService] Error loading blocks for tenant: $e');
      return [];
    }
  }

  Future<void> saveBlocks(List<Map<String, dynamic>> blocks) async {
    try {
      // Get tenant_id for multi-tenant isolation
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant ID found');
      }

      // Find the home page for this tenant (required for page_id)
      String? homePageId;
      final pagesResponse = await _supabase
          .from('website_pages')
          .select('id')
          .eq('tenant_id', tenantId)
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
              'tenant_id': tenantId,
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
          .eq('tenant_id', tenantId)
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
          final orderIndex = block['order_index'] ?? block['sort_order'] ?? index;

          return {
            'id': block['id'],
            'tenant_id': tenantId, // ✅ Add tenant_id for RLS
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
  Future<List<FeaturedProduct>> loadFeaturedProductsForTenant(String tenantId) async {
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
      final tenantId = await _tenantService.getTenantId(); // ✅ Use async version
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
      final tenantId = await _tenantService.getTenantId(); // ✅ Use async version
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
    try {
      final response = await _supabase
          .from('website_settings')
          .select()
          .eq('tenant_id', tenantId);

      final settings = <String, String>{};
      for (final row in response as List) {
        settings[row['key'] as String] = row['value'] as String? ?? '';
      }
      
      // Also update internal state so getSetting() works
      _settings = settings;
      _themePresets = _parseThemePresets(_settings['theme_presets']);
      
      return settings;
    } catch (e) {
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
      debugPrint('⚠️ [WebsiteService] _upsertSettings called with empty values - skipping');
      return;
    }

    try {
      final tenantId = await _tenantService.getTenantId();
      debugPrint('💾 [WebsiteService] _upsertSettings: tenantId=$tenantId, ${values.length} settings to save');
      if (tenantId == null) {
        throw Exception('No tenant ID available');
      }

      final timestamp = DateTime.now().toIso8601String();
      
      // Update or insert each setting individually
      for (final entry in values.entries) {
        debugPrint('💾 [WebsiteService] Upserting setting: ${entry.key} = ${entry.value} for tenant $tenantId');
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
          debugPrint('✅ [WebsiteService] Updated ${entry.key}: ${updateResult.length} rows affected');
          
          // If no rows were updated, insert new row
          if (updateResult.isEmpty) {
            await _supabase
              .from('website_settings')
              .insert({
                'key': entry.key,
                'value': entry.value?.toString() ?? '',
                'tenant_id': tenantId,
                'updated_at': timestamp,
              });
          }
        } catch (e) {
          debugPrint('⚠️ Error upserting setting ${entry.key}: $e');
          // If INSERT fails due to conflict, try UPDATE again (race condition)
          if (e.toString().contains('409') || e.toString().contains('Conflict')) {
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
      final response = await _supabase
          .from('online_orders')
          .select()
          .order('created_at', ascending: false);

      _orders =
          (response as List).map((json) => OnlineOrder.fromJson(json)).toList();

      // Load items for each order
      for (int i = 0; i < _orders.length; i++) {
        final items = await _loadOrderItems(_orders[i].id);
        _orders[i] = _orders[i].copyWith(items: items);
      }

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
      debugPrint('🛒 [WebsiteService] Order items inserted: ${itemsToInsert.length}');

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

      _pages = (response as List)
          .map((json) => WebsitePage.fromJson(json))
          .toList();

      debugPrint('[WebsiteService] Loaded ${_pages.length} pages for tenant $tenantId');

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
  Future<WebsitePage?> getPageBySlug(String slug) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return null;

      final response = await _supabase
          .from('website_pages')
          .select()
          .eq('tenant_id', tenantId)
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

      final response = await _supabase
          .from('website_pages')
          .insert(data)
          .select()
          .single();

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
      await _supabase
          .from('website_pages')
          .delete()
          .eq('id', pageId);

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
      await _supabase
          .from('website_pages')
          .update({
            'is_published': published,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', pageId);

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
      await _supabase
          .from('website_pages')
          .update({
            'is_home': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', pageId);

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

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      _error = 'Error al cargar bloques de página: $e';
      debugPrint(_error);
      return [];
    }
  }

  /// Save blocks for a specific page
  Future<void> saveBlocksForPage(String pageId, List<Map<String, dynamic>> blocks) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant ID found');
      }

      // Delete existing blocks FOR THIS PAGE ONLY
      await _supabase
          .from('website_blocks')
          .delete()
          .eq('tenant_id', tenantId)
          .eq('page_id', pageId);

      // Insert new blocks
      if (blocks.isNotEmpty) {
        final blocksToInsert = blocks.asMap().entries.map((entry) {
          final index = entry.key;
          final block = entry.value;

          return {
            'id': block['id'],
            'tenant_id': tenantId,
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

      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al guardar bloques de página: $e';
      debugPrint(_error);
      rethrow;
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

      final response = await _supabase
          .from('website_navigation')
          .select()
          .eq('tenant_id', tenantId)
          .order('order_index', ascending: true);

      _navigation = (response as List)
          .map((json) => WebsiteNavigation.fromJson(json))
          .toList();

      // Build hierarchy (children under parents)
      _buildNavigationHierarchy();

      _safeNotifyListeners();
    } catch (e) {
      _error = 'Error al cargar navegación: $e';
      debugPrint(_error);
    }
  }

  /// Build parent-child hierarchy for navigation items
  void _buildNavigationHierarchy() {
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
      final response = await _supabase
          .from('website_navigation')
          .update(nav.toUpdateJson())
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
      await _supabase
          .from('website_navigation')
          .delete()
          .eq('id', navId);

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
  Future<void> reorderNavigation(MenuLocation location, List<String> orderedIds) async {
    try {
      for (int i = 0; i < orderedIds.length; i++) {
        await _supabase
            .from('website_navigation')
            .update({
              'order_index': i,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', orderedIds[i]);
      }

      await loadNavigation();
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
        loadOrders(),
        loadBlocks(), // Load Odoo-style blocks
        loadPages(),  // Load multi-page support
        loadNavigation(), // Load navigation menus
      ]);
      
      // Link navigation items to their pages
      await linkNavigationToPages();
      
      _setupOrdersRealtime(); // Subscribe to real-time order updates
    } finally {
      _isInitializing = false;
      _safeNotifyListeners();
    }
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

      debugPrint('✅ [WebsiteService] Realtime subscription active for online_orders');
    } catch (e) {
      debugPrint('❌ [WebsiteService] Failed to setup realtime: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ordersChannel?.unsubscribe();
    super.dispose();
  }
}
