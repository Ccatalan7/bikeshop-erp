import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../theme/public_store_theme.dart';
import '../widgets/public_store_layout.dart';

/// Policy page renderer that uses WebsiteService for caching.
/// Much simpler than the old StaticPolicyPage - no duplicate DB logic!
class StaticPolicyPage extends StatefulWidget {
  final String slug;
  final String fallbackTitle;

  const StaticPolicyPage(
      {super.key, required this.slug, required this.fallbackTitle});

  @override
  State<StaticPolicyPage> createState() => _StaticPolicyPageState();
}

class _PublicPolicyView extends StatelessWidget {
  final String slug;
  final String fallbackTitle;
  final List<Map<String, dynamic>> blocks;

  const _PublicPolicyView({
    required this.slug,
    required this.fallbackTitle,
    required this.blocks,
  });

  static const _ink = PublicStoreTheme.textPrimary;
  static const _muted = PublicStoreTheme.textSecondary;
  static const _line = PublicStoreTheme.divider;

  @override
  Widget build(BuildContext context) {
    final meta = _PolicyMeta.forSlug(slug, fallbackTitle);
    final sections = _extractSections(blocks, meta.fallbackBody);

    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 768;

                if (!isDesktop) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PolicyHero(meta: meta),
                      const SizedBox(height: 32),
                      _PolicyNav(currentSlug: slug, isDesktop: false),
                      const SizedBox(height: 32),
                      _PolicyContent(sections: sections),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 240,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PolicyHero(meta: meta),
                          const SizedBox(height: 32),
                          _PolicyNav(currentSlug: slug, isDesktop: true),
                        ],
                      ),
                    ),
                    const SizedBox(width: 64),
                    Expanded(
                      child: _PolicyContent(sections: sections),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<_PolicySection> _extractSections(
    List<Map<String, dynamic>> source,
    String fallback,
  ) {
    final visible = source
        .where((block) => block['is_visible'] != false)
        .toList(growable: false);
    visible.sort(
        (a, b) => _toInt(a['order_index']).compareTo(_toInt(b['order_index'])));

    final sections = <_PolicySection>[];
    for (final block in visible) {
      final type = (block['block_type'] ?? '').toString().toLowerCase();
      final data = block['block_data'] is Map
          ? Map<String, dynamic>.from(block['block_data'] as Map)
          : <String, dynamic>{};

      if (type == 'hero') continue;

      final title = _clean(data['title']);
      final subtitle = _clean(data['subtitle']);
      final content = _clean(data['content']);

      if (type == 'features') {
        final items = <_PolicyItem>[];
        final features = data['features'];
        if (features is List) {
          for (final feature in features) {
            if (feature is! Map) continue;
            final map = Map<String, dynamic>.from(feature);
            final itemTitle = _clean(map['title']);
            final itemBody = _clean(map['description']);
            if (itemTitle.isEmpty && itemBody.isEmpty) continue;
            items.add(_PolicyItem(itemTitle, itemBody));
          }
        }
        if (items.isNotEmpty) {
          sections.add(_PolicySection(
            title.isEmpty ? 'Puntos importantes' : title,
            const [],
            items,
          ));
        }
        continue;
      }

      if (type == 'faq') {
        final items = <_PolicyItem>[];
        final faqItems = data['items'];
        if (faqItems is List) {
          for (final item in faqItems) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);
            final question = _clean(map['question']);
            final answer = _clean(map['answer']);
            if (question.isEmpty && answer.isEmpty) continue;
            items.add(_PolicyItem(question, answer));
          }
        }
        if (items.isNotEmpty) {
          sections.add(_PolicySection(
            title.isEmpty ? 'Preguntas frecuentes' : title,
            const [],
            items,
          ));
        }
        continue;
      }

      final paragraphs = [
        ..._paragraphs(subtitle),
        ..._paragraphs(content),
      ];
      if (title.isNotEmpty || paragraphs.isNotEmpty) {
        sections.add(_PolicySection(
          title.isEmpty ? 'Detalle' : title,
          paragraphs,
          const [],
        ));
      }
    }

    if (sections.isNotEmpty) return sections;
    return [_PolicySection('Información', _paragraphs(fallback), const [])];
  }

  static String _clean(dynamic value) {
    return (value ?? '')
        .toString()
        .replaceAll('vinabikechile@gmail.com', 'contacto@vinabike.cl')
        .replaceAll(r'\n', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  static List<String> _paragraphs(String text) {
    final clean = _clean(text);
    if (clean.isEmpty) return const [];
    return clean
        .split(RegExp(r'\n\s*\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _PolicyHero extends StatelessWidget {
  final _PolicyMeta meta;

  const _PolicyHero({required this.meta});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(meta.icon, color: meta.color, size: 24),
        ),
        const SizedBox(height: 24),
        Text(
          meta.title,
          style: const TextStyle(
            fontFamily: null,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.5,
            color: _PublicPolicyView._ink,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          meta.summary,
          style: const TextStyle(
            fontSize: 16,
            height: 1.5,
            color: _PublicPolicyView._muted,
          ),
        ),
      ],
    );
  }
}

class _PolicyNav extends StatelessWidget {
  final String currentSlug;
  final bool isDesktop;

  const _PolicyNav({required this.currentSlug, this.isDesktop = false});

  @override
  Widget build(BuildContext context) {
    const slugs = [
      'nosotros',
      'envios',
      'devoluciones',
      'terminos',
      'privacidad'
    ];

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final slug in slugs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NavButton(
                slug: slug,
                isSelected: currentSlug == slug,
                onTap: () =>
                    PublicStoreLayout.navigateToHref(context, '/$slug'),
              ),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final slug in slugs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: currentSlug == slug,
                label: Text(_PolicyMeta.forSlug(slug, slug).navLabel),
                avatar: Icon(
                  _PolicyMeta.forSlug(slug, slug).icon,
                  size: 16,
                  color: currentSlug == slug
                      ? _PublicPolicyView._ink
                      : _PublicPolicyView._muted,
                ),
                onSelected: (_) =>
                    PublicStoreLayout.navigateToHref(context, '/$slug'),
                selectedColor: const Color(0xFFF1F5F9),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: currentSlug == slug
                      ? Colors.transparent
                      : _PublicPolicyView._line,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                labelStyle: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      currentSlug == slug ? FontWeight.w700 : FontWeight.w500,
                  color: currentSlug == slug
                      ? _PublicPolicyView._ink
                      : _PublicPolicyView._muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String slug;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavButton({
    required this.slug,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _PolicyMeta.forSlug(slug, slug);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: const Color(0xFFF8FAFC),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF1F5F9) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              meta.icon,
              size: 18,
              color: isSelected
                  ? _PublicPolicyView._ink
                  : _PublicPolicyView._muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                meta.navLabel,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? _PublicPolicyView._ink
                      : _PublicPolicyView._muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyContent extends StatelessWidget {
  final List<_PolicySection> sections;

  const _PolicyContent({required this.sections});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 48),
          Text(
            sections[i].title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: _PublicPolicyView._ink,
            ),
          ),
          const SizedBox(height: 16),
          for (final paragraph in sections[i].paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                paragraph,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.65,
                  color: _PublicPolicyView._muted,
                ),
              ),
            ),
          if (sections[i].items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final item in sections[i].items)
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 260, maxWidth: 500),
                      child: _PolicyItemCard(item: item),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _PolicyItemCard extends StatelessWidget {
  final _PolicyItem item;

  const _PolicyItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.title.isNotEmpty)
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _PublicPolicyView._ink,
              ),
            ),
          if (item.title.isNotEmpty && item.body.isNotEmpty)
            const SizedBox(height: 8),
          if (item.body.isNotEmpty)
            Text(
              item.body,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Color(0xFF475569),
              ),
            ),
        ],
      ),
    );
  }
}

