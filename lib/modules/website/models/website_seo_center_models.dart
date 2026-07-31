import '../../../public_store/models/public_commerce_product_projection.dart';
import '../../../public_store/models/public_product_seo_copy.dart';
import '../../../public_store/utils/product_url.dart';
import '../../../shared/models/product.dart';
import 'website_catalog_presentation.dart';
import 'website_page_models.dart';
import 'website_seo_settings_aliases.dart';

/// Canonical groups shown by the future SEO control center.
enum WebsiteSeoEntityKind { site, page, product, collection }

/// Explains which editable owner supplied an effective metadata value.
///
/// This is intentionally separate from deployment and Google evidence. A
/// value being explicit or inherited says nothing about whether it was built
/// or indexed.
enum WebsiteSeoValueSource {
  explicit,
  ownerFallback,
  inherited,
  missing,
}

enum WebsiteSeoAppEligibilityState { eligible, ineligible }

enum WebsiteSeoAppEligibilityIssue {
  ownerNotPublished(true),
  indexingDisabled(true),
  publicPolicyExcluded(true),
  noEligibleContent(true),
  missingCanonicalPath(true),
  missingTitle(false),
  missingDescription(false),
  missingImage(false);

  const WebsiteSeoAppEligibilityIssue(this.blocksIndexing);

  final bool blocksIndexing;
}

enum WebsiteSeoBuildInclusionState { included, excluded, unknown }

enum WebsiteSeoGoogleIndexState { indexed, notIndexed, unknown, unavailable }

class WebsiteSeoEffectiveValue {
  const WebsiteSeoEffectiveValue({
    required this.value,
    required this.source,
    required this.ownerKind,
    required this.ownerId,
  });

  final String value;
  final WebsiteSeoValueSource source;
  final WebsiteSeoEntityKind ownerKind;
  final String ownerId;

  bool get isPresent => value.isNotEmpty;

  bool get isInherited => source == WebsiteSeoValueSource.inherited;
}

class WebsiteSeoEffectiveMetadata {
  const WebsiteSeoEffectiveMetadata({
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.keywords,
  });

  final WebsiteSeoEffectiveValue title;
  final WebsiteSeoEffectiveValue description;
  final WebsiteSeoEffectiveValue imageUrl;
  final WebsiteSeoEffectiveValue keywords;
}

class WebsiteSeoAppEligibilityEvidence {
  WebsiteSeoAppEligibilityEvidence({
    required List<WebsiteSeoAppEligibilityIssue> issues,
  })  : issues = List.unmodifiable(issues),
        state = issues.any((issue) => issue.blocksIndexing)
            ? WebsiteSeoAppEligibilityState.ineligible
            : WebsiteSeoAppEligibilityState.eligible;

  final WebsiteSeoAppEligibilityState state;
  final List<WebsiteSeoAppEligibilityIssue> issues;

  bool get isEligible => state == WebsiteSeoAppEligibilityState.eligible;

  List<WebsiteSeoAppEligibilityIssue> get blockingIssues =>
      issues.where((issue) => issue.blocksIndexing).toList(growable: false);

  List<WebsiteSeoAppEligibilityIssue> get qualityIssues =>
      issues.where((issue) => !issue.blocksIndexing).toList(growable: false);
}

class WebsiteSeoHttpArtifactEvidence {
  const WebsiteSeoHttpArtifactEvidence({
    required this.url,
    this.observedAt,
    this.reachable,
    this.httpOk,
    this.status,
    this.durationMs,
    required this.contentType,
    required this.etag,
    required this.lastModified,
    this.timedOut,
    required this.error,
  });

  factory WebsiteSeoHttpArtifactEvidence.fromJson(Object? raw) {
    final json = _asStringMap(raw);
    return WebsiteSeoHttpArtifactEvidence(
      url: _text(json['url']),
      observedAt: _dateTime(json['observedAt']),
      reachable: _boolean(json['reachable']),
      httpOk: _boolean(json['httpOk']),
      status: _integer(json['status']),
      durationMs: _integer(json['durationMs']),
      contentType: _text(json['contentType']),
      etag: _text(json['etag']),
      lastModified: _text(json['lastModified']),
      timedOut: _boolean(json['timedOut']),
      error: _text(json['error']),
    );
  }

  final String url;
  final DateTime? observedAt;
  final bool? reachable;
  final bool? httpOk;
  final int? status;
  final int? durationMs;
  final String contentType;
  final String etag;
  final String lastModified;
  final bool? timedOut;
  final String error;
}

class WebsiteSeoReleaseArtifactEvidence {
  const WebsiteSeoReleaseArtifactEvidence({
    required this.http,
    this.documentValid,
    required this.parseError,
    required this.commit,
    required this.run,
    this.builtAt,
    required this.target,
    required this.source,
    this.dirty,
    this.deployValid,
    this.publication,
    this.publicationTracked,
    this.publicationValid,
  });

  factory WebsiteSeoReleaseArtifactEvidence.fromJson(Object? raw) {
    final json = _asStringMap(raw);
    return WebsiteSeoReleaseArtifactEvidence(
      http: WebsiteSeoHttpArtifactEvidence.fromJson(json),
      documentValid: _boolean(json['documentValid']),
      parseError: _text(json['parseError']),
      commit: _text(json['commit']),
      run: _text(json['run']),
      builtAt: _dateTime(json['builtAt']),
      target: _text(json['target']),
      source: _text(json['source']),
      dirty: _boolean(json['dirty']),
      deployValid: _boolean(json['deployValid']),
      publication: json['publication'] == null
          ? null
          : WebsiteSeoReleasePublicationEvidence.fromJson(
              json['publication'],
            ),
      publicationTracked: _boolean(json['publicationTracked']),
      publicationValid: _boolean(json['publicationValid']),
    );
  }

