import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart'
    if (dart.library.io) '../../modules/website/services/google_business_service_stub.dart'
    as web;

import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../routes/deferred_commerce_route_page.dart';
import '../routes/deferred_customer_route_page.dart';
import '../services/checkout_exit_guard.dart';
import '../services/public_category_publication.dart';
import '../services/public_page_publication.dart';
import '../services/public_inventory_service.dart';
import '../services/public_store_scroll_state.dart';
import '../theme/public_store_theme.dart';
import '../theme/public_header_contrast.dart';
import '../../shared/models/public_product_visibility_policy.dart';
import '../models/public_checkout_capabilities.dart';
import '../services/public_checkout_capability_service.dart';
import 'floating_whatsapp_button.dart';
import 'customer_account_menu.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/models/website_editor_mode_route_binding.dart';
import '../../modules/website/models/website_editor_capability.dart';
import '../../modules/website/models/website_editor_oauth_intent.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/website_link_value_editor.dart';
import '../../modules/website/widgets/website_editor_navigation_guard.dart';
import '../../modules/website/widgets/website_workspace_scope.dart';
import '../../modules/website/theme/website_theme_builder.dart';
import '../../modules/website/models/website_page_models.dart';
import '../../modules/website/models/website_destination.dart';
import '../../modules/website/models/website_catalog_presentation.dart';
import '../../modules/website/models/website_catalog_query.dart';
import '../../shared/routes/erp_routes_barrel.dart' deferred as erp
    show
        AnalyticsDashboardPage,
        FeaturedProductsPage,
        HierarchicalCategoryPage,
        IntegrationsPage,
        NavigationManagementPage,
        OnlineOrdersPage,
        PageManagementPage,
        PaymentMethodsSettingsPage,
        ProductWebsiteVisibilityPage,
        WebsiteCatalogSection,
        SeoSettingsPage,
        WebsiteDestinationManagementPage,
        WebsiteManagementPage,
        WebsiteSettingsPage;
import '../../shared/services/tenant_service.dart';
import '../../shared/services/tenant_detection_service.dart';
import '../../shared/utils/file_download_web.dart'
    if (dart.library.io) '../../shared/utils/file_download_stub.dart';
import '../../shared/utils/seo_helper.dart';
import '../services/customer_account_service.dart';
import '../utils/product_url.dart';
import '../../shared/utils/web_url.dart' show setLocationHash;
import 'customer_chat_widget.dart';
import 'search_overlay.dart';
import 'storefront_navigation_guard_scope.dart';
import '../../shared/widgets/safe_layout_builder.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'mega_menu.dart';

part 'store_layout/runtime_href.dart';
part 'store_layout/header_geometry.dart';
part 'store_layout/editor_workspace_tabs.dart';
part 'store_layout/layout_helpers.dart';
part 'store_layout/page_navigator.dart';
part 'store_layout/scroll_and_chrome.dart';

class PublicStoreLayout extends StatefulWidget {
  final Widget child;
  final bool showEditorButton;
  final bool enablePageViewScrolling;
  final String? routePath;
  final WebsiteEditorNavigationIntent? backNavigationIntent;

  /// Injection seam for the tenant-scoped checkout capability read.
  ///
  /// Production uses the canonical `PublicCheckoutCapabilityService`; tests
  /// supply a loader so the footer's payment claims can be exercised without
  /// a backend.
  final PublicCheckoutCapabilityLoader? checkoutCapabilityLoader;

  const PublicStoreLayout({
    super.key,
    required this.child,
    this.showEditorButton = true,
    this.enablePageViewScrolling = true,
    this.routePath,
    this.backNavigationIntent,
    this.checkoutCapabilityLoader,
  });

  static bool isCheckoutPath(String path) {
    final normalized = path.trim().toLowerCase();
    return normalized == '/checkout' || normalized == '/tienda/checkout';
  }

