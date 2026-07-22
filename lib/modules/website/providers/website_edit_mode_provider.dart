import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/website_page_models.dart';
import '../models/website_action.dart';
import '../models/canvas_element_factory.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';

const _uuid = Uuid();

/// Device preview modes for the website editor
enum DevicePreviewMode {
  desktop,
  tablet,
  mobile,
}

/// The active task surface inside the Website Builder.
///
/// Page composition is the only workspace that owns the persistent block
/// inspector. Management workspaces use the full viewport while preserving the
/// editor draft in this provider.
enum WebsiteWorkspaceMode {
  pageEditor,
  catalog,
  structure,
  settings,
  operations,
}

/// Provider for website inline edit mode state.
/// Tracks edit mode, selected block, and pending changes.
///
/// Two modes:
/// - Preview mode: Shows the top bar (isPreviewMode = true)
/// - Edit mode: Shows the side panel (isEditMode = true)
class WebsiteEditModeProvider extends ChangeNotifier {
  @override
  void notifyListeners() {
    super.notifyListeners();
  }

  bool _isPreviewMode = false; // Preview with top bar
  bool _isEditMode = false; // Full edit with side panel
  WebsiteWorkspaceMode _workspaceMode = WebsiteWorkspaceMode.pageEditor;
  DevicePreviewMode _devicePreviewMode =
      DevicePreviewMode.desktop; // Persist preview options

  String? _selectedBlockId;
  int _selectionVersion = 0; // Tracks explicit selection events
  final Map<String, int> _carouselSlideSelections = {};
  final Map<String, String?> _canvasElementSelections = {};
  bool _hasUnsavedChanges = false;
  bool _hasHeaderChanges = false; // Track header-specific changes
  List<Map<String, dynamic>> _blocks = [];
  Map<String, dynamic> _settings = {};

  // Multi-page editing support (Dec 2025)
  String? _currentPageId; // The page ID being edited (null = home page)
  String? _currentPageSlug; // The page slug for navigation

  // Screenshot capability
  final GlobalKey _screenshotKey = GlobalKey();
  GlobalKey get screenshotKey => _screenshotKey;

  // Pending header settings (to be saved with main save button)
  Map<String, String> _pendingHeaderSettings = {};

  // Key for capturing the preview area for color picking
  final GlobalKey previewRepaintKey = GlobalKey();

  // Pending site-wide settings (to be saved with main save button)
  // Example: site_published, store_name, store_description, etc.
  Map<String, String> _pendingSiteSettings = {};
  bool _hasSiteSettingsChanges = false;

  // Pending footer settings (to be saved with main save button)
  // These are applied immediately in the UI but only saved when user clicks "Guardar".
  Map<String, String> _pendingFooterSettings = {};
  bool _hasFooterChanges = false;

  // Pending footer navigation order changes (saved with Guardar button)
  List<String>? _pendingFooterSectionOrder;
  Map<String, List<String>> _pendingFooterLinkOrder = {};

  // Pending footer navigation item edits (label + destination)
  // Applied immediately in live preview, saved when user clicks "Guardar".
  final Map<String, String> _pendingFooterNavLabels = {};
  final Map<String, NavLinkType> _pendingFooterNavLinkTypes = {};
  final Map<String, String?> _pendingFooterNavLinkValues = {};
  final Map<String, bool> _pendingFooterNavOpenInNewTab = {};
  final Map<String, WebsiteNavigation> _pendingFooterNavItems = {};
  final Map<String, WebsiteNavigation> _pendingFooterNavCreates = {};
  final Set<String> _pendingFooterNavDeletes = {};

  // Transient selection for on-canvas inline editing
  String? _selectedFooterNavId;

  // Pending theme settings for live preview
  // These are applied immediately in the UI but only saved when user clicks "Guardar"
  Map<String, String> _pendingThemeSettings = {};
  bool _hasThemeChanges = false;

  // Pending category visibility changes (saved with Guardar button)
  // Key: category ID, Value: show_on_website value
  final Map<String, bool> _pendingCategoryVisibility = {};
  bool _hasCategoryChanges = false;

  // Pending page-level SEO (saved with Guardar button)
  // Keyed by route key / slug (e.g. 'inicio', 'productos', 'terminos')
  // Values: {'meta_title': '...', 'meta_description': '...'}
  final Map<String, Map<String, String>> _pendingPageSeo = {};
  bool _hasSeoChanges = false;

  // History for undo/redo
  final List<List<Map<String, dynamic>>> _history = [];
  int _historyIndex = -1;
  final int _maxHistory = 50;

  // Getters
  bool get isPreviewMode => _isPreviewMode;
  bool get isEditMode => _isEditMode;
  bool get isInEditorContext =>
      _isPreviewMode || _isEditMode; // Either preview or edit
  WebsiteWorkspaceMode get workspaceMode => _workspaceMode;
  bool get isPageEditorWorkspace =>
      _workspaceMode == WebsiteWorkspaceMode.pageEditor;
  bool get isManagementWorkspace => !isPageEditorWorkspace;
  DevicePreviewMode get devicePreviewMode => _devicePreviewMode;
  String? get selectedBlockId => _selectedBlockId;
  int get selectionVersion => _selectionVersion;

  /// Transient inspector/canvas selection. This is UI state and must never be
  /// persisted into block data or mark the page as changed.
  int carouselSlideSelection(String blockId, int slideCount) {
    if (slideCount <= 0) return 0;
    return (_carouselSlideSelections[blockId] ?? 0)
        .clamp(0, slideCount - 1)
        .toInt();
  }

  String _canvasSelectionKey(String blockId, int? slideIndex) =>
      '$blockId:${slideIndex == null ? 'root' : 'slide_$slideIndex'}';

  /// Selected nested Canvas layer for a standalone Canvas block or a composed
  /// carousel slide. This is editor-only state: it never enters block_data,
  /// persistence, dirty tracking, or undo history.
  String? canvasElementSelection(String blockId, {int? slideIndex}) =>
      _canvasElementSelections[_canvasSelectionKey(blockId, slideIndex)];

  /// Select a nested Canvas layer while restoring its owning block/slide.
  /// Repeated selection is intentional and increments [selectionVersion] so
  /// the inspector can recover after another surface cleared its context.
  void selectCanvasElement(
    String blockId,
    String? elementId, {
    int? slideIndex,
    int? slideCount,
  }) {
    _selectedBlockId = blockId;
    if (slideIndex != null && slideCount != null && slideCount > 0) {
      _carouselSlideSelections[blockId] =
          slideIndex.clamp(0, slideCount - 1).toInt();
    }
    _canvasElementSelections[_canvasSelectionKey(blockId, slideIndex)] =
        elementId;
    _selectionVersion++;
    notifyListeners();
  }

