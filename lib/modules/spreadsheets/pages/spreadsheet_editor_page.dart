import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/spreadsheet_model.dart';
import '../services/formula_engine.dart';
import '../services/spreadsheet_service.dart';
import '../../../shared/widgets/main_layout.dart';

class SpreadsheetEditorPage extends StatefulWidget {
  final String spreadsheetId;
  const SpreadsheetEditorPage({super.key, required this.spreadsheetId});

  @override
  State<SpreadsheetEditorPage> createState() => _SpreadsheetEditorPageState();
}

class _SpreadsheetEditorPageState extends State<SpreadsheetEditorPage> {
  // Grid config
  static const int _defaultRows = 100;
  static const int _defaultCols = 26;
  static const double _cellWidth = 120;
  static const double _cellHeight = 32;
  static const double _headerWidth = 48;
  static const double _headerHeight = 32;

  // State
  SpreadsheetModel? _sheet;
  final Map<String, CellData> _cells = {};
  int _selectedRow = 0;
  int _selectedCol = 0;
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasUnsaved = false;

  Timer? _saveTimer;
  final TextEditingController _formulaBarController = TextEditingController();
  final TextEditingController _cellEditController = TextEditingController();
  final FocusNode _gridFocusNode = FocusNode();
  final FocusNode _cellEditFocusNode = FocusNode();
  final FocusNode _formulaBarFocusNode = FocusNode();
  final ScrollController _hScrollController = ScrollController();
  final ScrollController _vScrollController = ScrollController();

  late FormulaEngine _formulaEngine;

