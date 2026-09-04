import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/hr/models/hr_models.dart';
import 'package:vinabike_erp/modules/hr/services/hr_service.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/widgets/notifications_panel.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('closed shifts remain visible when nobody is in the store', (
    tester,
  ) async {
    final service = _FakeHRService([
      _closedEntry(
        attendanceId: 'attendance-vicente',
        employeeId: 'employee-vicente',
        firstName: 'Vicente',
        checkIn: DateTime.utc(2026, 8, 2, 14),
        checkOut: DateTime.utc(2026, 8, 2, 23, 30),
      ),
      _closedEntry(
        attendanceId: 'attendance-lucas',
        employeeId: 'employee-lucas',
        firstName: 'Lucas',
        checkIn: DateTime.utc(2026, 8, 2, 14),
        checkOut: DateTime.utc(2026, 8, 2, 20),
      ),
    ]);
    addTearDown(service.dispose);

    await _pumpPanel(tester, service);

    expect(find.text('0 personas'), findsOneWidget);
    expect(find.text('Nadie está en el local ahora.'), findsOneWidget);
    expect(find.text('Turnos finalizados hoy'), findsOneWidget);
    expect(find.text('Vicente'), findsOneWidget);
    expect(find.text('Lucas'), findsOneWidget);
    expect(find.text('10:00–19:30 · 9 h 30 min'), findsOneWidget);
    expect(find.text('10:00–16:00 · 6 h'), findsOneWidget);
    expect(find.text('Turno finalizado'), findsNWidgets(2));
  });

  testWidgets('live and completed attendance rows coexist', (tester) async {
    final service = _FakeHRService([
      _currentEntry(),
      _closedEntry(
        attendanceId: 'attendance-vicente',
        employeeId: 'employee-vicente',
        firstName: 'Vicente',
        checkIn: DateTime.utc(2026, 8, 2, 14),
        checkOut: DateTime.utc(2026, 8, 2, 23, 30),
      ),
    ]);
    addTearDown(service.dispose);

    await _pumpPanel(tester, service);

    expect(find.text('1 persona'), findsOneWidget);
    expect(find.text('Lucas'), findsOneWidget);
    expect(find.text('Jornada en curso'), findsWidgets);
    expect(find.text('Turnos finalizados hoy'), findsOneWidget);
    expect(find.text('Vicente'), findsOneWidget);
    expect(find.text('Turno finalizado'), findsOneWidget);
  });

  testWidgets(
      'a period that ended before today lists its closed shifts, '
      'not who is in the store now', (tester) async {
    final service = _FakeHRService([
      _currentEntry(),
      _closedEntry(
        attendanceId: 'attendance-vicente',
        employeeId: 'employee-vicente',
        firstName: 'Vicente',
        checkIn: DateTime.utc(2026, 8, 2, 14),
        checkOut: DateTime.utc(2026, 8, 2, 23, 30),
      ),
      _closedEntry(
        attendanceId: 'attendance-ana',
        employeeId: 'employee-ana',
        firstName: 'Ana',
        checkIn: DateTime.utc(2026, 8, 2, 14),
        checkOut: DateTime.utc(2026, 8, 2, 20),
      ),
    ]);
    addTearDown(service.dispose);

    await _pumpPanel(tester, service);
    expect(find.text('Ahora en el local'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey<String>('notification-period-trigger')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ayer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The service was asked for yesterday's business day, not today's.
    final requested = service.lastWindow!;
    final today = DateTime.now();
    expect(
        requested.end.difference(requested.start), const Duration(hours: 24));
    expect(requested.end.isBefore(today), isTrue);

    expect(find.text('Asistencia de ayer'), findsOneWidget);
    expect(find.text('Ahora en el local'), findsNothing);
    expect(find.text('2 turnos'), findsOneWidget);
    expect(find.text('Jornada en curso'), findsNothing,
        reason: "Lucas is in the store today; that is not yesterday's fact.");
    expect(find.text('Lucas'), findsNothing);
    expect(find.text('Vicente'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Turno finalizado'), findsNWidgets(2));
    expect(find.text('Turnos finalizados hoy'), findsNothing);
  });

  testWidgets('a truly empty day keeps the daily empty state', (tester) async {
    final service = _FakeHRService(const []);
    addTearDown(service.dispose);

    await _pumpPanel(tester, service);

    expect(find.text('Nadie ha marcado entrada hoy.'), findsOneWidget);
    expect(find.text('Turnos finalizados hoy'), findsNothing);
  });
}

Future<void> _pumpPanel(WidgetTester tester, HRService service) async {
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
        ChangeNotifierProvider<HRService>.value(value: service),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 900,
            child: NotificationsToolbarPanel(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

DailyAttendanceBriefingEntry _currentEntry() {
  final employee = _employee('employee-lucas', 'Lucas');
  return DailyAttendanceBriefingEntry(
    attendance: Attendance(
      id: 'attendance-lucas-current',
      tenantId: 'tenant-test',
      employeeId: employee.id!,
      checkIn: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    employee: employee,
  );
}

DailyAttendanceBriefingEntry _closedEntry({
  required String attendanceId,
  required String employeeId,
  required String firstName,
  required DateTime checkIn,
  required DateTime checkOut,
}) {
  final employee = _employee(employeeId, firstName);
  return DailyAttendanceBriefingEntry(
    attendance: Attendance(
      id: attendanceId,
      tenantId: 'tenant-test',
      employeeId: employeeId,
      checkIn: checkIn,
      checkOut: checkOut,
      status: AttendanceStatus.completed,
    ),
    employee: employee,
  );
}

Employee _employee(String id, String firstName) {
  return Employee(
    id: id,
    tenantId: 'tenant-test',
    employeeNumber: id,
    firstName: firstName,
    lastName: '',
    jobTitle: 'Taller',
  );
}

class _FakeHRService extends HRService {
  _FakeHRService(this.entries)
      : super(
          TenantService.testing(
            currentUserId: () => 'user-test',
            profileLookup: (_) async => const [
              {'tenant_id': 'tenant-test'},
            ],
          ),
        );

  final List<DailyAttendanceBriefingEntry> entries;
  ({DateTime start, DateTime end})? lastWindow;

  @override
  Future<List<DailyAttendanceBriefingEntry>> getDailyAttendanceBriefing({
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    lastWindow = (start: startsAt, end: endsAt);
    return entries;
  }
}
