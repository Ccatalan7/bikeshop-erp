// HR Module Models for Vinabike ERP
// Includes: Department, Employee, WorkSchedule, EmployeeContract, Attendance

import 'package:flutter/material.dart';

// ============================================================================
// DEPARTMENT MODEL
// ============================================================================
class Department {
  final String? id;
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
  final String name;
  final String code;
  final String? managerId;
  final String? description;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  Department({
    this.id,
    required this.tenantId,
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
      tenantId: map['tenant_id']?.toString() ?? '',
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      managerId: map['manager_id'],
      description: map['description'],
      active: map['active'] ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
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
    String? tenantId,
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
      tenantId: tenantId ?? this.tenantId,
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

enum PaymentMethod { cash, transfer, check }

enum BankAccountType { checking, savings, vista }

class Employee {
  final String? id;
  final String tenantId;
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
  final String? systemRole; // Links to job_roles.system_role
  final EmploymentType employmentType;
  final EmployeeStatus status;
  final String? photoUrl;
  final String? address;
  final String? city;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? notes;
  // Salary & Payment fields
  final double? hourlyRate;
  final PaymentMethod? preferredPaymentMethod;
  final String? bankName;
  final String? bankAccountNumber;
  final BankAccountType? bankAccountType;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Computed
  String get fullName => '$firstName $lastName';
  String get initials => '${firstName[0]}${lastName[0]}'.toUpperCase();

  Employee({
    this.id,
    required this.tenantId,
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
    this.systemRole, // Optional: links to standardized role
    this.employmentType = EmploymentType.fullTime,
    this.status = EmployeeStatus.active,
    this.photoUrl,
    this.address,
    this.city,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.notes,
    this.hourlyRate,
    this.preferredPaymentMethod,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountType,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : hireDate = hireDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'],
      tenantId: map['tenant_id']?.toString() ?? '',
      userId: map['user_id'],
      employeeNumber: map['employee_number'] ?? '',
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      email: map['email'],
      phone: map['phone'],
      rut: map['rut'],
      birthDate:
          map['birth_date'] != null ? DateTime.parse(map['birth_date']) : null,
      hireDate: map['hire_date'] != null
          ? DateTime.parse(map['hire_date'])
          : DateTime.now(),
      terminationDate: map['termination_date'] != null
          ? DateTime.parse(map['termination_date'])
          : null,
      departmentId: map['department_id'],
      jobTitle: map['job_title'] ?? '',
      systemRole: map['system_role'], // NEW: job role link
      employmentType: _employmentTypeFromString(map['employment_type']),
      status: _employeeStatusFromString(map['status']),
      photoUrl: map['photo_url'],
      address: map['address'],
      city: map['city'],
      emergencyContactName: map['emergency_contact_name'],
      emergencyContactPhone: map['emergency_contact_phone'],
      notes: map['notes'],
      hourlyRate: map['hourly_rate']?.toDouble(),
      preferredPaymentMethod:
          _paymentMethodFromString(map['preferred_payment_method']),
      bankName: map['bank_name'],
      bankAccountNumber: map['bank_account_number'],
      bankAccountType: _bankAccountTypeFromString(map['bank_account_type']),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      if (userId != null) 'user_id': userId,
      'employee_number': employeeNumber,
      'first_name': firstName,
      'last_name': lastName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (rut != null) 'rut': rut,
      if (birthDate != null)
        'birth_date': birthDate!.toIso8601String().split('T')[0],
      'hire_date': hireDate.toIso8601String().split('T')[0],
      if (terminationDate != null)
        'termination_date': terminationDate!.toIso8601String().split('T')[0],
      if (departmentId != null) 'department_id': departmentId,
      'job_title': jobTitle,
      if (systemRole != null) 'system_role': systemRole, // NEW: save role link
      'employment_type': _employmentTypeToString(employmentType),
      'status': _employeeStatusToString(status),
      if (photoUrl != null) 'photo_url': photoUrl,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (emergencyContactName != null)
        'emergency_contact_name': emergencyContactName,
      if (emergencyContactPhone != null)
        'emergency_contact_phone': emergencyContactPhone,
      if (notes != null) 'notes': notes,
      if (hourlyRate != null) 'hourly_rate': hourlyRate,
      if (preferredPaymentMethod != null)
        'preferred_payment_method':
            _paymentMethodToString(preferredPaymentMethod!),
      if (bankName != null) 'bank_name': bankName,
      if (bankAccountNumber != null) 'bank_account_number': bankAccountNumber,
      if (bankAccountType != null)
        'bank_account_type': _bankAccountTypeToString(bankAccountType!),
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

  static PaymentMethod? _paymentMethodFromString(String? value) {
    switch (value) {
      case 'cash':
        return PaymentMethod.cash;
      case 'transfer':
        return PaymentMethod.transfer;
      case 'check':
        return PaymentMethod.check;
      default:
        return null;
    }
  }

  static String _paymentMethodToString(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.transfer:
        return 'transfer';
      case PaymentMethod.check:
        return 'check';
    }
  }

  static BankAccountType? _bankAccountTypeFromString(String? value) {
    switch (value) {
      case 'checking':
        return BankAccountType.checking;
      case 'savings':
        return BankAccountType.savings;
      case 'vista':
        return BankAccountType.vista;
      default:
        return null;
    }
  }

  static String _bankAccountTypeToString(BankAccountType type) {
    switch (type) {
      case BankAccountType.checking:
        return 'checking';
      case BankAccountType.savings:
        return 'savings';
      case BankAccountType.vista:
        return 'vista';
    }
  }

  Employee copyWith({
    String? id,
    String? tenantId,
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
    double? hourlyRate,
    PaymentMethod? preferredPaymentMethod,
    String? bankName,
    String? bankAccountNumber,
    BankAccountType? bankAccountType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Employee(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
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
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      notes: notes ?? this.notes,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      preferredPaymentMethod:
          preferredPaymentMethod ?? this.preferredPaymentMethod,
      bankName: bankName ?? this.bankName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankAccountType: bankAccountType ?? this.bankAccountType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================================
// EMPLOYEE HOURS SUMMARY MODEL (for salary/hours statistics)
// ============================================================================
class EmployeeHoursSummary {
  final int totalDaysWorked;
  final double totalHours;
  final double totalOvertime;
  final int totalBreakMinutes;
  final double averageHoursPerDay;
  final String? earliestCheckIn; // Time string (HH:mm)
  final String? latestCheckOut; // Time string (HH:mm)
  final int daysWithOvertime;
  final int lateArrivals;
  final int earlyDepartures;
  final int perfectAttendanceDays;
  final int shortDays;

  EmployeeHoursSummary({
    required this.totalDaysWorked,
    required this.totalHours,
    required this.totalOvertime,
    required this.totalBreakMinutes,
    required this.averageHoursPerDay,
    this.earliestCheckIn,
    this.latestCheckOut,
    required this.daysWithOvertime,
    required this.lateArrivals,
    required this.earlyDepartures,
    required this.perfectAttendanceDays,
    required this.shortDays,
  });

  factory EmployeeHoursSummary.fromMap(Map<String, dynamic> map) {
    return EmployeeHoursSummary(
      totalDaysWorked: map['total_days_worked'] ?? 0,
      totalHours: (map['total_hours'] ?? 0).toDouble(),
      totalOvertime: (map['total_overtime'] ?? 0).toDouble(),
      totalBreakMinutes: map['total_break_minutes'] ?? 0,
      averageHoursPerDay: (map['average_hours_per_day'] ?? 0).toDouble(),
      earliestCheckIn: map['earliest_check_in'],
      latestCheckOut: map['latest_check_out'],
      daysWithOvertime: map['days_with_overtime'] ?? 0,
      lateArrivals: map['late_arrivals'] ?? 0,
      earlyDepartures: map['early_departures'] ?? 0,
      perfectAttendanceDays: map['perfect_attendance_days'] ?? 0,
      shortDays: map['short_days'] ?? 0,
    );
  }

  /// Calculate estimated earnings based on hourly rate
  double estimatedEarnings(double hourlyRate) => hourlyRate * totalHours;

  /// Calculate overtime earnings (typically 1.5x rate)
  double overtimeEarnings(double hourlyRate, {double multiplier = 1.5}) =>
      hourlyRate * totalOvertime * multiplier;

  /// Attendance score (0-100) based on perfect days and punctuality
  double get attendanceScore {
    if (totalDaysWorked == 0) return 100;
    final perfectRatio = perfectAttendanceDays / totalDaysWorked;
    final lateRatio = lateArrivals / totalDaysWorked;
    final earlyRatio = earlyDepartures / totalDaysWorked;
    return ((perfectRatio * 0.6) +
            ((1 - lateRatio) * 0.2) +
            ((1 - earlyRatio) * 0.2)) *
        100;
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
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
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
      if (wednesdayStart != null)
        'wednesday_start': _timeToString(wednesdayStart!),
      if (wednesdayEnd != null) 'wednesday_end': _timeToString(wednesdayEnd!),
      if (thursdayStart != null)
        'thursday_start': _timeToString(thursdayStart!),
      if (thursdayEnd != null) 'thursday_end': _timeToString(thursdayEnd!),
      if (fridayStart != null) 'friday_start': _timeToString(fridayStart!),
      if (fridayEnd != null) 'friday_end': _timeToString(fridayEnd!),
      if (saturdayStart != null)
        'saturday_start': _timeToString(saturdayStart!),
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
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
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
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
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
    required this.tenantId,
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
      tenantId: map['tenant_id']?.toString() ?? '',
      employeeId: map['employee_id'] ?? '',
      checkIn: DateTime.parse(map['check_in']).toLocal(),
      checkOut: map['check_out'] != null
          ? DateTime.parse(map['check_out']).toLocal()
          : null,
      workedHours: map['worked_hours']?.toDouble(),
      overtimeHours: map['overtime_hours']?.toDouble(),
      breakMinutes: map['break_minutes'] ?? 0,
      locationCheckIn: map['location_check_in'],
      locationCheckOut: map['location_check_out'],
      notes: map['notes'],
      status: _statusFromString(map['status']),
      approvedBy: map['approved_by'],
      approvedAt: map['approved_at'] != null
          ? DateTime.parse(map['approved_at']).toLocal()
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at']).toLocal()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at']).toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'employee_id': employeeId,
      'check_in': checkIn.toUtc().toIso8601String(),
      if (checkOut != null) 'check_out': checkOut!.toUtc().toIso8601String(),
      if (workedHours != null) 'worked_hours': workedHours,
      if (overtimeHours != null) 'overtime_hours': overtimeHours,
      'break_minutes': breakMinutes,
      if (locationCheckIn != null) 'location_check_in': locationCheckIn,
      if (locationCheckOut != null) 'location_check_out': locationCheckOut,
      if (notes != null) 'notes': notes,
      'status': _statusToString(status),
      if (approvedBy != null) 'approved_by': approvedBy,
      if (approvedAt != null)
        'approved_at': approvedAt!.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
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
    String? tenantId,
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
      tenantId: tenantId ?? this.tenantId,
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
  final String tenantId;
  final int totalDays;
  final double totalHours;
  final double totalOvertime;
  final double averageHours;
  final int lateArrivals;
  final int earlyDepartures;

  AttendanceSummary({
    required this.tenantId,
    required this.totalDays,
    required this.totalHours,
    required this.totalOvertime,
    required this.averageHours,
    required this.lateArrivals,
    required this.earlyDepartures,
  });

  factory AttendanceSummary.fromMap(Map<String, dynamic> map) {
    return AttendanceSummary(
      tenantId: map['tenant_id']?.toString() ?? '',
      totalDays: map['total_days'] ?? 0,
      totalHours: (map['total_hours'] ?? 0).toDouble(),
      totalOvertime: (map['total_overtime'] ?? 0).toDouble(),
      averageHours: (map['average_hours'] ?? 0).toDouble(),
      lateArrivals: map['late_arrivals'] ?? 0,
      earlyDepartures: map['early_departures'] ?? 0,
    );
  }
}

// ============================================================================
// MEDICAL LEAVE MODEL (LICENCIA MÉDICA)
// ============================================================================
enum LeaveType {
  enfermedadComun,
  accidenteTrabajo,
  enfermedadProfesional,
  maternal,
  paternal,
  prePostNatal
}

enum LeaveStatus { pending, approved, rejected, paid }

class MedicalLeave {
  final String? id;
  final String tenantId;
  final String employeeId;
  final LeaveType leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final int daysCount;
  final String? certificateNumber;
  final String? doctorName;
  final String? doctorRut;
  final String? issuingInstitution;
  final LeaveStatus status;
  final double? dailySubsidyAmount;
  final double? totalSubsidyAmount;
  final String? paidBy;
  final DateTime? paidAt;
  final String? certificateUrl;
  final String? approvalUrl;
  final String? diagnosis;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  MedicalLeave({
    this.id,
    required this.tenantId,
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    int? daysCount,
    this.certificateNumber,
    this.doctorName,
    this.doctorRut,
    this.issuingInstitution,
    this.status = LeaveStatus.pending,
    this.dailySubsidyAmount,
    this.totalSubsidyAmount,
    this.paidBy,
    this.paidAt,
    this.certificateUrl,
    this.approvalUrl,
    this.diagnosis,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : daysCount = daysCount ?? endDate.difference(startDate).inDays + 1,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory MedicalLeave.fromMap(Map<String, dynamic> map) {
    return MedicalLeave(
      id: map['id'],
      tenantId: map['tenant_id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      leaveType: _leaveTypeFromString(map['leave_type']),
      startDate: DateTime.parse(map['start_date']),
      endDate: DateTime.parse(map['end_date']),
      daysCount: map['days_count'],
      certificateNumber: map['certificate_number'],
      doctorName: map['doctor_name'],
      doctorRut: map['doctor_rut'],
      issuingInstitution: map['issuing_institution'],
      status: _leaveStatusFromString(map['status']),
      dailySubsidyAmount: map['daily_subsidy_amount']?.toDouble(),
      totalSubsidyAmount: map['total_subsidy_amount']?.toDouble(),
      paidBy: map['paid_by'],
      paidAt: map['paid_at'] != null ? DateTime.parse(map['paid_at']) : null,
      certificateUrl: map['certificate_url'],
      approvalUrl: map['approval_url'],
      diagnosis: map['diagnosis'],
      notes: map['notes'],
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'employee_id': employeeId,
      'leave_type': _leaveTypeToString(leaveType),
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      if (certificateNumber != null) 'certificate_number': certificateNumber,
      if (doctorName != null) 'doctor_name': doctorName,
      if (doctorRut != null) 'doctor_rut': doctorRut,
      if (issuingInstitution != null) 'issuing_institution': issuingInstitution,
      'status': _leaveStatusToString(status),
      if (dailySubsidyAmount != null)
        'daily_subsidy_amount': dailySubsidyAmount,
      if (totalSubsidyAmount != null)
        'total_subsidy_amount': totalSubsidyAmount,
      if (paidBy != null) 'paid_by': paidBy,
      if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
      if (certificateUrl != null) 'certificate_url': certificateUrl,
      if (approvalUrl != null) 'approval_url': approvalUrl,
      if (diagnosis != null) 'diagnosis': diagnosis,
      if (notes != null) 'notes': notes,
    };
  }

  static LeaveType _leaveTypeFromString(String? value) {
    switch (value) {
      case 'enfermedad_comun':
        return LeaveType.enfermedadComun;
      case 'accidente_trabajo':
        return LeaveType.accidenteTrabajo;
      case 'enfermedad_profesional':
        return LeaveType.enfermedadProfesional;
      case 'maternal':
        return LeaveType.maternal;
      case 'paternal':
        return LeaveType.paternal;
      case 'pre_post_natal':
        return LeaveType.prePostNatal;
      default:
        return LeaveType.enfermedadComun;
    }
  }

  static String _leaveTypeToString(LeaveType type) {
    switch (type) {
      case LeaveType.enfermedadComun:
        return 'enfermedad_comun';
      case LeaveType.accidenteTrabajo:
        return 'accidente_trabajo';
      case LeaveType.enfermedadProfesional:
        return 'enfermedad_profesional';
      case LeaveType.maternal:
        return 'maternal';
      case LeaveType.paternal:
        return 'paternal';
      case LeaveType.prePostNatal:
        return 'pre_post_natal';
    }
  }

  static LeaveStatus _leaveStatusFromString(String? value) {
    switch (value) {
      case 'pending':
        return LeaveStatus.pending;
      case 'approved':
        return LeaveStatus.approved;
      case 'rejected':
        return LeaveStatus.rejected;
      case 'paid':
        return LeaveStatus.paid;
      default:
        return LeaveStatus.pending;
    }
  }

  static String _leaveStatusToString(LeaveStatus status) {
    switch (status) {
      case LeaveStatus.pending:
        return 'pending';
      case LeaveStatus.approved:
        return 'approved';
      case LeaveStatus.rejected:
        return 'rejected';
      case LeaveStatus.paid:
        return 'paid';
    }
  }

  String get leaveTypeLabel {
    switch (leaveType) {
      case LeaveType.enfermedadComun:
        return 'Enfermedad Común';
      case LeaveType.accidenteTrabajo:
        return 'Accidente de Trabajo';
      case LeaveType.enfermedadProfesional:
        return 'Enfermedad Profesional';
      case LeaveType.maternal:
        return 'Maternal';
      case LeaveType.paternal:
        return 'Paternal';
      case LeaveType.prePostNatal:
        return 'Pre/Post Natal';
    }
  }

  String get statusLabel {
    switch (status) {
      case LeaveStatus.pending:
        return 'Pendiente';
      case LeaveStatus.approved:
        return 'Aprobada';
      case LeaveStatus.rejected:
        return 'Rechazada';
      case LeaveStatus.paid:
        return 'Pagada';
    }
  }

  Color get statusColor {
    switch (status) {
      case LeaveStatus.pending:
        return Colors.orange;
      case LeaveStatus.approved:
        return Colors.green;
      case LeaveStatus.rejected:
        return Colors.red;
      case LeaveStatus.paid:
        return Colors.blue;
    }
  }
}

// ============================================================================
// EMPLOYMENT CONTRACT MODEL (CHILEAN LABOR LAW)
// ============================================================================
enum ChileanContractType {
  indefinido,
  plazoFijo,
  obraFaena,
  partTime,
  honorarios
}

enum ChileanContractStatus { active, terminated, suspended }

enum ChileanPaymentFrequency { monthly, biweekly, weekly }

class EmploymentContract {
  final String? id;
  final String tenantId;
  final String employeeId;
  final ChileanContractType contractType;
  final DateTime startDate;
  final DateTime? endDate;
  final String positionTitle;
  final String? department;
  final String? jobDescription;
  final int weeklyHours;
  final String? workSchedule;
  final double baseSalary;
  final ChileanPaymentFrequency paymentFrequency;
  final String paymentMethod;
  final bool includesTransportation;
  final bool includesLunch;
  final bool includesHousing;
  final bool includesHealthInsurance;
  final bool includesLifeInsurance;
  final int vacationDays;
  final ChileanContractStatus status;
  final DateTime? terminationDate;
  final String? terminationReason;
  final String? contractUrl;
  final List<String>? addendumUrls;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmploymentContract({
    this.id,
    required this.tenantId,
    required this.employeeId,
    required this.contractType,
    required this.startDate,
    this.endDate,
    required this.positionTitle,
    this.department,
    this.jobDescription,
    this.weeklyHours = 45,
    this.workSchedule,
    required this.baseSalary,
    this.paymentFrequency = ChileanPaymentFrequency.monthly,
    this.paymentMethod = 'bank_transfer',
    this.includesTransportation = false,
    this.includesLunch = false,
    this.includesHousing = false,
    this.includesHealthInsurance = false,
    this.includesLifeInsurance = false,
    this.vacationDays = 15,
    this.status = ChileanContractStatus.active,
    this.terminationDate,
    this.terminationReason,
    this.contractUrl,
    this.addendumUrls,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory EmploymentContract.fromMap(Map<String, dynamic> map) {
    return EmploymentContract(
      id: map['id'],
      tenantId: map['tenant_id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      contractType: _contractTypeFromString(map['contract_type']),
      startDate: DateTime.parse(map['start_date']),
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      positionTitle: map['position_title'] ?? '',
      department: map['department'],
      jobDescription: map['job_description'],
      weeklyHours: map['weekly_hours'] ?? 45,
      workSchedule: map['work_schedule'],
      baseSalary: (map['base_salary'] ?? 0).toDouble(),
      paymentFrequency: _paymentFrequencyFromString(map['payment_frequency']),
      paymentMethod: map['payment_method'] ?? 'bank_transfer',
      includesTransportation: map['includes_transportation'] ?? false,
      includesLunch: map['includes_lunch'] ?? false,
      includesHousing: map['includes_housing'] ?? false,
      includesHealthInsurance: map['includes_health_insurance'] ?? false,
      includesLifeInsurance: map['includes_life_insurance'] ?? false,
      vacationDays: map['vacation_days'] ?? 15,
      status: _contractStatusFromString(map['status']),
      terminationDate: map['termination_date'] != null
          ? DateTime.parse(map['termination_date'])
          : null,
      terminationReason: map['termination_reason'],
      contractUrl: map['contract_url'],
      addendumUrls: map['addendum_urls'] != null
          ? List<String>.from(map['addendum_urls'])
          : null,
      notes: map['notes'],
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'employee_id': employeeId,
      'contract_type': _contractTypeToString(contractType),
      'start_date': startDate.toIso8601String().split('T')[0],
      if (endDate != null) 'end_date': endDate!.toIso8601String().split('T')[0],
      'position_title': positionTitle,
      if (department != null) 'department': department,
      if (jobDescription != null) 'job_description': jobDescription,
      'weekly_hours': weeklyHours,
      if (workSchedule != null) 'work_schedule': workSchedule,
      'base_salary': baseSalary,
      'payment_frequency': _paymentFrequencyToString(paymentFrequency),
      'payment_method': paymentMethod,
      'includes_transportation': includesTransportation,
      'includes_lunch': includesLunch,
      'includes_housing': includesHousing,
      'includes_health_insurance': includesHealthInsurance,
      'includes_life_insurance': includesLifeInsurance,
      'vacation_days': vacationDays,
      'status': _contractStatusToString(status),
      if (terminationDate != null)
        'termination_date': terminationDate!.toIso8601String().split('T')[0],
      if (terminationReason != null) 'termination_reason': terminationReason,
      if (contractUrl != null) 'contract_url': contractUrl,
      if (addendumUrls != null) 'addendum_urls': addendumUrls,
      if (notes != null) 'notes': notes,
    };
  }

  static ChileanContractType _contractTypeFromString(String? value) {
    switch (value) {
      case 'indefinido':
        return ChileanContractType.indefinido;
      case 'plazo_fijo':
        return ChileanContractType.plazoFijo;
      case 'obra_faena':
        return ChileanContractType.obraFaena;
      case 'part_time':
        return ChileanContractType.partTime;
      case 'honorarios':
        return ChileanContractType.honorarios;
      default:
        return ChileanContractType.indefinido;
    }
  }

  static String _contractTypeToString(ChileanContractType type) {
    switch (type) {
      case ChileanContractType.indefinido:
        return 'indefinido';
      case ChileanContractType.plazoFijo:
        return 'plazo_fijo';
      case ChileanContractType.obraFaena:
        return 'obra_faena';
      case ChileanContractType.partTime:
        return 'part_time';
      case ChileanContractType.honorarios:
        return 'honorarios';
    }
  }

  static ChileanContractStatus _contractStatusFromString(String? value) {
    switch (value) {
      case 'active':
        return ChileanContractStatus.active;
      case 'terminated':
        return ChileanContractStatus.terminated;
      case 'suspended':
        return ChileanContractStatus.suspended;
      default:
        return ChileanContractStatus.active;
    }
  }

  static String _contractStatusToString(ChileanContractStatus status) {
    switch (status) {
      case ChileanContractStatus.active:
        return 'active';
      case ChileanContractStatus.terminated:
        return 'terminated';
      case ChileanContractStatus.suspended:
        return 'suspended';
    }
  }

  static ChileanPaymentFrequency _paymentFrequencyFromString(String? value) {
    switch (value) {
      case 'monthly':
        return ChileanPaymentFrequency.monthly;
      case 'biweekly':
        return ChileanPaymentFrequency.biweekly;
      case 'weekly':
        return ChileanPaymentFrequency.weekly;
      default:
        return ChileanPaymentFrequency.monthly;
    }
  }

  static String _paymentFrequencyToString(ChileanPaymentFrequency freq) {
    switch (freq) {
      case ChileanPaymentFrequency.monthly:
        return 'monthly';
      case ChileanPaymentFrequency.biweekly:
        return 'biweekly';
      case ChileanPaymentFrequency.weekly:
        return 'weekly';
    }
  }

  String get contractTypeLabel {
    switch (contractType) {
      case ChileanContractType.indefinido:
        return 'Indefinido';
      case ChileanContractType.plazoFijo:
        return 'Plazo Fijo';
      case ChileanContractType.obraFaena:
        return 'Obra o Faena';
      case ChileanContractType.partTime:
        return 'Part-Time';
      case ChileanContractType.honorarios:
        return 'Honorarios';
    }
  }

  String get statusLabel {
    switch (status) {
      case ChileanContractStatus.active:
        return 'Activo';
      case ChileanContractStatus.terminated:
        return 'Terminado';
      case ChileanContractStatus.suspended:
        return 'Suspendido';
    }
  }

  Color get statusColor {
    switch (status) {
      case ChileanContractStatus.active:
        return Colors.green;
      case ChileanContractStatus.terminated:
        return Colors.red;
      case ChileanContractStatus.suspended:
        return Colors.orange;
    }
  }
}

// ============================================================================
// PAYROLL RECORD MODEL (LIQUIDACIÓN DE SUELDO)
// ============================================================================
class PayrollRecord {
  final String? id;
  final String tenantId;
  final String employeeId;
  final int periodMonth;
  final int periodYear;
  final DateTime paymentDate;

  // Haberes (Income)
  final double baseSalary;
  final double overtimePay;
  final double bonuses;
  final double commissions;
  final double mobilityAllowance;
  final double lunchAllowance;
  final double housingAllowance;
  final double otherIncome;
  final double totalHaberes;

  // Descuentos (Deductions)
  final double afpContribution;
  final double healthContribution;
  final double unemploymentInsurance;
  final double incomeTax;
  final double otherDeductions;
  final double totalDescuentos;

  // Líquido
  final double netPay;

  // Status
  final String status;
  final DateTime? paidAt;
  final String? paymentReference;
  final String? payslipUrl;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  PayrollRecord({
    this.id,
    required this.tenantId,
    required this.employeeId,
    required this.periodMonth,
    required this.periodYear,
    required this.paymentDate,
    required this.baseSalary,
    this.overtimePay = 0,
    this.bonuses = 0,
    this.commissions = 0,
    this.mobilityAllowance = 0,
    this.lunchAllowance = 0,
    this.housingAllowance = 0,
    this.otherIncome = 0,
    double? totalHaberes,
    required this.afpContribution,
    required this.healthContribution,
    this.unemploymentInsurance = 0,
    this.incomeTax = 0,
    this.otherDeductions = 0,
    double? totalDescuentos,
    double? netPay,
    this.status = 'draft',
    this.paidAt,
    this.paymentReference,
    this.payslipUrl,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : totalHaberes = totalHaberes ??
            (baseSalary +
                overtimePay +
                bonuses +
                commissions +
                mobilityAllowance +
                lunchAllowance +
                housingAllowance +
                otherIncome),
        totalDescuentos = totalDescuentos ??
            (afpContribution +
                healthContribution +
                unemploymentInsurance +
                incomeTax +
                otherDeductions),
        netPay = netPay ??
            ((totalHaberes ??
                    (baseSalary +
                        overtimePay +
                        bonuses +
                        commissions +
                        mobilityAllowance +
                        lunchAllowance +
                        housingAllowance +
                        otherIncome)) -
                (totalDescuentos ??
                    (afpContribution +
                        healthContribution +
                        unemploymentInsurance +
                        incomeTax +
                        otherDeductions))),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PayrollRecord.fromMap(Map<String, dynamic> map) {
    return PayrollRecord(
      id: map['id'],
      tenantId: map['tenant_id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString() ?? '',
      periodMonth: map['period_month'] ?? 1,
      periodYear: map['period_year'] ?? DateTime.now().year,
      paymentDate: DateTime.parse(map['payment_date']),
      baseSalary: (map['base_salary'] ?? 0).toDouble(),
      overtimePay: (map['overtime_pay'] ?? 0).toDouble(),
      bonuses: (map['bonuses'] ?? 0).toDouble(),
      commissions: (map['commissions'] ?? 0).toDouble(),
      mobilityAllowance: (map['mobility_allowance'] ?? 0).toDouble(),
      lunchAllowance: (map['lunch_allowance'] ?? 0).toDouble(),
      housingAllowance: (map['housing_allowance'] ?? 0).toDouble(),
      otherIncome: (map['other_income'] ?? 0).toDouble(),
      totalHaberes: (map['total_haberes'] ?? 0).toDouble(),
      afpContribution: (map['afp_contribution'] ?? 0).toDouble(),
      healthContribution: (map['health_contribution'] ?? 0).toDouble(),
      unemploymentInsurance: (map['unemployment_insurance'] ?? 0).toDouble(),
      incomeTax: (map['income_tax'] ?? 0).toDouble(),
      otherDeductions: (map['other_deductions'] ?? 0).toDouble(),
      totalDescuentos: (map['total_descuentos'] ?? 0).toDouble(),
      netPay: (map['net_pay'] ?? 0).toDouble(),
      status: map['status'] ?? 'draft',
      paidAt: map['paid_at'] != null ? DateTime.parse(map['paid_at']) : null,
      paymentReference: map['payment_reference'],
      payslipUrl: map['payslip_url'],
      notes: map['notes'],
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'employee_id': employeeId,
      'period_month': periodMonth,
      'period_year': periodYear,
      'payment_date': paymentDate.toIso8601String().split('T')[0],
      'base_salary': baseSalary,
      'overtime_pay': overtimePay,
      'bonuses': bonuses,
      'commissions': commissions,
      'mobility_allowance': mobilityAllowance,
      'lunch_allowance': lunchAllowance,
      'housing_allowance': housingAllowance,
      'other_income': otherIncome,
      'total_haberes': totalHaberes,
      'afp_contribution': afpContribution,
      'health_contribution': healthContribution,
      'unemployment_insurance': unemploymentInsurance,
      'income_tax': incomeTax,
      'other_deductions': otherDeductions,
      'total_descuentos': totalDescuentos,
      'net_pay': netPay,
      'status': status,
      if (paidAt != null) 'paid_at': paidAt!.toIso8601String(),
      if (paymentReference != null) 'payment_reference': paymentReference,
      if (payslipUrl != null) 'payslip_url': payslipUrl,
      if (notes != null) 'notes': notes,
    };
  }

  String get periodLabel => '$periodMonth/$periodYear';

  Color get statusColor {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'approved':
        return Colors.blue;
      case 'paid':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'approved':
        return 'Aprobada';
      case 'paid':
        return 'Pagada';
      default:
        return 'Desconocido';
    }
  }
}
