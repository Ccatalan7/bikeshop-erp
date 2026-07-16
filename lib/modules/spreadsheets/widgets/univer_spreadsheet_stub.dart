import 'package:flutter/material.dart';

const _unsupportedMessage =
    'UniverSpreadsheetView is only supported in Flutter web builds.';

abstract interface class _UniverSpreadsheetControllerDelegate {
  Future<Map<String, dynamic>?> requestSnapshot();

  void focus();
}

/// Imperative access to a mounted [UniverSpreadsheetView].
class UniverSpreadsheetController {
  _UniverSpreadsheetControllerDelegate? _delegate;

  /// Requests the current Univer workbook snapshot.
  ///
  /// Returns `null` when no view is attached or on unsupported platforms.
  Future<Map<String, dynamic>?> requestSnapshot() {
    return _delegate?.requestSnapshot() ??
        Future<Map<String, dynamic>?>.value();
  }

  /// Gives keyboard focus to the mounted Univer workbook, when supported.
  void focus() => _delegate?.focus();

  void _attach(_UniverSpreadsheetControllerDelegate delegate) {
    _delegate = delegate;
  }

  void _detach(_UniverSpreadsheetControllerDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
    }
  }
}

/// Non-web placeholder for the browser-only Univer spreadsheet surface.
class UniverSpreadsheetView extends StatefulWidget {
  const UniverSpreadsheetView({
    super.key,
    required this.initialSnapshot,
    this.onSnapshotChanged,
    this.onReady,
    this.onError,
    this.controller,
  });

  final Map<String, dynamic> initialSnapshot;
  final ValueChanged<Map<String, dynamic>>? onSnapshotChanged;
  final VoidCallback? onReady;
  final ValueChanged<String>? onError;
  final UniverSpreadsheetController? controller;

  @override
  State<UniverSpreadsheetView> createState() => _UniverSpreadsheetViewState();
}

class _UniverSpreadsheetViewState extends State<UniverSpreadsheetView>
    implements _UniverSpreadsheetControllerDelegate {
  bool _reportedUnsupported = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reportUnsupported();
      }
    });
  }

  @override
  void didUpdateWidget(covariant UniverSpreadsheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  Future<Map<String, dynamic>?> requestSnapshot() async {
    _reportUnsupported();
    return null;
  }

  @override
  void focus() => _reportUnsupported();

  void _reportUnsupported() {
    if (_reportedUnsupported) return;
    _reportedUnsupported = true;
    widget.onError?.call(_unsupportedMessage);
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: _unsupportedMessage,
      child: ColoredBox(
        color: colorScheme.surfaceContainerLowest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _unsupportedMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
