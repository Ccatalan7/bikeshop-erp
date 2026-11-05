import 'dart:async';

import 'package:flutter/material.dart';

import '../services/form_drafts/form_draft_store.dart';
import '../services/network/operation_identity.dart';
import 'draft_restored_pill.dart';

/// El salvado automático de un formulario: lo que la persona escribe se guarda
/// en el equipo mientras escribe, y si el formulario se cierra sin guardar (se
/// fue la luz, se cayó la app, se tocó «atrás», se cortó internet) vuelve
/// solo al abrirlo otra vez, con «Deshacer» a mano.
///
/// Envuelve el formulario sin tocar sus campos: encuentra los de texto y los
/// selectores de texto por su etiqueta (`labelText`). Reglas, para que
/// recuperar nunca deje algo donde no va:
/// - sólo campos con etiqueta **propia y única**: dos «Precio» (las líneas de
///   un documento) no se distinguen con seguridad y no se guardan; un
///   buscador (sólo pista, sin etiqueta) tampoco;
/// - sólo lo que la persona **tecleó** (el campo tuvo el foco): lo que el
///   formulario llena solo no es suyo;
/// - nunca una contraseña ni un campo de sólo lectura, ni lo que está dentro
///   de un [FormDraftSkip];
/// - se guarda el valor de antes y el de después: al recuperar, un campo que
///   otra persona cambió entretanto no se pisa, se deja y se avisa. Por eso
///   sirve también al editar un registro.
///
/// El formulario hace dos cosas:
/// - [ready] en `true` cuando terminó de cargar el registro: lo que muestra en
///   ese momento es «lo que había»;
/// - `markSaved()` (por una `GlobalKey<FormDraftScopeState>`) apenas guarda,
///   antes de salir; o [FormDraftScope.forget] si guardó después de cerrarse.
///   Si no, al abrir un formulario nuevo ofrecería otra vez lo ya guardado.
///
/// Contrato: docs/architecture/write-durability-contract.md.
class FormDraftScope extends StatefulWidget {
  const FormDraftScope({
    super.key,
    required this.draftKey,
    required this.child,
    this.ready = true,
    this.store,
    this.currentUserId,
    this.checkEvery = const Duration(seconds: 1),
    this.bannerAtBottom = false,
  });

  /// El formulario y su registro: `cliente:nuevo`, `cliente:<id>`…
  final String draftKey;
  final bool ready;
  final Widget child;
  final FormDraftStore? store;
  final String? Function()? currentUserId;
  final Duration checkEvery;

  /// El aviso «Recuperamos lo que escribiste» va al pie del formulario en vez
  /// de arriba. En un diálogo con su barra de botones abajo (la ficha de la
  /// bici), arriba tapaba el título del paso.
  final bool bannerAtBottom;

  /// Borra el borrador de [draftKey] de quien está conectado, aunque el
  /// formulario ya no esté en pantalla (guardó después de que la persona
  /// salió).
  ///
  /// También suelta la identidad del registro nuevo que nacía en ese borrador
  /// ([RecordIdentities]): el próximo registro es otro.
  static Future<void> forget(String draftKey) async {
    unawaited(RecordIdentities.release(draftKey));
    final user = FormDrafts.currentUserId();
    if (user == null || user.isEmpty) return;
    await FormDrafts.store.remove(user, draftKey);
  }

  @override
  State<FormDraftScope> createState() => FormDraftScopeState();
}

/// Lo de adentro no va al borrador: las líneas de un documento (que se
/// guardan por su propio camino y no se identifican por su etiqueta), o
/// cualquier parte que el formulario llene solo.
class FormDraftSkip extends StatelessWidget {
  const FormDraftSkip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Un campo del formulario, como lo encuentra el borrador.
abstract class _DraftField {
  String get value;
  bool get hasFocus;

  /// Lo pone como si la persona lo hubiera escrito (avisa a quien escucha).
  /// `false` si no se pudo.
  bool apply(String value);
}

class _TextDraftField implements _DraftField {
  _TextDraftField(this.editable);

  final EditableText editable;

  @override
  String get value => editable.controller.text;

  @override
  bool get hasFocus => editable.focusNode.hasFocus;

  @override
  bool apply(String value) {
    editable.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    // El mismo aviso que manda un teclado: el formulario y su `FormField` se
    // enteran igual que si se hubiera escrito.
    editable.onChanged?.call(value);
    return true;
  }
}

class _ChoiceDraftField implements _DraftField {
  _ChoiceDraftField(this.field, this.state, this.options);

