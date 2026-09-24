import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart'
    show StorefrontLogoResolution;

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

/// Página instantánea de la tienda (docs/architecture/storefront-instant-page.md).
void main() {
  const tenantId = '5443b130-cc28-45af-a420-cd500b288890';

  Map<String, dynamic> productRow({
    Object? price = 45000.0,
    Object? websitePrice,
    int stock = 3,
    bool isSet = false,
    String name = 'Aceite mineral <Shimano> 1000cc',
  }) =>
      {
        'id': 'p-1',
        'sku': 'S56467',
        'name': name,
        'description': 'Fluido para frenos hidráulicos.',
        'price': price,
        'website_price': websitePrice,
        'price_currency': 'CLP',
        'stock_quantity': stock,
        'inventory_qty': stock,
        'track_stock': true,
        'product_type': 'product',
        'is_set': isSet,
        'image_url': 'https://cdn.example.com/S56467.jpg',
        'category_id': 'c-1',
      };

  snapshots.SeoInstantPageTheme theme(
          [Map<String, String> settings = const {}]) =>
      snapshots.SeoInstantPageTheme.fromSettings(settings,
          storeName: 'Viñabike');

  group('tema', () {
    test('sin ajustes usa los mismos valores por defecto que la tienda', () {
      expect(
        snapshots.SeoInstantPageTheme.defaultCommerceText,
        WebsiteResolvedTheme.defaultCommerceTextColor.toARGB32(),
      );
      expect(
        snapshots.SeoInstantPageTheme.defaultCommerceAccent,
        WebsiteResolvedTheme.defaultCommerceAccentColor.toARGB32(),
      );
      expect(
        snapshots.SeoInstantPageTheme.defaultCommerceLine,
        WebsiteResolvedTheme.defaultCommerceLineColor.toARGB32(),
      );
      expect(
        snapshots.SeoInstantPageTheme.defaultBackground,
        WebsiteResolvedTheme.defaultBackgroundColor.toARGB32(),
      );
      expect(theme().css, contains('--ip-accent:#123f68'));
    });

    test('lee cada formato de color igual que WebsiteResolvedTheme', () {
      final settings = {
        'theme_background_color': '4294967295',
        'theme_product_detail_accent_color': '#0B3A5F',
        'theme_product_detail_text_color': '0xFF111827',
        'theme_product_detail_line_color': 'e2e8f0',
        'theme_heading_font': 'Oswald',
      };
      final resolved = WebsiteResolvedTheme.resolve(
        (key, fallback) => settings[key] ?? fallback,
      );
      final instant = theme(settings);
      expect(instant.background, resolved.backgroundColor.toARGB32());
      expect(instant.accent, resolved.commerceAccentColor.toARGB32());
      expect(instant.text, resolved.commerceTextColor.toARGB32());
      expect(instant.line, resolved.commerceLineColor.toARGB32());
      expect(instant.css, contains('--ip-heading-font:"Oswald"'));
    });

    test('usa el mismo primer logo que el encabezado de la tienda', () {
      for (final (configured, tenantLogo, tenant) in [
        ('', null, tenantId),
        ('', null, 'otro-tenant'),
        ('', 'https://x/tenant.png', tenantId),
        ('https://x/sitio.png', 'https://x/tenant.png', tenantId),
      ]) {
        final resolution = StorefrontLogoResolution.resolve(
          configuredUrl: configured,
          tenantLogoUrl: tenantLogo,
          tenantId: tenant,
        );
        final expected = resolution.networkCandidates.isNotEmpty
            ? resolution.networkCandidates.first
            : resolution.allowsBundledAsset
                ? 'assets/${StorefrontLogoResolution.bundledAssetPath}'
                : '';
        final instant = snapshots.SeoInstantPageTheme.fromSettings(
          {'logo_url': configured},
          storeName: 'Viñabike',
          tenantLogoUrl: tenantLogo,
          tenantId: tenant,
        );
        expect(instant.logoUrl, expected,
            reason: '$configured $tenantLogo $tenant');
      }
    });

    test('resuelve las fuentes como la tienda y todas tienen @font-face', () {
      final instantCss = File(snapshots.seoInstantStylePath).readAsStringSync();
      for (final (heading, body) in [
        (null, null),
        ('Barlow', 'Oswald'),
        ('Comic Sans', 'Inter'),
        ('Oswald";}body{x', ''),
      ]) {
        final settings = {
          if (heading != null) 'theme_heading_font': heading,
          if (body != null) 'theme_body_font': body,
        };
        final resolved = WebsiteResolvedTheme.resolve(
          (key, fallback) => settings[key] ?? fallback,
        );
        final instant = theme(settings);
        expect(instant.headingFont, resolved.headingFont, reason: '$heading');
        expect(instant.bodyFont, resolved.bodyFont, reason: '$body');
        expect(instant.css, isNot(contains('";}')));
        for (final family in [instant.headingFont, instant.bodyFont]) {
          expect(instantCss, contains('font-family: "$family";'),
              reason: 'sin @font-face, el navegador cambia de fuente');
        }
      }
    });
  });

  group('ficha', () {
    String template(Map<String, dynamic> row) =>
        snapshots.buildSeoInstantProductTemplate(
          theme: theme({'company_logo_url': 'https://x/logo.png'}),
          tenantId: tenantId,
          commerce: PublicCommerceProductProjection.fromJson(row),
          product: row,
        );

    test('muestra foto, nombre y precio como la ficha', () {
      final html = template(productRow());
      expect(html, startsWith('<template id="instant-page-template"'));
      expect(html, contains('data-ip-kind="product"'));
      expect(html, contains('src="https://cdn.example.com/S56467.jpg"'));
      expect(html, contains('fetchpriority="high"'));
      expect(html, contains(r'<p class="ip-price">$45.000</p>'));
      // El nombre pasa por el mismo limpiador de la ficha
      // (`storefrontDisplayTitle`), que quita los `<>`.
      expect(html, isNot(contains('<Shimano>')));
    });

    test('escapa el texto del catálogo', () {
      final html = template(productRow(name: 'Grasa & aceite "Pro"'));
      expect(html, contains('Grasa &amp; aceite'));
      expect(html, isNot(contains('"Pro"')));
    });

    test('no agrega un h1 ni un main al documento', () {
      // El validador del generador exige exactamente uno de cada por página;
      // la instantánea usa roles.
      final html = template(productRow());
      expect(html, isNot(contains('<h1')));
      expect(html, isNot(contains('<main')));
      expect(html, contains('role="heading" aria-level="1"'));
      expect(html, contains('role="main"'));
    });

    test('el precio web manda sobre el de lista', () {
      expect(template(productRow(websitePrice: 39990)),
          contains(r'<p class="ip-price">$39.990</p>'));
    });

    test('el precio nace neutro hasta verificarse', () {
      // instant_page.css sólo lo muestra con data-ip-state="verified".
      expect(template(productRow()), contains('data-ip-state="pending"'));
      expect(template(productRow()), contains('ip-price-skeleton'));
    });

    test('no afirma disponibilidad: la descuentan reservas que la fila no ve',
        () {
      for (final row in [
        productRow(),
        productRow(stock: 0),
        productRow(isSet: true),
      ]) {
        final html = template(row);
        expect(html, isNot(contains('En stock')));
        expect(html, isNot(contains('Agotado')));
        expect(html, isNot(contains('ip-stock-row')));
      }
    });

    test('lleva la firma de frescura de la fila', () {
      final row = productRow();
      expect(
        template(row),
        contains(
            'data-ip-sig="${snapshots.seoInstantFreshnessSignature(row)}"'),
      );
    });
  });

  group('firma de frescura', () {
    test('normaliza números y nulos como la lectura pública', () {
      expect(
        snapshots.seoInstantFreshnessSignature(productRow()),
        '|45000.00',
      );
      // PostgREST puede devolver 45000 o 45000.0: es el mismo precio.
      expect(
        snapshots.seoInstantFreshnessSignature(productRow(price: 45000)),
        snapshots.seoInstantFreshnessSignature(productRow(price: '45000.00')),
      );
    });

    test('cambia con el precio y no con el stock', () {
      final base = snapshots.seoInstantFreshnessSignature(productRow());
      expect(snapshots.seoInstantFreshnessSignature(productRow(price: 46000.0)),
          isNot(base));
      expect(
          snapshots
              .seoInstantFreshnessSignature(productRow(websitePrice: 39990)),
          isNot(base));
      expect(
          snapshots.seoInstantFreshnessSignature(productRow(stock: 0)), base);
    });

    test('el script vuelve a leer exactamente los mismos campos', () {
      final script = File(snapshots.seoInstantScriptPath).readAsStringSync();
      final match = RegExp(r"var fields = \[([^\]]+)\]").firstMatch(script);
      expect(match, isNotNull);
      final fields = RegExp(r"'([a-z_]+)'")
          .allMatches(match!.group(1)!)
          .map((m) => m.group(1))
          .toList();
      expect(fields, snapshots.seoInstantFreshnessFields);
    });
  });

  group('categoría', () {
    snapshots.SeoCategoryProjection category({
      double heroDesktopHeight = 360,
      String imageUrl = '',
    }) =>
        snapshots.SeoCategoryProjection(
          categoryId: 'c-1',
          name: 'Cadenas',
          fullPath: 'Componentes / Transmisión / Cadenas',
          slug: 'cadenas',
          slugAliases: const [],
          canonicalPath: '/productos/categoria/cadenas',
          displayTitle: 'Cadenas',
          description: '',
          seoTitle: '',
          seoDescription: '',
          imageUrl: imageUrl,
          socialImageUrl: '',
          allowIndexing: true,
          sortOrder: 0,
          updatedAt: null,
          products: const [],
          heroDesktopHeight: heroDesktopHeight,
          heroOverlay: 0.42,
        );

    test('la portada tiene la altura de CatalogCollectionPresentationHeader',
        () {
      final html = snapshots.buildSeoInstantCategoryTemplate(
        theme: theme(),
        tenantId: tenantId,
        category: category(),
      );
      // estándar: 360 × 0,5 = 180 en ancho; en compacto min(180, 180 × 0,72).
      expect(html, contains('--ip-hero-h:180px'));
      expect(html, contains('--ip-hero-h-compact:130px'));
      expect(html, contains('rgba(0,0,0,0.42)'));
      expect(html, contains('>Cadenas</p>'));
      expect(html, isNot(contains('<h1')));
    });

    test('la grilla es un espacio reservado, no productos inventados', () {
      final html = snapshots.buildSeoInstantCategoryTemplate(
        theme: theme(),
        tenantId: tenantId,
        category: category(),
      );
      expect(html, contains('class="ip-grid" aria-hidden="true"'));
      expect(html, isNot(contains('ip-price')));
    });
  });

  group('inyección', () {
    final index = File('web/index.html').readAsStringSync();
    final css = File(snapshots.seoInstantStylePath).readAsStringSync();
    final js = File(snapshots.seoInstantScriptPath).readAsStringSync();

    // CI no publica web/index.html: scripts/sync_seo_index.sh lo reescribe
    // entero desde su plantilla antes del build. El 2026-09-24 la instantánea
    // salió inerte porque su hoja y su script sólo vivían en web/index.html.
    String ciIndexTemplate() {
      final sync = File('scripts/sync_seo_index.sh').readAsStringSync();
      final start = sync.indexOf('cat > "\$INDEX_FILE" << HEREDOC\n');
      expect(start, isNonNegative, reason: 'sync_seo_index.sh cambió');
      final body = sync.substring(sync.indexOf('\n', start) + 1);
      return body.substring(0, body.indexOf('\nHEREDOC'));
    }

    void expectSelfSufficient(String html) {
      final shell = html.indexOf('<div id="app-shell">');
      final template = html.indexOf('<template id="instant-page-template">');
      final script = html.indexOf('<script id="instant-page-script">');
      final head = html.substring(0, html.indexOf('</head>'));
      expect(head, contains('<style id="instant-page-style">'));
      expect(head, contains('html.ip-covered #loading-logo'));
      expect(template, allOf(isNonNegative, lessThan(script)));
      expect(script, lessThan(shell),
          reason: 'debe montarse antes de que se pinte el splash');
      expect(html, contains('window.vinabikeInstantPage = api'));
      expect('vinabikeInstantPage'.allMatches(html).length,
          'vinabikeInstantPage'.allMatches(js).length,
          reason: 'un solo script de montaje');
    }

    test('la página queda completa sobre el index.html que publica CI', () {
      final ciIndex = ciIndexTemplate();
      expect(ciIndex, isNot(contains('vinabikeInstantPage')));
      expectSelfSufficient(snapshots.injectSeoInstantPage(
        ciIndex,
        theme: theme(),
        templateHtml: '<template id="instant-page-template"></template>',
      ));
    });

    test('y sobre web/index.html, que ya no trae nada de la instantánea', () {
      expect(index, isNot(contains('vinabikeInstantPage')));
      expect(index, isNot(contains('#instant-page')));
      expectSelfSufficient(snapshots.injectSeoInstantPage(
        index,
        theme: theme(),
        templateHtml: '<template id="instant-page-template"></template>',
      ));
    });

    test('falla fuerte si web/index.html vuelve a traer el script', () {
      expect(
        () => snapshots.injectSeoInstantPage(
          index.replaceFirst(
              '</body>', '<script>vinabikeInstantPage</script></body>'),
          theme: theme(),
          templateHtml: '<template id="instant-page-template"></template>',
        ),
        throwsStateError,
      );
    });

    test('pone el tema y la foto en head y la plantilla antes del splash', () {
      final html = snapshots.injectSeoInstantPage(
        index,
        theme: theme(),
        templateHtml: '<template id="instant-page-template"></template>',
        preloadImageUrl: 'https://cdn.example.com/S56467.jpg',
      );
      final head = html.substring(0, html.indexOf('</head>'));
      expect(head, contains('<style id="instant-page-theme">'));
      expect(
        head,
        contains('<link rel="preload" as="image" '
            'href="https://cdn.example.com/S56467.jpg" fetchpriority="high" '
            'crossorigin="anonymous">'),
      );
      expect(
        html.indexOf('<template id="instant-page-template">'),
        lessThan(html.indexOf('<div id="app-shell">')),
      );
    });

    test('el logo del splash ya no compite por el ancho de banda', () {
      final html = snapshots.injectSeoInstantPage(
        index,
        theme: theme(),
        templateHtml: '<template id="instant-page-template"></template>',
      );
      expect(html, isNot(contains('href="loading-logo.png"')));
      final logo = RegExp(r'<img\s+id="loading-logo"[^>]*>').firstMatch(html);
      expect(logo!.group(0), contains('loading="lazy"'));
      expect(logo.group(0), isNot(contains('fetchpriority="high"')));
    });

    test('falla fuerte si web/index.html pierde el splash', () {
      expect(
        () => snapshots.injectSeoInstantPage(
          '<html><head></head><body></body></html>',
          theme: theme(),
          templateHtml: '<template></template>',
        ),
        throwsStateError,
      );
    });

    test('el script monta la plantilla y expone release/arm', () {
      expect(js, contains("getElementById('instant-page-template')"));
      expect(js, contains('window.vinabikeInstantPage = api'));
      expect(js, contains('api.release = function'));
      expect(js, contains('api.arm = function'));
    });

    test('una ficha retirada después del build no queda a la vista', () {
      // La lectura anónima sólo ve fichas activas, publicadas y en la web.
      expect(js, contains("api.release('withdrawn')"));
      expect(js, contains("root.classList.remove('ip-covered')"));
    });

    test('un logo que no carga no deja una imagen rota', () {
      expect(js, contains("logo.addEventListener('error', hideLogo)"));
    });

    test('la categoría no reserva grilla donde la tienda pone filtros', () {
      final desktop = RegExp(
        r'@media \(min-width: 700px\) \{[\s\S]*?\.ip-catalog-heading,\s*'
        r'\.ip-grid \{\s*display: none;',
      );
      expect(desktop.hasMatch(css), isTrue,
          reason: 'ProductCatalogPage usa columna de filtros desde 700 px');
    });
  });
}
