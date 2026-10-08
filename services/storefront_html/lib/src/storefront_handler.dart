import 'block_product_picks.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:shelf/shelf.dart' show Middleware;
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'cart_page_model.dart';
import 'cart_page_view.dart';
import 'checkout_page_view.dart';
import 'order_page_view.dart';
import 'order_summary_pdf_route.dart';
import 'login_page_view.dart';
import 'portal_page_route.dart';
import 'portal_page_view.dart';
import 'catalog_page_model.dart';
import 'catalog_page_view.dart';
import 'catalog_price_list_view.dart';
import 'flutter_shell.dart';
import 'home_page_model.dart';
import 'contact_page_model.dart';
import 'contact_page_view.dart';
import 'editor_draft_route.dart';
import 'editor_page_model.dart';
import 'editor_page_view.dart';
import 'home_page_view.dart';
import 'policy_page_model.dart';
import 'policy_page_view.dart';
import 'product_page_model.dart';
import 'product_page_view.dart';
import 'public_reads.dart';
import 'site_layout.dart';
import 'storefront_config.dart';
import 'storefront_shell.dart';

/// The prefix Firebase Hosting forwards to this service for the hidden copy
/// of the store. Pages under it are never indexed nor measured; the same
/// pages answer without it once the public routes point here.
const hiddenRoutePrefix = '/_html';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Adds `x-storefront-source` to every response when the build knows its
/// source ([StorefrontConfig.source]).
Middleware storefrontSourceHeader(String? source) =>
    (Handler inner) => (Request request) async {
      final response = await inner(request);
      if (source == null) return response;
      return response.change(headers: {'x-storefront-source': source});
    };

/// Serves `/productos`, its categories and searches, and product pages,
/// built per visit from the public reads.
///
/// Pages are `private, no-cache`: the CDN never keeps a copy and the browser
/// asks again on every visit, so price and stock are as fresh as the base,
/// while the back button can still restore the page from memory.
///
/// [flutterShell] answers an opened editor page that has a block the HTML
/// does not draw yet ([FlutterShell]); without it such a page is drawn
/// without that block.
Handler storefrontHandler({
  required StorefrontConfig config,
  required PublicReads reads,
  FlutterShell? flutterShell,
  OrderSummaryFonts? orderSummaryFonts,

  /// The editor's draft ([editorDraftResponse]): pages are drawn even with
  /// the site unpublished, and each block names its id.
  bool draft = false,
}) {
  final fonts = orderSummaryFonts ?? OrderSummaryFonts.forConfig(config);
  return (Request request) async {
    final requested = request.requestedUri;
    var path = requested.path;
    final hidden =
        path == hiddenRoutePrefix || path.startsWith('$hiddenRoutePrefix/');
    if (hidden) {
      path = path.substring(hiddenRoutePrefix.length);
      if (path.isEmpty) path = '/';
    }
    if (path == orderSummaryPdfPath) {
      if (request.method != 'POST') {
        return Response(405, headers: {'allow': 'POST'});
      }
      return orderSummaryPdf(request, reads: reads, fonts: fonts);
    }
    if (path == editorDraftPath) {
      return editorDraftResponse(
        request,
        reads: reads,
        config: config,
        fonts: fonts,
      );
    }
    if (path == portalViewPath ||
        path == portalFilePath ||
        path == portalActionPath) {
      if (request.method != 'POST') {
        return Response(
          405,
          headers: {
            'allow': 'POST',
            'cache-control': 'no-store',
            'x-robots-tag': 'noindex',
          },
        );
      }
      return switch (path) {
        portalViewPath => portalViewResponse(request, reads: reads),
        portalFilePath => portalFileResponse(request, reads: reads),
        _ => portalActionResponse(request, reads: reads),
      };
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405, headers: {'allow': 'GET, HEAD'});
    }
    if (path == '/healthz') return Response.ok('ok');
    if (path.startsWith('/assets/') && config.assetsDir != null) {
      // Flutter publishes the asset key `assets/fonts/x.ttf` at
      // `/assets/assets/fonts/x.ttf`; the key is a path in the repository.
      return _localAsset(config.assetsDir!, path.substring('/assets/'.length));
    }
    if (path.startsWith('/fonts/') && config.assetsDir != null) {
      // Hosting serves `web/` at the root: the fonts' Latin subsets.
      return _localAsset(config.assetsDir!, 'web$path');
    }

    final List<String> segments;
    try {
      segments = Uri(
        path: path,
      ).pathSegments.where((segment) => segment.isNotEmpty).toList();
    } on Object {
      return _plainNotFound();
    }
    final route = _Route(
      config: config,
      reads: reads,
      request: request,
      path: path,
      hidden: hidden,
      flutterShell: flutterShell,
      draft: draft,
    );
    try {
      return switch (segments) {
        [] => await route.home(),
        ['productos'] => await route.catalog(null),
        ['productos', 'categoria', final slug] => await route.catalog(slug),
        ['servicios'] => await route.catalog(null, services: true),
        ['servicios', 'categoria', final slug] => await route.catalog(
          slug,
          services: true,
        ),
        ['productos', final slug, final sku] => await route.product(slug, sku),
        ['productos', final id] => await route.legacyProduct(id),
        ['producto', final id] => await route.legacyProduct(id),
        [final slug] when publicPolicySlugs.contains(slug) =>
          await route.policy(slug),
        ['contacto'] => await route.contact(),
        ['pagina', final slug] => await route.editorPage(slug),
        ['carrito'] => await route.cart(),
        ['carrito', 'lineas'] => await route.cartLines(),
        ['checkout'] => await route.checkout(),
        ['checkout', 'lineas'] => await route.checkoutLines(),
        ['pedido', final id] when _orderIdPattern.hasMatch(id) =>
          await route.order(id),
        ['cuenta', 'login'] => await route.login(),
        ['cuenta'] ||
        [
          'cuenta',
          'pedidos' || 'servicios' || 'bicicletas' || 'perfil' || 'direcciones',
        ] => await route.portal(PortalPage.ofPath('/${segments.join('/')}')!),
        // Old addresses, answered with a permanent redirect as Flutter did
        // in the browser: Hosting hands this server every path no other rule
        // claims, so they and an unknown path get a real status.
        ['tienda', 'producto' || 'productos', final id]
            when _uuid.hasMatch(id) =>
          await route.legacyProduct(id),
        ['tienda', ...final rest] => route.legacyStorePath(rest),
        ['cuenta', 'mensajes'] => route.oldChats(null),
        ['cuenta', 'mensajes', final id] => route.oldChats(id),
        _ => await route.notFound(),
      };
    } on PublicReadException catch (error) {
      stderr.writeln('read failed for $path: $error');
      return _readFailed();
    } on TimeoutException catch (error) {
      stderr.writeln('read timed out for $path: $error');
      return _readFailed();
    } on SocketException catch (error) {
      stderr.writeln('read failed for $path: $error');
      return _readFailed();
    } on HttpException catch (error) {
      // A connection the other side closed, even after one retry.
      stderr.writeln('read failed for $path: $error');
      return _readFailed();
    }
  };
}

