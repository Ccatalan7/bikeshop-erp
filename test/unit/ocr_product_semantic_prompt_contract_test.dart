import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native and companion prompts preserve catalog semantic boundaries', () {
    final nativePrompt = File(
      'lib/modules/ai_assistant/services/ai_service.dart',
    ).readAsStringSync();
    final companionPrompt = File(
      'tools/chrome-extensions/aliexpress-invoice-generator/popup.js',
    ).readAsStringSync();
    final ocrOwner = File(
      'lib/shared/widgets/ocr_upload_widget.dart',
    ).readAsStringSync();

    for (final source in [nativePrompt, companionPrompt]) {
      expect(source, contains('potencia'));
      expect(source, contains('Tee'));
      expect(source, contains('Presta'));
      expect(source, contains('Schrader'));
      expect(source, contains('Adaptadores'));
      expect(source, contains('compatible con Shimano'));
      expect(source, contains('IXF'));
    }

    expect(
      ocrOwner,
      contains('ProductCatalogSemanticResolver'),
      reason: 'OCR must revalidate free-form AI/add-on hints canonically.',
    );
    expect(
      ocrOwner,
      isNot(contains("'valvula': 'Válvula Tubeless'")),
      reason: 'A generic valve token cannot imply tubeless.',
    );
  });
}
