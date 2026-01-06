import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/website_service.dart';
import '../models/website_page_models.dart';

/// Navigation Management Page - Manage website menus (header, footer)
class NavigationManagementPage extends StatefulWidget {
  const NavigationManagementPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<NavigationManagementPage> createState() => _NavigationManagementPageState();
}

class _NavigationManagementPageState extends State<NavigationManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<WebsiteNavigation> _headerLinks = [];
  List<WebsiteNavigation> _footerLinks = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNavigation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadNavigation() async {
    setState(() => _isLoading = true);
    try {
      final service = context.read<WebsiteService>();
      await service.loadNavigation();
      
      setState(() {
        _headerLinks = service.headerNavigation;
        _footerLinks = service.footerNavigation;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading navigation: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar navegación: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = Column(
      children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                if (!widget.embedded) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                ],
                Icon(
                  Icons.menu_book,
                  color: Colors.teal,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestión de Navegación',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Configura los menús del header y footer',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showAddLinkDialog(
                    _tabController.index == 0
                        ? MenuLocation.header
                        : MenuLocation.footer,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar Enlace'),
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                icon: const Icon(Icons.web),
                text: 'Header (${_headerLinks.length})',
              ),
              Tab(
                icon: const Icon(Icons.call_to_action),
                text: 'Footer (${_footerLinks.length})',
              ),
            ],
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLinkList(_headerLinks, MenuLocation.header),
                      _buildLinkList(_footerLinks, MenuLocation.footer),
                    ],
                  ),
          ),
      ],
    );

    if (widget.embedded) return body;

    return MainLayout(child: body);
  }

  Widget _buildLinkList(List<WebsiteNavigation> links, MenuLocation location) {
    final theme = Theme.of(context);
    
    if (links.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              location == MenuLocation.header ? Icons.web : Icons.call_to_action,
              size: 64,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Sin enlaces en ${location == MenuLocation.header ? 'Header' : 'Footer'}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega enlaces para la navegación',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showAddLinkDialog(location),
              icon: const Icon(Icons.add),
              label: const Text('Agregar Primer Enlace'),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: links.length,
      onReorder: (oldIndex, newIndex) => _reorderLinks(links, oldIndex, newIndex, location),
      itemBuilder: (context, index) {
        final link = links[index];
        return _buildLinkCard(link, index, key: ValueKey(link.id));
      },
    );
  }

  Widget _buildLinkCard(WebsiteNavigation link, int index, {required Key key}) {
    final theme = Theme.of(context);
    
    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getLinkTypeColor(link.linkType).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getLinkTypeIcon(link.linkType),
            color: _getLinkTypeColor(link.linkType),
          ),
        ),
        title: Text(
          link.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getLinkTypeColor(link.linkType).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _getLinkTypeLabel(link.linkType),
                style: TextStyle(
                  fontSize: 11,
                  color: _getLinkTypeColor(link.linkType),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                link.linkValue ?? '',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!link.isVisible)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Oculto',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showEditLinkDialog(link),
              tooltip: 'Editar',
            ),
            IconButton(
              icon: Icon(
                link.isVisible ? Icons.visibility : Icons.visibility_off,
                size: 20,
                color: link.isVisible ? null : Colors.orange,
              ),
              onPressed: () => _toggleLinkVisibility(link),
              tooltip: link.isVisible ? 'Ocultar' : 'Mostrar',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: () => _confirmDeleteLink(link),
              tooltip: 'Eliminar',
            ),
            ReorderableDragStartListener(
              index: _getCurrentIndex(link),
              child: const Icon(Icons.drag_handle),
            ),
          ],
        ),
      ),
    );
  }

  int _getCurrentIndex(WebsiteNavigation link) {
    if (link.menuLocation == MenuLocation.header) {
      return _headerLinks.indexWhere((l) => l.id == link.id);
    } else {
      return _footerLinks.indexWhere((l) => l.id == link.id);
    }
  }

  IconData _getLinkTypeIcon(NavLinkType type) {
    switch (type) {
      case NavLinkType.page:
        return Icons.article;
      case NavLinkType.category:
        return Icons.category;
      case NavLinkType.external:
        return Icons.open_in_new;
      case NavLinkType.anchor:
        return Icons.tag;
      case NavLinkType.action:
        return Icons.smart_button;
    }
  }

  Color _getLinkTypeColor(NavLinkType type) {
    switch (type) {
      case NavLinkType.page:
        return Colors.blue;
      case NavLinkType.category:
        return Colors.green;
      case NavLinkType.external:
        return Colors.purple;
      case NavLinkType.anchor:
        return Colors.orange;
      case NavLinkType.action:
        return Colors.teal;
    }
  }

  String _getLinkTypeLabel(NavLinkType type) {
    switch (type) {
      case NavLinkType.page:
        return 'Página';
      case NavLinkType.category:
        return 'Categoría';
      case NavLinkType.external:
        return 'Externo';
      case NavLinkType.anchor:
        return 'Ancla';
      case NavLinkType.action:
        return 'Acción';
    }
  }

  Future<void> _reorderLinks(
    List<WebsiteNavigation> links,
    int oldIndex,
    int newIndex,
    MenuLocation location,
  ) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    setState(() {
      final item = links.removeAt(oldIndex);
      links.insert(newIndex, item);
    });

    // Update order_index in database
    try {
      final service = context.read<WebsiteService>();
      for (int i = 0; i < links.length; i++) {
        final updatedLink = links[i].copyWith(orderIndex: i);
        await service.updateNavigation(updatedLink);
      }
      debugPrint('✅ Navigation order updated');
    } catch (e) {
      debugPrint('❌ Error updating navigation order: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al reordenar: $e')),
      );
      _loadNavigation(); // Reload to restore original order
    }
  }

  Future<void> _toggleLinkVisibility(WebsiteNavigation link) async {
    try {
      final service = context.read<WebsiteService>();
      final updated = link.copyWith(isVisible: !link.isVisible);
      await service.updateNavigation(updated);
      _loadNavigation();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updated.isVisible
                  ? 'Enlace "${link.label}" visible'
                  : 'Enlace "${link.label}" oculto',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteLink(WebsiteNavigation link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Enlace'),
        content: Text('¿Estás seguro de eliminar "${link.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = context.read<WebsiteService>();
        await service.deleteNavigation(link.id!);
        _loadNavigation();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enlace eliminado')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e')),
          );
        }
      }
    }
  }

  void _showAddLinkDialog(MenuLocation location) {
    showDialog(
      context: context,
      builder: (context) => _NavigationFormDialog(
        location: location,
        onSave: (link) async {
          final service = context.read<WebsiteService>();
          await service.createNavigation(link);
          _loadNavigation();
        },
      ),
    );
  }

  void _showEditLinkDialog(WebsiteNavigation link) {
    showDialog(
      context: context,
      builder: (context) => _NavigationFormDialog(
        link: link,
        location: link.menuLocation,
        onSave: (updatedLink) async {
          final service = context.read<WebsiteService>();
          await service.updateNavigation(updatedLink);
          _loadNavigation();
        },
      ),
    );
  }
}

