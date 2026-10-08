import '../models/conversation.dart';
import '../models/message.dart';

/// Whether [message] was written by Viñabike — by anyone on the team — and
/// not by the customer or supplier on the other end of the conversation.
///
/// **Por qué (dueño, 2026-10-08).** «Todos los trabajadores deberíamos ser
/// Viñabike - (nombre del usuario) y todos ir con nuestros mensajes a la
/// derecha». La burbuja se decidía con `sender_id == yo`: lo que escribía un
/// compañero —o el mismo dueño desde otra cuenta— caía a la izquierda con su
/// nombre, sin checks, como un chat de grupo. Con un cliente o un proveedor
/// hay dos lados, Viñabike y el contacto; un chat interno sigue siendo de
/// personas.
bool isWrittenByBusiness(
  Message message,
  Conversation conversation, {
  bool Function(String userId)? isStaffUser,
}) {
  if (message.isMe) return true;
  if (!conversation.isSupport) return false;
  if (message.type == 'system') return false;
  final direction = message.metadata['message_direction']?.toString();
  if (direction == 'outbound') return true;
  if (direction == 'inbound') return false;
  // El portal web no marca dirección: quien escribe es un miembro del equipo
  // o el cliente con su propia cuenta.
  final senderId = message.senderId;
  if (senderId == null || senderId.isEmpty) return false;
  return isStaffUser?.call(senderId) ?? false;
}

/// How a teammate's message is signed inside the chat: «Viñabike · Diego».
String businessAuthorLabel(String? displayName) {
  final name = displayName?.trim() ?? '';
  if (name.isEmpty) return 'Viñabike';
  final first = name.split(RegExp(r'\s+')).first;
  return 'Viñabike · $first';
}
