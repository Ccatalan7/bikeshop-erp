part of 'portal_page_view.dart';

// The portal's writing pages (4b): «Perfil y seguridad» and «Direcciones»,
// as `customer_profile_page.dart` and `customer_addresses_page.dart` draw
// them. What each field asks for, the words and what a save writes come
// from `customer_portal_forms.dart`; the page script sends the forms to
// [portalActionPath] and draws what the server answers.

CustomerAddress? _address(Object? row) {
  if (row is! Map) return null;
  try {
    return CustomerAddress.fromJson(Map<String, dynamic>.from(row));
  } on Object {
    return null;
  }
}

String _profileText(Map<String, dynamic> profile, String key) =>
    (profile[key] ?? '').toString().trim();

// =============================================================== the profile

/// `CustomerProfilePage`: the facts (or their form, in place) and the
/// password, with the dialog that changes it.
Component _profile(PortalViewData data, _Sheets sheets) {
  final profile = data.profile;
  final named = customerFirstName(profile) != null;
  final name = named ? '${profile['name'] ?? ''}' : '';
  final password = sheets._add(
    (id) => _passwordDialog(id, email: _profileText(profile, 'email')),
  );
  return div(
    classes: 'pt-profile',
    attributes: {'data-profile': ''},
    [
      _section(
        'Datos personales',
        actionLabel: 'Editar',
        actionAct: 'profile-edit',
        child: div([
          _profileFacts(profile, named: named),
          _profileForm(profile, name: name),
        ]),
      ),
      span(classes: 'pt-gap72', const []),
      _section(
        'Seguridad',
        child: div(classes: 'pt-rows', [
          button(
            classes: 'pt-prow tap',
            attributes: {'type': 'button', 'data-password': password},
            [
              _thumb(fallback: mdLockOutline, size: 64),
              span(classes: 'pt-prow-main', [
                span(classes: 'pt-row-title', [_t('Contraseña')]),
                span(classes: 'pt-row-meta', [
                  _t(
                    data.pendingRevocation
                        ? 'Tu nueva contraseña ya está activa'
                        : 'Cambia la contraseña con que entras a la tienda',
                  ),
                ]),
              ]),
              RawText(materialIcon(mdArrowForward, size: 18)),
            ],
          ),
          if (data.pendingRevocation)
            div(classes: 'pt-revoke', [
              p(classes: 'pt-revoke-title', [
                _t(customerRevocationPendingTitle),
              ]),
              p(classes: 'pt-revoke-msg', [
                _t(customerRevocationPendingMessage),
              ]),
              div(classes: 'pt-revoke-go', [
                button(
                  classes: 'pt-tbtn',
                  attributes: {
                    'type': 'button',
                    'data-password': password,
                    'data-step-to': 'revocation',
                    'aria-label': 'Completar cierre',
                  },
                  [_t('Completar cierre')],
                ),
              ]),
            ]),
        ]),
      ),
    ],
  );
}

/// The facts as rows: an empty one says «AGREGAR» and opens the form.
Component _profileFacts(Map<String, dynamic> profile, {required bool named}) {
  Component fact(String label, String? value, {String? note}) {
    final text = (value ?? '').trim();
    final children = [
      span(classes: 'pt-prow-main', [
        span(classes: 'pt-row-title', [_t(label)]),
        if (note != null) span(classes: 'pt-row-meta', [_t(note)]),
      ]),
      span(classes: 'pt-prow-trail', [
        if (text.isEmpty)
          span(
            classes: 'pt-prow-add',
            attributes: {'aria-label': 'Agregar'},
            [_t('Agregar')],
          )
        else
          span(classes: 'pt-prow-value', [_t(text)]),
      ]),
      if (text.isEmpty) RawText(materialIcon(mdArrowForward, size: 18)),
    ];
    return text.isEmpty
        ? button(
            classes: 'pt-prow tap',
            attributes: {'type': 'button', 'data-act': 'profile-edit'},
            children,
          )
        : div(classes: 'pt-prow', children);
  }

  return div(
    classes: 'pt-rows',
    attributes: {'data-profile-facts': ''},
    [
      fact('Nombre', named ? profile['name']?.toString() : null),
      fact('RUT', profile['rut']?.toString(), note: 'Para tus boletas'),
      fact('Teléfono', profile['phone']?.toString()),
      div(classes: 'pt-prow', [
        span(classes: 'pt-prow-main', [
          span(classes: 'pt-row-title', [_t('Correo')]),
          span(classes: 'pt-row-meta', [
            _t('Es tu acceso a la cuenta; no se cambia desde aquí.'),
          ]),
        ]),
        span(classes: 'pt-prow-trail', [
          span(classes: 'pt-prow-value', [_t(_profileText(profile, 'email'))]),
        ]),
      ]),
    ],
  );
}

