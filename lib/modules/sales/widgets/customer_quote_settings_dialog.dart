import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/shop_time.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../models/customer_quote.dart';
import '../services/customer_quote_service.dart';

/// «Ajustes de cotizaciones» (20261103060000): lo que el taller le promete
/// al cliente y lo que se exige a sí mismo, cada valor con lo que significa.
/// Los cambia administración (o quien cambia los ajustes del taller); los
/// demás los ven. Devuelve true si se guardó un cambio.
Future<bool> showCustomerQuoteSettings(
  BuildContext context, {
  CustomerQuoteService? service,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => CustomerQuoteSettingsDialog(
      service: service ?? CustomerQuoteService(),
    ),
  );
  return saved == true;
}

class CustomerQuoteSettingsDialog extends StatefulWidget {
  const CustomerQuoteSettingsDialog({super.key, required this.service});

  final CustomerQuoteService service;

  @override
  State<CustomerQuoteSettingsDialog> createState() =>
      _CustomerQuoteSettingsDialogState();
}

/// Un valor en horas con sus límites.
class _HoursField {
  _HoursField(this.key, this.range);

  final String key;
  final ({int min, int max}) range;

  /// El diálogo es dueño de sus controladores y los suelta en su `dispose`,
  /// cuando sus campos ya no existen.
  final controller = TextEditingController();
  String? error;

  int? get value => int.tryParse(controller.text.trim());
}

