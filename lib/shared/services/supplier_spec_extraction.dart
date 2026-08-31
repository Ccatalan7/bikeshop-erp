/// Sacar la ficha técnica del texto que escribe **cualquier** proveedor.
///
/// **Por qué no más reglas.** Leer la válvula con expresiones regulares obliga
/// a enseñar cada catálogo a mano, y hasta que alguien lo enseña el proveedor
/// entra **mudo** — que en este dominio se leía como «cumple». En un solo día,
/// tres catálogos reales trajeron tres formas distintas de escribir lo mismo:
///
/// - RBX: `CAMARA 700 X 28/38C V/AUTO 48MM`
/// - Droppbike: `CAMARA 26X1.75 2.20 VAL. AUTO 48MM. BUTYL RITECH`
/// - Derman: `CAMARA ARO 700x35/38C A/V 48MM`
///
/// Y las trampas no son ortográficas: `V/DUNLOP` es un tercer tipo de válvula,
/// `AUTOMATICA` no es `V/AUTO`, y `CAMARA SCOOTER 8-1/2 X 2` no es una rueda
/// 700. Una lista de patrones nunca va a terminar de cubrirlas.
///
/// **Por qué se puede confiar en un modelo acá.** Porque no se le deja opinar.
/// El modelo sólo hace lo que hace bien —leer lenguaje— y devuelve, por cada
/// dato, **la porción del texto de donde lo sacó**. Después esta capa verifica,
/// sin red y sin modelo:
///
/// 1. la fila y el campo tienen que ser de los que se preguntaron;
/// 2. la cita tiene que **aparecer literalmente** en esa fila — si no, el dato
///    se descarta, y con eso una alucinación no puede entrar;
/// 3. el valor tiene que caer dentro del dominio del campo (sus valores
///    permitidos, o un número si el campo es numérico);
/// 4. dos lecturas distintas del mismo campo en la misma fila se anulan:
///    ambiguo no es lo mismo que desconocido;
/// 5. lo que no vuelve, **no consta**. La ausencia se conserva como ausencia,
///    nunca se rellena.
///
/// El veredicto —cumple, contradice, falta confirmar— lo sigue calculando el
/// código determinista de siempre sobre estos hechos. El modelo nunca dice
/// «cumple»: sólo dice «acá dice válvula americana, y lo dice en este pedazo».
/// Por eso un error suyo es visible al lado del nombre del producto, en vez de
/// ser un veredicto que nadie puede auditar.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'gemini_proxy_service.dart';
import 'supplier_need_portal_search.dart';

/// Una fila del proveedor tal como se le muestra al modelo.
class SupplierSpecExtractionRow {
  const SupplierSpecExtractionRow({required this.id, required this.text});

  /// El código del proveedor, o cualquier identidad estable de la fila.
  final String id;
  final String text;
}

/// Un dato leído, con el pedazo de texto que lo respalda.
/// La clave con que las **citas** viajan dentro de `technicalFacts`.
///
/// Guarda, por campo, la porción de texto que sostiene su valor — y sólo para
/// los valores que algún lector canónico pudo confirmar. Es evidencia positiva:
/// **lo que no tiene cita no está dicho**.
///
/// Una lista negativa de campos inferidos no bastaba: un recibo antiguo, que no
/// trae ninguna marca, se leía como si todo estuviera probado. Con las citas,
/// un recibo viejo no tiene ninguna y por lo tanto no prueba nada por omisión —
/// que es la respuesta correcta a «no sé qué sostenía esto».
///
/// Y sirven para revisar: el operador puede ver de dónde salió cada dato.
const String kSupplierFactQuotesFact = 'supplier_fact_quotes';

/// La marca explícita de que un campo lo **tradujo** el modelo sin respaldo.
///
/// Las citas son la evidencia positiva y bastan para juzgar; esta marca es la
/// declaración negativa correspondiente, y se respeta cuando viene: si alguien
/// dice «esto lo inferí», no hace falta volver a discutirlo.
const String kSupplierInferredFactsFact = 'supplier_inferred_facts';

/// Qué tan sostenido está un valor leído.
enum SupplierSpecEvidence {
  /// La cita lo dice: algún lector canónico lo reproduce desde ella.
  stated,

  /// El modelo lo tradujo de una escritura que ningún lector nuestro conoce.
  /// Se conserva —para eso está la IA— pero **no prueba**: un requisito no se
  /// da por cumplido con una traducción que nadie pudo verificar.
  inferred,
}

class SupplierSpecReading {
  const SupplierSpecReading({
    required this.field,
    required this.value,
    required this.quote,
    this.evidence = SupplierSpecEvidence.stated,
  });

  final String field;
  final Object value;

  /// Si la cita lo sostiene o el modelo lo tradujo.
  final SupplierSpecEvidence evidence;

  /// La porción del nombre del producto de donde salió. Es lo que se verifica
  /// y lo que se le puede mostrar al operador para que juzgue por sí mismo.
  final String quote;
}

/// El sustantivo con que el proveedor nombra la pieza de una fila.
const String kSupplierObjectHeadFact = 'supplier_object_head';

/// Si esa pieza es la que la necesidad está buscando.
const String kSupplierObjectIsRequestedFact = 'matches_requested_object';

/// Qué pieza nombra una fila, con el sustantivo que lo respalda.
///
/// **Reemplaza a la lista escrita a mano.** El calce sabía que `CAMARA` es una
/// cámara porque alguien lo escribió en la taxonomía canónica; no sabía que
/// `CUBETA` no es un motor de centro porque nadie lo había escrito todavía, y
/// esa lista no termina nunca. Acá el proveedor nombra la pieza y el modelo
/// sólo copia ese sustantivo y dice si es la buscada.
class SupplierObjectReading {
  const SupplierObjectReading({required this.head, required this.isRequested});

  /// El sustantivo del proveedor, verificado contra el texto de la fila.
  final String head;

  /// Si esa pieza es la que se está buscando.
  final bool isRequested;
}

/// Lo que sobrevivió a la verificación, por fila.
class SupplierSpecExtractionResult {
  const SupplierSpecExtractionResult({
    required this.readings,
    required this.rejected,
    this.objects = const <String, SupplierObjectReading>{},
  });

  /// `id de fila -> campo -> dato`.
  final Map<String, Map<String, SupplierSpecReading>> readings;

  /// `id de fila -> qué pieza nombra`, cuando el sustantivo pudo verificarse
  /// contra el texto. Es una LECTURA, no un veredicto de compra: dice «esto es
  /// una cubeta», nunca «esto sirve».
  final Map<String, SupplierObjectReading> objects;

  /// Por qué se descartó cada dato. Se cuenta y se registra: si esto crece,
  /// el problema es el contrato o el modelo, y hay que verlo, no ignorarlo.
  final List<String> rejected;

  Map<String, Object?> factsFor(String rowId) => <String, Object?>{
        for (final entry in (readings[rowId] ?? const {}).entries)
          entry.key: entry.value.value,
        // Viaja con la fila para que sobreviva al re-juicio y al guardado: la
        // pieza que el proveedor nombró es evidencia, igual que una medida.
        if (objects[rowId] case final object?) ...<String, Object?>{
          kSupplierObjectHeadFact: object.head,
          kSupplierObjectIsRequestedFact: object.isRequested,
        },
      };

  /// Los campos de esa fila que el modelo tradujo sin respaldo verificable.
  Set<String> inferredFieldsFor(String rowId) => <String>{
        for (final entry in (readings[rowId] ?? const {}).entries)
          if (entry.value.evidence == SupplierSpecEvidence.inferred) entry.key,
      };

  /// Las citas que sostienen cada valor **dicho** de esa fila.
  ///
  /// Un valor inferido no aparece: no hay cita que lo sostenga, y eso es
  /// exactamente lo que hay que poder distinguir después.
  Map<String, String> statedQuotesFor(String rowId) => <String, String>{
        for (final entry in (readings[rowId] ?? const {}).entries)
          if (entry.value.evidence == SupplierSpecEvidence.stated)
            entry.key: entry.value.quote,
      };
}

/// La instrucción que se le manda al modelo.
///
/// No enumera formas de escribir una válvula ni de escribir una medida: eso es
/// justo lo que no queremos mantener. Enumera **los campos y su dominio**, que
/// es lo que sí es nuestro, y exige la cita.
String buildSupplierSpecExtractionPrompt({
  required List<SupplierNeedSearchField> fields,
  required List<SupplierSpecExtractionRow> rows,
  String requestedObject = '',
}) {
  final fieldLines = <Map<String, Object?>>[
    for (final field in fields)
      <String, Object?>{
        'key': field.key,
        'label': field.label,
        'type': field.dataType,
        if (field.unit != null && field.unit!.trim().isNotEmpty)
          'unit': field.unit,
        if (field.allowedValues.isNotEmpty)
          'allowed_values': field.allowedValues,
      },
  ];
  final rowLines = <Map<String, Object?>>[
    for (final row in rows) <String, Object?>{'id': row.id, 'text': row.text},
  ];

  return '''
Eres un lector de catálogos de repuestos de bicicleta. Tu única tarea es LEER
lo que el proveedor escribió. No decides si un producto sirve.

Por cada fila responde dos cosas:

1. `object`: QUÉ PIEZA nombra la fila. `head` es el sustantivo con que el
   proveedor la nombra, copiado EXACTO del texto; `is_requested` es si esa
   pieza es la misma que se está buscando. Una pieza que se monta junto a la
   buscada, o que la contiene, NO es la buscada.
2. `facts`: los campos pedidos que el texto declare.

Para cada campo pedido, responde SOLO si el texto de esa fila lo dice. Reglas:

- `quote` debe ser una porción EXACTA del texto de esa fila, copiada tal cual.
  Si no puedes copiar el pedazo, no incluyas el dato.
- Si el campo trae `allowed_values`, `value` debe ser uno de ellos.
- Si el texto no dice el dato, NO lo incluyas. Omitir es la respuesta correcta;
  inventar o suponer es un error grave.
- No uses tu conocimiento del producto ni de la marca: sólo este texto.
- Un dato que aparece como parte de otra palabra no cuenta.

Pieza buscada: {{PIEZA}}

Campos pedidos:
${const JsonEncoder.withIndent('  ').convert(fieldLines)}

Filas:
${const JsonEncoder.withIndent('  ').convert(rowLines)}

Responde SOLO este JSON, sin texto alrededor:
{"rows":[{"id":"<id>","object":{"head":"<sustantivo copiado exacto>","is_requested":true|false},"facts":[{"field":"<key>","value":<valor>,"quote":"<porción exacta>"}]}]}
'''
      .replaceFirst(
          '{{PIEZA}}',
          requestedObject.trim().isEmpty
              ? 'la que describe la necesidad'
              : requestedObject.trim());
}

String _normalize(String value) => ProductIdentityExtractor.normalize(value)
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double? _number(Object? raw) {
  if (raw is num) return raw.toDouble();
  final text = raw?.toString().trim().replaceAll(',', '.');
  if (text == null || text.isEmpty) return null;
  return double.tryParse(text);
}

