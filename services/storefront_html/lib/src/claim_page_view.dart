import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/customer_claim_words.dart';

import 'claim_page_script.dart';
import 'login_page_css.dart';
import 'login_page_view.dart';
import 'material_icons.dart';
import 'portal_page_view.dart';
import 'site_layout.dart';

/// `/cuenta/vincular#c=<código>`: donde lleva el QR de la recepción y del
/// comprobante de entrega (2026-11-04). Es la creación de cuenta de la tienda
/// con un saludo: el código del QR dice quién es («Hola, Dora · Trek Marlin
/// 7»), el cliente pone su teléfono y entra con Google o con su correo, y la
/// cuenta queda ligada a su ficha del taller
/// (`claim_customer_portal_code_v1`). El código prueba que es el cliente:
/// por eso no hace falta otro código por teléfono.
///
/// El código viaja en el fragmento y sale de la dirección antes de pintar: no
/// llega a ningún servidor ni a Analytics. Se guarda en esta pestaña
/// (`vb-claim`) para la vuelta de Google, y en la cuenta que se crea con
/// correo (`vinabike_claim_code`) para el enlace de confirmación, que puede
/// abrirse en otro navegador: la tienda lo liga al entrar.
///
/// Se ve como el login (sus clases y su hoja de estilos): el mismo lugar de
/// la tienda con otras palabras.
Component claimPageDocument(PageContext page) {
  final prefix = page.hidden ? '/_html' : '';
  return sitePage(
    context: page,
    meta: claimPageMeta(page),
    content: [
      // Antes de pintar: el código sale de la dirección.
      script(content: _fragmentCapture),
      div(
        classes: 'lg cl',
        attributes: {
          'data-claim': '',
          'data-mode': 'register',
          'data-state': 'checking',
          'data-action-url': '$prefix$portalActionPath',
          'data-words': jsonEncode(claimPageWords),
        },
        [
          div(classes: 'lg-card', [_intro(), _form()]),
          Component.element(
            tag: 'noscript',
            children: [
              p(classes: 'lg-noscript', [
                .text(
                  'Activa JavaScript en este navegador para crear tu cuenta.',
                ),
              ]),
            ],
          ),
        ],
      ),
    ],
    pageScripts: [script(content: claimPageScript)],
  );
}

/// La cabeza de la página: nunca se indexa.
PageMeta claimPageMeta(PageContext page) {
  final shell = page.shell;
  return PageMeta(
    title: 'Crea tu cuenta | ${shell.storeName}',
    description: customerClaimLead,
    canonicalUrl: '${page.storeUrl}/cuenta/vincular',
    indexable: false,
    styles: loginPageCss(WebsiteThemeRoles.resolve(shell.setting)) + _claimCss,
  );
}

/// Las palabras que el guion escribe según lo que responda la tienda.
final claimPageWords = <String, Object?>{
  'checking': customerClaimChecking,
  'linking': customerClaimLinking,
  'done': customerClaimDone,
  'phoneMissing': customerClaimPhoneMissing,
  'verifyTitle': customerClaimVerifyTitle,
  'verifyBody': customerClaimVerifyBody('{email}'),
  'session': customerClaimSessionLine('{email}'),
  'greeting': customerClaimGreeting(null),
  'greetingNamed': customerClaimGreeting('{name}'),
  'problems': {
    for (final status in const [
      'invalid',
      'expired',
      'linked',
      'phone_mismatch',
      'linked_elsewhere',
      'account_has_history',
      'email_in_other_record',
      'too_many_attempts',
      'unavailable',
    ])
      status: customerClaimProblem(status),
  },
  'retryable': [
    for (final status in const ['phone_mismatch', 'unavailable'])
      if (customerClaimProblemIsRetryable(status)) status,
  ],
};

