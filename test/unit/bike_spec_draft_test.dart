import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/wheel_canonical_data.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_spec_draft.dart';

Bike _bike({
  String? wheelSize = "29''",
  BikeType? type = BikeType.mountainHardtail,
  double? frontHub = 100,
  double? rearHub = 135,
  int? spokeCount = 32,
}) =>
    Bike(
      id: 'bike-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      brand: 'Trek',
      model: 'Marlin 5',
      bikeType: type,
      wheelSize: wheelSize,
      frontHubSpacingMm: frontHub,
      rearHubSpacingMm: rearHub,
      spokeCount: spokeCount,
      imageUrls: const ['https://example.test/a.jpg'],
      notes: 'Llega los martes',
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2026, 9, 30, 12),
    );

BikeProfile _profile(Map<String, dynamic> values,
        {Map<String, dynamic> sources = const {},
        Map<String, dynamic> confirmed = const {}}) =>
    BikeProfile(
      id: 'profile-1',
      tenantId: 'tenant-1',
      bikeId: 'bike-1',
      catalogBikeId: 'catalog-9',
      intakeProfile: const {'primaryUse': 'trail'},
      technicalProfile: {
        'values': values,
        'sources': sources,
        'confirmed': confirmed,
        'catalogNote': 'se queda',
      },
      summarySnapshot: const {'identityLine': 'Trek Marlin 5'},
      lastConfirmedAt: DateTime.utc(2026, 8, 1),
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2026, 9, 30, 12, 5),
    );

final _now = DateTime.utc(2026, 10, 2, 15);

