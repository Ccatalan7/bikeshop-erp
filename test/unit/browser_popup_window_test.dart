import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/widgets/browser_popup_window.dart';

void main() {
  group('captura segura de window.open', () {
    test('inyecta al inicio y conserva this, argumentos y retorno', () {
      final script = browserPopupOpenCaptureUserScript();
      final source = script.source;

      expect(
        script.injectionTime,
        UserScriptInjectionTime.AT_DOCUMENT_START,
      );
      expect(script.forMainFrameOnly, isTrue);
      expect(source, contains('new URL(rawUrl, document.baseURI)'));
      expect(source, contains("resolved.protocol === 'http:'"));
      expect(source, contains("resolved.protocol === 'https:'"));
      expect(source, contains('Reflect.apply(nativeOpen, this, args)'));
      expect(source.indexOf('queue.push('),
          lessThan(source.indexOf('Reflect.apply(')));
    });

    test('la FIFO queda 1:1, acotada y no usa canales que loguean payloads',
        () {
      final source = browserPopupOpenCaptureUserScriptSource;

      expect(source, contains('const maxUrlLength = 8192'));
      expect(source, contains('const maxQueueLength = 8'));
      expect(source, contains('const maxAgeMilliseconds = 30000'));
      expect(source, contains('const entry = queue.shift()'));
      expect(source, isNot(contains('while (queue.length > 0)')));
      expect(source, contains('const entry = {url: null'));
      expect(source, contains('rawUrl.trim().length > 0'));
      expect(source, contains('entry.url = resolved.href'));
      expect(source, contains('queue.shift()'));
      expect(source, contains('queue.push(entry)'));
      expect(source, contains('if (openedWindow === null)'));
      expect(source, contains('queue.indexOf(entry)'));
      expect(source, contains('queue.splice(index, 1)'));
      expect(source, contains('throw error'));
      expect(source, contains('Date.now()'));
      expect(source, isNot(contains('callHandler')));
      expect(source, isNot(contains('flutter_inappwebview')));
      expect(source, isNot(contains('console.')));
      expect(source, isNot(contains('localStorage')));
      expect(source, isNot(contains('sessionStorage')));
    });

    test('acepta sólo HTTP(S) absoluto y conserva el destino completo', () {
      const oauthUrl =
          'https://accounts.google.com/signin/oauth?state=test-state&code=test-code#return';

      expect(
        browserPopupOpenUrlFromEvaluation(oauthUrl)?.toString(),
        oauthUrl,
      );
      expect(
        browserPopupOpenUrlFromEvaluation('http://thirdparty.example/login')
            ?.toString(),
        'http://thirdparty.example/login',
      );
      expect(browserPopupOpenUrlFromEvaluation(null), isNull);
      expect(browserPopupOpenUrlFromEvaluation(42), isNull);
      expect(browserPopupOpenUrlFromEvaluation(''), isNull);
      expect(browserPopupOpenUrlFromEvaluation('/login'), isNull);
      expect(browserPopupOpenUrlFromEvaluation('about:blank'), isNull);
      expect(browserPopupOpenUrlFromEvaluation('javascript:alert(1)'), isNull);
      expect(
          browserPopupOpenUrlFromEvaluation('data:text/plain,login'), isNull);
      expect(
          browserPopupOpenUrlFromEvaluation('https:///missing-host'), isNull);
      expect(
        browserPopupOpenUrlFromEvaluation(
          'https://example.com/${List.filled(8200, 'x').join()}',
        ),
        isNull,
      );
    });

    test('la extracción ejecuta sólo una expresión constante sin URL', () {
      expect(
        browserPopupOpenDequeueJavaScriptSource,
        contains('__vinabikeTakeBrowserPopupOpenUrl'),
      );
      expect(browserPopupOpenDequeueJavaScriptSource, contains('take()'));
      expect(browserPopupOpenDequeueJavaScriptSource, isNot(contains('http')));
      expect(browserPopupOpenDequeueJavaScriptSource, isNot(contains('query')));
    });

    test('el fallback sólo consulta si el runtime continúa en blank', () {
      expect(
        browserPopupRuntimeIsBlankJavaScriptSource,
        "location.href === '' || location.href === 'about:blank'",
      );
      expect(
        browserPopupExplicitLoadFallbackDelay,
        const Duration(milliseconds: 750),
      );
      expect(browserPopupExplicitLoadFallbackProbeAttempts, 2);
      expect(
          browserPopupRuntimeIsBlankJavaScriptSource, isNot(contains('http')));
      expect(
          browserPopupRuntimeIsBlankJavaScriptSource, isNot(contains('url')));
    });

    test('blank carga una sola vez y nonblank no carga', () async {
      var blankLoads = 0;
      final blankOutcome = await runBrowserPopupExplicitLoadFallback(
        wait: (_) async {},
        isActive: () => true,
        probeRuntimeIsBlank: () async => true,
        load: () async {
          blankLoads++;
        },
      );

      var nonBlankLoads = 0;
      final nonBlankOutcome = await runBrowserPopupExplicitLoadFallback(
        wait: (_) async {},
        isActive: () => true,
        probeRuntimeIsBlank: () async => false,
        load: () async {
          nonBlankLoads++;
        },
      );

      expect(blankOutcome, BrowserPopupExplicitLoadFallbackOutcome.loaded);
      expect(blankLoads, 1);
      expect(
        nonBlankOutcome,
        BrowserPopupExplicitLoadFallbackOutcome.notNeeded,
      );
      expect(nonBlankLoads, 0);
    });

    test('inactividad cancela y una sonda fallida se reintenta', () async {
      var active = true;
      var inactiveProbes = 0;
      var inactiveLoads = 0;
      final inactiveOutcome = await runBrowserPopupExplicitLoadFallback(
        wait: (_) async {
          active = false;
        },
        isActive: () => active,
        probeRuntimeIsBlank: () async {
          inactiveProbes++;
          return true;
        },
        load: () async {
          inactiveLoads++;
        },
      );

      var retries = 0;
      var retryLoads = 0;
      final retryOutcome = await runBrowserPopupExplicitLoadFallback(
        wait: (_) async {},
        isActive: () => true,
        probeRuntimeIsBlank: () async {
          retries++;
          if (retries == 1) throw StateError('probe unavailable');
          return true;
        },
        load: () async {
          retryLoads++;
        },
      );

      expect(
        inactiveOutcome,
        BrowserPopupExplicitLoadFallbackOutcome.inactive,
      );
      expect(inactiveProbes, 0);
      expect(inactiveLoads, 0);
      expect(retryOutcome, BrowserPopupExplicitLoadFallbackOutcome.loaded);
      expect(retries, 2);
      expect(retryLoads, 1);
    });

    test('desactiva el logger verboso del plugin antes de manejar secretos',
        () {
      final previous =
          PlatformInAppWebViewController.debugLoggingSettings.enabled;
      addTearDown(() {
        PlatformInAppWebViewController.debugLoggingSettings.enabled = previous;
      });

      PlatformInAppWebViewController.debugLoggingSettings.enabled = true;
      disableBrowserWebViewPluginDebugLogging();

      expect(
        PlatformInAppWebViewController.debugLoggingSettings.enabled,
        isFalse,
      );
    });
  });

  test('Android conserva windowId y sólo rescata un runtime aún blank', () {
    final popup = File(
      'lib/shared/widgets/browser_popup_window.dart',
    ).readAsStringSync();
    final browser = File(
      'lib/shared/widgets/webview_module_page.dart',
    ).readAsStringSync();

    expect(popup, isNot(contains('InAppBrowser')));
    expect(popup, contains('windowId: widget.windowId'));
    expect(popup, contains('onWebViewCreated: _handleWebViewCreated'));
    expect(popup, contains('_loadExplicitInitialUrlIfStillBlank('));
    expect(popup, contains('runBrowserPopupExplicitLoadFallback('));
    expect(popup, contains('probeRuntimeIsBlank: () =>'));
    expect(popup, contains('await controller.loadUrl('));
    expect(popup, contains('initialUserScripts:'));
    expect(popup, contains('onCreateWindow: _handleCreateWindow'));
    expect(popup, contains('takeCapturedBrowserPopupOpenUrl(controller)'));
    expect(popup, contains('onCloseWindow: (_) => _close()'));
    // Sin este callback Android no conduce la navegación heredada por el
    // `windowId`: la ventana hija se queda en su documento en blanco y el
    // inicio de sesión de AliExpress no llega nunca a Google. Medido sobre un
    // build release el 2026-08-10; un build debug escondía el defecto.
    expect(popup, contains('shouldOverrideUrlLoading:'));
    expect(popup, isNot(contains('browserPopupDebugLog')));

    final handlerStart = browser.indexOf('Future<bool> _handleCreateWindow(');
    final handlerEnd = browser.indexOf('String _displayHost()', handlerStart);
    expect(handlerStart, isNonNegative);
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = browser.substring(handlerStart, handlerEnd);
    expect(handler, contains('takeCapturedBrowserPopupOpenUrl(controller)'));
    expect(handler, contains('explicitInitialUrl: explicitInitialUrl'));
    expect(handler, isNot(contains('explicitInitialUrl = url')));

    expect(browser, contains('_browserInitialUserScripts'));
    expect(browser, contains('browserPopupOpenCaptureUserScript()'));
    expect(browser, contains('disableBrowserWebViewPluginDebugLogging();'));
    expect(browser, isNot(contains('_credentialAutofillUserScripts')));
    expect(browser, isNot(contains('onConsoleMessage:')));
    expect(browser, isNot(contains('[BrowserProbe] url=')));
  });

  test('el bridge Android consume la consola antes del fallback de logcat', () {
    final plugin = File(
      'packages/flutter_inappwebview_android/android/src/main/java/'
      'com/pichillilorenzo/flutter_inappwebview_android/webview/'
      'in_app_webview/InAppWebViewChromeClient.java',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final methodStart = plugin.indexOf(
      'public boolean onConsoleMessage(ConsoleMessage consoleMessage)',
    );
    final methodEnd = plugin.indexOf('\n  }', methodStart);

    expect(methodStart, isNonNegative);
    expect(methodEnd, greaterThan(methodStart));
    final method = plugin.substring(methodStart, methodEnd);
    expect(method, contains('return true;'));
    expect(method, isNot(contains('return super.onConsoleMessage')));
    expect(method, isNot(contains('Log.')));
    expect(pubspec, contains('flutter_inappwebview_android:'));
    expect(pubspec, contains('path: ./packages/flutter_inappwebview_android'));
  });

  testWidgets('un padre cerrado no expulsa a su popup hijo', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    BuildContext? parentContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Text('home'),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) {
          parentContext = context;
          return const Text('popup-parent');
        },
      ),
    );
    await tester.pumpAndSettle();
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Text('popup-child'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('popup-parent', skipOffstage: false), findsOneWidget);
    closeBrowserPopupRoute(parentContext!);
    await tester.pumpAndSettle();

    expect(find.text('popup-parent', skipOffstage: false), findsNothing);
    expect(find.text('popup-child'), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
