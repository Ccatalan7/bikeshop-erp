import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Las tareas de un trabajo las crea una persona; la descripción del catálogo
// es la instrucción de la línea (20260929040000). La base rechaza tareas nuevas
// copiadas de la descripción; esta guardia fija el lado de la app.
void main() {
  final service = File(
    'lib/modules/bikeshop/services/smart_task_service.dart',
  ).readAsStringSync();
  final tab = File(
    'lib/modules/bikeshop/widgets/tasks_tab_view.dart',
  ).readAsStringSync();

  String body(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNonNegative, reason: 'falta $signature');
    return source.substring(start, source.indexOf('\n  }\n', start));
  }

  test('la app no crea tareas desde una descripción', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('parsedFromDescription: true') ||
          source.contains("'parsed_from_description': true") ||
          source.contains('generateAutoTasksFromDescription')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('las tareas que se leen son las accionables de este taller', () {
    final read = body(service, 'Future<List<MechanicJobTask>> getTasksForJob(');
    expect(read, contains(".eq('tenant_id', tenantId)"));
    expect(read, contains(".eq('parsed_from_description', false)"));
    // La lista, el avance y el estado de cada línea salen de esa lectura.
    expect(
      body(service, 'Future<TaskProgress> calculateProgress('),
      contains('getTasksForJob(jobId)'),
    );
    expect(
      body(
        service,
        'Future<Map<String, List<MechanicJobTask>>> getTasksGroupedByParent(',
      ),
      contains('getTasksForJob(jobId)'),
    );
  });

  test('cada línea muestra su instrucción aparte de sus tareas', () {
    final group = body(tab, 'Widget _buildItemGroup(');
    expect(group, contains('JobLineInstructions('));
    expect(group, contains('notes: item.notes'));
    final descriptions =
        body(tab, 'Future<Map<String, String>> _fetchCatalogDescriptions(');
    expect(descriptions, contains(".eq('tenant_id', tenantId)"));
    expect(tab, isNot(contains('parsedFromDescription &&')));
  });

  test('en teléfono, las tareas y su instrucción se abren desde «Más»', () {
    final page = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    expect(
      page,
      contains(
          '_MobileWorkshopSurface.tasks => _buildMobileTasksWorkspace(job)'),
    );
    expect(page, contains("'Tareas e instrucciones'"));
    expect(
      page,
      contains('_openMobileInlineSurface(job, _MobileWorkshopSurface.tasks);'),
    );
    final workspace = body(page, 'Widget _buildMobileTasksWorkspace(');
    expect(workspace, contains('TasksTabView('));
    expect(workspace, contains('onPressed: _closeMobileInlineSurface'));
  });

  test('una tarea suelta se ve aunque el trabajo no tenga líneas', () {
    final list = body(tab, 'Widget _buildTaskList(');
    expect(list, contains('if (_items.isEmpty && standalone.isEmpty)'));
  });

  test('una línea sin tareas no se pinta como terminada', () {
    expect(tab, contains('isAllCompleted: total > 0 && completed == total'));
    expect(tab,
        isNot(contains('_progress!.completedTasks == _progress!.totalTasks')));
    expect(
      service,
      contains(
          'bool get isDone => totalTasks > 0 && completedTasks == totalTasks;'),
    );
  });
}
