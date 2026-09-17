import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_engine.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_index.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_query.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';

/// Un hilo se pide por la empresa **y** por la persona.
///
/// Las filas replican producción (2026-09-17): el chat de WhatsApp se titula
/// «TeknoBike» y el vendedor con el que se habla es Diego Muñoz, que sólo
/// aparece en el vínculo y en la ficha del contacto.
void main() {
  Map<String, dynamic> row({
    String? title = 'TeknoBike',
    String? channel = 'whatsapp',
    String? bindingName = 'Diego',
    String? contactName = 'Diego Muñoz',
    String? phone = '56977014463',
    String counterparty = 'supplier',
  }) =>
      <String, dynamic>{
        'id': 'c1',
        'title': title,
        'type': 'support',
        'channel': channel,
        'counterparty_type': counterparty,
        'status': 'active',
        'last_message_at': '2026-09-17T18:27:36Z',
        'whatsapp_conversation_bindings': <Map<String, dynamic>>[
          <String, dynamic>{
            'contact_name': bindingName,
            'external_phone_number': phone,
            'supplier_contacts': contactName == null
                ? null
                : <String, dynamic>{'name': contactName, 'role': 'Ventas'},
          },
        ],
      };

  test('«diego» encuentra el chat que se titula TeknoBike', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('diego'),
      entries: <GlobalSearchEntry>[globalSearchConversationEntry(row())!],
    );
    expect(outcome.flattened.single.entry.id, 'conversation:c1');
    expect(outcome.groups.single.kind.groupTitle, 'Conversaciones');
  });

  test('la persona es un nombre del hilo, no sólo texto que contiene', () {
    // Si fuera texto suelto no ganaría el bono de nombrar; acá «diego» nombra
    // este hilo tanto como lo nombra «teknobike».
    final entry = globalSearchConversationEntry(row())!;
    expect(entry.titleWords, containsAll(<String>['teknobike', 'diego']));
  });

  test('el nombre de la ficha manda sobre el perfil de WhatsApp', () {
    final entry = globalSearchConversationEntry(row())!;
    expect(entry.subtitle, startsWith('Diego Muñoz · WhatsApp'));
    // Y el perfil sigue encontrándose, porque comparten la primera palabra.
    expect(entry.titleWords, contains('diego'));
  });

  test('sin ficha del proveedor queda el nombre del perfil', () {
    final entry = globalSearchConversationEntry(row(contactName: null))!;
    expect(entry.subtitle, startsWith('Diego · WhatsApp'));
  });

  test('«teknobike» sigue encontrando su propio hilo', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('teknobike'),
      entries: <GlobalSearchEntry>[globalSearchConversationEntry(row())!],
    );
    expect(outcome.flattened.single.entry.id, 'conversation:c1');
  });

  test('el teléfono también abre el hilo, escrito de dos maneras', () {
    for (final typed in <String>['56977014463', '+56 9 7701 4463']) {
      final outcome = rankGlobalSearch(
        query: GlobalSearchQuery.parse(typed),
        entries: <GlobalSearchEntry>[globalSearchConversationEntry(row())!],
      );
      expect(outcome.flattened, isNotEmpty, reason: 'con «$typed»');
    }
  });

  test('abre el hilo en la bandeja del rail, no el módulo completo', () {
    // El dueño casi no usa el módulo: contesta desde el panel del rail. Un
    // resultado tiene que dejarlo donde él contesta, y ya en el hilo.
    final entry = globalSearchConversationEntry(row())!;
    expect(entry.conversationId, 'c1');
    expect(entry.toolbarTool, ToolbarTool.supplierMessages);
    expect(entry.route, '/chat?conversation=c1');
  });

  test('un hilo de cliente abre la bandeja de clientes', () {
    final entry = globalSearchConversationEntry(row(counterparty: 'customer'))!;
    expect(entry.toolbarTool, ToolbarTool.messages);
  });

  test('un hilo sin persona no repite el título en la segunda línea', () {
    final entry = globalSearchConversationEntry(
      row(title: 'Victor Calfual', bindingName: 'Victor Calfual',
          contactName: null),
    )!;
    expect(entry.title, 'Victor Calfual');
    expect(entry.subtitle, startsWith('WhatsApp'));
  });

  test('un hilo interno se nombra por su canal cuando no tiene título', () {
    final entry = globalSearchConversationEntry(
      row(title: null, channel: 'internal', bindingName: null,
          contactName: null, phone: null, counterparty: 'internal'),
    )!;
    expect(entry.title, 'Conversación · Interno');
  });

  test('una fila sin id no es un resultado', () {
    final broken = row()..remove('id');
    expect(globalSearchConversationEntry(broken), isNull);
  });
}
