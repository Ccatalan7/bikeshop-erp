import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/authority_scoped_cache.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/constants/storage_constants.dart';
import '../../../shared/themes/appearance_preset.dart';
import '../../../shared/themes/sidebar_palette_option.dart';
import '../../../shared/themes/workspace_chrome_theme.dart';
import '../../../shared/widgets/workspace_shell_scope.dart';

export '../../../shared/themes/sidebar_palette_option.dart';

typedef AppearanceCompanySettingsLoader = Future<List<Map<String, dynamic>>>
    Function(String tenantId);

class AppearanceService extends ChangeNotifier {
  static const String _homeIconKey = 'home_icon';
  static const String _companyLogoKey = 'company_logo';
  static const String _themeModeKey = 'theme_mode';
  static const String _sidebarPaletteKey = 'sidebar_palette';
  static const String _messagingSidebarPaletteKey =
      'quick_chat_uses_sidebar_palette';
  static const String _rightToolbarOverContentKey =
      'right_toolbar_over_content';
  static const String _rightToolbarBlurEnabledKey =
      'right_toolbar_blur_enabled';
  static const String _scopedPreferencesPrefix = 'vinabike_appearance_v2';
  static const String _legacyMigrationClaimKey =
      'vinabike_appearance_legacy_claim_v1';

  IconData _homeIcon = Icons.pedal_bike;
  String? _companyLogoUrl;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasLoadedWithTenant = false;
  int _cacheBuster = DateTime.now().millisecondsSinceEpoch;
  ThemeMode _themeMode = ThemeMode.light;
  String _sidebarPaletteCode = 'vinabike';
  bool _messagingUsesSidebarPalette = false;
  bool _rightToolbarOverContent = true;
  bool _rightToolbarBlurEnabled = true;
  final SupabaseClient? _supabaseOverride;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final AppearanceCompanySettingsLoader? _companySettingsLoader;
  final AuthorityCacheScope _authorityScope = AuthorityCacheScope();
  Future<void> _preferencesTail = Future<void>.value();
  String? _requestedUserId;
  Future<String?> Function()? _tenantResolver;
  int _synchronizationGeneration = 0;
  ErpAuthorityScopeKey? _lastResolvedScope;
  final Map<_AppearancePreferenceField, int> _preferenceRevisions = {
    for (final field in _AppearancePreferenceField.values) field: 0,
  };
  bool _authorityResolutionPending = false;
  bool _disposed = false;

  AppearanceService({
    SupabaseClient? supabase,
    Future<SharedPreferences> Function()? preferencesLoader,
    AppearanceCompanySettingsLoader? companySettingsLoader,
  })  : _supabaseOverride = supabase,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _companySettingsLoader = companySettingsLoader;

  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;

  @override
  void dispose() {
    _disposed = true;
    _synchronizationGeneration++;
    _authorityResolutionPending = false;
    _authorityScope.bind(userId: null, tenantId: null);
    super.dispose();
  }

  IconData get homeIcon => _homeIcon;
  String? get companyLogoUrl {
    if (_companyLogoUrl == null) return null;
    // Always add/update the cache-busting parameter when accessing the URL
    final baseUrl = _companyLogoUrl!.split('?').first;
    return '$baseUrl?v=$_cacheBuster';
  }

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get hasLoadedWithTenant => _hasLoadedWithTenant;
  bool get hasCustomLogo =>
      _companyLogoUrl != null && _companyLogoUrl!.isNotEmpty;
  ThemeMode get themeMode => _themeMode;
  String get sidebarPaletteCode => _sidebarPaletteCode;
  bool get messagingUsesSidebarPalette => _messagingUsesSidebarPalette;
  bool get quickChatUsesSidebarPalette => _messagingUsesSidebarPalette;
  bool get rightToolbarOverContent => _rightToolbarOverContent;
  bool get rightToolbarBlurEnabled => _rightToolbarBlurEnabled;
  SidebarPaletteOption get sidebarPalette => sidebarPalettes.firstWhere(
        (palette) => palette.code == _sidebarPaletteCode,
        orElse: () => sidebarPalettes.first,
      );
  AppearancePreset get appearancePreset =>
      AppearancePresets.byCode(_sidebarPaletteCode);

