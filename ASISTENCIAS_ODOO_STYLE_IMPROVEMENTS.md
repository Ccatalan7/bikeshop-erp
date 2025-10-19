# Asistencias Module - Odoo-Style Improvements

## 📋 Overview

The Asistencias (Attendances) module has been enhanced to match Odoo's attendance app behavior and visual design, based on the provided screenshots.

## ✅ Implemented Features

### 1. **Real-Time Clock for Ongoing Attendances** ⏱️
- **What it does**: Shows live elapsed time for employees currently clocked in
- **How it works**: A timer refreshes the UI every minute, recalculating the duration since check-in
- **Display format**: `HH:MM` format (e.g., "6:30" for 6 hours and 30 minutes)
- **Visual indicator**: Green blocks indicate ongoing shifts

### 2. **Clickable Attendance Blocks** 🖱️
- **What it does**: Each colored time block in the calendar is now tappable
- **How it works**: `GestureDetector` wraps each attendance block
- **Opens**: A detailed dialog showing full attendance information

### 3. **Attendance Detail Dialog** 📝
- **Layout**: Modal dialog with three sections:
  - **Header**: Status workflow visualization (Por aprobar → Aprobada → Rechazado)
  - **Content**: Editable attendance details
  - **Footer**: Action buttons (Eliminar, Descartar, Guardar y cerrar)

- **Displayed Information**:
  - Employee name
  - Check-in date/time (editable)
  - Check-out date/time (editable)
  - Total worked time (auto-calculated)
  - Overtime hours (with reject option)
  - Notes field (multi-line text)

