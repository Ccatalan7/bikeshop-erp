import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/crm_models.dart';

class CustomerService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService;

  RealtimeChannel? _customersChannel;

  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  List<Customer>? _cachedCustomers;
  DateTime? _customersCacheTime;
  List<Customer>? _cachedListCustomers;
  DateTime? _customersListCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);
  bool _isLoadingCustomers = false;
  bool _isLoadingListCustomers = false;

  // Public getters for cached data (instant access)
  List<Customer> get cachedCustomers => _cachedCustomers ?? [];
  bool get hasCustomersCache => _cachedCustomers != null;
  bool get isCustomersCacheFresh =>
      _cachedCustomers != null && _isCacheValid(_customersCacheTime);
  List<Customer> get cachedListCustomers => _cachedListCustomers ?? [];
  bool get hasListCustomersCache => _cachedListCustomers != null;
  bool get isListCustomersCacheFresh =>
      _cachedListCustomers != null && _isCacheValid(_customersListCacheTime);

  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  void invalidateCustomersCache() {
    _cachedCustomers = null;
    _customersCacheTime = null;
    _cachedListCustomers = null;
    _customersListCacheTime = null;
  }

  CustomerService(this._db, this._tenantService) {
    // Don't await - fire and forget to avoid blocking constructor
    _setupCustomersRealtime();
  }

  // Customer operations
  Future<List<Customer>> getCustomers(
      {String? searchTerm, bool forceRefresh = false, int limit = 50}) async {
    try {
      // Check if this is a filtered query
      final isFilteredQuery = searchTerm != null && searchTerm.isNotEmpty;

      // Return cached data if valid and not a filtered query
      if (!forceRefresh &&
          !isFilteredQuery &&
          _isCacheValid(_customersCacheTime) &&
          _cachedCustomers != null) {
        debugPrint(
            '📦 [CustomerService] Using cached customers (${_cachedCustomers!.length} items)');
        return _cachedCustomers!;
      }

      // Prevent concurrent fetches
      if (_isLoadingCustomers && !isFilteredQuery) {
        debugPrint('⏳ [CustomerService] Already loading customers, waiting...');
        while (_isLoadingCustomers) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        if (_cachedCustomers != null && !isFilteredQuery) {
          return _cachedCustomers!;
        }
      }

      if (!isFilteredQuery) _isLoadingCustomers = true;

      List<Map<String, dynamic>> data;

      if (searchTerm != null && searchTerm.isNotEmpty) {
        // Search by name, RUT, or email
        final nameResults =
            await _db.searchRecords('customers', 'name', searchTerm);
        final rutResults =
            await _db.searchRecords('customers', 'rut', searchTerm);
        final emailResults =
            await _db.searchRecords('customers', 'email', searchTerm);

        // Combine and deduplicate results
        final Set<String> ids = {};
        final List<Map<String, dynamic>> combined = [];

        for (var item in [...nameResults, ...rutResults, ...emailResults]) {
          final id = item['id']?.toString();
          if (id != null && ids.add(id)) {
            combined.add(item);
          }
          if (combined.length >= limit) break;
        }
        data = combined;
      } else {
        // Fetch ALL customers (uses pagination internally to bypass 1000 row limit)
        // If no searchTerm, we might want to respect the limit too, but the cache logic usually wants "all"
        data = await _db.select('customers', fetchAll: true, orderBy: 'name');
      }

      final customers = data.map((json) => Customer.fromJson(json)).toList();

      // Cache only unfiltered results
      if (!isFilteredQuery) {
        _cachedCustomers = customers;
        _customersCacheTime = DateTime.now();
        debugPrint('✅ [CustomerService] Cached ${customers.length} customers');
        _isLoadingCustomers = false;
      }

      return customers;
    } catch (e) {
      _isLoadingCustomers = false;
      if (kDebugMode) print('Error fetching customers: $e');
      rethrow;
    }
  }

  Future<List<Customer>> getCustomersForList(
      {bool forceRefresh = false}) async {
    try {
      if (!forceRefresh &&
          _isCacheValid(_customersListCacheTime) &&
          _cachedListCustomers != null) {
        debugPrint(
            '📦 [CustomerService] Using cached customer list preview (${_cachedListCustomers!.length} items)');
        return _cachedListCustomers!;
      }

      if (_isLoadingListCustomers) {
        debugPrint(
            '⏳ [CustomerService] Already loading customer list preview, waiting...');
        while (_isLoadingListCustomers) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        if (_cachedListCustomers != null) {
          return _cachedListCustomers!;
        }
      }

      _isLoadingListCustomers = true;

      final data = await _db.select(
        'customers',
        selectColumns: Customer.listPreviewSelect,
        fetchAll: true,
        orderBy: 'name',
      );

      final customers = data.map((json) => Customer.fromJson(json)).toList();
      _cachedListCustomers = customers;
      _customersListCacheTime = DateTime.now();
      debugPrint(
          '✅ [CustomerService] Cached ${customers.length} customer list preview rows');
      _isLoadingListCustomers = false;
      return customers;
    } catch (e) {
      _isLoadingListCustomers = false;
      if (kDebugMode) print('Error fetching customer list preview: $e');
      rethrow;
    }
  }

  Future<List<Customer>> getCustomersPaginated({
    required int page,
    required int pageSize,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize - 1;

      final data = await _db.selectWithPagination(
        'customers',
        from: from,
        to: to,
        orderBy: 'name',
      );

      return data.map((json) => Customer.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching customers (paginated): $e');
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
      if (customer.rut.trim().isNotEmpty) {
        if (!ChileanUtils.isValidRut(customer.rut)) {
          throw Exception('RUT inválido');
        }

        // Check if RUT already exists
        final existingCustomers =
            await _db.select('customers', where: 'rut=${customer.rut}');
        if (existingCustomers.isNotEmpty) {
          throw Exception('Ya existe un cliente con este RUT');
        }

        // Format RUT for storage
        final formattedRut = ChileanUtils.formatRut(customer.rut);
        customerToSave = customer.copyWith(rut: formattedRut);
      }

      // Add tenant_id to customer data
      final customerData = _tenantService.addTenantId(customerToSave.toJson());
      final data = await _db.insert('customers', customerData);

      // Create initial loyalty record
      final customerId = data['id']?.toString();
      if (customerId != null && customerId.isNotEmpty) {
        await _createInitialLoyalty(customerId);
      }

      invalidateCustomersCache();
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
      if (customer.rut.trim().isNotEmpty) {
        if (!ChileanUtils.isValidRut(customer.rut)) {
          throw Exception('RUT inválido');
        }

        // Check if RUT already exists (excluding current customer)
        final existingCustomers =
            await _db.select('customers', where: 'rut=${customer.rut}');
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

      final data =
          await _db.update('customers', customer.id!, customerToSave.toJson());
      invalidateCustomersCache();
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
      invalidateCustomersCache();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting customer: $e');
      rethrow;
    }
  }

  // Loyalty operations
  Future<Loyalty?> getCustomerLoyalty(String customerId) async {
    try {
      final data =
          await _db.select('loyalty', where: 'customer_id=$customerId');
      return data.isNotEmpty ? Loyalty.fromJson(data.first) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching loyalty: $e');
      return null;
    }
  }

  Future<void> _createInitialLoyalty(String customerId) async {
    try {
      if (customerId.isEmpty) return;
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return;

      final loyalty = Loyalty(
        tenantId: tenantId,
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
      if (customerId.isEmpty) {
        throw Exception('Cliente inválido');
      }
      final loyalty = await getCustomerLoyalty(customerId);
      if (loyalty == null) {
        await _createInitialLoyalty(customerId);
        await addLoyaltyPoints(customerId, points);
        return;
      }

      final newPoints = loyalty.points + points;
      final tempLoyalty = loyalty.copyWith(points: newPoints);
      final newTier = tempLoyalty.calculateTier();

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
      final tempLoyalty = loyalty.copyWith(points: newPoints);
      final newTier = tempLoyalty.calculateTier();

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
      final data =
          await _db.select('bike_history', where: 'customer_id=$customerId');
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
      final data = await _db.update(
          'bike_history', bikeHistory.id!, bikeHistory.toJson());
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
      rethrow;
    }
  }

  // Realtime subscription for customers
  Future<void> _setupCustomersRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        debugPrint('⚠️ [CustomerService] Cannot setup realtime: no tenant_id');
        return;
      }

      await _customersChannel?.unsubscribe();

      _customersChannel = Supabase.instance.client
          .channel('customers_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'customers',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              debugPrint(
                  '🔔 [CustomerService] Customer changed: ${payload.eventType}');

              if (payload.newRecord.isNotEmpty) {
                final updatedCustomer = Customer.fromJson(payload.newRecord);

                if (_cachedCustomers != null) {
                  final index = _cachedCustomers!
                      .indexWhere((c) => c.id == updatedCustomer.id);
                  if (index == -1) {
                    _cachedCustomers!.add(updatedCustomer);
                    _cachedCustomers!.sort((a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  } else {
                    _cachedCustomers![index] = updatedCustomer;
                  }
                }

                if (_cachedListCustomers != null) {
                  final index = _cachedListCustomers!
                      .indexWhere((c) => c.id == updatedCustomer.id);
                  if (index == -1) {
                    _cachedListCustomers!.add(updatedCustomer);
                    _cachedListCustomers!.sort((a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  } else {
                    _cachedListCustomers![index] = updatedCustomer;
                  }
                }
                notifyListeners();
              } else if (payload.eventType == PostgresChangeEvent.delete &&
                  payload.oldRecord.isNotEmpty) {
                final id = payload.oldRecord['id']?.toString();
                if (id != null && _cachedCustomers != null) {
                  _cachedCustomers!.removeWhere((c) => c.id == id);
                }
                if (id != null && _cachedListCustomers != null) {
                  _cachedListCustomers!.removeWhere((c) => c.id == id);
                }
                notifyListeners();
              }
            },
          )
          .subscribe();

      if (!kReleaseMode) {
        debugPrint('✅ [CustomerService] Realtime subscription active');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('❌ [CustomerService] Failed to setup realtime: $e');
      }
    }
  }

  @override
  void dispose() {
    _customersChannel?.unsubscribe();
    super.dispose();
  }
}
