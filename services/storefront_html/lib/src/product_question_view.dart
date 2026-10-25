import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';
import 'package:vinabike_public_core/public_store/models/customer_chat_words.dart';
import 'package:vinabike_public_core/public_store/models/public_product_question.dart';

import 'material_icons.dart';
import 'portal_page_view.dart' show portalActionPath;
import 'product_page_model.dart';

/// «Pregunta por este producto» (2026-10-24, owner: customers wrote asking
/// for products they had to describe; «que de la opción de preguntar por
/// whatsapp o por el chat interno nuestro»). The buy column's box opens a
/// sheet with the product, the questions a visitor taps
/// ([PublicProductQuestion.suggestions]) and their own words, and sends it
/// by WhatsApp or by the portal's chat as a consultation about the product
/// (`create_customer_support_request` with the `product` context: the ERP's
/// conversation opens it). Without JavaScript the box's links still go to
/// WhatsApp with the product, and to the chat.
///
/// The box shows when the product page template keeps it
/// ([WebsiteProductPageTemplate.showAsk]); the help card under the technical
/// sheet opens the same sheet.
Component productQuestionBox(ProductPageModel page) {
  final inStock = page.inStock;
  final template = page.template;
  final whatsapp = page.shell.whatsappDigits;
  return div(
    classes: inStock ? 'qbox' : 'qbox lead',
    attributes: page.page.pick('product-page:buy', 'Foto y compra'),
    [
      div(classes: 'qbox-head', [
        RawText(materialIcon(mdChatBubbleOutlineRounded, size: 20)),
        div([
          p(classes: 'qbox-title', [
            .text(template.resolvedAskTitle(inStock: inStock)),
          ]),
          p(classes: 'qbox-lead', [
            .text(PublicProductQuestion.lead(inStock: inStock)),
          ]),
        ]),
      ]),
      div(classes: whatsapp.isEmpty ? 'qbox-ch one' : 'qbox-ch', [
        if (whatsapp.isNotEmpty)
          a(
            classes: 'q-wa',
            href: productQuestionWhatsAppHref(page),
            attributes: {
              'rel': 'noopener',
              'target': '_blank',
              'data-question-open': 'whatsapp',
              ..._item(page),
            },
            [
              RawText(_whatsAppGlyph),
              .text(PublicProductQuestion.whatsAppLabel),
            ],
          ),
        a(
          classes: 'q-chat',
          href: '/cuenta/chats',
          attributes: {'data-question-open': 'chat'},
          [
            RawText(materialIcon(mdChat, size: 18)),
            .text(PublicProductQuestion.chatLabel),
          ],
        ),
      ]),
    ],
  );
}