class _Route {
  _Route({
    required this.config,
    required this.reads,
    required this.request,
    required this.path,
    required this.hidden,
    required this.flutterShell,
    this.draft = false,
  });

  final StorefrontConfig config;
  final PublicReads reads;
  final Request request;
  final String path;
  final bool hidden;
  final FlutterShell? flutterShell;
  final bool draft;

  /// The site is unpublished: the visitor gets the notice, the editor's
  /// draft the page it is editing.
  bool _closed(PageContext context) => !draft && !context.shell.sitePublished;
  final _watch = Stopwatch()..start();

  Uri get _uri => request.requestedUri;

  PageContext _context(ShellReads read) => PageContext(
    shell: StorefrontShell.fromJson(
      read.shell,
      checkoutCapabilities: read.payments,
    ),
    tenantId: config.tenantId,
    fallbackOrigin: config.storeOrigin,
    path: path,
    query: _uri.query,
    hidden: hidden,
    supabaseUrl: config.supabaseUrl,
    publishableKey: config.publishableKey,
    draft: draft,
  );

  /// `/productos` or a category, with the visitor's search and filters.
  /// `/productos` or, with [services], `/servicios`: the same catalog for the
  /// workshop's services, as Flutter's `_defaultProductTypeForRoute`.
  Future<Response> catalog(String? slug, {bool services = false}) async {
    final parsed = parseCatalogQuery(_uri);
    final legacy = slug == null ? _legacyCategoryValue() : null;
    if (legacy != null) {
      return _legacyCategoryCatalog(legacy, parsed, services: services);
    }
    if (slug == null && services) {
      // `/servicios` may be a price list, which lists every service: its
      // first hundred rows, without filters, are read with the shell, the
      // rest once the shell says so. A grid reads its own page instead, and
      // that first read (rows only) is the one wasted.
      final firstPage = reads.catalog(_listingPage(0));
      // Listened to at once: a failure while the shell is read would
      // otherwise be an unhandled error; awaiting it below still throws.
      firstPage.ignore();
      final context = _context(await reads.shell());
      final priceList =
          context.shell.sitePublished &&
          context.shell.presentations
                  .forCatalogRoot(WebsiteCatalogRoot.services)
                  ?.isPriceList ==
              true;
      if (_closed(context)) return _unpublished(context);
      return _catalogPage(
        context,
        null,
        parsed,
        priceList
            ? await _wholeListing(await firstPage)
            : await reads.catalog(
                catalogRequestFor(
                  shell: null,
                  categoryId: null,
                  query: parsed.query,
                  services: true,
                ),
              ),
        dataMs: _watch.elapsedMilliseconds,
        services: true,
      );
    }
    if (slug == null) {
      // The listing does not depend on the shell: read both at once.
      final results = await Future.wait<Object>([
        reads.shell(),
        reads.catalog(
          catalogRequestFor(
            shell: null,
            categoryId: null,
            query: parsed.query,
            services: services,
          ),
        ),
      ]);
      final context = _context(results[0] as ShellReads);
      if (_closed(context)) return _unpublished(context);
      return _catalogPage(
        context,
        null,
        parsed,
        results[1] as CatalogReads,
        dataMs: _watch.elapsedMilliseconds,
        services: services,
      );
    }

    final context = _context(await reads.shell());
    if (_closed(context)) return _unpublished(context);
    final shell = context.shell;
    final resolved = shell.resolveCategorySlug(slug);
    if (resolved == null) {
      return _render(
        unavailableCategoryDocument(context, services: services),
        status: 404,
      );
    }
    final canonical = shell.categoryPath(resolved.id, services: services);
    if (resolved.alias || canonical != path) {
      return _redirect(canonical, query: _uri.query);
    }
    final catalog = await reads.catalog(
      catalogRequestFor(
        shell: shell,
        categoryId: resolved.id,
        query: parsed.query,
        services: services,
      ),
    );
    return _catalogPage(
      context,
      resolved.id,
      parsed,
      catalog,
      dataMs: _watch.elapsedMilliseconds,
      services: services,
    );
  }

