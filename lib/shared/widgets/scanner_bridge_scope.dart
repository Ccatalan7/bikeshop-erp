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
///
/// IMPORTANT:
/// Remote scans are enabled globally, but keyboard-wedge scans are not armed
/// globally. A screen must explicitly call BarcodeScannerService.startListening()
/// if it wants raw keyboard input to be interpreted as scanner input.
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

    final remoteService = context.read<RemoteScannerService>();

    // Keep remote/mobile scanning available across the app.
    remoteService.startListening();

    // Bridge remote scans into the unified barcode stream.
    _remoteSubscription = remoteService.scanStream.listen((event) {
      context.read<BarcodeScannerService>().addBarcode(event.barcode);
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
