import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' if (dart.library.io) '../services/google_oauth_storage_stub.dart'
    as html;

/// Stable landing page for OAuth redirects.
///
/// Why: If we redirect OAuth back to '/', the router may immediately redirect to
/// '/login' or '/dashboard' and strip the `?code=...` query params before
/// Supabase can exchange them into a session.
class AuthCallbackPage extends StatefulWidget {
  const AuthCallbackPage({super.key});

  static const webReturnToEditorKey = 'google_oauth_return_to_editor';

  @override
  State<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends State<AuthCallbackPage> {
  StreamSubscription<AuthState>? _sub;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();

    // Log the raw URL (no secrets) to help diagnose lost callbacks.
    if (kIsWeb) {
      final uri = Uri.base;
      final qp = uri.queryParameters;
      debugPrint('🧩 [AuthCallback] Landed on path=${uri.path}');
      debugPrint(
          '🧩 [AuthCallback] Query keys=${qp.keys.toList()} hasCode=${qp.containsKey('code')} hasError=${qp.containsKey('error')}');
    }

    // Wait for Supabase to finish processing the OAuth callback.
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final hasProviderToken = session?.providerToken != null;
      final provider = session?.user.appMetadata['provider'];
      final identities = session?.user.identities?.map((i) => i.provider).toList();

      final sessionJson = session?.toJson();
          final map = sessionJson is Map
            ? Map<String, dynamic>.from(sessionJson as Map<dynamic, dynamic>)
            : null;
        final hasProviderTokenJson = map?['provider_token'] != null;
        final hasProviderRefreshTokenJson = map?['provider_refresh_token'] != null;

      debugPrint(
        '🧩 [AuthCallback] Auth event=${data.event}, provider=$provider, identities=$identities, hasProviderToken=$hasProviderToken, hasProviderTokenJson=$hasProviderTokenJson, hasProviderRefreshTokenJson=$hasProviderRefreshTokenJson');

      if (session != null) {
        // Sometimes a refresh makes Supabase rehydrate the session.
        Supabase.instance.client.auth.refreshSession().then((_) {
          final s2 = Supabase.instance.client.auth.currentSession;
          final has2 = s2?.providerToken != null;
          final s2json = s2?.toJson();
            final m2 = s2json is Map
              ? Map<String, dynamic>.from(s2json as Map<dynamic, dynamic>)
              : null;
          final has2json = m2?['provider_token'] != null;
          debugPrint(
              '🧩 [AuthCallback] After refreshSession: hasProviderToken=$has2, hasProviderTokenJson=$has2json');
        }).catchError((e) {
          debugPrint('⚠️ [AuthCallback] refreshSession failed: $e');
        });
        _navigatePostCallback();
      }
    });

    // Fallback: if session is already available (some browsers restore quickly)
    // navigate after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = Supabase.instance.client.auth.currentSession;
      final sessionJson = session?.toJson();
          final map = sessionJson is Map
            ? Map<String, dynamic>.from(sessionJson as Map<dynamic, dynamic>)
            : null;
        final hasProviderTokenJson = map?['provider_token'] != null;
      debugPrint(
          '🧩 [AuthCallback] Initial session provider=${session?.user.appMetadata['provider']}, identities=${session?.user.identities?.map((i) => i.provider).toList()}, hasProviderToken=${session?.providerToken != null}, hasProviderTokenJson=$hasProviderTokenJson');
      if (session != null) {
        _navigatePostCallback();
      }
    });

    // Safety timeout: don’t hang forever.
    _timeout = Timer(const Duration(seconds: 12), () {
      debugPrint('⏱️ [AuthCallback] Timeout waiting for session');
      if (mounted) {
        context.go('/');
      }
    });
  }

  void _navigatePostCallback() {
    _timeout?.cancel();

    // If this callback came from the store editor flow, request returning to
    // edit mode (PublicStoreLayout already consumes this flag).
    if (kIsWeb) {
      try {
        final flag = html.window.localStorage[AuthCallbackPage.webReturnToEditorKey];
        debugPrint('🧩 [AuthCallback] returnToEditor flag=$flag');
        // Keep the flag for PublicStoreLayout to consume & clear.
      } catch (e) {
        debugPrint('⚠️ [AuthCallback] localStorage read failed: $e');
      }
    }

    if (!mounted) return;

    // Send the user somewhere sane. For ERP host, '/' becomes login/dashboard.
    // For store host, '/' becomes store home.
    context.go('/');
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Completando autorización…',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'No cierres esta pestaña. Te redirigiremos automáticamente.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