  /// One page of 100 (the read's ceiling) of every published service, in
  /// name order and without the URL's filters: a price list shows them all
  /// and its search only hides rows (`?q=` included), so clearing it brings
  /// them back.
  CatalogRequest _listingPage(int offset) => CatalogRequest(
    categoryIds: null,
    searchQuery: '',
    brandIds: const [],
    specFilters: null,
    minPrice: null,
    maxPrice: null,
    onlyInStock: false,
    sortBy: 'name',
    limit: 100,
    offset: offset,
    services: true,
    facets: false,
  );

  /// Every row of the services listing, from its [first] page on.
  Future<CatalogReads> _wholeListing(CatalogReads first) async {
    final products = [...first.products];
    final thumbnails = [...first.thumbnails];
    int total(List<Object?> rows) => rows.isNotEmpty && rows.first is Map
        ? ((rows.first as Map)['total_count'] as num?)?.toInt() ?? rows.length
        : 0;
    final all = total(first.products);
    // Up to the listing's own total; fifty pages only guard against a
    // total that never ends.
    for (var offset = 100; offset < all && offset < 5000; offset += 100) {
      final next = await reads.catalog(_listingPage(offset));
      if (next.products.isEmpty) break;
      products.addAll(next.products);
      thumbnails.addAll(next.thumbnails);
    }
    return (
      products: products,
      brandRows: first.brandRows,
      thumbnails: thumbnails,
      facets: first.facets,
      optionLabels: first.optionLabels,
    );
  }

  Future<Response> _catalogPage(
    PageContext context,
    String? categoryId,
    ParsedCatalogQuery parsed,
    CatalogReads catalog, {
    required int dataMs,
    bool services = false,
  }) {
    final model = CatalogPageModel.build(
      page: context,
      uri: _uri,
      query: parsed.query,
      queryError: parsed.error,
      categoryId: categoryId,
      reads: catalog,
      services: services,
    );
    return _render(
      model.priceList != null
          ? catalogPriceListDocument(model)
          : catalogPageDocument(model),
      indexable: model.meta.indexable,
      dataMs: dataMs,
    );
  }

  /// `/productos/<slug>/<sku>`. Another slug for the same SKU, or an old path
  /// kept in `product_url_aliases`, answers with a permanent redirect.
  Future<Response> product(String slug, String sku) async =>
      _productPage(await reads.productPage(sku: sku));

