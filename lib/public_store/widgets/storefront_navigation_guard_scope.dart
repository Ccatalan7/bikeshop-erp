import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/website_editor_navigation_guard.dart';
import '../services/checkout_exit_guard.dart';

typedef StorefrontCheckoutExitAuthorizer = Future<bool> Function(
  BuildContext context, {
  required bool permitNextNavigation,
});

typedef StorefrontEditorPopIntentResolver = WebsiteEditorNavigationIntent
    Function(NavigatorState navigator);

typedef StorefrontPlatformExit = Future<void> Function();

Future<void> _exitStorefrontPlatform() => SystemNavigator.pop();

/// One route-pop boundary for Website Builder drafts and durable checkout.
///
/// Both guards finish before the route is allowed to pop. The final editor
/// discard and Navigator.pop are synchronous so a destination cannot activate
/// another page document between them.
class StorefrontNavigationGuardScope extends StatefulWidget {
  const StorefrontNavigationGuardScope({
    super.key,
    this.guardCheckout = false,
    this.authorizeCheckoutExit,
    this.editorPopIntent = WebsiteEditorNavigationIntent.leaveEditor,
    this.editorPopIntentResolver,
    this.requireNavigatorCanPop = false,
    this.exitPlatform = _exitStorefrontPlatform,
    required this.child,
  })  : assert(!guardCheckout || authorizeCheckoutExit != null),
        assert(
          editorPopIntent == WebsiteEditorNavigationIntent.switchPage ||
              editorPopIntent == WebsiteEditorNavigationIntent.leaveEditor,
        );

  /// Guards a page pop inside a nested storefront Navigator.
  ///
  /// A branch root deliberately does not register this boundary so the pop can
  /// bubble to the outer `leaveEditor` owner.
  const StorefrontNavigationGuardScope.pageSwitch({
    super.key,
    required this.child,
  })  : guardCheckout = false,
        authorizeCheckoutExit = null,
        editorPopIntent = WebsiteEditorNavigationIntent.switchPage,
        editorPopIntentResolver = null,
        requireNavigatorCanPop = true,
        exitPlatform = _exitStorefrontPlatform;

  final bool guardCheckout;
  final StorefrontCheckoutExitAuthorizer? authorizeCheckoutExit;
  final WebsiteEditorNavigationIntent editorPopIntent;
  final StorefrontEditorPopIntentResolver? editorPopIntentResolver;
  final bool requireNavigatorCanPop;
  final StorefrontPlatformExit exitPlatform;
  final Widget child;

  @override
  State<StorefrontNavigationGuardScope> createState() =>
      _StorefrontNavigationGuardScopeState();
}

