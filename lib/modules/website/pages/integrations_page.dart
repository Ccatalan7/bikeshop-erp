import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/google_business_service.dart';
import '../services/website_service.dart';
import '../widgets/website_admin_ui.dart';

/// Integrations configuration page for Google Merchant, Analytics, etc.
class IntegrationsPage extends StatefulWidget {
  final bool embedded;

  const IntegrationsPage({super.key, this.embedded = false});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  final bool _isLoading = false;
  final String _subdomain = 'vinabike';
  final String _gaTrackingId = 'G-FR5Q37BW43';
  final int _gmcProductCount = 0;

  bool _attemptedProviderTokenEnsure = false;

  // Google Business Profile
  late final WebsiteService _websiteService;

  @override
  void initState() {
    super.initState();
    _websiteService = WebsiteService();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _websiteService.loadSettings();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _websiteService.dispose();
    super.dispose();
  }

  String get _feedUrl {
    const supabaseUrl = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1';
    return '$supabaseUrl/google-merchant-feed?tenant=$_subdomain';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final googleBusinessService = context.watch<GoogleBusinessService>();

    // After returning from OAuth, some browsers will have the new session
    // persisted but not yet surfaced to the running app state. A one-time
    // refresh here avoids the need for a manual hard refresh.
    if (!_attemptedProviderTokenEnsure &&
        googleBusinessService.isLinked &&
        !googleBusinessService.hasProviderToken) {
      _attemptedProviderTokenEnsure = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        googleBusinessService.ensureProviderToken(
            timeout: const Duration(seconds: 3));
      });
    }

    return WebsiteAdminShell(
      embedded: widget.embedded,
      title: 'Integraciones',
      description: 'Conecta publicación, medición y presencia local.',
      child: _isLoading
          ? const Center(child: BrandedLoading())
          : WebsiteAdminBody(
              maxWidth: 1120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGoogleBusinessProfileSection(theme),
                  const SizedBox(height: 16),
                  _buildGoogleMerchantSection(theme),
                  const SizedBox(height: 16),
                  _buildGoogleAnalyticsSection(theme),
                  const SizedBox(height: 16),
                  _buildComingSoonSection(theme),
                ],
              ),
            ),
    );
  }

  // ==========================================================================
  // GOOGLE BUSINESS PROFILE SECTION
  // ==========================================================================
  Widget _buildGoogleBusinessProfileSection(ThemeData theme) {
    final svc = context.watch<GoogleBusinessService>();
    final hasToken = svc.hasProviderToken;
    final isLinked = svc.isLinked;
    final hasSavedGoogleBusinessData =
        _hasSavedGoogleBusinessData(_websiteService);
    final isConnected = hasToken || hasSavedGoogleBusinessData;
    final error = svc.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                _buildIntegrationIcon(
                  Icons.business_outlined,
                  const Color(0xFF4285F4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Business Profile',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                          'Sincroniza dirección, horario y reseñas de tu negocio',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                // Status badge
                if (isConnected)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 4),
                        Text('Conectado',
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                else if (isLinked)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.orange, size: 16),
                        SizedBox(width: 4),
                        Text('Autorizar',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 32),

            // Error display
            if (error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(error,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => svc.clearError(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Connection status and actions
            if (isConnected) ...[
              // Connected - show sync actions
              Text('Acciones disponibles',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _syncBusinessData,
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Sincronizar Datos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _syncReviews,
                    icon: const Icon(Icons.reviews, size: 18),
                    label: const Text('Sincronizar Reseñas'),
                  ),
                  TextButton.icon(
                    onPressed: () => svc.connect(
                editorCapability: context
                    .read<WebsiteEditModeProvider>()
                    .editorEntryLease,
              ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(hasToken ? 'Reconectar' : 'Renovar acceso'),
                  ),
                ],
              ),
              if (!hasToken) ...[
                const SizedBox(height: 12),
                Text(
                  'Los datos del negocio siguen guardados. Para volver a consultar Google en vivo, renueva el permiso.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else ...[
              // Not connected - show connect button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Conecta tu cuenta de Google para sincronizar:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    _buildBulletPoint('Dirección y datos de contacto'),
                    _buildBulletPoint('Horarios de atención'),
                    _buildBulletPoint('Reseñas de clientes'),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: svc.isLoading ? null : () => svc.connect(
                editorCapability: context
                    .read<WebsiteEditModeProvider>()
                    .editorEntryLease,
              ),
                        icon: svc.isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.login),
                        label: Text(svc.isLoading
                            ? 'Conectando...'
                            : isLinked
                                ? 'Autorizar Acceso'
                                : 'Conectar con Google'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Help text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Si ves "Acceso bloqueado (403)", necesitas agregar tu correo como "Test user" en Google Cloud Console → OAuth consent screen.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.check, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _syncBusinessData() async {
    try {
      final googleService = context.read<GoogleBusinessService>();
      final hasAccess = await _ensureGoogleApiAccess(googleService);
      if (!hasAccess) return;

      final locations = await googleService.fetchLocations();
      if (!mounted) return;

      if (locations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron ubicaciones')),
        );
        return;
      }

      // Show location selection dialog
      final selected = await showDialog<GoogleLocation>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Seleccionar Ubicación'),
          content: SizedBox(
            width: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: locations.length,
              itemBuilder: (context, index) {
                final loc = locations[index];
                return ListTile(
                  title: Text(loc.title),
                  subtitle: Text(loc.addressLine ?? ''),
                  onTap: () => Navigator.pop(ctx, loc),
                );
              },
            ),
          ),
        ),
      );

      if (selected != null && mounted) {
        final settings = <String, String>{
          'business_name': selected.title,
          'business_google_location_id': selected.name,
        };
        if (selected.phone != null) {
          settings['business_phone'] = selected.phone!;
          settings['contact_phone'] = selected.phone!;
          settings['seo_phone'] = selected.phone!;
        }
        if (selected.addressLine != null) {
          settings['contact_address'] = selected.addressLine!;
        }
        if (selected.addressStreet != null) {
          settings['seo_address_street'] = selected.addressStreet!;
        }
        if (selected.addressCity != null) {
          settings['seo_address_city'] = selected.addressCity!;
        }
        if (selected.addressRegion != null) {
          settings['seo_address_region'] = selected.addressRegion!;
        }
        if (selected.addressPostalCode != null) {
          settings['seo_address_postal'] = selected.addressPostalCode!;
        }
        if (selected.addressCountry != null) {
          settings['seo_address_country'] = selected.addressCountry!;
        }
        if (selected.hours != null && selected.hours!.isNotEmpty) {
          settings['google_business_regular_hours'] =
              jsonEncode(selected.hours);
        }
        final mapsUrl = selected.mapsUri;
        if (mapsUrl != null && mapsUrl.trim().isNotEmpty) {
          settings['business_google_maps_url'] = mapsUrl.trim();
          settings['seo_google_maps_url'] = mapsUrl.trim();
        }
        final reviewUrl = selected.newReviewUri;
        if (reviewUrl != null && reviewUrl.trim().isNotEmpty) {
          settings['business_google_review_url'] = reviewUrl.trim();
        }

        await _websiteService.saveSettings(settings);
        if (mounted) setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Datos sincronizados correctamente!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _syncReviews() async {
    try {
      final googleService = context.read<GoogleBusinessService>();
      final hasAccess = await _ensureGoogleApiAccess(googleService);
      if (!hasAccess) return;
      if (!mounted) return;

      final locationName =
          _websiteService.getSetting('business_google_location_id');
      if (locationName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Primero sincroniza los datos del negocio para obtener la ubicación.')),
        );
        return;
      }

      final reviews = await googleService.fetchReviews(locationName);
      if (!mounted) return;

      if (reviews.isNotEmpty) {
        await _websiteService.saveSetting(
            'google_reviews_data', jsonEncode(reviews));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Se descargaron ${reviews.length} reseñas correctamente!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No se encontraron reseñas para esta ubicación.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _hasSavedGoogleBusinessData(WebsiteService websiteService) {
    const keys = [
      'business_google_location_id',
      'google_maps_place_id',
      'google_business_regular_hours',
      'business_hours_json',
      'business_google_maps_url',
      'seo_google_maps_url',
      'business_google_review_url',
      'google_reviews_data',
    ];

    return keys.any((key) => websiteService.getSetting(key).trim().isNotEmpty);
  }

  Future<bool> _ensureGoogleApiAccess(
    GoogleBusinessService googleService,
  ) async {
    if (googleService.hasProviderToken) return true;

    if (googleService.isLinked) {
      final restored = await googleService.ensureProviderToken(
        timeout: const Duration(seconds: 3),
      );
      if (restored) return true;
    }

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Los datos guardados siguen conectados. Para refrescarlos desde Google, renueva el permiso.',
        ),
      ),
    );
    await googleService.connect(
      editorCapability:
          context.read<WebsiteEditModeProvider>().editorEntryLease,
    );
    return false;
  }

  // ==========================================================================
  // GOOGLE MERCHANT CENTER SECTION
  // ==========================================================================
  Widget _buildGoogleMerchantSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildIntegrationIcon(
                  Icons.shopping_bag_outlined,
                  const Color(0xFF19A974),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Merchant Center',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Feed de productos para Google Shopping',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 6),
                      Text('Feed Activo',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text('$_gmcProductCount productos en el feed',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 16),
            Text('URL del Feed:', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _feedUrl,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _feedUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('URL copiada al portapapeles')),
                      );
                    },
                    tooltip: 'Copiar URL',
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 20),
                    onPressed: () => launchUrl(Uri.parse(_feedUrl)),
                    tooltip: 'Abrir feed',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('Instrucciones de configuración'),
              tilePadding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStep('1', 'Accede a Google Merchant Center'),
                      _buildStep('2', 'Ve a Productos → Feeds'),
                      _buildStep('3', 'Haz clic en "Agregar feed"'),
                      _buildStep('4', 'Selecciona "Fetch programado" o "URL"'),
                      _buildStep('5', 'Pega la URL del feed de arriba'),
                      _buildStep(
                          '6', 'Configura la frecuencia de actualización'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                            Uri.parse('https://merchants.google.com')),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Ir a Google Merchant Center'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Para controlar qué productos aparecen en Google Shopping, activa el toggle "Google Merchant" en cada producto.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleAnalyticsSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildIntegrationIcon(
                  Icons.analytics_outlined,
                  const Color(0xFF7C4DFF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Analytics',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Tracking de visitas y conversiones',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Text(
              'El código de seguimiento GA4 ya está instalado en tu tienda.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Text(
                    'Measurement ID: $_gaTrackingId',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  launchUrl(Uri.parse('https://analytics.google.com')),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ver Google Analytics'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComingSoonSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildIntegrationIcon(
                  Icons.rocket_launch_outlined,
                  const Color(0xFFF28C28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Próximamente',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Más integraciones en desarrollo',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildComingSoonItem('Facebook Pixel'),
                _buildComingSoonItem('Meta Catalog'),
                _buildComingSoonItem('Google Ads'),
                _buildComingSoonItem('Mailchimp'),
                _buildComingSoonItem('WhatsApp Business'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildIntegrationIcon(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  Widget _buildComingSoonItem(String label) {
    return SizedBox(
      width: 160,
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFF28C28),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
