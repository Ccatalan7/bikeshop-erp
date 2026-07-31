import 'package:flutter/material.dart';

import '../payroll/payroll_redesign_page.dart';

/// Compatibility entry point for older embedded callers.
///
/// Payroll has one canonical surface. Keeping this tiny adapter lets existing
/// references migrate without preserving the former expansion-list workflow.
@Deprecated('Use PayrollRedesignPage directly.')
class PayrollListPage extends StatelessWidget {
  const PayrollListPage({super.key});

  @override
  Widget build(BuildContext context) => const PayrollRedesignPage();
}
