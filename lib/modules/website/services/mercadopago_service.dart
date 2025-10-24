import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for integrating MercadoPago payment gateway
/// 
/// This service handles:
/// - Payment preference creation
/// - Payment status verification
/// - Webhook handling (for server-side notifications)
class MercadoPagoService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // MercadoPago credentials (should be stored in Supabase settings or .env)
  String? _publicKey;
  String? _accessToken;
  bool _isTestMode = true; // Start in test mode

  String? get publicKey => _publicKey;
  bool get isTestMode => _isTestMode;
  bool get isConfigured => _publicKey != null && _accessToken != null;

  /// Initialize MercadoPago with credentials from database settings
  Future<void> initialize() async {
    try {
      // Load MercadoPago settings from website_settings table
      final response = await _supabase
          .from('website_settings')
          .select('key, value')
          .inFilter('key', [
        'mercadopago_public_key',
        'mercadopago_access_token',
        'mercadopago_test_mode'
      ]);

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
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing MercadoPago: $e');
    }
  }

  /// Save MercadoPago credentials to database
  Future<void> saveCredentials({
    required String publicKey,
    required String accessToken,
    required bool testMode,
  }) async {
    try {
      await _supabase.from('website_settings').upsert([
        {'key': 'mercadopago_public_key', 'value': publicKey},
        {'key': 'mercadopago_access_token', 'value': accessToken},
        {'key': 'mercadopago_test_mode', 'value': testMode ? 'true' : 'false'},
      ]);

      _publicKey = publicKey;
      _accessToken = accessToken;
      _isTestMode = testMode;

      notifyListeners();
    } catch (e) {
      debugPrint('Error saving MercadoPago credentials: $e');
      rethrow;
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
      throw Exception('MercadoPago no está configurado. Configure las credenciales primero.');
    }

    try {
      // Call our Supabase Edge Function to create the preference
      // (This keeps the access token secure on the server)
      final response = await _supabase.functions.invoke(
        'mercadopago-create-preference',
        body: {
          'order_id': orderId,
          'order_number': orderNumber,
          'total': total,
          'items': items,
          'payer': {
            'email': customerEmail,
            if (customerName != null) 'name': customerName,
          },
          'back_urls': {
            'success': _getCallbackUrl('success'),
            'failure': _getCallbackUrl('failure'),
            'pending': _getCallbackUrl('pending'),
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

      await _supabase.from('online_orders').update({
        'payment_status': paymentStatus,
        'payment_method': 'mercadopago',
        'payment_reference': paymentId,
        'paid_at': status == 'approved' ? DateTime.now().toIso8601String() : null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      // If payment is approved, process the order (create invoice + payment)
      if (status == 'approved') {
        await _supabase.rpc('process_online_order', params: {'p_order_id': orderId});
      }
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

  String _getCallbackUrl(String status) {
    // TODO: Replace with your actual website URL
    const baseUrl = kIsWeb
        ? 'http://localhost:8080' // Development
        : 'https://your-website.com'; // Production

    return '$baseUrl/checkout/callback?status=$status';
  }

  String _getWebhookUrl() {
    // TODO: Replace with your Supabase Edge Function URL
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    return '$supabaseUrl/functions/v1/mercadopago-webhook';
  }
}
