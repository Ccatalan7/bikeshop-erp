import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/mail/work/mail_work_models.dart';
import 'package:vinabike_erp/modules/mail/work/mail_work_words.dart';

/// Las palabras del correo que trabaja. Todo es inventado.
MailItem _item(Map<String, dynamic> extra) => MailItem.fromJson({
      'id': 'm-1',
      'mailbox': 'taller@ejemplo.invalid',
      'provider': 'gmail',
      'provider_message_id': 'p-1',
      'from_address': 'persona@ejemplo.invalid',
      'subject': 'Consulta',
      'received_at': '2026-11-06T13:00:00Z',
      'kind': 'customer',
      ...extra,
    });

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('los pesos se escriben como en Chile', () {
    expect(MailWords.money(45990), r'$45.990');
    expect(MailWords.money(3000.4), r'$3.000');
  });

  test('las entidades guardadas se leen, aunque vengan dos veces', () {
    expect(
        MailWords.decodeEntities('Ver la p&amp;aacute;gina'), 'Ver la página');
    expect(MailWords.decodeEntities('Se&ntilde;or &#40;taller&#x29;'),
        'Señor (taller)');
    expect(MailWords.decodeEntities('Tom &amp; Jerry'), 'Tom & Jerry');
    expect(
        MailWords.decodeEntities('&desconocida; queda'), '&desconocida; queda');
  });

  test('un párrafo cortado a mano se une; datos y listas quedan como vienen',
      () {
    const text = 'Hola, equipo:\n\n'
        'Les escribo porque quiero cambiar los frenos de mi bicicleta de\n'
        'ruta antes del fin de semana y no sé si tienen las pastillas\n'
        'en stock.\n\n'
        'Nombre: Persona Inventada\n'
        'Monto: \$12.000\n\n'
        '- pastillas\n'
        '- cable de freno de repuesto para la bicicleta de mi hija menor';
    final out = MailWords.readable(text);
    expect(
      out,
      'Hola, equipo:\n\n'
      'Les escribo porque quiero cambiar los frenos de mi bicicleta de ruta '
      'antes del fin de semana y no sé si tienen las pastillas en stock.\n\n'
      'Nombre: Persona Inventada\nMonto: \$12.000\n\n'
      '- pastillas\n'
      '- cable de freno de repuesto para la bicicleta de mi hija menor',
    );
  });

  test('el CSS que un remitente dejó en el texto no se lee', () {
    const text = 'Se ha creado una solicitud de envío\n\n'
        '@media screen and (max-width: 450px) {\nbody {\ndisplay: flex;\n'
        'flex-direction: column;\n}\n}\n\n.header {\nmargin-bottom: 20px;\n}'
        '\n\nTu orden de flete es 123. Precio {según tarifa}.';
    expect(
      MailWords.readable(text),
      'Se ha creado una solicitud de envío\n\n'
      'Tu orden de flete es 123. Precio {según tarifa}.',
    );
  });

  test('los corchetes sueltos de una imagen no se leen', () {
    expect(MailWords.readable('[\nEstimado:\n\nGracias.\n]\n['),
        'Estimado:\n\nGracias.');
  });

  test('las direcciones largas de los enlaces no se leen', () {
    expect(
      MailWords.readable(
          'Ver reseña <https://ejemplo.invalid/a/b/c?x=1>\nGracias'),
      'Ver reseña\nGracias',
    );
  });

  test('el número de operación del aviso del banco', () {
    expect(
        MailWords.operationNumber('Hora19:08\nNumero de operacion635938240135'),
        '635938240135');
    expect(MailWords.operationNumber('N° de operación: 1234567'), '1234567');
    expect(MailWords.operationNumber('Sin datos de la transferencia'), isNull);
  });

  test('sin nombre, la fila no repite la dirección', () {
    expect(MailWords.rowDetail(_item(const {})), '');
    expect(
      MailWords.rowDetail(_item(const {'from_name': 'Persona Inventada'})),
      'persona@ejemplo.invalid',
    );
  });

  test('un comprobante que no viene del banco se confirma antes de entregar',
      () {
    expect(
        MailWords.unverifiedPayment(_item(const {
          'subject': 'Comprobante de transferencia pedido 1234',
        })),
        isTrue);
    expect(
        MailWords.unverifiedPayment(_item(const {
          'subject': 'Aviso de transferencia de fondos',
          'kind': 'transfer',
          'party_type': 'bank',
        })),
        isFalse,
        reason: 'el aviso del banco es la prueba');
    expect(
        MailWords.unverifiedPayment(
            _item(const {'subject': '¿Tienen cadenas?'})),
        isFalse);
  });

  test('cómo va la lectura de una casilla', () {
    final now = DateTime(2026, 11, 6, 12);
    expect(
        MailWords.mailboxSync(
            lastSyncedAt: now.subtract(const Duration(minutes: 1)),
            hasError: false,
            now: now),
        'al día');
    expect(
        MailWords.mailboxSync(
            lastSyncedAt: now.subtract(const Duration(minutes: 12)),
            hasError: false,
            now: now),
        'al día hace 12 min');
    expect(MailWords.mailboxSync(lastSyncedAt: null, hasError: false, now: now),
        'trayendo su correo…');
    expect(MailWords.mailboxSync(lastSyncedAt: now, hasError: true, now: now),
        'no se pudo leer');
  });

  test('cada casilla trae su número para hoy', () {
    final counts = MailCounts.fromJson(const {
      'today': 3,
      'mailboxes': [
        {'address': 'a@ejemplo.invalid', 'provider': 'gmail', 'today': 2},
        {'address': 'b@ejemplo.invalid', 'provider': 'zoho', 'error': true},
      ],
    });
    expect(counts.mailboxes.map((m) => m.today), [2, 0]);
    expect(counts.mailboxes.last.hasError, isTrue);
  });

  // -------------------------------------------------------------------------
  // Esperando (20261106260000)
  // -------------------------------------------------------------------------

  MailItem sent({
    required DateTime at,
    bool overdue = false,
    bool done = false,
    String? doneText,
  }) =>
      MailItem.fromJson({
        'id': 'out-1',
        'mailbox': 'taller@ejemplo.invalid',
        'provider': 'gmail',
        'provider_message_id': 'p-out-1',
        'direction': 'out',
        'from_address': 'taller@ejemplo.invalid',
        'to': ['ventas@proveedor.invalid'],
        'subject': 'Re: Pastillas de freno',
        'received_at': at.toIso8601String(),
        'kind': 'own',
        'facts': {
          'to_party': {
            'address': 'ventas@proveedor.invalid',
            'type': 'supplier',
            'label': 'Repuestos Inventados',
          },
        },
        'state': {
          'actionable': true,
          'action': 'remind',
          'done': done,
          if (doneText != null) 'done_text': doneText,
          'waiting_since': at.toIso8601String(),
          'overdue': overdue,
          'remind_to': 'ventas@proveedor.invalid',
        },
      });

  test('lo que mandamos se titula por quien lo recibe', () {
    final item = sent(at: DateTime(2026, 11, 2, 10));
    expect(item.recipientTitle, 'Repuestos Inventados');
    expect(item.otherSideTitle, 'Repuestos Inventados');
    expect(MailWords.rowDetail(item), 'Enviado el 2 de noviembre');
  });

  test('el estado de lo que espera respuesta', () {
    final now = DateTime.now();
    expect(MailWords.rowStatus(sent(at: now.subtract(const Duration(days: 1)))),
        'Esperando');
    expect(
        MailWords.rowStatus(sent(
            at: now.subtract(const Duration(days: 4, hours: 1)),
            overdue: true)),
        '4 días sin respuesta');
    expect(
        MailWords.rowStatus(sent(
            at: now.subtract(const Duration(days: 4)),
            done: true,
            doneText: 'Ya respondieron')),
        'Respondieron');
    expect(MailWords.todayGroupOf(sent(at: now)), 'seguimientos');
    expect(MailWords.actionLabel(sent(at: now)), 'Mandar recordatorio');
  });

  test('el recordatorio de lo que mandamos, listo para revisar', () {
    final text = MailWords.reminderText(sent(at: DateTime(2026, 11, 2, 10)));
    expect(
        text,
        'Hola, ¿pudieron revisar mi correo del 2 de noviembre sobre '
        '«Pastillas de freno»? Quedamos atentos.\n\nEquipo Viñabike');
  });

  test('el recordatorio de un reclamo nombra el caso y el día en que empezó',
      () {
    final claim = MailItem.fromJson({
      'id': 'c-2',
      'mailbox': 'taller@ejemplo.invalid',
      'provider': 'gmail',
      'provider_message_id': 'p-c-2',
      'from_address': 'clientes@courier.invalid',
      'subject': 'Re: Caso registrado: XQ-123456 reclamo',
      'received_at': '2026-10-28T12:00:00Z',
      'kind': 'claim',
      'facts': {'case_ref': 'XQ-123456'},
      'case': [
        {
          'id': 'c-1',
          'subject': 'Caso registrado: XQ-123456 reclamo',
          'received_at': '2026-10-20T12:00:00Z',
          'kind': 'claim',
          'direction': 'in',
        },
      ],
    });
    expect(
        MailWords.reminderText(claim),
        'Hola, escribo por el caso XQ-123456 del 20 de octubre. '
        '¿Tienen novedades?\n\nEquipo Viñabike');
    expect(MailWords.plainSubject('RE: Fwd: Despacho'), 'Despacho');
    expect(MailWords.plainSubject('Fallo en el despacho de un pedido.'),
        'Fallo en el despacho de un pedido');
  });

  test('cuando el proveedor respondió el reclamo, nos toca', () {
    final answered = MailItem.fromJson({
      'id': 'c-9',
      'mailbox': 'taller@ejemplo.invalid',
      'provider': 'gmail',
      'provider_message_id': 'p-c-9',
      'from_address': 'contacto@proveedor.invalid',
      'party_label': 'Ciclo Inventado',
      'subject': 'Re: Fallo en el despacho',
      'received_at': '2026-10-20T19:10:00Z',
      'kind': 'claim',
      'read': true,
      'state': {'actionable': true, 'action': 'reply', 'done': false},
    });
    expect(MailWords.why(answered).$1,
        'Ciclo Inventado respondió el reclamo el 20 de octubre.');
    expect(MailWords.rowStatus(answered), 'Por responder');
    expect(MailWords.todayGroupOf(answered), 'seguimientos');
  });

  test('un desconocido que dice ser un banco', () {
    final fake = MailItem.fromJson({
      'id': 'f-1',
      'mailbox': 'taller@ejemplo.invalid',
      'provider': 'gmail',
      'provider_message_id': 'p-f-1',
      'from_address': 'alertas@otro.invalid',
      'subject': 'Su cuenta fue bloqueada',
      'received_at': '2026-11-06T12:00:00Z',
      'kind': 'security',
      'facts': {'fake_bank': true, 'bank_name': 'Banco de Chile'},
      'state': {'actionable': true, 'action': 'review', 'done': false},
    });
    expect(fake.fakeBank, isTrue);
    expect(MailWords.why(fake).$1,
        'Dice ser de Banco de Chile, pero no viene de su dirección.');
  });
}
