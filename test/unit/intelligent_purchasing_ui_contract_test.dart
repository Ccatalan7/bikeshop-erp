import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String workspace;
  late String jobs;
  late String routes;
  late String menu;
  late String purchaseForm;
  late String purchaseService;
  late String purchaseDraftSeed;

  setUpAll(() {
    // El recorrido dejó de vivir en un solo archivo: el bloque de captura y la
    // gramática visual salieron a `widgets/`. Este contrato es sobre los
    // controles del workspace, no sobre en qué archivo quedaron, así que la
    // fuente que se inspecciona es la del módulo completo.
    workspace = [
      'lib/modules/purchases/pages/intelligent_purchasing_workspace_page.dart',
      'lib/modules/purchases/widgets/purchase_composer.dart',
      'lib/modules/purchases/widgets/purchase_visual_language.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    jobs = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    routes = File('lib/shared/routes/app_router.dart').readAsStringSync();
    menu = File('lib/shared/widgets/main_layout.dart').readAsStringSync();
    purchaseForm = File(
      'lib/modules/purchases/pages/purchase_invoice_form_page.dart',
    ).readAsStringSync();
    purchaseService = File(
      'lib/modules/purchases/services/purchase_service.dart',
    ).readAsStringSync();
    purchaseDraftSeed = File(
      'lib/modules/purchases/models/purchase_invoice_draft_seed.dart',
    ).readAsStringSync();
  });

  test('new workspace replaces the legacy entry point without building on it',
      () {
    expect(routes, contains("path: '/purchases/assistant'"));
    expect(menu, contains("title: 'Asistente de compras'"));
    expect(menu, contains("route: '/purchases/assistant'"));
    expect(menu, contains("title: 'Documentos de compra'"));
    expect(menu, contains("title: 'Nuevo documento'"));
    expect(workspace, isNot(contains('SmartPurchaseListService')));
    expect(workspace, isNot(contains('smart_purchase_list')));
  });

  test('workflow is stock-first and external evidence remains secondary', () {
    // El paso Stock precede a Proveedores en el propio enum del proceso, no
    // sólo en el orden de dibujo de una pantalla.
    final surfaces = File(
      'lib/modules/purchases/pages/intelligent_purchasing_surfaces.dart',
    ).readAsStringSync();
    expect(
      surfaces,
      contains('enum PurchaseStep { need, stock, providers, plan }'),
    );
    expect(
      surfaces.indexOf('La bodega se consulta antes de cotizar'),
      greaterThanOrEqualTo(0),
    );
    final stockStep = workspace.indexOf('PurchaseStep.stock =>');
    final providersStep = workspace.indexOf('PurchaseStep.providers =>');
    expect(stockStep, greaterThanOrEqualTo(0));
    expect(providersStep, greaterThan(stockStep));
    // Comparar proveedores sólo se habilita desde el paso de bodega.
    expect(surfaces, contains('compare-providers-for-remaining'));
    expect(workspace, contains('disponibilidad por confirmar'));
    expect(
      File(
        'lib/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart',
      ).readAsStringSync(),
      contains('Abrir proveedor'),
    );
  });

  test('every panel is anchored: no scrim and no centred editing block', () {
    final decision = File(
      'lib/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart',
    ).readAsStringSync();
    for (final source in [workspace, decision]) {
      expect(source, isNot(contains('ModalBarrier')));
      // Un diálogo centrado siempre atenúa el host: no queda ninguno.
      expect(source, isNot(contains('showDialog<')));
      expect(source, isNot(contains('AlertDialog(')));
      // El rol de velo existe en el tema, pero este módulo no lo consume.
      expect(source, isNot(contains('roles.scrim')));
      // Toda hoja declara explícitamente un click-catcher transparente.
      for (final match in RegExp('barrierColor:([^,\n]*)').allMatches(source)) {
        expect(
          match.group(1)!.trim(),
          'Colors.transparent',
          reason: 'Una hoja del asistente no puede atenuar el fondo.',
        );
      }
    }
    // No queda ninguna familia de editor flotante: ni hoja, ni isla, ni
    // superficie con ancho fijo centrada sobre la página.
    expect(workspace, isNot(contains('showAnchoredPurchaseSheet')));
    expect(workspace, isNot(contains('showModalBottomSheet')));
    expect(workspace, isNot(contains('_AnchoredSheetBody')));
    // Los tres editores viven dentro de su fila.
    expect(workspace, contains('supply-draft-inline-editor-'));
    expect(workspace, contains('plan-quantity-inline-'));
    expect(workspace, contains('supply-draft-criteria-'));
    // La necesidad se edita en su propia fila.
    expect(workspace, contains("ValueKey('need-inline-description')"));
    expect(workspace, contains('_buildNeedInlineEditor'));
    // Ningún estado vacío del workspace se dibuja centrado ni queda sin
    // salida: el mensaje y su acción viven alineados a la izquierda.
    expect(workspace, isNot(contains('Center(\n        child: VbNotice(')));
    expect(workspace, contains("ValueKey('provider-results-choose-need')"));
    // Un solo estado de carga por acción: al responder, vive en el botón.
    expect(
      workspace,
      contains('if (_askingAssistant && _supplyNeedDraft == null)'),
    );
    // La petición se transcribe una sola vez, en su burbuja.
    expect(workspace, isNot(contains("'Pediste: «")));
    // El vacío del plan es inline y sin borde punteado ni isla centrada.
    expect(decision, contains("ValueKey('plan-empty-inline')"));
    expect(decision, isNot(contains('BorderStyle.')));
    expect(decision, contains('Todavía no hay productos elegidos'));
  });

  test('product identity renders a real photo with a same-geometry fallback',
      () {
    final surfaces = File(
      'lib/modules/purchases/pages/intelligent_purchasing_surfaces.dart',
    ).readAsStringSync();
    final models = File(
      'lib/modules/purchases/models/intelligent_purchasing_models.dart',
    ).readAsStringSync();
    expect(surfaces, contains('Image.network'));
    expect(surfaces, contains('errorBuilder'));
    expect(surfaces, contains('BoxFit.contain'));
    expect(models, contains('imageUrlOptimized'));
    expect(models, contains('imageUrls'));
    expect(models, contains('String? get primaryUrl'));
    // El plan no repite imágenes: ya no aportan a la decisión.
    expect(
      File(
        'lib/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart',
      ).readAsStringSync().indexOf('PlanEmptyInline'),
      greaterThanOrEqualTo(0),
    );
  });

  test('jobs status morphs only through the semantic capability flag', () {
    expect(jobs, contains('status.promptsSupplyNeedCapture'));
    expect(jobs, contains('SupplyNeedCapturePanel('));
    expect(jobs, contains("ValueKey('supply-need-back-to-statuses')"));
    expect(jobs, contains("semanticLabel: 'Volver a estados'"));
    expect(jobs, contains('_supplyCaptureHasOpened'));
    expect(jobs, contains('Offstage('));
    expect(jobs, contains("'Repuestos sin definir'"));
    expect(jobs, contains("'Solicitar captura de repuestos'"));
    expect(jobs, contains('final succeeded = await widget.onStatusSelected'));
    expect(
      jobs.indexOf('final succeeded = await widget.onStatusSelected'),
      lessThan(jobs.indexOf('_isCapturingSupplyNeed = true')),
      reason: 'The form may appear only after a confirmed status transition.',
    );
    expect(
      jobs,
      isNot(contains("status.name.toLowerCase() == 'repuestos'")),
      reason: 'Status names are editable and cannot own behavior.',
    );
  });

  test('responsive workspace avoids a chip wall and keeps in-page return', () {
    expect(workspace, contains('ResponsiveBreakpoints.desktopMin'));
    expect(workspace, contains('ResponsiveBreakpoints.phoneMaxExclusive'));
    expect(workspace, contains('Necesidades abiertas'));
    // El paso Necesidad es una conversación con salida direccional.
    expect(workspace, contains("ValueKey('purchase-utterance')"));
    expect(workspace, contains("ValueKey('go-to-next-step')"));
    expect(workspace, contains("ValueKey('intelligent-purchasing-analyze')"));
    expect(workspace, contains('PurchaseSurfaceGeometry.narrowColumnMax'));
    expect(workspace, contains('ReturnNavigation.close'));
    expect(workspace, isNot(contains('ChoiceChip(')));
    expect(workspace, isNot(contains('FilterChip(')));
    expect(workspace, isNot(contains('InputChip(')));
  });

  test('the review-only plan keeps its core corrections actionable', () {
    expect(workspace, contains("tooltip: 'Editar cantidad'"));
    expect(workspace, contains("tooltip: 'Quitar del plan'"));
    expect(workspace, contains('_service.updatePlanLineQuantity'));
    // Frames 07/18/21/24: la vuelta al paso anterior es una acción rotulada de
    // la cabecera del plan, no un icono con tooltip. La corrección directa de
    // cantidad vive además en el stepper de la línea.
    final decision = File(
      'lib/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart',
    ).readAsStringSync();
    expect(decision, contains("ValueKey('plan-back-to-compare')"));
    expect(decision, contains('Plan borrador'));
    expect(decision, contains('class PurchaseQuantityStepper'));
    expect(workspace, contains('PurchaseQuantityStepper('));
    expect(workspace, contains('_setPlanQuantity'));
    // La losa tonal «Borrador para revisar» quedó fuera: el estado del plan se
    // dice en la meta de su cabecera.
    expect(workspace, isNot(contains('Borrador para revisar')));
  });

  test('ningún control visible queda decorativo', () {
    final decision = File(
      'lib/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart',
    ).readAsStringSync();
    final surfaces = File(
      'lib/modules/purchases/pages/intelligent_purchasing_surfaces.dart',
    ).readAsStringSync();
    for (final source in [workspace, decision, surfaces]) {
      // Todo `IconButton` dice qué hace, también cuando está deshabilitado.
      final iconButtons = 'IconButton('.allMatches(source).length;
      final tooltips = RegExp(r'IconButton\((?:[^)]|\)(?!;))*?tooltip:')
          .allMatches(source)
          .length;
      expect(
        tooltips,
        iconButtons,
        reason: 'Un icono sin tooltip parece presionable sin decir qué hace.',
      );
    }
    // El stepper deshabilita en los extremos con una razón, no en silencio.
    expect(decision, contains("'Ya está en el mínimo'"));
    expect(decision, contains("'Ya está en el máximo'"));
  });

  test('las superficies de estado están cableadas a señal real', () {
    // Frame 09: el parcial sale de `evidenceQuality`/`hasMore`, no de una
    // condición inventada, y «Continuar» relanza con el corte ampliado.
    expect(workspace, contains("evidenceQuality == 'unevaluated'"));
    expect(workspace, contains('_analysisIsPartial'));
    expect(workspace, contains('PartialAnalysisNotice('));
    expect(workspace, contains('_rankingExtendedLimit'));
    expect(workspace, contains('resetRankingLimit: false'));
    // Frame 10: hay un filtro real que puede esconderlo todo, y se revierte.
    expect(workspace, contains('_allCandidatesHiddenByFilters'));
    expect(workspace, contains("'confirmed_only'"));
    expect(workspace, contains('_clearProviderFilters'));
    expect(workspace, contains('_includeUnconfirmedCompatibility'));
    expect(workspace, contains('NoMatchSurface('));
    // Frames 20/28: la canasta muta necesidades reales.
    expect(workspace, contains('BasketSectionTabs('));
    expect(workspace, contains('BasketRequestLinesCard('));
    expect(workspace, contains('_service.updateNeed('));
    expect(workspace, contains('_selectedScenarioKey'));
  });

  test('la nota de línea del plan no promete persistencia inexistente', () {
    final decision = File(
      'lib/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart',
    ).readAsStringSync();
    final models = File(
      'lib/modules/purchases/models/intelligent_purchasing_models.dart',
    ).readAsStringSync();
    // No existe campo de nota en la línea del plan…
    expect(models, isNot(contains('final String? note;')));
    // …así que tampoco existe el editor que fingía guardarla.
    expect(decision, isNot(contains('PlanLineAlternativeNote')));
    expect(decision, contains('class PlanLineEvidenceNote'));
    expect(workspace, contains('PlanLineEvidenceNote('));
  });

  test('el oscuro sale de roles, nunca de un color literal del feature', () {
    final decision = File(
      'lib/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart',
    ).readAsStringSync();
    final surfaces = File(
      'lib/modules/purchases/pages/intelligent_purchasing_surfaces.dart',
    ).readAsStringSync();
    for (final source in [workspace, decision, surfaces]) {
      // Ni hex, ni `Colors.<algo>` con tono: el módulo compone con roles.
      expect(
        RegExp(r'Color\(0x').hasMatch(source),
        isFalse,
        reason: 'La guía prohíbe hex literal en widgets.',
      );
      expect(
        RegExp(r'Colors\.(?!transparent\b)[a-z]').hasMatch(source),
        isFalse,
        reason: 'Sólo `Colors.transparent` es admisible: no tiene tono.',
      );
    }
  });

  test('la aclaración pregunta de a una y no persiste nada', () {
    // Una sola pregunta activa y progreso textual, nunca cápsulas.
    expect(workspace, contains("ValueKey('clarification-progress')"));
    expect(workspace, contains('_clarificationQueue'));
    expect(workspace, contains('activeIndex'));
    // Los tres controles del contrato, y sólo esos.
    expect(workspace,
        contains('AIAssistantSupplyNeedClarificationInputKind.singleChoice'));
    expect(workspace,
        contains('AIAssistantSupplyNeedClarificationInputKind.number'));
    expect(workspace, contains('suffixText: isNumber ? prompt.unit : null'));
    expect(workspace, contains('RadioListTile<String>'));
    // Continuar habla con el asistente, no con el servicio de necesidades.
    expect(workspace, contains('_submitClarificationAnswers'));
    expect(workspace, contains('isClarificationAnswer: true'));
    expect(
      workspace,
      isNot(contains('_saveSupplyNeedDraft();\n    await _askAssistant')),
    );
    // El mensaje es autocontenido y no arrastra estado del cliente.
    expect(workspace, contains("'kind': 'supply_need_clarification_answers'"));
    expect(workspace, contains("'originalRequest': _lastUserMessage ?? ''"));
    expect(workspace,
        contains("if (unknown) 'unknown': true else 'answer': value"));
    // La ronda la cuenta la confirmación del servidor, no el envío: así un
    // reintento exitoso también cuenta y un fallo no gasta cupo.
    expect(workspace, contains('_clarificationRound += 1'));
    expect(
      workspace,
      isNot(contains('setState(() => _clarificationRound -= 1)')),
    );
    // Un controlador por prompt: uno compartido filtraba texto entre preguntas.
    expect(workspace,
        contains('Map<String, TextEditingController> _clarificationInputs'));
    expect(workspace, contains('_clarificationControllerFor'));
    // El número se valida y se acota; nada de texto arbitrario en el hilo.
    expect(workspace, contains('_normalizeClarificationNumber'));
    expect(workspace, contains('LengthLimitingTextInputFormatter'));
    expect(workspace, contains('_clarificationNumberMaxLength = 32'));
    expect(workspace, contains('_clarificationTextMaxLength = 240'));
    // Con todo respondido no se repite el control.
    expect(workspace, contains("ValueKey('clarification-submit')"));
    expect(workspace, contains('if (answeredAll)'));
    // Tope de rondas y salida sin cuarto interrogatorio.
    expect(workspace, contains('_clarificationRoundCap'));
    expect(workspace, contains("ValueKey('clarification-round-cap')"));
    // El camino legacy sigue existiendo, separado del tipado.
    expect(workspace, contains("ValueKey('material-clarification-legacy')"));
    // La limitación del ERP no vive bajo el encabezado de precisión.
    expect(workspace, contains('supply-draft-coverage-note-'));
    expect(workspace,
        contains('!line.clarificationRequired && line.clarification != null'));
    // La prosa larga no es el texto primario.
    expect(workspace, contains('_derivedInterpretationSummary'));
    expect(workspace, contains("ValueKey('assistant-explanation-toggle')"));
  });

  test('local rescue purchase reuses the canonical purchase draft route', () {
    expect(workspace, contains("ValueKey('register-local-purchase')"));
    // Frame 13: la compra local se revisa en un panel anclado y recién después
    // navega al borrador canónico, con el tipo de documento elegido.
    expect(
      workspace,
      contains("'/purchases/new?documentKind=\$documentKind'"),
    );
    expect(workspace, contains('LocalPurchaseSheet('));
    expect(workspace, contains('_wrapWithLocalPurchaseSheet'));
    expect(workspace, contains('_closeLocalPurchaseCapture'));
    expect(workspace, contains('PurchaseInvoiceDraftSeed('));
    expect(routes, contains('state.extra is PurchaseInvoiceDraftSeed'));
    expect(purchaseDraftSeed, contains('class PurchaseInvoiceDraftSeed'));
    expect(purchaseDraftSeed, contains('final double quantity'));
    expect(workspace, isNot(contains("context.push('/expenses")));
  });

  test('document behavior comes from the server catalog and workflow kind', () {
    expect(
      purchaseService,
      contains("'purchase_source_document_kinds'"),
    );
    expect(purchaseService, contains('purchase_invoice_list_read_model_v2'));
    expect(
      purchaseForm,
      contains('_selectedSourceDocumentKind?.isDirectPurchase'),
    );
    expect(purchaseForm, contains('Confirmar compra'));
  });
}
