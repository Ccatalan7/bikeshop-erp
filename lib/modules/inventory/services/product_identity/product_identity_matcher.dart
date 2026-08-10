import 'dart:math' as math;

import 'bike_part_taxonomy.dart';
import 'product_identity_profile.dart';

/// Result of one gate. A gate either eliminates a candidate or it does not;
/// it never lowers a score quietly.
enum IdentityGateOutcome { passed, failed, notApplicable }

/// One decisive check, recorded so the review screen can say *why* a product
/// was offered or refused instead of showing an invented percentage.
class IdentityGate {
  const IdentityGate({
    required this.id,
    required this.label,
    required this.outcome,
    required this.detail,
  });

  final String id;
  final String label;
  final IdentityGateOutcome outcome;
  final String detail;

  bool get failed => outcome == IdentityGateOutcome.failed;
}

enum IdentityMatchVerdict {
  /// The same catalog object, established without judgement: identical SKU,
  /// the same supplier listing variant, or byte-identical imagery.
  exact,

  /// Decisive corroboration — an exact manufacturer model code, or family plus
  /// manufacturer plus every stated measurement agreeing.
  strong,

  /// Comparable, worth a human look.
  possible,

  /// Eliminated by a gate. Never shown as a suggestion.
  rejected,
}

/// Evidence the caller already holds that does not come from text.
class DeterministicIdentityEvidence {
  const DeterministicIdentityEvidence({
    this.sameCatalogSku = false,
    this.sameSupplierListing = false,
    this.sameImageIdentity = false,
    this.confirmedAlias = false,
  });

  final bool sameCatalogSku;
  final bool sameSupplierListing;
  final bool sameImageIdentity;
  final bool confirmedAlias;

  bool get isExact => sameCatalogSku || sameImageIdentity || confirmedAlias;

  bool get isAny => isExact || sameSupplierListing;

  static const none = DeterministicIdentityEvidence();
}

/// Everything the matcher concluded about one candidate.
class ProductIdentityMatch {
  const ProductIdentityMatch({
    required this.verdict,
    required this.score,
    required this.gates,
    required this.reasons,
    required this.objections,
    required this.variantMismatch,
    required this.matchedModelCodes,
  });

  final IdentityMatchVerdict verdict;

  /// Ordering strength inside a verdict. Deliberately never rendered as a
  /// percentage: the guide forbids a number that pretends to be a measurement.
  final double score;

  final List<IdentityGate> gates;

  /// Why this product was offered, in the shop's own words.
  final List<String> reasons;

  /// What does not line up, including the reason a candidate was refused.
  final List<String> objections;

  /// Same product line, different sold variant (colour).
  final bool variantMismatch;

  final Set<String> matchedModelCodes;

  bool get isRejected => verdict == IdentityMatchVerdict.rejected;
}

/// Compares two [ProductIdentityProfile]s.
///
/// The order is deliberate: **eliminate, then rank**. The previous matcher
/// ranked first and used thresholds to hide mismatches, which is why one
/// invoice line offered six different hubs as `strong` when only one of them
/// could physically be the purchased part.
class ProductIdentityMatcher {
  const ProductIdentityMatcher({this.categoryAncestry = const {}});

  /// Leaf category name (normalized) → its full path segments. Lets the
  /// matcher recognize that `Corta Cadena` lives under `Herramientas`, which
  /// is the difference between finding `AE0147` and returning nothing.
  final Map<String, List<String>> categoryAncestry;

  /// Scores at or above this belong to a product that shares the invoice's
  /// manufacturer model code. Nothing without one may reach it, so a generic
  /// `ROTOR SHIMANO 160MM` can never outrank the `RT56` the invoice names.
  static const double _modelMatchFloor = 0.95;

  /// Measurable properties whose disagreement is worth saying out loud but is
  /// not by itself proof of a different product.
  static const Set<PartSpecKind> _statedDifferences = <PartSpecKind>{
    PartSpecKind.teeth,
    PartSpecKind.crankLengthMm,
    PartSpecKind.speeds,
    PartSpecKind.lengthMm,
  };

