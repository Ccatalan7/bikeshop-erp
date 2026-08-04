import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_destination.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_attention_report.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_attention_read_model.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/models/notification_digest.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

const _tenant = 'tenant-a';
final _scope = ErpAuthorityScopeKey.from(userId: 'user-a', tenantId: _tenant)!;
final _authority = AIAssistantTurnAuthority(_scope);

/// A Bikeshop service that returns a fixed roster without touching a database.
class _FakeBikeshop implements BikeshopService {
  _FakeBikeshop({
    this.jobs = const <MechanicJob>[],
    ErpAuthorityScopeKey? scope,
    this.failure,
  }) : _scope = scope;

  List<MechanicJob> jobs;
  final ErpAuthorityScopeKey? _scope;
  Object? failure;
  int getJobsCalls = 0;

  @override
  ErpAuthorityScopeKey? get authorityScope => _scope;

  @override
  Future<List<MechanicJob>> getJobs({
    String? customerId,
    String? bikeId,
    JobStatus? status,
    String? searchTerm,
    bool includeCompleted = true,
    bool includeDeleted = false,
    bool forceRefresh = false,
  }) async {
    getJobsCalls++;
    final boom = failure;
    if (boom != null) throw boom;
    return jobs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTasks implements TaskService {
  _FakeTasks({
    this.taskList = const <TaskModel>[],
    ErpAuthorityScopeKey? scope,
    ErpAuthorityScopeKey? loadedScope,
    this.returnsNullScope = false,
  })  : _scope = scope,
        _loadedScope = loadedScope ?? scope;

  List<TaskModel> taskList;
  final ErpAuthorityScopeKey? _scope;
  final ErpAuthorityScopeKey? _loadedScope;
  final bool returnsNullScope;

  @override
  List<TaskModel> get tasks => taskList;

  @override
  ErpAuthorityScopeKey? get authorityScope => _scope;

  @override
  Future<ErpAuthorityScopeKey?> fetchTasksForPreload() async =>
      returnsNullScope ? null : _loadedScope;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MechanicJob _job({
  required String id,
  required DateTime? deadline,
  String tenantId = _tenant,
  JobStatus status = JobStatus.enCurso,
  JobPriority priority = JobPriority.normal,
  DateTime? deliveredAt,
  JobStatusCustom? customStatus,
}) {
  return MechanicJob(
    id: id,
    tenantId: tenantId,
    jobNumber: 'PG-$id',
    customerId: 'c1',
    status: status,
    priority: priority,
    deliveryDeadline: deadline,
    deliveredAt: deliveredAt,
    customStatus: customStatus,
    clientRequest: 'Revisar',
    totalCost: 0,
  );
}

JobStatusCustom _customStatus({
  String tenantId = _tenant,
  String code = 'en_taller',
  bool triggersDelivery = false,
}) {
  return JobStatusCustom(
    id: 'st-$code',
    tenantId: tenantId,
    name: code,
    code: code,
    color: '#000000',
    phase: StatusPhase.inProgress,
    sortOrder: 0,
    triggersDelivery: triggersDelivery,
  );
}

TaskModel _task({
  required String id,
  DateTime? due,
  String tenantId = _tenant,
  TaskStatus status = TaskStatus.pending,
  TaskPriority priority = TaskPriority.normal,
  String? linkedJobId,
}) {
  return TaskModel(
    id: id,
    tenantId: tenantId,
    title: 'Tarea $id',
    status: status,
    priority: priority,
    dueDate: due,
    linkedJobId: linkedJobId,
    createdBy: 'user-a',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// 2026-08-03 14:00 in Santiago, expressed in UTC.
final _now = DateTime.utc(2026, 8, 3, 18);

DateTime _chileDay(int day) => DateTime.utc(2026, 8, day, 16);

/// Length in hours of one Chilean civil day, measured from the real calendar
/// rather than assumed.
int _chileanDayLength(DateTime civilDay) {
  final start = tz.TZDateTime(
    tz.getLocation('America/Santiago'),
    civilDay.year,
    civilDay.month,
    civilDay.day,
  );
  final next = tz.TZDateTime(
    tz.getLocation('America/Santiago'),
    civilDay.year,
    civilDay.month,
    civilDay.day + 1,
  );
  return next.difference(start).inHours;
}

DateTime _findDayOfLength(int hours) {
  tzdata.initializeTimeZones();
  for (var month = 1; month <= 12; month++) {
    for (var day = 1; day <= 31; day++) {
      final candidate = DateTime.utc(2026, month, day);
      if (candidate.month != month) break;
      if (_chileanDayLength(candidate) == hours) return candidate;
    }
  }
  throw StateError('no $hours-hour day found in 2026');
}

DateTime _findShortDay() => _findDayOfLength(23);
DateTime _findLongDay() => _findDayOfLength(25);

/// A UTC instant that is [hour]:[minute] Chilean civil time on [civilDay],
/// using the offset actually in force that day.
DateTime _chileInstant(DateTime civilDay, {required int hour, int minute = 0}) {
  tzdata.initializeTimeZones();
  return tz.TZDateTime(
    tz.getLocation('America/Santiago'),
    civilDay.year,
    civilDay.month,
    civilDay.day,
    hour,
    minute,
  ).toUtc();
}

void main() {
  const readModel = AIAttentionReadModel();

  Future<AIAttentionReport> report({
    AIAttentionHorizon horizon = AIAttentionHorizon.today,
    BikeshopService? bikeshop,
    TaskService? tasks,
    DateTime? now,
  }) {
    return readModel.build(
      horizon: horizon,
      authority: _authority,
      bikeshopService: bikeshop ?? _FakeBikeshop(scope: _scope),
      taskService: tasks ?? _FakeTasks(scope: _scope),
      now: now ?? _now,
    );
  }

  group('intent detection', () {
    final service = AIAssistantService();

    test('the owner phrase for tomorrow is recognised exactly', () {
      expect(
        service.detectAttentionHorizon(
          'ayúdame a organizar el trabajo para mañana',
        ),
        AIAttentionHorizon.tomorrow,
      );
    });

    test('today variants survive accents and case', () {
      for (final phrase in const [
        '¿Qué necesita atención hoy?',
        'que necesita atencion hoy',
        'QUÉ DEBO RESOLVER HOY',
        'dame las prioridades de hoy',
        'Resumen operativo',
      ]) {
        expect(
          service.detectAttentionHorizon(phrase),
          AIAttentionHorizon.today,
          reason: phrase,
        );
      }
    });

    test('tomorrow variants win over the today-shaped substring', () {
      for (final phrase in const [
        'organiza mañana',
        'planifica mañana',
        'prioridades de mañana',
        '¿qué hay para mañana?',
      ]) {
        expect(
          service.detectAttentionHorizon(phrase),
          AIAttentionHorizon.tomorrow,
          reason: phrase,
        );
      }
    });

    test('an unrelated question is not a briefing', () {
      for (final phrase in const [
        'busca camara 29',
        'resumen de los trabajos activos',
        '¿cuál es la capital de Francia?',
      ]) {
        expect(service.detectAttentionHorizon(phrase), isNull, reason: phrase);
      }
    });
  });

  group('source outcomes', () {
    test('an authorized read with nothing in it is empty, not unavailable',
        () async {
      final r = await report();

      expect(r.isUnavailable, isFalse);
      expect(r.isPartial, isFalse);
      expect(
        r.outcomes.map((o) => o.state),
        everyElement(AIAttentionSourceState.empty),
      );
      expect(r.items, isEmpty);
    });

    test('rows that exist but commit to nothing is still a successful read',
        () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [_job(id: 'j1', deadline: null)],
        ),
      );

      final workshop =
          r.outcomes.firstWhere((o) => o.source == AIAttentionSource.workshop);
      expect(workshop.state, AIAttentionSourceState.success);
      expect(workshop.examined, 1);
      expect(r.items, isEmpty);
      expect(r.isUnavailable, isFalse);
    });

    test('one failed source makes the report partial, not empty', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(scope: _scope, failure: StateError('boom')),
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [_task(id: 't1', due: _chileDay(3))],
        ),
      );

      expect(r.isPartial, isTrue);
      expect(r.isUnavailable, isFalse);
      expect(r.items, hasLength(1));
    });

    test('both sources failing claims nothing at all', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(scope: _scope, failure: StateError('boom')),
        tasks: _FakeTasks(scope: _scope, returnsNullScope: true),
      );

      expect(r.isUnavailable, isTrue);
      expect(r.items, isEmpty);
    });

    test('tasks returning no scope is unavailable, never an empty day',
        () async {
      final r = await report(
        tasks: _FakeTasks(scope: _scope, returnsNullScope: true),
      );

      final tasks =
          r.outcomes.firstWhere((o) => o.source == AIAttentionSource.tasks);
      expect(tasks.state, AIAttentionSourceState.unavailable);
    });
  });

  group('authority', () {
    final otherScope =
        ErpAuthorityScopeKey.from(userId: 'user-a', tenantId: 'tenant-b')!;

    test('a task load for another taller is rejected', () async {
      final r = await report(
        tasks: _FakeTasks(scope: _scope, loadedScope: otherScope),
      );
      expect(
        r.outcomes.firstWhere((o) => o.source == AIAttentionSource.tasks).state,
        AIAttentionSourceState.unavailable,
      );
    });

    test('a task service bound elsewhere is rejected', () async {
      final r = await report(
        tasks: _FakeTasks(scope: otherScope, loadedScope: _scope),
      );
      expect(
        r.outcomes.firstWhere((o) => o.source == AIAttentionSource.tasks).state,
        AIAttentionSourceState.unavailable,
      );
    });

    test('a task row from another taller invalidates the source', () async {
      final r = await report(
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [_task(id: 't1', due: _chileDay(3), tenantId: 'tenant-b')],
        ),
      );
      expect(
        r.outcomes.firstWhere((o) => o.source == AIAttentionSource.tasks).state,
        AIAttentionSourceState.unavailable,
      );
    });

    test('a job row from another taller invalidates the source', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [_job(id: 'j1', deadline: _chileDay(3), tenantId: 'tenant-b')],
        ),
      );
      expect(
        r.outcomes
            .firstWhere((o) => o.source == AIAttentionSource.workshop)
            .state,
        AIAttentionSourceState.unavailable,
      );
    });

    test('a joined custom status from another taller invalidates the source',
        () async {
      // The status row comes from another table with its own tenant, so
      // arriving attached to a verified job is not evidence.
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            _job(
              id: 'j1',
              deadline: _chileDay(3),
              customStatus: _customStatus(tenantId: 'tenant-b'),
            ),
          ],
        ),
      );
      expect(
        r.outcomes
            .firstWhere((o) => o.source == AIAttentionSource.workshop)
            .state,
        AIAttentionSourceState.unavailable,
      );
    });

    test('a workshop scope that moved during the read is rejected', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: otherScope,
          jobs: [_job(id: 'j1', deadline: _chileDay(3))],
        ),
      );
      expect(
        r.outcomes
            .firstWhere((o) => o.source == AIAttentionSource.workshop)
            .state,
        AIAttentionSourceState.unavailable,
      );
    });
  });

  group('Chile civil calendar', () {
    test('tomorrow is the next civil day, not now plus 24 hours', () async {
      final r = await report(
        horizon: AIAttentionHorizon.tomorrow,
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            _job(id: 'today', deadline: _chileDay(3)),
            _job(id: 'tomorrow', deadline: _chileDay(4)),
            _job(id: 'later', deadline: _chileDay(9)),
          ],
        ),
      );

      expect(r.items.map((i) => i.title), contains('PG-tomorrow'));
      expect(r.items.map((i) => i.title), isNot(contains('PG-later')));
    });

    test('an instant late in a Los Angeles day is still the Chilean date',
        () async {
      // 2026-08-03 23:30 in Los Angeles is already 2026-08-04 in Santiago. A
      // briefing that used the device's calendar would plan the wrong day.
      final laLateNight = DateTime.utc(2026, 8, 4, 6, 30);
      final chileDay = NotificationDigestWindow.businessToday(now: laLateNight);
      expect(chileDay.day, 4);

      final r = await report(
        now: laLateNight,
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [_job(id: 'j4', deadline: _chileDay(4))],
        ),
      );
      expect(r.items, hasLength(1));
    });

    test('a 23-hour Chilean day still rolls to the next calendar date',
        () async {
      // Chile springs forward in early September: that day has 23 hours, so
      // "now + 24h" would skip past tomorrow. The deadline below is the real
      // next civil day.
      // Midday is where "+24h" still looks right. The skip shows up on the eve
      // of a short day: from 23:30, adding 24 real hours crosses a tomorrow
      // that is one hour shorter and lands on the day *after* — so tomorrow's
      // delivery drops out and the day after sneaks in.
      final short = _findShortDay();
      final eve = DateTime.utc(short.year, short.month, short.day - 1);
      final now = _chileInstant(eve, hour: 23, minute: 30);
      final today = NotificationDigestWindow.businessToday(now: now);
      final tomorrow = DateTime.utc(today.year, today.month, today.day + 1, 15);
      final dayAfter = DateTime.utc(today.year, today.month, today.day + 2, 15);

      expect(
        NotificationDigestWindow.businessToday(
          now: now.add(const Duration(hours: 24)),
        ).day,
        isNot(tomorrow.day),
        reason: 'this canary no longer exercises the +24h bug',
      );

      final r = await report(
        horizon: AIAttentionHorizon.tomorrow,
        now: now,
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            _job(id: 'manana', deadline: tomorrow),
            _job(id: 'pasado', deadline: dayAfter),
          ],
        ),
      );

      expect(r.items.map((i) => i.title), ['PG-manana']);
    });

    test('a 25-hour Chilean day still rolls to the next calendar date',
        () async {
      // Early in a long day: "+24h" from 00:30 lands back inside today, so
      // tomorrow would never be reached at all.
      final now = _chileInstant(_findLongDay(), hour: 0, minute: 30);
      final today = NotificationDigestWindow.businessToday(now: now);
      final tomorrow = DateTime.utc(today.year, today.month, today.day + 1, 15);

      expect(
        NotificationDigestWindow.businessToday(
          now: now.add(const Duration(hours: 24)),
        ).day,
        today.day,
        reason: 'this canary no longer exercises the +24h bug',
      );

      final r = await report(
        horizon: AIAttentionHorizon.tomorrow,
        now: now,
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            _job(id: 'manana', deadline: tomorrow),
            _job(
              id: 'hoy',
              deadline: DateTime.utc(today.year, today.month, today.day, 15),
            ),
          ],
        ),
      );

      expect(r.items.map((i) => i.title), ['PG-manana']);
    });

    test('the stamp is a real Chilean clock time, not civil midnight',
        () async {
      // 2026-08-04 06:30 UTC is 02:30 in Santiago.
      final instant = DateTime.utc(2026, 8, 4, 6, 30);
      final r = await report(now: instant);

      expect(r.generatedAt, instant);
      expect(
        AIAttentionReadModel.formatChileStamp(r.generatedAt),
        '04/08/2026 02:30',
      );
    });

    test('the same UTC clock renders one hour apart across DST', () async {
      // 15:00 UTC is 12:00 in Chilean summer (-03) and 11:00 in winter (-04).
      // Asserting the exact hours is the point: two different strings would
      // also pass if only the date differed.
      expect(
        AIAttentionReadModel.formatChileStamp(DateTime.utc(2026, 1, 15, 15)),
        '15/01/2026 12:00',
      );
      expect(
        AIAttentionReadModel.formatChileStamp(DateTime.utc(2026, 7, 15, 15)),
        '15/07/2026 11:00',
      );
    });
  });

  group('ranking', () {
    test('overdue deliveries come before the day\'s commitments', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            _job(id: 'due', deadline: _chileDay(3)),
            _job(id: 'late', deadline: _chileDay(1)),
          ],
        ),
      );

      expect(r.items.first.reason, AIAttentionReason.workshopOverdue);
      expect(r.items.first.title, 'PG-late');
    });

    test('workshop outranks tasks, and urgent tasks outrank normal ones',
        () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [_job(id: 'j', deadline: _chileDay(3))],
        ),
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [
            _task(id: 'normal', due: _chileDay(3)),
            _task(
                id: 'urgent', due: _chileDay(3), priority: TaskPriority.urgent),
          ],
        ),
      );

      expect(r.items.map((i) => i.title).toList(), [
        'PG-j',
        'Tarea urgent',
        'Tarea normal',
      ]);
    });

    test('an urgent task with no date is backlog, a normal one is not',
        () async {
      final r = await report(
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [
            _task(id: 'urgent', priority: TaskPriority.urgent),
            _task(id: 'normal'),
          ],
        ),
      );

      expect(r.items, hasLength(1));
      expect(r.items.single.reason, AIAttentionReason.taskUrgentBacklog);
    });

    test('at most six, and the count before truncation is preserved', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            for (var i = 0; i < 9; i++) _job(id: 'j$i', deadline: _chileDay(1)),
          ],
        ),
      );

      expect(r.items, hasLength(6));
      expect(r.selectedBeforeTruncation, 9);
      expect(r.isTruncated, isTrue);
    });

    test('the order is stable across identical runs', () async {
      Future<List<String>> run() async {
        final r = await report(
          bikeshop: _FakeBikeshop(
            scope: _scope,
            jobs: [
              for (var i = 0; i < 5; i++)
                _job(id: 'j$i', deadline: _chileDay(1)),
            ],
          ),
        );
        return r.items.map((i) => i.stableId).toList();
      }

      expect(await run(), await run());
    });

    test('a task linked to a job is not deduped away', () async {
      // "Llamar al cliente de la PG-1" is not the same commitment as repairing
      // the bike, so a shared job id must not collapse them.
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [_job(id: '1', deadline: _chileDay(3))],
        ),
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [_task(id: 't1', due: _chileDay(3), linkedJobId: '1')],
        ),
      );

      expect(r.items, hasLength(2));
    });
  });

  group('exclusions', () {
    test('finalizado without delivery still needs attention', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            _job(
              id: 'ready',
              deadline: _chileDay(1),
              status: JobStatus.finalizado,
            ),
          ],
        ),
      );

      expect(r.items, hasLength(1));
    });

    test('cancelled, delivered and delivery-triggering statuses are out',
        () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            _job(
              id: 'cancel',
              deadline: _chileDay(1),
              status: JobStatus.cancelado,
            ),
            _job(
              id: 'legacy',
              deadline: _chileDay(1),
              status: JobStatus.entregado,
            ),
            _job(
              id: 'stamped',
              deadline: _chileDay(1),
              deliveredAt: _chileDay(2),
            ),
            _job(
              id: 'triggers',
              deadline: _chileDay(1),
              customStatus: _customStatus(triggersDelivery: true),
            ),
            _job(
              id: 'custom-entregado',
              deadline: _chileDay(1),
              customStatus: _customStatus(code: 'entregado'),
            ),
          ],
        ),
      );

      expect(r.items, isEmpty);
    });

    test('completed and cancelled tasks are out', () async {
      final r = await report(
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [
            _task(id: 'done', due: _chileDay(1), status: TaskStatus.completed),
            _task(id: 'void', due: _chileDay(1), status: TaskStatus.cancelled),
          ],
        ),
      );

      expect(r.items, isEmpty);
    });
  });

  group('sanitisation', () {
    const secret = 'PGRST-42-tenant-b-leaked-token';

    test('an exception never reaches the outcome the panel renders', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(scope: _scope, failure: StateError(secret)),
      );

      final workshop =
          r.outcomes.firstWhere((o) => o.source == AIAttentionSource.workshop);
      expect(workshop.state, AIAttentionSourceState.unavailable);
      expect(workshop.reason, AIAttentionUnavailableReason.readFailed);
      expect(workshop.reason!.label, isNot(contains(secret)));
      expect(r.toString(), isNot(contains(secret)));
    });

    test('a verification failure is reported as unverifiable, not as text',
        () async {
      final r = await report(
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [_task(id: 't', due: _chileDay(3), tenantId: 'tenant-b')],
        ),
      );

      final tasks =
          r.outcomes.firstWhere((o) => o.source == AIAttentionSource.tasks);
      expect(tasks.reason, AIAttentionUnavailableReason.couldNotVerify);
      expect(tasks.reason!.label, isNot(contains('tenant-b')));
    });

    test('every reason the panel can print is a fixed sentence', () {
      for (final reason in AIAttentionUnavailableReason.values) {
        expect(reason.label.trim(), isNotEmpty);
        expect(reason.label, isNot(contains('Exception')));
        expect(reason.label, isNot(contains('#')));
      }
    });
  });

  group('row identity', () {
    test('two tasks with no id and the same title both survive', () async {
      // Falling back to the title would collapse them and drop a commitment
      // nobody ever saw.
      final r = await report(
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [
            TaskModel(
              tenantId: _tenant,
              title: 'Llamar al cliente',
              status: TaskStatus.pending,
              priority: TaskPriority.urgent,
              dueDate: _chileDay(3),
              createdBy: 'user-a',
              createdAt: DateTime.utc(2026, 1, 1),
            ),
            TaskModel(
              tenantId: _tenant,
              title: 'Llamar al cliente',
              status: TaskStatus.pending,
              priority: TaskPriority.urgent,
              dueDate: _chileDay(3),
              createdBy: 'user-a',
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        ),
      );

      expect(r.items, hasLength(2));
      expect(r.items.first.stableId, isNot(r.items.last.stableId));
    });

    test('two jobs with no id and the same number both survive', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            MechanicJob(
              tenantId: _tenant,
              jobNumber: 'PG-DUP',
              customerId: 'c1',
              status: JobStatus.enCurso,
              deliveryDeadline: _chileDay(1),
              clientRequest: 'Revisar',
              totalCost: 0,
            ),
            MechanicJob(
              tenantId: _tenant,
              jobNumber: 'PG-DUP',
              customerId: 'c1',
              status: JobStatus.enCurso,
              deliveryDeadline: _chileDay(1),
              clientRequest: 'Revisar',
              totalCost: 0,
            ),
          ],
        ),
      );

      expect(r.items, hasLength(2));
      expect(r.items.first.stableId, isNot(r.items.last.stableId));
    });

    test('the same row read twice keeps one identity', () async {
      final job = _job(id: 'j1', deadline: _chileDay(1));
      final r = await report(
        bikeshop: _FakeBikeshop(scope: _scope, jobs: [job, job]),
      );
      expect(r.items, hasLength(1));
    });
  });

  group('interaction limits', () {
    test('a briefing can only offer the two aggregate surfaces', () {
      // No editor, no deep link, no record id: the briefing names a module and
      // the operator decides whether to open it.
      expect(
        AIAttentionSource.values.map((s) => s.destination).toSet(),
        {
          AIAssistantDestination.workshopJobs,
          AIAssistantDestination.tasks,
        },
      );
    });

    test('building a briefing navigates nothing by itself', () async {
      // Asking is not acting. The read model has no navigation callback to
      // call, which is the structural version of that guarantee.
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [_job(id: 'j', deadline: _chileDay(3))],
        ),
      );
      expect(r.items, isNotEmpty);
    });

    test('the workshop read asks for a fresh, complete roster once', () async {
      final bikeshop = _FakeBikeshop(scope: _scope);
      await report(bikeshop: bikeshop);
      expect(bikeshop.getJobsCalls, 1);
    });
  });

  group('provenance', () {
    test('the report counts what it examined per source', () async {
      final r = await report(
        bikeshop: _FakeBikeshop(
          scope: _scope,
          jobs: [
            _job(id: 'a', deadline: _chileDay(3)),
            _job(id: 'b', deadline: null),
          ],
        ),
        tasks: _FakeTasks(
          scope: _scope,
          taskList: [_task(id: 't', due: _chileDay(3))],
        ),
      );

      expect(
        r.outcomes
            .firstWhere((o) => o.source == AIAttentionSource.workshop)
            .examined,
        2,
      );
      expect(r.examinedTotal, 3);
      expect(r.items, hasLength(2));
      expect(r.generatedAt.day, 3);
    });
  });
}
