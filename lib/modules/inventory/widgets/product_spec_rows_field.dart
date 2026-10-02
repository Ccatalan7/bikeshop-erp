import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../models/product_spec_rows.dart';
import '../models/product_spec_coherence.dart';
import '../models/product_spec_row_conditions.dart';
import '../models/product_spec_template_rules.dart';
import '../utils/spec_rule_evaluator.dart';
import 'product_spec_boolean_field.dart';

/// A table datum of the technical sheet: every item listed with what it
/// holds, the open one edited in a grid (2026-10-01). Item ids, sources and
/// absent cells are preserved exactly; this widget only arranges them.
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
      this.showLabel = true,
      this.conditions,
      Map<String, Map<String, String>> tokenLabels = const {},
      Map<String, ProductSpecRowLinkOptions> referenceOptions = const {}})
      : _referenceOptions = referenceOptions,
        _tokenLabels = tokenLabels;

  final String fieldKey;
  final String label;
  final String itemLabel;
  final String? helperText;

  /// A host that names the datum itself (the technical sheet's row) hides
  /// the title here.
  final bool showLabel;
  final ProductSpecRowSchema schema;
  final ProductSpecRowFieldConditions? conditions;
  final Object? value;
  final ValueChanged<Map<String, dynamic>?>? onChanged;
  final Map<String, ProductSpecRowLinkOptions>? _referenceOptions;
  Map<String, ProductSpecRowLinkOptions> get referenceOptions =>
      _referenceOptions ?? const {};
  final Map<String, Map<String, String>>? _tokenLabels;
  Map<String, Map<String, String>> get tokenLabels => _tokenLabels ?? const {};

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
    final theme = Theme.of(context);
    // Nothing chosen yet opens the first item; an empty id means the
    // operator closed them all.
    final selectedId = _selectedId == ''
        ? null
        : (rows.where((row) => row['id'] == _selectedId).firstOrNull ??
            rows.firstOrNull)?['id'] as String?;
    final enabled = widget.onChanged != null;
    final children = <Widget>[
      if (widget.showLabel)
        Text(widget.label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      if (widget.helperText != null)
        Text(widget.helperText!, style: theme.textTheme.bodySmall),
      if (rows.isEmpty)
        Text('Sin ${widget.itemLabel.toLowerCase()} todavía.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      for (var index = 0; index < rows.length; index++)
        _rowTile(context, rows, index,
            open: rows[index]['id'] == selectedId, enabled: enabled),
      if (enabled)
        Align(
          alignment: Alignment.centerLeft,
          child: VbButton(
              key: ValueKey('${widget.fieldKey}-add-row'),
              label: 'Añadir ${widget.itemLabel.toLowerCase()}',
              icon: Icons.add,
              variant: VbButtonVariant.text,
              onPressed: () {
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
              }),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(height: 10),
        children[index],
      ],
    ]);
  }

  /// One item of the table: its number and what it holds on one line, and,
  /// when open, its data in a grid. Every item stays visible; the old editor
  /// showed one at a time behind a «Configuración 1» dropdown, as a column of
  /// full-width boxes (owner, 2026-10-01: «está todo mal organizado»).
  Widget _rowTile(
      BuildContext context, List<Map<String, dynamic>> rows, int index,
      {required bool open, required bool enabled}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hairline = VinabikeThemeRoles.of(context).hairline;
    final row = rows[index];
    final id = row['id'] as String;
    final cells = Map<String, dynamic>.from(row['values'] as Map);
    final title = '${widget.itemLabel} ${index + 1}';
    final summary = _summary(cells);
    final header = Semantics(
      button: true,
      expanded: open,
      label: '$title: ${summary.isEmpty ? 'sin datos' : summary}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('${widget.fieldKey}-row-$id'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selectedId = open ? '' : id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            Text(title,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(summary.isEmpty ? 'Sin datos todavía' : summary,
                  maxLines: open ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            Icon(open ? Icons.expand_less : Icons.expand_more,
                size: 20, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: open ? scheme.outline : hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cellGrid(context, [
                    for (final column in widget.schema.columns)
                      if (widget.conditions
                                  ?.applicabilityFor(column.key, cells) !=
                              SpecTruth.no ||
                          cells.containsKey(column.key))
                        _labelled(
                            context,
                            column.label,
                            _conditionedCell(
                                context, id, column, cells, enabled)),
                  ]),
                  const SizedBox(height: 14),
                  _labelled(
                      context,
                      'Fuentes',
                      TextFormField(
                          key: ValueKey('${widget.fieldKey}-$id-sources'),
                          enabled: enabled,
                          controller: _textController(
                              '${widget.fieldKey}-$id-sources',
                              (row['sources'] as List).join('\n')),
                          minLines: 1,
                          maxLines: null,
                          style: theme.textTheme.bodyMedium,
                          decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Una URL por línea (opcional)'),
                          onChanged: enabled
                              ? (text) {
                                  final updated = _rows!;
                                  final at = updated
                                      .indexWhere((row) => row['id'] == id);
                                  final sources = text
                                      .split('\n')
                                      .map((source) => source.trim())
                                      .where((source) => source.isNotEmpty)
                                      .toList();
                                  _lastTextValues[
                                          '${widget.fieldKey}-$id-sources'] =
                                      sources.join('\n');
                                  updated[at] = {
                                    ...updated[at],
                                    'sources': sources
                                  };
                                  _emit(updated);
                                }
                              : null)),
                  if (enabled)
                    Align(
                      alignment: Alignment.centerRight,
                      child: VbButton(
                          key: ValueKey('${widget.fieldKey}-remove-row'),
                          label: 'Retirar ${widget.itemLabel.toLowerCase()}',
                          variant: VbButtonVariant.text,
                          icon: Icons.remove_circle_outline,
                          onPressed: () {
                            setState(() => _selectedId = null);
                            _emit(
                                rows.where((row) => row['id'] != id).toList());
                          }),
                    ),
                ]),
          ),
      ]),
    );
  }

  /// The open item's data side by side: three to a line on a desktop, two on
  /// a tablet, one on a phone.
  Widget _cellGrid(BuildContext context, List<Widget> cells) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perLine = width >= 840
            ? 3
            : width >= 520
                ? 2
                : 1;
        const gap = 16.0;
        final cellWidth = (width - gap * (perLine - 1)) / perLine;
        return Wrap(spacing: gap, runSpacing: 14, children: [
          for (final cell in cells) SizedBox(width: cellWidth, child: cell),
        ]);
      });

  Widget _labelled(BuildContext context, String label, Widget control) {
    final theme = Theme.of(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface)),
          const SizedBox(height: 6),
          control,
        ]);
  }

  /// What an item holds, on one line: its values in column order, a yes/no
  /// with the name of what it answers.
  String _summary(Map values) => widget.schema.columns
          .where((column) => values.containsKey(column.key))
          .take(4)
          .map((column) {
        final reference = widget.referenceOptions[column.key];
        final labels = widget.tokenLabels[column.key];
        final value = reference == null
            ? labels == null
                ? (column.type == 'token' && values[column.key] is String
                    ? _tokenText(values[column.key] as String)
                    : values[column.key])
                : labels[values[column.key]] ??
                    'Nombre no disponible · ${values[column.key]}'
            : reference.choices[values[column.key]] ?? 'Vínculo sin resolver';
        if (value is bool) return '${column.label}: ${value ? 'Sí' : 'No'}';
        return '$value${column.unit == null ? '' : ' ${column.unit}'}';
      }).join(' · ');

  /// A stored token written as plain lowercase words («manilla», «cáliper»)
  /// reads with its first letter up; codes and names keep their spelling.
  static String _tokenText(String token) =>
      RegExp(r'^[a-záéíóúñü][a-záéíóúñü ]*$').hasMatch(token)
          ? '${token[0].toUpperCase()}${token.substring(1)}'
          : token;

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
            '«${widget.schema.columns.firstWhere((c) => c.key == key).label}»')
        .join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      control,
      Text(
          allowed == SpecTruth.no
              ? 'Este dato no corresponde a los requisitos elegidos. Se conserva para revisarlo.'
              : 'Se habilita cuando completes $dependencies.',
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
          showLabel: false,
          semanticLabel: column.label,
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
          showLabel: false,
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
      final labels = widget.tokenLabels[column.key];
      final missingNames = labels != null &&
          choices.any((choice) => !labels.containsKey(choice));
      return VbSearchableSelect<String>(
          key: key,
          label: column.label,
          showLabel: false,
          semanticLabel: column.label,
          value: value as String?,
          sheetTitle: column.label,
          allowClear: true,
          clearLabel: 'Sin dato',
          placeholder:
              value != null && labels != null && !labels.containsKey(value)
                  ? 'Nombre no disponible · $value'
                  : null,
          helperText: helperText ??
              (missingNames
                  ? 'Algunos nombres no están disponibles. Las opciones y tu selección se conservan.'
                  : null),
          errorText: errorText ??
              (value != null && !choices.contains(value)
                  ? 'La opción conservada no pertenece a esta ficha.'
                  : null),
          options: choices
              .map((option) => VbSearchableSelectOption(
                  value: option,
                  label: labels == null
                      ? _tokenText(option)
                      : labels[option] ?? 'Nombre no disponible · $option'))
              .toList(),
          onChanged:
              enabled ? (next) => _changeCell(id, column.key, next) : null);
    }
    final numeric = column.type == 'decimal' || column.type == 'integer';
    return Semantics(
        label: column.label,
        child: TextFormField(
            key: key,
            enabled: enabled,
            controller: _textController(key.value, value?.toString() ?? ''),
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(
                    decimal: true, signed: true)
                : TextInputType.text,
            decoration: InputDecoration(
                isDense: true,
                hintText: 'Sin dato',
                suffixText: column.unit,
                errorText: errorText,
                helperText: helperText,
                helperMaxLines: 3,
                errorMaxLines: 4),
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
