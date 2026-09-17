import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_engine.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_index.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_query.dart';

/// Un archivo que llegó por WhatsApp es un resultado como cualquier otro.
///
/// La forma de las filas está copiada de producción (`messaging_attachments`
/// con el embed de `conversations`, leída el 2026-09-17): el proveedor mandó el
/// catálogo de pedales por WhatsApp y encontrarlo no puede costar entrar al
/// módulo de mensajería y bajar por el hilo.
void main() {
  Map<String, dynamic> row({
    String? storagePath = 'tenant/chat/pedales.pdf',
    String? fileName = 'PEDALES GINEYEA JUN 26.pdf',
    String? extension = 'pdf',
    String? mimeType = 'application/pdf',
    Map<String, dynamic>? conversation = const <String, dynamic>{
      'title': 'TeknoBike',
      'counterparty_type': 'supplier',
      'channel': 'whatsapp',
      'whatsapp_conversation_bindings': <Map<String, dynamic>>[
        <String, dynamic>{
          'contact_name': 'Diego',
          'supplier_contacts': <String, dynamic>{'name': 'Diego Muñoz'},
        },
      ],
    },
  }) =>
      <String, dynamic>{
        'id': 'a1',
        'conversation_id': 'c1',
        'storage_path': storagePath,
        'original_filename': fileName,
        'extension': extension,
        'declared_mime_type': mimeType,
        'attached_at': '2026-09-17T12:00:00Z',
        'conversations': conversation,
      };

  test('el resultado nombra la conversación entera, no sólo la empresa', () {
    // «TeknoBike» dice de qué proveedor vino; a quien uno le pidió el catálogo
    // es a Diego, y así se lee el encabezado del chat.
    final entry = globalSearchAttachmentEntry(row())!;
    expect(entry.kind, GlobalSearchKind.attachment);
    expect(entry.title, 'PEDALES GINEYEA JUN 26.pdf');
    expect(entry.subtitle, startsWith('TeknoBike · Diego Muñoz · WhatsApp'));
    expect(entry.attachment!.origin, 'TeknoBike · Diego Muñoz · WhatsApp');
  });

  test('«diego» trae lo que Diego mandó', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('diego'),
      entries: <GlobalSearchEntry>[globalSearchAttachmentEntry(row())!],
    );
    expect(outcome.flattened.single.entry.id, 'attachment:a1');
  });

  test('pero el archivo no se LLAMA Diego: viene de Diego', () {
    // La distinción decide el orden: un catálogo no compite de igual a igual
    // con las personas que sí se llaman así.
    final entry = globalSearchAttachmentEntry(row())!;
    expect(entry.titleWords, isNot(contains('diego')));
    expect(entry.haystack, contains('diego'));
  });

  test('el adjunto trae lo justo para abrir el visor sin el módulo de chat',
      () {
    final attachment = globalSearchAttachmentEntry(row())!.attachment!;
    expect(attachment.storagePath, 'tenant/chat/pedales.pdf');
    expect(attachment.contentType, 'application/pdf');
    expect(attachment.extension, 'pdf');
    expect(attachment.isImage, isFalse);
  });

  test('una foto se reconoce como imagen aunque la columna venga vacía', () {
    final attachment = globalSearchAttachmentEntry(
      row(fileName: 'Llegada.JPG', extension: null, mimeType: null),
    )!
        .attachment!;
    expect(attachment.extension, 'jpg');
    expect(attachment.isImage, isTrue);
    // Sin tipo declarado se abre igual: el visor lo resuelve por la extensión.
    expect(attachment.contentType, 'application/octet-stream');
  });

  test('una fila que no se puede abrir no es un resultado', () {
    expect(globalSearchAttachmentEntry(row(storagePath: null)), isNull);
    expect(globalSearchAttachmentEntry(row(fileName: null)), isNull);
  });

  test('sin conversación sigue siendo abrible, con una pista honesta', () {
    final entry = globalSearchAttachmentEntry(row(conversation: null))!;
    expect(entry.attachment!.origin, 'Conversación');
    expect(entry.subtitle, isNot(contains('·')));
  });

  test('«pedales» encuentra el catálogo que mandó el proveedor', () {
    final entries = <GlobalSearchEntry>[
      globalSearchAttachmentEntry(row())!,
      GlobalSearchEntry(
        kind: GlobalSearchKind.menu,
        id: 'menu:/chat',
        title: 'Mensajería',
        route: '/chat',
      ),
    ];

    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('pedales'),
      entries: entries,
    );

    expect(outcome.flattened.first.entry.id, 'attachment:a1');
    expect(
      outcome.groups.first.kind.groupTitle,
      'Archivos recibidos',
    );
  });

  test('el nombre del proveedor también trae sus archivos', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('teknobike'),
      entries: <GlobalSearchEntry>[globalSearchAttachmentEntry(row())!],
    );
    expect(outcome.flattened.single.entry.id, 'attachment:a1');
  });
}
