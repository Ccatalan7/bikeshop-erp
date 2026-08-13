import 'dart:convert';

import 'ai_assistant_destination.dart';
import 'ai_assistant_turn_contracts.dart';

const int aiAgentGatewayContractVersion = 1;
const int aiAgentGatewayMaxMessageBytes = 8 * 1024;
const int aiAgentGatewayMaxVisibleJobIds = 20;
const int aiAgentGatewayMaxCards = 6;

class AIAgentGatewayContractException implements Exception {
  const AIAgentGatewayContractException();

  @override
  String toString() => 'Invalid AI agent gateway contract';
}

enum AIAgentGatewayViewContextKind {
  none('none'),
  workshopJobs('workshop_jobs'),
  rejected('rejected');

  const AIAgentGatewayViewContextKind(this.wireValue);

  final String wireValue;
}

class AIAgentGatewayViewContext {
  factory AIAgentGatewayViewContext({
    required AIAgentGatewayViewContextKind kind,
    required List<String> jobIds,
    required bool truncated,
  }) {
    if (kind != AIAgentGatewayViewContextKind.workshopJobs &&
        (jobIds.isNotEmpty || truncated)) {
      throw const AIAgentGatewayContractException();
    }
    if (jobIds.length > aiAgentGatewayMaxVisibleJobIds) {
      throw const AIAgentGatewayContractException();
    }
    final normalized = <String>[];
    final seen = <String>{};
    for (final rawId in jobIds) {
      final id = _requiredOpaqueId(rawId);
      if (!seen.add(id)) throw const AIAgentGatewayContractException();
      normalized.add(id);
    }
    return AIAgentGatewayViewContext._(
      kind: kind,
      jobIds: List<String>.unmodifiable(normalized),
      truncated: truncated,
    );
  }

  const AIAgentGatewayViewContext._({
    required this.kind,
    required this.jobIds,
    required this.truncated,
  });

  factory AIAgentGatewayViewContext.none() => AIAgentGatewayViewContext(
        kind: AIAgentGatewayViewContextKind.none,
        jobIds: const <String>[],
        truncated: false,
      );

  factory AIAgentGatewayViewContext.rejected() => AIAgentGatewayViewContext(
        kind: AIAgentGatewayViewContextKind.rejected,
        jobIds: const <String>[],
        truncated: false,
      );

  final AIAgentGatewayViewContextKind kind;
  final List<String> jobIds;
  final bool truncated;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.wireValue,
        'jobIds': jobIds,
        'truncated': truncated,
      };
}

class AIAgentGatewayRequest {
  factory AIAgentGatewayRequest({
    required String clientRequestId,
    required String? threadId,
    required String message,
    required AIAgentGatewayViewContext viewContext,
  }) {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty ||
        utf8.encode(normalizedMessage).length > aiAgentGatewayMaxMessageBytes) {
      throw const AIAgentGatewayContractException();
    }
    return AIAgentGatewayRequest._(
      clientRequestId: _requiredOpaqueId(clientRequestId),
      threadId: threadId == null ? null : _requiredOpaqueId(threadId),
      message: normalizedMessage,
      viewContext: viewContext,
    );
  }

  const AIAgentGatewayRequest._({
    required this.clientRequestId,
    required this.threadId,
    required this.message,
    required this.viewContext,
  });

  final String clientRequestId;
  final String? threadId;
  final String message;
  final AIAgentGatewayViewContext viewContext;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': aiAgentGatewayContractVersion,
        'clientRequestId': clientRequestId,
        if (threadId case final value?) 'threadId': value,
        // Quality-first during the agent rollout: the client asks for the
        // logical deep role, while the gateway remains the sole owner of the
        // concrete provider, model and reasoning configuration. Cost routing
        // can move selected traffic to `fast` only after the real ERP evals
        // prove that intent resolution and multi-tool planning stay intact.
        'modelRole': 'deep',
        'message': message,
        'viewContext': viewContext.toJson(),
      };
}

/// A direct approval command. It intentionally carries no prompt, model role,
/// transcript, route, tenant or task fields: the server resolves the frozen
/// preview from [approvalId] under the caller's current authority.
class AIAgentGatewayApprovalRequest {
  factory AIAgentGatewayApprovalRequest({
    required String approvalId,
    required AIAssistantApprovalDecision decision,
    required String clientActionId,
  }) {
    return AIAgentGatewayApprovalRequest._(
      approvalId: _requiredOpaqueId(approvalId),
      decision: decision,
      clientActionId: _requiredOpaqueId(clientActionId),
    );
  }

