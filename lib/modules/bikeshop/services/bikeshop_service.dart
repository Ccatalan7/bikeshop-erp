import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/bikeshop_models.dart';

class _BikeMemoryTarget {
  final String systemKey;
  final String? componentSlotKey;
  final BikeMemoryLocation location;
  final BikeInterventionType interventionType;
  final bool createsLifecycle;

  const _BikeMemoryTarget({
    required this.systemKey,
    required this.componentSlotKey,
    required this.location,
    required this.interventionType,
    required this.createsLifecycle,
  });

  String get key =>
      '$systemKey|${componentSlotKey ?? '-'}|${location.dbValue}|${interventionType.dbValue}|$createsLifecycle';
}

class _BikeSystemStateTarget {
  final String bikeId;
  final String systemKey;
  final BikeMemoryLocation location;

  const _BikeSystemStateTarget({
    required this.bikeId,
    required this.systemKey,
    required this.location,
  });

  String get key => '$bikeId|$systemKey|${location.dbValue}';
}

class BikeshopService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService = TenantService();

  static const List<String> _derivedJobObservationSources = [
    'job_diagnosis_sync',
  ];
  static const List<String> _derivedJobItemSources = [
    'job_item_sync',
    'job_general_item_sync',
  ];
  static const List<String> _derivedJobStateSources = [
    'diagnosis_sheet',
    'job_diagnosis_sync',
    'job_item_sync',
    'job_general_item_sync',
  ];

  RealtimeChannel? _mechanicJobsChannel;
  RealtimeChannel? _jobBikesChannel;
  RealtimeChannel? _salesInvoicesChannel; // For invoice status updates
  Timer? _notifyDebounceTimer;

  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  List<MechanicJob>? _cachedJobs;
  List<Bike>? _cachedBikes;
  Map<String, List<MechanicJobBike>>? _cachedAllJobBikes;
  DateTime? _jobsCacheTime;
  DateTime? _bikesCacheTime;
  DateTime? _jobBikesCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);

  // Loading state flags to prevent concurrent fetches
  bool _isLoadingJobs = false;
  bool _isLoadingBikes = false;
  bool _isLoadingAllJobBikes = false;

  // Public getters for cached data (instant access)
  List<MechanicJob> get cachedJobs => _cachedJobs ?? [];
  List<Bike> get cachedBikes => _cachedBikes ?? [];
  Map<String, List<MechanicJobBike>> get cachedAllJobBikes => _cloneJobBikesMap(
      _cachedAllJobBikes ?? const <String, List<MechanicJobBike>>{});
  bool get hasJobsCache => _cachedJobs != null;
  bool get hasBikesCache => _cachedBikes != null;
  bool get hasJobBikesCache => _cachedAllJobBikes != null;
  bool get isJobsCacheFresh =>
      _cachedJobs != null && _isCacheValid(_jobsCacheTime);
  bool get isBikesCacheFresh =>
      _cachedBikes != null && _isCacheValid(_bikesCacheTime);
  bool get isJobBikesCacheFresh =>
      _cachedAllJobBikes != null && _isCacheValid(_jobBikesCacheTime);

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

  void invalidateJobBikesCache() {
    _cachedAllJobBikes = null;
    _jobBikesCacheTime = null;
  }

  Map<String, List<MechanicJobBike>> _cloneJobBikesMap(
      Map<String, List<MechanicJobBike>> source) {
    return source.map(
      (jobId, bikes) => MapEntry(jobId, List<MechanicJobBike>.from(bikes)),
    );
  }

  void _cacheAllJobBikes(Map<String, List<MechanicJobBike>> jobBikesMap) {
    _cachedAllJobBikes = _cloneJobBikesMap(jobBikesMap);
    _jobBikesCacheTime = DateTime.now();
  }

  void _upsertJobBikeInCache(MechanicJobBike jobBike) {
    if (_cachedAllJobBikes == null) return;

    final emptyJobIds = <String>[];
    _cachedAllJobBikes!.forEach((cachedJobId, bikes) {
      bikes.removeWhere((existing) => existing.id == jobBike.id);
      if (bikes.isEmpty) {
        emptyJobIds.add(cachedJobId);
      }
    });
    for (final emptyJobId in emptyJobIds) {
      _cachedAllJobBikes!.remove(emptyJobId);
    }

    final bikes = _cachedAllJobBikes!.putIfAbsent(jobBike.jobId, () => []);
    bikes.add(jobBike);
    bikes.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    _jobBikesCacheTime = DateTime.now();
  }

  void _removeJobBikeFromCache(String jobBikeId, {String? jobId}) {
    if (_cachedAllJobBikes == null) return;

    if (jobId != null) {
      final bikes = _cachedAllJobBikes![jobId];
      bikes?.removeWhere((existing) => existing.id == jobBikeId);
      if (bikes != null && bikes.isEmpty) {
        _cachedAllJobBikes!.remove(jobId);
      }
    } else {
      final emptyJobIds = <String>[];
      _cachedAllJobBikes!.forEach((cachedJobId, bikes) {
        bikes.removeWhere((existing) => existing.id == jobBikeId);
        if (bikes.isEmpty) {
          emptyJobIds.add(cachedJobId);
        }
      });
      for (final emptyJobId in emptyJobIds) {
        _cachedAllJobBikes!.remove(emptyJobId);
      }
    }

    _jobBikesCacheTime = DateTime.now();
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
    _setupMechanicJobBikesRealtime();
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
      final createdBike = Bike.fromJson(data);
      await _logBikeRegisteredEvent(createdBike);
      invalidateBikesCache();
      notifyListeners();
      return createdBike;
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

  Future<BikeProfile?> getBikeProfile(String bikeId) async {
    try {
      if (bikeId.isEmpty) return null;
      final data = await Supabase.instance.client
          .from('bike_profiles')
          .select()
          .eq('bike_id', bikeId)
          .maybeSingle();

      return data != null ? BikeProfile.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching bike profile: $e');
      rethrow;
    }
  }

  Future<BikeProfile> upsertBikeProfile(BikeProfile profile) async {
    try {
      BikeProfile? existing;

      if (profile.id != null && profile.id!.isNotEmpty) {
        final existingData = await _db.selectById('bike_profiles', profile.id!);
        existing =
            existingData != null ? BikeProfile.fromJson(existingData) : null;
      }

      existing ??= await getBikeProfile(profile.bikeId);

      if (existing != null && existing.id != null) {
        final data = await _db.update(
          'bike_profiles',
          existing.id!,
          profile
              .copyWith(id: existing.id, createdAt: existing.createdAt)
              .toJson(),
        );
        final savedProfile = BikeProfile.fromJson(data);
        await _logBikeProfileEvent(savedProfile, isCreate: false);
        return savedProfile;
      }

      final data = await _db.insert('bike_profiles', profile.toJson());
      final savedProfile = BikeProfile.fromJson(data);
      await _logBikeProfileEvent(savedProfile, isCreate: true);
      return savedProfile;
    } catch (e) {
      if (kDebugMode) print('Error upserting bike profile: $e');
      rethrow;
    }
  }

  Future<BikeRecordSnapshot?> getBikeRecordSnapshot(String bikeId) async {
    try {
      if (bikeId.isEmpty) return null;

      final bike = await getBikeById(bikeId);
      if (bike == null) return null;

      final profile = await getBikeProfile(bikeId);
      return BikeRecordSnapshot.fromBikeAndProfile(
        bike: bike,
        profile: profile,
      );
    } catch (e) {
      if (kDebugMode) print('Error fetching bike record snapshot: $e');
      rethrow;
    }
  }

  Future<List<BikeEvent>> getBikeEvents(String bikeId) async {
    try {
      if (bikeId.isEmpty) return const [];

      final response = await Supabase.instance.client
          .from('bike_events')
          .select()
          .eq('bike_id', bikeId)
          .order('event_date', ascending: false)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => BikeEvent.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching bike events: $e');
      rethrow;
    }
  }

  Future<BikeEvent> createBikeEvent(BikeEvent event) async {
    try {
      final data = await _db.insert('bike_events', event.toJson());
      notifyListeners();
      return BikeEvent.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating bike event: $e');
      rethrow;
    }
  }

  Future<List<BikeSystemState>> getBikeSystemStates(String bikeId) async {
    try {
      if (bikeId.isEmpty) return const [];

      final response = await Supabase.instance.client
          .from('bike_system_states')
          .select()
          .eq('bike_id', bikeId)
          .order('system_key')
          .order('location_key');

      return (response as List)
          .map((json) => BikeSystemState.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching bike system states: $e');
      rethrow;
    }
  }

  Future<BikeSystemState> upsertBikeSystemState(BikeSystemState state) async {
    try {
      final response = await Supabase.instance.client
          .from('bike_system_states')
          .upsert(
            state.toJson(),
            onConflict: 'tenant_id,bike_id,system_key,location_key',
          )
          .select()
          .single();

      notifyListeners();
      return BikeSystemState.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('Error upserting bike system state: $e');
      rethrow;
    }
  }

  Future<List<BikeComponentLifecycle>> getBikeComponentLifecycles(
    String bikeId, {
    bool activeOnly = false,
  }) async {
    try {
      if (bikeId.isEmpty) return const [];

      var query = Supabase.instance.client
          .from('bike_component_lifecycles')
          .select()
          .eq('bike_id', bikeId);

      if (activeOnly) {
        query = query.eq('status', 'installed');
      }

      final response = await query
          .order('installed_at', ascending: false)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) =>
              BikeComponentLifecycle.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching bike component lifecycles: $e');
      rethrow;
    }
  }

  Future<BikeComponentLifecycle> createBikeComponentLifecycle(
    BikeComponentLifecycle lifecycle,
  ) async {
    try {
      final data =
          await _db.insert('bike_component_lifecycles', lifecycle.toJson());
      notifyListeners();
      return BikeComponentLifecycle.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating bike component lifecycle: $e');
      rethrow;
    }
  }

  Future<List<BikeObservation>> getBikeObservations(
    String bikeId, {
    String? systemKey,
    String? componentSlotKey,
  }) async {
    try {
      if (bikeId.isEmpty) return const [];

      var query = Supabase.instance.client
          .from('bike_observations')
          .select()
          .eq('bike_id', bikeId);

      if (systemKey != null && systemKey.isNotEmpty) {
        query = query.eq('system_key', systemKey);
      }

      if (componentSlotKey != null && componentSlotKey.isNotEmpty) {
        query = query.eq('component_slot_key', componentSlotKey);
      }

      final response = await query
          .order('observed_at', ascending: false)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => BikeObservation.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching bike observations: $e');
      rethrow;
    }
  }

  Future<BikeObservation> createBikeObservation(
      BikeObservation observation) async {
    try {
      final data = await _db.insert('bike_observations', observation.toJson());
      notifyListeners();
      return BikeObservation.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating bike observation: $e');
      rethrow;
    }
  }

  Future<List<BikeIntervention>> getBikeInterventions(
    String bikeId, {
    String? systemKey,
    String? componentSlotKey,
  }) async {
    try {
      if (bikeId.isEmpty) return const [];

      var query = Supabase.instance.client
          .from('bike_interventions')
          .select()
          .eq('bike_id', bikeId);

      if (systemKey != null && systemKey.isNotEmpty) {
        query = query.eq('system_key', systemKey);
      }

      if (componentSlotKey != null && componentSlotKey.isNotEmpty) {
        query = query.eq('component_slot_key', componentSlotKey);
      }

      final response = await query
          .order('performed_at', ascending: false)
          .order('created_at', ascending: false);

      return (response as List)
          .map(
              (json) => BikeIntervention.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching bike interventions: $e');
      rethrow;
    }
  }

  Future<BikeIntervention> createBikeIntervention(
    BikeIntervention intervention,
  ) async {
    try {
      final data =
          await _db.insert('bike_interventions', intervention.toJson());
      notifyListeners();
      return BikeIntervention.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating bike intervention: $e');
      rethrow;
    }
  }

  Future<void> syncBikeMemoryFromJob(
    String jobId, {
    bool swallowErrors = true,
  }) async {
    try {
      if (jobId.isEmpty) return;

      final job = await getJobById(jobId);
      if (job == null || job.id == null) return;

      final jobBikes = await getJobBikes(jobId);
      final staleTargets = await _clearDerivedBikeMemoryForJob(jobId);

      if (jobBikes.isEmpty) {
        await _refreshDerivedSystemStates(staleTargets.values);
        return;
      }

      final jobItems = await getJobItems(jobId);
      final itemsByJobBikeId = <String?, List<MechanicJobItem>>{};
      for (final item in jobItems) {
        itemsByJobBikeId.putIfAbsent(item.jobBikeId, () => []).add(item);
      }
      final isCompleted = {
        JobStatus.finalizado,
        JobStatus.entregado,
      }.contains(job.status);

      for (final jobBike in jobBikes) {
        final bikeItems =
            itemsByJobBikeId[jobBike.id] ?? const <MechanicJobItem>[];
        await _syncJobBikeDiagnosisMemory(
            job: job, jobBike: jobBike, items: bikeItems);

        if (isCompleted) {
          await _syncCompletedJobBikeItems(
            job: job,
            jobBike: jobBike,
            items: bikeItems,
          );
        }
      }

      if (isCompleted && jobBikes.length == 1) {
        final orphanItems = itemsByJobBikeId[null] ?? const <MechanicJobItem>[];
        if (orphanItems.isNotEmpty) {
          await _syncCompletedJobBikeItems(
            job: job,
            jobBike: jobBikes.first,
            items: orphanItems,
            sourceOverride: 'job_general_item_sync',
          );
        }
      }

      await _refreshDerivedSystemStates(staleTargets.values);
    } catch (e) {
      if (kDebugMode) {
        print(
            '⚠️ [BikeshopService] Could not sync bike memory from job $jobId: $e');
      }
      if (!swallowErrors) rethrow;
    }
  }

  Future<void> _safeSyncBikeMemoryForJob(String? jobId) async {
    if (jobId == null || jobId.isEmpty) return;

    try {
      await syncBikeMemoryFromJob(jobId);
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [BikeshopService] Could not sync bike memory for $jobId: $e');
      }
    }
  }

  Future<bool> _jobShouldSyncCompletedItemMemory(String? jobId) async {
    if (jobId == null || jobId.isEmpty) return false;

    try {
      final job = await getJobById(jobId);
      if (job == null) return false;

      return {
        JobStatus.finalizado,
        JobStatus.entregado,
      }.contains(job.status);
    } catch (e) {
      if (kDebugMode) {
        print(
            '⚠️ [BikeshopService] Could not determine bike sync status for $jobId: $e');
      }
      return false;
    }
  }

  Future<void> _syncJobBikeDiagnosisMemory({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required List<MechanicJobItem> items,
  }) async {
    final diagnosisSheet = jobBike.diagnosisSheet;
    final observedAt = _resolveJobBikeDiagnosisObservedAt(job, jobBike);
    final combinedText = [
      jobBike.workRequested,
      jobBike.diagnosis,
      jobBike.workPerformed,
      jobBike.technicianNotes,
    ]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' | ');

    if (diagnosisSheet.hasMeaningfulData) {
      await _syncDiagnosisSheetMemory(
        job: job,
        jobBike: jobBike,
        diagnosisSheet: diagnosisSheet,
        observedAt: observedAt,
      );

      if (combinedText.isNotEmpty) {
        await createBikeObservation(
          BikeObservation(
            tenantId: job.tenantId,
            bikeId: jobBike.bikeId,
            jobId: job.id,
            jobBikeId: jobBike.id,
            systemKey: 'general',
            location: BikeMemoryLocation.none,
            observationKind: BikeObservationKind.diagnosisSnapshot,
            observationKey: 'job_diagnosis_note',
            title: 'Notas del diagnóstico',
            summary: combinedText,
            severity: _inferSeverityFromText(combinedText),
            observedAt: observedAt,
            source: 'job_diagnosis_sync',
            sourceField: 'diagnosis',
            payload: {
              'job_number': job.jobNumber,
              'status': job.status.name,
              'template_key': diagnosisSheet.templateKey,
            },
          ),
        );
      }

      return;
    }

    if (combinedText.isEmpty) return;

    final inferredTargets = {
      for (final target in [
        ..._inferTargetsFromText(combinedText),
        ...items.expand(_inferTargetsFromItem),
      ])
        target.key: target,
    }.values.toList();

    final targets = inferredTargets.isEmpty
        ? <_BikeMemoryTarget>[
            const _BikeMemoryTarget(
              systemKey: 'general',
              componentSlotKey: null,
              location: BikeMemoryLocation.none,
              interventionType: BikeInterventionType.inspection,
              createsLifecycle: false,
            ),
          ]
        : inferredTargets;

    final severity = _inferSeverityFromText(combinedText);

    for (final target in targets) {
      final observation = BikeObservation(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: target.systemKey,
        componentSlotKey: target.componentSlotKey,
        location: target.location,
        observationKind: BikeObservationKind.diagnosisSnapshot,
        observationKey: 'job_diagnosis',
        title: 'Diagnóstico registrado',
        summary: combinedText,
        severity: severity,
        observedAt: observedAt,
        source: 'job_diagnosis_sync',
        sourceField: 'diagnosis',
        payload: {
          'job_number': job.jobNumber,
          'status': job.status.name,
          'client_request': jobBike.workRequested,
          'diagnosis': jobBike.diagnosis,
          'work_performed': jobBike.workPerformed,
          'technician_notes': jobBike.technicianNotes,
        },
      );
      await createBikeObservation(observation);

      if (target.systemKey != 'general') {
        await upsertBikeSystemState(
          BikeSystemState(
            tenantId: job.tenantId,
            bikeId: jobBike.bikeId,
            jobId: job.id,
            jobBikeId: jobBike.id,
            systemKey: target.systemKey,
            location: target.location,
            overallStatus: severity == BikeMemorySeverity.critical
                ? BikeSystemOverallStatus.critical
                : BikeSystemOverallStatus.attention,
            statusNote: _truncateForStateNote(combinedText),
            lastReviewedAt: observedAt,
            payload: {
              'source': 'job_diagnosis_sync',
              'job_number': job.jobNumber,
            },
          ),
        );
      }
    }
  }

  Future<void> _syncDiagnosisSheetMemory({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required DateTime observedAt,
  }) async {
    await _syncDrivetrainDiagnosisSection(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      section: diagnosisSheet.drivetrain,
    );
    await _syncBrakeDiagnosisSection(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: 'front_brake',
      title: 'Diagnóstico freno delantero',
      location: BikeMemoryLocation.front,
      section: diagnosisSheet.frontBrake,
    );
    await _syncBrakeDiagnosisSection(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: 'rear_brake',
      title: 'Diagnóstico freno trasero',
      location: BikeMemoryLocation.rear,
      section: diagnosisSheet.rearBrake,
    );
    await _syncWheelDiagnosisSection(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: 'front_wheel',
      title: 'Diagnóstico rueda delantera',
      location: BikeMemoryLocation.front,
      section: diagnosisSheet.frontWheel,
    );
    await _syncWheelDiagnosisSection(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: 'rear_wheel',
      title: 'Diagnóstico rueda trasera',
      location: BikeMemoryLocation.rear,
      section: diagnosisSheet.rearWheel,
    );
  }

  Future<void> _syncDrivetrainDiagnosisSection({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required DateTime observedAt,
    required DrivetrainDiagnosisSheet section,
  }) async {
    if (!section.hasMeaningfulData) return;

    final noteParts = <String>[];
    if (section.chainWearPercent != null) {
      noteParts.add(
        'Cadena ${_formatChainWearGaugeSummary(section.chainWearPercent!)}',
      );
    }
    _appendDiagnosisSummaryPart(
      noteParts,
      'Lubricación cadena',
      _diagnosisConditionLabel(section.chainLubricationStatus),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Cassette',
      _diagnosisConditionLabel(section.cassetteCondition),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Plato',
      _diagnosisConditionLabel(section.chainringCondition),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Cambio trasero',
      _diagnosisConditionLabel(section.rearDerailleurCondition),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Cambio delantero',
      _diagnosisConditionLabel(section.frontDerailleurCondition),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Shifter',
      _diagnosisConditionLabel(section.shifterCondition),
    );
    if (section.notes != null && section.notes!.trim().isNotEmpty) {
      noteParts.add(section.notes!.trim());
    }
    final summary = noteParts.join(' | ');

    await createBikeObservation(
      BikeObservation(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: 'drivetrain',
        location: BikeMemoryLocation.center,
        observationKind: BikeObservationKind.conditionAssessment,
        observationKey: 'diagnosis_sheet_drivetrain',
        title: 'Diagnóstico tren motriz',
        summary: summary.isEmpty ? null : summary,
        statusValue: section.overallStatus.dbValue,
        severity: _severityFromSystemStatus(section.overallStatus),
        observedAt: observedAt,
        source: 'job_diagnosis_sync',
        sourceField: 'diagnosis_sheet',
        payload: {
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
          'section': 'drivetrain',
          ...section.toJson(),
        },
      ),
    );

    await upsertBikeSystemState(
      BikeSystemState(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: 'drivetrain',
        location: BikeMemoryLocation.center,
        overallStatus: section.overallStatus,
        statusNote: summary.isEmpty ? null : _truncateForStateNote(summary),
        lastReviewedAt: observedAt,
        payload: {
          'source': 'diagnosis_sheet',
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
        },
      ),
    );

    if (section.chainWearPercent != null) {
      await createBikeObservation(
        BikeObservation(
          tenantId: job.tenantId,
          bikeId: jobBike.bikeId,
          jobId: job.id,
          jobBikeId: jobBike.id,
          systemKey: 'drivetrain',
          componentSlotKey: 'chain',
          location: BikeMemoryLocation.center,
          observationKind: BikeObservationKind.measurement,
          observationKey: 'chain_wear_percent',
          title: 'Medición desgaste de cadena',
          valueNumeric: section.chainWearPercent,
          unit: '%',
          severity: _severityFromWearPercent(section.chainWearPercent),
          observedAt: observedAt,
          source: 'job_diagnosis_sync',
          sourceField: 'diagnosis_sheet',
          payload: {
            'job_number': job.jobNumber,
            'template_key': diagnosisSheet.templateKey,
          },
        ),
      );
    }

    if (section.cassetteCondition != null &&
        section.cassetteCondition!.isNotEmpty) {
      await createBikeObservation(
        BikeObservation(
          tenantId: job.tenantId,
          bikeId: jobBike.bikeId,
          jobId: job.id,
          jobBikeId: jobBike.id,
          systemKey: 'drivetrain',
          componentSlotKey: 'cassette',
          location: BikeMemoryLocation.center,
          observationKind: BikeObservationKind.conditionAssessment,
          observationKey: 'cassette_condition',
          title: 'Estado del cassette',
          statusValue: section.cassetteCondition,
          summary: section.notes,
          severity: section.cassetteCondition == 'replace'
              ? BikeMemorySeverity.critical
              : (section.cassetteCondition == 'attention'
                  ? BikeMemorySeverity.warning
                  : null),
          observedAt: observedAt,
          source: 'job_diagnosis_sync',
          sourceField: 'diagnosis_sheet',
          payload: {
            'job_number': job.jobNumber,
            'template_key': diagnosisSheet.templateKey,
          },
        ),
      );
    }

    await _createDrivetrainConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      componentSlotKey: 'chain',
      observationKey: 'chain_lubrication_status',
      title: 'Estado lubricación de cadena',
      statusValue: section.chainLubricationStatus,
    );

    await _createDrivetrainConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      componentSlotKey: 'chainring',
      observationKey: 'chainring_condition',
      title: 'Estado del plato',
      statusValue: section.chainringCondition,
    );

    await _createDrivetrainConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      componentSlotKey: 'rear_derailleur',
      observationKey: 'rear_derailleur_condition',
      title: 'Estado cambio trasero',
      statusValue: section.rearDerailleurCondition,
    );

    await _createDrivetrainConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      componentSlotKey: 'front_derailleur',
      observationKey: 'front_derailleur_condition',
      title: 'Estado cambio delantero',
      statusValue: section.frontDerailleurCondition,
    );

    await _createDrivetrainConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      componentSlotKey: 'shifter',
      observationKey: 'shifter_condition',
      title: 'Estado shifter',
      statusValue: section.shifterCondition,
    );
  }

  Future<void> _syncBrakeDiagnosisSection({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required DateTime observedAt,
    required String systemKey,
    required String title,
    required BikeMemoryLocation location,
    required BrakeDiagnosisSheet section,
  }) async {
    if (!section.hasMeaningfulData) return;

    final noteParts = <String>[];
    if (section.padWearPercent != null) {
      noteParts.add(
        'Desgaste pastillas ${section.padWearPercent!.toStringAsFixed(1)}%',
      );
    }
    _appendDiagnosisSummaryPart(
      noteParts,
      'Contaminacion pastillas',
      _diagnosisConditionLabel(section.padContaminationStatus),
    );
    if (section.rotorThicknessMm != null) {
      noteParts.add(
        'Rotor ${section.rotorThicknessMm!.toStringAsFixed(2)} mm',
      );
    }
    _appendDiagnosisSummaryPart(
      noteParts,
      'Alineacion rotor',
      _diagnosisConditionLabel(section.rotorTruenessStatus),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Contaminacion rotor',
      _diagnosisConditionLabel(section.rotorContaminationStatus),
    );
    if (section.symptomKeys.isNotEmpty) {
      noteParts.add(
        'Sintomas ${section.symptomKeys.map(_diagnosisSymptomLabel).whereType<String>().join(', ')}',
      );
    }
    if (section.notes != null && section.notes!.trim().isNotEmpty) {
      noteParts.add(section.notes!.trim());
    }
    final summary = noteParts.join(' | ');

    await createBikeObservation(
      BikeObservation(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: systemKey,
        location: location,
        observationKind: BikeObservationKind.conditionAssessment,
        observationKey: 'diagnosis_sheet_$systemKey',
        title: title,
        summary: summary.isEmpty ? null : summary,
        statusValue: section.overallStatus.dbValue,
        severity: _severityFromSystemStatus(section.overallStatus),
        observedAt: observedAt,
        source: 'job_diagnosis_sync',
        sourceField: 'diagnosis_sheet',
        payload: {
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
          'section': systemKey,
          ...section.toJson(),
        },
      ),
    );

    await upsertBikeSystemState(
      BikeSystemState(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: systemKey,
        location: location,
        overallStatus: section.overallStatus,
        statusNote: summary.isEmpty ? null : _truncateForStateNote(summary),
        lastReviewedAt: observedAt,
        payload: {
          'source': 'diagnosis_sheet',
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
        },
      ),
    );

    if (section.padWearPercent != null) {
      await createBikeObservation(
        BikeObservation(
          tenantId: job.tenantId,
          bikeId: jobBike.bikeId,
          jobId: job.id,
          jobBikeId: jobBike.id,
          systemKey: systemKey,
          componentSlotKey: 'brake_pad',
          location: location,
          observationKind: BikeObservationKind.measurement,
          observationKey: 'pad_wear_percent',
          title: 'Medición desgaste de pastillas',
          valueNumeric: section.padWearPercent,
          unit: '%',
          severity: _severityFromWearPercent(section.padWearPercent),
          observedAt: observedAt,
          source: 'job_diagnosis_sync',
          sourceField: 'diagnosis_sheet',
          payload: {
            'job_number': job.jobNumber,
            'template_key': diagnosisSheet.templateKey,
          },
        ),
      );
    }

    await _createBrakeConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: systemKey,
      location: location,
      componentSlotKey: 'brake_pad',
      observationKey: 'pad_contamination_status',
      title: 'Contaminacion de pastillas',
      statusValue: section.padContaminationStatus,
    );

    if (section.rotorThicknessMm != null) {
      await createBikeObservation(
        BikeObservation(
          tenantId: job.tenantId,
          bikeId: jobBike.bikeId,
          jobId: job.id,
          jobBikeId: jobBike.id,
          systemKey: systemKey,
          componentSlotKey: 'rotor',
          location: location,
          observationKind: BikeObservationKind.measurement,
          observationKey: 'rotor_thickness_mm',
          title: 'Medición espesor de rotor',
          valueNumeric: section.rotorThicknessMm,
          unit: 'mm',
          severity: _severityFromRotorThickness(section.rotorThicknessMm),
          observedAt: observedAt,
          source: 'job_diagnosis_sync',
          sourceField: 'diagnosis_sheet',
          payload: {
            'job_number': job.jobNumber,
            'template_key': diagnosisSheet.templateKey,
          },
        ),
      );
    }

    await _createBrakeConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: systemKey,
      location: location,
      componentSlotKey: 'rotor',
      observationKey: 'rotor_trueness_status',
      title: 'Alineacion del rotor',
      statusValue: section.rotorTruenessStatus,
    );

    await _createBrakeConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: systemKey,
      location: location,
      componentSlotKey: 'rotor',
      observationKey: 'rotor_contamination_status',
      title: 'Contaminacion del rotor',
      statusValue: section.rotorContaminationStatus,
    );

    if (section.symptomKeys.isNotEmpty) {
      final symptomLabels = section.symptomKeys
          .map(_diagnosisSymptomLabel)
          .whereType<String>()
          .toList();
      await createBikeObservation(
        BikeObservation(
          tenantId: job.tenantId,
          bikeId: jobBike.bikeId,
          jobId: job.id,
          jobBikeId: jobBike.id,
          systemKey: systemKey,
          location: location,
          observationKind: BikeObservationKind.conditionAssessment,
          observationKey: 'brake_symptoms',
          title: 'Sintomas del freno',
          summary: symptomLabels.join(', '),
          severity: BikeMemorySeverity.warning,
          observedAt: observedAt,
          source: 'job_diagnosis_sync',
          sourceField: 'diagnosis_sheet',
          payload: {
            'job_number': job.jobNumber,
            'template_key': diagnosisSheet.templateKey,
            'symptom_keys': section.symptomKeys,
          },
        ),
      );
    }
  }

  Future<void> _syncWheelDiagnosisSection({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required DateTime observedAt,
    required String systemKey,
    required String title,
    required BikeMemoryLocation location,
    required WheelDiagnosisSheet section,
  }) async {
    if (!section.hasMeaningfulData) return;

    final noteParts = <String>[];
    _appendDiagnosisSummaryPart(
      noteParts,
      'Cubierta',
      _diagnosisConditionLabel(section.tireCondition),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Aro',
      _diagnosisConditionLabel(section.rimCondition),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Rayos',
      _diagnosisConditionLabel(section.spokeCondition),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Maza',
      _diagnosisConditionLabel(section.hubBearingCondition),
    );
    _appendDiagnosisSummaryPart(
      noteParts,
      'Tubeless',
      _diagnosisConditionLabel(section.tubelessStatus),
    );
    if (section.notes != null && section.notes!.trim().isNotEmpty) {
      noteParts.add(section.notes!.trim());
    }
    final summary = noteParts.join(' | ');

    await createBikeObservation(
      BikeObservation(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: systemKey,
        location: location,
        observationKind: BikeObservationKind.conditionAssessment,
        observationKey: 'diagnosis_sheet_$systemKey',
        title: title,
        summary: summary.isEmpty ? null : summary,
        statusValue: section.overallStatus.dbValue,
        severity: _severityFromSystemStatus(section.overallStatus),
        observedAt: observedAt,
        source: 'job_diagnosis_sync',
        sourceField: 'diagnosis_sheet',
        payload: {
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
          'section': systemKey,
          ...section.toJson(),
        },
      ),
    );

    await upsertBikeSystemState(
      BikeSystemState(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: systemKey,
        location: location,
        overallStatus: section.overallStatus,
        statusNote: summary.isEmpty ? null : _truncateForStateNote(summary),
        lastReviewedAt: observedAt,
        payload: {
          'source': 'diagnosis_sheet',
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
        },
      ),
    );

    await _createWheelConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: systemKey,
      location: location,
      componentSlotKey: 'tire',
      observationKey: 'tire_condition',
      title: 'Estado de cubierta',
      statusValue: section.tireCondition,
    );

    await _createWheelConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: systemKey,
      location: location,
      componentSlotKey: 'rim',
      observationKey: 'rim_condition',
      title: 'Estado del aro',
      statusValue: section.rimCondition,
    );

    await _createWheelConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: systemKey,
      location: location,
      componentSlotKey: 'spokes',
      observationKey: 'spoke_condition',
      title: 'Estado de rayos',
      statusValue: section.spokeCondition,
    );

    await _createWheelConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: systemKey,
      location: location,
      componentSlotKey: 'hub',
      observationKey: 'hub_bearing_condition',
      title: 'Estado de rodamientos de maza',
      statusValue: section.hubBearingCondition,
    );

    await _createWheelConditionObservation(
      job: job,
      jobBike: jobBike,
      diagnosisSheet: diagnosisSheet,
      observedAt: observedAt,
      systemKey: systemKey,
      location: location,
      componentSlotKey: 'tubeless_setup',
      observationKey: 'tubeless_status',
      title: 'Estado tubeless',
      statusValue: section.tubelessStatus,
    );
  }

  Future<void> _createBrakeConditionObservation({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required DateTime observedAt,
    required String systemKey,
    required BikeMemoryLocation location,
    required String componentSlotKey,
    required String observationKey,
    required String title,
    required String? statusValue,
  }) async {
    if (statusValue == null || statusValue.trim().isEmpty) return;

    await createBikeObservation(
      BikeObservation(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: systemKey,
        componentSlotKey: componentSlotKey,
        location: location,
        observationKind: BikeObservationKind.conditionAssessment,
        observationKey: observationKey,
        title: title,
        statusValue: statusValue,
        summary: _diagnosisConditionLabel(statusValue),
        severity: _severityFromDiagnosisCondition(statusValue),
        observedAt: observedAt,
        source: 'job_diagnosis_sync',
        sourceField: 'diagnosis_sheet',
        payload: {
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
        },
      ),
    );
  }

  Future<void> _createWheelConditionObservation({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required DateTime observedAt,
    required String systemKey,
    required BikeMemoryLocation location,
    required String componentSlotKey,
    required String observationKey,
    required String title,
    required String? statusValue,
  }) async {
    if (statusValue == null || statusValue.trim().isEmpty) return;

    await createBikeObservation(
      BikeObservation(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: systemKey,
        componentSlotKey: componentSlotKey,
        location: location,
        observationKind: BikeObservationKind.conditionAssessment,
        observationKey: observationKey,
        title: title,
        statusValue: statusValue,
        summary: _diagnosisConditionLabel(statusValue),
        severity: _severityFromDiagnosisCondition(statusValue),
        observedAt: observedAt,
        source: 'job_diagnosis_sync',
        sourceField: 'diagnosis_sheet',
        payload: {
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
        },
      ),
    );
  }

  Future<void> _createDrivetrainConditionObservation({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required DateTime observedAt,
    required String componentSlotKey,
    required String observationKey,
    required String title,
    required String? statusValue,
  }) async {
    if (statusValue == null || statusValue.trim().isEmpty) return;

    await createBikeObservation(
      BikeObservation(
        tenantId: job.tenantId,
        bikeId: jobBike.bikeId,
        jobId: job.id,
        jobBikeId: jobBike.id,
        systemKey: 'drivetrain',
        componentSlotKey: componentSlotKey,
        location: BikeMemoryLocation.center,
        observationKind: BikeObservationKind.conditionAssessment,
        observationKey: observationKey,
        title: title,
        statusValue: statusValue,
        summary: _diagnosisConditionLabel(statusValue),
        severity: _severityFromDiagnosisCondition(statusValue),
        observedAt: observedAt,
        source: 'job_diagnosis_sync',
        sourceField: 'diagnosis_sheet',
        payload: {
          'job_number': job.jobNumber,
          'template_key': diagnosisSheet.templateKey,
        },
      ),
    );
  }

  BikeMemorySeverity? _severityFromSystemStatus(
    BikeSystemOverallStatus status,
  ) {
    switch (status) {
      case BikeSystemOverallStatus.ok:
      case BikeSystemOverallStatus.unknown:
        return null;
      case BikeSystemOverallStatus.attention:
        return BikeMemorySeverity.warning;
      case BikeSystemOverallStatus.critical:
        return BikeMemorySeverity.critical;
    }
  }

  BikeMemorySeverity? _severityFromWearPercent(double? value) {
    if (value == null) return null;
    if (value >= 75) return BikeMemorySeverity.critical;
    if (value >= 50) return BikeMemorySeverity.warning;
    return null;
  }

  BikeMemorySeverity? _severityFromDiagnosisCondition(String? value) {
    switch (value) {
      case 'contaminated':
      case 'replace':
      case 'worn_out':
      case 'failing':
      case 'broken':
      case 'bent':
      case 'damaged':
      case 'cracked':
        return BikeMemorySeverity.critical;
      case 'dry':
      case 'dirty':
      case 'attention':
      case 'worn':
      case 'misaligned':
      case 'slow':
      case 'sticky':
      case 'loose':
      case 'uneven':
      case 'rough':
      case 'play':
      case 'service':
      case 'leaking':
      case 'dry_sealant':
        return BikeMemorySeverity.warning;
      default:
        return null;
    }
  }

  BikeMemorySeverity? _severityFromRotorThickness(double? value) {
    if (value == null) return null;
    if (value <= 1.5) return BikeMemorySeverity.critical;
    if (value <= 1.7) return BikeMemorySeverity.warning;
    return null;
  }

  void _appendDiagnosisSummaryPart(
    List<String> parts,
    String label,
    String? value,
  ) {
    if (value == null || value.trim().isEmpty) return;
    parts.add('$label $value');
  }

  String _formatChainWearGaugeSummary(double storedPercent) {
    final gaugeValue = storedPercent / 100;
    return gaugeValue.toStringAsFixed(gaugeValue >= 1 ? 1 : 2);
  }

  String? _diagnosisConditionLabel(String? value) {
    switch (value) {
      case 'ok':
        return 'OK';
      case 'light':
        return 'Leve';
      case 'moderate':
        return 'Moderado';
      case 'replace':
        return 'Reemplazar';
      case 'dry':
        return 'Seca';
      case 'dirty':
        return 'Sucio';
      case 'contaminated':
        return 'Contaminado';
      case 'attention':
        return 'Con atención';
      case 'worn':
        return 'Desgastado';
      case 'worn_out':
        return 'Muy desgastado';
      case 'misaligned':
        return 'Desalineado';
      case 'failing':
        return 'Con falla';
      case 'slow':
        return 'Lento';
      case 'sticky':
        return 'Pegado';
      case 'broken':
        return 'Roto';
      case 'bent':
        return 'Golpeado / desviado';
      case 'damaged':
        return 'Dañado';
      case 'cracked':
        return 'Fisurado';
      case 'loose':
        return 'Suelto';
      case 'uneven':
        return 'Disparejo';
      case 'rough':
        return 'Áspero';
      case 'play':
        return 'Con juego';
      case 'service':
        return 'Requiere servicio';
      case 'leaking':
        return 'Pierde aire';
      case 'dry_sealant':
        return 'Líquido seco';
      case 'not_applicable':
        return 'No aplica';
      default:
        return null;
    }
  }

  String? _diagnosisSymptomLabel(String key) {
    switch (key) {
      case 'noise':
        return 'Ruido';
      case 'vibration':
        return 'Vibracion';
      case 'rubbing':
        return 'Roce constante';
      case 'low_power':
        return 'Poca potencia';
      case 'spongy_lever':
        return 'Maneta esponjosa';
      case 'intermittent':
        return 'Frenado intermitente';
      default:
        return null;
    }
  }

  Future<void> _syncCompletedJobBikeItems({
    required MechanicJob job,
    required MechanicJobBike jobBike,
    required List<MechanicJobItem> items,
    String sourceOverride = 'job_item_sync',
  }) async {
    final performedAt = _resolveJobItemPerformedAt(job);

    for (final item in items) {
      final targets = _inferTargetsFromItem(item);
      if (targets.isEmpty) continue;

      for (final target in targets) {
        final existingIntervention = await _findExistingDerivedIntervention(
          jobId: job.id!,
          bikeId: jobBike.bikeId,
          target: target,
          item: item,
          source: sourceOverride,
        );

        String? fromLifecycleId;
        String? toLifecycleId;

        if (target.createsLifecycle && target.componentSlotKey != null) {
          final currentLifecycle = await _findCurrentLifecycle(
            bikeId: jobBike.bikeId,
            componentSlotKey: target.componentSlotKey!,
            location: target.location,
          );

          final currentMatchesThisJob = currentLifecycle != null &&
              currentLifecycle.jobId == job.id &&
              currentLifecycle.productId == item.productId &&
              currentLifecycle.serviceProductId == item.serviceProductId &&
              currentLifecycle.componentLabel == item.productName;

          if (currentLifecycle != null) {
            fromLifecycleId = currentLifecycle.id;
          }

          if (!currentMatchesThisJob) {
            if (currentLifecycle != null && currentLifecycle.id != null) {
              await Supabase.instance.client
                  .from('bike_component_lifecycles')
                  .update({
                'status': BikeComponentLifecycleStatus.superseded.dbValue,
                'removed_at': performedAt.toIso8601String(),
                'removal_reason': 'replaced',
                'updated_at': DateTime.now().toIso8601String(),
              }).eq('id', currentLifecycle.id!);
            }

            final newLifecycle = await createBikeComponentLifecycle(
              BikeComponentLifecycle(
                tenantId: job.tenantId,
                bikeId: jobBike.bikeId,
                jobId: job.id,
                jobBikeId: jobBike.id,
                mechanicJobItemId: item.id,
                productId: item.productId,
                serviceProductId: item.serviceProductId,
                systemKey: target.systemKey,
                componentSlotKey: target.componentSlotKey!,
                location: target.location,
                componentLabel: item.productName,
                status: BikeComponentLifecycleStatus.installed,
                installedAt: performedAt,
                source: sourceOverride,
                notes: item.notes,
                payload: {
                  'job_number': job.jobNumber,
                  'item_type': item.itemType,
                },
              ),
            );
            toLifecycleId = newLifecycle.id;
          } else {
            toLifecycleId = currentLifecycle.id;
          }
        }

        final interventionPayload = {
          'job_number': job.jobNumber,
          'item_type': item.itemType,
          'product_name': item.productName,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'total_price': item.totalPrice,
          'notes': item.notes,
        };

        if (existingIntervention == null) {
          await createBikeIntervention(
            BikeIntervention(
              tenantId: job.tenantId,
              bikeId: jobBike.bikeId,
              jobId: job.id,
              jobBikeId: jobBike.id,
              mechanicJobItemId: item.id,
              productId: item.productId,
              serviceProductId: item.serviceProductId,
              fromLifecycleId: fromLifecycleId,
              toLifecycleId: toLifecycleId,
              systemKey: target.systemKey,
              componentSlotKey: target.componentSlotKey,
              location: target.location,
              interventionType: target.interventionType,
              title: _buildInterventionTitle(target, item),
              summary: _buildInterventionSummary(item),
              performedAt: performedAt,
              source: sourceOverride,
              payload: interventionPayload,
            ),
          );
        } else if (existingIntervention.id != null) {
          await Supabase.instance.client.from('bike_interventions').update({
            'mechanic_job_item_id': item.id,
            'product_id': item.productId,
            'service_product_id': item.serviceProductId,
            'from_lifecycle_id': fromLifecycleId,
            'to_lifecycle_id': toLifecycleId,
            'summary': _buildInterventionSummary(item),
            'performed_at': performedAt.toIso8601String(),
            'payload': interventionPayload,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', existingIntervention.id!);
        }

        await upsertBikeSystemState(
          BikeSystemState(
            tenantId: job.tenantId,
            bikeId: jobBike.bikeId,
            jobId: job.id,
            jobBikeId: jobBike.id,
            systemKey: target.systemKey,
            location: target.location,
            overallStatus: BikeSystemOverallStatus.ok,
            statusNote:
                _truncateForStateNote(_buildInterventionTitle(target, item)),
            lastReviewedAt: performedAt,
            payload: {
              'source': sourceOverride,
              'job_number': job.jobNumber,
            },
          ),
        );
      }
    }
  }

  DateTime _resolveJobBikeDiagnosisObservedAt(
    MechanicJob job,
    MechanicJobBike jobBike,
  ) {
    return jobBike.diagnosisSheetUpdatedAt ??
        job.statusUpdatedAt ??
        job.diagnosticSentAt ??
        job.startedAt ??
        job.arrivalDate;
  }

  DateTime _resolveJobItemPerformedAt(MechanicJob job) {
    return job.completedAt ??
        job.deliveredAt ??
        job.statusUpdatedAt ??
        job.startedAt ??
        job.arrivalDate;
  }

  DateTime _resolveJobCompletionEventAt(MechanicJob job) {
    if (job.status == JobStatus.entregado) {
      return job.deliveredAt ??
          job.completedAt ??
          job.statusUpdatedAt ??
          job.arrivalDate;
    }

    return job.completedAt ??
        job.statusUpdatedAt ??
        job.deliveredAt ??
        job.arrivalDate;
  }

  Future<Map<String, _BikeSystemStateTarget>> _clearDerivedBikeMemoryForJob(
    String jobId,
  ) async {
    final targets = <String, _BikeSystemStateTarget>{};

    void registerTarget({
      String? bikeId,
      String? systemKey,
      String? locationKey,
    }) {
      if (bikeId == null || bikeId.isEmpty) return;
      if (systemKey == null || systemKey.isEmpty) return;

      final target = _BikeSystemStateTarget(
        bikeId: bikeId,
        systemKey: systemKey,
        location: BikeMemoryLocation.fromDbValue(locationKey),
      );
      targets[target.key] = target;
    }

    try {
      final observationRows = await Supabase.instance.client
          .from('bike_observations')
          .select('id,bike_id,system_key,location_key')
          .eq('job_id', jobId)
          .inFilter('source', _derivedJobObservationSources);

      for (final row in observationRows as List) {
        final json = row as Map<String, dynamic>;
        registerTarget(
          bikeId: json['bike_id']?.toString(),
          systemKey: json['system_key']?.toString(),
          locationKey: json['location_key']?.toString(),
        );
      }

      if ((observationRows as List).isNotEmpty) {
        await Supabase.instance.client
            .from('bike_observations')
            .delete()
            .eq('job_id', jobId)
            .inFilter('source', _derivedJobObservationSources);
      }

      final stateRows = await Supabase.instance.client
          .from('bike_system_states')
          .select('id,bike_id,system_key,location_key,payload')
          .eq('job_id', jobId);

      final derivedStateIds = <String>[];
      for (final row in stateRows as List) {
        final json = row as Map<String, dynamic>;
        final payload = json['payload'] is Map
            ? Map<String, dynamic>.from(json['payload'] as Map)
            : const <String, dynamic>{};
        final source = payload['source']?.toString();
        if (!_derivedJobStateSources.contains(source)) continue;

        final id = json['id']?.toString();
        if (id != null && id.isNotEmpty) {
          derivedStateIds.add(id);
        }

        registerTarget(
          bikeId: json['bike_id']?.toString(),
          systemKey: json['system_key']?.toString(),
          locationKey: json['location_key']?.toString(),
        );
      }

      if (derivedStateIds.isNotEmpty) {
        await Supabase.instance.client
            .from('bike_system_states')
            .delete()
            .inFilter('id', derivedStateIds);
      }

      final interventionRows = await Supabase.instance.client
          .from('bike_interventions')
          .select(
              'id,bike_id,system_key,location_key,from_lifecycle_id,to_lifecycle_id')
          .eq('job_id', jobId)
          .inFilter('source', _derivedJobItemSources);

      final interventionIds = <String>[];
      final previousLifecycleIds = <String>{};
      final deletedLifecycleIds = <String>{};

      for (final row in interventionRows as List) {
        final json = row as Map<String, dynamic>;
        final id = json['id']?.toString();
        if (id != null && id.isNotEmpty) {
          interventionIds.add(id);
        }

        final fromLifecycleId = json['from_lifecycle_id']?.toString();
        if (fromLifecycleId != null && fromLifecycleId.isNotEmpty) {
          previousLifecycleIds.add(fromLifecycleId);
        }

        final toLifecycleId = json['to_lifecycle_id']?.toString();
        if (toLifecycleId != null && toLifecycleId.isNotEmpty) {
          deletedLifecycleIds.add(toLifecycleId);
        }

        registerTarget(
          bikeId: json['bike_id']?.toString(),
          systemKey: json['system_key']?.toString(),
          locationKey: json['location_key']?.toString(),
        );
      }

      if (interventionIds.isNotEmpty) {
        await Supabase.instance.client
            .from('bike_interventions')
            .delete()
            .inFilter('id', interventionIds);
      }

      final lifecycleRows = await Supabase.instance.client
          .from('bike_component_lifecycles')
          .select('id,bike_id,system_key,component_slot_key,location_key')
          .eq('job_id', jobId)
          .inFilter('source', _derivedJobItemSources);

      for (final row in lifecycleRows as List) {
        final json = row as Map<String, dynamic>;
        final id = json['id']?.toString();
        if (id != null && id.isNotEmpty) {
          deletedLifecycleIds.add(id);
        }

        registerTarget(
          bikeId: json['bike_id']?.toString(),
          systemKey: json['system_key']?.toString(),
          locationKey: json['location_key']?.toString(),
        );
      }

      if (deletedLifecycleIds.isNotEmpty) {
        await Supabase.instance.client
            .from('bike_component_lifecycles')
            .delete()
            .inFilter('id', deletedLifecycleIds.toList());
      }

      await _restoreSupersededLifecycles(
        previousLifecycleIds: previousLifecycleIds,
        deletedLifecycleIds: deletedLifecycleIds,
      );
    } catch (e) {
      if (kDebugMode) {
        print(
            '⚠️ [BikeshopService] Could not clear derived bike memory for job $jobId: $e');
      }
    }

    return targets;
  }

  Future<void> _restoreSupersededLifecycles({
    required Set<String> previousLifecycleIds,
    required Set<String> deletedLifecycleIds,
  }) async {
    if (previousLifecycleIds.isEmpty) return;

    try {
      final previousRows = await Supabase.instance.client
          .from('bike_component_lifecycles')
          .select('id,bike_id,component_slot_key,location_key,status')
          .inFilter('id', previousLifecycleIds.toList());

      for (final row in previousRows as List) {
        final json = row as Map<String, dynamic>;
        final lifecycleId = json['id']?.toString();
        if (lifecycleId == null || lifecycleId.isEmpty) continue;
        if (deletedLifecycleIds.contains(lifecycleId)) continue;

        final bikeId = json['bike_id']?.toString();
        final componentSlotKey = json['component_slot_key']?.toString();
        final locationKey = json['location_key']?.toString();

        if (bikeId == null ||
            bikeId.isEmpty ||
            componentSlotKey == null ||
            componentSlotKey.isEmpty) {
          continue;
        }

        final installedRows = await Supabase.instance.client
            .from('bike_component_lifecycles')
            .select('id')
            .eq('bike_id', bikeId)
            .eq('component_slot_key', componentSlotKey)
            .eq('location_key', locationKey ?? BikeMemoryLocation.none.dbValue)
            .eq('status', BikeComponentLifecycleStatus.installed.dbValue)
            .not('id', 'eq', lifecycleId)
            .limit(1);

        if ((installedRows as List).isNotEmpty) continue;

        await Supabase.instance.client
            .from('bike_component_lifecycles')
            .update({
          'status': BikeComponentLifecycleStatus.installed.dbValue,
          'removed_at': null,
          'removal_reason': null,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', lifecycleId);
      }
    } catch (e) {
      if (kDebugMode) {
        print(
            '⚠️ [BikeshopService] Could not restore superseded lifecycles: $e');
      }
    }
  }

  Future<void> _refreshDerivedSystemStates(
    Iterable<_BikeSystemStateTarget> targets,
  ) async {
    for (final target in targets) {
      await _refreshDerivedSystemState(target);
    }
  }

  Future<void> _refreshDerivedSystemState(
    _BikeSystemStateTarget target,
  ) async {
    try {
      final observationRows = await Supabase.instance.client
          .from('bike_observations')
          .select()
          .eq('bike_id', target.bikeId)
          .eq('system_key', target.systemKey)
          .eq('location_key', target.location.dbValue)
          .order('observed_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(12);

      final observations = (observationRows as List)
          .map((row) => BikeObservation.fromJson(row as Map<String, dynamic>))
          .toList();

      final interventionRows = await Supabase.instance.client
          .from('bike_interventions')
          .select()
          .eq('bike_id', target.bikeId)
          .eq('system_key', target.systemKey)
          .eq('location_key', target.location.dbValue)
          .order('performed_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(1);

      final observationState =
          _buildDerivedSystemStateFromObservations(observations);
      final interventionState = (interventionRows as List).isNotEmpty
          ? _buildDerivedSystemStateFromIntervention(
              BikeIntervention.fromJson(
                interventionRows.first,
              ),
            )
          : null;

      BikeSystemState? nextState;
      if (observationState != null && interventionState != null) {
        final observationAt = observationState.lastReviewedAt;
        final interventionAt = interventionState.lastReviewedAt;
        if (observationAt == null) {
          nextState = interventionState;
        } else if (interventionAt == null ||
            observationAt.isAfter(interventionAt)) {
          nextState = observationState;
        } else {
          nextState = interventionState;
        }
      } else {
        nextState = observationState ?? interventionState;
      }

      if (nextState == null) {
        await Supabase.instance.client
            .from('bike_system_states')
            .delete()
            .eq('bike_id', target.bikeId)
            .eq('system_key', target.systemKey)
            .eq('location_key', target.location.dbValue);
        return;
      }

      await upsertBikeSystemState(nextState);
    } catch (e) {
      if (kDebugMode) {
        print(
            '⚠️ [BikeshopService] Could not refresh derived state for ${target.key}: $e');
      }
    }
  }

  BikeSystemState? _buildDerivedSystemStateFromObservations(
    List<BikeObservation> observations,
  ) {
    for (final observation in observations) {
      final status = _deriveSystemStatusFromObservation(observation);
      if (status == null) continue;

      final noteSource = observation.summary?.trim().isNotEmpty == true
          ? observation.summary!.trim()
          : observation.title;

      return BikeSystemState(
        tenantId: observation.tenantId,
        bikeId: observation.bikeId,
        jobId: observation.jobId,
        jobBikeId: observation.jobBikeId,
        systemKey: observation.systemKey,
        location: observation.location,
        overallStatus: status,
        statusNote: _truncateForStateNote(noteSource),
        lastReviewedAt: observation.observedAt,
        payload: {
          'source': observation.source,
          'job_number': observation.payload['job_number'],
          'derived_from': 'observation',
          'observation_key': observation.observationKey,
        },
      );
    }

    return null;
  }

  BikeSystemState _buildDerivedSystemStateFromIntervention(
    BikeIntervention intervention,
  ) {
    final noteSource = intervention.summary?.trim().isNotEmpty == true
        ? intervention.summary!.trim()
        : intervention.title;

    return BikeSystemState(
      tenantId: intervention.tenantId,
      bikeId: intervention.bikeId,
      jobId: intervention.jobId,
      jobBikeId: intervention.jobBikeId,
      systemKey: intervention.systemKey,
      location: intervention.location,
      overallStatus: BikeSystemOverallStatus.ok,
      statusNote: _truncateForStateNote(noteSource),
      lastReviewedAt: intervention.performedAt,
      payload: {
        'source': intervention.source,
        'job_number': intervention.payload['job_number'],
        'derived_from': 'intervention',
        'intervention_type': intervention.interventionType.dbValue,
      },
    );
  }

  BikeSystemOverallStatus? _deriveSystemStatusFromObservation(
    BikeObservation observation,
  ) {
    final explicitStatus = observation.statusValue?.trim();
    if (explicitStatus != null && explicitStatus.isNotEmpty) {
      for (final status in BikeSystemOverallStatus.values) {
        if (status.dbValue == explicitStatus) {
          return status;
        }
      }
    }

    switch (observation.severity) {
      case BikeMemorySeverity.critical:
        return BikeSystemOverallStatus.critical;
      case BikeMemorySeverity.warning:
        return BikeSystemOverallStatus.attention;
      case BikeMemorySeverity.info:
        return BikeSystemOverallStatus.ok;
      case null:
        break;
    }

    if (observation.observationKind == BikeObservationKind.confirmation) {
      return BikeSystemOverallStatus.ok;
    }

    return null;
  }

  Future<BikeIntervention?> _findExistingDerivedIntervention({
    required String jobId,
    required String bikeId,
    required _BikeMemoryTarget target,
    required MechanicJobItem item,
    required String source,
  }) async {
    try {
      var query = Supabase.instance.client
          .from('bike_interventions')
          .select()
          .eq('job_id', jobId)
          .eq('bike_id', bikeId)
          .eq('system_key', target.systemKey)
          .eq('location_key', target.location.dbValue)
          .eq('source', source);

      if (target.componentSlotKey != null) {
        query = query.eq('component_slot_key', target.componentSlotKey!);
      } else {
        query = query.eq('title', _buildInterventionTitle(target, item));
      }

      final data = await query.limit(1);
      if (data.isNotEmpty) {
        return BikeIntervention.fromJson(data.first);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [BikeshopService] Could not fetch existing intervention: $e');
      }
    }
    return null;
  }

  Future<BikeComponentLifecycle?> _findCurrentLifecycle({
    required String bikeId,
    required String componentSlotKey,
    required BikeMemoryLocation location,
  }) async {
    try {
      final data = await Supabase.instance.client
          .from('bike_component_lifecycles')
          .select()
          .eq('bike_id', bikeId)
          .eq('component_slot_key', componentSlotKey)
          .eq('location_key', location.dbValue)
          .eq('status', BikeComponentLifecycleStatus.installed.dbValue)
          .limit(1);

      if (data.isNotEmpty) {
        return BikeComponentLifecycle.fromJson(data.first);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [BikeshopService] Could not fetch current lifecycle: $e');
      }
    }
    return null;
  }

  List<_BikeMemoryTarget> _inferTargetsFromItem(
    MechanicJobItem item, {
    bool preferStoredMetadata = true,
  }) {
    if (preferStoredMetadata &&
        item.systemKey != null &&
        item.systemKey!.isNotEmpty) {
      return [
        _BikeMemoryTarget(
          systemKey: item.systemKey!,
          componentSlotKey: item.componentSlotKey,
          location: item.location,
          interventionType: _defaultInterventionTypeForStoredTarget(item),
          createsLifecycle: _defaultCreatesLifecycleForStoredTarget(item),
        ),
      ];
    }

    final haystack = _normalizeText('${item.productName} ${item.notes ?? ''}');
    final location = item.location != BikeMemoryLocation.none
        ? item.location
        : _inferLocationFromText(haystack);
    final isServiceItem =
        item.itemType == 'service' || item.serviceProductId != null;

    if (_containsAny(haystack, ['cadena', 'chain'])) {
      return [
        _BikeMemoryTarget(
          systemKey: 'drivetrain',
          componentSlotKey: isServiceItem ? null : 'chain',
          location: BikeMemoryLocation.none,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.replacement,
          createsLifecycle: !isServiceItem,
        ),
      ];
    }

    if (_containsAny(haystack, ['cassette', 'piñon', 'pinon'])) {
      return [
        _BikeMemoryTarget(
          systemKey: 'drivetrain',
          componentSlotKey: isServiceItem ? null : 'cassette',
          location: BikeMemoryLocation.none,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.replacement,
          createsLifecycle: !isServiceItem,
        ),
      ];
    }

    if (_containsAny(haystack, ['plato', 'chainring', 'corona'])) {
      return [
        _BikeMemoryTarget(
          systemKey: 'drivetrain',
          componentSlotKey: isServiceItem ? null : 'chainring',
          location: BikeMemoryLocation.none,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.replacement,
          createsLifecycle: !isServiceItem,
        ),
      ];
    }

    if (_containsAny(haystack, ['hanger', 'patilla'])) {
      return [
        _BikeMemoryTarget(
          systemKey: 'drivetrain',
          componentSlotKey: isServiceItem ? null : 'derailleur_hanger',
          location: BikeMemoryLocation.none,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.replacement,
          createsLifecycle: !isServiceItem,
        ),
      ];
    }

    if (_containsAny(haystack, ['rotor', 'disco'])) {
      final brakeSystem = _brakeSystemForLocation(location);
      return [
        _BikeMemoryTarget(
          systemKey: brakeSystem,
          componentSlotKey:
              isServiceItem ? null : _slotForLocation(location, 'rotor'),
          location: location,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.replacement,
          createsLifecycle: !isServiceItem,
        ),
      ];
    }

    if (_containsAny(haystack, ['pastilla', 'pad'])) {
      final brakeSystem = _brakeSystemForLocation(location);
      return [
        _BikeMemoryTarget(
          systemKey: brakeSystem,
          componentSlotKey:
              isServiceItem ? null : _slotForLocation(location, 'pads'),
          location: location,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.replacement,
          createsLifecycle: !isServiceItem,
        ),
      ];
    }

    if (_containsAny(haystack, ['freno', 'brake', 'sangrado', 'bleed'])) {
      return [
        _BikeMemoryTarget(
          systemKey: _brakeSystemForLocation(location),
          componentSlotKey: null,
          location: location,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.adjustment,
          createsLifecycle: false,
        ),
      ];
    }

    if (_containsAny(haystack, ['cubierta', 'neumatic', 'tire', 'tyre'])) {
      return [
        _BikeMemoryTarget(
          systemKey: _wheelSystemForLocation(location),
          componentSlotKey:
              isServiceItem ? null : _slotForLocation(location, 'tire'),
          location: location,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.replacement,
          createsLifecycle: !isServiceItem,
        ),
      ];
    }

    if (_containsAny(
        haystack, ['rueda', 'wheel', 'centrado', 'rayo', 'aro', 'llanta'])) {
      return [
        _BikeMemoryTarget(
          systemKey: _wheelSystemForLocation(location),
          componentSlotKey: null,
          location: location,
          interventionType: isServiceItem
              ? BikeInterventionType.service
              : BikeInterventionType.adjustment,
          createsLifecycle: false,
        ),
      ];
    }

    return const [];
  }

  List<_BikeMemoryTarget> _inferTargetsFromText(String text) {
    final normalized = _normalizeText(text);
    final targets = <String, _BikeMemoryTarget>{};

    void add(_BikeMemoryTarget target) {
      targets[target.key] = target;
    }

    if (_containsAny(normalized, [
      'cadena',
      'cassette',
      'desviador',
      'cambio',
      'transmision',
      'transmisión',
      'drivetrain'
    ])) {
      add(const _BikeMemoryTarget(
        systemKey: 'drivetrain',
        componentSlotKey: null,
        location: BikeMemoryLocation.none,
        interventionType: BikeInterventionType.inspection,
        createsLifecycle: false,
      ));
    }

    if (_containsAny(
        normalized, ['freno', 'rotor', 'disco', 'pastilla', 'brake'])) {
      final location = _inferLocationFromText(normalized);
      add(_BikeMemoryTarget(
        systemKey: _brakeSystemForLocation(location),
        componentSlotKey: null,
        location: location,
        interventionType: BikeInterventionType.inspection,
        createsLifecycle: false,
      ));
    }

    if (_containsAny(normalized,
        ['rueda', 'aro', 'llanta', 'rayo', 'neumatic', 'cubierta', 'wheel'])) {
      final location = _inferLocationFromText(normalized);
      add(_BikeMemoryTarget(
        systemKey: _wheelSystemForLocation(location),
        componentSlotKey: null,
        location: location,
        interventionType: BikeInterventionType.inspection,
        createsLifecycle: false,
      ));
    }

    return targets.values.toList();
  }

  BikeMemorySeverity _inferSeverityFromText(String text) {
    final normalized = _normalizeText(text);
    if (_containsAny(normalized, [
      'quebrad',
      'roto',
      'critico',
      'crítico',
      'urgente',
      'peligro',
      'sin freno',
    ])) {
      return BikeMemorySeverity.critical;
    }
    return BikeMemorySeverity.warning;
  }

  BikeMemoryLocation _inferLocationFromText(String text) {
    if (_containsAny(text, ['delanter', 'front']))
      return BikeMemoryLocation.front;
    if (_containsAny(text, ['traser', 'rear'])) return BikeMemoryLocation.rear;
    if (_containsAny(text, ['izquierd', 'left']))
      return BikeMemoryLocation.left;
    if (_containsAny(text, ['derech', 'right']))
      return BikeMemoryLocation.right;
    if (_containsAny(text, ['centro', 'center']))
      return BikeMemoryLocation.center;
    return BikeMemoryLocation.none;
  }

  String _brakeSystemForLocation(BikeMemoryLocation location) {
    switch (location) {
      case BikeMemoryLocation.front:
        return 'front_brake';
      case BikeMemoryLocation.rear:
        return 'rear_brake';
      default:
        return 'brakes';
    }
  }

  String _wheelSystemForLocation(BikeMemoryLocation location) {
    switch (location) {
      case BikeMemoryLocation.front:
        return 'front_wheel';
      case BikeMemoryLocation.rear:
        return 'rear_wheel';
      default:
        return 'wheels';
    }
  }

  String _slotForLocation(BikeMemoryLocation location, String baseKey) {
    switch (location) {
      case BikeMemoryLocation.front:
        return 'front_$baseKey';
      case BikeMemoryLocation.rear:
        return 'rear_$baseKey';
      default:
        return baseKey;
    }
  }

  String _buildInterventionTitle(
      _BikeMemoryTarget target, MechanicJobItem item) {
    switch (target.interventionType) {
      case BikeInterventionType.replacement:
        return 'Reemplazo: ${item.productName}';
      case BikeInterventionType.service:
        return 'Servicio: ${item.productName}';
      case BikeInterventionType.adjustment:
        return 'Ajuste: ${item.productName}';
      case BikeInterventionType.installation:
        return 'Instalación: ${item.productName}';
      case BikeInterventionType.removal:
        return 'Retiro: ${item.productName}';
      case BikeInterventionType.inspection:
        return 'Inspección: ${item.productName}';
    }
  }

  String _buildInterventionSummary(MechanicJobItem item) {
    final parts = <String>[];
    parts.add(
        'Cantidad: ${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 2)}');
    if (item.notes != null && item.notes!.trim().isNotEmpty) {
      parts.add(item.notes!.trim());
    }
    return parts.join(' · ');
  }

  String _truncateForStateNote(String text) {
    final normalized = text.trim();
    if (normalized.length <= 180) return normalized;
    return '${normalized.substring(0, 177)}...';
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
  }

  bool _containsAny(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(_normalizeText(needle))) {
        return true;
      }
    }
    return false;
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

      // Join with job_statuses only. Subject data is hydrated separately so
      // the app does not depend on a deployed PostgREST relationship cache.
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

      jobs = await _hydrateJobSubjects(jobs);

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

      // Join with job_statuses only. Subject data is hydrated separately so
      // the app works before the FK relationship is deployed/refreshed.
      final data = await Supabase.instance.client
          .from('mechanic_jobs')
          .select('''
            *,
            job_status:job_statuses(*)
          ''')
          .eq('id', id)
          .isFilter('deleted_at', null) // Filter out soft-deleted
          .maybeSingle();

      if (data == null) return null;
      final hydrated = await _hydrateJobSubjects([
        MechanicJob.fromJson(data),
      ]);
      return hydrated.isNotEmpty ? hydrated.first : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching job: $e');
      rethrow;
    }
  }

  Future<List<MechanicJob>> _hydrateJobSubjects(List<MechanicJob> jobs) async {
    final subjectIds = jobs
        .map((job) => job.subjectId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (subjectIds.isEmpty) return jobs;

    try {
      final subjectRows = await Supabase.instance.client
          .from('job_subjects')
          .select()
          .inFilter('id', subjectIds) as List<dynamic>;

      final subjectById = {
        for (final row in subjectRows)
          (JobSubject.fromJson(row)).id!: JobSubject.fromJson(row)
      };

      return jobs
          .map((job) => job.copyWith(
                subjectData:
                    job.subjectId != null ? subjectById[job.subjectId!] : null,
              ))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [BikeshopService] Could not hydrate job subjects: $e');
      }
      return jobs;
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

      final createdJob = MechanicJob.fromJson(data);
      await _logJobCreatedBikeEvent(createdJob);

      invalidateJobsCache();
      notifyListeners();
      return createdJob;
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

  Future<MechanicJob> updateJob(
    MechanicJob job, {
    bool syncBikeMemory = true,
  }) async {
    try {
      if (job.id == null || job.id!.isEmpty) {
        throw Exception('ID de trabajo inválido');
      }

      final previousJob = await getJobById(job.id!);

      // Use forUpdate: true to exclude arrival_date and created_at from being overwritten
      final data = await _db.update(
          'mechanic_jobs', job.id!, job.toJson(forUpdate: true));
      final updatedJob = MechanicJob.fromJson(data);
      await _logJobCompletionBikeEvent(
        previousJob: previousJob,
        updatedJob: updatedJob,
      );
      if (syncBikeMemory) {
        await _safeSyncBikeMemoryForJob(updatedJob.id);
      }
      invalidateJobsCache();
      notifyListeners();
      return updatedJob;
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

  Future<void> _logBikeRegisteredEvent(Bike bike) async {
    await _safeCreateBikeEvent(
      BikeEvent(
        tenantId: bike.tenantId,
        bikeId: bike.id ?? '',
        eventType: BikeEventType.bikeRegistered,
        eventCategory: BikeEventCategory.state,
        eventDate: bike.createdAt,
        title: 'Bicicleta registrada',
        summary: BikeProfileSummaryBuilder.buildIdentityLine(bike),
        source: 'manual',
        payload: {
          'brand': bike.brand,
          'model': bike.model,
          'year': bike.year,
        },
      ),
    );
  }

  Future<void> _logBikeProfileEvent(
    BikeProfile profile, {
    required bool isCreate,
  }) async {
    if (profile.bikeId.isEmpty) return;

    final technicalValues = profile.technicalValues;
    final intakeProfile = profile.intakeProfile;

    await _safeCreateBikeEvent(
      BikeEvent(
        tenantId: profile.tenantId,
        bikeId: profile.bikeId,
        eventType: isCreate
            ? BikeEventType.profileCreated
            : BikeEventType.profileUpdated,
        eventCategory: BikeEventCategory.state,
        eventDate: profile.updatedAt,
        title: isCreate ? 'Ficha creada' : 'Ficha actualizada',
        summary: _buildProfileEventSummary(
          intakeProfile: intakeProfile,
          technicalValues: technicalValues,
          isCreate: isCreate,
        ),
        source: 'profile_save',
        payload: {
          'hasIntakeProfile': intakeProfile.isNotEmpty,
          'hasTechnicalProfile': technicalValues.isNotEmpty,
          'lastConfirmedAt': profile.lastConfirmedAt?.toIso8601String(),
        },
      ),
    );
  }

  Future<void> _logJobCreatedBikeEvent(MechanicJob job) async {
    final bikeId = job.bikeId;
    if (bikeId == null || bikeId.isEmpty) return;

    await _safeCreateBikeEvent(
      BikeEvent(
        tenantId: job.tenantId,
        bikeId: bikeId,
        jobId: job.id,
        eventType: BikeEventType.jobCreated,
        eventCategory: BikeEventCategory.visit,
        eventDate: job.arrivalDate,
        title: 'Trabajo creado',
        summary: job.clientRequest?.trim().isNotEmpty == true
            ? job.clientRequest!.trim()
            : 'Se abrió la orden ${job.jobNumber}.',
        source: 'job_lifecycle',
        referenceNumber: job.jobNumber,
        payload: {
          'status': job.status.name,
          'priority': job.priority.name,
        },
      ),
    );
  }

  Future<void> _logJobCompletionBikeEvent({
    required MechanicJob? previousJob,
    required MechanicJob updatedJob,
  }) async {
    final bikeId = updatedJob.bikeId;
    if (bikeId == null || bikeId.isEmpty) return;
    final previousStatus = previousJob?.status;
    final newStatus = updatedJob.status;
    final completionStatuses = {
      JobStatus.finalizado,
      JobStatus.entregado,
    };

    if (!completionStatuses.contains(newStatus) ||
        completionStatuses.contains(previousStatus)) {
      return;
    }

    await _safeCreateBikeEvent(
      BikeEvent(
        tenantId: updatedJob.tenantId,
        bikeId: bikeId,
        jobId: updatedJob.id,
        eventType: BikeEventType.jobCompleted,
        eventCategory: BikeEventCategory.visit,
        eventDate: _resolveJobCompletionEventAt(updatedJob),
        title: 'Trabajo completado',
        summary: updatedJob.workPerformed?.trim().isNotEmpty == true
            ? updatedJob.workPerformed!.trim()
            : 'Se completó la orden ${updatedJob.jobNumber}.',
        source: 'job_lifecycle',
        referenceNumber: updatedJob.jobNumber,
        payload: {
          'status': updatedJob.status.name,
          'totalCost': updatedJob.totalCost,
        },
      ),
    );
  }

  String _buildProfileEventSummary({
    required Map<String, dynamic> intakeProfile,
    required Map<String, dynamic> technicalValues,
    required bool isCreate,
  }) {
    final sections = <String>[];
    if (intakeProfile.isNotEmpty) sections.add('ingreso');
    if (technicalValues.isNotEmpty) sections.add('ficha técnica');

    if (sections.isEmpty) {
      return isCreate
          ? 'Se creó la ficha inicial de la bicicleta.'
          : 'Se actualizó la ficha de la bicicleta.';
    }

    final sectionsText = sections.join(' y ');
    return isCreate
        ? 'Se creó la ficha con $sectionsText.'
        : 'Se actualizó $sectionsText.';
  }

  Future<void> _safeCreateBikeEvent(BikeEvent event) async {
    if (event.bikeId.isEmpty || event.tenantId.isEmpty) return;

    try {
      await createBikeEvent(event);
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [BikeshopService] Could not create bike event: $e');
      }
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

  Future<MechanicJobItem> createJobItem(
    MechanicJobItem item, {
    bool syncBikeMemory = true,
  }) async {
    try {
      final resolvedItem = _withResolvedTargetMetadata(item);
      final data =
          await _db.insert('mechanic_job_items', resolvedItem.toJson());
      final createdItem = MechanicJobItem.fromJson(data);
      if (syncBikeMemory &&
          await _jobShouldSyncCompletedItemMemory(createdItem.jobId)) {
        await _safeSyncBikeMemoryForJob(createdItem.jobId);
      }
      notifyListeners();
      return createdItem;
    } catch (e) {
      if (kDebugMode) print('Error creating job item: $e');
      rethrow;
    }
  }

  Future<MechanicJobItem> updateJobItem(
    MechanicJobItem item, {
    bool syncBikeMemory = true,
  }) async {
    try {
      if (item.id == null || item.id!.isEmpty) {
        throw Exception('ID de ítem inválido');
      }

      final resolvedItem = _withResolvedTargetMetadata(item);
      final data = await _db.update(
        'mechanic_job_items',
        item.id!,
        resolvedItem.toJson(),
      );
      final updatedItem = MechanicJobItem.fromJson(data);
      if (syncBikeMemory &&
          await _jobShouldSyncCompletedItemMemory(updatedItem.jobId)) {
        await _safeSyncBikeMemoryForJob(updatedItem.jobId);
      }
      notifyListeners();
      return updatedItem;
    } catch (e) {
      if (kDebugMode) print('Error updating job item: $e');
      rethrow;
    }
  }

  Future<void> deleteJobItem(
    String id, {
    bool syncBikeMemory = true,
  }) async {
    try {
      if (id.isEmpty) throw Exception('ID de ítem inválido');

      String? jobId;
      if (syncBikeMemory) {
        final existing = await Supabase.instance.client
            .from('mechanic_job_items')
            .select('job_id')
            .eq('id', id)
            .maybeSingle();
        jobId = existing?['job_id']?.toString();
      }

      await _db.delete('mechanic_job_items', id);
      if (syncBikeMemory && await _jobShouldSyncCompletedItemMemory(jobId)) {
        await _safeSyncBikeMemoryForJob(jobId);
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting job item: $e');
      rethrow;
    }
  }

  MechanicJobItem _withResolvedTargetMetadata(MechanicJobItem item) {
    if (item.systemKey != null && item.systemKey!.isNotEmpty) {
      final explicitInterventionType = item.interventionType ??
          _defaultInterventionTypeForStoredTarget(item);
      final explicitCreatesLifecycle = item.createsLifecycle ||
          _defaultCreatesLifecycleForStoredTarget(item);

      return item.copyWith(
        location: item.location,
        interventionType: explicitInterventionType,
        createsLifecycle: explicitCreatesLifecycle,
      );
    }

    final inferredTargets =
        _inferTargetsFromItem(item, preferStoredMetadata: false);
    if (inferredTargets.isEmpty) {
      return item.copyWith(location: item.location);
    }

    final primaryTarget = inferredTargets.first;
    return item.copyWith(
      systemKey: primaryTarget.systemKey,
      componentSlotKey: primaryTarget.componentSlotKey,
      location: primaryTarget.location,
      interventionType: primaryTarget.interventionType,
      createsLifecycle: primaryTarget.createsLifecycle,
    );
  }

  BikeInterventionType _defaultInterventionTypeForStoredTarget(
    MechanicJobItem item,
  ) {
    final isServiceItem =
        item.itemType == 'service' || item.serviceProductId != null;
    if (item.interventionType != null) return item.interventionType!;
    if (isServiceItem) return BikeInterventionType.service;
    if (item.componentSlotKey != null && item.componentSlotKey!.isNotEmpty) {
      return BikeInterventionType.replacement;
    }
    return BikeInterventionType.adjustment;
  }

  bool _defaultCreatesLifecycleForStoredTarget(MechanicJobItem item) {
    if (item.createsLifecycle) return true;
    final isServiceItem =
        item.itemType == 'service' || item.serviceProductId != null;
    return !isServiceItem &&
        item.componentSlotKey != null &&
        item.componentSlotKey!.isNotEmpty;
  }

  // ============================================================
  // JOB BIKES OPERATIONS (Multi-bike support)
  // ============================================================

  /// Get all bikes for a job (multi-bike support)
  Future<List<MechanicJobBike>> getJobBikes(String jobId) async {
    try {
      if (isJobBikesCacheFresh && _cachedAllJobBikes != null) {
        return List<MechanicJobBike>.from(
            _cachedAllJobBikes![jobId] ?? const []);
      }

      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return [];

      final data = await Supabase.instance.client
          .from('mechanic_job_bikes')
          .select('''
            *,
            bike:bikes(*),
            status:job_statuses(*)
          ''')
          .eq('tenant_id', tenantId)
          .eq('job_id', jobId)
          .order('order_index');

      return (data as List)
          .map((json) => MechanicJobBike.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching job bikes: $e');
      rethrow;
    }
  }

  /// Get all job bikes (for list views - single query optimization)
  Future<Map<String, List<MechanicJobBike>>> getAllJobBikes({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && isJobBikesCacheFresh && _cachedAllJobBikes != null) {
        return _cloneJobBikesMap(_cachedAllJobBikes!);
      }

      if (_isLoadingAllJobBikes && !forceRefresh) {
        while (_isLoadingAllJobBikes) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        if (_cachedAllJobBikes != null) {
          return _cloneJobBikesMap(_cachedAllJobBikes!);
        }
      }

      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return {};

      _isLoadingAllJobBikes = true;
      final data =
          await Supabase.instance.client.from('mechanic_job_bikes').select('''
            *,
            bike:bikes(*),
            status:job_statuses(*)
          ''').eq('tenant_id', tenantId).order('order_index');

      final allJobBikes =
          (data as List).map((json) => MechanicJobBike.fromJson(json)).toList();

      // Group by job_id
      final result = <String, List<MechanicJobBike>>{};
      for (final jb in allJobBikes) {
        result.putIfAbsent(jb.jobId, () => []).add(jb);
      }
      _cacheAllJobBikes(result);
      return _cloneJobBikesMap(result);
    } catch (e) {
      if (kDebugMode) print('Error fetching all job bikes: $e');
      return {};
    } finally {
      _isLoadingAllJobBikes = false;
    }
  }

  /// Add a bike to a job
  Future<MechanicJobBike> addBikeToJob(
    MechanicJobBike jobBike, {
    bool syncBikeMemory = true,
  }) async {
    try {
      final data = await _db.insert('mechanic_job_bikes', jobBike.toJson());
      final createdJobBike = MechanicJobBike.fromJson(data);
      _upsertJobBikeInCache(createdJobBike);
      if (syncBikeMemory) {
        await _safeSyncBikeMemoryForJob(createdJobBike.jobId);
      }
      notifyListeners();
      return createdJobBike;
    } catch (e) {
      if (kDebugMode) print('Error adding bike to job: $e');
      rethrow;
    }
  }

  /// Update a job bike entry
  Future<MechanicJobBike> updateJobBike(
    MechanicJobBike jobBike, {
    bool syncBikeMemory = true,
  }) async {
    try {
      if (jobBike.id == null || jobBike.id!.isEmpty) {
        throw Exception('ID de bicicleta de trabajo inválido');
      }
      final data =
          await _db.update('mechanic_job_bikes', jobBike.id!, jobBike.toJson());
      final updatedJobBike = MechanicJobBike.fromJson(data);
      _upsertJobBikeInCache(updatedJobBike);
      if (syncBikeMemory) {
        await _safeSyncBikeMemoryForJob(updatedJobBike.jobId);
      }
      notifyListeners();
      return updatedJobBike;
    } catch (e) {
      if (kDebugMode) print('Error updating job bike: $e');
      rethrow;
    }
  }

  /// Remove a bike from a job
  Future<void> removeBikeFromJob(
    String jobBikeId, {
    bool syncBikeMemory = true,
  }) async {
    try {
      if (jobBikeId.isEmpty) throw Exception('ID inválido');

      String? jobId;
      if (syncBikeMemory) {
        final existing = await Supabase.instance.client
            .from('mechanic_job_bikes')
            .select('job_id')
            .eq('id', jobBikeId)
            .maybeSingle();
        jobId = existing?['job_id']?.toString();
      }

      await _db.delete('mechanic_job_bikes', jobBikeId);
      _removeJobBikeFromCache(jobBikeId, jobId: jobId);
      if (syncBikeMemory) {
        await _safeSyncBikeMemoryForJob(jobId);
      }
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
          final productData = await _db.selectById(
            'products',
            productId,
            selectColumns: 'id,name,sku,price',
          );
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
          itemType: 'service',
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

      if (kDebugMode) {
        print('⚠️ Invoice creation returned null for job: $jobId');
      }
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

  Future<void> _setupMechanicJobBikesRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        debugPrint(
            '⚠️ [BikeshopService] Cannot setup job bike realtime: no tenant_id');
        return;
      }

      await _jobBikesChannel?.unsubscribe();

      _jobBikesChannel = Supabase.instance.client
          .channel('mechanic_job_bikes_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'mechanic_job_bikes',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: _handleMechanicJobBikeChange,
          )
          .subscribe();

      if (!kReleaseMode) {
        debugPrint('✅ [BikeshopService] Job bike realtime subscription active');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('❌ [BikeshopService] Failed to setup job bike realtime: $e');
      }
    }
  }

  void _handleMechanicJobBikeChange(PostgresChangePayload payload) {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final rawNew = payload.newRecord;
          final jobBikeId = rawNew['id']?.toString();
          if (jobBikeId != null && jobBikeId.isNotEmpty) {
            _fetchAndUpdateJobBike(jobBikeId);
          }
          break;
        case PostgresChangeEvent.delete:
          final rawOld = payload.oldRecord;
          final jobBikeId = rawOld['id']?.toString();
          if (jobBikeId != null && jobBikeId.isNotEmpty) {
            _removeJobBikeFromCache(
              jobBikeId,
              jobId: rawOld['job_id']?.toString(),
            );
            if (!mounted) return;
            _debouncedNotify();
          }
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint(
          '⚠️ [BikeshopService] Error handling job bike realtime change: $e');
      _debouncedNotify();
    }
  }

  Future<void> _fetchAndUpdateJobBike(String jobBikeId) async {
    try {
      final data =
          await Supabase.instance.client.from('mechanic_job_bikes').select('''
            *,
            bike:bikes(*),
            status:job_statuses(*)
          ''').eq('id', jobBikeId).maybeSingle();

      if (data == null) return;

      final jobBike = MechanicJobBike.fromJson(data);
      _upsertJobBikeInCache(jobBike);
      if (!mounted) return;
      _debouncedNotify();
    } catch (e) {
      debugPrint(
          '⚠️ [BikeshopService] Error fetching job bike for surgical update: $e');
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
      // Fetch with job_status join only. Subject data is hydrated separately.
      final data =
          await Supabase.instance.client.from('mechanic_jobs').select('''
            *,
            job_status:job_statuses(*)
          ''').eq('id', jobId).isFilter('deleted_at', null).maybeSingle();

      if (data != null) {
        final hydrated = await _hydrateJobSubjects([
          MechanicJob.fromJson(data),
        ]);
        final job = hydrated.first;
        _surgicalUpdateJob(job);
        debugPrint('🔧 [BikeshopService] Surgical update: ${job.jobNumber}');

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
              // 1. Try to find if this invoice serves a cached job and update it surgically
              // This is critical because invoice updates change job totals via DB triggers
              try {
                final newRecord = payload.newRecord;
                if (_cachedJobs != null) {
                  final invoiceId = newRecord['id']?.toString();
                  if (invoiceId != null) {
                    final jobIndex = _cachedJobs!
                        .indexWhere((j) => j.invoiceId == invoiceId);
                    if (jobIndex != -1) {
                      final jobId = _cachedJobs![jobIndex].id;
                      if (jobId != null) {
                        debugPrint(
                            '🔗 [BikeshopService] Invoice update linked to job $jobId - refreshing job...');
                        // Fetch fresh job data immediately to reflect DB trigger updates
                        _fetchAndUpdateJob(jobId);
                      }
                    }
                  }
                }
              } catch (e) {
                debugPrint(
                    '⚠️ [BikeshopService] Error linking invoice to job: $e');
              }

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

  // ============================================================
  // JOB SUBJECTS CRUD (per-tenant component catalog)
  // ============================================================

  List<JobSubject>? _cachedSubjects;

  List<JobSubject> get cachedSubjects => _cachedSubjects ?? [];

  void invalidateSubjectsCache() {
    _cachedSubjects = null;
  }

  Future<List<JobSubject>> getJobSubjects({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSubjects != null) return _cachedSubjects!;
    try {
      final data = await Supabase.instance.client
          .from('job_subjects')
          .select()
          .eq('is_active', true)
          .order('category')
          .order('sort_order')
          .order('name') as List<dynamic>;
      _cachedSubjects = data
          .map((j) => JobSubject.fromJson(j as Map<String, dynamic>))
          .toList();
      return _cachedSubjects!;
    } catch (e) {
      if (kDebugMode) print('Error fetching job subjects: $e');
      rethrow;
    }
  }

  Future<List<JobSubject>> getAllJobSubjects() async {
    try {
      final data = await Supabase.instance.client
          .from('job_subjects')
          .select()
          .order('category')
          .order('sort_order')
          .order('name') as List<dynamic>;
      return data
          .map((j) => JobSubject.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching all job subjects: $e');
      rethrow;
    }
  }

  Future<JobSubject> createJobSubject(JobSubject subject) async {
    try {
      final payload = subject.toJson();
      if ((payload['tenant_id'] as String?)?.isEmpty ?? false) {
        payload.remove('tenant_id');
      }
      final data = await _db.insert('job_subjects', payload);
      invalidateSubjectsCache();
      return JobSubject.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating job subject: $e');
      rethrow;
    }
  }

  Future<JobSubject> updateJobSubject(JobSubject subject) async {
    try {
      final payload = subject.toJson(forUpdate: true);
      if ((payload['tenant_id'] as String?)?.isEmpty ?? false) {
        payload.remove('tenant_id');
      }
      final data = await _db.update('job_subjects', subject.id!, payload);
      invalidateSubjectsCache();
      return JobSubject.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating job subject: $e');
      rethrow;
    }
  }

  Future<void> deleteJobSubject(String subjectId) async {
    try {
      await _db.delete('job_subjects', subjectId);
      invalidateSubjectsCache();
    } catch (e) {
      if (kDebugMode) print('Error deleting job subject: $e');
      rethrow;
    }
  }

  // ============================================================
  // JOB TYPE CONVERSION METHODS
  // ============================================================

  /// Convert a warranty or quotation job into a regular service job (in-place).
  /// Updates the existing job record — preserves the job number and history.
  Future<MechanicJob> convertToServiceJob(String jobId) async {
    try {
      await Supabase.instance.client.from('mechanic_jobs').update({
        'job_type': 'service',
        // 'warranty_outcome': null, // PRESERVE to leave a footprint that this came from a warranty
        'quotation_status': null,
        'quotation_valid_until': null,
        'is_warranty_job': false,
        'converted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', jobId);
      invalidateJobsCache();
      _debouncedNotify();
      final updated = await getJobById(jobId);
      if (updated == null) {
        throw Exception('Job not found after conversion: $jobId');
      }
      return updated;
    } catch (e) {
      if (kDebugMode) print('Error converting job to service: $e');
      rethrow;
    }
  }

  /// Update the warranty outcome of a job
  Future<void> updateWarrantyOutcome(
      String jobId, WarrantyOutcome outcome) async {
    try {
      await Supabase.instance.client
          .from('mechanic_jobs')
          .update({'warranty_outcome': outcome.dbValue}).eq('id', jobId);
      invalidateJobsCache();
      _debouncedNotify();
    } catch (e) {
      if (kDebugMode) print('Error updating warranty outcome: $e');
      rethrow;
    }
  }

  /// Update the quotation status of a job
  Future<void> updateQuotationStatus(
      String jobId, QuotationStatus status) async {
    try {
      await Supabase.instance.client
          .from('mechanic_jobs')
          .update({'quotation_status': status.dbValue}).eq('id', jobId);
      invalidateJobsCache();
      _debouncedNotify();
    } catch (e) {
      if (kDebugMode) print('Error updating quotation status: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _notifyDebounceTimer?.cancel();
    _invoiceNotifyDebounceTimer?.cancel();
    _mechanicJobsChannel?.unsubscribe();
    _jobBikesChannel?.unsubscribe();
    _salesInvoicesChannel
        ?.unsubscribe(); // Clean up sales invoices subscription
    super.dispose();
  }
}
