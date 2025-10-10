import 'package:flutter/foundation.dart';
import '../../../shared/services/database_service.dart';
import '../../accounting/services/accounting_service.dart';
import '../models/supplier.dart';
import '../models/purchase_order.dart';

class PurchaseService extends ChangeNotifier {
  final DatabaseService _db;
  static AccountingService? _accountingService;

  PurchaseService(this._db);

  // Set accounting service dependency
  static void setAccountingService(AccountingService accountingService) {
    _accountingService = accountingService;
  }

  // Supplier CRUD operations
  Future<List<Supplier>> getSuppliers({
    String? search,
    bool? isActive,
  }) async {
    try {
      final data = await _db.select('suppliers');
      List<Supplier> suppliers = data.map((json) => Supplier.fromJson(json)).toList();
      
      if (search != null && search.isNotEmpty) {
        suppliers = suppliers.where((supplier) =>
          supplier.name.toLowerCase().contains(search.toLowerCase()) ||
          (supplier.rut?.toLowerCase().contains(search.toLowerCase()) ?? false) ||
          (supplier.email?.toLowerCase().contains(search.toLowerCase()) ?? false)
        ).toList();
      }

      if (isActive != null) {
        suppliers = suppliers.where((supplier) => supplier.isActive == isActive).toList();
      }

      return suppliers..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      throw Exception('Error loading suppliers: $e');
    }
  }

  Future<Supplier?> getSupplier(int id) async {
    try {
      final data = await _db.selectById('suppliers', id.toString());
      if (data != null) {
        return Supplier.fromJson(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Supplier> createSupplier(Supplier supplier) async {
    try {
      final supplierData = supplier.toJson();
      supplierData.remove('id');
      supplierData.remove('created_at');
      supplierData.remove('updated_at');

      final result = await _db.insert('suppliers', supplierData);
      
      return supplier.copyWith(id: result['id']);
    } catch (e) {
      throw Exception('Error creating supplier: $e');
    }
  }

  Future<Supplier> updateSupplier(Supplier supplier) async {
    try {
      final supplierData = supplier.toJson();
      supplierData.remove('created_at');

      await _db.update('suppliers', supplier.id.toString(), supplierData);
      
      return supplier;
    } catch (e) {
      throw Exception('Error updating supplier: $e');
    }
  }

  Future<void> deleteSupplier(int id) async {
    try {
      await _db.delete('suppliers', id.toString());
    } catch (e) {
      throw Exception('Error deleting supplier: $e');
    }
  }

  // Purchase Order CRUD operations
  Future<List<PurchaseOrder>> getPurchaseOrders({
    int? supplierId,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final data = await _db.select('purchase_orders');
      List<PurchaseOrder> orders = data.map((json) => PurchaseOrder.fromJson(json)).toList();

      if (supplierId != null) {
        orders = orders.where((order) => order.supplierId == supplierId).toList();
      }

      if (status != null) {
        orders = orders.where((order) => order.status == status).toList();
      }

      if (fromDate != null) {
        orders = orders.where((order) => order.date.isAfter(fromDate) || order.date.isAtSameMomentAs(fromDate)).toList();
      }

      if (toDate != null) {
        orders = orders.where((order) => order.date.isBefore(toDate) || order.date.isAtSameMomentAs(toDate)).toList();
      }

      return orders..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      throw Exception('Error loading purchase orders: $e');
    }
  }

  Future<PurchaseOrder?> getPurchaseOrder(int id) async {
    try {
      final data = await _db.selectById('purchase_orders', id.toString());
      if (data != null) {
        final order = PurchaseOrder.fromJson(data);
        
        // For now, return order without items (stub implementation)
        // TODO: Load items when database service supports complex queries
        
        return order;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<PurchaseOrder> createPurchaseOrder(PurchaseOrder order) async {
    try {
      final orderData = order.toJson();
      orderData.remove('id');
      orderData.remove('created_at');
      orderData.remove('updated_at');
      orderData.remove('items');

      final result = await _db.insert('purchase_orders', orderData);

      // For stub implementation, just return the order with the new ID
      // TODO: Create order items when database service supports it
      
      return order.copyWith(id: result['id']);
    } catch (e) {
      throw Exception('Error creating purchase order: $e');
    }
  }

  Future<PurchaseOrder> updatePurchaseOrder(PurchaseOrder order) async {
    try {
      final orderData = order.toJson();
      orderData.remove('created_at');
      orderData.remove('items');

      await _db.update('purchase_orders', order.id.toString(), orderData);

      // For stub implementation, just return the order
      // TODO: Update order items when database service supports it
      
      return order;
    } catch (e) {
      throw Exception('Error updating purchase order: $e');
    }
  }

  Future<void> deletePurchaseOrder(int id) async {
    try {
      // For stub implementation, just delete the main order
      // TODO: Delete order items when database service supports it
      await _db.delete('purchase_orders', id.toString());
    } catch (e) {
      throw Exception('Error deleting purchase order: $e');
    }
  }

  Future<PurchaseOrder> receivePurchaseOrder(int id) async {
    try {
      final order = await getPurchaseOrder(id);
      if (order == null) {
        throw Exception('Purchase order not found');
      }

      // Update status
      final updatedOrder = order.copyWith(status: 'received');
      await updatePurchaseOrder(updatedOrder);

      // Update inventory for each item
      for (final item in order.items) {
        await _updateInventory(item.productId, item.quantity, item.unitCost);
      }

      // Create accounting entries
      await _createAccountingEntries(id, updatedOrder);

      notifyListeners();
      return updatedOrder;
    } catch (e) {
      throw Exception('Error receiving purchase order: $e');
    }
  }

  Future<void> _updateInventory(int productId, int quantityReceived, double unitCost) async {
    try {
      // Stub implementation - would normally update product inventory
      debugPrint('Would update inventory for product $productId: +$quantityReceived units at \$${unitCost.toStringAsFixed(2)} each');
    } catch (e) {
      debugPrint('Error updating inventory: $e');
    }
  }

  Future<void> _createAccountingEntries(int orderId, PurchaseOrder order) async {
    try {
      if (_accountingService == null) {
        debugPrint('Accounting service not set, skipping accounting entries');
        return;
      }

      await _accountingService!.postPurchaseEntry(
        date: DateTime.now(),
        supplierName: 'Proveedor ${order.supplierId}', // TODO: Get actual supplier name
        invoiceNumber: 'PO-${order.orderNumber}',
        subtotal: order.subtotal,
        ivaAmount: order.tax,
        total: order.total,
      );
    } catch (e) {
      debugPrint('Error creating accounting entries: $e');
    }
  }
}
