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
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
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
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 200,
            height: 80,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border.all(color: Colors.grey[300]!),
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
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        employee.jobTitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
          final checkIn = DateFormat('HH:mm').format(attendance.checkIn);
          final checkOut = attendance.checkOut != null
              ? DateFormat('HH:mm').format(attendance.checkOut!)
              : '...';
          final hours = attendance.workedHours?.toStringAsFixed(1) ?? 
                       (attendance.isOngoing ? 'En curso' : '--');
          
          Color blockColor;
          if (attendance.status == AttendanceStatus.approved) {
            blockColor = Colors.green.shade100;
          } else if (attendance.status == AttendanceStatus.rejected) {
            blockColor = Colors.red.shade100;
          } else if (attendance.status == AttendanceStatus.ongoing) {
            blockColor = Colors.blue.shade100;
          } else {
            blockColor = baseColor.withOpacity(0.3);
          }

          return Tooltip(
            message: 'Entrada: \$checkIn\\nSalida: \$checkOut\\nHoras: \$hours',
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: blockColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: baseColor),
              ),
              child: Column(
                children: [
                  Text(
                    hours is String ? hours : '\${hours}h',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey[800],
                    ),
                  ),
                  Text(
                    '(\$checkIn-\$checkOut)',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
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
