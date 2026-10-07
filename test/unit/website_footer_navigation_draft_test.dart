import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/public_store/services/public_page_publication.dart';

WebsiteNavigation _nav(
  String id, {
  String? parent,
  int order = 0,
  List<WebsiteNavigation> children = const [],
}) {
  final now = DateTime.utc(2026, 10, 7);
  return WebsiteNavigation(
    id: id,
    tenantId: 'tenant',
    menuLocation: MenuLocation.footer,
    label: id,
    linkType: NavLinkType.external,
    linkValue: 'https://example.invalid/$id',
    parentId: parent,
    orderIndex: order,
    children: children,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test(
      'the footer as drafted: sections and links in their pending order, '
      'ready for the page projection', () {
    final provider = WebsiteEditModeProvider();
    addTearDown(provider.dispose);
    final saved = [
      _nav(
        'a',
        children: [
          _nav('a1', parent: 'a'),
          _nav('a2', parent: 'a', order: 1),
        ],
      ),
      _nav('b', order: 1),
    ];
    expect(provider.draftedFooterNavigation(saved).map((s) => s.id), [
      'a',
      'b',
    ]);

    provider
      ..updateFooterSectionOrder(['b', 'a'])
      ..updateFooterLinkOrder('a', ['a2', 'a1'])
      ..updateFooterNavLabel('a1', 'Despachos');
    final drafted = provider.draftedFooterNavigation(saved);
    expect(drafted.map((s) => s.id), ['b', 'a']);
    expect(drafted.last.children.map((l) => l.id), ['a2', 'a1']);
    expect(drafted.last.children.last.label, 'Despachos');

    // The footer orders before projecting: the projection is unmodifiable,
    // and sorting it threw as soon as a section was moved (since 8e01c879).
    final projected = PublicPagePublication.resolve(
      pages: const [],
      isAuthoritative: false,
    ).forAllAudiences(drafted);
    expect(projected.map((s) => s.id), ['b', 'a']);
    expect(
      () => projected.sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
      throwsUnsupportedError,
    );
  });
}