/// The form «Editar» opens in place of the facts.
Component _profileForm(Map<String, dynamic> profile, {required String name}) =>
    form(
      classes: 'pt-pform',
      attributes: {
        'data-form': 'profile',
        'novalidate': '',
        'hidden': '',
        'autocomplete': 'on',
      },
      [
        div(classes: 'pt-rows', [
          div(classes: 'pt-pform-in', [
            div(classes: 'pt-fgrid', [
              _field(
                'name',
                'Nombre completo',
                value: name,
                autocomplete: 'name',
                capitalize: 'words',
                required: customerProfileNameError(''),
              ),
              _field(
                'rut',
                'RUT',
                value: _profileText(profile, 'rut'),
                hint: '12.345.678-9',
              ),
              _field(
                'phone',
                'Teléfono',
                value: _profileText(profile, 'phone'),
                hint: '+56 9 1234 5678',
                type: 'tel',
                autocomplete: 'tel',
              ),
              // Flutter colors this one: `TextStyle(color: inkSecondary)`.
              _field(
                'email',
                'Correo de acceso',
                value: _profileText(profile, 'email'),
                disabled: true,
                classes: 'keep',
              ),
            ]),
            div(classes: 'pt-factions', [
              _button(
                'Cancelar',
                kind: 'sec',
                attributes: {'data-act': 'profile-cancel'},
              ),
              _submit('Guardar cambios', busy: 'Guardando…'),
            ]),
          ]),
        ]),
      ],
    );

