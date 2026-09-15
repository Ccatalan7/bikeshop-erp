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
    test('erp y portal son asignables; sin cuenta no lo es', () {
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
      expect(none.isAssignable, isFalse);
      expect(none.access, TaskPrincipalAccess.none);
      expect(none.assignmentContextLabel, 'Sin acceso');
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
