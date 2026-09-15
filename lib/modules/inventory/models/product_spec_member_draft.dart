import 'dart:convert';

import '../services/spec_engine_service.dart';
import '../utils/product_spec_inference_utils.dart';
import '../utils/spec_rule_evaluator.dart';
import 'product_spec_contract.dart';
import 'product_spec_member_profile.dart';
import 'product_spec_rows.dart';

/// One component's unsaved changes. Neither row selection nor a parent edit
/// can silently change the identity to which its observations belong.
class ProductSpecMemberDraft {
  ProductSpecMemberDraft._({
    required this.id,
    required this.collection,
    required this.template,
    required String memberRowId,
    required Map<String, String> identity,
    required List<String> identitySources,
    required Map<String, dynamic> values,
    required this.persisted,
    ProductSpecReference? reference,
    String? manufacturerSku,
    List<String> catalogKeys = const [],
  })  : _memberRowId = memberRowId,
        _reference = reference,
        _manufacturerSku = _sku(manufacturerSku),
        _autoValues = {
          for (final key in catalogKeys)
            if (reference?.facts.containsKey(key) == true) key: values[key]
        },
        _identity = Map.unmodifiable(identity),
        _identitySources = List.unmodifiable(identitySources),
        _values = _copy(values);

  factory ProductSpecMemberDraft.fromProfile(
          ProductSpecMemberProfile profile) =>
      ProductSpecMemberDraft._(
        id: profile.id,
        collection: profile.collection,
        template: profile.template,
        memberRowId: profile.memberRowId,
        identity: profile.record.memberIdentity,
        identitySources: profile.record.identitySources,
        values: profile.values,
        persisted: true,
        reference: profile.record.reference,
        manufacturerSku: profile.record.manufacturerSku,
        catalogKeys: profile.record.catalogKeys,
      );

  factory ProductSpecMemberDraft.forRow({
    required String id,
    required ProductSpecMemberCollection collection,
    required SpecTemplate parentTemplate,
    required SpecTemplate template,
    required Map<String, dynamic> parentValues,
    required String rowId,
  }) {
    if (!RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(id)) {
      throw const FormatException('Identificador de ficha inválido.');
    }
    final row = _row(collection, parentTemplate, parentValues, rowId);
    if (row.values[collection.familyColumn] != template.key) {
      throw const FormatException(
          'La ficha no corresponde a la familia de la pieza.');
    }
    return ProductSpecMemberDraft._(
        id: id,
        collection: collection,
        template: template,
        memberRowId: rowId,
        identity: _rowIdentity(collection, row),
        identitySources: row.sources,
        values: const {},
        persisted: false);
  }

  final String id;
  final ProductSpecMemberCollection collection;
  final SpecTemplate template;
  final bool persisted;
  String _memberRowId;
  Map<String, String> _identity;
  List<String> _identitySources;
  Map<String, dynamic> _values;
  ProductSpecReference? _reference;
  String? _manufacturerSku;
  Map<String, dynamic> _autoValues;
  final Set<String> _manualKeys = {};
  String? _bindingAction;

  Map<String, String> get identity => _identity;
  String get memberRowId => _memberRowId;
  ProductSpecReference? get reference => _reference;
  String? get manufacturerSku => _manufacturerSku;
  List<String> get identitySources => _identitySources;
  Map<String, dynamic> get values => _copy(_values);
  bool isCatalogValue(String key) => _autoValues.containsKey(key);

  bool _isActiveField(String key) => template.fields.any(
      (f) => f.definition?.key == key && template.roleFor(key) != 'legacy');