  final WebsiteSeoHttpArtifactEvidence http;
  final bool? documentValid;
  final String parseError;
  final String commit;
  final String run;
  final DateTime? builtAt;
  final String target;
  final String source;
  final bool? dirty;
  final bool? deployValid;
  final WebsiteSeoReleasePublicationEvidence? publication;
  final bool? publicationTracked;
  final bool? publicationValid;

  bool get provesPublishedStoreBuild =>
      deployValid ??
      (documentValid == true &&
          commit.trim().isNotEmpty &&
          builtAt != null &&
          target.trim().toLowerCase() == 'store' &&
          dirty == false);

  /// Whether this release carries a structurally valid editor-publication
  /// correlation. It still must match the database ledger and the other live
  /// origin before the UI may call the editor revision published.
  bool get provesTrackedPublication =>
      provesPublishedStoreBuild &&
      publicationTracked == true &&
      publicationValid == true &&
      publication?.isComplete == true;
}

class WebsiteSeoReleasePublicationEvidence {
  const WebsiteSeoReleasePublicationEvidence({
    required this.requestId,
    required this.ownerRevision,
    required this.ownerSourceSha256,
    required this.buildInputSha256,
  });

  factory WebsiteSeoReleasePublicationEvidence.fromJson(Object? raw) {
    final json = _asStringMap(raw);
    return WebsiteSeoReleasePublicationEvidence(
      requestId: _text(json['requestId'] ?? json['request_id']),
      ownerRevision:
          _integer(json['ownerRevision'] ?? json['owner_revision']) ?? 0,
      ownerSourceSha256: _text(
        json['ownerSourceSha256'] ?? json['owner_source_sha256'],
      ),
      buildInputSha256: _text(
        json['buildInputSha256'] ?? json['build_input_sha256'],
      ),
    );
  }

  final String requestId;
  final int ownerRevision;
  final String ownerSourceSha256;
  final String buildInputSha256;

  bool get isComplete =>
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(requestId) &&
      ownerRevision > 0 &&
      RegExp(r'^[0-9a-f]{64}$', caseSensitive: false)
          .hasMatch(ownerSourceSha256) &&
      RegExp(r'^[0-9a-f]{64}$', caseSensitive: false)
          .hasMatch(buildInputSha256);
}

class WebsiteSeoSitemapArtifactEvidence {
  const WebsiteSeoSitemapArtifactEvidence({
    required this.http,
    this.documentValid,
    this.hasUrlset,
    this.urlEntryCount,
    this.locationCount,
    this.locationsMatchEntries,
    this.invalidLocationCount,
    this.foreignOriginCount,
    this.canonicalOriginConsistent,
  });

  factory WebsiteSeoSitemapArtifactEvidence.fromJson(Object? raw) {
    final json = _asStringMap(raw);
    return WebsiteSeoSitemapArtifactEvidence(
      http: WebsiteSeoHttpArtifactEvidence.fromJson(json),
      documentValid: _boolean(json['documentValid']),
      hasUrlset: _boolean(json['hasUrlset']),
      urlEntryCount: _integer(json['urlEntryCount']),
      locationCount: _integer(json['locationCount']),
      locationsMatchEntries: _boolean(json['locationsMatchEntries']),
      invalidLocationCount: _integer(json['invalidLocationCount']),
      foreignOriginCount: _integer(json['foreignOriginCount']),
      canonicalOriginConsistent: _boolean(json['canonicalOriginConsistent']),
    );
  }

  final WebsiteSeoHttpArtifactEvidence http;
  final bool? documentValid;
  final bool? hasUrlset;
  final int? urlEntryCount;
  final int? locationCount;
  final bool? locationsMatchEntries;
  final int? invalidLocationCount;
  final int? foreignOriginCount;
  final bool? canonicalOriginConsistent;
}

class WebsiteSeoRobotsArtifactEvidence {
  WebsiteSeoRobotsArtifactEvidence({
    required this.http,
    this.documentValid,
    this.hasWildcardUserAgent,
    this.expectedSitemapDeclared,
    List<String> sitemapUrls = const [],
    this.userAgentCount,
    this.disallowDirectiveCount,
    this.rootDisallowDirectivePresent,
  }) : sitemapUrls = List.unmodifiable(sitemapUrls);

  factory WebsiteSeoRobotsArtifactEvidence.fromJson(Object? raw) {
    final json = _asStringMap(raw);
    return WebsiteSeoRobotsArtifactEvidence(
      http: WebsiteSeoHttpArtifactEvidence.fromJson(json),
      documentValid: _boolean(json['documentValid']),
      hasWildcardUserAgent: _boolean(json['hasWildcardUserAgent']),
      expectedSitemapDeclared: _boolean(json['expectedSitemapDeclared']),
      sitemapUrls: _stringList(json['sitemapUrls']),
      userAgentCount: _integer(json['userAgentCount']),
      disallowDirectiveCount: _integer(json['disallowDirectiveCount']),
      rootDisallowDirectivePresent:
          _boolean(json['rootDisallowDirectivePresent']),
    );
  }

