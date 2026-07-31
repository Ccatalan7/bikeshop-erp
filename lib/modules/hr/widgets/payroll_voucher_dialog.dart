import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../services/payroll_voucher_service.dart';
import '../models/payroll_voucher.dart';

enum PayrollPeriodMode { week, month }

class PayrollVoucherDialog extends StatefulWidget {
  final PayrollVoucher? existingVoucher; // For editing existing voucher

  const PayrollVoucherDialog({super.key, this.existingVoucher});

  @override
  State<PayrollVoucherDialog> createState() => _PayrollVoucherDialogState();
}

class _PayrollVoucherDialogState extends State<PayrollVoucherDialog> {
  DateTimeRange? _dateRange;
  PayrollVoucher? _draftVoucher;
  bool _isLoading = false;
  final String _saveOperationKey = const Uuid().v4();
  PayrollPeriodMode _periodMode = PayrollPeriodMode.week;

  final Map<String, TextEditingController> _hoursControllers = {};
  final Map<String, TextEditingController> _rateControllers = {};

  // Track original decimal values to avoid rounding errors
  final Map<String, double> _originalHours = {};
  final Map<String, double> _originalRates = {};
  final Set<String> _dirtyLines = {}; // Lines that user actually edited
  bool get _isEditMode => widget.existingVoucher != null;

  @override
  void initState() {
    super.initState();
    if (widget.existingVoucher != null) {
      // Edit mode: load existing voucher
      _draftVoucher = widget.existingVoucher;
      _dateRange = DateTimeRange(
        start: widget.existingVoucher!.periodStart,
        end: widget.existingVoucher!.periodEnd,
      );
      _initializeControllers(widget.existingVoucher);
    } else {
      _setCurrentPeriod();
    }
  }

  bool get _isCurrentPeriod {
    if (_dateRange == null) return false;
    final now = DateTime.now();
    if (_periodMode == PayrollPeriodMode.week) {
      final currentWeekStart = _getWeekStart(now);
      return _dateRange!.start.year == currentWeekStart.year &&
          _dateRange!.start.month == currentWeekStart.month &&
          _dateRange!.start.day == currentWeekStart.day;
    } else {
      return _dateRange!.start.year == now.year &&
          _dateRange!.start.month == now.month;
    }
  }

  DateTime _getWeekStart(DateTime date) {
    return DateTime(date.year, date.month, date.day - (date.weekday - 1));
  }

  DateTime _getWeekEnd(DateTime date) {
    final start = _getWeekStart(date);
    return DateTime(start.year, start.month, start.day + 6);
  }

