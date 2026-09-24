import 'package:flutter/foundation.dart';

import 'ga4_bridge.dart';

/// Un producto en un evento de comercio de GA4.
class Ga4Item {
  const Ga4Item({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
  });

  final String id;
  final String name;
  final double price;
  final int quantity;

  Map<String, Object?> toJson() => {
        'item_id': id,
        'item_name': name,
        'price': price,
        'quantity': quantity,
      };
}

/// Eventos de la tienda para Google Analytics 4.
///
/// Hasta el 2026-09-23 la tienda sólo mandaba a GA4 los eventos automáticos:
/// no se podía saber cuántas visitas veían un producto, lo agregaban al
/// carrito, pagaban o escribían por WhatsApp. Se disparan en los mismos
/// puntos que el píxel de Meta, con los nombres de comercio de GA4.
class Ga4CommerceEvents {
  Ga4CommerceEvents._();

  static final Ga4CommerceEvents instance = Ga4CommerceEvents._();

  /// Reemplazable en pruebas para ver qué se envía.
  @visibleForTesting
  bool Function(String eventName, Map<String, Object?> params) send =
      trackGa4Event;

  void viewItem(Ga4Item item) {
    _track('view_item', {
      'currency': 'CLP',
      'value': item.price,
      'items': [item.toJson()],
    });
  }

  void addToCart(Ga4Item item) {
    _track('add_to_cart', {
      'currency': 'CLP',
      'value': item.price * item.quantity,
      'items': [item.toJson()],
    });
  }

  void beginCheckout(List<Ga4Item> items, double value) {
    if (items.isEmpty) return;
    _track('begin_checkout', {
      'currency': 'CLP',
      'value': value,
      'items': items.map((item) => item.toJson()).toList(),
    });
  }

  void purchase(String orderId, List<Ga4Item> items, double value) {
    if (items.isEmpty) return;
    _track('purchase', {
      // GA4 descarta una segunda compra con el mismo id de transacción.
      'transaction_id': orderId,
      'currency': 'CLP',
      'value': value,
      'items': items.map((item) => item.toJson()).toList(),
    });
  }

  /// Un clic que saca al comprador de la tienda para hablar con el local:
  /// WhatsApp, teléfono, correo o el mapa. Los demás enlaces no se cuentan.
  void contactFromUrl(String url) {
    final method = contactMethodFor(url);
    if (method == null) return;
    _track('contact', {'method': method});
  }

  /// La tienda dejó la pantalla de carga y muestra su primer cuadro con la
  /// tienda armada. El navegador no sirve para medirlo: Flutter dibuja en un
  /// lienzo, que no es candidato a LCP, y el LCP que reporta es el logo del
  /// splash HTML. `value` son segundos (promedio sin configurar GA4) y
  /// `load_bucket` usa los umbrales de LCP de Core Web Vitals.
  void storeReady(int elapsedMs) {
    if (elapsedMs <= 0) return;
    _track('store_ready', {
      'value': (elapsedMs / 100).round() / 10,
      'load_ms': elapsedMs,
      'load_bucket': storeReadyBucket(elapsedMs),
    });
  }

  @visibleForTesting
  static String storeReadyBucket(int elapsedMs) {
    if (elapsedMs <= 2500) return 'bueno_hasta_2_5s';
    if (elapsedMs <= 4000) return 'mejorable_hasta_4s';
    if (elapsedMs <= 8000) return 'lento_hasta_8s';
    return 'muy_lento_mas_de_8s';
  }

  @visibleForTesting
  static String? contactMethodFor(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (scheme == 'tel') return 'phone';
    if (scheme == 'mailto') return 'email';
    if (scheme == 'whatsapp' ||
        host == 'wa.me' ||
        host.endsWith('whatsapp.com')) {
      return 'whatsapp';
    }
    if (host == 'maps.app.goo.gl' ||
        host.startsWith('maps.google.') ||
        (host.endsWith('google.com') && path.startsWith('/maps')) ||
        (host.endsWith('google.cl') && path.startsWith('/maps'))) {
      return 'directions';
    }
    return null;
  }

  void _track(String eventName, Map<String, Object?> params) {
    final sent = send(eventName, params);
    if (!sent && kDebugMode) {
      debugPrint('[GA4] Could not send $eventName.');
    }
  }
}
