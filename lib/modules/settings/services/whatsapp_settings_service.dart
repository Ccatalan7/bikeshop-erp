import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/whatsapp_service.dart';

class WhatsAppChannelStatus {
  final String id;
  final String? displayName;
  final String? displayPhoneNumber;
  final String phoneNumberId;
  final String? businessAccountId;
  final bool isActive;
  final DateTime? lastInboundAt;
  final DateTime? lastOutboundAt;
  final DateTime? lastWebhookAt;
  final int trackedConversations;

  const WhatsAppChannelStatus({
    required this.id,
    required this.displayName,
    required this.displayPhoneNumber,
    required this.phoneNumberId,
    required this.businessAccountId,
    required this.isActive,
    required this.lastInboundAt,
    required this.lastOutboundAt,
    required this.lastWebhookAt,
    required this.trackedConversations,
  });

  WhatsAppChannelStatus copyWith({bool? isActive}) {
    return WhatsAppChannelStatus(
      id: id,
      displayName: displayName,
      displayPhoneNumber: displayPhoneNumber,
      phoneNumberId: phoneNumberId,
      businessAccountId: businessAccountId,
      isActive: isActive ?? this.isActive,
      lastInboundAt: lastInboundAt,
      lastOutboundAt: lastOutboundAt,
      lastWebhookAt: lastWebhookAt,
      trackedConversations: trackedConversations,
    );
  }
}

class WhatsAppBillingWindowEstimate {
  final String phoneNumber;
  final String? contactName;
  final String category;
  final String templateName;
  final DateTime openedAt;
  final DateTime expiresAt;
  final double estimatedCostUsd;
  final String sourceMessageId;

  const WhatsAppBillingWindowEstimate({
    required this.phoneNumber,
    required this.contactName,
    required this.category,
    required this.templateName,
    required this.openedAt,
    required this.expiresAt,
    required this.estimatedCostUsd,
    required this.sourceMessageId,
  });

  bool get isActive => DateTime.now().toUtc().isBefore(expiresAt.toUtc());
}

class WhatsAppSettingsPreferences {
  final String firstContactTemplateName;
  final String firstContactTemplateLanguage;
  final double utilityConversationUsd;

  const WhatsAppSettingsPreferences({
    required this.firstContactTemplateName,
    required this.firstContactTemplateLanguage,
    required this.utilityConversationUsd,
  });

  factory WhatsAppSettingsPreferences.defaults() {
    return const WhatsAppSettingsPreferences(
      firstContactTemplateName: WhatsAppService.firstContactTemplateName,
      firstContactTemplateLanguage:
          WhatsAppService.firstContactTemplateLanguage,
      utilityConversationUsd:
          WhatsAppSettingsService.defaultUtilityConversationUsd,
    );
  }

  WhatsAppSettingsPreferences copyWith({
    String? firstContactTemplateName,
    String? firstContactTemplateLanguage,
    double? utilityConversationUsd,
  }) {
    return WhatsAppSettingsPreferences(
      firstContactTemplateName:
          firstContactTemplateName ?? this.firstContactTemplateName,
      firstContactTemplateLanguage:
          firstContactTemplateLanguage ?? this.firstContactTemplateLanguage,
      utilityConversationUsd:
          utilityConversationUsd ?? this.utilityConversationUsd,
    );
  }
}

class WhatsAppSettingsSnapshot {
  final String tenantId;
  final List<WhatsAppChannelStatus> channels;
  final DateTime? lastWebhookAt;
  final DateTime? lastOutboundAt;
  final DateTime? lastTemplateAt;
  final int webhookEvents24h;
  final int inboundEvents24h;
  final int statusEvents24h;
  final int outboundMessages30d;
  final int templateMessages30d;
  final int deliveredMessages30d;
  final int readMessages30d;
  final int failedMessages30d;
  final int activeCustomerServiceWindows;
  final int openBillableWindows;
  final int billableWindowsToday;
  final Map<String, int> templateMessagesByName;
  final List<WhatsAppBillingWindowEstimate> billableWindows30d;
  final double estimatedCost30dUsd;

