# 📊 Asistencias - View Mode Comparison

## Quick Reference Guide

### Cell Size Summary

| View | Width | Height | Display Format | Purpose |
|------|-------|--------|----------------|---------|
| **Day** | 200px | 100px | `07:29-19:25 (12:0)` | Maximum detail, comfortable spacing |
| **Week** | 140px | 80px | `07:29 (19:25-...` | Full time ranges, clear overview |
| **Month** | 100px | 70px | `07:29 (14...` | Compact time display, 30-day view |
| **Quarter** | 50px | 50px | `07` | **Ultra compact**, 90-day overview |
| **Year** | 140px | 120px | `07:29-19:25 (12:0)` | **Full detail, ALL shifts stacked** |

---

## Visual Examples

### 📅 Quarter View - ULTRA COMPACT (50px × 50px)
**Purpose:** Fit 3 months (~90 days) on screen with minimal scrolling

```
Employee Row (50px tall)
┌─────────────────────┬───┬───┬───┬───┬───┬───┬───┐
│ 👤 Juan Pérez       │ 1 │ 2 │ 3 │ 4 │ 5 │ 6 │ 7 │
│    Mecánico         ├───┼───┼───┼───┼───┼───┼───┤
│                     │07 │   │05 │06 │07 │   │08 │
└─────────────────────┴───┴───┴───┴───┴───┴───┴───┘
```

**Features:**
- ✅ Only shows hour digit (e.g., "07" = started at 7am)
- ✅ Minimal padding (2px/1px)
- ✅ 8px font size
- ✅ Clickable to see full details
- ✅ Color-coded status maintained
- ✅ ~90 days visible with horizontal scroll

---

### 📅 Month View - COMPACT (100px × 70px)
**Purpose:** See entire month comfortably

```
Employee Row (70px tall)
┌─────────────────────┬────────┬────────┬────────┬────────┐
│ 👤 Juan Pérez       │   1    │   2    │   3    │   4    │
│    Mecánico         ├────────┼────────┼────────┼────────┤
│                     │ 07:29  │        │ 05:34  │ 06:57  │
│                     │ (14... │        │ (14... │ (11... │
└─────────────────────┴────────┴────────┴────────┴────────┘
```

**Features:**
- ✅ Shows check-in + partial check-out
- ✅ 9px font size
- ✅ Truncated but readable
- ✅ ~30-31 days fit well

---

### 📅 Week View - MEDIUM (140px × 80px)
**Purpose:** Detailed weekly overview

```
Employee Row (80px tall)
┌─────────────────────┬──────────┬──────────┬──────────┐
│ 👤 Juan Pérez       │  Lun 29  │  Mar 30  │  Mié 1   │
│    Mecánico         ├──────────┼──────────┼──────────┤
│                     │  07:29   │  05:30   │  05:40   │
│                     │(19:25-...│(14:00-...│(13:53-...│
└─────────────────────┴──────────┴──────────┴──────────┘
```

**Features:**
- ✅ Full time range visible
- ✅ 10px font size
- ✅ Odoo-style format
- ✅ 7 days fit comfortably

---

### 📅 Year View - FULL DETAIL, VERTICAL STACKING (140px × 120px)
**Purpose:** See ALL attendance shifts for entire year with complete details

```
Employee Row (120px tall - TALLER for stacking)
┌─────────────────────┬──────────────┬──────────────┬──────────────┐
│ 👤 Juan Pérez       │    Lun 1     │    Mar 2     │    Mié 3     │
│    Mecánico         ├──────────────┼──────────────┼──────────────┤
│                     │ 07:29-12:30  │ 01:50-06:25  │ 05:34-14:30  │
│                     │    (5.0)     │    (4.6)     │    (8.9)     │
│                     │              │              │              │
│                     │ 14:00-19:25  │              │              │
│                     │    (5.4)     │              │              │
└─────────────────────┴──────────────┴──────────────┴──────────────┘
           ↑                    ↑
    Multiple shifts      Single shift
    stacked vertically   per day
```

**Features:**
- ✅ Shows EVERY individual shift (no aggregation)
- ✅ Full timestamps: `HH:mm-HH:mm (duration)`
- ✅ 10px font size
- ✅ Vertical stacking in Column widget
- ✅ Each block individually clickable
- ✅ Taller cells (120px) accommodate multiple shifts
- ✅ Perfect for annual review and analysis
- ✅ ~365 days total (horizontal scroll)

---

## Comparison: Quarter vs. Year

### Quarter View Philosophy
```
🎯 Goal: Overview - "Did they work?"
📊 Density: Maximum (90 days visible)
🔍 Detail: Minimum (just hour)
📱 Interaction: Click to see details
```

### Year View Philosophy
```
🎯 Goal: Analysis - "How much did they work?"
📊 Density: Medium (140px per day)
🔍 Detail: Maximum (all shifts, full times)
📱 Interaction: Direct visibility, no clicking needed
```

---

## When to Use Each View

### 📅 Day View
- ✅ Planning today's workforce
- ✅ Real-time attendance monitoring
- ✅ Kiosk check-in/out display

### 📅 Week View
- ✅ Weekly scheduling
- ✅ Comparing team members
- ✅ Detecting patterns

### 📅 Month View
- ✅ Monthly attendance reports
- ✅ Payroll preparation
- ✅ Absence tracking

### 📅 Quarter View
- ✅ Quarterly performance reviews
- ✅ Long-term pattern detection
- ✅ Quick presence verification
- ✅ "Did this person work in Q1?"

### 📅 Year View
- ✅ **Annual performance analysis**
- ✅ **Complete shift history**
- ✅ **Overtime calculation**
- ✅ **Audit trail**
- ✅ **Detailed reporting**
- ✅ "Show me ALL shifts this employee worked this year"

---

## Technical Implementation Notes

### Column Widget (Vertical Stacking)
```dart
Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: attendances.map((attendance) {
    // Each attendance becomes a separate widget
    return GestureDetector(
      onTap: () => showDetails(attendance),
      child: AttendanceBlock(...),
    );
  }).toList(),
)
```

### Responsive Cell Height
- Quarter: 50px (enough for "07")
- Month: 70px (enough for "07:29 (14...")
- Week: 80px (standard comfortable height)
- **Year: 120px** ← **TALLER** to fit multiple stacked blocks

### Responsive Content Display
```dart
if (_currentView == TimeView.quarter) {
  displayText = checkIn.substring(0, 2); // "07"
} else if (_currentView == TimeView.year) {
  displayText = '$checkIn-$checkOut ($duration)'; // Full detail
}
```

---

## Summary

| Aspect | Quarter View | Year View |
|--------|-------------|-----------|
| **Cell Width** | 50px (narrow) | 140px (wide) |
| **Cell Height** | 50px (compact) | 120px (tall) |
| **Content** | Hour only ("07") | Full shifts stacked |
| **Font Size** | 8px | 10px |
| **Aggregation** | None (shows individual) | None (shows ALL) |
| **Visibility** | ~90 days on screen | ~8-10 days on screen |
| **Scroll** | Minimal | More scrolling |
| **Use Case** | Quick overview | Detailed analysis |
| **Click Required** | Yes, to see details | No, all visible |

