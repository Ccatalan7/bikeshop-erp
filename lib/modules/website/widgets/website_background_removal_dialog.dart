import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/website_editor_capability.dart';
import '../services/website_background_removal_processor.dart';
import '../services/website_background_removal_service.dart';
import '../services/website_service.dart';

class WebsiteBackgroundRemovalSelection {
  final Uint8List? pngBytes;
  final String? imageUrl;
  final String method;

  const WebsiteBackgroundRemovalSelection.local(this.pngBytes)
      : imageUrl = null,
        method = 'local';

  const WebsiteBackgroundRemovalSelection.smart(this.imageUrl)
      : pngBytes = null,
        method = 'remove-bg';
}

Future<WebsiteBackgroundRemovalSelection?> showWebsiteBackgroundRemovalDialog({
  required BuildContext context,
  required String imageUrl,
  String? tenantId,
  WebsiteBackgroundRemovalService? service,
  WebsiteEditorRemoteWriteAuthority? Function()? remoteWriteAuthority,
}) {
  return showDialog<WebsiteBackgroundRemovalSelection>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WebsiteBackgroundRemovalDialog(
      imageUrl: imageUrl,
      tenantId: tenantId,
      service: service,
      remoteWriteAuthority: remoteWriteAuthority,
    ),
  );
}

class WebsiteBackgroundRemovalDialog extends StatefulWidget {
  final String imageUrl;
  final String? tenantId;
  final WebsiteBackgroundRemovalService? service;
  final WebsiteEditorRemoteWriteAuthority? Function()? remoteWriteAuthority;

  const WebsiteBackgroundRemovalDialog({
    super.key,
    required this.imageUrl,
    this.tenantId,
    this.service,
    this.remoteWriteAuthority,
  });

  @override
  State<WebsiteBackgroundRemovalDialog> createState() =>
      _WebsiteBackgroundRemovalDialogState();
}

class _WebsiteBackgroundRemovalDialogState
    extends State<WebsiteBackgroundRemovalDialog> {
  late final WebsiteBackgroundRemovalService _service;
  Uint8List? _originalBytes;
  WebsiteBackgroundRemovalResult? _localResult;
  String? _smartResultUrl;
  String? _error;
  int _tolerance = 34;
  int _requestVersion = 0;
  bool _loading = true;
  bool _smartLoading = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WebsiteBackgroundRemovalService();
    _loadAndProcess();
  }

  Future<void> _loadAndProcess() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _originalBytes = await _service.downloadImage(widget.imageUrl);
      await _processLocal();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _processLocal() async {
    final bytes = _originalBytes;
    if (bytes == null) return;
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
      _smartResultUrl = null;
    });
    try {
      final result = await _service.removeUniformBackground(
        bytes,
        tolerance: _tolerance,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _localResult = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _processSmart() async {
    setState(() {
      _smartLoading = true;
      _error = null;
    });
    try {
      final authority = widget.remoteWriteAuthority?.call();
      if (widget.remoteWriteAuthority != null && authority == null) {
        throw const WebsiteEditorWriteSupersededException(
          'La sesión del editor cambió antes de quitar el fondo.',
        );
      }
      final writeGuard = authority?.claimForWrite();
      final result = await _service.removeSmartBackground(
        imageUrl: widget.imageUrl,
        tenantId: authority?.tenantId ?? widget.tenantId,
        writeGuard: writeGuard,
      );
      authority?.ensureCurrent();
      if (!mounted) return;
      setState(() {
        _smartResultUrl = result.imageUrl;
        _smartLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _smartLoading = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('FormatException: ', '');
  }

  void _apply() {
    final smartUrl = _smartResultUrl;
    if (smartUrl != null) {
      Navigator.of(context).pop(
        WebsiteBackgroundRemovalSelection.smart(smartUrl),
      );
      return;
    }
    final result = _localResult;
    if (result != null && result.isUseful) {
      Navigator.of(context).pop(
        WebsiteBackgroundRemovalSelection.local(result.pngBytes),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = _localResult;
    final canApply = _smartResultUrl != null || (local?.isUseful ?? false);
    final localConfidence = local?.isLikelyUniformBackground == true;
    final alreadyTransparent = local?.alreadyTransparent == true;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high_rounded, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quitar fondo',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'El original se conserva. La versión web se optimiza automáticamente.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: _smartLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 620;
                        final original = _PreviewPanel(
                          label: 'Original',
                          child: Image.network(
                            widget.imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const _PreviewError(),
                          ),
                        );
                        final result = _PreviewPanel(
                          label: _smartResultUrl != null
                              ? 'Resultado inteligente'
                              : alreadyTransparent
                                  ? 'Ya transparente'
                                  : 'Resultado gratuito',
                          checkerboard: true,
                          child: _loading
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : _smartResultUrl != null
                                  ? Image.network(
                                      _smartResultUrl!,
                                      fit: BoxFit.contain,
                                    )
                                  : local != null
                                      ? Image.memory(
                                          local.pngBytes,
                                          fit: BoxFit.contain,
                                          gaplessPlayback: true,
                                        )
                                      : const _PreviewError(),
                        );
                        if (compact) {
                          return Column(
                            children: [
                              original,
                              const SizedBox(height: 12),
                              result,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: original),
                            const SizedBox(width: 12),
                            Expanded(child: result),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(
                          localConfidence
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                          size: 18,
                          color: localConfidence
                              ? Colors.green.shade700
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            alreadyTransparent
                                ? 'Esta imagen ya tiene fondo transparente. No hace falta crear otra copia.'
                                : localConfidence
                                    ? 'Fondo uniforme detectado. Este resultado no consume API.'
                                    : 'Ajusta la tolerancia. Para fondos complejos puedes usar el modo inteligente.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!alreadyTransparent)
                      Row(
                        children: [
                          const SizedBox(
                            width: 86,
                            child: Text(
                              'Tolerancia',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _tolerance.toDouble(),
                              min: 8,
                              max: 80,
                              divisions: 36,
                              label: '$_tolerance',
                              onChanged: _loading || _smartLoading
                                  ? null
                                  : (value) => setState(
                                        () => _tolerance = value.round(),
                                      ),
                              onChangeEnd: _loading || _smartLoading
                                  ? null
                                  : (_) => _processLocal(),
                            ),
                          ),
                          SizedBox(
                            width: 34,
                            child: Text(
                              '$_tolerance',
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('background_removal_smart'),
                      onPressed: _loading || _smartLoading || alreadyTransparent
                          ? null
                          : _processSmart,
                      icon: _smartLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Usar modo inteligente'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Solo este modo consume un crédito del proveedor.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _smartLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('background_removal_apply'),
                    onPressed:
                        canApply && !_loading && !_smartLoading ? _apply : null,
                    child: const Text('Aplicar versión'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final String label;
  final Widget child;
  final bool checkerboard;

  const _PreviewPanel({
    required this.label,
    required this.child,
    this.checkerboard = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          height: 280,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (checkerboard)
                const CustomPaint(painter: _CheckerboardPainter()),
              Padding(padding: const EdgeInsets.all(10), child: child),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.black38, size: 34),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 14.0;
    final light = Paint()..color = const Color(0xFFF7F7F7);
    final dark = Paint()..color = const Color(0xFFE5E5E5);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final alternate = ((x / cell).floor() + (y / cell).floor()).isOdd;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          alternate ? dark : light,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) => false;
}
