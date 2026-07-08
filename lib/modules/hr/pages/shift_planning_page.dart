import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/hr_models.dart';
import '../services/hr_service.dart';

enum PlanningDisplayTimeZone { chile, local, utc }

const bool _planningDndDebugLogs = true;
final Map<String, DateTime> _planningDndLastLogAt = {};

void _planningDndLog(
  String event,
  String message, {
  int throttleMs = 0,
}) {
  if (!_planningDndDebugLogs) return;

  if (throttleMs > 0) {
    final now = DateTime.now();
    final lastLogAt = _planningDndLastLogAt[event];
    if (lastLogAt != null &&
        now.difference(lastLogAt).inMilliseconds < throttleMs) {
      return;
    }
    _planningDndLastLogAt[event] = now;
  }

  debugPrint('[planning-dnd][$event] $message');
}

String _debugOffset(Offset offset) {
  return '${offset.dx.toStringAsFixed(1)},${offset.dy.toStringAsFixed(1)}';
}

class ShiftPlanningPage extends StatefulWidget {
  const ShiftPlanningPage({super.key});

  @override
  State<ShiftPlanningPage> createState() => _ShiftPlanningPageState();
}

class _ShiftPlanningPageState extends State<ShiftPlanningPage> {
  final _supabase = Supabase.instance.client;
  late DateTime _weekStart;
  bool _isLoading = true;
  String? _error;
  List<Employee> _employees = [];
  List<_PlannedShift> _shifts = [];
  List<_StorePeriod> _storePeriods = [];
  List<_PlanningRole> _roles = [];
  List<_ShiftChangeRequest> _requests = [];
  bool _isSavingShift = false;
  bool _isCreatingRoles = false;
  bool _isGeneratingDefaultShifts = false;
  PlanningDisplayTimeZone _displayTimeZone = PlanningDisplayTimeZone.chile;

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  DateTime _startOfWeek(DateTime date) {
    final midnight = DateTime(date.year, date.month, date.day);
    return midnight.subtract(Duration(days: midnight.weekday - 1));
  }

  void _setDisplayTimeZone(PlanningDisplayTimeZone value) {
    setState(() => _displayTimeZone = value);
  }

  IconData _displayTimeZoneIcon() {
    return switch (_displayTimeZone) {
      PlanningDisplayTimeZone.chile => Icons.flag,
      PlanningDisplayTimeZone.local => Icons.location_on,
      PlanningDisplayTimeZone.utc => Icons.public,
    };
  }

  String _displayTimeZoneShortLabel() {
    return switch (_displayTimeZone) {
      PlanningDisplayTimeZone.chile => 'Chile',
      PlanningDisplayTimeZone.local => 'Local',
      PlanningDisplayTimeZone.utc => 'UTC',
    };
  }

  String _displayTimeZoneDetailLabel() {
    return switch (_displayTimeZone) {
      PlanningDisplayTimeZone.chile => 'America/Santiago',
      PlanningDisplayTimeZone.local => 'Dispositivo',
      PlanningDisplayTimeZone.utc => 'UTC',
    };
  }

