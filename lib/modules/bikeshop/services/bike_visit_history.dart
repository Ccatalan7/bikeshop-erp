import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

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
    // si el trabajo no tiene filas o tiene sólo la suya.
    final headerRequest = onlyThisBike ? job.clientRequest?.trim() : null;

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

  final allItems = items.values.expand((lines) => lines).toList();
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
      debugPrint('Bike history product categories: $error');
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
      debugPrint('Bike history service families: $error');
    }
  }

  return buildBikeVisits(
    bikeId: bikeId,
    bike: bike,
    ownerName: ownerName,
    jobs: ownJobs,
    jobBikesByJobId: jobBikes,
    itemsByJobId: items,
    systemOf: (item) => bikeVisitLineSystem(
      item,
      serviceFamily: familyByProductId[item.serviceProductId ?? item.productId],
      categoryPath: categoryPathByProductId[item.productId],
    ),
  );
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}
