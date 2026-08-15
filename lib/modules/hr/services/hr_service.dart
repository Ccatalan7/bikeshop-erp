// HR Service for Vinabike ERP
// Handles all HR operations: employees, departments, contracts, schedules, and attendances

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/hr_models.dart';

class EmployeeRetirementResult {
  const EmployeeRetirementResult({
    required this.employeeId,
    required this.alreadyRetired,
  });

  final String employeeId;
  final bool alreadyRetired;

  factory EmployeeRetirementResult.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid employee retirement response');
    }

    final data = Map<String, dynamic>.from(value);
    final employeeId = data['employeeId'];
    final alreadyRetired = data['alreadyRetired'];
    if (data['success'] != true ||
        data['retired'] != true ||
        employeeId is! String ||
        employeeId.isEmpty ||
        alreadyRetired is! bool) {
      throw const FormatException('Invalid employee retirement response');
    }

    return EmployeeRetirementResult(
      employeeId: employeeId,
      alreadyRetired: alreadyRetired,
    );
  }
}

class EmployeeRetirementException implements Exception {
  const EmployeeRetirementException(this.message);

  final String message;

  factory EmployeeRetirementException.fromBackendEvidence(String evidence) {
    final normalized = evidence.toLowerCase();
    if (normalized.contains('employee_not_found')) {
      return const EmployeeRetirementException(
        'El trabajador ya no está disponible en este negocio.',
      );
    }
    if (normalized.contains('self_detach_forbidden')) {
      return const EmployeeRetirementException(
        'No puedes desvincular tu propio registro laboral.',
      );
    }
    if (normalized.contains('staff_hierarchy_forbidden') ||
        normalized.contains('principal_owner_protected') ||
        normalized.contains('employee_retirement_denied')) {
      return const EmployeeRetirementException(
        'No tienes permisos para desvincular a este trabajador.',
      );
    }
    return const EmployeeRetirementException(
      'No se pudo desvincular al trabajador. Inténtalo nuevamente.',
    );
  }
}

