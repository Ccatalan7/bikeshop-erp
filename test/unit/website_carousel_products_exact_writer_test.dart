import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final carousel = File(
    'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
  ).readAsStringSync();
  final products = File(
    'lib/modules/website/widgets/editor_panel/products_controls.dart',
  ).readAsStringSync();
  final canvas = File(
    'lib/modules/website/widgets/editor_panel/canvas_controls.dart',
  ).readAsStringSync();

  test('custom inspectors contain no legacy productive block-data writer', () {
    for (final source in <String>[carousel, products]) {
      expect(source, isNot(contains('.updateBlockData(')));
      expect(source, isNot(contains('.updateBlockDataMultiple(')));
      expect(source, contains('captureInlineMutationLease'));
      expect(source, contains('commitInlineMutation'));
    }
  });

  test('shared slider owns local draft, gesture lease, commit, and cancel', () {
    final sliderStart = products.indexOf('class _InlineLeaseCommitSlider');
    final sliderEnd = products.indexOf('/// Product picker dialog');
    expect(sliderStart, greaterThanOrEqualTo(0));
    expect(sliderEnd, greaterThan(sliderStart));
    final slider = products.substring(sliderStart, sliderEnd);

    expect(slider, contains('onChangeStart: _start'));
    expect(slider, contains('onChanged: _change'));
    expect(slider, contains('onChangeEnd: _commit'));
    expect(slider, contains('onPointerCancel: (_) => _cancel()'));
    expect(slider, contains('WebsiteInlineManipulationLease? _lease'));
    expect(slider, isNot(contains('updateBlockData')));
  });

  test('Products picker captures authority before await and never recaptures',
      () {
    final buildCapture = products.indexOf(
      'final pickerLease = _captureSharedLease(selectionProperties);',
    );
    final openCallback = products.indexOf(
      'onOpenPicker: () => _showProductPicker(',
    );
    final methodStart = products.indexOf('Future<void> _showProductPicker(');
    final awaitDialog = products.indexOf(
      'await showDialog<List<String>>',
      methodStart,
    );
    final commit = products.indexOf(
      'widget.provider.commitInlineMutation(',
      awaitDialog,
    );
    final methodEnd = products.indexOf(
      '// Shared by the Products inspector',
      methodStart,
    );

    expect(buildCapture, greaterThanOrEqualTo(0));
    expect(openCallback, greaterThan(buildCapture));
    expect(awaitDialog, greaterThan(methodStart));
    expect(commit, greaterThan(awaitDialog));
    final completion = products.substring(awaitDialog, methodEnd);
    expect(completion, isNot(contains('_captureSharedLease(')));
  });

  test('Products mirrors and action companions are declared atomically', () {
    expect(
      products,
      contains('WebsiteProductsBlockContract.legacySelectedProductsKey'),
    );
    for (final key in <String>[
      "_sharedProperty('viewAllText')",
      "_sharedProperty('viewAllLink')",
      "_sharedProperty('actionVariant')",
      "_sharedProperty('actions')",
    ]) {
      expect(products, contains(key));
    }
  });

  test('Products and Canvas catalog reads are exact and tenant-scoped', () {
    for (final source in <String>[products, canvas]) {
      expect(source, contains('readOwnerIdentity'));
      expect(source, contains('websiteRemoteAuthorityResolver('));
      expect(source, contains(".eq('tenant_id', authority.tenantId)"));
    }
    final canvasSelectors = canvas.substring(
      canvas.indexOf('class _CanvasProductSelector'),
    );
    expect(canvasSelectors, isNot(contains('_resolveTenantId')));
    expect(
      products,
      contains("_asyncFieldBinding('root.productsCatalogRead')"),
    );
  });

  test('Carousel root commands are exact and duration owns its companion', () {
    final rootStart = carousel.indexOf(
      'final autoPlayProperties = <WebsiteInlineManipulationProperty>[',
    );
    final repeaterStart = carousel.indexOf(
      "title: 'Slides (\${slides.length})'",
      rootStart,
    );
    expect(rootStart, greaterThanOrEqualTo(0));
    expect(repeaterStart, greaterThan(rootStart));
    final root = carousel.substring(rootStart, repeaterStart);

    expect(root, contains('_sharedRootBinding('));
    expect(root, contains('_InlineLeaseCommitSlider('));
    expect(
        root, contains("companionKeys: const <String>['transitionDuration']"));
    expect(root, contains("'animationDurationMs': value.toInt()"));
    expect(root, isNot(contains('_EditorSlider(')));
  });

  test('Carousel upload captures exact slide intent before every await', () {
    final methodStart = carousel.indexOf('Future<void> _uploadSlideVideoFile(');
    final capture = carousel.indexOf(
      'captureRepeaterMutationLease(target)',
      methodStart,
    );
    final slideRef =
        carousel.indexOf('_slideRef(slide, slideIndex)', methodStart);
    final firstAwait = carousel.indexOf(
      'await FilePicker.platform.pickFiles',
      methodStart,
    );
    final commit = carousel.indexOf(
      'commitRepeaterMutation(',
      firstAwait,
    );
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(capture, greaterThan(methodStart));
    expect(slideRef, greaterThan(capture));
    expect(firstAwait, greaterThan(slideRef));
    expect(commit, greaterThan(firstAwait));
  });
}
