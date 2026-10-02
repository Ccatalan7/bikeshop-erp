import 'package:flutter/material.dart';

import '../../../shared/utils/bike_finder_search.dart';
import '../../crm/models/crm_models.dart';
import '../models/bikeshop_models.dart';
import 'mechanic_job_visibility_policy.dart';

/// En qué punto del taller está una bici que todavía no se retira.
///
/// Sale de la fase que el taller le dio a cada estado en `job_statuses`
/// (Pendiente y Contactar son «por hacer»; Terminado y Probado, «completo»),
/// no del nombre del estado: el taller los renombra («REPUESTOS»).
enum BikeWorkshopStage {
  toStart('Por empezar', 'Recibidas, sin empezar'),
  inProgress('En trabajo', 'Lo que más espera, arriba'),
  readyForPickup('Para retirar', 'Tiempo desde que se terminó');

  const BikeWorkshopStage(this.label, this.hint);

  final String label;
  final String hint;
}

/// Una fila del directorio: la bici, su dueño y lo que dicen sus trabajos.
@immutable
class BikeDirectoryEntry {
  const BikeDirectoryEntry({
    required this.bike,
    required this.owner,
    required this.latestJob,
    required this.workshopJob,
    required this.visits,
    required this.lastVisitAt,
  });

  final Bike bike;
  final Customer? owner;

  /// El trabajo más reciente, cualquiera sea su estado.
  final MechanicJob? latestJob;

  /// El trabajo por el que la bici está hoy en el taller.
  final MechanicJob? workshopJob;

  /// Trabajos no cancelados.
  final int visits;

  final DateTime? lastVisitAt;

  bool get inWorkshop => workshopJob != null;

  BikeWorkshopStage? get stage {
    final job = workshopJob;
    if (job == null) return null;
    return switch (jobStatusPhase(job)) {
      StatusPhase.todo => BikeWorkshopStage.toStart,
      StatusPhase.inProgress => BikeWorkshopStage.inProgress,
      StatusPhase.complete => BikeWorkshopStage.readyForPickup,
    };
  }

  /// Desde cuándo espera: la llegada, o el término si ya está para retirar.
  DateTime? get waitingSince {
    final job = workshopJob;
    if (job == null) return null;
    if (stage == BikeWorkshopStage.readyForPickup) {
      return job.completedAt ?? job.statusUpdatedAt ?? job.arrivalDate;
    }
    return job.arrivalDate;
  }

  int? waitingDays(DateTime today) {
    final since = waitingSince;
    if (since == null) return null;
    return calendarDaysBetween(since, today);
  }
}

/// Días de calendario entre dos fechas, en la hora local. Se cuentan entre
/// fechas UTC del mismo día para que un cambio de hora no quite un día.
int calendarDaysBetween(DateTime from, DateTime to) {
  final start = from.toLocal();
  final end = to.toLocal();
  final days = DateTime.utc(end.year, end.month, end.day)
      .difference(DateTime.utc(start.year, start.month, start.day))
      .inDays;
  return days < 0 ? 0 : days;
}

/// La fase del estado del trabajo, con el enum antiguo de respaldo.
StatusPhase jobStatusPhase(MechanicJob job) {
  final custom = job.customStatus;
  if (custom != null) return custom.phase;
  return switch (job.status) {
    JobStatus.pendiente => StatusPhase.todo,
    JobStatus.finalizado ||
    JobStatus.entregado ||
    JobStatus.cancelado =>
      StatusPhase.complete,
    _ => StatusPhase.inProgress,
  };
}

/// El nombre del estado como lo configuró el taller. Los que el taller dejó
/// en mayúsculas («COMENZAR», «REPUESTOS») se muestran como frase.
String jobStatusLabel(MechanicJob job) {
  final name = job.customStatus?.name.trim() ?? '';
  if (name.isEmpty) return job.status.displayName;
  if (name.length > 3 && name == name.toUpperCase()) {
    final lower = name.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }
  return name;
}

/// El color que el taller le dio al estado.
Color jobStatusColor(MechanicJob job) {
  final custom = job.customStatus;
  if (custom != null) return custom.colorValue;
  return switch (job.status) {
    JobStatus.pendiente || JobStatus.diagnostico => const Color(0xFF6B7280),
    JobStatus.esperandoAprobacion => const Color(0xFFF59E0B),
    JobStatus.esperandoRepuestos => const Color(0xFFF97316),
    JobStatus.enCurso => const Color(0xFF3B82F6),
    JobStatus.finalizado || JobStatus.entregado => const Color(0xFF84CC16),
    JobStatus.cancelado => const Color(0xFFEF4444),
  };
}

bool _isCancelled(MechanicJob job) =>
    job.status == JobStatus.cancelado ||
    job.customStatus?.code.trim().toUpperCase() == 'CANCELADO';

/// Las bicis de cada trabajo: sus filas por bici y, si no tiene, la de su
/// cabecera. Ver [isMechanicJobIntakeInWorkshop].
Set<String> bikeIdsOfJob(
  MechanicJob job,
  Map<String, List<MechanicJobBike>> jobBikesByJobId,
) {
  final ids = <String>{
    for (final jobBike in jobBikesByJobId[job.id] ?? const <MechanicJobBike>[])
      if (jobBike.bikeId.trim().isNotEmpty) jobBike.bikeId.trim(),
  };
  final headerBikeId = job.bikeId?.trim();
  if (ids.isEmpty && headerBikeId != null && headerBikeId.isNotEmpty) {
    ids.add(headerBikeId);
  }
  return ids;
}

