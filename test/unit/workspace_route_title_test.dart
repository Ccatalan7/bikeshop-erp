import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  group('getRouteTitle workshop routes', () {
    test('recognizes the canonical job detail route and ignores its query', () {
      expect(
        getRouteTitle('/taller/pegas/job-123?from=chat'),
        'Detalle Trabajo',
      );
    });

    test('keeps the former singular job detail spelling compatible', () {
      expect(getRouteTitle('/taller/pega/job-123'), 'Detalle Trabajo');
    });

    test('recognizes canonical and legacy edit spellings', () {
      expect(getRouteTitle('/taller/pegas/job-123/edit'), 'Editar Trabajo');
      expect(getRouteTitle('/taller/pega/job-123/editar'), 'Editar Trabajo');
    });
  });
}
