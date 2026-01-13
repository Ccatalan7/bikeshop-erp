import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/config/supabase_config.dart';

/// Service for integrating MercadoPago payment gateway
///
/// This service handles:
/// - Payment preference creation
/// - Payment status verification
/// - Webhook handling (for server-side notifications)
/// - Fetching available payment methods
class MercadoPagoService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // MercadoPago credentials (should be stored in Supabase settings or .env)
  String? _publicKey;
  String? _accessToken;
  bool _isTestMode = true; // Start in test mode
  String? _storeUrl;
  String? _tenantId; // Tenant ID for multi-tenant filtering

  String? get publicKey => _publicKey;
  bool get isTestMode => _isTestMode;
  bool get isConfigured => _publicKey != null && _accessToken != null;

  /// Set the tenant ID for multi-tenant filtering
  void setTenantId(String tenantId) {
    _tenantId = tenantId;
    debugPrint('🔧 [MercadoPago] Set tenant_id: $tenantId');
  }

  /// Initialize MercadoPago with credentials from database settings
  /// If tenantId is provided, filters by tenant. Otherwise uses RLS.
  Future<void> initialize({String? tenantId}) async {
    if (tenantId != null) {
      _tenantId = tenantId;
    }

    try {
      // Load MercadoPago settings from website_settings table
      var query = _supabase
          .from('website_settings')
          .select('key, value')
          .inFilter('key', [
        'mercadopago_public_key',
        'mercadopago_access_token',
        'mercadopago_test_mode',
        'store_url',
      ]);

      // Filter by tenant if available
      if (_tenantId != null) {
        query = query.eq('tenant_id', _tenantId!);
      }

      final response = await query;

      for (final setting in response as List) {
        final key = setting['key'] as String;
        final value = setting['value'] as String?;

        switch (key) {
          case 'mercadopago_public_key':
            _publicKey = value;
            break;
          case 'mercadopago_access_token':
            _accessToken = value;
            break;
          case 'mercadopago_test_mode':
            _isTestMode = value == 'true' || value == '1';
            break;
          case 'store_url':
            _storeUrl = value;
            break;
        }
      }

      debugPrint(
          '🔧 [MercadoPago] Initialized - configured: $isConfigured, tenant: $_tenantId');

      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing MercadoPago: $e');
    }
  }

  /// Manually set credentials (e.g. loaded from another service)
  void setCredentials({
    required String? publicKey,
    required String? accessToken,
    bool isTestMode = true,
  }) {
    _publicKey = publicKey;
    _accessToken = accessToken;
    _isTestMode = isTestMode;
    notifyListeners();
    debugPrint('🔧 [MercadoPago] Credentials set manually');
  }

  /// Save MercadoPago credentials to database
  /// Requires tenant_id to be set first via setTenantId() or initialize(tenantId:)
  Future<void> saveCredentials({
    required String publicKey,
    required String accessToken,
    required bool testMode,
  }) async {
    if (_tenantId == null) {
      throw Exception('tenant_id not set. Call setTenantId() first.');
    }

    try {
      await _supabase.from('website_settings').upsert([
        {
          'tenant_id': _tenantId,
          'key': 'mercadopago_public_key',
          'value': publicKey
        },
        {
          'tenant_id': _tenantId,
          'key': 'mercadopago_access_token',
          'value': accessToken
        },
        {
          'tenant_id': _tenantId,
          'key': 'mercadopago_test_mode',
          'value': testMode ? 'true' : 'false'
        },
      ], onConflict: 'tenant_id,key');

      _publicKey = publicKey;
      _accessToken = accessToken;
      _isTestMode = testMode;

      debugPrint('✅ [MercadoPago] Credentials saved for tenant: $_tenantId');
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving MercadoPago credentials: $e');
      rethrow;
    }
  }

  /// Get official payment methods from MercadoPago API
  /// Returns a list of payment methods with secure_thumbnail
  Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    if (!isConfigured) {
      debugPrint('🔧 [MercadoPago] Not configured, skipping getPaymentMethods');
      return [];
    }
    if (_publicKey == null) {
      debugPrint('🔧 [MercadoPago] No public key, skipping getPaymentMethods');
      return [];
    }

    try {
      final url = Uri.parse(
          'https://api.mercadopago.com/v1/payment_methods?public_key=$_publicKey');

      debugPrint('🔧 [MercadoPago] Fetching payment methods from $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        debugPrint('🔧 [MercadoPago] Got ${data.length} total payment methods');

        // Filter for credit_card and debit_card
        final filtered = data
            .where((pm) =>
                pm['status'] == 'active' &&
                (pm['payment_type_id'] == 'credit_card' ||
                    pm['payment_type_id'] == 'debit_card'))
            .map((pm) => pm as Map<String, dynamic>)
            .toList();

        // Log what we're returning for debugging
        for (final pm in filtered) {
          debugPrint(
              '🔧 [MercadoPago] ${pm['name']}: thumbnail=${pm['thumbnail']}, secure=${pm['secure_thumbnail']}');
        }

        return filtered;
      } else {
        debugPrint(
            '🔧 [MercadoPago] Error fetching payment methods: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('🔧 [MercadoPago] Exception fetching payment methods: $e');
      return [];
    }
  }

  /// Create a payment preference for an online order
  ///
  /// This generates a MercadoPago checkout preference and returns the init_point
  /// (URL where customer should be redirected to complete payment)
  Future<Map<String, dynamic>> createPreference({
    required String orderId,
    required String orderNumber,
    required double total,
    required List<Map<String, dynamic>> items,
    required String customerEmail,
    String? customerName,
  }) async {
    if (!isConfigured) {
      throw Exception(
          'MercadoPago no está configurado. Configure las credenciales primero.');
    }

    try {
      // Build back_urls
      final successUrl = _buildReturnUrl(orderId: orderId, status: 'success');
      final failureUrl = _buildReturnUrl(orderId: orderId, status: 'failure');
      final pendingUrl = _buildReturnUrl(orderId: orderId, status: 'pending');

      debugPrint('🔗 [MercadoPago] Creating preference with back_urls:');
      debugPrint('   success: $successUrl');
      debugPrint('   failure: $failureUrl');
      debugPrint('   pending: $pendingUrl');

      // Call our Supabase Edge Function to create the preference
      // (This keeps the access token secure on the server)
      final response = await _supabase.functions.invoke(
        'mercadopago-create-preference',
        body: {
          'tenant_id': _tenantId, // Pass tenant_id for multi-tenant filtering
          'order_id': orderId,
          'order_number': orderNumber,
          'total': total,
          'items': items,
          'payer': {
            'email': customerEmail,
            if (customerName != null) 'name': customerName,
          },
          'back_urls': {
            'success': successUrl,
            'failure': failureUrl,
            'pending': pendingUrl,
          },
          'auto_return': 'approved',
          'notification_url': _getWebhookUrl(),
        },
      );

      if (response.status != 200) {
        throw Exception('Error creating payment preference: ${response.data}');
      }

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error creating MercadoPago preference: $e');
      rethrow;
    }
  }

  /// Get payment status from MercadoPago
  Future<Map<String, dynamic>?> getPaymentStatus(String paymentId) async {
    if (!isConfigured) {
      throw Exception('MercadoPago no está configurado.');
    }

    try {
      final response = await _supabase.functions.invoke(
        'mercadopago-get-payment',
        body: {'payment_id': paymentId},
      );

      if (response.status == 200) {
        return response.data as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      debugPrint('Error getting payment status: $e');
      return null;
    }
  }

  /// Process payment confirmation from callback
  ///
  /// This is called when customer returns from MercadoPago after payment
  /// NOTE: Only updates order status. The database trigger
  /// (trg_auto_process_paid_online_order) handles invoice creation.
  Future<void> processPaymentCallback({
    required String orderId,
    required String paymentId,
    required String status,
  }) async {
    try {
      // Update order payment status
      String paymentStatus;
      switch (status) {
        case 'approved':
          paymentStatus = 'paid';
          break;
        case 'pending':
        case 'in_process':
          paymentStatus = 'pending';
          break;
        case 'rejected':
        case 'cancelled':
          paymentStatus = 'failed';
          break;
        default:
          paymentStatus = 'pending';
      }

      // Only update the order status
      // The database trigger (trg_auto_process_paid_online_order) will
      // automatically call process_online_order when payment_status = 'paid'
      await _supabase.from('online_orders').update({
        'payment_status': paymentStatus,
        'payment_method': 'mercadopago',
        'payment_reference': paymentId,
        'paid_at':
            status == 'approved' ? DateTime.now().toIso8601String() : null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      // DO NOT call process_online_order here - the trigger handles it
      // This was causing duplicate invoices!

      debugPrint('✅ [MercadoPago] Order $orderId updated to $paymentStatus');
    } catch (e) {
      debugPrint('Error processing payment callback: $e');
      rethrow;
    }
  }

  /// Handle MercadoPago webhook notification
  ///
  /// This should be implemented as a Supabase Edge Function for security
  /// The Edge Function will:
  /// 1. Verify the webhook signature
  /// 2. Get payment details from MercadoPago API
  /// 3. Update order status
  /// 4. Call process_online_order if approved
  Future<void> handleWebhook(Map<String, dynamic> notification) async {
    // This is a placeholder - actual webhook handling should be done
    // in a Supabase Edge Function for security
    debugPrint('Webhook received: $notification');
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  String _resolveStoreUrl() {
    if (_storeUrl != null && _storeUrl!.isNotEmpty) {
      return _storeUrl!;
    }

    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty) {
        return origin;
      }
    }

    return 'https://vinabike-store.web.app';
  }

  String _buildReturnUrl({required String orderId, required String status}) {
    final base = _normalizeBaseUrl(_resolveStoreUrl());

    String url;
    if (status == 'failure') {
      // Use clean public store routes (no /tienda prefix) for web callbacks.
      // This also matches our canonical URLs on vinabike-store.web.app.
      url = '$base/checkout?pedido=$orderId&status=$status';
    } else {
      url = '$base/pedido/$orderId?status=$status';
    }

    debugPrint('🔗 [MercadoPago] Built return URL for $status: $url');
    return url;
  }

  String _getWebhookUrl() {
    final supabaseUrl = _normalizeBaseUrl(SupabaseConfig.url);
    return '$supabaseUrl/functions/v1/mercadopago-webhook';
  }

  String _normalizeBaseUrl(String url) {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }
}
