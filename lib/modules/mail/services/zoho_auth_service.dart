import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Zoho OAuth 2.0 Authentication Service
/// Handles token acquisition, storage, and refresh
class ZohoAuthService with ChangeNotifier {
  static const String _authUrl = 'https://accounts.zoho.com/oauth/v2/auth';

  // Required scopes for mail access
  static const String _scopes =
      'ZohoMail.messages.READ,ZohoMail.messages.CREATE,ZohoMail.messages.UPDATE,ZohoMail.accounts.READ,ZohoMail.folders.READ';

  // Zoho OAuth credentials
  // Client ID is needed for authorization URL
  static const String clientId = '1000.23SML89U5VKEOKXT0GW12J0SAPQYRQ';

  // Client Secret is now handled securely in Supabase Edge Function

  String? _accessToken;
  String? _refreshToken;
  String? _accountId;
  DateTime? _tokenExpiry;

  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;

  // Getters
  bool get isAuthenticated => _isAuthenticated && _accessToken != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get accessToken => _accessToken;
  String? get accountId => _accountId;

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Initialize - check for existing tokens in Supabase
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _isAuthenticated = false;
        return;
      }

      // Try to load stored tokens from Supabase
      final response = await _supabase
          .from('zoho_tokens')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        _refreshToken = response['refresh_token'];
        _accountId = response['account_id'];

        // Refresh access token
        if (_refreshToken != null) {
          await refreshAccessToken();
        }
      }
    } catch (e) {
      debugPrint('ZohoAuthService init error: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Generate the OAuth authorization URL
  String getAuthorizationUrl({required String redirectUri}) {
    final params = {
      'response_type': 'code',
      'client_id': clientId,
      'scope': _scopes,
      'redirect_uri': redirectUri,
      'access_type': 'offline', // Required for refresh token
      'prompt': 'consent',
    };

    return '$_authUrl?${Uri(queryParameters: params).query}';
  }

  /// Exchange authorization code for tokens
  Future<bool> exchangeCodeForTokens({
    required String code,
    required String redirectUri,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    debugPrint('🔐 [ZohoAuth] Exchanging code: ${code.substring(0, 10)}...');
    debugPrint('🔐 [ZohoAuth] Redirect URI: $redirectUri');

    try {
      // Call Supabase Edge Function to avoid CORS
      final FunctionResponse response = await _supabase.functions.invoke(
        'zoho-oauth',
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
        },
      );

      debugPrint('🔐 [ZohoAuth] Function response status: ${response.status}');

      if (response.status != 200) {
        debugPrint('🔐 [ZohoAuth] Function error: ${response.data}');
        throw Exception('Token exchange failed: ${response.data}');
      }

      final data = response.data;

      if (data['error'] != null) {
        debugPrint(
            '🔐 [ZohoAuth] API Error: ${data['error']} - ${data['error_description']}');
        throw Exception(data['error_description'] ?? data['error']);
      }

      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];
      _tokenExpiry = DateTime.now().add(
        Duration(seconds: data['expires_in'] ?? 3600),
      );

      debugPrint('🔐 [ZohoAuth] Token exchange successful.');

      // Extract Account ID from backend response
      if (data['account_info'] != null) {
        _accountId = data['account_info']['accountId']?.toString();
        debugPrint('🔐 [ZohoAuth] Account ID from backend: $_accountId');
      }

      // If missing, we might still try to fetch it, but that would fail CORS
      // Ideally the backend should always return it provided scopes are correct
      if (_accountId == null) {
        debugPrint('⚠️ [ZohoAuth] Account ID missing in backend response.');
      }

      // Store tokens in Supabase
      await _storeTokens();
      debugPrint('🔐 [ZohoAuth] Tokens stored in Supabase');

      _isAuthenticated = true;
      return true;
    } catch (e) {
      debugPrint('🔐 [ZohoAuth] Token exchange error: $e');
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh the access token using refresh token
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      // Call Supabase Edge Function to avoid CORS
      final FunctionResponse response = await _supabase.functions.invoke(
        'zoho-oauth',
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        },
      );

      if (response.status != 200) {
        throw Exception('Token refresh failed: ${response.data}');
      }

      final data = response.data;

      if (data['error'] != null) {
        // Refresh token expired - need to re-authenticate
        _isAuthenticated = false;
        notifyListeners();
        throw Exception(data['error_description'] ?? data['error']);
      }

      _accessToken = data['access_token'];
      _tokenExpiry = DateTime.now().add(
        Duration(seconds: data['expires_in'] ?? 3600),
      );

      _isAuthenticated = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Token refresh error: $e');
      _error = e.toString();
      return false;
    }
  }

  /// Get a valid access token (refreshing if needed)
  Future<String?> getValidAccessToken() async {
    if (_accessToken == null) return null;

    // Check if token is expired or about to expire (5 min buffer)
    if (_tokenExpiry != null &&
        DateTime.now()
            .isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      await refreshAccessToken();
    }

    return _accessToken;
  }

  /// Store tokens securely in Supabase
  Future<void> _storeTokens() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('zoho_tokens').upsert({
      'user_id': userId,
      'refresh_token': _refreshToken,
      'account_id': _accountId,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  /// Disconnect Zoho account
  Future<void> disconnect() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      await _supabase.from('zoho_tokens').delete().eq('user_id', userId);
    }

    _accessToken = null;
    _refreshToken = null;
    _accountId = null;
    _isAuthenticated = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
