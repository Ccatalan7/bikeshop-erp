import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AttendanceWeekWorker {
  const AttendanceWeekWorker({
    required this.id,
    required this.fullName,
    required this.initials,
    required this.jobTitle,
    required this.color,
    this.photoUrl,
  });

  final String id;
  final String fullName;
  final String initials;
  final String jobTitle;
  final Color color;
  final String? photoUrl;
}

class AttendanceWeekEntry {
  const AttendanceWeekEntry({
    required this.id,
    required this.workerId,
    required this.checkIn,
    required this.status,
    this.checkOut,
  });

  final String id;
  final String workerId;
  final DateTime checkIn;
  final DateTime? checkOut;
  final String status;

  bool get isOngoing => status == 'ongoing' && checkOut == null;

  Duration get duration {
    if (checkOut != null) return checkOut!.difference(checkIn);
    if (isOngoing) return DateTime.now().difference(checkIn);
    return Duration.zero;
  }
}

class AttendanceWeekCalendar extends StatelessWidget {
  const AttendanceWeekCalendar({
    super.key,
    required this.weekStart,
    required this.workers,
    required this.entriesByWorkerId,
    required this.toDisplayTimeZone,
    this.onEntryTap,
    this.padding = const EdgeInsets.all(16),
    this.workerColumnWidth = 240,
    this.dayColumnWidth = 168,
    this.headerHeight = 74,
    this.rowHeight = 96,
  });

  final DateTime weekStart;
  final List<AttendanceWeekWorker> workers;
  final Map<String, List<AttendanceWeekEntry>> entriesByWorkerId;
  final DateTime Function(DateTime dateTime) toDisplayTimeZone;
  final ValueChanged<AttendanceWeekEntry>? onEntryTap;
  final EdgeInsets padding;
  final double workerColumnWidth;
  final double dayColumnWidth;
  final double headerHeight;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final days =
        List.generate(7, (index) => weekStart.add(Duration(days: index)));

    if (workers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No hay trabajadores registrados',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderRow(
                days: days,
                workerColumnWidth: workerColumnWidth,
                dayColumnWidth: dayColumnWidth,
                headerHeight: headerHeight,
              ),
              ...workers.map(
                (worker) => _WorkerAttendanceRow(
                  worker: worker,
                  days: days,
                  entries: entriesByWorkerId[worker.id] ??
                      const <AttendanceWeekEntry>[],
                  toDisplayTimeZone: toDisplayTimeZone,
                  onEntryTap: onEntryTap,
                  workerColumnWidth: workerColumnWidth,
                  dayColumnWidth: dayColumnWidth,
                  rowHeight: rowHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.days,
    required this.workerColumnWidth,
    required this.dayColumnWidth,
    required this.headerHeight,
  });

