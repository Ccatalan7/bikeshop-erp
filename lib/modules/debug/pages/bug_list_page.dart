import 'package:cross_file/cross_file.dart';
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/bug_report.dart';
import '../services/bug_report_service.dart';

/// Page that lists all reported bugs & suggestions with search + filters.
class BugListPage extends StatefulWidget {
  const BugListPage({super.key});

  @override
  State<BugListPage> createState() => _BugListPageState();
}

class _BugListPageState extends State<BugListPage> {
  final _service = BugReportService();
  final _searchController = TextEditingController();

  List<BugReport> _bugs = [];
  bool _loading = true;
  String? _error;

  // Filters
  String _statusFilter = 'active'; // 'active' | 'resolved' | '' (all)
  String _typeFilter = ''; // 'bug' | 'suggestion' | '' (all)
  String? _moduleFilter;

  @override
  void initState() {
    super.initState();
    _loadBugs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBugs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bugs = await _service.fetchBugs(
        statusFilter: _statusFilter.isNotEmpty ? _statusFilter : null,
        typeFilter: _typeFilter.isNotEmpty ? _typeFilter : null,
        moduleFilter: _moduleFilter,
        searchQuery: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
      );
      if (mounted) {
        setState(() {
          _bugs = bugs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleStatus(BugReport bug) async {
    try {
      await _service.toggleStatus(bug);
      _loadBugs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar estado: $e')),
        );
      }
    }
  }

  Future<void> _deleteBug(BugReport bug) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar'),
        content: Text('¿Estás seguro de que quieres eliminar "${bug.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _service.deleteBug(bug.id);
        _loadBugs();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e')),
          );
        }
      }
    }
  }

  List<String> get _distinctModules {
    final modules = _bugs
        .where((b) => b.module != null && b.module!.isNotEmpty)
        .map((b) => b.module!)
        .toSet()
        .toList();
    modules.sort();
    return modules;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MainLayout(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bug_report,
                          size: 28, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        'Debug — Bugs & Sugerencias',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!_loading)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_bugs.length}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const Spacer(),
                      // New Bug button
                      FilledButton.icon(
                        onPressed: () => _openForm(context, type: 'bug'),
                        icon: const Icon(Icons.bug_report, size: 16),
                        label: const Text('Nuevo Bug'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // New Suggestion button
                      FilledButton.icon(
                        onPressed: () => _openForm(context, type: 'suggestion'),
                        icon: const Icon(Icons.lightbulb_outline, size: 16),
                        label: const Text('Nueva Sugerencia'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Filters row ─────────────────────────────────
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Type filter chips
                      _FilterChip(
                        label: 'Bugs',
                        icon: Icons.bug_report,
                        selected: _typeFilter == 'bug',
                        color: Colors.red.shade600,
                        onTap: () {
                          setState(() =>
                              _typeFilter = _typeFilter == 'bug' ? '' : 'bug');
                          _loadBugs();
                        },
                      ),
                      _FilterChip(
                        label: 'Sugerencias',
                        icon: Icons.lightbulb_outline,
                        selected: _typeFilter == 'suggestion',
                        color: Colors.amber.shade700,
                        onTap: () {
                          setState(() => _typeFilter =
                              _typeFilter == 'suggestion' ? '' : 'suggestion');
                          _loadBugs();
                        },
                      ),

                      Container(
                        width: 1,
                        height: 24,
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                      ),

                      // Status filter chips
                      _FilterChip(
                        label: 'Activos',
                        icon: Icons.error_outline,
                        selected: _statusFilter == 'active',
                        color: Colors.orange,
                        onTap: () {
                          setState(() => _statusFilter =
                              _statusFilter == 'active' ? '' : 'active');
                          _loadBugs();
                        },
                      ),
                      _FilterChip(
                        label: 'Resueltos',
                        icon: Icons.check_circle_outline,
                        selected: _statusFilter == 'resolved',
                        color: Colors.green,
                        onTap: () {
                          setState(() => _statusFilter =
                              _statusFilter == 'resolved' ? '' : 'resolved');
                          _loadBugs();
                        },
                      ),
                      _FilterChip(
                        label: 'Todos',
                        icon: Icons.list,
                        selected: _statusFilter.isEmpty && _typeFilter.isEmpty,
                        color: theme.colorScheme.primary,
                        onTap: () {
                          setState(() {
                            _statusFilter = '';
                            _typeFilter = '';
                          });
                          _loadBugs();
                        },
                      ),

                      const SizedBox(width: 8),

                      // Module filter dropdown
                      if (_distinctModules.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxWidth: 260),
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _moduleFilter != null
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.4),
                            ),
                            color: _moduleFilter != null
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.3)
                                : null,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value: _moduleFilter,
                              hint: Text('Módulo',
                                  style: theme.textTheme.bodySmall),
                              icon: const Icon(Icons.arrow_drop_down, size: 18),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Todos los módulos'),
                                ),
                                ..._distinctModules
                                    .map((m) => DropdownMenuItem<String?>(
                                          value: m,
                                          child: Text(m,
                                              overflow: TextOverflow.ellipsis),
                                        )),
                              ],
                              onChanged: (val) {
                                setState(() => _moduleFilter = val);
                                _loadBugs();
                              },
                            ),
                          ),
                        ),

                      const SizedBox(width: 8),

                      // Search bar
                      Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => _loadBugs(),
                          decoration: InputDecoration(
                            hintText: 'Buscar...',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      _loadBugs();
                                    },
                                  )
                                : null,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.4)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.4)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide:
                                  BorderSide(color: theme.colorScheme.primary),
                            ),
                            filled: true,
                            fillColor: isDark
                                ? theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3)
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Content ─────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: theme.colorScheme.error),
                              const SizedBox(height: 12),
                              Text('Error al cargar',
                                  style: theme.textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(_error!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _loadBugs,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      : _bugs.isEmpty
                          ? _buildEmptyState(theme)
                          : _buildBugList(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bug_report_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            _statusFilter == 'active'
                ? '¡Sin items activos! 🎉'
                : _statusFilter == 'resolved'
                    ? 'No hay items resueltos todavía'
                    : 'No hay bugs ni sugerencias reportadas',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Presiona "Nuevo Bug" o "Nueva Sugerencia" para crear uno',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBugList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bugs.length,
      itemBuilder: (context, index) {
        final bug = _bugs[index];
        return _BugCard(
          bug: bug,
          onToggleStatus: () => _toggleStatus(bug),
          onEdit: () => _openForm(context, bugId: bug.id),
          onDelete: () => _deleteBug(bug),
        );
      },
    );
  }

  void _openForm(BuildContext context,
      {String? bugId, String type = 'bug'}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _BugFormDialog(bugId: bugId, initialType: type),
      ),
    );
    if (result == true) {
      _loadBugs();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Bug/Suggestion Card widget
// ═══════════════════════════════════════════════════════════════════

class _BugCard extends StatelessWidget {
  final BugReport bug;
  final VoidCallback onToggleStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BugCard({
    required this.bug,
    required this.onToggleStatus,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    // Color scheme based on type
    final typeColor = bug.isBug ? Colors.red.shade600 : Colors.amber.shade700;
    final typeIcon = bug.isBug ? Icons.bug_report : Icons.lightbulb;
    final typeLabel = bug.isBug ? 'Bug' : 'Sugerencia';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: bug.isResolved
              ? Colors.green.withValues(alpha: 0.3)
              : typeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status icon (clickable toggle)
              Tooltip(
                message: bug.isResolved
                    ? 'Marcar como activo'
                    : 'Marcar como resuelto',
                child: InkWell(
                  onTap: onToggleStatus,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bug.isResolved
                          ? Colors.green.withValues(alpha: 0.15)
                          : typeColor.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      bug.isResolved ? Icons.check_circle : typeIcon,
                      size: 18,
                      color: bug.isResolved ? Colors.green.shade600 : typeColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type badge + Title row
                    Row(
                      children: [
                        // Type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(typeIcon, size: 12, color: typeColor),
                              const SizedBox(width: 4),
                              Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: typeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Title
                        Expanded(
                          child: Text(
                            bug.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: bug.isResolved
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: bug.isResolved
                                  ? theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Description preview
                    if (bug.description != null && bug.description!.isNotEmpty)
                      Text(
                        bug.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),

                    const SizedBox(height: 8),

                    // Metadata row
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (bug.module != null && bug.module!.isNotEmpty)
                          _MetaBadge(
                            icon: Icons.extension,
                            label: bug.module!,
                            color: theme.colorScheme.primary,
                          ),
                        if (bug.reportedByName != null)
                          _MetaBadge(
                            icon: Icons.person_outline,
                            label: bug.reportedByName!,
                            color: theme.colorScheme.secondary,
                          ),
                        _MetaBadge(
                          icon: Icons.access_time,
                          label: dateFormat.format(bug.createdAt.toLocal()),
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                        if (bug.imageUrls.isNotEmpty)
                          _MetaBadge(
                            icon: Icons.image,
                            label: '${bug.imageUrls.length}',
                            color: theme.colorScheme.tertiary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Image thumbnail (clickable → lightbox)
              if (bug.imageUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _DraggableImage(
                    imageUrl: bug.imageUrls.first,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () =>
                            _showImageViewer(context, bug.imageUrls, 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            bug.imageUrls.first,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 56,
                              height: 56,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(Icons.broken_image,
                                  size: 20,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ), // Actions menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 16),
                        SizedBox(width: 8),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                            bug.isResolved
                                ? Icons.undo
                                : Icons.check_circle_outline,
                            size: 16),
                        const SizedBox(width: 8),
                        Text(bug.isResolved ? 'Reabrir' : 'Marcar resuelto'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Eliminar', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'toggle') onToggleStatus();
                  if (val == 'delete') onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Small metadata badge
// ═══════════════════════════════════════════════════════════════════

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 11,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Filter chips
// ═══════════════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color:
                selected ? color.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.3),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: selected ? color : color.withValues(alpha: 0.6)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? color : color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Bug/Suggestion Form (full-page)
// ═══════════════════════════════════════════════════════════════════

class _BugFormDialog extends StatefulWidget {
  final String? bugId;
  final String initialType;
  const _BugFormDialog({this.bugId, this.initialType = 'bug'});

  @override
  State<_BugFormDialog> createState() => _BugFormDialogState();
}

class _BugFormDialogState extends State<_BugFormDialog> {
  final _service = BugReportService();
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _type = 'bug';
  String? _selectedModule;
  String _status = 'active';
  List<String> _imageUrls = [];
  bool _saving = false;
  bool _loadingExisting = false;
  bool _uploading = false;
  BugReport? _existingBug;

  // For module search
  final _moduleSearchCtrl = TextEditingController();
  List<String> _filteredModules = BugReportService.availableModules;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    if (widget.bugId != null) {
      _loadExistingBug();
    }
    _moduleSearchCtrl.addListener(_filterModules);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _moduleSearchCtrl.dispose();
    super.dispose();
  }

  void _filterModules() {
    final q = _moduleSearchCtrl.text.toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredModules = BugReportService.availableModules;
      } else {
        _filteredModules = BugReportService.availableModules
            .where((m) => m.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  Future<void> _loadExistingBug() async {
    setState(() => _loadingExisting = true);
    try {
      final bugs = await _service.fetchBugs();
      final bug = bugs.firstWhere((b) => b.id == widget.bugId);
      _existingBug = bug;
      _titleCtrl.text = bug.title;
      _descCtrl.text = bug.description ?? '';
      _type = bug.type;
      _selectedModule = bug.module;
      _status = bug.status;
      _imageUrls = List.from(bug.imageUrls);
    } catch (e) {
      debugPrint('Error loading bug: $e');
    }
    if (mounted) setState(() => _loadingExisting = false);
  }

  /// Upload a list of XFiles (from picker or drag-and-drop)
  Future<void> _uploadFiles(List<XFile> files) async {
    if (files.isEmpty) return;

    setState(() => _uploading = true);

    for (final file in files) {
      Uint8List? bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (e) {
        debugPrint('Error reading file ${file.name}: $e');
      }

      if (bytes == null) continue;

      try {
        final url = await _service.uploadScreenshot(
          bytes: bytes,
          fileName: file.name,
        );
        if (mounted) {
          setState(() => _imageUrls.add(url));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al subir ${file.name}: $e')),
          );
        }
      }
    }

    if (mounted) setState(() => _uploading = false);
  }

  /// Pick images using file_picker
  Future<void> _pickAndUploadImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      // Convert PlatformFiles to XFiles
      final validFiles = <XFile>[];
      for (final f in result.files) {
        if (f.bytes != null) {
          validFiles.add(XFile.fromData(f.bytes!, name: f.name));
        } else if (f.path != null) {
          validFiles.add(XFile(f.path!, name: f.name));
        }
      }

      await _uploadFiles(validFiles);
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar archivos: $e')),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() => _imageUrls.removeAt(index));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      if (_existingBug != null) {
        await _service.updateBug(_existingBug!.id, {
          'title': _titleCtrl.text.trim(),
          'type': _type,
          'description': _descCtrl.text.trim(),
          'module': _selectedModule,
          'status': _status,
          'image_urls': _imageUrls,
        });
      } else {
        await _service.createBug(
          title: _titleCtrl.text.trim(),
          type: _type,
          description: _descCtrl.text.trim(),
          module: _selectedModule,
          imageUrls: _imageUrls,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.bugId != null;
    final isBug = _type == 'bug';
    final accentColor = isBug ? Colors.red.shade600 : Colors.amber.shade700;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(isEditing
            ? 'Editar ${isBug ? "Bug" : "Sugerencia"}'
            : 'Nuevo ${isBug ? "Bug" : "Sugerencia"}'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (isEditing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _StatusToggle(
                status: _status,
                onChanged: (s) => setState(() => _status = s),
              ),
            ),
        ],
      ),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Type selector
                        Text('Tipo', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'bug',
                              label: Text('Bug'),
                              icon: Icon(Icons.bug_report, size: 16),
                            ),
                            ButtonSegment(
                              value: 'suggestion',
                              label: Text('Sugerencia / Mejora'),
                              icon: Icon(Icons.lightbulb_outline, size: 16),
                            ),
                          ],
                          selected: {_type},
                          onSelectionChanged: (s) =>
                              setState(() => _type = s.first),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        TextFormField(
                          controller: _titleCtrl,
                          decoration: InputDecoration(
                            labelText: isBug
                                ? 'Título del bug *'
                                : 'Título de la sugerencia *',
                            hintText: isBug
                                ? 'Ej: Error al guardar factura'
                                : 'Ej: Agregar filtro por fecha en ventas',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: Icon(
                                isBug
                                    ? Icons.bug_report
                                    : Icons.lightbulb_outline,
                                size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Description
                        TextFormField(
                          controller: _descCtrl,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: 'Descripción',
                            hintText: isBug
                                ? 'Describe el bug con detalle: qué pasó, qué esperabas, pasos para reproducir...'
                                : 'Describe la mejora o sugerencia con detalle...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Module selector (smart dropdown with search)
                        Text('Módulo / Submódulo',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            children: [
                              TextField(
                                controller: _moduleSearchCtrl,
                                decoration: InputDecoration(
                                  hintText: 'Buscar módulo...',
                                  prefixIcon:
                                      const Icon(Icons.search, size: 18),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  isDense: true,
                                  suffixIcon: _moduleSearchCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon:
                                              const Icon(Icons.close, size: 16),
                                          onPressed: () {
                                            _moduleSearchCtrl.clear();
                                          },
                                        )
                                      : null,
                                ),
                                style: theme.textTheme.bodySmall,
                              ),
                              const Divider(height: 1),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 180),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: _filteredModules.length,
                                  itemBuilder: (_, i) {
                                    final mod = _filteredModules[i];
                                    final isSelected = mod == _selectedModule;
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedModule =
                                              isSelected ? null : mod;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        color: isSelected
                                            ? theme.colorScheme.primaryContainer
                                                .withValues(alpha: 0.3)
                                            : null,
                                        child: Row(
                                          children: [
                                            if (isSelected)
                                              Icon(Icons.check,
                                                  size: 16,
                                                  color:
                                                      theme.colorScheme.primary)
                                            else
                                              const SizedBox(width: 16),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                mod,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selectedModule != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.extension,
                                    size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(_selectedModule!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    )),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () =>
                                      setState(() => _selectedModule = null),
                                  child: Icon(Icons.close,
                                      size: 14,
                                      color: theme.colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Image upload area
                        Text('Capturas de pantalla',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        _ImageUploadZone(
                          imageUrls: _imageUrls,
                          uploading: _uploading,
                          onPickImages: _pickAndUploadImages,
                          onRemoveImage: _removeImage,
                          onFilesDropped: _uploadFiles,
                        ),

                        const SizedBox(height: 32),

                        // Submit button
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(isEditing ? Icons.save : Icons.add,
                                  size: 18),
                          label: Text(isEditing
                              ? 'Guardar cambios'
                              : isBug
                                  ? 'Reportar Bug'
                                  : 'Enviar Sugerencia'),
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Status toggle for editing
// ═══════════════════════════════════════════════════════════════════

class _StatusToggle extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;

  const _StatusToggle({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
            value: 'active',
            label: Text('Activo'),
            icon: Icon(Icons.error_outline, size: 16)),
        ButtonSegment(
            value: 'resolved',
            label: Text('Resuelto'),
            icon: Icon(Icons.check_circle_outline, size: 16)),
      ],
      selected: {status},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Image Upload Zone (uses file_picker for web + desktop)
// ═══════════════════════════════════════════════════════════════════

class _ImageUploadZone extends StatelessWidget {
  final List<String> imageUrls;
  final bool uploading;
  final VoidCallback onPickImages;
  final void Function(int index) onRemoveImage;
  final void Function(List<XFile>)? onFilesDropped;

  const _ImageUploadZone({
    required this.imageUrls,
    required this.uploading,
    required this.onPickImages,
    required this.onRemoveImage,
    this.onFilesDropped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropTarget(
      onDragDone: (details) => onFilesDropped?.call(details.files),
      onDragEntered: (_) {},
      onDragExited: (_) {},
      child: Column(
        children: [
          // Upload button zone
          GestureDetector(
            onTap: uploading ? null : onPickImages,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  width: 1,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.2),
              ),
              child: Center(
                child: uploading
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Subiendo...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              )),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 32,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Haz clic para subir imágenes',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          Text(
                            'PNG, JPG, WEBP — Se pueden seleccionar múltiples',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          // Image thumbnails (clickable → lightbox)
          if (imageUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(imageUrls.length, (i) {
                  return Stack(
                    children: [
                      _DraggableImage(
                        imageUrl: imageUrls[i],
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () =>
                                _showImageViewer(context, imageUrls, i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrls[i],
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child:
                                      const Icon(Icons.broken_image, size: 20),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () => onRemoveImage(i),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.shade600,
                            ),
                            child: const Icon(Icons.close,
                                size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Global helper to open the image viewer
// ═══════════════════════════════════════════════════════════════════

void _showImageViewer(
    BuildContext context, List<String> imageUrls, int initialIndex) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ImageViewerDialog(
      imageUrls: imageUrls,
      initialIndex: initialIndex,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
// Fullscreen Image Viewer with gallery navigation + download
// ═══════════════════════════════════════════════════════════════════

class _ImageViewerDialog extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _ImageViewerDialog({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _download() async {
    final url = widget.imageUrls[_currentIndex];
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.imageUrls.length > 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Tap background to close
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.transparent),
          ),

          // Image gallery
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              return Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(
                    widget.imageUrls[i],
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 200,
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.broken_image,
                          size: 48, color: Colors.white54),
                    ),
                  ),
                ),
              );
            },
          ),

          // Top bar — counter + actions
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Counter badge
                if (hasMultiple)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.imageUrls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                // Download button
                _viewerActionButton(
                  icon: Icons.download,
                  tooltip: 'Descargar / Abrir',
                  onTap: _download,
                ),
                const SizedBox(width: 8),
                // Close button
                _viewerActionButton(
                  icon: Icons.close,
                  tooltip: 'Cerrar',
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Left arrow
          if (hasMultiple && _currentIndex > 0)
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _viewerActionButton(
                  icon: Icons.chevron_left,
                  tooltip: 'Anterior',
                  onTap: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),

          // Right arrow
          if (hasMultiple && _currentIndex < widget.imageUrls.length - 1)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _viewerActionButton(
                  icon: Icons.chevron_right,
                  tooltip: 'Siguiente',
                  onTap: () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _viewerActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Draggable Image Wrapper (Drag-to-Export)
// ═══════════════════════════════════════════════════════════════════

class _DraggableImage extends StatelessWidget {
  final String imageUrl;
  final Widget child;

  const _DraggableImage({
    required this.imageUrl,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      dragItemProvider: (request) async {
        final item = DragItem();

        // 1. Provide URL as text
        item.add(Formats.plainText(imageUrl));

        // 2. Provide content as URI
        item.add(Formats.uri(NamedUri(Uri.parse(imageUrl))));

        // 3. Provide Image Data (deferred)
        item.add(Formats.png.lazy(() async {
          try {
            final uri = Uri.parse(imageUrl);
            final response = await http.get(uri);
            if (response.statusCode == 200) {
              return response.bodyBytes;
            }
            return Uint8List(0);
          } catch (e) {
            debugPrint('Error fetching image for drag: $e');
            return Uint8List(0);
          }
        }));

        return item;
      },
      allowedOperations: () => [DropOperation.copy],
      child: DraggableWidget(
        child: child,
      ),
    );
  }
}
