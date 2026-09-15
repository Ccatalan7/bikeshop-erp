import '../services/spec_engine_service.dart';
import '../utils/spec_rule_evaluator.dart';
import 'product_spec_contract.dart';

/// Read side of the component profiles delivered inside
/// `get_product_spec_editor_context_v3`.
///
/// A profile is a scoped observation of one inventory product: the facts of a
/// component that came inside it, stored under `member:<profile id>`. Each
/// active profile is validated with its own family template and never merged
/// with another component; none of this creates an inventory child. Decoding
/// is strict: a shape the server does not emit is rejected instead of repaired,
/// because a silently repaired read would be saved back.

final _uuid =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
final _rowId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

const _activeKeys = {
  'id',
  'scope',
  'issues',
  'values',
  'template',
  'reference',
  'tenant_id',
  'created_at',
  'product_id',
  'updated_at',
  'archived_at',
  'template_id',
  'catalog_keys',
  'fact_payload',
  'reference_id',
  'member_row_id',
  'member_identity',
  'identity_sources',
  'manufacturer_sku',
  'active_template_guard',
  'saved_contract_version',
  'collection_definition_id',
};
// The server attaches an editable template only to active profiles.
final _archivedKeys = {..._activeKeys}..remove('template');
const _blockKeys = {
  'read_schema_version',
  'product_id',
  'revision',
  'product_updated_at',
  'profiles',
  'archived_profiles',
};

Never _invalid(String message) =>
    throw FormatException('Fichas de componentes: $message');

/// A parent collection that may own component profiles, as declared in the
/// parent template's `form_contract.member_profiles`.
class ProductSpecMemberCollection {
  const ProductSpecMemberCollection({
    required this.definitionId,
    required this.fieldKey,
    required this.familyColumn,
    required this.identityColumns,
    required this.familyOptions,
  });

  final String definitionId;
  final String fieldKey;
  final String familyColumn;
  final List<String> identityColumns;
  final List<String> familyOptions;
}

