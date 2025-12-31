import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/app_button.dart';
import '../models/hr_models.dart';
import '../services/hr_service.dart';

/// Employee Detail Page - Modern Profile Layout
class EmployeeDetailPage extends StatefulWidget {
  final String employeeId;

  const EmployeeDetailPage({super.key, required this.employeeId});

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

enum DateFilterType { weekly, monthly, custom }

class _EmployeeDetailPageState extends State<EmployeeDetailPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;

  // Controllers
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _employeeNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _rutController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _notesController = TextEditingController();
  // Salary controllers
  final _hourlyRateController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAccountNumberController = TextEditingController();

  // State
  Employee? _employee;
  List<Department> _departments = [];
  String? _departmentId;
  String? _selectedSystemRole;
  EmploymentType _employmentType = EmploymentType.fullTime;
  EmployeeStatus _status = EmployeeStatus.active;
  DateTime? _birthDate;
  DateTime _hireDate = DateTime.now();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  // Salary/Hours state
  PaymentMethod _paymentMethod = PaymentMethod.transfer;
  BankAccountType? _bankAccountType;
  EmployeeHoursSummary? _hoursSummary;
  bool _isLoadingHours = false;
  // Filtering
  DateFilterType _filterType = DateFilterType.weekly;
  late DateTimeRange _dateRange;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es_ES', null);

    // Initialize date range (Default: Current Week Mon-Sun)
    final now = DateTime.now();
    _dateRange = _calculateWeekRange(now);

