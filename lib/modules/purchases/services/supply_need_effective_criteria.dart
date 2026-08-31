import '../../../shared/services/supplier_need_portal_search.dart';
import '../../inventory/services/product_identity/bike_part_taxonomy.dart';
import '../../inventory/services/product_identity/product_identity_extractor.dart';
import '../../inventory/services/spec_engine_service.dart';
import '../models/intelligent_purchasing_models.dart';
import '../models/supplier_catalog.dart';

/// La ficha **efectiva** de una necesidad: lo guardado más lo que la propia
/// petición ya declara.
///
/// **El defecto que cierra.** «Cámaras 700» dice el aro con todas las letras.
/// La interpretación guardó la categoría y un perfil de ranking, y nada más, así
/// que `wheel_size` no existía en ninguna revisión. Con eso:
///
/// - `Criterios` abría en «Tamaño de rueda: sin especificar», pidiéndole al
///   operador que escribiera de nuevo lo que ya había escrito;
/// - y, peor, el feed se rejuzgaba **como «cualquier cámara»**: la corrida real
///   del 2026-08-30 pasó de 18 a 22 filas «por revisar» e incluyó aro 26, 27.5
///   y varias 28. No era un defecto visual: era la ficha con la que se juzga.
///
/// Por eso vive acá y no en el editor. Un parche en el formulario habría
/// arreglado el primer síntoma y dejado el segundo intacto: **editor,
/// previsualización, `_needSearchRequest` y el rejuicio del feed tienen que
/// compartir exactamente esta ficha**.
///
/// **Lo guardado manda.** Una revisión explícita es una decisión del operador;
/// la derivación sólo llena lo que nadie decidió todavía. Y es derivación, no
/// persistencia: se muestra para que pueda verla y cambiarla, y sólo se guarda
/// si refina.
SupplyNeedCriteria effectiveSupplyNeedCriteria({
  required SupplyNeedCriteria stored,
  required List<String> texts,
  required List<SupplierNeedSearchField> fields,

  /// La familia técnica de la **plantilla canónica** de la categoría.
  ///
  /// `create_supply_need_batch_v2` omite `technical_family` a propósito: su
  /// contrato la deriva de `category_tech_mappings`, así que la columna nace
  /// nula y el lector nuevo sólo leía esa columna. Resultado: la primera
  /// revisión de una necesidad recién creada se quedaba sin familia, que es
  /// justo la condición donde la identidad se juzga peor. La plantilla ya la
  /// tiene y es la misma autoridad; no hace falta tocar la base.
  String? templateTechnicalFamily,
}) {
  final fuentes = <String>[
    for (final text in texts)
      if (text.trim().isNotEmpty) text.trim(),
  ];
  if (fuentes.isEmpty || fields.isEmpty) return stored;

  final declared = <String>{
    for (final predicate in stored.predicates) predicate.field.trim(),
  };

  // **Cada fuente se lee en su propio contexto y después se fusionan por
  // campo.** Concatenarlas y pedirle a cada extractor que resuelva
  // contradicciones cruzadas era frágil en las dos direcciones: `Cámara 700` +
  // `29 unidades para el taller` marcaba ambigüedad y perdía el 700 que el
  // nombre sí dice, y una palabra del nombre podía pegarse a un número de la
  // petición. Leídas aparte, cada guard trabaja donde tiene sentido.
  //
  // La fusión es simple y no inventa: **igual conserva, distinto omite**, y lo
  // que sólo una fuente dice se conserva. Lo guardado manda sobre todo.
  final porCampo = <String, Set<Object>>{};
  final operadorDe = <String, String>{};
  for (final fuente in fuentes) {
    for (final predicate in supplyNeedSpecsStatedInRequest(
      description: fuente,
      fields: fields,
      familyHeads: supplyNeedFamilyHeads(
        technicalFamily: stored.technicalFamily ?? templateTechnicalFamily,
        categoryPath: stored.categoryPath,
        description: fuente,
      ),
    )) {
      final campo = predicate.field.trim();
      if (declared.contains(campo)) continue;
      porCampo
          .putIfAbsent(campo, () => <Object>{})
          .add(predicate.values.single);
      operadorDe[campo] = predicate.operator;
    }
  }

  final derived = <SupplyNeedPredicate>[];
  for (final entry in porCampo.entries) {
    // Dos fuentes que se contradicen no eligen: eso es no saber.
    if (entry.value.length != 1) continue;
    derived.add(SupplyNeedPredicate(
      field: entry.key,
      operator: operadorDe[entry.key] ?? 'eq',
      values: <Object>[entry.value.single],
    ));
  }
  if (derived.isEmpty) return stored;

  return SupplyNeedCriteria(
    predicates: List<SupplyNeedPredicate>.unmodifiable(
      <SupplyNeedPredicate>[...stored.predicates, ...derived],
    ),
    commercialPreference: stored.commercialPreference,
    categoryId: stored.categoryId,
    categoryPath: stored.categoryPath,
    revisionNo: stored.revisionNo,
    technicalFamily: stored.technicalFamily,
  );
}

