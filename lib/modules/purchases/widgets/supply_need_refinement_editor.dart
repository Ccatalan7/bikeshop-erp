import 'package:flutter/material.dart';

import '../../../shared/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../../inventory/services/spec_engine_service.dart';
import '../models/intelligent_purchasing_models.dart';
import 'purchase_visual_language.dart';

/// Qué comando resuelve lo que el operador acaba de escribir.
///
/// **No se le pregunta al operador.** Un trabajador nuevo no sabe si agregar
/// «válvula Presta» precisa o cambia la búsqueda; el sistema sí lo sabe, porque
/// puede ver si la categoría sigue siendo la misma. La clasificación se deduce
/// de lo que cambió y se le muestra como consecuencia antes de guardar.
enum SupplyNeedEditOutcome { none, quantity, precise, replace }

/// Lo que pasaría con el listado ya traído del proveedor si se guarda.
///
/// Se calcula sin red: las filas crudas están en memoria y el calce es
/// determinista. Poder decir «de 19 revisadas, 6 cumplen» **antes** de guardar
/// es lo que evita tener que enseñarle al operador la palabra «refinar».
@immutable
class SupplyNeedEditPreviewRow {
  const SupplyNeedEditPreviewRow({
    required this.supplierName,
    required this.code,
    required this.name,
    required this.isConfirmed,
    this.brand,
    this.priceNet,
  });

  /// De quién es la fila. Un feed puede traer varios proveedores y dos códigos
  /// iguales de proveedores distintos no son el mismo producto.
  final String supplierName;
  final String code;
  final String name;

  /// El proveedor demuestra todos los criterios pedidos. Si no, la fila sigue
  /// en el listado pero **por verificar**: nunca se dibujan iguales.
  final bool isConfirmed;
  final String? brand;
  final double? priceNet;
}

@immutable
class SupplyNeedEditPreview {
  const SupplyNeedEditPreview({
    required this.reviewed,
    required this.confirmed,
    required this.unverified,
    this.rows = const <SupplyNeedEditPreviewRow>[],
  });

  final int reviewed;

  /// **Cuáles**, no sólo cuántas.
  ///
  /// El dueño lo pidió con todas las letras el 2026-08-30: cambiar criterios es
  /// para ver cómo se comportan los resultados, no para leer un contador.
  /// Decir «quedarían 3» sin nombrarlas obliga a guardar para enterarse, que es
  /// justo lo que esta previsualización existe para evitar. Las filas salen del
  /// mismo juicio que el número, así que no pueden divergir.
  final List<SupplyNeedEditPreviewRow> rows;

  /// Filas donde el proveedor dice que **todos** los criterios se cumplen.
  final int confirmed;

  /// Filas que nada contradice pero a las que les falta algún dato. Quedan en
  /// el listado; no cumplen.
  final int unverified;

  /// Lo que queda tras acotar. Se muestra, pero nunca como «cumplen».
  int get matching => confirmed + unverified;

  bool get hasEvidence => reviewed > 0;
}

/// Conserva los criterios que este formulario no puede mostrar.
///
/// **Un criterio que no se ve no deja de existir.** La ficha vigente puede
/// traer campos que el template ya no expone —una categoría reordenada, un
/// campo retirado— y el servidor reemplaza los predicados técnicos con lo que
/// se le mande. Sin arrastrarlos, precisar el tipo de válvula borraría en
/// silencio el tamaño de rueda, que es el mismo defecto que teníamos con la
/// cantidad, un nivel más adentro.
List<SupplyNeedPredicate> carryForwardUnexpressedPredicates({
  required List<SupplyNeedPredicate> drafted,
  required List<SupplyNeedPredicate> current,
  required Set<String> expressibleFields,
}) {
  final result = <SupplyNeedPredicate>[...drafted];
  final present = <String>{for (final item in drafted) item.field};
  for (final carried in current) {
    if (expressibleFields.contains(carried.field)) continue;
    if (present.contains(carried.field)) continue;
    result.add(carried);
  }
  return List<SupplyNeedPredicate>.unmodifiable(result);
}

