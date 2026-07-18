import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/website_destination.dart';
import '../services/website_destination_audit_service.dart';
import '../widgets/website_admin_ui.dart';

enum _DestinationFilter { all, attention, pages, catalog, external }

/// Configuration companion for every CTA/link saved by the Website Editor.
///
/// This page deliberately does not mirror every CTA into navigation. It shows
/// which canonical entity owns each destination, whether it is publish-ready,
/// where it is used, and whether it is intentionally exposed in a menu.
class WebsiteDestinationManagementPage extends StatefulWidget {
  const WebsiteDestinationManagementPage({
    super.key,
    this.embedded = false,
    this.onOpenPages,
    this.onOpenNavigation,
    this.onOpenCatalogProducts,
    this.onOpenCatalogCategories,
    this.loadAudit,
  });

  final bool embedded;
  final VoidCallback? onOpenPages;
  final VoidCallback? onOpenNavigation;
  final VoidCallback? onOpenCatalogProducts;
  final VoidCallback? onOpenCatalogCategories;
  final Future<WebsiteDestinationAudit> Function()? loadAudit;

  @override
  State<WebsiteDestinationManagementPage> createState() =>
      _WebsiteDestinationManagementPageState();
}

class _WebsiteDestinationManagementPageState
    extends State<WebsiteDestinationManagementPage> {
  final _searchController = TextEditingController();
  late Future<WebsiteDestinationAudit> _auditFuture;
  _DestinationFilter _filter = _DestinationFilter.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _auditFuture =
        widget.loadAudit?.call() ?? WebsiteDestinationAuditService().load();
  }

  @override
  Widget build(BuildContext context) {
    return WebsiteAdminShell(
      embedded: widget.embedded,
      title: 'Destinos y enlaces',
      description:
          'Comprueba que botones, menús y campañas lleguen al lugar correcto.',
      actions: [
        IconButton.outlined(
          tooltip: 'Actualizar auditoría',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
      ],
      child: FutureBuilder<WebsiteDestinationAudit>(
        future: _auditFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildError(snapshot.error);
          }
          return _buildContent(
              snapshot.data ?? const WebsiteDestinationAudit(items: []));
        },
      ),
    );
  }

  Widget _buildContent(WebsiteDestinationAudit audit) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final items = audit.items.where((item) {
      final matchesFilter = switch (_filter) {
        _DestinationFilter.all => true,
        _DestinationFilter.attention => item.needsAttention,
        _DestinationFilter.pages => item.kind == WebsiteDestinationKind.page ||
            item.kind == WebsiteDestinationKind.system,
        _DestinationFilter.catalog =>
          item.kind == WebsiteDestinationKind.category ||
              item.kind == WebsiteDestinationKind.product,
        _DestinationFilter.external =>
          item.kind == WebsiteDestinationKind.external ||
              item.kind == WebsiteDestinationKind.anchor ||
              item.kind == WebsiteDestinationKind.custom,
      };
      if (!matchesFilter || query.isEmpty) return matchesFilter;
      final haystack = <String>[
        item.title,
        item.href,
        item.message,
        ...item.pageNames,
        ...item.sourceLabels,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WebsiteAdminMetricStrip(
                metrics: [
                  WebsiteAdminMetric(
                    label: 'Destinos listos',
                    value: '${audit.readyCount}',
                    icon: Icons.check_circle_outline_rounded,
                    accent: const Color(0xFF19A974),
                  ),
                  WebsiteAdminMetric(
                    label: 'Requieren revisión',
                    value: '${audit.warningCount}',
                    icon: Icons.warning_amber_rounded,
                    accent: const Color(0xFFF28C28),
                  ),
                  WebsiteAdminMetric(
                    label: 'Enlaces rotos',
                    value: '${audit.brokenCount}',
                    icon: Icons.link_off_rounded,
                    accent: const Color(0xFFD14343),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 17, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '“Solo campaña” indica que el enlace no está en el menú; no es un error.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openNavigation,
                    child: const Text('Administrar menú'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Buscar página, ruta o bloque…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  );
                  final filters = SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_DestinationFilter>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(
                            value: _DestinationFilter.all,
                            label: Text('Todos')),
                        ButtonSegment(
                            value: _DestinationFilter.attention,
                            label: Text('Requieren atención')),
                        ButtonSegment(
                            value: _DestinationFilter.pages,
                            label: Text('Páginas')),
                        ButtonSegment(
                            value: _DestinationFilter.catalog,
                            label: Text('Catálogo')),
                        ButtonSegment(
                            value: _DestinationFilter.external,
                            label: Text('Otros')),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (selection) {
                        setState(() => _filter = selection.first);
                      },
                    ),
                  );
                  if (constraints.maxWidth < 900) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        search,
                        const SizedBox(height: 8),
                        filters,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 320, child: search),
                      const SizedBox(width: 12),
                      Expanded(child: filters),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _buildEmpty(audit.items.isEmpty)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 46,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) =>
                      _buildDestinationRow(items[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildDestinationRow(WebsiteDestinationAuditItem item) {
    final theme = Theme.of(context);
    final status = _statusVisual(item.health, theme);
    final pages = item.pageNames.isEmpty
        ? 'Navegación'
        : item.pageNames.take(2).join(', ');
    final navigation = item.navigationLocations.isEmpty
        ? 'Solo campaña'
        : item.navigationLocations.join(' + ');

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: status.$2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(status.$1, size: 18, color: status.$3),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    item.href,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 3),
                  Text(
                    '$pages · ${item.usageCount} uso${item.usageCount == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              constraints: const BoxConstraints(minWidth: 104),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                navigation,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _ownerAction(item.owner),
              child: Text(_ownerActionLabel(item.owner)),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, Color) _statusVisual(
    WebsiteDestinationHealth health,
    ThemeData theme,
  ) {
    return switch (health) {
      WebsiteDestinationHealth.ready => (
          Icons.check_circle_outline,
          theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
          theme.colorScheme.primary,
        ),
      WebsiteDestinationHealth.warning => (
          Icons.warning_amber_rounded,
          Colors.amber.withValues(alpha: 0.13),
          Colors.amber.shade800,
        ),
      WebsiteDestinationHealth.broken => (
          Icons.error_outline,
          theme.colorScheme.errorContainer,
          theme.colorScheme.error,
        ),
    };
  }

  VoidCallback? _ownerAction(WebsiteDestinationOwner owner) {
    return switch (owner) {
      WebsiteDestinationOwner.pages => _openPages,
      WebsiteDestinationOwner.catalogCategories => _openCatalogCategories,
      WebsiteDestinationOwner.catalogProducts => _openCatalogProducts,
      WebsiteDestinationOwner.navigation => _openNavigation,
      WebsiteDestinationOwner.advanced || WebsiteDestinationOwner.none => null,
    };
  }

  String _ownerActionLabel(WebsiteDestinationOwner owner) {
    return switch (owner) {
      WebsiteDestinationOwner.pages => 'Páginas',
      WebsiteDestinationOwner.catalogCategories => 'Categorías',
      WebsiteDestinationOwner.catalogProducts => 'Productos',
      WebsiteDestinationOwner.navigation => 'Menú',
      WebsiteDestinationOwner.advanced => 'Avanzado',
      WebsiteDestinationOwner.none => 'Listo',
    };
  }

  void _openPages() {
    if (widget.onOpenPages != null) return widget.onOpenPages!();
    context.go('/website/pages');
  }

  void _openNavigation() {
    if (widget.onOpenNavigation != null) return widget.onOpenNavigation!();
    context.go('/website/navigation');
  }

  void _openCatalogProducts() {
    if (widget.onOpenCatalogProducts != null) {
      return widget.onOpenCatalogProducts!();
    }
    context.go('/website/product-visibility?section=categories');
  }

  void _openCatalogCategories() {
    if (widget.onOpenCatalogCategories != null) {
      return widget.onOpenCatalogCategories!();
    }
    context.go('/website/product-visibility');
  }

  Widget _buildError(Object? error) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 12),
            const Text('No se pudieron revisar los destinos.'),
            const SizedBox(height: 6),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => setState(_reload),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool hasNoDestinations) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_tree_outlined, size: 42),
          const SizedBox(height: 10),
          Text(hasNoDestinations
              ? 'Todavía no hay destinos guardados.'
              : 'Ningún destino coincide con el filtro.'),
        ],
      ),
    );
  }
}
