import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../theme/public_store_theme.dart';
import 'floating_whatsapp_button.dart';
import 'customer_account_menu.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/website_editor_panel.dart';

class PublicStoreLayout extends StatefulWidget {
  final Widget child;
  final bool showEditorButton;

  const PublicStoreLayout({
    super.key,
    required this.child,
    this.showEditorButton = true,
  });

  @override
  State<PublicStoreLayout> createState() => _PublicStoreLayoutState();
}

class _PublicStoreLayoutState extends State<PublicStoreLayout> {
  @override
  void initState() {
    super.initState();
    // Settings are loaded in main.dart after tenant detection
    // No need to load here - just watch the service
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final isLoggedIn = supabase.auth.currentUser != null;
    
    // Watch providers to rebuild when data changes
    context.watch<PublicStoreTenantProvider>();
    final websiteService = context.watch<WebsiteService>();
    
    // Don't block rendering - just use defaults until settings load
    // This makes the site feel faster

    final storeName = websiteService.getSetting('store_name', 'VINABIKE');
    final storeDescription = websiteService.getSetting(
      'store_description',
      'Todo lo que necesitas para tu bicicleta en Viña del Mar',
    );
    final logoUrl = websiteService.getSetting('logo_url', '');
    final topBannerText = websiteService.getSetting('top_banner_text', 'Envíos a todo Chile');
    final contactEmail =
        websiteService.getSetting('contact_email', 'contacto@vinabike.cl');
    final contactPhone =
        websiteService.getSetting('contact_phone', '+56 9 XXXX XXXX');
    final contactAddress = websiteService.getSetting(
      'contact_address',
      'Álvarez 32, Local 17\nViña del Mar, Chile',
    );
    final facebookHandle = websiteService.getSetting('facebook', '');
    final instagramHandle = websiteService.getSetting('instagram', '');
    final twitterHandle = websiteService.getSetting('twitter', '');
    final youtubeHandle =
        websiteService.getSetting('youtube', '@vinabikechannel');
    final whatsappRaw = websiteService.getSetting('whatsapp', '');
    final whatsappNumber = _sanitizePhone(whatsappRaw);
    final hasWhatsApp = whatsappNumber.isNotEmpty;

    final primaryColor = _resolveColor(
      websiteService.getSetting('theme_primary_color', ''),
      PublicStoreTheme.primaryBlue,
    );
    final accentColor = _resolveColor(
      websiteService.getSetting('theme_accent_color', ''),
      PublicStoreTheme.accentGreen,
    );
    final backgroundColor = _resolveColor(
      websiteService.getSetting('theme_background_color', ''),
      Colors.white,
    );
    
    // Header settings (DJI-style customization)
    final headerStyle = websiteService.getSetting('header_style', 'solid');
    final headerColorMode = websiteService.getSetting('header_color_mode', 'light');
    final showTopBannerRaw = websiteService.getSetting('header_show_top_banner', 'false');
    final showTopBanner = showTopBannerRaw == 'true';
    final headerShadow = websiteService.getSetting('header_shadow', 'true') == 'true';
    final headerBgColor = _resolveColor(
      websiteService.getSetting('header_bg_color', ''),
      Colors.white,
    );
    
    // Parse nav links (rewrite to clean paths when on public store domain)
    List<Map<String, String>> navLinks = [];
    final navLinksJson = websiteService.getSetting('header_nav_links', '');
    if (navLinksJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(navLinksJson) as List;
        navLinks = decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      } catch (_) {
        navLinks = [
          {'label': 'Inicio', 'url': '/tienda'},
          {'label': 'Productos', 'url': '/tienda/productos'},
          {'label': 'Contacto', 'url': '/tienda/contacto'},
        ];
      }
    } else {
      navLinks = [
        {'label': 'Inicio', 'url': '/tienda'},
        {'label': 'Productos', 'url': '/tienda/productos'},
        {'label': 'Contacto', 'url': '/tienda/contacto'},
      ];
    }

