import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The chat edits a purchase document **inside** the chat.
///
/// Pushing the form as a route buried the conversation under a full-screen
/// page whose only visible way forward was «Enviar» — a status change the chat
/// had not asked for. These are source guards: the form has no widget-test
/// harness (it needs eight providers), and the defect they protect against is
/// structural, not visual.
void main() {
  final form = File(
    'lib/modules/purchases/pages/purchase_invoice_form_page.dart',
  ).readAsStringSync();
  final chatDialog = File(
    'lib/modules/messaging/widgets/purchase_document_preview_dialog.dart',
  ).readAsStringSync();

  test('the chat hosts the purchase form instead of navigating to it', () {
    expect(
      chatDialog,
      contains('showDialog<bool>('),
      reason: 'Editing must stay in a floating block over the conversation.',
    );
    expect(
      chatDialog,
      isNot(contains('MaterialPageRoute')),
      reason:
          'A route would cover the chat and hand the way back to the router.',
    );
    expect(
      chatDialog,
      contains('startInEditMode: true'),
      reason:
          'The host already asked to edit; the form must not ask a second time.',
    );
    expect(chatDialog, contains('onEmbeddedFinished:'));
  });

  test('an embedded form reports back instead of driving the router', () {
    final returnToOrigin = form.substring(
      form.indexOf('void _returnToOrigin() {'),
    );
    final embeddedIndex = returnToOrigin.indexOf('onEmbeddedFinished');
    final routerIndex = returnToOrigin.indexOf('ReturnNavigation.canReturn');
    expect(embeddedIndex, greaterThan(-1));
    expect(
      embeddedIndex,
      lessThan(routerIndex),
      reason: 'Closing an embedded form must never reach the app router.',
    );

    final save = form.substring(
      form.indexOf('Future<void> _saveInvoice() async {'),
    );
    expect(
      save.indexOf('onEmbeddedFinished'),
      lessThan(save.indexOf('context.canPop()')),
      reason: 'Saving must return to the host, not to /purchases.',
    );
  });

  test('an embedded form drops the document workflow actions', () {
    expect(
      form,
      contains('widget.invoiceId != null && !_isEmbedded'),
      reason: 'Enviar, Eliminar and the receipt actions belong to the document '
          'page, not to a chat composer.',
    );
    expect(
      form,
      contains('bool get _isEmbedded => widget.onEmbeddedFinished != null;'),
    );
  });

  test('an embedded form does not paint the app shell inside its host', () {
    expect(
      form,
      contains('if (_isEmbedded) {'),
      reason: 'A second sidebar inside a dialog is not a layout.',
    );
    final build = form.substring(form.indexOf('Widget build(BuildContext'));
    expect(
      build.indexOf('if (_isEmbedded) {'),
      lessThan(build.indexOf('return MainLayout(child: body);')),
      reason: 'The shell is the routed form\'s wrapper, not the embedded one.',
    );
  });

  test('the routed form keeps its own behaviour', () {
    expect(form, contains('this.startInEditMode = false'));
    expect(
      form,
      contains(
          '_isEditing = widget.invoiceId == null || widget.startInEditMode;'),
      reason: 'An existing draft opened normally still starts in view mode.',
    );
    expect(form, contains('ReturnNavigation.close(context'));
    expect(
      form,
      contains('return MainLayout(child: body);'),
      reason: 'Opened as a route, the form still lives inside the app shell.',
    );
  });
}
