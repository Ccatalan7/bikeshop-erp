import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'meta_pixel_bridge.dart';

class MetaCatalogEventItem {
  const MetaCatalogEventItem({
    required this.contentId,
    required this.quantity,
    required this.itemPrice,
  });

  final String contentId;
  final int quantity;
  final double itemPrice;

  Map<String, dynamic> toJson() => {
        'id': contentId,
        'quantity': quantity,
        'item_price': itemPrice,
      };
}

class MetaPixelService {
  MetaPixelService._();

  static final MetaPixelService instance = MetaPixelService._();

  String? _pixelId;
  bool _initialized = false;
  final List<_PendingMetaEvent> _pendingEvents = [];

  bool get isConfigured => _initialized;

  static String catalogContentId({
    String? sku,
    String? productId,
  }) {
    final normalizedSku = sku?.trim() ?? '';
    if (normalizedSku.isNotEmpty) return normalizedSku;
    return productId?.trim() ?? '';
  }

  void initialize(String? pixelId) {
    final normalized = pixelId?.trim() ?? '';
    if (normalized.isEmpty || !RegExp(r'^\d+$').hasMatch(normalized)) return;
    if (_initialized && _pixelId == normalized) return;

    _pixelId = normalized;
    _initialized = initializeMetaPixel(normalized);
    if (!_initialized) return;

    final pending = List<_PendingMetaEvent>.from(_pendingEvents);
    _pendingEvents.clear();
    for (final event in pending) {
      _send(event);
    }
  }

  void trackViewContent({
    required String contentId,
    required String contentName,
    required double value,
  }) {
    _track(
      'ViewContent',
      {
        'content_ids': [contentId],
        'content_name': contentName,
        'content_type': 'product',
        'value': value,
        'currency': 'CLP',
      },
    );
  }

  void trackAddToCart({
    required String contentId,
    required String contentName,
    required double itemPrice,
    required int quantity,
  }) {
    _track(
      'AddToCart',
      {
        'content_ids': [contentId],
        'content_name': contentName,
        'content_type': 'product',
        'contents': [
          MetaCatalogEventItem(
            contentId: contentId,
            quantity: quantity,
            itemPrice: itemPrice,
          ).toJson(),
        ],
        'value': itemPrice * quantity,
        'currency': 'CLP',
      },
    );
  }

  void trackInitiateCheckout({
    required List<MetaCatalogEventItem> items,
    required double value,
  }) {
    if (items.isEmpty) return;
    _track(
      'InitiateCheckout',
      {
        'content_ids': items.map((item) => item.contentId).toList(),
        'content_type': 'product',
        'contents': items.map((item) => item.toJson()).toList(),
        'num_items': items.fold<int>(
          0,
          (total, item) => total + item.quantity,
        ),
        'value': value,
        'currency': 'CLP',
      },
    );
  }

  void trackPurchase({
    required String orderId,
    required List<MetaCatalogEventItem> items,
    required double value,
  }) {
    if (items.isEmpty) return;
    _track(
      'Purchase',
      {
        'content_ids': items.map((item) => item.contentId).toList(),
        'content_type': 'product',
        'contents': items.map((item) => item.toJson()).toList(),
        'num_items': items.fold<int>(
          0,
          (total, item) => total + item.quantity,
        ),
        'value': value,
        'currency': 'CLP',
      },
      eventId: 'purchase_$orderId',
    );
  }

  void _track(
    String eventName,
    Map<String, dynamic> payload, {
    String? eventId,
  }) {
    final event = _PendingMetaEvent(
      name: eventName,
      payloadJson: jsonEncode(payload),
      eventId: eventId,
    );
    if (!_initialized) {
      if (_pendingEvents.length >= 50) _pendingEvents.removeAt(0);
      _pendingEvents.add(event);
      return;
    }
    _send(event);
  }

  void _send(_PendingMetaEvent event) {
    final sent = trackMetaPixelEvent(
      event.name,
      event.payloadJson,
      eventId: event.eventId,
    );
    if (!sent && kDebugMode) {
      debugPrint('[MetaPixel] Could not send ${event.name}.');
    }
  }
}

class _PendingMetaEvent {
  const _PendingMetaEvent({
    required this.name,
    required this.payloadJson,
    this.eventId,
  });

  final String name;
  final String payloadJson;
  final String? eventId;
}
