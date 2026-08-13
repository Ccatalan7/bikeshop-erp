import 'package:flutter/foundation.dart';

import '../../../shared/services/authority_scoped_cache.dart';
import 'ai_assistant_destination.dart';

/// Raised when a shared service returned rows that could not be proven to
/// belong to the turn's authority.
class AIAssistantSourceUnavailable implements Exception {
  const AIAssistantSourceUnavailable(this.source, this.reason);

  final String source;
  final String reason;

  @override
  String toString() => 'AI source "$source" unavailable: $reason';
}

/// The one authority a turn may answer from.
///
/// An unresolved authority is not representable. Every row is checked against
/// this key before it reaches a prompt, tool result or card. A source that
/// cannot be proven is unavailable; it is never silently filtered or degraded
/// into zero results.
@immutable
class AIAssistantTurnAuthority {
  const AIAssistantTurnAuthority(
    this.scope, {
    this.role = 'unknown',
    this.permissions = const <String>{},
  });

  final ErpAuthorityScopeKey scope;
  final String role;
  final Set<String> permissions;

  String get tenantId => scope.tenantId;

  List<T> verifyRows<T>(
    String source,
    Iterable<T> rows,
    String? Function(T row) tenantOf,
  ) {
    final expected = scope.tenantId;
    final verified = <T>[];

    for (final row in rows) {
      final rowTenant = tenantOf(row)?.trim();
      if (rowTenant == null || rowTenant.isEmpty) {
        throw AIAssistantSourceUnavailable(source, 'a row carries no tenant');
      }
      if (rowTenant != expected) {
        throw AIAssistantSourceUnavailable(
          source,
          'a row belongs to another tenant',
        );
      }
      verified.add(row);
    }
    return verified;
  }

  void requireServiceScope(String source, ErpAuthorityScopeKey? serviceScope) {
    if (serviceScope == null) {
      throw AIAssistantSourceUnavailable(source, 'service has no bound scope');
    }
    if (serviceScope != scope) {
      throw AIAssistantSourceUnavailable(
        source,
        'service is bound to another authority',
      );
    }
  }
}

/// The only write intent currently admitted by an assistant approval card.
///
/// It names a server-owned command, never model-authored arguments. The exact
/// task preview is already frozen behind [AIAssistantApprovalRef.id].
enum AIAssistantApprovalAction {
  createTask,
}

/// The operator decision sent to the approval endpoint.
enum AIAssistantApprovalDecision {
  approve,
  discard,
}

/// Server-owned lifecycle of one exact approval preview.
enum AIAssistantApprovalState {
  pending,
  approved,
  discarded,
  expired;

  bool get isTerminal => this != AIAssistantApprovalState.pending;
}

/// Opaque approval identity attached only to a governed preview card.
@immutable
class AIAssistantApprovalRef {
  const AIAssistantApprovalRef({
    required this.id,
    required this.action,
    required this.expiresAt,
    required this.state,
  });

  final String id;
  final AIAssistantApprovalAction action;
  final DateTime expiresAt;
  final AIAssistantApprovalState state;

  AIAssistantApprovalRef withState(AIAssistantApprovalState nextState) =>
      AIAssistantApprovalRef(
        id: id,
        action: action,
        expiresAt: expiresAt,
        state: nextState,
      );
}

/// A card the assistant offers after answering.
///
/// The card carries a closed [destination] and may carry one verified,
/// server-owned [entityRef]. It never carries a model-authored route. The
/// application remains the owner of every possible click.
@immutable
class AIAssistantActionCard {
  const AIAssistantActionCard({
    required this.kind,
    required this.title,
    required this.destination,
    this.eyebrow,
    this.subtitle,
    this.description,
    this.chips = const <String>[],
    this.entityRef,
    this.approvalRef,
  });

  final String kind;
  final String title;
  final AIAssistantDestination destination;
  final String? eyebrow;
  final String? subtitle;
  final String? description;
  final List<String> chips;
  final AIAssistantEntityRef? entityRef;
  final AIAssistantApprovalRef? approvalRef;

  String get ctaLabel => entityRef?.detailCtaLabel ?? destination.ctaLabel;

  AIAssistantActionCard withApprovalState(
    AIAssistantApprovalState state,
  ) {
    final approval = approvalRef;
    if (approval == null) return this;
    return AIAssistantActionCard(
      kind: kind,
      title: title,
      destination: destination,
      eyebrow: eyebrow,
      subtitle: subtitle,
      description: description,
      chips: chips,
      entityRef: entityRef,
      approvalRef: approval.withState(state),
    );
  }
}

@immutable
class AIAssistantResponse {
  const AIAssistantResponse({
    required this.text,
    this.cards = const <AIAssistantActionCard>[],
  });

  final String text;
  final List<AIAssistantActionCard> cards;
}

/// Deterministic result of approve/discard. No model turn participates.
@immutable
class AIAssistantApprovalResolution {
  const AIAssistantApprovalResolution({
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
}
