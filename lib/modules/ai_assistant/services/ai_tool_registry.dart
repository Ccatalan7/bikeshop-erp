import 'dart:async';
import 'dart:convert';

import '../models/ai_agent_tool.dart';

/// A policy decision made by trusted runtime code.
class AIToolPolicyDecision {
  const AIToolPolicyDecision.allow({this.requiresApproval = false})
      : allowed = true;

  const AIToolPolicyDecision.deny()
      : allowed = false,
        requiresApproval = false;

  final bool allowed;

  /// Policy may elevate approval but can never remove the definition's gate.
  final bool requiresApproval;
}

/// Additional policy boundary outside both the model and tool executor.
abstract interface class AIToolPolicy {
  /// Decides whether a definition may be announced for this authority.
  AIToolPolicyDecision discover({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
  });

  /// Re-evaluates policy against the exact invocation immediately before use.
  AIToolPolicyDecision authorize({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
  });
}

/// Default policy. Required ERP permissions are still enforced by the registry
/// itself, so a custom policy cannot accidentally grant a missing permission.
class AIToolAllowAuthorizedPolicy implements AIToolPolicy {
  const AIToolAllowAuthorizedPolicy();

  @override
  AIToolPolicyDecision discover({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
  }) {
    return const AIToolPolicyDecision.allow();
  }

  @override
  AIToolPolicyDecision authorize({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
  }) {
    return const AIToolPolicyDecision.allow();
  }
}

/// Consumes approval evidence outside the model and client tool definition.
///
/// A production verifier must atomically validate a server-issued, single-use
/// approval against the exact authority, arguments and idempotency key. The
/// default rejects everything, so constructing [AIToolApproval] in the client
/// can never authorize a write by itself.
abstract interface class AIToolApprovalVerifier {
  Future<bool> consume({
    required AIToolApproval approval,
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
    required String? idempotencyKey,
    required DateTime now,
  });
}

class AIToolRejectAllApprovalVerifier implements AIToolApprovalVerifier {
  const AIToolRejectAllApprovalVerifier();

  @override
  Future<bool> consume({
    required AIToolApproval approval,
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
    required String? idempotencyKey,
    required DateTime now,
  }) async =>
      false;
}

/// Binds an immutable definition to a testable canonical executor callback.
class AIToolRegistration {
  const AIToolRegistration({
    required this.definition,
    required this.executor,
  });

  final AIToolDefinition definition;
  final AIToolExecutor executor;
}

