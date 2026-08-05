import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'ai_agent_contracts.dart';
import 'ai_agent_tool.dart';

/// A SHA-256 digest used at the audit boundary.
///
/// The audit model deliberately accepts digests instead of raw identifiers or
/// payloads. This makes it impossible for a sink to retain a prompt, tool
/// arguments, tool output, user id or tenant id through this contract.
@immutable
final class AIAgentAuditHash {
  factory AIAgentAuditHash.sha256OfUtf8(String value) {
    return AIAgentAuditHash._(
      sha256.convert(utf8.encode(value)).toString(),
    );
  }

  factory AIAgentAuditHash.sha256OfBytes(List<int> value) {
    return AIAgentAuditHash._(sha256.convert(value).toString());
  }

  /// Keyed digest for low-entropy private values such as short prompts and
  /// tool arguments. A plain digest lets an audit reader test likely values
  /// offline; HMAC prevents that comparison without the runtime-owned key.
  factory AIAgentAuditHash.hmacSha256OfUtf8({
    required List<int> key,
    required String value,
  }) {
    _requireAuditHmacKey(key);
    return AIAgentAuditHash._(
      Hmac(sha256, key).convert(utf8.encode(value)).toString(),
    );
  }

  /// Hashes JSON after sorting every object's keys recursively.
  ///
  /// Canonicalization means semantically identical argument/result maps
  /// produce the same audit digest even when their insertion order differs.
  factory AIAgentAuditHash.sha256OfJson(Object? value) {
    final canonicalJson = jsonEncode(_canonicalJsonValue(value));
    return AIAgentAuditHash.sha256OfUtf8(canonicalJson);
  }

  /// Keyed equivalent of [sha256OfJson], with the same canonical ordering.
  factory AIAgentAuditHash.hmacSha256OfJson({
    required List<int> key,
    required Object? value,
  }) {
    final canonicalJson = jsonEncode(_canonicalJsonValue(value));
    return AIAgentAuditHash.hmacSha256OfUtf8(
      key: key,
      value: canonicalJson,
    );
  }

  factory AIAgentAuditHash.fromSha256Hex(String value) {
    final normalized = value.toLowerCase();
    if (!_sha256Pattern.hasMatch(normalized)) {
      throw ArgumentError(
        'Audit hashes must be complete SHA-256 hexadecimal digests.',
        'value',
      );
    }
    return AIAgentAuditHash._(normalized);
  }

  const AIAgentAuditHash._(this.hex);

  static final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

  final String hex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AIAgentAuditHash && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => hex;
}

void _requireAuditHmacKey(List<int> key) {
  if (key.length < 32 || key.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError(
      'Audit HMAC keys must contain at least 32 bytes.',
      'key',
    );
  }
}

enum AIAgentAuditEventKind {
  modelInvocation,
  toolPolicyDecision,
  toolExecution,
}

enum AIAgentAuditDecision {
  notApplicable,
  allowed,
  denied,
  approvalRequired,
}

enum AIAgentAuditStatus {
  started,
  succeeded,
  rejected,
  failed,
  timedOut,
  cancelled,
}

