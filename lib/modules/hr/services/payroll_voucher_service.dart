import 'package:flutter/foundation.dart';
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
    notifyListeners();
  }

  void _setError(String? value) {
    _error = value;
    notifyListeners();
  }

  /// Generates a new voucher draft for the given period.
  /// Returns the ID of the created voucher.
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

      final voucher = PayrollVoucher.fromMap({
        ...voucherData,
        'lines': linesData,
      });

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

      return data.map((e) => PayrollVoucher.fromMap(e)).toList();
    } catch (e) {
      _setError('Error loading vouchers: $e');
      return [];
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches available payment methods.
  Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    return await _db.select('payment_methods', orderBy: 'name');
  }

  /// Fetches available payment/asset accounts.
  Future<List<Map<String, dynamic>>> getPaymentAccounts() async {
    // We want accounts that can pay (Assets/Banks/Cash)
    // Using Postgrest syntax for IN filter if supported by wrapper, or just fetching all assets
    // Attempting to fetch all active accounts and filter in memory if wrapper is restrictive,
    // but assuming we can pass a where clause.
    // 'type' is usually 'asset', 'liability', etc. Bank/Cash are subtypes or categories?
    // Based on user prompt, we just want accounts.
    return await _db.select('accounts',
        where: 'type=in.(asset,bank,cash)', orderBy: 'code');
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
  Future<void> payVoucher(String voucherId) async {
    try {
      _setLoading(true);

      // Ensure status is pending if currently draft
      final voucherData = await _db.selectById('payroll_vouchers', voucherId);
      if (voucherData != null && voucherData['status'] == 'draft') {
        await _db.update('payroll_vouchers', voucherId, {'status': 'pending'});
      }

      await _db.rpc('pay_payroll_voucher', params: {
        'p_voucher_id': voucherId,
      });
    } catch (e) {
      _setError('Error paying voucher: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Deletes a draft voucher.
  Future<void> deleteVoucher(String id) async {
    try {
      await _db.delete('payroll_vouchers', id);
    } catch (e) {
      _setError('Error deleting voucher: $e');
      rethrow;
    }
  }
}
