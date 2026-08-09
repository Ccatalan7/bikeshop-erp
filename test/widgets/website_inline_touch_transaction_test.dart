import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/block_resize_handle.dart';
import 'package:vinabike_erp/modules/website/widgets/block_spacer_handle.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_text_v2.dart';
import 'package:vinabike_erp/modules/website/widgets/text_formatting_toolbar.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_control_density.dart';
import 'package:vinabike_erp/shared/widgets/vb_segmented.dart';

/// Gesture-level regression for the inline manipulation contract.
///
/// These tests intentionally mount the controls without the block presenter:
/// the provider owns document atomicity while each control owns only its local
/// pointer preview. This keeps the gesture contract independently testable even
/// while renderer families evolve.
void main() {
  WebsiteEditModeProvider providerFor(
    Map<String, dynamic> data, {
    DevicePreviewMode preview = DevicePreviewMode.mobile,
  }) {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'block-1',
            'block_type': 'text',
            'block_data': data,
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-1',
        pageSlug: 'inicio',
      )
      ..selectBlock('block-1')
      ..setDevicePreviewMode(preview);
    provider.reportRenderedBlockViewport(
      'block-1',
      switch (preview) {
        DevicePreviewMode.desktop => WebsiteViewport.desktop,
        DevicePreviewMode.tablet => WebsiteViewport.tablet,
        DevicePreviewMode.mobile => WebsiteViewport.mobile,
      },
    );
    addTearDown(provider.dispose);
    return provider;
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );

  Map<String, dynamic> viewportData(
    WebsiteEditModeProvider provider,
    String viewport,
  ) {
    final responsive = dataOf(provider)['responsive'];
    if (responsive is! Map || responsive[viewport] is! Map) {
      return const <String, dynamic>{};
    }
    return Map<String, dynamic>.from(responsive[viewport] as Map);
  }

  WebsiteInlineManipulationTarget blockTarget({
    required WebsiteViewport viewport,
    required List<WebsiteInlineManipulationProperty> properties,
  }) {
    return WebsiteInlineManipulationTarget(
      blockId: 'block-1',
      owner: const WebsiteInlineBlockOwner(),
      viewport: viewport,
      properties: properties,
    );
  }

  group('separación entre bloques', () {
    Widget providerHost(
      WebsiteEditModeProvider provider, {
      VbDensity density = VbDensity.compact,
    }) {
      return MaterialApp(
        home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 520,
                child: WebsiteEditorControlDensityScope(
                  density: density,
                  child: Consumer<WebsiteEditModeProvider>(
                    builder: (context, watched, _) {
                      final data = dataOf(watched);
                      final mobile = viewportData(watched, 'mobile');
                      final spacing = (mobile['spacingAfter'] ??
                          data['spacingAfter']) as num;
                      return BlockSpacerHandle(
                        currentSpacing: spacing.toDouble(),
                        minimumInteractiveExtent: 24,
                        isActive: true,
                        onSpacingChanged: (value) => watched.updateBlockData(
                          'block-1',
                          WebsiteBlockMetaFields.spacingAfter.key,
                          value,
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
    }

    testWidgets('drag mantiene preview local y agrega exactamente un undo',
        (tester) async {
      final provider = providerFor(<String, dynamic>{'spacingAfter': 16.0});
      provider.setFieldWriteScope(
        blockId: 'block-1',
        propertyKey: WebsiteBlockMetaFields.spacingAfter.key,
        policy: WebsiteBlockMetaFields.spacingAfter.responsivePolicy,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      final original = dataOf(provider);

      await tester.pumpWidget(providerHost(provider));
      final handle = find.byType(BlockSpacerHandle);
      final drag = await tester.startGesture(tester.getCenter(handle));
      await drag.moveBy(const Offset(0, 40));
      await tester.pump();

      expect(dataOf(provider), original, reason: 'move sólo cambia el preview');
      expect(provider.canUndo, isFalse);

      await drag.up();
      await tester.pump();

      expect(dataOf(provider)['spacingAfter'], 16.0);
      expect(viewportData(provider, 'mobile')['spacingAfter'], 56.0);
      expect(provider.canUndo, isTrue);

      provider.undo();
      expect(dataOf(provider), original);
      expect(provider.canUndo, isFalse, reason: 'un drag equivale a un undo');
    });

    testWidgets('pointer-cancel abandona la lease con cero escrituras',
        (tester) async {
      final provider = providerFor(<String, dynamic>{'spacingAfter': 16.0});
      provider.setFieldWriteScope(
        blockId: 'block-1',
        propertyKey: WebsiteBlockMetaFields.spacingAfter.key,
        policy: WebsiteBlockMetaFields.spacingAfter.responsivePolicy,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      final original = dataOf(provider);

      await tester.pumpWidget(providerHost(provider));
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(BlockSpacerHandle)),
      );
      await drag.moveBy(const Offset(0, 40));
      await tester.pump();
      await drag.cancel();
      await tester.pump();

      expect(dataOf(provider), original);
      expect(provider.canUndo, isFalse);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.inlineManipulationSession, isNull);
    });

    testWidgets('inactivo no compite con el swipe de navegación',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: ListView(
                controller: controller,
                children: <Widget>[
                  BlockSpacerHandle(
                    currentSpacing: 96,
                    isActive: false,
                    onSpacingChanged: (_) {},
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );

      final swipe = await tester.startGesture(const Offset(20, 80));
      await swipe.moveBy(const Offset(0, -70));
      await swipe.up();
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
    });

    testWidgets('preserva 20 visuales con pointer y expone 48 en touch',
        (tester) async {
      final provider = providerFor(<String, dynamic>{'spacingAfter': 16.0});

      Future<double> presetExtent(VbDensity density) async {
        await tester.pumpWidget(providerHost(provider, density: density));
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(
          tester.getCenter(find.byType(BlockSpacerHandle)),
        );
        await tester.pump();
        final extent = tester
            .getSize(
              find.byKey(
                const ValueKey<String>('website-spacing-preset-0'),
              ),
            )
            .shortestSide;
        await mouse.removePointer();
        return extent;
      }

      expect(await presetExtent(VbDensity.compact), 20);
      expect(await presetExtent(VbDensity.touch), 48);
    });
  });

  group('altura del bloque', () {
    testWidgets('tablet se confirma una vez; cancel no persiste',
        (tester) async {
      final provider = providerFor(
        <String, dynamic>{'blockHeight': 300.0},
        preview: DevicePreviewMode.tablet,
      );
      provider.setFieldWriteScope(
        blockId: 'block-1',
        propertyKey: WebsiteBlockMetaFields.blockHeight.key,
        policy: WebsiteBlockMetaFields.blockHeight.responsivePolicy,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.tablet,
      );
      final target = blockTarget(
        viewport: WebsiteViewport.tablet,
        properties: <WebsiteInlineManipulationProperty>[
          WebsiteInlineManipulationProperty.fromSchema(
            WebsiteBlockMetaFields.blockHeight,
          ),
        ],
      );
      WebsiteInlineManipulationLease? lease;
      final previews = <double>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockResizeHandle(
              currentHeight: 300,
              isActive: true,
              snapIncrement: 10,
              onHeightChangeStart: (_) {
                lease = provider.beginInlineManipulation(target);
                return lease != null;
              },
              onHeightChanged: previews.add,
              onHeightChangeEnd: (value) {
                final active = lease;
                lease = null;
                if (active != null) {
                  provider.commitInlineManipulation(
                    active,
                    <String, Object?>{
                      WebsiteBlockMetaFields.blockHeight.key: value,
                    },
                  );
                }
              },
              onHeightChangeCancel: () {
                final active = lease;
                lease = null;
                if (active != null) {
                  provider.cancelInlineManipulation(active);
                }
              },
            ),
          ),
        ),
      );

      final handle = find.byType(BlockResizeHandle);
      final drag = await tester.startGesture(tester.getCenter(handle));
      await drag.moveBy(const Offset(0, 50));
      await tester.pump();
      expect(previews, isNotEmpty);
      expect(dataOf(provider)['blockHeight'], 300.0);
      expect(provider.canUndo, isFalse);
      await drag.up();
      await tester.pump();

      expect(dataOf(provider)['blockHeight'], 300.0);
      expect(viewportData(provider, 'tablet')['blockHeight'], 350.0);
      expect(viewportData(provider, 'mobile'), isEmpty);
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(provider.canUndo, isFalse);

      final original = dataOf(provider);
      final cancelled = await tester.startGesture(tester.getCenter(handle));
      await cancelled.moveBy(const Offset(0, 80));
      await tester.pump();
      await cancelled.cancel();
      await tester.pump();

      expect(dataOf(provider), original);
      expect(provider.canUndo, isFalse);
      expect(provider.inlineManipulationSession, isNull);
    });
  });

  group('texto inline compuesto', () {
    WebsiteInlineManipulationTarget textTarget() => blockTarget(
          viewport: WebsiteViewport.mobile,
          properties: <WebsiteInlineManipulationProperty>[
            WebsiteInlineManipulationProperty(
              canonicalKey: 'text',
              policy: WebsiteResponsivePropertyPolicy.sharedOnly,
            ),
            WebsiteInlineManipulationProperty(
              canonicalKey: 'formatting',
              policy: WebsiteResponsivePropertyPolicy.sharedOnly,
            ),
            WebsiteInlineManipulationProperty(
              canonicalKey: 'maxWidth',
              policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
            ),
          ],
        );

    Widget textHost(WebsiteEditModeProvider provider) {
      WebsiteInlineManipulationLease? lease;
      return MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 900)),
          child: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(height: 140),
                SizedBox(
                  width: 350,
                  child: InlineEditableTextV2(
                    text: 'Original',
                    maxLines: 1,
                    isEditMode: true,
                    formatting: const TextFormatting(),
                    maxWidth: 320,
                    toolbarPreset: TextToolbarPreset.minimal,
                    onSessionStart: () {
                      lease = provider.beginInlineManipulation(textTarget());
                      return lease;
                    },
                    onSessionCommit: (session, value) {
                      if (session is! WebsiteInlineManipulationLease ||
                          !identical(session, lease)) {
                        return false;
                      }
                      lease = null;
                      return provider.commitInlineManipulation(
                        session,
                        <String, Object?>{
                          'text': value.text,
                          'formatting': value.formatting.toJson(),
                          'maxWidth': value.maxWidth,
                        },
                      );
                    },
                    onSessionCancel: (session) {
                      if (session is WebsiteInlineManipulationLease &&
                          identical(session, lease)) {
                        lease = null;
                        provider.cancelInlineManipulation(session);
                      }
                    },
                  ),
                ),
                const SizedBox(key: ValueKey<String>('outside'), height: 200),
              ],
            ),
          ),
        ),
      );
    }

    WebsiteEditModeProvider textProvider() {
      final provider = providerFor(<String, dynamic>{
        'text': 'Original',
        'formatting': <String, dynamic>{},
        'maxWidth': 320.0,
      });
      provider.setFieldWriteScope(
        blockId: 'block-1',
        propertyKey: 'maxWidth',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      return provider;
    }

    testWidgets('texto, formato y ancho táctil crean una sola transacción',
        (tester) async {
      final provider = textProvider();
      final original = dataOf(provider);
      await tester.pumpWidget(textHost(provider));

      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget);

      final rightHandle = find.byKey(
        const ValueKey<String>('website-text-width-handle-right'),
      );
      expect(tester.getSize(rightHandle).width, 48);
      await tester.drag(rightHandle, const Offset(20, 0));
      await tester.pump();
      expect(dataOf(provider), original, reason: 'resize queda local');

      await tester.enterText(find.byType(EditableText), 'Texto final');
      await tester.tap(find.byTooltip('Negrita (Ctrl+B)'));
      await tester.pump();
      expect(dataOf(provider), original, reason: 'toolbar queda local');

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pump();

      final data = dataOf(provider);
      expect(data['text'], 'Texto final');
      expect(data['formatting'], containsPair('bold', true));
      expect(data['maxWidth'], 320.0);
      expect(viewportData(provider, 'mobile')['maxWidth'], 360.0);
      expect(provider.canUndo, isTrue);

      provider.undo();
      expect(dataOf(provider), original);
      expect(provider.canUndo, isFalse, reason: 'todo el editor fue un undo');
    });

    testWidgets('Escape descarta copy/formato locales con cero escrituras',
        (tester) async {
      final provider = textProvider();
      final original = dataOf(provider);
      await tester.pumpWidget(textHost(provider));

      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'No persistir');
      await tester.tap(find.byTooltip('Negrita (Ctrl+B)'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(dataOf(provider), original);
      expect(provider.canUndo, isFalse);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.inlineManipulationSession, isNull);
      expect(find.text('Original'), findsOneWidget);
    });
  });
}