    // On public store domain, rewrite legacy /tienda/* links to clean URLs
    if (_isPublicStoreDomain()) {
      navLinks = navLinks.map((link) {
        var url = link['url'] ?? '';
        if (url.startsWith('/tienda/pagina')) {
          url = url.replaceFirst('/tienda', '');
        } else if (url.startsWith('/tienda')) {
          url = url.replaceFirst('/tienda', '');
          if (url.isEmpty) url = '/';
        }
        // Ensure homepage uses clean root
        if (url == '/tienda' || url.isEmpty) {
          url = '/';
        }
        return {
          'label': link['label'] ?? '',
          'url': url,
        };
      }).toList();
    }

    // Check if in edit mode - use different layout structure
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isEditMode = editProvider.isEditMode;
    final isPreviewMode = editProvider.isPreviewMode;
    
    // Build footer (reused in all layouts)
    final footerWidget = _buildFooter(
      context: context,
      storeName: storeName,
      storeDescription: storeDescription,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      contactAddress: contactAddress,
      facebookHandle: facebookHandle,
      instagramHandle: instagramHandle,
      twitterHandle: twitterHandle,
      youtubeHandle: youtubeHandle,
      primaryColor: primaryColor,
      accentColor: accentColor,
      isEditMode: isEditMode,
    );
    
    // Build header widget builder for special layouts
    Widget buildHeaderWidget({bool isOverlay = false, Color? overrideBgColor, String? overrideColorMode, bool? overrideShowBanner, bool? overrideShadow}) {
      return _buildHeader(
        context: context,
        storeName: storeName,
        storeDescription: storeDescription,
        logoUrl: logoUrl,
        topBannerText: topBannerText,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        primaryColor: primaryColor,
        accentColor: accentColor,
        isEditMode: isEditMode,
        headerStyle: headerStyle,
        headerColorMode: overrideColorMode ?? headerColorMode,
        showTopBanner: overrideShowBanner ?? showTopBanner,
        headerShadow: overrideShadow ?? headerShadow,
        headerBgColor: overrideBgColor ?? headerBgColor,
        navLinks: navLinks,
        isOverlay: isOverlay,
      );
    }
    
    // Build the main page content based on header style
    Widget pageContent;
    
    // Check if we're on the homepage (route is exactly '/tienda' or '/')
    final currentRoute = GoRouterState.of(context).uri.path;
    final isHomePage = currentRoute == '/tienda' || currentRoute == '/' || currentRoute == '/tienda/';
    
