/// Need-scoped catalog search for supplier portals.
///
/// Natural language is interpreted before this layer. The durable need owns a
/// category and validated typed predicates; the category owns a technical
/// template; and each supplier adapter owns only its portal vocabulary,
/// navigation and parsing hints. No product family or supplier hostname is
/// special-cased by the matcher.
library;

import '../../modules/inventory/services/product_identity/product_identity_extractor.dart';
import '../../modules/inventory/services/product_identity/product_identity_profile.dart';
import '../../modules/inventory/services/product_identity/bike_part_taxonomy.dart';
import 'package:flutter/foundation.dart';

import 'supplier_catalog_api.dart';
import 'supplier_spec_extraction.dart';

class SupplierNeedSearchPredicate {
  const SupplierNeedSearchPredicate({
    required this.field,
    required this.operator,
    required this.values,
  });

  final String field;
  final String operator;
  final List<Object> values;
}

/// The authoritative spec-registry definition for one requested field.
class SupplierNeedSearchField {
  const SupplierNeedSearchField({
    required this.key,
    required this.label,
    required this.dataType,
    this.unit,
    this.description,
    this.allowedValues = const <Object>[],
    this.validationRules = const <String, Object?>{},
    this.isRequired = false,
  });

  final String key;
  final String label;
  final String dataType;
  final String? unit;

  /// Lo que la ficha explica del campo. Para un booleano es su única fuente de
  /// sinónimos: `Autosellante o anti-pinchazo: …` los enumera antes del
  /// dos puntos.
  final String? description;
  final List<Object> allowedValues;
  final Map<String, Object?> validationRules;
  final bool isRequired;
}

class SupplierNeedSearchRequest {
  const SupplierNeedSearchRequest({
    required this.needId,
    required this.description,
    required this.predicates,
    this.categoryId,
    this.categoryPath,
    this.technicalFamily,
    this.revisionNo,
    this.needVersion,
    this.fields = const <SupplierNeedSearchField>[],
    this.criteriaSpans = const <String>[],
    this.discoveredRequirements = const <SupplyNeedUnmodelledRequirement>[],
  });

  /// Qué interpretación está preguntando. Una lectura recién hecha responde
  /// la revisión vigente por definición; sin este dato saldría rotulada como
  /// «ficha anterior» apenas termina.
  ///
  /// **Se captura al INICIAR el recorrido, no al guardarlo.** Entre una cosa
  /// y la otra pueden pasar minutos y una edición: si el servidor pusiera la
  /// estampa al momento del `insert`, las filas leídas contra la ficha
  /// anterior quedarían presentadas como respuesta de la nueva.
  final int? revisionNo;

  /// La versión de la fila al iniciar. Viaja con la revisión porque el recibo
  /// las valida juntas contra el estado vigente.
  final int? needVersion;

  final String needId;
  final String description;
  final String? categoryId;
  final String? categoryPath;
  final String? technicalFamily;
  final List<SupplierNeedSearchPredicate> predicates;
  final List<SupplierNeedSearchField> fields;

  /// **Dónde, en la petición, está escrito cada criterio.**
  ///
  /// Los criterios se derivan de esta misma petición, pero el vínculo entre la
  /// frase y el campo se pierde al guardarlos: queda `Compuesto = Orgánico` y
  /// ya nadie sabe que el operador lo escribió «de resina». Sin ese vínculo,
  /// el eje de requisitos no expresados vuelve a exigir la palabra literal y
  /// cuenta dos veces lo mismo.
  ///
  /// Acá viajan los tramos **verificados** de la petición que declaran un
  /// criterio vigente. Vacío es la respuesta honesta cuando nadie pudo
  /// establecerlo: entonces manda el vocabulario de la ficha, como siempre.
  /// Ver `verifySupplyNeedCriteriaSpans`.
  final List<String> criteriaSpans;

  /// Lo que el lector encontró en la petición **completa** y que la ficha no
  /// representa, con su cita, su polaridad y su alcance ya verificados.
  ///
  /// Se une a lo que la extracción determinista alcanza a ver; no la reemplaza.
  /// Vacío significa que nadie pudo leerlo, y entonces manda la determinista.
  final List<SupplyNeedUnmodelledRequirement> discoveredRequirements;

  SupplierNeedSearchField? fieldDefinition(String key) {
    final normalized = key.trim();
    for (final field in fields) {
      if (field.key == normalized) return field;
    }
    return null;
  }
}

class SupplierNeedPortalNavigationStep {
  const SupplierNeedPortalNavigationStep({
    required this.fieldName,
    required this.optionText,
  });

  final String fieldName;
  final String optionText;

  factory SupplierNeedPortalNavigationStep.fromJson(
    Map<String, dynamic> json,
  ) {
    if (json['action']?.toString() != 'select_option') {
      throw const FormatException('Unsupported supplier navigation action');
    }
    final field = json['field']?.toString().trim() ?? '';
    final value = json['value']?.toString().trim() ?? '';
    if (field.isEmpty || value.isEmpty) {
      throw const FormatException('Incomplete supplier navigation step');
    }
    return SupplierNeedPortalNavigationStep(
      fieldName: field,
      optionText: value,
    );
  }
}

class SupplierNeedPortalCapturePattern {
  const SupplierNeedPortalCapturePattern({
    required this.pattern,
    required this.fieldsByGroup,
  });

  final String pattern;
  final Map<int, String> fieldsByGroup;

  factory SupplierNeedPortalCapturePattern.fromJson(Map<String, dynamic> json) {
    final pattern = json['pattern']?.toString().trim() ?? '';
    final rawFields = json['fields'];
    if (pattern.isEmpty || pattern.length > 500 || rawFields is! Map) {
      throw const FormatException('Invalid supplier capture pattern');
    }
    final fields = <int, String>{};
    for (final entry in rawFields.entries) {
      final group = int.tryParse(entry.key.toString());
      final field = entry.value?.toString().trim() ?? '';
      if (group == null || group < 1 || group > 20 || field.isEmpty) continue;
      fields[group] = field;
    }
    if (fields.isEmpty) {
      throw const FormatException('Supplier capture pattern has no fields');
    }
    // Compile while reading configuration. A broken pattern disables the
    // adapter instead of failing halfway through a live portal query.
    RegExp(pattern, caseSensitive: false, unicode: true);
    return SupplierNeedPortalCapturePattern(
      pattern: pattern,
      fieldsByGroup: Map.unmodifiable(fields),
    );
  }

  RegExp get expression => RegExp(pattern, caseSensitive: false, unicode: true);
}

class SupplierNeedPortalResultSchema {
  const SupplierNeedPortalResultSchema({
    this.columnAliases = const <String, List<String>>{},
    this.factColumnAliases = const <String, List<String>>{},
    this.noResultPhrases = const <String>[],
  });

  final Map<String, List<String>> columnAliases;
  final Map<String, List<String>> factColumnAliases;
  final List<String> noResultPhrases;

  factory SupplierNeedPortalResultSchema.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    return SupplierNeedPortalResultSchema(
      columnAliases: _stringListMap(json['columns']),
      factColumnAliases: _stringListMap(json['fact_columns']),
      noResultPhrases: _strings(json['no_result_phrases']),
    );
  }

  Map<String, dynamic> toProbeJson() => <String, dynamic>{
        'columns': columnAliases,
        'factColumns': factColumnAliases,
        'noResultPhrases': noResultPhrases,
      };
}

class SupplierNeedPortalFamilyAdapter {
  const SupplierNeedPortalFamilyAdapter({
    required this.identityFamily,
    required this.searchTerms,
    required this.identityTerms,
    required this.navigation,
    required this.capturePatterns,
    required this.fieldAliases,
    required this.valueAliases,
    this.initialUrl,
  });

  final String identityFamily;
  final List<String> searchTerms;
  final List<String> identityTerms;
  final List<SupplierNeedPortalNavigationStep> navigation;
  final List<SupplierNeedPortalCapturePattern> capturePatterns;
  final Map<String, List<String>> fieldAliases;

  /// field key -> canonical value -> supplier spellings.
  final Map<String, Map<String, List<String>>> valueAliases;
  final String? initialUrl;

  factory SupplierNeedPortalFamilyAdapter.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final identityFamily = json['identity_family']?.toString().trim() ?? '';
    final searchTerms = _strings(json['search_terms']);
    if (identityFamily.isEmpty || searchTerms.isEmpty) {
      throw const FormatException('Incomplete supplier family adapter');
    }
    final navigation = <SupplierNeedPortalNavigationStep>[];
    final rawNavigation = json['navigation'];
    if (rawNavigation is List) {
      for (final item in rawNavigation.whereType<Map>()) {
        navigation.add(SupplierNeedPortalNavigationStep.fromJson(
          Map<String, dynamic>.from(item),
        ));
      }
    }
    final captures = <SupplierNeedPortalCapturePattern>[];
    final rawCaptures = json['capture_patterns'];
    if (rawCaptures is List) {
      for (final item in rawCaptures.whereType<Map>()) {
        captures.add(SupplierNeedPortalCapturePattern.fromJson(
          Map<String, dynamic>.from(item),
        ));
      }
    }
    final valueAliases = <String, Map<String, List<String>>>{};
    for (final fieldEntry in _jsonMap(json['value_aliases']).entries) {
      valueAliases[fieldEntry.key] = _stringListMap(fieldEntry.value);
    }
    return SupplierNeedPortalFamilyAdapter(
      identityFamily: identityFamily,
      searchTerms: searchTerms,
      identityTerms: _strings(json['identity_terms']),
      navigation: List.unmodifiable(navigation),
      capturePatterns: List.unmodifiable(captures),
      fieldAliases: _stringListMap(json['field_aliases']),
      valueAliases: Map.unmodifiable(valueAliases),
      initialUrl: _text(json['initial_url']),
    );
  }
}

/// Data-owned capability for one portal. Code executes this schema; it does not
/// ask which supplier it belongs to.
class SupplierNeedPortalAdapter {
  const SupplierNeedPortalAdapter({
    required this.version,
    required this.families,
    required this.categories,
    required this.resultSchema,
    this.genericFamilySearch = false,
    this.initialUrl,
    this.sessionErrorPattern,
    this.catalogRoute,
    this.taxonomyDiscovery,
    this.catalogApi,
    this.budget = const SupplierNeedPortalBudget(),
    this.resultCap = kSupplierNeedPortalDefaultResultCap,
  });

  final int version;
  final Map<String, SupplierNeedPortalFamilyAdapter> families;
  final Map<String, SupplierNeedPortalFamilyAdapter> categories;
  final SupplierNeedPortalResultSchema resultSchema;
  final bool genericFamilySearch;
  final String? initialUrl;
  final String? sessionErrorPattern;

  /// How this portal expresses «browse taxonomy node N, page P». Its absence
  /// is what limits a portal to its word search, and it is data — never a
  /// hostname branch.
  final SupplierNeedPortalCatalogRoute? catalogRoute;

  /// Where the portal publishes its own classification selects.
  final SupplierNeedPortalTaxonomyDiscovery? taxonomyDiscovery;

  /// La API de catálogo de la plataforma sobre la que corre la tienda, cuando
  /// la hay. Es el camino preferido: entrega SKU, precio, categorías, stock y
  /// el total exacto sin raspar una sola etiqueta. Ver `supplier_catalog_api`.
  final SupplierCatalogApi? catalogApi;

  /// Una tienda con API puede contestar una necesidad aunque no publique ni
  /// tabla ni taxonomía navegable: `droppbike.cl` y `derman.cl` son eso.
  bool get canReadCatalogApi => catalogApi != null;

  final SupplierNeedPortalBudget budget;

  /// **El tope del cliente y el del recibo viajan juntos o no viajan.** Este
  /// número vive en el adaptador para que la misma migración que sube el cap
  /// del RPC suba el del cliente; separarlos produce una enumeración correcta
  /// que muere en el `insert` con `22023`.
  final int resultCap;

  bool get canBrowseTaxonomy =>
      catalogRoute != null && taxonomyDiscovery != null;

  factory SupplierNeedPortalAdapter.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.round() ?? 0;
    if (version != 1) {
      throw const FormatException('Unsupported supplier need adapter version');
    }

    Map<String, SupplierNeedPortalFamilyAdapter> adapters(Object? raw) {
      final result = <String, SupplierNeedPortalFamilyAdapter>{};
      for (final entry in _jsonMap(raw).entries) {
        final key = entry.key.trim();
        if (key.isEmpty) continue;
        result[key] = SupplierNeedPortalFamilyAdapter.fromJson(entry.value);
      }
      return Map.unmodifiable(result);
    }

    final families = adapters(json['families']);
    final categories = adapters(json['categories']);
    final genericFamilySearch = json['generic_family_search'] == true;
    if (families.isEmpty && categories.isEmpty && !genericFamilySearch) {
      throw const FormatException('Supplier need adapter has no families');
    }
    final sessionPattern = _text(json['session_error_pattern']);
    if (sessionPattern != null) {
      RegExp(sessionPattern, caseSensitive: false, unicode: true);
    }
    final rawCap = (json['result_cap'] as num?)?.round();
    return SupplierNeedPortalAdapter(
      version: version,
      families: families,
      categories: categories,
      resultSchema:
          SupplierNeedPortalResultSchema.fromJson(json['result_schema']),
      genericFamilySearch: genericFamilySearch,
      initialUrl: _text(json['initial_url']),
      sessionErrorPattern: sessionPattern,
      catalogRoute: json['catalog_route'] == null
          ? null
          : SupplierNeedPortalCatalogRoute.fromJson(json['catalog_route']),
      taxonomyDiscovery: json['taxonomy_discovery'] == null
          ? null
          : SupplierNeedPortalTaxonomyDiscovery.fromJson(
              json['taxonomy_discovery'],
            ),
      catalogApi: SupplierCatalogApi.fromJson(json['catalog_api']),
      budget: SupplierNeedPortalBudget.fromJson(json['budget']),
      resultCap: rawCap == null || rawCap < 1 || rawCap > 500
          ? kSupplierNeedPortalDefaultResultCap
          : rawCap,
    );
  }

  SupplierNeedPortalFamilyAdapter? familyFor(
    SupplierNeedSearchRequest request,
  ) {
    final categoryId = request.categoryId?.trim();
    if (categoryId != null && categoryId.isNotEmpty) {
      final category = categories[categoryId];
      if (category != null) return category;
    }
    final technicalFamily = request.technicalFamily?.trim();
    if (technicalFamily != null && technicalFamily.isNotEmpty) {
      final configured = families[technicalFamily];
      if (configured != null) return configured;
    }
    // **Exigir `technicalFamily` dejaba mudas las categorías sin plantilla.**
    // «Accesorios / Puños» tiene categoría reconocida y ninguna ficha, así que
    // la familia técnica nace nula y acá se devolvía `null`: el plan no se
    // podía armar y la necesidad ni siquiera permitía buscar. La familia se
    // deriva de la propia petición, no de la plantilla; y si el extractor no
    // reconoce ninguna, el sustantivo con que la categoría nombra al objeto es
    // exactamente lo que el operador escribiría en el buscador del proveedor.
    if (!genericFamilySearch || categoryId == null || categoryId.isEmpty) {
      return null;
    }

    // A portal may expose one ordinary word-search for its whole catalogue.
    // In that case a new ficha family must not require a Dart release or a
    // product/SKU exception. The reviewed need still owns category + typed
    // predicates; the canonical part taxonomy contributes only the head noun
    // used by the supplier's search box and the vocabulary used to prove that
    // returned rows are the requested kind of object.
    final identity = ProductIdentityExtractor.extract(ProductIdentityInput(
      name: supplyNeedTextWithoutExclusions(request.description),
    ));
    final familyId = identity.familyId;
    // **La categoría también nombra a la familia.** «Componentes / Frenos /
    // Rotores» es `brake_rotor` para la taxonomía canónica, y sin esto una
    // petición que el extractor no alcanza a clasificar se quedaba sin el
    // vocabulario con que el proveedor nombra la pieza —`disco de freno`— y no
    // podía reconocer sus propias filas.
    final family = (familyId == null || familyId.isEmpty
            ? null
            : BikePartTaxonomy.byId(familyId)) ??
        _familyByCategoryHead(request.categoryPath);
    final searchTerms = <String>[
      ...?family?.heads.map((term) => term.trim()).where((t) => t.isNotEmpty),
      // La palabra de la categoría: es la que el operador ve en pantalla y la
      // que escribiría en el buscador del proveedor.
      ...supplyNeedCategoryHeads(request.categoryPath),
    ];
    if (searchTerms.isEmpty) return null;
    return SupplierNeedPortalFamilyAdapter(
      // Sin familia canónica no se inventa una: la identidad se prueba con el
      // vocabulario de la categoría, y `product_family` queda pendiente en vez
      // de darse por demostrada. Es más pobre y es honesto.
      identityFamily: family?.id ?? '',
      searchTerms: searchTerms,
      identityTerms: family?.heads ?? searchTerms,
      navigation: const <SupplierNeedPortalNavigationStep>[],
      capturePatterns: const <SupplierNeedPortalCapturePattern>[],
      fieldAliases: const <String, List<String>>{},
      valueAliases: const <String, Map<String, List<String>>>{},
    );
  }
}

class SupplierNeedSearchPlan {
  const SupplierNeedSearchPlan({
    required this.request,
    required this.adapter,
    required this.family,
    required this.queries,
  });

  final SupplierNeedSearchRequest request;
  final SupplierNeedPortalAdapter adapter;
  final SupplierNeedPortalFamilyAdapter family;

  /// Ordered portal questions for the same need. A compact, typed
  /// discriminator is attempted first; the plain family term is the bounded
  /// fallback. These are never product names or SKUs.
  final List<String> queries;

  String get query => queries.first;

  /// El término de familia, ya acotado al máximo que acepta el buscador.
  ///
  /// Es siempre el último de [queries] por construcción: los discriminadores
  /// se agregan antes y el término base se agrega al final. Se usa también
  /// como rótulo de una enumeración por taxonomía, donde no hubo «consulta»
  /// pero el recibo igual exige una palabra dentro del límite del proveedor —
  /// tomarla de `searchTerms` sin acotar haría fallar el guardado con 22023
  /// después de haber recorrido el catálogo entero.
  String get broadQuery => queries.last;

  /// **El OBJETO que se busca, no el pedido.** Es lo único que se le pregunta
  /// al lector cuando tiene que decir qué pieza nombra una fila.
  ///
  /// Pasarle la petición entera —«pastillas para frenos Shimano BR-MT200, de
  /// resina y sin aletas»— le hacía contestar **compatibilidad** con el campo
  /// de **identidad**: el 2026-08-31 las diez filas reales de RBX volvieron con
  /// `head = PASTILLA FRENO DISCO` y, a la vez, `is_requested = false`.
  String get requestedObjectLabel {
    final label = BikePartTaxonomy.byId(family.identityFamily)?.label.trim();
    if (label != null && label.isNotEmpty) return label;
    for (final term in family.identityTerms) {
      final clean = term.trim();
      if (clean.isNotEmpty) return clean;
    }
    return family.searchTerms.first;
  }

  /// Las mismas preguntas, ordenadas por RECALL en vez de por precisión.
  ///
  /// «700» es un criterio de la necesidad, no el universo del proveedor.
  /// Preguntar primero lo angosto y quedarse con lo que trajo es exactamente
  /// cómo 18 cámaras se convirtieron en 10: cuando el buscador por palabra es
  /// lo único que queda, se pregunta primero lo ancho.
  List<String> get recallOrderedQueries => List<String>.unmodifiable(<String>[
        broadQuery,
        ...queries.take(queries.length - 1),
      ]);

  SupplierNeedPortalResultSchema get resultSchema => adapter.resultSchema;

  SupplierNeedPortalCatalogRoute? get catalogRoute => adapter.catalogRoute;

  SupplierNeedPortalTaxonomyDiscovery? get taxonomyDiscovery =>
      adapter.taxonomyDiscovery;

  SupplierNeedPortalBudget get budget => adapter.budget;

  int get resultCap => adapter.resultCap;

  /// A portal can enumerate its taxonomy only when it published both how to
  /// read the classification and how to browse one node. Anything less falls
  /// back to the word search, which can never claim complete coverage.
  bool get canBrowseTaxonomy => adapter.canBrowseTaxonomy;

  /// The supplier vocabulary that identifies this family in a node label.
  List<String> get familyTerms => <String>{
        ...family.identityTerms,
        ...family.searchTerms,
      }
          .map(_normalize)
          .where((term) => term.isNotEmpty)
          .toList(growable: false);

  /// Words that look like the family but are a different object. They come
  /// from the canonical part taxonomy, never from a supplier-specific list.
  List<String> get excludedTerms =>
      (BikePartTaxonomy.byId(family.identityFamily)?.negativeHeads ??
              const <String>[])
          .map(_normalize)
          .where((term) => term.isNotEmpty)
          .toList(growable: false);

  /// Which nodes of the discovered taxonomy plausibly hold this family.
  ///
  /// Deliberately returns several: when a portal splits one family across
  /// sibling nodes (`CAMARAS RUTA`, `CAMARAS MTB`), choosing one by guess is
  /// how a real option disappears. Enumerating the plausible siblings and
  /// letting the deterministic matcher eliminate is the repository's
  /// eliminate-then-rank contract applied to discovery.
  List<SupplierPortalTaxonomyNode> rankNodes(
    SupplierPortalCatalogTaxonomy? taxonomy,
  ) =>
      rankSupplierTaxonomyNodes(
        taxonomy: taxonomy,
        familyTerms: familyTerms,
        excludedTerms: excludedTerms,
        limit: budget.maxNodes,
      );

  /// A configured starting document may differ from the query deep link, but
  /// it must stay on the same exact origin. Configuration can never turn an
  /// authenticated portal runner into an arbitrary cross-origin browser.
  String initialUrlFor(String queryUrl) {
    // A family with native select steps starts from the configured catalogue
    // shell. A plain word-search must start at the query URL itself; loading
    // the shell and merely parsing it is what previously produced an empty
    // page (and RBX's legacy "no products" alert) without ever searching.
    if (family.navigation.isEmpty) return queryUrl;
    final configured = family.initialUrl ?? adapter.initialUrl;
    if (configured == null || configured.trim().isEmpty) return queryUrl;
    return _sameOriginUrl(configured, queryUrl) ? configured : queryUrl;
  }
}

/// Si esta palabra es el rótulo con que la petición introduce el valor de un
/// criterio: `anclaje de 6 pernos`, `sistema de freno Shimano`.
bool _introducesCoveredValue(
  List<String> tokens,
  int index,
  Set<String> enlaces,
  bool Function(String palabra, String stem) cubierta,
) {
  if (index + 1 >= tokens.length || !enlaces.contains(tokens[index + 1])) {
    return false;
  }
  for (var salto = 2; salto <= 4; salto += 1) {
    final siguiente = index + salto;
    if (siguiente >= tokens.length) return false;
    final palabra = tokens[siguiente];
    if (_kPolarityResets.contains(palabra)) return false;
    if (palabra.length < 3) continue;
    if (cubierta(palabra, _propertyStem(palabra))) return true;
  }
  return false;
}