class HRService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  final TenantService _tenantService;

  HRService(this._tenantService);

  // ============================================================
  // CACHING - TTL-based cache for performance optimization
  // ============================================================
  List<Employee> _employeesCache = [];
  List<Department> _departmentsCache = [];
  DateTime? _employeesCacheTime;
  DateTime? _departmentsCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);
  bool _isLoadingEmployees = false;
  bool _isLoadingDepartments = false;

  // Public getters for cached data (instant UI access)
  List<Employee> get cachedEmployees => List.unmodifiable(_employeesCache);
  List<Department> get cachedDepartments =>
      List.unmodifiable(_departmentsCache);
  bool get hasEmployeesCache =>
      _employeesCache.isNotEmpty && _employeesCacheTime != null;
  bool get hasDepartmentsCache =>
      _departmentsCache.isNotEmpty && _departmentsCacheTime != null;

  /// Check if cache is still valid
  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  /// Invalidate employee cache (call after create/update/delete)
  void invalidateEmployeesCache() {
    _employeesCacheTime = null;
    debugPrint('🗑️ [HRService] Employees cache invalidated');
  }

  /// Invalidate department cache (call after create/update/delete)
  void invalidateDepartmentsCache() {
    _departmentsCacheTime = null;
    debugPrint('🗑️ [HRService] Departments cache invalidated');
  }

  // ============================================================================
  // DEPARTMENTS
  // ============================================================================

  Future<List<Department>> getDepartments(
      {bool activeOnly = true, bool forceRefresh = false}) async {
    // Return cached data if valid (for non-filtered queries)
    if (!forceRefresh &&
        !activeOnly &&
        _isCacheValid(_departmentsCacheTime) &&
        _departmentsCache.isNotEmpty) {
      debugPrint(
          '📦 [HRService] Using cached departments (${_departmentsCache.length} items)');
      return _departmentsCache;
    }

    if (_isLoadingDepartments && !activeOnly) {
      while (_isLoadingDepartments) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_departmentsCache.isNotEmpty && !activeOnly) return _departmentsCache;
    }

    try {
      if (!activeOnly) _isLoadingDepartments = true;

      var query = _client.from('departments').select();

      if (activeOnly) {
        query = query.eq('active', true);
      }

      final response = await query.order('name');
      final departments =
          (response as List).map((json) => Department.fromMap(json)).toList();

      // Cache only non-filtered queries
      if (!activeOnly) {
        _departmentsCache = departments;
        _departmentsCacheTime = DateTime.now();
        debugPrint('✅ [HRService] Cached ${departments.length} departments');
      }

      return departments;
    } catch (e) {
      debugPrint('Error getting departments: $e');
      rethrow;
    } finally {
      if (!activeOnly) _isLoadingDepartments = false;
    }
  }

  Future<Department?> getDepartmentById(String id) async {
    try {
      final response =
          await _client.from('departments').select().eq('id', id).single();
      return Department.fromMap(response);
    } catch (e) {
      debugPrint('Error getting department: $e');
      return null;
    }
  }

  Future<Department> createDepartment(Department department) async {
    try {
      final response = await _client
          .from('departments')
          .insert(department.toMap())
          .select()
          .single();
      invalidateDepartmentsCache();
      notifyListeners();
      return Department.fromMap(response);
    } catch (e) {
      debugPrint('Error creating department: $e');
      rethrow;
    }
  }

  Future<Department> updateDepartment(Department department) async {
    try {
      final response = await _client
          .from('departments')
          .update(department.toMap())
          .eq('id', department.id!)
          .select()
          .single();
      invalidateDepartmentsCache();
      notifyListeners();
      return Department.fromMap(response);
    } catch (e) {
      debugPrint('Error updating department: $e');
      rethrow;
    }
  }

  Future<void> deleteDepartment(String id) async {
    try {
      await _client.from('departments').delete().eq('id', id);
      invalidateDepartmentsCache();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting department: $e');
      rethrow;
    }
  }

  // ============================================================================
  // EMPLOYEES
  // ============================================================================

  Future<List<Employee>> getEmployees({
    EmployeeStatus? status,
    String? departmentId,
    String? searchQuery,
    bool forceRefresh = false,
  }) async {
    // Check if this is a filtered query
    final isFilteredQuery = status != null ||
        departmentId != null ||
        (searchQuery != null && searchQuery.isNotEmpty);

    // Return cached data if valid and not a filtered query
    if (!forceRefresh &&
        !isFilteredQuery &&
        _isCacheValid(_employeesCacheTime) &&
        _employeesCache.isNotEmpty) {
      debugPrint(
          '📦 [HRService] Using cached employees (${_employeesCache.length} items)');
      return _employeesCache;
    }

    if (_isLoadingEmployees && !isFilteredQuery) {
      while (_isLoadingEmployees) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_employeesCache.isNotEmpty && !isFilteredQuery) {
        return _employeesCache;
      }
    }

    try {
      if (!isFilteredQuery) _isLoadingEmployees = true;

      var query = _client.from('employees').select();

      if (status != null) {
        query = query.eq('status', status.name);
      }

      if (departmentId != null) {
        query = query.eq('department_id', departmentId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
            'first_name.ilike.%$searchQuery%,last_name.ilike.%$searchQuery%,employee_number.ilike.%$searchQuery%,rut.ilike.%$searchQuery%');
      }

      final response = await query.order('last_name').order('first_name');
      final employees =
          (response as List).map((json) => Employee.fromMap(json)).toList();

      // Cache only non-filtered queries
      if (!isFilteredQuery) {
        _employeesCache = employees;
        _employeesCacheTime = DateTime.now();
        debugPrint('✅ [HRService] Cached ${employees.length} employees');
      }

      return employees;
    } catch (e) {
      debugPrint('Error getting employees: $e');
      rethrow;
    } finally {
      if (!isFilteredQuery) _isLoadingEmployees = false;
    }
  }

  Future<Employee?> getEmployeeById(String id) async {
    try {
      final response =
          await _client.from('employees').select().eq('id', id).single();
      return Employee.fromMap(response);
    } catch (e) {
      debugPrint('Error getting employee: $e');
      return null;
    }
  }

  Future<Employee?> getEmployeeByUserId(String userId) async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return response != null ? Employee.fromMap(response) : null;
    } catch (e) {
      debugPrint('Error getting employee by user ID: $e');
      return null;
    }
  }

  Future<Employee> createEmployee(Employee employee) async {
    try {
      // Add tenant_id to employee data
      final employeeData = _tenantService.addTenantId(employee.toMap());
      final response = await _client
          .from('employees')
          .insert(employeeData)
          .select()
          .single();
      invalidateEmployeesCache();
      notifyListeners();
      return Employee.fromMap(response);
    } catch (e) {
      debugPrint('Error creating employee: $e');
      rethrow;
    }
  }

  Future<Employee> updateEmployee(Employee employee) async {
    try {
      final response = await _client
          .from('employees')
          .update(employee.toMap())
          .eq('id', employee.id!)
          .select()
          .single();
      invalidateEmployeesCache();
      notifyListeners();
      return Employee.fromMap(response);
    } catch (e) {
      debugPrint('Error updating employee: $e');
      rethrow;
    }
  }

  Future<EmployeeRetirementResult> retireEmployee(String id) async {
    try {
      final response = await _client.rpc(
        'retire_employee',
        params: {'p_employee_id': id},
      );
      final result = EmployeeRetirementResult.fromJson(response);
      if (result.employeeId != id) {
        throw const FormatException('Employee retirement identity mismatch');
      }
      invalidateEmployeesCache();
      notifyListeners();
      return result;
    } on PostgrestException catch (error) {
      debugPrint(
        'Employee retirement rejected (${error.code ?? 'unknown code'})',
      );
      throw EmployeeRetirementException.fromBackendEvidence(
        '${error.code} ${error.message} ${error.details} ${error.hint}',
      );
    } catch (e) {
      debugPrint('Error retiring employee: $e');
      if (e is EmployeeRetirementException) rethrow;
      throw const EmployeeRetirementException(
        'No se pudo desvincular al trabajador. Inténtalo nuevamente.',
      );
    }
  }

  /// Get salary accounts (accounts starting with 6101 - Sueldos y Salarios)
  Future<List<Map<String, dynamic>>> getSalaryAccounts() async {
    try {
      final response = await _client
          .from('accounts')
          .select('id, code, name')
          .like('code', '6101%')
          .order('code');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting salary accounts: $e');
      return [];
    }
  }

  /// Get available payment methods
  Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    try {
      final response = await _client
          .from('payment_methods')
          .select()
          .eq('is_active', true)
          .inFilter('usage_scope', const ['outbound', 'both']).order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting payment methods: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPlanningRoles() async {
    try {
      final response = await _client
          .from('planning_roles')
          .select('id, code, name, color')
          .eq('is_active', true)
          .order('sort_order')
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting planning roles: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getEmployeeDefaultShiftBlocks(
    String employeeId,
  ) async {
    try {
      final response = await _client
          .from('employee_default_shift_blocks')
          .select('''
            id,
            employee_id,
            planning_role_id,
            day_of_week,
            start_time,
            end_time,
            timezone,
            source,
            store_hours_validated,
            outside_store_hours_reason,
            planning_roles(name, color)
          ''')
          .eq('employee_id', employeeId)
          .eq('is_active', true)
          .order('day_of_week')
          .order('start_time');

      return (response as List).whereType<Map>().map((row) {
        final map = Map<String, dynamic>.from(row);
        final role = map['planning_roles'] is Map
            ? Map<String, dynamic>.from(map['planning_roles'] as Map)
            : const <String, dynamic>{};
        return {
          'id': map['id']?.toString(),
          'employeeId': map['employee_id']?.toString(),
          'planningRoleId': map['planning_role_id']?.toString(),
          'planningRoleName': role['name']?.toString(),
          'planningRoleColor': role['color']?.toString(),
          'dayOfWeek': (map['day_of_week'] as num?)?.toInt(),
          'startTime': map['start_time']?.toString(),
          'endTime': map['end_time']?.toString(),
          'timezone': map['timezone']?.toString() ?? 'America/Santiago',
          'source': map['source']?.toString(),
          'storeHoursValidated': map['store_hours_validated'] == true,
          'outsideStoreHoursReason':
              map['outside_store_hours_reason']?.toString(),
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting default shift blocks: $e');
      rethrow;
    }
  }

  Future<void> replaceEmployeeDefaultShiftBlocks({
    required String employeeId,
    required List<Map<String, dynamic>> blocks,
  }) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) throw Exception('No se encontro la tienda actual');

    try {
      await _client
          .from('employee_default_shift_blocks')
          .update({
            'is_active': false,
            'updated_by': _client.auth.currentUser?.id,
          })
          .eq('tenant_id', tenantId)
          .eq('employee_id', employeeId)
          .eq('is_active', true);

      if (blocks.isEmpty) {
        notifyListeners();
        return;
      }

      final rows = blocks.map((block) {
        final roleId = block['planningRoleId']?.toString().trim();
        return {
          'tenant_id': tenantId,
          'employee_id': employeeId,
          if (roleId != null && roleId.isNotEmpty) 'planning_role_id': roleId,
          'day_of_week': block['dayOfWeek'],
          'start_time': block['startTime'],
          'end_time': block['endTime'],
          'timezone': block['timezone'] ?? 'America/Santiago',
          'source': 'profile',
          'is_active': true,
          'store_hours_validated': false,
          'updated_by': _client.auth.currentUser?.id,
        };
      }).toList();

      await _client.from('employee_default_shift_blocks').insert(rows);
      notifyListeners();
    } catch (e) {
      debugPrint('Error replacing default shift blocks: $e');
      rethrow;
    }
  }

  // ============================================================================
  // WORK SCHEDULES
  // ============================================================================

  Future<List<WorkSchedule>> getWorkSchedules({bool activeOnly = true}) async {
    try {
      var query = _client.from('work_schedules').select();

      if (activeOnly) {
        query = query.eq('active', true);
      }

      final response = await query.order('name');
      return (response as List)
          .map((json) => WorkSchedule.fromMap(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting work schedules: $e');
      rethrow;
    }
  }

  Future<WorkSchedule?> getWorkScheduleById(String id) async {
    try {
      final response =
          await _client.from('work_schedules').select().eq('id', id).single();
      return WorkSchedule.fromMap(response);
    } catch (e) {
      debugPrint('Error getting work schedule: $e');
      return null;
    }
  }

  Future<WorkSchedule> createWorkSchedule(WorkSchedule schedule) async {
    try {
      final response = await _client
          .from('work_schedules')
          .insert(schedule.toMap())
          .select()
          .single();
      notifyListeners();
      return WorkSchedule.fromMap(response);
    } catch (e) {
      debugPrint('Error creating work schedule: $e');
      rethrow;
    }
  }

  Future<WorkSchedule> updateWorkSchedule(WorkSchedule schedule) async {
    try {
      final response = await _client
          .from('work_schedules')
          .update(schedule.toMap())
          .eq('id', schedule.id!)
          .select()
          .single();
      notifyListeners();
      return WorkSchedule.fromMap(response);
    } catch (e) {
      debugPrint('Error updating work schedule: $e');
      rethrow;
    }
  }

  Future<void> deleteWorkSchedule(String id) async {
    try {
      await _client.from('work_schedules').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting work schedule: $e');
      rethrow;
    }
  }

  // ============================================================================
  // CONTRACTS
  // ============================================================================

  Future<List<EmployeeContract>> getContracts({
    String? employeeId,
    ContractStatus? status,
  }) async {
    try {
      var query = _client.from('employee_contracts').select();

      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
      }

      if (status != null) {
        query = query.eq('status', status.name);
      }

      final response = await query.order('start_date', ascending: false);
      return (response as List)
          .map((json) => EmployeeContract.fromMap(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting contracts: $e');
      rethrow;
    }
  }

  Future<EmployeeContract?> getContractById(String id) async {
    try {
      final response = await _client
          .from('employee_contracts')
          .select()
          .eq('id', id)
          .single();
      return EmployeeContract.fromMap(response);
    } catch (e) {
      debugPrint('Error getting contract: $e');
      return null;
    }
  }

  Future<EmployeeContract?> getActiveContract(String employeeId) async {
    try {
      final response = await _client
          .from('employee_contracts')
          .select()
          .eq('employee_id', employeeId)
          .eq('status', 'active')
          .maybeSingle();
      return response != null ? EmployeeContract.fromMap(response) : null;
    } catch (e) {
      debugPrint('Error getting active contract: $e');
      return null;
    }
  }

  Future<EmployeeContract> createContract(EmployeeContract contract) async {
    try {
      final response = await _client
          .from('employee_contracts')
          .insert(contract.toMap())
          .select()
          .single();
      notifyListeners();
      return EmployeeContract.fromMap(response);
    } catch (e) {
      debugPrint('Error creating contract: $e');
      rethrow;
    }
  }

  Future<EmployeeContract> updateContract(EmployeeContract contract) async {
    try {
      final response = await _client
          .from('employee_contracts')
          .update(contract.toMap())
          .eq('id', contract.id!)
          .select()
          .single();
      notifyListeners();
      return EmployeeContract.fromMap(response);
    } catch (e) {
      debugPrint('Error updating contract: $e');
      rethrow;
    }
  }

  Future<void> deleteContract(String id) async {
    try {
      await _client.from('employee_contracts').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting contract: $e');
      rethrow;
    }
  }

  // ============================================================================
  // ATTENDANCES
  // ============================================================================

  Future<List<Attendance>> getAttendances({
    String? employeeId,
    DateTime? startDate,
    DateTime? endDate,
    AttendanceStatus? status,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return [];
      var query =
          _client.from('attendances').select().eq('tenant_id', tenantId);

      if (employeeId != null) {
        query = query.eq('employee_id', employeeId);
      }

      if (startDate != null) {
        query = query.gte('check_in', startDate.toIso8601String());
      }

      if (endDate != null) {
        // Add 1 day to include the entire end date
        final endOfDay = endDate.add(const Duration(days: 1));
        query = query.lt('check_in', endOfDay.toIso8601String());
      }

      if (status != null) {
        query = query.eq('status', status.name);
      }

      final response = await query.order('check_in', ascending: false);
      return (response as List)
          .map((json) => Attendance.fromMap(json))
          .toList();
    } catch (e) {
      debugPrint('Error getting attendances: $e');
      rethrow;
    }
  }

  Future<Attendance?> getAttendanceById(String id) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return null;
      final response = await _client
          .from('attendances')
          .select()
          .eq('tenant_id', tenantId)
          .eq('id', id)
          .single();
      return Attendance.fromMap(response);
    } catch (e) {
      debugPrint('Error getting attendance: $e');
      return null;
    }
  }

  Future<Attendance?> getCurrentAttendance(String employeeId) async {
    try {
      final response = await _client
          .from('attendances')
          .select()
          .eq('employee_id', employeeId)
          .eq('status', 'ongoing')
          .isFilter('check_out', null)
          .maybeSingle();
      return response != null ? Attendance.fromMap(response) : null;
    } catch (e) {
      debugPrint('Error getting current attendance: $e');
      return null;
    }
  }

  /// Returns current presence plus attendances closed during the supplied day.
  ///
  /// Open attendance markings remain the only presence source. Completed and
  /// approved rows are historical evidence, never inferred from planning.
  Future<List<DailyAttendanceBriefingEntry>> getDailyAttendanceBriefing({
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) {
      throw StateError('No se encontró la tienda actual.');
    }
    if (!startsAt.isBefore(endsAt)) {
      throw ArgumentError.value(
        endsAt,
        'endsAt',
        'Debe ser posterior al inicio del día.',
      );
    }

    try {
      final startsAtUtc = startsAt.toUtc().toIso8601String();
      final endsAtUtc = endsAt.toUtc().toIso8601String();
      final responses = await Future.wait<dynamic>([
        _client
            .from('attendances')
            .select()
            .eq('tenant_id', tenantId)
            .or(
              'and(status.eq.ongoing,check_out.is.null),'
              'and(status.in.(completed,approved),'
              'check_out.not.is.null,check_out.gte.$startsAtUtc,'
              'check_out.lt.$endsAtUtc)',
            )
            .order('check_in'),
        _client.from('employees').select().eq('tenant_id', tenantId),
      ]);

      final attendances = (responses[0] as List<dynamic>)
          .whereType<Map>()
          .map((row) => Attendance.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      final employees = <String, Employee>{
        for (final row in (responses[1] as List<dynamic>).whereType<Map>())
          if (row['id'] != null)
            row['id'].toString():
                Employee.fromMap(Map<String, dynamic>.from(row)),
      };
      final entries = <DailyAttendanceBriefingEntry>[];
      for (final attendance in attendances) {
        final employee = employees[attendance.employeeId];
        if (employee == null) continue;
        entries.add(
          DailyAttendanceBriefingEntry(
            attendance: attendance,
            employee: employee,
          ),
        );
      }
      return entries;
    } catch (error) {
      debugPrint('Error getting daily attendance briefing: $error');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCheckedInEmployees() async {
    try {
      final response = await _client.rpc('get_checked_in_employees');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting checked-in employees: $e');
      return [];
    }
  }

  Future<AttendanceSummary?> getAttendanceSummary(
    String employeeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final response = await _client.rpc('get_attendance_summary', params: {
        'p_employee_id': employeeId,
        'p_start_date': startDate.toIso8601String().split('T')[0],
        'p_end_date': endDate.toIso8601String().split('T')[0],
      });

      if (response is List && response.isNotEmpty) {
        return AttendanceSummary.fromMap(response.first);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting attendance summary: $e');
      return null;
    }
  }

  /// Get comprehensive hours summary for salary calculations
  Future<EmployeeHoursSummary?> getEmployeeHoursSummary(
    String employeeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final response = await _client.rpc('get_employee_hours_summary', params: {
        'p_employee_id': employeeId,
        'p_start_date': startDate.toIso8601String().split('T')[0],
        'p_end_date': endDate.toIso8601String().split('T')[0],
      });

      if (response != null && response is Map<String, dynamic>) {
        return EmployeeHoursSummary.fromMap(response);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting employee hours summary: $e');
      return null;
    }
  }

  // Check in employee
  Future<Attendance> checkIn(
    String employeeId, {
    String? location,
    String? notes,
  }) async {
    try {
      // Verify no ongoing attendance exists
      final current = await getCurrentAttendance(employeeId);
      if (current != null) {
        throw Exception('El trabajador ya tiene una asistencia activa');
      }

      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      final attendance = Attendance(
        tenantId: tenantId,
        employeeId: employeeId,
        checkIn: DateTime.now(),
        locationCheckIn: location ?? 'Oficina',
        notes: notes,
        status: AttendanceStatus.ongoing,
      );

      final response = await _client
          .from('attendances')
          .insert(attendance.toMap())
          .select()
          .single();

      notifyListeners();
      return Attendance.fromMap(response);
    } catch (e) {
      debugPrint('Error checking in: $e');
      rethrow;
    }
  }

  // Check out employee
  Future<Attendance> checkOut(
    String attendanceId, {
    String? location,
    int breakMinutes = 0,
    String? notes,
  }) async {
    try {
      final attendance = await getAttendanceById(attendanceId);
      if (attendance == null) {
        throw Exception('Asistencia no encontrada');
      }

      if (attendance.checkOut != null) {
        throw Exception('Esta asistencia ya fue cerrada');
      }

      final updatedAttendance = attendance.copyWith(
        checkOut: DateTime.now(),
        locationCheckOut: location ?? 'Oficina',
        breakMinutes: breakMinutes,
        notes: notes ?? attendance.notes,
      );

      final response = await _client
          .from('attendances')
          .update(updatedAttendance.toMap())
          .eq('id', attendanceId)
          .select()
          .single();

      notifyListeners();
      return Attendance.fromMap(response);
    } catch (e) {
      debugPrint('Error checking out: $e');
      rethrow;
    }
  }

  Future<Attendance> createAttendance(Attendance attendance) async {
    try {
      final response = await _client
          .from('attendances')
          .insert(attendance.toMap())
          .select()
          .single();
      notifyListeners();
      return Attendance.fromMap(response);
    } catch (e) {
      debugPrint('Error creating attendance: $e');
      rethrow;
    }
  }

  Future<Attendance> updateAttendance(Attendance attendance) async {
    try {
      final response = await _client
          .from('attendances')
          .update(attendance.toMap())
          .eq('id', attendance.id!)
          .select()
          .single();
      notifyListeners();
      return Attendance.fromMap(response);
    } catch (e) {
      debugPrint('Error updating attendance: $e');
      rethrow;
    }
  }

  Future<void> deleteAttendance(String id) async {
    try {
      await _client.from('attendances').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting attendance: $e');
      rethrow;
    }
  }

  Future<void> approveAttendance(
      String attendanceId, String approvedById) async {
    try {
      await _client.from('attendances').update({
        'status': 'approved',
        'approved_by': approvedById,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', attendanceId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error approving attendance: $e');
      rethrow;
    }
  }

  Future<void> rejectAttendance(
      String attendanceId, String approvedById) async {
    try {
      await _client.from('attendances').update({
        'status': 'rejected',
        'approved_by': approvedById,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', attendanceId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error rejecting attendance: $e');
      rethrow;
    }
  }

  // Create a manual attendance entry (for corrections/historical data)
  Future<Attendance> createManualAttendance(
    String employeeId,
    DateTime checkIn, {
    DateTime? checkOut,
    String? location,
    int breakMinutes = 0,
    String? notes,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      final attendance = Attendance(
        tenantId: tenantId,
        employeeId: employeeId,
        checkIn: checkIn,
        checkOut: checkOut,
        locationCheckIn: location ?? 'Oficina',
        locationCheckOut: location ?? 'Oficina',
        breakMinutes: breakMinutes,
        notes: notes,
        status: checkOut != null
            ? AttendanceStatus.completed
            : AttendanceStatus.ongoing,
      );

      final response = await _client
          .from('attendances')
          .insert(attendance.toMap())
          .select()
          .single();

      notifyListeners();
      return Attendance.fromMap(response);
    } catch (e) {
      debugPrint('Error creating manual attendance: $e');
      rethrow;
    }
  }

  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================

  Future<String> generateEmployeeNumber() async {
    try {
      // Get current tenant ID
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('Tenant ID not found');
      }

      final response = await _client
          .from('employees')
          .select('employee_number')
          .eq('tenant_id', tenantId) // Filter by tenant
          .order('employee_number', ascending: false)
          .limit(1);

      if (response.isEmpty) {
        return 'EMP001';
      }

      final lastNumber = response.first['employee_number'] as String;
      final numberPart =
          int.tryParse(lastNumber.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final newNumber = (numberPart + 1).toString().padLeft(3, '0');
      return 'EMP$newNumber';
    } catch (e) {
      debugPrint('Error generating employee number: $e');
      // Fallback with timestamp to ensure uniqueness
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return 'EMP${(timestamp % 10000).toString().padLeft(4, '0')}';
    }
  }

  // Get employees count by department
  Future<Map<String, int>> getEmployeeCountByDepartment() async {
    try {
      final employees = await getEmployees(status: EmployeeStatus.active);
      final Map<String, int> counts = {};

      for (final employee in employees) {
        final deptId = employee.departmentId ?? 'sin_departamento';
        counts[deptId] = (counts[deptId] ?? 0) + 1;
      }

      return counts;
    } catch (e) {
      debugPrint('Error getting employee count by department: $e');
      return {};
    }
  }

  // Get today's attendance rate
  Future<double> getTodayAttendanceRate() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      final activeEmployees = await getEmployees(status: EmployeeStatus.active);
      final todayAttendances = await getAttendances(
        startDate: startOfDay,
        endDate: startOfDay,
      );

      if (activeEmployees.isEmpty) return 0.0;

      final uniqueEmployees =
          todayAttendances.map((a) => a.employeeId).toSet().length;

      return (uniqueEmployees / activeEmployees.length) * 100;
    } catch (e) {
      debugPrint('Error getting today attendance rate: $e');
      return 0.0;
    }
  }

  // ============================================================================
  // USER ACCOUNT CREATION FOR EMPLOYEES
  // ============================================================================

  /// Creates a user invitation for an employee, granting them system access
  /// This will send an email invitation to set up their account
  /// Returns whether the invitation email was confirmed as sent.
  Future<bool> createUserForEmployee({
    required String employeeId,
    required String email,
    required String role,
    required Map<String, dynamic> permissions,
    required String firstName,
    required String lastName,
  }) async {
    final result = await _invokeIdentityAdmin({
      'action': 'create_internal_invitation',
      'email': email.toLowerCase().trim(),
      'role': role,
      'permissions': permissions,
      'employeeId': employeeId,
      'name': '$firstName $lastName'.trim(),
    });
    final emailSent = result['success'] == true && result['emailSent'] == true;
    notifyListeners();
    return emailSent;
  }

  /// Resends a pending invitation through the tenant-authorized admin service.
  Future<void> resendInvitation(String invitationId) async {
    final result = await _invokeIdentityAdmin({
      'action': 'resend_internal_invitation',
      'invitationId': invitationId,
    });
    if (result['success'] != true || result['emailSent'] != true) {
      throw Exception('No se pudo enviar el correo de invitación.');
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> _invokeIdentityAdmin(
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'admin-user-management',
        body: body,
      );
      if (response.status < 200 || response.status >= 300) {
        throw Exception('No se pudo completar la gestión de acceso.');
      }

      final data = response.data;
      if (data is! Map) {
        throw Exception(
            'La gestión de acceso devolvió una respuesta inválida.');
      }
      return Map<String, dynamic>.from(data);
    } catch (_) {
      debugPrint('⚠️ [HRService] Identity admin operation failed');
      rethrow;
    }
  }

  // ============================================================================
  // MEDICAL LEAVES (LICENCIAS MÉDICAS)
  // ============================================================================

  List<MedicalLeave> _medicalLeaves = [];
  List<MedicalLeave> get medicalLeaves => _medicalLeaves;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadMedicalLeaves() async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await _client
          .from('medical_leaves')
          .select()
          .order('start_date', ascending: false);

      _medicalLeaves =
          (response as List).map((json) => MedicalLeave.fromMap(json)).toList();

      debugPrint('✅ Loaded ${_medicalLeaves.length} medical leaves');
    } catch (e) {
      debugPrint('❌ Error loading medical leaves: $e');
      _medicalLeaves = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<MedicalLeave> createMedicalLeave(MedicalLeave leave) async {
    try {
      final response = await _client
          .from('medical_leaves')
          .insert(leave.toMap())
          .select()
          .single();

      final newLeave = MedicalLeave.fromMap(response);
      _medicalLeaves.insert(0, newLeave);
      notifyListeners();

      debugPrint('✅ Created medical leave: ${newLeave.id}');
      return newLeave;
    } catch (e) {
      debugPrint('❌ Error creating medical leave: $e');
      rethrow;
    }
  }

  Future<MedicalLeave> updateMedicalLeave(MedicalLeave leave) async {
    try {
      final response = await _client
          .from('medical_leaves')
          .update(leave.toMap())
          .eq('id', leave.id!)
          .select()
          .single();

      final updatedLeave = MedicalLeave.fromMap(response);
      final index = _medicalLeaves.indexWhere((l) => l.id == leave.id);
      if (index != -1) {
        _medicalLeaves[index] = updatedLeave;
      }
      notifyListeners();

      debugPrint('✅ Updated medical leave: ${updatedLeave.id}');
      return updatedLeave;
    } catch (e) {
      debugPrint('❌ Error updating medical leave: $e');
      rethrow;
    }
  }

  Future<void> deleteMedicalLeave(String id) async {
    try {
      await _client.from('medical_leaves').delete().eq('id', id);

      _medicalLeaves.removeWhere((l) => l.id == id);
      notifyListeners();

      debugPrint('✅ Deleted medical leave: $id');
    } catch (e) {
      debugPrint('❌ Error deleting medical leave: $e');
      rethrow;
    }
  }

  // ============================================================================
  // EMPLOYMENT CONTRACTS
  // ============================================================================

  List<EmploymentContract> _contracts = [];
  List<EmploymentContract> get contracts => _contracts;

  Future<void> loadContracts() async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await _client
          .from('employment_contracts')
          .select()
          .order('start_date', ascending: false);

      _contracts = (response as List)
          .map((json) => EmploymentContract.fromMap(json))
          .toList();

      debugPrint('✅ Loaded ${_contracts.length} employment contracts');
    } catch (e) {
      debugPrint('❌ Error loading contracts: $e');
      _contracts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<EmploymentContract> createEmploymentContract(
      EmploymentContract contract) async {
    try {
      final response = await _client
          .from('employment_contracts')
          .insert(contract.toMap())
          .select()
          .single();

      final newContract = EmploymentContract.fromMap(response);
      _contracts.insert(0, newContract);
      notifyListeners();

      debugPrint('✅ Created contract: ${newContract.id}');
      return newContract;
    } catch (e) {
      debugPrint('❌ Error creating contract: $e');
      rethrow;
    }
  }

  Future<EmploymentContract> updateEmploymentContract(
      EmploymentContract contract) async {
    try {
      final response = await _client
          .from('employment_contracts')
          .update(contract.toMap())
          .eq('id', contract.id!)
          .select()
          .single();

      final updatedContract = EmploymentContract.fromMap(response);
      final index = _contracts.indexWhere((c) => c.id == contract.id);
      if (index != -1) {
        _contracts[index] = updatedContract;
      }
      notifyListeners();

      debugPrint('✅ Updated contract: ${updatedContract.id}');
      return updatedContract;
    } catch (e) {
      debugPrint('❌ Error updating contract: $e');
      rethrow;
    }
  }

  Future<void> deleteEmploymentContract(String id) async {
    try {
      await _client.from('employment_contracts').delete().eq('id', id);

      _contracts.removeWhere((c) => c.id == id);
      notifyListeners();

      debugPrint('✅ Deleted contract: $id');
    } catch (e) {
      debugPrint('❌ Error deleting contract: $e');
      rethrow;
    }
  }

  // ============================================================================
  // PAYROLL RECORDS (LIQUIDACIONES)
  // ============================================================================

  List<PayrollRecord> _payrollRecords = [];
  List<PayrollRecord> get payrollRecords => _payrollRecords;

  Future<void> loadPayrollRecords({int? month, int? year}) async {
    try {
      _isLoading = true;
      notifyListeners();

      var query = _client.from('payroll_records').select();

      if (month != null) {
        query = query.eq('period_month', month);
      }
      if (year != null) {
        query = query.eq('period_year', year);
      }

      final response = await query
          .order('period_year', ascending: false)
          .order('period_month', ascending: false);

      _payrollRecords = (response as List)
          .map((json) => PayrollRecord.fromMap(json))
          .toList();

      debugPrint('✅ Loaded ${_payrollRecords.length} payroll records');
    } catch (e) {
      debugPrint('❌ Error loading payroll records: $e');
      _payrollRecords = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<PayrollRecord> createPayrollRecord(PayrollRecord record) async {
    try {
      final response = await _client
          .from('payroll_records')
          .insert(record.toMap())
          .select()
          .single();

      final newRecord = PayrollRecord.fromMap(response);
      _payrollRecords.insert(0, newRecord);
      notifyListeners();

      debugPrint('✅ Created payroll record: ${newRecord.id}');
      return newRecord;
    } catch (e) {
      debugPrint('❌ Error creating payroll record: $e');
      rethrow;
    }
  }

  Future<PayrollRecord> updatePayrollRecord(PayrollRecord record) async {
    try {
      final response = await _client
          .from('payroll_records')
          .update(record.toMap())
          .eq('id', record.id!)
          .select()
          .single();

      final updatedRecord = PayrollRecord.fromMap(response);
      final index = _payrollRecords.indexWhere((r) => r.id == record.id);
      if (index != -1) {
        _payrollRecords[index] = updatedRecord;
      }
      notifyListeners();

      debugPrint('✅ Updated payroll record: ${updatedRecord.id}');
      return updatedRecord;
    } catch (e) {
      debugPrint('❌ Error updating payroll record: $e');
      rethrow;
    }
  }

  Future<void> deletePayrollRecord(String id) async {
    try {
      await _client.from('payroll_records').delete().eq('id', id);

      _payrollRecords.removeWhere((r) => r.id == id);
      notifyListeners();

      debugPrint('✅ Deleted payroll record: $id');
    } catch (e) {
      debugPrint('❌ Error deleting payroll record: $e');
      rethrow;
    }
  }

  // Get tenant ID
  Future<String> get tenantId async {
    final id = await _tenantService.getTenantId();
    return id ?? '';
  }

  // Get list of employees (simplified accessor)
  Future<List<Employee>> get employees async {
    try {
      return await getEmployees();
    } catch (e) {
      debugPrint('❌ Error getting employees: $e');
      return [];
    }
  }
}
