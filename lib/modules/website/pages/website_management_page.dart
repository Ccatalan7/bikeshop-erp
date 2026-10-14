import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/shop_time.dart';
import '../../../shared/widgets/asset_pdf_preview_dialog.dart';
import '../../../shared/widgets/module_start_page.dart';
import '../models/online_order_workflow_policy.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_service.dart';
import '../widgets/website_admin_ui.dart';
import '../widgets/website_editor_navigation_guard.dart';

/// Entry to the public website's workspaces.
///
/// The owner's definition (2026-10-14): the module's start page presents its
/// workspaces for orderly navigation, with almost no metrics. One continuous
/// page: a full-bleed chrome band with the site's state, the editor and four
/// figures, then the workspaces in columns split by hairlines — no floating
/// cards, no slogan, no decoration. Each figure and each workspace is a door
/// to the page that owns it.
class WebsiteManagementPage extends StatefulWidget {
  const WebsiteManagementPage({
    super.key,
    this.embedded = false,
    this.readPublication = readWebsiteHubPublication,
  });

  final bool embedded;

  /// Reads the live `release.json` of the store at `store_url`; a seam for
  /// tests.
  final Future<WebsiteHubPublication> Function(String storeUrl) readPublication;

  @override
  State<WebsiteManagementPage> createState() => _WebsiteManagementPageState();
}

