import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/models/notification_digest.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../models/ai_attention_report.dart';
import 'ai_service.dart';

/// Builds the operational briefing without the model.
///
/// Nothing here asks Gemini anything: not the intent, not the ranking, not a
/// single word of the answer. A briefing an operator plans their day around
/// has to be reproducible and auditable, and a generated one is neither.
class AIAttentionReadModel {
  const AIAttentionReadModel({this.maxItems = 6});

  final int maxItems;

  Future<AIAttentionReport> build({
    required AIAttentionHorizon horizon,
    required AIAssistantTurnAuthority authority,
    required BikeshopService? bikeshopService,
    required TaskService? taskService,
    DateTime? now,
  }) async {
    final instant = now ?? DateTime.now();
    final today = NotificationDigestWindow.businessToday(now: instant);

    // Tomorrow is the next *civil* day, built by incrementing the day field.
    // Adding 24 hours lands on the wrong date twice a year, and Chile changes
    // offset in the middle of the working year.
    //
    // `NotificationDigestWindow.resolve` is deliberately not used: it clamps a
    // future window's end to now, so it can never describe tomorrow.
    final targetDay = horizon == AIAttentionHorizon.today
        ? today
        : DateTime.utc(today.year, today.month, today.day + 1);

    final results = await Future.wait<_SourceResult>([
      _readWorkshop(
        authority: authority,
        service: bikeshopService,
        today: today,
        targetDay: targetDay,
        horizon: horizon,
      ),
      _readTasks(
        authority: authority,
        service: taskService,
        today: today,
        targetDay: targetDay,
        horizon: horizon,
      ),
    ]);

    final selected = <AIAttentionItem>[
      for (final result in results) ...result.items,
    ]..sort(_compare);

    final deduped = <String, AIAttentionItem>{};
    for (final item in selected) {
      deduped.putIfAbsent(item.stableId, () => item);
    }
    final ordered = deduped.values.toList();

    return AIAttentionReport(
      // The real instant the briefing was produced, in UTC. It used to be
      // civil midnight, which is a date, not a time: a briefing stamped
      // "00:00" tells the operator nothing about how fresh it is, and freshness
      // is the whole reason the stamp exists.
      generatedAt: instant.toUtc(),
      horizon: horizon,
      items: ordered.take(maxItems).toList(growable: false),
      outcomes: [for (final result in results) result.outcome],
      selectedBeforeTruncation: ordered.length,
      maxItems: maxItems,
    );
  }

  // ---------------------------------------------------------------- workshop

  Future<_SourceResult> _readWorkshop({
    required AIAssistantTurnAuthority authority,
    required BikeshopService? service,
    required DateTime today,
    required DateTime targetDay,
    required AIAttentionHorizon horizon,
  }) async {
    if (service == null) {
      return _SourceResult.unavailable(
        AIAttentionSource.workshop,
        AIAttentionUnavailableReason.notAvailableHere,
      );
    }

    List<MechanicJob> jobs;
    try {
      // A scope that is null *before* a cold read is normal. The post-check is
      // the one that matters: a read can span a tenant switch and come back
      // holding rows this turn may not see.
      jobs = await service.getJobs(includeCompleted: true, forceRefresh: true);
      authority.requireServiceScope('taller', service.authorityScope);
      authority.verifyRows('taller', jobs, (job) => job.tenantId);
      for (final job in jobs) {
        final custom = job.customStatus;
        if (custom == null) continue;
        // The status row is joined from another table and carries its own
        // tenant, so it is verified too rather than trusted for arriving
        // attached to a verified job.
        authority.verifyRows('taller', [custom], (status) => status.tenantId);
      }
    } on AIAssistantSourceUnavailable {
      _logSourceFailure(
        AIAttentionSource.workshop,
        AIAttentionUnavailableReason.couldNotVerify,
        AIAssistantSourceUnavailable,
      );
      return _SourceResult.unavailable(
        AIAttentionSource.workshop,
        AIAttentionUnavailableReason.couldNotVerify,
      );
    } catch (e) {
      _logSourceFailure(
        AIAttentionSource.workshop,
        AIAttentionUnavailableReason.readFailed,
        e.runtimeType,
      );
      return _SourceResult.unavailable(
        AIAttentionSource.workshop,
        AIAttentionUnavailableReason.readFailed,
      );
    }

    if (jobs.isEmpty) {
      return _SourceResult.empty(AIAttentionSource.workshop);
    }

    final items = <AIAttentionItem>[];
    for (var index = 0; index < jobs.length; index++) {
      final job = jobs[index];
      if (!_isOpenJob(job)) continue;
      final deadline = job.deliveryDeadline;
      if (deadline == null) continue;

      final deadlineDay = NotificationDigestWindow.businessToday(now: deadline);
      final overdue = _civilKey(deadlineDay) < _civilKey(today);
      final onTargetDay = _civilKey(deadlineDay) == _civilKey(targetDay);

      // Overdue always counts, on either horizon: a late delivery does not
      // stop being tomorrow's problem.
      if (!overdue && !onTargetDay) continue;

      items.add(
        AIAttentionItem(
          stableId: _rowIdentity('job', job.id, index, [
            job.jobNumber,
            job.customerId,
            deadline.toUtc().toIso8601String(),
          ]),
          source: AIAttentionSource.workshop,
          reason: overdue
              ? AIAttentionReason.workshopOverdue
              : AIAttentionReason.workshopDueOnDay,
          title: job.jobNumber ?? 'Trabajo sin número',
          detail: _jobDetail(job),
          priorityRank: _jobPriorityRank(job.priority),
          dueAt: deadline,
          createdAt: job.createdAt,
        ),
      );
    }

    return _SourceResult(
      outcome: AIAttentionSourceOutcome.success(
        source: AIAttentionSource.workshop,
        examined: jobs.length,
      ),
      items: items,
    );
  }