/// Los campos de una ficha en el vocabulario del buscador.
///
/// El editor los tiene como `SpecTemplateField` y el buscador como
/// `SupplierNeedSearchField`; la traducción estaba escrita dos veces en la
/// página, y una ficha efectiva que no se calcule con los MISMOS campos que el
/// plan del proveedor no es la misma ficha.
List<SupplierNeedSearchField> supplyNeedSearchFieldsOf(SpecTemplate? template) {
  if (template == null) return const <SupplierNeedSearchField>[];
  final fields = <SupplierNeedSearchField>[];
  for (final field in template.fields) {
    final definition = field.definition;
    if (definition == null) continue;
    fields.add(SupplierNeedSearchField(
      key: definition.key,
      label: definition.label,
      dataType: definition.dataType,
      unit: definition.unit,
      // La ficha lo llama `helpText`; es la misma `description` de la base.
      description: definition.helpText,
      allowedValues: definition.options,
      validationRules: Map<String, Object?>.from(definition.validationRules),
      isRequired: field.isRequired,
    ));
  }
  return List<SupplierNeedSearchField>.unmodifiable(fields);
}

/// Los sustantivos con que se nombra lo que se está pidiendo.
///
/// **Tres fuentes, porque una sola falla.** La ficha guarda
/// `technical_family` —`tube`, `rim`, `rotor`— y la taxonomía canónica usa sus
/// propios ids: `rotor` no existe ahí, se llama `brake_rotor`, así que buscar
/// sólo por id dejaba a los discos sin vocabulario y «disco 180» sin diámetro.
///
/// 1. La taxonomía por id, cuando coinciden.
/// 2. La familia que el extractor reconoce en la propia petición.
/// 3. **El nombre que la categoría le da al objeto** —el último tramo de
///    `categoryPath`—, con su singular. Es la palabra que el operador ve en
///    pantalla, y en «Componentes / Frenos / Discos» es la única que dice
///    `disco`.
List<String> supplyNeedFamilyHeads({
  required String? technicalFamily,
  required String? categoryPath,
  required String? description,
}) {
  final heads = <String>{};
  void add(Iterable<String>? values) {
    for (final value in values ?? const <String>[]) {
      final clean = value.trim();
      if (clean.isNotEmpty) heads.add(clean);
    }
  }

  add(BikePartTaxonomy.byId(technicalFamily)?.heads);
  final text = description?.trim() ?? '';
  if (text.isNotEmpty) {
    // Lo que el pedido excluye no puede nombrar lo que pide: «(no Center Lock)»
    // convertía un disco de freno en la familia `lock`.
    final identity = ProductIdentityExtractor.extract(
      ProductIdentityInput(name: supplyNeedTextWithoutExclusions(text)),
    );
    add(BikePartTaxonomy.byId(identity.familyId)?.heads);
  }
  final leaf = (categoryPath ?? '').split('/').last.trim().toLowerCase();
  if (leaf.isNotEmpty && !leaf.contains(' ')) {
    heads.add(leaf);
    // Plural chileno, que es como se rotula una categoría: `Discos` → `disco`.
    if (leaf.endsWith('es') && leaf.length > 4) {
      heads.add(leaf.substring(0, leaf.length - 2));
    } else if (leaf.endsWith('s') && leaf.length > 3) {
      heads.add(leaf.substring(0, leaf.length - 1));
    }
  }
  return List<String>.unmodifiable(heads);
}

