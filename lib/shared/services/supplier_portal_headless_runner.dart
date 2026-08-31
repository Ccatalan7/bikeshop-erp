import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'supplier_availability_service.dart';
import 'supplier_need_portal_search.dart';
import 'supplier_spec_extraction.dart';
import 'supplier_taxonomy_selection.dart';
import 'supplier_portal_probe_service.dart';
import 'supplier_portal_reading.dart';
import 'supplier_portal_session_recovery.dart';
import 'supplier_portal_navigation_queue.dart';
import 'supplier_portal_session_keeper.dart';

/// Confirma disponibilidad **sin ventana y sin operador**.
///
/// Corre en un `HeadlessInAppWebView`: un navegador real, con la misma sesión y
/// las mismas cookies que la pestaña visible —en macOS el almacén de datos del
/// webview es del proceso, y la app no usa modo incógnito— pero sin ocupar
/// pantalla ni robarle el foco a nadie.
///
/// Si la cookie venció, puede pedirle una sola recuperación al límite de
/// credenciales compartido del navegador. Sólo se envía automáticamente un
/// formulario HTTPS ordinario, sin CAPTCHA/OTP, contra el origen exacto
/// registrado. El secreto nunca se guarda ni se registra acá. Si esa
/// recuperación no es posible, `session_expired` sigue siendo un resultado
/// explícito y jamás se disfraza de «sin stock».
/// Interruptor de diagnóstico: apaga la lectura con modelo para aislar si un
/// comportamiento es del lector nuevo o ya estaba en el recorrido del portal.
/// **Aislar el lector nuevo del recorrido del portal.** Puesto en `true` se
/// juzga sólo con lo que el calce sabe leer solo. Sirvió el 2026-08-30 para
/// demostrar que la búsqueda de pedaliers no termina **también sin modelo**:
/// el defecto vive en el recorrido por palabra con navegación de familia, no
/// en la lectura de fichas.
const bool _diagnosticoSinModelo = false;

/// El portal se leyó, pero la lectura no quedó registrada.
///
/// Lleva el resultado consigo para que la pantalla pueda mostrarlo igual y
/// decir la verdad: esto se vio, y no se guardó. Sin esto, un fallo de
/// transporte se veía idéntico a un portal que no contestó.
class SupplierNeedSearchNotPersisted implements Exception {
  const SupplierNeedSearchNotPersisted(this.snapshot, this.request, this.cause);

  final SupplierNeedPortalSearchSnapshot snapshot;

  /// **La pregunta que esta lectura respondió.** Un reintento tiene que
  /// guardar exactamente eso: reconstruirla con los criterios de ahora
  /// estamparía la lectura contra una ficha que no es la que se recorrió, y el
  /// recibo la rechazaría —o peor, la aceptaría mal fechada—.
  final SupplierNeedSearchRequest request;
  final Object cause;

  @override
  String toString() => 'SupplierNeedSearchNotPersisted($cause)';
}

class SupplierPortalHeadlessRunner {
  SupplierPortalHeadlessRunner(
    this._service, {
    SupplierPortalCredentialResolver? credentialResolver,
    SupplierPortalSessionKeeper? sessionKeeper,
    SupplierPortalNavigationQueue? navigationQueue,
    SupplierSpecExtractor? specExtractor,
  })  : _credentialResolver = credentialResolver,
        // **El lector de fichas del proveedor.** Por defecto es el modelo: es
        // lo único que cubre de una vez todas las formas en que un catálogo
        // escribe la misma medida, sin enseñarle una por una. Se inyecta para
        // poder probar el circuito sin red.
        _specExtractor = specExtractor ?? geminiSupplierSpecExtractor(),
        _sessionKeeper = sessionKeeper ?? SupplierPortalSessionKeeper.shared,
        // Compartida a propósito: la cola es del PORTAL, no de esta instancia.
        // El módulo construye un runner nuevo por operación, así que una cola
        // por instancia no serializaría nada.
        _queue = navigationQueue ?? SupplierPortalNavigationQueue.shared;

  final SupplierAvailabilityService _service;
  final SupplierPortalCredentialResolver? _credentialResolver;
  final SupplierPortalSessionKeeper _sessionKeeper;
  final SupplierSpecExtractor _specExtractor;

  static String? _probeSource;

  /// Cada consulta es una navegación real. Ir más rápido no sirve: el portal
  /// de RBX es de los noventa y responde cuando responde.
  static const Duration _settleDelay = Duration(milliseconds: 2200);
  static const Duration _loadTimeout = Duration(seconds: 25);

  /// La taxonomía descubierta, mientras la app viva. La copia durable vive en
  /// la fila del portal; esto sólo evita releerla en cada necesidad.
  static final Map<String, SupplierPortalCatalogTaxonomy> _taxonomyCache =
      <String, SupplierPortalCatalogTaxonomy>{};

  /// **Una sola cola para TODA navegación de un proveedor.**
  ///
  /// La exacta por SKU y la enumeración por necesidad comparten cookie y
  /// sesión: si corren a la vez, la segunda cambia la clasificación de la
  /// primera y las dos informan filas que no son suyas. Ninguna falla; las dos
  /// mienten. Antes sólo la búsqueda por necesidad pedía turno, lo que dejaba
  /// abierta exactamente esa carrera.
  final SupplierPortalNavigationQueue _queue;

  /// Devuelve cuántas quedaron confirmadas y por qué se detuvo, si se detuvo.
  Future<SupplierPortalRunSummary> run({
    required String supplierId,
    required SupplierPortalProbe probe,
    required List<SupplierAvailabilityTarget> targets,
    void Function(int done, int total, String name)? onProgress,
  }) =>
      _queue.run(
        supplierId,
        () => _run(
          supplierId: supplierId,
          probe: probe,
          targets: targets,
          onProgress: onProgress,
        ),
      );

