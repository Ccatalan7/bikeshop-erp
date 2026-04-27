import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';

void main() {
  test('diagnosis sheet round-trips structured wheel sections', () {
    const sheet = MechanicJobDiagnosisSheet(
      frontWheel: WheelDiagnosisSheet(
        overallStatus: BikeSystemOverallStatus.attention,
        rimCondition: 'bent',
        spokeCondition: 'loose',
      ),
      rearWheel: WheelDiagnosisSheet(
        overallStatus: BikeSystemOverallStatus.critical,
        tireCondition: 'replace',
        tubelessStatus: 'leaking',
        notes: 'Pierde aire durante la prueba.',
      ),
      bottomBracket: BottomBracketDiagnosisSheet(
        overallStatus: BikeSystemOverallStatus.attention,
        bearingCondition: 'rough',
        noiseStatus: 'creaking',
        notes: 'Ruido al pedalear en carga.',
      ),
      suspension: SuspensionDiagnosisSheet(
        overallStatus: BikeSystemOverallStatus.attention,
        forkCondition: 'seal_leak',
        forkNoiseStatus: 'creaking',
        rearShockCondition: 'service',
        notes: 'Se ve aceite en el sello.',
      ),
      cockpit: CockpitDiagnosisSheet(
        overallStatus: BikeSystemOverallStatus.attention,
        headsetBearingCondition: 'play',
        headsetNoiseStatus: 'clicking',
        notes: 'Golpe al frenar o en baches.',
      ),
    );

    final json = sheet.toJson();

    expect(json['front_wheel']['overall_status'], 'attention');
    expect(json['front_wheel']['rim_condition'], 'bent');
    expect(json['front_wheel']['spoke_condition'], 'loose');
    expect(json['rear_wheel']['overall_status'], 'critical');
    expect(json['rear_wheel']['tire_condition'], 'replace');
    expect(json['rear_wheel']['tubeless_status'], 'leaking');
    expect(json['bottom_bracket']['overall_status'], 'attention');
    expect(json['bottom_bracket']['bearing_condition'], 'rough');
    expect(json['bottom_bracket']['noise_status'], 'creaking');
    expect(json['suspension']['overall_status'], 'attention');
    expect(json['suspension']['fork_condition'], 'seal_leak');
    expect(json['suspension']['fork_noise_status'], 'creaking');
    expect(json['suspension']['rear_shock_condition'], 'service');
    expect(json['cockpit']['overall_status'], 'attention');
    expect(json['cockpit']['headset_bearing_condition'], 'play');
    expect(json['cockpit']['headset_noise_status'], 'clicking');

    final restored = MechanicJobDiagnosisSheet.fromJson(
      Map<String, dynamic>.from(json),
    );

    expect(restored.hasMeaningfulData, isTrue);
    expect(restored.frontWheel.hasMeaningfulData, isTrue);
    expect(
      restored.frontWheel.overallStatus,
      BikeSystemOverallStatus.attention,
    );
    expect(restored.frontWheel.rimCondition, 'bent');
    expect(restored.frontWheel.spokeCondition, 'loose');
    expect(restored.rearWheel.hasMeaningfulData, isTrue);
    expect(
      restored.rearWheel.overallStatus,
      BikeSystemOverallStatus.critical,
    );
    expect(restored.rearWheel.tireCondition, 'replace');
    expect(restored.rearWheel.tubelessStatus, 'leaking');
    expect(restored.rearWheel.notes, 'Pierde aire durante la prueba.');
    expect(restored.bottomBracket.hasMeaningfulData, isTrue);
    expect(
      restored.bottomBracket.overallStatus,
      BikeSystemOverallStatus.attention,
    );
    expect(restored.bottomBracket.bearingCondition, 'rough');
    expect(restored.bottomBracket.noiseStatus, 'creaking');
    expect(restored.bottomBracket.notes, 'Ruido al pedalear en carga.');
    expect(restored.suspension.hasMeaningfulData, isTrue);
    expect(restored.suspension.overallStatus, BikeSystemOverallStatus.attention);
    expect(restored.suspension.forkCondition, 'seal_leak');
    expect(restored.suspension.forkNoiseStatus, 'creaking');
    expect(restored.suspension.rearShockCondition, 'service');
    expect(restored.suspension.notes, 'Se ve aceite en el sello.');
    expect(restored.cockpit.hasMeaningfulData, isTrue);
    expect(restored.cockpit.overallStatus, BikeSystemOverallStatus.attention);
    expect(restored.cockpit.headsetBearingCondition, 'play');
    expect(restored.cockpit.headsetNoiseStatus, 'clicking');
    expect(restored.cockpit.notes, 'Golpe al frenar o en baches.');
  });
}
