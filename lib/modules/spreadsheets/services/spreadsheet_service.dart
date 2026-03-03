import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/spreadsheet_model.dart';

/// Service for CRUD operations on spreadsheets and their cells.
class SpreadsheetService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  List<SpreadsheetModel> _spreadsheets = [];

  List<SpreadsheetModel> get spreadsheets => _spreadsheets;

  // ══════════════════════════════════════════════════════════════════
  // SPREADSHEET CRUD
  // ══════════════════════════════════════════════════════════════════

  Future<void> fetchSpreadsheets() async {
    try {
      final data = await _supabase
          .from('spreadsheets')
          .select()
          .order('updated_at', ascending: false);

      _spreadsheets =
          (data as List).map((e) => SpreadsheetModel.fromJson(e)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching spreadsheets: $e');
    }
  }

  Future<SpreadsheetModel> createSpreadsheet({String? name}) async {
    final data = await _supabase
        .from('spreadsheets')
        .insert({
          if (name != null) 'name': name,
        })
        .select()
        .single();

    final sheet = SpreadsheetModel.fromJson(data);
    _spreadsheets.insert(0, sheet);
    notifyListeners();
    return sheet;
  }

  Future<void> renameSpreadsheet(String id, String newName) async {
    await _supabase.from('spreadsheets').update({'name': newName}).eq('id', id);

    final idx = _spreadsheets.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      _spreadsheets[idx] = _spreadsheets[idx].copyWith(name: newName);
      notifyListeners();
    }
  }

  Future<void> deleteSpreadsheet(String id) async {
    await _supabase.from('spreadsheets').delete().eq('id', id);
    _spreadsheets.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════
  // CELL OPERATIONS
  // ══════════════════════════════════════════════════════════════════

  /// Load all cells for a given spreadsheet.
  Future<List<CellModel>> loadCells(String spreadsheetId) async {
    try {
      final data = await _supabase
          .from('spreadsheet_cells')
          .select()
          .eq('spreadsheet_id', spreadsheetId);

      return (data as List).map((e) => CellModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error loading cells: $e');
      return [];
    }
  }

  /// Batch upsert changed cells. Uses ON CONFLICT on (spreadsheet_id, row_index, col_index).
  Future<void> saveCells(
      String spreadsheetId, Map<String, CellData> dirtyCells) async {
    if (dirtyCells.isEmpty) return;

    final rows = <Map<String, dynamic>>[];
    for (final entry in dirtyCells.entries) {
      final parts = entry.key.split(',');
      final row = int.parse(parts[0]);
      final col = int.parse(parts[1]);
      final cell = entry.value;

      if (cell.isEmpty) {
        // Delete empty cells instead of saving them
        continue;
      }

      rows.add({
        'spreadsheet_id': spreadsheetId,
        'row_index': row,
        'col_index': col,
        'raw_value': cell.rawValue,
        'display_value': cell.displayValue,
        'cell_type': cell.cellType,
        'bold': cell.bold,
        'italic': cell.italic,
        'text_align': cell.textAlign,
      });
    }

    try {
      if (rows.isNotEmpty) {
        await _supabase.from('spreadsheet_cells').upsert(
              rows,
              onConflict: 'spreadsheet_id,row_index,col_index',
            );
      }

      // Delete empty cells
      for (final entry in dirtyCells.entries) {
        if (entry.value.isEmpty) {
          final parts = entry.key.split(',');
          final row = int.parse(parts[0]);
          final col = int.parse(parts[1]);
          await _supabase
              .from('spreadsheet_cells')
              .delete()
              .eq('spreadsheet_id', spreadsheetId)
              .eq('row_index', row)
              .eq('col_index', col);
        }
      }

      // Mark all as clean
      for (final cell in dirtyCells.values) {
        cell.dirty = false;
      }

      debugPrint('Saved ${rows.length} cells');
    } catch (e) {
      debugPrint('Error saving cells: $e');
    }
  }
}
