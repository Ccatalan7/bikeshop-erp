import '../../ai_assistant/services/ai_service.dart';

typedef ProductIdentityAuthorityLookup<TAuthority> = Future<TAuthority?>
    Function();
typedef ProductIdentityInvestigator = Future<AIProductIdentityInvestigation?>
    Function();
typedef ProductIdentityGroundedMatcher<TResult> = Future<TResult> Function(
  AIProductIdentityInvestigation? investigation,
);

sealed class ProductIdentityReviewCoordination<TAuthority, TResult> {
  const ProductIdentityReviewCoordination();
}

class ProductIdentityAuthorityCoordination<TAuthority, TResult>
    extends ProductIdentityReviewCoordination<TAuthority, TResult> {
  const ProductIdentityAuthorityCoordination(this.authority);

  final TAuthority authority;
}

class ProductIdentityMatchedCoordination<TAuthority, TResult>
    extends ProductIdentityReviewCoordination<TAuthority, TResult> {
  const ProductIdentityMatchedCoordination({
    required this.result,
    required this.investigation,
    this.investigationFailure,
  });

  final TResult result;
  final AIProductIdentityInvestigation? investigation;
  final Object? investigationFailure;
}

class ProductIdentityFailedCoordination<TAuthority, TResult>
    extends ProductIdentityReviewCoordination<TAuthority, TResult> {
  const ProductIdentityFailedCoordination({
    required this.failure,
    required this.authorityReadFailed,
  });

  final Object failure;
  final bool authorityReadFailed;
}

/// Enforces the only legal order for supplier-line identity review.
///
/// A confirmed immutable authority wins without model calls. A failed
/// authority read fails closed. Only a proven not-found (`null`) reaches the
/// primary investigation, and even an investigation failure is passed to the
/// matcher as `null` so that its canonical behavior is an explicit abstention
/// rather than a deterministic recommendation.
class ProductIdentityReviewCoordinator<TAuthority, TResult> {
  const ProductIdentityReviewCoordinator();

  Future<ProductIdentityReviewCoordination<TAuthority, TResult>> resolve({
    required ProductIdentityAuthorityLookup<TAuthority> lookupAuthority,
    required ProductIdentityInvestigator investigate,
    required ProductIdentityGroundedMatcher<TResult> match,
  }) async {
    TAuthority? authority;
    try {
      authority = await lookupAuthority();
    } on Object catch (error) {
      return ProductIdentityFailedCoordination<TAuthority, TResult>(
        failure: error,
        authorityReadFailed: true,
      );
    }
    if (authority != null) {
      return ProductIdentityAuthorityCoordination<TAuthority, TResult>(
        authority,
      );
    }

    AIProductIdentityInvestigation? investigation;
    Object? investigationFailure;
    try {
      investigation = await investigate();
    } on Object catch (error) {
      investigationFailure = error;
    }

    try {
      final result = await match(investigation);
      return ProductIdentityMatchedCoordination<TAuthority, TResult>(
        result: result,
        investigation: investigation,
        investigationFailure: investigationFailure,
      );
    } on Object catch (error) {
      return ProductIdentityFailedCoordination<TAuthority, TResult>(
        failure: error,
        authorityReadFailed: false,
      );
    }
  }
}