  Future<Response> _productPage(ProductPageReads data) async {
    final context = _context((shell: data.shell, payments: data.payments));
    if (_closed(context)) return _unpublished(context);
    final read = data.page;
    if (read == null || read['product'] is! Map) {
      final target = await _aliasTarget(path);
      if (target != null) return _redirect(target, query: _uri.query);
      return _productNotFound(context);
    }
    final model = ProductPageModel.build(page: context, read: read);
    if (!_samePath(model.path, path)) {
      return _redirect(model.path, query: _uri.query);
    }
    return _render(
      productPageDocument(model),
      indexable: model.meta.indexable,
      dataMs: _watch.elapsedMilliseconds,
    );
  }

  /// `/productos/<uuid>` and `/producto/<uuid>`, the product routes before
  /// the SKU one, and any old path in `product_url_aliases`.
  Future<Response> legacyProduct(String id) async {
    String? target;
    if (_uuid.hasMatch(id)) {
      target = await _productPath(id);
      // A product without a SKU lives at its UUID route: it is drawn here.
      if (target != null && _samePath(target, path)) {
        return _productPage(await reads.productPage(productId: id));
      }
    }
    target ??= await _aliasTarget(path);
    if (target != null && !_samePath(target, path)) {
      return _redirect(target, query: _uri.query);
    }
    final context = _context(await reads.shell());
    if (_closed(context)) return _unpublished(context);
    return _productNotFound(context);
  }

  /// `/tienda/...`, where the store lived inside the ERP's web app: the
  /// same path without the prefix, with its query.
  Response legacyStorePath(List<String> rest) => _redirect(
    '/${rest.map(Uri.encodeComponent).join('/')}',
    query: _uri.query,
  );

  /// `/cuenta/mensajes[/<id>]`, the chats' old address.
  Response oldChats(String? id) => _redirect(
    id == null ? '/cuenta/chats' : '/cuenta/chats/${Uri.encodeComponent(id)}',
    query: _uri.query,
  );

  /// `/nosotros`, `/envios`, `/devoluciones`, `/terminos`, `/privacidad`:
  /// the editor page and its blocks. A page without public content answers
  /// 404 with the same message Flutter shows.
  Future<Response> policy(String slug) async {
    final data = await reads.policyPages();
    final context = _context((shell: data.shell, payments: data.payments));
    if (_closed(context)) return _unpublished(context);
    final model = PolicyPageModel.build(page: context, slug: slug, reads: data);
    if (model.available) {
      if (await _flutterFallback(
            context,
            model.uncoveredTypes,
            meta: model.meta,
            document: policyPageDocument(model),
          )
          case final fallback?) {
        return fallback;
      }
    }
    final response = await _render(
      policyPageDocument(model),
      status: model.available ? 200 : 404,
      indexable: model.meta.indexable,
      dataMs: _watch.elapsedMilliseconds,
    );
    if (model.uncoveredTypes.isEmpty) return response;
    return response.change(
      headers: {'x-storefront-uncovered': model.uncoveredTypes.join(',')},
    );
  }

  /// `/contacto`: the store's contact page, or «Contacto no disponible»
  /// with a 404 while the editor has it unpublished.
  Future<Response> contact() async {
    final data = await reads.contactPage();
    final context = _context((shell: data.shell, payments: data.payments));
    if (_closed(context)) return _unpublished(context);
    final model = ContactPageModel.build(page: context, reads: data);
    return _render(
      contactPageDocument(model),
      status: model.available ? 200 : 404,
      indexable: model.meta.indexable,
      dataMs: _watch.elapsedMilliseconds,
    );
  }

  /// `/carrito`: the frame of the cart; its lines come from [cartLines].
  Future<Response> cart() async {
    final context = _context(await reads.shell());
    if (_closed(context)) return _unpublished(context);
    return _render(cartPageDocument(context));
  }

  /// `/carrito/lineas?l=<id>:<q>,…`: the visitor's saved lines, re-read
  /// and drawn, as JSON for the cart page. Never stored by a cache: it is
  /// this visitor's basket at this moment.
  Future<Response> cartLines() async =>
      _json(cartLinesJson(await _savedLines()));