/// La familia canónica que la categoría nombra, por su sustantivo.
///
/// La taxonomía se consulta por id y acá no hay id: hay la palabra que el
/// operador ve en pantalla. Se busca esa palabra entre los sustantivos con que
/// cada familia se nombra, que es el mismo vocabulario que ya se usa para
/// reconocer las filas del proveedor.
BikePartFamily? _familyByCategoryHead(String? categoryPath) {
  final heads = supplyNeedCategoryHeads(categoryPath);
  if (heads.isEmpty) return null;
  for (final family in BikePartTaxonomy.families) {
    for (final head in family.heads) {
      final normalizado = head.trim().toLowerCase();
      if (heads.contains(normalizado)) return family;
    }
  }
  return null;
}

/// La petición **sin lo que excluye**.
///
/// **Lo que el pedido descarta no puede nombrar lo que pide.** «Discos de freno
/// de 180 mm … (no Center Lock)» se clasificaba como familia `lock`: el
/// extractor de identidad ve la frase entera y `Center Lock` es el sustantivo
/// más específico que encuentra. Con eso el plan quedaba armado para otra
/// pieza y **rechazaba por identidad la fila que decía literalmente todo lo
/// pedido**. El caso negativo parecía correcto porque también rechazaba al
/// bueno.
///
/// Se recortan los tramos que empiezan en un negador y terminan en el primer
/// límite de cláusula —coma, paréntesis, punto— o al final del texto. No es
/// vocabulario: es la misma polaridad que ya gobierna las exigencias.
String supplyNeedTextWithoutExclusions(String description) {
  final limpio = description.replaceAllMapped(
    RegExp(
      r'(?:^|[,;(\[]|\.\s)\s*\b(?:no|sin|nunca|excepto|salvo)\b[^,;.)\]]*',
      caseSensitive: false,
    ),
    (match) {
      final abre = match.group(0)!.trimLeft();
      return abre.startsWith('(') || abre.startsWith('[') ? ' ' : ' , ';
    },
  );
  final resultado = limpio
      .replaceAll(RegExp(r'[)\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return resultado.isEmpty ? description : resultado;
}

/// El sustantivo con que la categoría nombra al objeto, y su singular.
///
/// Cuando no hay ficha ni familia canónica, esto es todo el vocabulario que
/// existe — y es del operador, no inventado: es la palabra que ve en pantalla.
List<String> supplyNeedCategoryHeads(String? categoryPath) {
  final leaf = (categoryPath ?? '').split('/').last.trim().toLowerCase();
  if (leaf.isEmpty || leaf.contains(' ')) return const <String>[];
  final heads = <String>{leaf};
  if (leaf.endsWith('es') && leaf.length > 4) {
    heads.add(leaf.substring(0, leaf.length - 2));
  } else if (leaf.endsWith('s') && leaf.length > 3) {
    heads.add(leaf.substring(0, leaf.length - 1));
  }
  return List<String>.unmodifiable(heads);
}

SupplierNeedSearchPlan? buildSupplierNeedSearchPlan({
  required SupplierNeedSearchRequest request,
  required SupplierNeedPortalAdapter adapter,
  required int maxLength,
}) {
  if (maxLength < 1) return null;
  final family = adapter.familyFor(request);
  if (family == null) return null;
  final baseQuery = _bounded(family.searchTerms.first, maxLength);
  if (baseQuery.isEmpty) return null;
  final queries = <String>[];
  if (family.navigation.isEmpty) {
    for (final token in _needQueryDiscriminators(request)) {
      final refined = '$baseQuery $token';
      if (refined.length <= maxLength && !queries.contains(refined)) {
        queries.add(refined);
      }
    }
  }
  if (!queries.contains(baseQuery)) queries.add(baseQuery);
  return SupplierNeedSearchPlan(
    request: request,
    adapter: adapter,
    family: family,
    queries: List<String>.unmodifiable(queries),
  );
}

/// Strong, compact values that an ordinary supplier word-search can use to
/// narrow one product family. The matcher still proves every requested field;
/// this only avoids losing the useful size behind the first catalogue page.
///
/// Only reviewed equality predicates backed by the canonical identity registry
/// qualify. Free text, descriptions, product names and SKUs never enter this
/// list.
List<String> _needQueryDiscriminators(SupplierNeedSearchRequest request) {
  final ranked = <({int rank, int order, String token})>[];
  for (var index = 0; index < request.predicates.length; index++) {
    final predicate = request.predicates[index];
    final operator = predicate.operator.trim().toLowerCase();
    if (operator != 'eq' && operator != 'in') continue;
    if (predicate.values.length != 1) continue;
    final kind = _identityKindByField[predicate.field.trim()];
    if (kind == null) continue;
    final token = _queryToken(predicate.values.single, kind);
    if (token == null) continue;
    ranked.add((
      rank: kind == PartSpecKind.wheelSize
          ? 0
          : _number(predicate.values.single) != null
              ? 1
              : 2,
      order: index,
      token: token,
    ));
  }
  ranked.sort((left, right) {
    final byRank = left.rank.compareTo(right.rank);
    return byRank != 0 ? byRank : left.order.compareTo(right.order);
  });
  return ranked.map((item) => item.token).toSet().toList(growable: false);
}

String? _queryToken(Object raw, PartSpecKind kind) {
  final canonical = _canonicalIdentityValue(kind, raw.toString()).trim();
  if (canonical.isEmpty) return null;
  final numeric = _number(canonical);
  if (numeric != null) {
    return numeric == numeric.roundToDouble()
        ? numeric.round().toString()
        : numeric.toString();
  }
  final token = canonical.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  if (token.length < 2 || token.length > 20) return null;
  return token;
}

/// The login destination is separate from search execution. It opens visibly
/// and never submits credentials from the background runner.
String? supplierNeedPortalLoginUrl(String? supplierWebsite) {
  final raw = supplierWebsite?.trim() ?? '';
  if (raw.isEmpty) return null;
  final parsed = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (parsed == null ||
      parsed.host.isEmpty ||
      !const <String>{'http', 'https'}.contains(parsed.scheme.toLowerCase())) {
    return null;
  }
  final host = parsed.host.toLowerCase();
  if (host == 'rburgos.cl' || host.endsWith('.rburgos.cl')) {
    return 'https://portal.rburgos.cl/login/';
  }
  return parsed.toString();
}

class SupplierPortalCatalogCandidate {
  const SupplierPortalCatalogCandidate({
    required this.code,
    required this.name,
    this.brand,
    this.origin,
    this.priceNet,
    this.rowText,
    this.technicalFacts = const <String, Object?>{},
  });

  final String code;
  final String name;
  final String? brand;
  final String? origin;
  final double? priceNet;
  final String? rowText;
  final Map<String, Object?> technicalFacts;

  factory SupplierPortalCatalogCandidate.fromJson(Map<String, dynamic> json) {
    final price = json['priceNet'];
    final rawFacts = json['technicalFacts'];
    return SupplierPortalCatalogCandidate(
      code: json['code']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      brand: _text(json['brand']),
      origin: _text(json['origin']),
      priceNet: price is num
          ? price.toDouble()
          : double.tryParse(price?.toString() ?? ''),
      rowText: _text(json['rowText']),
      technicalFacts: rawFacts is Map
          ? Map<String, Object?>.unmodifiable(
              Map<String, Object?>.from(rawFacts),
            )
          : const <String, Object?>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'name': name,
        'brand': brand,
        'origin': origin,
        'priceNet': priceNet,
        'rowText': rowText,
        if (technicalFacts.isNotEmpty) 'technicalFacts': technicalFacts,
      };
}

enum SupplierNeedMatchState { exact, possible, conflict }

extension SupplierNeedMatchStateWire on SupplierNeedMatchState {
  String get wireName => switch (this) {
        SupplierNeedMatchState.exact => 'exact',
        SupplierNeedMatchState.possible => 'possible',
        SupplierNeedMatchState.conflict => 'conflict',
      };
}

class SupplierNeedPortalMatch {
  const SupplierNeedPortalMatch({
    required this.candidate,
    required this.state,
    required this.provenFields,
    required this.missingFields,
    required this.conflictingFields,
    this.observedFacts = const <String, Object?>{},
    this.requirementFindings = const <SupplyRequirementFinding>[],
  });

  final SupplierPortalCatalogCandidate candidate;
  final SupplierNeedMatchState state;
  final List<String> provenFields;
  final List<String> missingFields;
  final List<String> conflictingFields;
  final Map<String, Object?> observedFacts;

  /// Lo que se sabe, para esta fila, de cada exigencia que la ficha no expresa.
  ///
  /// No viaja al recibo ni decide el estado: el estado ya lo dicen los ejes.
  /// Esto es lo que se le muestra al operador para que pueda comparar cuando la
  /// ficha se queda corta, que es justo cuando más lo necesita.
  final List<SupplyRequirementFinding> requirementFindings;

  factory SupplierNeedPortalMatch.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => (json[key] is List)
        ? (json[key] as List)
            .map((value) => value?.toString().trim())
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final rawFacts = json['observedFacts'];
    return SupplierNeedPortalMatch(
      candidate: SupplierPortalCatalogCandidate.fromJson(json),
      state: switch (json['matchState']?.toString()) {
        'exact' => SupplierNeedMatchState.exact,
        'conflict' => SupplierNeedMatchState.conflict,
        _ => SupplierNeedMatchState.possible,
      },
      provenFields: strings('provenFields'),
      missingFields: strings('missingFields'),
      conflictingFields: strings('conflictingFields'),
      observedFacts: rawFacts is Map
          ? Map<String, Object?>.unmodifiable(
              Map<String, Object?>.from(rawFacts),
            )
          : const <String, Object?>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...candidate.toJson(),
        'matchState': state.wireName,
        'provenFields': provenFields,
        'missingFields': missingFields,
        'conflictingFields': conflictingFields,
        if (observedFacts.isNotEmpty) 'observedFacts': observedFacts,
      };
}

enum SupplierNeedPortalSearchStatus {
  completed,
  noMatches,
  sessionExpired,
  unreadable,
}

extension SupplierNeedPortalSearchStatusWire on SupplierNeedPortalSearchStatus {
  String get wireName => switch (this) {
        SupplierNeedPortalSearchStatus.completed => 'completed',
        SupplierNeedPortalSearchStatus.noMatches => 'no_matches',
        SupplierNeedPortalSearchStatus.sessionExpired => 'session_expired',
        SupplierNeedPortalSearchStatus.unreadable => 'unreadable',
      };
}

bool supplierNeedPortalSessionExpired({
  required String sourceUrl,
  required Map<String, dynamic> report,
  String? loggedOutPattern,
  String? sessionErrorPattern,
}) {
  final session = report['session'];
  if (session is Map &&
      (session['hasPasswordField'] == true ||
          session['hasEmptySessionLabel'] == true ||
          (session['phrases'] is List &&
              (session['phrases'] as List).isNotEmpty))) {
    return true;
  }

  final body = report['bodySample']?.toString() ?? '';
  for (final configured in <String?>[loggedOutPattern, sessionErrorPattern]) {
    final pattern = configured?.trim();
    if (pattern == null || pattern.isEmpty) continue;
    try {
      if (RegExp(pattern, caseSensitive: false, unicode: true).hasMatch(body)) {
        return true;
      }
    } catch (_) {
      // Invalid configuration proves nothing and cannot turn a page into a
      // false logout. Adapter loading rejects it before a live run anyway.
    }
  }
  return false;
}

class SupplierNeedPortalSearchSnapshot {
  const SupplierNeedPortalSearchSnapshot({
    required this.query,
    required this.status,
    required this.checkedAt,
    required this.matches,
    this.sourceUrl,
    this.coverage = const SupplierNeedPortalCoverage.unknown(),
    this.searchRevisionNo,
    this.currentRevisionNo,
    this.evaluatedRevisionNo,
    this.operationKey,
  });

  /// Sella la identidad de la corrida sobre el resultado que se va a guardar.
  ///
  /// La clave se genera antes de abrir el portal; acá sólo se adhiere, para no
  /// repetirla en los nueve lugares donde nace un snapshot.
  SupplierNeedPortalSearchSnapshot withOperationKey(String key) =>
      SupplierNeedPortalSearchSnapshot(
        query: query,
        status: status,
        checkedAt: checkedAt,
        matches: matches,
        sourceUrl: sourceUrl,
        coverage: coverage,
        searchRevisionNo: searchRevisionNo,
        currentRevisionNo: currentRevisionNo,
        evaluatedRevisionNo: evaluatedRevisionNo,
        operationKey: key,
      );

  final String query;
  final SupplierNeedPortalSearchStatus status;
  final DateTime? checkedAt;
  final List<SupplierNeedPortalMatch> matches;
  final String? sourceUrl;

  /// La identidad de ESTA corrida, generada **antes de abrir el portal**.
  ///
  /// Es lo que permite que un guardado que murió en el transporte se recupere
  /// sin volver a navegar ni a preguntarle al modelo, y que reintentarlo no
  /// duplique el recibo. Viaja con el snapshot porque el reintento tiene que
  /// ser la MISMA operación, no otra parecida.
  final String? operationKey;

  /// How much of the supplier's catalogue this answer actually looked at.
  ///
  /// Kept apart from [status] on purpose: the status says how the run ended,
  /// coverage says what it saw. Fusing them is exactly what let «10 filas de
  /// la página 1» read as «el portal tiene 10».
  final SupplierNeedPortalCoverage coverage;

  /// **Cuándo se leyó el portal y para qué ficha.** Es procedencia: no cambia
  /// nunca, porque describe un hecho ocurrido. Junto con `checkedAt` y
  /// `coverage` es lo que permite auditar de dónde salió cada fila.
  final int? searchRevisionNo;

  /// Qué interpretación rige ahora.
  final int? currentRevisionNo;

  /// **Contra qué ficha se juzgaron estas filas.** Es distinto de haberlas
  /// leído: las mismas filas crudas se pueden volver a evaluar contra la ficha
  /// nueva sin volver a consultar, y entonces el veredicto es de ahora aunque
  /// la lectura siga siendo de antes. Fusionar las dos cosas —como hacía la
  /// primera versión del rematch, que pisaba `searchRevisionNo`— borra la
  /// procedencia y hace parecer que hubo una segunda visita al portal.
  ///
  /// Nulo significa «se juzgó cuando se leyó»: el valor por defecto es
  /// [searchRevisionNo].
  final int? evaluatedRevisionNo;

  int? get verdictRevisionNo => evaluatedRevisionNo ?? searchRevisionNo;

  /// El veredicto que se está mostrando responde la pregunta de ahora.
  ///
  /// Mira la revisión EVALUADA, no la leída: una lectura vieja re-evaluada
  /// contra la ficha vigente sí responde lo que se está preguntando.
  /// Cuando la base no informa revisiones —un recibo anterior a este
  /// contrato— se falla cerrado: no se puede demostrar que sea vigente.
  bool get answersCurrentRevision =>
      verdictRevisionNo != null &&
      currentRevisionNo != null &&
      verdictRevisionNo == currentRevisionNo;

  /// El veredicto es de ahora, pero las filas se leyeron para otra ficha.
  /// La pantalla lo dice: es información honesta, no un defecto.
  bool get reusesEarlierReading =>
      searchRevisionNo != null &&
      verdictRevisionNo != null &&
      searchRevisionNo != verdictRevisionNo;

  int get exactCount => matches
      .where((item) => item.state == SupplierNeedMatchState.exact)
      .length;
  int get possibleCount => matches
      .where((item) => item.state == SupplierNeedMatchState.possible)
      .length;
  int get conflictCount => matches
      .where((item) => item.state == SupplierNeedMatchState.conflict)
      .length;

  /// What the operator may be offered as an option.
  ///
  /// A contradicted row is evidence that the node was read, never a choice:
  /// two misclassified tyres inside `CAMARAS RUTA` must not be counted as
  /// cámaras just because the supplier filed them there.
  List<SupplierNeedPortalMatch> get relevantMatches => matches
      .where((item) => item.state != SupplierNeedMatchState.conflict)
      .toList(growable: false);

  int get relevantCount => relevantMatches.length;

  /// Absence is a claim about the whole set, so it needs the whole set —
  /// **y el conjunto de la pregunta que se está haciendo ahora**. Una
  /// enumeración completa contra la ficha anterior no autoriza a decir «no lo
  /// tiene» sobre la ficha nueva.
  bool get canAssertAbsence => coverage.isComplete && answersCurrentRevision;

  String get rowLabel => switch (status) {
        _
            when !answersCurrentRevision &&
                status == SupplierNeedPortalSearchStatus.completed =>
          'Ficha anterior',
        SupplierNeedPortalSearchStatus.sessionExpired => 'Sesión vencida',
        SupplierNeedPortalSearchStatus.unreadable => 'Sin concluir',
        // «No lo tiene» es una afirmación sobre TODO el catálogo. Sólo se
        // puede decir cuando se recorrió todo el catálogo.
        SupplierNeedPortalSearchStatus.noMatches =>
          canAssertAbsence ? 'No lo tiene' : 'No apareció',
        // Las dos cifras van juntas o el rótulo miente por omisión: «17
        // exactos» sobre un listado de 18 escondía justamente la fila que
        // había que mirar.
        SupplierNeedPortalSearchStatus.completed
            when exactCount > 0 && possibleCount > 0 =>
          '$exactCount ${exactCount == 1 ? 'exacto' : 'exactos'} · '
              '$possibleCount por revisar',
        SupplierNeedPortalSearchStatus.completed when exactCount > 0 =>
          '$exactCount ${exactCount == 1 ? 'exacto' : 'exactos'}',
        SupplierNeedPortalSearchStatus.completed when possibleCount > 0 =>
          '$possibleCount por revisar',
        SupplierNeedPortalSearchStatus.completed when conflictCount > 0 =>
          canAssertAbsence ? 'No lo tiene' : 'Sin coincidencias',
        _ => 'No apareció',
      };

  String get detailLabel {
    if (status == SupplierNeedPortalSearchStatus.sessionExpired) {
      return 'La sesión del portal venció; no se concluyó nada.';
    }
    if (status == SupplierNeedPortalSearchStatus.unreadable) {
      return coverage.limit == SupplierNeedCoverageLimit.parserDrift ||
              coverage.limit == SupplierNeedCoverageLimit.encoding
          ? 'El portal cambió de forma y su catálogo dejó de poder leerse; '
              'no se concluyó nada.'
          : 'El portal respondió, pero su catálogo no se pudo leer.';
    }
    if (status == SupplierNeedPortalSearchStatus.noMatches || matches.isEmpty) {
      return canAssertAbsence
          ? 'Se revisó ${coverage.scopeLabel} y no hay ningún producto que '
              'cumpla lo pedido.'
          : 'La búsqueda «$query» no devolvió productos, y no se alcanzó a '
              'revisar el catálogo completo.';
    }
    if (exactCount == 0 && possibleCount == 0 && conflictCount > 0) {
      return 'El portal mostró $conflictCount '
          '${conflictCount == 1 ? 'producto, pero contradice' : 'productos, pero contradicen'} '
          'la ficha pedida. ${coverage.sentence}';
    }
    final parts = <String>[
      if (exactCount > 0)
        '$exactCount ${exactCount == 1 ? 'coincidencia exacta' : 'coincidencias exactas'}',
      if (possibleCount > 0)
        '$possibleCount ${possibleCount == 1 ? 'resultado por revisar' : 'resultados por revisar'}',
    ];
    return '${parts.join(' · ')}. ${coverage.sentence} '
        'El portal prueba catálogo y precio, no unidades disponibles.';
  }

  /// Filas que se revisaron pero no alcanzaron a guardarse por el tope.
  ///
  /// **No son lo mismo que las descartadas.** Una fila contradicha se miró y
  /// se rechazó con evidencia; una omitida no se juzgó nunca. Sumarlas —como
  /// hacía este encabezado— convierte 80 filas sin evaluar en 80 que
  /// «contradicen la ficha»: una afirmación sobre productos que nadie comparó.
  int get omittedByCap {
    final omitted = coverage.rowsUnique - coverage.rowsPersisted;
    return omitted > 0 ? omitted : 0;
  }

  /// Filas guardadas que contradicen la ficha pedida.
  int get discardedByConflict {
    final discarded = matches.length - relevantCount;
    return discarded > 0 ? discarded : 0;
  }

  /// Encabezado del panel expandible: qué se revisó y qué se está mostrando.
  String get optionsSummaryLabel {
    final shown = relevantCount;
    final persisted = matches.length;
    final discarded = discardedByConflict;
    final omitted = omittedByCap;
    final parts = <String>[
      // «N opciones relevantes» sumaba lo que el proveedor confirmó con lo que
      // sólo no contradijo. Son dos cosas distintas y el operador decide con
      // ellas separadas.
      if (exactCount > 0 && possibleCount > 0)
        '$exactCount ${exactCount == 1 ? 'exacta' : 'exactas'} · '
            '$possibleCount por revisar'
      else if (exactCount > 0)
        '$exactCount ${exactCount == 1 ? 'opción exacta' : 'opciones exactas'}'
      else if (possibleCount > 0)
        '$possibleCount ${possibleCount == 1 ? 'opción' : 'opciones'} '
            'por revisar'
      else
        shown == 1 ? '1 opción relevante' : '$shown opciones relevantes',
      if (!answersCurrentRevision)
        'revisadas con la ficha anterior'
      else if (reusesEarlierReading)
        'evaluadas sobre lo que ya habíamos leído',
    ];
    if (discarded > 0) {
      parts.add('$discarded de $persisted '
          '${discarded == 1 ? 'contradice' : 'contradicen'} la ficha');
    }
    if (omitted > 0) {
      parts.add('$omitted ${omitted == 1 ? 'quedó' : 'quedaron'} sin evaluar '
          'por el tope de guardado');
    }
    return '${parts.join(' · ')} · ${coverage.sentence}';
  }

  String? get ageLabel {
    final at = checkedAt;
    if (at == null) return null;
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'recién';
    if (minutes < 60) return 'hace $minutes min';
    final hours = (minutes / 60).round();
    if (hours < 24) return 'hace $hours ${hours == 1 ? 'hora' : 'horas'}';
    final days = (minutes / 1440).round();
    return 'hace $days ${days == 1 ? 'día' : 'días'}';
  }

  factory SupplierNeedPortalSearchSnapshot.fromJson(
    Map<String, dynamic> json,
  ) {
    final raw = json['results'];
    return SupplierNeedPortalSearchSnapshot(
      query: json['searchQuery']?.toString() ?? '',
      status: switch (json['status']?.toString()) {
        'completed' => SupplierNeedPortalSearchStatus.completed,
        'no_matches' => SupplierNeedPortalSearchStatus.noMatches,
        'session_expired' => SupplierNeedPortalSearchStatus.sessionExpired,
        _ => SupplierNeedPortalSearchStatus.unreadable,
      },
      checkedAt: DateTime.tryParse('${json['checkedAt'] ?? ''}'),
      sourceUrl: _text(json['sourceUrl']),
      coverage: SupplierNeedPortalCoverage.fromJson(json['coverage']),
      searchRevisionNo: (json['searchRevisionNo'] as num?)?.round(),
      currentRevisionNo: (json['currentRevisionNo'] as num?)?.round(),
      // Lo guardado se juzgó cuando se leyó. Volver a evaluarlo es una
      // decisión posterior y explícita del cliente.
      evaluatedRevisionNo: (json['searchRevisionNo'] as num?)?.round(),
      matches: raw is List
          ? raw
              .whereType<Map>()
              .map((entry) => SupplierNeedPortalMatch.fromJson(
                    Map<String, dynamic>.from(entry),
                  ))
              .toList(growable: false)
          : const <SupplierNeedPortalMatch>[],
    );
  }
}

/// Auditable portal URL without userinfo, query, fragment or tokens.
String? sanitizeSupplierNeedPortalEvidenceUrl(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final parsed = Uri.tryParse(raw);
  if (parsed == null ||
      parsed.host.isEmpty ||
      !const <String>{'http', 'https'}.contains(parsed.scheme.toLowerCase())) {
    return null;
  }
  return Uri(
    scheme: parsed.scheme.toLowerCase(),
    host: parsed.host.toLowerCase(),
    port: parsed.hasPort ? parsed.port : null,
    path: parsed.path,
  ).toString();
}

/// Eliminate contradictions before ranking. Unknown portal evidence remains
/// unknown; it never becomes a guessed fact merely to fill a result card.
List<SupplierNeedPortalMatch> matchSupplierNeedCandidates(
  SupplierNeedSearchPlan plan,
  List<SupplierPortalCatalogCandidate> candidates,
) {
  final results = <SupplierNeedPortalMatch>[];
  for (final candidate in candidates) {
    final text = _normalize(
      <String?>[candidate.name, candidate.brand, candidate.rowText]
          .whereType<String>()
          .join(' '),
    );
    final profile = ProductIdentityExtractor.extract(ProductIdentityInput(
      name: candidate.name,
      description: candidate.rowText,
      brandHint: candidate.brand,
      brandIsAsserted: candidate.brand?.trim().isNotEmpty == true,
    ));
    final facts = _candidateFacts(plan, candidate, text, profile);
    // **El mismo juicio en la lista, la previsualización y el contador.** Un
    // valor que ningún lector pudo confirmar se conserva para auditoría, pero
    // no prueba **ni contradice**: el modelo tradujo algo y nadie lo verificó,
    // así que no puede decidir por el operador en ninguna de las tres
    // superficies. La evidencia positiva son las citas que viajan con la fila;
    // un recibo antiguo no trae ninguna y por lo tanto no prueba por omisión.
    // Sin cita persistida se **vuelve a verificar contra la fila**: es más
    // robusto que confiar en una marca, y es lo que salva a un recibo antiguo
    // de dar por probado lo que nadie sostuvo. `brake_system = Shimano` sobre
    // un texto que dice SHIMANO sigue valiendo; `brake_type = Disco
    // Hidráulico` sobre `PASTILLA FRENO DISCO` no, porque la fila trae una de
    // las dos palabras y no dice cuál disco es.
    final sinRespaldo = supplierFactsWithoutBacking(
      candidate: candidate,
      fields: plan.request.fields,
    );
    final proven = <String>[];
    final missing = <String>[];
    final conflicts = <String>[];
    final findings = <SupplyRequirementFinding>[];

    final familyTerms = plan.family.identityTerms
        .map(_normalize)
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    // **La palabra tiene que NOMBRAR el objeto, no aparecer dentro de otro.**
    // Buscar «camara» con `contains` daba por probada la familia en `CAMARAS
    // DE SEGURIDAD CCTV` y en `SOPORTE DE CAMARA PARA AUTO`, que es lo que
    // devuelve el buscador de Derman al preguntar por cámaras. Si el término
    // no aparece como palabra, la familia queda pendiente —nunca contradicha—
    // y la fila baja a «por verificar»: el lado seguro del error.
    final familyByVocabulary =
        familyTerms.any((term) => _containsWord(text, term));
    // **El vocabulario suple el silencio, no corrige al extractor.** Con un
    // `||`, una fila que el extractor ya había reconocido como OTRO objeto
    // pasaba igual con sólo tener la palabra dentro. Medido el 2026-08-30
    // pidiendo un motor de centro a RBX: `BIELAS Y EJE MOTOR ALUMINIO` y
    // `CUBETA MOTOR 34.8 DERECHO` —bielas y cubetas, otras piezas— entraron
    // las nueve al listado porque dicen «motor», y el operador se quedó con
    // 8 «falta confirmar» que ni siquiera eran lo que pidió.
    // **Lo que el proveedor nombró, leído del texto.** Es la única fuente que
    // no depende de una lista escrita a mano: `CUBETA` no estaba en la
    // taxonomía canónica y por eso una cubeta pasaba por motor de centro.
    // **Lo que el modelo COPIÓ decide; lo que opina, no.** `head` es el
    // sustantivo con que el proveedor nombra la pieza, copiado exacto de su
    // texto y verificable: es evidencia. `is_requested` es un veredicto, y se
    // contamina con el pedido — el 2026-08-31, diez filas con
    // `head = PASTILLA FRENO DISCO` traían `is_requested = false`.
    //
    // El head se **clasifica**, no se busca por contención: `SEPARADOR PARA
    // PASTILLAS` contiene la palabra y no es una pastilla. Si el extractor no
    // sabe clasificarlo, manda su **sustantivo**, que en español encabeza.
    final head = facts[kSupplierObjectHeadFact]?.toString().trim() ?? '';
    final headText = _normalize(head);
    final headFamily = head.isEmpty
        ? null
        : ProductIdentityExtractor.extract(ProductIdentityInput(name: head))
            .familyId;
    // Las familias sólo se comparan si las dos son ids canónicos: un adaptador
    // puede rotular la suya con etiqueta propia, y un desacuerdo de etiquetas
    // no es evidencia de otra pieza.
    final planFamilyEsCanonica =
        BikePartTaxonomy.byId(plan.family.identityFamily) != null;

    if (head.isNotEmpty &&
        headFamily != null &&
        planFamilyEsCanonica &&
        headFamily != plan.family.identityFamily) {
      conflicts.add('product_family');
    } else if (headFamily != null && headFamily == plan.family.identityFamily) {
      proven.add('product_family');
    } else if (head.isNotEmpty) {
      final sustantivo = headText.split(' ').first;
      if (familyTerms.any((term) => term == sustantivo)) {
        proven.add('product_family');
      } else {
        conflicts.add('product_family');
      }
    } else if (profile.familyId != null &&
        planFamilyEsCanonica &&
        profile.familyId != plan.family.identityFamily) {
      // **Sin head, el extractor gana al vocabulario.** Que la palabra aparezca
      // en la fila no rescata a una pieza que el extractor ya reconoció como
      // otra: es `CUBETA MOTOR 34.8`, que dice «motor». El vocabulario sigue
      // rescatando cuando el extractor no reconoció nada.
      conflicts.add('product_family');
    } else if (profile.familyId == plan.family.identityFamily ||
        familyByVocabulary) {
      proven.add('product_family');
    } else if (profile.familyId != null) {
      conflicts.add('product_family');
    } else {
      missing.add('product_family');
    }

    for (final predicate in plan.request.predicates) {
      final field = predicate.field.trim();
      if (field.isEmpty) continue;
      // Un valor sin cita que lo sostenga no decide nada: ni prueba ni
      // contradice. Se conserva en `observedFacts` para que el operador lo vea.
      final evidence = sinRespaldo.contains(field)
          ? _PredicateEvidence.unknown
          : _predicateEvidence(
              facts[field],
              predicate,
              plan.request.fieldDefinition(field),
            );
      if (evidence == _PredicateEvidence.proven) {
        proven.add(field);
      } else if (evidence == _PredicateEvidence.conflict) {
        conflicts.add(field);
      } else {
        missing.add(field);
      }
    }

    // **La compatibilidad pedida es un requisito, no un adorno.** Si la
    // petición nombra un modelo y la fila no lo trae, no se puede llamar
    // exacta a esa fila por ser Shimano y de resina: eso es cumplir dos specs,
    // no calzar. Queda pendiente hasta que alguien la demuestre, y nunca
    // elimina por identidad.
    final modelosPedidos = _requestModelCodes(plan.request);
    if (modelosPedidos.isNotEmpty) {
      final rawRowText = <String?>[candidate.name, candidate.rowText]
          .whereType<String>()
          .join(' ');
      final declarados = <String>{
        ...profile.modelCodes,
        ...profile.compatibilityModelCodes,
      };
      if (modelosPedidos.any((code) => _modelIsDenied(rawRowText, code))) {
        conflicts.add(kCompatibilityRequirementField);
      } else if (modelosPedidos.any(declarados.contains)) {
        proven.add(kCompatibilityRequirementField);
      } else {
        missing.add(kCompatibilityRequirementField);
      }
    }

    // **Lo que la petición exige y la ficha no supo expresar.** Un requisito no
    // deja de existir porque la plantilla no tenga ese campo, y detectar una
    // negación en la fila no alcanza: importan las cuatro respuestas —afirmado,
    // negado, desconocido y con qué alcance—. Con sólo «la fila niega una
    // palabra del pedido», `SIN ALETAS` pedido contra `SIN ALETAS` ofrecido
    // salía contradicho y contra `CON ALETAS` salía exacto, que es el juicio
    // invertido; y un rodamiento que no menciona sellos pasaba por cumplir.
    final propiedades = _requestedProperties(plan);
    // **Un recibo mal formado no puede tumbar la lista entera.** Esto llega de
    // una fila persistida meses atrás: si el valor no es un mapa, o la lectura
    // no es un mapa, se ignora esa entrada y se sigue. Y cada lectura viaja
    // atada a **la palabra del taller** que la originó: un término interno
    // coincide por casualidad entre peticiones distintas, la frase no.
    final lecturasDelProveedor =
        <String, ({String reading, String quote, String signature})>{};
    final crudo = candidate.technicalFacts[kSupplierRequirementReadingFact];
    if (crudo is Map) {
      for (final entry in crudo.entries) {
        final lectura = entry.value;
        if (lectura is! Map) continue;
        lecturasDelProveedor['${entry.key}'.trim()] = (
          reading: '${lectura['reading'] ?? ''}',
          quote: '${lectura['quote'] ?? ''}',
          signature: '${lectura['signature'] ?? ''}'.trim(),
        );
      }
    }
    if (propiedades.isNotEmpty) {
      var veredicto = _PredicateEvidence.proven;
      for (final propiedad in propiedades) {
        // **Lo que la fila declara manda sobre lo que el modelo interpretó.**
        // Una exigencia remitida por inferencia se juzga como cualquier otra:
        // si el proveedor escribe `DE KEVLAR` está demostrada, si escribe `SIN
        // KEVLAR` está contradicha, y si no dice nada queda pendiente. Cortar
        // antes de mirar la fila borraba las dos primeras y convertía evidencia
        // directa del producto en incertidumbre nuestra.
        //
        // Y la frontera se sostiene sola: la inferencia nunca completa, porque
        // el silencio de la fila ya es «pendiente». Lo que el tramo aporta es
        // saber **cuál criterio** representa esa exigencia, para poder decirlo.
        final evidencia = _propertyEvidence(text, propiedad);
        if (evidencia == _PredicateEvidence.conflict) {
          veredicto = _PredicateEvidence.conflict;
          break;
        }
        if (evidencia == _PredicateEvidence.unknown) {
          veredicto = _PredicateEvidence.unknown;
        }
      }
      switch (veredicto) {
        case _PredicateEvidence.conflict:
          conflicts.add(kRequestedPropertyField);
        case _PredicateEvidence.unknown:
          missing.add(kRequestedPropertyField);
        case _PredicateEvidence.proven:
          proven.add(kRequestedPropertyField);
      }
    }
    // **Lo que se sabe de cada exigencia, separado por cómo se sabe.** El
    // estado de la fila ya está decidido arriba; esto es lo que se muestra, y
    // es donde la lectura del modelo se vuelve útil sin volverse un hecho.
    for (final propiedad in propiedades) {
      final evidencia = _propertyEvidence(text, propiedad);
      final registrada = lecturasDelProveedor[propiedad.stem];
      // **La lectura responde una pregunta, no una palabra.** Se compara la
      // exigencia entera —polaridad, dimensión y alcance—; un recibo que no
      // dice qué pregunta contestó no puede reclamar ninguna, así que se ignora
      // y la exigencia queda como desconocida, que es lo que de verdad se sabe.
      final firma = SupplyNeedUnmodelledRequirement(
        term: propiedad.stem,
        tail: propiedad.tail,
        label: propiedad.label,
        affirmed: propiedad.affirmed,
        scope: propiedad.scope.toList(growable: false),
      ).signature;
      final lectura =
          registrada == null || registrada.signature != firma ? null : registrada;
      findings.add(SupplyRequirementFinding(
        label: propiedad.label.isEmpty ? propiedad.stem : propiedad.label,
        affirmed: propiedad.affirmed,
        status: switch (evidencia) {
          // El texto manda: si lo dice, está dicho.
          _PredicateEvidence.proven => SupplyRequirementStatus.proven,
          _PredicateEvidence.conflict => SupplyRequirementStatus.contradicted,
          // Y si no lo dice, se muestra lo que el modelo alcanzó a leer, con
          // su cita, o se admite que no se sabe.
          _PredicateEvidence.unknown => switch (lectura?.reading) {
              'contradicts' => SupplyRequirementStatus.contradicted,
              'suggests' => SupplyRequirementStatus.inferred,
              'suggestsAgainst' => SupplyRequirementStatus.doubted,
              _ => SupplyRequirementStatus.unknown,
            },
        },
        quote: (lectura?.quote.isNotEmpty ?? false) ? lectura!.quote : null,
      ));
    }

    final state = conflicts.isNotEmpty
        ? SupplierNeedMatchState.conflict
        : missing.isEmpty && plan.request.predicates.isNotEmpty
            ? SupplierNeedMatchState.exact
            : SupplierNeedMatchState.possible;
    results.add(SupplierNeedPortalMatch(
      candidate: candidate,
      state: state,
      provenFields: List.unmodifiable(proven),
      missingFields: List.unmodifiable(missing),
      conflictingFields: List.unmodifiable(conflicts),
      observedFacts: Map.unmodifiable(facts),
      requirementFindings: List.unmodifiable(findings),
    ));
  }
  results.sort((left, right) {
    final byState = left.state.index.compareTo(right.state.index);
    if (byState != 0) return byState;
    return left.candidate.name.compareTo(right.candidate.name);
  });
  // **Un «sin coincidencias» con 27 filas calzadas no dice nada por sí solo.**
  // Saber por qué campo se cae cada fila es la diferencia entre arreglar el
  // defecto y adivinar cuál de cinco compuertas fue.
  if (kDebugMode && results.isNotEmpty) {
    final porCampo = <String, int>{};
    for (final match in results) {
      for (final field in match.conflictingFields) {
        porCampo[field] = (porCampo[field] ?? 0) + 1;
      }
    }
    final exactas =
        results.where((m) => m.state == SupplierNeedMatchState.exact).length;
    debugPrint('🔎 calce: ${results.length} filas · exactas=$exactas · '
        'contradicen={${porCampo.entries.map((e) => '${e.key}:${e.value}').join(', ')}}');
  }
  return List.unmodifiable(results);
}

/// Los campos de una fila cuyo valor **nadie sostiene**.
///
/// Un escalar que viaja con la fila no es evidencia por existir: puede venir de
/// un recibo antiguo que se guardó sin cita, o de una lectura que confundió al
/// fabricante con el sistema al que la pieza sirve. Un campo sin respaldo no
/// prueba **ni contradice** —se conserva en `observedFacts` para que el
/// operador lo vea—, y esa decisión tiene que ser **la misma** en la lista, en
/// la previsualización y en el contador.
///
/// Vive acá porque estaba escrita dos veces y las dos copias divergieron: la
/// segunda no distinguía marca de compatibilidad, y con eso `MAGURA
/// CLARA/LOUISE`, `A10YS` y `D40.11` salían del preview sin que nadie hubiera
/// tocado un criterio.
Set<String> supplierFactsWithoutBacking({
  required SupplierPortalCatalogCandidate candidate,
  required List<SupplierNeedSearchField> fields,
}) {
  final citas = <String>{
    for (final entry in (candidate.technicalFacts[kSupplierFactQuotesFact]
                as Map<Object?, Object?>? ??
            const <Object?, Object?>{})
        .entries)
      '${entry.key}'.trim(),
  };
  final rawRowText = <String?>[candidate.name, candidate.rowText]
      .whereType<String>()
      .join(' ');
  final normalizedRowText = _normalize(rawRowText);
  return <String>{
    ..._inferredFieldsOf(candidate),
    for (final field in fields)
      if (candidate.technicalFacts[field.key] case final valor?)
        // Un escalar antiguo que sólo repite la marca no es evidencia del
        // sistema compatible: es justo la lectura errónea que traen los
        // recibos viejos.
        if (_valueIsOnlyBrand(
          normalizedRowText,
          _normalize('$valor'),
          candidate.brand,
        ))
          field.key.trim()
        else if (!citas.contains(field.key.trim()) &&
            supplierQuoteEvidence(
                  field: field,
                  value: valor,
                  quote: rawRowText,
                  rowText: rawRowText,
                ) !=
                SupplierSpecEvidence.stated)
          field.key.trim(),
  };
}

/// Reinterprets one already-enumerated supplier catalogue against the current
/// technical predicates.
///
/// The database only returns snapshots whose stored category equals the need's
/// latest category. This function therefore changes the derived verdicts, not
/// the evidence source: timestamp, URL and coverage remain those of the real
/// portal read. A refinement is immediate without pretending a second network
/// visit happened.
SupplierNeedPortalSearchSnapshot rematchSupplierNeedPortalSnapshot(
  SupplierNeedSearchPlan plan,
  SupplierNeedPortalSearchSnapshot snapshot, {
  /// La revisión vigente contra la que se acaba de juzgar.
  ///
  /// Una lectura que **nunca llegó a guardarse** no trae la revisión vigente
  /// del servidor: la trae quien la está rejuzgando. Sin esto, el veredicto
  /// recién calculado quedaba rotulado «Ficha anterior» aunque acabara de
  /// responder la ficha nueva.
  int? currentRevisionNo,
}) {
  if (snapshot.status != SupplierNeedPortalSearchStatus.completed) {
    return snapshot;
  }
  final matches = matchSupplierNeedCandidates(
    plan,
    snapshot.matches.map((match) => match.candidate).toList(growable: false),
  );
  return SupplierNeedPortalSearchSnapshot(
    query: snapshot.query,
    status: snapshot.status,
    // La marca de tiempo, la cobertura y la revisión LEÍDA no se tocan: son
    // el hecho de que alguien consultó ese portal en ese momento para esa
    // ficha. Lo único que cambia es contra qué se juzgaron las filas.
    checkedAt: snapshot.checkedAt,
    matches: matches,
    sourceUrl: snapshot.sourceUrl,
    coverage: snapshot.coverage,
    searchRevisionNo: snapshot.searchRevisionNo,
    currentRevisionNo: currentRevisionNo ?? snapshot.currentRevisionNo,
    evaluatedRevisionNo: currentRevisionNo ??
        snapshot.currentRevisionNo ??
        snapshot.evaluatedRevisionNo,
    // **La identidad de la corrida sobrevive al refiltrado.** Rejuzgar cambia
    // el veredicto, no quién recorrió el portal ni cuándo. Perderla acá dejaba
    // sin clave a la lectura justo después de precisar, y con eso: el recibo
    // pendiente ya no podía resolverse por clave —se reintentaría a ciegas o
    // no se reintentaría— y la regla de procedencia dejaba de reconocer que la
    // guardada y la de memoria son la MISMA corrida, cayendo a comparar horas
    // entre dos formas del mismo recorrido.
    operationKey: snapshot.operationKey,
  );
}

/// Cuál de las dos lecturas es **la de ahora**.
///
/// `stored ?? inMemory` parecía razonable —la guardada es durable— y consagraba
/// el caso al revés: con un recibo viejo en la base y la corrida de recién sólo
/// en memoria porque su recibo falló, ganaba el feed viejo. Durable no es lo
/// mismo que vigente, y lo que el operador está mirando es el recorrido más
/// reciente.
///
/// Se decide por **procedencia real**, en este orden:
///
/// 1. Si una sola existe, ésa.
/// 2. Si las dos llevan la MISMA `operationKey`, son la misma corrida: gana la
///    guardada, que es su forma durable y trae lo que el servidor validó.
/// 3. Si no, gana la de `checkedAt` más reciente. Un empate lo gana la
///    guardada, por la misma razón. Y una lectura **sin hora no puede
///    declararse más nueva**: sólo gana la de memoria cuando lo demuestra.
///
/// El alcance —que las dos sean de esta necesidad— no se decide acá: la
/// guardada la devuelve el RPC ya acotada por `supply_need_id`, y la de memoria
/// la sostiene la página, que sólo conserva el feed mientras no se cambie de
/// necesidad. Esta función nunca ve un id, así que no puede cruzarlas.
SupplierNeedPortalSearchSnapshot? _morePresentReading(
  SupplierNeedPortalSearchSnapshot? stored,
  SupplierNeedPortalSearchSnapshot? inMemory,
) {
  if (stored == null) return inMemory;
  if (inMemory == null) return stored;
  final key = stored.operationKey;
  if (key != null && key == inMemory.operationKey) return stored;
  final reciente = inMemory.checkedAt;
  final guardada = stored.checkedAt;
  if (reciente != null && (guardada == null || reciente.isAfter(guardada))) {
    return inMemory;
  }
  return stored;
}

/// Qué lectura de portal sigue viva para esta necesidad después de precisar.
///
/// **El contrato: precisar conserva el feed.** El 2026-08-30 una corrida real
/// recorrió el portal de RBX entero, leyó 27 filas y no pudo guardar el recibo
/// —504 del gateway—. Al guardar un criterio, la página recargaba las lecturas
/// **sólo desde la base**, no encontraba nada y el proveedor volvía a «sin
/// consultar»: minutos de navegación real borrados de la pantalla por un fallo
/// de transporte que no es del proveedor. Conservar la petición y la categoría
/// no basta si el feed desaparece.
///
/// Acá se decide con las dos fuentes por procedencia real —`_morePresentReading`
/// tiene la regla completa—: la misma `operationKey` es la misma corrida y ahí
/// manda la guardada; si no, gana la más reciente. En cualquier caso el
/// **veredicto** se recalcula contra el plan vigente: nunca se reusa el juicio
/// viejo.
///
/// **Es una función pura sobre filas que ya están en memoria.** No recibe ni
/// puede recibir un colaborador de red: rejuzgar no vuelve al portal.
SupplierNeedPortalSearchSnapshot? carrySupplierNeedPortalSearch({
  required SupplierNeedPortalSearchSnapshot? stored,
  required SupplierNeedPortalSearchSnapshot? inMemory,
  required SupplierNeedSearchPlan? plan,
  int? currentRevisionNo,
}) {
  final base = _morePresentReading(stored, inMemory);
  if (base == null) return null;
  if (plan == null) return base;
  return rematchSupplierNeedPortalSnapshot(
    plan,
    base,
    currentRevisionNo: currentRevisionNo,
  );
}

/// Lo que un texto declara sobre los campos de una ficha.
///
/// **Un solo lector para las dos orillas.** Esto lee la fila de un proveedor y
/// lee la línea que escribió el operador: es el mismo objeto descrito en el
/// mismo idioma, y tener dos lectores es cómo «Cámaras 700» se convierte en una
/// ficha muda mientras `CAMARA 700 X 18/25C` sí se entiende. Lo que queda
/// afuera son los `capturePatterns`, que pertenecen al adaptador de un portal
/// concreto y no describen una petición.
void _addTextualSpecFacts({
  required void Function(String key, Object? value) addFact,
  required bool Function(String key) alreadyKnown,
  required List<SupplierNeedSearchField> fields,
  required String text,
  required String rawText,
  required ProductIdentityProfile profile,

  /// La marca declarada de la fila, para no confundirla con el sistema al que
  /// la pieza sirve.
  String? candidateBrand,

  /// El texto sin la marca añadida al final, para juzgar dónde aparece cada
  /// palabra sin el contexto que le presta el token vecino.
  String brandFreeText = '',

  /// Los sustantivos con que se nombra el objeto —`camara`, `llanta`, `aro`—.
  /// Es lo que convierte un número en una medida: `LLANTA 26 VISION` dice su
  /// aro, y `presupuesto 700 pesos` no.
  List<String> familyHeads = const <String>[],
}) {
  // **La medida que nombra al objeto, y va primero.** Un número pegado al
  // sustantivo es el aro de una rueda o el diámetro de un disco —lo que uno
  // diría en voz alta al pedirlo—, nunca los radios ni el largo de la válvula,
  // que se escriben con su propia palabra (`32 hoyos`, `48mm`): sin ese
  // recorte, «Aro 24» habría declarado además 24 perforaciones.
  //
  // Corre **antes** que el extractor de identidad porque es el único que ve la
  // ambigüedad completa. Con `Cámara 700` como nombre reconocido y `cámara aro
  // 26` como petición, el extractor elegía una; acá se ven las dos, se anulan
  // entre sí en `addFact` y el campo queda sin afirmar para todo lector
  // posterior, que es la verdad.
  // **Lo que cuenta como segunda medida es lo que el contexto declara como
  // medida.** Contar cualquier número permitido que apareciera en el texto
  // borraba el dato bueno: `Cámara 700, código 26 del proveedor` decía 700 y
  // quedaba mudo. Las dos evidencias válidas son la lectura dimensional
  // —`700X28C Y 26X1.75`, un surtido de verdad— y la adyacencia al sustantivo.
  // Si la lectura dimensional ya vio DOS medidas, la fila las tiene mezcladas y
  // esta vía no opina: `CAMARA 700X28C Y 26X1.75 SURTIDO` no afirma ninguna.
  // **No se marca ambigüedad desde acá.** Hacerlo tumbaba filas cuyo segundo
  // número es una nota de equivalencia y no un surtido —`CAMARA 28 X 1.5/8 …
  // (27X1.1/4)`, donde 28 es la medida y el paréntesis su equivalencia—, que
  // el extractor de identidad sí sabe resolver.
  final mezclaDeMedidas = supplierWheelSizesFromText(text).length > 1;
  final tomadas = <double>{};
  for (final field in fields) {
    if (alreadyKnown(field.key) || mezclaDeMedidas) continue;
    if (!_objectNamingMeasures.contains(_identityKindByField[field.key])) {
      continue;
    }
    // Dos medidas pegadas a un sustantivo sí se anulan entre sí: ahí las dos
    // están dichas como medida.
    for (final size in _familyAdjacentSizesFromText(
      text,
      familyHeads,
      field.allowedValues,
    )) {
      addFact(field.key, size);
      tomadas.add(size);
    }
  }

  // **Una medida ya asignada deja de competir por los demás campos.** `Aro 26
  // 36 hoyos` —la forma en que se escribe de verdad— dejaba las perforaciones
  // mudas: con dos números pegados el extractor de identidad no separa cuál es
  // cuál, y con un `de` en medio sí. Releerlo sin el número que ya tiene dueño
  // desempata, y no agrega vocabulario: `hoyos` ya lo sabe el extractor, la
  // ficha ni siquiera lo nombra —se llama «Número de Rayos / Perforaciones»—.
  var perfil = profile;
  if (tomadas.isNotEmpty) {
    var limpio = text;
    for (final size in tomadas) {
      final escrito = size == size.roundToDouble()
          ? size.toStringAsFixed(0)
          : size.toString();
      limpio = limpio.replaceAll(
        RegExp('(?:^|(?<=[^0-9.,]))${RegExp.escape(escrito)}(?=[^0-9]|\$)'),
        ' ',
      );
    }
    if (limpio != text) {
      perfil = ProductIdentityExtractor.extract(
        ProductIdentityInput(name: limpio),
      );
    }
  }

  for (final field in fields) {
    if (alreadyKnown(field.key)) continue;
    final kind = _identityKindByField[field.key];
    if (kind == null) continue;
    // **El tipo de válvula sólo se lee del marcador.** El extractor de
    // identidad toma `AUTO` de cualquier parte de la frase, y `SOPORTE DE
    // CAMARA PARA AUTO CON VENTOSA` entraba al listado como americana
    // confirmada. Acá manda `V/…`, `VAL. …`, `VALVULA …` o `F/V`; sin
    // marcador no hay dato, que es la verdad.
    if (kind == PartSpecKind.valveType) continue;
    final observado = perfil.specs[kind] ?? profile.specs[kind];
    // **La cantidad no es una medida, venga de donde venga.** El extractor de
    // identidad también lee `Cámaras 29, unidades` como aro 29, y el guard de
    // cantidad estaba sólo en la lectura por familia: dependía del camino, no
    // del hecho.
    if (_objectNamingMeasures.contains(kind) &&
        _numberIsCountedOrPriced(text, observado)) {
      continue;
    }
    addFact(field.key, observado);
  }

  // **Un tamaño de rueda viene pegado a otra medida.** El catálogo no escribe
  // «700c»: escribe `CAMARA 700X28/38C`. Sin esta lectura, enumerar el nodo
  // completo sólo cambia 10 filas «por revisar» por 19 —medido sobre las 19
  // filas de `CAMARAS RUTA`: cero hechos observados—, y el operador sigue sin
  // poder elegir. Es una convención de la industria, no una regla de RBX ni de
  // las cámaras: la usa cualquier parte con rueda.
  for (final field in fields) {
    if (alreadyKnown(field.key)) continue;
    if (_identityKindByField[field.key] != PartSpecKind.wheelSize) continue;
    addFact(field.key, supplierWheelSizeFromText(text));
    // **La pulgada se marca con comillas, y el normalizador se las come.**
    // `Alexrims Llanta MD30 SSE 27.5" 28h` dice su aro con todas las letras y
    // llegaba mudo: el patrón de comillas existía, pero corría sobre el texto
    // ya normalizado, donde la comilla no está. Es el mismo motivo por el que
    // la fracción se lee del crudo.
    addFact(field.key, supplierWheelSizeFromText(rawText));
    // El normalizador canónico borra `/` y `-`, así que `8-1/2 X 2` llega como
    // `8 1 2 x 2` y la rueda de un scooter queda sin medida. Sin leerla del
    // texto crudo, `CAMARA SCOOTER 8-1/2 X 2` no contradecía «aro 700`: no
    // entraba por parecerse, entraba por no decir nada.
    addFact(field.key, supplierFractionalWheelSizeFromText(rawText));
  }

  // **El proveedor escribe el tipo de válvula pegado a `V/`.** `V/DUNLOP`,
  // `V/FRANC.`, `VALVULA SCHRADE`: formas que ninguna lista de valores
  // permitidos contiene, así que la ficha quedaba muda y la fila sobrevivía a
  // cualquier criterio de válvula. Se lee sólo la palabra que sigue al marcador
  // —`AUTOSELLANTE` y `AUTOMATICA` no son válvulas, y confundirlas con
  // `V/AUTO` es lo que hacía pasar dos cámaras Dunlop por americanas.
  for (final field in fields) {
    if (alreadyKnown(field.key)) continue;
    if (_identityKindByField[field.key] != PartSpecKind.valveType) continue;
    addFact(field.key, supplierValveTypeFromText(text));
  }

  // **Un booleano se nombra con su propia palabra.** No tiene `allowed_values`
  // que reconocer, pero sí una etiqueta, y esa etiqueta ES el vocabulario de la
  // ficha: `Trae líquido sellante`, `Tubeless ready`, `Flotante`. Si esa
  // palabra está en el texto, el dato está dicho; si viene negada, también.
  //
  // No se mina la descripción del campo, que es prosa: la de `tube_has_sealant`
  // dice «anti-pinchazo», y con eso «cámara con pinchazo» —una cámara
  // reventada— habría quedado declarada como autosellante.
  for (final field in fields) {
    if (alreadyKnown(field.key)) continue;
    if (field.dataType.trim().toLowerCase() != 'boolean') continue;
    addFact(
      field.key,
      supplierBooleanFromFieldVocabulary(
        text: text,
        label: field.label,
        description: field.description,
        familyHeads: familyHeads,
      ),
    );
  }
  // **Y si el texto trae una palabra de la propia ficha, eso es un dato.** Medido sobre cuatro fichas reales el 2026-08-30: `6 pernos`,
  // `Centerlock`, `1/8`, `3/32`, `Butilo` y `700c` estaban **literales** en la
  // petición y no llegaban a ninguna parte, porque el lector de identidad sólo
  // reconoce las medidas que sabe extraer. Esto no es un diccionario nuevo: el
  // vocabulario es el de la ficha, la misma lista que le muestra al operador el
  // desplegable. Vale para las dos orillas: el operador escribe `1/8` y el
  // proveedor titula `Cadena 1/2 X 1/8 Kmc`. Sin esto el criterio se derivaba y
  // no eliminaba nada, porque del lado del catálogo nadie sabía leerlo.
  //
  // Se excluyen dos clases, y las dos por la misma razón —afirmarían algo que
  // el texto no dice—:
  //
  // - **Los valores que son puro número** una vez normalizados (`26"` → `26`,
  //   `140`, `32`). Un número suelto puede ser una cantidad, un precio o un
  //   código; los que sí se pueden leer ya tienen su camino por medida o por
  //   marcador. Una **fracción** sí pasa —`1/8`, `3/32`, `160/140`—: nadie
  //   escribe una cantidad con barra, así que es una medida escrita a
  //   propósito.
  // - **Los comodines de la ficha** —`Otra`, `Otro`, `Desconocido`—, que son su
  //   forma de decir «no consta». Derivarlos convertiría la ignorancia en un
  //   criterio, y además cazarían cualquier «otro» de una frase normal.
  final normalizedText = ' $text ';
  final heads = <String>{for (final head in familyHeads) _normalize(head)};

  // **Una pareja compacta se reparte por los valores de la ficha.** `Motor de
  // centro 73 x 118` dice las dos medidas y el módulo las estaba tirando: 73 es
  // un ancho de caja y no un largo de eje, 118 es un largo de eje y no un ancho
  // de caja, así que el reparto es único. Lo decide la ficha —no un orden fijo
  // ni una tabla por familia—, y por eso también funciona escrito al revés y en
  // un nombre de catálogo (`Eje De Motor Sellado 68 X 113mm`).
  //
  // No pisa la rueda: una ficha de cámara o de llanta no tiene dos campos
  // numéricos con valores permitidos donde repartir `700 x 28`, así que ahí no
  // se forma ninguna pareja.
  for (final pareja in _numericPairsFromText(text)) {
    final reparto = _assignPairToFields(pareja, fields, alreadyKnown);
    if (reparto == null) continue;
    reparto.forEach(addFact);
  }

  for (final field in fields) {
    if (alreadyKnown(field.key)) continue;
    // **La válvula tiene su propio lector y su propia regla: sólo el
    // marcador.** Sus valores traen palabras —`Dunlop`, `americana`,
    // `francesa`— que aparecen en cualquier parte de un nombre, y `Dunlop` es
    // además una MARCA: `CAMARA DUNLOP 700X25C` no dice nada de su válvula.
    // Leerla por acá sería entrar por la puerta de atrás al contrato que existe
    // justamente porque `AUTO` de `AUTOSELLANTE` ya hizo pasar dos cámaras
    // Dunlop por americanas.
    if (_identityKindByField[field.key] == PartSpecKind.valveType) continue;
    final hits = <({Object value, String normalized})>[];
    for (final candidate in field.allowedValues) {
      final normalizedValue = _normalize('$candidate');
      if (normalizedValue.isEmpty) continue;
      if (_isFichaWildcard(normalizedValue)) continue;
      final esFraccion = '$candidate'.contains('/');
      if (!esFraccion && !RegExp(r'[a-z]').hasMatch(normalizedValue)) continue;
      if (!normalizedText.contains(' $normalizedValue ') &&
          !_textNamesValueConcept(normalizedText, normalizedValue)) {
        continue;
      }
      // El fabricante no es el sistema al que la pieza sirve.
      if (_valueIsOnlyBrand(
        brandFreeText.isEmpty ? text : brandFreeText,
        normalizedValue,
        candidateBrand,
      )) {
        continue;
      }
      hits.add((value: candidate, normalized: normalizedValue));
    }
    if (hits.isEmpty) {
      // **Una palabra que nombra a UN solo valor de ese campo también lo
      // dice.** La ficha del motor de centro ofrece `Rodamiento sellado`,
      // `Integrado` y `Cubetas y canastillo`; el taller dice «motor de centro
      // **sellado**», que es una sola de las tres. Sigue siendo vocabulario de
      // la ficha —las palabras son de sus propios valores—, y si la palabra
      // alcanza a dos valores no elige: `eje cuadrado` no distingue
      // `Cuadrado JIS` de `Cuadrado ISO`, y eso es no saber.
      final unicos = <Object>{};
      for (final palabra in normalizedText.split(' ')) {
        if (palabra.length < 6) continue;
        if (heads.contains(palabra)) continue;
        Object? unico;
        var cuantos = 0;
        for (final candidate in field.allowedValues) {
          final normalizedValue = _normalize('$candidate');
          if (_isFichaWildcard(normalizedValue)) continue;
          if (!' $normalizedValue '.contains(' $palabra ')) continue;
          cuantos += 1;
          unico = candidate;
        }
        if (cuantos == 1 && unico != null) unicos.add(unico);
      }
      for (final value in unicos) {
        addFact(field.key, value);
      }
      continue;
    }
    // **Gana el más largo, y un valor contenido en él no es una ambigüedad.**
    // `rotor_material` ofrece `Acero` y `Acero Inoxidable`: en «acero
    // inoxidable» calzan los dos, y tratarlos como contradicción cancelaba un
    // criterio que el texto dice sin ninguna duda. Sólo hay ambigüedad cuando
    // el otro valor **no** es parte del elegido —«centerlock o 6 pernos»—.
    hits.sort((a, b) => b.normalized.length.compareTo(a.normalized.length));
    final elegido = hits.first;
    addFact(field.key, elegido.value);
    for (final other in hits.skip(1)) {
      if (elegido.normalized.contains(other.normalized)) continue;
      addFact(field.key, other.value);
    }
  }
}

/// Si el texto nombra ese valor **con otra palabra que el dominio reconoce**.
///
/// La misma equivalencia canónica que impide inventar un requisito ya cubierto
/// sirve acá para la orilla contraria: `PASTILLA DE RESINA` declara su
/// compuesto aunque la ficha lo rotule `Orgánico`. Una sola normalización para
/// las dos lecturas; si fueran dos, volverían a divergir.
bool _textNamesValueConcept(String normalizedText, String normalizedValue) {
  final concepto = canonicalSupplierSpecConcept(normalizedValue);
  if (concepto == null) return false;
  for (final palabra in normalizedText.split(' ')) {
    if (canonicalSupplierSpecConcept(palabra) == concepto) return true;
  }
  return false;
}

/// Los criterios que la **propia petición** ya declara.
///
/// «Cámaras 700» dice el aro con todas las letras, pero la interpretación
/// guardó sólo la categoría, así que la ficha abría con «Tamaño de rueda: sin
/// especificar» y el criterio que el operador ya había escrito no llegaba ni al
/// formulario, ni a la previsualización, ni al juicio del feed.
///
/// Se lee con el mismo lector que lee al proveedor y se traduce al vocabulario
/// de la ficha con la **misma comparación** que después juzga las filas: si un
/// valor no se puede expresar en la ficha, no se inventa —se omite—.
///
/// Es derivación, no persistencia: lo que devuelve se muestra para que el
/// operador lo vea y pueda cambiarlo, y sólo se guarda si él refina.
List<SupplierNeedSearchPredicate> supplyNeedSpecsStatedInRequest({
  required String description,
  required List<SupplierNeedSearchField> fields,

  /// Los sustantivos de la familia que se está pidiendo. Sin ellos, un número
  /// pegado al objeto —«Cámaras 29»— no se puede distinguir de una cantidad.
  List<String> familyHeads = const <String>[],
}) {
  final clean = description.trim();
  if (clean.isEmpty || fields.isEmpty) {
    return const <SupplierNeedSearchPredicate>[];
  }
  final facts = <String, Object?>{};
  final ambiguous = <String>{};
  void addFact(String key, Object? value) {
    if (key.isEmpty || value == null || ambiguous.contains(key)) return;
    final normalized = value is String ? value.trim() : value;
    if (normalized is String && normalized.isEmpty) return;
    final existing = facts[key];
    if (existing == null) {
      facts[key] = normalized;
      return;
    }
    if (!_valuesEqual(existing, normalized)) {
      facts.remove(key);
      ambiguous.add(key);
    }
  }

  _addTextualSpecFacts(
    addFact: addFact,
    alreadyKnown: (key) => facts.containsKey(key) || ambiguous.contains(key),
    fields: fields,
    text: _normalize(clean),
    rawText: clean,
    profile: ProductIdentityExtractor.extract(
      ProductIdentityInput(name: clean),
    ),
    familyHeads: familyHeads,
  );

  final stated = <SupplierNeedSearchPredicate>[];
  for (final field in fields) {
    final observed = facts[field.key];
    if (observed == null) continue;
    final value = _statedFieldValue(field, observed);
    if (value == null) continue;
    stated.add(SupplierNeedSearchPredicate(
      field: field.key,
      operator: 'eq',
      values: <Object>[value],
    ));
  }
  return List<SupplierNeedSearchPredicate>.unmodifiable(stated);
}

/// Las parejas `A x B` que el texto escribe pegadas.
List<({double left, double right})> _numericPairsFromText(String text) {
  final pairs = <({double left, double right})>[];
  final expression = RegExp(
    r'(?:^|[^0-9.,])(\d{2,3}(?:[.,]\d+)?)\s*[x×]\s*(\d{2,3}(?:[.,]\d+)?)',
  );
  for (final match in expression.allMatches(text)) {
    final left = _number(match.group(1));
    final right = _number(match.group(2));
    if (left == null || right == null) continue;
    pairs.add((left: left, right: right));
  }
  return pairs;
}

/// A qué campos pertenece esa pareja, si el reparto es **único**.
///
/// Cada número se ofrece a los campos numéricos cuya lista de valores lo
/// contiene. Si un número calza en dos campos, o si los dos calzan en el mismo,
/// no hay reparto: ambiguo no es lo mismo que sabido.
Map<String, Object>? _assignPairToFields(
  ({double left, double right}) pair,
  List<SupplierNeedSearchField> fields,
  bool Function(String key) alreadyKnown,
) {
  Object? valorDe(SupplierNeedSearchField field, double number) {
    for (final candidate in field.allowedValues) {
      final permitido =
          candidate is num ? candidate.toDouble() : _number('$candidate');
      if (permitido != null && permitido == number) return candidate;
    }
    return null;
  }

  final porNumero =
      <bool, List<({SupplierNeedSearchField field, Object value})>>{
    true: <({SupplierNeedSearchField field, Object value})>[],
    false: <({SupplierNeedSearchField field, Object value})>[],
  };
  for (final field in fields) {
    if (alreadyKnown(field.key)) continue;
    if (!_isNumericField(field)) continue;
    if (field.allowedValues.isEmpty) continue;
    final izquierda = valorDe(field, pair.left);
    if (izquierda != null) {
      porNumero[true]!.add((field: field, value: izquierda));
    }
    final derecha = valorDe(field, pair.right);
    if (derecha != null) {
      porNumero[false]!.add((field: field, value: derecha));
    }
  }
  final deIzquierda = porNumero[true]!;
  final deDerecha = porNumero[false]!;
  if (deIzquierda.length != 1 || deDerecha.length != 1) return null;
  if (deIzquierda.single.field.key == deDerecha.single.field.key) return null;
  return <String, Object>{
    deIzquierda.single.field.key: deIzquierda.single.value,
    deDerecha.single.field.key: deDerecha.single.value,
  };
}

bool _isNumericField(SupplierNeedSearchField field) {
  const numericos = <String>{'number', 'integer', 'decimal', 'float'};
  return numericos.contains(field.dataType.trim().toLowerCase());
}

/// Los comodines con que una ficha dice «no consta».
///
/// No son valores: son la ausencia con nombre. Un criterio «material: Otro» no
/// acota nada, y buscarlos en el texto cazaría cualquier «otro» de una frase.
bool _isFichaWildcard(String normalizedValue) =>
    normalizedValue == 'otra' ||
    normalizedValue == 'otro' ||
    normalizedValue == 'otros' ||
    normalizedValue == 'otras' ||
    normalizedValue.startsWith('desconocid');

/// El hecho leído, dicho en el vocabulario de la ficha.
///
/// Un campo de lista sólo acepta uno de sus valores: `700` se guarda como
/// `700c` porque **la misma comparación que juzga las filas** dice que son lo
/// mismo. Escribir esa equivalencia otra vez acá sería un segundo dueño de la
/// verdad, y el día que uno cambie el formulario diría una cosa y el feed otra.
/// Si ningún valor permitido calza, el texto dice algo que esta ficha no sabe
/// expresar y no se fuerza nada.
Object? _statedFieldValue(SupplierNeedSearchField field, Object observed) {
  final allowed = field.allowedValues;
  if (allowed.isEmpty) return observed;
  for (final candidate in allowed) {
    final evidence = _predicateEvidence(
      observed,
      SupplierNeedSearchPredicate(
        field: field.key,
        operator: 'eq',
        values: <Object>[candidate],
      ),
      field,
    );
    if (evidence == _PredicateEvidence.proven) return candidate;
  }
  return null;
}

Map<String, Object?> _candidateFacts(
  SupplierNeedSearchPlan plan,
  SupplierPortalCatalogCandidate candidate,
  String text,
  ProductIdentityProfile profile,
) {
  final facts = <String, Object?>{...candidate.technicalFacts};
  final ambiguous = <String>{};

  void addFact(String key, Object? value) {
    if (key.isEmpty || value == null || ambiguous.contains(key)) return;
    final clean = value is String ? value.trim() : value;
    if (clean is String && clean.isEmpty) return;
    final existing = facts[key];
    if (existing == null) {
      facts[key] = clean;
      return;
    }
    if (!_valuesEqual(existing, clean)) {
      facts.remove(key);
      ambiguous.add(key);
    }
  }

  for (final capture in plan.family.capturePatterns) {
    for (final match in capture.expression.allMatches(text)) {
      for (final entry in capture.fieldsByGroup.entries) {
        if (entry.key > match.groupCount) continue;
        final raw = match.group(entry.key);
        addFact(entry.value, _number(raw) ?? raw);
      }
    }
  }

  _addTextualSpecFacts(
    addFact: addFact,
    alreadyKnown: (key) => facts.containsKey(key) || ambiguous.contains(key),
    fields: plan.request.fields,
    text: text,
    rawText: <String?>[candidate.name, candidate.rowText]
        .whereType<String>()
        .join(' '),
    profile: profile,
    candidateBrand: candidate.brand,
    // **Sin la marca pegada al final.** El matcher arma `text` uniendo nombre,
    // marca y fila; ese token suelto hereda el contexto de lo que quedó justo
    // antes, y una fila que termina en «PARA FRENOS SHIMANO» hacía que la
    // propia marca pareciera una declaración de compatibilidad.
    brandFreeText: _normalize(<String?>[candidate.name, candidate.rowText]
        .whereType<String>()
        .join(' ')),
    familyHeads: plan.family.identityTerms,
  );

  final unitUse = <String, int>{};
  for (final predicate in plan.request.predicates) {
    final unit = plan.request.fieldDefinition(predicate.field)?.unit;
    final normalizedUnit = _normalize(unit ?? '');
    if (normalizedUnit.isNotEmpty) {
      unitUse[normalizedUnit] = (unitUse[normalizedUnit] ?? 0) + 1;
    }
  }

  for (final field in plan.request.fields) {
    if (facts.containsKey(field.key) || ambiguous.contains(field.key)) continue;
    final aliases = <String>{
      field.label,
      ...?plan.family.fieldAliases[field.key],
    };
    final anchored = _numberNearAliases(text, aliases, field.unit);
    if (anchored != null) {
      addFact(field.key, anchored);
      continue;
    }
    final unit = _normalize(field.unit ?? '');
    if (unit.isNotEmpty && unitUse[unit] == 1) {
      final unique = _uniqueNumberWithUnit(text, unit);
      if (unique != null) {
        addFact(field.key, unique);
        continue;
      }
    }
    final allowed = _visibleAllowedValue(plan.family, field, text);
    if (allowed != null) addFact(field.key, allowed);
  }

  return facts;
}

enum _PredicateEvidence { proven, conflict, unknown }

_PredicateEvidence _predicateEvidence(
  Object? actual,
  SupplierNeedSearchPredicate predicate,
  SupplierNeedSearchField? field,
) {
  if (actual == null || predicate.values.isEmpty) {
    return _PredicateEvidence.unknown;
  }
  final actualValues = actual is Iterable && actual is! String
      ? actual.toList(growable: false)
      : <Object?>[actual];
  final kind = _identityKindByField[predicate.field];
  final canonicalActual = actualValues
      .map((value) => _canonicalValue(value, field, kind))
      .whereType<Object>()
      .toList(growable: false);
  final expected = predicate.values
      .map((value) => _canonicalValue(value, field, kind))
      .whereType<Object>()
      .toList(growable: false);
  if (canonicalActual.isEmpty || expected.isEmpty) {
    return _PredicateEvidence.unknown;
  }
  final equals = canonicalActual.any(
    (left) => expected.any((right) => _valuesEqual(left, right)),
  );

  switch (predicate.operator.trim().toLowerCase()) {
    case 'eq':
    case 'in':
      return equals ? _PredicateEvidence.proven : _PredicateEvidence.conflict;
    case 'neq':
    case 'not_in':
      return equals ? _PredicateEvidence.conflict : _PredicateEvidence.proven;
    case 'contains':
      final contains = canonicalActual.any((left) {
        final value = _normalize(left.toString());
        return expected.any(
          (right) => value.contains(_normalize(right.toString())),
        );
      });
      return contains ? _PredicateEvidence.proven : _PredicateEvidence.conflict;
    case 'lt':
    case 'lte':
    case 'gt':
    case 'gte':
      final boundary = _number(expected.first);
      final numbers = canonicalActual.map(_number).whereType<double>();
      if (boundary == null || numbers.isEmpty) {
        return _PredicateEvidence.unknown;
      }
      final met = numbers.any((value) => switch (predicate.operator) {
            'lt' => value < boundary,
            'lte' => value <= boundary,
            'gt' => value > boundary,
            _ => value >= boundary,
          });
      return met ? _PredicateEvidence.proven : _PredicateEvidence.conflict;
    case 'between':
      if (expected.length != 2) return _PredicateEvidence.unknown;
      final lower = _number(expected[0]);
      final upper = _number(expected[1]);
      final numbers = canonicalActual.map(_number).whereType<double>();
      if (lower == null || upper == null || numbers.isEmpty) {
        return _PredicateEvidence.unknown;
      }
      final min = lower <= upper ? lower : upper;
      final max = lower <= upper ? upper : lower;
      return numbers.any((value) => value >= min && value <= max)
          ? _PredicateEvidence.proven
          : _PredicateEvidence.conflict;
    default:
      return _PredicateEvidence.unknown;
  }
}

Object? _canonicalValue(
  Object? raw,
  SupplierNeedSearchField? field,
  PartSpecKind? kind,
) {
  if (raw == null) return null;
  if (kind != null) {
    final normalized = _canonicalIdentityValue(kind, raw.toString());
    final numeric = _number(normalized);
    return numeric ?? normalized;
  }
  final numeric = _number(raw);
  final dataType = field?.dataType.toLowerCase() ?? '';
  if (raw is num ||
      dataType == 'number' ||
      (numeric != null && _looksNumeric(raw.toString()))) {
    return numeric;
  }
  if (raw is bool) return raw;
  return _normalize(raw.toString());
}

String _canonicalIdentityValue(PartSpecKind kind, String raw) {
  final value = _normalize(raw);
  switch (kind) {
    case PartSpecKind.valveType:
      if (value.contains('presta') ||
          value.contains('franc') ||
          value == 'f v' ||
          value == 'fv') {
        return 'presta';
      }
      // **Dunlop es un tercer tipo, no otro nombre de la americana.** Sin él,
      // `CAMARA 700 X 28/38C V/DUNLOP` no contradecía «Schrader» y se contaba
      // como si cumpliera.
      if (value.contains('dunlop') || value.contains('woods')) return 'dunlop';
      // `auto` sólo como palabra entera: `AUTOSELLANTE` es un sellante y
      // `AUTOMATICA` un adjetivo. Con `contains` ambas se volvían americanas.
      if (value.contains('schrader') ||
          value.contains('americana') ||
          RegExp(r'\bauto\b').hasMatch(value) ||
          value == 'a v' ||
          value == 'av') {
        return 'schrader';
      }
      return value;
    case PartSpecKind.position:
      if (value.contains('delanter')) return 'front';
      if (value.contains('traser')) return 'rear';
      return value;
    case PartSpecKind.freehubStandard:
      if (value.contains('micro spline') || value == 'microspline') {
        return 'microspline';
      }
      if (value.contains('xdr')) return 'xdr';
      if (RegExp(r'\bxd\b').hasMatch(value)) return 'xd';
      if (value.contains('rueda libre') || value.contains('freewheel')) {
        return 'freewheel';
      }
      if (value.contains('shimano hg') || value == 'hg') return 'hg';
      return value;
    case PartSpecKind.brakeMount:
      if (value.contains('centerlock')) return 'centerlock';
      if (value.contains('6 perno') || value.contains('six bolt')) {
        return 'sixbolt';
      }
      return value;
    case PartSpecKind.shellStandard:
      if (value.contains('bsa') || value.contains('ingles')) return 'bsa';
      if (value.contains('bb30')) return 'bb30';
      if (value.contains('pressfit') || value.contains('bb86')) {
        return 'pressfit';
      }
      return value;
    default:
      return value.replaceAll(RegExp(r'[^0-9.,-]+$'), '').trim().isNotEmpty &&
              _number(value) != null
          ? _number(value)!.toString()
          : value;
  }
}

Object? _visibleAllowedValue(
  SupplierNeedPortalFamilyAdapter family,
  SupplierNeedSearchField field,
  String text,
) {
  final found = <Object>[];
  for (final allowed in field.allowedValues) {
    if (_number(allowed) != null) continue;
    final canonical = allowed.toString();
    final aliases = <String>{
      canonical,
      ...?family.valueAliases[field.key]?[canonical],
    };
    final visible = aliases.expand(_valueTerms).any(text.contains);
    if (visible) found.add(allowed);
  }
  return found.length == 1 ? found.single : null;
}

Iterable<String> _valueTerms(String raw) sync* {
  final normalized = _normalize(raw);
  if (normalized.length >= 2) yield normalized;
  for (final part in normalized.split(RegExp(r'[/()]'))) {
    final clean = part.trim();
    if (clean.length >= 2) yield clean;
  }
}

/// Las medidas que **nombran** el objeto: las que uno dice en voz alta al
/// pedirlo. `Aro 29`, `disco 180`. Un número pegado al sustantivo es una de
/// éstas y ninguna otra.
const Set<PartSpecKind> _objectNamingMeasures = <PartSpecKind>{
  PartSpecKind.wheelSize,
  PartSpecKind.rotorDiameterMm,
};

/// La medida que sigue al sustantivo que nombra el objeto.
///
/// **Dos condiciones, y las dos vienen del dominio, no de una heurística.**
///
/// 1. El número va **pegado al `head` de la familia** —`camara`, `llanta`,
///    `aro`—, admitiendo entre medio sólo palabras que no cambian de tema
///    (`aro`, `de`, `para`, un artículo). Con eso `LLANTA 26 VISION` y
///    `Cámaras 29 con válvula` declaran su aro, mientras `código 700`,
///    `presupuesto 700 pesos` —donde entre el sustantivo y el número hay otro
///    tema— y `llevar 32 cámaras` —donde el número va ANTES— no declaran nada.
/// 2. El número es **uno de los tamaños que la propia ficha ofrece**. No hay
///    lista escrita acá: `allowed_values` dice cuáles son. Por eso
///    `LLANTA 28 VISION` no declara medida —no existe un aro 28 en la ficha— y
///    `CAMARA CARRETILLA 350 X 8` tampoco entra por esta vía.
///
/// Dos medidas distintas junto a sendos `head` devuelven nada: ambiguo no es lo
/// mismo que desconocido.
Set<double> _familyAdjacentSizesFromText(
  String text,
  List<String> familyHeads,
  List<Object> allowedValues,
) {
  if (familyHeads.isEmpty || allowedValues.isEmpty) return const <double>{};
  final sizes = <double>{};
  for (final value in allowedValues) {
    final match = RegExp(r'^(\d{2,3}(?:[.,]\d)?)').firstMatch('$value'.trim());
    final size = _number(match?.group(1));
    if (size != null) sizes.add(size);
  }
  if (sizes.isEmpty) return const <double>{};

  // **Una fila que nombra dos medidas no afirma ninguna.** `CAMARA 700X28C Y
  // 26X1.75 SURTIDO` vende las dos; quedarse con la que va pegada al
  // sustantivo sería elegir por posición, no por evidencia. Es la misma
  // disciplina que ya tiene la lectura dimensional.

  const relleno = r'(?:aro|aros|rodado|rin|de|del|para|el|la|los|las)';
  final found = <double>{};
  for (final head in familyHeads) {
    final normalizedHead = _normalize(head);
    if (normalizedHead.isEmpty) continue;
    final expression = RegExp(
      '(?:^|[^a-z0-9])${RegExp.escape(normalizedHead)}'
      '(?:\\s+$relleno){0,2}'
      r'\s+(\d{2,3}(?:[.,]\d)?)(?:\s+(?:~\s+)?([a-z]+)|[^0-9.,]|$)',
    );
    for (final match in expression.allMatches(text)) {
      final size = _number(match.group(1));
      if (size == null || !sizes.contains(size)) continue;
      // **Lo que sigue al número también dice de qué está hablando.**
      // `Cámaras 29 unidades` y `Cámaras 700 pesos` tienen el número pegado al
      // objeto igual que `Cámaras 29`, y no son una medida: son cuánto y
      // cuánto vale.
      if (_countsOrPrices(match.group(2))) continue;
      found.add(size);
    }
  }
  return found;
}

/// Si ese número aparece en el texto contado o con precio.
///
/// Se mira el hecho, no quién lo leyó: da igual que la medida venga del
/// extractor de identidad, de la lectura dimensional o del sustantivo de la
/// familia — si el texto dice `29 unidades`, no es un aro.
bool _numberIsCountedOrPriced(String text, Object? value) {
  if (value == null) return false;
  final number = value is num ? value.toDouble() : _number('$value');
  if (number == null) return false;
  final escrito = number == number.roundToDouble()
      ? number.toStringAsFixed(0)
      : number.toString();
  // El normalizador canónico convierte la coma en `~`, así que `29, unidades`
  // llega como `29 ~ unidades`: sin saltar ese separador, una coma bastaba para
  // esconder la palabra que dice que el número es una cantidad.
  final expression = RegExp(
    '(?:^|[^0-9.,])${RegExp.escape(escrito)}\\s+(?:~\\s+)?([a-z]+)',
  );
  for (final match in expression.allMatches(text)) {
    if (_countsOrPrices(match.group(1))) return true;
  }
  return false;
}

/// Si la palabra que sigue al número lo convierte en cantidad o dinero.
bool _countsOrPrices(String? word) {
  final clean = (word ?? '').trim();
  if (clean.isEmpty) return false;
  const contadores = <String>{
    'unidad',
    'unidades',
    'und',
    'unds',
    'uds',
    'u',
    'piezas',
    'pieza',
    'juegos',
    'juego',
    'pares',
    'par',
    'cajas',
    'caja',
    'pesos',
    'peso',
    'clp',
    'usd',
    'dolares',
    'euros',
    'lucas',
  };
  return contadores.contains(clean);
}

double? _numberNearAliases(
  String text,
  Iterable<String> aliases,
  String? unit,
) {
  final unitText = _normalize(unit ?? '');
  final suffix = unitText.isEmpty ? '' : r'\s*' + RegExp.escape(unitText);
  final found = <double>{};
  for (final alias
      in aliases.map(_normalize).where((value) => value.isNotEmpty)) {
    final escaped = RegExp.escape(alias);
    final expressions = <RegExp>[
      RegExp('$escaped\\s*[:=-]?\\s*(\\d+(?:[.,]\\d+)?)$suffix'),
      RegExp('(\\d+(?:[.,]\\d+)?)$suffix\\s*[:=-]?\\s*$escaped'),
    ];
    for (final expression in expressions) {
      for (final match in expression.allMatches(text)) {
        final value = _number(match.group(1));
        if (value != null) found.add(value);
      }
    }
  }
  return found.length == 1 ? found.single : null;
}

double? _uniqueNumberWithUnit(String text, String unit) {
  final found = <double>{};
  final expression = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*' + RegExp.escape(unit) + r'\b',
  );
  for (final match in expression.allMatches(text)) {
    final value = _number(match.group(1));
    if (value != null) found.add(value);
  }
  return found.length == 1 ? found.single : null;
}

const Map<String, PartSpecKind> _identityKindByField = <String, PartSpecKind>{
  'spoke_holes': PartSpecKind.spokeCount,
  'rotor_diameter_mm': PartSpecKind.rotorDiameterMm,
  'clamp_diameter_mm': PartSpecKind.clampDiameterMm,
  'seatpost_diameter_mm': PartSpecKind.postDiameterMm,
  'crank_length_mm': PartSpecKind.crankLengthMm,
  'bcd_mm': PartSpecKind.boltCircleMm,
  'wheel_size': PartSpecKind.wheelSize,
  'hub_spacing_mm': PartSpecKind.axleWidthMm,
  'axle_width_mm': PartSpecKind.axleWidthMm,
  'axle_diameter_mm': PartSpecKind.axleDiameterMm,
  'freehub_type': PartSpecKind.freehubStandard,
  'valve_type': PartSpecKind.valveType,
  'valve_length_mm': PartSpecKind.lengthMm,
  'wheel_position': PartSpecKind.position,
  'brake_position': PartSpecKind.position,
  'chain_speeds': PartSpecKind.speeds,
  'drivetrain_speeds': PartSpecKind.speeds,
  'bb_shell_standard': PartSpecKind.shellStandard,
  'rotor_mount_type': PartSpecKind.brakeMount,
  'pack_count': PartSpecKind.packCount,
  'material': PartSpecKind.constructionMaterial,
};

bool _sameOriginUrl(String candidate, String reference) {
  final left = Uri.tryParse(candidate.trim());
  final right = Uri.tryParse(reference.trim());
  if (left == null ||
      right == null ||
      left.host.isEmpty ||
      right.host.isEmpty) {
    return false;
  }
  int port(Uri value) => value.hasPort
      ? value.port
      : value.scheme.toLowerCase() == 'https'
          ? 443
          : 80;
  return const <String>{'http', 'https'}.contains(left.scheme.toLowerCase()) &&
      left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      port(left) == port(right) &&
      left.userInfo.isEmpty;
}

bool _valuesEqual(Object? left, Object? right) {
  final leftNumber = _number(left);
  final rightNumber = _number(right);
  if (leftNumber != null && rightNumber != null) {
    return (leftNumber - rightNumber).abs() < 0.000001;
  }
  return _normalize(left?.toString() ?? '') ==
      _normalize(right?.toString() ?? '');
}

bool _looksNumeric(String value) =>
    RegExp(r'^\s*-?\d+(?:[.,]\d+)?\s*["a-zA-Z]*\s*$').hasMatch(value);

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value == null) return null;
  final match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(value.toString());
  return match == null
      ? null
      : double.tryParse(match.group(0)!.replaceAll(',', '.'));
}

