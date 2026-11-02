import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'material_icons.dart';
import 'quote_page_css.dart';
import 'quote_page_model.dart';
import 'quote_page_script.dart';
import 'site_layout.dart';

/// What the quote page needs that only the server knows: where the browser
/// reaches Supabase for the public quote commands (20261102041700).
class QuotePageData {
  const QuotePageData({
    required this.page,
    required this.supabaseUrl,
    required this.publishableKey,
  });

  final PageContext page;
  final String supabaseUrl;
  final String publishableKey;
}

/// `/cotizacion`: the quote the visitor puts together (products in stock and
/// on order, kept in this browser like the cart), the form that sends it, and
/// a sent quote opened with its link (`/cotizacion#t=<link>`): the offer, its
/// answers and its history. The link never reaches the server: it travels in
/// the fragment and the script reads the quote with it.
Component quotePageDocument(QuotePageData data) {
  final page = data.page;
  final shell = page.shell;
  final prefix = page.hidden ? '/_html' : '';
  return sitePage(
    context: page,
    meta: PageMeta(
      title: 'Tu cotización | ${shell.storeName}',
      description:
          'Cotiza productos en stock y a pedido en ${shell.storeName}: '
          'precio, plazo y disponibilidad confirmados.',
      canonicalUrl: '${page.storeUrl}$quotePagePath',
      indexable: false,
      styles: quotePageCss,
    ),
    content: [
      div(
        classes: 'qt-page',
        attributes: {
          'data-qt': '',
          'data-tenant': page.tenantId,
          'data-sb-url': data.supabaseUrl,
          'data-sb-key': data.publishableKey,
          'data-lines-url': '$prefix$quoteLinesPath',
          'data-store': shell.storeName,
          'data-icon-photo': materialIcon(mdPedalBikeOutlined, size: 28),
        },
        [
          div(classes: 'qt-in', [
            p(
              classes: 'qt-load',
              attributes: {'data-qt-loading': ''},
              [.text('Cargando tu cotización…')],
            ),
            section(
              classes: 'qt-build',
              attributes: {'data-qt-build': '', 'hidden': ''},
              [
                div(classes: 'qt-head', [
                  p(classes: 'qt-kick', [.text('Cotización')]),
                  h1(classes: 'qt-title', [.text('Tu cotización')]),
                  p(classes: 'qt-lede', [
                    .text(
                      'Junta productos en stock y a pedido. Te respondemos con '
                      'el precio, el plazo y la disponibilidad confirmados.',
                    ),
                  ]),
                ]),
                div(classes: 'qt-grid', [
                  div(classes: 'qt-col', [
                    ul(
                      classes: 'qt-lines',
                      attributes: {'data-qt-lines': ''},
                      [],
                    ),
                    p(classes: 'qt-ref', attributes: {'data-qt-ref': ''}, []),
                  ]),
                  RawText(_formHtml),
                ]),
              ],
            ),
            section(
              classes: 'qt-empty',
              attributes: {'data-qt-empty': '', 'hidden': ''},
              [
                h1(classes: 'qt-title', [.text('Tu cotización está vacía')]),
                p(classes: 'qt-lede', [
                  .text(
                    'Agrega productos desde su ficha con «Agregar a la '
                    'cotización». Los agotados se cotizan a pedido.',
                  ),
                ]),
                a(classes: 'qt-btn fill', href: '/productos', [
                  .text('Ver productos'),
                ]),
              ],
            ),
            section(
              classes: 'qt-view',
              attributes: {'data-qt-view': '', 'hidden': ''},
              [],
            ),
            div(
              classes: 'qt-toast',
              attributes: {'data-qt-toast': '', 'hidden': '', 'role': 'status'},
              [],
            ),
          ]),
        ],
      ),
    ],
    pageScripts: [script(content: quotePageScript)],
  );
}

/// The form is plain HTML: the script validates and sends it; without
/// JavaScript there is nothing to send to, so it says so.
const _formHtml = '''
<form class="qt-form" data-qt-form novalidate>
  <h2 class="qt-h2">Tus datos</h2>
  <label class="qt-field"><span>Nombre</span>
    <input name="name" autocomplete="name" maxlength="120" required></label>
  <fieldset class="qt-channel">
    <legend>Te enviamos la respuesta por</legend>
    <label><input type="radio" name="channel" value="whatsapp" checked><span>WhatsApp</span></label>
    <label><input type="radio" name="channel" value="email"><span>Correo</span></label>
  </fieldset>
  <label class="qt-field" data-qt-phone><span>Teléfono (WhatsApp)</span>
    <input name="phone" type="tel" autocomplete="tel" inputmode="tel" placeholder="+56 9 1234 5678" maxlength="20"></label>
  <label class="qt-field" data-qt-email><span>Correo</span>
    <input name="email" type="email" autocomplete="email" maxlength="160" placeholder="nombre@correo.cl"></label>
  <label class="qt-field"><span>Comentarios <i>(opcional)</i></span>
    <textarea name="notes" rows="3" maxlength="2000" placeholder="Por ejemplo: para una bici aro 29, lo necesito antes del sábado."></textarea></label>
  <p class="qt-err" data-qt-err hidden></p>
  <button class="qt-btn fill" type="submit" data-qt-send>Pedir cotización</button>
  <p class="qt-fine">No es una compra. Te enviamos una oferta que puedes aceptar, cambiar o rechazar.</p>
  <noscript><p class="qt-fine">Para enviar la cotización hace falta JavaScript.</p></noscript>
</form>
''';
