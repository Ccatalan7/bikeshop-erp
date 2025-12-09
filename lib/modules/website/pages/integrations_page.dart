import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';

/// Integrations configuration page for Google Merchant, Analytics, etc.
class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  bool _isLoading = false;
  final String _subdomain = 'vinabike';
  final String _gaTrackingId = 'G-FR5Q37BW43';
  int _gmcProductCount = 0;

  String get _feedUrl {
    const supabaseUrl = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1';
    return '$supabaseUrl/google-merchant-feed?tenant=$_subdomain';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MainLayout(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/website'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Integraciones',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Conecta tu tienda con Google y otras plataformas',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGoogleMerchantSection(theme),
                        const SizedBox(height: 24),
                        _buildGoogleAnalyticsSection(theme),
                        const SizedBox(height: 24),
                        _buildComingSoonSection(theme),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleMerchantSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shopping_bag, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Merchant Center', 
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Feed de productos para Google Shopping',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 6),
                      Text('Feed Activo', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
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
                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _feedUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('URL copiada al portapapeles')),
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
                      _buildStep('6', 'Configura la frecuencia de actualización'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse('https://merchants.google.com')),
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
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.analytics, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Analytics', 
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Tracking de visitas y conversiones',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('https://analytics.google.com')),
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.rocket_launch, color: Colors.purple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Próximamente', 
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Más integraciones en desarrollo',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                _buildComingSoonChip('Facebook Pixel'),
                _buildComingSoonChip('Meta Catalog'),
                _buildComingSoonChip('Google Ads'),
                _buildComingSoonChip('Mailchimp'),
                _buildComingSoonChip('WhatsApp Business'),
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
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildComingSoonChip(String label) {
    return Chip(
      avatar: const Icon(Icons.schedule, size: 16),
      label: Text(label),
      backgroundColor: Colors.grey.withOpacity(0.1),
    );
  }
}
