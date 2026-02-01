import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/website_service.dart';
import '../models/website_page_models.dart';
import '../widgets/website_link_value_editor.dart';
import '../../inventory/services/category_service.dart';
import '../../inventory/models/category_models.dart' as cat_models;

/// Navigation Management Page - Manage website menus (header, footer)
class NavigationManagementPage extends StatefulWidget {
  const NavigationManagementPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<NavigationManagementPage> createState() =>
      _NavigationManagementPageState();
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
              location == MenuLocation.header
                  ? Icons.web
                  : Icons.call_to_action,
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: links.map((link) => _buildLinkItem(link, location)).toList(),
    );
  }

  Widget _buildLinkItem(WebsiteNavigation link, MenuLocation location,
      {int depth = 0}) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 24.0, bottom: 8),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (depth > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.subdirectory_arrow_right,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant
                              .withOpacity(0.5)),
                    ),
                  Container(
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
                ],
              ),
              title: Text(
                link.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
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
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: () =>
                        _showAddLinkDialog(location, parentId: link.id),
                    tooltip: 'Agregar Sub-item',
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
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.red),
                    onPressed: () => _confirmDeleteLink(link),
                    tooltip: 'Eliminar',
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    onPressed: () => _moveItem(link, -1, location),
                    tooltip: 'Mover Arriba',
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 20),
                    onPressed: () => _moveItem(link, 1, location),
                    tooltip: 'Mover Abajo',
                  ),
                ],
              ),
            ),
          ),
        ),
        // Recursively render children
        if (link.children.isNotEmpty)
          ...link.children
              .map((c) => _buildLinkItem(c, location, depth: depth + 1)),
      ],
    );
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

  Future<void> _moveItem(
      WebsiteNavigation item, int direction, MenuLocation location) async {
    // Find parent collection (siblings)
    List<WebsiteNavigation> siblings;
    final service = context.read<WebsiteService>();

    // We need to look up in the FULL nested tree
    final allLinks = location == MenuLocation.header
        ? service.headerNavigation
        : service.footerNavigation;

    if (item.parentId != null) {
      WebsiteNavigation? findParent(List<WebsiteNavigation> nodes) {
        for (final node in nodes) {
          if (node.id == item.parentId) return node;
          final found = findParent(node.children);
          if (found != null) return found;
        }
        return null;
      }

      final parent = findParent(allLinks);
      siblings = parent?.children ?? [];
    } else {
      siblings = allLinks;
    }

    final index = siblings.indexWhere((l) => l.id == item.id);
    if (index == -1) return;

    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= siblings.length) return;

    // Create a new list with swapped items
    final newSiblings = List<WebsiteNavigation>.from(siblings);
    final other = newSiblings[newIndex];
    newSiblings[newIndex] = item;
    newSiblings[newIndex - direction] = other; // Swap back

    try {
      // Reorder expects a LIST OF IDS. The backend logic updates indices based on the position in this list.
      // We must send the whole list of siblings in their new order.
      await service.reorderNavigationIds(newSiblings.map((l) => l.id).toList());
      _loadNavigation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error moviendo item: $e')));
      }
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
        content: Text(
            '¿Estás seguro de eliminar "${link.label}"?\nSe eliminarán tamibén sus sub-items.'),
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
        await service.deleteNavigation(link.id);
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

  void _showAddLinkDialog(MenuLocation location, {String? parentId}) {
    // Find parent link object if parentId is provided
    WebsiteNavigation? parentLink;
    if (parentId != null) {
      final allLinks =
          location == MenuLocation.header ? _headerLinks : _footerLinks;
      WebsiteNavigation? findRecursive(List<WebsiteNavigation> nodes) {
        for (final node in nodes) {
          if (node.id == parentId) return node;
          final found = findRecursive(node.children);
          if (found != null) return found;
        }
        return null;
      }

      parentLink = findRecursive(allLinks);
    }

    showDialog(
      context: context,
      builder: (ctx) => _NavigationFormDialog(
        location: location,
        parentId: parentId,
        parentLink: parentLink,
        availableParents:
            location == MenuLocation.header ? _headerLinks : _footerLinks,
        onSave: (link, {List<cat_models.Category>? subcategories}) async {
          final service = context.read<WebsiteService>();

          // Bulk Add Mode: Create multiple sibling links
          if (subcategories != null && subcategories.isNotEmpty) {
            // If we are in bulk mode, 'link' is just a dummy container for the configuration
            // We iterate over the subcategories and create one link for each.
            int orderIndex =
                link.orderIndex; // Start from the passed index (or end)

            // If appending to a list, we should probably find the max order index of current children
            // But for simplicity, we just safely increment.

            for (final sub in subcategories) {
              final childLink = WebsiteNavigation(
                id: '',
                tenantId: link.tenantId,
                menuLocation: link.menuLocation,
                label: sub.name,
                linkType: NavLinkType.category,
                linkValue: '/productos?category=${sub.id}',
                orderIndex: orderIndex++,
                isVisible: true,
                parentId:
                    link.parentId, // This should be the parentId we passed in
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              await service.createNavigation(childLink);
            }
            _loadNavigation();
            return;
          }

          // Standard Single Link Creation
          // Create the parent link first
          final createdParent = await service.createNavigation(link);

          // If subcategories were selected, create child nav items
          if (subcategories != null && subcategories.isNotEmpty) {
            int orderIndex = 0;
            for (final sub in subcategories) {
              final childLink = WebsiteNavigation(
                id: '',
                tenantId: link.tenantId,
                menuLocation: link.menuLocation,
                label: sub.name,
                linkType: NavLinkType.category,
                linkValue: '/productos?category=${sub.id}',
                orderIndex: orderIndex++,
                isVisible: true,
                parentId: createdParent.id,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              await service.createNavigation(childLink);
            }
          }
          _loadNavigation();
        },
      ),
    );
  }

  void _showEditLinkDialog(WebsiteNavigation link) {
    showDialog(
      context: context,
      builder: (ctx) => _NavigationFormDialog(
        link: link,
        location: link.menuLocation,
        availableParents: link.menuLocation == MenuLocation.header
            ? _headerLinks
            : _footerLinks,
        onSave: (updatedLink,
            {List<cat_models.Category>? subcategories}) async {
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
  final String? parentId;
  final WebsiteNavigation? parentLink; // The parent object, if adding a child
  final List<WebsiteNavigation> availableParents;
  final Future<void> Function(WebsiteNavigation link,
      {List<cat_models.Category>? subcategories}) onSave;

  const _NavigationFormDialog({
    this.link,
    required this.location,
    required this.onSave,
    this.parentId,
    this.parentLink,
    this.availableParents = const [],
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
  String? _selectedParentId;
  bool _isSaving = false;

  // Category picker state
  List<cat_models.Category> _rootCategories = [];
  final Map<String, List<cat_models.Category>> _subcategoriesMap = {};
  String? _selectedRootCategoryId;
  Set<String> _selectedSubcategoryIds = {};
  bool _isLoadingCategories = false;

  // Bulk Add State
  bool _isBulkAddMode = false;
  List<cat_models.Category> _bulkAvailableSubcategories = [];

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.link?.label ?? '');
    _linkValueController =
        TextEditingController(text: widget.link?.linkValue ?? '');
    _linkType = widget.link?.linkType ?? NavLinkType.page;
    _isVisible = widget.link?.isVisible ?? true;
    _openInNewTab = widget.link?.openInNewTab ?? false;
    _selectedParentId = widget.link?.parentId ?? widget.parentId;

    // Detect if we should offer Bulk Add
    _checkForBulkAddOpportunity();

    // Load categories when type is category
    if (_linkType == NavLinkType.category) {
      _loadRootCategories();
    }
  }

  Future<void> _checkForBulkAddOpportunity() async {
    // Only if creating new link, has parent, and parent is Category type
    if (widget.link == null &&
        widget.parentLink != null &&
        widget.parentLink!.linkType == NavLinkType.category) {
      final parentVal = widget.parentLink!.linkValue ?? '';
      final uri = Uri.tryParse(parentVal);
      final catId = uri?.queryParameters['category'];

      if (catId != null) {
        setState(() => _isLoadingCategories = true);
        try {
          final categoryService = context.read<CategoryService>();
          final subs = await categoryService.getSubcategories(catId);

          if (subs.isNotEmpty) {
            setState(() {
              _isBulkAddMode = true;
              _bulkAvailableSubcategories = subs;
              // Select all by default? Or none? Let's select all for convenience.
              _selectedSubcategoryIds = subs.map((s) => s.id!).toSet();
              _isLoadingCategories = false;
            });
          } else {
            setState(() => _isLoadingCategories = false);
          }
        } catch (e) {
          debugPrint('Error checking for bulk subcategories: $e');
          setState(() => _isLoadingCategories = false);
        }
      }
    }
  }

  Future<void> _loadRootCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final categoryService = context.read<CategoryService>();
      final roots = await categoryService.getRootCategories();
      setState(() {
        _rootCategories = roots;
        _isLoadingCategories = false;
      });
    } catch (e) {
      debugPrint('Error loading categories: $e');
      setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _loadSubcategories(String parentId) async {
    if (_subcategoriesMap.containsKey(parentId)) return;
    try {
      final categoryService = context.read<CategoryService>();
      final subs = await categoryService.getSubcategories(parentId);
      setState(() {
        _subcategoriesMap[parentId] = subs;
      });
    } catch (e) {
      debugPrint('Error loading subcategories: $e');
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _linkValueController.dispose();
    super.dispose();
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
                if (_isBulkAddMode) ...[
                  _buildBulkAddUI(),
                ] else ...[
                  // Parent ID Selection (Recursive)
                  DropdownButtonFormField<String?>(
                    value: _selectedParentId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Elemento Padre',
                        border: OutlineInputBorder(),
                        helperText: 'Dejar vacío para nivel superior'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('(Nivel Superior)')),
                      ..._buildParentDropdownItems(widget.availableParents),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedParentId = val);
                    },
                  ),
                  const SizedBox(height: 16),

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
                              _selectedRootCategoryId = null;
                              _selectedSubcategoryIds.clear();
                            });
                            // Load categories when switching to category type
                            if (type == NavLinkType.category &&
                                _rootCategories.isEmpty) {
                              _loadRootCategories();
                            }
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
                    WebsiteLinkValueEditor(
                      label: 'Destino *',
                      value: _linkValueController.text,
                      dense: true,
                      showValuePreview: true,
                      allowInternal: true,
                      allowExternal: false,
                      allowAnchor: false,
                      helpText:
                          'Usá Destinos especiales (Catálogo) para configurar filtros sin pegar URLs.',
                      onChanged: (v) {
                        setState(() {
                          _linkValueController.text = v;
                        });
                      },
                    ),
                    Offstage(
                      offstage: true,
                      child: TextFormField(
                        controller: _linkValueController,
                        validator: (v) =>
                            v?.trim().isEmpty == true ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tip: si querés linkear una página personalizada, elegí "Página del sitio".',
                      style: theme.textTheme.bodySmall,
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
                        if (!v!.startsWith('http://') &&
                            !v.startsWith('https://')) {
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
                    // Category picker - dropdown with actual product categories
                    if (_isLoadingCategories)
                      const Center(child: CircularProgressIndicator())
                    else if (_rootCategories.isEmpty)
                      Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.warning,
                                  color: theme.colorScheme.onErrorContainer),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No hay categorías. Creá categorías en Inventario > Categorías primero.',
                                  style: TextStyle(
                                      color:
                                          theme.colorScheme.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // Root category dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedRootCategoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Categoría Principal *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: _rootCategories.map((c) {
                          return DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          );
                        }).toList(),
                        onChanged: (id) async {
                          setState(() {
                            _selectedRootCategoryId = id;
                            _selectedSubcategoryIds.clear();
                            // Auto-fill label with category name
                            if (_labelController.text.isEmpty && id != null) {
                              final cat = _rootCategories.firstWhere(
                                (c) => c.id == id,
                                orElse: () => _rootCategories.first,
                              );
                              _labelController.text = cat.name;
                            }
                          });
                          if (id != null) {
                            await _loadSubcategories(id);
                          }
                        },
                        validator: (v) =>
                            v == null ? 'Selecciona una categoría' : null,
                      ),
                      const SizedBox(height: 16),

                      // Subcategory checkboxes (if root selected)
                      if (_selectedRootCategoryId != null &&
                          _subcategoriesMap[_selectedRootCategoryId] != null &&
                          _subcategoriesMap[_selectedRootCategoryId]!
                              .isNotEmpty) ...[
                        Text(
                          'Subcategorías a incluir en el menú:',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Column(
                            children:
                                _subcategoriesMap[_selectedRootCategoryId]!
                                    .map((sub) => CheckboxListTile(
                                          title: Text(sub.name),
                                          subtitle: sub.description != null
                                              ? Text(sub.description!,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis)
                                              : null,
                                          value: _selectedSubcategoryIds
                                              .contains(sub.id),
                                          onChanged: (checked) {
                                            setState(() {
                                              if (checked == true) {
                                                _selectedSubcategoryIds
                                                    .add(sub.id!);
                                              } else {
                                                _selectedSubcategoryIds
                                                    .remove(sub.id);
                                              }
                                            });
                                          },
                                        ))
                                    .toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Las subcategorías seleccionadas aparecerán como columnas en el Mega Menú.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (_selectedRootCategoryId != null) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Esta categoría no tiene subcategorías. Se mostrará como enlace simple.',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                    // Hidden validator field
                    Offstage(
                      offstage: true,
                      child: TextFormField(
                        controller: _linkValueController,
                        validator: (v) => _selectedRootCategoryId == null
                            ? 'Selecciona categoría'
                            : null,
                      ),
                    ),
                  ] else if (_linkType == NavLinkType.action) ...[
                    DropdownButtonFormField<String>(
                      value: _linkValueController.text.isNotEmpty
                          ? _linkValueController.text
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Acción *',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'open_cart', child: Text('Abrir Carrito')),
                        DropdownMenuItem(
                            value: 'open_search',
                            child: Text('Abrir Búsqueda')),
                        DropdownMenuItem(
                            value: 'open_login', child: Text('Abrir Login')),
                        DropdownMenuItem(
                            value: 'toggle_theme', child: Text('Cambiar Tema')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _linkValueController.text = value ?? '';
                        });
                      },
                      validator: (v) =>
                          v == null ? 'Selecciona una acción' : null,
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

  // Recursive dropdown items builder
  List<DropdownMenuItem<String>> _buildParentDropdownItems(
      List<WebsiteNavigation> nodes,
      {int depth = 0}) {
    final List<DropdownMenuItem<String>> items = [];
    for (final node in nodes) {
      // Avoid selecting itself or its children as parent (cycle prevention)
      if (widget.link != null && (node.id == widget.link!.id)) continue;

      items.add(DropdownMenuItem(
        value: node.id,
        child: Padding(
          padding: EdgeInsets.only(left: depth * 16.0),
          child: Text(node.label),
        ),
      ));

      if (node.children.isNotEmpty) {
        items
            .addAll(_buildParentDropdownItems(node.children, depth: depth + 1));
      }
    }
    return items;
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

  Widget _buildBulkAddUI() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.playlist_add, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Se detectaron subcategorías para "${widget.parentLink?.label}".\nPodés agregarlas todas juntas aquí.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.blue[800]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Subcategorías disponibles:',
                style: theme.textTheme.labelLarge),
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedSubcategoryIds.length ==
                      _bulkAvailableSubcategories.length) {
                    _selectedSubcategoryIds.clear();
                  } else {
                    _selectedSubcategoryIds =
                        _bulkAvailableSubcategories.map((s) => s.id!).toSet();
                  }
                });
              },
              child: Text(_selectedSubcategoryIds.length ==
                      _bulkAvailableSubcategories.length
                  ? 'Desmarcar Todas'
                  : 'Marcar Todas'),
            ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView(
            shrinkWrap: true,
            children: _bulkAvailableSubcategories.map((sub) {
              return CheckboxListTile(
                title: Text(sub.name),
                value: _selectedSubcategoryIds.contains(sub.id),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedSubcategoryIds.add(sub.id!);
                    } else {
                      _selectedSubcategoryIds.remove(sub.id);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() => _isBulkAddMode = false);
            },
            child: const Text('Prefiero agregar un enlace manual'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_isBulkAddMode) {
      if (_selectedSubcategoryIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccioná al menos una subcategoría')),
        );
        return;
      }

      setState(() => _isSaving = true);
      try {
        final selectedSubs = _bulkAvailableSubcategories
            .where((s) => _selectedSubcategoryIds.contains(s.id))
            .toList();

        // Pass dummy link (will be ignored) and the subcategories
        await widget.onSave(
            WebsiteNavigation(
                id: '',
                tenantId: '',
                menuLocation: widget.location,
                label: 'Bulk',
                linkType: NavLinkType.category,
                linkValue: '',
                orderIndex: 0,
                isVisible: true,
                parentId: widget.parentId,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now()),
            subcategories: selectedSubs);

        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Determine link value based on type
      String linkValue;

      if (_linkType == NavLinkType.category &&
          _selectedRootCategoryId != null) {
        // Build category URL from selected category
        linkValue = '/productos?category=$_selectedRootCategoryId';
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
        openInNewTab: _openInNewTab,
        parentId: _selectedParentId,
        createdAt: widget.link?.createdAt ?? DateTime.now(),
        updatedAt: widget.link?.updatedAt ?? DateTime.now(),
      );

      // Gather selected subcategories to pass to callback
      List<cat_models.Category>? selectedSubcategories;
      if (_linkType == NavLinkType.category &&
          _selectedRootCategoryId != null &&
          _selectedSubcategoryIds.isNotEmpty) {
        final subs = _subcategoriesMap[_selectedRootCategoryId] ?? [];
        selectedSubcategories =
            subs.where((s) => _selectedSubcategoryIds.contains(s.id)).toList();
      }

      // Save the link and optionally pass subcategories for child creation
      await widget.onSave(link, subcategories: selectedSubcategories);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    }
  }
}
