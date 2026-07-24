import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/website_service.dart';
import '../models/website_catalog_query.dart';
import '../models/website_page_models.dart';
import '../models/website_destination.dart';
import '../widgets/website_link_value_editor.dart';
import '../../inventory/services/category_service.dart';
import '../../inventory/models/category_models.dart' as cat_models;
import '../widgets/website_admin_ui.dart';

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
    return WebsiteAdminShell(
      embedded: widget.embedded,
      title: 'Navegación',
      description: 'Define el recorrido principal del encabezado y del pie.',
      actions: [
        IconButton.outlined(
          onPressed: _loadNavigation,
          tooltip: 'Actualizar navegación',
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
        FilledButton.icon(
          onPressed: () => _showAddLinkDialog(
            _tabController.index == 0
                ? MenuLocation.header
                : MenuLocation.footer,
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Agregar enlace'),
        ),
      ],
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerHeight: 1,
            tabs: [
              Tab(
                text: 'Encabezado  ·  ${_headerLinks.length}',
              ),
              Tab(
                text: 'Pie de página  ·  ${_footerLinks.length}',
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
      ),
    );
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
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
    // We use ValueKey to ensure state preservation when reordering
    return _NavigationTreeItem(
      key: ValueKey(link.id),
      item: link,
      location: location,
      depth: depth,
      onAddSubItem: _showAddLinkDialog,
      onEdit: _showEditLinkDialog,
      onDelete: _confirmDeleteLink,
      onToggleVisibility: _toggleLinkVisibility,
      onMove: _moveItem,
      getIcon: _getLinkTypeIcon,
      getColor: _getLinkTypeColor,
      getLabel: _getLinkTypeLabel,
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
    final service = context.read<WebsiteService>();
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
            final catService = context.read<CategoryService>();
            int orderIndex = link.orderIndex;

            for (final sub in subcategories) {
              // 1. Create the Link for this Category (e.g. Transmisión)
              final childLink = WebsiteNavigation(
                id: '',
                tenantId: link.tenantId,
                menuLocation: link.menuLocation,
                label: sub.name,
                linkType: NavLinkType.category,
                linkValue: WebsiteDestination.routeForCatalog(
                  categoryId: sub.id,
                  categorySlug: service.catalogPresentationRegistry
                      .forCategory(sub.id)
                      ?.slug,
                ),
                orderIndex: orderIndex++,
                isVisible: true,
                parentId: link.parentId,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              final createdChild = await service.createNavigation(childLink);

              // 2. INTELLIGENT DEEP IMPORT
              // Check if this category has children in the DB. If so, create them too.
              try {
                final grandChildren =
                    await catService.getSubcategories(sub.id!);
                if (grandChildren.isNotEmpty) {
                  int gcOrder = 0;
                  for (final gc in grandChildren) {
                    final gcLink = WebsiteNavigation(
                      id: '',
                      tenantId: link.tenantId,
                      menuLocation: link.menuLocation,
                      label: gc.name,
                      linkType: NavLinkType.category,
                      linkValue: WebsiteDestination.routeForCatalog(
                        categoryId: gc.id,
                        categorySlug: service.catalogPresentationRegistry
                            .forCategory(gc.id)
                            ?.slug,
                      ),
                      orderIndex: gcOrder++,
                      isVisible: true,
                      parentId:
                          createdChild.id, // Parent is the one we just created
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    await service.createNavigation(gcLink);
                  }
                }
              } catch (e) {
                debugPrint('Error auto-importing grandchildren: $e');
              }
            }
            _loadNavigation();
            return;
          }

          // Standard Single Link Creation
          // Create the parent link first
          final createdParent = await service.createNavigation(link);

          // If subcategories were selected (via checklist for a SINGLE main link), create child nav items
          if (subcategories != null && subcategories.isNotEmpty) {
            int orderIndex = 0;
            for (final sub in subcategories) {
              final childLink = WebsiteNavigation(
                id: '',
                tenantId: link.tenantId,
                menuLocation: link.menuLocation,
                label: sub.name,
                linkType: NavLinkType.category,
                linkValue: WebsiteDestination.routeForCatalog(
                  categoryId: sub.id,
                  categorySlug: service.catalogPresentationRegistry
                      .forCategory(sub.id)
                      ?.slug,
                ),
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

          if (subcategories != null && subcategories.isNotEmpty) {
            int orderIndex = 0;
            for (final sub in subcategories) {
              final childLink = WebsiteNavigation(
                id: '',
                tenantId: updatedLink.tenantId,
                menuLocation: updatedLink.menuLocation,
                label: sub.name,
                linkType: NavLinkType.category,
                linkValue: WebsiteDestination.routeForCatalog(
                  categoryId: sub.id,
                  categorySlug: service.catalogPresentationRegistry
                      .forCategory(sub.id)
                      ?.slug,
                ),
                orderIndex: orderIndex++,
                isVisible: true,
                parentId: updatedLink.id,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                // Keep default showOnDesktop/Mobile as true
              );
              await service.createNavigation(childLink);
            }
          }

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
  late bool _isMegaMenu;
  String? _selectedParentId;
  bool _isSaving = false;
  WebsiteCatalogCategoryScope _selectedCategoryScope =
      WebsiteCatalogCategoryScope.subtree;

  // Category picker state
  List<cat_models.Category> _rootCategories = [];
  final Map<String, List<cat_models.Category>> _subcategoriesMap = {};
  String? _selectedRootCategoryId;
  Set<String> _selectedSubcategoryIds = {};
  bool _isLoadingCategories = false;
  bool _isLoadingSubcategories = false;

  bool get _canUseMegaMenu =>
      widget.location == MenuLocation.header &&
      _selectedParentId == null &&
      (_linkType == NavLinkType.category || _linkType == NavLinkType.page);

  String? _resolvedCssClass() {
    final tokens = (widget.link?.cssClass ?? '')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .where((token) => token.toLowerCase() != 'megamenu')
        .toList();
    if (_canUseMegaMenu && _isMegaMenu) {
      tokens.add('megamenu');
    }
    return tokens.isEmpty ? null : tokens.join(' ');
  }

  // Bulk Add State
  final bool _isBulkAddMode = false;
  List<cat_models.Category> _bulkAvailableSubcategories = [];

  String? _categoryIdFromHref(String rawHref) {
    final uri = Uri.tryParse(WebsiteDestination.normalizeHref(rawHref));
    final queryCategory = uri?.queryParameters['category']?.trim();
    if (queryCategory != null && queryCategory.isNotEmpty) {
      return queryCategory;
    }

    final destination = WebsiteDestination.parse(rawHref);
    if (destination.kind != WebsiteDestinationKind.category) return null;
    final slug = destination.reference?.trim() ?? '';
    if (slug.isEmpty) return null;

    // Clean category routes carry a slug rather than an ID. Resolve that slug
    // through the same presentation registry used by public routing so the
    // navigation editor can reopen canonical and historical-alias links.
    return context
        .read<WebsiteService>()
        .catalogPresentationRegistry
        .resolveSlug(slug)
        ?.presentation
        .ownerId;
  }

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
    _isMegaMenu =
        widget.link?.cssClass?.toLowerCase().contains('megamenu') ?? false;

    // Default to loading established root categories
    bool loadRoots = true;

    // INTELLIGENT DEFAULTS
    if (widget.link == null && widget.parentLink != null) {
      if (widget.parentLink!.linkType == NavLinkType.category) {
        _linkType = NavLinkType.category;

        // If adding to a category, we want to show its children
        if (widget.parentLink!.linkValue != null) {
          final parentCatId = _categoryIdFromHref(
            widget.parentLink!.href ?? widget.parentLink!.linkValue!,
          );
          if (parentCatId != null) {
            loadRoots = false;
            _selectedRootCategoryId = parentCatId;
            _selectedCategoryScope = WebsiteCatalogCategoryScope.direct;
            // Load children of the parent context
            _initParentSubcategories(parentCatId);
          }
        }
      }
    } else if (widget.link?.linkType == NavLinkType.category &&
        widget.link?.linkValue != null) {
      final destination = WebsiteDestination.parse(
        widget.link!.href ?? widget.link!.linkValue!,
      );
      _selectedRootCategoryId = _categoryIdFromHref(destination.href);
      final uri = Uri.tryParse(destination.href);
      final query = uri == null ? null : WebsiteCatalogQuery.tryParse(uri);
      _selectedCategoryScope =
          query?.categoryScope ?? WebsiteCatalogCategoryScope.subtree;
      _checkForBulkAddOpportunity();
    }

    if (_linkType == NavLinkType.category && loadRoots) {
      _loadRootCategories();
    }
  }

  Future<void> _initParentSubcategories(String parentId) async {
    setState(() => _isLoadingCategories = true);
    try {
      final categoryService = context.read<CategoryService>();
      final parent = await categoryService.getCategoryById(parentId);
      final children = await categoryService.getSubcategories(parentId);

      // The parent itself is a valid direct-membership destination. Keeping it
      // in this picker lets an editor create a real, removable child such as
      // `Cadenas · solo esta categoría` beside its taxonomic children.
      final validChildren = children.where((c) => c.id != parentId).toList();

      if (mounted) {
        setState(() {
          _rootCategories = [
            if (parent != null) parent,
            ...validChildren,
          ];

          // Bulk actions remain taxonomic children only. The homonymous direct
          // destination is created through the explicit scope control.
          _bulkAvailableSubcategories = validChildren;

          _isLoadingCategories = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading parent subcategories: $e');
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _checkForBulkAddOpportunity() async {
    if (_selectedCategoryScope == WebsiteCatalogCategoryScope.direct) {
      if (mounted) {
        setState(() {
          _bulkAvailableSubcategories = [];
          _selectedSubcategoryIds.clear();
          _isLoadingSubcategories = false;
        });
      }
      return;
    }

    String? catId;

    if (_linkType == NavLinkType.category) {
      // If specifically using the dropdown for category
      if (_selectedRootCategoryId != null) {
        catId = _selectedRootCategoryId;
      } else if (_linkValueController.text.isNotEmpty) {
        final uri = Uri.tryParse(_linkValueController.text);
        catId = uri?.queryParameters['category'];
      }
    }

    if (catId != null) {
      // 1. Try to use local cache first (instant)
      if (_subcategoriesMap.containsKey(catId) &&
          _subcategoriesMap[catId]!.isNotEmpty) {
        final subs = _subcategoriesMap[catId]!;
        if (mounted) {
          setState(() {
            _bulkAvailableSubcategories = subs;
            _selectedSubcategoryIds = subs.map((s) => s.id!).toSet();
            _isLoadingCategories = false;
            _isLoadingSubcategories = false;
          });
        }
        return;
      }

      setState(() => _isLoadingSubcategories = true);
      try {
        final categoryService = context.read<CategoryService>();
        final subs = await categoryService.getSubcategories(catId);

        if (mounted) {
          setState(() {
            _bulkAvailableSubcategories = subs;
            if (subs.isNotEmpty) {
              // Default to ALL selected
              _selectedSubcategoryIds = subs.map((s) => s.id!).toSet();
            }
            _isLoadingSubcategories = false;
          });
        }
      } catch (e) {
        debugPrint('Error checking for bulk subcategories: $e');
        if (mounted) setState(() => _isLoadingSubcategories = false);
      }
    } else {
      if (mounted) {
        setState(() {
          _bulkAvailableSubcategories = [];
        });
      }
    }
  }

  Future<void> _loadRootCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final categoryService = context.read<CategoryService>();
      final roots = await categoryService.getCategories(activeOnly: true);
      setState(() {
        _rootCategories = roots;
        _isLoadingCategories = false;
      });
    } catch (e) {
      debugPrint('Error loading categories: $e');
      setState(() => _isLoadingCategories = false);
    }
  }

  // ignore: unused_element
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
                    initialValue: _selectedParentId,
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
                    validator: (v) =>
                        (v?.isEmpty == true && _selectedSubcategoryIds.isEmpty)
                            ? 'Requerido'
                            : null,
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
                      // Canonical category destination
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRootCategoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Categoría *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: _rootCategories.map((c) {
                          return DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.fullPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (id) async {
                          setState(() {
                            _selectedRootCategoryId = id;
                            final parentCategoryId = widget.parentLink == null
                                ? null
                                : _categoryIdFromHref(
                                    widget.parentLink!.href ??
                                        widget.parentLink!.linkValue ??
                                        '',
                                  );
                            _selectedCategoryScope =
                                id != null && id == parentCategoryId
                                    ? WebsiteCatalogCategoryScope.direct
                                    : WebsiteCatalogCategoryScope.subtree;
                          });
                          // Only clear if we are NOT in the special mode of pre-loaded options
                          // Actually, if they change the root, we should probably check for subcategories of THAT root.
                          // But here we are likely in the "options loaded" state.

                          // Trigger bulk add check
                          await _checkForBulkAddOpportunity();
                        },
                        validator: (v) =>
                            (v == null && _selectedSubcategoryIds.isEmpty)
                                ? 'Selecciona una categoría'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<WebsiteCatalogCategoryScope>(
                        initialValue: _selectedCategoryScope,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Qué incluye este enlace',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.filter_alt_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: WebsiteCatalogCategoryScope.subtree,
                            child: Text('Categoría y subcategorías'),
                          ),
                          DropdownMenuItem(
                            value: WebsiteCatalogCategoryScope.direct,
                            child: Text(
                              'Solo productos asignados a esta categoría',
                            ),
                          ),
                        ],
                        onChanged: (scope) {
                          if (scope == null) return;
                          setState(() {
                            _selectedCategoryScope = scope;
                            if (scope == WebsiteCatalogCategoryScope.direct) {
                              _bulkAvailableSubcategories = [];
                              _selectedSubcategoryIds.clear();
                            }
                          });
                          if (scope == WebsiteCatalogCategoryScope.subtree) {
                            _checkForBulkAddOpportunity();
                          }
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _selectedCategoryScope ==
                                WebsiteCatalogCategoryScope.direct
                            ? 'No incluye productos asignados a categorías hijas.'
                            : 'Incluye esta categoría y toda su descendencia.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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
                      initialValue: _linkValueController.text.isNotEmpty
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
                      if (_canUseMegaMenu)
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Panel ancho'),
                            subtitle: const Text(
                              'Navegación editorial integrada al header; desactívalo para un desplegable compacto',
                            ),
                            value: _isMegaMenu,
                            onChanged: (v) => setState(() => _isMegaMenu = v),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                    ],
                  ),
                  if (_linkType == NavLinkType.external)
                    SwitchListTile(
                      title: const Text('Nueva Pestaña'),
                      subtitle: const Text('Abrir en nueva ventana'),
                      value: _openInNewTab,
                      onChanged: (v) => setState(() => _openInNewTab = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                  const SizedBox(height: 16),

                  // Subcategories Bulk Add Section
                  if (_isLoadingSubcategories)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_bulkAvailableSubcategories.isNotEmpty)
                    _buildBulkAddUI()
                  else if (_linkType == NavLinkType.category &&
                      _selectedRootCategoryId != null &&
                      !_isLoadingCategories)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'Esta categoría no tiene subcategorías para agregar.',
                        style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontStyle: FontStyle.italic),
                      ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Incluir Subcategorías:', style: theme.textTheme.titleSmall),
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
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
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
      ],
    );
  }

  Future<void> _save() async {
    // Check validation
    final isValid = _formKey.currentState!.validate();
    // If invalid AND we don't have bulk items, stop.
    // If invalid BUT we have bulk items, we proceed (assuming validators allowed empty fields)
    if (!isValid && _selectedSubcategoryIds.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      // Determine link value based on type
      String linkValue = '';

      if (_linkType == NavLinkType.category &&
          _selectedRootCategoryId != null) {
        final presentation = context
            .read<WebsiteService>()
            .catalogPresentationRegistry
            .forCategory(_selectedRootCategoryId);
        linkValue = WebsiteDestination.routeForCatalog(
          categoryId: _selectedRootCategoryId,
          categorySlug: presentation?.slug,
          catalogQuery: WebsiteCatalogQuery(
            categoryScope: _selectedCategoryScope,
          ),
        );
      } else {
        linkValue = _linkValueController.text.trim();
      }

      // If we are doing a bulk add and the user left the main label empty,
      // we create a placeholder link. The onSave callback should handle this
      // by ignoring the main link if it's "empty" but has subcategories.
      // However, looking at the code, onSave (in navigation_management_page)
      // specifically checks `if (subcategories != null && subcategories.isNotEmpty)`.
      // If that's true, it DOES NOT create the `link` passed in, it only creates the subcategories.
      // So we can safely pass a dummy link here.

      final effectiveLinkType = _linkType == NavLinkType.page
          ? WebsiteDestination.navigationTypeForHref(linkValue)
          : _linkType;

      final nav = WebsiteNavigation(
        id: widget.link?.id ?? '',
        tenantId: widget.link?.tenantId ?? '',
        menuLocation: widget.location,
        label: _labelController.text.trim().isEmpty
            ? 'BULK_ADD_PLACEHOLDER'
            : _labelController.text.trim(),
        icon: widget.link?.icon,
        linkType: effectiveLinkType,
        linkValue: linkValue,
        orderIndex: widget.link?.orderIndex ?? 0,
        isVisible: _isVisible,
        showOnDesktop: widget.link?.showOnDesktop ?? true,
        showOnMobile: widget.link?.showOnMobile ?? true,
        openInNewTab: _openInNewTab,
        parentId: _selectedParentId ?? widget.parentId,
        cssClass: _resolvedCssClass(),
        highlight: widget.link?.highlight ?? false,
        createdAt: widget.link?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Collect selected subcategories if any
      final selectedSubs = _bulkAvailableSubcategories
          .where((s) => _selectedSubcategoryIds.contains(s.id))
          .toList();

      // Pass the main link AND the subcategories to create
      await widget.onSave(nav, subcategories: selectedSubs);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

// ============================================================================
// COLLAPSIBLE NAVIGATION TREE ITEM
// ============================================================================

class _NavigationTreeItem extends StatefulWidget {
  final WebsiteNavigation item;
  final MenuLocation location;
  final int depth;

  // Callbacks
  final Function(MenuLocation, {String? parentId}) onAddSubItem;
  final Function(WebsiteNavigation) onEdit;
  final Function(WebsiteNavigation) onDelete;
  final Function(WebsiteNavigation) onToggleVisibility;
  final Function(WebsiteNavigation, int, MenuLocation) onMove;

  // Presentation helper methods from parent
  final IconData Function(NavLinkType) getIcon;
  final Color Function(NavLinkType) getColor;
  final String Function(NavLinkType) getLabel;

  const _NavigationTreeItem({
    super.key,
    required this.item,
    required this.location,
    required this.depth,
    required this.onAddSubItem,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleVisibility,
    required this.onMove,
    required this.getIcon,
    required this.getColor,
    required this.getLabel,
  });

  @override
  State<_NavigationTreeItem> createState() => _NavigationTreeItemState();
}

class _NavigationTreeItemState extends State<_NavigationTreeItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final link = widget.item;
    final hasChildren = link.children.isNotEmpty;
    final theme = Theme.of(context);

    // Indentation based on depth
    final indent = widget.depth * 24.0;

    return Column(
      children: [
        // THE ROW ITEM
        Padding(
          padding: EdgeInsets.only(left: indent, right: 8, top: 4, bottom: 4),
          child: Container(
            decoration: BoxDecoration(
              color: link.isVisible
                  ? theme.colorScheme.surface
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                // Expand/Collapse Button (or spacer)
                if (hasChildren)
                  IconButton(
                    icon: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _isExpanded = !_isExpanded),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: _isExpanded ? 'Contraer' : 'Expandir',
                  )
                else
                  const SizedBox(width: 32), // Spacer for alignment

                // Drag handle (visual only for now, manual sorting via arrows)
                Icon(Icons.drag_indicator,
                    size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 8),

                Icon(
                  widget.getIcon(link.linkType),
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        link.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.getLabel(link.linkType)} · ${link.linkValue ?? 'Sin destino'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Actions
                if (!link.isVisible)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Oculto',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    link.isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 20,
                    color: link.isVisible ? null : Colors.orange,
                  ),
                  onPressed: () => widget.onToggleVisibility(link),
                  tooltip: link.isVisible ? 'Ocultar' : 'Mostrar',
                ),
                PopupMenuButton<String>(
                  tooltip: 'Más acciones',
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  onSelected: (value) {
                    switch (value) {
                      case 'child':
                        widget.onAddSubItem(
                          widget.location,
                          parentId: link.id,
                        );
                      case 'edit':
                        widget.onEdit(link);
                      case 'delete':
                        widget.onDelete(link);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'child',
                      child: ListTile(
                        leading: Icon(Icons.subdirectory_arrow_right_rounded),
                        title: Text('Agregar subenlace'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Eliminar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                // Sorting Arrows
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => widget.onMove(link, -1, widget.location),
                      child: const Icon(Icons.keyboard_arrow_up, size: 18),
                    ),
                    InkWell(
                      onTap: () => widget.onMove(link, 1, widget.location),
                      child: const Icon(Icons.keyboard_arrow_down, size: 18),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),

        // CHILDREN (Collapsible)
        if (hasChildren && _isExpanded)
          Padding(
            padding:
                const EdgeInsets.only(top: 0), // Already nested by Padding left
            child: Column(
              children: link.children
                  .map((child) => _NavigationTreeItem(
                        item: child,
                        location: widget.location,
                        depth: widget.depth + 1,
                        onAddSubItem: widget.onAddSubItem,
                        onEdit: widget.onEdit,
                        onDelete: widget.onDelete,
                        onToggleVisibility: widget.onToggleVisibility,
                        onMove: widget.onMove,
                        getIcon: widget.getIcon,
                        getColor: widget.getColor,
                        getLabel: widget.getLabel,
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
