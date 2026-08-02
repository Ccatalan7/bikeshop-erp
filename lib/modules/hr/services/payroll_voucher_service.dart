import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import '../models/payroll_audit_read_models.dart';
import '../models/payroll_voucher.dart';
import '../../../../shared/services/database_service.dart';
import '../../accounting/services/financial_projection_refresh_coordinator.dart';

bool _payrollTimeZonesInitialized = false;

/// Falla conocida antes de que un comando financiero alcance su RPC.
///
/// La distinción es de integridad, no de presentación: cuando aparece esta
/// excepción el servicio garantiza que **no envió la escritura**, por lo que
/// el host no debe levantar la valla de resultado ambiguo ni insinuar que el
/// movimiento pudo haberse registrado.
enum PayrollVoucherPreflightFailureKind {
  rejected,
  unavailable,
}

class PayrollVoucherPreflightException implements Exception {
  const PayrollVoucherPreflightException.rejected(this.userMessage)
      : kind = PayrollVoucherPreflightFailureKind.rejected;

  const PayrollVoucherPreflightException.unavailable(this.userMessage)
      : kind = PayrollVoucherPreflightFailureKind.unavailable;

  final PayrollVoucherPreflightFailureKind kind;

  /// Texto deliberadamente seguro para interfaz; nunca contiene payloads ni
  /// mensajes crudos del backend.
  final String userMessage;

  bool get mayHaveCommitted => false;

  @override
  String toString() => 'PayrollVoucherPreflightException(${kind.name})';
}

@immutable
class PayrollAdvanceEvidenceReference {
  const PayrollAdvanceEvidenceReference({
    required this.appFileId,
    required this.sha256,
  });

  final String appFileId;
  final String sha256;
}

@immutable
class PayrollAdvanceRegistrationReceipt {
  const PayrollAdvanceRegistrationReceipt({
    required this.advanceId,
    required this.replayed,
    this.evidenceStorageObjectId,
    this.evidenceStorageObjectVersion,
    this.evidenceStorageObjectEtag,
  });

  final String advanceId;
  final bool replayed;
  final String? evidenceStorageObjectId;
  final String? evidenceStorageObjectVersion;
  final String? evidenceStorageObjectEtag;
}

class PayrollVoucherService extends ChangeNotifier {
  final DatabaseService _db;
  final FinancialProjectionRefreshCoordinator _financialProjectionRefresh;

  PayrollVoucherService(
    this._db, {
    FinancialProjectionRefreshCoordinator? financialProjectionRefresh,
  }) : _financialProjectionRefresh = financialProjectionRefresh ??
            FinancialProjectionRefreshCoordinator.fallback;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<PayrollVoucher>? _cachedVouchers;
  DateTime? _vouchersCacheTime;
  Future<List<PayrollVoucher>>? _vouchersLoadFuture;
  bool? _supportsVersionedPayrollCommands;
  static const Duration _cacheMaxAge = Duration(minutes: 5);

  List<PayrollVoucher> get cachedVouchers =>
      List.unmodifiable(_cachedVouchers ?? const <PayrollVoucher>[]);
  bool get hasVouchersCache =>
      _cachedVouchers != null && _vouchersCacheTime != null;

  /// Whether the backend has the atomic, versioned payroll command bundle.
  ///
  /// The reconciliation column and the v2 command RPCs are installed by the
  /// same migration. A successful header read including that column is
  /// therefore the non-mutating capability probe. The legacy header fallback
  /// is deliberately read-only and must never be interpreted as write
  /// compatibility.
  bool get supportsVersionedPayrollCommands =>
      _supportsVersionedPayrollCommands == true;

  /// Tri-state capability probe: `null` while no read has resolved it yet,
  /// then the last observed answer. Callers that must distinguish "unknown"
  /// from "confirmed absent" (e.g. the reconciliation preview) use this
  /// instead of [supportsVersionedPayrollCommands].
  bool? get versionedPayrollCommandsProbe => _supportsVersionedPayrollCommands;

  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  void invalidateVouchersCache() {
    _cachedVouchers = null;
    _vouchersCacheTime = null;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    _notifySafe();
  }

  void _setError(String? value) {
    _error = value;
    _notifySafe();
  }

