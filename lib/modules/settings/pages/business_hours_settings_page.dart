import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../../website/services/google_business_service.dart';
import '../../website/services/website_service.dart';

class BusinessHoursSettingsPage extends StatefulWidget {
  const BusinessHoursSettingsPage({super.key});

  @override
  State<BusinessHoursSettingsPage> createState() =>
      _BusinessHoursSettingsPageState();
}

class _BusinessHoursSettingsPageState extends State<BusinessHoursSettingsPage> {
  final _facebookPageIdController = TextEditingController();
  late List<_DayScheduleDraft> _days;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPublishing = false;
  String _sourceLabel = 'Ajuste manual';
  List<_PublishResult> _publishResults = const [];

  @override
  void initState() {
    super.initState();
    _days = _defaultSchedule();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final service = context.read<WebsiteService>();
      if (service.settings.isEmpty) {
        await service.loadSettings();
      }

      final manualRaw = service.getSetting('business_hours_json').trim();
      final googleRaw =
          service.getSetting('google_business_regular_hours').trim();
      _facebookPageIdController.text = service.getSetting(
        'facebook_page_id',
        service.getSetting('meta_facebook_page_id'),
      );
      final rawHours = manualRaw.isNotEmpty ? manualRaw : googleRaw;
      final parsed = _parseBusinessHours(rawHours);

      if (!mounted) return;
      setState(() {
        _days = parsed ?? _defaultSchedule();
        _sourceLabel = manualRaw.isNotEmpty
            ? 'Ajuste manual'
            : googleRaw.isNotEmpty
                ? 'Datos de Google'
                : 'Horario sugerido';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('No se pudo cargar el horario: $error');
    }
  }

  @override
  void dispose() {
    _facebookPageIdController.dispose();
    super.dispose();
  }

  Future<bool> _saveSettings({bool showSnackBar = true}) async {
    setState(() => _isSaving = true);
    final service = context.read<WebsiteService>();
    final now = DateTime.now().toIso8601String();

    try {
      await service.saveSettings({
        'business_hours_json': jsonEncode({
          'source': 'erp_settings',
          'updated_at': now,
          ..._regularHoursPayload(),
        }),
        'business_hours_source': 'erp_settings',
        'business_hours_updated_at': now,
        'business_hours_apply_payroll': 'true',
        'business_hours_apply_website': 'true',
        'facebook_page_id': _facebookPageIdController.text.trim(),
      });

      if (!mounted) return true;
      setState(() {
        _sourceLabel = 'Ajuste manual';
        _isSaving = false;
      });
      if (showSnackBar) _showSnackBar('Horario guardado');
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _isSaving = false);
      _showSnackBar('No se pudo guardar el horario: $error');
      return false;
    }
  }

  Future<void> _saveAndPublishSettings() async {
    final saved = await _saveSettings(showSnackBar: false);
    if (!saved || !mounted) return;
    await _publishBusinessHours();
  }

  Future<void> _publishBusinessHours() async {
    setState(() {
      _isPublishing = true;
      _publishResults = const [];
    });

    final service = context.read<WebsiteService>();
    final regularHours = _regularHoursPayload();
    final hoursLabel = _hoursLabel();
    final now = DateTime.now().toIso8601String();
    final results = <_PublishResult>[
      _PublishResult.success(
        'Tienda online',
        'Horario guardado para la pagina de contacto.',
      ),
    ];

    final googleLocation =
        service.getSetting('business_google_location_id').trim();
    if (googleLocation.isEmpty) {
      results.add(
        _PublishResult.skipped(
          'Google Maps',
          'Falta sincronizar o seleccionar la ubicacion de Google Business.',
        ),
      );
    } else {
      final google = context.read<GoogleBusinessService>();
      final hasGoogleToken = google.hasProviderToken ||
          await google.ensureProviderToken(timeout: const Duration(seconds: 2));
      if (!hasGoogleToken) {
        results.add(
          _PublishResult.skipped(
            'Google Maps',
            'Renueva el acceso de Google Business Profile para publicar.',
          ),
        );
      } else {
        try {
          await google.publishRegularHours(
            locationName: googleLocation,
            regularHours: regularHours,
          );
          results.add(
            _PublishResult.success(
              'Google Maps',
              'Horario enviado a Google Business Profile.',
            ),
          );
        } catch (error) {
          results.add(
            _PublishResult.failed(
              'Google Maps',
              _cleanError(error),
            ),
          );
        }
      }
    }

    await _publishMetaBusinessHours(
      regularHours: regularHours,
      hoursLabel: hoursLabel,
      results: results,
    );

    if (!mounted) return;
    setState(() {
      _isPublishing = false;
      _publishResults = results;
    });

    await service.saveSettings({
      'business_hours_last_published_at': now,
      'business_hours_publish_results_json': jsonEncode(
        results.map((result) => result.toJson()).toList(),
      ),
      'business_hours_publish_status':
          results.any((result) => result.isFailure) ? 'partial' : 'ok',
    });

    if (!mounted) return;
    final failures = results.where((result) => result.isFailure).length;
    _showSnackBar(
      failures == 0
          ? 'Horario publicado'
          : 'Horario publicado con $failures destino(s) pendiente(s)',
    );
  }

