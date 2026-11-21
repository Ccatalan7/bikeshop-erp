import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/crm/services/client_data_draft.dart';
import 'package:vinabike_erp/shared/utils/contact_greeting.dart';

ClientRecord _record({
  String name = 'Ivan Ostoic',
  String? phone,
  String? email,
  String? rut,
  String? address,
  String? notes,
  String token = '2026-10-03T12:00:00.123456+00:00',
}) =>
    ClientRecord.fromRow({
      'id': 'customer-1',
      'tenant_id': 'tenant-1',
      'name': name,
      'phone': phone,
      'email': email,
      'rut': rut,
      'address': address,
      'notes': notes,
      'is_active': true,
      'created_at': '2025-11-13T15:20:31.000000+00:00',
      'updated_at': token,
    });

void main() {
  group('Cómo saludarle (20261121200000)', () {
    test('the record reads its greeting; without the column, the first name',
        () {
      expect(_greeted().greeting, 'María');
      expect(_greeted(style: 'two_names').greeting, 'María José');
      expect(_greeted(style: 'custom', custom: 'Majo').greeting, 'Majo');
    });

    test('a changed greeting is one change and saves its two columns', () {
      final draft = ClientDataDraft(_greeted(style: 'two_names'));
      expect(draft.changeCount, 0);
      draft.setGreetingStyle(ContactGreetingStyle.secondName);
      expect(draft.isGreetingChanged, isTrue);
      expect(draft.changeCount, 1);
      expect(draft.greeting, 'José');
      expect(draft.changes, {
        'greeting_style': 'second_name',
        'greeting_custom_name': null,
      });
      draft.revertGreeting();
      expect(draft.changeCount, 0);
      expect(draft.changes, isEmpty);
    });

    test('a custom greeting needs its text, in one line', () {
      final draft = ClientDataDraft(_greeted())
        ..setGreetingStyle(ContactGreetingStyle.custom);
      expect(draft.greetingProblem, 'Escribe cómo saludarle.');
      draft.setGreetingCustom('  Majo \n');
      expect(draft.greetingProblem, isNull);
      expect(draft.changes['greeting_custom_name'], 'Majo');
      expect(draft.changes['greeting_style'], 'custom');
    });

    test('the greeting follows the name being written', () {
      final draft = ClientDataDraft(_greeted(style: 'two_names'))
        ..set(ClientDataField.name, 'Juan Pablo Vera');
      expect(draft.greeting, 'Juan Pablo');
    });

    test('a rebase keeps the greeting this edit chose', () {
      final draft = ClientDataDraft(_greeted())
        ..setGreetingStyle(ContactGreetingStyle.twoNames);
      final next = draft.rebasedOn(_greeted(style: 'first_name'));
      expect(next.greetingStyle, ContactGreetingStyle.twoNames);
      expect(next.isGreetingChanged, isTrue);
    });
  });

  group('ClientRecord', () {
    test('keeps the stored updated_at text as the edit token', () {
      // Comparar un DateTime de vuelta pierde los microsegundos en la web.
      expect(_record().updatedAtToken, '2026-10-03T12:00:00.123456+00:00');
    });

    test('the Zoho import line is the origin, not a shop note', () {
      final imported = _record(notes: 'Zoho ID: 5555000001234567');
      expect(imported.importedFromZoho, isTrue);
      expect(imported.shopNotes, isNull);
      expect(imported.valueOf(ClientDataField.notes), isNull);

      final mixed = _record(notes: 'Zoho ID: 555\nPrefiere WhatsApp');
      expect(mixed.shopNotes, 'Prefiere WhatsApp');
      expect(_record(notes: 'Cliente frecuente').importedFromZoho, isFalse);
    });

    test('empty text reads as missing', () {
      final record = _record(phone: '  ', email: '');
      expect(record.phone, isNull);
      expect(record.email, isNull);
    });
  });

  group('ClientDataDraft', () {
    test('writes only what changed', () {
      final draft = ClientDataDraft(_record(email: 'ivan@correo.cl'));
      expect(draft.changeCount, 0);
      expect(draft.changes, isEmpty);

      draft.set(ClientDataField.phone, '981210019');
      expect(draft.changedFields, [ClientDataField.phone]);
      expect(draft.changes, {'phone': '+56 9 8121 0019'});
    });

    test('a RUT or phone written another way is not a change', () {
      final draft = ClientDataDraft(
          _record(rut: '12.345.678-5', phone: '+56 9 8121 0019'));
      draft.set(ClientDataField.rut, '12345678-5');
      draft.set(ClientDataField.phone, '+56981210019');
      expect(draft.changeCount, 0);
    });

    test('stores the RUT formatted and clears empty data as null', () {
      final draft = ClientDataDraft(_record(email: 'ivan@correo.cl'));
      draft.set(ClientDataField.rut, '123456785');
      draft.set(ClientDataField.email, '   ');
      expect(draft.changes, {'email': null, 'rut': '12.345.678-5'});
    });

    test('notes keep the hidden Zoho line', () {
      final draft = ClientDataDraft(_record(notes: 'Zoho ID: 555'));
      expect(draft.value(ClientDataField.notes), isNull);
      draft.set(ClientDataField.notes, 'Prefiere WhatsApp');
      expect(draft.changes, {'notes': 'Zoho ID: 555\nPrefiere WhatsApp'});

      final cleared =
          ClientDataDraft(_record(notes: 'Zoho ID: 555\nPrefiere WhatsApp'))
            ..set(ClientDataField.notes, '');
      expect(cleared.changes, {'notes': 'Zoho ID: 555'});
    });

    test('revert puts back what was read', () {
      final draft = ClientDataDraft(_record(phone: '+56 9 8121 0019'));
      draft.set(ClientDataField.phone, '+56 9 1111 2222');
      draft.revert(ClientDataField.phone);
      expect(draft.changeCount, 0);
      expect(draft.value(ClientDataField.phone), '+56 9 8121 0019');
    });

    test('names what cannot be saved', () {
      final draft = ClientDataDraft(_record())
        ..set(ClientDataField.name, ' ')
        ..set(ClientDataField.email, 'ivan@correo')
        ..set(ClientDataField.rut, '12.345.678-9');
      expect(draft.problems.keys, [
        ClientDataField.name,
        ClientDataField.email,
        ClientDataField.rut,
      ]);
      draft
        ..set(ClientDataField.name, 'Ivan Ostoic')
        ..set(ClientDataField.email, 'ivan@correo.cl')
        ..set(ClientDataField.rut, '12.345.678-5');
      expect(draft.problems, isEmpty);
    });

    test('an invalid value already stored does not block another change', () {
      // Hay un correo así en producción (2026-10-03).
      final draft = ClientDataDraft(_record(email: 'ivan@correo'))
        ..set(ClientDataField.phone, '981210019');
      expect(draft.problems, isEmpty);
      expect(draft.changes, {'phone': '+56 9 8121 0019'});

      draft.set(ClientDataField.email, 'ivan@correo.c');
      expect(draft.problems.keys, [ClientDataField.email]);
    });

    test('rebases this edit over what another saved', () {
      final draft = ClientDataDraft(_record(phone: '+56 9 8121 0019'))
        ..set(ClientDataField.phone, '+56 9 1111 2222')
        ..set(ClientDataField.address, 'Av. Matta 123');
      final newer = _record(
        phone: '+56 9 3333 4444',
        email: 'otro@correo.cl',
        token: '2026-10-03T12:05:00.000001+00:00',
      );

      final next = draft.rebasedOn(newer);
      expect(next.record.updatedAtToken, newer.updatedAtToken);
      // Lo que esta edición no tocó toma lo nuevo.
      expect(next.value(ClientDataField.email), 'otro@correo.cl');
      expect(next.isChanged(ClientDataField.email), isFalse);
      // Lo que sí tocó queda, y se marca si otro también lo cambió.
      expect(next.value(ClientDataField.phone), '+56 9 1111 2222');
      expect(next.value(ClientDataField.address), 'Av. Matta 123');
      expect(next.changedByOthers, {ClientDataField.phone});
      expect(next.changes.keys, containsAll(['phone', 'address']));
    });
  });
}

ClientRecord _greeted({String? style, String? custom}) => ClientRecord.fromRow({
      'id': 'customer-2',
      'tenant_id': 'tenant-1',
      'name': 'María José Lara',
      'greeting_style': style,
      'greeting_custom_name': custom,
      'is_active': true,
      'created_at': '2025-11-13T15:20:31.000000+00:00',
      'updated_at': '2026-11-21T12:00:00.000000+00:00',
    });