  ProductIdentityMatch evaluate({
    required ProductIdentityProfile probe,
    required ProductIdentityProfile candidate,
    DeterministicIdentityEvidence deterministic =
        DeterministicIdentityEvidence.none,
  }) {
    final gates = <IdentityGate>[];
    final reasons = <String>[];
    final objections = <String>[];

    if (deterministic.isExact) {
      if (deterministic.sameCatalogSku) reasons.add('Mismo SKU del catálogo');
      if (deterministic.confirmedAlias) {
        reasons.add('Ya lo vinculaste antes a esta publicación');
      }
      if (deterministic.sameImageIdentity) reasons.add('Misma imagen');
      return ProductIdentityMatch(
        verdict: IdentityMatchVerdict.exact,
        score: 1,
        gates: const <IdentityGate>[],
        reasons: List<String>.unmodifiable(reasons),
        objections: const <String>[],
        variantMismatch: false,
        matchedModelCodes: const <String>{},
      );
    }

    // Identity codes only. A code that lives in a compatibility clause on
    // either side is fitment, not identity: two rotors that both say
    // `compatible M610 M6000` are not the same rotor, and letting that pair
    // count as a shared model outranked the `RT56` the invoice named.
    final sharedModels = probe.modelCodes.intersection(candidate.modelCodes);
    final hasModelMatch = sharedModels.isNotEmpty;

    // Only a code printed in the product's own name (or declared in its model
    // field) may make a candidate *strong*.
    final sharedPrimaryModels =
        probe.primaryModelCodes.intersection(candidate.primaryModelCodes);
    final hasPrimaryModelMatch = sharedPrimaryModels.isNotEmpty;

    // ── Gate 1: what kind of object is it ───────────────────────────────
    final probeFamily = probe.effectiveFamilyId;
    final candidateFamily = candidate.effectiveFamilyId;
    if (probeFamily != null && candidateFamily != null) {
      if (probeFamily != candidateFamily) {
        final detail = '${BikePartTaxonomy.labelOf(probeFamily)} ≠ '
            '${BikePartTaxonomy.labelOf(candidateFamily)}';
        gates.add(IdentityGate(
          id: 'familia',
          label: 'Tipo de pieza',
          outcome: IdentityGateOutcome.failed,
          detail: detail,
        ));
        objections.add('Es otra pieza: $detail');
        return _rejected(gates, objections);
      }
      gates.add(IdentityGate(
        id: 'familia',
        label: 'Tipo de pieza',
        outcome: IdentityGateOutcome.passed,
        detail: BikePartTaxonomy.labelOf(probeFamily),
      ));
      reasons.add('Es ${BikePartTaxonomy.labelOf(probeFamily).toLowerCase()}');
    } else {
      gates.add(const IdentityGate(
        id: 'familia',
        label: 'Tipo de pieza',
        outcome: IdentityGateOutcome.notApplicable,
        detail: 'No se pudo leer el tipo de pieza en una de las dos fichas',
      ));
    }

    // ── Gate 2: measurements that decide whether it physically fits ─────
    for (final kind in exclusivePartSpecs) {
      final probeValue = probe.specs[kind];
      final candidateValue = candidate.specs[kind];
      if (probeValue == null || candidateValue == null) continue;
      if (probeValue == candidateValue) {
        gates.add(IdentityGate(
          id: 'spec:${kind.name}',
          label: partSpecLabel(kind),
          outcome: IdentityGateOutcome.passed,
          detail: partSpecValueLabel(kind, probeValue),
        ));
        reasons.add(
          '${_capitalize(partSpecLabel(kind))} '
          '${partSpecValueLabel(kind, probeValue)}',
        );
        continue;
      }
      final detail = '${partSpecValueLabel(kind, probeValue)} ≠ '
          '${partSpecValueLabel(kind, candidateValue)}';
      gates.add(IdentityGate(
        id: 'spec:${kind.name}',
        label: partSpecLabel(kind),
        outcome: IdentityGateOutcome.failed,
        detail: detail,
      ));
      objections.add('${_capitalize(partSpecLabel(kind))}: $detail');
      return _rejected(gates, objections);
    }

    // ── Gate 3: who made it ─────────────────────────────────────────────
    final probeBrand = probe.assertedBrand;
    final candidateBrand = candidate.assertedBrand;
    if (probeBrand != null && candidateBrand != null) {
      // Fail closed, with no model-code escape hatch.
      //
      // Component makers reuse each other's model strings: `Zoom B01S` and
      // `Bucklos B01S` are different forks, `Risk DS01S` and `ZTTO DS01S` are
      // different pad sets. The previous rule let a shared code override two
      // contradictory manufacturers and publish the wrong product as
      // «casi seguro el mismo». Two stated manufacturers that disagree end the
      // comparison; a genuine rebadge is a decision for the worker, taken
      // through manual search in the picker.
      if (probeBrand != candidateBrand) {
        final detail = '${_capitalize(probeBrand)} ≠ '
            '${_capitalize(candidateBrand)}';
        gates.add(IdentityGate(
          id: 'marca',
          label: 'Fabricante',
          outcome: IdentityGateOutcome.failed,
          detail: detail,
        ));
        objections.add('Otro fabricante: $detail');
        return _rejected(gates, objections);
      }
      if (probeBrand == candidateBrand) {
        gates.add(IdentityGate(
          id: 'marca',
          label: 'Fabricante',
          outcome: IdentityGateOutcome.passed,
          detail: _capitalize(probeBrand),
        ));
        reasons.add('Fabricante ${_capitalize(probeBrand)}');
      }
    } else {
      gates.add(const IdentityGate(
        id: 'marca',
        label: 'Fabricante',
        outcome: IdentityGateOutcome.notApplicable,
        detail: 'Una de las dos fichas no declara fabricante',
      ));
      // A compatibility mention is not a manufacturer and must be said out
      // loud, because the AI hint used to promote it into one.
      if (probeBrand == null && probe.compatibilityBrands.isNotEmpty) {
        objections.add(
          'La factura sólo dice compatible con '
          '${probe.compatibilityBrands.map(_capitalize).join(' / ')}; '
          'eso no es la marca.',
        );
      }
    }

    // ── Ranking ─────────────────────────────────────────────────────────
    final variantMismatch = _variantMismatch(probe, candidate);
    if (variantMismatch) {
      objections.add(
        'Otro color: '
        '${candidate.specs[PartSpecKind.colorVariant]} '
        'en vez de ${probe.specs[PartSpecKind.colorVariant]}',
      );
    }

    if (hasPrimaryModelMatch) {
      reasons.insert(
        0,
        'Modelo ${sharedPrimaryModels.map(_upper).join(' / ')}',
      );
    } else if (hasModelMatch) {
      reasons.insert(
        0,
        'Comparte el código ${sharedModels.map(_upper).join(' / ')}',
      );
    }

    // A difference the operator must see even though it does not disqualify
    // the product on its own: an IXF crankset with a 34T ring really is the
    // catalog's answer to an IXF 36T line, but only the worker can decide
    // whether that is the same purchase.
    for (final kind in _statedDifferences) {
      final probeValue = probe.specs[kind];
      final candidateValue = candidate.specs[kind];
      if (probeValue == null ||
          candidateValue == null ||
          probeValue == candidateValue) {
        continue;
      }
      objections.add(
        '${_capitalize(partSpecLabel(kind))}: '
        '${partSpecValueLabel(kind, probeValue)} ≠ '
        '${partSpecValueLabel(kind, candidateValue)}',
      );
      gates.add(IdentityGate(
        id: 'diff:${kind.name}',
        label: partSpecLabel(kind),
        outcome: IdentityGateOutcome.notApplicable,
        detail: '${partSpecValueLabel(kind, probeValue)} ≠ '
            '${partSpecValueLabel(kind, candidateValue)}',
      ));
    }
    final hasStatedDifference =
        objections.any((objection) => objection.contains('≠'));

    final descriptorOverlap = _overlap(
      probe.descriptorTokens,
      candidate.descriptorTokens,
    );
    final specAgreement = _specAgreement(probe, candidate);
    final categoryAgreement = _categoryAgreement(probe, candidate);

    if (categoryAgreement >= 0.99) {
      reasons.add('Misma categoría del catálogo');
    }

    final familyAgrees = probeFamily != null && probeFamily == candidateFamily;
    final brandAgrees = probeBrand != null && probeBrand == candidateBrand;

    // The invoice names a manufacturer model and this product is not it.
    // `SM-RT10`, `RT26` and `D442SB` are real, comparable products, but
    // calling any of them a probable duplicate of `RT56` / `D042SB` is what
    // produced six equally "strong" hubs for one purchased hub.
    final probeAssertsModel = probe.primaryModelCodes.isNotEmpty;
    final modelIsContradicted = probeAssertsModel && !hasPrimaryModelMatch;
    if (modelIsContradicted && candidate.modelCodes.isNotEmpty) {
      objections.add(
        'Otro modelo: ${candidate.modelCodes.map(_upper).join(' / ')}',
      );
    }

    // Agreeing on the sold variant is evidence, not merely the absence of a
    // problem. Only penalising a mismatch left `Puños ODI-1 Negros` tied with
    // `Puños ODI de Gel Ergonómico` for a line whose variant says `Black`: the
    // one that states the right colour and the one that states none scored the
    // same, and the tie was broken by catalog order. Silence is not agreement.
    final variantAgrees = !variantMismatch &&
        probe.specs[PartSpecKind.colorVariant] != null &&
        probe.specs[PartSpecKind.colorVariant] ==
            candidate.specs[PartSpecKind.colorVariant];
    if (variantAgrees) {
      reasons.add(
        'Color ${probe.specs[PartSpecKind.colorVariant]}',
      );
    }

    var score = 0.0;
    score += familyAgrees ? 0.34 : 0.0;
    score += brandAgrees ? 0.20 : 0.0;
    score += specAgreement * 0.22;
    score += descriptorOverlap * 0.16;
    score += categoryAgreement * 0.08;
    if (variantAgrees) score += 0.10;
    if (variantMismatch) score -= 0.10;
    if (hasStatedDifference) score -= 0.08;
    if (!hasPrimaryModelMatch) {
      score = math.min(score, _modelMatchFloor - 0.05);
    }
    score = score.clamp(0, 1).toDouble();

    IdentityMatchVerdict verdict;
    if (hasPrimaryModelMatch && familyAgrees) {
      verdict = IdentityMatchVerdict.strong;
      score = math.max(score, _modelMatchFloor);
    } else if (familyAgrees &&
        brandAgrees &&
        specAgreement >= 0.75 &&
        !variantMismatch &&
        !hasStatedDifference &&
        !modelIsContradicted) {
      verdict = IdentityMatchVerdict.strong;
      score = math.max(score, 0.82);
    } else if (familyAgrees) {
      // Agreeing on the physical family, after the measurement and
      // manufacturer gates already ran, is real comparability — not filler.
      // Requiring extra corroboration on top rejected `AE0001 Adaptador
      // Válvula Francesa/Auto` for an invoice line that was exactly that,
      // only because neither row carries a brand or a model code. How far
      // down the list a weak family match appears is a ranking question,
      // handled by the caller's relevance floor.
      verdict = IdentityMatchVerdict.possible;
    } else if (hasModelMatch) {
      verdict = IdentityMatchVerdict.possible;
    } else {
      // Nothing but coincidental words. Offering it is the "candidato absurdo"
      // the owner rejected, so it is refused instead of padding the list.
      objections.add('Sólo coinciden palabras sueltas');
      gates.add(const IdentityGate(
        id: 'evidencia',
        label: 'Evidencia',
        outcome: IdentityGateOutcome.failed,
        detail: 'Sin marca, medida ni modelo en común',
      ));
      return _rejected(gates, objections);
    }

    return ProductIdentityMatch(
      verdict: verdict,
      score: score,
      gates: List<IdentityGate>.unmodifiable(gates),
      reasons: List<String>.unmodifiable(reasons),
      objections: List<String>.unmodifiable(objections),
      variantMismatch: variantMismatch,
      matchedModelCodes: sharedPrimaryModels,
    );
  }