/// Igualdad semántica entre dos fichas técnicas.
///
/// **Comparar por texto miente con los números.** Un `29` que llegó del JSON
/// como entero vuelve del `TextField` como `29.0`: distinto carácter a
/// carácter, idéntico como medida. Con la comparación textual, abrir el editor
/// y no tocar nada habilitaba «Guardar» y creaba una revisión que no cambiaba
/// nada —consumiendo linaje y dejando el feed del portal como «ficha
/// anterior»— por una diferencia de formato.
///
/// **Pero canonicalizar cada valor a número por separado miente al revés.**
/// `"001"` y `"1"` son dos identificadores textuales distintos, y el registro
/// guarda campos como `spoke_holes`, `valve_length_mm` o `wheel_size` unas
/// veces como número JSON y otras como cadena. Convertir todo lo parseable a
/// número borraría esa diferencia y dejaría pasar una edición real como si no
/// existiera.
///
/// La comparación es **par a par**, y el tipo de cada lado decide la regla:
///
/// | izquierda | derecha | regla |
/// |---|---|---|
/// | número | número | igualdad numérica (`29` = `29.0`) |
/// | número | cadena | se parsea la cadena; sirve para el ida y vuelta JSON → formulario |
/// | cadena | cadena | texto exacto (`"001"` ≠ `"1"`, `700c` ≠ `700C`) |
///
/// Campo, operador, cantidad de valores y su orden tienen que coincidir
/// igual: en `between`, `[2, 5]` no es `[5, 2]`.
bool supplyNeedPredicatesEqual(
  List<SupplyNeedPredicate> left,
  List<SupplyNeedPredicate> right,
) {
  if (left.length != right.length) return false;
  final leftByField = <String, SupplyNeedPredicate>{
    for (final predicate in left) predicate.field: predicate,
  };
  final byField = <String, SupplyNeedPredicate>{
    for (final predicate in right) predicate.field: predicate,
  };
  // **La unicidad tiene que ser simétrica.** Comprobarla sólo en `right`
  // dejaba pasar `left = [a, a]` contra `right = [a, b]`: mismo largo, `right`
  // único, y los dos `a` resolvían al mismo par mientras `b` no se comparaba
  // nunca. Los `constraints` vienen de un arreglo JSON de la base, así que un
  // campo repetido es un dato posible, no una hipótesis.
  if (leftByField.length != left.length) return false;
  if (byField.length != right.length) return false;

  for (final predicate in left) {
    final other = byField[predicate.field];
    if (other == null) return false;
    if (predicate.operator != other.operator) return false;
    if (predicate.values.length != other.values.length) return false;
    for (var index = 0; index < predicate.values.length; index++) {
      if (!_predicateValuesEqual(
        predicate.values[index],
        other.values[index],
      )) {
        return false;
      }
    }
  }
  return true;
}

bool _predicateValuesEqual(Object left, Object right) {
  if (left is num && right is num) {
    return left.toDouble() == right.toDouble();
  }
  if (left is num || right is num) {
    // Un solo lado es número: el otro viene del formulario. Se parsea ESE, y
    // sólo para compararlo con éste — nunca para reescribirlo.
    final number = (left is num ? left : right as num).toDouble();
    final text = left is num ? right : left;
    final parsed = double.tryParse(
      text.toString().trim().replaceAll(',', '.'),
    );
    return parsed != null && parsed == number;
  }
  if (left is bool || right is bool) return left == right;
  return left.toString().trim() == right.toString().trim();
}

/// Editor exclusivo de la ficha técnica de una necesidad abierta.
///
/// La petición original y la cantidad tienen su editor histórico aparte. Esta
/// superficie sólo cambia qué productos cumplen dentro de la categoría ya
/// reconocida y vuelve a evaluar el feed existente sin otra consulta de red.
/// Los campos salen del [SpecTemplate] activo; `refine_supply_need_v1` vuelve a
/// validar el resultado dentro del tenant.
class SupplyNeedRefinementEditor extends StatefulWidget {
  const SupplyNeedRefinementEditor({
    super.key,
    required this.template,
    required this.title,
    required this.categoryLabel,
    required this.criteria,
    required this.busy,
    required this.onSave,
    required this.onCancel,
    this.preciseBlockedReason,
    this.previewFor,
  });

  /// Nulo cuando la categoría no está resuelta: entonces la ficha no se puede
  /// dibujar y la sección queda deshabilitada con su explicación.
  final SpecTemplate? template;

  /// Encabezado con el producto reconocido y su cantidad.
  final String title;
  final String categoryLabel;
  final SupplyNeedCriteria criteria;
  final bool busy;

  /// Por qué no se puede precisar, cuando no se puede.
  final String? preciseBlockedReason;

  /// Cuántas filas ya traídas cumplirían con la ficha propuesta.
  final SupplyNeedEditPreview? Function(List<SupplyNeedPredicate> predicates)?
      previewFor;

  final ValueChanged<List<SupplyNeedPredicate>> onSave;
  final VoidCallback onCancel;

  @override
  State<SupplyNeedRefinementEditor> createState() =>
      _SupplyNeedRefinementEditorState();
}

