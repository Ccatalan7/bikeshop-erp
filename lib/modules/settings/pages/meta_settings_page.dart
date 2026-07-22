import 'package:flutter/material.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../services/meta_settings_service.dart';

class MetaSettingsPage extends StatefulWidget {
  final MetaSettingsGateway? service;

  const MetaSettingsPage({super.key, this.service});

  @override
  State<MetaSettingsPage> createState() => _MetaSettingsPageState();
}

class _MetaSettingsPageState extends State<MetaSettingsPage> {
  late final MetaSettingsGateway _service;
  MetaSettingsSnapshot? _snapshot;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isLaunchingAuthorization = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? MetaSettingsService();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snapshot = await _service.loadSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error is MetaSettingsException
            ? error.message
            : 'No se pudo cargar el estado de Instagram y Messenger.';
        _isLoading = false;
      });
    }
  }

  Future<void> _requestAuthorization() async {
    final snapshot = _snapshot;
    if (snapshot == null ||
        !snapshot.canManageAuthorization ||
        _isLaunchingAuthorization) {
      return;
    }

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Continuar en Meta'),
        content: const Text(
          'Se abrirá Meta en el navegador externo. La conexión no cambia '
          'hasta que revises y confirmes allí las cuentas y permisos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abrir Meta'),
          ),
        ],
      ),
    );
    if (shouldOpen != true || !mounted) {
      return;
    }

    setState(() => _isLaunchingAuthorization = true);
    try {
      await _service.launchAuthorization(tenantId: snapshot.tenantId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Meta se abrió en el navegador. Completa la autorización allí y '
            'luego vuelve para actualizar el estado.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is MetaSettingsException
          ? error.message
          : 'No se pudo abrir la autorización de Meta.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLaunchingAuthorization = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instagram y Messenger'),
        actions: [
          IconButton(
            key: const ValueKey('meta-refresh'),
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar estado',
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return _LoadError(message: errorMessage, onRetry: _load);
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return _LoadError(
        message: 'No se pudo cargar el estado de Instagram y Messenger.',
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIntroduction(context),
                  const SizedBox(height: 20),
                  _buildAuthorizationCard(context, snapshot),
                  const SizedBox(height: 20),
                  Text(
                    'Canales registrados',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'El estado se consulta desde el ERP; las credenciales '
                    'permanecen protegidas en el servidor. Los permisos '
                    'mostrados son concesiones actuales informadas por Meta.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.channels.isEmpty)
                    _buildEmptyChannels(context)
                  else
                    ...snapshot.channels.map(
                      (channel) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MetaChannelCard(channel: channel),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroduction(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conexión de canales Meta',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Autoriza las páginas de Facebook y cuentas profesionales de '
            'Instagram que usarán la mensajería del ERP. La autorización '
            'continúa en Meta y siempre requiere tu confirmación allí.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorizationCard(
    BuildContext context,
    MetaSettingsSnapshot snapshot,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasChannels = snapshot.channels.isNotEmpty;
    final canManage = snapshot.canManageAuthorization;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final action = FilledButton.icon(
            key: const ValueKey('meta-connect'),
            onPressed: canManage && !_isLaunchingAuthorization
                ? _requestAuthorization
                : null,
            icon: _isLaunchingAuthorization
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new, size: 18),
            label: Text(
              _isLaunchingAuthorization
                  ? 'Abriendo…'
                  : hasChannels
                      ? 'Reautorizar en Meta'
                      : 'Conectar Meta',
            ),
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasChannels
                    ? '${snapshot.channels.length} canal(es) registrado(s)'
                    : 'Sin canales registrados',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                !snapshot.isProfileActive
                    ? 'Tu acceso de trabajador está inactivo. Puedes revisar '
                        'el estado, pero no autorizar cuentas.'
                    : canManage
                        ? 'Después de autorizar en Meta, vuelve a esta página y '
                            'usa Actualizar estado.'
                        : 'Puedes revisar y actualizar el estado. Solo '
                            'administradores y managers pueden conectar o '
                            'reautorizar cuentas.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          );

          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 14),
                action,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyChannels(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Todavía no hay una página de Facebook ni una cuenta profesional de '
        'Instagram conectada a este negocio.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _MetaChannelCard extends StatelessWidget {
  final MetaChannelStatus channel;

  const _MetaChannelCard({required this.channel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = _resolveStatus(channel, DateTime.now().toUtc());

    return Semantics(
      label: '${channel.provider.label}: ${status.label}',
      container: true,
      child: Container(
        key: ValueKey('meta-channel-${channel.id}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                channel.provider == MetaChannelProvider.instagram
                    ? Icons.camera_alt_outlined
                    : Icons.forum_outlined,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        channel.provider.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _StatusLabel(status: status),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    channel.accountLabel,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 18,
                    runSpacing: 5,
                    children: [
                      _DetailText(
                        label: 'Suscripción',
                        value: channel.subscribedAt == null
                            ? 'Pendiente'
                            : _formatDate(channel.subscribedAt!),
                      ),
                      _DetailText(
                        label: 'Autorización',
                        value: channel.authorizationExpiresAt == null
                            ? 'Sin vencimiento informado'
                            : 'vence ${_formatDate(channel.authorizationExpiresAt!)}',
                      ),
                      _DetailText(
                        label: 'Permisos concedidos por Meta',
                        value: channel.grantedPermissions.isEmpty
                            ? 'Ninguno confirmado'
                            : channel.grantedPermissions.join(', '),
                      ),
                      if (channel.missingRequiredPermissions.isNotEmpty)
                        _DetailText(
                          label: 'Permisos faltantes',
                          value: channel.missingRequiredPermissions.join(', '),
                        ),
                      if (channel.updatedAt != null)
                        _DetailText(
                          label: 'Actualizado',
                          value: _formatDate(channel.updatedAt!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailText extends StatelessWidget {
  final String label;
  final String value;

  const _DetailText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final _ChannelStatusPresentation status;

  const _StatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status.kind) {
      _ChannelStatusKind.connected => colorScheme.tertiary,
      _ChannelStatusKind.pending => colorScheme.secondary,
      _ChannelStatusKind.permissionsMissing => colorScheme.secondary,
      _ChannelStatusKind.inactive => colorScheme.onSurfaceVariant,
      _ChannelStatusKind.expired => colorScheme.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.38)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _LoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ChannelStatusKind {
  connected,
  pending,
  permissionsMissing,
  inactive,
  expired,
}

class _ChannelStatusPresentation {
  final _ChannelStatusKind kind;
  final String label;

  const _ChannelStatusPresentation(this.kind, this.label);
}

_ChannelStatusPresentation _resolveStatus(
  MetaChannelStatus channel,
  DateTime now,
) {
  if (!channel.isActive) {
    return const _ChannelStatusPresentation(
      _ChannelStatusKind.inactive,
      'Inactivo',
    );
  }
  if (channel.authorizationExpiredAt(now)) {
    return const _ChannelStatusPresentation(
      _ChannelStatusKind.expired,
      'Autorización vencida',
    );
  }
  if (channel.subscribedAt == null) {
    return const _ChannelStatusPresentation(
      _ChannelStatusKind.pending,
      'Suscripción pendiente',
    );
  }
  if (channel.missingRequiredPermissions.isNotEmpty) {
    return const _ChannelStatusPresentation(
      _ChannelStatusKind.permissionsMissing,
      'Permisos incompletos',
    );
  }
  return const _ChannelStatusPresentation(
    _ChannelStatusKind.connected,
    'Conectado',
  );
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
