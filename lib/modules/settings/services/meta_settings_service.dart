import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/services/tenant_service.dart';

typedef MetaExternalUrlLauncher = Future<bool> Function(Uri uri);
typedef MetaCurrentTenantLoader = Future<String?> Function();

abstract interface class MetaSettingsGateway {
  Future<MetaSettingsSnapshot> loadSnapshot();

  Future<void> launchAuthorization({required String tenantId});
}

enum MetaChannelProvider {
  instagram,
  facebookMessenger;

  String get label => switch (this) {
        MetaChannelProvider.instagram => 'Instagram',
        MetaChannelProvider.facebookMessenger => 'Facebook Messenger',
      };

  static MetaChannelProvider? fromDatabaseValue(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'instagram' => MetaChannelProvider.instagram,
      'facebook_messenger' => MetaChannelProvider.facebookMessenger,
      _ => null,
    };
  }
}

class MetaChannelStatus {
  final String id;
  final MetaChannelProvider provider;
  final String externalAccountId;
  final String? displayName;
  final String? username;
  final List<String> grantedPermissions;
  final DateTime? authorizationExpiresAt;
  final DateTime? subscribedAt;
  final DateTime? updatedAt;
  final bool isActive;

  const MetaChannelStatus({
    required this.id,
    required this.provider,
    required this.externalAccountId,
    required this.displayName,
    required this.username,
    required this.grantedPermissions,
    required this.authorizationExpiresAt,
    required this.subscribedAt,
    required this.updatedAt,
    required this.isActive,
  });

  String get accountLabel {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }

    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) {
      return handle.startsWith('@') ? handle : '@$handle';
    }

    return externalAccountId;
  }

  bool authorizationExpiredAt(DateTime now) {
    final expiresAt = authorizationExpiresAt;
    return expiresAt != null && !expiresAt.isAfter(now.toUtc());
  }

  List<String> get requiredPermissions => switch (provider) {
        MetaChannelProvider.instagram => _instagramRequiredPermissions,
        MetaChannelProvider.facebookMessenger =>
          _facebookMessengerRequiredPermissions,
      };

  List<String> get missingRequiredPermissions {
    final granted = grantedPermissions.toSet();
    return List<String>.unmodifiable(
      requiredPermissions.where((permission) => !granted.contains(permission)),
    );
  }

  bool isOperationalAt(DateTime now) {
    return isActive &&
        !authorizationExpiredAt(now) &&
        subscribedAt != null &&
        missingRequiredPermissions.isEmpty;
  }
}

class MetaSettingsSnapshot {
  final String tenantId;
  final String role;
  final bool isProfileActive;
  final List<MetaChannelStatus> channels;

  const MetaSettingsSnapshot({
    required this.tenantId,
    required this.role,
    required this.isProfileActive,
    required this.channels,
  });

  bool get canManageAuthorization =>
      isProfileActive && (role == 'admin' || role == 'manager');

  bool hasConnectedChannelAt(DateTime now) {
    return channels.any((channel) => channel.isOperationalAt(now));
  }
}

class MetaSettingsException implements Exception {
  final String message;

  const MetaSettingsException(this.message);

  @override
  String toString() => message;
}

@visibleForTesting
Uri? parseMetaAuthorizationUrl(Object? payload) {
  final root = _stringKeyedMap(payload);
  final expectedClientId = _optionalString(root?['client_id']);
  final rawUrl = root?['authorization_url']?.toString().trim();
  if (root?['ok'] != true ||
      expectedClientId == null ||
      !RegExp(r'^\d+$').hasMatch(expectedClientId) ||
      rawUrl == null ||
      rawUrl.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(rawUrl);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }

  final host = uri.host.toLowerCase();
  if (host != 'www.facebook.com' ||
      !RegExp(r'^/v\d+\.\d+/dialog/oauth$').hasMatch(uri.path) ||
      uri.fragment.isNotEmpty) {
    return null;
  }

  final clientId = _singleQueryValue(uri, 'client_id');
  final redirectUriValue = _singleQueryValue(uri, 'redirect_uri');
  final state = _singleQueryValue(uri, 'state');
  final responseType = _singleQueryValue(uri, 'response_type');
  if (clientId != expectedClientId ||
      redirectUriValue == null ||
      state == null ||
      responseType != 'code') {
    return null;
  }

  final redirectUri = Uri.tryParse(redirectUriValue);
  if (redirectUri == null ||
      redirectUri.scheme.toLowerCase() != 'https' ||
      redirectUri.host.isEmpty ||
      redirectUri.userInfo.isNotEmpty ||
      redirectUri.fragment.isNotEmpty ||
      (redirectUri.hasPort && redirectUri.port != 443)) {
    return null;
  }

  return uri;
}

