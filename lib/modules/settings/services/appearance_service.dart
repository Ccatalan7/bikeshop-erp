import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cross_file/cross_file.dart';
import '../../../shared/services/image_service.dart';

class AppearanceService extends ChangeNotifier {
  static const String _homeIconKey = 'appearance_home_icon';
  static const String _companyLogoKey = 'appearance_company_logo';
  
  IconData _homeIcon = Icons.pedal_bike;
  String? _companyLogoUrl;
  bool _isInitialized = false;

  IconData get homeIcon => _homeIcon;
  String? get companyLogoUrl => _companyLogoUrl;
  bool get isInitialized => _isInitialized;
  bool get hasCustomLogo => _companyLogoUrl != null && _companyLogoUrl!.isNotEmpty;

  // Available home icons for selection
  static const List<HomeIconOption> availableIcons = [
    HomeIconOption(icon: Icons.pedal_bike, name: 'Bicicleta', code: 'pedal_bike'),
    HomeIconOption(icon: Icons.directions_bike, name: 'Bicicleta (alt)', code: 'directions_bike'),
    HomeIconOption(icon: Icons.two_wheeler, name: 'Motocicleta', code: 'two_wheeler'),
    HomeIconOption(icon: Icons.store, name: 'Tienda', code: 'store'),
    HomeIconOption(icon: Icons.business, name: 'Negocio', code: 'business'),
    HomeIconOption(icon: Icons.storefront, name: 'Tienda (alt)', code: 'storefront'),
    HomeIconOption(icon: Icons.home, name: 'Casa', code: 'home'),
    HomeIconOption(icon: Icons.home_work, name: 'Casa/Trabajo', code: 'home_work'),
    HomeIconOption(icon: Icons.apartment, name: 'Edificio', code: 'apartment'),
    HomeIconOption(icon: Icons.account_balance, name: 'Banco', code: 'account_balance'),
    HomeIconOption(icon: Icons.shopping_bag, name: 'Bolsa de compras', code: 'shopping_bag'),
    HomeIconOption(icon: Icons.shopping_cart, name: 'Carrito', code: 'shopping_cart'),
    HomeIconOption(icon: Icons.local_shipping, name: 'Envío', code: 'local_shipping'),
    HomeIconOption(icon: Icons.build, name: 'Herramientas', code: 'build'),
    HomeIconOption(icon: Icons.handyman, name: 'Taller', code: 'handyman'),
    HomeIconOption(icon: Icons.construction, name: 'Construcción', code: 'construction'),
    HomeIconOption(icon: Icons.sports, name: 'Deportes', code: 'sports'),
    HomeIconOption(icon: Icons.fitness_center, name: 'Gimnasio', code: 'fitness_center'),
    HomeIconOption(icon: Icons.star, name: 'Estrella', code: 'star'),
    HomeIconOption(icon: Icons.favorite, name: 'Corazón', code: 'favorite'),
  ];

  AppearanceService() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load icon
      final iconCode = prefs.getString(_homeIconKey);
      if (iconCode != null) {
        final option = availableIcons.firstWhere(
          (opt) => opt.code == iconCode,
          orElse: () => availableIcons.first,
        );
        _homeIcon = option.icon;
      }
      
      // Load company logo
      _companyLogoUrl = prefs.getString(_companyLogoKey);
      
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[AppearanceService] Error loading settings: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setHomeIcon(IconData icon, String iconCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_homeIconKey, iconCode);
      
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

  Future<void> uploadCompanyLogo(XFile imageFile) async {
    try {
      // Upload to Supabase storage
      final imageUrl = await ImageService.uploadToDefaultBucket(
        imageFile,
        'company_logos',
      );

      if (imageUrl != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_companyLogoKey, imageUrl);
        
        _companyLogoUrl = imageUrl;
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_companyLogoKey);
      
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