class _CustomerQuoteSettingsDialogState
    extends State<CustomerQuoteSettingsDialog> {
  CustomerQuoteSettings? _settings;
  Object? _loadError;
  bool _saving = false;
  String? _saveError;

  final _validity =
      _HoursField('offer_validity_hours', CustomerQuoteSettings.validityRange);
  final _reminder =
      _HoursField('reminder_hours_before', CustomerQuoteSettings.reminderRange);
  final _taskDue = _HoursField(
      'supplier_task_due_hours', CustomerQuoteSettings.taskDueRange);
  final _checkFresh = _HoursField(
      'supplier_check_fresh_hours', CustomerQuoteSettings.checkFreshRange);

  List<_HoursField> get _fields =>
      [_validity, _reminder, _taskDue, _checkFresh];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final settings = await widget.service.fetchSettings();
      if (!mounted) return;
      _validity.controller.text = '${settings.offerValidityHours}';
      _reminder.controller.text = '${settings.reminderHoursBefore}';
      _taskDue.controller.text = '${settings.supplierTaskDueHours}';
      _checkFresh.controller.text = '${settings.supplierCheckFreshHours}';
      setState(() => _settings = settings);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Lo mismo que la base exige, dicho en el campo antes de guardar.
  bool _validate() {
    for (final field in _fields) {
      final value = field.value;
      field.error = value == null
          ? 'Escribe un número de horas.'
          : value < field.range.min || value > field.range.max
              ? 'Entre ${field.range.min} y ${field.range.max} horas.'
              : null;
    }
    final validity = _validity.value;
    final reminder = _reminder.value;
    if (_reminder.error == null &&
        validity != null &&
        reminder != null &&
        reminder >= validity) {
      _reminder.error = 'Tiene que ser antes de que la oferta venza.';
    }
    return _fields.every((field) => field.error == null);
  }

  Future<void> _save() async {
    setState(() => _saveError = null);
    if (!_validate()) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.updateSettings(
        offerValidityHours: _validity.value!,
        reminderHoursBefore: _reminder.value!,
        supplierTaskDueHours: _taskDue.value!,
        supplierCheckFreshHours: _checkFresh.value!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final key = CustomerQuoteService.invalidSettingOf(error);
      setState(() {
        for (final field in _fields) {
          if (field.key == key) {
            field.error = field == _reminder
                ? 'Tiene que ser antes de que la oferta venza.'
                : 'Revisa este valor.';
          }
        }
        _saveError = CustomerQuoteService.describeError(error);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final canEdit = settings?.canEdit ?? false;
    return AlertDialog(
      title: const Text('Ajustes de cotizaciones'),
      content: SizedBox(
        width: 460,
        child: settings == null
            ? _loadError != null
                ? VbNotice(
                    title: 'No se pudieron leer los ajustes',
                    body: CustomerQuoteService.describeError(_loadError!),
                    tone: VbNoticeTone.danger,
                    action: VbButton(
                      label: 'Reintentar',
                      variant: VbButtonVariant.secondary,
                      onPressed: _load,
                    ),
                  )
                : const SizedBox(
                    height: 160, child: Center(child: BrandedLoading()))
            : SingleChildScrollView(
                child: _SettingsForm(
                  settings: settings,
                  canEdit: canEdit && !_saving,
                  validity: _validity,
                  reminder: _reminder,
                  taskDue: _taskDue,
                  checkFresh: _checkFresh,
                  saveError: _saveError,
                  onChanged: (field) => setState(() => field.error = null),
                ),
              ),
      ),
      actions: [
        VbButton(
          label: canEdit ? 'Cancelar' : 'Cerrar',
          variant: VbButtonVariant.text,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        if (canEdit)
          VbButton(
            label: 'Guardar',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
      ],
    );
  }
}

class _SettingsForm extends StatelessWidget {
  const _SettingsForm({
    required this.settings,
    required this.canEdit,
    required this.validity,
    required this.reminder,
    required this.taskDue,
    required this.checkFresh,
    required this.saveError,
    required this.onChanged,
  });

  final CustomerQuoteSettings settings;
  final bool canEdit;
  final _HoursField validity;
  final _HoursField reminder;
  final _HoursField taskDue;
  final _HoursField checkFresh;
  final String? saveError;
  final ValueChanged<_HoursField> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);
    final updatedAt = settings.updatedAt;
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: roles.faintForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!settings.canEdit) ...[
          const VbNotice(
            title: 'Sólo administración cambia estos valores',
            tone: VbNoticeTone.neutral,
          ),
          const SizedBox(height: 16),
        ],
        section('Con el cliente'),
        _HoursInput(
          field: validity,
          label: 'Vigencia de una oferta',
          help: (hours) => 'Desde que se envía${_inDays(hours)}. Después '
              'vence y el cliente pide una nueva.',
          enabled: canEdit,
          onChanged: onChanged,
        ),
        const SizedBox(height: 14),
        _HoursInput(
          field: reminder,
          label: 'Recordatorio antes de que venza',
          help: (hours) => hours == null
              ? 'Horas antes de que venza. Con 0 no se le recuerda.'
              : hours == 0
                  ? 'Con 0 no se le recuerda.'
                  : 'Le recordamos ${_hours(hours)} antes, por lo que '
                      'eligió. Con 0 no se le recuerda.',
          enabled: canEdit,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: roles.faintForeground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                settings.onOrderPrepayPercent >= 100
                    ? 'Lo que viene a pedido se paga completo al aceptar.'
                    : 'Lo que viene a pedido se paga con un abono del '
                        '${settings.onOrderPrepayPercent} %.',
                style: faint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        section('Con los proveedores'),
        _HoursInput(
          field: taskDue,
          label: 'Plazo para que responda un proveedor',
          help: (hours) => 'La tarea de preguntarle vence en '
              '${hours == null ? 'este plazo' : _hours(hours)}.',
          enabled: canEdit,
          onChanged: onChanged,
        ),
        const SizedBox(height: 14),
        _HoursInput(
          field: checkFresh,
          label: 'Una disponibilidad confirmada sirve por',
          help: (_) => 'Lo confirmado con el proveedor o leído de su portal '
              'hace menos de esto no se vuelve a preguntar.',
          enabled: canEdit,
          onChanged: onChanged,
        ),
        if (saveError != null) ...[
          const SizedBox(height: 16),
          Text(
            saveError!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        if (updatedAt != null) ...[
          const SizedBox(height: 16),
          Text(
            'Último cambio: '
            '${DateFormat("d MMM, HH:mm", 'es').format(shopTime(updatedAt))}',
            style: faint,
          ),
        ],
      ],
    );
  }
}

class _HoursInput extends StatelessWidget {
  const _HoursInput({
    required this.field,
    required this.label,
    required this.help,
    required this.enabled,
    required this.onChanged,
  });

  final _HoursField field;
  final String label;

  /// Lo que significa el valor escrito (null si no es un número).
  final String Function(int? hours) help;
  final bool enabled;
  final ValueChanged<_HoursField> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: field.controller,
      builder: (context, _, __) => TextField(
        key: ValueKey('quote-setting-${field.key}'),
        controller: field.controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        onChanged: (_) => onChanged(field),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'horas',
          helperText: help(field.value),
          helperMaxLines: 3,
          errorText: field.error,
          errorMaxLines: 2,
        ),
      ),
    );
  }
}

/// « (3 días)», « (1 día y 12 horas)»; nada bajo un día.
String _inDays(int? hours) {
  if (hours == null || hours < 24) return '';
  return ' (${_hours(hours)})';
}

/// 72 → «3 días», 36 → «1 día y 12 horas», 12 → «12 horas».
String _hours(int hours) {
  final days = hours ~/ 24;
  final rest = hours % 24;
  String plural(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';
  if (days == 0) return plural(rest, 'hora', 'horas');
  final dayText = plural(days, 'día', 'días');
  return rest == 0 ? dayText : '$dayText y ${plural(rest, 'hora', 'horas')}';
}
