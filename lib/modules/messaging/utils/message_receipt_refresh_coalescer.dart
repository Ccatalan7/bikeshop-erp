import 'dart:async';

typedef MessageReceiptRefreshBatch = Map<String, Set<String>>;
typedef MessageReceiptRefreshCallback = Future<void> Function(
  MessageReceiptRefreshBatch batch,
);

/// Debounces high-frequency provider receipt updates into one targeted read.
///
/// The outer key is the conversation and each value contains only the message
/// ids whose provider evidence changed. Updates received while a read is in
/// flight are retained for the next batch instead of being lost.
class MessageReceiptRefreshCoalescer {
  final Duration delay;
  final MessageReceiptRefreshCallback onRefresh;

  final Map<String, Set<String>> _pending = {};
  Timer? _timer;
  bool _refreshing = false;
  bool _disposed = false;

  MessageReceiptRefreshCoalescer({
    required this.onRefresh,
    this.delay = const Duration(milliseconds: 90),
  });

  void schedule({
    required String conversationId,
    required String messageId,
  }) {
    if (_disposed || conversationId.isEmpty || messageId.isEmpty) return;
    _pending.putIfAbsent(conversationId, () => <String>{}).add(messageId);
    if (_refreshing) return;
    _timer?.cancel();
    _timer = Timer(delay, _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    if (_disposed || _refreshing || _pending.isEmpty) return;

    final batch = <String, Set<String>>{
      for (final entry in _pending.entries)
        entry.key: Set<String>.unmodifiable(entry.value),
    };
    _pending.clear();
    _refreshing = true;
    try {
      await onRefresh(Map<String, Set<String>>.unmodifiable(batch));
    } finally {
      _refreshing = false;
      if (!_disposed && _pending.isNotEmpty) {
        _timer?.cancel();
        _timer = Timer(delay, _flush);
      }
    }
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
