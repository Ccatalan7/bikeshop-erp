import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_visit_history.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_line_systems.dart';
import 'package:vinabike_erp/shared/models/tax_treatment.dart';

const _tenant = 'tenant-1';
const _customer = 'customer-1';

MechanicJob _job(
  String id, {
  String? bikeId,
  DateTime? arrival,
  double total = 0,
  double parts = 0,
  double labor = 0,
  TaxTreatment tax = TaxTreatment.taxIncluded,
  JobWorkflowKind workflow = JobWorkflowKind.service,
  JobIntakeKind intake = JobIntakeKind.bike,
  String? request,
  String? subjectNotes,
  DateTime? deletedAt,
}) =>
    MechanicJob(
      id: id,
      tenantId: _tenant,
      jobNumber: 'PG-$id',
      customerId: _customer,
      bikeId: bikeId,
      workflowKind: workflow,
      intakeKind: intake,
      arrivalDate: arrival ?? DateTime(2026, 8, 12),
      totalCost: total,
      partsCost: parts,
      laborCost: labor,
      taxTreatment: tax,
      clientRequest: request,
      subjectNotes: subjectNotes,
      deletedAt: deletedAt,
    );

MechanicJobBike _row(String id, String jobId, String bikeId,
        {int order = 0, String? request}) =>
    MechanicJobBike(
      id: id,
      tenantId: _tenant,
      jobId: jobId,
      bikeId: bikeId,
      orderIndex: order,
      workRequested: request,
    );

MechanicJobItem _item(String jobId, String name, double price,
        {String? jobBikeId, String? systemKey}) =>
    MechanicJobItem(
      tenantId: _tenant,
      jobId: jobId,
      jobBikeId: jobBikeId,
      productName: name,
      unitPrice: price,
      totalPrice: price,
      systemKey: systemKey,
    );

List<BikeVisit> _visits(
  List<MechanicJob> jobs, {
  Map<String, List<MechanicJobBike>> rows = const {},
  Map<String, List<MechanicJobItem>> items = const {},
}) =>
    buildCustomerVisits(
      jobs: jobs,
      jobBikesByJobId: rows,
      itemsByJobId: items,
      systemOf: (item) =>
          jobLineSystemFromKey(item.systemKey) ?? JobLineSystem.general,
    );

void main() {
  test('a client visit is the whole job: every bike and what was bought apart',
      () {
    final visits = _visits(
      [_job('1', bikeId: 'bike-a', total: 120000)],
      rows: {
        '1': [
          _row('row-b', '1', 'bike-b', order: 1, request: 'Revisar frenos'),
          _row('row-a', '1', 'bike-a', request: 'Cambio de cadena'),
        ],
      },
      items: {
        '1': [
          _item('1', 'Cadena KMC', 15000,
              jobBikeId: 'row-a', systemKey: 'drivetrain'),
          _item('1', 'Pastillas', 20000,
              jobBikeId: 'row-b', systemKey: 'brakes'),
          _item('1', 'Luz trasera', 9000, systemKey: 'brakes'),
        ],
      },
    );

    final visit = visits.single;
    expect(visit.bikeIds, ['bike-a', 'bike-b']);
    expect(visit.amount, 120000);
    expect(visit.separatePurchaseAmount, 0);
    // Sin fila de bici en un trabajo que sí las tiene: compra aparte.
    final general = visit.groups
        .firstWhere((group) => group.system == JobLineSystem.general);
    expect(general.lines.map((line) => line.name), ['Luz trasera']);
    expect(visit.request, 'Cambio de cadena\nRevisar frenos');
  });

  test('a job without bike rows keeps its own line systems', () {
    final visit = _visits(
      [_job('2', bikeId: 'bike-a', total: 30000, request: 'Mantención')],
      items: {
        '2': [_item('2', 'Pastillas', 30000, systemKey: 'brakes')],
      },
    ).single;
    expect(visit.bikeIds, ['bike-a']);
    expect(visit.groups.single.system, JobLineSystem.brakes);
    expect(visit.request, 'Mantención');
  });

  test('a proposal shows its discounted total, not the no-tax subtotal', () {
    final visit = _visits([
      _job('3',
          workflow: JobWorkflowKind.quotation,
          intake: JobIntakeKind.none,
          total: 45000,
          parts: 50000,
          tax: TaxTreatment.noTax,
          subjectNotes: 'Horquilla 29 con bloqueo'),
    ]).single;
    expect(visit.amount, 45000);
    expect(visit.job.isStandaloneQuotation, isTrue);
    // Lo pedido de una cotización sin objeto es lo que se cotizó.
    expect(visit.request, 'Horquilla 29 con bloqueo');
    expect(visit.inWorkshop, isFalse);
  });

  test('a proposal discounted to zero shows zero, not its lines', () {
    final visit = _visits(
      [
        _job('8',
            bikeId: 'bike-a',
            workflow: JobWorkflowKind.quotation,
            total: 0,
            parts: 50000),
      ],
      items: {
        '8': [_item('8', 'Horquilla', 50000, systemKey: 'suspension')],
      },
    ).single;
    expect(visit.amount, 0);
  });

  test('a no-tax job shows its net amount', () {
    expect(
      jobDisplayTotal(_job('4',
          total: 119000, parts: 60000, labor: 40000, tax: TaxTreatment.noTax)),
      100000,
    );
  });

  test('deleted jobs are not activity, and the newest comes first', () {
    final visits = _visits([
      _job('5', arrival: DateTime(2026, 2, 27)),
      _job('6', arrival: DateTime(2026, 8, 12)),
      _job('7', deletedAt: DateTime(2026, 9, 1)),
    ]);
    expect(visits.map((visit) => visit.job.id), ['6', '5']);
  });
}
