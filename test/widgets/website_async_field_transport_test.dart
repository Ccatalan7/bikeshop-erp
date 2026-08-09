import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/focal_point_picker.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_editor.dart';
import 'package:vinabike_erp/modules/website/widgets/website_color_picker.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_action_editor.dart';
import 'package:vinabike_erp/modules/website/widgets/website_media_picker.dart';

const _blockId = 'block-async';

WebsiteEditModeProvider _provider() {
  return WebsiteEditModeProvider()
    ..enterEditMode(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _blockId,
          'block_type': 'hero',
          'block_data': <String, dynamic>{
            'color': '#FF08100D',
            'opacity': 0.5,
            'ctaText': 'Ver catálogo',
            'ctaLink': '/productos',
            'actionVariant': 'filled',
          },
          'is_visible': true,
          'sort_order': 0,
        },
      ],
      const <String, dynamic>{},
      pageId: 'page-identical',
      pageSlug: '/inicio',
    )
    ..selectBlock(_blockId);
}

WebsiteEditModeProvider _remoteProvider(String identity) {
  final provider = WebsiteEditModeProvider();
  provider.adoptEditorEntryLease(
    0,
    WebsiteEditorCapabilitySnapshot(
      identity: identity,
      activeTenantId: 'tenant-exact',
      storefrontTenantId: 'tenant-exact',
      hasAuthority: true,
      authorityEpoch: 0,
    ),
  );
  provider.applyRouteModeCommand(WebsiteEditorMode.edit);
  provider.activatePageDocument(
    const <Map<String, dynamic>>[
      <String, dynamic>{
        'id': _blockId,
        'block_type': 'hero',
        'block_data': <String, dynamic>{'imageUrl': ''},
        'is_visible': true,
        'sort_order': 0,
      },
    ],
    const <String, dynamic>{},
    pageId: 'page-identical',
    pageSlug: '/inicio',
  );
  provider.selectBlock(_blockId);
  return provider;
}

Map<String, dynamic> _data(WebsiteEditModeProvider provider) =>
    Map<String, dynamic>.from(provider.getBlockData(_blockId));

WebsiteAsyncFieldBinding _binding(
  WebsiteEditModeProvider provider,
  String scopeKey,
) {
  return WebsiteAsyncFieldBinding.pageBlock(
    provider: provider,
    target: WebsiteAsyncFieldTarget.block(
      blockId: _blockId,
      scopeKey: scopeKey,
    ),
  );
}