bool _isNumericField(SupplierNeedSearchField field) {
  final type = field.dataType.toLowerCase();
  return type == 'number' || type == 'integer' || type == 'decimal';
}

/// Verifica la respuesta del modelo contra el texto real. Función pura.
///
/// Todo lo que no se puede comprobar se cae. Este es el único lugar donde se
/// decide si un dato del modelo entra al dominio, y no llama a nadie.
SupplierSpecExtractionResult verifySupplierSpecExtraction({
  required List<SupplierNeedSearchField> fields,
  required List<SupplierSpecExtractionRow> rows,
  required Object? response,
}) {
  final rejected = <String>[];
  final byId = <String, String>{
    for (final row in rows) row.id: _normalize(row.text),
  };
  final fieldsByKey = <String, SupplierNeedSearchField>{
    for (final field in fields) field.key: field,
  };

  Object? decoded = response;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      rejected.add('respuesta ilegible');
      return SupplierSpecExtractionResult(
        readings: const <String, Map<String, SupplierSpecReading>>{},
        rejected: rejected,
      );
    }
  }
  if (decoded is! Map) {
    rejected.add('respuesta sin filas');
    return SupplierSpecExtractionResult(
      readings: const <String, Map<String, SupplierSpecReading>>{},
      rejected: rejected,
    );
  }

  final readings = <String, Map<String, SupplierSpecReading>>{};
  final objects = <String, SupplierObjectReading>{};
  final ambiguous = <String>{};

  for (final rawRow in (decoded['rows'] as List? ?? const <Object?>[])) {
    if (rawRow is! Map) continue;
    final rowId = rawRow['id']?.toString().trim() ?? '';
    final haystack = byId[rowId];
    if (haystack == null) {
      rejected.add('fila desconocida: $rowId');
      continue;
    }

    // **El sustantivo también se verifica contra el texto.** Sin esto, el
    // modelo podría decir «esto es un motor de centro» de cualquier fila y no
    // habría cómo desmentirlo. Copiando del texto, el operador ve por qué.
    final rawObject = rawRow['object'];
    if (rawObject is Map) {
      final head = rawObject['head']?.toString().trim() ?? '';
      final normalizedHead = _normalize(head);
      final isRequested = rawObject['is_requested'];
      if (normalizedHead.isEmpty || !haystack.contains(normalizedHead)) {
        rejected.add('$rowId/objeto: «$head» no está en la fila');
      } else if (isRequested is! bool) {
        rejected.add('$rowId/objeto: no dice si es la pieza buscada');
      } else {
        objects[rowId] =
            SupplierObjectReading(head: head, isRequested: isRequested);
      }
    }

    for (final rawFact in (rawRow['facts'] as List? ?? const <Object?>[])) {
      if (rawFact is! Map) continue;
      final key = rawFact['field']?.toString().trim() ?? '';
      final field = fieldsByKey[key];
      if (field == null) {
        rejected.add('$rowId: campo no pedido «$key»');
        continue;
      }
      final marker = '$rowId/$key';
      if (ambiguous.contains(marker)) continue;

      // (2) La cita tiene que estar en el texto. Sin esto, nada impide que el
      // modelo complete la ficha con lo que le parece razonable.
      final quote = rawFact['quote']?.toString() ?? '';
      final normalizedQuote = _normalize(quote);
      if (normalizedQuote.isEmpty || !haystack.contains(normalizedQuote)) {
        rejected.add('$marker: la cita no está en la fila');
        continue;
      }

      // (3) El valor tiene que caer en el dominio del campo.
      final rawValue = rawFact['value'];
      Object? value;
      if (field.allowedValues.isNotEmpty) {
        final wanted = _normalize(rawValue?.toString() ?? '');
        for (final allowed in field.allowedValues) {
          if (_normalize(allowed.toString()) == wanted) {
            value = allowed;
            break;
          }
        }
        if (value == null) {
          rejected.add('$marker: «$rawValue» no es un valor permitido');
          continue;
        }
      } else if (_isNumericField(field)) {
        value = _number(rawValue);
        if (value == null) {
          rejected.add('$marker: «$rawValue» no es un número');
          continue;
        }
      } else if (field.dataType.trim().toLowerCase() == 'boolean') {
        // **Un booleano se guarda como booleano.** Caía en la rama de texto
        // libre y `true` viajaba como la cadena «true», así que la
        // comprobación de que la cita lo sostuviera comparaba una cadena con
        // un booleano y siempre daba por buena la afirmación: `aletas = true`
        // citando `SIN ALETAS DE CALOR` entraba entera.
        final crudo = _normalize(rawValue?.toString() ?? '');
        if (crudo == 'true' || crudo == 'si' || crudo == 'yes') {
          value = true;
        } else if (crudo == 'false' || crudo == 'no') {
          value = false;
        } else {
          rejected.add('$marker: «$rawValue» no es un sí o un no');
          continue;
        }
      } else {
        final text = rawValue?.toString().trim() ?? '';
        if (text.isEmpty) {
          rejected.add('$marker: valor vacío');
          continue;
        }
        value = text;
      }

      // (3.b) **La cita tiene que SOSTENER el valor, no sólo existir.** Que
      // exista y que el valor caiga en el enum eran dos comprobaciones
      // independientes, y entre las dos cabía cualquier afirmación: el recibo
      // real de RBX guardó `brake_type = Disco Hidráulico` citando `FRENO
      // DISCO`, que no lo dice; `80 mm` citando `48 MM`; y `aletas = true`
      // citando `SIN ALETAS DE CALOR`, que dice lo contrario.
      //
      // La regla estructural es una sola: **se relee la cita con el mismo
      // lector determinista** y tiene que devolver ese valor. Si el lector
      // puede leer ese campo y no lo encuentra ahí, la afirmación no está
      // sostenida — da igual cómo esté redactada la frase.
      // **Contradicho se rechaza; no reconocido se marca.** Si algún lector
      // canónico lee OTRO valor en la cita, la afirmación es falsa y se cae.
      // Si ninguno la reconoce, el modelo puede estar traduciendo una
      // escritura que no sabemos leer —`TIPO FRANCES` por `presta`—: se
      // conserva con su cita, pero como **inferida**, y una inferida no
      // prueba ningún requisito.
      final soporte = supplierQuoteEvidence(
        field: field,
        value: value,
        quote: quote,
        rowText: haystack,
      );
      if (soporte == null) {
        rejected.add('$marker: la cita dice otra cosa que «$rawValue»');
        continue;
      }

      // (4) Dos lecturas distintas del mismo campo se anulan.
      final existing = readings[rowId]?[key];
      if (existing != null) {
        if (_normalize(existing.value.toString()) !=
            _normalize(value.toString())) {
          readings[rowId]!.remove(key);
          ambiguous.add(marker);
          rejected.add('$marker: dos lecturas que se contradicen');
        }
        continue;
      }

      (readings[rowId] ??= <String, SupplierSpecReading>{})[key] =
          SupplierSpecReading(
        field: key,
        value: value,
        quote: quote.trim(),
        evidence: soporte,
      );
    }
  }

  return SupplierSpecExtractionResult(
    readings: readings,
    objects: objects,
    rejected: List<String>.unmodifiable(rejected),
  );
}

/// Quien le pregunta al modelo. Se inyecta para que el circuito se pueda
/// probar sin red y para que un proveedor de IA caído no rompa la búsqueda.
typedef SupplierSpecExtractor = Future<Object?> Function(String prompt);

/// Le pone a cada fila la ficha que el modelo leyó de su propio texto.
///
/// **Reemplaza a las reglas, no las contradice.** Los hechos verificados se
/// escriben en `technicalFacts` del candidato, que es lo primero que mira el
/// calce; los lectores por expresión regular quedan detrás, para lo que el
/// modelo no alcanzó a leer y para cuando no hay modelo. Si la llamada falla
/// —cuota, red, respuesta ilegible— se devuelven las filas intactas: el
/// buscador nunca se cae por esto, sólo lee menos.
Future<List<SupplierPortalCatalogCandidate>> readSupplierSpecsWithModel({
  required List<SupplierNeedSearchField> fields,
  required List<SupplierPortalCatalogCandidate> candidates,
  required SupplierSpecExtractor extractor,

  /// Cómo describe la necesidad la pieza que busca. Es lo único que el modelo
  /// necesita para decir si una fila nombra esa pieza u otra.
  String requestedObject = '',
  void Function(List<String> rejected)? onRejected,

  /// **Un modelo lento es lo mismo que un modelo caído.** Atrapar la excepción
  /// no basta: con el Edge Runtime degradado la llamada no falla, se demora —y
  /// con reintentos deja la búsqueda entera colgada con «Buscando…» en
  /// pantalla y el portal ya recorrido. Medido el 2026-08-30: la enumeración
  /// terminó y el operador siguió esperando minutos por una lectura opcional.
  Duration deadline = const Duration(seconds: 25),
  SupplierModelReadOwner? owner,
}) async {
  if (fields.isEmpty || candidates.isEmpty) return candidates;
  if (owner?.isClosed ?? false) return candidates;

  final rows = <SupplierSpecExtractionRow>[
    for (final candidate in candidates)
      if (candidate.code.trim().isNotEmpty)
        SupplierSpecExtractionRow(
          id: candidate.code.trim(),
          text: <String?>[candidate.name, candidate.rowText]
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .join(' · '),
        ),
  ];
  if (rows.isEmpty) return candidates;

  final reloj = Stopwatch()..start();
  debugPrint('🧠 lectura de fichas: ${rows.length} filas, '
      '${fields.length} campos — llamando al modelo');
  final prompt = buildSupplierSpecExtractionPrompt(
    fields: fields,
    rows: rows,
    requestedObject: requestedObject,
  );

  // **Las mismas filas no se leen dos veces.** El buscador prueba varios
  // términos contra el mismo nodo del catálogo y cada intento devuelve las
  // MISMAS filas; sin esto, cada intento pagaba una llamada completa —medido
  // el 2026-08-30: dos lotes idénticos de 9 filas, 20 s cada uno, y la
  // búsqueda parecía colgada—. La llave es el texto exacto que se preguntó,
  // así que un catálogo que cambia produce otra llave y se vuelve a leer.
  // **La llave es lo que se preguntó, no cómo quedó redactado.** Usar el texto
  // del prompt hacía fallar el reuso cuando las mismas filas llegaban en otro
  // orden —que es justo lo que pasa al probar un término distinto contra el
  // mismo nodo—. Se ordena por código para que dos lotes iguales colapsen.
  final key = _readingKey(fields, rows, requestedObject);
  final cached = _readingsCache[key];
  if (cached != null) {
    debugPrint('🧠 lectura de fichas: ${rows.length} filas ya leídas, '
        'se reusa la lectura');
    return _merge(candidates, cached);
  }

  Object? response;
  try {
    response = await _conPlazo(extractor(prompt), deadline, owner);
  } catch (error) {
    // Sin modelo —caído, sin cuota o simplemente lento— se sigue con lo que el
    // calce sepa leer solo. La lectura es una mejora, nunca un requisito.
    debugPrint('🧠 lectura de fichas: sin modelo tras '
        '${reloj.elapsedMilliseconds} ms ($error)');
    return candidates;
  }
  debugPrint('🧠 lectura de fichas: el modelo respondió en '
      '${reloj.elapsedMilliseconds} ms');

  final result = verifySupplierSpecExtraction(
    fields: fields,
    rows: rows,
    response: response,
  );
  if (result.rejected.isNotEmpty) onRejected?.call(result.rejected);
  if (result.readings.isEmpty) return candidates;

  if (_readingsCache.length >= _readingsCacheMax) _readingsCache.clear();
  _readingsCache[key] = result;
  return _merge(candidates, result);
}