  DateTime _getMonthStart(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  DateTime _getMonthEnd(DateTime date) {
    return DateTime(date.year, date.month + 1, 0);
  }

  void _setCurrentPeriod() {
    final now = DateTime.now();
    if (_periodMode == PayrollPeriodMode.week) {
      _dateRange =
          DateTimeRange(start: _getWeekStart(now), end: _getWeekEnd(now));
    } else {
      _dateRange =
          DateTimeRange(start: _getMonthStart(now), end: _getMonthEnd(now));
    }
    _draftVoucher = null;
    setState(() {});
  }

  void _previousPeriod() {
    if (_dateRange == null) return;
    final current = _dateRange!.start;
    if (_periodMode == PayrollPeriodMode.week) {
      final newStart = current.subtract(const Duration(days: 7));
      _dateRange = DateTimeRange(
          start: _getWeekStart(newStart), end: _getWeekEnd(newStart));
    } else {
      final newDate = DateTime(current.year, current.month - 1, 1);
      _dateRange = DateTimeRange(
          start: _getMonthStart(newDate), end: _getMonthEnd(newDate));
    }
    _draftVoucher = null;
    setState(() {});
  }

  void _nextPeriod() {
    if (_dateRange == null) return;
    final current = _dateRange!.start;
    if (_periodMode == PayrollPeriodMode.week) {
      final newStart = current.add(const Duration(days: 7));
      _dateRange = DateTimeRange(
          start: _getWeekStart(newStart), end: _getWeekEnd(newStart));
    } else {
      final newDate = DateTime(current.year, current.month + 1, 1);
      _dateRange = DateTimeRange(
          start: _getMonthStart(newDate), end: _getMonthEnd(newDate));
    }
    _draftVoucher = null;
    setState(() {});
  }

  void _togglePeriodMode(PayrollPeriodMode mode) {
    if (_periodMode == mode) return;
    _periodMode = mode;
    _setCurrentPeriod();
  }

  String get _periodLabel {
    if (_dateRange == null) return 'Seleccionar Periodo';
    final dateFormat = DateFormat('dd MMM', 'es');
    final monthFormat = DateFormat('MMMM yyyy', 'es');
    if (_periodMode == PayrollPeriodMode.week) {
      final weekNum = _getISOWeekNumber(_dateRange!.start);
      return 'Semana $weekNum: ${dateFormat.format(_dateRange!.start)} - ${dateFormat.format(_dateRange!.end)}';
    } else {
      return monthFormat.format(_dateRange!.start).toUpperCase();
    }
  }

  int _getISOWeekNumber(DateTime date) {
    final dayOfYear = int.parse(DateFormat('D').format(date));
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  String _formatHoursHHMM(double decimalHours) {
    final hours = decimalHours.floor();
    final minutes = ((decimalHours - hours) * 60).round();
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  void _initializeControllers(PayrollVoucher? voucher) {
    _hoursControllers.clear();
    _rateControllers.clear();
    _originalHours.clear();
    _originalRates.clear();
    _dirtyLines.clear();

    if (voucher == null) return;
    for (var line in voucher.lines) {
      if (line.id == null) continue;
      // Use decimal format for hours (e.g., 19.78) to avoid HH:MM parsing issues
      _hoursControllers[line.id!] =
          TextEditingController(text: line.workedHours.toStringAsFixed(2));
      _rateControllers[line.id!] =
          TextEditingController(text: line.hourlyRate.toInt().toString());

      // Store original decimal values
      _originalHours[line.id!] = line.workedHours;
      _originalRates[line.id!] = line.hourlyRate;
    }
  }

  /// Generates a PREVIEW (not saved to DB) for user review
  Future<void> _generatePreview() async {
    if (_dateRange == null) return;
    final service = context.read<PayrollVoucherService>();
    setState(() => _isLoading = true);
    try {
      final preview = await service.generatePreview(
        _dateRange!.start,
        _dateRange!.end,
        periodLabel: _periodLabel,
      );
      if (mounted) {
        setState(() {
          _draftVoucher = preview;
          _isLoading = false;
        });
        _initializeControllers(preview);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Saves the preview to the database as a draft
  Future<void> _saveDraft() async {
    if (_draftVoucher == null) return;
    final service = context.read<PayrollVoucherService>();
    setState(() => _isLoading = true);
    try {
      // Apply any pending edits to the preview before saving
      _applyPendingEdits();

      if (_isEditMode) {
        // Update existing voucher
        await service.updateVoucher(
          _draftVoucher!,
          operationKey: _saveOperationKey,
        );
      } else {
        // Create new draft
        await service.saveDraft(
          _draftVoucher!,
          operationKey: _saveOperationKey,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode
                ? 'Nómina actualizada'
                : 'Borrador guardado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Applies pending edits from controllers to the preview voucher.
  /// Only updates lines where hours/rate text actually changed from original.
  void _applyPendingEdits() {
    if (_draftVoucher == null) return;

    final updatedLines = _draftVoucher!.lines.map((line) {
      final hoursText = _hoursControllers[line.id]?.text ?? '';
      final rateText = _rateControllers[line.id]?.text ?? '';

      // Parse current text values (decimal format)
      final hours = double.tryParse(hoursText) ?? line.workedHours;
      final rate = double.tryParse(rateText) ?? line.hourlyRate;
      final total = hours * rate;

      return line.copyWith(
        workedHours: hours,
        hourlyRate: rate,
        regularAmount: total,
        totalAmount: total,
      );
    }).toList();

    double totalAmount = 0;
    double totalHours = 0;
    int employeeCount = 0;

    for (var line in updatedLines) {
      if (line.isIncluded) {
        totalAmount += line.totalAmount;
        totalHours += line.workedHours;
        employeeCount++;
      }
    }

    _draftVoucher = _draftVoucher!.copyWith(
      lines: updatedLines,
      totalAmount: totalAmount,
      totalHours: totalHours,
      employeeCount: employeeCount,
    );
  }

  /// Recalculates footer totals without modifying line objects.
  /// Use this for live updates while typing to avoid rounding drift.
  void _recalculateTotalsOnly() {
    if (_draftVoucher == null) return;

    double totalAmount = 0;
    double totalHours = 0;
    int employeeCount = 0;

    for (var line in _draftVoucher!.lines) {
      if (!line.isIncluded) continue;

      final lineId = line.id ?? '';
      double hours;
      double rate;

      // Use original values for untouched lines, parsed values for dirty lines
      if (_dirtyLines.contains(lineId)) {
        final hoursText = _hoursControllers[lineId]?.text;
        final rateText = _rateControllers[lineId]?.text;
        hours = hoursText != null
            ? (double.tryParse(hoursText) ?? line.workedHours)
            : line.workedHours;
        rate = rateText != null
            ? (double.tryParse(rateText) ?? line.hourlyRate)
            : line.hourlyRate;
      } else {
        // Use stored original values to avoid rounding errors
        hours = _originalHours[lineId] ?? line.workedHours;
        rate = _originalRates[lineId] ?? line.hourlyRate;
      }

      totalAmount += hours * rate;
      totalHours += hours;
      employeeCount++;
    }

    // Only update totals, not lines (avoid rounding drift in line objects)
    _draftVoucher = _draftVoucher!.copyWith(
      totalAmount: totalAmount,
      totalHours: totalHours,
      employeeCount: employeeCount,
    );
  }

  /// Updates totals locally as user types (preview only, no line modification)
  void _updateLineLocal(PayrollVoucherLine line) {
    // Mark this line as dirty (user edited it)
    if (line.id != null) {
      _dirtyLines.add(line.id!);
    }
    _recalculateTotalsOnly();
    setState(() {}); // Refresh UI
  }

  double _effectiveHours(PayrollVoucherLine line) {
    final lineId = line.id;
    if (lineId == null) return line.workedHours;

    if (_dirtyLines.contains(lineId)) {
      final hoursText = _hoursControllers[lineId]?.text;
      return hoursText != null
          ? (double.tryParse(hoursText) ?? line.workedHours)
          : line.workedHours;
    }

    return _originalHours[lineId] ?? line.workedHours;
  }

  double _effectiveRate(PayrollVoucherLine line) {
    final lineId = line.id;
    if (lineId == null) return line.hourlyRate;

    if (_dirtyLines.contains(lineId)) {
      final rateText = _rateControllers[lineId]?.text;
      return rateText != null
          ? (double.tryParse(rateText) ?? line.hourlyRate)
          : line.hourlyRate;
    }

    return _originalRates[lineId] ?? line.hourlyRate;
  }

  double _effectiveLineTotal(PayrollVoucherLine line) {
    return _effectiveHours(line) * _effectiveRate(line);
  }

  /// Toggles include status locally (preview only, no DB call)
  void _toggleIncludeLocal(PayrollVoucherLine line, bool included) {
    if (_draftVoucher == null) return;

    final updatedLines = _draftVoucher!.lines.map((l) {
      if (l.id == line.id) {
        return l.copyWith(isIncluded: included);
      }
      return l;
    }).toList();

    setState(() {
      _draftVoucher = _draftVoucher!.copyWith(
        lines: updatedLines,
      );
      _recalculateTotalsOnly();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_draftVoucher == null && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Dialog(
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(24),
      child: Container(
        width: isMobile ? screenWidth : null,
        constraints: isMobile
            ? null
            : const BoxConstraints(maxWidth: 900, maxHeight: 800),
        child: Column(
          children: [
            _buildHeader(context, isMobile),
            const Divider(height: 1),
            Expanded(
                child: _draftVoucher == null
                    ? _buildEmptyState()
                    : _buildVoucherContent(context, isMobile)),
            if (isMobile || _draftVoucher != null) ...[
              const Divider(height: 1),
              _buildFooter(context, isMobile),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isMobile) {
    final theme = Theme.of(context);

    if (isMobile) {
      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. Title Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Generar Nómina', style: theme.textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 2. Navigation Area (Cleaner, integrated)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              color: theme.colorScheme.surface,
              child: Column(
                children: [
                  // Date Navigation Row
                  Row(
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_left),
                        onPressed:
                            _draftVoucher == null ? _previousPeriod : null,
                        visualDensity: VisualDensity.compact,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _periodLabel,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (!_isCurrentPeriod && _draftVoucher == null)
                              GestureDetector(
                                onTap: _setCurrentPeriod,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Ir al Actual',
                                    style: TextStyle(
                                      color: theme.primaryColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _draftVoucher == null ? _nextPeriod : null,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Mode Toggle (Subtle, Pill style)
                  if (_draftVoucher == null)
                    SegmentedButton<PayrollPeriodMode>(
                      segments: const [
                        ButtonSegment(
                            value: PayrollPeriodMode.week,
                            label: Text('Semana')),
                        ButtonSegment(
                            value: PayrollPeriodMode.month, label: Text('Mes')),
                      ],
                      selected: {_periodMode},
                      onSelectionChanged: (modes) =>
                          _togglePeriodMode(modes.first),
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Desktop
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Text('Generar Nómina', style: theme.textTheme.titleLarge),
          const SizedBox(width: 16),
          if (_draftVoucher == null)
            SegmentedButton<PayrollPeriodMode>(
              segments: const [
                ButtonSegment(
                    value: PayrollPeriodMode.week, label: Text('Semana')),
                ButtonSegment(
                    value: PayrollPeriodMode.month, label: Text('Mes')),
              ],
              selected: {_periodMode},
              onSelectionChanged: (modes) => _togglePeriodMode(modes.first),
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: _draftVoucher == null ? _previousPeriod : null,
                  visualDensity: VisualDensity.compact),
              InkWell(
                onTap: _draftVoucher == null && !_isCurrentPeriod
                    ? _setCurrentPeriod
                    : null,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isCurrentPeriod
                        ? Colors.green.withValues(alpha: 0.1)
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: _isCurrentPeriod
                            ? Colors.green
                            : theme.dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isCurrentPeriod)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(3)),
                          child: const Text('HOY',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      Text(_periodLabel,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color:
                                  _isCurrentPeriod ? Colors.green[700] : null)),
                    ],
                  ),
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: _draftVoucher == null ? _nextPeriod : null,
                  visualDensity: VisualDensity.compact),
            ],
          ),
          if (_draftVoucher == null && _dateRange != null) ...[
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _isLoading ? null : _generatePreview,
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
              child: const Text('Generar'),
            ),
          ],
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Selecciona un rango de fechas y genera un borrador',
              style: TextStyle(color: Colors.grey[600], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildVoucherContent(BuildContext context, bool isMobile) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (isMobile) {
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _draftVoucher!.lines.length,
        itemBuilder: (context, index) {
          final line = _draftVoucher!.lines[index];
          final currency =
              NumberFormat.currency(symbol: '\$', decimalDigits: 0);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                          value: line.isIncluded,
                          onChanged: (val) =>
                              _toggleIncludeLocal(line, val ?? false)),
                      Expanded(
                          child: Text(line.employeeName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16))),
                      Text(currency.format(_effectiveLineTotal(line)),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green[700])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hoursControllers[line.id],
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(
                              labelText: 'Horas',
                              isDense: true,
                              border: OutlineInputBorder()),
                          onChanged: (_) => _updateLineLocal(line),
                          onSubmitted: (_) => _updateLineLocal(line),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _rateControllers[line.id],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Tarifa/Hr',
                              isDense: true,
                              border: OutlineInputBorder()),
                          onChanged: (_) => _updateLineLocal(line),
                          onSubmitted: (_) => _updateLineLocal(line),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    // Desktop table
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(50),
          1: FlexColumnWidth(2),
          2: FixedColumnWidth(100),
          3: FixedColumnWidth(120),
          4: FixedColumnWidth(120),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey[100]),
            children: const [
              Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.check_circle_outline, size: 16)),
              Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Trabajador',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Horas',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Tarifa/Hr',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Total',
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          ..._draftVoucher!.lines.map((line) {
            final currency =
                NumberFormat.currency(symbol: '\$', decimalDigits: 0);
            return TableRow(
              children: [
                Checkbox(
                    value: line.isIncluded,
                    onChanged: (val) =>
                        _toggleIncludeLocal(line, val ?? false)),
                Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(line.employeeName)),
                _buildEditableCell(line, _hoursControllers[line.id]),
                _buildEditableCell(line, _rateControllers[line.id]),
                Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(currency.format(_effectiveLineTotal(line)),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEditableCell(
      PayrollVoucherLine line, TextEditingController? controller) {
    if (controller == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder()),
        onChanged: (_) => _updateLineLocal(line),
        onSubmitted: (_) => _updateLineLocal(line),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isMobile) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    if (isMobile) {
      if (_draftVoucher == null) {
        // Mobile Footer: Generate Button
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_isLoading || _dateRange == null)
                    ? null
                    : _generatePreview,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Generar Nómina'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        );
      }

      // Mobile Footer: Summary + Save
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${_draftVoucher!.employeeCount} trabajadores'),
                  Text('${_formatHoursHHMM(_draftVoucher!.totalHours)} hrs'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total: ${currency.format(_draftVoucher!.totalAmount)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700])),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _saveDraft,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trabajadores: ${_draftVoucher!.employeeCount}'),
              Text(
                  'Total Horas: ${_formatHoursHHMM(_draftVoucher!.totalHours)}'),
              Text(
                  'Total a Pagar: ${currency.format(_draftVoucher!.totalAmount)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.green[700])),
            ],
          ),
          FilledButton.icon(
            onPressed: _isLoading ? null : _saveDraft,
            icon: const Icon(Icons.save),
            label: const Text('Guardar Borrador'),
          ),
        ],
      ),
    );
  }
}