  /// `/checkout`: the form, the same for everyone, with the payment methods
  /// the store accepts now; the lines come from [checkoutLines].
  Future<Response> checkout() async {
    final read = await reads.shell();
    final context = _context(read);
    if (_closed(context)) return _unpublished(context);
    final methods = CheckoutPageData.methodsOf(read.payments);
    return _render(
      checkoutPageDocument(
        CheckoutPageData(
          page: context,
          methods: methods ?? const [],
          methodsKnown: methods != null,
          supabaseUrl: config.supabaseUrl,
          publishableKey: config.publishableKey,
        ),
      ),
    );
  }

  /// `/pedido/<id>`: the frame of the order page; the order comes from the
  /// access this tab keeps, so the script reads it.
  Future<Response> order(String id) async {
    final context = _context(await reads.shell());
    if (_closed(context)) return _unpublished(context);
    return _render(
      orderPageDocument(
        OrderPageData(
          page: context,
          orderId: id,
          supabaseUrl: config.supabaseUrl,
          publishableKey: config.publishableKey,
        ),
      ),
    );
  }

  /// `/cuenta/**` (4a, 4b): the frame; the customer's page comes from
  /// [portalViewResponse] with the session this browser keeps.
  Future<Response> portal(PortalPage which) async {
    final context = _context(await reads.shell());
    if (_closed(context)) return _unpublished(context);
    return _render(portalPageDocument(context, which));
  }

  /// `/cuenta/login` (4c): the way in. A link back from Supabase Auth
  /// ([loginIsAuthReturn]) is answered with the Flutter store, which redeems
  /// it, with the login's head; when that page cannot be read the visitor is
  /// asked to try again rather than shown a page that would drop the link.
  Future<Response> login() async {
    final context = _context(await reads.shell());
    if (_closed(context)) return _unpublished(context);
    final document = loginPageDocument(context);
    if (hidden || !loginIsAuthReturn(_uri.queryParameters.keys)) {
      return _render(document);
    }
    final shell = await flutterShell?.html(context.storeUrl);
    if (shell == null) return _readFailed();
    final rendered = await renderComponent(document, request: request);
    final html = adaptFlutterShell(
      shell,
      loginPageMeta(context),
      main: mainContentOf(utf8.decode(rendered.body)),
    );
    final gzipped = _acceptsGzip(request)
        ? gzip.encode(utf8.encode(html))
        : null;
    return Response(
      200,
      body: gzipped ?? html,
      headers: {
        ..._pageHeaders(noindex: true),
        'vary': 'accept-encoding',
        'content-encoding': ?(gzipped == null ? null : 'gzip'),
        'x-storefront-fallback': 'flutter',
      },
    );
  }

  /// `/checkout/lineas?l=<id>:<q>,…`: the cart's lines with what the order
  /// states of each one.
  Future<Response> checkoutLines() async =>
      _json(checkoutLinesJson(await _savedLines()));

  Future<CartLinesModel> _savedLines() async {
    final saved = parseSavedCartLines(
      request.requestedUri.queryParameters['l'] ?? '',
    );
    return CartLinesModel.build(
      saved: saved,
      reads: await reads.cartProducts([for (final line in saved) line.id]),
      tenantId: config.tenantId,
    );
  }

