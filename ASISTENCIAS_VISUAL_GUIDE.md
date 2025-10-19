# 🎨 Asistencias Module - Visual Guide

## 📊 Calendar View Improvements

### Before vs After Comparison

#### **Before**
```
┌─────────────────────────────────────┐
│  Fernando Tapia                     │
│  ┌──────────┐                       │
│  │ 6.5h     │  (No color coding)    │
│  │ (11:16-  │  (Static display)     │
│  │  17:46)  │  (Not clickable)      │
│  └──────────┘                       │
└─────────────────────────────────────┘
```

#### **After**
```
┌─────────────────────────────────────┐
│  🟢 Fernando Tapia                  │
│  ┌──────────┐                       │
│  │ 6:30 ⏱️  │  ✅ Green = Ongoing   │
│  │ (11:16)  │  ✅ Live updating     │
│  │          │  ✅ Clickable!        │
│  └──────────┘  👆 Tap to edit       │
└─────────────────────────────────────┘
```

---

## 🎯 Color Coding System

### Status Color Legend

| Status | Color | Border | Description | Example |
|--------|-------|--------|-------------|---------|
| **En curso** (Ongoing) | 🟢 Light Green | Dark Green | Employee is currently working | "6:30 (11:16)" |
| **Por aprobar** (Pending) | ⚪ Gray | Gray | Shift completed, waiting for approval | "6.5h (11:16)" |
| **Aprobada** (Approved) | 🟩 Pale Green | Light Green | Approved by manager | "6.5h (11:16)" |
| **Rechazado** (Rejected) | 🟥 Red | Dark Red | Rejected by manager | "6.5h (11:16)" |

### Visual Examples

```
┌─── ONGOING ────────────────┐
│  🟢 Background: #C8E6C9   │
│  🟢 Border: #388E3C       │
│                           │
│       6:30                │  ← HH:MM format (live)
│      (11:16)              │  ← Check-in time only
└───────────────────────────┘

┌─── PENDING ────────────────┐
│  ⚪ Background: #EEEEEE   │
│  ⚪ Border: #757575       │
│                           │
│       6.5h                │  ← Total hours
│      (11:16)              │  ← Check-in time
└───────────────────────────┘

┌─── APPROVED ───────────────┐
│  🟩 Background: #E8F5E9   │
│  🟩 Border: #81C784       │
│                           │
│       6.5h                │  ← Total hours
│      (11:16)              │  ← Check-in time
└───────────────────────────┘

┌─── REJECTED ───────────────┐
│  🟥 Background: #FFCDD2   │
│  🟥 Border: #C62828       │
│                           │
│       6.5h                │  ← Total hours
│      (11:16)              │  ← Check-in time
└───────────────────────────┘
```

---

## 📝 Detail Dialog Layout

### Dialog Structure

