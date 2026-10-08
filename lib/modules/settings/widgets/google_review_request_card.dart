import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/services/whatsapp_service.dart';
import '../services/google_review_request_service.dart';

/// «Reseñas de Google» en Configuración › WhatsApp: enciende el pedido
/// automático de reseña después de cada entrega, muestra si Meta aprobó la
/// plantilla y cuántos pedidos salieron en 30 días y por qué se omitieron
/// los demás.
class GoogleReviewRequestCard extends StatefulWidget {
  const GoogleReviewRequestCard({super.key, this.service});

  /// Costura de pruebas; en la app es el servicio real.
  final GoogleReviewRequestService? service;

  @override
  State<GoogleReviewRequestCard> createState() =>
      _GoogleReviewRequestCardState();
}

class _GoogleReviewRequestCardState extends State<GoogleReviewRequestCard> {
  late final GoogleReviewRequestService _service =
      widget.service ?? GoogleReviewRequestService();
  final DateFormat _dateFormat = DateFormat("d 'de' MMMM, HH:mm", 'es_CL');

  GoogleReviewRequestState? _state;
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
        _error = 'No se pudo leer el pedido de reseñas: $error';
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
      key: const Key('google-review-request-card'),
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
                    Icons.star_rate_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reseñas de Google',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tres horas después de entregar una bicicleta, el '
                        'cliente recibe por WhatsApp el enlace para dejar su '
                        'reseña. Sale entre las 10:00 y las 20:00, una vez al '
                        'año por cliente, a nombre de quien entregó la bici.',
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
              _buildSwitch(theme, state),
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

  Widget _buildSwitch(ThemeData theme, GoogleReviewRequestState state) {
    final canTurnOn = state.templateApproved;
    final blocked = !state.enabled && !canTurnOn;
    return SwitchListTile.adaptive(
      key: const Key('google-review-request-switch'),
      contentPadding: EdgeInsets.zero,
      value: state.enabled,
      onChanged: _saving || blocked ? null : _setEnabled,
      title: const Text(
        'Pedir reseña al entregar',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        blocked
            ? 'Se puede encender cuando Meta apruebe la plantilla.'
            : state.enabled
                ? 'Encendido: cada entrega con celular recibe el pedido.'
                : 'Apagado: no se envía ningún pedido.',
      ),
    );
  }

  Widget _buildTemplateRow(ThemeData theme, GoogleReviewRequestState state) {
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
    final category = status?.category;

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
                  text: WhatsAppService.reviewRequestTemplateName,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ': $label'),
                if (category != null)
                  TextSpan(
                    text: category == 'MARKETING'
                        ? ' · Meta la cobra como marketing'
                        : ' · Meta la cobra como servicio',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        if (status == null && !state.templateCheckFailed)
          FilledButton.tonal(
            key: const Key('google-review-request-create'),
            onPressed: _creating ? null : _createTemplate,
            child: Text(_creating ? 'Enviando a Meta…' : 'Crear en Meta'),
          ),
      ],
    );
  }

  Widget _buildActivity(ThemeData theme, GoogleReviewRequestState state) {
    final scheme = theme.colorScheme;
    final lastSent = state.lastSentAt;
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        _Figure(
          value: '${state.sent30d}',
          label: 'pedidos enviados en 30 días',
        ),
        _Figure(
          value: '${state.skipped30d}',
          label: state.skippedByReason.isEmpty
              ? 'omitidos'
              : 'omitidos: ${state.skippedByReason.map((entry) => '${entry.key} (${entry.value})').join(', ')}',
        ),
        if (lastSent != null)
          Text(
            'Último: ${_dateFormat.format(lastSent)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