/// Header and evidence shared by active and archived profiles, as read.
/// Maps and lists are immutable copies.
class ProductSpecMemberRecord {
  const ProductSpecMemberRecord({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.collectionDefinitionId,
    required this.memberRowId,
    required this.memberIdentity,
    required this.identitySources,
    required this.manufacturerSku,
    required this.templateId,
    required this.savedContractVersion,
    required this.referenceId,
    required this.reference,
    required this.values,
    required this.factPayload,
    required this.catalogKeys,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String productId;
  final String collectionDefinitionId;
  final String memberRowId;

  /// The family column and identity columns of the bound row when confirmed.
  final Map<String, String> memberIdentity;
  final List<String> identitySources;
  final String? manufacturerSku;
  final String templateId;
  final int savedContractVersion;
  final String? referenceId;
  final ProductSpecReference? reference;

  /// Facts by definition key; decimals keep their exact wire text.
  final Map<String, dynamic> values;

  /// The same facts by definition id, as stored.
  final Map<String, dynamic> factPayload;
  final List<String> catalogKeys;
  final String createdAt;
  final String updatedAt;

  String get scope => 'member:$id';
}

/// An active profile: the only kind an editor may change.
class ProductSpecMemberProfile {
  const ProductSpecMemberProfile({
    required this.record,
    required this.collection,
    required this.template,
    required this.serverIssues,
  });

  final ProductSpecMemberRecord record;
  final ProductSpecMemberCollection collection;
  final SpecTemplate template;
  final List<ProductSpecIssue> serverIssues;

  String get id => record.id;
  String get memberRowId => record.memberRowId;
  Map<String, dynamic> get values => record.values;

  /// The template changed after this profile was saved; the server rejects a
  /// save against the old version.
  bool get isStale => record.savedContractVersion != template.contractVersion;

  /// Validates this component alone with the shared draft validator. The
  /// identity keys are the ones the server passes for the reference check.
  List<ProductSpecIssue> validate([Map<String, dynamic>? draftValues]) =>
      validateProductSpecDraft(
        template: template,
        values: draftValues ?? values,
        reference: record.reference,
        brand: record.memberIdentity['identity_brand'] ?? '',
        model: record.memberIdentity['identity_model'] ?? '',
        manufacturerSku: record.manufacturerSku ?? '',
      );
}

/// Archived evidence. It has no template to edit against and no validation:
/// its row, family contract or template may have changed since.
class ProductSpecArchivedMemberProfile {
  const ProductSpecArchivedMemberProfile({
    required this.record,
    required this.archivedAt,
  });

  final ProductSpecMemberRecord record;
  final String archivedAt;

  String get id => record.id;
  Map<String, dynamic> get values => record.values;
}

class ProductSpecMemberProfiles {
  const ProductSpecMemberProfiles({
    required this.productId,
    required this.revision,
    required this.productUpdatedAt,
    required this.collections,
    required this.profiles,
    required this.archivedProfiles,
  });

  final String? productId;
  final int revision;
  final String? productUpdatedAt;
  final List<ProductSpecMemberCollection> collections;
  final List<ProductSpecMemberProfile> profiles;
  final List<ProductSpecArchivedMemberProfile> archivedProfiles;

  /// The active profile bound to one row of one collection, if any.
  ProductSpecMemberProfile? activeFor(
          String collectionDefinitionId, String memberRowId) =>
      profiles
          .where((profile) =>
              profile.record.collectionDefinitionId == collectionDefinitionId &&
              profile.memberRowId == memberRowId)
          .firstOrNull;

  /// The profile an editor may change. Archived evidence is never editable.
  ProductSpecMemberProfile editable(String profileId) {
    final active = profiles.where((p) => p.id == profileId).firstOrNull;
    if (active != null) return active;
    if (archivedProfiles.any((p) => p.id == profileId)) {
      throw StateError('La ficha archivada del componente no se edita.');
    }
    throw StateError('Ficha de componente no disponible.');
  }

  /// Each active component validated on its own, by profile id.
  Map<String, List<ProductSpecIssue>> validateAll() =>
      {for (final profile in profiles) profile.id: profile.validate()};
}

/// Validates the committed editor read-back before a form starts another edit.
/// The receipt supplies the revision and timestamp; no local persisted flag is
/// guessed and no follow-up read can race a second editor.
Map<String, dynamic>? decodeProductSpecSavedEditorContext(
  Map<String, dynamic> receipt, {
  required bool withMembers,
}) {
  if (!withMembers) return null;
  final product = receipt['product'];
  final context = receipt['editor_context'];
  if (product is! Map ||
      product['id'] is! String ||
      product['spec_revision'] is! int ||
      receipt['revision'] != product['spec_revision'] ||
      context is! Map ||
      context['product_updated_at'] is! String ||
      context['product_updated_at'] != product['updated_at'] ||
      context['member_parent_context'] != null) {
    _invalid('el acuse no contiene la ficha guardada del producto.');
  }
  final result = Map<String, dynamic>.from(context);
  decodeProductSpecMemberProfiles(result,
      expectedProductId: product['id'] as String,
      expectedRevision: product['spec_revision'] as int);
  return result;
}

/// Decodes the `member_profiles` block of a v3 editor context. The parent is
/// decoded first by [SpecEngineService.decodeProductSpecEditorContext], and
/// each member template goes through the same reader wrapped as a v2 context.
ProductSpecMemberProfiles decodeProductSpecMemberProfiles(
  Map<String, dynamic> editorContext, {
  String? expectedProductId,
  int? expectedRevision,
}) {
  final root = SpecEngineService.decodeProductSpecEditorContext(
      Map<String, dynamic>.from(editorContext));
  final rawProductId = editorContext['product_id'];
  final revision = editorContext['revision'] as int;
  if (expectedProductId != null && rawProductId != expectedProductId) {
    _invalid('la lectura pertenece a otro producto.');
  }
  if (expectedRevision != null && revision != expectedRevision) {
    _invalid('la lectura pertenece a otra revisión.');
  }
  final block = editorContext['member_profiles'];
  if (block is! Map ||
      block['read_schema_version'] is! int ||
      block['read_schema_version'] != 1) {
    _invalid('falta el bloque de perfiles v1.');
  }
  final collections = root.template == null
      ? const <ProductSpecMemberCollection>[]
      : _collections(root.template!);
  final persisted = editorContext['member_parent_context'];
  if (persisted != null &&
      (persisted is! Map ||
          rawProductId == null ||
          persisted['product_id'] != rawProductId ||
          persisted['revision'] != revision ||
          persisted['product_updated_at'] is! String ||
          persisted['product_updated_at'] !=
              editorContext['product_updated_at'])) {
    _invalid('el dueño guardado pertenece a otro producto o revisión.');
  }
  final ownerContext = persisted == null
      ? editorContext
      : Map<String, dynamic>.from(persisted as Map);
  final owner = persisted == null
      ? root
      : SpecEngineService.decodeProductSpecEditorContext(ownerContext);
  final ownerCollections = owner.template == null
      ? const <ProductSpecMemberCollection>[]
      : _collections(owner.template!);
  if (rawProductId == null) {
    if (!_sameKeys(block, _blockKeys) ||
        revision != 0 ||
        block['product_id'] != null ||
        block['product_updated_at'] != null ||
        block['revision'] is! int ||
        block['revision'] != 0 ||
        block['profiles'] is! List ||
        (block['profiles'] as List).isNotEmpty ||
        block['archived_profiles'] is! List ||
        (block['archived_profiles'] as List).isNotEmpty) {
      _invalid('un contexto sin producto no tiene perfiles.');
    }
    return ProductSpecMemberProfiles(
      productId: null,
      revision: 0,
      productUpdatedAt: null,
      collections: List.unmodifiable(collections),
      profiles: const [],
      archivedProfiles: const [],
    );
  }
  if (rawProductId is! String) _invalid('producto raíz inválido.');
  final productId = rawProductId;
  if (!_sameKeys(block, _blockKeys) ||
      block['product_id'] != productId ||
      block['revision'] is! int ||
      block['revision'] != revision ||
      block['product_updated_at'] is! String ||
      (editorContext['product_updated_at'] != null &&
          block['product_updated_at'] != editorContext['product_updated_at']) ||
      block['profiles'] is! List ||
      block['archived_profiles'] is! List) {
    _invalid('el bloque no corresponde al producto y revisión raíz.');
  }
  final rows = _rootRows(ownerCollections, ownerContext['values'] as Map);
  final seen = <String>{};
  final boundRows = <String>{};
  String? tenant;
  final profiles = <ProductSpecMemberProfile>[];
  final archivedProfiles = <ProductSpecArchivedMemberProfile>[];
  for (final (raw, archived) in [
    for (final raw in block['profiles'] as List) (raw, false),
    for (final raw in block['archived_profiles'] as List) (raw, true),
  ]) {
    if (raw is! Map) _invalid('perfil inválido.');
    final json = Map<String, dynamic>.from(raw);
    if (!_sameKeys(json, archived ? _archivedKeys : _activeKeys)) {
      _invalid('campos de perfil inesperados.');
    }
    final record = _record(json, productId);
    if (!seen.add(record.id)) {
      _invalid('perfil repetido entre activos y archivados.');
    }
    if ((tenant ??= record.tenantId) != record.tenantId) {
      _invalid('los perfiles pertenecen a otro tenant.');
    }
    final issues = json['issues'];
    if (archived) {
      // The server reports no issues for archived evidence.
      if (json['archived_at'] is! String ||
          json['active_template_guard'] != null ||
          issues is! List ||
          issues.isNotEmpty) {
        _invalid('estado de archivo inconsistente.');
      }
      archivedProfiles.add(ProductSpecArchivedMemberProfile(
          record: record, archivedAt: json['archived_at'] as String));
      continue;
    }
    if (json['archived_at'] != null || json['active_template_guard'] != true) {
      _invalid('estado de archivo inconsistente.');
    }
    final collection = ownerCollections
            .where((c) => c.definitionId == record.collectionDefinitionId)
            .firstOrNull ??
        _invalid('la colección no está declarada en la ficha raíz.');
    // One active profile per row, as the partial unique index guarantees.
    if (!boundRows.add('${collection.definitionId}/${record.memberRowId}')) {
      _invalid('dos perfiles activos para la misma fila.');
    }
    final row = rows[collection.definitionId]?[record.memberRowId] ??
        _invalid('falta la fila ${record.memberRowId} del componente.');
    final rowFamily = row[collection.familyColumn];
    if (rowFamily is! String ||
        (collection.familyOptions.isNotEmpty &&
            !collection.familyOptions.contains(rowFamily))) {
      _invalid('la fila no declara una familia de la colección.');
    }
    final projected = {
      for (final entry in row.entries)
        if (entry.key == collection.familyColumn ||
            collection.identityColumns.contains(entry.key))
          entry.key: entry.value,
    };
    if (!_sameJson(projected, record.memberIdentity)) {
      _invalid('la identidad no corresponde a la fila ${record.memberRowId}.');
    }
    final rawTemplate = json['template'];
    if (rawTemplate is! Map || rawTemplate['id'] != record.templateId) {
      _invalid('la plantilla no corresponde al perfil.');
    }
    final member = SpecEngineService.decodeProductSpecEditorContext({
      'read_schema_version': 2,
      'revision': revision,
      'values': record.values,
      'template_id': record.templateId,
      'contract_version': rawTemplate['contract_version'],
      'template_key': rawTemplate['key'],
      'technical_family': rawTemplate['technical_family'],
      'template': rawTemplate,
    }).template!;
    // The row names the template key; its technical family may be another word.
    if (member.key != rowFamily) {
      _invalid('la familia de la fila no es la de su plantilla.');
    }
    _checkFacts(member, record);
    if (issues is! List ||
        issues.any((issue) =>
            issue is! Map ||
            issue['profile_id'] != record.id ||
            issue['member_row_id'] != record.memberRowId ||
            issue['collection_definition_id'] !=
                record.collectionDefinitionId)) {
      _invalid('una observación pertenece a otro componente.');
    }
    final serverIssues = productSpecServerIssues(issues);
    if (serverIssues.length != issues.length) {
      _invalid('observación del servidor inválida.');
    }
    profiles.add(ProductSpecMemberProfile(
      record: record,
      collection: collection,
      template: member,
      serverIssues: List.unmodifiable(serverIssues),
    ));
  }
  return ProductSpecMemberProfiles(
    productId: productId,
    revision: revision,
    productUpdatedAt: block['product_updated_at'] as String,
    collections: List.unmodifiable(collections),
    profiles: List.unmodifiable(profiles),
    archivedProfiles: List.unmodifiable(archivedProfiles),
  );
}

ProductSpecMemberRecord _record(Map<String, dynamic> json, String productId) {
  final id = _uuidField(json, 'id');
  if (json['scope'] != 'member:$id') {
    _invalid('el alcance no corresponde al perfil.');
  }
  if (json['product_id'] != productId) {
    _invalid('el perfil pertenece a otro producto.');
  }
  final rowId = json['member_row_id'];
  if (rowId is! String || !_rowId.hasMatch(rowId)) {
    _invalid('fila de componente inválida.');
  }
  final identity = json['member_identity'];
  if (identity is! Map ||
      identity.isEmpty ||
      identity.entries.any((e) => e.key is! String || e.value is! String)) {
    _invalid('identidad de componente inválida.');
  }
  final version = json['saved_contract_version'];
  if (version is! int || version < 1) _invalid('versión guardada inválida.');
  final sku = json['manufacturer_sku'];
  if (sku != null && sku is! String) _invalid('código de fabricante inválido.');
  final referenceId = json['reference_id'];
  if (referenceId != null && referenceId is! String) {
    _invalid('referencia inválida.');
  }
  final values = _exact(json['values'], 'values');
  final catalogKeys = _strings(json['catalog_keys'], 'catalog_keys');
  if (catalogKeys.toSet().length != catalogKeys.length ||
      !catalogKeys.every(values.containsKey)) {
    _invalid('claves de catálogo fuera de los hechos del perfil.');
  }
  return ProductSpecMemberRecord(
    id: id,
    tenantId: _uuidField(json, 'tenant_id'),
    productId: productId,
    collectionDefinitionId: _uuidField(json, 'collection_definition_id'),
    memberRowId: rowId,
    memberIdentity: Map<String, String>.unmodifiable(
        {for (final e in identity.entries) e.key as String: e.value as String}),
    identitySources: List<String>.unmodifiable(
        _strings(json['identity_sources'], 'identity_sources')),
    manufacturerSku: sku as String?,
    templateId: _uuidField(json, 'template_id'),
    savedContractVersion: version,
    referenceId: referenceId as String?,
    reference: _reference(json['reference'], referenceId),
    values: values,
    factPayload: _factPayload(json['fact_payload']),
    catalogKeys: List<String>.unmodifiable(catalogKeys),
    createdAt: _string(json['created_at'], 'created_at'),
    updatedAt: _string(json['updated_at'], 'updated_at'),
  );
}

List<ProductSpecMemberCollection> _collections(SpecTemplate template) {
  final config = template.formContract['member_profiles'];
  if (config == null) return const [];
  if (config is! Map ||
      config['version'] != 1 ||
      config.keys.any((k) => k != 'version' && k != 'collections') ||
      config['collections'] is! List ||
      (config['collections'] as List).isEmpty) {
    _invalid('contrato de colecciones inválido.');
  }
  final result = <ProductSpecMemberCollection>[];
  for (final entry in config['collections'] as List) {
    if (entry is! Map ||
        entry.keys.any((k) => !const {
              'field',
              'family_column',
              'identity_columns'
            }.contains(k)) ||
        entry['field'] is! String ||
        entry['family_column'] is! String) {
      _invalid('colección inválida.');
    }
    final fieldKey = entry['field'] as String;
    final definition = template.fields
        .map((field) => field.definition)
        .whereType<SpecDefinition>()
        .where((d) => d.key == fieldKey)
        .firstOrNull;
    final schema = definition?.validationRules['rows_schema'];
    if (definition == null ||
        definition.dataType != 'json' ||
        schema is! Map ||
        template.roleFor(fieldKey) != 'contents' ||
        result.any((c) => c.fieldKey == fieldKey)) {
      _invalid('la colección $fieldKey no es contenido activo de la ficha.');
    }
    final columns = <String, Map>{
      for (final column in schema['columns'] as List? ?? const [])
        if (column is Map && column['key'] is String)
          column['key'] as String: column,
    };
    final familyColumn = entry['family_column'] as String;
    final family = columns[familyColumn];
    final options = family?['allowed_values'] ?? const [];
    if (family == null ||
        family['type'] != 'token' ||
        options is! List ||
        options.any((option) => option is! String)) {
      _invalid('la familia necesita una columna de opciones.');
    }
    final identityColumns =
        _strings(entry['identity_columns'], 'identity_columns');
    if (!identityColumns.contains('identity_brand') ||
        !identityColumns.contains('identity_model') ||
        identityColumns.toSet().length != identityColumns.length ||
        identityColumns.any((key) =>
            key == familyColumn ||
            !const {'token', 'text'}.contains(columns[key]?['type']))) {
      _invalid('columna de identidad inválida.');
    }
    result.add(ProductSpecMemberCollection(
      definitionId: definition.id,
      fieldKey: fieldKey,
      familyColumn: familyColumn,
      identityColumns: List.unmodifiable(identityColumns),
      familyOptions: List<String>.unmodifiable(options),
    ));
  }
  return result;
}

/// Persisted rows of the declared parent collections, by definition and row.
Map<String, Map<String, Map<String, dynamic>>> _rootRows(
    List<ProductSpecMemberCollection> collections, Map values) {
  final result = <String, Map<String, Map<String, dynamic>>>{};
  for (final collection in collections) {
    final cell = values[collection.fieldKey];
    if (cell == null) continue;
    if (cell is! Map || cell['rows'] is! List) {
      _invalid('filas de la colección ${collection.fieldKey} inválidas.');
    }
    final byId = <String, Map<String, dynamic>>{};
    for (final row in cell['rows'] as List) {
      if (row is! Map ||
          row['id'] is! String ||
          row['values'] is! Map ||
          byId.containsKey(row['id'])) {
        _invalid('fila de la colección ${collection.fieldKey} inválida.');
      }
      byId[row['id'] as String] =
          Map<String, dynamic>.from(row['values'] as Map);
    }
    result[collection.definitionId] = byId;
  }
  return result;
}

/// Facts by key and by id must describe the same observations, exactly.
void _checkFacts(SpecTemplate template, ProductSpecMemberRecord record) {
  final byKey = {
    for (final definition
        in template.fields.map((f) => f.definition).whereType<SpecDefinition>())
      definition.key: definition,
  };
  final byId = {for (final d in byKey.values) d.id: d};
  // The server refuses to save a scoped fact outside the member template.
  if (record.values.keys.any((key) => !byKey.containsKey(key))) {
    _invalid('un hecho no pertenece a la plantilla del componente.');
  }
  if (record.factPayload.length != record.values.length) {
    _invalid('los hechos almacenados no corresponden a los mostrados.');
  }
  for (final entry in record.factPayload.entries) {
    final definition = byId[entry.key] ??
        _invalid('los hechos almacenados no corresponden a los mostrados.');
    final stored = (entry.value as Map).entries.single;
    final kind = switch (definition.dataType) {
      'number' => 'number',
      'boolean' => 'boolean',
      'single_select' || 'multi_select' => 'value_ids',
      'json' when definition.validationRules['rows_schema'] is Map => 'rows',
      _ => 'text',
    };
    if (stored.key != kind || !record.values.containsKey(definition.key)) {
      _invalid('${definition.key} no tiene la forma almacenada de su tipo.');
    }
    if (kind == 'value_ids') {
      final shown = record.values[definition.key];
      final labels = definition.dataType == 'single_select'
          ? (shown is String ? [shown] : null)
          : (shown is List && shown.every((label) => label is String)
              ? shown.cast<String>()
              : null);
      final ids = stored.value as List;
      final expected =
          labels?.map((label) => definition.optionIds[label]).toSet();
      if (labels == null ||
          labels.isEmpty ||
          labels.toSet().length != labels.length ||
          expected!.contains(null) ||
          ids.length != expected.length ||
          !ids.every(expected.contains)) {
        _invalid(
            '${definition.key} tiene opciones de otro campo o distintas de las mostradas.');
      }
    } else if (!_sameJson(record.values[definition.key], stored.value)) {
      _invalid('${definition.key} difiere de su valor almacenado.');
    }
  }
}

Map<String, dynamic> _factPayload(Object? raw) {
  final payload = _exact(raw, 'fact_payload');
  for (final entry in payload.entries) {
    final fact = entry.value;
    if (!_uuid.hasMatch(entry.key) || fact is! Map || fact.length != 1) {
      _invalid('hecho almacenado inválido.');
    }
    final stored = fact.values.single;
    final valid = switch (fact.keys.single) {
      'number' => stored is String && SpecRuleDecimal.tryParse(stored) != null,
      'boolean' => stored is bool,
      'value_ids' => stored is List &&
          stored.isNotEmpty &&
          stored.every((id) => id is String && _uuid.hasMatch(id)) &&
          stored.toSet().length == stored.length,
      'rows' => stored is Map,
      'text' => stored == null || stored is String,
      _ => false,
    };
    if (!valid) _invalid('hecho almacenado sin transporte exacto.');
  }
  return payload;
}

ProductSpecReference? _reference(Object? raw, Object? referenceId) {
  if (referenceId == null) {
    if (raw != null) _invalid('referencia sin identificador.');
    return null;
  }
  if (raw is! Map ||
      raw['id'] != referenceId ||
      raw['read_schema_version'] != 2) {
    _invalid('la referencia no corresponde al perfil.');
  }
  final sku = raw['manufacturer_sku'];
  final claims = raw['claims'];
  if (raw['technical_family'] is! String ||
      raw['brand'] is! String ||
      raw['model'] is! String ||
      raw['label'] is! String ||
      (sku != null && sku is! String) ||
      claims is! List ||
      claims.any((claim) => claim is! Map)) {
    _invalid('referencia incompleta.');
  }
  return ProductSpecReference(
    id: referenceId as String,
    family: raw['technical_family'] as String,
    brand: raw['brand'] as String,
    model: raw['model'] as String,
    label: raw['label'] as String,
    manufacturerSku: sku as String?,
    facts: _exact(raw['facts'], 'reference.facts'),
    sources: List<String>.unmodifiable(
        _strings(raw['sources'], 'reference.sources')),
    claims: List.unmodifiable([
      for (final claim in claims) Map<String, dynamic>.unmodifiable(claim),
    ]),
  );
}

/// Observations travel as text. A JSON number is a precision loss that already
/// happened, so it is refused; only a row envelope's integer version passes.
Map<String, dynamic> _exact(Object? raw, String name) {
  if (raw is! Map) _invalid('$name inválido.');
  return _frozen(raw, name) as Map<String, dynamic>;
}

Object? _frozen(Object? value, String name) {
  if (value is Map) {
    final copy = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) _invalid('$name tiene una clave inválida.');
      copy[key] = key == 'schema_version' && entry.value is int
          ? entry.value
          : _frozen(entry.value, name);
    }
    return Map<String, dynamic>.unmodifiable(copy);
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(
        [for (final item in value) _frozen(item, name)]);
  }
  if (value is num) _invalid('$name trae un número redondeado.');
  return value;
}

/// Structural equality of decoded JSON: maps by key, lists by position.
bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.entries
            .every((e) => b.containsKey(e.key) && _sameJson(e.value, b[e.key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

bool _sameKeys(Map map, Set<String> keys) =>
    map.length == keys.length && keys.every(map.containsKey);

String _string(Object? value, String name) =>
    value is String ? value : _invalid('$name inválido.');

String _uuidField(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! String || !_uuid.hasMatch(value)) _invalid('$name inválido.');
  return value;
}

List<String> _strings(Object? value, String name) {
  if (value is! List || value.any((item) => item is! String)) {
    _invalid('$name inválido.');
  }
  return List<String>.from(value);
}
