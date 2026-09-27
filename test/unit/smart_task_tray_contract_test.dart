import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/tasks/models/smart_task_event.dart';
import 'package:vinabike_erp/modules/tasks/models/smart_task_job_item.dart';
import 'package:vinabike_erp/modules/tasks/models/task_assignment_principal.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/modules/worker_portal/services/worker_tasks_service.dart';

void main() {
  group('TaskModel · contrato de bandeja', () {
    Map<String, dynamic> baseRow() => {
          'id': '11111111-1111-4111-8111-111111111111',
          'tenant_id': '22222222-2222-4222-8222-222222222222',
          'title': 'Ajuste de cambios',
          'status': 'blocked',
          'priority': 'high',
          'task_kind': 'task',
          'visibility': 'private',
          'version': 7,
          'assigned_to': '33333333-3333-4333-8333-333333333333',
          'created_by': '44444444-4444-4444-8444-444444444444',
          'blocked_reason': 'Falta repuesto',
          'blocked_at': '2026-08-26T12:00:00Z',
          'acknowledged_at': null,
          'created_at': '2026-08-25T10:00:00Z',
          'updated_at': '2026-08-26T12:00:00Z',
        };

    test('parsea estado blocked, tipo, visibilidad y versión', () {
      final task = TaskModel.fromJson(baseRow());
      expect(task.status, TaskStatus.blocked);
      expect(task.isBlocked, isTrue);
      expect(task.kind, TaskKind.task);
      expect(task.visibility, TaskVisibility.private);
      expect(task.version, 7);
      expect(task.blockedReason, 'Falta repuesto');
    });

    test('una fila legada sin columnas nuevas sigue siendo válida', () {
      final task = TaskModel.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'tenant_id': '22222222-2222-4222-8222-222222222222',
        'title': 'Legada',
        'status': 'completed',
        'priority': 'normal',
        'created_by': '44444444-4444-4444-8444-444444444444',
      });
      expect(task.kind, TaskKind.task);
      expect(task.visibility, TaskVisibility.team);
      expect(task.version, 1);
      expect(task.isDone, isTrue);
    });

    test('toJson no exporta columnas de servidor (versión, sellos)', () {
      final json = TaskModel.fromJson(baseRow()).toJson();
      expect(json['task_kind'], 'task');
      expect(json['visibility'], 'private');
      expect(json.containsKey('version'), isFalse);
      expect(json.containsKey('acknowledged_at'), isFalse);
      expect(json.containsKey('blocked_at'), isFalse);
      expect(json.containsKey('completed_at'), isFalse);
    });

    test('por aceptar = asignada sin acuse y no terminada', () {
      final row = baseRow()..['status'] = 'pending';
      expect(TaskModel.fromJson(row).awaitsAcknowledgement, isTrue);
      final acknowledged =
          TaskModel.fromJson(row..['acknowledged_at'] = '2026-08-26T12:30:00Z');
      expect(acknowledged.awaitsAcknowledgement, isFalse);
    });

    test('la prioridad viaja en el vocabulario de la base', () {
      expect(taskPriorityWire(TaskPriority.urgent), 'urgent');
      expect(taskPriorityWire(TaskPriority.low), 'low');
    });
  });

  group('SmartTaskJobItem · evidencia durable', () {
    test('conserva snapshot y expone invalidación y cambio de contexto', () {
      final link = SmartTaskJobItem.fromJson({
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'task_id': '11111111-1111-4111-8111-111111111111',
        'job_item_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'job_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'item_name': 'Mantención de motor',
        'item_instructions':
            'REVISIÓN DE HORQUILLA Y MANTENCIÓN SI ES NECESARIO',
        'item_type': 'service',
        'job_number': 'PG-001234',
        'bike_label': 'Trek 820',
        'linked_at': '2026-08-26T10:00:00Z',
        'invalidated_at': '2026-08-26T15:00:00Z',
        'context_changed_at': null,
      });
      expect(link.itemName, 'Mantención de motor');
      expect(link.itemInstructions,
          'REVISIÓN DE HORQUILLA Y MANTENCIÓN SI ES NECESARIO');
      expect(link.isInvalidated, isTrue);
      expect(link.contextChanged, isFalse);
      expect(link.jobNumber, 'PG-001234');
      expect(link.isDone, isFalse, reason: 'sin done_at, pendiente');
    });

    test('lee hecho, cuándo y quién', () {
      final link = SmartTaskJobItem.fromJson({
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'task_id': '11111111-1111-4111-8111-111111111111',
        'job_item_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'job_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'item_name': 'Purga de frenos',
        'linked_at': '2026-09-26T10:00:00Z',
        'done_at': '2026-09-26T15:10:00Z',
        'done_by': '33333333-3333-4333-8333-333333333333',
      });
      expect(link.isDone, isTrue);
      expect(link.doneAt, DateTime.utc(2026, 9, 26, 15, 10));
      expect(link.doneBy, '33333333-3333-4333-8333-333333333333');
    });
  });

  group('TaskLinkableJob · trabajo ya terminado', () {
    Map<String, dynamic> row(String status, {Map<String, dynamic>? custom}) => {
          'id': 'j1',
          'tenant_id': 't',
          'job_number': 'PG-00565',
          'status': status,
          'arrival_date': '2026-09-16T12:00:00Z',
          'created_at': '2026-09-16T12:00:00Z',
          'updated_at': '2026-09-20T12:00:00Z',
          if (custom != null) 'job_status': custom,
        };

    test('el estado propio de fase complete («Terminado») lo termina', () {
      final job = TaskLinkableJob.fromJson(row('FINALIZADO', custom: {
        'id': 's1',
        'tenant_id': 't',
        'name': 'Terminado',
        'code': 'FINALIZADO',
        'color': '#10B981',
        'phase': 'complete',
      }));
      expect(job.workFinished, isTrue);
      expect(job.statusLabel, 'Terminado');
    });

    test('un estado propio en curso no lo termina', () {
      final job = TaskLinkableJob.fromJson(row('EN_PAUSA', custom: {
        'id': 's2',
        'tenant_id': 't',
        'name': 'En Pausa',
        'code': 'EN_PAUSA',
        'color': '#F59E0B',
        'phase': 'in_progress',
      }));
      expect(job.workFinished, isFalse);
    });

    test('sin estado propio, manda el estado base', () {
      expect(TaskLinkableJob.fromJson(row('FINALIZADO')).workFinished, isTrue);
      expect(TaskLinkableJob.fromJson(row('EN_CURSO')).workFinished, isFalse);
    });
  });

  group('TaskModel · nota para el siguiente turno', () {
    test('lee la nota con autor y hora, y no la exporta', () {
      final task = TaskModel.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'tenant_id': '22222222-2222-4222-8222-222222222222',
        'title': 'Hacer el trabajo',
        'status': 'in_progress',
        'created_by': '44444444-4444-4444-8444-444444444444',
        'handoff_note': '  Falta la piola  ',
        'handoff_note_at': '2026-09-26T21:40:00Z',
        'handoff_note_by': '33333333-3333-4333-8333-333333333333',
        'created_at': '2026-09-26T10:00:00Z',
        'updated_at': '2026-09-26T21:40:00Z',
      });
      expect(task.handoffNote, 'Falta la piola');
      expect(task.handoffNoteAt, DateTime.utc(2026, 9, 26, 21, 40));
      expect(task.handoffNoteBy, '33333333-3333-4333-8333-333333333333');
      expect(task.toJson().containsKey('handoff_note'), isFalse,
          reason: 'la nota la escribe sólo su comando');
    });
  });

  group('TaskModel · plazo como fecha de calendario', () {
    // Así vuelve de la base: la app manda la medianoche sin zona y la base
    // corre en UTC, así que el plazo «sábado 26» es 2026-09-26 00:00 UTC.
    TaskModel due(String? stored, {String status = 'pending'}) =>
        TaskModel.fromJson({
          'id': '11111111-1111-4111-8111-111111111111',
          'tenant_id': '22222222-2222-4222-8222-222222222222',
          'title': 'Hacer el trabajo',
          'status': status,
          'created_by': '44444444-4444-4444-8444-444444444444',
          'due_date': stored,
          'created_at': '2026-09-25T10:00:00Z',
          'updated_at': '2026-09-25T10:00:00Z',
        });

    test('el día del plazo no está vencida, ni a medianoche ni al cierre', () {
      final task = due('2026-09-26T00:00:00+00:00');
      expect(task.dueDay, DateTime(2026, 9, 26));
      expect(task.isOverdueAt(DateTime(2026, 9, 26, 0, 5)), isFalse);
      expect(task.isOverdueAt(DateTime(2026, 9, 26, 23, 59)), isFalse);
    });

    test('al día siguiente sí, salvo que esté cerrada', () {
      expect(
          due('2026-09-26T00:00:00+00:00')
              .isOverdueAt(DateTime(2026, 9, 27, 8)),
          isTrue);
      expect(
          due('2026-09-26T00:00:00+00:00', status: 'completed')
              .isOverdueAt(DateTime(2026, 9, 27, 8)),
          isFalse);
    });

    test('sin plazo nunca vence', () {
      expect(due(null).dueDay, isNull);
      expect(due(null).isOverdueAt(DateTime(2030)), isFalse);
    });
  });

  group('SmartTaskEvent · ledger', () {
    test('distingue la ruta directa auditada de un comando', () {
      final direct = SmartTaskEvent.fromJson({
        'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'task_id': '11111111-1111-4111-8111-111111111111',
        'event_type': 'completed',
        'task_version': 9,
        'payload': {'source': 'direct'},
        'created_at': '2026-08-26T16:00:00Z',
      });
      expect(direct.isDirectWrite, isTrue);
      expect(direct.eventType, 'completed');
      expect(direct.taskVersion, 9);
    });
  });

  group('TaskAssignmentPrincipal · directorio honesto', () {
    test('erp, portal y el trabajador sin cuenta son asignables', () {
      final erp = TaskAssignmentPrincipal.fromJson({
        'tenant_id': 't',
        'user_id': 'u1',
        'employee_id': 'e1',
        'display_name': 'Marcos Mecánico',
        'role': 'mechanic',
        'photo_url': null,
        'access': 'erp',
      });
      final portal = TaskAssignmentPrincipal.fromJson({
        'tenant_id': 't',
        'user_id': 'u2',
        'employee_id': 'e2',
        'display_name': 'Fernando Portal',
        'role': 'worker',
        'photo_url': null,
        'access': 'portal',
      });
      final none = TaskAssignmentPrincipal.fromJson({
        'tenant_id': 't',
        'user_id': null,
        'employee_id': 'e3',
        'display_name': 'Sofía SinCuenta',
        'role': 'worker',
        'photo_url': null,
        'access': 'none',
      });
      expect(erp.isAssignable, isTrue);
      expect(erp.initials, 'MM');
      expect(erp.assignmentContextLabel, 'Taller');
      expect(portal.isAssignable, isTrue);
      expect(portal.assignmentContextLabel, 'Recibe tareas en su portal');
      // Dueño, 2026-09-26: la tarea es de la persona; le llega sola cuando
      // tenga una cuenta.
      expect(none.isAssignable, isTrue);
      expect(none.assignmentKey, 'e3');
      expect(erp.assignmentKey, 'e1');
      expect(none.access, TaskPrincipalAccess.none);
      expect(
          none.assignmentContextLabel, 'Sin cuenta: la verá cuando tenga una');
    });

    test('traduce los roles ERP y nunca publica el código interno', () {
      String labelFor(String role) => TaskAssignmentPrincipal(
            tenantId: 't',
            userId: 'u',
            employeeId: 'e',
            displayName: 'Persona',
            role: role,
            photoUrl: null,
            access: TaskPrincipalAccess.erp,
          ).assignmentContextLabel;

      expect(labelFor('admin'), 'Administración');
      expect(labelFor('manager'), 'Gerencia');
      expect(labelFor('accountant'), 'Contabilidad');
      expect(labelFor('cashier'), 'Caja');
      expect(labelFor('unknown_backend_role'), 'Equipo ERP');
    });
  });

  group('WorkerTaskView · servicios marcables y nota del turno', () {
    test('lee la nota, quién la dejó y el plazo como fecha', () {
      final view = WorkerTaskView.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'title': 'Hacer el trabajo',
        'status': 'in_progress',
        'due_date': '2026-09-26T00:00:00+00:00',
        'job_items': [
          {
            'job_item_id': 'item-1',
            'item_name': 'Purga de frenos',
            'done_at': '2026-09-26T15:10:00Z',
            'done_by_name': 'Braulio Muñoz',
          },
        ],
        'handoff_note': 'Falta revisar el salto',
        'handoff_note_at': '2026-09-26T21:40:00Z',
        'handoff_note_by_name': 'Braulio Muñoz',
      });
      expect(view.handoffNote, 'Falta revisar el salto');
      expect(view.handoffNoteByName, 'Braulio Muñoz');
      expect(view.jobItems.single['job_item_id'], 'item-1');
      expect(view.isOverdueAt(DateTime(2026, 9, 26, 23, 30)), isFalse,
          reason: 'el día del plazo no está vencida');
      expect(view.isOverdueAt(DateTime(2026, 9, 27, 8)), isTrue);
    });
  });

  group('WorkerTaskView · proyección del portal', () {
    test('parsea multi-bici y servicios sin exigir precios', () {
      final view = WorkerTaskView.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'title': 'Mantención de motor',
        'status': 'pending',
        'priority': 'normal',
        'version': 3,
        'created_at': '2026-08-26T10:00:00Z',
        'creator_name': 'La Jefa',
        'assigner_name': 'La Manager',
        'job_number': 'PG-001234',
        'bike_labels': ['Trek 820', 'Giant Talon'],
        'job_items': [
          {
            'item_name': 'Mantención de motor',
            'item_instructions': 'Revisar dirección antes de reinstalar',
            'item_type': 'service',
          },
          {
            'item_name': 'Limpieza transmisión',
            'item_type': 'service',
            'invalidated': true,
          },
        ],
      });
      expect(view.bikeLabels, hasLength(2));
      expect(view.displayAssignerName, 'La Manager');
      expect(view.jobItems.last['invalidated'], isTrue);
      expect(view.jobItems.first['item_instructions'],
          'Revisar dirección antes de reinstalar');
      expect(view.awaitsAcknowledgement, isTrue);
      expect(view.jobItems.every((item) => !item.containsKey('unit_price')),
          isTrue);
    });

    test('sin assigned_by legacy, el creador es solo el fallback explícito',
        () {
      final view = WorkerTaskView.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'title': 'Legacy',
        'status': 'pending',
        'priority': 'normal',
        'version': 1,
        'created_at': '2026-08-26T10:00:00Z',
        'creator_name': 'La Jefa',
      });
      expect(view.assignerName, isNull);
      expect(view.displayAssignerName, 'La Jefa');
    });
  });

  group('Excepciones de comando', () {
    test('el solape transporta las tareas en conflicto', () {
      final exception = TaskOverlapException([
        {
          'task_id': 'x',
          'title': 'Ajuste',
          'assigned_to': 'u1',
          'job_item_ids': ['i1'],
        }
      ]);
      expect(exception.overlaps.single['title'], 'Ajuste');
    });
  });

  test('la consulta de trabajos desambigua el cliente real en PostgREST', () {
    expect(
      taskLinkableJobCustomerEmbed,
      'customers!mechanic_jobs_customer_id_fkey(name)',
    );
  });
}
