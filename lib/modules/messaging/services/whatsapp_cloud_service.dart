import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../../shared/services/supabase_functions_region.dart';

class WhatsAppCloudService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> sendTextMessage({
    required String phoneNumber,
    required String text,
    String? conversationId,
    String? customerId,
    String? contextType,
    String? contextId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'whatsapp-send',
        headers: kSupabaseFunctionsRegionHeaders,
        body: {
          'type': 'text',
          'text': text,
          'phoneNumber': phoneNumber,
          if (conversationId != null) 'conversationId': conversationId,
          if (customerId != null) 'customerId': customerId,
          if (contextType != null) 'contextType': contextType,
          if (contextId != null) 'contextId': contextId,
        },
      );

      if (response.status >= 300) {
        throw Exception('Failed to send WhatsApp message: ${response.status}');
      }
    } catch (e) {
      debugPrint('WhatsApp send error: $e');
      rethrow;
    }
  }

  /// Manda una reacción al contacto y la guarda contra el mensaje anotado.
  ///
  /// Un [emoji] vacío la retira: así lo expresa WhatsApp, y así lo entiende la
  /// función de envío, que borra la fila en vez de insertarla.
  ///
  /// La escritura la hace la función y no el cliente a propósito: si Meta
  /// rechaza la reacción, no debe quedar guardada una que el proveedor nunca
  /// vio.
  Future<void> sendReaction({
    required String phoneNumber,
    required String conversationId,
    required String messageId,
    required String externalMessageId,
    required String emoji,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'whatsapp-send',
        headers: kSupabaseFunctionsRegionHeaders,
        body: {
          'type': 'reaction',
          'phoneNumber': phoneNumber,
          'conversationId': conversationId,
          'reactionToMessageId': messageId,
          'reactionConversationId': conversationId,
          'reactionToExternalMessageId': externalMessageId,
          'reactionEmoji': emoji,
        },
      );

      if (response.status >= 300) {
        throw Exception('Failed to send WhatsApp reaction: ${response.status}');
      }
    } catch (e) {
      debugPrint('WhatsApp reaction error: $e');
      rethrow;
    }
  }
}
