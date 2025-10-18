// HR Service for Vinabike ERP
// Handles all HR operations: employees, departments, contracts, schedules, and attendances

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hr_models.dart';

class HRService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  HRService();

  // ============================================================================
  // DEPARTMENTS
  // ============================================================================

  Future<List<Department>> getDepartments({bool activeOnly = true}) async {
    try {
      var query = _client.from('departments').select();
      
      if (activeOnly) {
        query = query.eq('active', true);
      }
      
      final response = await query.order('name');
      return (response as List).map((json) => Department.fromMap(json)).toList();
    } catch (e) {
      debugPrint('Error getting departments: $e');
      rethrow;
    }
  }

  Future<Department?> getDepartmentById(String id) async {
    try {
      final response = await _client
          .from('departments')
          .select()
          .eq('id', id)
          .single();
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
  }) async {
    try {
      var query = _client.from('employees').select();

      if (status != null) {
        query = query.eq('status', status.name);
      }

      if (departmentId != null) {
        query = query.eq('department_id', departmentId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
          'first_name.ilike.%$searchQuery%,last_name.ilike.%$searchQuery%,employee_number.ilike.%$searchQuery%,rut.ilike.%$searchQuery%'
        );
      }

      final response = await query.order('last_name').order('first_name');
      return (response as List).map((json) => Employee.fromMap(json)).toList();
    } catch (e) {
      debugPrint('Error getting employees: $e');
      rethrow;
    }
  }

  Future<Employee?> getEmployeeById(String id) async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .eq('id', id)
          .single();
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
      final response = await _client
          .from('employees')
          .insert(employee.toMap())
          .select()
          .single();
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
      notifyListeners();
      return Employee.fromMap(response);
    } catch (e) {
      debugPrint('Error updating employee: $e');
      rethrow;
    }
  }

  Future<void> deleteEmployee(String id) async {
    try {
      await _client.from('employees').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting employee: $e');
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
      return (response as List).map((json) => WorkSchedule.fromMap(json)).toList();
    } catch (e) {
      debugPrint('Error getting work schedules: $e');
      rethrow;
    }
  }

  Future<WorkSchedule?> getWorkScheduleById(String id) async {
    try {
      final response = await _client
          .from('work_schedules')
          .select()
          .eq('id', id)
          .single();
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
      return (response as List).map((json) => EmployeeContract.fromMap(json)).toList();
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
      var query = _client.from('attendances').select();

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
      return (response as List).map((json) => Attendance.fromMap(json)).toList();
    } catch (e) {
      debugPrint('Error getting attendances: $e');
      rethrow;
    }
  }

  Future<Attendance?> getAttendanceById(String id) async {
    try {
      final response = await _client
          .from('attendances')
          .select()
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
        throw Exception('El empleado ya tiene una asistencia activa');
      }

      final attendance = Attendance(
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

  Future<void> approveAttendance(String attendanceId, String approvedById) async {
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

  Future<void> rejectAttendance(String attendanceId, String approvedById) async {
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

  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================

  Future<String> generateEmployeeNumber() async {
    try {
      final response = await _client
          .from('employees')
          .select('employee_number')
          .order('employee_number', ascending: false)
          .limit(1);

      if (response.isEmpty) {
        return 'EMP001';
      }

      final lastNumber = response.first['employee_number'] as String;
      final numberPart = int.tryParse(lastNumber.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final newNumber = (numberPart + 1).toString().padLeft(3, '0');
      return 'EMP$newNumber';
    } catch (e) {
      debugPrint('Error generating employee number: $e');
      return 'EMP${DateTime.now().millisecondsSinceEpoch % 1000}'.padLeft(3, '0');
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
        endDate: today,
      );
      
      if (activeEmployees.isEmpty) return 0.0;
      
      final uniqueEmployees = todayAttendances
          .map((a) => a.employeeId)
          .toSet()
          .length;
      
      return (uniqueEmployees / activeEmployees.length) * 100;
    } catch (e) {
      debugPrint('Error getting today attendance rate: $e');
      return 0.0;
    }
  }
}