  ProductIdentityMatch _rejected(
    List<IdentityGate> gates,
    List<String> objections,
  ) {
    return ProductIdentityMatch(
      verdict: IdentityMatchVerdict.rejected,
      score: 0,
      gates: List<IdentityGate>.unmodifiable(gates),
      reasons: const <String>[],
      objections: List<String>.unmodifiable(objections),
      variantMismatch: false,
      matchedModelCodes: const <String>{},
    );
  }

  bool _variantMismatch(
    ProductIdentityProfile probe,
    ProductIdentityProfile candidate,
  ) {
    final probeColor = probe.specs[PartSpecKind.colorVariant];
    final candidateColor = candidate.specs[PartSpecKind.colorVariant];
    return probeColor != null &&
        candidateColor != null &&
        probeColor != candidateColor;
  }

  /// Agreement weighted by how much of the invoice's evidence the candidate
  /// actually answers.
  ///
  /// A ratio alone rewards a product that states almost nothing: a generic
  /// `volante … 170mm` matched the single measurement it happened to mention
  /// and scored a perfect agreement against an invoice line that specified
  /// three, tying with the real IXF crankset.
  double _specAgreement(
    ProductIdentityProfile probe,
    ProductIdentityProfile candidate,
  ) {
    var shared = 0;
    var comparable = 0;
    var stated = 0;
    for (final entry in probe.specs.entries) {
      if (entry.key == PartSpecKind.colorVariant) continue;
      stated++;
      final other = candidate.specs[entry.key];
      if (other == null) continue;
      comparable++;
      if (other == entry.value) shared++;
    }
    if (comparable == 0 || stated == 0) return 0;
    final agreement = shared / comparable;
    final coverage = comparable / stated;
    return agreement * coverage;
  }