/// «Cambiar contraseña»: three steps in one dialog, as Flutter's
/// `_CustomerPasswordChangeDialog` (the new password, the code Auth mails
/// when the session needs it, and closing the other sessions when that
/// failed). The page script moves between them (`data-step`).
Component _passwordDialog(String id, {required String email}) => _alert(
  id,
  width: 420,
  scrollable: true,
  dismissible: false,
  step: 'password',
  form: 'password',
  title: [
    _stepText('password', 'Cambiar contraseña'),
    _stepText('verification', 'Verifica que eres tú'),
    _stepText('revocation', 'Completar seguridad'),
  ],
  body: [
    div(
      classes: 'pt-step-body',
      attributes: {'data-step-only': 'password'},
      [
        p(classes: 'pt-alert-text', [_t(customerPasswordIntro)]),
        div(classes: 'pt-fstack', [
          _field(
            'password',
            'Nueva contraseña',
            type: 'password',
            autocomplete: 'new-password',
            helper: AuthInputValidation.strongPasswordHelper,
            required: AuthInputValidation.validatePassword(
              '',
              isNewPassword: true,
            ),
          ),
          _field(
            'confirm',
            'Confirmar contraseña',
            type: 'password',
            autocomplete: 'new-password',
            required: AuthInputValidation.validatePasswordConfirmation(
              '',
              password: '',
            ),
          ),
        ]),
        p(
          classes: 'pt-alert-error',
          attributes: {'data-error': 'password', 'hidden': ''},
          const [],
        ),
      ],
    ),
    div(
      classes: 'pt-step-body',
      attributes: {'data-step-only': 'verification'},
      [
        p(classes: 'pt-alert-text', [_t(customerVerificationPrompt(email))]),
        div(classes: 'pt-fstack', [
          _field(
            'code',
            'Código de verificación',
            inputMode: 'numeric',
            autocomplete: 'one-time-code',
            maxLength: 6,
            classes: 'code',
            required: customerVerificationCodeError(''),
          ),
        ]),
        p(
          classes: 'pt-alert-error near',
          attributes: {'data-error': 'verification', 'hidden': ''},
          const [],
        ),
        p(
          classes: 'pt-alert-notice',
          attributes: {'data-notice': '', 'hidden': ''},
          const [],
        ),
      ],
    ),
    div(
      classes: 'pt-step-body',
      attributes: {'data-step-only': 'revocation'},
      [
        p(classes: 'pt-alert-strong', [
          _t('Tu contraseña ya quedó actualizada.'),
        ]),
        p(classes: 'pt-alert-text', [_t(customerRevocationIntro)]),
        p(
          classes: 'pt-alert-error',
          attributes: {'data-error': 'revocation', 'hidden': ''},
          const [],
        ),
      ],
    ),
  ],
  actions: [
    span(
      classes: 'pt-alert-act',
      attributes: {'data-step-only': 'password verification'},
      [
        _button('Cancelar', kind: 'sec', attributes: {'data-close': ''}),
      ],
    ),
    span(
      classes: 'pt-alert-act',
      attributes: {'data-step-only': 'revocation'},
      [
        _button(
          'Cerrar por ahora',
          kind: 'sec',
          attributes: {'data-close': ''},
        ),
      ],
    ),
    span(
      classes: 'pt-alert-act',
      attributes: {'data-step-only': 'verification'},
      [
        button(
          classes: 'pt-tbtn',
          attributes: {
            'type': 'button',
            'data-act': 'password-resend',
            'aria-label': 'Reenviar código',
          },
          [_t('Reenviar código')],
        ),
      ],
    ),
    span(
      classes: 'pt-alert-act',
      attributes: {'data-step-only': 'password'},
      [_submit('Cambiar', name: 'password')],
    ),
    span(
      classes: 'pt-alert-act',
      attributes: {'data-step-only': 'verification'},
      [_submit('Verificar y cambiar', name: 'verification')],
    ),
    span(
      classes: 'pt-alert-act',
      attributes: {'data-step-only': 'revocation'},
      [_submit('Reintentar cierre', name: 'revocation')],
    ),
  ],
);

Component _stepText(String step, String text) =>
    span(attributes: {'data-step-only': step}, [_t(text)]);

// ============================================================ the addresses

/// `CustomerAddressesPage`: the rows (principal first), or the empty state;
/// one form dialog for a new address or an edit, one confirmation to
/// delete and the rows' menu.
Component _addresses(PortalViewData data, _Sheets sheets) {
  final profile = data.profile;
  final profileName = _profileText(profile, 'name');
  final profilePhone = _profileText(profile, 'phone');
  sheets._add(
    (id) => _addressDialog(
      id,
      profileName: profileName,
      profilePhone: profilePhone,
    ),
  );
  sheets._add(_deleteDialog);
  final addresses = customerAddressesInOrder(data.addresses);
  if (addresses.isEmpty) {
    return _empty(
      'No tienes direcciones guardadas.',
      message:
          'Guarda la de tu casa o tu trabajo y no tendrás que '
          'escribirla en cada compra.',
      actions: [
        _button(
          'Agregar la primera dirección',
          icon: mdAdd,
          attributes: {'data-address': 'new'},
        ),
      ],
    );
  }
  return div([
    div(classes: 'pt-rows', [
      for (final address in addresses)
        _addressRow(
          address,
          usesProfile: customerAddressUsesProfileContact(
            address,
            profileName: profileName,
            profilePhone: profilePhone,
          ),
        ),
    ]),
    div(
      classes: 'pt-menu',
      attributes: {'role': 'menu', 'data-address-menu': '', 'hidden': ''},
      [
        button(
          classes: 'pt-menu-item',
          attributes: {
            'type': 'button',
            'role': 'menuitem',
            'data-menu': 'edit',
          },
          [_t('Editar')],
        ),
        button(
          classes: 'pt-menu-item',
          attributes: {
            'type': 'button',
            'role': 'menuitem',
            'data-menu': 'default',
          },
          [_t('Usar como principal')],
        ),
        button(
          classes: 'pt-menu-item danger',
          attributes: {
            'type': 'button',
            'role': 'menuitem',
            'data-menu': 'delete',
          },
          [_t('Eliminar')],
        ),
      ],
    ),
  ]);
}

