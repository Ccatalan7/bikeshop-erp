import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/services/auth_service.dart';
import '../../hr/widgets/attendance_week_calendar.dart';
import '../../hr/widgets/shift_planning_calendar.dart';

class WorkerHomePage extends StatefulWidget {
  const WorkerHomePage({super.key});

  @override
  State<WorkerHomePage> createState() => _WorkerHomePageState();
}

enum _WorkerPortalSection { resumen, planificacion, asistencias, perfil }

extension _WorkerPortalSectionMeta on _WorkerPortalSection {
  String get label {
    return switch (this) {
      _WorkerPortalSection.resumen => 'Resumen',
      _WorkerPortalSection.planificacion => 'Planificacion',
      _WorkerPortalSection.asistencias => 'Asistencias',
      _WorkerPortalSection.perfil => 'Mi perfil',
    };
  }

  String get description {
    return switch (this) {
      _WorkerPortalSection.resumen => 'Vista rapida de tu semana',
      _WorkerPortalSection.planificacion =>
        'Turnos, horario base y solicitudes',
      _WorkerPortalSection.asistencias => 'Horas trabajadas y pago estimado',
      _WorkerPortalSection.perfil => 'Datos laborales y contacto',
    };
  }

  IconData get icon {
    return switch (this) {
      _WorkerPortalSection.resumen => Icons.dashboard_outlined,
      _WorkerPortalSection.planificacion => Icons.calendar_month_outlined,
      _WorkerPortalSection.asistencias => Icons.access_time_outlined,
      _WorkerPortalSection.perfil => Icons.person_outline,
    };
  }
}