    if (headerStyle == 'transparent' && isHomePage) {
      // TRANSPARENT: Header floats over hero ONLY ON HOMEPAGE
      pageContent = SingleChildScrollView(
        child: Stack(
          children: [
            // Content starts from top (behind header)
            Column(
              children: [
                widget.child,
                footerWidget,
              ],
            ),
            // Header floats on top (positioned at top, scrolls with content)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: buildHeaderWidget(
                isOverlay: true,
                overrideBgColor: Colors.transparent,
                overrideColorMode: headerColorMode, // Use configured color mode (dark = white text)
                overrideShadow: false,
              ),
            ),
          ],
        ),
      );
    } else if (headerStyle == 'transparent' && !isHomePage) {
      // TRANSPARENT style but NOT homepage: Use solid header instead
      pageContent = Column(
        children: [
          // Header - static at top with solid background
          buildHeaderWidget(
            isOverlay: false,
            overrideBgColor: headerBgColor,
            overrideColorMode: headerColorMode,
            overrideShadow: headerShadow,
          ),
          // Main content area - scrollable
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  widget.child,
                  footerWidget,
                ],
              ),
            ),
          ),
        ],
      );
    } else if (headerStyle == 'sticky') {
      // STICKY: Header stays fixed at top while scrolling
      pageContent = _buildStickyHeaderLayout(
        context: context,
        storeName: storeName,
        storeDescription: storeDescription,
        logoUrl: logoUrl,
        topBannerText: topBannerText,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        primaryColor: primaryColor,
        accentColor: accentColor,
        headerColorMode: headerColorMode,
        showTopBanner: showTopBanner,
        headerShadow: headerShadow,
        headerBgColor: headerBgColor,
        navLinks: navLinks,
        isEditMode: isEditMode,
        footer: footerWidget,
      );
    } else {
      // SOLID: Normal layout, header at top, content scrolls below
      pageContent = Column(
        children: [
          // Header - static at top
          buildHeaderWidget(),
          // Main content area - scrollable
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  widget.child,
                  footerWidget,
                ],
              ),
            ),
          ),
        ],
      );
    }

    // In full edit mode, use Row layout with side panel
    if (isEditMode) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Row(
          children: [
            // Main content area
            Expanded(child: pageContent),
            // Side panel for editing
            WebsiteEditorPanel(
              onSave: () async {
                // Actually save the changes to the database
                await _saveChanges(context, editProvider, websiteService);
                // After save, go back to preview mode
                if (context.mounted) {
                  editProvider.switchToPreviewMode();
                }
              },
              onDiscard: () {
                // After discard, go back to preview mode
                editProvider.switchToPreviewMode();
              },
            ),
          ],
        ),
      );
    }

    // In preview mode, show top bar with "Editar" button
    if (isPreviewMode) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Column(
          children: [
            // Preview top bar (Odoo-style)
            _buildPreviewTopBar(context, editProvider, websiteService, storeName),
            // Page content
            Expanded(child: pageContent),
          ],
        ),
      );
    }

    // Build the main content (normal view mode)
    final mainContent = Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          pageContent,
          if (hasWhatsApp)
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingWhatsAppButton(
                phoneNumber: whatsappNumber,
                message:
                    'Hola! Me gustaría consultar sobre ${storeName.isNotEmpty ? storeName : 'sus productos'}.',
                backgroundColor: accentColor,
              ),
            ),
          // Show "Edit Site" button ONLY on ERP domain (not on public store domain)
          // This is for admin previewing the store from ERP, not for customers
          if (isLoggedIn && widget.showEditorButton && !_isPublicStoreDomain())
            Positioned(
              bottom: 24,
              right: hasWhatsApp ? 104 : 24,
              child: Builder(
                builder: (context) {
                  final editProvider = context.watch<WebsiteEditModeProvider>();
                  final isInEditorContext = editProvider.isInEditorContext;
                  final websiteService = context.read<WebsiteService>();
                  
                  // Don't show the floating button if we're already in editor context
                  if (isInEditorContext) return const SizedBox.shrink();
                  
                  return FloatingActionButton.extended(
                    onPressed: () {
                      debugPrint('🎨 [Layout] Edit button pressed. Entering preview mode');
                      // Enter preview mode first (shows top bar with Editar button)
                      final blocks = List<Map<String, dynamic>>.from(websiteService.blocks);
                      final settings = Map<String, dynamic>.from(websiteService.settings);
                      debugPrint('🎨 [Layout] Entering preview mode with ${blocks.length} blocks');
                      editProvider.enterPreviewMode(blocks, settings);
                    },
                    backgroundColor: accentColor,
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: const Text(
                      'Editar Sitio',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    tooltip: 'Editar sitio web',
                  );
                },
              ),
            ),
        ],
      ),
    );

    return mainContent;
  }

  /// Build the preview top bar (Odoo-style) with "Editar" button
  Widget _buildPreviewTopBar(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
    String storeName,
  ) {
    return Container(
      height: 48,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Logo/brand
          Row(
            children: [
              Icon(Icons.language, color: Colors.white.withValues(alpha: 0.8), size: 20),
              const SizedBox(width: 8),
              Text(
                'Sitio web',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Navigation items
          _buildPreviewNavItem('Sitio', true),
          _buildPreviewNavItem('Comercio electrónico', false),
          _buildPreviewNavItem('Reportes', false),
          _buildPreviewNavItem('Configuración', false),
          
          const Spacer(),
          
          // Store name dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  storeName.isNotEmpty ? storeName : 'Mi Tienda',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
              ],
            ),
          ),
          const SizedBox(width: 16),
          
          // Published toggle
          Row(
            children: [
              Text(
                'Publicado',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
              const SizedBox(width: 8),
              Switch(
                value: true,
                onChanged: (v) {},
                activeColor: Colors.green,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(width: 16),
          
          // Mobile preview button
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.phone_android, color: Colors.white70, size: 20),
            tooltip: 'Vista móvil',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 8),
          
          // New page button
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Nuevo', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          
          // EDIT button (main action)
          ElevatedButton(
            onPressed: () {
              editProvider.switchToEditMode();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text(
              'Editar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          
          // Close/exit button - go back to Website Management
          IconButton(
            onPressed: () {
              editProvider.exitEditMode();
              context.go('/website');
            },
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            tooltip: 'Volver a Gestión de Sitio Web',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewNavItem(String label, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
          fontSize: 13,
          fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    );
  }

  /// Check if we're on the public store domain (customer-facing)
  bool _isPublicStoreDomain() {
    if (!kIsWeb) return false;
    final host = Uri.base.host.toLowerCase();
    return host == 'vinabike-store.web.app' ||
        host == 'vinabike-store.firebaseapp.com' ||
        host == 'vinabike.cl' ||
        host == 'www.vinabike.cl';
  }

  /// Save changes to the database
  Future<void> _saveChanges(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
  ) async {
    try {
      // Get tenant ID
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final tenantId = tenantProvider.tenantId;
      
      if (tenantId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se pudo identificar el tenant')),
          );
        }
        return;
      }

      // Show saving indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guardando cambios...')),
        );
      }

      // Save header settings if there are pending changes
      debugPrint('🔄 [SaveChanges] hasHeaderChanges=${editProvider.hasHeaderChanges}, pendingSettings=${editProvider.pendingHeaderSettings.keys.join(', ')}');
      if (editProvider.hasHeaderChanges && editProvider.pendingHeaderSettings.isNotEmpty) {
        debugPrint('🔄 [SaveChanges] Saving header settings: ${editProvider.pendingHeaderSettings}');
        await websiteService.saveSettings(editProvider.pendingHeaderSettings);
        debugPrint('✅ [SaveChanges] Header settings saved');
      } else {
        debugPrint('⚠️ [SaveChanges] Skipping header save: hasHeaderChanges=${editProvider.hasHeaderChanges}, isEmpty=${editProvider.pendingHeaderSettings.isEmpty}');
      }

      // Convert blocks to the format expected by saveBlocks
      final blocks = editProvider.blocks;
      final pageId = editProvider.currentPageId; // Multi-page editing support
      final pageSlug = editProvider.currentPageSlug;
      debugPrint('🔄 [SaveChanges] Saving ${blocks.length} blocks for page: ${pageSlug ?? "home"} (id: $pageId)');
      
      final blocksForSave = blocks.asMap().entries.map((entry) {
        final index = entry.key;
        final block = entry.value;
        debugPrint('  Block ${index}: id=${block['id']}, type=${block['block_type']}');
        final blockType = block['block_type'] ?? block['type'];
        final blockData = block['block_data'] ?? block['data'] ?? {};
        final isVisible = block['is_visible'] ?? block['isVisible'] ?? true;
        final orderIndex = block['order_index'] ?? index;
        return {
          'id': block['id'],
          'type': blockType,
          'data': blockData,
          'isVisible': isVisible,
          'order_index': orderIndex,
        };
      }).toList();

      // Save blocks - use page-specific save if editing a non-home page
      if (pageId != null) {
        await websiteService.saveBlocksForPage(pageId, blocksForSave);
        debugPrint('✅ [SaveChanges] Blocks saved to page: $pageSlug (id: $pageId)');
      } else {
        await websiteService.saveBlocks(blocksForSave);
        debugPrint('✅ [SaveChanges] Blocks saved to home page');
      }

      // Mark as saved and clear header changes
      editProvider.markAsSaved();
      editProvider.clearHeaderChanged();
      
      // Reload blocks to get fresh data and update provider
      List<Map<String, dynamic>> freshBlocks;
      if (pageId != null) {
        freshBlocks = await websiteService.loadBlocksForPage(
          pageId,
          tenantId: tenantId,
        );
        debugPrint('✅ [SaveChanges] Reloaded ${freshBlocks.length} blocks for page: $pageSlug');
      } else {
        freshBlocks = await websiteService.loadBlocksForTenant(tenantId);
        debugPrint('✅ [SaveChanges] Reloaded ${freshBlocks.length} blocks for home page');
      }
      
      // Update the edit provider with fresh blocks from database
      editProvider.updateBlocksAfterSave(freshBlocks);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Cambios guardados'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [SaveChanges] Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildHeader({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    bool isEditMode = false,
    String headerStyle = 'solid',
    String headerColorMode = 'light',
    bool showTopBanner = true,
    bool headerShadow = true,
    Color headerBgColor = Colors.white,
    List<Map<String, String>> navLinks = const [],
    bool isOverlay = false, // For transparent mode when scrolled up
  }) {
    final cart = context.watch<CartProvider>();
    
    // Determine colors based on mode
    final isDarkMode = headerColorMode == 'dark' || isOverlay;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final iconColor = isDarkMode ? Colors.white : primaryColor;
    final bgColor = isOverlay ? Colors.transparent : headerBgColor;

    final headerContent = Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: headerShadow && !isOverlay
            ? [
                BoxShadow(
                  color: PublicStoreTheme.shadow,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          // Top banner - customizable (only show if enabled and not in overlay mode)
          if (showTopBanner && !isOverlay)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: primaryColor,
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 24,
                runSpacing: 8,
                children: [
                  if (topBannerText.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_shipping_outlined,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          topBannerText,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  if (contactPhone.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.support_agent_outlined,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Contáctanos: $contactPhone',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  if (contactEmail.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.mail_outline,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          contactEmail,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          // Main header with logo
          Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                // Logo - uses URL if set, otherwise falls back to asset, then text
                InkWell(
                  onTap: () => context.go('/tienda'),
                  child: SizedBox(
                    height: 48,
                    child: logoUrl.isNotEmpty
                        ? Image.network(
                            logoUrl,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            color: isDarkMode ? Colors.white : null,
                            colorBlendMode: isDarkMode ? BlendMode.srcIn : null,
                            errorBuilder: (context, error, stackTrace) => _buildTextLogo(context, storeName, textColor),
                          )
                        : Image.asset(
                            'assets/images/vinabike_logo.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            color: isDarkMode ? Colors.white : null,
                            colorBlendMode: isDarkMode ? BlendMode.srcIn : null,
                            errorBuilder: (context, error, stackTrace) => _buildTextLogo(context, storeName, textColor),
                          ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Row(
                    children: navLinks.isEmpty
                        ? [
                            _buildNavLink(context, 'Inicio', '/tienda', textColor),
                            const SizedBox(width: 24),
                            _buildNavLink(context, 'Productos', '/tienda/productos', textColor),
                            const SizedBox(width: 24),
                            _buildInfoDropdown(context, textColor),
                            const SizedBox(width: 24),
                            _buildNavLink(context, 'Contacto', '/tienda/contacto', textColor),
                          ]
                        : [
                            ...navLinks.map((link) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 24),
                                child: _buildNavLink(context, link['label'] ?? '', link['url'] ?? '/', textColor),
                              );
                            }),
                            _buildInfoDropdown(context, textColor),
                          ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      color: iconColor,
                      onPressed: () => context.go('/tienda/productos'),
                      tooltip: 'Buscar',
                    ),
                    const SizedBox(width: 8),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shopping_cart_outlined),
                          color: iconColor,
                          onPressed: () => context.go('/tienda/carrito'),
                          tooltip: 'Carrito',
                        ),
                        if (cart.itemCount > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: accentColor,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                  minWidth: 20, minHeight: 20),
                              child: Text(
                                '${cart.itemCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    CustomerAccountMenu(textColor: textColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Wrap with edit mode indicator if in edit mode
    if (isEditMode) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Select header for editing in the "Editar" tab
          final editProvider = context.read<WebsiteEditModeProvider>();
          editProvider.selectBlock('header');
        },
        child: Stack(
          children: [
            headerContent,
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Header',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return headerContent;
  }

  /// Builds a layout where the header stays fixed at the top while scrolling
  /// Header starts with configured style and stays visible
  Widget _buildStickyHeaderLayout({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    required String headerColorMode,
    required bool showTopBanner,
    required bool headerShadow,
    required Color headerBgColor,
    required List<Map<String, String>> navLinks,
    required bool isEditMode,
    required Widget footer,
  }) {
    // Sticky uses the scaffold that keeps header fixed at top
    return _StickyHeaderScaffold(
      storeName: storeName,
      storeDescription: storeDescription,
      logoUrl: logoUrl,
      topBannerText: topBannerText,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      primaryColor: primaryColor,
      accentColor: accentColor,
      headerColorMode: headerColorMode,
      showTopBanner: showTopBanner,
      headerShadow: headerShadow,
      headerBgColor: headerBgColor,
      navLinks: navLinks,
      isEditMode: isEditMode,
      buildHeader: _buildHeader,
      child: widget.child,
      footer: footer,
    );
  }

  Widget _buildFooter({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String contactEmail,
    required String contactPhone,
    required String contactAddress,
    required String facebookHandle,
    required String instagramHandle,
    required String twitterHandle,
    required String youtubeHandle,
    required Color primaryColor,
    required Color accentColor,
    bool isEditMode = false,
  }) {
    final facebookUrl =
        _buildSocialUrl(facebookHandle, 'https://facebook.com/');
    final instagramUrl =
        _buildSocialUrl(instagramHandle, 'https://instagram.com/');
    final twitterUrl = _buildSocialUrl(twitterHandle, 'https://twitter.com/');
    final youtubeUrl = _buildSocialUrl(youtubeHandle, 'https://youtube.com/');

    final footerContent = Container(
      width: double.infinity,
      color: PublicStoreTheme.textPrimary,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          storeName.isNotEmpty ? storeName : 'VINABIKE',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          storeDescription.isNotEmpty
                              ? storeDescription
                              : 'Todo lo que necesitas para tu bicicleta en Viña del Mar',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white70,
                                  ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.mail_outline,
                                  color: Colors.white70),
                              onPressed: contactEmail.isEmpty
                                  ? null
                                  : () => _launchUri(Uri(
                                      scheme: 'mailto', path: contactEmail)),
                              tooltip: 'Email',
                            ),
                            IconButton(
                              icon: const Icon(Icons.phone_outlined,
                                  color: Colors.white70),
                              onPressed: contactPhone.isEmpty
                                  ? null
                                  : () => _launchUri(
                                      Uri(scheme: 'tel', path: contactPhone)),
                              tooltip: 'Teléfono',
                            ),
                            IconButton(
                              icon: const Icon(Icons.facebook_outlined,
                                  color: Colors.white70),
                              onPressed: facebookUrl == null
                                  ? null
                                  : () => _launchUri(Uri.parse(facebookUrl)),
                              tooltip: 'Facebook',
                            ),
                            IconButton(
                              icon: const Icon(Icons.camera_alt_outlined,
                                  color: Colors.white70),
                              onPressed: instagramUrl == null
                                  ? null
                                  : () => _launchUri(Uri.parse(instagramUrl)),
                              tooltip: 'Instagram',
                            ),
                            IconButton(
                              icon: const Icon(Icons.alternate_email,
                                  color: Colors.white70),
                              onPressed: twitterUrl == null
                                  ? null
                                  : () => _launchUri(Uri.parse(twitterUrl)),
                              tooltip: 'Twitter',
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_circle_outline,
                                  color: Colors.white70),
                              onPressed: youtubeUrl == null
                                  ? null
                                  : () => _launchUri(Uri.parse(youtubeUrl)),
                              tooltip: 'YouTube',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enlaces',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _buildFooterLink(
                            context, 'Inicio', '/tienda', primaryColor),
                        _buildFooterLink(context, 'Productos',
                            '/tienda/productos', primaryColor),
                        _buildFooterLink(context, 'Servicios',
                            '/tienda/servicios', primaryColor),
                        _buildFooterLink(context, 'Contacto',
                            '/tienda/contacto', primaryColor),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Información',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _buildFooterLink(context, 'Sobre Nosotros',
                            _isPublicStoreDomain() ? '/pagina/nosotros' : '/tienda/pagina/nosotros', primaryColor),
                        _buildFooterLink(context, 'Términos y Condiciones',
                            _isPublicStoreDomain() ? '/pagina/terminos' : '/tienda/pagina/terminos', primaryColor),
                        _buildFooterLink(context, 'Política de Privacidad',
                            _isPublicStoreDomain() ? '/pagina/privacidad' : '/tienda/pagina/privacidad', primaryColor),
                        _buildFooterLink(context, 'Política de Devoluciones',
                            _isPublicStoreDomain() ? '/pagina/devoluciones' : '/tienda/pagina/devoluciones', primaryColor),
                        _buildFooterLink(context, 'Envíos',
                            _isPublicStoreDomain() ? '/pagina/envios' : '/tienda/pagina/envios', primaryColor),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contacto',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_outlined,
                                color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                contactAddress.isNotEmpty
                                    ? contactAddress
                                    : 'Álvarez 32, Local 17\nViña del Mar, Chile',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.white70,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined,
                                color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              contactPhone.isNotEmpty
                                  ? contactPhone
                                  : '+56 9 XXXX XXXX',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.email_outlined,
                                color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              contactEmail.isNotEmpty
                                  ? contactEmail
                                  : 'contacto@vinabike.cl',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              const Divider(color: Colors.white24),
              const SizedBox(height: 24),
              Text(
                '© ${DateTime.now().year} ${storeName.isNotEmpty ? storeName : 'Vinabike'}. Todos los derechos reservados.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    // Wrap with edit mode indicator if in edit mode
    if (isEditMode) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Select footer for editing in the "Editar" tab
          final editProvider = context.read<WebsiteEditModeProvider>();
          editProvider.selectBlock('footer');
        },
        child: Stack(
          children: [
            footerContent,
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.green.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Footer',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return footerContent;
  }

  Widget _buildTextLogo(BuildContext context, String storeName, Color primaryColor) {
    return Text(
      storeName.isNotEmpty ? storeName.toUpperCase() : 'MI TIENDA',
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
    );
  }

  Widget _buildNavLink(
    BuildContext context,
    String label,
    String path,
    Color primaryColor,
  ) {
    final isActive = GoRouterState.of(context).matchedLocation == path;

    return InkWell(
      onTap: () => context.go(path),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? primaryColor : PublicStoreTheme.textPrimary,
              ),
        ),
      ),
    );
  }

  /// Build elegant dropdown menu for information/policy pages
  Widget _buildInfoDropdown(BuildContext context, Color textColor) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      elevation: 8,
      color: Colors.white,
      onSelected: (String path) {
        context.go(path);
      },
      itemBuilder: (BuildContext context) {
        final basePath = _isPublicStoreDomain() ? '/pagina' : '/tienda/pagina';
        return <PopupMenuEntry<String>>[
          _buildDropdownItem(
            icon: Icons.info_outline,
            label: 'Sobre Nosotros',
            value: '$basePath/nosotros',
          ),
          const PopupMenuDivider(height: 1),
          _buildDropdownItem(
            icon: Icons.local_shipping_outlined,
            label: 'Envíos',
            value: '$basePath/envios',
          ),
          _buildDropdownItem(
            icon: Icons.replay_outlined,
            label: 'Devoluciones',
            value: '$basePath/devoluciones',
          ),
          const PopupMenuDivider(height: 1),
          _buildDropdownItem(
            icon: Icons.gavel_outlined,
            label: 'Términos y Condiciones',
            value: '$basePath/terminos',
          ),
          _buildDropdownItem(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacidad',
            value: '$basePath/privacidad',
          ),
        ];
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Información',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.normal,
                  color: textColor,
                ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 18, color: textColor),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildDropdownItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(
    BuildContext context,
    String label,
    String path,
    Color primaryColor,
  ) {
    final isActive = GoRouterState.of(context).matchedLocation == path;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.go(path),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
        ),
      ),
    );
  }

  Future<void> _launchUri(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  String? _buildSocialUrl(String handle, String baseUrl) {
    final trimmed = handle.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('http')) {
      return trimmed;
    }
    return '$baseUrl${trimmed.replaceAll('@', '')}';
  }

  String _sanitizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return '';
    }
    if (digits.startsWith('56')) {
      return digits;
    }
    if (digits.length == 9 && digits.startsWith('9')) {
      return '56$digits';
    }
    if (digits.length == 8) {
      return '56$digits';
    }
    return digits;
  }

  Color _resolveColor(String raw, Color fallback) {
    final value = raw.trim();
    if (value.isEmpty) return fallback;

    Color? parsed;
    int? intValue;

    String cleaned = value.toLowerCase();
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

    if (intValue != null) {
      parsed = Color(intValue);
    }

    return parsed ?? fallback;
  }
}