class _SupplyNeedRefinementEditorState
    extends State<SupplyNeedRefinementEditor> {
  final Map<String, _CriterionDraft> _drafts = <String, _CriterionDraft>{};
  final Map<String, TextEditingController> _valueControllers =
      <String, TextEditingController>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(covariant SupplyNeedRefinementEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template?.id != widget.template?.id ||
        oldWidget.criteria != widget.criteria) {
      _disposeValueControllers();
      _drafts.clear();
      _seed();
    }
  }

  @override
  void dispose() {
    _disposeValueControllers();
    super.dispose();
  }

  void _disposeValueControllers() {
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    _valueControllers.clear();
  }

  void _seed() {
    final template = widget.template;
    if (template == null) return;
    final byField = <String, SupplyNeedPredicate>{
      for (final predicate in widget.criteria.predicates)
        predicate.field: predicate,
    };
    for (final field in template.fields) {
      final definition = field.definition;
      if (definition == null) continue;
      final existing = byField[definition.key];
      final draft = _CriterionDraft(
        operator: existing?.operator ?? _defaultOperator(definition.dataType),
        values: List<Object>.from(existing?.values ?? const <Object>[]),
      );
      _drafts[definition.key] = draft;
      _syncTextControllers(definition, draft);
    }
  }

  String _defaultOperator(String dataType) =>
      dataType == 'text' ? 'contains' : 'eq';

  String _controllerKey(String field, int index) => '$field:$index';

  TextEditingController _controller(String field, int index) {
    return _valueControllers.putIfAbsent(
      _controllerKey(field, index),
      TextEditingController.new,
    );
  }

  void _syncTextControllers(SpecDefinition definition, _CriterionDraft draft) {
    if (!_isFreeValue(definition.dataType)) return;
    final count = draft.operator == 'between' ? 2 : 1;
    for (var index = 0; index < count; index += 1) {
      _controller(definition.key, index).text =
          index < draft.values.length ? _numberOrText(draft.values[index]) : '';
    }
  }

  Map<String, dynamic> get _currentValues {
    final template = widget.template;
    if (template == null) return <String, dynamic>{};
    final values = <String, dynamic>{};
    for (final field in template.fields) {
      final definition = field.definition;
      if (definition == null) continue;
      final draft = _drafts[definition.key];
      if (draft == null) continue;
      final current = _draftValues(definition, draft, tolerateInvalid: true);
      if (current.isEmpty) continue;
      values[definition.key] = current.length == 1 ? current.first : current;
    }
    return values;
  }

  List<Object> _draftValues(
    SpecDefinition definition,
    _CriterionDraft draft, {
    required bool tolerateInvalid,
  }) {
    if (!_isFreeValue(definition.dataType)) {
      return List<Object>.from(draft.values);
    }
    final count = draft.operator == 'between' ? 2 : 1;
    final values = <Object>[];
    for (var index = 0; index < count; index += 1) {
      final raw = _controller(definition.key, index).text.trim();
      if (raw.isEmpty) continue;
      if (_isNumeric(definition.dataType)) {
        final value = double.tryParse(raw.replaceAll(',', '.'));
        if (value == null) {
          if (tolerateInvalid) continue;
          throw FormatException(
              '${definition.label}: escribe un número válido.');
        }
        values.add(value);
      } else {
        values.add(raw);
      }
    }
    return values;
  }

  bool get _predicatesChanged {
    final List<SupplyNeedPredicate> drafted;
    try {
      drafted = _collectPredicates(tolerateInvalid: true);
    } on FormatException {
      return false;
    }
    return !supplyNeedPredicatesEqual(widget.criteria.predicates, drafted);
  }

  /// Cuántas filas del listado se muestran antes de la divulgación inline.
  static const int _previewCollapsedCount = 8;

  bool _previewExpanded = false;

  /// La previsualización de este borrador, calculada **una vez por build**.
  ///
  /// La frase y la lista tienen que salir del mismo cálculo, y para eso no
  /// basta prometerlo: un getter que cada quien invoca por su cuenta lo pide
  /// dos veces por frame y no hay nada que impida que devuelvan cosas
  /// distintas. Por eso `build` lo resuelve una sola vez y **pasa el resultado**
  /// a los dos consumidores.
  ///
  /// `drafted` distingue «no hay nada que previsualizar» de «hay un cambio pero
  /// el previsualizador no dio números»: la primera no dice nada y la segunda
  /// sí —«se acota el listado que ya tenemos»—.
  ({bool drafted, SupplyNeedEditPreview? preview}) _draftPreview() {
    if (!_predicatesChanged) return (drafted: false, preview: null);
    final List<SupplyNeedPredicate> predicates;
    try {
      predicates = _collectPredicates(tolerateInvalid: true);
    } on FormatException {
      return (drafted: false, preview: null);
    }
    return (drafted: true, preview: widget.previewFor?.call(predicates));
  }

  /// La consecuencia, con números reales y sin vocabulario que enseñar.
  String _consequenceFor(SupplyNeedEditPreview? preview) {
    if (preview == null || !preview.hasEvidence) {
      return 'Se acota el listado que ya tenemos. No se consulta al '
          'proveedor otra vez.';
    }
    if (preview.matching == 0) {
      return 'De ${preview.reviewed} revisadas no queda ninguna. '
          'No se consulta al proveedor otra vez.';
    }
    // **Lo que consta y lo que falta se dicen por separado.** Sumarlos daba «8
    // cumplen» cuando el proveedor sólo había confirmado 3: las otras 5 no
    // decían nada del tipo de válvula, y el silencio se leía como un sí.
    if (preview.unverified == 0) {
      return 'De ${preview.reviewed} revisadas quedarían ${preview.matching}, '
          'todas confirmadas. No se consulta al proveedor otra vez.';
    }
    if (preview.confirmed == 0) {
      return 'De ${preview.reviewed} revisadas quedarían ${preview.matching}, '
          'ninguna confirmada: '
          '${preview.unverified == 1 ? 'queda' : 'quedan'} por verificar. '
          'No se consulta al proveedor otra vez.';
    }
    return 'De ${preview.reviewed} revisadas quedarían ${preview.matching}: '
        '${preview.confirmed} '
        '${preview.confirmed == 1 ? 'cumple' : 'cumplen'} y '
        '${preview.unverified} '
        '${preview.unverified == 1 ? 'queda' : 'quedan'} por verificar. '
        'No se consulta al proveedor otra vez.';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final template = widget.template;
    final visible = template == null
        ? const <SpecTemplateField>[]
        : template.fields
            .where((field) =>
                field.definition != null && field.isVisible(_currentValues))
            .toList(growable: false);
    final draft = _draftPreview();
    final consequence = draft.drafted ? _consequenceFor(draft.preview) : null;
    return Column(
      key: const ValueKey('need-criteria-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(widget.title, style: PurchaseType.panelTitle),
        const SizedBox(height: PurchaseMetrics.stageGap),
        Text(
          'Ficha técnica: ${widget.categoryLabel}',
          key: const ValueKey('need-criteria-category'),
          style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
        ),
        const SizedBox(height: PurchaseMetrics.labelGap),
        if (widget.preciseBlockedReason != null)
          Text(
            widget.preciseBlockedReason!,
            key: const ValueKey('need-criteria-blocked'),
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          )
        else ...<Widget>[
          _responsiveFields(visible),
        ],
        if (consequence != null) ...<Widget>[
          const SizedBox(height: PurchaseMetrics.stageGap),
          Text(
            consequence,
            key: const ValueKey('need-criteria-consequence'),
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          ),
          _previewRows(draft.preview),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: PurchaseMetrics.labelGap),
          Text(
            _error!,
            key: const ValueKey('need-criteria-error'),
            style: PurchaseType.meta.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: PurchaseMetrics.actionsTopGap),
        Wrap(
          spacing: PurchaseMetrics.actionsGap,
          runSpacing: PurchaseMetrics.labelGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            PurchasePrimaryButton(
              key: const ValueKey('need-criteria-save'),
              label: 'Guardar criterios',
              onPressed: widget.busy || !_predicatesChanged ? null : _submit,
            ),
            TextButton(
              onPressed: widget.busy ? null : widget.onCancel,
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ],
    );
  }

  /// **Cuáles quedarían, no sólo cuántas.**
  ///
  /// Cambiar un criterio es para ver cómo se comportan los resultados. Con sólo
  /// el contador, enterarse de *qué* sobrevive obligaba a guardar —y guardar es
  /// exactamente lo que esta previsualización existe para no tener que hacer—.
  /// Las filas vienen del mismo juicio que el número, así que no pueden
  /// contradecirlo, y salen de las filas ya en memoria: acá no hay red.
  Widget _previewRows(SupplyNeedEditPreview? preview) {
    final rows = preview?.rows ?? const <SupplyNeedEditPreviewRow>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    final tokens = PurchaseTokens.of(context);
    // Un listado largo no puede empujar `Guardar criterios` fuera de alcance:
    // se muestra una tanda y el resto entra por divulgación inline, como la
    // cola de prioridad del módulo.
    final visible = _previewExpanded
        ? rows
        : rows.take(_previewCollapsedCount).toList(growable: false);
    final restantes = rows.length - visible.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        // El ancho que decide es el que hay, no el del dispositivo: este
        // editor vive dentro del scroll de la superficie.
        final compact =
            constraints.maxWidth < ResponsiveBreakpoints.phoneMaxExclusive;
        return Column(
          key: const ValueKey('need-criteria-preview-rows'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: PurchaseMetrics.stageGap),
            if (!compact) _previewHeader(),
            for (var index = 0; index < visible.length; index += 1) ...<Widget>[
              if (index > 0 || !compact)
                Container(height: 1, color: tokens.hair),
              _previewRow(visible[index], compact: compact),
            ],
            if (restantes > 0 || _previewExpanded) ...<Widget>[
              const SizedBox(height: PurchaseMetrics.labelGap),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('need-criteria-preview-more'),
                  onPressed: () =>
                      setState(() => _previewExpanded = !_previewExpanded),
                  child: Text(
                    _previewExpanded
                        ? 'Ver menos'
                        : restantes == 1
                            ? 'Ver la restante'
                            : 'Ver las $restantes restantes',
                    style: PurchaseType.inlineAction,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _previewHeader() {
    final tokens = PurchaseTokens.of(context);
    final style = PurchaseType.meta.copyWith(color: tokens.inkMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PurchaseMetrics.labelGap),
      child: Row(
        children: <Widget>[
          Expanded(flex: 5, child: Text('Producto', style: style)),
          Expanded(flex: 2, child: Text('Proveedor', style: style)),
          Expanded(flex: 2, child: Text('Precio neto', style: style)),
          Expanded(flex: 2, child: Text('Estado', style: style)),
        ],
      ),
    );
  }

  Widget _previewRow(
    SupplyNeedEditPreviewRow row, {
    required bool compact,
  }) {
    final tokens = PurchaseTokens.of(context);
    final metaStyle = PurchaseType.meta.copyWith(color: tokens.inkMuted);
    // El estado se escribe con las mismas palabras que la tabla del feed: dos
    // vocabularios para el mismo hecho es cómo el operador deja de creerle a
    // uno de los dos.
    final estado = row.isConfirmed ? 'Cumple' : 'Falta confirmar';
    final estadoStyle = PurchaseType.meta.copyWith(
      color: row.isConfirmed ? tokens.ink : tokens.inkMuted,
    );
    final producto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(row.name, style: PurchaseType.body),
        Text(
          row.brand == null || row.brand!.trim().isEmpty
              ? row.code
              : '${row.code} · ${row.brand!.trim()}',
          style: metaStyle,
        ),
      ],
    );
    final precio = PurchaseMoney.format(row.priceNet, 'CLP');
    return Semantics(
      // Una fila que sólo se lee por columnas no se puede encontrar ni afirmar.
      label: '${row.name} · ${row.code} · ${row.supplierName} · $estado',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PurchaseMetrics.labelGap),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  producto,
                  const SizedBox(height: PurchaseMetrics.labelGap),
                  Text(
                    '${row.supplierName} · $precio',
                    style: metaStyle,
                  ),
                  Text(estado, style: estadoStyle),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 5, child: producto),
                  Expanded(
                    flex: 2,
                    child: Text(row.supplierName, style: metaStyle),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(precio, style: PurchaseType.metaNumeric),
                  ),
                  Expanded(flex: 2, child: Text(estado, style: estadoStyle)),
                ],
              ),
      ),
    );
  }

  Widget _responsiveFields(List<SpecTemplateField> fields) {
    final tokens = PurchaseTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // **El ancho que decide es el que hay, no el de la ventana.** Este
        // editor vive dentro del scroll de la superficie y puede recibir menos
        // espacio que la pantalla; mirar `MediaQuery` dejaba el `constraints`
        // sin usar y ataba la composición al dispositivo en vez de al hueco.
        final compact =
            constraints.maxWidth < ResponsiveBreakpoints.phoneMaxExclusive;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!compact) _criteriaTableHeader(),
            for (var index = 0; index < fields.length; index += 1) ...<Widget>[
              // El separador de filas del módulo es el rol `hairline`, no el
              // `Divider` del tema: dos dueños del mismo trazo divergen.
              if (index > 0) Container(height: 1, color: tokens.hair),
              _criterionRow(fields[index], compact: compact),
            ],
          ],
        );
      },
    );
  }

  Widget _criteriaTableHeader() {
    final tokens = PurchaseTokens.of(context);
    final style = PurchaseType.meta.copyWith(color: tokens.inkMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PurchaseMetrics.labelGap),
      child: Row(
        children: <Widget>[
          Expanded(flex: 3, child: Text('Característica', style: style)),
          const SizedBox(width: PurchaseMetrics.stageGap),
          Expanded(flex: 2, child: Text('Condición', style: style)),
          const SizedBox(width: PurchaseMetrics.stageGap),
          Expanded(flex: 4, child: Text('Valor', style: style)),
        ],
      ),
    );
  }

  Widget _criterionRow(
    SpecTemplateField field, {
    required bool compact,
  }) {
    final definition = field.definition!;
    final draft = _drafts[definition.key]!;
    final characteristic = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(definition.label, style: PurchaseType.sectionTitle),
        if ((definition.helpText ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: PurchaseMetrics.labelGap),
          Text(
            definition.helpText!.trim(),
            style: PurchaseType.meta.copyWith(
              color: PurchaseTokens.of(context).inkMuted,
            ),
          ),
        ],
      ],
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PurchaseMetrics.stageGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            characteristic,
            const SizedBox(height: PurchaseMetrics.labelGap),
            _operatorField(definition, draft, showLabel: true),
            const SizedBox(height: PurchaseMetrics.labelGap),
            _valueField(definition, draft, showLabel: true),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PurchaseMetrics.stageGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 3, child: characteristic),
          const SizedBox(width: PurchaseMetrics.stageGap),
          Expanded(
            flex: 2,
            child: _operatorField(definition, draft, showLabel: false),
          ),
          const SizedBox(width: PurchaseMetrics.stageGap),
          Expanded(
            flex: 4,
            child: _valueField(definition, draft, showLabel: false),
          ),
        ],
      ),
    );
  }

  Widget _operatorField(
    SpecDefinition definition,
    _CriterionDraft draft, {
    required bool showLabel,
  }) {
    final options = _operatorsFor(definition.dataType);
    return VbShortSelect<String>(
      key: ValueKey('need-refinement-operator-${definition.key}'),
      value: options.contains(draft.operator) ? draft.operator : options.first,
      options: <VbShortSelectOption<String>>[
        for (final value in options)
          VbShortSelectOption<String>(
            value: value,
            label: _operatorLabel(value),
          ),
      ],
      onChanged: widget.busy
          ? null
          : (operator) => setState(() {
                // El operador cambia la condición, no el valor ya escrito.
                // Sin esta captura, pasar de «Igual a» a «Mínimo» volvía a
                // sembrar el controlador desde el valor original de la ficha
                // y descartaba silenciosamente la edición en curso.
                if (_isFreeValue(definition.dataType)) {
                  draft.values = _draftValues(
                    definition,
                    draft,
                    tolerateInvalid: true,
                  );
                }
                draft.operator = operator;
                if (operator != 'in' && draft.values.length > 1) {
                  draft.values = <Object>[draft.values.first];
                }
                _syncTextControllers(definition, draft);
              }),
      sheetTitle: 'Condición para ${definition.label}',
      label: showLabel ? 'Condición' : null,
    );
  }

  Widget _valueField(
    SpecDefinition definition,
    _CriterionDraft draft, {
    required bool showLabel,
  }) {
    return switch (definition.dataType) {
      'boolean' => _booleanValueField(
          definition,
          draft,
          showLabel: showLabel,
        ),
      'single_select' || 'select' => _selectValueField(
          definition,
          draft,
          showLabel: showLabel,
        ),
      'multi_select' || 'multiselect' => _multiSelectValueField(
          definition,
          draft,
          showLabel: showLabel,
        ),
      _ => _freeValueField(definition, draft, showLabel: showLabel),
    };
  }

  Widget _freeValueField(
    SpecDefinition definition,
    _CriterionDraft draft, {
    required bool showLabel,
  }) {
    final between = draft.operator == 'between';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: TextField(
            key: ValueKey('need-refinement-value-${definition.key}-0'),
            controller: _controller(definition.key, 0),
            enabled: !widget.busy,
            keyboardType: _isNumeric(definition.dataType)
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: showLabel ? (between ? 'Desde' : 'Valor') : null,
              hintText: showLabel ? null : (between ? 'Desde' : 'Valor'),
              suffixText: definition.unit,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (between) ...<Widget>[
          const SizedBox(width: PurchaseMetrics.stageGap),
          Expanded(
            child: TextField(
              key: ValueKey('need-refinement-value-${definition.key}-1'),
              controller: _controller(definition.key, 1),
              enabled: !widget.busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: showLabel ? 'Hasta' : null,
                hintText: showLabel ? null : 'Hasta',
                suffixText: definition.unit,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _booleanValueField(
    SpecDefinition definition,
    _CriterionDraft draft, {
    required bool showLabel,
  }) {
    final current = draft.values.singleOrNull;
    return VbShortSelect<bool?>(
      key: ValueKey('need-refinement-value-${definition.key}'),
      value: current is bool ? current : null,
      options: const <VbShortSelectOption<bool?>>[
        VbShortSelectOption<bool?>(value: null, label: 'Sin especificar'),
        VbShortSelectOption<bool?>(value: true, label: 'Sí'),
        VbShortSelectOption<bool?>(value: false, label: 'No'),
      ],
      onChanged: widget.busy
          ? null
          : (value) => setState(() {
                draft.operator = 'eq';
                draft.values = value == null ? <Object>[] : <Object>[value];
                _error = null;
              }),
      sheetTitle: definition.label,
      label: showLabel ? 'Valor' : null,
      placeholder: 'Sin especificar',
    );
  }

  Widget _selectValueField(
    SpecDefinition definition,
    _CriterionDraft draft, {
    required bool showLabel,
  }) {
    if (draft.operator == 'in') {
      return _multiSelectValueField(
        definition,
        draft,
        showLabel: showLabel,
      );
    }
    final value = draft.values.singleOrNull?.toString();
    final options = _allowedOptions(definition);
    if (options.length + 1 <= VbShortSelect.maxOptions) {
      return VbShortSelect<String?>(
        key: ValueKey('need-refinement-value-${definition.key}'),
        value: options.contains(value) ? value : null,
        options: <VbShortSelectOption<String?>>[
          const VbShortSelectOption<String?>(
            value: null,
            label: 'Sin especificar',
          ),
          for (final option in options)
            VbShortSelectOption<String?>(value: option, label: option),
        ],
        onChanged: widget.busy
            ? null
            : (selected) => setState(() {
                  draft.values =
                      selected == null ? <Object>[] : <Object>[selected];
                  _error = null;
                }),
        sheetTitle: definition.label,
        label: showLabel ? 'Valor' : null,
        placeholder: 'Sin especificar',
      );
    }
    return VbSearchableSelect<String>(
      key: ValueKey('need-refinement-value-${definition.key}'),
      value: options.contains(value) ? value : null,
      options: <VbSearchableSelectOption<String>>[
        for (final option in options)
          VbSearchableSelectOption<String>(value: option, label: option),
      ],
      onChanged: widget.busy
          ? null
          : (selected) => setState(() {
                draft.values =
                    selected == null ? <Object>[] : <Object>[selected];
                _error = null;
              }),
      sheetTitle: definition.label,
      label: showLabel ? 'Valor' : null,
      showLabel: showLabel,
      placeholder: 'Sin especificar',
      allowClear: true,
      clearLabel: 'Sin especificar',
    );
  }

  Widget _multiSelectValueField(
    SpecDefinition definition,
    _CriterionDraft draft, {
    required bool showLabel,
  }) {
    final options = _allowedOptions(definition);
    final chosen = draft.values.map((value) => value.toString()).toSet();
    final remaining =
        options.where((option) => !chosen.contains(option)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final value in chosen)
          Row(
            key: ValueKey('need-refinement-selected-${definition.key}-$value'),
            children: <Widget>[
              Expanded(child: Text(value, style: PurchaseType.body)),
              IconButton(
                tooltip: 'Quitar $value',
                onPressed: widget.busy
                    ? null
                    : () => setState(() {
                          draft.values.removeWhere(
                            (entry) => entry.toString() == value,
                          );
                          _error = null;
                        }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        if (remaining.isNotEmpty)
          VbSearchableSelect<String>(
            key: ValueKey('need-refinement-add-${definition.key}'),
            value: null,
            options: <VbSearchableSelectOption<String>>[
              for (final option in remaining)
                VbSearchableSelectOption<String>(
                  value: option,
                  label: option,
                ),
            ],
            onChanged: widget.busy
                ? null
                : (selected) {
                    if (selected == null) return;
                    setState(() {
                      draft.operator = 'in';
                      draft.values.add(selected);
                      _error = null;
                    });
                  },
            sheetTitle: 'Agregar ${definition.label}',
            label: showLabel
                ? (chosen.isEmpty ? 'Valor' : 'Agregar otra opción')
                : null,
            showLabel: showLabel,
            placeholder: 'Seleccionar…',
          ),
      ],
    );
  }

  List<String> _allowedOptions(SpecDefinition definition) {
    final field = widget.template!.fields.firstWhere(
      (field) => field.definition?.key == definition.key,
    );
    final narrowed = field.allowedOptionsFor(_currentValues);
    return definition.options
        .where((option) =>
            narrowed == null ||
            narrowed.contains(SpecTemplateField.normalizeRuleValue(option)))
        .toList(growable: false);
  }

  List<String> _operatorsFor(String dataType) => switch (dataType) {
        'number' => const <String>[
            'eq',
            'neq',
            'lt',
            'lte',
            'gt',
            'gte',
            'between'
          ],
        'text' => const <String>['contains', 'eq', 'neq'],
        'single_select' || 'select' => const <String>['eq', 'neq', 'in'],
        _ => const <String>['eq'],
      };

  String _operatorLabel(String value) => switch (value) {
        'eq' => 'Igual a',
        'neq' => 'Distinto de',
        'lt' => 'Menor que',
        'lte' => 'Máximo',
        'gt' => 'Mayor que',
        'gte' => 'Mínimo',
        'between' => 'Entre',
        'in' => 'Uno de',
        _ => 'Contiene',
      };

  bool _isNumeric(String dataType) => dataType == 'number';
  bool _isFreeValue(String dataType) =>
      dataType == 'number' || dataType == 'text';

  /// Junta los predicados dibujados, validándolos contra el propio template.
  ///
  /// `tolerateInvalid` existe para la línea de consecuencia, que se recalcula
  /// en cada tecla: mientras alguien escribe «2,» no se le puede gritar.
  List<SupplyNeedPredicate> _collectPredicates(
      {required bool tolerateInvalid}) {
    final template = widget.template;
    if (template == null) return const <SupplyNeedPredicate>[];
    final currentValues = _currentValues;
    final predicates = <SupplyNeedPredicate>[];
    for (final field in template.fields) {
      final definition = field.definition;
      if (definition == null || !field.isVisible(currentValues)) continue;
      final draft = _drafts[definition.key]!;
      final values = _draftValues(
        definition,
        draft,
        tolerateInvalid: tolerateInvalid,
      );
      if (values.isEmpty) continue;
      if (draft.operator == 'between' && values.length != 2) {
        if (tolerateInvalid) continue;
        throw FormatException('${definition.label}: completa ambos límites.');
      }
      if (!tolerateInvalid) {
        _validateBounds(definition, values);
      }
      predicates.add(SupplyNeedPredicate(
        field: definition.key,
        operator: draft.operator,
        values: List<Object>.unmodifiable(values),
      ));
    }
    // **Expresable es lo que el formulario MUESTRA, no lo que el template
    // contiene.** Este bucle recolecta sólo los campos visibles, así que
    // declarar expresable todo el template dejaba huérfano el predicado vigente
    // de un campo escondido por una regla de visibilidad: no se recolectaba ni
    // se arrastraba. En producción eso hacía que «Motor de centro sellado con
    // eje cuadrado» abriera `Criterios` con `Guardar` habilitado y la
    // consecuencia en pantalla **sin que el operador tocara nada**, y guardar
    // habría borrado en silencio el largo de eje.
    //
    // La regla de siempre —un criterio que no se ve no deja de existir— vale
    // igual cuando lo esconde la ficha: si el campo vuelve a mostrarse, el
    // valor sembrado sigue ahí y el operador puede cambiarlo.
    return carryForwardUnexpressedPredicates(
      drafted: predicates,
      current: widget.criteria.predicates,
      expressibleFields: <String>{
        for (final field in template.fields)
          if (field.definition != null && field.isVisible(currentValues))
            field.definition!.key,
      },
    );
  }

  void _submit() {
    try {
      final predicates = _collectPredicates(tolerateInvalid: false);
      if (predicates.length > 8) {
        throw const FormatException(
          'Puedes precisar hasta 8 características a la vez.',
        );
      }
      setState(() => _error = null);
      widget.onSave(predicates);
    } on FormatException catch (error) {
      setState(() => _error = error.message.toString());
    }
  }

  void _validateBounds(SpecDefinition definition, List<Object> values) {
    if (!_isNumeric(definition.dataType)) return;
    final minimum = _ruleNumber(definition.validationRules, 'min') ??
        _ruleNumber(definition.validationRules, 'minimum');
    final maximum = _ruleNumber(definition.validationRules, 'max') ??
        _ruleNumber(definition.validationRules, 'maximum');
    for (final raw in values) {
      final value = (raw as num).toDouble();
      if (minimum != null && value < minimum) {
        throw FormatException(
          '${definition.label}: el mínimo permitido es ${_number(minimum)}.',
        );
      }
      if (maximum != null && value > maximum) {
        throw FormatException(
          '${definition.label}: el máximo permitido es ${_number(maximum)}.',
        );
      }
    }
  }

  double? _ruleNumber(Map<String, dynamic> rules, String key) {
    final raw = rules[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  String _numberOrText(Object value) =>
      value is num ? _number(value) : '$value';

  String _number(num value) {
    final doubleValue = value.toDouble();
    if (doubleValue == doubleValue.roundToDouble()) {
      return doubleValue.toInt().toString();
    }
    return doubleValue.toString();
  }
}

class _CriterionDraft {
  _CriterionDraft({required this.operator, required this.values});

  String operator;
  List<Object> values;
}
