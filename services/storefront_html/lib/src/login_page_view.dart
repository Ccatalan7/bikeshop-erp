import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/customer_auth_forms.dart';

import 'login_page_css.dart';
import 'login_page_script.dart';
import 'material_icons.dart';
import 'portal_page_view.dart';
import 'site_layout.dart';

/// `/cuenta/login` (4c) as Flutter's `CustomerAuthPage` draws it in its two
/// plain modes, entering and creating an account: the card with the intro
/// beside the form (one above the other under 900 px), the notices, the
/// «¿Olvidaste tu contraseña?» dialog and the bars. The words and rules are
/// `customer_auth_forms.dart`'s.
///
/// The browser talks to Supabase Auth itself, as the Flutter store does (it
/// counts attempts by address), and keeps the session where
/// `supabase_flutter` keeps it; the server checks the fields first and,
/// once there is a session, makes it the store's customer
/// ([portalActionPath], `check` and `enter`). The page redeems a PKCE `code`
/// itself (Google's return to `/auth/callback`, an account's confirmation);
/// a link that sets a password (a recovery, an invitation: a token, a
/// `type`) is Flutter's ([loginAnsweredByFlutter]), and one that carries it
/// in the fragment, which never reaches the server, is sent back with
/// `?enlace=1` before the page paints.
Component loginPageDocument(PageContext page) {
  final prefix = page.hidden ? '/_html' : '';
  return sitePage(
    context: page,
    meta: loginPageMeta(page),
    content: [
      if (!page.hidden)
        // Before anything paints: a link that carries its token in the
        // fragment goes back to the server, which then answers Flutter.
        script(content: _fragmentHandoff),
      div(
        classes: 'lg',
        attributes: {
          'data-login': '',
          'data-mode': 'login',
          'data-action-url': '$prefix$portalActionPath',
        },
        [
          div(classes: 'lg-card', [_intro(), _form()]),
          _resetDialog(),
          Component.element(
            tag: 'noscript',
            children: [
              p(classes: 'lg-noscript', [
                .text(
                  'Tu sesión se guarda en este navegador: activa '
                  'JavaScript para entrar a tu cuenta.',
                ),
              ]),
            ],
          ),
        ],
      ),
    ],
    pageScripts: [script(content: loginPageScript())],
  );
}

/// The login's head: never indexed, the same for every visitor.
PageMeta loginPageMeta(PageContext page) {
  final shell = page.shell;
  return PageMeta(
    title: 'Iniciar sesión | ${shell.storeName}',
    description:
        'Entra a tu cuenta de ${shell.storeName} para ver tus pedidos, tus '
        'bicicletas y tus datos.',
    canonicalUrl: '${page.storeUrl}/cuenta/login',
    indexable: false,
    styles: loginPageCss(WebsiteThemeRoles.resolve(shell.setting)),
  );
}

/// What in the address makes the login Flutter's: a link back from Supabase
/// Auth that sets a password (a recovery or an invitation: a `token_hash`, a
/// `type`, tokens), an `error` from an e-mail's link, or `enlace`, which the
/// page adds when only the browser can tell (the token in the fragment, a
/// recovery's verifier, the editor's own Google intent). A bare PKCE `code`
/// is redeemed by the page, and on [callback] (`/auth/callback`) also
/// Google's refusal (until 2026-10-08 every one of them loaded Flutter).
bool loginAnsweredByFlutter(
  Iterable<String> queryKeys, {
  bool callback = false,
}) => queryKeys.any(
  {
    'token_hash',
    'type',
    'access_token',
    'refresh_token',
    'enlace',
    if (!callback) ...['error', 'error_code', 'error_description'],
  }.contains,
);

/// The fragment's keys that `CustomerAccountService.captureInitialUrl` and
/// `supabase_flutter` read, checked before the page paints.
final _fragmentHandoff =
    '(function(){var h=location.hash;if(!h||h.length<2)return;'
    'var k=new URLSearchParams(h.slice(1));'
    'if(!${jsonEncode(const ['access_token', 'token_hash', 'error', 'error_code', 'refresh_token', 'type'])}'
    '.some(function(n){return k.has(n)}))return;'
    'window.vinabikeAuthHandoff=true;'
    'var q=new URLSearchParams(location.search);q.set("enlace","1");'
    'location.replace(location.pathname+"?"+q.toString()+h)})();';

// ================================================================== the intro

Component _intro() => section(classes: 'lg-intro', [
  p(classes: 'lg-eyebrow', [_x(customerAuthEyebrow)]),
  h1(classes: 'lg-headline', [
    for (final mode in _modes)
      span(
        attributes: {'data-only': mode.name},
        [.text(customerAuthHeadline(mode))],
      ),
  ]),
  p(classes: 'lg-lead', [
    for (final mode in _modes)
      span(
        attributes: {'data-only': mode.name},
        [.text(customerAuthLead(mode))],
      ),
  ]),
  ul(classes: 'lg-benefits', [
    for (final (icon, title, subtitle) in customerAuthBenefits)
      li([
        span(classes: 'lg-bicon', [
          RawText(
            materialIcon(_benefitIcons[icon] ?? mdCheckCircleOutline, size: 20),
          ),
        ]),
        div([
          strong([.text(title)]),
          span([.text(subtitle)]),
        ]),
      ]),
  ]),
  // return-contract: explicit-destination, as Flutter's (a labelled link to
  // the home, not a way back).
  a(href: '/', classes: 'lg-back', [
    RawText(materialIcon(mdArrowBack, size: 18)),
    span([.text(customerAuthBackHome)]),
  ]),
]);

