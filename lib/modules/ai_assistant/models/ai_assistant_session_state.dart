import 'package:flutter/foundation.dart';

import '../../bikeshop/models/bikeshop_models.dart';
import '../services/ai_service.dart';

/// Lifecycle of the assistant session as far as the operator is concerned.
///
/// [ready] is the only state that may show prior data or accept a message.
/// [resolving] and [unavailable] are deliberately indistinguishable from the
/// outside in terms of what they expose — neither shows anything the previous
/// authority produced.
enum AIAssistantSessionStatus {
  /// No authenticated user.
  signedOut,

  /// An authority is being established (tenant and/or profile in flight).
  resolving,

  /// Authority could not be established: profile load issue, tenant/profile
  /// disagreement, or a missing tenant. Fail-closed.
  unavailable,

  /// One coherent user + tenant + profile. The only sendable state.
  ready,
}

/// Stable fingerprint of the capabilities an authority carries.
///
/// Role and permissions decide what the assistant is allowed to surface, so a
/// change in either is a change of authority even when user and tenant stay
/// the same. Permissions are sorted by key so map ordering never produces a
/// spurious difference.
@immutable
class AIAssistantCapabilityFingerprint {
  const AIAssistantCapabilityFingerprint._(this._value);

  final String _value;

  static const AIAssistantCapabilityFingerprint none =
      AIAssistantCapabilityFingerprint._('');

  factory AIAssistantCapabilityFingerprint.of({
    required String role,
    required Map<String, bool> permissions,
  }) {
    final keys = permissions.keys.toList(growable: false)..sort();
    final encoded =
        keys.map((key) => '$key=${permissions[key] == true}').join(';');
    return AIAssistantCapabilityFingerprint._(
      '${role.trim().toLowerCase()}|$encoded',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AIAssistantCapabilityFingerprint && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'AIAssistantCapabilityFingerprint($_value)';
}

/// Who produced a transcript entry.
enum AIAssistantTranscriptRole {
  user,
  assistant,

  /// Produced by the session boundary itself — a source that could not be
  /// trusted, an authority that is not resolved. Never sent to the model.
  notice,
}

@immutable
class AIAssistantTranscriptEntry {
  const AIAssistantTranscriptEntry({
    required this.role,
    required this.text,
    this.cards = const <AIAssistantActionCard>[],
  });

  const AIAssistantTranscriptEntry.notice(this.text)
      : role = AIAssistantTranscriptRole.notice,
        cards = const <AIAssistantActionCard>[];

  final AIAssistantTranscriptRole role;
  final String text;
  final List<AIAssistantActionCard> cards;
}

/// Why the visible-jobs context could not be trusted.
enum AIAssistantJobsContextIssue {
  /// No resolved authority to compare rows against.
  noAuthority,

  /// At least one row carried no tenant at all.
  tenantMissing,

  /// At least one row belonged to a different tenant than the authority.
  tenantMismatch,
}

/// Result of validating the jobs a page published for the assistant.
///
/// The rows come from another surface and are treated as untrusted input. A
/// single bad row invalidates the whole source: filtering it out silently
/// would let a cross-tenant page decide what the assistant answers from.
@immutable
class AIAssistantVisibleJobsContext {
  const AIAssistantVisibleJobsContext._({
    required this.jobs,
    required this.scopeLabel,
    required this.issue,
  });

  const AIAssistantVisibleJobsContext.trusted({
    required List<MechanicJob> jobs,
    required String? scopeLabel,
  }) : this._(jobs: jobs, scopeLabel: scopeLabel, issue: null);

  const AIAssistantVisibleJobsContext.rejected(
    AIAssistantJobsContextIssue issue,
  ) : this._(
          jobs: const <MechanicJob>[],
          scopeLabel: null,
          issue: issue,
        );

  final List<MechanicJob> jobs;
  final String? scopeLabel;
  final AIAssistantJobsContextIssue? issue;

  bool get isTrusted => issue == null;

  /// Validates published rows against the resolved authority.
  ///
  /// [authorityTenantId] is the tenant of the current authority; a null or
  /// empty value means there is nothing to validate against, which is itself a
  /// rejection.
  static AIAssistantVisibleJobsContext validate({
    required List<MechanicJob> jobs,
    required String? scopeLabel,
    required String? authorityTenantId,
  }) {
    final tenantId = authorityTenantId?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      return const AIAssistantVisibleJobsContext.rejected(
        AIAssistantJobsContextIssue.noAuthority,
      );
    }

    for (final job in jobs) {
      final rowTenant = job.tenantId.trim();
      if (rowTenant.isEmpty) {
        return const AIAssistantVisibleJobsContext.rejected(
          AIAssistantJobsContextIssue.tenantMissing,
        );
      }
      if (rowTenant != tenantId) {
        return const AIAssistantVisibleJobsContext.rejected(
          AIAssistantJobsContextIssue.tenantMismatch,
        );
      }
    }

    return AIAssistantVisibleJobsContext.trusted(
      jobs: List<MechanicJob>.unmodifiable(jobs),
      scopeLabel: scopeLabel,
    );
  }
}
