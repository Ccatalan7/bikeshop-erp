import 'package:flutter/foundation.dart';

import '../../../shared/utils/bike_finder_search.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bike_directory_entries.dart';
import '../../bikeshop/services/mechanic_job_visibility_policy.dart';
import '../../sales/models/sales_models.dart';
import '../models/crm_models.dart';

/// Lo que muestra la lista de clientes. «Con actividad» va primero: 1265 de
/// los 1757 clientes son importados de Zoho sin bicis, trabajos ni facturas
/// (2026-10-02), y en «Todos» tapaban a los que sí vienen.
enum CustomerListView { active, workshop, owed, all }

/// Una factura que todavía se debe: emitida, no anulada y con saldo.
///
/// Sólo cuenta lo emitido (`sent`, `confirmed`, `overdue`): un borrador no
/// se cobra, y una factura vieja marcada pagada con saldo (PG-00006,
/// 2026-10-03) es un dato a revisar, no una deuda.
bool invoiceIsOwed(Invoice invoice) =>
    (invoice.status == InvoiceStatus.sent ||
        invoice.status == InvoiceStatus.confirmed ||
        invoice.status == InvoiceStatus.overdue) &&
    invoice.balance > 0.5;

/// Un cliente en la lista, con lo que se sabe de él sin abrirlo.
@immutable
class CustomerDirectoryEntry {
  const CustomerDirectoryEntry({
    required this.customer,
    required this.bikes,
    required this.mainBike,
    required this.workshopJob,
    required this.lastVisitAt,
    required this.paid,
    required this.owedInvoices,
    required this.hasActivity,
  });

  final Customer customer;

  /// Sus bicis, las activas primero.
  final List<Bike> bikes;

  /// La bici que se muestra: la del último trabajo, o la más nueva.
  final Bike? mainBike;

  /// El trabajo por el que tiene algo en el taller hoy (el más reciente).
  final MechanicJob? workshopJob;

  /// La última vez que vino: un trabajo (llegada, término o entrega) o una
  /// factura emitida.
  final DateTime? lastVisitAt;

  /// Lo pagado en facturas no anuladas.
  final double paid;

  /// Lo que debe, la factura más antigua primero.
  final List<Invoice> owedInvoices;

  /// Tiene alguna bici, trabajo o factura.
  final bool hasActivity;

  bool get inWorkshop => workshopJob != null;

  double get owed =>
      owedInvoices.fold(0.0, (sum, invoice) => sum + invoice.balance);

  DateTime? get owedSince =>
      owedInvoices.isEmpty ? null : owedInvoices.first.date;
}

DateTime _latest(Iterable<DateTime?> dates) =>
    dates.whereType<DateTime>().reduce((a, b) => a.isAfter(b) ? a : b);

/// Arma una fila por cliente. Los trabajos de prueba no cuentan como visita
/// ni ponen a nadie «en el taller», con la misma identidad con que los
/// descarta el directorio de bicicletas.
List<CustomerDirectoryEntry> buildCustomerDirectory({
  required List<Customer> customers,
  required List<Bike> bikes,
  required List<MechanicJob> jobs,
  required Map<String, List<MechanicJobBike>> jobBikesByJobId,
  required List<Invoice> invoices,
}) {
  final bikesById = {
    for (final bike in bikes)
      if (bike.id != null && bike.id!.isNotEmpty) bike.id!: bike,
  };
  final bikesByCustomer = <String, List<Bike>>{};
  for (final bike in bikes) {
    if (bike.customerId.isEmpty) continue;
    bikesByCustomer.putIfAbsent(bike.customerId, () => []).add(bike);
  }
  final customerNames = {
    for (final customer in customers)
      if (customer.id != null) customer.id!: customer.name,
  };

  final jobsByCustomer = <String, List<MechanicJob>>{};
  final anyJob = <String>{};
  for (final job in jobs) {
    if (job.deletedAt != null || job.customerId.isEmpty) continue;
    anyJob.add(job.customerId);
    // Un trabajo es de prueba si lo es su cliente o todas sus bicis: una
    // bici real en el mismo trabajo es trabajo real, como en el directorio
    // de bicicletas, que lo cuenta para esa bici.
    final jobBikes = [
      for (final bikeId in bikeIdsOfJob(job, jobBikesByJobId))
        if (bikesById[bikeId] case final bike?) bike,
    ];
    bool fixtureWith(Bike? bike) => mechanicJobMatchesTestFixture(
          job,
          customerName: customerNames[job.customerId],
          bikeName: bike?.displayName,
          bikeBrand: bike?.brand,
          bikeModel: bike?.model,
          bikeSerialNumber: bike?.serialNumber,
        );
    final fixture =
        jobBikes.isEmpty ? fixtureWith(null) : jobBikes.every(fixtureWith);
    if (fixture) continue;
    jobsByCustomer.putIfAbsent(job.customerId, () => []).add(job);
  }

  final invoicesByCustomer = <String, List<Invoice>>{};
  for (final invoice in invoices) {
    final customerId = invoice.customerId;
    if (customerId == null || customerId.isEmpty) continue;
    invoicesByCustomer.putIfAbsent(customerId, () => []).add(invoice);
  }

  return [
    for (final customer in customers)
      if (customer.id case final id? when id.isNotEmpty)
        _entryFor(
          customer,
          bikes: bikesByCustomer[id] ?? const [],
          jobs: jobsByCustomer[id] ?? const [],
          hadJobs: anyJob.contains(id),
          invoices: invoicesByCustomer[id] ?? const [],
          bikesById: bikesById,
          jobBikesByJobId: jobBikesByJobId,
        ),
  ];
}

