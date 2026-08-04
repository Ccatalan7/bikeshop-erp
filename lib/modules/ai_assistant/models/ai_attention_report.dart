import 'package:flutter/foundation.dart';

import 'ai_assistant_destination.dart';

/// Which day the briefing is about.
enum AIAttentionHorizon {
  today,
  tomorrow;

  String get label => this == AIAttentionHorizon.today ? 'hoy' : 'mañana';
}

/// Where an item came from.
enum AIAttentionSource {
  workshop,
  tasks;

  String get label => this == AIAttentionSource.workshop ? 'Taller' : 'Tareas';

  AIAssistantDestination get destination => this == AIAttentionSource.workshop
      ? AIAssistantDestination.workshopJobs
      : AIAssistantDestination.tasks;
}

/// How one source ended, and nothing else.
///
/// `empty` is only reachable after a read that completed and was authorized.
/// `unavailable` means the question was not answered. There is deliberately no
/// state that blurs the two: "no hay nada" and "no pude mirar" lead an
/// operator to opposite actions.
enum AIAttentionSourceState {
  success,
  empty,
  unavailable,
}

@immutable
class AIAttentionSourceOutcome {
  const AIAttentionSourceOutcome._({
    required this.source,
    required this.state,
    required this.examined,
    required this.reason,
  });

  /// A read that completed and returned rows.
  const AIAttentionSourceOutcome.success({
    required AIAttentionSource source,
    required int examined,
  }) : this._(
          source: source,
          state: AIAttentionSourceState.success,
          examined: examined,
          reason: null,
        );

  /// A read that completed, was authorized, and held nothing.
  const AIAttentionSourceOutcome.empty(AIAttentionSource source)
      : this._(
          source: source,
          state: AIAttentionSourceState.empty,
          examined: 0,
          reason: null,
        );

  /// The read did not happen, or could not be trusted.
  ///
  /// There is no free-text reason: a stack trace, a Postgres message or a
  /// tenant id has no business appearing in the operator's panel, and an
  /// exception string is the easiest way for one to get there. The detail goes
  /// to the log; what surfaces is one of a fixed set of sentences.
  const AIAttentionSourceOutcome.unavailable(
    AIAttentionSource source,
    AIAttentionUnavailableReason reason,
  ) : this._(
          source: source,
          state: AIAttentionSourceState.unavailable,
          examined: 0,
          reason: reason,
        );

  final AIAttentionSource source;
  final AIAttentionSourceState state;

  /// Rows actually looked at. Not "the total of the business": paging is not
  /// explicit in these services, so the briefing says what it examined and
  /// never implies it saw everything.
  final int examined;
  final AIAttentionUnavailableReason? reason;

  bool get isAvailable => state != AIAttentionSourceState.unavailable;
}

/// The only things the panel may say about why a source failed.
enum AIAttentionUnavailableReason {
  /// The module is not part of this session.
  notAvailableHere,

  /// The read did not complete.
  readFailed,

  /// The data could not be confirmed as belonging to this taller.
  couldNotVerify;

  String get label {
    switch (this) {
      case AIAttentionUnavailableReason.notAvailableHere:
        return 'no está disponible en esta sesión';
      case AIAttentionUnavailableReason.readFailed:
        return 'no respondió';
      case AIAttentionUnavailableReason.couldNotVerify:
        return 'no se pudo confirmar que sus datos sean de este taller';
    }
  }
}

/// Why an item is on the list. Ordering is the ranking order.
enum AIAttentionReason {
  workshopOverdue,
  workshopDueOnDay,
  taskOverdue,
  taskDueOnDay,
  taskUrgentBacklog;

  int get rank => index;

  String get label {
    switch (this) {
      case AIAttentionReason.workshopOverdue:
        return 'Entrega atrasada';
      case AIAttentionReason.workshopDueOnDay:
        return 'Entrega comprometida';
      case AIAttentionReason.taskOverdue:
        return 'Tarea atrasada';
      case AIAttentionReason.taskDueOnDay:
        return 'Tarea del día';
      case AIAttentionReason.taskUrgentBacklog:
        return 'Pendiente sin fecha';
    }
  }
}

@immutable
class AIAttentionItem {
  const AIAttentionItem({
    required this.stableId,
    required this.source,
    required this.reason,
    required this.title,
    required this.detail,
    required this.priorityRank,
    required this.dueAt,
    required this.createdAt,
  });

  /// Identity for dedupe. Two items collapse only when this matches — a task
  /// is never dropped merely for referencing a job, because "llamar al cliente
  /// de la PG-00490" is not the same commitment as repairing it.
  final String stableId;
  final AIAttentionSource source;
  final AIAttentionReason reason;
  final String title;
  final String detail;

  /// Lower sorts first: 0 urgent, 1 high, 2 normal, 3 low.
  final int priorityRank;
  final DateTime? dueAt;
  final DateTime? createdAt;
}

@immutable
class AIAttentionReport {
  const AIAttentionReport({
    required this.horizon,
    required this.generatedAt,
    required this.items,
    required this.outcomes,
    required this.selectedBeforeTruncation,
    required this.maxItems,
  });

  final AIAttentionHorizon horizon;

  /// The real instant the briefing was produced, in UTC. Rendered in Chilean
  /// civil time — date *and* clock — so the operator can tell how fresh it is.
  final DateTime generatedAt;
  final List<AIAttentionItem> items;
  final List<AIAttentionSourceOutcome> outcomes;
  final int selectedBeforeTruncation;
  final int maxItems;

  bool get isTruncated => selectedBeforeTruncation > items.length;

  Iterable<AIAttentionSourceOutcome> get unavailableSources =>
      outcomes.where((o) => !o.isAvailable);

  /// No source could be read: the briefing has nothing to say and must not
  /// imply a quiet day.
  bool get isUnavailable => outcomes.every((o) => !o.isAvailable);

  /// Some sources answered and some did not.
  bool get isPartial => !isUnavailable && outcomes.any((o) => !o.isAvailable);

  int get examinedTotal =>
      outcomes.fold(0, (sum, outcome) => sum + outcome.examined);
}
