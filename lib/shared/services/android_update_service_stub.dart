import 'package:flutter/foundation.dart';

import '../models/android_release_manifest.dart';

class AndroidUpdateService extends ChangeNotifier {
  bool get isSupported => false;
  bool get isChecking => false;
  bool get isDownloading => false;
  int get consecutiveCheckFailures => 0;
  double? get downloadProgress => null;
  AndroidReleaseManifest? get availableUpdate => null;
  DateTime? get lastSuccessfulCheckAt => null;
  String? get errorMessage => null;
  String? get statusMessage => null;

  Future<void> checkForUpdate({bool force = false}) async {}

  Future<void> installAvailableUpdate() async {}

  void dismissAvailableUpdate() {}
}
