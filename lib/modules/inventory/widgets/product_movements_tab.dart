import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/stock_movement.dart';
import '../services/stock_movements_service.dart';

class ProductMovementsTab extends StatefulWidget {
  final String productId;

  const ProductMovementsTab({super.key, required this.productId});

  @override
  State<ProductMovementsTab> createState() => _ProductMovementsTabState();
}

class _ProductMovementsTabState extends State<ProductMovementsTab> {
  bool _isLoading = true;
  List<StockMovement> _movements = [];
  String? _error;
  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProductMovementsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      _loadMovements();
    }
  }

  Future<void> _loadMovements() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = context.read<StockMovementsService>();
      final movements = await service.getMovementsList(widget.productId);

      if (mounted) {
        setState(() {
          _movements = movements;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error cargando movimientos';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24.0),
        child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            TextButton(
                onPressed: _loadMovements, child: const Text('Reintentar'))
          ],
        ),
      );
    }

    if (_movements.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history,
                size: 48, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'Sin movimientos recientes',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);

    // Hybrid Layout: Horizontal Scroll but List Look
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(800, constraints.maxWidth),
              // 800px min width to fit all data comfortably
              height:
                  constraints.maxHeight.isFinite ? constraints.maxHeight : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Minimal Header
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5))),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 40 + 12), // Spacer for Icon
                        SizedBox(
                            width: 120,
                            child: Text("FECHA",
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant))),
                        SizedBox(
                            width: 140,
                            child: Text("TIPO / ORIGEN",
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant))),
                        SizedBox(
                            width: 120,
                            child: Text("REFERENCIA",
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant))),
                        Expanded(child: Container()), // Spacer
                        SizedBox(
                            width: 70,
                            child: Text("INICIAL",
                                textAlign: TextAlign.right,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant))),
                        const SizedBox(width: 16),
                        SizedBox(
                            width: 70,
                            child: Text("CAMBIO",
                                textAlign: TextAlign.right,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant))),
                        const SizedBox(width: 16),
                        SizedBox(
                            width: 70,
                            child: Text("FINAL",
                                textAlign: TextAlign.right,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant))),
                      ],
                    ),
                  ),

                  // List Content
                  Expanded(
                    child: ListView.separated(
                      itemCount: _movements.length,
                      separatorBuilder: (ctx, i) => Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.2)),
                      itemBuilder: (context, index) {
                        return _buildMovementRow(context, _movements[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMovementRow(BuildContext context, StockMovement move) {
    final theme = Theme.of(context);
    final isPositive = move.quantity > 0;
    final color = isPositive ? Colors.green : Colors.red;

    final dateStr =
        DateFormat('dd MMM yyyy, HH:mm').format(move.transactionDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 1. Icon (Visual Anchor)
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPositive
                  ? Icons.add_circle_outline
                  : Icons.remove_circle_outline,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),

          // 2. Date
          SizedBox(
            width: 120,
            child: Text(
              dateStr,
              style: theme.textTheme.bodyMedium,
            ),
          ),

          // 3. Type / Source
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  move.movementTypeDisplay.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  move.sourceDisplay,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              ],
            ),
          ),

          // 4. Reference
          SizedBox(
            width: 120,
            child: move.referenceNumber != null
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      move.referenceNumber!,
                      style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace', fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : Text('-', style: theme.textTheme.bodySmall),
          ),

          Expanded(child: Container()), // Flexible space

          // 5. Stock Stats Group
          // Initial
          SizedBox(
            width: 70,
            child: Text(
              move.stockBefore.toString(),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Change
          SizedBox(
            width: 70,
            child: Text(
              '${isPositive ? '+' : ''}${move.quantity}',
              textAlign: TextAlign.right,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Final
          SizedBox(
            width: 70,
            child: Text(
              move.stockAfter.toString(),
              textAlign: TextAlign.right,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
