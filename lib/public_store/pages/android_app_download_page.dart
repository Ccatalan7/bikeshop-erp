import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_public_core/public_store/models/android_download_words.dart';

import '../../shared/models/android_release_manifest.dart';
import '../../shared/services/mobile_release_repository.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/android_apk_download.dart';

class AndroidAppDownloadPage extends StatefulWidget {
  const AndroidAppDownloadPage({super.key});

  @override
  State<AndroidAppDownloadPage> createState() => _AndroidAppDownloadPageState();
}

class _AndroidAppDownloadPageState extends State<AndroidAppDownloadPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final MobileReleaseRepository _repository;
  late final http.Client _httpClient;
  StreamSubscription<AuthState>? _authSubscription;
  AndroidReleaseManifest? _release;
  bool _loading = true;
  bool _signingIn = false;
  bool _openingDownload = false;
  double? _downloadProgress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = MobileReleaseRepository();
    _httpClient = http.Client();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (!mounted) return;
      unawaited(_loadRelease());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRelease());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _repository.dispose();
    _httpClient.close();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRelease() async {
    if (!mounted) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _release = null;
        _error = null;
      });
      return;
    }

    final tenantId = context.read<PublicStoreTenantProvider>().tenantId?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      setState(() {
        _loading = false;
        _release = null;
        _error = 'No pudimos identificar la tienda.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final release = await _repository.fetchLatestAndroidRelease(
        tenantId: tenantId,
      );
      if (!mounted) return;
      setState(() {
        _release = release;
        _loading = false;
      });
    } on StorageException catch (error) {
      if (!mounted) return;
      setState(() {
        _release = null;
        _loading = false;
        _error = error.statusCode == '404'
            ? androidDownloadUnpublished
            : androidDownloadForbidden;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _release = null;
        _loading = false;
        _error = androidDownloadLoadFailed;
      });
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate() || _signingIn) return;
    setState(() {
      _signingIn = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await _loadRelease();
    } on AuthException {
      if (!mounted) return;
      setState(() => _error = androidDownloadSignInFailed);
    } finally {
      if (mounted) {
        setState(() => _signingIn = false);
      }
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    _passwordController.clear();
    setState(() {
      _release = null;
      _error = null;
    });
  }

  Future<void> _downloadApk() async {
    final release = _release;
    if (release == null || _openingDownload) return;
    setState(() {
      _openingDownload = true;
      _downloadProgress = 0;
      _error = null;
    });

    try {
      final downloadedParts = <Uint8List>[];
      var downloadedBytes = 0;
      for (final part in release.parts) {
        final signedUrl = await _repository.createAndroidApkPartDownloadUrl(
          part,
        );
        final response = await _httpClient.get(Uri.parse(signedUrl));
        if (response.statusCode != 200 ||
            response.bodyBytes.length != part.sizeBytes ||
            sha256.convert(response.bodyBytes).toString() != part.sha256) {
          throw StateError('An APK part failed verification.');
        }
        downloadedParts.add(response.bodyBytes);
        downloadedBytes += response.bodyBytes.length;
        if (mounted) {
          setState(() {
            _downloadProgress = downloadedBytes / release.sizeBytes;
          });
        }
      }
      if (downloadedBytes != release.sizeBytes) {
        throw StateError('The APK download was incomplete.');
      }
      final fullDigest = await sha256
          .bind(
            Stream<List<int>>.fromIterable(downloadedParts),
          )
          .first;
      if (fullDigest.toString() != release.sha256) {
        throw StateError('The APK failed final verification.');
      }
      await saveAndroidApk(
        fileName: release.apkObjectPath.split('/').last,
        parts: downloadedParts,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = androidDownloadFailed);
    } finally {
      if (mounted) {
        setState(() {
          _openingDownload = false;
          _downloadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ColoredBox(
      color: colors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 64),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  androidDownloadTitle,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  androidDownloadLead,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (user == null)
                  _buildSignInCard(context)
                else
                  _buildReleaseCard(context),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignInCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              androidDownloadSignInTitle,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: androidDownloadEmailLabel,
                border: OutlineInputBorder(),
              ),
              validator: androidDownloadEmailError,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _signIn(),
              decoration: const InputDecoration(
                labelText: androidDownloadPasswordLabel,
                border: OutlineInputBorder(),
              ),
              validator: androidDownloadPasswordError,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _signingIn ? null : _signIn,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                _signingIn ? androidDownloadSigningIn : androidDownloadSignIn,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReleaseCard(BuildContext context) {
    final release = _release;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (release == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(androidDownloadNone),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _signOut,
              child: const Text(androidDownloadOtherAccount),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  androidDownloadVersion(release.versionName),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _signOut,
                child: const Text(androidDownloadSignOut),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            release.releaseNotes?.summary ?? androidDownloadDefaultSummary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _MetadataRow(
            label: androidDownloadSizeLabel,
            value: androidDownloadSize(release.sizeBytes),
          ),
          const SizedBox(height: 6),
          _MetadataRow(
            label: androidDownloadCheckLabel,
            value: androidDownloadCheck(release.sha256),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('android-private-download-button'),
            onPressed: _openingDownload ? null : _downloadApk,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.android_rounded),
            label: Text(
              _openingDownload
                  ? androidDownloadProgress(
                      ((_downloadProgress ?? 0) * 100).round(),
                    )
                  : androidDownloadButton,
            ),
          ),
          if (_openingDownload) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _downloadProgress),
          ],
          const SizedBox(height: 12),
          Text(
            androidDownloadNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
