import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/constants/storage_constants.dart';

class AppearanceService extends ChangeNotifier {
  static const String _homeIconKey = 'home_icon';
  static const String _companyLogoKey = 'company_logo';

  IconData _homeIcon = Icons.pedal_bike;
  String? _companyLogoUrl;
  bool _isInitialized = false;
  int _cacheBuster = DateTime.now().millisecondsSinceEpoch;

  final _supabase = Supabase.instance.client;

  AppearanceService() {
    _loadSettings();
  }

  IconData get homeIcon => _homeIcon;
  String? get companyLogoUrl {
    if (_companyLogoUrl == null) return null;
    // Always add/update the cache-busting parameter when accessing the URL
    final baseUrl = _companyLogoUrl!.split('?').first;
    return '$baseUrl?v=$_cacheBuster';
  }

  bool get isInitialized => _isInitialized;
  bool get hasCustomLogo =>
      _companyLogoUrl != null && _companyLogoUrl!.isNotEmpty;

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
      // Load settings from Supabase database (global, synced across devices)
      final response = await _supabase
          .from('company_settings')
          .select('key, value')
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
      notifyListeners();
    } catch (e) {
      debugPrint('[AppearanceService] Error loading settings: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Refresh the logo with a new cache-buster to force reload
  void refreshLogo() {
    _cacheBuster = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  Future<void> setHomeIcon(IconData icon, String iconCode) async {
    try {
      // Save to Supabase database (synced across devices)
      await _supabase.from('company_settings').upsert(
        {
          'key': _homeIconKey,
          'value': iconCode,
          'updated_at': DateTime.now().toIso8601String()
        },
        onConflict: 'key',
      );

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
      // Upload to Supabase storage
      final imageUrl = await ImageService.uploadBytes(
        bytes: imageBytes,
        fileName: fileName,
        bucket: StorageConfig.defaultBucket,
        folder: 'company_logos',
      );

      if (imageUrl != null) {
        // Save to Supabase database (synced across devices)
        // Don't add cache-buster to stored URL - we add it dynamically in the getter
        await _supabase.from('company_settings').upsert(
          {
            'key': _companyLogoKey,
            'value': imageUrl,
            'updated_at': DateTime.now().toIso8601String()
          },
          onConflict: 'key',
        );

        _companyLogoUrl = imageUrl;
        // Update cache-buster to force reload on all devices
        _cacheBuster = DateTime.now().millisecondsSinceEpoch;
        notifyListeners();
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
      // Remove from Supabase database (synced across devices)
      await _supabase.from('company_settings').update({
        'value': null,
        'updated_at': DateTime.now().toIso8601String()
      }).eq('key', _companyLogoKey);

      _companyLogoUrl = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[AppearanceService] Error removing logo: $e');
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
