import 'dart:async';

import 'package:flutter/foundation.dart';

import 'supplier_need_portal_search.dart';
import 'supplier_spec_extraction.dart';

/// Leer la ficha que el catálogo del taller nunca llegó a tener.
///
/// **El problema es de datos, no de calce.** Medido sobre el catálogo real el
/// 2026-08-31: 1.613 productos activos y 45 con descripción de más de veinte
/// caracteres. Lo único escrito es el nombre, y el lector determinista sólo
/// resuelve un campo cuando la palabra pedida aparece literal — por eso
/// `METALICA` no contradecía `Orgánico` y una necesidad entera quedaba sin
/// verificar por silencio en vez de por desacuerdo.
///
/// Acá se le pide al modelo que lea ese nombre. Lo que no se hace es creerle:
///
///  · la cita se comprueba contra el texto de la fila y se **relee** con el
///    lector determinista, que es quien decide si sostiene el valor. Eso pasa
///    en `verifySupplierSpecExtraction`, compartido con el proveedor: es el
///    mismo circuito, no un motor paralelo;
///  · **el cliente descarta lo que puede desmentir; el servidor decide lo que
///    cuenta como prueba.** Lo que sobrevive a esa relectura se ofrece tal
///    cual, sea `stated` —algún lector nuestro lo reprodujo— o `inferred`
///    —ninguno lo reconoció—. Ofrecer `inferred` no es una rebaja: es donde
///    vive el valor de esto, porque `METALICA` no es literalmente `Metálico`
///    para ningún lector nuestro y por eso el catálogo llevaba años en
///    silencio. El servidor sí sabe resolverlo, comparando contra el
///    vocabulario que la propia ficha declara;
///  · y el servidor vuelve a comprobar todo por su cuenta antes de guardar,
///    porque el cliente es justamente la parte que podría estar equivocada. Un
///    hecho entra sólo si él lo acepta, y su veredicto es el que se reporta.
///
/// Una lectura que falla —modelo caído, lento, ilegible, o rechazada por el
/// servidor— no escribe nada y la fila sigue sin verificar. Es lo correcto:
/// «no sé» y «no cumple» no son lo mismo.
class CatalogRowToRead {
  const CatalogRowToRead({
    required this.productId,
    required this.text,
    required this.missingFields,
  });

  final String productId;

  /// El nombre —y la descripción, si la hay— tal como están guardados.
  final String text;

  /// Los campos que esta fila tiene sin resolver. Sólo se pregunta por ellos:
  /// preguntar por los ya resueltos gastaría la lectura en algo que el
  /// servidor va a descartar de todas formas, porque una ficha existente manda
  /// sobre una lectura.
  final Set<String> missingFields;
}

/// Qué pasó con cada lectura, para poder decirlo en pantalla y en las pruebas.
@immutable
class CatalogNameReadingOutcome {
  const CatalogNameReadingOutcome({
    required this.recorded,
    required this.rejectedByServer,
    required this.keptExisting,
    required this.rowsRead,
    this.failures = const <String>[],
    this.cutShort = false,
    this.modelUnavailable = false,
    this.abandoned = false,
    this.wouldOffer = 0,
  });

  /// Hechos que el servidor aceptó y guardó.
  final int recorded;

  /// Lecturas que pasaron el filtro del cliente y el servidor rechazó igual.
  /// **No es ruido**: es la medida de cuánto habría entrado sin esa segunda
  /// puerta, y por eso se reporta en vez de tragarse.
  final List<String> rejectedByServer;

  /// Campos que ya tenían un dato de otra procedencia. Una lectura nunca pisa
  /// a una persona.
  final int keptExisting;

  final int rowsRead;

  /// Lecturas que ni siquiera obtuvieron veredicto: la llamada falló o expiró.
  ///
  /// **No es lo mismo que un rechazo.** Un rechazo es una respuesta —esa cita
  /// no sostiene ese valor— y repetirla daría lo mismo. Un fallo es no haber
  /// preguntado, y ésa sí se puede reintentar.
  final List<String> failures;

  /// La pasada terminó por tope, presupuesto o cambio de pregunta, con
  /// lecturas todavía sin ofrecer.
  ///
  /// **Sin esto el corte no tenía continuidad.** Si los primeros sesenta
  /// intentos eran rechazos, no se guardaba nada, nadie recargaba y las
  /// lecturas válidas que venían detrás no se alcanzaban nunca.
  final bool cutShort;

  /// El modelo no contestó. Distinto de «no leyó nada»: hay que decirlo.
  final bool modelUnavailable;

