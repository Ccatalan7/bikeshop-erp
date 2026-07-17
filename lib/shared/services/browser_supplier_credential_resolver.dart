import '../models/supplier.dart';
import 'browser_credential_vault.dart';

class BrowserSupplierCredential {
  const BrowserSupplierCredential({
    required this.supplierId,
    required this.supplierName,
    required this.origin,
    required this.username,
    required this.password,
    required this.updatedAt,
  });

  final String supplierId;
  final String supplierName;
  final String origin;
  final String username;
  final String password;
  final DateTime updatedAt;
}

/// Resolves a supplier portal credential without allowing arbitrary subdomain
/// matches. The only host alias accepted is an optional leading `www.`.
BrowserSupplierCredential? resolveSupplierCredentialForOrigin({
  required Iterable<Supplier> suppliers,
  required String origin,
}) {
  final normalizedOrigin = normalizeSupplierBrowserOrigin(origin);
  if (normalizedOrigin == null) return null;
  final pageUri = Uri.parse(normalizedOrigin);
  final pageHost = _normalizedHost(pageUri.host);

  final matches = <BrowserSupplierCredential>[];
  for (final supplier in suppliers) {
    if (!supplier.isActive) continue;
    final websiteUri = _parseSupplierWebsite(supplier.website);
    final username = supplier.portalUsername?.trim() ?? '';
    final password = supplier.portalPassword ?? '';
    if (websiteUri == null || username.isEmpty || password.isEmpty) continue;
    if (_normalizedHost(websiteUri.host) != pageHost) continue;
    if (websiteUri.hasPort && websiteUri.port != pageUri.port) continue;
    if (!websiteUri.hasPort &&
        pageUri.hasPort &&
        pageUri.port != _defaultPort(pageUri.scheme)) {
      continue;
    }

    matches.add(
      BrowserSupplierCredential(
        supplierId: supplier.id,
        supplierName: supplier.name,
        origin: normalizedOrigin,
        username: username,
        password: password,
        updatedAt: supplier.updatedAt.toUtc(),
      ),
    );
  }

  return matches.length == 1 ? matches.single : null;
}

/// Supplier records may identify legacy HTTP portals. This normalization is
/// deliberately separate from [BrowserCredentialVault.normalizeOrigin], which
/// remains HTTPS-only so local saved credentials are never exposed on HTTP.
String? normalizeSupplierBrowserOrigin(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri.origin;
}

Uri? _parseSupplierWebsite(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}

String _normalizedHost(String value) {
  final host = value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  return host.startsWith('www.') ? host.substring(4) : host;
}

int _defaultPort(String scheme) => scheme == 'https' ? 443 : 80;
