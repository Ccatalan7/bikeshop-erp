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

/// A card the assistant offers after answering.
///
/// The card carries a closed [destination], never a model-authored route or
/// record id. The application remains the owner of every possible click.
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
  });

  final String kind;
  final String title;
  final AIAssistantDestination destination;
  final String? eyebrow;
  final String? subtitle;
  final String? description;
  final List<String> chips;

  String get ctaLabel => destination.ctaLabel;
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
