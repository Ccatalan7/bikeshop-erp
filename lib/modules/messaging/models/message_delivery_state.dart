import 'message.dart';

/// Provider-confirmed delivery state for an outbound external message.
///
/// A later customer reply is deliberately not considered proof that an older
/// message was read. Only the status persisted from the provider webhook may
/// advance a message to [MessageDeliveryStage.read].
enum MessageDeliveryStage {
  none,
  pending,
  queued,
  outcomeUnknown,
  accepted,
  sent,
  delivered,
  read,
  failed,
}

class MessageDeliveryState {
  const MessageDeliveryState({
    required this.stage,
    this.failureMessage,
    this.providerLabel,
  });

  final MessageDeliveryStage stage;
  final String? failureMessage;
  final String? providerLabel;

  bool get isVisible => stage != MessageDeliveryStage.none;

  static MessageDeliveryState fromMessage(Message message) {
    final providerLabel = _providerLabel(message.metadata);
    return fromValues(
      metadata: message.metadata,
      explicitStatus: message.metadata['external_status']?.toString(),
      isExternalTransport: providerLabel != null,
      providerLabel: providerLabel,
    );
  }

  static MessageDeliveryState fromConversationPreview({
    required Map<String, dynamic> metadata,
    required String? explicitStatus,
    required bool isExternalTransport,
    required String providerLabel,
  }) {
    return fromValues(
      metadata: metadata,
      explicitStatus: explicitStatus,
      isExternalTransport: isExternalTransport,
      providerLabel: providerLabel,
    );
  }

  static MessageDeliveryState fromValues({
    required Map<String, dynamic> metadata,
    required String? explicitStatus,
    required bool isExternalTransport,
    String? providerLabel,
  }) {
    if (!isExternalTransport) {
      return const MessageDeliveryState(stage: MessageDeliveryStage.none);
    }

    final status = _strongestConfirmedStatus(metadata, explicitStatus);
    if (status == null && metadata['pending'] == true) {
      return const MessageDeliveryState(stage: MessageDeliveryStage.pending);
    }
    final stage = switch (status) {
      'queued' => MessageDeliveryStage.queued,
      'accepted' => MessageDeliveryStage.accepted,
      'outcome_unknown' => MessageDeliveryStage.outcomeUnknown,
      'sent' => MessageDeliveryStage.sent,
      'delivered' => MessageDeliveryStage.delivered,
      'read' => MessageDeliveryStage.read,
      'failed' => MessageDeliveryStage.failed,
      _ => MessageDeliveryStage.none,
    };

    return MessageDeliveryState(
      stage: stage,
      providerLabel: providerLabel,
      failureMessage: switch (stage) {
        MessageDeliveryStage.failed =>
          _failureMessage(metadata, providerLabel: providerLabel),
        MessageDeliveryStage.outcomeUnknown =>
          'Resultado incierto: verifica la conversación antes de reenviar.',
        _ => null,
      },
    );
  }

  static String? _providerLabel(Map<String, dynamic> metadata) {
    final provider = metadata['external_provider']?.toString().toLowerCase() ??
        metadata['provider']?.toString().toLowerCase();
    final channel = metadata['channel']?.toString().toLowerCase();
    final externalId = metadata['external_message_id']?.toString();
    final resolved = provider ?? channel;
    return switch (resolved) {
      'whatsapp' => 'WhatsApp',
      'instagram' => 'Instagram',
      'facebook_messenger' => 'Messenger',
      _ when externalId?.startsWith('wamid.') == true => 'WhatsApp',
      _ when externalId?.trim().isNotEmpty == true => 'el proveedor',
      _ => null,
    };
  }

  static String? _strongestConfirmedStatus(
    Map<String, dynamic> metadata,
    String? explicitStatus,
  ) {
    final candidates = <String?>[
      explicitStatus,
      metadata['external_status']?.toString(),
      metadata['whatsapp_status']?.toString(),
      metadata['meta_status']?.toString(),
    ];

    String? strongestPositive;
    var positiveRank = 0;
    var hasFailure = false;
    var hasUnknownOutcome = false;
    var hasQueueReceipt = false;
    for (final raw in candidates) {
      final status = raw?.trim().toLowerCase();
      if (status == null || status.isEmpty) continue;
      if (status == 'queued') {
        hasQueueReceipt = true;
        continue;
      }
      if (status == 'failed') {
        hasFailure = true;
        continue;
      }
      if (status == 'outcome_unknown') {
        hasUnknownOutcome = true;
        continue;
      }
      final rank = switch (status) {
        'accepted' => 1,
        'sent' => 2,
        'delivered' => 3,
        'read' => 4,
        _ => 0,
      };
      if (rank > positiveRank) {
        positiveRank = rank;
        strongestPositive = status;
      }
    }

    // A late failure is valuable audit evidence, but it must not visually
    // erase a delivery/read receipt that the provider already confirmed.
    return strongestPositive ??
        (hasFailure
            ? 'failed'
            : hasUnknownOutcome
                ? 'outcome_unknown'
                : hasQueueReceipt
                    ? 'queued'
                    : null);
  }

  static String _failureMessage(
    Map<String, dynamic> metadata, {
    String? providerLabel,
  }) {
    final raw = metadata['external_error_message'] ??
        metadata['error_message'] ??
        metadata['error'];
    final detail = raw?.toString().trim();
    final provider = providerLabel ?? 'El proveedor';
    if (detail == null || detail.isEmpty) {
      return '$provider no pudo entregar este mensaje.';
    }
    return '$provider no pudo entregar este mensaje: $detail';
  }
}
