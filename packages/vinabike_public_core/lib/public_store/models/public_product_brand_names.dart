/// Whether [name] is a brand a shopper can recognize, and so may be shown and
/// declared as the product's brand: not the placeholder for «no brand»
/// («Genérico») nor where the product came from (a country or the supplier
/// it was bought from). On 2026-10-08, 46 published products showed
/// «Aliexpress» as their brand on the card, the product page and the JSON-LD,
/// and 46 more showed the distributor «Andes Industrial».
bool isPublicProductBrand(String name) {
  final normalized = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u');
  if (normalized.isEmpty) return false;
  return !const {
    'generico',
    'generic',
    'china',
    'taiwan',
    'aliexpress',
    'andes industrial',
  }.contains(normalized);
}

/// Builds the tenant-safe linked-brand map shared by public product consumers.
/// A brand that is not a public brand ([isPublicProductBrand]) is left out.
///
/// `product_brands` can contain tenant-owned and global (`tenant_id = null`)
/// rows. The caller may use a public client, so this defensive boundary also
/// rejects active rows from another tenant and rows that were not requested.
Map<String, String> canonicalPublicProductBrandNames({
  required List<Map<String, dynamic>> rows,
  required String tenantId,
  required Iterable<String> requestedBrandIds,
}) {
  final requested = requestedBrandIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final normalizedTenantId = tenantId.trim();
  final namesById = <String, String>{};
  for (final row in rows) {
    final id = row['id']?.toString().trim() ?? '';
    final name = row['name']?.toString().trim() ?? '';
    final rowTenantId = row['tenant_id']?.toString().trim() ?? '';
    if (!requested.contains(id) ||
        !isPublicProductBrand(name) ||
        row['is_active'] != true ||
        (rowTenantId.isNotEmpty && rowTenantId != normalizedTenantId)) {
      continue;
    }
    namesById[id] = name;
  }
  return Map.unmodifiable(namesById);
}
