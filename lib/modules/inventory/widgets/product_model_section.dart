import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:vinabike_public_core/public_store/models/public_product_model.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_search_field.dart';
import '../models/product_model_draft.dart';
import '../services/product_model_service.dart';

/// «Modelo y variantes» en la ficha del producto (20261120230000): las otras
/// tallas y colores de lo mismo, que la tienda muestra en una sola ficha con
/// un selector. Se lee y se arma aquí mismo («Editar» pone la sección en
/// edición; nada de diálogos): el nombre del modelo, sus ejes con sus valores
/// y cada variante con el valor que le toca. Al agrupar, el nombre de los
/// productos sugiere el modelo, el color y la talla.
class ProductModelSection extends StatefulWidget {
  const ProductModelSection({
    super.key,
    required this.product,
    required this.onOpenProduct,
    this.service,
  });

  /// Este producto, como variante (sus opciones vacías).
  final ProductModelMember product;

  /// Abre la ficha de otra variante.
  final ValueChanged<String> onOpenProduct;

  /// Para las pruebas.
  final ProductModelService? service;

  @override
  State<ProductModelSection> createState() => _ProductModelSectionState();
}

class _ProductModelSectionState extends State<ProductModelSection> {
  late final ProductModelService _service =
      widget.service ?? ProductModelService();
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final Map<String, TextEditingController> _valueControllers = {};
  final _axisController = TextEditingController();

  ProductModel? _model;
  bool _loading = true;
  String? _loadError;

  ProductModelDraft? _draft;
  bool _autoAxes = false;
  bool _saving = false;
  bool _confirmingDelete = false;
  String? _saveError;