  const AIAgentGatewayApprovalRequest._({
    required this.approvalId,
    required this.decision,
    required this.clientActionId,
  });

  final String approvalId;
  final AIAssistantApprovalDecision decision;
  final String clientActionId;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': aiAgentGatewayContractVersion,
        'operation': 'approval_action',
        'approvalId': approvalId,
        'approvalAction': switch (decision) {
          AIAssistantApprovalDecision.approve => 'approve',
          AIAssistantApprovalDecision.discard => 'discard',
        },
        'clientActionId': clientActionId,
      };
}

class AIAgentGatewayResponse {
  factory AIAgentGatewayResponse.fromJson(Map<String, Object?> json) {
    _requireExactKeys(
      json,
      const <String>{
        'version',
        'threadId',
        'runId',
        'text',
        'cards',
        'status',
      },
    );
    if (json['version'] != aiAgentGatewayContractVersion ||
        json['status'] != 'completed') {
      throw const AIAgentGatewayContractException();
    }
    final text = _requiredBoundedText(
      json['text'],
      maxBytes: 64 * 1024,
      allowEmpty: false,
    );
    final rawCards = json['cards'];
    if (rawCards is! List || rawCards.length > aiAgentGatewayMaxCards) {
      throw const AIAgentGatewayContractException();
    }
    final cards = <AIAssistantActionCard>[];
    final approvalIds = <String>{};
    for (final rawCard in rawCards) {
      if (rawCard is! Map) throw const AIAgentGatewayContractException();
      final card = _decodeCard(
        rawCard.map((key, value) => MapEntry(key.toString(), value)),
      );
      final approvalId = card.approvalRef?.id;
      if (approvalId != null && !approvalIds.add(approvalId)) {
        throw const AIAgentGatewayContractException();
      }
      cards.add(card);
    }
    return AIAgentGatewayResponse._(
      threadId: _requiredOpaqueId(json['threadId']),
      runId: _requiredOpaqueId(json['runId']),
      text: text,
      cards: List<AIAssistantActionCard>.unmodifiable(cards),
    );
  }

  const AIAgentGatewayResponse._({
    required this.threadId,
    required this.runId,
    required this.text,
    required this.cards,
  });

  final String threadId;
  final String runId;
  final String text;
  final List<AIAssistantActionCard> cards;

  AIAssistantResponse toAssistantResponse() => AIAssistantResponse(
        text: text,
        cards: cards,
      );
}

class AIAgentGatewayApprovalResponse {
  factory AIAgentGatewayApprovalResponse.fromJson(
    Map<String, Object?> json,
  ) {
    _requireExactKeys(
      json,
      const <String>{
        'version',
        'operation',
        'approvalId',
        'clientActionId',
        'approvalState',
        'text',
        'cards',
        'status',
      },
    );
    if (json['version'] != aiAgentGatewayContractVersion ||
        json['operation'] != 'approval_action' ||
        json['status'] != 'completed') {
      throw const AIAgentGatewayContractException();
    }
    final state = _approvalStateFromWire(json['approvalState']);
    if (state == null || !state.isTerminal) {
      throw const AIAgentGatewayContractException();
    }
    final rawCards = json['cards'];
    if (rawCards is! List || rawCards.length > 1) {
      throw const AIAgentGatewayContractException();
    }
    final cards = <AIAssistantActionCard>[
      for (final rawCard in rawCards)
        if (rawCard is Map)
          _decodeCard(
            rawCard.map((key, value) => MapEntry(key.toString(), value)),
          )
        else
          throw const AIAgentGatewayContractException(),
    ];
    if (state == AIAssistantApprovalState.approved) {
      if (cards.length != 1 ||
          cards.single.kind != 'task' ||
          cards.single.destination != AIAssistantDestination.tasks ||
          cards.single.approvalRef != null ||
          cards.single.entityRef != null) {
        throw const AIAgentGatewayContractException();
      }
    } else if (cards.isNotEmpty) {
      throw const AIAgentGatewayContractException();
    }
    return AIAgentGatewayApprovalResponse._(
      approvalId: _requiredOpaqueId(json['approvalId']),
      clientActionId: _requiredOpaqueId(json['clientActionId']),
      state: state,
      text: _requiredBoundedText(json['text'], maxBytes: 64 * 1024),
      cards: List<AIAssistantActionCard>.unmodifiable(cards),
    );
  }

