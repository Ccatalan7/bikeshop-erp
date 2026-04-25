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
    );

    final json = sheet.toJson();

    expect(json['front_wheel']['overall_status'], 'attention');
    expect(json['front_wheel']['rim_condition'], 'bent');
    expect(json['front_wheel']['spoke_condition'], 'loose');
    expect(json['rear_wheel']['overall_status'], 'critical');
    expect(json['rear_wheel']['tire_condition'], 'replace');
    expect(json['rear_wheel']['tubeless_status'], 'leaking');

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
  });
}
