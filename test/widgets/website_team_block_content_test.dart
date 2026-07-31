import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_team_block_content.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

Future<void> _pumpTeam(
  WidgetTester tester, {
  required double width,
  required Map<String, dynamic> data,
  bool previewMode = false,
  void Function(String route)? onNavigate,
  bool Function(String href)? isNavigationEligible,
  WebsiteBlockContentPresenters? presenters,
  WebsiteTeamImageProviderBuilder? imageProviderBuilder,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      WebsiteTeamBlockContent(
        data: data,
        accentColor: const Color(0xFF008F8C),
        previewMode: previewMode,
        onNavigate: onNavigate,
        isNavigationEligible: isNavigationEligible,
        presenters: presenters,
        imageProviderBuilder: imageProviderBuilder,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'uses approved 300px cards above 600 and full useful width below 600',
    (tester) async {
      const data = <String, dynamic>{
        'title': 'Equipo',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Ana'},
          <String, dynamic>{'name': 'Beto'},
          <String, dynamic>{'name': 'Carla'},
        ],
      };

      for (final testCase in <({double width, double cardWidth})>[
        (width: 1440, cardWidth: 300),
        (width: 834, cardWidth: 300),
        (width: 390, cardWidth: 342),
      ]) {
        await _pumpTeam(
          tester,
          width: testCase.width,
          data: data,
        );

        expect(
          tester
              .getSize(
                find.byKey(WebsiteTeamBlockContent.memberCardKey(0)),
              )
              .width,
          closeTo(testCase.cardWidth, 0.01),
          reason: 'width ${testCase.width}',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('empty collection renders no fabricated members', (tester) async {
    await _pumpTeam(
      tester,
      width: 834,
      data: const <String, dynamic>{
        'title': 'Equipo real',
        'members': <Map<String, dynamic>>[],
      },
    );

    expect(find.text('Equipo real'), findsOneWidget);
    expect(find.byKey(WebsiteTeamBlockContent.membersKey), findsNothing);
    expect(find.text('Nombre del integrante'), findsNothing);
    expect(find.text('Integrante 2'), findsNothing);
    expect(find.textContaining('Usa el editor'), findsNothing);
  });

  testWidgets(
    'legacy aliases feed real content and nested text/media targets',
    (tester) async {
      final textSlots = <String, WebsiteInlineTextSlot>{};
      final mediaSlots = <String, WebsiteInlineMediaSlot>{};
      final presenters = WebsiteBlockContentPresenters(
        text: (context, slot) {
          textSlots[slot.id] = slot;
          return Text(slot.value);
        },
        media: (context, slot) {
          mediaSlots[slot.id] = slot;
          return slot.fallback;
        },
      );

      await _pumpTeam(
        tester,
        width: 834,
        presenters: presenters,
        data: const <String, dynamic>{
          'title': 'Especialistas',
          'subtitle': 'Taller certificado',
          'team': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'member-1',
              'name': 'Andrea',
              'role': 'Mecánica',
              'bio': 'Especialista en suspensiones',
              'image': 'https://invalid.local/andrea.jpg',
              'avatarAltText': 'Andrea en el taller',
            },
          ],
        },
      );

      expect(find.text('Taller certificado'), findsOneWidget);
      expect(find.text('Andrea'), findsOneWidget);
      expect(find.text('Especialista en suspensiones'), findsOneWidget);

      final description = textSlots['team.description']!;
      expect(description.valueKeys, <String>['description', 'subtitle']);

      final name = textSlots['team.member.0.name']!;
      expect(name.valueKeys, <String>['name']);
      expect(
        name.repeaterTarget!.collectionKeys,
        <String>['members', 'team', 'items'],
      );
      expect(name.repeaterTarget!.itemIndex, 0);
      expect(name.repeaterTarget!.identityKey, 'id');
      expect(name.repeaterTarget!.identityValue, 'member-1');

      final avatar = mediaSlots['team.member.0.avatar']!;
      expect(avatar.url, 'https://invalid.local/andrea.jpg');
      expect(avatar.valueKeys, <String>['avatarUrl', 'image']);
      expect(avatar.semanticLabel, 'Andrea en el taller');
      expect(avatar.repeaterTarget, same(name.repeaterTarget));
    },
  );

  testWidgets(
    'explicit canonical empty values do not revive stale aliases',
    (tester) async {
      await _pumpTeam(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Equipo',
          'description': '',
          'subtitle': 'Descripción obsoleta',
          'members': <Map<String, dynamic>>[],
          'team': <Map<String, dynamic>>[
            <String, dynamic>{'name': 'Integrante obsoleto'},
          ],
        },
      );

      expect(find.text('Descripción obsoleta'), findsNothing);
      expect(find.text('Integrante obsoleto'), findsNothing);
      expect(find.byKey(WebsiteTeamBlockContent.membersKey), findsNothing);
    },
  );

  testWidgets(
    'social links honor eligibility and navigate only in public mode',
    (tester) async {
      final navigations = <String>[];
      const data = <String, dynamic>{
        'members': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Andrea',
            'instagram': '/equipo/andrea',
            'linkedin': '/bloqueado',
          },
        ],
      };

      await _pumpTeam(
        tester,
        width: 834,
        data: data,
        onNavigate: navigations.add,
        isNavigationEligible: (href) => href == '/equipo/andrea',
      );

      expect(find.byTooltip('Instagram'), findsOneWidget);
      expect(find.byTooltip('LinkedIn'), findsNothing);
      final publicButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.camera_alt_outlined),
      );
      expect(publicButton.onPressed, isNotNull);
      await tester.tap(find.byTooltip('Instagram'));
      expect(navigations, <String>['/equipo/andrea']);

      await _pumpTeam(
        tester,
        width: 834,
        data: data,
        previewMode: true,
        onNavigate: navigations.add,
        isNavigationEligible: (href) => href == '/equipo/andrea',
      );
      final previewButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.camera_alt_outlined),
      );
      expect(previewButton.onPressed, isNull);
      expect(navigations, <String>['/equipo/andrea']);
    },
  );

  testWidgets(
      'avatar missing and decode failure use an honest semantic fallback',
      (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final invalidBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    await _pumpTeam(
      tester,
      width: 834,
      imageProviderBuilder: (_) => MemoryImage(invalidBytes),
      data: const <String, dynamic>{
        'members': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Andrea',
            'avatarUrl': 'memory://invalid',
            'avatarAltText': 'Retrato de Andrea',
          },
          <String, dynamic>{
            'name': 'Beto',
            'avatarUrl': '',
          },
        ],
      },
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(WebsiteTeamBlockContent.memberAvatarFallbackKey(0)),
      findsOneWidget,
    );
    expect(
      find.byKey(WebsiteTeamBlockContent.memberAvatarFallbackKey(1)),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Retrato de Andrea'), findsOneWidget);
    expect(find.bySemanticsLabel('Foto de Beto'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semanticsHandle.dispose();
  });
}
