import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/bikeshop_models.dart';
import '../services/bikeshop_service.dart';

/// Management page for the per-tenant Job Subjects catalog.
/// Subjects are used for non-bike jobs (item_service, warranty, quotation).
class JobSubjectsPage extends StatefulWidget {
  const JobSubjectsPage({super.key});

  @override
  State<JobSubjectsPage> createState() => _JobSubjectsPageState();
}

class _JobSubjectsPageState extends State<JobSubjectsPage> {
  List<JobSubject> _subjects = [];
  bool _isLoading = true;
  String? _error;
  String _searchTerm = '';

  // Predefined categories (user can type a custom one)
  static const List<String> _defaultCategories = [
    'General',
    'Ruedas',
    'Transmisión',
    'Frenos',
    'Suspensión',
    'Movilidad',
    'Componentes',
  ];

  // Icon options (name → IconData)
  static const Map<String, IconData> _iconOptions = {
    'build': Icons.build,
    'build_circle': Icons.build_circle_outlined,
    'settings': Icons.settings,
    'tire_repair': Icons.tire_repair,
    'link': Icons.link,
    'circle': Icons.circle_outlined,
    'stop_circle': Icons.stop_circle_outlined,
    'cable': Icons.cable,
    'compress': Icons.compress,
    'arrow_upward': Icons.arrow_upward,
    'accessible': Icons.accessible,
    'shopping_cart': Icons.shopping_cart_outlined,
    'directions_walk': Icons.directions_walk,
    'extension': Icons.extension,
    'sports': Icons.sports,
    'rectangle': Icons.rectangle_outlined,
    'swap_horiz': Icons.swap_horiz,
    'pan_tool': Icons.pan_tool_outlined,
    'horizontal_rule': Icons.horizontal_rule,
  };

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final service = context.read<BikeshopService>();
      final subjects = await service.getAllJobSubjects();
      if (mounted) {
        setState(() {
          _subjects = subjects;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<JobSubject> get _filteredSubjects {
    if (_searchTerm.isEmpty) return _subjects;
    final term = _searchTerm.toLowerCase();
    return _subjects
        .where((s) =>
            s.name.toLowerCase().contains(term) ||
            s.category.toLowerCase().contains(term) ||
            (s.description?.toLowerCase().contains(term) ?? false))
        .toList();
  }

  Map<String, List<JobSubject>> get _subjectsByCategory {
    final map = <String, List<JobSubject>>{};
    for (final s in _filteredSubjects) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    // Sort within each category by sort_order
    for (final list in map.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return map;
  }

  void _showAddEditDialog([JobSubject? existing]) {
    showDialog(
      context: context,
      builder: (ctx) => _SubjectDialog(
        existing: existing,
        availableCategories: [
          ..._defaultCategories,
          // include any custom categories already in use
          ..._subjects
              .map((s) => s.category)
              .where((c) => !_defaultCategories.contains(c))
              .toSet(),
        ],
        iconOptions: _iconOptions,
        onSave: (subject) async {
          try {
            final service = context.read<BikeshopService>();
            if (existing == null) {
              await service.createJobSubject(subject);
            } else {
              await service.updateJobSubject(subject);
            }
            await _loadSubjects();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(existing == null
                      ? 'Elemento creado correctamente'
                      : 'Elemento actualizado'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _toggleActive(JobSubject subject) async {
    try {
      final service = context.read<BikeshopService>();
      await service.updateJobSubject(
        subject.copyWith(isActive: !subject.isActive),
      );
      await _loadSubjects();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete(JobSubject subject) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar elemento'),
        content: Text(
            '¿Eliminar "${subject.name}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final service = context.read<BikeshopService>();
      await service.deleteJobSubject(subject.id!);
      await _loadSubjects();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Elemento eliminado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Catálogo de Elementos',
      child: _isLoading
          ? const Center(child: BrandedLoading())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text('Error: $_error'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadSubjects,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final byCategory = _subjectsByCategory;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // ── Toolbar ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              // Title + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catálogo de Elementos',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Elementos utilizados en trabajos sin bicicleta (componentes, garantías, presupuestos)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Search
              SizedBox(
                width: 240,
                height: 40,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar elementos...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor:
                        colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  ),
                  onChanged: (v) => setState(() => _searchTerm = v),
                ),
              ),
              const SizedBox(width: 12),
              // Add button
              FilledButton.icon(
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar Elemento'),
              ),
            ],
          ),
        ),

        // ── Body ─────────────────────────────────────────────
        if (byCategory.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.build_circle_outlined,
                      size: 56, color: colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    _searchTerm.isEmpty
                        ? 'No hay elementos en el catálogo'
                        : 'Sin resultados para "$_searchTerm"',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_searchTerm.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Agrega elementos para comenzar',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _showAddEditDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar primer elemento'),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: byCategory.length,
              itemBuilder: (context, index) {
                final category = byCategory.keys.elementAt(index);
                final items = byCategory[category]!;
                return _buildCategorySection(category, items, theme);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCategorySection(
      String category, List<JobSubject> items, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(
            children: [
              Text(
                category,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${items.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 20),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final i = entry.key;
              final subject = entry.value;
              return Column(
                children: [
                  _buildSubjectRow(subject, theme),
                  if (i < items.length - 1)
                    Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: theme.dividerColor),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectRow(JobSubject subject, ThemeData theme) {
    final icon = _iconOptions[subject.icon] ?? Icons.build;
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: subject.isActive
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        child: Icon(
          icon,
          size: 18,
          color: subject.isActive
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        subject.name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: subject.isActive ? null : colorScheme.onSurfaceVariant,
          decoration: subject.isActive ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: subject.description?.isNotEmpty == true
          ? Text(
              subject.description!,
              style:
                  TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Active toggle
          Tooltip(
            message: subject.isActive ? 'Desactivar' : 'Activar',
            child: Switch(
              value: subject.isActive,
              onChanged: (_) => _toggleActive(subject),
            ),
          ),
          // Edit
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Editar',
            onPressed: () => _showAddEditDialog(subject),
          ),
          // Delete (only when not used - allow but warn)
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: Colors.red.shade400),
            tooltip: 'Eliminar',
            onPressed: subject.id != null ? () => _delete(subject) : null,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SUBJECT DIALOG (Create / Edit)
// ============================================================

class _SubjectDialog extends StatefulWidget {
  final JobSubject? existing;
  final List<String> availableCategories;
  final Map<String, IconData> iconOptions;
  final Future<void> Function(JobSubject) onSave;

  const _SubjectDialog({
    this.existing,
    required this.availableCategories,
    required this.iconOptions,
    required this.onSave,
  });

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late String _category;
  late String _icon;
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _category = e?.category ??
        (widget.availableCategories.isNotEmpty
            ? widget.availableCategories.first
            : 'General');
    _icon = e?.icon ?? 'build';
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final now = DateTime.now();
    final subject = JobSubject(
      id: widget.existing?.id,
      tenantId: widget.existing?.tenantId ?? '',
      name: _nameCtrl.text.trim(),
      category: _category,
      icon: _icon,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      isActive: _isActive,
      sortOrder: widget.existing?.sortOrder ?? 0,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      await widget.onSave(subject);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  isEdit ? 'Editar Elemento' : 'Nuevo Elemento',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 20),

                // Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    hintText: 'ej. Rueda delantera, Garantía de suspensión...',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'El nombre es obligatorio'
                      : null,
                ),
                const SizedBox(height: 16),

                // Category (dropdown + allows new)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: widget.availableCategories.contains(_category)
                            ? _category
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                          border: OutlineInputBorder(),
                        ),
                        items: widget.availableCategories
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _category = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Icon picker
                DropdownButtonFormField<String>(
                  initialValue: _icon,
                  decoration: const InputDecoration(
                    labelText: 'Ícono',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.iconOptions.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                Icon(e.value, size: 18),
                                const SizedBox(width: 8),
                                Text(e.key),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _icon = v);
                  },
                ),
                const SizedBox(height: 16),

                // Active toggle
                SwitchListTile(
                  title: const Text('Activo'),
                  subtitle: const Text(
                      'Los elementos inactivos no aparecen al crear trabajos'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isEdit ? 'Guardar' : 'Crear'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
