**Prompt for GitHub Copilot Chat Agent – Attendances Module Development (Odoo-like)**

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
You need to **develop a new module: Attendances (Asistencias)** replicating the functionality and design logic of **Odoo's Attendances App**.

Before developing this module, the agent must ensure that the HR foundation is properly structured. This includes:
- **Employees Section:** CRUD for employee data (name, position, ID, schedule, linked user, etc.).
- **Contracts Section:** For tracking employee contracts (start/end dates, salary, type, assigned hours, etc.).
- **Planning Section:** Optional but recommended for defining planned work schedules, which the attendance module can later compare with actual working times.

If any of these sections are not created yet, the agent should create them first.

---

### Module: Attendances (Asistencias)
The module should mimic the main logic of **Odoo’s Attendances module**, as shown in the reference screenshots.

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
   - **Day / Week / Month / Quarter / Year View** options (as shown in the screenshots).
   - Data visualization similar to Odoo's grid table: rows = employees, columns = days, and cells = colored time blocks showing worked hours.
   - Hover or click should show the exact timestamps.

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
   - Display attendance time blocks as colored cells or bars (similar to a Gantt-like chart but compact).
   - Each cell shows total worked hours, with hover details showing check-in and check-out times.

7. **Permissions and Roles:**
   - Admins and HR managers can view all employee records.
   - Employees can only see their own.

8. **Kiosk Mode (to be developed next):**
   - Important: The kiosk mode should behave as a separate sub-application.
   - When opened, it displays a full-screen list of all employees with their profile avatars and names.
   - Employees tap their name to check in/out.
   - A pop-up confirms the action (e.g., “Su entrada ha sido registrada”).
   - The mode should work in a touch-friendly layout.

   ⚠️ The kiosk mode will be addressed as the next subtask after the main Attendances module UI and backend are implemented.

---

### UI/UX Requirements
- Design must follow the same style as the current ERP (dark theme, clean, modern, responsive).
- Layout and interaction inspired by Odoo’s Attendances module (as per provided screenshots).
- The data grid must dynamically update based on the selected time range.
- Consider using Flutter widgets such as:
  - `DataTable` or custom grid for weekly/monthly view.
  - `DropdownButton`, `DateRangePicker`, and `SegmentedButton` for navigation.
  - `AlertDialog` or `SnackBar` for action confirmations.

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
> Build the Attendances module (Asistencias) fully integrated with HR, replicating Odoo’s functionality, layout, and logic. Ensure modularity so the kiosk mode can be implemented afterward as an extension of this system.