  final List<DateTime> days;
  final double workerColumnWidth;
  final double dayColumnWidth;
  final double headerHeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GridCell(
          width: workerColumnWidth,
          height: headerHeight,
          backgroundColor: Colors.white,
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Días',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        ...days.map(
          (day) => _DayHeaderCell(
            day: day,
            width: dayColumnWidth,
            height: headerHeight,
          ),
        ),
      ],
    );
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.day,
    required this.width,
    required this.height,
  });

  final DateTime day;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = today.year == day.year &&
        today.month == day.month &&
        today.day == day.day;

    return _GridCell(
      width: width,
      height: height,
      backgroundColor: isToday ? const Color(0xFFEFF6FF) : Colors.white,
      borderColor: isToday ? const Color(0xFF1D4ED8) : Colors.grey.shade300,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday ? const Color(0xFF1D4ED8) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              day.day.toString().padLeft(2, '0'),
              style: TextStyle(
                color: isToday ? Colors.white : const Color(0xFF111827),
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
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                Text(
                  DateFormat('dd/MM').format(day),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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

class _WorkerAttendanceRow extends StatelessWidget {
  const _WorkerAttendanceRow({
    required this.worker,
    required this.days,
    required this.entries,
    required this.toDisplayTimeZone,
    required this.workerColumnWidth,
    required this.dayColumnWidth,
    required this.rowHeight,
    this.onEntryTap,
  });

  final AttendanceWeekWorker worker;
  final List<DateTime> days;
  final List<AttendanceWeekEntry> entries;
  final DateTime Function(DateTime dateTime) toDisplayTimeZone;
  final ValueChanged<AttendanceWeekEntry>? onEntryTap;
  final double workerColumnWidth;
  final double dayColumnWidth;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final sortedEntries = [...entries]..sort(
        (a, b) => a.checkIn.compareTo(b.checkIn),
      );
    final total = sortedEntries.fold<Duration>(
      Duration.zero,
      (sum, entry) => sum + entry.duration,
    );

    return Row(
      children: [
        Tooltip(
          message: 'Semana: ${_durationLabel(total)}',
          waitDuration: const Duration(milliseconds: 450),
          child: _GridCell(
            width: workerColumnWidth,
            height: rowHeight,
            backgroundColor: Colors.grey.shade50,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: worker.color,
                  foregroundColor: Colors.white,
                  backgroundImage: worker.photoUrl == null
                      ? null
                      : NetworkImage(worker.photoUrl!),
                  child: worker.photoUrl == null
                      ? Text(
                          worker.initials,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        worker.jobTitle,
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
          ),
        ),
        ...days.map(
          (day) => _AttendanceDayCell(
            day: day,
            entries: sortedEntries.where((entry) {
              final displayCheckIn = toDisplayTimeZone(entry.checkIn);
              return displayCheckIn.year == day.year &&
                  displayCheckIn.month == day.month &&
                  displayCheckIn.day == day.day;
            }).toList(),
            toDisplayTimeZone: toDisplayTimeZone,
            onEntryTap: onEntryTap,
            width: dayColumnWidth,
            height: rowHeight,
          ),
        ),
      ],
    );
  }
}

class _AttendanceDayCell extends StatelessWidget {
  const _AttendanceDayCell({
    required this.day,
    required this.entries,
    required this.toDisplayTimeZone,
    required this.width,
    required this.height,
    this.onEntryTap,
  });

  final DateTime day;
  final List<AttendanceWeekEntry> entries;
  final DateTime Function(DateTime dateTime) toDisplayTimeZone;
  final ValueChanged<AttendanceWeekEntry>? onEntryTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _GridCell(
      width: width,
      height: height,
      backgroundColor: Colors.white,
      padding: const EdgeInsets.all(7),
      child: entries.isEmpty
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: entries
                    .map(
                      (entry) => _AttendanceBlock(
                        entry: entry,
                        toDisplayTimeZone: toDisplayTimeZone,
                        onTap: onEntryTap == null
                            ? null
                            : () => onEntryTap?.call(entry),
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}

class _AttendanceBlock extends StatelessWidget {
  const _AttendanceBlock({
    required this.entry,
    required this.toDisplayTimeZone,
    this.onTap,
  });

  final AttendanceWeekEntry entry;
  final DateTime Function(DateTime dateTime) toDisplayTimeZone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final checkIn = _timeLabel(toDisplayTimeZone(entry.checkIn));
    final checkOut = entry.checkOut == null
        ? '...'
        : _timeLabel(toDisplayTimeZone(entry.checkOut!));
    final duration = _durationLabel(entry.duration);
    final palette = _EntryPalette.fromStatus(entry.status, entry.isOngoing);
    final text = '$duration ($checkIn-$checkOut)';

    final block = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.text,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Tooltip(
      waitDuration: const Duration(milliseconds: 450),
      message: 'Duración: $duration\nEntrada: $checkIn\nSalida: $checkOut',
      child: onTap == null
          ? block
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: block,
            ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.width,
    required this.height,
    required this.child,
    required this.backgroundColor,
    this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final double width;
  final double height;
  final Widget child;
  final Color backgroundColor;
  final Color? borderColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor ?? Colors.grey.shade300),
      ),
      child: child,
    );
  }
}

class _EntryPalette {
  const _EntryPalette({
    required this.background,
    required this.border,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color text;

  factory _EntryPalette.fromStatus(String status, bool isOngoing) {
    if (isOngoing) {
      return _EntryPalette(
        background: Colors.green.shade100,
        border: Colors.green.shade700,
        text: Colors.green.shade900,
      );
    }
    return switch (status) {
      'approved' => _EntryPalette(
          background: Colors.green.shade50,
          border: Colors.green.shade300,
          text: Colors.green.shade800,
        ),
      'rejected' => _EntryPalette(
          background: Colors.red.shade100,
          border: Colors.red.shade700,
          text: Colors.red.shade900,
        ),
      _ => _EntryPalette(
          background: Colors.grey.shade100,
          border: Colors.grey.shade500,
          text: Colors.grey.shade900,
        ),
    };
  }
}

String _durationLabel(Duration duration) {
  if (duration.inMinutes <= 0) return '--:--';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return '$hours:${minutes.toString().padLeft(2, '0')}';
}

String _timeLabel(DateTime value) => DateFormat('HH:mm').format(value);

String _weekdayLabel(DateTime day) {
  const labels = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];
  return labels[day.weekday - 1];
}
