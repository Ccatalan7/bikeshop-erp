import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/services/hr_service.dart';

void main() {
  group('Employee retirement contract', () {
    test('accepts only a confirmed identity-bound retirement receipt', () {
      final result = EmployeeRetirementResult.fromJson({
        'success': true,
        'retired': true,
        'alreadyRetired': false,
        'employeeId': 'employee-1',
      });

      expect(result.employeeId, 'employee-1');
      expect(result.alreadyRetired, isFalse);

      for (final invalid in [
        null,
        <String, dynamic>{},
        {
          'success': true,
          'retired': false,
          'alreadyRetired': false,
          'employeeId': 'employee-1',
        },
        {
          'success': true,
          'retired': true,
          'alreadyRetired': 'false',
          'employeeId': 'employee-1',
        },
        {
          'success': true,
          'retired': true,
          'alreadyRetired': false,
          'employeeId': '',
        },
      ]) {
        expect(
          () => EmployeeRetirementResult.fromJson(invalid),
          throwsFormatException,
        );
      }
    });

    test('localizes stable backend failures without exposing raw evidence', () {
      final cases = {
        'employee_not_found detail=secret':
            'El trabajador ya no está disponible en este negocio.',
        'self_detach_forbidden raw-token':
            'No puedes desvincular tu propio registro laboral.',
        'staff_hierarchy_forbidden internal-role':
            'No tienes permisos para desvincular a este trabajador.',
        'employee_retirement_denied policy-name':
            'No tienes permisos para desvincular a este trabajador.',
        'unexpected backend table public.private_data':
            'No se pudo desvincular al trabajador. Inténtalo nuevamente.',
      };

      for (final entry in cases.entries) {
        final exception =
            EmployeeRetirementException.fromBackendEvidence(entry.key);
        expect(exception.message, entry.value);
        expect(exception.message, isNot(contains(entry.key)));
      }
    });

    test('all employee UI surfaces delegate to the canonical RPC', () {
      final service = File(
        'lib/modules/hr/services/hr_service.dart',
      ).readAsStringSync();
      final listPage = File(
        'lib/modules/hr/pages/employee_list_page.dart',
      ).readAsStringSync();
      final detailPage = File(
        'lib/modules/hr/pages/employee_detail_page.dart',
      ).readAsStringSync();
      final registry = File(
        'docs/architecture/canonical-ui-surfaces.md',
      ).readAsStringSync();
      final factoryResetPage = File(
        'lib/modules/settings/pages/factory_reset_page_new.dart',
      ).readAsStringSync();
      final router = File(
        'lib/shared/routes/app_router.dart',
      ).readAsStringSync();
      final listRetirementBlock = listPage.substring(
        listPage.indexOf('Future<void> _retireEmployee'),
        listPage.indexOf('  @override', listPage.indexOf('_retireEmployee')),
      );
      final detailRetirementBlock = detailPage.substring(
        detailPage.indexOf('Future<void> _retireEmployee'),
        detailPage.indexOf(
          'Future<void> _createWorkerPortalAccess',
          detailPage.indexOf('_retireEmployee'),
        ),
      );

      expect(service, contains("'retire_employee'"));
      expect(service, contains("'p_employee_id': id"));
      expect(service, isNot(contains(".from('employees').delete()")));

      expect(listPage, contains('retireEmployee(employee.id!)'));
      expect(listPage, contains('Desvincular trabajador'));
      expect(listPage, contains('EmployeeRetirementException'));
      expect(
        listRetirementBlock,
        isNot(contains("content: Text('Error: \$e')")),
      );
      expect(
        listPage,
        contains('status != EmployeeStatus.terminated'),
      );

      expect(detailPage, contains("Key('retire-employee-action')"));
      expect(detailPage, contains('retireEmployee(employeeId)'));
      expect(detailPage, contains('Registro laboral conservado'));
      expect(detailPage, contains('EmployeeRetirementException'));
      expect(
        detailRetirementBlock,
        isNot(contains('No se pudo desvincular al trabajador: \$error')),
      );

      expect(registry, contains('Workforce retirement and access closure'));
      expect(registry, contains('HRService.retireEmployee'));
      expect(registry, contains('factory reset rejects an HR purge'));

      expect(
        factoryResetPage,
        contains('Se desvinculan individualmente desde RR.HH.'),
      );
      expect(
        factoryResetPage,
        isNot(contains('_deleteEmployees = config.deleteEmployees')),
      );
      expect(factoryResetPage, isNot(contains('_deleteEmployees = true')));
      expect(router, contains('erp.FactoryResetPageNew()'));
      expect(router, isNot(contains('erp.FactoryResetPage()')));
    });
  });
}
