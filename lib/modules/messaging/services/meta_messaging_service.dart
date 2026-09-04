import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message.dart';
import '../../../shared/services/supabase_functions_region.dart';

enum MetaSendOutcome { accepted, rejected, outcomeUnknown }

/// Immutable result for one Instagram or Facebook Messenger dispatch.
///
/// `accepted` means Meta returned an external message ID and the Edge Function
/// durably stored the corresponding ERP message. It does not imply delivery or
/// read; those stages require later provider webhook evidence.
class MetaSendReceipt {
  const MetaSendReceipt({
    required this.outcome,
    this.attemptId,
    this.messageId,
    this.externalMessageId,
    this.externalStatus,
    this.errorCode,
    this.errorMessage,
  });

  final MetaSendOutcome outcome;
  final String? attemptId;
  final String? messageId;
  final String? externalMessageId;
  final String? externalStatus;
  final String? errorCode;
  final String? errorMessage;

  bool get isDurable =>
      outcome == MetaSendOutcome.accepted &&
      messageId?.isNotEmpty == true &&
      externalMessageId?.isNotEmpty == true;

  bool get replyWindowClosed => errorCode == 'reply_window_closed';
}

bool isDurableMetaSendPayload(Object? data) {
  if (data is! Map || data['ok'] != true || data['accepted'] != true) {
    return false;
  }
  final messageId = data['message_id']?.toString().trim() ?? '';
  final externalMessageId =
      data['external_message_id']?.toString().trim() ?? '';
  return messageId.isNotEmpty && externalMessageId.isNotEmpty;
}

Map<dynamic, dynamic>? _decodePayloadMap(Object? data) {
  if (data is Map) return data;
  if (data is! String || data.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(data);
    return decoded is Map ? decoded : null;
  } catch (_) {
    return null;
  }
}

