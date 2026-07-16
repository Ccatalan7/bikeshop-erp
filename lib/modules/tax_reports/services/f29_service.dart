import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/f29_declaration.dart';
import '../../../shared/services/tenant_service.dart';

class F29Service extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _tenantService = TenantService();

  List<F29Declaration> _declarations = [];
  bool _isLoading = false;
  String? _error;

  List<F29Declaration> get declarations => _declarations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all F29 declarations for current tenant
  Future<void> loadDeclarations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant found');
      }

      final response = await _supabase
          .from('f29_declarations')
          .select()
          .eq('tenant_id', tenantId)
          .order('period_year', ascending: false)
          .order('period_month', ascending: false);

      _declarations = (response as List)
          .map((json) => F29Declaration.fromJson(json))
          .toList();
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error loading F29 declarations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get F29 for specific period
  Future<F29Declaration?> getDeclarationForPeriod(
    int year,
    int month,
  ) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return null;

      final response = await _supabase
          .from('f29_declarations')
          .select()
          .eq('tenant_id', tenantId)
          .eq('period_year', year)
          .eq('period_month', month)
          .maybeSingle();

      if (response == null) return null;

      return F29Declaration.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error getting F29 for period $month/$year: $e');
      return null;
    }
  }

  /// Auto-generate F29 from accounting data
  Future<F29Declaration?> generateFromAccounting(
    int year,
    int month,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant found');
      }

      debugPrint('🔄 Auto-generating F29 for $month/$year...');

      final response = await _supabase.rpc(
        'generate_f29_from_accounting',
        params: {
          'p_tenant_id': tenantId,
          'p_year': year,
          'p_month': month,
        },
      );

      debugPrint('✅ F29 generated: ${response['period']}');
      debugPrint('   IVA Débito: \$${response['iva_debito']}');
      debugPrint('   IVA Crédito: \$${response['iva_credito']}');
      debugPrint('   IVA Neto: \$${response['iva_neto']}');
      debugPrint('   PPM: \$${response['ppm_monto']}');
      debugPrint('   Total a Pagar: \$${response['total_a_pagar']}');

      // Reload to get the newly generated F29
      await loadDeclarations();

      // Return the newly created F29
      return getDeclarationForPeriod(year, month);
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error generating F29: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update F29 status (draft → submitted → paid)
  Future<bool> updateStatus(
    String f29Id,
    String newStatus, {
    String? folioNumber,
    String? paymentReference,
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (newStatus == 'submitted') {
        updates['filed_at'] = DateTime.now().toIso8601String();
        if (folioNumber != null) {
          updates['folio_number'] = folioNumber;
        }
      }

      if (newStatus == 'paid') {
        updates['paid_at'] = DateTime.now().toIso8601String();
        if (paymentReference != null) {
          updates['payment_reference'] = paymentReference;
        }
      }

      await _supabase.from('f29_declarations').update(updates).eq('id', f29Id);

      debugPrint('✅ F29 status updated to $newStatus');

      // Reload declarations
      await loadDeclarations();

      return true;
    } catch (e) {
      debugPrint('❌ Error updating F29 status: $e');
      return false;
    }
  }

  /// Update F29 notes
  Future<bool> updateNotes(String f29Id, String notes) async {
    try {
      await _supabase.from('f29_declarations').update({
        'notes': notes,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', f29Id);

      // Reload declarations
      await loadDeclarations();

      return true;
    } catch (e) {
      debugPrint('❌ Error updating F29 notes: $e');
      return false;
    }
  }

  /// Delete F29 declaration (only if draft)
  Future<bool> deleteDeclaration(String f29Id) async {
    try {
      // Check status first
      final f29 = _declarations.firstWhere((d) => d.id == f29Id);
      if (!f29.isDraft) {
        throw Exception('Cannot delete F29 that is already submitted or paid');
      }

      await _supabase.from('f29_declarations').delete().eq('id', f29Id);

      debugPrint('✅ F29 deleted');

      // Reload declarations
      await loadDeclarations();

      return true;
    } catch (e) {
      debugPrint('❌ Error deleting F29: $e');
      _error = e.toString();
      return false;
    }
  }

  /// Get summary for multiple periods (for charts/reports)
  Future<List<Map<String, dynamic>>> getSummaryByPeriod(
    int startYear,
    int startMonth,
    int endYear,
    int endMonth,
  ) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return [];

      final response = await _supabase
          .from('f29_declarations')
          .select(
              'period_year, period_month, iva_neto, ppm_monto, total_a_pagar, total_a_favor')
          .eq('tenant_id', tenantId)
          .gte('period_year', startYear)
          .lte('period_year', endYear)
          .order('period_year')
          .order('period_month');

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Error getting F29 summary: $e');
      return [];
    }
  }

  /// Check if F29 exists for current period
  Future<bool> existsForCurrentPeriod() async {
    final now = DateTime.now();
    final f29 = await getDeclarationForPeriod(now.year, now.month);
    return f29 != null;
  }

  /// Get pending F29 declarations (draft status)
  List<F29Declaration> get pendingDeclarations {
    return _declarations.where((d) => d.isDraft).toList();
  }

  /// Get overdue F29 declarations (due date passed, not paid)
  List<F29Declaration> get overdueDeclarations {
    final now = DateTime.now();
    return _declarations
        .where((d) =>
            !d.isPaid &&
            d.dueDate != null &&
            d.dueDate!.isBefore(now) &&
            d.hasDebt)
        .toList();
  }

  /// Calculate total debt (unpaid F29s)
  double get totalDebt {
    return _declarations
        .where((d) => !d.isPaid && d.hasDebt)
        .fold(0.0, (sum, d) => sum + d.totalAPagar);
  }

  /// Calculate total credits (unused IVA credits)
  double get totalCredits {
    return _declarations
        .where((d) => d.hasCredit)
        .fold(0.0, (sum, d) => sum + d.totalAFavor);
  }
}
