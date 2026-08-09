import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/website_edit_mode_provider.dart';

enum WebsiteEditorNavigationIntent {
  samePage,
  switchPage,
  leaveEditor,
  newTab,
}

class WebsiteEditorNavigationDecision {
  WebsiteEditorNavigationDecision._({
    required this.isAllowed,
    this.provider,
    this.resolveLiveProvider,
    this.intent,
    this.expectedProviderRevision,
    this.discardOnCommit = false,
  });

  final bool isAllowed;
  final WebsiteEditModeProvider? provider;
  final WebsiteEditModeProvider? Function()? resolveLiveProvider;
  final WebsiteEditorNavigationIntent? intent;
  final int? expectedProviderRevision;
  final bool discardOnCommit;
  _WebsiteEditorNavigationDecisionState _state =
      _WebsiteEditorNavigationDecisionState.pending;

  /// Discards the authorized scope only when the caller is ready to navigate.
  ///
  /// This is intentionally separate from the confirmation dialog: another
  /// boundary (for example checkout) may still cancel the operation.
  bool get isCurrent {
    final captured = provider;
    if (captured == null) return true;
    final live = resolveLiveProvider?.call();
    return identical(live, captured) &&
        captured.navigationStateRevision == expectedProviderRevision;
  }

  /// Claims the authorization before starting a remote side effect.
  ///
  /// The claim is one-shot and validates the provider currently mounted above
  /// the caller. It does not discard a draft yet: [commit] owns that final
  /// transition after the remote operation succeeds.
  bool claim() {
    if (_state != _WebsiteEditorNavigationDecisionState.pending) return false;
    if (!isAllowed || !isCurrent) {
      _state = _WebsiteEditorNavigationDecisionState.rejected;
      return false;
    }
    _state = _WebsiteEditorNavigationDecisionState.claimed;
    return true;
  }

  /// Releases a failed remote attempt only while the same live provider and
  /// revision still own the authorization.
  bool releaseClaim() {
    if (_state != _WebsiteEditorNavigationDecisionState.claimed) return false;
    if (!isCurrent) {
      _state = _WebsiteEditorNavigationDecisionState.rejected;
      return false;
    }
    _state = _WebsiteEditorNavigationDecisionState.pending;
    return true;
  }

  bool commit() {
    if (_state == _WebsiteEditorNavigationDecisionState.pending && !claim()) {
      return false;
    }
    if (_state != _WebsiteEditorNavigationDecisionState.claimed || !isCurrent) {
      _state = _WebsiteEditorNavigationDecisionState.rejected;
      return false;
    }
    _state = _WebsiteEditorNavigationDecisionState.committed;
    if (!discardOnCommit) {
      // The leaveEditor intent owns closing the session even when there was
      // no draft to confirm: the FSM must never stay in Edit/Preview after
      // an authorized exit, or a later flag-less re-entry would re-project
      // editor context.
      if (intent == WebsiteEditorNavigationIntent.leaveEditor) {
        provider?.closeEditor();
      }
      return true;
    }
    switch (intent) {
      case WebsiteEditorNavigationIntent.switchPage:
        // A page switch discards ONLY the captured page draft; the session
        // and its sitewide/SEO drafts continue.
        provider?.discardActivePageDraft();
      case WebsiteEditorNavigationIntent.leaveEditor:
        provider?.discardPendingChanges();
        provider?.closeEditor();
      case WebsiteEditorNavigationIntent.samePage:
      case WebsiteEditorNavigationIntent.newTab:
      case null:
        break;
    }
    return true;
  }
}

enum _WebsiteEditorNavigationDecisionState {
  pending,
  claimed,
  committed,
  rejected,
}

/// Single confirmation boundary for navigation that can replace editor content.
class WebsiteEditorNavigationGuard {
  const WebsiteEditorNavigationGuard._();

