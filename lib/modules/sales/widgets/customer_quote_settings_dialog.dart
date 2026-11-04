import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/shop_time.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../models/customer_quote.dart';
import '../services/customer_quote_service.dart';

/// «Ajustes de cotizaciones» (20261103060000): lo que el taller le promete
/// al cliente y lo que se exige a sí mismo, cada valor con lo que significa,
/// y qué agotados de la tienda se ofrecen para cotizar (20261103070000). Los
/// cambia administración (o quien cambia los ajustes del taller); los demás
/// los ven. Devuelve true si se guardó un cambio.
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

  // Las marcas que se cotizan sin stock: la lista que se edita, la guardada
  // y los nombres; el resumen cuenta los agotados y ofrece las demás marcas.
  List<String> _listed = const [];
  Set<String> _savedListed = const {};
  final Map<String, String> _brandNames = {};
  CustomerQuoteSoldOutSummary? _summary;
  Object? _summaryError;
  String? _brandsError;

  bool get _listedChanged => !setEquals(_listed.toSet(), _savedListed);

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
    if (_summary == null) unawaited(_loadSummary());
    try {
      final settings = await widget.service.fetchSettings();
      if (!mounted) return;
      _validity.controller.text = '${settings.offerValidityHours}';
      _reminder.controller.text = '${settings.reminderHoursBefore}';
      _taskDue.controller.text = '${settings.supplierTaskDueHours}';
      _checkFresh.controller.text = '${settings.supplierCheckFreshHours}';
      setState(() {
        _settings = settings;
        _listed = [for (final brand in settings.soldOutBrands) brand.id];
        _savedListed = _listed.toSet();
        for (final brand in settings.soldOutBrands) {
          _brandNames[brand.id] = brand.name;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Contar los agotados no detiene el resto de los ajustes.
  Future<void> _loadSummary() async {
    setState(() => _summaryError = null);
    try {
      final summary = await widget.service.fetchSoldOutSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        for (final brand in summary.brands) {
          _brandNames[brand.id] = brand.name;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _summaryError = error);
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
        soldOutBrandIds: _listedChanged ? _listed : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final key = CustomerQuoteService.invalidSettingOf(error);
      setState(() {
        if (key == 'sold_out_brand_ids') {
          _brandsError = 'Una de las marcas ya no está. Cierra y vuelve a '
              'abrir los ajustes.';
        }
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
                  soldOut: _SoldOutBrandsSection(
                    summary: _summary,
                    summaryError: _summaryError,
                    onRetry: _loadSummary,
                    listed: _listed,
                    brandNames: _brandNames,
                    changed: _listedChanged,
                    enabled: canEdit && !_saving,
                    error: _brandsError,
                    onAdd: (id) => setState(() {
                      _brandsError = null;
                      if (!_listed.contains(id)) _listed = [..._listed, id];
                    }),
                    onRemove: (id) => setState(() {
                      _brandsError = null;
                      _listed = [
                        for (final listed in _listed)
                          if (listed != id) listed,
                      ];
                    }),
                  ),
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
    required this.soldOut,
  });

  final CustomerQuoteSettings settings;
  final bool canEdit;
  final _HoursField validity;
  final _HoursField reminder;
  final _HoursField taskDue;
  final _HoursField checkFresh;
  final String? saveError;
  final ValueChanged<_HoursField> onChanged;

  /// «Agotados en la tienda»: qué se ofrece para cotizar sin stock.
  final Widget soldOut;

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
        const SizedBox(height: 22),
        section('Agotados en la tienda'),
        soldOut,
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

/// Qué agotados del sitio se ofrecen: los que se venden a pedido, los que su
/// ficha manda cotizar y los de las marcas de esta lista. El dueño: los
/// premium, «de marcas un poco más reconocidas… es probable que varios
/// proveedores lo tengan»; lo descontinuado o de paso no se ofrece.
class _SoldOutBrandsSection extends StatelessWidget {
  const _SoldOutBrandsSection({
    required this.summary,
    required this.summaryError,
    required this.onRetry,
    required this.listed,
    required this.brandNames,
    required this.changed,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    this.error,
  });

  final CustomerQuoteSoldOutSummary? summary;
  final Object? summaryError;
  final VoidCallback onRetry;
  final List<String> listed;
  final Map<String, String> brandNames;

  /// La lista no es la guardada: el total dice lo que habrá al guardar.
  final bool changed;
  final bool enabled;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final String? error;

  /// Una marca de la lista: su nombre y, si tiene, sus agotados («Shimano ·
  /// 63»). Es una etiqueta, no un botón: sólo su ✕ se toca.
  Widget _brandChip(String id, CustomerQuoteSoldOutBrand? brand) {
    final name = brand?.name ?? brandNames[id] ?? 'Marca';
    final soldOut = brand?.soldOut ?? 0;
    final chip = Semantics(
      label: soldOut > 0 ? '$name, ${_count(soldOut, 'agotado')}' : name,
      excludeSemantics: false,
      child: Chip(
        key: ValueKey('quote-sold-out-brand-$id'),
        label: Text(
          soldOut > 0 ? '$name · $soldOut' : name,
          semanticsLabel: '',
        ),
        onDeleted: enabled ? () => onRemove(id) : null,
        deleteButtonTooltipMessage: 'Quitar $name',
      ),
    );
    return brand == null
        ? chip
        : Tooltip(message: _brandStock(brand), child: chip);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);
    final summary = this.summary;
    final listedSet = listed.toSet();
    final ordered = [...listed]..sort((a, b) {
        final bySoldOut = (summary?.brand(b)?.soldOut ?? 0)
            .compareTo(summary?.brand(a)?.soldOut ?? 0);
        return bySoldOut != 0
            ? bySoldOut
            : (brandNames[a] ?? '')
                .toLowerCase()
                .compareTo((brandNames[b] ?? '').toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary != null)
          _OfferedTotal(
            offered: summary.offeredWith(listedSet),
            soldOut: summary.soldOut,
            changed: changed,
          )
        else if (summaryError != null)
          Row(
            children: [
              Expanded(
                child:
                    Text('No se pudieron contar los agotados.', style: faint),
              ),
              VbButton(
                label: 'Reintentar',
                variant: VbButtonVariant.text,
                onPressed: onRetry,
              ),
            ],
          )
        else
          Text('Contando los agotados del sitio…', style: faint),
        const SizedBox(height: 8),
        Text(
          'Un agotado se puede cotizar si se vende a pedido, si su ficha dice '
          '«Se cotiza» o si su marca está aquí. Conviene listar marcas '
          'reconocidas, que varios proveedores traen; lo descontinuado o de '
          'paso queda fuera.',
          style: faint,
        ),
        const SizedBox(height: 14),
        Text('Marcas que se cotizan sin stock',
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (ordered.isEmpty)
          Text(
            'Ninguna: sólo se cotiza lo que se vende a pedido o lo que su '
            'ficha manda cotizar.',
            style: faint,
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in ordered) _brandChip(id, summary?.brand(id)),
            ],
          ),
        if (enabled && summary != null) ...[
          const SizedBox(height: 12),
          VbSearchableSelect<String>(
            key: const ValueKey('quote-sold-out-brand-add'),
            value: null,
            showLabel: false,
            placeholder: 'Agregar marca',
            semanticLabel: 'Agregar una marca que se cotiza sin stock',
            sheetTitle: 'Agregar marca',
            searchHint: 'Buscar marca…',
            emptyLabel: 'Ninguna marca coincide',
            // By name: by sold-out count the generic brands would lead, the
            // ones the list is meant to leave out.
            options: [
              for (final brand in [...summary.brands]..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                ))
                if (!listedSet.contains(brand.id))
                  VbSearchableSelectOption(
                    value: brand.id,
                    label: brand.name,
                    context: _brandStock(brand),
                  ),
            ],
            onChanged: (id) {
              if (id != null) onAdd(id);
            },
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}

/// «1 agotado», «3 agotados».
String _count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

/// Lo que una marca tiene en la tienda: «18 agotados de 40 publicados» o
/// «Sin agotados · 1 publicado».
String _brandStock(CustomerQuoteSoldOutBrand brand) => brand.soldOut == 0
    ? 'Sin agotados · ${_count(brand.published, 'publicado')}'
    : '${_count(brand.soldOut, 'agotado')} de '
        '${_count(brand.published, 'publicado')}';

/// «163 de 766 agotados se pueden cotizar», con la proporción en una barra.
class _OfferedTotal extends StatelessWidget {
  const _OfferedTotal({
    required this.offered,
    required this.soldOut,
    required this.changed,
  });

  final int offered;
  final int soldOut;
  final bool changed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern('es_CL');
    if (soldOut == 0) {
      return Text(
        'La tienda no tiene agotados publicados.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Semantics(
      container: true,
      label: '${changed ? 'Al guardar, ' : ''}se pueden cotizar '
          '$offered de $soldOut agotados del sitio',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: number.format(offered),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: ' de ${number.format(soldOut)} agotados se pueden '
                    'cotizar${changed ? ' al guardar' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
            ]),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (offered / soldOut).clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
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
