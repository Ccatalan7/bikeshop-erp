import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/spreadsheet_model.dart';

/// Persistence boundary used by spreadsheet UI surfaces.
///
/// Keeping this contract separate from the Supabase implementation allows
/// editor tests to use an in-memory fake without changing production callers.
abstract interface class SpreadsheetStore {
  List<SpreadsheetModel> get spreadsheets;

  Future<void> fetchSpreadsheets();

  Future<SpreadsheetModel> createSpreadsheet({
    String? name,
    Map<String, dynamic>? workbookData,
    int? rowCount,
    int? colCount,
  });

  Future<void> renameSpreadsheet(String id, String newName);

  Future<void> updateSpreadsheetMetadata(
    String id, {
    String? name,
    int? rowCount,
    int? colCount,
  });

  Future<void> saveWorkbookData(
    String id,
    Map<String, dynamic> data,
  );

  Future<void> deleteSpreadsheet(String id);

  Future<List<CellModel>> loadCells(String spreadsheetId);

  Future<void> saveCells(
    String spreadsheetId,
    Map<String, CellData> dirtyCells,
  );
}

/// The deployed database predates full-workbook snapshot persistence.
///
/// This is deliberately distinct from a transport failure: reconnecting or
/// repeatedly retrying cannot make the missing column appear.
class SpreadsheetSnapshotSchemaException implements Exception {
  const SpreadsheetSnapshotSchemaException(this.cause);

  final PostgrestException cause;

  @override
  String toString() =>
      'SpreadsheetSnapshotSchemaException(${cause.message}, ${cause.code})';
}

/// Service for CRUD operations on spreadsheets and their cells.
class SpreadsheetService extends ChangeNotifier implements SpreadsheetStore {
  SpreadsheetService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  static const _maxDeleteCoordinatesPerRequest = 100;

  final SupabaseClient _supabase;
  List<SpreadsheetModel> _spreadsheets = [];

  @override
  List<SpreadsheetModel> get spreadsheets => _spreadsheets;

  // ══════════════════════════════════════════════════════════════════
  // SPREADSHEET CRUD
  // ══════════════════════════════════════════════════════════════════

  @override
  Future<void> fetchSpreadsheets() async {
    try {
      final data = await _supabase
          .from('spreadsheets')
          .select()
          .order('updated_at', ascending: false);

      _spreadsheets =
          (data as List).map((e) => SpreadsheetModel.fromJson(e)).toList();
      notifyListeners();
    } catch (error) {
      // A failed fetch is not an empty spreadsheet list. Let the caller keep
      // its current state and decide how to surface or retry the failure.
      debugPrint('Error fetching spreadsheets: $error');
      rethrow;
    }
  }

