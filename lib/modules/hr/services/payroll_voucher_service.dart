import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/payroll_voucher.dart';
import '../../../../shared/services/database_service.dart';

class PayrollVoucherService extends ChangeNotifier {
  final DatabaseService _db;

  PayrollVoucherService(this._db);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

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
  Future<List<PayrollVoucher>> fetchVouchers() async {
    try {
      _setLoading(true);
      _setError(null);

      final data = await _db.select(
        'payroll_vouchers',
        orderBy: 'created_at',
        descending: true,
      );

      // Fetch lines for each voucher
      final vouchers = <PayrollVoucher>[];
      for (var v in data) {
        final voucherId = v['id'] as String;

        // Fetch lines directly
        final rawLines = await _db.select(
          'payroll_voucher_lines',
          where: 'voucher_id=$voucherId',
        );
        final lines =
            rawLines.map((l) => PayrollVoucherLine.fromMap(l)).toList();

        var voucher = PayrollVoucher.fromMap(v).copyWith(lines: lines);

        // Keep header totals aligned with current lines.
        final computed = _computeVoucherTotals(voucher.lines);
        if ((computed.totalAmount - voucher.totalAmount).abs() > 0.01 ||
            (computed.totalHours - voucher.totalHours).abs() > 0.01 ||
            computed.employeeCount != voucher.employeeCount) {
          await _db.update('payroll_vouchers', voucherId, {
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
        vouchers.add(voucher);
      }

      return vouchers;
    } catch (e) {
      _setError('Error loading vouchers: $e');
      return [];
    } finally {
      _setLoading(false);
    }
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

  /// Pays the voucher, generating expenses.
  /// NOTE: Voucher must be in 'confirmed' status (use confirmVoucher first).
  ///
  /// If [paymentSplits] is provided, it is forwarded to the RPC so each
  /// voucher line can be paid with multiple payment methods.
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
    } catch (e) {
      _setError('Error paying voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Confirms a draft voucher (draft → confirmed).
  /// This makes the voucher ready for payment.
  Future<void> confirmVoucher(String id) async {
    try {
      _setLoading(true);
      await _db.rpc('confirm_payroll_voucher', params: {'p_voucher_id': id});
    } catch (e) {
      _setError('Error confirming voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Reverts a paid voucher back to confirmed status (paid → confirmed).
  /// This deletes all expenses and journal entries generated by the payment.
  Future<void> revertPayment(String id) async {
    try {
      _setLoading(true);
      await _db.rpc('revert_payroll_payment', params: {'p_voucher_id': id});
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
    } catch (e) {
      _setError('Error reverting to draft: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
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