  /// Safely notify listeners, even during build phase
  void _notifySafe() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// Generates a PREVIEW of the payroll voucher for the given period.
  /// This does NOT save to the database - it's for user review only.
  /// Returns a PayrollVoucher object with calculated lines.
  Future<PayrollVoucher> generatePreview(
    DateTime startDate,
    DateTime endDate, {
    String? periodLabel,
  }) async {
    try {
      _setLoading(true);
      _setError(null);

      // Fetch active employees with their salary info
      final employees = await _db.select(
        'employees',
        where: 'status=active',
        orderBy: 'first_name',
      );

      // Fetch attendance records for the period
      final attendances = await _db.rpc(
            'get_payroll_attendance_summary_for_period_v2',
            params: {
              'p_start_date': startDate.toIso8601String().split('T')[0],
              'p_end_date': endDate.toIso8601String().split('T')[0],
            },
          ) as List<dynamic>? ??
          [];

      // Attendance owns both regular and overtime hours. Keep both values in
      // the preview so the read-only review matches the server-owned draft
      // command instead of silently omitting the overtime premium.
      final hoursMap = <String,
          ({
        double workedHours,
        double overtimeHours,
      })>{};
      for (var att in attendances) {
        final empId = att['employee_id'] as String;
        final workedHours = (att['total_hours'] as num?)?.toDouble() ?? 0;
        final overtimeHours = (att['overtime_hours'] as num?)?.toDouble() ??
            (att['total_overtime'] as num?)?.toDouble() ??
            0;
        hoursMap[empId] = (
          workedHours: workedHours,
          overtimeHours: overtimeHours,
        );
      }

      // Generate preview lines
      final lines = <PayrollVoucherLine>[];
      double totalAmount = 0;
      double totalHours = 0;

      for (var emp in employees) {
        final empId = emp['id'] as String;
        final attendanceHours = hoursMap[empId];
        final workedHours = attendanceHours?.workedHours ?? 0;
        final overtimeHours = attendanceHours?.overtimeHours ?? 0;
        final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0;
        final overtimeRate = hourlyRate * 1.5;
        final regularAmount = workedHours * hourlyRate;
        final overtimeAmount = overtimeHours * overtimeRate;
        final lineTotal = regularAmount + overtimeAmount;

        lines.add(PayrollVoucherLine(
          id: empId, // Use employee ID as temp ID for preview
          voucherId: 'preview',
          employeeId: empId,
          employeeName:
              '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim(),
          workedHours: workedHours,
          overtimeHours: overtimeHours,
          hourlyRate: hourlyRate,
          overtimeRate: overtimeRate,
          regularAmount: regularAmount,
          overtimeAmount: overtimeAmount,
          totalAmount: lineTotal,
          isIncluded: true,
          paymentMethod: emp['preferred_payment_method'] ?? 'transfer',
          paymentMethodId: emp['preferred_payment_method_id'],
          salaryAccountId: emp['salary_account_id'],
        ));

        totalAmount += lineTotal;
        totalHours += workedHours + overtimeHours;
      }

      // Create preview voucher (not saved)
      final label = periodLabel ??
          '${startDate.day}/${startDate.month} - ${endDate.day}/${endDate.month}';

      return PayrollVoucher(
        id: 'preview', // Special ID to indicate not saved
        tenantId: '', // Will be set by DB on actual save
        voucherNumber: 'PREVIEW',
        periodStart: startDate,
        periodEnd: endDate,
        periodLabel: label,
        status: PayrollVoucherStatus.draft,
        totalAmount: totalAmount,
        totalHours: totalHours,
        employeeCount: lines.where((l) => l.isIncluded).length,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lines: lines,
      );
    } catch (e) {
      _setError('Error generating preview: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Prepares one weekly payroll draft from server-owned Attendance data.
  ///
  /// The client sends no worker, hour, rate, payment-method, or account
  /// snapshot. [operationKey] is supplied by the workflow owner and is passed
  /// through unchanged so an ambiguous retry can reuse the exact same command.
  Future<String> prepareDraftFromAttendance(
    DateTime startDate,
    DateTime endDate, {
    String? periodLabel,
    required String operationKey,
  }) async {
    try {
      _setLoading(true);
      _setError(null);

      final result = await _db.rpc(
        'prepare_payroll_voucher_draft_v2',
        params: <String, dynamic>{
          'p_start_date': _civilDate(startDate),
          'p_end_date': _civilDate(endDate),
          'p_period_label': periodLabel,
          'p_operation_key': operationKey,
        },
      );
      final receipt = _asJsonObject(
        result,
        command: 'preparar la nómina desde Asistencias',
      );
      final receiptOperationKey = receipt['operation_key']?.toString();
      if (receiptOperationKey != operationKey) {
        throw StateError(
          'El servidor respondió con una operación de nómina distinta.',
        );
      }
      if (receipt['status']?.toString() != 'draft') {
        throw StateError(
          'El servidor no confirmó el borrador de nómina.',
        );
      }
      final voucherId = receipt['voucher_id']?.toString();
      if (voucherId == null || voucherId.isEmpty) {
        throw StateError(
          'El servidor no devolvió la nómina preparada.',
        );
      }

      invalidateVouchersCache();
      return voucherId;
    } catch (error) {
      _setError(
        'No se pudo preparar la nómina desde Asistencias: $error',
      );
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Saves the preview voucher as a draft to the database.
  /// Call this AFTER user reviews and possibly modifies the preview.
  Future<String> saveDraft(
    PayrollVoucher preview, {
    String? operationKey,
  }) async {
    try {
      _setLoading(true);
      _setError(null);

      final receipt = await _saveDraftSnapshot(
        preview,
        operationKey: operationKey ?? _newOperationKey('draft_create'),
        isCreate: true,
      );
      final voucherId = receipt['voucher_id']?.toString();
      if (voucherId == null || voucherId.isEmpty) {
        throw StateError('El servidor no devolvió la nómina creada.');
      }

      invalidateVouchersCache();
      return voucherId;
    } catch (e) {
      _setError('Error saving draft: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Updates an existing voucher (for editing)
  Future<void> updateVoucher(
    PayrollVoucher voucher, {
    String? operationKey,
  }) async {
    if (voucher.id == null) {
      throw Exception('Cannot update voucher without ID');
    }

    try {
      _setLoading(true);
      _setError(null);

      await _saveDraftSnapshot(
        voucher,
        operationKey: operationKey ?? _newOperationKey('draft_update'),
        isCreate: false,
      );

      invalidateVouchersCache();
    } catch (e) {
      _setError('Error updating voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Generates a new voucher draft for the given period.
  /// Returns the ID of the created voucher.
  @Deprecated('Use prepareDraftFromAttendance with a workflow operation key.')
  Future<String> generateDraft(
    DateTime startDate,
    DateTime endDate, {
    String? periodLabel,
  }) async {
    return prepareDraftFromAttendance(
      startDate,
      endDate,
      periodLabel: periodLabel,
      operationKey: _newOperationKey('attendance_prepare'),
    );
  }

  /// Fetches one exact voucher by ID with all its lines.
  ///
  /// Absence is represented by `null`. Authorization, connectivity, parsing
  /// and settlement-evidence failures remain visible to the caller so a
  /// history detail error cannot masquerade as a deleted payroll record.
  Future<PayrollVoucher?> fetchVoucherDetail(String id) async {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Voucher ID is required');
    }
    try {
      _setLoading(true);
      _setError(null);

      final voucherData = await _db.selectById('payroll_vouchers', id);
      if (voucherData == null) return null;

      final linesData = await _db.select(
        'payroll_voucher_lines',
        // Mismo join que la carga por lotes: el historial entra por acá, y sin
        // esto el respaldo de un pago no puede nombrar la cuenta de gasto.
        selectColumns: '*,salary_account:accounts!salary_account_id(code,name)',
        where: 'voucher_id=$id',
        orderBy: 'employee_name',
      );

      var voucher = PayrollVoucher.fromMap({
        ...voucherData,
        'lines': linesData,
      });
      voucher = await _hydrateSettlementData(voucher);

      // The server owns aggregate totals. A stale historical header may be
      // rendered with computed values, but reads never repair data by writing.
      return _withComputedTotals(voucher);
    } catch (e) {
      _setError('Error loading voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Legacy nullable compatibility wrapper.
  ///
  /// New routed and paginated detail surfaces must use [fetchVoucherDetail] so
  /// a failed read remains distinguishable from an absent record.
  Future<PayrollVoucher?> getVoucher(String id) async {
    try {
      return await fetchVoucherDetail(id);
    } catch (_) {
      return null;
    }
  }

  /// Loads one bounded page of the audited advance ledger for an employee.
  ///
  /// Totals and allocations come from the server-owned projection. The cursor
  /// must be reused unchanged; it identifies the last `(paid_at, id)` row
  /// returned by the preceding page.
  Future<PayrollAdvanceLedgerPage> fetchEmployeeAdvanceLedgerPage({
    required String employeeId,
    int pageSize = 25,
    PayrollAdvanceLedgerCursor? cursor,
  }) async {
    _validatePayrollReadPageSize(pageSize);
    if (employeeId.trim().isEmpty) {
      throw ArgumentError.value(
        employeeId,
        'employeeId',
        'Employee ID is required',
      );
    }

    final params = <String, dynamic>{
      'p_employee_id': employeeId,
      'p_page_size': pageSize,
      'p_cursor_paid_at': cursor?.paidAt.toUtc().toIso8601String(),
      'p_cursor_id': cursor?.id,
    };
    dynamic result;
    try {
      result = await _db.rpc(
        'get_employee_advance_ledger_page_v2',
        params: params,
      );
    } on PostgrestException catch (error) {
      if (!_isMissingPayrollAuditFunction(
        error,
        'get_employee_advance_ledger_page_v2',
      )) {
        rethrow;
      }
      // Expand-first rollout: released backends keep v1 while the structured
      // audit migration is pending. Only a genuinely absent v2 may degrade.
      result = await _db.rpc(
        'get_employee_advance_ledger_page_v1',
        params: params,
      );
    }
    return PayrollAdvanceLedgerPage.fromMap(
      _asJsonObject(
        result,
        command: 'cargar el libro de anticipos',
      ),
    );
  }

  /// Capability-safe advance ledger page for clients that may temporarily run
  /// against a backend awaiting the audit-pagination migration.
  ///
  /// Only an absent RPC is converted to `null`; authorization, connectivity,
  /// parsing and every other failure remain visible to the caller.
  Future<PayrollAdvanceLedgerPage?> tryFetchEmployeeAdvanceLedgerPage({
    required String employeeId,
    int pageSize = 25,
    PayrollAdvanceLedgerCursor? cursor,
  }) async {
    try {
      return await fetchEmployeeAdvanceLedgerPage(
        employeeId: employeeId,
        pageSize: pageSize,
        cursor: cursor,
      );
    } on PostgrestException catch (error) {
      if (!_isMissingPayrollAuditFunction(
        error,
        'get_employee_advance_ledger_page_v1',
      )) {
        rethrow;
      }
      debugPrint(
        '⚠️ [PayrollVoucherService] Advance-ledger pagination is not '
        'installed; using the open-advance compatibility reader.',
      );
      return null;
    }
  }

  /// Probes the exact read contract installed by the structured-advance
  /// migration before a caller uploads immutable evidence. This must never
  /// fall back to ledger v1: a `false` result guarantees that no evidence
  /// object should be created for a money command the backend cannot accept.
  Future<bool> supportsStructuredEmployeeAdvanceAudit({
    required String employeeId,
  }) async {
    final normalizedEmployeeId = employeeId.trim();
    if (normalizedEmployeeId.isEmpty) {
      throw ArgumentError.value(
        employeeId,
        'employeeId',
        'Employee ID is required',
      );
    }
    dynamic result;
    try {
      result = await _db.rpc(
        'get_employee_advance_ledger_page_v2',
        params: <String, dynamic>{
          'p_employee_id': normalizedEmployeeId,
          'p_page_size': 1,
          'p_cursor_paid_at': null,
          'p_cursor_id': null,
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingPayrollAuditFunction(
        error,
        'get_employee_advance_ledger_page_v2',
      )) {
        rethrow;
      }
      return false;
    }
    final response = _asJsonObject(
      result,
      command: 'validar anticipos auditados',
    );
    if (response['contract_version'] != 2) {
      throw StateError(
        'El servidor respondió con un contrato de anticipos incompatible.',
      );
    }
    final page = PayrollAdvanceLedgerPage.fromMap(response);
    if (page.employeeId != normalizedEmployeeId) {
      throw StateError(
        'El servidor respondió por otra persona al validar anticipos.',
      );
    }
    return true;
  }

  /// Loads paid/voided payroll headers using a stable `(period_end, id)`
  /// cursor. Voucher lines and settlement evidence remain on [getVoucher], so
  /// scrolling history never hydrates every historical voucher.
  Future<PayrollHistoryPage> fetchPayrollHistoryPage({
    int pageSize = 25,
    PayrollHistoryCursor? cursor,
  }) async {
    _validatePayrollReadPageSize(pageSize);
    final result = await _db.rpc(
      'get_payroll_history_page_v1',
      params: <String, dynamic>{
        'p_page_size': pageSize,
        'p_cursor_period_end':
            cursor == null ? null : _civilDate(cursor.periodEnd),
        'p_cursor_id': cursor?.id,
      },
    );
    return PayrollHistoryPage.fromMap(
      _asJsonObject(
        result,
        command: 'cargar el historial de nóminas',
      ),
    );
  }

  /// Capability-safe first page for clients that may temporarily run against
  /// a backend awaiting the audit-pagination migration.
  ///
  /// Only an absent RPC is converted to `null`; authorization, connectivity,
  /// parsing and every other failure remain visible to the caller.
  Future<PayrollHistoryPage?> tryFetchPayrollHistoryPage({
    int pageSize = 25,
    PayrollHistoryCursor? cursor,
  }) async {
    try {
      return await fetchPayrollHistoryPage(
        pageSize: pageSize,
        cursor: cursor,
      );
    } on PostgrestException catch (error) {
      if (!_isMissingPayrollAuditFunction(
        error,
        'get_payroll_history_page_v1',
      )) {
        rethrow;
      }
      debugPrint(
        '⚠️ [PayrollVoucherService] Audit pagination is not installed; '
        'using the bounded legacy compatibility reader.',
      );
      return null;
    }
  }

  bool _isMissingPayrollAuditFunction(
    PostgrestException error,
    String functionName,
  ) {
    final hint = error.hint?.toString().toLowerCase() ?? '';
    final diagnostic = <Object?>[
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().join(' ').toLowerCase();
    final namesAuditFunction = diagnostic.contains(functionName);
    final functionIsUnavailable = error.code == 'PGRST202' ||
        error.code == '42883' ||
        diagnostic.contains('schema cache') ||
        diagnostic.contains('could not find the function') ||
        diagnostic.contains('does not exist');
    // A signature mismatch ("no function matches the given name and
    // argument types") is contract drift, not an uninstalled backend: it
    // must stay loudly visible instead of degrading to the legacy reader.
    final isSignatureMismatch = diagnostic.contains('no function matches') ||
        (hint.contains('perhaps you meant') && hint.contains('$functionName('));
    return namesAuditFunction && functionIsUnavailable && !isSignatureMismatch;
  }

  void _validatePayrollReadPageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 100) {
      throw RangeError.range(
        pageSize,
        1,
        100,
        'pageSize',
      );
    }
  }

  /// Fetches a list of vouchers, ordered by most recent first.
  ///
  /// The list screen only needs voucher headers and payroll lines. Settlement
  /// totals are loaded lazily when a row is expanded, avoiding one RPC per
  /// historical payroll during initial navigation.
  Future<List<PayrollVoucher>> fetchVouchers({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedVouchers != null &&
        _isCacheValid(_vouchersCacheTime)) {
      debugPrint(
          '📦 [PayrollVoucherService] Using cached vouchers (${_cachedVouchers!.length} items)');
      return List<PayrollVoucher>.from(_cachedVouchers!);
    }

    if (!forceRefresh && _vouchersLoadFuture != null) {
      return List<PayrollVoucher>.from(await _vouchersLoadFuture!);
    }

    _vouchersLoadFuture = _fetchVouchersFromDatabase();
    try {
      final vouchers = await _vouchersLoadFuture!;
      return List<PayrollVoucher>.from(vouchers);
    } finally {
      _vouchersLoadFuture = null;
    }
  }

  /// Loads only actionable payroll weeks.
  ///
  /// History has its own bounded cursor projection. Keeping this query scoped
  /// to open states prevents the operational Payroll route from hydrating an
  /// ever-growing archive before the user asks to see it.
  Future<List<PayrollVoucher>> fetchOpenVouchers() async {
    try {
      _setLoading(true);
      _setError(null);
      final data = await _fetchVoucherHeaders(
        statuses: const <String>['draft', 'confirmed', 'partial'],
      );
      final voucherIds =
          data.map((row) => row['id']?.toString()).whereType<String>().toList();
      final linesByVoucherId = await _fetchLinesByVoucherId(voucherIds);

      return <PayrollVoucher>[
        for (final row in data)
          _withComputedTotals(
            PayrollVoucher.fromMap(row).copyWith(
              lines: row['id'] == null
                  ? const <PayrollVoucherLine>[]
                  : linesByVoucherId[row['id']?.toString()] ??
                      const <PayrollVoucherLine>[],
            ),
          ),
      ];
    } catch (error) {
      _setError('Error loading open payroll vouchers: $error');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Temporary bounded history reader for a client connected to a backend that
  /// does not yet expose [fetchPayrollHistoryPage].
  ///
  /// This returns headers only. The selected record must still be loaded
  /// explicitly through [getVoucher], so compatibility never turns into an
  /// unbounded archive hydration.
  Future<List<PayrollVoucher>> fetchLegacyHistoryVoucherHeaders({
    int limit = 25,
  }) async {
    _validatePayrollReadPageSize(limit);
    final data = await _fetchVoucherHeaders(
      statuses: const <String>['paid', 'voided'],
      limit: limit,
      orderBy: 'period_end',
    );
    return data.map(PayrollVoucher.fromMap).toList(growable: false);
  }

  Future<List<PayrollVoucher>> _fetchVouchersFromDatabase() async {
    try {
      _setLoading(true);
      _setError(null);

      final data = await _fetchVoucherHeaders();

      final voucherIds =
          data.map((row) => row['id']?.toString()).whereType<String>().toList();
      final linesByVoucherId = await _fetchLinesByVoucherId(voucherIds);

      final vouchers = <PayrollVoucher>[];
      for (final row in data) {
        final voucherId = row['id'] as String?;
        final lines = voucherId == null
            ? const <PayrollVoucherLine>[]
            : linesByVoucherId[voucherId] ?? const <PayrollVoucherLine>[];

        vouchers.add(_withComputedTotals(
          PayrollVoucher.fromMap(row).copyWith(lines: lines),
        ));
      }

      _cachedVouchers = vouchers;
      _vouchersCacheTime = DateTime.now();
      debugPrint(
          '✅ [PayrollVoucherService] Cached ${vouchers.length} payroll vouchers');
      return vouchers;
    } catch (e) {
      _setError('Error loading vouchers: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchVoucherHeaders({
    List<String>? statuses,
    int? limit,
    String orderBy = 'created_at',
  }) async {
    const legacyColumns =
        'id,tenant_id,voucher_number,period_start,period_end,period_label,'
        'total_hours,total_amount,employee_count,status,paid_at,paid_by,notes,'
        'created_by,created_at,updated_at';

    try {
      final rows = await _db.select(
        'payroll_vouchers',
        selectColumns: '$legacyColumns,reconciliation_version',
        where: statuses == null ? null : 'status',
        whereIn: statuses,
        orderBy: orderBy,
        descending: true,
        limit: limit,
      );
      _supportsVersionedPayrollCommands = true;
      return rows;
    } on PostgrestException catch (error) {
      if (!_isMissingReconciliationVersionColumn(error)) rethrow;
      _supportsVersionedPayrollCommands = false;
      debugPrint(
        '⚠️ [PayrollVoucherService] Backend anterior a conciliación OCR; '
        'cargando encabezados de nómina en modo compatible.',
      );
      return _db.select(
        'payroll_vouchers',
        selectColumns: legacyColumns,
        where: statuses == null ? null : 'status',
        whereIn: statuses,
        orderBy: orderBy,
        descending: true,
        limit: limit,
      );
    }
  }

  bool _isMissingReconciliationVersionColumn(PostgrestException error) {
    final diagnostic = <Object?>[
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().join(' ').toLowerCase();
    final identifiesColumn = diagnostic.contains('reconciliation_version');
    final identifiesSchemaMismatch = error.code == 'PGRST204' ||
        error.code == '42703' ||
        diagnostic.contains('schema cache') ||
        diagnostic.contains('column');
    return identifiesColumn && identifiesSchemaMismatch;
  }

  Future<Map<String, List<PayrollVoucherLine>>> _fetchLinesByVoucherId(
    List<String> voucherIds,
  ) async {
    if (voucherIds.isEmpty) {
      return const <String, List<PayrollVoucherLine>>{};
    }

    final rawLines = await _selectWhereInBatches(
      table: 'payroll_voucher_lines',
      column: 'voucher_id',
      values: voucherIds,
      // El asiento contable de un sueldo son dos cuentas: el gasto que se
      // reconoce y la cuenta de donde sale la plata. La segunda ya llegaba
      // resuelta con la evidencia de pago; la primera venía sólo como id, así
      // que el respaldo no podía nombrarla sin inventar. Se resuelve acá —
      // donde ya se lee la línea— en vez de acoplar la UI de Nóminas al
      // servicio de Contabilidad.
      selectColumns:
          'id,voucher_id,employee_id,employee_name,worked_hours,overtime_hours,hourly_rate,overtime_rate,regular_amount,overtime_amount,total_amount,payment_method,is_included,expense_id,salary_account_id,payment_method_id,payment_account_id,'
          'salary_account:accounts!salary_account_id(code,name)',
      orderBy: 'employee_name',
    );

    final grouped = <String, List<PayrollVoucherLine>>{};
    for (final row in rawLines) {
      final voucherId = row['voucher_id'] as String?;
      if (voucherId == null) continue;
      grouped
          .putIfAbsent(voucherId, () => <PayrollVoucherLine>[])
          .add(PayrollVoucherLine.fromMap(row));
    }
    return grouped;
  }

  Future<List<Map<String, dynamic>>> _selectWhereInBatches({
    required String table,
    required String column,
    required List<String> values,
    String? selectColumns,
    String? orderBy,
  }) async {
    final uniqueValues =
        values.where((value) => value.isNotEmpty).toSet().toList();
    if (uniqueValues.isEmpty) return const [];

    const batchSize = 100;
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; start < uniqueValues.length; start += batchSize) {
      final end = start + batchSize > uniqueValues.length
          ? uniqueValues.length
          : start + batchSize;
      rows.addAll(await _db.select(
        table,
        selectColumns: selectColumns,
        where: column,
        whereIn: uniqueValues.sublist(start, end),
        orderBy: orderBy,
      ));
    }
    return rows;
  }

  PayrollVoucher _withComputedTotals(PayrollVoucher voucher) {
    if (voucher.lines.isEmpty) return voucher;

    final computed = _computeVoucherTotals(voucher.lines);
    if ((computed.totalAmount - voucher.totalAmount).abs() <= 0.01 &&
        (computed.totalHours - voucher.totalHours).abs() <= 0.01 &&
        computed.employeeCount == voucher.employeeCount) {
      return voucher;
    }

    return voucher.copyWith(
      totalAmount: computed.totalAmount,
      totalHours: computed.totalHours,
      employeeCount: computed.employeeCount,
    );
  }

  _VoucherTotals _computeVoucherTotals(List<PayrollVoucherLine> lines) {
    double totalAmt = 0;
    double totalHrs = 0;
    int count = 0;

    for (final line in lines) {
      if (!line.isIncluded) continue;
      totalAmt += line.totalAmount;
      totalHrs += line.workedHours + line.overtimeHours;
      count++;
    }

    return _VoucherTotals(
      totalAmount: totalAmt,
      totalHours: totalHrs,
      employeeCount: count,
    );
  }

  Future<Map<String, dynamic>> _saveDraftSnapshot(
    PayrollVoucher voucher, {
    required String operationKey,
    required bool isCreate,
  }) async {
    final header = <String, dynamic>{
      'period_start': _civilDate(voucher.periodStart),
      'period_end': _civilDate(voucher.periodEnd),
      if (voucher.periodLabel?.trim().isNotEmpty == true)
        'period_label': voucher.periodLabel!.trim(),
      if (voucher.notes?.trim().isNotEmpty == true)
        'notes': voucher.notes!.trim(),
    };
    final lines = <Map<String, dynamic>>[
      for (final line in voucher.lines)
        <String, dynamic>{
          if (!isCreate && _looksLikeUuid(line.id)) 'line_id': line.id,
          'employee_id': line.employeeId,
          'worked_hours': line.workedHours,
          'overtime_hours': line.overtimeHours,
          'hourly_rate': line.hourlyRate,
          'overtime_rate': line.overtimeRate,
          'payment_method': line.paymentMethod,
          if (line.paymentMethodId?.trim().isNotEmpty == true)
            'payment_method_id': line.paymentMethodId,
          if (line.paymentAccountId?.trim().isNotEmpty == true)
            'payment_account_id': line.paymentAccountId,
          if (line.salaryAccountId?.trim().isNotEmpty == true)
            'salary_account_id': line.salaryAccountId,
          'is_included': line.isIncluded,
        },
    ];
    final response = await _db.rpc(
      'save_payroll_voucher_draft',
      params: <String, dynamic>{
        'p_voucher_id': isCreate ? null : voucher.id,
        'p_operation_key': operationKey,
        'p_expected_reconciliation_version':
            isCreate ? null : voucher.reconciliationVersion,
        'p_header': header,
        'p_lines': lines,
      },
    );
    return _asJsonObject(response, command: 'guardar la nómina');
  }

  String _newOperationKey(String purpose) =>
      'payroll_${purpose}_${const Uuid().v4()}';

  String _civilDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<tz.Location> _tenantTimeZoneLocation() async {
    if (!_payrollTimeZonesInitialized) {
      tzdata.initializeTimeZones();
      _payrollTimeZonesInitialized = true;
    }

    var timezoneName = 'America/Santiago';
    final tenantId = await _db.getTenantId();
    if (tenantId != null && tenantId.isNotEmpty) {
      try {
        final rows = await _db.select(
          'tenants',
          selectColumns: 'id,timezone',
          where: 'id=$tenantId',
          limit: 1,
        );
        final configured = rows.firstOrNull?['timezone']?.toString().trim();
        if (configured != null && configured.isNotEmpty) {
          timezoneName = configured;
        }
      } catch (_) {
        // The SQL boundary uses the same Santiago fallback when a tenant has
        // no readable timezone configuration.
      }
    }
    try {
      return tz.getLocation(timezoneName);
    } catch (_) {
      return tz.getLocation('America/Santiago');
    }
  }

  Future<String> _tenantCivilInstantIso(DateTime civilValue) async {
    final location = await _tenantTimeZoneLocation();
    return tz.TZDateTime(
      location,
      civilValue.year,
      civilValue.month,
      civilValue.day,
      civilValue.hour,
      civilValue.minute,
      civilValue.second,
      civilValue.millisecond,
      civilValue.microsecond,
    ).toUtc().toIso8601String();
  }

  bool _looksLikeUuid(String? value) =>
      value != null &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
        r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  Map<String, dynamic> _asJsonObject(
    dynamic value, {
    required String command,
  }) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('El servidor no confirmó $command.');
  }

  /// Fetches available payment methods.
  Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    final methods = await _db.select('payment_methods', orderBy: 'name');
    final accountIds = methods
        .map((method) => method['account_id']?.toString().trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (accountIds.isEmpty) return methods;

    final accounts = await _db.select(
      'accounts',
      selectColumns: 'id,code,name',
      where: 'id',
      whereIn: accountIds,
    );
    final accountById = <String, Map<String, dynamic>>{
      for (final account in accounts)
        if (account['id'] != null) account['id'].toString(): account,
    };
    return methods.map((method) {
      final enriched = Map<String, dynamic>.from(method);
      final account = accountById[method['account_id']?.toString()];
      if (account != null) {
        enriched['account_code'] = account['code'];
        enriched['account_name'] = account['name'];
      }
      return enriched;
    }).toList(growable: false);
  }

  /// Every tenant employee, ACTIVE OR NOT: the Anticipos surface must keep an
  /// inactive person with advance history discoverable (Codex cross-review
  /// 2026-07-30). Eligibility for NEW advances is gated per person by status
  /// downstream, never by hiding the record here.
  Future<List<Map<String, dynamic>>> getPayrollEmployees() async {
    return _db.select(
      'employees',
      // La cuenta DESTINO viaja en la misma lectura: la fila abierta de 5a
      // tiene que decir a dónde va la transferencia, y pedirla por persona
      // sería un N+1 sobre una tabla que esta pantalla ya trae entera.
      selectColumns: 'id,first_name,last_name,status,'
          'preferred_payment_method_id,'
          'bank_name,bank_account_type,bank_account_number',
      orderBy: 'first_name',
    );
  }

  /// Resolves an instant to the tenant's civil date (America/Santiago by
  /// default), so every payroll reader shows the same day for one advance.
  Future<DateTime> tenantCivilDate(DateTime instant) async {
    final location = await _tenantTimeZoneLocation();
    final civil = tz.TZDateTime.from(instant.toUtc(), location);
    return DateTime(civil.year, civil.month, civil.day);
  }

  Future<List<EmployeeAdvance>> getOpenEmployeeAdvances() async {
    final rows = await _db.select(
      'employee_advances',
      where: 'status',
      whereIn: const <String>['open', 'partially_applied'],
      orderBy: 'paid_at',
      descending: true,
    );
    final tenantLocation = await _tenantTimeZoneLocation();
    return rows.map((row) {
      final paidAt = DateTime.parse(row['paid_at'] as String).toUtc();
      final paidCivil = tz.TZDateTime.from(paidAt, tenantLocation);
      return EmployeeAdvance.fromMap(<String, dynamic>{
        ...row,
        'paid_civil_date': _civilDate(paidCivil),
      });
    }).toList();
  }

  Future<String> registerEmployeeAdvance({
    required String employeeId,
    required double amount,
    required String paymentMethodId,
    String? paymentAccountId,
    required DateTime paidAt,
    String? reference,
    String? notes,
    String? operationKey,
  }) async {
    final resolvedAccountId = await _resolvePaymentAccountId(
      paymentMethodId: paymentMethodId,
      suppliedAccountId: paymentAccountId,
    );
    final result = await _db.rpc(
      'register_employee_advance_v2',
      params: {
        'p_operation_key': operationKey ?? _newOperationKey('advance_register'),
        'p_employee_id': employeeId,
        'p_amount': amount,
        'p_payment_method_id': paymentMethodId,
        'p_payment_account_id': resolvedAccountId,
        'p_paid_at': await _tenantCivilInstantIso(paidAt),
        'p_reference': reference,
        'p_notes': notes,
      },
    );
    final receipt = _asJsonObject(result, command: 'registrar el anticipo');
    final advanceId = receipt['advance_id']?.toString();
    if (advanceId == null || advanceId.isEmpty) {
      throw StateError('El servidor no devolvió el anticipo registrado.');
    }
    _financialProjectionRefresh.recordCommitted(
      FinancialProjectionChange(
        kind: FinancialProjectionChangeKind.payroll,
        origin: FinancialProjectionChangeOrigin.localCommit,
        entityId: advanceId,
      ),
    );
    return advanceId;
  }

  /// Registers an advance with the structured audit contract owned by v3.
  ///
  /// This deliberately has no v2 fallback: silently dropping the canonical
  /// reason or original evidence during a rolling deployment would turn a
  /// successful financial write into an unaudited one. Released callers that
  /// still need the legacy path keep using [registerEmployeeAdvance].
  Future<PayrollAdvanceRegistrationReceipt> registerAuditedEmployeeAdvance({
    required String employeeId,
    required double amount,
    required String paymentMethodId,
    String? paymentAccountId,
    required DateTime paidAt,
    String? reference,
    String? notes,
    required PayrollAdvanceReasonCode reasonCode,
    required String reasonExplanation,
    DateTime? workEndedOn,
    PayrollAdvanceEvidenceReference? evidence,
    String? operationKey,
  }) async {
    final explanation = reasonExplanation.trim();
    final evidenceId = evidence?.appFileId.trim();
    final evidenceSha256 = evidence?.sha256.trim().toLowerCase();
    final hasValidReason = explanation.isNotEmpty && explanation.length <= 1000;
    final hasValidWorkDate =
        (reasonCode == PayrollAdvanceReasonCode.shortWorkweek) ==
            (workEndedOn != null);
    final hasValidEvidence = evidence == null ||
        (evidenceId != null &&
            evidenceId.isNotEmpty &&
            evidenceSha256 != null &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(evidenceSha256));
    final rawOperationKey =
        operationKey ?? _newOperationKey('advance_register');
    final resolvedOperationKey = rawOperationKey.trim();
    final hasValidOperationKey = rawOperationKey == resolvedOperationKey &&
        RegExp(r'^[A-Za-z0-9:_-]{8,200}$').hasMatch(resolvedOperationKey);
    if (!hasValidReason ||
        !hasValidWorkDate ||
        !hasValidEvidence ||
        !hasValidOperationKey) {
      throw const PayrollVoucherPreflightException.rejected(
        'Completa un motivo válido y su respaldo antes de registrar el anticipo.',
      );
    }

    final resolvedAccountId = await _resolvePaymentAccountId(
      paymentMethodId: paymentMethodId,
      suppliedAccountId: paymentAccountId,
    );
    final resolvedPaidAt = await _tenantCivilInstantIso(paidAt);
    final result = await _db.rpc(
      'register_employee_advance_v3',
      params: <String, dynamic>{
        'p_operation_key': resolvedOperationKey,
        'p_employee_id': employeeId,
        'p_amount': amount,
        'p_payment_method_id': paymentMethodId,
        'p_payment_account_id': resolvedAccountId,
        'p_paid_at': resolvedPaidAt,
        'p_reference': reference,
        'p_notes': notes,
        'p_reason_code': reasonCode.wireValue,
        'p_reason_explanation': explanation,
        'p_work_ended_on': workEndedOn == null ? null : _civilDate(workEndedOn),
        'p_evidence_file_id': evidenceId,
        'p_evidence_file_sha256': evidenceSha256,
      },
    );
    final receipt = _asJsonObject(
      result,
      command: 'registrar el anticipo auditado',
    );
    final advanceId = receipt['advance_id']?.toString().trim();
    final replayed = receipt['replayed'];
    final receiptWorkEndedOn = receipt['work_ended_on']?.toString();
    final expectedWorkEndedOn =
        workEndedOn == null ? null : _civilDate(workEndedOn);
    final receiptAmount = receipt['amount'];
    final evidenceStorageObjectId =
        receipt['evidence_storage_object_id']?.toString().trim();
    final evidenceStorageObjectVersion =
        receipt['evidence_storage_object_version']?.toString().trim();
    final evidenceStorageObjectEtag =
        receipt['evidence_storage_object_etag']?.toString().trim();
    final hasConfirmedStorageIdentity = evidence == null
        ? evidenceStorageObjectId == null &&
            evidenceStorageObjectVersion == null &&
            evidenceStorageObjectEtag == null
        : evidenceStorageObjectId != null &&
            RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
            ).hasMatch(evidenceStorageObjectId) &&
            evidenceStorageObjectVersion != null &&
            evidenceStorageObjectVersion.isNotEmpty &&
            evidenceStorageObjectEtag != null &&
            evidenceStorageObjectEtag.isNotEmpty;
    final receiptPaidAt =
        DateTime.tryParse(receipt['paid_at']?.toString() ?? '');
    final expectedPaidAt = DateTime.parse(resolvedPaidAt);
    final receiptMatches = advanceId != null &&
        advanceId.isNotEmpty &&
        replayed is bool &&
        receipt['operation_key']?.toString() == resolvedOperationKey &&
        receipt['employee_id']?.toString() == employeeId &&
        receiptAmount is num &&
        receiptAmount.toDouble() == amount &&
        receipt['payment_method_id']?.toString() == paymentMethodId &&
        receipt['payment_account_id']?.toString() == resolvedAccountId &&
        receiptPaidAt != null &&
        receiptPaidAt.toUtc().isAtSameMomentAs(expectedPaidAt) &&
        receipt['status'] == 'open' &&
        receipt['reference']?.toString() == reference &&
        receipt['reason_code'] == reasonCode.wireValue &&
        receipt['reason_explanation'] == explanation &&
        receiptWorkEndedOn == expectedWorkEndedOn &&
        receipt['evidence_file_id']?.toString() == evidenceId &&
        receipt['evidence_file_sha256']?.toString() == evidenceSha256 &&
        hasConfirmedStorageIdentity;
    if (!receiptMatches) {
      throw StateError(
        'El servidor no confirmó íntegramente el anticipo auditado.',
      );
    }

    _financialProjectionRefresh.recordCommitted(
      FinancialProjectionChange(
        kind: FinancialProjectionChangeKind.payroll,
        origin: FinancialProjectionChangeOrigin.localCommit,
        entityId: advanceId,
      ),
    );
    return PayrollAdvanceRegistrationReceipt(
      advanceId: advanceId,
      replayed: replayed,
      evidenceStorageObjectId: evidenceStorageObjectId,
      evidenceStorageObjectVersion: evidenceStorageObjectVersion,
      evidenceStorageObjectEtag: evidenceStorageObjectEtag,
    );
  }

  Future<String> _resolvePaymentAccountId({
    required String paymentMethodId,
    String? suppliedAccountId,
  }) async {
    final supplied = suppliedAccountId?.trim();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    final List<Map<String, dynamic>> methods;
    try {
      methods = await getPaymentMethods();
    } catch (_) {
      throw const PayrollVoucherPreflightException.unavailable(
        'No se pudo validar la cuenta del método de pago. Intenta nuevamente.',
      );
    }
    for (final method in methods) {
      if (method['id']?.toString() != paymentMethodId) continue;
      final accountId = method['account_id']?.toString().trim();
      if (method['is_active'] == false ||
          accountId == null ||
          accountId.isEmpty) {
        break;
      }
      return accountId;
    }
    throw const PayrollVoucherPreflightException.rejected(
      'El método de pago no tiene una cuenta contable activa.',
    );
  }

  /// Updates a specific line (e.g., changing hours or payment method).
  Future<void> updateLine(
    PayrollVoucherLine line, {
    String? operationKey,
  }) async {
    if (line.id == null) {
      throw const PayrollVoucherPreflightException.rejected(
        'La línea ya no está disponible. Recarga la semana.',
      );
    }
    try {
      final voucher = await getVoucher(line.voucherId);
      if (voucher == null) {
        throw const PayrollVoucherPreflightException.unavailable(
          'No se pudo validar la semana antes de cambiarla. Intenta nuevamente.',
        );
      }
      if (voucher.status != PayrollVoucherStatus.draft) {
        throw const PayrollVoucherPreflightException.rejected(
          'Una semana confirmada ya no puede cambiar sus horas ni su método. '
          'Registra el pago como movimiento.',
        );
      }
      final replaced = <PayrollVoucherLine>[
        for (final current in voucher.lines)
          if (current.id == line.id) line else current,
      ];
      if (!replaced.any((current) => current.id == line.id)) {
        throw const PayrollVoucherPreflightException.rejected(
          'La línea cambió; recarga la nómina.',
        );
      }
      await updateVoucher(
        voucher.copyWith(lines: replaced),
        operationKey: operationKey ?? _newOperationKey('line_update'),
      );
    } catch (e) {
      _setError('Error updating line: $e');
      rethrow;
    }
  }

  /// Registers one or more payroll settlement movements.
  /// NOTE: Voucher must be in 'confirmed' status (use commitVoucher first).
  ///
  /// [paymentSplits] may contain dated partial payments and advance
  /// allocations. Omitting it preserves the legacy pay-in-full behavior.
  Future<void> payVoucher(
    String voucherId, {
    Map<String, dynamic>? paymentSplits,
    String? operationKey,
    int? expectedReconciliationVersion,
  }) async {
    try {
      _setLoading(true);

      if (paymentSplits == null || paymentSplits.isEmpty) {
        throw const PayrollVoucherPreflightException.rejected(
          'El pago debe indicar exactamente qué persona y monto se registran.',
        );
      }
      final expectedVersion = expectedReconciliationVersion ??
          await _loadVoucherReconciliationVersion(voucherId);
      final result = await _db.rpc(
        'pay_payroll_voucher_v2',
        params: <String, dynamic>{
          'p_voucher_id': voucherId,
          'p_operation_key': operationKey ?? _newOperationKey('payment'),
          'p_expected_reconciliation_version': expectedVersion,
          'p_payment_splits': paymentSplits,
        },
      );
      _asJsonObject(result, command: 'registrar el pago de nómina');
      _financialProjectionRefresh.recordCommitted(
        FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.payroll,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: voucherId,
        ),
      );
      invalidateVouchersCache();
    } catch (e) {
      _setError('Error paying voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<int> _loadVoucherReconciliationVersion(String voucherId) async {
    final id = voucherId.trim();
    if (id.isEmpty) {
      throw const PayrollVoucherPreflightException.rejected(
        'La semana ya no está disponible. Recarga antes de continuar.',
      );
    }
    final Map<String, dynamic>? row;
    try {
      row = await _db.selectById('payroll_vouchers', id);
    } catch (_) {
      throw const PayrollVoucherPreflightException.unavailable(
        'No se pudo validar la versión de la semana. Intenta nuevamente.',
      );
    }
    if (row == null) {
      throw const PayrollVoucherPreflightException.rejected(
        'La semana ya no existe. Recarga antes de continuar.',
      );
    }
    final version = row['reconciliation_version'];
    if (version is! num) {
      throw const PayrollVoucherPreflightException.unavailable(
        'La semana no trae una versión verificable. Actualiza la vista antes '
        'de continuar.',
      );
    }
    return version.toInt();
  }

  int? _cachedVoucherReconciliationVersion(String voucherId) {
    final cached = _cachedVouchers;
    if (cached == null) return null;
    for (final voucher in cached) {
      if (voucher.id == voucherId) return voucher.reconciliationVersion;
    }
    return null;
  }

  /// Commits a draft voucher and recognizes each salary obligation.
  /// Asientos contables reales de un conjunto de pagos, indexados por el id
  /// del pago (`expense_payments.id`, que es el `evidence_id` de la evidencia).
  ///
  /// El vínculo es `journal_entries.source_reference = expense_payments.id`
  /// con `source_module = 'expense_payments'`, verificado contra producción.
  Future<Map<String, PayrollJournalEntry>> fetchJournalEntriesForPayments(
    List<String> paymentIds,
  ) async {
    final ids = paymentIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    try {
      final entryRows = await _db.select(
        'journal_entries',
        selectColumns: 'id,entry_number,source_reference',
        where: 'source_reference',
        whereIn: ids,
      );
      if (entryRows.isEmpty) return const {};

      final entryIds = entryRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();
      final lineRows = await _db.select(
        'journal_lines',
        selectColumns: 'entry_id,account_code,account_name,debit_amount,'
            'credit_amount',
        where: 'entry_id',
        whereIn: entryIds,
      );

      final linesByEntry = <String, List<PayrollJournalLine>>{};
      for (final row in lineRows) {
        final entryId = row['entry_id']?.toString();
        if (entryId == null) continue;
        linesByEntry
            .putIfAbsent(entryId, () => <PayrollJournalLine>[])
            .add(PayrollJournalLine.fromMap(row));
      }

      final result = <String, PayrollJournalEntry>{};
      for (final row in entryRows) {
        final entryId = row['id']?.toString();
        final paymentId = row['source_reference']?.toString();
        if (entryId == null || paymentId == null) continue;
        final lines = linesByEntry[entryId] ?? const <PayrollJournalLine>[];
        if (lines.isEmpty) continue;
        // El debe primero: es como se lee un asiento.
        lines.sort((a, b) => b.debit.compareTo(a.debit));
        result[paymentId] = PayrollJournalEntry(
          entryNumber: row['entry_number']?.toString() ?? '',
          lines: lines,
        );
      }
      return result;
    } catch (e) {
      // Un asiento ilegible no puede tumbar el respaldo del pago: el resto de
      // la evidencia sigue siendo válida y útil.
      debugPrint('No se pudieron leer los asientos de estos pagos: $e');
      return const {};
    }
  }

  Future<void> commitVoucher(
    String id, {
    String? operationKey,
    int? expectedReconciliationVersion,
  }) async {
    try {
      _setLoading(true);
      _setError(null);
      final expectedVersion = expectedReconciliationVersion ??
          _cachedVoucherReconciliationVersion(id) ??
          await _loadVoucherReconciliationVersion(id);
      final result = await _db.rpc(
        'confirm_payroll_voucher_v2',
        params: <String, dynamic>{
          'p_voucher_id': id,
          'p_operation_key': operationKey ?? _newOperationKey('draft_confirm'),
          'p_expected_reconciliation_version': expectedVersion,
        },
      );
      _asJsonObject(result, command: 'confirmar la semana');
      _financialProjectionRefresh.recordCommitted(
        FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.payroll,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: id,
        ),
      );
      invalidateVouchersCache();
    } catch (e) {
      _setError('No se pudo confirmar la semana: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Compatibility alias for callers that still use the ambiguous legacy
  /// lifecycle name. Committing is the accounting action performed by the RPC.
  @Deprecated('Use commitVoucher.')
  Future<void> confirmVoucher(
    String id, {
    String? operationKey,
    int? expectedReconciliationVersion,
  }) {
    return commitVoucher(
      id,
      operationKey: operationKey,
      expectedReconciliationVersion: expectedReconciliationVersion,
    );
  }

  /// Reverts payment/advance movements while preserving salary obligations.
  Future<void> revertPayment(String id) async {
    try {
      _setLoading(true);
      await _db.rpc('revert_payroll_payment', params: {'p_voucher_id': id});
      _financialProjectionRefresh.recordCommitted(
        FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.payroll,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: id,
        ),
      );
      invalidateVouchersCache();
    } catch (e) {
      _setError('Error reverting payment: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Deletes an unsettled draft through the server-owned aggregate command.
  Future<void> deleteVoucher(
    String id, {
    String? operationKey,
    int? expectedReconciliationVersion,
  }) async {
    try {
      _setLoading(true);
      _setError(null);
      final expectedVersion = expectedReconciliationVersion ??
          _cachedVoucherReconciliationVersion(id) ??
          await _loadVoucherReconciliationVersion(id);
      final result = await _db.rpc(
        'delete_payroll_voucher_draft_v2',
        params: <String, dynamic>{
          'p_voucher_id': id,
          'p_operation_key': operationKey ?? _newOperationKey('draft_delete'),
          'p_expected_reconciliation_version': expectedVersion,
        },
      );
      _asJsonObject(result, command: 'eliminar la nómina');
      _financialProjectionRefresh.recordCommitted(
        FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.payroll,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: id,
        ),
      );
      invalidateVouchersCache();
    } catch (e) {
      _setError('Error deleting voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Reverts a confirmed voucher back to draft status (confirmed → draft).
  Future<void> revertToDraft(String id) async {
    try {
      _setLoading(true);
      await _db.rpc('revert_payroll_to_draft', params: {'p_voucher_id': id});
      _financialProjectionRefresh.recordCommitted(
        FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.payroll,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: id,
        ),
      );
      invalidateVouchersCache();
    } catch (e) {
      _setError('Error reverting to draft: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<PayrollVoucher> hydrateVoucherSettlements(
    PayrollVoucher voucher,
  ) async {
    final hydrated = await _hydrateSettlementData(voucher);
    _replaceCachedVoucher(hydrated);
    return hydrated;
  }

  /// Hydrates every open voucher before a decision surface can expose balance.
  ///
  /// Paid/voided history remains lazy because it is not actionable and may be
  /// large. Open weeks are few and their settlement truth is required before
  /// enabling any payment command.
  Future<List<PayrollVoucher>> hydrateOpenVoucherSettlements(
    Iterable<PayrollVoucher> vouchers,
  ) async {
    final source = vouchers.toList(growable: false);
    final open = source
        .where(
          (voucher) =>
              voucher.status == PayrollVoucherStatus.draft ||
              voucher.status == PayrollVoucherStatus.confirmed ||
              voucher.status == PayrollVoucherStatus.partial,
        )
        .toList(growable: false);
    if (open.isEmpty) return source;

    if (supportsVersionedPayrollCommands) {
      try {
        final hydratedOpen = await _hydrateSettlementEvidenceBatch(open);
        final byId = <String, PayrollVoucher>{
          for (final voucher in hydratedOpen)
            if (voucher.id != null) voucher.id!: voucher,
        };
        final hydrated = [
          for (final voucher in source) byId[voucher.id] ?? voucher,
        ];
        for (final voucher in hydratedOpen) {
          _replaceCachedVoucher(voucher);
        }
        return hydrated;
      } on PostgrestException catch (error) {
        if (!_isMissingSettlementEvidenceFunction(error)) rethrow;
        debugPrint(
          '⚠️ [PayrollVoucherService] Evidence projection is not installed; '
          'using the aggregate compatibility reader.',
        );
      }
    }

    return Future.wait(
      source.map((voucher) {
        final isOpen = open.any((candidate) => candidate.id == voucher.id);
        return isOpen
            ? hydrateVoucherSettlements(voucher)
            : Future.value(voucher);
      }),
    );
  }

  void _replaceCachedVoucher(PayrollVoucher voucher) {
    final id = voucher.id;
    final cached = _cachedVouchers;
    if (id == null || cached == null) return;

    final index = cached.indexWhere((item) => item.id == id);
    if (index == -1) return;

    final updated = List<PayrollVoucher>.from(cached);
    updated[index] = voucher;
    _cachedVouchers = updated;
  }

  Future<PayrollVoucher> _hydrateSettlementData(PayrollVoucher voucher) async {
    if (voucher.id == null ||
        voucher.id == 'preview' ||
        voucher.lines.isEmpty) {
      return voucher;
    }

    if (supportsVersionedPayrollCommands) {
      try {
        return (await _hydrateSettlementEvidenceBatch([voucher])).single;
      } on PostgrestException catch (error) {
        if (!_isMissingSettlementEvidenceFunction(error)) rethrow;
        debugPrint(
          '⚠️ [PayrollVoucherService] Evidence projection is not installed; '
          'using the aggregate compatibility reader.',
        );
      }
    }

    try {
      return await _hydrateSettlementDataFromTables(voucher);
    } catch (e) {
      debugPrint(
          '⚠️ [PayrollVoucherService] Bulk settlement hydration failed, falling back to RPC: $e');
      return _hydrateSettlementDataViaRpc(voucher);
    }
  }

  Future<List<PayrollVoucher>> _hydrateSettlementEvidenceBatch(
    List<PayrollVoucher> vouchers,
  ) async {
    final voucherIds = vouchers
        .map((voucher) => voucher.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty && id != 'preview')
        .toSet()
        .toList(growable: false);
    if (voucherIds.isEmpty) return vouchers;

    final raw = await _db.rpc(
      'get_payroll_voucher_settlement_evidence',
      params: <String, dynamic>{'p_voucher_ids': voucherIds},
    );
    final rows = raw is List ? raw : const <dynamic>[];
    final evidenceByLineId = <String, List<PayrollSettlementEvidence>>{};
    for (final rawRow in rows) {
      if (rawRow is! Map) continue;
      final row = Map<String, dynamic>.from(rawRow);
      final lineId = row['line_id']?.toString();
      final evidenceId = row['evidence_id']?.toString();
      final voucherId = row['voucher_id']?.toString();
      if (lineId == null ||
          lineId.isEmpty ||
          evidenceId == null ||
          evidenceId.isEmpty ||
          voucherId == null ||
          voucherId.isEmpty) {
        continue;
      }
      evidenceByLineId
          .putIfAbsent(lineId, () => <PayrollSettlementEvidence>[])
          .add(PayrollSettlementEvidence.fromMap(row));
    }

    return [
      for (final voucher in vouchers)
        voucher.copyWith(
          lines: [
            for (final line in voucher.lines)
              _lineWithEvidence(
                line,
                line.id == null
                    ? const <PayrollSettlementEvidence>[]
                    : evidenceByLineId[line.id] ??
                        const <PayrollSettlementEvidence>[],
              ),
          ],
        ),
    ];
  }

  PayrollVoucherLine _lineWithEvidence(
    PayrollVoucherLine line,
    List<PayrollSettlementEvidence> evidence,
  ) {
    final sorted = List<PayrollSettlementEvidence>.from(evidence)
      ..sort((a, b) {
        final aDate = a.effectiveDate ?? a.recordedAt;
        final bDate = b.effectiveDate ?? b.recordedAt;
        if (aDate == null && bDate == null) return a.id.compareTo(b.id);
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        final byDate = aDate.compareTo(bDate);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    final cashPaid = sorted
        .where(
          (item) => item.kind == PayrollSettlementEvidenceKind.payment,
        )
        .fold<double>(0, (sum, item) => sum + item.amount);
    final advancesApplied = sorted
        .where(
          (item) => item.kind == PayrollSettlementEvidenceKind.advance,
        )
        .fold<double>(0, (sum, item) => sum + item.amount);
    final paid = cashPaid + advancesApplied;
    final settledAmount = paid > line.totalAmount ? line.totalAmount : paid;
    final remaining = line.totalAmount - paid;
    return line.copyWith(
      cashPaid: cashPaid,
      advancesApplied: advancesApplied,
      settledAmount: settledAmount,
      balance: remaining > 0 ? remaining : 0,
      settlementEvidence: List.unmodifiable(sorted),
    );
  }

  bool _isMissingSettlementEvidenceFunction(PostgrestException error) {
    final diagnostic = <Object?>[
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().join(' ').toLowerCase();
    return (error.code == 'PGRST202' ||
            error.code == '42883' ||
            diagnostic.contains('schema cache')) &&
        diagnostic.contains('get_payroll_voucher_settlement_evidence');
  }

  Future<PayrollVoucher> _hydrateSettlementDataFromTables(
    PayrollVoucher voucher,
  ) async {
    final expenseIds = voucher.lines
        .map((line) => line.expenseId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final lineIds = voucher.lines
        .map((line) => line.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final paymentRows = expenseIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _selectWhereInBatches(
            table: 'expense_payments',
            column: 'expense_id',
            values: expenseIds,
            selectColumns: 'expense_id,amount',
          );
    final advanceRows = lineIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _selectWhereInBatches(
            table: 'employee_advance_allocations',
            column: 'voucher_line_id',
            values: lineIds,
            selectColumns: 'voucher_line_id,amount',
          );

    final cashPaidByExpenseId = <String, double>{};
    for (final row in paymentRows) {
      _sumAmount(
        cashPaidByExpenseId,
        row['expense_id']?.toString(),
        row['amount'],
      );
    }

    final advancesByLineId = <String, double>{};
    for (final row in advanceRows) {
      _sumAmount(
        advancesByLineId,
        row['voucher_line_id']?.toString(),
        row['amount'],
      );
    }

    return voucher.copyWith(
      lines: voucher.lines.map((line) {
        final cashPaid = line.expenseId == null
            ? 0.0
            : cashPaidByExpenseId[line.expenseId] ?? 0.0;
        final advancesApplied =
            line.id == null ? 0.0 : advancesByLineId[line.id] ?? 0.0;
        final paid = cashPaid + advancesApplied;
        final settledAmount = paid > line.totalAmount ? line.totalAmount : paid;
        final remaining = line.totalAmount - paid;
        final balance = remaining > 0 ? remaining : 0.0;

        return line.copyWith(
          cashPaid: cashPaid,
          advancesApplied: advancesApplied,
          settledAmount: settledAmount,
          balance: balance,
        );
      }).toList(),
    );
  }

  void _sumAmount(
    Map<String, double> totals,
    String? key,
    Object? amount,
  ) {
    if (key == null || key.isEmpty) return;
    totals[key] = (totals[key] ?? 0) + _toDouble(amount);
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<PayrollVoucher> _hydrateSettlementDataViaRpc(
    PayrollVoucher voucher,
  ) async {
    if (voucher.id == null || voucher.id == 'preview') return voucher;

    final raw = await _db.rpc(
      'get_payroll_voucher_line_settlements',
      params: {'p_voucher_id': voucher.id},
    );
    final rows = raw is List ? raw : const <dynamic>[];
    final settlements = <String, Map<String, dynamic>>{
      for (final row in rows)
        if (row is Map && row['line_id'] != null)
          row['line_id'].toString(): Map<String, dynamic>.from(row),
    };

    return voucher.copyWith(
      lines: voucher.lines.map((line) {
        final settlement = settlements[line.id];
        if (settlement == null) return line;
        return line.copyWith(
          cashPaid: (settlement['cash_paid'] as num?)?.toDouble() ?? 0,
          advancesApplied:
              (settlement['advances_applied'] as num?)?.toDouble() ?? 0,
          settledAmount:
              (settlement['settled_amount'] as num?)?.toDouble() ?? 0,
          balance:
              (settlement['balance'] as num?)?.toDouble() ?? line.totalAmount,
        );
      }).toList(),
    );
  }
}

class _VoucherTotals {
  const _VoucherTotals({
    required this.totalAmount,
    required this.totalHours,
    required this.employeeCount,
  });

  final double totalAmount;
  final double totalHours;
  final int employeeCount;
}