  /// Symmetric word agreement.
  ///
  /// Containment over the smaller set was the previous measure and it rewarded
  /// emptiness: `ROTOR SHIMANO AE 160MM` has almost no words, so every one of
  /// them was shared and it scored a perfect overlap against a detailed
  /// invoice line — outranking the `RT56` the invoice actually named.
  double _overlap(Set<String> left, Set<String> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    final shared = left.intersection(right).length;
    if (shared == 0) return 0;
    return 2 * shared / (left.length + right.length);
  }

  /// 1.0 when the two categories are the same node or one contains the other
  /// in the tenant tree; 0 when they are unrelated.
  double _categoryAgreement(
    ProductIdentityProfile probe,
    ProductIdentityProfile candidate,
  ) {
    final probePath = _expandPath(probe.categoryPath);
    final candidatePath = _expandPath(candidate.categoryPath);
    if (probePath.isEmpty || candidatePath.isEmpty) return 0;
    if (probePath.join('/') == candidatePath.join('/')) return 1;
    final shorter =
        probePath.length <= candidatePath.length ? probePath : candidatePath;
    final longer =
        probePath.length <= candidatePath.length ? candidatePath : probePath;
    var prefix = 0;
    for (var index = 0; index < shorter.length; index++) {
      if (shorter[index] != longer[index]) break;
      prefix++;
    }
    if (prefix == shorter.length) return 1;
    if (prefix == 0) return 0;
    return prefix / shorter.length * 0.6;
  }

