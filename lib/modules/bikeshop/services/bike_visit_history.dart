import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/inventory_service.dart';
import '../../inventory/services/category_service.dart';
import '../models/bikeshop_models.dart';
import 'bike_directory_entries.dart';
import 'bikeshop_service.dart';
import 'job_line_systems.dart';
import 'mechanic_job_visibility_policy.dart';
import 'service_wizard_service.dart';

/// Una línea de un trabajo que se le hizo a esta bici.
@immutable
class BikeVisitLine {
  const BikeVisitLine({
    required this.name,
    required this.amount,
    required this.quantity,
    required this.isService,
    required this.system,
  });

  final String name;
  final double amount;
  final double quantity;
  final bool isService;
  final JobLineSystem system;
}

/// Una visita de la bici al taller: un trabajo y lo que se le hizo a ella.
@immutable
class BikeVisit {
  const BikeVisit({
    required this.job,
    required this.groups,
    required this.amount,
    required this.separatePurchaseAmount,
    required this.request,
    required this.inWorkshop,
    this.bikeIds = const [],
  });

  final MechanicJob job;

  /// Las líneas de esta bici por sistema, en el orden de [JobLineSystem].
  final List<({JobLineSystem system, List<BikeVisitLine> lines})> groups;

  /// Lo que costó lo de esta bici.
  final double amount;

  /// Lo comprado aparte en el mismo trabajo (la pestaña «General» del
  /// trabajo): no es de ninguna bici, sólo se menciona.
  final double separatePurchaseAmount;

  /// Lo que pidió el cliente para esta bici.
  final String? request;

  final bool inWorkshop;

  /// Las bicis que entraron en este trabajo (las visitas de un cliente).
  final List<String> bikeIds;

  DateTime get date => job.deliveredAt ?? job.completedAt ?? job.arrivalDate;

  /// Días que estuvo (o lleva) en el taller. Mientras siga ahí cuenta hasta
  /// hoy, aunque el trabajo ya esté terminado y espere el retiro.
  int daysInWorkshop(DateTime today) => calendarDaysBetween(
        job.arrivalDate,
        inWorkshop
            ? today
            : (job.deliveredAt ?? job.completedAt ?? job.updatedAt),
      );

  Set<JobLineSystem> get systems => {for (final group in groups) group.system};
}

/// El sistema de una línea: el que guardó el trabajo y, si no guardó ninguno
/// (los trabajos anteriores a septiembre de 2026), el que dice su familia de
/// servicio o la categoría del repuesto, con la regla de `job_line_systems`.
JobLineSystem bikeVisitLineSystem(
  MechanicJobItem item, {
  String? serviceFamily,
  String? categoryPath,
}) {
  final fromKey = jobLineSystemFromKey(item.systemKey);
  if (fromKey != null) return fromKey;
  return jobLineSystem(
    serviceFamily: serviceFamily,
    categoryPath: categoryPath,
    location: item.location,
  );
}

/// El `system_key` de la memoria de la bici, como sistema de línea.
JobLineSystem? jobLineSystemFromKey(String? key) =>
    switch (key?.trim().toLowerCase()) {
      'drivetrain' || 'bottom_bracket' => JobLineSystem.drivetrain,
      'brakes' => JobLineSystem.brakes,
      'front_brake' => JobLineSystem.frontBrake,
      'rear_brake' => JobLineSystem.rearBrake,
      'wheels' => JobLineSystem.wheels,
      'front_wheel' => JobLineSystem.frontWheel,
      'rear_wheel' => JobLineSystem.rearWheel,
      'cockpit' || 'headset' => JobLineSystem.cockpit,
      'suspension' => JobLineSystem.suspension,
      'general' => JobLineSystem.general,
      _ => null,
    };

