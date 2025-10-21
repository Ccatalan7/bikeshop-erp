import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/website_models.dart';
import '../../../shared/models/product.dart';

/// Service for managing website content, banners, featured products, and online orders
class WebsiteService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<WebsiteBanner> _banners = [];
  List<FeaturedProduct> _featuredProducts = [];
  List<WebsiteContent> _contents = [];
  Map<String, String> _settings = {};
  List<OnlineOrder> _orders = [];
  List<Map<String, dynamic>> _blocks = []; // Odoo-style editor blocks

  bool _isLoading = false;
  bool _isInitializing = false;
  String? _error;

  List<WebsiteBanner> get banners => _banners;
  List<FeaturedProduct> get featuredProducts => _featuredProducts;
  List<WebsiteContent> get contents => _contents;
  Map<String, String> get settings => _settings;
  List<OnlineOrder> get orders => _orders;
  List<Map<String, dynamic>> get blocks => _blocks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ============================================================================
  // BANNERS
  // ============================================================================

  Future<void> loadBanners() async {
    _isLoading = true;
    _error = null;
    if (!_isInitializing) notifyListeners();

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
      notifyListeners();
    }
  }

  Future<void> saveBanner(WebsiteBanner banner) async {
    try {
      final data = banner.toJson();
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('website_banners').upsert(data);

      await loadBanners();
    } catch (e) {
      _error = 'Error al guardar banner: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteBanner(String id) async {
    try {
      await _supabase.from('website_banners').delete().eq('id', id);

      await loadBanners();
    } catch (e) {
      _error = 'Error al eliminar banner: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

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
      notifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // WEBSITE BLOCKS (Odoo-style Visual Editor)
  // ============================================================================

  Future<void> loadBlocks() async {
    _isLoading = true;
    _error = null;
    if (!_isInitializing) notifyListeners();

    try {
      final response = await _supabase
          .from('website_blocks')
          .select()
          .order('order_index', ascending: true);

      final data = List<Map<String, dynamic>>.from(response as List);
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
      notifyListeners();
    }
  }

  Future<void> saveBlocks(List<Map<String, dynamic>> blocks) async {
    try {
      // Delete all existing blocks
      await _supabase
          .from('website_blocks')
          .delete()
          .neq('id', '00000000-0000-0000-0000-000000000000');

      // Insert new blocks
      if (blocks.isNotEmpty) {
        final blocksToInsert = blocks.asMap().entries.map((entry) {
          final index = entry.key;
          final block = entry.value;

          return {
            'id': block['id'],
            'block_type': block['type'],
            'block_data': block['data'],
            'is_visible': block['isVisible'] ?? true,
            'order_index': index,
            'updated_at': DateTime.now().toIso8601String(),
          };
        }).toList();

        await _supabase.from('website_blocks').insert(blocksToInsert);
      }

      await loadBlocks();
    } catch (e) {
      _error = 'Error al guardar bloques: $e';
      debugPrint(_error);
      notifyListeners();
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
      notifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // FEATURED PRODUCTS
  // ============================================================================

  Future<void> loadFeaturedProducts() async {
    _isLoading = true;
    _error = null;
    if (!_isInitializing) notifyListeners();

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
      notifyListeners();
    }
  }

  Future<void> addFeaturedProduct(String productId) async {
    try {
      // Get current max order index
      int maxOrder = 0;
      if (_featuredProducts.isNotEmpty) {
        maxOrder = _featuredProducts
            .map((fp) => fp.orderIndex)
            .reduce((a, b) => a > b ? a : b);
      }

      await _supabase.from('featured_products').insert({
        'product_id': productId,
        'active': true,
        'order_index': maxOrder + 1,
      });

      await loadFeaturedProducts();
    } catch (e) {
      _error = 'Error al agregar producto destacado: $e';
      debugPrint(_error);
      notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // CONTENT
  // ============================================================================

  Future<void> loadContents() async {
    _isLoading = true;
    _error = null;
    if (!_isInitializing) notifyListeners();

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
      notifyListeners();
    }
  }

  Future<void> saveContent(WebsiteContent content) async {
    try {
      final data = content.toJson();
      data['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('website_content').upsert(data);

      await loadContents();
    } catch (e) {
      _error = 'Error al guardar contenido: $e';
      debugPrint(_error);
      notifyListeners();
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
    if (!_isInitializing) notifyListeners();

    try {
      final response = await _supabase.from('website_settings').select();

      _settings = {};
      for (final row in response as List) {
        _settings[row['key'] as String] = row['value'] as String? ?? '';
      }

      _error = null;
    } catch (e) {
      _error = 'Error al cargar configuración: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveSetting(String key, String value) async {
    try {
      await _supabase.from('website_settings').upsert({
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      });

      await loadSettings();
    } catch (e) {
      _error = 'Error al guardar configuración: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  String getSetting(String key, [String defaultValue = '']) {
    return _settings[key] ?? defaultValue;
  }

  // ============================================================================
  // ORDERS
  // ============================================================================

  Future<void> loadOrders() async {
    _isLoading = true;
    _error = null;
    if (!_isInitializing) notifyListeners();

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
      notifyListeners();
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
      final response =
          await _supabase.from('online_orders').select().eq('id', id).single();

      final order = OnlineOrder.fromJson(response);
      final items = await _loadOrderItems(order.id);
      return order.copyWith(items: items);
    } catch (e) {
      debugPrint('Error loading order: $e');
      return null;
    }
  }

  /// Create a new online order from the public store
  Future<String> createOrder(Map<String, dynamic> orderData,
      List<Map<String, dynamic>> orderItems) async {
    try {
      // Insert order and get the generated ID
      final orderResponse = await _supabase
          .from('online_orders')
          .insert(orderData)
          .select()
          .single();

      final orderId = orderResponse['id'] as String;

      // Insert order items
      final itemsToInsert = orderItems.map((item) {
        return {
          ...item,
          'order_id': orderId,
        };
      }).toList();

      await _supabase.from('online_order_items').insert(itemsToInsert);

      // Reload orders
      await loadOrders();

      return orderId;
    } catch (e) {
      _error = 'Error al crear pedido: $e';
      debugPrint(_error);
      notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
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

      notifyListeners();
    } catch (e) {
      _error = 'Error al actualizar visibilidad del producto: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  Future<List<Product>> getWebsiteProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .eq('show_on_website', true)
          .gt('stock_quantity', 0)
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
    try {
      // Save to settings table
      await _supabase.from('website_settings').upsert([
        {
          'key': 'hero_title',
          'value': title,
          'updated_at': DateTime.now().toIso8601String(),
        },
        {
          'key': 'hero_subtitle',
          'value': subtitle,
          'updated_at': DateTime.now().toIso8601String(),
        },
        if (imageUrl != null)
          {
            'key': 'hero_image_url',
            'value': imageUrl,
            'updated_at': DateTime.now().toIso8601String(),
          },
      ]);

      await loadSettings();
    } catch (e) {
      _error = 'Error al actualizar sección hero: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  /// Update theme colors
  Future<void> updateThemeColors({
    required int primaryColor,
    required int accentColor,
  }) async {
    try {
      await _supabase.from('website_settings').upsert([
        {
          'key': 'theme_primary_color',
          'value': primaryColor.toString(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        {
          'key': 'theme_accent_color',
          'value': accentColor.toString(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      ]);

      await loadSettings();
    } catch (e) {
      _error = 'Error al actualizar colores: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  /// Update contact information
  Future<void> updateContactInfo({
    required String phone,
    required String email,
    required String address,
  }) async {
    try {
      await _supabase.from('website_settings').upsert([
        {
          'key': 'contact_phone',
          'value': phone,
          'updated_at': DateTime.now().toIso8601String(),
        },
        {
          'key': 'contact_email',
          'value': email,
          'updated_at': DateTime.now().toIso8601String(),
        },
        {
          'key': 'contact_address',
          'value': address,
          'updated_at': DateTime.now().toIso8601String(),
        },
      ]);

      await loadSettings();
    } catch (e) {
      _error = 'Error al actualizar información de contacto: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  Future<void> initialize() async {
    _isInitializing = true;
    try {
      await Future.wait([
        loadBanners(),
        loadFeaturedProducts(),
        loadContents(),
        loadSettings(),
        loadOrders(),
        loadBlocks(), // Load Odoo-style blocks
      ]);
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }
}
