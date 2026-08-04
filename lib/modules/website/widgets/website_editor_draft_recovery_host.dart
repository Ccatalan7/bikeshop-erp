import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/widgets/vb_notice.dart';
import '../models/website_editor_capability.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_editor_draft_controller.dart';
import '../services/website_editor_draft_store.dart';

/// Binds the durable page-draft controller to the active Website editor
/// document and exposes the only explicit restore/discard decision surface.
///
/// This host owns process lifecycle flushing and session replacement. It does
/// not own authored state: all restored content still enters through
/// [WebsiteEditModeProvider.restoreDurablePageDraft], including its authority,
/// baseline, history and page guards.
class WebsiteEditorDraftRecoveryHost extends StatefulWidget {
  const WebsiteEditorDraftRecoveryHost({
    super.key,
    required this.provider,
    this.store,
  });

  final WebsiteEditModeProvider provider;

  @visibleForTesting
  final WebsiteEditorDraftStore? store;

  @override
  State<WebsiteEditorDraftRecoveryHost> createState() =>
      _WebsiteEditorDraftRecoveryHostState();
}

class _WebsiteEditorDraftRecoveryHostState
    extends State<WebsiteEditorDraftRecoveryHost> with WidgetsBindingObserver {
  WebsiteEditorDraftController? _controller;
  WebsiteEditorDraftReadResult? _recovery;
  String? _sessionKey;
  Object? _error;
  int _bindingGeneration = 0;
  bool _bindingScheduled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.provider.addListener(_handleProviderChanged);
    _scheduleBinding();
  }

  @override
  void didUpdateWidget(WebsiteEditorDraftRecoveryHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.provider, widget.provider)) {
      oldWidget.provider.removeListener(_handleProviderChanged);
      widget.provider.addListener(_handleProviderChanged);
      _sessionKey = null;
      _scheduleBinding();
    }
  }

  void _handleProviderChanged() {
    if (_sessionKeyFor(widget.provider) != _sessionKey) _scheduleBinding();
  }

  void _scheduleBinding() {
    if (_bindingScheduled) return;
    _bindingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bindingScheduled = false;
      if (!mounted) return;
      unawaited(_bindCurrentSession());
    });
  }

  Future<void> _bindCurrentSession() async {
    final nextKey = _sessionKeyFor(widget.provider);
    if (nextKey == _sessionKey && _controller != null) return;

    final generation = ++_bindingGeneration;
    final previous = _controller;
    _controller = null;
    _sessionKey = nextKey;
    if (mounted) {
      setState(() {
        _recovery = null;
        _error = null;
        _busy = false;
      });
    }

    if (previous != null) {
      try {
        await previous.flushNow();
      } on Object {
        // The controller retains the typed error. A replacement must continue
        // so a stale page owner cannot stay attached to the new document.
      }
      await previous.dispose();
    }
    if (!mounted || generation != _bindingGeneration || nextKey == null) {
      return;
    }

    late final WebsiteEditorDraftController controller;
    controller = WebsiteEditorDraftController(
      provider: widget.provider,
      store: widget.store,
      onError: (error) {
        if (!mounted ||
            generation != _bindingGeneration ||
            !identical(_controller, controller)) {
          return;
        }
        setState(() => _error = error);
      },
    )..start();
    _controller = controller;
    try {
      final result = await controller.resolveRecovery();
      if (!mounted ||
          generation != _bindingGeneration ||
          !identical(_controller, controller)) {
        await controller.dispose();
        return;
      }
      setState(() {
        _recovery = result;
        _error = null;
      });
    } on WebsiteEditorReadSupersededException {
      if (mounted && generation == _bindingGeneration) _scheduleBinding();
    } on Object catch (error) {
      if (!mounted || generation != _bindingGeneration) return;
      setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      final controller = _controller;
      if (controller != null) {
        unawaited(controller.flushNow().onError((_, __) {
          // The controller reports the typed error through [onError]. A
          // lifecycle callback cannot await or rethrow the background flush.
        }));
      }
    }
  }

  Future<void> _restore() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      await controller.restorePending();
      if (!mounted || !identical(_controller, controller)) return;
      setState(() {
        _recovery = null;
        _error = null;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted || !identical(_controller, controller)) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  Future<void> _discard() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      await controller.discardPending();
      if (!mounted || !identical(_controller, controller)) return;
      setState(() {
        _recovery = null;
        _error = null;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted || !identical(_controller, controller)) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  void _retryRecoveryRead() {
    if (_busy) return;
    // Force a replacement even though the typed editor session itself did not
    // change: the previous controller owns the failed read and must not make a
    // retry look like an already-bound no-op.
    _sessionKey = null;
    _scheduleBinding();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return VbNotice(
        key: const ValueKey('website-draft-recovery-error'),
        title: 'No pudimos revisar el borrador local',
        body: 'Tu contenido actual sigue intacto. Vuelve a intentarlo antes de '
            'cerrar el editor.',
        tone: VbNoticeTone.danger,
        action: _DraftRecoveryAction(
          label: 'Reintentar',
          onPressed: _busy ? null : _retryRecoveryRead,
        ),
      );
    }

    final recovery = _recovery;
    if (recovery == null || !(_controller?.isAwaitingRecoveryChoice ?? false)) {
      return const SizedBox.shrink();
    }
    final stale =
        recovery.disposition == WebsiteEditorDraftReadDisposition.staleBase;
    return VbNotice(
      key: ValueKey(
        stale ? 'website-draft-stale-notice' : 'website-draft-restore-notice',
      ),
      title: stale
          ? 'El sitio cambió desde este borrador'
          : 'Hay un borrador local sin guardar',
      body: stale
          ? 'Por seguridad no se mezcló con la versión actual. Descártalo para '
              'seguir trabajando sobre el contenido más reciente.'
          : 'Puedes restaurarlo con su viewport, selección e historial, o '
              'descartarlo y continuar con la versión cargada.',
      tone: stale ? VbNoticeTone.warning : VbNoticeTone.info,
      action: _busy
          ? const SizedBox.square(
              dimension: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!stale)
                  _DraftRecoveryAction(
                    label: 'Restaurar',
                    onPressed: _restore,
                  ),
                _DraftRecoveryAction(
                  label: 'Descartar',
                  onPressed: _discard,
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.provider.removeListener(_handleProviderChanged);
    _bindingGeneration++;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(() async {
        try {
          await controller.flushNow();
        } on Object {
          // [onError] already retained and reported the failure while this
          // host was mounted. Disposal must still release the listener.
        } finally {
          await controller.dispose();
        }
      }());
    }
    super.dispose();
  }
}

class _DraftRecoveryAction extends StatelessWidget {
  const _DraftRecoveryAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(88, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

String? _sessionKeyFor(WebsiteEditModeProvider provider) {
  if (!provider.isInEditorContext) return null;
  final authority = provider.editorEntryLease;
  if (authority == null || !authority.granted) return null;
  final document = provider.document;
  if (document.ownerTenantId != authority.storefrontTenantId ||
      document.ownerLeaseFingerprint != authority.fingerprint) {
    return null;
  }
  return '${authority.fingerprint}|${authority.authorityEpoch}|'
      '${document.sessionRevision}|${document.pageId ?? ''}|'
      '${document.pageSlug ?? ''}';
}