String _readingKey(
  List<SupplierNeedSearchField> fields,
  List<SupplierSpecExtractionRow> rows,
  String requestedObject,
) {
  final campos = fields.map((field) => field.key).toList()..sort();
  // La pieza buscada es parte de la pregunta: cambiarla cambia la respuesta.
  final filas = rows.map((row) => '${row.id}\u0000${row.text}').toList()
    ..sort();
  return '$requestedObject\u0003${campos.join('|')}'
      '\u0001${filas.join('\u0002')}';
}

/// Lecturas ya hechas en esta corrida, por el conjunto exacto de filas.
final Map<String, SupplierSpecExtractionResult> _readingsCache =
    <String, SupplierSpecExtractionResult>{};
const int _readingsCacheMax = 32;

/// Vacía las lecturas memoizadas. Una prueba que comparte proceso con otra
/// tiene que empezar sin lecturas de la anterior, o se prueba la caché en vez
/// del lector.
@visibleForTesting
void resetSupplierSpecReadingsCache() => _readingsCache.clear();

List<SupplierPortalCatalogCandidate> _merge(
  List<SupplierPortalCatalogCandidate> candidates,
  SupplierSpecExtractionResult result,
) =>
    <SupplierPortalCatalogCandidate>[
      for (final candidate in candidates)
        if (result.readings.containsKey(candidate.code.trim()))
          SupplierPortalCatalogCandidate(
            code: candidate.code,
            name: candidate.name,
            brand: candidate.brand,
            origin: candidate.origin,
            priceNet: candidate.priceNet,
            rowText: candidate.rowText,
            technicalFacts: <String, Object?>{
              ...candidate.technicalFacts,
              ...result.factsFor(candidate.code.trim()),
              // **La procedencia viaja con el hecho.** Va dentro de
              // `technicalFacts`, que es lo que el recibo persiste, así que un
              // recibo rejuzgado meses después sigue sabiendo qué estaba dicho
              // y qué tradujo el modelo. Sin esto, al guardar los escalares se
              // perdía la cita y todo pesaba lo mismo.
              kSupplierFactQuotesFact:
                  result.statedQuotesFor(candidate.code.trim()),
              kSupplierInferredFactsFact:
                  result.inferredFieldsFor(candidate.code.trim()).toList(),
            },
          )
        else
          candidate,
    ];

/// El lector real: una sola llamada al modelo por búsqueda.
///
/// **Una pregunta por lote, no una por fila.** Treinta y cinco filas son una
/// sola pregunta; preguntarlas de a una multiplica el costo y la latencia por
/// treinta y cinco sin leer nada mejor.
///
/// Se pide el modelo más barato que sabe leer texto: acá no hay razonamiento,
/// sólo lectura. Y se le exige JSON, porque la respuesta la consume código.
/// Si contesta cualquier otra cosa, la compuerta la descarta entera y la
/// búsqueda sigue con lo que sepa leer sola.
SupplierSpecExtractor geminiSupplierSpecExtractor({
  GeminiProxyService? service,
  // **El modelo liviano alcanza y de sobra.** Acá no hay razonamiento: hay que
  // copiar un pedazo de texto y elegir de una lista cerrada. Medido el
  // 2026-08-30 contra el catálogo real de RBX, el modelo grande tardó 21,7 s y
  // 20,5 s en dos lotes de 9 filas — con eso una búsqueda se siente colgada, y
  // el plazo de 25 s queda a nada de vencer con lotes más grandes.
  String model = 'gemini-2.5-flash-lite',
}) {
  final proxy = service ?? GeminiProxyService();
  return (prompt) async {
    final text = await proxy.generateText(prompt: prompt, model: model);
    // El modelo suele envolver el JSON en un bloque de código.
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    return fence != null ? fence.group(1) : text;
  };
}

/// Si esa cita **sostiene** ese valor para ese campo.
///
/// No es una comprobación de forma: es releer la cita con el mismo lector
/// determinista que juzga cualquier texto y exigir que devuelva el valor.
/// Cuando el lector **puede** leer el campo —lista de valores, número o
/// booleano— y no encuentra el valor en la cita, la afirmación no está
/// sostenida. Cuando no puede leerlo —texto libre, sin vocabulario que
/// reconocer— no hay nada que contrastar y la cita se acepta como está: lo que
/// no se puede verificar no se declara verificado, pero tampoco se inventa un
/// rechazo.
SupplierSpecEvidence? supplierQuoteEvidence({
  required SupplierNeedSearchField field,
  required Object value,
  required String quote,

  /// El texto completo de la fila. **Una cita tiene que apuntar donde está el
  /// dato**: si alguna palabra del valor está en la fila y no en la cita, el
  /// modelo citó otro pedazo —`Disco Hidráulico` citando `PASTILLA` cuando la
  /// fila dice `DISCO` cinco letras más allá—. Eso no es traducir: es señalar
  /// mal.
  String rowText = '',
}) {
  final text = _normalize(quote);
  if (text.isEmpty) return null;

  if (field.dataType.trim().toLowerCase() == 'boolean') {
    final leido = supplierBooleanFromFieldVocabulary(
      text: text,
      label: field.label,
      description: field.description,
    );
    // Sin vocabulario propio el campo no se puede contrastar; con vocabulario,
    // la cita tiene que decir lo mismo.
    if (leido == null) return SupplierSpecEvidence.inferred;
    return leido == (value == true) ? SupplierSpecEvidence.stated : null;
  }

  if (field.allowedValues.isNotEmpty) {
    final wanted = _normalize(value.toString());
    if (wanted.isEmpty) return null;
    if (' $text '.contains(' $wanted ')) return SupplierSpecEvidence.stated;
    // **Los lectores canónicos también sostienen.** `V/AUTO` no dice
    // «Schrader (americana / auto)» con esas letras y sí lo declara.
    final valvula = supplierValveTypeFromText(text);
    if (valvula != null) {
      return wanted.contains(_normalize(valvula))
          ? SupplierSpecEvidence.stated
          : null;
    }
    // **Ninguna palabra en común tampoco demuestra nada.** Se creyó que sin
    // solape el modelo estaba traduciendo una escritura que no conocemos
    // —`V/FRANC.` por `presta`—, y eso también aceptaba `Disco Hidráulico`
    // citando `PASTILLA`, que no tiene relación alguna. Las traducciones
    // legítimas las cubren los lectores canónicos; lo que ninguno reconoce se
    // conserva como inferido, salvo que la cita traiga **parte** del valor:
    // `FRENO DISCO` tiene una de las dos palabras de `Disco Hidráulico` y no
    // dice cuál disco es. Eso no es traducir, es precisar sin respaldo.
    final palabras = wanted.split(' ').where((w) => w.length > 2).toSet();
    final enLaCita = palabras.where((w) => _containsWordIn(text, w)).toSet();
    if (enLaCita.isNotEmpty && enLaCita.length < palabras.length) return null;
    final fila = _normalize(rowText);
    final enLaFila = palabras.where((w) => _containsWordIn(fila, w)).toSet();
    if (enLaCita.isEmpty && enLaFila.isNotEmpty) return null;
    return SupplierSpecEvidence.inferred;
  }

  if (_isNumericField(field)) {
    final numero = _number(value);
    if (numero == null) return null;
    // Una medida escrita como fracción —`8-1/2`— sostiene su valor decimal.
    if (supplierFractionalWheelSizeFromText(quote) == numero) {
      return SupplierSpecEvidence.stated;
    }
    if (supplierWheelSizeFromText(text) == numero) {
      return SupplierSpecEvidence.stated;
    }
    final escrito = numero == numero.roundToDouble()
        ? numero.toStringAsFixed(0)
        : numero.toString();
    return RegExp('(?:^|[^0-9.,])${RegExp.escape(escrito)}(?:[^0-9]|\$)')
            .hasMatch(text)
        ? SupplierSpecEvidence.stated
        : null;
  }

  // Texto libre: no hay lector que contraste, así que se conserva pero no
  // prueba.
  return SupplierSpecEvidence.inferred;
}

bool _containsWordIn(String text, String word) =>
    RegExp('(?:^|[^a-z0-9])${RegExp.escape(word)}(?:[^a-z0-9]|\$)')
        .hasMatch(text);

/// Si ese texto declara —o niega— el booleano que la ficha nombra.
///
/// Vive acá, en la capa baja, porque lo usan **las dos orillas**: el
/// verificador de la lectura con IA y el lector determinista del calce. Dos
/// copias serían dos verdades sobre la misma palabra.
bool? supplierBooleanFromFieldVocabulary({
  required String text,
  required String label,
  String? description,
  List<String> familyHeads = const <String>[],
}) {
  final vocabulario = _booleanFieldVocabulary(label, description, familyHeads);
  if (vocabulario.isEmpty) return null;
  final tokens = _normalize(text).split(' ');
  final ordenado = vocabulario.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final vistos = <bool>{};
  for (final termino in ordenado) {
    final partes = termino.split(' ');
    for (var index = 0; index + partes.length <= tokens.length; index += 1) {
      var calza = true;
      for (var offset = 0; offset < partes.length; offset += 1) {
        if (tokens[index + offset] != partes[offset]) {
          calza = false;
          break;
        }
      }
      if (!calza) continue;
      var negado = false;
      for (var atras = 1; atras <= 2; atras += 1) {
        final previo = index - atras;
        if (previo < 0) break;
        final palabra = tokens[previo];
        if (palabra == 'sin' || palabra == 'no' || palabra == 'nunca') {
          negado = true;
          break;
        }
      }
      vistos.add(!negado);
    }
  }
  return vistos.length == 1 ? vistos.single : null;
}

