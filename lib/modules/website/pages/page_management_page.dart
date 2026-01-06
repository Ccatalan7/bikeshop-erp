import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/website_service.dart';
import '../models/website_page_models.dart';

/// Page Management UI - Manage website pages (Odoo-style multi-page support)
/// Allows creating, editing, and organizing pages for the public store
class PageManagementPage extends StatefulWidget {
  const PageManagementPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<PageManagementPage> createState() => _PageManagementPageState();
}

class _PageManagementPageState extends State<PageManagementPage> {
  bool _isLoading = true;
  List<WebsitePage> _pages = [];
  WebsitePage? _selectedPage;

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    setState(() => _isLoading = true);
    try {
      final service = context.read<WebsiteService>();
      await service.loadPages();
      if (mounted) {
        setState(() {
          _pages = service.pages;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading pages: $e');
      if (mounted) {
        setState(() => _isLoading = false);
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
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                // Back button
                if (!widget.embedded) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Volver',
                  ),
                  const SizedBox(width: 16),
                ],
                // Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Páginas del Sitio',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Administra las páginas de tu tienda online',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Add page button
                FilledButton.icon(
                  onPressed: () => _showPageDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva Página'),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _pages.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildPagesList(theme),
          ),
      ],
    );

    if (widget.embedded) return body;

    return MainLayout(child: body);
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.web_outlined,
            size: 80,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No hay páginas creadas',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea tu primera página para comenzar',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showPageDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Crear Página'),
          ),
        ],
      ),
    );
  }

  Widget _buildPagesList(ThemeData theme) {
    // Separate home page from others
    final homePage = _pages.where((p) => p.isHome).firstOrNull;
    final otherPages = _pages.where((p) => !p.isHome).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Home Page Card (Special)
          if (homePage != null) ...[
            Text(
              'Página Principal',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            _buildHomePageCard(homePage, theme),
            const SizedBox(height: 32),
          ],

          // Other Pages
          if (otherPages.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Otras Páginas',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${otherPages.length} página${otherPages.length != 1 ? 's' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...otherPages.map((page) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPageCard(page, theme),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildHomePageCard(WebsitePage page, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer.withOpacity(0.3),
              theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Home icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.home_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 20),
              // Page info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          page.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(page.isPublished, theme),
                        if (page.isSystem) ...[
                          const SizedBox(width: 8),
                          _buildSystemChip(theme),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'URL: /${page.slug}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (page.metaDescription?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        page.metaDescription!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Actions
              _buildPageActions(page, theme, isHome: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageCard(WebsitePage page, ThemeData theme) {
    final isSelected = _selectedPage?.id == page.id;

    return Card(
      elevation: isSelected ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedPage = isSelected ? null : page),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Page icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getTemplateColor(page.template).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getTemplateIcon(page.template),
                  color: _getTemplateColor(page.template),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Page info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            page.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(page.isPublished, theme),
                        if (page.isSystem) ...[
                          const SizedBox(width: 8),
                          _buildSystemChip(theme),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.link,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/${page.slug}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.layers_outlined,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getTemplateName(page.template),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              _buildPageActions(page, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isPublished, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isPublished
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPublished ? Icons.public : Icons.visibility_off,
            size: 12,
            color: isPublished ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 4),
          Text(
            isPublished ? 'Publicada' : 'Borrador',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isPublished ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemChip(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 12,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Text(
            'Sistema',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageActions(WebsitePage page, ThemeData theme,
      {bool isHome = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Edit blocks button
        FilledButton.tonalIcon(
          onPressed: () => _openPageEditor(page),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Editar'),
        ),
        const SizedBox(width: 8),
        // More options
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Más opciones',
          onSelected: (value) => _handleMenuAction(value, page),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'settings',
              child: ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Configuración'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: page.isPublished ? 'unpublish' : 'publish',
              child: ListTile(
                leading: Icon(
                  page.isPublished ? Icons.visibility_off : Icons.public,
                ),
                title: Text(page.isPublished ? 'Despublicar' : 'Publicar'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (!page.isHome)
              PopupMenuItem(
                value: 'set_home',
                child: ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Hacer Inicio'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            PopupMenuItem(
              value: 'copy_url',
              child: ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copiar URL'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (!page.isSystem) ...[
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red[400]),
                  title: Text(
                    'Eliminar',
                    style: TextStyle(color: Colors.red[400]),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _handleMenuAction(String action, WebsitePage page) async {
    final service = context.read<WebsiteService>();

    switch (action) {
      case 'settings':
        _showPageDialog(context, page: page);
        break;
      case 'publish':
      case 'unpublish':
        await service.togglePagePublished(page.id, action == 'publish');
        await _loadPages();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(action == 'publish'
                  ? 'Página publicada'
                  : 'Página despublicada'),
            ),
          );
        }
        break;
      case 'set_home':
        await service.setHomePage(page.id);
        await _loadPages();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Página establecida como inicio')),
          );
        }
        break;
      case 'copy_url':
        final url = '${Uri.base.origin}/${page.slug}';
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('URL copiada al portapapeles')),
          );
        }
        break;
      case 'delete':
        _confirmDelete(page);
        break;
    }
  }

  void _openPageEditor(WebsitePage page) {
    // Dec 2025+: Multi-page inline editing supported via DynamicWebsitePage + query params.
    // Use legacy /tienda/* routes on ERP host (root '/' is reserved for ERP).
    final path = page.isHome ? '/tienda' : '/tienda/pagina/${page.slug}';
    context.go('$path?edit=true');
  }

  void _confirmDelete(WebsitePage page) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Página'),
        content: Text(
          '¿Estás seguro de que quieres eliminar "${page.title}"?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await context.read<WebsiteService>().deletePage(page.id);
                await _loadPages();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Página eliminada')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al eliminar: $e')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showPageDialog(BuildContext context, {WebsitePage? page}) {
    showDialog(
      context: context,
      builder: (context) => _PageFormDialog(
        page: page,
        onSaved: () => _loadPages(),
      ),
    );
  }

  // Template helpers
  IconData _getTemplateIcon(PageTemplate template) {
    switch (template) {
      case PageTemplate.landing:
        return Icons.rocket_launch_outlined;
      case PageTemplate.blog:
        return Icons.article_outlined;
      case PageTemplate.productList:
        return Icons.shopping_bag_outlined;
      case PageTemplate.productDetail:
        return Icons.inventory_2_outlined;
      case PageTemplate.cart:
        return Icons.shopping_cart_outlined;
      default:
        return Icons.web_outlined;
    }
  }

  Color _getTemplateColor(PageTemplate template) {
    switch (template) {
      case PageTemplate.landing:
        return Colors.purple;
      case PageTemplate.blog:
        return Colors.blue;
      case PageTemplate.productList:
        return Colors.orange;
      case PageTemplate.productDetail:
        return Colors.teal;
      case PageTemplate.cart:
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  String _getTemplateName(PageTemplate template) {
    switch (template) {
      case PageTemplate.landing:
        return 'Landing';
      case PageTemplate.blog:
        return 'Blog';
      case PageTemplate.productList:
        return 'Productos';
      case PageTemplate.productDetail:
        return 'Detalle';
      case PageTemplate.cart:
        return 'Carrito';
      default:
        return 'Estándar';
    }
  }
}

// =============================================================================
// PAGE FORM DIALOG
// =============================================================================

class _PageFormDialog extends StatefulWidget {
  final WebsitePage? page;
  final VoidCallback onSaved;

  const _PageFormDialog({
    this.page,
    required this.onSaved,
  });

  @override
  State<_PageFormDialog> createState() => _PageFormDialogState();
}

class _PageFormDialogState extends State<_PageFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _slugController;
  late TextEditingController _metaTitleController;
  late TextEditingController _metaDescriptionController;
  late TextEditingController _metaKeywordsController;
  PageTemplate _selectedTemplate = PageTemplate.defaultTemplate;
  bool _isPublished = false;
  bool _isSubmitting = false;
  bool _autoSlug = true;

  bool get isEditing => widget.page != null;

  @override
  void initState() {
    super.initState();
    final page = widget.page;
    _titleController = TextEditingController(text: page?.title ?? '');
    _slugController = TextEditingController(text: page?.slug ?? '');
    _metaTitleController = TextEditingController(text: page?.metaTitle ?? '');
    _metaDescriptionController =
        TextEditingController(text: page?.metaDescription ?? '');
    _metaKeywordsController =
        TextEditingController(text: page?.metaKeywords ?? '');
    _selectedTemplate = page?.template ?? PageTemplate.defaultTemplate;
    _isPublished = page?.isPublished ?? false;
    _autoSlug = page == null; // Only auto-generate slug for new pages

    _titleController.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (_autoSlug && !isEditing) {
      _slugController.text = _generateSlug(_titleController.text);
    }
  }

  String _generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _slugController.dispose();
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    _metaKeywordsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isEditing ? 'Editar Página' : 'Nueva Página',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 32),

                // Form content
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic info section
                        Text(
                          'Información Básica',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Title
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Título de la Página *',
                            hintText: 'Ej: Sobre Nosotros',
                            prefixIcon: Icon(Icons.title),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'El título es requerido';
                            }
                            return null;
                          },
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),

                        // Slug
                        TextFormField(
                          controller: _slugController,
                          decoration: InputDecoration(
                            labelText: 'URL (slug) *',
                            hintText: 'sobre-nosotros',
                            prefixIcon: const Icon(Icons.link),
                            prefixText: '/',
                            suffixIcon: _autoSlug && !isEditing
                                ? Tooltip(
                                    message: 'Auto-generado desde el título',
                                    child: Icon(
                                      Icons.auto_fix_high,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            if (!isEditing) _autoSlug = false;
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'El slug es requerido';
                            }
                            if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
                              return 'Solo letras minúsculas, números y guiones';
                            }
                            return null;
                          },
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),

                        // Template dropdown
                        DropdownButtonFormField<PageTemplate>(
                          value: _selectedTemplate,
                          decoration: const InputDecoration(
                            labelText: 'Plantilla',
                            prefixIcon: Icon(Icons.layers_outlined),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: PageTemplate.defaultTemplate,
                              child: _buildTemplateItem(
                                'Estándar',
                                'Página con bloques editables',
                                Icons.web_outlined,
                              ),
                            ),
                            DropdownMenuItem(
                              value: PageTemplate.landing,
                              child: _buildTemplateItem(
                                'Landing Page',
                                'Página promocional de una sola vista',
                                Icons.rocket_launch_outlined,
                              ),
                            ),
                            DropdownMenuItem(
                              value: PageTemplate.blog,
                              child: _buildTemplateItem(
                                'Blog',
                                'Para artículos y noticias',
                                Icons.article_outlined,
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedTemplate = value);
                            }
                          },
                        ),

                        const SizedBox(height: 24),

                        // SEO section
                        Text(
                          'SEO (Opcional)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Meta title
                        TextFormField(
                          controller: _metaTitleController,
                          decoration: const InputDecoration(
                            labelText: 'Meta Título',
                            hintText: 'Título para buscadores',
                            prefixIcon: Icon(Icons.search),
                            helperText: 'Si está vacío, se usa el título',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),

                        // Meta description
                        TextFormField(
                          controller: _metaDescriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Meta Descripción',
                            hintText: 'Descripción para buscadores',
                            prefixIcon: Icon(Icons.description_outlined),
                          ),
                          maxLines: 2,
                          maxLength: 160,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),

                        // Meta keywords
                        TextFormField(
                          controller: _metaKeywordsController,
                          decoration: const InputDecoration(
                            labelText: 'Palabras Clave',
                            hintText: 'bicicletas, tienda, santiago',
                            prefixIcon: Icon(Icons.tag),
                            helperText: 'Separadas por comas',
                          ),
                          textInputAction: TextInputAction.done,
                        ),

                        const SizedBox(height: 24),

                        // Publish toggle
                        SwitchListTile(
                          value: _isPublished,
                          onChanged: (value) =>
                              setState(() => _isPublished = value),
                          title: const Text('Publicar página'),
                          subtitle: Text(
                            _isPublished
                                ? 'La página será visible públicamente'
                                : 'La página estará oculta (borrador)',
                          ),
                          secondary: Icon(
                            _isPublished ? Icons.public : Icons.visibility_off,
                            color: _isPublished ? Colors.green : Colors.orange,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 32),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isSubmitting ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(isEditing ? Icons.save : Icons.add),
                      label: Text(isEditing ? 'Guardar' : 'Crear Página'),
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

  Widget _buildTemplateItem(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final service = context.read<WebsiteService>();

      final pageData = WebsitePage(
        id: widget.page?.id ?? '',
        tenantId: widget.page?.tenantId ?? '',
        slug: _slugController.text.trim(),
        title: _titleController.text.trim(),
        metaTitle: _metaTitleController.text.trim().isEmpty
            ? null
            : _metaTitleController.text.trim(),
        metaDescription: _metaDescriptionController.text.trim().isEmpty
            ? null
            : _metaDescriptionController.text.trim(),
        metaKeywords: _metaKeywordsController.text.trim().isEmpty
            ? null
            : _metaKeywordsController.text.trim(),
        isPublished: _isPublished,
        isHome: widget.page?.isHome ?? false,
        isSystem: widget.page?.isSystem ?? false,
        template: _selectedTemplate,
        createdAt: widget.page?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (isEditing) {
        await service.updatePage(pageData);
      } else {
        await service.createPage(pageData);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'Página actualizada'
                : 'Página creada exitosamente'),
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
        setState(() => _isSubmitting = false);
      }
    }
  }
}
