# Smart Task System - Quick Reference

## 📋 What It Does

Automatic to-do list for mechanics working on pegas (mechanic jobs). Tasks auto-create when parts/services are added and sync with pega statuses.

## 🚀 Key Features

- ✅ **Auto-creates tasks** when parts or services added to pega
- ✅ **Syncs with pega status** (EN_CURSO, FINALIZADO, CANCELADO)
- ✅ **Tracks progress** (pending, in_progress, completed)
- ✅ **Multi-tenant safe** (complete data isolation)

## 📊 Database

### Table: `mechanic_job_tasks`

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid | Primary key |
| `tenant_id` | uuid | Tenant (multi-tenant) |
| `job_id` | uuid | Links to mechanic_jobs |
| `job_item_id` | uuid | Links to part (if auto-generated from part) |
| `job_labor_id` | uuid | Links to service (if auto-generated from service) |
| `task_type` | text | diagnostic, install_part, perform_service, etc. |
| `title` | text | Task title |
| `description` | text | Task description |
| `status` | text | pending, in_progress, completed, skipped, blocked |
| `priority` | text | urgent, high, normal, low |
| `is_auto_generated` | boolean | True if auto-created |
| `display_order` | integer | Sort order |

### Triggers

1. **`trg_auto_create_task_for_item`** → Creates task when part added
2. **`trg_auto_create_task_for_labor`** → Creates task when service added  
3. **`trg_sync_tasks_with_job_status`** → Updates tasks when pega status changes

### RPC Function

```sql
SELECT get_job_task_summary('job-id');
-- Returns: { total_tasks, completed, in_progress, pending, blocked, completion_percentage }
```

## 🎯 Status Flow

| Pega Status | Task Behavior |
|-------------|---------------|
| `PENDIENTE` | Tasks stay `pending` |
| `EN_CURSO` | First pending task → `in_progress` |
| `FINALIZADO` | All tasks → `completed` |
| `CANCELADO` | All tasks → `skipped` |

## 💻 Flutter Usage

### Load Tasks

```dart
final taskService = context.read<MechanicJobTaskService>();
await taskService.loadTasksForJob(pegaId);
```

### Display Tasks

```dart
Consumer<MechanicJobTaskService>(
  builder: (context, service, child) {
    return ListView.builder(
      itemCount: service.tasks.length,
      itemBuilder: (context, index) {
        final task = service.tasks[index];
        return ListTile(
          title: Text(task.title),
          subtitle: Text(task.status.displayName),
          leading: Checkbox(
            value: task.status == TaskStatus.completed,
            onChanged: (checked) {
              service.updateTaskStatus(
                task.id,
                checked ? TaskStatus.completed : TaskStatus.pending,
              );
            },
          ),
        );
      },
    );
  },
)
```

### Create Manual Task

```dart
await taskService.createTask(
  jobId: pegaId,
  taskType: TaskType.qualityCheck,
  title: 'Revisión final',
  priority: TaskPriority.high,
);
```

### Update Task Status

```dart
await taskService.updateTaskStatus(taskId, TaskStatus.completed);
```

### Get Summary

```dart
final summary = await taskService.getTaskSummary(jobId);
print('Progress: ${summary.completionPercentage}%');
print('Completed: ${summary.completed} / ${summary.totalTasks}');
```

## 🎨 UI Patterns

### Progress Bar

```dart
LinearProgressIndicator(
  value: summary.completionPercentage / 100,
)
Text('${summary.completed} de ${summary.totalTasks} completadas')
```

### Status Badge

```dart
Icon(
  task.status == TaskStatus.completed ? Icons.check_circle : Icons.schedule,
  color: task.status == TaskStatus.completed ? Colors.green : Colors.grey,
)
```

### Priority Chip

```dart
Container(
  padding: EdgeInsets.all(4),
  decoration: BoxDecoration(
    color: task.priority == TaskPriority.urgent ? Colors.red : Colors.grey,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(task.priority.displayName),
)
```

## 📂 Files

| File | Purpose |
|------|---------|
| `DEPLOY_SMART_TASK_SYSTEM.sql` | SQL deployment script |
| `SMART_TASK_SYSTEM_GUIDE.md` | Full documentation |
| `lib/modules/bikeshop/models/mechanic_job_task.dart` | Dart model |
| `lib/modules/bikeshop/services/mechanic_job_task_service.dart` | Dart service |

## 🧪 Testing

```sql
-- Add part → check task created
INSERT INTO mechanic_job_items (tenant_id, job_id, product_name, quantity, unit_price, total_price)
VALUES ('tenant-id', 'job-id', 'Test Part', 1, 10000, 10000);

SELECT * FROM mechanic_job_tasks WHERE job_id = 'job-id';

-- Change status → check tasks synced
UPDATE mechanic_jobs SET status = 'FINALIZADO' WHERE id = 'job-id';

SELECT status FROM mechanic_job_tasks WHERE job_id = 'job-id';
-- All should be 'completed'
```

## ✅ Deployment Checklist

- [ ] Run `DEPLOY_SMART_TASK_SYSTEM.sql` in Supabase
- [ ] Verify table created: `SELECT * FROM mechanic_job_tasks LIMIT 1;`
- [ ] Verify triggers exist: `SELECT tgname FROM pg_trigger WHERE tgname LIKE '%task%';`
- [ ] Add Flutter models to project
- [ ] Add Flutter service to project
- [ ] Register service in `main.dart` providers
- [ ] Add task UI to pega detail page
- [ ] Test with real pega (add part, check task created)
- [ ] Test status sync (change pega status, check tasks updated)

## 🎯 Common Operations

| Operation | Method |
|-----------|--------|
| Load tasks | `taskService.loadTasksForJob(jobId)` |
| Create task | `taskService.createTask(...)` |
| Complete task | `taskService.updateTaskStatus(taskId, TaskStatus.completed)` |
| Assign task | `taskService.assignTask(taskId, assignedTo: userId, technicianName: 'Juan')` |
| Update priority | `taskService.updateTaskPriority(taskId, TaskPriority.high)` |
| Delete task | `taskService.deleteTask(taskId)` |
| Reorder tasks | `taskService.reorderTasks(reorderedList)` |
| Get summary | `taskService.getTaskSummary(jobId)` |
| Get pending | `taskService.pendingTasks` |
| Get completed | `taskService.completedTasks` |

## 🎁 Auto-Generated Task Examples

When mechanic adds:
- **Part**: "Pastillas de Freno" → Task: "Instalar: Pastillas de Freno"
- **Service**: "Ajuste de cambios (2h)" → Task: "Ajuste de cambios (2.0 horas estimadas)"

## 🔒 Security

- ✅ RLS enabled on `mechanic_job_tasks`
- ✅ All operations filtered by `tenant_id`
- ✅ Only authenticated users can access
- ✅ Tasks auto-inherit tenant_id from parent job

## 📞 Support

Check database logs, Flutter console, verify RLS policies working.

---

**Quick Deploy:** Copy `DEPLOY_SMART_TASK_SYSTEM.sql` → Supabase SQL Editor → Run
**Quick Test:** Add part to pega → Check `mechanic_job_tasks` table