/// Antes de pintar: `#c=<código>` pasa a esta pestaña y sale de la dirección.
const _fragmentCapture =
    '(function(){var h=location.hash;if(!h||h.length<3)return;'
    'var k=new URLSearchParams(h.slice(1)),c=k.get("c");if(!c)return;'
    'try{var o=JSON.parse(sessionStorage.getItem("vb-claim")||"{}");'
    'if(o.code!==c){o={code:c}}sessionStorage.setItem("vb-claim",JSON.stringify(o))}catch(e){}'
    'window.vinabikeClaimCode=c;'
    'history.replaceState(history.state,"",location.pathname+location.search)})();';

const _benefitIcons = {
  'pedal_bike': mdPedalBikeOutlined,
  'fact_check': mdReceiptLongOutlined,
  'verified': mdVerifiedUserOutlined,
};

Component _intro() => section(classes: 'lg-intro', [
  p(classes: 'lg-eyebrow', [.text(customerClaimEyebrow)]),
  h1(
    classes: 'lg-headline',
    attributes: {'data-greeting': ''},
    [.text(customerClaimGreeting(null))],
  ),
  p(classes: 'lg-lead cl-subject', attributes: {'data-subject': ''}, const []),
  p(classes: 'lg-lead', [.text(customerClaimLead)]),
  ul(classes: 'lg-benefits cl-benefits', [
    for (final (icon, title) in customerClaimBenefits)
      li([
        span(classes: 'lg-bicon', [
          RawText(
            materialIcon(_benefitIcons[icon] ?? mdCheckCircleOutline, size: 20),
          ),
        ]),
        div([
          strong([.text(title)]),
        ]),
      ]),
  ]),
]);

Component _form() => section(classes: 'lg-form', [
  // Mientras se revisa el código y mientras se liga.
  div(
    classes: 'lg-wait cl-wait',
    attributes: {'data-panel': 'wait', 'role': 'status'},
    [
      span(classes: 'lg-spin', [RawText(loginSpinner)]),
      p(attributes: {'data-wait-text': ''}, [.text(customerClaimChecking)]),
    ],
  ),
  // Un código que no sirve: qué hacer, y entrar si ya tiene cuenta.
  div(
    classes: 'lg-bad cl-bad',
    attributes: {'data-panel': 'problem', 'role': 'alert', 'hidden': ''},
    [
      RawText(materialIcon(mdInfoOutline, size: 40)),
      p(attributes: {'data-problem-text': ''}, const []),
      a(href: '/cuenta/login', classes: 'lg-submit cl-link', [
        span([.text(customerClaimSignIn.toUpperCase())]),
      ]),
    ],
  ),
  // Ligada: a su cuenta.
  div(
    classes: 'lg-wait cl-done',
    attributes: {'data-panel': 'done', 'role': 'status', 'hidden': ''},
    [
      RawText(materialIcon(mdCheckCircleOutline, size: 40)),
      p([.text(customerClaimDone)]),
    ],
  ),
  // Creada con correo: falta confirmarlo.
  div(
    classes: 'lg-note',
    attributes: {'data-panel': 'verify', 'hidden': ''},
    [
      strong([.text(customerClaimVerifyTitle)]),
      p(attributes: {'data-verify-text': ''}, const []),
    ],
  ),
  div(
    classes: 'cl-main',
    attributes: {'data-panel': 'form', 'hidden': ''},
    [
      h2(classes: 'lg-title', [.text(customerClaimFormTitle)]),
      p(
        classes: 'lg-sub',
        attributes: {'data-session-line': '', 'hidden': ''},
        const [],
      ),
      Component.element(
        tag: 'form',
        classes: 'lg-fields',
        attributes: {'data-claim-form': '', 'method': 'post', 'novalidate': ''},
        children: [
          _field(
            'phone',
            customerClaimPhoneLabel,
            hint: customerClaimPhoneHint,
            icon: mdPhoneOutlined,
            type: 'tel',
            autocomplete: 'tel',
          ),
          // Con sesión abierta: ligar esa cuenta.
          button(
            classes: 'lg-submit',
            attributes: {'type': 'submit', 'data-link': '', 'hidden': ''},
            [
              span(
                classes: 'lg-spin',
                attributes: {'hidden': ''},
                [RawText(loginSpinner)],
              ),
              span([.text(customerClaimLinkAccount)]),
            ],
          ),
          // Sin sesión: el camino corto primero.
          button(
            classes: 'lg-google cl-google',
            attributes: {'type': 'button', 'data-google': '', 'hidden': ''},
            [
              RawText(loginGoogleGlyph),
              span([.text(customerClaimGoogle)]),
            ],
          ),
          div(
            classes: 'lg-or',
            attributes: {'data-or': '', 'hidden': ''},
            [
              span([.text(customerClaimOr)]),
            ],
          ),
          button(
            classes: 'cl-toggle',
            attributes: {
              'type': 'button',
              'data-email-toggle': '',
              'aria-expanded': 'false',
              'hidden': '',
            },
            [
              RawText(materialIcon(mdEmailOutlined, size: 18)),
              span([.text(customerClaimEmailToggle)]),
            ],
          ),
          div(
            classes: 'cl-email',
            attributes: {'data-email-fields': '', 'hidden': ''},
            [
              _field(
                'email',
                customerClaimEmailLabel,
                hint: customerClaimEmailHint,
                icon: mdEmailOutlined,
                type: 'email',
                autocomplete: 'email',
              ),
              _field(
                'password',
                customerClaimPasswordLabel,
                hint: customerClaimPasswordHint,
                icon: mdLockOutline,
                type: 'password',
                autocomplete: 'new-password',
              ),
              button(
                classes: 'lg-submit',
                attributes: {'type': 'submit', 'data-create': ''},
                [
                  span(
                    classes: 'lg-spin',
                    attributes: {'hidden': ''},
                    [RawText(loginSpinner)],
                  ),
                  span([.text(customerClaimCreate)]),
                ],
              ),
            ],
          ),
        ],
      ),
      p(
        classes: 'lg-switch',
        attributes: {'data-have-account': '', 'hidden': ''},
        [
          span([.text(customerClaimHaveAccount)]),
          a(
            href: '/cuenta/login',
            attributes: {'data-sign-in': ''},
            [.text(customerClaimSignIn)],
          ),
        ],
      ),
    ],
  ),
]);

