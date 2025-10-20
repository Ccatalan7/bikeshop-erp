# 📊 Asistencias - Responsive Cell Sizing (Odoo-style)

## Overview

The Asistencias module's attendance grid now adapts its cell sizes and content display based on the selected time view, matching Odoo's behavior exactly.

## Changes Made

### 1. **Dynamic Cell Sizing**

Added two new methods that calculate cell dimensions based on the current view:

- `_getCellWidth()`: Returns appropriate width for each view mode
- `_getCellHeight()`: Returns appropriate height for each view mode

**Cell Dimensions by View:**

| View Mode | Cell Width | Cell Height | Purpose |
|-----------|-----------|-------------|---------|
| Day       | 200px     | 100px       | Wide and tall - shows detailed time info |
| Week      | 140px     | 80px        | Medium - shows full time ranges |
| Month     | 100px     | 70px        | Medium-compact - shows truncated times |
| Quarter   | 50px      | 50px        | **VERY NARROW** - minimal info, clickable |
| Year      | 140px     | 120px       | **Wide and tall** - shows ALL shifts stacked vertically |

### 2. **Adaptive Header Labels**

The grid header now shows contextual labels:

- **All views**: "Días" (showing individual days)

### 3. **Responsive Header Content**

The day headers adapt their content based on the view:

**Quarter View:**
- Shows ONLY day numbers (1, 2, 3...)
- Very compact font size (10px)
- Center aligned
- No day names

**Month View:**
- Shows only day numbers (1, 2, 3...)
- Medium font size (14px)
- No day names

**Week/Day/Year View:**
- Shows day name + day number (Lun 15, Mar 16...)
- Full layout with larger fonts
- Two-line display

### 4. **Smart Attendance Block Display**

The attendance time blocks adapt their content to fit the available space:

#### **Quarter View (50px × 50px cells) - ULTRA COMPACT**
- Shows **ONLY the hour** (e.g., "07")
- Minimal padding and margins
- Font size: 8px, ultra-compact
- Clickable to see full details in dialog
- Purpose: Fit 3 months of data horizontally with scrolling

#### **Month View (100px × 70px cells) - COMPACT**
- Shows **truncated time ranges** (e.g., "07:29 (14...")
- Format: `HH:mm (HH...` (check-in with partial check-out)
- Font size: 9px
- Multiple blocks for multiple attendances per day

#### **Week View (140px × 80px cells) - MEDIUM**
- Shows **full time ranges** (e.g., "07:29 (19:25-...")
- Format: `HH:mm (HH:mm-...` (Odoo-style)
- Font size: 10px
- Clear start and end times

#### **Year View (140px × 120px cells) - FULL DETAIL, VERTICAL STACKING**
- Shows **ALL SHIFTS with complete information**
- Format: `HH:mm-HH:mm (H:mm)` (full times + duration)
- Font size: 10px
- **ALL attendance blocks stacked VERTICALLY** within the cell
- Taller cells (120px) to accommodate multiple shifts
- Each shift is clickable individually
- Example: A day with 2 shifts shows:
  ```
  07:29-12:30 (5.0)
  14:00-19:25 (5.4)
  ```

#### **Day View (200px × 100px cells) - MAXIMUM DETAIL**
- Shows **complete information** (e.g., "07:29-19:25 (12:0)")
- Format: `HH:mm-HH:mm (H:mm)` (full times + duration)
- Font size: 11px
- Maximum detail and spacing

### 5. **Year View - Vertical Shift Stacking**

For the year view, the system now displays ALL attendance shifts for each day:

1. **No aggregation** - Each shift is shown individually
2. **Vertical stacking** - Multiple shifts per day stack vertically within a taller cell (120px)
3. **Full details** - Each shift shows complete start time, end time, and duration
4. **Individual interaction** - Each shift block is clickable to view/edit details
5. **Scrollable content** - If a day has many shifts, the cell content can scroll

This allows users to see the complete picture of all attendances across the entire year while maintaining individual shift visibility.

### 6. **Quarter View - Maximum Compression**

The quarter view prioritizes fitting 3 months of data horizontally:

