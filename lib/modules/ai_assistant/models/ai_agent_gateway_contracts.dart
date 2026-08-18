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
  intelligentPurchasing('intelligent_purchasing'),
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

  factory AIAgentGatewayViewContext.intelligentPurchasing() =>
      AIAgentGatewayViewContext(
        kind: AIAgentGatewayViewContextKind.intelligentPurchasing,
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
      if (cards.length != 1 || cards.single.approvalRef != null) {
        throw const AIAgentGatewayContractException();
      }
      final card = cards.single;
      final isCommittedTask = card.kind == 'task' &&
          card.destination == AIAssistantDestination.tasks &&
          card.entityRef == null;
      final isCommittedWorkshopAction = card.kind == 'job' &&
          card.destination == AIAssistantDestination.workshopJobs &&
          card.entityRef?.kind == AIAssistantEntityKind.workshopJob;
      if (!isCommittedTask && !isCommittedWorkshopAction) {
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
    'listRef',
    'supplyNeedDraft',
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
  final previewAction = switch ((destination, kind)) {
    (AIAssistantDestination.tasks, 'task_preview') =>
      AIAssistantApprovalAction.createTask,
    (AIAssistantDestination.workshopJobs, 'diagnosis_preview') =>
      AIAssistantApprovalAction.updateDiagnosis,
    (AIAssistantDestination.workshopJobs, 'workshop_item_preview') =>
      AIAssistantApprovalAction.addWorkshopItem,
    _ => null,
  };
  final isSupplyNeedDraft = destination == AIAssistantDestination.purchases &&
      kind == 'supply_need_draft';
  if (expectedKind != kind && previewAction == null && !isSupplyNeedDraft) {
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
      'update_diagnosis' => AIAssistantApprovalAction.updateDiagnosis,
      'add_workshop_item' => AIAssistantApprovalAction.addWorkshopItem,
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
  if (previewAction != null) {
    // The canonical transcript updates this same preview after a decision.
    // Terminal previews are valid history; only the UI/action engine decides
    // that `pending` is actionable.
    if (entityRef != null ||
        approvalRef == null ||
        approvalRef.action != previewAction) {
      throw const AIAgentGatewayContractException();
    }
  } else if (approvalRef != null) {
    throw const AIAgentGatewayContractException();
  }

  AIAssistantInventoryListRef? inventoryListRef;
  if (json.containsKey('listRef')) {
    final rawListRef = json['listRef'];
    if (rawListRef is! Map ||
        kind != 'inventory' ||
        destination != AIAssistantDestination.inventoryProducts ||
        entityRef != null ||
        approvalRef != null) {
      throw const AIAgentGatewayContractException();
    }
    final listJson = rawListRef.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    _requireExactKeys(
      listJson,
      const <String>{
        'kind',
        'query',
        'availability',
        'resultCount',
        'hasMore',
        'entityIds',
        'autoOpen',
      },
    );
    if (listJson['kind'] != 'inventory' ||
        listJson['resultCount'] is! int ||
        (listJson['resultCount'] as int) < 0 ||
        (listJson['resultCount'] as int) > 10 ||
        listJson['hasMore'] is! bool ||
        listJson['autoOpen'] is! bool) {
      throw const AIAgentGatewayContractException();
    }
    final availability = switch (listJson['availability']) {
      'any' => AIAssistantInventoryAvailability.any,
      'in_stock' => AIAssistantInventoryAvailability.inStock,
      'low_stock' => AIAssistantInventoryAvailability.lowStock,
      'out_of_stock' => AIAssistantInventoryAvailability.outOfStock,
      _ => null,
    };
    if (availability == null) {
      throw const AIAgentGatewayContractException();
    }
    final hasMore = listJson['hasMore'] as bool;
    final rawEntityIds = listJson['entityIds'];
    if ((hasMore && rawEntityIds != null) ||
        (!hasMore && rawEntityIds is! List)) {
      throw const AIAgentGatewayContractException();
    }
    List<String>? entityIds;
    if (rawEntityIds is List) {
      entityIds = <String>[];
      final seen = <String>{};
      for (final rawId in rawEntityIds) {
        if (rawId is! String) {
          throw const AIAgentGatewayContractException();
        }
        try {
          final verified = AIAssistantEntityRef.verified(
            kind: AIAssistantEntityKind.product,
            id: rawId,
          );
          if (!seen.add(verified.id)) {
            throw const AIAgentGatewayContractException();
          }
          entityIds.add(verified.id);
        } on ArgumentError {
          throw const AIAgentGatewayContractException();
        }
      }
      if (entityIds.length != listJson['resultCount']) {
        throw const AIAgentGatewayContractException();
      }
      entityIds = List<String>.unmodifiable(entityIds);
    }
    inventoryListRef = AIAssistantInventoryListRef(
      query: _requiredBoundedText(listJson['query'], maxBytes: 240),
      availability: availability,
      resultCount: listJson['resultCount'] as int,
      hasMore: hasMore,
      entityIds: entityIds,
      autoOpen: listJson['autoOpen'] as bool,
    );
  }

  AIAssistantSupplyNeedDraft? supplyNeedDraft;
  if (json.containsKey('supplyNeedDraft')) {
    if (!isSupplyNeedDraft || entityRef != null || approvalRef != null) {
      throw const AIAgentGatewayContractException();
    }
    supplyNeedDraft = _decodeSupplyNeedDraft(json['supplyNeedDraft']);
  } else if (isSupplyNeedDraft) {
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
    inventoryListRef: inventoryListRef,
    supplyNeedDraft: supplyNeedDraft,
  );
}

AIAssistantSupplyNeedDraft _decodeSupplyNeedDraft(Object? value) {
  if (value is! Map) throw const AIAgentGatewayContractException();
  final json = value.map((key, value) => MapEntry(key.toString(), value));
  _requireExactKeys(json, const <String>{'profile', 'lines'});
  final profile = switch (json['profile']) {
    'balanced' => AIAssistantSupplyNeedProfile.balanced,
    'profitability' => AIAssistantSupplyNeedProfile.profitability,
    'urgent_local' => AIAssistantSupplyNeedProfile.urgentLocal,
    _ => null,
  };
  final rawLines = json['lines'];
  if (profile == null ||
      rawLines is! List ||
      rawLines.isEmpty ||
      rawLines.length > 8) {
    throw const AIAgentGatewayContractException();
  }

  final lineRefs = <String>{};
  final lines = <AIAssistantSupplyNeedDraftLine>[];
  for (final rawLine in rawLines) {
    if (rawLine is! Map) throw const AIAgentGatewayContractException();
    final line = rawLine.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    _requireExactKeys(
      line,
      const <String>{
        'lineRef',
        'description',
        'productId',
        'productName',
        'productSku',
        'identityState',
        'categoryId',
        'categoryPath',
        'technicalFamily',
        'quantity',
        'unit',
        'technicalPredicates',
        'preference',
        'clarification',
        'clarificationRequired',
        'clarificationPrompts',
      },
      required: const <String>{
        'lineRef',
        'description',
        'productId',
        'productName',
        'productSku',
        'identityState',
        'categoryId',
        'categoryPath',
        'technicalFamily',
        'quantity',
        'unit',
        'technicalPredicates',
        'preference',
        'clarification',
        'clarificationRequired',
      },
    );
    final lineRef = _requiredBoundedText(line['lineRef'], maxBytes: 6);
    final productId = line['productId'] == null
        ? null
        : _requiredOpaqueId(line['productId']).toLowerCase();
    final productName = _optionalBoundedText(
      line['productName'],
      maxBytes: 500,
    );
    final productSku = _optionalBoundedText(
      line['productSku'],
      maxBytes: 160,
    );
    // Procedencia de categoría. Es identidad server-owned: se transporta y se
    // devuelve intacta al comando, nunca se edita ni se adivina en el cliente.
    final categoryId = line['categoryId'] == null
        ? null
        : _requiredOpaqueId(line['categoryId']).toLowerCase();
    final categoryPath = _optionalBoundedText(
      line['categoryPath'],
      maxBytes: 240,
    );
    final technicalFamily = _optionalBoundedText(
      line['technicalFamily'],
      maxBytes: 120,
    );
    final identityState = line['identityState'];
    final quantityValue = line['quantity'];
    final clarificationRequired = line['clarificationRequired'];
    final clarification = _optionalBoundedText(
      line['clarification'],
      maxBytes: 500,
    );
    final clarificationPrompts = _decodeSupplyNeedClarificationPrompts(
      line['clarificationPrompts'] ?? const <Object?>[],
    );
    if (!RegExp(r'^line-[1-8]$').hasMatch(lineRef) ||
        !lineRefs.add(lineRef) ||
        (identityState != 'unresolved' && identityState != 'confirmed') ||
        quantityValue is! num ||
        !quantityValue.isFinite ||
        quantityValue < 0.001 ||
        quantityValue > 999999 ||
        clarificationRequired is! bool ||
        (productId == null &&
            (identityState != 'unresolved' ||
                productName != null ||
                productSku != null)) ||
        (productId != null &&
            (identityState != 'confirmed' || productName == null)) ||
        // Ruta o familia sin identidad detrás sería una glosa que nada
        // respalda: se rechaza la tarjeta entera.
        (categoryId == null &&
            (categoryPath != null || technicalFamily != null)) ||
        (clarificationRequired &&
            (clarification == null || productId != null)) ||
        (!clarificationRequired && clarificationPrompts.isNotEmpty)) {
      throw const AIAgentGatewayContractException();
    }
    final rawPredicates = line['technicalPredicates'];
    if (rawPredicates is! List || rawPredicates.length > 8) {
      throw const AIAgentGatewayContractException();
    }
    final predicateFields = <String>{};
    final predicates = <AIAssistantSupplyNeedTechnicalPredicate>[];
    for (final rawPredicate in rawPredicates) {
      if (rawPredicate is! Map) {
        throw const AIAgentGatewayContractException();
      }
      final predicate = rawPredicate.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      _requireExactKeys(
        predicate,
        const <String>{'field', 'operator', 'values'},
      );
      final field = _requiredBoundedText(predicate['field'], maxBytes: 64);
      final operator = predicate['operator'];
      final rawValues = predicate['values'];
      if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(field) ||
          !predicateFields.add(field) ||
          operator is! String ||
          !const <String>{
            'eq',
            'neq',
            'lt',
            'lte',
            'gt',
            'gte',
            'between',
            'in',
            'contains',
          }.contains(operator) ||
          rawValues is! List ||
          rawValues.isEmpty ||
          rawValues.length > 10 ||
          (operator == 'between' && rawValues.length != 2) ||
          (operator != 'between' &&
              operator != 'in' &&
              rawValues.length != 1)) {
        throw const AIAgentGatewayContractException();
      }
      final values = <Object>[];
      for (final rawValue in rawValues) {
        if (rawValue is String) {
          values.add(_requiredBoundedText(rawValue, maxBytes: 160));
        } else if (rawValue is num && rawValue.isFinite) {
          values.add(rawValue);
        } else if (rawValue is bool) {
          values.add(rawValue);
        } else {
          throw const AIAgentGatewayContractException();
        }
      }
      predicates.add(
        AIAssistantSupplyNeedTechnicalPredicate(
          field: field,
          operator: operator,
          values: List<Object>.unmodifiable(values),
        ),
      );
    }

    lines.add(
      AIAssistantSupplyNeedDraftLine(
        lineRef: lineRef,
        description: _requiredBoundedText(
          line['description'],
          maxBytes: 2000,
        ),
        productId: productId,
        productName: productName,
        productSku: productSku,
        identityState: identityState as String,
        categoryId: categoryId,
        categoryPath: categoryPath,
        technicalFamily: technicalFamily,
        quantity: quantityValue.toDouble(),
        unit: _requiredBoundedText(line['unit'], maxBytes: 32),
        technicalPredicates:
            List<AIAssistantSupplyNeedTechnicalPredicate>.unmodifiable(
          predicates,
        ),
        preference: _optionalBoundedText(
          line['preference'],
          maxBytes: 240,
        ),
        clarification: clarification,
        clarificationRequired: clarificationRequired,
        commercialTarget: _decodeSupplyNeedCommercialTarget(
          line['commercialTarget'],
        ),
        clarificationPrompts: clarificationPrompts,
      ),
    );
  }

  return AIAssistantSupplyNeedDraft(
    profile: profile,
    lines: List<AIAssistantSupplyNeedDraftLine>.unmodifiable(lines),
  );
}

/// Objetivo comercial de una línea, tal como lo devuelve la tarjeta cerrada.
///
/// Se valida acá y no se «arregla»: un valor fuera de rango o una clave que el
/// contrato no publica es una tarjeta que no cuadra, y eso se rechaza entero.
/// La moneda es del servidor: si aparece `currencyCode`, la tarjeta miente.
AIAssistantSupplyNeedCommercialTarget? _decodeSupplyNeedCommercialTarget(
  Object? value,
) {
  if (value == null) return null;
  if (value is! Map) throw const AIAgentGatewayContractException();
  const allowed = <String>{
    'gama',
    'maxLandedUnitCostNet',
    'minGrossMarginRatio',
  };
  for (final key in value.keys) {
    if (key is! String || !allowed.contains(key)) {
      throw const AIAgentGatewayContractException();
    }
  }
  final rawGama = value['gama'];
  if (rawGama != null &&
      (rawGama is! String ||
          !const {'economica', 'media', 'alta'}.contains(rawGama))) {
    throw const AIAgentGatewayContractException();
  }
  final rawCost = value['maxLandedUnitCostNet'];
  if (rawCost != null &&
      (rawCost is! num || !rawCost.isFinite || rawCost <= 0)) {
    throw const AIAgentGatewayContractException();
  }
  final rawMargin = value['minGrossMarginRatio'];
  if (rawMargin != null &&
      (rawMargin is! num ||
          !rawMargin.isFinite ||
          rawMargin < 0 ||
          rawMargin > 1)) {
    throw const AIAgentGatewayContractException();
  }
  final target = AIAssistantSupplyNeedCommercialTarget(
    gama: rawGama as String?,
    maxLandedUnitCostNet: (rawCost as num?)?.toDouble(),
    minGrossMarginRatio: (rawMargin as num?)?.toDouble(),
  );
  // Un objeto sin ninguna clave útil no es un objetivo: la base lo rechazaría.
  return target.isEmpty ? null : target;
}

List<AIAssistantSupplyNeedClarificationPrompt>
    _decodeSupplyNeedClarificationPrompts(Object? value) {
  if (value is! List || value.length > 3) {
    throw const AIAgentGatewayContractException();
  }
  final ids = <String>{};
  final prompts = <AIAssistantSupplyNeedClarificationPrompt>[];
  for (final rawPrompt in value) {
    if (rawPrompt is! Map) {
      throw const AIAgentGatewayContractException();
    }
    final prompt = rawPrompt.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    _requireExactKeys(
      prompt,
      const <String>{
        'id',
        'question',
        'inputKind',
        'options',
        'unit',
        'allowUnknown',
      },
    );
    final id = _requiredBoundedText(prompt['id'], maxBytes: 32);
    final question = _requiredBoundedText(
      prompt['question'],
      maxBytes: 320,
    );
    final inputKind = switch (prompt['inputKind']) {
      'single_choice' =>
        AIAssistantSupplyNeedClarificationInputKind.singleChoice,
      'text' => AIAssistantSupplyNeedClarificationInputKind.text,
      'number' => AIAssistantSupplyNeedClarificationInputKind.number,
      _ => null,
    };
    final allowUnknown = prompt['allowUnknown'];
    final unit = _optionalBoundedText(prompt['unit'], maxBytes: 32);
    final rawOptions = prompt['options'];
    if (!RegExp(r'^[a-z][a-z0-9_]{1,31}$').hasMatch(id) ||
        !ids.add(id) ||
        inputKind == null ||
        allowUnknown is! bool ||
        rawOptions is! List ||
        rawOptions.length > 5 ||
        (inputKind ==
                AIAssistantSupplyNeedClarificationInputKind.singleChoice &&
            (rawOptions.length < 2 || unit != null)) ||
        (inputKind !=
                AIAssistantSupplyNeedClarificationInputKind.singleChoice &&
            rawOptions.isNotEmpty) ||
        (inputKind != AIAssistantSupplyNeedClarificationInputKind.number &&
            unit != null)) {
      throw const AIAgentGatewayContractException();
    }
    final optionValues = <String>{};
    final options = <AIAssistantSupplyNeedClarificationOption>[];
    for (final rawOption in rawOptions) {
      if (rawOption is! Map) {
        throw const AIAgentGatewayContractException();
      }
      final option = rawOption.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      _requireExactKeys(option, const <String>{'value', 'label'});
      final optionValue = _requiredBoundedText(
        option['value'],
        maxBytes: 64,
      );
      final optionLabel = _requiredBoundedText(
        option['label'],
        maxBytes: 160,
      );
      if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(optionValue) ||
          !optionValues.add(optionValue)) {
        throw const AIAgentGatewayContractException();
      }
      options.add(
        AIAssistantSupplyNeedClarificationOption(
          value: optionValue,
          label: optionLabel,
        ),
      );
    }
    prompts.add(
      AIAssistantSupplyNeedClarificationPrompt(
        id: id,
        question: question,
        inputKind: inputKind,
        options: List<AIAssistantSupplyNeedClarificationOption>.unmodifiable(
          options,
        ),
        unit: unit,
        allowUnknown: allowUnknown,
      ),
    );
  }
  return List<AIAssistantSupplyNeedClarificationPrompt>.unmodifiable(prompts);
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
