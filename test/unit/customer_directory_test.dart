import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/modules/crm/services/customer_directory.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';

const _tenant = 'tenant-1';

Customer _customer(String id, String name, {String? phone}) => Customer(
      id: id,
      tenantId: _tenant,
      name: name,
      rut: '',
      phone: phone,
      createdAt: DateTime(2025, 11, 13),
    );

Bike _bike(String id, String customerId, {String model = 'Marlin 5'}) => Bike(
      id: id,
      tenantId: _tenant,
      customerId: customerId,
      brand: 'Trek',
      model: model,
      createdAt: DateTime(2026, 1, 1),
    );

MechanicJob _job(
  String id,
  String customerId, {
  String? bikeId,
  required DateTime arrival,
  JobStatus status = JobStatus.pendiente,
  DateTime? delivered,
}) =>
    MechanicJob(
      id: id,
      tenantId: _tenant,
      jobNumber: 'PG-$id',
      customerId: customerId,
      bikeId: bikeId,
      intakeKind: JobIntakeKind.bike,
      status: status,
      arrivalDate: arrival,
      deliveredAt: delivered,
    );

Invoice _invoice(
  String number,
  String? customerId, {
  required InvoiceStatus status,
  double total = 10000,
  double paid = 0,
  DateTime? date,
}) =>
    Invoice(
      id: 'inv-$number',
      tenantId: _tenant,
      customerId: customerId,
      invoiceNumber: number,
      date: date ?? DateTime(2026, 8, 12),
      status: status,
      total: total,
      paidAmount: paid,
      balance: total - paid,
    );

List<CustomerDirectoryEntry> _directory() => buildCustomerDirectory(
      customers: [
        _customer('ivan', 'Ivan Ostoic'),
        _customer('raul', 'Raul Hein', phone: '+56 9 8121 0019'),
        _customer('zoho', 'Abel Importado'),
        _customer('test', 'Test Taller'),
      ],
      bikes: [
        _bike('b-ivan', 'ivan', model: 'Tyax'),
        _bike('b-raul', 'raul'),
        _bike('b-test', 'test'),
      ],
      jobs: [
        _job('505', 'ivan', bikeId: 'b-ivan', arrival: DateTime(2026, 8, 12)),
        _job('461', 'ivan',
            bikeId: 'b-ivan',
            arrival: DateTime(2026, 7, 10),
            status: JobStatus.entregado,
            delivered: DateTime(2026, 7, 13)),
        _job('599', 'raul',
            bikeId: 'b-raul',
            arrival: DateTime(2026, 10, 2),
            status: JobStatus.entregado,
            delivered: DateTime(2026, 10, 2)),
        // Un trabajo de prueba no pone a nadie en el taller.
        _job('900', 'test', bikeId: 'b-test', arrival: DateTime(2026, 10, 1)),
      ],
      jobBikesByJobId: const {},
      invoices: [
        _invoice('FV-00948', 'ivan',
            status: InvoiceStatus.confirmed, total: 90000, paid: 45000),
        _invoice('FV-00847', 'ivan',
            status: InvoiceStatus.paid, total: 62000, paid: 62000),
        _invoice('FV-00999', 'raul',
            status: InvoiceStatus.cancelled, total: 30000),
        _invoice('FV-01000', 'raul',
            status: InvoiceStatus.draft,
            total: 8000,
            date: DateTime(2026, 10, 3)),
        _invoice('FV-00575', null, status: InvoiceStatus.sent, total: 5000),
      ],
    );

CustomerDirectoryEntry _row(String id) =>
    _directory().firstWhere((row) => row.customer.id == id);

void main() {
  test('only issued invoices with a balance are owed', () {
    expect(
      invoiceIsOwed(_invoice('A', 'x', status: InvoiceStatus.sent)),
      isTrue,
    );
    expect(
      invoiceIsOwed(_invoice('B', 'x', status: InvoiceStatus.draft)),
      isFalse,
    );
    // PG-00006: marcada pagada con saldo; se revisa, no se cobra aquí.
    expect(
      invoiceIsOwed(_invoice('C', 'x', status: InvoiceStatus.paid)),
      isFalse,
    );
    expect(
      invoiceIsOwed(_invoice('D', 'x', status: InvoiceStatus.cancelled)),
      isFalse,
    );
  });

  test('a customer row knows its bike, open job, debt and payments', () {
    final ivan = _row('ivan');
    expect(ivan.hasActivity, isTrue);
    expect(ivan.mainBike?.model, 'Tyax');
    expect(ivan.workshopJob?.jobNumber, 'PG-505');
    expect(ivan.paid, 107000);
    expect(ivan.owed, 45000);
    expect(ivan.owedInvoices.single.invoiceNumber, 'FV-00948');
    expect(ivan.lastVisitAt, DateTime(2026, 8, 12));

    final raul = _row('raul');
    expect(raul.inWorkshop, isFalse);
    // Lo anulado no es pago y un borrador no es una visita.
    expect(raul.paid, 0);
    expect(raul.lastVisitAt, DateTime(2026, 10, 2));
  });

  test('test jobs do not put a customer in the workshop', () {
    final test = _row('test');
    expect(test.inWorkshop, isFalse);
    expect(test.hasActivity, isTrue);
  });

  test('a job is a test job only if every bike in it is', () {
    MechanicJobBike row(String id, String jobId, String bikeId) =>
        MechanicJobBike(
            id: id, tenantId: _tenant, jobId: jobId, bikeId: bikeId);
    List<CustomerDirectoryEntry> build(List<Bike> bikes) =>
        buildCustomerDirectory(
          customers: [_customer('ana', 'Ana Real')],
          bikes: bikes,
          jobs: [_job('700', 'ana', arrival: DateTime(2026, 10, 1))],
          jobBikesByJobId: {
            '700': [
              for (final bike in bikes) row('r-${bike.id}', '700', bike.id!),
            ],
          },
          invoices: const [],
        );

    final testBike = Bike(
      id: 'b-test',
      tenantId: _tenant,
      customerId: 'ana',
      brand: 'Test',
      model: 'Bici de prueba',
      createdAt: DateTime(2026, 1, 1),
    );
    expect(build([testBike]).single.inWorkshop, isFalse);
    expect(
      build([_bike('b-real', 'ana'), testBike]).single.inWorkshop,
      isTrue,
    );
  });

  test('each view filters and orders its rows', () {
    final rows = _directory();
    List<String?> ids(CustomerListView view) => [
          for (final row in customerDirectoryView(rows, view)) row.customer.id,
        ];
    // Los que vinieron hace menos primero; los sin visitas al final.
    expect(ids(CustomerListView.active), ['raul', 'ivan', 'test']);
    expect(ids(CustomerListView.workshop), ['ivan']);
    expect(ids(CustomerListView.owed), ['ivan']);
    expect(ids(CustomerListView.all), ['zoho', 'ivan', 'raul', 'test']);
  });

  test('the search finds a customer by phone digits or bike', () {
    final raul = _row('raul');
    expect(customerDirectorySearchScore(raul, '981210019'), greaterThan(0));
    expect(customerDirectorySearchScore(raul, 'marlin hein'), greaterThan(0));
    expect(customerDirectorySearchScore(raul, 'tyax'), 0);
  });
}