/// The sheet the box and the help card open: the product, the questions
/// to tap, the visitor's words and the two ways to send them.
Component productQuestionSheet(ProductPageModel page) {
  final c = page.commerce;
  final whatsapp = page.shell.whatsappDigits;
  final price = _price(page);
  final suggestions = PublicProductQuestion.suggestions(
    inStock: page.inStock,
    technical: page.sheet.hasTechnicalData,
  );
  return Component.element(
    tag: 'dialog',
    id: 'pregunta',
    classes: 'qs',
    attributes: {
      'aria-labelledby': 'qs-title',
      'data-question': '',
      'data-product-id': c.id,
      'data-item-id': c.sku.isNotEmpty ? c.sku : c.id,
      'data-item-name': c.title,
      // The product's part of the message; the visitor's words follow it.
      'data-base': _baseMessage(page),
      'data-wa': whatsapp,
      'data-action': portalActionPath,
      'data-sending': PublicProductQuestion.chatSending,
      'data-failed': PublicProductQuestion.chatFailed,
      'data-send': PublicProductQuestion.sendChat,
      'data-signin': PublicProductQuestion.chatSignIn,
      'data-max': '$customerChatMessageMaxLength',
    },
    children: [
      Component.element(
        tag: 'form',
        classes: 'qs-in',
        attributes: {'method': 'dialog', 'novalidate': ''},
        children: [
          div(classes: 'qs-head', [
            h2(id: 'qs-title', [.text(PublicProductQuestion.sheetTitle)]),
            button(
              classes: 'qs-x',
              attributes: {
                'type': 'submit',
                'value': 'close',
                'aria-label': 'Cerrar',
              },
              [RawText(materialIcon(mdClose, size: 20))],
            ),
          ]),
          div(classes: 'qs-product', [
            span(classes: 'qs-thumb', [
              if (page.photos.isNotEmpty)
                img(
                  src: page.photos.first.src,
                  alt: '',
                  width: 56,
                  height: 56,
                  attributes: {'decoding': 'async'},
                )
              else
                RawText(materialIcon(mdPedalBikeOutlined, size: 26)),
            ]),
            div([
              p(classes: 'qs-name', [.text(c.title)]),
              p(classes: 'qs-meta', [
                .text(
                  [
                    if (price.isNotEmpty) price,
                    if (c.sku.trim().isNotEmpty) 'SKU ${c.sku.trim()}',
                    page.inStock ? 'En stock' : 'Agotado',
                  ].join(' · '),
                ),
              ]),
            ]),
          ]),
          if (suggestions.isNotEmpty)
            Component.element(
              tag: 'fieldset',
              classes: 'qs-sugs',
              children: [
                Component.element(
                  tag: 'legend',
                  children: [.text(PublicProductQuestion.questionLabel)],
                ),
                div(classes: 'qs-chips', [
                  for (final text in suggestions)
                    button(
                      classes: 'qs-chip',
                      attributes: {
                        'type': 'button',
                        'data-sug': text,
                        'aria-pressed': 'false',
                      },
                      [.text(text)],
                    ),
                ]),
              ],
            ),
          label(classes: 'qs-field', [
            span(classes: 'sr', [.text('Tu pregunta')]),
            Component.element(
              tag: 'textarea',
              attributes: {
                'name': 'pregunta',
                'rows': '3',
                'maxlength': '${PublicProductQuestion.questionMaxLength}',
                'placeholder': PublicProductQuestion.questionHint,
                'autocapitalize': 'sentences',
              },
            ),
          ]),
          div(classes: 'qs-send', [
            if (whatsapp.isNotEmpty)
              a(
                classes: 'qs-btn qs-wa',
                href: productQuestionWhatsAppHref(page),
                attributes: {
                  'rel': 'noopener',
                  'target': '_blank',
                  'data-question-wa': '',
                  ..._item(page),
                },
                [
                  RawText(_whatsAppGlyph),
                  .text(PublicProductQuestion.sendWhatsApp),
                ],
              ),
            button(
              classes: 'qs-btn qs-chat',
              attributes: {'type': 'button', 'data-question-chat': ''},
              [
                RawText(materialIcon(mdChat, size: 18)),
                span(
                  attributes: {'data-question-chat-label': ''},
                  [.text(PublicProductQuestion.sendChat)],
                ),
              ],
            ),
          ]),
          p(
            classes: 'qs-note',
            attributes: {'data-question-note': ''},
            [.text(PublicProductQuestion.chatSignInNote)],
          ),
          p(
            classes: 'qs-status',
            attributes: {'role': 'status', 'data-question-status': ''},
            [],
          ),
        ],
      ),
    ],
  );
}

/// WhatsApp with the product and no question yet: the box's link without
/// JavaScript, and the sheet's until the visitor writes.
String productQuestionWhatsAppHref(ProductPageModel page) =>
    'https://wa.me/${page.shell.whatsappDigits}'
    '?text=${Uri.encodeComponent(_baseMessage(page))}';

String _baseMessage(ProductPageModel page) => PublicProductQuestion.message(
  title: page.commerce.title,
  sku: page.commerce.sku,
  price: _price(page),
  url: page.productUrl,
);

String _price(ProductPageModel page) => page.commerce.price > 0
    ? catalogPriceLabel(page.commerce.price, mode: page.priceMode)
    : '';

/// What the store's measurement adds to the `contact` it sends for a
/// WhatsApp link: the product asked about.
Map<String, String> _item(ProductPageModel page) => {
  'data-item-id': page.commerce.sku.isNotEmpty
      ? page.commerce.sku
      : page.commerce.id,
  'data-item-name': page.commerce.title,
};

/// WhatsApp's glyph (Simple Icons, CC0), in its green.
const _whatsAppGlyph =
    '<svg class="wa" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="#25D366" d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413Z"/></svg>';

