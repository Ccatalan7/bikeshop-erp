import 'package:flutter/foundation.dart';
import '../models/spreadsheet_model.dart';

/// Evaluates formulas in spreadsheet cells.
///
/// Supports:
/// - Arithmetic: =A1+B1*2, =10/3-1
/// - Functions: SUM, AVERAGE, MIN, MAX, COUNT, IF
/// - Cell references: A1, B10, AA1
/// - Ranges: A1:A10, B2:D5
class FormulaEngine {
  /// All cell data keyed by "row,col"
  final Map<String, CellData> _cells;

  FormulaEngine(this._cells);

  /// Evaluate a formula string (must start with '=').
  /// Returns the display string.
  String evaluate(String formula, int selfRow, int selfCol) {
    try {
      if (!formula.startsWith('=')) return formula;
      final expr = formula.substring(1).trim();
      if (expr.isEmpty) return '';

      final result = _evalExpression(expr, selfRow, selfCol);
      if (result is double) {
        // Show as integer if whole number
        if (result == result.roundToDouble() && result.abs() < 1e15) {
          return result.toInt().toString();
        }
        return result.toStringAsFixed(2);
      }
      return result.toString();
    } catch (e) {
      debugPrint('Formula error: $e');
      return '#ERROR';
    }
  }

  /// Recalculate all formula cells. Returns list of changed cell keys.
  List<String> recalculateAll() {
    final changed = <String>[];
    for (final entry in _cells.entries) {
      final cell = entry.value;
      if (cell.isFormula) {
        final parts = entry.key.split(',');
        final row = int.parse(parts[0]);
        final col = int.parse(parts[1]);
        final newDisplay = evaluate(cell.rawValue, row, col);
        if (newDisplay != cell.displayValue) {
          cell.displayValue = newDisplay;
          cell.dirty = true;
          changed.add(entry.key);
        }
      }
    }
    return changed;
  }

  // ══════════════════════════════════════════════════════════════════
  // EXPRESSION PARSER
  // ══════════════════════════════════════════════════════════════════

  dynamic _evalExpression(String expr, int selfRow, int selfCol) {
    // Try to match function calls: FUNC(args)
    final funcMatch = RegExp(r'^([A-Z]+)\((.+)\)$', caseSensitive: false)
        .firstMatch(expr.trim());
    if (funcMatch != null) {
      final funcName = funcMatch.group(1)!.toUpperCase();
      final argsStr = funcMatch.group(2)!;
      return _evalFunction(funcName, argsStr, selfRow, selfCol);
    }

    // Try arithmetic expression
    return _evalArithmetic(expr, selfRow, selfCol);
  }

  double _evalFunction(String name, String argsStr, int selfRow, int selfCol) {
    final values = _resolveArgs(argsStr, selfRow, selfCol);

    switch (name) {
      case 'SUM':
        return values.fold(0.0, (sum, v) => sum + v);
      case 'AVERAGE':
      case 'PROMEDIO':
        if (values.isEmpty) return 0;
        return values.fold(0.0, (sum, v) => sum + v) / values.length;
      case 'MIN':
        if (values.isEmpty) return 0;
        return values.reduce((a, b) => a < b ? a : b);
      case 'MAX':
        if (values.isEmpty) return 0;
        return values.reduce((a, b) => a > b ? a : b);
      case 'COUNT':
      case 'CONTAR':
        return values.length.toDouble();
      case 'IF':
      case 'SI':
        return _evalIf(argsStr, selfRow, selfCol);
      default:
        throw Exception('Unknown function: $name');
    }
  }

  double _evalIf(String argsStr, int selfRow, int selfCol) {
    // IF(condition, value_if_true, value_if_false)
    final parts = _splitTopLevelCommas(argsStr);
    if (parts.length < 3) throw Exception('IF requires 3 arguments');

    final condition = _evalArithmetic(parts[0].trim(), selfRow, selfCol);
    if (condition != 0) {
      return _evalArithmetic(parts[1].trim(), selfRow, selfCol);
    } else {
      return _evalArithmetic(parts[2].trim(), selfRow, selfCol);
    }
  }

