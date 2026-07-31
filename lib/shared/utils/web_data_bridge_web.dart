import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

// Define the JS window extension to access our custom property
@JS('window')
external WindowExtension get window;

extension type WindowExtension(JSObject _) implements JSObject {
  @JS('flutter_injected_preloaded_data')
  external JSPromise? get flutterInjectedPreloadedData;
}

/// Web implementation - reads the raw tenant envelope from the JS Promise.
///
/// Ownership and payload validation stay in the platform-neutral facade.
Future<Object?> getPreloadedStoreDataImpl() async {
  try {
    final promise = window.flutterInjectedPreloadedData;

    if (promise == null) {
      debugPrint('ℹ️ [WebDataBridge] No preloaded data promise found.');
      return null;
    }

    // debugPrint('🚀 [WebDataBridge] Found preloaded data promise! Awaiting...');

    // Convert JSPromise to Dart Future
    final result = await promise.toDart;

    // Convert JSObject/JSAny to Dart Map
    // Ideally the result is a JS Object that matches Map<String, dynamic> structure
    // We might need to ensure it's converted to a pure Dart Map
    if (result != null) {
      // Simple way to ensure clean Dart object: json encode/decode if needed,
      // or just cast if using dart:convert on the JS side (which fetch().json() basically does)
      // With js_interop, it often returns a JSObject.
      // A safe trick is to rely on jsonEncode of the JS object if direct cast fails,
      // but let's try to interpret it as a Map first.

      // Since we know it came from res.json() in JS, it's a JS Object.
      // We can use a helper to stringify and parse back to be 100% safe about types
      // or manually convert. Stringify is safest for complex nested maps.
      final jsonString = _stringify(result);
      return json.decode(jsonString);
    }

    return null;
  } catch (e) {
    debugPrint('⚠️ [WebDataBridge] Failed to retrieve preloaded data: $e');
    return null;
  }
}

@JS('JSON.stringify')
external String _stringify(JSAny obj);
