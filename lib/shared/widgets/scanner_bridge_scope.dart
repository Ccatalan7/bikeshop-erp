import 'dart:async';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../services/barcode_scanner_service.dart';
import '../services/remote_scanner_service.dart';

/// A scope that unifies Physical and Remote scanner inputs.
/// 1. Listens to RawKeyboard events for physical USB scanners.
/// 2. Bridges RemoteScannerService events into BarcodeScannerService.
/// 3. Provides a unified stream via BarcodeScannerService.
class ScannerBridgeScope extends StatefulWidget {
  final Widget child;

  const ScannerBridgeScope({super.key, required this.child});

  @override
  State<ScannerBridgeScope> createState() => _ScannerBridgeScopeState();
}

class _ScannerBridgeScopeState extends State<ScannerBridgeScope> {
  StreamSubscription? _remoteSubscription;
  final FocusNode _focusNode = FocusNode(); // For keyboard listener

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  void _initialize() {
    final barcodeService = context.read<BarcodeScannerService>();
    final remoteService = context.read<RemoteScannerService>();

    // 1. Enable Barcode Service (Keyboard logic)
    barcodeService.startListening();

    // 2. Enable Remote Service (Supabase Realtime)
    remoteService.startListening();

    // 3. Bridge Remote -> Barcode
    _remoteSubscription = remoteService.scanStream.listen((event) {
      // Inject remote scan as if it were a physical scan (final result)
      barcodeService.addBarcode(event.barcode);
    });
  }

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: (event) {
        context.read<BarcodeScannerService>().processKeyEvent(event);
      },
      child: widget.child,
    );
  }
}
