import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage navigation drawer visibility state
/// This allows universal expand/collapse functionality across all pages
class NavigationService extends ChangeNotifier {
  static const String _drawerVisibleKey = 'navigation_drawer_visible';
  static const String _drawerWidthKey = 'navigation_drawer_width';
  static const double _minDrawerWidth = 200.0;
  static const double _maxDrawerWidth = 400.0;
  static const double _defaultDrawerWidth = 280.0;

  bool _isDrawerVisible = true;
  bool _isInitialized = false;
  double _drawerWidth = _defaultDrawerWidth;

  bool get isDrawerVisible => _isDrawerVisible;
  bool get isInitialized => _isInitialized;
  double get drawerWidth => _drawerWidth;

  /// Initialize the service and load saved state
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _isDrawerVisible = prefs.getBool(_drawerVisibleKey) ?? true;
      _drawerWidth = prefs.getDouble(_drawerWidthKey) ?? _defaultDrawerWidth;
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading navigation state: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Update drawer width (for resizing)
  /// Updates immediately for smooth dragging, saves to SharedPreferences async
  void updateDrawerWidth(double newWidth) {
    // Clamp width between min and max
    final clampedWidth = newWidth.clamp(_minDrawerWidth, _maxDrawerWidth);
    
    // Only update if changed significantly (avoid unnecessary rebuilds)
    if ((_drawerWidth - clampedWidth).abs() < 0.5) return;
    
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
}
