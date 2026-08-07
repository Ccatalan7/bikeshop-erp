import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/browser_user_agent.dart';
import 'package:vinabike_erp/shared/widgets/browser_popup_window.dart';

void main() {
  test('quita el token wv del user agent real de un WebView de Android', () {
    const androidWebView =
        'Mozilla/5.0 (Linux; Android 14; SM-G991B Build/UP1A.231005.007; wv) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
        'Chrome/140.0.7339.51 Mobile Safari/537.36';

    final sanitized = sanitizeEmbeddedUserAgent(androidWebView);

    expect(sanitized, isNotNull);
    expect(sanitized, isNot(contains('wv')));
    // Lo que identifica al navegador se conserva: no se disfraza de otra cosa.
    expect(sanitized, contains('Chrome/140.0.7339.51'));
    expect(sanitized, contains('Mobile Safari/537.36'));
    expect(sanitized, contains('Android 14'));
    expect(sanitized, isNot(contains(';)')));
    expect(sanitized, isNot(contains('  ')));
  });

  test('acepta la variante con el token al final del paréntesis', () {
    final sanitized = sanitizeEmbeddedUserAgent(
      'Mozilla/5.0 (Linux; Android 13; Pixel 7 wv) AppleWebKit/537.36',
    );

    expect(
        sanitized,
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36');
  });

  test('no inventa un user agent cuando no hay nada que corregir', () {
    expect(
      sanitizeEmbeddedUserAgent(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15',
      ),
      isNull,
    );
    expect(sanitizeEmbeddedUserAgent(null), isNull);
    expect(sanitizeEmbeddedUserAgent('   '), isNull);
  });

  test('no confunde palabras que contienen wv', () {
    const withWord =
        'Mozilla/5.0 (Linux; Android 14) Wvernon/2.1 Safari/537.36';

    expect(sanitizeEmbeddedUserAgent(withWord), isNull);
  });

  group('ventanas nuevas', () {
    // La dirección de la regla es lo que importa: perder un popup de login es
    // perder la sesión entera; hospedar de más sólo cambia dónde se ve una
    // página. Por eso se hospeda salvo que sea un enlace que la persona tocó.
    test('un window.open a secas se hospeda: es como abre su ventana un login',
        () {
      expect(
        shouldHostPopupWindow(url: 'https://login.aliexpress.com/'),
        isTrue,
      );
    });

    test('una ventana sin URL se hospeda siempre', () {
      expect(shouldHostPopupWindow(url: null), isTrue);
      expect(shouldHostPopupWindow(url: '   '), isTrue);
      expect(shouldHostPopupWindow(url: 'about:blank'), isTrue);
      expect(
        shouldHostPopupWindow(
          url: 'about:blank',
          navigationType: 'LINK_ACTIVATED',
        ),
        isTrue,
      );
    });

    test('un window.open con tamaño o sin barras también se hospeda', () {
      expect(
        shouldHostPopupWindow(url: 'https://x.test/', width: 500, height: 600),
        isTrue,
      );
      expect(
        shouldHostPopupWindow(
            url: 'https://x.test/', toolbarsVisibility: false),
        isTrue,
      );
      expect(shouldHostPopupWindow(url: 'https://x.test/', isDialog: true),
          isTrue);
    });

    test('un target="_blank" que la persona tocó sigue siendo otra pestaña',
        () {
      expect(
        shouldHostPopupWindow(
          url: 'https://x.test/articulo',
          navigationType: 'LINK_ACTIVATED',
        ),
        isFalse,
      );
    });
  });
}
