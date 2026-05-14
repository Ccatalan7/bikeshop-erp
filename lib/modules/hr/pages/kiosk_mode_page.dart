import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../models/hr_models.dart';
import '../services/hr_service.dart';
import '../../../shared/widgets/branded_loading.dart';

/// Kiosk Mode - Touch-friendly employee check-in/check-out interface
/// Designed to be displayed full-screen on a tablet/monitor at the store entrance
class KioskModePage extends StatefulWidget {
  final bool embedded;
  final bool compact;
  final VoidCallback? onClose;

  const KioskModePage({
    super.key,
    this.embedded = false,
    this.compact = false,
    this.onClose,
  });

  @override
  State<KioskModePage> createState() => _KioskModePageState();
}

class _KioskModePageState extends State<KioskModePage> {
  List<Employee> _employees = [];
  Map<String, bool> _checkedInStatus = {};
  bool _isLoading = true;
  String _searchQuery = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEmployees();
    });
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _loadEmployees();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);

    try {
      final hrService = context.read<HRService>();

      final employees =
          await hrService.getEmployees(status: EmployeeStatus.active);
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
          // Attendance record not found (deleted manually) - clear cached status
          if (!mounted) return;

          setState(() {
            _checkedInStatus.remove(employee.id);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No se encontró turno activo para ${employee.firstName}. '
                'Estado actualizado.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );

          // Refresh to sync state with database
          await _loadEmployees();
          return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
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
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              employee.fullName,
              style: TextStyle(fontSize: 20, color: textColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now()),
              style: TextStyle(
                fontSize: 16,
                color: subtitleColor,
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

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    context.go('/hr/attendances');
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
          onPressed: _handleClose,
          tooltip: 'Salir del modo kiosko',
        ),
      ],
    );
  }

  Widget _buildEmbeddedHeader(Color cardBgColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: cardBgColor,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Modo Kiosko',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Registro rápido de entradas y salidas',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmployees,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _handleClose,
            tooltip: 'Cerrar kiosko',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(Color cardBgColor, bool isDark) {
    return Container(
      padding: EdgeInsets.all(widget.compact ? 12 : 16),
      color: cardBgColor,
      child: TextField(
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'Buscar trabajador...',
          hintStyle:
              TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF3C3C3C) : Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: widget.compact ? 10 : 14,
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
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
            'No hay trabajadores disponibles',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeList() {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    if (_filteredEmployees.isEmpty) {
      return _buildEmptyState();
    }

    if (widget.compact) {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _filteredEmployees.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final employee = _filteredEmployees[index];
          final isCheckedIn = _checkedInStatus[employee.id] ?? false;

          return _CompactEmployeeTile(
            employee: employee,
            isCheckedIn: isCheckedIn,
            onTap: () => _handleEmployeeTap(employee),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1400
            ? 4
            : constraints.maxWidth >= 1000
                ? 3
                : constraints.maxWidth >= 640
                    ? 2
                    : 1;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: constraints.maxWidth >= 1000 ? 0.9 : 1.05,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
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
        );
      },
    );
  }

  Widget _buildBody(Color bgColor, Color cardBgColor, bool isDark) {
    return Container(
      color: bgColor,
      child: Column(
        children: [
          _buildSearchBar(cardBgColor, isDark),
          Expanded(child: _buildEmployeeList()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.grey[100]!;
    final cardBgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF383838) : Colors.grey[300]!;

    final body = _buildBody(bgColor, cardBgColor, isDark);

    if (!widget.embedded) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: _buildAppBar(),
        body: body,
      );
    }

    return Column(
      children: [
        if (!widget.compact) _buildEmbeddedHeader(cardBgColor, borderColor),
        Expanded(child: body),
      ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Card(
      elevation: 4,
      color: cardBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCheckedIn
              ? Colors.green
              : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status badge
              if (isCheckedIn)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'En el lugar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (isCheckedIn) const SizedBox(height: 6),
              // Avatar
              CircleAvatar(
                radius: 32,
                backgroundColor: _getAvatarColor(),
                child: employee.photoUrl != null
                    ? ClipOval(
                        child: Image.network(
                          employee.photoUrl!,
                          fit: BoxFit.cover,
                          width: 64,
                          height: 64,
                        ),
                      )
                    : Text(
                        employee.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              // Name
              Text(
                employee.fullName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Job title
              Text(
                employee.jobTitle,
                style: TextStyle(
                  fontSize: 11,
                  color: subtitleColor,
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
                  fontSize: 11,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      title: Text(
        isCheckingOut ? 'Registrar Salida' : 'Registrar Entrada',
        style: TextStyle(fontSize: 24, color: textColor),
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            employee.jobTitle,
            style: TextStyle(
              fontSize: 16,
              color: subtitleColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now()),
            style: TextStyle(fontSize: 16, color: textColor),
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

class _CompactEmployeeTile extends StatelessWidget {
  final Employee employee;
  final bool isCheckedIn;
  final VoidCallback onTap;

  const _CompactEmployeeTile({
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCheckedIn
              ? Colors.green
              : (isDark ? const Color(0xFF3A3A3A) : Colors.grey[300]!),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _getAvatarColor(),
                child: employee.photoUrl != null
                    ? ClipOval(
                        child: Image.network(
                          employee.photoUrl!,
                          fit: BoxFit.cover,
                          width: 44,
                          height: 44,
                        ),
                      )
                    : Text(
                        employee.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      employee.jobTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: subtitleColor,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(
                    isCheckedIn ? Icons.logout : Icons.login,
                    color: isCheckedIn ? Colors.green : Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCheckedIn ? 'Salir' : 'Entrar',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isCheckedIn ? Colors.green : Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