  List<ProductModelCandidate> _candidates = const [];
  bool _searching = false;
  Timer? _searchDebounce;
  int _searchSerial = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    _axisController.dispose();
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final model = await _service.fetchForProduct(widget.product.productId);
      if (!mounted) return;
      setState(() {
        _model = model;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'No se pudo leer el modelo de este producto.';
      });
    }
  }

  void _startEditing() {
    final model = _model;
    final draft = model == null
        ? ProductModelDraft(
            name: widget.product.name,
            axes: const [],
            members: [widget.product],
          )
        : ProductModelDraft.fromModel(model);
    setState(() {
      _draft = draft;
      // Un modelo nuevo se arma solo con los nombres hasta que el equipo
      // toca el nombre, los ejes o una opción.
      _autoAxes = model == null;
      _saveError = null;
      _confirmingDelete = false;
      _nameController.text = draft.name;
      _searchController.clear();
    });
    _search('');
  }

  void _cancel() {
    setState(() {
      _draft = null;
      _saveError = null;
      _confirmingDelete = false;
    });
  }

  void _update(ProductModelDraft draft, {bool manual = true}) {
    setState(() {
      _draft = draft;
      if (manual) _autoAxes = false;
      _saveError = null;
    });
  }

  void _addMember(ProductModelCandidate candidate) {
    final draft = _draft;
    if (draft == null) return;
    if (_autoAxes) {
      final suggested = ProductModelDraft.suggest([
        ...draft.members,
        candidate.toMember(),
      ]);
      _nameController.text = suggested.name;
      _update(
        ProductModelDraft(
          id: draft.id,
          updatedAt: draft.updatedAt,
          name: suggested.name,
          axes: suggested.axes,
          members: suggested.members,
        ),
        manual: false,
      );
    } else {
      _update(draft.withMember(candidate.toMember()), manual: false);
    }
  }

  void _removeMember(String productId) {
    final draft = _draft;
    if (draft == null) return;
    if (_autoAxes) {
      final rest = [
        for (final member in draft.members)
          if (member.productId != productId) member,
      ];
      final suggested = rest.length > 1
          ? ProductModelDraft.suggest(rest)
          : draft.copyWith(axes: const [], members: rest);
      _nameController.text = rest.length > 1 ? suggested.name : draft.name;
      _update(
        ProductModelDraft(
          id: draft.id,
          updatedAt: draft.updatedAt,
          name: rest.length > 1 ? suggested.name : draft.name,
          axes: suggested.axes,
          members: suggested.members,
        ),
        manual: false,
      );
    } else {
      _update(draft.withoutMember(productId), manual: false);
    }
  }

  void _search(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      final serial = ++_searchSerial;
      setState(() => _searching = true);
      try {
        final found = await _service.candidates(
          widget.product.productId,
          query: query,
        );
        if (!mounted || serial != _searchSerial) return;
        setState(() {
          _candidates = found;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || serial != _searchSerial) return;
        setState(() {
          _candidates = const [];
          _searching = false;
        });
      }
    });
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || !draft.canSave) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await _service.save(
        draft.copyWith(name: _nameController.text),
      );
      if (!mounted) return;
      setState(() {
        _model = saved;
        _draft = null;
        _saving = false;
      });
    } on ProductModelException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'No se pudo guardar el modelo. Revisa la conexión.';
      });
    }
  }

  Future<void> _delete() async {
    final model = _model;
    if (model == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _service.delete(model.id);
      if (!mounted) return;
      setState(() {
        _model = null;
        _draft = null;
        _saving = false;
        _confirmingDelete = false;
      });
    } on ProductModelException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'No se pudo desarmar el modelo. Revisa la conexión.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_loadError != null) {
      return _Notice(
        text: _loadError!,
        action: VbButton(
          label: 'Reintentar',
          variant: VbButtonVariant.text,
          onPressed: _load,
        ),
      );
    }
    final draft = _draft;
    if (draft != null) return _buildEditor(context, draft);
    final model = _model;
    if (model == null) return _buildLoose(context);
    return _buildRead(context, model);
  }

  Widget _buildLoose(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Si este producto viene en otras tallas o colores, júntalos en un '
          'modelo: la tienda los muestra en una sola ficha, con un selector '
          'de color y talla, y cada uno sigue con su stock y su SKU.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        VbButton(
          label: 'Agrupar tallas y colores',
          icon: Icons.layers_outlined,
          variant: VbButtonVariant.secondary,
          onPressed: _startEditing,
        ),
      ],
    );
  }

  Widget _buildRead(BuildContext context, ProductModel model) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final label = productModelAxesLabel([
      for (final axis in model.axes)
        (
          name: axis.name,
          count: {
            for (final member in model.members)
              if ((member.options[axis.name] ?? '').isNotEmpty)
                member.options[axis.name],
          }.length,
        ),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '${model.members.length} variantes',
                      if (label.isNotEmpty) label,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            VbButton(
              label: 'Editar',
              icon: Icons.edit_outlined,
              variant: VbButtonVariant.text,
              onPressed: _startEditing,
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < model.members.length; i++) ...[
          if (i > 0) Divider(height: 1, color: roles.hairline),
          _VariantRow(
            member: model.members[i],
            axes: model.axes,
            isThis: model.members[i].productId == widget.product.productId,
            onOpen: model.members[i].productId == widget.product.productId
                ? null
                : () => widget.onOpenProduct(model.members[i].productId),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'La tienda las muestra en una sola ficha, con un selector; cada '
          'una conserva su página, su stock y su SKU.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: roles.faintForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context, ProductModelDraft draft) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final problems = draft.copyWith(name: _nameController.text).problems;
    final memberIds = {for (final member in draft.members) member.productId};
    final candidates = [
      for (final candidate in _candidates)
        if (!memberIds.contains(candidate.productId)) candidate,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('product-model-name'),
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Nombre del modelo',
            helperText: 'Lo que comparten: «Rodillera Leatt 3DF 5.0».',
          ),
          onChanged: (value) => _update(draft.copyWith(name: value)),
        ),
        const SizedBox(height: 20),
        const _SubHeading('Qué cambia entre ellas'),
        const SizedBox(height: 8),
        if (draft.axes.isEmpty)
          Text(
            'Agrega las otras variantes abajo y sus nombres dirán qué cambia; '
            'o agrega un eje.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        for (final axis in draft.axes) _buildAxisEditor(context, draft, axis),
        if (draft.axes.length < ProductModelDraft.maxAxes)
          _buildAxisAdder(context, draft),
        const SizedBox(height: 20),
        _SubHeading('Variantes (${draft.members.length})'),
        const SizedBox(height: 4),
        for (var i = 0; i < draft.members.length; i++) ...[
          if (i > 0) Divider(height: 1, color: roles.hairline),
          _EditableVariantRow(
            member: draft.members[i],
            axes: draft.axes,
            isThis: draft.members[i].productId == widget.product.productId,
            onOption: (axis, value) => _update(
              draft.withOption(draft.members[i].productId, axis, value),
            ),
            onRemove: () => _removeMember(draft.members[i].productId),
          ),
        ],
        const SizedBox(height: 16),
        VbSearchField(
          controller: _searchController,
          hint: 'Agregar otra talla o color: busca por nombre o SKU',
          onChanged: _search,
          onClear: () {
            _searchController.clear();
            _search('');
          },
        ),
        const SizedBox(height: 6),
        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _searchController.text.trim().isEmpty
                  ? 'No hay productos con un nombre parecido. Búscalos por '
                      'nombre o SKU.'
                  : 'Nada con «${_searchController.text.trim()}».',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          if (_searchController.text.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                'Parecidos por nombre',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final candidate in candidates.take(8))
            _CandidateRow(
              candidate: candidate,
              onAdd: candidate.modelId != null ||
                      draft.members.length >= ProductModelDraft.maxMembers
                  ? null
                  : () => _addMember(candidate),
            ),
        ],
        const SizedBox(height: 16),
        if (problems.isNotEmpty) _Problems(problems: problems),
        if (_saveError != null) ...[
          const SizedBox(height: 8),
          _Notice(text: _saveError!, tone: _NoticeTone.error),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            VbButton(
              label: draft.id == null ? 'Crear modelo' : 'Guardar modelo',
              icon: Icons.check,
              busy: _saving,
              onPressed: problems.isEmpty && !_saving ? _save : null,
            ),
            VbButton(
              label: 'Cancelar',
              variant: VbButtonVariant.text,
              onPressed: _saving ? null : _cancel,
            ),
            if (draft.id != null && !_confirmingDelete)
              VbButton(
                label: 'Desarmar modelo',
                variant: VbButtonVariant.text,
                icon: Icons.link_off,
                onPressed: _saving
                    ? null
                    : () => setState(() => _confirmingDelete = true),
              ),
          ],
        ),
        if (_confirmingDelete) ...[
          const SizedBox(height: 12),
          _Notice(
            tone: _NoticeTone.attention,
            text: 'Los ${_model?.members.length ?? draft.members.length} '
                'productos quedan sueltos, cada uno con su ficha, como antes. '
                'La tienda los vuelve a mostrar por separado.',
            action: Wrap(
              spacing: 8,
              children: [
                VbButton(
                  label: 'Desarmar',
                  variant: VbButtonVariant.destructive,
                  busy: _saving,
                  onPressed: _saving ? null : _delete,
                ),
                VbButton(
                  label: 'No',
                  variant: VbButtonVariant.text,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _confirmingDelete = false),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  TextEditingController _valueController(String axis) =>
      _valueControllers.putIfAbsent(axis, TextEditingController.new);

  Widget _buildAxisEditor(
    BuildContext context,
    ProductModelDraft draft,
    ProductModelAxis axis,
  ) {
    final theme = Theme.of(context);
    final controller = _valueController(axis.name);
    void addValue() {
      final value = controller.text.trim();
      if (value.isEmpty) return;
      controller.clear();
      _update(draft.withAxisValue(axis.name, value));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                axis.name,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (draft.axes.length > 1)
                VbButton(
                  label: 'Quitar ${axis.name.toLowerCase()}',
                  variant: VbButtonVariant.text,
                  onPressed: () => _update(draft.withoutAxis(axis.name)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final value in axis.values)
                InputChip(
                  label: Text(value),
                  onDeleted: () =>
                      _update(draft.withoutAxisValue(axis.name, value)),
                  deleteButtonTooltipMessage: 'Quitar $value',
                ),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '+ ${productModelAxisWord(axis.name, 1)}',
                  ),
                  onSubmitted: (_) => addValue(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAxisAdder(BuildContext context, ProductModelDraft draft) {
    final taken = {for (final axis in draft.axes) axis.name.toLowerCase()};
    final suggestions = [
      for (final name in const ['Color', 'Talla', 'Medida'])
        if (!taken.contains(name.toLowerCase())) name,
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final name in suggestions)
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: Text(name),
            onPressed: () => _update(draft.withAxis(name)),
          ),
        SizedBox(
          width: 170,
          child: TextField(
            controller: _axisController,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '+ otro eje',
            ),
            onSubmitted: (value) {
              _axisController.clear();
              _update(draft.withAxis(value));
            },
          ),
        ),
      ],
    );
  }
}

class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// La foto del producto sobre una placa blanca, también en oscuro.
class _Photo extends StatelessWidget {
  const _Photo({required this.url, this.size = 44});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final radius = BorderRadius.circular(9);
    final image = url;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: image == null ? scheme.surfaceContainerHigh : Colors.white,
        border: Border.all(color: roles.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: image == null
          ? Icon(
              Icons.no_photography_outlined,
              size: size * 0.42,
              color: scheme.onSurfaceVariant,
            )
          : CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.contain,
              memCacheWidth: (size * 3).round(),
              errorWidget: (context, url, error) => Icon(
                Icons.broken_image_outlined,
                size: size * 0.42,
                color: scheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

/// Stock, precio y si está en la tienda, en una línea chica.
String _facts(ProductModelMember member) => [
      if (member.sku.isNotEmpty) member.sku,
      ChileanUtils.formatCurrency(member.price),
      if (member.trackStock)
        member.stock > 0 ? 'Stock ${member.stock}' : 'Sin stock',
      if (!member.onWebsite) 'Fuera de la tienda',
    ].join(' · ');

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.member,
    required this.axes,
    required this.isThis,
    this.onOpen,
  });

  final ProductModelMember member;
  final List<ProductModelAxis> axes;
  final bool isThis;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final options = [
      for (final axis in axes)
        if ((member.options[axis.name] ?? '').isNotEmpty)
          member.options[axis.name]!,
    ].join(' · ');
    return Semantics(
      button: onOpen != null,
      label: isThis ? '$options, esta ficha' : 'Abrir $options',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              _Photo(url: member.image),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          options.isEmpty ? member.name : options,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isThis)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: roles.selectionContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Esta ficha',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: roles.onSelectionContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _facts(member),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (onOpen != null)
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableVariantRow extends StatelessWidget {
  const _EditableVariantRow({
    required this.member,
    required this.axes,
    required this.isThis,
    required this.onOption,
    required this.onRemove,
  });

  final ProductModelMember member;
  final List<ProductModelAxis> axes;
  final bool isThis;
  final void Function(String axis, String value) onOption;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Photo(url: member.image, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isThis ? '${member.name} (esta ficha)' : member.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _facts(member),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final axis in axes)
                  if (axis.values.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 56,
                            child: Text(
                              axis.name,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final value in axis.values)
                            _OptionPill(
                              label: value,
                              selected: member.options[axis.name] == value,
                              missing:
                                  (member.options[axis.name] ?? '').isEmpty,
                              onTap: () => onOption(axis.name, value),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar del modelo',
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Un valor a la vista, elegido con un toque (nada de menús flotantes).
class _OptionPill extends StatelessWidget {
  const _OptionPill({
    required this.label,
    required this.selected,
    required this.missing,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool missing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        // Del ancho de su texto: en un Wrap, un Container con `alignment`
        // se estira a todo el ancho y cada valor quedaba en su propia línea
        // (visto en la app real el 2026-11-20).
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? roles.selectionContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : missing
                      ? roles.warning.border
                      : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Align(
            widthFactor: 1,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? roles.onSelectionContainer : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, required this.onAdd});

  final ProductModelCandidate candidate;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taken = candidate.modelName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _Photo(url: candidate.image, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.name, style: theme.textTheme.bodyMedium),
                Text(
                  [
                    if (candidate.sku.isNotEmpty) candidate.sku,
                    ChileanUtils.formatCurrency(candidate.price),
                    if (taken != null) 'Ya está en «$taken»',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          VbButton(
            label: 'Agregar',
            icon: Icons.add,
            variant: VbButtonVariant.secondary,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _Problems extends StatelessWidget {
  const _Problems({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final problem in problems.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    problem,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (problems.length > 4)
          Text(
            'y ${problems.length - 4} más.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

enum _NoticeTone { neutral, attention, error }

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    this.action,
    this.tone = _NoticeTone.neutral,
  });

  final String text;
  final Widget? action;
  final _NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final (background, border, foreground) = switch (tone) {
      _NoticeTone.neutral => (
          theme.colorScheme.surfaceContainerHigh,
          theme.colorScheme.outlineVariant,
          theme.colorScheme.onSurface,
        ),
      _NoticeTone.attention => (
          roles.warning.container,
          roles.warning.border,
          roles.warning.onContainer,
        ),
      _NoticeTone.error => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.error,
          theme.colorScheme.onErrorContainer,
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
