# Smart Task System for Mechanic Jobs (Pegas)

## Overview

The Smart Task System provides a dynamic to-do list for mechanics working on pegas (mechanic jobs). Tasks are automatically created when parts or services are added to a pega, and they sync with pega statuses to provide real-time workflow tracking.

## Key Features

### ✅ Automatic Task Generation
- When a mechanic adds a **part/product** (`mechanic_job_items`), a task is auto-created:
  - **Type**: `install_part`
  - **Title**: "Instalar: [Product Name]"
  - **Description**: Includes quantity and notes
  - **Status**: `pending`

- When a mechanic adds **labor/service** (`mechanic_job_labor`), a task is auto-created:
  - **Type**: `perform_service`
  - **Title**: Service description
  - **Description**: Includes estimated hours
  - **Status**: `pending`
  - **Assigned to**: Technician from labor record

### 🔄 Automatic Status Sync with Pega

Tasks automatically update based on pega status changes:

| Pega Status | Task Behavior |
|-------------|---------------|
| **EN_CURSO** (In Progress) | First `pending` task → `in_progress` |
| **FINALIZADO** (Completed) | All `pending`/`in_progress` tasks → `completed` |
| **CANCELADO** (Cancelled) | All active tasks → `skipped` |

### 📋 Task Types

1. **`diagnostic`** - Diagnose issue
2. **`install_part`** - Install a specific part (auto-generated)
3. **`perform_service`** - Perform service work (auto-generated)
4. **`quality_check`** - Quality control check
5. **`test_ride`** - Test bike after repair
6. **`cleanup`** - Clean/polish bike
7. **`general`** - General task

### 🚦 Task Statuses

1. **`pending`** - Not started yet
2. **`in_progress`** - Currently working on it
3. **`completed`** - Task finished
4. **`skipped`** - Skipped (not needed)
5. **`blocked`** - Waiting for something (parts, approval)

### ⚡ Task Priorities

1. **`urgent`** - Urgente
2. **`high`** - Alta
3. **`normal`** - Normal (default)
4. **`low`** - Baja

## Database Schema

### Table: `mechanic_job_tasks`

```sql
create table mechanic_job_tasks (
  id uuid primary key,
  tenant_id uuid not null references tenants(id),
  job_id uuid not null references mechanic_jobs(id) on delete cascade,
  
  -- Links to specific item/labor (optional)
  job_item_id uuid references mechanic_job_items(id) on delete cascade,
  job_labor_id uuid references mechanic_job_labor(id) on delete cascade,
  
  -- Task details
  task_type text not null,
  title text not null,
  description text,
  status text not null default 'pending',
  priority text not null default 'normal',
  
  -- Assignment
  assigned_to uuid references customers(id),
  assigned_technician_name text,
  
  -- Timing
  estimated_duration_minutes integer,
  actual_duration_minutes integer,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  
  -- Metadata
  is_auto_generated boolean not null default false,
  completed_by uuid,
  completed_by_name text,
  notes text,
  display_order integer not null default 0,
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
```

### Triggers

1. **`trg_auto_create_task_for_item`** - Auto-creates task when part is added
2. **`trg_auto_create_task_for_labor`** - Auto-creates task when service is added
3. **`trg_sync_tasks_with_job_status`** - Syncs task statuses with pega status changes

### RPC Function

**`get_job_task_summary(p_job_id uuid)`** - Returns task statistics:

```json
{
  "total_tasks": 5,
  "completed": 2,
  "in_progress": 1,
  "pending": 2,
  "blocked": 0,
  "completion_percentage": 40.00
}
```

## Flutter Integration

### Models

**Location:** `lib/modules/bikeshop/models/mechanic_job_task.dart`

```dart
// Enums
enum TaskType { diagnostic, installPart, performService, ... }
enum TaskStatus { pending, inProgress, completed, skipped, blocked }
enum TaskPriority { urgent, high, normal, low }

// Main model
class MechanicJobTask {
  final String id;
  final String jobId;
  final TaskType taskType;
  final String title;
  final TaskStatus status;
  final TaskPriority priority;
  // ... other fields
}

// Summary statistics
class TaskSummary {
  final int totalTasks;
  final int completed;
  final double completionPercentage;
  // ...
}
```

### Service

**Location:** `lib/modules/bikeshop/services/mechanic_job_task_service.dart`

```dart
class MechanicJobTaskService extends ChangeNotifier {
  // Load tasks for a job
  Future<void> loadTasksForJob(String jobId);
  
  // Get task summary
  Future<TaskSummary> getTaskSummary(String jobId);
  
  // Create manual task
  Future<MechanicJobTask?> createTask({
    required String jobId,
    required TaskType taskType,
    required String title,
    // ...
  });
  
  // Update task status
  Future<bool> updateTaskStatus(String taskId, TaskStatus newStatus);
  
  // Update priority
  Future<bool> updateTaskPriority(String taskId, TaskPriority newPriority);
  
  // Assign task
  Future<bool> assignTask(String taskId, {String? assignedTo, String? technicianName});
  
  // Delete task
  Future<bool> deleteTask(String taskId);
  
  // Reorder tasks
  Future<bool> reorderTasks(List<MechanicJobTask> reorderedTasks);
  
  // Getters
  List<MechanicJobTask> get tasks;
  List<MechanicJobTask> get pendingTasks;
  List<MechanicJobTask> get completedTasks;
  TaskSummary? get currentSummary;
}
```