  static const List<SidebarPaletteOption> sidebarPalettes =
      AppearancePresets.sidebarPalettes;

  // Available home icons for selection
  static const List<HomeIconOption> availableIcons = [
    HomeIconOption(
        icon: Icons.pedal_bike, name: 'Bicicleta', code: 'pedal_bike'),
    HomeIconOption(
        icon: Icons.directions_bike,
        name: 'Bicicleta (alt)',
        code: 'directions_bike'),
    HomeIconOption(
        icon: Icons.two_wheeler, name: 'Motocicleta', code: 'two_wheeler'),
    HomeIconOption(icon: Icons.store, name: 'Tienda', code: 'store'),
    HomeIconOption(icon: Icons.business, name: 'Negocio', code: 'business'),
    HomeIconOption(
        icon: Icons.storefront, name: 'Tienda (alt)', code: 'storefront'),
    HomeIconOption(icon: Icons.home, name: 'Casa', code: 'home'),
    HomeIconOption(
        icon: Icons.home_work, name: 'Casa/Trabajo', code: 'home_work'),
    HomeIconOption(icon: Icons.apartment, name: 'Edificio', code: 'apartment'),
    HomeIconOption(
        icon: Icons.account_balance, name: 'Banco', code: 'account_balance'),
    HomeIconOption(
        icon: Icons.shopping_bag,
        name: 'Bolsa de compras',
        code: 'shopping_bag'),
    HomeIconOption(
        icon: Icons.shopping_cart, name: 'Carrito', code: 'shopping_cart'),
    HomeIconOption(
        icon: Icons.local_shipping, name: 'Envío', code: 'local_shipping'),
    HomeIconOption(icon: Icons.build, name: 'Herramientas', code: 'build'),
    HomeIconOption(icon: Icons.handyman, name: 'Taller', code: 'handyman'),
    HomeIconOption(
        icon: Icons.construction, name: 'Construcción', code: 'construction'),
    HomeIconOption(icon: Icons.sports, name: 'Deportes', code: 'sports'),
    HomeIconOption(
        icon: Icons.fitness_center, name: 'Gimnasio', code: 'fitness_center'),
    HomeIconOption(icon: Icons.star, name: 'Estrella', code: 'star'),
    HomeIconOption(icon: Icons.favorite, name: 'Corazón', code: 'favorite'),
  ];