  Future<SupplierPortalRunSummary> _run({
    required String supplierId,
    required SupplierPortalProbe probe,
    required List<SupplierAvailabilityTarget> targets,
    void Function(int done, int total, String name)? onProgress,
  }) async {
    if (targets.isEmpty) {
      return const SupplierPortalRunSummary(checked: 0, stoppedBecause: null);
    }
    _probeSource ??= await rootBundle.loadString(
      'assets/browser/supplier_portal_probe.js',
    );

    Completer<void>? loaded;
    final webView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        // La misma sesión que la pestaña visible: sin esto el chequeo entraría
        // siempre deslogueado y no confirmaría nada.
        incognito: false,
        cacheEnabled: true,
        clearCache: false,
        javaScriptEnabled: true,
        // Nada de ventanas emergentes ni descargas en un contexto que el
        // operador no está mirando.
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
      ),
      onLoadStop: (_, __) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedError: (_, __, ___) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedHttpError: (_, __, ___) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
    );

    var checked = 0;
    String? stoppedBecause;
    try {
      await webView.run();
      final controller = webView.webViewController;
      if (controller == null) {
        return const SupplierPortalRunSummary(
          checked: 0,
          stoppedBecause: 'no_webview',
        );
      }

      Future<void> loadAndSettle(String url) async {
        final pending = Completer<void>();
        loaded = pending;
        await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        await pending.future.timeout(_loadTimeout);
        await Future<void>.delayed(_settleDelay);
      }

      Future<Object?> submitAndWait(String source) async {
        final pending = Completer<void>();
        loaded = pending;
        final result = await controller.evaluateJavascript(source: source);
        if (result?.toString().contains('filled-and-submitted') == true) {
          try {
            await pending.future.timeout(_loadTimeout);
          } on TimeoutException {
            // Algunos portales sustituyen un frame sin completar otra carga
            // principal. El reintento del catálogo demostrará la sesión.
          }
          await Future<void>.delayed(_settleDelay);
        }
        return result;
      }

      Future<bool> recoverSession() async {
        final result = await recoverSupplierPortalSession(
          supplierId: supplierId,
          loginUrl: probe.sessionLoginUrl,
          resolveCredential: _credentialResolver,
          loadLoginPage: loadAndSettle,
          currentUrl: () async => (await controller.getUrl())?.toString(),
          evaluateJavascript: (source) =>
              controller.evaluateJavascript(source: source),
          submitLogin: submitAndWait,
        );
        return result.submitted;
      }

      var sessionRecoveryAttempted = false;
      targetsLoop:
      for (var index = 0; index < targets.length; index++) {
        final target = targets[index];
        onProgress?.call(index, targets.length, target.name);
        final url = probe.urlForCode(target.supplierCode);

        while (true) {
          try {
            await loadAndSettle(url);
          } on TimeoutException {
            // Una página que no termina de cargar no es un cero: se anota como
            // ilegible y se sigue con la siguiente.
            await _record(
                supplierId,
                target,
                url,
                const SupplierPortalReading(
                  status: SupplierAvailabilityStatus.unreadable,
                ),
                '');
            checked++;
            continue targetsLoop;
          }

          await controller.evaluateJavascript(source: _probeSource!);
          final raw = await controller.evaluateJavascript(
            source: 'JSON.stringify(globalThis.__vinabikeSupplierProbe.probe('
                '${jsonEncode(target.supplierCode)}))',
          );
          final report = SupplierPortalProbeService.decodeReport(raw);
          if (report == null) {
            await _record(
                supplierId,
                target,
                url,
                const SupplierPortalReading(
                  status: SupplierAvailabilityStatus.unreadable,
                ),
                '');
            checked++;
            continue targetsLoop;
          }
          final body = report['bodySample']?.toString() ?? '';
          final session = report['session'];
          final reading = readSupplierPortal(
            SupplierPortalObservation(
              code: target.supplierCode,
              url: url,
              bodyText: body,
              hasPasswordField:
                  session is Map && session['hasPasswordField'] == true,
            ),
            probe,
          );

          if (reading.status == SupplierAvailabilityStatus.sessionExpired &&
              !sessionRecoveryAttempted) {
            sessionRecoveryAttempted = true;
            onProgress?.call(
              index,
              targets.length,
              'Recuperando sesión de proveedor',
            );
            if (await recoverSession()) {
              // La misma pregunta se repite una sola vez. Sólo esa respuesta
              // se persiste; la pantalla de login nunca contamina evidencia.
              continue;
            }
          }

          await _record(supplierId, target, url, reading, body);
          checked++;

          if (reading.status != SupplierAvailabilityStatus.sessionExpired &&
              reading.status != SupplierAvailabilityStatus.unreadable) {
            _sessionKeeper.activate(supplierId: supplierId, url: url);
          }

          // Sin sesión y sin recuperación segura, seguir escribiría la misma
          // pantalla de login para todos los productos.
          if (reading.status == SupplierAvailabilityStatus.sessionExpired) {
            stoppedBecause = 'session_expired';
            break targetsLoop;
          }
          continue targetsLoop;
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🛒 Chequeo de disponibilidad interrumpido: $error');
      }
      stoppedBecause ??= 'error';
    } finally {
      await webView.dispose();
    }
    return SupplierPortalRunSummary(
      checked: checked,
      stoppedBecause: stoppedBecause,
    );
  }

  /// Busca la necesidad abierta, no el barrido de reposición del proveedor.
  ///
  /// **El buscador del proveedor es un índice, no una autoridad.** Sirve para
  /// encontrar dónde vive una familia; nunca para acotar cuánto existe. Por eso
  /// el camino normal enumera el nodo de taxonomía completo, página por página,
  /// y sólo cae al buscador por palabra cuando el portal no publica una ruta de
  /// catálogo. Después el calce ocurre en Dart contra los predicados técnicos ya
  /// interpretados: el portal no decide qué es exacto y una IA no completa las
  /// medidas que el portal omitió.
  ///
  /// Lo que esta función SIEMPRE devuelve, además del resultado, es cuánto
  /// alcanzó a mirar. Sin ese dato «10 filas de la página 1» se lee idéntico a
  /// «el proveedor tiene 10», que es el defecto que originó todo esto.
  Future<SupplierNeedPortalSearchSnapshot> runNeedSearch({
    required String supplierId,
    required SupplierPortalProbe probe,
    required SupplierNeedSearchRequest request,
    void Function(String message)? onProgress,
  }) =>
      // **Una sesión, una navegación a la vez.** El portal es un ASP legacy con
      // estado por sesión y las dos consultas comparten la misma cookie: dos
      // recorridos en paralelo se pisan y ninguno de los dos se entera.
      _queue.run(
        supplierId,
        () => _runNeedSearch(
          supplierId: supplierId,
          probe: probe,
          request: request,
          onProgress: onProgress,
        ),
      );

  Future<SupplierNeedPortalSearchSnapshot> _runNeedSearch({
    required String supplierId,
    required SupplierPortalProbe probe,
    required SupplierNeedSearchRequest request,
    void Function(String message)? onProgress,
  }) async {
    final plan = probe.planForNeed(request);
    if (plan == null) {
      throw StateError('Supplier probe cannot search this need family');
    }
    // **Antes de tocar el portal.** Esta corrida ya tiene identidad, así que
    // si el guardado muere en el transporte se puede preguntar si entró y
    // reintentarla sin volver a navegar ni a invocar al modelo. Generarla
    // después convertiría cada reintento en una operación distinta.
    final runOperationKey =
        'portal-search:$supplierId:${request.needId}:${const Uuid().v4()}';
    // Se decide dentro del recorrido y se lee al cerrar: por eso vive acá.
    // El desenlace lo traduce `supplierPortalSessionOutcome`, que es la pieza
    // que las pruebas pueden ejercitar sin abrir un navegador.
    var sessionOutcome = SupplierPortalSessionOutcome.continueRun;
    final queries = plan.recallOrderedQueries;
    final primaryQuery = queries.isEmpty ? plan.query : queries.first;
    final primaryUrl = probe.urlForNeedQuery(primaryQuery);
    if (primaryUrl == null || primaryQuery.isEmpty || queries.isEmpty) {
      throw StateError('Supplier probe cannot search needs');
    }
    var lastInitialUrl = plan.initialUrlFor(primaryUrl);
    _probeSource ??= await rootBundle.loadString(
      'assets/browser/supplier_portal_probe.js',
    );

    Completer<void>? loaded;
    String? alertMessage;
    final webView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        incognito: false,
        cacheEnabled: true,
        clearCache: false,
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
      ),
      onLoadStop: (_, __) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedError: (_, __, ___) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedHttpError: (_, __, ___) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      // RBX anuncia «sin resultados» con un alert y redirige. Se confirma el
      // diálogo para que el navegador no quede bloqueado y se conserva el
      // texto: la página posterior ya no contiene esa evidencia.
      onJsAlert: (_, request) async {
        alertMessage = request.message;
        return JsAlertResponse(
          handledByClient: true,
          action: JsAlertResponseAction.CONFIRM,
        );
      },
    );

    SupplierNeedPortalSearchSnapshot? snapshot;
    var evidence = '';
    final navigationEvidence = <String>[];
    try {
      await webView.run();
      final controller = webView.webViewController;
      if (controller == null) {
        snapshot = SupplierNeedPortalSearchSnapshot(
          query: primaryQuery,
          status: SupplierNeedPortalSearchStatus.unreadable,
          checkedAt: DateTime.now().toUtc(),
          searchRevisionNo: request.revisionNo,
          currentRevisionNo: request.revisionNo,
          matches: const <SupplierNeedPortalMatch>[],
          sourceUrl: sanitizeSupplierNeedPortalEvidenceUrl(primaryUrl),
          coverage: const SupplierNeedPortalCoverage.unknown(),
        );
      } else {
        Future<void> loadAndSettle(String targetUrl) async {
          final pending = Completer<void>();
          loaded = pending;
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(targetUrl)),
          );
          await pending.future.timeout(_loadTimeout);
          await Future<void>.delayed(_settleDelay);
        }

        Future<Object?> submitAndWait(String source) async {
          final pending = Completer<void>();
          loaded = pending;
          final result = await controller.evaluateJavascript(source: source);
          if (result?.toString().contains('filled-and-submitted') == true) {
            try {
              await pending.future.timeout(_loadTimeout);
            } on TimeoutException {
              // El reintento autoritativo del catálogo decide si prendió.
            }
            await Future<void>.delayed(_settleDelay);
          }
          return result;
        }

        // **Una recuperación que exige a una persona NO se sigue esperando.**
        // El portal de RBX publica su ingreso por HTTPS pero su formulario
        // legacy envía por HTTP, y el preflight se niega —por contrato— a
        // revelar el secreto en claro. Entonces `interactionRequired` no es un
        // «todavía no»: es un «acá no puede ser sin una persona». Seguir
        // enumerando y después intentar guardar dejaba el spinner
        // «Recuperando la sesión…» dos minutos para terminar igual en sesión
        // vencida. Se corta al tiro y la superficie ofrece abrir el portal.
        Future<bool> recoverSession() async {
          onProgress?.call('Recuperando la sesión del proveedor…');
          final result = await recoverSupplierPortalSession(
            supplierId: supplierId,
            loginUrl: probe.sessionLoginUrl,
            resolveCredential: _credentialResolver,
            loadLoginPage: loadAndSettle,
            currentUrl: () async => (await controller.getUrl())?.toString(),
            evaluateJavascript: (source) =>
                controller.evaluateJavascript(source: source),
            submitLogin: submitAndWait,
          );
          sessionOutcome = supplierPortalSessionOutcome(result.status);
          if (sessionOutcome == SupplierPortalSessionOutcome.needsPerson) {
            onProgress?.call(
              'Este portal necesita que alguien inicie sesión.',
            );
          }
          return result.submitted;
        }

        Future<Map<String, dynamic>?> evaluateProbe(String call) async {
          await controller.evaluateJavascript(source: _probeSource!);
          final raw = await controller.evaluateJavascript(
            source: 'JSON.stringify(globalThis.__vinabikeSupplierProbe.$call)',
          );
          return SupplierPortalProbeService.decodeReport(raw);
        }

        // ── Camino normal: enumerar el nodo de taxonomía ──────────────────
        Future<SupplierPortalCatalogTaxonomy?> ensureTaxonomy() async {
          final discovery = plan.taxonomyDiscovery;
          if (discovery == null) return null;
          final known = _taxonomyCache[supplierId] ?? probe.catalogTaxonomy;
          if (known != null &&
              known.isFresh(discovery.ttl) &&
              plan.rankNodes(known).isNotEmpty) {
            return known;
          }
          onProgress?.call('Leyendo las categorías del proveedor…');
          await loadAndSettle(discovery.url);
          var discovered = await _readTaxonomy(evaluateProbe, discovery);
          if (discovered != null && plan.rankNodes(discovered).isEmpty) {
            // El documento inicial sólo trae los hijos del padre elegido. Se
            // abren SÓLO los padres que ya calzan con la familia pedida: abrir
            // los veinte sería un barrido del proveedor, no un descubrimiento.
            discovered = await _probeParents(
              plan: plan,
              discovery: discovery,
              known: discovered,
              evaluateProbe: evaluateProbe,
            );
          }
          if (discovered == null || discovered.isEmpty) return known;
          final merged =
              known == null ? discovered : known.mergedWith(discovered);
          _taxonomyCache[supplierId] = merged;
          unawaited(_service
              .recordCatalogTaxonomy(supplierId: supplierId, taxonomy: merged)
              .catchError((_) {}));
          return merged;
        }

        Future<SupplierNeedPortalSearchSnapshot?> enumerateTaxonomy() async {
          final route = plan.catalogRoute;
          if (route == null) return null;
          if (!supplierPortalRunMayContinue(sessionOutcome)) return null;
          final taxonomy = await ensureTaxonomy();
          // **Dónde buscar lo decide el catálogo del proveedor, no una lista
          // nuestra.** El punteo por vocabulario exige que alguien escriba las
          // palabras de cada familia antes de poder buscarla; la taxonomía ya
          // está descubierta, así que se le pregunta al modelo cuál de esos
          // rótulos puede contener la pieza. Si no hay modelo o su respuesta
          // no sirve, se usa el punteo de siempre: quedarse sin buscar sería
          // peor. El modelo no decide si un producto cumple — sólo dónde
          // mirar—, y lo que se miró queda dicho en la cobertura.
          final nodes = await chooseSupplierTaxonomyNodes(
            taxonomy: taxonomy,
            requestedObject: request.description,
            fallback: plan.rankNodes(taxonomy),
            limit: plan.budget.maxNodes,
            excludedTerms: plan.excludedTerms,
            extractor: _diagnosticoSinModelo ? null : _specExtractor,
          );
          if (nodes.isEmpty) return null;
          final available = countSupplierTaxonomyCandidates(
            taxonomy: taxonomy,
            familyTerms: plan.familyTerms,
            excludedTerms: plan.excludedTerms,
          );
          final enumerator = SupplierNeedCatalogEnumerator(
            route: route,
            budget: plan.budget,
            nodes: nodes,
            nodesAvailable: available,
          );
          var lastUrl = lastInitialUrl;
          while (true) {
            final step = enumerator.next();
            if (step == null) break;
            lastUrl = step.url;
            lastInitialUrl = step.url;
            onProgress?.call(
              'Revisando «${step.node.label}», página ${step.page}…',
            );
            SupplierNeedCatalogPageResult page;
            try {
              await loadAndSettle(step.url);
              page = await _readCatalogPage(
                evaluateProbe: evaluateProbe,
                plan: plan,
                probe: probe,
              );
            } on TimeoutException {
              page = const SupplierNeedCatalogPageResult.transportFailed();
            }
            enumerator.offer(page);
            if (page.sessionExpired || page.transportFailed) break;
            _sessionKeeper.activate(supplierId: supplierId, url: step.url);
          }

          // Mismo lector que en la búsqueda por palabra: el modelo lee la
          // ficha de cada fila y la compuerta descarta lo que no puede
          // comprobar contra el texto del proveedor.
          final leidas = _diagnosticoSinModelo
              ? dedupeSupplierPortalCandidates(enumerator.candidates).unique
              : await readSupplierSpecsWithModel(
                  fields: plan.request.fields,
                  candidates: dedupeSupplierPortalCandidates(
                    enumerator.candidates,
                  ).unique,
                  // **Los dos recorridos hacen la misma pregunta de objeto.**
                  // La enumeración por taxonomía no la pasaba, así que juzgaba
                  // la identidad con otra vara que la búsqueda por palabra.
                  requestedObject: plan.requestedObjectLabel,
                  extractor: _specExtractor,
                );
          // **Y lo que ninguna ficha sabe preguntar, se le pregunta igual.**
          // «A ambos lados» o «de kevlar» no son campos de ninguna plantilla:
          // sin esto, lo único que podía decirse de ellas era si la palabra
          // aparecía literal. La lectura viaja con la fila y no cambia el
          // veredicto —el texto sigue mandando—; sirve para decirle al operador
          // qué dijo el proveedor sobre la parte que nadie modeló.
          final conExigencias = _diagnosticoSinModelo
              ? leidas
              : attachSupplierRequirementReadings(
                  candidates: leidas,
                  readings: await readSupplierRequirementsWithModel(
                    rows: <SupplierSpecExtractionRow>[
                      for (final candidate in leidas)
                        if (candidate.code.trim().isNotEmpty)
                          SupplierSpecExtractionRow(
                            id: candidate.code.trim(),
                            text: <String?>[candidate.name, candidate.rowText]
                                .whereType<String>()
                                .where((value) => value.trim().isNotEmpty)
                                .join(' · '),
                          ),
                    ],
                    requirements: supplyNeedUnmodelledRequirements(plan),
                    extractor: _specExtractor,
                  ),
                );
          final matches = matchSupplierNeedCandidates(plan, conExigencias);
          debugPrint('🛒 taxonomía: ${leidas.length} filas leídas, '
              '${matches.length} calzadas — a guardar');
          // **Un tope de payload que trunca en silencio es un dato falso.** Se
          // recorta por estado —lo probado primero— y el recorte queda dicho en
          // la cobertura, que deja de poder declararse completa.
          final kept = matches.length > plan.resultCap
              ? matches.sublist(0, plan.resultCap)
              : matches;
          var coverage = enumerator.coverage(rowsPersisted: kept.length);
          final broken = !coverage.isActionable;
          final status =
              coverage.limit == SupplierNeedCoverageLimit.sessionExpired
                  ? SupplierNeedPortalSearchStatus.sessionExpired
                  : broken
                      ? SupplierNeedPortalSearchStatus.unreadable
                      : kept.isEmpty
                          ? SupplierNeedPortalSearchStatus.noMatches
                          : SupplierNeedPortalSearchStatus.completed;
          if (broken) {
            // Las filas se vieron, pero sus ausencias no significan nada: se
            // conservan como conteo en la cobertura, nunca como opciones.
            coverage = enumerator.coverage(rowsPersisted: 0);
          }
          evidence = _needSearchCoverageEvidence(
            plan: plan,
            coverage: coverage,
            taxonomy: taxonomy,
          );
          return SupplierNeedPortalSearchSnapshot(
            query: plan.broadQuery,
            status: status,
            checkedAt: DateTime.now().toUtc(),
            searchRevisionNo: request.revisionNo,
            currentRevisionNo: request.revisionNo,
            matches: broken ? const <SupplierNeedPortalMatch>[] : kept,
            sourceUrl: sanitizeSupplierNeedPortalEvidenceUrl(lastUrl),
            coverage: coverage,
          );
        }

        // ── Peldaño de abajo: el buscador por palabra ─────────────────────
        Future<SupplierNeedPortalSearchSnapshot> executeWordSearch() async {
          SupplierNeedPortalSearchSnapshot? lastSnapshot;
          for (var queryIndex = 0; queryIndex < queries.length; queryIndex++) {
            final query = queries[queryIndex];
            final url = probe.urlForNeedQuery(query);
            if (url == null || query.isEmpty) continue;
            final initialUrl = plan.initialUrlFor(url);
            lastInitialUrl = initialUrl;
            alertMessage = null;
            navigationEvidence.clear();
            onProgress?.call('Buscando «$query» en el portal…');
            await loadAndSettle(initialUrl);
            final initialReport = await evaluateProbe('discover()');
            final initialSourceUrl =
                initialReport?['url']?.toString() ?? initialUrl;
            final initialSessionExpired = initialReport != null &&
                supplierNeedPortalSessionExpired(
                  sourceUrl: initialSourceUrl,
                  report: initialReport,
                  loggedOutPattern: probe.loggedOutPattern,
                  sessionErrorPattern: plan.adapter.sessionErrorPattern,
                );
            if (initialSessionExpired) {
              evidence = _needSearchEvidence(
                stage: 'session_check',
                report: initialReport,
                plan: plan,
              );
              return SupplierNeedPortalSearchSnapshot(
                query: query,
                status: SupplierNeedPortalSearchStatus.sessionExpired,
                checkedAt: DateTime.now().toUtc(),
                searchRevisionNo: request.revisionNo,
                currentRevisionNo: request.revisionNo,
                matches: const <SupplierNeedPortalMatch>[],
                sourceUrl:
                    sanitizeSupplierNeedPortalEvidenceUrl(initialSourceUrl),
                coverage: _wordSearchCoverage(
                  limit: SupplierNeedCoverageLimit.sessionExpired,
                ),
              );
            }

            for (final step in plan.family.navigation) {
              // Un selector puede navegar sólo el frame que contiene el
              // formulario. La sonda del documento anterior deja de existir,
              // por eso se inyecta antes de cada paso configurado.
              final stepReport = await evaluateProbe(
                'selectOption(${jsonEncode(step.fieldName)},'
                '${jsonEncode(step.optionText)})',
              );
              navigationEvidence.add('${step.fieldName}:selected');
              if (kDebugMode) {
                debugPrint('🛒 Navegación de catálogo: '
                    '${jsonEncode(stepReport)}');
              }
              if (stepReport?['ok'] != true) {
                throw StateError(
                  'Configured supplier navigation is not available',
                );
              }
              await Future<void>.delayed(_settleDelay);
            }
            final report = await evaluateProbe(
              'search(${jsonEncode(query)},'
              '${jsonEncode(plan.resultSchema.toProbeJson())},'
              '${plan.resultCap})',
            );
            if (report == null) {
              return SupplierNeedPortalSearchSnapshot(
                query: query,
                status: SupplierNeedPortalSearchStatus.unreadable,
                checkedAt: DateTime.now().toUtc(),
                searchRevisionNo: request.revisionNo,
                currentRevisionNo: request.revisionNo,
                matches: const <SupplierNeedPortalMatch>[],
                sourceUrl: sanitizeSupplierNeedPortalEvidenceUrl(url),
                coverage: _wordSearchCoverage(
                  limit: SupplierNeedCoverageLimit.transport,
                ),
              );
            }

            evidence = _needSearchEvidence(
              stage: 'results',
              report: report,
              plan: plan,
              navigation: navigationEvidence,
            );
            final sourceUrl = report['url']?.toString() ?? url;
            final loggedOut = supplierNeedPortalSessionExpired(
              sourceUrl: sourceUrl,
              report: report,
              loggedOutPattern: probe.loggedOutPattern,
              sessionErrorPattern: plan.adapter.sessionErrorPattern,
            );
            final rawResults = report['results'];
            final candidates = rawResults is List
                ? rawResults
                    .whereType<Map>()
                    .map((entry) => SupplierPortalCatalogCandidate.fromJson(
                          Map<String, dynamic>.from(entry),
                        ))
                    .where((candidate) =>
                        candidate.code.isNotEmpty && candidate.name.isNotEmpty)
                    .toList(growable: false)
                : const <SupplierPortalCatalogCandidate>[];
            final noResultsAlert = _matchesNoResultAlert(
              alertMessage,
              plan.resultSchema.noResultPhrases,
            );
            final unique = dedupeSupplierPortalCandidates(candidates).unique;
            final status = loggedOut
                ? SupplierNeedPortalSearchStatus.sessionExpired
                : unique.isNotEmpty
                    ? SupplierNeedPortalSearchStatus.completed
                    : report['noResults'] == true || noResultsAlert
                        ? SupplierNeedPortalSearchStatus.noMatches
                        : SupplierNeedPortalSearchStatus.unreadable;
            // El modelo lee la ficha de cada fila ANTES de juzgar, y la
            // compuerta descarta lo que no pueda comprobar contra el texto.
            // Si no hay modelo, `unique` vuelve intacto y el calce sigue con
            // lo que sabe leer solo: se lee menos, nunca se rompe.
            final leidas = loggedOut || _diagnosticoSinModelo
                ? unique
                : await readSupplierSpecsWithModel(
                    fields: plan.request.fields,
                    candidates: unique,
                    // El OBJETO, no el pedido: preguntarle por la petición
                    // completa le hacía contestar compatibilidad con el campo
                    // de identidad.
                    requestedObject: plan.requestedObjectLabel,
                    extractor: _specExtractor,
                  );
            // Los dos recorridos preguntan lo mismo: la búsqueda por palabra
            // no puede juzgar una exigencia fuera de ficha con menos que la
            // enumeración por taxonomía.
            final conExigencias = loggedOut || _diagnosticoSinModelo
                ? leidas
                : attachSupplierRequirementReadings(
                    candidates: leidas,
                    readings: await readSupplierRequirementsWithModel(
                      rows: <SupplierSpecExtractionRow>[
                        for (final candidate in leidas)
                          if (candidate.code.trim().isNotEmpty)
                            SupplierSpecExtractionRow(
                              id: candidate.code.trim(),
                              text: <String?>[candidate.name, candidate.rowText]
                                  .whereType<String>()
                                  .where((value) => value.trim().isNotEmpty)
                                  .join(' · '),
                            ),
                      ],
                      requirements: supplyNeedUnmodelledRequirements(plan),
                      extractor: _specExtractor,
                    ),
                  );
            final matches = loggedOut
                ? const <SupplierNeedPortalMatch>[]
                : matchSupplierNeedCandidates(plan, conExigencias);
            final kept = matches.length > plan.resultCap
                ? matches.sublist(0, plan.resultCap)
                : matches;
            final currentSnapshot = SupplierNeedPortalSearchSnapshot(
              query: query,
              status: status,
              checkedAt: DateTime.now().toUtc(),
              searchRevisionNo: request.revisionNo,
              currentRevisionNo: request.revisionNo,
              matches: kept,
              sourceUrl: sanitizeSupplierNeedPortalEvidenceUrl(sourceUrl),
              coverage: _wordSearchCoverage(
                limit: loggedOut
                    ? SupplierNeedCoverageLimit.sessionExpired
                    : SupplierNeedCoverageLimit.wordSearchOnly,
                rowsObserved: candidates.length,
                rowsUnique: unique.length,
                rowsPersisted: kept.length,
              ),
            );
            lastSnapshot = currentSnapshot;
            // **`possible` no puede cortar la búsqueda.** «Posible» significa
            // que NO se pudo probar la ficha; tratar filas sin probar como
            // suficientes para dejar de buscar invierte el contrato
            // eliminate-then-rank, y es lo que dejó 18 cámaras en 10.
            if (currentSnapshot.status ==
                    SupplierNeedPortalSearchStatus.sessionExpired ||
                currentSnapshot.status ==
                    SupplierNeedPortalSearchStatus.completed ||
                currentSnapshot.status ==
                    SupplierNeedPortalSearchStatus.noMatches) {
              return currentSnapshot;
            }
          }
          return lastSnapshot ??
              SupplierNeedPortalSearchSnapshot(
                query: primaryQuery,
                status: SupplierNeedPortalSearchStatus.unreadable,
                checkedAt: DateTime.now().toUtc(),
                searchRevisionNo: request.revisionNo,
                currentRevisionNo: request.revisionNo,
                matches: const <SupplierNeedPortalMatch>[],
                sourceUrl: sanitizeSupplierNeedPortalEvidenceUrl(primaryUrl),
                coverage: _wordSearchCoverage(
                  limit: SupplierNeedCoverageLimit.transport,
                ),
              );
        }

        Future<SupplierNeedPortalSearchSnapshot> executeAttempt() async {
          if (plan.canBrowseTaxonomy) {
            final byTaxonomy = await enumerateTaxonomy();
            if (byTaxonomy != null && !_shouldFallBack(byTaxonomy)) {
              return byTaxonomy;
            }
            if (byTaxonomy != null &&
                byTaxonomy.status ==
                    SupplierNeedPortalSearchStatus.sessionExpired) {
              return byTaxonomy;
            }
          }
          return executeWordSearch();
        }

        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            snapshot = await executeAttempt();
          } on TimeoutException {
            snapshot = SupplierNeedPortalSearchSnapshot(
              query: primaryQuery,
              status: SupplierNeedPortalSearchStatus.unreadable,
              checkedAt: DateTime.now().toUtc(),
              searchRevisionNo: request.revisionNo,
              currentRevisionNo: request.revisionNo,
              matches: const <SupplierNeedPortalMatch>[],
              sourceUrl: sanitizeSupplierNeedPortalEvidenceUrl(primaryUrl),
              coverage: _wordSearchCoverage(
                limit: SupplierNeedCoverageLimit.transport,
              ),
            );
          }
          if (snapshot.status !=
                  SupplierNeedPortalSearchStatus.sessionExpired ||
              attempt > 0 ||
              !supplierPortalRunMayContinue(sessionOutcome) ||
              !await recoverSession()) {
            break;
          }
          evidence = '';
          onProgress?.call('Sesión recuperada. Buscando de nuevo…');
        }
      }
    } catch (error) {
      if (evidence.isEmpty && navigationEvidence.isNotEmpty) {
        evidence = jsonEncode(<String, dynamic>{
          'stage': 'navigation',
          'route': _needSearchRouteEvidence(plan),
          'steps': navigationEvidence,
        });
      }
      if (kDebugMode) {
        debugPrint('🛒 Búsqueda de necesidad interrumpida: $error');
      }
      snapshot ??= SupplierNeedPortalSearchSnapshot(
        query: primaryQuery,
        status: SupplierNeedPortalSearchStatus.unreadable,
        checkedAt: DateTime.now().toUtc(),
        searchRevisionNo: request.revisionNo,
        currentRevisionNo: request.revisionNo,
        matches: const <SupplierNeedPortalMatch>[],
        sourceUrl: sanitizeSupplierNeedPortalEvidenceUrl(primaryUrl),
        coverage: const SupplierNeedPortalCoverage.unknown(),
      );
    } finally {
      await webView.dispose();
    }

    final completedSnapshot = snapshot ??
        SupplierNeedPortalSearchSnapshot(
          query: primaryQuery,
          status: SupplierNeedPortalSearchStatus.unreadable,
          checkedAt: DateTime.now().toUtc(),
          searchRevisionNo: request.revisionNo,
          currentRevisionNo: request.revisionNo,
          matches: const <SupplierNeedPortalMatch>[],
          sourceUrl: sanitizeSupplierNeedPortalEvidenceUrl(primaryUrl),
          coverage: const SupplierNeedPortalCoverage.unknown(),
        );
    if (completedSnapshot.status == SupplierNeedPortalSearchStatus.completed ||
        completedSnapshot.status == SupplierNeedPortalSearchStatus.noMatches) {
      _sessionKeeper.activate(supplierId: supplierId, url: lastInitialUrl);
    }
    // **La identidad de la corrida se fija antes de abrir el portal.** Si se
    // generara al guardar, un reintento sería otra operación y duplicaría el
    // recibo de una lectura que costó minutos de navegación real.
    final stamped = completedSnapshot.withOperationKey(runOperationKey);
    // **Una sesión que exige a una persona no deja recibo que valga.** No hay
    // filas, la cobertura no afirma nada, y el intento de guardarlo cuesta hoy
    // dos minutos de gateway para terminar en el mismo lugar. Se devuelve para
    // que la superficie ofrezca abrir el portal, sin escribir nada.
    if (!supplierPortalRunShouldRecord(sessionOutcome)) return stamped;
    try {
      await _service.recordNeedSearch(
        supplierId: supplierId,
        request: request,
        snapshot: stamped,
        evidenceSample: evidence,
      );
    } catch (error) {
      if (kDebugMode) {
        // **Un fallo sin motivo cuesta una ronda entera.** Sólo el tipo no
        // dice nada: `PostgrestException` puede ser un CHECK, un tope o una
        // política. El mensaje del servidor ya está escrito para el negocio.
        final detalle = error is PostgrestException
            ? '${error.code ?? 'sin código'}: ${error.message}'
            : error.toString();
        debugPrint('🛒 No se pudo guardar la búsqueda de necesidad: '
            '${error.runtimeType} — $detalle');
      }
      // **Leer el portal y no poder guardarlo no es lo mismo que no haberlo
      // leído.** Antes esto subía como un error cualquiera y la página decía
      // «No se pudo buscar»: el operador perdía una lectura completa —minutos
      // de navegación real— sin enterarse de que existía. Medido el
      // 2026-08-30: cuatro corridas seguidas murieron acá con `504 upstream
      // request timeout` del gateway, con la RPC respondiendo en 7 ms.
      throw SupplierNeedSearchNotPersisted(stamped, request, error);
    }
    return completedSnapshot;
  }

  /// Sólo se baja al buscador por palabra cuando la ruta de catálogo no pudo
  /// usarse. Una cobertura completa con cero filas es una respuesta —«no lo
  /// tiene»—, y volver a preguntar por palabra la degradaría a una peor.
  bool _shouldFallBack(SupplierNeedPortalSearchSnapshot snapshot) =>
      snapshot.coverage.limit == SupplierNeedCoverageLimit.parserDrift ||
      snapshot.coverage.limit == SupplierNeedCoverageLimit.transport ||
      snapshot.coverage.limit == SupplierNeedCoverageLimit.notAttempted;

  SupplierNeedPortalCoverage _wordSearchCoverage({
    required SupplierNeedCoverageLimit limit,
    int rowsObserved = 0,
    int rowsUnique = 0,
    int rowsPersisted = 0,
  }) =>
      SupplierNeedPortalCoverage(
        method: SupplierNeedCoverageMethod.wordSearch,
        // El buscador por palabra JAMÁS declara cobertura completa: no recorre
        // el catálogo, sólo su índice de texto.
        isComplete: false,
        limit: limit,
        rowsObserved: rowsObserved,
        rowsUnique: rowsUnique,
        rowsPersisted: rowsPersisted,
        checkedAt: DateTime.now().toUtc(),
      );

  Future<SupplierNeedCatalogPageResult> _readCatalogPage({
    required Future<Map<String, dynamic>?> Function(String call) evaluateProbe,
    required SupplierNeedSearchPlan plan,
    required SupplierPortalProbe probe,
  }) async {
    final report = await evaluateProbe(
      'page(${jsonEncode(plan.resultSchema.toProbeJson())},'
      '${plan.budget.maxRows})',
    );
    if (report == null) {
      return const SupplierNeedCatalogPageResult.transportFailed();
    }
    final sourceUrl = report['url']?.toString() ?? '';
    if (supplierNeedPortalSessionExpired(
      sourceUrl: sourceUrl,
      report: report,
      loggedOutPattern: probe.loggedOutPattern,
      sessionErrorPattern: plan.adapter.sessionErrorPattern,
    )) {
      return const SupplierNeedCatalogPageResult.sessionExpired();
    }
    final rawResults = report['results'];
    final candidates = rawResults is List
        ? rawResults
            .whereType<Map>()
            .map((entry) => SupplierPortalCatalogCandidate.fromJson(
                  Map<String, dynamic>.from(entry),
                ))
            .where((candidate) =>
                candidate.code.isNotEmpty && candidate.name.isNotEmpty)
            .toList(growable: false)
        : const <SupplierPortalCatalogCandidate>[];
    return SupplierNeedCatalogPageResult(
      candidates: candidates,
      schemaMatched: report['schemaMatched'] == true,
      tablesSeen: (report['tablesSeen'] as num?)?.round() ?? 0,
      // Se comprueba en las dos capas: la sonda mira el documento y acá se
      // mira el texto que llegó. Un `Content-Type` sin charset deja que el
      // navegador adivine, y una adivinanza mala se lee como catálogo vacío.
      misdecoded: report['misdecoded'] == true ||
          supplierPortalTextLooksMisdecoded(
            report['bodySample']?.toString() ?? '',
          ),
    );
  }

  Future<SupplierPortalCatalogTaxonomy?> _readTaxonomy(
    Future<Map<String, dynamic>?> Function(String call) evaluateProbe,
    SupplierNeedPortalTaxonomyDiscovery discovery,
  ) async {
    final report = await evaluateProbe(
      'taxonomy([${jsonEncode(discovery.parentField)},'
      '${jsonEncode(discovery.childField)}])',
    );
    if (report == null) return null;
    final fields = report['fields'];
    if (fields is! List) return null;
    Map<String, dynamic>? fieldNamed(String name) {
      for (final entry in fields.whereType<Map>()) {
        final map = Map<String, dynamic>.from(entry);
        if (map['field']?.toString() == name) return map;
      }
      return null;
    }

    final parent = fieldNamed(discovery.parentField);
    final child = fieldNamed(discovery.childField);
    if (child == null) return null;
    final selectedParent = parent?['selected']?.toString();
    String? parentLabel;
    for (final option in _options(parent)) {
      if (option.$1 == selectedParent) parentLabel = option.$2;
    }
    final nodes = <SupplierPortalTaxonomyNode>[
      for (final option in _options(child))
        SupplierPortalTaxonomyNode(
          id: option.$1,
          label: option.$2,
          parentId: selectedParent,
          parentLabel: parentLabel,
        ),
    ];
    return SupplierPortalCatalogTaxonomy.fromNodes(
      nodes,
      discoveredAt: DateTime.now().toUtc(),
    );
  }

  List<(String, String)> _options(Map<String, dynamic>? field) {
    final raw = field?['options'];
    if (raw is! List) return const <(String, String)>[];
    return raw
        .whereType<Map>()
        .map((entry) => (
              entry['value']?.toString().trim() ?? '',
              entry['text']?.toString().trim() ?? '',
            ))
        .where((option) => option.$1.isNotEmpty && option.$2.isNotEmpty)
        .toList(growable: false);
  }

  /// Abre los padres que ya calzan con la familia para poblar sus hijos.
  ///
  /// El presupuesto existe porque un descubrimiento no es un barrido: abrir
  /// las veinte clasificaciones de un proveedor para buscar cámaras es
  /// recorrerle el catálogo entero con otro nombre.
  Future<SupplierPortalCatalogTaxonomy?> _probeParents({
    required SupplierNeedSearchPlan plan,
    required SupplierNeedPortalTaxonomyDiscovery discovery,
    required SupplierPortalCatalogTaxonomy? known,
    required Future<Map<String, dynamic>?> Function(String call) evaluateProbe,
  }) async {
    final report = await evaluateProbe(
      'taxonomy([${jsonEncode(discovery.parentField)}])',
    );
    final fields = report?['fields'];
    if (fields is! List || fields.isEmpty) return known;
    final parentOptions = _options(Map<String, dynamic>.from(fields.first));
    final parents = rankSupplierTaxonomyNodes(
      taxonomy:
          SupplierPortalCatalogTaxonomy.fromNodes(<SupplierPortalTaxonomyNode>[
        for (final option in parentOptions)
          SupplierPortalTaxonomyNode(id: option.$1, label: option.$2),
      ]),
      familyTerms: plan.familyTerms,
      excludedTerms: plan.excludedTerms,
      limit: discovery.maxParentProbes,
    );
    var merged = known;
    for (final parent in parents) {
      final selected = await evaluateProbe(
        'selectOption(${jsonEncode(discovery.parentField)},'
        '${jsonEncode(parent.label)})',
      );
      if (selected?['ok'] != true) continue;
      await Future<void>.delayed(_settleDelay);
      final discovered = await _readTaxonomy(evaluateProbe, discovery);
      if (discovered == null || discovered.isEmpty) continue;
      merged = merged == null ? discovered : merged.mergedWith(discovered);
      if (plan.rankNodes(merged).isNotEmpty) break;
    }
    return merged;
  }

  String _needSearchCoverageEvidence({
    required SupplierNeedSearchPlan plan,
    required SupplierNeedPortalCoverage coverage,
    required SupplierPortalCatalogTaxonomy? taxonomy,
  }) =>
      jsonEncode(<String, dynamic>{
        'stage': 'catalog_enumeration',
        'route': _needSearchRouteEvidence(plan),
        'coverage': coverage.toJson(),
        // La huella permite demostrar deriva del portal sin guardar una línea
        // de una página autenticada.
        'taxonomyFingerprint': taxonomy?.fingerprint,
        'taxonomyNodeCount': taxonomy?.nodes.length ?? 0,
      });

  /// Evidencia suficiente para diagnosticar deriva del adaptador sin guardar
  /// texto de una página autenticada, campos, cookies ni identificadores de
  /// cuenta. Los productos visibles ya viajan por separado en `results`.
  String _needSearchEvidence({
    required String stage,
    required Map<String, dynamic> report,
    required SupplierNeedSearchPlan plan,
    List<String> navigation = const <String>[],
  }) {
    final session = report['session'];
    final sessionMap = session is Map
        ? Map<String, dynamic>.from(session)
        : const <String, dynamic>{};
    final results = report['results'];
    return jsonEncode(<String, dynamic>{
      'stage': stage,
      'probeVersion': report['version']?.toString(),
      'frameCount': report['frameCount'] is num
          ? (report['frameCount'] as num).round()
          : null,
      'resultCount': results is List ? results.length : 0,
      'noResultsSignal': report['noResults'] == true,
      'session': <String, dynamic>{
        'passwordField': sessionMap['hasPasswordField'] == true,
        'emptyLabel': sessionMap['hasEmptySessionLabel'] == true,
        'phraseCount': sessionMap['phrases'] is List
            ? (sessionMap['phrases'] as List).length
            : 0,
      },
      'route': _needSearchRouteEvidence(plan),
      'steps': navigation,
    });
  }

  Map<String, Object?> _needSearchRouteEvidence(
    SupplierNeedSearchPlan plan,
  ) =>
      <String, Object?>{
        'technicalFamily': plan.request.technicalFamily,
        'identityFamily': plan.family.identityFamily,
        'configuredSteps': plan.family.navigation.length,
      };

  bool _matchesNoResultAlert(String? alert, List<String> phrases) {
    final normalized = alert?.trim() ?? '';
    if (normalized.isEmpty) return false;
    for (final phrase in phrases) {
      if (phrase.trim().isEmpty) continue;
      if (normalized.toLowerCase().contains(phrase.trim().toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  Future<void> _record(
    String supplierId,
    SupplierAvailabilityTarget target,
    String url,
    SupplierPortalReading reading,
    String body,
  ) async {
    try {
      await _service.record(
        supplierId: supplierId,
        target: target,
        reading: reading,
        sourceUrl: url,
        evidenceSample: body,
      );
    } catch (error) {
      // Perder una fila no puede tumbar el recorrido completo: las demás
      // consultas siguen siendo información válida.
      if (kDebugMode) {
        debugPrint('🛒 No se pudo anotar un chequeo: ${error.runtimeType}');
      }
    }
  }
}

class SupplierPortalRunSummary {
  const SupplierPortalRunSummary({
    required this.checked,
    required this.stoppedBecause,
  });

  final int checked;

  /// `session_expired` · `error` · `no_webview` · nulo si terminó entero.
  final String? stoppedBecause;

  bool get needsLogin => stoppedBecause == 'session_expired';
}
