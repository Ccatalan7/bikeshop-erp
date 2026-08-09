import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/google_business_service.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantA = '00000000-0000-4000-8000-00000000000a';
const _tenantB = '00000000-0000-4000-8000-00000000000b';
const _leaseA = WebsiteEditorCapabilitySnapshot(
  identity: 'user-a',
  activeTenantId: _tenantA,
  storefrontTenantId: _tenantA,
  hasAuthority: true,
);
const _leaseB = WebsiteEditorCapabilitySnapshot(
  identity: 'user-b',
  activeTenantId: _tenantB,
  storefrontTenantId: _tenantB,
  hasAuthority: true,
);

class _FakeGoogleBusinessService extends GoogleBusinessService {
  Completer<List<GoogleLocation>>? pendingLocations;
  Completer<List<Map<String, dynamic>>>? pendingReviews;
  List<GoogleLocation> locations = const <GoogleLocation>[];
  List<Map<String, dynamic>> reviews = const <Map<String, dynamic>>[];
  int locationFetches = 0;
  int reviewFetches = 0;

  @override
  bool get hasProviderToken => true;

  @override
  bool get isLinked => true;

  @override
  bool get isLoading => false;

  @override
  Future<List<GoogleLocation>> fetchLocations() {
    locationFetches++;
    return pendingLocations?.future ?? Future.value(locations);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReviews(String locationName) {
    reviewFetches++;
    return pendingReviews?.future ?? Future.value(reviews);
  }
}

class _FakeWebsiteService extends WebsiteService {
  _FakeWebsiteService({Map<String, String> settings = const {}})
      : _settings = Map<String, String>.from(settings),
        super(
          supabase: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          tenantService: TenantService.testing(
            currentUserId: () => null,
            profileLookup: (_) async => const <Map<String, dynamic>>[],
          ),
        );

  final Map<String, String> _settings;
  final List<({String tenantId, Map<String, String> values})> writes = [];
  void Function()? duringWrite;

  @override
  String getSetting(String key, [String defaultValue = '']) =>
      _settings[key] ?? defaultValue;