    debugPrint(
        '🔵 [EmployeeDetailPage] initState called for ID: ${widget.employeeId}');
    _tabController = TabController(length: 4, vsync: this);
    _loadEmployee();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _employeeNumberController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _rutController.dispose();
    _jobTitleController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _notesController.dispose();
    _hourlyRateController.dispose();
    _bankNameController.dispose();
    _bankAccountNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployee() async {
    final hrService = context.read<HRService>();

    // 🚀 TRY CACHE FIRST for instant load (synchronous - no setState needed)
    if (hrService.hasEmployeesCache && hrService.hasDepartmentsCache) {
      try {
        final employee = hrService.cachedEmployees.firstWhere(
          (e) => e.id == widget.employeeId,
          orElse: () => throw Exception('Not in cache'),
        );

        _populateFields(employee, hrService.cachedDepartments);
        _isLoading = false; // Direct assignment - works before first build
        debugPrint(
            '🟢 [EmployeeDetailPage] Loaded from cache - instant render');
        return;
      } catch (_) {
        debugPrint(
            '🟠 [EmployeeDetailPage] Not in cache, loading from network');
      }
    }

    // Only set loading if we didn't use cache
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final employees = await hrService.getEmployees();
      final departments = await hrService.getDepartments(activeOnly: false);

      if (!mounted) return;

      final employee = employees.firstWhere(
        (e) => e.id == widget.employeeId,
        orElse: () => throw Exception('Empleado no encontrado'),
      );

      _populateFields(employee, departments);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _populateFields(Employee employee, List<Department> departments) {
    _firstNameController.text = employee.firstName;
    _lastNameController.text = employee.lastName;
    _employeeNumberController.text = employee.employeeNumber;
    _emailController.text = employee.email ?? '';
    _phoneController.text = employee.phone ?? '';
    _rutController.text = employee.rut ?? '';
    _jobTitleController.text = employee.jobTitle;
    _addressController.text = employee.address ?? '';
    _cityController.text = employee.city ?? '';
    _emergencyContactNameController.text = employee.emergencyContactName ?? '';
    _emergencyContactPhoneController.text =
        employee.emergencyContactPhone ?? '';
    _notesController.text = employee.notes ?? '';
    // Salary fields
    _hourlyRateController.text = employee.hourlyRate?.toString() ?? '';
    _bankNameController.text = employee.bankName ?? '';
    _bankAccountNumberController.text = employee.bankAccountNumber ?? '';

    // Update state variables
    _employee = employee;
    _departments = departments;
    _departmentId = employee.departmentId;
    _selectedSystemRole = employee.systemRole;
    _employmentType = employee.employmentType;
    _status = employee.status;
    _birthDate = employee.birthDate;
    _hireDate = employee.hireDate;
    _paymentMethod = employee.preferredPaymentMethod ?? PaymentMethod.transfer;
    _bankAccountType = employee.bankAccountType;

    // Load hours summary in background
    _loadHoursSummary();
  }

  // Basic Date Calculations
  DateTimeRange _calculateWeekRange(DateTime date) {
    // Week starts on Monday
    final daysFromMonday = date.weekday - 1;
    final start = date.subtract(Duration(days: daysFromMonday));
    final startOfDay = DateTime(start.year, start.month, start.day);
    final end = startOfDay.add(const Duration(days: 6));
    // Set end to end of day
    final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    return DateTimeRange(start: startOfDay, end: endOfDay);
  }

  DateTimeRange _calculateMonthRange(DateTime date) {
    final start = DateTime(date.year, date.month, 1);
    final end = DateTime(date.year, date.month + 1, 0, 23, 59, 59);
    return DateTimeRange(start: start, end: end);
  }

  void _updateDateRange(DateTime anchorDate) {
    if (_filterType == DateFilterType.weekly) {
      _dateRange = _calculateWeekRange(anchorDate);
    } else if (_filterType == DateFilterType.monthly) {
      _dateRange = _calculateMonthRange(anchorDate);
    }
    // Custom range updates happen via picker
    _loadHoursSummary();
  }

  void _onNavigate(int offset) {
    if (_filterType == DateFilterType.custom) return; // No nav for custom

    DateTime newAnchor;
    if (_filterType == DateFilterType.weekly) {
      newAnchor = _dateRange.start.add(Duration(days: offset * 7));
    } else {
      // Monthly navigation
      newAnchor =
          DateTime(_dateRange.start.year, _dateRange.start.month + offset, 1);
    }

    setState(() {
      _updateDateRange(newAnchor);
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
      locale: const Locale('es', 'ES'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                ColorScheme.light(primary: Theme.of(context).primaryColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _filterType = DateFilterType.custom;
        // Ensure end date includes the full day
        _dateRange = DateTimeRange(
            start: picked.start,
            end: DateTime(
                picked.end.year, picked.end.month, picked.end.day, 23, 59, 59));
      });
      _loadHoursSummary();
    }
  }

  Future<void> _loadHoursSummary() async {
    if (_employee?.id == null) return;
    setState(() => _isLoadingHours = true);
    try {
      final hrService = context.read<HRService>();

      final summary = await hrService.getEmployeeHoursSummary(
        _employee!.id!,
        _dateRange.start,
        _dateRange.end,
      );

      if (mounted) {
        setState(() {
          _hoursSummary = summary;
          _isLoadingHours = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading hours summary: $e');
      if (mounted) setState(() => _isLoadingHours = false);
    }
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final hrService = context.read<HRService>();

      final updatedEmployee = Employee(
        id: _employee!.id,
        tenantId: _employee!.tenantId,
        userId: _employee!.userId,
        employeeNumber: _employeeNumberController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email:
            _emailController.text.isEmpty ? null : _emailController.text.trim(),
        phone:
            _phoneController.text.isEmpty ? null : _phoneController.text.trim(),
        rut: _rutController.text.isEmpty ? null : _rutController.text.trim(),
        birthDate: _birthDate,
        hireDate: _hireDate,
        departmentId: _departmentId,
        jobTitle: _jobTitleController.text.trim(),
        systemRole: _selectedSystemRole,
        employmentType: _employmentType,
        status: _status,
        photoUrl: _employee!.photoUrl,
        address: _addressController.text.isEmpty
            ? null
            : _addressController.text.trim(),
        city: _cityController.text.isEmpty ? null : _cityController.text.trim(),
        emergencyContactName: _emergencyContactNameController.text.isEmpty
            ? null
            : _emergencyContactNameController.text.trim(),
        emergencyContactPhone: _emergencyContactPhoneController.text.isEmpty
            ? null
            : _emergencyContactPhoneController.text.trim(),
        notes:
            _notesController.text.isEmpty ? null : _notesController.text.trim(),
        // Salary fields
        hourlyRate: _hourlyRateController.text.isEmpty
            ? null
            : double.tryParse(_hourlyRateController.text),
        preferredPaymentMethod: _paymentMethod,
        bankName: _bankNameController.text.isEmpty
            ? null
            : _bankNameController.text.trim(),
        bankAccountNumber: _bankAccountNumberController.text.isEmpty
            ? null
            : _bankAccountNumberController.text.trim(),
        bankAccountType: _bankAccountType,
      );

      await hrService.updateEmployee(updatedEmployee);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Perfil actualizado'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _employee = updatedEmployee);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectDate(BuildContext context,
      {required bool isBirthDate}) async {
    final initialDate =
        isBirthDate ? (_birthDate ?? DateTime(1990)) : _hireDate;
    final firstDate = DateTime(1950);
    final lastDate = DateTime.now().add(const Duration(days: 365));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isBirthDate) {
          _birthDate = picked;
        } else {
          _hireDate = picked;
        }
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Seleccionar fecha';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Color _getStatusColor(EmployeeStatus status) {
    switch (status) {
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

  String _getStatusLabel(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.active:
        return 'Activo';
      case EmployeeStatus.inactive:
        return 'Inactivo';
      case EmployeeStatus.onLeave:
        return 'Licencia';
      case EmployeeStatus.terminated:
        return 'Desvinculado';
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        '🔵 [EmployeeDetailPage] build called - isLoading: $_isLoading, hasError: ${_error != null}, hasEmployee: ${_employee != null}');
    final theme = Theme.of(context);

    return MainLayout(
      title: 'Perfil de Empleado',
      body: _isLoading
          ? const Center(child: BrandedLoading())
          : _error != null
              ? _buildErrorState(context)
              : _buildContent(context, theme),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_error!),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.go('/hr/employees'),
            child: const Text('Volver'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Top Toolbar with Back Button & Save Action
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.go('/hr/employees'),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Volver a lista',
                ),
                const SizedBox(width: 8),
                Text(
                  'Perfil de Empleado',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                AppButton(
                  text: 'Guardar',
                  icon: Icons.check,
                  onPressed: _saveEmployee,
                  isLoading: _isSaving,
                  type: ButtonType.primary,
                ),
              ],
            ),
          ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 900;

                if (isMobile) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildIdentityCard(theme),
                        const SizedBox(height: 16),
                        _buildTabs(theme),
                        const SizedBox(height: 16),
                        SizedBox(
                          height:
                              600, // Explicit height for TabBarView in ScrollView
                          child: _buildTabViews(theme),
                        ),
                      ],
                    ),
                  );
                }

                // Desktop Layout: Sidebar + Content
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sidebar (Identity)
                    SizedBox(
                      width: 320,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: _buildIdentityCard(theme),
                      ),
                    ),
                    VerticalDivider(width: 1, color: theme.dividerColor),
                    // Main Content Area
                    Expanded(
                      child: Column(
                        children: [
                          _buildTabs(theme),
                          Expanded(child: _buildTabViews(theme)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(ThemeData theme) {
    return Column(
      children: [
        // Avatar Section
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _employee?.initials ?? '?',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: theme.cardColor, width: 2),
              ),
              child:
                  const Icon(Icons.camera_alt, size: 16, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Name & Role
        Text(
          _employee?.fullName ?? '',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _jobTitleController.text.isNotEmpty
              ? _jobTitleController.text
              : 'Sin cargo',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          _employee?.employeeNumber ?? '',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.hintColor,
          ),
        ),

        const SizedBox(height: 24),

        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _getStatusColor(_status).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: _getStatusColor(_status).withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 10, color: _getStatusColor(_status)),
              const SizedBox(width: 8),
              Text(
                _getStatusLabel(_status),
                style: TextStyle(
                  color: _getStatusColor(_status),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),

        // Contact Stats
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickAction(theme, Icons.email_outlined, 'Email', () {}),
            _buildQuickAction(theme, Icons.phone_outlined, 'Llamar', () {}),
            _buildQuickAction(theme, Icons.chat_bubble_outline, 'Chat', () {}),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAction(
      ThemeData theme, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: theme.primaryColor,
        unselectedLabelColor: theme.hintColor,
        indicatorColor: theme.primaryColor,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        isScrollable: false,
        tabs: const [
          Tab(text: 'Información Personal'),
          Tab(text: 'Información Laboral'),
          Tab(text: 'Notas & Otros'),
          Tab(text: 'Salario y Horas'),
        ],
      ),
    );
  }

  Widget _buildTabViews(ThemeData theme) {
    return TabBarView(
      physics: const NeverScrollableScrollPhysics(),
      controller: _tabController,
      children: [
        _buildPersonalTab(theme),
        _buildEmploymentTab(theme),
        _buildNotesTab(theme),
        _buildSalaryHoursTab(theme),
      ],
    );
  }

  Widget _buildPersonalTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, 'Datos Básicos'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                  child: _buildTextField(
                      _firstNameController, 'Nombres', Icons.person)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildTextField(
                      _lastNameController, 'Apellidos', Icons.person_outline)),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(_rutController, 'RUT', Icons.badge),
          const SizedBox(height: 16),
          _buildDateField(context, 'Fecha de Nacimiento', _birthDate, true),
          const SizedBox(height: 40),
          _buildSectionHeader(theme, 'Información de Contacto'),
          const SizedBox(height: 24),
          _buildTextField(_emailController, 'Correo Electrónico', Icons.email),
          const SizedBox(height: 16),
          _buildTextField(_phoneController, 'Teléfono', Icons.phone),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  flex: 2,
                  child: _buildTextField(
                      _addressController, 'Dirección', Icons.location_on)),
              const SizedBox(width: 16),
              Expanded(
                  flex: 1,
                  child: _buildTextField(
                      _cityController, 'Ciudad', Icons.location_city)),
            ],
          ),
          const SizedBox(height: 40),
          _buildSectionHeader(theme, 'Contacto de Emergencia'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                  child: _buildTextField(_emergencyContactNameController,
                      'Nombre', Icons.person_add)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildTextField(_emergencyContactPhoneController,
                      'Teléfono', Icons.phone_callback)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmploymentTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, 'Detalles del Cargo'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                  child: _buildTextField(
                      _jobTitleController, 'Cargo / Puesto', Icons.work)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildTextField(
                      _employeeNumberController, 'No. Empleado', Icons.numbers,
                      enabled: false)),
            ],
          ),
          const SizedBox(height: 16),
          _buildDepartmentDropdown(),
          const SizedBox(height: 40),
          _buildSectionHeader(theme, 'Contrato y Estado'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildEmploymentTypeDropdown()),
              const SizedBox(width: 16),
              Expanded(child: _buildStatusDropdown()),
            ],
          ),
          const SizedBox(height: 16),
          _buildDateField(context, 'Fecha de Contratación', _hireDate, false),
        ],
      ),
    );
  }

  Widget _buildNotesTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(theme, 'Notas Internas'),
          const SizedBox(height: 8),
          Text(
            'Información privada visible solo para administradores.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 24),
          _buildTextField(_notesController, 'Notas adicionales', Icons.note,
              maxLines: 8),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, {Widget? action}) {
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Divider(
            color: theme.dividerColor,
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 16),
          action,
        ],
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool enabled = true,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
        filled: !enabled,
        fillColor: enabled ? null : Colors.grey.withOpacity(0.05),
      ),
      validator: (value) {
        if (enabled && (value == null || value.isEmpty)) {
          // Add specific field logic if needed, currently loose validation
          if (controller == _firstNameController ||
              controller == _lastNameController ||
              controller == _jobTitleController) {
            return 'Campo requerido';
          }
        }
        return null;
      },
    );
  }

  Widget _buildDateField(
      BuildContext context, String label, DateTime? date, bool isBirthDate) {
    return InkWell(
      onTap: () => _selectDate(context, isBirthDate: isBirthDate),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
          ),
        ),
        child: Text(
          _formatDate(date),
          style: TextStyle(
            color: date == null ? Colors.grey : null,
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentDropdown() {
    return DropdownButtonFormField<String?>(
      value: _departmentId,
      decoration: InputDecoration(
        labelText: 'Departamento',
        prefixIcon: const Icon(Icons.business, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Sin departamento')),
        ..._departments
            .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))),
      ],
      onChanged: (value) => setState(() => _departmentId = value),
    );
  }

  Widget _buildEmploymentTypeDropdown() {
    return DropdownButtonFormField<EmploymentType>(
      value: _employmentType,
      decoration: InputDecoration(
        labelText: 'Tipo de Contrato',
        prefixIcon: const Icon(Icons.assignment_ind, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
      ),
      items: const [
        DropdownMenuItem(
            value: EmploymentType.fullTime, child: Text('Tiempo completo')),
        DropdownMenuItem(
            value: EmploymentType.partTime, child: Text('Medio tiempo')),
        DropdownMenuItem(
            value: EmploymentType.contractor, child: Text('Contratista')),
        DropdownMenuItem(
            value: EmploymentType.intern, child: Text('Practicante')),
      ],
      onChanged: (value) => setState(() => _employmentType = value!),
    );
  }

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<EmployeeStatus>(
      value: _status,
      decoration: InputDecoration(
        labelText: 'Estado',
        prefixIcon: const Icon(Icons.flag, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
      ),
      items: const [
        DropdownMenuItem(value: EmployeeStatus.active, child: Text('Activo')),
        DropdownMenuItem(
            value: EmployeeStatus.inactive, child: Text('Inactivo')),
        DropdownMenuItem(
            value: EmployeeStatus.onLeave, child: Text('Licencia')),
        DropdownMenuItem(
            value: EmployeeStatus.terminated, child: Text('Desvinculado')),
      ],
      onChanged: (value) => setState(() => _status = value!),
    );
  }

  // ============================================================================
  // SALARY & HOURS TAB
  // ============================================================================
  // ============================================================================
  // SALARY & HOURS TAB (Refined Professional UI)
  // ============================================================================
  Widget _buildSalaryHoursTab(ThemeData theme) {
    final currencyFormat = NumberFormat.currency(locale: 'es_CL', symbol: '\$');
    final monthFormat = DateFormat('MMMM yyyy', 'es_ES');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Advanced Filter Bar & Summary Header
          _buildDateFilterBar(theme, monthFormat),
          const SizedBox(height: 16),

          if (_isLoadingHours)
            LinearProgressIndicator(
              backgroundColor: theme.dividerColor.withOpacity(0.1),
              minHeight: 2,
            ),

          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _isLoadingHours ? 0.5 : 1.0,
            child: _hoursSummary == null
                // Initial empty state (or if fetch fails/returns null)
                ? Container(
                    height: 200,
                    alignment: Alignment.center,
                    child: Text(
                      'Selecciona un rango para ver la asistencia',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  )
                : _buildProfessionalSummary(theme, currencyFormat),
          ),

          const SizedBox(height: 32),

          // 2. Payment Configuration (Compact)
          _buildSectionHeader(theme, 'Configuración de Pago'),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _hourlyRateController,
                          'Tarifa por Hora',
                          Icons.attach_money,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildPaymentMethodDropdown(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          _bankNameController,
                          'Banco',
                          Icons.account_balance,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildBankAccountTypeDropdown(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _bankAccountNumberController,
                    'N° Cuenta',
                    Icons.credit_card,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterBar(ThemeData theme, DateFormat monthFormat) {
    String rangeLabel = '';

    if (_filterType == DateFilterType.weekly) {
      final start = DateFormat('d MMM', 'es_ES').format(_dateRange.start);
      final end = DateFormat('d MMM', 'es_ES').format(_dateRange.end);
      rangeLabel = '$start - $end';
    } else if (_filterType == DateFilterType.monthly) {
      rangeLabel = monthFormat.format(_dateRange.start).toUpperCase();
    } else {
      final start = DateFormat('d/M/yy').format(_dateRange.start);
      final end = DateFormat('d/M/yy').format(_dateRange.end);
      rangeLabel = '$start - $end';
    }

    return Column(
      children: [
        _buildSectionHeader(
          theme,
          'Resumen de Asistencia',
          action: Container(
            height: 32,
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: ToggleButtons(
              isSelected: [
                _filterType == DateFilterType.weekly,
                _filterType == DateFilterType.monthly,
                _filterType == DateFilterType.custom,
              ],
              onPressed: (index) {
                setState(() {
                  _filterType = DateFilterType.values[index];
                  if (_filterType == DateFilterType.weekly) {
                    _updateDateRange(
                        DateTime.now()); // Weekly always jumps to Now
                  } else if (_filterType == DateFilterType.monthly) {
                    _updateDateRange(_dateRange.start); // Keep current anchor
                  } else {
                    _pickCustomRange();
                  }
                });
              },
              borderRadius: BorderRadius.circular(7),
              constraints: const BoxConstraints(minHeight: 30, minWidth: 60),
              selectedColor: theme.primaryColor,
              fillColor: theme.primaryColor.withOpacity(0.1),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              children: const [
                Text('Semana'),
                Text('Mes'),
                Text('Rango'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Navigation Bar
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _filterType == DateFilterType.custom
                    ? null
                    : () => _onNavigate(-1),
                tooltip: 'Anterior',
                color:
                    _filterType == DateFilterType.custom ? Colors.grey : null,
              ),
              InkWell(
                onTap: _pickCustomRange,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 16, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        rangeLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _filterType == DateFilterType.custom
                    ? null
                    : () => _onNavigate(1),
                tooltip: 'Siguiente',
                color:
                    _filterType == DateFilterType.custom ? Colors.grey : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfessionalSummary(
      ThemeData theme, NumberFormat currencyFormat) {
    final summary = _hoursSummary!;
    final hourlyRate = double.tryParse(_hourlyRateController.text) ?? 0;

    // Calculate total estimate
    final baseEarnings = summary.estimatedEarnings(hourlyRate);
    final overtimeBonus = summary.overtimeEarnings(hourlyRate);
    final totalEstimate = baseEarnings + overtimeBonus;

    return Column(
      children: [
        // Top KPI Row (Monochromatic, Data-Dense)
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                theme,
                label: 'HORAS TOTALES',
                value: '${summary.totalHours.toStringAsFixed(1)}',
                sublabel: 'hrs',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                theme,
                label: 'HORAS EXTRA',
                value: '${summary.totalOvertime.toStringAsFixed(1)}',
                sublabel: 'hrs',
                isHighlight: summary.totalOvertime > 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                theme,
                label: 'DÍAS TRABAJADOS',
                value: '${summary.totalDaysWorked}',
                sublabel: 'días',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Performance Grid (Table-like)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.dividerColor),
          ),
          child: Column(
            children: [
              _buildDataRow(theme, 'Promedio Diario',
                  '${summary.averageHoursPerDay.toStringAsFixed(1)} horas'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDataRow(theme, 'Puntualidad',
                  '${summary.attendanceScore.toStringAsFixed(0)}%'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDataRow(theme, 'Días Perfectos (8h+)',
                  '${summary.perfectAttendanceDays} días'),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDataRow(
                  theme, 'Llegadas Tarde', '${summary.lateArrivals} días',
                  isWarning: summary.lateArrivals > 0),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildDataRow(
                  theme, 'Salidas Tempranas', '${summary.earlyDepartures} días',
                  isWarning: summary.earlyDepartures > 0),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Financial Estimate (Clean, Professional)
        if (hourlyRate > 0)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color:
                  Colors.grey.withOpacity(0.05), // Very light grey background
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROYECCIÓN DE SUELDO',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.hintColor,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'Base (${summary.totalHours.toStringAsFixed(1)}h × ${currencyFormat.format(hourlyRate)}/h)'),
                    Text(currencyFormat.format(baseEarnings),
                        style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
                if (overtimeBonus > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Horas Extra (x1.5)',
                          style: TextStyle(color: Colors.green[700])),
                      Text('+ ${currencyFormat.format(overtimeBonus)}',
                          style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Estimado',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(
                      currencyFormat.format(totalEstimate),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildKpiCard(
    ThemeData theme, {
    required String label,
    required String value,
    required String sublabel,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.hintColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isHighlight
                      ? theme.primaryColor
                      : theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                sublabel,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(ThemeData theme, String label, String value,
      {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: isWarning ? Colors.red[700] : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodDropdown() {
    return DropdownButtonFormField<PaymentMethod>(
      value: _paymentMethod,
      decoration: InputDecoration(
        labelText: 'Método de Pago',
        prefixIcon: const Icon(Icons.payment, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
      ),
      items: const [
        DropdownMenuItem(
            value: PaymentMethod.transfer, child: Text('Transferencia')),
        DropdownMenuItem(value: PaymentMethod.cash, child: Text('Efectivo')),
        DropdownMenuItem(value: PaymentMethod.check, child: Text('Cheque')),
      ],
      onChanged: (value) => setState(() => _paymentMethod = value!),
    );
  }

  Widget _buildBankAccountTypeDropdown() {
    return DropdownButtonFormField<BankAccountType?>(
      value: _bankAccountType,
      decoration: InputDecoration(
        labelText: 'Tipo de Cuenta',
        prefixIcon: const Icon(Icons.account_balance_wallet, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
      ),
      items: const [
        DropdownMenuItem(value: null, child: Text('Sin especificar')),
        DropdownMenuItem(
            value: BankAccountType.checking, child: Text('Cuenta Corriente')),
        DropdownMenuItem(
            value: BankAccountType.savings, child: Text('Cuenta Ahorro')),
        DropdownMenuItem(
            value: BankAccountType.vista, child: Text('Cuenta Vista')),
      ],
      onChanged: (value) => setState(() => _bankAccountType = value),
    );
  }
}
