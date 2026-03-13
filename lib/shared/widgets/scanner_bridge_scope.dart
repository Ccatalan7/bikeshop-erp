import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
    RawKeyboard.instance.addListener(_handleRawKeyEvent);
  }

  void _initialize() {
    if (_isPublicStoreHost()) {
      return;
    }

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

  bool _isPublicStoreHost() {
    if (!kIsWeb) return false;
    final host = Uri.base.host.toLowerCase();
    return host == 'vinabike-store.web.app' ||
        host == 'vinabike-store.firebaseapp.com' ||
        host == 'vinabike.cl' ||
        host == 'www.vinabike.cl';
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(_handleRawKeyEvent);
    _remoteSubscription?.cancel();
    super.dispose();
  }

  void _handleRawKeyEvent(RawKeyEvent event) {
    if (_isPublicStoreHost() || !mounted) return;

    // 🛡️ PREVENT INTERFERENCE:
    // Do not process unrelated key events if the user is typing in a TextField/TextFormField.
    // This prevents the scanner service from interpreting fast typing as barcode scans.
    final focus = FocusManager.instance.primaryFocus;

    // Check if the focused element is a text input
    // Since EditableText wraps content in a Focus widget, we must check ancestors.
    bool isTextInput = false;
    if (focus != null && focus.context != null && focus.context!.mounted) {
      try {
        if (focus.context!.widget is EditableText) {
          isTextInput = true;
        } else {
          // Look up the tree for EditableText
          // SAFETY: Wrap in try-catch since context may be deactivated during rapid rebuilds
          final editableAncestor =
              focus.context!.findAncestorWidgetOfExactType<EditableText>();
          isTextInput = editableAncestor != null;
        }
      } catch (e) {
        // Context was deactivated during lookup - ignore this key event
        return;
      }
    }

    if (isTextInput) {
      return; // Allow the keys to be handled naturally by the text field
    }

    context.read<BarcodeScannerService>().processKeyEvent(event);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
