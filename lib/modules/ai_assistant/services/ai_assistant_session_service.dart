import 'package:flutter/foundation.dart';

import '../../../shared/models/current_user_profile.dart';
import '../../../shared/services/authority_scoped_cache.dart';
import '../../../shared/services/current_user_profile_service.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/services/inventory_service.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/services/sales_service.dart';
import '../../tasks/services/task_service.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../models/ai_assistant_session_state.dart';
import 'ai_service.dart';

/// Domain services one assistant turn needs. The panel collects them from the
/// widget tree; the session service stays the only sequencer.
@immutable
class AIAssistantTurnServices {
  const AIAssistantTurnServices({
    this.customerService,
    this.inventoryService,
    this.bikeshopService,
    this.purchaseService,
    this.salesService,
    this.taskService,
  });

  final CustomerService? customerService;
  final InventoryService? inventoryService;
  final BikeshopService? bikeshopService;
  final PurchaseService? purchaseService;
  final SalesService? salesService;
  final TaskService? taskService;
}

const String _greetingText =
    'Hola! Soy tu asistente de taller. Puedo decirte qué necesita atención hoy '
    'o ayudarte a organizar el trabajo para mañana —entregas del taller y '
    'tareas pendientes—, buscar productos en el inventario y resumir los '
    'trabajos. ¿Qué necesitas?';

const String _untrustedJobsNotice =
    'No pude usar los trabajos que tienes en pantalla: no puedo confirmar que '
    'pertenezcan a este taller, así que los dejé fuera de esta respuesta. Esto '
    'no significa que no haya trabajos.';

/// Owns the assistant session: the visible transcript, the authority it is
/// bound to, the generation that invalidates in-flight turns, and the engine.
///
/// It exists because the transcript used to live in the panel's widget state
/// while the model history lived in the engine. The two diverged: closing the
/// panel emptied what the operator saw while the model kept answering from the
/// previous search. One owner removes that class of defect by construction.
class AIAssistantSessionService extends ChangeNotifier {
  AIAssistantSessionService({
    AIAssistantService Function()? engineFactory,
  }) : _engineFactory = engineFactory ?? _defaultEngineFactory;

  static AIAssistantService _defaultEngineFactory() {
    final engine = AIAssistantService();
    engine.initialize();
    return engine;
  }

  final AIAssistantService Function() _engineFactory;
  final AuthorityCacheScope _scope = AuthorityCacheScope();

  AIAssistantService? _engine;
  String? _requestedUserId;
  int _resolutionToken = 0;
  AIAssistantCapabilityFingerprint _capabilities =
      AIAssistantCapabilityFingerprint.none;
  AIAssistantSessionStatus _status = AIAssistantSessionStatus.signedOut;
  bool _isSending = false;
  final List<AIAssistantTranscriptEntry> _transcript =
      <AIAssistantTranscriptEntry>[];

  AIAssistantSessionStatus get status => _status;

  /// The transcript the operator sees. Empty for every state but [ready], so
  /// nothing a previous authority produced survives a scope change or an
  /// unresolved window.
  List<AIAssistantTranscriptEntry> get transcript =>
      List<AIAssistantTranscriptEntry>.unmodifiable(_transcript);

  bool get isSending => _isSending;

  /// Fail-closed: only a fully resolved authority with no turn in flight may
  /// send. Callers must gate the composer on this.
  bool get canSend =>
      _status == AIAssistantSessionStatus.ready &&
      !_isSending &&
      _scope.key != null;

  /// Tenant of the current authority, or null when there is none.
  String? get authorityTenantId => _scope.key?.tenantId;

  @visibleForTesting
  int get generation => _scope.generation;

  @visibleForTesting
  AIAssistantService? get engine => _engine;

  /// Binds the session to one coherent Auth user + tenant + ERP profile.
  ///
  /// An authority is valid only when all of these agree: an authenticated user
  /// exists, the profile is loaded without issue, the profile belongs to that
  /// same user, a tenant resolves to a non-empty value, and the profile agrees
  /// with that tenant. Anything else is fail-closed.
  Future<void> synchronize({
    required String? authUserId,
    required CurrentUserProfile? profile,
    required bool profileIsLoading,
    required CurrentUserProfileLoadIssue? profileLoadIssue,
    required String? cachedTenantId,
    required Future<String?> Function() resolveTenantId,
  }) async {
    final normalizedUser = _normalize(authUserId);
    final identityChanged = normalizedUser != _requestedUserId;
    _requestedUserId = normalizedUser;
    final token = ++_resolutionToken;

    // An Auth change invalidates synchronously, before any await, so a tenant
    // resolution already in flight for the previous user cannot publish.
    if (identityChanged) {
      _suspend(
        normalizedUser == null
            ? AIAssistantSessionStatus.signedOut
            : AIAssistantSessionStatus.resolving,
      );
    }

    if (normalizedUser == null) {
      _suspend(AIAssistantSessionStatus.signedOut);
      return;
    }

    if (profileIsLoading) {
      _suspend(AIAssistantSessionStatus.resolving);
      return;
    }

    if (profileLoadIssue != null ||
        profile == null ||
        _normalize(profile.userId) != normalizedUser) {
      _suspend(AIAssistantSessionStatus.unavailable);
      return;
    }

    final profileTenantId = _normalize(profile.tenantId);
    if (profileTenantId == null) {
      _suspend(AIAssistantSessionStatus.unavailable);
      return;
    }

    final fingerprint = AIAssistantCapabilityFingerprint.of(
      role: profile.role,
      permissions: profile.permissions,
    );

    // A healthy session must survive a notify storm, so an authority that
    // already agrees with the profile is kept without re-suspending. The
    // cached tenant is consulted synchronously: if it disagrees, the authority
    // is stale and has to be resolved again.
    final currentKey = _scope.key;
    final cached = _normalize(cachedTenantId);
    // An absent tenant cache is not agreement. Treating null as "no
    // disagreement" let a session stay live on an authority nothing could
    // confirm any more, which is the state a tenant switch passes through.
    final stillCoherent = currentKey != null &&
        currentKey.userId == normalizedUser &&
        currentKey.tenantId == profileTenantId &&
        cached != null &&
        cached == currentKey.tenantId &&
        _capabilities == fingerprint;

    if (stillCoherent) {
      if (_status != AIAssistantSessionStatus.ready) {
        _status = AIAssistantSessionStatus.ready;
        notifyListeners();
      }
      return;
    }

    _suspend(AIAssistantSessionStatus.resolving);

    String? resolvedTenantId;
    try {
      resolvedTenantId = _normalize(await resolveTenantId());
    } catch (error) {
      if (!kReleaseMode) {
        debugPrint('[AIAssistantSession] Tenant resolution failed: $error');
      }
      resolvedTenantId = null;
    }

    // A newer synchronize won the race, or the identity moved while awaiting.
    if (token != _resolutionToken || _requestedUserId != normalizedUser) {
      return;
    }

    if (resolvedTenantId == null || resolvedTenantId != profileTenantId) {
      _suspend(AIAssistantSessionStatus.unavailable);
      return;
    }

    _scope.bind(userId: normalizedUser, tenantId: resolvedTenantId);
    _capabilities = fingerprint;
    _engine = null;
    _isSending = false;
    _transcript
      ..clear()
      ..add(
        const AIAssistantTranscriptEntry(
          role: AIAssistantTranscriptRole.assistant,
          text: _greetingText,
        ),
      );
    _status = AIAssistantSessionStatus.ready;
    notifyListeners();
  }