  Widget _buildTimeZoneSelector() {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return PopupMenuButton<PlanningDisplayTimeZone>(
      tooltip: 'Zona horaria',
      onSelected: _setDisplayTimeZone,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: PlanningDisplayTimeZone.chile,
          child: Row(
            children: [
              Icon(Icons.flag, size: 18),
              SizedBox(width: 8),
              Text('Chile (America/Santiago)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: PlanningDisplayTimeZone.local,
          child: Row(
            children: [
              Icon(Icons.location_on, size: 18),
              SizedBox(width: 8),
              Text('Local del dispositivo'),
            ],
          ),
        ),
        PopupMenuItem(
          value: PlanningDisplayTimeZone.utc,
          child: Row(
            children: [
              Icon(Icons.public, size: 18),
              SizedBox(width: 8),
              Text('UTC'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: accent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_displayTimeZoneIcon(), size: 18, color: accent),
            const SizedBox(width: 8),
            Text(
              _displayTimeZoneShortLabel(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _displayTimeZoneDetailLabel(),
              style: theme.textTheme.labelSmall?.copyWith(color: accent),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 20, color: accent),
          ],
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tenantService = context.read<TenantService>();
      final hrService = context.read<HRService>();
      final tenantId = await tenantService.getTenantId();
      if (tenantId == null) throw Exception('No se encontro la tienda actual');

      final weekEnd = _weekStart.add(const Duration(days: 7));
      final results = await Future.wait([
        hrService.getEmployees(status: EmployeeStatus.active),
        _loadPlannedShifts(tenantId, weekEnd),
        _loadStorePeriods(tenantId),
        _loadPlanningRoles(tenantId),
        _loadShiftRequests(tenantId),
        _loadDefaultShiftBlocks(tenantId),
      ]);

      if (!mounted) return;
      final employees = results[0] as List<Employee>;
      var shifts = results[1] as List<_PlannedShift>;
      final storePeriods = results[2] as List<_StorePeriod>;
      final defaultBlocks = results[5] as List<_DefaultShiftBlock>;
      final activeEmployeeIds = {
        for (final employee in employees)
          if (employee.id != null) employee.id!,
      };
      final generatedShifts = await _generateDefaultShiftsForWeek(
        tenantId: tenantId,
        existingShifts: shifts,
        defaultBlocks: defaultBlocks
            .where((block) => activeEmployeeIds.contains(block.employeeId))
            .toList(),
        storePeriods: storePeriods,
      );
      if (generatedShifts.isNotEmpty) {
        shifts = [...shifts, ...generatedShifts]
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
      }
      if (!mounted) return;

      setState(() {
        _employees = employees;
        _shifts = shifts;
        _storePeriods = storePeriods;
        _roles = results[3] as List<_PlanningRole>;
        _requests = results[4] as List<_ShiftChangeRequest>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _isLoading = false;
      });
    }
  }

  Future<List<_PlannedShift>> _loadPlannedShifts(
    String tenantId,
    DateTime weekEnd,
  ) async {
    final chileWeekStart = _planningChileDateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day,
    );
    final chileWeekEnd = _planningChileDateTime(
      weekEnd.year,
      weekEnd.month,
      weekEnd.day,
    );

    final response = await _supabase
        .from('planned_shifts')
        .select('''
          id,
          employee_id,
          title,
          start_at,
          end_at,
          status,
          source,
          planning_role_id,
          store_hours_validated,
          outside_store_hours_reason,
          planning_roles(name, color)
        ''')
        .eq('tenant_id', tenantId)
        .lt('start_at', chileWeekEnd.toUtc().toIso8601String())
        .gt('end_at', chileWeekStart.toUtc().toIso8601String())
        .order('start_at');

    return (response as List)
        .whereType<Map>()
        .map((row) => _PlannedShift.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<_DefaultShiftBlock>> _loadDefaultShiftBlocks(
    String tenantId,
  ) async {
    final response = await _supabase
        .from('employee_default_shift_blocks')
        .select('''
          id,
          employee_id,
          planning_role_id,
          day_of_week,
          start_time,
          end_time,
          timezone,
          planning_roles(name, color)
        ''')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('day_of_week')
        .order('start_time');

    return (response as List)
        .whereType<Map>()
        .map(
            (row) => _DefaultShiftBlock.fromMap(Map<String, dynamic>.from(row)))
        .whereType<_DefaultShiftBlock>()
        .toList();
  }

  Future<List<_StorePeriod>> _loadStorePeriods(String tenantId) async {
    final response = await _supabase
        .from('website_settings')
        .select('key, value')
        .eq('tenant_id', tenantId)
        .inFilter('key', const [
      'business_hours_json',
      'google_business_regular_hours',
    ]);

    final rows = (response as List).whereType<Map>();
    String? rawHours;
    for (final row in rows) {
      final key = row['key']?.toString();
      final value = row['value']?.toString().trim();
      if (value == null || value.isEmpty) continue;
      if (key == 'business_hours_json') {
        rawHours = value;
        break;
      }
      rawHours ??= value;
    }

    if (rawHours == null || rawHours.trim().isEmpty) return const [];
    return _parseStorePeriods(rawHours);
  }

  Future<List<_PlanningRole>> _loadPlanningRoles(String tenantId) async {
    final response = await _supabase
        .from('planning_roles')
        .select('id, code, name, color')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('sort_order')
        .order('name');

    return (response as List)
        .whereType<Map>()
        .map((row) => _PlanningRole.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<_ShiftChangeRequest>> _loadShiftRequests(String tenantId) async {
    final response = await _supabase
        .from('shift_change_requests')
        .select('''
          id,
          employee_id,
          planned_shift_id,
          request_type,
          requested_start_at,
          requested_end_at,
          worker_note,
          status,
          created_at,
          employees!shift_change_requests_employee_tenant_fk(first_name, last_name)
        ''')
        .eq('tenant_id', tenantId)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(20);

    return (response as List)
        .whereType<Map>()
        .map((row) =>
            _ShiftChangeRequest.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  void _moveWeek(int delta) {
    setState(() => _weekStart = _weekStart.add(Duration(days: delta * 7)));
    _loadData();
  }

  Future<void> _createDefaultRoles() async {
    setState(() => _isCreatingRoles = true);

    try {
      final tenantId = await context.read<TenantService>().getTenantId();
      if (tenantId == null) throw Exception('No se encontro la tienda actual');

      await _supabase.from('planning_roles').upsert([
        _roleSeed(tenantId, 'ventas', 'Ventas', '#2563EB', 10),
        _roleSeed(tenantId, 'taller', 'Taller', '#16A34A', 20),
        _roleSeed(tenantId, 'caja', 'Caja', '#F59E0B', 30),
        _roleSeed(tenantId, 'soporte', 'Soporte', '#7C3AED', 40),
      ], onConflict: 'tenant_id,code');

      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron crear los roles: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreatingRoles = false);
    }
  }

  Future<void> _generateDefaultsForVisibleWeek() async {
    if (_isGeneratingDefaultShifts) return;
    setState(() => _isGeneratingDefaultShifts = true);

    try {
      final tenantId = await context.read<TenantService>().getTenantId();
      if (tenantId == null) throw Exception('No se encontro la tienda actual');

      final defaultBlocks = await _loadDefaultShiftBlocks(tenantId);
      final activeEmployeeIds = {
        for (final employee in _employees)
          if (employee.id != null) employee.id!,
      };
      final generatedShifts = await _generateDefaultShiftsForWeek(
        tenantId: tenantId,
        existingShifts: _shifts,
        defaultBlocks: defaultBlocks
            .where((block) => activeEmployeeIds.contains(block.employeeId))
            .toList(),
        storePeriods: _storePeriods,
      );

      if (!mounted) return;
      setState(() {
        if (generatedShifts.isNotEmpty) {
          _shifts = [..._shifts, ...generatedShifts]
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            generatedShifts.isEmpty
                ? 'No hay turnos base pendientes para esta semana'
                : 'Turnos generados: ${generatedShifts.length}',
          ),
          backgroundColor:
              generatedShifts.isEmpty ? Colors.grey.shade700 : Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo generar el horario base: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingDefaultShifts = false);
    }
  }

  Future<List<_PlannedShift>> _generateDefaultShiftsForWeek({
    required String tenantId,
    required List<_PlannedShift> existingShifts,
    required List<_DefaultShiftBlock> defaultBlocks,
    required List<_StorePeriod> storePeriods,
  }) async {
    if (defaultBlocks.isEmpty) return const [];

    final workingShifts = [...existingShifts];
    final rows = <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc().toIso8601String();

    for (final block in defaultBlocks) {
      final day = _weekStart.add(Duration(days: block.dayOfWeek - 1));
      final startAt = _planningChileDateTime(
        day.year,
        day.month,
        day.day,
        block.startMinutes ~/ 60,
        block.startMinutes % 60,
      );
      final endAt = _planningChileDateTime(
        day.year,
        day.month,
        day.day,
        block.endMinutes ~/ 60,
        block.endMinutes % 60,
      );

      final hasOverlap = workingShifts.any((shift) {
        if (shift.status == 'cancelled') return false;
        if (shift.employeeId != block.employeeId) return false;
        return shift.startAt.isBefore(endAt) && shift.endAt.isAfter(startAt);
      });
      if (hasOverlap) continue;

      final validation = _validateAgainstStoreHours(
        startAt,
        endAt,
        storePeriods,
      );
      rows.add({
        'tenant_id': tenantId,
        'employee_id': block.employeeId,
        if (block.planningRoleId != null)
          'planning_role_id': block.planningRoleId,
        'start_at': startAt.toUtc().toIso8601String(),
        'end_at': endAt.toUtc().toIso8601String(),
        'timezone': 'America/Santiago',
        'status': 'published',
        'source': 'default_schedule',
        'store_hours_validated': validation.isValid,
        'outside_store_hours_reason': validation.reason,
        'store_hours_snapshot': validation.snapshot,
        'published_at': now,
      });

      workingShifts.add(
        _PlannedShift(
          id: 'pending-default-${block.id}-${day.toIso8601String()}',
          employeeId: block.employeeId,
          roleId: block.planningRoleId,
          startAt: startAt,
          endAt: endAt,
          status: 'published',
          roleName: block.planningRoleName,
          roleColor: block.planningRoleColor,
          storeHoursValidated: validation.isValid,
          outsideStoreHoursReason: validation.reason,
        ),
      );
    }

    if (rows.isEmpty) return const [];

    final response =
        await _supabase.from('planned_shifts').insert(rows).select('''
      id,
      employee_id,
      title,
      start_at,
      end_at,
      status,
      source,
      planning_role_id,
      store_hours_validated,
      outside_store_hours_reason,
      planning_roles(name, color)
    ''');

    return (response as List)
        .whereType<Map>()
        .map((row) => _PlannedShift.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Map<String, dynamic> _roleSeed(
    String tenantId,
    String code,
    String name,
    String color,
    int sortOrder,
  ) {
    return {
      'tenant_id': tenantId,
      'code': code,
      'name': name,
      'color': color,
      'sort_order': sortOrder,
      'is_active': true,
    };
  }

  Future<void> _openNewShiftDialog({DateTime? initialDay}) async {
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea trabajadores activos.')),
      );
      return;
    }

    final draft = await showDialog<_ShiftDraft>(
      context: context,
      builder: (dialogContext) => _ShiftDialog(
        employees: _employees,
        roles: _roles,
        initialDay: initialDay ?? _weekStart,
        storePeriods: _storePeriods,
      ),
    );

    if (draft == null) return;
    await _saveShift(draft);
  }

  Future<void> _saveShift(_ShiftDraft draft) async {
    setState(() => _isSavingShift = true);

    try {
      final tenantId = await context.read<TenantService>().getTenantId();
      if (tenantId == null) throw Exception('No se encontro la tienda actual');

      final validation = _validateAgainstStoreHours(
        _toPlanningDisplayTimeZone(
          draft.startAt,
          PlanningDisplayTimeZone.chile,
        ),
        _toPlanningDisplayTimeZone(
          draft.endAt,
          PlanningDisplayTimeZone.chile,
        ),
        _storePeriods,
      );

      final response = await _supabase.from('planned_shifts').insert({
        'tenant_id': tenantId,
        'employee_id': draft.employeeId,
        if (draft.roleId != null) 'planning_role_id': draft.roleId,
        'start_at': draft.startAt.toUtc().toIso8601String(),
        'end_at': draft.endAt.toUtc().toIso8601String(),
        'timezone': 'America/Santiago',
        'status': draft.publishNow ? 'published' : 'draft',
        'source': 'manual',
        'store_hours_validated': validation.isValid,
        'outside_store_hours_reason': validation.reason,
        'store_hours_snapshot': validation.snapshot,
        if (draft.publishNow)
          'published_at': DateTime.now().toUtc().toIso8601String(),
      }).select('''
        id,
        employee_id,
        title,
        start_at,
        end_at,
        status,
        source,
        planning_role_id,
        store_hours_validated,
        outside_store_hours_reason,
        planning_roles(name, color)
      ''').single();

      final insertedShift = _PlannedShift.fromMap(
        Map<String, dynamic>.from(response as Map),
      );

      if (!mounted) return;
      _insertShiftLocally(insertedShift);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            validation.isValid
                ? 'Turno creado'
                : 'Turno creado fuera del horario de tienda',
          ),
          backgroundColor: validation.isValid ? Colors.green : Colors.orange,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo crear el turno: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingShift = false);
    }
  }

  Future<void> _createShiftFromWorkerDrop(
    Employee worker,
    DateTime day,
    int startMinutes,
    int durationMinutes,
  ) async {
    final workerId = worker.id;
    if (workerId == null || durationMinutes <= 0) return;

    final endMinutes = startMinutes + durationMinutes;
    final startAt = _planningDisplayDateTime(
      _displayTimeZone,
      day.year,
      day.month,
      day.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
    final endAt = _planningDisplayDateTime(
      _displayTimeZone,
      day.year,
      day.month,
      day.day,
      endMinutes ~/ 60,
      endMinutes % 60,
    );

    _planningDndLog(
      'worker-drop-create',
      'worker=$workerId day=${_formatDate(day)} '
          'start=${_formatClock(startMinutes)} '
          'end=${_formatClock(endMinutes)} duration=${durationMinutes}m',
    );

    await _saveShift(
      _ShiftDraft(
        employeeId: workerId,
        startAt: startAt,
        endAt: endAt,
        publishNow: true,
      ),
    );
  }

  Future<void> _openEditShiftDialog(_PlannedShift shift) async {
    final draft = await showDialog<_ShiftDraft>(
      context: context,
      builder: (dialogContext) => _ShiftDialog(
        employees: _employees,
        roles: _roles,
        initialDay: _toPlanningDisplayTimeZone(
          shift.startAt,
          PlanningDisplayTimeZone.chile,
        ),
        storePeriods: _storePeriods,
        initialShift: shift,
      ),
    );

    if (draft == null) return;
    await _updateShift(shift, draft);
  }

  Future<void> _updateShift(_PlannedShift shift, _ShiftDraft draft) async {
    await _applyShiftUpdate(
      shift,
      employeeId: draft.employeeId,
      roleId: draft.roleId,
      startAt: draft.startAt,
      endAt: draft.endAt,
      status: draft.publishNow ? 'published' : 'draft',
      publishedAt: draft.publishNow ? DateTime.now().toUtc() : null,
    );
  }

  Future<void> _moveShift(
    _PlannedShift shift,
    DateTime targetDay,
    int startMinutes,
  ) async {
    final duration = shift.endAt.difference(shift.startAt);
    final startAt = _planningDisplayDateTime(
      _displayTimeZone,
      targetDay.year,
      targetDay.month,
      targetDay.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
    await _applyShiftUpdate(
      shift,
      employeeId: shift.employeeId,
      roleId: shift.roleId,
      startAt: startAt,
      endAt: startAt.add(duration),
      status: shift.status,
    );
  }

  Future<void> _resizeShift(
    _PlannedShift shift, {
    required bool resizeStart,
    required int deltaMinutes,
  }) async {
    if (deltaMinutes == 0) return;
    _planningDndLog(
      'resize-commit',
      'id=${shift.id} handle=${resizeStart ? 'start' : 'end'} '
          'delta=${deltaMinutes}m',
    );
    final startAt = resizeStart
        ? shift.startAt.add(Duration(minutes: deltaMinutes))
        : shift.startAt;
    final endAt = resizeStart
        ? shift.endAt
        : shift.endAt.add(Duration(minutes: deltaMinutes));
    if (!endAt.isAfter(startAt)) return;

    await _applyShiftUpdate(
      shift,
      employeeId: shift.employeeId,
      roleId: shift.roleId,
      startAt: startAt,
      endAt: endAt,
      status: shift.status,
    );
  }

  Future<void> _applyShiftUpdate(
    _PlannedShift shift, {
    required String? employeeId,
    required String? roleId,
    required DateTime startAt,
    required DateTime endAt,
    required String status,
    DateTime? publishedAt,
  }) async {
    final startChile = _toPlanningDisplayTimeZone(
      startAt,
      PlanningDisplayTimeZone.chile,
    );
    final endChile = _toPlanningDisplayTimeZone(
      endAt,
      PlanningDisplayTimeZone.chile,
    );
    final validation = _validateAgainstStoreHours(
      startChile,
      endChile,
      _storePeriods,
    );
    final previousShift = shift;
    final role = _planningRoleForId(roleId);
    final updatedShift = shift.copyWith(
      employeeId: employeeId,
      roleId: roleId,
      startAt: startAt,
      endAt: endAt,
      status: status,
      roleName: role?.name,
      roleColor: role?.color,
      storeHoursValidated: validation.isValid,
      outsideStoreHoursReason: validation.reason,
    );

    _planningDndLog(
      'optimistic-update',
      'id=${shift.id} '
          'start=${_formatDate(startChile)} ${_formatTime(startChile)} '
          'end=${_formatTime(endChile)} '
          'employee=$employeeId role=$roleId validStore=${validation.isValid}',
    );
    if (mounted) _replaceShiftLocally(updatedShift);

    try {
      await _supabase.from('planned_shifts').update({
        'employee_id': employeeId,
        'planning_role_id': roleId,
        'start_at': startAt.toUtc().toIso8601String(),
        'end_at': endAt.toUtc().toIso8601String(),
        'status': status,
        'store_hours_validated': validation.isValid,
        'outside_store_hours_reason': validation.reason,
        'store_hours_snapshot': validation.snapshot,
        if (publishedAt != null)
          'published_at': publishedAt.toUtc().toIso8601String(),
      }).eq('id', shift.id);
      _planningDndLog('save-success', 'id=${shift.id}');
    } catch (error) {
      if (!mounted) return;
      _planningDndLog('save-failed', 'id=${shift.id} error=$error');
      _replaceShiftLocally(previousShift);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el turno: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _replaceShiftLocally(_PlannedShift updatedShift) {
    final existingIndex =
        _shifts.indexWhere((current) => current.id == updatedShift.id);
    _planningDndLog(
      'local-replace',
      'id=${updatedShift.id} foundIndex=$existingIndex '
          'start=${updatedShift.startAt.toIso8601String()} '
          'end=${updatedShift.endAt.toIso8601String()}',
    );
    setState(() {
      _shifts = [
        for (final current in _shifts)
          if (current.id == updatedShift.id) updatedShift else current,
      ]..sort((a, b) => a.startAt.compareTo(b.startAt));
    });
  }

  void _insertShiftLocally(_PlannedShift shift) {
    _planningDndLog(
      'local-insert',
      'id=${shift.id} start=${shift.startAt.toIso8601String()} '
          'end=${shift.endAt.toIso8601String()}',
    );
    setState(() {
      _shifts = [..._shifts, shift]
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
    });
  }

  _PlanningRole? _planningRoleForId(String? roleId) {
    if (roleId == null) return null;
    for (final role in _roles) {
      if (role.id == roleId) return role;
    }
    return null;
  }

  Future<void> _publishShift(_PlannedShift shift) async {
    try {
      await _supabase.from('planned_shifts').update({
        'status': 'published',
        'published_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', shift.id);

      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo publicar el turno: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelShift(_PlannedShift shift) async {
    try {
      await _supabase.from('planned_shifts').update({
        'status': 'cancelled',
      }).eq('id', shift.id);

      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cancelar el turno: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteShift(_PlannedShift shift) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar turno'),
        content: const Text('Esta accion elimina el turno planificado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.from('planned_shifts').delete().eq('id', shift.id);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el turno: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _approveRequest(_ShiftChangeRequest request) async {
    try {
      if (request.plannedShiftId != null &&
          request.requestedStartAt != null &&
          request.requestedEndAt != null) {
        final requestedStartChile = _toPlanningDisplayTimeZone(
          request.requestedStartAt!,
          PlanningDisplayTimeZone.chile,
        );
        final requestedEndChile = _toPlanningDisplayTimeZone(
          request.requestedEndAt!,
          PlanningDisplayTimeZone.chile,
        );
        final validation = _validateAgainstStoreHours(
          requestedStartChile,
          requestedEndChile,
          _storePeriods,
        );

        await _supabase.from('planned_shifts').update({
          'start_at': request.requestedStartAt!.toUtc().toIso8601String(),
          'end_at': request.requestedEndAt!.toUtc().toIso8601String(),
          'source': 'worker_request',
          'store_hours_validated': validation.isValid,
          'outside_store_hours_reason': validation.reason,
          'store_hours_snapshot': validation.snapshot,
        }).eq('id', request.plannedShiftId!);
      }

      await _supabase.from('shift_change_requests').update({
        'status': 'approved',
        'decided_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', request.id);

      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo aprobar la solicitud: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectRequest(_ShiftChangeRequest request) async {
    try {
      await _supabase.from('shift_change_requests').update({
        'status': 'rejected',
        'decided_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', request.id);

      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo rechazar la solicitud: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Planificación',
      child: Column(
        children: [
          _buildToolbar(context),
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _error != null
                    ? _buildErrorState()
                    : _buildPlanner(context),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final weekEnd = _weekStart.add(const Duration(days: 6));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Semana anterior',
                    onPressed: () => _moveWeek(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Semana',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_formatDate(_weekStart)} - ${_formatDate(weekEnd)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Semana siguiente',
                    onPressed: () => _moveWeek(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(width: 24),
                  if (_roles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton.icon(
                        onPressed:
                            _isCreatingRoles ? null : _createDefaultRoles,
                        icon: _isCreatingRoles
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.badge_outlined),
                        label: const Text('Roles base'),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed:
                        _isSavingShift ? null : () => _openNewShiftDialog(),
                    icon: _isSavingShift
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: const Text('Nuevo turno'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isGeneratingDefaultShifts
                        ? null
                        : _generateDefaultsForVisibleWeek,
                    icon: _isGeneratingDefaultShifts
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_motion_outlined),
                    label: const Text('Horario base'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                  const SizedBox(width: 8),
                  _buildTimeZoneSelector(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanner(BuildContext context) {
    final days =
        List.generate(7, (index) => _weekStart.add(Duration(days: index)));
    final employeeById = {
      for (final employee in _employees)
        if (employee.id != null) employee.id!: employee,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSummaryRow(context),
              if (_requests.isNotEmpty) ...[
                const SizedBox(height: 12),
                _RequestsPanel(
                  requests: _requests,
                  displayTimeZone: _displayTimeZone,
                  onApprove: _approveRequest,
                  onReject: _rejectRequest,
                ),
              ],
              const SizedBox(height: 12),
              ...days.map((day) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DayColumn(
                      day: day,
                      shifts: _shiftsForDay(day),
                      employeeById: employeeById,
                      storePeriod: _storePeriodForDay(day),
                      displayTimeZone: _displayTimeZone,
                      onCreateShift: () => _openNewShiftDialog(initialDay: day),
                      onPublishShift: _publishShift,
                      onCancelShift: _cancelShift,
                      onDeleteShift: _deleteShift,
                    ),
                  )),
            ],
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryRow(context),
                  if (_requests.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _RequestsPanel(
                      requests: _requests,
                      displayTimeZone: _displayTimeZone,
                      onApprove: _approveRequest,
                      onReject: _rejectRequest,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _CalendarWeekView(
                days: days,
                shifts: _shifts,
                employeeById: employeeById,
                storePeriods: _storePeriods,
                displayTimeZone: _displayTimeZone,
                onCreateShift: (day) => _openNewShiftDialog(initialDay: day),
                onCreateShiftFromWorker: _createShiftFromWorkerDrop,
                onEditShift: _openEditShiftDialog,
                onMoveShift: _moveShift,
                onResizeShift: _resizeShift,
                onPublishShift: _publishShift,
                onCancelShift: _cancelShift,
                onDeleteShift: _deleteShift,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(BuildContext context) {
    final theme = Theme.of(context);
    final published =
        _shifts.where((shift) => shift.status == 'published').length;
    final draft = _shifts.where((shift) => shift.status == 'draft').length;
    final plannedMinutes = _shifts.fold<int>(
      0,
      (sum, shift) => sum + shift.endAt.difference(shift.startAt).inMinutes,
    );

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricTile(
          icon: Icons.people_outline,
          label: 'Trabajadores activos',
          value: _employees.length.toString(),
        ),
        _MetricTile(
          icon: Icons.event_available_outlined,
          label: 'Turnos semana',
          value: _shifts.length.toString(),
        ),
        _MetricTile(
          icon: Icons.publish_outlined,
          label: 'Publicados',
          value: published.toString(),
        ),
        _MetricTile(
          icon: Icons.edit_calendar_outlined,
          label: 'Borradores',
          value: draft.toString(),
        ),
        _MetricTile(
          icon: Icons.schedule_outlined,
          label: 'Horas planificadas',
          value: (plannedMinutes / 60).toStringAsFixed(1),
        ),
        if (_storePeriods.isEmpty)
          Text(
            'Horario de tienda no configurado',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
      ],
    );
  }

  List<_PlannedShift> _shiftsForDay(DateTime day) {
    return _shifts.where((shift) {
      final displayedStart =
          _toPlanningDisplayTimeZone(shift.startAt, _displayTimeZone);
      return displayedStart.year == day.year &&
          displayedStart.month == day.month &&
          displayedStart.day == day.day;
    }).toList();
  }

  _StorePeriod? _storePeriodForDay(DateTime day) {
    for (final period in _storePeriods) {
      if (period.weekday == day.weekday) return period;
    }
    return null;
  }
}

class _ShiftDialog extends StatefulWidget {
  const _ShiftDialog({
    required this.employees,
    required this.roles,
    required this.initialDay,
    required this.storePeriods,
    this.initialShift,
  });

  final List<Employee> employees;
  final List<_PlanningRole> roles;
  final DateTime initialDay;
  final List<_StorePeriod> storePeriods;
  final _PlannedShift? initialShift;

  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  String? _employeeId;
  String? _roleId;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _publishNow = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialShift = widget.initialShift;
    if (initialShift != null) {
      final startChile = _toPlanningDisplayTimeZone(
        initialShift.startAt,
        PlanningDisplayTimeZone.chile,
      );
      final endChile = _toPlanningDisplayTimeZone(
        initialShift.endAt,
        PlanningDisplayTimeZone.chile,
      );
      _date = DateTime(startChile.year, startChile.month, startChile.day);
      _employeeId = initialShift.employeeId;
      _roleId = initialShift.roleId;
      _startTime = TimeOfDay(hour: startChile.hour, minute: startChile.minute);
      _endTime = TimeOfDay(hour: endChile.hour, minute: endChile.minute);
      _publishNow = initialShift.status == 'published';
      return;
    }

    _date = DateTime(
      widget.initialDay.year,
      widget.initialDay.month,
      widget.initialDay.day,
    );
    for (final employee in widget.employees) {
      if (employee.id != null) {
        _employeeId = employee.id;
        break;
      }
    }
    final period = _storePeriodForDate(widget.storePeriods, _date);
    _startTime = _timeOfMinutes(period?.openMinutes ?? 10 * 60);
    _endTime = _timeOfMinutes(period?.closeMinutes ?? 18 * 60);
  }

  DateTime get _startAt => _planningChileDateTime(
        _date.year,
        _date.month,
        _date.day,
        _startTime.hour,
        _startTime.minute,
      );

  DateTime get _endAt => _planningChileDateTime(
        _date.year,
        _date.month,
        _date.day,
        _endTime.hour,
        _endTime.minute,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
      _error = null;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
        if (_timeMinutes(_endTime) <= _timeMinutes(_startTime)) {
          _endTime = _timeOfMinutes(
            (_timeMinutes(_startTime) + 4 * 60).clamp(0, 23 * 60 + 59).toInt(),
          );
        }
      } else {
        _endTime = picked;
      }
      _error = null;
    });
  }

  void _submit() {
    if (_employeeId == null) {
      setState(() => _error = 'Selecciona un trabajador.');
      return;
    }
    if (!_endAt.isAfter(_startAt)) {
      setState(() => _error = 'La hora de salida debe ser posterior.');
      return;
    }

    Navigator.of(context).pop(
      _ShiftDraft(
        employeeId: _employeeId!,
        roleId: _roleId,
        startAt: _startAt,
        endAt: _endAt,
        publishNow: _publishNow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validation = _validateAgainstStoreHours(
      _startAt,
      _endAt,
      widget.storePeriods,
    );

    return AlertDialog(
      title: Text(widget.initialShift == null ? 'Nuevo turno' : 'Editar turno'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _employeeId,
                decoration: const InputDecoration(
                  labelText: 'Trabajador',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                items: widget.employees
                    .where((employee) => employee.id != null)
                    .map(
                      (employee) => DropdownMenuItem(
                        value: employee.id!,
                        child: Text(employee.fullName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _employeeId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _roleId,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin rol'),
                  ),
                  ...widget.roles.map(
                    (role) => DropdownMenuItem<String?>(
                      value: role.id,
                      child: Text(role.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _roleId = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_formatDate(_date)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(isStart: true),
                      icon: const Icon(Icons.login_outlined),
                      label: Text(_formatTime(_startAt)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(isStart: false),
                      icon: const Icon(Icons.logout_outlined),
                      label: Text(_formatTime(_endAt)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _publishNow,
                onChanged: (value) => setState(() => _publishNow = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('Publicar de inmediato'),
              ),
              const SizedBox(height: 8),
              _StoreValidationPanel(validation: validation),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(widget.initialShift == null
              ? 'Guardar turno'
              : 'Guardar cambios'),
        ),
      ],
    );
  }
}

class _StoreValidationPanel extends StatelessWidget {
  const _StoreValidationPanel({required this.validation});

  final _StoreValidation validation;

  @override
  Widget build(BuildContext context) {
    final color = validation.isValid ? Colors.green : Colors.orange;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              validation.isValid
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
              color: color.shade700,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                validation.isValid
                    ? 'Dentro del horario de tienda'
                    : validation.reason ?? 'Fuera del horario de tienda',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarWeekView extends StatefulWidget {
  const _CalendarWeekView({
    required this.days,
    required this.shifts,
    required this.employeeById,
    required this.storePeriods,
    required this.displayTimeZone,
    required this.onCreateShift,
    required this.onCreateShiftFromWorker,
    required this.onEditShift,
    required this.onMoveShift,
    required this.onResizeShift,
    required this.onPublishShift,
    required this.onCancelShift,
    required this.onDeleteShift,
  });

  static const double _hourHeight = 64;
  static const double _timeGutterWidth = 64;
  static const double _headerHeight = 78;
  static const double _minimumDayWidth = 196;

  final List<DateTime> days;
  final List<_PlannedShift> shifts;
  final Map<String, Employee> employeeById;
  final List<_StorePeriod> storePeriods;
  final PlanningDisplayTimeZone displayTimeZone;
  final ValueChanged<DateTime> onCreateShift;
  final Future<void> Function(
    Employee worker,
    DateTime day,
    int startMinutes,
    int durationMinutes,
  ) onCreateShiftFromWorker;
  final ValueChanged<_PlannedShift> onEditShift;
  final Future<void> Function(
      _PlannedShift shift, DateTime day, int startMinutes) onMoveShift;
  final Future<void> Function(
    _PlannedShift shift, {
    required bool resizeStart,
    required int deltaMinutes,
  }) onResizeShift;
  final ValueChanged<_PlannedShift> onPublishShift;
  final ValueChanged<_PlannedShift> onCancelShift;
  final ValueChanged<_PlannedShift> onDeleteShift;

  @override
  State<_CalendarWeekView> createState() => _CalendarWeekViewState();
}

class _CalendarWeekViewState extends State<_CalendarWeekView> {
  static const double _hourHeight = _CalendarWeekView._hourHeight;
  static const double _timeGutterWidth = _CalendarWeekView._timeGutterWidth;
  static const double _headerHeight = _CalendarWeekView._headerHeight;
  static const double _minimumDayWidth = _CalendarWeekView._minimumDayWidth;
  static const int _workerDropDefaultDurationMinutes = 4 * 60;

  late final ScrollController _horizontalScrollController;
  late final ScrollController _verticalScrollController;
  final GlobalKey _calendarBodyKey = GlobalKey(
    debugLabel: 'planning-calendar-body',
  );
  _CalendarDragPreview? _dragPreview;
  _CalendarWorkerDragPreview? _workerDragPreview;
  _CalendarResizePreview? _resizePreview;
  String? _activeInteractionShiftId;
  String? _activeInteractionKind;
  bool _resourcesCollapsed = false;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController(
      debugLabel: 'planning-calendar-horizontal',
    );
    _verticalScrollController = ScrollController(
      debugLabel: 'planning-calendar-vertical',
    );
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _setDragPreview(_CalendarDragPreview? preview) {
    final current = _dragPreview;
    final isSame = current?.shift.id == preview?.shift.id &&
        current?.day == preview?.day &&
        current?.startMinutes == preview?.startMinutes;
    if (isSame) {
      if (preview != null) {
        _planningDndLog(
          'preview-same',
          'id=${preview.shift.id} day=${_formatDate(preview.day)} '
              'start=${_formatClock(preview.startMinutes)}',
          throttleMs: 500,
        );
      }
      return;
    }
    if (preview == null) {
      _planningDndLog('preview-clear', 'previous=${current?.shift.id}');
    } else {
      _planningDndLog(
        'preview-set',
        'id=${preview.shift.id} day=${_formatDate(preview.day)} '
            'start=${_formatClock(preview.startMinutes)} '
            'duration=${preview.durationMinutes}m',
        throttleMs: 80,
      );
    }
    setState(() => _dragPreview = preview);
  }

  void _clearDragPreview() {
    if (_dragPreview == null) return;
    _planningDndLog('preview-force-clear', 'id=${_dragPreview?.shift.id}');
    setState(() => _dragPreview = null);
  }

  void _setWorkerDragPreview(_CalendarWorkerDragPreview? preview) {
    final current = _workerDragPreview;
    final isSame = current?.worker.id == preview?.worker.id &&
        current?.day == preview?.day &&
        current?.startMinutes == preview?.startMinutes &&
        current?.durationMinutes == preview?.durationMinutes;
    if (isSame) return;

    if (preview == null) {
      _planningDndLog(
        'worker-preview-clear',
        'previous=${current?.worker.id}',
      );
    } else {
      _planningDndLog(
        'worker-preview-set',
        'worker=${preview.worker.id} day=${_formatDate(preview.day)} '
            'start=${_formatClock(preview.startMinutes)} '
            'duration=${preview.durationMinutes}m',
        throttleMs: 80,
      );
    }

    setState(() => _workerDragPreview = preview);
  }

  void _clearWorkerDragPreview() {
    if (_workerDragPreview == null) return;
    _planningDndLog(
      'worker-preview-force-clear',
      'id=${_workerDragPreview?.worker.id}',
    );
    setState(() => _workerDragPreview = null);
  }

  void _setResizePreview(
    _PlannedShift shift, {
    required bool resizeStart,
    required int deltaMinutes,
  }) {
    if (deltaMinutes == 0) {
      _clearResizePreview();
      return;
    }

    final current = _resizePreview;
    final isSame = current?.shift.id == shift.id &&
        current?.resizeStart == resizeStart &&
        current?.deltaMinutes == deltaMinutes;
    if (isSame) return;

    _planningDndLog(
      'resize-preview-set',
      'id=${shift.id} handle=${resizeStart ? 'start' : 'end'} '
          'delta=${deltaMinutes}m',
      throttleMs: 120,
    );
    setState(() {
      _resizePreview = _CalendarResizePreview(
        shift: shift,
        resizeStart: resizeStart,
        deltaMinutes: deltaMinutes,
      );
    });
  }

  void _clearResizePreview() {
    if (_resizePreview == null) return;
    _planningDndLog('resize-preview-clear', 'id=${_resizePreview?.shift.id}');
    setState(() => _resizePreview = null);
  }

  void _startShiftInteraction(_PlannedShift shift, String kind) {
    if (_activeInteractionShiftId == shift.id &&
        _activeInteractionKind == kind) {
      return;
    }
    _planningDndLog('interaction-start', 'id=${shift.id} kind=$kind');
    setState(() {
      _activeInteractionShiftId = shift.id;
      _activeInteractionKind = kind;
    });
  }

  void _endShiftInteraction(_PlannedShift shift, String kind) {
    if (_activeInteractionShiftId != shift.id) return;
    _planningDndLog('interaction-end', 'id=${shift.id} kind=$kind');
    setState(() {
      _activeInteractionShiftId = null;
      _activeInteractionKind = null;
    });
  }

  void _startWorkerInteraction(_CalendarWorkerDragData data) {
    final workerId = data.worker.id ?? data.worker.fullName;
    if (_activeInteractionShiftId == workerId &&
        _activeInteractionKind == 'worker-drag') {
      return;
    }
    _planningDndLog('worker-interaction-start', 'id=$workerId');
    setState(() {
      _activeInteractionShiftId = workerId;
      _activeInteractionKind = 'worker-drag';
    });
  }

  void _endWorkerInteraction(_CalendarWorkerDragData data) {
    final workerId = data.worker.id ?? data.worker.fullName;
    if (_activeInteractionShiftId != workerId) return;
    _planningDndLog('worker-interaction-end', 'id=$workerId');
    setState(() {
      _activeInteractionShiftId = null;
      _activeInteractionKind = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final startHour = _calendarStartHour(
      widget.days,
      widget.shifts,
      widget.storePeriods,
      widget.displayTimeZone,
    );
    final endHour = _calendarEndHour(
      widget.days,
      widget.shifts,
      widget.storePeriods,
      widget.displayTimeZone,
    );
    final gridHeight = (endHour - startHour) * _hourHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidebar = constraints.maxWidth >= 1180;
        final sidebarWidth =
            showSidebar ? (_resourcesCollapsed ? 44.0 : 252.0) : 0.0;
        final availableCalendarWidth = math.max(
          0.0,
          constraints.maxWidth - sidebarWidth,
        );
        final dayWidth = math.max(
          _minimumDayWidth,
          (availableCalendarWidth - _timeGutterWidth) / 7,
        );
        final calendarWidth = _timeGutterWidth + dayWidth * 7;

        return Row(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _horizontalScrollController,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: calendarWidth,
                    child: Column(
                      children: [
                        _CalendarHeaderRow(
                          days: widget.days,
                          dayWidth: dayWidth,
                          timeGutterWidth: _timeGutterWidth,
                          headerHeight: _headerHeight,
                          onCreateShift: widget.onCreateShift,
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: _verticalScrollController,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.vertical,
                            child: SingleChildScrollView(
                              controller: _verticalScrollController,
                              primary: false,
                              child: SizedBox(
                                key: _calendarBodyKey,
                                width: calendarWidth,
                                height: gridHeight,
                                child: Stack(
                                  children: [
                                    _CalendarGridLines(
                                      startHour: startHour,
                                      endHour: endHour,
                                      hourHeight: _hourHeight,
                                      timeGutterWidth: _timeGutterWidth,
                                      width: calendarWidth,
                                    ),
                                    for (var index = 0;
                                        index < widget.days.length;
                                        index++)
                                      Positioned(
                                        left:
                                            _timeGutterWidth + index * dayWidth,
                                        top: 0,
                                        width: dayWidth,
                                        height: gridHeight,
                                        child: _CalendarDayDropZone(
                                          day: widget.days[index],
                                          storePeriod: _storePeriodForDate(
                                            widget.storePeriods,
                                            widget.days[index],
                                          ),
                                          displayTimeZone:
                                              widget.displayTimeZone,
                                          startHour: startHour,
                                          hourHeight: _hourHeight,
                                          onCreateShift: widget.onCreateShift,
                                        ),
                                      ),
                                    for (var index = 0;
                                        index < widget.days.length;
                                        index++)
                                      ..._buildShiftBlocksForDay(
                                        day: widget.days[index],
                                        dayIndex: index,
                                        dayWidth: dayWidth,
                                        startHour: startHour,
                                        endHour: endHour,
                                      ),
                                    if (_dragPreview != null)
                                      _buildDragPreviewBlock(
                                        preview: _dragPreview!,
                                        dayWidth: dayWidth,
                                        startHour: startHour,
                                      ),
                                    if (_workerDragPreview != null)
                                      _buildWorkerDragPreviewBlock(
                                        preview: _workerDragPreview!,
                                        dayWidth: dayWidth,
                                        startHour: startHour,
                                      ),
                                    if (_resizePreview != null)
                                      _buildResizeGuide(
                                        preview: _resizePreview!,
                                        dayWidth: dayWidth,
                                        startHour: startHour,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showSidebar)
              SizedBox(
                width: sidebarWidth,
                child: _CalendarResourceSidebar(
                  employees: widget.employeeById.values.toList(),
                  shifts: widget.shifts,
                  displayTimeZone: widget.displayTimeZone,
                  isCollapsed: _resourcesCollapsed,
                  onToggleCollapsed: () {
                    setState(
                      () => _resourcesCollapsed = !_resourcesCollapsed,
                    );
                  },
                  onWorkerDragStarted: _startWorkerInteraction,
                  onWorkerDragPositionChanged: (
                    data,
                    globalPosition,
                  ) =>
                      _updateWorkerDragPreviewFromPointer(
                    data: data,
                    globalPosition: globalPosition,
                    dayWidth: dayWidth,
                    startHour: startHour,
                    endHour: endHour,
                  ),
                  onWorkerDragFinished: _finishWorkerPointerDrag,
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildShiftBlocksForDay({
    required DateTime day,
    required int dayIndex,
    required double dayWidth,
    required int startHour,
    required int endHour,
  }) {
    final dayItems = <_CalendarShiftRenderItem>[];
    final activeDragPreview = _dragPreview;
    final activeWorkerPreview = _workerDragPreview;

    for (final shift in widget.shifts) {
      if (activeDragPreview?.shift.id == shift.id) {
        if (!_sameDate(activeDragPreview!.day, day)) continue;
        dayItems.add(
          _CalendarShiftRenderItem(
            shift: shift,
            renderedShift: shift,
            startMinutes: activeDragPreview.startMinutes,
            endMinutes: activeDragPreview.startMinutes +
                activeDragPreview.durationMinutes,
            isPreview: true,
          ),
        );
        continue;
      }

      final renderedShift = _renderedShiftForResizePreview(shift);
      final displayedStart = _toPlanningDisplayTimeZone(
        renderedShift.startAt,
        widget.displayTimeZone,
      );
      if (displayedStart.year != day.year ||
          displayedStart.month != day.month ||
          displayedStart.day != day.day) {
        continue;
      }

      final displayedEnd = _toPlanningDisplayTimeZone(
        renderedShift.endAt,
        widget.displayTimeZone,
      );
      final startMinutes = displayedStart.hour * 60 + displayedStart.minute;
      final endMinutes = displayedEnd.hour * 60 + displayedEnd.minute;
      dayItems.add(
        _CalendarShiftRenderItem(
          shift: shift,
          renderedShift: renderedShift,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
        ),
      );
    }

    if (activeWorkerPreview != null &&
        _sameDate(activeWorkerPreview.day, day)) {
      final previewShift = _previewShiftForWorkerDrag(activeWorkerPreview);
      dayItems.add(
        _CalendarShiftRenderItem(
          shift: previewShift,
          renderedShift: previewShift,
          startMinutes: activeWorkerPreview.startMinutes,
          endMinutes: activeWorkerPreview.startMinutes +
              activeWorkerPreview.durationMinutes,
          isPreview: true,
          isSyntheticPreview: true,
        ),
      );
    }

    final layouts = _layoutCalendarItems(dayItems);
    final widgets = <Widget>[];

    for (final layout in layouts) {
      final item = layout.item;
      if (item.isSyntheticPreview) continue;

      final shift = item.shift;
      final renderedShift = item.renderedShift;
      final top = _topForMinutes(item.startMinutes, startHour, _hourHeight);
      final height = math.max(
        34.0,
        _heightForMinutes(item.endMinutes - item.startMinutes, _hourHeight),
      );
      const laneGap = 6.0;
      final availableWidth = dayWidth - 16;
      final laneWidth = (availableWidth - laneGap * (layout.laneCount - 1)) /
          layout.laneCount;
      final left = _timeGutterWidth +
          dayIndex * dayWidth +
          8 +
          layout.lane * (laneWidth + laneGap);

      final block = _CalendarShiftBlock(
        shift: renderedShift,
        employee: widget.employeeById[shift.employeeId],
        displayTimeZone: widget.displayTimeZone,
        hourHeight: _hourHeight,
        feedbackWidth: laneWidth,
        feedbackHeight: height,
        tooltipEnabled: _activeInteractionKind != 'worker-drag' &&
            _activeInteractionShiftId != shift.id &&
            _dragPreview?.shift.id != shift.id &&
            _resizePreview?.shift.id != shift.id,
        onTap: () => widget.onEditShift(shift),
        onPublish: () => widget.onPublishShift(shift),
        onCancel: () => widget.onCancelShift(shift),
        onDelete: () => widget.onDeleteShift(shift),
        onInteractionStart: (kind) => _startShiftInteraction(shift, kind),
        onInteractionEnd: (kind) => _endShiftInteraction(shift, kind),
        onDragPositionChanged: (
          data,
          globalPosition,
        ) =>
            _updateDragPreviewFromPointer(
          data: data,
          globalPosition: globalPosition,
          dayWidth: dayWidth,
          startHour: startHour,
          endHour: endHour,
        ),
        onDragFinished: (data) => _finishPointerDrag(data),
        onResizePreview: ({
          required bool resizeStart,
          required int deltaMinutes,
        }) =>
            _setResizePreview(
          shift,
          resizeStart: resizeStart,
          deltaMinutes: deltaMinutes,
        ),
        onResize: ({
          required bool resizeStart,
          required int deltaMinutes,
        }) {
          if (deltaMinutes == 0) {
            _clearResizePreview();
            return Future<void>.value();
          }
          _clearResizePreview();
          final update = widget.onResizeShift(
            shift,
            resizeStart: resizeStart,
            deltaMinutes: deltaMinutes,
          );
          return update;
        },
      );

      final positionedTop = top.clamp(0, double.infinity).toDouble();
      final shouldAnimateLane = _activeInteractionKind == 'drag' &&
              _dragPreview != null &&
              _dragPreview?.shift.id != shift.id &&
              _resizePreview?.shift.id != shift.id ||
          _activeInteractionKind == 'worker-drag' &&
              _workerDragPreview != null &&
              _resizePreview?.shift.id != shift.id;

      widgets.add(
        AnimatedPositioned(
          key: ValueKey('planned-shift-${shift.id}'),
          duration: shouldAnimateLane
              ? const Duration(milliseconds: 150)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          left: left,
          top: positionedTop,
          width: laneWidth,
          height: height,
          child: block,
        ),
      );
    }

    return widgets;
  }

  _PlannedShift _renderedShiftForResizePreview(_PlannedShift shift) {
    final preview = _resizePreview;
    if (preview == null || preview.shift.id != shift.id) return shift;

    final previewStart = preview.resizeStart
        ? shift.startAt.add(Duration(minutes: preview.deltaMinutes))
        : shift.startAt;
    final previewEnd = preview.resizeStart
        ? shift.endAt
        : shift.endAt.add(Duration(minutes: preview.deltaMinutes));
    if (!previewEnd.isAfter(previewStart)) return shift;

    return shift.copyWith(startAt: previewStart, endAt: previewEnd);
  }

  void _updateDragPreviewFromPointer({
    required _CalendarShiftDragData data,
    required Offset globalPosition,
    required double dayWidth,
    required int startHour,
    required int endHour,
  }) {
    final preview = _dragPreviewFromPointer(
      data: data,
      globalPosition: globalPosition,
      dayWidth: dayWidth,
      startHour: startHour,
      endHour: endHour,
    );
    _setDragPreview(preview);
  }

  _CalendarDragPreview? _dragPreviewFromPointer({
    required _CalendarShiftDragData data,
    required Offset globalPosition,
    required double dayWidth,
    required int startHour,
    required int endHour,
  }) {
    if (data.shift.status == 'cancelled') return null;
    final box =
        _calendarBodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final grabOffset = data.grabOffset;
    final pointerLocal = box.globalToLocal(globalPosition);
    final blockLocalTopLeft = pointerLocal - grabOffset;
    final calendarX = blockLocalTopLeft.dx - _timeGutterWidth;
    if (calendarX < -dayWidth || calendarX >= dayWidth * widget.days.length) {
      return null;
    }

    final clampedCalendarX = calendarX.clamp(
      0.0,
      math.max(0.0, dayWidth * widget.days.length - 1),
    );
    final dayIndex =
        (clampedCalendarX / dayWidth).floor().clamp(0, widget.days.length - 1);
    final rawMinutes =
        startHour * 60 + ((blockLocalTopLeft.dy / _hourHeight) * 60).round();
    final latestStart = endHour * 60 - data.durationMinutes;
    final snapped = _snapMinutes(rawMinutes).clamp(
      startHour * 60,
      math.max(startHour * 60, latestStart),
    );

    _planningDndLog(
      'pointer-preview',
      'id=${data.shift.id} global=${_debugOffset(globalPosition)} '
          'pointerLocal=${_debugOffset(pointerLocal)} '
          'grab=${_debugOffset(grabOffset)} '
          'block=${_debugOffset(blockLocalTopLeft)} '
          'day=${_formatDate(widget.days[dayIndex])} '
          'start=${_formatClock(snapped.toInt())}',
      throttleMs: 120,
    );

    return _CalendarDragPreview(
      shift: data.shift,
      day: widget.days[dayIndex],
      startMinutes: snapped.toInt(),
      durationMinutes: data.durationMinutes,
    );
  }

  void _finishPointerDrag(_CalendarShiftDragData data) {
    final preview = _dragPreview;
    _clearDragPreview();
    if (preview == null || preview.shift.id != data.shift.id) return;

    final currentStart = _toPlanningDisplayTimeZone(
      data.shift.startAt,
      widget.displayTimeZone,
    );
    final currentStartMinutes = currentStart.hour * 60 + currentStart.minute;
    if (_sameDate(currentStart, preview.day) &&
        currentStartMinutes == preview.startMinutes) {
      _planningDndLog(
        'pointer-drop-same',
        'id=${data.shift.id} day=${_formatDate(preview.day)} '
            'start=${_formatClock(preview.startMinutes)}',
      );
      return;
    }

    _planningDndLog(
      'pointer-drop',
      'id=${data.shift.id} day=${_formatDate(preview.day)} '
          'start=${_formatClock(preview.startMinutes)}',
    );
    widget.onMoveShift(data.shift, preview.day, preview.startMinutes);
  }

  void _updateWorkerDragPreviewFromPointer({
    required _CalendarWorkerDragData data,
    required Offset globalPosition,
    required double dayWidth,
    required int startHour,
    required int endHour,
  }) {
    final preview = _workerDragPreviewFromPointer(
      data: data,
      globalPosition: globalPosition,
      dayWidth: dayWidth,
      startHour: startHour,
      endHour: endHour,
    );
    _setWorkerDragPreview(preview);
  }

  _CalendarWorkerDragPreview? _workerDragPreviewFromPointer({
    required _CalendarWorkerDragData data,
    required Offset globalPosition,
    required double dayWidth,
    required int startHour,
    required int endHour,
  }) {
    if (data.worker.id == null) return null;
    final box =
        _calendarBodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final pointerLocal = box.globalToLocal(globalPosition);
    final calendarX = pointerLocal.dx - _timeGutterWidth;
    if (calendarX < 0 || calendarX >= dayWidth * widget.days.length) {
      return null;
    }

    final clampedCalendarX = calendarX.clamp(
      0.0,
      math.max(0.0, dayWidth * widget.days.length - 1),
    );
    final dayIndex =
        (clampedCalendarX / dayWidth).floor().clamp(0, widget.days.length - 1);
    final rawMinutes =
        startHour * 60 + ((pointerLocal.dy / _hourHeight) * 60).round();
    final snapped = _snapMinutes(rawMinutes);
    final range = _workerDropRangeForDay(
      day: widget.days[dayIndex],
      requestedStartMinutes: snapped,
      startHour: startHour,
      endHour: endHour,
    );

    _planningDndLog(
      'worker-pointer-preview',
      'worker=${data.worker.id} global=${_debugOffset(globalPosition)} '
          'pointerLocal=${_debugOffset(pointerLocal)} '
          'day=${_formatDate(widget.days[dayIndex])} '
          'start=${_formatClock(range.startMinutes)} '
          'duration=${range.durationMinutes}m',
      throttleMs: 120,
    );

    return _CalendarWorkerDragPreview(
      worker: data.worker,
      day: widget.days[dayIndex],
      startMinutes: range.startMinutes,
      durationMinutes: range.durationMinutes,
    );
  }

  _CalendarWorkerDropRange _workerDropRangeForDay({
    required DateTime day,
    required int requestedStartMinutes,
    required int startHour,
    required int endHour,
  }) {
    var minStart = startHour * 60;
    var maxEnd = endHour * 60;
    final period = _storePeriodForDate(widget.storePeriods, day);
    if (period != null) {
      final range = _displayStoreRange(day, period, widget.displayTimeZone);
      minStart = range.start.hour * 60 + range.start.minute;
      maxEnd = range.end.hour * 60 + range.end.minute;
    }

    if (maxEnd <= minStart) {
      minStart = startHour * 60;
      maxEnd = endHour * 60;
    }

    final minimumDuration = math.min(60, math.max(15, maxEnd - minStart));
    final preferredDuration = math.min(
      _workerDropDefaultDurationMinutes,
      math.max(minimumDuration, maxEnd - minStart),
    );
    final latestPreferredStart = math.max(minStart, maxEnd - preferredDuration);
    var startMinutes = requestedStartMinutes.clamp(
      minStart,
      latestPreferredStart,
    );
    var endMinutes = math.min(
      startMinutes + _workerDropDefaultDurationMinutes,
      maxEnd,
    );

    if (endMinutes - startMinutes < minimumDuration) {
      endMinutes = math.min(maxEnd, startMinutes + minimumDuration);
      startMinutes = math.max(minStart, endMinutes - minimumDuration);
    }

    return _CalendarWorkerDropRange(
      startMinutes: startMinutes.toInt(),
      durationMinutes: math.max(
        15,
        endMinutes.toInt() - startMinutes.toInt(),
      ),
    );
  }

  void _finishWorkerPointerDrag(_CalendarWorkerDragData data) {
    final preview = _workerDragPreview;
    _clearWorkerDragPreview();
    _endWorkerInteraction(data);
    if (preview == null || preview.worker.id != data.worker.id) return;

    _planningDndLog(
      'worker-pointer-drop',
      'worker=${data.worker.id} day=${_formatDate(preview.day)} '
          'start=${_formatClock(preview.startMinutes)} '
          'duration=${preview.durationMinutes}m',
    );
    widget.onCreateShiftFromWorker(
      preview.worker,
      preview.day,
      preview.startMinutes,
      preview.durationMinutes,
    );
  }

  _PlannedShift _previewShiftForWorkerDrag(
    _CalendarWorkerDragPreview preview,
  ) {
    final startAt = _planningDisplayDateTime(
      widget.displayTimeZone,
      preview.day.year,
      preview.day.month,
      preview.day.day,
      preview.startMinutes ~/ 60,
      preview.startMinutes % 60,
    );

    return _PlannedShift(
      id: 'worker-preview-${preview.worker.id}',
      employeeId: preview.worker.id,
      startAt: startAt,
      endAt: startAt.add(Duration(minutes: preview.durationMinutes)),
      status: 'published',
    );
  }

  Widget _buildDragPreviewBlock({
    required _CalendarDragPreview preview,
    required double dayWidth,
    required int startHour,
  }) {
    final dayIndex =
        widget.days.indexWhere((day) => _sameDate(day, preview.day));
    if (dayIndex == -1) return const SizedBox.shrink();

    final rawTop = _topForMinutes(preview.startMinutes, startHour, _hourHeight);
    final height = math.max(
      34.0,
      _heightForMinutes(preview.durationMinutes, _hourHeight),
    );
    final previewLane = _previewLaneForDay(
      preview: preview,
      day: preview.day,
    );
    const laneGap = 6.0;
    final availableWidth = dayWidth - 16;
    final laneWidth = (availableWidth - laneGap * (previewLane.laneCount - 1)) /
        previewLane.laneCount;
    final left = _timeGutterWidth +
        dayIndex * dayWidth +
        8 +
        previewLane.lane * (laneWidth + laneGap);
    final top = rawTop.clamp(0, double.infinity).toDouble();

    _planningDndLog(
      'preview-build',
      'id=${preview.shift.id} dayIndex=$dayIndex '
          'left=${left.toStringAsFixed(1)} top=${top.toStringAsFixed(1)} '
          'width=${laneWidth.toStringAsFixed(1)} '
          'height=${height.toStringAsFixed(1)}',
      throttleMs: 120,
    );

    return Positioned(
      left: left,
      top: top,
      width: laneWidth,
      height: height,
      child: IgnorePointer(
        child: _CalendarShiftPreviewBlock(
          shift: preview.shift,
          employee: widget.employeeById[preview.shift.employeeId],
          startMinutes: preview.startMinutes,
          durationMinutes: preview.durationMinutes,
        ),
      ),
    );
  }

  Widget _buildWorkerDragPreviewBlock({
    required _CalendarWorkerDragPreview preview,
    required double dayWidth,
    required int startHour,
  }) {
    final dayIndex =
        widget.days.indexWhere((day) => _sameDate(day, preview.day));
    if (dayIndex == -1) return const SizedBox.shrink();

    final rawTop = _topForMinutes(preview.startMinutes, startHour, _hourHeight);
    final height = math.max(
      34.0,
      _heightForMinutes(preview.durationMinutes, _hourHeight),
    );
    final previewLane = _workerPreviewLaneForDay(preview: preview);
    const laneGap = 6.0;
    final availableWidth = dayWidth - 16;
    final laneWidth = (availableWidth - laneGap * (previewLane.laneCount - 1)) /
        previewLane.laneCount;
    final left = _timeGutterWidth +
        dayIndex * dayWidth +
        8 +
        previewLane.lane * (laneWidth + laneGap);
    final top = rawTop.clamp(0, double.infinity).toDouble();

    _planningDndLog(
      'worker-preview-build',
      'worker=${preview.worker.id} dayIndex=$dayIndex '
          'left=${left.toStringAsFixed(1)} top=${top.toStringAsFixed(1)} '
          'width=${laneWidth.toStringAsFixed(1)} '
          'height=${height.toStringAsFixed(1)}',
      throttleMs: 120,
    );

    return Positioned(
      left: left,
      top: top,
      width: laneWidth,
      height: height,
      child: IgnorePointer(
        child: _CalendarWorkerPreviewBlock(
          worker: preview.worker,
          startMinutes: preview.startMinutes,
          durationMinutes: preview.durationMinutes,
        ),
      ),
    );
  }

  Widget _buildResizeGuide({
    required _CalendarResizePreview preview,
    required double dayWidth,
    required int startHour,
  }) {
    final renderedShift = _renderedShiftForResizePreview(preview.shift);
    final edge = _toPlanningDisplayTimeZone(
      preview.resizeStart ? renderedShift.startAt : renderedShift.endAt,
      widget.displayTimeZone,
    );
    final dayIndex = widget.days.indexWhere((day) => _sameDate(day, edge));
    if (dayIndex == -1) return const SizedBox.shrink();

    final edgeMinutes = edge.hour * 60 + edge.minute;
    final top = _topForMinutes(edgeMinutes, startHour, _hourHeight);
    final color = _workerColor(preview.shift.employeeId ?? preview.shift.id);

    return Positioned(
      left: _timeGutterWidth + dayIndex * dayWidth + 8,
      top: top - 11,
      width: dayWidth - 16,
      height: 22,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 54,
              top: 10,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    _formatClock(edgeMinutes),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _CalendarPreviewLane _previewLaneForDay({
    required _CalendarDragPreview preview,
    required DateTime day,
  }) {
    final items = <_CalendarShiftRenderItem>[];
    for (final shift in widget.shifts) {
      if (shift.id == preview.shift.id) continue;
      final renderedShift = _renderedShiftForResizePreview(shift);
      final displayedStart = _toPlanningDisplayTimeZone(
        renderedShift.startAt,
        widget.displayTimeZone,
      );
      if (!_sameDate(displayedStart, day)) continue;

      final displayedEnd = _toPlanningDisplayTimeZone(
        renderedShift.endAt,
        widget.displayTimeZone,
      );
      items.add(
        _CalendarShiftRenderItem(
          shift: shift,
          renderedShift: renderedShift,
          startMinutes: displayedStart.hour * 60 + displayedStart.minute,
          endMinutes: displayedEnd.hour * 60 + displayedEnd.minute,
        ),
      );
    }

    items.add(
      _CalendarShiftRenderItem(
        shift: preview.shift,
        renderedShift: preview.shift,
        startMinutes: preview.startMinutes,
        endMinutes: preview.startMinutes + preview.durationMinutes,
        isPreview: true,
      ),
    );

    final layout = _layoutCalendarItems(items).firstWhere(
      (layout) => layout.item.isPreview,
      orElse: () => _CalendarShiftLayout(
        item: items.last,
        lane: 0,
        laneCount: 1,
      ),
    );
    return _CalendarPreviewLane(
      lane: layout.lane,
      laneCount: layout.laneCount,
    );
  }

  _CalendarPreviewLane _workerPreviewLaneForDay({
    required _CalendarWorkerDragPreview preview,
  }) {
    final items = <_CalendarShiftRenderItem>[];
    for (final shift in widget.shifts) {
      final renderedShift = _renderedShiftForResizePreview(shift);
      final displayedStart = _toPlanningDisplayTimeZone(
        renderedShift.startAt,
        widget.displayTimeZone,
      );
      if (!_sameDate(displayedStart, preview.day)) continue;

      final displayedEnd = _toPlanningDisplayTimeZone(
        renderedShift.endAt,
        widget.displayTimeZone,
      );
      items.add(
        _CalendarShiftRenderItem(
          shift: shift,
          renderedShift: renderedShift,
          startMinutes: displayedStart.hour * 60 + displayedStart.minute,
          endMinutes: displayedEnd.hour * 60 + displayedEnd.minute,
        ),
      );
    }

    final previewShift = _previewShiftForWorkerDrag(preview);
    items.add(
      _CalendarShiftRenderItem(
        shift: previewShift,
        renderedShift: previewShift,
        startMinutes: preview.startMinutes,
        endMinutes: preview.startMinutes + preview.durationMinutes,
        isPreview: true,
        isSyntheticPreview: true,
      ),
    );

    final layout = _layoutCalendarItems(items).firstWhere(
      (layout) => layout.item.isSyntheticPreview,
      orElse: () => _CalendarShiftLayout(
        item: items.last,
        lane: 0,
        laneCount: 1,
      ),
    );
    return _CalendarPreviewLane(
      lane: layout.lane,
      laneCount: layout.laneCount,
    );
  }
}

class _CalendarHeaderRow extends StatelessWidget {
  const _CalendarHeaderRow({
    required this.days,
    required this.dayWidth,
    required this.timeGutterWidth,
    required this.headerHeight,
    required this.onCreateShift,
  });

  final List<DateTime> days;
  final double dayWidth;
  final double timeGutterWidth;
  final double headerHeight;
  final ValueChanged<DateTime> onCreateShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: headerHeight,
      child: Row(
        children: [
          SizedBox(
            width: timeGutterWidth,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Hora',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          for (final day in days)
            SizedBox(
              width: dayWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: theme.dividerColor),
                    bottom: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _sameDate(day, DateTime.now())
                              ? theme.colorScheme.primary
                              : Colors.grey.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          day.day.toString().padLeft(2, '0'),
                          style: TextStyle(
                            color: _sameDate(day, DateTime.now())
                                ? Colors.white
                                : theme.textTheme.bodyMedium?.color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _weekdayLabel(day),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              _formatDate(day),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nuevo turno',
                        onPressed: () => onCreateShift(day),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarGridLines extends StatelessWidget {
  const _CalendarGridLines({
    required this.startHour,
    required this.endHour,
    required this.hourHeight,
    required this.timeGutterWidth,
    required this.width,
  });

  final int startHour;
  final int endHour;
  final double hourHeight;
  final double timeGutterWidth;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
          ),
        ),
        for (var hour = startHour; hour <= endHour; hour++) ...[
          Positioned(
            left: timeGutterWidth,
            top: (hour - startHour) * hourHeight,
            width: math.max(0, width - timeGutterWidth),
            height: 1,
            child: ColoredBox(color: theme.dividerColor),
          ),
          Positioned(
            left: 0,
            top: math.max(0, (hour - startHour) * hourHeight - 9),
            width: timeGutterWidth - 8,
            height: 18,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatHourLabel(hour),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CalendarDayDropZone extends StatelessWidget {
  const _CalendarDayDropZone({
    required this.day,
    required this.storePeriod,
    required this.displayTimeZone,
    required this.startHour,
    required this.hourHeight,
    required this.onCreateShift,
  });

  final DateTime day;
  final _StorePeriod? storePeriod;
  final PlanningDisplayTimeZone displayTimeZone;
  final int startHour;
  final double hourHeight;
  final ValueChanged<DateTime> onCreateShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final storeRange = storePeriod == null
        ? null
        : _displayStoreRange(day, storePeriod!, displayTimeZone);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => onCreateShift(day),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(left: BorderSide(color: theme.dividerColor)),
        ),
        child: Stack(
          children: [
            if (storeRange != null)
              Positioned(
                top: _topForMinutes(
                  storeRange.start.hour * 60 + storeRange.start.minute,
                  startHour,
                  hourHeight,
                ),
                left: 8,
                right: 8,
                height: math.max(
                  24,
                  _heightForMinutes(
                    storeRange.end.difference(storeRange.start).inMinutes,
                    hourHeight,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CalendarShiftPreviewBlock extends StatelessWidget {
  const _CalendarShiftPreviewBlock({
    required this.shift,
    required this.employee,
    required this.startMinutes,
    required this.durationMinutes,
  });

  final _PlannedShift shift;
  final Employee? employee;
  final int startMinutes;
  final int durationMinutes;

  @override
  Widget build(BuildContext context) {
    final color = _workerColor(shift.employeeId ?? shift.id);
    final endMinutes = startMinutes + durationMinutes;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatClock(startMinutes)} - ${_formatClock(endMinutes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              employee?.fullName ?? 'Sin trabajador',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (shift.roleName != null)
              Text(
                shift.roleName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CalendarWorkerPreviewBlock extends StatelessWidget {
  const _CalendarWorkerPreviewBlock({
    required this.worker,
    required this.startMinutes,
    required this.durationMinutes,
  });

  final Employee worker;
  final int startMinutes;
  final int durationMinutes;

  @override
  Widget build(BuildContext context) {
    final workerId = worker.id ?? worker.fullName;
    final color = _workerColor(workerId);
    final endMinutes = startMinutes + durationMinutes;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatClock(startMinutes)} - ${_formatClock(endMinutes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              worker.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              'Nuevo turno',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarShiftBlock extends StatelessWidget {
  const _CalendarShiftBlock({
    required this.shift,
    required this.employee,
    required this.displayTimeZone,
    required this.hourHeight,
    required this.feedbackWidth,
    required this.feedbackHeight,
    required this.tooltipEnabled,
    required this.onTap,
    required this.onPublish,
    required this.onCancel,
    required this.onDelete,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onDragPositionChanged,
    required this.onDragFinished,
    required this.onResizePreview,
    required this.onResize,
  });

  final _PlannedShift shift;
  final Employee? employee;
  final PlanningDisplayTimeZone displayTimeZone;
  final double hourHeight;
  final double feedbackWidth;
  final double feedbackHeight;
  final bool tooltipEnabled;
  final VoidCallback onTap;
  final VoidCallback onPublish;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final ValueChanged<String> onInteractionStart;
  final ValueChanged<String> onInteractionEnd;
  final void Function(_CalendarShiftDragData data, Offset globalPosition)
      onDragPositionChanged;
  final ValueChanged<_CalendarShiftDragData> onDragFinished;
  final void Function({
    required bool resizeStart,
    required int deltaMinutes,
  }) onResizePreview;
  final Future<void> Function({
    required bool resizeStart,
    required int deltaMinutes,
  }) onResize;

  @override
  Widget build(BuildContext context) {
    final workerName = employee?.fullName ?? 'Sin trabajador';
    final start = _toPlanningDisplayTimeZone(shift.startAt, displayTimeZone);
    final end = _toPlanningDisplayTimeZone(shift.endAt, displayTimeZone);
    final color = _workerColor(shift.employeeId ?? shift.id);
    final durationMinutes = end.difference(start).inMinutes;
    final tooltip = [
      workerName,
      '${_formatDate(start)} ${_formatTime(start)} - ${_formatTime(end)}',
      if (shift.roleName != null) 'Rol: ${shift.roleName}',
      'Estado: ${_statusLabel(shift.status)}',
      'Duracion: ${(durationMinutes / 60).toStringAsFixed(1)} h',
      if (!shift.storeHoursValidated)
        shift.outsideStoreHoursReason ?? 'Fuera del horario tienda',
    ].join('\n');
    final card = TooltipVisibility(
      visible: tooltipEnabled,
      child: Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.manual,
        waitDuration: const Duration(milliseconds: 350),
        child: GestureDetector(
          onTap: tooltipEnabled ? onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(
                  alpha: shift.status == 'draft' ? 0.10 : 0.16),
              border: Border.all(color: color.withValues(alpha: 0.55)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_formatTime(start)} - ${_formatTime(end)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: tooltipEnabled ? 'Acciones' : null,
                            onSelected: (value) {
                              if (value == 'edit') onTap();
                              if (value == 'publish') onPublish();
                              if (value == 'cancel') onCancel();
                              if (value == 'delete') onDelete();
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Editar'),
                              ),
                              if (shift.status == 'draft')
                                const PopupMenuItem(
                                  value: 'publish',
                                  child: Text('Publicar'),
                                ),
                              if (shift.status != 'cancelled')
                                const PopupMenuItem(
                                  value: 'cancel',
                                  child: Text('Cancelar turno'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Eliminar'),
                              ),
                            ],
                            child: const Icon(Icons.more_horiz, size: 18),
                          ),
                        ],
                      ),
                      Text(
                        workerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (shift.roleName != null)
                        Text(
                          shift.roleName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        _statusLabel(shift.status),
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
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
    );
    final dragData = _CalendarShiftDragData(
      shift: shift,
      durationMinutes: durationMinutes,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final resizeHitHeight = math.min(
          22.0,
          math.max(14.0, constraints.maxHeight * 0.35),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: Draggable<_CalendarShiftDragData>(
                data: dragData,
                dragAnchorStrategy: (draggable, context, position) {
                  final box = context.findRenderObject() as RenderBox?;
                  final anchor =
                      box == null ? Offset.zero : box.globalToLocal(position);
                  dragData.grabOffset = anchor;
                  _planningDndLog(
                    'drag-anchor',
                    'id=${shift.id} global=${_debugOffset(position)} '
                        'anchor=${_debugOffset(anchor)}',
                  );
                  return anchor;
                },
                onDragStarted: () {
                  onInteractionStart('drag');
                  _planningDndLog(
                    'drag-start',
                    'id=${shift.id} '
                        'worker=${employee?.fullName ?? 'Sin trabajador'} '
                        'start=${_formatTime(start)} end=${_formatTime(end)} '
                        'feedback=${feedbackWidth.toStringAsFixed(1)}x'
                        '${feedbackHeight.toStringAsFixed(1)} visible=false',
                  );
                },
                onDragUpdate: (details) {
                  onDragPositionChanged(dragData, details.globalPosition);
                  _planningDndLog(
                    'drag-update',
                    'id=${shift.id} '
                        'global=${_debugOffset(details.globalPosition)} '
                        'delta=${_debugOffset(details.delta)}',
                    throttleMs: 120,
                  );
                },
                onDragCompleted: () {
                  _planningDndLog('drag-completed', 'id=${shift.id}');
                },
                onDragEnd: (details) {
                  _planningDndLog(
                    'drag-end',
                    'id=${shift.id} accepted=${details.wasAccepted} '
                        'velocity=${_debugOffset(details.velocity.pixelsPerSecond)}',
                  );
                  onDragFinished(dragData);
                  onInteractionEnd('drag');
                },
                feedback: Material(
                  color: Colors.transparent,
                  child: SizedBox(width: feedbackWidth, height: feedbackHeight),
                ),
                childWhenDragging: const SizedBox.expand(),
                child: card,
              ),
            ),
            Positioned(
              left: 0,
              right: 38,
              top: 0,
              height: resizeHitHeight,
              child: _CalendarResizeHandle(
                alignment: Alignment.topCenter,
                hourHeight: hourHeight,
                onInteractionStart: () => onInteractionStart('resize-start'),
                onInteractionEnd: () => onInteractionEnd('resize-start'),
                onPreview: (deltaMinutes) => onResizePreview(
                  resizeStart: true,
                  deltaMinutes: deltaMinutes,
                ),
                onResize: (deltaMinutes) => onResize(
                  resizeStart: true,
                  deltaMinutes: deltaMinutes,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: resizeHitHeight,
              child: _CalendarResizeHandle(
                alignment: Alignment.bottomCenter,
                hourHeight: hourHeight,
                onInteractionStart: () => onInteractionStart('resize-end'),
                onInteractionEnd: () => onInteractionEnd('resize-end'),
                onPreview: (deltaMinutes) => onResizePreview(
                  resizeStart: false,
                  deltaMinutes: deltaMinutes,
                ),
                onResize: (deltaMinutes) => onResize(
                  resizeStart: false,
                  deltaMinutes: deltaMinutes,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CalendarResizeHandle extends StatefulWidget {
  const _CalendarResizeHandle({
    required this.alignment,
    required this.hourHeight,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onPreview,
    required this.onResize,
  });

  final Alignment alignment;
  final double hourHeight;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;
  final ValueChanged<int> onPreview;
  final ValueChanged<int> onResize;

  @override
  State<_CalendarResizeHandle> createState() => _CalendarResizeHandleState();
}

class _CalendarResizeHandleState extends State<_CalendarResizeHandle> {
  double _dragDelta = 0;
  int _lastPreviewMinutes = 0;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isTop = widget.alignment == Alignment.topCenter;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) {
        _dragDelta = 0;
        _lastPreviewMinutes = 0;
        widget.onInteractionStart();
        _planningDndLog('resize-start', 'handle=${isTop ? 'start' : 'end'}');
      },
      onVerticalDragUpdate: (details) {
        _dragDelta += details.delta.dy;
        final rawMinutes = (_dragDelta / widget.hourHeight) * 60;
        final snapped = _snapDeltaMinutes(rawMinutes.round());
        if (snapped != _lastPreviewMinutes) {
          _lastPreviewMinutes = snapped;
          widget.onPreview(snapped);
        }
        _planningDndLog(
          'resize-update',
          'handle=${isTop ? 'start' : 'end'} '
              'deltaDy=${_dragDelta.toStringAsFixed(1)} '
              'raw=${rawMinutes.toStringAsFixed(1)}m snapped=${snapped}m',
          throttleMs: 120,
        );
      },
      onVerticalDragEnd: (_) {
        final rawMinutes = (_dragDelta / widget.hourHeight) * 60;
        final snapped = _snapDeltaMinutes(rawMinutes.round());
        _planningDndLog(
          'resize-end',
          'handle=${isTop ? 'start' : 'end'} '
              'deltaDy=${_dragDelta.toStringAsFixed(1)} '
              'snapped=${snapped}m',
        );
        _dragDelta = 0;
        _lastPreviewMinutes = 0;
        if (snapped == 0) {
          widget.onPreview(0);
          widget.onInteractionEnd();
          return;
        }
        widget.onResize(snapped);
        widget.onInteractionEnd();
      },
      onVerticalDragCancel: () {
        _planningDndLog(
          'resize-cancel',
          'handle=${isTop ? 'start' : 'end'}',
        );
        _dragDelta = 0;
        _lastPreviewMinutes = 0;
        widget.onPreview(0);
        widget.onInteractionEnd();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Align(
          alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
          child: Container(
            width: 48,
            height: 4,
            margin: EdgeInsets.only(
              top: isTop ? 2 : 0,
              bottom: isTop ? 0 : 2,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: _isHovered ? 0.38 : 0.24),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarShiftDragData {
  _CalendarShiftDragData({
    required this.shift,
    required this.durationMinutes,
  });

  final _PlannedShift shift;
  final int durationMinutes;
  Offset grabOffset = Offset.zero;
}

class _CalendarWorkerDragData {
  _CalendarWorkerDragData({
    required this.worker,
    required this.durationMinutes,
  });

  final Employee worker;
  final int durationMinutes;
}

class _CalendarDragPreview {
  const _CalendarDragPreview({
    required this.shift,
    required this.day,
    required this.startMinutes,
    required this.durationMinutes,
  });

  final _PlannedShift shift;
  final DateTime day;
  final int startMinutes;
  final int durationMinutes;
}

class _CalendarWorkerDragPreview {
  const _CalendarWorkerDragPreview({
    required this.worker,
    required this.day,
    required this.startMinutes,
    required this.durationMinutes,
  });

  final Employee worker;
  final DateTime day;
  final int startMinutes;
  final int durationMinutes;
}

class _CalendarWorkerDropRange {
  const _CalendarWorkerDropRange({
    required this.startMinutes,
    required this.durationMinutes,
  });

  final int startMinutes;
  final int durationMinutes;
}

class _CalendarResizePreview {
  const _CalendarResizePreview({
    required this.shift,
    required this.resizeStart,
    required this.deltaMinutes,
  });

  final _PlannedShift shift;
  final bool resizeStart;
  final int deltaMinutes;
}

class _CalendarShiftRenderItem {
  const _CalendarShiftRenderItem({
    required this.shift,
    required this.renderedShift,
    required this.startMinutes,
    required this.endMinutes,
    this.isPreview = false,
    this.isSyntheticPreview = false,
  });

  final _PlannedShift shift;
  final _PlannedShift renderedShift;
  final int startMinutes;
  final int endMinutes;
  final bool isPreview;
  final bool isSyntheticPreview;
}

class _CalendarShiftLayout {
  const _CalendarShiftLayout({
    required this.item,
    required this.lane,
    required this.laneCount,
  });

  final _CalendarShiftRenderItem item;
  final int lane;
  final int laneCount;
}

class _CalendarPreviewLane {
  const _CalendarPreviewLane({
    required this.lane,
    required this.laneCount,
  });

  final int lane;
  final int laneCount;
}

class _CalendarResourceSidebar extends StatelessWidget {
  const _CalendarResourceSidebar({
    required this.employees,
    required this.shifts,
    required this.displayTimeZone,
    required this.isCollapsed,
    required this.onToggleCollapsed,
    required this.onWorkerDragStarted,
    required this.onWorkerDragPositionChanged,
    required this.onWorkerDragFinished,
  });

  final List<Employee> employees;
  final List<_PlannedShift> shifts;
  final PlanningDisplayTimeZone displayTimeZone;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<_CalendarWorkerDragData> onWorkerDragStarted;
  final void Function(_CalendarWorkerDragData data, Offset globalPosition)
      onWorkerDragPositionChanged;
  final ValueChanged<_CalendarWorkerDragData> onWorkerDragFinished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workers = employees.where((employee) => employee.id != null).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final minutesByWorker = <String, int>{};
    for (final shift in shifts) {
      final employeeId = shift.employeeId;
      if (employeeId == null) continue;
      minutesByWorker[employeeId] = (minutesByWorker[employeeId] ?? 0) +
          shift.endAt.difference(shift.startAt).inMinutes;
    }

    if (isCollapsed) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(left: BorderSide(color: theme.dividerColor)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: _CalendarWeekView._headerHeight,
              child: Center(
                child: IconButton(
                  tooltip: 'Mostrar trabajadores',
                  onPressed: onToggleCollapsed,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            const SizedBox(height: 12),
            const Icon(Icons.people_outline, size: 18),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    'Trabajadores',
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.hintColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _CalendarWeekView._headerHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Trabajadores',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ocultar trabajadores',
                        onPressed: onToggleCollapsed,
                        icon: const Icon(Icons.chevron_right, size: 20),
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _calendarTimeZoneLabel(displayTimeZone),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: workers.isEmpty
                ? Center(
                    child: Text(
                      'Sin trabajadores',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: workers.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final worker = workers[index];
                      final workerId = worker.id!;
                      final color = _workerColor(workerId);
                      final plannedMinutes = minutesByWorker[workerId] ?? 0;

                      return _CalendarResourceWorkerTile(
                        worker: worker,
                        color: color,
                        plannedMinutes: plannedMinutes,
                        durationMinutes: _CalendarWeekViewState
                            ._workerDropDefaultDurationMinutes,
                        onDragStarted: onWorkerDragStarted,
                        onDragPositionChanged: onWorkerDragPositionChanged,
                        onDragFinished: onWorkerDragFinished,
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leyenda',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _CalendarLegendRow(
                  color: theme.colorScheme.primary,
                  label: 'Publicado',
                ),
                const SizedBox(height: 8),
                _CalendarLegendRow(
                  color: Colors.grey.shade600,
                  label: 'Borrador',
                  isDraft: true,
                ),
                const SizedBox(height: 8),
                _CalendarLegendRow(
                  color: Colors.orange.shade700,
                  label: 'Fuera de horario',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarResourceWorkerTile extends StatelessWidget {
  const _CalendarResourceWorkerTile({
    required this.worker,
    required this.color,
    required this.plannedMinutes,
    required this.durationMinutes,
    required this.onDragStarted,
    required this.onDragPositionChanged,
    required this.onDragFinished,
  });

  final Employee worker;
  final Color color;
  final int plannedMinutes;
  final int durationMinutes;
  final ValueChanged<_CalendarWorkerDragData> onDragStarted;
  final void Function(_CalendarWorkerDragData data, Offset globalPosition)
      onDragPositionChanged;
  final ValueChanged<_CalendarWorkerDragData> onDragFinished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workerId = worker.id ?? worker.fullName;
    final dragData = _CalendarWorkerDragData(
      worker: worker,
      durationMinutes: durationMinutes,
    );
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    worker.jobTitle.isEmpty ? 'Sin cargo' : worker.jobTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              plannedMinutes == 0
                  ? '-'
                  : '${(plannedMinutes / 60).toStringAsFixed(1)} h',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );

    return LongPressDraggable<_CalendarWorkerDragData>(
      data: dragData,
      delay: const Duration(milliseconds: 220),
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: (draggable, context, position) {
        _planningDndLog(
          'worker-drag-anchor',
          'worker=$workerId global=${_debugOffset(position)}',
        );
        return Offset.zero;
      },
      onDragStarted: () {
        _planningDndLog(
          'worker-drag-start',
          'worker=$workerId duration=${durationMinutes}m',
        );
        onDragStarted(dragData);
      },
      onDragUpdate: (details) {
        onDragPositionChanged(dragData, details.globalPosition);
        _planningDndLog(
          'worker-drag-update',
          'worker=$workerId global=${_debugOffset(details.globalPosition)}',
          throttleMs: 120,
        );
      },
      onDragEnd: (details) {
        _planningDndLog(
          'worker-drag-end',
          'worker=$workerId accepted=${details.wasAccepted} '
              'velocity=${_debugOffset(details.velocity.pixelsPerSecond)}',
        );
        onDragFinished(dragData);
      },
      feedback: Material(
        color: Colors.transparent,
        child: _CalendarResourceDragFeedback(
          worker: worker,
          color: color,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: tile),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: tile,
      ),
    );
  }
}

class _CalendarResourceDragFeedback extends StatelessWidget {
  const _CalendarResourceDragFeedback({
    required this.worker,
    required this.color,
  });

  final Employee worker;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          border: Border.all(color: color.withValues(alpha: 0.70)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: 184,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    worker.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarLegendRow extends StatelessWidget {
  const _CalendarLegendRow({
    required this.color,
    required this.label,
    this.isDraft = false,
  });

  final Color color;
  final String label;
  final bool isDraft;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDraft ? 0.08 : 0.16),
            border: Border.all(color: color.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.shifts,
    required this.employeeById,
    required this.storePeriod,
    required this.displayTimeZone,
    required this.onCreateShift,
    required this.onPublishShift,
    required this.onCancelShift,
    required this.onDeleteShift,
  });

  final DateTime day;
  final List<_PlannedShift> shifts;
  final Map<String, Employee> employeeById;
  final _StorePeriod? storePeriod;
  final PlanningDisplayTimeZone displayTimeZone;
  final VoidCallback onCreateShift;
  final ValueChanged<_PlannedShift> onPublishShift;
  final ValueChanged<_PlannedShift> onCancelShift;
  final ValueChanged<_PlannedShift> onDeleteShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _weekdayLabel(day),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Nuevo turno',
                  onPressed: onCreateShift,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _formatDate(day),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 8),
            _StoreHoursChip(period: storePeriod),
            const SizedBox(height: 12),
            if (shifts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Sin turnos',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              )
            else
              ...shifts.map(
                (shift) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ShiftCard(
                    shift: shift,
                    employee: employeeById[shift.employeeId],
                    displayTimeZone: displayTimeZone,
                    onPublish: () => onPublishShift(shift),
                    onCancel: () => onCancelShift(shift),
                    onDelete: () => onDeleteShift(shift),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StoreHoursChip extends StatelessWidget {
  const _StoreHoursChip({required this.period});

  final _StorePeriod? period;

  @override
  Widget build(BuildContext context) {
    final text = period == null
        ? 'Cerrado'
        : '${_formatClock(period!.openMinutes)}-${_formatClock(period!.closeMinutes)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: period == null
            ? Colors.grey.withValues(alpha: 0.10)
            : Colors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 16,
              color: period == null ? Colors.grey : Colors.green.shade700,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    required this.employee,
    required this.displayTimeZone,
    required this.onPublish,
    required this.onCancel,
    required this.onDelete,
  });

  final _PlannedShift shift;
  final Employee? employee;
  final PlanningDisplayTimeZone displayTimeZone;
  final VoidCallback onPublish;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final roleColor = _parseColor(shift.roleColor) ?? Colors.blue;
    final workerName = employee?.fullName ?? 'Sin trabajador';
    final start = _toPlanningDisplayTimeZone(shift.startAt, displayTimeZone);
    final end = _toPlanningDisplayTimeZone(shift.endAt, displayTimeZone);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: roleColor, width: 4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatTime(start)} - ${_formatTime(end)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Acciones',
                  onSelected: (value) {
                    if (value == 'publish') onPublish();
                    if (value == 'cancel') onCancel();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    if (shift.status == 'draft')
                      const PopupMenuItem(
                        value: 'publish',
                        child: Text('Publicar'),
                      ),
                    if (shift.status != 'cancelled')
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Text('Cancelar turno'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar'),
                    ),
                  ],
                  child: const Icon(Icons.more_horiz, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(workerName, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (shift.roleName != null) ...[
              const SizedBox(height: 2),
              Text(
                shift.roleName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              _statusLabel(shift.status),
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!shift.storeHoursValidated) ...[
              const SizedBox(height: 6),
              _OutsideStoreHoursChip(reason: shift.outsideStoreHoursReason),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: 180,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestsPanel extends StatelessWidget {
  const _RequestsPanel({
    required this.requests,
    required this.displayTimeZone,
    required this.onApprove,
    required this.onReject,
  });

  final List<_ShiftChangeRequest> requests;
  final PlanningDisplayTimeZone displayTimeZone;
  final ValueChanged<_ShiftChangeRequest> onApprove;
  final ValueChanged<_ShiftChangeRequest> onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Solicitudes pendientes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  requests.length.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...requests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _RequestTile(
                  request: request,
                  displayTimeZone: displayTimeZone,
                  onApprove: () => onApprove(request),
                  onReject: () => onReject(request),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.displayTimeZone,
    required this.onApprove,
    required this.onReject,
  });

  final _ShiftChangeRequest request;
  final PlanningDisplayTimeZone displayTimeZone;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final requestedStart = request.requestedStartAt == null
        ? null
        : _toPlanningDisplayTimeZone(
            request.requestedStartAt!,
            displayTimeZone,
          );
    final requestedEnd = request.requestedEndAt == null
        ? null
        : _toPlanningDisplayTimeZone(
            request.requestedEndAt!,
            displayTimeZone,
          );
    final requested = requestedStart == null || requestedEnd == null
        ? 'Sin horario propuesto'
        : '${_formatDate(requestedStart)} '
            '${_formatTime(requestedStart)}-${_formatTime(requestedEnd)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.workerName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(requested),
            if (request.workerNote != null &&
                request.workerNote!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                request.workerNote!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: const Text('Rechazar'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: const Text('Aprobar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutsideStoreHoursChip extends StatelessWidget {
  const _OutsideStoreHoursChip({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              size: 14,
              color: Colors.orange.shade800,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                reason?.isNotEmpty == true
                    ? reason!
                    : 'Fuera del horario tienda',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftDraft {
  const _ShiftDraft({
    required this.employeeId,
    required this.startAt,
    required this.endAt,
    required this.publishNow,
    this.roleId,
  });

  final String employeeId;
  final String? roleId;
  final DateTime startAt;
  final DateTime endAt;
  final bool publishNow;
}

class _PlanningRole {
  const _PlanningRole({
    required this.id,
    required this.code,
    required this.name,
    this.color,
  });

  final String id;
  final String code;
  final String name;
  final String? color;

  factory _PlanningRole.fromMap(Map<String, dynamic> map) {
    return _PlanningRole(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      color: map['color']?.toString(),
    );
  }
}

class _DefaultShiftBlock {
  const _DefaultShiftBlock({
    required this.id,
    required this.employeeId,
    required this.dayOfWeek,
    required this.startMinutes,
    required this.endMinutes,
    this.planningRoleId,
    this.planningRoleName,
    this.planningRoleColor,
  });

  final String id;
  final String employeeId;
  final String? planningRoleId;
  final String? planningRoleName;
  final String? planningRoleColor;
  final int dayOfWeek;
  final int startMinutes;
  final int endMinutes;

  static _DefaultShiftBlock? fromMap(Map<String, dynamic> map) {
    final role = map['planning_roles'] is Map
        ? Map<String, dynamic>.from(map['planning_roles'] as Map)
        : const <String, dynamic>{};
    final id = map['id']?.toString();
    final employeeId = map['employee_id']?.toString();
    final dayOfWeek = (map['day_of_week'] as num?)?.toInt();
    final startMinutes = _minutesFromSqlTime(map['start_time']);
    final endMinutes = _minutesFromSqlTime(map['end_time']);
    if (id == null ||
        employeeId == null ||
        dayOfWeek == null ||
        startMinutes == null ||
        endMinutes == null ||
        startMinutes >= endMinutes) {
      return null;
    }

    return _DefaultShiftBlock(
      id: id,
      employeeId: employeeId,
      planningRoleId: map['planning_role_id']?.toString(),
      planningRoleName: role['name']?.toString(),
      planningRoleColor: role['color']?.toString(),
      dayOfWeek: dayOfWeek,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
  }
}

class _ShiftChangeRequest {
  const _ShiftChangeRequest({
    required this.id,
    required this.workerName,
    this.plannedShiftId,
    this.requestedStartAt,
    this.requestedEndAt,
    this.workerNote,
  });

  final String id;
  final String workerName;
  final String? plannedShiftId;
  final DateTime? requestedStartAt;
  final DateTime? requestedEndAt;
  final String? workerNote;

  factory _ShiftChangeRequest.fromMap(Map<String, dynamic> map) {
    final employee = map['employees'] is Map
        ? Map<String, dynamic>.from(map['employees'] as Map)
        : const <String, dynamic>{};
    final firstName = employee['first_name']?.toString() ?? '';
    final lastName = employee['last_name']?.toString() ?? '';

    return _ShiftChangeRequest(
      id: map['id']?.toString() ?? '',
      plannedShiftId: map['planned_shift_id']?.toString(),
      workerName: '$firstName $lastName'.trim().isEmpty
          ? 'Trabajador'
          : '$firstName $lastName'.trim(),
      requestedStartAt:
          DateTime.tryParse(map['requested_start_at']?.toString() ?? ''),
      requestedEndAt:
          DateTime.tryParse(map['requested_end_at']?.toString() ?? ''),
      workerNote: map['worker_note']?.toString(),
    );
  }
}

class _PlannedShift {
  const _PlannedShift({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.status,
    this.employeeId,
    this.roleId,
    this.roleName,
    this.roleColor,
    this.storeHoursValidated = true,
    this.outsideStoreHoursReason,
  });

  static const Object _unchanged = Object();

  final String id;
  final String? employeeId;
  final String? roleId;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final String? roleName;
  final String? roleColor;
  final bool storeHoursValidated;
  final String? outsideStoreHoursReason;

  _PlannedShift copyWith({
    Object? employeeId = _unchanged,
    Object? roleId = _unchanged,
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    Object? roleName = _unchanged,
    Object? roleColor = _unchanged,
    bool? storeHoursValidated,
    Object? outsideStoreHoursReason = _unchanged,
  }) {
    return _PlannedShift(
      id: id,
      employeeId: identical(employeeId, _unchanged)
          ? this.employeeId
          : employeeId as String?,
      roleId: identical(roleId, _unchanged) ? this.roleId : roleId as String?,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      status: status ?? this.status,
      roleName:
          identical(roleName, _unchanged) ? this.roleName : roleName as String?,
      roleColor: identical(roleColor, _unchanged)
          ? this.roleColor
          : roleColor as String?,
      storeHoursValidated: storeHoursValidated ?? this.storeHoursValidated,
      outsideStoreHoursReason: identical(outsideStoreHoursReason, _unchanged)
          ? this.outsideStoreHoursReason
          : outsideStoreHoursReason as String?,
    );
  }

  factory _PlannedShift.fromMap(Map<String, dynamic> map) {
    final role = map['planning_roles'] is Map
        ? Map<String, dynamic>.from(map['planning_roles'] as Map)
        : const <String, dynamic>{};

    return _PlannedShift(
      id: map['id']?.toString() ?? '',
      employeeId: map['employee_id']?.toString(),
      roleId: map['planning_role_id']?.toString(),
      startAt: DateTime.parse(map['start_at'].toString()),
      endAt: DateTime.parse(map['end_at'].toString()),
      status: map['status']?.toString() ?? 'draft',
      roleName: role['name']?.toString(),
      roleColor: role['color']?.toString(),
      storeHoursValidated: map['store_hours_validated'] == true,
      outsideStoreHoursReason: map['outside_store_hours_reason']?.toString(),
    );
  }
}

class _StorePeriod {
  const _StorePeriod({
    required this.weekday,
    required this.openMinutes,
    required this.closeMinutes,
  });

  final int weekday;
  final int openMinutes;
  final int closeMinutes;
}

class _StoreValidation {
  const _StoreValidation({
    required this.isValid,
    required this.snapshot,
    this.reason,
  });

  final bool isValid;
  final String? reason;
  final Map<String, dynamic> snapshot;
}

List<_StorePeriod> _parseStorePeriods(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    final root = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
    final data = root['opening_hours'] is Map
        ? Map<String, dynamic>.from(root['opening_hours'] as Map)
        : root;
    final periods = data['periods'] is List
        ? List<dynamic>.from(data['periods'] as List)
        : const <dynamic>[];

    final parsed = <_StorePeriod>[];
    for (final rawPeriod in periods) {
      if (rawPeriod is! Map) continue;
      final period = Map<String, dynamic>.from(rawPeriod);
      final weekday = period.containsKey('openDay')
          ? _businessWeekday(period['openDay'])
          : _placesWeekday(_mapValue(period['open'])?['day']);
      final open = period.containsKey('openTime')
          ? _businessMinutes(period['openTime'])
          : _placesMinutes(_mapValue(period['open'])?['time']);
      final close = period.containsKey('closeTime')
          ? _businessMinutes(period['closeTime'])
          : _placesMinutes(_mapValue(period['close'])?['time']);
      if (weekday == null || open == null || close == null) continue;
      parsed.add(_StorePeriod(
        weekday: weekday,
        openMinutes: open,
        closeMinutes: close,
      ));
    }
    return parsed;
  } catch (_) {
    return const [];
  }
}

_StoreValidation _validateAgainstStoreHours(
  DateTime startAt,
  DateTime endAt,
  List<_StorePeriod> periods,
) {
  final snapshot = {
    'source': 'erp_settings',
    'periods': periods
        .map(
          (period) => {
            'weekday': period.weekday,
            'openMinutes': period.openMinutes,
            'closeMinutes': period.closeMinutes,
          },
        )
        .toList(),
  };

  if (periods.isEmpty) {
    return _StoreValidation(
      isValid: false,
      reason: 'Horario de tienda no configurado',
      snapshot: snapshot,
    );
  }

  if (startAt.year != endAt.year ||
      startAt.month != endAt.month ||
      startAt.day != endAt.day) {
    return _StoreValidation(
      isValid: false,
      reason: 'El turno cruza de dia',
      snapshot: snapshot,
    );
  }

  final period = _storePeriodForDate(periods, startAt);
  if (period == null) {
    return _StoreValidation(
      isValid: false,
      reason: 'La tienda aparece cerrada ese dia',
      snapshot: snapshot,
    );
  }

  final startMinutes = startAt.hour * 60 + startAt.minute;
  final endMinutes = endAt.hour * 60 + endAt.minute;
  if (startMinutes < period.openMinutes || endMinutes > period.closeMinutes) {
    return _StoreValidation(
      isValid: false,
      reason:
          'Fuera del horario ${_formatClock(period.openMinutes)}-${_formatClock(period.closeMinutes)}',
      snapshot: snapshot,
    );
  }

  return _StoreValidation(isValid: true, snapshot: snapshot);
}

int _calendarStartHour(
  List<DateTime> days,
  List<_PlannedShift> shifts,
  List<_StorePeriod> periods,
  PlanningDisplayTimeZone displayTimeZone,
) {
  var earliest = 9 * 60;
  for (final day in days) {
    final period = _storePeriodForDate(periods, day);
    if (period == null) continue;
    final range = _displayStoreRange(day, period, displayTimeZone);
    earliest = math.min(earliest, range.start.hour * 60 + range.start.minute);
  }
  for (final shift in shifts) {
    final start = _toPlanningDisplayTimeZone(shift.startAt, displayTimeZone);
    earliest = math.min(earliest, start.hour * 60 + start.minute);
  }
  return math.max(0, earliest ~/ 60 - 1);
}

int _calendarEndHour(
  List<DateTime> days,
  List<_PlannedShift> shifts,
  List<_StorePeriod> periods,
  PlanningDisplayTimeZone displayTimeZone,
) {
  var latest = 20 * 60;
  for (final day in days) {
    final period = _storePeriodForDate(periods, day);
    if (period == null) continue;
    final range = _displayStoreRange(day, period, displayTimeZone);
    latest = math.max(latest, range.end.hour * 60 + range.end.minute);
  }
  for (final shift in shifts) {
    final end = _toPlanningDisplayTimeZone(shift.endAt, displayTimeZone);
    latest = math.max(latest, end.hour * 60 + end.minute);
  }
  return math.min(24, (latest / 60).ceil() + 1);
}

DateTimeRange _displayStoreRange(
  DateTime day,
  _StorePeriod period,
  PlanningDisplayTimeZone displayTimeZone,
) {
  final start = _planningChileDateTime(
    day.year,
    day.month,
    day.day,
    period.openMinutes ~/ 60,
    period.openMinutes % 60,
  );
  final end = _planningChileDateTime(
    day.year,
    day.month,
    day.day,
    period.closeMinutes ~/ 60,
    period.closeMinutes % 60,
  );
  return DateTimeRange(
    start: _toPlanningDisplayTimeZone(start, displayTimeZone),
    end: _toPlanningDisplayTimeZone(end, displayTimeZone),
  );
}

double _topForMinutes(int minutes, int startHour, double hourHeight) {
  return ((minutes - startHour * 60) / 60) * hourHeight;
}

double _heightForMinutes(int minutes, double hourHeight) {
  return (minutes / 60) * hourHeight;
}

List<_CalendarShiftLayout> _layoutCalendarItems(
  List<_CalendarShiftRenderItem> items,
) {
  final sorted = List<_CalendarShiftRenderItem>.from(items)
    ..sort((a, b) {
      final startComparison = a.startMinutes.compareTo(b.startMinutes);
      if (startComparison != 0) return startComparison;
      final endComparison = b.endMinutes.compareTo(a.endMinutes);
      if (endComparison != 0) return endComparison;
      if (a.isPreview != b.isPreview) return a.isPreview ? 1 : -1;
      return a.shift.id.compareTo(b.shift.id);
    });

  final layouts = <_CalendarShiftLayout>[];
  var group = <_CalendarShiftRenderItem>[];
  var groupEnd = -1;

  void flushGroup() {
    if (group.isEmpty) return;
    final laneEnds = <int>[];
    final groupLayouts = <_CalendarShiftLayout>[];

    for (final item in group) {
      var lane = laneEnds.indexWhere((laneEnd) => laneEnd <= item.startMinutes);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(item.endMinutes);
      } else {
        laneEnds[lane] = item.endMinutes;
      }
      groupLayouts.add(
        _CalendarShiftLayout(
          item: item,
          lane: lane,
          laneCount: 1,
        ),
      );
    }

    final laneCount = math.max(1, laneEnds.length);
    layouts.addAll(
      groupLayouts.map(
        (layout) => _CalendarShiftLayout(
          item: layout.item,
          lane: layout.lane,
          laneCount: laneCount,
        ),
      ),
    );
    group = <_CalendarShiftRenderItem>[];
    groupEnd = -1;
  }

  for (final item in sorted) {
    if (group.isEmpty) {
      group.add(item);
      groupEnd = item.endMinutes;
      continue;
    }

    if (item.startMinutes < groupEnd) {
      group.add(item);
      groupEnd = math.max(groupEnd, item.endMinutes);
    } else {
      flushGroup();
      group.add(item);
      groupEnd = item.endMinutes;
    }
  }
  flushGroup();

  return layouts;
}

Color _workerColor(String seed) {
  const palette = [
    Color(0xFF2563EB),
    Color(0xFF0F766E),
    Color(0xFF7C3AED),
    Color(0xFFDC2626),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFF4F46E5),
    Color(0xFF16A34A),
  ];
  final hash = seed.codeUnits.fold<int>(0, (sum, code) => sum + code);
  return palette[hash % palette.length];
}

int _snapMinutes(int minutes) =>
    ((minutes / 15).round() * 15).clamp(0, 24 * 60);

int _snapDeltaMinutes(int minutes) {
  if (minutes.abs() < 8) return 0;
  return (minutes / 15).round() * 15;
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _formatHourLabel(int hour) {
  final normalized = hour % 24;
  if (normalized == 0) return '12am';
  if (normalized == 12) return '12pm';
  if (normalized < 12) return '${normalized}am';
  return '${normalized - 12}pm';
}

String _calendarTimeZoneLabel(PlanningDisplayTimeZone displayTimeZone) {
  return switch (displayTimeZone) {
    PlanningDisplayTimeZone.chile => 'Hora Chile',
    PlanningDisplayTimeZone.local => 'Hora local',
    PlanningDisplayTimeZone.utc => 'Hora UTC',
  };
}

_StorePeriod? _storePeriodForDate(List<_StorePeriod> periods, DateTime date) {
  for (final period in periods) {
    if (period.weekday == date.weekday) return period;
  }
  return null;
}

Map<String, dynamic>? _mapValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

int? _businessWeekday(dynamic rawDay) {
  final day = rawDay?.toString().toUpperCase();
  return switch (day) {
    'MONDAY' => 1,
    'TUESDAY' => 2,
    'WEDNESDAY' => 3,
    'THURSDAY' => 4,
    'FRIDAY' => 5,
    'SATURDAY' => 6,
    'SUNDAY' => 7,
    _ => null,
  };
}

int? _placesWeekday(dynamic rawDay) {
  final day = rawDay is num ? rawDay.toInt() : int.tryParse('$rawDay');
  return switch (day) {
    1 => 1,
    2 => 2,
    3 => 3,
    4 => 4,
    5 => 5,
    6 => 6,
    0 => 7,
    _ => null,
  };
}

int? _businessMinutes(dynamic rawTime) {
  if (rawTime is String) return _placesMinutes(rawTime);
  if (rawTime is! Map) return null;
  final time = Map<String, dynamic>.from(rawTime);
  final hours = (time['hours'] as num?)?.toInt();
  final minutes = (time['minutes'] as num?)?.toInt() ?? 0;
  if (hours == null) return null;
  return hours.clamp(0, 23).toInt() * 60 + minutes.clamp(0, 59).toInt();
}

int? _placesMinutes(dynamic rawTime) {
  final digits = rawTime?.toString().replaceAll(':', '').trim();
  if (digits == null || digits.length < 3) return null;
  final padded = digits.padLeft(4, '0');
  final hours = int.tryParse(padded.substring(0, 2));
  final minutes = int.tryParse(padded.substring(2, 4));
  if (hours == null || minutes == null) return null;
  return hours.clamp(0, 23).toInt() * 60 + minutes.clamp(0, 59).toInt();
}

int? _minutesFromSqlTime(dynamic rawTime) {
  final text = rawTime?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length < 2) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) return null;
  return hours.clamp(0, 23).toInt() * 60 + minutes.clamp(0, 59).toInt();
}

TimeOfDay _timeOfMinutes(int minutes) {
  final safe = minutes.clamp(0, 23 * 60 + 59).toInt();
  return TimeOfDay(hour: safe ~/ 60, minute: safe % 60);
}

int _timeMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

Color? _parseColor(String? rawColor) {
  final value = rawColor?.replaceAll('#', '').trim();
  if (value == null || value.isEmpty) return null;
  final parsed =
      int.tryParse(value.length == 6 ? 'FF$value' : value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

String _friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('planned_shifts') ||
      message.contains('does not exist')) {
    return 'El modulo de planificacion todavia no esta activado en la base de datos.';
  }
  return message;
}

bool _planningTimeZonesInitialized = false;
tz.Location? _planningChileLocation;

DateTime _planningChileDateTime(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
]) {
  return tz.TZDateTime(
    _planningChileTimeZone(),
    year,
    month,
    day,
    hour,
    minute,
  );
}

DateTime _planningDisplayDateTime(
  PlanningDisplayTimeZone displayTimeZone,
  int year,
  int month,
  int day,
  int hour,
  int minute,
) {
  return switch (displayTimeZone) {
    PlanningDisplayTimeZone.chile => _planningChileDateTime(
        year,
        month,
        day,
        hour,
        minute,
      ),
    PlanningDisplayTimeZone.utc => DateTime.utc(year, month, day, hour, minute),
    PlanningDisplayTimeZone.local => DateTime(year, month, day, hour, minute),
  };
}

DateTime _toPlanningDisplayTimeZone(
  DateTime dateTime,
  PlanningDisplayTimeZone displayTimeZone,
) {
  return switch (displayTimeZone) {
    PlanningDisplayTimeZone.chile =>
      tz.TZDateTime.from(dateTime.toUtc(), _planningChileTimeZone()),
    PlanningDisplayTimeZone.utc => dateTime.toUtc(),
    PlanningDisplayTimeZone.local => dateTime.toLocal(),
  };
}

tz.Location _planningChileTimeZone() {
  if (!_planningTimeZonesInitialized) {
    tzdata.initializeTimeZones();
    _planningChileLocation = tz.getLocation('America/Santiago');
    _planningTimeZonesInitialized = true;
  }
  return _planningChileLocation!;
}

String _weekdayLabel(DateTime date) {
  const labels = [
    'Lunes',
    'Martes',
    'Miercoles',
    'Jueves',
    'Viernes',
    'Sabado',
    'Domingo'
  ];
  return labels[date.weekday - 1];
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _formatClock(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
}

String _statusLabel(String status) {
  switch (status) {
    case 'published':
      return 'Publicado';
    case 'completed':
      return 'Completado';
    case 'cancelled':
      return 'Cancelado';
    default:
      return 'Borrador';
  }
}
