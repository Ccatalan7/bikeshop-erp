import '../models/conversation.dart';

/// «Crear cotización» desde un chat (2026-11-03): la «Cotización» de Trabajos,
/// su dueño, que la bandeja de Ventas › Cotizaciones lista junto a las del
/// sitio. Lleva ya elegido al cliente que escribe —el de su contacto—; si el
/// contacto no tiene ficha, el cliente vinculado a la conversación. Un chat
/// ligado al trabajo de otra persona (un papá que escribe por la bici del
/// hijo) cotiza para quien pregunta.
String newQuoteRouteForConversation(
  Conversation conversation, {
  String? contactCustomerId,
}) {
  final customerId = [
    contactCustomerId,
    conversation.contextHint?.customerId,
  ].map((id) => id?.trim() ?? '').firstWhere(
        (id) => id.isNotEmpty,
        orElse: () => '',
      );
  return Uri(
    path: '/taller/pegas/nueva',
    queryParameters: {
      'type': 'quotation',
      if (customerId.isNotEmpty) 'customer_id': customerId,
    },
  ).toString();
}

/// Sólo una conversación con un cliente: no la de un proveedor, del equipo ni
/// el hilo de una tarea.
bool canCreateQuoteFromConversation(Conversation conversation) =>
    conversation.isCustomerConversation &&
    !conversation.isSupplierConversation &&
    !conversation.isTaskThread;
