/// El recorrido del Asistente de compras, fuera de la pantalla.
///
/// Antes el recorrido vivía en ~40 campos del `State` de una página de 4.803
/// líneas: paso, necesidad elegida, stock, ranking, plan, canasta, filtros,
/// cantidades y una decena de banderas booleanas que decidían qué panel
/// aparecía. Dos consecuencias que el dueño sintió al usarlo: salir del módulo
/// borraba todo, y el «volver» era un único booleano puesto a mano en seis
/// lugares, no un historial.
///
/// El `spec.json` del handoff t23 pide exactamente lo contrario en su
/// `navigation_contract`: *pila propia con índice; back/forward navegan entre
/// las cuatro superficies conservando borradores, selección, filtros,
/// cantidades y scroll*. Eso es lo que implementa este controlador, y por eso
/// vive sobre la página y no dentro de ella.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/intelligent_purchasing_models.dart';
import 'intelligent_purchasing_service.dart';

/// Las cuatro superficies del recorrido, en el orden en que se trabajan.
enum PurchaseStep { need, stock, providers, plan }

/// Una posición del historial: dónde estaba parado el operador.
///
/// Sólo guarda *dónde*, nunca los datos. Los datos viven en el controlador y se
/// comparten entre posiciones — así volver atrás muestra lo mismo que había, en
/// vez de una copia congelada o una pantalla vacía.
@immutable
class PurchaseJourneyStop {
  const PurchaseJourneyStop({required this.step, this.needId});

  final PurchaseStep step;
  final String? needId;

  @override
  bool operator ==(Object other) =>
      other is PurchaseJourneyStop &&
      other.step == step &&
      other.needId == needId;

  @override
  int get hashCode => Object.hash(step, needId);
}

/// Dueño del recorrido: posición, historial y todo lo que no debe perderse.
class PurchaseJourneyController extends ChangeNotifier {
  PurchaseJourneyController(this._service);

  final IntelligentPurchasingService _service;

  // ── Historial ───────────────────────────────────────────────────────────
  //
  // Una pila con cursor, igual que la de un navegador: avanzar desde el medio
  // descarta lo que venía delante. `_stops` nunca queda vacía.
  final List<PurchaseJourneyStop> _stops = <PurchaseJourneyStop>[
    const PurchaseJourneyStop(step: PurchaseStep.need),
  ];
  int _cursor = 0;

  PurchaseJourneyStop get position => _stops[_cursor];
  PurchaseStep get step => position.step;
  String? get needId => position.needId;

  bool get canGoBack => _cursor > 0;
  bool get canGoForward => _cursor < _stops.length - 1;

  /// Historial visible, para que la banda de proceso muestre por dónde se pasó.
  List<PurchaseJourneyStop> get trail => List.unmodifiable(_stops);

  // ── Estado que sobrevive a la navegación ────────────────────────────────
  //
  // Cacheado por necesidad, no por paso: volver al stock de la necesidad A
  // después de mirar la B tiene que mostrar lo de A tal cual estaba.
  List<PurchasePrioritySuggestion> _priority = const [];
  List<SupplyNeed> _needs = const [];
  final Map<String, SupplyNeed> _needById = {};
  final Map<String, SupplyInventorySnapshot> _snapshots = {};
  final Map<String, PurchaseRanking> _rankings = {};
  final Map<String, double> _scrollOffsets = {};
  PurchaseScenarioResult? _scenarios;
  PurchasePlanDraft? _plan;

  /// Perfil de comparación y ancho del inspector: preferencias del operador
  /// dentro del recorrido. `state_preservation` las nombra explícitamente.
  String _rankingProfile = 'balanced';

  /// Gama pedida: `economica`, `media`, `alta`, o ninguna.
  ///
  /// Es el control más valioso para alguien sin experiencia, porque es el
  /// juicio que le falta: «esto es para una bici de arriendo» contra «esto es
  /// para un cliente que gastó plata».
  String? _gama;
  double _inspectorWidth = 420;
  String? _inspectedCandidateId;