  void setValue(String key, Object? value) {
    if (!_isActiveField(key)) {
      throw const FormatException('El dato no pertenece a esta ficha.');
    }
    _values = {..._values};
    _manualKeys.add(key);
    _autoValues.remove(key);
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = _copyValue(value);
    }
    selectReference(_reference);
  }

  /// A reference supplies only missing facts of this confirmed component.
  /// Detaching it removes its automatic facts while retaining observations.
  /// Only active fields of this template are derived: a documented fact the
  /// component cannot store is reported by [validate], never shown as a value.
  void selectReference(ProductSpecReference? next) {
    _values = pruneStaleAutoDerivedProductSpecValues(
        baseValues: _values,
        manualKeys: _manualKeys,
        previousAutoValues: _autoValues);
    _autoValues = {};
    _reference = next;
    if (next?.family == template.technicalFamily &&
        next!.matchesIdentity(
            brand: _identity['identity_brand'] ?? '',
            model: _identity['identity_model'] ?? '',
            manufacturerSku: _manufacturerSku ?? '')) {
      for (final entry in next.facts.entries) {
        if (_isActiveField(entry.key) &&
            !hasKnownSpecValue(_values[entry.key])) {
          _values[entry.key] = _copyValue(entry.value);
          _autoValues[entry.key] = _copyValue(entry.value);
        }
      }
    }
  }

  /// An explicit confirmation can enrich an unknown identity with evidence.
  /// Replacing a known part needs an archive followed by a new profile.
  void identify(
      {required SpecTemplate parentTemplate,
      required Map<String, dynamic> parentValues,
      String? manufacturerSku}) {
    final row = _row(collection, parentTemplate, parentValues, memberRowId);
    final next = _rowIdentity(collection, row);
    final nextSku = _sku(manufacturerSku);
    if (_sameIdentity(_identity, next) && nextSku == this.manufacturerSku) {
      return;
    }
    if (_bindingAction == 'rebind') {
      throw const FormatException(
          'Ya vinculaste otra fila en esta edición. Guarda antes de confirmar la identificación.');
    }
    if (row.sources.isEmpty ||
        _identity.entries
            .any((e) => hasKnownSpecValue(e.value) && next[e.key] != e.value) ||
        this.manufacturerSku != null && nextSku != this.manufacturerSku) {
      throw const FormatException(
          'Identificar exige una fuente y conservar los datos ya confirmados.');
    }
    _identity = Map.unmodifiable(next);
    _identitySources = List.unmodifiable(row.sources);
    _manufacturerSku = nextSku;
    _bindingAction = 'identify';
  }

  /// The operator selects the exact destination; identical parts are never
  /// matched automatically by brand, model, position or list order.
  void rebind(
      {required SpecTemplate parentTemplate,
      required Map<String, dynamic> parentValues,
      required String rowId}) {
    final row = _row(collection, parentTemplate, parentValues, rowId);
    if (!_sameIdentity(_identity, _rowIdentity(collection, row))) {
      throw const FormatException(
          'La fila elegida debe conservar la misma identidad.');
    }
    if (rowId == _memberRowId) return;
    if (_bindingAction == 'identify') {
      throw const FormatException(
          'Ya confirmaste la identificación en esta edición. Guarda antes de vincular otra fila.');
    }
    _memberRowId = rowId;
    _bindingAction = 'rebind';
  }

  List<ProductSpecIssue> validate() => validateProductSpecDraft(
      template: template,
      values: _values,
      reference: reference,
      brand: _identity['identity_brand'] ?? '',
      model: _identity['identity_model'] ?? '',
      manufacturerSku: manufacturerSku ?? '');

  Map<String, dynamic> buildUpsert(
      {required SpecTemplate parentTemplate,
      required Map<String, dynamic> parentValues}) {
    final row = _row(collection, parentTemplate, parentValues, memberRowId);
    if (row.values[collection.familyColumn] != template.key ||
        !_sameIdentity(_identity, _rowIdentity(collection, row))) {
      throw const FormatException(
          'La pieza cambió: confirma su identificación o archiva la ficha anterior.');
    }
    final blocking = validate().where((i) => i.blocking).firstOrNull;
    if (blocking != null) throw FormatException(blocking.message);
    return {
      'id': id,
      'collection_definition_id': collection.definitionId,
      'member_row_id': memberRowId,
      'template_id': template.id,
      'contract_version': template.contractVersion,
      'manufacturer_sku': _sku(manufacturerSku),
      'reference_id': reference?.id,
      'values': SpecEngineService.buildFactPayload(
          template,
          omitAutoDerivedProductSpecValues(
              values: _values, autoDerivedValues: _autoValues)),
      if (_bindingAction != null && persisted) 'binding_action': _bindingAction,
    };
  }
}

/// The whole member command is submitted with the parent, its expected
/// revision and the same idempotency key. Archiving is reversible until Save.
class ProductSpecMemberDrafts {
  ProductSpecMemberDrafts(this.source)
      : _active = {
          for (final p in source.profiles)
            p.id: ProductSpecMemberDraft.fromProfile(p)
        };

