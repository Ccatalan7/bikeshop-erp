import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenant_service.dart';

/// Top-level function required by firebase_messaging for background handling.
/// Must be outside any class and cannot be an anonymous function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized (required for background isolate)
  await Firebase.initializeApp();

  debugPrint('🔔 Background message received: ${message.messageId}');
  debugPrint('🔔 Data: ${message.data}');

  // Process the message using the singleton instance
  // Note: In background, some services may not be available
  try {
    await NotificationService().handleIncomingMessage(message);
  } catch (e) {
    debugPrint('❌ Background handler error: $e');
  }
}

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _supabase = Supabase.instance.client;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  AudioPlayer? _audioPlayer;

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  bool _isInitialized = false;

  // Cache for messaging style notifications to support grouping
  // Key: conversation_id (or sender_id if 1:1)
  final Map<String, List<Message>> _activeConversations = {};

  // Cache for sender names to avoid repeated DB lookups
  final Map<String, String> _senderNames = {};

  // Track last handled notification to prevent duplicate navigation
  String? _lastHandledNotificationId;

  // User Settings
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;

  final ValueNotifier<int> onlineOrderAlertCount = ValueNotifier<int>(0);
  final Set<String> _seenOnlineOrderAlertIds = {};
  final List<Map<String, dynamic>> _onlineOrderAlertRows = [];
  String? _onlineOrderTenantId;

  final _messageStreamController = StreamController<RemoteMessage>.broadcast();

  /// Stream of incoming messages (foreground & background)
  /// Listen to this to update UI badges or show in-app alerts
  Stream<RemoteMessage> get onMessageReceived =>
      _messageStreamController.stream;

  // Deprecated getter, keeping for backward compatibility if needed, map to new stream
  Stream<RemoteMessage> get messageStream => _messageStreamController.stream;

  /// Stream for notification taps that require navigation (deep links)
  final _navigationStreamController = StreamController<String>.broadcast();
  Stream<String> get onNotificationTap => _navigationStreamController.stream;

  String? get latestOnlineOrderAlertRoute {
    if (_onlineOrderAlertRows.isEmpty) return null;
    return _onlineOrderAlertRows.first['route']?.toString();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool('notification_sound') ?? true;
    _vibrationEnabled = prefs.getBool('notification_vibration') ?? true;
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

  Future<List<Map<String, dynamic>>> loadOnlineOrderAlerts(
    String tenantId,
  ) async {
    if (tenantId.trim().isEmpty) return const [];
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

  Future<void> playNotificationSound() async {
    if (!_soundEnabled) return;

    // Web: audio playback is often blocked by browser policy, and plugin
    // initialization can throw MissingPluginException depending on build.
    // Never let notification sounds crash app startup.
    if (kIsWeb) return;

    try {
      // Use a simple system beep or bundled sound
      // For cross-platform, we use a URL approach or asset
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!
          .play(AssetSource('sounds/notification.mp3'), volume: 1.0);
    } catch (e) {
      // On Web, browsers block audio if not triggered by user interaction.
      // We catch this to prevent the app from crashing.
      debugPrint('⚠️ Audio playback failed (likely browser policy): $e');
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

  Future<void> init() async {
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
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(chatChannel);
    }

    // Load user settings
    await _loadSettings();

    // Listen for auth changes to save token when user logs in
    _supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null && _fcmToken != null) {
        debugPrint('👤 [NotificationService] User logged in, saving token...');
        _saveTokenToDatabase(_fcmToken!);
      }
    });

    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await _initMobile();
    } else {
      // await _initDesktop();
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

      debugPrint('\n\n##################################################');
      debugPrint('### FCM TOKEN: $_fcmToken');
      debugPrint('##################################################\n\n');

      // 4. Save Token to Database
      if (_fcmToken != null) {
        await _saveTokenToDatabase(_fcmToken!);
      }

      // 5. Listen for token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _saveTokenToDatabase(newToken);
      });

      // 6. Listen for Foreground Messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        // Handle both notification+data and data-only messages
        final hasNotification = message.notification != null;
        final hasData = message.data.isNotEmpty;

        if (hasNotification) {
          debugPrint(
              'Message also contained a notification: ${message.notification}');
        }

        if (hasData || hasNotification) {
          // Notify in-app listeners (Snackbar)
          _messageStreamController.add(message);

          // Play sound and vibrate
          playNotificationSound();
          _triggerVibration();

          handleIncomingMessage(message);
        }
      });

      // 7. Handle notification tap when app is in background (not terminated)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 Notification tapped (background): ${message.data}');
        _handleNotificationTap(message);
      });

      // 8. Handle notification tap when app was terminated (cold start)
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          debugPrint('🔔 Notification tapped (cold start): ${message.data}');
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
    final messageId = message.messageId ?? message.data['conversation_id'];
    if (messageId != null && messageId == _lastHandledNotificationId) {
      debugPrint('🔔 Already handled notification $messageId, skipping');
      return;
    }
    _lastHandledNotificationId = messageId;

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
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 Web foreground message: ${message.data}');
      _messageStreamController.add(message);
      // The in-app notification overlay will handle display
    });

    // Listen for token refresh
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
    debugPrint('🔔 Setting up Realtime subscription for public:messages...');
    _supabase
        .channel('public:messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newMessage = payload.newRecord;
            final currentUserId = _supabase.auth.currentUser?.id;
            final senderId = newMessage['sender_id'];

            // Show notification only if:
            // 1. We are logged in
            // 2. The sender is NOT us (incoming message)
            if (currentUserId != null && senderId != currentUserId) {
              final content = newMessage['content'] ?? 'New Image';

              // Notify in-app listeners (Desktop)
              _messageStreamController.add(RemoteMessage(
                notification: RemoteNotification(
                  title: 'New Message',
                  body: content,
                ),
                data: newMessage,
              ));

              // Play sound and vibrate
              playNotificationSound();
              _triggerVibration();

              showLocalNotification('New Message', content);
            }
          },
        )
        .subscribe();
  }

  /// Handles an incoming FCM message and decides how to show it
  // Made public to be accessible from top-level background handler
  Future<void> handleIncomingMessage(RemoteMessage message) async {
    final data = message.data;
    final notification = message.notification;

    // Data-only messages have no notification field, so don't return early
    // if (notification == null) return;

    // Try to get conversation ID and Sender ID from data
    // Fallback: Use 'general' if missing
    final String conversationId =
        data['conversation_id'] ?? data['chat_id'] ?? 'general';
    final String senderId = data['sender_id'] ?? 'unknown_sender';

    debugPrint(
        '🔔 HandleIncomingMessage: conversationId=$conversationId, senderId=$senderId');
    debugPrint('🔔 Raw Data: $data');

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
      );
    }
  }

  Future<void> _showMessagingNotification({
    required String conversationId,
    String? conversationTitle,
    required List<Message> messages,
  }) async {
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
      color: const Color(0xFF000000),
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      macOS: const DarwinNotificationDetails(),
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
  Future<void> showLocalNotification(String title, String body,
      {int? notificationId}) async {
    if (kIsWeb) return;
    try {
      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'default_channel',
          'General Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
        macOS: DarwinNotificationDetails(),
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
