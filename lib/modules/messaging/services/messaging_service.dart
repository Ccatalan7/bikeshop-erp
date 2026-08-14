import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/conversation.dart';
import '../models/conversation_context_hint.dart';
import '../models/message.dart';
import '../utils/conversation_activity.dart';
import '../utils/whatsapp_message_filters.dart';
import 'messaging_attachment_service.dart';
import 'messaging_command_idempotency_store.dart';
// For VoidCallback

class MessageReceiptRealtimeUpdate {
  final String conversationId;
  final String messageId;
  final String externalStatus;

  const MessageReceiptRealtimeUpdate({
    required this.conversationId,
    required this.messageId,
    required this.externalStatus,
  });
}

class MessageHistoryPage {
  final List<Message> messages;
  final bool hasMore;
  final int? nextBeforeSequence;

  const MessageHistoryPage({
    required this.messages,
    required this.hasMore,
    required this.nextBeforeSequence,
  });
}

@visibleForTesting
String? resolveSupplierMessagingContactName(Map<String, dynamic>? supplier) {
  if (supplier == null) return null;

  final salesRepresentative = supplier['sales_rep_name']?.toString().trim();
  if (salesRepresentative != null && salesRepresentative.isNotEmpty) {
    return salesRepresentative.split(RegExp(r'\s+')).first;
  }

  final contactPerson = supplier['contact_person']?.toString().trim();
  return contactPerson == null || contactPerson.isEmpty
      ? null
      : contactPerson.split(RegExp(r'\s+')).first;
}

class MessagingService {
  static const int recentMessageStreamLimit = 250;
  static const int historyPageSize = 100;

  static final MessagingCommandIdempotencyStore _commandIdempotencyStore =
      MessagingCommandIdempotencyStore();

  final SupabaseClient _client = Supabase.instance.client;

