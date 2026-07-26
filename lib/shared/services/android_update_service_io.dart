import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/android_release_manifest.dart';
import 'mobile_release_repository.dart';

class AndroidUpdateService extends ChangeNotifier {
  static const _channel = MethodChannel('com.vinabike.erp/android_update');

  final SupabaseClient _supabase;
  final MobileReleaseRepository _releaseRepository;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  bool _hasChecked = false;
  bool _isChecking = false;
  bool _isDownloading = false;
  bool _dismissed = false;
  double? _downloadProgress;
  AndroidReleaseManifest? _availableUpdate;
  String? _errorMessage;
  String? _statusMessage;

  AndroidUpdateService({
    SupabaseClient? supabase,
    MobileReleaseRepository? releaseRepository,
    http.Client? httpClient,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _releaseRepository = releaseRepository ??
            MobileReleaseRepository(
              supabase: supabase ?? Supabase.instance.client,
            ),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  bool get isSupported => !kDebugMode && Platform.isAndroid;
  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double? get downloadProgress => _downloadProgress;
  AndroidReleaseManifest? get availableUpdate =>
      _dismissed ? null : _availableUpdate;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;

  Future<void> checkForUpdate({bool force = false}) async {
    if (!isSupported) return;
    if (_isChecking || (_hasChecked && !force)) return;
    if (_supabase.auth.currentUser == null) return;

    _isChecking = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      final tenantId = await _currentTenantId();
      if (tenantId == null) {
        _availableUpdate = null;
        return;
      }

      final installedVersionCode = await _channel.invokeMethod<int>(
        'getInstalledVersionCode',
      );
      if (installedVersionCode == null || installedVersionCode <= 0) {
        throw StateError('Android did not return the installed version.');
      }

      final release = await _releaseRepository.fetchLatestAndroidRelease(
        tenantId: tenantId,
      );
      if (release.versionCode > installedVersionCode) {
        if (_availableUpdate?.versionCode != release.versionCode) {
          _dismissed = false;
        }
        _availableUpdate = release;
      } else {
        _availableUpdate = null;
        _dismissed = false;
      }
      _hasChecked = true;
    } on StorageException catch (error, stackTrace) {
      _errorMessage = 'No se pudo revisar la actualización privada.';
      debugPrint('Android release storage check failed: $error\n$stackTrace');
    } catch (error, stackTrace) {
      _errorMessage = 'No se pudo revisar actualizaciones.';
      debugPrint('Android update check failed: $error\n$stackTrace');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<void> installAvailableUpdate() async {
    if (!isSupported || _isDownloading) return;
    final release = _availableUpdate;
    if (release == null) return;

    _isDownloading = true;
    _downloadProgress = 0;
    _errorMessage = null;
    _statusMessage = 'Descargando actualización…';
    notifyListeners();

    File? apkFile;
    try {
      apkFile = await _downloadAndVerifyApk(release);

      _statusMessage = 'Abriendo el instalador de Android…';
      notifyListeners();

      final result = await _channel.invokeMethod<String>('installApk', {
        'path': apkFile.path,
      });
      _statusMessage = result == 'permission_requested'
          ? 'Activa “Permitir desde esta fuente” y vuelve a la aplicación.'
          : 'Confirma la actualización en Android.';
    } catch (error, stackTrace) {
      _errorMessage = 'No se pudo preparar la actualización.';
      _statusMessage = null;
      debugPrint('Android update installation failed: $error\n$stackTrace');
      if (apkFile != null && await apkFile.exists()) {
        await apkFile.delete();
      }
      rethrow;
    } finally {
      _isDownloading = false;
      _downloadProgress = null;
      notifyListeners();
    }
  }

  void dismissAvailableUpdate() {
    _dismissed = true;
    notifyListeners();
  }

  Future<String?> _currentTenantId() async {
    final value = await _supabase.rpc('user_tenant_id');
    final tenantId = value?.toString().trim();
    return tenantId == null || tenantId.isEmpty ? null : tenantId;
  }

  Future<File> _downloadAndVerifyApk(
    AndroidReleaseManifest release,
  ) async {
    final temporaryDirectory = await getTemporaryDirectory();
    final updateDirectory = Directory(
      path.join(temporaryDirectory.path, 'android-updates'),
    );
    await updateDirectory.create(recursive: true);

    final apk = File(
      path.join(
        updateDirectory.path,
        'vinabike-erp-${release.versionCode}.apk',
      ),
    );
    if (await apk.exists()) {
      await apk.delete();
    }

    try {
      final sink = apk.openWrite();
      var receivedTotal = 0;
      try {
        for (final part in release.parts) {
          final signedUrl =
              await _releaseRepository.createAndroidApkPartDownloadUrl(part);
          final request = http.Request('GET', Uri.parse(signedUrl));
          final response = await _httpClient.send(request);
          if (response.statusCode != HttpStatus.ok) {
            throw HttpException(
              'APK part download failed with HTTP ${response.statusCode}.',
            );
          }
          final contentLength = response.contentLength;
          if (contentLength != null && contentLength != part.sizeBytes) {
            throw const FormatException(
              'An APK part size does not match the manifest.',
            );
          }

          final partDigestSink = _DigestSink();
          final partHashSink = sha256.startChunkedConversion(partDigestSink);
          var receivedPart = 0;
          try {
            await for (final chunk in response.stream) {
              receivedPart += chunk.length;
              receivedTotal += chunk.length;
              if (receivedPart > part.sizeBytes ||
                  receivedTotal > release.sizeBytes ||
                  receivedTotal > AndroidReleaseManifest.maximumApkBytes) {
                throw const FormatException(
                  'The APK exceeded its declared size.',
                );
              }
              partHashSink.add(chunk);
              sink.add(chunk);
              _downloadProgress = receivedTotal / release.sizeBytes;
              notifyListeners();
            }
          } finally {
            partHashSink.close();
          }
          if (receivedPart != part.sizeBytes) {
            throw const FormatException('An APK part was incomplete.');
          }
          if (partDigestSink.value?.toString() != part.sha256) {
            throw const FormatException('An APK part checksum is invalid.');
          }
        }
      } finally {
        await sink.close();
      }

      if (receivedTotal != release.sizeBytes) {
        throw const FormatException('The APK download was incomplete.');
      }

      final digest = await sha256.bind(apk.openRead()).first;
      if (digest.toString() != release.sha256) {
        throw const FormatException('The APK checksum is invalid.');
      }

      return apk;
    } catch (_) {
      if (await apk.exists()) {
        await apk.delete();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