  /// Builds an allowed decision without the interactive dialog so behavior
  /// tests can exercise the commit contract (leaveEditor closes the FSM,
  /// switchPage discards only the page draft).
  @visibleForTesting
  static WebsiteEditorNavigationDecision decisionForTesting({
    required WebsiteEditModeProvider provider,
    required WebsiteEditorNavigationIntent intent,
    required bool discardOnCommit,
    WebsiteEditModeProvider? Function()? resolveLiveProvider,
  }) =>
      WebsiteEditorNavigationDecision._(
        isAllowed: true,
        provider: provider,
        resolveLiveProvider: resolveLiveProvider ?? () => provider,
        intent: intent,
        expectedProviderRevision: provider.navigationStateRevision,
        discardOnCommit: discardOnCommit,
      );

  /// Classifies the effect on the editor document, not only the target URL.
  ///
  /// A hard browser replacement leaves the editor even when its URL names the
  /// same page. Treating it as [WebsiteEditorNavigationIntent.samePage] would
  /// bypass the guard and destroy page, sitewide and SEO drafts on reload.
  static WebsiteEditorNavigationIntent classifyIntent({
    required bool openInNewTab,
    required bool launchesExternalWindow,
    required bool keepsCurrentPage,
    bool replacesBrowserDocument = false,
  }) {
    if (replacesBrowserDocument) {
      return WebsiteEditorNavigationIntent.leaveEditor;
    }
    if (openInNewTab) return WebsiteEditorNavigationIntent.newTab;
    if (launchesExternalWindow) {
      return WebsiteEditorNavigationIntent.leaveEditor;
    }
    if (keepsCurrentPage) return WebsiteEditorNavigationIntent.samePage;
    return WebsiteEditorNavigationIntent.switchPage;
  }

  static Future<WebsiteEditorNavigationDecision> authorize(
    BuildContext context, {
    required WebsiteEditorNavigationIntent intent,
  }) async {
    if (intent == WebsiteEditorNavigationIntent.samePage ||
        intent == WebsiteEditorNavigationIntent.newTab) {
      return WebsiteEditorNavigationDecision._(isAllowed: true);
    }

    WebsiteEditModeProvider provider;
    try {
      provider = context.read<WebsiteEditModeProvider>();
    } catch (_) {
      return WebsiteEditorNavigationDecision._(isAllowed: true);
    }

    WebsiteEditModeProvider? resolveLiveProvider() {
      if (!context.mounted) return null;
      try {
        return context.read<WebsiteEditModeProvider>();
      } catch (_) {
        return null;
      }
    }

    final hasRelevantDraft = switch (intent) {
      WebsiteEditorNavigationIntent.switchPage => provider.hasPageDraftChanges,
      WebsiteEditorNavigationIntent.leaveEditor => provider.hasUnsavedChanges,
      WebsiteEditorNavigationIntent.samePage ||
      WebsiteEditorNavigationIntent.newTab =>
        false,
    };
    final expectedProviderRevision = provider.navigationStateRevision;
    if (!provider.isInEditorContext || !hasRelevantDraft) {
      return WebsiteEditorNavigationDecision._(
        isAllowed: true,
        provider: provider,
        resolveLiveProvider: resolveLiveProvider,
        intent: intent,
        expectedProviderRevision: expectedProviderRevision,
      );
    }
    if (!context.mounted) {
      return WebsiteEditorNavigationDecision._(isAllowed: false);
    }

    final content = intent == WebsiteEditorNavigationIntent.switchPage
        ? 'Tienes cambios sin guardar en esta página. Si continúas, la página '
            'de destino reemplazará ese borrador. Los ajustes generales del '
            'sitio se conservarán.'
        : 'Tienes cambios sin guardar en el Website Builder. Si sales, se '
            'descartarán los borradores de página y del sitio.';

    final shouldContinue = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Cambios sin guardar'),
            content: Text(content),
            actions: [
              TextButton(
                key: const ValueKey('website-draft-navigation-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const ValueKey('website-draft-navigation-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continuar sin guardar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldContinue) {
      return WebsiteEditorNavigationDecision._(isAllowed: false);
    }
    return WebsiteEditorNavigationDecision._(
      isAllowed: true,
      provider: provider,
      resolveLiveProvider: resolveLiveProvider,
      intent: intent,
      expectedProviderRevision: expectedProviderRevision,
      discardOnCommit: true,
    );
  }
}