/// One address: its name, the full address and who receives; the row
/// edits, the menu makes it the principal or deletes it.
Component _addressRow(CustomerAddress address, {required bool usesProfile}) {
  final contact = customerAddressContact(address);
  final values = {
    'id': address.id,
    'label': address.label,
    'recipient_name': address.recipientName,
    'phone': address.phone,
    'street_address': address.streetAddress,
    'street_number': address.streetNumber ?? '',
    'apartment': address.apartment ?? '',
    'comuna': address.comuna,
    'city': address.city,
    'region': address.region,
    'postal_code': address.postalCode ?? '',
    'additional_info': address.additionalInfo ?? '',
    'is_default': address.isDefault,
    'profile_contact': usesProfile,
  };
  return div(
    classes: 'pt-arow',
    attributes: {
      'data-address-row': jsonEncode(values),
      'data-delete-title': '¿Eliminar «${address.label}»?',
      'data-full': address.fullAddress,
    },
    [
      button(
        classes: 'pt-prow tap pt-arow-main',
        attributes: {
          'type': 'button',
          'data-address': 'edit',
          'aria-label': 'Editar ${address.label}',
        },
        [
          _thumb(fallback: mdLocationOnOutlined, size: 64),
          span(classes: 'pt-prow-main', [
            span(classes: 'pt-row-title', [_t(address.label)]),
            span(classes: 'pt-row-meta three', [
              _lines(
                [
                  address.fullAddress,
                  if (contact.isNotEmpty) contact,
                ].join('\n'),
              ),
            ]),
            if (address.isDefault)
              span(classes: 'pt-arow-foot', [_tag('Principal', 'ink')]),
          ]),
          if (address.isDefault)
            span(classes: 'pt-arow-tag', [_tag('Principal', 'ink')]),
          span(classes: 'pt-arow-space', const []),
        ],
      ),
      button(
        classes: 'pt-ibtn pt-arow-more',
        attributes: {
          'type': 'button',
          'data-address-more': '',
          'aria-haspopup': 'menu',
          'aria-label': 'Opciones de ${address.label}',
          'title': 'Opciones de ${address.label}',
        },
        [RawText(materialIcon(mdMoreVert))],
      ),
    ],
  );
}