/// Dialog for creating/editing navigation links
class _NavigationFormDialog extends StatefulWidget {
  final WebsiteNavigation? link;
  final MenuLocation location;
  final Future<void> Function(WebsiteNavigation link) onSave;

  const _NavigationFormDialog({
    this.link,
    required this.location,
    required this.onSave,
  });

  @override
  State<_NavigationFormDialog> createState() => _NavigationFormDialogState();
}

class _NavigationFormDialogState extends State<_NavigationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _labelController;
  late TextEditingController _linkValueController;
  late NavLinkType _linkType;
  late bool _isVisible;
  late bool _openInNewTab;
  bool _isSaving = false;

  // For page selection
  List<WebsitePage> _pages = [];
  String? _selectedPageSlug;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.link?.label ?? '');
    _linkValueController = TextEditingController(text: widget.link?.linkValue ?? '');
    _linkType = widget.link?.linkType ?? NavLinkType.page;
    _isVisible = widget.link?.isVisible ?? true;
    _openInNewTab = widget.link?.openInNewTab ?? false;
    
    // If editing a page link, extract the slug from linkValue
    if (widget.link?.linkType == NavLinkType.page && widget.link?.linkValue != null) {
      _selectedPageSlug = widget.link!.linkValue!.replaceFirst('/', '');
    }
    
    _loadPages();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _linkValueController.dispose();
    super.dispose();
  }

  Future<void> _loadPages() async {
    try {
      final service = context.read<WebsiteService>();
      await service.loadPages();
      setState(() {
        _pages = service.pages.where((p) => p.isPublished).toList();
      });
    } catch (e) {
      debugPrint('Error loading pages: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.link != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Enlace' : 'Agregar Enlace'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Link Type
                Text(
                  'Tipo de Enlace',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: NavLinkType.values.map((type) {
                    return ChoiceChip(
                      label: Text(_getLinkTypeLabel(type)),
                      selected: _linkType == type,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _linkType = type;
                            _linkValueController.clear();
                            _selectedPageSlug = null;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Label
                TextFormField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'Texto del Enlace *',
                    hintText: 'ej: Productos, Contacto, Blog',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),

                // Link Value - depends on type
                if (_linkType == NavLinkType.page) ...[
                  DropdownButtonFormField<String>(
                    value: _selectedPageSlug,
                    decoration: const InputDecoration(
                      labelText: 'Página *',
                      border: OutlineInputBorder(),
                    ),
                    items: _pages.map((page) {
                      return DropdownMenuItem(
                        value: page.slug,
                        child: Text(page.title),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPageSlug = value;
                        _linkValueController.text = '/$value';
                      });
                    },
                    validator: (v) => v == null ? 'Selecciona una página' : null,
                  ),
                ] else if (_linkType == NavLinkType.external) ...[
                  TextFormField(
                    controller: _linkValueController,
                    decoration: const InputDecoration(
                      labelText: 'URL Externa *',
                      hintText: 'https://ejemplo.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.open_in_new),
                    ),
                    validator: (v) {
                      if (v?.isEmpty == true) return 'Requerido';
                      if (!v!.startsWith('http://') && !v.startsWith('https://')) {
                        return 'Debe empezar con http:// o https://';
                      }
                      return null;
                    },
                  ),
                ] else if (_linkType == NavLinkType.anchor) ...[
                  TextFormField(
                    controller: _linkValueController,
                    decoration: const InputDecoration(
                      labelText: 'ID del Ancla *',
                      hintText: 'seccion-productos (sin #)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.tag),
                    ),
                    validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                  ),
                ] else if (_linkType == NavLinkType.category) ...[
                  TextFormField(
                    controller: _linkValueController,
                    decoration: const InputDecoration(
                      labelText: 'Categoría *',
                      hintText: 'bicicletas, accesorios, etc.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                  ),
                ] else if (_linkType == NavLinkType.action) ...[
                  DropdownButtonFormField<String>(
                    value: _linkValueController.text.isNotEmpty ? _linkValueController.text : null,
                    decoration: const InputDecoration(
                      labelText: 'Acción *',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'open_cart', child: Text('Abrir Carrito')),
                      DropdownMenuItem(value: 'open_search', child: Text('Abrir Búsqueda')),
                      DropdownMenuItem(value: 'open_login', child: Text('Abrir Login')),
                      DropdownMenuItem(value: 'toggle_theme', child: Text('Cambiar Tema')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _linkValueController.text = value ?? '';
                      });
                    },
                    validator: (v) => v == null ? 'Selecciona una acción' : null,
                  ),
                ],
                const SizedBox(height: 16),

                // Options Row
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        title: const Text('Visible'),
                        subtitle: const Text('Mostrar en menú'),
                        value: _isVisible,
                        onChanged: (v) => setState(() => _isVisible = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (_linkType == NavLinkType.external)
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('Nueva Pestaña'),
                          subtitle: const Text('Abrir en nueva ventana'),
                          value: _openInNewTab,
                          onChanged: (v) => setState(() => _openInNewTab = v),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }

  String _getLinkTypeLabel(NavLinkType type) {
    switch (type) {
      case NavLinkType.page:
        return 'Página';
      case NavLinkType.category:
        return 'Categoría';
      case NavLinkType.external:
        return 'URL Externa';
      case NavLinkType.anchor:
        return 'Ancla';
      case NavLinkType.action:
        return 'Acción';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Determine link value based on type
      String linkValue;
      if (_linkType == NavLinkType.page && _selectedPageSlug != null) {
        linkValue = '/$_selectedPageSlug';
      } else {
        linkValue = _linkValueController.text.trim();
      }

      final link = WebsiteNavigation(
        id: widget.link?.id ?? '',
        tenantId: widget.link?.tenantId ?? '',
        menuLocation: widget.location,
        label: _labelController.text.trim(),
        linkType: _linkType,
        linkValue: linkValue,
        orderIndex: widget.link?.orderIndex ?? 0,
        isVisible: _isVisible,
        openInNewTab: _linkType == NavLinkType.external ? _openInNewTab : false,
        createdAt: widget.link?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await widget.onSave(link);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.link != null
                  ? 'Enlace actualizado'
                  : 'Enlace creado',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
