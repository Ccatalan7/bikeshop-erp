import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/tenant_service.dart';
import '../providers/public_store_tenant_provider.dart';

String? _normalizedIdentifier(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? choosePublicStoreTenantId({
  required String? detectedTenantId,
  required String? authenticatedTenantId,
  required bool allowAuthenticatedFallback,
}) {
  final detected = _normalizedIdentifier(detectedTenantId);
  if (detected != null) return detected;

  if (!allowAuthenticatedFallback) return null;

  return _normalizedIdentifier(authenticatedTenantId);
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

String? chooseErpMountedStoreTenantId({
  required String? authenticatedTenantId,
  required String? focusedHostScopeTenantId,
  required bool hasAuthenticatedTenantOwner,
}) {
  final authenticated = _normalizedIdentifier(authenticatedTenantId);
  if (hasAuthenticatedTenantOwner) {
    return authenticated;
  }

  return _normalizedIdentifier(focusedHostScopeTenantId);
}

abstract interface class ErpMountedStorefrontAuthoritySource
    implements Listenable {
  String? get currentUserId;
  String? get cachedTenantId;
  Future<String?> resolveTenantId();
}

/// Adapts the two authenticated ERP owners into one observable storefront
/// authority without making the public-store provider depend on Supabase auth.
class AuthenticatedErpStorefrontAuthoritySource
    implements ErpMountedStorefrontAuthoritySource {
  const AuthenticatedErpStorefrontAuthoritySource({
    required this.authService,
    required this.tenantService,
  });

  final AuthService authService;
  final TenantService tenantService;

  @override
  String? get currentUserId => authService.currentUser?.id;

  @override
  String? get cachedTenantId => tenantService.currentTenantId;

  @override
  Future<String?> resolveTenantId() => tenantService.getTenantId();

  @override
  void addListener(VoidCallback listener) {
    authService.addListener(listener);
    tenantService.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    authService.removeListener(listener);
    tenantService.removeListener(listener);
  }
}

@immutable
class ErpMountedStorefrontAuthority {
  const ErpMountedStorefrontAuthority({
    required this.userId,
    required this.tenantId,
  });

  final String userId;
  final String tenantId;
}

bool isErpMountedStorefrontAuthorityCurrent(
  ErpMountedStorefrontAuthoritySource source,
  ErpMountedStorefrontAuthority authority,
) {
  return _normalizedIdentifier(source.currentUserId) == authority.userId;
}

/// Resolves an authenticated `(user, tenant)` lease and rejects results that
/// finish after the session identity changes.
Future<ErpMountedStorefrontAuthority?> resolveErpMountedStorefrontAuthority(
  ErpMountedStorefrontAuthoritySource source,
) async {
  final userId = _normalizedIdentifier(source.currentUserId);
  if (userId == null) return null;

  final cachedTenantId = _normalizedIdentifier(source.cachedTenantId);
  final tenantId =
      cachedTenantId ?? _normalizedIdentifier(await source.resolveTenantId());

  if (tenantId == null) {
    return null;
  }

  final authority = ErpMountedStorefrontAuthority(
    userId: userId,
    tenantId: tenantId,
  );
  return isErpMountedStorefrontAuthorityCurrent(source, authority)
      ? authority
      : null;
}

/// Resolves the tenant for the storefront mounted inside the authenticated ERP.
///
/// [TenantService] is authoritative whenever it is installed. The provider
/// fallback exists only for focused widget hosts that intentionally omit the
/// authenticated owner; it is never allowed to override an empty/invalid
/// authenticated scope in production.
Future<String?> resolveErpMountedStoreTenantId(BuildContext context) async {
  TenantService tenantService;
  try {
    tenantService = context.read<TenantService>();
  } on ProviderNotFoundException {
    String? focusedHostScopeTenantId;
    try {
      focusedHostScopeTenantId =
          context.read<PublicStoreTenantProvider>().tenantId;
    } on ProviderNotFoundException {
      focusedHostScopeTenantId = null;
    }
    return chooseErpMountedStoreTenantId(
      authenticatedTenantId: null,
      focusedHostScopeTenantId: focusedHostScopeTenantId,
      hasAuthenticatedTenantOwner: false,
    );
  }

  try {
    final authService = context.read<AuthService>();
    final authority = await resolveErpMountedStorefrontAuthority(
      AuthenticatedErpStorefrontAuthoritySource(
        authService: authService,
        tenantService: tenantService,
      ),
    );
    return authority?.tenantId;
  } on ProviderNotFoundException {
    // Focused hosts may intentionally omit AuthService. TenantService remains
    // their explicit authenticated owner, matching the legacy test contract.
  }

  final cachedTenantId = tenantService.currentTenantId;
  final authenticatedTenantId = cachedTenantId?.trim().isNotEmpty == true
      ? cachedTenantId
      : await tenantService.getTenantId();

  return chooseErpMountedStoreTenantId(
    authenticatedTenantId: authenticatedTenantId,
    focusedHostScopeTenantId: null,
    hasAuthenticatedTenantOwner: true,
  );
}

/// Resolves the storefront tenant without coupling page widgets to one host.
///
/// The current public-store scope always wins. The authenticated ERP tenant is
/// only eligible in Preview/Edit or when an ERP-only owner explicitly opts in,
/// because subdomain detection is not meaningful inside the mounted shell.
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
