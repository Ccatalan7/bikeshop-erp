# 🔧 Kiosk Mode Checkout Fix

## 🐛 Problem

When trying to check out (register exit) in kiosk mode, the app crashes with:
```
Error: TypeError: null: type 'Null' is not a subtype of type 'String'
```

## 🔍 Root Cause

The database function `get_checked_in_employees()` was missing the `attendance_id` field in its return value. The kiosk code needs this ID to call `checkOut()`, but the function only returned:
- `employee_id`
- `employee_name`
- `check_in`
- `hours_worked`

Without the `attendance_id`, the code tried to cast `null` as `String`, causing the crash.

## ✅ Solution

Updated the SQL function to include `attendance_id` in the returned columns:

```sql
create or replace function public.get_checked_in_employees()
returns table (
  attendance_id uuid,  -- ← ADDED
  employee_id uuid,
  employee_name text,
  check_in timestamp with time zone,
  hours_worked numeric
)
```

## 🚀 Deployment Steps

### 1. Update the Database

Run this SQL in your Supabase SQL Editor:

```sql
create or replace function public.get_checked_in_employees()
returns table (
  attendance_id uuid,
  employee_id uuid,
  employee_name text,
  check_in timestamp with time zone,
  hours_worked numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select 
    a.id as attendance_id,
    a.employee_id,
    e.first_name || ' ' || e.last_name as employee_name,
    a.check_in,
    round(extract(epoch from (now() - a.check_in)) / 3600.0, 2) as hours_worked
  from attendances a
  join employees e on e.id = a.employee_id
  where a.status = 'ongoing'
    and a.check_out is null
  order by a.check_in;
end;
$$;
```

**OR** deploy the entire updated schema:

```bash
# From project root
supabase db push
```

### 2. Restart the App

No code changes needed! Just hot restart your Flutter app to pick up the new function signature.

## 🧪 Testing

1. Open **Asistencias** module
2. Click on an employee to open Kiosk Mode (or navigate to `/hr/kiosk`)
3. Tap on an employee card to **check in** (Entrar)
4. You should see "Entrada registrada" with green checkmark
5. Tap the same employee again to **check out** (Salir)
6. You should see "Salida registrada" with blue icon
7. ✅ No more crashes!

## 📝 Technical Details

### Before
```dart
await hrService.checkOut(
  employeeRecord['attendance_id'] as String,  // ← null!
  location: 'Tienda',
);
```

### After
```dart
await hrService.checkOut(
  employeeRecord['attendance_id'] as String,  // ← now has UUID!
  location: 'Tienda',
);
```

The SQL function now correctly returns the attendance ID, so the cast succeeds.

## 🎯 Files Modified

- ✅ `supabase/sql/core_schema.sql` - Updated `get_checked_in_employees()` function

## ✨ Result

Kiosk mode now works perfectly for both check-in and check-out! 🎉

Perfect for employees clocking in/out at the bike shop! 🚴‍♂️⏰