class _PolicyMeta {
  final String title;
  final String navLabel;
  final String summary;
  final IconData icon;
  final Color color;
  final List<String> chips;
  final String fallbackBody;

  const _PolicyMeta({
    required this.title,
    required this.navLabel,
    required this.summary,
    required this.icon,
    required this.color,
    required this.chips,
    required this.fallbackBody,
  });

  static _PolicyMeta forSlug(String slug, String fallbackTitle) {
    switch (slug) {
      case 'nosotros':
        return const _PolicyMeta(
          title: 'Sobre Viñabike',
          navLabel: 'Nosotros',
          summary:
              'Tienda, taller y repuestos para bicicletas en Viña del Mar.',
          icon: Icons.storefront_outlined,
          color: PublicStoreTheme.primaryBlue,
          chips: ['Viña del Mar', 'Tienda física', 'Taller'],
          fallbackBody:
              'Viñabike es el nombre comercial de NEWEN SpA, RUT 77.541.999-7, con domicilio en Álvarez 32, Local 17, Viña del Mar. Vendemos bicicletas, repuestos y accesorios, y realizamos mantenciones y reparaciones.',
        );
      case 'envios':
        return const _PolicyMeta(
          title: 'Envíos',
          navLabel: 'Envíos',
          summary: 'Retiro en tienda y despacho dentro de Chile según destino.',
          icon: Icons.local_shipping_outlined,
          color: Color(0xFF2E7D32),
          chips: ['Chile', '3-12 días hábiles', 'Costo según pedido'],
          fallbackBody:
              'Despachamos a Chile continental en 3 a 12 días hábiles: \$6.990 hasta \$29.999; \$8.990 entre \$30.000 y \$79.999; \$11.990 entre \$80.000 y \$149.999; y \$14.990 desde \$150.000. El checkout muestra y suma el costo exacto antes de pagar. El retiro en Álvarez 32, Local 17, Viña del Mar no tiene costo.',
        );
      case 'devoluciones':
        return const _PolicyMeta(
          title: 'Devoluciones',
          navLabel: 'Devoluciones',
          summary: 'Condiciones claras para cambios, devoluciones y garantías.',
          icon: Icons.assignment_return_outlined,
          color: PublicStoreTheme.primaryBlue,
          chips: ['10 días', 'Cambios disponibles', 'Soporte directo'],
          fallbackBody:
              'En compras a distancia puedes ejercer el retracto dentro de 10 días desde la recepción, antes de usar el producto y devolviéndolo en buen estado. Si no recibes confirmación escrita, el plazo legal puede extenderse a 90 días. La garantía legal se mantiene y una oferta o liquidación no la elimina. Para iniciar el proceso escribe a ventas@vinabike.cl con tu número de pedido.',
        );
      case 'terminos':
        return const _PolicyMeta(
          title: 'Términos y condiciones',
          navLabel: 'Términos',
          summary: 'Condiciones generales para comprar en la tienda online.',
          icon: Icons.gavel_outlined,
          color: Color(0xFFB45309),
          chips: ['CLP', 'Stock sujeto a disponibilidad', 'Compra segura'],
          fallbackBody:
              'Este sitio es operado por NEWEN SpA, RUT 77.541.999-7, bajo el nombre comercial Viñabike. Los precios se publican en pesos chilenos (CLP) e incluyen los impuestos informados. Antes de confirmar mostramos productos, despacho y total; la compra se confirma una vez validado el pago y el stock reservado.',
        );
      case 'privacidad':
        return const _PolicyMeta(
          title: 'Privacidad',
          navLabel: 'Privacidad',
          summary: 'Uso de datos personales para pedidos, soporte y atención.',
          icon: Icons.shield_outlined,
          color: PublicStoreTheme.primaryBlue,
          chips: ['Pedidos', 'Soporte', 'Sin venta de datos'],
          fallbackBody:
              'Usamos los datos personales entregados por clientes para procesar pedidos, coordinar entregas, responder consultas y entregar soporte. No vendemos datos personales a terceros.',
        );
      default:
        return _PolicyMeta(
          title: fallbackTitle,
          navLabel: fallbackTitle,
          summary: 'Información de la tienda.',
          icon: Icons.info_outline,
          color: PublicStoreTheme.primaryBlue,
          chips: const ['Viñabike'],
          fallbackBody: 'Información de la tienda.',
        );
    }
  }
}

