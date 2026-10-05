import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'contact_page_model.dart';
import 'material_icons.dart';
import 'site_layout.dart';

/// `/contacto` laid out like Flutter's `ContactPage`.
Component contactPageDocument(ContactPageModel model) => sitePage(
  context: model.page,
  meta: model.meta,
  content: [
    if (!model.available)
      section(
        classes: 'ct-off',
        attributes: {'aria-label': 'Página de contacto no disponible'},
        [
          RawText(materialIcon(mdMarkEmailUnreadOutlined, size: 40)),
          h1([.text('Contacto no disponible')]),
          p([.text('Esta página todavía no está publicada. Vuelve pronto.')]),
        ],
      )
    else ...[
      div(classes: 'ct-hero', [
        h1([.text('Contáctanos')]),
        p([
          .text(
            'Estamos aquí para ayudarte. Escríbenos y te responderemos lo '
            'antes posible.',
          ),
        ]),
      ]),
      div(classes: 'ct-main', [
        div(classes: 'ct-in', [_form(model), _info(model)]),
      ]),
    ],
  ],
  afterFooter: [if (model.available) script(content: contactFormScript)],
);

Component _form(ContactPageModel model) {
  Component field({
    required String id,
    required String name,
    required String caption,
    required String hint,
    required String icon,
    String type = 'text',
    String? autocomplete,
    bool textarea = false,
    Map<String, String> rules = const {},
  }) {
    final attributes = {
      'id': id,
      'name': name,
      'placeholder': hint,
      'autocomplete': ?autocomplete,
      'aria-describedby': '$id-error',
      for (final MapEntry(:key, :value) in rules.entries) 'data-$key': value,
    };
    return div(classes: textarea ? 'ct-field area' : 'ct-field', [
      if (textarea)
        Component.element(
          tag: 'textarea',
          attributes: {...attributes, 'rows': '5'},
          children: const [],
        )
      else
        Component.element(
          tag: 'input',
          attributes: {...attributes, 'type': type},
        ),
      label(attributes: {'for': id}, [.text(caption)]),
      RawText(materialIcon(icon, size: 20, classes: 'ct-ico')),
      p(
        classes: 'ct-error',
        attributes: {'id': '$id-error', 'aria-live': 'polite'},
        const [],
      ),
    ]);
  }

  final sendable = model.email.isNotEmpty;
  return Component.element(
    tag: 'form',
    classes: 'ct-form',
    attributes: {
      'novalidate': '',
      // Without scripts the browser writes the email itself.
      if (sendable) ...{
        'action': 'mailto:${model.email}',
        'method': 'post',
        'enctype': 'text/plain',
        'data-mail': model.email,
      },
    },
    children: [
      h2([.text('Envíanos un mensaje')]),
      p(classes: 'ct-lead', [
        .text('Completa el formulario y nos contactaremos a la brevedad.'),
      ]),
      field(
        id: 'ct-nombre',
        name: 'Nombre',
        caption: 'Nombre completo',
        hint: 'Tu nombre',
        icon: mdPersonOutline,
        autocomplete: 'name',
        rules: {'required': 'Por favor ingresa tu nombre'},
      ),
      div(classes: 'ct-pair', [
        field(
          id: 'ct-email',
          name: 'Email',
          caption: 'Email',
          hint: 'tu@email.com',
          icon: mdEmailOutlined,
          type: 'email',
          autocomplete: 'email',
          rules: {
            'required': 'Por favor ingresa tu email',
            'email': 'Email inválido',
          },
        ),
        field(
          id: 'ct-telefono',
          name: 'Teléfono',
          caption: 'Teléfono (opcional)',
          hint: '+56 9 1234 5678',
          icon: mdPhoneOutlined,
          type: 'tel',
          autocomplete: 'tel',
        ),
      ]),
      field(
        id: 'ct-mensaje',
        name: 'Mensaje',
        caption: 'Mensaje',
        hint: '¿En qué podemos ayudarte?',
        icon: mdMessageOutlined,
        textarea: true,
        rules: {
          'required': 'Por favor ingresa tu mensaje',
          'min': 'El mensaje debe tener al menos 10 caracteres',
        },
      ),
      // With no mailbox there is nowhere to send it: disabled, as Flutter.
      button(
        classes: 'ct-send',
        attributes: {'type': 'submit', if (!sendable) 'disabled': ''},
        [.text('Enviar mensaje'), RawText(materialIcon(mdSend, size: 18))],
      ),
      p(
        classes: 'ct-toast',
        attributes: {'role': 'status', 'hidden': ''},
        [.text('Abriendo cliente de correo...')],
      ),
    ],
  );
}

