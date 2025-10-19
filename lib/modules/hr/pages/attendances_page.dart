import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../models/hr_models.dart';
import '../services/hr_service.dart';

enum TimeView { day, week, month, quarter, year }

// Color palette for attendance blocks (Odoo-style)
const List<Color> _employeeColors = [
  Color(0xFF4A90E2), // Blue
  Color(0xFF50C878), // Green
  Color(0xFFF39C12), // Orange
  Color(0xFF9B59B6), // Purple
  Color(0xFFE74C3C), // Red
  Color(0xFF1ABC9C), // Teal
  Color(0xFFE67E22), // Dark Orange
  Color(0xFF3498DB), // Light Blue
];

Color _getEmployeeColor(int index) {
  return _employeeColors[index % _employeeColors.length];
}

class AttendancesPage extends StatefulWidget {
  const AttendancesPage({super.key});

  @override
  State<AttendancesPage> createState() => _AttendancesPageState();
}

class _AttendancesPageState extends State<AttendancesPage> {
  TimeView _currentView = TimeView.week;
  DateTime _selectedDate = DateTime.now();
  List<Employee> _employees = [];
  Map<String, List<Attendance>> _attendancesByEmployee = {};
  bool _isLoading = true;
  Timer? _refreshTimer;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
    // Refresh every minute to update ongoing attendance times
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {}); // Trigger rebuild to update elapsed times
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final hrService = context.read<HRService>();
      final dateRange = _getDateRangeForView();
      
      final employees = await hrService.getEmployees(status: EmployeeStatus.active);
      final attendances = await hrService.getAttendances(
        startDate: dateRange.start,
        endDate: dateRange.end,
      );
      
      // Group attendances by employee
      final Map<String, List<Attendance>> grouped = {};
      for (final attendance in attendances) {
        if (!grouped.containsKey(attendance.employeeId)) {
          grouped[attendance.employeeId] = [];
        }
        grouped[attendance.employeeId]!.add(attendance);
      }
      
      if (!mounted) return;
      
      setState(() {
        _employees = employees;
        _attendancesByEmployee = grouped;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: \$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  DateTimeRange _getDateRangeForView() {
    switch (_currentView) {
      case TimeView.day:
        final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        return DateTimeRange(start: start, end: start.add(const Duration(days: 1)));
      
      case TimeView.week:
        final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
        return DateTimeRange(start: start, end: start.add(const Duration(days: 7)));
      
      case TimeView.month:
        final start = DateTime(_selectedDate.year, _selectedDate.month, 1);
        final end = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
        return DateTimeRange(start: start, end: end);
      
      case TimeView.quarter:
        final quarter = ((_selectedDate.month - 1) ~/ 3) + 1;
        final startMonth = (quarter - 1) * 3 + 1;
        final start = DateTime(_selectedDate.year, startMonth, 1);
        final end = DateTime(_selectedDate.year, startMonth + 3, 0);
        return DateTimeRange(start: start, end: end);
      
      case TimeView.year:
        final start = DateTime(_selectedDate.year, 1, 1);
        final end = DateTime(_selectedDate.year, 12, 31);
        return DateTimeRange(start: start, end: end);
    }
  }

  void _changeView(TimeView view) {
    setState(() => _currentView = view);
    _loadData();
  }

  void _navigatePrevious() {
    setState(() {
      switch (_currentView) {
        case TimeView.day:
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
          break;
        case TimeView.week:
          _selectedDate = _selectedDate.subtract(const Duration(days: 7));
          break;
        case TimeView.month:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1);
          break;
        case TimeView.quarter:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 3);
          break;
        case TimeView.year:
          _selectedDate = DateTime(_selectedDate.year - 1, _selectedDate.month);
          break;
      }
    });
    _loadData();
  }

  void _navigateNext() {
    setState(() {
      switch (_currentView) {
        case TimeView.day:
          _selectedDate = _selectedDate.add(const Duration(days: 1));
          break;
        case TimeView.week:
          _selectedDate = _selectedDate.add(const Duration(days: 7));
          break;
        case TimeView.month:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1);
          break;
        case TimeView.quarter:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 3);
          break;
        case TimeView.year:
          _selectedDate = DateTime(_selectedDate.year + 1, _selectedDate.month);
          break;
      }
    });
    _loadData();
  }

  void _navigateToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadData();
  }

  String _getDateRangeLabel() {
    final DateFormat dayFormat = DateFormat('d MMM');
    final DateFormat monthFormat = DateFormat('MMMM yyyy');
    final DateFormat yearFormat = DateFormat('yyyy');
    
    switch (_currentView) {
      case TimeView.day:
        return dayFormat.format(_selectedDate);
      
      case TimeView.week:
        final range = _getDateRangeForView();
        return 'Semana, de ${dayFormat.format(range.start)} a ${dayFormat.format(range.end.subtract(const Duration(days: 1)))}';
      
      case TimeView.month:
        return monthFormat.format(_selectedDate);
      
      case TimeView.quarter:
        final quarter = ((_selectedDate.month - 1) ~/ 3) + 1;
        return 'Trimestre $quarter ${_selectedDate.year}';
      
      case TimeView.year:
        return yearFormat.format(_selectedDate);
    }
  }

  void _showAttendanceDetailDialog(Attendance attendance) {
    // Find the employee for this attendance
    final employee = _employees.firstWhere(
      (e) => e.id == attendance.employeeId,
      orElse: () => Employee(
        employeeNumber: 'Unknown',
        firstName: 'Empleado',
        lastName: 'Desconocido',
        jobTitle: 'N/A',
      ),
    );

    showDialog(
      context: context,
      builder: (context) => _AttendanceDetailDialog(
        attendance: attendance,
        employee: employee,
        onSave: (updatedAttendance) async {
          try {
            final hrService = context.read<HRService>();
            await hrService.updateAttendance(updatedAttendance);
            if (!mounted) return;
            Navigator.of(context).pop();
            _loadData(); // Refresh data
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Asistencia actualizada correctamente'),
                backgroundColor: Colors.green,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al actualizar: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onDelete: () async {
          try {
            final hrService = context.read<HRService>();
            await hrService.deleteAttendance(attendance.id!);
            if (!mounted) return;
            Navigator.of(context).pop();
            _loadData(); // Refresh data
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Asistencia eliminada correctamente'),
                backgroundColor: Colors.orange,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al eliminar: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onApprove: () async {
          try {
            final hrService = context.read<HRService>();
            // TODO: Get current user ID properly
            await hrService.approveAttendance(attendance.id!, 'current-user-id');
            if (!mounted) return;
            Navigator.of(context).pop();
            _loadData(); // Refresh data
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Asistencia aprobada'),
                backgroundColor: Colors.green,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al aprobar: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        onReject: () async {
          try {
            final hrService = context.read<HRService>();
            // TODO: Get current user ID properly
            await hrService.rejectAttendance(attendance.id!, 'current-user-id');
            if (!mounted) return;
            Navigator.of(context).pop();
            _loadData(); // Refresh data
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Asistencia rechazada'),
                backgroundColor: Colors.orange,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al rechazar: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Asistencias',
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildAttendanceGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ViewButton(
                label: 'Día',
                isSelected: _currentView == TimeView.day,
                onTap: () => _changeView(TimeView.day),
              ),
              const SizedBox(width: 8),
              _ViewButton(
                label: 'Semana',
                isSelected: _currentView == TimeView.week,
                onTap: () => _changeView(TimeView.week),
              ),
              const SizedBox(width: 8),
              _ViewButton(
                label: 'Mes',
                isSelected: _currentView == TimeView.month,
                onTap: () => _changeView(TimeView.month),
              ),
              const SizedBox(width: 8),
              _ViewButton(
                label: 'Trimestre',
                isSelected: _currentView == TimeView.quarter,
                onTap: () => _changeView(TimeView.quarter),
              ),
              const SizedBox(width: 8),
              _ViewButton(
                label: 'Año',
                isSelected: _currentView == TimeView.year,
                onTap: () => _changeView(TimeView.year),
              ),
              const Spacer(),
              AppButton(
                text: 'Nuevo',
                onPressed: () {
                  // TODO: Implement manual entry dialog
                },
                icon: Icons.add,
                type: ButtonType.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _navigatePrevious,
                tooltip: 'Período anterior',
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _navigateToday,
                child: const Text('Hoy'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _navigateNext,
                tooltip: 'Período siguiente',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _getDateRangeLabel(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceGrid() {
    if (_employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No hay empleados registrados',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final dateRange = _getDateRangeForView();
    final List<DateTime> days = _getDaysInRange(dateRange);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGridHeader(days),
              const SizedBox(height: 8),
              ..._employees.asMap().entries.map((entry) {
                final index = entry.key;
                final employee = entry.value;
                return _buildEmployeeRow(employee, days, index);
              }),
            ],
          ),
        ),
      ),
    );
  }

  List<DateTime> _getDaysInRange(DateTimeRange range) {
    final List<DateTime> days = [];
    DateTime current = range.start;
    
    while (current.isBefore(range.end)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }
    
    return days;
  }

  Widget _buildGridHeader(List<DateTime> days) {
    return Row(
      children: [
        Container(
          width: 200,
          height: 60,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: const Text(
            'Días',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        ...days.map((day) => _buildDayHeader(day)),
      ],
    );
  }

  Widget _buildDayHeader(DateTime day) {
    final isToday = DateTime.now().year == day.year &&
        DateTime.now().month == day.month &&
        DateTime.now().day == day.day;

    return Container(
      width: 120,
      height: 60,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isToday ? Theme.of(context).primaryColor.withOpacity(0.1) : Theme.of(context).colorScheme.surface,
        border: Border.all(color: isToday ? Theme.of(context).primaryColor : Colors.grey[300]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('EEE').format(day),
            style: TextStyle(
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
              color: isToday ? Theme.of(context).primaryColor : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('d').format(day),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isToday ? Theme.of(context).primaryColor : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeRow(Employee employee, List<DateTime> days, int employeeIndex) {
    final color = _getEmployeeColor(employeeIndex);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 200,
            height: 80,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[50],
              border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  radius: 20,
                  child: employee.photoUrl != null
                      ? ClipOval(child: Image.network(employee.photoUrl!, fit: BoxFit.cover))
                      : Text(
                          employee.initials,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        employee.fullName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        employee.jobTitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...days.map((day) => _buildAttendanceCell(employee, day, color)),
        ],
      ),
    );
  }

  Widget _buildAttendanceCell(Employee employee, DateTime day, Color color) {
    final attendances = _attendancesByEmployee[employee.id] ?? [];
    
    final dayAttendances = attendances.where((att) {
      return att.checkIn.year == day.year &&
          att.checkIn.month == day.month &&
          att.checkIn.day == day.day;
    }).toList();

    return Container(
      width: 120,
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: dayAttendances.isEmpty
          ? const SizedBox.shrink()
          : _buildAttendanceBlocks(dayAttendances, color),
    );
  }

  Widget _buildAttendanceBlocks(List<Attendance> attendances, Color baseColor) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: attendances.map((attendance) {
          // Calculate elapsed time for ongoing attendances
          String displayTime;
          if (attendance.isOngoing) {
            final duration = DateTime.now().difference(attendance.checkIn);
            final hours = duration.inHours;
            final minutes = duration.inMinutes % 60;
            displayTime = '$hours:${minutes.toString().padLeft(2, '0')}';
          } else {
            displayTime = attendance.workedHours?.toStringAsFixed(1) ?? '--';
          }
          
          final checkIn = DateFormat('HH:mm').format(attendance.checkIn);
          final checkOut = attendance.checkOut != null
              ? DateFormat('HH:mm').format(attendance.checkOut!)
              : '...';
          
          // Color coding based on status
          Color blockColor;
          Color borderColor;
          if (attendance.isOngoing) {
            // Green for ongoing (En curso)
            blockColor = Colors.green.shade100;
            borderColor = Colors.green.shade700;
          } else if (attendance.status == AttendanceStatus.approved) {
            // Light green for approved
            blockColor = Colors.green.shade50;
            borderColor = Colors.green.shade300;
          } else if (attendance.status == AttendanceStatus.rejected) {
            // Red for rejected
            blockColor = Colors.red.shade100;
            borderColor = Colors.red.shade700;
          } else {
            // Gray for pending approval
            blockColor = Colors.grey.shade200;
            borderColor = Colors.grey.shade500;
          }

          // Build compact time range display like Odoo
          String timeRangeText = '$checkIn-$checkOut';
          
          // Check if text would be too long (more than ~15 characters)
          bool needsTruncation = timeRangeText.length > 15;
          String displayText = needsTruncation 
              ? '${timeRangeText.substring(0, 12)}...' 
              : timeRangeText;

          return GestureDetector(
            onTap: () => _showAttendanceDetailDialog(attendance),
            child: Tooltip(
              message: 'Entrada: $checkIn\nSalida: $checkOut\n${attendance.isOngoing ? "En curso" : "Tiempo trabajado: ${displayTime}h"}',
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: blockColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Text(
                  displayText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Colors.grey[900],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ViewButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? Theme.of(context).primaryColor
          : Colors.grey[200],
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// Attendance Detail Dialog (Odoo-style)
class _AttendanceDetailDialog extends StatefulWidget {
  final Attendance attendance;
  final Employee employee;
  final Function(Attendance) onSave;
  final VoidCallback onDelete;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _AttendanceDetailDialog({
    required this.attendance,
    required this.employee,
    required this.onSave,
    required this.onDelete,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_AttendanceDetailDialog> createState() => _AttendanceDetailDialogState();
}

class _AttendanceDetailDialogState extends State<_AttendanceDetailDialog> {
  late DateTime _checkIn;
  late DateTime? _checkOut;
  late String _notes;
  late int _overtimeMinutes;
  
  @override
  void initState() {
    super.initState();
    _checkIn = widget.attendance.checkIn;
    _checkOut = widget.attendance.checkOut;
    _notes = widget.attendance.notes ?? '';
    _overtimeMinutes = ((widget.attendance.overtimeHours ?? 0) * 60).toInt();
  }

  Future<void> _pickDateTime(bool isCheckIn) async {
    final DateTime initialDate = isCheckIn ? _checkIn : (_checkOut ?? DateTime.now());
    
    // Show date picker
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    if (pickedDate == null) return;
    
    if (!mounted) return;
    
    // Show time picker with 24-hour format
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    
    if (pickedTime == null) return;
    
    final DateTime combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    
    setState(() {
      if (isCheckIn) {
        _checkIn = combined;
      } else {
        _checkOut = combined;
      }
    });
  }

  Duration? get _workedDuration {
    if (_checkOut == null) return null;
    return _checkOut!.difference(_checkIn);
  }

  String get _workedHoursDisplay {
    if (_checkOut == null) {
      final ongoing = DateTime.now().difference(_checkIn);
      final hours = ongoing.inHours;
      final minutes = ongoing.inMinutes % 60;
      return '$hours:${minutes.toString().padLeft(2, '0')}';
    }
    final duration = _workedDuration!;
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  void _save() {
    final updatedAttendance = widget.attendance.copyWith(
      checkIn: _checkIn,
      checkOut: _checkOut,
      notes: _notes.isNotEmpty ? _notes : null,
      overtimeHours: _overtimeMinutes > 0 ? _overtimeMinutes / 60 : null,
    );
    widget.onSave(updatedAttendance);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;
    final inputBgColor = isDark ? const Color(0xFF3C3C3C) : Colors.grey[100]!;
    
    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with status workflow
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Abierto',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: textColor),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStatusWorkflow(),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Employee info
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          radius: 24,
                          child: widget.employee.photoUrl != null
                              ? ClipOval(
                                  child: Image.network(
                                    widget.employee.photoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Text(
                                      widget.employee.initials,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.employee.initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Empleado',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: labelColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.employee.fullName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                widget.employee.jobTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: labelColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Check-in time
                    Text(
                      'Entrada',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _pickDateTime(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(8),
                          color: inputBgColor,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                DateFormat('dd/MM/yyyy HH:mm').format(_checkIn),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(Icons.edit, size: 20, color: isDark ? Colors.blue[300] : Colors.blue),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Check-out time
                    Text(
                      'Salida',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _pickDateTime(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(8),
                          color: inputBgColor,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _checkOut != null
                                    ? DateFormat('dd/MM/yyyy HH:mm').format(_checkOut!)
                                    : 'No registrado',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(Icons.edit, size: 20, color: isDark ? Colors.blue[300] : Colors.blue),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Worked time
                    Text(
                      'Tiempo trabajado',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: inputBgColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _workedHoursDisplay,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Overtime (Horas extra)
                    Text(
                      'Horas extra',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '-${(_overtimeMinutes / 60).toStringAsFixed(0)}:${(_overtimeMinutes % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 18,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        TextButton.icon(
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Rechazar'),
                          onPressed: _overtimeMinutes > 0
                              ? () => setState(() => _overtimeMinutes = 0)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Notes
                    Text(
                      'Notas',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: _notes),
                      onChanged: (value) => _notes = value,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 16,
                        color: textColor,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Agregar notas...',
                        hintStyle: TextStyle(color: labelColor),
                        filled: true,
                        fillColor: inputBgColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[400]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[400]!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Footer buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                    onPressed: () {
                      // Confirm deletion
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Confirmar eliminación'),
                          content: const Text('¿Está seguro que desea eliminar esta asistencia?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                widget.onDelete();
                              },
                              child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Descartar'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF714B67),
                        ),
                        child: const Text('Guardar y cerrar', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusWorkflow() {
    final status = widget.attendance.status;
    
    return Row(
      children: [
        _buildStatusChip('Por aprobar', status == AttendanceStatus.ongoing || status == AttendanceStatus.completed),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, color: Colors.grey),
        const SizedBox(width: 8),
        _buildStatusChip('Aprobada', status == AttendanceStatus.approved),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, color: Colors.grey),
        const SizedBox(width: 8),
        _buildStatusChip('Rechazado', status == AttendanceStatus.rejected),
      ],
    );
  }

  Widget _buildStatusChip(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF4DD0E1) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? const Color(0xFF4DD0E1) : Colors.grey[400]!),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.grey[700],
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
