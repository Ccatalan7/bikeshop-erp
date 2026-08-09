part of '../website_editor_panel.dart';

/// Controls for editing the site header (special element, not a block)
class _HeaderBlockControls extends StatefulWidget {
  final WebsiteEditModeProvider provider;

  const _HeaderBlockControls({super.key, required this.provider});

  @override
  State<_HeaderBlockControls> createState() => _HeaderBlockControlsState();
}

class _HeaderBlockControlsState extends State<_HeaderBlockControls> {
  final _storeNameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _topBannerController = TextEditingController();
  final _headerBgColorController = TextEditingController();
  final _headerMenuSurfaceColorController = TextEditingController();
  final _headerMenuRailColorController = TextEditingController();

  // Header style options
  String _headerStyle = 'solid';
  String _headerColorMode = 'auto';
  bool _navigationUppercase = true;
  bool _showTopBanner = false;
  bool _headerShadow = true;
  bool _loaded = false;
  bool _hasLocalChanges = false;

  final _headerStyles = {
    'solid': 'Sólido',
    'transparent': 'Transparente (sobre hero)',
    'sticky': 'Fijo al hacer scroll'
  };
  final _headerColorModes = {
    'auto': 'Automático (recomendado)',
    'light': 'Claro (texto oscuro)',
    'dark': 'Oscuro (texto claro)'
  };

  WebsiteAsyncFieldBinding _headerAsyncBinding(String sourceKey) =>
      _sitewideAsyncFieldBinding(
        provider: widget.provider,
        bucket: WebsiteSitewideDraftBucket.header,
        sourceKey: sourceKey,
      );

  @override
  void initState() {
    super.initState();
    // Add listeners to detect changes
    _storeNameController.addListener(_onFieldChanged);
    _logoUrlController.addListener(_onFieldChanged);
    _topBannerController.addListener(_onFieldChanged);
    _headerBgColorController.addListener(_onFieldChanged);
    _headerMenuSurfaceColorController.addListener(_onFieldChanged);
    _headerMenuRailColorController.addListener(_onFieldChanged);
  }

  /// Every keystroke stages, not just the first one.
  ///
  /// The guard used to be `if (_loaded && !_hasLocalChanges)`, which made
  /// `_hasLocalChanges` do two jobs: remember that the control is dirty AND
  /// gate the sync. Once the first character set it true the condition was
  /// never true again, so the pending value froze at that first character
  /// while the field kept accepting text — the canvas previewed `E` for a
  /// banner the operator had finished renaming. `_markChanged` beside it
  /// already had the right shape: mark once, sync always.
  void _onFieldChanged() {
    if (!_loaded) return;
    _hasLocalChanges = true;
    _syncPendingSettingsToProvider();
  }

  void _markChanged() {
    if (!_hasLocalChanges) {
      _hasLocalChanges = true;
    }
    _syncPendingSettingsToProvider();
  }

