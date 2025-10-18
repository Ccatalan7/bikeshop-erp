// HR Module Models for Vinabike ERP
// Includes: Department, Employee, WorkSchedule, EmployeeContract, Attendance

import 'package:flutter/material.dart';

// ============================================================================
// DEPARTMENT MODEL
// ============================================================================
class Department {
  final String? id;
  final String name;
  final String code;
  final String? managerId;
  final String? description;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  Department({
    this.id,
    required this.name,
    required this.code,
    this.managerId,
    this.description,
    this.active = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Department.fromMap(Map<String, dynamic> map) {
    return Department(
      id: map['id'],
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      managerId: map['manager_id'],
      description: map['description'],
      active: map['active'] ?? true,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'code': code,
      if (managerId != null) 'manager_id': managerId,
      if (description != null) 'description': description,
      'active': active,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Department copyWith({
    String? id,
    String? name,
    String? code,
    String? managerId,
    String? description,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Department(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      managerId: managerId ?? this.managerId,
      description: description ?? this.description,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================================
// EMPLOYEE MODEL
// ============================================================================
enum EmploymentType { fullTime, partTime, contractor, intern }
enum EmployeeStatus { active, inactive, onLeave, terminated }

class Employee {
  final String? id;
  final String? userId;
  final String employeeNumber;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? rut;
  final DateTime? birthDate;
  final DateTime hireDate;
  final DateTime? terminationDate;
  final String? departmentId;
  final String jobTitle;
  final EmploymentType employmentType;
  final EmployeeStatus status;
  final String? photoUrl;
  final String? address;
  final String? city;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Computed
  String get fullName => '$firstName $lastName';
  String get initials => '${firstName[0]}${lastName[0]}'.toUpperCase();

  Employee({
    this.id,
    this.userId,
    required this.employeeNumber,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    this.rut,
    this.birthDate,
    DateTime? hireDate,
    this.terminationDate,
    this.departmentId,
    required this.jobTitle,
    this.employmentType = EmploymentType.fullTime,
    this.status = EmployeeStatus.active,
    this.photoUrl,
    this.address,
    this.city,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : hireDate = hireDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'],
      userId: map['user_id'],
      employeeNumber: map['employee_number'] ?? '',
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      email: map['email'],
      phone: map['phone'],
      rut: map['rut'],
      birthDate: map['birth_date'] != null ? DateTime.parse(map['birth_date']) : null,
      hireDate: map['hire_date'] != null ? DateTime.parse(map['hire_date']) : DateTime.now(),
      terminationDate: map['termination_date'] != null ? DateTime.parse(map['termination_date']) : null,
      departmentId: map['department_id'],
      jobTitle: map['job_title'] ?? '',
      employmentType: _employmentTypeFromString(map['employment_type']),
      status: _employeeStatusFromString(map['status']),
      photoUrl: map['photo_url'],
      address: map['address'],
      city: map['city'],
      emergencyContactName: map['emergency_contact_name'],
      emergencyContactPhone: map['emergency_contact_phone'],
      notes: map['notes'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'employee_number': employeeNumber,
      'first_name': firstName,
      'last_name': lastName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (rut != null) 'rut': rut,
      if (birthDate != null) 'birth_date': birthDate!.toIso8601String().split('T')[0],
      'hire_date': hireDate.toIso8601String().split('T')[0],
      if (terminationDate != null) 'termination_date': terminationDate!.toIso8601String().split('T')[0],
      if (departmentId != null) 'department_id': departmentId,
      'job_title': jobTitle,
      'employment_type': _employmentTypeToString(employmentType),
      'status': _employeeStatusToString(status),
      if (photoUrl != null) 'photo_url': photoUrl,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (emergencyContactName != null) 'emergency_contact_name': emergencyContactName,
      if (emergencyContactPhone != null) 'emergency_contact_phone': emergencyContactPhone,
      if (notes != null) 'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static EmploymentType _employmentTypeFromString(String? value) {
    switch (value) {
      case 'part_time':
        return EmploymentType.partTime;
      case 'contractor':
        return EmploymentType.contractor;
      case 'intern':
        return EmploymentType.intern;
      default:
        return EmploymentType.fullTime;
    }
  }

  static String _employmentTypeToString(EmploymentType type) {
    switch (type) {
      case EmploymentType.fullTime:
        return 'full_time';
      case EmploymentType.partTime:
        return 'part_time';
      case EmploymentType.contractor:
        return 'contractor';
      case EmploymentType.intern:
        return 'intern';
    }
  }

  static EmployeeStatus _employeeStatusFromString(String? value) {
    switch (value) {
      case 'inactive':
        return EmployeeStatus.inactive;
      case 'on_leave':
        return EmployeeStatus.onLeave;
      case 'terminated':
        return EmployeeStatus.terminated;
      default:
        return EmployeeStatus.active;
    }
  }

  static String _employeeStatusToString(EmployeeStatus status) {
    switch (status) {
      case EmployeeStatus.active:
        return 'active';
      case EmployeeStatus.inactive:
        return 'inactive';
      case EmployeeStatus.onLeave:
        return 'on_leave';
      case EmployeeStatus.terminated:
        return 'terminated';
    }
  }

  Employee copyWith({
    String? id,
    String? userId,
    String? employeeNumber,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? rut,
    DateTime? birthDate,
    DateTime? hireDate,
    DateTime? terminationDate,
    String? departmentId,
    String? jobTitle,
    EmploymentType? employmentType,
    EmployeeStatus? status,
    String? photoUrl,
    String? address,
    String? city,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Employee(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      employeeNumber: employeeNumber ?? this.employeeNumber,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      rut: rut ?? this.rut,
      birthDate: birthDate ?? this.birthDate,
      hireDate: hireDate ?? this.hireDate,
      terminationDate: terminationDate ?? this.terminationDate,
      departmentId: departmentId ?? this.departmentId,
      jobTitle: jobTitle ?? this.jobTitle,
      employmentType: employmentType ?? this.employmentType,
      status: status ?? this.status,
      photoUrl: photoUrl ?? this.photoUrl,
      address: address ?? this.address,
      city: city ?? this.city,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================================
// WORK SCHEDULE MODEL
// ============================================================================
class WorkSchedule {
  final String? id;
  final String name;
  final String? description;
  final TimeOfDay? mondayStart;
  final TimeOfDay? mondayEnd;
  final TimeOfDay? tuesdayStart;
  final TimeOfDay? tuesdayEnd;
  final TimeOfDay? wednesdayStart;
  final TimeOfDay? wednesdayEnd;
  final TimeOfDay? thursdayStart;
  final TimeOfDay? thursdayEnd;
  final TimeOfDay? fridayStart;
  final TimeOfDay? fridayEnd;
  final TimeOfDay? saturdayStart;
  final TimeOfDay? saturdayEnd;
  final TimeOfDay? sundayStart;
  final TimeOfDay? sundayEnd;
  final double weeklyHours;
  final String timezone;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkSchedule({
    this.id,
    required this.name,
    this.description,
    this.mondayStart,
    this.mondayEnd,
    this.tuesdayStart,
    this.tuesdayEnd,
    this.wednesdayStart,
    this.wednesdayEnd,
    this.thursdayStart,
    this.thursdayEnd,
    this.fridayStart,
    this.fridayEnd,
    this.saturdayStart,
    this.saturdayEnd,
    this.sundayStart,
    this.sundayEnd,
    this.weeklyHours = 45.0,
    this.timezone = 'America/Santiago',
    this.active = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory WorkSchedule.fromMap(Map<String, dynamic> map) {
    return WorkSchedule(
      id: map['id'],
      name: map['name'] ?? '',
      description: map['description'],
      mondayStart: _timeFromString(map['monday_start']),
      mondayEnd: _timeFromString(map['monday_end']),
      tuesdayStart: _timeFromString(map['tuesday_start']),
      tuesdayEnd: _timeFromString(map['tuesday_end']),
      wednesdayStart: _timeFromString(map['wednesday_start']),
      wednesdayEnd: _timeFromString(map['wednesday_end']),
      thursdayStart: _timeFromString(map['thursday_start']),
      thursdayEnd: _timeFromString(map['thursday_end']),
      fridayStart: _timeFromString(map['friday_start']),
      fridayEnd: _timeFromString(map['friday_end']),
      saturdayStart: _timeFromString(map['saturday_start']),
      saturdayEnd: _timeFromString(map['saturday_end']),
      sundayStart: _timeFromString(map['sunday_start']),
      sundayEnd: _timeFromString(map['sunday_end']),
      weeklyHours: (map['weekly_hours'] ?? 45.0).toDouble(),
      timezone: map['timezone'] ?? 'America/Santiago',
      active: map['active'] ?? true,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (description != null) 'description': description,
      if (mondayStart != null) 'monday_start': _timeToString(mondayStart!),
      if (mondayEnd != null) 'monday_end': _timeToString(mondayEnd!),
      if (tuesdayStart != null) 'tuesday_start': _timeToString(tuesdayStart!),
      if (tuesdayEnd != null) 'tuesday_end': _timeToString(tuesdayEnd!),
      if (wednesdayStart != null) 'wednesday_start': _timeToString(wednesdayStart!),
      if (wednesdayEnd != null) 'wednesday_end': _timeToString(wednesdayEnd!),
      if (thursdayStart != null) 'thursday_start': _timeToString(thursdayStart!),
      if (thursdayEnd != null) 'thursday_end': _timeToString(thursdayEnd!),
      if (fridayStart != null) 'friday_start': _timeToString(fridayStart!),
      if (fridayEnd != null) 'friday_end': _timeToString(fridayEnd!),
      if (saturdayStart != null) 'saturday_start': _timeToString(saturdayStart!),
      if (saturdayEnd != null) 'saturday_end': _timeToString(saturdayEnd!),
      if (sundayStart != null) 'sunday_start': _timeToString(sundayStart!),
      if (sundayEnd != null) 'sunday_end': _timeToString(sundayEnd!),
      'weekly_hours': weeklyHours,
      'timezone': timezone,
      'active': active,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static TimeOfDay? _timeFromString(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _timeToString(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// EMPLOYEE CONTRACT MODEL
// ============================================================================
enum ContractType { indefinite, fixedTerm, projectBased, seasonal }
enum ContractStatus { draft, active, expired, terminated }
enum SalaryPeriod { monthly, biweekly, weekly, hourly }

class EmployeeContract {
  final String? id;
  final String employeeId;
  final ContractType contractType;
  final DateTime startDate;
  final DateTime? endDate;
  final double salaryAmount;
  final String salaryCurrency;
  final SalaryPeriod salaryPeriod;
  final String? workScheduleId;
  final double? weeklyHours;
  final String positionTitle;
  final String? departmentId;
  final ContractStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmployeeContract({
    this.id,
    required this.employeeId,
    this.contractType = ContractType.indefinite,
    required this.startDate,
    this.endDate,
    required this.salaryAmount,
    this.salaryCurrency = 'CLP',
    this.salaryPeriod = SalaryPeriod.monthly,
    this.workScheduleId,
    this.weeklyHours,
    required this.positionTitle,
    this.departmentId,
    this.status = ContractStatus.draft,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory EmployeeContract.fromMap(Map<String, dynamic> map) {
    return EmployeeContract(
      id: map['id'],
      employeeId: map['employee_id'] ?? '',
      contractType: _contractTypeFromString(map['contract_type']),
      startDate: DateTime.parse(map['start_date']),
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      salaryAmount: (map['salary_amount'] ?? 0).toDouble(),
      salaryCurrency: map['salary_currency'] ?? 'CLP',
      salaryPeriod: _salaryPeriodFromString(map['salary_period']),
      workScheduleId: map['work_schedule_id'],
      weeklyHours: map['weekly_hours']?.toDouble(),
      positionTitle: map['position_title'] ?? '',
      departmentId: map['department_id'],
      status: _contractStatusFromString(map['status']),
      notes: map['notes'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'employee_id': employeeId,
      'contract_type': _contractTypeToString(contractType),
      'start_date': startDate.toIso8601String().split('T')[0],
      if (endDate != null) 'end_date': endDate!.toIso8601String().split('T')[0],
      'salary_amount': salaryAmount,
      'salary_currency': salaryCurrency,
      'salary_period': _salaryPeriodToString(salaryPeriod),
      if (workScheduleId != null) 'work_schedule_id': workScheduleId,
      if (weeklyHours != null) 'weekly_hours': weeklyHours,
      'position_title': positionTitle,
      if (departmentId != null) 'department_id': departmentId,
      'status': _contractStatusToString(status),
      if (notes != null) 'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static ContractType _contractTypeFromString(String? value) {
    switch (value) {
      case 'fixed_term':
        return ContractType.fixedTerm;
      case 'project_based':
        return ContractType.projectBased;
      case 'seasonal':
        return ContractType.seasonal;
      default:
        return ContractType.indefinite;
    }
  }

  static String _contractTypeToString(ContractType type) {
    switch (type) {
      case ContractType.indefinite:
        return 'indefinite';
      case ContractType.fixedTerm:
        return 'fixed_term';
      case ContractType.projectBased:
        return 'project_based';
      case ContractType.seasonal:
        return 'seasonal';
    }
  }

  static ContractStatus _contractStatusFromString(String? value) {
    switch (value) {
      case 'active':
        return ContractStatus.active;
      case 'expired':
        return ContractStatus.expired;
      case 'terminated':
        return ContractStatus.terminated;
      default:
        return ContractStatus.draft;
    }
  }

  static String _contractStatusToString(ContractStatus status) {
    switch (status) {
      case ContractStatus.draft:
        return 'draft';
      case ContractStatus.active:
        return 'active';
      case ContractStatus.expired:
        return 'expired';
      case ContractStatus.terminated:
        return 'terminated';
    }
  }

  static SalaryPeriod _salaryPeriodFromString(String? value) {
    switch (value) {
      case 'biweekly':
        return SalaryPeriod.biweekly;
      case 'weekly':
        return SalaryPeriod.weekly;
      case 'hourly':
        return SalaryPeriod.hourly;
      default:
        return SalaryPeriod.monthly;
    }
  }

  static String _salaryPeriodToString(SalaryPeriod period) {
    switch (period) {
      case SalaryPeriod.monthly:
        return 'monthly';
      case SalaryPeriod.biweekly:
        return 'biweekly';
      case SalaryPeriod.weekly:
        return 'weekly';
      case SalaryPeriod.hourly:
        return 'hourly';
    }
  }
}

// ============================================================================
// ATTENDANCE MODEL
// ============================================================================
enum AttendanceStatus { ongoing, completed, approved, rejected }

class Attendance {
  final String? id;
  final String employeeId;
  final DateTime checkIn;
  final DateTime? checkOut;
  final double? workedHours;
  final double? overtimeHours;
  final int breakMinutes;
  final String? locationCheckIn;
  final String? locationCheckOut;
  final String? notes;
  final AttendanceStatus status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Computed
  bool get isOngoing => status == AttendanceStatus.ongoing && checkOut == null;
  Duration get currentDuration => checkOut != null 
      ? checkOut!.difference(checkIn) 
      : DateTime.now().difference(checkIn);

  Attendance({
    this.id,
    required this.employeeId,
    required this.checkIn,
    this.checkOut,
    this.workedHours,
    this.overtimeHours,
    this.breakMinutes = 0,
    this.locationCheckIn,
    this.locationCheckOut,
    this.notes,
    this.status = AttendanceStatus.ongoing,
    this.approvedBy,
    this.approvedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id'],
      employeeId: map['employee_id'] ?? '',
      checkIn: DateTime.parse(map['check_in']),
      checkOut: map['check_out'] != null ? DateTime.parse(map['check_out']) : null,
      workedHours: map['worked_hours']?.toDouble(),
      overtimeHours: map['overtime_hours']?.toDouble(),
      breakMinutes: map['break_minutes'] ?? 0,
      locationCheckIn: map['location_check_in'],
      locationCheckOut: map['location_check_out'],
      notes: map['notes'],
      status: _statusFromString(map['status']),
      approvedBy: map['approved_by'],
      approvedAt: map['approved_at'] != null ? DateTime.parse(map['approved_at']) : null,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'employee_id': employeeId,
      'check_in': checkIn.toIso8601String(),
      if (checkOut != null) 'check_out': checkOut!.toIso8601String(),
      if (workedHours != null) 'worked_hours': workedHours,
      if (overtimeHours != null) 'overtime_hours': overtimeHours,
      'break_minutes': breakMinutes,
      if (locationCheckIn != null) 'location_check_in': locationCheckIn,
      if (locationCheckOut != null) 'location_check_out': locationCheckOut,
      if (notes != null) 'notes': notes,
      'status': _statusToString(status),
      if (approvedBy != null) 'approved_by': approvedBy,
      if (approvedAt != null) 'approved_at': approvedAt!.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static AttendanceStatus _statusFromString(String? value) {
    switch (value) {
      case 'completed':
        return AttendanceStatus.completed;
      case 'approved':
        return AttendanceStatus.approved;
      case 'rejected':
        return AttendanceStatus.rejected;
      default:
        return AttendanceStatus.ongoing;
    }
  }

  static String _statusToString(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.ongoing:
        return 'ongoing';
      case AttendanceStatus.completed:
        return 'completed';
      case AttendanceStatus.approved:
        return 'approved';
      case AttendanceStatus.rejected:
        return 'rejected';
    }
  }

  Attendance copyWith({
    String? id,
    String? employeeId,
    DateTime? checkIn,
    DateTime? checkOut,
    double? workedHours,
    double? overtimeHours,
    int? breakMinutes,
    String? locationCheckIn,
    String? locationCheckOut,
    String? notes,
    AttendanceStatus? status,
    String? approvedBy,
    DateTime? approvedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Attendance(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      workedHours: workedHours ?? this.workedHours,
      overtimeHours: overtimeHours ?? this.overtimeHours,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      locationCheckIn: locationCheckIn ?? this.locationCheckIn,
      locationCheckOut: locationCheckOut ?? this.locationCheckOut,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================================
// ATTENDANCE SUMMARY MODEL (for reports)
// ============================================================================
class AttendanceSummary {
  final int totalDays;
  final double totalHours;
  final double totalOvertime;
  final double averageHours;
  final int lateArrivals;
  final int earlyDepartures;

  AttendanceSummary({
    required this.totalDays,
    required this.totalHours,
    required this.totalOvertime,
    required this.averageHours,
    required this.lateArrivals,
    required this.earlyDepartures,
  });

  factory AttendanceSummary.fromMap(Map<String, dynamic> map) {
    return AttendanceSummary(
      totalDays: map['total_days'] ?? 0,
      totalHours: (map['total_hours'] ?? 0).toDouble(),
      totalOvertime: (map['total_overtime'] ?? 0).toDouble(),
      averageHours: (map['average_hours'] ?? 0).toDouble(),
      lateArrivals: map['late_arrivals'] ?? 0,
      earlyDepartures: map['early_departures'] ?? 0,
    );
  }
}