### 4. **Date-Time Pickers for Manual Editing** 📅
- **What it does**: Allows managers to adjust check-in/check-out times manually
- **How it works**: 
  - Tap on the time field (blue background indicates it's editable)
  - Opens native date picker first
  - Then opens time picker with 24-hour format
  - Combines both selections into a single DateTime
- **Use cases**: 
  - Correcting forgotten clock-outs
  - Adjusting times for employees who forgot to clock in
  - Historical data entry

### 5. **Enhanced Color Coding** 🎨
- **Ongoing (En curso)**: Green background with dark green border
  - Shows live elapsed time
  - Only displays check-in time ("(11:16)")
  
- **Pending Approval**: Gray background with gray border
  - Completed shifts waiting for manager approval
  
- **Approved**: Light green background with light green border
  - Shows worked hours ("6.5h")
  
- **Rejected**: Red background with dark red border
  - Shows the shift was rejected by manager

### 6. **Status Workflow Visualization** 🔄
- **Visual indicator**: Three status chips in dialog header
  - "Por aprobar" (Pending)
  - "Aprobada" (Approved)
  - "Rechazado" (Rejected)
- **Active status**: Highlighted with cyan background
- **Inactive statuses**: White background with gray border

## 🔧 Technical Implementation

### Timer Management
```dart
Timer? _refreshTimer;

@override
void initState() {
  _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
    if (mounted) {
      setState(() {}); // Trigger rebuild to update elapsed times
    }
  });
}

@override
void dispose() {
  _refreshTimer?.cancel();
  super.dispose();
}
```

### Live Time Calculation
```dart
if (attendance.isOngoing) {
  final duration = DateTime.now().difference(attendance.checkIn);
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  displayTime = '$hours:${minutes.toString().padLeft(2, '0')}';
}
```

### Date-Time Picker Integration
```dart
Future<void> _pickDateTime(bool isCheckIn) async {
  // 1. Show date picker
  final DateTime? pickedDate = await showDatePicker(...);
  
  // 2. Show time picker with 24-hour format
  final TimeOfDay? pickedTime = await showTimePicker(
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      );
    },
  );
  
  // 3. Combine date and time
  final DateTime combined = DateTime(
    pickedDate.year, pickedDate.month, pickedDate.day,
    pickedTime.hour, pickedTime.minute,
  );
}
```

## 🎯 User Experience Improvements

### Before
- Static time display
- No indication of ongoing vs completed shifts
- No way to view or edit attendance details
- Difficult to distinguish between different statuses

### After
- ✅ Live time updates for ongoing shifts
- ✅ Clear visual indicators (green = ongoing, gray = pending, etc.)
- ✅ One-tap access to full attendance details
- ✅ Easy manual time adjustments with native pickers
- ✅ Clear status workflow visualization
- ✅ Approval/rejection actions in dialog

## 📱 Workflow Examples

### Manager Reviewing Attendance
1. Open Asistencias module
2. See week view with all employee shifts
3. Notice green blocks = employees currently working
4. See elapsed time updating live (e.g., "6:30")
5. Tap on any block to view details
6. Review times, notes, and overtime
7. Approve or reject from dialog
8. Edit times if needed (e.g., employee forgot to clock out)

### Correcting a Forgotten Clock-Out
1. Tap on attendance block (shows "En curso")
2. Dialog opens showing check-in but no check-out
3. Tap on "Salida" field
4. Select correct date in calendar picker
5. Select correct time in time picker
6. Click "Guardar y cerrar"
7. System recalculates worked hours automatically
8. Attendance status changes to "Por aprobar"

## 🔄 Integration with Backend

### Service Methods Used
- `hrService.updateAttendance()` - Save edited times
- `hrService.deleteAttendance()` - Remove attendance record
- `hrService.approveAttendance()` - Mark as approved
- `hrService.rejectAttendance()` - Mark as rejected

### Data Flow
1. User edits times in dialog
2. Dialog calls `onSave` callback with updated `Attendance` object
3. Service updates database via Supabase
4. Page refreshes to show updated data
5. Timer continues updating live times for ongoing shifts

## 🎨 Visual Design Alignment

### Odoo Reference
The implementation closely matches Odoo's design:
- ✅ Status workflow chips at top
- ✅ Editable fields with visual feedback (blue backgrounds)
- ✅ Calendar/time pickers for date-time editing
- ✅ Color-coded blocks (green for ongoing)
- ✅ Live time display format (HH:MM)
- ✅ Action buttons at bottom (Eliminar, Descartar, Guardar)

## 🚀 Future Enhancements

### Potential Improvements
1. **Employee avatars**: Show photo instead of just color circles
2. **Geolocation**: Show location on map when available
3. **Batch operations**: Approve multiple attendances at once
4. **Export**: Generate attendance reports (PDF, Excel)
5. **Notifications**: Alert managers of pending approvals
6. **Overtime rules**: Auto-calculate overtime based on contract hours
7. **Break time tracking**: Separate field for lunch/break deductions

## 📊 Database Schema

No schema changes were required. The module uses existing fields:
- `check_in` - Entry timestamp
- `check_out` - Exit timestamp (nullable for ongoing)
- `worked_hours` - Calculated duration
- `overtime_hours` - Extra hours beyond standard shift
- `status` - Enum: ongoing, completed, approved, rejected
- `notes` - Text field for comments
- `approved_by` - Manager who approved/rejected
- `approved_at` - Approval timestamp

## ✅ Testing Checklist

- [x] Live time updates every minute
- [x] Clicking block opens dialog
- [x] Date picker shows calendar
- [x] Time picker uses 24-hour format
- [x] Saving updates database
- [x] Color coding reflects correct status
- [x] Worked time auto-calculates
- [x] Delete confirmation dialog appears
- [x] Approval/rejection updates status
- [x] Timer cleans up on page dispose

## 🎉 Result

The Asistencias module now provides a professional, Odoo-style attendance management experience with:
- Real-time tracking for ongoing shifts
- Intuitive visual design
- Easy editing and approval workflows
- Mobile-friendly date/time pickers
- Clear status indicators

Perfect for bike shop managers tracking mechanic/technician work hours! 🚴‍♂️
