import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/mail/services/mail_recipient_directory.dart';

/// La libreta del campo «Para» (dueño, 2026-11-16): proveedores, sus
/// contactos, clientes y a quién ya se le escribió. Nombres y direcciones son
/// inventados.

const _andina = MailRecipient(
  address: 'ventas@andina.example',
  kind: MailRecipientKind.supplier,
  name: 'Importadora Andina',
  logoUrl: 'https://example.invalid/andina.png',
);
const _rocio = MailRecipient(
  address: 'rocio@andina.example',
  kind: MailRecipientKind.supplier,
  name: 'Rocío Pérez',
  org: 'Importadora Andina',
  logoUrl: 'https://example.invalid/andina.png',
);
const _agata = MailRecipient(
  address: 'agata.soto@correo.example',
  kind: MailRecipientKind.customer,
  name: 'Ágata Soto',
);
final _nuevo = MailRecipient(
  address: 'nuevo@lejano.example',
  kind: MailRecipientKind.sent,
  uses: 2,
  lastUsed: DateTime.utc(2026, 11, 15, 12),
);
const _banco = MailRecipient(
  address: 'avisos@banco.example',
  kind: MailRecipientKind.sent,
  org: 'Banco Inventado',
  uses: 1,
);

class _FakeDirectory extends MailRecipientDirectory {
  _FakeDirectory(this.responses, {required DateTime Function() clock})
      : super(clock: clock);

  final List<Object?> responses;
  int calls = 0;

  @override
  Future<Object?> fetchDirectory() async {
    final response =
        responses[calls < responses.length ? calls : responses.length - 1];
    calls++;
    return response;
  }
}

