import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/services/tenant_service.dart';
import '../providers/public_store_tenant_provider.dart';

String? choosePublicStoreTenantId({
  required String? detectedTenantId,
  required String? authenticatedTenantId,
  required bool allowAuthenticatedFallback,
}) {
  final detected = detectedTenantId?.trim();
  if (detected != null && detected.isNotEmpty) return detected;

  if (!allowAuthenticatedFallback) return null;

  final authenticated = authenticatedTenantId?.trim();
  return authenticated == null || authenticated.isEmpty ? null : authenticated;
}

bool allowsAuthenticatedStoreTenantFallback({
  required bool explicitlyAllowed,
  required bool isEditorContext,
  required String? previewQuery,
  required String? editQuery,
}) {
  return explicitlyAllowed ||
      isEditorContext ||
      previewQuery == 'true' ||
      editQuery == 'true';
}

/// Resolves the storefront tenant without coupling page widgets to one host.
///
/// The detected public-store tenant always wins. The authenticated ERP tenant
/// is only eligible in Preview/Edit or when an ERP-only owner explicitly opts
/// in, because subdomain detection is not meaningful inside the mounted shell.
Future<String?> resolvePublicStoreTenantId(
  BuildContext context, {
  bool allowAuthenticatedFallback = false,
}) async {
  String? detectedTenantId;
  try {
    detectedTenantId = context.read<PublicStoreTenantProvider>().tenantId;
  } on ProviderNotFoundException {
    // Some focused hosts provide only the authenticated ERP tenant.
  }

  var isEditorContext = false;
  if (!allowAuthenticatedFallback) {
    try {
      isEditorContext =
          context.read<WebsiteEditModeProvider>().isInEditorContext;
    } on ProviderNotFoundException {
      isEditorContext = false;
    }
  }

  // Route query is the immediate Preview/Edit control. It can become visible
  // one frame before WebsiteEditModeProvider synchronizes after navigation.
  String? previewQuery;
  String? editQuery;
  if (!allowAuthenticatedFallback && !isEditorContext) {
    try {
      final query = GoRouterState.of(context).uri.queryParameters;
      previewQuery = query['preview'];
      editQuery = query['edit'];
    } catch (_) {
      // A focused widget host may not install GoRouter.
    }
  }

  final canUseAuthenticatedTenant = allowsAuthenticatedStoreTenantFallback(
    explicitlyAllowed: allowAuthenticatedFallback,
    isEditorContext: isEditorContext,
    previewQuery: previewQuery,
    editQuery: editQuery,
  );

  final detected = choosePublicStoreTenantId(
    detectedTenantId: detectedTenantId,
    authenticatedTenantId: null,
    allowAuthenticatedFallback: false,
  );
  if (detected != null || !canUseAuthenticatedTenant) return detected;

  try {
    final tenantService = context.read<TenantService>();
    final cachedTenantId = tenantService.currentTenantId;
    final authenticatedTenantId = cachedTenantId?.trim().isNotEmpty == true
        ? cachedTenantId
        : await tenantService.getTenantId();

    return choosePublicStoreTenantId(
      detectedTenantId: null,
      authenticatedTenantId: authenticatedTenantId,
      allowAuthenticatedFallback: true,
    );
  } on ProviderNotFoundException {
    return null;
  }
}
