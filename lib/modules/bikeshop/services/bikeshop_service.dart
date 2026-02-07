import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/bikeshop_models.dart';
import '../../sales/models/sales_models.dart'; // ✅ UNIFIED ARCHITECTURE (Nov 18, 2025)

// Helper to parse dates from JSON
DateTime _parseDateTime(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return DateTime.now();
}

class BikeshopService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService = TenantService();

  RealtimeChannel? _mechanicJobsChannel;
  RealtimeChannel? _salesInvoicesChannel; // For invoice status updates
  Timer? _notifyDebounceTimer;

  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  List<MechanicJob>? _cachedJobs;
  List<Bike>? _cachedBikes;
  DateTime? _jobsCacheTime;
  DateTime? _bikesCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);

  // Loading state flags to prevent concurrent fetches
  bool _isLoadingJobs = false;
  bool _isLoadingBikes = false;

  // Public getters for cached data (instant access)
  List<MechanicJob> get cachedJobs => _cachedJobs ?? [];
  List<Bike> get cachedBikes => _cachedBikes ?? [];
  bool get hasJobsCache => _cachedJobs != null;
  bool get hasBikesCache => _cachedBikes != null;

  /// Check if cache is still valid
  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  /// Invalidate caches (call after create/update/delete)
  void invalidateJobsCache() {
    _cachedJobs = null;
    _jobsCacheTime = null;
  }

  void invalidateBikesCache() {
    _cachedBikes = null;
    _bikesCacheTime = null;
  }

  // ============================================================
  // PEGAS TABLE STATE PERSISTENCE
  // Stores filter/pagination state so it persists across navigation
  // ============================================================
  int pegasCurrentPage = 0;
  int pegasRowsPerPage = 25;
  String? pegasSortColumn = 'arrival_date';
  bool pegasSortAscending = false;
  String pegasStatusFilter = 'active';
  Set<String> pegasCustomStatusFilter = {};
  bool pegasStatusFilterExcludeMode = false;
  Set<String> pegasPriorityFilter = {};
  bool pegasShowOnlyOverdue = false;
  bool pegasShowOnlyUnpaid = false;
  String pegasSearchTerm = '';
  String pegasViewMode = 'table';

  BikeshopService(this._db) {
    // Fire and forget - with debouncing, realtime is now safe!
    _setupMechanicJobsRealtime();
    _setupSalesInvoicesRealtime(); // Also listen to invoice changes (for payment status)
  }

  // ============================================================
  // BIKE OPERATIONS
  // ============================================================

  /// Get bikes with caching. Use forceRefresh=true to bypass cache.
  Future<List<Bike>> getBikes({
    String? customerId,
    String? searchTerm,
    bool forceRefresh = false,
  }) async {
    // For filtered queries, always fetch fresh (but still cache the full list)
    final isFilteredQuery = (customerId != null && customerId.isNotEmpty) ||
        (searchTerm != null && searchTerm.isNotEmpty);

    // Return cached data if valid and not a filtered query
    if (!forceRefresh &&
        !isFilteredQuery &&
        _isCacheValid(_bikesCacheTime) &&
        _cachedBikes != null) {
      debugPrint(
          '📦 [BikeshopService] Using cached bikes (${_cachedBikes!.length} items)');
      return _cachedBikes!;
    }

    // Prevent concurrent fetches
    if (_isLoadingBikes && !isFilteredQuery) {
      debugPrint('⏳ [BikeshopService] Already loading bikes, waiting...');
      // Wait for existing fetch to complete
      while (_isLoadingBikes) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_cachedBikes != null) return _cachedBikes!;
    }

    try {
      if (!isFilteredQuery) _isLoadingBikes = true;

      List<Map<String, dynamic>> data;

      if (searchTerm != null && searchTerm.isNotEmpty) {
        // Search by brand, model, serial number
        final brandResults =
            await _db.searchRecords('bikes', 'brand', searchTerm);
        final modelResults =
            await _db.searchRecords('bikes', 'model', searchTerm);
        final serialResults =
            await _db.searchRecords('bikes', 'serial_number', searchTerm);

        // Combine and deduplicate results
        final Set<String> ids = {};
        data =
            [...brandResults, ...modelResults, ...serialResults].where((item) {
          final id = item['id']?.toString();
          if (id == null) return true;
          return ids.add(id);
        }).toList();
      } else if (customerId != null && customerId.isNotEmpty) {
        data = await _db.select('bikes',
            where: 'customer_id=$customerId', fetchAll: true);
      } else {
        data = await _db.select('bikes', fetchAll: true);
      }

      final bikes = data.map((json) => Bike.fromJson(json)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Cache only unfiltered results
      if (!isFilteredQuery) {
        _cachedBikes = bikes;
        _bikesCacheTime = DateTime.now();
        debugPrint('✅ [BikeshopService] Cached ${bikes.length} bikes');
      }

      return bikes;
    } catch (e) {
      if (kDebugMode) print('Error fetching bikes: $e');
      rethrow;
    } finally {
      if (!isFilteredQuery) _isLoadingBikes = false;
    }
  }

  Future<Bike?> getBikeById(String id) async {
    try {
      if (id.isEmpty) return null;
      final data = await _db.selectById('bikes', id);
      return data != null ? Bike.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching bike: $e');
      rethrow;
    }
  }

  Future<Bike> createBike(Bike bike) async {
    try {
      final data = await _db.insert('bikes', bike.toJson());
      invalidateBikesCache();
      notifyListeners();
      return Bike.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating bike: $e');
      rethrow;
    }
  }

  Future<Bike> updateBike(Bike bike) async {
    try {
      if (bike.id == null || bike.id!.isEmpty) {
        throw Exception('ID de bicicleta inválido');
      }
      final data = await _db.update('bikes', bike.id!, bike.toJson());
      invalidateBikesCache();
      notifyListeners();
      return Bike.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating bike: $e');
      rethrow;
    }
  }

  Future<void> deleteBike(String id) async {
    try {
      if (id.isEmpty) throw Exception('ID de bicicleta inválido');
      await _db.delete('bikes', id);
      invalidateBikesCache();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting bike: $e');
      rethrow;
    }
  }

  // ============================================================
  // BIKE BRAND OPERATIONS
  // ============================================================

  Future<List<BikeBrand>> getBikeBrands({bool activeOnly = true}) async {
    try {
      final query = activeOnly ? 'is_active=true' : null;
      final data = await _db.select('bike_brands', where: query);
      return data.map((json) => BikeBrand.fromJson(json)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      if (kDebugMode) print('Error fetching bike brands: $e');
      rethrow;
    }
  }

  Future<BikeBrand?> getBikeBrandById(String id) async {
    try {
      if (id.isEmpty) return null;
      final data = await _db.selectById('bike_brands', id);
      return data != null ? BikeBrand.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching bike brand: $e');
      rethrow;
    }
  }

  Future<BikeBrand> createBikeBrand(BikeBrand brand) async {
    try {
      final data = await _db.insert('bike_brands', brand.toJson());
      notifyListeners();
      return BikeBrand.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating bike brand: $e');
      rethrow;
    }
  }

  Future<BikeBrand> updateBikeBrand(BikeBrand brand) async {
    try {
      if (brand.id == null || brand.id!.isEmpty) {
        throw Exception('ID de marca inválido');
      }
      final data = await _db.update('bike_brands', brand.id!, brand.toJson());
      notifyListeners();
      return BikeBrand.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating bike brand: $e');
      rethrow;
    }
  }

  Future<void> deleteBikeBrand(String id) async {
    try {
      if (id.isEmpty) throw Exception('ID de marca inválido');
      await _db.delete('bike_brands', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting bike brand: $e');
      rethrow;
    }
  }

  // ============================================================
  // BIKE MODEL OPERATIONS
  // ============================================================

  Future<List<BikeModel>> getBikeModels({
    String? brandId,
    bool activeOnly = true,
  }) async {
    try {
      final client = Supabase.instance.client;
      dynamic query = client.from('bike_models').select();

      if (brandId != null && brandId.isNotEmpty) {
        query = query.eq('brand_id', brandId);
      }

      if (activeOnly) {
        query = query.eq('is_active', true);
      }

      final data = await query as List;
      return data
          .map((json) => BikeModel.fromJson(json as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      if (kDebugMode) print('Error fetching bike models: $e');
      rethrow;
    }
  }

  Future<BikeModel?> getBikeModelById(String id) async {
    try {
      if (id.isEmpty) return null;
      final data = await _db.selectById('bike_models', id);
      return data != null ? BikeModel.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching bike model: $e');
      rethrow;
    }
  }

  Future<BikeModel> createBikeModel(BikeModel model) async {
    try {
      final data = await _db.insert('bike_models', model.toJson());
      notifyListeners();
      return BikeModel.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating bike model: $e');
      rethrow;
    }
  }

  Future<BikeModel> updateBikeModel(BikeModel model) async {
    try {
      if (model.id == null || model.id!.isEmpty) {
        throw Exception('ID de modelo inválido');
      }
      final data = await _db.update('bike_models', model.id!, model.toJson());
      notifyListeners();
      return BikeModel.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating bike model: $e');
      rethrow;
    }
  }

  Future<void> deleteBikeModel(String id) async {
    try {
      if (id.isEmpty) throw Exception('ID de modelo inválido');
      await _db.delete('bike_models', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting bike model: $e');
      rethrow;
    }
  }

  // ============================================================
  // PEGA (MECHANIC JOB) OPERATIONS
  // ✅ UNIFIED ARCHITECTURE (Nov 18, 2025): Now queries sales_invoices
  // ============================================================

  /// Convert Invoice to MechanicJob for backward compatibility
  MechanicJob _invoiceToMechanicJob(Invoice invoice) {
    return MechanicJob(
      id: invoice.id,
      tenantId: invoice.tenantId,
      jobNumber: invoice.jobNumber ?? invoice.invoiceNumber,
      customerId: invoice.customerId ?? '',
      bikeId: invoice.bikeId ?? '',
      arrivalDate: invoice.entryDate ?? invoice.date,
      deliveryDeadline: invoice.dueDate,
      status: _invoiceStatusToJobStatus(invoice.status),
      clientRequest: invoice.workDescription,
      diagnosis: invoice.workDescription,
      workPerformed: invoice.workDescription,
      notes: invoice.notes,
      partsCost: invoice.subtotal,
      laborCost: 0,
      totalCost: invoice.total,
      createdAt: invoice.createdAt,
      updatedAt: invoice.updatedAt,
    );
  }

  JobStatus _invoiceStatusToJobStatus(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return JobStatus.pendiente;
      case InvoiceStatus.confirmed:
        return JobStatus.finalizado;
      case InvoiceStatus.paid:
        return JobStatus.entregado;
      case InvoiceStatus.cancelled:
        return JobStatus.cancelado;
      default:
        return JobStatus.pendiente;
    }
  }

  InvoiceStatus _jobStatusToInvoiceStatus(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
      case JobStatus.diagnostico:
      case JobStatus.esperandoAprobacion:
      case JobStatus.esperandoRepuestos:
      case JobStatus.enCurso:
        return InvoiceStatus.draft;
      case JobStatus.finalizado:
        return InvoiceStatus.confirmed;
      case JobStatus.entregado:
        return InvoiceStatus.paid;
      case JobStatus.cancelado:
        return InvoiceStatus.cancelled;
    }
  }

  /// Get jobs with caching. Use forceRefresh=true to bypass cache.
  Future<List<MechanicJob>> getJobs({
    String? customerId,
    String? bikeId,
    JobStatus? status,
    String? searchTerm,
    bool includeCompleted = true,
    bool includeDeleted = false,
    bool forceRefresh = false,
  }) async {
    // Check if this is a filtered query
    final isFilteredQuery = (customerId != null && customerId.isNotEmpty) ||
        (bikeId != null && bikeId.isNotEmpty) ||
        status != null ||
        (searchTerm != null && searchTerm.isNotEmpty) ||
        !includeCompleted ||
        includeDeleted;

    // Return cached data if valid and not a filtered query
    if (!forceRefresh &&
        !isFilteredQuery &&
        _isCacheValid(_jobsCacheTime) &&
        _cachedJobs != null) {
      debugPrint(
          '📦 [BikeshopService] Using cached jobs (${_cachedJobs!.length} items)');
      return _cachedJobs!;
    }

    // Prevent concurrent fetches
    if (_isLoadingJobs && !isFilteredQuery) {
      debugPrint('⏳ [BikeshopService] Already loading jobs, waiting...');
      while (_isLoadingJobs) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_cachedJobs != null && !isFilteredQuery) return _cachedJobs!;
    }

    try {
      if (!isFilteredQuery) _isLoadingJobs = true;

      // Join with job_statuses to get custom status details
      var query = Supabase.instance.client.from('mechanic_jobs').select('''
        *,
        job_status:job_statuses(*)
      ''');

      // Filter out soft-deleted jobs by default
      if (!includeDeleted) {
        query = query.isFilter('deleted_at', null);
      }

      if (customerId != null && customerId.isNotEmpty) {
        query = query.eq('customer_id', customerId);
      }

      if (bikeId != null && bikeId.isNotEmpty) {
        query = query.eq('bike_id', bikeId);
      }

      if (status != null) {
        query = query.eq('status', status.name);
      }

      if (!includeCompleted) {
        query = query.not('status', 'in', '(FINALIZADO,ENTREGADO,CANCELADO)');
      }

      final data = await query as List<dynamic>;

      var jobs = data
          .map((json) => MechanicJob.fromJson(json as Map<String, dynamic>))
          .toList();

      if (searchTerm != null && searchTerm.isNotEmpty) {
        final searchLower = searchTerm.toLowerCase();
        jobs = jobs.where((job) {
          final jobNumber = (job.jobNumber ?? '').toLowerCase();
          final diagnosis = job.diagnosis?.toLowerCase() ?? '';
          final clientRequest = job.clientRequest?.toLowerCase() ?? '';
          return jobNumber.contains(searchLower) ||
              diagnosis.contains(searchLower) ||
              clientRequest.contains(searchLower);
        }).toList();
      }

      jobs.sort((a, b) => b.arrivalDate.compareTo(a.arrivalDate));

      // Cache only unfiltered results
      if (!isFilteredQuery) {
        _cachedJobs = jobs;
        _jobsCacheTime = DateTime.now();
        debugPrint('✅ [BikeshopService] Cached ${jobs.length} jobs');
      }

      return jobs;
    } catch (e) {
      if (kDebugMode) print('Error fetching jobs: $e');
      rethrow;
    } finally {
      if (!isFilteredQuery) _isLoadingJobs = false;
    }
  }

  Future<MechanicJob?> getJobById(String id) async {
    try {
      if (id.isEmpty) return null;

      // Join with job_statuses to get custom status details
      final data = await Supabase.instance.client
          .from('mechanic_jobs')
          .select('''
            *,
            job_status:job_statuses(*)
          ''')
          .eq('id', id)
          .isFilter('deleted_at', null) // Filter out soft-deleted
          .maybeSingle();

      return data != null ? MechanicJob.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching job: $e');
      rethrow;
    }
  }

  Future<MechanicJob> createJob(MechanicJob job) async {
    try {
      final jobData = job.toJson();

      // 🔍 DEBUG: Log what we're sending to database
      if (kDebugMode) {
        print('📤 [CREATE JOB] Sending data to database:');
        print(
            '   job_number in data: ${jobData.containsKey('job_number') ? jobData['job_number'] : 'NOT INCLUDED (DB will generate)'}');
        print('   Full data: $jobData');
      }

      final data = await _db.insert('mechanic_jobs', jobData);

      if (kDebugMode) {
        print(
            '✅ [CREATE JOB] Database returned: job_number=${data['job_number']}');
      }

      invalidateJobsCache();
      notifyListeners();
      return MechanicJob.fromJson(data);
    } catch (e) {
      if (kDebugMode) {
        print('❌ [CREATE JOB ERROR] $e');
        print('   jobNumber field value: ${job.jobNumber}');
        print('   jobNumber is null: ${job.jobNumber == null}');
        print('   jobNumber is empty: ${job.jobNumber?.isEmpty}');
      }
      rethrow;
    }
  }

  Future<MechanicJob> updateJob(MechanicJob job) async {
    try {
      if (job.id == null || job.id!.isEmpty) {
        throw Exception('ID de trabajo inválido');
      }

      // Use forUpdate: true to exclude arrival_date and created_at from being overwritten
      final data = await _db.update(
          'mechanic_jobs', job.id!, job.toJson(forUpdate: true));
      invalidateJobsCache();
      notifyListeners();
      return MechanicJob.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating job: $e');
      rethrow;
    }
  }

  Future<void> deleteJob(String id) async {
    try {
      if (id.isEmpty) throw Exception('ID de trabajo inválido');
      await _db.delete('mechanic_jobs', id);
      invalidateJobsCache();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting job: $e');
      rethrow;
    }
  }

  Future<MechanicJob> updateJobStatus(String jobId, JobStatus newStatus) async {
    try {
      if (kDebugMode) {
        print('🔄 [STATUS CHANGE] Job $jobId → ${newStatus.displayName}');
      }

      final job = await getJobById(jobId);
      if (job == null) throw Exception('Trabajo no encontrado');

      if (kDebugMode) {
        print(
            '🔍 [FETCHED JOB] Costs: parts=${job.partsCost}, labor=${job.laborCost}, total=${job.totalCost}');
      }

      final updatedJob = job.copyWith(status: newStatus);

      if (kDebugMode) {
        print(
            '🔍 [AFTER COPYWITH] Costs: parts=${updatedJob.partsCost}, labor=${updatedJob.laborCost}, total=${updatedJob.totalCost}');
      }

      return await updateJob(updatedJob);
    } catch (e) {
      if (kDebugMode) print('Error updating job status: $e');
      rethrow;
    }
  }

  // ============================================================
  // PEGA LINE ITEMS OPERATIONS (Parts & Labor)
  // ✅ Uses mechanic_job_items table
  // ============================================================

  Future<List<MechanicJobItem>> getJobItems(String jobId) async {
    try {
      final data = await Supabase.instance.client
          .from('mechanic_job_items')
          .select()
          .eq('job_id', jobId);

      return (data as List)
          .map((json) => MechanicJobItem.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching job items: $e');
      rethrow;
    }
  }

  Future<MechanicJobItem> createJobItem(MechanicJobItem item) async {
    try {
      final data = await _db.insert('mechanic_job_items', item.toJson());
      notifyListeners();
      return MechanicJobItem.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating job item: $e');
      rethrow;
    }
  }

  Future<MechanicJobItem> updateJobItem(MechanicJobItem item) async {
    try {
      if (item.id == null || item.id!.isEmpty) {
        throw Exception('ID de ítem inválido');
      }

      final data =
          await _db.update('mechanic_job_items', item.id!, item.toJson());
      notifyListeners();
      return MechanicJobItem.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating job item: $e');
      rethrow;
    }
  }

  Future<void> deleteJobItem(String id) async {
    try {
      if (id.isEmpty) throw Exception('ID de ítem inválido');
      await _db.delete('mechanic_job_items', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting job item: $e');
      rethrow;
    }
  }

  // ============================================================
  // JOB BIKES OPERATIONS (Multi-bike support)
  // ============================================================

  /// Get all bikes for a job (multi-bike support)
  Future<List<MechanicJobBike>> getJobBikes(String jobId) async {
    try {
      final data =
          await Supabase.instance.client.from('mechanic_job_bikes').select('''
            *,
            bike:bikes(*),
            status:job_statuses(*)
          ''').eq('job_id', jobId).order('order_index');

      return (data as List)
          .map((json) => MechanicJobBike.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching job bikes: $e');
      rethrow;
    }
  }

  /// Get all job bikes (for list views - single query optimization)
  Future<Map<String, List<MechanicJobBike>>> getAllJobBikes() async {
    try {
      final data =
          await Supabase.instance.client.from('mechanic_job_bikes').select('''
            *,
            bike:bikes(*),
            status:job_statuses(*)
          ''').order('order_index');

      final allJobBikes =
          (data as List).map((json) => MechanicJobBike.fromJson(json)).toList();

      // Group by job_id
      final result = <String, List<MechanicJobBike>>{};
      for (final jb in allJobBikes) {
        result.putIfAbsent(jb.jobId, () => []).add(jb);
      }
      return result;
    } catch (e) {
      if (kDebugMode) print('Error fetching all job bikes: $e');
      return {};
    }
  }

  /// Add a bike to a job
  Future<MechanicJobBike> addBikeToJob(MechanicJobBike jobBike) async {
    try {
      final data = await _db.insert('mechanic_job_bikes', jobBike.toJson());
      notifyListeners();
      return MechanicJobBike.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error adding bike to job: $e');
      rethrow;
    }
  }

  /// Update a job bike entry
  Future<MechanicJobBike> updateJobBike(MechanicJobBike jobBike) async {
    try {
      if (jobBike.id == null || jobBike.id!.isEmpty) {
        throw Exception('ID de bicicleta de trabajo inválido');
      }
      final data =
          await _db.update('mechanic_job_bikes', jobBike.id!, jobBike.toJson());
      notifyListeners();
      return MechanicJobBike.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating job bike: $e');
      rethrow;
    }
  }

  /// Remove a bike from a job
  Future<void> removeBikeFromJob(String jobBikeId) async {
    try {
      if (jobBikeId.isEmpty) throw Exception('ID inválido');
      await _db.delete('mechanic_job_bikes', jobBikeId);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error removing bike from job: $e');
      rethrow;
    }
  }

  /// Get items for a specific bike in a job
  Future<List<MechanicJobItem>> getJobBikeItems(String jobBikeId) async {
    try {
      final data = await Supabase.instance.client
          .from('mechanic_job_items')
          .select()
          .eq('job_bike_id', jobBikeId);

      return (data as List)
          .map((json) => MechanicJobItem.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching job bike items: $e');
      rethrow;
    }
  }

  // ============================================================
  // TIMELINE OPERATIONS
  // ============================================================

  Future<List<MechanicJobTimeline>> getJobTimeline(String jobId) async {
    try {
      // Use Supabase client directly to ensure RLS policies work correctly
      final response = await Supabase.instance.client
          .from('mechanic_job_timeline')
          .select()
          .eq('job_id', jobId)
          .order('created_at', ascending: false);

      if (kDebugMode) {
        print(
            '📋 Timeline query result for job $jobId: ${response.length} events');
      }

      return (response as List)
          .map((json) => MechanicJobTimeline.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching job timeline: $e');
      rethrow;
    }
  }

  // Timeline events are created automatically by database triggers,
  // but we can also create manual events if needed
  Future<MechanicJobTimeline> createTimelineEvent(
      MechanicJobTimeline event) async {
    try {
      final data = await _db.insert('mechanic_job_timeline', event.toJson());
      notifyListeners();
      return MechanicJobTimeline.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating timeline event: $e');
      rethrow;
    }
  }

  // ============================================================
  // SERVICE PACKAGE OPERATIONS
  // ============================================================

  Future<List<ServicePackage>> getServicePackages({String? searchTerm}) async {
    try {
      List<Map<String, dynamic>> data;

      if (searchTerm != null && searchTerm.isNotEmpty) {
        data = await _db.searchRecords('service_packages', 'name', searchTerm);
      } else {
        data = await _db.select('service_packages', where: 'is_active=true');
      }

      return data.map((json) => ServicePackage.fromJson(json)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      if (kDebugMode) print('Error fetching service packages: $e');
      rethrow;
    }
  }

  Future<ServicePackage?> getServicePackageById(String id) async {
    try {
      if (id.isEmpty) return null;
      final data = await _db.selectById('service_packages', id);
      return data != null ? ServicePackage.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching service package: $e');
      rethrow;
    }
  }

  Future<ServicePackage> createServicePackage(ServicePackage package) async {
    try {
      final data = await _db.insert('service_packages', package.toJson());
      notifyListeners();
      return ServicePackage.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating service package: $e');
      rethrow;
    }
  }

  Future<ServicePackage> updateServicePackage(ServicePackage package) async {
    try {
      if (package.id == null || package.id!.isEmpty) {
        throw Exception('ID de paquete de servicio inválido');
      }
      final data =
          await _db.update('service_packages', package.id!, package.toJson());
      notifyListeners();
      return ServicePackage.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating service package: $e');
      rethrow;
    }
  }

  Future<void> deleteServicePackage(String id) async {
    try {
      if (id.isEmpty) throw Exception('ID de paquete de servicio inválido');
      await _db.delete('service_packages', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting service package: $e');
      rethrow;
    }
  }

  // ============================================================
  // COMPOSITE/HELPER OPERATIONS
  // ============================================================

  /// Get complete job details with items and timeline
  Future<Map<String, dynamic>> getJobDetails(String jobId) async {
    try {
      final job = await getJobById(jobId);
      if (job == null) throw Exception('Trabajo no encontrado');

      final items = await getJobItems(jobId);
      final timeline = await getJobTimeline(jobId);

      return {
        'job': job,
        'items': items,
        'timeline': timeline,
      };
    } catch (e) {
      if (kDebugMode) print('Error fetching job details: $e');
      rethrow;
    }
  }

  /// Get all bikes and jobs for a customer (for logbook view)
  Future<Map<String, dynamic>> getCustomerBikeshopData(
      String customerId) async {
    try {
      final bikes = await getBikes(customerId: customerId);
      final jobs = await getJobs(customerId: customerId);

      return {
        'bikes': bikes,
        'jobs': jobs,
      };
    } catch (e) {
      if (kDebugMode) print('Error fetching customer bikeshop data: $e');
      rethrow;
    }
  }

  /// Get all jobs for a specific bike
  Future<List<MechanicJob>> getBikeHistory(String bikeId) async {
    try {
      return await getJobs(bikeId: bikeId);
    } catch (e) {
      if (kDebugMode) print('Error fetching bike history: $e');
      rethrow;
    }
  }

  /// Apply a service package to a job (creates product + service items)
  Future<void> applyServicePackage(String jobId, String packageId) async {
    try {
      final package = await getServicePackageById(packageId);
      if (package == null) throw Exception('Paquete de servicio no encontrado');

      // Get tenant_id from parent job
      final jobData = await _db.selectById('mechanic_jobs', jobId);
      if (jobData == null) throw Exception('Trabajo mecánico no encontrado');
      final tenantId = jobData['tenant_id']?.toString() ?? '';

      // Create items from package
      for (final item in package.items) {
        final productId = item['product_id']?.toString();
        final quantity =
            double.tryParse(item['quantity']?.toString() ?? '1') ?? 1;

        if (productId != null) {
          // Fetch product details
          final productData = await _db.selectById('products', productId);
          if (productData != null) {
            final unitPrice =
                double.tryParse(productData['price']?.toString() ?? '0') ?? 0;
            final jobItem = MechanicJobItem(
              jobId: jobId,
              tenantId: tenantId,
              productId: productId,
              productName: productData['name']?.toString() ?? '',
              productSku: productData['sku']?.toString(),
              quantity: quantity,
              unitPrice: unitPrice,
              totalPrice: quantity * unitPrice,
            );
            await createJobItem(jobItem);
          }
        }
      }

      // Create labor-as-item entry so services live in mechanic_job_items
      if (package.baseLaborCost > 0) {
        final hours = package.estimatedDurationHours <= 0
            ? 1.0
            : package.estimatedDurationHours;
        final hourlyRate = package.baseLaborCost / hours;

        final laborItem = MechanicJobItem(
          tenantId: tenantId,
          jobId: jobId,
          productName: package.name,
          productSku: null,
          quantity: hours,
          unitPrice: hourlyRate,
          totalPrice: package.baseLaborCost,
          notes: '${package.description} - ${hours}h labor',
        );

        await createJobItem(laborItem);
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error applying service package: $e');
      rethrow;
    }
  }

  /// Get dashboard statistics
  Future<Map<String, int>> getDashboardStats() async {
    try {
      final allJobs = await getJobs(includeCompleted: true);

      return {
        'total': allJobs.length,
        'pendiente':
            allJobs.where((j) => j.status == JobStatus.pendiente).length,
        'en_curso': allJobs.where((j) => j.status == JobStatus.enCurso).length,
        'esperando_repuestos': allJobs
            .where((j) => j.status == JobStatus.esperandoRepuestos)
            .length,
        'finalizado':
            allJobs.where((j) => j.status == JobStatus.finalizado).length,
        'entregado':
            allJobs.where((j) => j.status == JobStatus.entregado).length,
        'overdue': allJobs.where((j) => j.isOverdue && j.isActive).length,
      };
    } catch (e) {
      if (kDebugMode) print('Error fetching dashboard stats: $e');
      return {};
    }
  }

  /// Create an invoice from a mechanic job (AWESOME feature!)
  /// Calls database function to generate invoice with all items + labor + IVA
  Future<String?> createInvoiceFromJob(String jobId) async {
    try {
      if (jobId.isEmpty) return null;

      // Call the database function to create invoice
      // This will include all job items, labor costs, and calculate IVA
      final result = await _db.rpc(
        'create_invoice_from_mechanic_job',
        params: {'p_job_id': jobId},
      );

      if (result != null) {
        notifyListeners();
        if (kDebugMode) print('✅ Invoice created from job: $result');
        return result.toString();
      }

      if (kDebugMode)
        print('⚠️ Invoice creation returned null for job: $jobId');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error creating invoice from job: $e');
      // Don't rethrow - invoice creation failure shouldn't prevent job from being saved
      return null;
    }
  }

  /// Sync a mechanic job to its linked invoice
  /// Called after updating job items to ensure invoice totals are fresh
  Future<void> syncJobToInvoice(String jobId) async {
    try {
      if (jobId.isEmpty) return;

      // Call the database function to sync job to invoice
      await _db.rpc(
        'sync_job_to_invoice',
        params: {'p_job_id': jobId},
      );

      // Wait briefly to ensure database transaction commits
      // This prevents race condition where UI fetches stale data
      await Future.delayed(const Duration(milliseconds: 100));

      notifyListeners();
      if (kDebugMode) print('✅ Job synced to invoice: $jobId');
    } catch (e) {
      if (kDebugMode) print('❌ Error syncing job to invoice: $e');
      rethrow;
    }
  }

  // Realtime subscription for mechanic jobs
  // Uses SURGICAL UPDATES - only updates the specific changed record in cache
  // instead of triggering full page rebuilds
  Future<void> _setupMechanicJobsRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        debugPrint('⚠️ [BikeshopService] Cannot setup realtime: no tenant_id');
        return;
      }

      await _mechanicJobsChannel?.unsubscribe();

      _mechanicJobsChannel = Supabase.instance.client
          .channel('mechanic_jobs_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'mechanic_jobs',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) => _handleMechanicJobChange(payload),
          )
          .subscribe();

      if (!kReleaseMode) {
        debugPrint(
            '✅ [BikeshopService] Realtime subscription active (surgical mode)');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('❌ [BikeshopService] Failed to setup realtime: $e');
      }
    }
  }

  /// Handle realtime change for mechanic_jobs with SURGICAL UPDATE
  /// Fetches the complete record with joins to ensure all data is available
  void _handleMechanicJobChange(PostgresChangePayload payload) {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final rawNew = payload.newRecord;
          final jobId = rawNew['id']?.toString();
          if (jobId != null && jobId.isNotEmpty) {
            // Fetch complete job with joined data (async, non-blocking)
            _fetchAndUpdateJob(jobId);
          }
          break;
        case PostgresChangeEvent.delete:
          final rawOld = payload.oldRecord;
          final id = rawOld['id']?.toString();
          if (id != null) {
            _surgicalRemoveJob(id);
            debugPrint('🔧 [BikeshopService] Surgical remove: $id');
            if (!mounted) return;
            notifyListeners();
          }
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('⚠️ [BikeshopService] Error handling realtime change: $e');
      // Fallback to debounced notify on error
      _debouncedNotify();
    }
  }

  /// Fetch a complete job with joined data and update the cache surgically
  Future<void> _fetchAndUpdateJob(String jobId) async {
    try {
      // Fetch with joins - same query structure as getJobs()
      final data =
          await Supabase.instance.client.from('mechanic_jobs').select('''
            *,
            job_status:job_statuses(*)
          ''').eq('id', jobId).isFilter('deleted_at', null).maybeSingle();

      if (data != null) {
        final job = MechanicJob.fromJson(data);
        _surgicalUpdateJob(job);
        debugPrint(
            '🔧 [BikeshopService] Surgical update (with joins): ${job.jobNumber}');

        if (!mounted) return;
        notifyListeners();
      }
    } catch (e) {
      debugPrint(
          '⚠️ [BikeshopService] Error fetching job for surgical update: $e');
    }
  }

  /// Surgically update or add a job in the cache without invalidating it
  void _surgicalUpdateJob(MechanicJob job) {
    if (_cachedJobs == null) return;

    final index = _cachedJobs!.indexWhere((j) => j.id == job.id);
    if (index >= 0) {
      _cachedJobs![index] = job; // Update in-place
    } else {
      _cachedJobs!.add(job); // New record
      _cachedJobs!.sort((a, b) => b.arrivalDate.compareTo(a.arrivalDate));
    }
  }

  /// Surgically remove a job from the cache
  void _surgicalRemoveJob(String jobId) {
    _cachedJobs?.removeWhere((j) => j.id == jobId);
  }

  /// Setup realtime subscription for sales_invoices (for invoice status updates)
  /// Uses lighter-weight notification since we don't cache invoices here
  Future<void> _setupSalesInvoicesRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        return;
      }

      await _salesInvoicesChannel?.unsubscribe();

      _salesInvoicesChannel = Supabase.instance.client
          .channel('sales_invoices_for_pegas')
          .onPostgresChanges(
            event: PostgresChangeEvent
                .update, // Only care about updates (status changes)
            schema: 'public',
            table: 'sales_invoices',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              // For invoice changes, we use a longer debounce since these are less critical
              // The Pegas table will still show correct data on next user interaction
              _debouncedNotifyInvoiceChange();
            },
          )
          .subscribe();

      if (!kReleaseMode) {
        debugPrint(
            '✅ [BikeshopService] Sales invoices realtime subscription active');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint(
            '❌ [BikeshopService] Failed to setup sales invoices realtime: $e');
      }
    }
  }

  Timer? _invoiceNotifyDebounceTimer;

  /// Longer debounce for invoice changes (3 seconds) - less disruptive
  void _debouncedNotifyInvoiceChange() {
    _invoiceNotifyDebounceTimer?.cancel();
    _invoiceNotifyDebounceTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      debugPrint(
          '🔔 [BikeshopService] Invoice change notification (3s debounce)');
      notifyListeners();
    });
  }

  /// Debounced notifyListeners - prevents excessive reloads
  void _debouncedNotify() {
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return; // Don't notify if disposed
      notifyListeners();
    });
  }

  bool get mounted => !_isDisposed;
  bool _isDisposed = false;

  // ========== SOFT DELETE METHODS ==========

  /// Soft delete a mechanic job (sets deleted_at timestamp)
  Future<void> softDeleteJob(String jobId) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      await Supabase.instance.client.from('mechanic_jobs').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': userId,
      }).eq('id', jobId);

      invalidateJobsCache();
      _debouncedNotify();
      debugPrint('🗑️ Soft deleted job: $jobId');
    } catch (e) {
      if (kDebugMode) print('Error soft deleting job: $e');
      rethrow;
    }
  }

  /// Restore a soft-deleted mechanic job
  Future<void> restoreJob(String jobId) async {
    try {
      await Supabase.instance.client.from('mechanic_jobs').update({
        'deleted_at': null,
        'deleted_by': null,
      }).eq('id', jobId);

      invalidateJobsCache();
      _debouncedNotify();
      debugPrint('♻️ Restored job: $jobId');
    } catch (e) {
      if (kDebugMode) print('Error restoring job: $e');
      rethrow;
    }
  }

  /// Get only soft-deleted jobs (for "Eliminados" view)
  Future<List<MechanicJob>> getDeletedJobs() async {
    try {
      final data = await Supabase.instance.client
          .from('mechanic_jobs')
          .select()
          .not('deleted_at', 'is', null)
          .order('deleted_at', ascending: false);

      return (data as List<dynamic>)
          .map((json) => MechanicJob.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching deleted jobs: $e');
      rethrow;
    }
  }

  /// Permanently delete a job (hard delete - cannot be undone)
  Future<void> permanentlyDeleteJob(String jobId) async {
    try {
      await Supabase.instance.client
          .from('mechanic_jobs')
          .delete()
          .eq('id', jobId);

      invalidateJobsCache();
      _debouncedNotify();
      debugPrint('🔥 Permanently deleted job: $jobId');
    } catch (e) {
      if (kDebugMode) print('Error permanently deleting job: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _notifyDebounceTimer?.cancel();
    _mechanicJobsChannel?.unsubscribe();
    _salesInvoicesChannel
        ?.unsubscribe(); // Clean up sales invoices subscription
    super.dispose();
  }
}