/// Arma las visitas de una bici, la más reciente primero.
///
/// Las líneas de la bici son las de su fila en `mechanic_job_bikes`; las sin
/// fila son compra aparte («General», dueño 2026-10-01), salvo en trabajos
/// que no tienen filas por bici, donde todo es de la bici de la cabecera.
/// Los trabajos de prueba no cuentan, con la misma identidad (bici y dueño)
/// con que los descarta el directorio.
List<BikeVisit> buildBikeVisits({
  required String bikeId,
  required List<MechanicJob> jobs,
  required Map<String, List<MechanicJobBike>> jobBikesByJobId,
  required Map<String, List<MechanicJobItem>> itemsByJobId,
  required JobLineSystem Function(MechanicJobItem item) systemOf,
  Bike? bike,
  String? ownerName,
}) {
  final visits = <BikeVisit>[];
  for (final job in jobs) {
    final jobId = job.id;
    if (jobId == null || job.deletedAt != null) continue;
    if (!bikeIdsOfJob(job, jobBikesByJobId).contains(bikeId)) continue;
    if (mechanicJobMatchesTestFixture(
      job,
      customerName: ownerName,
      bikeName: bike?.displayName,
      bikeBrand: bike?.brand,
      bikeModel: bike?.model,
      bikeSerialNumber: bike?.serialNumber,
    )) {
      continue;
    }

    final jobBikes = jobBikesByJobId[jobId] ?? const <MechanicJobBike>[];
    final ownRows = jobBikes.where((row) => row.bikeId == bikeId).toList();
    final ownRowIds = {
      for (final row in ownRows)
        if (row.id != null) row.id!,
    };
    final items = itemsByJobId[jobId] ?? const <MechanicJobItem>[];
    final legacy = jobBikes.isEmpty;
    final onlyThisBike = legacy || jobBikes.length == 1;
    final own = <MechanicJobItem>[];
    var separate = 0.0;
    for (final item in items) {
      final rowId = item.jobBikeId;
      if (legacy || (rowId != null && ownRowIds.contains(rowId))) {
        own.add(item);
      } else if (rowId == null) {
        separate += item.totalPrice;
      }
    }

    final lines = [
      for (final item in own)
        BikeVisitLine(
          name: item.productName.trim().isEmpty
              ? 'Línea sin nombre'
              : item.productName.trim(),
          amount: item.totalPrice,
          quantity: item.quantity,
          isService: item.itemType == 'service',
          system: systemOf(item),
        ),
    ];
    final linesTotal = lines.fold<double>(0, (sum, line) => sum + line.amount);
    final amount = onlyThisBike && separate == 0 && job.totalCost > 0
        ? job.totalCost
        : linesTotal;
    final ownRequest =
        ownRows.isEmpty ? null : ownRows.first.workRequested?.trim();
    // La cabecera guarda el pedido de la primera bici: sólo es de esta bici
    // si el trabajo no tiene filas, o tiene sólo la suya y la cabecera no
    // nombra otra bici.
    final headerBikeId = job.bikeId?.trim();
    final headerIsThisBike = legacy ||
        (jobBikes.length == 1 &&
            (headerBikeId == null ||
                headerBikeId.isEmpty ||
                headerBikeId == bikeId));
    final headerRequest = headerIsThisBike ? job.clientRequest?.trim() : null;

    visits.add(
      BikeVisit(
        job: job,
        groups: groupJobLinesBySystem<BikeVisitLine>(
          lines,
          (line) => line.system,
        ),
        amount: amount,
        separatePurchaseAmount: separate,
        request: (ownRequest != null && ownRequest.isNotEmpty)
            ? ownRequest
            : headerRequest,
        inWorkshop: isMechanicJobIntakeInWorkshop(
          job,
          customerName: ownerName,
          bikeName: bike?.displayName,
          bikeBrand: bike?.brand,
          bikeModel: bike?.model,
          bikeSerialNumber: bike?.serialNumber,
        ),
      ),
    );
  }
  visits.sort((a, b) => b.job.arrivalDate.compareTo(a.job.arrivalDate));
  return visits;
}

/// Lee los trabajos de una bici con sus líneas.
///
/// Trabajos y filas por bici vienen del caché que la app ya precarga; las
/// líneas, de una lectura por lote. Si falla la lectura de filas por bici,
/// falla el historial: tomarla como vacía le daría todos los trabajos a la
/// bici de la cabecera. La categoría de cada repuesto y la familia de cada
/// servicio sólo afinan el sistema: si fallan, las líneas quedan en
/// «General» y el historial igual se muestra.
Future<List<BikeVisit>> loadBikeVisits(
  BuildContext context,
  String bikeId, {
  Bike? bike,
  String? ownerName,
}) async {
  final bikeshop = context.read<BikeshopService>();
  final inventory = _maybeRead<InventoryService>(context);
  final categories = _maybeRead<CategoryService>(context);

  final results = await Future.wait<Object>([
    bikeshop.getJobs(),
    bikeshop.getAllJobBikes(rethrowErrors: true),
  ]);
  final jobs = results[0] as List<MechanicJob>;
  final jobBikes = results[1] as Map<String, List<MechanicJobBike>>;
  final ownJobs = [
    for (final job in jobs)
      if (job.id != null &&
          job.deletedAt == null &&
          bikeIdsOfJob(job, jobBikes).contains(bikeId))
        job,
  ];
  final items = await bikeshop.getJobItemsForJobs(
    ownJobs.map((job) => job.id!),
  );

  final systemOf = await resolveJobLineSystems(
    items.values.expand((lines) => lines),
    inventory: inventory,
    categories: categories,
  );

  return buildBikeVisits(
    bikeId: bikeId,
    bike: bike,
    ownerName: ownerName,
    jobs: ownJobs,
    jobBikesByJobId: jobBikes,
    itemsByJobId: items,
    systemOf: systemOf,
  );
}