Component _info(ContactPageModel model) {
  Component head(String icon, String title) => div(classes: 'ct-head', [
    span(classes: 'ct-badge', [RawText(materialIcon(icon))]),
    h2([.text(title)]),
  ]);
  Component detail(String icon, String title, Component content) =>
      div(classes: 'ct-detail', [
        RawText(materialIcon(icon, size: 20)),
        div([
          p(classes: 'ct-dt', [.text(title)]),
          content,
        ]),
      ]);
  final maps = model.mapsUrl.isEmpty
      ? null
      : a(
          classes: 'ct-maps',
          href: model.mapsUrl,
          attributes: {'target': '_blank', 'rel': 'noopener'},
          [
            RawText(materialIcon(mdMapOutlined, size: 18)),
            .text('Ver en Google Maps'),
          ],
        );
  return div(classes: 'ct-info', [
    section(classes: 'ct-card', [
      head(mdLocationOnOutlined, 'Información de Contacto'),
      if (model.address.isNotEmpty)
        detail(
          mdMapOutlined,
          'Dirección',
          p(classes: 'ct-dd', [.text(model.address)]),
        ),
      if (model.phone.isNotEmpty)
        detail(
          mdPhoneOutlined,
          'Teléfono',
          a(classes: 'ct-dd', href: 'tel:${model.phone.replaceAll(' ', '')}', [
            .text(model.phone),
          ]),
        ),
      if (model.email.isNotEmpty)
        detail(
          mdEmailOutlined,
          'Email',
          a(classes: 'ct-dd', href: 'mailto:${model.email}', [
            .text(model.email),
          ]),
        ),
    ]),
    if (model.hours.isNotEmpty || maps != null)
      section(classes: 'ct-card', [
        head(mdAccessTimeRounded, 'Horario de Atención'),
        if (model.hours.isNotEmpty) ...[
          ul(classes: 'ct-hours', [
            for (final row in model.hours)
              li(classes: row.open ? 'open' : null, [
                span([.text(row.days)]),
                span(classes: 'ct-time', [.text(row.hours)]),
              ]),
          ]),
          if (maps != null) ...[hr(classes: 'ct-rule'), maps],
        ] else ...[
          p(classes: 'ct-note', [
            .text(
              'Consulta el horario actualizado directamente en Google Maps.',
            ),
          ]),
          ?maps,
        ],
      ]),
    if (model.whatsappDigits.isNotEmpty)
      section(classes: 'ct-card ct-wa', [
        div(classes: 'ct-wa-head', [
          RawText(materialIcon(mdChatBubbleOutlineRounded)),
          h2([.text('¿Necesitas ayuda rápida?')]),
        ]),
        p([.text('Escríbenos por WhatsApp y te responderemos al instante.')]),
        a(
          href: model.whatsappHref,
          attributes: {'target': '_blank', 'rel': 'noopener'},
          [.text('Abrir WhatsApp')],
        ),
      ]),
    if (model.instagramUrl != null || model.facebookUrl != null)
      section(classes: 'ct-card ct-follow', [
        h2([.text('Síguenos')]),
        div(classes: 'ct-social', [
          if (model.instagramUrl case final url?)
            a(
              classes: 'ig',
              href: url,
              attributes: {'target': '_blank', 'rel': 'noopener'},
              [
                RawText(materialIcon(mdCameraAltOutlined, size: 20)),
                .text('Instagram'),
              ],
            ),
          if (model.facebookUrl case final url?)
            a(
              classes: 'fb',
              href: url,
              attributes: {'target': '_blank', 'rel': 'noopener'},
              [RawText(materialIcon(mdFacebook, size: 20)), .text('Facebook')],
            ),
        ]),
      ]),
  ]);
}

/// The form as Flutter checks and sends it: each field's message under it,
/// in Flutter's words, then an email to the store with the four fields and
/// «Abriendo cliente de correo...» while the form clears. The email opens
/// through a link so the page script counts it as `contact` (email).
const contactFormScript = r'''
(function(f){if(!f)return;var mail=f.dataset.mail;
function check(el){var v=el.value.trim(),d=el.dataset,m="";
if(d.required!==undefined&&!v)m=d.required;else if(d.email&&v.indexOf("@")<0)m=d.email;else if(d.min&&v.length<10)m=d.min;
var out=document.getElementById(el.id+"-error");if(out)out.textContent=m;el.toggleAttribute("aria-invalid",!!m);return !m}
f.addEventListener("submit",function(e){e.preventDefault();if(!mail)return;
var els=[].slice.call(f.querySelectorAll("input,textarea")),ok=true,first=null;
els.forEach(function(el){if(!check(el)){ok=false;first=first||el}});
if(!ok){first.focus();return}
var v=function(n){return f.elements[n].value};
var body="Nombre: "+v("Nombre")+"\nEmail: "+v("Email")+"\nTeléfono: "+v("Teléfono")+"\n\nMensaje:\n"+v("Mensaje");
var a=document.createElement("a");a.href="mailto:"+mail+"?subject="+encodeURIComponent("Contacto desde sitio web")+"&body="+encodeURIComponent(body);
a.hidden=true;document.body.appendChild(a);a.click();a.remove();
var t=f.querySelector(".ct-toast");t.hidden=false;clearTimeout(t._h);t._h=setTimeout(function(){t.hidden=true},4000);
f.reset()});
f.addEventListener("input",function(e){var el=e.target;if(el.hasAttribute("aria-invalid"))check(el)});
})(document.querySelector(".ct-form"));
''';
