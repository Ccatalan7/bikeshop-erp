import 'dart:convert';
import 'dart:ui' show Tristate;
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

/// Debug-only input channel so an agent can drive the app **without touching
/// the owner's cursor**.
///
/// The previous path posted real `CGEvent`s to the window server, which moves
/// the actual pointer and steals focus — so the owner and the agent fought over
/// one mouse, and either could invalidate the other's action mid-gesture.
///
/// These extensions instead hand synthetic [PointerEvent]s straight to
/// [GestureBinding], which is the same thing `WidgetController` does in widget
/// tests. Consequences:
///
/// - the system cursor never moves, so the owner keeps using the Mac normally;
/// - the window does not need focus, or even to be visible;
/// - coordinates are deterministic instead of racing window position;
/// - an installed build can no longer steal the click, because the event is
///   delivered inside this process rather than aimed at a screen coordinate.
///
/// The trade-off is honest: this bypasses the OS event path, so it cannot catch
/// a defect that lives *in* that path (a window that never receives events at
/// all). For that case the CGEvent driver stays available in `app_control.sh`.
///
/// Never registered outside debug: [kDebugMode] gates the whole thing, so no
/// release build exposes an input channel.
void registerAgentInputExtensions() {
  if (!kDebugMode) return;
  if (_registered) return;
  _registered = true;

  developer.registerExtension('ext.vinabike.input.info', (_, __) async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    return _ok({
      'devicePixelRatio': view?.devicePixelRatio,
      'logicalWidth':
          view == null ? null : view.physicalSize.width / view.devicePixelRatio,
      'logicalHeight': view == null
          ? null
          : view.physicalSize.height / view.devicePixelRatio,
      'physicalWidth': view?.physicalSize.width,
      'physicalHeight': view?.physicalSize.height,
    });
  });

  developer.registerExtension('ext.vinabike.input.tap', (_, params) async {
    final at = _offset(params);
    if (at == null) return _err('x and y are required');
    await _tap(at);
    return _ok({
      'tapped': [at.dx, at.dy]
    });
  });

  // ── Tocar por identidad, no por píxel ─────────────────────────────────────
  //
  // Clicar por coordenada es frágil por una razón concreta: la captura y el
  // clic viven en espacios distintos. El frame puede venir a 1360x757 o a
  // 3024x1632 según el devicePixelRatio y el tamaño de ventana del momento, así
  // que toda coordenada leída de una captura anterior queda corrida en cuanto
  // algo cambia de escala. Reiniciar la app basta para invalidarlas todas.
  //
  // `find` resuelve el objetivo por su ValueKey o por su etiqueta de semántica
  // y devuelve su rectángulo REAL en coordenadas lógicas. `tapOn` hace las dos
  // cosas de una: ubica y toca, y responde qué tocó — así el agente no pierde
  // conciencia de dónde cayó el evento.
  // ── Leer la pantalla como la lee un lector de pantalla ────────────────────
  //
  // Una captura dice cómo se ve; no dice qué ESTÁ. Si un botón está
  // deshabilitado, si una fila está seleccionada o si un campo tiene foco son
  // hechos que mirando píxeles hay que deducir del color — y deducir es
  // exactamente lo que hace que un agente afirme cosas falsas.
  //
  // El árbol de semántica es la fuente estructurada: es lo que Flutter le
  // entrega a VoiceOver, así que refleja la app como la recibe una persona que
  // no la está mirando. Sale en texto, así que cuesta una fracción de lo que
  // cuesta una imagen.
  developer.registerExtension('ext.vinabike.input.tree', (_, params) async {
    final binding = WidgetsBinding.instance;
    // La semántica no se compila si nadie la pidió: hay que encenderla y que
    // corra un frame para que el árbol exista.
    final handle = binding.ensureSemantics();
    try {
      // Dos frames, no uno. El primero tras encender la semántica publica el
      // marco —rail, pestañas, toolbar— y deja el contenido del workspace a
      // medias: con un solo frame, Nóminas devolvía el shell y ni una fila.
      // Un árbol incompleto es peor que ninguno, porque se lee igual que una
      // pantalla donde el control no existe.
      final forced = await _pumpFrames(frames: 2);
      final root = binding.rootElement?.renderObject?.debugSemantics;
      if (root == null) return _err('sin árbol de semántica');
      final filter = params['filter']?.trim().toLowerCase();
      final lines = <String>[];
      _describeSemantics(root, 0, lines, filter);
      return _ok({'lines': lines, 'forcedFrame': forced});
    } finally {
      handle.dispose();
    }
  });

  developer.registerExtension('ext.vinabike.input.find', (_, params) async {
    // Sobre layout vigente: un objetivo se busca en el árbol de AHORA, no en el
    // del último frame que el engine tuvo ganas de entregar.
    await _pumpFrames(frames: _settleFrames);
    final matches = locateAgentInputTargetsForTesting(
      params['key'],
      params['label'],
    );
    if (matches.isEmpty) return _err('sin coincidencias');
    return _ok({'matches': matches});
  });

  developer.registerExtension('ext.vinabike.input.tapOn', (_, params) async {
    await _pumpFrames(frames: _settleFrames);
    final result = await tapAgentInputTargetForTesting(
      params,
    );
    if (result['ok'] != true) {
      return _err(result['error']?.toString() ?? 'objetivo no tocable');
    }
    // Y después del toque, para que su consecuencia exista cuando el agente
    // pregunte por ella en la llamada siguiente.
    await _pumpFrames(frames: _settleFrames);
    return _ok({'tapped': result['tapped']});
  });

  developer.registerExtension('ext.vinabike.input.scroll', (_, params) async {
    final at = _offset(params);
    if (at == null) return _err('x and y are required');
    final dy = double.tryParse(params['dy'] ?? '') ?? 0;
    final dx = double.tryParse(params['dx'] ?? '') ?? 0;
    _dispatch(PointerScrollEvent(
      position: at,
      scrollDelta: Offset(dx, dy),
      viewId: _viewId,
    ));
    return _ok({
      'scrolled': [dx, dy]
    });
  });

  developer.registerExtension('ext.vinabike.input.drag', (_, params) async {
    final from = _offset(params);
    final toX = double.tryParse(params['x2'] ?? '');
    final toY = double.tryParse(params['y2'] ?? '');
    if (from == null || toX == null || toY == null) {
      return _err('x, y, x2 and y2 are required');
    }
    await _drag(from, Offset(toX, toY),
        steps: int.tryParse(params['steps'] ?? '') ?? 12);
    return _ok({
      'dragged': [from.dx, from.dy, toX, toY]
    });
  });
}