  List<String> _expandPath(List<String> path) {
    if (path.isEmpty) return path;
    if (path.length > 1) return path;
    final expanded = categoryAncestry[path.single];
    return expanded ?? path;
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  static String _upper(String value) => value.toUpperCase();
}

/// Decides which surviving candidates are worth an operator's attention.
///
/// Separate from [ProductIdentityMatcher] on purpose: elimination is about
/// physical truth, this is about how much of the truth is useful. The owner's
/// rule — *«no muestres basura para completar un top-k»* — is implemented
/// here, by refusing to pad rather than by lowering a threshold.
class IdentityShortlistPolicy {
  const IdentityShortlistPolicy({
    this.limit = 6,
    this.absoluteFloor = 0.45,
    this.relativeBand = 0.30,
  });

  final int limit;

  /// Nothing weaker than this is ever offered, even when the list is empty.
  /// An empty list is an honest answer; a bad suggestion is not.
  final double absoluteFloor;

  /// How far below the best candidate a peer may still be useful.
  final double relativeBand;

  List<T> apply<T>(
    List<T> candidates,
    ProductIdentityMatch Function(T) matchOf,
  ) {
    final accepted =
        candidates.where((candidate) => !matchOf(candidate).isRejected).toList()
          ..sort((left, right) {
            final leftMatch = matchOf(left);
            final rightMatch = matchOf(right);
            final byVerdict =
                leftMatch.verdict.index.compareTo(rightMatch.verdict.index);
            if (byVerdict != 0) return byVerdict;
            return rightMatch.score.compareTo(leftMatch.score);
          });
    if (accepted.isEmpty) return const [];

    final best = matchOf(accepted.first);
    if (best.verdict == IdentityMatchVerdict.exact) {
      return accepted
          .where((candidate) =>
              matchOf(candidate).verdict == IdentityMatchVerdict.exact)
          .take(limit)
          .toList(growable: false);
    }

    // The absolute floor exists to keep *unrelated* products out. Family
    // agreement is precisely the evidence that a product is not unrelated, and
    // the family gate has already run — so a survivor that shares the object
    // family is offerable however modest its score. Applying the flat floor to
    // it is what made a whole shelf of `Postiza` disappear behind «Sin
    // coincidencia fiable» while the right one sat in the catalog.
    bool sharesFamily(T candidate) => matchOf(candidate).gates.any(
          (gate) =>
              gate.id == 'familia' &&
              gate.outcome == IdentityGateOutcome.passed,
        );

    final bestSharesFamily = sharesFamily(accepted.first);
    final floor = math.max(absoluteFloor, best.score - relativeBand);
    return accepted
        .where((candidate) =>
            matchOf(candidate).score >= floor ||
            (sharesFamily(candidate) && !bestSharesFamily) ||
            (sharesFamily(candidate) &&
                matchOf(candidate).score >= best.score - relativeBand))
        .take(limit)
        .toList(growable: false);
  }
}
