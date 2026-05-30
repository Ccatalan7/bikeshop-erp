import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tools available in the right toolbar.
enum ToolbarTool {
  newJob,
  bikeFinder,
  messages,
  storage,
  kiosk,
  quickSale,
  expenses,
  purchases,
  tasks,
  calculator,
  performance,
}

class RightToolbarService extends ChangeNotifier {
  static const String _gaugePinnedPrefKey = 'right_toolbar_gauge_pinned';
  static const bool _defaultGaugePinned = true;

  ToolbarTool? _activeTool;
  bool _isGaugePinned = _defaultGaugePinned;

  ToolbarTool? get activeTool => _activeTool;
  bool get isGaugePinned => _isGaugePinned;

  RightToolbarService() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isGaugePinned = prefs.getBool(_gaugePinnedPrefKey) ?? _defaultGaugePinned;
    if (!_isGaugePinned && _activeTool == ToolbarTool.performance) {
      _activeTool = null;
    }
    notifyListeners();
  }

  void toggleTool(ToolbarTool tool) {
    if (_activeTool == tool) {
      _activeTool = null;
    } else {
      _activeTool = tool;
    }
    notifyListeners();
  }

  void close() {
    _activeTool = null;
    notifyListeners();
  }

  Future<void> pinGaugeToToolbar() async {
    _isGaugePinned = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gaugePinnedPrefKey, true);
  }

  Future<void> unpinGaugeFromToolbar() async {
    _isGaugePinned = false;
    if (_activeTool == ToolbarTool.performance) {
      _activeTool = null;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gaugePinnedPrefKey, false);
  }
}