  Future<void> _publishMetaBusinessHours({
    required Map<String, dynamic> regularHours,
    required String hoursLabel,
    required List<_PublishResult> results,
  }) async {
    try {
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      final response = await Supabase.instance.client.functions.invoke(
        'whatsapp-profile-admin',
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: {
          'action': 'publish_business_hours',
          'businessHours': regularHours,
          'hoursLabel': hoursLabel,
          if (_facebookPageIdController.text.trim().isNotEmpty)
            'facebookPageId': _facebookPageIdController.text.trim(),
        },
      );

      if (response.status >= 300) {
        results.add(
          _PublishResult.failed(
            'Meta / WhatsApp',
            _errorMessage(response.data),
          ),
        );
        return;
      }

      _appendMetaResults(results, response.data);
    } on FunctionException catch (error) {
      results.add(
        _PublishResult.failed(
          'Meta / WhatsApp',
          _errorMessage(error.details),
        ),
      );
    } catch (error) {
      results.add(
        _PublishResult.failed(
          'Meta / WhatsApp',
          _cleanError(error),
        ),
      );
    }
  }

  Future<void> _pickTime(_DayScheduleDraft day, bool isOpeningTime) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpeningTime ? day.openTime : day.closeTime,
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isOpeningTime) {
        day.openTime = picked;
        if (_minuteOf(day.closeTime) <= _minuteOf(day.openTime)) {
          day.closeTime = _addHours(day.openTime, 1);
        }
      } else {
        day.closeTime = picked;
      }
    });
  }

  void _copyFromPrevious(int index) {
    if (index <= 0) return;
    final previous = _days[index - 1];
    final current = _days[index];

    setState(() {
      current.isOpen = previous.isOpen;
      current.openTime = previous.openTime;
      current.closeTime = previous.closeTime;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Map<String, dynamic> _regularHoursPayload() {
    return {
      'periods': _days
          .where((day) => day.isOpen)
          .map((day) => {
                'openDay': day.key,
                'openTime': _timeToJson(day.openTime),
                'closeDay': day.key,
                'closeTime': _timeToJson(day.closeTime),
              })
          .toList(),
    };
  }

  String _hoursLabel() {
    return _days
        .where((day) => day.isOpen)
        .map(
          (day) =>
              '${day.label} ${_formatTime(day.openTime)}-${_formatTime(day.closeTime)}',
        )
        .join('; ');
  }

  void _appendMetaResults(List<_PublishResult> results, dynamic responseData) {
    final data = responseData is Map
        ? Map<String, dynamic>.from(responseData as Map)
        : const <String, dynamic>{};
    final items = data['results'];
    if (items is! List) {
      results.add(
        _PublishResult.success(
          'Meta / WhatsApp',
          'Respuesta recibida desde Meta.',
        ),
      );
      return;
    }

    for (final item in items) {
      if (item is! Map) continue;
      final result = Map<String, dynamic>.from(item);
      final destination = _destinationLabel(result['destination']);
      if (result['skipped'] == true) {
        results.add(
          _PublishResult.skipped(destination, _skipMessage(result['reason'])),
        );
      } else if (result['ok'] == true) {
        results.add(
          _PublishResult.success(destination, 'Horario publicado.'),
        );
      } else {
        results.add(
          _PublishResult.failed(destination, _errorMessage(result['payload'])),
        );
      }
    }
  }

  String _destinationLabel(dynamic value) {
    return switch (value?.toString()) {
      'whatsapp' => 'WhatsApp',
      'facebook' => 'Facebook',
      'instagram' => 'Instagram',
      _ => 'Meta',
    };
  }

  String _skipMessage(dynamic reason) {
    return switch (reason?.toString()) {
      'facebook_page_id_missing' =>
        'Falta configurar facebook_page_id en ajustes.',
      _ => 'Destino sin configuracion suficiente.',
    };
  }

  String _errorMessage(dynamic value) {
    if (value == null) return 'No se pudo publicar el horario.';
    if (value is String) return value;
    if (value is Map) {
      final map = Map<String, dynamic>.from(value as Map);
      final error = map['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
      if (error is Map) {
        final errorMap = Map<String, dynamic>.from(error);
        final message = errorMap['message']?.toString().trim();
        if (message != null && message.isNotEmpty) return message;
      }
      final message = map['message']?.toString().trim();
      if (message != null && message.isNotEmpty) return message;
      final details = map['details'];
      if (details != null) return details.toString();
    }
    return value.toString();
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: BrandedLoading())
        : LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 920;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 18),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildSchedulePanel(context)),
                              const SizedBox(width: 18),
                              SizedBox(
                                width: 320,
                                child: _buildUsagePanel(context),
                              ),
                            ],
                          )
                        else ...[
                          _buildSchedulePanel(context),
                          const SizedBox(height: 18),
                          _buildUsagePanel(context),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horario de atencion'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : () => _saveSettings(),
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Guardando' : 'Guardar'),
          ),
          TextButton.icon(
            onPressed:
                _isSaving || _isPublishing ? null : _saveAndPublishSettings,
            icon: _isPublishing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_isPublishing ? 'Publicando' : 'Publicar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.schedule_outlined,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Horario operativo del negocio',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Define los dias y horas que deben usar la tienda online, nominas y proximas sincronizaciones externas.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulePanel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Semana laboral',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < _days.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _buildDayRow(context, _days[index], index),
          ],
        ],
      ),
    );
  }

  Widget _buildDayRow(
    BuildContext context,
    _DayScheduleDraft day,
    int index,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final dayLabel = Text(
          day.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        );
        final closedLabel = Text(
          'Cerrado',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        );
        final copyButton = IconButton(
          tooltip: 'Copiar dia anterior',
          onPressed: index == 0 ? null : () => _copyFromPrevious(index),
          icon: const Icon(Icons.copy_outlined, size: 18),
        );
        final timeControls = <Widget>[
          if (day.isOpen) ...[
            _TimeButton(
              label: _formatTime(day.openTime),
              icon: Icons.login_outlined,
              onPressed: () => _pickTime(day, true),
            ),
            if (!compact)
              Text(
                'a',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            _TimeButton(
              label: _formatTime(day.closeTime),
              icon: Icons.logout_outlined,
              onPressed: () => _pickTime(day, false),
            ),
          ] else
            closedLabel,
          copyButton,
        ];

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Switch(
                          value: day.isOpen,
                          onChanged: (value) =>
                              setState(() => day.isOpen = value),
                        ),
                        Expanded(child: dayLabel),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: timeControls,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Switch(
                      value: day.isOpen,
                      onChanged: (value) => setState(() => day.isOpen = value),
                    ),
                    SizedBox(width: 116, child: dayLabel),
                    if (day.isOpen)
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: timeControls,
                      )
                    else ...[
                      Expanded(child: closedLabel),
                      copyButton,
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _buildUsagePanel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final openDays = _days.where((day) => day.isOpen).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Uso del horario',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _StatusLine(
            icon: Icons.storefront_outlined,
            title: 'Tienda online',
            subtitle: 'La pagina de contacto lee este horario primero.',
          ),
          const SizedBox(height: 12),
          _StatusLine(
            icon: Icons.payments_outlined,
            title: 'Nominas',
            subtitle: 'El calendario de pago usa estos dias abiertos.',
          ),
          const SizedBox(height: 12),
          _StatusLine(
            icon: Icons.hub_outlined,
            title: 'Canales externos',
            subtitle: 'Base lista para publicar horarios por integraciones.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _facebookPageIdController,
            decoration: const InputDecoration(
              labelText: 'Facebook Page ID',
              prefixIcon: Icon(Icons.facebook),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const Divider(height: 28),
          Text(
            '$openDays dias abiertos',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Fuente actual: $_sourceLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push('/website/integrations'),
            icon: const Icon(Icons.sync_outlined),
            label: const Text('Abrir integraciones'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _isSaving || _isPublishing ? null : _saveAndPublishSettings,
              icon: _isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(
                _isPublishing ? 'Publicando horario' : 'Guardar y publicar',
              ),
            ),
          ),
          if (_publishResults.isNotEmpty) ...[
            const Divider(height: 28),
            for (final result in _publishResults) ...[
              _PublishStatusRow(result: result),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  List<_DayScheduleDraft> _defaultSchedule() {
    return [
      _DayScheduleDraft.open('MONDAY', 'Lunes', 10, 0, 19, 0),
      _DayScheduleDraft.open('TUESDAY', 'Martes', 10, 0, 19, 0),
      _DayScheduleDraft.open('WEDNESDAY', 'Miercoles', 10, 0, 19, 0),
      _DayScheduleDraft.open('THURSDAY', 'Jueves', 10, 0, 19, 0),
      _DayScheduleDraft.open('FRIDAY', 'Viernes', 10, 0, 19, 0),
      _DayScheduleDraft.open('SATURDAY', 'Sabado', 10, 0, 14, 0),
      _DayScheduleDraft.closed('SUNDAY', 'Domingo'),
    ];
  }

  List<_DayScheduleDraft>? _parseBusinessHours(String rawJson) {
    if (rawJson.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(rawJson);
      final rootData = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
      final data = rootData['opening_hours'] is Map
          ? Map<String, dynamic>.from(rootData['opening_hours'] as Map)
          : rootData;
      final periods = data['periods'] as List<dynamic>? ?? const [];
      if (periods.isEmpty) return null;

      final drafts = _defaultSchedule()
          .map((day) => day.copyWith(isOpen: false))
          .toList(growable: false);

      for (final rawPeriod in periods) {
        if (rawPeriod is! Map) continue;
        final period = Map<String, dynamic>.from(rawPeriod);

        if (period.containsKey('openDay') || period.containsKey('openTime')) {
          final index = _businessDayIndex(period['openDay']);
          final openTime = _parseBusinessTime(period['openTime']);
          final closeTime = _parseBusinessTime(period['closeTime']);
          if (index == null || openTime == null || closeTime == null) continue;
          _mergePeriod(drafts[index], openTime, closeTime);
          continue;
        }

        final open = period['open'] is Map
            ? Map<String, dynamic>.from(period['open'] as Map)
            : null;
        final close = period['close'] is Map
            ? Map<String, dynamic>.from(period['close'] as Map)
            : null;
        final index = _placesDayIndex(open?['day']);
        final openTime = _parsePlacesTime(open?['time']);
        final closeTime = _parsePlacesTime(close?['time']);
        if (index == null || openTime == null || closeTime == null) continue;
        _mergePeriod(drafts[index], openTime, closeTime);
      }

      return drafts.any((day) => day.isOpen) ? drafts : null;
    } catch (_) {
      return null;
    }
  }

  void _mergePeriod(
    _DayScheduleDraft day,
    TimeOfDay openTime,
    TimeOfDay closeTime,
  ) {
    if (!day.isOpen) {
      day.isOpen = true;
      day.openTime = openTime;
      day.closeTime = closeTime;
      return;
    }

    if (_minuteOf(openTime) < _minuteOf(day.openTime)) {
      day.openTime = openTime;
    }
    if (_minuteOf(closeTime) > _minuteOf(day.closeTime)) {
      day.closeTime = closeTime;
    }
  }

  int? _businessDayIndex(dynamic rawDay) {
    final day = rawDay?.toString().toUpperCase();
    return switch (day) {
      'MONDAY' => 0,
      'TUESDAY' => 1,
      'WEDNESDAY' => 2,
      'THURSDAY' => 3,
      'FRIDAY' => 4,
      'SATURDAY' => 5,
      'SUNDAY' => 6,
      _ => null,
    };
  }

  int? _placesDayIndex(dynamic rawDay) {
    final day = rawDay is num ? rawDay.toInt() : int.tryParse('$rawDay');
    return switch (day) {
      1 => 0,
      2 => 1,
      3 => 2,
      4 => 3,
      5 => 4,
      6 => 5,
      0 => 6,
      _ => null,
    };
  }

  TimeOfDay? _parseBusinessTime(dynamic rawTime) {
    if (rawTime is String) return _parsePlacesTime(rawTime);
    if (rawTime is! Map) return null;

    final time = Map<String, dynamic>.from(rawTime);
    final hours = (time['hours'] as num?)?.toInt();
    final minutes = (time['minutes'] as num?)?.toInt() ?? 0;
    if (hours == null) return null;
    return TimeOfDay(
      hour: hours.clamp(0, 23).toInt(),
      minute: minutes.clamp(0, 59).toInt(),
    );
  }

  TimeOfDay? _parsePlacesTime(dynamic rawTime) {
    final digits = rawTime?.toString().replaceAll(':', '').trim();
    if (digits == null || digits.length < 3) return null;
    final padded = digits.padLeft(4, '0');
    final hours = int.tryParse(padded.substring(0, 2));
    final minutes = int.tryParse(padded.substring(2, 4));
    if (hours == null || minutes == null) return null;
    return TimeOfDay(
      hour: hours.clamp(0, 23).toInt(),
      minute: minutes.clamp(0, 59).toInt(),
    );
  }

  Map<String, int> _timeToJson(TimeOfDay time) {
    return {
      'hours': time.hour,
      'minutes': time.minute,
    };
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  int _minuteOf(TimeOfDay time) => time.hour * 60 + time.minute;

  TimeOfDay _addHours(TimeOfDay time, int hours) {
    final minutes =
        (_minuteOf(time) + hours * 60).clamp(0, 23 * 60 + 59).toInt();
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }
}

class _DayScheduleDraft {
  final String key;
  final String label;
  bool isOpen;
  TimeOfDay openTime;
  TimeOfDay closeTime;

  _DayScheduleDraft({
    required this.key,
    required this.label,
    required this.isOpen,
    required this.openTime,
    required this.closeTime,
  });

  factory _DayScheduleDraft.open(
    String key,
    String label,
    int openHour,
    int openMinute,
    int closeHour,
    int closeMinute,
  ) {
    return _DayScheduleDraft(
      key: key,
      label: label,
      isOpen: true,
      openTime: TimeOfDay(hour: openHour, minute: openMinute),
      closeTime: TimeOfDay(hour: closeHour, minute: closeMinute),
    );
  }

  factory _DayScheduleDraft.closed(String key, String label) {
    return _DayScheduleDraft(
      key: key,
      label: label,
      isOpen: false,
      openTime: const TimeOfDay(hour: 10, minute: 0),
      closeTime: const TimeOfDay(hour: 18, minute: 0),
    );
  }

  _DayScheduleDraft copyWith({bool? isOpen}) {
    return _DayScheduleDraft(
      key: key,
      label: label,
      isOpen: isOpen ?? this.isOpen,
      openTime: openTime,
      closeTime: closeTime,
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _TimeButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(98, 38),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StatusLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublishResult {
  final String destination;
  final String message;
  final _PublishResultStatus status;

  const _PublishResult({
    required this.destination,
    required this.message,
    required this.status,
  });

  factory _PublishResult.success(String destination, String message) {
    return _PublishResult(
      destination: destination,
      message: message,
      status: _PublishResultStatus.success,
    );
  }

  factory _PublishResult.skipped(String destination, String message) {
    return _PublishResult(
      destination: destination,
      message: message,
      status: _PublishResultStatus.skipped,
    );
  }

  factory _PublishResult.failed(String destination, String message) {
    return _PublishResult(
      destination: destination,
      message: message,
      status: _PublishResultStatus.failed,
    );
  }

  bool get isFailure => status == _PublishResultStatus.failed;

  Map<String, String> toJson() {
    return {
      'destination': destination,
      'status': status.name,
      'message': message,
    };
  }
}

enum _PublishResultStatus { success, skipped, failed }

class _PublishStatusRow extends StatelessWidget {
  final _PublishResult result;

  const _PublishStatusRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = switch (result.status) {
      _PublishResultStatus.success => Colors.green.shade700,
      _PublishResultStatus.skipped => Colors.orange.shade800,
      _PublishResultStatus.failed => colorScheme.error,
    };
    final icon = switch (result.status) {
      _PublishResultStatus.success => Icons.check_circle_outline,
      _PublishResultStatus.skipped => Icons.info_outline,
      _PublishResultStatus.failed => Icons.error_outline,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.destination,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                result.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