  const AIAgentGatewayApprovalResponse._({
    required this.approvalId,
    required this.clientActionId,
    required this.state,
    required this.text,
    required this.cards,
  });

  final String approvalId;
  final String clientActionId;
  final AIAssistantApprovalState state;
  final String text;
  final List<AIAssistantActionCard> cards;

  AIAssistantApprovalResolution toResolution() => AIAssistantApprovalResolution(
        approvalId: approvalId,
        clientActionId: clientActionId,
        state: state,
        text: text,
        cards: cards,
      );
}

const Map<String, AIAssistantDestination> _destinationFromWire =
    <String, AIAssistantDestination>{
  'customers': AIAssistantDestination.customers,
  'suppliers': AIAssistantDestination.suppliers,
  'workshop_jobs': AIAssistantDestination.workshopJobs,
  'sales_invoices': AIAssistantDestination.salesInvoices,
  'purchases': AIAssistantDestination.purchases,
  'inventory_products': AIAssistantDestination.inventoryProducts,
  'expenses': AIAssistantDestination.expenses,
  'conversations': AIAssistantDestination.conversations,
  'tasks': AIAssistantDestination.tasks,
};

const Map<AIAssistantDestination, String> _kindForDestination =
    <AIAssistantDestination, String>{
  AIAssistantDestination.customers: 'customer',
  AIAssistantDestination.suppliers: 'supplier',
  AIAssistantDestination.workshopJobs: 'job',
  AIAssistantDestination.salesInvoices: 'sales_invoice',
  AIAssistantDestination.purchases: 'purchase_invoice',
  AIAssistantDestination.inventoryProducts: 'inventory',
  AIAssistantDestination.expenses: 'expense',
  AIAssistantDestination.conversations: 'conversation',
  AIAssistantDestination.tasks: 'task',
};

const Map<String, AIAssistantEntityKind> _entityKindFromWire =
    <String, AIAssistantEntityKind>{
  'workshopJob': AIAssistantEntityKind.workshopJob,
  'customer': AIAssistantEntityKind.customer,
  'salesInvoice': AIAssistantEntityKind.salesInvoice,
  'supplier': AIAssistantEntityKind.supplier,
  'purchaseInvoice': AIAssistantEntityKind.purchaseInvoice,
  'product': AIAssistantEntityKind.product,
  'expense': AIAssistantEntityKind.expense,
  'conversation': AIAssistantEntityKind.conversation,
};

const Map<AIAssistantEntityKind, String> _cardKindForEntityKind =
    <AIAssistantEntityKind, String>{
  AIAssistantEntityKind.workshopJob: 'job',
  AIAssistantEntityKind.customer: 'customer',
  AIAssistantEntityKind.salesInvoice: 'sales_invoice',
  AIAssistantEntityKind.supplier: 'supplier',
  AIAssistantEntityKind.purchaseInvoice: 'purchase_invoice',
  AIAssistantEntityKind.product: 'inventory',
  AIAssistantEntityKind.expense: 'expense',
  AIAssistantEntityKind.conversation: 'conversation',
};

