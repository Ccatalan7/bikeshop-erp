import 'package:flutter/foundation.dart';

import '../models/desktop_release_notes.dart';

class DesktopUpdateInfo {
  final String tag;
  final String releaseName;
  final String assetName;
  final String installerDownloadUrl;
  final String commit;
  final DesktopReleaseNotes? releaseNotes;

  const DesktopUpdateInfo({
    required this.tag,
    required this.releaseName,
    required this.assetName,
    required this.installerDownloadUrl,
    required this.commit,
    this.releaseNotes,
  });

  DesktopUpdateInfo copyWithReleaseNotes(DesktopReleaseNotes? notes) {
    return DesktopUpdateInfo(
      tag: tag,
      releaseName: releaseName,
      assetName: assetName,
      installerDownloadUrl: installerDownloadUrl,
      commit: commit,
      releaseNotes: notes,
    );
  }
}

class DesktopUpdateService extends ChangeNotifier {
  bool get isSupported => false;
  bool get isChecking => false;
  bool get isPreparing => false;
  bool get isUpdating => false;
  bool get isUpdateReady => false;
  bool get hasDismissedReadyUpdate => false;
  DesktopUpdateInfo? get availableUpdate => null;
  String? get errorMessage => null;

  Future<void> checkForUpdate({
    bool force = false,
    bool revealDismissed = true,
  }) async {}

  Future<void> startUpdate() async {}

  void dismissAvailableUpdate() {}

  void revealAvailableUpdate() {}
}
