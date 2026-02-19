import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modules/inventory/services/inventory_service.dart';
import '../../modules/inventory/models/inventory_models.dart';
import 'package:intl/intl.dart';

class OCRCleanupPage extends StatefulWidget {
  const OCRCleanupPage({super.key});

  @override
  State<OCRCleanupPage> createState() => _OCRCleanupPageState();
}

class _OCRCleanupPageState extends State<OCRCleanupPage> {
  bool _isLoading = true;
  List<SuspectProduct> _suspectProducts = [];
  Set<String> _selectedIds = {};
  bool _isFixing = false;

  @override
  void initState() {
    super.initState();
    _scanForSuspectProducts();
  }

  Future<void> _scanForSuspectProducts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final inventoryService =
          Provider.of<InventoryService>(context, listen: false);
      final products = await inventoryService.getProducts(forceRefresh: true);

      // Filter products created in the last 60 days (increased from 7)
      final recentProducts = products.where((p) {
        final daysSinceCreation = DateTime.now().difference(p.createdAt).inDays;
        return daysSinceCreation <= 60;
      }).toList();

      debugPrint(
          '🔍 Scanning ${recentProducts.length} recent products (last 60 days) for OCR issues...');

      final suspects = <SuspectProduct>[];

      for (final product in recentProducts) {
        // Skip if 0 stock (already correct/fixed)
        if (product.inventoryQty <= 0) continue;

        // Check movements
        final movements =
            await inventoryService.getStockMovements(productId: product.id);

        // Look for "Inventario inicial" adjustment
        StockMovement? initialMove;
        try {
          initialMove = movements.firstWhere(
            (m) =>
                m.type == StockMovementType.adjustment &&
                (m.reference?.toLowerCase().contains('inventario inicial') ??
                    false),
          );
        } catch (_) {
          // No matching movement found
        }

        // We include IT IF:
        // 1. It has "Inventario inicial" movement > 0
        // OR
        // 2. It has NO movements at all but has stock (Phantom stock)
        // OR
        // 3. We just show everything with stock created recently?
        // Let's go with permissive: Show if it has Initial Inventory OR if manually assumed.

        if (initialMove != null && initialMove.quantity > 0) {
          suspects.add(SuspectProduct(
            product: product,
            initialStock: initialMove.quantity,
            currentStock: product.inventoryQty,
            hasMovementRecord: true,
          ));
        } else if (product.inventoryQty > 0) {
          // Fallback: If product created recently has stock but we can't find the trace,
          // likely it's the issue. Show it but mark it.
          suspects.add(SuspectProduct(
            product: product,
            initialStock: product
                .inventoryQty, // Assume the entire current stock is the error if not found
            currentStock: product.inventoryQty,
            hasMovementRecord: false,
          ));
        }
      }

      // Sort by creation date (newest first)
      suspects
          .sort((a, b) => b.product.createdAt.compareTo(a.product.createdAt));

      if (mounted) {
        setState(() {
          _suspectProducts = suspects;
          // Pre-select only those with confirmed movement records to be safe,
          // let user manually check the others
          _selectedIds = suspects
              .where((s) => s.hasMovementRecord)
              .map((s) => s.product.id!)
              .toSet();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error scanning products: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al escanear: $e')),
        );
      }
    }
  }

  Future<void> _fixSelected() async {
    if (_selectedIds.isEmpty) return;

    setState(() => _isFixing = true);
    final inventoryService =
        Provider.of<InventoryService>(context, listen: false);
    int fixedCount = 0;

    try {
      for (final suspect in _suspectProducts) {
        if (!_selectedIds.contains(suspect.product.id)) continue;

        // Determine amount to deduct
        // If we found a specific initial movement, use that.
        // If not, we reset to 0 (deduct current stock).
        int amountToDeduct = suspect.hasMovementRecord
            ? suspect.initialStock
            : suspect.currentStock;

        // Safety check: ensure we don't go negative just in case
        if (suspect.product.inventoryQty - amountToDeduct < 0) {
          amountToDeduct = suspect.product.inventoryQty;
        }

        debugPrint(
            '🔧 Fixing ${suspect.product.name}: Deducting $amountToDeduct');

        await inventoryService.adjustStock(
          productId: suspect.product.id!,
          newQuantity: suspect.product.inventoryQty - amountToDeduct,
          reason: 'Corrección carga OCR (Eliminar Inventario Inicial)',
        );
        fixedCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $fixedCount productos corregidos'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh list
        _scanForSuspectProducts();
      }
    } catch (e) {
      debugPrint('Error fixing products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al corregir: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFixing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reparación de Datos OCR'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.shade50,
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Detectados ${_suspectProducts.length} productos con "Inventario Inicial" creado erróneamente en los últimos 7 días.',
                          style: TextStyle(color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            if (_selectedIds.length ==
                                _suspectProducts.length) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds = _suspectProducts
                                  .map((s) => s.product.id!)
                                  .toSet();
                            }
                          });
                        },
                        icon: Icon(
                          _selectedIds.length == _suspectProducts.length
                              ? Icons.deselect
                              : Icons.select_all,
                        ),
                        label: Text(
                          _selectedIds.length == _suspectProducts.length
                              ? 'Deseleccionar Todos'
                              : 'Seleccionar Todos',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _suspectProducts.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle,
                                  size: 64, color: Colors.green),
                              SizedBox(height: 16),
                              Text(
                                '¡Todo limpio!',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              Text('No se encontraron productos con errores.'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _suspectProducts.length,
                          itemBuilder: (context, index) {
                            final suspect = _suspectProducts[index];
                            final isSelected =
                                _selectedIds.contains(suspect.product.id);

                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIds.add(suspect.product.id!);
                                  } else {
                                    _selectedIds.remove(suspect.product.id);
                                  }
                                });
                              },
                              title: Text(suspect.product.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SKU: ${suspect.product.sku}\nCreado: ${DateFormat('dd/MM HH:mm').format(suspect.product.createdAt)}',
                                  ),
                                  if (!suspect.hasMovementRecord)
                                    const Text(
                                      '⚠️ Sin movimiento "Inventario inicial"',
                                      style: TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                ],
                              ),
                              secondary: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Actual: ${suspect.currentStock}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    suspect.hasMovementRecord
                                        ? 'Inicial: ${suspect.initialStock}'
                                        : 'A descontar: ${suspect.initialStock}',
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (_suspectProducts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isFixing ? null : _fixSelected,
                        icon: _isFixing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.build),
                        label: Text(_isFixing
                            ? 'Corrigiendo...'
                            : 'Corregir Seleccionados (${_selectedIds.length})'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class SuspectProduct {
  final Product product;
  final int initialStock;
  final int currentStock;
  final bool hasMovementRecord;

  SuspectProduct({
    required this.product,
    required this.initialStock,
    required this.currentStock,
    this.hasMovementRecord = true,
  });
}