  /// Sends one turn. The transcript entry and the model input come from this
  /// single sequence, so they cannot diverge.
  Future<void> send(
    String rawText, {
    required AIAssistantTurnServices services,
    required List<MechanicJob> visibleJobs,
    required bool hasVisibleJobsContext,
    String? visibleJobsScopeLabel,
    bool jobsAreCurrentView = false,
    bool allowJobCacheFallback = true,
  }) async {
    if (!canSend) return;
    final text = rawText.trim();
    if (text.isEmpty) return;

    final lease = _scope.capture();
    if (lease == null) return;

    // Rows published by another surface are untrusted input. One row without a
    // tenant, or with a different tenant, invalidates the whole source: a
    // silent filter would let that surface decide what the assistant answers
    // from.
    final jobsContext = hasVisibleJobsContext
        ? AIAssistantVisibleJobsContext.validate(
            jobs: visibleJobs,
            scopeLabel: visibleJobsScopeLabel,
            authorityTenantId: lease.scope.tenantId,
          )
        : const AIAssistantVisibleJobsContext.trusted(
            jobs: <MechanicJob>[],
            scopeLabel: null,
          );

    _isSending = true;
    _transcript.add(
      AIAssistantTranscriptEntry(
        role: AIAssistantTranscriptRole.user,
        text: text,
      ),
    );
    if (hasVisibleJobsContext && !jobsContext.isTrusted) {
      _transcript.add(
        const AIAssistantTranscriptEntry.notice(_untrustedJobsNotice),
      );
      if (!kReleaseMode) {
        debugPrint(
          '[AIAssistantSession] Visible jobs rejected: ${jobsContext.issue}',
        );
      }
    }
    notifyListeners();

    final engine = _engine ??= _engineFactory();

    AIAssistantResponse response;
    try {
      response = await engine.sendMessage(
        text,
        jobs: jobsContext.jobs,
        customerService: services.customerService,
        inventoryService: services.inventoryService,
        bikeshopService: services.bikeshopService,
        purchaseService: services.purchaseService,
        salesService: services.salesService,
        taskService: services.taskService,
        jobsAreCurrentView: jobsContext.isTrusted && jobsAreCurrentView,
        jobSummaryScopeLabel: jobsContext.scopeLabel,
        allowJobCacheFallback:
            jobsContext.isTrusted ? allowJobCacheFallback : false,
        visibleJobsSourceUnavailable:
            hasVisibleJobsContext && !jobsContext.isTrusted,
        // The turn's authority travels with the turn, so every shared cache
        // the engine reads is checked against this exact key rather than
        // against whatever the service happens to be bound to.
        authority: AIAssistantTurnAuthority(lease.scope),
      );
    } catch (error) {
      if (!kReleaseMode) {
        debugPrint('[AIAssistantSession] Turn failed: $error');
      }
      response = const AIAssistantResponse(
        text: 'No pude procesar esa solicitud ahora. Intenta de nuevo en unos '
            'segundos.',
      );
    }

    // A late response from a superseded authority or generation never
    // publishes, and never clears the replacement session's sending flag.
    if (!_scope.owns(lease)) return;

    _transcript.add(
      AIAssistantTranscriptEntry(
        role: AIAssistantTranscriptRole.assistant,
        text: response.text,
        cards: response.cards,
      ),
    );
    _isSending = false;
    notifyListeners();
  }

  /// Drops every trace of the current session: visible transcript, model
  /// history, inventory refinement state, matched SKUs and last results. The
  /// engine is discarded, so the next turn builds a fresh one.
  void _suspend(AIAssistantSessionStatus status) {
    _scope.bind(userId: null, tenantId: null);
    _scope.invalidate();
    _engine?.resetChat();
    _engine = null;
    _capabilities = AIAssistantCapabilityFingerprint.none;
    _transcript.clear();
    _isSending = false;
    _status = status;
    notifyListeners();
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  @override
  void dispose() {
    _engine?.resetChat();
    _engine = null;
    super.dispose();
  }
}
