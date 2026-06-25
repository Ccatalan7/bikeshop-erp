import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  static const _repo = 'Ccatalan7/bikeshop-erp';
  static const _currentBuildTag = String.fromEnvironment('VINABIKE_BUILD_TAG');

  bool _hasChecked = false;
  bool _dismissed = false;
  bool _isChecking = false;
  bool _isUpdating = false;
  DesktopUpdateInfo? _availableUpdate;
  String? _errorMessage;

  bool get isSupported => !kDebugMode && Platform.isWindows;
  bool get isChecking => _isChecking;
  bool get isUpdating => _isUpdating;
  DesktopUpdateInfo? get availableUpdate =>
      _dismissed ? null : _availableUpdate;
  String? get errorMessage => _errorMessage;

  Future<void> checkForUpdate({bool force = false}) async {
    if (!isSupported) return;
    if (_isChecking || (_hasChecked && !force)) return;

    _isChecking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final latest = await _fetchLatestWindowsRelease();
      final currentTag = _currentBuildTag.isNotEmpty
          ? _currentBuildTag
          : await _readInstalledReleaseTag();

      _availableUpdate = currentTag != latest.tag ? latest : null;
      _hasChecked = true;
    } catch (error, stackTrace) {
      _errorMessage = 'No se pudo revisar actualizaciones.';
      debugPrint('Windows update check failed: $error\n$stackTrace');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<void> startUpdate() async {
    if (!isSupported) return;

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final installRoot = _installRoot;
      if (installRoot == null) {
        throw StateError('LOCALAPPDATA is not available.');
      }

      final installer = File('$installRoot\\Install-VinabikeERP.ps1');
      if (!await installer.exists()) {
        await installer.parent.create(recursive: true);
        await _downloadInstaller(installer);
      }

      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          installer.path,
          '-Force',
          '-Launch',
          '-WaitForProcessId',
          pid.toString(),
        ],
        mode: ProcessStartMode.detached,
      );

      exit(0);
    } catch (error, stackTrace) {
      _isUpdating = false;
      _errorMessage = 'No se pudo iniciar la actualización.';
      debugPrint('Windows update start failed: $error\n$stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  void dismissAvailableUpdate() {
    _dismissed = true;
    notifyListeners();
  }

  String? get _installRoot {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      return null;
    }
    return '$localAppData\\VinabikeERP';
  }

  Future<DesktopUpdateInfo> _fetchLatestWindowsRelease() async {
    final uri =
        Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=30');
    final response = await http.get(
      uri,
      headers: const {'User-Agent': 'VinabikeERP-Updater'},
    );

    if (response.statusCode != 200) {
      throw StateError(
        'GitHub releases request failed with ${response.statusCode}.',
      );
    }

    final releases = jsonDecode(response.body) as List<dynamic>;
    for (final releaseValue in releases) {
      final release = releaseValue as Map<String, dynamic>;
      if (release['draft'] == true || release['prerelease'] == true) {
        continue;
      }

      final assets = release['assets'];
      if (assets is! List) continue;

      Map<String, dynamic>? zipAsset;
      for (final assetValue in assets) {
        final asset = assetValue as Map<String, dynamic>;
        final name = asset['name']?.toString() ?? '';
        if (RegExp(r'^vinabike_erp_windows_.*\.zip$').hasMatch(name)) {
          zipAsset = asset;
          break;
        }
      }

      if (zipAsset == null) continue;

      final zipName = zipAsset['name']?.toString() ?? '';
      final hashName = '$zipName.sha256';
      final hasHash = assets.any((assetValue) {
        final asset = assetValue as Map<String, dynamic>;
        return asset['name']?.toString() == hashName;
      });

      if (!hasHash) continue;

      return DesktopUpdateInfo(
        tag: release['tag_name']?.toString() ?? '',
        releaseName: release['name']?.toString() ?? 'Windows release',
        assetName: zipName,
      );
    }

    throw StateError('No Windows release asset was found.');
  }

  Future<String?> _readInstalledReleaseTag() async {
    final installRoot = _installRoot;
    if (installRoot == null) return null;

    final stateFile = File('$installRoot\\current-release.json');
    if (!await stateFile.exists()) return null;

    try {
      final state =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      return state['tag_name']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadInstaller(File installer) async {
    final uri = Uri.parse(
      'https://raw.githubusercontent.com/$_repo/main/scripts/install_vinabike_erp.ps1',
    );
    final response = await http.get(
      uri,
      headers: const {'User-Agent': 'VinabikeERP-Updater'},
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Installer download failed with ${response.statusCode}.',
      );
    }

    await installer.writeAsString(response.body);
  }
}