  final WebsiteSeoHttpArtifactEvidence http;
  final bool? documentValid;
  final bool? hasWildcardUserAgent;
  final bool? expectedSitemapDeclared;
  final List<String> sitemapUrls;
  final int? userAgentCount;
  final int? disallowDirectiveCount;
  final bool? rootDisallowDirectivePresent;
}

class WebsiteSeoArtifactSummary {
  const WebsiteSeoArtifactSummary({
    this.allReachable,
    this.allHttpOk,
    this.allDocumentsValid,
  });

  factory WebsiteSeoArtifactSummary.fromJson(Object? raw) {
    final json = _asStringMap(raw);
    return WebsiteSeoArtifactSummary(
      allReachable: _boolean(json['allReachable']),
      allHttpOk: _boolean(json['allHttpOk']),
      allDocumentsValid: _boolean(json['allDocumentsValid']),
    );
  }

  final bool? allReachable;
  final bool? allHttpOk;
  final bool? allDocumentsValid;
}

class WebsiteSeoSiteArtifacts {
  const WebsiteSeoSiteArtifacts({
    required this.origin,
    required this.release,
    required this.sitemap,
    required this.robots,
    required this.summary,
  });

  factory WebsiteSeoSiteArtifacts.fromJson(Object? raw) {
    final json = _asStringMap(raw);
    return WebsiteSeoSiteArtifacts(
      origin: _text(json['origin']),
      release: WebsiteSeoReleaseArtifactEvidence.fromJson(json['release']),
      sitemap: WebsiteSeoSitemapArtifactEvidence.fromJson(json['sitemap']),
      robots: WebsiteSeoRobotsArtifactEvidence.fromJson(json['robots']),
      summary: WebsiteSeoArtifactSummary.fromJson(json['summary']),
    );
  }

  final String origin;
  final WebsiteSeoReleaseArtifactEvidence release;
  final WebsiteSeoSitemapArtifactEvidence sitemap;
  final WebsiteSeoRobotsArtifactEvidence robots;
  final WebsiteSeoArtifactSummary summary;

  bool get provesCoherentSiteBuild =>
      summary.allReachable == true &&
      summary.allHttpOk == true &&
      summary.allDocumentsValid == true &&
      release.provesPublishedStoreBuild &&
      sitemap.documentValid == true &&
      robots.documentValid == true &&
      robots.rootDisallowDirectivePresent != true;
}

class WebsiteSeoSearchConsoleEvidence {
  const WebsiteSeoSearchConsoleEvidence({
    this.configured,
    this.ok,
    this.submitted,
    required this.sitemapUrl,
    this.lastSubmitted,
    this.lastDownloaded,
    this.isPending,
    this.warnings,
    this.errors,
    required this.error,
  });

  factory WebsiteSeoSearchConsoleEvidence.fromJson(Object? raw) {
    final json = _asStringMap(raw);
    return WebsiteSeoSearchConsoleEvidence(
      configured: _boolean(json['configured']),
      ok: _boolean(json['ok']),
      submitted: _boolean(json['submitted']),
      sitemapUrl: _text(json['sitemapUrl']),
      lastSubmitted: _dateTime(json['lastSubmitted']),
      lastDownloaded: _dateTime(json['lastDownloaded']),
      isPending: _boolean(json['isPending']),
      warnings: _integer(json['warnings']),
      errors: _integer(json['errors']),
      error: _text(json['error']),
    );
  }

  final bool? configured;
  final bool? ok;
  final bool? submitted;
  final String sitemapUrl;
  final DateTime? lastSubmitted;
  final DateTime? lastDownloaded;
  final bool? isPending;
  final int? warnings;
  final int? errors;
  final String error;
}

class WebsiteSeoSiteStatus {
  const WebsiteSeoSiteStatus({
    required this.available,
    this.observedAt,
    required this.origin,
    required this.siteUrl,
    this.artifacts,
    this.searchConsole,
    required this.indexingDisclaimer,
    required this.error,
  });

  factory WebsiteSeoSiteStatus.fromPayload(
    Object? raw, {
    required DateTime fallbackObservedAt,
  }) {
    final json = _asStringMap(raw);
    if (json.isEmpty || json['ok'] != true) {
      return WebsiteSeoSiteStatus.unavailable(
        observedAt: fallbackObservedAt,
        error: _text(json['error']).isEmpty
            ? 'La acción site_status no está disponible.'
            : _text(json['error']),
      );
    }
    return WebsiteSeoSiteStatus(
      available: true,
      observedAt: _dateTime(json['observedAt']) ?? fallbackObservedAt,
      origin: _text(json['origin']),
      siteUrl: _text(json['siteUrl']),
      artifacts: WebsiteSeoSiteArtifacts.fromJson(json['artifacts']),
      searchConsole:
          WebsiteSeoSearchConsoleEvidence.fromJson(json['searchConsole']),
      indexingDisclaimer: _text(json['indexingDisclaimer']),
      error: '',
    );
  }

  factory WebsiteSeoSiteStatus.unavailable({
    required DateTime observedAt,
    required String error,
  }) {
    return WebsiteSeoSiteStatus(
      available: false,
      observedAt: observedAt,
      origin: '',
      siteUrl: '',
      indexingDisclaimer: '',
      error: error.trim(),
    );
  }

