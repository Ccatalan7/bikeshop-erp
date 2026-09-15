import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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
  static const _repo = 'Ccatalan7/bikeshop-erp';
  static const _currentBuildTag = String.fromEnvironment('VINABIKE_BUILD_TAG');
  static const _macosLatestManifestUrl =
      'https://github.com/$_repo/releases/download/macos-latest/'
      'macos-release-manifest.json';
  static const _maxReleaseManifestBytes = 128 * 1024;
  static const _windowsReleasePageSize = 100;
  static const _maxWindowsReleasePages = 10;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final String? _macosUserHomeOverride;

  DesktopUpdateService({
    http.Client? httpClient,
    @visibleForTesting String? macosUserHomeOverride,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _macosUserHomeOverride = macosUserHomeOverride;

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

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }

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
      var latest = Platform.isMacOS
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
        _isUpdateReady = Platform.isMacOS
            ? await _readPreparedMacosReleaseTag() == latest.tag
            : await _readPreparedReleaseTag() == latest.tag;
        if (Platform.isMacOS && _isUpdateReady) {
          latest = latest.copyWithReleaseNotes(
            await _readPreparedMacosReleaseNotes(latest),
          );
        }
        _availableUpdate = latest;
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

  Stream<Map<String, dynamic>> _fetchWindowsReleasePages() async* {
    // Other platforms share this feed and can fill several recent pages.
    // Keep the same finite discovery budget as the PowerShell installer.
    for (var page = 1; page <= _maxWindowsReleasePages; page++) {
      final uri = Uri.parse(
        'https://api.github.com/repos/$_repo/releases'
        '?per_page=$_windowsReleasePageSize&page=$page',
      );
      final response = await _httpClient.get(
        uri,
        headers: const {'User-Agent': 'VinabikeERP-Updater'},
      );
      if (response.statusCode != 200) {
        throw StateError(
          'GitHub releases request failed with ${response.statusCode}.',
        );
      }
      final releases = jsonDecode(response.body) as List<dynamic>;
      for (final release in releases) {
        yield release as Map<String, dynamic>;
      }
      if (releases.length < _windowsReleasePageSize) return;
    }
  }

  Future<DesktopUpdateInfo> _fetchLatestWindowsRelease() async {
    await for (final release in _fetchWindowsReleasePages()) {
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
      final hashAsset = _findAsset(assets, hashName);

      if (hashAsset == null) continue;

      final tag = release['tag_name']?.toString() ?? '';
      final releaseCommit = release['target_commitish']?.toString() ?? '';
      final manifestAsset = _findAsset(assets, 'windows-release-manifest.json');
      final installerAsset = _findAsset(assets, 'install_vinabike_erp.ps1');
      if (!RegExp(r'^windows-v.+$').hasMatch(tag) ||
          !RegExp(r'^[a-f0-9]{40}$').hasMatch(releaseCommit) ||
          manifestAsset == null ||
          installerAsset == null) {
        throw const FormatException('Invalid Windows release metadata.');
      }

      final manifestUrl =
          manifestAsset['browser_download_url']?.toString() ?? '';
      final installerUrl =
          installerAsset['browser_download_url']?.toString() ?? '';
      final zipUrl = zipAsset['browser_download_url']?.toString() ?? '';
      final hashUrl = hashAsset['browser_download_url']?.toString() ?? '';
      if (!_isImmutableGithubReleaseAssetUrl(
            zipUrl,
            tag: tag,
            assetName: zipName,
          ) ||
          !_isImmutableGithubReleaseAssetUrl(
            hashUrl,
            tag: tag,
            assetName: hashName,
          ) ||
          !_isImmutableGithubReleaseAssetUrl(
            manifestUrl,
            tag: tag,
            assetName: 'windows-release-manifest.json',
          ) ||
          !_isImmutableGithubReleaseAssetUrl(
            installerUrl,
            tag: tag,
            assetName: 'install_vinabike_erp.ps1',
          )) {
        throw const FormatException('Invalid Windows release asset URL.');
      }

      final manifestResponse = await _httpClient.get(
        Uri.parse(manifestUrl),
        headers: const {'User-Agent': 'VinabikeERP-Updater'},
      );
      if (manifestResponse.statusCode != 200) {
        throw StateError(
          'Windows manifest request failed with '
          '${manifestResponse.statusCode}.',
        );
      }
      if (manifestResponse.bodyBytes.length > _maxReleaseManifestBytes) {
        throw const FormatException('Windows release manifest is too large.');
      }

      final manifestValue = jsonDecode(manifestResponse.body);
      if (manifestValue is! Map<String, dynamic>) {
        throw const FormatException('Invalid Windows release manifest.');
      }
      final manifestTag = manifestValue['tag_name']?.toString() ?? '';
      final manifestCommit = manifestValue['commit']?.toString() ?? '';
      final manifestZipName = manifestValue['zip_name']?.toString() ?? '';
      final manifestZipHash = manifestValue['zip_sha256']?.toString() ?? '';
      final manifestInstallerName =
          manifestValue['installer_name']?.toString() ?? '';
      final manifestInstallerHash =
          manifestValue['installer_sha256']?.toString() ?? '';
      if (manifestTag != tag ||
          manifestCommit != releaseCommit ||
          manifestZipName != zipName ||
          manifestInstallerName != 'install_vinabike_erp.ps1' ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestZipHash) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestInstallerHash)) {
        throw const FormatException('Mismatched Windows release manifest.');
      }

      return DesktopUpdateInfo(
        tag: tag,
        releaseName: release['name']?.toString() ?? 'Windows release',
        assetName: zipName,
        installerDownloadUrl: installerUrl,
        commit: manifestCommit,
        releaseNotes: DesktopReleaseNotes.tryParse(
          manifestValue['release_notes'],
          expectedToCommit: manifestCommit,
        ),
      );
    }

    throw StateError('No Windows release asset was found.');
  }

  Future<DesktopUpdateInfo> _fetchLatestMacosRelease() async {
    final uri = Uri.parse(_macosLatestManifestUrl);
    final response = await _httpClient.get(
      uri,
      headers: const {'User-Agent': 'VinabikeERP-Updater'},
    );

    if (response.statusCode != 200) {
      throw StateError(
        'macOS stable manifest request failed with ${response.statusCode}.',
      );
    }
    if (response.bodyBytes.length > _maxReleaseManifestBytes) {
      throw const FormatException('macOS stable manifest is too large.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid macOS stable manifest.');
    }

    final tag = decoded['tag_name']?.toString() ?? '';
    final archiveName = decoded['archive_name']?.toString() ?? '';
    final archiveUrl = Uri.tryParse(decoded['archive_url']?.toString() ?? '');
    final installerUrl =
        Uri.tryParse(decoded['installer_url']?.toString() ?? '');
    final archiveHash = decoded['archive_sha256']?.toString() ?? '';
    final installerHash = decoded['installer_sha256']?.toString() ?? '';
    final bundleId = decoded['bundle_id']?.toString() ?? '';
    final bundleVersion = decoded['bundle_version']?.toString() ?? '';
    final commit = decoded['commit']?.toString() ?? '';
    final immutableReleasePrefix = '/$_repo/releases/download/$tag/';
    final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

    if (!RegExp(r'^macos-v.+$').hasMatch(tag) ||
        !RegExp(r'^vinabike_erp_macos_.+\.zip$').hasMatch(archiveName) ||
        bundleId != 'com.vinabike.vinabikeErp' ||
        int.tryParse(bundleVersion) == null ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(commit) ||
        !sha256Pattern.hasMatch(archiveHash) ||
        !sha256Pattern.hasMatch(installerHash) ||
        archiveUrl?.scheme != 'https' ||
        archiveUrl?.host != 'github.com' ||
        !archiveUrl!.path.startsWith(immutableReleasePrefix) ||
        installerUrl?.scheme != 'https' ||
        installerUrl?.host != 'github.com' ||
        !installerUrl!.path.startsWith(immutableReleasePrefix)) {
      throw const FormatException('Invalid macOS stable manifest.');
    }

    return DesktopUpdateInfo(
      tag: tag,
      releaseName: 'Vinabike ERP $tag',
      assetName: archiveName,
      installerDownloadUrl: installerUrl.toString(),
      commit: commit,
      // The remote stable manifest is discovery metadata. User-facing notes
      // are loaded only from the local copy persisted after signature
      // verification by the macOS updater.
      releaseNotes: null,
    );
  }

  @visibleForTesting
  Future<DesktopUpdateInfo> fetchLatestWindowsReleaseForTesting() =>
      _fetchLatestWindowsRelease();

  @visibleForTesting
  Future<DesktopUpdateInfo> fetchLatestMacosReleaseForTesting() =>
      _fetchLatestMacosRelease();

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
    final override = _macosUserHomeOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return _userHomeFromMacosPath(override);
    }

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

  Future<DesktopReleaseNotes?> _readPreparedMacosReleaseNotes(
    DesktopUpdateInfo update,
  ) async {
    final directory = await _macosUpdateCoordinationDirectory();
    final manifestFile = File(
      path.join(directory.path, 'prepared-manifest.json'),
    );

    try {
      if (!await manifestFile.exists()) return null;
      if (await manifestFile.length() > _maxReleaseManifestBytes) return null;
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map<String, dynamic>) return null;

      final tag = decoded['tag_name']?.toString() ?? '';
      final commit = decoded['commit']?.toString() ?? '';
      final archiveName = decoded['archive_name']?.toString() ?? '';
      if (tag != update.tag ||
          commit != update.commit ||
          archiveName != update.assetName) {
        return null;
      }

      return DesktopReleaseNotes.tryParse(
        decoded['release_notes'],
        expectedToCommit: update.commit,
      );
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  Future<DesktopReleaseNotes?> readPreparedMacosReleaseNotesForTesting(
    DesktopUpdateInfo update,
  ) =>
      _readPreparedMacosReleaseNotes(update);

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
    final response = await _httpClient.get(
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
            if (_isUpdateReady) {
              _availableUpdate = update.copyWithReleaseNotes(
                await _readPreparedMacosReleaseNotes(update),
              );
            }
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

  Map<String, dynamic>? _findAsset(
    List<dynamic> assets,
    String expectedName,
  ) {
    for (final assetValue in assets) {
      final asset = assetValue as Map<String, dynamic>;
      if (asset['name']?.toString() == expectedName) {
        return asset;
      }
    }

    return null;
  }

  bool _isImmutableGithubReleaseAssetUrl(
    String value, {
    required String tag,
    required String assetName,
  }) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'https' &&
        uri?.host == 'github.com' &&
        uri?.path == '/$_repo/releases/download/$tag/$assetName';
  }

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
