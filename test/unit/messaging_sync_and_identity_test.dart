import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/models/message_delivery_state.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/utils/message_side.dart';
import 'package:vinabike_erp/shared/services/notification_service.dart';
import 'package:vinabike_erp/shared/services/whatsapp_pending_send_store.dart';

/// WhatsApp del ERP, 2026-10-08: el dueño pidió que todo el equipo sea
/// «Viñabike · nombre» con sus mensajes a la derecha, que un mensaje pendiente
/// no se pierda en el teléfono y que las notificaciones digan lo que llegó.
void main() {
  final supplierChat = Conversation(
    id: 'conv-supplier',
    type: 'support',
    channel: 'whatsapp',
    counterpartyType: 'supplier',
    updatedAt: DateTime(2026, 10, 8),
    participantIds: const [],
  );
  final portalChat = Conversation(
    id: 'conv-portal',
    type: 'support',
    channel: 'website_portal',
    updatedAt: DateTime(2026, 10, 8),
    participantIds: const [],
  );
  final teamChat = Conversation(
    id: 'conv-team',
    type: 'internal',
    channel: 'internal',
    updatedAt: DateTime(2026, 10, 8),
    participantIds: const [],
  );

  Message message({
    String? senderId,
    bool isMe = false,
    String? direction,
    String type = 'text',
    String conversationId = 'conv-supplier',
  }) =>
      Message(
        id: 'm-${senderId ?? 'contact'}-$direction-$isMe',
        conversationId: conversationId,
        senderId: senderId,
        content: 'Hola',
        type: type,
        metadata: {
          if (direction != null) 'message_direction': direction,
        },
        createdAt: DateTime(2026, 10, 8, 10, 28),
        isMe: isMe,
      );

  bool staff(String id) => id == 'staff-diego' || id == 'staff-claudio';

  group('Viñabike es un solo lado del chat', () {
    test('lo mío y lo de un compañero van del lado de Viñabike', () {
      expect(
        isWrittenByBusiness(
          message(senderId: 'staff-claudio', isMe: true),
          supplierChat,
        ),
        isTrue,
      );
      expect(
        isWrittenByBusiness(
          message(senderId: 'staff-diego', direction: 'outbound'),
          supplierChat,
          isStaffUser: staff,
        ),
        isTrue,
        reason: 'antes caía a la izquierda, como un chat de grupo',
      );
    });

    test('lo que escribe el proveedor es del otro lado', () {
      expect(
        isWrittenByBusiness(message(direction: 'inbound'), supplierChat),
        isFalse,
      );
      expect(isWrittenByBusiness(message(), supplierChat), isFalse);
    });

    test('en el portal decide si quien escribe es del equipo', () {
      expect(
        isWrittenByBusiness(
          message(senderId: 'staff-diego', conversationId: 'conv-portal'),
          portalChat,
          isStaffUser: staff,
        ),
        isTrue,
      );
      expect(
        isWrittenByBusiness(
          message(senderId: 'customer-auth', conversationId: 'conv-portal'),
          portalChat,
          isStaffUser: staff,
        ),
        isFalse,
      );
    });

    test('un chat interno sigue siendo de personas', () {
      expect(
        isWrittenByBusiness(
          message(senderId: 'staff-diego', conversationId: 'conv-team'),
          teamChat,
          isStaffUser: staff,
        ),
        isFalse,
      );
    });

    test('un mensaje de sistema no es de nadie', () {
      expect(
        isWrittenByBusiness(
          message(direction: 'outbound', type: 'system'),
          supplierChat,
        ),
        isFalse,
      );
    });

    test('la firma usa el nombre de pila', () {
      expect(businessAuthorLabel('Diego Muñoz Pérez'), 'Viñabike · Diego');
      expect(businessAuthorLabel(null), 'Viñabike');
      expect(businessAuthorLabel('  '), 'Viñabike');
    });
  });

  group('Realtime', () {
    test('una caída de red no cambia de transporte; un rechazo sí', () {
      expect(
        isRefusedRealtimeJoin(const RealtimeCloseEvent(code: 1006, reason: '')),
        isFalse,
        reason: 'el cierre 1006 es el socket, no una política',
      );
      expect(isRefusedRealtimeJoin(null), isFalse);
      expect(isRefusedRealtimeJoin(Exception('timeout')), isFalse);
      expect(
        isRefusedRealtimeJoin(
          Exception('Unauthorized: You do not have permissions to read '
              'from this Channel topic'),
        ),
        isTrue,
      );
    });
  });

  group('Notificaciones', () {
    test('una foto con texto dice el texto', () {
      expect(
        notificationBodyForMessage({
          'type': 'image',
          'content': 'confírmame si es eso entonces',
          'metadata': const {},
        }),
        '📷 confírmame si es eso entonces',
      );
      expect(
        notificationBodyForMessage({
          'type': 'image',
          'content': 'Imagen enviada',
        }),
        '📷 Foto',
      );
      expect(
        notificationBodyForMessage({
          'type': 'file',
          'content': 'Archivo adjunto',
          'metadata': {'filename': 'Pedido - 298454.pdf'},
        }),
        '📄 Pedido - 298454.pdf',
      );
      expect(
        notificationBodyForMessage({'type': 'text', 'content': ' a  ok '}),
        'a ok',
      );
    });

    test('una lectura anterior no borra el aviso de un mensaje posterior',
        () async {
      SharedPreferences.setMockInitialValues({});
      // Leído hasta 10; entra el 11 y se avisa; la señal llega después.
      await rememberAlertedMessageSequence({
        'conversation_id': 'conv-supplier',
        'message_sequence': '11',
      });
      expect(
        await readSignalCoversAlerts({
          'kind': 'conversation_read',
          'read_conversation_id': 'conv-supplier',
          'read_through_sequence': '10',
        }),
        isFalse,
        reason: 'el 11 sigue sin leer: su aviso se queda',
      );
      expect(
        await readSignalCoversAlerts({
          'kind': 'conversation_read',
          'read_conversation_id': 'conv-supplier',
          'read_through_sequence': '11',
        }),
        isTrue,
        reason: 'leído hasta el 11: el aviso sale',
      );
      expect(
        await readSignalCoversAlerts({
          'kind': 'conversation_read',
          'read_conversation_id': 'conv-other',
          'read_through_sequence': '3',
        }),
        isTrue,
        reason: 'sin avisos registrados, la señal manda',
      );
    });

    test('la marca del aviso gana a una señal que llega al mismo tiempo',
        () async {
      SharedPreferences.setMockInitialValues({});
      final results = await Future.wait([
        rememberAlertedMessageSequence({
          'conversation_id': 'conv-race',
          'message_sequence': '11',
        }).then((_) => true),
        readSignalCoversAlerts({
          'kind': 'conversation_read',
          'read_conversation_id': 'conv-race',
          'read_through_sequence': '10',
        }),
      ]);
      expect(results.last, isFalse);
    });

    test('la señal de leído nombra la conversación', () {
      expect(
        conversationReadSignalId({
          'kind': 'conversation_read',
          'read_conversation_id': 'conv-supplier',
        }),
        'conv-supplier',
      );
      expect(
        conversationReadSignalId({
          'kind': 'conversation_read',
          'conversation_id': 'conv-supplier',
        }),
        isNull,
        reason: 'con conversation_id la app publicada la anunciaba como '
            'mensaje nuevo; la señal usa read_conversation_id',
      );
    });
  });

  group('Un mensaje fallido dice por qué', () {
    test('131026: el número no tiene WhatsApp', () {
      final state = MessageDeliveryState.fromValues(
        metadata: const {
          'whatsapp_status_payload': {
            'errors': [
              {'code': 131026, 'title': 'Message undeliverable'},
            ],
          },
        },
        explicitStatus: 'failed',
        isExternalTransport: true,
        providerLabel: 'WhatsApp',
      );
      expect(state.stage, MessageDeliveryStage.failed);
      expect(state.failureMessage, contains('no tiene WhatsApp'));
    });

    test('un código desconocido conserva el detalle de Meta', () {
      final state = MessageDeliveryState.fromValues(
        metadata: const {
          'whatsapp_status_payload': {
            'errors': [
              {
                'code': 999999,
                'message': 'Algo raro',
                'error_data': {'details': 'Detalle de Meta'},
              },
            ],
          },
        },
        explicitStatus: 'failed',
        isExternalTransport: true,
        providerLabel: 'WhatsApp',
      );
      expect(state.failureMessage, contains('Detalle de Meta'));
    });
  });

  group('Un envío que no llegó al servidor no se pierde', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    PendingWhatsAppSend send(
      String id, {
      String userId = 'staff-claudio',
      String tenantId = 'tenant-a',
      DateTime? savedAt,
    }) =>
        PendingWhatsAppSend(
          clientMessageId: id,
          userId: userId,
          tenantId: tenantId,
          body: {
            'conversationId': 'conv-supplier',
            'message': 'quedo atento al monto',
            'metadata': {'client_message_id': id},
          },
          savedAt: savedAt ?? DateTime(2026, 10, 8, 10, 27),
        );

    test('se guarda hasta que la base contesta', () async {
      final store = WhatsAppPendingSendStore.instance;
      await store.remember(send('temp-wa-1'));
      final pending = await store.pendingFor(
        userId: 'staff-claudio',
        tenantId: 'tenant-a',
        now: DateTime(2026, 10, 8, 11),
      );
      expect(pending.map((s) => s.clientMessageId), ['temp-wa-1']);
      expect(pending.single.text, 'quedo atento al monto');
      expect(pending.single.conversationId, 'conv-supplier');

      await store.forget('temp-wa-1');
      expect(
        await store.pendingFor(
          userId: 'staff-claudio',
          tenantId: 'tenant-a',
          now: DateTime(2026, 10, 8, 11),
        ),
        isEmpty,
      );
    });

    test('dos envíos a la vez quedan los dos guardados', () async {
      final store = WhatsAppPendingSendStore.instance;
      await Future.wait([
        store.remember(send('temp-wa-a')),
        store.remember(send('temp-wa-b')),
      ]);
      final pending = await store.pendingFor(
        userId: 'staff-claudio',
        tenantId: 'tenant-a',
        now: DateTime(2026, 10, 8, 11),
      );
      expect(
        pending.map((s) => s.clientMessageId).toSet(),
        {'temp-wa-a', 'temp-wa-b'},
        reason: 'antes el segundo pisaba al primero',
      );
      await store.forget('temp-wa-a');
      await store.forget('temp-wa-b');
    });

    test('nunca se repite con otra persona ni otro taller', () async {
      final store = WhatsAppPendingSendStore.instance;
      await store.remember(send('temp-wa-2', userId: 'staff-diego'));
      await store.remember(send('temp-wa-3', tenantId: 'tenant-b'));
      expect(
        await store.pendingFor(
          userId: 'staff-claudio',
          tenantId: 'tenant-a',
          now: DateTime(2026, 10, 8, 11),
        ),
        isEmpty,
      );
    });

    test('lo muy viejo se descarta en vez de sorprender a un cliente',
        () async {
      final store = WhatsAppPendingSendStore.instance;
      await store.remember(send('temp-wa-4'));
      expect(
        await store.pendingFor(
          userId: 'staff-claudio',
          tenantId: 'tenant-a',
          now: DateTime(2026, 10, 9, 12),
        ),
        isEmpty,
      );
    });
  });
}
