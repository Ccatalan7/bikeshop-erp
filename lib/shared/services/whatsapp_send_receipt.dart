enum WhatsAppDeliveryMethod {
  cloudApi,
  manualFallback,
  failed,
}

/// Immutable result for one WhatsApp dispatch attempt.
///
/// Keeping every provider and persistence receipt on the returned value avoids
/// cross-talk when the process-wide [WhatsAppService] handles concurrent sends.
class WhatsAppSendReceipt {
  static const int reengagementErrorCode = 131047;
  static const int expiredAccessTokenErrorCode = 190;

  final WhatsAppDeliveryMethod deliveryMethod;
  final int? errorCode;
  final bool usedFirstContactTemplate;
  final String? resolvedMessageText;
  final String? messageId;
  final String? externalMessageId;
  final String? deliveryStrategy;
  final bool unsafeToFallback;

  /// Database acceptance is durable even before Meta supplies its identifier.
  final bool isQueued;
  final String externalStatus;

  const WhatsAppSendReceipt({
    required this.deliveryMethod,
    this.errorCode,
    this.usedFirstContactTemplate = false,
    this.resolvedMessageText,
    this.messageId,
    this.externalMessageId,
    this.deliveryStrategy,
    this.unsafeToFallback = false,
    this.isQueued = false,
    this.externalStatus = 'accepted',
  });

  bool get isSuccess =>
      deliveryMethod == WhatsAppDeliveryMethod.cloudApi ||
      deliveryMethod == WhatsAppDeliveryMethod.manualFallback;

  bool get isDurable =>
      deliveryMethod == WhatsAppDeliveryMethod.cloudApi &&
      messageId != null &&
      messageId!.isNotEmpty &&
      (isQueued ||
          (externalMessageId != null && externalMessageId!.isNotEmpty));

  bool get errorRequiresServerFix => errorCode == expiredAccessTokenErrorCode;

  bool get errorRequiresCustomerReply => errorCode == reengagementErrorCode;

  WhatsAppSendReceipt copyWith({
    WhatsAppDeliveryMethod? deliveryMethod,
    int? errorCode,
    bool clearErrorCode = false,
    bool? usedFirstContactTemplate,
    String? resolvedMessageText,
    String? messageId,
    String? externalMessageId,
    String? deliveryStrategy,
    bool? unsafeToFallback,
    bool? isQueued,
    String? externalStatus,
  }) {
    return WhatsAppSendReceipt(
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
      errorCode: clearErrorCode ? null : errorCode ?? this.errorCode,
      usedFirstContactTemplate:
          usedFirstContactTemplate ?? this.usedFirstContactTemplate,
      resolvedMessageText: resolvedMessageText ?? this.resolvedMessageText,
      messageId: messageId ?? this.messageId,
      externalMessageId: externalMessageId ?? this.externalMessageId,
      deliveryStrategy: deliveryStrategy ?? this.deliveryStrategy,
      unsafeToFallback: unsafeToFallback ?? this.unsafeToFallback,
      isQueued: isQueued ?? this.isQueued,
      externalStatus: externalStatus ?? this.externalStatus,
    );
  }
}

bool isDurableWhatsAppSendPayload(Object? data) {
  if (data is! Map || data['ok'] != true || data['accepted'] != true) {
    return false;
  }
  final messageId = data['message_id']?.toString().trim() ?? '';
  final externalMessageId =
      data['external_message_id']?.toString().trim() ?? '';
  return messageId.isNotEmpty &&
      (externalMessageId.isNotEmpty ||
          (data['queued'] == true &&
              const {
                'queued',
                'accepted',
                'sent',
                'delivered',
                'read',
                'failed',
                'outcome_unknown'
              }.contains(data['external_status'])));
}

WhatsAppSendReceipt parseDurableWhatsAppSendReceipt(
  Object? data, {
  String? resolvedMessageText,
}) {
  if (!isDurableWhatsAppSendPayload(data)) {
    throw const FormatException('Malformed durable WhatsApp send receipt');
  }
  final payload = data! as Map;
  return WhatsAppSendReceipt(
    deliveryMethod: WhatsAppDeliveryMethod.cloudApi,
    resolvedMessageText: resolvedMessageText,
    messageId: payload['message_id']!.toString().trim(),
    externalMessageId: payload['external_message_id']?.toString().trim(),
    deliveryStrategy: payload['delivery_strategy']?.toString().trim(),
    isQueued: payload['queued'] == true,
    externalStatus: payload['external_status']?.toString() ?? 'accepted',
    unsafeToFallback: payload['queued'] == true,
  );
}

bool isUnsafeWhatsAppManualFallback(Object? data) {
  if (data is! Map) return false;
  return data['provider_accepted'] == true ||
      data['outcome_unknown'] == true ||
      data['retry_safe'] == false;
}
