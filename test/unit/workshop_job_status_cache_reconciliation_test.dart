import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_cache_reconciler.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';

void main() {
  group('authoritative status cache reconciliation', () {
    final recordedAt = DateTime.utc(2026, 8, 24, 12);
    final subject = JobSubject(
      id: 'subject-1',
      tenantId: 'tenant-1',
      name: 'Rueda trasera',
      createdAt: recordedAt,
      updatedAt: recordedAt,
    );
    const warranty = MechanicJobServiceWarranty(
      jobId: 'job-1',
      customerId: 'customer-1',
      jobType: JobType.service,
      state: ServiceWarrantyState.active,
      daysRemaining: 8,
    );
    const metrics = MechanicJobTimeMetrics(
      jobId: 'job-1',
      currentIsCompleted: false,
      currentIsDelivered: false,
      reopenedAfterDelivery: false,
    );
    final targetStatus = JobStatusCustom(
      id: 'status-active',
      tenantId: 'tenant-1',
      name: 'En curso',
      code: 'EN_CURSO',
      color: '#22C55E',
      triggersStart: true,
    );

    test('keeps derived projections while accepting the RPC-owned row', () {
      final cached = MechanicJob(
        id: 'job-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        statusId: 'status-pending',
        status: JobStatus.pendiente,
        subjectData: subject,
        serviceWarranty: warranty,
        timeMetrics: metrics,
        finalCost: 100,
      );
      final authoritative = MechanicJob(
        id: 'job-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        statusId: 'status-active',
        status: JobStatus.enCurso,
        startedAt: recordedAt,
        finalCost: 125,
        updatedAt: recordedAt,
      );

      final merged = reconcileMechanicJobCacheProjection(
        authoritative: authoritative,
        cached: cached,
        targetStatus: targetStatus,
      );

      expect(merged.status, JobStatus.enCurso);
      expect(merged.statusId, 'status-active');
      expect(merged.startedAt, recordedAt);
      expect(merged.finalCost, 125, reason: 'base columns belong to the RPC');
      expect(merged.customStatus, same(targetStatus));
      expect(merged.subjectData, same(subject));
      expect(merged.serviceWarranty, same(warranty));
      expect(merged.timeMetrics, same(metrics));
    });

    test('never borrows projections from a different tenant or job', () {
      final cached = MechanicJob(
        id: 'other-job',
        tenantId: 'other-tenant',
        customerId: 'customer-1',
        subjectData: subject,
        serviceWarranty: warranty,
        timeMetrics: metrics,
      );
      final authoritative = MechanicJob(
        id: 'job-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        statusId: 'status-active',
        status: JobStatus.enCurso,
      );

      final merged = reconcileMechanicJobCacheProjection(
        authoritative: authoritative,
        cached: cached,
        targetStatus: targetStatus,
      );

      expect(merged.subjectData, isNull);
      expect(merged.serviceWarranty, isNull);
      expect(merged.timeMetrics, isNull);
      expect(merged.customStatus, same(targetStatus));
    });
  });

  group('surgical Jobs collection reconciliation', () {
    final older = DateTime.utc(2026, 8, 24, 10);
    final newer = DateTime.utc(2026, 8, 24, 11);

    MechanicJob job({
      required String id,
      required String number,
      required DateTime arrivalDate,
      JobStatus status = JobStatus.pendiente,
      String? diagnosis,
    }) {
      return MechanicJob(
        id: id,
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        jobNumber: number,
        arrivalDate: arrivalDate,
        status: status,
        diagnosis: diagnosis,
      );
    }

    test('inserts a realtime row into a fixed-length full-load snapshot', () {
      final existing = job(
        id: 'job-1',
        number: 'PG-00001',
        arrivalDate: older,
      );
      final inserted = job(
        id: 'job-2',
        number: 'PG-00002',
        arrivalDate: newer,
      );
      final fixedSnapshot = List<MechanicJob>.of(
        [existing],
        growable: false,
      );

      final reconciled = upsertMechanicJobCacheProjection(
        cachedJobs: fixedSnapshot,
        authoritative: inserted,
      );

      expect(reconciled.map((job) => job.id), ['job-2', 'job-1']);
      expect(fixedSnapshot.map((job) => job.id), ['job-1']);
      expect(
        () => reconciled.add(job(
          id: 'job-3',
          number: 'PG-00003',
          arrivalDate: newer,
        )),
        returnsNormally,
        reason: 'the next realtime insert must remain legal',
      );
    });

    test('updates only the matching realtime row', () {
      final untouched = job(
        id: 'job-1',
        number: 'PG-00001',
        arrivalDate: older,
      );
      final previous = job(
        id: 'job-2',
        number: 'PG-00002',
        arrivalDate: newer,
        diagnosis: 'Anterior',
      );
      final updated = job(
        id: 'job-2',
        number: 'PG-00002',
        arrivalDate: newer,
        status: JobStatus.enCurso,
        diagnosis: 'Actualizado',
      );

      final reconciled = upsertMechanicJobCacheProjection(
        cachedJobs: List<MechanicJob>.of(
          [previous, untouched],
          growable: false,
        ),
        authoritative: updated,
      );

      expect(reconciled, hasLength(2));
      expect(reconciled.firstWhere((job) => job.id == 'job-2').status,
          JobStatus.enCurso);
      expect(reconciled.firstWhere((job) => job.id == 'job-2').diagnosis,
          'Actualizado');
      expect(
          reconciled.firstWhere((job) => job.id == 'job-1'), same(untouched));
    });

    test('deletes a realtime row from a fixed-length snapshot', () {
      final first = job(
        id: 'job-1',
        number: 'PG-00001',
        arrivalDate: older,
      );
      final second = job(
        id: 'job-2',
        number: 'PG-00002',
        arrivalDate: newer,
      );

      final reconciled = removeMechanicJobCacheProjection(
        cachedJobs: List<MechanicJob>.of(
          [second, first],
          growable: false,
        ),
        jobId: 'job-2',
      );

      expect(reconciled.map((job) => job.id), ['job-1']);
      expect(
        () => reconciled.add(second),
        returnsNormally,
        reason: 'a later realtime insert must remain legal after a delete',
      );
    });
  });

  test('the single-row table transition has no full reload on success', () {
    final source = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final method = source.substring(
      source.indexOf('Future<bool> _updateJobToCustomStatus('),
      source.indexOf('/// Show status menu for a specific bike'),
    );
    final success = method.substring(0, method.indexOf('} catch (e) {'));
    final failure = method.substring(method.indexOf('} catch (e) {'));

    expect(success, contains('_applyAuthoritativeJobUpdate(updatedJob);'));
    expect(success, isNot(contains('_loadData(')));
    expect(
      failure,
      contains('await _loadData('),
      reason: 'an unknown/failing outcome still reconciles from the server',
    );
  });

  test('the service publishes the receipt row and invalidates only on failure',
      () {
    final source = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();
    final method = source.substring(
      source.indexOf('Future<MechanicJob> transitionJobStatus('),
      source.indexOf('/// Compatibility adapter for the remaining detail'),
    );
    final success = method.substring(0, method.indexOf('} catch (_) {'));
    final failure = method.substring(method.indexOf('} catch (_) {'));

    expect(success, isNot(contains('getJobById(')));
    expect(success, contains('result.authoritativeJobSnapshot'));
    expect(success, contains('reconcileMechanicJobCacheProjection('));
    expect(success, contains('_surgicalUpdateJob(updatedJob);'));
    expect(success, isNot(contains('finally')));
    expect(
      failure,
      contains('invalidateJobsCache();'),
      reason: 'unknown outcomes must discard the previous projection',
    );
  });

  test('supply-attention chunks are issued concurrently', () async {
    var calls = 0;
    var active = 0;
    var maxActive = 0;
    final release = Completer<void>();
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        calls++;
        active++;
        if (active > maxActive) maxActive = active;
        await release.future;
        active--;
        return http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final service = IntelligentPurchasingService(client: client);
    final fetch = service.fetchJobSupplyAttention(
      List<String>.generate(250, (index) => 'job-$index'),
    );

    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 3);
      expect(maxActive, 3);
    } finally {
      release.complete();
      await fetch;
      client.dispose();
    }
  });
}
