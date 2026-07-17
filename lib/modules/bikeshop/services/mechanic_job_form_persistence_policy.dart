import '../models/bikeshop_models.dart';

/// Commercial path for a normal bicycle service at intake.
///
/// Both choices keep the same physical workshop record. [budgetFirst] uses the
/// non-posting quotation workflow until the customer approves it;
/// [invoiceNow] keeps the established immediate-invoice behavior.
enum ServiceCommercialPath {
  budgetFirst,
  invoiceNow;

  String get displayName => switch (this) {
        ServiceCommercialPath.budgetFirst => 'Presupuestar primero',
        ServiceCommercialPath.invoiceNow => 'Facturar ahora',
      };

  String get description => switch (this) {
        ServiceCommercialPath.budgetFirst =>
          'La bicicleta queda recibida, pero no se crea factura ni movimiento financiero hasta aprobar.',
        ServiceCommercialPath.invoiceNow =>
          'Crea la factura al guardar; ideal cuando el trabajo y su valor ya están acordados.',
      };
}

/// Restores the persisted commercial path without applying the new-job
/// default retroactively. Historical billable services therefore keep their
/// immediate-invoice behavior when reopened.
ServiceCommercialPath mechanicJobServiceCommercialPathForExisting(
  MechanicJob job,
) {
  return job.isServiceBudget
      ? ServiceCommercialPath.budgetFirst
      : ServiceCommercialPath.invoiceNow;
}

/// Resolves the value written to the legacy `job_type` column.
///
/// Production normalizes every quotation workflow to `job_type = quotation`.
/// Keeping that facade explicit is especially important while editing a
/// bicycle-backed service budget: sending `service` would look like a direct
/// quotation-to-service conversion and must be rejected by the database guard.
JobType mechanicJobPersistedJobType({
  required JobType jobType,
  required ServiceCommercialPath serviceCommercialPath,
}) {
  if (jobType == JobType.service &&
      serviceCommercialPath == ServiceCommercialPath.budgetFirst) {
    return JobType.quotation;
  }
  return jobType;
}

/// Resolves the canonical workflow axis for a newly-created form.
JobWorkflowKind mechanicJobCreationWorkflowKind({
  required JobType jobType,
  required ServiceCommercialPath serviceCommercialPath,
}) {
  if (jobType == JobType.service &&
      serviceCommercialPath == ServiceCommercialPath.budgetFirst) {
    return JobWorkflowKind.quotation;
  }
  return JobWorkflowKind.fromLegacyJobType(jobType);
}

/// Resolves the physical intake independently from the commercial path.
JobIntakeKind mechanicJobCreationIntakeKind({
  required JobType jobType,
  String? bikeId,
  String? subjectId,
  String? subjectNotes,
}) {
  return JobIntakeKind.fromLegacyJobType(
    jobType,
    bikeId: bikeId,
    subjectId: subjectId,
    subjectNotes: subjectNotes,
  );
}

/// A persisted job whose linked invoice has payment evidence is an accounting
/// record, not an editable commercial draft.
///
/// The same fail-closed rule applies when the client could not prove the
/// payment state: diagnosis and non-lifecycle operational fields may still be
/// saved, but status/status_id, products, prices, discounts, totals and invoice
/// projection must remain exactly as they were until the linked invoice can be
/// read reliably.
bool shouldProtectJobCommercialSnapshot({
  required MechanicJob? existingJob,
  required bool linkedInvoiceHasActivePayments,
  required bool linkedInvoicePaymentStateUnknown,
}) {
  final linkedInvoiceId = existingJob?.invoiceId?.trim();
  final hasPersistedLinkedInvoice = existingJob?.id != null &&
      linkedInvoiceId != null &&
      linkedInvoiceId.isNotEmpty;
  return hasPersistedLinkedInvoice &&
      (linkedInvoiceHasActivePayments || linkedInvoicePaymentStateUnknown);
}

/// Builds the narrow job-header update allowed while a linked invoice is
/// payment-protected.
///
/// Removing lifecycle/commercial keys is stronger than writing their existing
/// values: PostgreSQL `UPDATE OF` triggers still fire when an unchanged column
/// is present in the statement. The remaining payload intentionally permits
/// diagnosis, operational notes, priority/deadlines and attachments.
Map<String, dynamic> mechanicJobPaymentProtectedUpdatePayload(
  Map<String, dynamic> payload,
) {
  const protectedKeys = <String>{
    'customer_id',
    'bike_id',
    'service_package_id',
    'job_type',
    'workflow_kind',
    'intake_kind',
    'mode_needs_review',
    'mode_review_reason',
    'subject_id',
    'subject_notes',
    'warranty_outcome',
    'quotation_status',
    'quotation_valid_until',
    'converted_from_id',
    'converted_at',
    'status',
    'status_id',
    'diagnostic_sent_at',
    'started_at',
    'completed_at',
    'delivered_at',
    'estimated_cost',
    'final_cost',
    'discount_amount',
    'invoice_id',
    'is_invoiced',
    'is_paid',
    'is_warranty_job',
    'requires_approval',
    'approved_by_customer',
    'approved_at',
  };
  return Map<String, dynamic>.of(payload)
    ..removeWhere((key, _) => protectedKeys.contains(key));
}

