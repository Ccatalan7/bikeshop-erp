import 'package:flutter/material.dart';

/// Represents a single workspace tab
class Workspace {
  final String id;
  final String title;
  final String initialRoute;
  final GlobalKey<NavigatorState> navigatorKey;
  
  Workspace({
    required this.id,
    required this.title,
    required this.initialRoute,
  }) : navigatorKey = GlobalKey<NavigatorState>();
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Workspace &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Manages multiple independent workspace tabs
/// Each workspace has its own GoRouter instance and navigation state
class WorkspaceManager extends ChangeNotifier {
  static const int maxWorkspaces = 10;
  
  final List<Workspace> _workspaces = [];
  int _activeIndex = 0;
  bool _isInitialized = false;
  
  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  int get activeIndex => _activeIndex;
  Workspace? get activeWorkspace => _workspaces.isEmpty ? null : _workspaces[_activeIndex];
  bool get isInitialized => _isInitialized;

  WorkspaceManager() {
    debugPrint('🏗️ [WorkspaceManager] Constructor called, creating initial Dashboard workspace');
    // Create initial Dashboard workspace
    addWorkspace(title: 'Dashboard', initialRoute: '/dashboard');
    _isInitialized = true;
    debugPrint('✅ [WorkspaceManager] Initialized with ${_workspaces.length} workspace(s)');
    // Force a notification after initialization to ensure UI rebuilds
    Future.microtask(() {
      debugPrint('🔔 [WorkspaceManager] Calling notifyListeners() after microtask');
      notifyListeners();
    });
  }
  
  /// Add a new workspace tab
  String addWorkspace({
    required String title,
    required String initialRoute,
  }) {
    debugPrint('➕ [WorkspaceManager] addWorkspace: title=$title, route=$initialRoute');
    
    if (_workspaces.length >= maxWorkspaces) {
      throw Exception('Maximum number of workspaces ($maxWorkspaces) reached');
    }
    
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final workspace = Workspace(
      id: id,
      title: title,
      initialRoute: initialRoute,
    );
    
    _workspaces.add(workspace);
    _activeIndex = _workspaces.length - 1;
    debugPrint('✅ [WorkspaceManager] Workspace added. Total: ${_workspaces.length}, Active: $_activeIndex');
    notifyListeners();
    
    return id;
  }
  
  /// Switch to a specific workspace by index
  void switchToWorkspace(int index) {
    if (index >= 0 && index < _workspaces.length) {
      _activeIndex = index;
      notifyListeners();
    }
  }
  
  /// Switch to a specific workspace by ID
  void switchToWorkspaceById(String id) {
    final index = _workspaces.indexWhere((w) => w.id == id);
    if (index != -1) {
      switchToWorkspace(index);
    }
  }
  
  /// Close a workspace tab
  void closeWorkspace(int index) {
    if (_workspaces.length <= 1) {
      // Don't allow closing the last workspace
      return;
    }
    
    if (index >= 0 && index < _workspaces.length) {
      _workspaces.removeAt(index);
      
      // Adjust active index if needed
      if (_activeIndex >= _workspaces.length) {
        _activeIndex = _workspaces.length - 1;
      } else if (_activeIndex > index) {
        _activeIndex--;
      }
      
      notifyListeners();
    }
  }
  
  /// Close a workspace by ID
  void closeWorkspaceById(String id) {
    final index = _workspaces.indexWhere((w) => w.id == id);
    if (index != -1) {
      closeWorkspace(index);
    }
  }
  
  /// Update workspace title
  void updateWorkspaceTitle(int index, String newTitle) {
    if (index >= 0 && index < _workspaces.length) {
      final workspace = _workspaces[index];
      final updatedWorkspace = Workspace(
        id: workspace.id,
        title: newTitle,
        initialRoute: workspace.initialRoute,
      );
      _workspaces[index] = updatedWorkspace;
      notifyListeners();
    }
  }
  
  /// Check if a workspace with the given route already exists
  /// If it does, switch to it instead of creating a new one
  bool switchToExistingWorkspaceWithRoute(String route) {
    debugPrint('🔍 [WorkspaceManager] Looking for existing workspace with route: $route');
    final index = _workspaces.indexWhere((w) => w.initialRoute == route);
    if (index != -1) {
      debugPrint('✅ [WorkspaceManager] Found existing workspace at index $index, switching...');
      switchToWorkspace(index);
      return true;
    }
    debugPrint('❌ [WorkspaceManager] No existing workspace found for $route');
    return false;
  }
  
  /// Clear all workspaces and reset to initial state
  void reset() {
    _workspaces.clear();
    _activeIndex = 0;
    addWorkspace(title: 'Dashboard', initialRoute: '/dashboard');
  }
}
