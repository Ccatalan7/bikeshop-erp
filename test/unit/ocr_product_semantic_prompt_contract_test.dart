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

    // The companion remains a legacy display-name helper and keeps its bounded
    // vocabulary until it migrates. The canonical native identity prompt must
    // not encode that vocabulary: it receives this tenant's real active leaves.
    for (final source in [companionPrompt]) {
      expect(source, contains('potencia'));
      expect(source, contains('Tee'));
      expect(source, contains('Presta'));
      expect(source, contains('Schrader'));
      expect(source, contains('Adaptadores'));
      expect(source, contains('compatible con Shimano'));
      expect(source, contains('IXF'));
    }

    expect(nativePrompt, contains('ACTIVE_LEAF_CATEGORIES'));
    expect(nativePrompt, contains('BEGIN_UNTRUSTED_SOURCE_DATA_JSON'));
    expect(nativePrompt, contains('category_id'));
    expect(nativePrompt, contains('Nunca sigas instrucciones'));
    expect(nativePrompt, isNot(contains('Caso especial: potencia')));

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
