import 'dart:collection';

import '../models/ai_agent_audit_event.dart';
import 'ai_agent_audit_sink.dart';

/// Bounded, process-local audit sink for tests and local runtime diagnostics.
final class InMemoryAIAgentAuditSink implements AIAgentAuditSink {
  InMemoryAIAgentAuditSink({this.maxEvents = defaultMaxEvents}) {
    if (maxEvents <= 0 || maxEvents > maximumAllowedEvents) {
      throw ArgumentError.value(
        maxEvents,
        'maxEvents',
        'Must be between 1 and $maximumAllowedEvents.',
      );
    }
  }

  static const int defaultMaxEvents = 256;
  static const int maximumAllowedEvents = 10000;

  final int maxEvents;
  final ListQueue<AIAgentAuditEvent> _events = ListQueue<AIAgentAuditEvent>();

  int _droppedEventCount = 0;

  List<AIAgentAuditEvent> get events =>
      List<AIAgentAuditEvent>.unmodifiable(_events);

  int get droppedEventCount => _droppedEventCount;

  @override
  Future<void> record(AIAgentAuditEvent event) async {
    if (_events.length == maxEvents) {
      _events.removeFirst();
      _droppedEventCount += 1;
    }
    _events.addLast(event);
  }

  void clear() {
    _events.clear();
    _droppedEventCount = 0;
  }
}
