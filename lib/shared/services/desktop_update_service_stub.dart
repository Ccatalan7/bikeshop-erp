import 'package:flutter/foundation.dart';

class DesktopUpdateInfo {
  final String tag;
  final String releaseName;
  final String assetName;

  const DesktopUpdateInfo({
    required this.tag,
    required this.releaseName,
    required this.assetName,
  });
}

class DesktopUpdateService extends ChangeNotifier {
  bool get isSupported => false;
  bool get isChecking => false;
  bool get isUpdating => false;
  DesktopUpdateInfo? get availableUpdate => null;
  String? get errorMessage => null;

  Future<void> checkForUpdate({bool force = false}) async {}

  Future<void> startUpdate() async {}

  void dismissAvailableUpdate() {}
}
