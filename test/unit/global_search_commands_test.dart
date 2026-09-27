import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/tasks/models/task_assignment_principal.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_commands.dart';
import 'package:vinabike_erp/shared/services/global_search/quick_task_draft.dart';

/// Acciones rápidas del buscador («/») y las reglas de `/tarea` (dueño,
/// 2026-09-26: «si escribo slash t, va a reconocer la acción rápida de
/// tareas, porque esa empieza con t»).
TaskAssignmentPrincipal _person(
  String name, {
  String? userId,
  String? employeeId,
  TaskPrincipalAccess access = TaskPrincipalAccess.erp,
}) =>
    TaskAssignmentPrincipal(
      tenantId: 't',
      userId: userId,
      employeeId: employeeId,
      displayName: name,
      role: 'mechanic',
      photoUrl: null,
      access: access,
    );

const _job = TaskLinkableJob(
  id: 'j1',
  jobNumber: 'PG-00575',
  status: 'ESPERANDO_APROBACION',
  customerName: 'Juan Pérez',
  clientRequest: 'Cambio de maneta',
  statusLabel: 'Esperando aprobación',
  bikeLabel: 'Trek Marlin 7',
  quotationStatus: 'pending',
  hasInvoice: true,
);

void main() {
  group('lo escrito como acción', () {
    test('sólo lo que empieza con «/» es una acción', () {
      expect(GlobalSearchCommandInput.parse('tarea'), isNull);
      expect(GlobalSearchCommandInput.parse('/')!.command, '');
      expect(GlobalSearchCommandInput.parse('  /t')!.command, 't');
    });

    test('lo que sigue al primer espacio es el comienzo del flujo', () {
      final input = GlobalSearchCommandInput.parse('/tarea vicente díaz')!;
      expect(input.command, 'tarea');
      expect(input.argument, 'vicente díaz');
      expect(input.hasArgument, isTrue);
    });

    test('mayúsculas y tildes no importan', () {
      expect(GlobalSearchCommandInput.parse('/TÁREA')!.command, 'tarea');
      expect(normalizeCommandText('Díaz Ñuñoa'), 'diaz nunoa');
    });
  });

  group('qué acción calza', () {
    test('«/t» es Tarea: empieza con t', () {
      expect(matchGlobalSearchCommands('t').first.id, 'tarea');
      expect(matchGlobalSearchCommands('tar').single.id, 'tarea');
    });

    test('sin nada escrito después de «/», todas', () {
      expect(matchGlobalSearchCommands(''), kGlobalSearchCommands);
    });

    test('los alias también la encuentran', () {
      expect(matchGlobalSearchCommands('pend').single.id, 'tarea');
    });

    test('lo que no calza con nada, no inventa', () {
      expect(matchGlobalSearchCommands('xyz'), isEmpty);
    });

    test('empezar con lo escrito gana a contenerlo', () {
      const traspaso = GlobalSearchCommand(
        id: 'traspaso',
        name: 'Traspaso',
        description: 'Mover stock',
        icon: Icons.swap_horiz,
      );
      const mantener = GlobalSearchCommand(
        id: 'mantener',
        name: 'Mantener',
        description: 'Contiene «t»',
        icon: Icons.build,
      );
      final matches = matchGlobalSearchCommands(
        't',
        commands: const [mantener, traspaso, kGlobalSearchTaskCommand],
      );
      expect(matches.map((c) => c.id), ['traspaso', 'tarea', 'mantener']);
    });
  });

  group('/tarea', () {
    test('cada tipo de tarea se titula con la bici, como se habla', () {
      expect(QuickTaskIntent.work.titleFor(_job),
          'Hacer el trabajo de la Trek Marlin 7');
      expect(QuickTaskIntent.quote.titleFor(_job),
          'Armar el presupuesto de la Trek Marlin 7');
      expect(QuickTaskIntent.callCustomer.titleFor(_job),
          'Llamar a Juan Pérez por la Trek Marlin 7');
      expect(QuickTaskIntent.other.titleFor(_job), isEmpty);
    });

    test('sin bici, el número del trabajo', () {
      const bare = TaskLinkableJob(
        id: 'j2',
        jobNumber: 'PG-00001',
        status: null,
        customerName: null,
        clientRequest: null,
      );
      expect(QuickTaskIntent.work.titleFor(bare), 'Hacer el trabajo PG-00001');
      expect(QuickTaskIntent.diagnosis.titleFor(bare),
          'Diagnosticar el trabajo PG-00001');
      expect(QuickTaskIntent.quote.titleFor(bare),
          'Armar el presupuesto del trabajo PG-00001');
      expect(QuickTaskIntent.callCustomer.titleFor(bare),
          'Llamar al cliente del trabajo PG-00001');
    });

    test('un componente se nombra por lo que es, con el número', () {
      const wheel = TaskLinkableJob(
        id: 'j3',
        jobNumber: 'PG-00579',
        status: null,
        customerName: 'Francisco Muñoz',
        clientRequest: null,
        componentLabel: 'Rueda trasera',
      );
      expect(wheel.objectLabel, 'Rueda trasera');
      expect(QuickTaskIntent.work.titleFor(wheel),
          'Hacer el trabajo PG-00579 (Rueda trasera)');
      expect(QuickTaskIntent.diagnosis.titleFor(wheel),
          'Diagnosticar el trabajo PG-00579 (Rueda trasera)');
      expect(QuickTaskIntent.quote.titleFor(wheel),
          'Armar el presupuesto del trabajo PG-00579 (Rueda trasera)');
      expect(QuickTaskIntent.callCustomer.titleFor(wheel),
          'Llamar a Francisco Muñoz por el trabajo PG-00579 (Rueda trasera)');
      expect(filterQuickTaskJobs([wheel], 'rueda'), [wheel]);
    });

    test('sólo «Hacer el trabajo» parte cubriendo los servicios', () {
      expect(
        QuickTaskIntent.values.where((intent) => intent.coversServices),
        [QuickTaskIntent.work],
      );
    });

    test('los plazos caen en el día que se dice', () {
      // Jueves 24 de septiembre de 2026.
      final thursday = DateTime(2026, 9, 24, 16, 30);
      expect(QuickTaskDue.none.resolve(thursday), isNull);
      expect(QuickTaskDue.today.resolve(thursday), DateTime(2026, 9, 24));
      expect(QuickTaskDue.tomorrow.resolve(thursday), DateTime(2026, 9, 25));
      expect(QuickTaskDue.week.resolve(thursday), DateTime(2026, 9, 26));
      // Un sábado, «esta semana» ya es la próxima.
      expect(QuickTaskDue.week.resolve(DateTime(2026, 9, 26, 10)),
          DateTime(2026, 10, 3));
    });

    test('quien escribe va primero; el resto por nombre', () {
      final people = quickTaskPeople([
        _person('Vicente Díaz', userId: 'u2', employeeId: 'e2'),
        _person('Braulio Muñoz',
            employeeId: 'e3', access: TaskPrincipalAccess.none),
        _person('Claudio Catalán', userId: 'me', employeeId: 'e1'),
      ], currentUserId: 'me');
      expect(people.map((p) => p.displayName),
          ['Claudio Catalán', 'Braulio Muñoz', 'Vicente Díaz']);
    });

    test('el trabajador sin cuenta también está: la tarea le llega después',
        () {
      final people = quickTaskPeople([
        _person('Braulio Muñoz',
            employeeId: 'e3', access: TaskPrincipalAccess.none),
        _person('Sin ficha ni cuenta', access: TaskPrincipalAccess.none),
      ], currentUserId: 'me');
      expect(people.map((p) => p.displayName), ['Braulio Muñoz']);
    });

    test('cualquier palabra del nombre encuentra a la persona', () {
      final people = [
        _person('Vicente Díaz', userId: 'u2', employeeId: 'e2'),
        _person('Rodrigo Nieto', employeeId: 'e4'),
      ];
      expect(filterQuickTaskPeople(people, 'diaz').single.displayName,
          'Vicente Díaz');
      expect(filterQuickTaskPeople(people, 'vic di').single.displayName,
          'Vicente Díaz');
      expect(filterQuickTaskPeople(people, ''), people);
    });

    test('un trabajo se encuentra por número, cliente o bici', () {
      expect(filterQuickTaskJobs([_job], '575'), [_job]);
      expect(filterQuickTaskJobs([_job], 'perez'), [_job]);
      expect(filterQuickTaskJobs([_job], 'marlin'), [_job]);
      expect(filterQuickTaskJobs([_job], 'giant'), isEmpty);
    });

    test('se dice cómo le llega a cada quien', () {
      expect(
        quickTaskDeliveryNote(
            _person('Vicente Díaz', userId: 'u2', employeeId: 'e2'),
            currentUserId: 'me'),
        'Le llega a Vicente en su bandeja de tareas.',
      );
      expect(
        quickTaskDeliveryNote(
            _person('Fernando Tapia',
                userId: 'u5',
                employeeId: 'e5',
                access: TaskPrincipalAccess.portal),
            currentUserId: 'me'),
        'Le llega a Fernando en su portal.',
      );
      expect(
        quickTaskDeliveryNote(
            _person('Braulio Muñoz',
                employeeId: 'e3', access: TaskPrincipalAccess.none),
            currentUserId: 'me'),
        contains('le llega sola el día que tenga una'),
      );
      expect(
        quickTaskDeliveryNote(
            _person('Claudio', userId: 'me', employeeId: 'e1'),
            currentUserId: 'me'),
        'Queda en tu bandeja.',
      );
    });

    test('facturado, aprobado, por aprobar, sin presupuesto, rechazado', () {
      TaskLinkableJob job(String number,
              {bool invoiced = false,
              bool paid = false,
              String? quotation,
              DateTime? received,
              bool finished = false}) =>
          TaskLinkableJob(
            id: number,
            jobNumber: number,
            status: null,
            customerName: null,
            clientRequest: null,
            hasInvoice: invoiced,
            isPaid: paid,
            quotationStatus: quotation,
            receivedAt: received,
            workFinished: finished,
          );
      final sorted = sortQuickTaskJobs([
        job('PG-1', received: DateTime(2026, 9, 25)),
        job('PG-2', quotation: 'pending', received: DateTime(2026, 9, 20)),
        job('PG-3', invoiced: true, received: DateTime(2026, 9, 10)),
        job('PG-4', quotation: 'approved', received: DateTime(2026, 9, 2)),
        job('PG-5', paid: true, received: DateTime(2026, 9, 22)),
        job('PG-6',
            invoiced: true,
            quotation: 'approved',
            received: DateTime(2026, 9, 1)),
        job('PG-7', quotation: 'rejected', received: DateTime(2026, 9, 26)),
        job('PG-8', quotation: 'pending', received: DateTime(2026, 9, 23)),
        job('PG-9',
            invoiced: true, finished: true, received: DateTime(2026, 9, 25)),
      ]);
      // El aprobado va segundo aunque sea más viejo que los por aprobar; el
      // rechazado va al final aunque sea el más nuevo.
      // El facturado ya terminado va al final de su grupo aunque sea el más
      // nuevo: sólo espera que lo retiren.
      expect(sorted.map((j) => j.jobNumber), [
        'PG-5', 'PG-3', 'PG-6', 'PG-9', //
        'PG-4', 'PG-8', 'PG-2', 'PG-1', 'PG-7',
      ]);
    });

    test('la fecha del trabajo se dice corta, con el año sólo si no es éste',
        () {
      final now = DateTime(2026, 9, 26);
      expect(quickTaskJobDateLabel(DateTime(2026, 9, 24), now: now), '24 sept');
      expect(
          quickTaskJobDateLabel(DateTime(2025, 12, 3), now: now), '3 dic 2025');
    });

    test('las señales del trabajo dicen presupuesto, factura y servicios', () {
      expect(quickTaskQuotationSignal(_job)!.label, 'Presupuesto por aprobar');
      expect(quickTaskInvoiceSignal(_job)!.label, 'Facturado');
      expect(quickTaskServiceCountLabel(0), 'Sin servicios');
      expect(quickTaskServiceCountLabel(1), '1 servicio');
      expect(quickTaskServiceCountLabel(3), '3 servicios');
    });
  });
}
