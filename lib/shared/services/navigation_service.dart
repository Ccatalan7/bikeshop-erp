import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default order of menu modules
const List<String> defaultModuleOrder = [
  'accounting',
  'tax_reports',
  'customers',
  'chat',
  'workshop',
  'smart_features',
  'inventory',
  'sales',
  'purchases',
  'pos',
  'hr',
  'tools',
  'debug',
];

/// Service to manage navigation drawer visibility state
/// This allows universal expand/collapse functionality across all pages
class NavigationService extends ChangeNotifier {
  static const String _drawerVisibleKey = 'navigation_drawer_visible';
  static const String _drawerWidthKey = 'navigation_drawer_width';
  static const String _moduleOrderKey = 'navigation_module_order';
  static const double _minDrawerWidth = 200.0;
  static const double _maxDrawerWidth = 400.0;
  static const double _defaultDrawerWidth = 280.0;

  bool _isDrawerVisible = true;
  bool _isInitialized = false;
  double _drawerWidth = _defaultDrawerWidth;
  bool _isResizing = false;
  List<String> _moduleOrder = List.from(defaultModuleOrder);
  bool _isReorderMode = false;

  bool get isDrawerVisible => _isDrawerVisible;
  bool get isInitialized => _isInitialized;
  double get drawerWidth => _drawerWidth;
  bool get isResizing => _isResizing;
  List<String> get moduleOrder => List.unmodifiable(_moduleOrder);
  bool get isReorderMode => _isReorderMode;

  // Expanded section state
  String? _expandedSection;
  String? get expandedSection => _expandedSection;

  /// Initialize the service and load saved state
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _isDrawerVisible = prefs.getBool(_drawerVisibleKey) ?? true;
      _drawerWidth = prefs.getDouble(_drawerWidthKey) ?? _defaultDrawerWidth;

      // Load module order
      final orderJson = prefs.getString(_moduleOrderKey);
      if (orderJson != null) {
        final List<dynamic> savedOrder = jsonDecode(orderJson);
        // Validate and merge with defaults (in case new modules were added)
        _moduleOrder = _mergeModuleOrder(savedOrder.cast<String>());
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading navigation state: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Merge saved order with defaults to handle new modules
  List<String> _mergeModuleOrder(List<String> savedOrder) {
    final result = <String>[];
    // Add saved items in order (if they still exist in defaults)
    for (final item in savedOrder) {
      if (defaultModuleOrder.contains(item) && !result.contains(item)) {
        result.add(item);
      }
    }
    // Add any new modules that weren't in saved order
    for (final item in defaultModuleOrder) {
      if (!result.contains(item)) {
        result.add(item);
      }
    }
    return result;
  }

  /// Toggle reorder mode
  void toggleReorderMode() {
    _isReorderMode = !_isReorderMode;
    notifyListeners();
  }

  /// Exit reorder mode
  void exitReorderMode() {
    if (!_isReorderMode) return;
    _isReorderMode = false;
    notifyListeners();
  }

  /// Reorder modules
  Future<void> reorderModules(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _moduleOrder.removeAt(oldIndex);
    _moduleOrder.insert(newIndex, item);
    notifyListeners();

    // Save to preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_moduleOrderKey, jsonEncode(_moduleOrder));
    } catch (e) {
      debugPrint('Error saving module order: $e');
    }
  }

  /// Reset module order to default
  Future<void> resetModuleOrder() async {
    _moduleOrder = List.from(defaultModuleOrder);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_moduleOrderKey);
    } catch (e) {
      debugPrint('Error resetting module order: $e');
    }
  }

  /// Update drawer width (for resizing)
  /// Updates immediately for smooth dragging, saves to SharedPreferences async
  void updateDrawerWidth(double newWidth) {
    // Clamp width between min and max
    final clampedWidth = newWidth.clamp(_minDrawerWidth, _maxDrawerWidth);

    // Update immediately for smooth tracking (no threshold check)
    if (_drawerWidth == clampedWidth) return;

    _drawerWidth = clampedWidth;
    notifyListeners();

    // Save asynchronously without blocking the drag gesture
    _saveDrawerWidthDebounced();
  }

  Timer? _saveTimer;
  void _saveDrawerWidthDebounced() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_drawerWidthKey, _drawerWidth);
      } catch (e) {
        debugPrint('Error saving drawer width: $e');
      }
    });
  }

  /// Start resizing (disable animation for smooth tracking)
  void startResizing() {
    if (_isResizing) return;
    _isResizing = true;
    notifyListeners();
  }

  /// Stop resizing (re-enable animation)
  void stopResizing() {
    if (!_isResizing) return;
    _isResizing = false;
    notifyListeners();
  }

  /// Toggle drawer visibility and persist the state
  Future<void> toggleDrawer() async {
    _isDrawerVisible = !_isDrawerVisible;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_drawerVisibleKey, _isDrawerVisible);
    } catch (e) {
      debugPrint('Error saving navigation state: $e');
    }
  }

  /// Show the drawer
  Future<void> showDrawer() async {
    if (_isDrawerVisible) return;

    _isDrawerVisible = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_drawerVisibleKey, true);
    } catch (e) {
      debugPrint('Error saving navigation state: $e');
    }
  }

  /// Hide the drawer
  Future<void> hideDrawer() async {
    if (!_isDrawerVisible) return;

    _isDrawerVisible = false;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_drawerVisibleKey, false);
    } catch (e) {
      debugPrint('Error saving navigation state: $e');
    }
  }

  /// Set the currently expanded menu section
  void setExpandedSection(String? section) {
    if (_expandedSection == section) return;
    _expandedSection = section;
    notifyListeners();
  }
}