  const WhatsAppSettingsSnapshot({
    required this.tenantId,
    required this.channels,
    required this.lastWebhookAt,
    required this.lastOutboundAt,
    required this.lastTemplateAt,
    required this.webhookEvents24h,
    required this.inboundEvents24h,
    required this.statusEvents24h,
    required this.outboundMessages30d,
    required this.templateMessages30d,
    required this.deliveredMessages30d,
    required this.readMessages30d,
    required this.failedMessages30d,
    required this.activeCustomerServiceWindows,
    required this.openBillableWindows,
    required this.billableWindowsToday,
    required this.templateMessagesByName,
    required this.billableWindows30d,
    required this.estimatedCost30dUsd,
  });

  bool get hasActiveChannel => channels.any((channel) => channel.isActive);
}

class WhatsAppSettingsPanelData {
  final WhatsAppSettingsSnapshot snapshot;
  final WhatsAppSettingsPreferences preferences;

  const WhatsAppSettingsPanelData({
    required this.snapshot,
    required this.preferences,
  });
}

class WhatsAppSettingsService {
  static const double defaultUtilityConversationUsd = 0.04;
  static const String utilityConversationUsdKey =
      'whatsapp_utility_conversation_usd';

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<WhatsAppSettingsPanelData> loadPanelData() async {
    final tenantId = await _requireTenantId();
    final preferences = await _loadPreferences(tenantId);
    final snapshot = await _loadSnapshot(tenantId, preferences);

    return WhatsAppSettingsPanelData(
      snapshot: snapshot,
      preferences: preferences,
    );
  }

  Future<WhatsAppSettingsSnapshot> loadSnapshot() async {
    final panelData = await loadPanelData();
    return panelData.snapshot;
  }

  Future<void> savePreferences(WhatsAppSettingsPreferences preferences) async {
    final tenantId = await _requireTenantId();

    await Future.wait([
      _upsertCompanySetting(
        tenantId: tenantId,
        key: utilityConversationUsdKey,
        value: preferences.utilityConversationUsd.toStringAsFixed(4),
      ),
      _upsertCompanySetting(
        tenantId: tenantId,
        key: WhatsAppService.firstContactTemplateNameSettingKey,
        value: preferences.firstContactTemplateName,
      ),
      _upsertCompanySetting(
        tenantId: tenantId,
        key: WhatsAppService.firstContactTemplateLanguageSettingKey,
        value: preferences.firstContactTemplateLanguage,
      ),
    ]);
  }

  Future<void> toggleChannelStatus({
    required String channelId,
    required bool isActive,
  }) async {
    final tenantId = await _requireTenantId();

    await _supabase
        .from('whatsapp_channels')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('tenant_id', tenantId)
        .eq('id', channelId);
  }

  Future<WhatsAppSettingsPreferences> _loadPreferences(String tenantId) async {
    try {
      final rows = await _supabase
          .from('company_settings')
          .select('key, value')
          .eq('tenant_id', tenantId)
          .inFilter('key', [
        utilityConversationUsdKey,
        WhatsAppService.firstContactTemplateNameSettingKey,
        WhatsAppService.firstContactTemplateLanguageSettingKey,
      ]);

      var preferences = WhatsAppSettingsPreferences.defaults();

      for (final row in rows) {
        final key = row['key']?.toString();
        final value = row['value']?.toString().trim();
        if (key == null || value == null || value.isEmpty) {
          continue;
        }

        if (key == utilityConversationUsdKey) {
          final parsed = double.tryParse(value.replaceAll(',', '.'));
          if (parsed != null && parsed >= 0) {
            preferences = preferences.copyWith(utilityConversationUsd: parsed);
          }
        } else if (key == WhatsAppService.firstContactTemplateNameSettingKey) {
          preferences = preferences.copyWith(firstContactTemplateName: value);
        } else if (key ==
            WhatsAppService.firstContactTemplateLanguageSettingKey) {
          preferences = preferences.copyWith(
            firstContactTemplateLanguage: value,
          );
        }
      }

      return preferences;
    } catch (error) {
      debugPrint(
        '⚠️ [WhatsAppSettingsService] Falling back to default preferences: $error',
      );
      return WhatsAppSettingsPreferences.defaults();
    }
  }

