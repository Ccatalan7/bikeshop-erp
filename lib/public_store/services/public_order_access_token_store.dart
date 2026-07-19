import '../../shared/utils/web_url.dart' as web_url;

/// Same-origin, session-lifetime bearer-token storage for public orders.
///
/// Web survives the Mercado Pago round trip through sessionStorage without
/// placing the token in a URL, browser history, referrer or server log. Native
/// storefronts retain the token only in process memory.
class PublicOrderAccessTokenStore {
  PublicOrderAccessTokenStore._();

  static const String _keyPrefix = 'vinabike.public-order-access.v1.';
  static final Map<String, String> _memory = <String, String>{};

  static void save({
    required String orderId,
    required String accessToken,
  }) {
    final normalizedOrderId = orderId.trim();
    final normalizedToken = accessToken.trim();
    if (normalizedOrderId.isEmpty ||
        normalizedToken.length < 40 ||
        normalizedToken.length > 128) {
      throw const FormatException('Credencial pública de pedido inválida');
    }

    _memory[normalizedOrderId] = normalizedToken;
    web_url.setSessionStorageValue(
      '$_keyPrefix$normalizedOrderId',
      normalizedToken,
    );
  }

  static String? read(String orderId) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return null;

    final memoryToken = _memory[normalizedOrderId];
    if (_isValidToken(memoryToken)) return memoryToken;

    final sessionToken = web_url.getSessionStorageValue(
      '$_keyPrefix$normalizedOrderId',
    );
    if (!_isValidToken(sessionToken)) return null;

    final normalizedToken = sessionToken!.trim();
    _memory[normalizedOrderId] = normalizedToken;
    return normalizedToken;
  }

  static void forget(String orderId) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return;
    _memory.remove(normalizedOrderId);
    web_url.setSessionStorageValue('$_keyPrefix$normalizedOrderId', '');
  }

  static bool _isValidToken(String? token) {
    final length = token?.trim().length ?? 0;
    return length >= 40 && length <= 128;
  }

  static void clearMemoryForTesting() => _memory.clear();
}
