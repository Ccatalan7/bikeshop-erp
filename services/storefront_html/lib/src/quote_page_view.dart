import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'checkout_records_script.dart';
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
/// a sent quote opened with its link (`/cotizacion#t=<link>`, or
/// `/cotizacion#q=<id>` from «Mi cuenta»): the offer, its answers and its
/// history. The link never reaches the server: it travels in the fragment and
/// the script reads the quote with it.
///
/// Sending asks for the customer's account (owner, 2026-11-02): the contact
/// is the account's and the customer only picks how to be told — email,
/// WhatsApp or both (20261102175500).
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
          'data-login-url': '$prefix/cuenta/login',
          'data-profile-url': '$prefix/cuenta/perfil',
          'data-account-url': '$prefix/cuenta/cotizaciones',
          'data-order-url': '$prefix/pedido/',
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
    // The checkout's records first: accepting leaves the order's access where
    // the order page reads it.
    pageScripts: [
      script(content: checkoutRecordsScript),
      script(content: quotePageScript),
    ],
  );
}

/// The send box is plain HTML: the script reads the session and shows the
/// way in or the account with its two notices; without JavaScript there is
/// nothing to send to, so it says so. The links carry their store path from
/// the page's data (`data-login-url`, `data-profile-url`).
const _formHtml = '''
<div class="qt-form" data-qt-box>
  <h2 class="qt-h2">Tus datos</h2>
  <p class="qt-copy" data-qt-checking>Revisando tu cuenta…</p>
  <div data-qt-signin hidden>
    <p class="qt-copy">Para enviarla, entra a tu cuenta. Te respondemos por correo o WhatsApp, como prefieras.</p>
    <a class="qt-btn fill" href="/cuenta/login" data-qt-login>Entrar o crear cuenta</a>
    <p class="qt-fine">Tu cotización queda guardada mientras entras.</p>
  </div>
  <form data-qt-form novalidate hidden>
    <div class="qt-who">
      <p class="qt-who-name" data-qt-who-name></p>
      <p class="qt-who-line" data-qt-who-line></p>
      <a class="qt-who-edit" href="/cuenta/perfil" data-qt-profile>Editar mis datos</a>
    </div>
    <fieldset class="qt-notify" data-qt-notify>
      <legend>¿Por dónde te avisamos?</legend>
      <div class="qt-notify-row">
        <label><input type="checkbox" name="notify_email"><span>Correo</span></label>
        <label><input type="checkbox" name="notify_whatsapp"><span>WhatsApp</span></label>
      </div>
      <p class="qt-hint" data-qt-nophone hidden>Para recibirla por WhatsApp, agrega tu teléfono en <a href="/cuenta/perfil" data-qt-profile>tu cuenta</a>.</p>
    </fieldset>
    <label class="qt-field"><span>Comentarios <i>(opcional)</i></span>
      <textarea name="notes" rows="3" maxlength="2000" placeholder="Por ejemplo: para una bici aro 29, lo necesito antes del sábado."></textarea></label>
    <p class="qt-err" data-qt-err hidden></p>
    <button class="qt-btn fill" type="submit" data-qt-send>Pedir cotización</button>
    <p class="qt-fine">No es una compra. Te enviamos una oferta que puedes aceptar, cambiar o rechazar.</p>
  </form>
  <noscript><p class="qt-fine">Para enviar la cotización hace falta JavaScript.</p></noscript>
</div>
''';