void main() {
  test('remote upload arm is tenant exact and rejects a live provider swap',
      () {
    final providerA = _remoteProvider('user-a');
    final providerB = _remoteProvider('user-b');
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    final bindingA = _binding(providerA, 'root.imageUrl');
    final bindingB = _binding(providerB, 'root.imageUrl');
    final armA = bindingA.capture();
    expect(armA, isNotNull);

    final staleResolver = websiteRemoteAuthorityResolver(
      openingBinding: bindingA,
      remoteArm: armA,
      liveBinding: () => bindingB,
      isMounted: () => true,
      operation: 'subir imagen de prueba',
    );
    expect(staleResolver, isNotNull);
    expect(staleResolver!(), isNull);
    expect(providerA.hasUnsavedChanges, isFalse);
    expect(providerB.hasUnsavedChanges, isFalse);

    final liveArm = bindingA.capture();
    final liveResolver = websiteRemoteAuthorityResolver(
      openingBinding: bindingA,
      remoteArm: liveArm,
      liveBinding: () => bindingA,
      isMounted: () => true,
      operation: 'subir imagen de prueba',
    );
    final authority = liveResolver!();
    expect(authority?.tenantId, 'tenant-exact');
    final guard = authority!.claimForWrite();
    guard();
    authority.ensureCurrent();
    expect(providerA.hasUnsavedChanges, isFalse);
  });

  test('catalog read owner changes across same-provider document ABA', () {
    final provider = _remoteProvider('user-a');
    addTearDown(provider.dispose);
    final bindingA = _binding(provider, 'root.productsCatalogRead');
    final armA = bindingA.capture();
    final ownerA = bindingA.readOwnerIdentity;

    provider.activatePageDocument(
      const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _blockId,
          'block_type': 'hero',
          'block_data': <String, dynamic>{'imageUrl': ''},
          'is_visible': true,
          'sort_order': 0,
        },
      ],
      const <String, dynamic>{},
      pageId: 'page-replacement',
      pageSlug: '/reemplazo',
    );
    provider.selectBlock(_blockId);
    final bindingB = _binding(provider, 'root.productsCatalogRead');
    expect(bindingB.readOwnerIdentity, isNot(ownerA));

    final resolver = websiteRemoteAuthorityResolver(
      openingBinding: bindingA,
      remoteArm: armA,
      liveBinding: () => bindingB,
      isMounted: () => true,
      operation: 'cargar catálogo de prueba',
    );
    final authority = resolver!();
    expect(authority, isNotNull);
    expect(
      authority!.claimForWrite,
      throwsA(isA<WebsiteEditorWriteSupersededException>()),
    );
    expect(provider.hasUnsavedChanges, isFalse);
  });

  test('scope A -> B -> A consumes the old arm and cannot resurrect it', () {
    final provider = _provider();
    addTearDown(provider.dispose);
    final bindingA = _binding(provider, 'root.color');
    final bindingB = _binding(provider, 'root.otherColor');
    final arm = bindingA.capture();
    expect(arm, isNotNull);
    var callsA = 0;
    var callsB = 0;

    expect(
      bindingB.commit(arm!, () {
        callsB++;
        return WebsiteInlineMutationResult.committed;
      }),
      WebsiteInlineMutationResult.rejected,
    );
    expect(
      bindingA.commit(arm, () {
        callsA++;
        return WebsiteInlineMutationResult.committed;
      }),
      WebsiteInlineMutationResult.rejected,
    );
    expect(callsA, 0);
    expect(callsB, 0);
    expect(provider.hasUnsavedChanges, isFalse);
  });

  testWidgets(
    'transactional slider rejects same-target document ABA at pointer-up',
    (tester) async {
      final provider = _provider();
      addTearDown(provider.dispose);
      var writes = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer<WebsiteEditModeProvider>(
                builder: (context, live, _) {
                  final binding = _binding(live, 'root.opacity');
                  return WebsiteTransactionalSlider(
                    key: const ValueKey('exact-slider'),
                    value: (_data(live)['opacity'] as num).toDouble(),
                    min: 0,
                    max: 1,
                    transactionIdentity: binding.identity,
                    asyncBinding: binding,
                    onCommit: (next) {
                      writes++;
                      live.updateBlockData(_blockId, 'opacity', next);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      var slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.5);
      slider.onChanged!(0.8);

      provider.updateBlockData(_blockId, 'color', '#F0642F');
      provider.undo();
      await tester.pump();
      expect(_data(provider)['color'], '#FF08100D');
      expect(_data(provider)['opacity'], 0.5);

      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeEnd!(0.8);
      await tester.pump();

      expect(writes, 0);
      expect(_data(provider)['opacity'], 0.5);
      expect(provider.canUndo, isFalse);
    },
  );

  testWidgets(
    'focal gesture rejects same-target document ABA at pointer-up',
    (tester) async {
      final provider = _provider();
      addTearDown(provider.dispose);
      var writes = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer<WebsiteEditModeProvider>(
                builder: (context, live, _) => SizedBox(
                  width: 320,
                  child: FocalPointPicker(
                    imageUrl: 'https://cdn.example/focal.webp',
                    focalX: 0.5,
                    focalY: 0.5,
                    continuousUpdates: false,
                    asyncBinding: _binding(live, 'root.imageUrl.focal'),
                    onChanged: (x, y) => writes++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Finder gestureOwner() => find.byWidgetPredicate(
            (widget) =>
                widget is Listener &&
                widget.onPointerDown != null &&
                widget.onPointerMove != null &&
                widget.onPointerUp != null,
          );
      var listener = tester.widget<Listener>(gestureOwner());
      listener.onPointerDown!(
        const PointerDownEvent(position: Offset(80, 40)),
      );
      listener.onPointerMove!(
        const PointerMoveEvent(position: Offset(240, 100)),
      );

      provider.updateBlockData(_blockId, 'color', '#F0642F');
      provider.undo();
      await tester.pump();

      listener = tester.widget<Listener>(gestureOwner());
      listener.onPointerUp!(
        const PointerUpEvent(position: Offset(240, 100)),
      );
      await tester.pump();

      expect(writes, 0);
      expect(provider.canUndo, isFalse);
    },
  );

  testWidgets(
    'action label edit cannot redirect from provider A to retained provider B',
    (tester) async {
      final providerA = _provider();
      final providerB = _provider();
      addTearDown(providerA.dispose);
      addTearDown(providerB.dispose);
      var live = providerA;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              final rendered = live;
              return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
                value: rendered,
                child: Scaffold(
                  body: WebsiteActionEditor(
                    key: const ValueKey('retained-action-editor'),
                    value: WebsiteActionValue(
                      label: _data(rendered)['ctaText'] as String,
                      href: _data(rendered)['ctaLink'] as String,
                    ),
                    asyncBinding: _binding(rendered, 'root.action'),
                    onChanged: (next) {
                      rendered.updateBlockDataMultiple(
                        _blockId,
                        <String, dynamic>{
                          'ctaText': next.label,
                          'ctaLink': next.href,
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );

      final editorA = tester.state(
        find.byKey(const ValueKey('retained-action-editor')),
      );
      var labelField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Ver catálogo',
      );
      await tester.tap(labelField);
      await tester.pump();
      tester.widget<TextField>(labelField).onChanged!('Borrador de A');

      rebuild(() => live = providerB);
      await tester.pump();
      final editorB = tester.state(
        find.byKey(const ValueKey('retained-action-editor')),
      );
      expect(identical(editorA, editorB), isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(_data(providerA)['ctaText'], 'Ver catálogo');
      expect(_data(providerB)['ctaText'], 'Ver catálogo');
      expect(providerA.canUndo, isFalse);
      expect(providerB.canUndo, isFalse);
    },
  );

  testWidgets(
    'color result from provider A cannot adopt live provider B with same State',
    (tester) async {
      final providerA = _provider();
      final providerB = _provider();
      addTearDown(providerA.dispose);
      addTearDown(providerB.dispose);
      final initialA = _data(providerA);
      final initialB = _data(providerB);
      var live = providerA;
      var callsA = 0;
      var callsB = 0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              final rendered = live;
              return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
                value: rendered,
                child: Scaffold(
                  body: WebsiteColorPickerField(
                    key: const ValueKey('same-color-field-state'),
                    label: 'Color exacto',
                    value: _data(rendered)['color'] as String,
                    asyncBinding: _binding(rendered, 'root.color'),
                    onChanged: (next) {
                      if (identical(rendered, providerA)) {
                        callsA++;
                      } else {
                        callsB++;
                      }
                      rendered.updateBlockData(_blockId, 'color', next);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );
      final stateA = tester.state(
        find.byKey(const ValueKey('same-color-field-state')),
      );
      await tester.tap(
        find.byKey(const ValueKey('website_color_picker_Color exacto')),
      );
      await tester.pumpAndSettle();

      rebuild(() => live = providerB);
      await tester.pump();
      final stateB = tester.state(
        find.byKey(const ValueKey('same-color-field-state')),
      );
      expect(identical(stateA, stateB), isTrue,
          reason: 'same State was reused');

      await tester.tap(
        find.byKey(const ValueKey('website_color_swatch_#F0642F')),
      );
      await tester.tap(
        find.byKey(const ValueKey('website_color_picker_apply')),
      );
      await tester.pumpAndSettle();

      expect(callsA, 0);
      expect(callsB, 0);
      expect(_data(providerA), initialA);
      expect(_data(providerB), initialB);
      expect(providerA.hasUnsavedChanges, isFalse);
      expect(providerB.hasUnsavedChanges, isFalse);
    },
  );

  testWidgets('valid color apply writes exactly once and cancel writes zero',
      (tester) async {
    final provider = _provider();
    addTearDown(provider.dispose);
    var calls = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Consumer<WebsiteEditModeProvider>(
              builder: (context, live, _) => WebsiteColorPickerField(
                label: 'Color válido',
                value: _data(live)['color'] as String,
                asyncBinding: _binding(live, 'root.color'),
                onChanged: (next) {
                  calls++;
                  live.updateBlockData(_blockId, 'color', next);
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('website_color_picker_Color válido')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(provider.canUndo, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('website_color_picker_Color válido')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('website_color_swatch_#F0642F')),
    );
    await tester.tap(
      find.byKey(const ValueKey('website_color_picker_apply')),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(_data(provider)['color'], '#F0642F');
    expect(provider.canUndo, isTrue);
    provider.undo();
    expect(_data(provider)['color'], '#FF08100D');
    expect(provider.canUndo, isFalse, reason: 'one history entry only');
  });

  testWidgets(
    'O-05 opens only after accepted commit and rejects provider A -> B',
    (tester) async {
      final providerA = _provider();
      final providerB = _provider();
      addTearDown(providerA.dispose);
      addTearDown(providerB.dispose);
      final initialA = _data(providerA);
      final initialB = _data(providerB);
      var live = providerA;
      var callsA = 0;
      var callsB = 0;
      var opensA = 0;
      var opensB = 0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              final rendered = live;
              final data = _data(rendered);
              final action = WebsiteActionValue(
                label: data['ctaText'] as String,
                href: data['ctaLink'] as String,
                variant: WebsiteActionVariant.fromStorage(
                  data['actionVariant']?.toString(),
                ),
              );
              return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
                value: rendered,
                child: WebsiteEditorChromeScope(
                  editorWidth: 390,
                  canvasWidth: 390,
                  child: Scaffold(
                    body: Center(
                      child: WebsiteInlineActionEditor(
                        key: const ValueKey('same-inline-action-state'),
                        action: action,
                        openOnFirstTap: true,
                        asyncBinding: _binding(rendered, 'root.action'),
                        onChanged: (next) {
                          if (identical(rendered, providerA)) {
                            callsA++;
                          } else {
                            callsB++;
                          }
                          rendered.updateBlockDataMultiple(
                            _blockId,
                            <String, dynamic>{
                              'ctaText': next.label,
                              'ctaLink': next.href,
                              'actionVariant': next.variant.storageValue,
                            },
                          );
                          return WebsiteInlineMutationResult.committed;
                        },
                        onOpen: (_) {
                          if (identical(rendered, providerA)) {
                            opensA++;
                          } else {
                            opensB++;
                          }
                        },
                        child: const SizedBox(
                          width: 180,
                          height: 48,
                          child: Center(child: Text('Ver catálogo')),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      final stateA = tester.state(
        find.byKey(const ValueKey('same-inline-action-state')),
      );
      await tester.tap(
        find.byKey(const ValueKey('same-inline-action-state')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(WebsiteInlineActionEditor.sheetKey), findsOneWidget);

      rebuild(() => live = providerB);
      await tester.pump();
      final stateB = tester.state(
        find.byKey(const ValueKey('same-inline-action-state')),
      );
      expect(identical(stateA, stateB), isTrue);
      await tester.tap(find.byKey(WebsiteInlineActionEditor.sheetOpenKey));
      await tester.pumpAndSettle();

      expect(callsA, 0);
      expect(callsB, 0);
      expect(opensA, 0);
      expect(opensB, 0);
      expect(_data(providerA), initialA);
      expect(_data(providerB), initialB);
    },
  );

  testWidgets('valid O-05 mutation writes once, then opens; cancel writes zero',
      (tester) async {
    final provider = _provider();
    addTearDown(provider.dispose);
    var calls = 0;
    var opens = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: WebsiteEditorChromeScope(
            editorWidth: 390,
            canvasWidth: 390,
            child: Scaffold(
              body: Center(
                child: Consumer<WebsiteEditModeProvider>(
                  builder: (context, live, _) {
                    final data = _data(live);
                    return WebsiteInlineActionEditor(
                      action: WebsiteActionValue(
                        label: data['ctaText'] as String,
                        href: data['ctaLink'] as String,
                        variant: WebsiteActionVariant.fromStorage(
                          data['actionVariant']?.toString(),
                        ),
                      ),
                      openOnFirstTap: true,
                      asyncBinding: _binding(live, 'root.action'),
                      onChanged: (next) {
                        calls++;
                        live.updateBlockDataMultiple(
                          _blockId,
                          <String, dynamic>{
                            'ctaText': next.label,
                            'ctaLink': next.href,
                            'actionVariant': next.variant.storageValue,
                          },
                        );
                        return WebsiteInlineMutationResult.committed;
                      },
                      onOpen: (_) => opens++,
                      child: const SizedBox(
                        width: 180,
                        height: 48,
                        child: Center(child: Text('Ver catálogo')),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(WebsiteInlineActionEditor));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WebsiteInlineActionEditor.sheetCancelKey));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(opens, 0);
    expect(provider.canUndo, isFalse);

    await tester.tap(find.byType(WebsiteInlineActionEditor));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Comprar ahora');
    await tester.pump();
    await tester.tap(find.byKey(WebsiteInlineActionEditor.sheetOpenKey));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(opens, 1);
    expect(_data(provider)['ctaText'], 'Comprar ahora');
    expect(provider.canUndo, isTrue);
    provider.undo();
    expect(_data(provider)['ctaText'], 'Ver catálogo');
    expect(provider.canUndo, isFalse, reason: 'one history entry only');
  });
}