  // ------------------------------------------------------------------- tasks

  Future<_SourceResult> _readTasks({
    required AIAssistantTurnAuthority authority,
    required TaskService? service,
    required DateTime today,
    required DateTime targetDay,
    required AIAttentionHorizon horizon,
  }) async {
    if (service == null) {
      return _SourceResult.unavailable(
        AIAttentionSource.tasks,
        AIAttentionUnavailableReason.notAvailableHere,
      );
    }

    List<TaskModel> tasks;
    try {
      // The fetch returns the scope it actually loaded for. A null means it
      // declined to load — never an empty task list.
      final loadedScope = await service.fetchTasksForPreload();
      if (loadedScope == null) {
        _logSourceFailure(
          AIAttentionSource.tasks,
          AIAttentionUnavailableReason.couldNotVerify,
          Null,
        );
        return _SourceResult.unavailable(
          AIAttentionSource.tasks,
          AIAttentionUnavailableReason.couldNotVerify,
        );
      }
      authority.requireServiceScope('tareas', loadedScope);
      authority.requireServiceScope('tareas', service.authorityScope);
      tasks = authority.verifyRows(
        'tareas',
        service.tasks,
        (task) => task.tenantId,
      );
    } on AIAssistantSourceUnavailable {
      _logSourceFailure(
        AIAttentionSource.tasks,
        AIAttentionUnavailableReason.couldNotVerify,
        AIAssistantSourceUnavailable,
      );
      return _SourceResult.unavailable(
        AIAttentionSource.tasks,
        AIAttentionUnavailableReason.couldNotVerify,
      );
    } catch (e) {
      _logSourceFailure(
        AIAttentionSource.tasks,
        AIAttentionUnavailableReason.readFailed,
        e.runtimeType,
      );
      return _SourceResult.unavailable(
        AIAttentionSource.tasks,
        AIAttentionUnavailableReason.readFailed,
      );
    }

    if (tasks.isEmpty) {
      return _SourceResult.empty(AIAttentionSource.tasks);
    }

    final items = <AIAttentionItem>[];
    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      if (task.status == TaskStatus.completed ||
          task.status == TaskStatus.cancelled) {
        continue;
      }

      final due = task.dueDate;
      final isUrgentish = task.priority == TaskPriority.urgent ||
          task.priority == TaskPriority.high;

      AIAttentionReason? reason;
      if (due != null) {
        final dueDay = NotificationDigestWindow.businessToday(now: due);
        if (_civilKey(dueDay) < _civilKey(today)) {
          reason = AIAttentionReason.taskOverdue;
        } else if (_civilKey(dueDay) == _civilKey(targetDay)) {
          reason = AIAttentionReason.taskDueOnDay;
        }
      } else if (isUrgentish) {
        reason = AIAttentionReason.taskUrgentBacklog;
      }
      if (reason == null) continue;

      items.add(
        AIAttentionItem(
          stableId: _rowIdentity('task', task.id, index, [
            task.title,
            task.linkedJobId,
            due?.toUtc().toIso8601String(),
            task.createdAt.toUtc().toIso8601String(),
          ]),
          source: AIAttentionSource.tasks,
          reason: reason,
          title: task.title,
          detail: _taskDetail(task, reason),
          priorityRank: _taskPriorityRank(task.priority),
          dueAt: due,
          createdAt: task.createdAt,
        ),
      );
    }

