import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../../shared/models/product.dart';

/// Widget for configuring a product as a set (juego) with components
/// Allows defining component products with labels, prices, and costs
class SetConfigurationWidget extends StatefulWidget {
  /// Whether this product is a set
  final bool isSet;

  /// Existing set identities cannot be downgraded through a best-effort
  /// product update. Their lifecycle is owned by the aggregate command.
  final bool canChangeSetStatus;

  /// Type of set (pair, front_rear, left_right, custom)
  final SetType? setType;

  /// List of component definitions being edited
  final List<SetComponentDraft> components;

  /// Callback when isSet changes
  final ValueChanged<bool> onIsSetChanged;

  /// Callback when set type changes
  final ValueChanged<SetType?> onSetTypeChanged;

  /// Callback when components change
  final ValueChanged<List<SetComponentDraft>> onComponentsChanged;

  /// Parent product name for auto-generating component names
  final String parentProductName;

  /// Parent product SKU for auto-generating component SKUs
  final String parentProductSku;

  /// Parent product price (for ratio calculations)
  final double parentPrice;

  /// Parent product cost (for ratio calculations)
  final double parentCost;

  const SetConfigurationWidget({
    super.key,
    required this.isSet,
    this.canChangeSetStatus = true,
    this.setType,
    required this.components,
    required this.onIsSetChanged,
    required this.onSetTypeChanged,
    required this.onComponentsChanged,
    required this.parentProductName,
    required this.parentProductSku,
    required this.parentPrice,
    required this.parentCost,
  });

  @override
  State<SetConfigurationWidget> createState() => _SetConfigurationWidgetState();
}

class _SetConfigurationWidgetState extends State<SetConfigurationWidget> {
  // Separate modes for cost and price
  bool _useCostRatios = true;
  bool _usePriceRatios = true;

  // Controllers for live updates
  final Map<int, TextEditingController> _costControllers = {};
  final Map<int, TextEditingController> _priceControllers = {};
  // Track which field is currently being edited to avoid overwriting user input
  // ignore: unused_field
  int? _editingCostIndex;
  // ignore: unused_field
  int? _editingPriceIndex;

