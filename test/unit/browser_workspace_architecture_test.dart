import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded browser keeps one persistent profile and safe permissions',
      () {
    final browser = File(
      'lib/shared/widgets/webview_module_page.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/shared/services/browser_profile_service.dart',
    ).readAsStringSync();
    final siteMemory = File(
      'lib/shared/services/browser_site_memory_service.dart',
    ).readAsStringSync();
    final credentialAutofill = File(
      'lib/shared/utils/browser_credential_autofill.dart',
    ).readAsStringSync();
    final credentialVault = File(
      'lib/shared/services/browser_credential_vault.dart',
    ).readAsStringSync();
    final supplierCredentialResolver = File(
      'lib/shared/services/browser_supplier_credential_resolver.dart',
    ).readAsStringSync();
    final supplierPortalCatalog = File(
      'lib/shared/services/browser_supplier_portal_catalog.dart',
    ).readAsStringSync();
    final supplierForm = File(
      'lib/modules/purchases/pages/supplier_form_page.dart',
    ).readAsStringSync();
    final manager = File(
      'lib/shared/services/workspace_manager.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final debugEntitlements = File(
      'macos/Runner/DebugProfile.entitlements',
    ).readAsStringSync();
    final releaseEntitlements = File(
      'macos/Runner/Release.entitlements',
    ).readAsStringSync();
    final macosProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final iosDebugEntitlements = File(
      'ios/Runner/DebugProfile.entitlements',
    ).readAsStringSync();
    final iosReleaseEntitlements = File(
      'ios/Runner/Release.entitlements',
    ).readAsStringSync();
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final app = File('lib/main.dart').readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();
    final emptyKeychainAccessGroups = RegExp(
      r'<key>keychain-access-groups</key>\s*'
      r'<array(?:\s*/>|\s*>\s*</array>)',
    );
    final macosSandboxEnabled = RegExp(
      r'<key>com\.apple\.security\.app-sandbox</key>\s*<true\s*/>',
    );
    final forgetCredentialBlock = browser.substring(
      browser.indexOf('Future<void> _confirmForgetCurrentSiteCredentials()'),
      browser.indexOf('void _setCurrentUrl(WebUri? url)'),
    );
    final submittedCredentialBlock = browser.substring(
      browser.indexOf('Future<bool> _saveSubmittedBrowserCredential('),
      browser.indexOf('Future<void> _autofillSavedBrowserCredential('),
    );
    final autofillCredentialBlock = browser.substring(
      browser.indexOf('Future<void> _autofillSavedBrowserCredential('),
      browser.indexOf(
        'Future<BrowserSupplierCredentialLookupResult>',
      ),
    );

    expect(profile, contains('userDataFolder: userDataDirectory'));
    expect(profile, contains('_windowsEnvironments.putIfAbsent'));
    expect(browser, contains('BrowserProfileService.environmentForUser'));
    expect(browser, isNot(contains('Chrome/120.0.0.0')));
    expect(browser, isNot(contains('userAgent: _userAgent')));
    expect(browser, contains('_requestSitePermission(request)'));
    expect(siteMemory, contains("'vinabike_browser_sites_v1'"));
    expect(siteMemory, contains('static const maxEntries = 500'));
    expect(browser, contains('BrowserSiteMemoryService.recordVisit'));
    expect(browser, contains('unawaited(_loadBrowserHistory())'));
    expect(browser, contains('_BrowserAddressSuggestion.addressSite(site)'));
    expect(browser, contains('unawaited(_loadSupplierPortalCatalog())'));
    expect(browser, contains('buildBrowserSupplierPortalCatalog(suppliers)'));
    expect(browser, contains("activeOnly: true"));
    expect(supplierPortalCatalog, contains('BrowserSupplierPortalEntry'));
    expect(supplierPortalCatalog, isNot(contains('portalPassword')));
    expect(supplierPortalCatalog, isNot(contains('portalUsername')));
    expect(browser, contains('_applyInlineAddressCompletion(userQuery)'));
    expect(browser, contains('browserInlineHostCompletion('));
    expect(browser, contains('TextSelection('));
    expect(browser, contains('_inlineCompletionNavigationUrl'));
    expect(browser, contains('rankedPrefixSites.first.url'));
    expect(siteMemory, contains("'lastUrl': lastUrl"));
    expect(browser, contains('BrowserSiteMemoryService.mergeFromHistory'));
    expect(browser,
        contains('initialUserScripts: _credentialAutofillUserScripts'));
    expect(browser, contains('UserScriptInjectionTime.AT_DOCUMENT_END'));
    expect(credentialAutofill, contains("'current-password'"));
    expect(browser, contains('browserCredentialCaptureHandlerName'));
    expect(browser, contains('_autofillSavedBrowserCredential'));
    expect(browser, contains('_supplierCredentialLookupForOrigin'));
    expect(browser, contains('_localCredentialForOrigin'));
    expect(
      browser,
      contains('credential is only a fallback after a confirmed protected'),
    );
    expect(browser, contains('context.read<PurchaseService>()'));
    expect(browser, contains('Olvidar credenciales del sitio'));
    expect(credentialVault, contains('FlutterSecureStorage'));
    expect(credentialVault, contains('normalizeOrigin'));
    expect(credentialVault, isNot(contains('SharedPreferences')));
    expect(
      supplierCredentialResolver,
      contains('resolveSupplierCredentialForOrigin'),
    );
    expect(
      supplierCredentialResolver,
      contains('normalizeSupplierBrowserOrigin'),
    );
    expect(supplierCredentialResolver, isNot(contains("startsWith('www.')")));
    expect(
      browser,
      contains('revealPortalCredentialForOrigin'),
    );
    expect(
      submittedCredentialBlock,
      contains('BrowserSupplierCredentialLookupStatus.unavailable'),
    );
    expect(submittedCredentialBlock, contains('supplierLookup.isMatched'));
    expect(
        submittedCredentialBlock, contains('_deleteLocalCredential(origin)'));
    expect(
      submittedCredentialBlock.indexOf(
        '_supplierCredentialLookupForOrigin(origin)',
      ),
      lessThan(submittedCredentialBlock.indexOf('localCredential.username')),
    );
    expect(
      submittedCredentialBlock.indexOf(
        'BrowserSupplierCredentialLookupStatus.unavailable',
      ),
      lessThan(submittedCredentialBlock.indexOf('_credentialVault.save(')),
    );
    expect(
      autofillCredentialBlock,
      contains('supplierCredential == null && vaultCredential != null'),
    );
    expect(
      autofillCredentialBlock,
      contains('!authority.canManageSupplierCredentials'),
    );
    expect(
      autofillCredentialBlock,
      isNot(
        contains('const BrowserSupplierCredentialLookupResult.noMatch()'),
      ),
    );
    expect(
      autofillCredentialBlock.indexOf(
        '_supplierCredentialLookupForOrigin(',
      ),
      lessThan(
        autofillCredentialBlock.indexOf(
          '_localCredentialForOrigin(secureOrigin)',
        ),
      ),
    );
    expect(
      RegExp(r'requireSupplierCredentialPermission:\s*true')
          .allMatches(autofillCredentialBlock),
      hasLength(2),
    );
    expect(autofillCredentialBlock, isNot(contains('updatedAt.isAfter')));
    expect(browser, contains('credential.supplierNoMatchConfirmed'));
    expect(browser, contains('supplierNoMatchConfirmed: true'));
    expect(
      supplierCredentialResolver,
      isNot(contains("import '../models/supplier.dart'")),
    );
    expect(
      forgetCredentialBlock,
      contains('_supplierCredentialReferenceForOrigin(origin)'),
    );
    expect(
      forgetCredentialBlock,
      isNot(contains('_supplierCredentialLookupForOrigin(origin)')),
    );
    expect(
      forgetCredentialBlock,
      isNot(contains('revealPortalCredentialForOrigin')),
    );
    expect(pubspec, contains('flutter_secure_storage: ^10.3.1'));
    expect(androidManifest, contains('android:allowBackup="false"'));
    expect(androidManifest, isNot(contains('android:allowBackup="true"')));
    expect(debugEntitlements, isNot(contains('keychain-access-groups')));
    expect(releaseEntitlements, isNot(contains('keychain-access-groups')));
    expect(iosDebugEntitlements, matches(emptyKeychainAccessGroups));
    expect(iosReleaseEntitlements, matches(emptyKeychainAccessGroups));
    expect(debugEntitlements, matches(macosSandboxEnabled));
    expect(releaseEntitlements, matches(macosSandboxEnabled));
    expect(
      RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile\.entitlements;',
      ).allMatches(macosProject),
      hasLength(2),
    );
    expect(
      RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/Release\.entitlements;',
      ).allMatches(macosProject),
      hasLength(1),
    );
    expect(
      RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile\.entitlements;',
      ).allMatches(iosProject),
      hasLength(2),
    );
    expect(
      RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/Release\.entitlements;',
      ).allMatches(iosProject),
      hasLength(1),
    );
    expect(
      browser,
      isNot(contains('onPermissionRequest: (controller, request) async {')),
    );
    expect(browser, contains('openBrowserWorkspace('));
    expect(manager, contains('updateBrowserWorkspaceState('));
    expect(manager, contains('_restoreBrowserSession('));
    expect(app, contains("'dormant-\${workspace.id}'"));
    expect(registry, contains('## Embedded Browser Surfaces'));
    expect(registry, contains('memoria de dominios'));
    expect(registry, contains('autocompletado inline'));
    expect(registry, contains('catálogo corporativo'));
    expect(registry, contains('cualquier equipo'));
    expect(registry, contains('última ruta útil'));
    expect(
      registry,
      matches(RegExp(r"operating system's\s+secure store")),
    );
    expect(registry, contains('SupplierCredentialService'));
    expect(registry, contains('stable key'));
    expect(registry, contains('canonical HTTPS origin'));
    expect(registry, contains('dedicated supplier-credential permission'));
    expect(registry, isNot(contains('portal_username')));
    expect(registry, contains('ambiguous'));
    expect(registry, contains('exact origin'));
    expect(registry, contains('failed repeated login'));
    expect(browser, contains('allowInsecureSupplierOrigin: false'));
    expect(browser, isNot(contains('filled-insecure')));
    expect(supplierForm, contains('canonicalSupplierCredentialOrigin'));
    expect(supplierForm, contains('obscureText: true'));
    expect(supplierForm, contains('enableSuggestions: false'));
    expect(supplierForm, isNot(contains('PurchaseService')));
    expect(supplierForm, isNot(contains('_showPortalPassword')));
  });
}
