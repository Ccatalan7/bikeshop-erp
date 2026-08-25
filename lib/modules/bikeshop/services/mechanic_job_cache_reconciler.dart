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
