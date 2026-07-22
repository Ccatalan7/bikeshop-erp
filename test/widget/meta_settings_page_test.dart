import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/settings/pages/meta_settings_page.dart';
import 'package:vinabike_erp/modules/settings/services/meta_settings_service.dart';

void main() {
  testWidgets('staff can inspect and refresh but cannot authorize',
      (tester) async {
    final gateway = _FakeMetaSettingsGateway(
      snapshot: _snapshot(role: 'employee'),
    );

    await tester.pumpWidget(
      MaterialApp(home: MetaSettingsPage(service: gateway)),
    );
    await tester.pump();

    expect(find.text('Instagram y Messenger'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('Viñabike'), findsOneWidget);
    expect(find.text('Conectado'), findsOneWidget);
    expect(
      find.textContaining('Solo administradores y managers'),
      findsOneWidget,
    );

    final connectButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('meta-connect')),
    );
    expect(connectButton.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('meta-refresh')));
    await tester.pump();
    expect(gateway.loadCount, 2);
    expect(gateway.launchCount, 0);
  });

  testWidgets('admin explicitly confirms before opening Meta', (tester) async {
    final gateway = _FakeMetaSettingsGateway(
      snapshot: _snapshot(role: 'admin'),
    );

    await tester.pumpWidget(
      MaterialApp(home: MetaSettingsPage(service: gateway)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('meta-connect')));
    await tester.pumpAndSettle();

    expect(find.text('Continuar en Meta'), findsOneWidget);
    expect(
      find.textContaining('La conexión no cambia'),
      findsOneWidget,
    );
    expect(gateway.launchCount, 0);

    await tester.tap(find.text('Abrir Meta'));
    await tester.pumpAndSettle();

    expect(gateway.launchCount, 1);
    expect(
      find.textContaining('Completa la autorización allí'),
      findsOneWidget,
    );
  });

  testWidgets('inactive admin can inspect but cannot authorize',
      (tester) async {
    final gateway = _FakeMetaSettingsGateway(
      snapshot: _snapshot(role: 'admin', isProfileActive: false),
    );

    await tester.pumpWidget(
      MaterialApp(home: MetaSettingsPage(service: gateway)),
    );
    await tester.pump();

    expect(find.textContaining('acceso de trabajador está inactivo'),
        findsOneWidget);
    final connectButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('meta-connect')),
    );
    expect(connectButton.onPressed, isNull);
    expect(gateway.launchCount, 0);
  });
}

MetaSettingsSnapshot _snapshot({
  required String role,
  bool isProfileActive = true,
}) {
  return MetaSettingsSnapshot(
    tenantId: '5443b130-cc28-45af-a420-cd500b288890',
    role: role,
    isProfileActive: isProfileActive,
    channels: [
      MetaChannelStatus(
        id: 'instagram-channel',
        provider: MetaChannelProvider.instagram,
        externalAccountId: '17840000000000000',
        displayName: 'Viñabike',
        username: 'vina.bike',
        grantedPermissions: const [
          'pages_show_list',
          'pages_messaging',
          'pages_manage_metadata',
          'pages_read_engagement',
          'instagram_basic',
          'instagram_manage_messages',
          'instagram_manage_comments',
        ],
        authorizationExpiresAt: DateTime.utc(2030),
        subscribedAt: DateTime.utc(2026, 7, 21),
        updatedAt: DateTime.utc(2026, 7, 21, 12),
        isActive: true,
      ),
    ],
  );
}

class _FakeMetaSettingsGateway implements MetaSettingsGateway {
  final MetaSettingsSnapshot snapshot;
  int loadCount = 0;
  int launchCount = 0;

  _FakeMetaSettingsGateway({required this.snapshot});

  @override
  Future<MetaSettingsSnapshot> loadSnapshot() async {
    loadCount += 1;
    return snapshot;
  }

  @override
  Future<void> launchAuthorization({required String tenantId}) async {
    expect(tenantId, '5443b130-cc28-45af-a420-cd500b288890');
    launchCount += 1;
  }
}