/// The box under the buy button and its sheet. The site's colors come from
/// the editor's theme (`--primary`, `--ink`, `--c-line`).
const productQuestionCss = '''
.qbox{margin-top:22px;padding:16px 18px 18px;border:1px solid var(--c-line);border-radius:10px;background:var(--c-soft)}
.qbox-head{display:flex;align-items:flex-start;gap:12px}
.qbox-head>svg{flex:none;margin-top:1px;color:var(--primary)}
.qbox-title{margin:0;font:700 14.5px/1.35 var(--body);color:var(--ink)}
.qbox-lead{margin:3px 0 0;font-size:13px;line-height:1.45;color:var(--c-2nd)}
.qbox-ch{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:14px}
.qbox-ch.one{grid-template-columns:1fr}
.qbox-ch a{display:flex;align-items:center;justify-content:center;gap:8px;min-height:46px;padding:0 12px;border:1px solid var(--c-line);border-radius:6px;background:#fff;color:var(--ink);font:700 14px var(--body);text-decoration:none;transition:border-color .15s,background .15s}
.qbox-ch a:hover{border-color:var(--primary);background:color-mix(in srgb,var(--primary) 4%,#fff)}
.qbox-ch a:focus-visible,.qs-btn:focus-visible,.qs-chip:focus-visible,.qs-x:focus-visible{outline:2px solid var(--primary);outline-offset:2px}
.qbox-ch .q-chat svg{color:var(--primary)}
/* Out of stock, asking is the page's next step. */
.qbox.lead{border-color:color-mix(in srgb,var(--primary) 35%,var(--c-line));background:color-mix(in srgb,var(--primary) 5%,#fff)}
.qs{width:min(520px,calc(100% - 24px));max-height:calc(100% - 24px);margin:auto;padding:0;border:0;border-radius:14px;background:#fff;color:var(--ink);box-shadow:0 28px 70px -24px rgb(15 23 42 / .45)}
.qs::backdrop{background:rgb(15 23 42 / .45)}
.qs[open]{animation:qs-in .18s ease-out}
@keyframes qs-in{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}
.qs-in{display:flex;flex-direction:column;gap:16px;padding:20px 22px 22px}
.qs-head{display:flex;align-items:center;justify-content:space-between;gap:12px}
.qs-head h2{margin:0;font:700 17px/1.3 var(--body);color:var(--ink)}
.qs-x{display:grid;place-items:center;width:40px;height:40px;margin:-8px -10px -8px 0;border:0;border-radius:50%;background:none;color:var(--c-2nd);cursor:pointer}
.qs-x:hover{background:rgba(0,0,0,.05)}
.qs-product{display:flex;align-items:center;gap:14px;padding:10px;border:1px solid var(--c-line);border-radius:10px}
.qs-thumb{flex:none;display:grid;place-items:center;width:56px;height:56px;overflow:hidden;border-radius:6px;background:var(--c-soft);color:var(--c-muted)}
.qs-thumb img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply}
.qs-product div{min-width:0}
.qs-name{margin:0;font:700 14px/1.35 var(--body);color:var(--ink);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.qs-meta{margin:3px 0 0;font-size:12.5px;line-height:1.4;color:var(--c-2nd);font-variant-numeric:tabular-nums}
.qs-sugs{margin:0;padding:0;border:0;min-width:0}
.qs-sugs legend{margin:0 0 8px;padding:0;font:700 13px/1.4 var(--body);color:var(--ink)}
.qs-chips{display:flex;flex-wrap:wrap;gap:8px}
.qs-chip{min-height:38px;padding:7px 14px;border:1px solid var(--c-line);border-radius:999px;background:#fff;color:var(--ink);font:500 13.5px/1.3 var(--body);text-align:left;cursor:pointer;transition:border-color .15s,background .15s}
.qs-chip:hover{border-color:var(--primary)}
.qs-chip[aria-pressed=true]{border-color:var(--primary);background:color-mix(in srgb,var(--primary) 9%,#fff);color:var(--primary);font-weight:700}
.qs-field{display:block}
.qs-field textarea{display:block;width:100%;min-height:88px;padding:12px 14px;border:1px solid var(--c-line);border-radius:8px;background:#fff;color:var(--ink);font:15px/1.5 var(--body);resize:vertical}
.qs-field textarea:focus{outline:none;border-color:var(--primary);box-shadow:0 0 0 3px color-mix(in srgb,var(--primary) 18%,transparent)}
.qs-field textarea::placeholder{color:var(--c-muted)}
.qs-send{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.qs-send:has(>:only-child){grid-template-columns:1fr}
.qs-btn{display:flex;align-items:center;justify-content:center;gap:8px;min-height:50px;padding:0 14px;border:1px solid var(--c-line);border-radius:6px;background:#fff;color:var(--ink);font:700 14.5px var(--body);text-decoration:none;cursor:pointer}
.qs-btn:hover{border-color:var(--primary)}
.qs-chat svg{color:var(--primary)}
/* The channel the visitor picked in the box is the sheet's main button. */
.qs[data-via=whatsapp] .qs-wa,.qs[data-via=chat] .qs-chat{border-color:var(--primary);background:var(--primary);color:#fff}
.qs[data-via=chat] .qs-chat svg{color:#fff}
.qs[data-via=whatsapp] .qs-wa .wa path{fill:#fff}
.qs-btn[aria-busy=true]{opacity:.7;cursor:progress}
.qs-note{margin:-4px 0 0;font-size:12.5px;line-height:1.45;color:var(--c-2nd)}
.qs-status{margin:-6px 0 0;font-size:13px;line-height:1.45;color:var(--c-2nd)}
.qs-status:empty{display:none}
.qs-status[data-state=error]{color:var(--bad)}
@media (max-width:560px){
.qs{width:100%;max-width:none;max-height:92%;margin:auto 0 0;border-radius:16px 16px 0 0}
.qs[open]{animation:qs-up .22s ease-out}
.qs-in{padding:18px 16px calc(18px + env(safe-area-inset-bottom,0px))}
.qs-send{grid-template-columns:1fr}
}
@keyframes qs-up{from{transform:translateY(24px);opacity:.4}to{transform:none;opacity:1}}
@media (prefers-reduced-motion:reduce){.qs[open]{animation:none}}
''';

