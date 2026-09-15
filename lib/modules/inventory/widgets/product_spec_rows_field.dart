import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../models/product_spec_rows.dart';
import '../models/product_spec_coherence.dart';
import '../models/product_spec_row_conditions.dart';
import '../models/product_spec_template_rules.dart';
import '../utils/spec_rule_evaluator.dart';
import 'product_spec_boolean_field.dart';

/// Edits one configuration at a time inside the existing form section.
/// S-06, I-01, S-04 and A-01 own the controls. The 16 px separation is the
/// F-02/F-04 form stack already sourced in the ficha implementation plan.
class ProductSpecRowsField extends StatefulWidget {
  const ProductSpecRowsField(
      {super.key,
      required this.fieldKey,
      required this.label,
      required this.schema,
      required this.value,
      required this.onChanged,
      this.itemLabel = 'Configuración',
      this.helperText,
      this.conditions,
      Map<String, ProductSpecRowLinkOptions> referenceOptions = const {}})
      : _referenceOptions = referenceOptions;

  final String fieldKey;
  final String label;
  final String itemLabel;
  final String? helperText;
  final ProductSpecRowSchema schema;
  final ProductSpecRowFieldConditions? conditions;
  final Object? value;
  final ValueChanged<Map<String, dynamic>?>? onChanged;
  final Map<String, ProductSpecRowLinkOptions>? _referenceOptions;
  Map<String, ProductSpecRowLinkOptions> get referenceOptions =>
      _referenceOptions ?? const {};

  @override
  State<ProductSpecRowsField> createState() => _ProductSpecRowsFieldState();
}

class _ProductSpecRowsFieldState extends State<ProductSpecRowsField> {
  String? _selectedId;
  final _textControllers = <String, TextEditingController>{};
  final _lastTextValues = <String, String>{};