bool _registered = false;

/// Frames que se corren para dar por asentada una interacción: ~320 ms, que
/// cubre las transiciones del shell (`PayrollTokens.base` es 200 ms y la de
/// panel 380 ms se ve empezada, que es lo que hace falta para ubicar).
const int _settleFrames = 20;
int _pointer = 7000;

int get _viewId =>
    WidgetsBinding.instance.platformDispatcher.implicitView?.viewId ?? 0;

Offset? _offset(Map<String, String> params) {
  final x = double.tryParse(params['x'] ?? '');
  final y = double.tryParse(params['y'] ?? '');
  if (x == null || y == null) return null;
  return Offset(x, y);
}

/// Aplana el árbol de semántica a líneas indentadas.
///
/// Sólo se emite un nodo que aporte algo —etiqueta, valor o un flag de
/// interacción— porque el árbol crudo está lleno de nodos de agrupación que no
/// dicen nada y sólo gastarían contexto. `filter` deja pasar únicamente las
/// ramas cuyo texto contiene lo buscado, para poder mirar una sola zona.
/// Corre [frames] frames y devuelve `true` si hubo que dibujarlos a mano.
///
/// **Por qué existe.** El engine sólo entrega frames mientras la app está
/// visible: si el ciclo de vida cae a `hidden` —la ventana tapada por otra, que
/// es el estado normal cuando el dueño trabaja mientras el agente verifica—
/// `scheduleFrame()` pasa a ser un no-op y la app queda **congelada, pero
/// viva**. Dos consecuencias que costaron una ronda cada una el 31/07:
///
/// - `read` esperaba `endOfFrame` sin límite y no volvía nunca, mientras `shot`
///   seguía respondiendo. `_flutter.screenshot` rasteriza el árbol de capas que
///   ya existe, así que no necesita frame nuevo: la app parecía muerta y no lo
///   estaba, y parecía viva y no respondía.
/// - un `tap` marcaba el estado nuevo pero sin frame no había layout nuevo, así
///   que el control que ese toque acababa de abrir todavía no existía para el
///   `find` siguiente. Se leyó como «el menú no se expande».
///
/// Dibujar el frame a mano es lo mismo que hace el binding de tests, y
/// `drawFrame` incluye el `flushSemantics`. El timestamp **avanza** en cada
/// vuelta: sin eso las animaciones no corren y un panel plegado se queda a
/// medio abrir para siempre.
Future<bool> _pumpFrames({int frames = 2}) async {
  final binding = WidgetsBinding.instance;
  if (binding.framesEnabled) {
    var arrived = true;
    for (var i = 0; i < frames && arrived; i++) {
      await binding.endOfFrame.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          arrived = false;
        },
      );
    }
    if (arrived) return false;
  }
  // Sólo desde reposo: entrar a la mitad de un frame ajeno sí rompería.
  if (binding.schedulerPhase != SchedulerPhase.idle) return true;
  var stamp = binding.currentSystemFrameTimeStamp;
  for (var i = 0; i < frames; i++) {
    stamp += const Duration(milliseconds: 16);
    binding.handleBeginFrame(stamp);
    binding.handleDrawFrame();
  }
  return true;
}