class _WorkerHomePageState extends State<WorkerHomePage> {
  late DateTime _weekStart;
  late Future<List<Map<String, dynamic>>> _shiftsFuture;
  late Future<List<Map<String, dynamic>>> _planningCalendarFuture;
  late Future<List<Map<String, dynamic>>> _requestsFuture;
  late Future<_WorkerAttendanceBundle> _attendanceBundleFuture;
  _WorkerPortalSection _selectedSection = _WorkerPortalSection.resumen;
  bool _planningSidePanelCollapsed = true;

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    _shiftsFuture = _loadShifts();
    _planningCalendarFuture = _loadPlanningCalendar();
    _requestsFuture = _loadRequests();
    _attendanceBundleFuture = _loadAttendanceBundle();
  }

  DateTime _startOfWeek(DateTime date) {
    final midnight = DateTime(date.year, date.month, date.day);
    return midnight.subtract(Duration(days: midnight.weekday - 1));
  }

  Future<List<Map<String, dynamic>>> _loadShifts() async {
    final weekStartAt = _workerWeekStartAtChile(_weekStart);
    final weekEndAt = _workerWeekEndAtChile(_weekStart);
    final response = await Supabase.instance.client.rpc(
      'get_my_worker_shifts',
      params: {
        'p_start_at': weekStartAt.toUtc().toIso8601String(),
        'p_end_at': weekEndAt.toUtc().toIso8601String(),
      },
    );

    if (response is List) {
      return response
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _loadPlanningCalendar() async {
    final weekStartAt = _workerWeekStartAtChile(_weekStart);
    final weekEndAt = _workerWeekEndAtChile(_weekStart);
    try {
      final response = await Supabase.instance.client.rpc(
        'get_worker_portal_planning_calendar',
        params: {
          'p_start_at': weekStartAt.toUtc().toIso8601String(),
          'p_end_at': weekEndAt.toUtc().toIso8601String(),
        },
      );

      return _mapsFromList(response);
    } catch (error) {
      debugPrint('[worker-portal][planning-calendar] fallback: $error');
      final ownShifts = await _loadShifts();
      return ownShifts.map((shift) {
        final next = Map<String, dynamic>.from(shift);
        next['is_my_shift'] = true;
        return next;
      }).toList();
    }
  }

  Future<List<Map<String, dynamic>>> _loadRequests() async {
    final response =
        await Supabase.instance.client.from('shift_change_requests').select('''
          id,
          planned_shift_id,
          request_type,
          requested_start_at,
          requested_end_at,
          worker_note,
          status,
          created_at
        ''').order('created_at', ascending: false).limit(10);

    return (response as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<_WorkerAttendanceBundle> _loadAttendanceBundle() async {
    final weekStartAt = _workerWeekStartAtChile(_weekStart);
    final weekEndAt = _workerWeekEndAtChile(_weekStart);
    final payrollEnd = weekEndAt.subtract(const Duration(days: 1));
    final rawAttendances = await _loadWorkerAttendances(
      weekStartAt,
      weekEndAt,
    );
    final shiftAttendances = await _loadAttendanceFallbackFromShifts(
      weekStartAt,
      weekEndAt,
    );
    final attendances = _mergeAttendanceRows(rawAttendances, shiftAttendances);
    debugPrint(
      '[worker-portal][attendances] '
      'week=${_workerChileDateString(weekStartAt)} '
      'raw=${rawAttendances.length} '
      'shiftFallback=${shiftAttendances.length} '
      'merged=${attendances.length}',
    );
    final payrollRows = await _loadWorkerPayrollRows(payrollEnd);

    return _WorkerAttendanceBundle(
      attendances: attendances,
      payrollRows: payrollRows,
    );
  }

  Future<List<Map<String, dynamic>>> _loadWorkerAttendances(
    DateTime weekStartAt,
    DateTime weekEndAt,
  ) async {
    final client = Supabase.instance.client;
    try {
      final response = await client.rpc(
        'get_my_worker_attendances',
        params: {
          'p_start_at': weekStartAt.toUtc().toIso8601String(),
          'p_end_at': weekEndAt.toUtc().toIso8601String(),
        },
      );
      return _mapsFromList(response);
    } catch (error) {
      debugPrint('[worker-portal][attendances] fallback: $error');
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadWorkerPayrollRows(
    DateTime payrollEnd,
  ) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_my_worker_payroll_for_period',
        params: {
          'p_start_date': _workerChileDateString(_weekStart),
          'p_end_date': _workerChileDateString(payrollEnd),
        },
      );
      return _mapsFromList(response);
    } catch (error) {
      debugPrint('[worker-portal][payroll] unavailable: $error');
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadAttendanceFallbackFromShifts(
    DateTime weekStartAt,
    DateTime weekEndAt,
  ) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_my_worker_shifts',
        params: {
          'p_start_at': weekStartAt.toUtc().toIso8601String(),
          'p_end_at': weekEndAt.toUtc().toIso8601String(),
        },
      );
      return _mapsFromList(response)
          .where((row) => row['first_check_in'] != null)
          .map((row) {
        return {
          'id': 'shift-${row['id']}',
          'check_in': row['first_check_in'],
          'check_out': row['last_check_out'],
          'status': row['last_check_out'] == null ? 'ongoing' : 'completed',
        };
      }).toList();
    } catch (error) {
      debugPrint('[worker-portal][attendance-fallback] failed: $error');
      return const [];
    }
  }

  void _moveWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: delta * 7));
      _shiftsFuture = _loadShifts();
      _planningCalendarFuture = _loadPlanningCalendar();
      _requestsFuture = _loadRequests();
      _attendanceBundleFuture = _loadAttendanceBundle();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _shiftsFuture = _loadShifts();
      _planningCalendarFuture = _loadPlanningCalendar();
      _requestsFuture = _loadRequests();
      _attendanceBundleFuture = _loadAttendanceBundle();
    });
    await Future.wait([
      _shiftsFuture,
      _planningCalendarFuture,
      _requestsFuture,
      _attendanceBundleFuture,
      context.read<AuthService>().refreshWorkerProfile(),
    ]);
  }

  Future<void> _signOut() async {
    await context.read<AuthService>().signOut();
    if (mounted) context.go('/worker/login');
  }

  Future<void> _requestShiftChange(Map<String, dynamic> shift) async {
    final request = await showDialog<_ShiftChangeDraft>(
      context: context,
      builder: (dialogContext) => _ShiftChangeDialog(shift: shift),
    );
    if (request == null) return;

    try {
      await Supabase.instance.client.rpc(
        'request_my_shift_change',
        params: {
          'p_request_type': 'update',
          'p_planned_shift_id': shift['id']?.toString(),
          'p_requested_start_at': request.startAt.toUtc().toIso8601String(),
          'p_requested_end_at': request.endAt.toUtc().toIso8601String(),
          'p_requested_role_id': null,
          'p_worker_note': request.note,
          'p_request_payload': {
            'source': 'worker_pwa',
            'requestedAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud enviada'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() => _requestsFuture = _loadRequests());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar la solicitud: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _requestMoveShift(
    Map<String, dynamic> shift,
    DateTime targetDay,
  ) async {
    final timezone = _shiftTimezone(shift);
    final start = _parseShiftDateTime(shift['start_at'], timezone);
    final end = _parseShiftDateTime(shift['end_at'], timezone);
    if (start == null || end == null || _sameDate(start, targetDay)) return;

    final requestedStart = _zonedDateTime(
      timezone,
      targetDay.year,
      targetDay.month,
      targetDay.day,
      start.hour,
      start.minute,
    );
    final requestedEnd = _zonedDateTime(
      timezone,
      targetDay.year,
      targetDay.month,
      targetDay.day,
      end.hour,
      end.minute,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Solicitar movimiento'),
        content: Text(
          '${_weekdayLabel(start)} ${_formatTime(start)}-${_formatTime(end)}\n'
          '${_weekdayLabel(requestedStart)} ${_formatTime(requestedStart)}-'
          '${_formatTime(requestedEnd)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc(
        'request_my_shift_change',
        params: {
          'p_request_type': 'update',
          'p_planned_shift_id': shift['id']?.toString(),
          'p_requested_start_at': requestedStart.toUtc().toIso8601String(),
          'p_requested_end_at': requestedEnd.toUtc().toIso8601String(),
          'p_requested_role_id': null,
          'p_worker_note': null,
          'p_request_payload': {
            'source': 'worker_pwa_drag_drop',
            'requestedAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud enviada'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _requestsFuture = _loadRequests();
        _shiftsFuture = _loadShifts();
        _planningCalendarFuture = _loadPlanningCalendar();
        _attendanceBundleFuture = _loadAttendanceBundle();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar la solicitud: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _updateOwnShift(
    String shiftId,
    DateTime startAt,
    DateTime endAt,
  ) async {
    if (!endAt.isAfter(startAt)) return;

    try {
      await Supabase.instance.client.rpc(
        'update_my_worker_shift',
        params: {
          'p_shift_id': shiftId,
          'p_start_at': startAt.toUtc().toIso8601String(),
          'p_end_at': endAt.toUtc().toIso8601String(),
        },
      );

      if (!mounted) return;
      setState(() {
        _shiftsFuture = _loadShifts();
        _planningCalendarFuture = _loadPlanningCalendar();
        _attendanceBundleFuture = _loadAttendanceBundle();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turno actualizado'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el turno: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _editDefaultShiftBlocks() async {
    final profile = context.read<AuthService>().workerProfile ?? const {};
    final defaultShiftBlocks = _mapsFromList(profile['defaultShiftBlocks']);
    final planningRoles = _mapsFromList(profile['planningRoles']);
    final drafts = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) => _DefaultScheduleEditorDialog(
        defaultShiftBlocks: defaultShiftBlocks,
        planningRoles: planningRoles,
      ),
    );
    if (drafts == null) return;
    await _saveDefaultShiftBlocks(drafts);
  }

  Future<void> _moveDefaultShiftBlock(
    Map<String, dynamic> block,
    int targetWeekday,
  ) async {
    final profile = context.read<AuthService>().workerProfile ?? const {};
    final blocks = _mapsFromList(profile['defaultShiftBlocks']);
    final blockId = _cleanText(block['id']);
    if (blockId == null || _number(block['dayOfWeek']) == targetWeekday) {
      return;
    }

    final updated = blocks.map((current) {
      final next = Map<String, dynamic>.from(current);
      if (_cleanText(next['id']) == blockId) next['dayOfWeek'] = targetWeekday;
      return _defaultBlockPayload(next);
    }).toList();

    await _saveDefaultShiftBlocks(updated, successMessage: 'Horario movido');
  }

  Future<void> _saveDefaultShiftBlocks(
    List<Map<String, dynamic>> blocks, {
    String successMessage = 'Horario base actualizado',
  }) async {
    final authService = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.rpc(
        'set_my_default_shift_blocks',
        params: {'p_blocks': blocks},
      );
      if (!mounted) return;
      await authService.refreshWorkerProfile();
      if (!mounted) return;
      setState(() {
        _shiftsFuture = _loadShifts();
        _planningCalendarFuture = _loadPlanningCalendar();
        _requestsFuture = _loadRequests();
        _attendanceBundleFuture = _loadAttendanceBundle();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el horario: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final profile = auth.workerProfile;

    if (profile == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 12),
                const Text('Acceso trabajador no disponible'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _signOut,
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final employee = Map<String, dynamic>.from(
      (profile['employee'] as Map?) ?? const {},
    );
    final tenant = Map<String, dynamic>.from(
      (profile['tenant'] as Map?) ?? const {},
    );
    final storeSchedule = Map<String, dynamic>.from(
      (profile['storeSchedule'] as Map?) ?? const {},
    );
    final account = Map<String, dynamic>.from(
      (profile['account'] as Map?) ?? const {},
    );
    final planningRoles = _mapsFromList(profile['planningRoles']);
    final defaultShiftBlocks = _mapsFromList(profile['defaultShiftBlocks']);
    final workerName = employee['fullName']?.toString() ?? 'Trabajador';
    final shopName = tenant['shopName']?.toString() ?? 'Tienda';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 980;

        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: isDesktop
              ? null
              : AppBar(
                  titleSpacing: 16,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        shopName,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Salir',
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_outlined),
                    ),
                  ],
                ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: _WorkerPortalBody(
              isDesktop: isDesktop,
              workerName: workerName,
              shopName: shopName,
              employee: employee,
              account: account,
              planningRoles: planningRoles,
              defaultShiftBlocks: defaultShiftBlocks,
              storeSchedule: storeSchedule,
              weekStart: _weekStart,
              selectedSection: _selectedSection,
              shiftsFuture: _shiftsFuture,
              planningCalendarFuture: _planningCalendarFuture,
              requestsFuture: _requestsFuture,
              attendanceBundleFuture: _attendanceBundleFuture,
              planningSidePanelCollapsed: _planningSidePanelCollapsed,
              onSectionChanged: (section) {
                setState(() => _selectedSection = section);
              },
              onPreviousWeek: () => _moveWeek(-1),
              onNextWeek: () => _moveWeek(1),
              onRefresh: _refresh,
              onSignOut: _signOut,
              onRequestChange: _requestShiftChange,
              onRequestMove: _requestMoveShift,
              onUpdateShift: _updateOwnShift,
              onMoveDefaultBlock: _moveDefaultShiftBlock,
              onEditDefaultSchedule: _editDefaultShiftBlocks,
              onTogglePlanningSidePanel: () {
                setState(() {
                  _planningSidePanelCollapsed = !_planningSidePanelCollapsed;
                });
              },
              onRetryShifts: () {
                setState(() {
                  _shiftsFuture = _loadShifts();
                  _planningCalendarFuture = _loadPlanningCalendar();
                  _attendanceBundleFuture = _loadAttendanceBundle();
                });
              },
            ),
          ),
        );
      },
    );
  }
}

class _WorkerPortalBody extends StatelessWidget {
  const _WorkerPortalBody({
    required this.isDesktop,
    required this.workerName,
    required this.shopName,
    required this.employee,
    required this.account,
    required this.planningRoles,
    required this.defaultShiftBlocks,
    required this.storeSchedule,
    required this.weekStart,
    required this.selectedSection,
    required this.shiftsFuture,
    required this.planningCalendarFuture,
    required this.requestsFuture,
    required this.attendanceBundleFuture,
    required this.planningSidePanelCollapsed,
    required this.onSectionChanged,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onRefresh,
    required this.onSignOut,
    required this.onRequestChange,
    required this.onRequestMove,
    required this.onUpdateShift,
    required this.onMoveDefaultBlock,
    required this.onEditDefaultSchedule,
    required this.onTogglePlanningSidePanel,
    required this.onRetryShifts,
  });

  final bool isDesktop;
  final String workerName;
  final String shopName;
  final Map<String, dynamic> employee;
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> planningRoles;
  final List<Map<String, dynamic>> defaultShiftBlocks;
  final Map<String, dynamic> storeSchedule;
  final DateTime weekStart;
  final _WorkerPortalSection selectedSection;
  final Future<List<Map<String, dynamic>>> shiftsFuture;
  final Future<List<Map<String, dynamic>>> planningCalendarFuture;
  final Future<List<Map<String, dynamic>>> requestsFuture;
  final Future<_WorkerAttendanceBundle> attendanceBundleFuture;
  final bool planningSidePanelCollapsed;
  final ValueChanged<_WorkerPortalSection> onSectionChanged;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;
  final ValueChanged<Map<String, dynamic>> onRequestChange;
  final void Function(Map<String, dynamic> shift, DateTime targetDay)
      onRequestMove;
  final Future<void> Function(
    String shiftId,
    DateTime startAt,
    DateTime endAt,
  ) onUpdateShift;
  final void Function(Map<String, dynamic> block, int targetWeekday)
      onMoveDefaultBlock;
  final VoidCallback onEditDefaultSchedule;
  final VoidCallback onTogglePlanningSidePanel;
  final VoidCallback onRetryShifts;

  @override
  Widget build(BuildContext context) {
    final maxWidth = isDesktop ? 1480.0 : double.infinity;
    final sectionChildren = _sectionChildren(isDesktop);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F8),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: _WorkerPortalNavigationPane(
                    workerName: workerName,
                    shopName: shopName,
                    employee: employee,
                    selectedSection: selectedSection,
                    onSectionChanged: onSectionChanged,
                    onSignOut: onSignOut,
                  ),
                ),
                VerticalDivider(width: 1, color: Colors.grey.shade200),
                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(28),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: sectionChildren,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: sectionChildren,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _WorkerPortalBottomNavigation(
                      selectedSection: selectedSection,
                      onSectionChanged: onSectionChanged,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _sectionChildren(bool desktop) {
    return switch (selectedSection) {
      _WorkerPortalSection.resumen => _summaryChildren(desktop),
      _WorkerPortalSection.planificacion => _planningChildren(desktop),
      _WorkerPortalSection.asistencias => _attendanceChildren(desktop),
      _WorkerPortalSection.perfil => _profileChildren(desktop),
    };
  }

  List<Widget> _summaryChildren(bool desktop) {
    final compact = !desktop;
    final sidePanels = [
      _RequestsFuturePanel(requestsFuture: requestsFuture, showEmpty: true),
      const SizedBox(height: 12),
      _StoreHoursSummary(schedule: storeSchedule),
    ];

    return [
      _WorkerHeroPanel(
        workerName: workerName,
        shopName: shopName,
        employee: employee,
        account: account,
        isDesktop: desktop,
        onRefresh: onRefresh,
        onSignOut: onSignOut,
      ),
      const SizedBox(height: 16),
      _WeekMetricsPanel(
        shiftsFuture: shiftsFuture,
        requestsFuture: requestsFuture,
        compact: compact,
      ),
      const SizedBox(height: 16),
      _PortalSectionHeader(
        section: _WorkerPortalSection.resumen,
        trailing: OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ),
      const SizedBox(height: 12),
      if (desktop)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _WorkerAttendancePaySection(
                weekStart: weekStart,
                attendanceBundleFuture: attendanceBundleFuture,
                employee: employee,
                isDesktop: true,
                compact: true,
                onRetry: onRetryShifts,
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 360,
              child: Column(children: sidePanels),
            ),
          ],
        )
      else ...[
        _WorkerAttendancePaySection(
          weekStart: weekStart,
          attendanceBundleFuture: attendanceBundleFuture,
          employee: employee,
          isDesktop: false,
          compact: true,
          onRetry: onRetryShifts,
        ),
        const SizedBox(height: 14),
        ...sidePanels,
      ],
    ];
  }

  List<Widget> _planningChildren(bool desktop) {
    final planner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekHeader(
          weekStart: weekStart,
          onPrevious: onPreviousWeek,
          onNext: onNextWeek,
        ),
        const SizedBox(height: 12),
        _WorkerPlanningCalendarSection(
          weekStart: weekStart,
          planningCalendarFuture: planningCalendarFuture,
          employee: employee,
          storeSchedule: storeSchedule,
          isDesktop: desktop,
          onRetry: onRetryShifts,
          onUpdateShift: onUpdateShift,
        ),
      ],
    );

    return [
      _PortalSectionHeader(
        section: _WorkerPortalSection.planificacion,
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: onEditDefaultSchedule,
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: const Text('Horario base'),
            ),
            if (desktop)
              OutlinedButton.icon(
                onPressed: onTogglePlanningSidePanel,
                icon: Icon(
                  planningSidePanelCollapsed
                      ? Icons.keyboard_double_arrow_left
                      : Icons.keyboard_double_arrow_right,
                  size: 18,
                ),
                label: Text(
                  planningSidePanelCollapsed ? 'Mostrar' : 'Ocultar',
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (desktop)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: planner),
            const SizedBox(width: 16),
            _PlanningSidePanel(
              collapsed: planningSidePanelCollapsed,
              defaultShiftBlocks: defaultShiftBlocks,
              requestsFuture: requestsFuture,
              onEditDefaultSchedule: onEditDefaultSchedule,
              onToggle: onTogglePlanningSidePanel,
            ),
          ],
        )
      else ...[
        planner,
        const SizedBox(height: 14),
        _DefaultSchedulePanel(
          defaultShiftBlocks: defaultShiftBlocks,
          onEdit: onEditDefaultSchedule,
        ),
        const SizedBox(height: 14),
        _RequestsFuturePanel(requestsFuture: requestsFuture, showEmpty: true),
      ],
    ];
  }

  List<Widget> _attendanceChildren(bool desktop) {
    return [
      _PortalSectionHeader(
        section: _WorkerPortalSection.asistencias,
        trailing: OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ),
      const SizedBox(height: 14),
      _WeekHeader(
        weekStart: weekStart,
        onPrevious: onPreviousWeek,
        onNext: onNextWeek,
      ),
      const SizedBox(height: 12),
      _WorkerAttendancePaySection(
        weekStart: weekStart,
        attendanceBundleFuture: attendanceBundleFuture,
        employee: employee,
        isDesktop: desktop,
        compact: false,
        onRetry: onRetryShifts,
      ),
    ];
  }

  List<Widget> _profileChildren(bool desktop) {
    final panels = [
      _ProfileSnapshotPanel(
        employee: employee,
        account: account,
        planningRoles: planningRoles,
      ),
      const SizedBox(height: 12),
      _DefaultSchedulePanel(
        defaultShiftBlocks: defaultShiftBlocks,
        onEdit: onEditDefaultSchedule,
      ),
      const SizedBox(height: 12),
      _StoreHoursSummary(schedule: storeSchedule),
    ];

    return [
      const _PortalSectionHeader(section: _WorkerPortalSection.perfil),
      const SizedBox(height: 14),
      _WorkerHeroPanel(
        workerName: workerName,
        shopName: shopName,
        employee: employee,
        account: account,
        isDesktop: desktop,
        onRefresh: onRefresh,
        onSignOut: onSignOut,
      ),
      const SizedBox(height: 14),
      if (desktop)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: panels.take(1).toList())),
            const SizedBox(width: 14),
            SizedBox(
              width: 420,
              child: Column(children: panels.skip(1).toList()),
            ),
          ],
        )
      else
        ...panels,
    ];
  }
}

