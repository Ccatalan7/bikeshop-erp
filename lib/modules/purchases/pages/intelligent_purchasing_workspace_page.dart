import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../ai_assistant/config/ai_assistant_runtime_config.dart';
import '../../ai_assistant/models/ai_assistant_destination.dart';
import '../../ai_assistant/models/ai_agent_gateway_contracts.dart';
import '../../ai_assistant/models/ai_assistant_turn_contracts.dart';
import '../../ai_assistant/services/ai_agent_gateway_client.dart';
import '../../ai_assistant/widgets/ai_assistant_compact_action_tile.dart';
import '../../inventory/services/inventory_service.dart';
import '../models/intelligent_purchasing_models.dart';
import '../../../shared/models/product.dart';
import '../models/purchase_invoice_draft_seed.dart';
import '../services/intelligent_purchasing_service.dart';
import '../widgets/purchase_composer.dart';
import '../widgets/purchase_plan_close.dart';
import '../widgets/purchase_priority_panel.dart';
import '../widgets/purchase_visual_language.dart';
import 'intelligent_purchasing_decision_surfaces.dart';
import 'intelligent_purchasing_surfaces.dart';

class IntelligentPurchasingWorkspacePage extends StatefulWidget {
  const IntelligentPurchasingWorkspacePage({
    super.key,
    this.initialNeedId,
    this.mechanicJobId,
    this.service,
    this.gatewayClient,
  });

  final String? initialNeedId;
  final String? mechanicJobId;
  final IntelligentPurchasingService? service;
  final AIAgentGatewayClient? gatewayClient;

  @override
  State<IntelligentPurchasingWorkspacePage> createState() =>
      _IntelligentPurchasingWorkspacePageState();
}

