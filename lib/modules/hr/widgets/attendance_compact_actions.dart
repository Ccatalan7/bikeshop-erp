import 'package:flutter/material.dart';

import '../../../shared/widgets/app_button.dart';

class AttendanceCompactActions extends StatelessWidget {
  const AttendanceCompactActions({
    super.key,
    required this.canAccessPayroll,
    required this.onOpenPayroll,
    required this.onGeneratePayroll,
    required this.onCreateAttendance,
  });

  final bool canAccessPayroll;
  final VoidCallback onOpenPayroll;
  final VoidCallback onGeneratePayroll;
  final VoidCallback onCreateAttendance;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackPayrollActions = constraints.maxWidth < 640;
        final payrollActions = stackPayrollActions
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _openPayrollButton(),
                  const SizedBox(height: 8),
                  _generatePayrollButton(),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _openPayrollButton()),
                  const SizedBox(width: 8),
                  Expanded(child: _generatePayrollButton()),
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canAccessPayroll) ...[
              payrollActions,
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: AppButton(
                text: 'Nuevo',
                onPressed: onCreateAttendance,
                icon: Icons.add,
                type: ButtonType.primary,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _openPayrollButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.history_edu),
      label: const Text('Nóminas'),
      onPressed: onOpenPayroll,
    );
  }

  Widget _generatePayrollButton() {
    return AppButton(
      text: 'Preparar nómina',
      onPressed: onGeneratePayroll,
      icon: Icons.payments,
      type: ButtonType.secondary,
    );
  }
}
