import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/authority_scoped_cache.dart';
import '../../../shared/widgets/vb_form_section.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../models/product_spec_contract.dart';
import '../models/product_spec_member_draft.dart';
import '../models/product_spec_member_profile.dart';
import '../models/product_spec_rows.dart';
import '../services/spec_engine_service.dart';
import '../utils/spec_rule_evaluator.dart';

typedef ProductSpecMemberTemplateLoader = Future<SpecTemplate> Function({
  required String parentTemplateId,
  required String collectionDefinitionId,
  required String familyKey,
});

/// The same family fields used by the root editor, scoped to a selected piece.
/// S-06/I-01 and F-02/F-04 own controls and spacing. No inventory child is made.
class ProductSpecMemberEditor extends StatefulWidget {
  const ProductSpecMemberEditor({
    super.key,
    required this.drafts,
    required this.parentTemplate,
    required this.parentValues,
    required this.collections,
    required this.loadTemplate,
    required this.loadReferences,
    required this.buildFields,
    required this.onChanged,
    required this.onAuthorityChanged,
    this.enabled = true,
  });

  final ProductSpecMemberDrafts drafts;
  final SpecTemplate? parentTemplate;
  final Map<String, dynamic> parentValues;
  final List<ProductSpecMemberCollection> collections;
  final ProductSpecMemberTemplateLoader loadTemplate;
  final Future<List<ProductSpecReference>> Function(String family)
      loadReferences;
  final List<Widget> Function(ProductSpecMemberDraft draft, int generation)
      buildFields;
  final VoidCallback onChanged;
  final VoidCallback onAuthorityChanged;
  final bool enabled;

  @override
  State<ProductSpecMemberEditor> createState() =>
      _ProductSpecMemberEditorState();
}

class _MemberRow {
  const _MemberRow(this.collection, this.row);
  final ProductSpecMemberCollection collection;
  final ProductSpecRow row;
  String get key => 'row:${collection.definitionId}:${row.id}';
}

class _ProductSpecMemberEditorState extends State<ProductSpecMemberEditor> {
  String? _selected;
  String? _loadingRow;
  String? _error;
  int _request = 0;
  int _generation = 0;
  bool _authorityChanged = false;
  bool get _enabled => widget.enabled && !_authorityChanged;
  final _references = <String, List<ProductSpecReference>>{};
  final _referenceErrors = <String, String>{};
  final _referenceLoading = <String>{};
  final _knownTemplates = <String, SpecTemplate>{};
  final _mpn = <String, TextEditingController>{};