  /// Nested selection for the currently selected block, used by the inspector
  /// identity and scroll reset contract.
  String? get selectedCanvasElementId {
    final blockId = _selectedBlockId;
    if (blockId == null) return null;
    final block = getBlock(blockId);
    if (block == null) return null;
    final type = (block['block_type'] ?? block['type'] ?? '').toString();
    if (type == WebsiteBlockType.carousel.name) {
      final data = Map<String, dynamic>.from(block['block_data'] ?? const {});
      final slides = data['slides'];
      final count = slides is List ? slides.length : 0;
      if (count <= 0) return null;
      return canvasElementSelection(
        blockId,
        slideIndex: carouselSlideSelection(blockId, count),
      );
    }
    if (type == WebsiteBlockType.canvas.name) {
      return canvasElementSelection(blockId);
    }
    return null;
  }

  void selectCarouselSlide(String blockId, int index, int slideCount) {
    if (slideCount <= 0) return;
    final normalized = index.clamp(0, slideCount - 1).toInt();
    _carouselSlideSelections[blockId] = normalized;
    _selectedBlockId = blockId;
    _selectionVersion++;
    notifyListeners();
  }

  bool get hasUnsavedChanges =>
      _hasUnsavedChanges ||
      _hasHeaderChanges ||
      _hasSiteSettingsChanges ||
      _hasSeoChanges ||
      _hasThemeChanges ||
      _hasFooterChanges ||
      _hasCategoryChanges;
  bool get hasHeaderChanges => _hasHeaderChanges;
  bool get hasSiteSettingsChanges => _hasSiteSettingsChanges;
  bool get hasThemeChanges => _hasThemeChanges;
  bool get hasFooterChanges => _hasFooterChanges;
  bool get hasCategoryChanges => _hasCategoryChanges;
  Map<String, bool> get pendingCategoryVisibility => _pendingCategoryVisibility;
  List<Map<String, dynamic>> get blocks => _blocks;
  Map<String, dynamic> get settings => _settings;
  Map<String, String> get pendingHeaderSettings => _pendingHeaderSettings;
  Map<String, String> get pendingSiteSettings => _pendingSiteSettings;
  Map<String, String> get pendingFooterSettings => _pendingFooterSettings;
  Map<String, String> get pendingThemeSettings => _pendingThemeSettings;
  Map<String, Map<String, String>> get pendingPageSeo => _pendingPageSeo;
  Map<String, List<String>> get pendingFooterLinkOrder =>
      _pendingFooterLinkOrder;

  Map<String, String> get pendingFooterNavLabels => _pendingFooterNavLabels;
  Map<String, NavLinkType> get pendingFooterNavLinkTypes =>
      _pendingFooterNavLinkTypes;
  Map<String, String?> get pendingFooterNavLinkValues =>
      _pendingFooterNavLinkValues;
  Map<String, bool> get pendingFooterNavOpenInNewTab =>
      _pendingFooterNavOpenInNewTab;
  Map<String, WebsiteNavigation> get pendingFooterNavItems =>
      _pendingFooterNavItems;
  Map<String, WebsiteNavigation> get pendingFooterNavCreates =>
      _pendingFooterNavCreates;
  Set<String> get pendingFooterNavDeletes => _pendingFooterNavDeletes;

  String? get selectedFooterNavId => _selectedFooterNavId;
  bool get canUndo => _historyIndex > 0;
  bool get canRedo => _historyIndex < _history.length - 1;

  // Multi-page editing getters
  String? get currentPageId => _currentPageId;
  String? get currentPageSlug => _currentPageSlug;
  bool get isEditingHomePage => _currentPageId == null;

  /// Switch task surfaces without reloading or clearing the current page draft.
  void openWorkspace(WebsiteWorkspaceMode mode) {
    if (_workspaceMode == mode) return;
    _workspaceMode = mode;
    notifyListeners();
  }

  void returnToPageEditor() {
    openWorkspace(WebsiteWorkspaceMode.pageEditor);
  }

  /// Update the current page context without resetting blocks/settings.
  ///
  /// Useful when the page row is created/resolved at save-time and we want
  /// subsequent saves to target the correct page.
  void updateCurrentPageContext({
    String? pageId,
    String? pageSlug,
  }) {
    _currentPageId = pageId;
    _currentPageSlug = pageSlug;
    notifyListeners();
  }

  /// Mark header as having unsaved changes
  void markHeaderChanged() {
    _hasHeaderChanges = true;
    notifyListeners();
  }