  /// Sync current header settings to provider for saving with main button
  void _syncPendingSettingsToProvider() {
    debugPrint(
        '🔧 [HeaderSettings] Syncing to provider: header_show_top_banner = $_showTopBanner');
    widget.provider.updateHeaderSettings({
      'store_name': _storeNameController.text,
      'logo_url': _logoUrlController.text,
      'top_banner_text': _topBannerController.text,
      'header_style': _headerStyle,
      'header_color_mode': _headerColorMode,
      'header_navigation_uppercase': _navigationUppercase.toString(),
      'header_show_top_banner': _showTopBanner.toString(),
      'header_shadow': _headerShadow.toString(),
      'header_bg_color': _headerBgColorController.text,
      'header_menu_surface_color': _headerMenuSurfaceColorController.text,
      'header_menu_rail_color': _headerMenuRailColorController.text,
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loadSettings();
      _loaded = true;
    }
  }

  @override
  void didUpdateWidget(covariant _HeaderBlockControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.provider, widget.provider)) {
      _loaded = false;
      _hasLocalChanges = false;
      _loadSettings();
      _loaded = true;
    }
  }

  void _loadSettings() {
    final service = context.read<WebsiteService>();
    // Reopening the control hydrates PENDING over saved: an unsaved staged
    // draft must never disagree with the canvas it is previewing.
    String effective(String key, String defaultValue) =>
        widget.provider.getEffectiveHeaderSetting(
          key,
          service.getSetting(key, defaultValue),
        );

    _storeNameController.text = effective('store_name', '');
    _logoUrlController.text = effective('logo_url', '');
    _topBannerController.text =
        effective('top_banner_text', 'Envíos a Chile continental');
    _headerBgColorController.text = effective('header_bg_color', '#FFFFFF');
    _headerMenuSurfaceColorController.text =
        effective('header_menu_surface_color', '#000000');
    _headerMenuRailColorController.text =
        effective('header_menu_rail_color', '#64748B');

    _headerStyle = effective('header_style', 'solid');
    _headerColorMode = effective('header_color_mode', 'auto');
    _navigationUppercase =
        effective('header_navigation_uppercase', 'true') == 'true';
    final rawBannerValue = effective('header_show_top_banner', 'false');
    _showTopBanner = rawBannerValue == 'true';
    debugPrint(
        '🔧 [HeaderSettings] _loadSettings: rawBannerValue="$rawBannerValue" → _showTopBanner=$_showTopBanner');
    _headerShadow = effective('header_shadow', 'true') == 'true';
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _logoUrlController.dispose();
    _topBannerController.dispose();
    _headerBgColorController.dispose();
    _headerMenuSurfaceColorController.dispose();
    _headerMenuRailColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.web_asset, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Header',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Encabezado del sitio',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Logo section
          const _SectionHeader('Logo'),
          const SizedBox(height: 12),
          _LogoUploader(
            currentUrl: _logoUrlController.text,
            asyncBinding: _headerAsyncBinding('logo_url'),
            onChanged: (url) {
              _logoUrlController.text = url;
              setState(() {});
            },
          ),

          const SizedBox(height: 20),

          // Store name
          _EditorTextField(
            label: 'Nombre de la tienda',
            value: _storeNameController.text,
            controller: _storeNameController,
            onChanged: (_) {},
            hint: 'Mi Tienda',
          ),

          const SizedBox(height: 16),

          // Top banner text
          _EditorTextField(
            label: 'Texto del banner superior',
            value: _topBannerController.text,
            controller: _topBannerController,
            onChanged: (_) {},
            hint: 'Envíos gratis en compras sobre \$50.000',
          ),

          const SizedBox(height: 24),

          // ========== HEADER STYLE SECTION ==========
          const _SectionHeader('Estilo del header'),
          const SizedBox(height: 12),

          // Header style dropdown
          _buildDropdown(
            label: 'Modo de visualización',
            value: _headerStyle,
            items: _headerStyles.keys.toList(),
            labels: _headerStyles,
            onChanged: (v) {
              setState(() => _headerStyle = v!);
              _markChanged();
            },
          ),
          const SizedBox(height: 12),

          // Color mode dropdown
          _buildDropdown(
            label: 'Contraste del contenido',
            value: _headerColorMode,
            items: _headerColorModes.keys.toList(),
            labels: _headerColorModes,
            onChanged: (v) {
              setState(() => _headerColorMode = v!);
              _markChanged();
            },
          ),
          const SizedBox(height: 8),
          Text(
            _headerColorMode == 'auto'
                ? 'El logo, los enlaces y los íconos se adaptan al fondo. Sobre banners se agrega una protección tonal sutil para que ninguna capa los haga desaparecer.'
                : 'Este modo reemplaza el contraste automático en todo el sitio.',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),

          // Background color
          _ColorField(
            label: 'Color de fondo',
            controller: _headerBgColorController,
            asyncBinding: _headerAsyncBinding('header_bg_color'),
          ),

          const SizedBox(height: 20),

          const _SectionHeader('Menú desplegado'),
          const SizedBox(height: 8),
          const Text(
            'Estos colores se aplican sólo cuando se abre la navegación.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _ColorField(
            label: 'Header y panel principal',
            controller: _headerMenuSurfaceColorController,
            allowAlpha: false,
            asyncBinding: _headerAsyncBinding('header_menu_surface_color'),
          ),
          const SizedBox(height: 12),
          _ColorField(
            label: 'Franja de categorías',
            controller: _headerMenuRailColorController,
            allowAlpha: false,
            asyncBinding: _headerAsyncBinding('header_menu_rail_color'),
          ),
          const SizedBox(height: 16),

          // Toggles
          _buildSwitch(
            label: 'Mostrar banner superior',
            value: _showTopBanner,
            onChanged: (v) {
              debugPrint(
                  '🔧 [HeaderSettings] Toggling showTopBanner: $_showTopBanner → $v');
              setState(() {
                _showTopBanner = v;
                _hasLocalChanges = true;
              });
              // Sync AFTER setState completes with new value
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _syncPendingSettingsToProvider();
              });
            },
          ),
          const SizedBox(height: 8),
          _buildSwitch(
            label: 'Mostrar sombra',
            value: _headerShadow,
            onChanged: (v) {
              setState(() {
                _headerShadow = v;
                _hasLocalChanges = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _syncPendingSettingsToProvider();
              });
            },
          ),

          const SizedBox(height: 24),

          // Navigation records belong to website_navigation, not header settings.
          const _SectionHeader('Navegación'),
          const SizedBox(height: 12),
          _buildSwitch(
            label: 'Títulos del menú en mayúsculas',
            value: _navigationUppercase,
            onChanged: (value) {
              setState(() {
                _navigationUppercase = value;
                _hasLocalChanges = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _syncPendingSettingsToProvider();
              });
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.menu, color: Colors.white70, size: 17),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El header y el footer usan el menú central del sitio.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      WebsiteWorkspaceScope.maybeOf(context)?.open(
                        WebsiteWorkspacePanel.navigation,
                      );
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Administrar navegación'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Info text - changes are saved with main button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade300),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Los cambios se guardarán al presionar "Guardar" en la barra superior.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    Map<String, String>? labels,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        MenuAnchor(
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(const Color(0xFF2D2D2D)),
            surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          menuChildren: items.map((item) {
            final itemLabel = labels?[item] ?? item;
            return MenuItemButton(
              onPressed: () => onChanged(item),
              style: ButtonStyle(
                backgroundColor: item == value
                    ? WidgetStateProperty.all(
                        Colors.white.withValues(alpha: 0.1))
                    : null,
                foregroundColor: WidgetStateProperty.all(Colors.white),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(
                  itemLabel,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            );
          }).toList(),
          builder: (context, controller, child) {
            final selectedLabel = labels?[value] ?? value;
            return InkWell(
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        selectedLabel,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        color: Colors.white54, size: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSwitch({
    required String label,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          // ON state: bright teal color (highlighted)
          activeThumbColor: Colors.white,
          activeTrackColor: const Color(0xFF00A09D),
          // OFF state: dim/dark (muted)
          inactiveThumbColor: Colors.grey.shade400,
          inactiveTrackColor: Colors.grey.shade700,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

String _footerNavigationSourceSnapshot(
  Iterable<WebsiteNavigation> navigation,
) {
  Map<String, dynamic> snapshot(WebsiteNavigation item) => <String, dynamic>{
        ...item.toJson(),
        'children': item.children.map(snapshot).toList(growable: false),
      };

  return jsonEncode(navigation.map(snapshot).toList(growable: false));
}

WebsiteNavigation? _findFooterNavigation(
  Iterable<WebsiteNavigation> navigation,
  String id,
) {
  for (final item in navigation) {
    if (item.id == id) return item;
    final nested = _findFooterNavigation(item.children, id);
    if (nested != null) return nested;
  }
  return null;
}

class _FooterNavigationDragArm {
  const _FooterNavigationDragArm({
    required this.intent,
    required this.sourceSnapshot,
    required this.itemId,
    this.parentId,
  });

  final WebsiteSitewideAsyncIntent intent;
  final String sourceSnapshot;
  final String itemId;
  final String? parentId;
}

/// Controls for editing the site footer (special element, not a block)
class _FooterBlockControls extends StatefulWidget {
  final WebsiteEditModeProvider provider;

  const _FooterBlockControls({super.key, required this.provider});

  @override
  State<_FooterBlockControls> createState() => _FooterBlockControlsState();
}

class _FooterBlockControlsState extends State<_FooterBlockControls> {
  final _taglineController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _addressController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _twitterController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _tiktokController = TextEditingController();
  bool _loaded = false;

  bool _hasLocalChanges = false;

  String? _selectedFooterSectionId;

  // Inline editor state (Edit happens inside the panel, not a modal)
  String? _editingFooterNavId;
  final _inlineNavLabelController = TextEditingController();
  final _inlineNavLinkValueController = TextEditingController();
  String? _inlineNavParentId;
  NavLinkType _inlineNavLinkType = NavLinkType.page;
  bool _inlineNavIsVisible = true;
  bool _inlineNavShowOnDesktop = true;
  bool _inlineNavShowOnMobile = true;
  bool _inlineNavOpenInNewTab = false;
  bool _isSavingInlineNav = false;

  List<String>? _footerSectionOrderOverride;
  final Map<String, List<String>> _footerLinkOrderOverrideBySection = {};

  // Drag state for visual reordering feedback (sections/tabs)
  String? _draggingSectionId;
  int? _hoveringSectionIndex;

  // Drag state for visual reordering feedback (links within a section)
  String? _draggingLinkId;
  int? _hoveringLinkIndex;
  _FooterNavigationDragArm? _sectionDragArm;
  _FooterNavigationDragArm? _linkDragArm;

  _FooterNavigationDragArm? _captureFooterDragArm({
    required String itemId,
    String? parentId,
  }) {
    final service = context.read<WebsiteService>();
    final intent = widget.provider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.footer,
      sourceKeys: const <String>{
        WebsiteSitewideAsyncSourceKey.footerNavigation,
      },
    );
    if (intent == null) return null;
    return _FooterNavigationDragArm(
      intent: intent,
      sourceSnapshot: _footerNavigationSourceSnapshot(
        service.footerNavigation,
      ),
      itemId: itemId,
      parentId: parentId,
    );
  }

  void _cancelFooterDragArm(_FooterNavigationDragArm? arm) {
    if (arm == null) return;
    widget.provider.commitSitewideAsyncIntent(
      arm.intent,
      () => WebsiteInlineMutationResult.unchanged,
    );
  }

  bool _commitFooterDragOrder(
    _FooterNavigationDragArm? arm,
    List<String> orderedIds,
  ) {
    if (arm == null) return false;
    final service = context.read<WebsiteService>();
    final provider = widget.provider;
    final result = provider.commitSitewideAsyncIntent(arm.intent, () {
      if (_footerNavigationSourceSnapshot(service.footerNavigation) !=
          arm.sourceSnapshot) {
        return WebsiteInlineMutationResult.rejected;
      }
      final effective = provider.getEffectiveFooterNavigation(
        service.footerNavigation,
      );
      final siblings = arm.parentId == null
          ? effective
          : _findFooterNavigation(effective, arm.parentId!)?.children;
      if (siblings == null ||
          siblings.where((item) => item.id == arm.itemId).length != 1) {
        return WebsiteInlineMutationResult.rejected;
      }
      final liveIds = siblings.map((item) => item.id).toList(growable: false);
      if (orderedIds.length != liveIds.length ||
          orderedIds.toSet().length != orderedIds.length ||
          !orderedIds.toSet().containsAll(liveIds)) {
        return WebsiteInlineMutationResult.rejected;
      }
      if (arm.parentId == null) {
        provider.updateFooterSectionOrder(orderedIds);
      } else {
        provider.updateFooterLinkOrder(arm.parentId!, orderedIds);
      }
      return WebsiteInlineMutationResult.committed;
    });
    if (!result.accepted || !mounted) return false;
    setState(() {
      if (arm.parentId == null) {
        _footerSectionOrderOverride = orderedIds;
      } else {
        _footerLinkOrderOverrideBySection[arm.parentId!] = orderedIds;
      }
    });
    return true;
  }

  List<WebsiteNavigation> _applyIdOrder(
    List<WebsiteNavigation> items,
    List<String>? orderedIds,
  ) {
    if (orderedIds == null || orderedIds.isEmpty) return items;

    final byId = <String, WebsiteNavigation>{
      for (final i in items) i.id: i,
    };
    final ordered = <WebsiteNavigation>[];
    for (final id in orderedIds) {
      final item = byId[id];
      if (item != null) ordered.add(item);
    }
    for (final item in items) {
      if (!orderedIds.contains(item.id)) {
        ordered.add(item);
      }
    }
    return ordered;
  }

  List<WebsiteNavigation> _getDisplayedFooterSections(WebsiteService service) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    var sections = editProvider.getEffectiveFooterNavigation(
      service.footerNavigation,
    )..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    sections = _applyIdOrder(sections, _footerSectionOrderOverride);

    // Apply visual reordering during drag
    if (_draggingSectionId != null && _hoveringSectionIndex != null) {
      final draggedIndex =
          sections.indexWhere((s) => s.id == _draggingSectionId);
      if (draggedIndex >= 0 && draggedIndex != _hoveringSectionIndex) {
        final item = sections.removeAt(draggedIndex);
        final insertAt = _hoveringSectionIndex!.clamp(0, sections.length);
        sections.insert(insertAt, item);
      }
    }

    return sections;
  }

  List<WebsiteNavigation> _getDisplayedFooterLinks(WebsiteNavigation section) {
    var links = List<WebsiteNavigation>.from(section.children)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    links = _applyIdOrder(links, _footerLinkOrderOverrideBySection[section.id]);

    // Apply visual reordering during drag
    if (_draggingLinkId != null && _hoveringLinkIndex != null) {
      final draggedIndex = links.indexWhere((l) => l.id == _draggingLinkId);
      if (draggedIndex >= 0 && draggedIndex != _hoveringLinkIndex) {
        final item = links.removeAt(draggedIndex);
        final insertAt = _hoveringLinkIndex!.clamp(0, links.length);
        links.insert(insertAt, item);
      }
    }

    return links;
  }

  Widget _buildCollapsibleSection({
    required String title,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white54,
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [child],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _taglineController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _whatsappController.addListener(_onFieldChanged);
    _addressController.addListener(_onFieldChanged);
    _facebookController.addListener(_onFieldChanged);
    _instagramController.addListener(_onFieldChanged);
    _twitterController.addListener(_onFieldChanged);
    _youtubeController.addListener(_onFieldChanged);
    _tiktokController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!_loaded) return;
    if (!_hasLocalChanges) _hasLocalChanges = true;
    _syncPendingSettingsToProvider();
  }

  void _syncPendingSettingsToProvider() {
    widget.provider.updateFooterSettings({
      'store_tagline': _taglineController.text,
      'contact_email': _emailController.text,
      'contact_phone': _phoneController.text,
      'whatsapp': _whatsappController.text,
      'contact_address': _addressController.text,
      // Align with public store keys
      'facebook': _facebookController.text,
      'instagram': _instagramController.text,
      'twitter': _twitterController.text,
      'youtube': _youtubeController.text,
      'tiktok': _tiktokController.text,
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loadSettings();
      _loaded = true;
    }
  }

  @override
  void didUpdateWidget(covariant _FooterBlockControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.provider, widget.provider)) {
      _loaded = false;
      _hasLocalChanges = false;
      _editingFooterNavId = null;
      _isSavingInlineNav = false;
      _selectedFooterSectionId = null;
      _draggingSectionId = null;
      _hoveringSectionIndex = null;
      _draggingLinkId = null;
      _hoveringLinkIndex = null;
      _loadSettings();
      _loaded = true;
    }
  }

  void _loadSettings() {
    final service = context.read<WebsiteService>();
    _taglineController.text = widget.provider.getEffectiveFooterSetting(
      'store_tagline',
      service.getSetting('store_tagline', ''),
    );
    _emailController.text = widget.provider.getEffectiveFooterSetting(
      'contact_email',
      service.getSetting('contact_email', ''),
    );
    _phoneController.text = widget.provider.getEffectiveFooterSetting(
      'contact_phone',
      service.getSetting('contact_phone', ''),
    );
    _whatsappController.text = widget.provider.getEffectiveFooterSetting(
      'whatsapp',
      service.getSetting('whatsapp', ''),
    );
    _addressController.text = widget.provider.getEffectiveFooterSetting(
      'contact_address',
      service.getSetting('contact_address', ''),
    );

    // Backward compatible: prefer new keys used by store, fallback to legacy *_handle.
    _facebookController.text = widget.provider.getEffectiveFooterSetting(
      'facebook',
      service.getSetting('facebook', service.getSetting('facebook_handle', '')),
    );
    _instagramController.text = widget.provider.getEffectiveFooterSetting(
      'instagram',
      service.getSetting(
          'instagram', service.getSetting('instagram_handle', '')),
    );
    _twitterController.text = widget.provider.getEffectiveFooterSetting(
      'twitter',
      service.getSetting('twitter', service.getSetting('twitter_handle', '')),
    );
    _youtubeController.text = widget.provider.getEffectiveFooterSetting(
      'youtube',
      service.getSetting('youtube', service.getSetting('youtube_handle', '')),
    );
    _tiktokController.text = widget.provider.getEffectiveFooterSetting(
      'tiktok',
      service.getSetting('tiktok', service.getSetting('tiktok_handle', '')),
    );
    _footerSectionOrderOverride = widget.provider.pendingFooterSectionOrder;
    _footerLinkOrderOverrideBySection
      ..clear()
      ..addAll(widget.provider.pendingFooterLinkOrder);
  }

  Future<void> _addFooterSection() async {
    await _showFooterNavDialog(
      title: 'Nueva sección',
      initialIsSection: true,
    );
  }

  Future<void> _addFooterLink({String? parentId}) async {
    await _showFooterNavDialog(
      title: 'Nuevo enlace',
      initialParentId: parentId,
      initialIsSection: false,
    );
  }

  void _beginInlineFooterNavEdit(WebsiteNavigation nav) {
    setState(() {
      _editingFooterNavId = nav.id;

      // Prefill
      _inlineNavLabelController.text = nav.label;
      _inlineNavLinkValueController.text = nav.linkValue ?? '';
      _inlineNavParentId = nav.parentId;
      _inlineNavLinkType = nav.linkType;
      _inlineNavIsVisible = nav.isVisible;
      _inlineNavShowOnDesktop = nav.showOnDesktop;
      _inlineNavShowOnMobile = nav.showOnMobile;
      _inlineNavOpenInNewTab = nav.openInNewTab;

      // If user clicked edit on a section tab, ensure the section is selected.
      if (nav.parentId == null) {
        _selectedFooterSectionId = nav.id;
      }
    });
  }

  void _cancelInlineFooterNavEdit() {
    setState(() {
      _editingFooterNavId = null;
      _isSavingInlineNav = false;
    });
  }

  bool _isEditingNav(WebsiteNavigation nav) => _editingFooterNavId == nav.id;

  bool _isInlineEditingSection(WebsiteNavigation nav) {
    // A footer "section" is a top-level item (parent_id = null).
    // Historically we store it with link_type='action' and blank link_value.
    return nav.parentId == null;
  }

  Widget _buildInlineFooterNavEditor(
    WebsiteNavigation nav, {
    required List<WebsiteNavigation> footerParents,
  }) {
    final isSection = _isInlineEditingSection(nav);

    final visibleParents = footerParents
        .where((p) => p.id != nav.id)
        .map((p) => (p.id, p.label))
        .toList();

    String linkTypeValue(NavLinkType type) => switch (type) {
          NavLinkType.page => 'page',
          NavLinkType.external => 'external',
          NavLinkType.anchor => 'anchor',
          _ => 'page',
        };

    NavLinkType parseLinkTypeValue(String value) => switch (value) {
          'page' => NavLinkType.page,
          'external' => NavLinkType.external,
          'anchor' => NavLinkType.anchor,
          _ => NavLinkType.page,
        };

    String? validate() {
      if (_inlineNavLabelController.text.trim().isEmpty) {
        return 'El texto es requerido.';
      }
      if (!isSection) {
        if (_inlineNavLinkValueController.text.trim().isEmpty) {
          return 'El destino es requerido.';
        }
      }
      return null;
    }

    final errorText = validate();

    final title = isSection ? 'Editar sección' : 'Editar enlace';

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: _cancelInlineFooterNavEdit,
                child: const Text(
                  'Cerrar',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Texto
          _EditorTextField(
            label: 'Texto',
            value: _inlineNavLabelController.text,
            controller: _inlineNavLabelController,
            onChanged: (_) => setState(() {}),
            hint: isSection
                ? 'Ej: Legal, Ayuda, Empresa'
                : 'Ej: Términos y condiciones',
          ),

          if (!isSection) ...[
            const SizedBox(height: 12),
            _EditorDropdown(
              label: 'Sección (opcional)',
              value: _inlineNavParentId ?? '',
              options: <(String, String)>[
                ('', 'Sin sección'),
                ...visibleParents,
              ],
              onChanged: (v) => setState(() {
                _inlineNavParentId = v.isEmpty ? null : v;
              }),
            ),
            const SizedBox(height: 12),
            _EditorDropdown(
              label: 'Tipo',
              value: linkTypeValue(_inlineNavLinkType),
              options: const <(String, String)>[
                ('page', 'Página'),
                ('external', 'URL externa'),
                ('anchor', 'Ancla (#)'),
              ],
              onChanged: (v) => setState(() {
                _inlineNavLinkType = parseLinkTypeValue(v);
                // Reset new tab toggle when leaving external.
                if (_inlineNavLinkType != NavLinkType.external) {
                  _inlineNavOpenInNewTab = false;
                }
              }),
            ),
            const SizedBox(height: 12),
            WebsiteLinkValueEditor(
              label: 'Destino',
              value: _inlineNavLinkValueController.text,
              dense: true,
              darkStyle: true,
              allowInternal: _inlineNavLinkType == NavLinkType.page,
              allowExternal: _inlineNavLinkType == NavLinkType.external,
              allowAnchor: _inlineNavLinkType == NavLinkType.anchor,
              helpText: switch (_inlineNavLinkType) {
                NavLinkType.page =>
                  'Elige una página o ruta del sitio (recomendado).',
                NavLinkType.external => 'Pega un enlace externo (https://...)',
                NavLinkType.anchor =>
                  'Usa un ancla como #seccion (misma página).',
                _ => null,
              },
              onChanged: (v) {
                _inlineNavLinkValueController.text = v;
                setState(() {});
              },
            ),
            if (_inlineNavLinkType == NavLinkType.external) ...[
              const SizedBox(height: 10),
              _EditorToggle(
                label: 'Abrir en nueva pestaña',
                value: _inlineNavOpenInNewTab,
                onChanged: (v) => setState(() => _inlineNavOpenInNewTab = v),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Las secciones son títulos (columnas). No tienen destino.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 12),
          _EditorToggle(
            label: 'Visible',
            value: _inlineNavIsVisible,
            onChanged: (v) => setState(() => _inlineNavIsVisible = v),
          ),
          const SizedBox(height: 8),
          _EditorToggle(
            label: 'Mostrar en escritorio',
            value: _inlineNavShowOnDesktop,
            onChanged: (v) => setState(() => _inlineNavShowOnDesktop = v),
          ),
          const SizedBox(height: 8),
          _EditorToggle(
            label: 'Mostrar en móvil',
            value: _inlineNavShowOnMobile,
            onChanged: (v) => setState(() => _inlineNavShowOnMobile = v),
          ),

          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              errorText,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _isSavingInlineNav ? null : _cancelInlineFooterNavEdit,
                  style: OutlinedButton.styleFrom(
                    side:
                        BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: (errorText != null || _isSavingInlineNav)
                      ? null
                      : () {
                          final editProvider =
                              context.read<WebsiteEditModeProvider>();
                          setState(() => _isSavingInlineNav = true);

                          final updated = WebsiteNavigation(
                            id: nav.id,
                            tenantId: nav.tenantId,
                            menuLocation: MenuLocation.footer,
                            label: _inlineNavLabelController.text.trim(),
                            linkType: isSection
                                ? NavLinkType.action
                                : _inlineNavLinkType,
                            linkValue: isSection
                                ? ''
                                : _inlineNavLinkValueController.text.trim(),
                            openInNewTab: (!isSection &&
                                    _inlineNavLinkType == NavLinkType.external)
                                ? _inlineNavOpenInNewTab
                                : false,
                            parentId: isSection ? null : _inlineNavParentId,
                            orderIndex: nav.orderIndex,
                            isVisible: _inlineNavIsVisible,
                            showOnDesktop: _inlineNavShowOnDesktop,
                            showOnMobile: _inlineNavShowOnMobile,
                            cssClass: nav.cssClass,
                            highlight: nav.highlight,
                            createdAt: nav.createdAt,
                            updatedAt: DateTime.now(),
                            children: nav.children,
                            linkedPage: nav.linkedPage,
                          );

                          editProvider.updateFooterNavItem(updated);

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cambio aplicado. Presiona Guardar para publicarlo.',
                                ),
                                backgroundColor: Color(0xFF00A09D),
                              ),
                            );
                            setState(() {
                              _isSavingInlineNav = false;
                              _editingFooterNavId = null;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A09D),
                    foregroundColor: Colors.white,
                  ),
                  child: _isSavingInlineNav
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _persistFooterSectionOrder(List<String> orderedIds) {
    final editProvider = context.read<WebsiteEditModeProvider>();

    setState(() {
      _footerSectionOrderOverride = orderedIds;
    });

    // Update provider - will be saved when user clicks Guardar
    editProvider.updateFooterSectionOrder(orderedIds);
  }

  void _persistFooterLinkOrder(String parentId, List<String> orderedIds) {
    final editProvider = context.read<WebsiteEditModeProvider>();

    setState(() {
      _footerLinkOrderOverrideBySection[parentId] = orderedIds;
    });

    // Update provider - will be saved when user clicks Guardar
    editProvider.updateFooterLinkOrder(parentId, orderedIds);
  }

  List<String> _moveIdInOrder(List<String> ids, String id, int delta) {
    final fromIndex = ids.indexOf(id);
    if (fromIndex < 0) return ids;

    final toIndex = (fromIndex + delta).clamp(0, ids.length - 1);
    if (toIndex == fromIndex) return ids;

    final next = List<String>.from(ids);
    final moved = next.removeAt(fromIndex);
    next.insert(toIndex, moved);
    return next;
  }

  /// Renders the visual content of a footer section tab (for feedback widget).
  /// This does NOT contain a Draggable to avoid infinite recursion.
  Widget _buildFooterSectionTabContent(
    WebsiteNavigation section, {
    required bool isSelected,
    required Color backgroundColor,
  }) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_handle,
              color: Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              section.label,
              style: TextStyle(
                color: section.isVisible ? Colors.white : Colors.orange,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.more_vert, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  /// Renders the visual content of a footer link row (for feedback widget).
  /// This does NOT contain a Draggable to avoid infinite recursion.
  Widget _buildFooterLinkRowContent(
    WebsiteNavigation link, {
    required double width,
  }) {
    return Material(
      color: const Color(0xFF2D2D2D),
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      shadowColor: Colors.black54,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.drag_handle,
              color: Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                link.label,
                style: TextStyle(
                  color: link.isVisible ? Colors.white70 : Colors.orange,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.more_vert, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  /// Builds a footer link row with Draggable + DragTarget for reordering.
  Widget _buildFooterLinkRow(
    WebsiteNavigation link, {
    required int index,
    required WebsiteNavigation parentSection,
    required int totalCount,
    required List<String> orderedIds,
    required double width,
  }) {
    final isDropTarget = _hoveringLinkIndex == index && _draggingLinkId != null;
    final isEditing = _isEditingNav(link);

    return DragTarget<String>(
      key: ValueKey('footer_link_target_$index'),
      onWillAcceptWithDetails: (details) {
        // Always accept - we'll check for actual reordering in onAccept.
        // Note: Can't use `details.data != link.id` because visual reordering
        // moves the dragged item to the hover position, making them equal!
        return true;
      },
      onMove: (details) {
        // Only update if we're at a different index
        // Note: Don't check details.data != link.id because visual reordering
        // makes them equal at the hover position
        if (_hoveringLinkIndex != index) {
          setState(() {
            _hoveringLinkIndex = index;
          });
        }
      },
      onAcceptWithDetails: (details) {
        // Get fresh section from service to avoid stale children
        final service = context.read<WebsiteService>();
        final freshSection = service.footerNavigation.firstWhere(
          (s) => s.id == parentSection.id,
          orElse: () => parentSection,
        );

        // Get base order and apply current drag state
        var orderedLinks = List<WebsiteNavigation>.from(freshSection.children)
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        orderedLinks = _applyIdOrder(
          orderedLinks,
          _footerLinkOrderOverrideBySection[freshSection.id],
        );

        // Apply the visual reorder from drag state
        if (_draggingLinkId != null && _hoveringLinkIndex != null) {
          final draggedIndex =
              orderedLinks.indexWhere((l) => l.id == _draggingLinkId);
          if (draggedIndex >= 0 && draggedIndex != _hoveringLinkIndex) {
            final item = orderedLinks.removeAt(draggedIndex);
            final insertAt = _hoveringLinkIndex!.clamp(0, orderedLinks.length);
            orderedLinks.insert(insertAt, item);
          }
        }

        final currentOrder = orderedLinks.map((l) => l.id).toList();
        final dragArm = _linkDragArm;
        _commitFooterDragOrder(dragArm, currentOrder);
        setState(() {
          _linkDragArm = null;
          _draggingLinkId = null;
          _hoveringLinkIndex = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDropTarget
                ? Colors.white.withValues(alpha: 0.12)
                : (isEditing
                    ? const Color(0xFF00A09D).withValues(alpha: 0.10)
                    : const Color(0xFF2D2D2D)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDropTarget
                  ? Colors.white24
                  : (isEditing ? const Color(0xFF00A09D) : Colors.white10),
              width: isEditing ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Draggable<String>(
                data: link.id,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                onDragStarted: () {
                  final arm = _captureFooterDragArm(
                    itemId: link.id,
                    parentId: parentSection.id,
                  );
                  setState(() {
                    _linkDragArm = arm;
                    _draggingLinkId = arm == null ? null : link.id;
                  });
                },
                // Note: Don't clear state in onDragEnd - it races with
                // onAcceptWithDetails. Let onAcceptWithDetails handle
                // successful drops, onDraggableCanceled handles failures.
                onDraggableCanceled: (_, __) {
                  _cancelFooterDragArm(_linkDragArm);
                  setState(() {
                    _linkDragArm = null;
                    _draggingLinkId = null;
                    _hoveringLinkIndex = null;
                  });
                },
                feedback: _buildFooterLinkRowContent(link, width: width),
                childWhenDragging: const Icon(
                  Icons.drag_handle,
                  color: Colors.white24,
                  size: 18,
                ),
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(
                    Icons.drag_handle,
                    color: Colors.white54,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  link.label,
                  style: TextStyle(
                    color: link.isVisible ? Colors.white70 : Colors.orange,
                    fontSize: 13,
                  ),
                ),
              ),
              _buildFooterItemActionsMenu(
                link,
                parent: parentSection,
                itemIndex: index,
                totalCount: totalCount,
                orderedIds: orderedIds,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooterSectionTab(
    WebsiteNavigation section, {
    required bool isSelected,
    required bool isDropTarget,
    required int index,
    required int totalCount,
    required List<String> orderedIds,
  }) {
    final isEditing = _isEditingNav(section);
    final bg = isSelected
        ? const Color(0xFF00A09D).withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.06);

    final effectiveBg = isDropTarget
        ? Colors.white.withValues(alpha: 0.10)
        : (isEditing ? const Color(0xFF00A09D).withValues(alpha: 0.12) : bg);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEditing ? const Color(0xFF00A09D) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            _selectedFooterSectionId = section.id;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle-only drag. Feedback uses non-recursive content builder.
                Draggable<String>(
                  data: section.id,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  onDragStarted: () {
                    final arm = _captureFooterDragArm(itemId: section.id);
                    setState(() {
                      _sectionDragArm = arm;
                      _draggingSectionId = arm == null ? null : section.id;
                    });
                  },
                  // Note: Don't clear state in onDragEnd - it races with
                  // onAcceptWithDetails. Let onAcceptWithDetails handle
                  // successful drops, onDraggableCanceled handles failures.
                  onDraggableCanceled: (_, __) {
                    _cancelFooterDragArm(_sectionDragArm);
                    setState(() {
                      _sectionDragArm = null;
                      _draggingSectionId = null;
                      _hoveringSectionIndex = null;
                    });
                  },
                  feedback: _buildFooterSectionTabContent(
                    section,
                    isSelected: isSelected,
                    backgroundColor: bg,
                  ),
                  childWhenDragging: const Icon(
                    Icons.drag_handle,
                    color: Colors.white24,
                    size: 18,
                  ),
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(
                      Icons.drag_handle,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  section.label,
                  style: TextStyle(
                    color: section.isVisible ? Colors.white : Colors.orange,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                _buildFooterItemActionsMenu(
                  section,
                  itemIndex: index,
                  totalCount: totalCount,
                  orderedIds: orderedIds,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterItemActionsMenu(
    WebsiteNavigation nav, {
    WebsiteNavigation? parent,
    int? itemIndex,
    int? totalCount,
    List<String>? orderedIds,
  }) {
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      color: const Color(0xFF2D2D2D),
      icon: const Icon(Icons.more_vert, color: Colors.white70, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'move_prev':
          case 'move_next':
          case 'move_up':
          case 'move_down':
            {
              final ids = orderedIds;
              final index = itemIndex;
              final total = totalCount;

              if (ids == null || index == null || total == null) return;

              // Determine movement direction.
              final delta = switch (value) {
                'move_prev' || 'move_up' => -1,
                'move_next' || 'move_down' => 1,
                _ => 0,
              };
              if (delta == 0) return;

              final nextOrder = _moveIdInOrder(ids, nav.id, delta);
              if (nextOrder.length != ids.length) return;

              if (parent == null) {
                _persistFooterSectionOrder(nextOrder);
              } else {
                _persistFooterLinkOrder(parent.id, nextOrder);
              }
              return;
            }
          case 'add_link':
            await _addFooterLink(parentId: nav.id);
            return;
          case 'toggle_visible':
            await _toggleFooterNavVisibility(nav);
            return;
          case 'edit':
            _beginInlineFooterNavEdit(nav);
            return;
          case 'delete':
            await _deleteFooterNav(nav);
            return;
        }
      },
      itemBuilder: (context) {
        final isSection = nav.parentId == null;
        final canReorder = itemIndex != null && totalCount != null;
        final idx = itemIndex ?? -1;
        final total = totalCount ?? 0;
        final canMovePrev = canReorder && idx > 0;
        final canMoveNext = canReorder && idx >= 0 && idx < (total - 1);

        return <PopupMenuEntry<String>>[
          if (canReorder && (canMovePrev || canMoveNext)) ...[
            if (canMovePrev)
              PopupMenuItem(
                value: isSection ? 'move_prev' : 'move_up',
                child: Text(
                  isSection ? 'Mover a la izquierda' : 'Mover arriba',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (canMoveNext)
              PopupMenuItem(
                value: isSection ? 'move_next' : 'move_down',
                child: Text(
                  isSection ? 'Mover a la derecha' : 'Mover abajo',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            const PopupMenuDivider(),
          ],
          if (isSection)
            const PopupMenuItem(
              value: 'add_link',
              child:
                  Text('Agregar enlace', style: TextStyle(color: Colors.white)),
            ),
          PopupMenuItem(
            value: 'toggle_visible',
            child: Text(
              nav.isVisible ? 'Ocultar' : 'Mostrar',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const PopupMenuItem(
            value: 'edit',
            child: Text('Editar', style: TextStyle(color: Colors.white)),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ];
      },
    );
  }

  Future<void> _toggleFooterNavVisibility(WebsiteNavigation nav) async {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final effective = editProvider.getEffectiveFooterNavItem(nav);
    editProvider.updateFooterNavItem(
      effective.copyWith(isVisible: !effective.isVisible),
    );
  }

  Future<void> _deleteFooterNav(WebsiteNavigation nav) async {
    final websiteService = context.read<WebsiteService>();
    final sourceNavigation = _footerNavigationSourceSnapshot(
      websiteService.footerNavigation,
    );
    final intent = widget.provider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.footer,
      sourceKeys: const <String>{
        WebsiteSitewideAsyncSourceKey.footerNavigation,
      },
    );
    if (intent == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Eliminar', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Eliminar "${nav.label}"?${nav.hasChildren ? "\n\nEsto también eliminará sus enlaces hijos." : ""}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final liveWebsiteService = context.read<WebsiteService>();
    final liveProvider = widget.provider;
    liveProvider.commitSitewideAsyncIntent(intent, () {
      if (_footerNavigationSourceSnapshot(
            liveWebsiteService.footerNavigation,
          ) !=
          sourceNavigation) {
        return WebsiteInlineMutationResult.rejected;
      }
      final liveNavigation = _findFooterNavigation(
        liveWebsiteService.footerNavigation,
        nav.id,
      );
      if (liveNavigation == null) {
        return WebsiteInlineMutationResult.rejected;
      }
      liveProvider.deleteFooterNavItem(liveNavigation);
      return WebsiteInlineMutationResult.committed;
    });
  }

  Future<void> _showFooterNavDialog({
    required String title,
    WebsiteNavigation? existing,
    String? initialParentId,
    required bool initialIsSection,
  }) async {
    final formKey = GlobalKey<FormState>();
    final labelController = TextEditingController(text: existing?.label ?? '');
    final linkValueController =
        TextEditingController(text: existing?.linkValue ?? '');

    var isSection = initialIsSection;
    var isVisible = existing?.isVisible ?? true;
    var showOnDesktop = existing?.showOnDesktop ?? true;
    var showOnMobile = existing?.showOnMobile ?? true;
    var openInNewTab = existing?.openInNewTab ?? false;
    var linkType = existing?.linkType ?? NavLinkType.page;
    var parentId = initialParentId;

    final service = context.read<WebsiteService>();
    final sourceNavigation = _footerNavigationSourceSnapshot(
      service.footerNavigation,
    );
    final intent = widget.provider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.footer,
      sourceKeys: const <String>{
        WebsiteSitewideAsyncSourceKey.footerNavigation,
      },
    );
    if (intent == null) {
      labelController.dispose();
      linkValueController.dispose();
      return;
    }
    final footerParents = widget.provider.getEffectiveFooterNavigation(
      service.footerNavigation,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final effectiveIsSection = isSection;

            String linkTypeValue(NavLinkType type) => switch (type) {
                  NavLinkType.page => 'page',
                  NavLinkType.external => 'external',
                  NavLinkType.anchor => 'anchor',
                  _ => 'page',
                };

            NavLinkType parseLinkTypeValue(String value) => switch (value) {
                  'page' => NavLinkType.page,
                  'external' => NavLinkType.external,
                  'anchor' => NavLinkType.anchor,
                  _ => NavLinkType.page,
                };

            return AlertDialog(
              backgroundColor: const Color(0xFF2D2D2D),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Texto
                        FormField<String>(
                          initialValue: labelController.text,
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Requerido';
                            return null;
                          },
                          builder: (state) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _EditorTextField(
                                  label: 'Texto',
                                  value: labelController.text,
                                  controller: labelController,
                                  onChanged: (v) {
                                    state.didChange(v);
                                    setState(() {});
                                  },
                                  hint: effectiveIsSection
                                      ? 'Ej: Legal, Ayuda, Empresa'
                                      : 'Ej: Términos y condiciones',
                                ),
                                if (state.hasError) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    state.errorText ?? '',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Sección (opcional)
                        _EditorDropdown(
                          label: 'Sección (opcional)',
                          value: parentId ?? '',
                          options: <(String, String)>[
                            ('', 'Sin sección'),
                            ...footerParents.map((p) => (p.id, p.label)),
                          ],
                          onChanged: (v) => setState(() {
                            parentId = v.isEmpty ? null : v;
                          }),
                        ),
                        const SizedBox(height: 14),

                        // Es sección (título)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Es sección (título)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Una sección es un encabezado con enlaces dentro.',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Switch(
                                value: isSection,
                                onChanged: (v) => setState(() {
                                  isSection = v;
                                  if (isSection) {
                                    linkType = NavLinkType.action;
                                    linkValueController.text = '';
                                  }
                                }),
                                activeThumbColor: Colors.white,
                                activeTrackColor: const Color(0xFF00A09D),
                                inactiveThumbColor: Colors.grey.shade400,
                                inactiveTrackColor: Colors.grey.shade700,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),

                        if (!effectiveIsSection) ...[
                          const SizedBox(height: 12),

                          // Tipo
                          _EditorDropdown(
                            label: 'Tipo',
                            value: linkTypeValue(linkType),
                            options: const <(String, String)>[
                              ('page', 'Página'),
                              ('external', 'URL externa'),
                              ('anchor', 'Ancla (#)'),
                            ],
                            onChanged: (v) => setState(() {
                              linkType = parseLinkTypeValue(v);
                            }),
                          ),
                          const SizedBox(height: 12),

                          // Destino
                          FormField<String>(
                            initialValue: linkValueController.text,
                            validator: (v) {
                              final value = (v ?? '').trim();
                              if (value.isEmpty) return 'Requerido';
                              return null;
                            },
                            builder: (state) {
                              final help = switch (linkType) {
                                NavLinkType.page =>
                                  'Elige una página o ruta del sitio (recomendado).',
                                NavLinkType.external =>
                                  'Pega un enlace externo (https://...)',
                                NavLinkType.anchor =>
                                  'Usa un ancla como #seccion (misma página).',
                                _ => null,
                              };

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  WebsiteLinkValueEditor(
                                    label: 'Destino',
                                    value: linkValueController.text,
                                    helpText: help,
                                    dense: true,
                                    darkStyle: true,
                                    allowInternal: linkType == NavLinkType.page,
                                    allowExternal:
                                        linkType == NavLinkType.external,
                                    allowAnchor: linkType == NavLinkType.anchor,
                                    onChanged: (v) {
                                      linkValueController.text = v;
                                      state.didChange(v);
                                      setState(() {});
                                    },
                                  ),
                                  if (state.hasError) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      state.errorText ?? '',
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          if (linkType == NavLinkType.external) ...[
                            const SizedBox(height: 10),
                            _EditorToggle(
                              label: 'Abrir en nueva pestaña',
                              value: openInNewTab,
                              onChanged: (v) =>
                                  setState(() => openInNewTab = v),
                            ),
                          ],
                        ],

                        const SizedBox(height: 12),
                        _EditorToggle(
                          label: 'Visible',
                          value: isVisible,
                          onChanged: (v) => setState(() => isVisible = v),
                        ),
                        const SizedBox(height: 8),
                        _EditorToggle(
                          label: 'Mostrar en escritorio',
                          value: showOnDesktop,
                          onChanged: (v) => setState(() => showOnDesktop = v),
                        ),
                        const SizedBox(height: 8),
                        _EditorToggle(
                          label: 'Mostrar en móvil',
                          value: showOnMobile,
                          onChanged: (v) => setState(() => showOnMobile = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar',
                      style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    final normalizedLinkValue = effectiveIsSection
                        ? ''
                        : linkValueController.text.trim();

                    final nav = WebsiteNavigation(
                      id: existing?.id ?? '',
                      tenantId: existing?.tenantId ?? '',
                      menuLocation: MenuLocation.footer,
                      label: labelController.text.trim(),
                      linkType:
                          effectiveIsSection ? NavLinkType.action : linkType,
                      linkValue: normalizedLinkValue,
                      openInNewTab: (!effectiveIsSection &&
                              linkType == NavLinkType.external)
                          ? openInNewTab
                          : false,
                      parentId: parentId,
                      orderIndex: existing?.orderIndex ?? 0,
                      isVisible: isVisible,
                      showOnDesktop: showOnDesktop,
                      showOnMobile: showOnMobile,
                      createdAt: existing?.createdAt ?? DateTime.now(),
                      updatedAt: DateTime.now(),
                    );

                    final liveService = this.context.read<WebsiteService>();
                    final liveProvider = widget.provider;
                    final result = liveProvider.commitSitewideAsyncIntent(
                      intent,
                      () {
                        if (_footerNavigationSourceSnapshot(
                              liveService.footerNavigation,
                            ) !=
                            sourceNavigation) {
                          return WebsiteInlineMutationResult.rejected;
                        }
                        liveProvider.createFooterNavDraft(nav);
                        return WebsiteInlineMutationResult.committed;
                      },
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (result == WebsiteInlineMutationResult.rejected) {
                      return;
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A09D)),
                  child: Text(existing != null ? 'Aplicar' : 'Agregar'),
                ),
              ],
            );
          },
        );
      },
    );
    labelController.dispose();
    linkValueController.dispose();
  }

  @override
  void dispose() {
    _taglineController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _addressController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _youtubeController.dispose();
    _tiktokController.dispose();
    _inlineNavLabelController.dispose();
    _inlineNavLinkValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final websiteService = context.watch<WebsiteService>();
    final footerNavItems = websiteService.footerNavigation;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.web_asset_off,
                    color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Footer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Pie de página del sitio',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildCollapsibleSection(
            title: 'Marca',
            initiallyExpanded: false,
            child: Column(
              children: [
                _EditorTextField(
                  label: 'Eslogan / Tagline',
                  value: _taglineController.text,
                  controller: _taglineController,
                  onChanged: (_) {},
                  hint: 'Todo lo que necesitas para tu bicicleta',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Contacto',
            initiallyExpanded: false,
            child: Column(
              children: [
                _EditorTextField(
                  label: 'Email',
                  value: _emailController.text,
                  controller: _emailController,
                  onChanged: (_) {},
                  hint: 'contacto@mitienda.cl',
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Teléfono',
                  value: _phoneController.text,
                  controller: _phoneController,
                  onChanged: (_) {},
                  hint: '+56 2 1234 5678',
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Dirección',
                  value: _addressController.text,
                  controller: _addressController,
                  onChanged: (_) {},
                  hint: 'Av. Principal 123, Santiago',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Redes sociales',
            initiallyExpanded: false,
            child: Column(
              children: [
                _EditorTextField(
                  label: 'Facebook',
                  value: _facebookController.text,
                  controller: _facebookController,
                  onChanged: (_) {},
                  hint: 'mitienda',
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Instagram',
                  value: _instagramController.text,
                  controller: _instagramController,
                  onChanged: (_) {},
                  hint: '@mitienda',
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Twitter/X',
                  value: _twitterController.text,
                  controller: _twitterController,
                  onChanged: (_) {},
                  hint: '@mitienda',
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'YouTube',
                  value: _youtubeController.text,
                  controller: _youtubeController,
                  onChanged: (_) {},
                  hint: 'mitienda',
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'WhatsApp',
                  value: _whatsappController.text,
                  controller: _whatsappController,
                  onChanged: (_) {},
                  hint: '+56912345678',
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'TikTok',
                  value: _tiktokController.text,
                  controller: _tiktokController,
                  onChanged: (_) {},
                  hint: '@mitienda',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Enlaces del footer',
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Secciones = títulos (columnas) dentro del footer. Se guarda en Navegación (menu_location=footer) y se refleja de inmediato en el preview.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AddItemButton(
                        label: 'Agregar sección',
                        onPressed: _addFooterSection,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AddItemButton(
                        label: 'Agregar enlace',
                        onPressed: () =>
                            _addFooterLink(parentId: _selectedFooterSectionId),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (footerNavItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Text(
                      'Todavía no hay navegación del footer guardada. Abajo del sitio se ven enlaces “por defecto”.\n\nAgrega una sección/enlace para empezar y quedará guardado acá.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  )
                else
                  Builder(
                    builder: (context) {
                      final sections =
                          _getDisplayedFooterSections(websiteService);

                      final effectiveSelectedId = (_selectedFooterSectionId !=
                                  null &&
                              sections
                                  .any((s) => s.id == _selectedFooterSectionId))
                          ? _selectedFooterSectionId!
                          : sections.first.id;

                      if (effectiveSelectedId != _selectedFooterSectionId) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() {
                            _selectedFooterSectionId = effectiveSelectedId;
                          });
                        });
                      }

                      final selectedSection = sections.firstWhere(
                        (s) => s.id == effectiveSelectedId,
                        orElse: () => sections.first,
                      );

                      final links = _getDisplayedFooterLinks(selectedSection);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // "Tabs" (sections) as a horizontal reorderable strip
                          SizedBox(
                            height: 40,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children:
                                    List.generate(sections.length, (index) {
                                  final section = sections[index];
                                  final isSelected =
                                      section.id == effectiveSelectedId;

                                  final orderedSectionIds =
                                      sections.map((s) => s.id).toList();

                                  return DragTarget<String>(
                                    onWillAcceptWithDetails: (details) {
                                      return details.data != section.id;
                                    },
                                    onMove: (details) {
                                      if (details.data != section.id &&
                                          _hoveringSectionIndex != index) {
                                        setState(() {
                                          _hoveringSectionIndex = index;
                                        });
                                      }
                                    },
                                    onLeave: (_) {
                                      // Don't clear immediately to avoid flicker
                                    },
                                    onAcceptWithDetails: (details) {
                                      // Get base order from service
                                      var orderedSections =
                                          List<WebsiteNavigation>.from(
                                              websiteService.footerNavigation)
                                            ..sort((a, b) => a.orderIndex
                                                .compareTo(b.orderIndex));
                                      orderedSections = _applyIdOrder(
                                        orderedSections,
                                        _footerSectionOrderOverride,
                                      );

                                      // Apply the visual reorder from drag state
                                      if (_draggingSectionId != null &&
                                          _hoveringSectionIndex != null) {
                                        final draggedIndex =
                                            orderedSections.indexWhere((s) =>
                                                s.id == _draggingSectionId);
                                        if (draggedIndex >= 0 &&
                                            draggedIndex !=
                                                _hoveringSectionIndex) {
                                          final item = orderedSections
                                              .removeAt(draggedIndex);
                                          final insertAt =
                                              _hoveringSectionIndex!.clamp(
                                                  0, orderedSections.length);
                                          orderedSections.insert(
                                              insertAt, item);
                                        }
                                      }

                                      final currentOrder = orderedSections
                                          .map((s) => s.id)
                                          .toList();
                                      final dragArm = _sectionDragArm;
                                      _commitFooterDragOrder(
                                        dragArm,
                                        currentOrder,
                                      );
                                      setState(() {
                                        _sectionDragArm = null;
                                        _draggingSectionId = null;
                                        _hoveringSectionIndex = null;
                                      });
                                    },
                                    builder:
                                        (context, candidateData, rejectedData) {
                                      final isDropTarget =
                                          candidateData.isNotEmpty;
                                      return Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        child: ConstrainedBox(
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  height: 40),
                                          child: _buildFooterSectionTab(
                                            section,
                                            isSelected: isSelected,
                                            isDropTarget: isDropTarget,
                                            index: index,
                                            totalCount: sections.length,
                                            orderedIds: orderedSectionIds,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Selected section header + quick add
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () => _beginInlineFooterNavEdit(
                                          selectedSection),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6, horizontal: 6),
                                        child: Text(
                                          selectedSection.label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add,
                                      color: Colors.white70),
                                  tooltip: 'Agregar enlace',
                                  onPressed: () => _addFooterLink(
                                      parentId: selectedSection.id),
                                ),
                              ],
                            ),
                          ),

                          // Inline editor for the selected section (when editing a section)
                          if (_isEditingNav(selectedSection))
                            _buildInlineFooterNavEditor(
                              selectedSection,
                              footerParents: sections,
                            ),

                          const SizedBox(height: 10),

                          if (links.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: const Text(
                                'Esta sección no tiene enlaces todavía.',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            )
                          else
                            ConstraintLayoutBuilder(
                              builder: (context, constraints) {
                                final listWidth = constraints.maxWidth;
                                return Column(
                                  children:
                                      List.generate(links.length, (index) {
                                    final link = links[index];
                                    final orderedLinkIds =
                                        links.map((l) => l.id).toList();
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildFooterLinkRow(
                                          link,
                                          index: index,
                                          parentSection: selectedSection,
                                          totalCount: links.length,
                                          orderedIds: orderedLinkIds,
                                          width: listWidth,
                                        ),
                                        if (_isEditingNav(link))
                                          _buildInlineFooterNavEditor(
                                            link,
                                            footerParents: sections,
                                          ),
                                      ],
                                    );
                                  }),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AddItemButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AddItemButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF00A09D).withValues(alpha: 0.5),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Color(0xFF00A09D), size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF00A09D), fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
