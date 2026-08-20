import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tools available in the right toolbar.
enum ToolbarTool {
  notifications,
  newJob,
  bikeFinder,
  aiAssistant,
  messages,
  supplierMessages,
  storage,
  fileRunner,
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

  void openTool(ToolbarTool tool) {
    if (_activeTool == tool) return;
    _activeTool = tool;
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

  // --- Sesión de vista de los paneles -------------------------------------
  //
  // Cerrar el toolbar desmonta el panel activo, y eso es deliberado: el
  // `dispose()` de los paneles de chat cancela la suscripción realtime y suelta
  // el historial de la conversación. Mantenerlos montados (Offstage/IndexedStack)
  // dejaría la conversación marcada como activa con el panel cerrado, marcando
  // como leídos mensajes que el usuario nunca vio, y retendría historial sin
  // techo. El widget sigue siendo desechable; lo que sobrevive es el estado de
  // vista del que se reconstruye, para que reabrir no se sienta un arranque en
  // frío.
  //
  // Sólo estado de vista: búsqueda, filtro, selección, scroll. Nunca datos de
  // negocio — esos viven en la caché con alcance de tenant de su servicio, y
  // cada valor restaurado se valida contra los datos del tenant actual antes de
  // usarse, de modo que un cambio de tenant no puede arrastrar nada.
  final Map<ToolbarTool, Object> _panelSessions = {};

  T? panelSession<T extends Object>(ToolbarTool tool) {
    final session = _panelSessions[tool];
    return session is T ? session : null;
  }

  /// Guarda el estado de vista del panel. No notifica: se llama desde el
  /// `dispose()` del panel, y notificar durante el desmontaje reconstruiría el
  /// árbol que se está desarmando.
  void savePanelSession(ToolbarTool tool, Object session) {
    _panelSessions[tool] = session;
  }

  void clearPanelSession(ToolbarTool tool) {
    _panelSessions.remove(tool);
  }

  /// Se llama al cerrar sesión o cambiar de tenant: el estado de vista nombra
  /// conversaciones y proveedores de un tenant y no debe cruzar el límite.
  void clearAllPanelSessions() {
    _panelSessions.clear();
  }
}
