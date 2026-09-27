import 'package:flutter/material.dart';

import '../../../modules/tasks/models/task_assignment_principal.dart';
import '../../../modules/tasks/models/task_model.dart';
import '../../../modules/tasks/services/task_service.dart';
import 'global_search_commands.dart';

/// Reglas de `/tarea`, sin pantalla: qué se puede encargar sobre un trabajo,
/// cómo se titula, qué plazo significa cada opción y cómo se lee el resumen.
///
/// Viven aparte del panel para que se prueben solas y para que otra superficie
/// (el rail, el asistente) pueda decir lo mismo con las mismas palabras.

/// Lo que se encarga sobre un trabajo del taller. Son las tareas que el taller
/// reparte de verdad (dueño, 2026-09-26: «en general van a ser tareas para los
/// mecánicos o para crear cotizaciones»). «Otra» se escribe a mano.
enum QuickTaskIntent {
  work(
    label: 'Hacer el trabajo',
    description: 'Los servicios del trabajo, como lista para ir marcando',
    icon: Icons.build_rounded,
    verb: 'Hacer el trabajo',
    coversServices: true,
  ),
  diagnosis(
    label: 'Hacer el diagnóstico',
    description: 'Revisar la bici y anotar lo que necesita',
    icon: Icons.manage_search_rounded,
    verb: 'Diagnosticar',
    coversServices: false,
  ),
  quote(
    label: 'Armar el presupuesto',
    description: 'Cotizar lo que hay que hacer y mandarlo al cliente',
    icon: Icons.request_quote_outlined,
    verb: 'Armar el presupuesto',
    coversServices: false,
  ),
  callCustomer(
    label: 'Llamar al cliente',
    description: 'Avisar, pedir aprobación o coordinar el retiro',
    icon: Icons.call_outlined,
    verb: 'Llamar a',
    coversServices: false,
  ),
  other(
    label: 'Otra cosa',
    description: 'Escribe tú qué hay que hacer',
    icon: Icons.edit_outlined,
    verb: '',
    coversServices: false,
  );

  const QuickTaskIntent({
    required this.label,
    required this.description,
    required this.icon,
    required this.verb,
    required this.coversServices,
  });

  final String label;
  final String description;
  final IconData icon;
  final String verb;

  /// Si la tarea parte cubriendo todos los servicios del trabajo. Sólo
  /// «Hacer el trabajo»: un presupuesto o una llamada no son esos servicios.
  final bool coversServices;

  /// El título que propone, editable. Nombra la bici antes que el número:
  /// en el taller se dice «la Trek del Juan», no «la PG-00575».
  String titleFor(TaskLinkableJob job) {
    final bike = job.bikeLabel;
    // «la Trek Marlin 7» / «el trabajo PG-00575», con su artículo.
    final subject = bike == null ? 'el trabajo ${job.jobNumber}' : 'la $bike';
    final ofSubject =
        bike == null ? 'del trabajo ${job.jobNumber}' : 'de la $bike';
    return switch (this) {
      QuickTaskIntent.work => bike == null
          ? 'Hacer el trabajo ${job.jobNumber}'
          : 'Hacer el trabajo $ofSubject',
      QuickTaskIntent.diagnosis => 'Diagnosticar $subject',
      QuickTaskIntent.quote => 'Armar el presupuesto $ofSubject',
      QuickTaskIntent.callCustomer => job.customerName == null
          ? 'Llamar al cliente $ofSubject'
          : 'Llamar a ${job.customerName} por $subject',
      QuickTaskIntent.other => '',
    };
  }
}

/// El plazo, en las palabras de quien reparte trabajo en el mostrador.
enum QuickTaskDue {
  none('Sin plazo'),
  today('Hoy'),
  tomorrow('Mañana'),
  week('Esta semana');

  const QuickTaskDue(this.label);
  final String label;

  /// La fecha que se guarda. «Esta semana» es el sábado, el último día que el
  /// taller atiende; si hoy ya es sábado o domingo, el próximo.
  DateTime? resolve(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      QuickTaskDue.none => null,
      QuickTaskDue.today => today,
      QuickTaskDue.tomorrow => today.add(const Duration(days: 1)),
      QuickTaskDue.week => () {
          var daysToSaturday = DateTime.saturday - today.weekday;
          if (daysToSaturday <= 0) daysToSaturday += 7;
          return today.add(Duration(days: daysToSaturday));
        }(),
    };
  }
}

/// Personas a las que se les puede encargar, con quien escribe primero.
List<TaskAssignmentPrincipal> quickTaskPeople(
  List<TaskAssignmentPrincipal> directory, {
  required String? currentUserId,
}) {
  final people = directory.where((p) => p.isAssignable).toList();
  people.sort((a, b) {
    final aMe = a.userId != null && a.userId == currentUserId;
    final bMe = b.userId != null && b.userId == currentUserId;
    if (aMe != bMe) return aMe ? -1 : 1;
    return normalizeCommandText(a.displayName)
        .compareTo(normalizeCommandText(b.displayName));
  });
  return people;
}

/// Filtra por cualquier palabra del nombre: «ana» y «soto» encuentran a
/// Ana Soto, sin tildes ni mayúsculas.
List<TaskAssignmentPrincipal> filterQuickTaskPeople(
  List<TaskAssignmentPrincipal> people,
  String query,
) {
  final words = _words(query);
  if (words.isEmpty) return people;
  return people.where((person) {
    final haystack = normalizeCommandText(person.displayName);
    return words.every(haystack.contains);
  }).toList(growable: false);
}

