import 'package:flutter/material.dart';

import '../models/financial_report.dart';

/// Widget for selecting date ranges for reports
/// Includes presets and custom date picker
class DateRangeSelectorWidget extends StatefulWidget {
  final DateRange initialRange;
  final ReportPeriod initialPeriod;
  final Function(DateRange, ReportPeriod) onRangeChanged;
  final bool showEndDate; // For Balance Sheet (single date), hide end date

  const DateRangeSelectorWidget({
    super.key,
    required this.initialRange,
    this.initialPeriod = ReportPeriod.currentMonth,
    required this.onRangeChanged,
    this.showEndDate = true,
  });

  @override
  State<DateRangeSelectorWidget> createState() => _DateRangeSelectorWidgetState();
}

class _DateRangeSelectorWidgetState extends State<DateRangeSelectorWidget> {
  late ReportPeriod _selectedPeriod;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _selectedPeriod = widget.initialPeriod;
    _startDate = widget.initialRange.start;
    _endDate = widget.initialRange.end;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Período del Reporte',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Period preset dropdown
            DropdownButtonFormField<ReportPeriod>(
              value: _selectedPeriod,
              decoration: const InputDecoration(
                labelText: 'Preset',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
              ),
              items: ReportPeriod.values.map((period) {
                return DropdownMenuItem(
                  value: period,
                  child: Text(period.displayName),
                );
              }).toList(),
              onChanged: (period) {
                if (period != null) {
                  setState(() {
                    _selectedPeriod = period;
                    if (period != ReportPeriod.custom) {
                      final range = period.getDateRange();
                      _startDate = range.start;
                      _endDate = range.end;
                      widget.onRangeChanged(range, period);
                    }
                  });
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // Custom date range (only if custom is selected)
            if (_selectedPeriod == ReportPeriod.custom) ...[
              Row(
                children: [
                  // Start date
                  Expanded(
                    child: _buildDatePicker(
                      context: context,
                      label: widget.showEndDate ? 'Fecha Inicio' : 'Fecha',
                      date: _startDate,
                      onDateSelected: (date) {
                        setState(() {
                          _startDate = date;
                          if (!widget.showEndDate) {
                            _endDate = date; // Same date for balance sheet
                          }
                          widget.onRangeChanged(
                            DateRange(_startDate, _endDate),
                            _selectedPeriod,
                          );
                        });
                      },
                    ),
                  ),
                  
                  if (widget.showEndDate) ...[
                    const SizedBox(width: 16),
                    
                    // End date
                    Expanded(
                      child: _buildDatePicker(
                        context: context,
                        label: 'Fecha Fin',
                        date: _endDate,
                        onDateSelected: (date) {
                          setState(() {
                            _endDate = date;
                            widget.onRangeChanged(
                              DateRange(_startDate, _endDate),
                              _selectedPeriod,
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
            
            // Show selected range preview
            if (_selectedPeriod != ReportPeriod.custom) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.showEndDate
                            ? '${_formatDate(_startDate)} - ${_formatDate(_endDate)}'
                            : _formatDate(_endDate),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required BuildContext context,
    required String label,
    required DateTime date,
    required Function(DateTime) onDateSelected,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          locale: const Locale('es', 'CL'),
        );
        
        if (picked != null) {
          onDateSelected(picked);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.calendar_month),
        ),
        child: Text(
          _formatDate(date),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
