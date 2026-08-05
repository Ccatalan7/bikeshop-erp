import '../models/ai_agent_audit_event.dart';

/// Destination for sanitized assistant audit events.
///
/// Implementations receive an [AIAgentAuditEvent], whose closed schema cannot
/// contain raw prompts, tool payloads, identities, tenant ids or exceptions.
abstract interface class AIAgentAuditSink {
  Future<void> record(AIAgentAuditEvent event);
}

/// Sink used when auditing is intentionally unavailable.
final class NoopAIAgentAuditSink implements AIAgentAuditSink {
  const NoopAIAgentAuditSink();

  @override
  Future<void> record(AIAgentAuditEvent event) async {}
}

/// Failure boundary that prevents audit infrastructure from breaking a turn.
///
/// Errors are intentionally swallowed without logging the error object or
/// stack trace: either may contain provider payloads or other sensitive data.
final class FailSafeAIAgentAuditSink implements AIAgentAuditSink {
  FailSafeAIAgentAuditSink(this._delegate);

  final AIAgentAuditSink _delegate;
  int _droppedEventCount = 0;

  /// Sanitized health signal; the delegate exception is never retained.
  int get droppedEventCount => _droppedEventCount;

  @override
  Future<void> record(AIAgentAuditEvent event) async {
    try {
      await _delegate.record(event);
    } on Object {
      // Read/model telemetry is non-fatal, but losing it must remain visible.
      // Client-side write tools are denied by policy; any future write
      // activation requires a durable server-side audit gate before commit.
      _droppedEventCount++;
    }
  }
}