## Usage Examples

### 1. Display Tasks in Pega Detail View

```dart
class PegaDetailPage extends StatefulWidget {
  final String jobId;
  // ...
}

class _PegaDetailPageState extends State<PegaDetailPage> {
  late MechanicJobTaskService _taskService;
  
  @override
  void initState() {
    super.initState();
    _taskService = context.read<MechanicJobTaskService>();
    _taskService.loadTasksForJob(widget.jobId);
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<MechanicJobTaskService>(
      builder: (context, service, child) {
        if (service.isLoading) {
          return CircularProgressIndicator();
        }
        
        // Show task summary
        final summary = service.currentSummary;
        if (summary != null) {
          return Column(
            children: [
              Text('Progreso: ${summary.completionPercentage.toStringAsFixed(0)}%'),
              LinearProgressIndicator(
                value: summary.completionPercentage / 100,
              ),
              Text('${summary.completed} de ${summary.totalTasks} completadas'),
            ],
          );
        }
        
        // Show task list
        return ListView.builder(
          itemCount: service.tasks.length,
          itemBuilder: (context, index) {
            final task = service.tasks[index];
            return TaskTile(
              task: task,
              onStatusChanged: (newStatus) {
                service.updateTaskStatus(task.id, newStatus);
              },
            );
          },
        );
      },
    );
  }
}
```

### 2. Task Tile Widget

```dart
class TaskTile extends StatelessWidget {
  final MechanicJobTask task;
  final ValueChanged<TaskStatus>? onStatusChanged;
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: task.status == TaskStatus.completed,
        onChanged: (checked) {
          if (checked != null) {
            onStatusChanged?.call(
              checked ? TaskStatus.completed : TaskStatus.pending,
            );
          }
        },
      ),
      title: Text(task.title),
      subtitle: Text(task.description ?? ''),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Priority indicator
          _buildPriorityChip(task.priority),
          
          // Status badge
          _buildStatusBadge(task.status),
          
          // Duration
          if (task.estimatedDurationMinutes != null)
            Text(task.estimatedDurationFormatted),
        ],
      ),
    );
  }
  
  Widget _buildPriorityChip(TaskPriority priority) {
    final color = switch (priority) {
      TaskPriority.urgent => Colors.red,
      TaskPriority.high => Colors.orange,
      TaskPriority.normal => Colors.blue,
      TaskPriority.low => Colors.grey,
    };
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        priority.displayName,
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
  
  Widget _buildStatusBadge(TaskStatus status) {
    final icon = switch (status) {
      TaskStatus.pending => Icons.schedule,
      TaskStatus.inProgress => Icons.sync,
      TaskStatus.completed => Icons.check_circle,
      TaskStatus.skipped => Icons.skip_next,
      TaskStatus.blocked => Icons.block,
    };
    
    final color = switch (status) {
      TaskStatus.pending => Colors.grey,
      TaskStatus.inProgress => Colors.blue,
      TaskStatus.completed => Colors.green,
      TaskStatus.skipped => Colors.orange,
      TaskStatus.blocked => Colors.red,
    };
    
    return Icon(icon, color: color, size: 20);
  }
}
```

### 3. Create Manual Task

```dart
// Add a quality check task
await _taskService.createTask(
  jobId: pegaId,
  taskType: TaskType.qualityCheck,
  title: 'Revisión final de frenos',
  description: 'Verificar que los frenos funcionen correctamente después de cambio de pastillas',
  priority: TaskPriority.high,
  estimatedDurationMinutes: 15,
);
```

### 4. Update Task Status

```dart
// Mark task as in progress
await _taskService.updateTaskStatus(
  taskId,
  TaskStatus.inProgress,
);

// Complete task
await _taskService.updateTaskStatus(
  taskId,
  TaskStatus.completed,
  completedByName: 'Juan Pérez',
);
```

### 5. Get Task Summary

```dart
final summary = await _taskService.getTaskSummary(jobId);

print('Total tasks: ${summary.totalTasks}');
print('Completed: ${summary.completed}');
print('Progress: ${summary.completionPercentage}%');
```

## Workflow Example

### Scenario: Mechanic working on a pega

1. **Mechanic opens pega "PG-00123"**
   - Status: `PENDIENTE`
   - No tasks yet

2. **Mechanic adds parts:**
   - Adds "Pastillas de Freno" (qty: 2)
   - **AUTO-CREATES TASK**: "Instalar: Pastillas de Freno" (status: `pending`)
   
   - Adds "Cable de Cambio" (qty: 1)
   - **AUTO-CREATES TASK**: "Instalar: Cable de Cambio" (status: `pending`)