  final bool available;
  final DateTime? observedAt;
  final String origin;
  final String siteUrl;
  final WebsiteSeoSiteArtifacts? artifacts;
  final WebsiteSeoSearchConsoleEvidence? searchConsole;
  final String indexingDisclaimer;
  final String error;
}

class WebsiteSeoBuildEvidence {
  const WebsiteSeoBuildEvidence({
    required this.state,
    this.observedAt,
    this.artifacts,
    required this.releaseCommit,
    required this.releaseRun,
    this.releaseBuiltAt,
    required this.error,
  });

  const WebsiteSeoBuildEvidence.unknown({
    this.observedAt,
    this.artifacts,
    this.releaseCommit = '',
    this.releaseRun = '',
    this.releaseBuiltAt,
    this.error = '',
  }) : state = WebsiteSeoBuildInclusionState.unknown;

  factory WebsiteSeoBuildEvidence.fromSiteStatus(
    WebsiteSeoSiteStatus status,
  ) {
    final artifacts = status.artifacts;
    return WebsiteSeoBuildEvidence(
      // Site-level coherent deploy artifacts prove that the site build exists.
      // They do not prove that any individual page/product/collection URL was
      // included; those owners deliberately remain `unknown`.
      state: artifacts?.provesCoherentSiteBuild == true
          ? WebsiteSeoBuildInclusionState.included
          : WebsiteSeoBuildInclusionState.unknown,
      observedAt: status.observedAt,
      artifacts: artifacts,
      releaseCommit: artifacts?.release.commit ?? '',
      releaseRun: artifacts?.release.run ?? '',
      releaseBuiltAt: artifacts?.release.builtAt,
      error: status.error,
    );
  }

  final WebsiteSeoBuildInclusionState state;
  final DateTime? observedAt;
  final WebsiteSeoSiteArtifacts? artifacts;
  final String releaseCommit;
  final String releaseRun;
  final DateTime? releaseBuiltAt;
  final String error;
}

class WebsiteSeoGoogleEvidence {
  const WebsiteSeoGoogleEvidence({
    required this.state,
    this.observedAt,
    this.configured,
    this.sitemapSubmitted,
    this.lastSubmitted,
    this.lastDownloaded,
    this.isPending,
    required this.googleCanonical,
    this.lastCrawlAt,
    required this.coverageState,
    required this.error,
  });

  const WebsiteSeoGoogleEvidence.unknown({
    this.observedAt,
    this.configured,
    this.sitemapSubmitted,
    this.lastSubmitted,
    this.lastDownloaded,
    this.isPending,
    this.googleCanonical = '',
    this.lastCrawlAt,
    this.coverageState = '',
    this.error = '',
  }) : state = WebsiteSeoGoogleIndexState.unknown;

  factory WebsiteSeoGoogleEvidence.fromSiteStatus(
    WebsiteSeoSiteStatus status,
  ) {
    final searchConsole = status.searchConsole;
    if (!status.available ||
        searchConsole?.configured == false ||
        (searchConsole?.configured == true && searchConsole?.ok == false)) {
      return WebsiteSeoGoogleEvidence(
        state: WebsiteSeoGoogleIndexState.unavailable,
        observedAt: status.observedAt,
        configured: searchConsole?.configured,
        sitemapSubmitted: searchConsole?.submitted,
        lastSubmitted: searchConsole?.lastSubmitted,
        lastDownloaded: searchConsole?.lastDownloaded,
        isPending: searchConsole?.isPending,
        googleCanonical: '',
        coverageState: '',
        error:
            status.error.isNotEmpty ? status.error : searchConsole?.error ?? '',
      );
    }
    return WebsiteSeoGoogleEvidence.unknown(
      observedAt: status.observedAt,
      configured: searchConsole?.configured,
      sitemapSubmitted: searchConsole?.submitted,
      lastSubmitted: searchConsole?.lastSubmitted,
      lastDownloaded: searchConsole?.lastDownloaded,
      isPending: searchConsole?.isPending,
      error: searchConsole?.error ?? '',
    );
  }

  final WebsiteSeoGoogleIndexState state;
  final DateTime? observedAt;
  final bool? configured;
  final bool? sitemapSubmitted;
  final DateTime? lastSubmitted;
  final DateTime? lastDownloaded;
  final bool? isPending;
  final String googleCanonical;
  final DateTime? lastCrawlAt;
  final String coverageState;
  final String error;
}

abstract class WebsiteSeoOwner {
  const WebsiteSeoOwner({
    required this.kind,
    required this.id,
    required this.label,
    required this.canonicalPath,
    required this.isPublished,
    required this.allowsIndexing,
    required this.hasEligibleContent,
    required this.metadata,
    this.additionalEligibilityIssues = const [],
    this.buildEvidence = const WebsiteSeoBuildEvidence.unknown(),
    this.googleEvidence = const WebsiteSeoGoogleEvidence.unknown(),
  });

  final WebsiteSeoEntityKind kind;
  final String id;
  final String label;
  final String canonicalPath;
  final bool isPublished;
  final bool allowsIndexing;
  final bool hasEligibleContent;
  final WebsiteSeoEffectiveMetadata metadata;
  final List<WebsiteSeoAppEligibilityIssue> additionalEligibilityIssues;
  final WebsiteSeoBuildEvidence buildEvidence;
  final WebsiteSeoGoogleEvidence googleEvidence;