  TextEditingController _textController(String key, String value) {
    final controller = _textControllers.putIfAbsent(
        key, () => TextEditingController(text: value));
    // Synchronize an external replacement or explicit clear. A local keystroke
    // already records its normalized value, so rebuilding does not move the
    // cursor or discard a decimal separator/space the operator is still typing.
    if (_lastTextValues[key] != value && controller.text != value) {
      controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length));
    }
    _lastTextValues[key] = value;
    return controller;
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>>? get _rows {
    if (widget.value == null) {
      return [];
    }
    final value = widget.value;
    if (value is! Map ||
        value['schema_version'] != widget.schema.version ||
        value['rows'] is! List) {
      return null;
    }
    final rows = value['rows'] as List;
    if (rows.any((row) =>
        row is! Map ||
        row['id'] is! String ||
        row['values'] is! Map ||
        row['sources'] is! List)) {
      return null;
    }
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  void _emit(List<Map<String, dynamic>> rows) =>
      widget.onChanged?.call(rows.isEmpty
          ? null
          : {'schema_version': widget.schema.version, 'rows': rows});

  void _changeCell(String id, String key, Object? value) {
    final rows = _rows;
    if (rows == null || widget.onChanged == null) return;
    final index = rows.indexWhere((row) => row['id'] == id);
    if (index < 0) return;
    final cells = Map<String, dynamic>.from(rows[index]['values'] as Map);
    if (value == null || value is String && value.isEmpty) {
      cells.remove(key);
    } else {
      cells[key] = value;
    }
    rows[index] = {...rows[index], 'values': cells};
    _emit(rows);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      return VbNotice(
          title: widget.label,
          tone: VbNoticeTone.warning,
          body:
              'Estos datos necesitan revisión de formato. Se conservan completos.');
    }
    final selected =
        rows.where((row) => row['id'] == _selectedId).firstOrNull ??
            rows.firstOrNull;
    final id = selected?['id'] as String?;
    final cells =
        Map<String, dynamic>.from(selected?['values'] as Map? ?? const {});
    final enabled = widget.onChanged != null;
    final children = <Widget>[
      Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
      if (widget.helperText != null)
        Text(widget.helperText!, style: Theme.of(context).textTheme.bodySmall),
      if (rows.isNotEmpty)
        VbSearchableSelect<String>(
            key: ValueKey('${widget.fieldKey}-row-selector'),
            value: id,
            label: widget.itemLabel,
            sheetTitle: 'Elegir ${widget.itemLabel.toLowerCase()}',
            options: [
              for (var index = 0; index < rows.length; index++)
                VbSearchableSelectOption(
                    value: rows[index]['id'] as String,
                    label: '${widget.itemLabel} ${index + 1}',
                    context: _summary(rows[index]['values'] as Map)),
            ],
            onChanged: (next) => setState(() => _selectedId = next)),
      if (selected != null) ...[
        for (final column in widget.schema.columns)
          if (widget.conditions?.applicabilityFor(column.key, cells) !=
                  SpecTruth.no ||
              cells.containsKey(column.key))
            _conditionedCell(context, id!, column, cells, enabled),
        VbShortSelect.labelled(
            context,
            'Fuentes de esta configuración',
            TextFormField(
                key: ValueKey('${widget.fieldKey}-$id-sources'),
                enabled: enabled,
                controller: _textController('${widget.fieldKey}-$id-sources',
                    (selected['sources'] as List).join('\n')),
                minLines: 1,
                maxLines: null,
                decoration: const InputDecoration(
                    helperText:
                        'Una URL por línea. Cada fuente acompaña sólo a esta configuración.'),
                onChanged: enabled
                    ? (text) {
                        final updated = _rows!;
                        final index =
                            updated.indexWhere((row) => row['id'] == id);
                        final sources = text
                            .split('\n')
                            .map((source) => source.trim())
                            .where((source) => source.isNotEmpty)
                            .toList();
                        _lastTextValues['${widget.fieldKey}-$id-sources'] =
                            sources.join('\n');
                        updated[index] = {
                          ...updated[index],
                          'sources': sources
                        };
                        _emit(updated);
                      }
                    : null)),
      ],
      if (enabled)
        Wrap(children: [
          VbButton(
              key: ValueKey('${widget.fieldKey}-add-row'),
              label: 'Añadir ${widget.itemLabel.toLowerCase()}',
              icon: Icons.add,
              variant: VbButtonVariant.text,
              onPressed: enabled
                  ? () {
                      final next = const Uuid().v4();
                      setState(() => _selectedId = next);
                      _emit([
                        ...rows,
                        {
                          'id': next,
                          'values': <String, dynamic>{},
                          'sources': <String>[]
                        }
                      ]);
                    }
                  : null),
          if (selected != null)
            VbButton(
                key: ValueKey('${widget.fieldKey}-remove-row'),
                label: 'Retirar ${widget.itemLabel.toLowerCase()}',
                variant: VbButtonVariant.text,
                icon: Icons.remove_circle_outline,
                onPressed: enabled
                    ? () {
                        setState(() => _selectedId = null);
                        _emit(rows.where((row) => row['id'] != id).toList());
                      }
                    : null),
        ]),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(height: 16),
        children[index],
      ],
    ]);
  }

  String _summary(Map values) => widget.schema.columns
          .where((column) => values.containsKey(column.key))
          .take(3)
          .map((column) {
        final reference = widget.referenceOptions[column.key];
        final value = reference == null
            ? values[column.key]
            : reference.choices[values[column.key]] ?? 'Vínculo sin resolver';
        return '${column.label}: ${value is bool ? (value ? 'Sí' : 'No') : value}${column.unit == null ? '' : ' ${column.unit}'}';
      }).join(' · ');

  Widget _conditionedCell(BuildContext context, String id,
      ProductSpecRowColumn column, Map<String, dynamic> cells, bool enabled) {
    final allowed =
        widget.conditions?.applicabilityFor(column.key, cells) ?? SpecTruth.yes;
    final value = cells[column.key];
    final valueIssues = widget.conditions
            ?.validateRow(widget.fieldKey, id, cells)
            .where((issue) =>
                issue.column == column.key &&
                {'row_value_pending', 'row_value_conflict'}
                    .contains(issue.code))
            .toList() ??
        const <ProductSpecRowConditionIssue>[];
    Set<Object>? confirmedChoices;
    if (column.type == 'boolean' || column.type == 'token') {
      for (final rule in widget.conditions?.valueWhen[column.key] ??
          const <ProductSpecRowValueRule>[]) {
        if (evaluateProductSpecTemplateCondition(rule.when, cells) !=
            SpecTruth.yes) {
          continue;
        }
        final expected = <Object>{rule.expected};
        confirmedChoices = confirmedChoices == null
            ? expected
            : confirmedChoices.intersection(expected);
      }
    }
    final control = _cell(
        context, id, column, value, enabled && allowed == SpecTruth.yes,
        conditionalChoices: confirmedChoices,
        errorText:
            valueIssues.where((issue) => issue.blocking).firstOrNull?.message,
        helperText:
            valueIssues.where((issue) => !issue.blocking).firstOrNull?.message);
    if (allowed == SpecTruth.yes) return control;
    final dependencies = widget.conditions!
        .dependenciesFor(column.key)
        .map((key) =>
            widget.schema.columns.firstWhere((c) => c.key == key).label)
        .join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      control,
      Text(
          allowed == SpecTruth.no
              ? 'Este dato no corresponde a los requisitos elegidos. Se conserva para revisarlo.'
              : 'Define primero $dependencies en esta configuración.',
          style: Theme.of(context).textTheme.bodySmall),
      if (enabled && value != null)
        VbButton(
            key: ValueKey('${widget.fieldKey}-$id-${column.key}-clear'),
            label: 'Retirar dato',
            variant: VbButtonVariant.text,
            onPressed: () => _changeCell(id, column.key, null)),
    ]);
  }

  Widget _cell(BuildContext context, String id, ProductSpecRowColumn column,
      Object? value, bool enabled,
      {Set<Object>? conditionalChoices,
      String? errorText,
      String? helperText}) {
    final key = ValueKey('${widget.fieldKey}-$id-${column.key}');
    final scopedOptions = widget.conditions?.allowedOptions[column.key];
    final reference = widget.referenceOptions[column.key];
    if (reference != null) {
      final unresolved = value != null && !reference.choices.containsKey(value);
      final outsideScope = value != null &&
          scopedOptions != null &&
          !scopedOptions.contains(value);
      final choices = reference.choices.entries
          .where((entry) =>
              scopedOptions == null || scopedOptions.contains(entry.key))
          .toList();
      return VbSearchableSelect<String>(
          key: key,
          label: column.label,
          value: value as String?,
          sheetTitle: 'Elegir de ${reference.label}',
          placeholder: unresolved ? 'Vínculo sin resolver' : 'Sin dato',
          helperText: helperText ??
              (reference.choices.isEmpty
                  ? 'Define primero ${reference.label}.'
                  : null),
          errorText: errorText ??
              reference.error ??
              (outsideScope
                  ? 'La opción conservada no pertenece a esta ficha.'
                  : unresolved && reference.choices.isNotEmpty
                      ? 'La configuración vinculada no existe en esta ficha.'
                      : null),
          allowClear: true,
          clearLabel: 'Sin vínculo',
          options: [
            for (final entry in choices)
              VbSearchableSelectOption(value: entry.key, label: entry.value)
          ],
          onChanged: enabled && (choices.isNotEmpty || value != null)
              ? (next) => _changeCell(id, column.key, next)
              : null);
    }
    if (column.type == 'boolean') {
      return ProductSpecBooleanField(
          key: key,
          label: column.label,
          value: value is bool ? value : null,
          allowedValues: conditionalChoices?.cast<bool>(),
          helperText: helperText,
          errorText: errorText,
          onChanged:
              enabled ? (next) => _changeCell(id, column.key, next) : null);
    }
    if (column.type == 'token' &&
        (scopedOptions != null ||
            column.allowedValues.isNotEmpty ||
            conditionalChoices != null)) {
      final choices = (scopedOptions ??
              (column.allowedValues.isNotEmpty
                  ? column.allowedValues
                  : conditionalChoices!.cast<String>().toList()))
          .where((choice) =>
              conditionalChoices == null || conditionalChoices.contains(choice))
          .toList();
      return VbSearchableSelect<String>(
          key: key,
          label: column.label,
          value: value as String?,
          sheetTitle: column.label,
          allowClear: true,
          clearLabel: 'Sin dato',
          helperText: helperText,
          errorText: errorText ??
              (value != null && !choices.contains(value)
                  ? 'La opción conservada no pertenece a esta ficha.'
                  : null),
          options: choices
              .map((option) =>
                  VbSearchableSelectOption(value: option, label: option))
              .toList(),
          onChanged:
              enabled ? (next) => _changeCell(id, column.key, next) : null);
    }
    final numeric = column.type == 'decimal' || column.type == 'integer';
    return VbShortSelect.labelled(
        context,
        column.label,
        TextFormField(
            key: key,
            enabled: enabled,
            controller: _textController(key.value, value?.toString() ?? ''),
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(
                    decimal: true, signed: true)
                : TextInputType.text,
            decoration: InputDecoration(
                suffixText: column.unit,
                errorText: errorText,
                helperText: helperText),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (text) {
              if (text == null || text.trim().isEmpty) return null;
              try {
                column.validate(numeric ? text.replaceAll(',', '.') : text);
              } on FormatException catch (error) {
                return error.message;
              }
              return null;
            },
            onChanged: enabled
                ? (text) {
                    final next =
                        numeric ? text.replaceAll(',', '.') : text.trim();
                    _lastTextValues[key.value] = next;
                    _changeCell(id, column.key, next);
                  }
                : null));
  }
}