  Future<WhatsAppSettingsSnapshot> _loadSnapshot(
    String tenantId,
    WhatsAppSettingsPreferences preferences,
  ) async {
    final now = DateTime.now().toUtc();
    final since24h = now.subtract(const Duration(hours: 24));
    final since30d = now.subtract(const Duration(days: 30));
    final startOfToday = DateTime.utc(now.year, now.month, now.day);

    final results = await Future.wait([
      _supabase
          .from('whatsapp_channels')
          .select(
            'id, display_name, display_phone_number, phone_number_id, business_account_id, is_active',
          )
          .eq('tenant_id', tenantId)
          .order('is_active', ascending: false)
          .order('created_at', ascending: false),
      _supabase
          .from('whatsapp_conversation_bindings')
          .select(
            'channel_id, external_phone_number, contact_name, last_inbound_at, last_outbound_at',
          )
          .eq('tenant_id', tenantId),
      _supabase
          .from('whatsapp_webhook_events')
          .select('channel_id, event_type, direction, created_at')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(400),
      _supabase
          .from('messages')
          .select(
            'id, content, metadata, created_at, external_status',
          )
          .eq('tenant_id', tenantId)
          .eq('external_provider', 'whatsapp')
          .eq('message_direction', 'outbound')
          .gte('created_at', since30d.toIso8601String())
          .order('created_at', ascending: false)
          .limit(800),
    ]);

    final channelsRaw = List<Map<String, dynamic>>.from(results[0] as List);
    final bindingsRaw = List<Map<String, dynamic>>.from(results[1] as List);
    final webhooksRaw = List<Map<String, dynamic>>.from(results[2] as List);
    final outboundRaw = List<Map<String, dynamic>>.from(results[3] as List);

    final bindingsByChannel = <String, List<Map<String, dynamic>>>{};
    for (final binding in bindingsRaw) {
      final channelId = binding['channel_id']?.toString();
      if (channelId == null || channelId.isEmpty) {
        continue;
      }
      bindingsByChannel.putIfAbsent(channelId, () => []).add(binding);
    }

    final webhooksByChannel = <String, List<Map<String, dynamic>>>{};
    for (final event in webhooksRaw) {
      final channelId = event['channel_id']?.toString();
      if (channelId == null || channelId.isEmpty) {
        continue;
      }
      webhooksByChannel.putIfAbsent(channelId, () => []).add(event);
    }

    final channels = channelsRaw.map((channel) {
      final channelId = channel['id']?.toString() ?? '';
      final channelBindings = bindingsByChannel[channelId] ?? const [];
      final channelWebhooks = webhooksByChannel[channelId] ?? const [];

      return WhatsAppChannelStatus(
        id: channelId,
        displayName: channel['display_name']?.toString(),
        displayPhoneNumber: channel['display_phone_number']?.toString(),
        phoneNumberId: channel['phone_number_id']?.toString() ?? '',
        businessAccountId: channel['business_account_id']?.toString(),
        isActive: channel['is_active'] == true,
        lastInboundAt: _maxDate(
          channelBindings
              .map((binding) => _parseDateTime(binding['last_inbound_at'])),
        ),
        lastOutboundAt: _maxDate(
          channelBindings
              .map((binding) => _parseDateTime(binding['last_outbound_at'])),
        ),
        lastWebhookAt: _maxDate(
          channelWebhooks.map((event) => _parseDateTime(event['created_at'])),
        ),
        trackedConversations: channelBindings.length,
      );
    }).toList();

    final webhookEvents24h = webhooksRaw.where((event) {
      final createdAt = _parseDateTime(event['created_at']);
      return createdAt != null && !createdAt.isBefore(since24h);
    }).toList();

    final outboundMessages = outboundRaw.map(_toOutboundMessage).toList();
    final templateMessages = outboundMessages.where((message) {
      final outboundType = message.metadata['outbound_type']?.toString();
      return outboundType == 'template';
    }).toList();

    final billableWindows =
        _buildBillableWindows(templateMessages, preferences);

    final templateMessagesByName = <String, int>{};
    for (final message in templateMessages) {
      final templateName = _extractTemplateName(message.metadata) ?? 'template';
      templateMessagesByName.update(
        templateName,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final activeCustomerServiceWindows = bindingsRaw.where((binding) {
      final lastInboundAt = _parseDateTime(binding['last_inbound_at']);
      return lastInboundAt != null && !lastInboundAt.isBefore(since24h);
    }).length;

    final deliveredMessages30d = outboundMessages.where((message) {
      return message.externalStatus == 'delivered';
    }).length;

    final readMessages30d = outboundMessages.where((message) {
      return message.externalStatus == 'read';
    }).length;

    final failedMessages30d = outboundMessages.where((message) {
      return message.externalStatus == 'failed';
    }).length;

    return WhatsAppSettingsSnapshot(
      tenantId: tenantId,
      channels: channels,
      lastWebhookAt: _maxDate(
        webhooksRaw.map((event) => _parseDateTime(event['created_at'])),
      ),
      lastOutboundAt: _maxDate(
        outboundMessages.map((message) => message.createdAt),
      ),
      lastTemplateAt: _maxDate(
        templateMessages.map((message) => message.createdAt),
      ),
      webhookEvents24h: webhookEvents24h.length,
      inboundEvents24h: webhookEvents24h
          .where((event) => event['direction'] == 'inbound')
          .length,
      statusEvents24h: webhookEvents24h
          .where((event) => event['event_type'] == 'status')
          .length,
      outboundMessages30d: outboundMessages.length,
      templateMessages30d: templateMessages.length,
      deliveredMessages30d: deliveredMessages30d,
      readMessages30d: readMessages30d,
      failedMessages30d: failedMessages30d,
      activeCustomerServiceWindows: activeCustomerServiceWindows,
      openBillableWindows:
          billableWindows.where((window) => window.isActive).length,
      billableWindowsToday: billableWindows
          .where((window) => !window.openedAt.isBefore(startOfToday))
          .length,
      templateMessagesByName: templateMessagesByName,
      billableWindows30d: billableWindows,
      estimatedCost30dUsd: billableWindows.fold<double>(
        0,
        (total, window) => total + window.estimatedCostUsd,
      ),
    );
  }

  Future<void> _upsertCompanySetting({
    required String tenantId,
    required String key,
    required String value,
  }) async {
    final trimmedValue = value.trim();
    final existing = await _supabase
        .from('company_settings')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('key', key)
        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('company_settings')
          .update({
            'value': trimmedValue,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('tenant_id', tenantId)
          .eq('key', key);
      return;
    }

    await _supabase.from('company_settings').insert({
      'tenant_id': tenantId,
      'key': key,
      'value': trimmedValue,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> _requireTenantId() async {
    final tenantId = await TenantService().getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se pudo resolver el tenant actual.');
    }
    return tenantId;
  }

  List<WhatsAppBillingWindowEstimate> _buildBillableWindows(
    List<_OutboundWhatsAppMessage> templateMessages,
    WhatsAppSettingsPreferences preferences,
  ) {
    final sortedMessages = [...templateMessages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final lastWindowByKey = <String, WhatsAppBillingWindowEstimate>{};
    final windows = <WhatsAppBillingWindowEstimate>[];

    for (final message in sortedMessages) {
      if (message.externalStatus == 'failed') {
        continue;
      }

      final phoneNumber = _extractPhoneNumber(message.metadata);
      if (phoneNumber == null || phoneNumber.isEmpty) {
        continue;
      }

      final templateName = _extractTemplateName(message.metadata) ?? 'template';
      final category = _inferTemplateCategory(message.metadata, templateName);
      final unitCost = _estimatedUnitCostForCategory(category, preferences);
      if (unitCost <= 0) {
        continue;
      }

      final key = '$phoneNumber::$category';
      final previousWindow = lastWindowByKey[key];
      if (previousWindow != null &&
          !message.createdAt.isAfter(previousWindow.expiresAt)) {
        continue;
      }

      final window = WhatsAppBillingWindowEstimate(
        phoneNumber: phoneNumber,
        contactName: _extractContactName(message.metadata),
        category: category,
        templateName: templateName,
        openedAt: message.createdAt,
        expiresAt: message.createdAt.add(const Duration(hours: 24)),
        estimatedCostUsd: unitCost,
        sourceMessageId: message.id,
      );

      lastWindowByKey[key] = window;
      windows.add(window);
    }

    return windows.reversed.toList();
  }

  _OutboundWhatsAppMessage _toOutboundMessage(Map<String, dynamic> row) {
    final rawMetadata = row['metadata'];
    final metadata = rawMetadata is Map
        ? Map<String, dynamic>.from(rawMetadata)
        : <String, dynamic>{};

    return _OutboundWhatsAppMessage(
      id: row['id']?.toString() ?? '',
      createdAt: _parseDateTime(row['created_at']) ?? DateTime.now().toUtc(),
      externalStatus: row['external_status']?.toString(),
      metadata: metadata,
    );
  }

  DateTime? _parseDateTime(dynamic raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  DateTime? _maxDate(Iterable<DateTime?> values) {
    DateTime? latest;
    for (final value in values) {
      if (value == null) {
        continue;
      }
      if (latest == null || value.isAfter(latest)) {
        latest = value;
      }
    }
    return latest;
  }

  String? _extractPhoneNumber(Map<String, dynamic> metadata) {
    final direct = metadata['external_wa_id']?.toString();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final phone = metadata['phone_number']?.toString();
    if (phone != null && phone.isNotEmpty) {
      return phone;
    }

    final graphPayload = metadata['graph_payload'];
    if (graphPayload is Map) {
      final payloadMap = Map<String, dynamic>.from(graphPayload);
      final to = payloadMap['to']?.toString();
      if (to != null && to.isNotEmpty) {
        return to;
      }
    }

    return null;
  }

  String? _extractContactName(Map<String, dynamic> metadata) {
    final direct = metadata['contact_name']?.toString().trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final recipient = metadata['recipient_name']?.toString().trim();
    if (recipient != null && recipient.isNotEmpty) {
      return recipient;
    }

    final graphPayload = metadata['graph_payload'];
    if (graphPayload is Map) {
      final payloadMap = Map<String, dynamic>.from(graphPayload);
      final name = payloadMap['contactName']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }

    return null;
  }

  String? _extractTemplateName(Map<String, dynamic> metadata) {
    final direct = metadata['template_name']?.toString().trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final graphPayload = metadata['graph_payload'];
    if (graphPayload is Map) {
      final payloadMap = Map<String, dynamic>.from(graphPayload);
      final template = payloadMap['template'];
      if (template is Map) {
        final templateMap = Map<String, dynamic>.from(template);
        final name = templateMap['name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          return name;
        }
      }
    }

    return null;
  }

  String _inferTemplateCategory(
    Map<String, dynamic> metadata,
    String templateName,
  ) {
    final explicitCategory = metadata['template_category']?.toString().trim();
    if (explicitCategory != null && explicitCategory.isNotEmpty) {
      return explicitCategory;
    }

    final conversationCategory =
        metadata['conversation_category']?.toString().trim();
    if (conversationCategory != null && conversationCategory.isNotEmpty) {
      return conversationCategory;
    }

    final templatePurpose = metadata['template_purpose']?.toString();
    if (templatePurpose == 'first_contact' ||
        templateName == WhatsAppService.firstContactTemplateName) {
      return 'utility';
    }

    final normalizedName = templateName.toLowerCase();
    if (normalizedName.contains('auth')) {
      return 'authentication';
    }
    if (normalizedName.contains('promo') || normalizedName.contains('market')) {
      return 'marketing';
    }
    return 'utility';
  }

  double _estimatedUnitCostForCategory(
    String category,
    WhatsAppSettingsPreferences preferences,
  ) {
    switch (category) {
      case 'utility':
      case 'authentication':
      case 'marketing':
      default:
        return preferences.utilityConversationUsd;
    }
  }
}

class _OutboundWhatsAppMessage {
  final String id;
  final DateTime createdAt;
  final String? externalStatus;
  final Map<String, dynamic> metadata;

  const _OutboundWhatsAppMessage({
    required this.id,
    required this.createdAt,
    required this.externalStatus,
    required this.metadata,
  });
}