  /// Qué hay que comprar, según el sistema. Es con lo que abre el módulo.
  List<PurchasePrioritySuggestion> get priority => List.unmodifiable(_priority);
  List<SupplyNeed> get needs => List.unmodifiable(_needs);
  SupplyNeed? get selectedNeed => needId == null ? null : _needById[needId];
  SupplyInventorySnapshot? get snapshot =>
      needId == null ? null : _snapshots[needId];
  PurchaseRanking? get ranking => needId == null ? null : _rankings[needId];
  PurchaseScenarioResult? get scenarios => _scenarios;
  PurchasePlanDraft? get plan => _plan;
  String get rankingProfile => _rankingProfile;
  String? get gama => _gama;
  double get inspectorWidth => _inspectorWidth;
  String? get inspectedCandidateId => _inspectedCandidateId;

  /// Scroll por superficie, para que volver no salte al principio.
  double scrollOffsetFor(PurchaseStep step) => _scrollOffsets[step.name] ?? 0;
  void rememberScroll(PurchaseStep step, double offset) =>
      _scrollOffsets[step.name] = offset;

  // ── Estado efímero ──────────────────────────────────────────────────────
  //
  // Esto sí es de la vuelta actual: si falla o termina, no debe sobrevivir.
  bool _busy = false;
  String? _failure;

  bool get busy => _busy;
  String? get failure => _failure;

  // ── Navegación ──────────────────────────────────────────────────────────

  /// Va a una superficie. Si ya estamos ahí, no ensucia el historial.
  ///
  /// No borra nada: el estado es del controlador y se comparte entre paradas.
  /// Ése es el punto — cambiar de paso jamás destruye lo trabajado.
  void goTo(PurchaseStep step, {String? needId}) {
    final target = PurchaseJourneyStop(
      step: step,
      needId: needId ?? this.needId,
    );
    if (target == position) return;
    if (canGoForward) _stops.removeRange(_cursor + 1, _stops.length);
    _stops.add(target);
    _cursor = _stops.length - 1;
    _failure = null;
    notifyListeners();
  }

  void back() {
    if (!canGoBack) return;
    _cursor -= 1;
    _failure = null;
    notifyListeners();
  }

  void forward() {
    if (!canGoForward) return;
    _cursor += 1;
    _failure = null;
    notifyListeners();
  }

  // ── Preferencias del recorrido ──────────────────────────────────────────

  void setRankingProfile(String profile) {
    if (_rankingProfile == profile) return;
    _rankingProfile = profile;
    // El ranking cacheado quedó calculado con otro perfil: se invalida sólo el
    // de esta necesidad, no el de las demás.
    if (needId != null) _rankings.remove(needId);
    notifyListeners();
  }

  /// Cambiar la gama sólo invalida el ranking de la necesidad en curso: lo
  /// consultado para las demás sigue siendo válido.
  void setGama(String? gama) {
    if (_gama == gama) return;
    _gama = gama;
    if (needId != null) _rankings.remove(needId);
    notifyListeners();
  }

  void setInspectorWidth(double width) {
    if (_inspectorWidth == width) return;
    _inspectorWidth = width;
    notifyListeners();
  }

  void inspect(String? candidateId) {
    if (_inspectedCandidateId == candidateId) return;
    _inspectedCandidateId = candidateId;
    notifyListeners();
  }

  // ── Cargas ──────────────────────────────────────────────────────────────
  //
  // Cada carga es idempotente y cacheada: entrar dos veces a la misma
  // superficie no vuelve a pegarle a la base ni pierde lo que ya había.

  /// La prioridad se pide una vez por sesión de trabajo: es una foto de la
  /// mañana, no un dato que cambie mientras la persona decide.
  Future<void> loadPriority({bool force = false}) async {
    if (_priority.isNotEmpty && !force) return;
    await _guard(
        () async => _priority = await _service.fetchPurchasePriority());
  }