MetaSendReceipt parseMetaSendPayload(Object? data) {
  final payload = _decodePayloadMap(data) ?? const <String, dynamic>{};
  final error = payload['error'] is Map ? payload['error'] as Map : const {};
  String? text(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  final common = (
    attemptId: text(payload['attempt_id']),
    messageId: text(payload['message_id']),
    externalMessageId: text(payload['external_message_id']),
    externalStatus: text(payload['external_status']),
    errorCode: text(error['code']) ?? text(payload['error_code']),
    errorMessage: text(error['message']) ?? text(payload['error_message']),
  );

  if (isDurableMetaSendPayload(payload)) {
    return MetaSendReceipt(
      outcome: MetaSendOutcome.accepted,
      attemptId: common.attemptId,
      messageId: common.messageId,
      externalMessageId: common.externalMessageId,
      externalStatus: common.externalStatus ?? 'accepted',
    );
  }

  // Only the complete backend rejection receipt proves that Meta was not
  // called or explicitly rejected the request. Missing flags, gateways that
  // return text/HTML, and malformed JSON are all ambiguous: retrying them can
  // duplicate a provider-accepted message.
  final explicitlyRejected = payload['retry_safe'] == true &&
      payload['provider_accepted'] == false &&
      payload['outcome_unknown'] == false;
  final unstructuredError = data is String && payload.isEmpty
      ? text(data.length > 500 ? data.substring(0, 500) : data)
      : null;
  return MetaSendReceipt(
    outcome: explicitlyRejected
        ? MetaSendOutcome.rejected
        : MetaSendOutcome.outcomeUnknown,
    attemptId: common.attemptId,
    messageId: common.messageId,
    externalMessageId: common.externalMessageId,
    externalStatus: common.externalStatus,
    errorCode: common.errorCode,
    errorMessage: common.errorMessage ?? unstructuredError,
  );
}

enum MetaOutboundAttemptState {
  prepared('prepared'),
  preflightFailed('preflight_failed'),
  outcomeUnknown('outcome_unknown'),
  providerAccepted('provider_accepted'),
  providerRejected('provider_rejected'),
  finalized('finalized');

  const MetaOutboundAttemptState(this.wireName);

  final String wireName;

  static MetaOutboundAttemptState? fromWire(Object? value) {
    final wireName = value?.toString().trim().toLowerCase();
    for (final state in values) {
      if (state.wireName == wireName) return state;
    }
    return null;
  }
}

/// Durable server-side receipt for an outbound Meta command.
class MetaOutboundSendReceipt {
  const MetaOutboundSendReceipt({
    required this.attemptId,
    required this.conversationId,
    required this.actorId,
    required this.clientMessageId,
    required this.state,
    required this.messageText,
    required this.createdAt,
    required this.updatedAt,
    this.messageId,
    this.externalMessageId,
    this.errorCode,
    this.errorMessage,
    this.providerAcceptedAt,
    this.finalizedAt,
  });

  final String attemptId;
  final String conversationId;
  final String actorId;
  final String clientMessageId;
  final MetaOutboundAttemptState state;
  final String messageText;
  final String? messageId;
  final String? externalMessageId;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? providerAcceptedAt;
  final DateTime? finalizedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get shouldRecover => state != MetaOutboundAttemptState.finalized;

  static MetaOutboundSendReceipt? fromJson(Map<dynamic, dynamic> json) {
    String? textValue(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    DateTime? dateValue(Object? value) {
      final text = textValue(value);
      return text == null ? null : DateTime.tryParse(text)?.toLocal();
    }

    final attemptId = textValue(json['attempt_id']);
    final conversationId = textValue(json['conversation_id']);
    final actorId = textValue(json['actor_id']);
    final clientMessageId = textValue(json['client_message_id']);
    final state = MetaOutboundAttemptState.fromWire(json['state']);
    final messageText = textValue(json['message_text']);
    final createdAt = dateValue(json['created_at']);
    final updatedAt = dateValue(json['updated_at']);
    if (attemptId == null ||
        conversationId == null ||
        actorId == null ||
        clientMessageId == null ||
        state == null ||
        messageText == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }

    return MetaOutboundSendReceipt(
      attemptId: attemptId,
      conversationId: conversationId,
      actorId: actorId,
      clientMessageId: clientMessageId,
      state: state,
      messageText: messageText,
      messageId: textValue(json['message_id']),
      externalMessageId: textValue(json['external_message_id']),
      errorCode: textValue(json['error_code']),
      errorMessage: textValue(json['error_message']),
      providerAcceptedAt: dateValue(json['provider_accepted_at']),
      finalizedAt: dateValue(json['finalized_at']),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Least-privilege transport state exposed to authenticated ERP users.
///
/// External Meta account and user identifiers intentionally never cross this
/// boundary. `canReply` also reflects whether the configured channel is active;
/// the client still validates the timestamp defensively before enabling send.
class MetaConversationTransport {
  const MetaConversationTransport({
    required this.provider,
    required this.replyWindowExpiresAt,
    required this.canReply,
  });

  final String provider;
  final DateTime? replyWindowExpiresAt;
  final bool canReply;

  static MetaConversationTransport? fromJson(Map<dynamic, dynamic> json) {
    final provider = json['provider']?.toString().trim().toLowerCase();
    final rawExpiry = json['reply_window_expires_at']?.toString().trim();
    final canReply = json['can_reply'];
    final expiry = rawExpiry == null || rawExpiry.isEmpty
        ? null
        : DateTime.tryParse(rawExpiry)?.toLocal();
    if ((provider != 'instagram' && provider != 'facebook_messenger') ||
        canReply is! bool ||
        (rawExpiry?.isNotEmpty == true && expiry == null) ||
        (canReply && expiry == null)) {
      return null;
    }
    return MetaConversationTransport(
      provider: provider!,
      replyWindowExpiresAt: expiry,
      canReply: canReply,
    );
  }
}

/// Rebuilds a visible, non-sendable bubble from an exact durable attempt.
///
/// No state is promoted to sent/delivered/read here. `provider_accepted` is
/// shown as accepted only when its receipt includes Meta's external ID. A
/// recovered `prepared` receipt is already outside the live request context,
/// so it is ambiguous rather than an indefinitely pending send.
Message buildRecoveredMetaAttemptMessage({
  required MetaOutboundSendReceipt receipt,
  required String channel,
  required String? currentUserId,
  String? optimisticMessageId,
  Map<String, dynamic> existingMetadata = const {},
}) {
  final hasProviderAcceptance =
      receipt.state == MetaOutboundAttemptState.providerAccepted &&
          receipt.externalMessageId != null;
  final externalStatus = switch (receipt.state) {
    MetaOutboundAttemptState.prepared => 'outcome_unknown',
    MetaOutboundAttemptState.outcomeUnknown => 'outcome_unknown',
    MetaOutboundAttemptState.providerAccepted =>
      hasProviderAcceptance ? 'accepted' : 'outcome_unknown',
    MetaOutboundAttemptState.preflightFailed ||
    MetaOutboundAttemptState.providerRejected =>
      'failed',
    MetaOutboundAttemptState.finalized => null,
  };

  return Message(
    id: optimisticMessageId ?? 'meta-attempt-${receipt.attemptId}',
    conversationId: receipt.conversationId,
    senderId: receipt.actorId,
    content: receipt.messageText,
    type: 'text',
    metadata: {
      ...existingMetadata,
      'channel': channel,
      'provider': channel,
      'external_provider': channel,
      'message_direction': 'outbound',
      'client_message_id': receipt.clientMessageId,
      'provider_attempt_id': receipt.attemptId,
      'meta_attempt_state': receipt.state.wireName,
      'recovered_outbound_attempt': true,
      'attempt_receipt_durable': true,
      'server_ack_durable': false,
      'pending': false,
      'retry_disabled':
          receipt.state != MetaOutboundAttemptState.preflightFailed &&
              receipt.state != MetaOutboundAttemptState.providerRejected,
      if (externalStatus != null) 'external_status': externalStatus,
      if (externalStatus == 'outcome_unknown') 'outcome_unknown': true,
      if (receipt.messageId != null) 'server_message_id': receipt.messageId,
      if (receipt.externalMessageId != null)
        'external_message_id': receipt.externalMessageId,
      if (receipt.errorCode != null) 'external_error_code': receipt.errorCode,
      if (receipt.errorMessage != null)
        'external_error_message': receipt.errorMessage,
      if (receipt.providerAcceptedAt != null)
        'provider_accepted_at': receipt.providerAcceptedAt!.toIso8601String(),
    },
    createdAt: receipt.createdAt,
    isMe: currentUserId != null && receipt.actorId == currentUserId,
  );
}

List<MetaOutboundSendReceipt> parseMetaOutboundSendReceiptsPayload(
  Object? raw, {
  required String conversationId,
}) {
  if (raw is! List) {
    throw const FormatException('Invalid Meta send receipt list');
  }

  final receipts = <MetaOutboundSendReceipt>[];
  for (final row in raw) {
    if (row is! Map) {
      throw const FormatException('Invalid Meta send receipt row');
    }
    final receipt = MetaOutboundSendReceipt.fromJson(row);
    if (receipt == null || receipt.conversationId != conversationId) {
      throw const FormatException('Invalid Meta send receipt row');
    }
    receipts.add(receipt);
  }
  return List.unmodifiable(receipts);
}

class MetaMessagingService {
  MetaMessagingService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const Duration standardReplyWindow = Duration(hours: 24);
  static const Duration maximumClockSkew = Duration(minutes: 5);

  final SupabaseClient _client;

  static bool isStandardReplyWindowOpen(
    DateTime? lastInboundAt, {
    DateTime? now,
  }) {
    if (lastInboundAt == null) return false;
    final nowUtc = (now ?? DateTime.now()).toUtc();
    final inboundUtc = lastInboundAt.toUtc();
    if (inboundUtc.isAfter(nowUtc.add(maximumClockSkew))) return false;
    final effectiveInbound = inboundUtc.isAfter(nowUtc) ? nowUtc : inboundUtc;
    final elapsed = nowUtc.difference(effectiveInbound);
    return elapsed < standardReplyWindow;
  }

  static bool isReplyWindowOpenFromExpiry(
    DateTime? replyWindowExpiresAt, {
    DateTime? now,
  }) {
    if (replyWindowExpiresAt == null) return false;
    final nowUtc = (now ?? DateTime.now()).toUtc();
    final expiryUtc = replyWindowExpiresAt.toUtc();
    if (expiryUtc.isAfter(
      nowUtc.add(standardReplyWindow).add(maximumClockSkew),
    )) {
      return false;
    }
    return expiryUtc.isAfter(nowUtc);
  }

  Future<List<MetaOutboundSendReceipt>> listOutboundSendReceipts({
    required String conversationId,
  }) async {
    final raw = await _client.rpc(
      'list_meta_outbound_send_receipts',
      params: {'p_conversation_id': conversationId},
    );
    return parseMetaOutboundSendReceiptsPayload(
      raw,
      conversationId: conversationId,
    );
  }

  Future<MetaConversationTransport> getConversationTransport({
    required String conversationId,
  }) async {
    final raw = await _client.rpc(
      'get_meta_conversation_transport',
      params: {'p_conversation_id': conversationId},
    );
    final Map<dynamic, dynamic>? row = switch (raw) {
      Map<dynamic, dynamic>() => raw,
      List<dynamic>() when raw.length == 1 && raw.single is Map =>
        raw.single as Map<dynamic, dynamic>,
      _ => null,
    };
    final transport =
        row == null ? null : MetaConversationTransport.fromJson(row);
    if (transport == null) {
      throw const FormatException('Invalid Meta conversation transport');
    }
    return transport;
  }

  Future<MetaSendReceipt> sendText({
    required String conversationId,
    required String message,
    required String clientMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client.functions.invoke(
        'meta-send',
        headers: kSupabaseFunctionsRegionHeaders,
        body: {
          'conversationId': conversationId,
          'message': message,
          'clientMessageId': clientMessageId,
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        },
      );
      // Any response without both durable IDs is ambiguous unless it carries
      // the backend's complete explicit-rejection receipt.
      final receipt = parseMetaSendPayload(response.data);
      debugPrint(
        '[MetaSend] completed status=${response.status} '
        'outcome=${receipt.outcome.name} elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return receipt;
    } on FunctionException catch (error) {
      final receipt = parseMetaSendPayload(error.details);
      debugPrint(
        '[MetaSend] rejected status=${error.status} '
        'outcome=${receipt.outcome.name} code=${receipt.errorCode ?? '-'} '
        'elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
      return receipt;
    } catch (error) {
      // A transport exception cannot prove that the provider did not accept the
      // command. Keep it explicitly ambiguous and never offer a blind retry.
      debugPrint(
        '[MetaSend] outcome_unknown elapsed=${stopwatch.elapsedMilliseconds}ms '
        'errorType=${error.runtimeType}',
      );
      return const MetaSendReceipt(
        outcome: MetaSendOutcome.outcomeUnknown,
        errorMessage:
            'No llegó una confirmación final del canal. Verifica antes de reenviar.',
      );
    }
  }
}
