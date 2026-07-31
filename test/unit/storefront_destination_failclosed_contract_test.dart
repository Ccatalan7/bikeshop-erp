import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_destination.dart';
import '../support/library_source.dart';

/// Authored destinations must be canonical, discriminated and fail-closed.
///
/// Two defects motivated this: the picker displayed "todavía está en
/// borrador" and still let the operator press Aplicar, and a legacy bare UUID
/// was resolved page-first and then rewritten to `/productos/<uuid>` blindly —
/// including when the page it found belonged to a **different tenant**.
void main() {
  final editorSource = File(
    'lib/modules/website/widgets/website_link_value_editor.dart',
  ).readAsStringSync();
  final layoutSource = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');

  group('the canonical route is already a stable discriminant', () {
    // This is why no `{kind, entityId, canonicalHref}` envelope migration is
    // needed: every authored href already parses to exactly one kind, so the
    // persisted route carries the discriminant without touching a single
    // stored record or consumer.
    test('each canonical shape resolves to exactly one kind', () {
      final cases = <String, WebsiteDestinationKind>{
        '/pagina/faq': WebsiteDestinationKind.page,
        '/productos/categoria/rutas': WebsiteDestinationKind.category,
        '/servicios/categoria/mantenciones': WebsiteDestinationKind.category,
        '/productos/camara-aro-26/AE0037': WebsiteDestinationKind.product,
        '/contacto': WebsiteDestinationKind.system,
        '/productos': WebsiteDestinationKind.system,
        'https://otro.cl/x': WebsiteDestinationKind.external,
        '#seccion': WebsiteDestinationKind.anchor,
      };
      cases.forEach((href, expected) {
        expect(
          WebsiteDestination.parse(href).kind,
          expected,
          reason: '$href must discriminate as $expected',
        );
      });
    });

    test('a page route and a category route are never confused', () {
      expect(
        WebsiteDestination.parse('/pagina/rutas').kind,
        isNot(WebsiteDestination.parse('/productos/categoria/rutas').kind),
      );
    });

    test('a bare UUID is not a canonical destination of any kind', () {
      const uuid = '11111111-2222-3333-4444-555555555555';
      final parsed = WebsiteDestination.parse(uuid);
      expect(parsed.kind, isNot(WebsiteDestinationKind.product));
      expect(parsed.kind, isNot(WebsiteDestinationKind.page));
    });
  });

  group('the picker refuses an unusable destination', () {
    test('a readiness gate blocks Aplicar', () {
      expect(editorSource, contains('_blockingReadinessMessage()'));
      expect(
        editorSource,
        contains('final blocking = _blockingReadinessMessage();'),
      );
      // The gate must run inside _apply, before the dialog pops its result.
      final gate = editorSource.indexOf('final blocking =');
      final pop = editorSource.indexOf('Navigator.of(context).pop(\n      '
          '_WebsiteLinkPickerResult(url, openPanel: openPanel),');
      expect(gate, greaterThan(0));
      expect(pop, greaterThan(gate));
    });

    test('every owned destination type is covered', () {
      for (final marker in const [
        '_InternalDestinationType.page:',
        '_InternalDestinationType.category:',
        '_InternalDestinationType.product:',
      ]) {
        expect(editorSource, contains(marker));
      }
    });

    test('a draft page, hidden category or unpublished product all block', () {
      expect(editorSource, contains('La página está en borrador'));
      expect(
        editorSource,
        contains('La categoría está oculta del catálogo público'),
      );
      expect(editorSource, contains('El producto no está publicado en la web'));
    });

    test('a still-loading owner blocks rather than passing optimistically', () {
      expect(
        editorSource,
        contains('Todavía se está comprobando la página seleccionada.'),
      );
      expect(
        editorSource,
        contains('Todavía se está comprobando la categoría seleccionada.'),
      );
      expect(
        editorSource,
        contains('Todavía se está comprobando el producto seleccionado.'),
      );
    });

    test('a nonexistent owner blocks', () {
      expect(editorSource, contains('No existe una página CMS con esta ruta'));
      expect(editorSource, contains('ya no existe en el catálogo'));
      expect(editorSource, contains('ya no existe en este catálogo'));
    });
  });

  group('a legacy UUID never navigates by blind fallback', () {
    test('the blind product rewrite is gone', () {
      expect(
          layoutSource, isNot(contains("internalHref = '/productos/\$uuid'")));
    });

    test('the product side is verified, tenant-scoped and publication-aware',
        () {
      expect(layoutSource, contains('getProductById('));
      expect(layoutSource, contains('tenantId: tenantId'));
      expect(
        layoutSource,
        contains('PublicProductVisibilityPolicy.fromSettings'),
      );
      // Only a resolved public product yields a canonical route.
      expect(
        layoutSource,
        contains('product == null ? null : publicProductPath(product)'),
      );
    });

    test('an unresolvable legacy reference stays inert', () {
      // 0 owners and 2 owners take the same refusal path.
      expect(layoutSource, contains('if (owners.length != 1)'));
      expect(
        layoutSource,
        contains('public owners, expected exactly one'),
      );
    });

    test('the page candidate is tenant-scoped and publication-gated', () {
      expect(
        layoutSource,
        contains("(p) => p?.id == uuid && p?.tenantId == tenantId"),
      );
      expect(layoutSource, contains('ownedPage.isPublished'));
      expect(
        layoutSource,
        contains('_pagePublication.allowsHref(ownedPage.fullPath)'),
      );
    });

    test('no unscoped page lookup by id remains', () {
      // `getPageById(uuid)` queried website_pages by id alone, so it could
      // read another tenant's row — and accepted it outright when the active
      // tenant was unknown.
      expect(
        layoutSource,
        isNot(contains('await websiteService.getPageById(')),
      );
    });

    test('both owners are always evaluated, never page-first short-circuit',
        () {
      // The product lookup must not sit inside an `else` that a resolved page
      // can skip.
      final pageHref = layoutSource.indexOf('String? pageHref;');
      final productLookup = layoutSource.indexOf('getProductById(');
      final ownersList = layoutSource.indexOf('final owners = <String>[');
      expect(pageHref, greaterThan(0));
      expect(productLookup, greaterThan(pageHref));
      expect(ownersList, greaterThan(productLookup));
    });

    test('exactly one public owner is required', () {
      expect(layoutSource, contains('if (owners.length != 1)'));
      expect(layoutSource, contains('internalHref = owners.single'));
      expect(
        layoutSource,
        contains('public owners, expected exactly one'),
      );
    });

    test('unknown page authority is fail-closed', () {
      expect(
        layoutSource,
        contains('hasAuthoritativePagePublicationForTenant(tenantId)'),
      );
      expect(
        layoutSource,
        contains('publication for this tenant is unknown'),
      );
    });

    test('an absent tenant makes the reference inert', () {
      expect(
        layoutSource,
        contains("if (tenantId == null || tenantId.trim().isEmpty)"),
      );
    });
  });

  group('capability retry is bounded, tenant-owned and timer-driven', () {
    test('a failed read releases the in-flight latch', () {
      // Without this the same tenant could never retry: the guard latched on
      // the requested id and only a full reload cleared it.
      expect(
        layoutSource,
        contains('_paymentCapabilitiesRequestedTenantId = null;'),
      );
    });

    test('the attempt budget belongs to exactly one tenant', () {
      // A global budget let tenant A\'s three failures lock tenant B out
      // forever, because the reset keyed on the in-flight marker that every
      // failure nulls.
      expect(layoutSource, contains('_paymentCapabilitiesAttemptsTenantId'));
      expect(
        layoutSource,
        contains('if (_paymentCapabilitiesAttemptsTenantId != normalized) {'),
      );
    });

    test('the deadline is a real timer, never a passive rebuild gate', () {
      expect(layoutSource, contains('_paymentCapabilitiesRetryTimer = Timer('));
      expect(layoutSource, contains('_kPaymentCapabilityMaxAttempts'));
      expect(layoutSource, contains('_kPaymentCapabilityBackoff'));
      // The passive DateTime gate is gone with its rebuild dependency.
      expect(layoutSource, isNot(contains('_paymentCapabilitiesRetryAfter')));
    });

    test('the build-path check is pure', () {
      expect(
        layoutSource,
        contains('_paymentCapabilityAutoLoadDue(normalized)'),
      );
      // The old check mutated the attempt budget from inside build.
      expect(layoutSource, isNot(contains('_paymentCapabilityRetryDue')));
    });

    test('the timer is cancelled on tenant switch, success and dispose', () {
      expect(
        RegExp(r'_paymentCapabilitiesRetryTimer\?\.cancel\(\);')
            .allMatches(layoutSource)
            .length,
        greaterThanOrEqualTo(3),
      );
      // Stale timers are additionally inert via the generation comparison.
      expect(
        layoutSource,
        contains('generation != _paymentCapabilitiesGeneration'),
      );
    });

    test('failure still claims nothing', () {
      expect(layoutSource, contains('_paymentCapabilities = null;'));
    });
  });

  group('obsolete payment scaffolding is gone', () {
    test('no "hardcoded payment" comments remain', () {
      expect(layoutSource.toLowerCase(), isNot(contains('now hardcoded')));
    });
  });

  group('/contacto availability uses real authority', () {
    final contactSource = File(
      'lib/public_store/pages/contact_page.dart',
    ).readAsStringSync();

    test('authority comes from the tenant-scoped flag, not list emptiness', () {
      expect(
        contactSource,
        contains('hasAuthoritativePagePublicationForTenant('),
      );
      expect(
        contactSource,
        isNot(contains('isAuthoritative: service.pages.isNotEmpty')),
      );
    });

    test('unknown is fail-closed in public', () {
      expect(contactSource,
          contains('if (normalizedTenantId.isEmpty) return false;'));
      expect(contactSource, contains('return false;'));
    });

    test('an authoritative empty list counts as authority', () {
      // resolve() is called with isAuthoritative: true once the flag says so,
      // so zero published pages correctly means "not published".
      expect(contactSource, contains('isAuthoritative: true'));
    });

    test('Edit and Preview bypass the public gate', () {
      expect(
        contactSource,
        contains('if (!isEditorContext &&'),
      );
    });
  });
}
