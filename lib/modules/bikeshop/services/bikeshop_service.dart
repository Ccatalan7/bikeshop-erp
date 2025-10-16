import 'package:flutter/foundation.dart';
import '../../../shared/services/database_service.dart';
import '../models/bikeshop_models.dart';

class BikeshopService extends ChangeNotifier {
  final DatabaseService _db;

  BikeshopService(this._db);

  // ============================================================
  // BIKE OPERATIONS
  // ============================================================

  Future<List<Bike>> getBikes({String? customerId, String? searchTerm}) async {
    try {
      List<Map<String, dynamic>> data;

      if (searchTerm != null && searchTerm.isNotEmpty) {
        // Search by brand, model, serial number
        final brandResults = await _db.searchRecords('bikes', 'brand', searchTerm);
        final modelResults = await _db.searchRecords('bikes', 'model', searchTerm);
        final serialResults = await _db.searchRecords('bikes', 'serial_number', searchTerm);

        // Combine and deduplicate results
        final Set<String> ids = {};
        data = [...brandResults, ...modelResults, ...serialResults]
            .where((item) {
              final id = item['id']?.toString();
              if (id == null) return true;
              return ids.add(id);
            })
            .toList();
      } else if (customerId != null && customerId.isNotEmpty) {
        data = await _db.select('bikes', where: 'customer_id=$customerId');
      } else {
        data = await _db.select('bikes');
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

      data = await _db.select('mechanic_jobs', where: whereClause);

      if (searchTerm != null && searchTerm.isNotEmpty) {
        final searchLower = searchTerm.toLowerCase();
        data = data.where((job) {
          final jobNumber = job['job_number']?.toString().toLowerCase() ?? '';
          final diagnosis = job['diagnosis']?.toString().toLowerCase() ?? '';
          final clientRequest = job['client_request']?.toString().toLowerCase() ?? '';
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
      final data = await _db.select('mechanic_job_items', where: 'job_id=$jobId');
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
      final data = await _db.update('mechanic_job_items', item.id!, item.toJson());
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
      final data = await _db.select('mechanic_job_labor', where: 'job_id=$jobId');
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
      final data = await _db.update('mechanic_job_labor', labor.id!, labor.toJson());
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
      final data = await _db.select(
        'mechanic_job_timeline',
        where: 'job_id=$jobId',
        orderBy: 'created_at',
        descending: true,
      );
      return data.map((json) => MechanicJobTimeline.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching job timeline: $e');
      rethrow;
    }
  }

  // Timeline events are created automatically by database triggers,
  // but we can also create manual events if needed
  Future<MechanicJobTimeline> createTimelineEvent(MechanicJobTimeline event) async {
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
      final data = await _db.update('service_packages', package.id!, package.toJson());
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
  Future<Map<String, dynamic>> getCustomerBikeshopData(String customerId) async {
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

      // Create items from package
      for (final item in package.items) {
        final productId = item['product_id']?.toString();
        final quantity = double.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
        
        if (productId != null) {
          // Fetch product details
          final productData = await _db.selectById('products', productId);
          if (productData != null) {
            final unitPrice = double.tryParse(productData['price']?.toString() ?? '0') ?? 0;
            final jobItem = MechanicJobItem(
              jobId: jobId,
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
        'pendiente': allJobs.where((j) => j.status == JobStatus.pendiente).length,
        'en_curso': allJobs.where((j) => j.status == JobStatus.enCurso).length,
        'esperando_repuestos': allJobs.where((j) => j.status == JobStatus.esperandoRepuestos).length,
        'finalizado': allJobs.where((j) => j.status == JobStatus.finalizado).length,
        'entregado': allJobs.where((j) => j.status == JobStatus.entregado).length,
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
      
      if (kDebugMode) print('⚠️ Invoice creation returned null for job: $jobId');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error creating invoice from job: $e');
      // Don't rethrow - invoice creation failure shouldn't prevent job from being saved
      return null;
    }
  }
}