  @override
  void dispose() {
    for (final c in _costControllers.values) {
      c.dispose();
    }
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(SetConfigurationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defer sync to after build completes to avoid setState during build
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncAllControllers();
      }
    });
  }

  void _syncAllControllers() {
    for (int i = 0; i < widget.components.length; i++) {
      final component = widget.components[i];

      // Sync cost controller
      if (_costControllers.containsKey(i)) {
        final newCostValue = _useCostRatios
            ? (component.costRatio != null
                ? (component.costRatio! * 100).toStringAsFixed(0)
                : '')
            : component.cost.toStringAsFixed(0);
        if (_costControllers[i]!.text != newCostValue) {
          _costControllers[i]!.text = newCostValue;
        }
      }

      // Sync price controller
      if (_priceControllers.containsKey(i)) {
        final newPriceValue = _usePriceRatios
            ? (component.priceRatio != null
                ? (component.priceRatio! * 100).toStringAsFixed(0)
                : '')
            : component.price.toStringAsFixed(0);
        if (_priceControllers[i]!.text != newPriceValue) {
          _priceControllers[i]!.text = newPriceValue;
        }
      }
    }
  }

  TextEditingController _getCostController(int index, String value) {
    if (!_costControllers.containsKey(index)) {
      _costControllers[index] = TextEditingController(text: value);
    }
    return _costControllers[index]!;
  }

  TextEditingController _getPriceController(int index, String value) {
    if (!_priceControllers.containsKey(index)) {
      _priceControllers[index] = TextEditingController(text: value);
    }
    return _priceControllers[index]!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main toggle: Is this a set?
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Row(
            children: [
              const Text('Es un Juego/Set'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '📦',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Text(
            !widget.canChangeSetStatus && !widget.isSet
                ? 'Un producto existente no se convierte en juego desde esta ficha. Crea un juego nuevo para definir su composición de forma atómica.'
                : 'El juego no guarda stock propio: su disponibilidad se calcula desde sus componentes.',
          ),
          value: widget.isSet,
          onChanged: widget.canChangeSetStatus ? widget.onIsSetChanged : null,
        ),

        // Show set configuration only when isSet is true
        if (widget.isSet) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // Set type selector
          _buildSetTypeSelector(theme),

          const SizedBox(height: 16),

          // Pricing mode toggles (separate for cost and price)
          _buildPricingModeToggles(theme),

          const SizedBox(height: 16),

          // Components list
          _buildComponentsList(theme),

          const SizedBox(height: 12),

          // Add component button
          Center(
            child: OutlinedButton.icon(
              onPressed: _addComponent,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Componente'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSetTypeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de Set',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SetType.values.map((type) {
            final isSelected = widget.setType == type;
            return ChoiceChip(
              label: Text(type.displayName),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  widget.onSetTypeChanged(type);
                  // Always regenerate components based on new type
                  _autoGenerateComponents(type);
                  // Clear controllers to force re-initialization with new values
                  _costControllers.clear();
                  _priceControllers.clear();
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPricingModeToggles(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Modo de Precios',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // Cost mode toggle
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  'Costo:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Porcentajes'),
                      icon: Icon(Icons.percent, size: 16),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Manual'),
                      icon: Icon(Icons.edit, size: 16),
                    ),
                  ],
                  selected: {_useCostRatios},
                  onSelectionChanged: (selection) {
                    setState(() => _useCostRatios = selection.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Price mode toggle
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  'Precio:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Porcentajes'),
                      icon: Icon(Icons.percent, size: 16),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Manual'),
                      icon: Icon(Icons.edit, size: 16),
                    ),
                  ],
                  selected: {_usePriceRatios},
                  onSelectionChanged: (selection) {
                    setState(() => _usePriceRatios = selection.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _useCostRatios || _usePriceRatios
                ? '💡 Al editar un %, el resto se ajusta automáticamente.'
                : 'Los valores se definen manualmente para cada componente.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentsList(ThemeData theme) {
    if (widget.components.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 8),
              Text(
                'Sin componentes definidos',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Selecciona un tipo de set o agrega componentes manualmente',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Componentes (${widget.components.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // Show total percentages
            if (_useCostRatios || _usePriceRatios) ...[
              if (_useCostRatios)
                _buildTotalBadge(theme, 'Costo', _getTotalCostRatio()),
              if (_useCostRatios && _usePriceRatios) const SizedBox(width: 8),
              if (_usePriceRatios)
                _buildTotalBadge(theme, 'Precio', _getTotalPriceRatio()),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ...widget.components.asMap().entries.map((entry) {
          final index = entry.key;
          final component = entry.value;
          return _buildComponentCard(theme, index, component);
        }),
      ],
    );
  }

  Widget _buildTotalBadge(ThemeData theme, String label, double total) {
    final isValid = (total - 1.0).abs() < 0.001; // Close to 100%
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isValid
            ? Colors.green.withValues(alpha: 0.1)
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: ${(total * 100).toStringAsFixed(0)}%',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: isValid ? Colors.green : theme.colorScheme.error,
        ),
      ),
    );
  }

  double _getTotalCostRatio() {
    return widget.components.fold(0.0, (sum, c) => sum + (c.costRatio ?? 0));
  }

  double _getTotalPriceRatio() {
    return widget.components.fold(0.0, (sum, c) => sum + (c.priceRatio ?? 0));
  }

  Widget _buildComponentCard(
      ThemeData theme, int index, SetComponentDraft component) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with position and delete button
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    component.label.isEmpty
                        ? 'Componente ${index + 1}'
                        : component.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeComponent(index),
                  color: theme.colorScheme.error,
                  tooltip: 'Eliminar componente',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Component fields
            Row(
              children: [
                // Label field
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('label_${index}_${component.label}'),
                    initialValue: component.label,
                    decoration: const InputDecoration(
                      labelText: 'Etiqueta',
                      hintText: 'Ej: Delantero',
                      isDense: true,
                    ),
                    onChanged: (value) => _updateComponent(
                        index, component.copyWith(label: value)),
                  ),
                ),
                const SizedBox(width: 12),
                // SKU suffix field
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('sku_${index}_${component.skuSuffix}'),
                    initialValue: component.skuSuffix,
                    decoration: InputDecoration(
                      labelText: 'Sufijo SKU',
                      hintText: 'Ej: FRONT',
                      prefixText: '${widget.parentProductSku}-',
                      isDense: true,
                    ),
                    onChanged: (value) => _updateComponent(
                        index, component.copyWith(skuSuffix: value)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: ValueKey(
                      'quantity_${index}_${component.quantityInSet}',
                    ),
                    initialValue: component.quantityInSet.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Cant. por juego',
                      helperText: 'Unidades físicas',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      final quantity = int.tryParse(value ?? '');
                      if (quantity == null || quantity < 1) {
                        return 'Mínimo 1';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      final quantity = int.tryParse(value);
                      if (quantity == null || quantity < 1) return;
                      _updateComponent(
                        index,
                        component.copyWith(quantityInSet: quantity),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Name field (auto-generated but editable)
            TextFormField(
              key: ValueKey(
                  'name_${index}_${component.label}_${component.name}'),
              initialValue: component.name.isEmpty
                  ? _generateComponentName(component.label)
                  : component.name,
              decoration: const InputDecoration(
                labelText: 'Nombre del Componente',
                hintText: 'Nombre completo del producto componente',
                isDense: true,
              ),
              onChanged: (value) =>
                  _updateComponent(index, component.copyWith(name: value)),
            ),
            const SizedBox(height: 12),

            // Pricing fields - Cost
            _buildCostField(theme, index, component),
            const SizedBox(height: 12),
            // Pricing fields - Price
            _buildPriceField(theme, index, component),
          ],
        ),
      ),
    );
  }

  Widget _buildCostField(
      ThemeData theme, int index, SetComponentDraft component) {
    if (_useCostRatios) {
      final ratioValue = component.costRatio != null
          ? (component.costRatio! * 100).toStringAsFixed(0)
          : '';
      final controller = _getCostController(index, ratioValue);

      return Focus(
        onFocusChange: (hasFocus) {
          if (hasFocus) {
            _editingCostIndex = index;
          } else {
            _editingCostIndex = null;
          }
        },
        child: TextFormField(
          key: ValueKey('cost_ratio_$index'),
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Costo (%)',
            hintText: '50',
            suffixText: '%',
            helperText:
                'Costo: \$${_calculateFromRatio(widget.parentCost, component.costRatio).toStringAsFixed(0)}',
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            final ratio = (double.tryParse(value) ?? 0) / 100;
            _updateCostRatioWithAutoBalance(index, ratio);
          },
        ),
      );
    } else {
      final costValue = component.cost.toStringAsFixed(0);
      final controller = _getCostController(index, costValue);

      return Focus(
        onFocusChange: (hasFocus) {
          if (hasFocus) {
            _editingCostIndex = index;
          } else {
            _editingCostIndex = null;
          }
        },
        child: TextFormField(
          key: ValueKey('cost_manual_$index'),
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Costo',
            prefixText: '\$ ',
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            final cost = double.tryParse(value) ?? 0;
            _updateCostManualWithAutoBalance(index, cost);
          },
        ),
      );
    }
  }

  Widget _buildPriceField(
      ThemeData theme, int index, SetComponentDraft component) {
    if (_usePriceRatios) {
      final ratioValue = component.priceRatio != null
          ? (component.priceRatio! * 100).toStringAsFixed(0)
          : '';
      final controller = _getPriceController(index, ratioValue);

      return Focus(
        onFocusChange: (hasFocus) {
          if (hasFocus) {
            _editingPriceIndex = index;
          } else {
            _editingPriceIndex = null;
          }
        },
        child: TextFormField(
          key: ValueKey('price_ratio_$index'),
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Precio (%)',
            hintText: '50',
            suffixText: '%',
            helperText:
                'Precio: \$${_calculateFromRatio(widget.parentPrice, component.priceRatio).toStringAsFixed(0)}',
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            final ratio = (double.tryParse(value) ?? 0) / 100;
            _updatePriceRatioWithAutoBalance(index, ratio);
          },
        ),
      );
    } else {
      final priceValue = component.price.toStringAsFixed(0);
      final controller = _getPriceController(index, priceValue);

      return Focus(
        onFocusChange: (hasFocus) {
          if (hasFocus) {
            _editingPriceIndex = index;
          } else {
            _editingPriceIndex = null;
          }
        },
        child: TextFormField(
          key: ValueKey('price_manual_$index'),
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Precio',
            prefixText: '\$ ',
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            final price = double.tryParse(value) ?? 0;
            _updatePriceManualWithAutoBalance(index, price);
          },
        ),
      );
    }
  }

  void _updateCostRatioWithAutoBalance(int changedIndex, double newRatio) {
    // Clamp ratio to valid range (0-100%)
    // For 2 components: max is 100%, for 3+: max leaves at least 0% for others
    const maxRatio = 1.0; // 100%
    final clampedRatio = newRatio.clamp(0.0, maxRatio);

    if (widget.components.length < 2) {
      // Only one component, just update it
      _updateComponent(
        changedIndex,
        widget.components[changedIndex].copyWith(
          costRatio: clampedRatio,
          cost: widget.parentCost * clampedRatio,
        ),
      );
      return;
    }

    // Auto-balance: distribute remaining ratio among other components
    final remainingRatio = (1.0 - clampedRatio).clamp(0.0, 1.0);
    final otherCount = widget.components.length - 1;
    final otherRatio = remainingRatio / otherCount;

    final updated = widget.components.asMap().entries.map((entry) {
      final i = entry.key;
      final component = entry.value;

      if (i == changedIndex) {
        return component.copyWith(
          costRatio: clampedRatio,
          cost: widget.parentCost * clampedRatio,
        );
      } else {
        return component.copyWith(
          costRatio: otherRatio,
          cost: widget.parentCost * otherRatio,
        );
      }
    }).toList();

    widget.onComponentsChanged(updated);
  }

  void _updatePriceRatioWithAutoBalance(int changedIndex, double newRatio) {
    // Clamp ratio to valid range (0-100%)
    const maxRatio = 1.0; // 100%
    final clampedRatio = newRatio.clamp(0.0, maxRatio);

    if (widget.components.length < 2) {
      // Only one component, just update it
      _updateComponent(
        changedIndex,
        widget.components[changedIndex].copyWith(
          priceRatio: clampedRatio,
          price: widget.parentPrice * clampedRatio,
        ),
      );
      return;
    }

    // Auto-balance: distribute remaining ratio among other components
    final remainingRatio = (1.0 - clampedRatio).clamp(0.0, 1.0);
    final otherCount = widget.components.length - 1;
    final otherRatio = remainingRatio / otherCount;

    final updated = widget.components.asMap().entries.map((entry) {
      final i = entry.key;
      final component = entry.value;

      if (i == changedIndex) {
        return component.copyWith(
          priceRatio: clampedRatio,
          price: widget.parentPrice * clampedRatio,
        );
      } else {
        return component.copyWith(
          priceRatio: otherRatio,
          price: widget.parentPrice * otherRatio,
        );
      }
    }).toList();

    widget.onComponentsChanged(updated);
  }

  void _updateCostManualWithAutoBalance(int changedIndex, double newCost) {
    // Clamp to valid range (0 to parent cost)
    final clampedCost = newCost.clamp(0.0, widget.parentCost);

    if (widget.components.length < 2) {
      _updateComponent(
        changedIndex,
        widget.components[changedIndex].copyWith(cost: clampedCost),
      );
      return;
    }

    // Auto-balance: distribute remaining cost among other components
    final remainingCost =
        (widget.parentCost - clampedCost).clamp(0.0, widget.parentCost);
    final otherCount = widget.components.length - 1;
    final otherCost = remainingCost / otherCount;

    final updated = widget.components.asMap().entries.map((entry) {
      final i = entry.key;
      final component = entry.value;

      if (i == changedIndex) {
        return component.copyWith(cost: clampedCost);
      } else {
        return component.copyWith(cost: otherCost);
      }
    }).toList();

    widget.onComponentsChanged(updated);
  }

  void _updatePriceManualWithAutoBalance(int changedIndex, double newPrice) {
    // Clamp to valid range (0 to parent price)
    final clampedPrice = newPrice.clamp(0.0, widget.parentPrice);

    if (widget.components.length < 2) {
      _updateComponent(
        changedIndex,
        widget.components[changedIndex].copyWith(price: clampedPrice),
      );
      return;
    }

    // Auto-balance: distribute remaining price among other components
    final remainingPrice =
        (widget.parentPrice - clampedPrice).clamp(0.0, widget.parentPrice);
    final otherCount = widget.components.length - 1;
    final otherPrice = remainingPrice / otherCount;

    final updated = widget.components.asMap().entries.map((entry) {
      final i = entry.key;
      final component = entry.value;

      if (i == changedIndex) {
        return component.copyWith(price: clampedPrice);
      } else {
        return component.copyWith(price: otherPrice);
      }
    }).toList();

    widget.onComponentsChanged(updated);
  }

  double _calculateFromRatio(double parentValue, double? ratio) {
    if (ratio == null) return 0;
    return parentValue * ratio;
  }

  String _generateComponentName(String label) {
    if (label.isEmpty) return widget.parentProductName;
    return '${widget.parentProductName} - $label';
  }

  void _autoGenerateComponents(SetType type) {
    final labels = type.defaultLabels;
    final equalRatio = 1.0 / labels.length;

    final components = labels.asMap().entries.map((entry) {
      final index = entry.key;
      final label = entry.value;
      final skuSuffix =
          label.toUpperCase().substring(0, label.length.clamp(0, 5));

      return SetComponentDraft(
        label: label,
        name: _generateComponentName(label),
        skuSuffix: skuSuffix,
        position: index + 1,
        quantityInSet: 1,
        costRatio: equalRatio,
        priceRatio: equalRatio,
        cost: widget.parentCost * equalRatio,
        price: widget.parentPrice * equalRatio,
      );
    }).toList();

    widget.onComponentsChanged(components);
  }

  void _addComponent() {
    // Calculate remaining ratios
    final usedCostRatio = _getTotalCostRatio();
    final usedPriceRatio = _getTotalPriceRatio();
    final remainingCostRatio = (1.0 - usedCostRatio).clamp(0.0, 1.0);
    final remainingPriceRatio = (1.0 - usedPriceRatio).clamp(0.0, 1.0);

    final newComponent = SetComponentDraft(
      label: 'Componente ${widget.components.length + 1}',
      name: '',
      skuSuffix: 'C${widget.components.length + 1}',
      position: widget.components.length + 1,
      quantityInSet: 1,
      costRatio: remainingCostRatio,
      priceRatio: remainingPriceRatio,
      cost: widget.parentCost * remainingCostRatio,
      price: widget.parentPrice * remainingPriceRatio,
    );

    widget.onComponentsChanged([...widget.components, newComponent]);
  }

  void _removeComponent(int index) {
    final updated = [...widget.components];
    updated.removeAt(index);
    // Re-number positions
    for (var i = 0; i < updated.length; i++) {
      updated[i] = updated[i].copyWith(position: i + 1);
    }

    // Re-balance ratios if only one component left
    if (updated.length == 1) {
      updated[0] = updated[0].copyWith(
        costRatio: 1.0,
        priceRatio: 1.0,
        cost: widget.parentCost,
        price: widget.parentPrice,
      );
    }

    widget.onComponentsChanged(updated);
  }

  void _updateComponent(int index, SetComponentDraft component) {
    final updated = [...widget.components];
    updated[index] = component;
    widget.onComponentsChanged(updated);
  }
}