  final ProductSpecMemberProfiles source;
  final Map<String, ProductSpecMemberDraft> _active;
  final Map<String, ProductSpecMemberDraft> _archiving = {};
  List<ProductSpecMemberDraft> get active => List.unmodifiable(_active.values);
  List<ProductSpecMemberDraft> get archiving =>
      List.unmodifiable(_archiving.values);

  ProductSpecMemberDraft? forRow(String definitionId, String rowId) => _active
      .values
      .where((p) =>
          p.collection.definitionId == definitionId && p.memberRowId == rowId)
      .firstOrNull;

  void add(ProductSpecMemberDraft draft) {
    if (_active.containsKey(draft.id) ||
        _archiving.containsKey(draft.id) ||
        source.archivedProfiles.any((p) => p.id == draft.id) ||
        forRow(draft.collection.definitionId, draft.memberRowId) != null) {
      throw const FormatException(
          'La pieza ya tiene una ficha; conserva o archiva la anterior.');
    }
    _active[draft.id] = draft;
  }

  void archive(String id) {
    final draft = _active.remove(id);
    if (draft == null) {
      throw const FormatException('Ficha de componente no disponible.');
    }
    _archiving[id] = draft;
  }

  void undoArchive(String id) {
    final draft = _archiving[id];
    if (draft == null ||
        forRow(draft.collection.definitionId, draft.memberRowId) != null) {
      throw const FormatException(
          'Retira primero la ficha que ocupa esa fila.');
    }
    _archiving.remove(id);
    _active[id] = draft;
  }

  Map<String, dynamic> buildCommand(
      {required SpecTemplate? parentTemplate,
      required Map<String, dynamic> parentValues}) {
    if (_active.isNotEmpty && parentTemplate == null) {
      throw const FormatException(
          'Archiva las fichas incluidas antes de retirar la ficha del producto.');
    }
    final rows = <String>{};
    for (final draft in _active.values) {
      if (!rows.add('${draft.collection.definitionId}:${draft.memberRowId}')) {
        throw const FormatException(
            'La fila del componente tiene dos fichas activas.');
      }
    }
    return {
      'schema_version': 1,
      'upserts': [
        for (final draft in _active.values)
          draft.buildUpsert(
              parentTemplate: parentTemplate!, parentValues: parentValues)
      ],
      'archive_ids': [
        for (final draft in _archiving.values)
          if (draft.persisted) draft.id
      ]
    };
  }
}

ProductSpecRow _row(ProductSpecMemberCollection collection, SpecTemplate parent,
    Map<String, dynamic> values, String rowId) {
  final field = parent.fields
      .where((f) =>
          f.specDefinitionId == collection.definitionId &&
          f.definition?.key == collection.fieldKey)
      .firstOrNull;
  final config = parent.formContract['member_profiles'];
  final declarations = config is Map ? config['collections'] : null;
  if (field == null ||
      parent.roleFor(collection.fieldKey) != 'contents' ||
      declarations is! List ||
      !declarations.whereType<Map>().any((c) =>
          c['field'] == collection.fieldKey &&
          c['family_column'] == collection.familyColumn &&
          _sameColumns(c['identity_columns'], collection.identityColumns))) {
    throw const FormatException(
        'La ficha del producto cambió: archiva las fichas incluidas anteriores.');
  }
  final schema = field.definition!.rowSchema!;
  final value = values[collection.fieldKey];
  final row = value == null
      ? null
      : schema.parse(value).rows.where((r) => r.id == rowId).firstOrNull;
  if (row == null) {
    throw const FormatException(
        'Restituye la fila del componente o archiva su ficha.');
  }
  return row;
}

Map<String, String> _rowIdentity(
        ProductSpecMemberCollection collection, ProductSpecRow row) =>
    {
      for (final key in [
        collection.familyColumn,
        ...collection.identityColumns
      ])
        if (row.values.containsKey(key)) key: row.values[key] as String,
    };

bool _sameIdentity(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// The identity is a projection over a set of columns: a parent that declares
/// another set would confirm a different identity for the same row.
bool _sameColumns(Object? declared, List<String> expected) =>
    declared is List &&
    declared.length == expected.length &&
    declared.every((column) => column is String) &&
    declared.toSet().containsAll(expected);
String? _sku(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
Object? _copyValue(Object? value) => jsonDecode(jsonEncode(value));
Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    _copyValue(value) as Map<String, dynamic>;
