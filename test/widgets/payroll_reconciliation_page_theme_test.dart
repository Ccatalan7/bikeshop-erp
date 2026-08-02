import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/pages/payroll_reconciliation_page.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_reconciliation_surface.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('reconciliation page follows the mounted app theme', () {
    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        testWidgets('${preset.code}/${brightness.name}', (tester) async {
          final theme = AppTheme.resolve(
            preset: preset,
            brightness: brightness,
          );

          await _pumpPage(
            tester,
            theme: theme,
            size: const Size(1000, 700),
          );

          _expectPageUsesTheme(tester, theme);
        });
      }
    }

    for (final brightness in Brightness.values) {
      testWidgets('pacific/${brightness.name} remains themed on phone',
          (tester) async {
        final theme = AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: brightness,
        );

        await _pumpPage(
          tester,
          theme: theme,
          size: const Size(390, 844),
        );

        _expectPageUsesTheme(tester, theme);
        expect(
          find.byKey(const ValueKey('reconciliation-workflow-header')),
          findsNothing,
        );
      });
    }
  });

  test('page source has no feature-owned visual palette or theme island', () {
    final source = File(
      'lib/modules/hr/pages/payroll_reconciliation_page.dart',
    ).readAsStringSync();
    final staticVisualToken = RegExp(
      r'PayrollTokens\.(?:'
      r'canvas|surface(?:Sunken|Selected)?|border(?:Strong)?|'
      r'ink(?:Muted|Faint|Disabled)?|accent(?:Soft|Border)?|'
      r'success(?:Fg|Soft|Border)|warning(?:Fg|Soft|Border)|'
      r'danger(?:Fg|Soft|Border)|neutral(?:Fg|Soft|Border)|'
      r'moduleTitle|recordTitle|sectionTitle|cardTitle|bodyM|bodyS|'
      r'label|labelStrong|overline|monoS|monoM|numRow|numCard|numBar|'
      r'raised|moneyBar|overlay|selectedRing)\b',
    );

    expect(staticVisualToken.hasMatch(source), isFalse);
    expect(RegExp(r'\bPayrollTokensDark\b').hasMatch(source), isFalse);
    expect(RegExp(r'\bColors\.').hasMatch(source), isFalse);
    expect(RegExp(r'\bColor\s*\(').hasMatch(source), isFalse);
    expect(RegExp(r'\bTheme\s*\(').hasMatch(source), isFalse);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required ThemeData theme,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: PayrollReconciliationPage(
          actions: _unusedActions,
          pickFile: _emptyPicker,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectPageUsesTheme(WidgetTester tester, ThemeData theme) {
  final surface = find.byType(PayrollReconciliationSurface);
  final canvas = tester.widget<ColoredBox>(
    find.descendant(of: surface, matching: find.byType(ColoredBox)).first,
  );
  final card = tester.widget<Container>(
    find.byKey(const ValueKey('payroll-reconciliation-file-card')),
  );
  final decoration = card.decoration! as BoxDecoration;
  final border = decoration.border! as Border;
  final title = tester.widget<Text>(find.text('Carga la cartola'));
  final scanner = tester.widget<Icon>(
    find.descendant(
      of: find.byKey(
        const ValueKey('payroll-reconciliation-file-card'),
      ),
      matching: find.byIcon(Icons.document_scanner_outlined),
    ),
  );

  expect(canvas.color, theme.scaffoldBackgroundColor);
  expect(decoration.color, theme.colorScheme.surface);
  expect(border.top.color, theme.colorScheme.outline);
  expect(title.style?.color, theme.colorScheme.onSurface);
  expect(scanner.color, theme.colorScheme.primary);
  expect(tester.takeException(), isNull);

  if (theme.brightness == Brightness.dark) {
    expect(decoration.color, isNot(Colors.white));
    expect(canvas.color, isNot(Colors.black));
  }
}

Future<PayrollPickedStatement?> _emptyPicker() async => null;

final PayrollReconciliationActions _unusedActions =
    PayrollReconciliationActions(
  prepare: ({required bytes, required filename, sourcePath}) async {
    throw UnimplementedError();
  },
  createImport: (_, {required erpAccountId}) async {
    throw UnimplementedError();
  },
  apply: ({
    required draft,
    required importReceipt,
    required decisions,
    required authorizedDraftVoucherIds,
    operationKey,
  }) async {
    throw UnimplementedError();
  },
);
