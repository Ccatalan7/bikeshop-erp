import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/task_form_dialog.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';

TaskModel _model({
  TaskKind kind = TaskKind.task,
  TaskVisibility visibility = TaskVisibility.team,
  TaskStatus status = TaskStatus.pending,
}) =>
    TaskModel(
      id: '11111111-1111-4111-8111-111111111111',
      tenantId: 't',
      title: 'Original',
      createdBy: 'creator',
      kind: kind,
      visibility: visibility,
      version: 5,
      status: status,
    );

TaskModel _build(TaskModel? editing) => buildTaskFormSaveModel(
      editing: editing,
      tenantId: 't',
      fallbackCreatorId: 'someone-else',
      title: 'Editada',
      description: '',
      priority: TaskPriority.high,
      // Lo que el dropdown legado habría enviado.
      selectedStatus: TaskStatus.completed,
      dueDate: null,
      assignedToId: 'assignee-from-dropdown',
      assigneeName: 'Marcos',
      linkedJobId: 'job-1',
      linkedJobNumber: 'PG-1',
      linkedPurchaseInvoiceId: null,
      linkedPurchaseInvoiceNumber: null,
      linkedSalesInvoiceId: null,
      linkedSalesInvoiceNumber: null,
      linkedCustomerId: null,
      linkedCustomerName: null,
      linkedSupplierId: null,
      linkedSupplierName: null,
      attachments: const [],
    );

void main() {
  test('editar una nota preserva tipo y no le inventa ciclo ni responsable',
      () {
    final saved = _build(_model(kind: TaskKind.note));
    expect(saved.kind, TaskKind.note,
        reason: 'el diálogo no puede degradar una nota a tarea');
    expect(saved.status, TaskStatus.pending,
        reason: 'una nota no toma el estado del dropdown de tareas');
    expect(saved.assignedTo, isNull,
        reason: 'una nota jamás sale del diálogo con responsable');
    expect(saved.version, 5);
    expect(saved.createdBy, 'creator');
  });

  test('editar una privada preserva visibilidad y sigue siendo personal', () {
    final saved = _build(_model(visibility: TaskVisibility.private));
    expect(saved.visibility, TaskVisibility.private,
        reason: 'el diálogo no puede exponer una privada como team');
    expect(saved.assignedTo, isNull);
    expect(saved.linkedJobId, isNull,
        reason: 'private implica sin pega (invariante de la base)');
    expect(saved.version, 5);
  });

  test('una tarea de equipo normal conserva el comportamiento previo', () {
    final saved = _build(_model());
    expect(saved.kind, TaskKind.task);
    expect(saved.visibility, TaskVisibility.team);
    expect(saved.status, TaskStatus.completed);
    expect(saved.assignedTo, 'assignee-from-dropdown');
    expect(saved.linkedJobId, 'job-1');
  });

  test(
      'editar una bloqueada conserva un valor válido sin ofrecer bloqueo nuevo',
      () {
    expect(
        taskFormStatusOptions(_model()), isNot(contains(TaskStatus.blocked)));
    expect(
      taskFormStatusOptions(_model(status: TaskStatus.blocked)),
      contains(TaskStatus.blocked),
      reason: 'el dropdown debe poder renderizar el estado que ya tiene',
    );
  });
}