  /// Saca una sugerencia de la lista cuando ya se actuó sobre ella, sin
  /// recargar todo: volver atrás no debe hacerla reaparecer.
  void dismissPriority(String entityId) {
    final next = _priority
        .where((item) => item.entityId != entityId)
        .toList(growable: false);
    if (next.length == _priority.length) return;
    _priority = next;
    notifyListeners();
  }

  Future<void> loadNeeds({bool force = false}) async {
    if (_needs.isNotEmpty && !force) return;
    await _guard(() async {
      final needs = await _service.fetchOpenNeeds();
      _needs = needs;
      for (final need in needs) {
        _needById[need.id] = need;
      }
    });
  }

  Future<void> loadStock({bool force = false}) async {
    final id = needId;
    if (id == null) return;
    if (_snapshots.containsKey(id) && !force) return;
    await _guard(
        () async => _snapshots[id] = await _service.inventorySnapshot(id));
  }

  Future<void> loadRanking({bool force = false}) async {
    final id = needId;
    final need = selectedNeed;
    if (id == null || need == null) return;
    if (_rankings.containsKey(id) && !force) return;
    await _guard(() async {
      // El kernel acepta una identidad exacta **o** uno breve, nunca los dos.
      // Con producto confirmado se rankea esa identidad; sin él, la descripción
      // del operador, recortada a los 240 bytes que admite el RPC.
      //
      // CUIDADO al cablear esto (medido en producción, 2026-08-17): el camino
      // por **texto** tarda ~32 s con los datos del taller real y el ranking se
      // corta a los 4,5 s. Es un defecto anterior a este trabajo, todavía sin
      // resolver; la pantalla actual no lo toca porque siempre rankea por
      // producto exacto. Antes de usar la rama de `query` en una superficie
      // real hay que arreglar el kernel, o el operador verá un error opaco.
      final confirmed = need.productId;
      _rankings[id] = await _service.rankCandidates(
        productId: confirmed,
        query: confirmed == null ? _boundedQuery(need.description) : null,
        profile: _rankingProfile,
        gama: _gama,
      );
    });
  }

  Future<void> loadPlan(String planId, {bool force = false}) async {
    if (_plan != null && !force) return;
    await _guard(() async => _plan = await _service.fetchPlan(planId));
  }

  /// Reemplaza el plan tras un comando que lo modificó.
  void adoptPlan(PurchasePlanDraft? plan) {
    _plan = plan;
    notifyListeners();
  }

  /// Reemplaza una necesidad tras editarla, conservando su caché de stock sólo
  /// si la identidad no cambió: si cambió, lo consultado ya no le corresponde.
  void adoptNeed(SupplyNeed need, {bool identityChanged = false}) {
    _needById[need.id] = need;
    _needs = [
      for (final item in _needs)
        if (item.id == need.id) need else item,
    ];
    if (identityChanged) {
      _snapshots.remove(need.id);
      _rankings.remove(need.id);
    }
    notifyListeners();
  }

  /// Limpia el error visible sin tocar nada de lo trabajado.
  void dismissFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  /// Recorta por **bytes**, no por caracteres: el límite del RPC es de bytes y
  /// una medida con «ó» o «×» ocupa dos.
  static String _boundedQuery(String value) {
    final trimmed = value.trim();
    final bytes = utf8.encode(trimmed);
    if (bytes.length <= 240) return trimmed;
    return utf8.decode(bytes.sublist(0, 240), allowMalformed: true).trim();
  }

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    _failure = null;
    notifyListeners();
    try {
      await body();
    } catch (error) {
      // El mensaje se muestra junto a la superficie que falló; el recorrido
      // sigue en pie y nada de lo cargado antes se pierde.
      _failure = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