/// Draft model for component being edited (before saving)
class SetComponentDraft {
  final String? productId;
  final String label;
  final String name;
  final String skuSuffix;
  final int position;
  final int quantityInSet;
  final double? costRatio;
  final double? priceRatio;
  final double cost;
  final double price;

  const SetComponentDraft({
    this.productId,
    required this.label,
    required this.name,
    required this.skuSuffix,
    required this.position,
    this.quantityInSet = 1,
    this.costRatio,
    this.priceRatio,
    required this.cost,
    required this.price,
  });

  SetComponentDraft copyWith({
    String? productId,
    String? label,
    String? name,
    String? skuSuffix,
    int? position,
    int? quantityInSet,
    double? costRatio,
    double? priceRatio,
    double? cost,
    double? price,
  }) {
    return SetComponentDraft(
      productId: productId ?? this.productId,
      label: label ?? this.label,
      name: name ?? this.name,
      skuSuffix: skuSuffix ?? this.skuSuffix,
      position: position ?? this.position,
      quantityInSet: quantityInSet ?? this.quantityInSet,
      costRatio: costRatio ?? this.costRatio,
      priceRatio: priceRatio ?? this.priceRatio,
      cost: cost ?? this.cost,
      price: price ?? this.price,
    );
  }

  /// Generate final SKU from parent SKU
  String generateSku(String parentSku) {
    return '$parentSku-$skuSuffix';
  }
}
