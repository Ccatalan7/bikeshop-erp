import '../models/bikeshop_models.dart';

/// Combines one server-owned mechanic-job row with read-only projections that
/// are not part of the status-transition RPC snapshot.
///
/// Every persisted/base column comes from [authoritative]. Derived projections
/// may be retained only from the exact same job and tenant. The target status
/// is display metadata already loaded by the caller; its ID and tenant must
/// match the acknowledged server row before it can decorate that row.
MechanicJob reconcileMechanicJobCacheProjection({
  required MechanicJob authoritative,
  MechanicJob? cached,
  JobStatusCustom? targetStatus,
}) {
  final canPreserveProjection = cached != null &&
      cached.id == authoritative.id &&
      cached.tenantId == authoritative.tenantId;
  final matchingTargetStatus = targetStatus?.id == authoritative.statusId &&
          targetStatus?.tenantId == authoritative.tenantId
      ? targetStatus
      : null;
  final matchingCachedStatus =
      canPreserveProjection && cached.statusId == authoritative.statusId
          ? cached.customStatus
          : null;

  return authoritative.copyWith(
    subjectData: authoritative.subjectData ??
        (canPreserveProjection ? cached.subjectData : null),
    serviceWarranty: authoritative.serviceWarranty ??
        (canPreserveProjection ? cached.serviceWarranty : null),
    timeMetrics: authoritative.timeMetrics ??
        (canPreserveProjection ? cached.timeMetrics : null),
    customStatus: matchingTargetStatus ??
        authoritative.customStatus ??
        matchingCachedStatus,
  );
}

/// Reconciles one authoritative row into the cached Jobs collection.
///
/// The returned collection is always growable. A full load may legitimately
/// produce a fixed-length list, but realtime INSERT/DELETE must still be able
/// to evolve that snapshot without falling back to a universal reload.
List<MechanicJob> upsertMechanicJobCacheProjection({
  required List<MechanicJob> cachedJobs,
  required MechanicJob authoritative,
  JobStatusCustom? targetStatus,
}) {
  final nextJobs = List<MechanicJob>.of(cachedJobs, growable: true);
  final index = nextJobs.indexWhere((job) => job.id == authoritative.id);
  final cached = index >= 0 ? nextJobs[index] : null;
  final reconciled = reconcileMechanicJobCacheProjection(
    authoritative: authoritative,
    cached: cached,
    targetStatus: targetStatus,
  );

  if (index >= 0) {
    nextJobs[index] = reconciled;
  } else {
    nextJobs.add(reconciled);
    nextJobs.sort((a, b) => b.arrivalDate.compareTo(a.arrivalDate));
  }
  return nextJobs;
}

/// Removes one row from the cached Jobs collection without assuming that the
/// incoming snapshot supports length-changing operations.
List<MechanicJob> removeMechanicJobCacheProjection({
  required List<MechanicJob> cachedJobs,
  required String jobId,
}) {
  return cachedJobs.where((job) => job.id != jobId).toList(growable: true);
}