const _modes = [CustomerAuthMode.login, CustomerAuthMode.register];

const _benefitIcons = {
  'shopping_bag': mdShoppingBagOutlined,
  'pedal_bike': mdPedalBikeOutlined,
  'support_agent': mdSupportAgentOutlined,
};

// =================================================================== the form

Component _form() => section(classes: 'lg-form', [
  h2(classes: 'lg-title', [
    for (final mode in _modes)
      span(
        attributes: {'data-only': mode.name},
        [.text(customerAuthFormTitle(mode))],
      ),
  ]),
  p(classes: 'lg-sub', [
    for (final mode in _modes)
      span(
        attributes: {'data-only': mode.name},
        [.text(customerAuthFormLead(mode))],
      ),
  ]),
  // `?confirmed=true`: the e-mail's link confirmed the account.
  div(
    classes: 'lg-note ok',
    attributes: {'data-confirmed': '', 'hidden': ''},
    [
      RawText(materialIcon(mdCheckCircleOutline)),
      p([.text(customerAuthConfirmedNotice)]),
    ],
  ),
  // After creating the account: where the confirmation went.
  div(
    classes: 'lg-note',
    attributes: {'data-verify': '', 'hidden': ''},
    [
      strong([.text(customerAuthVerifyTitle)]),
      p(
        attributes: {
          'data-verify-body': '',
          'data-template': customerAuthVerifyBody('{email}'),
        },
        const [],
      ),
      button(
        classes: 'lg-resend',
        attributes: {'type': 'button', 'data-resend': ''},
        [
          RawText(materialIcon(mdMarkEmailUnreadOutlined, size: 18)),
          span([.text(customerAuthResend)]),
        ],
      ),
    ],
  ),
  Component.element(
    tag: 'form',
    classes: 'lg-fields',
    // POST: the store's script leaves out a GET form's empty fields.
    attributes: {'data-login-form': '', 'method': 'post', 'novalidate': ''},
    children: [
      _field(
        'name',
        customerAuthNameLabel,
        hint: customerAuthNameHint,
        icon: mdPersonOutline,
        autocomplete: 'name',
        only: 'register',
      ),
      _field(
        'email',
        customerAuthEmailLabel,
        hint: customerAuthEmailHint,
        icon: mdEmailOutlined,
        type: 'email',
        autocomplete: 'email',
      ),
      _field(
        'phone',
        customerAuthPhoneLabel,
        hint: customerAuthPhoneHint,
        icon: mdPhoneOutlined,
        type: 'tel',
        autocomplete: 'tel',
        only: 'register',
      ),
      _field(
        'password',
        customerAuthPasswordLabel,
        hints: {
          for (final mode in _modes) mode.name: customerAuthPasswordHint(mode),
        },
        icon: mdLockOutline,
        type: 'password',
        autocomplete: 'current-password',
        reveal: true,
      ),
      button(
        classes: 'lg-submit',
        attributes: {'type': 'submit'},
        [
          span(
            classes: 'lg-spin',
            attributes: {'hidden': ''},
            [RawText(_spinner)],
          ),
          for (final mode in _modes)
            span(
              attributes: {'data-only': mode.name},
              [.text(customerAuthSubmit(mode))],
            ),
        ],
      ),
    ],
  ),
  div(classes: 'lg-or', [
    span([.text(customerAuthOr)]),
  ]),
  button(
    classes: 'lg-google',
    attributes: {'type': 'button', 'data-google': ''},
    [
      RawText(_googleGlyph),
      for (final mode in _modes)
        span(
          attributes: {'data-only': mode.name},
          [.text(customerAuthGoogle(mode))],
        ),
    ],
  ),
  p(classes: 'lg-switch', [
    for (final mode in _modes) ...[
      span(
        attributes: {'data-only': mode.name},
        [.text(customerAuthSwitchQuestion(mode))],
      ),
      button(
        attributes: {
          'type': 'button',
          'data-only': mode.name,
          'data-switch': '',
        },
        [.text(customerAuthSwitchAction(mode))],
      ),
    ],
  ]),
  button(
    classes: 'lg-forgot',
    attributes: {'type': 'button', 'data-only': 'login', 'data-forgot': ''},
    [.text(customerAuthForgot)],
  ),
]);

