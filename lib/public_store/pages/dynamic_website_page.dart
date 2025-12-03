import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_models.dart';
import '../../modules/website/models/website_page_models.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../shared/widgets/branded_loading.dart';
import '../theme/public_store_theme.dart';
import '../providers/public_store_tenant_provider.dart';

/// Dynamic page that renders website_blocks for any page based on slug
/// 
/// This widget:
/// 1. Loads the page by slug from website_pages
/// 2. Loads blocks associated with that page from website_blocks
/// 3. Renders blocks using WebsiteBlockRenderer
/// 4. Applies theme settings (colors, fonts, spacing)
/// 
/// Dec 2025 - Multi-page website support
class DynamicWebsitePage extends StatefulWidget {
  final String slug;
  
  const DynamicWebsitePage({
    super.key,
    required this.slug,
  });

  @override
  State<DynamicWebsitePage> createState() => _DynamicWebsitePageState();
}

class _DynamicWebsitePageState extends State<DynamicWebsitePage> {
  bool _isLoading = true;
  String? _error;
  WebsitePage? _page;
  List<Map<String, dynamic>> _blocks = [];
  
  // Theme settings
  Color _primaryColor = const Color(0xFF2E7D32);
  Color _accentColor = const Color(0xFFFF6F00);
  Color _backgroundColor = Colors.white;
  Color _textColor = Colors.black87;
  String _headingFont = 'Roboto';
  String _bodyFont = 'Roboto';
  double _headingSize = 48.0;
  double _bodySize = 16.0;
  double _sectionSpacing = 64.0;
  double _containerPadding = 24.0;

  static const List<String> _responsiveBreakpoints = [
    'desktop',
    'tablet',
    'mobile'
  ];

  @override
  void initState() {
    super.initState();
    _loadPageData();
  }

