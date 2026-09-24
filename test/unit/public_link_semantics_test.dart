import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/premium_product_card.dart';
import 'package:vinabike_erp/public_store/services/crawler_semantics.dart';
import 'package:vinabike_erp/public_store/widgets/public_link_semantics.dart';

/// Google renderiza la tienda con Flutter montado: sin árbol de accesibilidad
/// no hay ni texto ni `<a href>` en el DOM. Los destinos se declaran como
/// enlaces y la semántica se activa para los rastreadores.
void main() {
  setUp(() => PublicLinkSemantics.publicStoreRuntime = true);
  tearDown(() => PublicLinkSemantics.publicStoreRuntime = false);

  group('isKnownCrawlerUserAgent', () {
    test('reconoce los rastreadores de Google, Merchant y Bing', () {
      const agents = [
        'Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile '
            'Safari/537.36 (compatible; Googlebot/2.1; '
            '+http://www.google.com/bot.html)',
        'Mozilla/5.0 (compatible; Google-InspectionTool/1.0;)',
        'Mozilla/5.0 (X11; Linux x86_64; Storebot-Google/1.0) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 '
            'Safari/537.36',
        'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; '
            'bingbot/2.0; +http://www.bing.com/bingbot.htm) Chrome/116.0 '
            'Safari/537.36',
      ];
      for (final agent in agents) {
        expect(isKnownCrawlerUserAgent(agent), isTrue, reason: agent);
      }
    });

    test('un navegador de cliente no activa la semántica', () {
      const agents = [
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
            'Mobile/15E148 Safari/604.1',
        '',
      ];
      for (final agent in agents) {
        expect(isKnownCrawlerUserAgent(agent), isFalse, reason: agent);
      }
    });
  });

  group('publicLinkUri', () {
    test('acepta rutas de la tienda y páginas web', () {
      expect(publicLinkUri('/productos/cadena/10266').toString(),
          '/productos/cadena/10266');
      expect(publicLinkUri(' /servicios ').toString(), '/servicios');
      expect(publicLinkUri('https://vinabike.cl/contacto').toString(),
          'https://vinabike.cl/contacto');
    });

    test('descarta lo que no es una página navegable', () {
      for (final href in [
        null,
        '',
        '#top',
        'tel:+56998357797',
        'mailto:contacto@vinabike.cl',
        'productos',
        '//otro-sitio.cl/productos',
      ]) {
        expect(publicLinkUri(href), isNull, reason: '$href');
      }
    });
  });

  testWidgets('PublicLinkSemantics expone el destino como enlace',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PublicLinkSemantics(
          href: '/productos/categoria/cadenas',
          child: Text('Cadenas'),
        ),
      ),
    );

    final data = tester.getSemantics(find.text('Cadenas')).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isLink), isTrue);
    expect(data.linkUrl.toString(), '/productos/categoria/cadenas');
    handle.dispose();
  });

  testWidgets('canonicalPublicHref quita la ruta montada del ERP',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }));
    expect(canonicalPublicHref(context, '/tienda'), '/');
    expect(canonicalPublicHref(context, '/tienda/productos'), '/productos');
    expect(canonicalPublicHref(context, '/productos?q=ruta'),
        '/productos?q=ruta');
    // Sin registro de presentaciones no hay ruta de colección que inventar.
    expect(canonicalPublicHref(context, '/productos?category=abc'),
        '/productos?category=abc');
    expect(canonicalPublicHref(context, 'https://wa.me/56998357797'),
        'https://wa.me/56998357797');
  });

  testWidgets('en el ERP (Edit y Preview bajo /tienda) no se declara enlace',
      (tester) async {
    PublicLinkSemantics.publicStoreRuntime = false;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PublicLinkSemantics(
          href: '/productos',
          child: Text('Productos'),
        ),
      ),
    );

    final data =
        tester.getSemantics(find.text('Productos')).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isLink), isFalse);
    handle.dispose();
  });

  testWidgets('en Edit no se declara enlace', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PublicLinkSemantics(
          href: '/productos',
          enabled: false,
          child: Text('Productos'),
        ),
      ),
    );

    final data =
        tester.getSemantics(find.text('Productos')).getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isLink), isFalse);
    handle.dispose();
  });

  testWidgets('la tarjeta de producto de los bloques enlaza a su ficha',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 380,
            child: PremiumProductCard(
              name: 'Cadena X8 KMC',
              price: 12990,
              productSku: '10266',
              productId: 'p-1',
              interactionsEnabled: true,
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(PremiumProductCard));
    final data = node.getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isLink), isTrue);
    expect(data.linkUrl.toString(), '/productos/cadena-x8-kmc/10266');
    handle.dispose();
  });
}