void _describeSemantics(
  SemanticsNode node,
  int depth,
  List<String> out,
  String? filter,
) {
  final data = node.getSemanticsData();
  final label = data.label.trim();
  final value = data.value.trim();

  // En 3.38 los flags con estado son `Tristate`: `null` significa que el nodo
  // no declara ese estado, y es distinto de declararlo en falso. Un botón sin
  // estado de habilitación no es un botón deshabilitado.
  final f = data.flagsCollection;
  final flags = <String>[
    if (f.isButton) 'botón',
    if (f.isTextField) 'campo',
    if (f.isHeader) 'encabezado',
    if (f.isEnabled == Tristate.isFalse) 'DESHABILITADO',
    if (f.isSelected == Tristate.isTrue) 'seleccionado',
    if (f.isFocused == Tristate.isTrue) 'con foco',
    if (f.isExpanded != Tristate.none)
      (f.isExpanded == Tristate.isTrue ? 'abierto' : 'cerrado'),
  ];

  final interesting = label.isNotEmpty || value.isNotEmpty || flags.isNotEmpty;
  if (interesting) {
    final rect = node.rect;
    final where = '${rect.width.toStringAsFixed(0)}x'
        '${rect.height.toStringAsFixed(0)}';
    final parts = <String>[
      if (label.isNotEmpty) label,
      if (value.isNotEmpty) '= $value',
      if (flags.isNotEmpty) '[${flags.join(' ')}]',
      where,
    ];
    final line = '${'  ' * depth}${parts.join(' · ')}';
    if (filter == null ||
        filter.isEmpty ||
        line.toLowerCase().contains(filter)) {
      out.add(line);
    }
  }

  node.visitChildren((child) {
    _describeSemantics(child, interesting ? depth + 1 : depth, out, filter);
    return true;
  });
}

class _LocatedAgentInputTarget {
  const _LocatedAgentInputTarget({
    required this.element,
    required this.rect,
    required this.tapPoint,
    required this.key,
    required this.label,
    required this.widgetName,
  });

  final Element element;
  final Rect rect;
  final Offset tapPoint;
  final String? key;
  final String? label;
  final String widgetName;

  Map<String, Object?> toJson() => {
        'key': key,
        'label': label,
        'widget': widgetName,
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
        'centerX': tapPoint.dx,
        'centerY': tapPoint.dy,
      };
}