  WebsiteSeoEntityProjection project({
    WebsiteSeoBuildEvidence? build,
    WebsiteSeoGoogleEvidence? google,
  }) {
    final issues = <WebsiteSeoAppEligibilityIssue>[
      if (!isPublished) WebsiteSeoAppEligibilityIssue.ownerNotPublished,
      if (!allowsIndexing) WebsiteSeoAppEligibilityIssue.indexingDisabled,
      if (!hasEligibleContent) WebsiteSeoAppEligibilityIssue.noEligibleContent,
      ...additionalEligibilityIssues,
      if (canonicalPath.trim().isEmpty)
        WebsiteSeoAppEligibilityIssue.missingCanonicalPath,
      if (!metadata.title.isPresent) WebsiteSeoAppEligibilityIssue.missingTitle,
      if (!metadata.description.isPresent)
        WebsiteSeoAppEligibilityIssue.missingDescription,
      if (!metadata.imageUrl.isPresent)
        WebsiteSeoAppEligibilityIssue.missingImage,
    ];
    return WebsiteSeoEntityProjection(
      kind: kind,
      id: id,
      label: label,
      canonicalPath: canonicalPath,
      metadata: metadata,
      appEligibility: WebsiteSeoAppEligibilityEvidence(issues: issues),
      buildEvidence: build ?? buildEvidence,
      googleEvidence: google ?? googleEvidence,
    );
  }
}

class WebsiteSeoSiteOwner extends WebsiteSeoOwner {
  factory WebsiteSeoSiteOwner({
    String id = 'site',
    required String storeName,
    required String origin,
    required String title,
    required String description,
    required String imageUrl,
    String keywords = '',
    String locality = '',
    bool allowsIndexing = true,
    WebsiteSeoBuildEvidence buildEvidence =
        const WebsiteSeoBuildEvidence.unknown(),
    WebsiteSeoGoogleEvidence googleEvidence =
        const WebsiteSeoGoogleEvidence.unknown(),
  }) {
    final cleanStoreName = _cleanSeoText(storeName);
    return WebsiteSeoSiteOwner._(
      id: id,
      storeName: cleanStoreName,
      origin: WebsiteSeoSettingsAliases.normalizeHttpsOrigin(origin),
      locality: _cleanSeoText(locality),
      allowsIndexing: allowsIndexing,
      metadata: WebsiteSeoEffectiveMetadata(
        title: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.site,
          ownerId: id,
          candidates: [
            _ValueCandidate(title, WebsiteSeoValueSource.explicit),
            _ValueCandidate(
              cleanStoreName,
              WebsiteSeoValueSource.ownerFallback,
            ),
          ],
        ),
        description: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.site,
          ownerId: id,
          candidates: [
            _ValueCandidate(description, WebsiteSeoValueSource.explicit),
          ],
        ),
        imageUrl: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.site,
          ownerId: id,
          candidates: [
            _ValueCandidate(imageUrl, WebsiteSeoValueSource.explicit),
          ],
        ),
        keywords: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.site,
          ownerId: id,
          candidates: [
            _ValueCandidate(keywords, WebsiteSeoValueSource.explicit),
          ],
        ),
      ),
      buildEvidence: buildEvidence,
      googleEvidence: googleEvidence,
    );
  }

  const WebsiteSeoSiteOwner._({
    required super.id,
    required this.storeName,
    required this.origin,
    required this.locality,
    required super.allowsIndexing,
    required super.metadata,
    required super.buildEvidence,
    required super.googleEvidence,
  }) : super(
          kind: WebsiteSeoEntityKind.site,
          label: storeName,
          canonicalPath: origin,
          isPublished: true,
          hasEligibleContent: true,
        );

  final String storeName;
  final String origin;
  final String locality;
}

class WebsiteSeoPageOwner extends WebsiteSeoOwner {
  factory WebsiteSeoPageOwner.fromPage({
    required WebsitePage page,
    required WebsiteSeoSiteOwner site,
    bool hasEligibleContent = true,
    WebsiteSeoBuildEvidence buildEvidence =
        const WebsiteSeoBuildEvidence.unknown(),
    WebsiteSeoGoogleEvidence googleEvidence =
        const WebsiteSeoGoogleEvidence.unknown(),
  }) {
    final ownerId = page.id;
    final pageTitle = _cleanSeoText(page.title);
    final titledFallback =
        pageTitle.isEmpty ? '' : '$pageTitle | ${site.storeName}';
    return WebsiteSeoPageOwner._(
      page: page,
      metadata: WebsiteSeoEffectiveMetadata(
        title: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.page,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              page.metaTitle,
              WebsiteSeoValueSource.explicit,
            ),
            _ValueCandidate(
              titledFallback,
              WebsiteSeoValueSource.ownerFallback,
            ),
            _inheritedCandidate(site.metadata.title),
          ],
        ),
        description: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.page,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              page.metaDescription,
              WebsiteSeoValueSource.explicit,
            ),
            _inheritedCandidate(site.metadata.description),
          ],
        ),
        imageUrl: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.page,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              page.ogImageUrl,
              WebsiteSeoValueSource.explicit,
            ),
            _inheritedCandidate(site.metadata.imageUrl),
          ],
        ),
        keywords: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.page,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              page.metaKeywords,
              WebsiteSeoValueSource.explicit,
            ),
            _inheritedCandidate(site.metadata.keywords),
          ],
        ),
      ),
      hasEligibleContent: hasEligibleContent,
      buildEvidence: buildEvidence,
      googleEvidence: googleEvidence,
    );
  }

  WebsiteSeoPageOwner._({
    required this.page,
    required super.metadata,
    required super.hasEligibleContent,
    required super.buildEvidence,
    required super.googleEvidence,
  }) : super(
          kind: WebsiteSeoEntityKind.page,
          id: page.id,
          label: page.title,
          canonicalPath: page.fullPath,
          isPublished: page.isPublished,
          allowsIndexing: true,
        );

  final WebsitePage page;
}

