import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_audit_event.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_contracts.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_agent_audit_sink.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/in_memory_ai_agent_audit_sink.dart';

void main() {
  group('AIAgentAuditHash', () {
    test('hashes sensitive values without retaining the clear text', () {
      const raw = 'tenant/customer@example.com/private prompt';

      final digest = AIAgentAuditHash.sha256OfUtf8(raw);

      expect(digest.hex, hasLength(64));
      expect(digest.hex, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(digest.hex, isNot(contains(raw)));
      expect(AIAgentAuditHash.fromSha256Hex(digest.hex), digest);
      expect(
        () => AIAgentAuditHash.fromSha256Hex(raw),
        throwsArgumentError,
      );
    });

    test('canonical JSON hashes ignore map insertion order', () {
      final first = AIAgentAuditHash.sha256OfJson(const <String, Object?>{
        'query': 'cadena privada',
        'filters': <String, Object?>{'active': true, 'limit': 5},
      });
      final second = AIAgentAuditHash.sha256OfJson(const <String, Object?>{
        'filters': <String, Object?>{'limit': 5, 'active': true},
        'query': 'cadena privada',
      });

      expect(first, second);
    });

    test('keyed JSON hashes resist dictionaries and stay canonical', () {
      final firstKey = List<int>.filled(32, 7);
      final secondKey = List<int>.filled(32, 8);
      final first = AIAgentAuditHash.hmacSha256OfJson(
        key: firstKey,
        value: const <String, Object?>{'query': 'stock bajo', 'limit': 5},
      );
      final reordered = AIAgentAuditHash.hmacSha256OfJson(
        key: firstKey,
        value: const <String, Object?>{'limit': 5, 'query': 'stock bajo'},
      );
      final differentlyKeyed = AIAgentAuditHash.hmacSha256OfJson(
        key: secondKey,
        value: const <String, Object?>{'query': 'stock bajo', 'limit': 5},
      );

      expect(first, reordered);
      expect(first, isNot(differentlyKeyed));
      expect(
        () => AIAgentAuditHash.hmacSha256OfUtf8(
          key: const <int>[1, 2, 3],
          value: 'hola',
        ),
        throwsArgumentError,
      );
    });
  });

  group('AIAgentAuditEvent', () {
    test('serializes only allowlisted metadata and hashes', () {
      const prompt = 'Busca la factura privada de cliente@example.com';
      const arguments = 'rut=11.111.111-1&tenant=secret-tenant';
      const result = 'Cliente privado, saldo 99000';
      final event = _toolEvent(
        inputHash: AIAgentAuditHash.sha256OfUtf8('$prompt|$arguments'),
        outputHash: AIAgentAuditHash.sha256OfUtf8(result),
      );

      final encoded = jsonEncode(event.toSafeMap());

      expect(encoded, isNot(contains(prompt)));
      expect(encoded, isNot(contains(arguments)));
      expect(encoded, isNot(contains(result)));
      expect(encoded, isNot(contains('cliente@example.com')));
      expect(encoded, isNot(contains('secret-tenant')));
      expect(event.toSafeMap(), containsPair('model_role', 'fast'));
      expect(event.toSafeMap(), containsPair('provider', 'gemini'));
      expect(
        event.toSafeMap(),
        containsPair('model', 'gemini-2.5-flash-lite'),
      );
      expect(event.toSafeMap(), containsPair('tool_id', 'inventory_search'));
      expect(event.toSafeMap(), containsPair('tool_version', 'v1'));
      expect(event.toSafeMap(), containsPair('risk', 'read'));
      expect(event.toSafeMap(), containsPair('decision', 'allowed'));
      expect(event.toSafeMap(), containsPair('status', 'succeeded'));
      expect(
        event.toSafeMap().keys,
        isNot(containsAll(<String>[
          'prompt',
          'arguments',
          'result',
          'tenant',
          'user',
          'exception',
        ])),
      );
    });

    test('rejects identifiers that could carry free-form or personal data', () {
      expect(
        () => _modelEvent(provider: 'customer@example.com'),
        throwsArgumentError,
      );
      expect(
        () => _modelEvent(model: 'model with arbitrary text'),
        throwsArgumentError,
      );
    });

    test('requires complete tool identity only for tool events', () {
      expect(
        () => AIAgentAuditEvent(
          occurredAt: DateTime.utc(2026, 8, 4),
          kind: AIAgentAuditEventKind.toolExecution,
          sessionIdHash: _hash('session'),
          turnIdHash: _hash('turn'),
          clientRequestIdHash: _hash('request'),
          modelRole: AIAgentModelRole.fast,
          provider: 'gemini',
          model: 'gemini-2.5-flash-lite',
          decision: AIAgentAuditDecision.allowed,
          status: AIAgentAuditStatus.started,
          duration: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => AIAgentAuditEvent(
          occurredAt: DateTime.utc(2026, 8, 4),
          kind: AIAgentAuditEventKind.modelInvocation,
          sessionIdHash: _hash('session'),
          turnIdHash: _hash('turn'),
          clientRequestIdHash: _hash('request'),
          toolCallIdHash: _hash('call'),
          modelRole: AIAgentModelRole.fast,
          provider: 'gemini',
          model: 'gemini-2.5-flash-lite',
          toolId: 'inventory_search',
          toolVersion: 'v1',
          risk: AIToolRiskLevel.read,
          decision: AIAgentAuditDecision.notApplicable,
          status: AIAgentAuditStatus.started,
          duration: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
  });

  group('audit sinks', () {
    test('in-memory sink keeps a bounded FIFO buffer', () async {
      final sink = InMemoryAIAgentAuditSink(maxEvents: 2);
      final first = _modelEvent(model: 'model-v1');
      final second = _modelEvent(model: 'model-v2');
      final third = _modelEvent(model: 'model-v3');

      await sink.record(first);
      await sink.record(second);
      await sink.record(third);

      expect(sink.events, <AIAgentAuditEvent>[second, third]);
      expect(sink.droppedEventCount, 1);
      expect(() => sink.events.add(first), throwsUnsupportedError);

      sink.clear();
      expect(sink.events, isEmpty);
      expect(sink.droppedEventCount, 0);
    });

    test('fail-safe sink absorbs delegate errors and retains no exception',
        () async {
      final sink = FailSafeAIAgentAuditSink(_ThrowingAuditSink());

      await expectLater(sink.record(_modelEvent()), completes);
      expect(sink.droppedEventCount, 1);
    });

    test('buffer capacity is bounded by contract', () {
      expect(
        () => InMemoryAIAgentAuditSink(maxEvents: 0),
        throwsArgumentError,
      );
      expect(
        () => InMemoryAIAgentAuditSink(
          maxEvents: InMemoryAIAgentAuditSink.maximumAllowedEvents + 1,
        ),
        throwsArgumentError,
      );
    });
  });
}

AIAgentAuditEvent _modelEvent({
  String provider = 'gemini',
  String model = 'gemini-2.5-flash-lite',
}) {
  return AIAgentAuditEvent(
    occurredAt: DateTime.utc(2026, 8, 4, 12, 30),
    kind: AIAgentAuditEventKind.modelInvocation,
    sessionIdHash: _hash('session-1'),
    turnIdHash: _hash('turn-1'),
    clientRequestIdHash: _hash('request-1'),
    modelRole: AIAgentModelRole.fast,
    provider: provider,
    model: model,
    decision: AIAgentAuditDecision.notApplicable,
    status: AIAgentAuditStatus.succeeded,
    duration: const Duration(milliseconds: 42),
    inputHash: _hash('private input'),
    outputHash: _hash('private output'),
  );
}

AIAgentAuditEvent _toolEvent({
  AIAgentAuditHash? inputHash,
  AIAgentAuditHash? outputHash,
}) {
  return AIAgentAuditEvent(
    occurredAt: DateTime.utc(2026, 8, 4, 12, 30),
    kind: AIAgentAuditEventKind.toolExecution,
    sessionIdHash: _hash('session-1'),
    turnIdHash: _hash('turn-1'),
    clientRequestIdHash: _hash('request-1'),
    toolCallIdHash: _hash('tool-call-1'),
    modelRole: AIAgentModelRole.fast,
    provider: 'gemini',
    model: 'gemini-2.5-flash-lite',
    toolId: 'inventory_search',
    toolVersion: 'v1',
    risk: AIToolRiskLevel.read,
    decision: AIAgentAuditDecision.allowed,
    status: AIAgentAuditStatus.succeeded,
    duration: const Duration(milliseconds: 15),
    inputHash: inputHash,
    outputHash: outputHash,
  );
}

AIAgentAuditHash _hash(String value) => AIAgentAuditHash.sha256OfUtf8(value);

final class _ThrowingAuditSink implements AIAgentAuditSink {
  @override
  Future<void> record(AIAgentAuditEvent event) async {
    throw StateError(
      'provider leaked private prompt and customer@example.com',
    );
  }
}
