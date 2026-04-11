import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../providers/public_store_tenant_provider.dart';
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
    final primaryColor =
      _parseColor(eff('theme_primary_color', websiteService.getSetting('theme_primary_color', ''))) ??
        const Color(0xFF2E7D32);
    final accentColor =
      _parseColor(eff('theme_accent_color', websiteService.getSetting('theme_accent_color', ''))) ??
        const Color(0xFFFF6F00);
    final headingFont = eff(
      'theme_heading_font',
      websiteService.getSetting('theme_heading_font', 'Roboto'),
    );
    final bodyFont = eff(
      'theme_body_font',
      websiteService.getSetting('theme_body_font', 'Roboto'),
    );
    final headingSize = double.tryParse(
        eff('theme_heading_size', websiteService.getSetting('theme_heading_size', '48')),
      ) ??
      48.0;
    final bodySize = double.tryParse(
        eff('theme_body_size', websiteService.getSetting('theme_body_size', '16')),
      ) ??
      16.0;
    final sectionSpacing = double.tryParse(
        eff('theme_section_spacing', websiteService.getSetting('theme_section_spacing', '64')),
      ) ??
      64.0;
    final textColor =
      _parseColor(eff('theme_text_color', websiteService.getSetting('theme_text_color', ''))) ??
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
                style:
                    TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.7)),
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
            style: TextStyle(fontSize: 18, color: textColor.withValues(alpha: 0.7)),
          ),
        ),
      );
    }

    final tenantId = context.read<PublicStoreTenantProvider>().tenantId;

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
            onNavigate: (route) => PublicStoreLayout.navigateToHref(context, route),
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
            onNavigate: (route) => PublicStoreLayout.navigateToHref(context, route),
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