AIAssistantActionCard _decodeCard(Map<String, Object?> json) {
  const required = <String>{'kind', 'title', 'destination', 'chips'};
  const optional = <String>{
    'eyebrow',
    'subtitle',
    'description',
    'entityRef',
    'approvalRef',
  };
  _requireExactKeys(json, <String>{...required, ...optional},
      required: required);

  final destinationWire = json['destination'];
  final destination =
      destinationWire is String ? _destinationFromWire[destinationWire] : null;
  if (destination == null || !destination.isRegistered) {
    throw const AIAgentGatewayContractException();
  }
  final kind = _requiredBoundedText(json['kind'], maxBytes: 32);
  final expectedKind = _kindForDestination[destination];
  final isTaskPreview =
      destination == AIAssistantDestination.tasks && kind == 'task_preview';
  if (expectedKind != kind && !isTaskPreview) {
    throw const AIAgentGatewayContractException();
  }

  AIAssistantEntityRef? entityRef;
  if (json.containsKey('entityRef')) {
    final rawEntityRef = json['entityRef'];
    if (rawEntityRef is! Map) {
      throw const AIAgentGatewayContractException();
    }
    final entityJson = rawEntityRef.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    _requireExactKeys(entityJson, const <String>{'kind', 'id'});
    final entityKindWire = entityJson['kind'];
    final entityKind =
        entityKindWire is String ? _entityKindFromWire[entityKindWire] : null;
    if (entityKind == null || _cardKindForEntityKind[entityKind] != kind) {
      throw const AIAgentGatewayContractException();
    }
    try {
      entityRef = AIAssistantEntityRef.verified(
        kind: entityKind,
        id: _requiredBoundedText(entityJson['id'], maxBytes: 36),
      );
    } on ArgumentError {
      throw const AIAgentGatewayContractException();
    }
    if (entityRef.destination != destination) {
      throw const AIAgentGatewayContractException();
    }
  }

  AIAssistantApprovalRef? approvalRef;
  if (json.containsKey('approvalRef')) {
    final rawApprovalRef = json['approvalRef'];
    if (rawApprovalRef is! Map) {
      throw const AIAgentGatewayContractException();
    }
    final approvalJson = rawApprovalRef.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    _requireExactKeys(
      approvalJson,
      const <String>{'id', 'action', 'expiresAt', 'state'},
    );
    final action = switch (approvalJson['action']) {
      'create_task' => AIAssistantApprovalAction.createTask,
      _ => null,
    };
    final state = _approvalStateFromWire(approvalJson['state']);
    if (action == null || state == null) {
      throw const AIAgentGatewayContractException();
    }
    approvalRef = AIAssistantApprovalRef(
      id: _requiredOpaqueId(approvalJson['id']),
      action: action,
      expiresAt: _requiredUtcTimestamp(approvalJson['expiresAt']),
      state: state,
    );
  }
  if (isTaskPreview) {
    // The canonical transcript updates this same preview after a decision.
    // Terminal previews are valid history; only the UI/action engine decides
    // that `pending` is actionable.
    if (entityRef != null || approvalRef == null) {
      throw const AIAgentGatewayContractException();
    }
  } else if (approvalRef != null) {
    throw const AIAgentGatewayContractException();
  }

  final rawChips = json['chips'];
  if (rawChips is! List || rawChips.length > 4) {
    throw const AIAgentGatewayContractException();
  }
  final chips = <String>[
    for (final rawChip in rawChips) _requiredBoundedText(rawChip, maxBytes: 64),
  ];

  return AIAssistantActionCard(
    kind: kind,
    title: _requiredBoundedText(json['title'], maxBytes: 160),
    destination: destination,
    eyebrow: _optionalBoundedText(json['eyebrow'], maxBytes: 80),
    subtitle: _optionalBoundedText(json['subtitle'], maxBytes: 240),
    description: _optionalBoundedText(json['description'], maxBytes: 500),
    chips: List<String>.unmodifiable(chips),
    entityRef: entityRef,
    approvalRef: approvalRef,
  );
}

AIAssistantApprovalState? _approvalStateFromWire(Object? value) =>
    switch (value) {
      'pending' => AIAssistantApprovalState.pending,
      'approved' => AIAssistantApprovalState.approved,
      'discarded' => AIAssistantApprovalState.discarded,
      'expired' => AIAssistantApprovalState.expired,
      _ => null,
    };

void _requireExactKeys(
  Map<String, Object?> value,
  Set<String> allowed, {
  Set<String>? required,
}) {
  final actual = value.keys.toSet();
  final requiredKeys = required ?? allowed;
  if (!actual.containsAll(requiredKeys) || !allowed.containsAll(actual)) {
    throw const AIAgentGatewayContractException();
  }
}

String _requiredOpaqueId(Object? value) {
  if (value is! String) throw const AIAgentGatewayContractException();
  final normalized = value.trim();
  if (!isAIAgentGatewayOpaqueId(normalized)) {
    throw const AIAgentGatewayContractException();
  }
  return normalized;
}

DateTime _requiredUtcTimestamp(Object? value) {
  if (value is! String || !value.endsWith('Z')) {
    throw const AIAgentGatewayContractException();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const AIAgentGatewayContractException();
  }
  return parsed;
}

bool isAIAgentGatewayOpaqueId(String value) =>
    _uuidPattern.hasMatch(value.trim());

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String _requiredBoundedText(
  Object? value, {
  required int maxBytes,
  bool allowEmpty = false,
}) {
  if (value is! String) throw const AIAgentGatewayContractException();
  final normalized = value.trim();
  if ((!allowEmpty && normalized.isEmpty) ||
      utf8.encode(normalized).length > maxBytes) {
    throw const AIAgentGatewayContractException();
  }
  return normalized;
}

String? _optionalBoundedText(Object? value, {required int maxBytes}) {
  if (value == null) return null;
  return _requiredBoundedText(value, maxBytes: maxBytes);
}