class WebsiteSeoProductOwner extends WebsiteSeoOwner {
  factory WebsiteSeoProductOwner.fromProduct({
    required Product product,
    required WebsiteSeoSiteOwner site,
    required String titleTemplate,
    required String descriptionTemplate,
    String? resolvedBrand,
    String? categoryPath,
    bool? isPubliclyEligible,
    WebsiteSeoBuildEvidence buildEvidence =
        const WebsiteSeoBuildEvidence.unknown(),
    WebsiteSeoGoogleEvidence googleEvidence =
        const WebsiteSeoGoogleEvidence.unknown(),
  }) {
    final commerce = PublicCommerceProductProjection.fromProduct(
      product,
      resolvedBrand: resolvedBrand,
      categoryPath: categoryPath,
    );
    final seoCopy = resolvePublicProductSeoCopyFromInput(
      PublicProductSeoCopyInput(
        seoTitleOverride: product.websiteSeoTitle ?? '',
        seoDescriptionOverride: product.websiteSeoDescription ?? '',
        titleTemplate: titleTemplate,
        descriptionTemplate: descriptionTemplate,
        storeName: site.storeName,
        locality: site.locality,
        searchTerms: product.websiteSearchTerms,
        product: PublicProductSeoProductInput(
          name: commerce.title,
          sku: commerce.sku,
          price: commerce.price,
          brand: commerce.brand,
          description: commerce.description,
          categoryPath: commerce.categoryPath,
        ),
      ),
    );
    final image =
        commerce.imageUrls.isEmpty ? '' : commerce.imageUrls.first.trim();
    final ownerId = product.id;
    final ownerIsPublished = product.isActive &&
        product.isPublished &&
        product.lifecycleStatus.trim().toLowerCase() == 'active';
    final isCurrentPublicOwner =
        isPubliclyEligible == true ? true : ownerIsPublished;
    final additionalEligibilityIssues = <WebsiteSeoAppEligibilityIssue>[
      if (isPubliclyEligible == false && ownerIsPublished)
        WebsiteSeoAppEligibilityIssue.publicPolicyExcluded,
    ];
    return WebsiteSeoProductOwner._(
      product: product,
      metadata: WebsiteSeoEffectiveMetadata(
        title: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.product,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              seoCopy.title,
              seoCopy.titleSource == PublicProductSeoValueSource.explicit
                  ? WebsiteSeoValueSource.explicit
                  : WebsiteSeoValueSource.ownerFallback,
            ),
            _inheritedCandidate(site.metadata.title),
          ],
        ),
        description: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.product,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              seoCopy.description,
              seoCopy.descriptionSource == PublicProductSeoValueSource.explicit
                  ? WebsiteSeoValueSource.explicit
                  : WebsiteSeoValueSource.ownerFallback,
            ),
            _inheritedCandidate(site.metadata.description),
          ],
        ),
        imageUrl: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.product,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(image, WebsiteSeoValueSource.ownerFallback),
            _inheritedCandidate(site.metadata.imageUrl),
          ],
        ),
        keywords: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.product,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              seoCopy.searchPhrase,
              WebsiteSeoValueSource.explicit,
            ),
            _inheritedCandidate(site.metadata.keywords),
          ],
        ),
      ),
      isPublished: isCurrentPublicOwner,
      hasEligibleContent:
          commerce.id.isNotEmpty && commerce.title.trim().isNotEmpty,
      additionalEligibilityIssues: additionalEligibilityIssues,
      buildEvidence: buildEvidence,
      googleEvidence: googleEvidence,
    );
  }

  WebsiteSeoProductOwner._({
    required this.product,
    required super.metadata,
    required super.isPublished,
    required super.hasEligibleContent,
    required super.additionalEligibilityIssues,
    required super.buildEvidence,
    required super.googleEvidence,
  }) : super(
          kind: WebsiteSeoEntityKind.product,
          id: product.id,
          label: product.name,
          canonicalPath: publicProductPath(product),
          allowsIndexing: true,
        );

  final Product product;
}