/// Whether a creation-mode change replaces the currently selected bicycle
/// context and therefore requires an explicit user confirmation.
///
/// Warranty intake is sourced from the original delivered work, while a quote
/// and a component-only service do not retain bicycle tabs. Switching to any
/// of those modes must never discard ficha/diagnosis state silently.
bool mechanicJobModeSwitchRemovesBikeContext({
  required JobType from,
  required JobType to,
  required bool hasPhysicalBikeTabs,
}) {
  if (!hasPhysicalBikeTabs || from == to) return false;
  return to == JobType.quotation ||
      to == JobType.itemService ||
      to == JobType.warranty ||
      to == JobType.sale;
}

/// Merges commercial lines while preserving their original instances and
/// stable IDs. The first occurrence wins so moving a draft between standalone
/// and General storage cannot duplicate invoice-linked rows or wizard state.
List<T> preserveMechanicJobModeLines<T>({
  required Iterable<Iterable<T>> collections,
  required String Function(T item) stableIdOf,
}) {
  final result = <T>[];
  final seenIds = <String>{};
  for (final collection in collections) {
    for (final item in collection) {
      final stableId = stableIdOf(item).trim();
      if (stableId.isEmpty || seenIds.add(stableId)) {
        result.add(item);
      }
    }
  }
  return result;
}

/// Preserves a real bike-specific narrative and only falls back to the
/// job-level quotation narrative when conversion created an empty first
/// mechanic_job_bikes row.
String mechanicJobConvertedBikeNarrativeValue({
  required String bikeValue,
  String? jobValue,
}) {
  return mechanicJobFirstBikeNarrativeValue(
    bikeValue: bikeValue,
    standaloneValue: jobValue,
  );
}

/// Hydrates the first physical bicycle from a standalone quote/component
/// draft without replacing anything already entered for that bicycle.
String mechanicJobFirstBikeNarrativeValue({
  required String bikeValue,
  String? standaloneValue,
}) {
  return bikeValue.trim().isNotEmpty ? bikeValue : (standaloneValue ?? '');
}

/// Changing a warranty source replaces its physical diagnostic context. Only
/// a real source change with entered source-scoped draft data requires consent.
bool mechanicJobWarrantySourceChangeNeedsConfirmation({
  required String? currentSourceJobId,
  required String? nextSourceJobId,
  required bool hasSourceScopedDraft,
}) {
  final current = currentSourceJobId?.trim();
  final next = nextSourceJobId?.trim();
  return hasSourceScopedDraft &&
      current != null &&
      current.isNotEmpty &&
      current != next;
}

/// Returns the persisted rows that belong in the job-level products/services
/// workbench when the form has no physical bicycle tabs.
///
/// Keeping the original model instances is intentional: their stable ids,
/// catalog references, targeting and wizard answers are needed to update the
/// same rows instead of deleting/recreating them on an edit save.
List<MechanicJobItem> mechanicJobStandaloneItemsForForm({
  required Iterable<MechanicJobItem> persistedItems,
  required bool hasPhysicalBikeTabs,
}) {
  if (hasPhysicalBikeTabs) return const <MechanicJobItem>[];
  return List<MechanicJobItem>.unmodifiable(persistedItems);
}

/// In-memory receipt of warranty commands that have already been confirmed
/// during the current form session.
///
/// A later, unrelated save stage may fail after PostgreSQL accepted the
/// command. This checkpoint prevents the next Save from issuing the same
/// registration/decision with a fresh operation key while the form's initial
/// projections are still stale.
class MechanicJobWarrantySaveCheckpoint {
  String? _registeredSourceJobId;
  WarrantyOutcome? _confirmedOutcome;
  bool _hasExplicitPersistedClaim = false;

  String? get registeredSourceJobId => _registeredSourceJobId;
  WarrantyOutcome? get confirmedOutcome => _confirmedOutcome;
  bool get hasExplicitPersistedClaim => _hasExplicitPersistedClaim;

  void hydrate({
    required MechanicJobWarrantyClaim? claim,
    WarrantyOutcome? persistedOutcome,
  }) {
    _hasExplicitPersistedClaim = claim != null;
    _registeredSourceJobId = _normalized(claim?.sourceJobId);
    _confirmedOutcome = persistedOutcome ?? claim?.outcome;
  }

  void reset() {
    _registeredSourceJobId = null;
    _confirmedOutcome = null;
    _hasExplicitPersistedClaim = false;
  }

  bool get requiresSourceSelection =>
      !_hasExplicitPersistedClaim && _registeredSourceJobId == null;

  bool needsRegistration(String? sourceJobId) {
    final source = _normalized(sourceJobId);
    return source != null && _registeredSourceJobId == null;
  }

  void confirmRegistration(String sourceJobId) {
    _registeredSourceJobId = _required(sourceJobId, 'sourceJobId');
    _hasExplicitPersistedClaim = true;
    // The registration RPC canonically resets the claim to pending. A legacy
    // mechanic_jobs mirror may have said covered/not_covered without an
    // immutable registration event; it must not suppress the audited decision
    // that now needs to follow this newly confirmed registration.
    _confirmedOutcome = WarrantyOutcome.pending;
  }

  bool needsDecision(WarrantyOutcome desiredOutcome) {
    return desiredOutcome != (_confirmedOutcome ?? WarrantyOutcome.pending);
  }

  void confirmDecision(WarrantyOutcome outcome) {
    _confirmedOutcome = outcome;
  }

  static String _required(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty');
    }
    return normalized;
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