@visibleForTesting
List<MetaChannelStatus> parseMetaChannelRows(Object? payload) {
  if (payload is! List) {
    throw const MetaSettingsException(
      'Meta devolvió un estado de canales inválido.',
    );
  }

  final channels = <MetaChannelStatus>[];
  for (final rawRow in payload) {
    final row = _stringKeyedMap(rawRow);
    if (row == null) {
      continue;
    }

    final id = row['id']?.toString().trim() ?? '';
    final externalAccountId =
        row['external_account_id']?.toString().trim() ?? '';
    final provider = MetaChannelProvider.fromDatabaseValue(row['provider']);
    if (id.isEmpty || externalAccountId.isEmpty || provider == null) {
      continue;
    }

    final rawScopes = row['granted_scopes'];
    final grantedPermissions = rawScopes is List
        ? (rawScopes
            .map((scope) => scope.toString().trim().toLowerCase())
            .where((scope) => scope.isNotEmpty)
            .toSet()
            .toList()
          ..sort())
        : <String>[];
    channels.add(
      MetaChannelStatus(
        id: id,
        provider: provider,
        externalAccountId: externalAccountId,
        displayName: _optionalString(row['display_name']),
        username: _optionalString(row['username']),
        grantedPermissions: List<String>.unmodifiable(grantedPermissions),
        authorizationExpiresAt: _optionalDate(row['token_expires_at']),
        subscribedAt: _optionalDate(row['subscribed_at']),
        updatedAt: _optionalDate(row['updated_at']),
        isActive: row['is_active'] == true,
      ),
    );
  }

  return List<MetaChannelStatus>.unmodifiable(channels);
}

class MetaSettingsService implements MetaSettingsGateway {
  final SupabaseClient _client;
  final MetaExternalUrlLauncher _externalLauncher;
  final MetaCurrentTenantLoader _currentTenantLoader;

  MetaSettingsService({
    SupabaseClient? client,
    MetaExternalUrlLauncher? externalLauncher,
    MetaCurrentTenantLoader? currentTenantLoader,
  })  : _client = client ?? Supabase.instance.client,
        _externalLauncher = externalLauncher ?? _launchExternally,
        _currentTenantLoader = currentTenantLoader ?? _loadCurrentTenant;