String _bounded(String value, int maxLength) {
  final clean = value.trim();
  if (clean.length <= maxLength) return clean;
  return clean.substring(0, maxLength).trimRight();
}

Map<String, dynamic> _jsonMap(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

Map<String, List<String>> _stringListMap(Object? raw) {
  final result = <String, List<String>>{};
  for (final entry in _jsonMap(raw).entries) {
    final values = _strings(entry.value);
    if (entry.key.trim().isNotEmpty && values.isNotEmpty) {
      result[entry.key.trim()] = values;
    }
  }
  return Map.unmodifiable(result);
}

List<String> _strings(Object? raw) => raw is List
    ? List<String>.unmodifiable(
        raw
            .map((value) => value?.toString().trim())
            .whereType<String>()
            .where((value) => value.isNotEmpty),
      )
    : const <String>[];

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _normalize(String value) => ProductIdentityExtractor.normalize(value)
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// ---------------------------------------------------------------------------
// Descubrimiento del catálogo y cobertura
//
// El buscador de un proveedor es un ÍNDICE, no una autoridad: sirve para
// encontrar dónde vive una familia, nunca para acotar cuánto existe. Lo que
// sigue enumera el nodo de taxonomía completo y, sobre todo, informa cuánto
// alcanzó a mirar. Sin ese segundo dato, «10 filas de la página 1» se lee
// idéntico a «el proveedor tiene 10».
// ---------------------------------------------------------------------------

/// Tope de filas que hoy acepta el recibo (`record_supplier_need_portal_search_v1`).
/// Vive acá y en el adaptador para que cliente y RPC se muevan juntos.
const int kSupplierNeedPortalDefaultResultCap = 40;

class SupplierNeedPortalBudget {
  const SupplierNeedPortalBudget({
    this.maxNodes = 3,
    this.maxPages = 15,
    this.maxRows = 240,
    this.wallClock = const Duration(seconds: 90),
  });

  /// Cuántos nodos hermanos plausibles se enumeran. Recorrer el catálogo
  /// entero de un proveedor no es una respuesta: es un abuso del portal.
  final int maxNodes;

  /// Páginas totales de la corrida, no por nodo.
  final int maxPages;
  final int maxRows;
  final Duration wallClock;

  factory SupplierNeedPortalBudget.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    const defaults = SupplierNeedPortalBudget();
    int read(String key, int fallback, int max) {
      final value = (json[key] as num?)?.round();
      if (value == null || value < 1 || value > max) return fallback;
      return value;
    }

    return SupplierNeedPortalBudget(
      maxNodes: read('max_nodes', defaults.maxNodes, 10),
      maxPages: read('max_pages', defaults.maxPages, 60),
      maxRows: read('max_rows', defaults.maxRows, 1000),
      wallClock: Duration(
        seconds: read(
          'wall_clock_seconds',
          defaults.wallClock.inSeconds,
          600,
        ),
      ),
    );
  }
}

