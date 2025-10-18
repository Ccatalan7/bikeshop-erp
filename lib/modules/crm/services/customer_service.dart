import 'package:flutter/foundation.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/crm_models.dart';

class CustomerService extends ChangeNotifier {
  final DatabaseService _db;
  
  CustomerService(this._db);
  
  // Customer operations
  Future<List<Customer>> getCustomers({String? searchTerm}) async {
    try {
      List<Map<String, dynamic>> data;
      
      if (searchTerm != null && searchTerm.isNotEmpty) {
        // Search by name, RUT, or email
        final nameResults = await _db.searchRecords('customers', 'name', searchTerm);
        final rutResults = await _db.searchRecords('customers', 'rut', searchTerm);
        final emailResults = await _db.searchRecords('customers', 'email', searchTerm);
        
        // Combine and deduplicate results
        final Set<String> ids = {};
        data = [...nameResults, ...rutResults, ...emailResults]
            .where((item) {
              final id = item['id']?.toString();
              if (id == null) return true;
              return ids.add(id);
            })
            .toList();
      } else {
        data = await _db.select('customers');
      }
      
      return data.map((json) => Customer.fromJson(json)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      if (kDebugMode) print('Error fetching customers: $e');
      rethrow;
    }
  }
  
  Future<Customer?> getCustomerById(String id) async {
    try {
      if (id.isEmpty) return null;
      final data = await _db.selectById('customers', id);
      return data != null ? Customer.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching customer: $e');
      rethrow;
    }
  }
  
  Future<Customer> createCustomer(Customer customer) async {
    try {
      Customer customerToSave = customer;
      
      // Validate RUT only if provided (not null and not empty)
      if (customer.rut != null && customer.rut.trim().isNotEmpty) {
        if (!ChileanUtils.isValidRut(customer.rut)) {
          throw Exception('RUT inválido');
        }
        
        // Check if RUT already exists
        final existingCustomers = await _db.select('customers', where: 'rut=${customer.rut}');
        if (existingCustomers.isNotEmpty) {
          throw Exception('Ya existe un cliente con este RUT');
        }
        
        // Format RUT for storage
        final formattedRut = ChileanUtils.formatRut(customer.rut);
        customerToSave = customer.copyWith(rut: formattedRut);
      }
      
      final data = await _db.insert('customers', customerToSave.toJson());
      
      // Create initial loyalty record
      final customerId = data['id']?.toString();
      if (customerId != null && customerId.isNotEmpty) {
        await _createInitialLoyalty(customerId);
      }
      
      notifyListeners();
      return Customer.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating customer: $e');
      rethrow;
    }
  }
  
  Future<Customer> updateCustomer(Customer customer) async {
    try {
      Customer customerToSave = customer.copyWith(updatedAt: DateTime.now());
      
      // Validate RUT only if provided (not null and not empty)
      if (customer.rut != null && customer.rut.trim().isNotEmpty) {
        if (!ChileanUtils.isValidRut(customer.rut)) {
          throw Exception('RUT inválido');
        }
        
        // Check if RUT already exists (excluding current customer)
        final existingCustomers = await _db.select('customers', where: 'rut=${customer.rut}');
        final duplicates = existingCustomers.where((c) {
          final existingId = c['id']?.toString();
          return existingId != null && existingId != customer.id;
        }).toList();
        if (duplicates.isNotEmpty) {
          throw Exception('Ya existe otro cliente con este RUT');
        }
        
        // Format RUT for storage
        final formattedRut = ChileanUtils.formatRut(customer.rut);
        customerToSave = customer.copyWith(
          rut: formattedRut,
          updatedAt: DateTime.now(),
        );
      }
      
      if (customer.id == null) {
        throw Exception('ID de cliente inválido');
      }

      final data = await _db.update('customers', customer.id!, customerToSave.toJson());
      notifyListeners();
      return Customer.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating customer: $e');
      rethrow;
    }
  }
  
  Future<void> deleteCustomer(String id) async {
    try {
      if (id.isEmpty) {
        throw Exception('ID de cliente inválido');
      }
      await _db.delete('customers', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting customer: $e');
      rethrow;
    }
  }
  
  // Loyalty operations
  Future<Loyalty?> getCustomerLoyalty(String customerId) async {
    try {
      final data = await _db.select('loyalty', where: 'customer_id=$customerId');
      return data.isNotEmpty ? Loyalty.fromJson(data.first) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching loyalty: $e');
      return null;
    }
  }
  
  Future<void> _createInitialLoyalty(String customerId) async {
    try {
      if (customerId.isEmpty) return;
      final loyalty = Loyalty(
        customerId: customerId,
        points: 0,
        tier: LoyaltyTier.bronze,
        lastUpdated: DateTime.now(),
      );
      
      await _db.insert('loyalty', loyalty.toJson());
    } catch (e) {
      if (kDebugMode) print('Error creating initial loyalty: $e');
      // Don't throw, as this is not critical
    }
  }
  
  Future<void> addLoyaltyPoints(String customerId, int points) async {
    try {
      if (customerId.isEmpty) return;
      final loyalty = await getCustomerLoyalty(customerId);
      if (loyalty == null) {
        await _createInitialLoyalty(customerId);
        await addLoyaltyPoints(customerId, points);
        return;
      }
      
      final newPoints = loyalty.points + points;
      final newTier = Loyalty(
        customerId: customerId,
        points: newPoints,
      ).calculateTier();
      
      final updatedLoyalty = loyalty.copyWith(
        points: newPoints,
        tier: newTier,
        lastUpdated: DateTime.now(),
      );
      
      if (loyalty.id == null) {
        throw Exception('ID de lealtad inválido');
      }

      await _db.update('loyalty', loyalty.id!, updatedLoyalty.toJson());
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error adding loyalty points: $e');
      rethrow;
    }
  }
  
  Future<void> redeemLoyaltyPoints(String customerId, int points) async {
    try {
      if (customerId.isEmpty) {
        throw Exception('Cliente inválido');
      }
      final loyalty = await getCustomerLoyalty(customerId);
      if (loyalty == null || loyalty.points < points) {
        throw Exception('Puntos insuficientes');
      }
      
      final newPoints = loyalty.points - points;
      final newTier = Loyalty(
        customerId: customerId,
        points: newPoints,
      ).calculateTier();
      
      final updatedLoyalty = loyalty.copyWith(
        points: newPoints,
        tier: newTier,
        lastUpdated: DateTime.now(),
      );
      
      if (loyalty.id == null) {
        throw Exception('ID de lealtad inválido');
      }

      await _db.update('loyalty', loyalty.id!, updatedLoyalty.toJson());
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error redeeming loyalty points: $e');
      rethrow;
    }
  }
  
  // Bike history operations
  Future<List<BikeHistory>> getCustomerBikeHistory(String customerId) async {
    try {
      if (customerId.isEmpty) return [];
      final data = await _db.select('bike_history', where: 'customer_id=$customerId');
      return data.map((json) => BikeHistory.fromJson(json)).toList()
        ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    } catch (e) {
      if (kDebugMode) print('Error fetching bike history: $e');
      return [];
    }
  }
  
  Future<BikeHistory> addBikeToHistory(BikeHistory bikeHistory) async {
    try {
      if (bikeHistory.customerId.isEmpty) {
        throw Exception('Cliente inválido');
      }
      final data = await _db.insert('bike_history', bikeHistory.toJson());
      
      // Award loyalty points for purchase (1 point per $1000 CLP)
      final points = (bikeHistory.purchaseAmount / 1000).floor();
      if (points > 0) {
        await addLoyaltyPoints(bikeHistory.customerId, points);
      }
      
      notifyListeners();
      return BikeHistory.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error adding bike to history: $e');
      rethrow;
    }
  }
  
  Future<BikeHistory> updateBikeHistory(BikeHistory bikeHistory) async {
    try {
      if (bikeHistory.id == null) {
        throw Exception('ID de bicicleta inválido');
      }
      final data = await _db.update('bike_history', bikeHistory.id!, bikeHistory.toJson());
      notifyListeners();
      return BikeHistory.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating bike history: $e');
      rethrow;
    }
  }
  
  Future<void> deleteBikeHistory(String id) async {
    try {
      if (id.isEmpty) {
        throw Exception('ID de historial inválido');
      }
      await _db.delete('bike_history', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting bike history: $e');
      rethrow;
    }
  }
  
  // Analytics and reports
  Future<Map<String, dynamic>> getCustomerAnalytics() async {
    try {
      final customers = await getCustomers();
      final totalCustomers = customers.length;
      final activeCustomers = customers.where((c) => c.isActive).length;
      
      // Region distribution
      final regionDistribution = <String, int>{};
      for (final customer in customers) {
        if (customer.region != null) {
          regionDistribution[customer.region!] = 
              (regionDistribution[customer.region!] ?? 0) + 1;
        }
      }
      
      return {
        'total_customers': totalCustomers,
        'active_customers': activeCustomers,
        'inactive_customers': totalCustomers - activeCustomers,
        'region_distribution': regionDistribution,
      };
    } catch (e) {
      if (kDebugMode) print('Error getting customer analytics: $e');
      return {};
    }
  }
}
