// Diagnostic only: does not initialize Flutter/Supabase or write product data.
import 'dart:convert';
import '../../../lib/modules/bikeshop/config/drivetrain_canonical_data.dart';

void main() {
  final values = <String, dynamic>{
    'chain_speeds': ['6', '7', '8'],
    'drivetrain_primary_ecosystem': 'Ecosistema Shimano',
    'drivetrain_declared_compatible_ecosystems': ['Ecosistema SRAM'],
    'chain_profile_family': ['Campagnolo'],
    'chain_width_family': '11/128',
    'chain_outer_width_mm': 7.1,
  };
  for (final key in values.keys) {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: key,
      currentValues: values,
    );
    print(jsonEncode({
      'field': key,
      'allowed': behavior.allowedOptions,
      'enabled': behavior.enabled,
      'hidden': behavior.hidden,
    }));
  }
}