/// El texto de la petición: lo reconocido **y** lo que el operador escribió.
///
/// **Un nombre reconocido no reemplaza a la petición.** La página derivaba la
/// ficha y armaba la búsqueda desde `productName ?? description`, así que en
/// cuanto la interpretación reconocía un producto, todo lo que el operador
/// había escrito y no cabía en ese nombre dejaba de existir. El fake realista
/// del propio módulo lo muestra: `Neumático 27,5` como nombre y
/// `neumático económico 27,5 ancho mayor a 2,0` como petición. Es el mismo
/// defecto de «Cámaras 700» un nivel más arriba — un dato explícito descartado
/// antes de llegar a la ficha y al feed.
///
/// **Las dos mitades van separadas por una cláusula.** El normalizador canónico
/// convierte el punto en `~`, y esa marca impide que la última palabra del
/// nombre se pegue al primer número de la petición: unir los textos no puede
/// fabricar una medida que ninguno de los dos dice. Si se contradicen, el lector
/// ve dos valores y no afirma ninguno, que es la respuesta correcta.
///
/// Va primero el nombre reconocido, porque es la identidad; y si la petición ya
/// lo contiene, no se repite.
List<String> supplyNeedRequestTexts(SupplyNeed need) {
  final nombre = need.productName?.trim() ?? '';
  final peticion = need.description.trim();
  if (nombre.isEmpty) return <String>[peticion];
  if (peticion.isEmpty) return <String>[nombre];
  if (peticion.toLowerCase().contains(nombre.toLowerCase())) {
    return <String>[peticion];
  }
  return <String>[nombre, peticion];
}

String supplyNeedRequestText(SupplyNeed need) {
  final nombre = need.productName?.trim() ?? '';
  final peticion = need.description.trim();
  if (nombre.isEmpty) return peticion;
  if (peticion.isEmpty) return nombre;
  final unaDentroDeLaOtra =
      peticion.toLowerCase().contains(nombre.toLowerCase());
  if (unaDentroDeLaOtra) return peticion;
  return '$nombre. $peticion';
}

/// Cuáles filas del catálogo interno de un proveedor **destaca** el juicio
/// compartido.
///
/// **Una coincidencia amplia del servidor no es un cumplimiento.** Los CTA de
/// MKR y AliExpress abren su catálogo interno y `supplier_catalog_page_v1`
/// marca `matchesNeed` con un criterio propio y ancho: bajo «COINCIDE CON esta
/// petición» aparecían patines, frenos completos, discos, mangueras y olivas
/// para un pedido de pastillas. El cliente ya tiene el nombre, la marca, la
/// categoría y la ficha, así que puede aplicarles **el mismo juicio** que la
/// lista de proveedores antes de destacar nada.
///
/// Lo que no pasa la compuerta **no se esconde**: baja al resto del catálogo,
/// que sigue accesible y paginado igual. Acá sólo se decide qué se presenta
/// como coincidencia.
Set<String> supplierCatalogHighlightedProductIds({
  required Iterable<SupplierCatalogItem> items,
  required SupplierNeedSearchPlan? plan,
}) {
  if (plan == null) {
    return <String>{
      for (final item in items)
        if (item.matchesNeed) item.productId,
    };
  }
  final candidates = <SupplierPortalCatalogCandidate>[
    for (final item in items)
      if (item.matchesNeed)
        SupplierPortalCatalogCandidate(
          code: item.productId,
          name: item.name,
          brand: item.brand,
          priceNet: item.catalogCostNet,
          rowText: <String?>[item.name, item.categoryPath]
              .whereType<String>()
              .join(' · '),
        ),
  ];
  if (candidates.isEmpty) return const <String>{};
  // **Destacar exige prueba, no ausencia de contradicción, y la prueba es la
  // misma que en la lista de proveedores.** Estas filas son de nuestro propio
  // catálogo y no pasaron por el lector con modelo, así que no traen el
  // sustantivo citado: una manguera o una oliva no contradicen la familia,
  // simplemente no la demuestran. Y demostrar la familia tampoco basta: una
  // pastilla `PARA FRENOS TEKTRO` la demuestra y contradice el sistema pedido,
  // y una que no dice nada de compatibilidad lo deja pendiente. Presentar
  // cualquiera de las dos como coincidencia es exactamente el error del
  // servidor. Bajan al resto del catálogo, que sigue accesible y paginado.
  //
  // No se usa `SupplierNeedMatchState.exact` porque ese estado exige criterios
  // vigentes: una necesidad sin ficha guardada no tendría nunca una
  // coincidencia, y el catálogo interno se quedaría sin destacados justo cuando
  // el nombre es toda la evidencia que hay. Lo que se exige es lo mismo por
  // partes: familia demostrada, nada contradicho y nada pendiente.
  return <String>{
    for (final match in matchSupplierNeedCandidates(plan, candidates))
      if (match.provenFields.contains('product_family') &&
          match.conflictingFields.isEmpty &&
          match.missingFields.isEmpty)
        match.candidate.code,
  };
}
