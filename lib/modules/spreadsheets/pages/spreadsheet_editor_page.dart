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
  int? _selectionEndRow;
  int? _selectionEndCol;

  // Drag state (fill-handle only)
  bool _isDraggingHandle = false;
  bool _isSelectingRange = false;
  int? _dragSourceMinRow;
  int? _dragSourceMaxRow;
  int? _dragSourceMinCol;
  int? _dragSourceMaxCol;

  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasUnsaved = false;

  bool get _isPrimaryShortcutPressed =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  int get _rowCount => _sheet?.rowCount ?? _defaultRows;
  int get _colCount => _sheet?.colCount ?? _defaultCols;

  bool get _isMultiSelection =>
      _selectionEndRow != null &&
      _selectionEndCol != null &&
      (_selectionEndRow != _selectedRow || _selectionEndCol != _selectedCol);

  int get _minRow => _isMultiSelection
      ? (_selectedRow < _selectionEndRow! ? _selectedRow : _selectionEndRow!)
      : _selectedRow;
  int get _maxRow => _isMultiSelection
      ? (_selectedRow > _selectionEndRow! ? _selectedRow : _selectionEndRow!)
      : _selectedRow;
  int get _minCol => _isMultiSelection
      ? (_selectedCol < _selectionEndCol! ? _selectedCol : _selectionEndCol!)
      : _selectedCol;
  int get _maxCol => _isMultiSelection
      ? (_selectedCol > _selectionEndCol! ? _selectedCol : _selectionEndCol!)
      : _selectedCol;

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
      _formulaBarController.text =
          _getCell(_selectedRow, _selectedCol).rawValue;
      _focusGrid();
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // CELL EDITING
  // ══════════════════════════════════════════════════════════════════

  String _cellKey(int row, int col) => '$row,$col';

  CellData _getCell(int row, int col) {
    return _cells.putIfAbsent(_cellKey(row, col), () => CellData());
  }

  CellData _cloneCell(CellData cell) {
    return CellData(
      rawValue: cell.rawValue,
      displayValue: cell.displayValue,
      cellType: cell.cellType,
      bold: cell.bold,
      italic: cell.italic,
      textAlign: cell.textAlign,
      dirty: true,
    );
  }

  void _applyRawToCell(CellData cell, String raw, int row, int col) {
    cell.rawValue = raw;

    if (raw.isEmpty) {
      cell.cellType = 'text';
      cell.displayValue = '';
      return;
    }

    if (raw.startsWith('=')) {
      cell.cellType = 'formula';
      cell.displayValue = _formulaEngine.evaluate(raw, row, col);
      return;
    }

    if (double.tryParse(raw.replaceAll(',', '.')) != null) {
      cell.cellType = 'number';
      cell.displayValue = raw;
      return;
    }

    cell.cellType = 'text';
    cell.displayValue = raw;
  }

  bool _isCellInSelection(int row, int col) {
    return row >= _minRow && row <= _maxRow && col >= _minCol && col <= _maxCol;
  }

  void _captureCurrentSelectionForDrag() {
    _dragSourceMinRow = _minRow;
    _dragSourceMaxRow = _maxRow;
    _dragSourceMinCol = _minCol;
    _dragSourceMaxCol = _maxCol;
  }

  void _resetPointerState() {
    _isDraggingHandle = false;
    _isSelectingRange = false;
    _dragSourceMinRow = null;
    _dragSourceMaxRow = null;
    _dragSourceMinCol = null;
    _dragSourceMaxCol = null;
  }

  /// Aggressively request focus on the grid.
  /// Uses both sync + post-frame callback to guarantee keyboard events arrive.
  void _focusGrid() {
    _gridFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isEditing) {
        _gridFocusNode.requestFocus();
      }
    });
  }

  bool _isOverFillHandle(double x, double y) {
    final handleCenterX = _headerWidth + (_maxCol + 1) * _cellWidth;
    final handleCenterY = _headerHeight + (_maxRow + 1) * _cellHeight;
    return (x - handleCenterX).abs() <= 10 && (y - handleCenterY).abs() <= 10;
  }

  void _selectRange(int startRow, int startCol, int endRow, int endCol) {
    if (_isEditing) _commitEdit();

    setState(() {
      _selectedRow = startRow;
      _selectedCol = startCol;
      _selectionEndRow = endRow;
      _selectionEndCol = endCol;
      _isEditing = false;
      _formulaBarController.text = _getCell(startRow, startCol).rawValue;
    });

    _ensureVisibleCell(endRow, endCol);
    _focusGrid();
  }

  void _selectCell(int row, int col) {
    _selectRange(row, col, row, col);
  }

  void _selectAll() {
    _selectRange(0, 0, _rowCount - 1, _colCount - 1);
  }

  void _selectRow(int row) {
    _selectRange(row, 0, row, _colCount - 1);
  }

  void _selectColumn(int col) {
    _selectRange(0, col, _rowCount - 1, col);
  }

  void _updateSelectionEnd(int row, int col) {
    if (_isEditing) _commitEdit();
    setState(() {
      _selectionEndRow = row;
      _selectionEndCol = col;
    });
    _ensureVisibleCell(row, col);
    _focusGrid();
  }

  void _startEditing() {
    final cell = _getCell(_selectedRow, _selectedCol);
    _beginEditing(
      initialText: cell.rawValue,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: cell.rawValue.length,
      ),
    );
  }

  void _startTyping(String firstCharacter) {
    _beginEditing(
      initialText: firstCharacter,
      selection: TextSelection.collapsed(offset: firstCharacter.length),
    );
  }

  void _beginEditing({
    required String initialText,
    required TextSelection selection,
  }) {
    setState(() {
      _isEditing = true;
      _cellEditController.value = TextEditingValue(
        text: initialText,
        selection: selection,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cellEditFocusNode.requestFocus();
    });
  }

  void _commitEdit() {
    if (!_isEditing) return;
    final raw = _cellEditController.text;
    _setCellValue(_selectedRow, _selectedCol, raw);
    setState(() => _isEditing = false);
    _focusGrid();
  }

  void _cancelEdit() {
    setState(() => _isEditing = false);
    _focusGrid();
  }

  void _setCellValue(int row, int col, String raw) {
    final cell = _getCell(row, col);
    _applyRawToCell(cell, raw, row, col);
    cell.dirty = true;

    // Recalculate dependent formulas
    _formulaEngine.recalculateAll();

    _formulaBarController.text = _getCell(_selectedRow, _selectedCol).rawValue;
    _hasUnsaved = true;
    _scheduleSave();
    setState(() {});
  }

  void _clearCellSilently(int row, int col) {
    final cell = _getCell(row, col);
    _applyRawToCell(cell, '', row, col);
    cell.dirty = true;
  }

  void _writeCellFromSource(
    int row,
    int col,
    CellData source, {
    int rowOffset = 0,
    int colOffset = 0,
    bool shiftFormula = false,
  }) {
    final target = _getCell(row, col);
    final raw = shiftFormula && source.isFormula
        ? _shiftFormula(source.rawValue, rowOffset, colOffset)
        : source.rawValue;

    target.bold = source.bold;
    target.italic = source.italic;
    target.textAlign = source.textAlign;
    _applyRawToCell(target, raw, row, col);
    target.dirty = true;
  }

  void _finishBatchUpdate() {
    _formulaEngine.recalculateAll();
    _formulaBarController.text = _getCell(_selectedRow, _selectedCol).rawValue;
    _hasUnsaved = true;
    _scheduleSave();
    setState(() {});
  }

  // ══════════════════════════════════════════════════════════════════
  // FORMULA BAR
  // ══════════════════════════════════════════════════════════════════

  void _onFormulaBarSubmitted(String value) {
    _setCellValue(_selectedRow, _selectedCol, value);
    _focusGrid();
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
  // AUTOFILL LOGIC
  // ══════════════════════════════════════════════════════════════════

  void _performAutofill() {
    if (!_isMultiSelection ||
        _dragSourceMinRow == null ||
        _dragSourceMinCol == null) {
      return;
    }

    final sourceMinRow = _dragSourceMinRow!;
    final sourceMaxRow = _dragSourceMaxRow ?? sourceMinRow;
    final sourceMinCol = _dragSourceMinCol!;
    final sourceMaxCol = _dragSourceMaxCol ?? sourceMinCol;

    final sourceHeight = sourceMaxRow - sourceMinRow + 1;
    final sourceWidth = sourceMaxCol - sourceMinCol + 1;
    bool changedAny = false;

    for (int r = _minRow; r <= _maxRow; r++) {
      for (int c = _minCol; c <= _maxCol; c++) {
        final isInsideOriginalSource = r >= sourceMinRow &&
            r <= sourceMaxRow &&
            c >= sourceMinCol &&
            c <= sourceMaxCol;
        if (isInsideOriginalSource) continue;

        final sourceRow = sourceMinRow + ((r - _minRow) % sourceHeight);
        final sourceCol = sourceMinCol + ((c - _minCol) % sourceWidth);
        final sourceCell = _getCell(sourceRow, sourceCol);

        if (sourceCell.isEmpty) {
          _clearCellSilently(r, c);
        } else {
          _writeCellFromSource(
            r,
            c,
            sourceCell,
            rowOffset: r - sourceRow,
            colOffset: c - sourceCol,
            shiftFormula: sourceCell.isFormula,
          );
        }
        changedAny = true;
      }
    }

    if (changedAny) {
      _finishBatchUpdate();
    }
  }

  String _shiftFormula(String formula, int rowOffset, int colOffset) {
    final refRegex = RegExp(r'\b([A-Z]+)(\d+)\b', caseSensitive: false);
    return formula.replaceAllMapped(refRegex, (match) {
      final colStr = match.group(1)!;
      final rowStr = match.group(2)!;
      final col = CellModel.letterToCol(colStr.toUpperCase());
      final row = int.parse(rowStr) - 1;

      final newCol = (col + colOffset).clamp(0, _colCount - 1);
      final newRow = (row + rowOffset).clamp(0, _rowCount - 1);

      return '${CellModel.colToLetter(newCol)}${newRow + 1}';
    });
  }

  String _selectionToText() {
    final rows = <String>[];
    for (int r = _minRow; r <= _maxRow; r++) {
      final values = <String>[];
      for (int c = _minCol; c <= _maxCol; c++) {
        values.add(_getCell(r, c).rawValue);
      }
      rows.add(values.join('\t'));
    }
    return rows.join('\n');
  }

  Future<void> _copySelectionToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _selectionToText()));
  }

  Future<void> _cutSelectionToClipboard() async {
    await _copySelectionToClipboard();
    for (int r = _minRow; r <= _maxRow; r++) {
      for (int c = _minCol; c <= _maxCol; c++) {
        _clearCellSilently(r, c);
      }
    }
    _finishBatchUpdate();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final rows = text.replaceAll('\r\n', '\n').split('\n').toList();
    if (rows.isNotEmpty && rows.last.isEmpty) {
      rows.removeLast();
    }
    if (rows.isEmpty) return;

    int widestRow = 0;
    for (int rowOffset = 0; rowOffset < rows.length; rowOffset++) {
      final values = rows[rowOffset].split('\t');
      widestRow = values.length > widestRow ? values.length : widestRow;

      for (int colOffset = 0; colOffset < values.length; colOffset++) {
        final targetRow = _selectedRow + rowOffset;
        final targetCol = _selectedCol + colOffset;
        if (targetRow >= _rowCount || targetCol >= _colCount) continue;
        final target = _getCell(targetRow, targetCol);
        _applyRawToCell(target, values[colOffset], targetRow, targetCol);
        target.dirty = true;
      }
    }

    setState(() {
      _selectionEndRow =
          (_selectedRow + rows.length - 1).clamp(0, _rowCount - 1);
      _selectionEndCol = (_selectedCol + widestRow - 1).clamp(0, _colCount - 1);
    });
    _finishBatchUpdate();
  }

  // ══════════════════════════════════════════════════════════════════
  // KEYBOARD
  // ══════════════════════════════════════════════════════════════════

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (!_isEditing && _isPrimaryShortcutPressed) {
      if (key == LogicalKeyboardKey.keyC) {
        unawaited(_copySelectionToClipboard());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        unawaited(_cutSelectionToClipboard());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        unawaited(_pasteFromClipboard());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _selectAll();
        return KeyEventResult.handled;
      }
    }

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

    // Navigation with Shift for multi-selection
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (isShiftPressed) {
        final endR = _selectionEndRow ?? _selectedRow;
        final endC = _selectionEndCol ?? _selectedCol;
        _updateSelectionEnd((endR + 1).clamp(0, _rowCount - 1), endC);
      } else {
        _moveSelection(1, 0);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isShiftPressed) {
        final endR = _selectionEndRow ?? _selectedRow;
        final endC = _selectionEndCol ?? _selectedCol;
        _updateSelectionEnd((endR - 1).clamp(0, _rowCount - 1), endC);
      } else {
        _moveSelection(-1, 0);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isShiftPressed) {
        final endR = _selectionEndRow ?? _selectedRow;
        final endC = _selectionEndCol ?? _selectedCol;
        _updateSelectionEnd(endR, (endC + 1).clamp(0, _colCount - 1));
      } else {
        _moveSelection(0, 1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (isShiftPressed) {
        final endR = _selectionEndRow ?? _selectedRow;
        final endC = _selectionEndCol ?? _selectedCol;
        _updateSelectionEnd(endR, (endC - 1).clamp(0, _colCount - 1));
      } else {
        _moveSelection(0, -1);
      }
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
      if (_isMultiSelection) {
        for (int r = _minRow; r <= _maxRow; r++) {
          for (int c = _minCol; c <= _maxCol; c++) {
            _setCellValue(r, c, '');
          }
        }
      } else {
        _setCellValue(_selectedRow, _selectedCol, '');
      }
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
      _startTyping(event.character!);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _moveSelection(int dRow, int dCol) {
    setState(() {
      _selectedRow = (_selectedRow + dRow).clamp(0, _rowCount - 1);
      _selectedCol = (_selectedCol + dCol).clamp(0, _colCount - 1);
      _selectionEndRow = null;
      _selectionEndCol = null;
      final cell = _getCell(_selectedRow, _selectedCol);
      _formulaBarController.text = cell.rawValue;
    });
    _ensureVisibleCell(_selectedRow, _selectedCol);
    _focusGrid();
  }

  void _ensureVisibleCell(int row, int col) {
    if (!_hScrollController.hasClients || !_vScrollController.hasClients) {
      return;
    }

    final targetX = _headerWidth + col * _cellWidth;
    final targetY = _headerHeight + row * _cellHeight;
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
  // POINTER HANDLERS (simple Excel model: click=select, drag=extend)
  // ══════════════════════════════════════════════════════════════════

  void _onGridPointerDown(PointerDownEvent details) {
    final x = details.localPosition.dx;
    final y = details.localPosition.dy;

    // Header: select all
    if (x < _headerWidth && y < _headerHeight) {
      _selectAll();
      return;
    }
    // Row header: select row
    if (x < _headerWidth) {
      final row =
          ((y - _headerHeight) / _cellHeight).floor().clamp(0, _rowCount - 1);
      _selectRow(row);
      return;
    }
    // Column header: select column
    if (y < _headerHeight) {
      final col =
          ((x - _headerWidth) / _cellWidth).floor().clamp(0, _colCount - 1);
      _selectColumn(col);
      return;
    }

    final col = ((x - _headerWidth) / _cellWidth).floor();
    final row = ((y - _headerHeight) / _cellHeight).floor();
    if (row < 0 || row >= _rowCount || col < 0 || col >= _colCount) return;

    // Fill handle
    if ((_isMultiSelection || (row == _selectedRow && col == _selectedCol)) &&
        _isOverFillHandle(x, y)) {
      if (_isEditing) _commitEdit();
      _captureCurrentSelectionForDrag();
      _isDraggingHandle = true;
      return;
    }

    // Clicking inside the active inline editor — let EditableText handle it
    if (_isEditing && row == _selectedRow && col == _selectedCol) {
      return;
    }

    // Commit any active edit before selecting a new cell
    if (_isEditing) _commitEdit();

    // Select (or extend with Shift)
    if (HardwareKeyboard.instance.isShiftPressed) {
      _updateSelectionEnd(row, col);
    } else {
      _selectCell(row, col);
    }
    _isSelectingRange = true;
  }

  void _onGridPointerMove(PointerMoveEvent details) {
    if (!details.down) return;
    final x = details.localPosition.dx;
    final y = details.localPosition.dy;
    if (x < _headerWidth || y < _headerHeight) return;

    final col =
        ((x - _headerWidth) / _cellWidth).floor().clamp(0, _colCount - 1);
    final row =
        ((y - _headerHeight) / _cellHeight).floor().clamp(0, _rowCount - 1);

    if (_isDraggingHandle || _isSelectingRange) {
      _updateSelectionEnd(row, col);
    }
  }

  void _onGridPointerUp(PointerUpEvent details) {
    if (_isDraggingHandle && _isMultiSelection) {
      _performAutofill();
    }
    _resetPointerState();
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
                autofocus: true,
                focusNode: _gridFocusNode,
                onKeyEvent: _handleKeyEvent,
                child: _buildGrid(theme),
              ),
            ),

            // ── Quick Stats Bottom Bar ──
            if (_isMultiSelection) _buildQuickStatsBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsBar(ThemeData theme) {
    double sum = 0;
    int count = 0;
    int numCount = 0;

    for (int r = _minRow; r <= _maxRow; r++) {
      for (int c = _minCol; c <= _maxCol; c++) {
        final cell = _getCell(r, c);
        if (cell.isEmpty) continue;
        count++;

        final val =
            double.tryParse(cell.isFormula ? cell.displayValue : cell.rawValue);
        if (val != null) {
          sum += val;
          numCount++;
        }
      }
    }

    if (numCount == 0 && count == 0) return const SizedBox.shrink();

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (numCount > 0) ...[
            Text('Promedio: ${(sum / numCount).toStringAsFixed(2)}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(width: 16),
            Text('Recuento nums: $numCount',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(width: 16),
            Text('Suma: ${sum.toStringAsFixed(2)}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(width: 16),
          ],
          Text('Recuento: $count',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildGrid(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = _headerWidth + _colCount * _cellWidth;
        final totalHeight = _headerHeight + _rowCount * _cellHeight;

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
                        isEditing: _isEditing,
                        selectionEndRow: _selectionEndRow,
                        selectionEndCol: _selectionEndCol,
                        isDraggingHandle: _isDraggingHandle,
                        rowCount: _rowCount,
                        colCount: _colCount,
                        cellWidth: _cellWidth,
                        cellHeight: _cellHeight,
                        headerWidth: _headerWidth,
                        headerHeight: _headerHeight,
                        theme: theme,
                      ),
                      child: Stack(
                        children: [
                          Listener(
                            onPointerDown: _onGridPointerDown,
                            onPointerMove: _onGridPointerMove,
                            onPointerUp: _onGridPointerUp,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onDoubleTapDown: (details) {
                                final x = details.localPosition.dx;
                                final y = details.localPosition.dy;
                                if (x < _headerWidth || y < _headerHeight)
                                  return;
                                final col =
                                    ((x - _headerWidth) / _cellWidth).floor();
                                final row =
                                    ((y - _headerHeight) / _cellHeight).floor();
                                if (row >= 0 &&
                                    row < _rowCount &&
                                    col >= 0 &&
                                    col < _colCount) {
                                  _selectCell(row, col);
                                  _startEditing();
                                }
                              },
                              child: Container(
                                width: totalWidth,
                                height: totalHeight,
                                color: Colors.transparent,
                              ),
                            ),
                          ),
                          if (_isEditing)
                            Positioned(
                              left:
                                  _headerWidth + _selectedCol * _cellWidth + 1,
                              top: _headerHeight +
                                  _selectedRow * _cellHeight +
                                  1,
                              width: _cellWidth - 2,
                              height: _cellHeight - 2,
                              child: ColoredBox(
                                color: Colors.white,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: Center(
                                    child: SizedBox(
                                      height: 18,
                                      child: EditableText(
                                        controller: _cellEditController,
                                        focusNode: _cellEditFocusNode,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.0,
                                          color: Colors.black87,
                                        ),
                                        strutStyle: const StrutStyle(
                                          fontSize: 13,
                                          height: 1.0,
                                          forceStrutHeight: true,
                                        ),
                                        maxLines: 1,
                                        cursorColor: Colors.blue,
                                        backgroundCursorColor: Colors.black54,
                                        textAlign: TextAlign.left,
                                        selectionColor:
                                            Colors.blue.withOpacity(0.18),
                                        onSubmitted: (_) {
                                          _commitEdit();
                                          _moveSelection(1, 0);
                                        },
                                      ),
                                    ),
                                  ),
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
  final bool isEditing;
  final int? selectionEndRow;
  final int? selectionEndCol;
  final bool isDraggingHandle;
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
    this.isEditing = false,
    this.selectionEndRow,
    this.selectionEndCol,
    this.isDraggingHandle = false,
    required this.rowCount,
    required this.colCount,
    required this.cellWidth,
    required this.cellHeight,
    required this.headerWidth,
    required this.headerHeight,
    required this.theme,
  });

  bool get _isMultiSelection =>
      selectionEndRow != null &&
      selectionEndCol != null &&
      (selectionEndRow != selectedRow || selectionEndCol != selectedCol);

  int get _minRow => _isMultiSelection
      ? (selectedRow < selectionEndRow! ? selectedRow : selectionEndRow!)
      : selectedRow;
  int get _maxRow => _isMultiSelection
      ? (selectedRow > selectionEndRow! ? selectedRow : selectionEndRow!)
      : selectedRow;
  int get _minCol => _isMultiSelection
      ? (selectedCol < selectionEndCol! ? selectedCol : selectionEndCol!)
      : selectedCol;
  int get _maxCol => _isMultiSelection
      ? (selectedCol > selectionEndCol! ? selectedCol : selectionEndCol!)
      : selectedCol;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.5;
    final headerBg = Paint()..color = Colors.grey.shade100;

    final selectionBorderPaint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final selectionFillPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final selectionHeaderBg = Paint()..color = Colors.blue.shade50;

    final minR = _minRow;
    final maxR = _maxRow;
    final minC = _minCol;
    final maxC = _maxCol;

    // ── Column headers ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, headerHeight),
      headerBg,
    );
    for (int c = 0; c < colCount; c++) {
      final x = headerWidth + c * cellWidth;
      // Highlight selected column header(s)
      final isSelected = c >= minC && c <= maxC;
      if (isSelected) {
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
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
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
      // Highlight selected row header(s)
      final isSelected = r >= minR && r <= maxR;
      if (isSelected) {
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
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
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
      if (isEditing && row == selectedRow && col == selectedCol) continue;

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

    // ── Selection Overlay ──
    final selX = headerWidth + minC * cellWidth;
    final selY = headerHeight + minR * cellHeight;
    final selW = (maxC - minC + 1) * cellWidth;
    final selH = (maxR - minR + 1) * cellHeight;

    // Fill the selection (except the primary cell)
    if (_isMultiSelection) {
      canvas.drawRect(
          Rect.fromLTWH(selX, selY, selW, selH), selectionFillPaint);

      // Clear fill from the active cell
      final activeX = headerWidth + selectedCol * cellWidth;
      final activeY = headerHeight + selectedRow * cellHeight;
      canvas.drawRect(
          Rect.fromLTWH(activeX, activeY, cellWidth, cellHeight),
          Paint()
            ..color = Colors.white
            ..blendMode = BlendMode.clear);
    }

    // Draw the main border around the selection
    canvas.drawRect(
        Rect.fromLTWH(selX, selY, selW, selH), selectionBorderPaint);

    // ── Autofill Handle ──
    final handleSize = 6.0;
    final handleX = selX + selW; // bottom right
    final handleY = selY + selH;

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(handleX, handleY),
        width: handleSize,
        height: handleSize,
      ),
      Paint()..color = Colors.blue.shade700,
    );
  }

  @override
  bool shouldRepaint(covariant _SpreadsheetPainter oldDelegate) {
    return true; // Repaint on every state change for simplicity
  }
}