    return _SourceResult(
      outcome: AIAttentionSourceOutcome.success(
        source: AIAttentionSource.tasks,
        examined: tasks.length,
      ),
      items: items,
    );
  }

  // ------------------------------------------------------------------ rules

  /// A job counts as open unless it was cancelled or actually handed over.
  ///
  /// `finalizado` stays in: the bike is ready and nobody has come for it, and
  /// that is precisely a thing that needs attention.
  static bool _isOpenJob(MechanicJob job) {
    if (job.status == JobStatus.cancelado) return false;
    if (job.deliveredAt != null) return false;
    if (job.status == JobStatus.entregado) return false;
    final custom = job.customStatus;
    if (custom != null) {
      if (custom.triggersDelivery) return false;
      if (custom.code.trim().toLowerCase() == 'entregado') return false;
    }
    return true;
  }

  /// Identity for dedupe.
  ///
  /// A real id is used when there is one. Without it, falling back to a title
  /// or a job number would let two genuinely different rows — two tasks called
  /// "Llamar al cliente" — collapse into one and silently drop a commitment.
  /// The synthetic identity therefore includes the row's position and its
  /// distinguishing fields, and stays the same across runs over the same data.
  static String _rowIdentity(
    String kind,
    String? id,
    int index,
    List<String?> fields,
  ) {
    final trimmed = id?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return '$kind:$trimmed';
    final parts = fields.map((f) => f?.trim() ?? '').join('|');
    return '$kind:#$index|$parts';
  }

  static int _jobPriorityRank(JobPriority priority) {
    switch (priority) {
      case JobPriority.urgente:
        return 0;
      case JobPriority.alta:
        return 1;
      case JobPriority.normal:
        return 2;
      case JobPriority.baja:
        return 3;
    }
  }

  static int _taskPriorityRank(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.urgent:
        return 0;
      case TaskPriority.high:
        return 1;
      case TaskPriority.normal:
        return 2;
      case TaskPriority.low:
        return 3;
    }
  }

  static String _jobDetail(MechanicJob job) {
    final parts = <String>[
      job.status.displayName,
      if (job.customStatus != null) job.customStatus!.name,
    ];
    return parts.join(' · ');
  }

  static String _taskDetail(TaskModel task, AIAttentionReason reason) {
    return reason == AIAttentionReason.taskUrgentBacklog
        ? 'Sin fecha comprometida'
        : task.status == TaskStatus.inProgress
            ? 'En curso'
            : 'Pendiente';
  }

  /// Every ordering key is explicit, so two runs over the same data produce
  /// the same list.
  static int _compare(AIAttentionItem a, AIAttentionItem b) {
    final byReason = a.reason.rank.compareTo(b.reason.rank);
    if (byReason != 0) return byReason;

    final byPriority = a.priorityRank.compareTo(b.priorityRank);
    if (byPriority != 0) return byPriority;

    final byDue = _dateSort(a.dueAt).compareTo(_dateSort(b.dueAt));
    if (byDue != 0) return byDue;

    final byAge = _dateSort(a.createdAt).compareTo(_dateSort(b.createdAt));
    if (byAge != 0) return byAge;

    return a.stableId.compareTo(b.stableId);
  }

  static int _dateSort(DateTime? value) =>
      value?.toUtc().millisecondsSinceEpoch ?? 1 << 62;

  /// Civil day as a comparable yyyyMMdd integer, so two instants in different
  /// offsets are compared as the dates a person would read.
  static int _civilKey(DateTime day) =>
      day.year * 10000 + day.month * 100 + day.day;

  @visibleForTesting
  static int civilKeyForTesting(DateTime day) => _civilKey(day);

  /// Logs a failed source without its message.
  ///
  /// The exception text is where a tenant id, a token or a Postgres detail
  /// lives; interpolating it into a log puts those in a crash report, a
  /// terminal or a screen share. The type and the category are enough to
  /// diagnose, and carry nothing about anyone's data.
  static void _logSourceFailure(
    AIAttentionSource source,
    AIAttentionUnavailableReason reason,
    Type errorType,
  ) {
    if (!kDebugMode) return;
    debugPrint(
      '⛔ [AIAttention] ${source.name}: ${reason.name} ($errorType)',
    );
  }

  static bool _timeZonesReady = false;
  static tz.Location? _santiagoLocation;

  static tz.Location get _santiago {
    if (!_timeZonesReady) {
      tzdata.initializeTimeZones();
      _timeZonesReady = true;
    }
    return _santiagoLocation ??= tz.getLocation('America/Santiago');
  }

  /// Renders an instant as the date and clock time an operator in Chile would
  /// read, with whatever offset was in force at that instant.
  static String formatChileStamp(DateTime instant) {
    final local = tz.TZDateTime.from(instant.toUtc(), _santiago);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

@immutable
class _SourceResult {
  const _SourceResult({required this.outcome, required this.items});

  _SourceResult.unavailable(
    AIAttentionSource source,
    AIAttentionUnavailableReason reason,
  )   : outcome = AIAttentionSourceOutcome.unavailable(source, reason),
        items = const <AIAttentionItem>[];

  _SourceResult.empty(AIAttentionSource source)
      : outcome = AIAttentionSourceOutcome.empty(source),
        items = const <AIAttentionItem>[];

  final AIAttentionSourceOutcome outcome;
  final List<AIAttentionItem> items;
}
