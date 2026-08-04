import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_session_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';

/// A coherent ERP profile for one user and one taller.
CurrentUserProfile aiTestProfile({
  String userId = 'user-test',
  String tenantId = 'tenant-test',
  String role = 'owner',
  Map<String, bool> permissions = const {'manage_users': true},
}) {
  return CurrentUserProfile(
    userId: userId,
    email: '$userId@vinabike.cl',
    emailVerified: true,
    displayName: 'Persona de prueba',
    tenantId: tenantId,
    tenantName: 'Taller de prueba',
    tenantSubdomain: null,
    role: role,
    permissions: permissions,
    employeeLinkState: EmployeeLinkState.unlinked,
    employee: null,
  );
}

/// Builds a session and drives it to `ready` through the **real**
/// [AIAssistantSessionService.synchronize].
///
/// There is deliberately no shortcut constructor on the service: a test that
/// installs a ready session by fiat proves nothing about the path production
/// actually takes to get there, and that path — auth, tenant, profile, all
/// three agreeing — is the whole point of the boundary.
Future<AIAssistantSessionService> boundAiSession({
  String userId = 'user-test',
  String tenantId = 'tenant-test',
  String role = 'owner',
  Map<String, bool> permissions = const {'manage_users': true},
  AIAssistantService Function()? engineFactory,
}) async {
  final session = AIAssistantSessionService(engineFactory: engineFactory);
  await session.synchronize(
    authUserId: userId,
    profile: aiTestProfile(
      userId: userId,
      tenantId: tenantId,
      role: role,
      permissions: permissions,
    ),
    profileIsLoading: false,
    profileLoadIssue: null,
    cachedTenantId: tenantId,
    resolveTenantId: () async => tenantId,
  );
  return session;
}