  @override
  Future<MetaSettingsSnapshot> loadSnapshot() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const MetaSettingsException(
        'Tu sesión expiró. Vuelve a iniciar sesión para revisar Meta.',
      );
    }

    try {
      final tenantId = (await _currentTenantLoader())?.trim() ?? '';
      if (!_isUuid(tenantId)) {
        throw const MetaSettingsException(
          'No se pudo identificar la empresa actual para revisar Meta.',
        );
      }

      final profile = await _client
          .from('user_profiles')
          .select('tenant_id, role, is_active')
          .eq('user_id', user.id)
          .eq('tenant_id', tenantId)
          .maybeSingle();
      final role = profile?['role']?.toString().trim().toLowerCase() ?? '';
      final isProfileActive = profile?['is_active'] == true;
      if (role.isEmpty) {
        throw const MetaSettingsException(
          'No encontramos tu acceso de trabajador para esta empresa.',
        );
      }

      final rows = await _client
          .from('meta_channels')
          .select(
            'id, provider, external_account_id, display_name, username, '
            'granted_scopes, token_expires_at, subscribed_at, is_active, '
            'updated_at',
          )
          .eq('tenant_id', tenantId)
          .order('is_active', ascending: false)
          .order('updated_at', ascending: false);

      return MetaSettingsSnapshot(
        tenantId: tenantId,
        role: role,
        isProfileActive: isProfileActive,
        channels: parseMetaChannelRows(rows),
      );
    } on MetaSettingsException {
      rethrow;
    } catch (error) {
      debugPrint(
        '[MetaSettings] Status load failed: ${error.runtimeType}',
      );
      throw const MetaSettingsException(
        'No se pudo cargar el estado de Instagram y Messenger.',
      );
    }
  }

  @override
  Future<void> launchAuthorization({required String tenantId}) async {
    final normalizedTenantId = tenantId.trim();
    if (!_isUuid(normalizedTenantId)) {
      throw const MetaSettingsException(
        'No se pudo identificar la empresa para conectar Meta.',
      );
    }

    final accessToken = _client.auth.currentSession?.accessToken.trim();
    if (accessToken == null || accessToken.isEmpty) {
      throw const MetaSettingsException(
        'Tu sesión expiró. Vuelve a iniciar sesión antes de conectar Meta.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'meta-oauth',
        headers: {'Authorization': 'Bearer $accessToken'},
        body: {
          'action': 'start',
          'tenantId': normalizedTenantId,
        },
      );
      if (response.status != 200) {
        throw _oauthStatusException(response.status);
      }

      final authorizationUri = parseMetaAuthorizationUrl(response.data);
      if (authorizationUri == null) {
        throw const MetaSettingsException(
          'Meta no entregó un enlace de autorización HTTPS válido.',
        );
      }

      final launched = await _externalLauncher(authorizationUri);
      if (!launched) {
        throw const MetaSettingsException(
          'No se pudo abrir Meta en el navegador externo.',
        );
      }
    } on MetaSettingsException {
      rethrow;
    } on FunctionException catch (error) {
      debugPrint(
        '[MetaSettings] OAuth start failed with status ${error.status}.',
      );
      throw _oauthStatusException(error.status);
    } catch (error) {
      debugPrint(
        '[MetaSettings] OAuth start failed: ${error.runtimeType}',
      );
      throw const MetaSettingsException(
        'No se pudo iniciar la autorización con Meta. Inténtalo nuevamente.',
      );
    }
  }

  static Future<bool> _launchExternally(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<String?> _loadCurrentTenant() async {
    final tenantService = TenantService();
    return tenantService.currentTenantId ?? await tenantService.getTenantId();
  }

  static MetaSettingsException _oauthStatusException(int status) {
    return switch (status) {
      401 => const MetaSettingsException(
          'Tu sesión expiró. Vuelve a iniciar sesión antes de conectar Meta.',
        ),
      403 => const MetaSettingsException(
          'Solo administradores y managers pueden autorizar Meta.',
        ),
      503 => const MetaSettingsException(
          'La conexión Meta todavía no está configurada en el servidor.',
        ),
      _ => const MetaSettingsException(
          'No se pudo iniciar la autorización con Meta. Inténtalo nuevamente.',
        ),
    };
  }
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
}

String? _optionalString(Object? value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}

DateTime? _optionalDate(Object? value) {
  final raw = _optionalString(value);
  return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
}

bool _isUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

String? _singleQueryValue(Uri uri, String name) {
  final values = uri.queryParametersAll[name];
  if (values == null || values.length != 1) {
    return null;
  }
  return _optionalString(values.single);
}

// These sets are finalized with the server OAuth contract. They are kept
// provider-specific so a channel is never marked connected from unrelated
// grants merely present on the same Meta authorization.
const List<String> _instagramRequiredPermissions = <String>[
  'pages_show_list',
  'pages_messaging',
  'pages_manage_metadata',
  'pages_read_engagement',
  'instagram_basic',
  'instagram_manage_messages',
  'instagram_manage_comments',
];
const List<String> _facebookMessengerRequiredPermissions = <String>[
  'pages_show_list',
  'pages_messaging',
  'pages_manage_metadata',
  'pages_read_engagement',
];