  @override
  Future<void> saveSettingsForTenant(
    String tenantId,
    Map<String, String> settings, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    writeGuard?.call();
    duringWrite?.call();
    writeGuard?.call();
    final copy = Map<String, String>.from(settings);
    writes.add((tenantId: tenantId, values: copy));
    _settings.addAll(copy);
  }
}

WebsiteEditModeProvider _provider(
  WebsiteEditorCapabilitySnapshot lease, {
  Map<String, dynamic> settings = const <String, dynamic>{},
}) {
  final provider = WebsiteEditModeProvider();
  provider.adoptEditorEntryLease(provider.editorEntryLeaseGeneration, lease);
  provider.enterEditMode(
    const <Map<String, dynamic>>[],
    settings,
    pageId: 'home',
    pageSlug: '',
  );
  return provider;
}

GoogleLocation _location() => GoogleLocation(
      name: 'accounts/a/locations/location-a',
      title: 'Tienda A',
      phone: '+56 9 1111 1111',
      addressLine: 'Calle A 123, Santiago',
      addressStreet: 'Calle A 123',
      addressCity: 'Santiago',
      addressRegion: 'RM',
      addressPostalCode: '8320000',
      addressCountry: 'Chile',
      hours: const <String, dynamic>{'MONDAY': '09:00-18:00'},
      mapsUri: 'https://maps.example/location-a',
      newReviewUri: 'https://reviews.example/location-a',
    );

Widget _host({
  required ValueNotifier<WebsiteEditModeProvider> activeProvider,
  required _FakeGoogleBusinessService googleService,
  required _FakeWebsiteService websiteService,
}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: SizedBox(
        width: 430,
        height: 900,
        child: ValueListenableBuilder<WebsiteEditModeProvider>(
          valueListenable: activeProvider,
          builder: (context, provider, _) => MultiProvider(
            providers: [
              ChangeNotifierProvider<WebsiteEditModeProvider>.value(
                value: provider,
              ),
              ChangeNotifierProvider<GoogleBusinessService>.value(
                value: googleService,
              ),
              ChangeNotifierProvider<WebsiteService>.value(
                value: websiteService,
              ),
            ],
            child: const WebsiteEditorPanel(),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openGoogleTab(WidgetTester tester) async {
  final google = find.text('Google');
  if (google.evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('vb-sub-tabs-overflow')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Google').last);
  await tester.pumpAndSettle();
  expect(find.text('Sincronizar Datos'), findsOneWidget);
}

Future<void> _tapSyncAction(WidgetTester tester, String label) async {
  final action = find.text(label);
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('locations A to B during fetch performs zero writes',
      (tester) async {
    final providerA = _provider(_leaseA);
    final providerB = _provider(_leaseB);
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final google = _FakeGoogleBusinessService()
      ..pendingLocations = Completer<List<GoogleLocation>>();
    final website = _FakeWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(google.dispose);
    addTearDown(website.dispose);

    await tester.pumpWidget(_host(
      activeProvider: activeProvider,
      googleService: google,
      websiteService: website,
    ));
    await tester.pumpAndSettle();
    await _openGoogleTab(tester);
    await _tapSyncAction(tester, 'Sincronizar Datos');
    await tester.pump();
    expect(google.locationFetches, 1);

    activeProvider.value = providerB;
    await tester.pump();
    google.pendingLocations!.complete(<GoogleLocation>[_location()]);
    await tester.pumpAndSettle();
    expect(website.writes, isEmpty);
    expect(find.text('Seleccionar Ubicación'), findsNothing);
  });

  testWidgets('locations A to B to A during fetch is rejected as ABA',
      (tester) async {
    final providerA = _provider(_leaseA);
    final providerB = _provider(_leaseB);
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final google = _FakeGoogleBusinessService()
      ..pendingLocations = Completer<List<GoogleLocation>>();
    final website = _FakeWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(google.dispose);
    addTearDown(website.dispose);

    await tester.pumpWidget(_host(
      activeProvider: activeProvider,
      googleService: google,
      websiteService: website,
    ));
    await tester.pumpAndSettle();
    await _openGoogleTab(tester);
    await _tapSyncAction(tester, 'Sincronizar Datos');
    await tester.pump();

    activeProvider.value = providerB;
    await tester.pump();
    activeProvider.value = providerA;
    await tester.pump();
    google.pendingLocations!.complete(<GoogleLocation>[_location()]);
    await tester.pumpAndSettle();
    expect(website.writes, isEmpty);
  });

  testWidgets('rapid double tap starts exactly one locations operation',
      (tester) async {
    final providerA = _provider(_leaseA);
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final google = _FakeGoogleBusinessService()
      ..pendingLocations = Completer<List<GoogleLocation>>();
    final website = _FakeWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(google.dispose);
    addTearDown(website.dispose);

    await tester.pumpWidget(_host(
      activeProvider: activeProvider,
      googleService: google,
      websiteService: website,
    ));
    await tester.pumpAndSettle();
    await _openGoogleTab(tester);
    await _tapSyncAction(tester, 'Sincronizar Datos');
    await tester.pump();
    await tester.tap(find.text('Sincronizar Datos'));
    await tester.pump();
    await tester.ensureVisible(find.text('Sincronizar Reseñas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sincronizar Reseñas'));
    await tester.pump();

    expect(google.locationFetches, 1);
    expect(google.reviewFetches, 0,
        reason: 'locations and reviews share one remote single-flight');
    google.pendingLocations!.complete(const <GoogleLocation>[]);
    await tester.pumpAndSettle();
    expect(website.writes, isEmpty);
  });

  testWidgets('provider change while location dialog is open writes nothing',
      (tester) async {
    final providerA = _provider(_leaseA);
    final providerB = _provider(_leaseB);
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final google = _FakeGoogleBusinessService()
      ..locations = <GoogleLocation>[_location()];
    final website = _FakeWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(google.dispose);
    addTearDown(website.dispose);

    await tester.pumpWidget(_host(
      activeProvider: activeProvider,
      googleService: google,
      websiteService: website,
    ));
    await tester.pumpAndSettle();
    await _openGoogleTab(tester);
    await _tapSyncAction(tester, 'Sincronizar Datos');
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar Ubicación'), findsOneWidget);

    activeProvider.value = providerB;
    await tester.pump();
    await tester.tap(find.text('Tienda A'));
    await tester.pumpAndSettle();
    expect(website.writes, isEmpty);
  });

  testWidgets('valid location selection is one atomic tenant-A write',
      (tester) async {
    final providerA = _provider(_leaseA);
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final google = _FakeGoogleBusinessService()
      ..locations = <GoogleLocation>[_location()];
    final website = _FakeWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(google.dispose);
    addTearDown(website.dispose);

    await tester.pumpWidget(_host(
      activeProvider: activeProvider,
      googleService: google,
      websiteService: website,
    ));
    await tester.pumpAndSettle();
    await _openGoogleTab(tester);
    await _tapSyncAction(tester, 'Sincronizar Datos');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tienda A'));
    await tester.pumpAndSettle();

    expect(website.writes, hasLength(1));
    expect(website.writes.single.tenantId, _tenantA);
    expect(
      website.writes.single.values['business_google_location_id'],
      'accounts/a/locations/location-a',
    );
    expect(website.writes.single.values['business_phone'], '+56 9 1111 1111');
    expect(website.writes.single.values['seo_google_maps_url'],
        'https://maps.example/location-a');
  });

  testWidgets('reviews A to B during fetch performs zero writes',
      (tester) async {
    const settings = <String, dynamic>{
      'business_google_location_id': 'accounts/a/locations/location-a',
    };
    final providerA = _provider(_leaseA, settings: settings);
    final providerB = _provider(_leaseB, settings: settings);
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final google = _FakeGoogleBusinessService()
      ..pendingReviews = Completer<List<Map<String, dynamic>>>();
    final website = _FakeWebsiteService(settings: const <String, String>{
      'business_google_location_id': 'accounts/a/locations/location-a',
    });
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(google.dispose);
    addTearDown(website.dispose);

    await tester.pumpWidget(_host(
      activeProvider: activeProvider,
      googleService: google,
      websiteService: website,
    ));
    await tester.pumpAndSettle();
    await _openGoogleTab(tester);
    await _tapSyncAction(tester, 'Sincronizar Reseñas');
    await tester.pump();
    expect(google.reviewFetches, 1);

    activeProvider.value = providerB;
    await tester.pump();
    google.pendingReviews!.complete(<Map<String, dynamic>>[
      <String, dynamic>{'name': 'reviews/a'},
    ]);
    await tester.pumpAndSettle();
    expect(website.writes, isEmpty);
  });

  testWidgets('valid reviews sync is one tenant-explicit write',
      (tester) async {
    const settings = <String, dynamic>{
      'business_google_location_id': 'accounts/a/locations/location-a',
    };
    final providerA = _provider(_leaseA, settings: settings);
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final google = _FakeGoogleBusinessService()
      ..reviews = <Map<String, dynamic>>[
        <String, dynamic>{'name': 'reviews/a', 'rating': 5},
      ];
    final website = _FakeWebsiteService(settings: const <String, String>{
      'business_google_location_id': 'accounts/a/locations/location-a',
    });
    addTearDown(providerA.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(google.dispose);
    addTearDown(website.dispose);

    await tester.pumpWidget(_host(
      activeProvider: activeProvider,
      googleService: google,
      websiteService: website,
    ));
    await tester.pumpAndSettle();
    await _openGoogleTab(tester);
    await _tapSyncAction(tester, 'Sincronizar Reseñas');
    await tester.pumpAndSettle();

    expect(website.writes, hasLength(1));
    expect(website.writes.single.tenantId, _tenantA);
    expect(
      website.writes.single.values.keys,
      const <String>['google_reviews_data'],
    );
    expect(
      website.writes.single.values['google_reviews_data'],
      contains('reviews/a'),
    );
  });
}
