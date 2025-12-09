import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/constants/storage_constants.dart';

class AppearanceService extends ChangeNotifier {
  static const String _homeIconKey = 'home_icon';
  static const String _companyLogoKey = 'company_logo';
  static const String _themeModeKey = 'theme_mode';

  IconData _homeIcon = Icons.pedal_bike;
  String? _companyLogoUrl;
  bool _isInitialized = false;
  bool _hasLoadedWithTenant = false; // True only if settings were loaded with valid tenant
  int _cacheBuster = DateTime.now().millisecondsSinceEpoch;
  ThemeMode _themeMode = ThemeMode.light;
  StreamSubscription<AuthState>? _authSubscription;

  final _supabase = Supabase.instance.client;

  AppearanceService() {
    _loadSettings();
    _listenToAuthChanges();
  }
  
  /// Listen to auth state changes and reload settings when user logs in
  void _listenToAuthChanges() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && !_hasLoadedWithTenant) {
        _loadSettings();
      } else if (data.event == AuthChangeEvent.signedOut) {
        // Reset state on logout
        _companyLogoUrl = null;
        _homeIcon = Icons.pedal_bike;
        _hasLoadedWithTenant = false;
        notifyListeners();
      }
    });
  }
  
  @override
  void dispose() {
    _authSubscription?.cancel();
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
  bool get hasLoadedWithTenant => _hasLoadedWithTenant;
  bool get hasCustomLogo =>
      _companyLogoUrl != null && _companyLogoUrl!.isNotEmpty;
  ThemeMode get themeMode => _themeMode;

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

  Future<void> _loadSettings() async {
    try {
      // Load theme mode from SharedPreferences (local, per-device)
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString(_themeModeKey);
      if (themeModeString != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.name == themeModeString,
          orElse: () => ThemeMode.light,
        );
      }

      // Get tenant_id for loading settings
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        _isInitialized = true;
        _hasLoadedWithTenant = false; // Mark that we didn't load with tenant
        notifyListeners();
        return;
      }

      // Load settings from Supabase database (global, synced across devices)
      final response = await _supabase
          .from('company_settings')
          .select('key, value')
          .eq('tenant_id', tenantId)
          .inFilter('key', [_homeIconKey, _companyLogoKey]);

      for (final row in response) {
        final key = row['key'] as String;
        final value = row['value'] as String?;

        if (key == _homeIconKey && value != null) {
          final option = availableIcons.firstWhere(
            (opt) => opt.code == value,
            orElse: () => availableIcons.first,
          );
          _homeIcon = option.icon;
        } else if (key == _companyLogoKey && value != null) {
          // Strip any existing cache-buster from stored URL
          _companyLogoUrl = value.split('?').first;
        }
      }

      _isInitialized = true;
      _hasLoadedWithTenant = true; // Successfully loaded with tenant
      debugPrint('[AppearanceService] Settings loaded. hasCustomLogo=$hasCustomLogo, logoUrl=$_companyLogoUrl');
      notifyListeners();
    } catch (e) {
      debugPrint('[AppearanceService] Error loading settings: $e');
      _isInitialized = true;
      _hasLoadedWithTenant = false;
      notifyListeners();
    }
  }

  /// Refresh the logo with a new cache-buster to force reload
  void refreshLogo() {
    _cacheBuster = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// Reload settings from database (call after authentication)
  Future<void> reloadSettings() async {
    debugPrint('[AppearanceService] reloadSettings() called');
    await _loadSettings();
  }

  Future<void> setHomeIcon(IconData icon, String iconCode) async {
    try {
      // Get tenant_id
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant found');
      }

      // Check if setting exists
      final existing = await _supabase
          .from('company_settings')
          .select('id')
          .eq('tenant_id', tenantId)
          .eq('key', _homeIconKey)
          .maybeSingle();

      if (existing != null) {
        // Update existing record
        await _supabase.from('company_settings').update({
          'value': iconCode,
          'updated_at': DateTime.now().toIso8601String()
        }).eq('tenant_id', tenantId).eq('key', _homeIconKey);
      } else {
        // Insert new record
        await _supabase.from('company_settings').insert({
          'tenant_id': tenantId,
          'key': _homeIconKey,
          'value': iconCode,
          'updated_at': DateTime.now().toIso8601String()
        });
      }

      _homeIcon = icon;
      notifyListeners();
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
      
      // Get tenant_id
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant found');
      }
      
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
        // Check if setting exists
        debugPrint('[AppearanceService] Checking existing settings...');
        final existing = await _supabase
            .from('company_settings')
            .select('id')
            .eq('tenant_id', tenantId)
            .eq('key', _companyLogoKey)
            .maybeSingle();

        debugPrint('[AppearanceService] Existing record: ${existing != null ? "found" : "not found"}');

        if (existing != null) {
          // Update existing record
          debugPrint('[AppearanceService] Updating existing record...');
          await _supabase.from('company_settings').update({
            'value': imageUrl,
            'updated_at': DateTime.now().toIso8601String()
          }).eq('tenant_id', tenantId).eq('key', _companyLogoKey);
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

        _companyLogoUrl = imageUrl;
        // Update cache-buster to force reload on all devices
        _cacheBuster = DateTime.now().millisecondsSinceEpoch;
        
        debugPrint('[AppearanceService] Logo URL set to: $_companyLogoUrl');
        debugPrint('[AppearanceService] Cache buster: $_cacheBuster');
        debugPrint('[AppearanceService] Notifying listeners...');
        
        notifyListeners();
        
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
      // Get tenant_id
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant found');
      }

      // Remove from Supabase database (synced across devices)
      await _supabase.from('company_settings').update({
        'value': null,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('tenant_id', tenantId).eq('key', _companyLogoKey);

      _companyLogoUrl = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[AppearanceService] Error removing logo: $e');
      rethrow;
    }
  }

  /// Set theme mode (light, dark, or system)
  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.name);
      _themeMode = mode;
      notifyListeners();
    } catch (e) {
      debugPrint('[AppearanceService] Error saving theme mode: $e');
      rethrow;
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