  /// La pregunta cambió mientras el modelo respondía y la lectura se soltó.
  ///
  /// **No es lo mismo que un corte por tope.** Un tope significa «esto ya se
  /// preguntó, sigue por lo que falta»; esto significa «esto no se preguntó
  /// nunca», y hay que poder volver a intentarlo tal cual cuando el operador
  /// regrese a esa necesidad.
  final bool abandoned;

  /// Cuántas llamadas de este lote consumieron presupuesto.
  ///
  /// **Un fallo no cuenta.** El presupuesto acota el trabajo útil —cuántos
  /// hechos se alcanzan a someter al juicio del servidor— y una llamada que
  /// nunca obtuvo veredicto no gastó nada de eso. Además una caída detiene la
  /// cadena por sí sola, así que tampoco puede dar vueltas gratis.
  int get attemptsSpent =>
      recorded + keptExisting + rejectedByServer.length + wouldOffer;

  /// En ensayo, cuántos hechos se le **habrían ofrecido** al servidor.
  ///
  /// No es «se habrían guardado»: el ensayo no llega a preguntar, y el que
  /// decide si un hecho entra es el servidor. Confundir las dos cosas sería
  /// contar como evidencia algo que nadie juzgó. Fuera del ensayo siempre es
  /// cero: ahí lo que cuenta es el veredicto real.
  final int wouldOffer;

  bool get changedSomething => recorded > 0;

  /// Si vale la pena volver a intentar este mismo conjunto.
  ///
  /// Un rechazo del servidor no es reintentable: la misma cita y el mismo
  /// valor dan el mismo veredicto. Un modelo caído o una RPC que nunca
  /// respondió sí lo son, y bloquear el conjunto por un fallo transitorio
  /// dejaba esa necesidad sin lectura hasta remontar la página.
  bool get retryable => modelUnavailable || failures.isNotEmpty || abandoned;

  /// Queda trabajo por ofrecer en este mismo conjunto.
  bool get hasMoreToOffer => cutShort;
}

/// Quien guarda un hecho leído. Es la RPC del servidor, inyectada para poder
/// probar el circuito sin red.
typedef CatalogReadingRecorder = Future<Map<String, Object?>> Function({
  required String productId,
  required String fieldKey,
  required Object value,
  required String quote,
});

/// Cuántas filas se leen de una vez. Una lectura es una llamada al modelo con
/// todas las filas dentro, así que el tope es de tamaño de prompt y de tiempo,
/// no de costo por fila.
const int kCatalogNameReadingRowCap = 40;

/// Cuántos hechos se persisten como máximo en una pasada.
///
/// **Acotar el prompt no acota la escritura.** Cuarenta filas por tres campos
/// son ciento veinte viajes al servidor, uno por hecho, después de que la
/// pantalla ya está montada. El tope existe para que una necesidad grande no
/// se convierta en una ráfaga: lo que no entre en esta pasada entra en la
/// siguiente, porque la llave de la lectura la calculan los huecos que quedan.
const int kCatalogNameReadingRecordCap = 60;

/// Cuánto puede durar la persistencia entera. Un servidor lento no puede
/// dejar la lectura escribiendo indefinidamente detrás de una pantalla que el
/// operador ya está usando para otra cosa.
const Duration kCatalogNameReadingRecordBudget = Duration(seconds: 20);

/// **Ensayo: el circuito entero, sin escribir un solo hecho.**
///
/// Existe porque verificar esta pantalla en la app real la haría persistir
/// lecturas de verdad, y una comprobación visual no puede dejar hechos de
/// prueba mezclados con los del taller. En ensayo se lee, se verifica y se
/// cuenta lo que se habría ofrecido; la RPC no se llama nunca.
///
/// Es un `get` y no un `final` a propósito: así un hot reload lo cambia. Se
/// deja en `false`, y se enciende sólo mientras dura una verificación.
bool get catalogNameReadingDryRun => false;

