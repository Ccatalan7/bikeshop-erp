import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/pegas_calendar_widget.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  Future<void> pumpCalendar(
    WidgetTester tester,
    Size size, {
    List<MechanicJob> jobs = const <MechanicJob>[],
    TextScaler textScaler = TextScaler.noScaling,
    bool? useCompactLayout,
    PegasCalendarSession? session,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _CalendarBikeshopService(jobs);
    addTearDown(service.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<BikeshopService>.value(
        value: service,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: Scaffold(
            body: PegasCalendarWidget(
              jobs: jobs,
              customers: const <String, Customer>{},
              bikes: const <String, Bike>{},
              useCompactLayout: useCompactLayout,
              session: session,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in <double>[384, 599, 600, 899]) {
    testWidgets(
      'calendar stacks month and agenda without overflow at ${width.toInt()}px',
      (tester) async {
        await pumpCalendar(tester, Size(width, 824));

        final monthFinder =
            find.byKey(const ValueKey('workshop-calendar-compact-month'));
        final agendaFinder =
            find.byKey(const ValueKey('workshop-calendar-compact-agenda'));

        expect(
          find.byKey(const ValueKey('workshop-calendar-compact-stack')),
          findsOneWidget,
        );
        expect(monthFinder, findsOneWidget);
        expect(agendaFinder, findsOneWidget);

        final monthRect = tester.getRect(monthFinder);
        final agendaRect = tester.getRect(agendaFinder);
        expect(monthRect.bottom, lessThan(agendaRect.top));
        expect(monthRect.left, agendaRect.left);
        expect(monthRect.right, agendaRect.right);
        expect(monthRect.left, greaterThanOrEqualTo(0));
        expect(monthRect.right, lessThanOrEqualTo(width));

        if (width == 384) {
          final today = DateTime.now();
          final dayFinder = find.byKey(
            ValueKey(
              'workshop-calendar-day-'
              '${today.year.toString().padLeft(4, '0')}-'
              '${today.month.toString().padLeft(2, '0')}-'
              '${today.day.toString().padLeft(2, '0')}',
            ),
          );
          expect(dayFinder, findsOneWidget);
          final daySize = tester.getSize(dayFinder);
          expect(daySize.width, greaterThanOrEqualTo(48));
          expect(daySize.height, greaterThanOrEqualTo(48));
        }

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('calendar keeps the desktop split from 900px', (tester) async {
    await pumpCalendar(tester, const Size(900, 900));

    final splitFinder =
        find.byKey(const ValueKey('workshop-calendar-desktop-split'));
    expect(splitFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey('workshop-calendar-compact-stack')),
      findsNothing,
    );

    final cards = find.descendant(
      of: splitFinder,
      matching: find.byType(Card),
    );
    expect(cards, findsNWidgets(2));

    final monthRect = tester.getRect(cards.at(0));
    final agendaRect = tester.getRect(cards.at(1));
    expect(monthRect.top, agendaRect.top);
    expect(monthRect.right, lessThan(agendaRect.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inherits the root layout class and restores the browsed month after remount',
    (tester) async {
      final session = PegasCalendarSession();
      await pumpCalendar(
        tester,
        const Size(900, 900),
        useCompactLayout: true,
        session: session,
      );

      expect(
        find.byKey(const ValueKey('workshop-calendar-compact-stack')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pump();
      final focusedMonth = session.focusedMonth;

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpCalendar(
        tester,
        const Size(384, 824),
        useCompactLayout: true,
        session: session,
      );

      expect(session.focusedMonth, focusedMonth);
      expect(
        find.byKey(
          ValueKey(
            'workshop-calendar-day-'
            '${focusedMonth.year.toString().padLeft(4, '0')}-'
            '${focusedMonth.month.toString().padLeft(2, '0')}-01',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact job uses the full workspace and back restores its selected day',
    (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(tester.view.resetViewInsets);

      final today = DateTime.now();
      final selectedDay = DateTime(today.year, today.month, today.day, 12);
      final job = MechanicJob(
        id: 'calendar-job-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        jobNumber: 'PG-CAL-1',
        diagnosticDeadline: selectedDay,
        arrivalDate: selectedDay,
        clientRequest: 'Revisión general y ajuste de transmisión',
      );

      await pumpCalendar(
        tester,
        const Size(384, 824),
        jobs: <MechanicJob>[job],
        textScaler: const TextScaler.linear(1.3),
      );

      expect(
        find.byKey(const ValueKey('workshop-calendar-compact-stack')),
        findsOneWidget,
      );
      await tester.tap(find.text('PG-CAL-1'));
      await tester.pump();
      await tester.pump();

      final workspace = find.byKey(
        const ValueKey('workshop-calendar-compact-detail-workspace'),
      );
      final back = find.byKey(
        const ValueKey('workshop-calendar-compact-back'),
      );
      expect(workspace, findsOneWidget);
      expect(
        find.byKey(const ValueKey('workshop-calendar-compact-stack')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workshop-calendar-compact-month')),
        findsNothing,
      );
      expect(back, findsOneWidget);
      expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey('workshop-calendar-compact-status'),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        find.byKey(const ValueKey('workshop-calendar-compact-editor')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey('workshop-calendar-compact-editor-save'),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.getRect(workspace).width, greaterThan(350));
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(workspace).bottom,
        lessThanOrEqualTo(
          824 - (300 / tester.view.devicePixelRatio),
        ),
      );

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      await tester.tap(back);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('workshop-calendar-compact-stack')),
        findsOneWidget,
      );
      expect(find.text('PG-CAL-1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('PG-CAL-1'));
      await tester.pump();
      await tester.pump();
      final save = find.byKey(
        const ValueKey('workshop-calendar-compact-editor-save'),
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('workshop-calendar-compact-stack')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}

class _CalendarBikeshopService extends ChangeNotifier
    implements BikeshopService {
  _CalendarBikeshopService(List<MechanicJob> jobs)
      : _jobsById = <String, MechanicJob>{
          for (final job in jobs)
            if (job.id != null) job.id!: job,
        };

  final Map<String, MechanicJob> _jobsById;

  @override
  Future<List<MechanicJobItem>> getJobItems(String jobId) async =>
      const <MechanicJobItem>[];

  @override
  Future<MechanicJob?> getJobById(String id) async => _jobsById[id];

  @override
  Future<MechanicJob> updateJob(
    MechanicJob job, {
    bool syncBikeMemory = true,
    bool protectCommercialSnapshot = false,
  }) async {
    if (job.id != null) _jobsById[job.id!] = job;
    return job;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