/// Filtra trabajos por número, cliente, bici o lo que pidió el cliente.
List<TaskLinkableJob> filterQuickTaskJobs(
  List<TaskLinkableJob> jobs,
  String query,
) {
  final words = _words(query);
  if (words.isEmpty) return jobs;
  return jobs.where((job) {
    final haystack = normalizeCommandText([
      job.jobNumber,
      job.customerName,
      job.bikeLabel,
      job.clientRequest,
      job.statusLabel,
    ].whereType<String>().join(' '));
    return words.every(haystack.contains);
  }).toList(growable: false);
}

/// El orden de «¿Sobre qué trabajo?»: qué tan listo está el trabajo para
/// ponerle manos (dueño, 2026-09-26: «muestra primero los que sí están
/// facturados y luego los que están en presupuestos»; «un presupuesto
/// aprobado obviamente es la segunda prioridad»).
///
///  1. Facturado o pagado: ya se vendió, hay que hacerlo.
///  2. Presupuesto aprobado: el cliente dijo que sí, se puede partir.
///  3. Presupuesto por aprobar: se espera al cliente.
///  4. Sin presupuesto: falta diagnosticar o cotizar.
///  5. Presupuesto rechazado o vencido: no hay trabajo que hacer.
///
/// Dentro de cada grupo, lo que entró más recientemente arriba.
List<TaskLinkableJob> sortQuickTaskJobs(List<TaskLinkableJob> jobs) {
  int group(TaskLinkableJob job) {
    if (job.hasInvoice || job.isPaid) return 0;
    return switch (job.quotationStatus) {
      'approved' => 1,
      'pending' => 2,
      'rejected' || 'expired' => 4,
      _ => 3,
    };
  }

  final sorted = [...jobs];
  sorted.sort((a, b) {
    final byGroup = group(a).compareTo(group(b));
    if (byGroup != 0) return byGroup;
    final aDate = a.receivedAt;
    final bDate = b.receivedAt;
    if (aDate != null && bDate != null && aDate != bDate) {
      return bDate.compareTo(aDate);
    }
    if (aDate != null && bDate == null) return -1;
    if (aDate == null && bDate != null) return 1;
    return b.jobNumber.compareTo(a.jobNumber);
  });
  return sorted;
}

const _quickTaskMonths = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sept',
  'oct',
  'nov',
  'dic',
];

/// «24 sept», y con el año si no es el de hoy: «3 dic 2025». Sin depender de
/// que el idioma de fechas esté cargado.
String quickTaskJobDateLabel(DateTime date, {required DateTime now}) {
  final local = date.isUtc ? date.toLocal() : date;
  final label = '${local.day} ${_quickTaskMonths[local.month - 1]}';
  return local.year == now.year ? label : '$label ${local.year}';
}

/// Filtra los destinos de «otra cosa» (clientes, proveedores, documentos).
List<TaskContextTarget> filterQuickTaskTargets(
  List<TaskContextTarget> targets,
  String query,
) {
  final words = _words(query);
  if (words.isEmpty) return targets;
  return targets.where((target) {
    final haystack = normalizeCommandText(
        '${target.label} ${target.context ?? ''} ${target.searchText ?? ''}');
    return words.every(haystack.contains);
  }).toList(growable: false);
}

List<String> _words(String query) => normalizeCommandText(query)
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .toList(growable: false);

/// Cómo le llega la tarea, dicho antes de crearla y después de crearla.
String quickTaskDeliveryNote(
  TaskAssignmentPrincipal person, {
  required String? currentUserId,
}) {
  if (person.userId != null && person.userId == currentUserId) {
    return 'Queda en tu bandeja.';
  }
  final firstName = person.displayName.split(RegExp(r'\s+')).first;
  return switch (person.access) {
    TaskPrincipalAccess.erp => 'Le llega a $firstName en su bandeja de tareas.',
    TaskPrincipalAccess.portal => 'Le llega a $firstName en su portal.',
    TaskPrincipalAccess.none =>
      '$firstName todavía no tiene cuenta: la tarea queda a su nombre en la '
          'bandeja del equipo y le llega sola el día que tenga una.',
  };
}

/// Cómo se llama un presupuesto en la fila de un trabajo.
({String label, QuickTaskSignalTone tone})? quickTaskQuotationSignal(
    TaskLinkableJob job) {
  return switch (job.quotationStatus) {
    'pending' => (
        label: 'Presupuesto por aprobar',
        tone: QuickTaskSignalTone.warning
      ),
    'approved' => (
        label: 'Presupuesto aprobado',
        tone: QuickTaskSignalTone.success
      ),
    'rejected' => (
        label: 'Presupuesto rechazado',
        tone: QuickTaskSignalTone.danger
      ),
    _ => null,
  };
}

/// Cómo se llama la factura en la fila de un trabajo.
({String label, QuickTaskSignalTone tone})? quickTaskInvoiceSignal(
    TaskLinkableJob job) {
  if (job.isPaid) return (label: 'Pagado', tone: QuickTaskSignalTone.success);
  if (job.hasInvoice) {
    return (label: 'Facturado', tone: QuickTaskSignalTone.info);
  }
  return null;
}

/// «3 servicios», «1 servicio», «Sin servicios».
String quickTaskServiceCountLabel(int count) => switch (count) {
      0 => 'Sin servicios',
      1 => '1 servicio',
      _ => '$count servicios',
    };

/// Tono de una señal, traducido a `VbStatusTone` por la pantalla.
enum QuickTaskSignalTone { neutral, info, success, warning, danger }