  /// Binds local appearance and tenant branding to one exact ERP authority.
  ///
  /// The provider owns when this is called. Each invocation supersedes every
  /// prior async load, so a late result from a signed-out user or old tenant
  /// can never repaint the current application.
  Future<void> synchronize({
    required String? userId,
    required Future<String?> Function() resolveTenantId,
  }) async {
    final normalizedUserId = _normalized(userId);
    final identityChanged = normalizedUserId != _requestedUserId;
    final previousResolvedScope = identityChanged ? null : _lastResolvedScope;
    _requestedUserId = normalizedUserId;
    _tenantResolver = resolveTenantId;
    final generation = ++_synchronizationGeneration;

    if (identityChanged) {
      _lastResolvedScope = null;
      _resetState(resetPreferences: true);
    }

    if (normalizedUserId == null) {
      _authorityScope.bind(userId: null, tenantId: null);
      _lastResolvedScope = null;
      _authorityResolutionPending = false;
      if (!identityChanged) {
        _resetState(resetPreferences: true);
      }
      _isInitialized = true;
      _isLoading = false;
      _notify();
      return;
    }

    // Tenant resolution is asynchronous and can return a different tenant for
    // the same authenticated user. Invalidate the previous authority before
    // awaiting it so no setter or captured lease can operate on the old tenant
    // during that unresolved window.
    _authorityScope.bind(userId: null, tenantId: null);
    _authorityResolutionPending = true;
    _isLoading = true;
    _isInitialized = false;
    final revisionsAtStart = _preferenceRevisionSnapshot;
    _notify();

    String? tenantId;
    try {
      tenantId = _normalized(await resolveTenantId());
    } catch (error) {
      if (!kReleaseMode) {
        debugPrint(
          '[AppearanceService] Tenant resolution failed: $error',
        );
      }
    }
    if (!_ownsRequest(generation, normalizedUserId)) return;

    final nextScope = ErpAuthorityScopeKey.from(
      userId: normalizedUserId,
      tenantId: tenantId,
    );
    if (nextScope == null) {
      _authorityScope.bind(userId: null, tenantId: null);
      _lastResolvedScope = null;
      _authorityResolutionPending = false;
      _resetState(resetPreferences: true);
      _isInitialized = true;
      _isLoading = false;
      _notify();
      return;
    }

    final scopeChanged = previousResolvedScope != nextScope;
    _authorityScope.bind(
      userId: nextScope.userId,
      tenantId: nextScope.tenantId,
    );
    _authorityResolutionPending = false;
    _lastResolvedScope = nextScope;
    if (scopeChanged) {
      _homeIcon = Icons.pedal_bike;
      _companyLogoUrl = null;
      _hasLoadedWithTenant = false;
      _resetPreferences();
      _notify();
    }

    try {
      final loadedPreferences = await _loadScopedPreferences(
        nextScope,
        isCurrent: () => _ownsRequest(
          generation,
          normalizedUserId,
          scope: nextScope,
        ),
      );
      if (!_ownsRequest(
        generation,
        normalizedUserId,
        scope: nextScope,
      )) {
        return;
      }

      if (loadedPreferences != null) {
        final mergedPreferences = _mergeLoadedPreferences(
          loadedPreferences,
          revisionsAtStart: revisionsAtStart,
        );
        final preferencesChangedDuringLoad =
            _preferencesChangedSince(revisionsAtStart);
        _applyPreferences(mergedPreferences);
        if (preferencesChangedDuringLoad) {
          await _persistPreferences(
            nextScope,
            mergedPreferences,
          );
        }
        _notify();
      }
    } catch (error) {
      if (!_ownsRequest(
        generation,
        normalizedUserId,
        scope: nextScope,
      )) {
        return;
      }
      if (!kReleaseMode) {
        debugPrint(
          '[AppearanceService] Local preference load failed: $error',
        );
      }
      _applyPreferences(
        _mergeLoadedPreferences(
          const _AppearancePreferences.defaults(),
          revisionsAtStart: revisionsAtStart,
        ),
      );
      _notify();
    }

    try {
      final companySettings = await _fetchCompanySettings(nextScope.tenantId);
      if (!_ownsRequest(
        generation,
        normalizedUserId,
        scope: nextScope,
      )) {
        return;
      }
      _applyCompanySettings(companySettings);
      _isInitialized = true;
      _hasLoadedWithTenant = true;
      _isLoading = false;
      if (!kReleaseMode) {
        debugPrint(
          '[AppearanceService] Scoped settings loaded. '
          'hasCustomLogo=$hasCustomLogo',
        );
      }
      _notify();
    } catch (error) {
      if (!_ownsRequest(
        generation,
        normalizedUserId,
        scope: nextScope,
      )) {
        return;
      }
      if (!kReleaseMode) {
        debugPrint(
          '[AppearanceService] Company settings load failed: $error',
        );
      }
      _isInitialized = true;
      _hasLoadedWithTenant = false;
      _isLoading = false;
      _notify();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCompanySettings(
    String tenantId,
  ) async {
    final loader = _companySettingsLoader;
    if (loader != null) return loader(tenantId);
    final response = await _supabase
        .from('company_settings')
        .select('key, value')
        .eq('tenant_id', tenantId)
        .inFilter('key', [_homeIconKey, _companyLogoKey]);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<_AppearancePreferences?> _loadScopedPreferences(
    ErpAuthorityScopeKey scope, {
    required bool Function() isCurrent,
  }) {
    return _withPreferencesLock((preferences) async {
      if (!isCurrent()) return null;

      final storageKey = _scopedPreferencesKey(scope);
      final existingRaw = preferences.getString(storageKey);
      if (existingRaw != null) {
        final existing = _AppearancePreferences.tryDecode(
              existingRaw,
              expectedScope: scope,
              supportedPalettes: sidebarPalettes,
            ) ??
            const _AppearancePreferences.defaults();
        if (!isCurrent()) return null;
        await preferences.setString(storageKey, existing.encode(scope));
        return existing;
      }

      final scopeToken = _scopeToken(scope);
      var migrationClaim = preferences.getString(_legacyMigrationClaimKey);
      if (migrationClaim == null) {
        await preferences.setString(_legacyMigrationClaimKey, scopeToken);
        migrationClaim = scopeToken;
      }
      if (!isCurrent()) return null;

      final migrated = migrationClaim == scopeToken
          ? _legacyPreferences(preferences)
          : const _AppearancePreferences.defaults();
      await preferences.setString(storageKey, migrated.encode(scope));

      if (migrationClaim == scopeToken) {
        for (final key in _legacyPreferenceKeys) {
          await preferences.remove(key);
        }
      }
      return isCurrent() ? migrated : null;
    });
  }

  _AppearancePreferences _legacyPreferences(SharedPreferences preferences) {
    final themeModeValue = preferences.get(_themeModeKey);
    final paletteValue = preferences.get(_sidebarPaletteKey);
    final messagingValue = preferences.get(_messagingSidebarPaletteKey);
    final toolbarValue = preferences.get(_rightToolbarOverContentKey);
    final blurValue = preferences.get(_rightToolbarBlurEnabledKey);
    return _AppearancePreferences(
      themeMode: _parseThemeMode(themeModeValue),
      sidebarPaletteCode: _parsePaletteCode(paletteValue),
      messagingUsesSidebarPalette:
          messagingValue is bool ? messagingValue : false,
      rightToolbarOverContent: toolbarValue is bool ? toolbarValue : true,
      rightToolbarBlurEnabled: blurValue is bool ? blurValue : true,
    );
  }

  Future<void> _persistPreferences(
    ErpAuthorityScopeKey scope,
    _AppearancePreferences preferences,
  ) {
    return _withPreferencesLock((storage) async {
      await storage.setString(
        _scopedPreferencesKey(scope),
        preferences.encode(scope),
      );
    });
  }

  Future<T> _withPreferencesLock<T>(
    Future<T> Function(SharedPreferences preferences) operation,
  ) {
    final completer = Completer<T>();
    _preferencesTail = _preferencesTail.then((_) async {
      try {
        final preferences = await _preferencesLoader();
        completer.complete(await operation(preferences));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _applyPreferences(_AppearancePreferences preferences) {
    _themeMode = preferences.themeMode;
    _sidebarPaletteCode = preferences.sidebarPaletteCode;
    _messagingUsesSidebarPalette = preferences.messagingUsesSidebarPalette;
    _rightToolbarOverContent = preferences.rightToolbarOverContent;
    _rightToolbarBlurEnabled = preferences.rightToolbarBlurEnabled;
  }

  _AppearancePreferences _mergeLoadedPreferences(
    _AppearancePreferences loaded, {
    required Map<_AppearancePreferenceField, int> revisionsAtStart,
  }) {
    bool unchanged(_AppearancePreferenceField field) =>
        revisionsAtStart[field] == _preferenceRevisions[field];

    return _AppearancePreferences(
      themeMode: unchanged(_AppearancePreferenceField.themeMode)
          ? loaded.themeMode
          : _themeMode,
      sidebarPaletteCode: unchanged(_AppearancePreferenceField.sidebarPalette)
          ? loaded.sidebarPaletteCode
          : _sidebarPaletteCode,
      messagingUsesSidebarPalette:
          unchanged(_AppearancePreferenceField.messagingSidebarPalette)
              ? loaded.messagingUsesSidebarPalette
              : _messagingUsesSidebarPalette,
      rightToolbarOverContent:
          unchanged(_AppearancePreferenceField.rightToolbarOverContent)
              ? loaded.rightToolbarOverContent
              : _rightToolbarOverContent,
      rightToolbarBlurEnabled:
          unchanged(_AppearancePreferenceField.rightToolbarBlurEnabled)
              ? loaded.rightToolbarBlurEnabled
              : _rightToolbarBlurEnabled,
    );
  }

  Map<_AppearancePreferenceField, int> get _preferenceRevisionSnapshot =>
      Map<_AppearancePreferenceField, int>.unmodifiable(
        _preferenceRevisions,
      );

  bool _preferencesChangedSince(
    Map<_AppearancePreferenceField, int> snapshot,
  ) {
    return _AppearancePreferenceField.values.any(
      (field) => snapshot[field] != _preferenceRevisions[field],
    );
  }

  void _markPreferenceChanged(_AppearancePreferenceField field) {
    _preferenceRevisions[field] = _preferenceRevisions[field]! + 1;
  }

  ErpAuthorityScopeKey? _preferenceMutationScope() {
    if (_authorityResolutionPending) {
      throw StateError(
        'Appearance settings cannot change while ERP authority is resolving',
      );
    }
    return _authorityScope.key;
  }

  void _applyCompanySettings(List<Map<String, dynamic>> settings) {
    _homeIcon = Icons.pedal_bike;
    _companyLogoUrl = null;
    for (final row in settings) {
      final key = row['key']?.toString();
      final value = row['value']?.toString();
      if (key == _homeIconKey && value != null && value.isNotEmpty) {
        _homeIcon = availableIcons
            .firstWhere(
              (option) => option.code == value,
              orElse: () => availableIcons.first,
            )
            .icon;
      } else if (key == _companyLogoKey && value != null && value.isNotEmpty) {
        _companyLogoUrl = value.split('?').first;
      }
    }
  }

  bool _ownsRequest(
    int generation,
    String userId, {
    ErpAuthorityScopeKey? scope,
  }) {
    if (_disposed ||
        generation != _synchronizationGeneration ||
        _requestedUserId != userId) {
      return false;
    }
    return scope == null || _authorityScope.key == scope;
  }

  void _resetState({required bool resetPreferences}) {
    _homeIcon = Icons.pedal_bike;
    _companyLogoUrl = null;
    _hasLoadedWithTenant = false;
    if (resetPreferences) _resetPreferences();
  }

  void _resetPreferences() {
    _themeMode = ThemeMode.light;
    _sidebarPaletteCode = 'vinabike';
    _messagingUsesSidebarPalette = false;
    _rightToolbarOverContent = true;
    _rightToolbarBlurEnabled = true;
  }

  _AppearancePreferences get _currentPreferences => _AppearancePreferences(
        themeMode: _themeMode,
        sidebarPaletteCode: _sidebarPaletteCode,
        messagingUsesSidebarPalette: _messagingUsesSidebarPalette,
        rightToolbarOverContent: _rightToolbarOverContent,
        rightToolbarBlurEnabled: _rightToolbarBlurEnabled,
      );

  AuthorityCacheLease _requireAuthorityLease() {
    final lease = _authorityScope.capture();
    if (lease == null) {
      throw StateError('Appearance settings require an active ERP authority');
    }
    return lease;
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static ThemeMode _parseThemeMode(Object? value) {
    if (value is! String) return ThemeMode.light;
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.light,
    );
  }

  static String _parsePaletteCode(Object? value) {
    if (value is String &&
        sidebarPalettes.any((palette) => palette.code == value)) {
      return value;
    }
    return 'vinabike';
  }

  static String _scopeToken(ErpAuthorityScopeKey scope) =>
      '${scope.tenantId}:${scope.userId}';

  static String _scopedPreferencesKey(ErpAuthorityScopeKey scope) =>
      '$_scopedPreferencesPrefix:${_scopeToken(scope)}';

  static const List<String> _legacyPreferenceKeys = [
    _themeModeKey,
    _sidebarPaletteKey,
    _messagingSidebarPaletteKey,
    _rightToolbarOverContentKey,
    _rightToolbarBlurEnabledKey,
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Refresh the logo with a new cache-buster to force reload
  void refreshLogo() {
    _cacheBuster = DateTime.now().millisecondsSinceEpoch;
    _notify();
  }

  /// Reload settings for the currently requested Auth identity.
  Future<void> reloadSettings() async {
    final resolver = _tenantResolver;
    if (resolver == null) return;
    await synchronize(
      userId: _requestedUserId,
      resolveTenantId: resolver,
    );
  }

  Future<void> setHomeIcon(IconData icon, String iconCode) async {
    try {
      final lease = _requireAuthorityLease();
      final tenantId = lease.scope.tenantId;

      // Check if setting exists
      final existing = await _supabase
          .from('company_settings')
          .select('id')
          .eq('tenant_id', tenantId)
          .eq('key', _homeIconKey)
          .maybeSingle();
      if (!_authorityScope.owns(lease)) {
        throw const AuthorityScopeChangedException();
      }

      if (existing != null) {
        // Update existing record
        await _supabase
            .from('company_settings')
            .update({
              'value': iconCode,
              'updated_at': DateTime.now().toIso8601String()
            })
            .eq('tenant_id', tenantId)
            .eq('key', _homeIconKey);
      } else {
        // Insert new record
        await _supabase.from('company_settings').insert({
          'tenant_id': tenantId,
          'key': _homeIconKey,
          'value': iconCode,
          'updated_at': DateTime.now().toIso8601String()
        });
      }

      if (_authorityScope.owns(lease)) {
        _homeIcon = icon;
        _notify();
      }
    } catch (e) {
      debugPrint('[AppearanceService] Error saving home icon: $e');
      rethrow;
    }
  }

  String getIconCode(IconData icon) {
    final option = availableIcons.firstWhere(
      (opt) => opt.icon == icon,
      orElse: () => availableIcons.first,
    );
    return option.code;
  }

  Future<void> uploadCompanyLogo(Uint8List imageBytes, String fileName) async {
    try {
      debugPrint('[AppearanceService] uploadCompanyLogo started: $fileName');

      final lease = _requireAuthorityLease();
      final tenantId = lease.scope.tenantId;

      debugPrint('[AppearanceService] Tenant ID: $tenantId');

      // Upload to Supabase storage
      debugPrint('[AppearanceService] Uploading to storage...');
      final imageUrl = await ImageService.uploadBytes(
        bytes: imageBytes,
        fileName: fileName,
        bucket: StorageConfig.defaultBucket,
        folder: 'company_logos',
      );

      debugPrint('[AppearanceService] Upload complete, URL: $imageUrl');

      if (imageUrl != null) {
        if (!_authorityScope.owns(lease)) {
          throw const AuthorityScopeChangedException();
        }
        // Check if setting exists
        debugPrint('[AppearanceService] Checking existing settings...');
        final existing = await _supabase
            .from('company_settings')
            .select('id')
            .eq('tenant_id', tenantId)
            .eq('key', _companyLogoKey)
            .maybeSingle();
        if (!_authorityScope.owns(lease)) {
          throw const AuthorityScopeChangedException();
        }

        debugPrint(
            '[AppearanceService] Existing record: ${existing != null ? "found" : "not found"}');

        if (existing != null) {
          // Update existing record
          debugPrint('[AppearanceService] Updating existing record...');
          await _supabase
              .from('company_settings')
              .update({
                'value': imageUrl,
                'updated_at': DateTime.now().toIso8601String()
              })
              .eq('tenant_id', tenantId)
              .eq('key', _companyLogoKey);
        } else {
          // Insert new record
          debugPrint('[AppearanceService] Inserting new record...');
          await _supabase.from('company_settings').insert({
            'tenant_id': tenantId,
            'key': _companyLogoKey,
            'value': imageUrl,
            'updated_at': DateTime.now().toIso8601String()
          });
        }

        debugPrint('[AppearanceService] Database updated successfully');

        if (_authorityScope.owns(lease)) {
          _companyLogoUrl = imageUrl;
          // Update cache-buster to force reload on all devices
          _cacheBuster = DateTime.now().millisecondsSinceEpoch;

          debugPrint('[AppearanceService] Logo URL set to: $_companyLogoUrl');
          debugPrint('[AppearanceService] Cache buster: $_cacheBuster');
          debugPrint('[AppearanceService] Notifying listeners...');

          _notify();
        }

        debugPrint('[AppearanceService] Upload complete!');
      } else {
        throw Exception('Failed to upload image');
      }
    } catch (e) {
      debugPrint('[AppearanceService] Error uploading logo: $e');
      rethrow;
    }
  }

  Future<void> removeCompanyLogo() async {
    try {
      final lease = _requireAuthorityLease();
      final tenantId = lease.scope.tenantId;

      // Remove from Supabase database (synced across devices)
      await _supabase
          .from('company_settings')
          .update(
              {'value': null, 'updated_at': DateTime.now().toIso8601String()})
          .eq('tenant_id', tenantId)
          .eq('key', _companyLogoKey);

      if (_authorityScope.owns(lease)) {
        _companyLogoUrl = null;
        _notify();
      }
    } catch (e) {
      debugPrint('[AppearanceService] Error removing logo: $e');
      rethrow;
    }
  }

  /// Set theme mode (light, dark, or system)
  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      final scope = _preferenceMutationScope();
      _themeMode = mode;
      _markPreferenceChanged(_AppearancePreferenceField.themeMode);
      _notify();
      if (scope != null) {
        await _persistPreferences(scope, _currentPreferences);
      }
    } catch (e) {
      debugPrint('[AppearanceService] Error saving theme mode: $e');
      rethrow;
    }
  }

  Future<void> setSidebarPalette(String paletteCode) async {
    if (!sidebarPalettes.any((palette) => palette.code == paletteCode)) return;

    try {
      final scope = _preferenceMutationScope();
      _sidebarPaletteCode = paletteCode;
      _markPreferenceChanged(_AppearancePreferenceField.sidebarPalette);
      _notify();
      if (scope != null) {
        await _persistPreferences(scope, _currentPreferences);
      }
    } catch (e) {
      debugPrint('[AppearanceService] Error saving sidebar palette: $e');
      rethrow;
    }
  }

  Future<void> setMessagingUsesSidebarPalette(bool value) async {
    try {
      final scope = _preferenceMutationScope();
      _messagingUsesSidebarPalette = value;
      _markPreferenceChanged(
        _AppearancePreferenceField.messagingSidebarPalette,
      );
      _notify();
      if (scope != null) {
        await _persistPreferences(scope, _currentPreferences);
      }
    } catch (e) {
      debugPrint(
          '[AppearanceService] Error saving messaging palette setting: $e');
      rethrow;
    }
  }

  Future<void> setQuickChatUsesSidebarPalette(bool value) {
    return setMessagingUsesSidebarPalette(value);
  }

  Future<void> setRightToolbarOverContent(bool value) async {
    try {
      final scope = _preferenceMutationScope();
      _rightToolbarOverContent = value;
      _markPreferenceChanged(
        _AppearancePreferenceField.rightToolbarOverContent,
      );
      _notify();
      if (scope != null) {
        await _persistPreferences(scope, _currentPreferences);
      }
    } catch (e) {
      debugPrint('[AppearanceService] Error saving toolbar layout: $e');
      rethrow;
    }
  }

  Future<void> setRightToolbarBlurEnabled(bool value) async {
    try {
      final scope = _preferenceMutationScope();
      _rightToolbarBlurEnabled = value;
      _markPreferenceChanged(
        _AppearancePreferenceField.rightToolbarBlurEnabled,
      );
      _notify();
      if (scope != null) {
        await _persistPreferences(scope, _currentPreferences);
      }
    } catch (e) {
      debugPrint('[AppearanceService] Error saving toolbar blur setting: $e');
      rethrow;
    }
  }
}

enum _AppearancePreferenceField {
  themeMode,
  sidebarPalette,
  messagingSidebarPalette,
  rightToolbarOverContent,
  rightToolbarBlurEnabled,
}

ThemeData buildSidebarPaletteTheme(
  ThemeData baseTheme,
  SidebarPaletteOption palette,
) {
  return WorkspaceChromeTheme.sidebarTheme(
    baseTheme,
    WorkspaceChromeStyleData(
      canvas: palette.background,
      raised: palette.backgroundAlt,
      edge: palette.border,
      foreground: palette.foreground,
      mutedForeground: palette.mutedForeground,
      accent: palette.accent,
      onAccent: palette.onAccent,
      dirty: const Color(0xFFF5B545),
      attention: const Color(0xFFF2637A),
    ),
  );
}

BoxDecoration buildSidebarPaletteDecoration(SidebarPaletteOption palette) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        palette.background,
        Color.alphaBlend(
          palette.accent.withValues(alpha: 0.08),
          palette.backgroundAlt,
        ),
      ],
    ),
  );
}

@immutable
class _AppearancePreferences {
  const _AppearancePreferences({
    required this.themeMode,
    required this.sidebarPaletteCode,
    required this.messagingUsesSidebarPalette,
    required this.rightToolbarOverContent,
    required this.rightToolbarBlurEnabled,
  });

  const _AppearancePreferences.defaults()
      : themeMode = ThemeMode.light,
        sidebarPaletteCode = 'vinabike',
        messagingUsesSidebarPalette = false,
        rightToolbarOverContent = true,
        rightToolbarBlurEnabled = true;

  static const int version = 2;

  final ThemeMode themeMode;
  final String sidebarPaletteCode;
  final bool messagingUsesSidebarPalette;
  final bool rightToolbarOverContent;
  final bool rightToolbarBlurEnabled;

  String encode(ErpAuthorityScopeKey scope) {
    return jsonEncode({
      'version': version,
      'tenant_id': scope.tenantId,
      'user_id': scope.userId,
      'theme_mode': themeMode.name,
      'sidebar_palette': sidebarPaletteCode,
      'quick_chat_uses_sidebar_palette': messagingUsesSidebarPalette,
      'right_toolbar_over_content': rightToolbarOverContent,
      'right_toolbar_blur_enabled': rightToolbarBlurEnabled,
    });
  }

  static _AppearancePreferences? tryDecode(
    String raw, {
    required ErpAuthorityScopeKey expectedScope,
    required List<SidebarPaletteOption> supportedPalettes,
  }) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != version ||
          decoded['tenant_id'] != expectedScope.tenantId ||
          decoded['user_id'] != expectedScope.userId) {
        return null;
      }

      final themeModeValue = decoded['theme_mode'];
      final themeMode = themeModeValue is String
          ? ThemeMode.values.firstWhere(
              (mode) => mode.name == themeModeValue,
              orElse: () => ThemeMode.light,
            )
          : ThemeMode.light;
      final paletteValue = decoded['sidebar_palette'];
      final paletteCode = paletteValue is String &&
              supportedPalettes.any(
                (palette) => palette.code == paletteValue,
              )
          ? paletteValue
          : 'vinabike';

      return _AppearancePreferences(
        themeMode: themeMode,
        sidebarPaletteCode: paletteCode,
        messagingUsesSidebarPalette:
            decoded['quick_chat_uses_sidebar_palette'] is bool
                ? decoded['quick_chat_uses_sidebar_palette'] as bool
                : false,
        rightToolbarOverContent: decoded['right_toolbar_over_content'] is bool
            ? decoded['right_toolbar_over_content'] as bool
            : true,
        rightToolbarBlurEnabled: decoded['right_toolbar_blur_enabled'] is bool
            ? decoded['right_toolbar_blur_enabled'] as bool
            : true,
      );
    } catch (_) {
      return null;
    }
  }
}

class HomeIconOption {
  final IconData icon;
  final String name;
  final String code;

  const HomeIconOption({
    required this.icon,
    required this.name,
    required this.code,
  });
}
