import 'package:flutter/foundation.dart';

import '../models/android_release_manifest.dart';

class AndroidUpdateService extends ChangeNotifier {
  bool get isSupported => false;
  bool get isChecking => false;
  bool get isDownloading => false;
  double? get downloadProgress => null;
  AndroidReleaseManifest? get availableUpdate => null;
  String? get errorMessage => null;
  String? get statusMessage => null;

  Future<void> checkForUpdate({bool force = false}) async {}

  Future<void> installAvailableUpdate() async {}

  void dismissAvailableUpdate() {}
}
