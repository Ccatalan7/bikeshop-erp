import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/services/whatsapp_service.dart';
import '../services/portal_phone_verification_service.dart';
import 'settings_figure.dart';

/// «Confirmar teléfono en el portal» en Configuración › WhatsApp: crea en
/// Meta la plantilla del código, la enciende cuando Meta la aprueba y dice
/// cuántos códigos salieron y se confirmaron en 30 días (20261105010000).
class PortalPhoneVerificationCard extends StatefulWidget {
  const PortalPhoneVerificationCard({super.key, this.service});

  /// Costura de pruebas; en la app es el servicio real.
  final PortalPhoneVerificationService? service;

  @override
  State<PortalPhoneVerificationCard> createState() =>
      _PortalPhoneVerificationCardState();
}

class _PortalPhoneVerificationCardState
    extends State<PortalPhoneVerificationCard> {
  late final PortalPhoneVerificationService _service =
      widget.service ?? PortalPhoneVerificationService();
  final DateFormat _dateFormat = DateFormat("d 'de' MMMM, HH:mm", 'es_CL');

  PortalPhoneVerificationState? _state;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await _service.load();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo leer la confirmación del teléfono: $error';
        _loading = false;
      });
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await _service.setEnabled(enabled);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createTemplate() async {
    setState(() => _creating = true);
    try {
      await _service.createTemplate();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = _state;

    return Card(
      key: const Key('portal-phone-verification-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.phonelink_lock_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Confirmar teléfono en el portal',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'El cliente que crea su cuenta en la tienda recibe un '
                        'código por WhatsApp para confirmar su teléfono. Al '
                        'escribirlo, su cuenta queda con su ficha del taller y '
                        've sus servicios, garantías y facturas.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (_error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Reintentar')),
                ],
              )
            else if (state != null) ...[
              _buildSwitch(state),
              const Divider(height: 28),
              _buildTemplateRow(theme, state),
              const SizedBox(height: 16),
              _buildActivity(theme, state),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(PortalPhoneVerificationState state) {
    final blocked = !state.enabled && !state.templateApproved;
    return SwitchListTile.adaptive(
      key: const Key('portal-phone-verification-switch'),
      contentPadding: EdgeInsets.zero,
      value: state.enabled,
      onChanged: _saving || blocked ? null : _setEnabled,
      title: const Text(
        'Ofrecer confirmar el teléfono',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        blocked
            ? 'Se puede encender cuando Meta apruebe la plantilla.'
            : state.enabled
                ? 'Encendido: el portal lo ofrece a quien todavía no ve su '
                    'ficha del taller.'
                : 'Apagado: el portal no lo ofrece.',
      ),
    );
  }

  Widget _buildTemplateRow(
      ThemeData theme, PortalPhoneVerificationState state) {
    final scheme = theme.colorScheme;
    final status = state.templateStatus;
    final (label, color) = switch (status?.status) {
      _ when state.templateCheckFailed => (
          'No se pudo consultar a Meta',
          scheme.error,
        ),
      null => ('Todavía no existe en Meta', scheme.onSurfaceVariant),
      'APPROVED' => ('Aprobada por Meta', scheme.primary),
      'PENDING' || 'IN_APPEAL' => ('En revisión de Meta', scheme.tertiary),
      'REJECTED' => (
          'Rechazada por Meta'
              '${status?.rejectedReason == null ? '' : ' (${status!.rejectedReason})'}',
          scheme.error,
        ),
      final other => ('Estado en Meta: $other', scheme.onSurfaceVariant),
    };

    return Row(
      children: [
        Icon(Icons.verified_outlined, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Plantilla '),
                const TextSpan(
                  text: WhatsAppService.phoneVerificationTemplateName,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ': $label'),
              ],
            ),
          ),
        ),
        if (status == null && !state.templateCheckFailed)
          FilledButton.tonal(
            key: const Key('portal-phone-verification-create'),
            onPressed: _creating ? null : _createTemplate,
            child: Text(_creating ? 'Enviando a Meta…' : 'Crear en Meta'),
          ),
      ],
    );
  }

  Widget _buildActivity(ThemeData theme, PortalPhoneVerificationState state) {
    final lastSent = state.lastSentAt;
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        SettingsFigure(
          value: '${state.sent30d}',
          label: 'códigos enviados en 30 días',
        ),
        SettingsFigure(
          value: '${state.confirmed30d}',
          label: 'teléfonos confirmados',
        ),
        if (state.failed30d > 0)
          SettingsFigure(
            value: '${state.failed30d}',
            label: 'no salieron',
          ),
        if (lastSent != null)
          Text(
            'Último: ${_dateFormat.format(lastSent)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
