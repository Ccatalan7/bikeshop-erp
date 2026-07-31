import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_seo_center_models.dart';

void main() {
  Map<String, dynamic> release({
    Object? publication,
    bool? publicationTracked,
    bool? publicationValid,
  }) {
    return {
      'url': 'https://vinabike.cl/release.json',
      'documentValid': true,
      'commit': '0123456789abcdef0123456789abcdef01234567',
      'run': '42',
      'builtAt': '2026-07-28T20:00:00Z',
      'target': 'store',
      'source': 'github-actions',
      'dirty': false,
      'deployValid': true,
      'publication': publication,
      'publicationTracked': publicationTracked,
      'publicationValid': publicationValid,
    };
  }

  test('tracked evidence requires complete request revision and hashes', () {
    final evidence = WebsiteSeoReleaseArtifactEvidence.fromJson(
      release(
        publication: {
          'requestId': '11111111-1111-4111-8111-111111111111',
          'ownerRevision': 42,
          'ownerSourceSha256': List.filled(64, 'a').join(),
          'buildInputSha256': List.filled(64, 'b').join(),
        },
        publicationTracked: true,
        publicationValid: true,
      ),
    );

    expect(evidence.provesPublishedStoreBuild, isTrue);
    expect(evidence.provesTrackedPublication, isTrue);
    expect(evidence.publication!.ownerRevision, 42);
  });

  test('a clean push build remains valid but explicitly untracked', () {
    final evidence = WebsiteSeoReleaseArtifactEvidence.fromJson(
      release(
        publication: null,
        publicationTracked: false,
        publicationValid: false,
      ),
    );

    expect(evidence.provesPublishedStoreBuild, isTrue);
    expect(evidence.provesTrackedPublication, isFalse);
    expect(evidence.publication, isNull);
  });

  test('malformed publication never becomes tracked evidence', () {
    final evidence = WebsiteSeoReleaseArtifactEvidence.fromJson(
      release(
        publication: {
          'requestId': 'wrong',
          'ownerRevision': 0,
          'ownerSourceSha256': 'short',
          'buildInputSha256': 'short',
        },
        publicationTracked: true,
        publicationValid: true,
      ),
    );

    expect(evidence.publication!.isComplete, isFalse);
    expect(evidence.provesTrackedPublication, isFalse);
  });
}