class _IntelligentPurchasingWorkspacePageState
    extends State<IntelligentPurchasingWorkspacePage> {
  late final IntelligentPurchasingService _service;
  AIAgentGatewayClient? _gatewayClient;
  final _composerController = TextEditingController();
  final _stockReasonController = TextEditingController();
  final _identityController = TextEditingController();
  final _needDescriptionController = TextEditingController();
  final _needQuantityController = TextEditingController();
  // Los tres editores del asistente se abren dentro de su propia fila. No hay
  // ninguna superficie flotante: una isla centrada sobre la página se lee como
  // el modal que el dueño prohibió, aunque no lleve velo.
  final _draftDescriptionController = TextEditingController();
  final _draftQuantityController = TextEditingController();
  final _draftUnitController = TextEditingController();
  final _planQuantityController = TextEditingController();
  String? _editingDraftLineRef;
  String? _draftEditError;
  String? _criteriaLineRef;
  String? _editingPlanLineId;
  String? _planQuantityError;
  bool _editingNeed = false;
  bool _composerExpanded = false;
  bool _showExamples = false;
  String? _inspectedCandidateId;
  double _inspectorWidth = PurchaseSurfaceGeometry.inspectorDefaultWidth;

  /// El `»` de los frames 04/05: el detalle cede ancho a la lista sin
  /// cerrarse. Colapsado es el mínimo del clamp, no cero: a cero sería
  /// indistinguible de cerrar, y para eso ya está el `×`.
  bool _inspectorCollapsed = false;

  /// Cantidad elegida en el pie del inspector. `null` mientras nadie la
  /// toca: manda la de la necesidad, que es la respuesta correcta por
  /// defecto y la que el operador ya declaró.
  int? _inspectorQuantity;

  /// La línea del plan cuya nota se está guardando.
  String? _savingNoteLineId;

  List<PurchasePrioritySuggestion> _priority = const [];
  bool _priorityUnavailable = false;
  String? _takingPriorityId;
  List<SupplyNeed> _needs = const [];
  SupplyNeed? _selectedNeed;
  SupplyInventorySnapshot? _inventorySnapshot;
  PurchaseRanking? _ranking;

  /// Lectura stock-first de la fase B1. Es la autoridad de `needVersion` y
  /// `revisionNo`: `supply_needs` no guarda la revisión que gobierna, así que
  /// ningún comando de esta fase toma esos números de `SupplyNeed`.
  SupplyStockResolution? _stockResolution;

  /// Candidatos externos de la fase B2, con sus dos grupos.
  SupplyExternalCandidates? _externalCandidates;

  /// El servidor cerró el paso externo hasta que alguien decida el stock.
  /// Es un estado del flujo, no un fallo de red.
  bool _stockFirstRequired = false;

  /// Objetivo comercial tipado vigente.
  SupplyCommercialTarget? _commercialTarget;

  /// La necesidad cambió bajo los pies: se relee, no se reintenta con la
  /// versión vieja.
  bool _needsReload = false;

  /// Corte vigente de cada grupo. Son dos páginas independientes en el
  /// servidor, así que también son dos estados acá: pedir más no verificados
  /// no puede recortar los accionables.
  int _candidateOffset = 0;
  int _unverifiedLimit = _unverifiedBaseLimit;
  int _unverifiedOffset = 0;

  /// Corte de la bodega del carril familia. Es una tercera página, distinta de
  /// las dos externas: ampliarla no toca ni reordena los candidatos.
  int _stockLimit = _stockBaseLimit;

  /// El editor del objetivo comercial está abierto.
  bool _editingCommercialTarget = false;

  /// Una recarga incremental está en vuelo. **No** vacía la pantalla: sólo
  /// apaga los controles que piden más.
  bool _refreshingResults = false;

  /// Reintento de la última recarga incremental fallida, si la hubo.
  VoidCallback? _retryIncremental;

  /// **No hay una decisión coherente cargada todavía.**
  ///
  /// Una sola noción, derivada del único hecho que la define: ninguna lectura
  /// llegó a comprometerse. `_stockResolution` sólo se asigna en el `setState`
  /// final, después de que los cuatro envelopes concuerdan; mientras sea nulo
  /// no hubo decisión, sea porque la lectura falló o porque hubo conflicto.
  ///
  /// Antes esto vivía en un `bool` propio que sólo cubría el fallo genérico:
  /// un conflicto inicial lo dejaba en `false` con todas las lecturas nulas, y
  /// la pantalla volvía a concluir «no hay compras comparables» y a ofrecer
  /// confirmar identidad sobre datos que nunca tuvo.
  bool get _decisionUnavailable =>
      _stockResolution == null && !_loadingDecision;

  /// Y su dueño visual: el conflicto lo dice su aviso con «Recargar»; el fallo
  /// genérico, la superficie de lectura fallida con su reintento. Nunca los
  /// dos, y nunca dos bandas del mismo problema.
  bool get _showsLoadFailure => _decisionUnavailable && !_needsReload;
  PurchaseScenarioResult? _scenarioResult;
  PurchasePlanDraft? _plan;

  /// Criterios de la necesidad abierta, y si su detalle está desplegado.
  SupplyNeedCriteria _needCriteria = SupplyNeedCriteria.empty;
  bool _showNeedCriteria = false;
  ProductSelection? _identitySelection;
  final Set<String> _basketNeedIds = <String>{};
  bool _loadingNeeds = true;
  bool _loadingDecision = false;
  bool _loadingScenarios = false;
  bool _runningCommand = false;
  bool _askingAssistant = false;
  bool _showStockRejection = false;

  /// Frame 13 — la captura de compra local está abierta como panel anclado.
  bool _showLocalPurchaseSheet = false;
  bool _showScenarios = false;

  /// Frame 20 — subestado visible de la canasta. Cambiar de pestaña no
  /// descarta escenarios, selección ni cantidades: son dos vistas del mismo
  /// borrador.
  BasketSection _basketSection = BasketSection.scenarios;

  /// Escenario elegido. Sobrevive al ida y vuelta entre pestañas.
  String? _selectedScenarioKey;
  String? _basketBusyNeedId;
  bool _selectingBasket = false;
  bool _returnToScenarios = false;
  String? _addingCandidateId;
  String? _preparingScenarioKey;
  String? _removingPlanLineId;
  String? _updatingPlanLineId;
  String _rankingProfile = 'balanced';
  String _tableView = 'auto';

  /// Límite vigente del ranking. «Continuar análisis» lo sube; es la única
  /// forma real de pedirle al servidor que evalúe más allá del corte.
  int _rankingLimit = _rankingBaseLimit;
  int _maxSuppliers = 2;
  String? _loadError;
  String? _decisionError;
  String? _scenarioError;
  String? _assistantText;
  String? _assistantError;
  List<AIAssistantActionCard> _assistantCards = const [];
  AIAssistantSupplyNeedDraft? _supplyNeedDraft;
  String? _supplyNeedBatchOperationKey;
  String? _supplyNeedSaveError;
  bool _showAllAssistantActions = false;

  /// Respuestas de la ronda vigente, por `lineRef|promptId`. Sobreviven a un
  /// reintento fallido: sólo las borra una petición nueva.
  final Map<String, String> _clarificationAnswers = <String, String>{};
  final Set<String> _clarificationUnknown = <String>{};

  /// Ronda de aclaración dentro del mismo hilo. Al llegar al tope el cliente
  /// deja de preguntar y ofrece las dos salidas honestas.
  int _clarificationRound = 0;
  static const int _clarificationRoundCap = 3;

  /// Un controlador por prompt. Uno solo compartido arrastraba el texto de una
  /// pregunta a la siguiente cuando venían dos entradas seguidas.
  final Map<String, TextEditingController> _clarificationInputs =
      <String, TextEditingController>{};

  /// Error de validación por prompt, mostrado en el propio campo.
  final Map<String, String> _clarificationInputErrors = <String, String>{};

  /// La prosa larga del modelo empieza colapsada.
  bool _showAssistantExplanation = false;
  String? _lastUserMessage;
  String? _threadId;
  String? _replayRequestId;
  String? _replayMessage;

  /// Si el reintento pendiente es una respuesta de aclaración. Sin esto el
  /// reintento reiniciaría la ronda y pisaría la petición original con el
  /// JSON de respuestas.
  bool _replayIsClarificationAnswer = false;
  Completer<void>? _agentAbort;
  late PurchaseStep _step;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? IntelligentPurchasingService();
    _gatewayClient = widget.gatewayClient;
    _step = widget.initialNeedId == null
        ? PurchaseStep.need
        : PurchaseStep.providers;
    unawaited(_loadNeeds());
    unawaited(_loadPriority());
    unawaited(_restoreOpenPlan());
  }

  /// Retoma el plan borrador que quedó abierto, en vez de empezar otro encima.
  ///
  /// **El bucle que corta.** `_plan` sólo se llenaba con lo agregado en la
  /// sesión en curso, y `prepare_purchase_plan_line_v1` abre un plan nuevo
  /// cada vez que recibe `p_plan_id` nulo. El operador armaba su plan, cerraba,
  /// volvía, no lo veía —el paso Plan aparecía deshabilitado con las líneas
  /// vivas en la base— y al agregar otra línea estrenaba un segundo borrador.
  /// En producción quedaron dos planes del mismo 2026-08-18 por eso.
  ///
  /// Como la prioridad, un fallo acá no rompe el módulo: sin plan restaurado el
  /// recorrido sigue igual que antes, sólo que sin retomar.
  Future<void> _restoreOpenPlan() async {
    try {
      final plan = await _service.fetchOpenDraftPlan();
      if (!mounted || plan == null) return;
      // Si el operador ya empezó a armar algo mientras se leía, manda lo suyo:
      // la restauración llega tarde y no puede pisarlo.
      if (_plan != null) return;
      setState(() => _plan = plan);
    } catch (_) {
      // Silencio deliberado: retomar es una comodidad, no un requisito.
    }
  }

  /// Qué hay que comprar, levantado por el sistema. Se pide al abrir porque es
  /// lo primero que la persona necesita ver, no algo que deba ir a buscar.
  ///
  /// Un fallo acá no rompe el módulo: la prioridad es una ayuda, y el resto del
  /// recorrido —escribir una petición, retomar una necesidad— sigue en pie.
  Future<void> _loadPriority() async {
    try {
      final priority = await _service.fetchPurchasePriority();
      if (!mounted) return;
      setState(() => _priority = priority);
    } catch (_) {
      if (!mounted) return;
      setState(() => _priorityUnavailable = true);
    }
  }

  @override
  void dispose() {
    final abort = _agentAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _composerController.dispose();
    for (final controller in _clarificationInputs.values) {
      controller.dispose();
    }
    _stockReasonController.dispose();
    _identityController.dispose();
    _needDescriptionController.dispose();
    _needQuantityController.dispose();
    _draftDescriptionController.dispose();
    _draftQuantityController.dispose();
    _draftUnitController.dispose();
    _planQuantityController.dispose();
    super.dispose();
  }

  Future<void> _loadNeeds({String? selectId}) async {
    if (mounted) {
      setState(() {
        _loadingNeeds = true;
        _loadError = null;
      });
    }
    try {
      var needs = await _service.fetchOpenNeeds(
        mechanicJobId: widget.mechanicJobId,
      );
      final wantedId = selectId ?? _selectedNeed?.id ?? widget.initialNeedId;
      if (wantedId != null && needs.every((need) => need.id != wantedId)) {
        final requested = await _service.fetchNeed(wantedId);
        if (requested != null) needs = [requested, ...needs];
      }
      if (!mounted) return;
      SupplyNeed? selected;
      if (wantedId != null) {
        selected = _firstWhereOrNull(needs, (need) => need.id == wantedId);
      }
      if (selected == null &&
          wantedId == null &&
          needs.isNotEmpty &&
          MediaQuery.sizeOf(context).width >=
              ResponsiveBreakpoints.desktopMin) {
        selected = needs.first;
      }
      setState(() {
        _needs = needs;
        _basketNeedIds.removeWhere(
          (id) => needs.every((need) => need.id != id),
        );
        _selectedNeed = selected;
        _loadingNeeds = false;
      });
      if (selected != null) await _loadDecision(selected);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingNeeds = false;
        _loadError = 'No se pudieron cargar las necesidades de abastecimiento.';
      });
    }
  }

  Future<void> _selectNeed(SupplyNeed need) async {
    if (_selectingBasket) {
      _toggleBasketNeed(need);
      return;
    }
    setState(() {
      // Stock interno antes que proveedores, siempre que haya identidad.
      _step = need.hasConfirmedProduct
          ? PurchaseStep.stock
          : PurchaseStep.providers;
      _selectedNeed = need;
      _inspectedCandidateId = null;
      _inspectorQuantity = null;
      _editingNeed = false;
      _returnToScenarios = false;
      _identitySelection = null;
      _identityController.clear();
      _showStockRejection = false;
      _stockReasonController.clear();
      // Los criterios son de la necesidad que se abandona: se limpian ahora,
      // para que la barra no muestre los de la anterior mientras carga.
      _needCriteria = SupplyNeedCriteria.empty;
      _showNeedCriteria = false;
    });
    await _loadDecision(need);
  }

  /// Trae los criterios de la necesidad abierta, sin bloquear su decisión.
  ///
  /// Van por su propio camino porque son una glosa: el stock, los candidatos y
  /// el plan no esperan por ellos, y si no llegan la barra se dibuja con el
  /// origen como siempre.
  Future<void> _loadNeedCriteria(SupplyNeed need) async {
    final criteria = await _service.fetchNeedCriteria(need.id);
    if (!mounted || _selectedNeed?.id != need.id) return;
    setState(() => _needCriteria = criteria);
  }

  Future<void> _loadDecision(
    SupplyNeed need, {
    /// El corte vuelve a su base al cambiar de necesidad, no en cada recarga:
    /// «Continuar análisis» recarga a propósito con el corte ampliado.
    bool resetRankingLimit = true,

    /// **Recarga incremental**: el operador pidió *más* de algo que ya está en
    /// pantalla. Vaciar los resultados y montar un spinner haría desaparecer
    /// la tabla, el candidato abierto y el panel del objetivo durante toda la
    /// petición, para volver a dibujar lo mismo más un par de filas. Se
    /// conserva lo visible, se apaga el control que disparó la carga y el
    /// reemplazo ocurre de una sola vez al llegar la respuesta.
    bool incremental = false,
  }) async {
    if (!mounted || _selectedNeed?.id != need.id) return;
    // **Acá y no en `_selectNeed`.** Hay dos caminos que abren una necesidad:
    // el toque del operador y `_loadNeeds`, que selecciona sola al entrar con
    // una necesidad ya pedida y llama directo a este método. Colgar la lectura
    // del primero dejaba la barra sin criterios justo al abrir el módulo, que
    // es la vez que más se mira. Una recarga incremental no la repite: el
    // operador pidió más resultados, no otra necesidad.
    if (!incremental) unawaited(_loadNeedCriteria(need));
    if (incremental) {
      setState(() {
        _refreshingResults = true;
        _decisionError = null;
        _retryIncremental = null;
      });
    } else {
      setState(() {
        _loadingDecision = true;
        _decisionError = null;
        _retryIncremental = null;
        _inventorySnapshot = null;
        _ranking = null;
        _stockResolution = null;
        _externalCandidates = null;
        _commercialTarget = null;
        _stockFirstRequired = false;
        _needsReload = false;
        _inspectedCandidateId = null;
        // El editor del objetivo pertenece a **una** necesidad: dejarlo
        // abierto al cambiar de fila mostraría —y guardaría— los números de
        // la anterior.
        _editingCommercialTarget = false;
        if (resetRankingLimit) {
          _rankingLimit = _rankingBaseLimit;
          _candidateOffset = 0;
          _unverifiedLimit = _unverifiedBaseLimit;
          _unverifiedOffset = 0;
          _stockLimit = _stockBaseLimit;
        }
      });
    }
    try {
      // **El carril lo decide el servidor, no `hasConfirmedProduct`.** La
      // lectura de stock responde en los dos carriles y trae la versión y la
      // revisión que los comandos siguientes exigen; sin ella una necesidad de
      // familia no tenía ninguna superficie y quedaba encerrada.
      final resolution = await _service.stockResolution(
        need.id,
        limit: _stockLimit,
      );
      SupplyInventorySnapshot? snapshot;
      if (need.hasConfirmedProduct) {
        // El carril exacto conserva su vista de componentes y sets: dice cosas
        // que la resolución por familia no conoce.
        snapshot = await _service.inventorySnapshot(need.id);
      }
      final target = await _service.commercialTarget(need.id);

      // **La lectura externa se llama siempre.** Condicionarla a `isOk` y a
      // `open` dejaba inalcanzables tres estados que sólo ella sabe nombrar
      // —`supply_closed`, `identity_unresolved` y `needs_refinement`—: la
      // interfaz decidía por su cuenta que no había nada que preguntar y el
      // operador se quedaba sin la causa ni la acción.
      SupplyExternalCandidates? candidates;
      var stockFirst = false;
      try {
        candidates = await _service.externalCandidates(
          need.id,
          limit: _rankingLimit,
          offset: _candidateOffset,
          unverifiedLimit: _unverifiedLimit,
          unverifiedOffset: _unverifiedOffset,
        );
      } on SupplyStockFirstRequired {
        // **El P0001 tiene que cuadrar con la resolución que ya se leyó.**
        // El servidor lo levanta a partir de su propia evaluación; si la
        // resolución que esta pantalla va a mostrar dice que el paso externo
        // está abierto, las dos lecturas describen momentos distintos y montar
        // «primero decide el stock» sobre una bodega que no bloquea sería
        // afirmar algo que la propia pantalla desmiente. Eso es un conflicto,
        // y se recarga.
        if (!(resolution.isOk &&
            resolution.blocksExternal &&
            !resolution.externalAllowed)) {
          throw SupplyConcurrencyConflict(need.id);
        }
        stockFirst = true;
      }
      if (!mounted || _selectedNeed?.id != need.id) return;
      // **Tres lecturas separadas pueden describir tres momentos distintos.**
      // Si alguien escribió entremedio, montarlas juntas produce una pantalla
      // que no existió nunca: stock de antes, objetivo de después y un ranking
      // calculado sobre otra revisión. No se presenta esa mezcla; se ofrece
      // releer, que es la única salida honesta.
      if (!_envelopesAgree(need, resolution, target, candidates)) {
        throw SupplyConcurrencyConflict(need.id);
      }
      setState(() {
        _stockResolution = resolution;
        _inventorySnapshot = snapshot;
        _commercialTarget = target;
        _externalCandidates = candidates;
        _stockFirstRequired = stockFirst;
        // La superficie ya refactorizada sigue consumiendo el ranking; sólo el
        // grupo accionable entra, porque los no verificados tienen su propio
        // bloque rotulado y no se mezclan.
        _ranking = candidates?.asRanking;
        _loadingDecision = false;
        _refreshingResults = false;
        _retryIncremental = null;
        // El candidato abierto puede haber desaparecido del corte nuevo.
        if (_inspectedCandidate == null) _inspectedCandidateId = null;
      });
    } on SupplyConcurrencyConflict {
      if (!mounted || _selectedNeed?.id != need.id) return;
      setState(() {
        _loadingDecision = false;
        _refreshingResults = false;
        _needsReload = true;
        _decisionError = _concurrencyMessage;
      });
    } catch (_) {
      if (!mounted || _selectedNeed?.id != need.id) return;
      setState(() {
        _loadingDecision = false;
        _refreshingResults = false;
        if (incremental) {
          // Lo que ya estaba en pantalla sigue siendo cierto: pedir más y
          // fallar no invalida lo comparado hasta aquí.
          _decisionError = 'No se pudo traer el resto. Lo comparado sigue '
              'en pantalla.';
          _retryIncremental = () => unawaited(
                _loadDecision(
                  need,
                  resetRankingLimit: false,
                  incremental: true,
                ),
              );
        } else {
          _decisionError =
              'No se pudo completar el análisis. Puedes reintentar sin perder la necesidad.';
        }
      });
    }
  }

  /// Los cuatro envelopes hablan de la misma necesidad, versión y revisión.
  ///
  /// `needVersion` y `supplyState` los publican las tres lecturas; `revisionNo`
  /// lo comparten resolución y candidatos, y `targetRevisionNo`, objetivo y
  /// candidatos. Cualquier desacuerdo significa que hubo una escritura entre
  /// medio y que la pantalla armada sería un collage de dos estados.
  bool _envelopesAgree(
    SupplyNeed need,
    SupplyStockResolution resolution,
    SupplyCommercialTarget target,
    SupplyExternalCandidates? candidates,
  ) {
    if (resolution.needId != need.id || target.needId != need.id) return false;
    if (resolution.needVersion != need.version) return false;
    if (target.needVersion != need.version) return false;
    if (target.needSupplyState != need.supplyState) return false;
    if (candidates == null) return true;
    return candidates.needId == need.id &&
        candidates.needVersion == need.version &&
        candidates.needSupplyState == need.supplyState &&
        candidates.revisionNo == resolution.revisionNo &&
        candidates.targetRevisionNo == target.targetRevisionNo;
  }

  Future<void> _askAssistant({
    String? message,

    /// Una respuesta de aclaración viaja por el mismo camino que cualquier
    /// mensaje del operador —no es dato de confianza del servidor— pero no
    /// reinicia la ronda ni pisa la petición original.
    bool isClarificationAnswer = false,
  }) async {
    final normalized = (message ?? _composerController.text).trim();
    if (normalized.isEmpty || _askingAssistant) return;
    if (mounted) {
      setState(() {
        _composerExpanded = false;
        _showExamples = false;
      });
    }

    final gatewayClient = _resolveGatewayClient();
    if (gatewayClient == null) {
      setState(() {
        _assistantError =
            'La conversación con IA no está disponible en esta compilación. '
            'Puedes seguir revisando stock, rankings y necesidades guardadas.';
        _replayRequestId = null;
        _replayMessage = null;
        _replayIsClarificationAnswer = false;
      });
      return;
    }

    final requestId = _replayMessage == normalized && _replayRequestId != null
        ? _replayRequestId!
        : const Uuid().v4();
    final abort = Completer<void>();
    setState(() {
      _step = PurchaseStep.need;
      _askingAssistant = true;
      _assistantError = null;
      // Responder una aclaración no descarta el borrador en pantalla: si el
      // envío falla, el operador conserva lo que ya había contestado.
      if (!isClarificationAnswer) _supplyNeedDraft = null;
      _supplyNeedBatchOperationKey = null;
      _supplyNeedSaveError = null;
      if (!isClarificationAnswer) {
        // Una petición nueva reinicia ronda, respuestas y explicación.
        _lastUserMessage = normalized;
        _clarificationRound = 0;
        _clarificationAnswers.clear();
        _clarificationUnknown.clear();
        _clarificationInputErrors.clear();
        for (final controller in _clarificationInputs.values) {
          controller.dispose();
        }
        _clarificationInputs.clear();
        _showAssistantExplanation = false;
      }
      _agentAbort = abort;
    });
    try {
      final response = await gatewayClient.complete(
        AIAgentGatewayRequest(
          clientRequestId: requestId,
          threadId: _threadId,
          message: normalized,
          viewContext: AIAgentGatewayViewContext.intelligentPurchasing(),
        ),
        abortTrigger: abort.future,
      );
      if (!mounted) return;
      final supplyDrafts = response.cards
          .map((card) => card.supplyNeedDraft)
          .whereType<AIAssistantSupplyNeedDraft>()
          .toList(growable: false);
      if (supplyDrafts.length > 1) {
        throw const AIAgentGatewayContractException();
      }
      setState(() {
        _threadId = response.threadId;
        _assistantText = response.text;
        // Las respuestas de la ronda ya viajaron: la ronda siguiente empieza
        // en blanco. Sin esto, los prompts que vuelven con el mismo id se
        // consideran contestados y quedan sin poder responderse.
        if (isClarificationAnswer) {
          _clarificationRound += 1;
          _clarificationAnswers.clear();
          _clarificationUnknown.clear();
          _clarificationInputErrors.clear();
          for (final controller in _clarificationInputs.values) {
            controller.dispose();
          }
          _clarificationInputs.clear();
        }
        _replayIsClarificationAnswer = false;
        _assistantCards = response.cards
            .where(
              (card) =>
                  card.approvalRef == null &&
                  card.supplyNeedDraft == null &&
                  card.destination.isRegistered,
            )
            .toList(growable: false);
        _supplyNeedDraft = supplyDrafts.isEmpty ? null : supplyDrafts.single;
        _supplyNeedBatchOperationKey = null;
        _supplyNeedSaveError = null;
        _showAllAssistantActions = false;
        _assistantError = null;
        _askingAssistant = false;
        _replayRequestId = null;
        _replayMessage = null;
        _composerController.clear();
      });
      final autoOpenCards = _assistantCards
          .where((card) => card.inventoryListRef?.autoOpen == true)
          .toList(growable: false);
      if (autoOpenCards.length == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleAssistantCard(autoOpenCards.single);
        });
      }
    } on AIAgentGatewayException catch (error) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          '[IntelligentPurchasing] gateway error code=${error.code} '
          'status=${error.statusCode} outcomeUnknown=${error.outcomeUnknown}',
        );
      }
      final preserveRequest =
          error.outcomeUnknown || error.code == 'run_in_progress';
      final mayRetry = error.code != 'forbidden' &&
          error.code != 'invalid_session' &&
          error.code != 'authority_changed';
      setState(() {
        _askingAssistant = false;
        _assistantError = _assistantGatewayErrorMessage(error);
        _replayRequestId = preserveRequest ? requestId : null;
        _replayMessage = mayRetry ? normalized : null;
        _replayIsClarificationAnswer = mayRetry && isClarificationAnswer;
      });
    } on AIAgentGatewayContractException {
      if (!mounted) return;
      setState(() {
        _askingAssistant = false;
        _assistantError =
            'El resultado llegó incompleto. Reintenta para recuperar la misma ejecución sin duplicarla.';
        _replayRequestId = requestId;
        _replayMessage = normalized;
        _replayIsClarificationAnswer = isClarificationAnswer;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _askingAssistant = false;
        _assistantError =
            'No se pudo confirmar el resultado. Reintenta para recuperar la misma ejecución sin duplicarla.';
        _replayRequestId = requestId;
        _replayMessage = normalized;
        _replayIsClarificationAnswer = isClarificationAnswer;
      });
    } finally {
      if (identical(_agentAbort, abort)) _agentAbort = null;
    }
  }

  AIAgentGatewayClient? _resolveGatewayClient() {
    final injected = _gatewayClient;
    if (injected != null) return injected;
    if (!AIAssistantRuntimeConfig.serverGatewayEnabled) return null;
    try {
      return _gatewayClient = AIAgentGatewayClient();
    } on ArgumentError {
      return null;
    }
  }

  void _handleAssistantCard(AIAssistantActionCard card) {
    final inventoryList = card.inventoryListRef;
    if (inventoryList != null) {
      context.read<InventoryService>().applyExternalSearch(
            inventoryList.entityIds == null ? inventoryList.query : '',
            matchedProductIds: inventoryList.entityIds,
            stockFilter: switch (inventoryList.availability) {
              AIAssistantInventoryAvailability.any =>
                InventoryExternalStockFilter.any,
              AIAssistantInventoryAvailability.inStock =>
                InventoryExternalStockFilter.inStock,
              AIAssistantInventoryAvailability.lowStock =>
                InventoryExternalStockFilter.lowStock,
              AIAssistantInventoryAvailability.outOfStock =>
                InventoryExternalStockFilter.outOfStock,
            },
          );
    }

    final workspaceManager = context.read<WorkspaceManager>();
    final toolbar = context.read<RightToolbarService>();
    final resolver = AIAssistantDestinationResolver(
      navigateWorkspace: (route) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          workspaceManager.openRouteInWorkspace(route);
        });
      },
      openToolbarTool: toolbar.openTool,
    );
    final dispatched = resolver.dispatch(
      card.destination,
      entityRef: card.entityRef,
    );
    if (!dispatched && kDebugMode) {
      debugPrint(
        '[IntelligentPurchasing] ignored incompatible action destination '
        '${card.destination}',
      );
    }
  }

  Future<void> _saveSupplyNeedDraft() async {
    final originalRequest = _lastUserMessage;
    final draft = _supplyNeedDraft;
    if (originalRequest == null || draft == null || _runningCommand) return;
    final operationKey = _supplyNeedBatchOperationKey ?? const Uuid().v4();
    setState(() {
      _runningCommand = true;
      _supplyNeedSaveError = null;
      _supplyNeedBatchOperationKey = operationKey;
    });
    try {
      final needs = await _service.createNeedBatch(
        originalRequest: originalRequest,
        draft: draft,
        assistantThreadId: _threadId,
        operationKey: operationKey,
      );
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _supplyNeedDraft = null;
        _supplyNeedBatchOperationKey = null;
        _supplyNeedSaveError = null;
        _step = PurchaseStep.providers;
      });
      await _loadNeeds(selectId: needs.first.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _supplyNeedSaveError =
            'No se pudo confirmar si el lote quedó guardado. Reintenta: se usará la misma operación y no se duplicarán necesidades.';
      });
    }
  }

  void _removeSupplyNeedDraftLine(String lineRef) {
    final draft = _supplyNeedDraft;
    if (draft == null || draft.lines.length <= 1 || _runningCommand) return;
    setState(() {
      _supplyNeedDraft = draft.copyWith(
        lines: List<AIAssistantSupplyNeedDraftLine>.unmodifiable(
          draft.lines.where((line) => line.lineRef != lineRef),
        ),
      );
      _supplyNeedBatchOperationKey = null;
      _supplyNeedSaveError = null;
    });
  }

  /// Abre el editor de la línea dentro de su propia fila.
  void _openDraftLineEditor(AIAssistantSupplyNeedDraftLine line) {
    _draftDescriptionController.text = line.description;
    _draftQuantityController.text = _formatSupplyQuantity(line.quantity);
    _draftUnitController.text = _supplyUnitEditorValue(line.unit);
    setState(() {
      _editingDraftLineRef = line.lineRef;
      _draftEditError = null;
      // Criterios y edición no compiten por la misma fila.
      _criteriaLineRef = null;
    });
  }

  void _cancelDraftLineEditor() {
    setState(() {
      _editingDraftLineRef = null;
      _draftEditError = null;
    });
  }

  /// Guarda la línea editada conservando la validación previa: descripción,
  /// cantidad y unidad acotadas, y pérdida explícita de identidad cuando el
  /// texto cambia.
  void _saveDraftLineEditor(AIAssistantSupplyNeedDraftLine line) {
    final description = _draftDescriptionController.text.trim();
    final quantity = _parseSupplyQuantity(_draftQuantityController.text);
    final unit = _canonicalSupplyUnit(_draftUnitController.text);
    if (description.isEmpty ||
        utf8.encode(description).length > 2000 ||
        quantity == null ||
        quantity <= 0 ||
        quantity > 999999 ||
        unit.isEmpty ||
        utf8.encode(unit).length > 32) {
      setState(
        () => _draftEditError = 'Revisa la descripción, cantidad y unidad.',
      );
      return;
    }
    // Reescribir la descripción cambia qué se está pidiendo, así que la
    // procedencia entera —producto, categoría y predicados— se limpia. Cambiar
    // sólo cantidad o unidad no la toca.
    final identityChanged = description != line.description;
    final edited = identityChanged
        ? line.withRewrittenDescription(
            description: description,
            quantity: quantity,
            unit: unit,
            clarification:
                'Confirma el producto exacto antes de comparar proveedores.',
          )
        : line.copyWith(quantity: quantity, unit: unit);

    final draft = _supplyNeedDraft;
    if (draft == null ||
        draft.lines.every((item) => item.lineRef != line.lineRef)) {
      setState(() => _editingDraftLineRef = null);
      return;
    }
    setState(() {
      _supplyNeedDraft = draft.copyWith(
        lines: draft.lines
            .map((item) => item.lineRef == line.lineRef ? edited : item)
            .toList(growable: false),
      );
      _supplyNeedBatchOperationKey = const Uuid().v4();
      _supplyNeedSaveError = null;
      _editingDraftLineRef = null;
      _draftEditError = null;
    });
  }

  void _toggleDraftLineCriteria(String lineRef) {
    setState(
      () => _criteriaLineRef = _criteriaLineRef == lineRef ? null : lineRef,
    );
  }

  Future<void> _confirmIdentity() async {
    final need = _selectedNeed;
    final selection = _identitySelection;
    if (need == null ||
        selection == null ||
        !selection.isCatalogProduct ||
        selection.product?.id == null ||
        _runningCommand) {
      return;
    }
    setState(() => _runningCommand = true);
    try {
      final updated = await _service.updateNeed(
        need,
        description: need.description,
        productId: selection.product!.id,
      );
      if (!mounted) return;
      setState(() {
        _selectedNeed = updated;
        _runningCommand = false;
        _needs = _needs
            .map((item) => item.id == updated.id ? updated : item)
            .toList(growable: false);
      });
      await _loadDecision(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _decisionError =
            'No se pudo confirmar el producto. Recarga la necesidad e inténtalo otra vez.';
      });
    }
  }

  Future<void> _assignStock() async {
    final need = _selectedNeed;
    if (need == null || _runningCommand) return;
    setState(() => _runningCommand = true);
    try {
      final updated = await _service.assignFromStock(need);
      if (!mounted) return;
      setState(() => _runningCommand = false);
      await _loadNeeds(selectId: updated.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _decisionError =
            'El stock cambió antes de reservarlo. Recarga y revisa la disponibilidad actual.';
      });
    }
  }

  /// Registra por qué el stock interno no sirve, en el carril que corresponda.
  ///
  /// v2 y no v1: v1 exige un producto confirmado, así que en el carril familia
  /// nunca podía registrarse el rechazo — y sin rechazo el paso externo queda
  /// cerrado para siempre. La versión y la revisión salen de la lectura, no de
  /// `supply_needs`.
  Future<void> _rejectInternalStock() async {
    final need = _selectedNeed;
    final resolution = _stockResolution;
    final reason = _stockReasonController.text.trim();
    if (need == null ||
        resolution == null ||
        reason.isEmpty ||
        _runningCommand) {
      return;
    }
    setState(() => _runningCommand = true);
    try {
      await _service.rejectInternalStockForLane(
        resolution: resolution,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _showStockRejection = false;
      });
      // Releer: el rechazo subió la versión y abrió el paso externo.
      await _loadNeeds(selectId: need.id);
    } on SupplyConcurrencyConflict {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _needsReload = true;
        _decisionError = _concurrencyMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _decisionError = 'No se pudo guardar el motivo. Inténtalo otra vez.';
      });
    }
  }

  /// El perfil que el servidor resolvió, dicho como dato.
  ///
  /// No es un control: la lectura externa lo toma de la revisión que gobierna
  /// la necesidad. Ofrecerlo como menú prometía un cambio que nunca llegaba.
  String get _serverProfileLabel {
    final external = _externalCandidates;
    final profile = external?.rankingProfile ?? _rankingProfile;
    final label = _rankingProfileOptions[profile] ?? profile;
    if (external == null) return 'Prioridad · $label';
    return external.rankingProfileSource == 'revision'
        ? 'Prioridad · $label'
        : 'Prioridad · $label (por omisión)';
  }

  /// Guarda el objetivo comercial y vuelve a leer.
  ///
  /// La moneda **no** viaja: es del servidor y una carga que la traiga se
  /// rechaza. El parche es explícito, así que un campo vacío limpia ese
  /// objetivo en vez de conservarlo por descuido.
  Future<void> _saveCommercialTarget(Map<String, Object?> values) async {
    final target = _commercialTarget;
    final need = _selectedNeed;
    if (target == null || need == null || _runningCommand) return;
    setState(() {
      _runningCommand = true;
      _decisionError = null;
    });
    try {
      await _service.setCommercialTarget(current: target, values: values);
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _editingCommercialTarget = false;
      });
      await _loadNeeds(selectId: need.id);
    } on SupplyConcurrencyConflict {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _needsReload = true;
        _decisionError = _concurrencyMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _decisionError =
            'No se pudo guardar el objetivo. Recarga e inténtalo otra vez.';
      });
    }
  }

  /// Amplía el corte del grupo sin verificar, y sólo ése.
  Future<void> _showMoreUnverified() async {
    final need = _selectedNeed;
    if (need == null || _loadingDecision || _refreshingResults) return;
    setState(() => _unverifiedLimit += _unverifiedStep);
    await _loadDecision(need, resetRankingLimit: false, incremental: true);
  }

  /// Amplía el corte de la bodega del carril familia, y sólo ése.
  Future<void> _showMoreFamilyStock() async {
    final need = _selectedNeed;
    if (need == null || _loadingDecision || _refreshingResults) return;
    setState(() => _stockLimit += _stockStep);
    await _loadDecision(need, resetRankingLimit: false, incremental: true);
  }

  /// El aviso del paso activo: **uno solo**, con la acción que corresponde.
  ///
  /// Hay cuatro clases de fallo y cada una tiene su salida: una escritura ajena
  /// se recarga, una recarga incremental se reintenta sin perder lo comparado,
  /// una lectura inicial fallida se reintenta entera, y un comando que falló
  /// sólo se dice —la decisión que sigue disponible está justo debajo—.
  List<Widget>? _decisionNotice() {
    final message = _decisionError;
    if (message == null) return null;
    // El fallo genérico sin datos lo dice **sólo** su superficie: dos bandas
    // con el mismo problema en la misma columna es ruido, no información.
    if (_showsLoadFailure) return null;
    final Widget? action;
    if (_needsReload) {
      action = TextButton(
        key: const ValueKey('reload-after-conflict'),
        onPressed: _reloadAfterConflict,
        child: const Text('Recargar la necesidad'),
      );
    } else if (_retryIncremental != null) {
      action = TextButton(
        key: const ValueKey('retry-incremental-load'),
        onPressed: _refreshingResults ? null : _retryIncremental,
        child: const Text('Reintentar'),
      );
    } else {
      action = null;
    }
    return [
      VbNotice(
        key: const ValueKey('decision-recoverable-error'),
        title: message,
        tone: VbNoticeTone.warning,
        action: action,
      ),
      const SizedBox(height: 12),
    ];
  }

  /// Reintenta la lectura completa de la decisión tras un fallo inicial.
  Future<void> _retryDecisionLoad() async {
    final need = _selectedNeed;
    if (need == null || _loadingDecision) return;
    await _loadDecision(need, resetRankingLimit: false);
  }

  /// Vuelve a leer la necesidad tras un choque de concurrencia.
  Future<void> _reloadAfterConflict() async {
    final need = _selectedNeed;
    setState(() {
      _needsReload = false;
      _decisionError = null;
    });
    await _loadNeeds(selectId: need?.id);
  }

  /// Carril familia, primera escritura: fijar la identidad desde el candidato.
  ///
  /// **No agrega nada al plan.** `prepare_purchase_plan_line_v1` exige un
  /// producto confirmado, así que sin este paso la línea sería imposible; y
  /// unir los dos en un botón escondería dos escrituras bajo una palabra y
  /// dejaría al operador sin saber cuál falló.
  Future<void> _chooseFamilyProduct(PurchaseCandidate candidate) =>
      _chooseFamilyProductId(candidate.productId);

  Future<void> _chooseFamilyProductId(String productId) async {
    final need = _selectedNeed;
    final resolution = _stockResolution;
    if (need == null || resolution == null || _runningCommand) return;
    setState(() {
      _runningCommand = true;
      _decisionError = null;
    });
    try {
      await _service.confirmFamilyChoice(
        needId: need.id,
        expectedVersion: resolution.needVersion,
        expectedRevisionNo: resolution.revisionNo,
        productId: productId,
      );
      if (!mounted) return;
      setState(() => _runningCommand = false);
      // Releer necesidad, stock y candidatos: la convergencia cambió la
      // identidad, la versión y la revisión, y el conjunto elegible ya no es
      // el mismo.
      await _loadNeeds(selectId: need.id);
    } on SupplyConcurrencyConflict {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _needsReload = true;
        _decisionError = _concurrencyMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _decisionError =
            'No se pudo fijar el producto de la necesidad. Recarga e inténtalo otra vez.';
      });
    }
  }

  Future<void> _changeRankingProfile(String profile) async {
    if (profile == _rankingProfile) return;
    setState(() => _rankingProfile = profile);
    if (_showScenarios) {
      await _loadScenarios();
      return;
    }
    final need = _selectedNeed;
    if (need != null) await _loadDecision(need);
  }

  /// Frame 13 — abre la captura anclada. No navega todavía: primero se revisa.
  void _openLocalPurchaseCapture() {
    if (_selectedNeed == null) return;
    setState(() => _showLocalPurchaseSheet = true);
  }

  /// Cierre de la captura por el contrato de retorno del ERP.
  void _closeLocalPurchaseCapture() {
    if (!_showLocalPurchaseSheet) return;
    setState(() => _showLocalPurchaseSheet = false);
  }

  /// Entrega consciente al borrador canónico: es el único destino que el
  /// backend admite para una compra local, y se navega con lo revisado.
  Future<void> _continueToLocalPurchaseDraft({
    required String documentKind,
    required double quantity,
    required String treatment,
  }) async {
    final need = _selectedNeed;
    if (need == null) return;
    setState(() => _showLocalPurchaseSheet = false);
    final seed = PurchaseInvoiceDraftSeed(
      sourceDocumentKind: documentKind,
      lines: [
        PurchaseInvoiceDraftLineSeed(
          sourceNeedId: need.id,
          productId: need.productId ?? '',
          productName: need.productName ?? need.description,
          productSku: need.productSku,
          quantity: quantity,
          purchaseTreatment: treatment == 'workshop_consumable'
              ? PurchaseTreatment.workshopConsumable
              : PurchaseTreatment.inventory,
        ),
      ],
    );
    await context.push<void>(
      '/purchases/new?documentKind=$documentKind',
      extra: seed,
    );
    if (mounted && need.hasConfirmedProduct) {
      await _loadDecision(need);
    }
  }

  /// Monta la captura como panel anclado al borde, sin velo: el área libre es
  /// un click-catcher transparente que sólo cierra.
  Widget _wrapWithLocalPurchaseSheet(Widget body) {
    if (!_showLocalPurchaseSheet) return body;
    final need = _selectedNeed;
    if (need == null) return body;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < ResponsiveBreakpoints.phoneMaxExclusive;
    final sheet = LocalPurchaseSheet(
      productLabel: need.productName ?? need.description,
      suggestedQuantity: need.quantity,
      unitLabel: purchaseUnitLabel(need.unit, need.quantity),
      onCancel: _closeLocalPurchaseCapture,
      onContinue: ({
        required String documentKind,
        required double quantity,
        required String treatment,
      }) =>
          unawaited(
        _continueToLocalPurchaseDraft(
          documentKind: documentKind,
          quantity: quantity,
          treatment: treatment,
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned.fill(
          child: phone
              // Teléfono: hoja anclada al borde inferior, dentro del viewport.
              // La altura sale del alto disponible del propio Stack; un
              // `FractionallySizedBox` dentro de una `Column` recibe altura
              // infinita y revienta el layout.
              ? LayoutBuilder(
                  builder: (context, constraints) => Column(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _closeLocalPurchaseCapture,
                        ),
                      ),
                      SizedBox(
                        height: constraints.maxHeight *
                            PurchaseSurfaceGeometry.phoneSheetHeightFactor,
                        child: Material(elevation: 8, child: sheet),
                      ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _closeLocalPurchaseCapture,
                      ),
                    ),
                    SizedBox(
                      width: PurchaseSurfaceGeometry.tabletEdgeSheetWidth,
                      child: Material(elevation: 8, child: sheet),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  void _toggleBasketMode() {
    setState(() {
      // La canasta se arma en el paso Necesidad: alternar el modo no puede
      // sacar al operador del paso donde está eligiendo.
      _selectingBasket = !_selectingBasket;
      _showScenarios = false;
      _scenarioResult = null;
      _scenarioError = null;
      _returnToScenarios = false;
      if (!_selectingBasket) _basketNeedIds.clear();
    });
  }

  void _toggleBasketNeed(SupplyNeed need) {
    if (!_isBasketEligible(need)) return;
    setState(() {
      if (!_basketNeedIds.remove(need.id) && _basketNeedIds.length < 8) {
        _basketNeedIds.add(need.id);
      }
    });
  }

  bool _isBasketEligible(SupplyNeed need) =>
      need.hasConfirmedProduct && need.supplyState == 'open';

  List<SupplyNeed> get _selectedBasketNeeds => _needs
      .where((need) => _basketNeedIds.contains(need.id))
      .toList(growable: false);

  Future<void> _compareBasket() async {
    if (_basketNeedIds.length < 2 || _loadingScenarios) return;
    setState(() {
      // La comparación de la canasta vive en el paso Proveedores.
      _step = PurchaseStep.providers;
      _showScenarios = true;
      _returnToScenarios = false;
      _scenarioResult = null;
      _scenarioError = null;
    });
    await _loadScenarios();
  }

  Future<void> _loadScenarios() async {
    final needs = _selectedBasketNeeds;
    if (needs.length < 2 || _loadingScenarios) return;
    setState(() {
      _loadingScenarios = true;
      _scenarioError = null;
    });
    try {
      final result = await _service.buildScenarios(
        needs: needs,
        profile: _rankingProfile,
        maxSuppliers: _maxSuppliers,
      );
      if (!mounted) return;
      setState(() {
        _scenarioResult = result;
        _loadingScenarios = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingScenarios = false;
        _scenarioError =
            'No se pudo comparar la canasta. La selección sigue guardada para reintentar.';
      });
    }
  }

  Future<void> _changeMaxSuppliers(int value) async {
    if (value == _maxSuppliers) return;
    setState(() => _maxSuppliers = value);
    await _loadScenarios();
  }

  Future<void> _prepareScenario(PurchaseScenario scenario) async {
    if (scenario.externalCandidates.isEmpty || _preparingScenarioKey != null) {
      return;
    }
    setState(() {
      _preparingScenarioKey = scenario.key;
      _scenarioError = null;
    });
    try {
      final plan = await _service.prepareScenario(
        scenario: scenario,
        needs: _selectedBasketNeeds,
        profile: _rankingProfile,
        plan: _plan,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _preparingScenarioKey = null;
        _step = PurchaseStep.plan;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparingScenarioKey = null;
        _scenarioError =
            'El plan cambió o una alternativa dejó de ser válida. Recalcula antes de volver a guardarlo.';
      });
    }
  }

  Future<void> _reviewScenarioLine(PurchaseScenarioLine line) async {
    final need = _firstWhereOrNull(
      _needs,
      (item) => item.id == line.lineRef,
    );
    if (need == null) return;
    setState(() {
      _step = PurchaseStep.providers;
      _showScenarios = false;
      _selectingBasket = false;
      _returnToScenarios = true;
      _selectedNeed = need;
      _identitySelection = null;
      _identityController.clear();
      _showStockRejection = false;
      _stockReasonController.clear();
      _needCriteria = SupplyNeedCriteria.empty;
      _showNeedCriteria = false;
    });
    await _loadDecision(need);
  }

  Future<void> _addCandidateToPlan(PurchaseCandidate candidate) async {
    final need = _selectedNeed;
    if (need == null || _addingCandidateId != null) return;
    setState(() {
      _addingCandidateId = candidate.candidateId;
      _decisionError = null;
    });
    try {
      final plan = await _service.preparePlanLine(
        need: need,
        candidate: candidate,
        profile: _rankingProfile,
        plan: _plan,
        quantity: _inspectorQuantity?.toDouble(),
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _addingCandidateId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addingCandidateId = null;
        _decisionError =
            'No se pudo guardar la alternativa en el plan. Recarga y vuelve a intentarlo.';
      });
    }
  }

  /// Guarda o borra la nota de una línea del plan.
  ///
  /// `frames[plan].with_lines.line_disclosure`: «Alternativa y **nota**». Un
  /// fallo no se traga: la razón por la que se eligió un candidato es
  /// justamente lo que se pierde si nadie avisa que no se guardó.
  Future<void> _savePlanLineNote(PurchasePlanLine line, String? note) async {
    final plan = _plan;
    if (plan == null || _savingNoteLineId != null) return;
    setState(() {
      _savingNoteLineId = line.id;
      _decisionError = null;
    });
    try {
      final updated = await _service.setPlanLineNote(
        plan: plan,
        line: line,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        _plan = updated;
        _savingNoteLineId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingNoteLineId = null;
        _decisionError = 'No se pudo guardar la nota de la línea.';
      });
    }
  }

  /// «Sustituir candidato»: vuelve a Proveedores **con la necesidad de esa
  /// línea** abierta.
  ///
  /// No borra la línea antes de que haya reemplazo. Quitarla y luego mandar a
  /// buscar dejaría el plan peor que antes si el operador se arrepiente o no
  /// encuentra nada mejor: elegir otro candidato para la misma necesidad ya
  /// reemplaza la línea del lado del servidor.
  void _substitutePlanLine(PurchasePlanLine line) {
    final need = _firstWhereOrNull(
      _needs,
      (item) => item.id == line.sourceNeedId,
    );
    if (need == null) return;
    unawaited(_selectNeed(need));
    if (!mounted) return;
    setState(() => _step = PurchaseStep.providers);
  }

  Future<void> _removePlanLine(PurchasePlanLine line) async {
    final plan = _plan;
    if (plan == null ||
        _removingPlanLineId != null ||
        _updatingPlanLineId != null) {
      return;
    }
    setState(() {
      _removingPlanLineId = line.id;
      _decisionError = null;
    });
    try {
      final updated = await _service.removePlanLine(plan: plan, line: line);
      if (!mounted) return;
      setState(() {
        _plan = updated;
        _removingPlanLineId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _removingPlanLineId = null;
        _decisionError =
            'No se pudo quitar la línea. Recarga el plan antes de volver a intentarlo.';
      });
    }
  }

  /// Abre el editor de cantidad dentro de la fila del plan.
  void _openPlanQuantityEditor(PurchasePlanLine line) {
    if (_updatingPlanLineId != null || _removingPlanLineId != null) return;
    _planQuantityController.text = _formatSupplyQuantity(line.quantity);
    setState(() {
      _editingPlanLineId = line.id;
      _planQuantityError = null;
    });
  }

  void _cancelPlanQuantityEditor() {
    setState(() {
      _editingPlanLineId = null;
      _planQuantityError = null;
    });
  }

  Future<void> _commitPlanQuantity(PurchasePlanLine line) async {
    final plan = _plan;
    if (plan == null) return;
    final sourceNeed = _firstWhereOrNull(
      _needs,
      (need) => need.id == line.sourceNeedId,
    );
    final quantity = _parseSupplyQuantity(_planQuantityController.text);
    final maximum = sourceNeed?.quantity;
    if (quantity == null ||
        quantity <= 0 ||
        quantity > 999999 ||
        (maximum != null && quantity > maximum)) {
      setState(() {
        _planQuantityError = maximum != null
            ? 'Ingresa una cantidad entre 1 y ${_formatSupplyQuantity(maximum)}.'
            : 'Ingresa una cantidad válida.';
      });
      return;
    }
    setState(() {
      _editingPlanLineId = null;
      _planQuantityError = null;
    });
    if (!mounted || quantity == line.quantity) return;

    setState(() {
      _updatingPlanLineId = line.id;
      _decisionError = null;
    });
    try {
      final updated = await _service.updatePlanLineQuantity(
        plan: plan,
        line: line,
        quantity: quantity,
      );
      if (!mounted) return;
      setState(() => _plan = updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _decisionError =
            'La cantidad no se pudo guardar. Recarga el plan antes de volver a intentarlo.';
      });
    } finally {
      if (mounted) setState(() => _updatingPlanLineId = null);
    }
  }

  /// Frame 24 — corrección directa desde el stepper de la línea.
  ///
  /// Comparte el mismo tope que el editor escrito: nunca se planifica más de lo
  /// que la necesidad de origen pidió.
  Future<void> _setPlanQuantity(PurchasePlanLine line, int quantity) async {
    final plan = _plan;
    if (plan == null || quantity <= 0) return;
    final sourceNeed = _firstWhereOrNull(
      _needs,
      (need) => need.id == line.sourceNeedId,
    );
    final maximum = sourceNeed?.quantity;
    if (maximum != null && quantity > maximum) {
      setState(() {
        _decisionError =
            'La necesidad pidió ${_formatSupplyQuantity(maximum)}; el plan no puede superarla.';
      });
      return;
    }
    if (quantity == line.quantity) return;
    setState(() {
      _updatingPlanLineId = line.id;
      _decisionError = null;
    });
    try {
      final updated = await _service.updatePlanLineQuantity(
        plan: plan,
        line: line,
        quantity: quantity.toDouble(),
      );
      if (!mounted) return;
      setState(() => _plan = updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _decisionError =
            'La cantidad no se pudo guardar. Recarga el plan antes de volver a intentarlo.';
      });
    } finally {
      if (mounted) setState(() => _updatingPlanLineId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            constraints.maxWidth >= ResponsiveBreakpoints.desktopMin;
        return MainLayout(
          title: 'Asistente de compras',
          onBackPressed: () {
            if (_step == PurchaseStep.plan) {
              setState(
                () => _step = PurchaseStep.providers,
              );
              return;
            }
            if (_showScenarios) {
              setState(() => _showScenarios = false);
              return;
            }
            if (_returnToScenarios) {
              setState(() {
                _returnToScenarios = false;
                _selectingBasket = true;
                _showScenarios = true;
              });
              return;
            }
            if (!desktop && _selectedNeed != null) {
              setState(() => _selectedNeed = null);
              return;
            }
            if (_selectingBasket) {
              _toggleBasketMode();
              return;
            }
            // La captura anclada se cierra antes que nada: es la superficie
            // más superficial del paso.
            if (_showLocalPurchaseSheet) {
              _closeLocalPurchaseCapture();
              return;
            }
            if (_step == PurchaseStep.providers &&
                widget.initialNeedId == null) {
              setState(
                () => _step = PurchaseStep.need,
              );
              return;
            }
            ReturnNavigation.close(context, fallbackRoute: '/purchases');
          },
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWorkspaceHeader(desktop: desktop),
                if (_selectedNeed != null && _step != PurchaseStep.need)
                  _buildNeedBar(),
                if (_selectedNeed != null &&
                    _step != PurchaseStep.need &&
                    _showNeedCriteria)
                  _buildNeedCriteriaDisclosure(),
                Expanded(
                  child: _wrapWithLocalPurchaseSheet(
                    Padding(
                      // `geometry_shell.content_padding` del handoff-t23.
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: switch (_step) {
                        PurchaseStep.need => _buildRequestWorkspace(),
                        PurchaseStep.stock => _buildStockStep(),
                        PurchaseStep.providers =>
                          _buildResolveWorkspace(desktop: desktop),
                        PurchaseStep.plan => _buildPlanStep(compact: !desktop),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Un paso está disponible sólo cuando su dato de entrada existe. Navegar
  /// entre pasos nunca destruye el borrador, la selección ni el scroll.
  Set<PurchaseStep> get _enabledSteps {
    final need = _selectedNeed;
    return {
      PurchaseStep.need,
      // El paso de stock existe en los dos carriles: el conjunto elegible de
      // una necesidad de familia también tiene bodega que revisar.
      if (need != null) PurchaseStep.stock,
      if (need != null) PurchaseStep.providers,
      if (_plan != null) PurchaseStep.plan,
    };
  }

  Map<PurchaseStep, String> get _stepMeta {
    final snapshot = _inventorySnapshot;
    final resolution = _stockResolution;
    final ranking = _ranking;
    return {
      // Frames 01/19/22/26: el paso 1 describe la actividad, no un recuento.
      // El número de necesidades ya vive en su propia superficie.
      PurchaseStep.need: 'petición y revisión',
      // El plural se concuerda: «1 opciones» y «1 disponibles» se leen como un
      // descuido, y las palabras son parte del diseño.
      if (snapshot != null)
        PurchaseStep.stock: _countLabel(
          snapshot.availableToPromise ?? 0,
          'disponible',
          'disponibles',
        )
      // Carril familia: no hay un ATP único que mostrar —sumar variantes no
      // prueba cobertura—, así que el paso cuenta alternativas elegibles.
      else if (resolution != null && resolution.isOk)
        PurchaseStep.stock: _countLabel(
          resolution.counts.eligible,
          'alternativa',
          'alternativas',
        ),
      if (ranking != null)
        PurchaseStep.providers:
            _countLabel(ranking.items.length, 'opción', 'opciones'),
      if (_plan != null)
        PurchaseStep.plan: _countLabel(_plan!.lines.length, 'línea', 'líneas'),
    };
  }

  /// Recuento con su palabra concordada. Un solo lugar, para que ningún paso
  /// vuelva a decir «1 opciones».
  static String _countLabel(num count, String singular, String plural) {
    final rounded = count is int ? count : count.round();
    return '$rounded ${rounded == 1 ? singular : plural}';
  }

  void _openWorkspaceSection(PurchaseStep section) {
    if (!_enabledSteps.contains(section)) return;
    setState(() => _step = section);
  }

  /// El estado que la cabecera anuncia, con su punto semántico.
  ///
  /// **El contrato nombra tres, la app decía dos.** «Listo» y «Resultados
  /// parciales» (NOTES §36-37), y el frame 08 muestra el segundo justo cuando
  /// hay una precisión pendiente. La cabecera decía «Listo» con una pregunta
  /// abierta en pantalla: afirmaba que el análisis estaba completo mientras el
  /// propio módulo pedía un dato para poder comparar.
  ///
  /// No se inventa la condición: es la misma que el borrador ya usa para
  /// bloquearse (`clarificationRequired` en cualquiera de sus líneas).
  /// «Analizando» gana sobre las dos, porque mientras se carga todavía no hay
  /// resultado del que decir si es parcial.
  String get _moduleStatusLabel {
    if (_loadingDecision || _askingAssistant) return 'Analizando';
    final draft = _supplyNeedDraft;
    final pendingPrecision =
        draft != null && draft.lines.any((line) => line.clarificationRequired);
    return pendingPrecision ? 'Resultados parciales' : 'Listo';
  }

  Widget _buildWorkspaceHeader({required bool desktop}) {
    return PurchaseProcessBand(
      key: const ValueKey('intelligent-purchasing-sections'),
      active: _step,
      meta: _stepMeta,
      enabled: _enabledSteps,
      // `process_band` del spec: desktop y tablet comparten los cuatro pasos;
      // sólo el teléfono usa el stepper de tres piezas.
      compact: MediaQuery.sizeOf(context).width <
          ResponsiveBreakpoints.phoneMaxExclusive,
      statusLabel: _moduleStatusLabel,
      statusPartial: _moduleStatusLabel == 'Resultados parciales',
      onGo: _openWorkspaceSection,
    );
  }

  /// Lo que «Criterios» despliega: el resumen completo, sin el corte del «+N».
  ///
  /// Es una disclosure bajo la barra, no una superficie aparte, por la misma
  /// razón que la del borrador: leer los criterios no puede sacar al operador
  /// del paso en que está ni tapar la página. Copia la anatomía de
  /// `_buildDraftLineCriteriaDisclosure` —panel `surfaceContainerLow` con
  /// hairline izquierdo de 3 px— porque es el mismo objeto dicho dos veces en
  /// el recorrido, y verlo distinto haría dudar de si es lo mismo.
  Widget _buildNeedCriteriaDisclosure() {
    final theme = Theme.of(context);
    final tokens = PurchaseTokens.of(context);
    final criteria = _needCriteria;
    return Container(
      key: const ValueKey('need-criteria-disclosure'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Criterios interpretados',
                  style: PurchaseType.panelTitle.copyWith(color: tokens.ink),
                ),
              ),
              TextButton(
                key: const ValueKey('need-criteria-close'),
                onPressed: () => setState(() => _showNeedCriteria = false),
                child: const Text('Ocultar'),
              ),
            ],
          ),
          if (criteria.categoryPath != null) ...[
            const SizedBox(height: 6),
            Text(
              'Categoría: ${criteria.categoryPath}',
              style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
            ),
          ],
          for (final predicate in criteria.predicates) ...[
            const SizedBox(height: 6),
            Text(
              _criterionLabel(predicate),
              style: PurchaseType.body.copyWith(color: tokens.ink),
            ),
          ],
          if (criteria.commercialPreference?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              criteria.commercialPreference!.trim(),
              style: PurchaseType.body.copyWith(color: tokens.ink),
            ),
            const SizedBox(height: 2),
            // Se dice, porque el operador lo escribió y merece verlo, pero
            // sin dejar creer que ordena la lista: quedó demostrado que el
            // texto libre no gobierna el ranking.
            Text(
              'Nota del operador. No ordena los proveedores.',
              style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
            ),
          ],
        ],
      ),
    );
  }

  /// Fila persistente de la necesidad. La edición ocurre aquí mismo: el owner
  /// rechazó explícitamente editarla en un diálogo centrado.
  Widget _buildNeedBar() {
    final need = _selectedNeed!;
    return SupplyNeedBar(
      title: need.productName ?? need.description,
      // La barra pluralizaba a mano —«1 unidades» con una llanta suelta— y
      // dejaba pasar crudo cualquier otra unidad. El vocabulario tiene un dueño
      // único en este módulo y es el mismo que recibe el inspector.
      quantityLabel: '${_formatSupplyQuantity(need.quantity)} '
          '${purchaseUnitLabel(need.unit, need.quantity)}',
      // La barra ya imprime la cantidad en su propia columna: repetirla en el
      // resumen dejaba «2 unidades · 2 unidades · Solicitud directa».
      //
      // **El origen es el respaldo, no el contenido.** El contrato pide acá el
      // resumen de criterios («rodado 27,5 · ancho > 2,0 · gama económica ·
      // buen margen · +1», NOTES §44-47). Esta ranura recibía siempre el
      // origen, así que una necesidad interpretada se veía igual que una
      // escrita a mano. Cuando hay criterios mandan ellos; cuando no —una
      // solicitud directa sin predicados— sigue el origen, que es lo único
      // cierto que queda por decir.
      criteriaSummary: _needCriteria.isNotEmpty
          ? _criteriaSummaryLine(_needCriteria)
          : _needOrigin(need),
      // La CTA que el contrato nombra existía en el widget y **nadie la
      // pasaba**: era código muerto. Sólo se ofrece cuando hay algo que
      // desplegar, porque un botón que abre una lista vacía miente.
      onOpenCriteria: _needCriteria.isNotEmpty
          ? () => setState(() => _showNeedCriteria = !_showNeedCriteria)
          : null,
      editing: _editingNeed,
      onEdit: () {
        _needDescriptionController.text = need.description;
        _needQuantityController.text = _formatSupplyQuantity(need.quantity);
        setState(() => _editingNeed = true);
      },
      onCancel: () => setState(() => _editingNeed = false),
      editor: _buildNeedInlineEditor(need),
    );
  }

  Widget _buildNeedInlineEditor(SupplyNeed need) {
    return Wrap(
      spacing: 11,
      runSpacing: 9,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            key: const ValueKey('need-inline-description'),
            controller: _needDescriptionController,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 116,
          child: TextField(
            key: const ValueKey('need-inline-quantity'),
            controller: _needQuantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        FilledButton(
          onPressed: _runningCommand ? null : () => _saveNeedInline(need),
          child: const Text('Guardar'),
        ),
        TextButton(
          onPressed: () => setState(() => _editingNeed = false),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Future<void> _saveNeedInline(SupplyNeed need) async {
    final description = _needDescriptionController.text.trim();
    final quantity = double.tryParse(
      _needQuantityController.text.trim().replaceAll(',', '.'),
    );
    if (description.isEmpty || quantity == null || quantity <= 0) return;
    setState(() => _runningCommand = true);
    try {
      final updated = await _service.updateNeed(
        need,
        description: description,
        productId: need.productId,
        quantity: quantity,
      );
      if (!mounted) return;
      setState(() {
        _editingNeed = false;
        _runningCommand = false;
        _selectedNeed = updated;
        _needs = _needs
            .map((item) => item.id == updated.id ? updated : item)
            .toList(growable: false);
      });
      await _loadDecision(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningCommand = false;
        _decisionError = 'No se pudo guardar la necesidad. Intenta de nuevo.';
      });
    }
  }

  /// Paso 2 — la bodega antes de cotizar.
  Widget _buildStockStep() {
    final need = _selectedNeed;
    final snapshot = _inventorySnapshot;
    final resolution = _stockResolution;
    final external = _externalCandidates;
    // Las cards son de teléfono. En 834 el spec sigue pidiendo la fila con
    // media 38 (`frames[single-stock].geometry."834"`), así que el corte es
    // el de phone y no el de escritorio.
    final compact = MediaQuery.sizeOf(context).width <
        ResponsiveBreakpoints.phoneMaxExclusive;
    if (need == null) return const SizedBox.shrink();
    if (_loadingDecision) {
      return const Center(child: CircularProgressIndicator());
    }
    // Reservar o rechazar stock puede fallar, y el aviso vivía en otro paso:
    // el operador tocaba «Usar este stock», no pasaba nada visible y creía que
    // había quedado reservado.
    final notice = _decisionNotice();
    // **El mismo contrato que Proveedores.** Sin decisión cargada, este paso
    // no puede afirmar «no fue posible verificar el stock interno»: eso culpa
    // a la bodega de un fallo que puede ser de la lectura entera o de una
    // escritura ajena, y además pisaba «Recargar la necesidad» con un
    // reintento genérico que reintenta lo que no corresponde.
    if (_decisionUnavailable) {
      return ListView(
        key: const ValueKey('stock-step-no-decision'),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        children: [
          ...?notice,
          if (_showsLoadFailure)
            DecisionLoadFailedSurface(
              busy: _loadingDecision,
              onRetry: () => unawaited(_retryDecisionLoad()),
            ),
        ],
      );
    }
    // La evaluación técnica no dejó un conjunto que mirar. El estado y su
    // acción los publica la lectura externa, que es su dueña; repetirlos acá
    // con otras palabras sería una segunda verdad.
    if (resolution != null && !resolution.isOk) {
      if (external != null) {
        return ListView(
          key: const ValueKey('stock-step-state'),
          children: [
            ...?notice,
            ExternalCandidatesStateSurface(
              result: external,
              onEditNeed: () => setState(() => _step = PurchaseStep.need),
              onRegisterLocalPurchase: _openLocalPurchaseCapture,
            ),
          ],
        );
      }
      return SingleChildScrollView(
        child: VbNotice(
          title: 'La necesidad todavía no define un conjunto que revisar',
          body: 'Edita la necesidad para dejarla dentro de una categoría.',
          tone: VbNoticeTone.neutral,
          action: TextButton(
            onPressed: () => setState(() => _step = PurchaseStep.need),
            child: const Text('Editar la necesidad'),
          ),
        ),
      );
    }
    // **Carril familia: la bodega del conjunto elegible.** Depender del
    // snapshot exacto dejaba esta pantalla diciendo «no fue posible verificar
    // el stock interno» cuando el servidor sí había respondido.
    if (snapshot == null && resolution != null && resolution.isFamilyLane) {
      if (notice != null) {
        // El aviso va arriba y la decisión conserva su propio scroll: anidar
        // dos viewports verticales revienta el layout.
        return Column(
          key: const ValueKey('family-stock-with-notice'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: notice,
              ),
            ),
            // La decisión sigue disponible debajo del aviso: un fallo de
            // comando no borra la bodega que sí se leyó.
            Expanded(
              child: FamilyStockOptions(
                resolution: resolution,
                compact: compact,
                busy: _runningCommand || _refreshingResults,
                onChooseProduct: (option) => unawaited(
                  _chooseFamilyProductId(option.productId),
                ),
                onShowMore: () => unawaited(_showMoreFamilyStock()),
                onCompareProviders: () =>
                    setState(() => _step = PurchaseStep.providers),
              ),
            ),
          ],
        );
      }
      return FamilyStockOptions(
        resolution: resolution,
        compact: compact,
        busy: _runningCommand || _refreshingResults,
        onChooseProduct: (option) => unawaited(
          _chooseFamilyProductId(option.productId),
        ),
        onShowMore: () => unawaited(_showMoreFamilyStock()),
        onCompareProviders: () =>
            setState(() => _step = PurchaseStep.providers),
      );
    }
    if (snapshot == null) {
      return SingleChildScrollView(
        child: VbNotice(
          title: 'No fue posible verificar el stock interno',
          body: 'Reintenta antes de tomar una decisión de compra.',
          tone: VbNoticeTone.warning,
          action: TextButton(
            onPressed: () => _loadDecision(need),
            child: const Text('Reintentar'),
          ),
        ),
      );
    }
    final stockSurface = InternalStockSurface(
      components: snapshot.components,
      requestedQuantity: need.quantity,
      compact: compact,
      assignable: snapshot.assignable &&
          need.internalStockRejectionReason == null &&
          need.supplyState == 'open',
      busy: _runningCommand,
      rejectionReason: need.internalStockRejectionReason,
      onAssign: _assignStock,
      onCompareProviders: () => setState(() => _step = PurchaseStep.providers),
    );
    if (notice == null) return stockSurface;
    return Column(
      key: const ValueKey('exact-stock-with-notice'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: notice,
          ),
        ),
        Expanded(child: stockSurface),
      ],
    );
  }

  /// Paso 4 — plan borrador. El vacío es inline, nunca una isla centrada.
  Widget _buildPlanStep({required bool compact}) {
    final plan = _plan;
    if (plan == null || plan.lines.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: 14),
        child: PlanEmptyInline(
          compact: compact,
          onChooseCandidate: () =>
              setState(() => _step = PurchaseStep.providers),
          onRegisterLocalPurchase: _openLocalPurchaseCapture,
        ),
      );
    }
    return _buildPlanSurface();
  }

  /// Paso 1 — Necesidad.
  ///
  /// Es una conversación con ritmo, no una tabla de borradores: petición del
  /// operador, interpretación en lenguaje natural, la precisión material
  /// cuando hace falta, la evidencia consultada colapsada, y una salida
  /// direccional al paso siguiente. El composer se compacta después de
  /// analizar para no duplicar el espacio de entrada.
  Widget _buildRequestWorkspace() {
    final analysed = _assistantText != null ||
        _assistantError != null ||
        _supplyNeedDraft != null ||
        _askingAssistant;
    return Align(
      // El prototipo centra la columna con `margin:0 auto`. Fijarla arriba a la
      // izquierda era la mitad perdida de `column_max`: con el mismo ancho, la
      // pantalla se lee como otra cosa.
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        // `frames[single-need].geometry.column_max`.
        constraints: const BoxConstraints(
          maxWidth: PurchaseSurfaceGeometry.narrowColumnMax,
        ),
        child: SingleChildScrollView(
          key: const ValueKey('intelligent-purchasing-request-scroll'),
          padding: const EdgeInsets.only(top: 14, bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildComposer(compact: analysed),
              if (_lastUserMessage != null) ...[
                const SizedBox(height: 11),
                _buildUtteranceBubble(_lastUserMessage!),
              ],
              // El borrador sobrevive sólo a una respuesta de aclaración, así
              // que «borrador en pantalla + ocupado» significa exactamente eso:
              // su estado de carga vive en el propio botón («Enviando…») y esta
              // fila lo duplicaría, además diciendo que interpreta una petición
              // que nadie volvió a escribir.
              if (_askingAssistant && _supplyNeedDraft == null) ...[
                const SizedBox(height: 11),
                _buildInterpretingRow(),
              ],
              if (_supplyNeedDraft != null) ...[
                const SizedBox(height: 11),
                _buildSupplyNeedDraftReview(_supplyNeedDraft!),
              ] else if (!_askingAssistant &&
                  (_assistantError != null || _assistantText != null)) ...[
                const SizedBox(height: 11),
                _buildAssistantResult(),
              ],
              if (_needs.isNotEmpty) ...[
                const SizedBox(height: 18),
                _buildOpenNeedsSection(),
              ],
              if (_selectedNeed != null && _supplyNeedDraft == null) ...[
                const SizedBox(height: 18),
                _buildNextStepCta(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// La frase del operador, alineada a la derecha y con la geometría de burbuja
  /// del handoff: nunca se pierde, y la interpretación se lee contra ella.
  Widget _buildUtteranceBubble(String message) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          key: const ValueKey('purchase-utterance'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(2),
            ),
          ),
          child: Text(
            message,
            style: PurchaseType.body
                .copyWith(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
      ),
    );
  }

  /// Estado «interpretando»: una línea con spinner, sin vaciar lo ya leído.
  Widget _buildInterpretingRow() {
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('purchase-interpreting'),
      children: [
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Interpretando tu petición…',
            style: PurchaseType.body
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  /// Índice de necesidades abiertas, como lista de texto estable.
  ///
  /// Es un panel con la lista a sangre: el encabezado lleva el padding del
  /// panel y cada fila su propia línea interna. Suelto sobre el fondo, como
  /// estaba, no se leía como un bloque.
  Widget _buildOpenNeedsSection() {
    final tokens = PurchaseTokens.of(context);
    return PurchasePanel(
      padded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Necesidades abiertas',
                        style: PurchaseType.sectionTitle
                            .copyWith(color: tokens.ink),
                      ),
                    ),
                    if (_needs.length > 1)
                      PurchaseInlineAction(
                        key: const ValueKey('compare-basket'),
                        label: _selectingBasket
                            ? 'Comparar canasta (${_basketNeedIds.length})'
                            : 'Armar canasta',
                        onPressed: _loadingScenarios
                            ? null
                            : _selectingBasket
                                ? _compareBasket
                                : _toggleBasketMode,
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Retoma el stock, las alternativas y el plan sin volver a escribir la solicitud.',
                  style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                ),
              ],
            ),
          ),
          for (final need in _needs)
            _OpenNeedRow(
              key: ValueKey('supply-need-${need.id}'),
              need: need,
              selected: _selectingBasket
                  ? _basketNeedIds.contains(need.id)
                  : _selectedNeed?.id == need.id,
              selecting: _selectingBasket,
              subtitle: _needSubtitle(need),
              onTap: () => _selectNeed(need),
            ),
        ],
      ),
    );
  }

  /// Salida direccional: la decisión termina moviéndose al paso siguiente, no
  /// en un botón aislado al pie de una página vacía.
  Widget _buildNextStepCta() {
    final need = _selectedNeed!;
    final theme = Theme.of(context);
    final next =
        need.hasConfirmedProduct ? PurchaseStep.stock : PurchaseStep.providers;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            need.hasConfirmedProduct
                ? 'La bodega se revisa antes de cotizar.'
                : 'Falta confirmar el producto exacto antes de comparar.',
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              key: const ValueKey('go-to-next-step'),
              onPressed: () => _openWorkspaceSection(next),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text('Ir a ${next.label}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResolveWorkspace({required bool desktop}) {
    if (_loadingNeeds) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return SingleChildScrollView(
        child: VbNotice(
          title: _loadError!,
          tone: VbNoticeTone.warning,
          action: TextButton(
            onPressed: _loadNeeds,
            child: const Text('Reintentar'),
          ),
        ),
      );
    }
    if (_needs.isEmpty) {
      return SingleChildScrollView(
        child: VbNotice(
          key: const ValueKey('intelligent-purchasing-empty-needs'),
          title: 'Todavía no hay necesidades por resolver',
          body:
              'Describe una o varias piezas y revisa cómo las interpretó el asistente antes de guardarlas.',
          tone: VbNoticeTone.neutral,
          action: TextButton(
            onPressed: () => _openWorkspaceSection(PurchaseStep.need),
            child: const Text('Nueva búsqueda'),
          ),
        ),
      );
    }

    if (_showScenarios) return _buildScenarioSurface();

    final width = MediaQuery.sizeOf(context).width;
    final phone = width < ResponsiveBreakpoints.phoneMaxExclusive;
    final inspected = _inspectedCandidate;

    final results = _buildProviderResults(phone: phone);

    if (inspected == null) return results;

    if (desktop) {
      // Split pane: ambos paneles conservan ancho útil y el detalle no tapa
      // la comparación.
      // Colapsado el panel deja su riel de 28 px, no un panel estrecho: es lo
      // que el spec pide y lo que distingue colapsar de cerrar.
      if (_inspectorCollapsed) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: results),
            CandidateInspectorRail(
              onExpand: () => setState(() => _inspectorCollapsed = false),
            ),
          ],
        );
      }
      final paneWidth = _inspectorWidth.clamp(
        PurchaseSurfaceGeometry.inspectorMinWidth,
        PurchaseSurfaceGeometry.inspectorMaxWidth,
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: results),
          _InspectorPaneHandle(
            width: paneWidth,
            onDelta: (delta) => setState(() {
              // Arrastrar es pedir un ancho a mano: sale del colapso en vez de
              // pelear contra él y no mover nada.
              _inspectorCollapsed = false;
              _inspectorWidth = (_inspectorWidth - delta).clamp(
                PurchaseSurfaceGeometry.inspectorMinWidth,
                PurchaseSurfaceGeometry.inspectorMaxWidth,
              );
            }),
          ),
          SizedBox(
            width: paneWidth,
            child: _buildInspector(inspected, collapsible: true),
          ),
        ],
      );
    }

    if (phone) {
      // **Frame 17: la hoja sube sobre el contenido, sin velo.** El encabezado
      // de resultados y «Orden y filtros» siguen visibles y sin atenuar; la
      // app **reemplazaba** la región entera por el detalle y ofrecía un
      // «Volver a las opciones» que el contrato no pide. Perder de vista la
      // lista es perder el contexto de contra qué se estaba comparando.
      //
      // Misma anatomía que la hoja de compra local y que el edge sheet de
      // tablet, que ya viven en este archivo: la franja libre de arriba queda
      // interactiva y sólo cierra el detalle —no es un scrim— y la altura sale
      // del `LayoutBuilder` porque un `FractionallySizedBox` dentro de una
      // `Column` recibe altura infinita y revienta el layout.
      //
      // El `×` no se repone acá: el panel ya trae el suyo
      // (`close-candidate-inspector`), y dos cierres en la misma cabecera
      // serían dos formas de decir lo mismo.
      return Stack(
        children: [
          Positioned.fill(child: results),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('inspector-sheet-dismiss'),
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _inspectedCandidateId = null),
                    ),
                  ),
                  SizedBox(
                    height: constraints.maxHeight *
                        PurchaseSurfaceGeometry.phoneSheetHeightFactor,
                    child: Material(
                      elevation: 8,
                      child: _buildInspector(inspected),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Tablet: edge sheet derecho. El área libre a la izquierda queda
    // interactiva y sólo cierra el detalle; no es un scrim.
    return Stack(
      children: [
        Positioned.fill(child: results),
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _inspectedCandidateId = null),
                ),
              ),
              SizedBox(
                width: PurchaseSurfaceGeometry.tabletEdgeSheetWidth,
                child: Material(
                  elevation: 8,
                  child: _buildInspector(inspected),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// El candidato abierto, **de cualquiera de los dos grupos**.
  ///
  /// Buscar sólo en el ranking accionable dejaba a los no verificados sin
  /// inspector: se listaban, se podían tocar, y no pasaba nada. Un grupo que
  /// se muestra pero no se puede abrir es peor que no mostrarlo.
  PurchaseCandidate? get _inspectedCandidate {
    final id = _inspectedCandidateId;
    if (id == null) return null;
    final ranking = _ranking;
    final unverified = _externalCandidates?.unverifiedItems ?? const [];
    return _firstWhereOrNull(
      [...?ranking?.items, ...unverified],
      (candidate) => candidate.candidateId == id,
    );
  }

  Widget _buildInspector(
    PurchaseCandidate candidate, {
    /// Sólo el split pane de escritorio ofrece `»`: es el único sitio donde
    /// colapsar devuelve ancho a algo. En el edge sheet de tablet y en la
    /// hoja de teléfono el control no tendría a quién cederlo.
    bool collapsible = false,
  }) {
    final need = _selectedNeed;
    final plannedLine = need == null || _plan == null
        ? null
        : _firstWhereOrNull(
            _plan!.lines,
            (line) => line.sourceNeedId == need.id,
          );
    // La cantidad del pie: la elegida si el operador la tocó, y si no la de
    // la necesidad, que es lo que ya declaró.
    final quantity = (_inspectorQuantity ?? need?.quantity ?? 1).toDouble();
    return CandidateInspectorPanel(
      candidate: candidate,
      quantity: quantity,
      // El vocabulario de unidades tiene un dueño único en este módulo; el
      // inspector lo recibe concordado en vez de asumir «u.».
      unitLabel: purchaseUnitLabel(need?.unit ?? 'unit', quantity),
      onQuantityChanged: (value) =>
          setState(() => _inspectorQuantity = value),
      onToggleCollapsed: collapsible
          ? () => setState(
                () => _inspectorCollapsed = !_inspectorCollapsed,
              )
          : null,
      collapsed: _inspectorCollapsed,
      adding: _addingCandidateId == candidate.candidateId,
      alreadyInPlan: plannedLine?.candidateId == candidate.candidateId,
      onClose: () => setState(() => _inspectedCandidateId = null),
      onAddToPlan: () => _addCandidateToPlan(candidate),
      // Carril familia: la necesidad no tiene identidad, así que el pie ofrece
      // «Elegir producto». «Agregar al plan» aparece recién después de
      // confirmar y releer, porque son dos escrituras distintas.
      onChooseProduct: need != null && !need.hasConfirmedProduct
          ? () => unawaited(_chooseFamilyProduct(candidate))
          : null,
      onOpenSupplier: candidate.supplierWebsite == null
          ? null
          : () => _openSupplier(
                candidate.supplierWebsite!,
                supplierName: candidate.supplierName,
              ),
    );
  }

  /// Entrada de la petición.
  ///
  /// Antes de analizar ocupa el espacio que merece la única decisión de la
  /// pantalla. Después se compacta a una línea reabrible: el resultado manda,
  /// y no se duplica un campo grande que ya cumplió su función.
  Widget _buildComposer({required bool compact}) {
    if (compact && !_composerExpanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('intelligent-purchasing-composer-reopen'),
          onPressed: () => setState(() => _composerExpanded = true),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Escribir otra petición'),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Petición al asistente de compras',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El bloque de captura es UN panel, no un título, un subtítulo, una
          // caja y unos botones apoyados sobre el fondo. El título y el
          // subtítulo que había acá no existen en el diseño: se fueron.
          // El módulo abre por lo que hay que comprar, no por un campo vacío.
          // El texto libre queda debajo, como salida para lo que no está en la
          // lista — es la puerta de emergencia, no la puerta de entrada.
          //
          // Se muestra sólo mientras no hay análisis en pantalla: una vez que
          // la persona pidió algo, el resultado manda y la lista de la mañana
          // pasa a ser ruido. El parámetro `compact` de este builder significa
          // exactamente «ya se analizó», no «pantalla angosta».
          if (!compact && !_priorityUnavailable && _priority.isNotEmpty) ...[
            PurchasePriorityPanel(
              suggestions: _priority,
              busyEntityId: _takingPriorityId,
              onTake: _takePriority,
            ),
            const SizedBox(height: PurchaseMetrics.stageGap),
            Text(
              '¿Necesitas algo que no está en la lista?',
              style: PurchaseType.meta.copyWith(
                color: PurchaseTokens.of(context).inkMuted,
              ),
            ),
            const SizedBox(height: 6),
          ],
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _composerController,
            builder: (context, value, _) => PurchaseComposer(
              controller: _composerController,
              busy: _askingAssistant,
              examplesOpen: _showExamples,
              // El prototipo apaga la acción mientras no hay nada que analizar.
              onAnalyze: value.text.trim().isEmpty
                  ? null
                  : () => unawaited(_askAssistant()),
              onToggleExamples: () =>
                  setState(() => _showExamples = !_showExamples),
            ),
          ),
          if (compact)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _composerExpanded = false),
                child: const Text('Cerrar'),
              ),
            ),
          if (_showExamples) ...[
            const SizedBox(height: 10),
            for (final example in const [
              'Necesito neumáticos 27,5 de ancho mayor a 2,0, económicos pero con buen margen',
              'Necesito piñones, rayos, neumáticos y llantas',
              'Necesito hoy un piñón Shimano; revisa también talleres locales',
            ])
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    _composerController.text = example;
                    setState(() => _showExamples = false);
                  },
                  child: Text(example, textAlign: TextAlign.left),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssistantResult() {
    if (_askingAssistant && _assistantText == null) {
      return const VbNotice(
        title: 'Analizando la petición',
        body:
            'Estoy interpretando especificaciones, stock y evidencia de compra.',
        tone: VbNoticeTone.info,
      );
    }
    if (_assistantError != null) {
      return VbNotice(
        title: _assistantError!,
        tone: VbNoticeTone.warning,
        action: TextButton(
          key: const ValueKey('assistant-retry'),
          onPressed: _askingAssistant || _replayMessage == null
              ? null
              : () => _askAssistant(
                    message: _replayMessage,
                    isClarificationAnswer: _replayIsClarificationAnswer,
                  ),
          child: const Text('Reintentar'),
        ),
      );
    }
    final supplyDraft = _supplyNeedDraft;
    if (supplyDraft != null) {
      return _buildSupplyNeedDraftReview(supplyDraft);
    }
    final visibleActions = _showAllAssistantActions
        ? _assistantCards
        : _assistantCards.take(2).toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Análisis del asistente',
                    style: PurchaseType.panelTitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: _assistantText ?? '',
              selectable: true,
            ),
            if (visibleActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              ...visibleActions.map(
                (card) => AIAssistantCompactActionTile(
                  card: card,
                  includeFilterSummary: false,
                  onTap: () => _handleAssistantCard(card),
                ),
              ),
              if (_assistantCards.length > 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(
                      () =>
                          _showAllAssistantActions = !_showAllAssistantActions,
                    ),
                    child: Text(
                      _showAllAssistantActions
                          ? 'Mostrar menos'
                          : 'Ver ${_assistantCards.length - 2} acciones más',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Respuesta del asistente dentro de la conversación.
  ///
  /// No es una tarjeta de borrador: es lo que el asistente entendió, dicho en
  /// una frase, con el resumen de cada necesidad debajo y una sola salida. Sin
  /// cabecera de tabla, sin fila numerada, sin footer, sin contenedor exterior.
  Widget _buildSupplyNeedDraftReview(AIAssistantSupplyNeedDraft draft) {
    final theme = Theme.of(context);
    final blocked = draft.lines.any((line) => line.clarificationRequired);
    return Column(
      key: const ValueKey('supply-draft-review-surface'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Resumen derivado y breve. La prosa del modelo puede ser larga y
        //    empujar la pregunta bajo el fold: se muestra bajo demanda.
        Text(
          _derivedInterpretationSummary(draft),
          key: const ValueKey('assistant-interpretation'),
          style: PurchaseType.sectionTitle,
        ),
        if (_hasDistinctAssistantExplanation(draft)) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('assistant-explanation-toggle'),
              onPressed: () => setState(
                () => _showAssistantExplanation = !_showAssistantExplanation,
              ),
              child: Text(
                _showAssistantExplanation
                    ? 'Ocultar explicación del análisis'
                    : 'Ver explicación del análisis',
              ),
            ),
          ),
          if (_showAssistantExplanation)
            Text(
              _assistantText!.trim(),
              key: const ValueKey('assistant-explanation-body'),
              style: PurchaseType.meta
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
        const SizedBox(height: 6),
        Text(
          'Los costos vienen del historial de compras; la disponibilidad del proveedor no se afirma sin una fuente vigente.',
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),

        // 2. Resumen compacto por necesidad, separado sólo por hairlines.
        for (var index = 0; index < draft.lines.length; index++)
          _buildSupplyNeedDraftLine(
            draft.lines[index],
            index: index,
            count: draft.lines.length,
          ),

        // 3. La precisión material vive en el flujo, como pregunta.
        if (blocked) ...[
          const SizedBox(height: 14),
          _buildMaterialClarification(draft),
        ],

        // 4. Evidencia consultada: disclosure secundaria, etiqueta honesta.
        const SizedBox(height: 14),
        _buildConsultedEvidenceDisclosure(),

        if (_supplyNeedSaveError != null) ...[
          const SizedBox(height: 12),
          Text(
            _supplyNeedSaveError!,
            style: PurchaseType.meta.copyWith(color: theme.colorScheme.error),
          ),
        ],

        // 5. Una sola salida, al final de la decisión.
        const SizedBox(height: 18),
        _buildDraftCommitCta(draft, blocked: blocked),
      ],
    );
  }

  /// «Entendí …» derivado siempre de las líneas: es corto y predecible, y deja
  /// la pregunta y su acción arriba del fold. Nunca inventa criterios.
  String _derivedInterpretationSummary(AIAssistantSupplyNeedDraft draft) {
    final parts = draft.lines
        .map(
          (line) =>
              '${line.description} (${_formatSupplyQuantity(line.quantity)} '
              '${purchaseUnitLabel(line.unit, line.quantity)})',
        )
        .join('; ');
    return 'Entendí $parts. Priorizando ${_supplyProfileLabel(draft.profile)}.';
  }

  /// La prosa sólo merece un disclosure si dice algo distinto del resumen.
  bool _hasDistinctAssistantExplanation(AIAssistantSupplyNeedDraft draft) {
    final narrated = _assistantText?.trim();
    if (narrated == null || narrated.isEmpty) return false;
    return narrated != _derivedInterpretationSummary(draft);
  }

  // ── Aclaración progresiva (frames 08/19) ───────────────────────────────
  //
  // El contrato ya distingue los dos casos y la UI los separa:
  //  · `clarificationRequired == true`  → falta un hecho que el operador tiene.
  //    Bloquea y se pregunta, una pregunta a la vez.
  //  · `clarificationRequired == false` con `clarification != null` → límite del
  //    ERP. No bloquea, no abre inputs y no vive bajo «hace falta una
  //    precisión»: es una advertencia junto a su línea.

  String _clarificationKeyOf(String lineRef, String promptId) =>
      '$lineRef|$promptId';

  /// Prompts pendientes en orden de contrato: por línea y, dentro de cada
  /// línea, por la posición que el modelo eligió. El cliente no reordena.
  List<
      ({
        AIAssistantSupplyNeedDraftLine line,
        AIAssistantSupplyNeedClarificationPrompt prompt
      })> _clarificationQueue(
    AIAssistantSupplyNeedDraft draft,
  ) =>
      [
        for (final line in draft.lines)
          if (line.clarificationRequired)
            for (final prompt in line.clarificationPrompts)
              (line: line, prompt: prompt),
      ];

  /// Líneas que bloquean pero llegaron sin prompts: card v1 o modelo antiguo.
  List<AIAssistantSupplyNeedDraftLine> _legacyBlockingLines(
    AIAssistantSupplyNeedDraft draft,
  ) =>
      draft.lines
          .where((line) =>
              line.clarificationRequired && line.clarificationPrompts.isEmpty)
          .toList(growable: false);

  bool _isAnswered(String lineRef, String promptId) {
    final key = _clarificationKeyOf(lineRef, promptId);
    return _clarificationAnswers.containsKey(key) ||
        _clarificationUnknown.contains(key);
  }

  /// Longitudes máximas de la respuesta. Se aplican con formatters para no
  /// pintar el contador de caracteres, que aquí sería ruido.
  static const int _clarificationNumberMaxLength = 32;
  static const int _clarificationTextMaxLength = 240;

  TextEditingController _clarificationControllerFor(String key) =>
      _clarificationInputs.putIfAbsent(key, TextEditingController.new);

  /// Normaliza un número escrito como lo escribe la gente: coma o punto, con
  /// signo opcional. Devuelve la forma canónica, o `null` si no es un número.
  String? _normalizeClarificationNumber(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null || !parsed.isFinite) return null;
    return trimmed;
  }

  void _setClarificationAnswer(String lineRef, String promptId, String value) {
    setState(() {
      final key = _clarificationKeyOf(lineRef, promptId);
      _clarificationUnknown.remove(key);
      _clarificationAnswers[key] = value;
    });
  }

  void _setClarificationUnknown(String lineRef, String promptId) {
    setState(() {
      final key = _clarificationKeyOf(lineRef, promptId);
      _clarificationAnswers.remove(key);
      _clarificationUnknown.add(key);
    });
  }

  /// Confirma el borrador de un campo libre sin desmontarlo mientras la
  /// persona todavía está escribiendo. Marcarlo como respondido desde
  /// `onChanged` hacía que el primer carácter reemplazara inmediatamente el
  /// campo por el resumen (por ejemplo, `274` terminaba guardado como `2`).
  void _commitClarificationInput(
    AIAssistantSupplyNeedDraftLine line,
    AIAssistantSupplyNeedClarificationPrompt prompt,
  ) {
    final key = _clarificationKeyOf(line.lineRef, prompt.id);
    final raw = _clarificationControllerFor(key).text.trim();
    final isNumber =
        prompt.inputKind == AIAssistantSupplyNeedClarificationInputKind.number;
    final normalized = isNumber ? _normalizeClarificationNumber(raw) : raw;
    if (normalized == null || normalized.isEmpty) {
      setState(() {
        _clarificationInputErrors[key] = isNumber
            ? 'Escribe sólo un número (por ejemplo 584 o 584,5).'
            : 'Escribe una respuesta antes de continuar.';
      });
      return;
    }
    setState(() {
      _clarificationUnknown.remove(key);
      _clarificationInputErrors.remove(key);
      _clarificationAnswers[key] = normalized;
    });
  }

  /// Mensaje autocontenido con la petición original y sólo lo respondido.
  ///
  /// Viaja como mensaje del operador: el servidor no debe tratarlo como dato
  /// de confianza, y por eso no lleva nada que el cliente no haya visto.
  String _encodeClarificationAnswers(AIAssistantSupplyNeedDraft draft) {
    final answers = <Map<String, Object?>>[];
    for (final entry in _clarificationQueue(draft)) {
      final key = _clarificationKeyOf(entry.line.lineRef, entry.prompt.id);
      final unknown = _clarificationUnknown.contains(key);
      final value = _clarificationAnswers[key];
      if (!unknown && value == null) continue;
      answers.add({
        'lineRef': entry.line.lineRef,
        'promptId': entry.prompt.id,
        'question': entry.prompt.question,
        if (unknown) 'unknown': true else 'answer': value,
      });
    }
    return jsonEncode(<String, Object?>{
      'kind': 'supply_need_clarification_answers',
      'originalRequest': _lastUserMessage ?? '',
      'answers': answers,
    });
  }

  Future<void> _submitClarificationAnswers(
    AIAssistantSupplyNeedDraft draft,
  ) async {
    if (_askingAssistant) return;
    final payload = _encodeClarificationAnswers(draft);
    // La ronda la cuenta la confirmación del servidor, no el envío: así un
    // reintento exitoso —que entra por el botón Reintentar y no por aquí—
    // también cuenta, y un fallo de transporte no gasta ninguna.
    await _askAssistant(message: payload, isClarificationAnswer: true);
  }

  /// Una sola pregunta activa: la primera sin responder de la cola.
  Widget _buildMaterialClarification(AIAssistantSupplyNeedDraft draft) {
    final theme = Theme.of(context);
    final queue = _clarificationQueue(draft);
    final legacy = _legacyBlockingLines(draft);

    // Sin prompts estructurados se conserva la salida anterior tal cual.
    if (queue.isEmpty) return _buildLegacyClarification(legacy);

    // Tope de rondas: no hay un cuarto interrogatorio.
    if (_clarificationRound >= _clarificationRoundCap) {
      return _buildClarificationRoundCapReached(draft);
    }

    final activeIndex = queue.indexWhere(
      (entry) => !_isAnswered(entry.line.lineRef, entry.prompt.id),
    );
    final answeredAll = activeIndex < 0;

    return Column(
      key: const ValueKey('material-clarification'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Antes de comparar hace falta una precisión',
          style: PurchaseType.sectionTitle,
        ),
        const SizedBox(height: 6),
        _buildOriginalRequestLine(),
        // Progreso textual, nunca una fila de cápsulas. Con todo respondido no
        // hay pregunta en curso que numerar: el resumen ya lo dice todo.
        if (queue.length > 1 && !answeredAll)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Pregunta ${activeIndex + 1} de ${queue.length}',
              key: const ValueKey('clarification-progress'),
              style: PurchaseType.label.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        _buildAnsweredClarificationSummary(queue),
        // Con todas respondidas no se vuelve a dibujar el último control: sería
        // repetir lo que el resumen ya muestra y ofrecer dos sitios para lo
        // mismo. Queda el resumen corregible y la única salida.
        if (answeredAll)
          _buildClarificationSubmit(draft)
        else
          _buildClarificationPrompt(
            draft,
            queue[activeIndex].line,
            queue[activeIndex].prompt,
            remaining: queue
                .where(
                  (entry) => !_isAnswered(entry.line.lineRef, entry.prompt.id),
                )
                .length,
          ),
        if (legacy.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildLegacyClarification(legacy),
        ],
      ],
    );
  }

  Widget _buildOriginalRequestLine() {
    final original = _lastUserMessage?.trim();
    if (original == null || original.isEmpty) return const SizedBox.shrink();
    // La petición ya está transcrita literal en su burbuja, justo encima y en
    // la misma columna. Repetirla aquí era el bloque más largo de la tarjeta y
    // empujaba la pregunta hacia abajo. Queda la acción, que es lo que faltaba:
    // la petición no sólo visible, también editable desde donde se pregunta.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('clarification-edit-original-request'),
          onPressed: _askingAssistant
              ? null
              : () {
                  _composerController.text = original;
                  setState(() {
                    _composerExpanded = true;
                    _showExamples = false;
                  });
                },
          child: const Text('Editar la petición original'),
        ),
      ),
    );
  }

  /// Lo ya respondido en esta ronda, en una línea por pregunta.
  ///
  /// Sin esto, marcar «No lo sé» y avanzar dejaba al operador sin rastro de lo
  /// que acababa de contestar, y sin forma de corregirlo antes de enviar.
  Widget _buildAnsweredClarificationSummary(
    List<
            ({
              AIAssistantSupplyNeedDraftLine line,
              AIAssistantSupplyNeedClarificationPrompt prompt
            })>
        queue,
  ) {
    final theme = Theme.of(context);
    final answered = queue
        .where((entry) => _isAnswered(entry.line.lineRef, entry.prompt.id))
        .toList(growable: false);
    if (answered.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        key: const ValueKey('clarification-answered-summary'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in answered)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      _clarificationUnknown.contains(
                        _clarificationKeyOf(
                            entry.line.lineRef, entry.prompt.id),
                      )
                          // «No lo sé» se dice tal cual: no se asume un valor.
                          ? '${entry.prompt.question} — No lo sé'
                          : '${entry.prompt.question} — ${_clarificationAnswerLabel(entry.prompt, _clarificationAnswers[_clarificationKeyOf(entry.line.lineRef, entry.prompt.id)]!)}',
                      key: ValueKey<String>(
                        'clarification-answered-${entry.prompt.id}',
                      ),
                      style: PurchaseType.meta
                          .copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    key: ValueKey<String>(
                      'clarification-change-${entry.prompt.id}',
                    ),
                    onPressed: _askingAssistant
                        ? null
                        : () => setState(() {
                              final key = _clarificationKeyOf(
                                entry.line.lineRef,
                                entry.prompt.id,
                              );
                              _clarificationAnswers.remove(key);
                              _clarificationUnknown.remove(key);
                              _clarificationInputErrors.remove(key);
                              // Sólo se borra el borrador de ESTE prompt.
                              _clarificationInputs[key]?.clear();
                            }),
                    child: const Text('Cambiar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// La etiqueta de la opción, no su valor de máquina.
  String _clarificationAnswerLabel(
    AIAssistantSupplyNeedClarificationPrompt prompt,
    String value,
  ) {
    for (final option in prompt.options) {
      if (option.value == value) return option.label;
    }
    return prompt.unit == null ? value : '$value ${prompt.unit}';
  }

  /// Reintento del envío de respuestas.
  ///
  /// Cuando el borrador sobrevive al fallo —que es lo correcto— la banda de
  /// error del asistente no se dibuja, así que el reintento idempotente no
  /// tenía dónde vivir. Reusa `_replayMessage`/`_replayRequestId`: el mismo
  /// `clientRequestId`, no una petición nueva.
  Widget _buildClarificationRetry(ThemeData theme) {
    final canRetry = !_askingAssistant && _replayMessage != null;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'No se pudo enviar la respuesta. Reintenta: lo que marcaste sigue aquí.',
            key: const ValueKey('clarification-send-error'),
            style: PurchaseType.meta.copyWith(color: theme.colorScheme.error),
          ),
        ),
        TextButton(
          key: const ValueKey('clarification-retry'),
          onPressed: canRetry
              ? () => unawaited(
                    _askAssistant(
                      message: _replayMessage,
                      isClarificationAnswer: true,
                    ),
                  )
              : null,
          child: const Text('Reintentar'),
        ),
      ],
    );
  }

  /// Estado «todo respondido»: sólo la salida, sin repetir la última pregunta.
  Widget _buildClarificationSubmit(AIAssistantSupplyNeedDraft draft) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width <
        ResponsiveBreakpoints.phoneMaxExclusive;
    final busy = _askingAssistant;
    return Container(
      key: const ValueKey('clarification-submit'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Listo para enviar tus respuestas. Puedes cambiar cualquiera antes '
            'de continuar.',
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: compact ? PurchaseSurfaceGeometry.phoneStepControl : 36,
            width: compact ? double.infinity : null,
            child: FilledButton(
              key: const ValueKey('clarification-continue'),
              onPressed: busy
                  ? null
                  : () => unawaited(_submitClarificationAnswers(draft)),
              child: Text(busy ? 'Enviando…' : 'Continuar'),
            ),
          ),
          if (_assistantError != null) ...[
            const SizedBox(height: 8),
            _buildClarificationRetry(theme),
          ],
        ],
      ),
    );
  }

  /// El control que pide el contrato, y sólo ese.
  ///
  /// `single_choice` son filas de radio —opciones, no filtros—; `number` es un
  /// campo con su unidad como sufijo; `text` es un campo breve y sólo aparece
  /// cuando el modelo lo pidió. Ninguno inventa un valor por omisión.
  Widget _buildClarificationPrompt(
    AIAssistantSupplyNeedDraft draft,
    AIAssistantSupplyNeedDraftLine line,
    AIAssistantSupplyNeedClarificationPrompt prompt, {
    required int remaining,
  }) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width <
        ResponsiveBreakpoints.phoneMaxExclusive;
    final key = _clarificationKeyOf(line.lineRef, prompt.id);
    final answer = _clarificationAnswers[key];
    final unknown = _clarificationUnknown.contains(key);
    final busy = _askingAssistant;
    TextEditingController? inputController;

    final Widget control;
    switch (prompt.inputKind) {
      case AIAssistantSupplyNeedClarificationInputKind.singleChoice:
        control = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final option in prompt.options)
              RadioListTile<String>(
                key: ValueKey<String>(
                  'clarification-option-${prompt.id}-${option.value}',
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: option.value,
                // ignore: deprecated_member_use
                groupValue: unknown ? null : answer,
                title: Text(option.label),
                // ignore: deprecated_member_use
                onChanged: busy
                    ? null
                    : (value) => _setClarificationAnswer(
                          line.lineRef,
                          prompt.id,
                          value ?? option.value,
                        ),
              ),
          ],
        );
      case AIAssistantSupplyNeedClarificationInputKind.number:
      case AIAssistantSupplyNeedClarificationInputKind.text:
        final isNumber = prompt.inputKind ==
            AIAssistantSupplyNeedClarificationInputKind.number;
        inputController = _clarificationControllerFor(key);
        control = SizedBox(
          width: compact ? double.infinity : 240,
          child: TextField(
            key: ValueKey<String>('clarification-input-${prompt.id}'),
            controller: inputController,
            enabled: !busy,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            // Se acota la entrada sin contador visible: es un dato, no una
            // redacción.
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                isNumber
                    ? _clarificationNumberMaxLength
                    : _clarificationTextMaxLength,
              ),
            ],
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              // La unidad es sufijo del campo, no una cápsula al lado.
              suffixText: isNumber ? prompt.unit : null,
              hintText: isNumber ? 'Sólo el número' : null,
              errorText: _clarificationInputErrors[key],
            ),
            onChanged: (value) {
              final trimmed = value.trim();
              if (trimmed.isEmpty) {
                setState(() {
                  _clarificationInputErrors.remove(key);
                });
                return;
              }
              if (!isNumber) {
                setState(() => _clarificationInputErrors.remove(key));
                return;
              }
              final normalized = _normalizeClarificationNumber(trimmed);
              if (normalized == null) {
                // Nunca se envía texto arbitrario donde el contrato pide número.
                setState(() {
                  _clarificationInputErrors[key] =
                      'Escribe sólo un número (por ejemplo 584 o 584,5).';
                });
                return;
              }
              setState(() => _clarificationInputErrors.remove(key));
            },
          ),
        );
    }

    final hasInput = inputController != null;
    final inputDraft = inputController?.text.trim() ?? '';
    final validInputDraft =
        inputDraft.isNotEmpty && _clarificationInputErrors[key] == null;
    // Un radio confirma con el gesto de selección. Texto y número requieren
    // un gesto explícito para no avanzar después del primer carácter.
    final canContinue = !busy && (hasInput ? validInputDraft : remaining == 0);
    final actions = <Widget>[
      SizedBox(
        height: compact ? PurchaseSurfaceGeometry.phoneStepControl : 36,
        width: compact ? double.infinity : null,
        child: FilledButton(
          key: const ValueKey('clarification-continue'),
          onPressed: !canContinue
              ? null
              : hasInput
                  ? () => _commitClarificationInput(line, prompt)
                  : () => unawaited(_submitClarificationAnswers(draft)),
          child: Text(
            busy
                ? 'Enviando…'
                : hasInput && remaining > 1
                    ? 'Siguiente'
                    : hasInput
                        ? 'Confirmar'
                        : 'Continuar',
          ),
        ),
      ),
      if (!busy && remaining > 0)
        Text(
          hasInput
              ? 'Confirma la respuesta para continuar'
              : remaining == 1
                  ? 'Responde la pregunta para continuar'
                  : 'Faltan $remaining respuestas para continuar',
          key: const ValueKey('clarification-continue-hint'),
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      if (prompt.allowUnknown)
        SizedBox(
          height: compact ? PurchaseSurfaceGeometry.phoneStepControl : 36,
          width: compact ? double.infinity : null,
          child: TextButton(
            key: const ValueKey('clarification-unknown'),
            onPressed: busy
                ? null
                : () {
                    _clarificationInputs[key]?.clear();
                    setState(() => _clarificationInputErrors.remove(key));
                    _setClarificationUnknown(line.lineRef, prompt.id);
                  },
            child: const Text('No lo sé'),
          ),
        ),
      // **La segunda vía, en el punto de la decisión.**
      //
      // El contrato del frame 08 la declara desde el principio —«secundaria:
      // Responder después»— y no estaba: al pie de la pregunta sólo había un
      // «Continuar» apagado y un texto diciendo por qué. La salida existía,
      // pero vivía al final de todo el borrador, pasada la evidencia
      // consultada y fuera de pantalla en teléfono. Desde la pregunta, la
      // única lectura posible era «no puedo seguir hasta contestar esto».
      //
      // Sigue con lo que el asistente entendió: la precisión queda pendiente
      // en la línea y se resuelve en el paso siguiente, que es exactamente lo
      // que la CTA del borrador ya hacía.
      if (!busy) ...[
        PurchaseInlineAction(
          key: const ValueKey('clarification-answer-later'),
          label: 'Responder después',
          onPressed:
              _runningCommand ? null : () => unawaited(_saveSupplyNeedDraft()),
        ),
        Text(
          'Sigue con lo que el asistente entendió; la línea queda con su '
          'precisión pendiente.',
          key: const ValueKey('clarification-answer-later-hint'),
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    ];

    return Container(
      key: ValueKey<String>('clarification-prompt-${prompt.id}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prompt.question, style: PurchaseType.rowTitle),
          if (draft.lines.length > 1) ...[
            const SizedBox(height: 2),
            Text(
              'Para «${line.description}»',
              style: PurchaseType.meta
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          control,
          const SizedBox(height: 12),
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  actions[i],
                ],
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          if (_assistantError != null) ...[
            const SizedBox(height: 8),
            _buildClarificationRetry(theme),
          ],
        ],
      ),
    );
  }

  /// Tope de rondas alcanzado: dos salidas reales, ninguna pregunta más.
  Widget _buildClarificationRoundCapReached(
    AIAssistantSupplyNeedDraft draft,
  ) {
    final theme = Theme.of(context);
    final first = draft.lines
        .where((line) => line.clarificationRequired)
        .toList(growable: false);
    return Column(
      key: const ValueKey('clarification-round-cap'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Seguimos sin la precisión necesaria',
          style: PurchaseType.sectionTitle,
        ),
        const SizedBox(height: 6),
        _buildOriginalRequestLine(),
        Text(
          'Ya respondiste $_clarificationRoundCap veces y el dato sigue sin '
          'cerrarse. Puedes corregir la petición o guardarla pendiente y '
          'confirmar el producto en el paso siguiente.',
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (first.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('clarification-edit-request'),
              onPressed: _askingAssistant
                  ? null
                  : () => _openDraftLineEditor(first.first),
              child: const Text('Corregir la petición'),
            ),
          ),
      ],
    );
  }

  /// Salida anterior, intacta, para `clarificationRequired == true` sin
  /// prompts: card v1 o modelo que todavía no emite preguntas tipadas.
  Widget _buildLegacyClarification(
    List<AIAssistantSupplyNeedDraftLine> pending,
  ) {
    final theme = Theme.of(context);
    if (pending.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('material-clarification-legacy'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Antes de comparar hace falta una precisión',
          style: PurchaseType.sectionTitle,
        ),
        const SizedBox(height: 6),
        _buildOriginalRequestLine(),
        for (final line in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line.clarification ??
                  'Falta confirmar el producto exacto de «${line.description}».',
              style: PurchaseType.body,
            ),
          ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('clarification-edit-request'),
              onPressed: _askingAssistant
                  ? null
                  : () => _openDraftLineEditor(pending.first),
              child: const Text('Corregir la petición'),
            ),
            // No es un botón disfrazado: nombra la acción que sí existe abajo.
            Text(
              'o guárdala como pendiente con la acción de abajo y confirma el '
              'producto en el paso siguiente',
              style: PurchaseType.meta
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  /// Evidencia consultada.
  ///
  /// El backend todavía no publica el recuento por fuente de este turno, así
  /// que la etiqueta dice qué se consultó y no inventa números.
  Widget _buildConsultedEvidenceDisclosure() {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('consulted-evidence'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          'Evidencia consultada',
          style: PurchaseType.rowTitle
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        children: [
          Text(
            'Catálogo y fichas técnicas del tenant, e historial de compras para '
            'costo y proveedor. El detalle por fuente de este análisis todavía '
            'no se publica; no se muestran recuentos estimados.',
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// Única CTA del paso: persiste la necesidad y avanza a donde corresponde.
  Widget _buildDraftCommitCta(
    AIAssistantSupplyNeedDraft draft, {
    required bool blocked,
  }) {
    final theme = Theme.of(context);
    // La CTA sólo promete lo que el paso siguiente puede ejecutar. Sin
    // producto confirmado no hay bodega que consultar **ni** comparación que
    // correr: la salida honesta es guardar pendiente. `blocked` no basta como
    // criterio —una línea puede no bloquear y aun así no tener producto—.
    final allConfirmed = draft.lines.every((line) => line.hasConfirmedProduct);
    final label = allConfirmed
        ? 'Guardar y revisar stock'
        : 'Guardar pendiente y continuar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: FilledButton.icon(
            key: const ValueKey('save-supply-need-draft'),
            onPressed: _runningCommand
                ? null
                : () => unawaited(_saveSupplyNeedDraft()),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(label),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          // La garantía va literal en las dos ramas: cambia el encabezado,
          // nunca la promesa de que no se compra nada.
          '${allConfirmed ? 'Guardar crea la necesidad para trabajarla' : 'Se guarda con la identidad pendiente y podrás confirmar el producto en el paso siguiente'}; '
          'no compra, no reserva stock y no emite ningún documento.',
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildDraftLineInlineEditor(
    AIAssistantSupplyNeedDraftLine line, {
    required int index,
  }) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width <
        ResponsiveBreakpoints.phoneMaxExclusive;
    return Container(
      key: ValueKey('supply-draft-inline-editor-${line.lineRef}'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Editar necesidad ${index + 1}',
            style: PurchaseType.sectionTitle,
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey('supply-draft-description-field-${line.lineRef}'),
            controller: _draftDescriptionController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: compact ? double.infinity : 140,
                child: TextField(
                  key: ValueKey('supply-draft-quantity-field-${line.lineRef}'),
                  controller: _draftQuantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(width: compact ? 0 : 12, height: compact ? 10 : 0),
              SizedBox(
                width: compact ? double.infinity : 180,
                child: TextField(
                  key: ValueKey('supply-draft-unit-field-${line.lineRef}'),
                  controller: _draftUnitController,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          if (_draftEditError != null) ...[
            const SizedBox(height: 8),
            Text(
              _draftEditError!,
              style: PurchaseType.meta.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                height: 40,
                width: compact ? double.infinity : null,
                child: FilledButton(
                  key: ValueKey('supply-draft-save-${line.lineRef}'),
                  onPressed:
                      _runningCommand ? null : () => _saveDraftLineEditor(line),
                  child: const Text('Guardar cambios'),
                ),
              ),
              SizedBox(
                height: 40,
                width: compact ? double.infinity : null,
                child: TextButton(
                  key: ValueKey('supply-draft-cancel-${line.lineRef}'),
                  onPressed: _cancelDraftLineEditor,
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupplyNeedDraftLine(
    AIAssistantSupplyNeedDraftLine line, {
    required int index,
    required int count,
  }) {
    if (_editingDraftLineRef == line.lineRef) {
      return _buildDraftLineInlineEditor(line, index: index);
    }
    if (_criteriaLineRef == line.lineRef) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSupplyNeedDraftRowBody(line, index: index, count: count),
          _buildDraftLineCriteriaDisclosure(line),
        ],
      );
    }
    return _buildSupplyNeedDraftRowBody(line, index: index, count: count);
  }

  /// Criterios interpretados, revelados bajo su propia línea.
  ///
  /// Es una disclosure nombrada en el flujo, no una superficie aparte: leerlos
  /// no puede sacar al operador de la revisión ni tapar la página.
  Widget _buildDraftLineCriteriaDisclosure(
    AIAssistantSupplyNeedDraftLine line,
  ) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('supply-draft-criteria-${line.lineRef}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Criterios interpretados',
                  // `panel_title` en el spec: «inspector, criterios, compra
                  // local». Es un panel, no un encabezado de bloque.
                  style: PurchaseType.panelTitle,
                ),
              ),
              TextButton(
                key: ValueKey('supply-draft-criteria-close-${line.lineRef}'),
                onPressed: () => _toggleDraftLineCriteria(line.lineRef),
                child: const Text('Ocultar'),
              ),
            ],
          ),
          if (line.preference != null) ...[
            const SizedBox(height: 6),
            Text(
              'Preferencia: ${line.preference}',
              style: PurchaseType.meta
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          for (final predicate in line.technicalPredicates) ...[
            const SizedBox(height: 4),
            Text(
              _predicateLabel(predicate),
              style: PurchaseType.meta
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (line.preference == null && line.technicalPredicates.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'La IA no dedujo criterios adicionales para esta línea.',
              style: PurchaseType.meta
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  /// Criterio técnico en palabras del operador, no en jerga del motor.
  String _predicateLabel(AIAssistantSupplyNeedTechnicalPredicate predicate) {
    final values = predicate.values.map((value) => '$value').join(' y ');
    final comparison = switch (predicate.operator) {
      'gt' => 'mayor a',
      'gte' => 'mayor o igual a',
      'lt' => 'menor a',
      'lte' => 'menor o igual a',
      'between' => 'entre',
      'in' => 'entre las opciones',
      'neq' => 'distinto de',
      _ => 'igual a',
    };
    return '${predicate.field}: $comparison $values';
  }

  /// Resumen compacto de una necesidad interpretada.
  ///
  /// Superficie abierta: sin número de fila, sin cabecera de tabla, sin
  /// contenedor con footer. Sólo un hairline la separa de la siguiente.
  Widget _buildSupplyNeedDraftRowBody(
    AIAssistantSupplyNeedDraftLine line, {
    required int index,
    required int count,
  }) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final identityTone = line.hasConfirmedProduct
        ? roles.success
        : line.clarificationRequired
            ? roles.warning
            : roles.neutral;
    final identity = line.hasConfirmedProduct
        ? 'Producto confirmado · ${line.productName}'
        : line.clarificationRequired
            ? 'Producto por precisar'
            : 'Sin producto asignado';
    final criteria = <String>[
      if (line.preference != null) line.preference!,
      for (final predicate in line.technicalPredicates)
        _predicateLabel(predicate),
    ];

    return Container(
      key: ValueKey('supply-draft-line-${line.lineRef}'),
      padding: EdgeInsets.only(top: index == 0 ? 0 : 12, bottom: 12),
      decoration: index == 0
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  line.description,
                  style: PurchaseType.rowTitle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_formatSupplyQuantity(line.quantity)} '
                '${purchaseUnitLabel(line.unit, line.quantity)}',
                style: PurchaseType.metaNumeric.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Punto semántico, no cápsula: un estado por línea.
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 6, right: 8),
                decoration: BoxDecoration(
                  color: identityTone.accent,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  identity,
                  style: PurchaseType.meta
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          if (criteria.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Text(
                criteria.join(' · '),
                style: PurchaseType.meta
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
          // `clarificationRequired == false` con texto es un límite del ERP,
          // no una pregunta: vive junto a su línea, en secundario, no bloquea
          // y no abre ningún control.
          if (!line.clarificationRequired && line.clarification != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Text(
                line.clarification!,
                key: ValueKey('supply-draft-coverage-note-${line.lineRef}'),
                style: PurchaseType.meta
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(height: 6),
          // Acciones textuales azules, junto a lo que modifican.
          Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  key: ValueKey('supply-draft-edit-${line.lineRef}'),
                  onPressed:
                      _runningCommand ? null : () => _openDraftLineEditor(line),
                  child: const Text('Editar'),
                ),
                if (criteria.isNotEmpty)
                  TextButton(
                    key: ValueKey('supply-draft-criteria-open-${line.lineRef}'),
                    onPressed: () => _toggleDraftLineCriteria(line.lineRef),
                    child: const Text('Revisar criterios'),
                  ),
                if (count > 1)
                  TextButton(
                    key: ValueKey('supply-draft-remove-${line.lineRef}'),
                    onPressed: _runningCommand
                        ? null
                        : () => _removeSupplyNeedDraftLine(line.lineRef),
                    child: const Text('Quitar'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Líneas reales de la canasta: son las necesidades seleccionadas, no una
  /// copia. La precisión pendiente sale del estado de identidad que publica el
  /// propio backend, no de una heurística de texto.
  List<BasketRequestLine> get _basketRequestLines => _selectedBasketNeeds
      .map(
        (need) => BasketRequestLine(
          id: need.id,
          name: need.productName ?? need.description,
          description: need.productName == null
              ? 'sin SKU exacto: se comparará por descripción'
              : need.description,
          quantity: need.quantity.round(),
          unitLabel: purchaseUnitLabel(need.unit, need.quantity),
          precisionBlocker: need.hasConfirmedProduct
              ? null
              : 'falta confirmar el producto exacto',
        ),
      )
      .toList(growable: false);

  SupplyNeed? _needById(String id) =>
      _firstWhereOrNull(_needs, (need) => need.id == id);

  /// Cambia la cantidad de una línea de la canasta en la necesidad real.
  Future<void> _changeBasketQuantity(
    BasketRequestLine line,
    int quantity,
  ) async {
    final need = _needById(line.id);
    if (need == null || quantity <= 0 || _basketBusyNeedId != null) return;
    if (quantity == need.quantity.round()) return;
    setState(() {
      _basketBusyNeedId = need.id;
      _scenarioError = null;
    });
    try {
      final updated = await _service.updateNeed(
        need,
        description: need.description,
        productId: need.productId,
        quantity: quantity.toDouble(),
      );
      if (!mounted) return;
      setState(() {
        _needs = _needs
            .map((item) => item.id == updated.id ? updated : item)
            .toList(growable: false);
        if (_selectedNeed?.id == updated.id) _selectedNeed = updated;
        // Los escenarios se calcularon con la cantidad anterior: dejan de ser
        // verdad y se piden de nuevo en vez de mostrarse desactualizados.
        _scenarioResult = null;
      });
      await _loadScenarios();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scenarioError =
            'La cantidad no se pudo guardar. Reintenta sin perder la canasta.';
      });
    } finally {
      if (mounted) setState(() => _basketBusyNeedId = null);
    }
  }

  /// Quitar una línea saca la necesidad de la canasta; nunca borra la
  /// necesidad, que sigue viva en su propio paso.
  Future<void> _removeBasketLine(BasketRequestLine line) async {
    if (!_basketNeedIds.contains(line.id)) return;
    setState(() {
      _basketNeedIds.remove(line.id);
      _scenarioResult = null;
      _selectedScenarioKey = null;
    });
    if (_basketNeedIds.length < 2) {
      // Con menos de dos líneas no hay canasta que comparar: la salida honesta
      // es volver a la selección, no dejar una comparación imposible.
      setState(() {
        _showScenarios = false;
        _selectingBasket = true;
        _step = PurchaseStep.need;
      });
      return;
    }
    await _loadScenarios();
  }

  /// Agregar línea vuelve al paso donde se eligen necesidades, con el modo de
  /// selección ya activo.
  void _addBasketLine() {
    setState(() {
      _showScenarios = false;
      _selectingBasket = true;
      _returnToScenarios = true;
      _step = PurchaseStep.need;
    });
  }

  /// Resolver la precisión lleva a la necesidad concreta para confirmar su
  /// identidad, y deja marcado el retorno a la canasta.
  void _resolveBasketLine(BasketRequestLine line) {
    final need = _needById(line.id);
    if (need == null) return;
    setState(() {
      _selectedNeed = need;
      _showScenarios = false;
      _selectingBasket = false;
      _returnToScenarios = true;
      _step = PurchaseStep.need;
    });
  }

  Widget _buildScenarioSurface() {
    // El mismo umbral que el resto del módulo: bajo `phoneMaxExclusive` la
    // composición es la del teléfono.
    final compact = MediaQuery.sizeOf(context).width <
        ResponsiveBreakpoints.phoneMaxExclusive;
    final result = _scenarioResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showScenarios = false),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Volver a la selección'),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comparación de la canasta',
                    style: PurchaseType.surfaceTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_basketNeedIds.length} necesidades · hasta $_maxSuppliers ${_maxSuppliers == 1 ? 'proveedor' : 'proveedores'}',
                    style: PurchaseType.meta.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Frame 20: bajo el encabezado van las tabs. Acá se apilaban dos
        // desplegables de formulario a ancho completo más una losa tonal, y
        // eso empujaba la comparación **bajo el pliegue** en teléfono (y≈590
        // de 788 medidos). En escritorio los dos controles se quedan, que es
        // lo que el frame 11 pide en su encabezado; en teléfono se reúnen en
        // un solo botón anclado, el mismo tratamiento que el paso de una sola
        // necesidad ya usa a un paso de distancia.
        BasketResultControls(
          compact: compact,
          profileValue: _rankingProfile,
          profileOptions: const {
            'balanced': 'Equilibrio',
            'profitability': 'Mayor rentabilidad',
            'urgent_local': 'Urgencia local',
          },
          onProfileChanged: _changeRankingProfile,
          maxSuppliersValue: '$_maxSuppliers',
          maxSuppliersOptions: const {
            '1': '1 proveedor',
            '2': 'Hasta 2',
            '3': 'Hasta 3',
          },
          onMaxSuppliersChanged: (value) =>
              _changeMaxSuppliers(int.parse(value)),
          enabled: !_loadingScenarios,
        ),
        const SizedBox(height: 10),
        // La misma salvedad, dicha como texto. El dueño ya rechazó una losa
        // `VbNotice` en este módulo por repetir en un bloque tonal lo que la
        // frase dice sola; en teléfono además costaba el pliegue.
        Text(
          'Stock interno primero; proveedores después. Los costos y fletes son '
          'históricos y la disponibilidad externa se confirma con cada '
          'proveedor.',
          style: PurchaseType.meta
              .copyWith(color: PurchaseTokens.of(context).inkMuted),
        ),
        if (_scenarioError != null) ...[
          const SizedBox(height: 12),
          VbNotice(
            title: _scenarioError!,
            tone: VbNoticeTone.warning,
            action: TextButton(
              onPressed: _loadingScenarios ? null : _loadScenarios,
              child: const Text('Recalcular'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Frame 20 — dos subestados del mismo borrador.
        BasketSectionTabs(
          active: _basketSection,
          onChanged: (section) => setState(() => _basketSection = section),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _basketSection == BasketSection.lines
              ? SingleChildScrollView(
                  // Frame 28 — las líneas de la petición, editables aquí mismo.
                  child: BasketRequestLinesCard(
                    lines: _basketRequestLines,
                    compact: MediaQuery.sizeOf(context).width <
                        ResponsiveBreakpoints.phoneMaxExclusive,
                    busy: _basketBusyNeedId != null || _loadingScenarios,
                    onChangeQuantity: (line, quantity) =>
                        unawaited(_changeBasketQuantity(line, quantity)),
                    onRemoveLine: (line) => unawaited(_removeBasketLine(line)),
                    onAddLine: _addBasketLine,
                    onResolvePrecision: _resolveBasketLine,
                  ),
                )
              : _loadingScenarios && result == null
                  ? const Center(child: CircularProgressIndicator())
                  : result == null || result.scenarios.isEmpty
                      // Sin isla centrada: la causa se dice a la izquierda,
                      // dentro del flujo, con su salida real.
                      ? SingleChildScrollView(
                          child: NoMatchSurface(
                            causeSentence:
                                'Las necesidades de la canasta no tienen una '
                                'combinación histórica suficiente para armar un '
                                'escenario. Ninguna quedó descartada por '
                                'incompatibilidad técnica.',
                            onClearFilters: _addBasketLine,
                            onIncludeUnconfirmed: () => setState(
                              () => _basketSection = BasketSection.lines,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: result.scenarios.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 24),
                          itemBuilder: (context, index) {
                            final scenario = result.scenarios[index];
                            return _PurchaseScenarioPanel(
                              scenario: scenario,
                              selected: _selectedScenarioKey == scenario.key ||
                                  (_selectedScenarioKey == null && index == 0),
                              onSelect: () => setState(
                                () => _selectedScenarioKey = scenario.key,
                              ),
                              initiallyExpanded: _selectedScenarioKey ==
                                      scenario.key ||
                                  (_selectedScenarioKey == null && index == 0),
                              preparing: _preparingScenarioKey == scenario.key,
                              commandsEnabled: _preparingScenarioKey == null,
                              onPrepare: () => _prepareScenario(scenario),
                              onReviewLine: _reviewScenarioLine,
                            );
                          },
                        ),
        ),
      ],
    );
  }

  /// Resultados del paso Proveedores: identidad pendiente, o comparación.
  Widget _buildProviderResults({required bool phone}) {
    final need = _selectedNeed;
    if (need == null) {
      // Era una isla centrada y, peor, un estado sin salida: pedía elegir una
      // necesidad sin ofrecer dónde. Ahora es inline a la izquierda, con la
      // acción que resuelve el propio mensaje.
      final theme = Theme.of(context);
      return ListView(
        key: const ValueKey('provider-results-needs-empty'),
        padding: const EdgeInsets.only(top: 14),
        children: [
          Text('Selecciona una necesidad', style: PurchaseType.sectionTitle),
          const SizedBox(height: 4),
          Text(
            'Verás primero el stock interno y luego las opciones de compra.',
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const ValueKey('provider-results-choose-need'),
              onPressed: () => _openWorkspaceSection(PurchaseStep.need),
              child: const Text('Elegir necesidad'),
            ),
          ),
        ],
      );
    }
    if (_loadingDecision) {
      return const Center(child: CircularProgressIndicator());
    }
    // **El carril familia resuelve la identidad eligiendo un candidato.**
    // Este paso solía cortar en seco ante cualquier necesidad sin producto
    // confirmado, y ése era el gate que dejaba a la familia sin ninguna
    // superficie externa. Cuando hay candidatos que comparar, se comparan: el
    // pie de cada uno ofrece «Elegir producto», que es la misma decisión de
    // identidad, tomada con la evidencia a la vista.
    final external = _externalCandidates;
    final hasChoosableCandidates =
        external != null && external.isSuccess && external.hasAnyCandidate;
    //
    // La vía manual no se pierde: cuando no hay ningún candidato que elegir,
    // el panel de identidad viaja al final de la misma columna, debajo del
    // estado que el servidor devolvió.
    return _buildCandidateSection(
      phone: phone,
      identityFallback:
          _identityFallbackApplies(need, external) && !hasChoosableCandidates
              ? _buildIdentityResolution(need)
              : null,
    );
  }

  /// Fijar el producto exacto sólo es una salida donde de verdad lo es.
  ///
  /// Una necesidad **cerrada** no se resuelve eligiendo producto: ya está
  /// cubierta o cancelada, y ofrecer «Falta confirmar qué producto es» debajo
  /// de «Esta necesidad ya está resuelta» son dos afirmaciones que se
  /// contradicen en la misma pantalla. Y con `no_eligible_products` el
  /// catálogo entero quedó fuera por contradecir la ficha: lo que falla son
  /// los criterios, no la identidad.
  ///
  /// En los demás estados abiertos sí se conserva, porque mientras no exista
  /// el refinador técnico es la única salida que le queda al operador.
  bool _identityFallbackApplies(
    SupplyNeed need,
    SupplyExternalCandidates? external,
  ) {
    if (need.hasConfirmedProduct) return false;
    if (need.supplyState != 'open') return false;
    // Una decisión que no se cargó no autoriza a proponer resolver la
    // identidad: da igual si faltó por fallo o por conflicto.
    if (_decisionUnavailable) return false;
    const closedToIdentity = {'supply_closed', 'no_eligible_products'};
    if (external != null && closedToIdentity.contains(external.status)) {
      return false;
    }
    return true;
  }

  /// Confirmar qué producto es: **un** panel con la explicación, las dos vías
  /// para resolverlo y su acción, en vez de cuatro controles a sangre completa
  /// apoyados sobre el fondo.
  Widget _buildIdentityResolution(SupplyNeed need) {
    final tokens = PurchaseTokens.of(context);
    return PurchasePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Falta confirmar qué producto es',
            style: PurchaseType.panelTitle.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 3),
          Text(
            'La descripción se conserva. La IA puede interpretarla y tú confirmas antes de reservar stock.',
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          ),
          const SizedBox(height: 11),
          ProductAutocompleteField(
            key: ValueKey('confirm-supply-product-${need.id}'),
            controller: _identityController,
            allowCustomItems: false,
            labelText: 'Confirmar producto del catálogo',
            hintText: 'Busca por nombre, SKU o características',
            onProductSelected: (selection) =>
                setState(() => _identitySelection = selection),
          ),
          const SizedBox(height: PurchaseMetrics.actionsTopGap),
          Row(
            children: [
              PurchasePrimaryButton(
                label: 'Confirmar y revisar stock',
                onPressed: _identitySelection?.isCatalogProduct == true &&
                        !_runningCommand
                    ? _confirmIdentity
                    : null,
              ),
              const SizedBox(width: PurchaseMetrics.actionsGap),
              // La otra vía, como acción textual: es una alternativa, no una
              // acción de igual peso que confirmar.
              PurchaseInlineAction(
                label:
                    _askingAssistant ? 'Interpretando…' : 'Interpretar con IA',
                onPressed: _askingAssistant
                    ? null
                    : () => _askAssistant(message: need.description),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Motivo tipado para rechazar stock realmente asignable. Sólo se pide
  /// cuando el stock existía: si nunca hubo, no se exige justificar su ausencia.
  Widget _buildStockRejectionInline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _stockReasonController,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '¿Por qué no sirve el stock disponible?',
            hintText: 'Ej.: necesito una gama superior para este trabajo',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: _runningCommand
                  ? null
                  : () => setState(() => _showStockRejection = false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: _runningCommand ? null : _rejectInternalStock,
              child: const Text('Guardar motivo y comparar'),
            ),
          ],
        ),
      ],
    );
  }

  /// Un choque de concurrencia se recupera releyendo, nunca reintentando con
  /// la versión vieja: esa versión ya describe otra cosa.
  static const String _concurrencyMessage =
      'La necesidad cambió mientras la revisabas. Recárgala para trabajar '
      'sobre la versión vigente.';

  Widget _buildCandidateSection({
    required bool phone,
    Widget? identityFallback,
  }) {
    final ranking = _ranking;
    final need = _selectedNeed;
    final external = _externalCandidates;
    final resolution = _stockResolution;
    // **Bloqueo de stock significa stock, y nada más.** Antes esto era «no se
    // muestran candidatos», así que `needs_refinement`, `identity_unresolved`
    // y `supply_closed` se rotulaban como «el stock interno todavía puede
    // cubrir esta necesidad» —una afirmación falsa sobre la bodega y, peor,
    // la acción equivocada—. Ahora cada estado llega a su propia superficie.
    final blockedByStock = need != null &&
        resolution != null &&
        resolution.isOk &&
        resolution.blocksExternal &&
        !resolution.externalAllowed;
    final width = MediaQuery.sizeOf(context).width;
    final usableWidth =
        width - (_inspectedCandidate != null ? _inspectorWidth : 0);
    // La tabla conserva sus columnas opcionales sólo con ancho útil suficiente;
    // «Vista» puede pedir menos, nunca más de lo que cabe (frame 26).
    final showOptionalColumns = _tableView != 'compact' && usableWidth >= 900;
    // Umbral del spec: por debajo, la tabla dejaría de ser legible y la
    // composición correcta son las cards, no una tabla comprimida.
    final useCards = phone || usableWidth < 470;

    return ListView(
      key: const ValueKey('provider-results'),
      padding: const EdgeInsets.only(top: 14),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            // Frame 03/04/16/26: recuento de candidatos y de proveedores en una
            // sola línea, con la salvedad de disponibilidad como texto
            // secundario contiguo. Nunca una cápsula: no es una excepción.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              children: [
                Text(
                  _candidateCountLabel(
                    ranking,
                    unverified: external?.unverifiedItems.length ?? 0,
                  ),
                  style: PurchaseType.sectionTitle,
                ),
                if (_allCandidatesHiddenByFilters)
                  Text(
                    '0 visibles con el filtro activo',
                    style: PurchaseType.meta.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (ranking != null && ranking.items.isNotEmpty)
                  Text(
                    'Stock no verificado',
                    style: PurchaseType.meta.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            // Frames 03/26 en ancho, 16/20 en teléfono.
            ProviderResultControls(
              compact: phone,
              enabled: !_loadingDecision && !_refreshingResults,
              profileLabel: _serverProfileLabel,
              viewValue: _tableView,
              viewOptions: _tableViewOptions,
              onViewChanged: (view) => setState(() => _tableView = view),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // La historia informa; la disponibilidad no se afirma desde ella.
        Text(
          'Precios históricos; disponibilidad por confirmar. El costo incluye el flete atribuible registrado y abrir el proveedor no genera una compra.',
          style: PurchaseType.meta.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        // Qué objetivo está reordenando la lista. Sin esto, un candidato que
        // sube por la marca preferida se ve como un ranking caprichoso.
        if (_commercialTarget != null) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _commercialTargetSentence ??
                    'Sin objetivo del taller: manda el ranking histórico.',
                style: PurchaseType.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              PurchaseInlineAction(
                key: const ValueKey('edit-commercial-target'),
                label: _commercialTarget!.hasTarget
                    ? 'Cambiar objetivo'
                    : 'Fijar objetivo',
                onPressed: _loadingDecision || _runningCommand
                    ? null
                    : () => setState(() => _editingCommercialTarget = true),
              ),
            ],
          ),
        ],
        if (_editingCommercialTarget && _commercialTarget != null) ...[
          const SizedBox(height: 10),
          CommercialTargetEditor(
            target: _commercialTarget!,
            busy: _runningCommand,
            onCancel: () => setState(() => _editingCommercialTarget = false),
            onSave: (values) => unawaited(_saveCommercialTarget(values)),
          ),
        ],
        const SizedBox(height: 12),
        // Frame 09 — el análisis quedó a medias. Va antes de los resultados y
        // conserva lo ya revisado.
        if (!blockedByStock && _analysisIsPartial)
          PartialAnalysisNotice(
            evaluated:
                (ranking?.items.length ?? 0) - _unevaluatedCandidates.length,
            total: ranking?.items.length ?? 0,
            pendingLabels: _unevaluatedCandidates
                .map((candidate) => candidate.supplierName)
                .toSet()
                .toList(growable: false),
            busy: _loadingDecision || _refreshingResults,
            onContinue: () => unawaited(_continueAnalysis()),
            technicalDetail: ranking?.hasMore == true
                ? 'El ranking se cortó en $_rankingLimit opciones y el servidor '
                    'indica que hay más. Continuar vuelve a pedirlo con '
                    '$_rankingExtendedLimit.'
                : 'Las opciones sin evaluar conservan su evidencia previa; '
                    'continuar no descarta lo ya comparado.',
          ),
        // **Todo error del paso activo se ve, y una sola vez.** Antes el aviso
        // sólo aparecía para conflicto o recarga incremental: un comando que
        // fallaba —fijar el producto, guardar el objetivo, agregar al plan—
        // dejaba el mensaje escrito en el estado y ninguna pantalla lo
        // mostraba, así que el operador veía la decisión intacta y creía que
        // su acción había pasado.
        ...?_decisionNotice(),
        // **Sin decisión cargada no se concluye nada.** Ni «no hay compras
        // comparables», ni «falta confirmar qué producto es»: las dos son
        // afirmaciones sobre datos que esta pantalla nunca tuvo. El fallo
        // genérico trae su propia superficie con su reintento; el conflicto ya
        // se dijo arriba con «Recargar la necesidad» y no necesita una segunda
        // banda que repita el mismo problema.
        if (_showsLoadFailure)
          DecisionLoadFailedSurface(
            busy: _loadingDecision,
            onRetry: () => unawaited(_retryDecisionLoad()),
          )
        else if (_decisionUnavailable)
          const SizedBox.shrink()
        // El servidor cerró el paso externo. Es un estado con su acción, no
        // «no se pudo completar el análisis».
        else if (_stockFirstRequired) ...[
          StockFirstRequiredSurface(
            busy: _runningCommand,
            onExplainRejection: () =>
                setState(() => _showStockRejection = true),
            onReviewStock: () => setState(() => _step = PurchaseStep.stock),
          ),
          if (_showStockRejection) ...[
            const SizedBox(height: 12),
            _buildStockRejectionInline(),
          ],
        ] else if (blockedByStock) ...[
          VbNotice(
            title: 'El stock interno todavía puede cubrir esta necesidad',
            body:
                'Usa la bodega o registra por qué no sirve antes de comparar proveedores.',
            tone: VbNoticeTone.neutral,
            action: TextButton(
              onPressed: () => setState(() => _showStockRejection = true),
              child: const Text('No me sirve el stock'),
            ),
          ),
          if (_showStockRejection) ...[
            const SizedBox(height: 12),
            _buildStockRejectionInline(),
          ],
        ]
        // Los siete estados en que no se propone comprar tienen cada uno su
        // causa y su acción. Colapsarlos en «sin resultados» le quitaría al
        // operador justamente lo que tiene que hacer después.
        else if (external != null && !external.isSuccess)
          ExternalCandidatesStateSurface(
            result: external,
            onEditNeed: () => setState(() => _step = PurchaseStep.need),
            onRegisterLocalPurchase: _openLocalPurchaseCapture,
          )
        // El vacío legado sólo aplica cuando **tampoco** hay sin verificar:
        // un conjunto que sólo trae opciones por verificar no es «no hay
        // compras comparables», y su grupo se dibuja más abajo.
        else if ((ranking == null || ranking.items.isEmpty) &&
            (external == null || external.unverifiedItems.isEmpty))
          // Superficie de decisión alineada a la izquierda, sin isla flotante.
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No hay compras históricas comparables',
                  style: PurchaseType.sectionTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  'Ninguna opción quedó descartada por incompatibilidad técnica: todavía no existe evidencia de compra para este producto.',
                  style: PurchaseType.meta.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const ValueKey('register-local-purchase'),
                  onPressed: _openLocalPurchaseCapture,
                  child: const Text('Registrar compra local'),
                ),
              ],
            ),
          )
        // Frame 10 — existen opciones pero el filtro activo las esconde todas.
        // No se confunde con «no hay compras históricas comparables», que es
        // otra causa y tiene su propia superficie.
        else if (_allCandidatesHiddenByFilters)
          NoMatchSurface(
            causeSentence: _noMatchCause,
            onClearFilters: _clearProviderFilters,
            onIncludeUnconfirmed: _includeUnconfirmedCompatibility,
            perCandidateExplanations: _noMatchExplanations,
          )
        else if (useCards)
          for (final candidate in _visibleCandidates)
            ProviderCandidateCard(
              candidate: candidate,
              selected: _inspectedCandidateId == candidate.candidateId,
              onSelect: () => setState(
                () => _inspectedCandidateId = candidate.candidateId,
              ),
            )
        else
          ProviderCandidatesTable(
            candidates: _visibleCandidates,
            selectedCandidateId: _inspectedCandidateId,
            showOptionalColumns: showOptionalColumns,
            onSelect: (candidate) => setState(
              () => _inspectedCandidateId = candidate.candidateId,
            ),
          ),
        // **Grupo aparte, rotulado.** «No lo sé» no es «no cumple»: los
        // candidatos que el ERP no pudo verificar se muestran, con su propia
        // página, y nunca mezclados con los accionables.
        if (!_stockFirstRequired &&
            external != null &&
            external.unverifiedItems.isNotEmpty) ...[
          UnverifiedCandidatesBand(
            count: external.counts.unverified,
            page: external.unverifiedPage,
            busy: _loadingDecision || _refreshingResults,
            // Su propia página: pedir más no verificados no recorta ni
            // reordena el grupo accionable, igual que en el servidor.
            onShowMore:
                external.unverifiedPage.hasMore ? _showMoreUnverified : null,
          ),
          if (useCards)
            for (final candidate in external.unverifiedItems)
              ProviderCandidateCard(
                candidate: candidate,
                selected: _inspectedCandidateId == candidate.candidateId,
                onSelect: () => setState(
                  () => _inspectedCandidateId = candidate.candidateId,
                ),
              )
          else
            ProviderCandidatesTable(
              candidates: external.unverifiedItems,
              selectedCandidateId: _inspectedCandidateId,
              showOptionalColumns: showOptionalColumns,
              onSelect: (candidate) => setState(
                () => _inspectedCandidateId = candidate.candidateId,
              ),
            ),
        ],
        // La vía manual de identidad, cuando no hay candidato que elegir.
        //
        // Conserva su ancho de lectura, pero **alineada a la izquierda**: los
        // bloques que tiene encima —el recuento, el aviso de stock— ocupan la
        // región entera de resultados, así que centrarla la dejaba como una
        // isla flotando en medio de un lienzo vacío, con su borde izquierdo
        // sin relación con nada. Es el mismo defecto que ya se corrigió en
        // «Selecciona una necesidad», y el contrato lo prohíbe: la superficie
        // de decisión del frame 10 va a la izquierda, sin isla.
        if (identityFallback != null) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: PurchaseSurfaceGeometry.narrowColumnMax,
              ),
              child: identityFallback,
            ),
          ),
        ],
      ],
    );
  }

  /// El objetivo comercial vigente, dicho en una línea.
  ///
  /// La moneda es la **de la revisión** que fijó el tope, no la del taller de
  /// hoy: si el taller cambió de moneda, releer el tope en la de hoy lo
  /// reinterpretaría y nadie lo notaría.
  String? get _commercialTargetSentence {
    final target = _commercialTarget;
    if (target == null || !target.hasTarget) return null;
    final parts = <String>[];
    final values = target.target;
    if (values.gama != null) parts.add('gama ${values.gama}');
    if (values.preferredBrandId != null) {
      parts.add(
        target.preferredBrandAvailable == false
            ? 'marca preferida (ya no disponible)'
            : 'marca preferida',
      );
    }
    if (values.maxLandedUnitCostNet != null) {
      parts.add(
        'tope ${target.currencyCode} '
        '${values.maxLandedUnitCostNet!.toStringAsFixed(0)}',
      );
    }
    if (values.minGrossMarginRatio != null) {
      parts.add(
        'margen mínimo '
        '${(values.minGrossMarginRatio! * 100).toStringAsFixed(0)}%',
      );
    }
    if (parts.isEmpty) return null;
    final rebased = target.currencyRebased
        ? ' El taller opera hoy en ${target.tenantCurrencyCode}.'
        : '';
    return 'Objetivo del taller: ${parts.join(' · ')}.$rebased';
  }

  /// Corte base del ranking, el mismo que usa el servicio por omisión.
  static const int _rankingBaseLimit = 10;

  /// Corte ampliado que pide «Continuar análisis» (frame 09).
  static const int _rankingExtendedLimit = 25;

  /// Corte base del grupo sin verificar. Es su propia página: ampliarla no
  /// toca la de los accionables, igual que en el servidor.
  static const int _unverifiedBaseLimit = 5;

  /// Corte base de la bodega del carril familia, y cuánto crece cada vez.
  static const int _stockBaseLimit = 12;
  static const int _stockStep = 12;

  /// Cuánto crece ese grupo cada vez que el operador pide ver más.
  static const int _unverifiedStep = 5;

  /// Candidatos que el servidor devolvió sin evaluar.
  ///
  /// No es una condición inventada: `evidenceQuality == 'unevaluated'` es el
  /// estado que el propio ranking publica cuando una opción entró en la lista
  /// pero no alcanzó a compararse.
  List<PurchaseCandidate> get _unevaluatedCandidates =>
      _ranking?.items
          .where((candidate) => candidate.evidenceQuality == 'unevaluated')
          .toList(growable: false) ??
      const [];

  /// El análisis quedó a medias si hay opciones sin evaluar, o si el ranking
  /// se cortó en el límite y todavía hay más.
  bool get _analysisIsPartial =>
      _unevaluatedCandidates.isNotEmpty || (_ranking?.hasMore ?? false);

  /// El filtro real de la comparación: `confirmed_only` esconde a quien no
  /// tiene evidencia suficiente para afirmar compatibilidad.
  bool get _hidingUnconfirmedCompatibility => _tableView == 'confirmed_only';

  /// Lo que el operador ve después de aplicar el filtro activo.
  List<PurchaseCandidate> get _visibleCandidates {
    final items = _ranking?.items ?? const <PurchaseCandidate>[];
    if (!_hidingUnconfirmedCompatibility) return items;
    return items.where(_compatibilityIsConfirmed).toList(growable: false);
  }

  /// **«Compatibilidad confirmada» es una pregunta técnica.**
  ///
  /// El filtro leía `evidenceQuality`, que mide qué tan firme es el historial
  /// económico —costo, flete, recencia—. Con eso, un candidato con factura
  /// impecable pasaba el filtro de compatibilidad sin que nadie hubiera
  /// comprobado que calza, y uno que la ficha confirma quedaba fuera por tener
  /// una compra vieja. Son dos preguntas distintas y el rótulo promete la
  /// técnica.
  ///
  /// Para el candidato de la fase B2 sólo `strong` está confirmado contra la
  /// ficha: `weak` coincide por el nombre, `no_criteria` no tuvo nada que
  /// comparar y `unverified` no se pudo verificar —y además viaja en su propio
  /// grupo—. El candidato histórico, que no sabe nada de `matchState`,
  /// conserva su lectura económica de siempre, dicha por separado.
  static bool _compatibilityIsConfirmed(PurchaseCandidate candidate) {
    if (candidate is SupplyExternalCandidate) {
      return candidate.matchState == 'strong';
    }
    return candidate.evidenceQuality == 'complete';
  }

  /// Por qué **este** candidato queda fuera del filtro, en su propio idioma.
  static String _hiddenReason(PurchaseCandidate candidate) {
    if (candidate is SupplyExternalCandidate) {
      return switch (candidate.matchState) {
        'weak' => 'coincide por el nombre, no por la ficha',
        'no_criteria' => 'la petición no traía criterios que comparar',
        'unverified' => 'la ficha no alcanza para verificarlo',
        _ => 'sin confirmación técnica',
      };
    }
    return switch (candidate.evidenceQuality) {
      'partial' => 'evidencia económica por revisar',
      'unevaluated' => 'sin evaluar',
      _ => 'evidencia económica débil',
    };
  }

  /// Existen opciones, pero el filtro activo las esconde todas (frame 10).
  bool get _allCandidatesHiddenByFilters =>
      (_ranking?.items.isNotEmpty ?? false) && _visibleCandidates.isEmpty;

  /// Frase de causa del frame 10, construida con los números reales.
  String get _noMatchCause {
    final total = _ranking?.items.length ?? 0;
    return 'Existen $total ${total == 1 ? 'opción' : 'opciones'}, pero el filtro '
        'activo las esconde todas: «sólo compatibilidad confirmada» deja pasar '
        'únicamente lo que la ficha confirma. Los criterios de la petición no '
        'cambiaron y ninguna opción quedó descartada por incompatibilidad '
        'técnica.';
  }

  List<String> get _noMatchExplanations => (_ranking?.items ?? const [])
      .where((candidate) => !_compatibilityIsConfirmed(candidate))
      .map((candidate) => '${candidate.productName} — '
          '${_hiddenReason(candidate)}')
      .toList(growable: false);

  /// «Continuar análisis» (frame 09): vuelve a pedir el ranking con el corte
  /// ampliado. Es el mínimo relanzamiento posible y conserva perfil, selección
  /// y paso; no descarta lo ya revisado.
  Future<void> _continueAnalysis() async {
    final need = _selectedNeed;
    if (need == null || _loadingDecision || _refreshingResults) return;
    if (_rankingLimit >= _rankingExtendedLimit && !_analysisIsPartial) return;
    setState(() => _rankingLimit = _rankingExtendedLimit);
    // Incremental: continuar el análisis amplía lo comparado, no lo reemplaza
    // por un spinner.
    await _loadDecision(need, resetRankingLimit: false, incremental: true);
  }

  /// «Quitar filtros» (frame 10): devuelve la vista a su estado sin filtrar.
  void _clearProviderFilters() {
    if (_tableView == 'auto') return;
    setState(() => _tableView = 'auto');
  }

  /// «Incluir opciones con compatibilidad por confirmar» (frame 10).
  ///
  /// Es la misma palanca que el menú «Vista», expuesta donde el operador la
  /// necesita. Reversible: volver a elegir «Sólo compatibilidad confirmada»
  /// restablece el filtro.
  void _includeUnconfirmedCompatibility() {
    if (!_hidingUnconfirmedCompatibility) return;
    setState(() => _tableView = 'auto');
  }

  /// Perfiles de comparación publicados por el spec.
  static const Map<String, String> _rankingProfileOptions = {
    'balanced': 'Equilibrado',
    'profitability': 'Mayor rentabilidad',
    'urgent_local': 'Urgente/local',
  };

  /// Densidad de la tabla. `auto` respeta el ancho útil real; `compact` oculta
  /// las columnas opcionales aunque quepan. No existe una opción que las fuerce
  /// cuando no caben: eso produciría la tabla comprimida que el frame descarta.
  static const Map<String, String> _tableViewOptions = {
    'auto': 'Automática',
    'compact': 'Sólo columnas esenciales',
    'confirmed_only': 'Sólo compatibilidad confirmada',
  };

  /// Encabezado de resultados del frame 03/04/16/26: «N candidatos ·
  /// M proveedores». El segundo recuento cuenta proveedores distintos, no
  /// filas: dos candidatos del mismo proveedor no son dos proveedores.
  /// El recuento aparece **una vez**, en el encabezado de la comparación
  /// (`frames[weak-evidence].count_rule`), y nunca dice «nada visible» con
  /// filas a la vista: los candidatos por confirmar se muestran en su propio
  /// grupo, así que «Sin opciones visibles» encima de ellos era falso.
  String _candidateCountLabel(PurchaseRanking? ranking, {int unverified = 0}) {
    if (ranking == null || ranking.items.isEmpty) {
      if (unverified > 0) {
        return '0 verificados · $unverified por confirmar';
      }
      return 'Sin opciones visibles';
    }
    final candidates = ranking.items.length;
    final suppliers = ranking.items
        .map((candidate) => candidate.supplierName.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;
    final candidateWord = candidates == 1 ? 'candidato' : 'candidatos';
    final supplierWord = suppliers == 1 ? 'proveedor' : 'proveedores';
    final base = '$candidates $candidateWord · $suppliers $supplierWord';
    return unverified > 0 ? '$base · $unverified por confirmar' : base;
  }

  /// Abre el portal del proveedor **dentro del ERP**.
  ///
  /// El dueño lo pidió explícitamente: «abrir automáticamente la página del
  /// proveedor, que ya va a estar logueado si tiene sus credenciales listas».
  /// Esto hacía `launchUrl(externalApplication)`, que echa al navegador del
  /// sistema —otra ventana, otra sesión, sin nada guardado—: justo lo contrario.
  ///
  /// El ERP ya tiene su propio navegador con pestañas y sesión persistente, así
  /// que el portal abre ahí y la sesión del proveedor sobrevive entre visitas.
  /// Si el navegador interno no puede tomarlo —tope de pestañas o URL inválida—
  /// se cae al del sistema en vez de dejar el botón muerto.
  ///
  /// Las credenciales no se escriben desde acá: el ERP las guarda cifradas y su
  /// revelación es una acción explícita del operador, con su propio recibo.
  Future<void> _openSupplier(String rawUrl, {String? supplierName}) async {
    final parsed = Uri.tryParse(rawUrl.trim());
    final uri = parsed != null && parsed.hasScheme
        ? parsed
        : Uri.tryParse('https://${rawUrl.trim()}');
    if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) return;

    final opened = context.read<WorkspaceManager>().openBrowserWorkspace(
          uri.toString(),
          title: supplierName,
        );
    if (opened != null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildPlanSurface() {
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Frames 07/18/21/24: «Plan borrador» con su recuento y dos acciones
        // secundarias. Aquí vivía una losa `VbNotice` que el owner rechazó:
        // repetía en un bloque tonal lo que la cabecera ya dice en texto.
        PlanDraftHeader(
          lineCount: plan.lines.length,
          compact: compact,
          purchasedLabel: 'nada comprado',
          onBackToCompare: () => setState(() => _step = PurchaseStep.providers),
          onRegisterLocalPurchase: _openLocalPurchaseCapture,
        ),
        if (_decisionError != null) ...[
          VbNotice(
            title: _decisionError!,
            tone: _needsReload ? VbNoticeTone.warning : VbNoticeTone.danger,
            // Un 40001 no se reintenta con la versión vieja: se relee. La
            // acción está en el aviso porque es la única salida.
            action: _needsReload
                ? TextButton(
                    key: const ValueKey('reload-after-conflict'),
                    onPressed: _reloadAfterConflict,
                    child: const Text('Recargar la necesidad'),
                  )
                : null,
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: plan.supplierGroups.isEmpty
              // El vacío es la misma superficie inline del frame 06: nunca una
              // isla centrada sobre el resto del plan.
              ? SingleChildScrollView(
                  child: PlanEmptyInline(
                    compact: compact,
                    onChooseCandidate: () =>
                        setState(() => _step = PurchaseStep.providers),
                    onRegisterLocalPurchase: _openLocalPurchaseCapture,
                  ),
                )
              : ListView.separated(
                  itemCount: plan.supplierGroups.length,
                  // Cada proveedor ya es una tarjeta cerrada; una raya entre
                  // dos tarjetas es un borde de más. La separación es la del
                  // prototipo (`gap:11px`).
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: PurchaseMetrics.stageGap),
                  itemBuilder: (context, index) {
                    final group = plan.supplierGroups[index];
                    final lines = plan.lines
                        .where((line) =>
                            line.supplierName == group.supplierName &&
                            line.currency == group.currency)
                        .toList(growable: false);
                    return PurchasePlanGroup(
                      group: group,
                      lines: lines,
                      removingLineId: _removingPlanLineId,
                      updatingLineId: _updatingPlanLineId,
                      editingLineId: _editingPlanLineId,
                      quantityController: _planQuantityController,
                      quantityError: _planQuantityError,
                      onEditQuantity: _openPlanQuantityEditor,
                      onCancelQuantity: _cancelPlanQuantityEditor,
                      onCommitQuantity: (line) =>
                          unawaited(_commitPlanQuantity(line)),
                      onStepQuantity: (line, quantity) =>
                          unawaited(_setPlanQuantity(line, quantity)),
                      onRemove: _removePlanLine,
                      onSaveNote: _savePlanLineNote,
                      onSubstitute: _substitutePlanLine,
                      savingNoteLineId: _savingNoteLineId,
                    );
                  },
                ),
        ),
        // Totales y cierre: los define `frames[plan].with_lines` del spec y no
        // existían en el módulo. Sin ellos el plan no terminaba en ninguna
        // parte.
        if (plan.lines.isNotEmpty) ...[
          const SizedBox(height: PurchaseMetrics.stageGap),
          PurchasePlanClose(
            lines: plan.lines,
            supplierCount: plan.supplierGroups.length,
            missingCount: _planMissingCount(plan),
          ),
        ],
      ],
    );
  }

  /// Lo que el plan deja fuera: necesidades abiertas que no llegaron a línea.
  int _planMissingCount(PurchasePlanDraft plan) {
    final planned = plan.lines.map((line) => line.sourceNeedId).toSet();
    return _needs
        .where(
            (need) => need.supplyState == 'open' && !planned.contains(need.id))
        .length;
  }

  String _needSubtitle(SupplyNeed need) {
    final quantity = _formatSupplyQuantity(need.quantity);
    return '$quantity ${need.unit == 'unit' ? 'unidad(es)' : need.unit} · '
        '${_needOrigin(need)}';
  }

  /// De dónde salió la necesidad, sin la cantidad.
  String _needOrigin(SupplyNeed need) => need.originKind == 'mechanic_job'
      ? 'Trabajo de taller'
      : 'Solicitud directa';

  /// Cuántas piezas del resumen caben antes del «+N».
  ///
  /// El contrato muestra cuatro y luego «+1» (NOTES §46). No es un número
  /// elegido a ojo: es el corte del frame.
  static const int _criteriaSummaryVisible = 4;

  /// El resumen de una línea que pide la barra de necesidad.
  ///
  /// Los predicados van primero porque son los que el servidor usa para
  /// eliminar candidatos; la preferencia comercial va al final porque no
  /// gobierna nada. Lo que no cabe se cuenta, no se corta a mitad de palabra.
  String _criteriaSummaryLine(SupplyNeedCriteria criteria) {
    final parts = <String>[
      for (final predicate in criteria.predicates) _criterionLabel(predicate),
      if (criteria.commercialPreference?.trim().isNotEmpty ?? false)
        criteria.commercialPreference!.trim(),
    ];
    if (parts.length <= _criteriaSummaryVisible) return parts.join(' · ');
    final shown = parts.take(_criteriaSummaryVisible).join(' · ');
    return '$shown · +${parts.length - _criteriaSummaryVisible}';
  }

  /// Un predicado guardado, dicho con el mismo vocabulario que el borrador.
  ///
  /// Reusa la tabla de comparadores de `_predicateLabel` en vez de escribir una
  /// segunda: dos formas de decir «mayor a» en el mismo módulo se separan al
  /// primer cambio.
  String _criterionLabel(SupplyNeedPredicate predicate) => _predicateLabel(
        AIAssistantSupplyNeedTechnicalPredicate(
          field: predicate.field,
          operator: predicate.operator,
          values: predicate.values,
        ),
      );

  /// Tomar una sugerencia: el mínimo input es **un toque**.
  ///
  /// El sistema ya sabe qué, cuántos y por qué; pedirle a la persona que lo
  /// reescriba sería devolverle el trabajo que este panel le quitó. Si la
  /// sugerencia trae producto exacto, la necesidad nace confirmada y el
  /// recorrido puede ir directo a bodega.
  Future<void> _takePriority(PurchasePrioritySuggestion suggestion) async {
    if (_takingPriorityId != null) return;
    setState(() => _takingPriorityId = suggestion.entityId);
    try {
      final need = await _service.createNeed(
        description: suggestion.title,
        quantity: suggestion.suggestedQuantity,
        unit: suggestion.unit,
        productId: suggestion.productId,
      );
      if (!mounted) return;
      setState(() {
        _priority = _priority
            .where((item) => item.entityId != suggestion.entityId)
            .toList(growable: false);
        _needs = [need, ..._needs];
        _takingPriorityId = null;
      });
      _selectNeed(need);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _takingPriorityId = null;
        _decisionError = 'No se pudo tomar «${suggestion.title}»: $error';
      });
    }
  }
}

String _assistantGatewayErrorMessage(AIAgentGatewayException error) {
  return switch (error.code) {
    'agent_budget_exhausted' =>
      'No pude cerrar el análisis con evidencia suficiente. Reintenta o simplifica sólo si quieres acotar la búsqueda.',
    'assistant_quota_exceeded' ||
    'rate_limited' =>
      'El asistente alcanzó su límite momentáneo. Espera un momento y vuelve a intentarlo.',
    'provider_unavailable' ||
    'provider_rejected' ||
    'provider_invalid_response' =>
      'El modelo no pudo responder de forma verificable. Puedes reintentar sin perder la petición.',
    'invalid_request' =>
      'La petición no pudo enviarse con el formato esperado. Revísala y vuelve a intentarlo.',
    'origin_not_allowed' =>
      'Esta compilación no está autorizada para usar la conversación con IA. El stock y las necesidades guardadas siguen disponibles.',
    'invalid_session' =>
      'La sesión ya no permite consultar al asistente. Vuelve a iniciar sesión; el resto del workspace sigue disponible.',
    'forbidden' ||
    'assistant_forbidden' ||
    'authority_changed' =>
      'Tu acceso cambió y esta conversación no puede continuar. El stock y las necesidades guardadas siguen disponibles.',
    'request_timeout' ||
    'request_aborted' ||
    'gateway_unavailable' ||
    'invalid_response' ||
    'response_too_large' ||
    'run_finalization_pending' ||
    'run_in_progress' =>
      'El resultado todavía no está confirmado. Reintenta para recuperar la misma ejecución sin duplicarla.',
    _ => 'El análisis no pudo completarse. Reintenta sin perder la petición.',
  };
}

class _PurchaseScenarioPanel extends StatelessWidget {
  const _PurchaseScenarioPanel({
    required this.scenario,
    required this.selected,
    required this.onSelect,
    required this.initiallyExpanded,
    required this.preparing,
    required this.commandsEnabled,
    required this.onPrepare,
    required this.onReviewLine,
  });

  final PurchaseScenario scenario;

  /// Frame 11 — un radio por escenario; la elección sobrevive a la pestaña.
  final bool selected;
  final VoidCallback onSelect;
  final bool initiallyExpanded;
  final bool preparing;
  final bool commandsEnabled;
  final VoidCallback onPrepare;
  final ValueChanged<PurchaseScenarioLine> onReviewLine;

  @override
  Widget build(BuildContext context) {
    final missing = scenario.totalLineCount - scenario.coverageLineCount;
    final externalCandidates = scenario.externalCandidates;
    final firstLine = scenario.lines.isEmpty ? null : scenario.lines.first;
    return ExpansionTile(
      key: PageStorageKey<String>('purchase-scenario-${scenario.key}'),
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Row(
        children: [
          Radio<bool>(
            value: true,
            // ignore: deprecated_member_use
            groupValue: selected,
            // ignore: deprecated_member_use
            onChanged: (_) => onSelect(),
          ),
          Expanded(
            child: Text(
              scenario.label,
              style: PurchaseType.rowTitle,
            ),
          ),
          if (scenario.historicalSubtotals.length == 1) ...[
            const SizedBox(width: 12),
            _ScenarioSubtotalText(
              subtotal: scenario.historicalSubtotals.single,
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${scenario.coverageLineCount} de ${scenario.totalLineCount} cubiertos · ${scenario.supplierCount} ${scenario.supplierCount == 1 ? 'proveedor' : 'proveedores'}${missing > 0 ? ' · faltan $missing' : ''}',
      ),
      children: [
        ...scenario.lines.map(
          (line) => _ScenarioLineTile(
            line: line,
            onTap: () => onReviewLine(line),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: externalCandidates.isEmpty
              ? OutlinedButton.icon(
                  onPressed:
                      firstLine == null ? null : () => onReviewLine(firstLine),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Revisar stock interno'),
                )
              : FilledButton.icon(
                  key: ValueKey<String>('prepare-scenario-${scenario.key}'),
                  onPressed: commandsEnabled ? onPrepare : null,
                  icon: preparing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_outlined, size: 18),
                  label: Text(
                    'Agregar ${externalCandidates.length} ${externalCandidates.length == 1 ? 'alternativa' : 'alternativas'} al plan',
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          'El total suma costos aterrizados históricos por línea; no supone ahorro adicional de flete por consolidar.',
          style: PurchaseType.meta.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ScenarioLineTile extends StatelessWidget {
  const _ScenarioLineTile({required this.line, required this.onTap});

  final PurchaseScenarioLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final margin = line.projectedGrossMarginRatio;
    final detail = switch (line.sourcing) {
      'internal' =>
        'Stock interno · ATP ${line.availableToPromise} para ${_formatSupplyQuantity(line.requestedQuantity)}',
      'external' =>
        '${line.supplierName ?? 'Proveedor histórico'} · disponibilidad por confirmar${margin == null ? '' : ' · margen ${(margin * 100).toStringAsFixed(1)}%'}',
      _ => 'Sin alternativa histórica · revisar identidad o proveedor',
    };
    final icon = switch (line.sourcing) {
      'internal' => Icons.inventory_2_outlined,
      'external' => line.isConfirmedLocal
          ? Icons.storefront_outlined
          : Icons.local_shipping_outlined,
      _ => Icons.error_outline,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(
        line.productName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (line.latestLandedUnitCostNet != null)
            line.currency == null || line.currency == 'CLP'
                ? VbMoneyText(line.latestLandedUnitCostNet)
                : Text(
                    '${line.currency} ${line.latestLandedUnitCostNet!.toStringAsFixed(2)}',
                  ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ScenarioSubtotalText extends StatelessWidget {
  const _ScenarioSubtotalText({required this.subtotal});

  final PurchaseScenarioSubtotal subtotal;

  @override
  Widget build(BuildContext context) {
    // `VbMoneyText` fija su tamaño por dentro (14) y asume peso chileno, así
    // que el subtotal de un escenario en USD se dibujaba con otra escala que
    // el de al lado y la columna dejaba de alinear. La cifra llega ya
    // formateada por `PurchaseMoney.format` —que reusa el mismo formato de
    // pesos— y la escala la pone `metric_sm`, el rol que el spec asigna a los
    // totales de grupo. Se pierde el cero apagado de `VbMoneyText`: un
    // subtotal de escenario en cero es un total real, no un «no aplica».
    return Text(
      PurchaseMoney.format(subtotal.amount, subtotal.currency),
      style: PurchaseType.metricSmall.copyWith(
        color: PurchaseTokens.of(context).ink,
        fontFeatures: PurchaseType.tabular,
      ),
    );
  }
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

String _formatSupplyQuantity(double value) {
  if (value == value.truncateToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

String _supplyUnitEditorValue(String raw) => switch (raw.trim().toLowerCase()) {
      'unit' || 'units' || 'unidad' || 'unidades' => 'unidad',
      'pair' || 'pairs' || 'par' || 'pares' => 'par',
      'set' || 'sets' || 'juego' || 'juegos' => 'juego',
      'meter' ||
      'meters' ||
      'metre' ||
      'metres' ||
      'metro' ||
      'metros' =>
        'metro',
      _ => raw.trim(),
    };

String _canonicalSupplyUnit(String raw) => switch (raw.trim().toLowerCase()) {
      'unit' || 'units' || 'unidad' || 'unidades' => 'unit',
      'pair' || 'pairs' || 'par' || 'pares' => 'pair',
      'set' || 'sets' || 'juego' || 'juegos' => 'set',
      'meter' ||
      'meters' ||
      'metre' ||
      'metres' ||
      'metro' ||
      'metros' =>
        'meter',
      _ => raw.trim(),
    };

String _supplyProfileLabel(AIAssistantSupplyNeedProfile profile) =>
    switch (profile) {
      AIAssistantSupplyNeedProfile.balanced => 'equilibrio',
      AIAssistantSupplyNeedProfile.profitability => 'rentabilidad',
      AIAssistantSupplyNeedProfile.urgentLocal => 'urgencia local',
    };

double? _parseSupplyQuantity(String? raw) {
  final normalized = raw?.trim().replaceAll(',', '.');
  if (normalized == null || normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

/// Manija del split pane del inspector.
///
/// El asa visual es discreta, pero su área de arrastre cubre todo el alto y
/// declara `separator` con sus límites para el teclado y el lector.
class _InspectorPaneHandle extends StatelessWidget {
  const _InspectorPaneHandle({required this.width, required this.onDelta});

  final double width;
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Ancho del panel de detalle',
      value: '${width.round()} píxeles',
      slider: true,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            onDelta(24);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            onDelta(-24);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) => onDelta(details.delta.dx),
            child: SizedBox(
              width: PurchaseSurfaceGeometry.inspectorHandleWidth,
              child: Center(
                child: Container(
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de necesidad abierta en el paso 1. Lista de texto estable: sin nube de
/// cápsulas y sin repetir el estado en cada columna.
class _OpenNeedRow extends StatelessWidget {
  const _OpenNeedRow({
    super.key,
    required this.need,
    required this.selected,
    required this.selecting,
    required this.subtitle,
    required this.onTap,
  });

  final SupplyNeed need;
  final bool selected;
  final bool selecting;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PurchaseTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? tokens.selected : null,
          // Dentro del panel la separación es `hairline`, no el borde de una
          // caja: `outlineVariant` acá dibujaba el contorno de otro objeto.
          border: Border(top: BorderSide(color: tokens.hair)),
        ),
        child: Row(
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    need.productName ?? need.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuerpo de una hoja anclada con la misma anatomía que tenía el diálogo
/// (título, contenido y acciones), pero sin superficie centrada ni velo.

/// Edición de cantidad dentro de la fila del plan.
///
/// Sustituye la fila en su sitio y a su mismo ancho: no hay tarjeta flotante,
/// ni centrado, ni bloqueo de la navegación mientras se corrige un número.
