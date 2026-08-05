import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_block_sheet.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_action_editor.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';
import 'package:vinabike_erp/public_store/widgets/persistent_editor_shell.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Map<String, dynamic> block({
    required String id,
    required String type,
    required int order,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'id': id,
      'block_type': type,
      'order_index': order,
      'is_visible': true,
      'block_data': data,
    };
  }

  List<Map<String, dynamic>> page() => <Map<String, dynamic>>[
        block(
          id: 'hero-1',
          type: 'hero',
          order: 0,
          data: const <String, dynamic>{
            'title': 'Taller de bicicletas',
            'blockHeight': 620,
            'buttonText': 'Ver catálogo',
            'buttonLink': '/productos',
          },
        ),
        block(
          id: 'text-1',
          type: 'text',
          order: 1,
          data: const <String, dynamic>{
            'content': 'Productos destacados',
            'blockHeight': 620,
          },
        ),
      ];

  Widget host(WebsiteEditModeProvider provider) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.light,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: Scaffold(
          body: PersistentEditorShell(
            child: Consumer<WebsiteEditModeProvider>(
              builder: (context, live, _) => SingleChildScrollView(
                child: PageComposition(
                  composition: WebsitePageComposition.project(
                    blocks: live.blocks,
                    mode: WebsitePageCompositionMode.edit,
                    breakpoint: 'mobile',
                  ),
                  primaryColor: Colors.blue,
                  accentColor: Colors.teal,
                  textColor: Colors.black,
                  containerPadding: 16,
                  onAddBlock: (type, {atIndex}) {},
                  onSpacingChanged: (blockId, spacing) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpHost(
    WidgetTester tester,
    WebsiteEditModeProvider provider,
  ) async {
    await tester.runAsync(DeferredEditableBlockRenderer.preload);
    await tester.pumpWidget(host(provider));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    }
  }

  Future<void> openCtaEditor(WidgetTester tester) async {
    final cta = find.byKey(
      const ValueKey<String>('website-inline-action-hero-1-hero.action'),
    );
    expect(cta, findsOneWidget);
    await tester.tap(cta, warnIfMissed: false);
    await tester.pump();
    await tester.tap(cta, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(WebsiteInlineActionEditor.sheetKey), findsOneWidget);
  }

  Future<double> waitForSystemKeyboard(WidgetTester tester) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final sheetContext = tester.element(
        find.byKey(WebsiteInlineActionEditor.sheetKey),
      );
      final inset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      if (inset > 0) return inset;
    }
    return 0;
  }

  Rect rectOf(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    return box.localToGlobal(Offset.zero) & box.size;
  }

  testWidgets(
    'iOS keyboard keeps the contextual CTA sheet and Listo reachable',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          page(),
          const <String, dynamic>{},
          pageId: 'ios-phone-smoke',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, provider);
      await openCtaEditor(tester);

      final labelField = find
          .descendant(
            of: find.byKey(WebsiteInlineActionEditor.sheetFieldsKey),
            matching: find.byType(TextField),
          )
          .first;
      final editable = find.descendant(
        of: labelField,
        matching: find.byType(EditableText),
      );

      // Integration tests normally register TestTextInput. Unregister it for
      // this one smoke so iOS owns the actual software keyboard and viewInsets.
      tester.testTextInput.unregister();
      addTearDown(tester.testTextInput.register);
      await tester.tap(labelField);
      await tester.pump();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');

      final keyboardInset = await waitForSystemKeyboard(tester);
      expect(keyboardInset, greaterThan(0));
      expect(
        tester.state<EditableTextState>(editable).widget.focusNode.hasFocus,
        isTrue,
      );

      final sheetContext = tester.element(
        find.byKey(WebsiteInlineActionEditor.sheetKey),
      );
      final viewportHeight = MediaQuery.sizeOf(sheetContext).height;
      final keyboardTop = viewportHeight - keyboardInset;
      final sheet = rectOf(
        tester,
        find.byKey(WebsiteInlineActionEditor.sheetKey),
      );
      final apply = rectOf(
        tester,
        find.byKey(WebsiteInlineActionEditor.sheetApplyKey),
      );

      expect(sheet.bottom, lessThanOrEqualTo(keyboardTop + 1));
      expect(apply.bottom, lessThanOrEqualTo(keyboardTop + 1));
      expect(
        apply.height,
        WebsiteBlockEditSheetGeometry.ctaHeight,
      );

      debugPrint(
        'IOS_PHONE_AUTHORING_KEYBOARD_READY '
        'inset=$keyboardInset sheetBottom=${sheet.bottom} '
        'applyBottom=${apply.bottom} keyboardTop=$keyboardTop',
      );
      final screenshot = await binding.takeScreenshot(
        'website-phone-authoring-ios-keyboard',
      );
      expect(screenshot, isNotEmpty);

      if (const bool.fromEnvironment('IOS_SMOKE_CAPTURE_HOLD')) {
        debugPrint('IOS_PHONE_AUTHORING_CAPTURE_WINDOW');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 15)),
        );
      }
    },
  );
}
