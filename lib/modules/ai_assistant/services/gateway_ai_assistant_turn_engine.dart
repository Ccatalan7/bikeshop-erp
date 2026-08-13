import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../shared/services/authority_scoped_cache.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/services/inventory_service.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/services/sales_service.dart';
import '../../tasks/services/task_service.dart';
import '../models/ai_agent_gateway_contracts.dart';
import '../models/ai_assistant_turn_contracts.dart';
import 'ai_agent_gateway_client.dart';
import 'ai_assistant_turn_engine.dart';

class GatewayAIAssistantTurnEngine
    implements AIAssistantTurnEngine, AIAssistantApprovalTurnEngine {
  GatewayAIAssistantTurnEngine({
    AIAgentGatewayClient? client,
    String Function()? idFactory,
  })  : _client = client ?? AIAgentGatewayClient(),
        _idFactory = idFactory ?? const Uuid().v4;

  final AIAgentGatewayClient _client;
  final String Function() _idFactory;

  String? _threadId;
  ErpAuthorityScopeKey? _authorityScope;
  Completer<void>? _inFlightAbort;
  String? _replayRequestId;
  String? _replaySignature;
  String? _approvalReplayActionId;
  String? _approvalReplaySignature;
  int _generation = 0;

  @override
  Future<AIAssistantResponse> sendMessage(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    InventoryService? inventoryService,
    BikeshopService? bikeshopService,
    bool jobsAreCurrentView = false,
    String? jobSummaryScopeLabel,
    PurchaseService? purchaseService,
    SalesService? salesService,
    bool allowJobCacheFallback = true,
    bool visibleJobsSourceUnavailable = false,
    TaskService? taskService,
    required AIAssistantTurnAuthority authority,
  }) async {
    if (_inFlightAbort != null) {
      throw const AIAgentGatewayException(code: 'turn_in_progress');
    }
    final boundScope = _authorityScope;
    if (boundScope != null && boundScope != authority.scope) {
      throw const AIAgentGatewayException(code: 'authority_changed');
    }
    _authorityScope ??= authority.scope;

    final generation = _generation;
    final abort = Completer<void>();
    _inFlightAbort = abort;
    final requestThreadId = _threadId;
    final viewContext = _projectViewContext(
      jobs: jobs ?? const <MechanicJob>[],
      jobsAreCurrentView: jobsAreCurrentView,
      visibleJobsSourceUnavailable: visibleJobsSourceUnavailable,
    );
    final replaySignature = jsonEncode(<String, Object?>{
      'threadId': requestThreadId,
      'message': message.trim(),
      'viewContext': viewContext.toJson(),
    });
    final String clientRequestId;
    if (_replaySignature == replaySignature && _replayRequestId != null) {
      clientRequestId = _replayRequestId!;
    } else {
      _replayRequestId = null;
      _replaySignature = null;
      clientRequestId = _idFactory();
    }
    final request = AIAgentGatewayRequest(
      clientRequestId: clientRequestId,
      threadId: requestThreadId,
      message: message,
      viewContext: viewContext,
    );
    try {
      final response = await _client.complete(
        request,
        abortTrigger: abort.future,
      );
      if (generation != _generation) {
        throw const AIAgentGatewayException(code: 'request_aborted');
      }
      if (requestThreadId != null && response.threadId != requestThreadId) {
        throw const AIAgentGatewayContractException();
      }
      _threadId = response.threadId;
      _clearReplayCandidate(clientRequestId);
      return response.toAssistantResponse();
    } on AIAgentGatewayException catch (error) {
      if (generation == _generation &&
          (error.outcomeUnknown || error.code == 'run_in_progress')) {
        _replayRequestId = clientRequestId;
        _replaySignature = replaySignature;
      } else {
        _clearReplayCandidate(clientRequestId);
      }
      rethrow;
    } on AIAgentGatewayContractException {
      if (generation == _generation) {
        // A malformed 2xx response may have followed a committed run. Preserve
        // the exact id so the next identical turn can recover its replay.
        _replayRequestId = clientRequestId;
        _replaySignature = replaySignature;
      }
      rethrow;
    } finally {
      if (identical(_inFlightAbort, abort)) _inFlightAbort = null;
    }
  }

  @override
  Future<AIAssistantApprovalResolution> resolveApproval(
    AIAssistantApprovalRef approval,
    AIAssistantApprovalDecision decision, {
    required AIAssistantTurnAuthority authority,
  }) async {
    if (_inFlightAbort != null) {
      throw const AIAgentGatewayException(code: 'turn_in_progress');
    }
    if (approval.action != AIAssistantApprovalAction.createTask ||
        approval.state != AIAssistantApprovalState.pending) {
      throw const AIAgentGatewayException(code: 'approval_invalid');
    }
    final boundScope = _authorityScope;
    if (boundScope != null && boundScope != authority.scope) {
      throw const AIAgentGatewayException(code: 'authority_changed');
    }
    _authorityScope ??= authority.scope;

    final generation = _generation;
    final abort = Completer<void>();
    _inFlightAbort = abort;
    final replaySignature = jsonEncode(<String, Object?>{
      'approvalId': approval.id,
      'approvalAction': approval.action.name,
      'decision': decision.name,
    });
    final String clientActionId;
    if (_approvalReplaySignature == replaySignature &&
        _approvalReplayActionId != null) {
      clientActionId = _approvalReplayActionId!;
    } else {
      _approvalReplayActionId = null;
      _approvalReplaySignature = null;
      clientActionId = _idFactory();
    }
    final request = AIAgentGatewayApprovalRequest(
      approvalId: approval.id,
      decision: decision,
      clientActionId: clientActionId,
    );
    try {
      final response = await _client.resolveApproval(
        request,
        abortTrigger: abort.future,
      );
      if (generation != _generation) {
        throw const AIAgentGatewayException(code: 'request_aborted');
      }
      if (response.approvalId != approval.id ||
          response.clientActionId != clientActionId) {
        throw const AIAgentGatewayContractException();
      }
      _clearApprovalReplayCandidate(clientActionId);
      return response.toResolution();
    } on AIAgentGatewayException catch (error) {
      if (generation == _generation && error.outcomeUnknown) {
        _approvalReplayActionId = clientActionId;
        _approvalReplaySignature = replaySignature;
      } else {
        _clearApprovalReplayCandidate(clientActionId);
      }
      rethrow;
    } on AIAgentGatewayContractException {
      if (generation == _generation) {
        // A malformed success may follow a committed task creation. Preserve
        // the action id so the exact retry can only read back that outcome.
        _approvalReplayActionId = clientActionId;
        _approvalReplaySignature = replaySignature;
      }
      rethrow;
    } finally {
      if (identical(_inFlightAbort, abort)) _inFlightAbort = null;
    }
  }

  void _clearReplayCandidate(String requestId) {
    if (_replayRequestId != requestId) return;
    _replayRequestId = null;
    _replaySignature = null;
  }

  void _clearApprovalReplayCandidate(String actionId) {
    if (_approvalReplayActionId != actionId) return;
    _approvalReplayActionId = null;
    _approvalReplaySignature = null;
  }

  AIAgentGatewayViewContext _projectViewContext({
    required List<MechanicJob> jobs,
    required bool jobsAreCurrentView,
    required bool visibleJobsSourceUnavailable,
  }) {
    if (visibleJobsSourceUnavailable) {
      return AIAgentGatewayViewContext.rejected();
    }
    if (!jobsAreCurrentView) return AIAgentGatewayViewContext.none();
    // An empty client list is not proof that the server-side workshop view is
    // empty, so do not manufacture a verified workshop context from it.
    if (jobs.isEmpty) return AIAgentGatewayViewContext.none();

    final ids = <String>[];
    final seen = <String>{};
    var omitted = false;
    for (final job in jobs) {
      final id = job.id?.trim();
      if (id == null || !isAIAgentGatewayOpaqueId(id) || !seen.add(id)) {
        omitted = true;
        continue;
      }
      if (ids.length >= aiAgentGatewayMaxVisibleJobIds) {
        omitted = true;
        continue;
      }
      ids.add(id);
    }
    if (ids.isEmpty) return AIAgentGatewayViewContext.rejected();
    return AIAgentGatewayViewContext(
      kind: AIAgentGatewayViewContextKind.workshopJobs,
      jobIds: ids,
      truncated: omitted,
    );
  }

  @override
  void resetChat() {
    _generation++;
    final abort = _inFlightAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _inFlightAbort = null;
    _threadId = null;
    _authorityScope = null;
    _replayRequestId = null;
    _replaySignature = null;
    _approvalReplayActionId = null;
    _approvalReplaySignature = null;
  }
}
