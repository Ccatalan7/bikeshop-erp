import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../modules/settings/models/barcode_scan_event.dart';

/// Service to receive barcode scans from remote devices (phones) via Supabase Realtime
class RemoteScannerService {
  static final RemoteScannerService _instance =
      RemoteScannerService._internal();
  factory RemoteScannerService() => _instance;
  RemoteScannerService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final _scanController = StreamController<BarcodeScanEvent>.broadcast();

  RealtimeChannel? _channel;
  String? _deviceId;
  bool _isListening = false;

  /// Stream of incoming barcode scans from remote devices
  Stream<BarcodeScanEvent> get scanStream => _scanController.stream;

  /// Whether the service is currently listening for remote scans
  bool get isListening => _isListening;

  /// Get or create a unique device ID for this ERP instance
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString('device_id', _deviceId!);
    }

    return _deviceId!;
  }

  /// Reset the device ID to force disconnection of all paired devices
  Future<void> resetDeviceId() async {
    await stopListening();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
    _deviceId = null;

    // Generate new ID immediately
    await getDeviceId();

    // Restart listening with new ID
    await startListening();
  }

  /// Start listening for remote scanner broadcasts
  Future<void> startListening() async {
    if (_isListening) {
      debugPrint('📱 RemoteScannerService: Already listening');
      return;
    }

    try {
      final deviceId = await getDeviceId();
      final channelName = 'barcode_scans:$deviceId';

      debugPrint(
          '📱 RemoteScannerService: Subscribing to channel: $channelName');

      _channel = _supabase.channel(channelName);

      _channel!.onBroadcast(
        event: 'scan',
        callback: (payload) {
          debugPrint('📱 RemoteScannerService: Received scan: $payload');
          try {
            // Filter out Config QR payloads accidentally scanned as products
            final rawPayload = payload.toString();
            if (rawPayload.contains('supabase.co') &&
                rawPayload.contains('deviceId')) {
              debugPrint('⚠️ RemoteScannerService: Ignored Config QR scan');
              return;
            }

            final scanEvent = BarcodeScanEvent.fromJson(payload);
            _scanController.add(scanEvent);
          } catch (e) {
            debugPrint('❌ RemoteScannerService: Error parsing scan event: $e');
          }
        },
      );

      _channel!.subscribe();
      _isListening = true;
      debugPrint('✅ RemoteScannerService: Listening on $channelName');
    } catch (e) {
      debugPrint('❌ RemoteScannerService: Error starting listener: $e');
      rethrow;
    }
  }

  /// Stop listening for remote scanner broadcasts
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _channel?.unsubscribe();
      _channel = null;
      _isListening = false;
      debugPrint('🛑 RemoteScannerService: Stopped listening');
    } catch (e) {
      debugPrint('❌ RemoteScannerService: Error stopping listener: $e');
    }
  }

  /// Send a scan event (for mobile scanner app)
  Future<void> sendScan(BarcodeScanEvent event, String targetDeviceId) async {
    try {
      final channelName = 'barcode_scans:$targetDeviceId';
      debugPrint('📤 RemoteScannerService: Sending scan to $channelName');

      final channel = _supabase.channel(channelName);
      channel.subscribe();

      await channel.sendBroadcastMessage(
        event: 'scan',
        payload: event.toJson(),
      );

      await channel.unsubscribe();
      debugPrint('✅ RemoteScannerService: Scan sent successfully');
    } catch (e) {
      debugPrint('❌ RemoteScannerService: Error sending scan: $e');
      rethrow;
    }
  }

  void dispose() {
    stopListening();
    _scanController.close();
  }
}
