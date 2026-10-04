/// Builds the tenant-safe linked-brand map shared by public product consumers.
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
        name.isEmpty ||
        row['is_active'] != true ||
        (rowTenantId.isNotEmpty && rowTenantId != normalizedTenantId)) {
      continue;
    }
    namesById[id] = name;
  }
  return Map.unmodifiable(namesById);
}
