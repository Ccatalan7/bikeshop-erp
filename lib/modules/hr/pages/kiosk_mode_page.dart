import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/hr_models.dart';
import '../services/hr_service.dart';

/// Kiosk Mode - Touch-friendly employee check-in/check-out interface
/// Designed to be displayed full-screen on a tablet/monitor at the store entrance
class KioskModePage extends StatefulWidget {
  const KioskModePage({super.key});

  @override
  State<KioskModePage> createState() => _KioskModePageState();
}

class _KioskModePageState extends State<KioskModePage> {
  List<Employee> _employees = [];
  Map<String, bool> _checkedInStatus = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEmployees();
    });
    // Auto-refresh every minute to update checked-in status
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) _loadEmployees();
    });
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);
    
    try {
      final hrService = context.read<HRService>();
      
      final employees = await hrService.getEmployees(status: EmployeeStatus.active);
      final checkedIn = await hrService.getCheckedInEmployees();
      
      final Map<String, bool> statusMap = {};
      for (final emp in checkedIn) {
        statusMap[emp['employee_id'] as String] = true;
      }
      
      if (!mounted) return;
      
      setState(() {
        _employees = employees;
        _checkedInStatus = statusMap;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleEmployeeTap(Employee employee) async {
    final isCheckedIn = _checkedInStatus[employee.id] ?? false;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConfirmationDialog(
        employee: employee,
        isCheckingOut: isCheckedIn,
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final hrService = context.read<HRService>();
      
      if (isCheckedIn) {
        // Check out
        final checkedInList = await hrService.getCheckedInEmployees();
        final employeeRecord = checkedInList.firstWhere(
          (e) => e['employee_id'] == employee.id,
          orElse: () => <String, dynamic>{},
        );
        
        if (employeeRecord.isEmpty) {
          throw Exception('No se encontró registro de entrada');
        }
        
        await hrService.checkOut(
          employeeRecord['attendance_id'] as String,
          location: 'Tienda',
        );
        
        if (!mounted) return;
        
        await _showSuccessDialog(employee, false);
      } else {
        // Check in
        await hrService.checkIn(
          employee.id!,
          location: 'Tienda',
        );
        
        if (!mounted) return;
        
        await _showSuccessDialog(employee, true);
      }
      
      // Refresh employee list
      await _loadEmployees();
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showSuccessDialog(Employee employee, bool checkedIn) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checkedIn ? Icons.check_circle : Icons.logout,
              color: checkedIn ? Colors.green : Colors.blue,
              size: 80,
            ),
            const SizedBox(height: 24),
            Text(
              checkedIn ? 'Entrada registrada' : 'Salida registrada',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              employee.fullName,
              style: const TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now()),
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Employee> get _filteredEmployees {
    if (_searchQuery.isEmpty) return _employees;
    
    final query = _searchQuery.toLowerCase();
    return _employees.where((emp) {
      return emp.fullName.toLowerCase().contains(query) ||
          emp.jobTitle.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Registro de Asistencia'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmployees,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Salir del modo kiosko',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar empleado...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          // Employee grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEmployees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No hay empleados disponibles',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, // 3 columns for tablets
                          childAspectRatio: 1.0,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _filteredEmployees.length,
                        itemBuilder: (context, index) {
                          final employee = _filteredEmployees[index];
                          final isCheckedIn = _checkedInStatus[employee.id] ?? false;
                          return _EmployeeCard(
                            employee: employee,
                            isCheckedIn: isCheckedIn,
                            onTap: () => _handleEmployeeTap(employee),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  final bool isCheckedIn;
  final VoidCallback onTap;

  const _EmployeeCard({
    required this.employee,
    required this.isCheckedIn,
    required this.onTap,
  });

  Color _getAvatarColor() {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];
    return colors[employee.fullName.hashCode % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCheckedIn ? Colors.green : Colors.grey[300]!,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status badge
              if (isCheckedIn)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'En el lugar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (isCheckedIn) const SizedBox(height: 8),
              // Avatar
              CircleAvatar(
                radius: 50,
                backgroundColor: _getAvatarColor(),
                child: employee.photoUrl != null
                    ? ClipOval(
                        child: Image.network(
                          employee.photoUrl!,
                          fit: BoxFit.cover,
                          width: 100,
                          height: 100,
                        ),
                      )
                    : Text(
                        employee.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              // Name
              Text(
                employee.fullName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Job title
              Text(
                employee.jobTitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              // Action label
              Text(
                isCheckedIn ? 'Toca para salir' : 'Toca para entrar',
                style: TextStyle(
                  fontSize: 13,
                  color: isCheckedIn ? Colors.green : Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmationDialog extends StatelessWidget {
  final Employee employee;
  final bool isCheckingOut;

  const _ConfirmationDialog({
    required this.employee,
    required this.isCheckingOut,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        isCheckingOut ? 'Registrar Salida' : 'Registrar Entrada',
        style: const TextStyle(fontSize: 24),
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCheckingOut ? Icons.logout : Icons.login,
            size: 64,
            color: isCheckingOut ? Colors.blue : Colors.green,
          ),
          const SizedBox(height: 16),
          Text(
            employee.fullName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            employee.jobTitle,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now()),
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: isCheckingOut ? Colors.blue : Colors.green,
                ),
                child: Text(
                  isCheckingOut ? 'Salir' : 'Entrar',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
