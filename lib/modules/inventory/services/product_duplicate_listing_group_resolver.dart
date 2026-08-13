import '../models/product_duplicate_candidate.dart';
import 'product_duplicate_matcher_service.dart';
import 'product_identity/product_identity_profile.dart';

/// One independently resolved supplier row participating in document-level
/// consistency review.
class ProductDuplicateListingGroupRow {
  const ProductDuplicateListingGroupRow({
    required this.rowId,
    required this.supplierId,
    required this.supplierListingId,
    required this.immutableVariantKey,
    required this.result,
    this.deterministicTopCandidate,
  });

  final String rowId;
  final String? supplierId;
  final String? supplierListingId;
  final String? immutableVariantKey;

  /// The row's leading viable candidate before any AI adjudication.
  ///
  /// Group consistency is deterministic evidence. The final [result] may have
  /// been reordered by AI, so reading its first recommendation here would let a
  /// repeated model opinion manufacture its own majority.
  final ProductDuplicateCandidate? deterministicTopCandidate;
  final ProductDuplicateSearchResult result;
}

/// Uses sibling rows from one immutable supplier listing as a conservative
/// contradiction detector.
///
/// It never creates or changes a recommendation. When a strict majority of
/// independently recommended rows agrees on one catalog product and that same
/// product remains viable for a dissenting variant, the dissenter is downgraded
/// to an abstention and the shared option is surfaced first for manual review.
/// This prevents one weak variant token from looking decisive without turning
/// the unsafe assumption «one listing = one product» into identity authority.
class ProductDuplicateListingGroupResolver {
  const ProductDuplicateListingGroupResolver();

  Map<String, ProductDuplicateSearchResult> resolve(
    Iterable<ProductDuplicateListingGroupRow> rows,
  ) {
    final groups = <String, List<ProductDuplicateListingGroupRow>>{};
    for (final row in rows) {
      final supplierId = row.supplierId?.trim().toLowerCase() ?? '';
      final listingId = row.supplierListingId?.trim().toLowerCase() ?? '';
      if (supplierId.isEmpty || listingId.isEmpty) continue;
      groups
          .putIfAbsent('$supplierId\u0000$listingId',
              () => <ProductDuplicateListingGroupRow>[])
          .add(row);
    }

    final reconciled = <String, ProductDuplicateSearchResult>{};
    for (final group in groups.values) {
      reconciled.addAll(_resolveOne(group));
    }
    return Map<String, ProductDuplicateSearchResult>.unmodifiable(reconciled);
  }

