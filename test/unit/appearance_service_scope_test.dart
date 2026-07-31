import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('legacy device preferences migrate to one exact ERP authority',
      () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'sidebar_palette': 'pacific',
      'quick_chat_uses_sidebar_palette': true,
      'right_toolbar_over_content': false,
      'right_toolbar_blur_enabled': false,
    });
    final service = _service();
    addTearDown(service.dispose);

    await _synchronize(service, userId: 'user-a', tenantId: 'tenant-a');

    expect(service.themeMode, ThemeMode.dark);
    expect(service.sidebarPaletteCode, 'pacific');
    expect(service.messagingUsesSidebarPalette, isTrue);
    expect(service.rightToolbarOverContent, isFalse);
    expect(service.rightToolbarBlurEnabled, isFalse);

    final preferences = await SharedPreferences.getInstance();
    final migrated = _decodedEnvelope(
      preferences,
      tenantId: 'tenant-a',
      userId: 'user-a',
    );
    expect(migrated['tenant_id'], 'tenant-a');
    expect(migrated['user_id'], 'user-a');
    expect(migrated['theme_mode'], 'dark');
    expect(
      preferences.getString('vinabike_appearance_legacy_claim_v1'),
      'tenant-a:user-a',
    );
    expect(preferences.get('theme_mode'), isNull);
    expect(preferences.get('sidebar_palette'), isNull);

    await _synchronize(service, userId: null, tenantId: null);
    await _synchronize(service, userId: 'user-b', tenantId: 'tenant-a');

    expect(service.themeMode, ThemeMode.light);
    expect(service.sidebarPaletteCode, 'vinabike');
    expect(service.messagingUsesSidebarPalette, isFalse);
    expect(service.rightToolbarOverContent, isTrue);
    expect(service.rightToolbarBlurEnabled, isTrue);
  });

  test('each tenant and user restores an independent appearance', () async {
    final service = _service();
    addTearDown(service.dispose);

    await _synchronize(service, userId: 'user-a', tenantId: 'tenant-a');
    await service.setThemeMode(ThemeMode.dark);
    await service.setSidebarPalette('pacific');
    await service.setMessagingUsesSidebarPalette(true);
    await service.setRightToolbarOverContent(false);
    await service.setRightToolbarBlurEnabled(false);

    await _synchronize(service, userId: 'user-b', tenantId: 'tenant-a');
    expect(service.themeMode, ThemeMode.light);
    expect(service.sidebarPaletteCode, 'vinabike');
    await service.setThemeMode(ThemeMode.system);
    await service.setSidebarPalette('evergreen');

    await _synchronize(service, userId: 'user-a', tenantId: 'tenant-a');
    expect(service.themeMode, ThemeMode.dark);
    expect(service.sidebarPaletteCode, 'pacific');
    expect(service.messagingUsesSidebarPalette, isTrue);
    expect(service.rightToolbarOverContent, isFalse);
    expect(service.rightToolbarBlurEnabled, isFalse);

    await _synchronize(service, userId: 'user-b', tenantId: 'tenant-a');
    expect(service.themeMode, ThemeMode.system);
    expect(service.sidebarPaletteCode, 'evergreen');
  });

  test('late company settings from a previous identity never publish',
      () async {
    final tenantAStarted = Completer<void>();
    final tenantBStarted = Completer<void>();
    final tenantAResult = Completer<List<Map<String, dynamic>>>();
    final tenantBResult = Completer<List<Map<String, dynamic>>>();
    final service = AppearanceService(
      companySettingsLoader: (tenantId) {
        if (tenantId == 'tenant-a') {
          tenantAStarted.complete();
          return tenantAResult.future;
        }
        tenantBStarted.complete();
        return tenantBResult.future;
      },
    );
    addTearDown(service.dispose);

    final oldLoad = _synchronize(
      service,
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    await tenantAStarted.future;
    final newLoad = _synchronize(
      service,
      userId: 'user-b',
      tenantId: 'tenant-b',
    );
    await tenantBStarted.future;

    tenantBResult.complete([
      {'key': 'company_logo', 'value': 'https://example.com/b.png'},
    ]);
    await newLoad;
    tenantAResult.complete([
      {'key': 'company_logo', 'value': 'https://example.com/a.png'},
    ]);
    await oldLoad;

    expect(service.companyLogoUrl, startsWith('https://example.com/b.png?'));
    expect(service.hasLoadedWithTenant, isTrue);
  });

  test('sign-out resets immediately and rejects an in-flight company load',
      () async {
    final companyLoadStarted = Completer<void>();
    final companyResult = Completer<List<Map<String, dynamic>>>();
    final service = AppearanceService(
      companySettingsLoader: (_) {
        companyLoadStarted.complete();
        return companyResult.future;
      },
    );
    addTearDown(service.dispose);

    final oldLoad = _synchronize(
      service,
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    await companyLoadStarted.future;
    await service.setThemeMode(ThemeMode.dark);

    await _synchronize(service, userId: null, tenantId: null);
    expect(service.themeMode, ThemeMode.light);
    expect(service.companyLogoUrl, isNull);
    expect(service.hasLoadedWithTenant, isFalse);

    companyResult.complete([
      {'key': 'company_logo', 'value': 'https://example.com/old.png'},
    ]);
    await oldLoad;

    expect(service.themeMode, ThemeMode.light);
    expect(service.companyLogoUrl, isNull);
    expect(service.hasLoadedWithTenant, isFalse);
  });

  test('late tenant resolution cannot establish the previous user scope',
      () async {
    final tenantA = Completer<String?>();
    final service = _service();
    addTearDown(service.dispose);

    final oldLoad = service.synchronize(
      userId: 'user-a',
      resolveTenantId: () => tenantA.future,
    );
    await Future<void>.delayed(Duration.zero);
    await _synchronize(service, userId: 'user-b', tenantId: 'tenant-b');
    tenantA.complete('tenant-a');
    await oldLoad;
    await service.setThemeMode(ThemeMode.dark);

    final preferences = await SharedPreferences.getInstance();
    expect(
      _decodedEnvelope(
        preferences,
        tenantId: 'tenant-b',
        userId: 'user-b',
      )['theme_mode'],
      'dark',
    );
    expect(
      preferences.getString(_storageKey('tenant-a', 'user-a')),
      isNull,
    );
  });

  test(
      'same user tenant change invalidates authority while resolution is pending',
      () async {
    SharedPreferences.setMockInitialValues({
      _storageKey('tenant-a', 'user-a'): jsonEncode({
        'version': 2,
        'tenant_id': 'tenant-a',
        'user_id': 'user-a',
        'theme_mode': 'dark',
        'sidebar_palette': 'pacific',
        'quick_chat_uses_sidebar_palette': true,
        'right_toolbar_over_content': false,
        'right_toolbar_blur_enabled': false,
      }),
      _storageKey('tenant-b', 'user-a'): jsonEncode({
        'version': 2,
        'tenant_id': 'tenant-b',
        'user_id': 'user-a',
        'theme_mode': 'light',
        'sidebar_palette': 'evergreen',
        'quick_chat_uses_sidebar_palette': false,
        'right_toolbar_over_content': true,
        'right_toolbar_blur_enabled': true,
      }),
    });
    final service = _service();
    addTearDown(service.dispose);

    await _synchronize(service, userId: 'user-a', tenantId: 'tenant-a');
    expect(service.themeMode, ThemeMode.dark);
    expect(service.sidebarPaletteCode, 'pacific');

    final tenantB = Completer<String?>();
    final tenantChange = service.synchronize(
      userId: 'user-a',
      resolveTenantId: () => tenantB.future,
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.isLoading, isTrue);
    await expectLater(
      service.setThemeMode(ThemeMode.system),
      throwsA(isA<StateError>()),
    );

    final preferences = await SharedPreferences.getInstance();
    expect(
      _decodedEnvelope(
        preferences,
        tenantId: 'tenant-b',
        userId: 'user-a',
      )['theme_mode'],
      'light',
    );

    tenantB.complete('tenant-b');
    await tenantChange;

    expect(service.themeMode, ThemeMode.light);
    expect(service.sidebarPaletteCode, 'evergreen');
    expect(service.messagingUsesSidebarPalette, isFalse);
    expect(service.rightToolbarOverContent, isTrue);
    expect(service.rightToolbarBlurEnabled, isTrue);
    final tenantBEnvelope = _decodedEnvelope(
      preferences,
      tenantId: 'tenant-b',
      userId: 'user-a',
    );
    expect(tenantBEnvelope['theme_mode'], 'light');
    expect(tenantBEnvelope['sidebar_palette'], 'evergreen');
  });

  test('an appearance change during initial load merges only its dirty field',
      () async {
    SharedPreferences.setMockInitialValues({
      _storageKey('tenant-a', 'user-a'): jsonEncode({
        'version': 2,
        'tenant_id': 'tenant-a',
        'user_id': 'user-a',
        'theme_mode': 'light',
        'sidebar_palette': 'pacific',
        'quick_chat_uses_sidebar_palette': true,
        'right_toolbar_over_content': false,
        'right_toolbar_blur_enabled': false,
      }),
    });
    final storedPreferences = await SharedPreferences.getInstance();
    final loaderStarted = Completer<void>();
    final releaseLoader = Completer<void>();
    final service = AppearanceService(
      preferencesLoader: () async {
        if (!loaderStarted.isCompleted) loaderStarted.complete();
        await releaseLoader.future;
        return storedPreferences;
      },
      companySettingsLoader: (_) async => [],
    );
    addTearDown(service.dispose);

    final load = _synchronize(
      service,
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    await loaderStarted.future;
    final userChange = service.setThemeMode(ThemeMode.dark);
    expect(service.themeMode, ThemeMode.dark);
    releaseLoader.complete();
    await Future.wait([load, userChange]);

    expect(service.themeMode, ThemeMode.dark);
    expect(service.sidebarPaletteCode, 'pacific');
    expect(service.messagingUsesSidebarPalette, isTrue);
    expect(service.rightToolbarOverContent, isFalse);
    expect(service.rightToolbarBlurEnabled, isFalse);
    final envelope = _decodedEnvelope(
      storedPreferences,
      tenantId: 'tenant-a',
      userId: 'user-a',
    );
    expect(
      envelope['theme_mode'],
      'dark',
    );
    expect(envelope['sidebar_palette'], 'pacific');
    expect(envelope['quick_chat_uses_sidebar_palette'], isTrue);
    expect(envelope['right_toolbar_over_content'], isFalse);
    expect(envelope['right_toolbar_blur_enabled'], isFalse);
  });

  test('missing tenant fails closed without claiming legacy preferences',
      () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'sidebar_palette': 'pacific',
    });
    final service = _service();
    addTearDown(service.dispose);

    await _synchronize(service, userId: 'user-a', tenantId: null);

    expect(service.isInitialized, isTrue);
    expect(service.hasLoadedWithTenant, isFalse);
    expect(service.themeMode, ThemeMode.light);
    expect(service.sidebarPaletteCode, 'vinabike');
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('vinabike_appearance_legacy_claim_v1'),
      isNull,
    );
    expect(preferences.getString('theme_mode'), 'dark');
  });

  test('invalid scoped values heal to supported defaults', () async {
    SharedPreferences.setMockInitialValues({
      _storageKey('tenant-a', 'user-a'): jsonEncode({
        'version': 2,
        'tenant_id': 'tenant-a',
        'user_id': 'user-a',
        'theme_mode': 'sepia',
        'sidebar_palette': 'unknown',
        'quick_chat_uses_sidebar_palette': 'yes',
        'right_toolbar_over_content': 0,
        'right_toolbar_blur_enabled': null,
      }),
    });
    final service = _service();
    addTearDown(service.dispose);

    await _synchronize(service, userId: 'user-a', tenantId: 'tenant-a');

    expect(service.themeMode, ThemeMode.light);
    expect(service.sidebarPaletteCode, 'vinabike');
    expect(service.messagingUsesSidebarPalette, isFalse);
    expect(service.rightToolbarOverContent, isTrue);
    expect(service.rightToolbarBlurEnabled, isTrue);
  });
}

AppearanceService _service() {
  return AppearanceService(
    companySettingsLoader: (_) async => [],
  );
}

Future<void> _synchronize(
  AppearanceService service, {
  required String? userId,
  required String? tenantId,
}) {
  return service.synchronize(
    userId: userId,
    resolveTenantId: () async => tenantId,
  );
}

String _storageKey(String tenantId, String userId) {
  return 'vinabike_appearance_v2:$tenantId:$userId';
}

Map<String, dynamic> _decodedEnvelope(
  SharedPreferences preferences, {
  required String tenantId,
  required String userId,
}) {
  return Map<String, dynamic>.from(
    jsonDecode(preferences.getString(_storageKey(tenantId, userId))!) as Map,
  );
}
