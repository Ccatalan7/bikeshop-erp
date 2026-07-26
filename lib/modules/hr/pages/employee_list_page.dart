import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/job_role_service.dart';
import '../../../shared/models/job_role.dart';
import '../models/hr_models.dart';
import '../services/hr_service.dart';

class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  State<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  String _searchQuery = '';
  EmployeeStatus? _selectedStatus = EmployeeStatus.active;
  String? _selectedDepartmentId;
  List<Employee> _employees = [];
  List<Department> _departments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final hrService = context.read<HRService>();

    // 🚀 INSTANT RENDER: Show cached data immediately if available
    if (hrService.hasEmployeesCache && _employees.isEmpty) {
      setState(() {
        _employees = hrService.cachedEmployees;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final employees = await hrService.getEmployees(
        status: _selectedStatus,
        departmentId: _selectedDepartmentId,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );

      final departments = await hrService.getDepartments(activeOnly: false);

      if (!mounted) return;

      setState(() {
        _employees = employees;
        _departments = departments;
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

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
    _loadData();
  }

  Future<void> _showEmployeeForm([Employee? employee]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EmployeeFormDialog(
        employee: employee,
        departments: _departments,
      ),
    );

    if (result != null) {
      _loadData();

      final invitationRequested = result['invitationRequested'] == true;
      final invitationEmailSent = result['invitationEmailSent'] == true;
      final email = result['email'] as String?;

      if (invitationRequested && mounted) {
        final destination = email == null || email.isEmpty ? '' : ' a $email';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              invitationEmailSent
                  ? 'Trabajador creado e invitación enviada$destination.'
                  : 'Trabajador creado, pero el correo de invitación no fue enviado. Reinténtalo desde Usuarios y roles.',
            ),
            backgroundColor: invitationEmailSent ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Está seguro de eliminar al trabajador ${employee.fullName}? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final hrService = context.read<HRService>();
        await hrService.deleteEmployee(employee.id!);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Trabajador ${employee.fullName} eliminado'),
            backgroundColor: Colors.green,
          ),
        );

        _loadData();
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
    return MainLayout(
      title: 'Trabajadores',
      child: Column(
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 800) {
                  // Mobile: Stack elements
                  return Column(
                    children: [
                      SearchWidget(
                        onSearchChanged: _onSearchChanged,
                        hintText: 'Buscar por nombre, RUT, número...',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<EmployeeStatus?>(
                              initialValue: _selectedStatus,
                              decoration: const InputDecoration(
                                labelText: 'Estado',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('Todos')),
                                ...EmployeeStatus.values.map((status) {
                                  String label = '';
                                  switch (status) {
                                    case EmployeeStatus.active:
                                      label = 'Activo';
                                      break;
                                    case EmployeeStatus.inactive:
                                      label = 'Inactivo';
                                      break;
                                    case EmployeeStatus.onLeave:
                                      label = 'Con licencia';
                                      break;
                                    case EmployeeStatus.terminated:
                                      label = 'Desvinculado';
                                      break;
                                  }
                                  return DropdownMenuItem(
                                      value: status, child: Text(label));
                                }),
                              ],
                              onChanged: (value) {
                                setState(() => _selectedStatus = value);
                                _loadData();
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _selectedDepartmentId,
                              decoration: const InputDecoration(
                                labelText: 'Depto',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('Todos')),
                                ..._departments.map((dept) => DropdownMenuItem(
                                      value: dept.id,
                                      child: Text(dept.name),
                                    )),
                              ],
                              onChanged: (value) {
                                setState(() => _selectedDepartmentId = value);
                                _loadData();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: AppButton(
                          text: 'Nuevo Trabajador',
                          onPressed: () => _showEmployeeForm(),
                          icon: Icons.add,
                          type: ButtonType.primary,
                        ),
                      ),
                    ],
                  );
                }

                // Desktop: Row
                return Row(
                  children: [
                    Expanded(
                      child: SearchWidget(
                        onSearchChanged: _onSearchChanged,
                        hintText: 'Buscar por nombre, RUT, número...',
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Status filter
                    Flexible(
                      child: DropdownButtonFormField<EmployeeStatus?>(
                        initialValue: _selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Estado',
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Todos')),
                          ...EmployeeStatus.values.map((status) {
                            String label = '';
                            switch (status) {
                              case EmployeeStatus.active:
                                label = 'Activo';
                                break;
                              case EmployeeStatus.inactive:
                                label = 'Inactivo';
                                break;
                              case EmployeeStatus.onLeave:
                                label = 'Con licencia';
                                break;
                              case EmployeeStatus.terminated:
                                label = 'Desvinculado';
                                break;
                            }
                            return DropdownMenuItem(
                                value: status, child: Text(label));
                          }),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedStatus = value);
                          _loadData();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Department filter
                    Flexible(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _selectedDepartmentId,
                        decoration: const InputDecoration(
                          labelText: 'Departamento',
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Todos')),
                          ..._departments.map((dept) => DropdownMenuItem(
                                value: dept.id,
                                child: Text(dept.name),
                              )),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedDepartmentId = value);
                          _loadData();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    AppButton(
                      text: 'Nuevo Trabajador',
                      onPressed: () => _showEmployeeForm(),
                      icon: Icons.add,
                      type: ButtonType.primary,
                    ),
                  ],
                );
              },
            ),
          ),
          // Employee list
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _employees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No hay trabajadores registrados'
                                  : 'No se encontraron trabajadores',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _employees.length,
                        itemBuilder: (context, index) {
                          final employee = _employees[index];
                          return _EmployeeCard(
                            employee: employee,
                            departments: _departments,
                            onEdit: () => _showEmployeeForm(employee),
                            onDelete: () => _deleteEmployee(employee),
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
  final List<Department> departments;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeCard({
    required this.employee,
    required this.departments,
    required this.onEdit,
    required this.onDelete,
  });

  Color _getStatusColor() {
    switch (employee.status) {
      case EmployeeStatus.active:
        return Colors.green;
      case EmployeeStatus.inactive:
        return Colors.grey;
      case EmployeeStatus.onLeave:
        return Colors.orange;
      case EmployeeStatus.terminated:
        return Colors.red;
    }
  }

  String _getStatusLabel() {
    switch (employee.status) {
      case EmployeeStatus.active:
        return 'Activo';
      case EmployeeStatus.inactive:
        return 'Inactivo';
      case EmployeeStatus.onLeave:
        return 'Con licencia';
      case EmployeeStatus.terminated:
        return 'Desvinculado';
    }
  }

  String _getDepartmentName() {
    if (employee.departmentId == null) return 'Sin departamento';
    final dept = departments.firstWhere(
      (d) => d.id == employee.departmentId,
      orElse: () => Department(tenantId: '', name: 'Desconocido', code: ''),
    );
    return dept.name;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/hr/employees/${employee.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    Theme.of(context).primaryColor.withValues(alpha: 0.1),
                child: employee.photoUrl != null
                    ? ClipOval(
                        child: Image.network(
                          employee.photoUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              employee.initials,
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            );
                          },
                        ),
                      )
                    : Text(
                        employee.initials,
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          employee.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor().withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _getStatusColor()),
                          ),
                          child: Text(
                            _getStatusLabel(),
                            style: TextStyle(
                              color: _getStatusColor(),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${employee.jobTitle} • ${_getDepartmentName()}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.badge, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          employee.employeeNumber,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        if (employee.rut != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.credit_card,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            employee.rut!,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (employee.email != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.email, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            employee.email!,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: onEdit,
                    tooltip: 'Editar',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    color: Colors.red,
                    onPressed: onDelete,
                    tooltip: 'Eliminar',
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

class _EmployeeFormDialog extends StatefulWidget {
  final Employee? employee;
  final List<Department> departments;

  const _EmployeeFormDialog({
    this.employee,
    required this.departments,
  });

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _employeeNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _rutController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _notesController = TextEditingController();

  String? _departmentId;
  String? _selectedSystemRole; // NEW: selected job role
  List<String> _suggestedTitles = []; // NEW: job title suggestions
  EmploymentType _employmentType = EmploymentType.fullTime;
  EmployeeStatus _status = EmployeeStatus.active;
  DateTime? _birthDate;
  DateTime _hireDate = DateTime.now();
  bool _grantSystemAccess = false; // NEW: checkbox for user account creation
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      final emp = widget.employee!;
      _firstNameController.text = emp.firstName;
      _lastNameController.text = emp.lastName;
      _employeeNumberController.text = emp.employeeNumber;
      _emailController.text = emp.email ?? '';
      _phoneController.text = emp.phone ?? '';
      _rutController.text = emp.rut ?? '';
      _jobTitleController.text = emp.jobTitle;
      _addressController.text = emp.address ?? '';
      _cityController.text = emp.city ?? '';
      _notesController.text = emp.notes ?? '';
      _departmentId = emp.departmentId;
      _selectedSystemRole = emp.systemRole; // Load existing role
      _employmentType = emp.employmentType;
      _status = emp.status;
      _birthDate = emp.birthDate;
      _hireDate = emp.hireDate;

      // Load suggested titles if role exists
      if (emp.systemRole != null) {
        _loadSuggestedTitles(emp.systemRole!);
      }
    } else {
      // Generate employee number for new employee
      context.read<HRService>().generateEmployeeNumber().then((number) {
        if (mounted) {
          setState(() => _employeeNumberController.text = number);
        }
      });
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _employeeNumberController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _rutController.dispose();
    _jobTitleController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // Load job title suggestions when role is selected
  Future<void> _loadSuggestedTitles(String systemRole) async {
    try {
      final jobRoleService = context.read<JobRoleService>();
      final titles = await jobRoleService.getSuggestedTitles(systemRole);
      if (mounted) {
        setState(() => _suggestedTitles = titles);
      }
    } catch (e) {
      // Silently fail - suggestions are optional
      setState(() => _suggestedTitles = []);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Additional validation for system access
    if (_grantSystemAccess) {
      if (_emailController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Se requiere un email para otorgar acceso al sistema'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_selectedSystemRole == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se requiere un rol para otorgar acceso al sistema'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final hrService = context.read<HRService>();
      final jobRoleService = context.read<JobRoleService>();

      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      final employee = Employee(
        id: widget.employee?.id,
        tenantId: tenantId,
        employeeNumber: _employeeNumberController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        email: _emailController.text.isEmpty ? null : _emailController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        rut: _rutController.text.isEmpty ? null : _rutController.text,
        jobTitle: _jobTitleController.text,
        systemRole: _selectedSystemRole, // NEW: save role link
        departmentId: _departmentId,
        employmentType: _employmentType,
        status: _status,
        birthDate: _birthDate,
        hireDate: _hireDate,
        address:
            _addressController.text.isEmpty ? null : _addressController.text,
        city: _cityController.text.isEmpty ? null : _cityController.text,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      // Save employee first
      final saved = widget.employee == null
          ? await hrService.createEmployee(employee)
          : await hrService.updateEmployee(employee);

      // If granting system access, create user account
      var invitationRequested = false;
      var invitationEmailSent = false;
      if (_grantSystemAccess &&
          saved.id != null &&
          _selectedSystemRole != null) {
        invitationRequested = true;
        try {
          // Get default permissions for the role
          final permissions =
              await jobRoleService.getDefaultPermissions(_selectedSystemRole!);

          // Create user invitation (will send email with setup link)
          invitationEmailSent = await hrService.createUserForEmployee(
            employeeId: saved.id!,
            email: _emailController.text,
            role: _selectedSystemRole!,
            permissions: permissions,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
          );
        } catch (_) {
          invitationEmailSent = false;
        }
      }

      if (!mounted) return;

      Navigator.pop(context, {
        'employee': saved,
        'invitationRequested': invitationRequested,
        'invitationEmailSent': invitationEmailSent,
        'email': _emailController.text,
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos guardar el trabajador o enviar su acceso. Inténtalo nuevamente.',
          ),
          backgroundColor: Colors.red,
        ),
      );

      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 720, // Increased slightly to prevent overflow
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    widget.employee == null
                        ? 'Nuevo Trabajador'
                        : 'Editar Trabajador',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _firstNameController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value?.isEmpty ?? true
                                  ? 'Campo requerido'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _lastNameController,
                              decoration: const InputDecoration(
                                labelText: 'Apellido *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value?.isEmpty ?? true
                                  ? 'Campo requerido'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _employeeNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Número de Trabajador *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value?.isEmpty ?? true
                                  ? 'Campo requerido'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _rutController,
                              decoration: const InputDecoration(
                                labelText: 'RUT',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              decoration: const InputDecoration(
                                labelText: 'Teléfono',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Role selection dropdown
                      FutureBuilder<List<Map<String, String>>>(
                        future: context.read<JobRoleService>().getRoleOptions(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox(
                              height: 60,
                              child: Center(child: BrandedLoading(size: 32)),
                            );
                          }

                          final roleOptions = snapshot.data!;

                          return DropdownButtonFormField<String?>(
                            initialValue: _selectedSystemRole,
                            decoration: const InputDecoration(
                              labelText: 'Rol del Sistema',
                              helperText:
                                  'Opcional: vincula al trabajador con permisos predefinidos',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Sin rol asignado'),
                              ),
                              ...roleOptions.map((option) => DropdownMenuItem(
                                    value: option['code'],
                                    child: Text(option['name']!),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedSystemRole = value;
                                _suggestedTitles = [];
                              });
                              if (value != null) {
                                _loadSuggestedTitles(value);
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _suggestedTitles.isEmpty
                                ? TextFormField(
                                    controller: _jobTitleController,
                                    decoration: const InputDecoration(
                                      labelText: 'Cargo *',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) => value?.isEmpty ?? true
                                        ? 'Campo requerido'
                                        : null,
                                  )
                                : DropdownButtonFormField<String>(
                                    initialValue: _suggestedTitles
                                            .contains(_jobTitleController.text)
                                        ? _jobTitleController.text
                                        : null,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Cargo * (sugerencias del rol)',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      ..._suggestedTitles
                                          .map((title) => DropdownMenuItem(
                                                value: title,
                                                child: Text(title),
                                              )),
                                      const DropdownMenuItem(
                                        value: 'custom',
                                        child: Text('Otro (personalizado)...'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == 'custom') {
                                        setState(() {
                                          _jobTitleController.clear();
                                          _suggestedTitles =
                                              []; // Switch to text field
                                        });
                                      } else if (value != null) {
                                        setState(() =>
                                            _jobTitleController.text = value);
                                      }
                                    },
                                    validator: (value) {
                                      if (_jobTitleController.text.isEmpty) {
                                        return 'Campo requerido';
                                      }
                                      return null;
                                    },
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _departmentId,
                              decoration: const InputDecoration(
                                labelText: 'Departamento',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Sin departamento'),
                                ),
                                ...widget.departments
                                    .map((dept) => DropdownMenuItem(
                                          value: dept.id,
                                          child: Text(dept.name),
                                        )),
                              ],
                              onChanged: (value) =>
                                  setState(() => _departmentId = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<EmploymentType>(
                              initialValue: _employmentType,
                              decoration: const InputDecoration(
                                labelText: 'Tipo de Empleo',
                                border: OutlineInputBorder(),
                              ),
                              items: EmploymentType.values.map((type) {
                                String label = '';
                                switch (type) {
                                  case EmploymentType.fullTime:
                                    label = 'Tiempo completo';
                                    break;
                                  case EmploymentType.partTime:
                                    label = 'Tiempo parcial';
                                    break;
                                  case EmploymentType.contractor:
                                    label = 'Contratista';
                                    break;
                                  case EmploymentType.intern:
                                    label = 'Practicante';
                                    break;
                                }
                                return DropdownMenuItem(
                                    value: type, child: Text(label));
                              }).toList(),
                              onChanged: (value) =>
                                  setState(() => _employmentType = value!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<EmployeeStatus>(
                              initialValue: _status,
                              decoration: const InputDecoration(
                                labelText: 'Estado',
                                border: OutlineInputBorder(),
                              ),
                              items: EmployeeStatus.values.map((status) {
                                String label = '';
                                switch (status) {
                                  case EmployeeStatus.active:
                                    label = 'Activo';
                                    break;
                                  case EmployeeStatus.inactive:
                                    label = 'Inactivo';
                                    break;
                                  case EmployeeStatus.onLeave:
                                    label = 'Con licencia';
                                    break;
                                  case EmployeeStatus.terminated:
                                    label = 'Desvinculado';
                                    break;
                                }
                                return DropdownMenuItem(
                                    value: status, child: Text(label));
                              }).toList(),
                              onChanged: (value) =>
                                  setState(() => _status = value!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cityController,
                        decoration: const InputDecoration(
                          labelText: 'Ciudad',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notas',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      // Grant System Access section
                      if (widget.employee == null ||
                          widget.employee?.userId == null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            border: Border.all(color: Colors.blue[200]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.security,
                                      color: Colors.blue[700], size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Acceso al Sistema',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[900],
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                value: _grantSystemAccess,
                                onChanged: _selectedSystemRole != null
                                    ? (value) => setState(() =>
                                        _grantSystemAccess = value ?? false)
                                    : null,
                                title:
                                    const Text('Otorgar acceso al sistema ERP'),
                                subtitle: Text(
                                  _selectedSystemRole == null
                                      ? 'Primero selecciona un rol del sistema arriba'
                                      : 'Se creará una cuenta de usuario con permisos de ${JobRole.getRoleDisplayName(_selectedSystemRole!)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _selectedSystemRole == null
                                        ? Colors.red[700]
                                        : Colors.grey[700],
                                  ),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                              if (_grantSystemAccess &&
                                  _emailController.text.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(left: 16, top: 8),
                                  child: Text(
                                    '⚠️ Se requiere un email válido para crear la cuenta de usuario',
                                    style: TextStyle(
                                        color: Colors.red[700], fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    text: widget.employee == null ? 'Crear' : 'Guardar',
                    onPressed: _isSaving ? null : _save,
                    isLoading: _isSaving,
                    type: ButtonType.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