  @override
  Future<SpreadsheetModel> createSpreadsheet({
    String? name,
    Map<String, dynamic>? workbookData,
    int? rowCount,
    int? colCount,
  }) async {
    final id = const Uuid().v4();
    final trimmedName = name?.trim();
    Map<String, dynamic>? normalizedWorkbook;
    if (workbookData != null) {
      normalizedWorkbook = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(workbookData)) as Map,
      )
        ..['id'] = id
        ..['name'] = trimmedName?.isNotEmpty == true
            ? trimmedName
            : 'Planilla sin título';
    }
    final data = await _supabase
        .from('spreadsheets')
        .insert({
          'id': id,
          if (trimmedName?.isNotEmpty == true) 'name': trimmedName,
          if (rowCount != null) 'row_count': rowCount,
          if (colCount != null) 'col_count': colCount,
          if (normalizedWorkbook != null) 'workbook_data': normalizedWorkbook,
        })
        .select()
        .single();

    final sheet = SpreadsheetModel.fromJson(data);
    _spreadsheets.insert(0, sheet);
    notifyListeners();
    return sheet;
  }

  @override
  Future<void> renameSpreadsheet(String id, String newName) async {
    final updatedAt = DateTime.now().toUtc();
    await _supabase.from('spreadsheets').update({
      'name': newName,
      'updated_at': updatedAt.toIso8601String(),
    }).eq('id', id);

    final idx = _spreadsheets.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      final updated = _spreadsheets[idx].copyWith(
        name: newName,
        updatedAt: updatedAt,
      );
      _spreadsheets
        ..removeAt(idx)
        ..insert(0, updated);
      notifyListeners();
    }
  }

  @override
  Future<void> updateSpreadsheetMetadata(
    String id, {
    String? name,
    int? rowCount,
    int? colCount,
  }) async {
    if (name == null && rowCount == null && colCount == null) return;
    final updatedAt = DateTime.now().toUtc();
    final updates = <String, dynamic>{
      if (name != null) 'name': name,
      if (rowCount != null) 'row_count': rowCount,
      if (colCount != null) 'col_count': colCount,
      'updated_at': updatedAt.toIso8601String(),
    };
    await _supabase.from('spreadsheets').update(updates).eq('id', id);

    final idx = _spreadsheets.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      final updated = _spreadsheets[idx].copyWith(
        name: name ?? _spreadsheets[idx].name,
        rowCount: rowCount ?? _spreadsheets[idx].rowCount,
        colCount: colCount ?? _spreadsheets[idx].colCount,
        updatedAt: updatedAt,
      );
      _spreadsheets
        ..removeAt(idx)
        ..insert(0, updated);
      notifyListeners();
    }
  }

  @override
  Future<void> saveWorkbookData(
    String id,
    Map<String, dynamic> data,
  ) async {
    final workbookData = Map<String, dynamic>.from(data);
    final updatedAt = DateTime.now().toUtc();
    try {
      await _supabase.from('spreadsheets').update({
        'workbook_data': workbookData,
        'updated_at': updatedAt.toIso8601String(),
      }).eq('id', id);
    } on PostgrestException catch (error) {
      if (_isMissingWorkbookSnapshotColumn(error)) {
        throw SpreadsheetSnapshotSchemaException(error);
      }
      rethrow;
    }

    final idx = _spreadsheets.indexWhere((sheet) => sheet.id == id);
    if (idx >= 0) {
      final updated = _spreadsheets[idx].copyWith(
        workbookData: workbookData,
        updatedAt: updatedAt,
      );
      _spreadsheets
        ..removeAt(idx)
        ..insert(0, updated);
      notifyListeners();
    }
  }

  bool _isMissingWorkbookSnapshotColumn(PostgrestException error) {
    final diagnostic = <Object?>[
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().join(' ').toLowerCase();
    final identifiesColumn = diagnostic.contains('workbook_data');
    final identifiesSchemaMismatch = error.code == 'PGRST204' ||
        error.code == '42703' ||
        diagnostic.contains('schema cache') ||
        diagnostic.contains('column');
    return identifiesColumn && identifiesSchemaMismatch;
  }

  @override
  Future<void> deleteSpreadsheet(String id) async {
    await _supabase.from('spreadsheets').delete().eq('id', id);
    _spreadsheets.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════
  // CELL OPERATIONS
  // ══════════════════════════════════════════════════════════════════

  /// Load all cells for a given spreadsheet.
  @override
  Future<List<CellModel>> loadCells(String spreadsheetId) async {
    try {
      final data = await _supabase
          .from('spreadsheet_cells')
          .select()
          .eq('spreadsheet_id', spreadsheetId);

      return (data as List).map((e) => CellModel.fromJson(e)).toList();
    } catch (error) {
      // Returning [] here would make a transport/auth failure look like a
      // legitimately empty sheet and could cause subsequent destructive saves.
      debugPrint('Error loading cells: $error');
      rethrow;
    }
  }

  /// Batch upsert changed cells.
  ///
  /// Uses ON CONFLICT on (spreadsheet_id, row_index, col_index). Empty cells
  /// are deleted in scoped batches. The operations are idempotent but are not
  /// one database transaction, so any partial failure is propagated and every
  /// caller-owned cell stays dirty for a safe retry.
  @override
  Future<void> saveCells(
    String spreadsheetId,
    Map<String, CellData> dirtyCells,
  ) async {
    if (dirtyCells.isEmpty) return;

    try {
      // Snapshot persisted fields before the first await. This prevents an edit
      // made during a save from being incorrectly marked clean afterward.
      final plans = dirtyCells.entries.map(_CellSavePlan.fromEntry).toList();
      final rows = plans
          .where((plan) => !plan.isEmpty)
          .map((plan) => plan.toRow(spreadsheetId))
          .toList();
      final emptyPlans = plans.where((plan) => plan.isEmpty).toList();

      if (rows.isNotEmpty) {
        await _supabase.from('spreadsheet_cells').upsert(
              rows,
              onConflict: 'spreadsheet_id,row_index,col_index',
            );
      }

      // PostgREST supports nested `or(and(...), and(...))` filters. Keep the
      // spreadsheet equality outside the OR so a malformed/changed coordinate
      // list can never broaden deletion beyond the requested sheet. Batching
      // also avoids one HTTP request per cleared cell without creating huge
      // request URLs.
      for (var start = 0;
          start < emptyPlans.length;
          start += _maxDeleteCoordinatesPerRequest) {
        final end = (start + _maxDeleteCoordinatesPerRequest)
            .clamp(0, emptyPlans.length);
        final batch = emptyPlans.sublist(start, end);
        final coordinateFilter = batch
            .map(
              (plan) =>
                  'and(row_index.eq.${plan.row},col_index.eq.${plan.col})',
            )
            .join(',');

        await _supabase
            .from('spreadsheet_cells')
            .delete()
            .eq('spreadsheet_id', spreadsheetId)
            .or(coordinateFilter);
      }

      // Cell writes are workbook edits too. Keep the dashboard's recency and
      // sorting accurate even when only cell contents or formatting changed.
      final updatedAt = DateTime.now().toUtc();
      await _supabase.from('spreadsheets').update({
        'updated_at': updatedAt.toIso8601String(),
      }).eq('id', spreadsheetId);

      final sheetIndex =
          _spreadsheets.indexWhere((sheet) => sheet.id == spreadsheetId);
      if (sheetIndex >= 0) {
        final updated =
            _spreadsheets[sheetIndex].copyWith(updatedAt: updatedAt);
        _spreadsheets
          ..removeAt(sheetIndex)
          ..insert(0, updated);
        notifyListeners();
      }

      // This is deliberately after every awaited write. If any batch fails,
      // the exception escapes and all cells remain dirty for an idempotent
      // retry. Cells edited during the save also stay dirty.
      for (final plan in plans) {
        if (plan.matchesCurrentCell) {
          plan.cell.dirty = false;
        }
      }

      debugPrint(
        'Saved ${rows.length} cells and deleted ${emptyPlans.length} empty cells',
      );
    } catch (error) {
      debugPrint('Error saving cells: $error');
      rethrow;
    }
  }
}

class _CellSavePlan {
  _CellSavePlan._({
    required this.cell,
    required this.row,
    required this.col,
    required this.rawValue,
    required this.displayValue,
    required this.cellType,
    required this.bold,
    required this.italic,
    required this.textAlign,
  });

  factory _CellSavePlan.fromEntry(MapEntry<String, CellData> entry) {
    final parts = entry.key.split(',');
    if (parts.length != 2) {
      throw FormatException(
        'Invalid cell coordinate "${entry.key}"; expected "row,col".',
      );
    }

    final row = int.parse(parts[0]);
    final col = int.parse(parts[1]);
    if (row < 0 || col < 0) {
      throw FormatException(
        'Invalid cell coordinate "${entry.key}"; indexes must be non-negative.',
      );
    }

    final cell = entry.value;
    return _CellSavePlan._(
      cell: cell,
      row: row,
      col: col,
      rawValue: cell.rawValue,
      displayValue: cell.displayValue,
      cellType: cell.cellType,
      bold: cell.bold,
      italic: cell.italic,
      textAlign: cell.textAlign,
    );
  }

  final CellData cell;
  final int row;
  final int col;
  final String rawValue;
  final String displayValue;
  final String cellType;
  final bool bold;
  final bool italic;
  final String textAlign;

  bool get isEmpty => rawValue.isEmpty;

  bool get matchesCurrentCell =>
      cell.rawValue == rawValue &&
      cell.displayValue == displayValue &&
      cell.cellType == cellType &&
      cell.bold == bold &&
      cell.italic == italic &&
      cell.textAlign == textAlign;

  Map<String, dynamic> toRow(String spreadsheetId) => {
        'spreadsheet_id': spreadsheetId,
        'row_index': row,
        'col_index': col,
        'raw_value': rawValue,
        'display_value': displayValue,
        'cell_type': cellType,
        'bold': bold,
        'italic': italic,
        'text_align': textAlign,
      };
}
