import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/user_management_navigation.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  test('selection request round-trips without becoming workspace identity', () {
    final route = UserManagementNavigation.destination(
      audience: UserManagementAudience.customers,
      target: UserManagementTarget.customer,
      targetId: 'customer-42',
      requestId: 'request-1',
    );

    final uri = Uri.parse(route);
    final request = UserManagementOpenRequest.tryParse(
      uri.queryParameters['openRequest'],
    );

    expect(request?.audience, UserManagementAudience.customers);
    expect(request?.target, UserManagementTarget.customer);
    expect(request?.targetId, 'customer-42');
    expect(workspaceRouteIdentity(route), UserManagementNavigation.route);
  });

  test('malformed or incomplete requests fail closed', () {
    expect(UserManagementOpenRequest.tryParse('not-json'), isNull);
    expect(
      UserManagementOpenRequest.tryParse(
        '{"v":1,"audience":"customers","target":"customer"}',
      ),
      isNull,
    );
    expect(
      UserManagementOpenRequest.tryParse(
        '{"v":1,"audience":"unknown"}',
      ),
      isNull,
    );
  });
}