  /// Split by commas that are not inside parentheses.
  List<String> _splitTopLevelCommas(String s) {
    final parts = <String>[];
    int depth = 0;
    int start = 0;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '(') depth++;
      if (s[i] == ')') depth--;
      if (s[i] == ',' && depth == 0) {
        parts.add(s.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(s.substring(start));
    return parts;
  }

  /// Resolve function arguments: can be ranges (A1:A10), cell refs, or numbers.
  List<double> _resolveArgs(String argsStr, int selfRow, int selfCol) {
    final values = <double>[];
    final parts = _splitTopLevelCommas(argsStr);

    for (final part in parts) {
      final trimmed = part.trim();

      // Range: A1:B10
      final rangeMatch =
          RegExp(r'^([A-Z]+)(\d+):([A-Z]+)(\d+)$', caseSensitive: false)
              .firstMatch(trimmed);
      if (rangeMatch != null) {
        final startCol =
            CellModel.letterToCol(rangeMatch.group(1)!.toUpperCase());
        final startRow = int.parse(rangeMatch.group(2)!) - 1;
        final endCol =
            CellModel.letterToCol(rangeMatch.group(3)!.toUpperCase());
        final endRow = int.parse(rangeMatch.group(4)!) - 1;

        for (int r = startRow; r <= endRow; r++) {
          for (int c = startCol; c <= endCol; c++) {
            values.add(_getCellNumericValue(r, c));
          }
        }
        continue;
      }

      // Single cell reference: A1
      final cellMatch =
          RegExp(r'^([A-Z]+)(\d+)$', caseSensitive: false).firstMatch(trimmed);
      if (cellMatch != null) {
        final col = CellModel.letterToCol(cellMatch.group(1)!.toUpperCase());
        final row = int.parse(cellMatch.group(2)!) - 1;
        values.add(_getCellNumericValue(row, col));
        continue;
      }

      // Literal number
      final num = double.tryParse(trimmed);
      if (num != null) {
        values.add(num);
        continue;
      }

      // Nested function
      final funcMatch = RegExp(r'^([A-Z]+)\((.+)\)$', caseSensitive: false)
          .firstMatch(trimmed);
      if (funcMatch != null) {
        values.add(_evalFunction(funcMatch.group(1)!.toUpperCase(),
            funcMatch.group(2)!, selfRow, selfCol));
        continue;
      }
    }
    return values;
  }

  /// Simple arithmetic parser supporting +, -, *, / and cell references.
  double _evalArithmetic(String expr, int selfRow, int selfCol) {
    final trimmed = expr.trim();

    // Check for comparison operators for IF conditions
    for (final op in ['>=', '<=', '!=', '>', '<', '==']) {
      final idx = trimmed.indexOf(op);
      if (idx > 0) {
        final left =
            _evalArithmetic(trimmed.substring(0, idx), selfRow, selfCol);
        final right = _evalArithmetic(
            trimmed.substring(idx + op.length), selfRow, selfCol);
        switch (op) {
          case '>':
            return left > right ? 1 : 0;
          case '<':
            return left < right ? 1 : 0;
          case '>=':
            return left >= right ? 1 : 0;
          case '<=':
            return left <= right ? 1 : 0;
          case '==':
            return left == right ? 1 : 0;
          case '!=':
            return left != right ? 1 : 0;
        }
      }
    }

    // Handle addition/subtraction (lowest precedence)
    // Find the last + or - that is not inside parentheses
    int depth = 0;
    int lastAddSub = -1;
    for (int i = trimmed.length - 1; i >= 0; i--) {
      if (trimmed[i] == ')') depth++;
      if (trimmed[i] == '(') depth--;
      if (depth == 0 && (trimmed[i] == '+' || trimmed[i] == '-') && i > 0) {
        lastAddSub = i;
        break;
      }
    }
    if (lastAddSub > 0) {
      final left =
          _evalArithmetic(trimmed.substring(0, lastAddSub), selfRow, selfCol);
      final op = trimmed[lastAddSub];
      final right =
          _evalArithmetic(trimmed.substring(lastAddSub + 1), selfRow, selfCol);
      return op == '+' ? left + right : left - right;
    }

    // Handle multiplication/division
    depth = 0;
    int lastMulDiv = -1;
    for (int i = trimmed.length - 1; i >= 0; i--) {
      if (trimmed[i] == ')') depth++;
      if (trimmed[i] == '(') depth--;
      if (depth == 0 && (trimmed[i] == '*' || trimmed[i] == '/') && i > 0) {
        lastMulDiv = i;
        break;
      }
    }
    if (lastMulDiv > 0) {
      final left =
          _evalArithmetic(trimmed.substring(0, lastMulDiv), selfRow, selfCol);
      final op = trimmed[lastMulDiv];
      final right =
          _evalArithmetic(trimmed.substring(lastMulDiv + 1), selfRow, selfCol);
      if (op == '/') {
        if (right == 0) throw Exception('Division by zero');
        return left / right;
      }
      return left * right;
    }

    // Parentheses
    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      return _evalArithmetic(
          trimmed.substring(1, trimmed.length - 1), selfRow, selfCol);
    }

    // Function call inside arithmetic
    final funcMatch =
        RegExp(r'^([A-Z]+)\((.+)\)$', caseSensitive: false).firstMatch(trimmed);
    if (funcMatch != null) {
      return _evalFunction(funcMatch.group(1)!.toUpperCase(),
          funcMatch.group(2)!, selfRow, selfCol);
    }

    // Cell reference
    final cellMatch =
        RegExp(r'^([A-Z]+)(\d+)$', caseSensitive: false).firstMatch(trimmed);
    if (cellMatch != null) {
      final col = CellModel.letterToCol(cellMatch.group(1)!.toUpperCase());
      final row = int.parse(cellMatch.group(2)!) - 1;
      return _getCellNumericValue(row, col);
    }

    // Literal number
    final num = double.tryParse(trimmed);
    if (num != null) return num;

    throw Exception('Cannot parse: $trimmed');
  }

  double _getCellNumericValue(int row, int col) {
    final key = '$row,$col';
    final cell = _cells[key];
    if (cell == null || cell.isEmpty) return 0;

    // Use display value for formulas, raw value for numbers
    final val = cell.isFormula ? cell.displayValue : cell.rawValue;
    return double.tryParse(val) ?? 0;
  }
}