/// Cómo pedir «el nodo N de la taxonomía, página P».
class SupplierNeedPortalCatalogRoute {
  const SupplierNeedPortalCatalogRoute({
    required this.urlTemplate,
    required this.pageSize,
    this.firstPage = 1,
    this.maxPagesPerNode = 12,
  });

  final String urlTemplate;

  /// El tamaño REAL que sirve el portal, no el que uno pediría. RBX ignora
  /// `tamanopagina=27` y sigue devolviendo 9: declarar 27 acá haría que la
  /// primera página de 9 se leyera como «página corta» y cerrara el nodo con
  /// un tercio del catálogo.
  final int pageSize;
  final int firstPage;
  final int maxPagesPerNode;

  factory SupplierNeedPortalCatalogRoute.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final template = _text(json['url_template']) ?? '';
    if (!template.contains('{node}') ||
        !template.contains('{page}') ||
        !(template.startsWith('http://') || template.startsWith('https://'))) {
      throw const FormatException('Invalid supplier catalog route');
    }
    final pageSize = (json['page_size'] as num?)?.round() ?? 0;
    if (pageSize < 1 || pageSize > 200) {
      throw const FormatException('Invalid supplier catalog page size');
    }
    final firstPage = (json['first_page'] as num?)?.round() ?? 1;
    final maxPagesPerNode = (json['max_pages_per_node'] as num?)?.round() ?? 12;
    if (firstPage < 0 || maxPagesPerNode < 1 || maxPagesPerNode > 60) {
      throw const FormatException('Invalid supplier catalog pagination');
    }
    return SupplierNeedPortalCatalogRoute(
      urlTemplate: template,
      pageSize: pageSize,
      firstPage: firstPage,
      maxPagesPerNode: maxPagesPerNode,
    );
  }

  String urlFor({
    required SupplierPortalTaxonomyNode node,
    required int page,
  }) =>
      urlTemplate
          .replaceAll('{node}', Uri.encodeQueryComponent(node.id))
          .replaceAll(
            '{parent_node}',
            Uri.encodeQueryComponent(node.parentId ?? ''),
          )
          .replaceAll('{page}', page.toString())
          .replaceAll('{page_size}', pageSize.toString());
}

