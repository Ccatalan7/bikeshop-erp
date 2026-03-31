import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

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
}