  /// Update pending header settings (will be saved with main save button)
  void updateHeaderSettings(Map<String, String> settings) {
    _pendingHeaderSettings = Map<String, String>.from(settings);
    _hasHeaderChanges = true;
    debugPrint(
        '📝 [EditProvider] Header settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Clear header changed flag (after save)
  void clearHeaderChanged() {
    _hasHeaderChanges = false;
    _pendingHeaderSettings = {};
    notifyListeners();
  }

  /// Update a single footer setting for live preview
  void updateFooterSetting(String key, String value) {
    _pendingFooterSettings[key] = value;
    _hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple footer settings at once
  void updateFooterSettings(Map<String, String> settings) {
    _pendingFooterSettings.addAll(settings);
    _hasFooterChanges = true;
    debugPrint(
        '🦶 [EditProvider] Footer settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Get effective footer setting (pending value if exists, otherwise from settings)
  String getEffectiveFooterSetting(String key, String defaultValue) {
    if (_pendingFooterSettings.containsKey(key)) {
      return _pendingFooterSettings[key]!;
    }
    final saved = _settings[key];
    if (saved != null) return saved.toString();
    return defaultValue;
  }

  /// Get pending footer section order (for visual display)
  List<String>? get pendingFooterSectionOrder => _pendingFooterSectionOrder;

  /// Get pending footer link order for a section
  List<String>? getPendingFooterLinkOrder(String sectionId) =>
      _pendingFooterLinkOrder[sectionId];

  /// Update pending footer section order (does not save until Guardar)
  void updateFooterSectionOrder(List<String> orderedIds) {
    _pendingFooterSectionOrder = orderedIds;
    _hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer section order updated (pending save)');
    notifyListeners();
  }

  /// Update pending footer link order for a section (does not save until Guardar)
  void updateFooterLinkOrder(String sectionId, List<String> orderedIds) {
    _pendingFooterLinkOrder[sectionId] = orderedIds;
    _hasFooterChanges = true;
    debugPrint(
        '🦶 [EditProvider] Footer link order for $sectionId updated (pending save)');
    notifyListeners();
  }

  /// Select a footer navigation item for on-canvas inline editing.
  void selectFooterNavItem(String? navId) {
    _selectedFooterNavId = navId;
    _selectionVersion++;
    debugPrint(
        '👉 [EditProvider] Footer Nav Selected: $navId (v$_selectionVersion)');
    notifyListeners();
  }

  /// Update a footer navigation label (live preview + saved with Guardar).
  void updateFooterNavLabel(String navId, String label) {
    _pendingFooterNavLabels[navId] = label;
    _hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer nav label updated: $navId = $label');
    notifyListeners();
  }

  /// Update a footer navigation destination (live preview + saved with Guardar).
  void updateFooterNavDestination(
    String navId, {
    required NavLinkType linkType,
    required String? linkValue,
    bool? openInNewTab,
  }) {
    _pendingFooterNavLinkTypes[navId] = linkType;
    _pendingFooterNavLinkValues[navId] = linkValue;
    if (openInNewTab != null) {
      _pendingFooterNavOpenInNewTab[navId] = openInNewTab;
    }
    _hasFooterChanges = true;
    debugPrint(
        '🦶 [EditProvider] Footer nav destination updated: $navId = ${linkType.value}:$linkValue');
    notifyListeners();
  }

  /// Update a footer navigation item as staged editor state.
  ///
  /// Used by the side-panel footer editor for fields beyond label/destination
  /// such as visibility, parent section, and device visibility.
  void updateFooterNavItem(WebsiteNavigation nav) {
    if (_pendingFooterNavCreates.containsKey(nav.id)) {
      _pendingFooterNavCreates[nav.id] = nav;
    } else {
      _pendingFooterNavItems[nav.id] = nav;
    }
    _hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer nav item updated: ${nav.id}');
    notifyListeners();
  }

  WebsiteNavigation createFooterNavDraft(WebsiteNavigation nav) {
    final draftId = nav.id.trim().isEmpty ? 'draft_${_uuid.v4()}' : nav.id;
    final draft = WebsiteNavigation(
      id: draftId,
      tenantId: nav.tenantId,
      menuLocation: nav.menuLocation,
      label: nav.label,
      icon: nav.icon,
      linkType: nav.linkType,
      linkValue: nav.linkValue,
      openInNewTab: nav.openInNewTab,
      parentId: nav.parentId,
      orderIndex: nav.orderIndex,
      isVisible: nav.isVisible,
      showOnDesktop: nav.showOnDesktop,
      showOnMobile: nav.showOnMobile,
      cssClass: nav.cssClass,
      highlight: nav.highlight,
      createdAt: nav.createdAt,
      updatedAt: nav.updatedAt,
      children: nav.children,
      linkedPage: nav.linkedPage,
    );

    _pendingFooterNavCreates[draft.id] = draft;
    _pendingFooterNavDeletes.remove(draft.id);
    _hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer nav draft created: ${draft.id}');
    notifyListeners();
    return draft;
  }

  void deleteFooterNavItem(WebsiteNavigation nav) {
    final ids = <String>{};

    void collect(WebsiteNavigation item) {
      ids.add(item.id);
      for (final child in item.children) {
        collect(child);
      }
    }

    collect(nav);

    var foundDraftChild = true;
    while (foundDraftChild) {
      foundDraftChild = false;
      for (final draft in _pendingFooterNavCreates.values) {
        if (draft.parentId != null &&
            ids.contains(draft.parentId) &&
            ids.add(draft.id)) {
          foundDraftChild = true;
        }
      }
    }

    for (final id in ids) {
      if (_pendingFooterNavCreates.remove(id) == null) {
        _pendingFooterNavDeletes.add(id);
      }
      _pendingFooterNavItems.remove(id);
      _pendingFooterNavLabels.remove(id);
      _pendingFooterNavLinkTypes.remove(id);
      _pendingFooterNavLinkValues.remove(id);
      _pendingFooterNavOpenInNewTab.remove(id);
    }

    _hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer nav items deleted: ${ids.join(', ')}');
    notifyListeners();
  }

  String getEffectiveFooterNavLabel(String navId, String savedLabel) {
    if (_pendingFooterNavLabels.containsKey(navId)) {
      return _pendingFooterNavLabels[navId]!;
    }
    return savedLabel;
  }

  NavLinkType getEffectiveFooterNavLinkType(String navId, NavLinkType saved) {
    return _pendingFooterNavLinkTypes[navId] ?? saved;
  }

  String? getEffectiveFooterNavLinkValue(String navId, String? saved) {
    if (_pendingFooterNavLinkValues.containsKey(navId)) {
      return _pendingFooterNavLinkValues[navId];
    }
    return saved;
  }

  bool getEffectiveFooterNavOpenInNewTab(String navId, bool saved) {
    if (_pendingFooterNavOpenInNewTab.containsKey(navId)) {
      return _pendingFooterNavOpenInNewTab[navId]!;
    }
    return saved;
  }

  WebsiteNavigation getEffectiveFooterNavItem(WebsiteNavigation saved) {
    final staged = _pendingFooterNavItems[saved.id];
    final source = staged ?? saved;
    final hasLinkValue = _pendingFooterNavLinkValues.containsKey(saved.id);

    return WebsiteNavigation(
      id: saved.id,
      tenantId: saved.tenantId,
      menuLocation: source.menuLocation,
      label: _pendingFooterNavLabels[saved.id] ?? source.label,
      icon: source.icon,
      linkType: _pendingFooterNavLinkTypes[saved.id] ?? source.linkType,
      linkValue: hasLinkValue
          ? _pendingFooterNavLinkValues[saved.id]
          : source.linkValue,
      openInNewTab:
          _pendingFooterNavOpenInNewTab[saved.id] ?? source.openInNewTab,
      parentId: source.parentId,
      orderIndex: source.orderIndex,
      isVisible: source.isVisible,
      showOnDesktop: source.showOnDesktop,
      showOnMobile: source.showOnMobile,
      cssClass: source.cssClass,
      highlight: source.highlight,
      createdAt: saved.createdAt,
      updatedAt: source.updatedAt,
      children: source.children,
      linkedPage: saved.linkedPage,
    );
  }

  List<WebsiteNavigation> getEffectiveFooterNavigation(
    List<WebsiteNavigation> savedRoots,
  ) {
    final byId = <String, WebsiteNavigation>{};

    void collect(WebsiteNavigation item) {
      byId[item.id] = item;
      for (final child in item.children) {
        collect(child);
      }
    }

    for (final root in savedRoots) {
      collect(root);
    }
    byId.addAll(_pendingFooterNavCreates);
    byId.removeWhere((id, _) => _pendingFooterNavDeletes.contains(id));

    final effectiveById = <String, WebsiteNavigation>{
      for (final entry in byId.entries)
        entry.key: getEffectiveFooterNavItem(entry.value),
    };
    final childrenByParent = <String, List<WebsiteNavigation>>{};
    final roots = <WebsiteNavigation>[];

    for (final item in effectiveById.values) {
      final parentId = item.parentId;
      if (parentId == null || !effectiveById.containsKey(parentId)) {
        roots.add(item);
      } else {
        childrenByParent.putIfAbsent(parentId, () => []).add(item);
      }
    }

    WebsiteNavigation buildNode(WebsiteNavigation item, Set<String> path) {
      if (path.contains(item.id)) return item.copyWith(children: const []);
      final nextPath = <String>{...path, item.id};
      final children = List<WebsiteNavigation>.from(
        childrenByParent[item.id] ?? const <WebsiteNavigation>[],
      )..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return item.copyWith(
        children: children.map((child) => buildNode(child, nextPath)).toList(),
      );
    }

    roots.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return roots.map((root) => buildNode(root, const <String>{})).toList();
  }

  /// Clear footer changed flag (after save)
  void clearFooterChanges() {
    _hasFooterChanges = false;
    _pendingFooterSettings = {};
    _pendingFooterSectionOrder = null;
    _pendingFooterLinkOrder = {};
    _pendingFooterNavLabels.clear();
    _pendingFooterNavLinkTypes.clear();
    _pendingFooterNavLinkValues.clear();
    _pendingFooterNavOpenInNewTab.clear();
    _pendingFooterNavItems.clear();
    _pendingFooterNavCreates.clear();
    _pendingFooterNavDeletes.clear();
    _selectedFooterNavId = null;
    notifyListeners();
  }

  /// Update a single theme setting for live preview
  void updateThemeSetting(String key, String value) {
    _pendingThemeSettings[key] = value;
    _hasThemeChanges = true;
    debugPrint('🎨 [EditProvider] Theme setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple theme settings at once
  void updateThemeSettings(Map<String, String> settings) {
    _pendingThemeSettings.addAll(settings);
    _hasThemeChanges = true;
    debugPrint(
        '🎨 [EditProvider] Theme settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Get effective theme setting (pending value if exists, otherwise from settings)
  String getEffectiveThemeSetting(String key, String defaultValue) {
    // First check pending theme settings (live preview)
    if (_pendingThemeSettings.containsKey(key)) {
      return _pendingThemeSettings[key]!;
    }
    // Fall back to saved settings
    final saved = _settings[key];
    if (saved != null) return saved.toString();
    return defaultValue;
  }

  /// Clear theme changed flag (after save)
  void clearThemeChanges() {
    _hasThemeChanges = false;
    _pendingThemeSettings = {};
    notifyListeners();
  }

  /// Update category visibility (saved with Guardar button)
  void updateCategoryVisibility(String categoryId, bool showOnWebsite) {
    _pendingCategoryVisibility[categoryId] = showOnWebsite;
    _hasCategoryChanges = true;
    debugPrint(
        '📁 [EditProvider] Category visibility updated: $categoryId = $showOnWebsite');
    notifyListeners();
  }

  /// Get effective category visibility (pending value if exists)
  bool? getEffectiveCategoryVisibility(String categoryId) {
    if (_pendingCategoryVisibility.containsKey(categoryId)) {
      return _pendingCategoryVisibility[categoryId];
    }
    return null; // No pending change
  }

  /// Clear category changes (after save)
  void clearCategoryChanges() {
    _hasCategoryChanges = false;
    _pendingCategoryVisibility.clear();
    notifyListeners();
  }

  /// Update a single site-wide setting for live preview (saved with Guardar)
  void updateSiteSetting(String key, String value) {
    _pendingSiteSettings[key] = value;
    _hasSiteSettingsChanges = true;
    debugPrint('🏁 [EditProvider] Site setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple site-wide settings at once (saved with Guardar)
  void updateSiteSettings(Map<String, String> settings) {
    _pendingSiteSettings.addAll(settings);
    _hasSiteSettingsChanges = true;
    debugPrint(
        '🏁 [EditProvider] Site settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Get effective site-wide setting (pending value if exists, otherwise from settings)
  String getEffectiveSiteSetting(String key, String defaultValue) {
    if (_pendingSiteSettings.containsKey(key)) {
      return _pendingSiteSettings[key]!;
    }
    final saved = _settings[key];
    if (saved != null) return saved.toString();
    return defaultValue;
  }

  /// Clear site-wide settings changed flag (after save)
  void clearSiteSettingsChanges() {
    _hasSiteSettingsChanges = false;
    _pendingSiteSettings = {};
    notifyListeners();
  }

  Map<String, String>? getPendingPageSeo(String routeKey) {
    return _pendingPageSeo[routeKey];
  }

  /// Stage page-level SEO changes (saved on global Guardar).
  ///
  /// We keep this keyed by route key so users can adjust multiple pages
  /// without losing edits when navigating inside the persistent editor.
  void updatePageSeo({
    required String routeKey,
    required String metaTitle,
    required String metaDescription,
  }) {
    _pendingPageSeo[routeKey] = {
      'meta_title': metaTitle,
      'meta_description': metaDescription,
    };
    _hasSeoChanges = true;
    debugPrint('🔎 [EditProvider] Page SEO updated (pending save): $routeKey');
    notifyListeners();
  }

  void clearSeoChanges() {
    _hasSeoChanges = false;
    _pendingPageSeo.clear();
    notifyListeners();
  }

  void _clearPendingEditorChanges() {
    _hasUnsavedChanges = false;
    _hasHeaderChanges = false;
    _hasSiteSettingsChanges = false;
    _hasSeoChanges = false;
    _hasThemeChanges = false;
    _hasFooterChanges = false;
    _hasCategoryChanges = false;

    _pendingHeaderSettings = {};
    _pendingSiteSettings = {};
    _pendingFooterSettings = {};
    _pendingThemeSettings = {};
    _pendingFooterSectionOrder = null;
    _pendingFooterLinkOrder = {};
    _pendingFooterNavLabels.clear();
    _pendingFooterNavLinkTypes.clear();
    _pendingFooterNavLinkValues.clear();
    _pendingFooterNavOpenInNewTab.clear();
    _pendingFooterNavItems.clear();
    _pendingFooterNavCreates.clear();
    _pendingFooterNavDeletes.clear();
    _pendingCategoryVisibility.clear();
    _pendingPageSeo.clear();
    _selectedFooterNavId = null;
    _carouselSlideSelections.clear();
  }

  /// Restore the editor state from the last loaded/saved snapshot.
  void discardPendingChanges() {
    if (_history.isNotEmpty) {
      _blocks =
          _history.first.map((b) => Map<String, dynamic>.from(b)).toList();
      _history
        ..clear()
        ..add(_blocks.map((b) => Map<String, dynamic>.from(b)).toList());
      _historyIndex = 0;
    }

    _clearPendingEditorChanges();
    _selectedBlockId = null;
    notifyListeners();
  }

  /// Enter preview mode (shows top bar with "Editar" button)
  /// [pageId] - Optional page ID for multi-page editing (null = home page)
  /// [pageSlug] - Optional page slug for navigation
  void enterPreviewMode(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    String? pageId,
    String? pageSlug,
  }) {
    _isPreviewMode = true;
    _isEditMode = false;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    _blocks = blocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _settings = Map<String, dynamic>.from(settings);
    _clearPendingEditorChanges();
    _selectedBlockId = null;
    _currentPageId = pageId;
    _currentPageSlug = pageSlug;
    notifyListeners();
  }

  /// Enter edit mode (shows side panel editor)
  /// [pageId] - Optional page ID for multi-page editing (null = home page)
  /// [pageSlug] - Optional page slug for navigation
  void enterEditMode(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    String? pageId,
    String? pageSlug,
  }) {
    debugPrint(
        '🥶 [FREEZE_DEBUG] WebsiteEditModeProvider.enterEditMode START path=${pageSlug ?? "home"}');
    _isPreviewMode = false;
    _isEditMode = true;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    _blocks = blocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _settings = Map<String, dynamic>.from(settings);
    _clearPendingEditorChanges();
    _selectedBlockId = null;
    _currentPageId = pageId;
    _currentPageSlug = pageSlug;

    // Initialize history with current state
    _history.clear();
    _history.add(_blocks.map((b) => Map<String, dynamic>.from(b)).toList());
    _historyIndex = 0;

    debugPrint(
        '✏️ [EditProvider] Entered edit mode for page: ${pageSlug ?? "home"} (id: $pageId)');
    notifyListeners();
  }

  /// Switch from preview to edit mode (keeps blocks)
  void switchToEditMode() {
    _isPreviewMode = false;
    _isEditMode = true;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    notifyListeners();
  }

  /// Switch from edit mode back to preview (after save/discard)
  void switchToPreviewMode() {
    _isEditMode = false;
    _isPreviewMode = true;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    _selectedBlockId = null;
    notifyListeners();
  }

  /// Set device preview mode (desktop, tablet, mobile)
  void setDevicePreviewMode(DevicePreviewMode mode) {
    _devicePreviewMode = mode;
    notifyListeners();
  }

  /// Exit completely (back to normal visitor view)
  void exitEditMode() {
    if (!_isPreviewMode && !_isEditMode) return;

    _isPreviewMode = false;
    _isEditMode = false;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    _selectedBlockId = null;
    _clearPendingEditorChanges();
    _blocks = [];
    _settings = {};
    _currentPageId = null;
    _currentPageSlug = null;
    notifyListeners();
  }

  /// Update blocks after successful save (refresh with database data)
  void updateBlocksAfterSave(List<Map<String, dynamic>> freshBlocks) {
    _blocks = freshBlocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  /// Select a block for editing
  void selectBlock(String? blockId) {
    _selectedBlockId = blockId;
    _selectionVersion++;
    debugPrint(
        '👉 [EditProvider] Block Selected: $blockId (v$_selectionVersion)');
    notifyListeners();
  }

  /// Update block data without notifying listeners (for real-time drag preview)
  /// Use this during drag operations to avoid rebuilding the entire widget tree
  void updateBlockDataSilent(String blockId, String key, dynamic value) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return;

    final block = _blocks[blockIndex];
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    blockData[key] = value;
    _blocks[blockIndex] = {
      ...block,
      'block_data': blockData,
    };
    _hasUnsavedChanges = true;
    // Don't call notifyListeners() - caller is responsible for UI updates
  }

  /// Update block data
  /// [saveHistory] - Set to false for transient updates (like activeElementId changes) to avoid history pollution
  void updateBlockData(String blockId, String key, dynamic value,
      {bool saveHistory = true}) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint('⚠️ [EditProvider] updateBlockData: block $blockId not found');
      return;
    }

    final block = _blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    blockData[key] = value;

    _syncDerivedActions(
      blockType: blockType,
      updatedKey: key,
      blockData: blockData,
    );
    _blocks[blockIndex] = {
      ...block,
      'block_data': blockData,
    };
    _hasUnsavedChanges = true;
    if (saveHistory) {
      _saveToHistory();
    }
    debugPrint(
        '✅ [EditProvider] updateBlockData: blockId=$blockId, key=$key, hasUnsavedChanges=$_hasUnsavedChanges');
    notifyListeners();
  }

  /// Update multiple block data keys atomically (single notification)
  /// Use this when updating related values that should be saved together
  void updateBlockDataMultiple(String blockId, Map<String, dynamic> updates,
      {bool saveHistory = true}) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint(
          '⚠️ [EditProvider] updateBlockDataMultiple: block $blockId not found');
      return;
    }

    final block = _blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});

    // Apply all updates atomically
    for (final entry in updates.entries) {
      blockData[entry.key] = entry.value;
    }

    // If multiple keys updated, sync derived actions if any CTA-related keys changed.
    final changedKeys = updates.keys.toSet();
    const ctaKeys = {
      'ctaText',
      'ctaLink',
      'buttonText',
      'buttonLink',
      'showCta',
      'actions',
      'label',
      'link',
      'style',
      'viewAllText',
      'viewAllLink',
      'showViewAll',
      'actionVariant',
    };
    if (changedKeys.intersection(ctaKeys).isNotEmpty) {
      _syncDerivedActions(
        blockType: blockType,
        updatedKey: 'multiple',
        blockData: blockData,
      );
    }

    _blocks[blockIndex] = {
      ...block,
      'block_data': blockData,
    };
    _hasUnsavedChanges = true;
    if (saveHistory) {
      _saveToHistory();
    }
    debugPrint(
        '✅ [EditProvider] updateBlockDataMultiple: blockId=$blockId, keys=${updates.keys.join(", ")}');
    notifyListeners();
  }

  void _syncDerivedActions({
    required String blockType,
    required String updatedKey,
    required Map<String, dynamic> blockData,
  }) {
    final typeLower = blockType.trim().toLowerCase();
    final isCtaLike = typeLower == 'hero' ||
        typeLower == 'cta' ||
        typeLower == 'videobanner' ||
        typeLower == 'button' ||
        typeLower == 'products';
    if (!isCtaLike) return;

    // If user edits actions directly in the future, don't fight it.
    if (updatedKey == 'actions') return;

    final labelKeys = switch (typeLower) {
      'button' => const ['label', 'text'],
      'products' => const ['viewAllText'],
      _ => const ['ctaText', 'buttonText'],
    };
    final hrefKeys = switch (typeLower) {
      'button' => const ['link'],
      'products' => const ['viewAllLink'],
      _ => const ['ctaLink', 'buttonLink'],
    };
    final enabled = switch (typeLower) {
      'videobanner' => blockData['showCta'] != false,
      'products' => blockData['showViewAll'] != false,
      _ => true,
    };
    final action = WebsiteActionValue.resolvePrimary(
      blockData,
      labelKeys: labelKeys,
      hrefKeys: hrefKeys,
      defaultLabel:
          typeLower == 'products' ? 'Ver todos los productos' : 'Ver más',
      defaultVariant: typeLower == 'button'
          ? WebsiteActionVariant.fromStorage(blockData['style']?.toString())
          : WebsiteActionVariant.outline,
      enabled: enabled,
    );
    final effective = action ?? const WebsiteActionValue(label: '', href: '');
    blockData['actions'] =
        WebsiteActionValue.mergePrimary(blockData['actions'], effective);
    if (action == null) {
      if (enabled) {
        for (final key in hrefKeys) {
          blockData[key] = '';
        }
      }
      return;
    }
    for (final key in labelKeys) {
      blockData[key] = action.label;
    }
    for (final key in hrefKeys) {
      blockData[key] = action.href;
    }
    if (typeLower == 'button') {
      blockData['style'] = action.variant.storageValue;
    } else {
      blockData['actionVariant'] = action.variant.storageValue;
    }
  }

  /// Convenience: add a Canvas element to the currently selected Canvas block.
  /// Returns true if an element was added.
  bool addCanvasElementToSelectedCanvas(String elementType) {
    final selected = _selectedBlockId;
    if (selected == null) return false;
    return addCanvasElementToCanvasBlock(selected, elementType);
  }

  /// Add a Canvas element to a specific Canvas block by id.
  /// Returns true if successful.
  bool addCanvasElementToCanvasBlock(String canvasBlockId, String elementType) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == canvasBlockId);
    if (blockIndex == -1) return false;
    final block = _blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    if (blockType == WebsiteBlockType.carousel.name) {
      final data = Map<String, dynamic>.from(block['block_data'] ?? const {});
      final rawSlides = data['slides'];
      if (rawSlides is! List || rawSlides.isEmpty) return false;
      final slides = rawSlides
          .whereType<Map>()
          .map((slide) => Map<String, dynamic>.from(slide))
          .toList();
      if (slides.isEmpty) return false;
      final slideIndex = carouselSlideSelection(canvasBlockId, slides.length);
      final slide = Map<String, dynamic>.from(slides[slideIndex]);
      final rawElements = slide['elements'];
      final elements = rawElements is List
          ? rawElements
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final id = 'el_${DateTime.now().microsecondsSinceEpoch}';
      elements.add(createCanvasElement(id: id, type: elementType));
      slides[slideIndex] = {
        ...slide,
        'useComposition': true,
        'elements': elements,
      };
      updateBlockData(canvasBlockId, 'slides', slides);
      selectCanvasElement(
        canvasBlockId,
        id,
        slideIndex: slideIndex,
        slideCount: slides.length,
      );
      return true;
    }
    if (blockType != WebsiteBlockType.canvas.name) return false;

    final data = Map<String, dynamic>.from(block['block_data'] ?? {});
    final rawElements = data['elements'];
    final elements = rawElements is List
        ? rawElements
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final now = DateTime.now().microsecondsSinceEpoch;
    final id = 'el_$now';
    final next = createCanvasElement(id: id, type: elementType);

    elements.add(next);
    updateBlockData(canvasBlockId, 'elements', elements);
    selectCanvasElement(canvasBlockId, id);
    return true;
  }

  /// Save current state to history
  void _saveToHistory() {
    // Remove any future history if we're not at the end
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    // Deep copy blocks
    final snapshot = _blocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _history.add(snapshot);
    _historyIndex = _history.length - 1;

    // Limit history size
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
      _historyIndex--;
    }

    debugPrint(
        '💾 [EditProvider] Saved to history: index=$_historyIndex, total=${_history.length}, canUndo=$canUndo, canRedo=$canRedo');
  }

  /// Undo last change
  void undo() {
    if (!canUndo) return;

    _historyIndex--;
    _blocks = _history[_historyIndex]
        .map((b) => Map<String, dynamic>.from(b))
        .toList();
    _hasUnsavedChanges = true;
    debugPrint('⏪ [EditProvider] Undo: index=$_historyIndex');
    notifyListeners();
  }

  /// Redo last undone change
  void redo() {
    if (!canRedo) return;

    _historyIndex++;
    _blocks = _history[_historyIndex]
        .map((b) => Map<String, dynamic>.from(b))
        .toList();
    _hasUnsavedChanges = true;
    debugPrint('⏩ [EditProvider] Redo: index=$_historyIndex');
    notifyListeners();
  }

  /// Get block by ID
  Map<String, dynamic>? getBlock(String blockId) {
    try {
      return _blocks.firstWhere((b) => b['id'] == blockId);
    } catch (_) {
      return null;
    }
  }

  /// Get block data
  Map<String, dynamic> getBlockData(String blockId) {
    final block = getBlock(blockId);
    return Map<String, dynamic>.from(block?['block_data'] ?? {});
  }

  /// Move block up
  void moveBlockUp(String blockId) {
    debugPrint('🔼 [EditProvider] moveBlockUp called for blockId: $blockId');
    final index = _blocks.indexWhere((b) => b['id'] == blockId);
    debugPrint('🔼 [EditProvider] Block index: $index');
    if (index <= 0) {
      debugPrint(
          '🔼 [EditProvider] Cannot move up - already at top or not found');
      return;
    }

    final block = _blocks.removeAt(index);
    _blocks.insert(index - 1, block);

    // Update sort_order for all blocks to match new positions
    _updateSortOrders();

    _hasUnsavedChanges = true;
    debugPrint('🔼 [EditProvider] Moved block from $index to ${index - 1}');
    notifyListeners();
  }

  /// Move block down
  void moveBlockDown(String blockId) {
    debugPrint('🔽 [EditProvider] moveBlockDown called for blockId: $blockId');
    final index = _blocks.indexWhere((b) => b['id'] == blockId);
    debugPrint(
        '🔽 [EditProvider] Block index: $index, total blocks: ${_blocks.length}');
    if (index == -1 || index >= _blocks.length - 1) {
      debugPrint(
          '🔽 [EditProvider] Cannot move down - already at bottom or not found');
      return;
    }

    final block = _blocks.removeAt(index);
    _blocks.insert(index + 1, block);

    // Update sort_order for all blocks to match new positions
    _updateSortOrders();

    _hasUnsavedChanges = true;
    debugPrint('🔽 [EditProvider] Moved block from $index to ${index + 1}');
    notifyListeners();
  }

  /// Reorder blocks via drag-and-drop (Structure panel).
  void reorderBlocks(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _blocks.length) return;
    if (newIndex < 0) return;
    if (newIndex > _blocks.length) newIndex = _blocks.length;

    // Flutter's ReorderableListView gives newIndex in the "post-removal" space.
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final item = _blocks.removeAt(oldIndex);
    _blocks.insert(newIndex, item);

    _updateSortOrders();
    _hasUnsavedChanges = true;
    _saveToHistory();
    notifyListeners();
  }

  /// Update sort_order values to match current list positions
  void _updateSortOrders() {
    for (int i = 0; i < _blocks.length; i++) {
      _blocks[i] = {
        ..._blocks[i],
        'sort_order': i,
        'order_index': i,
      };
    }
  }

  /// Delete block
  void deleteBlock(String blockId) {
    _blocks.removeWhere((b) => b['id'] == blockId);
    if (_selectedBlockId == blockId) {
      _selectedBlockId = null;
    }
    // Update sort_order for remaining blocks
    _updateSortOrders();
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Duplicate block
  void duplicateBlock(String blockId) {
    final index = _blocks.indexWhere((b) => b['id'] == blockId);
    if (index == -1) return;

    final original = _blocks[index];
    final duplicate = Map<String, dynamic>.from(original);
    duplicate['id'] = _uuid.v4(); // Use proper UUID for database compatibility
    duplicate['block_data'] =
        Map<String, dynamic>.from(original['block_data'] ?? {});

    _blocks.insert(index + 1, duplicate);
    _updateSortOrders(); // Update sort_order values after duplicate
    _selectedBlockId = duplicate['id'] as String?;
    _hasUnsavedChanges = true;
    notifyListeners();
    debugPrint(
        '📋 [EditProvider] Duplicated block at index $index with new ID: ${duplicate['id']}');
  }

  /// Toggle block visibility
  void toggleBlockVisibility(String blockId) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return;

    final block = _blocks[blockIndex];
    _blocks[blockIndex] = {
      ...block,
      'is_visible': !(block['is_visible'] ?? true),
    };
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Add a new block
  void addBlock(String blockType, {int? atIndex}) {
    final newBlock = {
      'id': _uuid.v4(), // Use proper UUID for database compatibility
      'block_type': blockType,
      'block_data': _defaultDataForType(blockType),
      'is_visible': true,
      'sort_order': _blocks.length,
    };

    if (atIndex != null && atIndex >= 0 && atIndex <= _blocks.length) {
      _blocks.insert(atIndex, newBlock);
    } else {
      _blocks.add(newBlock);
    }

    // Update sort_order for all blocks
    _updateSortOrders();

    _selectedBlockId = newBlock['id'] as String?;
    _selectionVersion++;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  Map<String, dynamic> _defaultDataForType(String blockType) {
    final normalized = blockType.trim();
    for (final type in WebsiteBlockType.values) {
      if (type.name.toLowerCase() == normalized.toLowerCase()) {
        return _deepCopyMap(
          WebsiteBlockRegistry.definitionFor(type).defaultData,
        );
      }
    }
    return _legacyDefaultDataForUnknownType(blockType);
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) =>
      source.map((key, value) => MapEntry(key, _deepCopyValue(value)));

  dynamic _deepCopyValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(key.toString(), _deepCopyValue(nested)),
      );
    }
    if (value is List) return value.map(_deepCopyValue).toList();
    return value;
  }

