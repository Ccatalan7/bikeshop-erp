import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/services/auth_service.dart';
import '../../shared/services/tenant_service.dart';
import '../../shared/widgets/branded_loading.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';
import '../utils/public_store_tenant_resolver.dart';
import 'public_store_bootstrap.dart' show restorePublicStoreCartForTenant;

typedef ErpMountedStorefrontTenantReady = Future<void> Function(
  String tenantId,
);

/// Installs one authenticated storefront scope before mounting any ERP-hosted
/// storefront consumer.
///
/// The boundary owns the `(user, tenant, generation)` lease for both the
/// persistent store shell and direct checkout routes. A stale async result can
/// finish, but cannot project a tenant, restore a cart, or reveal a consumer.
class ErpMountedStorefrontScopeBoundary extends StatefulWidget {
  const ErpMountedStorefrontScopeBoundary({
    super.key,
    required this.child,
    this.authService,
    this.authoritySource,
    this.onTenantReady,
    this.loading = const BrandedLoadingOverlay(),
  }) : assert(
          authService == null || authoritySource == null,
          'Provide either AuthService or an injected authority source.',
        );

  final Widget child;
  final AuthService? authService;

  @visibleForTesting
  final ErpMountedStorefrontAuthoritySource? authoritySource;

  final ErpMountedStorefrontTenantReady? onTenantReady;
  final Widget loading;

  @override
  State<ErpMountedStorefrontScopeBoundary> createState() =>
      _ErpMountedStorefrontScopeBoundaryState();
}

class _ErpMountedStorefrontScopeBoundaryState
    extends State<ErpMountedStorefrontScopeBoundary> {
  ErpMountedStorefrontAuthoritySource? _authoritySource;
  AuthService? _boundAuthService;
  TenantService? _boundTenantService;
  int _leaseGeneration = 0;
  bool _isReady = false;
  String? _readyUserId;
  String? _readyTenantId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshAuthorityBinding();
  }

  @override
  void didUpdateWidget(covariant ErpMountedStorefrontScopeBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authService, widget.authService) ||
        !identical(oldWidget.authoritySource, widget.authoritySource)) {
      _refreshAuthorityBinding();
    }
  }

  void _refreshAuthorityBinding() {
    final injected = widget.authoritySource;
    if (injected != null) {
      if (identical(_authoritySource, injected)) return;
      _bindAuthority(injected);
      _boundAuthService = null;
      _boundTenantService = null;
      return;
    }

    final authService = widget.authService ?? context.read<AuthService>();
    final tenantService = context.read<TenantService>();
    if (_authoritySource != null &&
        identical(_boundAuthService, authService) &&
        identical(_boundTenantService, tenantService)) {
      return;
    }

    _boundAuthService = authService;
    _boundTenantService = tenantService;
    _bindAuthority(
      AuthenticatedErpStorefrontAuthoritySource(
        authService: authService,
        tenantService: tenantService,
      ),
    );
  }

  void _bindAuthority(ErpMountedStorefrontAuthoritySource source) {
    _authoritySource?.removeListener(_handleAuthorityChanged);
    _authoritySource = source;
    source.addListener(_handleAuthorityChanged);

    _isReady = false;
    _readyUserId = null;
    _readyTenantId = null;
    final generation = ++_leaseGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_leaseIsCurrent(generation, source)) return;
      unawaited(_synchronize(generation, source));
    });
  }

  void _handleAuthorityChanged() {
    final source = _authoritySource;
    if (source == null || !mounted) return;

    final generation = ++_leaseGeneration;
    if (_isReady || _readyUserId != null || _readyTenantId != null) {
      setState(() {
        _isReady = false;
        _readyUserId = null;
        _readyTenantId = null;
      });
    }
    unawaited(_synchronize(generation, source));
  }

  bool _leaseIsCurrent(
    int generation,
    ErpMountedStorefrontAuthoritySource source,
  ) {
    return mounted &&
        generation == _leaseGeneration &&
        identical(source, _authoritySource);
  }

  Future<void> _synchronize(
    int generation,
    ErpMountedStorefrontAuthoritySource source,
  ) async {
    if (!_leaseIsCurrent(generation, source)) return;

    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final cartProvider = context.read<CartProvider>();
    final inventoryService = context.read<PublicInventoryService>();
    final onTenantReady = widget.onTenantReady;

    final authority = await resolveErpMountedStorefrontAuthority(source);
    if (!_leaseIsCurrent(generation, source)) return;

    if (authority == null) {
      tenantProvider.clearTenant();
      return;
    }

    tenantProvider.projectAuthenticatedTenantForStorefront(
      authority.tenantId,
    );
    if (!tenantProvider.matchesAuthenticatedTenantScope(authority.tenantId) ||
        !isErpMountedStorefrontAuthorityCurrent(source, authority)) {
      return;
    }

    try {
      await Future.wait([
        restorePublicStoreCartForTenant(
          cartProvider: cartProvider,
          inventoryService: inventoryService,
          tenantId: authority.tenantId,
        ),
        if (onTenantReady != null) onTenantReady(authority.tenantId),
      ]);
    } catch (error) {
      if (_leaseIsCurrent(generation, source)) {
        debugPrint(
          '⚠️ [ERP Store Scope] Tenant readiness failed: $error',
        );
      }
      return;
    }

    if (!_leaseIsCurrent(generation, source) ||
        !isErpMountedStorefrontAuthorityCurrent(source, authority) ||
        !tenantProvider.matchesAuthenticatedTenantScope(authority.tenantId)) {
      return;
    }

    setState(() {
      _readyUserId = authority.userId;
      _readyTenantId = authority.tenantId;
      _isReady = true;
    });
  }

  @override
  void dispose() {
    _leaseGeneration++;
    _authoritySource?.removeListener(_handleAuthorityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _authoritySource;
    if (!_isReady ||
        source == null ||
        _readyUserId == null ||
        _readyTenantId == null) {
      return widget.loading;
    }

    return widget.child;
  }
}