/// Un campo como los del login: la etiqueta arriba, la pista adentro, el
/// ícono al inicio y el mensaje debajo cuando no pasa.
Component _field(
  String name,
  String label, {
  String? hint,
  required String icon,
  String type = 'text',
  String? autocomplete,
}) {
  final id = 'cl-f-$name';
  return div(
    classes: 'lg-field',
    attributes: {'data-field': name},
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
            'placeholder': hint ?? '',
            'autocomplete': ?autocomplete,
            if (type == 'email') 'autocapitalize': 'none',
            if (type == 'tel') 'inputmode': 'tel',
            'spellcheck': 'false',
            'aria-describedby': '$id-m',
          },
        ),
      ]),
      p(classes: 'lg-msg', attributes: {'id': '$id-m'}, const []),
    ],
  );
}

/// Lo propio de esta página sobre la hoja del login.
const _claimCss = '''
.cl .cl-subject{font-weight:600;margin-top:-4px}
.cl .cl-subject:empty{display:none}
.cl .cl-benefits strong{font-weight:600}
.cl .cl-google{width:100%;justify-content:center}
.cl .cl-toggle{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:44px;margin-top:4px;background:none;border:1px solid currentColor;border-color:color-mix(in srgb,currentColor 22%,transparent);color:inherit;font:inherit;font-weight:600;cursor:pointer}
.cl .cl-toggle:focus-visible{outline:2px solid currentColor;outline-offset:2px}
.cl .cl-email{display:grid;gap:14px;margin-top:6px}
.cl .cl-email[hidden],.cl [hidden]{display:none!important}
.cl .cl-link{display:inline-flex;align-items:center;justify-content:center;text-decoration:none;margin-top:8px}
.cl .cl-wait,.cl .cl-done,.cl .cl-bad{display:grid;justify-items:center;gap:10px;text-align:center;padding:24px 0}
''';