void main() {
  group('libreta del servidor', () {
    test('lee cada fila y descarta lo que no es una dirección', () {
      final recipients = parseMailRecipients([
        {
          'address': ' Ventas@Andina.example ',
          'name': 'Importadora Andina',
          'logo': 'https://example.invalid/andina.png',
          'kind': 'supplier',
          'uses': 0,
        },
        {
          'address': 'nuevo@lejano.example',
          'kind': 'sent',
          'uses': 2,
          'last_used': '2026-11-15T12:00:00+00:00',
        },
        {
          'address': 'agata.soto@correo.example',
          'name': ' ',
          'kind': 'customer'
        },
        {'address': 'sin-arroba', 'kind': 'customer'},
        'basura',
      ]);

      expect(recipients.map((r) => r.address), [
        'ventas@andina.example',
        'nuevo@lejano.example',
        'agata.soto@correo.example',
      ]);
      expect(recipients[0].kind, MailRecipientKind.supplier);
      expect(recipients[0].logoUrl, 'https://example.invalid/andina.png');
      expect(recipients[1].kind, MailRecipientKind.sent);
      expect(recipients[1].uses, 2);
      expect(recipients[1].lastUsed, DateTime.utc(2026, 11, 15, 12));
      expect(recipients[2].name, isNull,
          reason: 'un nombre en blanco no es nombre');
      expect(parseMailRecipients(null), isEmpty);
    });

    test('cada fila dice quién es y de quién es la dirección', () {
      expect(_andina.title, 'Importadora Andina');
      expect(_andina.detail, 'ventas@andina.example · Proveedor');
      expect(_rocio.detail, 'rocio@andina.example · Importadora Andina');
      expect(_agata.detail, 'agata.soto@correo.example · Cliente');
      expect(_nuevo.title, 'nuevo@lejano.example');
      expect(_nuevo.detail, isNull,
          reason: 'sin nombre, la dirección va arriba y no se repite');
      expect(_banco.detail, 'Banco Inventado');
      // El logo es del proveedor: si no carga, van sus iniciales.
      expect(_rocio.markName, 'Importadora Andina');
      expect(_agata.markName, 'Ágata Soto');
    });
  });

  group('qué calza con lo escrito', () {
    test('por el comienzo de la dirección o del nombre, sin tildes', () {
      expect(mailRecipientMatch(_rocio, 'roc'), 3);
      expect(mailRecipientMatch(_rocio, 'ROCIO'), 3);
      expect(mailRecipientMatch(_agata, 'aga'), 3);
      expect(mailRecipientMatch(_agata, 'Ága'), 3);
    });

    test(
        'por el comienzo de cualquier palabra del nombre, del dueño o de la dirección',
        () {
      expect(mailRecipientMatch(_rocio, 'perez'), 2);
      expect(mailRecipientMatch(_rocio, 'andina'), 2,
          reason: 'el proveedor del contacto');
      expect(mailRecipientMatch(_nuevo, 'lejano'), 2, reason: 'el dominio');
      expect(mailRecipientMatch(_agata, 'soto ag'), 2,
          reason: 'varias palabras, en cualquier orden');
      expect(mailRecipientMatch(_banco, 'banco inv'), 2);
    });

    test('lo escrito con @ o punto vale por palabras o dentro de la dirección',
        () {
      expect(mailRecipientMatch(_nuevo, '@lejano'), 2);
      expect(mailRecipientMatch(_agata, 'soto@correo'), 2);
      expect(mailRecipientMatch(_agata, 'oto@corr'), 1,
          reason: 'a media palabra, sólo si va con @ o punto');
      expect(mailRecipientMatch(_agata, 'oto corr'), 0);
    });

    test('lo que no calza no se ofrece', () {
      expect(mailRecipientMatch(_rocio, 'xyz'), 0);
      expect(mailRecipientMatch(_rocio, 'cio'), 0,
          reason: 'sólo comienzos de palabra');
      expect(mailRecipientMatch(_rocio, '   '), 0);
    });
  });

  group('sugerencias', () {
    final libreta = [_andina, _rocio, _agata, _nuevo, _banco];

    test('lo más usado primero, después lo que mejor calza y los proveedores',
        () {
      expect(suggestMailRecipients(libreta, 'a').map((r) => r.address), [
        'avisos@banco.example', // usado una vez
        'agata.soto@correo.example', // empieza así (cliente)
        'ventas@andina.example', // empieza una palabra (proveedor)
        'rocio@andina.example', // empieza una palabra (proveedor)
      ]);
      expect(
          suggestMailRecipients(libreta, 'andina').map((r) => r.address),
          [
            'ventas@andina.example',
            'rocio@andina.example',
          ],
          reason: 'entre iguales, por nombre: Importadora antes que Rocío');
      expect(suggestMailRecipients(libreta, 'e').map((r) => r.address).first,
          'nuevo@lejano.example',
          reason: 'dos envíos pesan más que calzar mejor');
    });

    test('sin lo ya puesto, con tope y nada sin escribir', () {
      expect(
        suggestMailRecipients(libreta, 'andina',
            exclude: {'ventas@andina.example'}).map((r) => r.address),
        ['rocio@andina.example'],
      );
      expect(suggestMailRecipients(libreta, 'a', limit: 2), hasLength(2));
      expect(suggestMailRecipients(libreta, ' '), isEmpty);
    });
  });

  group('el destinatario que se escribe', () {
    test('es el trozo entre comas donde está el cursor', () {
      expect(currentMailRecipientToken('uno@a.example, ro', 17).text, ' ro');
      expect(currentMailRecipientToken('uno@a.example, ro', 3).text,
          'uno@a.example');
      expect(currentMailRecipientToken('', 0).text, '');
      expect(currentMailRecipientToken('a@b.cl;c', 99).text, 'c');
    });

    test('elegir lo reemplaza y deja listo el siguiente', () {
      TextEditingValue at(String text, [int? cursor]) => TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: cursor ?? text.length),
          );

      expect(acceptMailRecipient(at('roc'), 'rocio@andina.example').text,
          'rocio@andina.example, ');
      final second =
          acceptMailRecipient(at('uno@a.example, roc'), 'rocio@andina.example');
      expect(second.text, 'uno@a.example, rocio@andina.example, ');
      expect(second.selection.baseOffset, second.text.length);
      expect(
          acceptMailRecipient(at('uno@a.example,roc'), 'rocio@andina.example')
              .text,
          'uno@a.example, rocio@andina.example, ');
      final middle = acceptMailRecipient(
          at('ro, dos@b.example', 2), 'rocio@andina.example');
      expect(middle.text, 'rocio@andina.example, dos@b.example');
      expect(middle.selection.baseOffset, 'rocio@andina.example, '.length);
    });

    test('las direcciones ya escritas, sin la que se está escribiendo', () {
      const text = 'Uno@A.example, dos@b.example, tr';
      final token = currentMailRecipientToken(text, text.length);
      expect(mailRecipientAddresses(text, except: token),
          {'uno@a.example', 'dos@b.example'});
      expect(mailRecipientAddresses(text),
          {'uno@a.example', 'dos@b.example', 'tr'});
      expect(mailRecipientAddresses(''), isEmpty);
    });
  });

  group('la libreta de la app', () {
    late DateTime now;
    setUp(() => now = DateTime.utc(2026, 11, 16, 15));

    test(
        'cada Redactar la vuelve a leer, y dos ventanas a la vez comparten la lectura',
        () async {
      final directory = _FakeDirectory([
        [
          {
            'address': 'ventas@andina.example',
            'name': 'Importadora Andina',
            'kind': 'supplier'
          },
        ],
        [
          {
            'address': 'ventas@andina.example',
            'name': 'Importadora Andina',
            'kind': 'supplier'
          },
          {
            'address': 'vendedor@andina.example',
            'name': 'Vendedor de Andina',
            'org': 'Importadora Andina',
            'kind': 'supplier'
          },
        ],
      ], clock: () => now);

      expect(directory.cached, isEmpty);
      final both = await Future.wait([directory.load(), directory.load()]);
      expect(directory.calls, 1);
      expect(both[0].single.address, 'ventas@andina.example');
      expect(directory.cached.single.address, 'ventas@andina.example');

      // El dueño le agrega el correo a un contacto y vuelve a Redactar un
      // minuto después: el contacto tiene que aparecer (2026-11-17).
      now = now.add(const Duration(minutes: 1));
      final again = await directory.load();
      expect(directory.calls, 2);
      expect(again.map((r) => r.address),
          containsAll(['ventas@andina.example', 'vendedor@andina.example']));
      expect(
          suggestMailRecipients(directory.cached, 'andina')
              .map((r) => r.address),
          contains('vendedor@andina.example'));
    });

    test(
        'lo recién enviado sube al tiro y no se cuenta dos veces cuando llega del servidor',
        () async {
      final sentAt = now;
      final directory = _FakeDirectory([
        [
          {
            'address': 'ventas@andina.example',
            'name': 'Importadora Andina',
            'kind': 'supplier',
            'uses': 0
          },
        ],
        [
          {
            'address': 'ventas@andina.example',
            'name': 'Importadora Andina',
            'kind': 'supplier',
            'uses': 0
          },
        ],
        [
          {
            'address': 'ventas@andina.example',
            'name': 'Importadora Andina',
            'kind': 'supplier',
            'uses': 1,
            'last_used': sentAt.toIso8601String(),
          },
          {
            'address': 'nuevo@lejano.example',
            'kind': 'sent',
            'uses': 1,
            'last_used': sentAt.toIso8601String(),
          },
        ],
      ], clock: () => now);

      await directory.load();
      directory.remember(
          ['Ventas@Andina.example ', 'nuevo@lejano.example', 'sin-arroba']);

      MailRecipient find(String address) =>
          directory.cached.firstWhere((r) => r.address == address);
      expect(find('ventas@andina.example').uses, 1);
      expect(find('ventas@andina.example').lastUsed, sentAt);
      expect(find('nuevo@lejano.example').kind, MailRecipientKind.sent);
      expect(directory.cached.where((r) => r.address == 'sin-arroba'), isEmpty);

      // El servidor todavía no lo trae: se sigue sumando aparte.
      now = now.add(const Duration(minutes: 1));
      await directory.load();
      expect(find('ventas@andina.example').uses, 1);
      expect(find('nuevo@lejano.example').uses, 1);

      // Ya llegó: cuenta lo del servidor, una sola vez.
      now = now.add(const Duration(minutes: 2));
      await directory.load();
      expect(find('ventas@andina.example').uses, 1);
      expect(find('nuevo@lejano.example').uses, 1);
      expect(directory.cached.where((r) => r.address == 'nuevo@lejano.example'),
          hasLength(1));
    });

    test('lo enviado que el servidor nunca trae se olvida a la media hora',
        () async {
      final directory = _FakeDirectory([const []], clock: () => now);
      await directory.load();
      directory.remember(['nuevo@lejano.example']);
      expect(directory.cached.single.address, 'nuevo@lejano.example');

      now = now
          .add(MailRecipientDirectory.rememberFor + const Duration(minutes: 1));
      await directory.load();
      expect(directory.cached, isEmpty);
    });
  });
}
