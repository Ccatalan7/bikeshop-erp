import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage navigation drawer visibility state
/// This allows universal expand/collapse functionality across all pages
class NavigationService extends ChangeNotifier {
  static const String _drawerVisibleKey = 'navigation_drawer_visible';
  
  bool _isDrawerVisible = true;
  bool _isInitialized = false;
  
  bool get isDrawerVisible => _isDrawerVisible;
  bool get isInitialized => _isInitialized;

  /// Initialize the service and load saved state
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDrawerVisible = prefs.getBool(_drawerVisibleKey) ?? true;
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading navigation state: $e');
      _isInitialized = true;
      notifyListeners();
    }
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
