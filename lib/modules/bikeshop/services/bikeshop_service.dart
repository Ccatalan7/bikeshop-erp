import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/bikeshop_models.dart';

class BikeshopService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService = TenantService();
  
  RealtimeChannel? _mechanicJobsChannel;

  BikeshopService(this._db) {
    // Don't await - fire and forget to avoid blocking constructor
    _setupMechanicJobsRealtime();
  }

  // ============================================================
  // BIKE OPERATIONS
  // ============================================================

  Future<List<Bike>> getBikes({String? customerId, String? searchTerm}) async {
    try {
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
        data = await _db.select('bikes', where: 'customer_id=$customerId', fetchAll: true);
      } else {
        data = await _db.select('bikes', fetchAll: true);
      }

      return data.map((json) => Bike.fromJson(json)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      if (kDebugMode) print('Error fetching bikes: $e');
      rethrow;
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
      return data.map((json) => BikeModel.fromJson(json as Map<String, dynamic>)).toList()
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
  // MECHANIC JOB OPERATIONS
  // ============================================================

  Future<List<MechanicJob>> getJobs({
    String? customerId,
    String? bikeId,
    JobStatus? status,
    String? searchTerm,
    bool includeCompleted = true,
  }) async {
    try {
      List<Map<String, dynamic>> data;

      String? whereClause;
      if (customerId != null && customerId.isNotEmpty) {
        whereClause = 'customer_id=$customerId';
      } else if (bikeId != null && bikeId.isNotEmpty) {
        whereClause = 'bike_id=$bikeId';
      } else if (status != null) {
        whereClause = "status=${status.dbValue}";
      }

      if (!includeCompleted) {
        final excludedStatuses = "'FINALIZADO','ENTREGADO','CANCELADO'";
        if (whereClause != null) {
          whereClause += ' AND status NOT IN ($excludedStatuses)';
        } else {
          whereClause = 'status NOT IN ($excludedStatuses)';
        }
      }

      data = await _db.select('mechanic_jobs', where: whereClause, fetchAll: true);

      if (searchTerm != null && searchTerm.isNotEmpty) {
        final searchLower = searchTerm.toLowerCase();
        data = data.where((job) {
          final jobNumber = job['job_number']?.toString().toLowerCase() ?? '';
          final diagnosis = job['diagnosis']?.toString().toLowerCase() ?? '';
          final clientRequest =
              job['client_request']?.toString().toLowerCase() ?? '';
          return jobNumber.contains(searchLower) ||
              diagnosis.contains(searchLower) ||
              clientRequest.contains(searchLower);
        }).toList();
      }

      return data.map((json) => MechanicJob.fromJson(json)).toList()
        ..sort((a, b) => b.arrivalDate.compareTo(a.arrivalDate));
    } catch (e) {
      if (kDebugMode) print('Error fetching jobs: $e');
      rethrow;
    }
  }

  Future<MechanicJob?> getJobById(String id) async {
    try {
      if (id.isEmpty) return null;
      final data = await _db.selectById('mechanic_jobs', id);
      return data != null ? MechanicJob.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching job: $e');
      rethrow;
    }
  }

  Future<MechanicJob> createJob(MechanicJob job) async {
    try {
      // Job number will be auto-generated by the database trigger
      final data = await _db.insert('mechanic_jobs', job.toJson());
      notifyListeners();
      return MechanicJob.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating job: $e');
      rethrow;
    }
  }

  Future<MechanicJob> updateJob(MechanicJob job) async {
    try {
      if (job.id == null || job.id!.isEmpty) {
        throw Exception('ID de trabajo inválido');
      }
      final data = await _db.update('mechanic_jobs', job.id!, job.toJson());
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
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting job: $e');
      rethrow;
    }
  }

  Future<MechanicJob> updateJobStatus(String jobId, JobStatus newStatus) async {
    try {
      final job = await getJobById(jobId);
      if (job == null) throw Exception('Trabajo no encontrado');

      final updatedJob = job.copyWith(status: newStatus);
      return await updateJob(updatedJob);
    } catch (e) {
      if (kDebugMode) print('Error updating job status: $e');
      rethrow;
    }
  }

  // ============================================================
  // MECHANIC JOB ITEMS OPERATIONS
  // ============================================================

  Future<List<MechanicJobItem>> getJobItems(String jobId) async {
    try {
      final data =
          await _db.select('mechanic_job_items', where: 'job_id=$jobId');
      return data.map((json) => MechanicJobItem.fromJson(json)).toList();
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
  // MECHANIC JOB LABOR OPERATIONS
  // ============================================================

  Future<List<MechanicJobLabor>> getJobLabor(String jobId) async {
    try {
      final data =
          await _db.select('mechanic_job_labor', where: 'job_id=$jobId');
      return data.map((json) => MechanicJobLabor.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching job labor: $e');
      rethrow;
    }
  }

  Future<MechanicJobLabor> createJobLabor(MechanicJobLabor labor) async {
    try {
      final data = await _db.insert('mechanic_job_labor', labor.toJson());
      notifyListeners();
      return MechanicJobLabor.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating job labor: $e');
      rethrow;
    }
  }

  Future<MechanicJobLabor> updateJobLabor(MechanicJobLabor labor) async {
    try {
      if (labor.id == null || labor.id!.isEmpty) {
        throw Exception('ID de mano de obra inválido');
      }
      final data =
          await _db.update('mechanic_job_labor', labor.id!, labor.toJson());
      notifyListeners();
      return MechanicJobLabor.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating job labor: $e');
      rethrow;
    }
  }

  Future<void> deleteJobLabor(String id) async {
    try {
      if (id.isEmpty) throw Exception('ID de mano de obra inválido');
      await _db.delete('mechanic_job_labor', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting job labor: $e');
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
        print('📋 Timeline query result for job $jobId: ${response.length} events');
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

  /// Get complete job details with items, labor, and timeline
  Future<Map<String, dynamic>> getJobDetails(String jobId) async {
    try {
      final job = await getJobById(jobId);
      if (job == null) throw Exception('Trabajo no encontrado');

      final items = await getJobItems(jobId);
      final labor = await getJobLabor(jobId);
      final timeline = await getJobTimeline(jobId);

      return {
        'job': job,
        'items': items,
        'labor': labor,
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

  /// Apply a service package to a job (creates items and labor entries)
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

      // Create labor entry
      if (package.baseLaborCost > 0) {
        final labor = MechanicJobLabor(
          jobId: jobId,
          tenantId: tenantId,
          technicianName: 'Sin asignar',
          description: package.name,
          hoursWorked: package.estimatedDurationHours,
          hourlyRate: package.baseLaborCost / package.estimatedDurationHours,
          totalCost: package.baseLaborCost,
        );
        await createJobLabor(labor);
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

      notifyListeners();
      if (kDebugMode) print('✅ Job synced to invoice: $jobId');
    } catch (e) {
      if (kDebugMode) print('❌ Error syncing job to invoice: $e');
      rethrow;
    }
  }

  // Realtime subscription for mechanic jobs
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
            callback: (payload) {
              debugPrint('🔔 [BikeshopService] Mechanic job changed: ${payload.eventType}');
              notifyListeners(); // Notify listeners to reload data
            },
          )
          .subscribe();

      debugPrint('✅ [BikeshopService] Realtime subscription active');
    } catch (e) {
      debugPrint('❌ [BikeshopService] Failed to setup realtime: $e');
    }
  }

  @override
  void dispose() {
    _mechanicJobsChannel?.unsubscribe();
    super.dispose();
  }
}