Set<String> _booleanFieldVocabulary(
  String label,
  String? description,
  List<String> familyHeads,
) {
  const auxiliares = <String>{
    'trae',
    'tiene',
    'incluye',
    'indica',
    'si',
    'el',
    'la',
    'los',
    'las',
    'de',
    'del',
    'con',
    'sin',
    'por',
    'para',
    'y',
    'o',
    'un',
    'una',
    'es',
    'viene',
    'declarado',
    'esta',
  };
  final heads = <String>{for (final head in familyHeads) _normalize(head)};
  final terminos = <String>{};

  void addPhrase(String raw) {
    final palabras = _normalize(raw)
        .split(' ')
        .where((word) =>
            word.isNotEmpty &&
            !auxiliares.contains(word) &&
            !heads.contains(word))
        .toList(growable: false);
    if (palabras.isEmpty) return;
    if (palabras.length == 1 && palabras.single.length < 6) return;
    terminos.add(palabras.join(' '));
    for (final palabra in palabras) {
      if (palabra.length >= 6) terminos.add(palabra);
    }
  }

  addPhrase(label);
  final texto = description?.trim() ?? '';
  final corte = texto.indexOf(':');
  if (corte > 0) {
    final cabeza = texto.substring(0, corte);
    if (!_normalize(cabeza).startsWith('indica')) {
      for (final sinonimo in cabeza.split(RegExp(r'\s+o\s+|,'))) {
        if (sinonimo.trim().isNotEmpty) addPhrase(sinonimo);
      }
    }
  }
  return terminos;
}

// ---------------------------------------------------------------------------
// Lectores canónicos de valor, en la capa que los usan las DOS orillas.
//
// Estaban arriba, en el calce, y el verificador de la lectura con IA no podía
// alcanzarlos: por eso «la cita tiene que sostener el valor» rechazaba
// `V/AUTO` como prueba de `schrader`, que sí lo sostiene. Bajarlos deja un
// solo dueño de cada lectura.
// ---------------------------------------------------------------------------

/// El tamaño de rueda tal como lo escribe un catálogo, o nada.
///
/// Se acepta sólo en contexto dimensional —`700x28`, `26x1.75`, `700c`, `29"`—
/// porque un número suelto no es una medida: en `CAMARA 700X28/38C V/AUTO
/// 48MM` el 48 es el largo de la válvula, y tomarlo por un tamaño inventaría
/// la ficha. Si aparecen dos tamaños distintos se devuelve nada: ambiguo no
/// es lo mismo que desconocido, pero ninguno de los dos se adivina.
double? supplierWheelSizeFromText(String text) {
  final found = supplierWheelSizesFromText(text);
  return found.length == 1 ? found.single : null;
}

/// Todas las medidas que el texto declara con contexto dimensional.
///
/// Se expone el conjunto, no sólo el resultado, porque **cuántas hay es una
/// evidencia por sí misma**: una fila que nombra dos —`CAMARA 700X28C Y
/// 26X1.75 SURTIDO`— no afirma ninguna, y quien lea por otra vía tiene que
/// saberlo en vez de quedarse con la primera.
Set<double> supplierWheelSizesFromText(String text) {
  final found = <double>{};
  const expressions = <String>[
    // `700x28`, `650x23`: tamaños de tres dígitos pegados al ancho.
    r'(?:^|[^0-9.,])(\d{3})\s*[x×]\s*\d',
    // `26x1.75`, `27.5x2.35`, `29x2.10`: pulgadas pegadas al ancho.
    r'(?:^|[^0-9.,])(\d{2}(?:[.,]\d)?)\s*[x×]\s*\d',
    // `700c` con su marca de rueda explícita.
    r'(?:^|[^0-9.,])(\d{3})\s*c(?:[^a-z0-9]|$)',
    // `29"`, `27.5"`.
    r'(?:^|[^0-9.,])(\d{2}(?:[.,]\d)?)\s*"',
    // `aro 700`, `rodado 26`, `rin 29`: el marcador con que se escribe acá.
    //
    // **Es una lectura por marcador, no un número suelto.** Un `700` a secas
    // puede ser un precio, un código o una cantidad, y por eso el resto de las
    // expresiones exige contexto dimensional. Pero «aro» nombra el tamaño de
    // rueda tan explícitamente como `V/` nombra la válvula, y sin esta línea la
    // necesidad real «Cámaras aro 700 para reposición del taller» no declaraba
    // su medida: la ficha abría muda y el feed se rejuzgaba como «cualquier
    // cámara».
    r'(?:^|[^a-z0-9])(?:aro|rodado|rin)\s*(\d{2,3}(?:[.,]\d)?)(?:[^0-9.,]|\$)',
  ];
  for (final expression in expressions) {
    for (final match in RegExp(expression).allMatches(text)) {
      final value = _number(match.group(1));
      if (value == null) continue;
      // **Un diámetro ETRTO no es un aro: es el MISMO aro escrito en
      // milímetros.** Una llanta real de esta tienda —`LLANTA 29 DP-30 NEGRA TR
      // 622X30MM. 32H.`— entregaba `622` con la forma de una medida francesa.
      // Como `622` no existe en ninguna ficha, contradecía `29"` y la llanta
      // correcta quedaba fuera del listado: una exclusión falsa, que es peor
      // que no saber.
      //
      // No se traduce a `29"` ni a `700c` porque **622 es los dos** —la misma
      // llanta con dos nombres— y elegir uno sería inventar. Queda sin dato, y
      // la fila se revisa. Lo que sí conserva su contradicción es una medida
      // ajena de tres dígitos, como el `350 X 8` de una cámara de carretilla.
      if (_etrtoBicycleDiameters.contains(value)) continue;
      found.add(value);
    }
  }
  return found;
}

/// Los diámetros ETRTO que usan las bicicletas, en milímetros.
///
/// Es la lista cerrada del estándar, no una heurística: 622 es 700c y 29",
/// 584 es 650b y 27.5", 559 es 26". Están acá para **no** confundirlos con una
/// medida francesa de tres dígitos.
final Set<double> _etrtoBicycleDiameters = <double>{
  622, // 700c · 29"
  635, // 28 × 1½
  630, // 27"
  584, // 650b · 27.5"
  571, // 650c
  559, // 26"
  547, // 24 × 1⅜
  540, // 24"
  507, // 24 × 1.75
  451, // 20" ISO 451
  406, // 20"
  349, // 16" Brompton
  305, // 16"
  203, // 12"
};

/// Una rueda escrita como fracción de pulgada —`8-1/2 X 2`, `12 1/2 X 2 1/4`—
/// leída del texto **crudo**, porque el normalizador borra `/` y `-`.
///
/// Se exige el contexto dimensional completo (`… x <número>`) para no leer
/// `(28-5/8-1/4)`, la equivalencia en pulgadas que casi toda cámara 700 lleva
/// al final del nombre y que no es el tamaño de la rueda.
double? supplierFractionalWheelSizeFromText(String text) {
  final found = <double>{};
  final expression =
      RegExp(r'(?:^|[^0-9./-])(\d{1,2})[\s-](\d)/(\d)\s*[xX×]\s*\d');
  for (final match in expression.allMatches(text)) {
    final whole = _number(match.group(1));
    final numerator = _number(match.group(2));
    final denominator = _number(match.group(3));
    if (whole == null || numerator == null || denominator == null) continue;
    if (denominator == 0) continue;
    found.add(whole + numerator / denominator);
  }
  return found.length == 1 ? found.single : null;
}

/// El tipo de válvula tal como lo marca el catálogo, o nada.
///
/// Sólo cuenta la palabra que sigue al marcador de válvula, ya sin la barra ni
/// el punto que borra el normalizador. Cada proveedor lo escribe distinto y
/// **todas las formas salen de catálogos reales**, no de una lista inventada:
///
/// - RBX: `V/AUTO`, `V/FRANCESA`, `V/DUNLOP`, `V/FRANC.`, `VALVULA SCHRADE`
/// - Droppbike: `VAL. AUTO`, `VAL. FRANCESA` — el punto llega como `~`
/// - Derman: `F/V`, `A/V` — la abreviatura sola, sin palabra que la siga
///
/// Dos marcadores que se contradicen devuelven nada: ambiguo no es lo mismo
/// que desconocido, y ninguno de los dos se adivina.
String? supplierValveTypeFromText(String text) {
  final found = <String>{};
  for (final match in RegExp(r'\b(?:v|val|valv|valvula|valve)[\s~]+([a-z]+)')
      .allMatches(text)) {
    final canonical = _valveMarkerWord(match.group(1)!);
    if (canonical != null) found.add(canonical);
  }
  // `F/V` y `A/V` no llevan palabra detrás: la abreviatura ES el tipo. El
  // normalizador les borra la barra, así que llegan como dos letras sueltas.
  if (RegExp(r'\bf\s*v\b').hasMatch(text)) found.add('presta');
  if (RegExp(r'\ba\s*v\b').hasMatch(text)) found.add('schrader');
  return found.length == 1 ? found.single : null;
}

String? _valveMarkerWord(String word) {
  if (word.startsWith('presta') || word.startsWith('franc')) return 'presta';
  if (word.startsWith('schrad') ||
      word.startsWith('american') ||
      word == 'auto') {
    return 'schrader';
  }
  if (word.startsWith('dunlop') || word.startsWith('wood')) return 'dunlop';
  return null;
}

/// Palabras distintas que nombran **el mismo valor** de una ficha.
///
/// **Una normalización compartida, no un diccionario del buscador.** La ficha
/// de pastillas rotula el compuesto por su química —`Orgánico`—; el taller y
/// medio catálogo lo nombran por su aglutinante —«de resina»—. Sin una
/// equivalencia canónica, las dos orillas quedan ciegas a la vez: una petición
/// que dice «resina» no reconoce el criterio que ya la representa, y una fila
/// que titula `PASTILLA DE RESINA` no demuestra su propio compuesto.
///
/// Es equivalencia de **valor**, no de familia ni de identidad: nunca decide
/// qué pieza es una fila. La ficha sigue siendo la dueña de qué valores
/// existen; esto sólo dice cuáles palabras nombran a cada uno.
const Map<String, Set<String>> kSupplierSpecValueSynonyms = <String, Set<String>>{
  // Compuesto de fricción de una pastilla o zapata.
  'compuesto:organico': <String>{
    'organico', 'organica', 'organicos', 'organicas', 'organic',
    'resina', 'resinas', 'resin',
  },
  'compuesto:metalico': <String>{
    'metalico', 'metalica', 'metalicos', 'metalicas', 'metallic',
    'sinterizado', 'sinterizada', 'sinterizados', 'sinterizadas', 'sintered',
  },
  'compuesto:semimetalico': <String>{
    'semimetalico', 'semimetalica', 'semimetallic',
  },
  // Material de construcción, con las mismas palabras que ya reconoce el
  // lector de identidad canónico.
  'material:aluminio': <String>{
    'aluminio', 'aluminum', 'aluminium', 'alu',
  },
  'material:acero': <String>{'acero', 'steel'},
  'material:carbono': <String>{'carbono', 'carbon'},
  'material:plastico': <String>{
    'plastico', 'plastica', 'plastic', 'policarbonato', 'polycarbonate',
  },
};

final Map<String, String> _supplierSpecValueConcepts = <String, String>{
  for (final entry in kSupplierSpecValueSynonyms.entries)
    for (final word in entry.value) word: entry.key,
};

