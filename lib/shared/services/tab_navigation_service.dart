import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data model for a tab
class TabData {
  final String route;
  final String title;
  final DateTime openedAt;
  final IconData? icon;
  final Widget? cachedWidget; // NEW: Store the widget instance

  TabData({
    required this.route,
    required this.title,
    DateTime? openedAt,
    this.icon,
    this.cachedWidget,
  }) : openedAt = openedAt ?? DateTime.now();

  // Create a copy with updated widget
  TabData copyWith({Widget? cachedWidget}) {
    return TabData(
      route: route,
      title: title,
      openedAt: openedAt,
      icon: icon,
      cachedWidget: cachedWidget ?? this.cachedWidget,
    );
  }

  Map<String, dynamic> toJson() => {
        'route': route,
        'title': title,
        'openedAt': openedAt.toIso8601String(),
      };

  factory TabData.fromJson(Map<String, dynamic> json) => TabData(
        route: json['route'] as String,
        title: json['title'] as String,
        openedAt: DateTime.parse(json['openedAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabData && runtimeType == other.runtimeType && route == other.route;

  @override
  int get hashCode => route.hashCode;
}

/// Service to manage tabbed navigation
/// 
/// Features:
/// - Multiple tabs open simultaneously
/// - Tab switching with click
/// - Close individual tabs
/// - Persistent tabs across app restarts
/// - Maximum 10 tabs (prevents memory issues)
/// - Auto-activation of remaining tab when closing active tab
class TabNavigationService extends ChangeNotifier {
  static const int maxTabs = 10;
  static const String _storageKey = 'navigation_tabs';
  static const String _activeIndexKey = 'navigation_active_tab';

  final List<TabData> _tabs = [];
  int _activeIndex = 0;

  List<TabData> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  TabData? get activeTab => _tabs.isEmpty ? null : _tabs[_activeIndex];
  bool get hasTabs => _tabs.isNotEmpty;
  int get tabCount => _tabs.length;

  TabNavigationService() {
    _initialize();
  }

  /// Initialize service and restore tabs from storage
  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Restore tabs
      final tabsJson = prefs.getString(_storageKey);
      if (tabsJson != null) {
        final List<dynamic> decoded = jsonDecode(tabsJson);
        _tabs.addAll(decoded.map((json) => TabData.fromJson(json)));
      }

      // Restore active index
      final savedIndex = prefs.getInt(_activeIndexKey) ?? 0;
      _activeIndex = _tabs.isEmpty ? 0 : savedIndex.clamp(0, _tabs.length - 1);

      debugPrint('📑 [TABS] Restored ${_tabs.length} tabs, active: $_activeIndex');
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [TABS] Error restoring tabs: $e');
      _tabs.clear();
      _activeIndex = 0;
    }
  }

  /// Save tabs to persistent storage
  Future<void> _saveTabs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tabsJson = jsonEncode(_tabs.map((tab) => tab.toJson()).toList());
      await prefs.setString(_storageKey, tabsJson);
      await prefs.setInt(_activeIndexKey, _activeIndex);
    } catch (e) {
      debugPrint('⚠️ [TABS] Error saving tabs: $e');
    }
  }

  /// Open a new tab or switch to existing tab with same route
  /// 
  /// Returns true if new tab was created, false if switched to existing
  bool openTab(String route, String title, {IconData? icon}) {
    // Check if tab already exists
    final existingIndex = _tabs.indexWhere((tab) => tab.route == route);
    if (existingIndex != -1) {
      // Switch to existing tab
      _activeIndex = existingIndex;
      debugPrint('📑 [TABS] Switched to existing tab: $title');
      notifyListeners();
      _saveTabs();
      return false;
    }

    // Check max tabs limit
    if (_tabs.length >= maxTabs) {
      debugPrint('⚠️ [TABS] Max tabs ($maxTabs) reached, cannot open: $title');
      return false;
    }

    // Create new tab
    final newTab = TabData(route: route, title: title, icon: icon);
    _tabs.add(newTab);
    _activeIndex = _tabs.length - 1;

    debugPrint('📑 [TABS] Opened new tab: $title (${_tabs.length}/$maxTabs)');
    notifyListeners();
    _saveTabs();
    return true;
  }

  /// Open a new tab WITHOUT navigating to it (for right-click "Open in new tab")
  /// 
  /// Returns true if new tab was created, false if tab already exists
  bool openTabWithoutNavigation(String route, String title, {IconData? icon}) {
    // Check if tab already exists
    final existingIndex = _tabs.indexWhere((tab) => tab.route == route);
    if (existingIndex != -1) {
      debugPrint('📑 [TABS] Tab already exists: $title');
      return false;
    }

    // Check max tabs limit
    if (_tabs.length >= maxTabs) {
      debugPrint('⚠️ [TABS] Max tabs ($maxTabs) reached, cannot open: $title');
      return false;
    }

    // Create new tab (but don't change active index)
    final newTab = TabData(route: route, title: title, icon: icon);
    _tabs.add(newTab);
    // Don't update _activeIndex - stay on current tab

    debugPrint('📑 [TABS] Opened background tab: $title (${_tabs.length}/$maxTabs)');
    notifyListeners();
    _saveTabs();
    return true;
  }

  /// Close a tab at the specified index
  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;

    final closedTab = _tabs[index];
    _tabs.removeAt(index);

    // Adjust active index if needed
    if (_tabs.isEmpty) {
      _activeIndex = 0;
    } else if (index <= _activeIndex) {
      // If closing active tab or a tab before it, adjust index
      _activeIndex = (_activeIndex - 1).clamp(0, _tabs.length - 1);
    }

    debugPrint('📑 [TABS] Closed tab: ${closedTab.title} (${_tabs.length} remaining)');
    notifyListeners();
    _saveTabs();
  }

  /// Close tab by route
  void closeTabByRoute(String route) {
    final index = _tabs.indexWhere((tab) => tab.route == route);
    if (index != -1) {
      closeTab(index);
    }
  }

  /// Switch to tab at specified index
  void switchToTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;

    _activeIndex = index;
    debugPrint('📑 [TABS] Switched to tab: ${_tabs[index].title}');
    notifyListeners();
    _saveTabs();
  }

  /// Switch to tab by route
  bool switchToTabByRoute(String route) {
    final index = _tabs.indexWhere((tab) => tab.route == route);
    if (index != -1) {
      switchToTab(index);
      return true;
    }
    return false;
  }

  /// Close all tabs
  void closeAllTabs() {
    _tabs.clear();
    _activeIndex = 0;
    debugPrint('📑 [TABS] Closed all tabs');
    notifyListeners();
    _saveTabs();
  }

  /// Check if a route is currently open in a tab
  bool hasTab(String route) {
    return _tabs.any((tab) => tab.route == route);
  }

  /// Get tab index by route
  int? getTabIndex(String route) {
    final index = _tabs.indexWhere((tab) => tab.route == route);
    return index == -1 ? null : index;
  }

  @override
  void dispose() {
    _saveTabs();
    super.dispose();
  }
}