  @override
  void didUpdateWidget(DynamicWebsitePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      _loadPageData();
    }
  }

  String _currentBreakpoint(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) return 'mobile';
    if (width < 1024) return 'tablet';
    return 'desktop';
  }

  bool? _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'si' || normalized == 'sí') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  Map<String, bool> _normalizeBlockVisibility(dynamic raw) {
    final visibility = {
      for (final breakpoint in _responsiveBreakpoints) breakpoint: true,
    };

    dynamic source = raw;
    if (source is String) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) {
        source = null;
      } else {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) source = decoded;
        } catch (_) {
          source = null;
        }
      }
    }

    if (source is Map) {
      source.forEach((key, value) {
        final keyString = key.toString();
        if (!visibility.containsKey(keyString)) return;
        final parsed = _toBool(value);
        if (parsed != null) visibility[keyString] = parsed;
      });
    }

    return visibility;
  }

  Color? _tryParseColor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    int? intValue;
    var cleaned = trimmed.toLowerCase();

    if (cleaned.startsWith('color(')) {
      final inside = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
      intValue = int.tryParse(inside);
    }

    intValue ??= int.tryParse(cleaned);
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
  }

  Future<void> _loadPageData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final websiteService = context.read<WebsiteService>();
      
      // Load settings first
      if (websiteService.settings.isEmpty) {
        await websiteService.loadSettings();
      }
      _loadThemeFromSettings(websiteService);

      // Load pages if not already loaded
      await websiteService.loadPages();
      final pages = websiteService.pages;
      
      // Find the page by slug (or home page for empty slug)
      WebsitePage? page;
      if (widget.slug.isEmpty) {
        // Look for home page
        page = pages.firstWhere(
          (p) => p.isHome && p.isPublished,
          orElse: () => pages.firstWhere(
            (p) => p.isPublished,
            orElse: () => throw Exception('No published pages found'),
          ),
        );
      } else {
        // Find by slug
        page = pages.firstWhere(
          (p) => p.slug == widget.slug && p.isPublished,
          orElse: () => throw Exception('Page not found: ${widget.slug}'),
        );
      }

      _page = page;

      // Load blocks for this page
      final blocks = await websiteService.loadBlocksForPage(page.id);
      
      // Filter visible blocks only
      _blocks = blocks.where((block) {
        return block['is_visible'] == true;
      }).toList();

      debugPrint('[DynamicWebsitePage] Loaded page "${page.title}" with ${_blocks.length} blocks');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[DynamicWebsitePage] Error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _loadThemeFromSettings(WebsiteService service) {
    final primary = service.getSetting('theme_primary_color');
    final accent = service.getSetting('theme_accent_color');
    final background = service.getSetting('theme_background_color');
    final text = service.getSetting('theme_text_color');
    final headingFont = service.getSetting('theme_heading_font');
    final bodyFont = service.getSetting('theme_body_font');
    final headingSize = service.getSetting('theme_heading_size');
    final bodySize = service.getSetting('theme_body_size');
    final sectionSpacing = service.getSetting('theme_section_spacing');
    final containerPadding = service.getSetting('theme_container_padding');

    final parsedPrimary = _tryParseColor(primary);
    final parsedAccent = _tryParseColor(accent);
    final parsedBackground = _tryParseColor(background);
    final parsedText = _tryParseColor(text);

    if (parsedPrimary != null) _primaryColor = parsedPrimary;
    if (parsedAccent != null) _accentColor = parsedAccent;
    if (parsedBackground != null) _backgroundColor = parsedBackground;
    if (parsedText != null) _textColor = parsedText;
    if (headingFont.isNotEmpty) _headingFont = headingFont;
    if (bodyFont.isNotEmpty) _bodyFont = bodyFont;
    
    final parsedHeadingSize = double.tryParse(headingSize);
    final parsedBodySize = double.tryParse(bodySize);
    final parsedSectionSpacing = double.tryParse(sectionSpacing);
    final parsedContainerPadding = double.tryParse(containerPadding);
    
    if (parsedHeadingSize != null) _headingSize = parsedHeadingSize.clamp(24.0, 72.0);
    if (parsedBodySize != null) _bodySize = parsedBodySize.clamp(12.0, 24.0);
    if (parsedSectionSpacing != null) _sectionSpacing = parsedSectionSpacing.clamp(32.0, 128.0);
    if (parsedContainerPadding != null) _containerPadding = parsedContainerPadding.clamp(16.0, 64.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: const Center(
          child: BrandedLoading(message: 'Cargando...'),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: _buildErrorView(),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadPageData,
        child: CustomScrollView(
          slivers: [
            // Render each block
            ..._buildBlockSlivers(),
            
            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 64),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBlockSlivers() {
    final breakpoint = _currentBreakpoint(context);
    final visibleBlocks = <Map<String, dynamic>>[];

    for (final block in _blocks) {
      final blockData = block['block_data'] as Map<String, dynamic>? ?? {};
      final visibility = _normalizeBlockVisibility(blockData['visibility']);
      
      if (visibility[breakpoint] == true) {
        visibleBlocks.add(block);
      }
    }

    if (visibleBlocks.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _buildEmptyState(),
        ),
      ];
    }

    return visibleBlocks.map((block) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(bottom: _sectionSpacing),
          child: WebsiteBlockRenderer.build(
            context: context,
            blockType: block['block_type']?.toString() ?? 'hero',
            data: block['block_data'] as Map<String, dynamic>? ?? {},
            primaryColor: _primaryColor,
            accentColor: _accentColor,
            headingFont: _headingFont,
            bodyFont: _bodyFont,
            headingSize: _headingSize,
            bodySize: _bodySize,
            onNavigate: (route) => context.go(route),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildEmptyState() {
    return Container(
      padding: EdgeInsets.all(_containerPadding),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.web_stories_outlined,
              size: 64,
              color: _textColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Esta página está en construcción',
              style: TextStyle(
                fontSize: _headingSize * 0.5,
                fontFamily: _headingFont,
                color: _textColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vuelve pronto para ver el contenido',
              style: TextStyle(
                fontSize: _bodySize,
                fontFamily: _bodyFont,
                color: _textColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Página no encontrada',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Ha ocurrido un error al cargar la página',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: _textColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/tienda'),
              icon: const Icon(Icons.home),
              label: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }
}
