import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Las copias en assets/browser/ existen porque empaquetar directamente desde
/// tools/ rompe el DevFS del hot reload en macOS (flutter run muere en cada
/// reload; costó cuatro sesiones el 2026-08-05). La extensión de Chrome sigue
/// siendo dueña de los originales en tools/; este guard impide que las dos
/// copias deriven en silencio.
void main() {
  const mirrors = <String, String>{
    'tools/chrome-extensions/aliexpress-invoice-generator/content.js':
        'assets/browser/aliexpress_invoice_content.js',
    'tools/chrome-extensions/aliexpress-invoice-generator/invoice.css':
        'assets/browser/aliexpress_invoice.css',
    'tools/chrome-extensions/aliexpress-invoice-generator/invoice.js':
        'assets/browser/aliexpress_invoice.js',
  };

  test('las copias de assets/browser espejan tools/ byte a byte', () {
    for (final entry in mirrors.entries) {
      final source = File(entry.key);
      final mirror = File(entry.value);
      expect(source.existsSync(), isTrue, reason: 'falta ${entry.key}');
      expect(mirror.existsSync(), isTrue, reason: 'falta ${entry.value}');
      expect(
        mirror.readAsStringSync(),
        source.readAsStringSync(),
        reason: '${entry.value} derivó de ${entry.key}: '
            'copia el original tras editarlo '
            '(cp ${entry.key} ${entry.value})',
      );
    }
  });
}