```
┌─────────────────────────────────────────────────────────┐
│  HEADER (Gray background)                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │  Abierto                                       ✕    ││
│  │                                                      ││
│  │  ┌───────────┐   ➤   ┌──────────┐   ➤  ┌─────────┐││
│  │  │Por aprobar│        │ Aprobada │       │Rechazado│││
│  │  └───────────┘        └──────────┘       └─────────┘││
│  │      ↑ Cyan when active                             ││
│  └─────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────┤
│  CONTENT (White background, scrollable)                 │
│                                                          │
│  👤 Fernando Tapia                                      │
│     Manager                                             │
│                                                          │
│  Entrada                                                │
│  ┌──────────────────────────────────────┐              │
│  │ 📅 15/10/2025 11:16           ✏️    │  ← Editable  │
│  └──────────────────────────────────────┘              │
│                                                          │
│  Salida                                                 │
│  ┌──────────────────────────────────────┐              │
│  │ 📅 15/10/2025 17:46           ✏️    │  ← Editable  │
│  └──────────────────────────────────────┘              │
│                                                          │
│  Tiempo trabajado                                       │
│  ┌──────────────────────────────────────┐              │
│  │     06:30                            │              │
│  └──────────────────────────────────────┘              │
│                                                          │
│  Horas extra                                            │
│  -01:00  [✕ Rechazar]                                  │
│                                                          │
│  Notas                                                  │
│  ┌──────────────────────────────────────┐              │
│  │                                      │              │
│  │  (Multi-line text field)             │              │
│  │                                      │              │
│  └──────────────────────────────────────┘              │
├─────────────────────────────────────────────────────────┤
│  FOOTER (Gray background)                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │  🗑️ Eliminar          [Descartar] [Guardar y cerrar]││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

---

## 🕐 Time Display Formats

### Ongoing Attendance (En curso)

**Calendar Block:**
```
┌──────────┐
│  6:30    │  ← Live updating every minute
│ (11:16)  │  ← Check-in time (static)
└──────────┘
```

**Calculation:**
```dart
final duration = DateTime.now() - checkIn;
final hours = duration.inHours;         // 6
final minutes = duration.inMinutes % 60; // 30
display = "$hours:$minutes";             // "6:30"
```

### Completed Attendance (Con salida)

**Calendar Block:**
```
┌──────────┐
│  6.5h    │  ← Total hours (decimal)
│ (11:16)  │  ← Check-in time
└──────────┘
```

**Calculation:**
```dart
final duration = checkOut - checkIn;
final hours = duration.inHours / 60;  // 6.5
display = "${hours.toStringAsFixed(1)}h"; // "6.5h"
```

---

## 📅 Date-Time Picker Workflow

### User Flow for Editing Times

```
1. USER CLICKS TIME FIELD
   ┌──────────────────────────┐
   │ 📅 15/10/2025 11:16  ✏️ │ ← Blue background
   └──────────────────────────┘
             ↓
             
2. CALENDAR PICKER APPEARS
   ┌────────────────────────┐
   │   octubre 2025         │
   │  L  M  M  J  V  S  D   │
   │           1  2  3  4  5│
   │  6  7  8  9 10 11 12   │
   │ 13 14 [15]16 17 ⭕ 19 │
   │         ↑   ↑           │
   │      picked today       │
   └────────────────────────┘
             ↓
             
3. TIME PICKER APPEARS (24H)
   ┌────────────────────────┐
   │     11:16:24           │
   │                        │
   │      11  :  16         │
   │      ↑       ↑         │
   │    hours  minutes      │
   │                        │
   │       [Aplicar]        │
   └────────────────────────┘
             ↓
             
4. UPDATED FIELD
   ┌──────────────────────────┐
   │ 📅 15/10/2025 11:16  ✏️ │
   └──────────────────────────┘
```

---

## 🔄 Status Workflow Visualization

### Dialog Header States

#### 1. **Pending Approval** (Por aprobar)
```
┌─────────────────────────────────────────┐
│ ┏━━━━━━━━━━━┓     ┌──────────┐  ┌─────────┐
│ ┃Por aprobar┃  ➤  │ Aprobada │  │Rechazado│
│ ┗━━━━━━━━━━━┛     └──────────┘  └─────────┘
│  ↑ Cyan/Active     ↑ Gray        ↑ Gray
└─────────────────────────────────────────┘
```

#### 2. **Approved** (Aprobada)
```
┌─────────────────────────────────────────┐
│ ┌───────────┐     ┏━━━━━━━━━━┓  ┌─────────┐
│ │Por aprobar│  ➤  ┃ Aprobada ┃  │Rechazado│
│ └───────────┘     ┗━━━━━━━━━━┛  └─────────┘
│  ↑ Gray            ↑ Cyan/Active ↑ Gray
└─────────────────────────────────────────┘
```

#### 3. **Rejected** (Rechazado)
```
┌─────────────────────────────────────────┐
│ ┌───────────┐     ┌──────────┐  ┏━━━━━━━━━┓
│ │Por aprobar│  ➤  │ Aprobada │  ┃Rechazado┃
│ └───────────┘     └──────────┘  ┗━━━━━━━━━┛
│  ↑ Gray           ↑ Gray         ↑ Cyan/Active
└─────────────────────────────────────────┘
```

---

## 🎭 Interactive Elements

### Clickable Areas

```
Calendar Grid:
┌─────────────────────────────────┐
│ Empleado │ Lun │ Mar │ Mié │... │
├──────────┼─────┼─────┼─────┼────┤
│ Fernando │ 👆  │     │     │    │  ← Each block is clickable
│          │6:30 │     │     │    │
│          │(11:16)                │
├──────────┼─────┼─────┼─────┼────┤
│ Claudio  │     │ 👆  │     │    │
│          │     │7.2h │     │    │
│          │     │(09:00)          │
└─────────────────────────────────┘