class WebsiteSeoCollectionOwner extends WebsiteSeoOwner {
  factory WebsiteSeoCollectionOwner.fromPresentation({
    required String id,
    required String label,
    required String canonicalPath,
    required bool isPublished,
    required bool hasEligibleContent,
    required WebsiteCatalogPresentation presentation,
    required WebsiteSeoSiteOwner site,
    String canonicalDescription = '',
    String canonicalImageUrl = '',
    WebsiteSeoBuildEvidence buildEvidence =
        const WebsiteSeoBuildEvidence.unknown(),
    WebsiteSeoGoogleEvidence googleEvidence =
        const WebsiteSeoGoogleEvidence.unknown(),
  }) {
    final ownerId = id.trim();
    final cleanLabel = _cleanSeoText(label);
    final titleFallback =
        cleanLabel.isEmpty ? '' : '$cleanLabel | ${site.storeName}';
    return WebsiteSeoCollectionOwner._(
      presentation: presentation,
      id: ownerId,
      label: cleanLabel,
      canonicalPath: canonicalPath,
      isPublished: isPublished,
      hasEligibleContent: hasEligibleContent,
      metadata: WebsiteSeoEffectiveMetadata(
        title: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.collection,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              presentation.seoTitle,
              WebsiteSeoValueSource.explicit,
            ),
            _ValueCandidate(
              presentation.heroTitle,
              WebsiteSeoValueSource.ownerFallback,
            ),
            _ValueCandidate(
              titleFallback,
              WebsiteSeoValueSource.ownerFallback,
            ),
            _inheritedCandidate(site.metadata.title),
          ],
        ),
        description: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.collection,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              presentation.seoDescription,
              WebsiteSeoValueSource.explicit,
            ),
            _ValueCandidate(
              presentation.heroDescription,
              WebsiteSeoValueSource.ownerFallback,
            ),
            _ValueCandidate(
              canonicalDescription,
              WebsiteSeoValueSource.ownerFallback,
            ),
            _inheritedCandidate(site.metadata.description),
          ],
        ),
        imageUrl: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.collection,
          ownerId: ownerId,
          candidates: [
            _ValueCandidate(
              presentation.socialImageUrl,
              WebsiteSeoValueSource.explicit,
            ),
            _ValueCandidate(
              presentation.heroImageUrl,
              WebsiteSeoValueSource.ownerFallback,
            ),
            _ValueCandidate(
              canonicalImageUrl,
              WebsiteSeoValueSource.ownerFallback,
            ),
            _inheritedCandidate(site.metadata.imageUrl),
          ],
        ),
        keywords: _resolveEffectiveValue(
          ownerKind: WebsiteSeoEntityKind.collection,
          ownerId: ownerId,
          candidates: [
            _inheritedCandidate(site.metadata.keywords),
          ],
        ),
      ),
      buildEvidence: buildEvidence,
      googleEvidence: googleEvidence,
    );
  }

  WebsiteSeoCollectionOwner._({
    required this.presentation,
    required super.id,
    required super.label,
    required super.canonicalPath,
    required super.isPublished,
    required super.hasEligibleContent,
    required super.metadata,
    required super.buildEvidence,
    required super.googleEvidence,
  }) : super(
          kind: WebsiteSeoEntityKind.collection,
          allowsIndexing: presentation.allowIndexing,
        );

  final WebsiteCatalogPresentation presentation;
}

class WebsiteSeoCenterOwners {
  WebsiteSeoCenterOwners({
    required this.site,
    Iterable<WebsiteSeoPageOwner> pages = const [],
    Iterable<WebsiteSeoProductOwner> products = const [],
    Iterable<WebsiteSeoCollectionOwner> collections = const [],
    int? categoryOwnerTotal,
  })  : pages = List.unmodifiable(pages),
        products = List.unmodifiable(products),
        collections = List.unmodifiable(collections),
        categoryOwnerTotal = _ownerTotal(
          categoryOwnerTotal,
          collections.length,
        );

  final WebsiteSeoSiteOwner site;
  final List<WebsiteSeoPageOwner> pages;
  final List<WebsiteSeoProductOwner> products;
  final List<WebsiteSeoCollectionOwner> collections;
  final int categoryOwnerTotal;
}

class WebsiteSeoEntityProjection {
  const WebsiteSeoEntityProjection({
    required this.kind,
    required this.id,
    required this.label,
    required this.canonicalPath,
    required this.metadata,
    required this.appEligibility,
    required this.buildEvidence,
    required this.googleEvidence,
  });

  final WebsiteSeoEntityKind kind;
  final String id;
  final String label;
  final String canonicalPath;
  final WebsiteSeoEffectiveMetadata metadata;
  final WebsiteSeoAppEligibilityEvidence appEligibility;
  final WebsiteSeoBuildEvidence buildEvidence;
  final WebsiteSeoGoogleEvidence googleEvidence;
}

class WebsiteSeoGroupSummary {
  const WebsiteSeoGroupSummary({
    required this.total,
    required this.appEligible,
    required this.appIneligible,
    required this.buildIncluded,
    required this.buildExcluded,
    required this.buildUnknown,
    required this.googleIndexed,
    required this.googleNotIndexed,
    required this.googleUnknown,
    required this.googleUnavailable,
  });

  factory WebsiteSeoGroupSummary.fromEntities(
    Iterable<WebsiteSeoEntityProjection> entities,
  ) {
    final items = entities.toList(growable: false);
    int countApp(WebsiteSeoAppEligibilityState state) =>
        items.where((item) => item.appEligibility.state == state).length;
    int countBuild(WebsiteSeoBuildInclusionState state) =>
        items.where((item) => item.buildEvidence.state == state).length;
    int countGoogle(WebsiteSeoGoogleIndexState state) =>
        items.where((item) => item.googleEvidence.state == state).length;
    return WebsiteSeoGroupSummary(
      total: items.length,
      appEligible: countApp(WebsiteSeoAppEligibilityState.eligible),
      appIneligible: countApp(WebsiteSeoAppEligibilityState.ineligible),
      buildIncluded: countBuild(WebsiteSeoBuildInclusionState.included),
      buildExcluded: countBuild(WebsiteSeoBuildInclusionState.excluded),
      buildUnknown: countBuild(WebsiteSeoBuildInclusionState.unknown),
      googleIndexed: countGoogle(WebsiteSeoGoogleIndexState.indexed),
      googleNotIndexed: countGoogle(WebsiteSeoGoogleIndexState.notIndexed),
      googleUnknown: countGoogle(WebsiteSeoGoogleIndexState.unknown),
      googleUnavailable: countGoogle(WebsiteSeoGoogleIndexState.unavailable),
    );
  }

