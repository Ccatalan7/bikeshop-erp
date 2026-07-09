// ignore_for_file: unused_element

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

enum PlanningCalendarTimeZone { chile, local, utc }

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

class PlanningCalendarWorker {
  const PlanningCalendarWorker({
    required this.id,
    required this.fullName,
    required this.jobTitle,
    this.initials,
    this.photoUrl,
  });

  final String? id;
  final String fullName;
  final String jobTitle;
  final String? initials;
  final String? photoUrl;
}

class PlanningCalendarShift {
  const PlanningCalendarShift({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.status,
    this.employeeId,
    this.title,
    this.roleId,
    this.roleName,
    this.roleColor,
    this.storeHoursValidated = true,
    this.outsideStoreHoursReason,
  });

  final String id;
  final String? employeeId;
  final String? title;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final String? roleId;
  final String? roleName;
  final String? roleColor;
  final bool storeHoursValidated;
  final String? outsideStoreHoursReason;

  PlanningCalendarShift copyWith({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
  }) {
    return PlanningCalendarShift(
      id: id,
      employeeId: employeeId,
      title: title,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      status: status ?? this.status,
      roleId: roleId,
      roleName: roleName,
      roleColor: roleColor,
      storeHoursValidated: storeHoursValidated,
      outsideStoreHoursReason: outsideStoreHoursReason,
    );
  }
}

class PlanningCalendarStorePeriod {
  const PlanningCalendarStorePeriod({
    required this.weekday,
    required this.openMinutes,
    required this.closeMinutes,
  });

  final int weekday;
  final int openMinutes;
  final int closeMinutes;
}

class ShiftPlanningCalendar extends StatefulWidget {
  const ShiftPlanningCalendar({
    super.key,
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
    this.editableWorkerIds = const {},
    this.showWorkerSidebar = true,
    this.allowCreateShift = true,
    this.allowCreateShiftFromWorker = true,
    this.allowAdministrativeActions = true,
  });

  static const double _hourHeight = 64;
  static const double _timeGutterWidth = 64;
  static const double _headerHeight = 78;
  static const double _minimumDayWidth = 196;

  final List<DateTime> days;
  final List<PlanningCalendarShift> shifts;
  final Map<String, PlanningCalendarWorker> employeeById;
  final List<PlanningCalendarStorePeriod> storePeriods;
  final PlanningCalendarTimeZone displayTimeZone;
  final ValueChanged<DateTime> onCreateShift;
  final Future<void> Function(
    PlanningCalendarWorker worker,
    DateTime day,
    int startMinutes,
    int durationMinutes,
  ) onCreateShiftFromWorker;
  final ValueChanged<PlanningCalendarShift> onEditShift;
  final Future<void> Function(
      PlanningCalendarShift shift, DateTime day, int startMinutes) onMoveShift;
  final Future<void> Function(
    PlanningCalendarShift shift, {
    required bool resizeStart,
    required int deltaMinutes,
  }) onResizeShift;
  final ValueChanged<PlanningCalendarShift> onPublishShift;
  final ValueChanged<PlanningCalendarShift> onCancelShift;
  final ValueChanged<PlanningCalendarShift> onDeleteShift;
  final Set<String> editableWorkerIds;
  final bool showWorkerSidebar;
  final bool allowCreateShift;
  final bool allowCreateShiftFromWorker;
  final bool allowAdministrativeActions;

  @override
  State<ShiftPlanningCalendar> createState() => ShiftPlanningCalendarState();
}

class ShiftPlanningCalendarState extends State<ShiftPlanningCalendar> {
  static const double _hourHeight = ShiftPlanningCalendar._hourHeight;
  static const double _timeGutterWidth = ShiftPlanningCalendar._timeGutterWidth;
  static const double _headerHeight = ShiftPlanningCalendar._headerHeight;
  static const double _minimumDayWidth = ShiftPlanningCalendar._minimumDayWidth;
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