/// A stateful widget that manages the sticky header that stays fixed at top while scrolling
class _StickyHeaderScaffold extends StatefulWidget {
  final String storeName;
  final String storeDescription;
  final String logoUrl;
  final String topBannerText;
  final String contactPhone;
  final String contactEmail;
  final Color primaryColor;
  final Color accentColor;
  final String headerColorMode;
  final bool showTopBanner;
  final bool headerShadow;
  final Color headerBgColor;
  final List<Map<String, String>> navLinks;
  final bool isEditMode;
  final Widget Function({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    bool isEditMode,
    String headerStyle,
    String headerColorMode,
    bool showTopBanner,
    bool headerShadow,
    Color headerBgColor,
    List<Map<String, String>> navLinks,
    bool isOverlay,
  }) buildHeader;
  final Widget child;
  final Widget footer;

  const _StickyHeaderScaffold({
    required this.storeName,
    required this.storeDescription,
    required this.logoUrl,
    required this.topBannerText,
    required this.contactPhone,
    required this.contactEmail,
    required this.primaryColor,
    required this.accentColor,
    required this.headerColorMode,
    required this.showTopBanner,
    required this.headerShadow,
    required this.headerBgColor,
    required this.navLinks,
    required this.isEditMode,
    required this.buildHeader,
    required this.child,
    required this.footer,
  });

