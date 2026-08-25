import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../purchases/models/intelligent_purchasing_models.dart';
import '../../purchases/services/intelligent_purchasing_service.dart';
import '../models/bikeshop_models.dart';

/// Brief Jobs-origin capture/editor for one durable supply need.
///
/// Product identity, quantity and workshop attribution are one decision. The
/// fields therefore stay in one vertical reading order instead of squeezing a
/// full-height numeric field beside a compact selector with unrelated
/// baselines. The surrounding status popover owns navigation; this widget owns
/// only the need draft and its exact saved receipt.
class SupplyNeedCapturePanel extends StatefulWidget {
  const SupplyNeedCapturePanel({
    super.key,
    required this.job,
    required this.jobBikes,
    required this.onCreated,
    required this.onResolve,
    this.existingNeed,
    this.initialJobBikeId,
    this.onUpdated,
    this.onReturnToList,
    this.service,
  });

  final MechanicJob job;
  final List<MechanicJobBike> jobBikes;
  final SupplyNeed? existingNeed;
  final String? initialJobBikeId;
  final ValueChanged<SupplyNeed> onCreated;
  final ValueChanged<SupplyNeed>? onUpdated;
  final ValueChanged<SupplyNeed> onResolve;
  final VoidCallback? onReturnToList;
  final IntelligentPurchasingService? service;

  @override
  State<SupplyNeedCapturePanel> createState() => _SupplyNeedCapturePanelState();
}

class _SupplyNeedCapturePanelState extends State<SupplyNeedCapturePanel> {
  static const _generalScope = '__general__';

  late final IntelligentPurchasingService _service;
  late final TextEditingController _descriptionController;
  late final TextEditingController _quantityController;
  ProductSelection? _selection;
  SupplyNeed? _editingNeed;
  String? _scope;
  String _operationKey = const Uuid().v4();
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  SupplyNeed? _savedNeed;

  List<MechanicJobBike> get _linkedBikes =>
      widget.jobBikes.where((link) => link.id != null).toList(growable: false)
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? IntelligentPurchasingService();
    _editingNeed = widget.existingNeed;
    _descriptionController = TextEditingController(
      text: _editingNeed?.description ?? '',
    );
    _quantityController = TextEditingController(
      text: _formatQuantity(_editingNeed?.quantity ?? 1),
    );
    _scope = _initialScope(_editingNeed);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  String? _initialScope(SupplyNeed? need) {
    if (need != null) return need.jobBikeId ?? _generalScope;
    final bikes = _linkedBikes;
    final requestedBikeId = widget.initialJobBikeId;
    if (requestedBikeId != null &&
        bikes.any((link) => link.id == requestedBikeId)) {
      return requestedBikeId;
    }
    if (bikes.length == 1) return bikes.single.id;
    if (bikes.isEmpty) return _generalScope;
    // A multi-bike job has no honest implicit destination. General remains an
    // explicit choice, but the operator must make it.
    return null;
  }