Tap anywhere on the colored block → Opens detail dialog
```

### Editable Fields (Blue Background)

```
┌──────────────────────────────────┐
│ 📅 15/10/2025 11:16        ✏️   │  ← Indicates editable
└──────────────────────────────────┘
    ↑ Blue background = clickable
```

---

## ⏱️ Live Update Mechanism

### Timer Refresh Cycle

```
Initial State (11:16):
┌──────────┐
│  0:00    │
│ (11:16)  │
└──────────┘

After 30 minutes (11:46):
┌──────────┐
│  0:30    │  ← Updated automatically
│ (11:16)  │
└──────────┘

After 6.5 hours (17:46):
┌──────────┐
│  6:30    │  ← Still updating (if no checkout)
│ (11:16)  │
└──────────┘

After checkout:
┌──────────┐
│  6.5h    │  ← Static display (decimal hours)
│ (11:16)  │
└──────────┘
```

**Technical Implementation:**
- Timer fires every 60 seconds
- Calls `setState()` to rebuild UI
- Only active attendances recalculate
- Completed attendances use cached `worked_hours`

---

## 🎨 Odoo Design Alignment Checklist

✅ **Color Coding**
- Green for ongoing shifts
- Gray for pending approval
- Light green for approved
- Red for rejected

✅ **Status Workflow**
- Three-stage chips at top
- Cyan highlight for active stage
- Arrow indicators between stages

✅ **Time Display**
- Live HH:MM format for ongoing
- Decimal hours for completed
- Only check-in time shown in block

✅ **Editable Fields**
- Blue background indicates interactive
- Pencil icon on right side
- Calendar + time picker flow

✅ **Dialog Layout**
- Header: Status workflow
- Content: Form fields (scrollable)
- Footer: Actions (left: delete, right: save/cancel)

✅ **Typography**
- Bold labels for field names
- Large text for employee name
- Small gray text for job title

---

## 📱 Responsive Behavior

### Calendar Grid Scrolling

```
Horizontal Scroll:
┌────────────────────────────────────────┐
│ Empleado │ Lun │ Mar │ Mié │ Jue │ ...│
│══════════│═════│═════│═════│═════│════│
│ Fernando │ ■   │     │     │ ■   │    │ ← Scroll right →
│ Claudio  │     │ ■   │ ■   │     │    │
│ Max      │ ■   │ ■   │     │ ■   │    │
└────────────────────────────────────────┘

Vertical Scroll (many employees):
┌──────────┐
│ Fernando │ ↕
│ Claudio  │ Scroll
│ Max      │ down
│ ...      │ ↓
└──────────┘
```

### Dialog Responsive

```
Desktop (600px wide):
┌────────────────────────────────────┐
│  Full width dialog                 │
│  Comfortable spacing               │
└────────────────────────────────────┘

Mobile (Full screen):
┌──────────────────┐
│  Full screen     │
│  Larger touch    │
│  targets         │
└──────────────────┘
```

---

## 🚀 Performance Optimizations

### Efficient Updates

```dart
// ❌ BAD: Rebuild entire page every second
Timer.periodic(Duration(seconds: 1), (_) {
  setState(() {
    _loadData(); // Expensive!
  });
});

// ✅ GOOD: Just rebuild UI every minute
Timer.periodic(Duration(minutes: 1), (_) {
  if (mounted) {
    setState(() {}); // Cheap! Just recalculates display time
  }
});
```

### Memory Management

```dart
@override
void dispose() {
  _refreshTimer?.cancel(); // ✅ Clean up timer
  super.dispose();
}
```

---

## 🎉 Summary

The Asistencias module now provides a **professional, Odoo-style** attendance management experience with:

- 🟢 **Live time tracking** for ongoing shifts
- 🎨 **Color-coded status** indicators
- 👆 **Clickable blocks** for easy access
- ✏️ **Editable times** with native pickers
- 🔄 **Status workflow** visualization
- 📱 **Responsive design** for all devices

Perfect for tracking bike shop mechanics and technicians! 🚴‍♂️🔧