/// El sistema de cada línea de [lines], para armar visitas.
///
/// La categoría de cada repuesto y la familia de cada servicio sólo afinan
/// el sistema de las líneas que no lo guardaron: si su lectura falla, esas
/// líneas quedan en «General» y el historial igual se muestra.
Future<JobLineSystem Function(MechanicJobItem item)> resolveJobLineSystems(
  Iterable<MechanicJobItem> lines, {
  InventoryService? inventory,
  CategoryService? categories,
}) async {
  final allItems = lines.toList();
  final productIds = {
    for (final item in allItems)
      if (item.systemKey == null || item.systemKey!.trim().isEmpty)
        if (item.productId case final id? when id.isNotEmpty) id,
  };
  final serviceIds = {
    for (final item in allItems)
      if ((item.systemKey == null || item.systemKey!.trim().isEmpty) &&
          item.itemType == 'service')
        if (item.serviceProductId ?? item.productId case final id?
            when id.isNotEmpty)
          id,
  };

  final categoryPathByProductId = <String, String>{};
  if (inventory != null && categories != null && productIds.isNotEmpty) {
    try {
      final products = await inventory.getProductsByIds(productIds);
      final categoryList = await categories.getCategories();
      final pathByCategoryId = {
        for (final category in categoryList)
          if (category.id case final String id) id: category.fullPath,
      };
      for (final product in products) {
        final path =
            pathByCategoryId[product.categoryId] ?? product.categoryName;
        if (path != null && path.trim().isNotEmpty) {
          categoryPathByProductId[product.id] = path;
        }
      }
    } catch (error) {
      debugPrint('Visit history product categories: $error');
    }
  }

  var familyByProductId = const <String, String>{};
  if (serviceIds.isNotEmpty && allItems.isNotEmpty) {
    try {
      familyByProductId =
          await ServiceWizardService().getServiceFamiliesForProducts(
        serviceIds,
        tenantId: allItems.first.tenantId,
      );
    } catch (error) {
      debugPrint('Visit history service families: $error');
    }
  }

  return (item) => bikeVisitLineSystem(
        item,
        serviceFamily:
            familyByProductId[item.serviceProductId ?? item.productId],
        categoryPath: categoryPathByProductId[item.productId],
      );
}

/// Lo que vale un trabajo para su cliente.
///
/// Una propuesta (presupuesto o cotización) no tiene impuesto antes de
/// facturarse, pero su total con descuento es `totalCost`: no se muestra el
/// subtotal sin descuento. Un trabajo sin impuesto muestra su neto.
double jobDisplayTotal(MechanicJob job) {
  if (job.isQuotationWorkflow) {
    return job.totalCost;
  }
  if (job.taxTreatment == TaxTreatment.noTax) {
    return job.partsCost + job.laborCost;
  }
  return job.totalCost;
}