  static String? _currentRoutePath(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      try {
        return GoRouter.of(context).routeInformationProvider.value.uri.path;
      } catch (_) {
        return kIsWeb ? Uri.base.path : null;
      }
    }
  }

  static bool _isCurrentLocation(BuildContext context, String href) {
    final target = Uri.tryParse(href);
    if (target == null || target.scheme.isNotEmpty || href.startsWith('#')) {
      return false;
    }
    try {
      final current = GoRouterState.of(context).uri;
      return target.path == current.path &&
          target.queryParameters.toString() ==
              current.queryParameters.toString() &&
          target.fragment == current.fragment;
    } catch (_) {
      return false;
    }
  }

  /// Confirms a destructive exit only while the active storefront route owns
  /// a durable checkout lease. A one-shot permit is used when another action
  /// (for example sign-out) must complete before the actual navigation.
  static Future<bool> authorizeCheckoutExit(
    BuildContext context, {
    bool permitNextNavigation = false,
  }) async {
    CheckoutExitGuard guard;
    try {
      guard = context.read<CheckoutExitGuard>();
    } catch (_) {
      return true;
    }

    if (!guard.isLocked) return true;
    if (guard.consumeNavigationPermit()) return true;

    final currentPath = _currentRoutePath(context);
    if (currentPath != null && !isCheckoutPath(currentPath)) {
      return true;
    }

    return guard.requestExitAuthorization(
      (phase) async {
        if (!context.mounted) return false;
        final hasCreatedOrder = phase == CheckoutExitPhase.orderCreated;
        final isPreparingOrder = phase == CheckoutExitPhase.preparingOrder;
        return await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => AlertDialog(
                title: Text(
                  hasCreatedOrder
                      ? '¿Salir del pedido en curso?'
                      : isPreparingOrder
                          ? '¿Salir mientras preparamos tu pedido?'
                          : '¿Salir de la recuperación segura?',
                ),
                content: Text(
                  hasCreatedOrder
                      ? 'Tu pedido ya está creado y quedó guardado de forma '
                          'segura en esta pestaña. Si sales, podrás volver al '
                          'checkout para continuar el mismo pedido.'
                      : isPreparingOrder
                          ? 'Estamos guardando una recuperación segura antes '
                              'de enviar el pedido. Si sales ahora, este envío '
                              'se cancelará y podrás volver a intentarlo.'
                          : 'El intento de pedido quedó guardado de forma '
                              'segura en esta pestaña. Si sales, podrás volver '
                              'al checkout y reintentar la confirmación sin '
                              'crear otro pedido.',
                ),
                actions: [
                  TextButton(
                    key: const ValueKey('checkout-exit-cancel'),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('CANCELAR'),
                  ),
                  FilledButton(
                    key: const ValueKey('checkout-exit-confirm'),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('SALIR DEL CHECKOUT'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      permitNextNavigation: permitNextNavigation,
    );
  }

  static Future<bool> signOutCustomer(
    BuildContext context,
    CustomerAccountService accountService, {
    String destination = '/',
  }) async {
    if (!await authorizeCheckoutExit(
      context,
      permitNextNavigation: true,
    )) {
      return false;
    }
    if (!context.mounted) return false;

    try {
      await accountService.signOut();
      if (context.mounted) {
        await navigateToHref(context, destination);
      }
      return true;
    } catch (_) {
      if (context.mounted) {
        try {
          context.read<CheckoutExitGuard>().revokeNavigationPermit();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Centralized navigation entry-point for public store UI elements.
  ///
  /// Prefer this over calling `context.go(...)` directly from pages/blocks so
  /// transitions + route normalization behave consistently.
  static Future<void> navigateToHref(
    BuildContext context,
    String href, {
    bool openInNewTab = false,
  }) async {
    final state = context.findAncestorStateOfType<_PublicStoreLayoutState>();
    if (state != null) {
      await state._navigateToHref(context, href, openInNewTab: openInNewTab);
      return;
    }

    // Fallback (should be rare): best-effort navigation without normalization.
    final authored = href.trim();
    final normalized = WebsiteDestination.normalizeHref(
      authored,
      internalOrigins: kIsWeb ? <Uri>[Uri.base] : const <Uri>[],
    );
    if (normalized.isEmpty) return;
    final authoredUri = Uri.tryParse(authored);
    final authoredIsAbsoluteHttp = authoredUri != null &&
        (authoredUri.scheme == 'http' || authoredUri.scheme == 'https');
    final normalizedUri = Uri.tryParse(normalized);
    final launchesExternalWindow = authoredIsAbsoluteHttp &&
        normalizedUri != null &&
        (normalizedUri.scheme == 'http' || normalizedUri.scheme == 'https');
    final keepsCurrentPage = openInNewTab ||
        normalized.startsWith('#') ||
        _isCurrentLocation(context, normalized);
    final editorDecision = await WebsiteEditorNavigationGuard.authorize(
      context,
      intent: WebsiteEditorNavigationGuard.classifyIntent(
        openInNewTab: openInNewTab,
        launchesExternalWindow: launchesExternalWindow,
        keepsCurrentPage: keepsCurrentPage,
      ),
    );
    if (!editorDecision.isAllowed) return;
    if (!context.mounted) return;
    if (!keepsCurrentPage && !await authorizeCheckoutExit(context)) {
      return;
    }
    if (!context.mounted) return;

    if (authoredIsAbsoluteHttp && (normalized == authored || openInNewTab)) {
      if (authoredUri.host.isNotEmpty) {
        final didLaunch = await launchUrl(
          authoredUri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: openInNewTab ? '_blank' : '_self',
        );
        if (didLaunch) editorDecision.commit();
      }
      return;
    }

    if (normalized.startsWith('#')) {
      if (!editorDecision.commit()) return;
      if (kIsWeb) {
        setLocationHash(normalized);
      }
      return;
    }

    // Fallback: treat non-external links as top-level navigation.
    // Using go() avoids stacking routes on web (which can lead to blank frames
    // when a layout exception occurs in an offstage route).
    if (!editorDecision.commit()) return;
    context.go(normalized);
  }

  /// Defensive public eligibility check for CMS-authored links.
  ///
  /// Renderers should remove invalid category affordances when they can. This
  /// central boundary prevents a stale CTA from becoming a route to an
  /// unpublished collection while the editor's destination audit is repaired.
  static bool isHrefPubliclyEligible(BuildContext context, String href) {
    final state = context.findAncestorStateOfType<_PublicStoreLayoutState>();
    return state?._allowsPublicHref(href) ?? true;
  }

  /// Starts route-specific read-only warm-up when a pointer/focus indicates
  /// likely navigation. Deferred features remain outside the initial bundle.
  static void prepareHref(BuildContext context, String href) {
    final state = context.findAncestorStateOfType<_PublicStoreLayoutState>();
    state?._warmDeferredRouteForPath(
      Uri.tryParse(href.trim())?.path ?? href.trim(),
    );
  }

  /// Restores the editor session after a Google OAuth return.
  ///
  /// The OAuth return is an UNTRUSTED entry command (the reloaded page may
  /// not have an open session yet): it passes through the same single
  /// capability gate as a `?edit=true` deep link and fails closed. The FULL
  /// identity context — lease generation, identity revision, auth identity
  /// epoch, request identity and normalized tenant — is captured before the
  /// await and revalidated immediately after it, so a coalesced A→B→A auth
  /// sequence or a tenant switch during the await can never re-apply the
  /// stale identity's grant. A transient failure suspends (drafts retained)
  /// and NEVER fabricates a denial.
  @visibleForTesting
  static Future<WebsiteEditorOAuthRestoreOutcome>
      restoreEditorSessionAfterOAuth({
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String? Function() currentTenantId,
    String? expectedIssuerFingerprint,
  }) async {
    // No short-circuit before the gate: even an already-open Edit session
    // must revalidate through the capability truth.
    final wasInEditMode = editProvider.isEditMode;
    final tenantId = currentTenantId();
    // START guard: if the session's typed identity evidence (live,
    // suspended or owner lease) belongs to a DIFFERENT auth identity or
    // storefront tenant than this request, A dies BEFORE any await — B
    // never inherits A's session, and the one-shot intention is consumed.
    final sessionIdentity = editProvider.editorSessionIdentity;
    if (sessionIdentity != null &&
        (sessionIdentity.identity !=
                websiteService.editorCapabilityRequestIdentity ||
            sessionIdentity.storefrontTenantId != (tenantId?.trim() ?? ''))) {
      if (editProvider.revokeEditorEntryLease()) {
        websiteService.requestActiveCmsPageOriginRevalidation();
      }
      return WebsiteEditorOAuthRestoreOutcome.superseded;
    }
    final generation = editProvider.editorEntryLeaseGeneration;
    final identityRevision = editProvider.editorEntryLeaseIdentityRevision;
    final requestEpoch = websiteService.identityEpoch;
    final requestIdentity = websiteService.editorCapabilityRequestIdentity;
    final requestTenantNorm = tenantId?.trim() ?? '';
    WebsiteEditorCapabilitySnapshot? snapshot;
    var transientFailure = false;
    try {
      snapshot = await websiteService.resolveEditorCapability(tenantId);
    } on WebsiteEditorCapabilityUnresolvedException {
      transientFailure = true; // Classified transient: identity unresolved.
    } on WebsiteEditorAuthorityException {
      snapshot = null;
      transientFailure = false; // Durable: consumed below as denial.
    } catch (_) {
      transientFailure = true; // Transport/unavailability: transient.
    }
    if (websiteService.identityEpoch != requestEpoch ||
        websiteService.editorCapabilityRequestIdentity != requestIdentity ||
        (currentTenantId()?.trim() ?? '') != requestTenantNorm ||
        generation != editProvider.editorEntryLeaseGeneration ||
        identityRevision != editProvider.editorEntryLeaseIdentityRevision) {
      return WebsiteEditorOAuthRestoreOutcome.superseded;
    }
    if (snapshot == null && transientFailure) {
      // Classified TRANSIENT failure: hide any editor projection but
      // RETAIN drafts for this identity's retry — never adopt a fabricated
      // denial. A granted lease on a Public projection is still
      // authority-unknown and suspends too.
      if ((editProvider.isInEditorContext ||
              editProvider.editorEntryLease != null) &&
          editProvider.suspendEditorEntryLease()) {
        websiteService.requestActiveCmsPageOriginRevalidation();
      }
      return WebsiteEditorOAuthRestoreOutcome.transient;
    }
    // VALIDATE the resolved snapshot against the captured request AND the
    // issuing intent BEFORE any provider mutation: a mismatched identity,
    // storefront tenant or issuer fingerprint is superseded with ZERO
    // provider state touched.
    if (snapshot != null) {
      if (snapshot.identity != requestIdentity ||
          snapshot.storefrontTenantId != requestTenantNorm) {
        return WebsiteEditorOAuthRestoreOutcome.superseded;
      }
      if (expectedIssuerFingerprint != null &&
          snapshot.granted &&
          snapshot.fingerprint != expectedIssuerFingerprint) {
        return WebsiteEditorOAuthRestoreOutcome.superseded;
      }
    }
    var transitioned = false;
    if ((snapshot == null || !snapshot.granted) &&
        editProvider.isInEditorContext) {
      // A durable denial closes any projected session before it is
      // recorded; a different live fingerprint goes through the provider's
      // central takeover inside adopt.
      transitioned = editProvider.revokeEditorEntryLease() || transitioned;
    }
    if (snapshot != null) {
      transitioned = editProvider.adoptEditorEntryLease(
            editProvider.editorEntryLeaseGeneration,
            snapshot,
          ) ||
          transitioned;
    }
    if (transitioned) {
      // Exactly ONE CMS transition per logical outcome, never a double
      // reload.
      websiteService.requestActiveCmsPageOriginRevalidation();
    }
    if (snapshot != null &&
        snapshot.granted &&
        editProvider.editorEntryLeaseGranted) {
      if (wasInEditMode && editProvider.isEditMode) {
        return WebsiteEditorOAuthRestoreOutcome.alreadyInEdit;
      }
      editProvider.applyRouteModeCommand(WebsiteEditorMode.edit);
      return WebsiteEditorOAuthRestoreOutcome.granted;
    }
    return WebsiteEditorOAuthRestoreOutcome.denied;
  }

  @override
  State<PublicStoreLayout> createState() => _PublicStoreLayoutState();
}

/// Durable-vs-transient outcome of the OAuth editor restore: the caller
/// consumes the one-shot localStorage intention ONLY on a durable outcome
/// and opens Integrations only after a stable grant.
enum WebsiteEditorOAuthRestoreOutcome {
  granted,
  denied,
  transient,
  superseded,
  alreadyInEdit,
}

class _PublicStoreLayoutState extends State<PublicStoreLayout> {
  // --- Server-confirmed payment claims -------------------------------------
  //
  // Guarded by tenant id plus a monotonic generation, exactly like the
  // checkout loader: a late response for tenant A must never paint tenant B's
  // footer, and a superseded request must never overwrite a newer answer.
  PublicCheckoutCapabilities? _paymentCapabilities;
  String? _paymentCapabilitiesTenantId;
  String? _paymentCapabilitiesRequestedTenantId;
  int _paymentCapabilitiesGeneration = 0;

  /// Bounded retry state for a transient capability read failure.
  ///
  /// The attempt budget belongs to exactly one tenant
  /// ([_paymentCapabilitiesAttemptsTenantId]): tenant B must be able to start
  /// immediately even when tenant A just exhausted its attempts, because A's
  /// failures were never B's. The deadline is a real [Timer], not a passive
  /// gate — recovery must not depend on an unrelated rebuild happening to run
  /// the footer builder. At most [_kPaymentCapabilityMaxAttempts] requests are
  /// made per tenant: the initial one plus one retry per backoff entry.
  String? _paymentCapabilitiesAttemptsTenantId;
  int _paymentCapabilitiesAttempts = 0;
  Timer? _paymentCapabilitiesRetryTimer;
  static const int _kPaymentCapabilityMaxAttempts = 3;
  static const List<Duration> _kPaymentCapabilityBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 8),
  ];

  static const double _externalEditorPanelWidth = 380;
  static const String _actionPageEditorWorkspace = 'workspace_page_editor';
  static const String _actionEcomCatalog = 'ecom_catalog';
  static const String _actionSitePages = 'site_pages';
  static const String _actionSiteNavigation = 'site_navigation';
  static const String _actionSiteDestinations = 'site_destinations';
  static const String _actionSiteSettings = 'site_settings';
  static const String _actionSiteOpenWebsiteHub = 'site_hub';

  static const String _actionEcomOrders = 'ecom_orders';
  static const String _actionEcomGoogle = 'ecom_google';

  static const String _actionReportsAnalytics = 'reports_analytics';
  static const String _actionReportsOrders = 'reports_orders';

  static const String _actionGoogleOpenMerchantFeed = 'google_open_feed';
  static const String _actionGoogleCopyMerchantFeed = 'google_copy_feed';

  static const String _actionConfigDomain = 'config_domain';
  static const String _actionConfigPaymentMethods = 'config_payment_methods';
  static const String _actionConfigIntegrations = 'config_integrations';
  static const String _actionConfigWebsiteSettings = 'config_website_settings';

  static const String _actionStoreCopyUrl = 'store_copy_url';
  static const String _actionStoreOpenPublic = 'store_open_public';
  static const String _actionStoreOpenWebsite = 'store_open_website';

  static const String _actionPageCopyLink = 'page_copy_link';
  static const String _actionPageOpenNewTab = 'page_open_new_tab';

  bool _isConfigHubOpen = false;
  _EditorConfigHubTab _configHubTab = _EditorConfigHubTab.siteHub;
  _EditorCatalogTab _catalogTab = _EditorCatalogTab.products;
  _EditorCategoryTab _categoryTab = _EditorCategoryTab.publication;

  Future<void>? _erpLibraryFuture;

  Future<void> _ensureErpLibraryLoaded() {
    return _erpLibraryFuture ??= erp.loadLibrary();
  }

  // Screenshot capture state
  bool _isCapturingScreenshot = false;

  // Route/provider mode binding memory: the last URI consumed as a mode
  // command. A changed URI is an entry command for the FSM; an unchanged URI
  // with a provider change triggers the write-through projection instead.
  String? _modeBindingUriSignature;
  // Single in-flight async capability resolution for the ONE editor-entry
  // gate, keyed by (lease generation, storefront tenant) so an identity or
  // tenant change can never reuse — nor adopt the result of — a resolution
  // requested for a previous identity. Lease/ABA safety lives in the
  // provider (fingerprint + generation); this is request-dedup data only.
  Future<void>? _editorLeaseResolution;
  String? _editorLeaseResolutionKey;
  // Monotonic per-request nonce. The string key above only DEDUPES repeated
  // builds of the same request; it can be recycled (identity A → B → A with
  // the provider generation unchanged), so staleness is decided exclusively
  // by this serial: a completion may apply only when it is still the LATEST
  // request ever started.
  int _editorLeaseResolutionSerial = 0;
  // Identity revision that owned the previous route-command binding; a
  // change relative to it (sync OR async) consumes the pending URI command.
  int? _lastBoundLeaseIdentityRevision;
  bool _leaseRevalidationScheduled = false;

  /// Coalesces every effective lease transition produced during a build into
  /// exactly ONE post-frame emission of the central CMS revalidation signal
  /// (a ValueNotifier must never notify during build). Pages then reload
  /// according to the CURRENT provider mode/lease.
  void _scheduleLeaseRevalidationEmission(WebsiteService websiteService) {
    if (_leaseRevalidationScheduled) return;
    _leaseRevalidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _leaseRevalidationScheduled = false;
      if (!mounted) return;
      websiteService.requestActiveCmsPageOriginRevalidation();
    });
  }

  /// Validates the identity-bound editor-entry lease EVERY build — including
  /// same-mode URIs and programmatic sessions — against the single truth
  /// (`WebsiteService.editorCapabilitySync`).
  ///
  /// A fingerprint change observed through the auth lifecycle (logout, user
  /// switch, tenant switch, refreshed authority) ALWAYS revokes first —
  /// discarding the previous identity's page/sitewide/SEO drafts via the
  /// provider — before the new identity's snapshot is adopted, even when
  /// both identities are granted. A transient resolution error of the same
  /// identity only suspends (drafts retained hidden for that identity's
  /// retry). Remote role/permission edits that the identity cache has not
  /// observed are enforced by the server boundary instead: RLS blocks the
  /// reads/writes, and an editor load rejected for classified auth/RLS
  /// reasons surfaces as WebsiteEditorAuthorityException, which the CMS
  /// consumers convert into lease revocation plus a public reload (see
  /// WebsiteEditorCapabilitySnapshot's documented limit).
  void _syncEditorEntryLease(
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
    String? storefrontTenantId,
  ) {
    final sync = websiteService.editorCapabilitySync(storefrontTenantId);
    final lease = editProvider.editorEntryLease;
    if (sync != null) {
      _editorLeaseResolution = null;
      _editorLeaseResolutionKey = null;
      if (lease == null) {
        var changed = false;
        if (editProvider.isInEditorContext && !sync.granted) {
          // An editor session without authority for this identity is closed
          // and its buckets discarded before the denied lease is recorded.
          changed = editProvider.revokeEditorEntryLease() || changed;
        }
        changed = editProvider.adoptEditorEntryLease(
              editProvider.editorEntryLeaseGeneration,
              sync,
            ) ||
            changed;
        if (changed) {
          // One CMS revalidation per effective lease transition: the central
          // freshness owner reloads Dynamic/Policy through the audience that
          // provider.mode now dictates (no per-page synchronizers).
          _scheduleLeaseRevalidationEmission(websiteService);
        }
      } else if (lease.fingerprint != sync.fingerprint ||
          lease.authorityEpoch != sync.authorityEpoch) {
        // Identity OR epoch changed (a coalesced A→B→A reproduces A's
        // fingerprint but never A's epoch): revoke/close/discard FIRST,
        // then adopt — B never inherits A's mode or drafts, granted or
        // not. (The provider's central takeover in adopt is the backstop
        // for callers that skip this.)
        editProvider.revokeEditorEntryLease();
        editProvider.adoptEditorEntryLease(
          editProvider.editorEntryLeaseGeneration,
          sync,
        );
        _scheduleLeaseRevalidationEmission(websiteService);
      } else if (!sync.granted && editProvider.isInEditorContext) {
        // The warm truth DENIES this exact fingerprint while an editor
        // session is projected (a programmatic open bypassed the gate):
        // close it — zero chrome, zero draft survives a denied identity.
        editProvider.revokeEditorEntryLease();
        _scheduleLeaseRevalidationEmission(websiteService);
      }
      return;
    }
    // Cold identity caches: authority is UNKNOWN, so no editor projection
    // may stay visible during the await (typed field comparison — the
    // fingerprint string is an opaque token, never parsed).
    //  - A lease for a different auth identity or storefront tenant →
    //    REVOKE before the await: B never sees one frame of A's chrome or
    //    drafts.
    //  - A lease for the SAME identity → SUSPEND before the await:
    //    chrome/drafts hidden but retained, and a re-grant of the exact
    //    fingerprint restores them.
    //  - An editor session WITHOUT a lease: its typed document owner
    //    attributes the drafts, so it suspends for that identity; an
    //    ownerless session is not safely attributable and closes.
    final coldLease = editProvider.editorEntryLease;
    if (coldLease != null) {
      if (coldLease.identity !=
              websiteService.editorCapabilityRequestIdentity ||
          coldLease.storefrontTenantId !=
              (storefrontTenantId?.trim() ?? '')) {
        editProvider.revokeEditorEntryLease();
        _scheduleLeaseRevalidationEmission(websiteService);
      } else if (editProvider.suspendEditorEntryLease()) {
        _scheduleLeaseRevalidationEmission(websiteService);
      }
    } else if (editProvider.isInEditorContext) {
      if (editProvider.documentOwnerLeaseFingerprint != null) {
        if (editProvider.suspendEditorEntryLease()) {
          _scheduleLeaseRevalidationEmission(websiteService);
        }
      } else {
        editProvider.revokeEditorEntryLease();
        _scheduleLeaseRevalidationEmission(websiteService);
      }
    }
    // One async resolve keyed by generation + identity epoch + tenant.
    final generation = editProvider.editorEntryLeaseGeneration;
    final requestedTenant = storefrontTenantId;
    // The key binds the request to generation + auth identity + tenant: a
    // user switch with a cold cache can never adopt the previous user's
    // in-flight response for the same tenant.
    final key = '$generation|'
        '${websiteService.identityEpoch}|'
        '${websiteService.editorCapabilityRequestIdentity}|'
        '${requestedTenant ?? ''}';
    if (_editorLeaseResolutionKey == key && _editorLeaseResolution != null) {
      return;
    }
    _editorLeaseResolutionKey = key;
    final serial = ++_editorLeaseResolutionSerial;
    // Full identity context captured BEFORE the await. The completion
    // requires all of it unchanged — without waiting for another build —
    // so an identity/tenant/epoch change during the await can never adopt
    // this response, even when the string key was recycled.
    final requestEpoch = websiteService.identityEpoch;
    final requestIdentity = websiteService.editorCapabilityRequestIdentity;
    final requestTenantNorm = requestedTenant?.trim() ?? '';
    _editorLeaseResolution = () async {
      WebsiteEditorCapabilitySnapshot? snapshot;
      try {
        snapshot = await websiteService.resolveEditorCapability(
          requestedTenant,
        );
      } catch (_) {
        snapshot = null; // Transient resolver failure.
      }
      if (!mounted) return;
      // ABA-safe supersession: an equal RE-CREATED key (A → B → A) still has
      // a newer serial, so this stale completion drops itself.
      if (serial != _editorLeaseResolutionSerial) return;
      if (websiteService.identityEpoch != requestEpoch ||
          websiteService.editorCapabilityRequestIdentity !=
              requestIdentity ||
          (context.read<PublicStoreTenantProvider>().tenantId?.trim() ??
                  '') !=
              requestTenantNorm) {
        // The identity context moved during the await: drop the response
        // and let the next build issue a fresh request.
        _editorLeaseResolution = null;
        _editorLeaseResolutionKey = null;
        return;
      }
      _editorLeaseResolution = null;
      _editorLeaseResolutionKey = null;
      final provider = context.read<WebsiteEditModeProvider>();
      if (generation != provider.editorEntryLeaseGeneration) {
        return; // ABA: a revocation happened while resolving.
      }
      if (snapshot == null) {
        // Same-identity transient failure: hide, retain drafts, retry later.
        if (provider.isInEditorContext &&
            provider.suspendEditorEntryLease()) {
          websiteService.requestActiveCmsPageOriginRevalidation();
        }
        return;
      }
      // The snapshot must still describe the CURRENT identity: if the warm
      // caches now disagree, drop it and let the next build re-evaluate.
      final currentSync = websiteService.editorCapabilitySync(requestedTenant);
      if (currentSync != null &&
          (currentSync.fingerprint != snapshot.fingerprint ||
              currentSync.authorityEpoch != snapshot.authorityEpoch)) {
        return;
      }
      var changed = false;
      if (!snapshot.granted && provider.isInEditorContext) {
        changed = provider.revokeEditorEntryLease() || changed;
      }
      changed = provider.adoptEditorEntryLease(
            provider.editorEntryLeaseGeneration,
            snapshot,
          ) ||
          changed;
      if (changed) {
        websiteService.requestActiveCmsPageOriginRevalidation();
      }
    }();
  }
  PublicCategoryPublication _categoryPublication =
      PublicCategoryPublication.empty();
  PublicPagePublication _pagePublication = const PublicPagePublication(
    publishedPaths: <String>{},
    isAuthoritative: false,
  );
  List<Uri> _storefrontInternalOrigins = const <Uri>[];
  bool _isErpMountedStore() => PublicStoreRuntimeConfig.isErpMounted;

  // ------------------------------------------------------------------------
  // On-canvas inline editing: Footer navigation
  // ------------------------------------------------------------------------
  String? _activeInlineFooterNavId;
  final TextEditingController _inlineFooterNavLabelController =
      TextEditingController();
  final FocusNode _inlineFooterNavLabelFocusNode = FocusNode();

  // ------------------------------------------------------------------------
  // Debug: URL + router state (web)
  // ------------------------------------------------------------------------
  bool get _storeUrlLogsEnabled =>
      kDebugMode || const bool.fromEnvironment('STORE_PERF_LOGS');

  String? _lastLoggedUrlSignature;

  @override
  void initState() {
    super.initState();
    // Settings are loaded in main.dart after tenant detection
    // No need to load here - just watch the service

    // Check if we're returning from Google OAuth and need to restore edit mode
    if (kIsWeb) {
      _checkGoogleOAuthReturn();
    }
  }

  @override
  void dispose() {
    _paymentCapabilitiesRetryTimer?.cancel();
    _inlineFooterNavLabelController.dispose();
    _inlineFooterNavLabelFocusNode.dispose();
    super.dispose();
  }

  String _currentPublicStorePath(BuildContext context) {
    final explicitRoutePath = widget.routePath;
    if (explicitRoutePath != null && explicitRoutePath.isNotEmpty) {
      return explicitRoutePath;
    }

    final routeName = ModalRoute.of(context)?.settings.name;
    if (routeName != null && routeName.isNotEmpty) {
      final parsed = Uri.tryParse(routeName);
      if (parsed != null && parsed.path.isNotEmpty) {
        return parsed.path;
      }
      if (routeName.startsWith('/')) {
        return routeName;
      }
    }

    try {
      final path = GoRouterState.of(context).uri.path;
      if (path.isNotEmpty) {
        return path;
      }
    } catch (_) {
      // Fall through to a safe default.
    }

    return '/';
  }

  bool _isHomePagePath(String path) {
    switch (path) {
      case '/':
      case '/tienda':
      case '/tienda/':
      case '/home':
      case '/inicio':
      case '/tienda/home':
      case '/tienda/inicio':
        return true;
      default:
        return false;
    }
  }

  bool _usesInlineHeaderLayout(String path) {
    return path == '/carrito' ||
        path == '/checkout' ||
        path == '/cuenta' ||
        path.startsWith('/cuenta/') ||
        path == '/tienda/carrito' ||
        path == '/tienda/checkout' ||
        path == '/tienda/cuenta' ||
        path.startsWith('/tienda/cuenta/') ||
        path.startsWith('/pedido/') ||
        path.startsWith('/tienda/pedido/');
  }

  void _beginInlineFooterNavEdit(
    WebsiteEditModeProvider editProvider,
    WebsiteNavigation nav,
  ) {
    setState(() {
      _activeInlineFooterNavId = nav.id;
      _inlineFooterNavLabelController.text =
          editProvider.getEffectiveFooterNavItem(nav).label;
    });
    editProvider.selectBlock('footer');
    editProvider.selectFooterNavItem(nav.id);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineFooterNavLabelFocusNode.requestFocus();
      _inlineFooterNavLabelController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inlineFooterNavLabelController.text.length,
      );
    });
  }

  Future<void> _showInlineFooterNavDestinationDialog(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteNavigation nav,
  ) async {
    final effective = editProvider.getEffectiveFooterNavItem(nav);

    final initialHref = (effective.linkValue ?? '').trim();

    final pickedHref = await WebsiteLinkValueEditor.pickLink(
      context: context,
      initialValue: initialHref,
      allowInternal: true,
      allowExternal: true,
      allowAnchor: true,
      darkStyle: true,
    );

    if (!context.mounted) return;

    if (pickedHref == null) return;
    final href = pickedHref.trim();
    if (href.isEmpty) return;

    final inferredType = WebsiteDestination.navigationTypeForHref(href);

    var openInNewTab = effective.openInNewTab;
    if (inferredType == NavLinkType.external) {
      final applied = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Opciones del enlace'),
            content: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Abrir en nueva pestaña'),
              value: openInNewTab,
              onChanged: (v) => setDialogState(() => openInNewTab = v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      );

      if (applied != true) {
        // Keep the destination change, but preserve the current openInNewTab.
        openInNewTab = effective.openInNewTab;
      }
    } else {
      openInNewTab = false;
    }

    editProvider.updateFooterNavDestination(
      nav.id,
      linkType: inferredType,
      linkValue: href,
      openInNewTab: openInNewTab,
    );
  }

  /// Check localStorage for Google OAuth return flag and restore edit mode.
  ///
  /// The one-shot flags are consumed ONLY on a durable outcome (grant or
  /// denial): a transient resolution failure keeps them so the intention
  /// retries on the next load, and Integrations opens only after a stable
  /// grant.
  static WebsiteEditorOAuthIntentStore _webOAuthIntentStore() =>
      WebsiteEditorOAuthIntentStore(
        readRaw: () => web.window.localStorage
            .getItem(WebsiteEditorOAuthIntentGate.storageKey),
        writeRaw: (value) => web.window.localStorage
            .setItem(WebsiteEditorOAuthIntentGate.storageKey, value),
        removeRaw: () => web.window.localStorage
            .removeItem(WebsiteEditorOAuthIntentGate.storageKey),
      );

  void _checkGoogleOAuthReturn() {
    try {
      // Legacy loose flags are consumed unconditionally, fail-closed: ONE
      // typed intent is the only owner of the OAuth editor return.
      web.window.localStorage.removeItem('google_oauth_return_to_editor');
      web.window.localStorage.removeItem('google_oauth_return_path');
      web.window.localStorage.removeItem('google_oauth_open_integrations');
      web.window.localStorage.removeItem('google_oauth_return_issuer');

      final store = _webOAuthIntentStore();
      final rawPresent = web.window.localStorage
              .getItem(WebsiteEditorOAuthIntentGate.storageKey) !=
          null;
      if (!rawPresent) return;
      if (store.peek(nowMs: DateTime.now().millisecondsSinceEpoch) == null) {
        // A PRESENT but malformed/legacy/expired payload is consumed
        // fail-closed in THIS mount — never left behind as persistent
        // garbage under our key. `take` removes it atomically.
        store.take(nowMs: DateTime.now().millisecondsSinceEpoch);
        return;
      }
      debugPrint(
          '🔄 [PublicStoreLayout] Detected OAuth return - restoring edit mode');

      // Schedule edit mode activation after the widget tree is built.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // ONE-SHOT: take (remove) the exact nonce BEFORE any async
        // capability await — a second mount or replay finds nothing.
        final taken = _webOAuthIntentStore()
            .take(nowMs: DateTime.now().millisecondsSinceEpoch);
        if (taken == null) return;
        final intent = taken.intent;
        // FAIL CLOSED before any restore work: the issuer identity AND
        // storefront tenant must match the current context. The intent is
        // already consumed, so a mismatch simply dies here.
        final currentIdentity =
            context.read<WebsiteService>().editorCapabilityRequestIdentity;
        final currentTenant =
            context.read<PublicStoreTenantProvider>().tenantId?.trim() ?? '';
        if (intent.issuerIdentity != currentIdentity ||
            intent.issuerTenantId != currentTenant) {
          debugPrint('⛔ [PublicStoreLayout] OAuth intent issuer mismatch; '
              'consumed fail-closed');
          return;
        }
        final outcome = await PublicStoreLayout.restoreEditorSessionAfterOAuth(
          editProvider: context.read<WebsiteEditModeProvider>(),
          websiteService: context.read<WebsiteService>(),
          currentTenantId: () => mounted
              ? context.read<PublicStoreTenantProvider>().tenantId
              : null,
          expectedIssuerFingerprint: intent.issuerFingerprint,
        );
        if (!mounted) return;
        switch (outcome) {
          case WebsiteEditorOAuthRestoreOutcome.granted:
          case WebsiteEditorOAuthRestoreOutcome.alreadyInEdit:
            debugPrint('✅ [PublicStoreLayout] Edit mode restored after OAuth');
            if (intent.openIntegrations) {
              _openConfigHub(_EditorConfigHubTab.integrations);
            }
          case WebsiteEditorOAuthRestoreOutcome.denied:
          case WebsiteEditorOAuthRestoreOutcome.superseded:
            // Durable outcomes: the one-shot stays consumed.
            debugPrint('⛔ [PublicStoreLayout] OAuth return without editor '
                'capability; staying public');
          case WebsiteEditorOAuthRestoreOutcome.transient:
            // ONLY a classified transient failure restores the SAME
            // unexpired nonce — and only when no newer intent exists.
            _webOAuthIntentStore().restoreIfNonce(
              taken,
              nowMs: DateTime.now().millisecondsSinceEpoch,
            );
            debugPrint('🔁 [PublicStoreLayout] OAuth restore transient '
                'failure; keeping intent for retry');
        }
      });
    } catch (e) {
      debugPrint('⚠️ [PublicStoreLayout] Error checking OAuth return: $e');
    }
  }

  /// Capture the full page as a screenshot
  Future<void> _captureFullPageScreenshot(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) async {
    // Show loading state
    setState(() => _isCapturingScreenshot = true);

    try {
      // Wait for the layout to rebuild without scroll constraints
      await Future.delayed(const Duration(milliseconds: 100));
      // Wait for another frame to ensure painting is complete
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 50));

      final boundary = editProvider.screenshotKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('No se encontró el área de captura (RepaintBoundary)');
      }

      // Capture image at 2x resolution for crisp output
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'website-preview-$timestamp.png';

      await downloadFile(
        bytes: pngBytes,
        fileName: fileName,
        mimeType: 'image/png',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Captura descargada: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Screenshot error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al capturar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Restore normal scroll view
      if (mounted) {
        setState(() => _isCapturingScreenshot = false);
      }
    }
  }

  Widget _withCheckoutExitScope(
    BuildContext context,
    Uri currentUri,
    Widget child,
  ) {
    final routePath = widget.routePath?.trim().isNotEmpty == true
        ? widget.routePath!
        : currentUri.path;
    return StorefrontNavigationGuardScope(
      guardCheckout: PublicStoreLayout.isCheckoutPath(routePath),
      editorPopIntentResolver: widget.backNavigationIntent == null
          ? (navigator) => navigator.canPop()
              ? WebsiteEditorNavigationIntent.switchPage
              : WebsiteEditorNavigationIntent.leaveEditor
          : null,
      editorPopIntent: widget.backNavigationIntent ??
          WebsiteEditorNavigationIntent.leaveEditor,
      authorizeCheckoutExit: (
        guardContext, {
        required permitNextNavigation,
      }) =>
          PublicStoreLayout.authorizeCheckoutExit(
        guardContext,
        permitNextNavigation: permitNextNavigation,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final isLoggedIn = supabase.auth.currentUser != null;

    // Watch providers to rebuild when data changes
    final tenantProvider = context.watch<PublicStoreTenantProvider>();
    final inventoryService = context.watch<PublicInventoryService>();
    final websiteService = context.watch<WebsiteService>();
    final editProvider = context.watch<WebsiteEditModeProvider>();

    // Check if in edit/preview mode. Also respect URL query params so the UI
    // can enter editor context before provider updates.
    final routerState = GoRouterState.of(context);
    final currentUri = routerState.uri;

    // Log when the router thinks we're on a new location, and what the browser
    // address bar says. This helps diagnose cases where the URL gets rewritten
    // to the origin (path stripped) by an unexpected history.replaceState().
    if (kIsWeb && _storeUrlLogsEnabled) {
      try {
        final browserHref = web.window.location.href;
        final signature =
            '${Uri.base.toString()}|$browserHref|${routerState.uri}|${routerState.matchedLocation}';
        if (_lastLoggedUrlSignature != signature) {
          _lastLoggedUrlSignature = signature;
          debugPrint(
            '🌐 [StoreURL] base=${Uri.base} href=$browserHref '
            'routerUri=${routerState.uri} matched=${routerState.matchedLocation}',
          );
        }
      } catch (e) {
        // Ignore on non-web platforms
      }
    }
    // ======================================================================
    // MODE FSM ROUTE BINDING
    // ======================================================================
    // WebsiteEditModeProvider owns exactly one mode (public|preview|edit).
    // The URI participates only two ways, both deterministic and timer-free:
    //  1. A CHANGED URI is an input command. `?edit=true`/`?preview=true`
    //    request entering that mode (Edit wins when both flags appear), and
    //    it is honored only after the single capability gate
    //    (WebsiteService.canOpenEditorForTenant) resolves to granted —
    //    anonymous or unauthorized visitors fail closed to public. A
    //    flag-less URI is never an exit command: exits belong to the guarded
    //    close flow, so a stale historical URL cannot discard the session.
    //  2. An UNCHANGED URI with a provider-side mode change receives the
    //    write-through projection after the frame; the projection re-reads
    //    the provider so the latest revision always wins.
    // The lease is validated EVERY build — same-mode URIs and programmatic
    // sessions included — and WebsiteService relays TenantService auth
    // notifications, so an identity change (logout, user or tenant switch)
    // triggers this rebuild and revokes editor context without any other
    // interaction. Remote authority edits the caches have not observed are
    // enforced by the server: RLS blocks the reads/writes and a classified
    // auth/RLS rejection of an editor load surfaces as
    // WebsiteEditorAuthorityException → lease revocation + public reload.
    final leaseIdentityRevisionBeforeSync =
        editProvider.editorEntryLeaseIdentityRevision;
    _syncEditorEntryLease(
      editProvider,
      websiteService,
      context.read<PublicStoreTenantProvider>().tenantId,
    );
    // The URI command is OWNED by the identity revision that last bound it.
    // Any revision change since the previous binding — inside this build or
    // asynchronously between builds (async revoke, OAuth, auth event) —
    // kills the previous identity's pending command: B never inherits A's
    // intent; the command epoch is consumed and the flags canonicalize to
    // Public. A same-identity SUSPENSION bumps only the generation, so its
    // pending command stays pending and reapplies exactly once on regrant.
    final leaseIdentityRevision =
        editProvider.editorEntryLeaseIdentityRevision;
    // Both windows count: a transition DURING this very sync (covers the
    // first build of a remounted layout, where no previous binding exists)
    // and one that happened asynchronously since the last binding.
    final identityChangedThisBuild =
        leaseIdentityRevision != leaseIdentityRevisionBeforeSync ||
            (_lastBoundLeaseIdentityRevision != null &&
                leaseIdentityRevision != _lastBoundLeaseIdentityRevision);
    _lastBoundLeaseIdentityRevision = leaseIdentityRevision;
    // Command consumption is keyed by URI + lease generation (grant epoch):
    // a suspend/revoke bumps the generation, so after a re-grant the SAME
    // `?edit=true` URI counts as an unconsumed command again and re-enters
    // exactly once. While unknown/transient the command stays pending with
    // safe public content; a stable denial consumes it and canonicalizes the
    // URL, so no state leaves an edit-flagged URL with a permanently public
    // FSM.
    final uriSignature = currentUri.toString();
    final commandKey =
        '$uriSignature|${editProvider.editorEntryLeaseGeneration}';
    final modeRequest = websiteEditorModeRequestFromUri(currentUri);
    if (identityChangedThisBuild &&
        modeRequest != WebsiteEditorMode.public) {
      _modeBindingUriSignature = commandKey;
      if (kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final latestUri = GoRouterState.of(context).uri;
          final cleaned = projectWebsiteEditorModeOntoUri(
            latestUri,
            WebsiteEditorMode.public,
          );
          if (cleaned.toString() == latestUri.toString()) return;
          context.go(_routeForPublicStore(cleaned.toString()));
        });
      }
    } else if (modeRequest == WebsiteEditorMode.public ||
        modeRequest == editProvider.mode) {
      // No pending entry command: consume the URI so a stale flag cannot
      // reapply later, then let the write-through branch below reconcile.
      _modeBindingUriSignature = commandKey;
    } else if (editProvider.editorEntryLeaseGranted) {
      if (_modeBindingUriSignature != commandKey) {
        _modeBindingUriSignature = commandKey;
        editProvider.applyRouteModeCommand(modeRequest);
      }
    } else if (editProvider.editorEntryLeaseDenied) {
      // Resolved denial: consume the command and canonicalize the URL by
      // stripping the mode flags, so no ambiguous pending command survives.
      _modeBindingUriSignature = commandKey;
      if (kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final latestUri = GoRouterState.of(context).uri;
          final provider = context.read<WebsiteEditModeProvider>();
          if (provider.editorEntryLeaseGranted) return;
          final cleaned = projectWebsiteEditorModeOntoUri(
            latestUri,
            WebsiteEditorMode.public,
          );
          if (cleaned.toString() == latestUri.toString()) return;
          context.go(_routeForPublicStore(cleaned.toString()));
        });
      }
    }
    // else: resolution in flight — fail closed this frame; the unconsumed
    // command retries the SAME URI exactly once when the lease grants.
    if (_modeBindingUriSignature == commandKey &&
        kIsWeb &&
        editProvider.isInEditorContext &&
        !uriProjectsWebsiteEditorMode(currentUri, editProvider.mode)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final latestUri = GoRouterState.of(context).uri;
        final latestMode = context.read<WebsiteEditModeProvider>().mode;
        if (uriProjectsWebsiteEditorMode(latestUri, latestMode)) return;
        final projected =
            projectWebsiteEditorModeOntoUri(latestUri, latestMode);
        context.go(_routeForPublicStore(projected.toString()));
      });
    }

    final isEditMode = editProvider.isEditMode;
    final isPreviewMode = editProvider.isPreviewMode;
    final devicePreviewMode = editProvider.devicePreviewMode;
    final isInEditorContext = editProvider.isInEditorContext;

    // ======================================================================
    // PAGE CONTENT TRANSITION (WEB)
    // ======================================================================
    // go_router page transitions can be visually imperceptible here because the
    // header/layout is nearly identical between routes (only body changes).
    // This AnimatedSwitcher makes route changes obvious while keeping header
    // stable. It is disabled for editor/preview modes.
    final mq = MediaQuery.maybeOf(context);
    final reduceMotion =
        (mq?.disableAnimations ?? false) || (mq?.accessibleNavigation ?? false);
    final isSmallScreen = (mq?.size.shortestSide ?? 9999) < 600;

    Widget animateBody(Widget child, {bool expand = false}) {
      // Disable the content switcher on small screens (mobile). On mobile web
      // the animation is often dropped/janky and can feel worse than instant.
      // Also disable on web entirely due to blank screen issues during transitions
      // where the FadeTransition opacity gets stuck at 0 until a resize forces
      // a repaint. This is a known Flutter web rendering issue.
      if (reduceMotion ||
          isSmallScreen ||
          isInEditorContext ||
          isEditMode ||
          isPreviewMode ||
          kIsWeb ||
          // The ERP child is one persistent StatefulNavigationShell. An
          // AnimatedSwitcher would retain the outgoing URI subtree while
          // mounting that same shell for the incoming URI, duplicating every
          // branch Navigator GlobalKey.
          _isErpMountedStore()) {
        return expand ? SizedBox.expand(child: child) : child;
      }

      final uri = GoRouterState.of(context).uri.toString();
      final keyedChild = KeyedSubtree(
        key: ValueKey<String>('store_body_$uri'),
        child: expand ? SizedBox.expand(child: child) : child,
      );

      return AnimatedSwitcher(
        // Intentionally long and obvious for UX verification.
        duration: isSmallScreen
            ? const Duration(milliseconds: 700)
            : const Duration(milliseconds: 460),
        reverseDuration: isSmallScreen
            ? const Duration(milliseconds: 650)
            : const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          // Keep the top of pages aligned so the movement reads clearly.
          // Use StackFit.passthrough to ensure children get proper constraints.
          // This fixes blank screen issues on web where the Stack would have
          // zero height during transitions.
          return Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.topCenter,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          // More obvious on mobile: fade + slide + slight scale.
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          final beginDy = isSmallScreen ? 0.06 : 0.035;
          final beginScale = isSmallScreen ? 0.97 : 0.985;

          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, beginDy),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale:
                    Tween<double>(begin: beginScale, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
        child: keyedChild,
      );
    }

    // Don't block rendering - just use defaults until settings load
    // This makes the site feel faster

    final storeName = websiteService
        .getSetting(
          'seo_business_name',
          websiteService.getSetting('store_name', 'Tienda'),
        )
        .trim();
    final storeDescription =
        websiteService.getSetting('store_description', '').trim();
    final logoUrl = websiteService.getSetting('logo_url', '');
    final topBannerText = websiteService
        .getSetting('top_banner_text', 'Envíos a Chile continental')
        .trim();

    // Footer info - use provider for live preview when in editor context
    final contactEmail = (isInEditorContext
            ? editProvider.getEffectiveFooterSetting(
                'contact_email',
                websiteService.getSetting('contact_email', ''),
              )
            : websiteService.getSetting('contact_email', ''))
        .trim();
    final contactPhone = (isInEditorContext
            ? editProvider.getEffectiveFooterSetting(
                'contact_phone',
                websiteService.getSetting('contact_phone', ''),
              )
            : websiteService.getSetting('contact_phone', ''))
        .trim();
    final contactAddress = (isInEditorContext
            ? editProvider.getEffectiveFooterSetting(
                'contact_address',
                websiteService.getSetting('contact_address', ''),
              )
            : websiteService.getSetting('contact_address', ''))
        .trim();

    final facebookHandle = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'facebook',
            websiteService.getSetting(
                'facebook', websiteService.getSetting('facebook_handle', '')),
          )
        : websiteService.getSetting(
            'facebook', websiteService.getSetting('facebook_handle', ''));
    final instagramHandle = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'instagram',
            websiteService.getSetting(
                'instagram', websiteService.getSetting('instagram_handle', '')),
          )
        : websiteService.getSetting(
            'instagram', websiteService.getSetting('instagram_handle', ''));
    final twitterHandle = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'twitter',
            websiteService.getSetting(
                'twitter', websiteService.getSetting('twitter_handle', '')),
          )
        : websiteService.getSetting(
            'twitter', websiteService.getSetting('twitter_handle', ''));
    // No tenant's real channel may be another tenant's default. An unset
    // network is omitted, not substituted.
    final youtubeHandle = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'youtube',
            websiteService.getSetting(
                'youtube', websiteService.getSetting('youtube_handle', '')),
          )
        : websiteService.getSetting(
            'youtube', websiteService.getSetting('youtube_handle', ''));

    final whatsappRaw = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'whatsapp',
            websiteService.getSetting('whatsapp', ''),
          )
        : websiteService.getSetting('whatsapp', '');
    final whatsappNumber = _sanitizePhone(whatsappRaw);
    final hasWhatsApp = whatsappNumber.isNotEmpty;

    // Site publish flag (stored in website_settings)
    final sitePublished =
        websiteService.getSetting('site_published', 'true') == 'true';

    // Theme colors - use provider for live preview when in editor context
    final primaryColor = _resolveColor(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting('theme_primary_color',
              websiteService.getSetting('theme_primary_color', ''))
          : websiteService.getSetting('theme_primary_color', ''),
      PublicStoreTheme.primaryBlue,
    );
    final accentColor = _resolveColor(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting('theme_accent_color',
              websiteService.getSetting('theme_accent_color', ''))
          : websiteService.getSetting('theme_accent_color', ''),
      PublicStoreTheme.accentGreen,
    );
    final backgroundColor = _resolveColor(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting(
              'theme_background_color',
              websiteService.getSetting('theme_background_color', ''),
            )
          : websiteService.getSetting('theme_background_color', ''),
      Colors.white,
    );

    // Global typography (fonts + base sizes)
    final headingFont = isInEditorContext
        ? editProvider.getEffectiveThemeSetting(
            'theme_heading_font',
            websiteService.getSetting('theme_heading_font', ''),
          )
        : websiteService.getSetting('theme_heading_font', '');
    final bodyFont = isInEditorContext
        ? editProvider.getEffectiveThemeSetting(
            'theme_body_font',
            websiteService.getSetting('theme_body_font', ''),
          )
        : websiteService.getSetting('theme_body_font', '');

    final headingSize = double.tryParse(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting(
              'theme_heading_size',
              websiteService.getSetting('theme_heading_size', ''),
            )
          : websiteService.getSetting('theme_heading_size', ''),
    );
    final bodySize = double.tryParse(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting(
              'theme_body_size',
              websiteService.getSetting('theme_body_size', ''),
            )
          : websiteService.getSetting('theme_body_size', ''),
    );
    String getThemeSetting(String key, String fallback) {
      return isInEditorContext
          ? editProvider.getEffectiveThemeSetting(
              key,
              websiteService.getSetting(key, fallback),
            )
          : websiteService.getSetting(key, fallback);
    }

    final commerceAccentColor = _resolveColor(
      getThemeSetting('theme_product_detail_accent_color', '#123F68'),
      const Color(0xFF123F68),
    );
    final commerceTextColor = _resolveColor(
      getThemeSetting('theme_product_detail_text_color', '#1E293B'),
      const Color(0xFF1E293B),
    );
    final commerceLineColor = _resolveColor(
      getThemeSetting('theme_product_detail_line_color', '#E8E2D8'),
      const Color(0xFFE8E2D8),
    );

    final websiteTheme = WebsiteThemeBuilder.build(
      base: Theme.of(context),
      primaryColor: primaryColor,
      accentColor: accentColor,
      backgroundColor: backgroundColor,
      headingFont: headingFont,
      bodyFont: bodyFont,
      headingSize: headingSize,
      bodySize: bodySize,
      buttonStyle: getThemeSetting('button_style', 'rounded'),
      buttonSize: getThemeSetting('button_size', 'medium'),
      commerceAccentColor: commerceAccentColor,
      commerceTextColor: commerceTextColor,
      commerceLineColor: commerceLineColor,
    );

    // Header settings (DJI-style customization)
    // Header settings (DJI-style customization)
    // In edit mode, prefer pending settings for real-time preview
    String getHeaderSetting(String key, String def) {
      if (isInEditorContext) {
        return editProvider.pendingHeaderSettings[key] ??
            websiteService.getSetting(key, def);
      }
      return websiteService.getSetting(key, def);
    }

    final headerStyle = getHeaderSetting('header_style', 'solid');
    final headerColorMode = getHeaderSetting('header_color_mode', 'auto');
    final headerNavigationUppercase =
        getHeaderSetting('header_navigation_uppercase', 'true') == 'true';
    final showTopBannerRaw =
        getHeaderSetting('header_show_top_banner', 'false');
    final showTopBanner = showTopBannerRaw == 'true';
    final headerShadow = getHeaderSetting('header_shadow', 'true') == 'true';
    final headerBgColor = _resolveColor(
      getHeaderSetting('header_bg_color', ''),
      Colors.white,
    );
    final headerMenuSurfaceColor = _resolveColor(
      getHeaderSetting('header_menu_surface_color', '#000000'),
      Colors.black,
    );
    final headerMenuRailColor = _resolveColor(
      getHeaderSetting('header_menu_rail_color', '#64748B'),
      PublicStoreTheme.secondaryGray,
    );

    // Navigation (single source of truth): website_navigation table.
    // Public store loads it via WebsiteService.loadNavigationForTenant().
    final authoredNavItems =
        websiteService.headerNavigation.where((n) => n.isVisible).toList();
    final navigationCategorySnapshot = tenantProvider.tenantId == null
        ? null
        : inventoryService.cachedCategoriesForTenant(
            tenantId: tenantProvider.tenantId!,
          );
    final storefrontInternalOrigins = _resolveStorefrontInternalOrigins(
      websiteService,
      tenantProvider,
    );
    final categoryPublication = navigationCategorySnapshot == null
        ? PublicCategoryPublication.empty()
        : PublicCategoryPublication.resolve(
            categories: [
              for (final category in navigationCategorySnapshot.categories)
                if (category.id != null)
                  PublicCategoryDescriptor(
                    id: category.id!,
                    name: category.name,
                    fullPath: category.fullPath,
                    showOnWebsite: category.showOnWebsite,
                  ),
            ],
            navigation: websiteService.navigation,
            presentationRegistry: websiteService.catalogPresentationRegistry,
            internalOrigins: storefrontInternalOrigins,
          );
    _categoryPublication = categoryPublication;
    _storefrontInternalOrigins = storefrontInternalOrigins;
    final pagePublication = PublicPagePublication.resolve(
      pages: websiteService.pages,
      isAuthoritative: tenantProvider.tenantId != null &&
          websiteService.hasAuthoritativePagePublicationForTenant(
            tenantProvider.tenantId!,
          ),
      internalOrigins: storefrontInternalOrigins,
    );
    _pagePublication = pagePublication;
    final navItems = pagePublication.forAllAudiences(authoredNavItems);
    final categoryNavigationProjection = PublicCategoryNavigationProjection(
      categoryPublication,
      internalOrigins: storefrontInternalOrigins,
    );

    // If the site is unpublished, show a holding page to visitors. The FSM
    // route command already ran in this build, so a `?preview=true` or
    // `?edit=true` entry is reflected by the provider mode here.
    final bypassUnpublished = isInEditorContext;
    if (!sitePublished && !bypassUnpublished) {
      return Theme(
        data: websiteTheme,
        child: _buildUnpublishedSiteScaffold(context, storeName),
      );
    }

    // Build footer (reused in all layouts)
    final footerWidget = _buildFooter(
      context: context,
      storeName: storeName,
      storeDescription: storeDescription,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      contactAddress: contactAddress,
      facebookHandle: facebookHandle,
      instagramHandle: instagramHandle,
      twitterHandle: twitterHandle,
      youtubeHandle: youtubeHandle,
      whatsappHandle: whatsappRaw,
      primaryColor: primaryColor,
      accentColor: accentColor,
      isEditMode: isEditMode,
      logoUrl: logoUrl, // Pass logoUrl
      categoryNavigationProjection: categoryNavigationProjection,
    );

    // Build header widget builder for special layouts
    Widget buildHeaderWidget(
        {bool isOverlay = false,
        Color? overrideBgColor,
        String? overrideColorMode,
        bool? overrideShowBanner,
        bool? overrideShadow}) {
      return _buildHeader(
        context: context,
        storeName: storeName,
        storeDescription: storeDescription,
        logoUrl: logoUrl,
        topBannerText: topBannerText,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        primaryColor: primaryColor,
        accentColor: accentColor,
        isEditMode: isEditMode,
        headerStyle: headerStyle,
        headerColorMode: overrideColorMode ?? headerColorMode,
        showTopBanner: overrideShowBanner ?? showTopBanner,
        headerShadow: overrideShadow ?? headerShadow,
        headerBgColor: overrideBgColor ?? headerBgColor,
        // The closed header keeps its configured normal/overlay appearance.
        // Opening navigation consumes its own editor-owned surfaces.
        menuSurfaceColor: headerMenuSurfaceColor,
        menuRailColor: headerMenuRailColor,
        navigationUppercase: headerNavigationUppercase,
        navItems: navItems,
        categoryNavigationProjection: categoryNavigationProjection,
        isOverlay: isOverlay,
      );
    }

    // Build the main page content based on header style
    Widget pageContent;

    // Use the page route name first because the raw GoRouter state inside this
    // shared shell can resolve to the outer location and misclassify inner
    // pages like /checkout or /pedido/:id as the homepage.
    final currentRoute = _currentPublicStorePath(context);
    final isHomePage = _isHomePagePath(currentRoute);
    final allowsOverlayHeader = isHomePage;
    final usesInlineHeaderLayout =
        widget.enablePageViewScrolling && _usesInlineHeaderLayout(currentRoute);

    if (headerStyle == 'transparent' &&
        allowsOverlayHeader &&
        widget.enablePageViewScrolling) {
      // TRANSPARENT: Header floats over hero ONLY ON HOMEPAGE
      pageContent = ScrollConfiguration(
        behavior: isEditMode
            ? const _NoDragScrollBehavior()
            : const MaterialScrollBehavior(),
        child: _PublicStoreScrollView(
          // The routed StatefulNavigationShell below owns branch Navigators
          // with GlobalKeys. Keep every ancestor identity stable while the CMS
          // switches Edit/Preview so Flutter updates that shell in place.
          key: const ValueKey('scroll_transparent_home'),
          // On Web, clip layers can end up painting above later Stack children
          // (like the header) due to DOM stacking context quirks.
          clipBehavior:
              (_isCapturingScreenshot || kIsWeb) ? Clip.none : Clip.hardEdge,
          physics: _isCapturingScreenshot
              ? const NeverScrollableScrollPhysics()
              : null,
          child: RepaintBoundary(
            key: editProvider.screenshotKey,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Content starts from top (behind header)
                Column(
                  children: [
                    animateBody(widget.child),
                    footerWidget,
                  ],
                ),
                // Header floats on top (positioned at top, scrolls with content)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: buildHeaderWidget(
                    isOverlay: true,
                    overrideBgColor: Colors.transparent,
                    overrideColorMode:
                        headerColorMode, // Use configured color mode (dark = white text)
                    overrideShadow: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (headerStyle == 'transparent' &&
        !isHomePage &&
        widget.enablePageViewScrolling) {
      // TRANSPARENT style but NOT homepage: Use solid header instead
      pageContent = usesInlineHeaderLayout
          ? ScrollConfiguration(
              behavior: isEditMode
                  ? const _NoDragScrollBehavior()
                  : const MaterialScrollBehavior(),
              child: _PublicStoreScrollView(
                key: const ValueKey('scroll_transparent_inline'),
                child: Column(
                  children: [
                    buildHeaderWidget(
                      isOverlay: false,
                      overrideBgColor: headerBgColor,
                      overrideColorMode: headerColorMode,
                      overrideShowBanner: false,
                      overrideShadow: headerShadow,
                    ),
                    animateBody(widget.child),
                    footerWidget,
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Header - static at top with solid background
                buildHeaderWidget(
                  isOverlay: false,
                  overrideBgColor: headerBgColor,
                  overrideColorMode: headerColorMode,
                  overrideShadow: headerShadow,
                ),
                // Main content area - scrollable
                Expanded(
                  child: ScrollConfiguration(
                    behavior: isEditMode
                        ? const _NoDragScrollBehavior()
                        : const MaterialScrollBehavior(),
                    child: _PublicStoreScrollView(
                      key: const ValueKey('scroll_transparent_notHome'),
                      child: Column(
                        children: [
                          animateBody(widget.child),
                          footerWidget,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
    } else if (headerStyle == 'sticky' &&
        (widget.enablePageViewScrolling || isPreviewMode || isEditMode)) {
      // STICKY: Homepage may overlay the hero; inner routes reserve header
      // height so the fixed header stays visible without covering content.
      final stickyAllowsOverlay = allowsOverlayHeader;
      pageContent = _buildStickyHeaderLayout(
        context: context,
        storeName: storeName,
        storeDescription: storeDescription,
        logoUrl: logoUrl,
        topBannerText: topBannerText,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        primaryColor: primaryColor,
        accentColor: accentColor,
        headerColorMode: headerColorMode,
        showTopBanner: stickyAllowsOverlay ? showTopBanner : false,
        headerShadow: headerShadow,
        headerBgColor: headerBgColor,
        headerMenuSurfaceColor: headerMenuSurfaceColor,
        headerMenuRailColor: headerMenuRailColor,
        navItems: navItems,
        categoryNavigationProjection: categoryNavigationProjection,
        isEditMode: isEditMode,
        child: animateBody(widget.child),
        footer: footerWidget,
        allowOverlayAtTop: stickyAllowsOverlay,
      );
    } else {
      // SOLID: Normal layout, header at top, content scrolls below
      pageContent = usesInlineHeaderLayout
          ? ScrollConfiguration(
              behavior: isEditMode
                  ? const _NoDragScrollBehavior()
                  : const MaterialScrollBehavior(),
              child: _PublicStoreScrollView(
                key: const ValueKey('scroll_solid_inline'),
                child: Column(
                  children: [
                    buildHeaderWidget(overrideShowBanner: false),
                    animateBody(widget.child),
                    footerWidget,
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Header - static at top
                buildHeaderWidget(),
                // Main content area - scrollable or fixed
                Expanded(
                  child: widget.enablePageViewScrolling
                      ? ScrollConfiguration(
                          behavior: isEditMode
                              ? const _NoDragScrollBehavior()
                              : const MaterialScrollBehavior(),
                          child: _PublicStoreScrollView(
                            key: const ValueKey('scroll_solid'),
                            child: Column(
                              children: [
                                animateBody(widget.child),
                                footerWidget,
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                                child: animateBody(widget.child, expand: true)),
                            // In fixed mode, footer is not shown or is part of child.
                            // Let's hide footer for fixed layout to gain max space.
                          ],
                        ),
                ),
              ],
            );
    }

    // ========================================================================
    // SEO BACKGROUND UPDATE
    // ========================================================================
    // Automatically update browser title and meta tags based on current page
    if (kIsWeb && !isEditMode) {
      final seoUri = resolvePublicStoreSeoUri(
        routerUri: currentUri,
        routePath: currentRoute,
      );
      final currentPath = seoUri.path;

      // Catalog collections, product detail, and CMS-owned pages manage SEO
      // only after their canonical owner and eligibility have loaded. This
      // also covers the `/tienda/...` ERP mount without letting the generic
      // page updater overwrite their metadata.
      if (isCatalogSeoManagedPath(currentPath) ||
          isProductDetailSeoManagedPath(currentPath) ||
          isStaticPolicySeoManagedPath(currentPath) ||
          isDynamicWebsitePageSeoManagedPath(currentPath)) {
        // Skip the generic page SEO updater.
      } else {
        String normalizedSlug = currentPath;
        if (normalizedSlug.startsWith('/tienda/')) {
          normalizedSlug = normalizedSlug.substring(8);
        } else if (normalizedSlug.startsWith('/tienda')) {
          normalizedSlug = 'home';
        }
        if (normalizedSlug.startsWith('/')) {
          normalizedSlug = normalizedSlug.substring(1);
        }
        if (normalizedSlug.isEmpty) normalizedSlug = 'home';

        // Handle legacy route specific cases
        if (currentPath == '/') normalizedSlug = 'home';

        WebsitePage? currentPage;
        try {
          // Try to find matching page
          if (websiteService.pages.isNotEmpty) {
            currentPage = websiteService.pages.firstWhere(
              (p) =>
                  p.slug == normalizedSlug ||
                  (p.isHome && normalizedSlug == 'home'),
              orElse: () => websiteService.pages.firstWhere((p) => p.isHome,
                  orElse: () => websiteService.pages.first),
            );
          }
        } catch (_) {
          // Page not found or list empty
        }

        String seoTitle = resolvePublicStoreSystemSeoTitle(
          path: currentPath,
          storeName: storeName,
        );
        final globalSeoTitle = [
          websiteService.getSetting('seo_meta_title', '').trim(),
          websiteService.getSetting('meta_title', '').trim(),
        ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
        final globalSeoDescription = [
          websiteService.getSetting('seo_meta_description', '').trim(),
          websiteService.getSetting('meta_description', '').trim(),
          storeDescription.trim(),
        ].firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => storeName.isEmpty
              ? 'Información pública de la tienda.'
              : 'Información pública de $storeName.',
        );
        final globalSeoKeywords = [
          websiteService.getSetting('seo_meta_keywords', '').trim(),
          websiteService.getSetting('meta_keywords', '').trim(),
        ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
        final globalSeoImage = [
          websiteService.getSetting('seo_og_image', '').trim(),
          logoUrl.trim(),
        ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
        if (normalizeStorefrontSeoPath(currentPath) == '/' &&
            globalSeoTitle.isNotEmpty) {
          seoTitle = globalSeoTitle;
        }
        String? seoDesc = globalSeoDescription;
        String? seoKeywords =
            globalSeoKeywords.isEmpty ? null : globalSeoKeywords;
        String? seoImage = globalSeoImage.isEmpty ? null : globalSeoImage;

        if (currentPage != null) {
          // Only use page-specific SEO if we matched the correct page
          bool isCorrectPage = currentPage.slug == normalizedSlug ||
              (currentPage.isHome && normalizedSlug == 'home');

          if (isCorrectPage) {
            if (currentPage.metaTitle?.isNotEmpty == true) {
              seoTitle = currentPage.metaTitle!;
            } else if (currentPage.title.isNotEmpty) {
              seoTitle = '${currentPage.title} | $storeName';
            }

            if (currentPage.metaDescription?.isNotEmpty == true) {
              seoDesc = currentPage.metaDescription;
            }

            if (currentPage.metaKeywords?.isNotEmpty == true) {
              seoKeywords = currentPage.metaKeywords;
            }

            if (currentPage.ogImageUrl?.isNotEmpty == true) {
              seoImage = currentPage.ogImageUrl;
            }
          }
        }

        // A clean route owned by a `website_pages` row may only be indexed
        // while that owner is published. Without this the generic branch used
        // the `ownerIsPublished: true` default, so a draft `/contacto` stayed
        // `index,follow` at runtime even though the static generator had
        // already excluded it from the sitemap and written no snapshot.
        final seoOwnerPath = normalizeStorefrontSeoPath(seoUri.path);
        final seoOwnerIsPublished =
            !PublicPagePublication.managedCleanPaths.contains(seoOwnerPath) ||
                _pagePublication.allowsHref(seoOwnerPath);
        final seoRoute = projectStorefrontSeoRoute(
          seoUri,
          isErpMounted: _isErpMountedStore(),
          ownerIsPublished: seoOwnerIsPublished,
        );
        final publicStoreUrl = _resolvePublicStoreUrl(websiteService);
        final publicStoreUri = publicStoreUrl == null
            ? null
            : Uri.tryParse(publicStoreUrl.endsWith('/')
                ? publicStoreUrl
                : '$publicStoreUrl/');
        final canonicalUrl = publicStoreUri
            ?.resolve(seoRoute.canonicalPath)
            .replace(query: null, fragment: null)
            .toString();

        // Defer SEO update to avoid build-phase conflicts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            SeoHelper.updateSeo(
              title: seoTitle,
              description: seoDesc,
              imageUrl: seoImage,
              keywords: seoKeywords,
              canonicalUrl: canonicalUrl,
              robots: seoRoute.robots,
            );
          }
        });
      }
    }

    // When the editor panel is rendered externally (PersistentEditorShell),
    // reserve horizontal space so the website (including header) is never
    // hidden behind the panel. Keep the top command bar full-width.
    // NOTE: Only apply this padding in DESKTOP preview mode. In mobile/tablet
    // preview, the content is already inside a constrained frame.
    if (isEditMode && devicePreviewMode == DevicePreviewMode.desktop) {
      pageContent = Padding(
        padding: const EdgeInsets.only(right: _externalEditorPanelWidth),
        child: pageContent,
      );
    }

    // ONE storefront shell Scaffold for ALL modes (public|preview|edit):
    // the FSM rebuilds its body in place, so Public↔Edit↔Preview
    // transitions never remount the shell and routed consumer State
    // (scroll positions, kept-alive pages) survives every mode change.
    // ONE routed content anchor for ALL modes and device previews: the
    // SAME type/key chain hosts pageContent in public|preview|edit, so mode
    // toggles and device-frame changes rebuild in place (properties and
    // constraints only) and routed State — scroll, forms, filters, carts —
    // survives. Chrome (top bar, config hub, chat, FABs) are SIBLINGS,
    // never new parents of the content subtree.
    final contentAnchor = KeyedSubtree(
      key: const ValueKey('storefront_content_anchor'),
      child: _buildStorefrontContentViewport(
        context,
        pageContent,
        framed:
            isInEditorContext && devicePreviewMode != DevicePreviewMode.desktop,
        isEditMode: isEditMode,
        devicePreviewMode: devicePreviewMode,
      ),
    );
    Widget shellBody;
    if (isInEditorContext) {
      Widget overlayLayer = _buildConfigHubOverlay();
      if (isEditMode &&
          devicePreviewMode == DevicePreviewMode.desktop &&
          !_isConfigHubOpen) {
        overlayLayer = Padding(
          padding: const EdgeInsets.only(right: _externalEditorPanelWidth),
          child: overlayLayer,
        );
      }
      // The editor panel has one owner: PersistentEditorShell. Keeping an
      // inline fallback here previously reintroduced a second save
      // orchestrator and could switch to Preview even after a failed save.
      shellBody = Stack(
        children: [
          Positioned.fill(top: 48, child: contentAnchor),
          if (_isConfigHubOpen)
            Positioned.fill(top: 48, child: overlayLayer),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 48,
            child: _buildPreviewTopBar(
                context, editProvider, websiteService, storeName),
          ),
        ],
      );
    } else {
      shellBody = Stack(
        children: [
          Positioned.fill(child: contentAnchor),
          // Internal Chat System (replaces WhatsApp for richer interaction)
          const CustomerChatWidget(),
          if (hasWhatsApp &&
              1 ==
                  0) // Disable WhatsApp button in favor of new chat (or make it configurable)
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingWhatsAppButton(
                phoneNumber: whatsappNumber,
                message:
                    'Hola! Me gustaría consultar sobre ${storeName.isNotEmpty ? storeName : 'sus productos'}.',
                backgroundColor: accentColor,
              ),
            ),
          // Show the legacy "Edit Site" FAB only when the store is mounted
          // inside the ERP shell. Standalone store debug on localhost should
          // behave like the public storefront and never expose this old entry.
          // Visibility is gated on the GRANTED entry lease — being logged in
          // is not authority, and a programmatic open must never bypass the
          // capability gate.
          if (isLoggedIn && widget.showEditorButton && _isErpMountedStore())
            Positioned(
              bottom: 24,
              right: hasWhatsApp ? 104 : 24,
              child: Builder(
                builder: (context) {
                  final editProvider = context.watch<WebsiteEditModeProvider>();
                  final isInEditorContext = editProvider.isInEditorContext;
                  final websiteService = context.read<WebsiteService>();

                  if (isInEditorContext) return const SizedBox.shrink();
                  if (!editProvider.editorEntryLeaseGranted) {
                    return const SizedBox.shrink();
                  }

                  return FloatingActionButton.extended(
                    heroTag: 'edit_site_fab',
                    onPressed: () {
                      debugPrint(
                          '🎨 [Layout] Edit button pressed. Entering preview mode');
                      final blocks = List<Map<String, dynamic>>.from(
                          websiteService.blocks);
                      final settings =
                          Map<String, dynamic>.from(websiteService.settings);
                      debugPrint(
                          '🎨 [Layout] Entering preview mode with ${blocks.length} blocks');
                      editProvider.openEditorDocument(
                        blocks,
                        settings,
                        mode: WebsiteEditorMode.preview,
                      );
                    },
                    backgroundColor: accentColor,
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: const Text(
                      'Editar Sitio',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    tooltip: 'Editar sitio web',
                  );
                },
              ),
            ),
        ],
      );
    }

    return _withCheckoutExitScope(
      context,
      currentUri,
      WebsiteWorkspaceScope(
        onOpen: _openWorkspacePanel,
        child: Theme(
          data: websiteTheme,
          child: Scaffold(
            key: const ValueKey('storefront_shell_scaffold'),
            backgroundColor: backgroundColor,
            body: shellBody,
          ),
        ),
      ),
    );
  }

  /// Build the preview top bar (Odoo-style) with "Editar" button
  Widget _buildPreviewTopBar(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
    String storeName,
  ) {
    final isEditMode = editProvider.isEditMode;
    final sitePublished =
        websiteService.getSetting('site_published', 'true') == 'true';
    return Container(
      height: 48,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Logo/brand
          Row(
            children: [
              Icon(Icons.language,
                  color: Colors.white.withValues(alpha: 0.8), size: 20),
              const SizedBox(width: 8),
              Text(
                'Sitio web',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Task-oriented workspace navigation. Management screens replace the
          // canvas instead of competing with the block inspector.
          _buildPreviewWorkspaceButton(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Editar página',
            icon: Icons.edit_outlined,
            actionId: _actionPageEditorWorkspace,
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.pageEditor,
          ),
          _buildPreviewWorkspaceButton(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Catálogo web',
            icon: Icons.storefront_outlined,
            actionId: _actionEcomCatalog,
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.catalog,
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Estructura',
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.structure,
            actions: const [
              _PreviewNavAction(
                id: _actionSitePages,
                label: 'Páginas',
                icon: Icons.description_outlined,
              ),
              _PreviewNavAction(
                id: _actionSiteNavigation,
                label: 'Navegación y menús',
                icon: Icons.menu,
              ),
              _PreviewNavAction(
                id: _actionSiteDestinations,
                label: 'Destinos y enlaces',
                icon: Icons.account_tree_outlined,
              ),
            ],
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Ajustes',
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.settings,
            actions: const [
              _PreviewNavAction(
                id: _actionSiteSettings,
                label: 'Sitio, tema y contacto',
                icon: Icons.tune,
              ),
              _PreviewNavAction(
                id: _actionConfigWebsiteSettings,
                label: 'SEO',
                icon: Icons.manage_search_outlined,
              ),
              _PreviewNavAction(
                id: _actionConfigIntegrations,
                label: 'Integraciones',
                icon: Icons.extension_outlined,
              ),
              _PreviewNavAction(
                id: _actionConfigDomain,
                label: 'Dominio y URL',
                icon: Icons.link_outlined,
              ),
              _PreviewNavAction(
                id: _actionConfigPaymentMethods,
                label: 'Métodos de pago',
                icon: Icons.payments_outlined,
              ),
            ],
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Más',
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.operations,
            actions: const [
              _PreviewNavAction(
                id: _actionEcomOrders,
                label: 'Pedidos online',
                icon: Icons.shopping_bag_outlined,
              ),
              _PreviewNavAction(
                id: _actionReportsAnalytics,
                label: 'Analytics',
                icon: Icons.analytics_outlined,
              ),
              _PreviewNavAction(
                id: _actionSiteOpenWebsiteHub,
                label: 'Centro del Sitio Web',
                icon: Icons.dashboard_outlined,
              ),
              _PreviewNavAction.divider(),
              _PreviewNavAction(
                id: _actionGoogleOpenMerchantFeed,
                label: 'Abrir feed de productos',
                icon: Icons.feed_outlined,
              ),
              _PreviewNavAction(
                id: _actionGoogleCopyMerchantFeed,
                label: 'Copiar feed de productos',
                icon: Icons.copy,
              ),
            ],
          ),

          // Current page actions (copy link, open)
          _buildCurrentPageMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
          ),

          const Spacer(),

          // Store name dropdown
          _buildStoreMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            storeName: storeName,
          ),
          const SizedBox(width: 16),

          // Published toggle
          Row(
            children: [
              Text(
                'Publicado',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
              const SizedBox(width: 8),
              Switch(
                value: sitePublished,
                onChanged: (v) async {
                  final next = v ? 'true' : 'false';
                  await websiteService.saveSetting('site_published', next);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          v ? 'Sitio publicado' : 'Sitio despublicado',
                        ),
                      ),
                    );
                  }
                },
                activeThumbColor: Colors.green,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(width: 16),

          if (editProvider.isPageEditorWorkspace) ...[
            // Device preview belongs to page composition, not management.
            PopupMenuButton<DevicePreviewMode>(
              tooltip: 'Vista (dispositivo)',
              initialValue: editProvider.devicePreviewMode,
              onSelected: (mode) => editProvider.setDevicePreviewMode(mode),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: DevicePreviewMode.desktop,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.desktop_windows_outlined),
                    title: Text('Desktop'),
                  ),
                ),
                PopupMenuItem(
                  value: DevicePreviewMode.tablet,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.tablet_mac_outlined),
                    title: Text('Tablet'),
                  ),
                ),
                PopupMenuItem(
                  value: DevicePreviewMode.mobile,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.phone_android_outlined),
                    title: Text('Móvil'),
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  editProvider.devicePreviewMode == DevicePreviewMode.desktop
                      ? Icons.desktop_windows
                      : editProvider.devicePreviewMode ==
                              DevicePreviewMode.tablet
                          ? Icons.tablet_mac
                          : Icons.phone_android,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Screenshot button
            IconButton(
              onPressed: _isCapturingScreenshot
                  ? null
                  : () => _captureFullPageScreenshot(context, editProvider),
              icon: _isCapturingScreenshot
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(Icons.camera_alt_outlined,
                      color: Colors.white70, size: 20),
              tooltip: 'Capturar página',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 8),

            // New page button
            TextButton(
              onPressed: () => _showQuickCreatePageDialog(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Nuevo', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),

            // Main mode button (Preview -> Edit, Edit -> Preview)
            _CmsModeButton(
              label: isEditMode ? 'Vista previa' : 'Editar',
              onPressed: () {
                final next = isEditMode
                    ? WebsiteEditorMode.preview
                    : WebsiteEditorMode.edit;

                // The native ERP workspace keeps its route stable: the FSM is
                // the only owner and there is no visible URL to project.
                if (_isErpMountedStore() && !kIsWeb) {
                  editProvider.setMode(next);
                  return;
                }

                // On web the toggle is a navigation carrying the canonical
                // mode projection; the changed URI is then consumed as the
                // FSM command in the next build. One navigation, one history
                // entry, so browser Back/forward replay mode transitions.
                final currentUri = GoRouterState.of(context).uri;
                final projected =
                    projectWebsiteEditorModeOntoUri(currentUri, next);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  context.go(_routeForPublicStore(projected.toString()));
                });
              },
            ),
            const SizedBox(width: 8),
          ],

          // Close/exit button - go back to Website Management
          IconButton(
            onPressed: () async {
              final editorDecision =
                  await WebsiteEditorNavigationGuard.authorize(
                context,
                intent: WebsiteEditorNavigationIntent.leaveEditor,
              );
              if (!editorDecision.isAllowed) return;
              if (!context.mounted) return;
              if (!await PublicStoreLayout.authorizeCheckoutExit(context)) {
                return;
              }
              if (!context.mounted) return;
              if (!editorDecision.commit()) return;
              editProvider.closeEditor();
              context.go(
                _isErpMountedStore()
                    ? '/website'
                    : _routeForPublicStore('/tienda'),
              );
            },
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            tooltip: 'Volver a Gestión de Sitio Web',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreMenu({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String storeName,
  }) {
    final label = storeName.isNotEmpty ? storeName : 'Mi Tienda';
    return PopupMenuButton<String>(
      tooltip: 'Acciones de tienda',
      onSelected: (action) => _handleTopBarAction(
        context: context,
        editProvider: editProvider,
        websiteService: websiteService,
        actionId: action,
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _actionStoreOpenPublic,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.open_in_new),
            title: Text('Abrir tienda pública'),
          ),
        ),
        PopupMenuItem(
          value: _actionStoreCopyUrl,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.copy),
            title: Text('Copiar URL'),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewWorkspaceButton({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String label,
    required IconData icon,
    required String actionId,
    required bool isActive,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _handleTopBarAction(
          context: context,
          editProvider: editProvider,
          websiteService: websiteService,
          actionId: actionId,
        ),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withValues(alpha: 0.1) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewNavMenu({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String label,
    required bool isActive,
    required List<_PreviewNavAction> actions,
  }) {
    final entries = <PopupMenuEntry<String>>[];
    for (final a in actions) {
      if (a.isDivider) {
        entries.add(const PopupMenuDivider());
        continue;
      }
      entries.add(
        PopupMenuItem<String>(
          value: a.id!,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(a.icon,
                color: Colors.white.withValues(alpha: 0.9), size: 20),
            title: Text(
              a.label!,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: label,
      offset: const Offset(0, 38),
      color: const Color(0xFF252525),
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (action) => _handleTopBarAction(
        context: context,
        editProvider: editProvider,
        websiteService: websiteService,
        actionId: action,
      ),
      itemBuilder: (context) => entries,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color:
                  isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPageMenu({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
  }) {
    final title = _currentPageTitle(context, editProvider);

    return InkWell(
      onTap: () => _showPageNavigator(
        context: context,
        editProvider: editProvider,
        websiteService: websiteService,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(
              Icons.article_outlined,
              size: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }

  String _currentPageTitle(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) {
    final slug = _getCurrentSlugFromRoute(context, editProvider);
    if (slug.isEmpty) return 'Página: Inicio';
    return 'Página: ${_displayPathForSlug(slug)}';
  }

  /// Detect the current page slug from the actual URL, falling back to
  /// editProvider.currentPageSlug for CMS pages.
  String _getCurrentSlugFromRoute(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) {
    try {
      final uri = GoRouterState.of(context).uri;
      final path = uri.path;

      // Remove /tienda prefix if present (ERP host)
      var cleanPath = path;
      if (cleanPath.startsWith('/tienda')) {
        cleanPath = cleanPath.substring('/tienda'.length);
      }
      if (cleanPath.isEmpty || cleanPath == '/') {
        return ''; // Home page
      }

      // Ensure it starts with /
      if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';

      // Dynamic system routes are not CMS pages. Preserve their exact public
      // context in the top bar instead of falling back to the last edited page
      // (historically this mislabeled product detail as “Página: Inicio”).
      if (cleanPath.startsWith('/productos/categoria/') ||
          cleanPath.startsWith('/servicios/categoria/')) {
        return '!path:$cleanPath';
      }
      final productSegments = cleanPath
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      if (productSegments.length >= 2 && productSegments.first == 'productos') {
        return '!path:$cleanPath';
      }

      // Known canonical routes
      const canonicalRoutes = <String, String>{
        '/productos': 'productos',
        '/contacto': 'contacto',
        '/carrito': 'carrito',
        '/checkout': 'checkout',
        '/cuenta': 'cuenta',
      };
      if (canonicalRoutes.containsKey(cleanPath)) {
        return canonicalRoutes[cleanPath]!;
      }

      // Policy pages at root level
      const policySlugs = {
        'nosotros',
        'terminos',
        'privacidad',
        'devoluciones',
        'envios'
      };
      final rootSlug = cleanPath.substring(1); // Remove leading /
      if (policySlugs.contains(rootSlug)) {
        return rootSlug;
      }

      // /pagina/<slug> pattern
      if (cleanPath.startsWith('/pagina/')) {
        return cleanPath.substring('/pagina/'.length);
      }

      // If it's a simple slug (e.g. /servicios), use it
      if (!rootSlug.contains('/')) {
        return rootSlug;
      }

      // Fallback to provider
      return (editProvider.currentPageSlug ?? '').trim();
    } catch (_) {
      return (editProvider.currentPageSlug ?? '').trim();
    }
  }

  Future<void> _showPageNavigator({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
  }) async {
    final navContext = context;

    // Ensure pages are available (public store can run unauthenticated).
    final tenantProvider = navContext.read<PublicStoreTenantProvider>();
    final tenantId = tenantProvider.tenantId;
    if (websiteService.pages.isEmpty && tenantId != null) {
      await websiteService.loadPagesForTenant(tenantId);
    }

    if (!navContext.mounted) return;

    final initialSlug = _getCurrentSlugFromRoute(navContext, editProvider);
    final pages = List<WebsitePage>.from(websiteService.pages);

    // Build targets (include a few canonical routes even if pages table is
    // missing them).
    final targets = _buildPageNavigatorTargets(pages);

    final selected = await showDialog<_PageNavTarget>(
      context: navContext,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final isCompact = size.width < 720;

        return Dialog(
          backgroundColor: const Color(0xFF1E1E1E), // Match editor theme
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 24,
            vertical: isCompact ? 16 : 24,
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: isCompact ? size.height - 32 : 680,
              minHeight: 420,
            ),
            child: _PageNavigatorDialog(
              initialSlug: initialSlug,
              targets: targets,
              onCopyLink: () => _copyCurrentPageUrl(
                dialogContext,
                editProvider,
                websiteService,
              ),
              onOpenNewTab: () => _openCurrentPageUrl(
                dialogContext,
                editProvider,
                websiteService,
              ),
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    if (!navContext.mounted) return;

    // The page navigator already provides normalized hrefs. Use direct
    // navigation instead of _navigateToHref to avoid UUID resolution loops.
    final href = selected.href;

    // Project the CURRENT editor mode onto the destination. The page
    // selector keeps the appropriate edit/preview context; it never escalates
    // Preview to Edit on its own (that is an explicit toggle command).
    final currentUri = GoRouterState.of(navContext).uri;
    final parsedHref = Uri.tryParse(href);
    final target = parsedHref == null
        ? href
        : projectWebsiteEditorModeOntoUri(
            parsedHref,
            navContext.read<WebsiteEditModeProvider>().mode,
          ).toString();
    final targetUri = Uri.tryParse(target);
    if (targetUri?.toString() == currentUri.toString()) return;
    final keepsCurrentDocument =
        targetUri != null && targetUri.path == currentUri.path;

    // Use go() to replace current route (avoids stacking editor pages).
    final editorDecision = await WebsiteEditorNavigationGuard.authorize(
      navContext,
      intent: keepsCurrentDocument
          ? WebsiteEditorNavigationIntent.samePage
          : WebsiteEditorNavigationIntent.switchPage,
    );
    if (!editorDecision.isAllowed) return;
    if (!navContext.mounted) return;
    if (!await PublicStoreLayout.authorizeCheckoutExit(navContext)) return;
    if (!navContext.mounted) return;
    if (!editorDecision.commit()) return;
    navContext.go(target);
  }

  List<_PageNavTarget> _buildPageNavigatorTargets(List<WebsitePage> pages) {
    // Some routes are not always present as CMS rows but are still useful to
    // navigate while in edit mode.
    const canonical = <_PageNavTarget>[
      _PageNavTarget(
        key: 'home',
        title: 'Inicio',
        href: '/tienda',
        kind: _PageNavKind.core,
      ),
      _PageNavTarget(
        key: 'productos',
        title: 'Productos',
        href: '/tienda/productos',
        kind: _PageNavKind.core,
      ),
      _PageNavTarget(
        key: 'servicios',
        title: 'Servicios',
        href: '/tienda/servicios',
        kind: _PageNavKind.core,
      ),
      _PageNavTarget(
        key: 'contacto',
        title: 'Contacto',
        href: '/tienda/contacto',
        kind: _PageNavKind.core,
      ),
      _PageNavTarget(
        key: 'carrito',
        title: 'Carrito',
        href: '/tienda/carrito',
        kind: _PageNavKind.system,
      ),
      _PageNavTarget(
        key: 'checkout',
        title: 'Checkout',
        href: '/tienda/checkout',
        kind: _PageNavKind.system,
      ),
      _PageNavTarget(
        key: 'cuenta',
        title: 'Cuenta',
        href: '/tienda/cuenta',
        kind: _PageNavKind.system,
      ),
    ];

    const policySlugs = <String>{
      'nosotros',
      'terminos',
      'privacidad',
      'devoluciones',
      'envios',
    };

    final byKey = <String, _PageNavTarget>{
      for (final t in canonical) t.key: t,
    };

    for (final p in pages) {
      final slug = p.slug.trim();
      if (slug.isEmpty) continue;

      final isPolicy = policySlugs.contains(slug);
      final isHome = p.isHome || slug == 'inicio' || slug == 'home';

      final kind = isHome
          ? _PageNavKind.core
          : isPolicy
              ? _PageNavKind.legal
              : p.isSystem
                  ? _PageNavKind.system
                  : (p.isPublished
                      ? _PageNavKind.published
                      : _PageNavKind.draft);

      final legacyHref = isHome
          ? '/tienda'
          : isPolicy
              ? '/$slug'
              : _isDirectSlug(slug)
                  ? '/tienda/$slug'
                  : '/tienda/pagina/$slug';

      final key = isHome ? 'home' : slug;
      byKey[key] = _PageNavTarget(
        key: key,
        title: p.title.isNotEmpty ? p.title : slug,
        href: legacyHref,
        kind: kind,
        subtitle: _displayPathForSlug(isHome ? '' : slug),
        isPublished: p.isPublished,
      );
    }

    final targets = byKey.values.toList();
    targets.sort((a, b) {
      final kindCmp = a.kind.index.compareTo(b.kind.index);
      if (kindCmp != 0) return kindCmp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    // Normalize hrefs to current host conventions.
    return targets
        .map(
          (t) => t.copyWith(href: _routeForPublicStore(t.href)),
        )
        .toList();
  }

  bool _isDirectSlug(String slug) {
    // Slugs that map to clean top-level routes (not /pagina/*).
    const direct = <String>{
      'productos',
      'servicios',
      'contacto',
      'carrito',
      'checkout',
      'cuenta',
    };
    return direct.contains(slug);
  }

  String _displayPathForSlug(String slug) {
    if (slug.isEmpty) return '/';
    if (slug.startsWith('!path:')) return slug.substring('!path:'.length);
    if (_isDirectSlug(slug)) return '/$slug';
    const policySlugs = <String>{
      'nosotros',
      'terminos',
      'privacidad',
      'devoluciones',
      'envios',
    };
    if (policySlugs.contains(slug)) return '/$slug';
    return '/pagina/$slug';
  }

  Future<void> _handleTopBarAction({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String actionId,
  }) async {
    // For actions that go back into ERP pages, ensure we exit editor mode cleanly.
    Future<void> goAdmin(String path) async {
      final editorDecision = await WebsiteEditorNavigationGuard.authorize(
        context,
        intent: WebsiteEditorNavigationIntent.leaveEditor,
      );
      if (!editorDecision.isAllowed) return;
      if (!context.mounted) return;
      if (!await PublicStoreLayout.authorizeCheckoutExit(context)) return;
      if (!context.mounted) return;
      if (!editorDecision.commit()) return;
      editProvider.closeEditor();
      context.go(path);
    }

    switch (actionId) {
      case _actionPageEditorWorkspace:
        _closeConfigHub();
        return;
      case _actionEcomCatalog:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomCatalog);
          return;
        }
        await goAdmin('/website/product-visibility');
        return;

      // Site
      case _actionSitePages:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.sitePages);
          return;
        }
        await goAdmin('/website/pages');
        return;
      case _actionSiteNavigation:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteNavigation);
          return;
        }
        await goAdmin('/website/navigation');
        return;
      case _actionSiteDestinations:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteDestinations);
          return;
        }
        await goAdmin('/website/destinations');
        return;
      case _actionSiteSettings:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteSettings);
          return;
        }
        await goAdmin('/website/settings');
        return;
      case _actionSiteOpenWebsiteHub:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteHub);
          return;
        }
        await goAdmin('/website');
        return;

      // E-commerce
      case _actionEcomOrders:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomOrders);
          return;
        }
        await goAdmin('/website/orders');
        return;
      case _actionEcomGoogle:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.integrations);
          return;
        }
        await goAdmin('/website/integrations');
        return;

      // Reports
      case _actionReportsAnalytics:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.reportsAnalytics);
          return;
        }
        await goAdmin('/tools/analytics');
        return;
      case _actionReportsOrders:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomOrders);
          return;
        }
        await goAdmin('/website/orders');
        return;

      // Google quick actions
      case _actionGoogleOpenMerchantFeed:
        final url = _resolveGoogleMerchantFeedUrl(websiteService);
        if (url == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudo determinar la URL del feed'),
              ),
            );
          }
          return;
        }
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      case _actionGoogleCopyMerchantFeed:
        final url = _resolveGoogleMerchantFeedUrl(websiteService);
        if (url == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudo determinar la URL del feed'),
              ),
            );
          }
          return;
        }
        await _copyToClipboard(url);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Feed copiado al portapapeles')),
          );
        }
        return;

      // Config
      case _actionConfigWebsiteSettings:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.seo);
          return;
        }
        await goAdmin('/website/seo');
        return;
      case _actionConfigIntegrations:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.integrations);
          return;
        }
        await goAdmin('/website/integrations');
        return;
      case _actionConfigPaymentMethods:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.paymentMethods);
          return;
        }
        await goAdmin('/settings/payment-methods');
        return;
      case _actionConfigDomain:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.domain);
          return;
        }
        await _showDomainAndUrlDialog(context);
        return;

      // Page actions
      case _actionPageCopyLink:
        await _copyCurrentPageUrl(context, editProvider, websiteService);
        return;
      case _actionPageOpenNewTab:
        await _openCurrentPageUrl(context, editProvider, websiteService);
        return;

      // Store actions
      case _actionStoreOpenWebsite:
        await goAdmin('/website');
        return;
      case _actionStoreCopyUrl:
        await _copyPublicStoreUrl(context, websiteService);
        return;
      case _actionStoreOpenPublic:
        await _openPublicStoreUrl(context, websiteService);
        return;
    }
  }

  Future<void> _openPublicStoreUrl(
    BuildContext context,
    WebsiteService websiteService,
  ) async {
    final url = _resolvePublicStoreUrl(websiteService);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo determinar la URL pública')),
        );
      }
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _currentPagePathForLink(WebsiteEditModeProvider editProvider) {
    final slug = (editProvider.currentPageSlug ?? '').trim();
    if (slug.isEmpty) {
      return _routeForPublicStore('/tienda');
    }

    // Policy pages are always clean URLs in both hosts.
    const policySlugs = {
      'nosotros',
      'terminos',
      'privacidad',
      'devoluciones',
      'envios',
    };
    if (policySlugs.contains(slug)) {
      return '/$slug';
    }

    // All other CMS pages should use the standard website page route.
    return _routeForPublicStore('/tienda/pagina/$slug');
  }

  String? _buildUrlWithPath({
    required WebsiteService websiteService,
    required String path,
  }) {
    final base = _resolvePublicStoreUrl(websiteService);
    if (base == null) return null;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return null;

    // Ensure path is appended cleanly (avoid double slashes).
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final next = baseUri.replace(
      path: normalizedPath,
      query: '',
      fragment: '',
    );
    return next.toString();
  }

  Future<void> _openCurrentPageUrl(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
  ) async {
    final path = _currentPagePathForLink(editProvider);
    final url = _buildUrlWithPath(websiteService: websiteService, path: path);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo determinar el enlace')),
        );
      }
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _copyCurrentPageUrl(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
  ) async {
    final path = _currentPagePathForLink(editProvider);
    final url = _buildUrlWithPath(websiteService: websiteService, path: path);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo determinar el enlace')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlace copiado al portapapeles')),
      );
    }
  }

  Future<void> _copyPublicStoreUrl(
    BuildContext context,
    WebsiteService websiteService,
  ) async {
    final url = _resolvePublicStoreUrl(websiteService);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo determinar la URL pública')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL copiada al portapapeles')),
      );
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  String? _resolvePublicStoreUrl(WebsiteService websiteService) {
    final explicit = websiteService.getSetting('store_url', '').trim();
    if (explicit.isNotEmpty) return explicit;

    if (!kIsWeb) return null;

    // When running in ERP/admin host, we can't reliably derive the public domain here.
    // But on the public store host, Uri.base already is the public store.
    final host = Uri.base.host;
    if (host.isEmpty) return null;
    return '${Uri.base.scheme}://$host';
  }

  List<Uri> _resolveStorefrontInternalOrigins(
    WebsiteService websiteService,
    PublicStoreTenantProvider tenantProvider,
  ) {
    final tenantId = tenantProvider.tenantId;
    final subdomain = tenantProvider.subdomain?.trim() ?? '';
    final customDomain =
        tenantProvider.currentTenant?.customDomain?.trim() ?? '';
    return WebsiteDestination.resolveInternalOrigins(
      configuredUrls: [
        websiteService.getSetting('store_url', ''),
        // This is accepted only as an owned alias. `store_url` remains the
        // public-runtime owner until the unified SEO projection replaces the
        // legacy duplicate setting.
        websiteService.getSetting('seo_canonical_url', ''),
      ],
      ownedHosts: [
        customDomain,
        if (subdomain.isNotEmpty) '$subdomain.bikeshop-erp.app',
        if (tenantId != null)
          ...TenantDetectionService.knownHostsForTenant(tenantId),
      ],
      currentUri: kIsWeb ? Uri.base : null,
    );
  }

  bool _allowsPublicHref(String href) {
    return _pagePublication.allowsHref(href) &&
        _categoryPublication.allowsHref(
          href,
          internalOrigins: _storefrontInternalOrigins,
        );
  }

  String? _resolveGoogleMerchantFeedUrl(WebsiteService websiteService) {
    const supabaseFunctionsBaseUrl =
        'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1';

    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final subdomain = (tenantProvider.subdomain ?? '').trim();

    // Prefer custom domain if we can resolve it (works for vinabike.cl).
    final publicUrl = _resolvePublicStoreUrl(websiteService);
    final host = publicUrl == null ? '' : (Uri.tryParse(publicUrl)?.host ?? '');

    if (host.isNotEmpty) {
      return '$supabaseFunctionsBaseUrl/google-merchant-feed?domain=$host';
    }
    if (subdomain.isNotEmpty) {
      return '$supabaseFunctionsBaseUrl/google-merchant-feed?tenant=$subdomain';
    }
    return null;
  }

  Future<void> _showDomainAndUrlDialog(BuildContext context) async {
    final tenantId = await _resolveTenantIdForSave(context);

    if (tenantId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo identificar el tenant')),
        );
      }
      return;
    }

    final supabase = Supabase.instance.client;
    final tenant = await supabase
        .from('tenants')
        .select('subdomain, custom_domain')
        .eq('id', tenantId)
        .maybeSingle();

    if (!context.mounted) return;

    final subdomain = (tenant?['subdomain'] as String?)?.trim() ?? '';
    final currentCustomDomain = (tenant?['custom_domain'] as String?)?.trim();

    final controller = TextEditingController(text: currentCustomDomain ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dominio y URL'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subdominio actual: ${subdomain.isEmpty ? "—" : "$subdomain.bikeshop-erp.app"}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Dominio personalizado (opcional)',
                  hintText: 'www.tutienda.cl',
                  prefixIcon: Icon(Icons.link_outlined),
                  helperText:
                      'Si lo dejas vacío, tu tienda seguirá usando el subdominio.',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'DNS (resumen):\n- CNAME: www -> tu-subdominio.bikeshop-erp.app\n- O A/ALIAS según tu proveedor',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final next = controller.text.trim();
              try {
                await supabase.from('tenants').update({
                  'custom_domain': next.isEmpty ? null : next,
                }).eq('id', tenantId);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Error actualizando dominio: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.language_outlined),
            label: const Text('Aplicar dominio'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dominio actualizado')),
      );
    }
  }

  Widget _buildUnpublishedSiteScaffold(BuildContext context, String storeName) {
    final label = storeName.isNotEmpty ? storeName : 'Mi Tienda';
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_off_outlined,
                    size: 56, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  '$label no está publicado',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Este sitio está en construcción. Vuelve pronto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final isLoggedIn =
                        Supabase.instance.client.auth.currentUser != null;
                    if (!isLoggedIn) return const SizedBox.shrink();
                    return FilledButton.icon(
                      onPressed: () => context
                          .go(_routeForPublicStore('/tienda?preview=true')),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Entrar al editor'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ONE viewport for every mode and device preview. The TYPE/KEY chain is
  /// constant — MediaQueryLayoutBuilder → Padding → Center → Container →
  /// MediaQuery → child — and only PROPERTY VALUES change (frame width,
  /// height, decoration, media size). The routed content therefore never
  /// re-parents across public|preview|edit or desktop|tablet|mobile.
  Widget _buildStorefrontContentViewport(
    BuildContext context,
    Widget child, {
    required bool framed,
    required bool isEditMode,
    required DevicePreviewMode devicePreviewMode,
  }) {
    // Captured OUTSIDE the layout builder: the unframed branch must expose
    // the ORIGINAL ambient MediaQuery (MediaQueryLayoutBuilder injects a
    // constraint-derived one, which would silently reroute responsive
    // consumers like the footer).
    final outerMedia = MediaQuery.of(context);
    // A REAL LayoutBuilder: the anchor slot's actual constraints drive the
    // fill (MediaQueryLayoutBuilder would substitute MediaQuery.size and
    // letterbox the storefront under scoped-media hosts).
    return LayoutBuilder(
      key: const ValueKey('storefront_content_viewport'),
      builder: (context, constraints) {
        final screenSize = outerMedia.size;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : screenSize.height;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screenSize.width;
        final frameWidth = framed
            ? (devicePreviewMode == DevicePreviewMode.tablet ? 820.0 : 390.0)
            : availableWidth;
        // Shift a framed preview left of the overlaid editor panel so it
        // reads visually centered.
        final panelOffset =
            framed && isEditMode ? _externalEditorPanelWidth / 2 : 0.0;
        return Padding(
          padding: EdgeInsets.only(right: panelOffset * 2),
          child: Center(
            child: Container(
              width: frameWidth,
              height: availableHeight,
              decoration: framed
                  ? BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    )
                  : null,
              clipBehavior: framed ? Clip.antiAlias : Clip.none,
              child: MediaQuery(
                data: framed
                    ? outerMedia.copyWith(
                        size: Size(frameWidth, availableHeight),
                      )
                    : outerMedia,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
  Future<void> _showQuickCreatePageDialog(BuildContext context) async {
    final editorDecision = await WebsiteEditorNavigationGuard.authorize(
      context,
      intent: WebsiteEditorNavigationIntent.switchPage,
    );
    if (!editorDecision.isAllowed || !context.mounted) return;

    final titleController = TextEditingController();
    final slugController = TextEditingController();
    var autoSlug = true;
    PageTemplate template = PageTemplate.defaultTemplate;

    String generateSlug(String title) {
      return title
          .toLowerCase()
          .replaceAll(RegExp(r'[áàäâ]'), 'a')
          .replaceAll(RegExp(r'[éèëê]'), 'e')
          .replaceAll(RegExp(r'[íìïî]'), 'i')
          .replaceAll(RegExp(r'[óòöô]'), 'o')
          .replaceAll(RegExp(r'[úùüû]'), 'u')
          .replaceAll('ñ', 'n')
          .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
    }

    titleController.addListener(() {
      if (autoSlug) {
        slugController.text = generateSlug(titleController.text);
      }
    });

    final created = await showDialog<WebsitePage>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Nueva página'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: slugController,
                    decoration: InputDecoration(
                      labelText: 'Slug (URL)',
                      prefixText: '/pagina/',
                      prefixIcon: const Icon(Icons.link),
                      helperText: autoSlug
                          ? 'Auto-generado desde el título'
                          : 'Puedes editarlo manualmente',
                    ),
                    onChanged: (_) => setState(() => autoSlug = false),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PageTemplate>(
                    initialValue: template,
                    decoration: const InputDecoration(
                      labelText: 'Plantilla',
                      prefixIcon: Icon(Icons.layers_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PageTemplate.defaultTemplate,
                        child: Text('Estándar (bloques)'),
                      ),
                      DropdownMenuItem(
                        value: PageTemplate.landing,
                        child: Text('Landing'),
                      ),
                      DropdownMenuItem(
                        value: PageTemplate.blog,
                        child: Text('Blog'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => template = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final title = titleController.text.trim();
                  final slug = slugController.text.trim();
                  if (title.isEmpty || slug.isEmpty) return;
                  if (!editorDecision.isCurrent) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'El borrador cambió. Cierra y vuelve a crear la '
                          'página para no perderlo.',
                        ),
                      ),
                    );
                    return;
                  }

                  try {
                    final websiteService = context.read<WebsiteService>();
                    final page = WebsitePage(
                      id: '',
                      tenantId: '',
                      slug: slug,
                      title: title,
                      template: template,
                      isPublished: true,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    final created = await websiteService.createPage(page);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, created);
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Error creando página: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Crear y editar'),
              ),
            ],
          ),
        );
      },
    );

    titleController.dispose();
    slugController.dispose();

    if (created == null || !context.mounted) return;
    if (!editorDecision.commit()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La página fue creada, pero el borrador cambió y se conservó. '
            'Ábrela desde el selector de páginas.',
          ),
        ),
      );
      return;
    }

    // Jump directly into edit mode on the new page.
    context
        .go(_routeForPublicStore('/tienda/pagina/${created.slug}?edit=true'));
  }

  /// Requests the tenant's confirmed payment methods.
  ///
  /// Never called during build; scheduled from the footer builder when the
  /// active tenant changes, or fired by the bounded retry timer. All retry
  /// state mutation lives here — [_paymentCapabilityAutoLoadDue] stays pure.
  Future<void> _loadPaymentCapabilities(String tenantId) async {
    final normalized = tenantId.trim();
    if (normalized.isEmpty) return;
    if (_paymentCapabilitiesTenantId == normalized &&
        _paymentCapabilities != null) {
      return;
    }

    // The attempt budget belongs to one tenant. A different tenant starts
    // fresh: its predecessor's failures were never its own, and the
    // predecessor's pending retry is now moot.
    if (_paymentCapabilitiesAttemptsTenantId != normalized) {
      _paymentCapabilitiesRetryTimer?.cancel();
      _paymentCapabilitiesRetryTimer = null;
      _paymentCapabilitiesAttemptsTenantId = normalized;
      _paymentCapabilitiesAttempts = 0;
    }
    // A request is already in flight for this exact tenant.
    if (_paymentCapabilitiesRequestedTenantId == normalized) return;
    if (_paymentCapabilitiesAttempts >= _kPaymentCapabilityMaxAttempts) return;

    // This attempt supersedes any pending timer for the same tenant.
    _paymentCapabilitiesRetryTimer?.cancel();
    _paymentCapabilitiesRetryTimer = null;

    final generation = ++_paymentCapabilitiesGeneration;
    _paymentCapabilitiesRequestedTenantId = normalized;
    _paymentCapabilitiesAttempts += 1;
    try {
      final capabilities = await (widget.checkoutCapabilityLoader ??
          const PublicCheckoutCapabilityService().load)(normalized);
      if (!mounted || generation != _paymentCapabilitiesGeneration) return;
      _paymentCapabilitiesRetryTimer?.cancel();
      _paymentCapabilitiesRetryTimer = null;
      setState(() {
        _paymentCapabilities = capabilities;
        _paymentCapabilitiesTenantId = normalized;
        _paymentCapabilitiesRequestedTenantId = null;
        _paymentCapabilitiesAttempts = 0;
      });
    } catch (_) {
      if (!mounted || generation != _paymentCapabilitiesGeneration) return;
      // A failed read is unknown, not "no methods" — the footer keeps
      // claiming nothing. The in-flight latch is released, and while budget
      // remains a real timer owns the next attempt so recovery never depends
      // on an external rebuild.
      final backoffIndex = _paymentCapabilitiesAttempts - 1;
      setState(() {
        _paymentCapabilities = null;
        _paymentCapabilitiesTenantId = null;
        _paymentCapabilitiesRequestedTenantId = null;
      });
      if (backoffIndex < _kPaymentCapabilityBackoff.length) {
        _paymentCapabilitiesRetryTimer = Timer(
          _kPaymentCapabilityBackoff[backoffIndex],
          () {
            _paymentCapabilitiesRetryTimer = null;
            // A timer armed before a tenant switch or a newer request is
            // stale; the generation comparison keeps it inert.
            if (!mounted || generation != _paymentCapabilitiesGeneration) {
              return;
            }
            _loadPaymentCapabilities(normalized);
          },
        );
      }
    }
  }

  /// Whether the footer builder may schedule a load right now.
  ///
  /// Pure by contract: build must never mutate retry state. Every mutation —
  /// budget reset on tenant change, timer cancellation, attempt accounting —
  /// happens inside [_loadPaymentCapabilities], which re-validates before
  /// acting.
  bool _paymentCapabilityAutoLoadDue(String normalizedTenantId) {
    // A request for this tenant is already in flight.
    if (_paymentCapabilitiesRequestedTenantId == normalizedTenantId) {
      return false;
    }
    // The budget and any pending timer belong to another tenant; loading this
    // one resets them, so it is always allowed to start.
    if (_paymentCapabilitiesAttemptsTenantId != normalizedTenantId) {
      return true;
    }
    // The pending timer owns the next attempt for this tenant.
    if (_paymentCapabilitiesRetryTimer != null) return false;
    return _paymentCapabilitiesAttempts < _kPaymentCapabilityMaxAttempts;
  }

  /// Renders the "Medios de Pago" block, or nothing while unknown.
  List<Widget> _buildPaymentBadges(BuildContext context, String? tenantId) {
    final normalized = tenantId?.trim() ?? '';
    if (normalized.isEmpty) return const <Widget>[];

    if (_paymentCapabilitiesTenantId != normalized) {
      // Schedule outside build; until it answers, no claim is made. The pure
      // due-check keeps this from queueing a callback per frame while a retry
      // timer or an in-flight request already owns the next attempt.
      if (_paymentCapabilityAutoLoadDue(normalized)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadPaymentCapabilities(normalized);
        });
      }
      return const <Widget>[];
    }

    final claims = resolvePublicPaymentClaims(_paymentCapabilities);
    if (claims.isEmpty) return const <Widget>[];

    return [
      const SizedBox(height: 32),
      Semantics(
        container: true,
        label: 'Medios de pago aceptados',
        child: Column(
          children: [
            Text(
              'Medios de Pago',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final code in claims)
                  if (kPublicStorePaymentClaims[code]!.imageUrl case final url?)
                    _PaymentBadge(
                      name: kPublicStorePaymentClaims[code]!.label,
                      imageUrl: url,
                      isSvg: url.endsWith('.svg'),
                    )
                  else
                    _GenericPaymentClaim(
                      label: kPublicStorePaymentClaims[code]!.label,
                    ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  /// Converts legacy in-app routes under `/tienda` to clean public-store routes.
  ///
  /// Example: `/tienda` -> `/`, `/tienda/productos` -> `/productos`.
  /// Preserves query parameters (e.g. `/tienda?edit=true` -> `/?edit=true`).

  /// Converts legacy in-app routes under `/tienda` to clean public-store routes.
  ///
  /// Example: `/tienda` -> `/`, `/tienda/productos` -> `/productos`.
  /// Preserves query parameters (e.g. `/tienda?edit=true` -> `/?edit=true`).
  String _routeForPublicStore(String legacyRoute) => publicStoreHref(
        legacyRoute,
        isErpMounted: _isErpMountedStore(),
      );

  Future<String?> _resolveTenantIdForSave(BuildContext context) async {
    // 1) Public store host (anonymous tenant detection) via provider
    try {
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final tenantId = tenantProvider.tenantId;
      if (tenantId != null && tenantId.isNotEmpty) {
        return tenantId;
      }
    } catch (_) {
      // Provider not available in this tree (ERP host) - fall back below.
    }

    // 2) Authenticated ERP host via TenantService
    try {
      final tenantService = context.read<TenantService>();
      final tenantId = await tenantService.getTenantId();
      if (tenantId != null && tenantId.isNotEmpty) {
        return tenantId;
      }
    } catch (_) {
      // TenantService not provided - fall back to direct instantiation
    }

    final fallbackService = TenantService();
    final tenantId = await fallbackService.getTenantId();
    if (tenantId != null && tenantId.isNotEmpty) {
      return tenantId;
    }

    return null;
  }

  Widget _buildHeader({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    bool isEditMode = false,
    String headerStyle = 'solid',
    String headerColorMode = 'auto',
    bool showTopBanner = true,
    bool headerShadow = true,
    Color headerBgColor = Colors.white,
    Color? menuSurfaceColor,
    Color? menuRailColor,
    bool navigationUppercase = true,
    List<WebsiteNavigation> navItems = const [],
    required PublicCategoryNavigationProjection categoryNavigationProjection,
    bool isOverlay = false, // For transparent mode when scrolled up
  }) {
    final cart = context.watch<CartProvider>();
    final catalogPresentationRegistry =
        context.read<WebsiteService>().catalogPresentationRegistry;
    // The header identity is stable across Edit/Preview/Public: the FSM
    // rebuilds it in place (edit chrome is overlay state, not a new tree).
    return MediaQueryLayoutBuilder(
        key: ValueKey('header_layout_${isOverlay ? 'overlay' : 'solid'}'),
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: MegaMenuController.instance,
            builder: (context, child) {
              final isMenuOpen = MegaMenuController.instance.isAnyMenuOpen;

              final contrastMode =
                  PublicHeaderContrastModeX.parse(headerColorMode);
              final configuredMenuSurface = menuSurfaceColor ?? headerBgColor;
              final resolvedMenuSurface = configuredMenuSurface.a <= 0.01
                  ? Theme.of(context).colorScheme.surface
                  : configuredMenuSurface.withValues(alpha: 1);
              final resolvedMenuRail =
                  (menuRailColor ?? PublicStoreTheme.secondaryGray)
                      .withValues(alpha: 1);
              // Opening the menu swaps only the active navigation surface.
              // The closed header keeps its normal configured appearance.
              final effectiveBgColor = isMenuOpen
                  ? resolvedMenuSurface
                  : (isOverlay ? Colors.transparent : headerBgColor);
              final effectiveHeaderContrastMode = isMenuOpen
                  ? PublicHeaderContrastMode.automatic
                  : contrastMode;
              final usesLightForeground =
                  effectiveHeaderContrastMode.usesLightForeground(
                isOverlay: isMenuOpen ? false : isOverlay,
                backgroundColor: effectiveBgColor,
              );
              final menuPanelUsesLightForeground =
                  PublicHeaderContrastMode.automatic.usesLightForeground(
                isOverlay: false,
                backgroundColor: resolvedMenuSurface,
              );
              final menuPanelForegroundColor = menuPanelUsesLightForeground
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface;
              final menuRailUsesLightForeground =
                  PublicHeaderContrastMode.automatic.usesLightForeground(
                isOverlay: false,
                backgroundColor: resolvedMenuRail,
              );
              final menuRailForegroundColor = menuRailUsesLightForeground
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface;

              final textColor =
                  usesLightForeground ? Colors.white : Colors.black87;
              final iconColor = usesLightForeground
                  ? Colors.white
                  : PublicStoreTheme.logoBlue;

              // Remove shadow when menu is open to prevent "seam" line
              final effectiveElevation =
                  (isMenuOpen || isOverlay) ? 0.0 : (headerShadow ? 2.0 : 0.0);

              final screenWidth = constraints.maxWidth;
              // The desktop header needs enough room for the complete saved
              // navigation and account actions. Below this width the compact
              // navigation is clearer than squeezing the same content.
              final headerGeometry =
                  PublicStoreHeaderGeometry.resolve(screenWidth);
              final isDesktopHeader = headerGeometry.isDesktop;
              final projectedNavItems = isDesktopHeader
                  ? categoryNavigationProjection.forDesktop(navItems)
                  : categoryNavigationProjection.forMobile(navItems);
              final useAdaptiveOverlayScrim = isOverlay &&
                  contrastMode == PublicHeaderContrastMode.automatic;

              // Transform creates a web stacking context so the configured
              // header and its menu remain above carousel/hero layers.
              final headerContent = Transform.translate(
                offset: Offset.zero,
                child: MegaMenuHeaderWrapper(
                  openBackgroundColor: resolvedMenuSurface,
                  child: AnimatedPhysicalModel(
                    duration: const Duration(
                        milliseconds:
                            300), // Slightly slower to match menu fade/rendering
                    curve: Curves.easeInOut,
                    shape: BoxShape.rectangle,
                    elevation: effectiveElevation,
                    color: effectiveBgColor,
                    shadowColor: Colors.black,
                    child: Container(
                      decoration: useAdaptiveOverlayScrim
                          ? BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.52),
                                  Colors.black.withValues(alpha: 0.24),
                                ],
                              ),
                            )
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showTopBanner && topBannerText.isNotEmpty)
                            Container(
                              width: double.infinity,
                              color: usesLightForeground
                                  ? Colors.black.withValues(alpha: 0.3)
                                  : primaryColor,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_shipping_outlined,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      topBannerText,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isDesktopHeader) ...[
                                    if (contactPhone.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 16),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.phone_outlined,
                                                color: Colors.white, size: 16),
                                            const SizedBox(width: 8),
                                            Text(
                                              contactPhone,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (contactEmail.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 16),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.mail_outline,
                                                color: Colors.white, size: 16),
                                            const SizedBox(width: 8),
                                            Text(
                                              contactEmail,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),

                          // Main header with logo
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: headerGeometry.horizontalPadding,
                                vertical: headerGeometry.verticalPadding),
                            child: Row(
                              children: [
                                // Logo - uses URL if set, otherwise falls back to asset, then text
                                // Logo - Force use of local asset for consistency and to fix "white block" issue
                                // (Database logo_url might be opaque, causing white tint to fill the box)
                                InkWell(
                                  key: const ValueKey(
                                    'public-store-header-home',
                                  ),
                                  onTap: isEditMode
                                      ? null
                                      : () {
                                          final path =
                                              _routeForPublicStore('/tienda');
                                          _navigateToHref(
                                            context,
                                            path,
                                            forceHomeRefresh: true,
                                          );
                                        },
                                  child: SizedBox(
                                    height: headerGeometry.logoHitBox,
                                    child: Center(
                                      child: _buildLogo(
                                        context: context,
                                        logoUrl: logoUrl,
                                        storeName: storeName,
                                        textColor: textColor,
                                        isDarkMode: usesLightForeground,
                                        height: headerGeometry.logoHeight,
                                        maxWidth: headerGeometry.logoMaxWidth,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: headerGeometry.logoGap),
                                // Only show nav links on desktop, use Spacer on mobile
                                if (isDesktopHeader)
                                  Expanded(
                                    child: Row(
                                      children: [
                                        if (projectedNavItems.isEmpty &&
                                            isEditMode)
                                          TextButton.icon(
                                            onPressed: () =>
                                                _openWorkspacePanel(
                                              WebsiteWorkspacePanel.navigation,
                                            ),
                                            icon: const Icon(
                                              Icons.add_link_rounded,
                                              size: 17,
                                            ),
                                            label: const Text(
                                              'Configurar navegación',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: textColor,
                                            ),
                                          )
                                        else
                                          ...projectedNavItems.map((nav) {
                                            final children = nav.children
                                                .where((c) => c.isVisible)
                                                .where((c) => c.showOnDesktop)
                                                .toList()
                                              ..sort((a, b) => a.orderIndex
                                                  .compareTo(b.orderIndex));
                                            if (children.isNotEmpty &&
                                                nav.cssClass
                                                        ?.split(RegExp(r'\s+'))
                                                        .contains('megamenu') ==
                                                    true) {
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 24),
                                                child: MegaMenuButton(
                                                  key: ValueKey(
                                                      'mega_${nav.id}_${nav.label}'),
                                                  parent: nav,
                                                  children: children,
                                                  isEditMode: isEditMode,
                                                  uppercaseLabel:
                                                      navigationUppercase,
                                                  textColor: textColor,
                                                  panelBackgroundColor:
                                                      resolvedMenuSurface,
                                                  panelForegroundColor:
                                                      menuPanelForegroundColor,
                                                  panelRailBackgroundColor:
                                                      resolvedMenuRail,
                                                  panelRailForegroundColor:
                                                      menuRailForegroundColor,
                                                  branchPresentations:
                                                      _projectMegaMenuBranchPresentations(
                                                    branches: children,
                                                    registry:
                                                        catalogPresentationRegistry,
                                                  ),
                                                  canNavigate:
                                                      categoryNavigationProjection
                                                          .canNavigate,
                                                  onNavigate: (href, newTab) =>
                                                      _navigateToHref(
                                                          context, href,
                                                          openInNewTab: newTab),
                                                ),
                                              );
                                            }

                                            if (children.isNotEmpty) {
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 24),
                                                child: NavigationDropdownButton(
                                                  key: ValueKey(
                                                      'dropdown_${nav.id}_${nav.label}'),
                                                  parent: nav,
                                                  children: children,
                                                  isEditMode: isEditMode,
                                                  uppercaseLabel:
                                                      navigationUppercase,
                                                  textColor: textColor,
                                                  panelBackgroundColor:
                                                      resolvedMenuSurface,
                                                  panelForegroundColor:
                                                      menuPanelForegroundColor,
                                                  canNavigate:
                                                      categoryNavigationProjection
                                                          .canNavigate,
                                                  onNavigate: (href, newTab) =>
                                                      _navigateToHref(
                                                    context,
                                                    href,
                                                    openInNewTab: newTab,
                                                  ),
                                                ),
                                              );
                                            }

                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 24),
                                              child: _buildNavItemLink(
                                                context,
                                                nav,
                                                textColor,
                                                isEditMode: isEditMode,
                                                uppercaseLabel:
                                                    navigationUppercase,
                                              ),
                                            );
                                          }),
                                      ],
                                    ),
                                  )
                                else
                                  const Spacer(),
                                Row(
                                  children: [
                                    IconButton(
                                      key: const ValueKey(
                                        'public-store-header-search',
                                      ),
                                      icon: Icon(Icons.search,
                                          size: headerGeometry.iconSize),
                                      color: iconColor,
                                      onPressed: () =>
                                          SearchOverlay.show(context),
                                      tooltip: 'Buscar',
                                      constraints: BoxConstraints.tightFor(
                                        width: headerGeometry.iconBox,
                                        height: headerGeometry.iconBox,
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                    SizedBox(width: headerGeometry.actionGap),
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        IconButton(
                                          key: const ValueKey(
                                            'public-store-header-cart',
                                          ),
                                          icon: Icon(
                                            Icons.shopping_cart_outlined,
                                            size: headerGeometry.iconSize,
                                          ),
                                          color: iconColor,
                                          onPressed: () => _navigateToHref(
                                            context,
                                            _routeForPublicStore(
                                                '/tienda/carrito'),
                                          ),
                                          tooltip: 'Carrito',
                                          constraints: BoxConstraints.tightFor(
                                            width: headerGeometry.iconBox,
                                            height: headerGeometry.iconBox,
                                          ),
                                          padding: EdgeInsets.zero,
                                        ),
                                        if (cart.itemCount > 0)
                                          Positioned(
                                            right: 0,
                                            top: 0,
                                            child: IgnorePointer(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: accentColor,
                                                  shape: BoxShape.circle,
                                                ),
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 18,
                                                  minHeight: 18,
                                                ),
                                                child: Text(
                                                  '${cart.itemCount}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (isDesktopHeader) ...[
                                      const SizedBox(width: 10),
                                      MouseRegion(
                                        onEnter: (_) =>
                                            _warmDeferredRouteForPath(
                                          '/cuenta',
                                        ),
                                        child: CustomerAccountMenu(
                                          textColor: textColor,
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        key: const ValueKey(
                                          'public-store-header-menu',
                                        ),
                                        icon: Icon(Icons.menu,
                                            size: headerGeometry.iconSize),
                                        color: iconColor,
                                        onPressed: () => _showMobileMenu(
                                          context,
                                          projectedNavItems,
                                          isEditMode: isEditMode,
                                          canNavigate:
                                              categoryNavigationProjection
                                                  .canNavigate,
                                        ),
                                        tooltip: 'Menú',
                                        constraints: BoxConstraints.tightFor(
                                          width: headerGeometry.iconBox,
                                          height: headerGeometry.iconBox,
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                    ]
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              // Wrap with edit mode indicator if in edit mode
              if (isEditMode) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // Select header for editing in the "Editar" tab
                    final editProvider =
                        context.read<WebsiteEditModeProvider>();
                    editProvider.selectBlock('header');
                  },
                  child: Stack(
                    children: [
                      headerContent,
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.5),
                                width: 2,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Container(
                                margin: const EdgeInsets.all(4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit,
                                        color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Header',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return headerContent;
            },
          );
        });
  }

  /// Builds a layout where the header stays fixed at the top while scrolling
  /// Header starts with configured style and stays visible
  Widget _buildStickyHeaderLayout({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    required String headerColorMode,
    required bool showTopBanner,
    required bool headerShadow,
    required Color headerBgColor,
    required Color headerMenuSurfaceColor,
    required Color headerMenuRailColor,
    required List<WebsiteNavigation> navItems,
    required PublicCategoryNavigationProjection categoryNavigationProjection,
    required bool isEditMode,
    required Widget child,
    required Widget footer,
    bool allowOverlayAtTop = true,
  }) {
    // Sticky uses the scaffold that keeps header fixed at top
    return _StickyHeaderScaffold(
      // This subtree contains the routed shell. Replacing it for a CMS mode
      // change can inflate its branch Navigator GlobalKeys before the outgoing
      // subtree is deactivated, so its identity must remain mode-independent.
      key: const ValueKey('sticky_scaffold'),
      storeName: storeName,
      storeDescription: storeDescription,
      logoUrl: logoUrl,
      topBannerText: topBannerText,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      primaryColor: primaryColor,
      accentColor: accentColor,
      headerColorMode: headerColorMode,
      showTopBanner: showTopBanner,
      headerShadow: headerShadow,
      headerBgColor: headerBgColor,
      headerMenuSurfaceColor: headerMenuSurfaceColor,
      headerMenuRailColor: headerMenuRailColor,
      navItems: navItems,
      categoryNavigationProjection: categoryNavigationProjection,
      isEditMode: isEditMode,
      allowOverlayAtTop: allowOverlayAtTop,
      buildHeader: _buildHeader,
      footer: footer,
      child: child,
    );
  }

  Widget _buildMobileFooter({
    required BuildContext context,
    required List<WebsiteNavigation> footerNavItems,
    required String storeName,
    required String storeDescription,
    required String contactEmail,
    required String contactPhone,
    required String contactAddress,
    required String? facebookUrl,
    required String? instagramUrl,
    required String? twitterUrl,
    required String? youtubeUrl,
    required String? whatsappUrl,
    required Color primaryColor,
    required Color accentColor,
    required String logoUrl,
    required bool Function(WebsiteNavigation navigation) canNavigate,
    bool isEditMode = false,
    bool isPreviewMode = false, // Added for preview visibility
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    const dividerColor = Colors.white24;
    // final iconColor = primaryColor; // Unused now, switching to white

    return Container(
      color: PublicStoreTheme.textPrimary,
      padding:
          const EdgeInsets.fromLTRB(16, 32, 16, 24), // Reduced bottom padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Store Logo
          Center(
            child: SizedBox(
              height: 50,
              child: logoUrl.isNotEmpty
                  ? Stack(
                      children: [
                        // Outline layers (simulated stroke)
                        for (final offset in const [
                          Offset(-1, -1),
                          Offset(1, -1),
                          Offset(-1, 1),
                          Offset(1, 1),
                        ])
                          Transform.translate(
                            offset: offset,
                            child: Image.network(
                              logoUrl,
                              fit: BoxFit.contain,
                              color: Colors.white,
                              colorBlendMode: BlendMode.srcIn,
                            ),
                          ),
                        // Main Image
                        Image.network(
                          logoUrl,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) => Text(
                            storeName,
                            style: textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    )
                  // No configured logo: this store's own wordmark, never the
                  // bundled asset of a different tenant.
                  : Text(
                      storeName.isNotEmpty ? storeName : 'Tienda',
                      style: textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 32),

          ..._buildMobileFooterNavigationSections(
            context: context,
            footerNavItems: footerNavItems,
            titleStyle: textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
            isEditMode: isEditMode,
            canNavigate: canNavigate,
          ),

          // Collapsible: Contact
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                'CONTACTO',
                style: textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              iconColor: Colors.white,
              collapsedIconColor: Colors.white,
              childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
              children: [
                if (contactAddress.isNotEmpty)
                  _buildFooterContactItem(context, Icons.location_on_outlined,
                      contactAddress, null),
                if (contactPhone.isNotEmpty)
                  _buildFooterContactItem(
                      context,
                      Icons.phone_outlined,
                      contactPhone,
                      () => _launchUri(Uri(scheme: 'tel', path: contactPhone))),
                if (contactEmail.isNotEmpty)
                  _buildFooterContactItem(
                      context,
                      Icons.email_outlined,
                      contactEmail,
                      () => _launchUri(
                          Uri(scheme: 'mailto', path: contactEmail))),
              ],
            ),
          ),
          const Divider(color: dividerColor),

          const SizedBox(height: 32),

          if (facebookUrl != null ||
              instagramUrl != null ||
              twitterUrl != null ||
              youtubeUrl != null ||
              whatsappUrl != null ||
              isEditMode) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '¡SÍGUENOS!',
                style: textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                alignment: WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (facebookUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.facebook,
                      facebookUrl,
                      isEditMode,
                      settingKey: 'facebook',
                      label: 'Facebook',
                    ),
                  if (instagramUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.instagram,
                      instagramUrl,
                      isEditMode,
                      settingKey: 'instagram',
                      label: 'Instagram',
                    ),
                  if (twitterUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.xTwitter,
                      twitterUrl,
                      isEditMode,
                      settingKey: 'twitter',
                      label: 'Twitter/X',
                    ),
                  if (youtubeUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.youtube,
                      youtubeUrl,
                      isEditMode,
                      settingKey: 'youtube',
                      label: 'YouTube',
                    ),
                  if (whatsappUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.whatsapp,
                      whatsappUrl,
                      isEditMode,
                      settingKey: 'whatsapp',
                      label: 'WhatsApp',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],

          // Copyright
          Center(
            child: Text(
              '© ${DateTime.now().year}${storeName.isNotEmpty ? ' $storeName' : ''}. Todos los derechos reservados.',
              style: textTheme.bodySmall?.copyWith(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24), // Reduced bottom space
        ],
      ),
    );
  }

  Widget _buildDesktopSocialIcon(
    BuildContext context,
    IconData icon,
    String? url,
    bool isEditMode,
    String settingKey,
    String label, {
    bool isContact = false, // Special handling for contact items
  }) {
    if ((url == null || url.trim().isEmpty) && !isEditMode) {
      return const SizedBox.shrink();
    }

    // Determine icon color
    final hasValue = url != null && url.trim().isNotEmpty;
    final iconColor =
        hasValue ? Colors.white70 : Colors.white70.withValues(alpha: 0.35);

    // Determine tooltip
    final tooltip =
        isEditMode ? (hasValue ? 'Editar $label' : 'Agregar $label') : label;

    // Determine tap action
    VoidCallback? onTap;
    if (isEditMode) {
      onTap = () {
        if (isContact) {
          _showFooterContactEditDialog(context, settingKey, label, url ?? '');
        } else {
          _showSocialMediaEditDialog(context, settingKey, label, url);
        }
      };
    } else if (hasValue) {
      onTap = () {
        if (isContact) {
          if (settingKey == 'contact_email') {
            _launchUri(Uri(scheme: 'mailto', path: url));
          } else if (settingKey == 'contact_phone') {
            _launchUri(Uri(scheme: 'tel', path: url));
          }
        } else {
          _launchUri(Uri.parse(url));
        }
      };
    }

    return IconButton(
      icon: FaIcon(icon, color: iconColor, size: 22),
      onPressed: onTap,
      tooltip: tooltip,
    );
  }

  Widget _buildFooterLinkMobile(
    BuildContext context,
    String text,
    String route, {
    bool forceHomeRefresh = false,
    required bool isEditMode,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: InkWell(
          onTap: isEditMode
              ? null
              : () {
                  _navigateToHref(
                    context,
                    route,
                    forceHomeRefresh: forceHomeRefresh,
                  );
                },
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterContactItem(
      BuildContext context, IconData icon, String text, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFooterContactEditDialog(
    BuildContext context,
    String settingKey,
    String label,
    String currentValue,
  ) async {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final controller = TextEditingController(text: currentValue);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Editar $label'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(
                    color: Colors.black87), // Ensure visible text
                decoration: InputDecoration(
                  labelText: label,
                  hintText: _getHintForFooterContactSetting(settingKey),
                  fillColor: Colors.white,
                  filled: true,
                  prefixIcon: Icon(
                    settingKey == 'contact_phone'
                        ? Icons.phone_outlined
                        : Icons.mail_outline,
                  ),
                  helperText: settingKey == 'contact_phone'
                      ? 'Ej: +56 9 1234 5678'
                      : 'Ej: contacto@tienda.cl',
                ),
                keyboardType: settingKey == 'contact_phone'
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              editProvider.updateFooterSetting(settingKey, value);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Aplicar'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  String _getHintForFooterContactSetting(String key) {
    switch (key) {
      case 'contact_email':
        return 'contacto@tienda.cl';
      case 'contact_phone':
        return '+56 9 1234 5678';
      case 'contact_address':
        return 'Calle y número, ciudad';
      case 'whatsapp':
        return '+56 9 1234 5678';
      default:
        return '';
    }
  }

  Widget _buildSocialIconMobile(
    IconData icon,
    String? url,
    bool isEditMode, {
    required String settingKey,
    required String label,
  }) {
    if (url == null && !isEditMode) {
      return const SizedBox.shrink();
    }

    final hasUrl = url != null && url.isNotEmpty;

    return InkWell(
      onTap: () async {
        if (isEditMode) {
          // Show edit dialog
          await _showSocialMediaEditDialog(context, settingKey, label, url);
        } else if (hasUrl) {
          _launchUri(Uri.parse(url));
        }
      },
      child: Stack(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasUrl
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
              border: isEditMode && !hasUrl
                  ? Border.all(
                      color: Colors.white38,
                      width: 1,
                      strokeAlign: BorderSide.strokeAlignInside)
                  : null,
            ),
            child: Center(
              child: FaIcon(
                icon,
                color: hasUrl ? Colors.white : Colors.white38,
                size: 22,
              ),
            ),
          ),
          if (isEditMode)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: hasUrl ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasUrl ? Icons.check : Icons.edit,
                  color: Colors.white,
                  size: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSocialMediaEditDialog(
    BuildContext context,
    String settingKey,
    String label,
    String? currentValue,
  ) async {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final controller = TextEditingController(text: currentValue ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Editar $label'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(
                    color: Colors.black87), // Ensure visible text
                decoration: InputDecoration(
                  labelText: 'Usuario o URL de $label',
                  hintText: _getHintForSetting(settingKey),
                  fillColor: Colors.white,
                  filled: true,
                  prefixIcon: const Icon(Icons.link_outlined),
                  helperText: 'Puedes ingresar el @usuario o la URL completa',
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              editProvider.updateFooterSetting(settingKey, value);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Aplicar'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (saved == true && mounted) {
      setState(() {}); // Refresh to show updated value
    }
  }

  String _getHintForSetting(String key) {
    switch (key) {
      case 'facebook':
        return '@vinabike o https://facebook.com/vinabike';
      case 'instagram':
        return '@vinabike o https://instagram.com/vinabike';
      case 'twitter':
        return '@vinabike o https://twitter.com/vinabike';
      case 'youtube':
        return '@vinabikechannel o https://youtube.com/@vinabike';
      default:
        return '';
    }
  }

  Widget _buildFooter({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String contactEmail,
    required String contactPhone,
    required String contactAddress,
    required String facebookHandle,
    required String instagramHandle,
    required String twitterHandle,
    required String youtubeHandle,
    required String whatsappHandle,
    required Color primaryColor,
    required Color accentColor,
    required String logoUrl, // Added parameter
    required PublicCategoryNavigationProjection categoryNavigationProjection,
    bool isEditMode = false,
  }) {
    // The footer identity is stable across Edit/Preview/Public: the FSM
    // rebuilds it in place (inline nav editing is overlay state).
    return MediaQueryLayoutBuilder(
        key: const ValueKey('footer_layout'),
        builder: (context, constraints) {
          final websiteService = context.watch<WebsiteService>();
          final editProvider = context.watch<WebsiteEditModeProvider>();
          var footerNavItems = editProvider.getEffectiveFooterNavigation(
            websiteService.footerNavigation,
          );
          footerNavItems = _pagePublication.forAllAudiences(footerNavItems);

          // Apply pending section order from provider for live preview
          final pendingSectionOrder = editProvider.pendingFooterSectionOrder;
          if (pendingSectionOrder != null && pendingSectionOrder.isNotEmpty) {
            final orderMap = <String, int>{};
            for (var i = 0; i < pendingSectionOrder.length; i++) {
              orderMap[pendingSectionOrder[i]] = i;
            }
            footerNavItems.sort((a, b) {
              final aIdx = orderMap[a.id] ?? a.orderIndex;
              final bIdx = orderMap[b.id] ?? b.orderIndex;
              return aIdx.compareTo(bIdx);
            });
          }

          // Apply pending link order for each section - create new section objects
          final pendingLinkOrder = editProvider.pendingFooterLinkOrder;
          if (pendingLinkOrder.isNotEmpty) {
            footerNavItems = footerNavItems.map((section) {
              final linkOrder = pendingLinkOrder[section.id];
              if (linkOrder != null && linkOrder.isNotEmpty) {
                final orderMap = <String, int>{};
                for (var i = 0; i < linkOrder.length; i++) {
                  orderMap[linkOrder[i]] = i;
                }
                final sortedChildren =
                    List<WebsiteNavigation>.from(section.children)
                      ..sort((a, b) {
                        final aHas = orderMap.containsKey(a.id);
                        final bHas = orderMap.containsKey(b.id);
                        if (aHas && bHas) {
                          return orderMap[a.id]!.compareTo(orderMap[b.id]!);
                        }
                        if (aHas) return -1;
                        if (bHas) return 1;
                        return a.orderIndex.compareTo(b.orderIndex);
                      });

                return section.copyWith(children: sortedChildren);
              }
              return section;
            }).toList();
          }

          final screenWidth = MediaQuery.of(context).size.width;
          final isMobile = screenWidth < 800;
          footerNavItems = isMobile
              ? categoryNavigationProjection.forMobile(footerNavItems)
              : categoryNavigationProjection.forDesktop(footerNavItems);

          final facebookUrl =
              normalizeSocialUrl(facebookHandle, 'https://facebook.com/');
          final instagramUrl =
              normalizeSocialUrl(instagramHandle, 'https://instagram.com/');
          final twitterUrl =
              normalizeSocialUrl(twitterHandle, 'https://twitter.com/');
          final youtubeUrl = normalizeSocialUrl(
            youtubeHandle,
            'https://youtube.com/',
            keepAtPrefix: true,
          );
          final whatsappUrl = whatsappHandle.isNotEmpty
              ? 'https://wa.me/${_sanitizePhone(whatsappHandle)}?text=${Uri.encodeComponent("Hola $storeName, vengo desde el sitio web")}'
              : null;
          bool canNavigate(WebsiteNavigation navigation) =>
              _pagePublication.canNavigate(navigation) &&
              categoryNavigationProjection.canNavigate(navigation);

          if (isMobile) {
            return _buildMobileFooter(
              context: context,
              footerNavItems: footerNavItems,
              storeName: storeName,
              storeDescription: storeDescription,
              contactEmail: contactEmail,
              contactPhone: contactPhone,
              contactAddress: contactAddress,
              facebookUrl: facebookUrl,
              instagramUrl: instagramUrl,
              twitterUrl: twitterUrl,
              youtubeUrl: youtubeUrl,
              whatsappUrl: whatsappUrl,
              primaryColor: primaryColor,
              accentColor: accentColor,
              logoUrl: logoUrl,
              canNavigate: canNavigate,
              isEditMode: isEditMode,
              isPreviewMode:
                  isMobile, // Always true when this branch runs, so icons show
            );
          }

          final footerContent = Container(
            width: double.infinity,
            color: PublicStoreTheme.textPrimary,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 32,
                      runSpacing: 24,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                        SizedBox(
                          width: 250,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLogo(
                                context: context,
                                logoUrl: logoUrl,
                                storeName: storeName,
                                textColor: Colors.white,
                                isDarkMode: true,
                                height: 60,
                                alignment: Alignment.centerLeft,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                storeDescription.isNotEmpty
                                    ? storeDescription
                                    : 'Información pública de la tienda.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Colors.white70,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 8,
                                children: [
                                  // Facebook
                                  if (facebookUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.facebook,
                                      facebookUrl,
                                      isEditMode,
                                      'facebook',
                                      'Facebook',
                                    ),
                                  // Instagram
                                  if (instagramUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.instagram,
                                      instagramUrl,
                                      isEditMode,
                                      'instagram',
                                      'Instagram',
                                    ),
                                  // Twitter
                                  if (twitterUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.xTwitter,
                                      twitterUrl,
                                      isEditMode,
                                      'twitter',
                                      'Twitter',
                                    ),
                                  // YouTube
                                  if (youtubeUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.youtube,
                                      youtubeUrl,
                                      isEditMode,
                                      'youtube',
                                      'YouTube',
                                    ),
                                  // WhatsApp
                                  if (whatsappUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.whatsapp,
                                      whatsappUrl,
                                      isEditMode,
                                      'whatsapp',
                                      'WhatsApp',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ..._buildFooterNavigationColumnsDesktop(
                          context: context,
                          footerNavItems: footerNavItems,
                          primaryColor: primaryColor,
                          isEditMode: isEditMode,
                          canNavigate: canNavigate,
                        ),
                        SizedBox(
                          width: 200,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contacto',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              if (contactAddress.isNotEmpty) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.location_on_outlined,
                                        color: Colors.white70, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        contactAddress,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.white70,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (contactPhone.isNotEmpty) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.phone_outlined,
                                        color: Colors.white70, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      contactPhone,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white70,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (contactEmail.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.email_outlined,
                                        color: Colors.white70, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      contactEmail,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white70,
                                          ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Accepted payment methods are a commercial claim, so
                    // they render only from the tenant-scoped server
                    // capability.
                    ..._buildPaymentBadges(
                      context,
                      context.read<PublicStoreTenantProvider>().tenantId,
                    ),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 24),
                    Text(
                      '© ${DateTime.now().year}${storeName.isNotEmpty ? ' $storeName' : ''}. Todos los derechos reservados.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );

          // Wrap with edit mode indicator if in edit mode
          if (isEditMode) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // Select footer for editing in the "Editar" tab
                final editProvider = context.read<WebsiteEditModeProvider>();
                editProvider.selectBlock('footer');
              },
              child: Stack(
                children: [
                  footerContent,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Footer',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return footerContent;
        });
  }

  List<Widget> _buildFooterNavigationColumnsDesktop({
    required BuildContext context,
    required List<WebsiteNavigation> footerNavItems,
    required Color primaryColor,
    required bool isEditMode,
    required bool Function(WebsiteNavigation navigation) canNavigate,
  }) {
    final desktopItems = footerNavItems
        .where((n) => n.isVisible)
        .where((n) => n.showOnDesktop)
        .toList();

    if (desktopItems.isEmpty) {
      // Navigation is editor-owned. When nothing is persisted for this
      // audience the footer shows no link column at all: a renderer-invented
      // "Inicio / Productos / Servicios / Contacto" set advertised routes the
      // owner never placed, and kept advertising them after the owner removed
      // them. An absent column is honest; a fabricated one is not.
      return const <Widget>[];
    }

    final sectionParents = desktopItems
        .where((parent) => _footerNavigableDescendants(
              parent.children,
              desktop: true,
              canNavigate: canNavigate,
            ).isNotEmpty)
        .toList();

    if (sectionParents.isNotEmpty) {
      return sectionParents.map((parent) {
        final children = _footerNavigableDescendants(
          parent.children,
          desktop: true,
          canNavigate: canNavigate,
        );

        return SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parent.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              for (final child in children)
                _buildFooterNavLinkDesktop(context, child,
                    isEditMode: isEditMode),
            ],
          ),
        );
      }).toList();
    }

    // Flat list
    return [
      SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enlaces',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            for (final nav in desktopItems)
              if (canNavigate(nav))
                _buildFooterNavLinkDesktop(
                  context,
                  nav,
                  isEditMode: isEditMode,
                ),
          ],
        ),
      ),
    ];
  }

  Widget _buildFooterNavLinkDesktop(
    BuildContext context,
    WebsiteNavigation nav, {
    required bool isEditMode,
  }) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final effective = editProvider.getEffectiveFooterNavItem(nav);

    final href = _routeForPublicStore(effective.href ?? '/');
    final isActive = GoRouterState.of(context).matchedLocation == href;
    final isInlineEditing = isEditMode && _activeInlineFooterNavId == nav.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isInlineEditing
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _inlineFooterNavLabelController,
                        focusNode: _inlineFooterNavLabelFocusNode,
                        onChanged: (value) =>
                            editProvider.updateFooterNavLabel(nav.id, value),
                        cursorColor: Colors.white,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight:
                                  isActive ? FontWeight.bold : FontWeight.w500,
                            ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.10),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.42),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar destino',
                    onPressed: () => _showInlineFooterNavDestinationDialog(
                      context,
                      editProvider,
                      effective,
                    ),
                    icon: const Icon(Icons.link, size: 18, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Terminar',
                    onPressed: () {
                      setState(() => _activeInlineFooterNavId = null);
                      editProvider.selectFooterNavItem(null);
                    },
                    icon:
                        const Icon(Icons.check, size: 18, color: Colors.white),
                  ),
                ],
              ),
            )
          : MouseRegion(
              cursor: isEditMode ? SystemMouseCursors.click : MouseCursor.defer,
              onEnter:
                  isEditMode ? null : (_) => _warmDeferredRouteForPath(href),
              child: InkWell(
                onTap: isEditMode
                    ? () => _beginInlineFooterNavEdit(editProvider, effective)
                    : () {
                        _navigateToHref(
                          context,
                          href,
                          openInNewTab: effective.openInNewTab,
                        );
                      },
                child: Text(
                  effective.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                ),
              ),
            ),
    );
  }

  List<Widget> _buildMobileFooterNavigationSections({
    required BuildContext context,
    required List<WebsiteNavigation> footerNavItems,
    required TextStyle? titleStyle,
    required bool isEditMode,
    required bool Function(WebsiteNavigation navigation) canNavigate,
  }) {
    final theme = Theme.of(context);
    const dividerColor = Colors.white24;

    final mobileItems = footerNavItems
        .where((n) => n.isVisible)
        .where((n) => n.showOnMobile)
        .toList();

    if (mobileItems.isEmpty) {
      // Same contract as desktop: only persisted navigation renders. The
      // mobile footer therefore drops its accordion entirely rather than
      // offering fabricated quick links.
      return const <Widget>[];
    }

    final sectionParents = mobileItems
        .where((parent) => _footerNavigableDescendants(
              parent.children,
              desktop: false,
              canNavigate: canNavigate,
            ).isNotEmpty)
        .toList();

    if (sectionParents.isNotEmpty) {
      final sections = <Widget>[];
      for (final parent in sectionParents) {
        final children = _footerNavigableDescendants(
          parent.children,
          desktop: false,
          canNavigate: canNavigate,
        );

        sections.add(
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(parent.label.toUpperCase(), style: titleStyle),
              iconColor: Colors.white,
              collapsedIconColor: Colors.white,
              childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
              children: [
                for (final child in children)
                  _buildFooterNavLinkMobile(
                    context,
                    child,
                    isEditMode: isEditMode,
                  ),
              ],
            ),
          ),
        );
        sections.add(const Divider(color: dividerColor));
      }

      return sections;
    }

    return [
      Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text('ENLACES', style: titleStyle),
          iconColor: Colors.white,
          collapsedIconColor: Colors.white,
          childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
          children: [
            for (final nav in mobileItems)
              if (canNavigate(nav))
                _buildFooterNavLinkMobile(
                  context,
                  nav,
                  isEditMode: isEditMode,
                ),
          ],
        ),
      ),
      const Divider(color: dividerColor),
    ];
  }

  List<WebsiteNavigation> _footerNavigableDescendants(
    Iterable<WebsiteNavigation> nodes, {
    required bool desktop,
    required bool Function(WebsiteNavigation navigation) canNavigate,
  }) {
    final result = <WebsiteNavigation>[];

    void visit(Iterable<WebsiteNavigation> current) {
      for (final node in current) {
        final visibleForAudience = node.isVisible &&
            (desktop ? node.showOnDesktop : node.showOnMobile);
        if (!visibleForAudience) continue;
        if (canNavigate(node)) {
          result.add(node);
        } else {
          // Footer columns are one link level deep. Promote published
          // descendants through a structural unpublished category instead of
          // rendering the grouping as a broken link or dropping its children.
          visit(node.children);
        }
      }
    }

    visit(nodes);
    return result;
  }

  Widget _buildFooterNavLinkMobile(
    BuildContext context,
    WebsiteNavigation nav, {
    required bool isEditMode,
  }) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final effective = editProvider.getEffectiveFooterNavItem(nav);

    final href = _routeForPublicStore(effective.href ?? '/');
    final isInlineEditing = isEditMode && _activeInlineFooterNavId == nav.id;

    if (!isEditMode) {
      return _buildFooterLinkMobile(
        context,
        effective.label,
        href,
        isEditMode: false,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isInlineEditing
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inlineFooterNavLabelController,
                      focusNode: _inlineFooterNavLabelFocusNode,
                      onChanged: (value) =>
                          editProvider.updateFooterNavLabel(nav.id, value),
                      cursorColor: Colors.white,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.10),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.42),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Destino',
                    onPressed: () => _showInlineFooterNavDestinationDialog(
                      context,
                      editProvider,
                      effective,
                    ),
                    icon: const Icon(Icons.link, size: 18, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'OK',
                    onPressed: () {
                      setState(() => _activeInlineFooterNavId = null);
                      editProvider.selectFooterNavItem(null);
                    },
                    icon:
                        const Icon(Icons.check, size: 18, color: Colors.white),
                  ),
                ],
              ),
            )
          : InkWell(
              onTap: () => _beginInlineFooterNavEdit(editProvider, effective),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 14, color: Colors.white70),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        effective.label,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLogo({
    required BuildContext context,
    required String logoUrl,
    required String storeName,
    required Color textColor,
    required bool isDarkMode,
    double height = 48,
    double? maxWidth,
    Alignment alignment = Alignment.center,
  }) {
    Widget applyContrast(Widget child) {
      if (!isDarkMode) return child;
      return ColorFiltered(
        colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
        child: child,
      );
    }

    // 1. Try Network URL if available
    if (logoUrl.isNotEmpty) {
      return Container(
        height: height,
        constraints: maxWidth == null
            ? const BoxConstraints()
            : BoxConstraints(maxWidth: maxWidth),
        alignment: alignment,
        child: applyContrast(
          Image.network(
            logoUrl,
            fit: BoxFit.contain,
            // A broken logo URL falls back to this store's own wordmark.
            // The bundled asset is one specific tenant's logo and must never
            // stand in for another store's identity.
            errorBuilder: (context, error, stackTrace) =>
                _buildTextLogo(context, storeName, textColor),
          ),
        ),
      );
    }

    // 2. No configured logo: this store's typographic wordmark.
    return Container(
      height: height,
      constraints: maxWidth == null
          ? const BoxConstraints()
          : BoxConstraints(maxWidth: maxWidth),
      alignment: alignment,
      child: applyContrast(_buildTextLogo(context, storeName, textColor)),
    );
  }

  Widget _buildTextLogo(
      BuildContext context, String storeName, Color primaryColor) {
    return Text(
      storeName.isNotEmpty ? storeName.toUpperCase() : 'Tienda',
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
    );
  }

  Future<void> _navigateToHref(
    BuildContext context,
    String href, {
    bool openInNewTab = false,
    bool forceHomeRefresh = false,
  }) async {
    final authored = href.trim();
    final normalized = WebsiteDestination.normalizeHref(
      authored,
      internalOrigins: _storefrontInternalOrigins,
    );
    if (normalized.isEmpty) return;
    if (!_allowsPublicHref(normalized)) {
      debugPrint(
        '[PublicStoreLayout] Blocked unpublished category destination: '
        '$normalized',
      );
      return;
    }
    final authoredUri = Uri.tryParse(authored);
    final authoredIsAbsoluteHttp = authoredUri != null &&
        (authoredUri.scheme == 'http' || authoredUri.scheme == 'https');
    final normalizedUri = Uri.tryParse(normalized);
    final launchesExternalWindow = authoredIsAbsoluteHttp &&
        normalizedUri != null &&
        (normalizedUri.scheme == 'http' || normalizedUri.scheme == 'https');
    final editProvider = context.read<WebsiteEditModeProvider>();
    final editorMode = editProvider.mode;
    final isEditMode = editorMode == WebsiteEditorMode.edit;
    final normalizedTargetPath = normalizedUri?.path.trim().toLowerCase();
    final isRequestedHomeTarget = const <String>{
      '/',
      '/inicio',
      '/home',
      '/tienda',
      '/tienda/',
      '/tienda/inicio',
      '/tienda/home',
    }.contains(normalizedTargetPath);
    final replacesBrowserDocument =
        kIsWeb && forceHomeRefresh && isRequestedHomeTarget && !isEditMode;
    final keepsCurrentPage = openInNewTab ||
        normalized.startsWith('#') ||
        PublicStoreLayout._isCurrentLocation(context, normalized);
    final editorDecision = await WebsiteEditorNavigationGuard.authorize(
      context,
      intent: WebsiteEditorNavigationGuard.classifyIntent(
        openInNewTab: openInNewTab,
        launchesExternalWindow: launchesExternalWindow,
        keepsCurrentPage: keepsCurrentPage,
        replacesBrowserDocument: replacesBrowserDocument,
      ),
    );
    if (!editorDecision.isAllowed) return;
    if (!context.mounted) return;
    if (!keepsCurrentPage &&
        !await PublicStoreLayout.authorizeCheckoutExit(context)) {
      return;
    }
    if (!context.mounted) return;

    // Ensure any open mega menu closes before navigation so the configured
    // header surface returns to its normal overlay/solid state.
    MegaMenuController.instance.closeMenu();

    // Sometimes website blocks/navigation store a bare UUID as a link target.
    // This can be either a product id OR a website_pages.id. Normalize to a
    // real route so we don't hit go_router 404s.
    final uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{12}$',
    );
    String internalHref = normalized;
    String? uuid;
    if (uuidRe.hasMatch(internalHref)) {
      uuid = internalHref;
    } else if (internalHref.startsWith('/') &&
        uuidRe.hasMatch(internalHref.substring(1))) {
      uuid = internalHref.substring(1);
    }

    if (uuid != null) {
      // A legacy bare UUID is not a canonical destination. It may name a CMS
      // page **or** a product, so it navigates only when exactly one public
      // owner of this tenant claims it.
      //
      // Both sides are always evaluated. Resolving page-first and returning
      // early meant a UUID owned by a public page *and* a public product
      // silently picked the page — an ambiguous reference resolved by
      // evaluation order rather than refused.
      final websiteService = context.read<WebsiteService>();
      final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
      if (tenantId == null || tenantId.trim().isEmpty) {
        debugPrint(
          '[PublicStoreLayout] Legacy UUID destination without an active '
          'tenant is inert: $uuid',
        );
        return;
      }

      if (!websiteService.hasAuthoritativePagePublicationForTenant(tenantId)) {
        await websiteService.loadPagesForTenant(tenantId);
        if (!context.mounted) return;
      }
      // Unknown page authority is fail-closed: without it we cannot prove the
      // page side is *not* an owner, so we cannot prove uniqueness either.
      if (!websiteService.hasAuthoritativePagePublicationForTenant(tenantId)) {
        debugPrint(
          '[PublicStoreLayout] Legacy UUID destination blocked: page '
          'publication for this tenant is unknown: $uuid',
        );
        return;
      }

      // Page candidate: only from the authoritative tenant-scoped collection.
      // The previous `getPageById(uuid)` fallback queried `website_pages` by
      // id alone, so it could read another tenant's row, and it accepted that
      // row outright whenever the active tenant was unknown.
      final ownedPage = websiteService.pages.cast<WebsitePage?>().firstWhere(
            (p) => p?.id == uuid && p?.tenantId == tenantId,
            orElse: () => null,
          );
      final pageSlug = ownedPage?.slug.trim() ?? '';
      final pageIsPublicOwner = ownedPage != null &&
          ownedPage.isPublished &&
          pageSlug.isNotEmpty &&
          _pagePublication.allowsHref(ownedPage.fullPath);

      String? pageHref;
      if (pageIsPublicOwner) {
        const directSlugs = <String>{
          'productos',
          'contacto',
          'nosotros',
          'terminos',
          'privacidad',
          'devoluciones',
          'envios',
          'carrito',
          'checkout',
          'cuenta',
        };
        if (pageSlug == 'inicio' || pageSlug == 'home') {
          pageHref = '/';
        } else if (directSlugs.contains(pageSlug)) {
          pageHref = '/$pageSlug';
        } else {
          pageHref = '/pagina/$pageSlug';
        }
      }

      // Product candidate: tenant-scoped and filtered by the same public
      // visibility policy the storefront catalog uses.
      final product =
          await context.read<PublicInventoryService>().getProductById(
                productId: uuid,
                tenantId: tenantId,
                policy: PublicProductVisibilityPolicy.fromSettings(
                  websiteService.settings,
                ),
              );
      if (!context.mounted) return;
      final productHref = product == null ? null : publicProductPath(product);

      final owners = <String>[
        if (pageHref != null) pageHref,
        if (productHref != null) productHref,
      ];
      if (owners.length != 1) {
        debugPrint(
          '[PublicStoreLayout] Legacy UUID destination has '
          '${owners.length} public owners, expected exactly one: $uuid',
        );
        return;
      }
      internalHref = owners.single;
    }

    // UUID-backed CMS links are classified only after resolving the owning
    // page. Apply the same publication guard again to the canonical route so
    // legacy authored references cannot bypass website_pages.is_published.
    if (!_allowsPublicHref(internalHref)) {
      debugPrint(
        '[PublicStoreLayout] Blocked unpublished resolved destination: '
        '$internalHref',
      );
      return;
    }

    // Preserve an explicitly authored new-tab contract even when the absolute
    // URL points back to this storefront. Same-store links otherwise continue
    // below as normalized internal routes so they share guards and history.
    if (authoredIsAbsoluteHttp && (normalized == authored || openInNewTab)) {
      if (authoredUri.host.isNotEmpty) {
        final didLaunch = await launchUrl(
          authoredUri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: openInNewTab ? '_blank' : '_self',
        );
        if (didLaunch) editorDecision.commit();
      }
      return;
    }

    // Anchor links (best-effort on web)
    if (normalized.startsWith('#')) {
      if (!editorDecision.commit()) return;
      if (kIsWeb) {
        setLocationHash(normalized);
      }
      return;
    }

    // Normalize internal relative paths like 'productos' to '/productos'.
    // Some CMS/DB-stored links omit the leading '/', which can lead to
    // inconsistent URL updates on web.
    final parsedInternal = Uri.tryParse(internalHref);
    if (parsedInternal != null &&
        parsedInternal.scheme.isEmpty &&
        internalHref.isNotEmpty &&
        !internalHref.startsWith('/') &&
        !internalHref.startsWith('?')) {
      internalHref = '/$internalHref';
    }

    // Normalize common "home" aliases so they behave like a real home
    // navigation (including scroll-to-top behavior).
    final internalPath =
        (Uri.tryParse(internalHref)?.path ?? internalHref).trim().toLowerCase();
    if (internalPath == '/inicio' || internalPath == '/home') {
      internalHref = '/';
    } else if (internalPath == '/tienda/inicio' ||
        internalPath == '/tienda/home') {
      internalHref = '/tienda';
    }

    // Re-normalize the internal route against the current runtime.
    // This is critical in preview/editor contexts where callers may pass a
    // clean store route (`/`) while the ERP-mounted shell actually needs
    // `/tienda`, or vice versa.
    internalHref = _routeForPublicStore(internalHref);

    // Internal navigation. The FSM is the only mode owner: every internal
    // route carries the canonical mode projection, so each history entry
    // replays its mode as a route command (browser Back/forward included).
    final targetUri = Uri.tryParse(internalHref);
    var target = internalHref;
    if (targetUri != null && targetUri.scheme.isEmpty) {
      target =
          projectWebsiteEditorModeOntoUri(targetUri, editorMode).toString();
    }

    // Avoid redundant navigation.
    final current = GoRouterState.of(context).uri.toString();

    // Prefer go() for top-level navigation (header/footer) on web to avoid
    // stacking routes (Navigator keeps prior routes offstage, which can
    // exacerbate "RenderBox was not laid out" failures and lead to blank
    // frames). Keep push() for detail routes like product pages.
    final targetPath = Uri.tryParse(target)?.path ?? target;
    _warmDeferredRouteForPath(targetPath);
    final isHomeTarget = targetPath == '/' ||
        targetPath == '/tienda' ||
        targetPath == '/tienda/';
    final shouldReplace = _shouldReplaceForPublicStoreNav(targetPath);
    final shouldResetTargetScroll =
        _shouldResetScrollForPublicStoreNav(targetPath);

    // A product-to-product navigation can reuse the same GoRouter page/state
    // because only path parameters changed. Queue an explicit reset for the
    // destination so related-product clicks never inherit the previous
    // detail's below-the-fold scroll offset.
    if (shouldResetTargetScroll) {
      final scrollState = context.read<PublicStoreScrollState>();
      scrollState.requestScrollToTop(target);
      scrollState.requestScrollToTopForPath(targetPath);
    }

    // The logo/Inicio action is also the storefront's explicit clean refresh.
    // Keep ordinary navigation soft, but preserve this deliberate escape hatch
    // so customers can reload the latest deployment and origin-backed state.
    if (kIsWeb && forceHomeRefresh && isHomeTarget && !isEditMode) {
      try {
        final currentPath = Uri.parse(web.window.location.href).path;
        final desiredPath = targetPath.isEmpty ? '/' : targetPath;

        if (currentPath == desiredPath) {
          if (!editorDecision.commit()) return;
          web.window.location.reload();
        } else {
          if (!editorDecision.commit()) return;
          web.window.location.assign(target);
        }
        return;
      } catch (_) {
        // Fall through to normal navigation outside a browser runtime.
      }
    }

    // If we're already on the target route, still honor explicit "home"
    // navigations (logo / Inicio) by scrolling to top and revalidating through
    // the normal data owners. A browser reload would discard the persistent
    // shell and make returning home feel like a cold launch.
    if (current == target) {
      if (shouldReplace) {
        context.read<PublicStoreScrollState>().requestScrollToTop(target);
        context
            .read<PublicStoreScrollState>()
            .requestScrollToTopForPath(targetPath);
      }

      if (isHomeTarget) {
        context.read<PublicStoreScrollState>().requestScrollToTopForPath('/');
        context
            .read<PublicStoreScrollState>()
            .requestScrollToTopForPath('/tienda');
      }

      if (forceHomeRefresh && isHomeTarget) {
        context.read<PublicStoreScrollState>().requestHomeRefresh();
      }
      return;
    }

    if (shouldReplace) {
      // Explicit "home" navigations (logo / Inicio) should land at the top,
      // even if we pop-to-root (which would otherwise preserve scroll).
      context.read<PublicStoreScrollState>().requestScrollToTop(target);
      context
          .read<PublicStoreScrollState>()
          .requestScrollToTopForPath(targetPath);

      if (isHomeTarget) {
        context.read<PublicStoreScrollState>().requestScrollToTopForPath('/');
        context
            .read<PublicStoreScrollState>()
            .requestScrollToTopForPath('/tienda');
      }

      if (forceHomeRefresh) {
        context.read<PublicStoreScrollState>().requestHomeRefresh();
      }

      // For home navigation, always use go() directly instead of the pop loop.
      // The pop-to-root approach was causing blank screen issues on production
      // because the context becomes invalid after multiple pops, and the
      // postFrameCallback couldn't reliably navigate to the target.
      // Using go() directly is more reliable and handles the browser history
      // correctly on web.
      if (!editorDecision.commit()) return;
      context.go(target);
    } else {
      if (!editorDecision.commit()) return;
      context.push(target);
    }
  }

  void _warmDeferredRouteForPath(String path) {
    var normalized = path.trim().toLowerCase();
    if (normalized.startsWith('/tienda/')) {
      normalized = normalized.substring('/tienda'.length);
    } else if (normalized == '/tienda') {
      normalized = '/';
    }

    if (normalized == '/cuenta' || normalized.startsWith('/cuenta/')) {
      DeferredCustomerRoutePage.preload().ignore();
    }
    if (normalized == '/checkout' || normalized.startsWith('/pedido/')) {
      DeferredCommerceRoutePage.preload().ignore();
    }

    String? cmsSlug;
    const policySlugs = <String>{
      '/nosotros',
      '/terminos',
      '/privacidad',
      '/devoluciones',
      '/envios',
    };
    if (policySlugs.contains(normalized)) {
      cmsSlug = normalized.substring(1);
    } else if (normalized.startsWith('/pagina/')) {
      cmsSlug = Uri.decodeComponent(normalized.substring('/pagina/'.length));
    }
    if (cmsSlug == null || cmsSlug.isEmpty || !mounted) return;

    final editProvider = context.read<WebsiteEditModeProvider>();
    if (editProvider.isInEditorContext) return;
    final tenantId =
        context.read<PublicStoreTenantProvider>().tenantId?.trim() ?? '';
    if (tenantId.isEmpty) return;
    context
        .read<WebsiteService>()
        .prefetchPageWithBlocks(cmsSlug, tenantId: tenantId)
        .ignore();
  }

  bool _shouldReplaceForPublicStoreNav(String path) {
    final p = path.trim().toLowerCase();
    if (p.isEmpty) return true;

    // Normalize legacy ERP-mounted store routes.
    var normalized = p;
    if (normalized == '/tienda') return true;
    if (normalized == '/tienda/') return true;
    if (normalized.startsWith('/tienda/')) {
      normalized = normalized.substring('/tienda'.length);
      if (normalized.isEmpty) normalized = '/';
    }

    // Home
    if (normalized == '/') return true;

    // Catalog collections are destinations in their own right. Navigating to
    // one from a product breadcrumb or mega-menu must replace the detail
    // route; pushing it can duplicate the category page key that already sits
    // underneath the detail in Navigator's stack. The catalog page itself
    // still owns root -> category as a push so its editor transition remains
    // stable.
    if (normalized == '/productos') return true;
    if (normalized == '/servicios') return true;
    if (normalized.startsWith('/productos/categoria/')) return true;
    if (normalized.startsWith('/servicios/categoria/')) return true;

    // Product and service detail routes remain push navigations.
    if (normalized.startsWith('/productos/')) return false;
    if (normalized.startsWith('/servicios/')) return false;

    // Top-level pages
    const topLevelExact = <String>{
      '/contacto',
      '/carrito',
      '/checkout',
      '/cuenta',
      '/cuenta/login',
      '/nosotros',
      '/terminos',
      '/privacidad',
      '/devoluciones',
      '/envios',
    };
    if (topLevelExact.contains(normalized)) return true;

    // Custom pages
    if (normalized.startsWith('/pagina/')) return true;

    return false;
  }

  bool _shouldResetScrollForPublicStoreNav(String path) {
    var normalized = path.trim().toLowerCase();
    if (normalized.startsWith('/tienda/')) {
      normalized = normalized.substring('/tienda'.length);
    }

    if (normalized.startsWith('/producto/')) return true;
    if (normalized.startsWith('/productos/')) {
      return !normalized.startsWith('/productos/categoria/');
    }
    if (normalized.startsWith('/servicios/')) {
      return !normalized.startsWith('/servicios/categoria/');
    }
    return false;
  }

  Widget _buildNavItemLink(
    BuildContext context,
    WebsiteNavigation nav,
    Color primaryColor, {
    bool isEditMode = false,
    bool uppercaseLabel = false,
  }) {
    final href = _routeForPublicStore(nav.href ?? '/');
    final isActive = GoRouterState.of(context).matchedLocation == href;

    return MouseRegion(
      onEnter: isEditMode ? null : (_) => _warmDeferredRouteForPath(href),
      child: InkWell(
        onTap: isEditMode
            ? null
            : () {
                _navigateToHref(context, href, openInNewTab: nav.openInNewTab);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? primaryColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Semantics(
            label: nav.label,
            excludeSemantics: true,
            child: Text(
              uppercaseLabel ? nav.label.toUpperCase() : nav.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    letterSpacing: 0.1,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive
                        ? primaryColor
                        : (primaryColor == Colors.white
                            ? Colors.white
                            : PublicStoreTheme.textPrimary),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMobileMenu(
    BuildContext context,
    List<WebsiteNavigation> navItems, {
    required bool isEditMode,
    required bool Function(WebsiteNavigation navigation) canNavigate,
  }) {
    _warmDeferredRouteForPath('/cuenta');
    // IMPORTANT: The bottom-sheet builder gets its own BuildContext. After
    // `Navigator.pop(sheetContext)`, that context can be disposed; using it for
    // navigation can make taps appear to do nothing (especially on mobile).
    final navContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        // Access provider here inside the builder to ensure we have context.
        final accountService = sheetContext.watch<CustomerAccountService>();
        final isAuthenticated = accountService.isAuthenticated;
        final theme = Theme.of(sheetContext);
        final colors = theme.colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                // Account Section (Top)
                if (isAuthenticated) ...[
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.person_rounded,
                    label: 'Mi Cuenta',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _navigateToHref(
                        navContext,
                        _routeForPublicStore('/tienda/cuenta'),
                      );
                    },
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Divider(color: colors.outlineVariant),
                  ),
                ] else ...[
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.login_rounded,
                    label: 'Iniciar Sesión',
                    color: colors.primary,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _navigateToHref(
                        navContext,
                        _routeForPublicStore('/tienda/cuenta/login'),
                      );
                    },
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Divider(color: colors.outlineVariant),
                  ),
                ],

                // Navigation items
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.62,
                  ),
                  child: SingleChildScrollView(
                    child: Builder(
                      builder: (context) {
                        final visibleNavigation = navItems
                            .where(
                                (item) => item.isVisible && item.showOnMobile)
                            .toList()
                          ..sort(
                              (a, b) => a.orderIndex.compareTo(b.orderIndex));

                        if (visibleNavigation.isEmpty) {
                          if (!isEditMode) {
                            return const SizedBox.shrink();
                          }
                          return _buildMobileMenuItem(
                            sheetContext,
                            icon: Icons.add_link_rounded,
                            label: 'Configurar navegación',
                            color: colors.primary,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _openWorkspacePanel(
                                WebsiteWorkspacePanel.navigation,
                              );
                            },
                          );
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: visibleNavigation
                              .map(
                                (nav) => _buildMobileNavigationNode(
                                  sheetContext,
                                  nav,
                                  canNavigate: canNavigate,
                                  onNavigate: (target) {
                                    if (!canNavigate(target)) return;
                                    Navigator.pop(sheetContext);
                                    final href = _routeForPublicStore(
                                      target.href ?? '/',
                                    );
                                    _navigateToHref(
                                      navContext,
                                      href,
                                      openInNewTab: target.openInNewTab,
                                    );
                                  },
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ),
                ),

                // Logout at bottom (only if authenticated)
                if (isAuthenticated) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Divider(color: colors.outlineVariant),
                  ),
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.logout_rounded,
                    label: 'Cerrar Sesión',
                    color: colors.error,
                    onTap: () async {
                      final signedOut = await PublicStoreLayout.signOutCustomer(
                        navContext,
                        accountService,
                      );
                      if (!signedOut) return;
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                      if (navContext.mounted) {
                        ScaffoldMessenger.of(navContext).showSnackBar(
                          const SnackBar(
                            content: Text('Sesión cerrada correctamente'),
                          ),
                        );
                      }
                    },
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileNavigationNode(
    BuildContext context,
    WebsiteNavigation navigation, {
    required ValueChanged<WebsiteNavigation> onNavigate,
    required bool Function(WebsiteNavigation navigation) canNavigate,
    int depth = 0,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hrefUri = Uri.tryParse(navigation.href?.trim() ?? '');
    final isDirectCategory = hrefUri != null &&
        WebsiteCatalogQuery.tryParse(hrefUri)?.categoryScope ==
            WebsiteCatalogCategoryScope.direct;
    final children = navigation.children
        .where((child) => child.isVisible && child.showOnMobile)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    if (children.isEmpty) {
      return _buildMobileMenuItem(
        context,
        icon: depth == 0
            ? Icons.arrow_forward_rounded
            : Icons.subdirectory_arrow_right_rounded,
        label: navigation.label,
        subtitle: isDirectCategory ? 'Solo esta categoría' : null,
        depth: depth,
        onTap: () => onNavigate(navigation),
      );
    }

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('mobile-nav-${navigation.id}'),
        tilePadding: EdgeInsets.only(
          left: 24 + (depth * 14),
          right: 20,
        ),
        childrenPadding: EdgeInsets.only(left: 12 + (depth * 8)),
        leading: Icon(
          Icons.folder_outlined,
          color: colors.onSurfaceVariant,
          size: 21,
        ),
        title: Text(
          navigation.label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconColor: colors.primary,
        collapsedIconColor: colors.onSurfaceVariant,
        backgroundColor: colors.primary.withValues(alpha: 0.035),
        collapsedBackgroundColor: Colors.transparent,
        maintainState: true,
        children: [
          if (canNavigate(navigation) &&
              navigation.href?.trim().isNotEmpty == true)
            _buildMobileMenuItem(
              context,
              icon: Icons.arrow_forward_rounded,
              label: 'Ver todo ${navigation.label}',
              color: colors.primary,
              depth: depth + 1,
              onTap: () => onNavigate(navigation),
            ),
          ...children.map(
            (child) => _buildMobileNavigationNode(
              context,
              child,
              onNavigate: onNavigate,
              canNavigate: canNavigate,
              depth: depth + 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
    int depth = 0,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveColor = color ?? colors.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: colors.primary.withValues(alpha: 0.08),
        hoverColor: colors.primary.withValues(alpha: 0.045),
        child: Container(
          padding: EdgeInsets.only(
            left: 24 + (depth * 14),
            right: 20,
            top: 14,
            bottom: 14,
          ),
          child: Row(
            children: [
              Icon(icon, color: effectiveColor, size: 21),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: effectiveColor,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: effectiveColor.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openConfigHub(_EditorConfigHubTab tab) {
    context
        .read<WebsiteEditModeProvider>()
        .openWorkspace(_workspaceModeForConfigTab(tab));
    setState(() {
      _configHubTab = tab;
      _isConfigHubOpen = true;
    });
  }

  void _openWorkspacePanel(WebsiteWorkspacePanel panel) {
    switch (panel) {
      case WebsiteWorkspacePanel.pages:
        _openConfigHub(_EditorConfigHubTab.sitePages);
        return;
      case WebsiteWorkspacePanel.navigation:
        _openConfigHub(_EditorConfigHubTab.siteNavigation);
        return;
      case WebsiteWorkspacePanel.destinations:
        _openConfigHub(_EditorConfigHubTab.siteDestinations);
        return;
      case WebsiteWorkspacePanel.catalogProducts:
        setState(() => _catalogTab = _EditorCatalogTab.products);
        _openConfigHub(_EditorConfigHubTab.ecomCatalog);
        return;
      case WebsiteWorkspacePanel.catalogCategories:
        setState(() {
          _catalogTab = _EditorCatalogTab.categories;
          _categoryTab = _EditorCategoryTab.publication;
        });
        _openConfigHub(_EditorConfigHubTab.ecomCatalog);
        return;
    }
  }

  void _closeConfigHub() {
    context.read<WebsiteEditModeProvider>().returnToPageEditor();
    if (_isConfigHubOpen) {
      setState(() => _isConfigHubOpen = false);
    }
  }

  WebsiteWorkspaceMode _workspaceModeForConfigTab(_EditorConfigHubTab tab) {
    switch (tab) {
      case _EditorConfigHubTab.ecomCatalog:
        return WebsiteWorkspaceMode.catalog;
      case _EditorConfigHubTab.sitePages:
      case _EditorConfigHubTab.siteNavigation:
      case _EditorConfigHubTab.siteDestinations:
        return WebsiteWorkspaceMode.structure;
      case _EditorConfigHubTab.siteSettings:
      case _EditorConfigHubTab.seo:
      case _EditorConfigHubTab.integrations:
      case _EditorConfigHubTab.paymentMethods:
      case _EditorConfigHubTab.domain:
        return WebsiteWorkspaceMode.settings;
      case _EditorConfigHubTab.siteHub:
      case _EditorConfigHubTab.ecomOrders:
      case _EditorConfigHubTab.reportsAnalytics:
        return WebsiteWorkspaceMode.operations;
    }
  }

  Widget _buildConfigHubOverlay() {
    final theme = Theme.of(context);

    Widget buildBody() {
      if (_configHubTab == _EditorConfigHubTab.domain) {
        return _buildDomainAndUrlPanel();
      }

      return FutureBuilder(
        future: _ensureErpLibraryLoaded(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              ),
            );
          }

          switch (_configHubTab) {
            // Site
            case _EditorConfigHubTab.siteHub:
              return erp.WebsiteManagementPage(embedded: true);
            case _EditorConfigHubTab.sitePages:
              return erp.PageManagementPage(embedded: true);
            case _EditorConfigHubTab.siteNavigation:
              return erp.NavigationManagementPage(embedded: true);
            case _EditorConfigHubTab.siteDestinations:
              return erp.WebsiteDestinationManagementPage(
                embedded: true,
                onOpenPages: () =>
                    _openConfigHub(_EditorConfigHubTab.sitePages),
                onOpenNavigation: () =>
                    _openConfigHub(_EditorConfigHubTab.siteNavigation),
                onOpenCatalogProducts: () {
                  setState(() => _catalogTab = _EditorCatalogTab.products);
                  _openConfigHub(_EditorConfigHubTab.ecomCatalog);
                },
                onOpenCatalogCategories: () {
                  setState(() {
                    _catalogTab = _EditorCatalogTab.categories;
                    _categoryTab = _EditorCategoryTab.publication;
                  });
                  _openConfigHub(_EditorConfigHubTab.ecomCatalog);
                },
              );
            case _EditorConfigHubTab.siteSettings:
              return erp.WebsiteSettingsPage(embedded: true);

            // E-commerce
            case _EditorConfigHubTab.ecomCatalog:
              return _buildCatalogWorkspace(theme);
            case _EditorConfigHubTab.ecomOrders:
              return erp.OnlineOrdersPage(embedded: true);

            // Reports
            case _EditorConfigHubTab.reportsAnalytics:
              return erp.AnalyticsDashboardPage(
                dashboardUrl: 'https://analytics.google.com',
                embedded: true,
              );

            // Config
            case _EditorConfigHubTab.seo:
              return erp.SeoSettingsPage(embedded: true);
            case _EditorConfigHubTab.integrations:
              return erp.IntegrationsPage(embedded: true);
            case _EditorConfigHubTab.paymentMethods:
              return erp.PaymentMethodsSettingsPage(embedded: true);
            case _EditorConfigHubTab.domain:
              // Handled above.
              return const SizedBox.shrink();
          }
        },
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Volver al editor'),
                  onPressed: _closeConfigHub,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 24,
                  child: VerticalDivider(color: theme.dividerColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _configHubTab.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Builder(
                  builder: (context) {
                    final editProvider =
                        context.watch<WebsiteEditModeProvider>();
                    if (!editProvider.hasUnsavedChanges) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Borrador de página preservado',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogWorkspace(ThemeData theme) {
    final selectedSection = switch ((_catalogTab, _categoryTab)) {
      (_EditorCatalogTab.categories, _EditorCategoryTab.presentation) =>
        erp.WebsiteCatalogSection.categoryPresentation,
      (_EditorCatalogTab.categories, _) => erp.WebsiteCatalogSection.categories,
      _ => erp.WebsiteCatalogSection.products,
    };

    Widget body;
    if (_catalogTab == _EditorCatalogTab.featured) {
      body = erp.FeaturedProductsPage(embedded: true);
    } else if (_catalogTab == _EditorCatalogTab.categories &&
        _categoryTab == _EditorCategoryTab.structure) {
      body = erp.HierarchicalCategoryPage(embedded: true);
    } else {
      body = erp.ProductWebsiteVisibilityPage(
        embedded: true,
        section: selectedSection,
      );
    }

    final workspaceDescription = switch (_catalogTab) {
      _EditorCatalogTab.products =>
        'Publica artículos y revisa exactamente qué verá el cliente.',
      _EditorCatalogTab.categories => switch (_categoryTab) {
          _EditorCategoryTab.publication =>
            'Elige qué categorías aparecen en la navegación; no limitan productos por sí solas.',
          _EditorCategoryTab.structure =>
            'Organiza nombres y jerarquías del inventario; no publica productos por sí solo.',
          _EditorCategoryTab.presentation =>
            'Diseña el hero, la jerarquía, los filtros y el grid de cada colección.',
        },
      _EditorCatalogTab.featured =>
        'Orden usado por los bloques de portada cuya fuente es “Destacados”.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              SegmentedButton<_EditorCatalogTab>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _EditorCatalogTab.products,
                    icon: Icon(Icons.inventory_2_outlined, size: 17),
                    label: Text('Productos'),
                  ),
                  ButtonSegment(
                    value: _EditorCatalogTab.categories,
                    icon: Icon(Icons.category_outlined, size: 17),
                    label: Text('Categorías'),
                  ),
                  ButtonSegment(
                    value: _EditorCatalogTab.featured,
                    icon: Icon(Icons.star_outline, size: 17),
                    label: Text('Portada'),
                  ),
                ],
                selected: {_catalogTab},
                onSelectionChanged: (selection) {
                  setState(() => _catalogTab = selection.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (_catalogTab == _EditorCatalogTab.categories) ...[
                const SizedBox(width: 12),
                SegmentedButton<_EditorCategoryTab>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: _EditorCategoryTab.publication,
                      label: Text('Publicación'),
                    ),
                    ButtonSegment(
                      value: _EditorCategoryTab.structure,
                      label: Text('Estructura'),
                    ),
                    ButtonSegment(
                      value: _EditorCategoryTab.presentation,
                      label: Text('Presentación'),
                    ),
                  ],
                  selected: {_categoryTab},
                  onSelectionChanged: (selection) {
                    setState(() => _categoryTab = selection.first);
                  },
                ),
              ],
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  workspaceDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildDomainAndUrlPanel() {
    // Reuse the same data shown in the dialog, but as an inline panel.
    final websiteService = context.read<WebsiteService>();
    final url = _resolvePublicStoreUrl(websiteService);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dominio y URL',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Administra tu URL pública. (La configuración de dominio se gestiona en Firebase Hosting / DNS).',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          url ?? 'No se pudo determinar la URL pública',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: url == null
                            ? null
                            : () async {
                                await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Abrir'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: url == null
                        ? null
                        : () async {
                            await _copyToClipboard(url);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('URL copiada'),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar URL'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}