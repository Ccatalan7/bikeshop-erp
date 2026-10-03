import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_visit_history.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/job_visit_card.dart';
import 'package:vinabike_erp/modules/crm/services/client_data_draft.dart';
import 'package:vinabike_erp/modules/crm/widgets/client_data_sheet.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

ClientRecord _ivan() => ClientRecord.fromRow(const {
      'id': 'customer-1',
      'tenant_id': 'tenant-1',
      'name': 'Ivan Ostoic',
      'notes': 'Zoho ID: 5555000001234567',
      'is_active': true,
      'created_at': '2025-11-13T15:20:31+00:00',
      'updated_at': '2026-10-03T12:00:00.123456+00:00',
    });

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// La página en miniatura: tiene el borrador y los campos, como la real.
class _SheetHost extends StatefulWidget {
  const _SheetHost({super.key, required this.record});

  final ClientRecord record;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  ClientDataDraft? draft;
  final controllers = <ClientDataField, TextEditingController>{};
  final focus = {
    for (final field in ClientDataField.values) field: FocusNode(),
  };

  void startEdit(ClientDataField? _) {
    final next = ClientDataDraft(widget.record);
    for (final field in ClientDataField.values) {
      controllers[field] = TextEditingController(text: next.value(field) ?? '');
    }
    setState(() => draft = next);
  }

  @override
  Widget build(BuildContext context) => ClientDataSheet(
        record: widget.record,
        draft: draft,
        controllers: controllers,
        focusNodes: focus,
        problems: draft?.problems ?? const {},
        busy: false,
        onAdd: startEdit,
        onChanged: (field, value) => setState(() => draft!.set(field, value)),
        onRegionChanged: (value) =>
            setState(() => draft!.set(ClientDataField.region, value)),
        onUndo: (field) => setState(() {
          draft!.revert(field);
          controllers[field]!.text = draft!.value(field) ?? '';
        }),
      );
}

void main() {
  testWidgets('the data sheet shows every field and edits in place',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final host = GlobalKey<_SheetHostState>();
    await tester.pumpWidget(_app(_SheetHost(key: host, record: _ivan())));

    expect(find.text('Datos del cliente'), findsOneWidget);
    expect(find.text('1 de 8 datos · faltan el contacto y los de facturación'),
        findsOneWidget);
    // Los vacíos se ofrecen para completar, sin esconderlos tras «Editar».
    expect(find.text('Agregar teléfono'), findsOneWidget);
    expect(find.text('Agregar RUT'), findsOneWidget);
    expect(find.text('Agregar nota'), findsOneWidget);
    // La línea de Zoho es el origen, no una nota.
    expect(find.text('Importado de Zoho'), findsOneWidget);
    expect(find.textContaining('Zoho ID'), findsNothing);
    expect(
      find.text('Sin teléfono no se le puede avisar por WhatsApp que su bici '
          'está lista.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Agregar teléfono'));
    await tester.pumpAndSettle();
    expect(find.text('Editando los datos'), findsOneWidget);
    expect(host.currentState!.draft, isNotNull);

    final phone = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.controller ==
            host.currentState!.controllers[ClientDataField.phone]);
    await tester.enterText(phone, '981210019');
    await tester.pump();
    expect(find.text('Nuevo'), findsOneWidget);
    expect(host.currentState!.draft!.changes, {'phone': '+56 9 8121 0019'});

    await tester.tap(find.byTooltip('Deshacer cambio de Teléfono'));
    await tester.pump();
    expect(find.text('Nuevo'), findsNothing);
    expect(host.currentState!.draft!.changeCount, 0);
  });

  testWidgets('the data sheet becomes one card per section on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(_SheetHost(record: _ivan()), brightness: Brightness.dark),
    );
    expect(find.text('Datos del cliente'), findsNothing);
    expect(find.text('Contacto'), findsOneWidget);
    expect(find.text('Lo pone el sistema'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('a visit card keeps a proposal apart from a bill', () {
    BikeVisit visit(MechanicJob job) => BikeVisit(
          job: job,
          groups: const [],
          amount: 45000,
          separatePurchaseAmount: 0,
          request: job.subjectNotes,
          inWorkshop: false,
        );

    Future<void> pump(WidgetTester tester, BikeVisit visit,
        {List<JobVisitSubject> subjects = const []}) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(JobVisitCard(
        visit: visit,
        today: DateTime(2026, 10, 3),
        narrow: false,
        subjects: subjects,
        footer: const Text('Esta cotización aún no ha generado una factura.'),
      )));
    }

    testWidgets('a quotation with nothing received', (tester) async {
      await pump(
        tester,
        visit(MechanicJob(
          id: 'q1',
          tenantId: 'tenant-1',
          jobNumber: 'PG-00600',
          customerId: 'customer-1',
          workflowKind: JobWorkflowKind.quotation,
          intakeKind: JobIntakeKind.none,
          arrivalDate: DateTime(2026, 9, 30),
          totalCost: 45000,
          subjectNotes: 'Horquilla 29 con bloqueo',
        )),
        subjects: const [JobVisitSubject(label: 'Sin objeto recibido')],
      );
      expect(find.text('Cotización Pendiente'), findsOneWidget);
      expect(find.text('Sin objeto recibido'), findsOneWidget);
      expect(find.text('Cotización del 30 sep'), findsOneWidget);
      expect(find.text('Total cotizado'), findsOneWidget);
      expect(
        find.text('Esta cotización aún no ha generado una factura.'),
        findsOneWidget,
      );
    });

    testWidgets('a budget for a bike keeps both statuses', (tester) async {
      await pump(
        tester,
        visit(MechanicJob(
          id: 'b1',
          tenantId: 'tenant-1',
          jobNumber: 'PG-00601',
          customerId: 'customer-1',
          bikeId: 'bike-1',
          workflowKind: JobWorkflowKind.quotation,
          intakeKind: JobIntakeKind.bike,
          arrivalDate: DateTime(2026, 9, 30),
          totalCost: 45000,
        )),
      );
      expect(find.text('Presupuesto Pendiente'), findsOneWidget);
      expect(find.text('Total presupuestado'), findsOneWidget);
    });
  });
}
