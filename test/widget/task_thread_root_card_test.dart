import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/tasks/models/smart_task_job_item.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/widgets/task_thread_root_card.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  testWidgets(
      'the task is the visible root and keeps full workshop instructions',
      (tester) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final task = TaskModel(
      id: 'task-527',
      tenantId: 'tenant',
      title: 'Prueba de comentarios · PG-00527',
      description: 'Revisa el trabajo y responde dentro de este hilo.',
      createdBy: 'owner',
      assignedTo: 'claudio',
      creatorName: 'Viñabike',
      assigneeName: 'Claudio Catalán',
      linkedJobId: 'job-527',
      linkedJobNumber: 'PG-00527',
    );
    final links = [
      SmartTaskJobItem(
        id: 'link-1',
        taskId: 'task-527',
        jobItemId: 'item-1',
        jobId: 'job-527',
        jobBikeId: 'bike-1',
        itemName: 'Mecánica Media',
        itemType: 'service',
        jobNumber: 'PG-00527',
        bikeLabel: 'Totem 4423',
        itemInstructions:
            'REVISIÓN DE HORQUILLA/DIRECCIÓN + MANTENCIÓN SI ES NECESARIO',
        linkedAt: DateTime.utc(2026, 8, 27),
        invalidatedAt: null,
        contextChangedAt: null,
      ),
    ];
    var openedReplies = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: TaskThreadRootCard(
            task: task,
            links: links,
            replyCount: 2,
            jobNumber: 'PG-00527',
            onOpenTask: () {},
            onOpenReplies: () => openedReplies = true,
            onOpenJob: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('task-thread-root')), findsOneWidget);
    expect(find.text('TAREA'), findsOneWidget);
    expect(find.text('TRABAJO #PG-00527'), findsOneWidget);
    expect(find.textContaining('Mecánica Media · Totem 4423'), findsOneWidget);
    expect(
      find.text(
        'REVISIÓN DE HORQUILLA/DIRECCIÓN + MANTENCIÓN SI ES NECESARIO',
      ),
      findsOneWidget,
    );
    expect(find.text('2 respuestas'), findsOneWidget);
    expect(find.text('Abrir tarea'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('task-thread-open-replies')),
    );
    expect(openedReplies, isTrue);
  });
}
