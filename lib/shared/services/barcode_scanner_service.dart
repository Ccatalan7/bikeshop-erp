import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Unified barcode scanner service
/// Supports both USB/HID keyboard scanners (desktop/web) and Bluetooth scanners (mobile)
class BarcodeScannerService extends ChangeNotifier {
  final StreamController<String> _barcodeController = StreamController<String>.broadcast();
  Stream<String> get barcodeStream => _barcodeController.stream;
  
  StringBuffer _scanBuffer = StringBuffer();
  Timer? _scanTimer;
  DateTime? _lastKeyTime;
  
  bool _isListening = false;
  bool get isListening => _isListening;
  
  // Configuration for keyboard scanner detection
  static const Duration _scanTimeout = Duration(milliseconds: 100);
  static const int _minBarcodeLength = 3;
  
  /// Start listening for barcode input (keyboard mode)
  void startListening() {
    if (_isListening) return;
    _isListening = true;
    notifyListeners();
    
    if (kDebugMode) print('✅ Barcode scanner listening started (Keyboard mode)');
  }
  
  /// Stop listening for barcode input
  void stopListening() {
    if (!_isListening) return;
    _isListening = false;
    _scanBuffer.clear();
    _scanTimer?.cancel();
    notifyListeners();
    
    if (kDebugMode) print('🛑 Barcode scanner listening stopped');
  }
  
  /// Process keyboard input - should be called from a RawKeyboardListener
  void processKeyEvent(RawKeyEvent event) {
    if (!_isListening) return;
    if (event is! RawKeyDownEvent) return;
    
    final now = DateTime.now();
    final key = event.logicalKey;
    
    // Check if this is part of a rapid sequence (typical of scanner input)
    if (_lastKeyTime != null) {
      final timeDiff = now.difference(_lastKeyTime!);
      
      // If too much time has passed, reset the buffer (user typing, not scanner)
      if (timeDiff > _scanTimeout) {
        _scanBuffer.clear();
      }
    }
    
    _lastKeyTime = now;
    
    // Cancel existing timer
    _scanTimer?.cancel();
    
    // Handle Enter/Return key (end of scan)
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _processScan();
      return;
    }
    
    // Add character to buffer
    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _scanBuffer.write(char);
      
      // Set timer to auto-process if no more keys arrive
      _scanTimer = Timer(_scanTimeout, _processScan);
    }
  }
  
  /// Process the accumulated scan buffer
  void _processScan() {
    _scanTimer?.cancel();
    
    final barcode = _scanBuffer.toString().trim();
    _scanBuffer.clear();
    
    // Validate barcode
    if (barcode.length >= _minBarcodeLength) {
      _barcodeController.add(barcode);
      if (kDebugMode) print('📦 Barcode scanned: $barcode');
    }
  }
  
  /// Manually add a barcode (for testing or manual entry)
  void addBarcode(String barcode) {
    if (barcode.trim().isNotEmpty) {
      _barcodeController.add(barcode.trim());
    }
  }
  
  @override
  void dispose() {
    stopListening();
    _barcodeController.close();
    super.dispose();
  }
}
