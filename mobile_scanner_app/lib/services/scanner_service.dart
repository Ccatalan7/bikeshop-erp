import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/barcode_scan_event.dart';

class ScannerService extends ChangeNotifier {
  SupabaseClient? _supabase;

  String? _pairedDeviceId;
  String? _myDeviceId;
  String? _deviceName;
  bool _isLoading = true;
  String? _targetModule;
  final List<ScanHistoryItem> _scanHistory = [];

  String? get pairedDeviceId => _pairedDeviceId;
  String? get myDeviceId => _myDeviceId;
  String? get deviceName => _deviceName;
  bool get isLoading => _isLoading;
  bool get isConfigured => _supabase != null;
  String? get targetModule => _targetModule;
  List<ScanHistoryItem> get scanHistory => _scanHistory;
  bool get isPaired => _pairedDeviceId != null;

  /// Initialize service and check for saved configuration
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load saved credentials
      final savedUrl = prefs.getString('supabase_url');
      final savedKey = prefs.getString('supabase_key');

      if (savedUrl != null && savedKey != null) {
        _initSupabase(savedUrl, savedKey);
        debugPrint('✅ Supabase initialized from storage');
      } else {
        debugPrint('⚠️ No Supabase credentials found');
      }

      // Load device info
      await loadPairedDevice();
    } catch (e) {
      debugPrint('❌ Error initializing scanner service: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Configure Supabase credentials
  Future<void> configure(String url, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('supabase_url', url);
      await prefs.setString('supabase_key', key);

      _initSupabase(url, key);
      notifyListeners();
      debugPrint('✅ Supabase configured successfully');
    } catch (e) {
      debugPrint('❌ Error configuring Supabase: $e');
      rethrow;
    }
  }

  void _initSupabase(String url, String key) {
    // Create a new client instance
    _supabase = SupabaseClient(url, key);
  }

  /// Load paired device from storage
  Future<void> loadPairedDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pairedDeviceId = prefs.getString('paired_device_id');
      _myDeviceId = prefs.getString('my_device_id');
      _deviceName = prefs.getString('device_name');

      if (_myDeviceId == null) {
        _myDeviceId = const Uuid().v4();
        await prefs.setString('my_device_id', _myDeviceId!);
      }

      if (_deviceName == null) {
        _deviceName = Platform.isAndroid ? 'Android Scanner' : 'iOS Scanner';
        await prefs.setString('device_name', _deviceName!);
      }

      debugPrint('📱 Paired device: $_pairedDeviceId');
    } catch (e) {
      debugPrint('❌ Error loading paired device: $e');
    }
  }

  /// Pair with a target device using its ID
  Future<void> pairDevice(String targetDeviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('paired_device_id', targetDeviceId);
      _pairedDeviceId = targetDeviceId;

      debugPrint('✅ Paired with device: $targetDeviceId');
      debugPrint('✅ Paired with device: $targetDeviceId');
      notifyListeners();

      // Send handshake ping to wake up ERP (after a brief delay to ensure connection)
      Future.delayed(const Duration(milliseconds: 1000), () {
        sendScan('📶 Dispositivo Conectado');
      });
    } catch (e) {
      debugPrint('❌ Error pairing device: $e');
      rethrow;
    }
  }

  /// Unpair from current device
  Future<void> unpairDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('paired_device_id');
      _pairedDeviceId = null;
      _scanHistory.clear();

      debugPrint('🔓 Unpaired device');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error unpairing device: $e');
      rethrow;
    }
  }

  /// Set target module for scans
  void setTargetModule(String? module) {
    _targetModule = module;
    notifyListeners();
  }

  /// Send a barcode scan to the paired device
  Future<void> sendScan(String barcode) async {
    if (_supabase == null) {
      throw Exception('Not configured. Scan setup QR code first.');
    }
    if (_pairedDeviceId == null || _myDeviceId == null) {
      throw Exception('No paired device');
    }

    try {
      final event = BarcodeScanEvent(
        barcode: barcode,
        deviceId: _myDeviceId!,
        deviceName: _deviceName ?? 'Mobile Scanner',
        timestamp: DateTime.now(),
        targetModule: _targetModule,
      );

      final channelName = 'barcode_scans:$_pairedDeviceId';
      debugPrint('📤 Sending scan to $channelName: $barcode');

      final channel = _supabase!.channel(channelName);
      await channel.subscribe();

      await channel.sendBroadcastMessage(
        event: 'scan',
        payload: event.toJson(),
      );

      await channel.unsubscribe();

      // Add to history
      _scanHistory.insert(
        0,
        ScanHistoryItem(
          barcode: barcode,
          timestamp: DateTime.now(),
          targetModule: _targetModule,
          sent: true,
        ),
      );

      if (_scanHistory.length > 50) {
        _scanHistory.removeLast();
      }

      // Vibrate on success
      HapticFeedback.mediumImpact();

      debugPrint('✅ Scan sent successfully');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error sending scan: $e');

      // Add to history as failed
      _scanHistory.insert(
        0,
        ScanHistoryItem(
          barcode: barcode,
          timestamp: DateTime.now(),
          targetModule: _targetModule,
          sent: false,
        ),
      );
      notifyListeners();

      rethrow;
    }
  }

  /// Clear scan history
  void clearHistory() {
    _scanHistory.clear();
    notifyListeners();
  }
}
