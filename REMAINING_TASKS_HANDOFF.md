# Remaining Tasks for Smart Tasks Module

The implementation of the Smart Tasks ("Tareas") module has completed its foundational UI and database layers, including the migrations, services, and the `TaskFormDialog` creation shortcuts embedded across Jobs, Purchase Invoices, and Sales Invoices.

There are several pending tasks to make the module fully functional and interactive from the newly created list view. Here is the handoff of the remaining work to be completed:

## 1. Task Interaction in `PegasTasksWidget`
**File:** `lib/modules/bikeshop/widgets/pegas_tasks_widget.dart`

- **Task Details/Edit (TODO around line 171):**
  Implement the `onTap` handler on the task card to open the `TaskFormDialog` in edit mode. 
  *Context:* Change the empty `onTap` to pass the task to `TaskFormDialog(taskToEdit: task)` so users can edit the details.

- **Toggle Status (TODO around line 183):**
  Implement the `onTap` handler on the task checkbox to quickly toggle a task's status between `pending` (or `inProgress`) and `completed`. This should call `context.read<TaskService>().updateTask()` with the modified status.

## 2. Contextual Badge Navigation
**File:** `lib/modules/bikeshop/widgets/pegas_tasks_widget.dart`

Currently, `_buildLinkBadge` (around line 327) renders a static container for tasks linked to Jobs, Purchase Invoices, or Sales Invoices.
- Wrap this badge in an `InkWell` or similar tappable widget.
- Implement routing logic using `GoRouter` so that tapping the badge navigates the user directly to the associated entity:
  - Jobs `linkedJobNumber` -> Job dashboard / editor
  - Purchase `linkedPurchaseInvoiceId` -> `/purchases/invoices/{id}`
  - Sales `linkedSalesInvoiceId` -> `/sales/invoices/{id}`

## 3. Task Assignment User List
**File:** `lib/modules/bikeshop/widgets/task_form_dialog.dart`

Currently, task assignment (`assignedTo`) needs to be fully wired up to select real system users.
- Update `TaskFormDialog` to interact with `UserManagementService`.
- Fetch the list of active users/employees in the tenant.
- Render a `DropdownButtonFormField` that allows the creator to select a specific user from the system to populate the `assignedTo` UUID field gracefully.

## 4. Notification / UI Polish
- Ensure the `TaskService` correctly triggers UI rebuilds for the `PegasTasksWidget` after mutations (e.g., status toggle or edit save).
- Check the remaining `flutter analyze` lints to resolve the `deprecated_member_use` warnings introduced by `withOpacity` vs `withValues` in your modifications if any still linger.
