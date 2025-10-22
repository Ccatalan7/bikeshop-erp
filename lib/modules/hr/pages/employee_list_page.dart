import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
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
    setState(() => _isLoading = true);

    try {
      final hrService = context.read<HRService>();

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
    final result = await showDialog<Employee>(
      context: context,
      builder: (context) => _EmployeeFormDialog(
        employee: employee,
        departments: _departments,
      ),
    );

    if (result != null) {
      _loadData();
    }
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Está seguro de eliminar al empleado ${employee.fullName}? Esta acción no se puede deshacer.',
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
            content: Text('✅ Empleado ${employee.fullName} eliminado'),
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
      title: 'Empleados',
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
            child: Row(
              children: [
                Expanded(
                  child: SearchWidget(
                    onSearchChanged: _onSearchChanged,
                    hintText: 'Buscar por nombre, RUT, número...',
                  ),
                ),
                const SizedBox(width: 16),
                // Status filter
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<EmployeeStatus?>(
                    value: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
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
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedDepartmentId,
                    decoration: const InputDecoration(
                      labelText: 'Departamento',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
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
                  text: 'Nuevo Empleado',
                  onPressed: () => _showEmployeeForm(),
                  icon: Icons.add,
                  type: ButtonType.primary,
                ),
              ],
            ),
          ),
          // Employee list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
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
                                  ? 'No hay empleados registrados'
                                  : 'No se encontraron empleados',
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
      orElse: () => Department(name: 'Desconocido', code: ''),
    );
    return dept.name;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    Theme.of(context).primaryColor.withOpacity(0.1),
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
                            color: _getStatusColor().withOpacity(0.1),
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
  EmploymentType _employmentType = EmploymentType.fullTime;
  EmployeeStatus _status = EmployeeStatus.active;
  DateTime? _birthDate;
  DateTime _hireDate = DateTime.now();
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
      _employmentType = emp.employmentType;
      _status = emp.status;
      _birthDate = emp.birthDate;
      _hireDate = emp.hireDate;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final hrService = context.read<HRService>();

      final employee = Employee(
        id: widget.employee?.id,
        employeeNumber: _employeeNumberController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        email: _emailController.text.isEmpty ? null : _emailController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        rut: _rutController.text.isEmpty ? null : _rutController.text,
        jobTitle: _jobTitleController.text,
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

      final saved = widget.employee == null
          ? await hrService.createEmployee(employee)
          : await hrService.updateEmployee(employee);

      if (!mounted) return;

      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
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
                        ? 'Nuevo Empleado'
                        : 'Editar Empleado',
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
                                labelText: 'Número de Empleado *',
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
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _jobTitleController,
                              decoration: const InputDecoration(
                                labelText: 'Cargo *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => value?.isEmpty ?? true
                                  ? 'Campo requerido'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              value: _departmentId,
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
                              value: _employmentType,
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
                              value: _status,
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