  double? get _quantity {
    final normalized = _quantityController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String? get _selectedProductId {
    final selection = _selection;
    if (selection != null && selection.isCatalogProduct) {
      if (_descriptionController.text.trim() == selection.displayText.trim()) {
        return selection.product?.id;
      }
      return null;
    }
    final existing = _editingNeed;
    if (existing != null &&
        _descriptionController.text.trim() == existing.description.trim()) {
      return existing.productId;
    }
    return null;
  }

  bool get _willDiscardCatalogIdentity {
    final selected = _selection;
    if (selected != null && selected.isCatalogProduct) {
      return _descriptionController.text.trim() != selected.displayText.trim();
    }
    final existing = _editingNeed;
    return existing?.productId != null &&
        _descriptionController.text.trim() != existing!.description.trim();
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final quantity = _quantity;
    final scope = _scope;
    setState(() => _submitted = true);
    if (description.isEmpty ||
        quantity == null ||
        scope == null ||
        widget.job.id == null) {
      setState(() {
        _error = description.isEmpty
            ? 'Describe o selecciona el repuesto.'
            : quantity == null
                ? 'Ingresa una cantidad mayor que cero.'
                : scope == null
                    ? 'Indica en qué bicicleta se usará o elige todo el trabajo.'
                    : 'Este trabajo aún no se puede vincular.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final jobBikeId = scope == _generalScope ? null : scope;
      final existing = _editingNeed;
      final need = existing == null
          ? await _service.createNeed(
              originKind: 'mechanic_job',
              mechanicJobId: widget.job.id,
              jobBikeId: jobBikeId,
              description: description,
              productId: _selectedProductId,
              quantity: quantity,
              operationKey: _operationKey,
            )
          : await _service.updateWorkshopNeed(
              existing,
              description: description,
              productId: _selectedProductId,
              jobBikeId: jobBikeId,
              quantity: quantity,
            );
      if (!mounted) return;
      setState(() {
        _savedNeed = need;
        _editingNeed = need;
        _saving = false;
      });
      if (existing == null) {
        widget.onCreated(need);
      } else {
        widget.onUpdated?.call(need);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'No se pudo guardar. La necesidad pudo haber cambiado; vuelve a cargarla e inténtalo otra vez.';
      });
    }
  }

  void _startAnother() {
    setState(() {
      _savedNeed = null;
      _editingNeed = null;
      _selection = null;
      _descriptionController.clear();
      _quantityController.text = '1';
      _scope = _initialScope(null);
      _operationKey = const Uuid().v4();
      _submitted = false;
      _error = null;
    });
  }

  String _bikeLabel(MechanicJobBike link) {
    final bike = link.bike;
    final serial = bike?.serialNumber?.trim();
    final identity = <String?>[
      bike?.brand,
      bike?.model,
      serial == null || serial.isEmpty ? null : 'S/N $serial',
    ]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' · ');
    if (identity.isNotEmpty) return identity;
    return 'Bicicleta ${link.orderIndex + 1}';
  }

  String _scopeLabel(String? jobBikeId) {
    if (jobBikeId == null) return 'Todo el trabajo';
    for (final link in _linkedBikes) {
      if (link.id == jobBikeId) return _bikeLabel(link);
    }
    return 'Bicicleta vinculada';
  }

  @override
  Widget build(BuildContext context) {
    final saved = _savedNeed;
    if (saved != null) return _buildReceipt(context, saved);

    final editing = _editingNeed != null;
    final linkedBikes = _linkedBikes;
    final scopeOptions = <VbSearchableSelectOption<String>>[
      ..._linkedBikes.map(
        (link) => VbSearchableSelectOption(
          value: link.id!,
          label: _bikeLabel(link),
          context: 'Bicicleta ${link.orderIndex + 1} del trabajo',
        ),
      ),
      const VbSearchableSelectOption(
        value: _generalScope,
        label: 'Todo el trabajo',
        context: 'Sin una bicicleta específica',
      ),
    ];
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          editing ? 'Editar repuesto' : 'Registrar repuesto',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Busca un producto del catálogo o descríbelo. La necesidad quedará visible aquí y en el Asistente de Compras.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ProductAutocompleteField(
          controller: _descriptionController,
          allowCustomItems: true,
          showCost: true,
          enabled: !_saving,
          autoFocus: false,
          preloadCatalog: false,
          minimumSearchCharacters: 2,
          compactSuggestions: true,
          labelText: 'Producto o descripción',
          hintText: 'SKU, nombre o descripción libre',
          onTextChanged: (_) {
            setState(() => _error = null);
          },
          onProductSelected: (selection) {
            setState(() {
              _selection = selection;
              _error = null;
            });
          },
        ),
        if (_willDiscardCatalogIdentity) ...[
          const SizedBox(height: 8),
          const VbNotice(
            title: 'La descripción ya no coincide con el catálogo',
            body:
                'Se guardará como texto libre y quedará por identificar en Compras.',
            tone: VbNoticeTone.warning,
          ),
        ],
        const SizedBox(height: 12),
        if (linkedBikes.length <= 1)
          _buildAutomaticScope(context, linkedBikes)
        else
          VbSearchableSelect<String>(
            value: _scope,
            options: scopeOptions,
            onChanged: _saving
                ? null
                : (value) {
                    setState(() {
                      _scope = value;
                      _error = null;
                    });
                  },
            sheetTitle: '¿Dónde se usará?',
            label: 'Aplicar en',
            placeholder: 'Elige una bicicleta o todo el trabajo',
            semanticLabel: 'Destino del repuesto',
            searchHint: 'Buscar bicicleta…',
            errorText: _submitted && _scope == null
                ? 'Selecciona un destino antes de guardar.'
                : null,
          ),
        const SizedBox(height: 12),
        Text('Cantidad', style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        SizedBox(
          height: VbShortSelect.fieldHeight,
          child: TextField(
            key: const ValueKey('workshop-supply-quantity'),
            controller: _quantityController,
            enabled: !_saving,
            textAlignVertical: TextAlignVertical.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            style: theme.textTheme.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              hintText: '1',
              contentPadding: const EdgeInsets.symmetric(horizontal: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          VbNotice(title: _error!, tone: VbNoticeTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            if (widget.onReturnToList != null)
              TextButton(
                onPressed: _saving ? null : widget.onReturnToList,
                child: const Text('Cancelar'),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(editing ? 'Guardar cambios' : 'Guardar repuesto'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAutomaticScope(
    BuildContext context,
    List<MechanicJobBike> linkedBikes,
  ) {
    final theme = Theme.of(context);
    final hasBike = linkedBikes.isNotEmpty;
    final destination =
        hasBike ? _bikeLabel(linkedBikes.single) : 'Todo el trabajo';
    return Semantics(
      label: 'Aplicar en: $destination',
      readOnly: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aplicar en', style: theme.textTheme.labelSmall),
          ListTile(
            key: const ValueKey('workshop-supply-automatic-scope'),
            contentPadding: EdgeInsets.zero,
            minVerticalPadding: 0,
            leading: Icon(
              hasBike ? Icons.pedal_bike_outlined : Icons.work_outline,
              color: theme.colorScheme.primary,
            ),
            title: Text(destination),
            subtitle: Text(
              hasBike
                  ? 'Destino automático: es la única bicicleta vinculada.'
                  : 'El trabajo no tiene una bicicleta específica vinculada.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceipt(BuildContext context, SupplyNeed need) {
    final theme = Theme.of(context);
    final productLabel = need.productName?.trim().isNotEmpty == true
        ? need.productName!.trim()
        : need.description;
    final productContext = <String>[
      if (need.productSku?.trim().isNotEmpty == true)
        'SKU ${need.productSku!.trim()}',
      '${_formatQuantity(need.quantity)} ${_unitLabel(need.quantity, need.unit)}',
      _scopeLabel(need.jobBikeId),
      'Registrado ${DateFormat('dd/MM/yyyy · HH:mm').format(need.createdAt.toLocal())}',
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VbNotice(
          title: widget.existingNeed == null
              ? 'Repuesto registrado'
              : 'Cambios guardados',
          body: need.hasConfirmedProduct
              ? 'Quedó vinculado al catálogo, a este trabajo y al destino indicado.'
              : 'Quedó trazado con la descripción original; Compras podrá identificarlo antes de buscar alternativas.',
          tone: VbNoticeTone.success,
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            need.hasConfirmedProduct
                ? Icons.inventory_2_outlined
                : Icons.manage_search_outlined,
            color: theme.colorScheme.primary,
          ),
          title:
              Text(productLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(productContext),
          trailing: VbStatusBadge(
            label:
                need.hasConfirmedProduct ? 'Identificado' : 'Por identificar',
            tone: need.hasConfirmedProduct
                ? VbStatusTone.success
                : VbStatusTone.warning,
            dense: true,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.onReturnToList != null)
              TextButton(
                onPressed: widget.onReturnToList,
                child: const Text('Ver repuestos'),
              ),
            TextButton(
              onPressed: _startAnother,
              child: const Text('Añadir otro'),
            ),
            FilledButton.icon(
              onPressed: () => widget.onResolve(need),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Abrir en Compras'),
            ),
          ],
        ),
      ],
    );
  }

  String _unitLabel(double quantity, String unit) {
    if (unit != 'unit') return unit;
    return quantity == 1 ? 'unidad' : 'unidades';
  }

  static String _formatQuantity(double value) {
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }
}
