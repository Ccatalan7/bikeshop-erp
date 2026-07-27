import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);

  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');
  expect(end, greaterThan(start), reason: 'Missing $endMarker');
  return source.substring(start, end);
}

void main() {
  test('workshop products editor has a touch-first mobile contract', () {
    final source = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();

    final responsiveEntry = _section(
      source,
      'Widget _buildPartsSection()',
      'Widget _buildMobilePartsSection',
    );
    expect(
      responsiveEntry,
      contains('MechanicJobResponsivePolicy.usesCompactComposition('),
    );
    expect(
      responsiveEntry,
      contains('ResponsiveViewport.widthOf(context)'),
    );
    expect(responsiveEntry, contains('return _buildMobilePartsSection(theme)'));
    expect(
      responsiveEntry.indexOf(
        'MechanicJobResponsivePolicy.usesCompactComposition(',
      ),
      lessThan(responsiveEntry.indexOf('SingleChildScrollView')),
      reason: 'Phone and tablet must bypass the horizontally scrolling desktop '
          'table using the root viewport class.',
    );
    expect(responsiveEntry, isNot(contains('constraints.maxWidth < 600')));

    final mobileEditor = _section(
      source,
      'Widget _buildMobilePartsSection',
      'Widget _buildPartAutocompleteField',
    );
    expect(mobileEditor, contains('mobile_products_services_editor'));
    expect(mobileEditor, contains('mobileLayout: true'));
    expect(mobileEditor, contains('_buildMobileServiceRow('));
    expect(mobileEditor, contains('_buildPartAutocompleteField()'));
    expect(
      mobileEditor,
      isNot(contains('SingleChildScrollView')),
      reason: 'Mobile lines must not depend on a horizontally scrolling table.',
    );

    final adaptiveLine = _section(
      source,
      'class _PartItemRowState',
      'class _JobPartItem',
    );
    expect(adaptiveLine, contains('_buildDesktopRow(theme, item)'));
    expect(adaptiveLine, contains('_buildMobileCard(theme, item)'));
    expect(
      RegExp(r'_buildProductEditor\(item, mobileLayout: (?:true|false)\)')
          .allMatches(adaptiveLine),
      hasLength(2),
      reason:
          'Desktop and mobile must share the same product/configuration editor.',
    );
    expect(adaptiveLine, contains('_handleProductChanged(item, selection)'));
    expect(
      adaptiveLine,
      contains('minimumSize: const Size(0, 48)'),
      reason: 'Mobile line actions must keep a 48 px touch target.',
    );
    final locationSelector = _section(
      source,
      'class _ServiceLocationDropdown',
      'class _JobServiceItem',
    );
    expect(locationSelector, contains('height: 48'));

    final narrowForm = _section(
      source,
      'final customerSection = KeyedSubtree(',
      "title: 'Adjuntos'",
    );
    expect(
      narrowForm,
      contains('widget.isInlineWorkspace && widget.jobId != null'),
    );
    expect(narrowForm, contains('if (prioritizesRequestedWorkbench)'));
    expect(
      narrowForm,
      contains('const EdgeInsets.fromLTRB(8, 12, 8, 16)'),
      reason:
          'The inline workspace must not stack a desktop page gutter around '
          'already padded section content.',
    );
    expect(
      narrowForm.indexOf('workbenchSection,'),
      lessThan(narrowForm.indexOf('customerSection,', 1)),
      reason:
          'An existing inline job must land on its workbench before context.',
    );

    final commercialNotice = _section(
      source,
      'Widget _buildCommercialLockBanner',
      'Widget _buildSectionCard',
    );
    expect(commercialNotice, contains('widget.isInlineWorkspace'));
    expect(
      commercialNotice,
      contains("ValueKey('commercial-history-inline-disclosure')"),
    );
    expect(commercialNotice, contains('minTileHeight: 52'));
    expect(
      commercialNotice,
      contains('if (!widget.isInlineWorkspace)'),
      reason:
          'The inline header already owns return navigation; its notice must '
          'not repeat the desktop table action.',
    );

    final compactSectionCards = _section(
      source,
      'Widget _buildSectionCard',
      'Widget _buildInlineBikeTabs',
    );
    expect(
      RegExp(r'margin: isCompactInline \? EdgeInsets\.zero : null')
          .allMatches(compactSectionCards),
      hasLength(2),
    );
    expect(compactSectionCards, contains('isCompactInline ? 12 : 20'));

    for (final stableKey in [
      'mobile_part_card_',
      'mobile_part_configure_',
      'mobile_part_quantity_',
      'mobile_part_price_',
      'mobile_part_total_',
      'mobile_part_move_up_',
      'mobile_part_move_down_',
      'mobile_part_delete_',
    ]) {
      expect(adaptiveLine, contains(stableKey));
    }

    final legacyService = _section(
      source,
      'Widget _buildMobileServiceRow',
      'Widget _buildServiceRow',
    );
    for (final stableKey in [
      'mobile_service_card_',
      'mobile_service_description_',
      'mobile_service_quantity_',
      'mobile_service_price_',
      'mobile_service_total_',
      'mobile_service_move_up_',
      'mobile_service_move_down_',
      'mobile_service_delete_',
    ]) {
      expect(legacyService, contains(stableKey));
    }
  });
}