/// El concepto canónico que nombra esa palabra, si el dominio conoce alguno.
///
/// Devuelve `null` cuando la palabra no pertenece a ninguna equivalencia
/// conocida: entonces se compara como texto, que es lo que se hacía siempre.
String? canonicalSupplierSpecConcept(String word) =>
    _supplierSpecValueConcepts[word.trim().toLowerCase()];

/// Dónde, en la petición, está escrito cada criterio vigente.
///
/// **El problema que resuelve.** Los criterios salen de la misma petición, pero
/// al guardarlos se pierde con qué palabras los escribió el operador: queda
/// `Compuesto = Orgánico` y nadie sabe que eso se pidió como «de resina». El
/// eje de requisitos no expresados vuelve entonces a exigir la palabra literal
/// y cuenta dos veces el mismo requisito, dejando pendiente una fila que
/// demostró todo lo que se le pidió.
///
/// **Por qué no basta con una lista de sinónimos.** Una lista sólo sabe las
/// palabras que alguien alcanzó a escribir, y el objetivo es entender
/// peticiones nuevas. El lector que ya existe —el mismo que lee la fila de un
/// proveedor— sabe leer un texto contra los campos de una ficha; lo único que
/// faltaba era pedírselo también para la petición.
@immutable
class SupplyNeedCriteriaSpans {
  const SupplyNeedCriteriaSpans({required this.spans, required this.rejected});

  /// Los tramos verificados, tal como aparecen en la petición.
  final List<String> spans;

  /// Lo que el modelo afirmó y no se pudo sostener. Se conserva para poder
  /// mirarlo: una lectura descartada en silencio no se puede diagnosticar.
  final List<String> rejected;
}

/// Verifica lo que el modelo dijo sobre la petición.
///
/// **Una cita literal y un valor permitido no prueban una relación.** Que
/// «de resina» esté en el texto y que `Orgánico` sea un valor de la ficha no
/// dice que lo uno signifique lo otro; el modelo pudo asociarlos mal, y una
/// asociación equivocada haría desaparecer un requisito real. Por eso se exigen
/// **tres** cosas, y la tercera es la que convierte la coincidencia en relación:
///
/// 1. **El tramo existe en la petición**, comparado sobre el texto normalizado.
///    Es la barrera contra una cita inventada.
/// 2. **El campo tiene un criterio vigente.** El modelo no puede cubrir un
///    campo que nadie está preguntando, ni crear un criterio nuevo.
/// 3. **El valor que el modelo leyó es EL MISMO que el operador ya pidió.** El
///    modelo no puede cambiar un criterio: sólo señalar dónde está escrito uno
///    que otra fuente —la interpretación que el operador revisó y guardó— ya
///    había establecido.
/// 4. **El tramo no pertenece, por el vocabulario de la ficha, a OTRO campo
///    preguntado.** Las tres primeras dejaban pasar un vínculo falso: en «…
///    Shimano, de resina y sin aletas» tanto `Orgánico` como la ausencia de
///    aletas son ciertas, así que un modelo que dijera `compound_type =
///    Orgánico` **citando «sin aletas»** pasaba los tres controles y descargaba
///    la exigencia equivocada. La ficha misma lo desmiente: «aletas» es una
///    palabra del rótulo de `pad_finned`, y un tramo que nombra otro campo no
///    puede ser la cita de éste.
/// 5. **La ficha dice lo MISMO que el tramo, no una familia que lo contenga.**
///    `relation` es la única pregunta donde el modelo aporta comprensión, y por
///    eso se la hace explícita en vez de deducirla: «de resina» y `Orgánico`
///    son la misma cosa dicha de dos formas, pero «de kevlar» o «titanio» son
///    **más específicos** que `Orgánico` o `Metálico`. Descargar el tramo ahí
///    perdería la mitad de la exigencia —el compuesto quedaría demostrado y la
///    fibra no—, así que sólo `same` descarga; `narrower` y `broader` conservan
///    el requisito vivo. Si el modelo se equivoca, el error cae del lado de
///    dejar una exigencia pendiente, que es el lado visible.
///
/// De esa exigencia sale una propiedad que importa más que el caso original:
/// **un criterio que contradice la petición no queda cubierto**. Si el texto
/// dice «sin aletas» y el criterio guardado quedó en `con aletas`, los valores
/// no coinciden, el tramo no se descarga y la exigencia sigue viva con su
/// polaridad, en vez de desaparecer sin que nadie lo note.
///
/// Nada de esto pasa por `supplierQuoteEvidence`: ese lector decide si la fila
/// de un **proveedor** demuestra una spec, donde equivocarse produce un falso
/// «cumple». Acá el problema es el contrario —no perder un requisito— y la
/// corroboración es el propio criterio del operador.
/// Un envoltorio del modelo llega como texto o como mapa; el resto del lector
/// trabaja igual con los dos.
Object? _decodeExtractionResponse(Object? response) {
  if (response is! String) return response;
  try {
    return jsonDecode(response);
  } catch (_) {
    return null;
  }
}

SupplyNeedCriteriaSpans verifySupplyNeedCriteriaSpans({
  required String requestText,
  required List<SupplierNeedSearchField> fields,
  required Map<String, List<Object>> askedValues,
  required Object? response,
}) {
  // El vocabulario propio de cada campo preguntado: su rótulo, su clave y sus
  // valores permitidos. Es la ficha hablando de sí misma, no una lista nueva.
  // **Todos los campos de la ficha, no sólo los preguntados.** «Aletas» nombra
  // a `pad_finned` exista o no un criterio sobre él; que nadie lo esté
  // preguntando no convierte esa palabra en una cita del compuesto.
  final vocabularioDe = <String, Set<String>>{};
  for (final field in fields) {
    final key = field.key.trim();
    final palabras = <String>{
      ...ProductIdentityExtractor.normalize(field.label).split(' '),
      ...ProductIdentityExtractor.normalize(key.replaceAll('_', ' '))
          .split(' '),
      for (final value in field.allowedValues)
        ...ProductIdentityExtractor.normalize('$value').split(' '),
    }..removeWhere((word) => word.length < 4);
    vocabularioDe[key] = palabras;
  }
  final normalizedRequest =
      ' ${ProductIdentityExtractor.normalize(requestText)} ';
  if (normalizedRequest.trim().isEmpty || askedValues.isEmpty) {
    return const SupplyNeedCriteriaSpans(
      spans: <String>[],
      rejected: <String>[],
    );
  }
  final definitions = <String, SupplierNeedSearchField>{
    for (final field in fields) field.key.trim(): field,
  };
  final spans = <String>[];
  final rejected = <String>[];

  final decoded = _decodeExtractionResponse(response);
  if (decoded is! Map) {
    return const SupplyNeedCriteriaSpans(
      spans: <String>[],
      rejected: <String>['respuesta sin filas'],
    );
  }
  // **Una respuesta con otra forma es una respuesta sin leer, no una excepción.**
  // `rows` u objeto, `facts` como mapa, un `id` de otra fila: el modelo puede
  // devolver cualquiera de esas cosas, y todas tienen que terminar en cero
  // tramos, nunca en un `TypeError` fuera de la degradación.
  final rawRows = decoded['rows'];
  if (rawRows is! List) {
    return const SupplyNeedCriteriaSpans(
      spans: <String>[],
      rejected: <String>['respuesta sin filas'],
    );
  }
  for (final rawRow in rawRows) {
    if (rawRow is! Map) continue;
    // La única fila que se preguntó es la petición. Una lectura rotulada con
    // otro id responde otra pregunta.
    final rowId = rawRow['id']?.toString().trim() ?? '';
    if (rowId != kSupplyNeedCriteriaSpansRowId) {
      rejected.add('fila ajena: ${rowId.isEmpty ? 'sin id' : rowId}');
      continue;
    }
    final rawFacts = rawRow['facts'];
    if (rawFacts is! List) {
      rejected.add('la fila no trae una lista de criterios');
      continue;
    }
    for (final rawFact in rawFacts) {
      if (rawFact is! Map) continue;
      final field = rawFact['field']?.toString().trim() ?? '';
      final quote = rawFact['quote']?.toString().trim() ?? '';
      final value = rawFact['value'];
      final motivo = _criteriaSpanRejection(
        field: field,
        quote: quote,
        value: value,
        relation: '${rawFact['relation'] ?? ''}'.trim().toLowerCase(),
        normalizedRequest: normalizedRequest,
        askedValues: askedValues,
        definition: definitions[field],
        vocabularioDe: vocabularioDe,
      );
      if (motivo != null) {
        rejected.add('$field: $motivo');
        continue;
      }
      spans.add(quote);
    }
  }
  return SupplyNeedCriteriaSpans(
    spans: List<String>.unmodifiable(spans),
    rejected: List<String>.unmodifiable(rejected),
  );
}

String? _criteriaSpanRejection({
  required String field,
  required String quote,
  required Object? value,
  required String relation,
  required String normalizedRequest,
  required Map<String, List<Object>> askedValues,
  required SupplierNeedSearchField? definition,
  required Map<String, Set<String>> vocabularioDe,
}) {
  if (field.isEmpty) return 'sin campo';
  if (quote.isEmpty) return 'sin cita';
  // **La ficha es la que define qué campos existen.** `askedValues` viene de
  // los criterios guardados y puede nombrar un campo que la plantilla vigente
  // ya no tiene; descargar por ahí sería juzgar con una ficha que no existe.
  if (definition == null) return 'ese campo no está en la ficha';
  final pedidos = askedValues[field];
  if (pedidos == null || pedidos.isEmpty) return 'nadie pregunta por ese campo';
  final normalizedQuote = ProductIdentityExtractor.normalize(quote);
  if (normalizedQuote.isEmpty) return 'cita vacía';
  if (!normalizedRequest.contains(' $normalizedQuote ') &&
      !normalizedRequest.contains('$normalizedQuote ') &&
      !normalizedRequest.contains(' $normalizedQuote')) {
    return 'la cita no está en la petición';
  }
  if (!pedidos.any((pedido) => _sameCriterionValue(pedido, value, definition))) {
    return 'el valor leído no es el que el operador pidió';
  }
  if (relation != 'same') {
    return relation.isEmpty
        ? 'no dice si la ficha dice lo mismo o algo más amplio'
        : 'la ficha dice algo más amplio que el pedido ($relation)';
  }
  // **El tramo no puede estar nombrando otro campo preguntado.** Lo decide el
  // vocabulario de la propia ficha, no una lista de palabras del caso.
  final palabrasDelTramo = normalizedQuote.split(' ').toSet();
  for (final entry in vocabularioDe.entries) {
    if (entry.key == field) continue;
    if (entry.value.any(palabrasDelTramo.contains)) {
      return 'la cita nombra el campo «${entry.key}», no éste';
    }
  }
  return null;
}

