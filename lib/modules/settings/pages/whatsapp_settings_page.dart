import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../services/whatsapp_settings_service.dart';

class WhatsAppSettingsPage extends StatefulWidget {
  final bool embedded;

  const WhatsAppSettingsPage({super.key, this.embedded = false});

  @override
  State<WhatsAppSettingsPage> createState() => _WhatsAppSettingsPageState();
}

class _WhatsAppSettingsPageState extends State<WhatsAppSettingsPage> {
  final WhatsAppSettingsService _service = WhatsAppSettingsService();
  final NumberFormat _usdFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'US\4',
    decimalDigits: 2,
  );
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm', 'es_CL');
  final DateFormat _shortFormat = DateFormat('dd/MM HH:mm', 'es_CL');

  WhatsAppSettingsSnapshot? _snapshot;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final snapshot = await _service.loadSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp'),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'No se pudo cargar la configuración de WhatsApp',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildEstimateNotice(context),
          const SizedBox(height: 16),
          _buildSummaryCards(context, snapshot),
          const SizedBox(height: 16),
          _buildTemplateCard(context, snapshot),
          const SizedBox(height: 16),
          _buildChannelSection(context, snapshot),
          const SizedBox(height: 16),
          _buildBillingWindowsSection(context, snapshot),
          const SizedBox(height: 16),
          _buildDiagnosticsSection(context, snapshot),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEstimateNotice(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB7D7FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF0E5AA7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimación de cobro Meta',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0E3E73),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Esto no es la factura oficial de Meta. La pantalla estima ventanas cobrables abiertas por plantillas enviadas desde el ERP usando la tarifa de referencia utility ~ US\4 0.04 por conversación.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF214D79),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(
    BuildContext context,
    WhatsAppSettingsSnapshot snapshot,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          title: 'Costo estimado 30d',
          value: _usdFormat.format(snapshot.estimatedCost30dUsd),
          subtitle: 'Plantillas utility aceptadas',
          icon: Icons.attach_money,
          accent: const Color(0xFF14532D),
          background: const Color(0xFFECFDF3),
        ),
        _MetricCard(
          title: 'Ventanas cobrables 30d',
          value: '${snapshot.billableWindows30d.length}',
          subtitle: 'Aperturas estimadas por template',
          icon: Icons.forum_outlined,
          accent: const Color(0xFF7C2D12),
          background: const Color(0xFFFFF7ED),
        ),
        _MetricCard(
          title: 'Ventanas abiertas ahora',
          value: '${snapshot.openBillableWindows}',
          subtitle: 'Cobrables aún vigentes',
          icon: Icons.schedule,
          accent: const Color(0xFF1D4ED8),
          background: const Color(0xFFEFF6FF),
        ),
        _MetricCard(
          title: 'Ventanas gratis 24h',
          value: '${snapshot.activeCustomerServiceWindows}',
          subtitle: 'Con último inbound del cliente',
          icon: Icons.mark_chat_read_outlined,
          accent: const Color(0xFF065F46),
          background: const Color(0xFFECFDF5),
        ),
      ],
    );
  }

  Widget _buildTemplateCard(
    BuildContext context,
    WhatsAppSettingsSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final firstContactCount =
        snapshot.templateMessagesByName['seguimiento_servicio_bicicleta'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFDCFCE7),
                  child: Icon(
                    Icons.campaign_outlined,
                    color: Colors.green[800],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Template de primer contacto',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'seguimiento_servicio_bicicleta · Utility · es_CL',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InlineStat(
                  label: 'Envíos 30d',
                  value: '$firstContactCount',
                ),
                _InlineStat(
                  label: 'Ventanas hoy',
                  value: '${snapshot.billableWindowsToday}',
                ),
                _InlineStat(
                  label: 'Último envío',
                  value: snapshot.lastTemplateAt != null
                      ? _dateTimeFormat
                          .format(snapshot.lastTemplateAt!.toLocal())
                      : 'Sin envíos',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Si ese template ya fue aprobado y se envió fuera de una ventana previa de 24h para ese mismo contacto, esta pantalla lo cuenta como una apertura probablemente cobrable.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelSection(
    BuildContext context,
    WhatsAppSettingsSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Canales y Salud',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (snapshot.channels.isEmpty)
              Text(
                'No hay canales de WhatsApp configurados para este tenant.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ...snapshot.channels.map((channel) {
                final chipColor = channel.isActive
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF3F4F6);
                final chipTextColor = channel.isActive
                    ? const Color(0xFF166534)
                    : const Color(0xFF4B5563);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.displayName?.isNotEmpty == true
                                  ? channel.displayName!
                                  : 'Canal sin nombre',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: chipColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              channel.isActive ? 'Activo' : 'Inactivo',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: chipTextColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildDetailLine(
                        context,
                        'Número',
                        channel.displayPhoneNumber ?? 'No configurado',
                      ),
                      _buildDetailLine(
                        context,
                        'Phone Number ID',
                        channel.phoneNumberId,
                      ),
                      _buildDetailLine(
                        context,
                        'Business Account',
                        channel.businessAccountId ?? 'No configurada',
                      ),
                      _buildDetailLine(
                        context,
                        'Conversaciones vinculadas',
                        '${channel.trackedConversations}',
                      ),
                      _buildDetailLine(
                        context,
                        'Último webhook',
                        _formatDateTime(channel.lastWebhookAt),
                      ),
                      _buildDetailLine(
                        context,
                        'Último inbound',
                        _formatDateTime(channel.lastInboundAt),
                      ),
                      _buildDetailLine(
                        context,
                        'Último outbound',
                        _formatDateTime(channel.lastOutboundAt),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingWindowsSection(
    BuildContext context,
    WhatsAppSettingsSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ventanas cobrables estimadas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cada fila representa una apertura estimada de conversación business-initiated por template. Si mandaste un template aprobado y no había una ventana previa para ese contacto/categoría, aquí debería aparecer.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (snapshot.billableWindows30d.isEmpty)
              Text(
                'No hay ventanas cobrables estimadas en los últimos 30 días.',
                style: theme.textTheme.bodyMedium,
              )
            else
              ...snapshot.billableWindows30d.take(12).map((window) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: window.isActive
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: window.isActive
                          ? const Color(0xFFBBF7D0)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              window.contactName?.isNotEmpty == true
                                  ? window.contactName!
                                  : window.phoneNumber,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _usdFormat.format(window.estimatedCostUsd),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF14532D),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${window.templateName} · ${window.category}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Abierta: ${_shortFormat.format(window.openedAt.toLocal())} · Expira: ${_shortFormat.format(window.expiresAt.toLocal())}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsSection(
    BuildContext context,
    WhatsAppSettingsSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actividad y Diagnóstico',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InlineStat(
                  label: 'Webhooks 24h',
                  value: '${snapshot.webhookEvents24h}',
                ),
                _InlineStat(
                  label: 'Statuses 24h',
                  value: '${snapshot.statusEvents24h}',
                ),
                _InlineStat(
                  label: 'Outbounds 30d',
                  value: '${snapshot.outboundMessages30d}',
                ),
                _InlineStat(
                  label: 'Delivered 30d',
                  value: '${snapshot.deliveredMessages30d}',
                ),
                _InlineStat(
                  label: 'Read 30d',
                  value: '${snapshot.readMessages30d}',
                ),
                _InlineStat(
                  label: 'Failed 30d',
                  value: '${snapshot.failedMessages30d}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailLine(
              context,
              'Último webhook global',
              _formatDateTime(snapshot.lastWebhookAt),
            ),
            _buildDetailLine(
              context,
              'Último outbound global',
              _formatDateTime(snapshot.lastOutboundAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailLine(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Sin datos';
    return _dateTimeFormat.format(value.toLocal());
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color background;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String label;
  final String value;

  const _InlineStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