/// Returns only live targets whose chosen point is inside the Flutter viewport
/// and whose render branch wins hit testing at that point.
@visibleForTesting
List<Map<String, Object?>> locateAgentInputTargetsForTesting(
  String? key,
  String? label,
) =>
    _locateAgentInputTargets(key, label)
        .map((target) => target.toJson())
        .toList(growable: false);

/// Resolves and taps one live target. The injected dispatcher lets tests prove
/// that every invalid or ambiguous request produces zero pointer events.
@visibleForTesting
Future<Map<String, Object?>> tapAgentInputTargetForTesting(
  Map<String, String> params, {
  Future<void> Function(Offset)? tap,
}) async {
  final matches = _locateAgentInputTargets(params['key'], params['label']);
  if (matches.isEmpty) {
    return const {'ok': false, 'error': 'sin coincidencias: nada que tocar'};
  }

  final rawIndex = params['index'];
  final int index;
  if (rawIndex == null || rawIndex.trim().isEmpty) {
    if (matches.length > 1) {
      return {
        'ok': false,
        'error': '${matches.length} coincidencias; pasa index=N. '
            '${matches.map((match) => match.label ?? match.key).toList()}',
      };
    }
    index = 0;
  } else {
    final parsed = int.tryParse(rawIndex);
    if (parsed == null) {
      return {'ok': false, 'error': 'index debe ser un entero'};
    }
    index = parsed;
  }
  if (index < 0 || index >= matches.length) {
    return {
      'ok': false,
      'error': 'index $index fuera de rango (${matches.length})',
    };
  }

  final target = matches[index];
  await (tap ?? _tap)(target.tapPoint);
  return {'ok': true, 'tapped': target.toJson()};
}

/// Recorre el árbol vivo buscando por `ValueKey<String>` o por etiqueta de
/// semántica. Un objetivo se devuelve sólo si el punto que se tocará es
/// visible, habilitado y pertenece a su rama en el hit test vivo.
List<_LocatedAgentInputTarget> _locateAgentInputTargets(
  String? key,
  String? label,
) {
  final wanted = key?.trim();
  final wantedLabel = label?.trim().toLowerCase();
  if ((wanted == null || wanted.isEmpty) &&
      (wantedLabel == null || wantedLabel.isEmpty)) {
    return const [];
  }
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null || view.devicePixelRatio <= 0) return const [];
  final viewport = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  final found = <_LocatedAgentInputTarget>[];
  void visit(Element element) {
    final widget = element.widget;
    var hit = false;
    String? matchedLabel;

    if (wanted != null && wanted.isNotEmpty) {
      final widgetKey = widget.key;
      if (widgetKey is ValueKey<String> && widgetKey.value == wanted) {
        hit = true;
      }
    }
    if (!hit && wantedLabel != null && wantedLabel.isNotEmpty) {
      if (widget is Semantics) {
        final semanticLabel = widget.properties.label;
        if (semanticLabel != null &&
            semanticLabel.toLowerCase().contains(wantedLabel)) {
          hit = true;
          matchedLabel = semanticLabel;
        }
      } else if (widget is Text) {
        final text = widget.data ?? widget.textSpan?.toPlainText();
        if (text != null && text.toLowerCase().contains(wantedLabel)) {
          hit = true;
          matchedLabel = text;
        }
      }
    }

    if (hit) {
      final object = element.renderObject;
      if (object is RenderBox && object.hasSize && object.attached) {
        final size = object.size;
        if (size.width > 0 && size.height > 0) {
          final origin = object.localToGlobal(Offset.zero);
          final bottomRight =
              object.localToGlobal(size.bottomRight(Offset.zero));
          final rect = Rect.fromPoints(origin, bottomRight);
          final visibleRect = rect.intersect(viewport);
          if (!visibleRect.isEmpty &&
              visibleRect.center.dx.isFinite &&
              visibleRect.center.dy.isFinite &&
              !_isAgentInputBlocked(element) &&
              _hitTestBelongsTo(object, visibleRect.center, view.viewId)) {
            final candidate = _LocatedAgentInputTarget(
              element: element,
              rect: rect,
              tapPoint: visibleRect.center,
              key: widget.key is ValueKey<String>
                  ? (widget.key! as ValueKey<String>).value
                  : null,
              label: matchedLabel,
              widgetName: widget.runtimeType.toString(),
            );
            _addDeduplicatedAgentTarget(found, candidate);
          }
        }
      }
    }
    element.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return found;
}

