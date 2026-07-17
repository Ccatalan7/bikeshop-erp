import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class DesktopUpdateInfo {
  final String tag;
  final String releaseName;
  final String assetName;
  final String installerDownloadUrl;

  const DesktopUpdateInfo({
    required this.tag,
    required this.releaseName,
    required this.assetName,
    required this.installerDownloadUrl,
  });
}

class DesktopUpdateService extends ChangeNotifier {
  static const _repo = 'Ccatalan7/bikeshop-erp';
  static const _currentBuildTag = String.fromEnvironment('VINABIKE_BUILD_TAG');

  bool _hasChecked = false;
  bool _dismissed = false;
  bool _isChecking = false;
  bool _isPreparing = false;
  bool _isUpdating = false;
  bool _isUpdateReady = false;
  String? _preparingTag;
  DesktopUpdateInfo? _availableUpdate;
  String? _errorMessage;

  bool get isSupported =>
      !kDebugMode && (Platform.isWindows || Platform.isMacOS);
  bool get isChecking => _isChecking;
  bool get isPreparing => _isPreparing;
  bool get isUpdating => _isUpdating;
  bool get isUpdateReady => _isUpdateReady;
  bool get hasDismissedReadyUpdate =>
      _dismissed && _availableUpdate != null && _isUpdateReady && !_isUpdating;
  DesktopUpdateInfo? get availableUpdate =>
      !_dismissed ? _availableUpdate : null;
  String? get errorMessage => _errorMessage;