1. **Minimal cell width** (50px) - Allows ~90 days to fit on screen
2. **Just the hour** - Shows only "07", "14", etc. (no minutes, no duration)
3. **Clickable blocks** - Users can click any block to see full details in dialog
4. **Horizontal scrolling** - Natural scrolling to see all 90 days
5. **Color-coded status** - Maintains green/red/gray status indicators

### 7. **Color-Coded Status**

All views maintain the status color coding:

- **Green block** = Ongoing attendance (in progress)
- **Light green** = Approved attendance
- **Red block** = Rejected attendance  
- **Gray block** = Pending approval

### 8. **Responsive Employee Row Height**

Employee name rows now adapt to match cell height:

- **Day view**: 100px (shows avatar + name + job title clearly)
- **Week view**: 80px (standard height)
- **Month view**: 70px (medium)
- **Quarter view**: 50px (compact)
- **Year view**: 120px (tall to accommodate vertically stacked shifts)

## Visual Behavior

### Week View (140px × 80px)
```
┌──────────┬──────────┬──────────┐
│ Lun 29   │ Mar 30   │ Mié 1    │
├──────────┼──────────┼──────────┤
│ 07:29    │ 05:30    │ 05:40    │
│ (19:25-..│ (14:00-..│ (13:53-..│
└──────────┴──────────┴──────────┘
```

### Month View (100px × 70px)
```
┌────────┬────────┬────────┬────────┐
│   1    │   2    │   3    │   4    │
├────────┼────────┼────────┼────────┤
│ 07:29  │ 01:50  │ 05:34  │ 06:57  │
│ (14... │ (19... │ (14... │ (11... │
└────────┴────────┴────────┴────────┘
```

### Quarter View (50px × 50px) - ULTRA COMPACT
```
┌───┬───┬───┬───┬───┐
│ 1 │ 2 │ 3 │ 4 │ 5 │
├───┼───┼───┼───┼───┤
│07 │01 │05 │06 │   │
└───┴───┴───┴───┴───┘
(Click to see full details)
```

### Year View (140px × 120px) - VERTICAL STACKING
```
┌──────────────┬──────────────┬──────────────┐
│    Lun 1     │    Mar 2     │    Mié 3     │
├──────────────┼──────────────┼──────────────┤
│ 07:29-12:30  │ 01:50-06:25  │ 05:34-14:30  │
│    (5.0)     │    (4.6)     │    (8.9)     │
│              │              │              │
│ 14:00-19:25  │              │              │
│    (5.4)     │              │              │
└──────────────┴──────────────┴──────────────┘
(All shifts visible, stacked vertically)
```

## Technical Implementation

### Key Methods Updated:

1. **`_getCellWidth()`** - Returns dynamic width based on `_currentView`
   - Quarter: 50px (ultra narrow for horizontal scrolling)
   - Year: 140px (wide to fit stacked shifts)
   
2. **`_getCellHeight()`** - Returns dynamic height based on `_currentView`
   - Quarter: 50px (compact)
   - Year: 120px (tall for vertical stacking)
   
3. **`_buildGridHeader()`** - Uses dynamic height, shows "Días" for all views

4. **`_buildDayHeader()`** - Adapts header content:
   - Quarter: Just day number (10px font)
   - Month: Day number (14px font)
   - Week/Day/Year: Day name + number (full layout)
   
5. **`_buildEmployeeRow()`** - Uses dynamic cell height

6. **`_buildAttendanceCell()`** - Gets attendances for specific day (no aggregation)

7. **`_getDaysInRange()`** - Returns all days in range for ALL views

8. **`_buildAttendanceBlocks()`** - Adaptive display logic:
   - **Quarter**: Shows only hour "07" (8px font, minimal padding)
   - **Month**: Shows `HH:mm (HH...` (9px font)
   - **Week**: Shows `HH:mm (HH:mm-...` (10px font)
   - **Year**: Shows `HH:mm-HH:mm (H:mm)` - FULL DETAILS (10px font)
   - All blocks stacked vertically in Column widget

### Responsive Font Sizes:

- **Quarter view**: 8px (ultra compact - just hour)
- **Month view**: 9px (compact - truncated time)
- **Week view**: 10px (medium - full time range)
- **Year view**: 10px (full details, stacked vertically)
- **Day view**: 11px (maximum detail)

### Responsive Padding:

- **Quarter view**: 2px horizontal, 1px vertical (minimal)
- **Month view**: 4px horizontal, 3px vertical (compact)
- **Week view**: 6px horizontal, 4px vertical (standard)
- **Year view**: 6px horizontal, 3px vertical (balanced for stacking)
- **Day view**: 6px horizontal, 4px vertical (comfortable)

## User Experience

### Smooth Transitions
When switching between views, users will see:

1. **Cells resize smoothly** (no jumpy layout)
2. **Content adapts intelligently** (more detail = wider cells)
3. **Scrolling behavior adjusts** (horizontal scroll enabled for all views)
4. **Information density scales** (more time periods visible in narrower views)

### Horizontal Scrolling
- **Quarter**: Very narrow 50px cells allow ~90 days visible with scrolling
- **Month**: 100px cells for comfortable month navigation
- **Week**: 140px cells for detailed week view
- **Year**: 140px cells with taller height to show all shifts - fits entire year horizontally (~5,100px total width for 365 days)

### Key User Benefits

#### Quarter View:
- ✅ See 3 months of data at a glance
- ✅ Quick overview of attendance patterns
- ✅ Click any block to see full details
- ✅ Minimal horizontal scrolling needed

#### Year View:
- ✅ See ALL attendance shifts for the entire year
- ✅ Each shift individually visible and clickable
- ✅ Full timestamps and durations shown
- ✅ No data loss - everything is accessible
- ✅ Vertical stacking prevents cell overflow
- ✅ Taller cells (120px) provide comfortable spacing

## Testing

To verify the responsive behavior:

1. ✅ **Switch to Week view** → Cells should be 140px wide, showing "07:29 (19:25-..."
2. ✅ **Switch to Month view** → Cells should be 100px wide, showing "07:29 (14..."
3. ✅ **Switch to Quarter view** → Cells should shrink to 50px, showing ONLY "07" (ultra compact)
4. ✅ **Switch to Year view** → Cells should be 140px wide × 120px tall, showing ALL shifts stacked vertically
5. ✅ **Check employee row heights** → Should match cell heights (100→80→70→50→120px)
6. ✅ **Verify day headers in quarter view** → Should show only numbers "1, 2, 3..." (10px font)
7. ✅ **Verify year view stacking** → Multiple shifts should appear stacked, not truncated
8. ✅ **Test horizontal scrolling** → Should work smoothly in all views
9. ✅ **Test clickability in quarter view** → Even tiny blocks should be clickable
10. ✅ **Check tooltip on hover** → Full info should appear regardless of view

## Notes

- The implementation follows Odoo's exact sizing strategy
- **Quarter view** optimized for maximum horizontal density (50px cells)
- **Year view** optimized for maximum vertical detail (120px tall cells)
- Font sizes automatically scale to prevent text overflow
- All tooltip information remains available regardless of view
- Status colors are preserved across all views
- The design is mobile-friendly (horizontal scrolling works on touch devices)
- Year view shows ALL individual shifts (no aggregation/summarization)
- Each shift block is individually interactive (click to edit/view details)

## Key Differences from Initial Implementation

### What Changed:
1. ✅ **Quarter view**: Changed from 80px to **50px** (ultra compact)
2. ✅ **Year view**: Changed from 50px to **140px** width (wider for details)
3. ✅ **Year view**: Changed from 50px to **120px** height (taller for stacking)
4. ✅ **Year view**: No longer aggregates - shows ALL individual shifts
5. ✅ **Quarter view**: Shows only hour digits (e.g., "07") instead of full time
6. ✅ **Header labels**: All views show "Días" (not "Meses")
7. ✅ **Date range**: All views return daily dates (not monthly for year view)

### Design Philosophy:
- **Quarter view** = Maximum compression for overview
- **Year view** = Maximum detail for analysis
- **Week/Month** = Balanced middle ground
- **Day view** = Maximum spacing and comfort

## Future Enhancements

Potential improvements:
- [ ] Add smooth animated transitions between view modes
- [ ] Add pinch-to-zoom gesture support for mobile
- [ ] Add "Fit to screen" option that auto-calculates optimal cell size
- [ ] Add print-friendly view with optimized cell sizes
- [ ] Add export to Excel with view-specific formatting