3. **Mechanic adds services:**
   - Adds "Ajuste de frenos" (2 hours)
   - **AUTO-CREATES TASK**: "Ajuste de frenos" (status: `pending`, assigned to technician)

4. **Mechanic starts work:**
   - Changes pega status to `EN_CURSO`
   - **AUTO-UPDATES**: First pending task → `in_progress`
   - Task: "Instalar: Pastillas de Freno" now shows as `in_progress`

5. **Mechanic completes first task:**
   - Marks "Instalar: Pastillas de Freno" as `completed`
   - Manually starts "Instalar: Cable de Cambio" → `in_progress`

6. **Mechanic finishes all work:**
   - Changes pega status to `FINALIZADO`
   - **AUTO-UPDATES**: All remaining tasks → `completed`
   - Summary shows: 100% completion

7. **Pega delivered:**
   - Status: `ENTREGADO`
   - All tasks remain `completed` for record-keeping

## Multi-Tenant Support

✅ **Full tenant isolation:**
- All tasks linked to `tenant_id`
- RLS policies enforce tenant boundaries
- Auto-generated tasks inherit tenant_id from parent job
- Manual tasks get tenant_id from authenticated user

## Benefits

1. **Clear Workflow** - Mechanics see exactly what needs to be done
2. **Progress Tracking** - Real-time completion percentage
3. **Accountability** - Track who completed each task and when
4. **Automated** - Tasks auto-created from parts/services
5. **Flexible** - Add manual tasks for quality checks, test rides, etc.
6. **Synchronized** - Tasks sync with pega statuses automatically
7. **Multi-Tenant Safe** - Complete data isolation per tenant

## Deployment

### Step 1: Deploy Database Schema

Copy and run `DEPLOY_SMART_TASK_SYSTEM.sql` in Supabase SQL Editor.

This will create:
- `mechanic_job_tasks` table
- Auto-generation triggers
- Status sync trigger
- Task summary RPC function
- RLS policies

### Step 2: Add to Flutter App

Files already created:
- ✅ Model: `lib/modules/bikeshop/models/mechanic_job_task.dart`
- ✅ Service: `lib/modules/bikeshop/services/mechanic_job_task_service.dart`

### Step 3: Register Service

In `main.dart` or providers setup:

```dart
MultiProvider(
  providers: [
    // ... existing providers
    ChangeNotifierProvider(create: (_) => MechanicJobTaskService()),
  ],
  // ...
)
```

### Step 4: Add Tasks UI to Pega Detail View

Integrate task list widget into existing pega detail page.

## Testing

### Manual Testing Checklist

- [ ] Add part to pega → task auto-created
- [ ] Add service to pega → task auto-created
- [ ] Change pega to EN_CURSO → first task becomes in_progress
- [ ] Complete task manually → status updates correctly
- [ ] Change pega to FINALIZADO → all tasks completed
- [ ] Change pega to CANCELADO → all tasks skipped
- [ ] Create manual task → appears in list
- [ ] Delete manual task → removed from list
- [ ] Reorder tasks → order persists
- [ ] Get task summary → shows correct statistics
- [ ] Multi-tenant test → tasks isolated per tenant

### SQL Testing

```sql
-- Test task auto-creation
INSERT INTO mechanic_job_items (tenant_id, job_id, product_name, quantity, unit_price, total_price)
VALUES ('your-tenant-id', 'your-job-id', 'Test Part', 1, 10000, 10000);

-- Check task was created
SELECT * FROM mechanic_job_tasks WHERE job_id = 'your-job-id';

-- Test status sync
UPDATE mechanic_jobs SET status = 'FINALIZADO' WHERE id = 'your-job-id';

-- Check tasks were completed
SELECT * FROM mechanic_job_tasks WHERE job_id = 'your-job-id';

-- Test task summary
SELECT get_job_task_summary('your-job-id');
```

## Future Enhancements

- [ ] Task dependencies (task B can't start until task A is done)
- [ ] Estimated vs actual time tracking
- [ ] Task templates for common services
- [ ] Notifications when tasks assigned/completed
- [ ] Time tracking integration (clock in/out per task)
- [ ] Photo attachments per task
- [ ] Task checklists (sub-tasks)
- [ ] Gantt chart view for complex pegas
- [ ] Task history/audit trail
- [ ] Integration with employee module (when HR is complete)

## Support

For issues or questions:
1. Check database logs in Supabase
2. Check Flutter console for debug messages
3. Verify RLS policies are working correctly
4. Check that triggers are firing (inspect created tasks)

---

**Location in core_schema.sql:** Lines 9427-9726
**Deployment file:** `DEPLOY_SMART_TASK_SYSTEM.sql`
**Flutter models:** `lib/modules/bikeshop/models/mechanic_job_task.dart`
**Flutter service:** `lib/modules/bikeshop/services/mechanic_job_task_service.dart`
