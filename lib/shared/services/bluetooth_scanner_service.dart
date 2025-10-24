import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service to handle Bluetooth barcode scanner connections
/// Supports HID-compatible Bluetooth barcode scanners
class BluetoothScannerService extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _dataSubscription;
  
  final StreamController<String> _barcodeController = StreamController<String>.broadcast();
  Stream<String> get barcodeStream => _barcodeController.stream;
  
  bool _isScanning = false;
  bool get isScanning => _isScanning;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  String? _connectedDeviceName;
  String? get connectedDeviceName => _connectedDeviceName;
  
  List<BluetoothDevice> _availableDevices = [];
  List<BluetoothDevice> get availableDevices => _availableDevices;
  
  StringBuffer _dataBuffer = StringBuffer();

  /// Check if permissions are granted
  Future<bool> hasPermissions() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final bluetoothScan = await Permission.bluetoothScan.status;
        final bluetoothConnect = await Permission.bluetoothConnect.status;
        final location = await Permission.location.status;
        
        return bluetoothScan.isGranted && 
               bluetoothConnect.isGranted && 
               location.isGranted;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final bluetooth = await Permission.bluetooth.status;
        return bluetooth.isGranted;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('Error checking permissions: $e');
      return false;
    }
  }

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();
        
        if (kDebugMode) {
          print('Permission statuses:');
          statuses.forEach((permission, status) {
            print('  $permission: $status');
          });
        }
        
        return statuses.values.every((status) => status.isGranted);
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final status = await Permission.bluetooth.request();
        return status.isGranted;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('Error requesting permissions: $e');
      return false;
    }
  }

  /// Check if any permission is permanently denied
  Future<bool> hasPermissionsDenied() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final bluetoothScan = await Permission.bluetoothScan.status;
        final bluetoothConnect = await Permission.bluetoothConnect.status;
        final location = await Permission.location.status;
        
        return bluetoothScan.isPermanentlyDenied || 
               bluetoothConnect.isPermanentlyDenied || 
               location.isPermanentlyDenied;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final bluetooth = await Permission.bluetooth.status;
        return bluetooth.isPermanentlyDenied;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('Error checking denied permissions: $e');
      return false;
    }
  }

  /// Check if Bluetooth is supported and enabled
  Future<bool> isBluetoothAvailable() async {
    try {
      if (await FlutterBluePlus.isSupported == false) {
        return false;
      }
      
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      if (kDebugMode) print('Error checking Bluetooth availability: $e');
      return false;
    }
  }

  /// Turn on Bluetooth (Android only)
  Future<void> turnOnBluetooth() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await FlutterBluePlus.turnOn();
      }
    } catch (e) {
      if (kDebugMode) print('Error turning on Bluetooth: $e');
    }
  }

  /// Scan for available Bluetooth devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;
    
    _isScanning = true;
    _availableDevices.clear();
    notifyListeners();

    try {
      // Listen to scan results
      final subscription = FlutterBluePlus.scanResults.listen((results) {
        _availableDevices = results
            .map((r) => r.device)
            .where((device) => device.platformName.isNotEmpty)
            .toList();
        notifyListeners();
      });

      // Start scanning
      await FlutterBluePlus.startScan(timeout: timeout);
      
      // Wait for timeout
      await Future.delayed(timeout);
      
      // Stop scanning
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
      
      _isScanning = false;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error scanning: $e');
      _isScanning = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Connect to a Bluetooth device
  Future<void> connect(BluetoothDevice device) async {
    try {
      // Disconnect any existing connection
      if (_connectedDevice != null) {
        await disconnect();
      }

      // Connect to device
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      _connectedDeviceName = device.platformName;
      _isConnected = true;
      notifyListeners();

      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      
      // Find characteristics that support notifications (typical for barcode scanners)
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.notify) {
            // Subscribe to notifications
            await characteristic.setNotifyValue(true);
            
            _dataSubscription = characteristic.lastValueStream.listen((value) {
              _processIncomingData(value);
            });
          }
        }
      }

      if (kDebugMode) print('Connected to ${device.platformName}');
    } catch (e) {
      if (kDebugMode) print('Error connecting to device: $e');
      _isConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Process incoming data from barcode scanner
  void _processIncomingData(List<int> data) {
    try {
      String text = String.fromCharCodes(data);
      
      // Accumulate data in buffer
      _dataBuffer.write(text);
      
      // Check for newline/carriage return (end of barcode)
      String bufferContent = _dataBuffer.toString();
      if (bufferContent.contains('\n') || bufferContent.contains('\r')) {
        // Extract barcode (remove control characters)
        String barcode = bufferContent
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .trim();
        
        if (barcode.isNotEmpty) {
          // Emit barcode
          _barcodeController.add(barcode);
          if (kDebugMode) print('Barcode scanned: $barcode');
        }
        
        // Clear buffer
        _dataBuffer.clear();
      }
    } catch (e) {
      if (kDebugMode) print('Error processing data: $e');
    }
  }

  /// Handle device disconnection
  void _handleDisconnection() {
    _isConnected = false;
    _connectedDeviceName = null;
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _connectedDevice = null;
    notifyListeners();
    
    if (kDebugMode) print('Device disconnected');
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    try {
      await _dataSubscription?.cancel();
      await _connectionSubscription?.cancel();
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      
      _handleDisconnection();
    } catch (e) {
      if (kDebugMode) print('Error disconnecting: $e');
    }
  }

  /// Get list of bonded/paired devices (Android only)
  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await FlutterBluePlus.bondedDevices;
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('Error getting bonded devices: $e');
      return [];
    }
  }

  @override
  void dispose() {
    disconnect();
    _barcodeController.close();
    super.dispose();
  }
}