class _PolicySection {
  final String title;
  final List<String> paragraphs;
  final List<_PolicyItem> items;

  const _PolicySection(this.title, this.paragraphs, this.items);
}

class _PolicyItem {
  final String title;
  final String body;

  const _PolicyItem(this.title, this.body);
}

class _StaticPolicyPageState extends State<StaticPolicyPage>
    with AutomaticKeepAliveClientMixin {
  static const List<String> _policySlugs = <String>[
    'nosotros',
    'terminos',
    'privacidad',
    'devoluciones',
    'envios',
  ];

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _blocks = [];
  String? _pageId;
  bool _editModeChecked = false;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // If we have cached blocks, render immediately (no 1-frame spinner flicker).
    final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
    if (tenantId != null && tenantId.isNotEmpty) {
      final websiteService = context.read<WebsiteService>();
      final snapshot = websiteService.peekPageWithBlocks(
        widget.slug,
        tenantId: tenantId,
      );
      if (snapshot != null) {
        _pageId = snapshot.page.id;
        _blocks = snapshot.blocks;
        _loading = false;
      }
    }

    _loadPage();
  }

  @override
  void didUpdateWidget(covariant StaticPolicyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      _editModeChecked = false;
      _loadPage();
    }
  }

  bool _providerHasBlocksForThisPage(WebsiteEditModeProvider editProvider) {
    if (_pageId == null) return false;

    final contextMatches = (editProvider.currentPageId == _pageId) ||
        (editProvider.currentPageSlug == widget.slug);
    if (!contextMatches) return false;

    final providerBlocks = editProvider.blocks;
    if (providerBlocks.isEmpty) return false;

    // If blocks include page_id, ensure they match this page.
    final hasPageId = providerBlocks.any((b) => b['page_id'] != null);
    if (!hasPageId) return true;

    return providerBlocks
        .every((b) => b['page_id']?.toString() == _pageId.toString());
  }

  void _updateEditProviderIfNeeded() {
    if (!mounted) return;
    // This page is kept alive across tab/branch navigation. Only the active
    // (ticker-enabled) branch should be allowed to sync the editor provider;
    // otherwise offstage pages will fight over currentPageSlug/blocks.
    if (!TickerMode.of(context)) return;
    if (_loading || _pageId == null) return;

    final editProvider = context.read<WebsiteEditModeProvider>();

    // Only sync when we are already in editor context and the provider is
    // not actually synced to this page.
    if (!editProvider.isInEditorContext) return;
    if (_providerHasBlocksForThisPage(editProvider)) return;

    final websiteService = context.read<WebsiteService>();
    final blocks = List<Map<String, dynamic>>.from(_blocks);
    final settings = Map<String, dynamic>.from(websiteService.settings);

    debugPrint(
        '🔄 [StaticPolicyPage] Sync editor context: ${editProvider.currentPageSlug} → ${widget.slug} (${blocks.length} blocks)');

    // This resets selection/history for the new page (same as DynamicWebsitePage).
    if (editProvider.isEditMode) {
      editProvider.enterEditMode(
        blocks,
        settings,
        pageId: _pageId,
        pageSlug: widget.slug,
      );
    } else {
      editProvider.enterPreviewMode(
        blocks,
        settings,
        pageId: _pageId,
        pageSlug: widget.slug,
      );
    }
  }

  Future<void> _loadPage() async {
    final shouldShowSpinner = _blocks.isEmpty;
    if (shouldShowSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      // Keep rendering existing content; just clear previous error.
      _error = null;
    }

    try {
      // Get tenant from provider or authenticated user
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      String? tenantId = tenantProvider.tenantId;

      if (tenantId == null) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final profileResp = await Supabase.instance.client
              .from('user_profiles')
              .select('tenant_id')
              .eq('user_id', user.id)
              .maybeSingle();
          tenantId = profileResp?['tenant_id'] as String?;
        }
      }

      if (tenantId == null) {
        throw Exception('No tenant detected');
      }
      if (!mounted) return;

      // Use WebsiteService for cached page loading
      final websiteService = context.read<WebsiteService>();
      final cached = await websiteService.loadPageWithBlocks(
        widget.slug,
        tenantId: tenantId,
      );

      if (cached == null) {
        throw Exception('Página no encontrada');
      }

      _pageId = cached.page.id;
      _blocks = cached.blocks;

      // Prefetch other policy pages in the background so switching between them
      // is instant and doesn't show loading UI.
      _prefetchOtherPolicyPages(
          websiteService: websiteService, tenantId: tenantId);

      if (mounted) {
        setState(() => _loading = false);
      } else {
        _loading = false;
      }

      // If the user navigated here while already in edit/preview mode,
      // update the provider so the right panel can edit selected blocks.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateEditProviderIfNeeded();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      } else {
        _loading = false;
        _error = e.toString();
      }
    }
  }

  void _prefetchOtherPolicyPages({
    required WebsiteService websiteService,
    required String tenantId,
  }) {
    for (final slug in _policySlugs) {
      if (slug == widget.slug) continue;
      // Fire-and-forget.
      websiteService.loadPageWithBlocks(slug, tenantId: tenantId);
    }
  }

  void _checkEditModeFromRouter(BuildContext context) {
    if (_loading || _pageId == null) return;
    if (_editModeChecked) return;
    // Avoid entering edit/preview from an offstage kept-alive page.
    if (!TickerMode.of(context)) return;

    // URL params should only be used to ENTER editor context.
    // Once already inside the editor shell, ignore URL forcing to prevent
    // preview/edit bouncing on persistent shell routes.
    final editProvider = context.read<WebsiteEditModeProvider>();
    if (editProvider.isInEditorContext) {
      _editModeChecked = true;
      return;
    }

    final goRouterState = GoRouterState.of(context);
    final queryParams = goRouterState.uri.queryParameters;
    final shouldPreview = queryParams['preview'] == 'true';
    // If both are present, preview wins (prevents mode bouncing).
    final shouldEdit = !shouldPreview && queryParams['edit'] == 'true';

    if (!shouldEdit && !shouldPreview) return;
    _editModeChecked = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final websiteService = context.read<WebsiteService>();
      final blocks = List<Map<String, dynamic>>.from(_blocks);
      final settings = Map<String, dynamic>.from(websiteService.settings);

      if (shouldEdit) {
        editProvider.enterEditMode(
          blocks,
          settings,
          pageId: _pageId,
          pageSlug: widget.slug,
        );
      } else {
        editProvider.enterPreviewMode(
          blocks,
          settings,
          pageId: _pageId,
          pageSlug: widget.slug,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    _checkEditModeFromRouter(context);

    // If already in editor context and the user navigated without ?edit=true,
    // keep provider synced to this page so the editor panel can render fields.
    if (TickerMode.of(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateEditProviderIfNeeded();
      });
    }

    final editProvider = context.watch<WebsiteEditModeProvider>();
    final websiteService = context.watch<WebsiteService>();
    final isEditMode = editProvider.isEditMode;

    // Only use provider blocks if we are actually editing THIS page
    // This prevents showing homepage blocks when navigating to a policy page
    // without explicitly entering edit mode for that specific page.
    final matchesPage = (editProvider.currentPageId != null &&
            editProvider.currentPageId == _pageId) ||
        (editProvider.currentPageSlug != null &&
            editProvider.currentPageSlug == widget.slug);

    // Note: Auto-switching context between cached policy pages was removed
    // because it caused infinite loops. The _checkEditModeFromRouter handles
    // entering edit mode when navigating to a page with ?edit=true.
    // For context switching between already-cached pages, use block selection.

    // In editor context (preview or edit), render the provider blocks for THIS page.
    // This ensures switching to preview after saving shows the updated content.
    final blocksToRender = (editProvider.isInEditorContext && matchesPage)
        ? editProvider.blocks
        : _blocks;

    String eff(String key, String fallback) {
      if (editProvider.isInEditorContext) {
        return editProvider.getEffectiveThemeSetting(key, fallback);
      }
      return fallback;
    }

    // Get theme from WebsiteService (already cached), with live-preview overrides
    final primaryColor = _parseColor(eff('theme_primary_color',
            websiteService.getSetting('theme_primary_color', ''))) ??
        const Color(0xFF2E7D32);
    final accentColor = _parseColor(eff('theme_accent_color',
            websiteService.getSetting('theme_accent_color', ''))) ??
        const Color(0xFFFF6F00);
    final headingFont = eff(
      'theme_heading_font',
      websiteService.getSetting('theme_heading_font', 'Oswald'),
    );
    final bodyFont = eff(
      'theme_body_font',
      websiteService.getSetting('theme_body_font', 'Barlow'),
    );
    final headingSize = double.tryParse(
          eff('theme_heading_size',
              websiteService.getSetting('theme_heading_size', '48')),
        ) ??
        48.0;
    final bodySize = double.tryParse(
          eff('theme_body_size',
              websiteService.getSetting('theme_body_size', '16')),
        ) ??
        16.0;
    final sectionSpacing = double.tryParse(
          eff('theme_section_spacing',
              websiteService.getSetting('theme_section_spacing', '64')),
        ) ??
        64.0;
    final textColor = _parseColor(eff('theme_text_color',
            websiteService.getSetting('theme_text_color', ''))) ??
        Colors.black87;

    if (_loading && _blocks.isEmpty) {
      final minHeight = MediaQuery.sizeOf(context).height * 0.55;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                widget.fallbackTitle,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: textColor.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    if (_blocks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Esta página está en construcción',
            style: TextStyle(
                fontSize: 18, color: textColor.withValues(alpha: 0.7)),
          ),
        ),
      );
    }

    final tenantId = context.read<PublicStoreTenantProvider>().tenantId;

    if (!editProvider.isInEditorContext && !isEditMode) {
      return _PublicPolicyView(
        slug: widget.slug,
        fallbackTitle: widget.fallbackTitle,
        blocks: blocksToRender,
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          for (final block in blocksToRender) ...[
            Padding(
              padding: EdgeInsets.only(bottom: sectionSpacing),
              child: _buildBlockWidget(
                context: context,
                block: block,
                isEditMode: isEditMode,
                primaryColor: primaryColor,
                accentColor: accentColor,
                headingFont: headingFont,
                bodyFont: bodyFont,
                headingSize: headingSize,
                bodySize: bodySize,
                tenantId: tenantId,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBlockWidget({
    required BuildContext context,
    required Map<String, dynamic> block,
    required bool isEditMode,
    required Color primaryColor,
    required Color accentColor,
    required String headingFont,
    required String bodyFont,
    required double headingSize,
    required double bodySize,
    required String? tenantId,
  }) {
    final data = block['block_data'] as Map<String, dynamic>? ?? {};
    final isVisible = block['is_visible'] == true;
    final blockType = block['block_type']?.toString() ?? 'hero';
    final blockId = block['id']?.toString() ?? '';

    return isEditMode
        ? DeferredEditableBlockRenderer.build(
            context: context,
            blockId: blockId,
            blockType: blockType,
            data: data,
            primaryColor: primaryColor,
            accentColor: accentColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            headingSize: headingSize,
            bodySize: bodySize,
            onNavigate: (route) =>
                PublicStoreLayout.navigateToHref(context, route),
            isVisible: isVisible,
            tenantId: tenantId,
          )
        : WebsiteBlockRenderer.build(
            context: context,
            blockType: blockType,
            data: data,
            primaryColor: primaryColor,
            accentColor: accentColor,
            previewMode: false,
            headingFont: headingFont,
            bodyFont: bodyFont,
            headingSize: headingSize,
            bodySize: bodySize,
            onNavigate: (route) =>
                PublicStoreLayout.navigateToHref(context, route),
            tenantId: tenantId,
          );
  }

  Color? _parseColor(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      var cleaned = trimmed.toLowerCase();
      if (cleaned.startsWith('color(')) {
        cleaned = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
      }
      int? intValue = int.tryParse(cleaned);
      if (intValue == null && cleaned.startsWith('0x')) {
        intValue = int.tryParse(cleaned);
      }
      if (intValue == null) {
        cleaned = cleaned.replaceAll('#', '');
        intValue = int.tryParse(cleaned, radix: 16);
        if (intValue != null && cleaned.length <= 6) {
          intValue = 0xFF000000 | intValue;
        }
      }
      return intValue != null ? Color(intValue) : null;
    } catch (_) {
      return null;
    }
  }
}
