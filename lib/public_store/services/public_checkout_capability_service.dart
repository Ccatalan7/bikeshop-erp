import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/public_checkout_capabilities.dart';

typedef PublicCheckoutCapabilityLoader = Future<PublicCheckoutCapabilities>
    Function(String tenantId);

class PublicCheckoutCapabilityService {
  const PublicCheckoutCapabilityService();

  Future<PublicCheckoutCapabilities> load(String tenantId) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw const FormatException('No se pudo identificar la tienda.');
    }
    final response = await Supabase.instance.client.rpc(
      'get_public_checkout_capabilities',
      params: {'p_tenant_id': normalizedTenantId},
    );
    return PublicCheckoutCapabilities.fromRpc(response);
  }
}