/// «Nueva dirección» / «Editar dirección», filled by the script from the
/// row it edits.
Component _addressDialog(
  String id, {
  required String profileName,
  required String profilePhone,
}) {
  final hasProfileContact = profileName.isNotEmpty && profilePhone.isNotEmpty;
  final required = customerAddressRequiredError('');
  return _alert(
    id,
    width: 500,
    step: 'new',
    form: 'address',
    attributes: {
      'data-address-dialog': '',
      'data-profile-name': profileName,
      'data-profile-phone': profilePhone,
    },
    title: [
      _stepText('new', 'Nueva dirección'),
      _stepText('edit', 'Editar dirección'),
    ],
    body: [
      div(classes: 'pt-addr', [
        const input(type: InputType.hidden, name: 'id', value: ''),
        const input(type: InputType.hidden, name: 'postal_code', value: ''),
        _field('label', 'Etiqueta (ej: Casa, Trabajo)', required: required),
        label(classes: hasProfileContact ? 'pt-mine' : 'pt-mine off', [
          _checkbox('profile_contact', disabled: !hasProfileContact),
          span(classes: 'pt-mine-text', [
            span(classes: 'pt-row-title', [_t('Usar mis datos de cuenta')]),
            span(classes: 'pt-row-meta', [
              _t(
                customerProfileContactLabel(
                  profileName: profileName,
                  profilePhone: profilePhone,
                ),
              ),
            ]),
          ]),
        ]),
        _field('recipient_name', 'Nombre del destinatario', required: required),
        _field('phone', 'Teléfono', type: 'tel', required: required),
        div(
          classes: 'pt-addr-search',
          attributes: {'data-places': '', 'hidden': ''},
          [
            _field(
              'search',
              'Buscar dirección en Google Maps',
              hint: 'Ej: Álvarez 32, Viña del Mar',
              icon: mdSearch,
              autocomplete: 'off',
              attributes: {
                'role': 'combobox',
                'aria-autocomplete': 'list',
                'aria-expanded': 'false',
                'aria-controls': '$id-sugs',
              },
            ),
            ul(
              classes: 'pt-sugs',
              attributes: {'id': '$id-sugs', 'role': 'listbox', 'hidden': ''},
              const [],
            ),
          ],
        ),
        div(classes: 'pt-addr-street', [
          _field('street_address', 'Calle', required: required),
          _field('street_number', 'Número'),
        ]),
        _field('apartment', 'Depto/Oficina (opcional)'),
        _field('comuna', 'Comuna', required: required),
        _field('city', 'Ciudad', required: required),
        _field('region', 'Región', required: required),
        _field('additional_info', 'Referencias (opcional)', rows: 2),
        label(classes: 'pt-check-tile', [
          _checkbox('is_default'),
          span(classes: 'pt-row-title', [_t('Usar como dirección principal')]),
        ]),
      ]),
    ],
    actions: [
      _button('Cancelar', kind: 'sec', attributes: {'data-close': ''}),
      _submit('Guardar dirección', busy: 'Guardando…'),
    ],
  );
}

/// «¿Eliminar «Casa»?» with the full address; the script names it.
Component _deleteDialog(String id) => _alert(
  id,
  width: 480,
  step: 'delete',
  form: 'address-delete',
  attributes: {'data-delete-dialog': ''},
  title: [
    span(attributes: {'data-delete-title': ''}, const []),
  ],
  body: [
    p(classes: 'pt-alert-sub', attributes: {'data-delete-full': ''}, const []),
  ],
  actions: [
    _button('Cancelar', kind: 'sec', attributes: {'data-close': ''}),
    _submit('Eliminar', kind: 'danger'),
  ],
);

// ================================================================= controls