  Response _json(Map<String, Object?> value) {
    final body = utf8.encode(jsonEncode(value));
    final gzipped = _acceptsGzip(request) ? gzip.encode(body) : null;
    return Response.ok(
      gzipped ?? body,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        'x-robots-tag': 'noindex',
        'vary': 'accept-encoding',
        'content-encoding': ?(gzipped == null ? null : 'gzip'),
      },
    );
  }

  /// `/`: the editor's home page and its blocks.
  Future<Response> home() async {
    final data = await reads.homePage(pagePicks);
    final context = _context((shell: data.shell, payments: data.payments));
    if (_closed(context)) return _unpublished(context);
    if (data.page == null) return notFound();
    final model = HomePageModel.build(page: context, reads: data, draft: draft);
    if (await _flutterFallback(
          context,
          model.uncoveredTypes,
          meta: model.meta,
          document: homePageDocument(model),
        )
        case final fallback?) {
      return fallback;
    }
    final response = await _render(
      homePageDocument(model),
      indexable: model.meta.indexable,
      dataMs: _watch.elapsedMilliseconds,
    );
    if (model.uncoveredTypes.isEmpty) return response;
    return response.change(
      headers: {'x-storefront-uncovered': model.uncoveredTypes.join(',')},
    );
  }

  /// `/pagina/<slug>`: a page the editor creates and its blocks
  /// (`DynamicWebsitePage`, which reads the slug in lower case).
  Future<Response> editorPage(String requested) async {
    final slug = requested.trim().toLowerCase();
    if (slug.isEmpty || slug.length > 200) return notFound();
    if (slug != requested) {
      return _redirect(
        '/${Uri(pathSegments: ['pagina', slug])}',
        query: _uri.query,
      );
    }
    final data = await reads.websitePage(slug, pagePicks);
    final context = _context((shell: data.shell, payments: data.payments));
    if (_closed(context)) return _unpublished(context);
    if (data.page == null) return notFound();
    final model = EditorPageModel.build(
      page: context,
      slug: slug,
      reads: data,
      draft: draft,
    );
    if (await _flutterFallback(
          context,
          model.uncoveredTypes,
          meta: model.meta,
          document: editorPageDocument(model),
        )
        case final fallback?) {
      return fallback;
    }
    final response = await _render(
      editorPageDocument(model),
      indexable: model.meta.indexable,
      dataMs: _watch.elapsedMilliseconds,
    );
    if (model.uncoveredTypes.isEmpty) return response;
    return response.change(
      headers: {'x-storefront-uncovered': model.uncoveredTypes.join(',')},
    );
  }

  Future<Response> notFound() async {
    final context = _context(await reads.shell());
    return _render(
      _messagePage(
        context,
        title: 'No encontramos esta página',
        text: 'Puede que el enlace haya cambiado.',
      ),
      status: 404,
    );
  }

  /// The canonical path of a published product, by id.
  Future<String?> _productPath(String id) async {
    final row = await reads.productById(id);
    if (row == null) return null;
    final target = publicProductPath(Product.fromJson(row));
    return target == '/productos' ? null : target;
  }

  Future<String?> _aliasTarget(String aliasPath) async {
    final id = await reads.productIdForAlias(aliasPath);
    return id == null ? null : _productPath(id);
  }

  /// A category the old `?category=`, `?category_id=` or `?cat=` names, by
  /// id or slug, when it is published.
  /// The old `?category=`, `?category_id=` or `?cat=`, in the Flutter
  /// catalog's order of precedence (the first present wins, even empty).
  String? _legacyCategoryValue() {
    final parameters = _uri.queryParameters;
    final value =
        (parameters['category'] ??
                parameters['category_id'] ??
                parameters['cat'] ??
                '')
            .trim();
    return value.isEmpty ? null : value;
  }

  /// `/productos?category=<value>`: a published category opens at its own
  /// path; anything else that is not a UUID is searched for, unless the URL
  /// already searches, as the Flutter catalog does.
  Future<Response> _legacyCategoryCatalog(
    String value,
    ParsedCatalogQuery parsed, {
    bool services = false,
  }) async {
    final context = _context(await reads.shell());
    if (_closed(context)) return _unpublished(context);
    final id = context.shell.resolveCategorySlug(value)?.id;
    if (id != null) {
      return _redirect(
        context.shell.categoryPath(id, services: services),
        query: _withoutKeys(_uri, const {'category', 'category_id', 'cat'}),
      );
    }
    final query = !_uuid.hasMatch(value) && parsed.query.searchQuery.isEmpty
        ? (query: _withSearch(parsed.query, value), error: parsed.error)
        : parsed;
    final catalog = await reads.catalog(
      catalogRequestFor(
        shell: null,
        categoryId: null,
        query: query.query,
        services: services,
      ),
    );
    return _catalogPage(
      context,
      null,
      query,
      catalog,
      dataMs: _watch.elapsedMilliseconds,
      services: services,
    );
  }

  Future<Response> _productNotFound(PageContext context) => _render(
    _messagePage(
      context,
      title: 'Producto no encontrado',
      text: 'Puede que ya no esté a la venta o que el enlace haya cambiado.',
    ),
    status: 404,
  );

  Future<Response> _unpublished(PageContext context) =>
      _render(unpublishedPage(context), indexable: false);

  Response _redirect(String target, {String query = ''}) {
    final location =
        '${hidden ? hiddenRoutePrefix : ''}$target'
        '${query.isEmpty ? '' : '?$query'}';
    return Response(
      301,
      headers: {
        'location': location,
        'cache-control': 'public, max-age=300',
        if (hidden) 'x-robots-tag': 'noindex',
      },
    );
  }

  /// On a public path, a page with blocks the HTML does not draw yet is
  /// answered with the Flutter store, which draws it whole, carrying this
  /// page's head and words for crawlers ([adaptFlutterShell]); the hidden
  /// copy shows what the HTML draws, to measure it.
  Future<Response?> _flutterFallback(
    PageContext context,
    Set<String> uncovered, {
    required PageMeta meta,
    required Component document,
  }) async {
    if (uncovered.isEmpty || hidden) return null;
    final shell = await flutterShell?.html(context.storeUrl);
    if (shell == null) return null;
    final rendered = await renderComponent(document, request: request);
    final html = adaptFlutterShell(
      shell,
      meta,
      main: mainContentOf(utf8.decode(rendered.body)),
    );
    final gzipped = _acceptsGzip(request)
        ? gzip.encode(utf8.encode(html))
        : null;
    return Response(
      200,
      body: gzipped ?? html,
      headers: {
        ..._pageHeaders(noindex: !meta.indexable),
        'vary': 'accept-encoding',
        'content-encoding': ?(gzipped == null ? null : 'gzip'),
        'x-storefront-uncovered': uncovered.join(','),
        'x-storefront-fallback': 'flutter',
      },
    );
  }

  Future<Response> _render(
    Component document, {
    int status = 200,
    bool indexable = false,
    int? dataMs,
  }) async {
    final data = dataMs ?? _watch.elapsedMilliseconds;
    final rendered = await renderComponent(document, request: request);
    final html = rendered.body;
    // Neither Cloud Run nor Firebase Hosting compresses a proxied page
    // (measured 2026-10-05: 64 KB sent as is), so it is compressed here:
    // ~5× less to send to a slow phone and out of Cloud Run.
    final gzipped = _acceptsGzip(request) ? gzip.encode(html) : null;
    final renderMs = _watch.elapsedMilliseconds - data;
    return Response(
      status,
      body: gzipped ?? html,
      headers: {
        ..._pageHeaders(noindex: hidden || !indexable || status != 200),
        'vary': 'accept-encoding',
        'content-encoding': ?(gzipped == null ? null : 'gzip'),
        'server-timing': 'data;dur=$data, render;dur=$renderMs',
      },
    );
  }
}

