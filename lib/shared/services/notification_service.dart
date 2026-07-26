import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_notification_gate.dart';
import 'erp_notification_gate.dart';
import 'mail_notification_gate.dart';
import 'tenant_service.dart';

/// Top-level function required by firebase_messaging for background handling.
/// Must be outside any class and cannot be an anonymous function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized (required for background isolate)
  await Firebase.initializeApp();

  if (kDebugMode) {
    debugPrint(
      '🔔 Background notification received; native FCM presentation retained '
      'for ${message.messageId ?? 'unknown message'}',
    );
  }

  // push-notification sends a native Android/APNs alert. Firebase/OS presents
  // that alert while the app is backgrounded. Creating another local
  // notification from this isolate would display the same message twice and
  // cannot apply the foreground conversation gate. Conversation state is
  // refreshed from the authoritative store when the app resumes.
}

enum NotificationCategory {
  general,
  message,
  email,
}

enum NotificationSoundGroup {
  mountainBike,
  workshop,
  pointOfSale,
  digital,
  desk,
  regular,
}

class NotificationSoundOption {
  final String id;
  final String label;
  final String description;
  final String assetPath;
  final NotificationSoundGroup group;
  final double volumeScale;

  const NotificationSoundOption({
    required this.id,
    required this.label,
    required this.description,
    required this.assetPath,
    this.group = NotificationSoundGroup.regular,
    this.volumeScale = 1,
  });
}

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _supabase = Supabase.instance.client;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  AudioPlayer? _audioPlayer;

  static const defaultMessageSoundId = 'mtb_freehub';
  static const defaultEmailSoundId = 'low_tap';
  static const defaultGeneralSoundId = 'soft_snap';

  static const List<NotificationSoundOption> soundOptions = [
    NotificationSoundOption(
      id: 'mtb_freehub',
      label: 'MTB freehub',
      description: 'Ratchet real, corto y seco',
      assetPath: 'sounds/notify_mtb_freehub.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.58,
    ),
    NotificationSoundOption(
      id: 'mtb_freehub_soft',
      label: 'MTB freehub suave',
      description: 'Misma textura, menos mordida',
      assetPath: 'sounds/notify_mtb_freehub_soft.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.64,
    ),
    NotificationSoundOption(
      id: 'mtb_gravel',
      label: 'MTB gravilla',
      description: 'Gravilla real, breve y sin tono',
      assetPath: 'sounds/notify_mtb_gravel.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.50,
    ),
    NotificationSoundOption(
      id: 'mtb_trail',
      label: 'MTB sendero',
      description: 'Rodado apagado, muy corto',
      assetPath: 'sounds/notify_mtb_trail.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.62,
    ),
    NotificationSoundOption(
      id: 'mtb_rock_ping',
      label: 'MTB piedra',
      description: 'Golpe de sendero, seco',
      assetPath: 'sounds/notify_mtb_rock_ping.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.60,
    ),
    NotificationSoundOption(
      id: 'mtb_pebble_snap',
      label: 'MTB piedrita',
      description: 'Chasquido corto de gravilla',
      assetPath: 'sounds/notify_mtb_pebble_snap.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.50,
    ),
    NotificationSoundOption(
      id: 'mtb_gravel_bite',
      label: 'MTB gravel bite',
      description: 'Gravilla con más carácter',
      assetPath: 'sounds/notify_mtb_gravel_bite.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.52,
    ),
    NotificationSoundOption(
      id: 'mtb_road_tick',
      label: 'MTB road tick',
      description: 'Rodado rápido, compacto',
      assetPath: 'sounds/notify_mtb_road_tick.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.42,
    ),
    NotificationSoundOption(
      id: 'mtb_dust_tick',
      label: 'MTB polvo seco',
      description: 'Tick de camino muy corto',
      assetPath: 'sounds/notify_mtb_dust_tick.wav',
      group: NotificationSoundGroup.mountainBike,
      volumeScale: 0.60,
    ),
    NotificationSoundOption(
      id: 'mtb_spokes',
      label: 'Rayos',
      description: 'Metal real, sin campana larga',
      assetPath: 'sounds/notify_mtb_spokes.wav',
      group: NotificationSoundGroup.workshop,
      volumeScale: 0.54,
    ),
    NotificationSoundOption(
      id: 'mtb_shift',
      label: 'Cambio seco',
      description: 'Golpe seco con textura de rueda',
      assetPath: 'sounds/notify_mtb_shift.wav',
      group: NotificationSoundGroup.workshop,
      volumeScale: 0.56,
    ),
    NotificationSoundOption(
      id: 'mtb_bell',
      label: 'Trail bell corta',
      description: 'Campana real, recortada y suave',
      assetPath: 'sounds/notify_mtb_bell.wav',
      group: NotificationSoundGroup.workshop,
      volumeScale: 0.48,
    ),
    NotificationSoundOption(
      id: 'bike_brake_chirp',
      label: 'Freno chirp',
      description: 'Chirrido breve, con carácter',
      assetPath: 'sounds/notify_bike_brake_chirp.wav',
      group: NotificationSoundGroup.workshop,
      volumeScale: 0.34,
    ),
    NotificationSoundOption(
      id: 'bike_brake_soft',
      label: 'Freno suave',
      description: 'Freno real, más apagado',
      assetPath: 'sounds/notify_bike_brake_soft.wav',
      group: NotificationSoundGroup.workshop,
      volumeScale: 0.30,
    ),
    NotificationSoundOption(
      id: 'bike_bell_ping',
      label: 'Bell ping',
      description: 'Campana corta y limpia',
      assetPath: 'sounds/notify_bike_bell_ping.wav',
      group: NotificationSoundGroup.workshop,
      volumeScale: 0.56,
    ),
    NotificationSoundOption(
      id: 'bike_bell_double',
      label: 'Bell doble',
      description: 'Doble campana muy recortada',
      assetPath: 'sounds/notify_bike_bell_double.wav',
      group: NotificationSoundGroup.workshop,
      volumeScale: 0.62,
    ),
    NotificationSoundOption(
      id: 'bike_spoke_flick',
      label: 'Spoke flick',
      description: 'Toque metálico de rueda',
      assetPath: 'sounds/notify_bike_spoke_flick.wav',
      group: NotificationSoundGroup.workshop,
      volumeScale: 0.56,
    ),
    NotificationSoundOption(
      id: 'pos_scan',
      label: 'Scan caja',
      description: 'Beep POS corto y limpio',
      assetPath: 'sounds/notify_pos_scan.wav',
      group: NotificationSoundGroup.pointOfSale,
      volumeScale: 0.44,
    ),
    NotificationSoundOption(
      id: 'pos_scan_soft',
      label: 'Scan suave',
      description: 'Scanner menos brillante',
      assetPath: 'sounds/notify_pos_scan_soft.wav',
      group: NotificationSoundGroup.pointOfSale,
      volumeScale: 0.42,
    ),
    NotificationSoundOption(
      id: 'pos_confirm',
      label: 'Confirmación POS',
      description: 'Confirmación compacta',
      assetPath: 'sounds/notify_pos_confirm.wav',
      group: NotificationSoundGroup.pointOfSale,
      volumeScale: 0.40,
    ),
    NotificationSoundOption(
      id: 'digital_blip',
      label: 'Blip digital',
      description: 'Digital, corto, no invasivo',
      assetPath: 'sounds/notify_digital_blip.wav',
      group: NotificationSoundGroup.digital,
      volumeScale: 0.62,
    ),
    NotificationSoundOption(
      id: 'digital_glint',
      label: 'Glint digital',
      description: 'Brillante pero recortado',
      assetPath: 'sounds/notify_digital_glint.wav',
      group: NotificationSoundGroup.digital,
      volumeScale: 0.50,
    ),
    NotificationSoundOption(
      id: 'digital_sent',
      label: 'Enviado suave',
      description: 'Confirmación digital baja',
      assetPath: 'sounds/notify_digital_sent.wav',
      group: NotificationSoundGroup.digital,
      volumeScale: 0.34,
    ),
    NotificationSoundOption(
      id: 'desk_trackpad',
      label: 'Trackpad',
      description: 'Click físico limpio',
      assetPath: 'sounds/notify_desk_trackpad.wav',
      group: NotificationSoundGroup.desk,
      volumeScale: 0.74,
    ),
    NotificationSoundOption(
      id: 'desk_keys',
      label: 'Teclas rápidas',
      description: 'Teclado real, muy corto',
      assetPath: 'sounds/notify_desk_keys.wav',
      group: NotificationSoundGroup.desk,
      volumeScale: 0.76,
    ),
    NotificationSoundOption(
      id: 'desk_key_soft',
      label: 'Tecla suave',
      description: 'Click de escritorio apagado',
      assetPath: 'sounds/notify_desk_key_soft.wav',
      group: NotificationSoundGroup.desk,
      volumeScale: 0.82,
    ),
    NotificationSoundOption(
      id: 'dry_click',
      label: 'Clic seco',
      description: 'Corto, seco, sin melodía',
      assetPath: 'sounds/notify_dry_click.wav',
      volumeScale: 0.9,
    ),
    NotificationSoundOption(
      id: 'low_tap',
      label: 'Tap bajo',
      description: 'Muy discreto para uso constante',
      assetPath: 'sounds/notify_low_tap.wav',
      volumeScale: 0.95,
    ),
    NotificationSoundOption(
      id: 'soft_tock',
      label: 'Tock suave',
      description: 'Más redondo y menos brillante',
      assetPath: 'sounds/notify_soft_tock.wav',
      volumeScale: 0.92,
    ),
    NotificationSoundOption(
      id: 'soft_snap',
      label: 'Chasquido suave',
      description: 'El más corto de la lista',
      assetPath: 'sounds/notify_soft_snap.wav',
      volumeScale: 0.88,
    ),
    NotificationSoundOption(
      id: 'double_click',
      label: 'Doble clic',
      description: 'Dos golpes secos y bajos',
      assetPath: 'sounds/notify_double_click.wav',
      volumeScale: 0.82,
    ),
    NotificationSoundOption(
      id: 'muted_ping',
      label: 'Ping apagado',
      description: 'Claro, pero sin campana larga',
      assetPath: 'sounds/notify_muted_ping.wav',
      volumeScale: 0.78,
    ),
    NotificationSoundOption(
      id: 'classic',
      label: 'Clásico original',
      description: 'El sonido original de la app',
      assetPath: 'sounds/notification.mp3',
      volumeScale: 0.78,
    ),
  ];

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  bool _isInitialized = false;
  Future<void>? _initializingFuture;
  StreamSubscription<AuthState>? _authStateSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  RealtimeChannel? _desktopMessagesChannel;
  Timer? _desktopMessagesRetryTimer;
  int _desktopMessagesRetryAttempt = 0;
  bool _desktopMessagesSetupInFlight = false;
  String? _desktopMessagesTenantId;
  String? _desktopMessagesAuthUserId;

  // Cache for messaging style notifications to support grouping
  // Key: conversation_id (or sender_id if 1:1)
  final Map<String, List<Message>> _activeConversations = {};

  // Cache for sender names to avoid repeated DB lookups
  final Map<String, String> _senderNames = {};

  // Track last handled notification to prevent duplicate navigation
  String? _lastHandledNotificationId;

  // User Settings
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _messageNotificationsEnabled = true;
  bool _emailNotificationsEnabled = true;
  String _messageSoundId = defaultMessageSoundId;
  String _emailSoundId = defaultEmailSoundId;
  double _soundVolume = 0.56;

  bool get notificationsEnabled => _notificationsEnabled;
  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get messageNotificationsEnabled => _messageNotificationsEnabled;
  bool get emailNotificationsEnabled => _emailNotificationsEnabled;
  String get messageSoundId => _messageSoundId;
  String get emailSoundId => _emailSoundId;
  double get soundVolume => _soundVolume;

  final ValueNotifier<int> onlineOrderAlertCount = ValueNotifier<int>(0);
  final Set<String> _seenOnlineOrderAlertIds = {};
  final List<Map<String, dynamic>> _onlineOrderAlertRows = [];
  String? _onlineOrderTenantId;

  final _messageStreamController = StreamController<RemoteMessage>.broadcast();
  Object? _foregroundPresentationPolicyOwner;
  bool Function(RemoteMessage message)? _foregroundPresentationPolicy;

  /// Stream of incoming messages (foreground & background)
  /// Listen to this to update UI badges or show in-app alerts
  Stream<RemoteMessage> get onMessageReceived =>
      _messageStreamController.stream;

  // Deprecated getter, keeping for backward compatibility if needed, map to new stream
  Stream<RemoteMessage> get messageStream => _messageStreamController.stream;

  /// Installs the process-level foreground presentation policy owned by the
  /// stable workspace shell. Incoming events still reach [messageStream] so
  /// providers can update unread state, but sounds and native banners may be
  /// suppressed while the matching conversation is visibly open.
  void setForegroundPresentationPolicy(
    Object owner,
    bool Function(RemoteMessage message) policy,
  ) {
    _foregroundPresentationPolicyOwner = owner;
    _foregroundPresentationPolicy = policy;
  }

  void clearForegroundPresentationPolicy(Object owner) {
    if (!identical(_foregroundPresentationPolicyOwner, owner)) return;
    _foregroundPresentationPolicyOwner = null;
    _foregroundPresentationPolicy = null;
  }

  bool shouldPresentForegroundMessage(RemoteMessage message) {
    return _foregroundPresentationPolicy?.call(message) ?? true;
  }

  /// Whether the stable application shell owns foreground presentation.
  ///
  /// The service still publishes every event through [messageStream] so the
  /// canonical inbox can reconcile unread state. When a shell owner is
  /// installed, sounds, banners and local notifications must be emitted only
  /// after that owner has applied its process-wide stable-event gate.
  bool get hasForegroundPresentationOwner =>
      _foregroundPresentationPolicyOwner != null &&
      _foregroundPresentationPolicy != null;

  /// Stream for notification taps that require navigation (deep links)
  final _navigationStreamController = StreamController<String>.broadcast();
  Stream<String> get onNotificationTap => _navigationStreamController.stream;

  String? get latestOnlineOrderAlertRoute {
    if (_onlineOrderAlertRows.isEmpty) return null;
    return _onlineOrderAlertRows.first['route']?.toString();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    _soundEnabled = prefs.getBool('notification_sound') ?? true;
    _vibrationEnabled = prefs.getBool('notification_vibration') ?? true;
    _messageNotificationsEnabled =
        prefs.getBool('notification_messages_enabled') ?? true;
    _emailNotificationsEnabled =
        prefs.getBool('notification_email_enabled') ?? true;
    _messageSoundId = _validSoundId(
      prefs.getString('notification_message_sound') ?? defaultMessageSoundId,
      fallback: defaultMessageSoundId,
    );
    _emailSoundId = _validSoundId(
      prefs.getString('notification_email_sound') ?? defaultEmailSoundId,
      fallback: defaultEmailSoundId,
    );
    _soundVolume = (prefs.getDouble('notification_sound_volume') ?? 0.56)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Future<void> loadSettingsForUi() => _loadSettings();

  static NotificationSoundOption soundOptionById(String id) {
    for (final option in soundOptions) {
      if (option.id == id) return option;
    }
    return soundOptions
        .firstWhere((option) => option.id == defaultGeneralSoundId);
  }

  static List<NotificationSoundOption> soundOptionsForGroup(
    NotificationSoundGroup group,
  ) {
    return soundOptions
        .where((option) => option.group == group)
        .toList(growable: false);
  }

  static String _validSoundId(String id, {required String fallback}) {
    for (final option in soundOptions) {
      if (option.id == id) return id;
    }
    return fallback;
  }

  bool notificationsEnabledFor(NotificationCategory category) {
    if (!_notificationsEnabled) return false;
    return switch (category) {
      NotificationCategory.general => true,
      NotificationCategory.message => _messageNotificationsEnabled,
      NotificationCategory.email => _emailNotificationsEnabled,
    };
  }

  String soundIdForCategory(NotificationCategory category) {
    return switch (category) {
      NotificationCategory.general => defaultGeneralSoundId,
      NotificationCategory.message => _messageSoundId,
      NotificationCategory.email => _emailSoundId,
    };
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
  }

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_sound', value);
  }

  Future<void> setVibrationEnabled(bool value) async {
    _vibrationEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_vibration', value);
  }

  Future<void> setCategoryNotificationsEnabled(
    NotificationCategory category,
    bool value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    switch (category) {
      case NotificationCategory.general:
        await setNotificationsEnabled(value);
        return;
      case NotificationCategory.message:
        _messageNotificationsEnabled = value;
        await prefs.setBool('notification_messages_enabled', value);
        return;
      case NotificationCategory.email:
        _emailNotificationsEnabled = value;
        await prefs.setBool('notification_email_enabled', value);
        return;
    }
  }

  Future<void> setSoundForCategory(
    NotificationCategory category,
    String soundId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final validSoundId =
        _validSoundId(soundId, fallback: defaultGeneralSoundId);
    switch (category) {
      case NotificationCategory.general:
        return;
      case NotificationCategory.message:
        _messageSoundId = validSoundId;
        await prefs.setString('notification_message_sound', validSoundId);
        return;
      case NotificationCategory.email:
        _emailSoundId = validSoundId;
        await prefs.setString('notification_email_sound', validSoundId);
        return;
    }
  }

  Future<void> setSoundVolume(double value) async {
    _soundVolume = value.clamp(0.0, 1.0).toDouble();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('notification_sound_volume', _soundVolume);
  }

  Future<List<Map<String, dynamic>>> loadOnlineOrderAlerts(
    String tenantId,
  ) async {
    if (tenantId.trim().isEmpty) return const [];
    final generation = _notificationScopeGeneration;
    if (_notificationScopeTenantId != tenantId) return const [];
    _onlineOrderTenantId = tenantId;

    try {
      final response = await _supabase
          .from('erp_notifications')
          .select('id,title,body,route,entity_id,created_at')
          .eq('tenant_id', tenantId)
          .eq('type', 'online_order_created')
          .isFilter('read_at', null)
          .order('created_at', ascending: false)
          .limit(200);

      final rows = (response as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (generation != _notificationScopeGeneration ||
          _notificationScopeTenantId != tenantId) {
        return const [];
      }
      _onlineOrderAlertRows
        ..clear()
        ..addAll(rows);
      _seenOnlineOrderAlertIds
        ..clear()
        ..addAll(rows.map((row) => row['id']?.toString() ?? ''));
      _seenOnlineOrderAlertIds.remove('');
      onlineOrderAlertCount.value = rows.length;
      return rows;
    } catch (e) {
      debugPrint('⚠️ Could not load online order alerts: $e');
      return const [];
    }
  }

  bool recordOnlineOrderAlert(
    String notificationId, {
    Map<String, dynamic>? notification,
  }) {
    final notificationTenantId = notification?['tenant_id']?.toString();
    if (_notificationScopeTenantId == null ||
        (notificationTenantId != null &&
            notificationTenantId != _notificationScopeTenantId)) {
      return false;
    }
    if (notificationId.trim().isEmpty ||
        !_seenOnlineOrderAlertIds.add(notificationId)) {
      return false;
    }

    if (notification != null) {
      _onlineOrderAlertRows.insert(0, Map<String, dynamic>.from(notification));
    }
    onlineOrderAlertCount.value = onlineOrderAlertCount.value + 1;
    return true;
  }

  Future<void> markOnlineOrderAlertReadForOrder(String orderId) async {
    final tenantId =
        _onlineOrderTenantId ?? await TenantService().getTenantId();
    final trimmedOrderId = orderId.trim();
    if (tenantId == null || tenantId.isEmpty || trimmedOrderId.isEmpty) return;
    _onlineOrderTenantId = tenantId;

    final existingIndex = _onlineOrderAlertRows.indexWhere(
      (row) => row['entity_id']?.toString() == trimmedOrderId,
    );
    final existing = existingIndex == -1
        ? null
        : _onlineOrderAlertRows.removeAt(existingIndex);
    final notificationId = existing?['id']?.toString();
    if (existing != null) {
      if (notificationId != null && notificationId.isNotEmpty) {
        _seenOnlineOrderAlertIds.remove(notificationId);
      }
      if (onlineOrderAlertCount.value > 0) {
        onlineOrderAlertCount.value = onlineOrderAlertCount.value - 1;
      }
    }

    try {
      await _supabase
          .from('erp_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('tenant_id', tenantId)
          .eq('type', 'online_order_created')
          .eq('entity_type', 'online_order')
          .eq('entity_id', trimmedOrderId)
          .isFilter('read_at', null);
      if (existing == null) {
        await loadOnlineOrderAlerts(tenantId);
      }
    } catch (e) {
      debugPrint('⚠️ Could not mark online order alert read: $e');
      if (existing != null) {
        _onlineOrderAlertRows.insert(existingIndex, existing);
        if (notificationId != null && notificationId.isNotEmpty) {
          _seenOnlineOrderAlertIds.add(notificationId);
        }
        onlineOrderAlertCount.value = onlineOrderAlertCount.value + 1;
      }
    }
  }

  void clearOnlineOrderAlerts() {
    if (onlineOrderAlertCount.value == 0) return;
    onlineOrderAlertCount.value = 0;
    _onlineOrderAlertRows.clear();
    _seenOnlineOrderAlertIds.clear();
  }

  Future<void> markOnlineOrderAlertsRead() async {
    final tenantId = _onlineOrderTenantId;
    clearOnlineOrderAlerts();
    if (tenantId == null || tenantId.isEmpty) return;

    try {
      await _supabase
          .from('erp_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('tenant_id', tenantId)
          .eq('type', 'online_order_created')
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('⚠️ Could not mark online order alerts read: $e');
    }
  }

  // ============================================================
  // GENERIC NOTIFICATIONS CENTER FEED
  // Backed by the shared erp_notifications table. Surfaces every
  // notification type (jobs, payments, expenses, online orders, WhatsApp
  // catalog approvals, ...) in one feed for the right-side panel.
  // ============================================================

  /// Latest notifications (read + unread) for the current tenant.
  final ValueNotifier<List<Map<String, dynamic>>> notificationsFeed =
      ValueNotifier<List<Map<String, dynamic>>>(const []);

  /// Unread ERP alerts created during the current local business day.
  ///
  /// The right-toolbar badge is a prompt for today's attention, not a lifetime
  /// inbox counter. Older unread rows remain available through the briefing's
  /// calendar-period selector and can still be marked read, but no longer
  /// accumulate into a permanent `99+` badge.
  final ValueNotifier<int> unreadNotificationsCount = ValueNotifier<int>(0);

  String? _notificationsTenantId;
  String? _notificationScopeKey;
  String? _notificationScopeTenantId;
  int _notificationScopeGeneration = 0;
  static const int _historicalNotificationPageSize = 500;

  /// Clears process-wide notification projections when the authenticated
  /// user/tenant changes. The stable workspace shell calls this before loading
  /// the new baseline, so old badges and previews can never leak across users.
  void activateNotificationScope({
    required String userId,
    required String tenantId,
  }) {
    final nextScope = '${userId.trim()}:${tenantId.trim()}';
    if (userId.trim().isEmpty || tenantId.trim().isEmpty) {
      throw ArgumentError('Notification scope requires user and tenant IDs.');
    }
    if (_notificationScopeKey == nextScope) return;
    _notificationScopeKey = nextScope;
    _notificationScopeTenantId = tenantId.trim();
    _notificationScopeGeneration++;
    _clearUserScopedNotificationState();
  }

  void clearNotificationScope() {
    _notificationScopeKey = null;
    _notificationScopeTenantId = null;
    _notificationScopeGeneration++;
    _clearUserScopedNotificationState();
  }

  void _clearUserScopedNotificationState() {
    _onlineOrderTenantId = null;
    _onlineOrderAlertRows.clear();
    _seenOnlineOrderAlertIds.clear();
    onlineOrderAlertCount.value = 0;
    _notificationsTenantId = null;
    notificationsFeed.value = const [];
    unreadNotificationsCount.value = 0;
    _activeConversations.clear();
    _senderNames.clear();
    _lastHandledNotificationId = null;
  }

  void _recomputeUnreadCount() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final unread = notificationsFeed.value.where((row) {
      if (row['read_at'] != null) return false;
      final createdAt = DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      )?.toLocal();
      return createdAt != null &&
          !createdAt.isBefore(today) &&
          createdAt.isBefore(tomorrow);
    }).length;
    unreadNotificationsCount.value = unread;
  }

  /// Load the latest notifications for the notifications center.
  Future<List<Map<String, dynamic>>> loadNotifications(String tenantId) async {
    if (tenantId.trim().isEmpty) return const [];
    final generation = _notificationScopeGeneration;
    if (_notificationScopeTenantId != tenantId) return const [];
    _notificationsTenantId = tenantId;

    try {
      final response = await _supabase
          .from('erp_notifications')
          .select(
              'id,type,title,body,route,entity_type,entity_id,severity,data,read_at,created_at')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(100);

      final rows = (response as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (generation != _notificationScopeGeneration ||
          _notificationScopeTenantId != tenantId) {
        return const [];
      }
      notificationsFeed.value = rows;
      _recomputeUnreadCount();
      return rows;
    } catch (e) {
      debugPrint('⚠️ Could not load notifications: $e');
      return const [];
    }
  }

  /// Loads every notification created within [startsAt, endsAt).
  ///
  /// This historical projection is tenant/scope safe and intentionally does
  /// not publish into [notificationsFeed], which remains the latest realtime
  /// projection used by the toolbar badge.
  Future<List<Map<String, dynamic>>> loadNotificationsForRange({
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final startUtc = startsAt.toUtc();
    final endUtc = endsAt.toUtc();
    if (!endUtc.isAfter(startUtc)) {
      throw ArgumentError.value(
        endsAt,
        'endsAt',
        'Must be after startsAt.',
      );
    }

    final tenantId = _notificationScopeTenantId;
    if (tenantId == null || tenantId.isEmpty) return const [];
    final generation = _notificationScopeGeneration;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;

    try {
      while (true) {
        final response = await _supabase
            .from('erp_notifications')
            .select(
                'id,type,title,body,route,entity_type,entity_id,severity,data,read_at,created_at')
            .eq('tenant_id', tenantId)
            .gte('created_at', startUtc.toIso8601String())
            .lt('created_at', endUtc.toIso8601String())
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .range(
              offset,
              offset + _historicalNotificationPageSize - 1,
            );

        if (generation != _notificationScopeGeneration ||
            _notificationScopeTenantId != tenantId) {
          return const [];
        }

        final page = (response as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
        rows.addAll(page);
        if (page.length < _historicalNotificationPageSize) break;
        offset += _historicalNotificationPageSize;
      }
      return rows;
    } catch (e) {
      debugPrint('⚠️ Could not load historical notifications: $e');
      rethrow;
    }
  }

  /// Insert/refresh a single notification row (used by realtime inserts).
  void recordNotification(Map<String, dynamic> notification) {
    final id = notification['id']?.toString();
    final tenantId = notification['tenant_id']?.toString();
    if (id == null ||
        id.isEmpty ||
        _notificationScopeTenantId == null ||
        tenantId != _notificationScopeTenantId) {
      return;
    }

    final current = List<Map<String, dynamic>>.from(notificationsFeed.value);
    final existingIndex =
        current.indexWhere((row) => row['id']?.toString() == id);
    final row = Map<String, dynamic>.from(notification);
    if (existingIndex == -1) {
      current.insert(0, row);
    } else {
      current[existingIndex] = row;
    }
    notificationsFeed.value = current;
    _recomputeUnreadCount();
  }

  /// Mark a single notification as read (local + database).
  Future<void> markNotificationRead(String notificationId) async {
    final id = notificationId.trim();
    if (id.isEmpty) return;
    final tenantId = _notificationScopeTenantId;
    if (tenantId == null || tenantId.isEmpty) return;

    final current = List<Map<String, dynamic>>.from(notificationsFeed.value);
    final index = current.indexWhere((row) => row['id']?.toString() == id);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    if (index != -1 && current[index]['read_at'] == null) {
      current[index] = {...current[index], 'read_at': nowIso};
      notificationsFeed.value = current;
      _recomputeUnreadCount();
    }

    try {
      await _supabase
          .from('erp_notifications')
          .update({'read_at': nowIso})
          .eq('tenant_id', tenantId)
          .eq('id', id)
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('⚠️ Could not mark notification read: $e');
    }
  }

  /// Marks unread notifications created within [startsAt, endsAt) as read.
  ///
  /// Only matching rows in the latest local projection are reconciled. Rows
  /// outside the latest feed are still updated through the tenant-scoped
  /// database query.
  Future<void> markNotificationsReadForRange({
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final startUtc = startsAt.toUtc();
    final endUtc = endsAt.toUtc();
    if (!endUtc.isAfter(startUtc)) {
      throw ArgumentError.value(
        endsAt,
        'endsAt',
        'Must be after startsAt.',
      );
    }

    final tenantId = _notificationScopeTenantId;
    if (tenantId == null || tenantId.isEmpty) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    var changed = false;
    final current = notificationsFeed.value.map((row) {
      if (row['read_at'] != null) return row;
      final createdAt =
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toUtc();
      if (createdAt == null ||
          createdAt.isBefore(startUtc) ||
          !createdAt.isBefore(endUtc)) {
        return row;
      }
      changed = true;
      return <String, dynamic>{...row, 'read_at': nowIso};
    }).toList(growable: false);

    if (changed) {
      notificationsFeed.value = current;
      _recomputeUnreadCount();
    }

    try {
      await _supabase
          .from('erp_notifications')
          .update({'read_at': nowIso})
          .eq('tenant_id', tenantId)
          .gte('created_at', startUtc.toIso8601String())
          .lt('created_at', endUtc.toIso8601String())
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('⚠️ Could not mark historical notifications read: $e');
    }
  }

  /// Mark every unread notification as read for the current tenant.
  Future<void> markAllNotificationsRead() async {
    final tenantId =
        _notificationsTenantId ?? await TenantService().getTenantId();
    if (tenantId == null || tenantId.isEmpty) return;
    _notificationsTenantId = tenantId;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final current = notificationsFeed.value
        .map(
            (row) => row['read_at'] == null ? {...row, 'read_at': nowIso} : row)
        .toList();
    notificationsFeed.value = current;
    _recomputeUnreadCount();

    try {
      await _supabase
          .from('erp_notifications')
          .update({'read_at': nowIso})
          .eq('tenant_id', tenantId)
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('⚠️ Could not mark all notifications read: $e');
    }
  }

  Future<void> playNotificationSound({
    NotificationCategory category = NotificationCategory.general,
    String? soundId,
    bool preview = false,
  }) async {
    if (!preview && (!_soundEnabled || !notificationsEnabledFor(category))) {
      return;
    }

    // Web: audio playback is often blocked by browser policy, and plugin
    // initialization can throw MissingPluginException depending on build.
    // Never let notification sounds crash app startup.
    if (kIsWeb) return;

    try {
      _audioPlayer ??= AudioPlayer();
      final option = soundOptionById(soundId ?? soundIdForCategory(category));
      final effectiveVolume =
          (_soundVolume * option.volumeScale).clamp(0.0, 1.0).toDouble();
      await _audioPlayer!.play(
        AssetSource(option.assetPath),
        volume: effectiveVolume,
      );
    } catch (e) {
      debugPrint('⚠️ Audio playback failed: $e');
    }
  }

  void _triggerVibration() {
    if (!_vibrationEnabled || kIsWeb) return;

    try {
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('⚠️ Could not trigger vibration: $e');
    }
  }

  Future<void> init() {
    if (_isInitialized) return Future<void>.value();
    final inFlight = _initializingFuture;
    if (inFlight != null) return inFlight;

    final operation = _initInternal();
    _initializingFuture = operation;
    return operation.whenComplete(() {
      if (identical(_initializingFuture, operation)) {
        _initializingFuture = null;
      }
    });
  }

  Future<void> _initInternal() async {
    if (_isInitialized) return;

    // Web: Skip FCM for now - causes service worker conflicts and permission violations
    // TODO: Re-enable web push with proper user-initiated permission flow
    if (kIsWeb) {
      await _loadSettings();
      _isInitialized = true;
      debugPrint(
          'ℹ️ [NotificationService] Web push disabled - using in-app only');
      return;
    }

    // 1. Initialize Local Notifications for ALL platforms
    const initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initializationSettingsMacOS = DarwinInitializationSettings();
    const initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');
    const initializationSettingsWindows = WindowsInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      macOS: initializationSettingsMacOS,
      linux: initializationSettingsLinux,
      windows: initializationSettingsWindows,
    );

    debugPrint('🔔 [NotificationService] Initializing...');
    await _localNotifications.initialize(initializationSettings);
    _isInitialized = true;
    debugPrint('✅ [NotificationService] Local notifications initialized');

    // Create dedicated chat notification channel on Android
    if (defaultTargetPlatform == TargetPlatform.android) {
      const chatChannel = AndroidNotificationChannel(
        'chat_messages',
        'Mensajes de chat',
        description: 'Notificaciones de mensajes de chat',
        importance: Importance.high,
        enableVibration: true,
        playSound: false,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(chatChannel);

      const mailChannel = AndroidNotificationChannel(
        'mail_messages',
        'Correos',
        description: 'Notificaciones de correos entrantes',
        importance: Importance.high,
        enableVibration: true,
        playSound: false,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(mailChannel);
    }

    // Load user settings
    await _loadSettings();

    // Listen for auth changes to save token when user logs in
    await _authStateSubscription?.cancel();
    _authStateSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null && _fcmToken != null) {
        debugPrint('👤 [NotificationService] User logged in, saving token...');
        _saveTokenToDatabase(_fcmToken!);
      }

      if (data.event == AuthChangeEvent.signedOut) {
        ChatNotificationGate.shared.clearScope();
        MailNotificationGate.shared.clearScope();
        ErpNotificationGate.shared.clearScope();
        clearNotificationScope();
      }

      if (_usesDesktopRealtimeNotifications) {
        if (data.session != null) {
          unawaited(_setupDesktopMessageRealtime());
        } else if (data.event == AuthChangeEvent.signedOut) {
          unawaited(_teardownDesktopMessageRealtime());
        }
      }
    });

    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await _initMobile();
    } else {
      await _initDesktop();
    }
  }

  Future<void> _initMobile() async {
    // Safety check: specific platforms might be misidentified or init might have failed
    if (Firebase.apps.isEmpty) {
      debugPrint(
          '⚠️ Firebase not initialized, skipping mobile notification setup.');
      return;
    }

    final firebaseMessaging = FirebaseMessaging.instance;

    // 1. Request Permission
    NotificationSettings settings = await firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted permission');

      // 2. Register Background Handler
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // 3. Get Token (with retry for iOS APNS token not ready)
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Wait a bit for APNS token to be ready on iOS
        for (int i = 0; i < 5; i++) {
          try {
            final apnsToken = await firebaseMessaging.getAPNSToken();
            if (apnsToken != null) {
              _fcmToken = await firebaseMessaging.getToken();
              break;
            }
          } catch (e) {
            debugPrint('⏳ APNS token not ready, retrying... ($i/5)');
          }
          await Future.delayed(const Duration(seconds: 2));
        }
      } else {
        _fcmToken = await firebaseMessaging.getToken(
          vapidKey: kIsWeb
              ? 'BEiJc0XNBT3YycnP1Rk1_lojF3EKAEQzyiOceq1vWM20OmeoS4bkDShbVSHIuVCuNP6uHDHYhpaFbNayxv24Iws'
              : null,
        );
      }

      // 4. Save Token to Database
      if (_fcmToken != null) {
        await _saveTokenToDatabase(_fcmToken!);
      }

      // 5. Listen for token refreshes
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription =
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _saveTokenToDatabase(newToken);
      });

      // 6. Listen for Foreground Messages
      await _foregroundMessageSubscription?.cancel();
      _foregroundMessageSubscription =
          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint('🔔 Foreground notification received');
        }

        // Handle both notification+data and data-only messages
        final hasNotification = message.notification != null;
        final hasData = message.data.isNotEmpty;

        if (hasData || hasNotification) {
          final category = categoryForMessage(message);

          // Notify in-app listeners (Snackbar)
          _messageStreamController.add(message);

          if (!hasForegroundPresentationOwner &&
              notificationsEnabledFor(category) &&
              shouldPresentForegroundMessage(message)) {
            // Play sound and vibrate
            playNotificationSound(category: category);
            _triggerVibration();

            handleIncomingMessage(message);
          }
        }
      });

      // 7. Handle notification tap when app is in background (not terminated)
      await _openedAppSubscription?.cancel();
      _openedAppSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) debugPrint('🔔 Background notification opened');
        _handleNotificationTap(message);
      });

      // 8. Handle notification tap when app was terminated (cold start)
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          if (kDebugMode) debugPrint('🔔 Initial notification opened');
          // Delay slightly to ensure app is ready
          Future.delayed(const Duration(milliseconds: 500), () {
            _handleNotificationTap(message);
          });
        }
      });
    } else {
      debugPrint('User declined or has not accepted permission');
    }
  }

  /// Handle navigation when user taps a notification
  void _handleNotificationTap(RemoteMessage message) {
    // Prevent duplicate handling of the same notification
    final messageId =
        (message.data['message_id'] ?? message.data['id'] ?? message.messageId)
            ?.toString()
            .trim();
    if (messageId != null &&
        messageId.isNotEmpty &&
        messageId == _lastHandledNotificationId) {
      debugPrint('🔔 Already handled notification $messageId, skipping');
      return;
    }
    if (messageId != null && messageId.isNotEmpty) {
      _lastHandledNotificationId = messageId;
    }

    final route = message.data['route']?.toString();
    if (route != null && route.isNotEmpty) {
      debugPrint('🔔 Navigating to notification route: $route');
      _navigationStreamController.add(route);
      return;
    }

    final conversationId = message.data['conversation_id'];
    if (conversationId != null && conversationId.toString().isNotEmpty) {
      debugPrint('🔔 Navigating to chat: $conversationId');
      // Emit to stream for main.dart to handle navigation
      _navigationStreamController.add('/chat?conversation=$conversationId');
    } else {
      // Fallback: just go to chat list
      debugPrint('🔔 No conversation_id, navigating to chat list');
      _navigationStreamController.add('/chat');
    }
  }

  /// Request web notification permission - MUST be called from user gesture (click/tap)
  Future<bool> requestWebNotificationPermission() async {
    if (!kIsWeb) return false;

    try {
      final firebaseMessaging = FirebaseMessaging.instance;

      NotificationSettings settings = await firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Web push permission granted');
        await _setupWebMessaging(firebaseMessaging);
        return true;
      }
    } catch (e) {
      debugPrint('❌ Error requesting web permission: $e');
    }
    return false;
  }

  /// Set up FCM messaging after permission is granted
  Future<void> _setupWebMessaging(FirebaseMessaging firebaseMessaging) async {
    // Get FCM token with VAPID key
    _fcmToken = await firebaseMessaging.getToken(
      vapidKey:
          'BEiJc0XNBT3YycnP1Rk1_lojF3EKAEQzyiOceq1vWM20OmeoS4bkDShbVSHIuVCuNP6uHDHYhpaFbNayxv24Iws',
    );

    debugPrint('🔑 Web FCM Token: $_fcmToken');

    if (_fcmToken != null) {
      await _saveTokenToDatabase(_fcmToken!);
    }

    // Listen for foreground messages
    await _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription =
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) debugPrint('🔔 Web foreground notification received');
      _messageStreamController.add(message);
      // The in-app notification overlay will handle display
    });

    // Listen for token refresh
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription =
        firebaseMessaging.onTokenRefresh.listen((newToken) {
      debugPrint('🔄 Web FCM token refreshed');
      _fcmToken = newToken;
      _saveTokenToDatabase(newToken);
    });
  }

  // ignore: unused_element
  Future<void> _initDesktop() async {
    debugPrint('🖥️ Initializing Desktop Notifications...');

    // const initializationSettingsLinux =
    //     LinuxInitializationSettings(defaultActionName: 'Open notification');
    // const initializationSettings = InitializationSettings(
    //   macOS: initializationSettingsMacOS,
    //   linux: initializationSettingsLinux,
    // );
    // await _localNotifications.initialize(initializationSettings);

    // Request Permissions explicitly for macOS
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    // 2. Listen to Realtime Messages
    if (_supabase.auth.currentUser == null) {
      debugPrint(
          '🔔 Desktop message notifications waiting for authenticated session');
      return;
    }

    unawaited(_setupDesktopMessageRealtime());
  }

  bool get _usesDesktopRealtimeNotifications {
    if (kIsWeb) return false;
    return defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
  }

  Future<void> _setupDesktopMessageRealtime({bool force = false}) async {
    if (_desktopMessagesSetupInFlight) return;

    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      debugPrint(
          '🔔 Desktop message notifications waiting for authenticated session');
      return;
    }

    final tenantService = TenantService();
    final cachedTenantId = tenantService.currentTenantId;
    final tenantId = (cachedTenantId != null && cachedTenantId.isNotEmpty)
        ? cachedTenantId
        : await tenantService.getTenantId();

    if (_supabase.auth.currentUser?.id != currentUser.id) return;

    if (tenantId == null || tenantId.isEmpty) {
      debugPrint('⚠️ Desktop message notifications waiting for tenant context');
      _scheduleDesktopMessageRealtimeReconnect('tenant context unavailable');
      return;
    }

    if (!force &&
        _desktopMessagesChannel != null &&
        _desktopMessagesTenantId == tenantId &&
        _desktopMessagesAuthUserId == currentUser.id) {
      return;
    }

    _desktopMessagesSetupInFlight = true;
    try {
      _desktopMessagesRetryTimer?.cancel();
      _desktopMessagesRetryTimer = null;

      if (_desktopMessagesChannel != null) {
        await _teardownDesktopMessageRealtime(cancelRetry: false);
      }

      if (_supabase.auth.currentUser?.id != currentUser.id) return;

      debugPrint(
          '🔔 Setting up tenant-filtered Realtime subscription for public:messages...');

      late final RealtimeChannel channel;
      channel = _supabase
          .channel('desktop-message-notifications-$tenantId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              if (_supabase.auth.currentUser?.id != currentUser.id) return;
              final newMessage = payload.newRecord;
              final currentUserId = _supabase.auth.currentUser?.id;
              final senderId = newMessage['sender_id'];

              // Show notification only if:
              // 1. We are logged in
              // 2. The sender is NOT us (incoming message)
              if (currentUserId != null && senderId != currentUserId) {
                final content = newMessage['content'] ?? 'New Image';
                final incomingMessage = RemoteMessage(
                  notification: RemoteNotification(
                    title: 'New Message',
                    body: content,
                  ),
                  data: newMessage,
                );

                // Notify in-app listeners (Desktop)
                _messageStreamController.add(incomingMessage);

                if (!hasForegroundPresentationOwner &&
                    notificationsEnabledFor(NotificationCategory.message) &&
                    shouldPresentForegroundMessage(incomingMessage)) {
                  // Play sound and vibrate
                  playNotificationSound(
                    category: NotificationCategory.message,
                  );
                  _triggerVibration();

                  showLocalNotification(
                    'New Message',
                    content,
                    category: NotificationCategory.message,
                  );
                }
              }
            },
          )
          .subscribe((status, error) {
        _handleDesktopMessageRealtimeStatus(channel, status, error);
      });

      _desktopMessagesChannel = channel;
      _desktopMessagesTenantId = tenantId;
      _desktopMessagesAuthUserId = currentUser.id;
    } catch (e) {
      debugPrint('⚠️ Desktop message notification realtime setup failed: $e');
      _scheduleDesktopMessageRealtimeReconnect('setup failed');
    } finally {
      _desktopMessagesSetupInFlight = false;
      final activeUserId = _supabase.auth.currentUser?.id;
      if (activeUserId != null &&
          (_desktopMessagesChannel == null ||
              _desktopMessagesAuthUserId != activeUserId)) {
        unawaited(_setupDesktopMessageRealtime(force: true));
      }
    }
  }

  void _handleDesktopMessageRealtimeStatus(
    RealtimeChannel channel,
    RealtimeSubscribeStatus status,
    Object? error,
  ) {
    if (!identical(channel, _desktopMessagesChannel)) return;

    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _desktopMessagesRetryAttempt = 0;
        _desktopMessagesRetryTimer?.cancel();
        _desktopMessagesRetryTimer = null;
        debugPrint(
            '✅ Desktop message notification realtime active for tenant $_desktopMessagesTenantId');
        break;
      case RealtimeSubscribeStatus.channelError:
        debugPrint(
            '⚠️ Desktop message notification realtime issue: ${_describeDesktopRealtimeIssue(error)}');
        _scheduleDesktopMessageRealtimeReconnect('channel error');
        break;
      case RealtimeSubscribeStatus.closed:
        debugPrint('ℹ️ Desktop message notification realtime closed');
        _scheduleDesktopMessageRealtimeReconnect('channel closed');
        break;
      case RealtimeSubscribeStatus.timedOut:
        debugPrint('⚠️ Desktop message notification realtime timed out');
        _scheduleDesktopMessageRealtimeReconnect('subscribe timeout');
        break;
    }
  }

  String _describeDesktopRealtimeIssue(Object? error) {
    if (error == null) return 'socket closed without error details';

    final description = error.toString();
    if (description.contains('RealtimeCloseEvent(code: 1002')) {
      return '$description; websocket protocol close, retrying';
    }
    return description;
  }

  void _scheduleDesktopMessageRealtimeReconnect(String reason) {
    if (!_usesDesktopRealtimeNotifications ||
        _supabase.auth.currentUser == null ||
        (_desktopMessagesRetryTimer?.isActive ?? false)) {
      return;
    }

    const retryDelays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ];
    final nextAttempt = _desktopMessagesRetryAttempt + 1;
    final delayIndex = nextAttempt > retryDelays.length
        ? retryDelays.length - 1
        : nextAttempt - 1;
    final delay = retryDelays[delayIndex];
    _desktopMessagesRetryAttempt = nextAttempt;

    debugPrint(
        '🔁 Desktop message notification realtime reconnect in ${delay.inSeconds}s ($reason)');

    _desktopMessagesRetryTimer = Timer(delay, () {
      _desktopMessagesRetryTimer = null;
      unawaited(_reconnectDesktopMessageRealtime());
    });
  }

  Future<void> _reconnectDesktopMessageRealtime() async {
    if (_supabase.auth.currentUser == null) {
      await _teardownDesktopMessageRealtime();
      return;
    }

    await _teardownDesktopMessageRealtime(cancelRetry: false);
    await _setupDesktopMessageRealtime(force: true);
  }

  Future<void> _teardownDesktopMessageRealtime({
    bool cancelRetry = true,
  }) async {
    if (cancelRetry) {
      _desktopMessagesRetryTimer?.cancel();
      _desktopMessagesRetryTimer = null;
      _desktopMessagesRetryAttempt = 0;
    }

    final channel = _desktopMessagesChannel;
    _desktopMessagesChannel = null;
    _desktopMessagesTenantId = null;
    _desktopMessagesAuthUserId = null;
    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  /// Handles an incoming FCM message and decides how to show it
  // Made public to be accessible from top-level background handler
  Future<void> handleIncomingMessage(RemoteMessage message) async {
    final category = categoryForMessage(message);
    if (!notificationsEnabledFor(category)) return;

    final data = message.data;
    final notification = message.notification;

    final isMailNotification = data['type'] == 'mail' ||
        data['notification_type'] == 'mail' ||
        data['route'] == '/mail';

    if (isMailNotification) {
      await showLocalNotification(
        data['title'] ?? notification?.title ?? 'Nuevo correo',
        data['body'] ?? notification?.body ?? 'Correo entrante',
        notificationId: (data['history_id'] ?? data['email_address'] ?? 'mail')
            .toString()
            .hashCode,
        category: NotificationCategory.email,
      );
      return;
    }

    // Data-only messages have no notification field, so don't return early
    // if (notification == null) return;

    // Try to get conversation ID and Sender ID from data
    // Fallback: Use 'general' if missing
    final String conversationId =
        data['conversation_id'] ?? data['chat_id'] ?? 'general';
    final String senderId = data['sender_id'] ?? 'unknown_sender';

    if (kDebugMode) {
      debugPrint('🔔 Presenting a messaging notification');
    }

    try {
      // Determine sender name from data (preferred) or cache or DB
      String? senderName = data['sender_name'] ?? _senderNames[senderId];

      if (senderName == null) {
        // Attempt to fetch if we have a senderId (senderId = auth.users.id)
        if (senderId != 'unknown_sender') {
          try {
            // Get user_profile to find employee_id
            final userProfile = await _supabase
                .from('user_profiles')
                .select('employee_id')
                .eq('user_id', senderId)
                .maybeSingle()
                .timeout(const Duration(seconds: 2));

            if (userProfile != null && userProfile['employee_id'] != null) {
              // Get employee name
              final employee = await _supabase
                  .from('employees')
                  .select('first_name, last_name')
                  .eq('id', userProfile['employee_id'])
                  .maybeSingle()
                  .timeout(const Duration(seconds: 2));

              if (employee != null) {
                senderName =
                    '${employee['first_name']} ${employee['last_name']}'.trim();
                _senderNames[senderId] = senderName;
              }
            }
          } catch (e) {
            debugPrint('Error fetching sender name: $e');
          }
        }
        // Final fallback
        senderName ??= data['title'] ?? notification?.title ?? 'Nuevo Mensaje';
      }

      // Get body from data first, then notification
      final String body = data['body'] ?? notification?.body ?? '';

      // Create the Message object for MessagingStyle
      final Person person = Person(
        key: senderId,
        name: senderName,
        // icon: // Could load avatar if needed
      );

      final Message newMessage = Message(
        body,
        DateTime.now(),
        person,
      );

      // Update conversation cache
      if (!_activeConversations.containsKey(conversationId)) {
        _activeConversations[conversationId] = [];
      }
      _activeConversations[conversationId]!.add(newMessage);

      // Limit cache size per conversation (e.g. last 5 messages)
      if (_activeConversations[conversationId]!.length > 5) {
        _activeConversations[conversationId]!.removeAt(0);
      }

      await _showMessagingNotification(
        conversationId: conversationId,
        conversationTitle: data['group_name'], // Null if 1:1
        messages: _activeConversations[conversationId]!,
      );
    } catch (e) {
      debugPrint(
          '⚠️ MessagingStyle failed, falling back to simple notification: $e');
      showLocalNotification(
        data['title'] ?? notification?.title ?? 'New Message',
        data['body'] ?? notification?.body ?? '',
        notificationId: conversationId.hashCode,
        category: NotificationCategory.message,
      );
    }
  }

  NotificationCategory categoryForMessage(RemoteMessage message) {
    final data = message.data;
    final isMailNotification = data['type'] == 'mail' ||
        data['notification_type'] == 'mail' ||
        data['route'] == '/mail';
    if (isMailNotification) return NotificationCategory.email;
    return NotificationCategory.message;
  }

  Future<void> _showMessagingNotification({
    required String conversationId,
    String? conversationTitle,
    required List<Message> messages,
  }) async {
    if (!notificationsEnabledFor(NotificationCategory.message)) return;

    // Generate a consistent ID based on conversationId hash
    // This allows updating the *same* notification slot instead of creating new ones
    final int notificationId = conversationId.hashCode;

    final MessagingStyleInformation styleInfo = MessagingStyleInformation(
      messages.last.person ??
          const Person(
              name:
                  'User'), // Main persona (usually user, but here sender works)
      groupConversation: conversationTitle != null,
      conversationTitle: conversationTitle,
      messages: messages,
    );

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'chat_messages', // Dedicated chat channel
      'Mensajes de chat',
      channelDescription: 'Notificaciones de mensajes de chat',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: styleInfo,
      groupKey: 'com.vinabike.chat', // Group key for stacking
      tag:
          conversationId, // Same tag = replaces previous notification for this conversation
      setAsGroupSummary: false, // Individual conversation
      onlyAlertOnce: true, // Don't re-alert for updates to same notification
      playSound: false,
      color: const Color(0xFF000000),
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      macOS: const DarwinNotificationDetails(presentSound: false),
      linux: const LinuxNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );

    try {
      await _localNotifications.show(
        notificationId,
        conversationTitle ??
            messages.last.person?.name ??
            'Chat', // Title: Group Name or Sender Name
        messages.last.text, // Body: Last message text
        details,
      );
      debugPrint('✅ Messaging notification updated for $conversationId');
    } catch (e) {
      debugPrint('❌ Error showing messaging notification: $e');
    }
  }

  // Legacy method kept for simple alerts or errors
  Future<void> showLocalNotification(
    String title,
    String body, {
    int? notificationId,
    NotificationCategory category = NotificationCategory.general,
  }) async {
    if (!notificationsEnabledFor(category)) return;
    if (kIsWeb) return;
    try {
      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'default_channel',
          'General Notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: false,
        ),
        macOS: DarwinNotificationDetails(presentSound: false),
        linux: LinuxNotificationDetails(),
        windows: WindowsNotificationDetails(),
      );

      await _localNotifications.show(
        notificationId ?? DateTime.now().millisecond,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('❌ Error: $e');
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('user_fcm_tokens').upsert({
        'user_id': userId,
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, fcm_token');

      debugPrint('✅ FCM Token saved to Supabase');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }
}
