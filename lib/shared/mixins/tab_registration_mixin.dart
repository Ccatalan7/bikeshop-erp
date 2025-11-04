import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/tab_navigation_service.dart';

/// Mixin for pages that should automatically register as tabs
/// 
/// Usage:
/// ```dart
/// class MyPage extends StatefulWidget {
///   const MyPage({super.key});
///   
///   @override
///   State<MyPage> createState() => _MyPageState();
/// }
/// 
/// class _MyPageState extends State<MyPage> with TabRegistrationMixin {
///   @override
///   String get tabRoute => '/my-route';
///   
///   @override
///   String get tabTitle => 'My Page';
///   
///   @override
///   IconData? get tabIcon => Icons.my_icon;
///   
///   @override
///   Widget build(BuildContext context) {
///     registerTab(context); // Call in build method
///     return Scaffold(...);
///   }
/// }
/// ```
mixin TabRegistrationMixin<T extends StatefulWidget> on State<T> {
  /// Route path for this tab (e.g., '/ventas', '/inventory/products')
  String get tabRoute;

  /// Human-readable title for the tab
  String get tabTitle;

  /// Optional icon for the tab
  IconData? get tabIcon => null;

  /// Whether to skip tab registration for this route
  bool get skipTabRegistration => false;

  /// Register this page as a tab
  /// Call this in your build() method
  void registerTab(BuildContext context) {
    if (skipTabRegistration) return;

    // Use post-frame callback to avoid modifying state during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        final tabService = context.read<TabNavigationService>();
        tabService.openTab(tabRoute, tabTitle, icon: tabIcon);
      } catch (e) {
        debugPrint('⚠️ [TAB] Failed to register tab: $e');
      }
    });
  }
}