/// Dónde publica el portal sus propios selectores de clasificación.
class SupplierNeedPortalTaxonomyDiscovery {
  const SupplierNeedPortalTaxonomyDiscovery({
    required this.url,
    required this.parentField,
    required this.childField,
    this.maxParentProbes = 3,
    this.ttl = const Duration(hours: 24),
  });

  final String url;
  final String parentField;
  final String childField;

  /// Cuántos padres se abren para poblar sus hijos cuando el documento
  /// inicial no los trae. Se abren SÓLO los que ya calzan con la familia
  /// pedida: abrir los veinte es un barrido, no un descubrimiento.
  final int maxParentProbes;
  final Duration ttl;

  factory SupplierNeedPortalTaxonomyDiscovery.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final url = _text(json['url']) ?? '';
    final parentField = _text(json['parent_field']) ?? '';
    final childField = _text(json['child_field']) ?? '';
    if (!(url.startsWith('http://') || url.startsWith('https://')) ||
        parentField.isEmpty ||
        childField.isEmpty) {
      throw const FormatException('Invalid supplier taxonomy discovery');
    }
    final probes = (json['max_parent_probes'] as num?)?.round() ?? 3;
    final ttlHours = (json['ttl_hours'] as num?)?.round() ?? 24;
    return SupplierNeedPortalTaxonomyDiscovery(
      url: url,
      parentField: parentField,
      childField: childField,
      maxParentProbes: probes < 0 || probes > 25 ? 3 : probes,
      ttl: Duration(hours: ttlHours < 1 || ttlHours > 720 ? 24 : ttlHours),
    );
  }
}