  final int total;
  final int appEligible;
  final int appIneligible;
  final int buildIncluded;
  final int buildExcluded;
  final int buildUnknown;
  final int googleIndexed;
  final int googleNotIndexed;
  final int googleUnknown;
  final int googleUnavailable;
}

class WebsiteSeoCenterProjection {
  WebsiteSeoCenterProjection({
    required this.generatedAt,
    required this.siteStatus,
    required this.site,
    Iterable<WebsiteSeoEntityProjection> pages = const [],
    Iterable<WebsiteSeoEntityProjection> products = const [],
    Iterable<WebsiteSeoEntityProjection> collections = const [],
    int? categoryOwnerTotal,
  })  : pages = List.unmodifiable(pages),
        products = List.unmodifiable(products),
        collections = List.unmodifiable(collections),
        categoryOwnerTotal = _ownerTotal(
          categoryOwnerTotal,
          collections.length,
        ),
        siteSummary = WebsiteSeoGroupSummary.fromEntities([site]),
        pagesSummary = WebsiteSeoGroupSummary.fromEntities(pages),
        productsSummary = WebsiteSeoGroupSummary.fromEntities(products),
        collectionsSummary = WebsiteSeoGroupSummary.fromEntities(collections);

  final DateTime generatedAt;
  final WebsiteSeoSiteStatus siteStatus;
  final WebsiteSeoEntityProjection site;
  final List<WebsiteSeoEntityProjection> pages;
  final List<WebsiteSeoEntityProjection> products;
  final List<WebsiteSeoEntityProjection> collections;
  final int categoryOwnerTotal;
  final WebsiteSeoGroupSummary siteSummary;
  final WebsiteSeoGroupSummary pagesSummary;
  final WebsiteSeoGroupSummary productsSummary;
  final WebsiteSeoGroupSummary collectionsSummary;

  /// Collection rows the owner has actually published.
  ///
  /// Derived from each row's own blocking reason rather than from
  /// `categoryOwnerTotal - collections.length`. That subtraction only worked
  /// while unpublished categories were excluded from the list; now that the
  /// center inventories all of them it would report zero unpublished
  /// categories forever.
  Iterable<WebsiteSeoEntityProjection> get publishedCollections =>
      collections.where((collection) => !_isUnpublished(collection));

  Iterable<WebsiteSeoEntityProjection> get unpublishedCollections =>
      collections.where(_isUnpublished);

  int get publishedCategoryOwnerCount => publishedCollections.length;

  int get unpublishedCategoryOwnerCount {
    final listed = unpublishedCollections.length;
    // A category the center could not list at all (missing id) is still an
    // owner that is not published; never report fewer than the real gap.
    final gap = categoryOwnerTotal - collections.length;
    return gap > 0 ? listed + gap : listed;
  }

  static bool _isUnpublished(WebsiteSeoEntityProjection collection) =>
      collection.appEligibility.blockingIssues.contains(
        WebsiteSeoAppEligibilityIssue.ownerNotPublished,
      );
}

class _ValueCandidate {
  const _ValueCandidate(
    this.value,
    this.source, {
    this.ownerKind,
    this.ownerId,
  });

  final Object? value;
  final WebsiteSeoValueSource source;
  final WebsiteSeoEntityKind? ownerKind;
  final String? ownerId;
}

_ValueCandidate _inheritedCandidate(WebsiteSeoEffectiveValue value) {
  return _ValueCandidate(
    value.value,
    WebsiteSeoValueSource.inherited,
    ownerKind: value.ownerKind,
    ownerId: value.ownerId,
  );
}

WebsiteSeoEffectiveValue _resolveEffectiveValue({
  required WebsiteSeoEntityKind ownerKind,
  required String ownerId,
  required Iterable<_ValueCandidate> candidates,
}) {
  for (final candidate in candidates) {
    final value = _cleanSeoText(_text(candidate.value));
    if (value.isEmpty) continue;
    return WebsiteSeoEffectiveValue(
      value: value,
      source: candidate.source,
      ownerKind: candidate.ownerKind ?? ownerKind,
      ownerId: candidate.ownerId ?? ownerId,
    );
  }
  return WebsiteSeoEffectiveValue(
    value: '',
    source: WebsiteSeoValueSource.missing,
    ownerKind: ownerKind,
    ownerId: ownerId,
  );
}

String _cleanSeoText(String raw) {
  return raw
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Map<String, dynamic> _asStringMap(Object? raw) {
  if (raw is! Map) return const <String, dynamic>{};
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

String _text(Object? value) => value?.toString().trim() ?? '';

bool? _boolean(Object? value) {
  if (value is bool) return value;
  return switch (_text(value).toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => null,
  };
}

int? _integer(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(_text(value));
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) return value;
  final raw = _text(value);
  return raw.isEmpty ? null : DateTime.tryParse(raw);
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) return const <String>[];
  return value
      .map(_text)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int _ownerTotal(int? reportedTotal, int projectedCount) {
  final normalized = reportedTotal ?? projectedCount;
  return normalized < projectedCount ? projectedCount : normalized;
}