/// Arma las filas del directorio. Los trabajos de prueba no cuentan, igual
/// que en el buscador rápido y en la tabla de trabajos.
List<BikeDirectoryEntry> buildBikeDirectoryEntries({
  required List<Bike> bikes,
  required Map<String, Customer> customersById,
  required List<MechanicJob> jobs,
  required Map<String, List<MechanicJobBike>> jobBikesByJobId,
}) {
  final bikesById = {
    for (final bike in bikes)
      if (bike.id != null && bike.id!.isNotEmpty) bike.id!: bike,
  };
  final jobsByBikeId = <String, List<MechanicJob>>{};
  for (final job in jobs) {
    if (job.deletedAt != null) continue;
    for (final bikeId in bikeIdsOfJob(job, jobBikesByJobId)) {
      final bike = bikesById[bikeId];
      if (bike == null) continue;
      final owner = customersById[bike.customerId];
      if (mechanicJobMatchesTestFixture(
        job,
        customerName: owner?.name,
        bikeName: bike.displayName,
        bikeBrand: bike.brand,
        bikeModel: bike.model,
        bikeSerialNumber: bike.serialNumber,
      )) {
        continue;
      }
      jobsByBikeId.putIfAbsent(bikeId, () => []).add(job);
    }
  }

  return [
    for (final bike in bikesById.values)
      _entryFor(
        bike,
        customersById[bike.customerId],
        jobsByBikeId[bike.id] ?? const [],
      ),
  ];
}

BikeDirectoryEntry _entryFor(
  Bike bike,
  Customer? owner,
  List<MechanicJob> jobs,
) {
  MechanicJob? latest;
  MechanicJob? inWorkshop;
  DateTime? lastVisit;
  var visits = 0;
  for (final job in jobs) {
    if (!_isCancelled(job)) visits++;
    if (latest == null ||
        job.arrivalDate.isAfter(latest.arrivalDate) ||
        (job.arrivalDate.isAtSameMomentAs(latest.arrivalDate) &&
            job.updatedAt.isAfter(latest.updatedAt))) {
      latest = job;
    }
    if (isMechanicJobIntakeInWorkshop(job) &&
        (inWorkshop == null ||
            job.arrivalDate.isAfter(inWorkshop.arrivalDate))) {
      inWorkshop = job;
    }
    final activity = [job.arrivalDate, job.completedAt, job.deliveredAt]
        .whereType<DateTime>()
        .reduce((a, b) => a.isAfter(b) ? a : b);
    if (lastVisit == null || activity.isAfter(lastVisit)) lastVisit = activity;
  }
  return BikeDirectoryEntry(
    bike: bike,
    owner: owner,
    latestJob: latest,
    workshopJob: inWorkshop,
    visits: visits,
    lastVisitAt: lastVisit,
  );
}

/// «Todas»: las que vinieron hace menos, primero; las sin trabajos al final.
List<BikeDirectoryEntry> sortByRecentVisit(Iterable<BikeDirectoryEntry> rows) {
  final sorted = rows.toList();
  sorted.sort((a, b) {
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
    return b.bike.updatedAt.compareTo(a.bike.updatedAt);
  });
  return sorted;
}

/// «En el taller»: por etapa y, dentro de cada una, lo que más espera arriba.
List<({BikeWorkshopStage stage, List<BikeDirectoryEntry> rows})>
    groupInWorkshop(Iterable<BikeDirectoryEntry> rows) {
  final byStage = <BikeWorkshopStage, List<BikeDirectoryEntry>>{};
  for (final row in rows) {
    final stage = row.stage;
    if (stage == null) continue;
    byStage.putIfAbsent(stage, () => []).add(row);
  }
  return [
    for (final stage in BikeWorkshopStage.values)
      if (byStage[stage] case final group?)
        (
          stage: stage,
          rows: group
            ..sort((a, b) => (a.waitingSince ?? DateTime(0))
                .compareTo(b.waitingSince ?? DateTime(0))),
        ),
  ];
}

/// La búsqueda del buscador rápido de bicis: palabras en cualquier orden,
/// repartidas entre la bici y su dueño, con un error de tipeo tolerado.
int bikeDirectorySearchScore(BikeDirectoryEntry row, String query) {
  final bike = row.bike;
  final owner = row.owner;
  return bikeFinderRelationalSearchScore(
    query: query,
    fields: [
      BikeFinderSearchField(bike.serialNumber, weight: 135),
      BikeFinderSearchField(bike.qrCode, weight: 135),
      BikeFinderSearchField(bike.displayName, weight: 125),
      BikeFinderSearchField(bike.brand, weight: 108),
      BikeFinderSearchField(bike.model, weight: 108),
      BikeFinderSearchField(owner?.name, weight: 120),
      BikeFinderSearchField(owner?.rut, weight: 128),
      BikeFinderSearchField(owner?.phone, weight: 128),
      BikeFinderSearchField(owner?.email, weight: 112),
      BikeFinderSearchField(row.latestJob?.jobNumber, weight: 120),
      BikeFinderSearchField(bike.year?.toString(), weight: 92),
      BikeFinderSearchField(bike.color, weight: 78),
      BikeFinderSearchField(bike.bikeType?.displayName, weight: 72),
      BikeFinderSearchField(bike.notes, weight: 55),
    ],
  );
}

/// «Aro 29», «700c», «Aro 27.5» desde lo que se escribió (29", 29'', 700).
String? wheelSizeLabel(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  final cleaned = value
      .replaceAll('"', '')
      .replaceAll("''", '')
      .replaceAll('”', '')
      .replaceAll(',', '.')
      .trim();
  if (cleaned.isEmpty) return null;
  final lower = cleaned.toLowerCase();
  if (lower == '700' || lower == '700c') return '700c';
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) return 'Aro $cleaned';
  return cleaned;
}