/// Arma las visitas de un cliente, la más reciente primero: cada trabajo
/// suyo con todas sus líneas.
///
/// A diferencia de la bici, la visita del cliente es el trabajo entero: las
/// líneas de cada bici y lo comprado aparte (en «General», como en el
/// trabajo), con el total del trabajo ([jobDisplayTotal]). Lo que pidió es
/// lo pedido para cada bici; en una cotización sin objeto, lo que se cotizó.
List<BikeVisit> buildCustomerVisits({
  required List<MechanicJob> jobs,
  required Map<String, List<MechanicJobBike>> jobBikesByJobId,
  required Map<String, List<MechanicJobItem>> itemsByJobId,
  required JobLineSystem Function(MechanicJobItem item) systemOf,
  Map<String, Bike> bikesById = const {},
  String? ownerName,
}) {
  final visits = <BikeVisit>[];
  for (final job in jobs) {
    final jobId = job.id;
    if (jobId == null || job.deletedAt != null) continue;
    final jobBikes = [...?jobBikesByJobId[jobId]]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final bikeIds = <String>[
      for (final row in jobBikes)
        if (row.bikeId.trim().isNotEmpty) row.bikeId.trim(),
    ];
    final headerBikeId = job.bikeId?.trim();
    if (bikeIds.isEmpty && headerBikeId != null && headerBikeId.isNotEmpty) {
      bikeIds.add(headerBikeId);
    }
    final distinctBikeIds = bikeIds.toSet().toList();

    final items = itemsByJobId[jobId] ?? const <MechanicJobItem>[];
    final lines = [
      for (final item in items)
        BikeVisitLine(
          name: item.productName.trim().isEmpty
              ? 'Línea sin nombre'
              : item.productName.trim(),
          amount: item.totalPrice,
          quantity: item.quantity,
          isService: item.itemType == 'service',
          // Sin fila de bici en un trabajo que sí las tiene: compra aparte.
          system: jobBikes.isNotEmpty && item.jobBikeId == null
              ? JobLineSystem.general
              : systemOf(item),
        ),
    ];
    final linesTotal = lines.fold<double>(0, (sum, line) => sum + line.amount);
    final total = jobDisplayTotal(job);

    final requestSummary =
        job.isStandaloneQuotation ? job.subjectNotes?.trim() : null;
    final bikeRequests = [
      for (final row in jobBikes)
        if (row.workRequested?.trim() case final text? when text.isNotEmpty)
          text,
    ];
    final request = requestSummary?.isNotEmpty == true
        ? requestSummary
        : bikeRequests.isNotEmpty
            ? bikeRequests.toSet().join('\n')
            : job.clientRequest?.trim();

    final firstBike =
        distinctBikeIds.isEmpty ? null : bikesById[distinctBikeIds.first];
    visits.add(
      BikeVisit(
        job: job,
        groups: groupJobLinesBySystem<BikeVisitLine>(
          lines,
          (line) => line.system,
        ),
        // Una propuesta muestra su total aunque sea cero (todo descontado);
        // sólo un trabajo sin total guardado se suma por sus líneas.
        amount: job.isQuotationWorkflow || total != 0 ? total : linesTotal,
        separatePurchaseAmount: 0,
        request: request,
        inWorkshop: isMechanicJobIntakeInWorkshop(
          job,
          customerName: ownerName,
          bikeName: firstBike?.displayName,
          bikeBrand: firstBike?.brand,
          bikeModel: firstBike?.model,
          bikeSerialNumber: firstBike?.serialNumber,
        ),
        bikeIds: distinctBikeIds,
      ),
    );
  }
  visits.sort((a, b) => b.job.arrivalDate.compareTo(a.job.arrivalDate));
  return visits;
}

/// Lee los trabajos de un cliente con sus líneas, como visitas.
///
/// Igual que [loadBikeVisits]: si falla la lectura de filas por bici, falla
/// la actividad (tomarla como vacía mezclaría lo comprado aparte con lo de
/// cada bici); la categoría y la familia sólo afinan el sistema.
Future<List<BikeVisit>> loadCustomerVisits(
  BuildContext context,
  String customerId, {
  Map<String, Bike> bikesById = const {},
  String? ownerName,
}) async {
  final bikeshop = context.read<BikeshopService>();
  final inventory = _maybeRead<InventoryService>(context);
  final categories = _maybeRead<CategoryService>(context);

  final results = await Future.wait<Object>([
    bikeshop.getJobs(customerId: customerId, includeCompleted: true),
    bikeshop.getAllJobBikes(rethrowErrors: true),
  ]);
  final jobs = [
    for (final job in results[0] as List<MechanicJob>)
      if (job.id != null &&
          job.deletedAt == null &&
          job.customerId == customerId)
        job,
  ];
  final jobBikes = results[1] as Map<String, List<MechanicJobBike>>;
  final items = await bikeshop.getJobItemsForJobs(jobs.map((job) => job.id!));
  final systemOf = await resolveJobLineSystems(
    items.values.expand((lines) => lines),
    inventory: inventory,
    categories: categories,
  );
  return buildCustomerVisits(
    jobs: jobs,
    jobBikesByJobId: jobBikes,
    itemsByJobId: items,
    systemOf: systemOf,
    bikesById: bikesById,
    ownerName: ownerName,
  );
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}