class _WebsiteManagementPageState extends State<WebsiteManagementPage> {
  bool _isHydratingMetrics = true;
  WebsiteHubPublication? _publication;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final service = context.read<WebsiteService>();
      await service.initialize();
      await service.initializeOrders();
    } catch (error) {
      debugPrint('No se pudieron hidratar las métricas del sitio web: $error');
    } finally {
      if (mounted) setState(() => _isHydratingMetrics = false);
    }
    if (mounted) {
      // The store's origin is the site settings' own `store_url`, loaded with
      // them above; the band never reads the tenant directory.
      await _loadPublication(
        context.read<WebsiteService>().settings['store_url'] ?? '',
      );
    }
  }

  Future<void> _loadPublication(String storeUrl) async {
    WebsiteHubPublication publication;
    try {
      publication = await widget.readPublication(storeUrl);
    } catch (_) {
      publication = const WebsiteHubPublication(host: null, readFailed: true);
    }
    if (mounted) setState(() => _publication = publication);
  }

  /// The store's own domain; a native build has no web origin of its own.
  Uri? get _storeUri {
    final host = _publication?.host;
    if (host != null) return Uri.https(host, '/');
    final base = Uri.base;
    if (base.scheme == 'http' || base.scheme == 'https') {
      return Uri.parse('${base.origin}/tienda');
    }
    return null;
  }

  Future<void> _openStore() async {
    final uri = _storeUri;
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir una ventana externa.')),
    );
  }

  Future<void> _openInlineStore({required bool preview}) async {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final currentSlug = editProvider.currentPageSlug?.trim().toLowerCase();
    final keepsCurrentDocument =
        currentSlug == 'inicio' || currentSlug == 'home';
    final editorDecision = await WebsiteEditorNavigationGuard.authorize(
      context,
      intent: keepsCurrentDocument
          ? WebsiteEditorNavigationIntent.samePage
          : WebsiteEditorNavigationIntent.switchPage,
    );
    if (!editorDecision.isAllowed || !mounted) return;
    if (!editorDecision.commit()) return;
    context.go('/tienda?${preview ? 'preview' : 'edit'}=true');
  }

  Future<void> _openManual() {
    return showAssetPdfPreviewDialog(
      context,
      assetPath: 'assets/manuals/manual_sitio_web_ventas_online.pdf',
      title: 'Manual de sitio web y ventas online',
      description: 'Publicación, pedidos, pagos, documentos y excepciones.',
      fileName: 'manual_sitio_web_ventas_online.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    return WebsiteAdminShell(
      embedded: widget.embedded,
      showBack: false,
      title: 'Sitio web',
      description: '',
      actions: [
        IconButton(
          key: const ValueKey('website-hub-manual'),
          onPressed: _openManual,
          tooltip: 'Manual de sitio web y ventas',
          icon: const Icon(Icons.help_outline_rounded, size: 20),
        ),
        if (phone)
          IconButton(
            key: const ValueKey('website-hub-preview'),
            onPressed: () => _openInlineStore(preview: true),
            tooltip: 'Vista previa',
            icon: const Icon(Icons.visibility_outlined, size: 20),
          )
        else
          TextButton.icon(
            key: const ValueKey('website-hub-preview'),
            onPressed: () => _openInlineStore(preview: true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            icon: const Icon(Icons.visibility_outlined, size: 19),
            label: const Text('Vista previa'),
          ),
        IconButton(
          key: const ValueKey('website-hub-open-external'),
          onPressed: _openStore,
          tooltip: 'Abrir el sitio en otra ventana',
          icon: const Icon(Icons.north_east_rounded, size: 20),
        ),
      ],
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Consumer<WebsiteService>(
                builder: (context, service, _) => _band(
                  context,
                  phone: phone,
                  figures:
                      _isHydratingMetrics ? null : _SiteFigures.of(service),
                ),
              ),
              ModuleStartWorkspaces(
                phone: phone,
                title: 'Espacios de trabajo',
                groups: _groups(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _band(
    BuildContext context, {
    required bool phone,
    required _SiteFigures? figures,
  }) {
    final shell = VinabikeThemeRoles.of(context).shell;
    final status = _SiteStatus.of(_publication);
    void open(String route) => context.go(route);
    final editor = FilledButton.icon(
      key: const ValueKey('website-hub-open-editor'),
      onPressed: () => _openInlineStore(preview: false),
      style: ModuleStartBand.primaryStyle(context, phone: phone),
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: Text(phone ? 'Abrir editor' : 'Abrir editor visual'),
    );
    final dot = status.tone == _StatusTone.live
        ? shell.positive
        : shell.mutedForeground;
    return ModuleStartBand(
      phone: phone,
      lead: Row(
        children: [
          Container(
            width: phone ? 7 : 9,
            height: phone ? 7 : 9,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          SizedBox(width: phone ? 9 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: shell.foreground,
                    fontSize: phone ? 14.5 : 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  status.detail,
                  key: const ValueKey('website-hub-publication'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: shell.mutedForeground,
                    fontSize: phone ? 12 : 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!phone)
          OutlinedButton(
            key: const ValueKey('website-hub-open-site'),
            onPressed: _openStore,
            style: ModuleStartBand.outlineStyle(context),
            child: const Text('Ver sitio ↗'),
          ),
        editor,
      ],
      figures: [
        ModuleStartFigure(
          key: const ValueKey('website-hub-figure-sections'),
          label: 'Secciones visibles',
          shortLabel: 'Secciones visibles',
          value: figures == null ? null : '${figures.visibleSections}',
          caption: 'en la portada',
          onTap: () => _openInlineStore(preview: false),
        ),
        ModuleStartFigure(
          key: const ValueKey('website-hub-figure-featured'),
          label: 'Productos destacados',
          shortLabel: 'Destacados en portada',
          value: figures == null ? null : '${figures.featuredOnHome}',
          caption: figures == null
              ? null
              : !figures.homeShowsFeatured
                  ? 'la portada no los muestra'
                  : figures.featuredChosen > figures.featuredOnHome
                      ? 'en portada · ${figures.featuredChosen} elegidos'
                      : 'en la portada',
          onTap: () => open('/website/product-visibility?tab=featured'),
        ),
        ModuleStartFigure(
          key: const ValueKey('website-hub-figure-attend'),
          label: 'Pedidos por atender',
          shortLabel: 'Por atender',
          value: figures == null ? null : '${figures.ordersToAttend}',
          caption: figures == null
              ? null
              : figures.ordersToAttend == 0
                  ? 'todo al día'
                  : 'en la lista de pedidos',
          captionTone: figures == null
              ? ModuleStartCaptionTone.muted
              : figures.ordersToAttend == 0
                  ? ModuleStartCaptionTone.positive
                  : ModuleStartCaptionTone.attention,
          onTap: () => open('/website/orders'),
        ),
        ModuleStartFigure(
          key: const ValueKey('website-hub-figure-orders'),
          label: 'Pedidos históricos',
          shortLabel: 'Pedidos en total',
          value: figures == null ? null : '${figures.realOrders}',
          caption: figures == null
              ? null
              : figures.lastOrderAt == null
                  ? 'aún no hay pedidos'
                  : 'el último, ${_date(figures.lastOrderAt!)}',
          onTap: () => open('/website/orders'),
        ),
      ],
    );
  }

  List<ModuleStartGroup> _groups(BuildContext context) {
    ModuleStartEntry entry(
      String title,
      String description,
      IconData icon,
      String route,
    ) =>
        ModuleStartEntry(
          key: ValueKey('website-hub-workspace-$route'),
          title: title,
          description: description,
          icon: icon,
          onTap: () => context.go(route),
        );
    return [
      ModuleStartGroup(
        title: 'Contenido y estructura',
        description: 'Páginas, menús y enlaces',
        icon: Icons.dashboard_customize_outlined,
        tone: ModuleStartTone.a,
        entries: [
          entry('Páginas', 'Crea y ordena las páginas del sitio',
              Icons.description_outlined, '/website/pages'),
          entry('Navegación', 'Menús del encabezado y pie', Icons.menu_rounded,
              '/website/navigation'),
          entry('Destinos y enlaces', 'Comprueba rutas, botones y campañas',
              Icons.link_rounded, '/website/destinations'),
        ],
      ),
      ModuleStartGroup(
        title: 'Catálogo y ventas',
        description: 'Productos, pedidos y despacho',
        icon: Icons.storefront_outlined,
        tone: ModuleStartTone.c,
        entries: [
          entry(
              'Catálogo de la tienda',
              'Qué se vende online y qué falta resolver',
              Icons.storefront_outlined,
              '/website/product-visibility'),
          entry(
              'Productos destacados',
              'La selección principal de la portada',
              Icons.star_outline_rounded,
              '/website/product-visibility?tab=featured'),
          entry('Pedidos online', 'Revisa estados, pagos y entregas',
              Icons.shopping_bag_outlined, '/website/orders'),
          entry('Envíos', 'Despacho por región y retiro en tienda',
              Icons.local_shipping_outlined, '/website/shipping'),
        ],
      ),
      ModuleStartGroup(
        title: 'Configuración y alcance',
        description: 'Datos, conexiones y Google',
        icon: Icons.trending_up_rounded,
        tone: ModuleStartTone.b,
        entries: [
          entry('Configuración', 'Datos públicos y reglas de compra',
              Icons.tune_rounded, '/website/settings'),
          entry('Integraciones', 'Google, medición y canales externos',
              Icons.hub_outlined, '/website/integrations'),
          entry('SEO', 'Cómo aparece la tienda en buscadores',
              Icons.search_rounded, '/website/seo'),
          entry(
              'Presencia en internet',
              'Búsquedas, visitas e indexación, día a día',
              Icons.insights_rounded,
              '/website/presence'),
        ],
      ),
    ];
  }
}

/// The store's domain and when its live build was made.
///
/// The host is the site settings' `store_url` (the one canonical origin,
/// edited in Sitio web › Configuración). `release.json` is what it serves now
/// (the store build writes it:
/// commit, run, `built_at`), so «Última publicación» is the live site's own
/// word. The editor's publication ledger (20260728230000) has dispatch off
/// until its GitHub App exists, and push and daily builds do not report to
/// it, so it cannot date the site yet.
@immutable
class WebsiteHubPublication {
  const WebsiteHubPublication({
    required this.host,
    this.builtAt,
    this.readFailed = false,
  });

  final String? host;
  final DateTime? builtAt;
  final bool readFailed;
}

Future<WebsiteHubPublication> readWebsiteHubPublication(String storeUrl) async {
  final host = _cleanHost(storeUrl);
  if (host == null) return const WebsiteHubPublication(host: null);
  try {
    final response = await http
        .get(Uri.https(host, '/release.json'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      return WebsiteHubPublication(host: host, readFailed: true);
    }
    final json = jsonDecode(response.body);
    final builtAt =
        json is Map ? DateTime.tryParse('${json['built_at'] ?? ''}') : null;
    return WebsiteHubPublication(
      host: host,
      builtAt: builtAt,
      readFailed: builtAt == null,
    );
  } catch (_) {
    return WebsiteHubPublication(host: host, readFailed: true);
  }
}

String? _cleanHost(String raw) {
  var value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  final parsed = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  value = parsed?.host ?? '';
  if (value.isEmpty) return null;
  return value.startsWith('www.') ? value.substring(4) : value;
}

/// What the band says about the published site, in the shop's words.
@immutable
class _SiteStatus {
  const _SiteStatus({
    required this.title,
    required this.detail,
    required this.tone,
  });

  final String title;
  final String detail;
  final _StatusTone tone;

  static _SiteStatus of(WebsiteHubPublication? publication) {
    if (publication == null) {
      return const _SiteStatus(
        title: 'Sitio web',
        detail: 'Consultando la publicación…',
        tone: _StatusTone.quiet,
      );
    }
    final host = publication.host;
    final builtAt = publication.builtAt;
    if (host == null) {
      return _SiteStatus(
        title: 'Sitio web',
        detail: publication.readFailed
            ? 'No se pudo consultar la publicación'
            : 'Falta la dirección de la tienda',
        tone: _StatusTone.quiet,
      );
    }
    if (builtAt == null) {
      return _SiteStatus(
        title: host,
        detail: 'No se pudo leer la última publicación',
        tone: _StatusTone.quiet,
      );
    }
    return _SiteStatus(
      title: '$host en línea',
      detail: 'Última publicación: ${_dateTime(builtAt)}',
      tone: _StatusTone.live,
    );
  }
}

enum _StatusTone { live, quiet }

/// The four figures, computed the way the pages they open count them.
@immutable
class _SiteFigures {
  const _SiteFigures({
    required this.visibleSections,
    required this.featuredOnHome,
    required this.featuredChosen,
    required this.homeShowsFeatured,
    required this.ordersToAttend,
    required this.realOrders,
    required this.lastOrderAt,
  });

  final int visibleSections;
  final int featuredOnHome;
  final int featuredChosen;
  final bool homeShowsFeatured;
  final int ordersToAttend;
  final int realOrders;
  final DateTime? lastOrderAt;

  static _SiteFigures of(WebsiteService service) {
    final visible =
        service.blocks.where((block) => block['is_visible'] == true).toList();
    final chosen =
        service.featuredProducts.where((product) => product.active).length;
    // How many the home really shows: its visible products blocks that list
    // the featured ones each stop at their own `maxProducts` (2026-10-14: 16
    // chosen, 6 on the home).
    final featuredLimits = <int>[
      for (final block in visible)
        if ((block['block_type'] ?? block['type']) == 'products')
          if (WebsiteProductsBlockContract.fromData(_dataOf(block))
              case final contract when contract.productSource == 'featured')
            contract.maxProducts,
    ];
    final onHome = featuredLimits.isEmpty
        ? 0
        : math.min(chosen, featuredLimits.reduce(math.max));
    // Same numbers as the orders list: test orders are not sales, and «por
    // atender» is the list's own queue, not the raw `pending` status
    // (2026-10-13: 41 «por revisar» when one real order was waiting).
    final realOrders = service.orders.where((order) => !order.isTest).toList();
    final toAttend = realOrders
        .where(
          (order) =>
              OnlineOrderWorkflowPolicy.queueFor(
                status: order.status,
                paymentStatus: order.operationalPaymentStatus,
                paymentNeedsAttention: order.hasPaymentProcessingAttention,
              ) ==
              OnlineOrderQueue.attend,
        )
        .length;
    DateTime? lastOrderAt;
    for (final order in realOrders) {
      if (lastOrderAt == null || order.createdAt.isAfter(lastOrderAt)) {
        lastOrderAt = order.createdAt;
      }
    }
    return _SiteFigures(
      visibleSections: visible.length,
      featuredOnHome: onHome,
      featuredChosen: chosen,
      homeShowsFeatured: featuredLimits.isNotEmpty,
      ordersToAttend: toAttend,
      realOrders: realOrders.length,
      lastOrderAt: lastOrderAt,
    );
  }

  static Map<String, dynamic> _dataOf(Map<String, dynamic> block) {
    final raw = block['block_data'] ?? block['data'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }
}

const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

// On the shop's clock: the owner's Mac runs on Pacific time and showed the
// 15:59 build as 11:59 (2026-10-14).
String _date(DateTime value) {
  final local = shopTime(value);
  return '${local.day} ${_months[local.month - 1]}';
}

String _dateTime(DateTime value) {
  final local = shopTime(value);
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_date(local)}, $hour:$minute';
}