  Map<String, ProductDuplicateSearchResult> _resolveOne(
    List<ProductDuplicateListingGroupRow> rows,
  ) {
    if (!_isSafeVariantGroup(rows)) {
      return const <String, ProductDuplicateSearchResult>{};
    }

    final votes = _uniqueVariantVotes(rows);
    if (votes == null || votes.length < 2) {
      return const <String, ProductDuplicateSearchResult>{};
    }

    final firstPlaceCounts = <String, int>{};
    for (final vote in votes.values) {
      final key = vote.candidateKey;
      if (key == null) continue;
      firstPlaceCounts[key] = (firstPlaceCounts[key] ?? 0) + 1;
    }
    if (firstPlaceCounts.isEmpty) {
      return const <String, ProductDuplicateSearchResult>{};
    }

    final ordered = firstPlaceCounts.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount != 0 ? byCount : left.key.compareTo(right.key);
      });
    final winner = ordered.first;
    final strictMajority = votes.length ~/ 2 + 1;
    if (winner.value < strictMajority ||
        (ordered.length > 1 && ordered[1].value == winner.value)) {
      return const <String, ProductDuplicateSearchResult>{};
    }

    final reconciled = <String, ProductDuplicateSearchResult>{};
    for (final row in rows) {
      // Listing evidence may only remove an unsafe recommendation. It never
      // promotes an abstention/no-match, even when the shared candidate remains
      // visible in the operator picker.
      if (row.result.kind != ProductDuplicateDecisionKind.recommendation ||
          row.result.recommendations.isEmpty) {
        continue;
      }
      final currentTop = row.result.recommendations.first;
      if (currentTop.isRuledOut || currentTop.isReviewOnlyFamilyScope) {
        continue;
      }
      if (_candidateKey(currentTop) == winner.key) {
        continue;
      }

      // The group majority is built exclusively from deterministic leaders.
      // It may question a row only while that row's final recommendation still
      // repeats its own deterministic leader. If the grounded adjudicator has
      // explicitly selected another offered candidate for this exact variant,
      // using the deterministic group vote to undo that decision would let the
      // evidence the adjudicator just rejected overrule it a second time.
      //
      // This remains conservative: a result where AI merely confirms the
      // deterministic leader can still be downgraded by sibling evidence.
      final deterministicTop = row.deterministicTopCandidate;
      final aiOverruledDeterministicLeader = row.result.adjudicationState ==
              ProductDuplicateAdjudicationState.accepted &&
          (deterministicTop == null ||
              _candidateKey(currentTop) != _candidateKey(deterministicTop));
      if (aiOverruledDeterministicLeader) {
        continue;
      }

      ProductDuplicateCandidate? shared;
      for (final candidate in row.result.operatorChoices) {
        if (!candidate.isRuledOut &&
            !candidate.isReviewOnlyFamilyScope &&
            _candidateKey(candidate) == winner.key) {
          shared = candidate;
          break;
        }
      }
      if (shared == null) continue;

      final choices = <ProductDuplicateCandidate>[
        shared,
        for (final candidate in row.result.operatorChoices)
          if (_candidateKey(candidate) != winner.key) candidate,
      ];
      final currentLabel =
          'esta variante también coincide con ${currentTop.product.sku}';
      final groupReason = 'La publicación favorece ${shared.product.sku}, pero '
          '$currentLabel; revisa ambas opciones.';
      reconciled[row.rowId] = ProductDuplicateSearchResult(
        probeIdentity: row.result.probeIdentity,
        kind: ProductDuplicateDecisionKind.abstained,
        recommendations: const <ProductDuplicateCandidate>[],
        normalCandidates: row.result.normalCandidates,
        operatorChoices: choices,
        categoryConflicts: row.result.categoryConflicts,
        deterministicTopCandidate: row.result.deterministicTopCandidate,
        adjudicationState: row.result.adjudicationState,
        investigation: row.result.investigation,
        adjudication: row.result.adjudication,
        reason: _appendReason(row.result.reason, groupReason),
      );
    }
    return reconciled;
  }

  bool _isSafeVariantGroup(List<ProductDuplicateListingGroupRow> rows) {
    if (rows.length < 2) return false;
    if (rows.any(
      (row) =>
          row.result.kind == ProductDuplicateDecisionKind.authoritativeExact,
    )) {
      return false;
    }

    final variantKeys = <String>{};
    for (final row in rows) {
      final key = row.immutableVariantKey?.trim().toLowerCase() ?? '';
      if (!key.startsWith('sku:') && !key.startsWith('props:')) return false;
      variantKeys.add(key);
    }
    if (variantKeys.length < 2) return false;

    final families = rows
        .map((row) => row.result.probeIdentity.resolvedFamilyId)
        .whereType<String>()
        .toSet();
    if (families.length != 1 ||
        rows.any((row) => !row.result.probeIdentity.hasResolvedFamily)) {
      return false;
    }

    final categories = rows
        .map((row) => row.result.probeIdentity.category?.label)
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
    if (categories.length > 1) return false;

    final brands = rows
        .map((row) => row.result.probeIdentity.profile.assertedBrand)
        .whereType<String>()
        .toSet();
    if (brands.length > 1) return false;

    final primaryModels = <String>{};
    for (final row in rows) {
      primaryModels.addAll(row.result.probeIdentity.profile.primaryModelCodes);
    }
    if (primaryModels.length > 1) return false;

    final valuesBySpec = <PartSpecKind, Set<String>>{};
    for (final row in rows) {
      for (final entry in row.result.probeIdentity.profile.specs.entries) {
        if (entry.key == PartSpecKind.colorVariant) continue;
        valuesBySpec.putIfAbsent(entry.key, () => <String>{}).add(entry.value);
      }
    }
    return valuesBySpec.values.every((values) => values.length <= 1);
  }

  /// One vote per immutable supplier variant.
  ///
  /// Multiple invoice rows may be repeated purchases of the same variant. They
  /// are one identity witness, not several. If two rows carrying the same key
  /// disagree about their deterministic leader (including leader versus no
  /// leader), the group itself is inconsistent and cannot reconcile anything.
  Map<String, _DeterministicVariantVote>? _uniqueVariantVotes(
    List<ProductDuplicateListingGroupRow> rows,
  ) {
    final votes = <String, _DeterministicVariantVote>{};
    for (final row in rows) {
      final variantKey = row.immutableVariantKey?.trim().toLowerCase() ?? '';
      if (!variantKey.startsWith('sku:') && !variantKey.startsWith('props:')) {
        return null;
      }

      final candidate = row.deterministicTopCandidate;
      final candidateKey = candidate == null ||
              candidate.isRuledOut ||
              candidate.isReviewOnlyFamilyScope
          ? null
          : _candidateKey(candidate);
      final existing = votes[variantKey];
      if (existing != null && existing.candidateKey != candidateKey) {
        return null;
      }
      votes.putIfAbsent(
        variantKey,
        () => _DeterministicVariantVote(candidateKey: candidateKey),
      );
    }
    return votes;
  }

  static String _appendReason(String? prior, String groupReason) {
    final normalizedPrior = prior?.trim() ?? '';
    if (normalizedPrior.isEmpty) return groupReason;
    if (normalizedPrior.contains(groupReason)) return normalizedPrior;
    return '$normalizedPrior $groupReason';
  }

  static String _candidateKey(ProductDuplicateCandidate candidate) {
    final id = candidate.product.id?.trim() ?? '';
    if (id.isNotEmpty) return 'id:$id';
    return 'sku:${candidate.product.sku.trim().toLowerCase()}';
  }
}

class _DeterministicVariantVote {
  const _DeterministicVariantVote({required this.candidateKey});

  final String? candidateKey;
}