bool _isAgentInputBlocked(Element element) {
  var blocked = _widgetBlocksAgentInput(element.widget);
  element.visitAncestorElements((ancestor) {
    blocked = blocked || _widgetBlocksAgentInput(ancestor.widget);
    return !blocked;
  });
  return blocked;
}

bool _widgetBlocksAgentInput(Widget widget) {
  if (widget is Offstage && widget.offstage) return true;
  if (widget is IgnorePointer && widget.ignoring) return true;
  if (widget is AbsorbPointer && widget.absorbing) return true;
  if (widget is Semantics && widget.properties.enabled == false) return true;
  if (widget is ButtonStyleButton && !widget.enabled) return true;
  if (widget is IconButton && widget.onPressed == null) return true;
  return false;
}

bool _hitTestBelongsTo(RenderObject candidate, Offset point, int viewId) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, point, viewId);
  for (final entry in result.path) {
    final target = entry.target;
    if (target is! RenderObject) continue;
    RenderObject? current = target;
    while (current != null) {
      if (identical(current, candidate)) return true;
      final parent = current.parent;
      current = parent is RenderObject ? parent : null;
    }
  }
  return false;
}

void _addDeduplicatedAgentTarget(
  List<_LocatedAgentInputTarget> found,
  _LocatedAgentInputTarget candidate,
) {
  for (var index = 0; index < found.length; index += 1) {
    final existing = found[index];
    if (!_elementsShareBranch(existing.element, candidate.element)) continue;
    if (existing.element.widget is Semantics) return;
    if (candidate.element.widget is Semantics) {
      found[index] = candidate;
      return;
    }
  }
  found.add(candidate);
}

bool _elementsShareBranch(Element left, Element right) =>
    _isElementAncestor(left, right) || _isElementAncestor(right, left);

bool _isElementAncestor(Element possibleAncestor, Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    found = identical(ancestor, possibleAncestor);
    return !found;
  });
  return found;
}

void _dispatch(PointerEvent event) =>
    GestureBinding.instance.handlePointerEvent(event);

Future<void> _tap(Offset at) async {
  final id = _pointer++;
  // A hover first, so widgets that only arm on enter (menus, hover rows) see
  // the pointer arrive instead of a down event materialising out of nowhere.
  _dispatch(PointerHoverEvent(position: at, viewId: _viewId));
  _dispatch(PointerDownEvent(pointer: id, position: at, viewId: _viewId));
  await Future<void>.delayed(const Duration(milliseconds: 40));
  _dispatch(PointerUpEvent(pointer: id, position: at, viewId: _viewId));
  // Let the tap settle before the caller screenshots it.
  await Future<void>.delayed(const Duration(milliseconds: 60));
}

Future<void> _drag(Offset from, Offset to, {int steps = 12}) async {
  final id = _pointer++;
  _dispatch(PointerDownEvent(pointer: id, position: from, viewId: _viewId));
  var previous = from;
  for (var i = 1; i <= steps; i++) {
    final at = Offset.lerp(from, to, i / steps)!;
    _dispatch(PointerMoveEvent(
      pointer: id,
      position: at,
      delta: at - previous,
      viewId: _viewId,
    ));
    previous = at;
    await Future<void>.delayed(const Duration(milliseconds: 12));
  }
  _dispatch(PointerUpEvent(pointer: id, position: to, viewId: _viewId));
  await Future<void>.delayed(const Duration(milliseconds: 60));
}

developer.ServiceExtensionResponse _ok(Map<String, Object?> body) =>
    developer.ServiceExtensionResponse.result(
        jsonEncode({'ok': true, ...body}));

developer.ServiceExtensionResponse _err(String message) =>
    developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.invalidParams,
      jsonEncode({'ok': false, 'error': message}),
    );