/// Si el valor que leyó el modelo es **el mismo** que el criterio vigente.
///
/// Se compara con la tolerancia mínima que la ficha ya usa en todas partes:
/// booleanos como booleanos, números como números, y texto por su forma
/// normalizada, porque `Orgánico` y `organico` son el mismo valor de la lista.
bool _sameCriterionValue(
  Object pedido,
  Object? leido,
  SupplierNeedSearchField? definition,
) {
  if (leido == null) return false;
  if (pedido is bool || leido is bool) {
    final izquierda = pedido is bool ? pedido : _booleanOf('$pedido');
    final derecha = leido is bool ? leido : _booleanOf('$leido');
    return izquierda != null && izquierda == derecha;
  }
  if (pedido is num || leido is num) {
    final izquierda =
        pedido is num ? pedido.toDouble() : double.tryParse('$pedido');
    final derecha =
        leido is num ? leido.toDouble() : double.tryParse('$leido');
    return izquierda != null && derecha != null && izquierda == derecha;
  }
  return ProductIdentityExtractor.normalize('$pedido') ==
      ProductIdentityExtractor.normalize('$leido');
}

bool? _booleanOf(String raw) {
  final value = raw.trim().toLowerCase();
  if (value == 'true' || value == 'si' || value == 'sí') return true;
  if (value == 'false' || value == 'no') return false;
  return null;
}

/// Quién es el dueño de una lectura con modelo.
///
/// **Cancelar no puede ser global.** Con dos espacios de compras abiertos,
/// cerrar uno soltaba también los plazos del otro y los del lector del portal:
/// una pantalla viva se quedaba esperando una respuesta cuyo plazo alguien más
/// había tirado. Cada quien crea el suyo y cancela el suyo; una lectura sin
/// dueño pertenece a nadie y la cancela la llamada sin argumentos.
class SupplierModelReadOwner {
  final Set<_LecturaEnVuelo> _vivas = <_LecturaEnVuelo>{};

  /// **Cerrar es terminal.** Cancelar sólo lo que estaba en vuelo no alcanza:
  /// la página espera la plantilla antes de leer, así que una plantilla que
  /// llega **después** del `dispose` arrancaba una llamada al modelo y un
  /// temporizador nuevos para una pantalla que ya no existe. Un dueño cerrado
  /// no vuelve a abrir nada.
  bool _cerrado = false;

  /// Si este dueño ya soltó sus lecturas y no admite ninguna más.
  bool get isClosed => _cerrado;
}

class _LecturaEnVuelo {
  _LecturaEnVuelo(this.timer, this.completer, this.owner);

  final Timer timer;
  final Completer<Object?> completer;
  final SupplierModelReadOwner? owner;
}

/// La excepción con que se cierra una espera cuyo dueño ya no la necesita.
class SupplierModelReadCancelled implements Exception {
  const SupplierModelReadCancelled();

  @override
  String toString() => 'la lectura con modelo se soltó: nadie la espera';
}

final Set<_LecturaEnVuelo> _lecturasEnVuelo = <_LecturaEnVuelo>{};

/// Suelta los plazos en vuelo de `owner`, o los que no tienen dueño.
///
/// **Cancelar tiene que cerrar también la espera.** Matar el temporizador y
/// dejar el `Completer` abierto no arregla la fuga: la deja peor, porque quien
/// esperaba se queda colgado para siempre cuando el modelo no responde. Se
/// completa con [SupplierModelReadCancelled], que cada lector trata como
/// cualquier otro fallo: degrada.
void cancelSupplierModelReadDeadlines({SupplierModelReadOwner? owner}) {
  final objetivo = <_LecturaEnVuelo>[
    for (final lectura in (owner?._vivas ?? _lecturasEnVuelo))
      if (owner != null || lectura.owner == null) lectura,
  ];
  owner?._cerrado = true;
  for (final lectura in objetivo) {
    lectura.timer.cancel();
    _lecturasEnVuelo.remove(lectura);
    lectura.owner?._vivas.remove(lectura);
    if (!lectura.completer.isCompleted) {
      lectura.completer.completeError(const SupplierModelReadCancelled());
    }
  }
}