void main() {
  test('opening and saving without changes keeps what the bike had', () {
    final draft = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile({
        'brakeType': 'rim',
        'rimBrakeFamily': 'v_brake',
        'drivetrainConfig': '3x8',
        'drivetrainSpeeds': 24,
        'someFutureKey': 'intacto',
      }),
    );

    // El aro se lee como lo dice la ficha, pero nadie lo cambió.
    expect(draft.value('wheelSize'), '29"');
    expect(draft.value('chainrings'), '3');
    expect(draft.value('rearCogs'), '8');
    expect(draft.hasChanges, isFalse);

    final saved = draft.build(confirmedAt: _now);
    expect(saved.bike.wheelSize, "29''");
    expect(saved.bike.notes, 'Llega los martes');
    expect(saved.bike.imageUrls, ['https://example.test/a.jpg']);
    final values = saved.profile!.technicalValues;
    expect(values['drivetrainConfig'], '3x8');
    expect(values['drivetrainSpeeds'], 24);
    expect(values['rimBrakeFamily'], 'v_brake');
    expect(values['someFutureKey'], 'intacto');
    expect(saved.profile!.technicalSources, isEmpty);
    expect(saved.profile!.technicalProfile['catalogNote'], 'se queda');
    expect(saved.profile!.intakeProfile, {'primaryUse': 'trail'});
    expect(saved.profile!.catalogBikeId, 'catalog-9');
    expect(saved.profile!.lastConfirmedAt, _now);
  });

  test('what the mechanic picks is confirmed; «Desconocido» never is', () {
    final draft = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile({'valveType': 'presta'}),
    )
      ..set('valveType', 'unknown')
      ..set('frontAxleInterface', kRegistryUnknownCode)
      ..set('freehubType', 'shimano_hg');

    expect(draft.changeCount, 3);
    final profile = draft.build(confirmedAt: _now).profile!;
    expect(profile.technicalSources['valveType'], 'mechanic');
    expect(profile.technicalConfirmed.containsKey('valveType'), isFalse);
    expect(
        profile.technicalConfirmed.containsKey('frontAxleInterface'), isFalse);
    expect(profile.technicalSources['freehubType'], 'mechanic');
    expect(profile.technicalConfirmed['freehubType'], isTrue);
  });

  test('changing the brake drops what the new brake does not have', () {
    final draft = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile(
        {'brakeType': 'rim', 'rimBrakeFamily': 'v_brake'},
        sources: {'rimBrakeFamily': 'catalog'},
        confirmed: {'rimBrakeFamily': false},
      ),
    );
    expect(draft.isVisible('frontRotorSizeMm'), isFalse);

    draft.set('brakeType', 'hydraulic_disc');
    expect(draft.isVisible('rimBrakeFamily'), isFalse);
    expect(draft.isVisible('frontRotorSizeMm'), isTrue);
    expect(draft.isVisible('frontBrakeFluidType'), isTrue);
    expect(draft.isVisible('frontRotorMount'), isTrue);
    draft
      ..set('frontRotorSizeMm', '180')
      ..set('frontBrakeFluidType', 'aceite_mineral');

    final profile = draft.build(confirmedAt: _now).profile!;
    final values = profile.technicalValues;
    expect(values.containsKey('rimBrakeFamily'), isFalse);
    expect(profile.technicalSources.containsKey('rimBrakeFamily'), isFalse);
    expect(values['brakeType'], 'hydraulic_disc');
    expect(values['frontRotorSizeMm'], 180);
    expect(values['frontBrakeFluidType'], 'aceite_mineral');
    expect(profile.technicalConfirmed['brakeType'], isTrue);

    // De vuelta a llanta, los rotores tampoco quedan.
    draft.set('brakeType', 'rim');
    expect(draft.value('frontRotorSizeMm'), isNull);
  });

  test('the bike type limits the suspension, as in the bike form', () {
    final hardtail = BikeSpecDraft.fromRecord(
      bike: _bike(type: BikeType.mountain),
      profile: _profile({'suspensionLayout': 'full_suspension'}),
    )..set('bikeType', 'mountain_hardtail');
    expect(hardtail.value('suspensionLayout'), isNull);
    expect(hardtail.options('suspensionLayout').map((o) => o.value),
        ['rigid', 'front_suspension']);

    final bmx = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile({'suspensionLayout': 'front_suspension'}),
    )..set('bikeType', 'bmx');
    expect(bmx.value('suspensionLayout'), 'rigid');
    final saved = bmx.build(confirmedAt: _now);
    expect(saved.bike.bikeType, BikeType.bmx);
    // La regla del tipo sugiere; no es el mecánico confirmando.
    expect(saved.profile!.technicalSources['suspensionLayout'], 'bike_type');
    expect(saved.profile!.technicalConfirmed['suspensionLayout'], isFalse);
    expect(saved.profile!.technicalSources['bikeType'], 'mechanic');
  });

  test('chainrings and cogs are saved together as the whole drivetrain', () {
    final draft = BikeSpecDraft.fromRecord(bike: _bike(), profile: null)
      ..set('chainrings', '2');
    expect(draft.blockingMessage, isNotNull);

    draft.set('rearCogs', '10');
    expect(draft.blockingMessage, isNull);
    expect(draft.drivetrainSummary, '2×10 · 20 velocidades');
    final profile = draft.build(confirmedAt: _now).profile!;
    expect(profile.id, isNull);
    expect(profile.technicalValues['drivetrainConfig'], '2x10');
    expect(profile.technicalValues['drivetrainSpeeds'], 20);
    expect(profile.technicalSources['drivetrainConfig'], 'mechanic');
    expect(profile.technicalConfirmed['drivetrainSpeeds'], isTrue);

    final single = BikeSpecDraft.fromRecord(bike: _bike(), profile: null)
      ..set('chainrings', '1')
      ..set('rearCogs', '1');
    expect(
      single.build(confirmedAt: _now).profile!.technicalValues,
      containsPair('drivetrainConfig', 'singlespeed'),
    );
  });

  test('a drivetrain written another way survives until replaced', () {
    final draft = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile({'drivetrainConfig': 'interna 3v'}),
    );
    expect(draft.value('chainrings'), isNull);
    expect(draft.drivetrainSummary, 'Anotado «interna 3v»');
    draft.set('valveType', 'presta');
    expect(draft.build(confirmedAt: _now).profile!.technicalValues,
        containsPair('drivetrainConfig', 'interna 3v'));
  });

  test('a new bottom bracket family drops measures it does not have', () {
    final draft = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile({
        'bottomBracketFamily': 'bsa_threaded',
        'bbShellWidthMm': 68.0,
        'spindleInterface': 'hollowtech_24',
      }),
    );
    expect(draft.value('bbShellWidthMm'), '68');
    expect(draft.isVisible('bbShellDiameterMm'), isFalse);

    // Un pressfit no mide 68 de ancho, pero sí lleva un eje Hollowtech.
    draft.set('bottomBracketFamily', 'pressfit');
    expect(draft.value('bbShellWidthMm'), isNull);
    expect(draft.value('spindleInterface'), 'hollowtech_24');
    expect(draft.isVisible('bbShellDiameterMm'), isTrue);

    // Un Mid de BMX sí mide 68, pero su eje es de BMX.
    draft
      ..set('bbShellWidthMm', '89.5')
      ..set('bottomBracketFamily', 'mid');
    expect(draft.value('bbShellWidthMm'), isNull);
    expect(draft.value('spindleInterface'), isNull);

    final values = draft.build(confirmedAt: _now).profile!.technicalValues;
    expect(values['bottomBracketFamily'], 'mid');
    expect(values.containsKey('bbShellWidthMm'), isFalse);
    expect(values.containsKey('spindleInterface'), isFalse);
  });

  test('base facts go to the bike row with their origin in the sheet', () {
    final draft = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile({}, sources: {'wheelSize': 'catalog'}),
    )
      ..set('frontHubSpacingMm', '110')
      ..set('wheelSize', null)
      ..set('frameSize', 'M');
    final saved = draft.build(confirmedAt: _now);
    expect(saved.bike.frontHubSpacingMm, 110);
    expect(saved.bike.wheelSize, isNull);
    expect(saved.bike.frameSize, 'M');
    expect(saved.profile!.technicalSources['frontHubSpacingMm'], 'mechanic');
    expect(saved.profile!.technicalSources.containsKey('wheelSize'), isFalse);
    expect(saved.profile!.technicalSources.containsKey('frameSize'), isFalse);
  });

  test('spoke holes start from the bike and move its spoke count', () {
    final draft = BikeSpecDraft.fromRecord(bike: _bike(), profile: null);
    expect(draft.value('frontSpokeHoles'), '32');
    draft
      ..set('frontSpokeHoles', '28')
      ..set('rearSpokeHoles', '28');
    final saved = draft.build(confirmedAt: _now);
    expect(saved.bike.spokeCount, 28);
    expect(saved.profile!.technicalValues['frontSpokeHoles'], 28);
  });

  test('a value outside the list stays offered with its own name', () {
    final draft = BikeSpecDraft.fromRecord(
      bike: _bike(wheelSize: '27.5" - 26"'),
      profile: _profile({'rearWheelBsdMm': 559}),
    );
    expect(draft.value('wheelSize'), '27.5" - 26"');
    expect(draft.options('wheelSize').last.label, '27.5" - 26"');
    expect(draft.labelFor('rearWheelBsdMm', '559'), '559 (26″)');
  });

  test('a rejected save is redone on top of the newer bike', () {
    final draft = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile({'valveType': 'presta'}),
    )..set('brakeType', 'mechanical_disc');

    final newer = BikeSpecDraft.fromRecord(
      bike: _bike(),
      profile: _profile({'valveType': 'schrader'}),
    );
    final rebased = draft.rebasedOn(
      bike: newer.bike,
      profile: newer.profile,
    );
    expect(rebased.value('brakeType'), 'mechanical_disc');
    expect(rebased.value('valveType'), 'schrader');
    expect(rebased.changedKeys, {'brakeType'});
  });

  test('the content signature follows the content, not the moment', () {
    final draft = BikeSpecDraft.fromRecord(bike: _bike(), profile: null)
      ..set('valveType', 'presta');
    final a = draft.build(confirmedAt: _now);
    final b = draft.build(confirmedAt: _now.add(const Duration(minutes: 1)));
    expect(
      draft.contentSignature(a.bike, a.profile),
      draft.contentSignature(b.bike, b.profile),
    );
    draft.set('valveType', 'schrader');
    final c = draft.build(confirmedAt: _now);
    expect(
      draft.contentSignature(c.bike, c.profile),
      isNot(draft.contentSignature(a.bike, a.profile)),
    );
  });
}
