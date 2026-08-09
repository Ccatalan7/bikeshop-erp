import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS host publishes adaptive margins from every layout pass', () {
    final source = File(
      'ios/Runner/WindowChromeLayoutViewController.swift',
    ).readAsStringSync();
    final storyboard = File(
      'ios/Runner/Base.lproj/Main.storyboard',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(source, contains('#available(iOS 26.0, *)'));
    expect(
      source,
      contains('.margins(cornerAdaptation: .horizontal)'),
    );
    expect(source, contains('override func viewDidLayoutSubviews()'));
    expect(source, isNot(contains('view.safeAreaInsets')));
    expect(
      storyboard,
      contains('customClass="WindowChromeLayoutViewController"'),
    );
    expect(
      project,
      contains('WindowChromeLayoutViewController.swift in Sources'),
    );
  });
}