  /// Get current user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<void> _assertMessagingCommandSession({
    required String expectedUserId,
    required String expectedTenantId,
  }) async {
    if (currentUserId != expectedUserId) {
      throw Exception('La sesión cambió antes de completar la operación');
    }

    final activeTenantId = await TenantService().getTenantId();
    if (currentUserId != expectedUserId || activeTenantId != expectedTenantId) {
      throw Exception(
          'El tenant activo cambió antes de completar la operación');
    }
  }

  (String?, String?) _normalizedContextPair(
    String? contextType,
    String? contextId,
  ) {
    final normalizedType = _normalizeConversationContextType(contextType);
    final normalizedId = _text(contextId);
    if ((normalizedType == null) != (normalizedId == null)) {
      throw Exception(
          'El tipo y el identificador de contexto son inseparables');
    }
    return (normalizedType, normalizedId);
  }

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
      'purchase_invoice' ||
      'bike' ||
      'product' ||
      'order' ||
      'supplier' ||
      'customer' =>
        normalized,
      _ => throw Exception('Tipo de contexto no permitido: $contextType'),
    };
  }

  bool _isDuplicateParticipantError(Object error) {
    return error is PostgrestException && error.code == '23505';
  }

  String? _text(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  double? _doubleValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime? _dateValue(dynamic value) {
    final text = _text(value);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }

  void _debugInboxService(
    String event,
    Stopwatch stopwatch, {
    Map<String, Object?> details = const {},
  }) {
    if (!kDebugMode) return;

    final parts = <String>[
      event,
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
      ...details.entries.map((entry) => '${entry.key}=${entry.value}'),
    ];
    debugPrint('[InboxSync] service:${parts.join(' ')}');
  }

  Map<String, dynamic> _rowMap(dynamic row) {
    if (row is Map<String, dynamic>) return row;
    return Map<String, dynamic>.from(row as Map);
  }

  (String?, String?) _primaryContextFromConversation(dynamic rawConversation) {
    final json = _rowMap(rawConversation);
    String? contextType = _text(json['context_type']);
    String? contextId = _text(json['context_id']);

    final contexts = json['conversation_contexts'];
    if ((contextType == null || contextId == null) && contexts is List) {
      dynamic selectedContext;
      for (final context in contexts) {
        if (context is Map && context['is_primary'] == true) {
          selectedContext = context;
          break;
        }
      }
      if (selectedContext == null && contexts.isNotEmpty) {
        selectedContext = contexts.first;
      }
      if (selectedContext is Map) {
        contextType ??= _text(selectedContext['context_type']);
        contextId ??= _text(selectedContext['context_id']);
      }
    }

    return (contextType, contextId);
  }

  String _jobStatusLabel(dynamic rawStatus) {
    final status = _text(rawStatus)?.toUpperCase();
    return switch (status) {
      'PENDIENTE' => 'Pendiente',
      'DIAGNOSTICO' => 'Diagnóstico',
      'ESPERANDO_APROBACION' => 'Esperando aprobación',
      'ESPERANDO_REPUESTOS' => 'Esperando repuestos',
      'EN_CURSO' => 'En curso',
      'FINALIZADO' => 'Finalizado',
      'ENTREGADO' => 'Entregado',
      'CANCELADO' => 'Cancelado',
      _ => _text(rawStatus) ?? 'Trabajo activo',
    };
  }

  String? _jobStatusColor(Map<String, dynamic> job) {
    final joinedStatus = job['job_status'];
    if (joinedStatus is Map) {
      final color = _text(joinedStatus['color']);
      if (color != null) return color;
    }

    final status = _text(job['status'])?.toUpperCase();
    return switch (status) {
      'PENDIENTE' => '#F59E0B',
      'DIAGNOSTICO' => '#3B82F6',
      'ESPERANDO_APROBACION' => '#F59E0B',
      'ESPERANDO_REPUESTOS' => '#8B5CF6',
      'EN_CURSO' => '#06B6D4',
      'FINALIZADO' => '#10B981',
      'ENTREGADO' => '#16A34A',
      'CANCELADO' => '#EF4444',
      _ => null,
    };
  }

  bool _isOpenJob(Map<String, dynamic> job) {
    final status = _text(job['status'])?.toUpperCase();
    return status != 'FINALIZADO' &&
        status != 'ENTREGADO' &&
        status != 'CANCELADO';
  }

  DateTime _jobSortDate(Map<String, dynamic> job) {
    return _dateValue(job['status_updated_at']) ??
        _dateValue(job['updated_at']) ??
        _dateValue(job['arrival_date']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String? _bikeNameFromRow(Map<String, dynamic>? bike) {
    if (bike == null) return null;
    final parts = <String>[
      if (_text(bike['brand']) != null) _text(bike['brand'])!,
      if (_text(bike['model']) != null) _text(bike['model'])!,
      if (_text(bike['year']) != null) _text(bike['year'])!,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  String? _invoiceStatusLabel(dynamic rawStatus) {
    final status = _text(rawStatus)?.toLowerCase();
    return switch (status) {
      'draft' => 'Borrador',
      'sent' => 'Enviada',
      'confirmed' => 'Confirmada',
      'paid' => 'Pagada',
      'overdue' => 'Vencida',
      'cancelled' || 'canceled' => 'Cancelada',
      _ => _text(rawStatus),
    };
  }

  String? _purchaseInvoiceStatusLabel(dynamic rawStatus) {
    final status = _text(rawStatus)?.toLowerCase();
    return switch (status) {
      'draft' => 'Borrador',
      'sent' => 'Enviada',
      'confirmed' => 'Confirmada',
      'received' => 'Recibida',
      'paid' => 'Pagada',
      'cancelled' || 'canceled' => 'Anulada',
      _ => _text(rawStatus),
    };
  }

  bool _isActivePurchaseInvoice(Map<String, dynamic> invoice) {
    return ConversationActivity.isActivePurchaseInvoiceStatus(
      _text(invoice['status']),
    );
  }

  Set<String> _phoneLookupCandidates(String phone) {
    final trimmed = phone.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    final candidates = <String>{trimmed};
    if (digits.isNotEmpty) {
      candidates.add(digits);
      candidates.add('+$digits');
      if (digits.startsWith('56') && digits.length > 2) {
        final local = digits.substring(2);
        candidates.add(local);
        candidates.add('+56 $local');
        candidates.add('+56$local');
      } else {
        candidates.add('56$digits');
        candidates.add('+56$digits');
      }
    }
    return candidates.where((candidate) => candidate.trim().isNotEmpty).toSet();
  }

  Future<Map<String, ConversationContextHint>>
      _fetchContextHintsForConversations(List<dynamic> rawConversations) async {
    if (rawConversations.isEmpty) return {};

    final tenantId = await TenantService().getTenantId();
    final conversationRows = <String, Map<String, dynamic>>{};
    final contextTypeByConversation = <String, String?>{};
    final contextIdByConversation = <String, String?>{};
    final customerIdByConversation = <String, String>{};
    final contactNameByConversation = <String, String>{};
    final phoneByConversation = <String, String>{};
    final explicitJobIds = <String>{};
    final explicitInvoiceIds = <String>{};
    final explicitPurchaseInvoiceIds = <String>{};
    final supplierIdByConversation = <String, String>{};
    final orderIds = <String>{};
    final creatorIds = <String>{};

    for (final raw in rawConversations) {
      final row = _rowMap(raw);
      final conversationId = _text(row['id']);
      if (conversationId == null) continue;
      conversationRows[conversationId] = row;

      final (contextType, contextId) = _primaryContextFromConversation(row);
      contextTypeByConversation[conversationId] = contextType;
      contextIdByConversation[conversationId] = contextId;

      if (contextType == 'customer' && contextId != null) {
        customerIdByConversation[conversationId] = contextId;
      } else if (contextType == 'job' && contextId != null) {
        explicitJobIds.add(contextId);
      } else if (contextType == 'invoice' && contextId != null) {
        explicitInvoiceIds.add(contextId);
      } else if (contextType == 'purchase_invoice' && contextId != null) {
        explicitPurchaseInvoiceIds.add(contextId);
      } else if (contextType == 'supplier' && contextId != null) {
        supplierIdByConversation[conversationId] = contextId;
      } else if (contextType == 'order' && contextId != null) {
        orderIds.add(contextId);
      }

      final createdBy = _text(row['created_by']);
      if (createdBy != null && row['type'] == 'support') {
        creatorIds.add(createdBy);
      }
    }

    final customerRowsById = <String, Map<String, dynamic>>{};
    final customerRowsByAuthId = <String, Map<String, dynamic>>{};

    void captureCustomer(dynamic rawCustomer) {
      final customer = _rowMap(rawCustomer);
      final id = _text(customer['id']);
      if (id != null) customerRowsById[id] = customer;
      final authUserId = _text(customer['auth_user_id']);
      if (authUserId != null) customerRowsByAuthId[authUserId] = customer;
    }

    Future<void> loadCustomersByIds(Set<String> ids) async {
      final missingIds = ids.where((id) => !customerRowsById.containsKey(id));
      if (missingIds.isEmpty) return;
      try {
        dynamic query = _client.from('customers').select(
              'id, auth_user_id, name, phone, image_url',
            );
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query.inFilter('id', missingIds.toList());
        for (final row in rows as List) {
          captureCustomer(row);
        }
      } catch (e) {
        debugPrint('⚠️ Error loading context customers: $e');
      }
    }

    try {
      final ids = conversationRows.keys.toList();
      final bindings = await _client
          .from('whatsapp_conversation_bindings')
          .select(
            'conversation_id, customer_id, contact_name, external_phone_number',
          )
          .inFilter('conversation_id', ids);

      final phoneCandidatesByConversation = <String, Set<String>>{};
      final allPhoneCandidates = <String>{};
      for (final rawBinding in bindings as List) {
        final binding = _rowMap(rawBinding);
        final conversationId = _text(binding['conversation_id']);
        if (conversationId == null) continue;

        final customerId = _text(binding['customer_id']);
        if (customerId != null) {
          customerIdByConversation[conversationId] = customerId;
        }

        final contactName = _text(binding['contact_name']);
        if (contactName != null) {
          contactNameByConversation[conversationId] = contactName;
        }

        final phone = _text(binding['external_phone_number']);
        if (phone != null) {
          phoneByConversation[conversationId] = phone;
          final candidates = _phoneLookupCandidates(phone);
          phoneCandidatesByConversation[conversationId] = candidates;
          allPhoneCandidates.addAll(candidates);
        }
      }

      if (allPhoneCandidates.isNotEmpty) {
        dynamic query = _client.from('customers').select(
              'id, auth_user_id, name, phone, image_url',
            );
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final customersByPhone = await query.inFilter(
          'phone',
          allPhoneCandidates.toList(),
        );
        for (final rawCustomer in customersByPhone as List) {
          final customer = _rowMap(rawCustomer);
          captureCustomer(customer);
          final phone = _text(customer['phone']);
          final customerId = _text(customer['id']);
          if (phone == null || customerId == null) continue;
          for (final entry in phoneCandidatesByConversation.entries) {
            if (entry.value.contains(phone)) {
              customerIdByConversation.putIfAbsent(entry.key, () => customerId);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading WhatsApp context hints: $e');
    }

    final supplierRowsById = <String, Map<String, dynamic>>{};
    final supplierPhoneCandidatesById = <String, Set<String>>{};
    try {
      dynamic query = _client.from('suppliers').select(
            'id, name, phone, sales_rep_phone, is_active',
          );
      if (tenantId != null && tenantId.isNotEmpty) {
        query = query.eq('tenant_id', tenantId);
      }
      final rows = await query;
      for (final rawSupplier in rows as List) {
        final supplier = _rowMap(rawSupplier);
        final supplierId = _text(supplier['id']);
        if (supplierId == null) continue;
        supplierRowsById[supplierId] = supplier;

        final candidates = <String>{};
        final phone =
            _text(supplier['sales_rep_phone']) ?? _text(supplier['phone']);
        final primaryPhone = _text(supplier['phone']);
        final salesRepPhone = _text(supplier['sales_rep_phone']);
        if (phone != null) candidates.addAll(_phoneLookupCandidates(phone));
        if (primaryPhone != null) {
          candidates.addAll(_phoneLookupCandidates(primaryPhone));
        }
        if (salesRepPhone != null) {
          candidates.addAll(_phoneLookupCandidates(salesRepPhone));
        }
        if (candidates.isNotEmpty) {
          supplierPhoneCandidatesById[supplierId] = candidates;
        }
      }

      for (final phoneEntry in phoneByConversation.entries) {
        final phoneCandidates = _phoneLookupCandidates(phoneEntry.value);
        for (final supplierEntry in supplierPhoneCandidatesById.entries) {
          if (phoneCandidates.intersection(supplierEntry.value).isNotEmpty) {
            supplierIdByConversation.putIfAbsent(
              phoneEntry.key,
              () => supplierEntry.key,
            );
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading supplier context hints: $e');
    }

    if (creatorIds.isNotEmpty) {
      try {
        dynamic query = _client.from('customers').select(
              'id, auth_user_id, name, phone, image_url',
            );
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query.inFilter('auth_user_id', creatorIds.toList());
        for (final row in rows as List) {
          captureCustomer(row);
        }
        for (final entry in conversationRows.entries) {
          final createdBy = _text(entry.value['created_by']);
          if (createdBy == null) continue;
          final customer = customerRowsByAuthId[createdBy];
          final customerId = customer == null ? null : _text(customer['id']);
          if (customerId != null) {
            customerIdByConversation.putIfAbsent(entry.key, () => customerId);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error loading creator context customers: $e');
      }
    }

    final invoiceRowsById = <String, Map<String, dynamic>>{};
    Future<void> loadInvoicesByIds(Set<String> ids) async {
      final missingIds = ids.where((id) => !invoiceRowsById.containsKey(id));
      if (missingIds.isEmpty) return;
      try {
        dynamic query = _client.from('sales_invoices').select(
              'id, customer_id, customer_name, invoice_number, status, total, balance, date',
            );
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query.inFilter('id', missingIds.toList());
        for (final row in rows as List) {
          final invoice = _rowMap(row);
          final id = _text(invoice['id']);
          if (id != null) invoiceRowsById[id] = invoice;
        }
      } catch (e) {
        debugPrint('⚠️ Error loading context invoices: $e');
      }
    }

    await loadInvoicesByIds(explicitInvoiceIds);

    final purchaseInvoiceRowsById = <String, Map<String, dynamic>>{};
    Future<void> loadPurchaseInvoicesByIds(Set<String> ids) async {
      final missingIds =
          ids.where((id) => !purchaseInvoiceRowsById.containsKey(id));
      if (missingIds.isEmpty) return;
      try {
        dynamic query = _client.from('purchase_invoices').select(
              'id, supplier_id, supplier_name, invoice_number, status, total, balance, date, due_date, updated_at',
            );
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query.inFilter('id', missingIds.toList());
        for (final row in rows as List) {
          final invoice = _rowMap(row);
          final id = _text(invoice['id']);
          if (id != null) purchaseInvoiceRowsById[id] = invoice;
        }
      } catch (e) {
        debugPrint('⚠️ Error loading context purchase invoices: $e');
      }
    }

    await loadPurchaseInvoicesByIds(explicitPurchaseInvoiceIds);
    for (final entry in contextIdByConversation.entries) {
      if (contextTypeByConversation[entry.key] != 'purchase_invoice') continue;
      final invoice = purchaseInvoiceRowsById[entry.value];
      final supplierId = invoice == null ? null : _text(invoice['supplier_id']);
      if (supplierId != null) supplierIdByConversation[entry.key] = supplierId;
    }

    for (final entry in contextIdByConversation.entries) {
      if (contextTypeByConversation[entry.key] != 'invoice') continue;
      final invoice = invoiceRowsById[entry.value];
      final customerId = invoice == null ? null : _text(invoice['customer_id']);
      if (customerId != null) customerIdByConversation[entry.key] = customerId;
      final customerName =
          invoice == null ? null : _text(invoice['customer_name']);
      if (customerName != null) {
        contactNameByConversation[entry.key] = customerName;
      }
    }

    if (orderIds.isNotEmpty) {
      try {
        dynamic query = _client.from('online_orders').select(
              'id, customer_id, customer_name, customer_phone',
            );
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query.inFilter('id', orderIds.toList());
        final ordersById = <String, Map<String, dynamic>>{};
        for (final row in rows as List) {
          final order = _rowMap(row);
          final id = _text(order['id']);
          if (id != null) ordersById[id] = order;
        }
        for (final entry in contextIdByConversation.entries) {
          if (contextTypeByConversation[entry.key] != 'order') continue;
          final order = ordersById[entry.value];
          if (order == null) continue;
          final customerId = _text(order['customer_id']);
          if (customerId != null) {
            customerIdByConversation[entry.key] = customerId;
          }
          final customerName = _text(order['customer_name']);
          if (customerName != null) {
            contactNameByConversation[entry.key] = customerName;
          }
          final phone = _text(order['customer_phone']);
          if (phone != null) phoneByConversation[entry.key] = phone;
        }
      } catch (e) {
        debugPrint('⚠️ Error loading order context hints: $e');
      }
    }

    final activePurchaseInvoiceBySupplierId = <String, Map<String, dynamic>>{};
    final latestPurchaseInvoiceBySupplierId = <String, Map<String, dynamic>>{};
    final supplierIds = supplierIdByConversation.values.toSet();
    if (supplierIds.isNotEmpty) {
      try {
        dynamic query = _client.from('purchase_invoices').select(
              'id, supplier_id, supplier_name, invoice_number, status, total, balance, date, due_date, updated_at',
            );
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query
            .inFilter('supplier_id', supplierIds.toList())
            .order('date', ascending: false)
            .limit(500);
        for (final rawInvoice in rows as List) {
          final invoice = _rowMap(rawInvoice);
          final invoiceId = _text(invoice['id']);
          if (invoiceId != null) purchaseInvoiceRowsById[invoiceId] = invoice;

          final supplierId = _text(invoice['supplier_id']);
          if (supplierId == null) continue;
          latestPurchaseInvoiceBySupplierId.putIfAbsent(
            supplierId,
            () => invoice,
          );
          if (_isActivePurchaseInvoice(invoice)) {
            activePurchaseInvoiceBySupplierId.putIfAbsent(
              supplierId,
              () => invoice,
            );
          }
        }
      } catch (e) {
        debugPrint(
            '⚠️ Error loading active supplier purchase context hints: $e');
      }
    }

    final jobRowsById = <String, Map<String, dynamic>>{};
    final jobRowsByInvoiceId = <String, Map<String, dynamic>>{};

    void captureJob(dynamic rawJob) {
      final job = _rowMap(rawJob);
      final id = _text(job['id']);
      if (id != null) jobRowsById[id] = job;
      final invoiceId = _text(job['invoice_id']);
      if (invoiceId != null) jobRowsByInvoiceId[invoiceId] = job;
    }

    Future<void> loadJobsByIds(Set<String> ids) async {
      final missingIds = ids.where((id) => !jobRowsById.containsKey(id));
      if (missingIds.isEmpty) return;
      try {
        dynamic query = _client.from('mechanic_jobs').select('''
          id, tenant_id, customer_id, bike_id, job_number, status, status_id,
          status_updated_at, invoice_id, arrival_date, updated_at,
          job_status:job_statuses(name, color)
        ''');
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query
            .inFilter('id', missingIds.toList())
            .isFilter('deleted_at', null);
        for (final row in rows as List) {
          captureJob(row);
        }
      } catch (e) {
        debugPrint('⚠️ Error loading explicit job context hints: $e');
      }
    }

    await loadJobsByIds(explicitJobIds);
    for (final entry in contextIdByConversation.entries) {
      if (contextTypeByConversation[entry.key] != 'job') continue;
      final job = jobRowsById[entry.value];
      final customerId = job == null ? null : _text(job['customer_id']);
      if (customerId != null) customerIdByConversation[entry.key] = customerId;
    }

    final invoiceIdsNeedingJob = {...explicitInvoiceIds};
    if (invoiceIdsNeedingJob.isNotEmpty) {
      try {
        dynamic query = _client.from('mechanic_jobs').select('''
          id, tenant_id, customer_id, bike_id, job_number, status, status_id,
          status_updated_at, invoice_id, arrival_date, updated_at,
          job_status:job_statuses(name, color)
        ''');
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query
            .inFilter('invoice_id', invoiceIdsNeedingJob.toList())
            .isFilter('deleted_at', null);
        for (final row in rows as List) {
          captureJob(row);
        }
      } catch (e) {
        debugPrint('⚠️ Error loading invoice job context hints: $e');
      }
    }

    await loadCustomersByIds(customerIdByConversation.values.toSet());

    final activeJobByCustomerId = <String, Map<String, dynamic>>{};
    final customerIds = customerIdByConversation.values.toSet();
    if (customerIds.isNotEmpty) {
      try {
        dynamic query = _client.from('mechanic_jobs').select('''
          id, tenant_id, customer_id, bike_id, job_number, status, status_id,
          status_updated_at, invoice_id, arrival_date, updated_at,
          job_status:job_statuses(name, color)
        ''');
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query
            .inFilter('customer_id', customerIds.toList())
            .isFilter('deleted_at', null)
            .order('updated_at', ascending: false)
            .limit(300);
        final jobs = (rows as List).map(_rowMap).where(_isOpenJob).toList()
          ..sort((a, b) => _jobSortDate(b).compareTo(_jobSortDate(a)));
        for (final job in jobs) {
          captureJob(job);
          final customerId = _text(job['customer_id']);
          if (customerId != null) {
            activeJobByCustomerId.putIfAbsent(customerId, () => job);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error loading active customer job context hints: $e');
      }
    }

    final selectedJobByConversation = <String, Map<String, dynamic>>{};
    final invoiceIdsToLoad = <String>{...explicitInvoiceIds};
    for (final conversationId in conversationRows.keys) {
      final contextType = contextTypeByConversation[conversationId];
      final contextId = contextIdByConversation[conversationId];
      final customerId = customerIdByConversation[conversationId];

      Map<String, dynamic>? job;
      if (contextType == 'job' && contextId != null) {
        job = jobRowsById[contextId];
      } else if (contextType == 'invoice' && contextId != null) {
        job = jobRowsByInvoiceId[contextId];
      }
      job ??= customerId == null ? null : activeJobByCustomerId[customerId];

      if (job != null) {
        selectedJobByConversation[conversationId] = job;
        final invoiceId = _text(job['invoice_id']);
        if (invoiceId != null) invoiceIdsToLoad.add(invoiceId);
      }
    }

    await loadInvoicesByIds(invoiceIdsToLoad);

    final bikeRowsById = <String, Map<String, dynamic>>{};
    final bikeNameByJobId = <String, String>{};
    final bikeIdByJobId = <String, String>{};
    final bikeIds = <String>{};
    final selectedJobIds = <String>{};
    for (final job in selectedJobByConversation.values) {
      final jobId = _text(job['id']);
      if (jobId != null) selectedJobIds.add(jobId);
      final bikeId = _text(job['bike_id']);
      if (bikeId != null) bikeIds.add(bikeId);
    }

    if (bikeIds.isNotEmpty) {
      try {
        dynamic query = _client.from('bikes').select('id, brand, model, year');
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query.inFilter('id', bikeIds.toList());
        for (final row in rows as List) {
          final bike = _rowMap(row);
          final id = _text(bike['id']);
          if (id != null) bikeRowsById[id] = bike;
        }
      } catch (e) {
        debugPrint('⚠️ Error loading context bikes: $e');
      }
    }

    if (selectedJobIds.isNotEmpty) {
      try {
        dynamic query = _client.from('mechanic_job_bikes').select('''
          job_id, bike_id, order_index,
          bike:bikes(id, brand, model, year)
        ''');
        if (tenantId != null && tenantId.isNotEmpty) {
          query = query.eq('tenant_id', tenantId);
        }
        final rows = await query
            .inFilter('job_id', selectedJobIds.toList())
            .order('order_index');
        for (final rawRow in rows as List) {
          final row = _rowMap(rawRow);
          final jobId = _text(row['job_id']);
          if (jobId == null || bikeNameByJobId.containsKey(jobId)) continue;
          final bikeId = _text(row['bike_id']);
          if (bikeId != null) bikeIdByJobId[jobId] = bikeId;
          final bike = row['bike'] is Map ? _rowMap(row['bike']) : null;
          final bikeName = _bikeNameFromRow(bike);
          if (bikeName != null) bikeNameByJobId[jobId] = bikeName;
        }
      } catch (e) {
        debugPrint('⚠️ Error loading context job bikes: $e');
      }
    }

    final result = <String, ConversationContextHint>{};
    for (final conversationId in conversationRows.keys) {
      final customerId = customerIdByConversation[conversationId];
      final customer = customerId == null ? null : customerRowsById[customerId];
      final job = selectedJobByConversation[conversationId];
      final contextType = contextTypeByConversation[conversationId];
      final contextId = contextIdByConversation[conversationId];
      final explicitInvoiceId = contextType == 'invoice' ? contextId : null;
      final explicitPurchaseInvoiceId =
          contextType == 'purchase_invoice' ? contextId : null;
      final jobInvoiceId = job == null ? null : _text(job['invoice_id']);
      final invoiceId = explicitInvoiceId ?? jobInvoiceId;
      final invoice = invoiceId == null ? null : invoiceRowsById[invoiceId];
      final supplierId = supplierIdByConversation[conversationId];
      final supplier = supplierId == null ? null : supplierRowsById[supplierId];
      final purchaseInvoice = explicitPurchaseInvoiceId == null
          ? (supplierId == null
              ? null
              : activePurchaseInvoiceBySupplierId[supplierId] ??
                  latestPurchaseInvoiceBySupplierId[supplierId])
          : purchaseInvoiceRowsById[explicitPurchaseInvoiceId];
      final jobId = job == null ? null : _text(job['id']);
      final jobBikeId = jobId == null ? null : bikeIdByJobId[jobId];
      final directBikeId = job == null ? null : _text(job['bike_id']);
      final bikeId = directBikeId ?? jobBikeId;
      final bikeName = jobId == null
          ? null
          : bikeNameByJobId[jobId] ?? _bikeNameFromRow(bikeRowsById[bikeId]);

      final hint = ConversationContextHint(
        customerId: customerId,
        customerName: _text(customer == null ? null : customer['name']) ??
            contactNameByConversation[conversationId],
        customerImageUrl:
            _text(customer == null ? null : customer['image_url']),
        phone: _text(customer == null ? null : customer['phone']) ??
            _text(supplier == null ? null : supplier['sales_rep_phone']) ??
            _text(supplier == null ? null : supplier['phone']) ??
            phoneByConversation[conversationId],
        primaryContextType: contextType,
        primaryContextId: contextId,
        jobId: jobId,
        jobNumber: job == null ? null : _text(job['job_number']),
        jobStatus: job == null
            ? null
            : (job['job_status'] is Map
                    ? _text((job['job_status'] as Map)['name'])
                    : null) ??
                _jobStatusLabel(job['status']),
        jobStatusColor: job == null ? null : _jobStatusColor(job),
        bikeId: bikeId,
        bikeName: bikeName,
        invoiceId: invoiceId,
        invoiceNumber:
            invoice == null ? null : _text(invoice['invoice_number']),
        invoiceStatus:
            invoice == null ? null : _invoiceStatusLabel(invoice['status']),
        invoiceBalance:
            invoice == null ? null : _doubleValue(invoice['balance']),
        invoiceTotal: invoice == null ? null : _doubleValue(invoice['total']),
        supplierId: supplierId,
        supplierName: _text(supplier == null ? null : supplier['name']) ??
            (purchaseInvoice == null
                ? null
                : _text(purchaseInvoice['supplier_name'])),
        supplierPhone:
            _text(supplier == null ? null : supplier['sales_rep_phone']) ??
                _text(supplier == null ? null : supplier['phone']) ??
                phoneByConversation[conversationId],
        purchaseInvoiceId:
            purchaseInvoice == null ? null : _text(purchaseInvoice['id']),
        purchaseInvoiceNumber: purchaseInvoice == null
            ? null
            : _text(purchaseInvoice['invoice_number']),
        purchaseInvoiceStatus: purchaseInvoice == null
            ? null
            : _purchaseInvoiceStatusLabel(purchaseInvoice['status']),
        purchaseInvoiceBalance: purchaseInvoice == null
            ? null
            : _doubleValue(purchaseInvoice['balance']),
        purchaseInvoiceTotal: purchaseInvoice == null
            ? null
            : _doubleValue(purchaseInvoice['total']),
      );

      if (hint.hasCustomer || hint.hasSupplier || hint.hasOperationalContext) {
        result[conversationId] = hint;
      }
    }

    return result;
  }

  /// Refreshes only the derived business context shown beside inbox rows.
  /// Conversation previews and unread counts have their own faster read path.
  Future<Map<String, ConversationContextHint>> getConversationContextHints(
    List<Conversation> conversations,
  ) async {
    final conversationIds =
        conversations.map((conversation) => conversation.id).toList();
    final contextsByConversation = <String, List<Map<String, dynamic>>>{};
    if (conversationIds.isNotEmpty) {
      try {
        final contextRows = await _client
            .from('conversation_contexts')
            .select(
              'conversation_id, context_type, context_id, is_primary',
            )
            .inFilter('conversation_id', conversationIds);
        for (final rawContext in contextRows as List) {
          final context = _rowMap(rawContext);
          final conversationId = _text(context['conversation_id']);
          if (conversationId == null) continue;
          contextsByConversation
              .putIfAbsent(conversationId, () => [])
              .add(context);
        }
      } catch (error) {
        debugPrint('⚠️ Error loading conversation context links: $error');
      }
    }

    final rows = conversations
        .map(
          (conversation) => <String, dynamic>{
            'id': conversation.id,
            'type': conversation.type,
            'channel': conversation.channel,
            'created_by': conversation.createdBy,
            'context_type': conversation.contextType,
            'context_id': conversation.contextId,
            'conversation_contexts':
                contextsByConversation[conversation.id] ?? const [],
          },
        )
        .toList(growable: false);
    return await _fetchContextHintsForConversations(rows);
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
  Future<List<Conversation>> getConversations({
    String? type,
    bool includeContextHints = true,
  }) async {
    final userId = currentUserId;
    if (userId == null) return [];
    final stopwatch = Stopwatch()..start();
    final conversationSelect = includeContextHints
        ? '*, conversation_participants(user_id), conversation_contexts(*)'
        : '''
          id, type, channel, is_group, counterparty_type, status, title,
          context_type, context_id,
          updated_at, last_message_at, staff_last_read_at,
          staff_last_read_message_sequence, created_by,
          conversation_participants(user_id)
        ''';
    final internalConversationSelect = includeContextHints
        ? '*, conversation_participants!inner(user_id), conversation_contexts(*)'
        : '''
          id, type, channel, is_group, counterparty_type, status, title,
          context_type, context_id,
          updated_at, last_message_at, staff_last_read_at,
          staff_last_read_message_sequence, created_by,
          conversation_participants!inner(user_id)
        ''';

    List<dynamic> data = [];

    if (type == 'support') {
      // For support chats: show ALL support conversations (shared inbox)
      final response = await _client
          .from('conversations')
          .select(conversationSelect)
          .eq('type', 'support')
          .order('last_message_at', ascending: false);
      data = response as List<dynamic>;
      debugPrint('📬 Support chats loaded: ${data.length}');
    } else if (type == 'internal') {
      // For internal chats: only show ones where user is a participant
      final response = await _client
          .from('conversations')
          .select(internalConversationSelect)
          .eq('type', 'internal')
          .order('last_message_at', ascending: false);
      data = response as List<dynamic>;
      debugPrint('💬 Internal chats loaded: ${data.length}');
    } else {
      // No filter: get both internal (participated) and support (all)
      final responses = await Future.wait([
        _client
            .from('conversations')
            .select(internalConversationSelect)
            .eq('type', 'internal')
            .order('last_message_at', ascending: false),
        _client
            .from('conversations')
            .select(conversationSelect)
            .eq('type', 'support')
            .order('last_message_at', ascending: false),
      ]);
      final internalResponse = responses[0] as List;
      final supportResponse = responses[1] as List;

      debugPrint('💬 Internal chats: ${internalResponse.length}');
      debugPrint('📬 Support chats: ${supportResponse.length}');

      data = [...internalResponse, ...supportResponse];
      // Sort by last_message_at
      data.sort((a, b) {
        final aTime = a['last_message_at'] ?? a['updated_at'];
        final bTime = b['last_message_at'] ?? b['updated_at'];
        return bTime.compareTo(aTime);
      });
      debugPrint('📊 Total conversations: ${data.length}');
    }
    _debugInboxService(
      'getConversations:baseRows',
      stopwatch,
      details: {
        'type': type ?? 'all',
        'rows': data.length,
        'includeContextHints': includeContextHints,
      },
    );

    final conversationIds =
        data.map((json) => json['id']?.toString()).whereType<String>().toSet();

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

    final unreadFuture = (() async {
      final response = await _client
          .from('conversation_unread_counts')
          .select('conversation_id, unread_count')
          .eq('user_id', userId);
      final rows = response as List<dynamic>;
      _debugInboxService(
        'getConversations:unread',
        stopwatch,
        details: {'rows': rows.length},
      );
      return rows;
    })();

    final latestMessagesFuture = (() async {
      final latestMessages =
          await _fetchLatestMessagesForConversations(conversationIds);
      _debugInboxService(
        'getConversations:latestMessages',
        stopwatch,
        details: {'rows': latestMessages.length},
      );
      return latestMessages;
    })();

    final whatsappNamesFuture = (() async {
      if (!includeContextHints || supportConversationIds.isEmpty) {
        _debugInboxService(
          'getConversations:whatsappNames',
          stopwatch,
          details: {'skipped': true},
        );
        return <dynamic>[];
      }

      try {
        final response = await _client
            .from('whatsapp_conversation_bindings')
            .select('conversation_id, contact_name, external_phone_number')
            .inFilter(
              'conversation_id',
              supportConversationIds.toList(),
            );
        final rows = response as List<dynamic>;
        _debugInboxService(
          'getConversations:whatsappNames',
          stopwatch,
          details: {'rows': rows.length},
        );
        return rows;
      } catch (e) {
        debugPrint('Error fetching WhatsApp contact names: $e');
        return <dynamic>[];
      }
    })();

    final customerNamesFuture = (() async {
      if (!includeContextHints || creatorIds.isEmpty) {
        _debugInboxService(
          'getConversations:customerNames',
          stopwatch,
          details: {'skipped': true},
        );
        return <dynamic>[];
      }

      try {
        final response = await _client
            .from('customers')
            .select('auth_user_id, name')
            .inFilter('auth_user_id', creatorIds.toList());
        final rows = response as List<dynamic>;
        _debugInboxService(
          'getConversations:customerNames',
          stopwatch,
          details: {'rows': rows.length},
        );
        return rows;
      } catch (e) {
        debugPrint('Error fetching customer names: $e');
        return <dynamic>[];
      }
    })();

    final contextHintsFuture = (() async {
      if (!includeContextHints) {
        _debugInboxService(
          'getConversations:contextHints',
          stopwatch,
          details: {
            'included': false,
            'rows': 0,
          },
        );
        return <String, ConversationContextHint>{};
      }

      final hints = await _fetchContextHintsForConversations(data);
      _debugInboxService(
        'getConversations:contextHints',
        stopwatch,
        details: {
          'included': true,
          'rows': hints.length,
        },
      );
      return hints;
    })();

    final inboxPieces = await Future.wait<dynamic>([
      unreadFuture,
      latestMessagesFuture,
      whatsappNamesFuture,
      customerNamesFuture,
      contextHintsFuture,
    ]);
    final unreadResponse = inboxPieces[0] as List<dynamic>;
    final latestMessages = inboxPieces[1] as Map<String, Map<String, dynamic>>;
    final whatsappNameRows = inboxPieces[2] as List<dynamic>;
    final customerNameRows = inboxPieces[3] as List<dynamic>;
    final contextHints = inboxPieces[4] as Map<String, ConversationContextHint>;

    final Map<String, int> unreadMap = {};
    for (var row in unreadResponse) {
      final conversationId = row['conversation_id']?.toString();
      if (conversationId == null) continue;
      unreadMap[conversationId] = row['unread_count'] ?? 0;
    }

    final Map<String, String> whatsappContactNames = {};
    for (final binding in whatsappNameRows) {
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

    // Fetch customer names for creators
    Map<String, String> customerNames = {};
    for (var c in customerNameRows) {
      if (c['auth_user_id'] != null && c['name'] != null) {
        customerNames[c['auth_user_id']] = c['name'];
      }
    }

    final conversations = data.map((json) {
      // Inject unread count and creator name into json before parsing.
      final conversationId = json['id']?.toString();
      final latestMessage =
          conversationId == null ? null : latestMessages[conversationId];
      final participates = _currentUserParticipates(json, userId);
      final serverUnreadCount =
          conversationId == null ? 0 : unreadMap[conversationId] ?? 0;
      json['unread_count'] = serverUnreadCount > 0
          ? serverUnreadCount
          : _needsSharedInboxUnreadHint(
              conversation: json,
              latestMessage: latestMessage,
              userId: userId,
              currentUserParticipates: participates,
            )
              ? 1
              : 0;
      if (latestMessage != null) {
        final lastMessage = latestMessage;
        json['last_message_id'] = lastMessage['id'];
        json['last_message_sequence'] = lastMessage['message_sequence'];
        json['last_message_content'] = lastMessage['content'];
        json['last_message_type'] = lastMessage['type'];
        json['last_message_metadata'] = lastMessage['metadata'];
        json['last_message_direction'] = lastMessage['message_direction'];
        json['last_message_external_status'] = lastMessage['external_status'];
        json['last_message_is_mine'] =
            lastMessage['sender_id']?.toString() == userId;
      }
      final createdBy = json['created_by'];
      if (conversationId != null &&
          whatsappContactNames.containsKey(conversationId)) {
        json['creator_name'] = whatsappContactNames[conversationId];
      } else if (createdBy != null && customerNames.containsKey(createdBy)) {
        json['creator_name'] = customerNames[createdBy];
      }
      final contextHint =
          conversationId == null ? null : contextHints[conversationId];
      if (contextHint != null) {
        json['context_hint'] = contextHint.toJson();
      }
      return Conversation.fromJson(json);
    }).toList();
    _debugInboxService(
      'getConversations:done',
      stopwatch,
      details: {'rows': conversations.length},
    );
    return conversations;
  }

  Future<Map<String, Map<String, dynamic>>>
      _fetchLatestMessagesForConversations(
    Set<String> conversationIds,
  ) async {
    if (conversationIds.isEmpty) return {};

    try {
      final limit = (conversationIds.length * 8).clamp(50, 500).toInt();
      final rows = await _client
          .from('messages')
          .select(
            'id, conversation_id, content, type, sender_id, created_at, message_sequence, metadata, message_direction, external_status',
          )
          .inFilter('conversation_id', conversationIds.toList())
          .order('message_sequence', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);

      final latestByConversation = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final message = Map<String, dynamic>.from(row as Map);
        if (isUnsupportedWhatsAppCompanionRow(message)) continue;

        final conversationId = message['conversation_id']?.toString();
        if (conversationId == null) continue;
        latestByConversation.putIfAbsent(conversationId, () => message);
      }

      return latestByConversation;
    } catch (e) {
      debugPrint('⚠️ Error fetching latest message previews: $e');
      return {};
    }
  }

  bool _currentUserParticipates(dynamic conversation, String userId) {
    final participants = conversation['conversation_participants'];
    if (participants is! List) return false;

    return participants.any(
      (participant) => participant['user_id']?.toString() == userId,
    );
  }

  bool _needsSharedInboxUnreadHint({
    required dynamic conversation,
    required Map<String, dynamic>? latestMessage,
    required String userId,
    required bool currentUserParticipates,
  }) {
    if (latestMessage == null || currentUserParticipates) return false;
    if (conversation['type']?.toString() != 'support') return false;

    final status = conversation['status']?.toString();
    if (status == 'resolved' || status == 'rejected') return false;

    final messageType = latestMessage['type']?.toString();
    if (messageType == 'system') return false;

    final senderId = latestMessage['sender_id']?.toString();
    if (senderId == userId) return false;

    final direction = latestMessage['message_direction']?.toString();
    if (direction == 'outbound') return false;

    final createdAt = DateTime.tryParse(
      latestMessage['created_at']?.toString() ?? '',
    );
    if (createdAt == null) return false;

    final staffLastReadAt = _dateValue(conversation['staff_last_read_at']);
    if (staffLastReadAt != null && !createdAt.isAfter(staffLastReadAt)) {
      return false;
    }

    if (DateTime.now().difference(createdAt.toLocal()) >
        const Duration(days: 7)) {
      return false;
    }

    // Shared WhatsApp/web support threads may not have a staff participant row
    // yet. Until the current user opens the chat, show one clear unread hint.
    return direction == 'inbound' || senderId == null || senderId.isNotEmpty;
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
  Future<void> markAsRead(
    String conversationId, {
    required String readThroughMessageId,
  }) async {
    if (currentUserId == null) throw Exception('Not authenticated');
    if (conversationId.trim().isEmpty || readThroughMessageId.trim().isEmpty) {
      throw Exception('La evidencia de lectura está incompleta');
    }

    await _client.rpc('mark_conversation_read', params: {
      'p_conversation_id': conversationId,
      'p_read_through_message_id': readThroughMessageId,
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
          .order('message_sequence', ascending: true)
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
              [
                'attachment_id',
                'url',
                'media_url',
                'documentUrl',
                'document_url'
              ].any(
                (key) => metadata.containsKey(key),
              ));
    }).length;
    final attachmentManifest = messages
        .map((message) {
          final metadata = message['metadata'];
          if (metadata is! Map) return null;
          final attachmentId = metadata['attachment_id']?.toString().trim();
          final storageBucket =
              metadata['storage_bucket'] ?? metadata['storageBucket'];
          final storagePath =
              metadata['storage_path'] ?? metadata['storagePath'];
          final manifest = <String, dynamic>{
            'message_id': message['id'],
            'created_at': message['created_at'],
            'type': message['type'],
            'filename': metadata['filename'] ??
                metadata['documentFilename'] ??
                metadata['document_filename'],
            'content_type': metadata['contentType'] ?? metadata['content_type'],
            'size_bytes': metadata['sizeBytes'] ?? metadata['size_bytes'],
            if (attachmentId != null && attachmentId.isNotEmpty)
              'attachment_id': attachmentId,
            if (storageBucket != null) 'storage_bucket': storageBucket,
            if (storagePath != null) 'storage_path': storagePath,
          };

          if (attachmentId != null &&
              attachmentId.isNotEmpty &&
              storageBucket == MessagingAttachmentService.bucketName &&
              storagePath != null) {
            return manifest;
          }

          final legacyCandidates = [
            metadata['url'],
            metadata['media_url'],
            metadata['documentUrl'],
            metadata['document_url'],
            if (message['type'] == 'image' || message['type'] == 'file')
              message['content'],
          ];
          final expectedHost = Uri.tryParse(_client.storage.url)?.host;
          for (final candidate in legacyCandidates) {
            if (MessagingAttachmentService.isTrustedLegacyPublicUrl(
              candidate?.toString(),
              expectedStorageHost: expectedHost,
            )) {
              return {...manifest, 'legacy_url': candidate};
            }
          }
          return null;
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
        .order('message_sequence', ascending: false)
        .limit(recentMessageStreamLimit)
        .map((data) {
          final messages = data
              .map((json) =>
                  Message.fromJson(json, currentUserId: currentUserId))
              .where(
                  (message) => !isUnsupportedWhatsAppCompanionMessage(message))
              .toList()
            ..sort(compareMessageTimelineOrder);
          return messages;
        });
  }

  /// Reads one immutable page immediately before [beforeSequence]. Realtime
  /// continues to own the latest page; callers merge this older snapshot into
  /// their current timeline so a late response can never replace live rows.
  Future<MessageHistoryPage> getMessagesBefore(
    String conversationId, {
    required int beforeSequence,
    int limit = historyPageSize,
  }) async {
    final safeLimit = limit.clamp(1, 200);
    final response = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .lt('message_sequence', beforeSequence)
        .order('message_sequence', ascending: false)
        .limit(safeLimit + 1);
    final rows = response as List<dynamic>;
    final hasMore = rows.length > safeLimit;
    final pageRows = rows.take(safeLimit).toList(growable: false);
    int? nextBeforeSequence;
    for (final row in pageRows) {
      final value = (row as Map)['message_sequence'];
      final sequence = value is int
          ? value
          : value is num
              ? value.toInt()
              : int.tryParse(value?.toString() ?? '');
      if (sequence != null &&
          (nextBeforeSequence == null || sequence < nextBeforeSequence)) {
        nextBeforeSequence = sequence;
      }
    }
    final messages = pageRows
        .map((row) => Message.fromJson(
              Map<String, dynamic>.from(row as Map),
              currentUserId: currentUserId,
            ))
        .where((message) => !isUnsupportedWhatsAppCompanionMessage(message))
        .toList()
      ..sort(compareMessageTimelineOrder);

    return MessageHistoryPage(
      messages: messages,
      hasMore: hasMore,
      nextBeforeSequence: nextBeforeSequence,
    );
  }

  /// Lightweight initial page used to warm the inbox before a thread opens.
  /// The live stream remains authoritative once the conversation is visible.
  Future<List<Message>> getRecentMessages(
    String conversationId, {
    int limit = 60,
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final response = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('message_sequence', ascending: false)
        .order('created_at', ascending: false)
        .limit(safeLimit);
    final messages = (response as List<dynamic>)
        .map((row) => Message.fromJson(
              Map<String, dynamic>.from(row as Map),
              currentUserId: currentUserId,
            ))
        .where((message) => !isUnsupportedWhatsAppCompanionMessage(message))
        .toList()
      ..sort(compareMessageTimelineOrder);
    return messages;
  }

  /// Reads only the messages whose provider evidence changed. RLS remains the
  /// tenant/user authorization boundary for the returned rows.
  Future<Map<String, Message>> getMessagesByIds(
    Iterable<String> messageIds,
  ) async {
    final ids = messageIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return const {};

    final response = await _client
        .from('messages')
        .select()
        .inFilter('id', ids.toList(growable: false));
    final messages = <String, Message>{};
    for (final row in response as List<dynamic>) {
      final message = Message.fromJson(
        Map<String, dynamic>.from(row as Map),
        currentUserId: currentUserId,
      );
      if (isUnsupportedWhatsAppCompanionMessage(message)) continue;
      messages[message.id] = message;
    }
    return messages;
  }

  /// Resolves the authoritative latest row for each affected conversation
  /// without reloading unrelated inbox rows or their context enrichment.
  Future<Map<String, Message>> getLatestMessagesForConversations(
    Iterable<String> conversationIds,
  ) async {
    final ids = conversationIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return const {};

    final rows = await Future.wait(
      ids.map(
        (conversationId) => _client
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .order('message_sequence', ascending: false)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
      ),
    );

    final latest = <String, Message>{};
    for (final row in rows) {
      if (row == null) continue;
      final message = Message.fromJson(
        Map<String, dynamic>.from(row),
        currentUserId: currentUserId,
      );
      if (isUnsupportedWhatsAppCompanionMessage(message)) continue;
      latest[message.conversationId] = message;
    }
    return latest;
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
    final normalizedContactName = contactName.trim();
    final normalizedCustomerId = _text(customerId);
    final (normalizedContextType, normalizedContextId) =
        _normalizedContextPair(contextType, contextId);
    final fingerprintParts = <Object?>[
      channel['id']?.toString(),
      normalizedPhone,
      normalizedContactName,
      normalizedCustomerId,
      normalizedContextType,
      normalizedContextId,
    ];
    return _commandIdempotencyStore.execute(
      namespace: MessagingCommandNamespace.whatsappSupportOpen,
      userId: userId,
      tenantId: tenantId,
      fingerprintParts: fingerprintParts,
      command: (commandKey) async {
        await _assertMessagingCommandSession(
          expectedUserId: userId,
          expectedTenantId: tenantId,
        );
        final result = await _client.rpc(
          'open_whatsapp_support_conversation',
          params: {
            'p_tenant_id': tenantId,
            'p_channel_id': channel['id'],
            'p_wa_id': normalizedPhone,
            'p_phone_number': normalizedPhone,
            'p_contact_name': normalizedContactName,
            'p_customer_id': normalizedCustomerId,
            'p_context_type': normalizedContextType,
            'p_context_id': normalizedContextId,
            'p_idempotency_key': commandKey,
          },
        );

        final data = Map<String, dynamic>.from(result as Map);
        final conversationId = data['conversation_id']?.toString();
        if (conversationId == null || conversationId.isEmpty) {
          throw Exception('No se pudo abrir la conversación de WhatsApp');
        }
        return conversationId;
      },
    );
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

  /// Listen for messaging changes that can affect inbox order or unread badges.
  RealtimeChannel subscribeToConversationsUpdates(
    VoidCallback onUpdate, {
    ValueChanged<MessageReceiptRealtimeUpdate>? onMessageReceiptUpdate,
  }) {
    final channelName =
        'public:messaging-inbox-${DateTime.now().microsecondsSinceEpoch}';
    void handleChange(PostgresChangePayload payload) {
      final receiptUpdate = _messageReceiptUpdate(payload);
      if (receiptUpdate != null) {
        onMessageReceiptUpdate?.call(receiptUpdate);
        return;
      }
      // Every other mutation may change lifecycle, participants, context,
      // ordering or unread evidence. ChatProvider coalesces this authoritative
      // refresh, so no state-bearing UPDATE is silently discarded here.
      onUpdate();
    }

    return _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: handleChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_participants',
          callback: handleChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: handleChange,
        )
        .subscribe();
  }

  MessageReceiptRealtimeUpdate? _messageReceiptUpdate(
    PostgresChangePayload payload,
  ) {
    if (payload.table != 'messages' ||
        payload.eventType != PostgresChangeEvent.update) {
      return null;
    }

    final record = payload.newRecord;
    final messageId = _text(record['id']);
    final conversationId = _text(record['conversation_id']);
    final externalStatus = _text(record['external_status']);
    if (messageId == null || conversationId == null || externalStatus == null) {
      return null;
    }

    return MessageReceiptRealtimeUpdate(
      conversationId: conversationId,
      messageId: messageId,
      externalStatus: externalStatus,
    );
  }

  /// Watches canonical conversation lifecycle changes, including status
  /// transitions that the high-volume employee inbox listener intentionally
  /// coalesces. RLS remains the authority over which rows a customer can see.
  RealtimeChannel subscribeToConversationLifecycleUpdates(
    VoidCallback onUpdate, {
    String? conversationId,
  }) {
    final channel = _client.channel(
      'public:conversation-lifecycle-${DateTime.now().microsecondsSinceEpoch}',
    );
    final normalizedId = conversationId?.trim();

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'conversations',
      filter: normalizedId == null || normalizedId.isEmpty
          ? null
          : PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: normalizedId,
            ),
      callback: (_) => onUpdate(),
    );
    return channel.subscribe();
  }

  Future<String> _createStaffSupportConversation({
    String? title,
    String? customerUserId,
    String? contextType,
    String? contextId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');
    final tenantId = (await TenantService().getTenantId())?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se pudo determinar el tenant activo');
    }
    final normalizedTitle = _text(title);
    final normalizedCustomerUserId = _text(customerUserId);
    final (normalizedContextType, normalizedContextId) =
        _normalizedContextPair(contextType, contextId);

    return _commandIdempotencyStore.execute(
      namespace: MessagingCommandNamespace.staffSupportCreate,
      userId: userId,
      tenantId: tenantId,
      fingerprintParts: [
        normalizedTitle,
        normalizedCustomerUserId,
        normalizedContextType,
        normalizedContextId,
      ],
      command: (commandKey) async {
        await _assertMessagingCommandSession(
          expectedUserId: userId,
          expectedTenantId: tenantId,
        );
        final result = await _client.rpc(
          'create_staff_support_conversation',
          params: {
            'p_tenant_id': tenantId,
            'p_title': normalizedTitle,
            'p_customer_user_id': normalizedCustomerUserId,
            'p_context_type': normalizedContextType,
            'p_context_id': normalizedContextId,
            'p_idempotency_key': commandKey,
          },
        );
        if (result is! Map) {
          throw Exception('El servidor no confirmó el chat de soporte');
        }
        final data = Map<String, dynamic>.from(result);
        final conversationId = _text(data['conversation_id']);
        if (conversationId == null || data['status'] != 'active') {
          throw Exception('El servidor no confirmó el chat de soporte');
        }
        return conversationId;
      },
    );
  }

  Future<String> _createStaffInternalConversation({
    required List<String> participantIds,
    required bool isGroup,
    String? title,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');
    final tenantId = (await TenantService().getTenantId())?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se pudo determinar el tenant activo');
    }
    final normalizedParticipantIds = participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != userId)
        .toSet()
        .toList()
      ..sort();
    final normalizedTitle = _text(title);

    return _commandIdempotencyStore.execute(
      namespace: MessagingCommandNamespace.staffInternalCreate,
      userId: userId,
      tenantId: tenantId,
      fingerprintParts: [
        isGroup,
        normalizedTitle,
        normalizedParticipantIds,
      ],
      command: (commandKey) async {
        await _assertMessagingCommandSession(
          expectedUserId: userId,
          expectedTenantId: tenantId,
        );
        final result = await _client.rpc(
          'create_staff_internal_conversation',
          params: {
            'p_tenant_id': tenantId,
            'p_participant_ids': normalizedParticipantIds,
            'p_title': normalizedTitle,
            'p_is_group': isGroup,
            'p_idempotency_key': commandKey,
          },
        );
        if (result is! Map) {
          throw Exception('El servidor no confirmó el chat interno');
        }
        final data = Map<String, dynamic>.from(result);
        final conversationId = _text(data['conversation_id']);
        if (conversationId == null ||
            data['status'] != 'active' ||
            data['is_group'] != isGroup) {
          throw Exception('El servidor no confirmó el chat interno');
        }
        return conversationId;
      },
    );
  }

  /// Create a staff-owned support conversation with a deliverable recipient.
  Future<String> createSupportTicket({
    required String title,
    String? contextType,
    String? contextId,
  }) async {
    return _createStaffSupportConversation(
      title: title,
      contextType: contextType,
      contextId: contextId,
    );
  }

  /// Create or get existing "Internal" chat with another employee
  Future<String> createInternalChat(String otherUserId) async {
    return _createStaffInternalConversation(
      participantIds: [otherUserId],
      isGroup: false,
    );
  }

  // ===========================================================================
  // GROUP & OUTBOUND CHAT METHODS
  // ===========================================================================

  /// Create a new internal group chat
  Future<String> createGroupChat({
    required List<String> participantIds,
    required String title,
  }) async {
    return _createStaffInternalConversation(
      participantIds: participantIds,
      title: title,
      isGroup: true,
    );
  }

  /// Create a new support chat initiated by Employee (Outbound)
  Future<String> createOutboundSupportChat(
    String customerUserId, {
    String? contextType,
    String? contextId,
  }) async {
    return _createStaffSupportConversation(
      customerUserId: customerUserId,
      contextType: contextType,
      contextId: contextId,
    );
  }

  /// Archives a conversation while preserving its messages, participants,
  /// provider receipts and workshop/accounting links as audit evidence.
  Future<void> archiveConversation(String conversationId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    debugPrint('📦 Archiving conversation: $conversationId');

    try {
      await _client.rpc('archive_conversation', params: {
        'p_conversation_id': conversationId,
      });
      debugPrint('✅ Conversation archived successfully');
    } catch (e) {
      debugPrint('❌ Error archiving conversation: $e');
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
    final (normalizedContextType, normalizedContextId) =
        _normalizedContextPair(contextType, contextId);

    debugPrint(
        '🔗 Linking conversation $conversationId to $normalizedContextType/$normalizedContextId');

    try {
      await _client.rpc('set_conversation_primary_context', params: {
        'p_conversation_id': conversationId,
        'p_context_type': normalizedContextType,
        'p_context_id': normalizedContextId,
      });

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
    final normalizedMessage = initialMessage.trim();
    final normalizedTenantId = tenantId.trim();
    final (normalizedContextType, normalizedContextId) =
        _normalizedContextPair(contextType, contextId);
    final fingerprintParts = <Object?>[
      normalizedMessage,
      normalizedContextType,
      normalizedContextId,
    ];
    final conversationId = await _commandIdempotencyStore.execute(
      namespace: MessagingCommandNamespace.customerSupportRequest,
      userId: userId,
      tenantId: normalizedTenantId,
      fingerprintParts: fingerprintParts,
      command: (commandKey) async {
        await _assertMessagingCommandSession(
          expectedUserId: userId,
          expectedTenantId: normalizedTenantId,
        );
        final result = await _client.rpc(
          'create_customer_support_request',
          params: {
            'p_tenant_id': normalizedTenantId,
            'p_initial_message': normalizedMessage,
            'p_context_type': normalizedContextType,
            'p_context_id': normalizedContextId,
            'p_idempotency_key': commandKey,
          },
        );
        final data = Map<String, dynamic>.from(result as Map);
        final conversationId = data['conversation_id']?.toString();
        if (conversationId == null || conversationId.isEmpty) {
          throw Exception('No se pudo crear la consulta de soporte');
        }
        return conversationId;
      },
    );

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

  /// Resolves the human contact configured on the canonical supplier profile.
  ///
  /// The WhatsApp binding intentionally keeps the supplier/company name for
  /// inbox identity. Supplier templates instead greet only the first name of
  /// the configured sales representative (or contact person) and fail closed
  /// when neither exists.
  Future<String?> getSupplierTemplateContactName({
    required String conversationId,
    String? supplierId,
  }) async {
    try {
      final tenantId = (await TenantService().getTenantId())?.trim();
      if (tenantId == null || tenantId.isEmpty) return null;

      var resolvedSupplierId = _text(supplierId);
      if (resolvedSupplierId == null) {
        final conversation = await _client
            .from('conversations')
            .select(
              'context_type, context_id, conversation_contexts(context_type, context_id, is_primary)',
            )
            .eq('tenant_id', tenantId)
            .eq('id', conversationId)
            .limit(1)
            .maybeSingle();

        if (conversation != null) {
          final (contextType, contextId) =
              _primaryContextFromConversation(conversation);
          if (contextType == 'supplier') {
            resolvedSupplierId = contextId;
          } else if (contextType == 'purchase_invoice' && contextId != null) {
            final purchase = await _client
                .from('purchase_invoices')
                .select('supplier_id')
                .eq('tenant_id', tenantId)
                .eq('id', contextId)
                .limit(1)
                .maybeSingle();
            resolvedSupplierId = _text(purchase?['supplier_id']);
          }
        }
      }

      if (resolvedSupplierId == null) return null;
      final supplier = await _client
          .from('suppliers')
          .select('sales_rep_name, contact_person')
          .eq('tenant_id', tenantId)
          .eq('id', resolvedSupplierId)
          .limit(1)
          .maybeSingle();
      return resolveSupplierMessagingContactName(supplier);
    } catch (error) {
      debugPrint(
        '⚠️ Error resolving supplier WhatsApp template contact: $error',
      );
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
      var lastInboundAt = binding?['last_inbound_at']?.toString();
      final lastOutboundAt = binding?['last_outbound_at']?.toString();

      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        return {
          'customer_id': customerId,
          'name': contactName,
          'phone': phoneNumber,
          'last_inbound_at': lastInboundAt,
          'last_outbound_at': lastOutboundAt,
        };
      }

      final lastFirstContactTemplateAt = await loadLastFirstContactTemplateAt();
      final lastInboundMessageAt = await loadLastInboundMessageAt();
      lastInboundAt = latestTimestamp(
        lastInboundAt,
        lastInboundMessageAt,
      );

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