  bool _canEditShift(PlanningCalendarShift shift) {
    final workerId = shift.employeeId;
    return widget.editableWorkerIds.isEmpty ||
        workerId != null && widget.editableWorkerIds.contains(workerId);
  }

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
    PlanningCalendarShift shift, {
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

  void _startShiftInteraction(PlanningCalendarShift shift, String kind) {
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

  void _endShiftInteraction(PlanningCalendarShift shift, String kind) {
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
        final showSidebar =
            widget.showWorkerSidebar && constraints.maxWidth >= 1180;
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
                          allowCreateShift: widget.allowCreateShift,
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
                                          allowCreateShift:
                                              widget.allowCreateShift,
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
                  allowCreateShiftFromWorker: widget.allowCreateShiftFromWorker,
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
      final displayedStart = _toPlanningCalendarTimeZone(
        renderedShift.startAt,
        widget.displayTimeZone,
      );
      if (displayedStart.year != day.year ||
          displayedStart.month != day.month ||
          displayedStart.day != day.day) {
        continue;
      }

      final displayedEnd = _toPlanningCalendarTimeZone(
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
      final isEditable = _canEditShift(shift);

      final block = _CalendarShiftBlock(
        shift: renderedShift,
        employee: widget.employeeById[shift.employeeId],
        displayTimeZone: widget.displayTimeZone,
        hourHeight: _hourHeight,
        feedbackWidth: laneWidth,
        feedbackHeight: height,
        isEditable: isEditable,
        allowAdministrativeActions: widget.allowAdministrativeActions,
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

  PlanningCalendarShift _renderedShiftForResizePreview(
      PlanningCalendarShift shift) {
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

    final currentStart = _toPlanningCalendarTimeZone(
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
    if (!widget.allowCreateShiftFromWorker) {
      _clearWorkerDragPreview();
      _endWorkerInteraction(data);
      return;
    }
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

  PlanningCalendarShift _previewShiftForWorkerDrag(
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

    return PlanningCalendarShift(
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
    final edge = _toPlanningCalendarTimeZone(
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
      final displayedStart = _toPlanningCalendarTimeZone(
        renderedShift.startAt,
        widget.displayTimeZone,
      );
      if (!_sameDate(displayedStart, day)) continue;

      final displayedEnd = _toPlanningCalendarTimeZone(
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
      final displayedStart = _toPlanningCalendarTimeZone(
        renderedShift.startAt,
        widget.displayTimeZone,
      );
      if (!_sameDate(displayedStart, preview.day)) continue;

      final displayedEnd = _toPlanningCalendarTimeZone(
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
    required this.allowCreateShift,
  });

  final List<DateTime> days;
  final double dayWidth;
  final double timeGutterWidth;
  final double headerHeight;
  final ValueChanged<DateTime> onCreateShift;
  final bool allowCreateShift;

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
                      if (allowCreateShift)
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
    required this.allowCreateShift,
  });

  final DateTime day;
  final PlanningCalendarStorePeriod? storePeriod;
  final PlanningCalendarTimeZone displayTimeZone;
  final int startHour;
  final double hourHeight;
  final ValueChanged<DateTime> onCreateShift;
  final bool allowCreateShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final storeRange = storePeriod == null
        ? null
        : _displayStoreRange(day, storePeriod!, displayTimeZone);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: allowCreateShift ? () => onCreateShift(day) : null,
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

  final PlanningCalendarShift shift;
  final PlanningCalendarWorker? employee;
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

  final PlanningCalendarWorker worker;
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
    required this.isEditable,
    required this.allowAdministrativeActions,
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

  final PlanningCalendarShift shift;
  final PlanningCalendarWorker? employee;
  final PlanningCalendarTimeZone displayTimeZone;
  final double hourHeight;
  final double feedbackWidth;
  final double feedbackHeight;
  final bool tooltipEnabled;
  final bool isEditable;
  final bool allowAdministrativeActions;
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
    final start = _toPlanningCalendarTimeZone(shift.startAt, displayTimeZone);
    final end = _toPlanningCalendarTimeZone(shift.endAt, displayTimeZone);
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
          onTap: isEditable && tooltipEnabled ? onTap : null,
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
                          if (isEditable)
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
                                if (allowAdministrativeActions &&
                                    shift.status == 'draft')
                                  const PopupMenuItem(
                                    value: 'publish',
                                    child: Text('Publicar'),
                                  ),
                                if (allowAdministrativeActions &&
                                    shift.status != 'cancelled')
                                  const PopupMenuItem(
                                    value: 'cancel',
                                    child: Text('Cancelar turno'),
                                  ),
                                if (allowAdministrativeActions)
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
              child: isEditable
                  ? Draggable<_CalendarShiftDragData>(
                      data: dragData,
                      dragAnchorStrategy: (draggable, context, position) {
                        final box = context.findRenderObject() as RenderBox?;
                        final anchor = box == null
                            ? Offset.zero
                            : box.globalToLocal(position);
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
                              'start=${_formatTime(start)} '
                              'end=${_formatTime(end)} '
                              'feedback=${feedbackWidth.toStringAsFixed(1)}x'
                              '${feedbackHeight.toStringAsFixed(1)} '
                              'visible=false',
                        );
                      },
                      onDragUpdate: (details) {
                        onDragPositionChanged(
                          dragData,
                          details.globalPosition,
                        );
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
                        child: SizedBox(
                          width: feedbackWidth,
                          height: feedbackHeight,
                        ),
                      ),
                      childWhenDragging: const SizedBox.expand(),
                      child: card,
                    )
                  : card,
            ),
            if (isEditable) ...[
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

  final PlanningCalendarShift shift;
  final int durationMinutes;
  Offset grabOffset = Offset.zero;
}

class _CalendarWorkerDragData {
  _CalendarWorkerDragData({
    required this.worker,
    required this.durationMinutes,
  });

  final PlanningCalendarWorker worker;
  final int durationMinutes;
}

class _CalendarDragPreview {
  const _CalendarDragPreview({
    required this.shift,
    required this.day,
    required this.startMinutes,
    required this.durationMinutes,
  });

  final PlanningCalendarShift shift;
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

  final PlanningCalendarWorker worker;
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

  final PlanningCalendarShift shift;
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

  final PlanningCalendarShift shift;
  final PlanningCalendarShift renderedShift;
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
    required this.allowCreateShiftFromWorker,
    required this.onToggleCollapsed,
    required this.onWorkerDragStarted,
    required this.onWorkerDragPositionChanged,
    required this.onWorkerDragFinished,
  });

  final List<PlanningCalendarWorker> employees;
  final List<PlanningCalendarShift> shifts;
  final PlanningCalendarTimeZone displayTimeZone;
  final bool isCollapsed;
  final bool allowCreateShiftFromWorker;
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
              height: ShiftPlanningCalendar._headerHeight,
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
            height: ShiftPlanningCalendar._headerHeight,
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
                        durationMinutes: ShiftPlanningCalendarState
                            ._workerDropDefaultDurationMinutes,
                        dragEnabled: allowCreateShiftFromWorker,
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
    required this.dragEnabled,
    required this.onDragStarted,
    required this.onDragPositionChanged,
    required this.onDragFinished,
  });

  final PlanningCalendarWorker worker;
  final Color color;
  final int plannedMinutes;
  final int durationMinutes;
  final bool dragEnabled;
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

    if (!dragEnabled) {
      return tile;
    }

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

  final PlanningCalendarWorker worker;
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

int _calendarStartHour(
  List<DateTime> days,
  List<PlanningCalendarShift> shifts,
  List<PlanningCalendarStorePeriod> periods,
  PlanningCalendarTimeZone displayTimeZone,
) {
  var earliest = 9 * 60;
  for (final day in days) {
    final period = _storePeriodForDate(periods, day);
    if (period == null) continue;
    final range = _displayStoreRange(day, period, displayTimeZone);
    earliest = math.min(earliest, range.start.hour * 60 + range.start.minute);
  }
  for (final shift in shifts) {
    final start = _toPlanningCalendarTimeZone(shift.startAt, displayTimeZone);
    earliest = math.min(earliest, start.hour * 60 + start.minute);
  }
  return math.max(0, earliest ~/ 60 - 1);
}

int _calendarEndHour(
  List<DateTime> days,
  List<PlanningCalendarShift> shifts,
  List<PlanningCalendarStorePeriod> periods,
  PlanningCalendarTimeZone displayTimeZone,
) {
  var latest = 20 * 60;
  for (final day in days) {
    final period = _storePeriodForDate(periods, day);
    if (period == null) continue;
    final range = _displayStoreRange(day, period, displayTimeZone);
    latest = math.max(latest, range.end.hour * 60 + range.end.minute);
  }
  for (final shift in shifts) {
    final end = _toPlanningCalendarTimeZone(shift.endAt, displayTimeZone);
    latest = math.max(latest, end.hour * 60 + end.minute);
  }
  return math.min(24, (latest / 60).ceil() + 1);
}

DateTimeRange _displayStoreRange(
  DateTime day,
  PlanningCalendarStorePeriod period,
  PlanningCalendarTimeZone displayTimeZone,
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
    start: _toPlanningCalendarTimeZone(start, displayTimeZone),
    end: _toPlanningCalendarTimeZone(end, displayTimeZone),
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

String _calendarTimeZoneLabel(PlanningCalendarTimeZone displayTimeZone) {
  return switch (displayTimeZone) {
    PlanningCalendarTimeZone.chile => 'Hora Chile',
    PlanningCalendarTimeZone.local => 'Hora local',
    PlanningCalendarTimeZone.utc => 'Hora UTC',
  };
}

PlanningCalendarStorePeriod? _storePeriodForDate(
    List<PlanningCalendarStorePeriod> periods, DateTime date) {
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
  PlanningCalendarTimeZone displayTimeZone,
  int year,
  int month,
  int day,
  int hour,
  int minute,
) {
  return switch (displayTimeZone) {
    PlanningCalendarTimeZone.chile => _planningChileDateTime(
        year,
        month,
        day,
        hour,
        minute,
      ),
    PlanningCalendarTimeZone.utc =>
      DateTime.utc(year, month, day, hour, minute),
    PlanningCalendarTimeZone.local => DateTime(year, month, day, hour, minute),
  };
}

DateTime _toPlanningCalendarTimeZone(
  DateTime dateTime,
  PlanningCalendarTimeZone displayTimeZone,
) {
  return switch (displayTimeZone) {
    PlanningCalendarTimeZone.chile =>
      tz.TZDateTime.from(dateTime.toUtc(), _planningChileTimeZone()),
    PlanningCalendarTimeZone.utc => dateTime.toUtc(),
    PlanningCalendarTimeZone.local => dateTime.toLocal(),
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
