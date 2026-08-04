import 'dart:async';

import '../models/website_editor_capability.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_editor_draft_store.dart';

/// Serializes durable local-draft recovery and autosave around the canonical
/// [WebsiteEditModeProvider].
///
/// The controller deliberately stays UI-free. A host first calls
/// [resolveRecovery] after opening the authoritative page. While a restorable
/// or stale snapshot awaits an explicit Restore/Discard choice, autosave is
/// paused so the clean server document cannot erase the only recovery copy.
/// Once resolved, provider changes are debounced and serialized; a slower old
/// write can never become the final stored value after a newer edit or delete.
class WebsiteEditorDraftController {
  WebsiteEditorDraftController({
    required WebsiteEditModeProvider provider,
    WebsiteEditorDraftStore? store,
    this.debounce = const Duration(milliseconds: 350),
    DateTime Function()? clock,
    this.onError,
  })  : _provider = provider,
        _store = store ?? WebsiteEditorDraftStore(),
        _clock = clock ?? DateTime.now;

  final WebsiteEditModeProvider _provider;
  final WebsiteEditorDraftStore _store;
  final Duration debounce;
  final DateTime Function() _clock;
  final void Function(Object error)? onError;

  Timer? _timer;
  Future<void> _serial = Future<void>.value();
  bool _started = false;
  bool _recoveryResolved = false;
  WebsiteEditorDraftReadResult? _pendingRecovery;
  _CapturedDraftIdentity? _boundSession;
  _DraftWriteIntent? _pendingWrite;
  Object? _lastError;

  WebsiteEditorDraftReadResult? get pendingRecovery => _pendingRecovery;
  Object? get lastError => _lastError;
  bool get isAwaitingRecoveryChoice =>
      _pendingRecovery?.disposition ==
          WebsiteEditorDraftReadDisposition.restorable ||
      _pendingRecovery?.disposition ==
          WebsiteEditorDraftReadDisposition.staleBase;

  void start() {
    if (_started) return;
    _started = true;
    _provider.addListener(_onProviderChanged);
  }

  Future<WebsiteEditorDraftReadResult> resolveRecovery() async {
    final captured = _captureIdentity();
    if (captured == null) {
      _boundSession = null;
      _recoveryResolved = true;
      _pendingRecovery = const WebsiteEditorDraftReadResult.absent();
      return _pendingRecovery!;
    }
    final result = await _store.read(
      identity: captured.identity,
      currentBaseBlocks: _provider.pageDraftBaselineBlocks,
    );
    _requireCurrent(captured);
    _boundSession = captured;
    _pendingRecovery = result;
    _recoveryResolved = true;
    if (!isAwaitingRecoveryChoice) _captureAndSchedule();
    return result;
  }

  Future<bool> restorePending() async {
    final pending = _pendingRecovery;
    final snapshot = pending?.snapshot;
    if (pending == null || !pending.canRestore || snapshot == null) {
      return false;
    }
    final captured = _captureIdentity();
    if (captured == null || !snapshot.identity.matches(captured.identity)) {
      throw const WebsiteEditorReadSupersededException(
        'El borrador local pertenece a una sesión anterior.',
      );
    }
    final changed = _provider.restoreDurablePageDraft(
      authority: captured.authority,
      recoveredBlocks: snapshot.blocks,
      recoveredViewport: snapshot.previewViewport,
      recoveredWriteScope: snapshot.writeScope,
      recoveredSelectedBlockId: snapshot.selectedBlockId,
      pageId: captured.pageId,
      pageSlug: captured.pageSlug,
    );
    _pendingRecovery = null;
    _recoveryResolved = true;
    _captureAndSchedule();
    await flushNow();
    return changed;
  }

  Future<void> discardPending() async {
    final captured = _captureIdentity();
    final pendingIdentity = _pendingRecovery?.snapshot?.identity;
    final identity = pendingIdentity ?? captured?.identity;
    _pendingRecovery = null;
    _recoveryResolved = true;
    if (identity != null) {
      await _enqueue(() => _store.discard(identity));
    }
    _captureAndSchedule();
  }

  void _onProviderChanged() {
    if (!_recoveryResolved || isAwaitingRecoveryChoice) return;
    final bound = _boundSession;
    if (bound == null) return;
    if (!_isCurrent(bound)) {
      // Capture happens synchronously on every authored change. If a route,
      // lease or document transition arrives before the debounce expires, the
      // detached snapshot still belongs to the old page and can be flushed
      // safely; never recapture from the new document under the old owner.
      _timer?.cancel();
      _timer = null;
      if (_pendingWrite != null) _flushInBackground();
      return;
    }
    _captureAndSchedule();
  }