/// A field as the login draws it: its label above, the hint inside, the
/// icon at the start, and the message under it when it does not pass.
/// [hints] is the hint by mode when it changes with it.
Component _field(
  String name,
  String label, {
  String? hint,
  Map<String, String>? hints,
  required String icon,
  String type = 'text',
  String? autocomplete,
  String? only,
  bool reveal = false,
}) {
  final id = 'lg-f-$name';
  return div(
    classes: 'lg-field',
    attributes: {'data-field': name, 'data-only': ?only},
    [
      Component.element(
        tag: 'label',
        attributes: {'for': id},
        children: [.text(label)],
      ),
      div(classes: 'lg-box', [
        RawText(materialIcon(icon, classes: 'lg-ic')),
        input(
          attributes: {
            'id': id,
            'name': name,
            'type': type,
            'placeholder': hint ?? hints?.values.first ?? '',
            'data-hints': ?(hints == null ? null : jsonEncode(hints)),
            'autocomplete': ?autocomplete,
            if (type == 'email') 'autocapitalize': 'none',
            'spellcheck': 'false',
            'aria-describedby': '$id-m',
          },
        ),
        if (reveal)
          button(
            classes: 'lg-eye',
            attributes: {
              'type': 'button',
              'data-reveal': '',
              'aria-label': 'Mostrar contraseña',
              'aria-pressed': 'false',
            },
            [
              RawText(materialIcon(mdVisibilityOutlined, classes: 'show')),
              RawText(materialIcon(mdVisibilityOffOutlined, classes: 'hide')),
            ],
          ),
      ]),
      p(classes: 'lg-msg', attributes: {'id': '$id-m'}, const []),
    ],
  );
}

/// «¿Olvidaste tu contraseña?»: Flutter's `AlertDialog` with the e-mail
/// typed so far.
Component _resetDialog() => Component.element(
  tag: 'dialog',
  id: 'lg-reset',
  classes: 'lg-dlg',
  attributes: {'aria-labelledby': 'lg-reset-t', 'tabindex': '-1'},
  children: [
    div(classes: 'lg-scrim', attributes: {'data-close': ''}, const []),
    Component.element(
      tag: 'form',
      classes: 'lg-alert',
      attributes: {'data-reset-form': '', 'method': 'post', 'novalidate': ''},
      children: [
        h2(attributes: {'id': 'lg-reset-t'}, [.text(customerResetTitle)]),
        p([.text(customerResetBody)]),
        div(
          classes: 'lg-ff',
          attributes: {'data-field': 'email'},
          [
            RawText(materialIcon(mdEmailOutlined, classes: 'lg-ic')),
            input(
              attributes: {
                'id': 'lg-r-email',
                'name': 'email',
                'type': 'email',
                'placeholder': ' ',
                'autocomplete': 'email',
                'autocapitalize': 'none',
                'spellcheck': 'false',
                'aria-describedby': 'lg-r-email-m',
              },
            ),
            Component.element(
              tag: 'label',
              attributes: {'for': 'lg-r-email'},
              children: [.text(customerAuthEmailLabel)],
            ),
            Component.element(
              tag: 'fieldset',
              attributes: {'aria-hidden': 'true'},
              children: [
                Component.element(
                  tag: 'legend',
                  children: [
                    span([.text(customerAuthEmailLabel)]),
                  ],
                ),
              ],
            ),
            p(classes: 'lg-msg', attributes: {'id': 'lg-r-email-m'}, const []),
          ],
        ),
        div(classes: 'lg-actions', [
          button(
            classes: 'lg-text',
            attributes: {'type': 'button', 'data-close': ''},
            [.text(customerResetCancel)],
          ),
          button(
            classes: 'lg-fill',
            attributes: {'type': 'submit'},
            [.text(customerResetSend)],
          ),
        ]),
      ],
    ),
  ],
);

/// A letter-spaced text, moved right by half its spacing as SkParagraph
/// draws it.
Component _x(String text) => span(classes: 'lg-x', [.text(text)]);

const _spinner =
    '<svg viewBox="0 0 18 18" width="18" height="18" aria-hidden="true">'
    '<circle cx="9" cy="9" r="8" fill="none" stroke="currentColor" '
    'stroke-width="2"/></svg>';

/// Font Awesome Free's `google` brand glyph (CC BY 4.0), the one
/// `font_awesome_flutter` 10.9 draws: its outline on the font's own box
/// (512 units a size, 534 from ascent to descent).
const _googleGlyph =
    '<svg class="lg-g" viewBox="0 0 488 534" width="15.25" height="16.6875" '
    'fill="currentColor" aria-hidden="true"><path d="M488 274Q486 382 422 '
    '448Q357 514 248 516Q179 515 123 482Q67 449 34 393Q1 337 0 268Q1 199 34 '
    '143Q67 87 123 54Q179 21 248 20Q349 22 414 85L347 150Q300 108 242 112Q184 '
    '115 140 156Q97 198 94 268Q96 335 139 379Q183 423 248 425Q297 424 327 '
    '405Q357 386 372 362Q386 337 389 318L248 318L248 232L484 232Q488 250 488 '
    '274Z"/></svg>';
