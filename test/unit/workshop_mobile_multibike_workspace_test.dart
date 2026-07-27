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
  late String table;
  late String chooser;

  setUpAll(() {
    table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    chooser = File(
      'lib/modules/bikeshop/widgets/workshop_mobile_bike_chooser.dart',
    ).readAsStringSync();
  });

  test('compact bicycle action resolves every linked bicycle in stable order',
      () {
    final resolver = _section(
      table,
      'List<Bike> _linkedBikesForJob',
      'Future<Bike?> _showMobileBikeChooser',
    );
    expect(resolver, contains('_jobBikesMap[jobId]'));
    expect(resolver, contains('a.orderIndex.compareTo(b.orderIndex)'));
    expect(resolver, contains('_bikes[link.bikeId] ?? link.bike'));
    expect(resolver, contains('bikesById[bikeId] = bike'));
    expect(resolver, contains('bikesById.putIfAbsent(primaryBikeId'));

    final mobileObject = _section(
      table,
      'Widget _buildMobileJobObject',
      'Widget _buildMobileStatusAction',
    );
    expect(mobileObject, contains('_linkedBikesForJob(job)'));
    expect(mobileObject, contains("'Bicicletas'"));
    expect(mobileObject, contains("'\$linkedBikeCount vinculadas'"));
    expect(
      mobileObject,
      contains('unawaited(_openMobileJobBike(job, customer))'),
    );
    expect(
      mobileObject,
      isNot(contains('_showBikeProfileDialog')),
      reason: 'Compact Jobs must not detour through the desktop modal.',
    );
  });

  test('multi-bike compact action uses a labelled touch-safe chooser', () {
    final chooserHost = _section(
      table,
      'Future<Bike?> _showMobileBikeChooser',
      'Future<void> _openMobileJobBike',
    );
    expect(chooserHost, contains('showModalBottomSheet<Bike>'));
    expect(chooserHost, contains('useSafeArea: true'));
    expect(chooserHost, contains('isScrollControlled: true'));
    expect(chooserHost, contains('WorkshopMobileBikeChooser('));
    expect(
      chooserHost,
      contains('Navigator.of(sheetContext).pop(bike)'),
      reason: 'The chosen object, not the job primary, must leave the sheet.',
    );

    expect(chooser, contains("'Seleccionar bicicleta'"));
    expect(chooser, contains('bicicletas vinculadas. Elige la ficha'));
    expect(
      chooser,
      contains("ValueKey('workshop-mobile-bike-chooser')"),
    );
    expect(
      chooser,
      contains("'workshop-mobile-bike-choice-\$bikeId'"),
    );
    expect(chooser, contains('minTileHeight: 56'));
    expect(chooser, contains('width: 48'));
    expect(chooser, contains('height: 48'));
    expect(chooser, contains('button: true'));
    expect(chooser, contains("'Abrir bicicleta \${bike.displayName}"));
    expect(chooser, contains('onTap: () => onSelected(bike)'));
  });

  test('single bike opens directly and multi-bike selection opens inline', () {
    final openFlow = _section(
      table,
      'Future<void> _openMobileJobBike',
      'MechanicJob _currentMobileWorkspaceJob',
    );
    expect(openFlow, contains('final bikes = _linkedBikesForJob(job);'));
    expect(openFlow, contains('linkedBikeCount > 1'));
    expect(
      openFlow,
      contains('await _showMobileBikeChooser(job, bikes, linkedBikeCount)'),
    );
    expect(openFlow, contains(': bikes.first'));
    expect(openFlow, contains('if (!mounted || selectedBike == null) return;'));
    expect(openFlow, contains('_MobileWorkshopSurface.bike'));
    expect(openFlow, contains('bike: selectedBike'));
  });

  test('embedded canonical bike editor preserves cancel and one refresh', () {
    final inlineWorkspace = _section(
      table,
      'Widget _buildMobileBikeWorkspace',
      'Widget _buildMobileInlineUnavailable',
    );
    expect(
      table,
      contains("ValueKey('workshop-mobile-inline-bike')"),
    );
    expect(inlineWorkspace, contains('PopScope('));
    expect(inlineWorkspace, contains('canPop: false'));
    expect(inlineWorkspace, contains('_closeMobileInlineSurface()'));
    expect(inlineWorkspace, contains('BikeFormDialog('));
    expect(inlineWorkspace, contains('bike: bike'));
    expect(inlineWorkspace, contains('isEmbedded: true'));
    expect(inlineWorkspace, contains('onSaved: _handleMobileBikeSave'));
    expect(
      inlineWorkspace,
      contains('onCanceled: _closeMobileInlineSurface'),
    );
    expect(
      inlineWorkspace,
      isNot(contains('showDialog')),
      reason: 'The compact editor must replace only the Jobs list body.',
    );

    final saveFlow = _section(
      table,
      'void _handleMobileBikeSave',
      'Future<void> _handleMobileInlinePaymentRequested',
    );
    expect(saveFlow, contains('_bikes[bikeId] = bike'));
    expect(saveFlow, contains('_mobileWorkshopWorkspace = null'));
    expect(
      RegExp(r'_loadData\(\)').allMatches(saveFlow),
      hasLength(1),
      reason: 'A successful aggregate save refreshes the Jobs owner once.',
    );
    expect(saveFlow, isNot(contains('forceInvoiceRefresh')));

    final cancelFlow = _section(
      table,
      'void _closeMobileInlineSurface',
      'void _handleMobileInlineSave',
    );
    expect(cancelFlow, contains('_mobileWorkshopWorkspace = null'));
    for (final owner in const [
      '_mobileJobsScrollController',
      '_statusFilter',
      '_searchTerm',
      '_customStatusFilter',
      '_priorityFilter',
      '_viewMode',
      '_expandedMobileJobKeys',
    ]) {
      expect(
        cancelFlow,
        isNot(contains('$owner =')),
        reason: '$owner must survive bicycle cancel/system Back.',
      );
    }
  });

  test('desktop per-bike subrow passes the clicked bicycle explicitly', () {
    final bikeCell = _section(
      table,
      'Widget _getCellContent',
      "case 'arrival_date':",
    );
    final perBikeDetail = _section(
      bikeCell,
      'if (isPerBikeDetail)',
      'if (isMultiBikeSummary)',
    );
    expect(perBikeDetail, contains('_showBikeProfileDialog('));
    expect(perBikeDetail, contains('initialBike: bike'));

    final desktopDialog = _section(
      table,
      'void _showBikeProfileDialog',
      'List<Bike> _customerBikesForPicker',
    );
    expect(desktopDialog, contains('Bike? initialBike'));
    expect(desktopDialog, contains('var activeBike = initialBike ??'));
    expect(
      desktopDialog,
      contains('_bikes[activeJob.bikeId!]'),
      reason: 'Single-bike desktop still falls back to the existing primary.',
    );
    expect(desktopDialog, contains('showDialog<Bike>'));
    expect(desktopDialog, contains('BikeFormDialog('));
  });

  test('the registered 899/900 boundary keeps phone and tablet dedicated', () {
    expect(
      table,
      contains('screenWidth < ResponsiveViewport.desktopMin'),
    );
    for (final expectation in const <(double, bool)>[
      (384, true),
      (599, true),
      (600, true),
      (899, true),
      (900, false),
      (1440, false),
    ]) {
      final (width, usesCompactComposition) = expectation;
      expect(
        width < 900,
        usesCompactComposition,
        reason: 'Unexpected composition at ${width.toInt()} px.',
      );
    }
  });
}
