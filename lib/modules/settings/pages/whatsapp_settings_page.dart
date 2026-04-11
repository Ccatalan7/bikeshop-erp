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
  final TextEditingController _templateNameController = TextEditingController();
  final TextEditingController _templateLanguageController =
      TextEditingController();
  final TextEditingController _utilityRateController = TextEditingController();

  final NumberFormat _usdFormat = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'US\$',
    decimalDigits: 2,
  );
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm', 'es_CL');
  final DateFormat _shortFormat = DateFormat('dd/MM HH:mm', 'es_CL');

  WhatsAppSettingsPanelData? _panelData;
  String? _error;
  bool _isLoading = true;
  bool _isSavingPreferences = false;
  final Set<String> _channelUpdates = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _templateNameController.dispose();
    _templateLanguageController.dispose();
    _utilityRateController.dispose();
    super.dispose();
  }

  bool get _hasValidRate {
    final parsed = double.tryParse(
        _utilityRateController.text.trim().replaceAll(',', '.'));
    return parsed != null && parsed >= 0;
  }

  bool get _hasUnsavedChanges {
    final panelData = _panelData;
    if (panelData == null) {
      return false;
    }

    final preferences = panelData.preferences;
    final currentRate = double.tryParse(
        _utilityRateController.text.trim().replaceAll(',', '.'));

    return _templateNameController.text.trim() !=
            preferences.firstContactTemplateName ||
        _templateLanguageController.text.trim() !=
            preferences.firstContactTemplateLanguage ||
        currentRate == null ||
        (currentRate - preferences.utilityConversationUsd).abs() > 0.0001;
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final panelData = await _service.loadPanelData();
      if (!mounted) {
        return;
      }

      _applyPreferences(panelData.preferences);
      setState(() {
        _panelData = panelData;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _applyPreferences(WhatsAppSettingsPreferences preferences) {
    _templateNameController.text = preferences.firstContactTemplateName;
    _templateLanguageController.text = preferences.firstContactTemplateLanguage;
    _utilityRateController.text =
        preferences.utilityConversationUsd.toStringAsFixed(2);
  }

  void _resetToDefaults() {
    _applyPreferences(WhatsAppSettingsPreferences.defaults());
    setState(() {});
  }

  Future<void> _savePreferences() async {
    final panelData = _panelData;
    if (panelData == null || !_hasValidRate || _isSavingPreferences) {
      return;
    }

    final rate =
        double.parse(_utilityRateController.text.trim().replaceAll(',', '.'));

    final preferences = panelData.preferences.copyWith(
      firstContactTemplateName: _templateNameController.text.trim(),
      firstContactTemplateLanguage: _templateLanguageController.text.trim(),
      utilityConversationUsd: rate,
    );

    setState(() => _isSavingPreferences = true);

    try {
      await _service.savePreferences(preferences);
      if (!mounted) {
        return;
      }
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuracion de WhatsApp guardada')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingPreferences = false);
      }
    }
  }

  Future<void> _toggleChannel(
      WhatsAppChannelStatus channel, bool isActive) async {
    setState(() => _channelUpdates.add(channel.id));

    try {
      await _service.toggleChannelStatus(
        channelId: channel.id,
        isActive: isActive,
      );
      if (!mounted) {
        return;
      }

      final panelData = _panelData;
      if (panelData != null) {
        final updatedChannels = panelData.snapshot.channels.map((item) {
          if (item.id == channel.id) {
            return item.copyWith(isActive: isActive);
          }
          return item;
        }).toList();

        setState(() {
          _panelData = WhatsAppSettingsPanelData(
            preferences: panelData.preferences,
            snapshot: WhatsAppSettingsSnapshot(
              tenantId: panelData.snapshot.tenantId,
              channels: updatedChannels,
              lastWebhookAt: panelData.snapshot.lastWebhookAt,
              lastOutboundAt: panelData.snapshot.lastOutboundAt,
              lastTemplateAt: panelData.snapshot.lastTemplateAt,
              webhookEvents24h: panelData.snapshot.webhookEvents24h,
              inboundEvents24h: panelData.snapshot.inboundEvents24h,
              statusEvents24h: panelData.snapshot.statusEvents24h,
              outboundMessages30d: panelData.snapshot.outboundMessages30d,
              templateMessages30d: panelData.snapshot.templateMessages30d,
              deliveredMessages30d: panelData.snapshot.deliveredMessages30d,
              readMessages30d: panelData.snapshot.readMessages30d,
              failedMessages30d: panelData.snapshot.failedMessages30d,
              activeCustomerServiceWindows:
                  panelData.snapshot.activeCustomerServiceWindows,
              openBillableWindows: panelData.snapshot.openBillableWindows,
              billableWindowsToday: panelData.snapshot.billableWindowsToday,
              templateMessagesByName: panelData.snapshot.templateMessagesByName,
              billableWindows30d: panelData.snapshot.billableWindows30d,
              estimatedCost30dUsd: panelData.snapshot.estimatedCost30dUsd,
            ),
          );
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isActive ? 'Canal activado' : 'Canal desactivado'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el canal: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _channelUpdates.remove(channel.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
          ),
        ],
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
                'No se pudo cargar la configuracion de WhatsApp',
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

    final panelData = _panelData;
    if (panelData == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, panelData),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 980;
                      if (!isWide) {
                        return Column(
                          children: [
                            _buildConfigurationCard(context, panelData),
                            const SizedBox(height: 16),
                            _buildOverviewCard(context, panelData),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _buildConfigurationCard(context, panelData),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 5,
                            child: _buildOverviewCard(context, panelData),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildChannelsCard(context, panelData),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 980;
                      if (!isWide) {
                        return Column(
                          children: [
                            _buildBillableWindowsCard(context, panelData),
                            const SizedBox(height: 16),
                            _buildDiagnosticsCard(context, panelData),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child:
                                _buildBillableWindowsCard(context, panelData),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDiagnosticsCard(context, panelData),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WhatsAppSettingsPanelData panelData,
  ) {
    final theme = Theme.of(context);
    final snapshot = panelData.snapshot;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5FAF7), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7EBDD)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 620,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuracion de WhatsApp',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ahora si es un panel real: configura el template de primer contacto, la tarifa referencial para la estimacion y el estado operativo de cada canal. La telemetria sigue disponible, pero como apoyo, no como protagonista.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          _HeroBadge(
            label: 'Canales activos',
            value:
                '${snapshot.channels.where((channel) => channel.isActive).length}',
          ),
          _HeroBadge(
            label: 'Ultimo template',
            value:
                _formatDateTime(snapshot.lastTemplateAt, empty: 'Sin envios'),
          ),
          _HeroBadge(
            label: 'Costo estimado 30d',
            value: _usdFormat.format(snapshot.estimatedCost30dUsd),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationCard(
    BuildContext context,
    WhatsAppSettingsPanelData panelData,
  ) {
    final theme = Theme.of(context);
    final firstContactCount = panelData.snapshot
            .templateMessagesByName[_templateNameController.text.trim()] ??
        0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configuracion operativa',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Estos valores si afectan el envio real del primer mensaje por WhatsApp. Se guardan por tenant en company_settings.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isSavingPreferences ? null : _resetToDefaults,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Usar defaults'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: (!_hasUnsavedChanges ||
                          !_hasValidRate ||
                          _isSavingPreferences)
                      ? null
                      : _savePreferences,
                  icon: _isSavingPreferences
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                final fields = [
                  _ConfigField(
                    title: 'Template de primer contacto',
                    description:
                        'Nombre exacto aprobado en Meta. Este es el que usa el boton inicial del chat de factura.',
                    child: TextField(
                      controller: _templateNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de template',
                        hintText: 'seguimiento_servicio_bicicleta',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _ConfigField(
                    title: 'Idioma del template',
                    description:
                        'Codigo de idioma enviado a la Cloud API para ese template.',
                    child: TextField(
                      controller: _templateLanguageController,
                      decoration: const InputDecoration(
                        labelText: 'Idioma',
                        hintText: 'es_CL',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _ConfigField(
                    title: 'Tarifa referencial por conversacion',
                    description:
                        'Valor usado por el estimador interno. No reemplaza la factura oficial de Meta.',
                    child: TextField(
                      controller: _utilityRateController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'USD por ventana',
                        prefixText: 'US\$ ',
                        border: const OutlineInputBorder(),
                        errorText: _hasValidRate
                            ? null
                            : 'Ingresa un monto valido mayor o igual a 0',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ];

                if (!isWide) {
                  return Column(
                    children: [
                      for (var i = 0; i < fields.length; i++) ...[
                        fields[i],
                        if (i != fields.length - 1) const SizedBox(height: 16),
                      ],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: 16),
                    Expanded(child: fields[1]),
                    const SizedBox(width: 16),
                    Expanded(child: fields[2]),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InlineFact(
                  label: 'Template actual configurado',
                  value: _templateNameController.text.trim().isEmpty
                      ? 'Sin valor'
                      : _templateNameController.text.trim(),
                ),
                _InlineFact(
                  label: 'Idioma actual',
                  value: _templateLanguageController.text.trim().isEmpty
                      ? 'Sin valor'
                      : _templateLanguageController.text.trim(),
                ),
                _InlineFact(
                  label: 'Envios 30d del template configurado',
                  value: '$firstContactCount',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    BuildContext context,
    WhatsAppSettingsPanelData panelData,
  ) {
    final theme = Theme.of(context);
    final snapshot = panelData.snapshot;
    final templateName = panelData.preferences.firstContactTemplateName;
    final templateCount = snapshot.templateMessagesByName[templateName] ?? 0;
    final topTemplate = snapshot.templateMessagesByName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen operativo',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'La parte util del dashboard sigue aqui, pero compacta y legible.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatTile(
                  title: 'Costo estimado 30d',
                  value: _usdFormat.format(snapshot.estimatedCost30dUsd),
                  subtitle: 'Con tarifa referencial configurada',
                  accent: const Color(0xFF14532D),
                ),
                _StatTile(
                  title: 'Ventanas cobrables 30d',
                  value: '${snapshot.billableWindows30d.length}',
                  subtitle: 'Aperturas estimadas por template',
                  accent: const Color(0xFF7C2D12),
                ),
                _StatTile(
                  title: 'Ventanas gratis 24h',
                  value: '${snapshot.activeCustomerServiceWindows}',
                  subtitle: 'Con ultimo inbound del cliente',
                  accent: const Color(0xFF065F46),
                ),
                _StatTile(
                  title: 'Entregados 30d',
                  value: '${snapshot.deliveredMessages30d}',
                  subtitle: 'Outbounds confirmados',
                  accent: const Color(0xFF1D4ED8),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7FB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE7E7EF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lectura rapida',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildDetailLine(
                    context,
                    'Template configurado',
                    '$templateName · ${panelData.preferences.firstContactTemplateLanguage}',
                  ),
                  _buildDetailLine(
                    context,
                    'Envios 30d de ese template',
                    '$templateCount',
                  ),
                  _buildDetailLine(
                    context,
                    'Ultimo webhook',
                    _formatDateTime(snapshot.lastWebhookAt),
                  ),
                  _buildDetailLine(
                    context,
                    'Ultimo outbound',
                    _formatDateTime(snapshot.lastOutboundAt),
                  ),
                  _buildDetailLine(
                    context,
                    'Template mas usado',
                    topTemplate.isEmpty
                        ? 'Sin actividad'
                        : '${topTemplate.first.key} (${topTemplate.first.value})',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsCard(
    BuildContext context,
    WhatsAppSettingsPanelData panelData,
  ) {
    final theme = Theme.of(context);
    final channels = panelData.snapshot.channels;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Canales',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Activa o desactiva cada numero desde aqui. El estado se guarda directamente sobre whatsapp_channels.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 16),
            if (channels.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'No hay canales de WhatsApp configurados para este tenant.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ...channels.map((channel) {
                final isUpdating = _channelUpdates.contains(channel.id);
                final stateColor = channel.isActive
                    ? const Color(0xFF166534)
                    : const Color(0xFF6B7280);
                final stateBackground = channel.isActive
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF3F4F6);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: channel.isActive
                                  ? const Color(0xFFE7F8ED)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.phone_android,
                              color: stateColor,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  channel.displayName?.isNotEmpty == true
                                      ? channel.displayName!
                                      : 'Canal sin nombre',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  channel.displayPhoneNumber ??
                                      'Numero no configurado',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (isUpdating)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Switch.adaptive(
                              value: channel.isActive,
                              onChanged: (value) =>
                                  _toggleChannel(channel, value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetaPill(
                            label: channel.isActive ? 'Activo' : 'Inactivo',
                            background: stateBackground,
                            color: stateColor,
                          ),
                          _MetaPill(
                            label: 'Bindings: ${channel.trackedConversations}',
                          ),
                          _MetaPill(
                            label:
                                'Webhook: ${_formatDateTime(channel.lastWebhookAt, empty: 'Sin datos')}',
                          ),
                          _MetaPill(
                            label:
                                'Inbound: ${_formatDateTime(channel.lastInboundAt, empty: 'Sin datos')}',
                          ),
                          _MetaPill(
                            label:
                                'Outbound: ${_formatDateTime(channel.lastOutboundAt, empty: 'Sin datos')}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildBillableWindowsCard(
    BuildContext context,
    WhatsAppSettingsPanelData panelData,
  ) {
    final theme = Theme.of(context);
    final windows = panelData.snapshot.billableWindows30d;

    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          initiallyExpanded: true,
          title: Text(
            'Ventanas cobrables estimadas',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            'Detalle secundario: util para auditar el estimador sin convertir la pantalla en un muro de datos.',
            style: theme.textTheme.bodySmall,
          ),
          children: [
            if (windows.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No hay ventanas cobrables estimadas en los ultimos 30 dias.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ...windows.take(10).map((window) {
                return Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: window.isActive
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
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
                                fontWeight: FontWeight.w800,
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetaPill(label: window.templateName),
                          _MetaPill(label: window.category),
                          _MetaPill(
                            label: window.isActive ? 'Activa' : 'Cerrada',
                            background: window.isActive
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFF3F4F6),
                            color: window.isActive
                                ? const Color(0xFF166534)
                                : const Color(0xFF4B5563),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Abierta ${_shortFormat.format(window.openedAt.toLocal())} · Expira ${_shortFormat.format(window.expiresAt.toLocal())}',
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

  Widget _buildDiagnosticsCard(
    BuildContext context,
    WhatsAppSettingsPanelData panelData,
  ) {
    final theme = Theme.of(context);
    final snapshot = panelData.snapshot;

    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Text(
            'Actividad y diagnostico',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            'Salud del webhook, volumenes y senales para soporte operativo.',
            style: theme.textTheme.bodySmall,
          ),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InlineFact(
                  label: 'Webhooks 24h',
                  value: '${snapshot.webhookEvents24h}',
                ),
                _InlineFact(
                  label: 'Inbound 24h',
                  value: '${snapshot.inboundEvents24h}',
                ),
                _InlineFact(
                  label: 'Statuses 24h',
                  value: '${snapshot.statusEvents24h}',
                ),
                _InlineFact(
                  label: 'Outbounds 30d',
                  value: '${snapshot.outboundMessages30d}',
                ),
                _InlineFact(
                  label: 'Read 30d',
                  value: '${snapshot.readMessages30d}',
                ),
                _InlineFact(
                  label: 'Failed 30d',
                  value: '${snapshot.failedMessages30d}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildDetailLine(
              context,
              'Ultimo webhook global',
              _formatDateTime(snapshot.lastWebhookAt),
            ),
            _buildDetailLine(
              context,
              'Ultimo outbound global',
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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

  String _formatDateTime(DateTime? value, {String empty = 'Sin datos'}) {
    if (value == null) {
      return empty;
    }
    return _dateTimeFormat.format(value.toLocal());
  }
}

class _ConfigField extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _ConfigField({
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color accent;

  const _StatTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
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

class _InlineFact extends StatelessWidget {
  final String label;
  final String value;

  const _InlineFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
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

class _MetaPill extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? color;

  const _MetaPill({
    required this.label,
    this.background,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedBackground =
        background ?? Theme.of(context).colorScheme.surfaceContainerHighest;
    final resolvedColor = color ?? Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: resolvedColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String label;
  final String value;

  const _HeroBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EFE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