  final DropdownButtonFormField<String> field;
  final FormFieldState<String> state;
  final Set<String> options;

  static const String none = '\u0000';

  @override
  String get value => state.value ?? none;

  @override
  bool get hasFocus => false;

  @override
  bool apply(String value) {
    final next = value == none ? null : value;
    if (next != null && !options.contains(next)) return false;
    state.didChange(next);
    field.onChanged?.call(next);
    return true;
  }
}

class _Restored {
  const _Restored({
    required this.savedAt,
    required this.previous,
    required this.untouched,
  });

  final DateTime savedAt;

  /// Lo que tenía cada campo antes de recuperarlo, para «Deshacer».
  final Map<String, String> previous;

  /// Campos que otra persona cambió entretanto: no se tocaron.
  final List<String> untouched;

  _Restored merge(
          Map<String, String> morePrevious, List<String> moreUntouched) =>
      _Restored(
        savedAt: savedAt,
        previous: {...morePrevious, ...previous},
        untouched: [...untouched, ...moreUntouched],
      );
}

class FormDraftScopeState extends State<FormDraftScope>
    with WidgetsBindingObserver {
  FormDraftStore get _store => widget.store ?? FormDrafts.store;

  Map<String, String>? _baseline;
  String? _userId;

  /// Lo del borrador cuyo campo no estaba en pantalla al abrir (una pestaña
  /// o sección cerrada): se pone cuando aparece, si el campo sigue con lo
  /// que tenía.
  final Map<String, FormDraftChange> _waiting = {};

  /// Los campos de texto que la persona tocó. Sólo eso es «lo que escribió».
  final Set<String> _touched = {};

  Map<String, FormDraftChange>? _written;
  DateTime? _draftSavedAt;

  /// Cómo quedó todo justo después de recuperar: apenas la persona sigue
  /// escribiendo, aceptó lo recuperado y el aviso se va.
  Map<String, FormDraftChange>? _afterRestore;
  _Restored? _banner;
  Timer? _check;
  Timer? _bannerTimer;
  int _generation = 0;

  /// Si hay algo escrito que todavía no se guarda.
  bool get hasUnsavedChanges => _currentChanges().isNotEmpty;

  /// Cuándo se guardó el borrador que se recuperó al abrir.
  DateTime? get restoredSavedAt => _draftSavedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChange);
    if (widget.ready) _settle();
  }

  @override
  void didUpdateWidget(FormDraftScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draftKey != widget.draftKey ||
        (!oldWidget.ready && widget.ready)) {
      // Otro registro, o volvió a cargar el mismo: lo que muestra ahora es
      // «lo que había», y lo escrito que siga en el borrador vuelve encima.
      _persist(apply: false);
      _reset();
      if (widget.ready) _settle();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Antes de que el sistema congele o cierre la app.
    if (state != AppLifecycleState.resumed) _persist(apply: false);
  }

  @override
  void deactivate() {
    // Salir del formulario sin guardar deja el borrador al día. Los campos
    // siguen montados en este momento; no se escribe en ellos.
    _persist(apply: false);
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_onFocusChange);
    _check?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  /// El formulario guardó: lo que muestra ahora es lo que hay.
  ///
  /// La identidad del registro nuevo de este borrador se suelta aquí, igual
  /// al descartar y al deshacer un borrador recuperado: si la persona empieza
  /// de cero, lo que escriba es otro registro.
  void markSaved() {
    unawaited(RecordIdentities.release(widget.draftKey));
    final user = _userId;
    _waiting.clear();
    _touched.clear();
    _written = null;
    _afterRestore = null;
    _hideBanner();
    if (mounted) {
      _baseline = _readFields().map((key, field) => MapEntry(key, field.value));
    }
    if (user != null) unawaited(_store.remove(user, widget.draftKey));
  }

  /// La persona decidió no guardar lo que escribió.
  void discard() => markSaved();

  void _reset() {
    _generation += 1;
    _check?.cancel();
    _check = null;
    _baseline = null;
    _waiting.clear();
    _touched.clear();
    _written = null;
    _afterRestore = null;
    _hideBanner();
  }

  void _settle() {
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _generation || !widget.ready) return;
      final user = (widget.currentUserId ?? FormDrafts.currentUserId)();
      if (user == null || user.isEmpty) return;
      _userId = user;
      _baseline = _readFields().map((key, field) => MapEntry(key, field.value));
      final draft = await _store.read(user, widget.draftKey);
      if (!mounted || generation != _generation) return;
      if (draft != null) {
        // Lo que hay guardado: si al final no queda nada que recuperar, la
        // próxima revisión lo borra.
        _written = draft.changes;
        _draftSavedAt = draft.savedAt;
        _waiting.addAll(draft.changes);
        _applyWaiting();
      }
      _check = Timer.periodic(widget.checkEvery, (_) => _persist());
    });
  }

  /// Pone lo del borrador en los campos que están en pantalla y que la
  /// persona no tocó, si todavía tienen lo que tenían al escribirse.
  void _applyWaiting() {
    if (_waiting.isEmpty || !mounted) return;
    final baseline = _baseline;
    if (baseline == null) return;
    final fields = _readFields();
    final previous = <String, String>{};
    final untouched = <String>[];
    for (final key in _waiting.keys.toList()) {
      final field = fields[key];
      if (field == null) continue;
      if (_touched.contains(key) || field.hasFocus) {
        // Ya está escribiendo ahí: manda lo nuevo.
        _waiting.remove(key);
        continue;
      }
      final change = _waiting.remove(key)!;
      final now = field.value;
      // Lo que mostraba al aparecer es su «lo que había».
      baseline.putIfAbsent(key, () => now);
      if (now == change.after) continue;
      if (now != change.before) {
        untouched.add(key);
        continue;
      }
      if (field.apply(change.after)) {
        previous[key] = now;
        _touched.add(key);
      }
    }
    if (previous.isEmpty && untouched.isEmpty) return;
    final shown = _banner;
    _showBanner(
      shown == null
          ? _Restored(
              savedAt: _draftSavedAt ?? DateTime.now(),
              previous: previous,
              untouched: untouched,
            )
          : shown.merge(previous, untouched),
    );
    _afterRestore = _currentChanges();
  }

  void _undo() {
    final restored = _banner;
    if (restored == null) return;
    final fields = _readFields();
    for (final entry in restored.previous.entries) {
      fields[entry.key]?.apply(entry.value);
    }
    discard();
  }

  void _onFocusChange() {
    // Entrar o salir de un campo es el momento natural de dejarlo guardado.
    // El foco puede cambiar en plena construcción: se hace a continuación.
    if (_baseline == null) return;
    scheduleMicrotask(() {
      if (mounted) _persist();
    });
  }

  /// Lo que la persona cambió respecto de lo que había al abrir, más lo del
  /// borrador anterior que espera su campo.
  Map<String, FormDraftChange> _currentChanges() {
    final baseline = _baseline;
    if (baseline == null || !mounted) return const {};
    final fields = _readFields();
    for (final entry in fields.entries) {
      // Un campo que aparece después (otra pestaña) trae su «lo que había»
      // antes de que se pueda escribir en él.
      baseline.putIfAbsent(entry.key, () => entry.value.value);
      if (entry.value.hasFocus) _touched.add(entry.key);
    }
    final changes = <String, FormDraftChange>{..._waiting};
    for (final entry in fields.entries) {
      final field = entry.value;
      if (field is _TextDraftField && !_touched.contains(entry.key)) continue;
      final before = baseline[entry.key]!;
      final now = field.value;
      if (now != before) {
        changes[entry.key] = FormDraftChange(before: before, after: now);
      }
    }
    return changes;
  }

  void _persist({bool apply = true}) {
    final user = _userId;
    if (user == null || _baseline == null || !mounted) return;
    if (apply) _applyWaiting();
    final changes = _currentChanges();
    final restored = _afterRestore;
    if (_banner != null &&
        restored != null &&
        !_sameChanges(changes, restored)) {
      // Siguió escribiendo encima de lo recuperado: ya no hay qué deshacer.
      _afterRestore = null;
      _hideBanner();
    }
    if (_sameChanges(changes, _written)) return;
    _written = changes;
    if (changes.isEmpty) {
      unawaited(_store.remove(user, widget.draftKey));
      return;
    }
    unawaited(_store.write(FormDraft(
      key: widget.draftKey,
      userId: user,
      savedAt: DateTime.now(),
      changes: changes,
    )));
  }

  static bool _sameChanges(
    Map<String, FormDraftChange> a,
    Map<String, FormDraftChange>? b,
  ) {
    if (b == null) return a.isEmpty;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Los campos del formulario por su etiqueta: sólo los de etiqueta propia y
  /// única (ver las reglas arriba).
  Map<String, _DraftField> _readFields() {
    final candidates = <(String, _DraftField)>[];
    void add(String? label, _DraftField field) {
      final name = label?.trim();
      if (name == null || name.isEmpty) return;
      candidates.add((name, field));
    }

    void walk(Element element, String? label) {
      final widget = element.widget;
      // Otro borrador manda adentro; lo marcado como fuera, fuera.
      if (widget is FormDraftScope || widget is FormDraftSkip) return;
      var next = label;
      if (widget is InputDecorator) next = _labelOf(widget.decoration);
      if (widget is EditableText) {
        if (!widget.obscureText && !widget.readOnly) {
          add(next, _TextDraftField(widget));
        }
        return;
      }
      if (widget is DropdownButtonFormField<String> &&
          element is StatefulElement &&
          element.state is FormFieldState<String>) {
        add(
          _labelOf(widget.decoration),
          _ChoiceDraftField(
            widget,
            element.state as FormFieldState<String>,
            _optionsUnder(element),
          ),
        );
        return;
      }
      element.visitChildren((child) => walk(child, next));
    }

    if (!mounted) return const {};
    (context as Element).visitChildren((child) => walk(child, null));
    final counts = <String, int>{};
    for (final (name, _) in candidates) {
      counts.update(name, (n) => n + 1, ifAbsent: () => 1);
    }
    return {
      for (final (name, field) in candidates)
        if (counts[name] == 1) name: field,
    };
  }

  static String? _labelOf(InputDecoration decoration) {
    final text = decoration.labelText ??
        switch (decoration.label) {
          final Text label => label.data,
          _ => null,
        };
    return text == null || text.trim().isEmpty ? null : text;
  }

  static Set<String> _optionsUnder(Element element) {
    final options = <String>{};
    void walk(Element child) {
      final widget = child.widget;
      if (widget is DropdownButton<String>) {
        for (final item in widget.items ?? const <DropdownMenuItem<String>>[]) {
          final value = item.value;
          if (value != null) options.add(value);
        }
        return;
      }
      child.visitChildren(walk);
    }

    element.visitChildren(walk);
    return options;
  }

  void _showBanner(_Restored restored) {
    _bannerTimer?.cancel();
    setState(() => _banner = restored);
    // Queda hasta que la persona siga escribiendo o lo cierre; un minuto
    // como máximo, para que no se quede pegado sobre el formulario.
    _bannerTimer = Timer(const Duration(minutes: 1), _hideBanner);
  }

  void _hideBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    if (_banner == null) return;
    if (mounted) {
      setState(() => _banner = null);
    } else {
      _banner = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    // En el teléfono, arriba taparía «volver» y el título: va al pie, sobre
    // el aviso de conexión.
    final compact = MediaQuery.sizeOf(context).width < 600;
    final atBottom = compact || widget.bannerAtBottom;
    // Dentro de un diálogo el pie del formulario ya está sobre sus botones y
    // lejos del aviso de conexión, que vive en la pantalla.
    final bottom = widget.bannerAtBottom
        ? 12.0
        : MediaQuery.paddingOf(context).bottom + 76;
    // `passthrough`: el formulario recibe exactamente el espacio que tenía sin
    // el borrador; el aviso flota encima.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned(
          top: atBottom ? null : 12,
          bottom: atBottom ? bottom : null,
          left: 16,
          right: 16,
          child: IgnorePointer(
            ignoring: banner == null,
            child: Align(
              alignment:
                  atBottom ? Alignment.bottomCenter : Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: banner == null
                    ? const SizedBox.shrink(key: ValueKey('draft-banner-none'))
                    : _RestoredBanner(
                        key: const ValueKey('draft-banner'),
                        restored: banner,
                        onUndo: _undo,
                        onClose: _hideBanner,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RestoredBanner extends StatelessWidget {
  const _RestoredBanner({
    super.key,
    required this.restored,
    required this.onUndo,
    required this.onClose,
  });

  final _Restored restored;
  final VoidCallback onUndo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final untouched = restored.untouched;
    return DraftRestoredPill(
      title: restored.previous.isEmpty
          ? 'Tenías cambios sin guardar'
          : 'Recuperamos lo que escribiste',
      savedAt: restored.savedAt,
      note: untouched.isEmpty
          ? null
          : 'no tocamos ${untouched.join(', ')}: '
              '${untouched.length == 1 ? 'cambió' : 'cambiaron'} mientras tanto',
      onUndo: restored.previous.isNotEmpty ? onUndo : null,
      onClose: onClose,
    );
  }
}