/// Un plazo propio: vence igual que `Future.timeout` y además se puede soltar.
///
/// `Future.timeout` crea su temporizador y no lo presta: con la llamada sin
/// volver —lo normal al cerrar la pantalla o sin red— seguía vivo veinte
/// segundos después de que ya nadie esperaba.
Future<Object?> _conPlazo(
  Future<Object?> operacion,
  Duration plazo,
  SupplierModelReadOwner? owner,
) {
  if (owner?.isClosed ?? false) {
    return Future<Object?>.error(const SupplierModelReadCancelled());
  }
  final completer = Completer<Object?>();
  late final _LecturaEnVuelo lectura;
  void soltar() {
    lectura.timer.cancel();
    _lecturasEnVuelo.remove(lectura);
    owner?._vivas.remove(lectura);
  }

  final temporizador = Timer(plazo, () {
    _lecturasEnVuelo.remove(lectura);
    owner?._vivas.remove(lectura);
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException('la lectura con modelo no respondió', plazo),
      );
    }
  });
  lectura = _LecturaEnVuelo(temporizador, completer, owner);
  _lecturasEnVuelo.add(lectura);
  owner?._vivas.add(lectura);
  operacion.then(
    (value) {
      soltar();
      if (!completer.isCompleted) completer.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      soltar();
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future;
}

/// El id de la única fila que esta lectura pregunta: la petición.
const String kSupplyNeedCriteriaSpansRowId = 'peticion';

/// El prompt que le pide al lector **dónde** está escrito cada criterio.
///
/// Es deliberadamente la tarea más pequeña posible: no se le pregunta qué
/// significa la petición ni si un producto sirve, sólo en qué palabras el
/// operador escribió un criterio que ya existe. Y se le pide la única
/// distinción que el código no puede hacer solo —si la ficha dice lo mismo o
/// algo más amplio—, porque de eso depende conservar la exigencia.
String buildSupplyNeedCriteriaSpansPrompt({
  required String requestText,
  required List<SupplierNeedSearchField> fields,
  required Map<String, List<Object>> askedValues,
}) {
  final campos = <Map<String, Object?>>[
    for (final field in fields)
      if (askedValues.containsKey(field.key.trim()))
        <String, Object?>{
          'key': field.key,
          'label': field.label,
          'type': field.dataType,
          if (field.unit != null && field.unit!.trim().isNotEmpty)
            'unit': field.unit,
          if (field.allowedValues.isNotEmpty)
            'allowed_values': field.allowedValues,
          'pedido': askedValues[field.key.trim()],
        },
  ];
  return '''
Eres un lector. Tu única tarea es señalar EN QUÉ PALABRAS de una petición está
escrito cada criterio que el taller ya definió. No decides qué se necesita ni si
un producto sirve.

PETICIÓN:
${jsonEncode(requestText)}

CRITERIOS YA DEFINIDOS (cada uno con el valor que el taller pidió):
${jsonEncode(campos)}

Por cada criterio, responde SÓLO si la petición lo dice, con:

- `quote`: el pedazo EXACTO de la petición donde está escrito, copiado tal cual.
  Si no puedes copiarlo, no incluyas el criterio.
- `value`: el valor que esas palabras declaran. Tiene que ser el mismo que
  `pedido`; si lo que la petición dice es otro valor, no incluyas el criterio.
- `relation`: cómo se relaciona el valor de la ficha con lo que dice la
  petición.
  - `same` si dicen lo mismo con otras palabras.
  - `narrower` si la petición dice algo MÁS ESPECÍFICO que el valor de la ficha
    (la ficha ofrece una familia y el taller pidió una variante concreta).
  - `broader` si la petición dice algo más general que el valor de la ficha.

Reglas:

- La cita tiene que ser de las palabras que declaran ESE criterio. Si esas
  palabras hablan de otra característica, no incluyas el criterio.
- Si la petición no dice el criterio, OMÍTELO. Omitir es la respuesta correcta;
  suponer es un error grave.
- No uses tu conocimiento del producto: sólo el texto de la petición.

Responde SOLO este JSON:

{"rows":[{"id":"peticion","facts":[
  {"field":"<key>","value":<valor>,"quote":"<texto exacto>","relation":"same"}
]}]}
''';
}

/// Le pregunta al lector dónde está escrito cada criterio, y verifica.
///
/// **Qué prueba esta verificación y qué no.** La cita literal impide inventar
/// texto; la igualdad con el criterio impide cambiar lo que el taller pidió; el
/// vocabulario de la ficha impide atribuirle a un campo las palabras de otro; y
/// `relation` conserva la exigencia cuando la ficha sólo ofrece una familia.
/// Ninguna de las cuatro impide que el modelo se equivoque **dentro** de esos
/// límites: puede responder `same` cuando no lo es, o citar una frase real que
/// no sostiene su conclusión. Por eso lo único que esta lectura puede hacer es
/// **descargar** una exigencia que ya se está juzgando como criterio, nunca
/// declarar algo cumplido; y por eso el fallo se degrada a no descargar nada.
///
/// Sin modelo, con el modelo lento, sin cuota o con una respuesta ilegible se
/// devuelven cero tramos: el juicio sigue con el vocabulario de la ficha, que
/// es más pobre pero nunca peor que ignorar el requisito.
Future<SupplyNeedCriteriaSpans> readSupplyNeedCriteriaSpansWithModel({
  required String requestText,
  required List<SupplierNeedSearchField> fields,
  required Map<String, List<Object>> askedValues,
  required SupplierSpecExtractor extractor,
  Duration deadline = const Duration(seconds: 20),
  SupplierModelReadOwner? owner,
}) async {
  if (requestText.trim().isEmpty || askedValues.isEmpty || fields.isEmpty) {
    return const SupplyNeedCriteriaSpans(
      spans: <String>[],
      rejected: <String>[],
    );
  }
  if (owner?.isClosed ?? false) {
    return const SupplyNeedCriteriaSpans(
      spans: <String>[],
      rejected: <String>['la pantalla que la pidió ya se cerró'],
    );
  }
  final key = supplyNeedCriteriaSpansKey(requestText, askedValues, fields);
  final cached = _spansCache[key];
  if (cached != null) return cached;

  Object? response;
  try {
    response = await _conPlazo(
      extractor(buildSupplyNeedCriteriaSpansPrompt(
        requestText: requestText,
        fields: fields,
        askedValues: askedValues,
      )),
      deadline,
      owner,
    );
  } catch (error) {
    debugPrint('🧠 tramos de la petición: sin modelo ($error)');
    return const SupplyNeedCriteriaSpans(
      spans: <String>[],
      rejected: <String>['sin modelo'],
    );
  }
  final result = verifySupplyNeedCriteriaSpans(
    requestText: requestText,
    fields: fields,
    askedValues: askedValues,
    response: response,
  );
  if (result.rejected.isNotEmpty) {
    debugPrint('🧠 tramos de la petición: '
        '${result.spans.length} aceptados, '
        '${result.rejected.length} descartados — ${result.rejected.join('; ')}');
  }
  // **La misma petición no se lee dos veces.** Precisar un criterio vuelve a
  // armar la consulta, y sin esto cada refinamiento pagaría otra llamada por
  // un texto que no cambió. La llave incluye los valores pedidos, así que
  // cambiar un criterio sí vuelve a preguntar: es otra pregunta.
  if (_spansCache.length >= _spansCacheMax) _spansCache.clear();
  _spansCache[key] = result;
  return result;
}

const int _spansCacheMax = 32;
final Map<String, SupplyNeedCriteriaSpans> _spansCache =
    <String, SupplyNeedCriteriaSpans>{};

/// La llave del reuso: el texto, los criterios **y la ficha con que se leen**.
///
/// Sin la ficha, `2 mm` y `2 cm` son la misma pregunta: la clave del campo y el
/// número pedido no cambian cuando cambia la unidad, el tipo o la lista de
/// valores permitidos, y la respuesta anterior se reusaba para una ficha que ya
/// dice otra cosa.
String supplyNeedCriteriaSpansKey(
  String requestText,
  Map<String, List<Object>> askedValues,
  List<SupplierNeedSearchField> fields,
) {
  final campos = askedValues.keys.toList(growable: false)..sort();
  final ficha = <Map<String, Object?>>[
    for (final field in (fields.toList()
      ..sort((left, right) => left.key.compareTo(right.key))))
      <String, Object?>{
        'key': field.key,
        'label': field.label,
        'type': field.dataType,
        'unit': field.unit,
        'allowed': field.allowedValues.map((value) => '$value').toList(),
      },
  ];
  return jsonEncode(<String, Object?>{
    'texto': requestText.trim(),
    'criterios': <String, Object?>{
      for (final campo in campos) campo: askedValues[campo],
    },
    'ficha': ficha,
  });
}

/// Vacía el reuso de tramos. Sólo para pruebas.
@visibleForTesting
void resetSupplyNeedCriteriaSpansCache() => _spansCache.clear();

/// Lo que el proveedor dice sobre una exigencia que la ficha no sabe nombrar.
///
/// **La asimetría es deliberada.** Una lectura del modelo puede DESCARTAR una
/// fila con evidencia —el proveedor dice que el rodamiento es abierto, que la
/// pastilla trae aletas— y eso le ahorra al operador abrir filas que no
/// sirven. No puede, en cambio, declarar cumplida una exigencia que nadie
/// verificó: ahí lo más que hace es recomendar, y la fila queda por revisar.
/// Es la misma frontera que separa una inferencia de un hecho demostrado.
enum SupplierRequirementReading {
  /// El proveedor dice lo contrario de lo que se pidió, y lo dice en su texto.
  contradicts,

  /// El proveedor parece cumplirla, pero eso lo concluyó el modelo.
  suggests,

  /// El modelo cree que no la cumple y el texto citado no lo confirma. Se
  /// muestra como duda, no como descarte: una fila válida perdida por una
  /// inferencia no vuelve.
  suggestsAgainst,

  /// No se pudo establecer nada.
  unknown,
}

/// Verifica lo que el modelo dijo de cada fila sobre cada exigencia.
///
/// La cita tiene que estar **literal en el texto de esa fila**: es lo que
/// impide inventar un rechazo. Lo demás lo decide el código, no el modelo:
/// `meets:false` con cita se convierte en contradicción, `meets:true` en una
/// recomendación que no completa, y cualquier otra cosa en nada.
/// Lo que el proveedor dijo de una exigencia, con la cita que lo sostiene.
@immutable
class SupplierRequirementFinding {
  const SupplierRequirementFinding({
    required this.reading,
    required this.quote,
    this.signature = '',
  });

  /// La exigencia completa que esta lectura contestó: polaridad, dimensión y
  /// alcance. Es lo que la ata a su pregunta; la palabra sola no basta.
  final String signature;

  final SupplierRequirementReading reading;

  /// El pedazo del texto del proveedor, verificado literal contra esa fila.
  /// Sin cita no hay lectura, y con ella el operador puede desmentirla.
  final String quote;
}

Map<String, Map<String, SupplierRequirementFinding>>
    verifySupplierRequirementReadings({
  required List<SupplierSpecExtractionRow> rows,
  required List<SupplyNeedUnmodelledRequirement> requirements,
  required Object? response,
  List<String>? rejected,
}) {
  final requirementTerms = <String, SupplyNeedUnmodelledRequirement>{
    for (final requirement in requirements) requirement.term: requirement,
  };
  final decoded = _decodeExtractionResponse(response);
  if (decoded is! Map) {
    rejected?.add('respuesta sin filas');
    return const <String, Map<String, SupplierRequirementFinding>>{};
  }
  final textoDe = <String, String>{
    for (final row in rows)
      row.id: ' ${ProductIdentityExtractor.normalize(row.text)} ',
  };
  final rawRows = decoded['rows'];
  if (rawRows is! List) {
    rejected?.add('respuesta sin filas');
    return const <String, Map<String, SupplierRequirementFinding>>{};
  }
  final lecturas = <String, Map<String, SupplierRequirementFinding>>{};
  for (final rawRow in rawRows) {
    if (rawRow is! Map) continue;
    final rowId = rawRow['id']?.toString().trim() ?? '';
    final texto = textoDe[rowId];
    if (texto == null) {
      rejected?.add('fila desconocida: ${rowId.isEmpty ? 'sin id' : rowId}');
      continue;
    }
    final rawFacts = rawRow['requirements'];
    if (rawFacts is! List) continue;
    for (final rawFact in rawFacts) {
      if (rawFact is! Map) continue;
      final term = rawFact['term']?.toString().trim() ?? '';
      final requirement = requirementTerms[term];
      if (requirement == null) {
        rejected?.add('$rowId: exigencia no pedida «$term»');
        continue;
      }
      final meets = rawFact['meets'];
      if (meets is! bool) continue;
      final quote = rawFact['quote']?.toString().trim() ?? '';
      final normalizedQuote = ProductIdentityExtractor.normalize(quote);
      if (normalizedQuote.isEmpty || !texto.contains(normalizedQuote)) {
        rejected?.add('$rowId/$term: la cita no está en la fila');
        continue;
      }
      // **Un negativo descarta un producto: pide el mismo cuidado que un
      // cumplimiento, o más.** Que la cita exista no dice que contradiga: el
      // modelo puede citar una frase verdadera y concluir mal, y ahí se pierde
      // una fila que servía. Así que el rechazo lo confirma el código sobre las
      // palabras citadas —la exigencia tiene que aparecer ahí con la polaridad
      // contraria—; si no lo puede corroborar, queda como lectura sin
      // confirmar, nunca como descarte.
      final lectura = meets
          ? SupplierRequirementReading.suggests
          : (_quoteContradicts(normalizedQuote, requirement)
              ? SupplierRequirementReading.contradicts
              : SupplierRequirementReading.suggestsAgainst);
      lecturas.putIfAbsent(
        rowId,
        () => <String, SupplierRequirementFinding>{},
      )[term] = SupplierRequirementFinding(
        reading: lectura,
        quote: quote,
        signature: requirement.signature,
      );
    }
  }
  return lecturas;
}


/// Si las palabras citadas contradicen la exigencia, leídas por el código.
///
/// Se busca la exigencia en la cita y se compara su polaridad: pedida presente
/// y citada negada —o al revés— es una contradicción que el texto sostiene.
/// Cualquier otra cosa no lo es, por convincente que suene la conclusión.
bool _quoteContradicts(
  String normalizedQuote,
  SupplyNeedUnmodelledRequirement requirement,
) {
  const negadores = <String>{'sin', 'no', 'nunca', 'ningun', 'ninguna'};
  final tokens = normalizedQuote.split(' ');
  for (var index = 0; index < tokens.length; index += 1) {
    if (!tokens[index].startsWith(requirement.term)) continue;
    var negada = false;
    for (var atras = 1; atras <= 3 && index - atras >= 0; atras += 1) {
      if (negadores.contains(tokens[index - atras])) {
        negada = true;
        break;
      }
    }
    if (negada != requirement.affirmed) return false;
    return true;
  }
  return false;
}

/// El prompt que le pregunta al proveedor por lo que la ficha no sabe nombrar.
String buildSupplierRequirementReadingPrompt({
  required List<SupplierSpecExtractionRow> rows,
  required List<SupplyNeedUnmodelledRequirement> requirements,
}) {
  // **La exigencia viaja como la escribió el taller.** Mandar sólo la raíz
  // interna preguntaba por `3` en vez de por `3/32`, y por `sell` en vez de
  // «sello de goma a ambos lados»: el proveedor no puede contestar eso.
  final exigencias = <Map<String, Object?>>[
    for (final requirement in requirements)
      <String, Object?>{
        'term': requirement.term,
        'exigencia': requirement.label.isEmpty
            ? <String>[requirement.term, ...requirement.tail].join(' ')
            : requirement.label,
        'pedida': requirement.affirmed ? 'presente' : 'ausente',
        if (requirement.scope.isNotEmpty) 'alcance': requirement.scope,
      },
  ];
  final filas = <Map<String, Object?>>[
    for (final row in rows) <String, Object?>{'id': row.id, 'text': row.text},
  ];
  return '''
Eres un lector de catálogos de repuestos de bicicleta. Tu única tarea es LEER lo
que el proveedor escribió. No decides si un producto sirve.

El taller pidió unas características que su ficha técnica no sabe nombrar:

${jsonEncode(exigencias)}

FILAS:
${jsonEncode(filas)}

Por cada fila y cada exigencia, responde SÓLO si el texto de esa fila dice algo
al respecto:

- `meets`: `true` si la fila declara lo que se pidió, `false` si declara lo
  contrario.
- `quote`: el pedazo EXACTO del texto de esa fila donde lo dice, copiado tal
  cual. Sin cita no se incluye nada.

Reglas:

- Si la fila no dice nada de esa exigencia, OMÍTELA. Omitir es la respuesta
  correcta; suponer es un error grave.
- No uses tu conocimiento del producto ni de la marca: sólo el texto de la fila.

Responde SOLO este JSON:

{"rows":[{"id":"<id>","requirements":[
  {"term":"<term>","meets":true,"quote":"<texto exacto>"}
]}]}
''';
}

/// Le pregunta al proveedor por las exigencias fuera de ficha, y verifica.
///
/// **Lo que esto cambia y lo que no.** El veredicto sigue saliendo del texto de
/// la fila: una lectura confirmada como contradicción es la misma conclusión a
/// la que el código llega solo, y una lectura afirmativa nunca completa. Lo que
/// agrega es **decírselo al operador**: por qué una fila quedó pendiente, y qué
/// dijo el proveedor sobre la parte que ninguna ficha sabe preguntar. Viaja con
/// la fila, no la juzga.
Future<Map<String, Map<String, SupplierRequirementFinding>>>
    readSupplierRequirementsWithModel({
  required List<SupplierSpecExtractionRow> rows,
  required List<SupplyNeedUnmodelledRequirement> requirements,
  required SupplierSpecExtractor extractor,
  Duration deadline = const Duration(seconds: 20),
  List<String>? rejected,
  SupplierModelReadOwner? owner,
}) async {
  if (rows.isEmpty || requirements.isEmpty || (owner?.isClosed ?? false)) {
    return const <String, Map<String, SupplierRequirementFinding>>{};
  }
  Object? response;
  try {
    response = await _conPlazo(
      extractor(buildSupplierRequirementReadingPrompt(
        rows: rows,
        requirements: requirements,
      )),
      deadline,
      owner,
    );
  } catch (error) {
    debugPrint('🧠 exigencias fuera de ficha: sin modelo ($error)');
    return const <String, Map<String, SupplierRequirementFinding>>{};
  }
  return verifySupplierRequirementReadings(
    rows: rows,
    requirements: requirements,
    response: response,
    rejected: rejected,
  );
}

/// La clave con que la lectura de exigencias viaja dentro de una fila.
const String kSupplierRequirementReadingFact = 'requirement_readings';

/// Adjunta las lecturas a sus filas, sin tocar nada más.
List<SupplierPortalCatalogCandidate> attachSupplierRequirementReadings({
  required List<SupplierPortalCatalogCandidate> candidates,
  required Map<String, Map<String, SupplierRequirementFinding>> readings,
}) {
  if (readings.isEmpty) return candidates;
  return <SupplierPortalCatalogCandidate>[
    for (final candidate in candidates)
      if (readings[candidate.code.trim()] case final lectura?)
        SupplierPortalCatalogCandidate(
          code: candidate.code,
          name: candidate.name,
          brand: candidate.brand,
          origin: candidate.origin,
          priceNet: candidate.priceNet,
          rowText: candidate.rowText,
          technicalFacts: <String, Object?>{
            ...candidate.technicalFacts,
            kSupplierRequirementReadingFact: <String, Object?>{
              for (final entry in lectura.entries)
                entry.key: <String, Object?>{
                  'reading': entry.value.reading.name,
                  'quote': entry.value.quote,
                  'signature': entry.value.signature,
                },
            },
          },
        )
      else
        candidate,
  ];
}

/// El prompt que le entrega al lector **la petición completa** y lo que la
/// ficha ya representa, para que nombre lo que falta.
///
/// **Por qué el texto entero y no unas raíces.** La extracción determinista
/// filtra por largo, descarta dígitos y absorbe sintagmas, y cada uno de esos
/// filtros existe por una buena razón — pero juntos hacen desaparecer
/// exigencias antes de que nadie las lea: `gel` por corta, `3/32` por numérica,
/// una condición compuesta por quedar pegada a otra. Al lector se le da la
/// petición **tal como la escribió el taller** y la lista de lo que los
/// criterios ya cubren; lo que queda es justamente lo que hay que preservar.
String buildSupplyNeedRequirementDiscoveryPrompt({
  required String requestText,
  required List<SupplierNeedSearchField> fields,
  required Map<String, List<Object>> askedValues,
}) {
  final cubierto = <Map<String, Object?>>[
    for (final field in fields)
      if (askedValues[field.key.trim()] case final pedido?)
        <String, Object?>{'campo': field.label, 'pedido': pedido},
  ];
  return '''
Eres un lector. Tu única tarea es señalar QUÉ EXIGENCIAS de una petición no
están representadas por los criterios que ya se registraron. No decides si un
producto sirve ni inventas criterios nuevos.

PETICIÓN, tal como la escribió el taller:
${jsonEncode(requestText)}

YA REPRESENTADO por la ficha técnica:
${jsonEncode(cubierto)}

Responde una entrada por cada exigencia de la petición que NO esté en esa lista,
incluidas las que se piden ausentes y las que traen una cantidad o un alcance:

- `quote`: el pedazo EXACTO de la petición donde está escrita, copiado tal cual.
  Sin cita no se incluye.
- `required`: `true` si se pide presente, `false` si se pide ausente.
- `scope`: las palabras de cantidad o alcance que la acompañan, si las hay
  («a ambos lados», «en un solo lado»). Arreglo vacío si no hay.

Reglas:

- Una exigencia ya representada NO se repite.
- El nombre de la pieza que se busca no es una exigencia.
- Una cantidad de compra («4 unidades», «3 juegos») no es una exigencia.
- Si no queda ninguna, responde con la lista vacía. Es la respuesta correcta.

Responde SOLO este JSON:

{"requirements":[{"quote":"<texto exacto>","required":true,"scope":[]}]}
''';
}

/// Verifica las exigencias que el lector encontró en la petición.
///
/// La cita tiene que estar **literal en la petición**: es lo que impide
/// inventar una exigencia que nadie escribió. Lo demás lo decide el código —la
/// raíz con que se comparará contra la fila, y el alcance—, igual que en la vía
/// determinista, para que las dos produzcan exactamente el mismo tipo de
/// exigencia y se puedan unir sin que una degrade a la otra.
List<SupplyNeedUnmodelledRequirement> verifySupplyNeedDiscoveredRequirements({
  required String requestText,
  required Object? response,
  List<String>? rejected,
}) {
  final decoded = _decodeExtractionResponse(response);
  if (decoded is! Map) {
    rejected?.add('respuesta sin exigencias');
    return const <SupplyNeedUnmodelledRequirement>[];
  }
  final raw = decoded['requirements'];
  if (raw is! List) {
    rejected?.add('respuesta sin exigencias');
    return const <SupplyNeedUnmodelledRequirement>[];
  }
  final normalizedRequest =
      ' ${ProductIdentityExtractor.normalize(requestText)} ';
  final encontradas = <String, SupplyNeedUnmodelledRequirement>{};
  for (final entry in raw) {
    if (entry is! Map) continue;
    final quote = entry['quote']?.toString().trim() ?? '';
    final normalizedQuote = ProductIdentityExtractor.normalize(quote);
    if (normalizedQuote.isEmpty ||
        !normalizedRequest.contains(normalizedQuote)) {
      rejected?.add('«$quote» no está en la petición');
      continue;
    }
    final required = entry['required'];
    if (required is! bool) {
      rejected?.add('«$quote» no dice si se pide presente o ausente');
      continue;
    }
    // **El alcance sale de la cita, no de un campo aparte.** El modelo puede
    // mandar `scope: ['ambos lados']` sobre una cita que dice sólo «gel», y eso
    // sería exigir algo que el taller no escribió. Se leen las palabras de
    // alcance del propio texto citado, con el mismo vocabulario de dominio que
    // usa la vía determinista.
    final tokensCita = normalizedQuote.split(' ');
    final scope = <String>[
      for (final word in tokensCita)
        if (kSupplyScopeWords.contains(word)) word,
    ];

    // **Una fracción es una medida entera.** `3/32` llega partido en dos
    // números por el normalizador canónico, y ninguno pasa un filtro de largo:
    // se recupera del texto crudo y se exige como pareja contigua.
    final fraccion = RegExp(r'\b\d+\s*/\s*\d+\b').firstMatch(quote);
    if (fraccion != null) {
      final partes = ProductIdentityExtractor.normalize(fraccion.group(0)!)
          .split(' ')
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
      if (partes.isNotEmpty) {
        encontradas.putIfAbsent(
          partes.join(' '),
          () => SupplyNeedUnmodelledRequirement(
            term: partes.first,
            tail: partes.skip(1).toList(growable: false),
            label: fraccion.group(0)!,
            affirmed: required,
            scope: scope,
          ),
        );
        continue;
      }
    }

    // **El conector nunca es la exigencia.** «Con gel» tiene dos palabras de
    // tres letras, y quedarse con `con` habría probado la exigencia contra
    // cualquier fila del catálogo. Se descartan las palabras de función y de
    // alcance, y de lo que queda manda la de más contenido.
    final palabras = tokensCita
        .where((word) =>
            word.length >= 3 &&
            !kSupplyScopeWords.contains(word) &&
            !kSupplyFunctionWords.contains(word))
        .toList(growable: false);
    if (palabras.isEmpty) {
      rejected?.add('«$quote» no nombra nada');
      continue;
    }
    final cabeza = palabras.reduce((a, b) => b.length > a.length ? b : a);
    encontradas.putIfAbsent(
      cabeza,
      () => SupplyNeedUnmodelledRequirement(
        term: cabeza,
        label: quote,
        affirmed: required,
        scope: scope,
      ),
    );
  }
  return List<SupplyNeedUnmodelledRequirement>.unmodifiable(
    encontradas.values,
  );
}

/// Le pregunta al lector qué exige la petición que la ficha no representa.
///
/// Se reusa por pregunta —texto y criterios—, igual que la lectura de tramos:
/// precisar un criterio vuelve a armar la consulta y no puede pagar otra
/// llamada por un texto que no cambió. Sin modelo devuelve cero exigencias, y
/// entonces manda la extracción determinista, que es más pobre y nunca peor.
Future<List<SupplyNeedUnmodelledRequirement>>
    readSupplyNeedRequirementsWithModel({
  required String requestText,
  required List<SupplierNeedSearchField> fields,
  required Map<String, List<Object>> askedValues,
  required SupplierSpecExtractor extractor,
  Duration deadline = const Duration(seconds: 20),
  SupplierModelReadOwner? owner,
}) async {
  if (requestText.trim().isEmpty) {
    return const <SupplyNeedUnmodelledRequirement>[];
  }
  if (owner?.isClosed ?? false) {
    return const <SupplyNeedUnmodelledRequirement>[];
  }
  final key = supplyNeedCriteriaSpansKey(requestText, askedValues, fields);
  final cached = _discoveryCache[key];
  if (cached != null) return cached;

  Object? response;
  try {
    response = await _conPlazo(
      extractor(buildSupplyNeedRequirementDiscoveryPrompt(
        requestText: requestText,
        fields: fields,
        askedValues: askedValues,
      )),
      deadline,
      owner,
    );
  } catch (error) {
    debugPrint('🧠 exigencias de la petición: sin modelo ($error)');
    return const <SupplyNeedUnmodelledRequirement>[];
  }
  final rechazos = <String>[];
  final encontradas = verifySupplyNeedDiscoveredRequirements(
    requestText: requestText,
    response: response,
    rejected: rechazos,
  );
  if (rechazos.isNotEmpty) {
    debugPrint('🧠 exigencias de la petición: ${encontradas.length} aceptadas, '
        '${rechazos.length} descartadas — ${rechazos.join('; ')}');
  }
  if (_discoveryCache.length >= _spansCacheMax) _discoveryCache.clear();
  _discoveryCache[key] = encontradas;
  return encontradas;
}

final Map<String, List<SupplyNeedUnmodelledRequirement>> _discoveryCache =
    <String, List<SupplyNeedUnmodelledRequirement>>{};

/// Vacía el reuso de exigencias descubiertas. Sólo para pruebas.
@visibleForTesting
void resetSupplyNeedRequirementDiscoveryCache() => _discoveryCache.clear();
