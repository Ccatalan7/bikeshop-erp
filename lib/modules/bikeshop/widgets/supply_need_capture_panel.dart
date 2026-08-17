import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../../purchases/models/intelligent_purchasing_models.dart';
import '../../purchases/services/intelligent_purchasing_service.dart';
import '../models/bikeshop_models.dart';

class SupplyNeedCapturePanel extends StatefulWidget {
  const SupplyNeedCapturePanel({
    super.key,
    required this.job,
    required this.jobBikes,
    required this.onCreated,
    required this.onResolve,
    this.service,
  });

  final MechanicJob job;
  final List<MechanicJobBike> jobBikes;
  final ValueChanged<SupplyNeed> onCreated;
  final ValueChanged<SupplyNeed> onResolve;
  final IntelligentPurchasingService? service;

  @override
  State<SupplyNeedCapturePanel> createState() => _SupplyNeedCapturePanelState();
}

class _SupplyNeedCapturePanelState extends State<SupplyNeedCapturePanel> {
  static const _generalScope = '__general__';

  late final IntelligentPurchasingService _service;
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  ProductSelection? _selection;
  String _scope = _generalScope;
  String _operationKey = const Uuid().v4();
  bool _saving = false;
  String? _error;
  SupplyNeed? _createdNeed;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? IntelligentPurchasingService();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  double? get _quantity {
    final normalized = _quantityController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String? get _selectedProductId {
    final selection = _selection;
    if (selection == null || !selection.isCatalogProduct) return null;
    if (_descriptionController.text.trim() != selection.displayText.trim()) {
      return null;
    }
    return selection.product?.id;
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final quantity = _quantity;
    if (description.isEmpty || quantity == null || widget.job.id == null) {
      setState(() {
        _error = description.isEmpty
            ? 'Describe o selecciona el repuesto.'
            : quantity == null
                ? 'Ingresa una cantidad mayor que cero.'
                : 'Este trabajo aún no se puede vincular.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final need = await _service.createNeed(
        originKind: 'mechanic_job',
        mechanicJobId: widget.job.id,
        jobBikeId: _scope == _generalScope ? null : _scope,
        description: description,
        productId: _selectedProductId,
        quantity: quantity,
        operationKey: _operationKey,
      );
      if (!mounted) return;
      setState(() {
        _createdNeed = need;
        _saving = false;
      });
      widget.onCreated(need);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar. Revisa la conexión e inténtalo otra vez.';
      });
    }
  }

  void _startAnother() {
    setState(() {
      _createdNeed = null;
      _selection = null;
      _descriptionController.clear();
      _quantityController.text = '1';
      _scope = _generalScope;
      _operationKey = const Uuid().v4();
      _error = null;
    });
  }

  String _bikeLabel(MechanicJobBike link) {
    final bike = link.bike;
    final identity = <String?>[bike?.brand, bike?.model]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' ');
    if (identity.isNotEmpty) return identity;
    return 'Bicicleta ${link.orderIndex + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final created = _createdNeed;
    if (created != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VbNotice(
            title: 'Repuesto guardado',
            body: created.hasConfirmedProduct
                ? 'Quedó vinculado al catálogo y listo para revisar stock.'
                : 'El asistente interpretará la descripción antes de comparar alternativas.',
            tone: VbNoticeTone.success,
          ),
          const SizedBox(height: 12),
          Text(
            created.description,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatQuantity(created.quantity)} ${created.unit == 'unit' ? 'unidad(es)' : created.unit}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _startAnother,
                child: const Text('Añadir otro'),
              ),
              FilledButton.icon(
                onPressed: () => widget.onResolve(created),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Resolver abastecimiento'),
              ),
            ],
          ),
        ],
      );
    }

    final scopeOptions = <VbSearchableSelectOption<String>>[
      const VbSearchableSelectOption(
        value: _generalScope,
        label: 'General del trabajo',
      ),
      ...widget.jobBikes.where((link) => link.id != null).map(
            (link) => VbSearchableSelectOption(
              value: link.id!,
              label: _bikeLabel(link),
              context: 'Bicicleta del trabajo',
            ),
          ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '¿Qué falta para continuar este trabajo?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        ProductAutocompleteField(
          controller: _descriptionController,
          allowCustomItems: true,
          showCost: true,
          autoFocus: true,
          preloadCatalog: false,
          minimumSearchCharacters: 2,
          compactSuggestions: true,
          labelText: 'Repuesto',
          hintText: 'Busca en catálogo o descríbelo con tus palabras',
          onProductSelected: (selection) {
            setState(() {
              _selection = selection;
              _error = null;
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: TextField(
                controller: _quantityController,
                enabled: !_saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (scopeOptions.length > 1) ...[
              const SizedBox(width: 12),
              Expanded(
                child: VbSearchableSelect<String>(
                  value: _scope,
                  options: scopeOptions,
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _scope = value);
                        },
                  sheetTitle: 'Asignar repuesto a',
                  label: 'Aplica a',
                  searchHint: 'Buscar bicicleta…',
                ),
              ),
            ],
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          VbNotice(
            title: _error!,
            tone: VbNoticeTone.danger,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar repuesto'),
          ),
        ),
      ],
    );
  }

  String _formatQuantity(double value) {
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }
}
