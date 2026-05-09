import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
// For VoidCallback

class MessagingService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Get current user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  String _normalizeWhatsAppPhone(String phone) {
    var cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleaned.startsWith('56') && cleaned.length > 9) {
      cleaned = cleaned.substring(2);
    }

    if (!cleaned.startsWith('9')) {
      cleaned = '9$cleaned';
    }

    return '56$cleaned';
  }

  String? _normalizeConversationContextType(String? contextType) {
    final normalized = contextType?.trim().toLowerCase().replaceAll('-', '_');
    if (normalized == null || normalized.isEmpty) return null;

    return switch (normalized) {
      'online_order' || 'website_order' || 'web_order' => 'order',
      'job' ||
      'invoice' ||
      'bike' ||
      'product' ||
      'order' ||
      'customer' =>
        normalized,
      _ => throw Exception('Tipo de contexto no permitido: $contextType'),
    };
  }

  bool _isDuplicateParticipantError(Object error) {
    return error is PostgrestException && error.code == '23505';
  }

  Future<void> _addCurrentUserAsParticipant({
    required String conversationId,
    required String userId,
    String? tenantId,
    String role = 'member',
  }) async {
    try {
      final data = {
        'conversation_id': conversationId,
        'user_id': userId,
        'role': role,
        if (tenantId != null) 'tenant_id': tenantId,
      };
      await _client.from('conversation_participants').insert(data);
    } catch (error) {
      if (!_isDuplicateParticipantError(error)) rethrow;
    }
  }

  Future<void> _setPrimaryConversationContext({
    required String conversationId,
    required String contextType,
    required String contextId,
    required String userId,
    String? tenantId,
  }) async {
    await _client
        .from('conversation_contexts')
        .update({'is_primary': false}).eq('conversation_id', conversationId);

    await _client.from('conversation_contexts').upsert(
      {
        'conversation_id': conversationId,
        'context_type': contextType,
        'context_id': contextId,
        'is_primary': true,
        'added_by': userId,
        if (tenantId != null) 'tenant_id': tenantId,
      },
      onConflict: 'conversation_id,context_type,context_id',
    );
  }

  Future<void> _clearConversationContexts(String conversationId) async {
    await _client
        .from('conversation_contexts')
        .delete()
        .eq('conversation_id', conversationId);
  }

  Future<Set<String>> getConversationIdsForContext({
    required String contextType,
    required String contextId,
  }) async {
    final normalizedContextType = _normalizeConversationContextType(
      contextType,
    );
    if (normalizedContextType == null || contextId.isEmpty) return {};

    final activeRows = await _client
        .from('conversations')
        .select('id')
        .eq('context_type', normalizedContextType)
        .eq('context_id', contextId);

    final contextRows = await _client
        .from('conversation_contexts')
        .select('conversation_id')
        .eq('context_type', normalizedContextType)
        .eq('context_id', contextId);

    return {
      for (final row in activeRows) row['id']?.toString(),
      for (final row in contextRows) row['conversation_id']?.toString(),
    }.whereType<String>().toSet();
  }

  /// Fetch conversations for the current user with unread counts
  /// [type] filter: 'internal' or 'support'
  Future<List<Conversation>> getConversations({String? type}) async {
    final userId = currentUserId;
    if (userId == null) return [];

    List<dynamic> data = [];

    if (type == 'support') {
      // For support chats: show ALL support conversations (shared inbox)
      final response = await _client
          .from('conversations')
          .select(
              '*, conversation_participants(user_id), conversation_contexts(*)')
          .eq('type', 'support')
          .order('last_message_at', ascending: false);
      data = response as List<dynamic>;
      debugPrint('📬 Support chats loaded: ${data.length}');
    } else if (type == 'internal') {
      // For internal chats: only show ones where user is a participant
      final response = await _client
          .from('conversations')
          .select(
              '*, conversation_participants!inner(user_id), conversation_contexts(*)')
          .eq('type', 'internal')
          .order('last_message_at', ascending: false);
      data = response as List<dynamic>;
      debugPrint('💬 Internal chats loaded: ${data.length}');
    } else {
      // No filter: get both internal (participated) and support (all)
      final internalResponse = await _client
          .from('conversations')
          .select(
              '*, conversation_participants!inner(user_id), conversation_contexts(*)')
          .eq('type', 'internal')
          .order('last_message_at', ascending: false);

      final supportResponse = await _client
          .from('conversations')
          .select(
              '*, conversation_participants(user_id), conversation_contexts(*)')
          .eq('type', 'support')
          .order('last_message_at', ascending: false);

      debugPrint('💬 Internal chats: ${(internalResponse as List).length}');
      debugPrint('📬 Support chats: ${(supportResponse as List).length}');

      data = [...(internalResponse as List), ...(supportResponse as List)];
      // Sort by last_message_at
      data.sort((a, b) {
        final aTime = a['last_message_at'] ?? a['updated_at'];
        final bTime = b['last_message_at'] ?? b['updated_at'];
        return bTime.compareTo(aTime);
      });
      debugPrint('📊 Total conversations: ${data.length}');
    }

    // Fetch unread counts for current user
    final unreadResponse = await _client
        .from('conversation_unread_counts')
        .select('conversation_id, unread_count')
        .eq('user_id', userId);

    final Map<String, int> unreadMap = {};
    for (var row in unreadResponse) {
      unreadMap[row['conversation_id']] = row['unread_count'] ?? 0;
    }

    // Collect support conversation IDs and creator IDs to fetch customer names
    // and WhatsApp contact names in batch.
    final Set<String> supportConversationIds = {};
    final Set<String> creatorIds = {};
    for (var json in data) {
      final createdBy = json['created_by'];
      if (createdBy != null && json['type'] == 'support') {
        creatorIds.add(createdBy);
      }
      if (json['type'] == 'support' && json['id'] != null) {
        supportConversationIds.add(json['id'].toString());
      }
    }

    final Map<String, String> whatsappContactNames = {};
    if (supportConversationIds.isNotEmpty) {
      try {
        final bindings = await _client
            .from('whatsapp_conversation_bindings')
            .select('conversation_id, contact_name, external_phone_number')
            .inFilter('conversation_id', supportConversationIds.toList());

        for (final binding in bindings) {
          final conversationId = binding['conversation_id']?.toString();
          final contactName = binding['contact_name']?.toString().trim();
          final phone = binding['external_phone_number']?.toString().trim();
          if (conversationId == null) continue;
          if (contactName != null && contactName.isNotEmpty) {
            whatsappContactNames[conversationId] = contactName;
          } else if (phone != null && phone.isNotEmpty) {
            whatsappContactNames[conversationId] = phone;
          }
        }
      } catch (e) {
        debugPrint('Error fetching WhatsApp contact names: $e');
      }
    }

    // Fetch customer names for creators
    Map<String, String> customerNames = {};
    if (creatorIds.isNotEmpty) {
      try {
        final customersResponse = await _client
            .from('customers')
            .select('auth_user_id, name')
            .inFilter('auth_user_id', creatorIds.toList());
        for (var c in customersResponse) {
          if (c['auth_user_id'] != null && c['name'] != null) {
            customerNames[c['auth_user_id']] = c['name'];
          }
        }
      } catch (e) {
        debugPrint('Error fetching customer names: $e');
      }
    }

    return data.map((json) {
      // Inject unread count and creator name into json before parsing
      json['unread_count'] = unreadMap[json['id']] ?? 0;
      final conversationId = json['id']?.toString();
      final createdBy = json['created_by'];
      if (conversationId != null &&
          whatsappContactNames.containsKey(conversationId)) {
        json['creator_name'] = whatsappContactNames[conversationId];
      } else if (createdBy != null && customerNames.containsKey(createdBy)) {
        json['creator_name'] = customerNames[createdBy];
      }
      return Conversation.fromJson(json);
    }).toList();
  }

  /// Fetch all conversations linked to a specific customer (via conversation_contexts)
  Future<List<Conversation>> getConversationsForCustomer(
      String customerId) async {
    // Collect all conversation IDs related to this customer:
    // 1. Direct: context_type='customer', context_id=customerId
    // 2. Via their jobs: context_type='job', context_id IN customer's job IDs
    // 3. Via their invoices: context_type='invoice', context_id IN customer's invoice IDs

    // Fetch job IDs and invoice IDs for this customer in parallel, plus direct contexts
    final results = await Future.wait([
      // Direct customer contexts
      _client
          .from('conversation_contexts')
          .select('conversation_id')
          .eq('context_type', 'customer')
          .eq('context_id', customerId),
      // Job IDs for this customer
      _client.from('mechanic_jobs').select('id').eq('customer_id', customerId),
      // Invoice IDs for this customer
      _client.from('sales_invoices').select('id').eq('customer_id', customerId),
    ]);

    final Set<String> ids = {};

    // Add direct context conversation IDs
    for (var row in results[0] as List) {
      ids.add(row['conversation_id'] as String);
    }

    // Collect job IDs and invoice IDs
    final jobIds = (results[1] as List).map((r) => r['id'] as String).toList();
    final invoiceIds =
        (results[2] as List).map((r) => r['id'] as String).toList();

    // Fetch job-linked conversation IDs
    if (jobIds.isNotEmpty) {
      final jobContexts = await _client
          .from('conversation_contexts')
          .select('conversation_id')
          .eq('context_type', 'job')
          .inFilter('context_id', jobIds);
      for (var row in jobContexts as List) {
        ids.add(row['conversation_id'] as String);
      }
    }

    // Fetch invoice-linked conversation IDs
    if (invoiceIds.isNotEmpty) {
      final invoiceContexts = await _client
          .from('conversation_contexts')
          .select('conversation_id')
          .eq('context_type', 'invoice')
          .inFilter('context_id', invoiceIds);
      for (var row in invoiceContexts as List) {
        ids.add(row['conversation_id'] as String);
      }
    }

    if (ids.isEmpty) return [];

    final data = await _client
        .from('conversations')
        .select(
            '*, conversation_participants(user_id), conversation_contexts(*)')
        .inFilter('id', ids.toList())
        .order('last_message_at', ascending: false);

    // Inject unread counts
    final userId = currentUserId;
    Map<String, int> unreadMap = {};
    if (userId != null) {
      final unreadResponse = await _client
          .from('conversation_unread_counts')
          .select('conversation_id, unread_count')
          .eq('user_id', userId);
      for (var row in unreadResponse) {
        unreadMap[row['conversation_id']] = row['unread_count'] ?? 0;
      }
    }

    return (data as List).map((json) {
      json['unread_count'] = unreadMap[json['id']] ?? 0;
      return Conversation.fromJson(json);
    }).toList();
  }

  /// Mark a conversation as read for the current user
  Future<void> markAsRead(String conversationId) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _client.rpc('mark_conversation_read', params: {
      'p_conversation_id': conversationId,
    });
  }

  /// Build a portable, audit-friendly snapshot of one conversation.
  ///
  /// This complements tenant-level database backups with a focused chat export
  /// that staff can download directly from the conversation info panel.
  Future<Map<String, dynamic>> getConversationArchiveSnapshot(
    String conversationId,
  ) async {
    final conversation = await _client
        .from('conversations')
        .select()
        .eq('id', conversationId)
        .single();

    final results = await Future.wait<dynamic>([
      _client
          .from('conversation_participants')
          .select()
          .eq('conversation_id', conversationId),
      _client
          .from('conversation_contexts')
          .select()
          .eq('conversation_id', conversationId)
          .order('added_at', ascending: true),
      _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true),
      _client
          .from('whatsapp_conversation_bindings')
          .select()
          .eq('conversation_id', conversationId),
    ]);

    final participants = List<Map<String, dynamic>>.from(results[0] as List);
    final contexts = List<Map<String, dynamic>>.from(results[1] as List);
    final messages = List<Map<String, dynamic>>.from(results[2] as List);
    final whatsappBindings =
        List<Map<String, dynamic>>.from(results[3] as List);

    final channelIds = whatsappBindings
        .map((binding) => binding['channel_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    List<Map<String, dynamic>> whatsappChannels = [];
    if (channelIds.isNotEmpty) {
      final channels = await _client
          .from('whatsapp_channels')
          .select(
            'id, tenant_id, phone_number_id, business_account_id, display_name, display_phone_number, is_active, created_at, updated_at',
          )
          .inFilter('id', channelIds);
      whatsappChannels = List<Map<String, dynamic>>.from(channels as List);
    }

    final attachmentCount = messages.where((message) {
      final type = message['type']?.toString();
      final metadata = message['metadata'];
      return type == 'image' ||
          type == 'file' ||
          (metadata is Map &&
              ['url', 'media_url', 'documentUrl', 'document_url'].any(
                (key) => metadata.containsKey(key),
              ));
    }).length;
    final attachmentManifest = messages
        .map((message) {
          final metadata = message['metadata'];
          if (metadata is! Map) return null;
          final url = metadata['url'] ??
              metadata['media_url'] ??
              metadata['documentUrl'] ??
              metadata['document_url'] ??
              (message['type'] == 'image' || message['type'] == 'file'
                  ? message['content']
                  : null);
          if (url == null || url.toString().trim().isEmpty) return null;
          return <String, dynamic>{
            'message_id': message['id'],
            'created_at': message['created_at'],
            'type': message['type'],
            'url': url,
            'filename': metadata['filename'] ??
                metadata['documentFilename'] ??
                metadata['document_filename'],
            'content_type': metadata['contentType'] ?? metadata['content_type'],
            'size_bytes': metadata['sizeBytes'] ?? metadata['size_bytes'],
            'storage_bucket':
                metadata['storageBucket'] ?? metadata['storage_bucket'],
            'storage_path': metadata['storagePath'] ?? metadata['storage_path'],
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final externalMessageCount = messages
        .where((message) => message['external_provider'] != null)
        .length;

    return {
      'archive_version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'conversation_id': conversationId,
      'summary': {
        'message_count': messages.length,
        'participant_count': participants.length,
        'context_count': contexts.length,
        'attachment_reference_count': attachmentCount,
        'external_message_count': externalMessageCount,
      },
      'conversation': conversation,
      'participants': participants,
      'contexts': contexts,
      'messages': messages,
      'attachment_manifest': attachmentManifest,
      'whatsapp_bindings': whatsappBindings,
      'whatsapp_channels': whatsappChannels,
    };
  }

  /// Get messages stream for a specific conversation
  Stream<List<Message>> getMessagesStream(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((data) => data
            .map((json) => Message.fromJson(json, currentUserId: currentUserId))
            .toList());
  }

  /// Send a message
  Future<void> sendMessage({
    required String conversationId,
    required String content,
    String type = 'text',
    Map<String, dynamic>? metadata,
    List<String>? participantIds, // Optional: for push notifications
  }) async {
    if (currentUserId == null) throw Exception('Not authenticated');

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': currentUserId,
      'content': content,
      'type': type,
      'metadata': metadata ?? {},
    });
    // Trigger updates conversation timestamp automatically via DB trigger
  }

  /// Create or resolve a WhatsApp-backed support conversation without sending.
  ///
  /// This is the handoff point for ERP actions that need to contact a customer
  /// through our internal inbox. Transport still happens later from ChatWindow.
  Future<String> openWhatsAppSupportConversation({
    required String phoneNumber,
    required String contactName,
    String? customerId,
    String? contextType,
    String? contextId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    final tenantId = await TenantService().getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se pudo resolver el tenant del usuario');
    }

    final channel = await _client
        .from('whatsapp_channels')
        .select('id, phone_number_id')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (channel == null) {
      throw Exception('No hay un canal de WhatsApp activo para este tenant');
    }

    final normalizedPhone = _normalizeWhatsAppPhone(phoneNumber);
    final normalizedContextType =
        _normalizeConversationContextType(contextType);
    final result = await _client.rpc(
      'ensure_whatsapp_conversation_binding',
      params: {
        'p_tenant_id': tenantId,
        'p_channel_id': channel['id'],
        'p_wa_id': normalizedPhone,
        'p_phone_number': normalizedPhone,
        'p_contact_name': contactName,
        'p_customer_id': customerId,
        'p_context_type': normalizedContextType,
        'p_context_id': contextId,
      },
    );

    final data = Map<String, dynamic>.from(result as Map);
    final conversationId = data['conversation_id']?.toString();
    if (conversationId == null || conversationId.isEmpty) {
      throw Exception('No se pudo abrir la conversación de WhatsApp');
    }

    await _client.from('conversations').update({
      'channel': 'whatsapp',
      'status': 'active',
      'accepted_by': userId,
      'accepted_at': DateTime.now().toIso8601String(),
      if (normalizedContextType != null && contextId != null) ...{
        'context_type': normalizedContextType,
        'context_id': contextId,
      },
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);

    await _addCurrentUserAsParticipant(
      conversationId: conversationId,
      userId: userId,
      tenantId: tenantId,
      role: 'admin',
    );

    return conversationId;
  }

  /// Resolve the customer contact directly from a business context before a
  /// conversation exists. Used by embedded entity chat surfaces.
  Future<Map<String, dynamic>?> getSupportContextContact({
    required String contextType,
    required String contextId,
  }) async {
    try {
      Future<Map<String, dynamic>?> loadCustomerById(String? customerId) async {
        if (customerId == null || customerId.isEmpty) return null;

        final customer = await _client
            .from('customers')
            .select('id, name, phone')
            .eq('id', customerId)
            .limit(1)
            .maybeSingle();

        if (customer == null) return null;

        final phone = customer['phone']?.toString().trim();
        if (phone == null || phone.isEmpty) return null;

        return {
          'customer_id': customer['id']?.toString(),
          'name': customer['name']?.toString(),
          'phone': phone,
        };
      }

      final normalizedContextType = _normalizeConversationContextType(
        contextType,
      );

      if (normalizedContextType == 'customer') {
        return loadCustomerById(contextId);
      }

      if (normalizedContextType == 'job') {
        final job = await _client
            .from('mechanic_jobs')
            .select('customer_id')
            .eq('id', contextId)
            .limit(1)
            .maybeSingle();

        return loadCustomerById(job?['customer_id']?.toString());
      }

      if (normalizedContextType == 'invoice') {
        final invoice = await _client
            .from('sales_invoices')
            .select('customer_id, customer_name')
            .eq('id', contextId)
            .limit(1)
            .maybeSingle();

        final customerContact = await loadCustomerById(
          invoice?['customer_id']?.toString(),
        );
        if (customerContact == null) return null;

        final invoiceCustomerName = invoice?['customer_name']?.toString();
        if (invoiceCustomerName != null && invoiceCustomerName.isNotEmpty) {
          customerContact['name'] = invoiceCustomerName;
        }

        return customerContact;
      }

      if (normalizedContextType == 'order') {
        final order = await _client
            .from('online_orders')
            .select('customer_id, customer_name, customer_phone')
            .eq('id', contextId)
            .limit(1)
            .maybeSingle();

        if (order == null) return null;

        final orderPhone = order['customer_phone']?.toString().trim();
        if (orderPhone != null && orderPhone.isNotEmpty) {
          return {
            'customer_id': order['customer_id']?.toString(),
            'name': order['customer_name']?.toString(),
            'phone': orderPhone,
          };
        }

        return loadCustomerById(order['customer_id']?.toString());
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ Error resolving support context contact: $e');
      return null;
    }
  }

  /// Listen for ANY changes to the conversations table (for list re-fetch)
  RealtimeChannel subscribeToConversationsUpdates(VoidCallback onUpdate) {
    // We listen to the global 'conversations' table changes
    // Ideally, we would filter by 'participant', but Supabase Realtime filters are limited on joins.
    // So we listen to ALL 'conversations' changes, and the client will re-fetch.
    // Optimization: Listen to specific IDs if list is small, or just accept the overhead for now.
    // Better: Filter where 'id' is in the user's conversation list? Hard to maintain.
    // Simplest robust solution: Listen to 'conversations' table.
    return _client
        .channel('public:conversations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) {
            // Trigger update regardless of payload for simplicity,
            // the Provider will re-fetch the user's specific list.
            onUpdate();
          },
        )
        .subscribe();
  }

  /// Create a new "Support" conversation (for Customer Portal)
  Future<String> createSupportTicket({
    required String title,
    String? contextType,
    String? contextId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');
    final normalizedContextType = _normalizeConversationContextType(
      contextType,
    );

    // 1. Create Conversation
    final conversation = await _client
        .from('conversations')
        .insert({
          'type': 'support',
          'channel': 'website_portal',
          'title': title,
          'context_type': normalizedContextType,
          'context_id': contextId,
          'last_message_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final conversationId = conversation['id'];

    // 2. Add creator as participant
    await _client.from('conversation_participants').insert({
      'conversation_id': conversationId,
      'user_id': userId,
      'role': 'admin', // Creator is admin of the thread
    });

    if (normalizedContextType != null && contextId != null) {
      await _setPrimaryConversationContext(
        conversationId: conversationId,
        contextType: normalizedContextType,
        contextId: contextId,
        userId: userId,
      );
    }

    return conversationId;
  }

  /// Create or get existing "Internal" chat with another employee
  Future<String> createInternalChat(String otherUserId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    // First, try to find an existing 1:1 internal conversation between these two users
    // We need to find a conversation where:
    // - type = 'internal'
    // - both users are participants
    // - only these two users are participants (1:1 chat)

    try {
      // Get all internal conversations where current user is participant
      final myConversations = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', userId);

      // Get all internal conversations where other user is participant
      final otherConversations = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', otherUserId);

      // Find intersection
      final myIds = (myConversations as List)
          .map((c) => c['conversation_id'] as String)
          .toSet();
      final otherIds = (otherConversations as List)
          .map((c) => c['conversation_id'] as String)
          .toSet();
      final commonIds = myIds.intersection(otherIds);

      if (commonIds.isNotEmpty) {
        // Check if any of these are internal 1:1 chats
        for (final conversationId in commonIds) {
          final conversation = await _client
              .from('conversations')
              .select('id, type')
              .eq('id', conversationId)
              .eq('type', 'internal')
              .maybeSingle();

          if (conversation != null) {
            // Verify it's a 1:1 chat (only 2 participants)
            final participants = await _client
                .from('conversation_participants')
                .select('user_id')
                .eq('conversation_id', conversationId);

            if ((participants as List).length == 2) {
              // Found existing 1:1 chat, return it
              return conversationId;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking existing conversations: $e');
      // Continue to create new if check fails
    }

    // No existing chat found, create new one
    final conversation = await _client
        .from('conversations')
        .insert({
          'type': 'internal',
          'channel': 'internal',
          'last_message_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final conversationId = conversation['id'];

    // Add participants
    await _client.from('conversation_participants').insert([
      {
        'conversation_id': conversationId,
        'user_id': userId,
        'role': 'admin',
      },
      {
        'conversation_id': conversationId,
        'user_id': otherUserId,
        'role': 'member',
      }
    ]);

    return conversationId;
  }

  // ===========================================================================
  // GROUP & OUTBOUND CHAT METHODS
  // ===========================================================================

  /// Create a new internal group chat
  Future<String> createGroupChat({
    required List<String> participantIds,
    required String title,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    // Create conversation
    final conversation = await _client
        .from('conversations')
        .insert({
          'type': 'internal',
          'channel': 'internal',
          'title': title,
          'last_message_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final conversationId = conversation['id'] as String;

    // Add participants (Creator + others)
    final participants = [
      {'conversation_id': conversationId, 'user_id': userId, 'role': 'admin'},
      ...participantIds.map((pid) =>
          {'conversation_id': conversationId, 'user_id': pid, 'role': 'member'})
    ];

    await _client.from('conversation_participants').insert(participants);

    return conversationId;
  }

  /// Create a new support chat initiated by Employee (Outbound)
  Future<String> createOutboundSupportChat(
    String customerUserId, {
    String? contextType,
    String? contextId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    // Create conversation
    final conversation = await _client
        .from('conversations')
        .insert({
          'type': 'support',
          'channel': 'website_portal',
          'status': 'active', // Active immediately as staff initiated it
          'created_by': userId,
          'accepted_by': userId, // Auto-accepted
          'accepted_at': DateTime.now().toIso8601String(),
          'last_message_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final conversationId = conversation['id'] as String;

    // Add participants: Employee and Customer
    await _client.from('conversation_participants').insert([
      {'conversation_id': conversationId, 'user_id': userId, 'role': 'admin'},
      {
        'conversation_id': conversationId,
        'user_id': customerUserId,
        'role': 'member'
      }
    ]);

    // Add context if provided
    if (contextType != null && contextId != null) {
      await _client.from('conversation_contexts').insert({
        'conversation_id': conversationId,
        'context_type': contextType,
        'context_id': contextId,
        'is_primary': true,
        'added_by': userId,
      });
    }

    return conversationId;
  }

  /// Delete a conversation and all its messages
  /// Uses RPC function for proper permission handling
  Future<void> deleteConversation(String conversationId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    debugPrint('🗑️ Deleting conversation: $conversationId');

    try {
      await _client.rpc('delete_conversation', params: {
        'p_conversation_id': conversationId,
      });
      debugPrint('✅ Conversation deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting conversation: $e');
      rethrow;
    }
  }

  /// Update the context linking of a conversation
  /// Allows linking an existing chat to a Job, Invoice, etc.
  Future<void> updateConversationContext({
    required String conversationId,
    String? contextType,
    String? contextId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');
    final normalizedContextType = _normalizeConversationContextType(
      contextType,
    );

    debugPrint(
        '🔗 Linking conversation $conversationId to $normalizedContextType/$contextId');

    try {
      await _client.from('conversations').update({
        'context_type': normalizedContextType,
        'context_id': contextId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', conversationId);

      if (normalizedContextType != null && contextId != null) {
        await _setPrimaryConversationContext(
          conversationId: conversationId,
          contextType: normalizedContextType,
          contextId: contextId,
          userId: userId,
        );
      } else {
        await _clearConversationContexts(conversationId);
      }

      debugPrint('✅ Conversation context updated successfully');
    } catch (e) {
      debugPrint('❌ Error updating conversation context: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // CUSTOMER CHAT METHODS
  // ===========================================================================

  /// Create a chat request from customer portal
  /// The first message is the request itself - simple, frictionless
  Future<String> createChatRequest({
    required String initialMessage,
    String? contextType,
    String? contextId,
    required String tenantId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    // 1. Create conversation with 'pending' status
    final conversation = await _client
        .from('conversations')
        .insert({
          'type': 'support',
          'channel': 'website_portal',
          'status': 'pending',
          'context_type': contextType,
          'context_id': contextId,
          'tenant_id': tenantId,
          'created_by': userId, // Explicitly set for RLS
          'last_message_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final conversationId = conversation['id'] as String;

    // 2. Add customer as participant
    await _client.from('conversation_participants').insert({
      'conversation_id': conversationId,
      'user_id': userId,
      'role': 'admin', // Customer is admin of their own request
      'tenant_id': tenantId,
    });

    // 3. Add context if provided
    if (contextType != null && contextId != null) {
      await _client.from('conversation_contexts').insert({
        'conversation_id': conversationId,
        'context_type': contextType,
        'context_id': contextId,
        'is_primary': true,
        'added_by': userId,
        'tenant_id': tenantId,
      });
    }

    // 4. Send the initial message
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': userId,
      'content': initialMessage,
      'type': 'text',
      'tenant_id': tenantId,
    });

    debugPrint('✅ Created chat request: $conversationId');
    return conversationId;
  }

  /// Get conversations for a customer (supports filtering by status)
  Future<List<Map<String, dynamic>>> getCustomerConversations({
    String? status,
  }) async {
    final userId = currentUserId;
    if (userId == null) return [];

    // Build query dynamically
    dynamic query = _client.from('conversations').select('''
      *,
      conversation_participants!inner(user_id, role),
      messages(id, content, sender_id, created_at, type)
    ''').eq('type', 'support').eq('channel', 'website_portal');

    if (status != null) {
      query = query.eq('status', status);
    }

    final response = await query.order('last_message_at', ascending: false);
    final List<dynamic> data = response as List<dynamic>;

    // Filter to only include convos where current user is participant
    return data
        .where((conv) {
          final participants = conv['conversation_participants'] as List?;
          return participants?.any((p) => p['user_id'] == userId) ?? false;
        })
        .map((conv) => Map<String, dynamic>.from(conv))
        .toList();
  }

  /// Accept a chat request (for employees)
  Future<void> acceptChatRequest(String conversationId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    await _client.from('conversations').update({
      'status': 'active',
      'accepted_by': userId,
      'accepted_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);

    await _addCurrentUserAsParticipant(
      conversationId: conversationId,
      userId: userId,
    );

    debugPrint('✅ Accepted chat request: $conversationId');
  }

  /// Reject a chat request (for employees)
  Future<void> rejectChatRequest(String conversationId, String reason) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    await _client.from('conversations').update({
      'status': 'rejected',
      'reject_reason': reason,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);

    debugPrint('❌ Rejected chat request: $conversationId');
  }

  /// Resolve a chat (mark as completed)
  Future<void> resolveChat(String conversationId) async {
    await _client.from('conversations').update({
      'status': 'resolved',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);

    debugPrint('✅ Resolved chat: $conversationId');
  }

  /// Get pending chat requests (for employee inbox)
  Future<List<Map<String, dynamic>>> getPendingChatRequests() async {
    final response = await _client
        .from('conversations')
        .select('''
      *,
      conversation_participants(user_id, role),
      messages(id, content, sender_id, created_at, type),
      conversation_contexts(context_type, context_id, is_primary)
    ''')
        .eq('type', 'support')
        .eq('status', 'pending')
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Get sender info for a user ID (employee or customer)
  /// Get sender info for a user ID (employee or customer)
  Future<Map<String, dynamic>?> getSenderInfo(String senderId) async {
    try {
      // Use secure RPC to fetch public info without hitting table RLS
      final result = await _client.rpc('get_public_user_info', params: {
        'p_user_id': senderId,
      }).maybeSingle();

      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Error fetching sender info: $e');
      return null;
    }
  }

  /// Resolve the customer contact for a support conversation.
  ///
  /// Prefers an existing WhatsApp binding and falls back to the customer
  /// participant linked through `customers.auth_user_id`.
  Future<Map<String, dynamic>?> getSupportConversationContact(
    String conversationId,
  ) async {
    try {
      Future<Map<String, dynamic>?> loadCustomerById(String? customerId) async {
        if (customerId == null || customerId.isEmpty) {
          return null;
        }

        final customer = await _client
            .from('customers')
            .select('id, name, phone')
            .eq('id', customerId)
            .limit(1)
            .maybeSingle();

        if (customer == null) {
          return null;
        }

        final phone = customer['phone']?.toString();
        if (phone == null || phone.isEmpty) {
          return null;
        }

        return {
          'customer_id': customer['id']?.toString(),
          'name': customer['name']?.toString(),
          'phone': phone,
        };
      }

      Future<String?> loadLastFirstContactTemplateAt() async {
        final messages = await _client
            .from('messages')
            .select('created_at, metadata')
            .eq('conversation_id', conversationId)
            .eq('external_provider', 'whatsapp')
            .eq('message_direction', 'outbound')
            .order('created_at', ascending: false)
            .limit(20);

        for (final message in messages) {
          final metadata = message['metadata'];
          if (metadata is Map &&
              metadata['template_purpose'] == 'first_contact') {
            return message['created_at']?.toString();
          }
        }

        return null;
      }

      Future<String?> loadLastInboundMessageAt() async {
        final messages = await _client
            .from('messages')
            .select('created_at, sender_id, type, content, message_direction')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(50);

        for (final message in messages) {
          final direction = message['message_direction']?.toString();
          final senderId = message['sender_id']?.toString();
          final type = message['type']?.toString();
          final content = message['content']?.toString().trim() ?? '';
          final isInbound = direction == 'inbound' ||
              (senderId == null && type != 'system' && content.isNotEmpty);

          if (isInbound) {
            return message['created_at']?.toString();
          }
        }

        return null;
      }

      String? latestTimestamp(String? first, String? second) {
        if (first == null || first.isEmpty) return second;
        if (second == null || second.isEmpty) return first;

        final firstDate = DateTime.tryParse(first);
        final secondDate = DateTime.tryParse(second);
        if (firstDate == null) return second;
        if (secondDate == null) return first;

        return secondDate.toUtc().isAfter(firstDate.toUtc()) ? second : first;
      }

      final lastFirstContactTemplateAt = await loadLastFirstContactTemplateAt();
      final lastInboundMessageAt = await loadLastInboundMessageAt();

      final binding = await _client
          .from('whatsapp_conversation_bindings')
          .select(
            'customer_id, contact_name, external_phone_number, last_inbound_at, last_outbound_at',
          )
          .eq('conversation_id', conversationId)
          .limit(1)
          .maybeSingle();

      String? customerId = binding?['customer_id']?.toString();
      String? contactName = binding?['contact_name']?.toString();
      String? phoneNumber = binding?['external_phone_number']?.toString();
      final lastInboundAt = latestTimestamp(
        binding?['last_inbound_at']?.toString(),
        lastInboundMessageAt,
      );
      final lastOutboundAt = binding?['last_outbound_at']?.toString();

      if (customerId != null && customerId.isNotEmpty) {
        final customerContact = await loadCustomerById(customerId);
        if (customerContact != null) {
          contactName = customerContact['name']?.toString() ?? contactName;
          phoneNumber = customerContact['phone']?.toString() ?? phoneNumber;
        }
      }

      final conversation = await _client
          .from('conversations')
          .select(
              'id, context_type, context_id, conversation_contexts(context_type, context_id, is_primary)')
          .eq('id', conversationId)
          .limit(1)
          .maybeSingle();

      if (conversation != null) {
        String? contextType = conversation['context_type']?.toString();
        String? contextId = conversation['context_id']?.toString();

        final contexts = conversation['conversation_contexts'];
        if ((contextType == null || contextId == null) &&
            contexts is List &&
            contexts.isNotEmpty) {
          final primaryContext = contexts.firstWhere(
            (context) => context['is_primary'] == true,
            orElse: () => contexts.first,
          );
          contextType =
              primaryContext['context_type']?.toString() ?? contextType;
          contextId = primaryContext['context_id']?.toString() ?? contextId;
        }

        if (contextType == 'invoice' &&
            contextId != null &&
            contextId.isNotEmpty) {
          final invoice = await _client
              .from('sales_invoices')
              .select('customer_id, customer_name')
              .eq('id', contextId)
              .limit(1)
              .maybeSingle();

          customerId = invoice?['customer_id']?.toString();
          final customerContact = await loadCustomerById(customerId);
          if (customerContact != null) {
            contactName = customerContact['name']?.toString() ?? contactName;
            phoneNumber = customerContact['phone']?.toString() ?? phoneNumber;
          }

          final invoiceCustomerName = invoice?['customer_name']?.toString();
          if (invoiceCustomerName != null && invoiceCustomerName.isNotEmpty) {
            contactName = invoiceCustomerName;
          }
        }

        if (contextType == 'job' && contextId != null && contextId.isNotEmpty) {
          final job = await _client
              .from('mechanic_jobs')
              .select('customer_id')
              .eq('id', contextId)
              .limit(1)
              .maybeSingle();

          customerId = job?['customer_id']?.toString();
          final customerContact = await loadCustomerById(customerId);
          if (customerContact != null) {
            contactName = customerContact['name']?.toString() ?? contactName;
            phoneNumber = customerContact['phone']?.toString() ?? phoneNumber;
          }
        }

        if (contextType == 'order' &&
            contextId != null &&
            contextId.isNotEmpty) {
          final order = await _client
              .from('online_orders')
              .select('customer_id, customer_name, customer_phone')
              .eq('id', contextId)
              .limit(1)
              .maybeSingle();

          customerId = order?['customer_id']?.toString() ?? customerId;

          final orderCustomerName = order?['customer_name']?.toString();
          if (orderCustomerName != null && orderCustomerName.isNotEmpty) {
            contactName = orderCustomerName;
          }

          final orderPhone = order?['customer_phone']?.toString();
          if (orderPhone != null && orderPhone.isNotEmpty) {
            phoneNumber = orderPhone;
          } else {
            final customerContact = await loadCustomerById(customerId);
            if (customerContact != null) {
              contactName = customerContact['name']?.toString() ?? contactName;
              phoneNumber = customerContact['phone']?.toString() ?? phoneNumber;
            }
          }
        }
      }

      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        return {
          'customer_id': customerId,
          'name': contactName,
          'phone': phoneNumber,
          'last_inbound_at': lastInboundAt,
          'last_outbound_at': lastOutboundAt,
          'last_first_contact_template_at': lastFirstContactTemplateAt,
        };
      }

      final participants = await _client
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', conversationId);

      final participantIds = (participants as List)
          .map((row) => row['user_id']?.toString())
          .whereType<String>()
          .where((userId) => userId != currentUserId)
          .toList();

      if (participantIds.isEmpty) {
        return null;
      }

      final customers = await _client
          .from('customers')
          .select('id, auth_user_id, name, phone')
          .inFilter('auth_user_id', participantIds);

      for (final rawCustomer in customers) {
        final customer = Map<String, dynamic>.from(rawCustomer);
        final phone = customer['phone']?.toString();
        if (phone != null && phone.isNotEmpty) {
          return {
            'customer_id': customer['id']?.toString(),
            'name': customer['name']?.toString() ?? contactName,
            'phone': phone,
            'last_inbound_at': lastInboundAt,
            'last_outbound_at': lastOutboundAt,
            'last_first_contact_template_at': lastFirstContactTemplateAt,
          };
        }
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ Error resolving support conversation contact: $e');
      return null;
    }
  }

  /// Get all support conversations grouped by status (for ERP inbox)
  Future<Map<String, List<Map<String, dynamic>>>> getSupportInbox() async {
    final response = await _client.from('conversations').select('''
      *,
      conversation_participants(user_id, role),
      messages(id, content, sender_id, created_at, type),
      conversation_contexts(context_type, context_id, is_primary)
    ''').eq('type', 'support').order('last_message_at', ascending: false);

    final conversations = List<Map<String, dynamic>>.from(response);

    // Group by status
    return {
      'pending': conversations.where((c) => c['status'] == 'pending').toList(),
      'active': conversations.where((c) => c['status'] == 'active').toList(),
      'resolved':
          conversations.where((c) => c['status'] == 'resolved').toList(),
    };
  }
}