class _WorkerPortalNavigationPane extends StatelessWidget {
  const _WorkerPortalNavigationPane({
    required this.workerName,
    required this.shopName,
    required this.employee,
    required this.selectedSection,
    required this.onSectionChanged,
    required this.onSignOut,
  });

  final String workerName;
  final String shopName;
  final Map<String, dynamic> employee;
  final _WorkerPortalSection selectedSection;
  final ValueChanged<_WorkerPortalSection> onSectionChanged;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 238,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _WorkerAvatar(
                photoUrl: _cleanText(employee['photoUrl']),
                workerName: workerName,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workerName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ..._WorkerPortalSection.values.map(
            (section) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _WorkerPortalNavItem(
                section: section,
                selected: selectedSection == section,
                onTap: () => onSectionChanged(section),
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_outlined, size: 18),
            label: const Text('Salir'),
          ),
        ],
      ),
    );
  }
}

class _WorkerPortalNavItem extends StatelessWidget {
  const _WorkerPortalNavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _WorkerPortalSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF0F6B63) : Colors.grey.shade700;
    return Material(
      color: selected ? const Color(0xFF0F6B63).withValues(alpha: 0.1) : null,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(section.icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkerPortalBottomNavigation extends StatelessWidget {
  const _WorkerPortalBottomNavigation({
    required this.selectedSection,
    required this.onSectionChanged,
  });

  final _WorkerPortalSection selectedSection;
  final ValueChanged<_WorkerPortalSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: NavigationBar(
        selectedIndex: _WorkerPortalSection.values.indexOf(selectedSection),
        onDestinationSelected: (index) {
          onSectionChanged(_WorkerPortalSection.values[index]);
        },
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: _WorkerPortalSection.values
            .map(
              (section) => NavigationDestination(
                icon: Icon(section.icon),
                label: section.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PortalSectionHeader extends StatelessWidget {
  const _PortalSectionHeader({
    required this.section,
    this.trailing,
  });

  final _WorkerPortalSection section;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(section.icon, color: const Color(0xFF0F6B63), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.label,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                section.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class _WorkerHeroPanel extends StatelessWidget {
  const _WorkerHeroPanel({
    required this.workerName,
    required this.shopName,
    required this.employee,
    required this.account,
    required this.isDesktop,
    required this.onRefresh,
    required this.onSignOut,
  });

  final String workerName;
  final String shopName;
  final Map<String, dynamic> employee;
  final Map<String, dynamic> account;
  final bool isDesktop;
  final Future<void> Function() onRefresh;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final photoUrl = _cleanText(employee['photoUrl']);
    final jobTitle = _profileText(employee, 'jobTitle', fallback: 'Sin cargo');
    final department = _cleanText(employee['departmentName']);
    final employeeNumber = _profileText(
      employee,
      'employeeNumber',
      fallback: 'Sin numero',
    );
    final username = _profileText(account, 'username', fallback: 'sin usuario');
    final actionRow = Wrap(
      alignment: isDesktop ? WrapAlignment.end : WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: [
        _HeroFact(
          icon: Icons.work_outline,
          label: jobTitle,
          value: department ?? _employmentTypeLabel(employee),
        ),
        _HeroFact(
          icon: Icons.verified_user_outlined,
          label: 'Estado',
          value: _employeeStatusLabel(employee['status']),
        ),
        IconButton.filledTonal(
          tooltip: 'Actualizar',
          onPressed: () => onRefresh(),
          icon: const Icon(Icons.refresh),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF8FD6D0)),
          ),
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_outlined),
          label: const Text('Salir'),
        ),
      ],
    );
    final identityBlock = Row(
      children: [
        _WorkerAvatar(photoUrl: photoUrl, workerName: workerName),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workerName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isDesktop ? 22 : 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _HeroBadge(
                    icon: Icons.storefront_outlined,
                    text: shopName,
                  ),
                  _HeroBadge(
                    icon: Icons.badge_outlined,
                    text: employeeNumber,
                  ),
                  _HeroBadge(
                    icon: Icons.account_circle_outlined,
                    text: username,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12323A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 22 : 16),
        child: Flex(
          direction: isDesktop ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: isDesktop
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.stretch,
          children: [
            if (isDesktop)
              Expanded(flex: 2, child: identityBlock)
            else
              identityBlock,
            SizedBox(width: isDesktop ? 24 : 0, height: isDesktop ? 0 : 14),
            if (isDesktop)
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: actionRow,
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: actionRow,
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkerAvatar extends StatelessWidget {
  const _WorkerAvatar({required this.photoUrl, required this.workerName});

  final String? photoUrl;
  final String workerName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1F24),
        border: Border.all(color: const Color(0x668FD6D0)),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: photoUrl == null
          ? Text(
              _initials(workerName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            )
          : Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => Text(
                _initials(workerName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFFB8E8E4)),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  const _HeroFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF0F6B63), size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekMetricsPanel extends StatelessWidget {
  const _WeekMetricsPanel({
    required this.shiftsFuture,
    required this.requestsFuture,
    required this.compact,
  });

  final Future<List<Map<String, dynamic>>> shiftsFuture;
  final Future<List<Map<String, dynamic>>> requestsFuture;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: shiftsFuture,
      builder: (context, shiftSnapshot) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: requestsFuture,
          builder: (context, requestSnapshot) {
            final shifts = shiftSnapshot.data ?? const [];
            final requests = requestSnapshot.data ?? const [];
            final plannedMinutes = _sumShiftMinutes(shifts, 'planned_minutes');
            final actualMinutes = _sumShiftMinutes(shifts, 'actual_minutes');
            final varianceMinutes =
                _sumShiftMinutes(shifts, 'variance_minutes');
            final pendingRequests = requests
                .where((request) => request['status']?.toString() == 'pending')
                .length;
            final tiles = [
              _MetricTile(
                icon: Icons.calendar_month_outlined,
                label: 'Turnos semana',
                value: shifts.length.toString(),
                detail: shifts.isEmpty ? 'Sin publicar' : 'Planificados',
                accent: const Color(0xFF2563EB),
              ),
              _MetricTile(
                icon: Icons.schedule_outlined,
                label: 'Horas planificadas',
                value: _minutesAsHours(plannedMinutes),
                detail: actualMinutes > 0
                    ? '${_minutesAsHours(actualMinutes)} reales'
                    : 'Esperando asistencia',
                accent: const Color(0xFF0F766E),
              ),
              _MetricTile(
                icon: Icons.query_stats_outlined,
                label: 'Diferencia asistencia',
                value: varianceMinutes == 0
                    ? '0 min'
                    : _varianceLabel(varianceMinutes),
                detail: 'Turno vs marcaje',
                accent: varianceMinutes == 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFF59E0B),
              ),
              _MetricTile(
                icon: Icons.pending_actions_outlined,
                label: 'Solicitudes',
                value: pendingRequests.toString(),
                detail: pendingRequests == 1 ? 'Pendiente' : 'Pendientes',
                accent: const Color(0xFF7C3AED),
              ),
            ];

            if (compact) {
              return GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.55,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: tiles,
              );
            }

            return Row(
              children: tiles
                  .map(
                    (tile) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: tile,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerAttendancePaySection extends StatelessWidget {
  const _WorkerAttendancePaySection({
    required this.weekStart,
    required this.attendanceBundleFuture,
    required this.employee,
    required this.isDesktop,
    required this.compact,
    required this.onRetry,
  });

  final DateTime weekStart;
  final Future<_WorkerAttendanceBundle> attendanceBundleFuture;
  final Map<String, dynamic> employee;
  final bool isDesktop;
  final bool compact;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WorkerAttendanceBundle>(
      future: attendanceBundleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PanelSurface(
            icon: Icons.access_time_outlined,
            title: 'Asistencias',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(minHeight: 3),
                SizedBox(height: 12),
                Text('Cargando asistencias...'),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return _MessagePanel(
            icon: Icons.error_outline,
            text: 'No se pudieron cargar tus asistencias.',
            actionLabel: 'Reintentar',
            onAction: onRetry,
          );
        }

        final bundle = snapshot.data ?? const _WorkerAttendanceBundle.empty();
        final profileWorkerId = _cleanText(employee['id']);
        final entries = _attendanceEntriesFromRows(
          bundle.attendances,
          fallbackWorkerId: profileWorkerId ?? 'worker',
        );
        final workerId = profileWorkerId ??
            (entries.isEmpty ? 'worker' : entries.first.workerId);
        final worker = _attendanceWorkerFromProfile(employee, workerId);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkerPayrollStatusPanel(
              weekStart: weekStart,
              entries: entries,
              payrollRows: bundle.payrollRows,
              isDesktop: isDesktop,
              compact: compact,
            ),
            if (!compact) ...[
              const SizedBox(height: 14),
              _PanelSurface(
                icon: Icons.calendar_view_week_outlined,
                title: 'Detalle semanal',
                child: AttendanceWeekCalendar(
                  weekStart: weekStart,
                  workers: [worker],
                  entriesByWorkerId: {workerId: entries},
                  toDisplayTimeZone: _workerPortalAttendanceDisplayTime,
                  padding: EdgeInsets.zero,
                  workerColumnWidth: isDesktop ? 250 : 190,
                  dayColumnWidth: isDesktop ? 168 : 138,
                  rowHeight: isDesktop ? 104 : 96,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _WorkerPayrollStatusPanel extends StatelessWidget {
  const _WorkerPayrollStatusPanel({
    required this.weekStart,
    required this.entries,
    required this.payrollRows,
    required this.isDesktop,
    required this.compact,
  });

  final DateTime weekStart;
  final List<AttendanceWeekEntry> entries;
  final List<Map<String, dynamic>> payrollRows;
  final bool isDesktop;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final workedMinutes =
        entries.fold<num>(0, (sum, entry) => sum + entry.duration.inMinutes);
    final primaryPayroll = payrollRows.isEmpty
        ? null
        : Map<String, dynamic>.from(payrollRows.first);
    final status = _cleanText(primaryPayroll?['status']) ?? 'pending';
    final amount = _number(primaryPayroll?['total_amount']);
    final hours = _number(primaryPayroll?['worked_hours']);
    final period = primaryPayroll == null
        ? _weekRangeLabel(weekStart)
        : _payrollPeriodLabel(primaryPayroll);

    final tiles = [
      _PayrollSummaryTile(
        icon: Icons.fingerprint_outlined,
        label: 'Trabajado',
        value: _minutesAsHours(workedMinutes),
        detail: entries.isEmpty ? 'Sin marcajes' : 'Marcajes semana',
      ),
      _PayrollSummaryTile(
        icon: Icons.payments_outlined,
        label: 'Nómina',
        value: amount == null ? 'Sin nómina' : _moneyLabel(amount),
        detail: primaryPayroll == null
            ? 'Pendiente de generar'
            : '${_numberLabel(hours)} h registradas',
      ),
      _PayrollSummaryTile(
        icon: Icons.verified_outlined,
        label: 'Estado',
        value: _payrollStatusLabel(status),
        detail: primaryPayroll == null
            ? 'Sin comprobante'
            : _cleanText(primaryPayroll['voucher_number']) ?? 'Comprobante',
        statusColor: _payrollStatusColor(status),
      ),
      _PayrollSummaryTile(
        icon: Icons.date_range_outlined,
        label: 'Periodo',
        value: period,
        detail: _paymentMethodText(primaryPayroll),
      ),
    ];

    return _PanelSurface(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Horas y nómina',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: isDesktop && !compact ? 4 : 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: isDesktop ? 2.55 : 1.55,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: tiles,
          ),
          if (payrollRows.length > 1) ...[
            const Divider(height: 24),
            ...payrollRows.skip(1).take(3).map(_PayrollCompactLine.new),
          ],
        ],
      ),
    );
  }
}

class _PayrollSummaryTile extends StatelessWidget {
  const _PayrollSummaryTile({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.statusColor,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final accent = statusColor ?? const Color(0xFF0F6B63);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade600,
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

class _PayrollCompactLine extends StatelessWidget {
  const _PayrollCompactLine(this.row);

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = _cleanText(row['status']) ?? 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _TinyTag(
            text: _payrollStatusLabel(status),
            color: _payrollStatusColor(status),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _payrollPeriodLabel(row),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            _moneyLabel(_number(row['total_amount']) ?? 0),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _WorkerAttendanceBundle {
  const _WorkerAttendanceBundle({
    required this.attendances,
    required this.payrollRows,
  });

  const _WorkerAttendanceBundle.empty()
      : attendances = const <Map<String, dynamic>>[],
        payrollRows = const <Map<String, dynamic>>[];

  final List<Map<String, dynamic>> attendances;
  final List<Map<String, dynamic>> payrollRows;
}

List<AttendanceWeekEntry> _attendanceEntriesFromRows(
  List<Map<String, dynamic>> rows, {
  required String fallbackWorkerId,
}) {
  final entries = <AttendanceWeekEntry>[];
  for (final row in rows) {
    final checkIn = _parseDateTimeValue(row['check_in']);
    if (checkIn == null) continue;
    final checkOut = _parseDateTimeValue(row['check_out']);
    final workerId = _cleanText(row['employee_id']) ?? fallbackWorkerId;
    entries.add(
      AttendanceWeekEntry(
        id: _cleanText(row['id']) ??
            '$workerId-${checkIn.toUtc().toIso8601String()}',
        workerId: workerId,
        checkIn: checkIn,
        checkOut: checkOut,
        status: _cleanText(row['status']) ??
            (checkOut == null ? 'ongoing' : 'completed'),
      ),
    );
  }
  entries.sort((a, b) => a.checkIn.compareTo(b.checkIn));
  return entries;
}

AttendanceWeekWorker _attendanceWorkerFromProfile(
  Map<String, dynamic> employee,
  String workerId,
) {
  final fullName = _profileText(employee, 'fullName', fallback: 'Trabajador');
  return AttendanceWeekWorker(
    id: workerId,
    fullName: fullName,
    initials: _initials(fullName),
    jobTitle: _profileText(employee, 'jobTitle', fallback: 'Sin cargo'),
    photoUrl: _cleanText(employee['photoUrl']),
    color: const Color(0xFF0F6B63),
  );
}

DateTime _workerPortalAttendanceDisplayTime(DateTime value) {
  return _toWorkerTimeZone(value, 'America/Santiago');
}

DateTime? _parseDateTimeValue(dynamic value) {
  final text = _cleanText(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

String _payrollStatusLabel(String status) {
  return switch (status) {
    'draft' => 'Borrador',
    'confirmed' => 'Confirmada',
    'partial' => 'Parcial',
    'paid' => 'Pagada',
    'voided' => 'Anulada',
    'pending' => 'Pendiente',
    _ => status,
  };
}

Color _payrollStatusColor(String status) {
  return switch (status) {
    'paid' => const Color(0xFF15803D),
    'confirmed' => const Color(0xFF2563EB),
    'partial' => const Color(0xFFD97706),
    'voided' => const Color(0xFFB45309),
    'draft' => const Color(0xFF4B5563),
    _ => const Color(0xFF6B7280),
  };
}

String _payrollPeriodLabel(Map<String, dynamic> row) {
  final label = _cleanText(row['period_label']);
  if (label != null) return label;
  final start = _dateLabel(row['period_start']);
  final end = _dateLabel(row['period_end']);
  if (start != null && end != null) return '$start - $end';
  return 'Periodo sin fecha';
}

String _paymentMethodText(Map<String, dynamic>? row) {
  if (row == null) return 'Sin comprobante';
  return _cleanText(row['payment_method_name']) ??
      _paymentMethodLabel(row['payment_method']);
}

String _weekRangeLabel(DateTime weekStart) {
  final end = weekStart.add(const Duration(days: 6));
  return '${_formatDate(weekStart)} - ${_formatDate(end)}';
}

String _numberLabel(num? value) {
  if (value == null) return '0';
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.01) return rounded.toInt().toString();
  return value.toStringAsFixed(1);
}

class _ProfileSnapshotPanel extends StatelessWidget {
  const _ProfileSnapshotPanel({
    required this.employee,
    required this.account,
    required this.planningRoles,
  });

  final Map<String, dynamic> employee;
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> planningRoles;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _ProfileInfoRow(
        icon: Icons.badge_outlined,
        label: 'N trabajador',
        value: _profileText(employee, 'employeeNumber', fallback: 'Sin numero'),
      ),
      _ProfileInfoRow(
        icon: Icons.work_outline,
        label: 'Cargo',
        value: _profileText(employee, 'jobTitle', fallback: 'Sin cargo'),
      ),
      _ProfileInfoRow(
        icon: Icons.apartment_outlined,
        label: 'Area',
        value: _profileText(employee, 'departmentName', fallback: 'Sin area'),
      ),
      _ProfileInfoRow(
        icon: Icons.assignment_ind_outlined,
        label: 'Tipo',
        value: _employmentTypeLabel(employee),
      ),
      _ProfileInfoRow(
        icon: Icons.credit_card_outlined,
        label: 'RUT',
        value: _profileText(employee, 'rut', fallback: 'Sin RUT'),
      ),
      _ProfileInfoRow(
        icon: Icons.email_outlined,
        label: 'Email',
        value: _profileText(employee, 'email', fallback: 'Sin email'),
      ),
      _ProfileInfoRow(
        icon: Icons.phone_outlined,
        label: 'Telefono',
        value: _profileText(employee, 'phone', fallback: 'Sin telefono'),
      ),
      _ProfileInfoRow(
        icon: Icons.event_available_outlined,
        label: 'Ingreso',
        value: _dateLabel(employee['hireDate']) ?? 'Sin fecha',
      ),
      _ProfileInfoRow(
        icon: Icons.location_city_outlined,
        label: 'Ciudad',
        value: _profileText(employee, 'city', fallback: 'Sin ciudad'),
      ),
      _ProfileInfoRow(
        icon: Icons.account_circle_outlined,
        label: 'Usuario app',
        value: _profileText(account, 'username', fallback: 'Sin usuario'),
      ),
    ];

    return _PanelSurface(
      icon: Icons.person_outline,
      title: 'Mi perfil',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows,
          if (_cleanText(employee['address']) != null) ...[
            const Divider(height: 20),
            _ProfileInfoRow(
              icon: Icons.home_outlined,
              label: 'Direccion',
              value: _cleanText(employee['address'])!,
            ),
          ],
          if (_cleanText(employee['emergencyContactName']) != null ||
              _cleanText(employee['emergencyContactPhone']) != null) ...[
            const Divider(height: 20),
            _ProfileInfoRow(
              icon: Icons.health_and_safety_outlined,
              label: 'Emergencia',
              value: [
                _cleanText(employee['emergencyContactName']),
                _cleanText(employee['emergencyContactPhone']),
              ].whereType<String>().join(' - '),
            ),
          ],
          const Divider(height: 20),
          _PlanningRolesPanel(planningRoles: planningRoles),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanningRolesPanel extends StatelessWidget {
  const _PlanningRolesPanel({required this.planningRoles});

  final List<Map<String, dynamic>> planningRoles;

  @override
  Widget build(BuildContext context) {
    if (planningRoles.isEmpty) {
      return Text(
        'Sin roles de planificacion asignados',
        style: TextStyle(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: planningRoles.map((role) {
        final color = _roleColor(role['color']);
        final isDefault = role['isDefault'] == true;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            border: Border.all(color: color.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDefault ? Icons.star_rounded : Icons.circle,
                  color: color,
                  size: isDefault ? 16 : 8,
                ),
                const SizedBox(width: 6),
                Text(
                  _profileText(role, 'name', fallback: 'Rol'),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DefaultSchedulePanel extends StatelessWidget {
  const _DefaultSchedulePanel({
    required this.defaultShiftBlocks,
    required this.onEdit,
    this.onCollapse,
  });

  final List<Map<String, dynamic>> defaultShiftBlocks;
  final VoidCallback onEdit;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.date_range_outlined,
                  size: 20,
                  color: Color(0xFF0F6B63),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Horario base',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (onCollapse != null)
                  IconButton(
                    tooltip: 'Ocultar horario base',
                    onPressed: onCollapse,
                    icon: const Icon(
                      Icons.keyboard_double_arrow_right,
                      size: 20,
                    ),
                  ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Editar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (defaultShiftBlocks.isEmpty)
              Text(
                'Sin horario base configurado',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              Column(
                children: List.generate(7, (index) {
                  final weekday = index + 1;
                  final blocks = _blocksForWeekday(defaultShiftBlocks, weekday);
                  return _DefaultScheduleDayRow(
                    weekday: weekday,
                    blocks: blocks,
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }
}

class _DefaultScheduleDayRow extends StatelessWidget {
  const _DefaultScheduleDayRow({
    required this.weekday,
    required this.blocks,
  });

  final int weekday;
  final List<Map<String, dynamic>> blocks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Text(
              _weekdayNameFromNumber(weekday),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: blocks.isEmpty
                ? Text(
                    'Libre',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: blocks
                        .map(
                          (block) => _DefaultBlockPill(block: block),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DefaultBlockPill extends StatelessWidget {
  const _DefaultBlockPill({required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(block['planningRoleColor']);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Text(
          '${_timeText(block['startTime'])}-${_timeText(block['endTime'])}',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _PanelSurface extends StatelessWidget {
  const _PanelSurface({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF0F6B63)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _RequestsFuturePanel extends StatelessWidget {
  const _RequestsFuturePanel({
    required this.requestsFuture,
    this.showEmpty = false,
  });

  final Future<List<Map<String, dynamic>>> requestsFuture;
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: requestsFuture,
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const [];
        if (requests.isEmpty && !showEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _WorkerRequestsPanel(
            requests: requests,
            isLoading: snapshot.connectionState == ConnectionState.waiting,
          ),
        );
      },
    );
  }
}

class _PlanningSidePanel extends StatelessWidget {
  const _PlanningSidePanel({
    required this.collapsed,
    required this.defaultShiftBlocks,
    required this.requestsFuture,
    required this.onEditDefaultSchedule,
    required this.onToggle,
  });

  final bool collapsed;
  final List<Map<String, dynamic>> defaultShiftBlocks;
  final Future<List<Map<String, dynamic>>> requestsFuture;
  final VoidCallback onEditDefaultSchedule;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final targetWidth = collapsed ? 58.0 : 340.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: targetWidth,
      child: ClipRect(
        child: SizedBox(
          width: targetWidth,
          child: collapsed ? _collapsedRail(context) : _expandedPanel(),
        ),
      ),
    );
  }

  Widget _expandedPanel() {
    return Column(
      key: const ValueKey('planning-side-expanded'),
      children: [
        _DefaultSchedulePanel(
          defaultShiftBlocks: defaultShiftBlocks,
          onEdit: onEditDefaultSchedule,
          onCollapse: onToggle,
        ),
        const SizedBox(height: 12),
        _RequestsFuturePanel(
          requestsFuture: requestsFuture,
          showEmpty: true,
        ),
      ],
    );
  }

  Widget _collapsedRail(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('planning-side-collapsed'),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Mostrar horario base',
              onPressed: onToggle,
              icon: const Icon(Icons.keyboard_double_arrow_left, size: 20),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: 'Horario base',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onToggle,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F6B63).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.date_range_outlined,
                    color: Color(0xFF0F6B63),
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            RotatedBox(
              quarterTurns: 1,
              child: Text(
                'Horario base',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 16),
            IconButton(
              tooltip: 'Editar horario base',
              onPressed: onEditDefaultSchedule,
              icon: const Icon(Icons.edit_calendar_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ShiftsFuturePlanner extends StatelessWidget {
  const _ShiftsFuturePlanner({
    required this.weekStart,
    required this.shiftsFuture,
    required this.defaultShiftBlocks,
    required this.isDesktop,
    required this.onMoveDefaultBlock,
    required this.onRetry,
    required this.onRequestChange,
    required this.onRequestMove,
  });

  final DateTime weekStart;
  final Future<List<Map<String, dynamic>>> shiftsFuture;
  final List<Map<String, dynamic>> defaultShiftBlocks;
  final bool isDesktop;
  final void Function(Map<String, dynamic> block, int targetWeekday)
      onMoveDefaultBlock;
  final VoidCallback onRetry;
  final ValueChanged<Map<String, dynamic>> onRequestChange;
  final void Function(Map<String, dynamic> shift, DateTime targetDay)
      onRequestMove;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: shiftsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _MessagePanel(
            icon: Icons.error_outline,
            text: 'No se pudieron cargar los turnos.',
            actionLabel: 'Reintentar',
            onAction: onRetry,
          );
        }

        final shifts = snapshot.data ?? const [];
        if (shifts.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EmptyWeekMessage(
                hasDefaultBlocks: defaultShiftBlocks.isNotEmpty,
              ),
              const SizedBox(height: 12),
              _WorkerWeekPlanner(
                weekStart: weekStart,
                shifts: const [],
                defaultShiftBlocks: defaultShiftBlocks,
                isDesktop: isDesktop,
                onMoveDefaultBlock: onMoveDefaultBlock,
                onRequestChange: onRequestChange,
                onRequestMove: onRequestMove,
              ),
            ],
          );
        }

        return _WorkerWeekPlanner(
          weekStart: weekStart,
          shifts: shifts,
          defaultShiftBlocks: defaultShiftBlocks,
          isDesktop: isDesktop,
          onMoveDefaultBlock: onMoveDefaultBlock,
          onRequestChange: onRequestChange,
          onRequestMove: onRequestMove,
        );
      },
    );
  }
}

class _WorkerPlanningCalendarSection extends StatelessWidget {
  const _WorkerPlanningCalendarSection({
    required this.weekStart,
    required this.planningCalendarFuture,
    required this.employee,
    required this.storeSchedule,
    required this.isDesktop,
    required this.onRetry,
    required this.onUpdateShift,
  });

  final DateTime weekStart;
  final Future<List<Map<String, dynamic>>> planningCalendarFuture;
  final Map<String, dynamic> employee;
  final Map<String, dynamic> storeSchedule;
  final bool isDesktop;
  final VoidCallback onRetry;
  final Future<void> Function(
    String shiftId,
    DateTime startAt,
    DateTime endAt,
  ) onUpdateShift;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: planningCalendarFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: isDesktop ? 760 : 620,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _MessagePanel(
            icon: Icons.error_outline,
            text: 'No se pudieron cargar los turnos.',
            actionLabel: 'Reintentar',
            onAction: onRetry,
          );
        }

        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final currentWorkerId = _cleanText(employee['id']);
        final workerById = _calendarWorkers(rows, currentWorkerId);
        final shifts = rows
            .map((row) => _calendarShift(row, currentWorkerId))
            .whereType<PlanningCalendarShift>()
            .toList();
        final days =
            List.generate(7, (index) => weekStart.add(Duration(days: index)));

        return SizedBox(
          height: isDesktop ? 760 : 620,
          child: ShiftPlanningCalendar(
            days: days,
            shifts: shifts,
            employeeById: workerById,
            storePeriods: _storePeriodsFromSchedule(storeSchedule),
            displayTimeZone: PlanningCalendarTimeZone.chile,
            editableWorkerIds: currentWorkerId == null
                ? const {'__no_worker__'}
                : {currentWorkerId},
            showWorkerSidebar: false,
            allowCreateShift: false,
            allowCreateShiftFromWorker: false,
            allowAdministrativeActions: false,
            onCreateShift: (_) {},
            onCreateShiftFromWorker: (_, __, ___, ____) async {},
            onEditShift: (shift) => _editShift(context, shift, rows),
            onMoveShift: (shift, day, startMinutes) async {
              if (!_isOwnShift(shift, currentWorkerId)) return;
              final duration = shift.endAt.difference(shift.startAt);
              final startAt = _zonedDateTime(
                'America/Santiago',
                day.year,
                day.month,
                day.day,
                startMinutes ~/ 60,
                startMinutes % 60,
              );
              await onUpdateShift(shift.id, startAt, startAt.add(duration));
            },
            onResizeShift: (
              shift, {
              required bool resizeStart,
              required int deltaMinutes,
            }) async {
              if (!_isOwnShift(shift, currentWorkerId) || deltaMinutes == 0) {
                return;
              }
              final startAt = resizeStart
                  ? shift.startAt.add(Duration(minutes: deltaMinutes))
                  : shift.startAt;
              final endAt = resizeStart
                  ? shift.endAt
                  : shift.endAt.add(Duration(minutes: deltaMinutes));
              await onUpdateShift(shift.id, startAt, endAt);
            },
            onPublishShift: (_) {},
            onCancelShift: (_) {},
            onDeleteShift: (_) {},
          ),
        );
      },
    );
  }

  Map<String, PlanningCalendarWorker> _calendarWorkers(
    List<Map<String, dynamic>> rows,
    String? currentWorkerId,
  ) {
    final workers = <String, PlanningCalendarWorker>{};
    if (currentWorkerId != null) {
      final name = _cleanText(employee['fullName']) ?? 'Trabajador';
      workers[currentWorkerId] = PlanningCalendarWorker(
        id: currentWorkerId,
        fullName: name,
        jobTitle: _cleanText(employee['jobTitle']) ?? '',
        initials: _initials(name),
        photoUrl: _cleanText(employee['photoUrl']),
      );
    }

    for (final row in rows) {
      final isMine = row['is_my_shift'] == true;
      final workerId =
          _cleanText(row['employee_id']) ?? (isMine ? currentWorkerId : null);
      if (workerId == null) continue;
      final name = _cleanText(row['employee_full_name']) ??
          _cleanText(row['employee_name']) ??
          _cleanText(row['worker_name']) ??
          (isMine ? _cleanText(employee['fullName']) : null) ??
          'Trabajador';
      workers[workerId] = PlanningCalendarWorker(
        id: workerId,
        fullName: name,
        jobTitle: _cleanText(row['employee_job_title']) ??
            _cleanText(row['job_title']) ??
            (isMine ? _cleanText(employee['jobTitle']) : null) ??
            '',
        initials: _initials(name),
        photoUrl: _cleanText(row['employee_photo_url']) ??
            (isMine ? _cleanText(employee['photoUrl']) : null),
      );
    }

    return workers;
  }

  PlanningCalendarShift? _calendarShift(
    Map<String, dynamic> row,
    String? currentWorkerId,
  ) {
    final id = _cleanText(row['id']);
    final startAt = _parseShiftDateTime(row['start_at'], _shiftTimezone(row));
    final endAt = _parseShiftDateTime(row['end_at'], _shiftTimezone(row));
    if (id == null || startAt == null || endAt == null) return null;
    final isMine = row['is_my_shift'] == true;
    return PlanningCalendarShift(
      id: id,
      employeeId:
          _cleanText(row['employee_id']) ?? (isMine ? currentWorkerId : null),
      title: _cleanText(row['title']),
      startAt: startAt,
      endAt: endAt,
      status: _cleanText(row['status']) ?? 'published',
      roleId: _cleanText(row['planning_role_id']),
      roleName:
          _cleanText(row['planning_role_name']) ?? _cleanText(row['role_name']),
      roleColor: _cleanText(row['planning_role_color']) ??
          _cleanText(row['role_color']),
      storeHoursValidated: row['store_hours_validated'] != false,
      outsideStoreHoursReason: _cleanText(row['outside_store_hours_reason']),
    );
  }

  Future<void> _editShift(
    BuildContext context,
    PlanningCalendarShift shift,
    List<Map<String, dynamic>> rows,
  ) async {
    final draft = await showDialog<_ShiftChangeDraft>(
      context: context,
      builder: (dialogContext) => _ShiftChangeDialog(
        shift: _rowForShift(shift, rows),
        title: 'Editar turno',
        submitLabel: 'Guardar',
        showNote: false,
      ),
    );
    if (draft == null) return;
    final startAt = _zonedDateTime(
      'America/Santiago',
      draft.startAt.year,
      draft.startAt.month,
      draft.startAt.day,
      draft.startAt.hour,
      draft.startAt.minute,
    );
    final endAt = _zonedDateTime(
      'America/Santiago',
      draft.endAt.year,
      draft.endAt.month,
      draft.endAt.day,
      draft.endAt.hour,
      draft.endAt.minute,
    );
    await onUpdateShift(shift.id, startAt, endAt);
  }

  Map<String, dynamic> _rowForShift(
    PlanningCalendarShift shift,
    List<Map<String, dynamic>> rows,
  ) {
    for (final row in rows) {
      if (_cleanText(row['id']) == shift.id) return row;
    }
    return {
      'id': shift.id,
      'start_at': shift.startAt.toIso8601String(),
      'end_at': shift.endAt.toIso8601String(),
      'timezone': 'America/Santiago',
    };
  }

  bool _isOwnShift(PlanningCalendarShift shift, String? currentWorkerId) {
    return currentWorkerId != null && shift.employeeId == currentWorkerId;
  }
}

class _WorkerWeekPlanner extends StatelessWidget {
  const _WorkerWeekPlanner({
    required this.weekStart,
    required this.shifts,
    required this.defaultShiftBlocks,
    required this.isDesktop,
    required this.onMoveDefaultBlock,
    required this.onRequestChange,
    required this.onRequestMove,
  });

  final DateTime weekStart;
  final List<Map<String, dynamic>> shifts;
  final List<Map<String, dynamic>> defaultShiftBlocks;
  final bool isDesktop;
  final void Function(Map<String, dynamic> block, int targetWeekday)
      onMoveDefaultBlock;
  final ValueChanged<Map<String, dynamic>> onRequestChange;
  final void Function(Map<String, dynamic> shift, DateTime targetDay)
      onRequestMove;

  @override
  Widget build(BuildContext context) {
    final days =
        List.generate(7, (index) => weekStart.add(Duration(days: index)));

    if (isDesktop) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final boardWidth =
              constraints.maxWidth < 1120 ? 1120.0 : constraints.maxWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: boardWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: days
                    .map(
                      (day) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _WorkerDaySection(
                            day: day,
                            shifts: shifts
                                .where(
                                  (shift) => _shiftBelongsToDay(shift, day),
                                )
                                .toList(),
                            baseBlocks: _blocksForWeekday(
                              defaultShiftBlocks,
                              day.weekday,
                            ),
                            isDesktop: true,
                            onMoveDefaultBlock: onMoveDefaultBlock,
                            onRequestChange: onRequestChange,
                            onRequestMove: onRequestMove,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: days
          .map(
            (day) => _WorkerDaySection(
              day: day,
              shifts: shifts
                  .where((shift) => _shiftBelongsToDay(shift, day))
                  .toList(),
              baseBlocks: _blocksForWeekday(defaultShiftBlocks, day.weekday),
              isDesktop: false,
              onMoveDefaultBlock: onMoveDefaultBlock,
              onRequestChange: onRequestChange,
              onRequestMove: onRequestMove,
            ),
          )
          .toList(),
    );
  }
}

class _WorkerDaySection extends StatelessWidget {
  const _WorkerDaySection({
    required this.day,
    required this.shifts,
    required this.baseBlocks,
    required this.isDesktop,
    required this.onMoveDefaultBlock,
    required this.onRequestChange,
    required this.onRequestMove,
  });

  final DateTime day;
  final List<Map<String, dynamic>> shifts;
  final List<Map<String, dynamic>> baseBlocks;
  final bool isDesktop;
  final void Function(Map<String, dynamic> block, int targetWeekday)
      onMoveDefaultBlock;
  final ValueChanged<Map<String, dynamic>> onRequestChange;
  final void Function(Map<String, dynamic> shift, DateTime targetDay)
      onRequestMove;

  @override
  Widget build(BuildContext context) {
    final hasShifts = shifts.isNotEmpty;
    final hasBaseBlocks = baseBlocks.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DragTarget<_ScheduleDragPayload>(
        onWillAcceptWithDetails: (details) {
          final payload = details.data;
          if (payload.isDefaultBlock) {
            return _number(payload.data['dayOfWeek'])?.toInt() != day.weekday;
          }

          final status = payload.data['status']?.toString();
          if (status == 'cancelled') return false;

          final start = _parseShiftDateTime(
            payload.data['start_at'],
            _shiftTimezone(payload.data),
          );
          return start != null && !_sameDate(start, day);
        },
        onAcceptWithDetails: (details) {
          final payload = details.data;
          if (payload.isDefaultBlock) {
            onMoveDefaultBlock(payload.data, day.weekday);
          } else {
            onRequestMove(payload.data, day);
          }
        },
        builder: (context, candidateData, rejectedData) {
          final isTargeted = candidateData.isNotEmpty;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: isDesktop
                ? const BoxConstraints(minHeight: 430)
                : const BoxConstraints(),
            decoration: BoxDecoration(
              color: isTargeted
                  ? Colors.teal.withValues(alpha: 0.08)
                  : Colors.white,
              border: Border.all(
                color: isTargeted ? Colors.teal.shade600 : Colors.grey.shade200,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _sameDate(day, DateTime.now())
                              ? const Color(0xFF0F6B63)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          day.day.toString().padLeft(2, '0'),
                          style: TextStyle(
                            color: _sameDate(day, DateTime.now())
                                ? Colors.white
                                : Colors.grey.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _weekdayLabel(day),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _DayCountBadge(
                        count: hasShifts ? shifts.length : baseBlocks.length,
                        isBase: !hasShifts && hasBaseBlocks,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (hasShifts)
                    ...shifts.map(
                      (shift) => _DraggableShiftTile(
                        shift: shift,
                        onRequestChange: () => onRequestChange(shift),
                      ),
                    )
                  else if (hasBaseBlocks)
                    ...baseBlocks.map(
                      (block) => _DraggableBaseShiftTile(block: block),
                    )
                  else
                    const _FreeDayPlaceholder(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayCountBadge extends StatelessWidget {
  const _DayCountBadge({required this.count, required this.isBase});

  final int count;
  final bool isBase;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isBase
            ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
            : const Color(0xFF0F6B63).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          isBase ? 'Base $count' : '$count',
          style: TextStyle(
            color: isBase ? const Color(0xFFB45309) : const Color(0xFF0F6B63),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _BaseShiftTile extends StatelessWidget {
  const _BaseShiftTile({required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final roleName = _cleanText(block['planningRoleName']) ?? 'Horario base';
    final color = _roleColor(block['planningRoleColor']);
    final valid = block['storeHoursValidated'] != false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(
          color: valid ? color.withValues(alpha: 0.28) : Colors.orange.shade300,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_timeText(block['startTime'])} - ${_timeText(block['endTime'])}',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            roleName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!valid) ...[
            const SizedBox(height: 6),
            _OutsideStoreHoursNotice(
              reason: _cleanText(block['outsideStoreHoursReason']),
            ),
          ],
        ],
      ),
    );
  }
}

class _FreeDayPlaceholder extends StatelessWidget {
  const _FreeDayPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.weekend_outlined, color: Colors.grey.shade500, size: 18),
            const SizedBox(width: 7),
            Text(
              'Libre',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleDragPayload {
  const _ScheduleDragPayload.shift(this.data) : isDefaultBlock = false;

  const _ScheduleDragPayload.defaultBlock(this.data) : isDefaultBlock = true;

  final Map<String, dynamic> data;
  final bool isDefaultBlock;
}

class _DraggableBaseShiftTile extends StatelessWidget {
  const _DraggableBaseShiftTile({required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final tile = _BaseShiftTile(block: block);
    return LongPressDraggable<_ScheduleDragPayload>(
      data: _ScheduleDragPayload.defaultBlock(block),
      feedback: _BaseShiftDragFeedback(block: block),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }
}

class _BaseShiftDragFeedback extends StatelessWidget {
  const _BaseShiftDragFeedback({required this.block});

  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFF0F6B63)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox(
          width: 210,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${_timeText(block['startTime'])} - ${_timeText(block['endTime'])}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableShiftTile extends StatelessWidget {
  const _DraggableShiftTile({
    required this.shift,
    required this.onRequestChange,
  });

  final Map<String, dynamic> shift;
  final VoidCallback onRequestChange;

  @override
  Widget build(BuildContext context) {
    final status = shift['status']?.toString() ?? 'draft';
    final canMove = status != 'cancelled';
    final tile = _ShiftTile(shift, onRequestChange: onRequestChange);

    if (!canMove) return tile;

    return LongPressDraggable<_ScheduleDragPayload>(
      data: _ScheduleDragPayload.shift(shift),
      feedback: _ShiftDragFeedback(shift: shift),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }
}

class _ShiftDragFeedback extends StatelessWidget {
  const _ShiftDragFeedback({required this.shift});

  final Map<String, dynamic> shift;

  @override
  Widget build(BuildContext context) {
    final timezone = _shiftTimezone(shift);
    final start = _parseShiftDateTime(shift['start_at'], timezone);
    final end = _parseShiftDateTime(shift['end_at'], timezone);

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.teal.shade600),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox(
          width: 220,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              start == null || end == null
                  ? 'Turno'
                  : '${_formatTime(start)} - ${_formatTime(end)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreHoursSummary extends StatelessWidget {
  const _StoreHoursSummary({required this.schedule});

  final Map<String, dynamic> schedule;

  @override
  Widget build(BuildContext context) {
    final label = _storeHoursLabel(schedule);
    final hasSchedule = label != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.storefront_outlined, color: Colors.grey.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Horario tienda',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasSchedule ? label : 'Horario de tienda no configurado',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.weekStart,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime weekStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Semana anterior',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'Semana',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDate(weekStart)} - ${_formatDate(weekEnd)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Semana siguiente',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerRequestsPanel extends StatelessWidget {
  const _WorkerRequestsPanel({
    required this.requests,
    required this.isLoading,
  });

  final List<Map<String, dynamic>> requests;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final visible = requests.take(3).toList();

    return _PanelSurface(
      icon: Icons.pending_actions_outlined,
      title: 'Solicitudes',
      child: isLoading
          ? const LinearProgressIndicator(minHeight: 3)
          : visible.isEmpty
              ? Text(
                  'Sin solicitudes pendientes',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Column(
                  children: visible
                      .map(
                        (request) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _WorkerRequestRow(request: request),
                        ),
                      )
                      .toList(),
                ),
    );
  }
}

class _EmptyWeekMessage extends StatelessWidget {
  const _EmptyWeekMessage({required this.hasDefaultBlocks});

  final bool hasDefaultBlocks;

  @override
  Widget build(BuildContext context) {
    return _PanelSurface(
      icon: Icons.info_outline,
      title: hasDefaultBlocks ? 'Pendiente de publicar' : 'Sin horario base',
      child: Text(
        hasDefaultBlocks
            ? 'No hay turnos publicados para esta semana. Se muestran tus bloques base como referencia.'
            : 'RR.HH. todavia no configuro turnos ni horario base para esta semana.',
        style: TextStyle(
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

class _WorkerRequestRow extends StatelessWidget {
  const _WorkerRequestRow({required this.request});

  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final status = request['status']?.toString() ?? 'pending';
    final start =
        DateTime.tryParse(request['requested_start_at']?.toString() ?? '')
            ?.toLocal();
    final end = DateTime.tryParse(request['requested_end_at']?.toString() ?? '')
        ?.toLocal();
    final MaterialColor statusColor = switch (status) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      _ => Colors.orange,
    };
    final label = start == null || end == null
        ? 'Cambio solicitado'
        : '${_formatDate(start)} ${_formatTime(start)}-${_formatTime(end)}';

    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: statusColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _requestStatusLabel(status),
          style: TextStyle(
            color: statusColor.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ShiftTile extends StatelessWidget {
  const _ShiftTile(this.shift, {required this.onRequestChange});

  final Map<String, dynamic> shift;
  final VoidCallback onRequestChange;

  @override
  Widget build(BuildContext context) {
    final timezone = _shiftTimezone(shift);
    final start = _parseShiftDateTime(shift['start_at'], timezone);
    final end = _parseShiftDateTime(shift['end_at'], timezone);
    final role = shift['planning_role_name']?.toString();
    final status = shift['status']?.toString() ?? 'draft';
    final variance = _number(shift['variance_minutes']);
    final actualStart = _parseShiftDateTime(shift['first_check_in'], timezone);
    final actualEnd = _parseShiftDateTime(shift['last_check_out'], timezone);
    final storeHoursValidated = shift['store_hours_validated'] == true;
    final outsideReason = shift['outside_store_hours_reason']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: Color(0xFF0F6B63),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            start == null || end == null
                                ? 'Turno'
                                : '${_formatTime(start)} - ${_formatTime(end)}',
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Solicitar cambio',
                          onPressed:
                              status == 'cancelled' ? null : onRequestChange,
                          icon: const Icon(Icons.edit_calendar_outlined),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (role != null && role.isNotEmpty)
                          _TinyTag(
                            text: role,
                            color: const Color(0xFF2563EB),
                          ),
                        _TinyTag(
                          text: _statusLabel(status),
                          color: _statusColor(status),
                        ),
                        if (variance != null)
                          _TinyTag(
                            text: _varianceLabel(variance),
                            color: variance == 0
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFF59E0B),
                          ),
                      ],
                    ),
                    if (actualStart != null || actualEnd != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.fingerprint_outlined,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Marcaje ${actualStart == null ? '--:--' : _formatTime(actualStart)} - ${actualEnd == null ? '--:--' : _formatTime(actualEnd)}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (!storeHoursValidated) ...[
                      const SizedBox(height: 8),
                      _OutsideStoreHoursNotice(reason: outsideReason),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyTag extends StatelessWidget {
  const _TinyTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _OutsideStoreHoursNotice extends StatelessWidget {
  const _OutsideStoreHoursNotice({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              size: 15,
              color: Colors.orange.shade800,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                reason?.isNotEmpty == true
                    ? reason!
                    : 'Fuera del horario tienda',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontSize: 12,
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

class _ShiftChangeDialog extends StatefulWidget {
  const _ShiftChangeDialog({
    required this.shift,
    this.title = 'Solicitar cambio',
    this.submitLabel = 'Enviar',
    this.showNote = true,
  });

  final Map<String, dynamic> shift;
  final String title;
  final String submitLabel;
  final bool showNote;

  @override
  State<_ShiftChangeDialog> createState() => _ShiftChangeDialogState();
}

class _ShiftChangeDialogState extends State<_ShiftChangeDialog> {
  final _noteController = TextEditingController();
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String? _error;

  @override
  void initState() {
    super.initState();
    final timezone = _shiftTimezone(widget.shift);
    final start = _parseShiftDateTime(widget.shift['start_at'], timezone) ??
        DateTime.now();
    final end = _parseShiftDateTime(widget.shift['end_at'], timezone) ??
        start.add(const Duration(hours: 4));
    _date = DateTime(start.year, start.month, start.day);
    _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
    _endTime = TimeOfDay(hour: end.hour, minute: end.minute);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  DateTime get _startAt => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _startTime.hour,
        _startTime.minute,
      );

  DateTime get _endAt => DateTime(
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
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
      _error = null;
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
      _error = null;
    });
  }

  void _submit() {
    if (!_endAt.isAfter(_startAt)) {
      setState(() => _error = 'La salida debe ser posterior.');
      return;
    }

    Navigator.of(context).pop(
      _ShiftChangeDraft(
        startAt: _startAt,
        endAt: _endAt,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                    onPressed: () => _pickTime(start: true),
                    icon: const Icon(Icons.login_outlined),
                    label: Text(_formatTime(_startAt)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(start: false),
                    icon: const Icon(Icons.logout_outlined),
                    label: Text(_formatTime(_endAt)),
                  ),
                ),
              ],
            ),
            if (widget.showNote) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Nota opcional',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon:
              Icon(widget.showNote ? Icons.send_outlined : Icons.save_outlined),
          label: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

class _ShiftChangeDraft {
  const _ShiftChangeDraft({
    required this.startAt,
    required this.endAt,
    this.note,
  });

  final DateTime startAt;
  final DateTime endAt;
  final String? note;
}

class _DefaultScheduleEditorDialog extends StatefulWidget {
  const _DefaultScheduleEditorDialog({
    required this.defaultShiftBlocks,
    required this.planningRoles,
  });

  final List<Map<String, dynamic>> defaultShiftBlocks;
  final List<Map<String, dynamic>> planningRoles;

  @override
  State<_DefaultScheduleEditorDialog> createState() =>
      _DefaultScheduleEditorDialogState();
}

class _DefaultScheduleEditorDialogState
    extends State<_DefaultScheduleEditorDialog> {
  late List<_DefaultShiftDraft> _drafts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _drafts = widget.defaultShiftBlocks
        .map(_DefaultShiftDraft.fromBlock)
        .where((draft) => draft != null)
        .cast<_DefaultShiftDraft>()
        .toList();
  }

  void _addBlock(int weekday) {
    final dayDrafts = _drafts
        .where((draft) => draft.dayOfWeek == weekday)
        .toList()
      ..sort((a, b) => _minutesOfDay(a.startTime) - _minutesOfDay(b.startTime));
    final lastEnd = dayDrafts.isEmpty ? null : dayDrafts.last.endTime;
    final start = lastEnd ?? const TimeOfDay(hour: 10, minute: 0);
    final end = _addHours(start, dayDrafts.isEmpty ? 8 : 4);

    setState(() {
      _drafts.add(
        _DefaultShiftDraft(
          dayOfWeek: weekday,
          startTime: start,
          endTime: end,
          planningRoleId: _defaultPlanningRoleId(),
        ),
      );
      _error = null;
    });
  }

  String _defaultPlanningRoleId() {
    for (final role in widget.planningRoles) {
      if (role['isDefault'] == true) return _cleanText(role['id']) ?? '';
    }
    return '';
  }

  Future<void> _pickTime(_DefaultShiftDraft draft,
      {required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? draft.startTime : draft.endTime,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        draft.startTime = picked;
      } else {
        draft.endTime = picked;
      }
      _error = null;
    });
  }

  void _removeBlock(_DefaultShiftDraft draft) {
    setState(() {
      _drafts.remove(draft);
      _error = null;
    });
  }

  void _submit() {
    for (final draft in _drafts) {
      if (_minutesOfDay(draft.startTime) >= _minutesOfDay(draft.endTime)) {
        setState(() => _error = 'Cada bloque debe tener salida posterior.');
        return;
      }
    }

    for (var weekday = 1; weekday <= 7; weekday++) {
      final dayDrafts =
          _drafts.where((draft) => draft.dayOfWeek == weekday).toList()
            ..sort(
              (a, b) => _minutesOfDay(a.startTime) - _minutesOfDay(b.startTime),
            );
      for (var index = 1; index < dayDrafts.length; index++) {
        if (_minutesOfDay(dayDrafts[index].startTime) <
            _minutesOfDay(dayDrafts[index - 1].endTime)) {
          setState(
            () => _error =
                'Hay bloques superpuestos en ${_weekdayNameFromNumber(weekday)}.',
          );
          return;
        }
      }
    }

    Navigator.of(context).pop(
      _drafts.map((draft) => draft.toPayload()).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar horario base'),
      content: SizedBox(
        width: 720,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  _DefaultScheduleEditorDay(
                    weekday: weekday,
                    drafts: _drafts
                        .where((draft) => draft.dayOfWeek == weekday)
                        .toList(),
                    planningRoles: widget.planningRoles,
                    onAdd: () => _addBlock(weekday),
                    onPickTime: _pickTime,
                    onRemove: _removeBlock,
                    onRoleChanged: (draft, roleId) {
                      setState(() {
                        draft.planningRoleId = roleId ?? '';
                        _error = null;
                      });
                    },
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
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
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DefaultScheduleEditorDay extends StatelessWidget {
  const _DefaultScheduleEditorDay({
    required this.weekday,
    required this.drafts,
    required this.planningRoles,
    required this.onAdd,
    required this.onPickTime,
    required this.onRemove,
    required this.onRoleChanged,
  });

  final int weekday;
  final List<_DefaultShiftDraft> drafts;
  final List<Map<String, dynamic>> planningRoles;
  final VoidCallback onAdd;
  final Future<void> Function(_DefaultShiftDraft draft, {required bool start})
      onPickTime;
  final ValueChanged<_DefaultShiftDraft> onRemove;
  final void Function(_DefaultShiftDraft draft, String? roleId) onRoleChanged;

  @override
  Widget build(BuildContext context) {
    drafts.sort(
      (a, b) => _minutesOfDay(a.startTime) - _minutesOfDay(b.startTime),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _weekdayNameFromNumber(weekday),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar'),
              ),
            ],
          ),
          if (drafts.isEmpty)
            Text(
              'Libre',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...drafts.map(
              (draft) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => onPickTime(draft, start: true),
                      icon: const Icon(Icons.login_outlined, size: 18),
                      label: Text(_timeOfDayText(draft.startTime)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onPickTime(draft, start: false),
                      icon: const Icon(Icons.logout_outlined, size: 18),
                      label: Text(_timeOfDayText(draft.endTime)),
                    ),
                    if (planningRoles.isNotEmpty)
                      SizedBox(
                        width: 210,
                        child: DropdownButtonFormField<String>(
                          initialValue: draft.planningRoleId,
                          decoration: const InputDecoration(
                            labelText: 'Rol',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Sin rol'),
                            ),
                            ...planningRoles.map(
                              (role) => DropdownMenuItem(
                                value: _cleanText(role['id']) ?? '',
                                child: Text(
                                  _profileText(
                                    role,
                                    'name',
                                    fallback: 'Rol',
                                  ),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) => onRoleChanged(draft, value),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Eliminar bloque',
                      onPressed: () => onRemove(draft),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DefaultShiftDraft {
  _DefaultShiftDraft({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.planningRoleId,
  });

  int dayOfWeek;
  TimeOfDay startTime;
  TimeOfDay endTime;
  String planningRoleId;

  static _DefaultShiftDraft? fromBlock(Map<String, dynamic> block) {
    final day = _number(block['dayOfWeek'])?.toInt();
    final start = _timeOfDayFromValue(block['startTime']);
    final end = _timeOfDayFromValue(block['endTime']);
    if (day == null || start == null || end == null) return null;
    return _DefaultShiftDraft(
      dayOfWeek: day,
      startTime: start,
      endTime: end,
      planningRoleId: _cleanText(block['planningRoleId']) ?? '',
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      'dayOfWeek': dayOfWeek,
      'startTime': _timeOfDayText(startTime),
      'endTime': _timeOfDayText(endTime),
      'timezone': 'America/Santiago',
      if (planningRoleId.isNotEmpty) 'planningRoleId': planningRoleId,
    };
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.grey.shade700),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const String _workerChileTimeZone = 'America/Santiago';

DateTime _workerWeekStartAtChile(DateTime weekStart) {
  return tz.TZDateTime(
    _workerTimeZoneLocation(_workerChileTimeZone),
    weekStart.year,
    weekStart.month,
    weekStart.day,
  );
}

DateTime _workerWeekEndAtChile(DateTime weekStart) {
  return _workerWeekStartAtChile(weekStart).add(const Duration(days: 7));
}

String _workerChileDateString(DateTime date) {
  return DateFormat(
    'yyyy-MM-dd',
  ).format(_toWorkerTimeZone(date, _workerChileTimeZone));
}

List<Map<String, dynamic>> _mergeAttendanceRows(
  List<Map<String, dynamic>> rawRows,
  List<Map<String, dynamic>> fallbackRows,
) {
  final merged = <Map<String, dynamic>>[];
  final seenCheckIns = <String>{};

  void addRow(Map<String, dynamic> row) {
    final checkIn = _cleanText(row['check_in']);
    if (checkIn == null || !seenCheckIns.add(checkIn)) return;
    merged.add(row);
  }

  for (final row in rawRows) {
    addRow(row);
  }
  for (final row in fallbackRows) {
    addRow(row);
  }

  merged.sort((a, b) {
    final left = _cleanText(a['check_in']) ?? '';
    final right = _cleanText(b['check_in']) ?? '';
    return left.compareTo(right);
  });
  return merged;
}

List<Map<String, dynamic>> _mapsFromList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

bool _workerTimeZonesInitialized = false;
final Map<String, tz.Location> _workerTimeZoneLocations = {};

String _shiftTimezone(Map<String, dynamic> shift) {
  return _cleanText(shift['timezone']) ?? 'America/Santiago';
}

DateTime? _parseShiftDateTime(dynamic value, String timezone) {
  final text = _cleanText(value);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return _toWorkerTimeZone(parsed, timezone);
}

DateTime _zonedDateTime(
  String timezone,
  int year,
  int month,
  int day,
  int hour,
  int minute,
) {
  try {
    final location = _workerTimeZoneLocation(timezone);
    return tz.TZDateTime(location, year, month, day, hour, minute);
  } catch (_) {
    return DateTime(year, month, day, hour, minute);
  }
}

DateTime _toWorkerTimeZone(DateTime value, String timezone) {
  try {
    final location = _workerTimeZoneLocation(timezone);
    return tz.TZDateTime.from(value.toUtc(), location);
  } catch (_) {
    return value.toLocal();
  }
}

tz.Location _workerTimeZoneLocation(String timezone) {
  if (!_workerTimeZonesInitialized) {
    tzdata.initializeTimeZones();
    _workerTimeZonesInitialized = true;
  }
  return _workerTimeZoneLocations.putIfAbsent(
    timezone,
    () => tz.getLocation(timezone),
  );
}

String? _cleanText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return text;
}

String _profileText(
  Map<String, dynamic> source,
  String key, {
  required String fallback,
}) {
  return _cleanText(source[key]) ?? fallback;
}

String _employmentTypeLabel(Map<String, dynamic> employee) {
  return switch (_cleanText(employee['employmentType'])) {
    'full_time' => 'Jornada completa',
    'part_time' => 'Media jornada',
    'contractor' => 'Contrato externo',
    'intern' => 'Practica',
    _ => 'Sin tipo',
  };
}

String _employeeStatusLabel(dynamic status) {
  return switch (_cleanText(status)) {
    'active' => 'Activo',
    'inactive' => 'Inactivo',
    'on_leave' => 'Con licencia',
    'terminated' => 'Terminado',
    _ => 'Sin estado',
  };
}

Color _roleColor(dynamic rawColor) {
  final text = _cleanText(rawColor);
  if (text == null) return const Color(0xFF0F6B63);
  final normalized = text.startsWith('#') ? text.substring(1) : text;
  if (normalized.length != 6) return const Color(0xFF0F6B63);
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return const Color(0xFF0F6B63);
  return Color(0xFF000000 | parsed);
}

Color _statusColor(String status) {
  return switch (status) {
    'published' => const Color(0xFF2563EB),
    'completed' => const Color(0xFF16A34A),
    'cancelled' => const Color(0xFFDC2626),
    _ => const Color(0xFFF59E0B),
  };
}

num _sumShiftMinutes(List<Map<String, dynamic>> shifts, String key) {
  num total = 0;
  for (final shift in shifts) {
    total += _number(shift[key]) ?? 0;
  }
  return total;
}

String _minutesAsHours(num minutes) {
  final rounded = minutes.round();
  if (rounded <= 0) return '0 h';
  final hours = rounded ~/ 60;
  final remainder = rounded % 60;
  if (remainder == 0) return '$hours h';
  if (hours == 0) return '$remainder min';
  return '$hours h $remainder min';
}

String _moneyLabel(num amount) {
  return NumberFormat.currency(
    locale: 'es_CL',
    symbol: r'$',
    decimalDigits: 0,
  ).format(amount);
}

String _paymentMethodLabel(dynamic value) {
  return switch (_cleanText(value)) {
    'cash' => 'Efectivo',
    'check' => 'Cheque',
    'transfer' => 'Transferencia',
    String text => text,
    _ => 'Método no configurado',
  };
}

List<Map<String, dynamic>> _blocksForWeekday(
  List<Map<String, dynamic>> blocks,
  int weekday,
) {
  final filtered = blocks.where((block) {
    final day = _number(block['dayOfWeek'])?.toInt();
    return day == weekday;
  }).toList();
  filtered.sort(
    (a, b) => _timeText(a['startTime']).compareTo(_timeText(b['startTime'])),
  );
  return filtered;
}

String _weekdayNameFromNumber(int weekday) {
  const labels = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];
  if (weekday < 1 || weekday > 7) return 'Dia';
  return labels[weekday - 1];
}

String _timeText(dynamic value) {
  final text = _cleanText(value);
  if (text == null) return '--:--';
  final pieces = text.split(':');
  if (pieces.length >= 2) {
    final hours = int.tryParse(pieces[0]);
    final minutes = int.tryParse(pieces[1]);
    if (hours != null && minutes != null) return _clockLabel(hours, minutes);
  }
  return text;
}

String? _dateLabel(dynamic value) {
  final text = _cleanText(value);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  return '${parsed.day.toString().padLeft(2, '0')}/'
      '${parsed.month.toString().padLeft(2, '0')}/'
      '${parsed.year}';
}

Map<String, dynamic> _defaultBlockPayload(Map<String, dynamic> block) {
  final roleId = _cleanText(block['planningRoleId']);
  return {
    'dayOfWeek': _number(block['dayOfWeek'])?.toInt() ?? 1,
    'startTime': _timeText(block['startTime']),
    'endTime': _timeText(block['endTime']),
    'timezone': _cleanText(block['timezone']) ?? 'America/Santiago',
    if (roleId != null) 'planningRoleId': roleId,
  };
}

int _minutesOfDay(TimeOfDay value) => value.hour * 60 + value.minute;

TimeOfDay _addHours(TimeOfDay value, int hours) {
  final minutes = (_minutesOfDay(value) + hours * 60).clamp(0, 23 * 60 + 59);
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

String _timeOfDayText(TimeOfDay value) => _clockLabel(value.hour, value.minute);

TimeOfDay? _timeOfDayFromValue(dynamic value) {
  final text = _timeText(value);
  if (text == '--:--') return null;
  final pieces = text.split(':');
  if (pieces.length < 2) return null;
  final hour = int.tryParse(pieces[0]);
  final minute = int.tryParse(pieces[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _weekdayLabel(DateTime date) {
  const labels = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];
  return labels[date.weekday - 1];
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

String _varianceLabel(num minutes) {
  if (minutes == 0) return 'Exacto';
  final abs = minutes.abs().round();
  return minutes > 0 ? '+$abs min' : '-$abs min';
}

String _requestStatusLabel(String status) {
  switch (status) {
    case 'approved':
      return 'Aprobada';
    case 'rejected':
      return 'Rechazada';
    case 'cancelled':
      return 'Cancelada';
    default:
      return 'Pendiente';
  }
}

num? _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '');
}

bool _shiftBelongsToDay(Map<String, dynamic> shift, DateTime day) {
  final start = _parseShiftDateTime(shift['start_at'], _shiftTimezone(shift));
  return start != null && _sameDate(start, day);
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'T';
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$second'.toUpperCase();
}

String? _storeHoursLabel(Map<String, dynamic> schedule) {
  final raw =
      (schedule['businessHoursJson']?.toString().trim().isNotEmpty ?? false)
          ? schedule['businessHoursJson'].toString()
          : schedule['googleBusinessHoursJson']?.toString();
  if (raw == null || raw.trim().isEmpty) return null;

  try {
    final decoded = jsonDecode(raw);
    final root = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
    final data = root['opening_hours'] is Map
        ? Map<String, dynamic>.from(root['opening_hours'] as Map)
        : root;
    final periods = data['periods'] is List
        ? List<dynamic>.from(data['periods'] as List)
        : const <dynamic>[];

    final labels = <String>[];
    for (final rawPeriod in periods) {
      if (rawPeriod is! Map) continue;
      final period = Map<String, dynamic>.from(rawPeriod);
      final label = _businessPeriodLabel(period);
      if (label != null) labels.add(label);
    }

    if (labels.isEmpty) return null;
    final visible = labels.take(4).join('; ');
    final remaining = labels.length - 4;
    return remaining > 0 ? '$visible; +$remaining dias' : visible;
  } catch (_) {
    return null;
  }
}

String? _businessPeriodLabel(Map<String, dynamic> period) {
  final open = _mapValue(period['open']);
  final close = _mapValue(period['close']);
  final openDay = period.containsKey('openDay')
      ? _businessDayLabel(period['openDay'])
      : _placesDayLabel(open?['day']);
  final openTime = period.containsKey('openTime')
      ? _businessTimeLabel(period['openTime'])
      : _placesTimeLabel(open?['time']);
  final closeTime = period.containsKey('closeTime')
      ? _businessTimeLabel(period['closeTime'])
      : _placesTimeLabel(close?['time']);

  if (openDay == null || openTime == null || closeTime == null) return null;
  return '$openDay $openTime-$closeTime';
}

Map<String, dynamic>? _mapValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _businessDayLabel(dynamic rawDay) {
  final day = rawDay?.toString().toUpperCase();
  return switch (day) {
    'MONDAY' => 'Lun',
    'TUESDAY' => 'Mar',
    'WEDNESDAY' => 'Mie',
    'THURSDAY' => 'Jue',
    'FRIDAY' => 'Vie',
    'SATURDAY' => 'Sab',
    'SUNDAY' => 'Dom',
    _ => null,
  };
}

String? _placesDayLabel(dynamic rawDay) {
  final day = rawDay is num ? rawDay.toInt() : int.tryParse('$rawDay');
  return switch (day) {
    1 => 'Lun',
    2 => 'Mar',
    3 => 'Mie',
    4 => 'Jue',
    5 => 'Vie',
    6 => 'Sab',
    0 => 'Dom',
    _ => null,
  };
}

String? _businessTimeLabel(dynamic rawTime) {
  if (rawTime is String) return _placesTimeLabel(rawTime);
  if (rawTime is! Map) return null;

  final time = Map<String, dynamic>.from(rawTime);
  final hours = (time['hours'] as num?)?.toInt();
  final minutes = (time['minutes'] as num?)?.toInt() ?? 0;
  if (hours == null) return null;
  return _clockLabel(hours, minutes);
}

List<PlanningCalendarStorePeriod> _storePeriodsFromSchedule(
  Map<String, dynamic> schedule,
) {
  final raw =
      (schedule['businessHoursJson']?.toString().trim().isNotEmpty ?? false)
          ? schedule['businessHoursJson'].toString()
          : schedule['googleBusinessHoursJson']?.toString();
  if (raw == null || raw.trim().isEmpty) return const [];

  try {
    final decoded = jsonDecode(raw);
    final root = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
    final data = root['opening_hours'] is Map
        ? Map<String, dynamic>.from(root['opening_hours'] as Map)
        : root;
    final periods = data['periods'] is List
        ? List<dynamic>.from(data['periods'] as List)
        : const <dynamic>[];
    final result = <PlanningCalendarStorePeriod>[];

    for (final rawPeriod in periods) {
      if (rawPeriod is! Map) continue;
      final period = Map<String, dynamic>.from(rawPeriod);
      final open = _mapValue(period['open']);
      final close = _mapValue(period['close']);
      final weekday = period.containsKey('openDay')
          ? _businessWeekdayNumber(period['openDay'])
          : _placesWeekdayNumber(open?['day']);
      final openMinutes = period.containsKey('openTime')
          ? _businessMinutesValue(period['openTime'])
          : _placesMinutesValue(open?['time']);
      final closeMinutes = period.containsKey('closeTime')
          ? _businessMinutesValue(period['closeTime'])
          : _placesMinutesValue(close?['time']);

      if (weekday == null || openMinutes == null || closeMinutes == null) {
        continue;
      }
      if (closeMinutes <= openMinutes) continue;
      result.add(
        PlanningCalendarStorePeriod(
          weekday: weekday,
          openMinutes: openMinutes,
          closeMinutes: closeMinutes,
        ),
      );
    }

    return result;
  } catch (_) {
    return const [];
  }
}

int? _businessWeekdayNumber(dynamic rawDay) {
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

int? _placesWeekdayNumber(dynamic rawDay) {
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

int? _businessMinutesValue(dynamic rawTime) {
  if (rawTime is String) return _placesMinutesValue(rawTime);
  if (rawTime is! Map) return null;
  final time = Map<String, dynamic>.from(rawTime);
  final hours = (time['hours'] as num?)?.toInt();
  final minutes = (time['minutes'] as num?)?.toInt() ?? 0;
  if (hours == null) return null;
  return hours.clamp(0, 23).toInt() * 60 + minutes.clamp(0, 59).toInt();
}

int? _placesMinutesValue(dynamic rawTime) {
  final digits = rawTime?.toString().replaceAll(':', '').trim();
  if (digits == null || digits.length < 3) return null;
  final padded = digits.padLeft(4, '0');
  final hours = int.tryParse(padded.substring(0, 2));
  final minutes = int.tryParse(padded.substring(2, 4));
  if (hours == null || minutes == null) return null;
  return hours.clamp(0, 23).toInt() * 60 + minutes.clamp(0, 59).toInt();
}

String? _placesTimeLabel(dynamic rawTime) {
  final digits = rawTime?.toString().replaceAll(':', '').trim();
  if (digits == null || digits.length < 3) return null;
  final padded = digits.padLeft(4, '0');
  final hours = int.tryParse(padded.substring(0, 2));
  final minutes = int.tryParse(padded.substring(2, 4));
  if (hours == null || minutes == null) return null;
  return _clockLabel(hours, minutes);
}

String _clockLabel(int hours, int minutes) {
  final safeHours = hours.clamp(0, 23);
  final safeMinutes = minutes.clamp(0, 59);
  return '${safeHours.toString().padLeft(2, '0')}:'
      '${safeMinutes.toString().padLeft(2, '0')}';
}