  /// Compatibility fallback for marketplace/legacy block types not registered
  /// in [WebsiteBlockRegistry]. Registered blocks must never add defaults here.
  Map<String, dynamic> _legacyDefaultDataForUnknownType(String blockType) {
    switch (blockType) {
      case 'hero':
        return {
          'title': 'Servicios y Productos de Bicicleta',
          'subtitle': 'Todo lo que necesitas para tu bicicleta',
          'buttonText': 'Ver Productos',
          'buttonLink': '/productos',
          'backgroundImage': '',
        };
      case 'carousel':
        return {
          'slides': [
            {
              'title': 'Bienvenido a nuestra tienda',
              'subtitle': 'Descubre los mejores productos para tu bicicleta',
              'imageUrl': '',
              'ctaText': 'Ver catálogo',
              'ctaLink': '/productos',
              'showOverlay': true,
              'overlayOpacity': 0.55,
            },
            {
              'title': 'Servicio técnico certificado',
              'subtitle': 'Agenda tu mantención sin salir de casa',
              'imageUrl': '',
              'ctaText': 'Agendar ahora',
              'ctaLink': '/tienda/servicios',
              'showOverlay': true,
              'overlayOpacity': 0.55,
            },
          ],
          'autoPlay': true,
          'intervalSeconds': 5,
          'showIndicators': true,
          'showArrows': true,
          'animation': 'slide',
        };
      case 'products':
        return {
          'title': 'Productos Destacados',
          'subtitle': 'Los mejores productos para ti',
          'showPrice': true,
          'maxProducts': 8,
        };
      case 'text':
        return {
          'text': 'Haz clic para editar este texto',
          'preset': 'paragraph', // heading | subheading | paragraph | caption
          'maxWidth': 800,
          'formatting': const <String, dynamic>{},
        };
      case 'canvas':
        return {
          'blockHeight': 420.0,
          'heightMode': 'fixed', // fixed | viewport
          'vhPct': 0.7, // viewport height percentage (0.2..1.0)
          'fullBleed': false,
          'backgroundColor': '#FFFFFF',
          'backgroundImageUrl': '',
          'backgroundVideoUrl': '',
          'backgroundYoutubeId': '',
          'overlayEnabled': false,
          'overlayOpacity': 0.35,
          'overlayColor': '#000000',
          'backgroundFit': 'cover', // cover | contain
          'showGrid': true,
          'gridSize': 8.0,
          'snap': true,
          'snapDistance': 6.0,
          'activeElementId': null,
          'elements': [
            {
              'id': 'el_${DateTime.now().microsecondsSinceEpoch}',
              'type': 'text',
              'x': 24.0,
              'y': 24.0,
              'w': 360.0,
              'h': 72.0,
              'text': 'Arrástrame (Canvas)',
              'fontSize': 28.0,
              'fontWeight': 'w700',
              'color': '#111111',
              'align': 'left',
            },
            {
              'id': 'el_${DateTime.now().microsecondsSinceEpoch + 1}',
              'type': 'button',
              'x': 24.0,
              'y': 120.0,
              'w': 220.0,
              'h': 56.0,
              'label': 'Botón',
              'style': 'filled',
              'inheritTheme': true,
              'bgColor': '#00A09D',
              'fgColor': '#FFFFFF',
              'radius': 12.0,
              'link': '/',
            },
          ],
        };
      case 'button':
        return {
          'label': 'Botón',
          'link': '/',
          'style': 'filled', // filled | outline | text
        };
      case 'divider':
        return {
          'thickness': 1.0,
          'color': '#E0E0E0',
          'widthPct': 1.0,
        };
      case 'about':
        return {
          'title': 'Sobre Nosotros',
          'description':
              'Somos una tienda especializada en bicicletas y accesorios. Contamos con años de experiencia brindando productos de calidad y el mejor servicio a nuestros clientes.',
          'image': '',
        };
      case 'services':
        return {
          'title': 'Nuestros Servicios',
          'services': [
            {
              'icon': 'build',
              'title': 'Reparación',
              'description': 'Servicio técnico profesional'
            },
            {
              'icon': 'tune',
              'title': 'Mantención',
              'description': 'Mantención preventiva y correctiva'
            },
            {
              'icon': 'shopping_bag',
              'title': 'Venta',
              'description': 'Bicicletas y accesorios'
            },
          ],
        };
      case 'features':
        return {
          'title': '¿Por qué elegirnos?',
          'features': [
            {
              'icon': 'local_shipping',
              'title': 'Envío Rápido',
              'description': 'Envíos a Chile continental en 3 a 12 días hábiles'
            },
            {
              'icon': 'verified',
              'title': 'Productos Originales',
              'description': 'Garantía de autenticidad'
            },
            {
              'icon': 'support_agent',
              'title': 'Atención Personalizada',
              'description': 'Asesoramiento experto'
            },
          ],
        };
      case 'testimonials':
        return {
          'title': 'Lo que dicen nuestros clientes',
          'testimonials': [
            {
              'name': 'Cliente Satisfecho',
              'text': 'Excelente servicio y productos de calidad.',
              'rating': 5
            },
          ],
        };
      case 'stats':
        return {
          'title': 'Nuestros Números',
          'stats': [
            {'value': '1000+', 'label': 'Clientes Satisfechos'},
            {'value': '500+', 'label': 'Productos'},
            {'value': '10+', 'label': 'Años de Experiencia'},
          ],
        };
      case 'team':
        return {
          'title': 'Nuestro Equipo',
          'members': [
            {'name': 'Nombre', 'role': 'Cargo', 'image': ''},
          ],
        };
      case 'faq':
        return {
          'title': 'Preguntas Frecuentes',
          'questions': [
            {
              'question': '¿Cuál es el horario de atención?',
              'answer': 'Lunes a Viernes de 9:00 a 18:00'
            },
            {
              'question': '¿Hacen envíos a regiones?',
              'answer': 'Sí, enviamos a Chile continental'
            },
          ],
        };
      case 'pricing':
        return {
          'title': 'Nuestros Planes',
          'plans': [
            {
              'name': 'Básico',
              'price': '9.990',
              'features': ['Feature 1', 'Feature 2']
            },
            {
              'name': 'Pro',
              'price': '19.990',
              'features': ['Feature 1', 'Feature 2', 'Feature 3'],
              'highlighted': true
            },
          ],
        };
      case 'contact':
        return {
          'title': 'Contáctanos',
          'subtitle': 'Estamos aquí para ayudarte',
          'showMap': false,
          'showForm': true,
        };
      case 'cta':
        return {
          'title': '¿Listo para empezar?',
          'description': 'Visítanos o contáctanos para más información',
          'buttonText': 'Contactar',
          'buttonLink': '/tienda/contacto',
        };
      case 'gallery':
        return {
          'title': 'Galería',
          'images': [],
        };
      case 'categoryGrid':
        return {
          'title': 'Explora Nuestras Categorías',
          'subtitle': 'Encuentra lo que buscas',
          'categories': [
            {
              'title': 'Mountain Bike',
              'subtitle': 'Conquista cualquier terreno',
              'imageUrl': '',
              'ctaText': 'Ver colección',
              'ctaLink': '/productos',
              'size': 'large',
            },
            {
              'title': 'Ruta',
              'subtitle': 'Velocidad y rendimiento',
              'imageUrl': '',
              'ctaText': 'Ver colección',
              'ctaLink': '/productos',
              'size': 'large',
            },
            {
              'title': 'Urbano',
              'subtitle': 'Movilidad en la ciudad',
              'imageUrl': '',
              'ctaText': 'Ver gama',
              'ctaLink': '/productos',
              'size': 'medium',
            },
            {
              'title': 'Accesorios',
              'subtitle': 'Todo lo que necesitas',
              'imageUrl': '',
              'ctaText': 'Explorar',
              'ctaLink': '/productos',
              'size': 'medium',
            },
          ],
        };
      case 'videoBanner':
        return {
          'title': 'Vive la Aventura',
          'subtitle': 'La experiencia de rodar sin límites',
          'imageUrl': '',
          'videoUrl': '',
          'ctaText': 'Descubrir más',
          'ctaLink': '/productos',
          'showCta': true,
          'overlayOpacity': 0.5,
        };
      case 'partnersBanner':
        return {
          'title': 'Nuestras Ubicaciones',
          'imageUrl': '',
          'items': [
            'Santiago, Chile',
            'Viña del Mar, Chile',
            'Concepción, Chile',
          ],
        };
      case 'brandLogos':
        return {
          'title': 'MARCAS',
          'accentColor': '#E53935',
          'brands': [
            {'name': 'Marca 1', 'imageUrl': '', 'link': ''},
            {'name': 'Marca 2', 'imageUrl': '', 'link': ''},
            {'name': 'Marca 3', 'imageUrl': '', 'link': ''},
          ],
        };
      default:
        return {};
    }
  }

  /// Update settings
  void updateSetting(String key, dynamic value) {
    _settings[key] = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Mark changes as saved
  void markAsSaved() {
    _hasUnsavedChanges = false;
    notifyListeners();
  }
}