  @override
  void initState() {
    super.initState();
    _formulaEngine = FormulaEngine(_cells);
    _loadSpreadsheet();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveNow();
    _formulaBarController.dispose();
    _cellEditController.dispose();
    _gridFocusNode.dispose();
    _cellEditFocusNode.dispose();
    _formulaBarFocusNode.dispose();
    _hScrollController.dispose();
    _vScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSpreadsheet() async {
    final service = context.read<SpreadsheetService>();

    // Get sheet metadata
    await service.fetchSpreadsheets();
    final sheet = service.spreadsheets
        .where((s) => s.id == widget.spreadsheetId)
        .firstOrNull;

    if (sheet == null) {
      if (mounted) context.go('/tools/spreadsheets');
      return;
    }

    // Load cells
    final cellModels = await service.loadCells(widget.spreadsheetId);
    for (final cell in cellModels) {
      final key = '${cell.row},${cell.col}';
      _cells[key] = CellData(
        rawValue: cell.rawValue ?? '',
        displayValue: cell.displayValue ?? '',
        cellType: cell.cellType,
        bold: cell.bold,
        italic: cell.italic,
        textAlign: cell.textAlign,
      );
    }

    // Recalculate formula cells
    _formulaEngine.recalculateAll();

    if (mounted) {
      setState(() {
        _sheet = sheet;
        _isLoading = false;
      });
      _gridFocusNode.requestFocus();
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // CELL EDITING
  // ══════════════════════════════════════════════════════════════════

  CellData _getCell(int row, int col) {
    return _cells.putIfAbsent('$row,$col', () => CellData());
  }

  void _selectCell(int row, int col) {
    if (_isEditing) _commitEdit();
    setState(() {
      _selectedRow = row;
      _selectedCol = col;
      _isEditing = false;
      final cell = _getCell(row, col);
      _formulaBarController.text = cell.rawValue;
    });
    _gridFocusNode.requestFocus();
  }

  void _startEditing() {
    final cell = _getCell(_selectedRow, _selectedCol);
    setState(() {
      _isEditing = true;
      _cellEditController.text = cell.rawValue;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cellEditFocusNode.requestFocus();
      _cellEditController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _cellEditController.text.length,
      );
    });
  }

  void _commitEdit() {
    if (!_isEditing) return;
    final raw = _cellEditController.text;
    _setCellValue(_selectedRow, _selectedCol, raw);
    setState(() => _isEditing = false);
    _gridFocusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() => _isEditing = false);
    _gridFocusNode.requestFocus();
  }

  void _setCellValue(int row, int col, String raw) {
    final cell = _getCell(row, col);
    cell.rawValue = raw;
    cell.dirty = true;

    // Determine type and display value
    if (raw.startsWith('=')) {
      cell.cellType = 'formula';
      cell.displayValue = _formulaEngine.evaluate(raw, row, col);
    } else if (double.tryParse(raw.replaceAll(',', '.')) != null) {
      cell.cellType = 'number';
      cell.displayValue = raw;
    } else {
      cell.cellType = 'text';
      cell.displayValue = raw;
    }

    // Recalculate dependent formulas
    _formulaEngine.recalculateAll();

    _formulaBarController.text = raw;
    _hasUnsaved = true;
    _scheduleSave();
    setState(() {});
  }

  // ══════════════════════════════════════════════════════════════════
  // FORMULA BAR
  // ══════════════════════════════════════════════════════════════════

  void _onFormulaBarSubmitted(String value) {
    _setCellValue(_selectedRow, _selectedCol, value);
    _gridFocusNode.requestFocus();
  }

  // ══════════════════════════════════════════════════════════════════
  // SAVE
  // ══════════════════════════════════════════════════════════════════

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveNow);
  }

  Future<void> _saveNow() async {
    if (!_hasUnsaved) return;
    final dirty = Map.fromEntries(
      _cells.entries.where((e) => e.value.dirty),
    );
    if (dirty.isEmpty) {
      _hasUnsaved = false;
      return;
    }

    setState(() => _isSaving = true);
    await context
        .read<SpreadsheetService>()
        .saveCells(widget.spreadsheetId, dirty);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _hasUnsaved = false;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // KEYBOARD
  // ══════════════════════════════════════════════════════════════════

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // If editing, handle special keys
    if (_isEditing) {
      if (key == LogicalKeyboardKey.enter) {
        _commitEdit();
        _moveSelection(1, 0);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _cancelEdit();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.tab) {
        _commitEdit();
        _moveSelection(0, 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Navigation
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveSelection(0, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(0, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _moveSelection(0, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      _moveSelection(1, 0);
      return KeyEventResult.handled;
    }

    // Delete
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _setCellValue(_selectedRow, _selectedCol, '');
      return KeyEventResult.handled;
    }

    // F2 to edit
    if (key == LogicalKeyboardKey.f2) {
      _startEditing();
      return KeyEventResult.handled;
    }

    // Start typing to edit
    if (event.character != null &&
        event.character!.isNotEmpty &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      final cell = _getCell(_selectedRow, _selectedCol);
      setState(() {
        _isEditing = true;
        _cellEditController.text = event.character!;
        cell.rawValue = event.character!;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _cellEditFocusNode.requestFocus();
        _cellEditController.selection = TextSelection.collapsed(
          offset: _cellEditController.text.length,
        );
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _moveSelection(int dRow, int dCol) {
    setState(() {
      _selectedRow = (_selectedRow + dRow).clamp(0, _defaultRows - 1);
      _selectedCol = (_selectedCol + dCol).clamp(0, _defaultCols - 1);
      final cell = _getCell(_selectedRow, _selectedCol);
      _formulaBarController.text = cell.rawValue;
    });
    _ensureVisible();
  }

  void _ensureVisible() {
    // Scroll to keep selected cell visible
    final targetX = _headerWidth + _selectedCol * _cellWidth;
    final targetY = _headerHeight + _selectedRow * _cellHeight;
    final viewportWidth = _hScrollController.position.viewportDimension;
    final viewportHeight = _vScrollController.position.viewportDimension;

    if (targetX < _hScrollController.offset) {
      _hScrollController.jumpTo(targetX);
    } else if (targetX + _cellWidth >
        _hScrollController.offset + viewportWidth) {
      _hScrollController.jumpTo(targetX + _cellWidth - viewportWidth);
    }

    if (targetY < _vScrollController.offset) {
      _vScrollController.jumpTo(targetY);
    } else if (targetY + _cellHeight >
        _vScrollController.offset + viewportHeight) {
      _vScrollController.jumpTo(targetY + _cellHeight - viewportHeight);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MainLayout(
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final theme = Theme.of(context);
    final cellRef = '${CellModel.colToLetter(_selectedCol)}${_selectedRow + 1}';

    return MainLayout(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          children: [
            // ── Top bar ──
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: () {
                      _saveNow();
                      context.go('/tools/spreadsheets');
                    },
                    tooltip: 'Volver',
                  ),
                  const SizedBox(width: 8),
                  // Editable title
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: () async {
                        final ctrl =
                            TextEditingController(text: _sheet?.name ?? '');
                        final result = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Renombrar'),
                            content: TextField(
                              controller: ctrl,
                              autofocus: true,
                              onSubmitted: (v) => Navigator.of(ctx).pop(v),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(ctrl.text),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                        if (result != null && result.isNotEmpty && mounted) {
                          await context
                              .read<SpreadsheetService>()
                              .renameSpreadsheet(_sheet!.id!, result);
                          setState(
                              () => _sheet = _sheet!.copyWith(name: result));
                        }
                        ctrl.dispose();
                      },
                      child: Text(
                        _sheet?.name ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Save indicator
                  if (_isSaving)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_hasUnsaved)
                    Icon(Icons.cloud_upload_outlined,
                        size: 16, color: Colors.orange.shade600)
                  else
                    Icon(Icons.cloud_done_outlined,
                        size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 12),
                ],
              ),
            ),

            // ── Formula bar ──
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  // Cell reference badge
                  Container(
                    width: 60,
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.white,
                    ),
                    child: Text(
                      cellRef,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(width: 8),
                  // Formula input
                  Expanded(
                    child: TextField(
                      controller: _formulaBarController,
                      focusNode: _formulaBarFocusNode,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        hintText:
                            'Escribe un valor o fórmula (ej: =SUM(A1:A10))',
                        hintStyle: TextStyle(fontSize: 12),
                      ),
                      onSubmitted: _onFormulaBarSubmitted,
                    ),
                  ),
                ],
              ),
            ),

            // ── Spreadsheet grid ──
            Expanded(
              child: Focus(
                focusNode: _gridFocusNode,
                onKeyEvent: _handleKeyEvent,
                child: _buildGrid(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = _headerWidth + _defaultCols * _cellWidth;
        final totalHeight = _headerHeight + _defaultRows * _cellHeight;

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: true,
          ),
          child: Scrollbar(
            controller: _vScrollController,
            thumbVisibility: true,
            child: Scrollbar(
              controller: _hScrollController,
              thumbVisibility: true,
              notificationPredicate: (n) => n.depth == 1,
              child: SingleChildScrollView(
                controller: _vScrollController,
                child: SingleChildScrollView(
                  controller: _hScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    height: totalHeight,
                    child: CustomPaint(
                      painter: _SpreadsheetPainter(
                        cells: _cells,
                        selectedRow: _selectedRow,
                        selectedCol: _selectedCol,
                        rowCount: _defaultRows,
                        colCount: _defaultCols,
                        cellWidth: _cellWidth,
                        cellHeight: _cellHeight,
                        headerWidth: _headerWidth,
                        headerHeight: _headerHeight,
                        theme: theme,
                      ),
                      child: Stack(
                        children: [
                          // Click handler
                          GestureDetector(
                            onTapDown: (details) {
                              final x = details.localPosition.dx;
                              final y = details.localPosition.dy;
                              if (x < _headerWidth || y < _headerHeight) return;
                              final col =
                                  ((x - _headerWidth) / _cellWidth).floor();
                              final row =
                                  ((y - _headerHeight) / _cellHeight).floor();
                              if (row >= 0 &&
                                  row < _defaultRows &&
                                  col >= 0 &&
                                  col < _defaultCols) {
                                _selectCell(row, col);
                              }
                            },
                            onDoubleTapDown: (details) {
                              final x = details.localPosition.dx;
                              final y = details.localPosition.dy;
                              if (x < _headerWidth || y < _headerHeight) return;
                              final col =
                                  ((x - _headerWidth) / _cellWidth).floor();
                              final row =
                                  ((y - _headerHeight) / _cellHeight).floor();
                              if (row >= 0 &&
                                  row < _defaultRows &&
                                  col >= 0 &&
                                  col < _defaultCols) {
                                _selectCell(row, col);
                                _startEditing();
                              }
                            },
                          ),

                          // Inline cell editor
                          if (_isEditing)
                            Positioned(
                              left:
                                  _headerWidth + _selectedCol * _cellWidth + 1,
                              top: _headerHeight +
                                  _selectedRow * _cellHeight +
                                  1,
                              width: _cellWidth - 2,
                              height: _cellHeight - 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.blue.shade600,
                                    width: 2,
                                  ),
                                ),
                                child: TextField(
                                  controller: _cellEditController,
                                  focusNode: _cellEditFocusNode,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 6),
                                  ),
                                  onSubmitted: (_) {
                                    _commitEdit();
                                    _moveSelection(1, 0);
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — renders the entire grid efficiently
// ══════════════════════════════════════════════════════════════════
class _SpreadsheetPainter extends CustomPainter {
  final Map<String, CellData> cells;
  final int selectedRow;
  final int selectedCol;
  final int rowCount;
  final int colCount;
  final double cellWidth;
  final double cellHeight;
  final double headerWidth;
  final double headerHeight;
  final ThemeData theme;

  _SpreadsheetPainter({
    required this.cells,
    required this.selectedRow,
    required this.selectedCol,
    required this.rowCount,
    required this.colCount,
    required this.cellWidth,
    required this.cellHeight,
    required this.headerWidth,
    required this.headerHeight,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.5;
    final headerBg = Paint()..color = Colors.grey.shade100;
    final selectionPaint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final selectionHeaderBg = Paint()..color = Colors.blue.shade50;

    // ── Column headers ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, headerHeight),
      headerBg,
    );
    for (int c = 0; c < colCount; c++) {
      final x = headerWidth + c * cellWidth;
      // Highlight selected column header
      if (c == selectedCol) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, cellWidth, headerHeight),
          selectionHeaderBg,
        );
      }
      // Column letter
      final label = CellModel.colToLetter(c);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: c == selectedCol ? FontWeight.bold : FontWeight.w500,
            color:
                c == selectedCol ? Colors.blue.shade700 : Colors.grey.shade600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          x + (cellWidth - tp.width) / 2,
          (headerHeight - tp.height) / 2,
        ),
      );
      // Vertical line
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    // ── Row headers ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, headerWidth, size.height),
      headerBg,
    );
    for (int r = 0; r < rowCount; r++) {
      final y = headerHeight + r * cellHeight;
      // Highlight selected row header
      if (r == selectedRow) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, headerWidth, cellHeight),
          selectionHeaderBg,
        );
      }
      final label = '${r + 1}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: r == selectedRow ? FontWeight.bold : FontWeight.w500,
            color:
                r == selectedRow ? Colors.blue.shade700 : Colors.grey.shade600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (headerWidth - tp.width) / 2,
          y + (cellHeight - tp.height) / 2,
        ),
      );
      // Horizontal line
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // ── Top-left corner ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, headerWidth, headerHeight),
      headerBg,
    );

    // ── Cell values ──
    for (final entry in cells.entries) {
      final cell = entry.value;
      if (cell.isEmpty) continue;

      final parts = entry.key.split(',');
      final row = int.parse(parts[0]);
      final col = int.parse(parts[1]);
      if (row >= rowCount || col >= colCount) continue;

      final x = headerWidth + col * cellWidth;
      final y = headerHeight + row * cellHeight;

      final displayText = cell.isFormula ? cell.displayValue : cell.rawValue;

      TextAlign align;
      switch (cell.textAlign) {
        case 'center':
          align = TextAlign.center;
          break;
        case 'right':
          align = TextAlign.right;
          break;
        default:
          // Right-align numbers by default
          align = cell.cellType == 'number' ? TextAlign.right : TextAlign.left;
      }

      final tp = TextPainter(
        text: TextSpan(
          text: displayText,
          style: TextStyle(
            fontSize: 12,
            color: Colors.black87,
            fontWeight: cell.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: cell.italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: cellWidth - 8);

      double offsetX;
      if (align == TextAlign.right) {
        offsetX = x + cellWidth - tp.width - 6;
      } else if (align == TextAlign.center) {
        offsetX = x + (cellWidth - tp.width) / 2;
      } else {
        offsetX = x + 4;
      }

      tp.paint(
        canvas,
        Offset(offsetX, y + (cellHeight - tp.height) / 2),
      );
    }

    // ── Selection border ──
    final selX = headerWidth + selectedCol * cellWidth;
    final selY = headerHeight + selectedRow * cellHeight;
    canvas.drawRect(
      Rect.fromLTWH(selX, selY, cellWidth, cellHeight),
      selectionPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpreadsheetPainter oldDelegate) {
    return true; // Repaint on every state change for simplicity
  }
}
