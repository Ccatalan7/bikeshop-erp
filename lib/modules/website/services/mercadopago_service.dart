import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MercadoPagoCheckoutException implements Exception {
  const MercadoPagoCheckoutException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

String _mercadoPagoCheckoutErrorMessage(int? status, Object? details) {
  final providerMessage = details is Map ? details['error']?.toString() : null;

  if (status == 403) {
    return 'La sesión segura del pedido venció. Vuelve a abrir el pedido desde esta compra.';
  }
  if (status == 409 &&
      providerMessage == 'Payment checkout is already being prepared') {
    return 'Estamos preparando el pago. Espera unos segundos y vuelve a intentarlo.';
  }
  if (status == 409) {
    return 'Este pedido ya no está disponible para pago. Puede haberse pagado, cancelado o cambiado su stock.';
  }
  if (status == 429 || (status != null && status >= 500)) {
    return 'Mercado Pago está demorando más de lo normal. No se generará un cobro duplicado; inténtalo nuevamente en unos segundos.';
  }
  return 'No pudimos preparar el pago de forma segura. Revisa el pedido e inténtalo nuevamente.';
}

/// Service for integrating MercadoPago payment gateway
///
/// This service handles:
/// - Payment preference creation
/// - Payment status verification
/// - Webhook handling (for server-side notifications)
/// - Fetching available payment methods
class MercadoPagoService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // The access token is intentionally never loaded in public storefront flows.
  // Edge Functions read it with the service role when creating/verifying payments.
  String? _publicKey;
  String? _accessToken;
  bool _isTestMode = true; // Start in test mode
  String? _tenantId; // Tenant ID for multi-tenant filtering

  String? get publicKey => _publicKey;
  bool get isTestMode => _isTestMode;
  bool get hasAdminAccessTokenInMemory => _accessToken?.isNotEmpty == true;
  bool get isConfigured => _publicKey != null || _tenantId != null;

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
        'mercadopago_test_mode',
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
          case 'mercadopago_test_mode':
            _isTestMode = value == 'true' || value == '1';
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
    required String orderAccessToken,
  }) async {
    if (_tenantId == null) {
      throw Exception('No se pudo detectar la tienda para iniciar el pago.');
    }

    try {
      // Call our Supabase Edge Function to create the preference
      // (provider credentials and authoritative monetary data stay server-side).
      final response = await _supabase.functions.invoke(
        'mercadopago-create-preference',
        body: {
          'order_id': orderId,
          'order_access_token': orderAccessToken,
        },
      );

      if (response.status != 200) {
        throw MercadoPagoCheckoutException(
          _mercadoPagoCheckoutErrorMessage(response.status, response.data),
          retryable: response.status == 409 || response.status == 429,
        );
      }

      return response.data as Map<String, dynamic>;
    } on MercadoPagoCheckoutException {
      rethrow;
    } on FunctionException catch (error) {
      debugPrint(
        'MercadoPago preference function failed with status ${error.status}.',
      );
      throw MercadoPagoCheckoutException(
        _mercadoPagoCheckoutErrorMessage(error.status, error.details),
        retryable:
            error.status == 409 || error.status == 429 || error.status >= 500,
      );
    } catch (error) {
      debugPrint(
        'MercadoPago preference request failed: ${error.runtimeType}.',
      );
      throw const MercadoPagoCheckoutException(
        'No pudimos comunicarnos con Mercado Pago. No se generará un cobro duplicado; inténtalo nuevamente en unos segundos.',
        retryable: true,
      );
    }
  }

  /// Get payment status from MercadoPago
  Future<Map<String, dynamic>?> getPaymentStatus(
    String paymentId, {
    required String orderId,
    required String orderAccessToken,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'mercadopago-get-payment',
        body: {
          'payment_id': paymentId,
          'order_id': orderId,
          'order_access_token': orderAccessToken,
        },
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
    required String orderAccessToken,
  }) async {
    await getPaymentStatus(
      paymentId,
      orderId: orderId,
      orderAccessToken: orderAccessToken,
    );
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
}