  @override
  State<_StickyHeaderScaffold> createState() =>
      _StickyHeaderScaffoldState();
}

class _StickyHeaderScaffoldState extends State<_StickyHeaderScaffold> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calculate header opacity based on scroll (0 = transparent, 1 = solid)
    // Transition happens over the first 100 pixels of scroll
    final double headerOpacity = (_scrollOffset / 100).clamp(0.0, 1.0);
    final bool isScrolled = _scrollOffset > 50;

    // When scrolled, switch to light mode (dark text on white bg)
    final String effectiveColorMode = isScrolled ? 'light' : widget.headerColorMode;
    final Color effectiveBgColor = isScrolled 
        ? widget.headerBgColor 
        : widget.headerBgColor.withValues(alpha: headerOpacity);

    return Stack(
      children: [
        // Main scrollable content
        SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            children: [
              // Add padding at top for the header space (only if not in edit mode)
              if (!widget.isEditMode) const SizedBox(height: 0),
              widget.child,
              widget.footer,
            ],
          ),
        ),
        // Floating header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: widget.buildHeader(
            context: context,
            storeName: widget.storeName,
            storeDescription: widget.storeDescription,
            logoUrl: widget.logoUrl,
            topBannerText: widget.topBannerText,
            contactPhone: widget.contactPhone,
            contactEmail: widget.contactEmail,
            primaryColor: widget.primaryColor,
            accentColor: widget.accentColor,
            isEditMode: widget.isEditMode,
            headerStyle: 'transparent',
            headerColorMode: effectiveColorMode,
            showTopBanner: widget.showTopBanner && !isScrolled,
            headerShadow: widget.headerShadow && isScrolled,
            headerBgColor: effectiveBgColor,
            navLinks: widget.navLinks,
            isOverlay: !isScrolled, // Only overlay when not scrolled
          ),
        ),
      ],
    );
  }
}