Future<CatalogNameReadingOutcome> readCatalogNamesIntoFicha({
  required List<SupplierNeedSearchField> fields,
  required List<CatalogRowToRead> rows,
  required SupplierSpecExtractor extractor,
  required CatalogReadingRecorder recorder,
  String requestedObject = '',
  int rowCap = kCatalogNameReadingRowCap,
  int recordCap = kCatalogNameReadingRecordCap,
  Duration recordBudget = kCatalogNameReadingRecordBudget,
  Duration deadline = const Duration(seconds: 25),
  SupplierModelReadOwner? owner,

  /// Recorre todo el circuito sin llamar a la RPC. Ver
  /// [catalogNameReadingDryRun].
  bool dryRun = false,

  /// Pares `producto|campo` que ya se le ofrecieron al servidor en pasadas
  /// anteriores de esta misma pantalla. Se saltan, y los de esta pasada se
  /// agregan a medida que se ofrecen.
  ///
  /// **Es lo que le da continuidad al corte.** Sin esta memoria, una pasada
  /// que se corta por el tope volvía a empezar por las mismas lecturas y las
  /// de más atrás no se alcanzaban nunca; y si las primeras eran todas
  /// rechazos, no se guardaba nada, nadie recargaba y ahí quedaba.
  Set<String>? alreadyOffered,

  /// Si la pregunta que originó esta lectura sigue siendo la vigente.
  ///
  /// **El dueño no alcanza.** `SupplierModelReadOwner` se cierra en el
  /// `dispose` de la pantalla, así que si el operador cambia de necesidad
  /// mientras el modelo responde, el dueño sigue abierto y las escrituras de
  /// la necesidad anterior salían igual — sobre productos que ya nadie está
  /// mirando y con los campos de otra pregunta. Se comprueba **antes de cada
  /// escritura**, no una sola vez al empezar: entre la primera RPC y la última
  /// pasan segundos.
  bool Function()? stillCurrent,
}) async {
  const nada = CatalogNameReadingOutcome(
    recorded: 0,
    rejectedByServer: <String>[],
    keptExisting: 0,
    rowsRead: 0,
  );
  if (fields.isEmpty || rows.isEmpty) return nada;

  // Lo ya ofrecido no se vuelve a ofrecer: un rechazo del servidor da el mismo
  // veredicto siempre, y repetirlo consume el tope que necesita lo que viene
  // detrás.
  final ofrecidos = alreadyOffered ?? <String>{};
  final porLeer = <CatalogRowToRead>[
    for (final row in rows)
      if (row.missingFields
          .any((field) => !ofrecidos.contains('${row.productId}|$field')))
        CatalogRowToRead(
          productId: row.productId,
          text: row.text,
          missingFields: <String>{
            for (final field in row.missingFields)
              if (!ofrecidos.contains('${row.productId}|$field')) field,
          },
        ),
  ];
  if (porLeer.isEmpty) return nada;
  rows = porLeer;

  // Sólo se pregunta por lo que falta, y sólo por las filas a las que les
  // falta algo que este campo pueda responder.
  final pedidos = <String>{for (final row in rows) ...row.missingFields};
  final campos = <SupplierNeedSearchField>[
    for (final field in fields)
      if (pedidos.contains(field.key)) field,
  ];
  if (campos.isEmpty) return nada;

  final acotadas = rows.take(rowCap).toList(growable: false);
  // **Lo que el lote no alcanzó a preguntar también queda pendiente.** Las
  // filas más allá del tope ni siquiera entran al `result`, así que sin esto
  // una primera tanda de puros rechazos terminaba con `cutShort = false` y las
  // filas 41 en adelante no se miraban nunca.
  final quedaronFilasFuera = rows.length > acotadas.length;
  final filas = <SupplierSpecExtractionRow>[
    for (final row in acotadas)
      if (row.text.trim().isNotEmpty)
        SupplierSpecExtractionRow(id: row.productId, text: row.text),
  ];
  if (filas.isEmpty) return nada;

  final result = await readSpecsFromRowsWithModel(
    fields: campos,
    rows: filas,
    extractor: extractor,
    requestedObject: requestedObject,
    deadline: deadline,
    owner: owner,
  );
  if (result == null) {
    return CatalogNameReadingOutcome(
      recorded: 0,
      rejectedByServer: const <String>[],
      keptExisting: 0,
      rowsRead: filas.length,
      modelUnavailable: true,
    );
  }

  final faltantes = <String, Set<String>>{
    for (final row in acotadas) row.productId: row.missingFields,
  };
  var guardados = 0;
  var conservados = 0;
  final rechazos = <String>[];
  final fallos = <String>[];
  final reloj = Stopwatch()..start();
  var intentos = 0;
  var cortado = false;
  var quedaronSinOfrecer = false;
  var abandonada = false;
  var ensayadas = 0;

  for (final entry in result.readings.entries) {
    final pendientes = faltantes[entry.key];
    if (pendientes == null) continue;
    for (final lectura in entry.value.values) {
      // **El cliente descarta lo que puede desmentir; el servidor decide lo
      // que cuenta como prueba.** Lo que llega hasta acá ya sobrevivió a la
      // relectura determinista, que tira toda cita que diga otra cosa que el
      // valor —`FRENO DISCO` para `Disco Hidráulico`, `48 MM` para `80`—. Lo
      // que queda es `stated`, que algún lector nuestro reprodujo, o
      // `inferred`, que ninguno reconoció.
      //
      // Las dos se ofrecen, y no es una rebaja: **`inferred` es justo donde
      // vive el valor de esto**. `METALICA` no es literalmente `Metálico` para
      // ningún lector nuestro —el español flexiona el final— y por eso el
      // catálogo entero llevaba años en silencio. El servidor sí sabe
      // resolverlo, porque compara contra el vocabulario que la propia ficha
      // declara, y es él quien tiene la última palabra: acá se ofrece, allá se
      // juzga. Filtrar `inferred` de este lado dejaba fuera exactamente los
      // casos por los que existe esta lectura y no guardaba ni uno.
      if (!pendientes.contains(lectura.field)) continue;
      if (cortado) {
        quedaronSinOfrecer = true;
        continue;
      }
      if (owner?.isClosed ?? false) {
        cortado = true;
        abandonada = true;
        quedaronSinOfrecer = true;
        continue;
      }
      // La vigencia se comprueba acá, pegada a la escritura, y no al empezar.
      if (stillCurrent != null && !stillCurrent()) {
        cortado = true;
        abandonada = true;
        quedaronSinOfrecer = true;
        continue;
      }
      final restante = recordBudget - reloj.elapsed;
      if (intentos >= recordCap || restante <= Duration.zero) {
        cortado = true;
        quedaronSinOfrecer = true;
        continue;
      }
      intentos += 1;
      ofrecidos.add('${entry.key}|${lectura.field}');
      if (dryRun) {
        ensayadas += 1;
        continue;
      }
      try {
        // **El presupuesto es del conjunto, no de cada llamada.** Comprobarlo
        // sólo antes del `await` dejaba que una sola RPC colgada se comiera los
        // veinte segundos enteros y siguiera corriendo detrás de una pantalla
        // que el operador ya está usando. Cada llamada recibe lo que queda.
        final veredicto = await recorder(
          productId: entry.key,
          fieldKey: lectura.field,
          value: lectura.value,
          quote: lectura.quote,
        ).timeout(restante);
        switch (veredicto['verdict']?.toString()) {
          case 'recorded':
            guardados += 1;
          case 'kept_existing':
            conservados += 1;
          default:
            rechazos.add('${entry.key}/${lectura.field}: '
                '${veredicto['reason'] ?? 'sin razón'}');
        }
      } catch (error) {
        // Guardar un hecho puede fallar sin que la pantalla tenga que fallar:
        // lo que no se guardó, simplemente sigue sin verificarse. Pero un
        // fallo NO es un rechazo: no hubo veredicto, así que se puede volver a
        // preguntar, y por eso se saca de lo ya ofrecido.
        fallos.add('${entry.key}/${lectura.field}: $error');
        ofrecidos.remove('${entry.key}|${lectura.field}');
      }
    }
  }

  // **El silencio del modelo también se marca.** Un campo del que no dijo nada
  // da la misma respuesta si se le vuelve a preguntar con el mismo texto, y
  // dejarlo sin marcar hacía que cada vuelta repitiera el mismo lote para
  // siempre. Lo que sí tiene lectura y se quedó sin ofrecer —porque se acabó
  // el tope— NO se marca: ésa es justamente la que la vuelta siguiente tiene
  // que alcanzar.
  // Y no se marca nada si la pregunta cambió a mitad de camino: ahí no se
  // juzgó ni el silencio, y al volver a esa necesidad hay que poder preguntar
  // otra vez exactamente lo mismo.
  if (!abandonada) {
    for (final row in acotadas) {
      for (final field in row.missingFields) {
        final leido =
            result.readings[row.productId]?.containsKey(field) ?? false;
        if (!leido) ofrecidos.add('${row.productId}|$field');
      }
    }
  }

  debugPrint('🧠 lectura del catálogo: ${filas.length} filas, '
      '$guardados hechos guardados, ${rechazos.length} rechazados por el '
      'servidor, ${fallos.length} sin veredicto, $conservados ya tenían dato'
      '${ensayadas > 0 ? ', $ensayadas se habrían ofrecido (ENSAYO)' : ''}'
      '${cortado ? ' (cortada, queda por ofrecer)' : ''}');
  return CatalogNameReadingOutcome(
    recorded: guardados,
    rejectedByServer: List<String>.unmodifiable(rechazos),
    failures: List<String>.unmodifiable(fallos),
    keptExisting: conservados,
    rowsRead: filas.length,
    cutShort: quedaronSinOfrecer || quedaronFilasFuera,
    abandoned: abandonada,
    wouldOffer: ensayadas,
  );
}
