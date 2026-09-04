import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/chat_media_cache.dart';

/// A chat image drawn from the device: memory, then disk, then — only when
/// this device has never seen it — one download through [resolveUrl].
///
/// The box has a fixed size so the timeline never re-measures when the
/// picture arrives (that jump is what made the list "vibrate"). A picture the
/// operator just sent comes from the composer's own bytes, so its bubble is
/// full the moment it appears.
class ChatMediaThumbnail extends StatefulWidget {
  const ChatMediaThumbnail({
    super.key,
    required this.message,
    required this.resolveUrl,
    this.width = 220,
    this.height = 220,
    this.fit = BoxFit.cover,
    this.borderRadius = 8,
    this.placeholderColor,
    this.unavailable,
  });

  final Message message;

  /// Mints an authorised URL for the bytes. Called once per device per
  /// attachment, never while the cache already holds them.
  final Future<String?> Function() resolveUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;
  final Color? placeholderColor;

  /// What to show when the bytes cannot be obtained; tapping it retries.
  final Widget Function(VoidCallback retry)? unavailable;

  @override
  State<ChatMediaThumbnail> createState() => _ChatMediaThumbnailState();
}

class _ChatMediaThumbnailState extends State<ChatMediaThumbnail> {
  final ChatMediaCache _cache = ChatMediaCache.instance;
  String? _key;
  Uint8List? _bytes;
  Future<Uint8List?>? _pending;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant ChatMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = ChatMediaCache.keyFor(widget.message);
    if (nextKey != _key) _start();
  }

  void _start() {
    final key = ChatMediaCache.keyFor(widget.message);
    _key = key;
    _failed = false;
    _pending = null;
    if (key == null) {
      _bytes = null;
      return;
    }
    // Synchronous hits paint on the first frame; nothing to await.
    final immediate = _cache.peek(key) ??
        _peekLocal(ChatMediaCache.localKeyFor(widget.message));
    if (immediate != null) {
      _bytes = immediate;
      return;
    }
    _bytes = null;
    _load(key);
  }

  Uint8List? _peekLocal(String? localKey) {
    if (localKey == null) return null;
    return _cache.peek(localKey);
  }

  void _load(String key) {
    final localKey = ChatMediaCache.localKeyFor(widget.message);
    final future = () async {
      final fromLocal = localKey == null ? null : await _cache.read(localKey);
      if (fromLocal != null) {
        // The server row arrived for a file this device sent: keep one
        // durable copy under the server identity.
        await _cache.put(key, fromLocal, fileExtension: _extension());
        return fromLocal;
      }
      return _cache.fetch(
        key,
        resolveUrl: widget.resolveUrl,
        fileExtension: _extension(),
      );
    }();
    _pending = future;
    future.then((bytes) {
      if (!mounted || !identical(_pending, future)) return;
      setState(() {
        _bytes = bytes;
        _failed = bytes == null;
        _pending = null;
      });
    });
  }

  String? _extension() {
    final value = widget.message.metadata['extension']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  void _retry() {
    final key = _key;
    if (key == null) return;
    setState(() {
      _failed = false;
      _bytes = null;
    });
    _load(key);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final key = _key;
    if (bytes != null && key != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image(
          image: _cache.providerFor(key, bytes),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _unavailable(context),
        ),
      );
    }
    if (_failed || key == null) return _unavailable(context);
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.placeholderColor ??
            Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context) {
    final custom = widget.unavailable;
    if (custom != null) return custom(_retry);
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _retry,
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: Icon(
          Icons.broken_image_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