/// A catalog URL's query, read the way the Flutter catalog reads it, plus
/// what a plain HTML form sends: a checkbox list repeats its name
/// (`brand=a&brand=b`) and an empty field still sends `min_price=`.
typedef ParsedCatalogQuery = ({WebsiteCatalogQuery query, String? error});

ParsedCatalogQuery parseCatalogQuery(Uri uri) {
  final merged = <String, String>{};
  uri.queryParametersAll.forEach((key, values) {
    final present = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (present.isEmpty) return;
    final listed =
        WebsiteCatalogQuery.specFilterKeyFromParameter(key) != null ||
        const {
          'brand',
          'brands',
          'brand_id',
          'brand_ids',
          'marca',
          'marcas',
        }.contains(key);
    merged[key] = listed ? present.join(',') : present.last;
  });
  // Old links used `?categoria=mtb` as a collection; Flutter searches it.
  final legacy = merged.remove('categoria');
  if (legacy != null && !merged.containsKey('q')) merged['q'] = legacy;

  final query = WebsiteCatalogQuery.tryParse(
    Uri(path: uri.path, queryParameters: merged),
  );
  if (query == null) {
    return (
      query: WebsiteCatalogQuery(),
      error: 'La URL contiene filtros de catálogo inválidos.',
    );
  }
  if (query.stock == WebsiteCatalogStockFilter.unavailable) {
    return (
      query: _withoutStock(query),
      error:
          'El filtro exclusivo de productos agotados todavía no está disponible.',
    );
  }
  return (query: query, error: null);
}

WebsiteCatalogQuery _withSearch(WebsiteCatalogQuery q, String search) =>
    WebsiteCatalogQuery(
      searchQuery: search,
      productType: q.productType,
      categoryScope: q.categoryScope,
      brandIds: q.brandIds,
      specFilters: q.specFilters,
      minPrice: q.minPrice,
      maxPrice: q.maxPrice,
      stock: q.stock,
      sort: q.sort,
      page: q.page,
      pageSize: q.pageSize,
    );

WebsiteCatalogQuery _withoutStock(WebsiteCatalogQuery q) => WebsiteCatalogQuery(
  searchQuery: q.searchQuery,
  productType: q.productType,
  categoryScope: q.categoryScope,
  brandIds: q.brandIds,
  specFilters: q.specFilters,
  minPrice: q.minPrice,
  maxPrice: q.maxPrice,
  sort: q.sort,
  page: q.page,
  pageSize: q.pageSize,
);

