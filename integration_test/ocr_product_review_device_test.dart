import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/ocr_candidate_picker.dart';
import 'package:vinabike_erp/shared/widgets/ocr_product_review_workspace.dart';

/// Real Android IME and shared review widgets. Isolated source-derived fixture:
/// no Supabase initialization, purchases, reservations or catalog writes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets(
        'OCR ${brightness.name}: compare, keyboard, dismiss and mark new',
        (tester) async {
      final controllers = OcrProductDraftControllers(
          sku: TextEditingController(),
          name: TextEditingController(text: 'Maza Trasera Novatec D042SB 32H'),
          cost: TextEditingController(text: '43317'),
          price: TextEditingController(text: '86600'));
      final candidate = ProductDuplicateCandidate(
          product: Product(
              id: 'novatec',
              tenantId: 'fixture',
              sku: 'AE0062',
              name: 'Maza Trasera Novatec 32H 135x10mm HG D042SB',
              price: 86600,
              cost: 43317),
          matchTier: ProductDuplicateMatchTier.strong,
          confidence: 0.9,
          reasons: const [
            'Modelo D042SB',
            'Agujeros 32H',
            'Ancho de eje 135mm'
          ],
          objections: const [],
          gates: const [],
          variantMismatch: false,
          hasProductImage: false);
      var writes = 0;
      var newDecisions = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike, brightness: brightness),
        home: Builder(
            builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('Revisar productos')),
                  body: OcrProductReviewWorkspace(
                      lines: [
                        OcrProductReviewLine(
                            id: 'maza',
                            sku: '',
                            originalTitle:
                                'NOVATEC D041SB D042SB 32/36 agujeros · Black D042SB 32H',
                            sourceQuantity: 1,
                            sourceLineTotal: 43317,
                            controllers: controllers,
                            status: OcrProductReviewStatus.ready,
                            candidates: [candidate],
                            inventoryProduct: candidate.product)
                      ],
                      callbacks: OcrProductReviewCallbacks(
                          onConfirmNewProduct: (_) => writes++,
                          onPrepareNewProduct: (_) => newDecisions++,
                          onOpenCandidates: (_) => OcrCandidatePicker.show(
                              context,
                              line: const OcrCandidateLineContext(
                                  title: 'Maza Trasera Novatec D042SB 32H',
                                  quantity: 1,
                                  unitCost: 43317),
                              candidates: [candidate],
                              onSearch: (_) async => [candidate.product])),
                      primaryLabel: 'Falta 1 decisión',
                      pricingPolicyLabel: 'Precio sugerido = costo × 2'),
                )),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ocr-review-inventory-maza')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('ocr-candidate-search'));
      tester.testTextInput.unregister();
      tester.widget<TextField>(search).controller!.text = 'Novatec';
      await tester.tap(search);
      await tester.pump();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      for (var i = 0; i < 30 && tester.view.viewInsets.bottom == 0; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      final close =
          tester.getRect(find.byKey(const Key('ocr-candidate-close')));
      expect(
          close.bottom,
          lessThan((tester.view.physicalSize.height -
                  tester.view.viewInsets.bottom) /
              tester.view.devicePixelRatio));
      debugPrint(
          'OCR_DEVICE_IME ${brightness.name} inset=${tester.view.viewInsets.bottom}');
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('ocr-${brightness.name}-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ocr-candidate-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ocr-review-row-maza')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ocr-review-new-maza')));
      await tester.pumpAndSettle();
      expect(newDecisions, 1);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('ocr-${brightness.name}-batch');
      await tester.pumpWidget(const SizedBox.shrink());
      tester.testTextInput.register();
      for (final controller in [
        controllers.name,
        controllers.sku,
        controllers.cost,
        controllers.price
      ]) {
        controller.dispose();
      }
    });
  }
}