CustomerDirectoryEntry _entryFor(
  Customer customer, {
  required List<Bike> bikes,
  required List<MechanicJob> jobs,
  required bool hadJobs,
  required List<Invoice> invoices,
  required Map<String, Bike> bikesById,
  required Map<String, List<MechanicJobBike>> jobBikesByJobId,
}) {
  MechanicJob? latest;
  MechanicJob? workshop;
  DateTime? lastVisit;
  for (final job in jobs) {
    if (latest == null || job.arrivalDate.isAfter(latest.arrivalDate)) {
      latest = job;
    }
    if (isMechanicJobIntakeInWorkshop(job) &&
        (workshop == null || job.arrivalDate.isAfter(workshop.arrivalDate))) {
      workshop = job;
    }
    final cancelled = job.status == JobStatus.cancelado ||
        job.customStatus?.code.trim().toUpperCase() == 'CANCELADO';
    if (cancelled) continue;
    final visit = _latest([job.arrivalDate, job.completedAt, job.deliveredAt]);
    if (lastVisit == null || visit.isAfter(lastVisit)) lastVisit = visit;
  }

  var paid = 0.0;
  final owed = <Invoice>[];
  for (final invoice in invoices) {
    if (invoice.status == InvoiceStatus.cancelled) continue;
    paid += invoice.paidAmount;
    if (invoiceIsOwed(invoice)) owed.add(invoice);
    if (invoice.status != InvoiceStatus.draft &&
        (lastVisit == null || invoice.date.isAfter(lastVisit))) {
      lastVisit = invoice.date;
    }
  }
  owed.sort((a, b) => a.date.compareTo(b.date));

  final sortedBikes = [...bikes]..sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
  Bike? mainBike;
  final shown = workshop ?? latest;
  if (shown != null) {
    for (final bikeId in bikeIdsOfJob(shown, jobBikesByJobId)) {
      final bike = bikesById[bikeId];
      if (bike != null && bike.customerId == customer.id) {
        mainBike = bike;
        break;
      }
    }
  }
  mainBike ??= sortedBikes.isEmpty ? null : sortedBikes.first;

  return CustomerDirectoryEntry(
    customer: customer,
    bikes: sortedBikes,
    mainBike: mainBike,
    workshopJob: workshop,
    lastVisitAt: lastVisit,
    paid: paid,
    owedInvoices: owed,
    hasActivity: bikes.isNotEmpty || hadJobs || invoices.isNotEmpty,
  );
}

/// Las filas de una vista, en su orden:
/// - con actividad: los que vinieron hace menos, primero;
/// - en el taller: lo que más espera, primero;
/// - por cobrar: el saldo más alto, primero;
/// - todos: por nombre.
List<CustomerDirectoryEntry> customerDirectoryView(
  Iterable<CustomerDirectoryEntry> rows,
  CustomerListView view,
) {
  final list = switch (view) {
    CustomerListView.active => rows.where((row) => row.hasActivity).toList(),
    CustomerListView.workshop => rows.where((row) => row.inWorkshop).toList(),
    CustomerListView.owed =>
      rows.where((row) => row.owedInvoices.isNotEmpty).toList(),
    CustomerListView.all => rows.toList(),
  };
  int byName(CustomerDirectoryEntry a, CustomerDirectoryEntry b) =>
      a.customer.name.toLowerCase().compareTo(b.customer.name.toLowerCase());
  switch (view) {
    case CustomerListView.active:
      list.sort((a, b) {
        final aDate = a.lastVisitAt;
        final bDate = b.lastVisitAt;
        if (aDate != null && bDate != null) {
          final byDate = bDate.compareTo(aDate);
          if (byDate != 0) return byDate;
        } else if (aDate != null) {
          return -1;
        } else if (bDate != null) {
          return 1;
        }
        return byName(a, b);
      });
    case CustomerListView.workshop:
      list.sort((a, b) =>
          a.workshopJob!.arrivalDate.compareTo(b.workshopJob!.arrivalDate));
    case CustomerListView.owed:
      list.sort((a, b) {
        final byOwed = b.owed.compareTo(a.owed);
        return byOwed != 0 ? byOwed : byName(a, b);
      });
    case CustomerListView.all:
      list.sort(byName);
  }
  return list;
}

/// La búsqueda de la lista: nombre, teléfono (también sólo los dígitos),
/// correo, RUT y sus bicis, con las palabras en cualquier orden.
int customerDirectorySearchScore(CustomerDirectoryEntry row, String query) {
  final customer = row.customer;
  final phone = customer.phone;
  return bikeFinderRelationalSearchScore(
    query: query,
    fields: [
      BikeFinderSearchField(customer.name, weight: 130),
      BikeFinderSearchField(phone, weight: 125),
      BikeFinderSearchField(phone?.replaceAll(RegExp(r'\D'), ''), weight: 125),
      BikeFinderSearchField(customer.email, weight: 115),
      BikeFinderSearchField(customer.rut, weight: 120),
      BikeFinderSearchField(row.workshopJob?.jobNumber, weight: 110),
      for (final bike in row.bikes) ...[
        BikeFinderSearchField(bike.brand, weight: 95),
        BikeFinderSearchField(bike.model, weight: 95),
        BikeFinderSearchField(bike.serialNumber, weight: 110),
      ],
      for (final invoice in row.owedInvoices)
        BikeFinderSearchField(invoice.invoiceNumber, weight: 105),
    ],
  );
}