/// Un nodo navegable de la taxonomía del proveedor.
class SupplierPortalTaxonomyNode {
  const SupplierPortalTaxonomyNode({
    required this.id,
    required this.label,
    this.parentId,
    this.parentLabel,
  });

  final String id;
  final String label;
  final String? parentId;
  final String? parentLabel;

  String get key => '${parentId ?? ''}/$id';

  factory SupplierPortalTaxonomyNode.fromJson(Map<String, dynamic> json) =>
      SupplierPortalTaxonomyNode(
        id: json['id']?.toString().trim() ?? '',
        label: json['label']?.toString().trim() ?? '',
        parentId: _text(json['parentId']),
        parentLabel: _text(json['parentLabel']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        if (parentId != null) 'parentId': parentId,
        if (parentLabel != null) 'parentLabel': parentLabel,
      };

  @override
  bool operator ==(Object other) =>
      other is SupplierPortalTaxonomyNode && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// La taxonomía descubierta, con su huella para detectar deriva.
class SupplierPortalCatalogTaxonomy {
  const SupplierPortalCatalogTaxonomy({
    required this.nodes,
    required this.fingerprint,
    this.discoveredAt,
  });

  final List<SupplierPortalTaxonomyNode> nodes;
  final String fingerprint;
  final DateTime? discoveredAt;

  bool get isEmpty => nodes.isEmpty;

  /// La misma taxonomía, fechada por el servidor.
  ///
  /// **El TTL no puede depender de una fecha que escribió quien llama.** El
  /// `discoveredAt` que viaja dentro del jsonb es dato de la fila; la columna
  /// `catalog_taxonomy_discovered_at` la estampa el recibo. Si se creyera la
  /// del payload, una fecha futura dejaría el caché fresco para siempre y el
  /// portal no se volvería a leer nunca.
  /// Reemplaza SIEMPRE, incluso con `null`: sin fecha del servidor la
  /// taxonomía se trata como vencida y se vuelve a descubrir. Conservar la del
  /// payload «porque es lo único que hay» es justo el agujero.
  SupplierPortalCatalogTaxonomy withServerDiscoveredAt(DateTime? at) =>
      SupplierPortalCatalogTaxonomy(
        nodes: nodes,
        fingerprint: fingerprint,
        discoveredAt: at,
      );

  bool isFresh(Duration ttl, {DateTime? now}) {
    final at = discoveredAt;
    if (at == null || nodes.isEmpty) return false;
    return (now ?? DateTime.now().toUtc()).difference(at) < ttl;
  }

  /// Une lo descubierto con lo que ya estaba, sin perder nodos de otro padre.
  SupplierPortalCatalogTaxonomy mergedWith(
    SupplierPortalCatalogTaxonomy other, {
    DateTime? at,
  }) {
    final merged = <String, SupplierPortalTaxonomyNode>{
      for (final node in nodes) node.key: node,
      for (final node in other.nodes) node.key: node,
    };
    final ordered = merged.values.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return SupplierPortalCatalogTaxonomy(
      nodes: List.unmodifiable(ordered),
      fingerprint: fingerprintOf(ordered),
      discoveredAt: at ?? other.discoveredAt ?? discoveredAt,
    );
  }

  /// Huella estable y determinista (FNV-1a). `String.hashCode` no sirve: no
  /// está garantizado entre corridas ni entre plataformas, y una huella que
  /// cambia sola reportaría deriva del portal todos los días.
  static String fingerprintOf(Iterable<SupplierPortalTaxonomyNode> nodes) {
    final material = (nodes.map((node) => '${node.key}|${node.label}').toList()
          ..sort())
        .join('\n');
    var hash = 0x811c9dc5;
    for (final unit in material.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  factory SupplierPortalCatalogTaxonomy.fromNodes(
    Iterable<SupplierPortalTaxonomyNode> nodes, {
    DateTime? discoveredAt,
  }) {
    final unique = <String, SupplierPortalTaxonomyNode>{
      for (final node in nodes)
        if (node.id.isNotEmpty && node.label.isNotEmpty) node.key: node,
    };
    final ordered = unique.values.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return SupplierPortalCatalogTaxonomy(
      nodes: List.unmodifiable(ordered),
      fingerprint: fingerprintOf(ordered),
      discoveredAt: discoveredAt,
    );
  }

  factory SupplierPortalCatalogTaxonomy.fromJson(Object? raw) {
    final json = _jsonMap(raw);
    final rawNodes = json['nodes'];
    final nodes = rawNodes is List
        ? rawNodes
            .whereType<Map>()
            .map((entry) => SupplierPortalTaxonomyNode.fromJson(
                  Map<String, dynamic>.from(entry),
                ))
            .where((node) => node.id.isNotEmpty && node.label.isNotEmpty)
            .toList(growable: false)
        : const <SupplierPortalTaxonomyNode>[];
    return SupplierPortalCatalogTaxonomy(
      nodes: List.unmodifiable(nodes),
      fingerprint: _text(json['fingerprint']) ?? fingerprintOf(nodes),
      discoveredAt: DateTime.tryParse('${json['discoveredAt'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
        'fingerprint': fingerprint,
        if (discoveredAt != null)
          'discoveredAt': discoveredAt!.toUtc().toIso8601String(),
      };
}

bool _containsWord(String haystack, String needle) {
  if (needle.isEmpty || haystack.isEmpty) return false;
  return RegExp('(^|[^a-z0-9])${RegExp.escape(needle)}([^a-z0-9]|\$)')
      .hasMatch(haystack);
}

/// Qué nodos del catálogo del proveedor pueden contener esta familia.
///
/// Devuelve varios a propósito. Elegir uno por corazonada es cómo desaparece
/// una opción real; enumerar los hermanos plausibles y dejar que el calce
/// determinista elimine es el contrato eliminate-then-rank aplicado al
/// descubrimiento.
List<SupplierPortalTaxonomyNode> rankSupplierTaxonomyNodes({
  required SupplierPortalCatalogTaxonomy? taxonomy,
  required List<String> familyTerms,
  required List<String> excludedTerms,
  required int limit,
}) {
  if (taxonomy == null || taxonomy.isEmpty || limit < 1) {
    return const <SupplierPortalTaxonomyNode>[];
  }
  final terms = familyTerms.where((term) => term.isNotEmpty).toList();
  if (terms.isEmpty) return const <SupplierPortalTaxonomyNode>[];
  final scored = <({int score, SupplierPortalTaxonomyNode node})>[];
  for (final node in taxonomy.nodes) {
    final label = _normalize(node.label);
    if (label.isEmpty) continue;
    if (excludedTerms.any((term) => _containsWord(label, term))) continue;
    final parent = _normalize(node.parentLabel ?? '');
    var labelScore = 0;
    var parentBonus = 0;
    for (final term in terms) {
      if (_containsWord(label, term)) {
        labelScore += 3;
      } else if (label.contains(term)) {
        labelScore += 1;
      }
      if (_containsWord(parent, term)) parentBonus += 1;
    }
    // **El padre desempata, nunca califica.** `NEUMATICOS RUTA` cuelga de
    // `NEUMATICOS Y CAMARAS`: si el rótulo del padre bastara para entrar, se
    // enumeraría el nodo de neumáticos para pedir cámaras.
    if (labelScore <= 0) continue;
    scored.add((score: labelScore + parentBonus, node: node));
  }
  scored.sort((left, right) {
    final byScore = right.score.compareTo(left.score);
    if (byScore != 0) return byScore;
    // Un rótulo más corto es el nodo más directo de la familia; el resto del
    // orden es alfabético para que dos corridas iguales elijan igual.
    final byLength = left.node.label.length.compareTo(right.node.label.length);
    if (byLength != 0) return byLength;
    return left.node.label.compareTo(right.node.label);
  });
  return scored.take(limit).map((entry) => entry.node).toList(growable: false);
}

/// Cuántos nodos calzan con la familia, antes de aplicar el presupuesto.
int countSupplierTaxonomyCandidates({
  required SupplierPortalCatalogTaxonomy? taxonomy,
  required List<String> familyTerms,
  required List<String> excludedTerms,
}) =>
    rankSupplierTaxonomyNodes(
      taxonomy: taxonomy,
      familyTerms: familyTerms,
      excludedTerms: excludedTerms,
      limit: 1 << 20,
    ).length;

enum SupplierNeedCoverageMethod { taxonomy, wordSearch, none }

extension SupplierNeedCoverageMethodWire on SupplierNeedCoverageMethod {
  String get wireName => switch (this) {
        SupplierNeedCoverageMethod.taxonomy => 'taxonomy',
        SupplierNeedCoverageMethod.wordSearch => 'word_search',
        SupplierNeedCoverageMethod.none => 'none',
      };
}

/// Por qué se detuvo la enumeración.
///
/// La distinción no es cosmética: un tope NUESTRO deja filas que sí se vieron
/// y se pueden usar con reserva; una invariante rota (sesión, parser, encoding,
/// transporte) deja un conjunto cuyas AUSENCIAS no significan nada, y esas
/// filas sólo sirven como evidencia.
enum SupplierNeedCoverageLimit {
  enumerated,
  maxNodes,
  maxPages,
  maxRows,
  wallClock,
  storageCap,
  loopDetected,
  sessionExpired,
  parserDrift,
  encoding,
  transport,
  wordSearchOnly,
  notAttempted,
}

extension SupplierNeedCoverageLimitFacts on SupplierNeedCoverageLimit {
  String get wireName => switch (this) {
        SupplierNeedCoverageLimit.enumerated => 'enumerated',
        SupplierNeedCoverageLimit.maxNodes => 'max_nodes',
        SupplierNeedCoverageLimit.maxPages => 'max_pages',
        SupplierNeedCoverageLimit.maxRows => 'max_rows',
        SupplierNeedCoverageLimit.wallClock => 'wall_clock',
        SupplierNeedCoverageLimit.storageCap => 'storage_cap',
        SupplierNeedCoverageLimit.loopDetected => 'loop_detected',
        SupplierNeedCoverageLimit.sessionExpired => 'session_expired',
        SupplierNeedCoverageLimit.parserDrift => 'parser_drift',
        SupplierNeedCoverageLimit.encoding => 'encoding',
        SupplierNeedCoverageLimit.transport => 'transport',
        SupplierNeedCoverageLimit.wordSearchOnly => 'word_search_only',
        SupplierNeedCoverageLimit.notAttempted => 'not_attempted',
      };

  /// Un tope que nos pusimos nosotros. Las filas vistas son reales.
  bool get isSelfImposed => switch (this) {
        SupplierNeedCoverageLimit.maxNodes ||
        SupplierNeedCoverageLimit.maxPages ||
        SupplierNeedCoverageLimit.maxRows ||
        SupplierNeedCoverageLimit.wallClock ||
        SupplierNeedCoverageLimit.storageCap ||
        SupplierNeedCoverageLimit.loopDetected ||
        SupplierNeedCoverageLimit.wordSearchOnly =>
          true,
        _ => false,
      };

  /// Se rompió una invariante: no se puede distinguir «el portal mostró
  /// menos» de «dejamos de ver».
  bool get isBrokenInvariant => switch (this) {
        SupplierNeedCoverageLimit.sessionExpired ||
        SupplierNeedCoverageLimit.parserDrift ||
        SupplierNeedCoverageLimit.encoding ||
        SupplierNeedCoverageLimit.transport =>
          true,
        _ => false,
      };
}

SupplierNeedCoverageLimit _limitFromWire(String? raw) {
  for (final value in SupplierNeedCoverageLimit.values) {
    if (value.wireName == raw) return value;
  }
  return SupplierNeedCoverageLimit.notAttempted;
}

class SupplierNeedPortalCoverage {
  const SupplierNeedPortalCoverage({
    required this.method,
    required this.isComplete,
    required this.limit,
    this.nodeLabels = const <String>[],
    this.nodeIds = const <String>[],
    this.nodesAvailable = 0,
    this.nodesPlanned = 0,
    this.nodesCompleted = 0,
    this.pagesFetched = 0,
    this.rowsObserved = 0,
    this.rowsUnique = 0,
    this.rowsPersisted = 0,
    this.checkedAt,
  });

  const SupplierNeedPortalCoverage.unknown()
      : this(
          method: SupplierNeedCoverageMethod.none,
          isComplete: false,
          limit: SupplierNeedCoverageLimit.notAttempted,
        );

  final SupplierNeedCoverageMethod method;
  final bool isComplete;
  final SupplierNeedCoverageLimit limit;
  final List<String> nodeLabels;
  final List<String> nodeIds;
  final int nodesAvailable;
  final int nodesPlanned;
  final int nodesCompleted;
  final int pagesFetched;
  final int rowsObserved;
  final int rowsUnique;
  final int rowsPersisted;
  final DateTime? checkedAt;

  /// Si las filas pueden ofrecerse como opciones o sólo guardarse.
  bool get isActionable =>
      limit == SupplierNeedCoverageLimit.enumerated || limit.isSelfImposed;

  bool get truncatedForStorage =>
      rowsPersisted > 0 && rowsPersisted < rowsUnique;

  String get scopeLabel {
    if (nodeLabels.isEmpty) return 'el catálogo';
    if (nodeLabels.length == 1) return '«${nodeLabels.single}»';
    return '${nodeLabels.length} categorías del catálogo';
  }

  String get statusLabel =>
      isComplete ? 'Cobertura completa' : 'Revisión parcial';

  /// Una frase que dice qué se miró y qué faltó. Nunca un número solo: un
  /// número sin referente no informa.
  String get sentence {
    if (method == SupplierNeedCoverageMethod.none) {
      return 'Sin datos de cobertura.';
    }
    if (method == SupplierNeedCoverageMethod.wordSearch) {
      return 'Revisión parcial: se usó el buscador del proveedor, que no '
          'recorre el catálogo completo.';
    }
    final reviewed = '$rowsUnique '
        '${rowsUnique == 1 ? 'producto revisado' : 'productos revisados'} '
        'en $scopeLabel';
    if (isComplete) return 'Cobertura completa: $reviewed.';
    final because = switch (limit) {
      SupplierNeedCoverageLimit.maxNodes =>
        'quedaron ${nodesAvailable - nodesPlanned} '
            '${nodesAvailable - nodesPlanned == 1 ? 'categoría' : 'categorías'} '
            'sin revisar',
      SupplierNeedCoverageLimit.maxPages ||
      SupplierNeedCoverageLimit.maxRows ||
      SupplierNeedCoverageLimit.wallClock =>
        'se alcanzó el límite de la revisión',
      SupplierNeedCoverageLimit.storageCap =>
        'se guardaron $rowsPersisted de $rowsUnique',
      SupplierNeedCoverageLimit.loopDetected =>
        'el portal repitió la misma página',
      SupplierNeedCoverageLimit.sessionExpired => 'venció la sesión',
      SupplierNeedCoverageLimit.parserDrift => 'el catálogo cambió de formato',
      SupplierNeedCoverageLimit.encoding =>
        'el portal respondió con texto ilegible',
      SupplierNeedCoverageLimit.transport => 'el portal dejó de responder',
      _ => 'la revisión no terminó',
    };
    return 'Revisión parcial: $reviewed y $because.';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': method.wireName,
        'complete': isComplete,
        'limit': limit.wireName,
        'actionable': isActionable,
        'nodeIds': nodeIds,
        'nodeLabels': nodeLabels,
        'nodesAvailable': nodesAvailable,
        'nodesPlanned': nodesPlanned,
        'nodesCompleted': nodesCompleted,
        'pagesFetched': pagesFetched,
        'rowsObserved': rowsObserved,
        'rowsUnique': rowsUnique,
        'rowsPersisted': rowsPersisted,
        if (checkedAt != null)
          'checkedAt': checkedAt!.toUtc().toIso8601String(),
      };

  factory SupplierNeedPortalCoverage.fromJson(Object? raw) {
    if (raw is! Map) return const SupplierNeedPortalCoverage.unknown();
    final json = Map<String, dynamic>.from(raw);
    int number(String key) => (json[key] as num?)?.round() ?? 0;
    return SupplierNeedPortalCoverage(
      method: switch (json['method']?.toString()) {
        'taxonomy' => SupplierNeedCoverageMethod.taxonomy,
        'word_search' => SupplierNeedCoverageMethod.wordSearch,
        _ => SupplierNeedCoverageMethod.none,
      },
      isComplete: json['complete'] == true,
      limit: _limitFromWire(json['limit']?.toString()),
      nodeIds: _strings(json['nodeIds']),
      nodeLabels: _strings(json['nodeLabels']),
      nodesAvailable: number('nodesAvailable'),
      nodesPlanned: number('nodesPlanned'),
      nodesCompleted: number('nodesCompleted'),
      pagesFetched: number('pagesFetched'),
      rowsObserved: number('rowsObserved'),
      rowsUnique: number('rowsUnique'),
      rowsPersisted: number('rowsPersisted'),
      checkedAt: DateTime.tryParse('${json['checkedAt'] ?? ''}'),
    );
  }
}

class SupplierPortalCandidateSet {
  const SupplierPortalCandidateSet({
    required this.unique,
    required this.duplicates,
  });

  final List<SupplierPortalCatalogCandidate> unique;
  final int duplicates;
}

String supplierPortalCandidateKey(SupplierPortalCatalogCandidate candidate) {
  final code = _normalize(candidate.code).replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (code.isNotEmpty) return code;
  return _normalize('${candidate.code} ${candidate.name}');
}

/// El mismo producto aparece en dos nodos hermanos y en dos páginas. Se
/// deduplica por código, que es lo único que el proveedor promete único.
SupplierPortalCandidateSet dedupeSupplierPortalCandidates(
  Iterable<SupplierPortalCatalogCandidate> candidates,
) {
  final byKey = <String, SupplierPortalCatalogCandidate>{};
  var duplicates = 0;
  for (final candidate in candidates) {
    if (candidate.code.trim().isEmpty || candidate.name.trim().isEmpty) {
      continue;
    }
    final key = supplierPortalCandidateKey(candidate);
    if (byKey.containsKey(key)) {
      duplicates++;
      continue;
    }
    byKey[key] = candidate;
  }
  return SupplierPortalCandidateSet(
    unique: List.unmodifiable(byKey.values),
    duplicates: duplicates,
  );
}

/// Una página que el enumerador quiere que alguien vaya a buscar.
class SupplierNeedCatalogRequest {
  const SupplierNeedCatalogRequest({
    required this.node,
    required this.page,
    required this.url,
  });

  final SupplierPortalTaxonomyNode node;
  final int page;
  final String url;
}

/// Lo que el portal contestó para esa página, ya leído por la sonda.
class SupplierNeedCatalogPageResult {
  const SupplierNeedCatalogPageResult({
    required this.candidates,
    this.schemaMatched = true,
    this.tablesSeen = 0,
    this.misdecoded = false,
    this.sessionExpired = false,
    this.transportFailed = false,
  });

  const SupplierNeedCatalogPageResult.sessionExpired()
      : this(
          candidates: const <SupplierPortalCatalogCandidate>[],
          sessionExpired: true,
        );

  const SupplierNeedCatalogPageResult.transportFailed()
      : this(
          candidates: const <SupplierPortalCatalogCandidate>[],
          transportFailed: true,
        );

  final List<SupplierPortalCatalogCandidate> candidates;
  final bool schemaMatched;
  final int tablesSeen;
  final bool misdecoded;
  final bool sessionExpired;
  final bool transportFailed;
}

/// Enumera un conjunto acotado de nodos, página por página, y sabe cuándo
/// parar y por qué.
///
/// Vive fuera del navegador a propósito: la regla de terminación es lógica de
/// negocio —confundir «página vacía» con «encabezado renombrado» es cómo se
/// cierra un catálogo a un tercio— y se prueba sin una pantalla.
class SupplierNeedCatalogEnumerator {
  SupplierNeedCatalogEnumerator({
    required this.route,
    required this.budget,
    required this.nodes,
    required this.nodesAvailable,
    DateTime Function()? clock,
  })  : _clock = clock ?? (() => DateTime.now().toUtc()),
        _page = route.firstPage {
    _startedAt = _clock();
  }

  final SupplierNeedPortalCatalogRoute route;
  final SupplierNeedPortalBudget budget;
  final List<SupplierPortalTaxonomyNode> nodes;

  /// Cuántos nodos calzaban con la familia antes de aplicar `maxNodes`.
  final int nodesAvailable;

  final DateTime Function() _clock;
  late final DateTime _startedAt;

  final Map<String, SupplierPortalCatalogCandidate> _byKey =
      <String, SupplierPortalCatalogCandidate>{};
  final Set<String> _visited = <String>{};

  int _nodeIndex = 0;
  int _page;
  int _pagesFetched = 0;
  int _rowsObserved = 0;
  int _duplicates = 0;
  int _nodesCompleted = 0;
  int _pagesInNode = 0;
  bool _loopSeen = false;
  bool _nodeCapSeen = false;
  SupplierNeedCoverageLimit? _broken;
  SupplierNeedCoverageLimit? _budgetStop;
  SupplierNeedCatalogRequest? _pending;

  List<SupplierPortalCatalogCandidate> get candidates =>
      List.unmodifiable(_byKey.values);

  int get duplicates => _duplicates;

  SupplierNeedCatalogRequest? next() {
    if (_broken != null || _budgetStop != null) return null;
    if (nodes.isEmpty || _nodeIndex >= nodes.length) return null;
    if (_clock().difference(_startedAt) >= budget.wallClock) {
      _budgetStop = SupplierNeedCoverageLimit.wallClock;
      return null;
    }
    if (_pagesFetched >= budget.maxPages) {
      _budgetStop = SupplierNeedCoverageLimit.maxPages;
      return null;
    }
    if (_rowsObserved >= budget.maxRows) {
      _budgetStop = SupplierNeedCoverageLimit.maxRows;
      return null;
    }
    final node = nodes[_nodeIndex];
    final url = route.urlFor(node: node, page: _page);
    // Un portal legacy puede devolver la misma página con otro número. Pedir
    // dos veces la misma URL es la señal más barata de un ciclo.
    if (!_visited.add('${node.key}#$_page')) {
      _loopSeen = true;
      _advanceNode(completed: false);
      return next();
    }
    final request = SupplierNeedCatalogRequest(
      node: node,
      page: _page,
      url: url,
    );
    _pending = request;
    return request;
  }

  void offer(SupplierNeedCatalogPageResult result) {
    if (_pending == null) {
      throw StateError('Supplier catalog page offered without a request');
    }
    _pending = null;
    _pagesFetched++;
    _pagesInNode++;

    if (result.sessionExpired) {
      _broken = SupplierNeedCoverageLimit.sessionExpired;
      return;
    }
    if (result.transportFailed) {
      _broken = SupplierNeedCoverageLimit.transport;
      return;
    }
    if (result.misdecoded) {
      _broken = SupplierNeedCoverageLimit.encoding;
      return;
    }
    // **Una tabla que existe y no calzó no es una página vacía.** Sin esta
    // rama, un encabezado renombrado cierra el nodo declarando cobertura
    // completa sobre cero filas.
    if (result.tablesSeen > 0 && !result.schemaMatched) {
      _broken = SupplierNeedCoverageLimit.parserDrift;
      return;
    }

    _rowsObserved += result.candidates.length;
    var fresh = 0;
    for (final candidate in result.candidates) {
      if (candidate.code.trim().isEmpty || candidate.name.trim().isEmpty) {
        continue;
      }
      final key = supplierPortalCandidateKey(candidate);
      if (_byKey.containsKey(key)) {
        _duplicates++;
        continue;
      }
      _byKey[key] = candidate;
      fresh++;
    }

    if (result.candidates.isEmpty) {
      // Página vacía: el nodo se acabó. El enlace «Siguiente» sigue dibujado
      // en RBX incluso acá, así que no se le cree.
      _advanceNode(completed: true);
      return;
    }
    if (fresh == 0) {
      _loopSeen = true;
      _advanceNode(completed: false);
      return;
    }
    if (result.candidates.length < route.pageSize) {
      _advanceNode(completed: true);
      return;
    }
    if (_pagesInNode >= route.maxPagesPerNode) {
      _nodeCapSeen = true;
      _advanceNode(completed: false);
      return;
    }
    _page++;
  }

  void _advanceNode({required bool completed}) {
    if (completed) _nodesCompleted++;
    _nodeIndex++;
    _page = route.firstPage;
    _pagesInNode = 0;
  }

  SupplierNeedCoverageLimit get _limit {
    final broken = _broken;
    if (broken != null) return broken;
    final budgetStop = _budgetStop;
    if (budgetStop != null) return budgetStop;
    if (nodes.isEmpty) return SupplierNeedCoverageLimit.notAttempted;
    if (_nodeIndex < nodes.length) {
      return SupplierNeedCoverageLimit.notAttempted;
    }
    if (_loopSeen) return SupplierNeedCoverageLimit.loopDetected;
    if (_nodeCapSeen) return SupplierNeedCoverageLimit.maxPages;
    if (nodesAvailable > nodes.length) {
      return SupplierNeedCoverageLimit.maxNodes;
    }
    return SupplierNeedCoverageLimit.enumerated;
  }

  SupplierNeedPortalCoverage coverage({int? rowsPersisted}) {
    var limit = _limit;
    final unique = _byKey.length;
    final persisted = rowsPersisted ?? unique;
    if (limit == SupplierNeedCoverageLimit.enumerated && persisted < unique) {
      limit = SupplierNeedCoverageLimit.storageCap;
    }
    return SupplierNeedPortalCoverage(
      method: SupplierNeedCoverageMethod.taxonomy,
      isComplete: limit == SupplierNeedCoverageLimit.enumerated,
      limit: limit,
      nodeIds: nodes.map((node) => node.id).toList(growable: false),
      nodeLabels: nodes.map((node) => node.label).toList(growable: false),
      nodesAvailable: nodesAvailable,
      nodesPlanned: nodes.length,
      nodesCompleted: _nodesCompleted,
      pagesFetched: _pagesFetched,
      rowsObserved: _rowsObserved,
      rowsUnique: unique,
      rowsPersisted: persisted,
      checkedAt: _clock(),
    );
  }
}

/// El mismo hecho que reporta la sonda, disponible tambien en Dart.
///
/// Un IIS que sirve `text/html` sin `charset` deja que el navegador
/// adivine. Cuando adivina UTF-8 sobre bytes Windows-1252, «Código» llega
/// como «CÃ³digo» y ningún alias de columna calza: la página se lee
/// idéntica a un nodo agotado, y la enumeración cerraría jurando cobertura
/// completa sobre cero filas. Se comprueba en las dos capas porque el costo
/// de no verlo es una afirmación falsa, no una fila perdida.
final RegExp _misdecodedText = RegExp('[\u00c3\u00c2][\u0080-\u00bf]|\ufffd');

bool supplierPortalTextLooksMisdecoded(String body) =>
    body.isNotEmpty && _misdecodedText.hasMatch(body);

/// Cuántas de las filas YA leídas cumplirían con otra ficha.
///
/// Es el cálculo que permite decirle al operador «de 19 revisadas, 6 cumplen»
/// **antes** de guardar, y sin volver a consultar al proveedor: las filas
/// están en memoria y sus hechos observados ya fueron extraídos de lo que el
/// portal mostró. Cambiar la ficha cambia el veredicto, no la observación.
///
/// Reutiliza el mismo evaluador que el calce real; escribir una segunda
/// versión de «este predicado se contradice» sería tener dos dueños de la
/// regla y verlos divergir.
///
/// Sólo se descartan las filas **contradichas**. Una medida que el portal no
/// publicó sigue siendo una opción por revisar, igual que en el calce: una
/// omisión no es un rechazo.
/// Cuántas filas quedan bajo unos criterios, **separando lo demostrado de lo
/// que nadie ha verificado**.
///
/// Un solo número mezclaba las dos cosas y mentía. Medido sobre la corrida real
/// de RBX del 2026-08-29 —35 filas, `camara`— pedir válvula Schrader dejaba «8
/// cumplen», pero sólo 3 filas traían `valve_type: schrader` observado
/// (`10663`, `14473`, `18335`); las otras 5 sobrevivían por **no tener el dato**
/// —una ausencia no contradice—, y ese silencio se imprimía como si el
/// proveedor lo hubiera confirmado. Con Presta pasaba lo mismo: 15 = 10
/// probadas + 5 mudas.
class SupplierNeedMatchTally {
  const SupplierNeedMatchTally({this.confirmed = 0, this.unverified = 0});

  /// El proveedor lo dice: **todos** los criterios pedidos están probados.
  final int confirmed;

  /// Nada la contradice, pero al menos un criterio no consta. Es candidata a
  /// revisar, no una fila que cumple.
  final int unverified;

  /// Lo que queda en el listado. Nunca es la cifra de «cumplen».
  int get total => confirmed + unverified;

  SupplierNeedMatchTally operator +(SupplierNeedMatchTally other) =>
      SupplierNeedMatchTally(
        confirmed: confirmed + other.confirmed,
        unverified: unverified + other.unverified,
      );

  @override
  bool operator ==(Object other) =>
      other is SupplierNeedMatchTally &&
      other.confirmed == confirmed &&
      other.unverified == unverified;

  @override
  int get hashCode => Object.hash(confirmed, unverified);

  @override
  String toString() =>
      'SupplierNeedMatchTally(confirmed: $confirmed, unverified: $unverified)';
}

/// Una fila que sobrevive al filtro, con su veredicto.
@immutable
class SupplierNeedMatchVerdict {
  const SupplierNeedMatchVerdict({
    required this.match,
    required this.isConfirmed,
  });

  final SupplierNeedPortalMatch match;

  /// El proveedor lo dice: todos los criterios pedidos están probados. Si es
  /// `false`, la fila queda igual en el listado pero **por verificar**.
  final bool isConfirmed;
}

/// Las filas que quedarían, en el orden en que vinieron, ya juzgadas.
///
/// Es la única implementación del juicio: el conteo se deriva de acá. Tener dos
/// —una que cuenta y otra que lista— es cómo un número deja de describir la
/// lista que se muestra al lado.
List<SupplierNeedMatchVerdict> judgeSupplierNeedMatchesUnder({
  required Iterable<SupplierNeedPortalMatch> matches,
  required List<SupplierNeedSearchPredicate> predicates,
  List<SupplierNeedSearchField> fields = const <SupplierNeedSearchField>[],
}) {
  SupplierNeedSearchField? definitionFor(String key) {
    for (final field in fields) {
      if (field.key == key) return field;
    }
    return null;
  }

  final asked = predicates
      .where((predicate) => predicate.field.trim().isNotEmpty)
      .toList(growable: false);

  final verdicts = <SupplierNeedMatchVerdict>[];
  for (final match in matches) {
    // **Un conflicto de REQUISITO no lo levanta un cambio de criterios.** Los
    // ejes de requisito son un conjunto cerrado y nombrado —identidad y
    // compatibilidad—: no dependen de la ficha, así que vaciar criterios no
    // puede revivir una fila que dice `NO COMPATIBLE CON MT200`.
    //
    // Todo lo demás **sí** depende de los criterios vigentes: un campo que el
    // operador acaba de retirar suelta su contradicción anterior, porque ya no
    // se está preguntando por él. Mirar «lo que no está en `asked`» convertía
    // cada campo retirado en un requisito permanente.
    final conflictosDeRequisito = match.conflictingFields
        .where((field) => kSupplierRequirementAxes.contains(field.trim()));
    if (match.state == SupplierNeedMatchState.conflict &&
        conflictosDeRequisito.isNotEmpty) {
      // La familia no la cambia una precisión de ficha: si ya contradecía por
      // ser otro objeto, lo sigue haciendo.
      continue;
    }
    var contradicted = false;
    // **La familia también hay que demostrarla.** `SupplierNeedMatchState.exact`
    // exige que NADA quede pendiente, familia incluida; contar como cumplida
    // una fila cuyo objeto no se pudo reconocer —sólo sus medidas— separaba el
    // conteo del estado que la propia fila muestra. Sin `product_family`
    // probado la fila sigue en el listado, pero por verificar.
    // **Un requisito pendiente impide llamarla cumplida** —cualquiera de los
    // ejes, no sólo la compatibilidad—. Cumplir dos specs no es calzar con el
    // modelo pedido, y un rodamiento que no menciona los sellos no cumple «con
    // sello de goma a ambos lados» por no contradecirlo.
    var everythingProven = asked.isNotEmpty &&
        match.provenFields.contains('product_family') &&
        !match.missingFields
            .any((field) => kSupplierRequirementAxes.contains(field.trim()));
    // **El mismo respaldo que usó la lista, calculado por el mismo dueño.** La
    // previsualización lo recalculaba por su cuenta y se le quedaba fuera la
    // distinción marca/compatibilidad: `MAGURA CLARA/LOUISE` trae la palabra
    // MAGURA como FABRICANTE, así que un escalar `brake_system = Magura` no
    // está respaldado —la lista lo dejaba pendiente— pero la cita literal sí
    // existía en el texto, y la previsualización lo tomaba por afirmado y lo
    // contradecía contra Shimano. Tres filas reales desaparecían al abrir la
    // misma ficha sin cambiar un solo criterio.
    final sinRespaldo = supplierFactsWithoutBacking(
      candidate: match.candidate,
      fields: fields,
    );
    for (final predicate in asked) {
      final campo = predicate.field.trim();
      final definicion = definitionFor(campo);
      final evidence = sinRespaldo.contains(campo)
          ? _PredicateEvidence.unknown
          : _predicateEvidence(
              match.observedFacts[campo],
              predicate,
              definicion,
            );
      if (evidence == _PredicateEvidence.conflict) {
        contradicted = true;
        break;
      }
      // Sin `break`: la ausencia no descarta la fila, pero **sí** le quita el
      // derecho a llamarse cumplida.
      if (evidence != _PredicateEvidence.proven) everythingProven = false;
    }
    if (contradicted) continue;
    verdicts.add(SupplierNeedMatchVerdict(
      match: match,
      isConfirmed: everythingProven,
    ));
  }
  return List<SupplierNeedMatchVerdict>.unmodifiable(verdicts);
}

SupplierNeedMatchTally tallySupplierNeedMatchesUnder({
  required Iterable<SupplierNeedPortalMatch> matches,
  required List<SupplierNeedSearchPredicate> predicates,
  List<SupplierNeedSearchField> fields = const <SupplierNeedSearchField>[],
}) {
  var confirmed = 0;
  var unverified = 0;
  for (final verdict in judgeSupplierNeedMatchesUnder(
    matches: matches,
    predicates: predicates,
    fields: fields,
  )) {
    if (verdict.isConfirmed) {
      confirmed++;
    } else {
      unverified++;
    }
  }
  return SupplierNeedMatchTally(confirmed: confirmed, unverified: unverified);
}

/// El campo con que se dice «la compatibilidad pedida no está demostrada».
///
/// No es una spec de la ficha: es el requisito que la petición trae y que
/// todavía nadie probó.
const String kCompatibilityRequirementField = 'compatibility_reference';

/// Los campos que esa fila declara como **inferidos** por el modelo.
Set<String> _inferredFieldsOf(SupplierPortalCatalogCandidate candidate) =>
    <String>{
      for (final raw in (candidate.technicalFacts[kSupplierInferredFactsFact]
              as List<Object?>? ??
          const <Object?>[]))
        raw.toString().trim(),
    };

/// Los ejes que **no** son criterios de la ficha.
///
/// Identidad y compatibilidad se juzgan contra lo que la petición pide y lo que
/// el proveedor escribe, no contra los criterios que el operador mueve. Por eso
/// su contradicción sobrevive a cualquier cambio de ficha — y por eso son un
/// conjunto cerrado y nombrado, no «todo lo que no se está preguntando».
const Set<String> kSupplierRequirementAxes = <String>{
  'product_family',
  kCompatibilityRequirementField,
  kRequestedPropertyField,
};

/// El eje con que se dice «la fila niega algo que la petición exige».
///
/// **Una exigencia no desaparece porque la ficha no tenga ese campo.** El
/// pedido decía «rodamientos **sellados** … con **sello** de goma a ambos
/// lados» y la ficha real sólo tiene aplicación y código, así que el sellado no
/// era criterio de nadie: una fila que dice `ABIERTO SIN SELLOS` cumplía los
/// dos criterios y salía Exacta.
///
/// No hace falta enseñar cada petición: si el proveedor **niega** una palabra
/// que la petición pide —`sin sellos` contra `sellados`—, eso es una
/// contradicción, tenga o no un campo donde vivir.
const String kRequestedPropertyField = 'requested_property';

/// Si el texto **niega la compatibilidad** con ese modelo.
///
/// **La negación pertenece a lo que nombra.** Una ventana de palabras hacia
/// atrás fallaba en los dos sentidos: dejaba pasar `MT200 NO ES COMPATIBLE`
/// —la negación va después— y descartaba `SIN ALETAS PARA MT200`, donde el
/// `sin` niega las aletas y no el calce. Se exige que el negador esté pegado a
/// una **palabra de compatibilidad** y que el modelo esté en esa misma
/// cláusula.
bool _modelIsDenied(String rawText, String code) {
  final tokens = _normalize(rawText).split(' ');
  final target = _normalize(code);
  const negadores = <String>{'no', 'sin', 'nunca'};
  bool esCompatibilidad(String word) =>
      word.startsWith('compatib') ||
      word.startsWith('calza') ||
      word.startsWith('sirve') ||
      word.startsWith('apto') ||
      word.startsWith('apta');

  // **El modelo también se escribe partido.** `MT 200` es `mt200`: el
  // extractor ya los une, y si la negación mira sólo palabras sueltas, una
  // advertencia escrita con espacio se escapa.
  final posicionesModelo = <int>[
    for (var index = 0; index < tokens.length; index += 1)
      if (tokens[index] == target ||
          tokens[index].contains(target) ||
          (index + 1 < tokens.length &&
              '${tokens[index]}${tokens[index + 1]}'.contains(target)))
        index,
  ];
  if (posicionesModelo.isEmpty) return false;

  for (var index = 0; index < tokens.length; index += 1) {
    if (!esCompatibilidad(tokens[index])) continue;
    var negada = false;
    for (var salto = 1; salto <= 2; salto += 1) {
      final antes = index - salto;
      if (antes >= 0 && negadores.contains(tokens[antes])) negada = true;
      final despues = index + salto;
      if (despues < tokens.length && negadores.contains(tokens[despues])) {
        negada = true;
      }
    }
    if (!negada) continue;
    for (final posicion in posicionesModelo) {
      if ((posicion - index).abs() <= 6) return true;
    }
  }
  return false;
}

/// Los modelos que la petición nombra, en la forma canónica del extractor.
///
/// `BR-MT200`, `MT200` y `BR MT200` son el mismo modelo: reconocerlos por su
/// forma escrita hacía que reformular borrara el requisito.
/// `ProductIdentityExtractor` ya los normaliza a `mt200`.
///
/// Pero `modelCodes` **no es un registro de modelos**: para «Cámaras aro 700»
/// devuelve `aro700`, que es la medida. Lo que separa un modelo de fabricante
/// de una medida es que la ficha puede expresar la medida y no el modelo: se
/// descartan los códigos que empiezan por número y los que empiezan con un
/// sustantivo de la taxonomía.
Set<String> _requestModelCodes(SupplierNeedSearchRequest request) {
  final text = request.description.trim();
  if (text.isEmpty) return const <String>{};
  final profile =
      ProductIdentityExtractor.extract(ProductIdentityInput(name: text));
  final crudos = <String>{
    ...profile.modelCodes,
    ...profile.compatibilityModelCodes,
  };
  return <String>{
    for (final code in crudos)
      if (RegExp(r'^[a-z]').hasMatch(code) &&
          !_taxonomyHeads.any((head) => code.startsWith(head)))
        code,
  };
}

/// Todos los sustantivos con que el dominio nombra una pieza.
///
/// La taxonomía **entera**, no la familia buscada: `aro700` sale de una
/// petición de cámaras y `aro` es palabra de llantas.
final Set<String> _taxonomyHeads = <String>{
  for (final family in BikePartTaxonomy.families)
    for (final head in family.heads)
      if (_normalize(head).isNotEmpty) _normalize(head).replaceAll(' ', ''),
};

/// Una propiedad que la petición exige, con su **polaridad** y su **alcance**.
///
/// **Un requisito tiene tres partes, no una.** `sello` pedido no es lo mismo
/// que `sello` negado, y «a ambos lados» no es lo mismo que «en un solo lado».
/// El eje anterior sólo miraba si el proveedor negaba una palabra del pedido,
/// así que perdía la polaridad —`SIN ALETAS` pedido contra `SIN ALETAS`
/// ofrecido salía contradicho, y contra `CON ALETAS` salía exacto— y trataba
/// la ausencia como cumplimiento.
@immutable
class _RequestedProperty {
  const _RequestedProperty({
    required this.stem,
    required this.affirmed,
    required this.scope,
    this.tail = const <String>[],
    this.label = '',
    this.remittedByInference = false,
  });

  /// Los tokens que tienen que seguir al primero, contiguos. Vacío para una
  /// palabra suelta; `['32']` para la fracción `3/32`, que el normalizador
  /// canónico parte en dos.
  final List<String> tail;

  /// La palabra tal como aparece en la petición.
  final String label;

  /// **Remitida a su criterio por una lectura del modelo, no demostrada.**
  ///
  /// Cuando la equivalencia entre la palabra del taller y el valor de la ficha
  /// está corroborada —el vocabulario de la propia ficha, o una equivalencia
  /// canónica de valores—, la palabra ni siquiera llega acá: se juzga como
  /// criterio. Cuando la sostiene **sólo** el modelo, la exigencia se conserva
  /// y se juzga contra la fila como cualquier otra; lo que el tramo aporta no
  /// es un veredicto sino saber **cuál criterio** la representa, para poder
  /// decírselo al operador.
  ///
  /// La frontera se sostiene sin ninguna regla extra: el silencio de la fila ya
  /// es «pendiente», así que una inferencia nunca completa. Y al revés, tampoco
  /// tapa nada: si el proveedor escribe la palabra, esa evidencia manda.
  final bool remittedByInference;

  /// La raíz, para que `sellos` y `sello` sean la misma propiedad.
  final String stem;

  /// `true` si la petición la exige presente; `false` si la exige ausente.
  final bool affirmed;

  /// Las palabras de cantidad o alcance que la acompañan: `ambos`, `lados`.
  final Set<String> scope;

  @override
  bool operator ==(Object other) =>
      other is _RequestedProperty &&
      other.stem == stem &&
      other.affirmed == affirmed &&
      other.remittedByInference == remittedByInference &&
      other.scope.length == scope.length &&
      other.scope.containsAll(scope);

  @override
  int get hashCode => Object.hash(stem, affirmed, scope.length);
}

/// Conectores y preposiciones: aparecen en cualquier fila y no prueban nada.
const Set<String> kSupplyFunctionWords = <String>{
  'con', 'sin', 'para', 'por', 'del', 'las', 'los', 'una', 'uno', 'unos',
  'unas', 'que', 'este', 'esta', 'como', 'tipo', 'muy', 'mas', 'menos',
};

/// Palabras que **niegan** lo que viene después.
const Set<String> _kPolarityNegators = <String>{
  'sin', 'no', 'nunca', 'ningun', 'ninguna', 'ninguno', 'exento', 'exenta',
  'carece', 'excluye', 'salvo',
};

/// Palabras que **cierran** una negación y devuelven el texto a lo afirmado.
///
/// El normalizador canónico ya convierte coma y punto en `~`, así que el
/// límite de cláusula llega hasta acá como un token propio.
const Set<String> _kPolarityResets = <String>{
  'con', 'y', 'e', 'o', 'u', '~', '+', 'pero', 'mas', 'ademas', 'tambien',
  'incluye', 'incluyen', 'trae', 'para',
};

/// Las palabras de **cantidad o alcance** que acompañan a una propiedad.
const Set<String> _kScopeWords = kSupplyScopeWords;

/// Las palabras de **cantidad o alcance** que acompañan a una propiedad.
const Set<String> kSupplyScopeWords = <String>{
  'ambos', 'ambas', 'lados', 'lado', 'caras', 'cara', 'solo', 'sola',
  'unico', 'unica', 'doble', 'simple', 'completo', 'completa',
};

/// Para cada token, si aparece **afirmado**.
///
/// La negación en castellano alcanza al sintagma, no a la palabra siguiente:
/// «sin aletas de refrigeración» niega las tres. Por eso se arrastra unos
/// pocos tokens y se corta en el primer conector afirmativo o límite de
/// cláusula, en vez de mirar sólo la palabra anterior.
List<bool> _affirmedPolarity(List<String> tokens) {
  const alcanceMaximo = 4;
  final afirmado = List<bool>.filled(tokens.length, true);
  var restante = 0;
  for (var index = 0; index < tokens.length; index += 1) {
    final palabra = tokens[index];
    if (_kPolarityNegators.contains(palabra)) {
      restante = alcanceMaximo;
      continue;
    }
    if (_kPolarityResets.contains(palabra)) {
      restante = 0;
      continue;
    }
    if (restante > 0) {
      afirmado[index] = false;
      restante -= 1;
    }
  }
  return afirmado;
}

/// La raíz de una palabra, para que la misma exigencia escrita de dos formas
/// sea una sola.
///
/// **El participio y el sustantivo nombran lo mismo.** «Rodamientos
/// **sellados**» y «**sello** de goma» son la misma pieza de información, y una
/// fila que dice `ABIERTO SIN SELLOS` está contradiciendo la primera aunque no
/// repita su palabra. Con la raíz sólo plural, esa contradicción no se veía y
/// la fila quedaba «pendiente» en vez de contradicha.
String _propertyStem(String word) {
  var raiz = word;
  if (raiz.endsWith('es') && raiz.length > 5) {
    raiz = raiz.substring(0, raiz.length - 2);
  } else if (raiz.endsWith('s') && raiz.length > 4) {
    raiz = raiz.substring(0, raiz.length - 1);
  }
  for (final participio in const <String>['ado', 'ada', 'ido', 'ida']) {
    if (raiz.endsWith(participio) && raiz.length - participio.length >= 4) {
      return raiz.substring(0, raiz.length - participio.length);
    }
  }
  return raiz;
}

/// Qué dice la fila sobre esa propiedad.
///
/// - **Proven**: la nombra con la misma polaridad y con el alcance pedido.
/// - **Conflict**: la nombra con la polaridad contraria.
/// - **Unknown**: no la nombra, o la nombra sin el alcance pedido. En los dos
///   casos el requisito **sigue sin demostrarse**, que es exactamente lo que
///   impide llamar exacta a la fila. Una ausencia no es un cumplimiento.
/// Si la exigencia empieza exactamente acá.
///
/// Un número se compara completo —`3` no es `32` ni `300`—; una palabra por su
/// raíz, que es lo que hace `sellos` y `sellados` la misma exigencia.
bool _matchesHere(List<String> tokens, int index, _RequestedProperty prop) {
  final esNumero = RegExp(r'^[0-9]+$').hasMatch(prop.stem);
  final cabeza = tokens[index];
  if (esNumero ? cabeza != prop.stem : !cabeza.startsWith(prop.stem)) {
    return false;
  }
  for (var salto = 0; salto < prop.tail.length; salto += 1) {
    final siguiente = index + salto + 1;
    if (siguiente >= tokens.length) return false;
    if (tokens[siguiente] != prop.tail[salto]) return false;
  }
  return true;
}

_PredicateEvidence _propertyEvidence(String rowText, _RequestedProperty prop) {
  final tokens = rowText.split(' ');
  final afirmado = _affirmedPolarity(tokens);
  var visto = _PredicateEvidence.unknown;
  for (var index = 0; index < tokens.length; index += 1) {
    if (!_matchesHere(tokens, index, prop)) continue;
    if (afirmado[index] != prop.affirmed) return _PredicateEvidence.conflict;
    if (prop.scope.isEmpty) return _PredicateEvidence.proven;
    // **El alcance también se demuestra, y no siempre va detrás.** «Sello de
    // goma en un solo lado» nombra la propiedad y no el alcance pedido: no
    // contradice —puede haber otra variante—, pero tampoco cumple. Y en
    // castellano el alcance suele **preceder**: «DOBLE ABRAZADERA», «UNA SOLA
    // PIEZA». Mirar sólo hacia adelante dejaba sin demostrar filas que lo
    // dicen con todas las letras.
    final cerca = <String>{
      for (var salto = 1; salto <= 6; salto += 1) ...<String>[
        if (index + salto < tokens.length)
          _propertyStem(tokens[index + salto]),
        if (index - salto >= 0) _propertyStem(tokens[index - salto]),
      ],
    };
    if (prop.scope.every(cerca.contains)) return _PredicateEvidence.proven;
    visto = _PredicateEvidence.unknown;
  }
  return visto;
}

/// Las propiedades que la petición exige y **la ficha no supo absorber**.
///
/// Lo que ya es criterio se juzga como criterio; acá quedan las exigencias sin
/// dónde vivir —el sellado de un rodamiento cuya plantilla sólo trae aplicación
/// y código, las aletas de una pastilla cuya plantilla sólo trae el sistema—
/// para que no desaparezcan del juicio por no tener campo.
///
/// No hay vocabulario por referencia: una palabra entra si es lo bastante
/// específica, no la aporta la propia familia, no es trámite y ningún campo,
/// valor permitido o predicado de la ficha ya la representa.
Set<_RequestedProperty> _requestedProperties(SupplierNeedSearchPlan plan) {
  final cache = _requestedPropertiesCache[plan];
  if (cache != null) return cache;
  final tokens = _normalize(plan.request.description).split(' ');
  final afirmado = _affirmedPolarity(tokens);
  // **Una fracción es una medida, nunca una cantidad.** `3/32` y `1/8` son el
  // ancho de la cadena, y el normalizador canónico les come la barra: quedan
  // como dos números sueltos que el filtro de dígitos descartaba enteros. Nadie
  // escribe una cantidad con barra, así que se recuperan del texto crudo y se
  // exigen como una pareja contigua.
  final fracciones = <List<String>>[
    for (final match
        in RegExp(r'\b\d+\s*/\s*\d+\b').allMatches(plan.request.description))
      _normalize(match.group(0)!).split(' '),
  ];
  final heads = <String>{
    ...plan.familyTerms,
    ..._taxonomyHeads,
  };
  // **Cada criterio sabe con qué palabras se lo nombra.** Lo que la ficha ya
  // expresa no vuelve por esta puerta —se juzga como criterio, con su operador
  // y su cita—, y además queda registrado **cuál** criterio la petición nombró.
  final vocabularioDe = <String, Set<String>>{};
  final conceptosDe = <String, Set<String>>{};
  void cubrir(String campo, Iterable<String> palabras) {
    final destino = vocabularioDe.putIfAbsent(campo.trim(), () => <String>{});
    final conceptos = conceptosDe.putIfAbsent(campo.trim(), () => <String>{});
    for (final palabra in palabras) {
      final concepto = canonicalSupplierSpecConcept(palabra);
      if (concepto != null) conceptos.add(concepto);
      final stem = _propertyStem(palabra);
      if (stem.length >= 3) destino.add(stem);
    }
  }

  for (final field in plan.request.fields) {
    cubrir(field.key, _normalize(field.label).split(' '));
    cubrir(field.key, _normalize(field.key.replaceAll('_', ' ')).split(' '));
    for (final value in field.allowedValues) {
      cubrir(field.key, _normalize('$value').split(' '));
    }
  }
  for (final predicate in plan.request.predicates) {
    for (final value in predicate.values) {
      cubrir(predicate.field, _normalize('$value').split(' '));
    }
  }

  // **La atribución necesita evidencia positiva, no una cuenta.** Que sobren
  // tantas palabras como criterios no demuestra qué frase corresponde a qué
  // criterio: un criterio puede haberse elegido después, en `Criterios`, sin
  // reescribir la petición. Con esa cuenta, un `Aplicación = Maza` recién
  // agregado se comía la exigencia «sellados», que no tiene ninguna relación
  // con él. Lo que sí liga una palabra a un campo es el **vocabulario**: sus
  // rótulos, sus valores permitidos y las palabras que el dominio reconoce como
  // el mismo valor —«resina» y `Orgánico` nombran el mismo compuesto—.
  // **Dónde está escrito cada criterio, cuando alguien pudo establecerlo.** Es
  // la vía general: el mismo lector que lee la fila de un proveedor lee la
  // petición y señala qué tramo declara cada criterio vigente, verificado
  // contra el texto y contra el valor que el operador ya pidió. Una lista de
  // sinónimos sólo conoce las palabras que alguien alcanzó a escribir; esto
  // funciona con la petición de mañana. Vacío significa que nadie pudo
  // establecerlo, y entonces manda el vocabulario de la ficha, como siempre.
  final tramos = <String>{
    for (final span in plan.request.criteriaSpans)
      for (final palabra in _normalize(span).split(' '))
        if (palabra.length >= 3) _propertyStem(palabra),
  };

  bool cubierta(String palabra, String stem) {
    final concepto = canonicalSupplierSpecConcept(palabra);
    var visto = false;
    for (final entry in vocabularioDe.entries) {
      final porConcepto =
          concepto != null && (conceptosDe[entry.key]?.contains(concepto) ?? false);
      if (!porConcepto &&
          !entry.value.any(
            (word) => word.startsWith(stem) || stem.startsWith(word),
          )) {
        continue;
      }
      visto = true;
    }
    return visto;
  }

  final propiedades = <String, _RequestedProperty>{};
  // **`X de Y` nombra una sola cosa.** `motor de centro` es el objeto, no un
  // motor con la propiedad «centro»; `aletas de refrigeración` es una sola
  // exigencia, no dos. Sin esto, cada sintagma del castellano se convertía en
  // un requisito extra que ninguna fila podía demostrar, y nada volvía a ser
  // exacto. Lo que refina un nombre se cuelga de él y no exige aparte.
  const enlaces = <String>{'de', 'del', 'para', 'tipo'};
  var ancla = false;
  var enlazado = false;
  for (var index = 0; index < tokens.length; index += 1) {
    final palabra = tokens[index];
    if (enlaces.contains(palabra)) {
      enlazado = ancla;
      continue;
    }
    final continuaElNombre = enlazado;
    enlazado = false;
    // Un número también nombra a su criterio —`6902` es el código pedido—, y
    // saberlo importa antes de descartarlo como propiedad.
    if (afirmado[index] && cubierta(palabra, _propertyStem(palabra))) {
      ancla = true;
      continue;
    }
    // Cuatro letras ya son una exigencia: `goma` se perdía por corta, y era
    // justo lo que el taller pedía.
    if (palabra.length < 4 ||
        RegExp(r'[0-9]').hasMatch(palabra) ||
        _kScopeWords.contains(palabra) ||
        _kPolarityNegators.contains(palabra) ||
        _kPolarityResets.contains(palabra)) {
      ancla = false;
      continue;
    }
    if (_kRequestBoilerplate.contains(palabra)) {
      ancla = false;
      continue;
    }
    // **Lo que el taller EXCLUYE nunca se absorbe.** «No cassette» se perdía
    // porque `cassette` es vocabulario de la familia, que es exactamente la
    // razón por la que importa: el operador está descartando una pieza hermana
    // que el buscador va a devolver igual. Una palabra negada es siempre una
    // exigencia, la nombre quien la nombre.
    final excluida = !afirmado[index];
    // La regla del sintagma sigue valiendo aunque esté negada: «sin aletas de
    // refrigeración» es UNA exigencia, no dos, y partirla dejaría pendiente
    // para siempre la mitad que el proveedor nunca escribe.
    if (continuaElNombre) continue;
    if (!excluida) {
      if (heads.any(
        (head) => palabra.startsWith(head) || head.startsWith(palabra),
      )) {
        ancla = true;
        continue;
      }
    }
    final stem = _propertyStem(palabra);
    if (stem.length < 4) {
      ancla = false;
      continue;
    }
    if (!excluida && cubierta(palabra, stem)) {
      ancla = true;
      continue;
    }
    // **Una palabra que INTRODUCE un criterio nombra el campo, no una
    // exigencia nueva.** «Con anclaje de 6 pernos» dice el montaje que la ficha
    // ya pregunta; exigir además la palabra «anclaje» dejaba pendiente una fila
    // que declara `6 PERNOS` con todas las letras. Es la regla del sintagma
    // mirando hacia adelante: si lo que sigue es el valor de un criterio, esto
    // era su rótulo.
    if (!excluida && _introducesCoveredValue(tokens, index, enlaces, cubierta)) {
      ancla = true;
      continue;
    }
    ancla = true;
    final scope = <String>{
      for (var salto = 1; salto <= 6; salto += 1)
        if (index + salto < tokens.length &&
            _kScopeWords.contains(tokens[index + salto]))
          _propertyStem(tokens[index + salto]),
    };
    final existente = propiedades[stem];
    if (existente == null || existente.scope.length < scope.length) {
      propiedades[stem] = _RequestedProperty(
        stem: stem,
        label: palabra,
        affirmed: afirmado[index],
        scope: scope,
        // El modelo la remitió a un criterio, pero nadie corroboró esa
        // equivalencia: se conserva pendiente en vez de completar.
        remittedByInference: tramos.contains(stem),
      );
    }
  }

  // **Lo que el lector encontró en el texto entero se une a lo que el código
  // alcanzó a ver.** Los filtros deterministas —largo mínimo, dígitos,
  // sintagmas— existen por buenas razones y aun así dejan caer exigencias antes
  // de que nadie las lea. Unir, no reemplazar: si el modelo no está, lo
  // determinista sigue siendo todo lo que hay.
  for (final encontrada in plan.request.discoveredRequirements) {
    final stem = encontrada.term.trim();
    if (stem.isEmpty) continue;
    final existente = propiedades[stem];
    if (existente != null && existente.scope.length >= encontrada.scope.length) {
      continue;
    }
    propiedades[stem] = _RequestedProperty(
      stem: stem,
      tail: encontrada.tail,
      label: encontrada.label,
      affirmed: encontrada.affirmed,
      scope: encontrada.scope.toSet(),
    );
  }

  for (final fraccion in fracciones) {
    if (fraccion.isEmpty) continue;
    final clave = fraccion.join(' ');
    if (propiedades.containsKey(clave)) continue;
    if (cubierta(clave, clave)) continue;
    propiedades[clave] = _RequestedProperty(
      stem: fraccion.first,
      tail: fraccion.skip(1).toList(growable: false),
      label: clave.replaceAll(' ', '/'),
      affirmed: true,
      scope: const <String>{},
    );
  }
  final resultado = Set<_RequestedProperty>.unmodifiable(propiedades.values);
  _requestedPropertiesCache[plan] = resultado;
  return resultado;
}

/// Qué se sabe de una exigencia fuera de ficha, para ESTA fila.
///
/// **Tres niveles, y la diferencia entre ellos es toda la honestidad del
/// módulo.** Lo demostrado lo dice el texto del proveedor y lo comprueba el
/// código; lo inferido lo concluyó el modelo y viaja con la cita que usó, para
/// que el operador pueda desmentirlo; lo desconocido se admite como tal en vez
/// de rellenarse. Nada de esto elimina una fila: una duda ordena y avisa, no
/// borra.
enum SupplyRequirementStatus {
  /// El texto del proveedor la dice, con la polaridad y el alcance pedidos.
  proven,

  /// El texto del proveedor dice lo contrario.
  contradicted,

  /// El modelo concluyó que la cumple. Recomienda; no demuestra.
  inferred,

  /// El modelo cree que no la cumple y el texto citado no lo confirma.
  doubted,

  /// Nadie dijo nada.
  unknown,
}

/// Una exigencia fuera de ficha y lo que se sabe de ella en una fila.
@immutable
class SupplyRequirementFinding {
  const SupplyRequirementFinding({
    required this.label,
    required this.affirmed,
    required this.status,
    this.quote,
  });

  /// La palabra del taller, tal como la escribió.
  final String label;

  /// Si la pidió presente o ausente.
  final bool affirmed;

  final SupplyRequirementStatus status;

  /// La cita del proveedor cuando la hay: es lo que hace verificable una
  /// lectura del modelo en vez de una afirmación suya.
  final String? quote;
}

/// Las exigencias de la petición que **ninguna ficha puede expresar**.
///
/// Son las que hoy sólo se pueden probar si la palabra aparece literal en la
/// fila: «a ambos lados», «de kevlar», «sin aletas». Publicarlas permite
/// preguntárselas al lector del proveedor, que es la única forma de que dejen
/// de quedar pendientes para siempre cuando el proveedor las dice con otras
/// palabras.
List<SupplyNeedUnmodelledRequirement> supplyNeedUnmodelledRequirements(
  SupplierNeedSearchPlan plan,
) =>
    <SupplyNeedUnmodelledRequirement>[
      for (final property in _requestedProperties(plan))
        SupplyNeedUnmodelledRequirement(
          term: property.stem,
          // **La exigencia viaja entera.** Sin `tail` y sin `label`, al lector
          // del proveedor le llegaba `3` en vez de `3/32`: una raíz interna no
          // es una pregunta que nadie pueda contestar.
          tail: property.tail,
          label: property.label,
          affirmed: property.affirmed,
          scope: property.scope.toList(growable: false),
        ),
    ];

/// Una exigencia del taller que la plantilla no sabe nombrar.
@immutable
class SupplyNeedUnmodelledRequirement {
  const SupplyNeedUnmodelledRequirement({
    required this.term,
    required this.affirmed,
    required this.scope,
    this.tail = const <String>[],
    this.label = '',
  });

  /// Los tokens que tienen que seguir al primero, contiguos: `3/32` llega
  /// partido en dos porque el normalizador canónico se come la barra.
  final List<String> tail;

  /// La raíz de la palabra con que el taller la escribió.
  final String term;

  /// Y la palabra tal como el taller la escribió: `sell` no se le muestra a
  /// nadie, «sellados» sí.
  final String label;

  /// **La exigencia completa, en una línea.** Una lectura del proveedor
  /// responde una pregunta concreta, y ninguna parte suelta la identifica.
  /// «Puños CON gel» y «puños SIN gel» comparten término y frase y son
  /// preguntas opuestas: hace falta la polaridad. Y «resistente al agua» y
  /// «resistente al calor» comparten término, polaridad y alcance: hace falta
  /// **la frase**, que además es lo que el lector recibe y usa para
  /// interpretar. Van las cuatro: frase, término, dimensión, polaridad y
  /// alcance.
  String get signature => <String>[
        ProductIdentityExtractor.normalize(label),
        term,
        ...tail,
        affirmed ? '+' : '-',
        ...(scope.toList()..sort()),
      ].join('\u0000');

  /// Si la pide presente o ausente.
  final bool affirmed;

  /// Las palabras de alcance que la acompañan: `ambo`, `lado`.
  final List<String> scope;
}

/// El plan es el mismo para todas las filas de una corrida; leer la petición
/// una vez por fila era gasto puro.
final Expando<Set<_RequestedProperty>> _requestedPropertiesCache =
    Expando<Set<_RequestedProperty>>('requested-properties');

/// Palabras de trámite: dicen cómo se pide, no qué se pide.
const Set<String> _kRequestBoilerplate = <String>{
  'necesito', 'necesitamos', 'quiero', 'queremos', 'requiero', 'requerimos',
  'favor', 'porfavor', 'cotizar', 'cotizacion', 'comprar', 'compra', 'pedido',
  'pedir', 'urgente', 'taller', 'tienda', 'bodega', 'stock', 'reposicion',
  'reponer', 'cliente', 'clientes', 'unidad', 'unidades', 'juego', 'juegos',
  'pares', 'cajas', 'pack', 'packs', 'aproximadamente', 'preferentemente',
  'preferible', 'barato', 'barata', 'economico', 'economica', 'nuevos',
  'nuevas', 'nuevo', 'nueva', 'pesos', 'precio', 'costo', 'marca', 'modelo',
  'tipo', 'tipos', 'medida', 'medidas', 'talla', 'color', 'colores',
  'cualquier', 'cualquiera', 'todos', 'todas', 'algun', 'alguna', 'debe',
  'deben', 'sean', 'estar', 'tener', 'tenga', 'tengan', 'venga', 'vengan',
  'sirva', 'sirvan', 'usar', 'usamos', 'ojala', 'idealmente', 'entrega',
  'despacho', 'proveedor', 'proveedores', 'catalogo', 'producto', 'productos',
  // Comparadores y cuantificadores: dicen cómo se acota un número, no qué
  // propiedad tiene la pieza.
  'entre', 'desde', 'hasta', 'mayor', 'menor', 'menos', 'sobre', 'bajo',
  'minimo', 'minima', 'maximo', 'maxima', 'igual', 'aprox', 'cerca',
  'alrededor', 'similar', 'parecido', 'equivalente', 'rango',
};

/// Si esa palabra aparece **sólo como fabricante** en el texto.
///
/// **Qué es una pieza y con qué calza son cosas distintas** —lo dice el
/// contrato de identidad—, y `Shimano` puede ser las dos: la marca que la
/// fabrica o el sistema al que sirve. Tomar la marca por compatibilidad hacía
/// dos daños opuestos: descartaba `MARCA TEKTRO PARA FRENOS SHIMANO` de una
/// búsqueda Shimano, y daba por probado el sistema de una pastilla que sólo
/// dice `MARCA SHIMANO`.
///
/// Una aparición cuenta como compatibilidad cuando algo la introduce como tal
/// —`para`, `compatible con`, `calza`—; cuenta como fabricante cuando la
/// introduce `marca` o cuando es la marca declarada de la fila. Si todas sus
/// apariciones son de fabricante, no dice nada del sistema.
bool _valueIsOnlyBrand(String text, String value, String? brand) {
  final target = _normalize(value);
  if (target.isEmpty) return false;
  final tokens = text.split(' ');
  final marca = _normalize(brand ?? '');
  const fitment = <String>{
    'para', 'compatible', 'compatibles', 'calza', 'calzan', 'sirve', 'sirven',
    'apto', 'apta', 'uso',
  };
  var vistas = 0;
  var soloMarca = true;
  for (var index = 0; index < tokens.length; index += 1) {
    if (tokens[index] != target) continue;
    vistas += 1;
    var esFitment = false;
    for (var atras = 1; atras <= 3; atras += 1) {
      final previo = index - atras;
      if (previo < 0) break;
      if (fitment.contains(tokens[previo])) {
        esFitment = true;
        break;
      }
    }
    if (esFitment) {
      soloMarca = false;
      continue;
    }
    var esMarca = target == marca;
    for (var atras = 1; atras <= 2; atras += 1) {
      final previo = index - atras;
      if (previo < 0) break;
      if (tokens[previo] == 'marca') esMarca = true;
    }
    if (!esMarca) soloMarca = false;
  }
  return vistas > 0 && soloMarca;
}