class _StorefrontNavigationGuardScopeState
    extends State<StorefrontNavigationGuardScope> {
  bool _allowPopOnce = false;
  bool _authorizationInFlight = false;
  bool _consumingLocalHistory = false;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    if (widget.requireNavigatorCanPop && !navigator.canPop()) {
      return widget.child;
    }

    final checkoutGuard =
        widget.guardCheckout ? context.watch<CheckoutExitGuard>() : null;
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final editorPopIntent = widget.editorPopIntentResolver?.call(navigator) ??
        widget.editorPopIntent;
    final guardsEditorDraft = editProvider.isInEditorContext &&
        switch (editorPopIntent) {
          WebsiteEditorNavigationIntent.switchPage =>
            editProvider.hasPageDraftChanges,
          WebsiteEditorNavigationIntent.leaveEditor =>
            editProvider.hasUnsavedChanges,
          WebsiteEditorNavigationIntent.samePage ||
          WebsiteEditorNavigationIntent.newTab =>
            false,
        };
    // A CLEAN Edit/Preview session still owns its Back: the outer exit must
    // run through the guard so commit() closes the FSM (no dialog is shown
    // without a draft). Otherwise the provider would stay in editor mode and
    // a later flag-less re-entry would re-project editor context.
    final guardsEditorExit = editProvider.isInEditorContext &&
        editorPopIntent == WebsiteEditorNavigationIntent.leaveEditor;
    final guardsCheckout = checkoutGuard?.isLocked ?? false;
    final guardIsActive =
        guardsEditorDraft || guardsEditorExit || guardsCheckout;

    // LocalHistory (drawers, in-page panels) owns this Back before PopScope.
    // Capture that disposition during build so its resulting `didPop=false`
    // callback never becomes an editor-page discard.
    final route = ModalRoute.of(context);
    final routePopDisposition = ModalRoute.popDispositionOf(context);
    final routeHandlesLocalHistory = route?.willHandlePopInternally == true &&
        routePopDisposition == RoutePopDisposition.pop;

    return PopScope(
      // Keep this wrapper mounted for Public/Preview/Edit. Conditionally
      // inserting PopScope remounted the complete storefront Scaffold (and
      // every plain GoRoute consumer State) when editor context changed.
      // An inactive guard varies only this value and behaves like no boundary.
      canPop: !guardIsActive || _allowPopOnce,
      onPopInvokedWithResult: (didPop, result) async {
        if (!guardIsActive) return;
        if (!didPop &&
            (routeHandlesLocalHistory ||
                route?.willHandlePopInternally == true)) {
          if (_consumingLocalHistory) return;
          if (route?.willHandlePopInternally == true) {
            _consumingLocalHistory = true;
            try {
              navigator.pop(result);
            } finally {
              _consumingLocalHistory = false;
            }
          }
          if (mounted) setState(() {});
          return;
        }
        if (didPop) {
          checkoutGuard?.revokeNavigationPermit();
          if (mounted && _allowPopOnce) {
            setState(() => _allowPopOnce = false);
          }
          return;
        }
        if (_allowPopOnce) {
          checkoutGuard?.revokeNavigationPermit();
          if (mounted) setState(() => _allowPopOnce = false);
          return;
        }
        if (_authorizationInFlight) return;
        _authorizationInFlight = true;
        var checkoutAuthorizationRequested = false;
        var popRequested = false;

        try {
          // Always capture the provider revision. A checkout may begin outside
          // editor context and a draft can appear while its dialog is open.
          final editorDecision = await WebsiteEditorNavigationGuard.authorize(
            context,
            intent: editorPopIntent,
          );
          if (!editorDecision.isAllowed || !context.mounted) return;

          if (checkoutGuard?.isLocked == true) {
            checkoutAuthorizationRequested = true;
            final checkoutApproved = await widget.authorizeCheckoutExit!(
              context,
              permitNextNavigation: true,
            );
            if (!checkoutApproved) return;
            if (!context.mounted) {
              checkoutGuard?.revokeNavigationPermit();
              return;
            }
          }

          final currentRoute = ModalRoute.of(context);
          if (!identical(currentRoute, route) ||
              currentRoute?.isCurrent != true) {
            return;
          }
          if (currentRoute!.willHandlePopInternally) {
            checkoutGuard?.revokeNavigationPermit();
            navigator.pop(result);
            return;
          }

          setState(() => _allowPopOnce = true);
          await WidgetsBinding.instance.endOfFrame;
          if (!context.mounted) {
            checkoutGuard?.revokeNavigationPermit();
            return;
          }
          if (!navigator.mounted) {
            checkoutGuard?.revokeNavigationPermit();
            setState(() => _allowPopOnce = false);
            return;
          }

          final verifiedRoute = ModalRoute.of(context);
          final checkoutAuthorizationIsCurrent = checkoutGuard == null ||
              !checkoutGuard.isLocked ||
              checkoutGuard.consumeNavigationPermit();
          if (identical(verifiedRoute, route) &&
              verifiedRoute?.willHandlePopInternally == true) {
            checkoutGuard?.revokeNavigationPermit();
            setState(() => _allowPopOnce = false);
            navigator.pop(result);
            return;
          }
          final verifiedDisposition = verifiedRoute?.popDisposition;
          final routeCanComplete = identical(verifiedRoute, route) &&
              verifiedRoute?.isCurrent == true &&
              switch (verifiedDisposition) {
                RoutePopDisposition.pop => navigator.canPop(),
                RoutePopDisposition.bubble => !navigator.canPop(),
                RoutePopDisposition.doNotPop || null => false,
              };
          if (!checkoutAuthorizationIsCurrent ||
              !editorDecision.isCurrent ||
              !routeCanComplete) {
            checkoutGuard?.revokeNavigationPermit();
            setState(() => _allowPopOnce = false);
            return;
          }

          if (!editorDecision.commit()) {
            setState(() => _allowPopOnce = false);
            return;
          }
          popRequested = true;
          if (verifiedDisposition == RoutePopDisposition.bubble) {
            await widget.exitPlatform();
            return;
          }
          navigator.pop(result);
        } catch (error, stackTrace) {
          debugPrint(
            'Storefront navigation guard failed: $error\n$stackTrace',
          );
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                key: ValueKey<String>('storefront-navigation-guard-error'),
                content: Text(
                  'No se pudo verificar la salida. Inténtalo de nuevo.',
                ),
              ),
            );
          }
        } finally {
          if (!popRequested) {
            if (checkoutAuthorizationRequested) {
              checkoutGuard?.revokeNavigationPermit();
            }
            if (mounted && _allowPopOnce) {
              setState(() => _allowPopOnce = false);
            }
          }
          _authorizationInFlight = false;
        }
      },
      child: widget.child,
    );
  }
}