  void _captureAndSchedule() {
    final bound = _boundSession;
    if (bound == null || !_isCurrent(bound)) return;
    _pendingWrite = _provider.hasPageDraftChanges
        ? _DraftWriteIntent.save(
            WebsiteEditorDraftSnapshot.capture(
              identity: bound.identity,
              updatedAt: _clock(),
              baseBlocks: _provider.pageDraftBaselineBlocks,
              draftBlocks: _provider.document.blocks,
              previewViewport: _provider.previewViewport,
              writeScope: _provider.writeScope,
              selectedBlockId: _provider.selectedBlockId,
            ),
          )
        : _DraftWriteIntent.discard(bound.identity);
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _flushInBackground();
    });
  }

  void _flushInBackground() {
    unawaited(flushNow().onError((_, __) {
      // [_enqueue] already retained and reported the typed error. Background
      // autosave must not leak an unhandled asynchronous exception into the
      // app zone; explicit calls to [flushNow] still surface failures.
    }));
  }

  Future<void> flushNow() async {
    _timer?.cancel();
    _timer = null;
    if (!_recoveryResolved || isAwaitingRecoveryChoice) return;
    final intent = _pendingWrite;
    if (intent == null) return;
    _pendingWrite = null;
    await _enqueue(() => intent.apply(_store));
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final completion = Completer<void>();
    _serial = _serial.then((_) async {
      try {
        await operation();
        _lastError = null;
        completion.complete();
      } on Object catch (error, stackTrace) {
        _lastError = error;
        onError?.call(error);
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }

  _CapturedDraftIdentity? _captureIdentity() {
    if (!_provider.isInEditorContext) return null;
    final authority = _provider.editorEntryLease;
    if (authority == null || !authority.granted) return null;
    final document = _provider.document;
    if (document.ownerTenantId != authority.storefrontTenantId ||
        document.ownerLeaseFingerprint != authority.fingerprint) {
      return null;
    }
    return _CapturedDraftIdentity(
      identity: WebsiteEditorDraftIdentity.forPage(
        capability: authority,
        pageId: document.pageId,
        pageSlug: document.pageSlug,
      ),
      authority: authority,
      sessionRevision: document.sessionRevision,
      pageId: document.pageId,
      pageSlug: document.pageSlug,
    );
  }

  void _requireCurrent(_CapturedDraftIdentity captured) {
    if (!_isCurrent(captured)) {
      throw const WebsiteEditorReadSupersededException(
        'La recuperación del borrador pertenece a una sesión anterior.',
      );
    }
  }

  bool _isCurrent(_CapturedDraftIdentity captured) {
    final current = _captureIdentity();
    return current != null &&
        current.identity.matches(captured.identity) &&
        current.sessionRevision == captured.sessionRevision &&
        current.pageId == captured.pageId &&
        current.pageSlug == captured.pageSlug;
  }

  Future<void> dispose() async {
    _timer?.cancel();
    if (_started) _provider.removeListener(_onProviderChanged);
    await _serial;
  }
}

class _CapturedDraftIdentity {
  const _CapturedDraftIdentity({
    required this.identity,
    required this.authority,
    required this.sessionRevision,
    required this.pageId,
    required this.pageSlug,
  });

  final WebsiteEditorDraftIdentity identity;
  final WebsiteEditorCapabilitySnapshot authority;
  final int sessionRevision;
  final String? pageId;
  final String? pageSlug;
}

class _DraftWriteIntent {
  const _DraftWriteIntent._({
    required this.identity,
    this.snapshot,
  });

  factory _DraftWriteIntent.save(WebsiteEditorDraftSnapshot snapshot) =>
      _DraftWriteIntent._(
        identity: snapshot.identity,
        snapshot: snapshot,
      );

  factory _DraftWriteIntent.discard(WebsiteEditorDraftIdentity identity) =>
      _DraftWriteIntent._(identity: identity);

  final WebsiteEditorDraftIdentity identity;
  final WebsiteEditorDraftSnapshot? snapshot;

  Future<void> apply(WebsiteEditorDraftStore store) {
    final value = snapshot;
    return value == null ? store.discard(identity) : store.save(value);
  }
}
