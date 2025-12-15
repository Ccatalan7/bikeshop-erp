import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'veryfi_service.dart';

/// Loads Veryfi configuration from environment variables.
///
/// Required environment variables in `.env`:
/// - `VERYFI_API_URL` - API endpoint (default: https://api.veryfi.com/api/v8/partner/documents)
/// - `VERYFI_CLIENT_ID` - Your Veryfi Client ID
/// - `VERYFI_API_KEY` - Your Veryfi API Key
class VeryfiConfigLoader {
  static bool _envLoaded = false;

  /// Call `await VeryfiConfigLoader.loadEnv()` early (e.g., at app start)
  static Future<void> loadEnv() async {
    if (_envLoaded) return;

    try {
      // Load .env from assets (declared as assets/.env in pubspec.yaml)
      await dotenv.load(fileName: '.env');
      _envLoaded = true;
      debugPrint('✅ Veryfi: Environment loaded from assets/.env');
    } catch (e) {
      debugPrint('⚠️ Veryfi: Could not load .env file: $e');
      // Continue anyway - env vars might be set in platform config
      _envLoaded = true;
    }
  }

  /// Check if Veryfi credentials are properly configured
  static bool get isConfigured {
    final clientId = dotenv.env['VERYFI_CLIENT_ID'];
    final apiKey = dotenv.env['VERYFI_API_KEY'];

    return clientId != null &&
        clientId.isNotEmpty &&
        apiKey != null &&
        apiKey.isNotEmpty;
  }

  /// Get a friendly status message about Veryfi configuration
  static String get statusMessage {
    if (!_envLoaded) {
      return 'Veryfi: Environment not loaded yet';
    }

    final clientId = dotenv.env['VERYFI_CLIENT_ID'];
    final apiKey = dotenv.env['VERYFI_API_KEY'];

    if (clientId == null || clientId.isEmpty) {
      return 'Veryfi: Missing VERYFI_CLIENT_ID in .env';
    }
    if (apiKey == null || apiKey.isEmpty) {
      return 'Veryfi: Missing VERYFI_API_KEY in .env';
    }

    return 'Veryfi: Configured ✓';
  }

  /// Build VeryfiConfig from environment variables
  static VeryfiConfig fromEnv() {
    // Default to v8 API (latest as of 2024)
    final apiUrl = dotenv.env['VERYFI_API_URL'] ??
        'https://api.veryfi.com/api/v8/partner/documents';
    final clientId = dotenv.env['VERYFI_CLIENT_ID'] ?? '';
    final apiKey = dotenv.env['VERYFI_API_KEY'] ?? '';
    final username = dotenv.env['VERYFI_USERNAME'] ?? '';

    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (clientId.isNotEmpty) {
      headers['Client-Id'] = clientId;
    }

    // Veryfi requires: Authorization: apikey USERNAME:API_KEY
    if (username.isNotEmpty && apiKey.isNotEmpty) {
      headers['Authorization'] = 'apikey $username:$apiKey';
    } else if (dotenv.env['VERYFI_AUTH_HEADER'] != null &&
        dotenv.env['VERYFI_AUTH_VALUE'] != null) {
      // Alternative: custom header format
      headers[dotenv.env['VERYFI_AUTH_HEADER']!] =
          dotenv.env['VERYFI_AUTH_VALUE']!;
    }

    debugPrint('🔧 Veryfi config: API URL = $apiUrl');
    debugPrint(
        '🔧 Veryfi config: Client ID = ${clientId.isNotEmpty ? "${clientId.substring(0, 4)}..." : "(empty)"}');
    debugPrint(
        '🔧 Veryfi config: Username = ${username.isNotEmpty ? username : "(empty)"}');

    return VeryfiConfig(apiUrl: apiUrl, extraHeaders: headers);
  }

  /// Validate that the config is usable (has required headers)
  static bool validateConfig(VeryfiConfig config) {
    return config.extraHeaders.containsKey('Authorization') &&
        config.extraHeaders['Authorization']!.isNotEmpty;
  }
}
