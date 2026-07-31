import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/current_user_profile.dart';
import '../services/auth_service.dart';
import '../services/current_user_profile_service.dart';
import '../services/tenant_service.dart';
import 'main_layout.dart';

enum ErpAuthorizationArea {
  hrManagement,
  payroll,
}

enum ErpAuthorizationDecision {
  resolving,
  unavailable,
  denied,
  allowed,
}

@visibleForTesting
ErpAuthorizationDecision evaluateErpAuthorization({
  required ErpAuthorizationArea area,
  required CurrentUserProfile? profile,
  required bool isLoading,
  required CurrentUserProfileLoadIssue? loadIssue,
}) {
  if (isLoading) return ErpAuthorizationDecision.resolving;
  if (profile == null || loadIssue != null) {
    return ErpAuthorizationDecision.unavailable;
  }

  final allowed = switch (area) {
    ErpAuthorizationArea.hrManagement => profile.canManageUsers,
    ErpAuthorizationArea.payroll => profile.canAccessAccounting,
  };
  return allowed
      ? ErpAuthorizationDecision.allowed
      : ErpAuthorizationDecision.denied;
}

typedef ErpAuthorizationBlockedBuilder = Widget Function(
  BuildContext context,
  ErpAuthorizationDecision decision,
);

/// Prevents protected route bodies from being constructed before authority is
/// resolved from the canonical current-user profile.
class ErpAuthorizationGate extends StatelessWidget {
  const ErpAuthorizationGate({
    super.key,
    required this.area,
    required this.authorizedBuilder,
    this.blockedBuilder,
  });

  final ErpAuthorizationArea area;
  final WidgetBuilder authorizedBuilder;
  final ErpAuthorizationBlockedBuilder? blockedBuilder;

  @override
  Widget build(BuildContext context) {
    final profileService = context.watch<CurrentUserProfileService>();
    final decision = evaluateErpAuthorization(
      area: area,
      profile: profileService.profile,
      isLoading: profileService.isLoading,
      loadIssue: profileService.loadIssue,
    );
    if (decision == ErpAuthorizationDecision.allowed) {
      return authorizedBuilder(context);
    }
    return blockedBuilder?.call(context, decision) ??
        _ErpAuthorizationStatus(
          area: area,
          decision: decision,
        );
  }
}

class _ErpAuthorizationStatus extends StatelessWidget {
  const _ErpAuthorizationStatus({
    required this.area,
    required this.decision,
  });

  final ErpAuthorizationArea area;
  final ErpAuthorizationDecision decision;

  String get _areaTitle => switch (area) {
        ErpAuthorizationArea.hrManagement => 'Recursos humanos',
        ErpAuthorizationArea.payroll => 'Nóminas',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolving = decision == ErpAuthorizationDecision.resolving;
    final unavailable = decision == ErpAuthorizationDecision.unavailable;
    final denied = decision == ErpAuthorizationDecision.denied;
    final title = resolving
        ? 'Verificando acceso'
        : unavailable
            ? 'No pudimos verificar tu acceso'
            : 'No tienes acceso a $_areaTitle';
    final description = resolving
        ? 'Estamos comprobando los permisos de esta sesión.'
        : unavailable
            ? 'La autorización no está disponible. No mostraremos datos '
                'protegidos hasta poder validarla.'
            : area == ErpAuthorizationArea.hrManagement
                ? 'Un administrador puede otorgarte el permiso para gestionar '
                    'trabajadores.'
                : 'Un administrador puede otorgarte acceso contable.';

    return MainLayout(
      title: _areaTitle,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (resolving)
                  const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Icon(
                    denied ? Icons.lock_outline : Icons.cloud_off_outlined,
                    size: 36,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(height: 20),
                Text(
                  title,
                  key: ValueKey(
                    'erp-authorization-${decision.name}',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (unavailable) ...[
                  const SizedBox(height: 24),
                  FilledButton.tonalIcon(
                    onPressed: () => _retry(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ] else if (denied) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    // return-contract: explicit-destination
                    onPressed: () => context.push('/profile'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Revisar mi perfil'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry(BuildContext context) async {
    final profileService = context.read<CurrentUserProfileService>();
    final authService = context.read<AuthService>();
    final tenantService = context.read<TenantService>();
    final user = authService.currentUser;
    await profileService.synchronize(
      identity: user == null ? null : CurrentUserIdentity.fromUser(user),
      resolveTenantId: tenantService.getTenantId,
      force: true,
    );
  }
}