/// The sheet's behavior: open from the box or the help card with the channel
/// picked, tap questions, keep WhatsApp's link with the words, and send by
/// the chat as the customer (`/cuenta/accion`, `chat-new` with the product).
/// A visitor without a session enters first; the question waits in this
/// tab (`vb-question`) and goes out when the page comes back
/// (`vb-after-login`, read by the login page).
const productQuestionScript = r'''
(function () {
  var sheet = document.querySelector('[data-question]');
  if (!sheet || !sheet.showModal) return;
  var d = sheet.dataset, form = sheet.querySelector('form'), field = sheet.querySelector('textarea');
  var wa = sheet.querySelector('[data-question-wa]'), chat = sheet.querySelector('[data-question-chat]');
  var chatLabel = sheet.querySelector('[data-question-chat-label]'), note = sheet.querySelector('[data-question-note]');
  var status = sheet.querySelector('[data-question-status]');
  var maxLength = Number(d.max || 8000);
  var prefix = location.pathname.indexOf('/_html/') === 0 ? '/_html' : '';
  var PENDING = 'vb-question', AFTER = 'vb-after-login';
  var sending = false;
  // On a phone the keyboard would cover the questions to tap: the field
  // takes the focus only where typing does not raise one.
  var touch = window.matchMedia && matchMedia('(pointer: coarse)').matches;
  function focusField() { if (!touch) field.focus(); }

  function track(name, params) { var m = window.vinabikeMeasure; if (m && m.track) m.track(name, params); }
  // PublicProductQuestion.message: the product, then the question.
  function message() {
    var asked = field.value.trim();
    return d.base + (asked ? '\n\n' + asked : '');
  }
  // The questions tapped are the field's words: a chip is pressed while
  // its question is written there.
  function chips() {
    var text = field.value;
    sheet.querySelectorAll('[data-sug]').forEach(function (c) { c.setAttribute('aria-pressed', text.indexOf(c.dataset.sug) >= 0 ? 'true' : 'false'); });
    if (wa) wa.href = 'https://wa.me/' + d.wa + '?text=' + encodeURIComponent(message());
  }
  function toggle(sug) {
    var text = field.value, at = text.indexOf(sug);
    if (at >= 0) text = (text.slice(0, at) + text.slice(at + sug.length)).replace(/\s{2,}/g, ' ').trim();
    else text = (text.trim() ? text.trim() + ' ' : '') + sug;
    field.value = text;
    chips();
  }
  function say(text, error) {
    status.textContent = text || '';
    if (error) status.dataset.state = 'error'; else delete status.dataset.state;
  }
  function busy(on) {
    sending = on;
    chat.setAttribute('aria-busy', on ? 'true' : 'false');
    chatLabel.textContent = on ? d.sending : d.send;
  }
  function open(via, opener) {
    if (via) sheet.dataset.via = via; else delete sheet.dataset.via;
    say('');
    paintNote();
    chips();
    if (!sheet.open) sheet.showModal();
    if (opener && opener.dataset.questionSug && field.value.indexOf(opener.dataset.questionSug) < 0) toggle(opener.dataset.questionSug);
    setTimeout(focusField, 30);
  }
  // The note on entering only for a visitor who has to.
  function paintNote() {
    var s = window.vinabikeSession;
    note.hidden = !!(s && s.read && s.read());
  }
  function key() {
    var bytes = new Uint8Array(12);
    (window.crypto || window.msCrypto).getRandomValues(bytes);
    return Array.prototype.map.call(bytes, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }
  function post(token, values) {
    return fetch(prefix + d.action, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: 'Bearer ' + token },
      body: JSON.stringify({ path: '/cuenta/chats', query: '', action: 'chat-new', values: values })
    }).then(function (r) { return r.ok ? r.json() : null; });
  }
  function signIn(values) {
    try {
      sessionStorage.setItem(PENDING, JSON.stringify({ product: d.productId, message: values.message, key: values.key, question: field.value, at: Date.now() }));
      sessionStorage.setItem(AFTER, location.pathname + location.search);
    } catch (e) { /* the question is lost; the visitor writes it again */ }
    location.assign(prefix + '/cuenta/login');
  }
  // [returning]: back from entering, the question goes out once; without a
  // customer session still, the sheet says so instead of leaving again.
  function send(values, returning) {
    var s = window.vinabikeSession;
    if (!s || !s.profile) { say(d.failed, true); return; }
    busy(true);
    say(d.sending);
    var attempt = function (renewed) {
      return (renewed ? s.renew() : s.current()).then(function (session) {
        if (!session) return { state: 'signin' };
        return post(session.access_token, values).then(function (answer) {
          if (answer && answer.state === 'expired' && !renewed) return attempt(true);
          if (answer && answer.state === 'expired') return { state: 'signin' };
          return answer;
        });
      });
    };
    s.profile().then(function (account) {
      if (!account) return { state: 'signin' };
      return attempt(false);
    }).then(function (answer) {
      if (answer && answer.state === 'signin') {
        busy(false);
        if (returning) { forget(); say(d.signin, true); return; }
        say('');
        signIn(values);
        return;
      }
      if (answer && answer.conversation) {
        forget();
        track('contact', { method: 'chat', item_id: d.itemId, item_name: d.itemName });
        location.assign(prefix + '/cuenta/chats/' + answer.conversation);
        return;
      }
      busy(false);
      if (returning) forget();
      say((answer && answer.toast) || d.failed, true);
    }, function () { busy(false); if (returning) forget(); say(d.failed, true); });
  }
  function forget() { try { sessionStorage.removeItem(PENDING); } catch (e) { /* nothing kept */ } }
  function sendChat() {
    if (sending) return;
    var text = message();
    if (text.length > maxLength) text = text.slice(0, maxLength);
    send({ message: text, key: key(), product: d.productId }, false);
  }

  document.addEventListener('click', function (e) {
    var t = e.target.closest && e.target.closest('[data-question-open]');
    if (!t) return;
    e.preventDefault();
    open(t.dataset.questionOpen, t);
  });
  sheet.addEventListener('click', function (e) {
    if (e.target === sheet) { sheet.close(); return; }
    var sug = e.target.closest('[data-sug]');
    if (sug) { toggle(sug.dataset.sug); focusField(); return; }
    if (e.target.closest('[data-question-chat]')) { e.preventDefault(); sendChat(); }
  });
  field.addEventListener('input', chips);
  form.addEventListener('submit', function (e) { if (e.submitter && e.submitter.value === 'close') return; e.preventDefault(); });

  // Back from entering: the question this tab kept for this product goes out.
  var kept = null;
  try { kept = JSON.parse(sessionStorage.getItem(PENDING) || 'null'); } catch (e) { kept = null; }
  if (kept && kept.product === d.productId && Date.now() - (kept.at || 0) < 30 * 60e3) {
    var s = window.vinabikeSession;
    if (s && s.read && s.read()) {
      field.value = kept.question || '';
      open('chat', null);
      send({ message: kept.message, key: kept.key, product: d.productId }, true);
    } else forget();
  }
})();
''';
