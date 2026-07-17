import '../models/supplier.dart';

/// Non-secret supplier portal metadata used by the ERP browser omnibox.
///
/// Credentials intentionally do not belong to this model: the omnibox only
/// needs the supplier name and its configured portal address.
class BrowserSupplierPortalEntry {
  const BrowserSupplierPortalEntry({
    required this.supplierId,
    required this.supplierName,
    required this.host,
    required this.url,
  });

  final String supplierId;
  final String supplierName;
  final String host;
  final String url;
}

/// Builds the shared corporate portal catalog from active supplier records.
///
/// Bare domains default to HTTPS. Query strings, fragments and user-info are
/// discarded so central suggestions can never carry transient or secret URL
/// data. An explicitly configured path such as `/login` remains available.
List<BrowserSupplierPortalEntry> buildBrowserSupplierPortalCatalog(
  Iterable<Supplier> suppliers,
) {
  final candidates = <_PortalCandidate>[];

  for (final supplier in suppliers) {
    if (!supplier.isActive) continue;
    final uri = _parsePortalUri(supplier.website);
    if (uri == null) continue;

    candidates.add(
      _PortalCandidate(
        entry: BrowserSupplierPortalEntry(
          supplierId: supplier.id,
          supplierName: supplier.name.trim().isEmpty
              ? _normalizedHost(uri.host)
              : supplier.name.trim(),
          host: uri.host,
          url: uri.toString(),
        ),
        scheme: uri.scheme,
        dedupeKey: _portalDedupeKey(uri),
      ),
    );
  }

  candidates.sort((a, b) {
    final keyComparison = a.dedupeKey.compareTo(b.dedupeKey);
    if (keyComparison != 0) return keyComparison;
    final schemeComparison = _schemeRank(a.scheme).compareTo(
      _schemeRank(b.scheme),
    );
    if (schemeComparison != 0) return schemeComparison;
    final nameComparison = a.entry.supplierName.toLowerCase().compareTo(
          b.entry.supplierName.toLowerCase(),
        );
    if (nameComparison != 0) return nameComparison;
    return a.entry.supplierId.compareTo(b.entry.supplierId);
  });

  final byPortal = <String, BrowserSupplierPortalEntry>{};
  for (final candidate in candidates) {
    byPortal.putIfAbsent(candidate.dedupeKey, () => candidate.entry);
  }

  final entries = byPortal.values.toList(growable: false);
  entries.sort((a, b) {
    final nameComparison = a.supplierName.toLowerCase().compareTo(
          b.supplierName.toLowerCase(),
        );
    if (nameComparison != 0) return nameComparison;
    return a.host.toLowerCase().compareTo(b.host.toLowerCase());
  });
  return entries;
}

Uri? _parsePortalUri(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final parsed = Uri.tryParse(candidate);
  if (parsed == null ||
      parsed.host.isEmpty ||
      (parsed.scheme != 'http' && parsed.scheme != 'https')) {
    return null;
  }

  final scheme = parsed.scheme.toLowerCase();
  final port = parsed.hasPort && parsed.port != _defaultPort(scheme)
      ? parsed.port
      : null;
  return Uri(
    scheme: scheme,
    host: parsed.host.toLowerCase(),
    port: port,
    path: parsed.path,
  );
}

String _portalDedupeKey(Uri uri) {
  final port =
      uri.hasPort && uri.port != _defaultPort(uri.scheme) ? ':${uri.port}' : '';
  return '${_normalizedHost(uri.host)}$port';
}

String _normalizedHost(String value) {
  final host = value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  return host.startsWith('www.') ? host.substring(4) : host;
}

int _schemeRank(String scheme) => scheme == 'https' ? 0 : 1;

int _defaultPort(String scheme) => scheme == 'https' ? 443 : 80;

class _PortalCandidate {
  const _PortalCandidate({
    required this.entry,
    required this.scheme,
    required this.dedupeKey,
  });

  final BrowserSupplierPortalEntry entry;
  final String scheme;
  final String dedupeKey;
}