/// A Material outlined field as the portal's form theme draws it: square,
/// a fine line, the action color when writing, the label resting inside
/// and floating into the line. [required] is the message an empty field
/// shows on saving.
Component _field(
  String name,
  String labelText, {
  String value = '',
  String type = 'text',
  String? hint,
  String? helper,
  String? autocomplete,
  String? inputMode,
  String? capitalize,
  String? required,
  String? icon,
  String? classes,
  bool disabled = false,
  int? maxLength,
  int rows = 1,
  Map<String, String> attributes = const {},
}) {
  // A page has one form of each kind, so a name is unique on it.
  final id = 'pt-f-$name';
  final common = {
    'id': id,
    'name': name,
    'placeholder': hint ?? ' ',
    'autocomplete': ?autocomplete,
    'inputmode': ?inputMode,
    'autocapitalize': ?capitalize,
    'maxlength': ?maxLength?.toString(),
    'data-required': ?required,
    'disabled': ?(disabled ? '' : null),
    'aria-describedby': '$id-m',
    ...attributes,
  };
  return div(
    classes: [
      'pt-f',
      if (rows > 1) 'ta',
      if (icon != null) 'ic',
      if (disabled) 'off',
      ?classes,
    ].join(' '),
    [
      if (rows > 1)
        textarea(attributes: {...common, 'rows': '$rows'}, [.text(value)])
      else
        input(attributes: {...common, 'type': type, 'value': value}),
      Component.element(
        tag: 'label',
        attributes: {'for': id},
        children: [_t(labelText)],
      ),
      Component.element(
        tag: 'fieldset',
        attributes: {'aria-hidden': 'true'},
        children: [
          Component.element(
            tag: 'legend',
            children: [
              span([.text(labelText)]),
            ],
          ),
        ],
      ),
      if (icon != null) span(classes: 'pt-f-ic', [RawText(materialIcon(icon))]),
      if (type == 'search' || icon != null)
        span(
          classes: 'pt-f-busy',
          attributes: {'hidden': ''},
          [RawText(_spinner)],
        ),
      p(
        classes: 'pt-f-msg',
        attributes: {'id': '$id-m', 'data-helper': helper ?? ''},
        [if (helper != null) .text(helper)],
      ),
    ],
  );
}

/// A square Material checkbox in the action color.
Component _checkbox(String name, {bool disabled = false}) =>
    span(classes: 'pt-cb', [
      input(type: InputType.checkbox, name: name, disabled: disabled),
      RawText(materialIcon(mdCheck, size: 18, classes: 'pt-cb-mark')),
    ]);

/// A form's main button, with Flutter's busy state (a spinner, the label
/// [busy] says while it works).
Component _submit(
  String label, {
  String kind = 'pri',
  String? busy,
  String? name,
}) => button(
  classes: 'pt-btn $kind',
  attributes: {
    'type': 'submit',
    'data-submit': ?name,
    'data-busy-label': ?busy,
  },
  [
    span(
      classes: 'pt-btn-spin',
      attributes: {'hidden': ''},
      [RawText(_spinner)],
    ),
    span(classes: 'pt-btn-label', [_t(label)]),
  ],
);

/// `PortalDialog`: Flutter's `AlertDialog` with the portal's bar, its title
/// in capitals, the content and the actions at the end. [step] is the part
/// shown first; [dismissible] lets the scrim close it.
Component _alert(
  String id, {
  required int width,
  required String step,
  required String form,
  required List<Component> title,
  required List<Component> body,
  required List<Component> actions,
  bool scrollable = false,
  bool dismissible = true,
  Map<String, String> attributes = const {},
}) => Component.element(
  tag: 'dialog',
  id: id,
  classes: 'pt-dlg alert',
  // Opening focuses the dialog, not its first field: Flutter's dialog opens
  // with no field focused (its label stays inside).
  attributes: {
    'aria-labelledby': '$id-t',
    'data-step': step,
    'autofocus': '',
    'tabindex': '-1',
    ...attributes,
  },
  children: [
    div(
      classes: 'pt-scrim',
      attributes: {'data-close': ?(dismissible ? '' : null)},
      const [],
    ),
    Component.element(
      tag: 'form',
      classes: scrollable ? 'pt-alert scroll' : 'pt-alert',
      attributes: {
        'data-form': form,
        'novalidate': '',
        'style': '--pt-aw:${width}px',
      },
      children: [
        span(classes: 'pt-panel-bar', const []),
        div(classes: 'pt-alert-main', [
          h2(classes: 'pt-alert-title', attributes: {'id': '$id-t'}, title),
          div(classes: 'pt-alert-body', body),
        ]),
        div(classes: 'pt-alert-actions', actions),
      ],
    ),
  ],
);
