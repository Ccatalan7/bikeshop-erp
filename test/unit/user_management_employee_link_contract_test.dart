import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/user_management_service.dart';

void main() {
  Map<String, dynamic> employeeState({
    String linkState = 'available',
    String? erpUserId,
    bool workerAccessExists = false,
    bool workerAccessActive = false,
    String? workerUsername,
    String status = 'active',
    bool erpProfileActive = false,
    bool pendingInvitation = false,
  }) {
    return {
      'employeeId': 'employee-1',
      'employeeName': 'Ana Mecánica',
      'email': 'ana@example.com',
      'status': status,
      'erpUserId': erpUserId,
      'erpProfileActive': erpProfileActive,
      'pendingInvitation': pendingInvitation,
      'workerAccessExists': workerAccessExists,
      'workerAccessActive': workerAccessActive,
      'workerUsername': workerUsername,
      'linkState': linkState,
    };
  }

  test('employee access projection accepts only coherent link evidence', () {
    final available = EmployeeAccessState.fromJson(employeeState());
    expect(available.linkState, EmployeeErpLinkState.available);
    expect(available.canReceiveErpLink, isTrue);

    final pending = EmployeeAccessState.fromJson(
      employeeState(
        linkState: 'pending_invitation',
        pendingInvitation: true,
      ),
    );
    expect(pending.linkState, EmployeeErpLinkState.pendingInvitation);
    expect(pending.canReceiveErpLink, isFalse);

    final suspended = EmployeeAccessState.fromJson(
      employeeState(
        linkState: 'worker_suspended',
        workerAccessExists: true,
        workerUsername: 'ana.mecanica',
      ),
    );
    expect(suspended.linkState, EmployeeErpLinkState.workerSuspended);
    expect(suspended.canReceiveErpLink, isTrue);

    final activeWorker = EmployeeAccessState.fromJson(
      employeeState(
        linkState: 'worker_active',
        workerAccessExists: true,
        workerAccessActive: true,
        workerUsername: 'ana.mecanica',
      ),
    );
    expect(activeWorker.linkState, EmployeeErpLinkState.workerActive);
    expect(activeWorker.canReceiveErpLink, isFalse);

    final suspendedErpProfile = EmployeeAccessState.fromJson(
      employeeState(
        linkState: 'erp_linked',
        erpUserId: 'user-1',
        erpProfileActive: false,
      ),
    );
    expect(suspendedErpProfile.linkState, EmployeeErpLinkState.erpLinked);
    expect(suspendedErpProfile.canReceiveErpLink, isFalse);

    final contradictory = EmployeeAccessState.fromJson(
      employeeState(
        linkState: 'available',
        workerAccessExists: true,
        workerAccessActive: true,
        workerUsername: 'ana.mecanica',
      ),
    );
    expect(contradictory.linkState, EmployeeErpLinkState.inconsistent);
    expect(contradictory.canReceiveErpLink, isFalse);
  });

  test('employee access projection fails closed on malformed overview data',
      () {
    expect(
      () => parseEmployeeAccessStates('not-a-list'),
      throwsFormatException,
    );
    expect(
      () => parseEmployeeAccessStates([42]),
      throwsFormatException,
    );
    expect(
      () => EmployeeAccessState.fromJson({
        ...employeeState(),
        'workerAccessActive': 'yes',
      }),
      throwsFormatException,
    );
    expect(
      EmployeeAccessState.fromJson(
        employeeState(linkState: 'future_state'),
      ).linkState,
      EmployeeErpLinkState.inconsistent,
    );
  });

  test('link conflicts are localized without exposing backend text', () {
    expect(
      localizedUserManagementError('worker_access_conflict'),
      contains('app de trabajadores'),
    );
    expect(
      localizedUserManagementError('worker_identity_conflict'),
      contains('Worker Space'),
    );
    expect(
      localizedUserManagementError('employee_erp_link_conflict'),
      contains('otra cuenta ERP'),
    );
    expect(
      localizedUserManagementError('employee_erp_link_state_changed'),
      contains('consola se actualizará'),
    );
    expect(
      localizedUserManagementError('active_staff_email_requires_direct_link'),
      contains('Vincula directamente'),
    );
    expect(
      localizedUserManagementError('staff_membership_inactive'),
      contains('suspendido'),
    );
    expect(
      localizedUserManagementError('staff_identity_tenant_conflict'),
      contains('reconciliación'),
    );
    expect(
      localizedUserManagementError(
        'historical_employee_identity_conflict',
      ),
      contains('vínculo de trabajador'),
    );
    expect(
      localizedUserManagementError('identity_unavailable'),
      contains('vínculo de acceso incompatible'),
    );
    expect(
      localizedUserManagementError('unknown_code'),
      'No pudimos completar la gestión de acceso. Inténtalo nuevamente.',
    );
  });

  test('invitation identity projection fails closed on contradictory data', () {
    final customer = InvitationIdentityCheck.fromJson({
      'eligible': true,
      'status': 'available_existing_customer',
      'hasExistingAuthIdentity': true,
      'isExistingCustomer': true,
    });
    expect(customer.eligible, isTrue);
    expect(customer.isExistingCustomer, isTrue);
    expect(
      customer.status,
      InvitationIdentityStatus.availableExistingCustomer,
    );

    final conflict = InvitationIdentityCheck.fromJson({
      'eligible': false,
      'status': 'staff_identity_tenant_conflict',
      'hasExistingAuthIdentity': true,
      'isExistingCustomer': false,
    });
    expect(conflict.eligible, isFalse);
    expect(conflict.code, 'staff_identity_tenant_conflict');

    expect(
      () => InvitationIdentityCheck.fromJson({
        'eligible': true,
        'status': 'staff_identity_tenant_conflict',
        'hasExistingAuthIdentity': true,
        'isExistingCustomer': false,
      }),
      throwsFormatException,
    );
    expect(
      () => InvitationIdentityCheck.fromJson({
        'eligible': true,
        'status': 'future_status',
        'hasExistingAuthIdentity': true,
        'isExistingCustomer': false,
      }),
      throwsFormatException,
    );
  });

  test('link actions require the exact server acknowledgement', () {
    expect(
      () => validateEmployeeLinkResult(
        {
          'success': true,
          'linked': true,
          'userId': 'user-1',
          'employeeId': 'employee-1',
        },
        userId: 'user-1',
        employeeId: 'employee-1',
        linked: true,
      ),
      returnsNormally,
    );
    expect(
      () => validateEmployeeLinkResult(
        {
          'success': true,
          'linked': true,
          'userId': 'another-user',
          'employeeId': 'employee-1',
        },
        userId: 'user-1',
        employeeId: 'employee-1',
        linked: true,
      ),
      throwsFormatException,
    );
    expect(
      () => validateEmployeeLinkResult(
        {
          'success': true,
          'linked': true,
          'userId': 'user-1',
          'employeeId': 'employee-1',
        },
        userId: 'user-1',
        employeeId: 'employee-1',
        linked: false,
      ),
      throwsFormatException,
    );
  });

  test('employee-linking action policy fails closed in unsafe states', () {
    expect(
      canChangeEmployeeLink(
        actionRunning: false,
        employeeLinkNeedsReview: false,
        profileActive: true,
        hasHealthyEmployeeLink: false,
      ),
      isTrue,
      reason: 'An active unlinked profile may choose an employee explicitly.',
    );
    expect(
      canChangeEmployeeLink(
        actionRunning: false,
        employeeLinkNeedsReview: false,
        profileActive: false,
        hasHealthyEmployeeLink: true,
      ),
      isTrue,
      reason: 'A suspended profile may explicitly unlink its healthy link.',
    );
    expect(
      canChangeEmployeeLink(
        actionRunning: false,
        employeeLinkNeedsReview: false,
        profileActive: false,
        hasHealthyEmployeeLink: false,
      ),
      isFalse,
      reason: 'A suspended unlinked profile must be restored first.',
    );
    expect(
      canChangeEmployeeLink(
        actionRunning: false,
        employeeLinkNeedsReview: true,
        profileActive: true,
        hasHealthyEmployeeLink: false,
      ),
      isFalse,
      reason: 'Contradictory employee evidence must block link changes.',
    );
    expect(
      canChangeEmployeeLink(
        actionRunning: true,
        employeeLinkNeedsReview: false,
        profileActive: true,
        hasHealthyEmployeeLink: false,
      ),
      isFalse,
      reason: 'A running mutation must block a second link action.',
    );
  });

  test('user console honors the employee-linking action contract', () {
    final page = File(
      'lib/modules/settings/pages/user_management_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/shared/services/user_management_service.dart',
    ).readAsStringSync();
    final surfaces = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(service, contains("'action': 'link_internal_user_employee'"));
    expect(
      service,
      contains("'action': 'check_internal_invitation_identity'"),
    );
    expect(service, contains("'action': 'unlink_internal_user_employee'"));
    expect(service, contains("'userId': userId"));
    expect(service, contains("'employeeId': employeeId"));
    expect(page, contains("overview['employeeAccessStates']"));
    expect(page, contains('employeeId: employeeId'));
    expect(page, contains('var selectedEmployeeKey = _noEmployeeSelection'));
    expect(page, contains('String? selectedEmployeeId;'));
    expect(page, contains('_applyEmployeePrefill('));
    expect(page, contains('previousEmailPrefill'));
    expect(page, contains('_canSelectEmployee(employee)'));
    expect(page, contains('_confirmLinkEmployee('));
    expect(page, contains('_confirmUnlinkEmployee('));
    expect(page, contains('Confirma que ambas identidades'));
    expect(page, contains('canChangeEmployeeLink('));
    expect(
      page,
      contains('Otro administrador autorizado debe cambiar tu rol o permisos'),
    );
    expect(page, isNot(contains('selectedEmployee = activeEmployees.first')));
    expect(
      surfaces,
      contains('selection is always explicit and optional'),
    );
    expect(
      surfaces,
      contains('never infer a match from equal names or emails'),
    );
  });
}
