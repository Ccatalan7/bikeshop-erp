**Historical prompt — Attendances module**

> [!WARNING]
> **Historical business context; not UI authority.** This document may explain
> original attendance behavior, data, and permissions. Every visual, layout,
> navigation, component, color, spacing, modal/dialog/snackbar, responsive, and
> platform recipe below is superseded by
> [`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md) and
> [`GUI_MOBILE_DESIGN_PRINCIPLES.md`](GUI_MOBILE_DESIGN_PRINCIPLES.md). Do not
> imitate a reference product or screenshot. Inspect the current real hosts and
> select inline, in-block, pane, popover, sheet, blocking surface, or full route
> from task evidence; none is an automatic module-wide pattern.

### Project Context
- **IDE:** Visual Studio Code  
- **Language:** Dart  
- **Framework:** Flutter  
- **Auth:** Supabase  
- **Database:** Supabase (PostgreSQL)  
- **Storage:** Supabase Bucket  
- **Country of Origin:** Chile  
- **Language:** Spanish  
- **App Type:** ERP specialized for bike shops (focused on MTB)  

### Current Modules
- Accounting (core base)  
- Clients  
- Inventory  
- Sales  
- Purchases  
- Point of Sale (POS)  
- Configuration  
- Human Resources (HR / RRHH)  
- Reports  
- Bikeshop Mechanic Work Management  

### Future Modules
- Website Integration  

### Task Objective
The original objective was to develop **Attendances (Asistencias)** with the
business capabilities listed below. Product composition and interaction must
be designed for the current ERP rather than copied from another application.

Before developing this module, the agent must ensure that the HR foundation is properly structured. This includes:
- **Employees Section:** CRUD for employee data (name, position, ID, schedule, linked user, etc.).
- **Contracts Section:** For tracking employee contracts (start/end dates, salary, type, assigned hours, etc.).
- **Planning Section:** Optional but recommended for defining planned work schedules, which the attendance module can later compare with actual working times.

If any of these sections are not created yet, the agent should create them first.

---

### Module: Attendances (Asistencias)
The module needs the following attendance capabilities. References in the
original prompt are behavioral context only.

#### Core Features to Implement
1. **Employee Time Tracking:**
   - Each employee can check in and check out, registering their entry and exit times.
   - Each record creates a timestamp in Supabase (PostgreSQL) with fields like:
     ```sql
     id, employee_id, check_in, check_out, worked_hours, date
     ```
   - When an employee checks in, the system starts counting their active work session in the background.
   - When they check out, the system calculates total worked hours.

2. **View Modes:**
   - **Day / Week / Month / Quarter / Year View** period options, subject to
     validation against the current operating workflow.
   - Provide a period comparison that makes employee/day worked time legible.
     The representation depends on the current task and viewport.
   - Exact timestamps must be available through pointer, keyboard, and touch
     paths; important information cannot depend on hover.

3. **Filters and Grouping:**
   - Filters by date, employee, or department.
   - Group by date range (week, month, etc.) and by employee.

4. **Buttons and Controls:**
   - Navigation buttons (← →) to move between periods.
   - Dropdown menu to switch between view modes (Día, Semana, Mes, Trimestre, Año).
   - Date range picker (“Desde / Para / Aplicar”).
   - “Nuevo” button to manually add or correct an attendance.

5. **Backend Logic:**
   - Create a Supabase table for attendances.
   - Define relationships with the Employees table.
   - When an employee checks in, save timestamp; when checks out, update record with worked_hours.
   - If check_out is null, employee is currently clocked in.

6. **Data Visualization:**
   - Display worked-time intervals and totals in a form suited to the selected
     period and platform.
   - State and duration must remain understandable without color alone, and
     exact check-in/check-out times must be reachable without hover.

7. **Permissions and Roles:**
   - Admins and HR managers can view all employee records.
   - Employees can only see their own.

8. **Kiosk Mode (to be developed next):**
   - Important: The kiosk mode should behave as a separate sub-application.
   - When opened, it displays a full-screen list of all employees with their profile avatars and names.
   - Employees tap their name to check in/out.
   - Give clear confirmation of the action through the shared feedback pattern
     appropriate to its scope; a centered pop-up is not prescribed.
   - The mode should work in a touch-friendly layout.

   ⚠️ The kiosk mode will be addressed as the next subtask after the main Attendances module UI and backend are implemented.

---

### UI/UX Requirements
- Follow both canonical GUI guides linked in the warning above. The result must
  be contemporary, professional, visually considered, and deliberately
  composed for each supported viewport and input mode.
- The data grid must dynamically update based on the selected time range.
- Choose the representation and interaction surface from the operating task.
  Long comparisons may justify a grid; narrow or touch hosts may require a
  dedicated composition. No Flutter widget or transient surface is mandatory
  merely because it appeared in this historical prompt.

---

### Integration Notes
- Data must be stored and retrieved through Supabase using its Dart client.
- Global constants for database references (e.g., `attendances`, `employees`, `contracts`).
- All timestamps in UTC or converted to local time for display.
- Sync with HR and Reports modules.
- Hardcode initial test data for employees and sample attendances for development.

---

### Deliverables
1. **Supabase Table Schemas** for employees, contracts, and attendances.
2. **Flutter UI** for Attendances view with all the filters, navigation, and data visualization.
3. **Attendance logic** for registering check-in/check-out.
4. **Link to HR module** to fetch employees.
5. **Preparations for kiosk mode** as next phase.

---

### Goal for this Task
> Build Attendances (Asistencias) fully integrated with HR, preserving the
> required business behavior while following the current canonical UI and
> platform guidance. Keep the architecture modular so kiosk mode can be added
> as a distinct touch workflow.
