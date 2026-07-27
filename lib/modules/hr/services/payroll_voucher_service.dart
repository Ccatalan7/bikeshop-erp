import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/payroll_voucher.dart';
import '../../../../shared/services/database_service.dart';
import '../../accounting/services/financial_projection_refresh_coordinator.dart';

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
  static const Duration _cacheMaxAge = Duration(minutes: 5);

  List<PayrollVoucher> get cachedVouchers =>
      List.unmodifiable(_cachedVouchers ?? const <PayrollVoucher>[]);
  bool get hasVouchersCache =>
      _cachedVouchers != null && _vouchersCacheTime != null;

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
            'get_attendance_summary_for_period',
            params: {
              'p_start_date': startDate.toIso8601String().split('T')[0],
              'p_end_date': endDate.toIso8601String().split('T')[0],
            },
          ) as List<dynamic>? ??
          [];

      // Build a map of employee_id -> total hours
      final hoursMap = <String, double>{};
      for (var att in attendances) {
        final empId = att['employee_id'] as String;
        final hours = (att['total_hours'] as num?)?.toDouble() ?? 0;
        hoursMap[empId] = hours;
      }

      // Generate preview lines
      final lines = <PayrollVoucherLine>[];
      double totalAmount = 0;
      double totalHours = 0;

      for (var emp in employees) {
        final empId = emp['id'] as String;
        final workedHours = hoursMap[empId] ?? 0;
        final hourlyRate = (emp['hourly_rate'] as num?)?.toDouble() ?? 0;
        final lineTotal = workedHours * hourlyRate;

        lines.add(PayrollVoucherLine(
          id: empId, // Use employee ID as temp ID for preview
          voucherId: 'preview',
          employeeId: empId,
          employeeName:
              '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim(),
          workedHours: workedHours,
          overtimeHours: 0,
          hourlyRate: hourlyRate,
          overtimeRate: hourlyRate * 1.5,
          regularAmount: lineTotal,
          overtimeAmount: 0,
          totalAmount: lineTotal,
          isIncluded: true,
          paymentMethod: emp['preferred_payment_method'] ?? 'transfer',
          paymentMethodId: emp['preferred_payment_method_id'],
          salaryAccountId: emp['salary_account_id'],
        ));

        totalAmount += lineTotal;
        totalHours += workedHours;
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

  /// Saves the preview voucher as a draft to the database.
  /// Call this AFTER user reviews and possibly modifies the preview.
  Future<String> saveDraft(PayrollVoucher preview) async {
    try {
      _setLoading(true);
      _setError(null);

      // Generate sequential voucher number like NOM-00001
      final existing = await _db.select(
        'payroll_vouchers',
        orderBy: 'voucher_number',
        descending: true,
        limit: 1,
      );

      int nextNum = 1;
      if (existing.isNotEmpty) {
        final lastNumber = existing.first['voucher_number'] as String? ?? '';
        final match = RegExp(r'NOM-(\d+)').firstMatch(lastNumber);
        if (match != null) {
          nextNum = int.parse(match.group(1)!) + 1;
        }
      }
      final voucherNumber = 'NOM-${nextNum.toString().padLeft(5, '0')}';

      // Insert voucher header
      final voucherData = await _db.insert('payroll_vouchers', {
        'voucher_number': voucherNumber,
        'period_start': preview.periodStart.toIso8601String().split('T')[0],
        'period_end': preview.periodEnd.toIso8601String().split('T')[0],
        'period_label': preview.periodLabel,
        'status': 'draft',
        'total_amount': preview.totalAmount,
        'total_hours': preview.totalHours,
        'employee_count': preview.employeeCount,
      });

      final voucherId = voucherData['id'] as String;

      // Insert lines
      for (var line in preview.lines) {
        if (!line.isIncluded) continue;
        await _db.insert('payroll_voucher_lines', {
          'voucher_id': voucherId,
          'employee_id': line.employeeId,
          'employee_name': line.employeeName,
          'worked_hours': line.workedHours,
          'overtime_hours': line.overtimeHours,
          'hourly_rate': line.hourlyRate,
          'overtime_rate': line.overtimeRate,
          'regular_amount': line.regularAmount,
          'overtime_amount': line.overtimeAmount,
          'total_amount': line.totalAmount,
          'is_included': line.isIncluded,
        });
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
  Future<void> updateVoucher(PayrollVoucher voucher) async {
    if (voucher.id == null) {
      throw Exception('Cannot update voucher without ID');
    }

    try {
      _setLoading(true);
      _setError(null);

      // Update voucher header
      await _db.update('payroll_vouchers', voucher.id!, {
        'period_start': voucher.periodStart.toIso8601String().split('T')[0],
        'period_end': voucher.periodEnd.toIso8601String().split('T')[0],
        'period_label': voucher.periodLabel,
        'total_amount': voucher.totalAmount,
        'total_hours': voucher.totalHours,
        'employee_count': voucher.employeeCount,
      });

      // Delete existing lines and re-insert
      await _db.deleteWhere('payroll_voucher_lines', 'voucher_id', voucher.id!);

      // Insert updated lines
      for (var line in voucher.lines) {
        if (!line.isIncluded) continue;
        await _db.insert('payroll_voucher_lines', {
          'voucher_id': voucher.id,
          'employee_id': line.employeeId,
          'employee_name': line.employeeName,
          'worked_hours': line.workedHours,
          'overtime_hours': line.overtimeHours,
          'hourly_rate': line.hourlyRate,
          'overtime_rate': line.overtimeRate,
          'regular_amount': line.regularAmount,
          'overtime_amount': line.overtimeAmount,
          'total_amount': line.totalAmount,
          'is_included': line.isIncluded,
        });
      }

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
  /// @deprecated Use generatePreview() + saveDraft() instead
  Future<String> generateDraft(
    DateTime startDate,
    DateTime endDate, {
    String? periodLabel,
  }) async {
    try {
      _setLoading(true);
      _setError(null);

      // Call the RPC function via DatabaseService
      final response = await _db.rpc(
        'generate_payroll_voucher_draft',
        params: {
          'p_start_date': startDate.toIso8601String(),
          'p_end_date': endDate.toIso8601String(),
          'p_period_label': periodLabel,
        },
      );

      return response as String;
    } catch (e) {
      _setError('Error creating voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches a specific voucher by ID with all its lines.
  Future<PayrollVoucher?> getVoucher(String id) async {
    try {
      _setLoading(true);
      _setError(null);

      // Fetch voucher header
      final voucherData = await _db.selectById('payroll_vouchers', id);
      if (voucherData == null) return null;

      // Fetch lines
      final linesData = await _db.select(
        'payroll_voucher_lines',
        where: 'voucher_id=$id',
        orderBy: 'employee_name',
      );

      var voucher = PayrollVoucher.fromMap({
        ...voucherData,
        'lines': linesData,
      });
      voucher = await _hydrateSettlementData(voucher);

      // Ensure header totals stay consistent with line totals.
      // This avoids confusing mismatches like a stale voucher.total_amount.
      final computed = _computeVoucherTotals(voucher.lines);
      if ((computed.totalAmount - voucher.totalAmount).abs() > 0.01 ||
          (computed.totalHours - voucher.totalHours).abs() > 0.01 ||
          computed.employeeCount != voucher.employeeCount) {
        await _db.update('payroll_vouchers', id, {
          'total_amount': computed.totalAmount,
          'total_hours': computed.totalHours,
          'employee_count': computed.employeeCount,
        });
        voucher = voucher.copyWith(
          totalAmount: computed.totalAmount,
          totalHours: computed.totalHours,
          employeeCount: computed.employeeCount,
        );
      }

      return voucher;
    } catch (e) {
      _setError('Error loading voucher: $e');
      return null;
    } finally {
      _setLoading(false);
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

  Future<List<PayrollVoucher>> _fetchVouchersFromDatabase() async {
    try {
      _setLoading(true);
      _setError(null);

      final data = await _db.select(
        'payroll_vouchers',
        selectColumns:
            'id,tenant_id,voucher_number,period_start,period_end,period_label,total_hours,total_amount,employee_count,status,paid_at,paid_by,notes,created_by,created_at,updated_at',
        orderBy: 'created_at',
        descending: true,
      );

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
      return [];
    } finally {
      _setLoading(false);
    }
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
      selectColumns:
          'id,voucher_id,employee_id,employee_name,worked_hours,overtime_hours,hourly_rate,overtime_rate,regular_amount,overtime_amount,total_amount,payment_method,is_included,expense_id,salary_account_id,payment_method_id,payment_account_id',
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

  /// Fetches available payment methods.
  Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    return await _db.select('payment_methods', orderBy: 'name');
  }

  Future<List<EmployeeAdvance>> getOpenEmployeeAdvances() async {
    final rows = await _db.select(
      'employee_advances',
      orderBy: 'paid_at',
      descending: true,
    );
    return rows
        .map(EmployeeAdvance.fromMap)
        .where((advance) =>
            advance.status == 'open' || advance.status == 'partially_applied')
        .toList();
  }

  Future<String> registerEmployeeAdvance({
    required String employeeId,
    required double amount,
    required String paymentMethodId,
    String? paymentAccountId,
    required DateTime paidAt,
    String? reference,
    String? notes,
  }) async {
    final result = await _db.rpc(
      'register_employee_advance',
      params: {
        'p_employee_id': employeeId,
        'p_amount': amount,
        'p_payment_method_id': paymentMethodId,
        'p_payment_account_id': paymentAccountId,
        'p_paid_at': paidAt.toUtc().toIso8601String(),
        'p_reference': reference,
        'p_notes': notes,
      },
    );
    final advanceId = result as String;
    _financialProjectionRefresh.recordCommitted(
      FinancialProjectionChange(
        kind: FinancialProjectionChangeKind.payroll,
        origin: FinancialProjectionChangeOrigin.localCommit,
        entityId: advanceId,
      ),
    );
    return advanceId;
  }

  /// Updates a specific line (e.g., changing hours or payment method).
  Future<void> updateLine(PayrollVoucherLine line) async {
    if (line.id == null) return;
    try {
      // Recalculate totals client-side before save for accuracy
      final rate = line.hourlyRate;
      final otRate = line.overtimeRate;
      final regAmt = line.workedHours * rate;
      final otAmt = line.overtimeHours * otRate;
      final total = regAmt + otAmt;

      await _db.update('payroll_voucher_lines', line.id!, {
        'worked_hours': line.workedHours,
        'overtime_hours': line.overtimeHours,
        'hourly_rate': line.hourlyRate,
        'overtime_rate': line.overtimeRate,
        'regular_amount': regAmt,
        'overtime_amount': otAmt,
        'total_amount': total,
        'payment_method': line.paymentMethod,
        'is_included': line.isIncluded,
        'salary_account_id': line.salaryAccountId,
        // New strict fields
        'payment_method_id': line.paymentMethodId,
        'payment_account_id': line.paymentAccountId,
      });

      // Recalculate voucher totals
      await _recalculateVoucherTotals(line.voucherId);
      invalidateVouchersCache();
    } catch (e) {
      _setError('Error updating line: $e');
      rethrow;
    }
  }

  /// Private helper to update voucher totals after line changes.
  Future<void> _recalculateVoucherTotals(String voucherId) async {
    // Fetch all lines for this voucher
    final data = await _db.select(
      'payroll_voucher_lines',
      where: 'voucher_id=$voucherId',
    );

    double totalAmt = 0;
    double totalHrs = 0;
    int count = 0;

    for (var row in data) {
      // Only include if is_included is true
      if (row['is_included'] == true) {
        totalAmt += (row['total_amount'] as num).toDouble();
        totalHrs += (row['worked_hours'] as num).toDouble() +
            (row['overtime_hours'] as num).toDouble();
        count++;
      }
    }

    await _db.update('payroll_vouchers', voucherId, {
      'total_amount': totalAmt,
      'total_hours': totalHrs,
      'employee_count': count,
    });
  }

  /// Registers one or more payroll settlement movements.
  /// NOTE: Voucher must be in 'confirmed' status (use confirmVoucher first).
  ///
  /// [paymentSplits] may contain dated partial payments and advance
  /// allocations. Omitting it preserves the legacy pay-in-full behavior.
  Future<void> payVoucher(
    String voucherId, {
    Map<String, dynamic>? paymentSplits,
  }) async {
    try {
      _setLoading(true);

      final params = <String, dynamic>{
        'p_voucher_id': voucherId,
      };

      if (paymentSplits != null) {
        params['p_payment_splits'] = paymentSplits;
      }

      await _db.rpc('pay_payroll_voucher', params: params);
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

  /// Confirms a draft voucher and recognizes each salary obligation.
  Future<void> confirmVoucher(String id) async {
    try {
      _setLoading(true);
      await _db.rpc('confirm_payroll_voucher', params: {'p_voucher_id': id});
      _financialProjectionRefresh.recordCommitted(
        FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.payroll,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: id,
        ),
      );
      invalidateVouchersCache();
    } catch (e) {
      _setError('Error confirming voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
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

  /// Deletes a draft voucher along with its expenses and journal entries.
  Future<void> deleteVoucher(String id) async {
    try {
      _setLoading(true);

      // 1. Fetch lines to get expense IDs
      final lines = await _db.select(
        'payroll_voucher_lines',
        where: 'voucher_id=$id',
      );

      // 2. Delete expenses linked to each line
      for (var line in lines) {
        final expenseId = line['expense_id'] as String?;
        if (expenseId != null) {
          // Delete journal entries for this expense (will cascade if lines table exists)
          try {
            await _db.delete('journal_entries',
                'source_type=\'expense\' AND source_id=\'$expenseId\'');
          } catch (_) {}

          // Delete the expense
          await _db.delete('expenses', expenseId);
        }
      }

      // 3. Delete any journal entries linked directly to the payroll voucher
      try {
        await _db.delete(
            'journal_entries', 'source_type=\'payroll\' AND source_id=\'$id\'');
      } catch (_) {}

      // 4. Delete lines (will cascade via FK, but explicit is safer)
      await _db.deleteWhere('payroll_voucher_lines', 'voucher_id', id);

      // 5. Delete the voucher itself
      await _db.delete('payroll_vouchers', id);
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

    try {
      return await _hydrateSettlementDataFromTables(voucher);
    } catch (e) {
      debugPrint(
          '⚠️ [PayrollVoucherService] Bulk settlement hydration failed, falling back to RPC: $e');
      return _hydrateSettlementDataViaRpc(voucher);
    }
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