/// Fail-closed registry used for discovery and execution.
class AIToolRegistry {
  AIToolRegistry({
    required Iterable<AIToolRegistration> registrations,
    this.policy = const AIToolAllowAuthorizedPolicy(),
    this.approvalVerifier = const AIToolRejectAllApprovalVerifier(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    for (final registration in registrations) {
      final name = registration.definition.name;
      if (_registrations.containsKey(name)) {
        throw const AIToolRegistryException(
          AIToolFailureCode.duplicateTool,
        );
      }
      _registrations[name] = registration;
    }
  }

  final AIToolPolicy policy;
  final AIToolApprovalVerifier approvalVerifier;
  final DateTime Function() _now;
  final Map<String, AIToolRegistration> _registrations =
      <String, AIToolRegistration>{};
  final Set<String> _activeNonParallelTools = <String>{};
  final Set<String> _claimedApprovalIds = <String>{};

  /// Only definitions allowed by both ERP permissions and policy are exposed.
  List<AIToolAdvertisement> advertisedToolsFor(AIToolAuthority authority) {
    final visible = <AIToolAdvertisement>[];
    for (final registration in _registrations.values) {
      final definition = registration.definition;
      if (!_hasRequiredPermissions(definition, authority)) continue;
      final decision = _safeDiscoveryDecision(definition, authority);
      if (decision.allowed) visible.add(definition.advertisement);
    }
    return List<AIToolAdvertisement>.unmodifiable(visible);
  }

  Future<AIToolExecution> execute({
    required String toolName,
    required Map<String, Object?> arguments,
    required AIToolAuthority authority,
    AIToolApproval? approval,
    String? idempotencyKey,
    Duration? executionTimeout,
  }) async {
    final startedAt = _now().toUtc();
    final budgetStopwatch = Stopwatch()..start();
    final registration = _registrations[toolName];
    if (registration == null) {
      _reject(
        code: AIToolFailureCode.unknownTool,
        toolName: 'unknown_tool',
        authority: authority,
        startedAt: startedAt,
      );
    }

    final definition = registration.definition;
    if (executionTimeout != null && executionTimeout <= Duration.zero) {
      _reject(
        code: AIToolFailureCode.timeout,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
      );
    }
    if (!_hasRequiredPermissions(definition, authority)) {
      _reject(
        code: AIToolFailureCode.unauthorized,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
      );
    }

    final discoveryDecision = _safeDiscoveryDecision(definition, authority);
    if (!discoveryDecision.allowed) {
      _reject(
        code: AIToolFailureCode.unauthorized,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
      );
    }

    if (!definition.inputSchema.accepts(arguments)) {
      _reject(
        code: AIToolFailureCode.invalidArguments,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
      );
    }

    final normalizedIdempotencyKey = idempotencyKey?.trim();
    if (definition.idempotency == AIToolIdempotencyPolicy.required &&
        (normalizedIdempotencyKey == null ||
            normalizedIdempotencyKey.isEmpty)) {
      _reject(
        code: AIToolFailureCode.idempotencyKeyRequired,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
      );
    }

    final executionContext = AIToolExecutionContext(
      definition: definition,
      authority: authority,
      arguments: arguments,
      idempotencyKey: normalizedIdempotencyKey,
    );
    final decision = _safeAuthorizationDecision(
      definition,
      authority,
      executionContext.arguments,
    );
    if (!decision.allowed) {
      _reject(
        code: AIToolFailureCode.unauthorized,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
      );
    }

    final requiresApproval = definition.requiresApproval ||
        discoveryDecision.requiresApproval ||
        decision.requiresApproval;
    var approvalValid = false;
    final approvalMatchesInvocation = approval?.authorizes(
          definition: definition,
          authority: authority,
          arguments: executionContext.arguments,
          idempotencyKey: normalizedIdempotencyKey,
          now: _now().toUtc(),
        ) ??
        false;
    var approvalTimedOut = false;
    if (requiresApproval &&
        approval != null &&
        approvalMatchesInvocation &&
        _claimedApprovalIds.add(approval.approvalId)) {
      try {
        final remainingApprovalBudget = executionTimeout == null
            ? definition.timeout
            : executionTimeout - budgetStopwatch.elapsed;
        if (remainingApprovalBudget <= Duration.zero) {
          approvalTimedOut = true;
        } else {
          approvalValid = await approvalVerifier
              .consume(
                approval: approval,
                definition: definition,
                authority: authority,
                arguments: executionContext.arguments,
                idempotencyKey: normalizedIdempotencyKey,
                now: _now().toUtc(),
              )
              .timeout(remainingApprovalBudget);
        }
      } on TimeoutException {
        approvalTimedOut = true;
        approvalValid = false;
      } catch (_) {
        approvalValid = false;
      }
      if (!approvalValid) {
        _claimedApprovalIds.remove(approval.approvalId);
      }
    }
    if (approvalTimedOut) {
      _reject(
        code: AIToolFailureCode.timeout,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }
    if (requiresApproval && !approvalValid) {
      _reject(
        code: AIToolFailureCode.approvalRequired,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }

    final remainingExecutionBudget = executionTimeout == null
        ? definition.timeout
        : executionTimeout - budgetStopwatch.elapsed;
    if (remainingExecutionBudget <= Duration.zero) {
      _reject(
        code: AIToolFailureCode.timeout,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }
    final effectiveTimeout = remainingExecutionBudget >= definition.timeout
        ? definition.timeout
        : remainingExecutionBudget;

    final ownsNonParallelLock = !definition.allowsParallelExecution;
    final nonParallelLockKey =
        '${authority.tenantId}\u0000${authority.userId}\u0000${definition.name}';
    if (ownsNonParallelLock &&
        !_activeNonParallelTools.add(nonParallelLockKey)) {
      _reject(
        code: AIToolFailureCode.concurrentExecutionDenied,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }

    Future<AIToolExecutorResult> executionFuture;
    try {
      executionFuture = registration.executor(executionContext);
    } on AIToolExecutorOutputException {
      if (ownsNonParallelLock) {
        _activeNonParallelTools.remove(nonParallelLockKey);
      }
      _reject(
        code: AIToolFailureCode.invalidOutput,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    } catch (_) {
      if (ownsNonParallelLock) {
        _activeNonParallelTools.remove(nonParallelLockKey);
      }
      _reject(
        code: AIToolFailureCode.executionFailed,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }

    AIToolExecutorResult executorResult;
    if (ownsNonParallelLock) {
      // Future.timeout does not cancel the executor. Keep the single-flight
      // lock until the real work settles; releasing it on the timeout wrapper
      // would permit a second write while the first may still commit.
      executionFuture.then<void>(
        (_) => _activeNonParallelTools.remove(nonParallelLockKey),
        onError: (Object _, StackTrace __) {
          _activeNonParallelTools.remove(nonParallelLockKey);
        },
      );
    }
    try {
      executorResult = await executionFuture.timeout(effectiveTimeout);
    } on TimeoutException {
      _reject(
        code: AIToolFailureCode.timeout,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    } on AIToolExecutorOutputException {
      _reject(
        code: AIToolFailureCode.invalidOutput,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    } catch (_) {
      _reject(
        code: AIToolFailureCode.executionFailed,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }

    if (executorResult.resultCount < 0) {
      _reject(
        code: AIToolFailureCode.invalidOutput,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }
    if (executorResult.resultCount > definition.maxResults) {
      _reject(
        code: AIToolFailureCode.oversizedOutput,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }

    final outputBytes = _jsonByteLength(executorResult.data);
    if (outputBytes == null) {
      _reject(
        code: AIToolFailureCode.invalidOutput,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }
    if (outputBytes > definition.maxOutputBytes) {
      _reject(
        code: AIToolFailureCode.oversizedOutput,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }
    if (definition.requiresReadBack && !executorResult.readBackVerified) {
      _reject(
        code: AIToolFailureCode.readBackRequired,
        definition: definition,
        authority: authority,
        startedAt: startedAt,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
      );
    }

    final completedAt = _now().toUtc();
    return AIToolExecution(
      data: executorResult.data,
      receipt: AIToolReceipt(
        toolName: definition.name,
        toolVersion: definition.version,
        risk: definition.risk,
        authorityScopeHash: authority.auditScopeHash,
        status: AIToolReceiptStatus.succeeded,
        startedAt: startedAt,
        completedAt: completedAt,
        resultCount: executorResult.resultCount,
        approvalUsed: approvalValid,
        idempotencyUsed: normalizedIdempotencyKey?.isNotEmpty ?? false,
        readBackVerified: executorResult.readBackVerified,
        failureCode: null,
      ),
    );
  }

  /// Produces the same sanitized receipt path when the enclosing agent turn
  /// expires before this tool can start or finish.
  AIToolExecutionException rejectForTurnLimit({
    required String toolName,
    required AIToolAuthority authority,
  }) {
    final registration = _registrations[toolName];
    try {
      _reject(
        code: AIToolFailureCode.turnLimitExceeded,
        definition: registration?.definition,
        toolName: registration == null ? 'unknown_tool' : null,
        authority: authority,
        startedAt: _now().toUtc(),
      );
    } on AIToolExecutionException catch (error) {
      return error;
    }
  }

  bool _hasRequiredPermissions(
    AIToolDefinition definition,
    AIToolAuthority authority,
  ) {
    return authority.hasEveryPermission(definition.requiredPermissions);
  }

  AIToolPolicyDecision _safeDiscoveryDecision(
    AIToolDefinition definition,
    AIToolAuthority authority,
  ) {
    try {
      return policy.discover(definition: definition, authority: authority);
    } catch (_) {
      return const AIToolPolicyDecision.deny();
    }
  }

  AIToolPolicyDecision _safeAuthorizationDecision(
    AIToolDefinition definition,
    AIToolAuthority authority,
    Map<String, Object?> arguments,
  ) {
    try {
      return policy.authorize(
        definition: definition,
        authority: authority,
        arguments: arguments,
      );
    } catch (_) {
      return const AIToolPolicyDecision.deny();
    }
  }

  Never _reject({
    required AIToolFailureCode code,
    required AIToolAuthority authority,
    required DateTime startedAt,
    AIToolDefinition? definition,
    String? toolName,
    bool approvalUsed = false,
    bool idempotencyUsed = false,
  }) {
    final status = switch (code) {
      AIToolFailureCode.timeout => AIToolReceiptStatus.timedOut,
      AIToolFailureCode.executionFailed ||
      AIToolFailureCode.invalidOutput ||
      AIToolFailureCode.oversizedOutput ||
      AIToolFailureCode.readBackRequired =>
        AIToolReceiptStatus.failed,
      _ => AIToolReceiptStatus.rejected,
    };
    throw AIToolExecutionException(
      code: code,
      receipt: AIToolReceipt(
        toolName: definition?.name ?? toolName ?? 'unknown_tool',
        toolVersion: definition?.version,
        risk: definition?.risk,
        authorityScopeHash: authority.auditScopeHash,
        status: status,
        startedAt: startedAt,
        completedAt: _now().toUtc(),
        resultCount: 0,
        approvalUsed: approvalUsed,
        idempotencyUsed: idempotencyUsed,
        readBackVerified: false,
        failureCode: code,
      ),
    );
  }
}

int? _jsonByteLength(Map<String, Object?> output) {
  try {
    return utf8.encode(jsonEncode(output)).length;
  } catch (_) {
    return null;
  }
}
