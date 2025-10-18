import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../models/hr_models.dart';
import '../services/hr_service.dart';

enum TimeView { day, week, month, quarter, year }

class AttendancesPage extends StatefulWidget {
  const AttendancesPage({super.key});

  @override
  State<AttendancesPage> createState() => _AttendancesPageState();
}

class _AttendancesPageState extends State<AttendancesPage> {
  TimeView _currentView = TimeView.month;
  DateTime _selectedDate = DateTime.now();
  Employee? _selectedEmployee;
  AttendanceStatus? _selectedStatus;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAttendances();
    });
  }

  Future<void> _loadAttendances() async {
    // Trigger a rebuild to refresh the FutureBuilder
    setState(() {});
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
    _loadAttendances();
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
    _loadAttendances();
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
    _loadAttendances();
  }

  void _navigateToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadAttendances();
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
        return '${dayFormat.format(range.start)} - ${dayFormat.format(range.end)}';
      
      case TimeView.month:
        return monthFormat.format(_selectedDate);
      
      case TimeView.quarter:
        final quarter = ((_selectedDate.month - 1) ~/ 3) + 1;
        return 'Q$quarter ${_selectedDate.year}';
      
      case TimeView.year:
        return yearFormat.format(_selectedDate);
    }
  }

  Future<void> _showCheckInDialog() async {
    // Get list of employees
    final hrService = context.read<HRService>();
    final employees = await hrService.getEmployees(status: EmployeeStatus.active);
    
    if (!mounted) return;
    
    Employee? selectedEmployee;
    String location = 'Oficina';
    String notes = '';
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Registrar Entrada'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Empleado', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<Employee>(
                  value: selectedEmployee,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: employees.map((emp) {
                    return DropdownMenuItem(
                      value: emp,
                      child: Text(emp.fullName),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedEmployee = value),
                ),
                const SizedBox(height: 16),
                const Text('Ubicación', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: location,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) => location = value,
                ),
                const SizedBox(height: 16),
                const Text('Notas (opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                  onChanged: (value) => notes = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selectedEmployee == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Registrar Entrada'),
            ),
          ],
        ),
      ),
    );
    
    if (result == true && selectedEmployee != null && mounted) {
      try {
        await hrService.checkIn(
          selectedEmployee!.id!,
          location: location,
          notes: notes.isEmpty ? null : notes,
        );
        
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Entrada registrada para ${selectedEmployee!.fullName}'),
            backgroundColor: Colors.green,
          ),
        );
        
        _loadAttendances();
      } catch (e) {
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showCheckOutDialog() async {
    // Get list of currently checked-in employees
    final hrService = context.read<HRService>();
    final checkedInEmployees = await hrService.getCheckedInEmployees();
    
    if (!mounted) return;
    
    if (checkedInEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay empleados con entrada registrada'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    Map<String, dynamic>? selectedEmployee;
    String location = 'Oficina';
    int breakMinutes = 0;
    String notes = '';
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Registrar Salida'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Empleado', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: selectedEmployee,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: checkedInEmployees.map((emp) {
                    return DropdownMenuItem(
                      value: emp,
                      child: Text(emp['employee_name'] ?? 'Sin nombre'),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedEmployee = value),
                ),
                const SizedBox(height: 16),
                const Text('Ubicación', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: location,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) => location = value,
                ),
                const SizedBox(height: 16),
                const Text('Minutos de pausa', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: breakMinutes.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixText: 'min',
                  ),
                  onChanged: (value) => breakMinutes = int.tryParse(value) ?? 0,
                ),
                const SizedBox(height: 16),
                const Text('Notas (opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                  onChanged: (value) => notes = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selectedEmployee == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Registrar Salida'),
            ),
          ],
        ),
      ),
    );
    
    if (result == true && selectedEmployee != null && mounted) {
      try {
        await hrService.checkOut(
          selectedEmployee!['attendance_id'],
          location: location,
          breakMinutes: breakMinutes,
          notes: notes.isEmpty ? null : notes,
        );
        
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Salida registrada para ${selectedEmployee!['employee_name']}'),
            backgroundColor: Colors.green,
          ),
        );
        
        _loadAttendances();
      } catch (e) {
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hrService = context.watch<HRService>();
    final dateRange = _getDateRangeForView();
    
    return MainLayout(
      title: 'Asistencias',
      child: Column(
        children: [
          // Toolbar
          Container(
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
                // View selector and actions
                Row(
                  children: [
                    // View buttons
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
                    // Action buttons
                    AppButton(
                      text: 'Entrada',
                      onPressed: _showCheckInDialog,
                      icon: Icons.login,
                      type: ButtonType.primary,
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      text: 'Salida',
                      onPressed: _showCheckOutDialog,
                      icon: Icons.logout,
                      type: ButtonType.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Date navigation
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _navigatePrevious,
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _navigateToday,
                      child: const Text('Hoy'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _navigateNext,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _getDateRangeLabel(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Filters
                    const Text('Estado:', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<AttendanceStatus?>(
                        value: _selectedStatus,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Todos')),
                          ...AttendanceStatus.values.map((status) {
                            String label = '';
                            switch (status) {
                              case AttendanceStatus.ongoing:
                                label = 'En curso';
                                break;
                              case AttendanceStatus.completed:
                                label = 'Completado';
                                break;
                              case AttendanceStatus.approved:
                                label = 'Aprobado';
                                break;
                              case AttendanceStatus.rejected:
                                label = 'Rechazado';
                                break;
                            }
                            return DropdownMenuItem(
                              value: status,
                              child: Text(label),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedStatus = value);
                          _loadAttendances();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Content area
          Expanded(
            child: FutureBuilder<List<Attendance>>(
              future: hrService.getAttendances(
                employeeId: _selectedEmployee?.id,
                startDate: dateRange.start,
                endDate: dateRange.end,
                status: _selectedStatus,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  );
                }
                
                final attendances = snapshot.data ?? [];
                
                if (attendances.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hay asistencias registradas',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                return _buildAttendancesList(attendances);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendancesList(List<Attendance> attendances) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: attendances.length,
      itemBuilder: (context, index) {
        final attendance = attendances[index];
        return _AttendanceCard(
          attendance: attendance,
          onApprove: () => _approveAttendance(attendance),
          onReject: () => _rejectAttendance(attendance),
        );
      },
    );
  }

  Future<void> _approveAttendance(Attendance attendance) async {
    // Get current user (in real app, from auth service)
    final hrService = context.read<HRService>();
    
    try {
      // For now, use a placeholder user ID
      await hrService.approveAttendance(attendance.id!, 'current-user-id');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Asistencia aprobada'),
          backgroundColor: Colors.green,
        ),
      );
      
      _loadAttendances();
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectAttendance(Attendance attendance) async {
    final hrService = context.read<HRService>();
    
    try {
      await hrService.rejectAttendance(attendance.id!, 'current-user-id');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Asistencia rechazada'),
          backgroundColor: Colors.orange,
        ),
      );
      
      _loadAttendances();
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

class _AttendanceCard extends StatelessWidget {
  final Attendance attendance;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _AttendanceCard({
    required this.attendance,
    required this.onApprove,
    required this.onReject,
  });

  Color _getStatusColor() {
    switch (attendance.status) {
      case AttendanceStatus.ongoing:
        return Colors.blue;
      case AttendanceStatus.completed:
        return Colors.orange;
      case AttendanceStatus.approved:
        return Colors.green;
      case AttendanceStatus.rejected:
        return Colors.red;
    }
  }

  String _getStatusLabel() {
    switch (attendance.status) {
      case AttendanceStatus.ongoing:
        return 'En curso';
      case AttendanceStatus.completed:
        return 'Completado';
      case AttendanceStatus.approved:
        return 'Aprobado';
      case AttendanceStatus.rejected:
        return 'Rechazado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkInTime = DateFormat('HH:mm').format(attendance.checkIn);
    final checkOutTime = attendance.checkOut != null
        ? DateFormat('HH:mm').format(attendance.checkOut!)
        : '---';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Employee info (placeholder - in real app, fetch from employee_id)
                const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attendance.employeeId, // Replace with employee name
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE d MMMM, yyyy').format(attendance.checkIn),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getStatusColor()),
                  ),
                  child: Text(
                    _getStatusLabel(),
                    style: TextStyle(
                      color: _getStatusColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Time details
            Row(
              children: [
                Expanded(
                  child: _TimeInfo(
                    icon: Icons.login,
                    label: 'Entrada',
                    time: checkInTime,
                    location: attendance.locationCheckIn,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _TimeInfo(
                    icon: Icons.logout,
                    label: 'Salida',
                    time: checkOutTime,
                    location: attendance.locationCheckOut,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _TimeInfo(
                    icon: Icons.schedule,
                    label: 'Trabajadas',
                    time: attendance.workedHours != null
                        ? '${attendance.workedHours!.toStringAsFixed(1)}h'
                        : (attendance.isOngoing
                            ? '${attendance.currentDuration.inHours}h ${attendance.currentDuration.inMinutes.remainder(60)}m'
                            : '---'),
                  ),
                ),
              ],
            ),
            if (attendance.notes != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.note, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        attendance.notes!,
                        style: TextStyle(color: Colors.grey[800]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Approval actions
            if (attendance.status == AttendanceStatus.completed) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rechazar'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Aprobar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;
  final String? location;

  const _TimeInfo({
    required this.icon,
    required this.label,
    required this.time,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        if (location != null) ...[
          const SizedBox(height: 2),
          Text(
            location!,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