  @override
  void didUpdateWidget(covariant ProductSpecMemberEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.drafts, widget.drafts)) {
      // A confirmed receipt supplies new persisted identities and revisions.
      _request++;
      _loadingRow = null;
      _referenceLoading.clear();
      _references.clear();
      _referenceErrors.clear();
      _generation++;
      _authorityChanged = false;
      _error = null;
      for (final controller in _mpn.values) {
        controller.dispose();
      }
      _mpn.clear();
    }
  }

  @override
  void dispose() {
    _request++;
    for (final controller in _mpn.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<_MemberRow> _rows() {
    final parent = widget.parentTemplate;
    if (parent == null) return const [];
    return [
      for (final collection in widget.collections)
        if (widget.parentValues[collection.fieldKey] != null)
          for (final row in parent.fields
              .firstWhere(
                  (field) => field.specDefinitionId == collection.definitionId)
              .definition!
              .rowSchema!
              .parse(widget.parentValues[collection.fieldKey])
              .rows)
            _MemberRow(collection, row),
    ];
  }

  String _title(Map<String, dynamic> identity) {
    final model = ['identity_brand', 'identity_model']
        .map((key) => identity[key])
        .where(hasKnownSpecValue)
        .join(' ');
    final position = ['member_role', 'position']
        .map((key) => identity[key])
        .where(hasKnownSpecValue)
        .join(' · ');
    return [
      if (model.isNotEmpty) model,
      if (position.isNotEmpty) position,
      if (!hasKnownSpecValue(identity['identity_model']))
        'modelo sin confirmar',
    ].join(' · ').ifEmpty('Pieza sin identificar');
  }

  String? _bindingError(ProductSpecMemberDraft draft) {
    if (widget.parentTemplate == null) {
      return 'La ficha del producto cambió. Archiva esta ficha para conservar sus datos antes de guardar.';
    }
    try {
      draft.buildUpsert(
          parentTemplate: widget.parentTemplate!,
          parentValues: widget.parentValues);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  void _change(VoidCallback change) {
    try {
      change();
      setState(() => _error = null);
      widget.onChanged();
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  void _sessionChanged() {
    setState(() {
      _authorityChanged = true;
      _request++;
      _loadingRow = null;
      _referenceLoading.clear();
      _error = 'La sesión cambió. Vuelve a abrir el producto.';
    });
    widget.onAuthorityChanged();
  }

  Future<void> _create(_MemberRow selected) async {
    final parent = widget.parentTemplate!;
    final owner = widget.drafts;
    final family = selected.row.values[selected.collection.familyColumn];
    if (family is! String ||
        !selected.collection.familyOptions.contains(family)) {
      return;
    }
    final identity = jsonEncode(selected.row.values);
    final sources = jsonEncode(selected.row.sources);
    final request = ++_request;
    setState(() {
      _loadingRow = selected.key;
      _error = null;
    });
    try {
      final template = await widget.loadTemplate(
          parentTemplateId: parent.id,
          collectionDefinitionId: selected.collection.definitionId,
          familyKey: family);
      if (!mounted || request != _request || !identical(owner, widget.drafts)) {
        return;
      }
      final current =
          _rows().where((row) => row.key == selected.key).firstOrNull;
      if (!_enabled ||
          widget.parentTemplate?.id != parent.id ||
          widget.parentTemplate?.contractVersion != parent.contractVersion ||
          current == null ||
          jsonEncode(current.row.values) != identity ||
          jsonEncode(current.row.sources) != sources) {
        throw const FormatException(
            'La pieza cambió durante la carga. Revisa sus datos antes de crear la ficha.');
      }
      final draft = ProductSpecMemberDraft.forRow(
          id: const Uuid().v4(),
          collection: current.collection,
          parentTemplate: widget.parentTemplate!,
          template: template,
          parentValues: widget.parentValues,
          rowId: current.row.id);
      owner.add(draft);
      setState(() => _selected = 'profile:${draft.id}');
      widget.onChanged();
      _loadReferences(draft);
    } on AuthorityScopeChangedException {
      if (mounted && request == _request) _sessionChanged();
    } on FormatException catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error =
            'No se pudo cargar la ficha de esta pieza. Reintenta la carga.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loadingRow = null);
    }
  }

  Future<void> _loadReferences(ProductSpecMemberDraft draft) async {
    if (_referenceLoading.contains(draft.id)) return;
    final owner = widget.drafts;
    setState(() {
      _referenceLoading.add(draft.id);
      _referenceErrors.remove(draft.id);
    });
    try {
      final references =
          await widget.loadReferences(draft.template.technicalFamily);
      if (mounted && identical(owner, widget.drafts)) {
        setState(() => _references[draft.id] = references);
      }
    } on AuthorityScopeChangedException {
      if (mounted && identical(owner, widget.drafts)) _sessionChanged();
    } catch (_) {
      if (mounted && identical(owner, widget.drafts)) {
        setState(() => _referenceErrors[draft.id] =
            'No se pudieron cargar las referencias. Los datos de la pieza se conservan.');
      }
    } finally {
      if (mounted && identical(owner, widget.drafts)) {
        setState(() => _referenceLoading.remove(draft.id));
      }
    }
  }

  Widget _source(String source) => TextButton(
      onPressed: () =>
          launchUrl(Uri.parse(source), mode: LaunchMode.externalApplication),
      child: Text('Fuente: ${Uri.parse(source).host}'));

  List<Widget> _profile(ProductSpecMemberDraft draft, List<_MemberRow> rows) {
    final mpn = _mpn.putIfAbsent(draft.id,
        () => TextEditingController(text: draft.manufacturerSku ?? ''));
    final sameRows = rows
        .where((candidate) =>
            candidate.collection.definitionId ==
                draft.collection.definitionId &&
            candidate.row.id != draft.memberRowId &&
            widget.drafts.forRow(
                    candidate.collection.definitionId, candidate.row.id) ==
                null &&
            mapEquals(draft.identity, {
              for (final key in [
                draft.collection.familyColumn,
                ...draft.collection.identityColumns
              ])
                if (candidate.row.values.containsKey(key))
                  key: candidate.row.values[key]
            }))
        .toList();
    final currentReference = draft.reference;
    final choices = <String, ProductSpecReference>{
      for (final reference in _references[draft.id] ?? <ProductSpecReference>[])
        if (reference.family == draft.template.technicalFamily &&
            reference.matchesIdentity(
                brand: draft.identity['identity_brand'] ?? '',
                model: draft.identity['identity_model'] ?? '',
                manufacturerSku: draft.manufacturerSku ?? ''))
          reference.id: reference,
      if (currentReference != null) currentReference.id: currentReference,
    };
    return [
      VbFormSection(title: draft.template.name, children: [
        Text(_title(draft.identity)),
        const Text(
            'La identificación y sus fuentes corresponden a la pieza registrada en Contenido.'),
        for (final source in draft.identitySources) _source(source),
        const SizedBox(height: 16),
        VbShortSelect.labelled(
            context,
            'Código del fabricante de la pieza (MPN)',
            TextFormField(
                key: ValueKey('member-mpn-${draft.id}'),
                controller: mpn,
                enabled: _enabled && draft.manufacturerSku == null,
                decoration: const InputDecoration(
                    helperMaxLines: 5,
                    helperText:
                        'Confirma el código con una fuente en la fila de Contenido. Un código ya confirmado pertenece a esta pieza.'))),
        TextButton(
            key: ValueKey('member-identify-${draft.id}'),
            onPressed: !_enabled || widget.parentTemplate == null
                ? null
                : () => _change(() {
                      draft.identify(
                          parentTemplate: widget.parentTemplate!,
                          parentValues: widget.parentValues,
                          manufacturerSku: mpn.text);
                      draft.selectReference(draft.reference);
                      _generation++;
                    }),
            child: const Text('Confirmar identificación de la pieza')),
        if (sameRows.isNotEmpty)
          VbSearchableSelect<String>(
              key: ValueKey('member-rebind-${draft.id}'),
              value: null,
              label: 'Vincular a otra fila de la misma pieza',
              sheetTitle: 'Elegir la fila que conserva esta identidad',
              options: [
                for (final candidate in sameRows)
                  VbSearchableSelectOption(
                      value: candidate.row.id,
                      label: _title(candidate.row.values),
                      context: _rowLocation(candidate, rows))
              ],
              onChanged: !_enabled
                  ? null
                  : (rowId) {
                      if (rowId != null) {
                        _change(() => draft.rebind(
                            parentTemplate: widget.parentTemplate!,
                            parentValues: widget.parentValues,
                            rowId: rowId));
                      }
                    }),
        const SizedBox(height: 16),
        if (!_references.containsKey(draft.id))
          TextButton(
              key: ValueKey('member-load-references-${draft.id}'),
              onPressed: !_enabled || _referenceLoading.contains(draft.id)
                  ? null
                  : () => _loadReferences(draft),
              child: Text(_referenceLoading.contains(draft.id)
                  ? 'Cargando referencias…'
                  : 'Buscar referencias del fabricante')),
        if (_referenceErrors[draft.id] != null)
          VbNotice(
              title: 'Referencias pendientes de cargar',
              body: _referenceErrors[draft.id],
              tone: VbNoticeTone.warning),
        VbSearchableSelect<String>(
            key: ValueKey('member-reference-${draft.id}'),
            value: draft.reference?.id,
            label: 'Referencia del fabricante de la pieza',
            sheetTitle: 'Elegir referencia de esta pieza',
            allowClear: true,
            clearLabel: 'Sin referencia · completar manualmente',
            helperText:
                'Confirma el modelo y el MPN para ver las referencias de esa variante. Al retirar la referencia se conservan las respuestas manuales.',
            options: [
              for (final reference in choices.values)
                VbSearchableSelectOption(
                    value: reference.id,
                    label: reference.label,
                    context: reference.manufacturerSku == null
                        ? 'Referencia del modelo'
                        : 'MPN: ${reference.manufacturerSku}',
                    searchText: reference.manufacturerSku)
            ],
            onChanged: !_enabled
                ? null
                : (id) => _change(() {
                      draft.selectReference(choices[id]);
                      _generation++;
                    })),
        if (draft.reference != null) ...[
          for (final entry in draft.reference!.facts.entries)
            if (draft.template.fields
                .any((f) => f.definition?.key == entry.key))
              Text(
                  '${draft.template.labelFor(entry.key)}: ${_value(entry.value)}'),
          for (final claim in draft.reference!.claims)
            Text(productSpecClaimSummary(claim)),
          for (final source in draft.reference!.sources) _source(source),
        ],
        TextButton(
            key: ValueKey('member-archive-${draft.id}'),
            onPressed: !_enabled
                ? null
                : () => _change(() {
                      widget.drafts.archive(draft.id);
                      _selected = null;
                    }),
            child: Text(draft.persisted
                ? 'Archivar ficha de esta pieza'
                : 'Retirar ficha sin guardar')),
      ]),
      const SizedBox(height: 16),
      ...widget.buildFields(draft, _generation),
    ];
  }

  String _rowLocation(_MemberRow row, List<_MemberRow> rows) {
    final inCollection = rows
        .where((candidate) =>
            candidate.collection.definitionId == row.collection.definitionId)
        .toList();
    final position =
        inCollection.indexWhere((entry) => entry.key == row.key) + 1;
    final label =
        widget.parentTemplate?.labelFor(row.collection.fieldKey) ?? 'Contenido';
    return '$label · configuración $position';
  }

  String _selectionContext(String key, List<_MemberRow> rows) {
    final profile = widget.drafts.active
        .where((draft) => key == 'profile:${draft.id}')
        .firstOrNull;
    final row = rows
        .where((row) => profile == null
            ? key == row.key
            : row.collection.definitionId == profile.collection.definitionId &&
                row.row.id == profile.memberRowId)
        .firstOrNull;
    return '${profile == null ? 'Sin ficha' : 'Con ficha'} · '
        '${row == null ? 'pieza ya no incluida' : _rowLocation(row, rows)}';
  }

  String _archivedLabel(ProductSpecArchivedMemberProfile archive, String key) {
    final definition = _knownTemplates[archive.record.templateId]
        ?.fields
        .map((field) => field.definition)
        .where((definition) =>
            definition?.key == key &&
            archive.record.factPayload.containsKey(definition!.id))
        .firstOrNull;
    return definition?.label ?? 'Dato anterior sin etiqueta disponible';
  }

  String _archivedDate(String value) {
    final date = DateTime.parse(value).toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatFullDate(date)} · '
        '${labels.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  String _value(Object? value) => value == true
      ? 'Sí'
      : value == false
          ? 'No'
          : value is List
              ? value.map(_value).join(', ')
              : value is Map
                  ? const JsonEncoder.withIndent('  ').convert(value)
                  : value?.toString() ?? 'Sin confirmar';

  @override
  Widget build(BuildContext context) {
    List<_MemberRow> rows = const [];
    String? rowsError;
    try {
      rows = _rows();
    } on FormatException catch (error) {
      rowsError = error.message;
    }
    final active = widget.drafts.active;
    for (final profile in widget.drafts.source.profiles) {
      _knownTemplates[profile.template.id] = profile.template;
    }
    for (final draft in [...active, ...widget.drafts.archiving]) {
      _knownTemplates[draft.template.id] = draft.template;
    }
    final choices = <String, String>{
      for (final draft in active) 'profile:${draft.id}': _title(draft.identity),
      for (final row in rows)
        if (widget.drafts.forRow(row.collection.definitionId, row.row.id) ==
            null)
          row.key: _title(row.row.values),
    };
    final selected =
        choices.containsKey(_selected) ? _selected : choices.keys.firstOrNull;
    final profile =
        active.where((draft) => 'profile:${draft.id}' == selected).firstOrNull;
    final newRow = rows.where((row) => row.key == selected).firstOrNull;
    final family = newRow?.row.values[newRow.collection.familyColumn];
    final familyReady =
        family is String && newRow!.collection.familyOptions.contains(family);
    final issues = <String>[
      if (rowsError != null) rowsError,
      if (rowsError == null)
        for (final draft in active)
          if (_bindingError(draft) case final String issue)
            '${_title(draft.identity)}: $issue',
    ];
    final archived = widget.drafts.source.archivedProfiles;
    if (choices.isEmpty &&
        widget.collections.isEmpty &&
        widget.drafts.archiving.isEmpty &&
        archived.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      VbFormSection(title: 'Fichas de las piezas incluidas', children: [
        const Text(
            'Cada pieza conserva su identificación y sus propios datos. Completa primero las piezas incluidas en Contenido; sus fichas se guardan junto al producto.'),
        if (issues.isNotEmpty)
          VbNotice(
              title: 'Revisa las piezas antes de guardar',
              body: issues.join('\n'),
              tone: VbNoticeTone.danger),
        if (_error != null)
          VbNotice(
              title: 'Revisa esta acción',
              body: _error,
              tone: VbNoticeTone.warning),
        const SizedBox(height: 16),
        if (choices.isNotEmpty)
          VbSearchableSelect<String>(
              key: const ValueKey('member-selection'),
              label: 'Pieza incluida',
              sheetTitle: 'Elegir pieza',
              value: selected,
              options: [
                for (final entry in choices.entries)
                  VbSearchableSelectOption(
                      value: entry.key,
                      label: entry.value,
                      context: _selectionContext(entry.key, rows))
              ],
              onChanged: !_enabled
                  ? null
                  : (value) => setState(() {
                        _selected = value;
                        _error = null;
                      })),
        if (newRow != null) ...[
          if (!familyReady)
            const Text(
                'Confirma la familia de esta pieza en Contenido antes de crear su ficha.'),
          TextButton(
              key: ValueKey('member-create-${newRow.key}'),
              onPressed: !_enabled || !familyReady || _loadingRow != null
                  ? null
                  : () => _create(newRow),
              child: Text(_loadingRow == newRow.key
                  ? 'Cargando ficha…'
                  : 'Crear ficha de esta pieza')),
        ],
        if (choices.isEmpty)
          const Text('Todavía no hay piezas incluidas para completar.'),
        for (final draft in widget.drafts.archiving)
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(
                '${_title(draft.identity)} · ${draft.persisted ? 'Se archivará al guardar' : 'Ficha sin guardar retirada'}'),
            TextButton(
                key: ValueKey('member-undo-${draft.id}'),
                onPressed: !_enabled
                    ? null
                    : () => _change(() => widget.drafts.undoArchive(draft.id)),
                child: const Text('Deshacer')),
          ]),
      ]),
      const SizedBox(height: 16),
      if (profile != null) ..._profile(profile, rows),
      if (archived.isNotEmpty) ...[
        VbFormSection(title: 'Fichas archivadas', children: [
          const Text(
              'Se conservan como historial. Sus datos no describen las piezas actuales.'),
          for (final archive in archived)
            ExpansionTile(
                key: ValueKey('member-history-${archive.id}'),
                title: Text(_title(archive.record.memberIdentity)),
                subtitle: Text(
                    'Archivada el ${_archivedDate(archive.archivedAt)} · ${archive.values.length} datos conservados'),
                children: [
                  for (final entry in archive.values.entries)
                    ListTile(
                        title: Text(_archivedLabel(archive, entry.key)),
                        subtitle: Text(_value(entry.value))),
                  for (final source in archive.record.identitySources)
                    _source(source),
                  for (final source
                      in archive.record.reference?.sources ?? <String>[])
                    _source(source),
                ]),
        ]),
        const SizedBox(height: 16),
      ],
    ]);
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
