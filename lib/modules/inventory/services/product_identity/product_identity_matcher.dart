import 'dart:math' as math;
import 'dart:typed_data';

import 'bike_part_taxonomy.dart';
import 'canonical_product_identity_resolver.dart';
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
  /// The same catalog object, established without judgement: an authoritative
  /// catalog SKU or an immutable, confirmed supplier-variant alias.
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

  bool get isExact => sameCatalogSku || confirmedAlias;

  bool get isAny => isExact || sameSupplierListing || sameImageIdentity;

  static const none = DeterministicIdentityEvidence();
}

/// Everything the matcher concluded about one candidate.
class ProductIdentityMatch {
  const ProductIdentityMatch({
    required this.verdict,
    required this.score,
    required this.lineScore,
    required this.variantAgreement,
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

  /// Ranking strength from product-line identity only.
  ///
  /// The selected variant is intentionally absent. [score] may be the next
  /// representable value only when [variantAgreement] breaks an exact tie.
  final double lineScore;

  /// Both rows explicitly state the same selected colour/variant.
  final bool variantAgreement;

  final List<IdentityGate> gates;

  /// Why this product was offered, in the shop's own words.
  final List<String> reasons;

  /// What does not line up, including the reason a candidate was refused.
  final List<String> objections;

  /// Same product line, different sold variant (colour).
  final bool variantMismatch;

  final Set<String> matchedModelCodes;

  bool get isRejected => verdict == IdentityMatchVerdict.rejected;

  /// Lexicographic order used by callers that can compare the components
  /// directly: verdict, line evidence, then selected-variant agreement.
  int compareRankTo(ProductIdentityMatch other) {
    final byVerdict = verdict.index.compareTo(other.verdict.index);
    if (byVerdict != 0) return byVerdict;
    final byLine = other.lineScore.compareTo(lineScore);
    if (byLine != 0) return byLine;
    if (variantAgreement != other.variantAgreement) {
      return variantAgreement ? -1 : 1;
    }
    return 0;
  }
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

  /// Families for which a stated body material identifies a genuinely
  /// different sellable object. Assemblies and multi-material products stay
  /// outside this gate because `aluminio` may describe only one subcomponent.
  static const Set<String> _materialScopedFamilies = <String>{
    'bottle_cage',
    'phone_mount',
    'pedal',
    'stem',
    'stem_spacer',
    'handlebar',
    'seatpost',
    'seatpost_shim',
    'crank_arm',
    'chainring',
    'chainring_guard',
    'chain_guide',
    'hub',
    'rim',
    'axle',
    'axle_adapter',
    'rack',
    'fender',
    'kickstand',
  };

  ProductIdentityMatch evaluate({
    required ProductIdentityProfile probe,
    required ProductIdentityProfile candidate,
    CanonicalProductIdentity? probeIdentity,
    CanonicalProductIdentity? candidateIdentity,
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
      return ProductIdentityMatch(
        verdict: IdentityMatchVerdict.exact,
        score: 1,
        lineScore: 1,
        variantAgreement: false,
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
    final effectiveProbeModels = <String>{
      ...probe.modelCodes,
      ...probe.selectedOptionModelCodes,
    };
    final effectiveProbePrimaryModels = <String>{
      ...probe.primaryModelCodes,
      ...probe.selectedOptionModelCodes,
    };
    final sharedModels =
        effectiveProbeModels.intersection(candidate.modelCodes);
    final hasModelMatch = sharedModels.isNotEmpty;

    // Only a code printed in the product's own name (or declared in its model
    // field) may make a candidate *strong*.
    final sharedPrimaryModels =
        effectiveProbePrimaryModels.intersection(candidate.primaryModelCodes);
    final hasPrimaryModelMatch = sharedPrimaryModels.isNotEmpty;

    // ── Gate 1: what kind of object is it ───────────────────────────────
    final probeFamily = probeIdentity == null
        ? probe.effectiveFamilyId
        : probeIdentity.resolvedFamilyId;
    final candidateFamily = candidateIdentity == null
        ? candidate.effectiveFamilyId
        : candidateIdentity.resolvedFamilyId;
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
      final probeValue = _effectiveSpec(probe, kind);
      final candidateValue = _effectiveSpec(candidate, kind);
      if (probeValue == null || candidateValue == null) continue;
      if (_exclusiveSpecCompatible(
        kind,
        probeValue,
        candidateValue,
        probeFamily,
        candidateFamily,
      )) {
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
      objections.add(
        kind == PartSpecKind.colorVariant
            ? 'Otro color: $candidateValue en vez de $probeValue'
            : '${_capitalize(partSpecLabel(kind))}: $detail',
      );
      return _rejected(
        gates,
        objections,
        variantMismatch: kind == PartSpecKind.colorVariant,
      );
    }

    // ── Gate 2b: explicitly stated construction material ───────────────
    if (probeFamily != null &&
        probeFamily == candidateFamily &&
        _materialScopedFamilies.contains(probeFamily)) {
      final probeMaterial =
          _effectiveSpec(probe, PartSpecKind.constructionMaterial);
      final candidateMaterial =
          _effectiveSpec(candidate, PartSpecKind.constructionMaterial);
      if (probeMaterial != null && candidateMaterial != null) {
        if (probeMaterial != candidateMaterial) {
          final detail =
              '${partSpecValueLabel(PartSpecKind.constructionMaterial, probeMaterial)} ≠ '
              '${partSpecValueLabel(PartSpecKind.constructionMaterial, candidateMaterial)}';
          gates.add(IdentityGate(
            id: 'spec:${PartSpecKind.constructionMaterial.name}',
            label: partSpecLabel(PartSpecKind.constructionMaterial),
            outcome: IdentityGateOutcome.failed,
            detail: detail,
          ));
          objections.add('Material: $detail');
          return _rejected(gates, objections);
        }
        gates.add(IdentityGate(
          id: 'spec:${PartSpecKind.constructionMaterial.name}',
          label: partSpecLabel(PartSpecKind.constructionMaterial),
          outcome: IdentityGateOutcome.passed,
          detail: partSpecValueLabel(
            PartSpecKind.constructionMaterial,
            probeMaterial,
          ),
        ));
        reasons.add(
          'Material ${partSpecValueLabel(PartSpecKind.constructionMaterial, probeMaterial)}',
        );
      }
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

    if (deterministic.sameSupplierListing) {
      reasons.add('Misma publicación del proveedor');
    }
    if (deterministic.sameImageIdentity) {
      reasons.add('Misma foto de la publicación; no confirma la variante');
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
    final probeAssertsModel = effectiveProbePrimaryModels.isNotEmpty;
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
    final probeColor = _effectiveSpec(probe, PartSpecKind.colorVariant);
    final candidateColor = _effectiveSpec(candidate, PartSpecKind.colorVariant);
    final variantAgrees =
        !variantMismatch && probeColor != null && probeColor == candidateColor;
    if (variantAgrees) {
      reasons.add(
        'Color $probeColor',
      );
    }

    var score = 0.0;
    score += familyAgrees ? 0.34 : 0.0;
    score += brandAgrees ? 0.20 : 0.0;
    score += specAgreement * 0.22;
    score += descriptorOverlap * 0.16;
    // Category already selected the normal candidate scope. It describes
    // where the shop files this family; counting it again as identity evidence
    // would reward placement twice and penalize an uncategorized gold row.
    if (deterministic.sameSupplierListing) score += 0.04;
    if (deterministic.sameImageIdentity) score += 0.04;
    if (hasStatedDifference) score -= 0.08;
    if (!hasPrimaryModelMatch) {
      // Keep every non-model candidate below the model floor without
      // flattening distinct line evidence into the same value. The old hard
      // clamp made `same photo + same material` tie with a colour-only row,
      // after which the variant tie-break could promote the weaker identity.
      const oldCeiling = _modelMatchFloor - 0.05;
      const preservedCeiling = _modelMatchFloor - 0.01;
      if (score > oldCeiling) {
        score = oldCeiling +
            (score - oldCeiling) *
                ((preservedCeiling - oldCeiling) / (1 - oldCeiling));
      }
    }
    score = score.clamp(0, 1).toDouble();

    IdentityMatchVerdict verdict;
    if (hasPrimaryModelMatch && familyAgrees) {
      verdict = IdentityMatchVerdict.strong;
      // A shared model establishes a strong candidate, but several sold
      // variants can share it. Preserve secondary evidence as a deterministic
      // tie-breaker instead of flattening every model match to exactly 0.95.
      score = _modelMatchFloor + (1 - _modelMatchFloor) * score;
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

    final lineScore = score;
    // Encode the lexicographic tie-break for existing score-only callers with
    // one ULP. It beats an exactly equal line score and cannot leapfrog any
    // strictly stronger representable line score.
    score = variantAgrees ? _nextUp(lineScore) : lineScore;

    return ProductIdentityMatch(
      verdict: verdict,
      score: score,
      lineScore: lineScore,
      variantAgreement: variantAgrees,
      gates: List<IdentityGate>.unmodifiable(gates),
      reasons: List<String>.unmodifiable(reasons),
      objections: List<String>.unmodifiable(objections),
      variantMismatch: variantMismatch,
      matchedModelCodes: sharedPrimaryModels,
    );
  }

  ProductIdentityMatch _rejected(
    List<IdentityGate> gates,
    List<String> objections, {
    bool variantMismatch = false,
  }) {
    return ProductIdentityMatch(
      verdict: IdentityMatchVerdict.rejected,
      score: 0,
      lineScore: 0,
      variantAgreement: false,
      gates: List<IdentityGate>.unmodifiable(gates),
      reasons: const <String>[],
      objections: List<String>.unmodifiable(objections),
      variantMismatch: variantMismatch,
      matchedModelCodes: const <String>{},
    );
  }

  bool _variantMismatch(
    ProductIdentityProfile probe,
    ProductIdentityProfile candidate,
  ) {
    final probeColor = _effectiveSpec(probe, PartSpecKind.colorVariant);
    final candidateColor = _effectiveSpec(candidate, PartSpecKind.colorVariant);
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
    // Product-line evidence and purchased-option evidence have different
    // jobs.  A selected colour/side/material may reject another sold variant
    // or break an otherwise exact tie, but it must not inflate the score that
    // asks whether these are the same catalog line.  Reading the merged
    // `specs` view here made one option token count twice: once as line
    // evidence and again as the variant tie-break.
    for (final entry in probe.lineSpecs.entries) {
      if (entry.key == PartSpecKind.colorVariant) continue;
      final other = candidate.lineSpecs[entry.key];
      if (entry.key == PartSpecKind.constructionMaterial) {
        final family = probe.effectiveFamilyId;
        if (family == null ||
            family != candidate.effectiveFamilyId ||
            !_materialScopedFamilies.contains(family) ||
            other == null) {
          // Material is evidence only as an explicit two-sided statement in a
          // family where it describes the sold object's body.
          continue;
        }
      }
      stated++;
      if (other == null) continue;
      comparable++;
      if (_exclusiveSpecCompatible(
        entry.key,
        entry.value,
        other,
        probe.effectiveFamilyId,
        candidate.effectiveFamilyId,
      )) {
        shared++;
      }
    }
    if (comparable == 0 || stated == 0) return 0;
    final agreement = shared / comparable;
    final coverage = comparable / stated;
    return agreement * coverage;
  }

  String? _effectiveSpec(ProductIdentityProfile profile, PartSpecKind kind) {
    return profile.variantSpecs[kind] ?? profile.lineSpecs[kind];
  }

  /// Next IEEE-754 value for a finite non-negative score.
  static double _nextUp(double value) {
    if (value.isNaN || value >= 1) return value;
    if (value == 0) return double.minPositive;
    final data = ByteData(8)..setFloat64(0, value, Endian.host);
    final bits = data.getUint64(0, Endian.host) + 1;
    data.setUint64(0, bits, Endian.host);
    return data.getFloat64(0, Endian.host);
  }

  bool _exclusiveSpecCompatible(
    PartSpecKind kind,
    String left,
    String right,
    String? leftFamily,
    String? rightFamily,
  ) {
    if (left == right) return true;
    if (kind != PartSpecKind.valveType ||
        leftFamily != 'valve_adapter' ||
        rightFamily != 'valve_adapter') {
      return false;
    }

    // A title that says only the target side (`to Schrader`) has not stated
    // the other side of the adapter. It is compatible with the complete pair
    // `Presta ↔ Schrader`; treating the incomplete half as a contradiction is
    // how the scooter adapter beat the real AE0001 row.
    final leftStandards = left.split('_').toSet();
    final rightStandards = right.split('_').toSet();
    return leftStandards.containsAll(rightStandards) ||
        rightStandards.containsAll(leftStandards);
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
    ProductIdentityMatch Function(T) matchOf, {
    String Function(T)? stableKeyOf,
  }) {
    // `List.sort` is not stable. Keep the source position as the final fallback
    // so generic callers cannot reshuffle exact ties by accident; catalog
    // callers additionally provide a SKU/product key and therefore get a
    // deterministic total order independent of retrieval order.
    final accepted = candidates
        .asMap()
        .entries
        .where(
          (entry) => !matchOf(entry.value).isRejected,
        )
        .toList()
      ..sort((left, right) {
        final ranked = compareCandidates(
          left.value,
          right.value,
          matchOf,
          stableKeyOf: stableKeyOf,
        );
        return ranked != 0 ? ranked : left.key.compareTo(right.key);
      });
    if (accepted.isEmpty) return const [];

    final ordered = accepted.map((entry) => entry.value).toList(
          growable: false,
        );

    final best = matchOf(ordered.first);
    if (best.verdict == IdentityMatchVerdict.exact) {
      return ordered
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

    final bestSharesFamily = sharesFamily(ordered.first);
    final floor = math.max(absoluteFloor, best.score - relativeBand);
    return ordered
        .where((candidate) =>
            matchOf(candidate).score >= floor ||
            (sharesFamily(candidate) && !bestSharesFamily) ||
            (sharesFamily(candidate) &&
                matchOf(candidate).score >= best.score - relativeBand))
        .take(limit)
        .toList(growable: false);
  }

  /// Canonical order shared by shortlist construction and its service caller.
  ///
  /// [ProductIdentityMatch.compareRankTo] owns evidence ordering. A caller may
  /// append a stable domain key (catalog SKU, then product id/name) without
  /// reimplementing that ranking and drifting from the shortlist.
  static int compareCandidates<T>(
    T left,
    T right,
    ProductIdentityMatch Function(T) matchOf, {
    String Function(T)? stableKeyOf,
  }) {
    final byEvidence = matchOf(left).compareRankTo(matchOf(right));
    if (byEvidence != 0) return byEvidence;
    if (stableKeyOf == null) return 0;
    return stableKeyOf(left).compareTo(stableKeyOf(right));
  }
}