  Future<void> checkForUpdate({
    bool force = false,
    bool revealDismissed = true,
  }) async {
    if (!isSupported) return;
    if (_isChecking || (_hasChecked && !force)) return;

    if (force && revealDismissed) {
      _dismissed = false;
      if (Platform.isMacOS) {
        await _clearMacosPreparationFailureForRetry();
      }
    }
    _isChecking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final latest = Platform.isMacOS
          ? await _fetchLatestMacosRelease()
          : await _fetchLatestWindowsRelease();
      final installedTag = Platform.isMacOS
          ? await _readInstalledMacosReleaseTag()
          : await _readInstalledReleaseTag();
      final isCurrentRelease =
          installedTag == latest.tag || _currentBuildTag == latest.tag;

      if (!isCurrentRelease) {
        if (_availableUpdate?.tag != latest.tag) {
          _dismissed = false;
        }
        _availableUpdate = latest;
        _isUpdateReady = Platform.isMacOS
            ? await _readPreparedMacosReleaseTag() == latest.tag
            : await _readPreparedReleaseTag() == latest.tag;
        if (Platform.isMacOS) {
          _errorMessage = await _readMacosUpdateError(latest.tag);
        }
        final hasMacosPreparationError =
            Platform.isMacOS && _errorMessage != null;
        if (!_isUpdateReady && !hasMacosPreparationError) {
          _prepareUpdateInBackground(latest);
        }
      } else {
        _availableUpdate = null;
        _isUpdateReady = false;
      }
      _hasChecked = true;
    } catch (error, stackTrace) {
      _errorMessage = 'No se pudo revisar actualizaciones.';
      debugPrint('Desktop update check failed: $error\n$stackTrace');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<void> startUpdate() async {
    if (!isSupported) return;

    if (Platform.isMacOS) {
      await _startMacosUpdate();
      return;
    }

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final installRoot = _installRoot;
      if (installRoot == null) {
        throw StateError('LOCALAPPDATA is not available.');
      }

      final update = _availableUpdate ?? await _fetchLatestWindowsRelease();
      final installer = File('$installRoot\\Install-VinabikeERP.ps1');
      final applyScript = File('$installRoot\\Apply-VinabikeERPUpdate.ps1');
      final launcherScript = File('$installRoot\\Start-VinabikeERPUpdate.vbs');
      final bootstrapLog = File('$installRoot\\updater-bootstrap.log');

      await installer.parent.create(recursive: true);
      await _appendBootstrapLog(
        bootstrapLog,
        'Preparing update handoff for ${update.tag}.',
      );
      await _downloadInstaller(
        installer,
        downloadUrl: update.installerDownloadUrl,
      );
      await applyScript.writeAsString(
        _buildApplyScript(
          installerPath: installer.path,
          appPath: '$installRoot\\app\\vinabike_erp.exe',
          applyPrepared: true,
          logPath: bootstrapLog.path,
          waitForProcessId: pid,
        ),
      );
      await launcherScript.writeAsString(
        _buildHiddenLauncherScript(applyScript.path),
      );
      await _appendBootstrapLog(
        bootstrapLog,
        'Starting hidden update launcher at ${launcherScript.path}.',
      );

      await Process.start(
        'wscript.exe',
        [
          '//B',
          '//Nologo',
          launcherScript.path,
        ],
        mode: ProcessStartMode.detached,
        workingDirectory: installRoot,
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

  void revealAvailableUpdate() {
    if (_availableUpdate == null) return;

    _dismissed = false;
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
        installerDownloadUrl:
            _findInstallerDownloadUrl(assets) ?? _fallbackInstallerDownloadUrl,
      );
    }

    throw StateError('No Windows release asset was found.');
  }

  Future<DesktopUpdateInfo> _fetchLatestMacosRelease() async {
    final uri =
        Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=100');
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

      final tag = release['tag_name']?.toString() ?? '';
      if (!tag.startsWith('macos-v')) continue;

      final assets = release['assets'];
      if (assets is! List) continue;

      Map<String, dynamic>? zipAsset;
      Map<String, dynamic>? installerAsset;
      var hasManifest = false;
      var hasManifestSignature = false;
      for (final assetValue in assets) {
        final asset = assetValue as Map<String, dynamic>;
        final name = asset['name']?.toString() ?? '';
        if (RegExp(r'^vinabike_erp_macos_.*\.zip$').hasMatch(name)) {
          zipAsset = asset;
        } else if (name == 'install_vinabike_erp_macos.sh') {
          installerAsset = asset;
        } else if (name == 'macos-release-manifest.json') {
          hasManifest = true;
        } else if (name == 'macos-release-manifest.json.sig') {
          hasManifestSignature = true;
        }
      }

      if (zipAsset == null ||
          installerAsset == null ||
          !hasManifest ||
          !hasManifestSignature) {
        continue;
      }

      return DesktopUpdateInfo(
        tag: tag,
        releaseName: release['name']?.toString() ?? 'macOS release',
        assetName: zipAsset['name']?.toString() ?? '',
        installerDownloadUrl:
            installerAsset['browser_download_url']?.toString() ?? '',
      );
    }

    throw StateError('No verified macOS release asset was found.');
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

  Future<String?> _readPreparedReleaseTag() async {
    final installRoot = _installRoot;
    if (installRoot == null) return null;

    final stateFile = File('$installRoot\\prepared-release.json');
    if (!await stateFile.exists()) return null;

    try {
      final state =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      return state['tag_name']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _macosUpdateCoordinationDirectory() async {
    final userHome = await _macosUserHomeDirectory();
    final directory = Directory(
      path.join(
        userHome,
        'Library',
        'Application Support',
        'VinabikeERP',
        'coordination',
      ),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _macosUserHomeDirectory() async {
    final environmentHome = Platform.environment['HOME']?.trim();
    if (environmentHome != null && environmentHome.isNotEmpty) {
      return _userHomeFromMacosPath(environmentHome);
    }

    final applicationSupport = await getApplicationSupportDirectory();
    return _userHomeFromMacosPath(applicationSupport.path);
  }

  String _userHomeFromMacosPath(String candidate) {
    const containerMarker = '/Library/Containers/';
    final containerIndex = candidate.indexOf(containerMarker);
    if (containerIndex > 0) {
      return candidate.substring(0, containerIndex);
    }

    const applicationSupportMarker = '/Library/Application Support/';
    final applicationSupportIndex = candidate.indexOf(
      applicationSupportMarker,
    );
    if (applicationSupportIndex > 0) {
      return candidate.substring(0, applicationSupportIndex);
    }

    if (path.isAbsolute(candidate)) return candidate;
    throw StateError('Could not resolve the macOS user home directory.');
  }

  Future<String?> _readInstalledMacosReleaseTag() async {
    final directory = await _macosUpdateCoordinationDirectory();
    return _readTagFromJsonFile(
      File(path.join(directory.path, 'current-release.json')),
    );
  }

  Future<String?> _readPreparedMacosReleaseTag() async {
    final directory = await _macosUpdateCoordinationDirectory();
    return _readTagFromJsonFile(
      File(path.join(directory.path, 'prepared-release.json')),
    );
  }

  Future<String?> _readTagFromJsonFile(File file) async {
    if (!await file.exists()) return null;

    try {
      final state =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return state['tag_name']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readMacosUpdateError(String tag) async {
    final directory = await _macosUpdateCoordinationDirectory();
    final errorFile = File(path.join(directory.path, 'update-error.json'));
    if (!await errorFile.exists()) return null;

    try {
      final state =
          jsonDecode(await errorFile.readAsString()) as Map<String, dynamic>;
      final errorTag = state['tag_name']?.toString();
      if (errorTag != tag && errorTag != 'unknown') return null;
      final message = state['message']?.toString().trim() ?? '';
      return message.isEmpty
          ? 'No se pudo preparar la actualización.'
          : message;
    } catch (_) {
      return 'No se pudo preparar la actualización.';
    }
  }

  Future<void> _clearMacosPreparationFailureForRetry() async {
    final directory = await _macosUpdateCoordinationDirectory();
    for (final name in const [
      'update-error.json',
      'prepare-request.json',
    ]) {
      final file = File(path.join(directory.path, name));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _requestMacosPreparation(DesktopUpdateInfo update) async {
    final directory = await _macosUpdateCoordinationDirectory();
    final requestFile = File(path.join(directory.path, 'prepare-request.json'));
    final existingTag = await _readTagFromJsonFile(requestFile);
    if (existingTag == update.tag) return;

    await requestFile.writeAsString(
      jsonEncode({
        'tag_name': update.tag,
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> _startMacosUpdate() async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final update = _availableUpdate ?? await _fetchLatestMacosRelease();
      final preparedTag = await _readPreparedMacosReleaseTag();
      if (preparedTag != update.tag) {
        throw StateError('The macOS update is not prepared yet.');
      }

      final directory = await _macosUpdateCoordinationDirectory();
      final requestFile = File(path.join(directory.path, 'apply-request.json'));
      await requestFile.writeAsString(
        jsonEncode({
          'tag_name': update.tag,
          'process_id': pid,
          'requested_at': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );

      // The per-user LaunchAgent watches this request, waits for this process
      // to exit, swaps the verified app bundle, and relaunches it.
      exit(0);
    } catch (error, stackTrace) {
      _isUpdating = false;
      _errorMessage = 'No se pudo iniciar la actualización.';
      debugPrint('macOS update start failed: $error\n$stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _downloadInstaller(
    File installer, {
    required String downloadUrl,
  }) async {
    final uri = Uri.parse(downloadUrl);
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

  void _prepareUpdateInBackground(DesktopUpdateInfo update) {
    if (_isPreparing || _preparingTag == update.tag) return;

    _isPreparing = true;
    _preparingTag = update.tag;
    notifyListeners();

    Future<void>(() async {
      try {
        if (Platform.isMacOS) {
          await _requestMacosPreparation(update);
        } else {
          await _prepareUpdate(update);
        }
        if (_availableUpdate?.tag == update.tag) {
          if (Platform.isMacOS) {
            _isUpdateReady = await _readPreparedMacosReleaseTag() == update.tag;
          } else {
            _isUpdateReady = true;
          }
          if (_isUpdateReady) {
            _errorMessage = null;
          }
        }
      } catch (error, stackTrace) {
        if (_availableUpdate?.tag == update.tag) {
          _errorMessage = 'No se pudo preparar la actualización.';
        }
        debugPrint('Desktop update prepare failed: $error\n$stackTrace');
      } finally {
        if (_preparingTag == update.tag) {
          _isPreparing = false;
          _preparingTag = null;
        }
        notifyListeners();
      }
    });
  }

  Future<void> _prepareUpdate(DesktopUpdateInfo update) async {
    final installRoot = _installRoot;
    if (installRoot == null) {
      throw StateError('LOCALAPPDATA is not available.');
    }

    final installer = File('$installRoot\\Install-VinabikeERP.ps1');
    await installer.parent.create(recursive: true);
    await _downloadInstaller(installer,
        downloadUrl: update.installerDownloadUrl);

    final process = await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        installer.path,
        '-Prepare',
        '-Quiet',
      ],
      workingDirectory: installRoot,
    );

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw StateError('Installer prepare failed with exit code $exitCode.');
    }
  }

  String? _findInstallerDownloadUrl(List<dynamic> assets) {
    for (final assetValue in assets) {
      final asset = assetValue as Map<String, dynamic>;
      if (asset['name']?.toString() == 'install_vinabike_erp.ps1') {
        return asset['browser_download_url']?.toString();
      }
    }

    return null;
  }

  String get _fallbackInstallerDownloadUrl =>
      'https://raw.githubusercontent.com/$_repo/main/scripts/install_vinabike_erp.ps1';

  String _buildApplyScript({
    required String installerPath,
    required String appPath,
    required bool applyPrepared,
    required String logPath,
    required int waitForProcessId,
  }) {
    final installer = _escapePowerShellSingleQuoted(installerPath);
    final app = _escapePowerShellSingleQuoted(appPath);
    final updateMode = applyPrepared ? '-ApplyPrepared' : '-Force';
    final log = _escapePowerShellSingleQuoted(logPath);

    return '''
\$ErrorActionPreference = 'Continue'
\$installer = '$installer'
\$app = '$app'
\$log = '$log'

function Write-VinabikeUpdateLog {
  param([string]\$Message)
  try {
    \$timestamp = Get-Date -Format o
    Add-Content -LiteralPath \$log -Value "[\$timestamp] \$Message"
  } catch {}
}

Write-VinabikeUpdateLog 'Hidden update handoff started.'
Start-Sleep -Seconds 1
\$exitCode = 0

try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \$installer $updateMode -Launch -WaitForProcessId $waitForProcessId *>> \$log
  if (\$null -ne \$LASTEXITCODE) {
    \$exitCode = \$LASTEXITCODE
  } elseif (-not \$?) {
    \$exitCode = 1
  }
} catch {
  Write-VinabikeUpdateLog "Installer failed: \$(\$_.Exception.Message)"
  \$exitCode = 1
}

Write-VinabikeUpdateLog "Installer exited with \$exitCode."
if (\$exitCode -ne 0 -and (Test-Path -LiteralPath \$app)) {
  Write-VinabikeUpdateLog 'Reopening existing app after failed update.'
  Start-Process -FilePath \$app -WorkingDirectory (Split-Path -Parent \$app)
}

exit \$exitCode
''';
  }

  String _buildHiddenLauncherScript(String scriptPath) {
    final escapedScript = scriptPath.replaceAll('"', '""');
    return '''
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$escapedScript""", 0, False
''';
  }

  String _escapePowerShellSingleQuoted(String value) =>
      value.replaceAll("'", "''");

  Future<void> _appendBootstrapLog(File logFile, String message) async {
    await logFile.parent.create(recursive: true);
    final timestamp = DateTime.now().toIso8601String();
    await logFile.writeAsString(
      '[$timestamp] $message${Platform.lineTerminator}',
      mode: FileMode.append,
    );
  }
}