/// Sanitized local audit record for one model or tool-runtime event.
///
/// Every free-form business value is represented by a digest. The remaining
/// strings are allowlisted operational identifiers owned by the runtime. No
/// arbitrary metadata map is exposed, so a caller cannot append PII or an
/// exception message to an event.
@immutable
final class AIAgentAuditEvent {
  factory AIAgentAuditEvent({
    required DateTime occurredAt,
    required AIAgentAuditEventKind kind,
    required AIAgentAuditHash sessionIdHash,
    required AIAgentAuditHash turnIdHash,
    required AIAgentAuditHash clientRequestIdHash,
    required AIAgentModelRole modelRole,
    required String provider,
    required String model,
    required AIAgentAuditDecision decision,
    required AIAgentAuditStatus status,
    required Duration duration,
    AIAgentAuditHash? toolCallIdHash,
    String? toolId,
    String? toolVersion,
    AIToolRiskLevel? risk,
    AIAgentAuditHash? inputHash,
    AIAgentAuditHash? outputHash,
  }) {
    if (duration.isNegative) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Audit duration cannot be negative.',
      );
    }

    final isToolEvent = kind != AIAgentAuditEventKind.modelInvocation;
    final hasMinimumToolIdentity = toolCallIdHash != null && toolId != null;
    final carriesAnyToolIdentity = toolCallIdHash != null ||
        toolId != null ||
        toolVersion != null ||
        risk != null;
    if ((isToolEvent && !hasMinimumToolIdentity) ||
        (!isToolEvent && carriesAnyToolIdentity)) {
      throw ArgumentError(
        isToolEvent
            ? 'Tool audit events require a hashed call id and tool id. '
                'Unknown or rejected calls may not have a version or risk.'
            : 'Model audit events cannot include tool identity fields.',
      );
    }

    if (kind == AIAgentAuditEventKind.modelInvocation &&
        decision != AIAgentAuditDecision.notApplicable) {
      throw ArgumentError(
        'Model invocation events use the notApplicable policy decision.',
        'decision',
      );
    }

    return AIAgentAuditEvent._(
      occurredAt: occurredAt.toUtc(),
      kind: kind,
      sessionIdHash: sessionIdHash,
      turnIdHash: turnIdHash,
      clientRequestIdHash: clientRequestIdHash,
      toolCallIdHash: toolCallIdHash,
      modelRole: modelRole,
      provider: _validatedRuntimeIdentifier(
        provider,
        fieldName: 'provider',
        maxLength: 48,
      ),
      model: _validatedRuntimeIdentifier(
        model,
        fieldName: 'model',
        maxLength: 120,
      ),
      toolId: toolId == null
          ? null
          : _validatedRuntimeIdentifier(
              toolId,
              fieldName: 'toolId',
              maxLength: 100,
            ),
      toolVersion: toolVersion == null
          ? null
          : _validatedRuntimeIdentifier(
              toolVersion,
              fieldName: 'toolVersion',
              maxLength: 32,
            ),
      risk: risk,
      decision: decision,
      status: status,
      duration: duration,
      inputHash: inputHash,
      outputHash: outputHash,
    );
  }

  const AIAgentAuditEvent._({
    required this.occurredAt,
    required this.kind,
    required this.sessionIdHash,
    required this.turnIdHash,
    required this.clientRequestIdHash,
    required this.toolCallIdHash,
    required this.modelRole,
    required this.provider,
    required this.model,
    required this.toolId,
    required this.toolVersion,
    required this.risk,
    required this.decision,
    required this.status,
    required this.duration,
    required this.inputHash,
    required this.outputHash,
  });

  final DateTime occurredAt;
  final AIAgentAuditEventKind kind;
  final AIAgentAuditHash sessionIdHash;
  final AIAgentAuditHash turnIdHash;
  final AIAgentAuditHash clientRequestIdHash;
  final AIAgentAuditHash? toolCallIdHash;
  final AIAgentModelRole modelRole;
  final String provider;
  final String model;
  final String? toolId;
  final String? toolVersion;
  final AIToolRiskLevel? risk;
  final AIAgentAuditDecision decision;
  final AIAgentAuditStatus status;
  final Duration duration;
  final AIAgentAuditHash? inputHash;
  final AIAgentAuditHash? outputHash;

  /// The only serialization shape an audit sink is expected to persist.
  Map<String, Object> toSafeMap() {
    return Map<String, Object>.unmodifiable(<String, Object>{
      'occurred_at': occurredAt.toIso8601String(),
      'kind': kind.name,
      'session_id_hash': sessionIdHash.hex,
      'turn_id_hash': turnIdHash.hex,
      'client_request_id_hash': clientRequestIdHash.hex,
      if (toolCallIdHash != null) 'tool_call_id_hash': toolCallIdHash!.hex,
      'model_role': modelRole.name,
      'provider': provider,
      'model': model,
      if (toolId != null) 'tool_id': toolId!,
      if (toolVersion != null) 'tool_version': toolVersion!,
      if (risk != null) 'risk': risk!.name,
      'decision': decision.name,
      'status': status.name,
      'duration_microseconds': duration.inMicroseconds,
      if (inputHash != null) 'input_hash': inputHash!.hex,
      if (outputHash != null) 'output_hash': outputHash!.hex,
    });
  }

  @override
  String toString() => 'AIAgentAuditEvent(${toSafeMap()})';
}

final RegExp _runtimeIdentifierPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:+/-]*$',
);

String _validatedRuntimeIdentifier(
  String value, {
  required String fieldName,
  required int maxLength,
}) {
  if (value.isEmpty ||
      value.length > maxLength ||
      !_runtimeIdentifierPattern.hasMatch(value)) {
    throw ArgumentError(
      '$fieldName must be a bounded runtime-owned identifier.',
      fieldName,
    );
  }
  return value;
}

Object? _canonicalJsonValue(Object? value) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError('Audit hash input must be finite JSON data.');
    }
    return value;
  }
  if (value is List<Object?>) {
    return value.map<Object?>(_canonicalJsonValue).toList(growable: false);
  }
  if (value is Map<String, Object?>) {
    final sortedKeys = value.keys.toList(growable: false)..sort();
    return <String, Object?>{
      for (final key in sortedKeys) key: _canonicalJsonValue(value[key]),
    };
  }
  throw ArgumentError('Audit hash input must be JSON-compatible data.');
}
