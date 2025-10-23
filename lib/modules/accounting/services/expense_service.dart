import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/database_service.dart';
import '../models/expense.dart';
import '../models/expense_attachment.dart';
import '../models/expense_category.dart';
import '../models/expense_line.dart';
import '../models/expense_payment.dart';

class ExpenseService extends ChangeNotifier {
  ExpenseService(this._databaseService);

  final DatabaseService _databaseService;
  final SupabaseClient _client = Supabase.instance.client;

  bool _isLoading = false;
  String? _error;
  bool _expensesLoaded = false;
  bool _categoriesLoaded = false;

  List<Expense> _expenses = const [];
  List<ExpenseCategory> _categories = const [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Expense> get expenses => _expenses;
  List<ExpenseCategory> get categories => _categories;

  Future<List<Expense>> fetchExpenses({bool forceRefresh = false}) async {
    if (_expensesLoaded && !forceRefresh) {
      return _expenses;
    }

    _setLoading(true);
    try {
      final rows = await _databaseService.select(
        'expenses',
        orderBy: 'issue_date',
        descending: true,
      );

      _expenses = rows.map(Expense.fromJson).toList();
      _expensesLoaded = true;
      _setLoading(false);
      return _expenses;
    } catch (e) {
      _registerError('No se pudieron cargar los gastos: $e');
      rethrow;
    }
  }

  Future<Expense?> getExpense(String id, {bool forceRefresh = false}) async {
    if (!_expensesLoaded || forceRefresh) {
      await fetchExpenses(forceRefresh: forceRefresh);
    }

    try {
      final cached = _expenses.firstWhere(
        (expense) => expense.id == id,
        orElse: () =>
            Expense(expenseNumber: '', issueDate: DateTime.now()),
      );
      if (cached.id == id && !forceRefresh) {
        return await _hydrateExpense(cached);
      }
    } catch (_) {
      // ignore cache miss
    }

    final base = await _databaseService.selectById('expenses', id);
    if (base == null) return null;

    final expense = Expense.fromJson(base);
    return _hydrateExpense(expense);
  }

  Future<ExpenseCategory> saveCategory(ExpenseCategory category) async {
    try {
      if (category.id.isEmpty) {
        final inserted = await _databaseService.insert(
          'expense_categories',
          category.toJson()..remove('id'),
        );
        final created = ExpenseCategory.fromJson(inserted);
        await fetchCategories(forceRefresh: true);
        notifyListeners();
        return created;
      } else {
        final payload = category.toJson();
        payload.remove('created_at');
        final updated = await _databaseService.update(
          'expense_categories',
          category.id,
          payload,
        );
        final saved = ExpenseCategory.fromJson(updated);
        await fetchCategories(forceRefresh: true);
        notifyListeners();
        return saved;
      }
    } catch (e) {
      throw Exception('No se pudo guardar la categoría: $e');
    }
  }

  Future<List<ExpenseCategory>> fetchCategories({bool forceRefresh = false}) async {
    if (_categoriesLoaded && !forceRefresh) {
      return _categories;
    }

    try {
      final rows = await _databaseService.select(
        'expense_categories',
        orderBy: 'name',
      );
      _categories = rows.map(ExpenseCategory.fromJson).toList();
      _categoriesLoaded = true;
      notifyListeners();
      return _categories;
    } catch (e) {
      throw Exception('No se pudieron cargar las categorías de gasto: $e');
    }
  }

  Future<Expense> saveExpense(Expense expense) async {
    try {
      final payload = expense.toDatabasePayload();
      Map<String, dynamic> stored;

      if (expense.id == null || expense.id!.isEmpty) {
        stored = await _databaseService.insert(
          'expenses',
          payload,
        );
      } else {
        payload.remove('created_at');
        stored = await _databaseService.update(
          'expenses',
          expense.id!,
          payload,
        );
      }

      final saved = Expense.fromJson(stored);
      await _syncExpenseLines(saved.id!, expense.lines);

      // Payments are handled via dedicated endpoints to maintain audit trail.
      // Attachments are managed separately as well.

      await fetchExpenses(forceRefresh: true);
      notifyListeners();

      return await _hydrateExpense(saved);
    } catch (e) {
      throw Exception('No se pudo guardar el gasto: $e');
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      await _databaseService.delete('expenses', id);
      await fetchExpenses(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo eliminar el gasto: $e');
    }
  }

  Future<Expense> postExpense(String id) async {
    try {
      final result = await _databaseService.update('expenses', id, {
        'posting_status': 'posted',
      });
      await fetchExpenses(forceRefresh: true);
      notifyListeners();
      return await _hydrateExpense(Expense.fromJson(result));
    } catch (e) {
      throw Exception('No se pudo contabilizar el gasto: $e');
    }
  }

  Future<Expense> revertExpenseToDraft(String id) async {
    try {
      final result = await _databaseService.update('expenses', id, {
        'posting_status': 'draft',
      });
      await fetchExpenses(forceRefresh: true);
      notifyListeners();
      return await _hydrateExpense(Expense.fromJson(result));
    } catch (e) {
      throw Exception('No se pudo mover el gasto a borrador: $e');
    }
  }

  Future<Expense> markExpensePaid(String id) async {
    try {
      final result = await _databaseService.update('expenses', id, {
        'payment_status': 'paid',
      });
      await fetchExpenses(forceRefresh: true);
      notifyListeners();
      return await _hydrateExpense(Expense.fromJson(result));
    } catch (e) {
      throw Exception('No se pudo marcar el gasto como pagado: $e');
    }
  }

  Future<ExpensePayment> createPayment(ExpensePayment payment) async {
    try {
      final payload = payment.toJson(includeIdentifier: false);
      final stored = await _databaseService.insert('expense_payments', payload);
      await fetchExpenses(forceRefresh: true);
      notifyListeners();
      return ExpensePayment.fromJson(stored);
    } catch (e) {
      throw Exception('No se pudo registrar el pago: $e');
    }
  }

  Future<void> deletePayment(String paymentId) async {
    try {
      await _databaseService.delete('expense_payments', paymentId);
      await fetchExpenses(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo eliminar el pago: $e');
    }
  }

  Future<void> attachDocument(ExpenseAttachment attachment) async {
    try {
      await _databaseService.insert(
        'expense_attachments',
        attachment.toJson(includeIdentifier: false),
      );
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo adjuntar el archivo: $e');
    }
  }

  Future<void> removeAttachment(String attachmentId) async {
    try {
      await _databaseService.delete('expense_attachments', attachmentId);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo eliminar el adjunto: $e');
    }
  }

  Future<Expense> _hydrateExpense(Expense expense) async {
    if (expense.id == null || expense.id!.isEmpty) return expense;

    final expenseId = expense.id!;

    final linesRaw = await _client
        .from('expense_lines')
        .select()
        .eq('expense_id', expenseId)
        .order('line_index')
        .order('created_at') as List<dynamic>;

    final paymentsRaw = await _client
        .from('expense_payments')
        .select()
        .eq('expense_id', expenseId)
        .order('payment_date', ascending: false) as List<dynamic>;

    final attachmentsRaw = await _client
        .from('expense_attachments')
        .select()
        .eq('expense_id', expenseId)
        .order('uploaded_at', ascending: false) as List<dynamic>;

    final category = expense.categoryId == null
        ? null
        : await _getCategory(expense.categoryId!);

    return expense.withDetails(
      lines: linesRaw
          .map((row) => ExpenseLine.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      payments: paymentsRaw
          .map((row) => ExpensePayment.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      attachments: attachmentsRaw
          .map((row) => ExpenseAttachment.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      category: category,
    );
  }

  Future<void> _syncExpenseLines(
    String expenseId,
    List<ExpenseLine> lines,
  ) async {
    final existingRaw = await _client
        .from('expense_lines')
        .select('id')
        .eq('expense_id', expenseId) as List<dynamic>;

    final existingIds = existingRaw
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();

    final incomingIds = <String>{};

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final payload = line
          .copyWith(expenseId: expenseId, lineIndex: i)
          .toJson();

      if (line.id == null || line.id!.isEmpty) {
        await _client.from('expense_lines').insert(payload);
      } else {
        incomingIds.add(line.id!);
        payload.remove('created_at');
    await _client
      .from('expense_lines')
      .update(payload)
      .eq('id', line.id!);
      }
    }

    final toDelete = existingIds.difference(incomingIds);
    if (toDelete.isNotEmpty) {
      await _client
          .from('expense_lines')
          .delete()
          .inFilter('id', toDelete.toList());
    }
  }

  Future<ExpenseCategory?> _getCategory(String id) async {
    if (!_categoriesLoaded) {
      await fetchCategories();
    }
    try {
      return _categories.firstWhere((category) => category.id == id);
    } catch (_) {
      final row = await _databaseService.selectById('expense_categories', id);
      if (row == null) return null;
      final category = ExpenseCategory.fromJson(row);
      _categories = [..._categories.where((c) => c.id != category.id), category];
      return category;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _registerError(String message) {
    _error = message;
    _isLoading = false;
    notifyListeners();
  }
}