String _withoutKeys(Uri uri, Set<String> keys) {
  final kept = [
    for (final entry in uri.queryParametersAll.entries)
      if (!keys.contains(entry.key))
        for (final value in entry.value)
          '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(value)}',
  ];
  return kept.join('&');
}

/// The same product page whatever the encoding of its SKU.
bool _samePath(String canonical, String requested) {
  try {
    return _listEquals(
      Uri(path: canonical).pathSegments,
      Uri(path: requested).pathSegments,
    );
  } on Object {
    return false;
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Component _messagePage(
  PageContext context, {
  required String title,
  required String text,
}) => sitePage(
  context: context,
  meta: PageMeta(
    title: '$title · ${context.shell.storeName}',
    description: text,
    canonicalUrl: '${context.storeUrl}/productos',
    indexable: false,
  ),
  content: [
    div(classes: 'wrap notfound', [
      h1([.text(title)]),
      p([.text(text)]),
      a(classes: 'primary-link', href: '/productos', [
        .text('Ver todos los productos'),
      ]),
    ]),
  ],
);

/// `Accept-Encoding` names gzip with a weight above zero (`gzip;q=0` refuses
/// it).
bool _acceptsGzip(Request request) {
  for (final part in (request.headers['accept-encoding'] ?? '').split(',')) {
    final pieces = part.split(';');
    if (pieces.first.trim().toLowerCase() != 'gzip') continue;
    for (final parameter in pieces.skip(1)) {
      final pair = parameter.split('=');
      if (pair.length == 2 && pair.first.trim().toLowerCase() == 'q') {
        return (double.tryParse(pair.last.trim()) ?? 0) > 0;
      }
    }
    return true;
  }
  return false;
}

Map<String, String> _pageHeaders({
  required bool noindex,
  String contentType = 'text/html; charset=utf-8',
}) => {
  'content-type': contentType,
  'cache-control': 'private, no-cache',
  if (noindex) 'x-robots-tag': 'noindex',
};

Response _readFailed() => Response(
  503,
  body: utf8.encode(
    '<!DOCTYPE html><html lang="es-CL"><meta charset="utf-8">'
    '<meta name="robots" content="noindex"><title>Intenta de nuevo</title>'
    '<p>La tienda no pudo leer esta página. Intenta de nuevo en un momento.</p>',
  ),
  headers: {..._pageHeaders(noindex: true), 'retry-after': '5'},
);

Response _plainNotFound() => Response.notFound(
  utf8.encode(
    '<!DOCTYPE html><html lang="es-CL"><meta charset="utf-8">'
    '<meta name="robots" content="noindex"><title>No encontrado</title>'
    '<p>No encontramos esta página. <a href="/productos">Ver productos</a></p>',
  ),
  headers: _pageHeaders(noindex: true),
);

Future<Response> _localAsset(String root, String relative) async {
  if (relative.contains('..')) return Response.notFound(null);
  // A package's asset (`packages/font_awesome_flutter/lib/fonts/x.ttf`) is in
  // that package's folder, which the repository's package config names.
  var path = '$root/$relative';
  final package = RegExp(r'^packages/([^/]+)/(.+)$').firstMatch(relative);
  if (package != null) {
    final packageRoot = await _packageRoot(root, package.group(1)!);
    if (packageRoot == null) return Response.notFound(null);
    path = '$packageRoot/${package.group(2)}';
  }
  final file = File(path);
  if (!await file.exists()) return Response.notFound(null);
  final type = switch (relative.split('.').last) {
    'ttf' => 'font/ttf',
    'woff2' => 'font/woff2',
    'otf' => 'font/otf',
    'webp' => 'image/webp',
    'png' => 'image/png',
    'svg' => 'image/svg+xml',
    _ => 'application/octet-stream',
  };
  return Response.ok(
    file.openRead(),
    headers: {
      'content-type': type,
      'cache-control': 'public, max-age=31536000, immutable',
    },
  );
}

Future<String?> _packageRoot(String repository, String name) async {
  final config = File('$repository/.dart_tool/package_config.json');
  if (!await config.exists()) return null;
  final packages =
      (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
  for (final entry in packages.cast<Map>()) {
    if (entry['name'] != name) continue;
    final uri = Uri.parse(entry['rootUri'] as String);
    return uri.isAbsolute
        ? uri.toFilePath()
        : Uri.file('$repository/.dart_tool/').resolveUri(uri).toFilePath();
  }
  return null;
}

/// An order id as the store issues them (a UUID); anything else is a page
/// that is not there.
final _orderIdPattern = RegExp(r'^[0-9A-Za-z-]{1,64}$');
