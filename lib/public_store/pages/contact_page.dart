import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../modules/website/services/website_service.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../theme/public_store_theme.dart';
import '../../shared/widgets/safe_layout_builder.dart';

/// Modern contact page that reads all data from website_settings
/// Fully editable through the Website Editor
class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _BusinessHourRowData {
  const _BusinessHourRowData({
    required this.dayLabel,
    required this.hoursLabel,
    required this.isOpen,
  });

  final String dayLabel;
  final String hoursLabel;
  final bool isOpen;
}

class _ContactPageState extends State<ContactPage>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSending = false;

  // DISABLED: AutomaticKeepAliveClientMixin causes element activation conflicts
  // during edit/preview mode switches. The performance cost of reloading is acceptable.
  @override
  bool get wantKeepAlive => false;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  String _sanitizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  Future<void> _submitForm(String email) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      final subject = Uri.encodeComponent('Contacto desde sitio web');
      final body = Uri.encodeComponent(
        'Nombre: ${_nameController.text}\n'
        'Email: ${_emailController.text}\n'
        'Teléfono: ${_phoneController.text}\n\n'
        'Mensaje:\n${_messageController.text}',
      );

      await _launchUrl('mailto:$email?subject=$subject&body=$body');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abriendo cliente de correo...'),
            backgroundColor: Colors.green,
          ),
        );
        // Clear form
        _nameController.clear();
        _emailController.clear();
        _phoneController.clear();
        _messageController.clear();
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    debugPrint('📞 [ContactPage] dispose() called');
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Debug: build
    final websiteService = context.watch<WebsiteService>();

    // Get edit mode for key to prevent element reactivation conflicts
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final modeKey = editProvider.isEditMode
        ? 'edit'
        : (editProvider.isPreviewMode ? 'preview' : 'normal');

    // Get all contact info from website_settings (editable in admin)
    final storeName = websiteService.getSetting('store_name', 'Viñabike');
    final contactEmail =
        websiteService.getSetting('contact_email', 'contacto@vinabike.cl');
    final contactPhone =
        websiteService.getSetting('contact_phone', '+56 9 9835 7797');
    final contactAddress = websiteService.getSetting(
        'contact_address', 'Álvarez 32, Local 17\nViña del Mar, Chile');
    final whatsappRaw = websiteService.getSetting('whatsapp', '+56998357797');
    final whatsappNumber = _sanitizePhone(whatsappRaw);
    final instagramHandle = websiteService.getSetting('instagram', '');
    final facebookHandle = websiteService.getSetting('facebook', '');
    final businessHoursJson = _firstNonEmptySetting(
      websiteService,
      const ['business_hours_json', 'google_business_regular_hours'],
    );
    final configuredGoogleMapsUrl = _firstNonEmptySetting(
      websiteService,
      const [
        'seo_google_maps_url',
        'business_google_maps_url',
        'google_maps_url'
      ],
    );
    final googleMapsUrl = configuredGoogleMapsUrl.isNotEmpty
        ? configuredGoogleMapsUrl
        : _buildMapsSearchUrl(storeName, contactAddress);

    // Theme colors
    final primaryColorStr =
        websiteService.getSetting('theme_primary_color', '');
    final primaryColor =
        _parseColor(primaryColorStr) ?? PublicStoreTheme.primaryBlue;

    return Column(
      children: [
        // Hero Section - Clean and minimal
        _buildHeroSection(primaryColor),

        // Main Content
        Container(
          width: double.infinity,
          color: Colors.grey.shade50,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
              child: Column(
                children: [
                  // Two column layout: Form + Info
                  MediaQueryLayoutBuilder(
                    key: ValueKey('contact_form_layout_$modeKey'),
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 900;

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Contact Form
                            Expanded(
                              flex: 3,
                              child: _buildContactForm(
                                  contactEmail, primaryColor, modeKey),
                            ),
                            const SizedBox(width: 48),
                            // Info Panel
                            Expanded(
                              flex: 2,
                              child: _buildInfoPanel(
                                storeName: storeName,
                                contactAddress: contactAddress,
                                contactPhone: contactPhone,
                                contactEmail: contactEmail,
                                whatsappNumber: whatsappNumber,
                                instagramHandle: instagramHandle,
                                facebookHandle: facebookHandle,
                                businessHoursJson: businessHoursJson,
                                googleMapsUrl: googleMapsUrl,
                                primaryColor: primaryColor,
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _buildInfoPanel(
                            storeName: storeName,
                            contactAddress: contactAddress,
                            contactPhone: contactPhone,
                            contactEmail: contactEmail,
                            whatsappNumber: whatsappNumber,
                            instagramHandle: instagramHandle,
                            facebookHandle: facebookHandle,
                            businessHoursJson: businessHoursJson,
                            googleMapsUrl: googleMapsUrl,
                            primaryColor: primaryColor,
                          ),
                          const SizedBox(height: 48),
                          _buildContactForm(
                              contactEmail, primaryColor, modeKey),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _firstNonEmptySetting(WebsiteService service, List<String> keys) {
    for (final key in keys) {
      final value = service.getSetting(key, '').trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _buildMapsSearchUrl(String storeName, String contactAddress) {
    final query = [storeName, contactAddress.replaceAll('\n', ' ')]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' ');

    if (query.isEmpty) return '';
    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
  }

  Widget _buildHeroSection(Color primaryColor) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: const Column(
            children: [
              Text(
                'Contáctanos',
                style: TextStyle(
                  fontFamily: null,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  color: PublicStoreTheme.textPrimary,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Estamos aquí para ayudarte. Escríbenos y te responderemos lo antes posible.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: PublicStoreTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactForm(
      String contactEmail, Color primaryColor, String modeKey) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PublicStoreTheme.divider),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Envíanos un mensaje',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: PublicStoreTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Completa el formulario y nos contactaremos a la brevedad.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: PublicStoreTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 36),

            // Name Field
            _buildTextField(
              controller: _nameController,
              label: 'Nombre completo',
              hint: 'Tu nombre',
              icon: Icons.person_outline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Por favor ingresa tu nombre';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Email & Phone Row
            MediaQueryLayoutBuilder(
              key: ValueKey('contact_email_phone_layout_$modeKey'),
              builder: (context, constraints) {
                if (constraints.maxWidth > 500) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _emailController,
                          label: 'Email',
                          hint: 'tu@email.com',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Por favor ingresa tu email';
                            }
                            if (!value.contains('@')) {
                              return 'Email inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextField(
                          controller: _phoneController,
                          label: 'Teléfono (opcional)',
                          hint: '+56 9 1234 5678',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'tu@email.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Por favor ingresa tu email';
                        }
                        if (!value.contains('@')) {
                          return 'Email inválido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Teléfono (opcional)',
                      hint: '+56 9 1234 5678',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Message Field
            _buildTextField(
              controller: _messageController,
              label: 'Mensaje',
              hint: '¿En qué podemos ayudarte?',
              icon: Icons.message_outlined,
              maxLines: 5,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Por favor ingresa tu mensaje';
                }
                if (value.trim().length < 10) {
                  return 'El mensaje debe tener al menos 10 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _isSending ? null : () => _submitForm(contactEmail),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Enviar mensaje',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.send, size: 18),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        labelStyle: const TextStyle(color: PublicStoreTheme.textSecondary),
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: PublicStoreTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: PublicStoreTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: PublicStoreTheme.primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
      ),
    );
  }

  Widget _buildInfoPanel({
    required String storeName,
    required String contactAddress,
    required String contactPhone,
    required String contactEmail,
    required String whatsappNumber,
    required String instagramHandle,
    required String facebookHandle,
    required String businessHoursJson,
    required String googleMapsUrl,
    required Color primaryColor,
  }) {
    final businessHourRows = _parseBusinessHours(businessHoursJson);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contact Details Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: PublicStoreTheme.divider),
                    ),
                    child: const Icon(Icons.location_on_outlined,
                        color: PublicStoreTheme.textPrimary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Información de Contacto',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: PublicStoreTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildContactDetailRow(
                  Icons.map_outlined, 'Dirección', contactAddress),
              if (contactPhone.isNotEmpty) const SizedBox(height: 16),
              if (contactPhone.isNotEmpty)
                _buildContactDetailRow(
                    Icons.phone_outlined, 'Teléfono', contactPhone),
              if (contactEmail.isNotEmpty) const SizedBox(height: 16),
              if (contactEmail.isNotEmpty)
                _buildContactDetailRow(
                    Icons.email_outlined, 'Email', contactEmail),
            ],
          ),
        ),

        const SizedBox(height: 24),

        if (businessHourRows.isNotEmpty || googleMapsUrl.isNotEmpty) ...[
          _buildBusinessHoursCard(
            businessHourRows: businessHourRows,
            googleMapsUrl: googleMapsUrl,
          ),
          const SizedBox(height: 24),
        ],

        // WhatsApp Quick Contact
        if (whatsappNumber.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.white, size: 24),
                    SizedBox(width: 12),
                    Text(
                      '¿Necesitas ayuda rápida?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Escríbenos por WhatsApp y te responderemos al instante.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final message = Uri.encodeComponent(
                        '¡Hola! Me gustaría obtener más información.',
                      );
                      _launchUrl('https://wa.me/$whatsappNumber?text=$message');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Abrir WhatsApp'),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 24),

        // Social Media
        if (instagramHandle.isNotEmpty || facebookHandle.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Síguenos',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: PublicStoreTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (instagramHandle.isNotEmpty)
                      _buildSocialButton(
                        icon: Icons.camera_alt_outlined,
                        label: 'Instagram',
                        color: const Color(0xFFE4405F),
                        onTap: () => _launchUrl(
                            'https://instagram.com/$instagramHandle'),
                      ),
                    if (instagramHandle.isNotEmpty && facebookHandle.isNotEmpty)
                      const SizedBox(width: 12),
                    if (facebookHandle.isNotEmpty)
                      _buildSocialButton(
                        icon: Icons.facebook,
                        label: 'Facebook',
                        color: const Color(0xFF1877F2),
                        onTap: () =>
                            _launchUrl('https://facebook.com/$facebookHandle'),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBusinessHoursCard({
    required List<_BusinessHourRowData> businessHourRows,
    required String googleMapsUrl,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: PublicStoreTheme.divider),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: PublicStoreTheme.textPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Horario de Atención',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: PublicStoreTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (businessHourRows.isNotEmpty) ...[
            for (final row in businessHourRows)
              _buildHourRow(row.dayLabel, row.hoursLabel, row.isOpen),
            if (googleMapsUrl.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Divider(color: PublicStoreTheme.divider),
              const SizedBox(height: 14),
              _buildGoogleMapsButton(googleMapsUrl),
            ],
          ] else ...[
            const Text(
              'Consulta el horario actualizado directamente en Google Maps.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: PublicStoreTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            _buildGoogleMapsButton(googleMapsUrl),
          ],
        ],
      ),
    );
  }

  Widget _buildGoogleMapsButton(String googleMapsUrl) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _launchUrl(googleMapsUrl),
        icon: const Icon(Icons.map_outlined, size: 18),
        label: const Text('Ver en Google Maps'),
        style: OutlinedButton.styleFrom(
          foregroundColor: PublicStoreTheme.textPrimary,
          side: const BorderSide(color: PublicStoreTheme.divider),
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  List<_BusinessHourRowData> _parseBusinessHours(String rawJson) {
    if (rawJson.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(rawJson);
      final rootData = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
      final data = rootData['opening_hours'] is Map
          ? Map<String, dynamic>.from(rootData['opening_hours'] as Map)
          : rootData;
      final periods = data['periods'] as List<dynamic>? ?? const [];
      if (periods.isEmpty) return const [];

      const dayOrder = [
        'MONDAY',
        'TUESDAY',
        'WEDNESDAY',
        'THURSDAY',
        'FRIDAY',
        'SATURDAY',
        'SUNDAY',
      ];
      const dayLabels = {
        'MONDAY': 'Lunes',
        'TUESDAY': 'Martes',
        'WEDNESDAY': 'Miércoles',
        'THURSDAY': 'Jueves',
        'FRIDAY': 'Viernes',
        'SATURDAY': 'Sábado',
        'SUNDAY': 'Domingo',
      };

      final hoursByDay = {
        for (final day in dayOrder) day: <String>[],
      };

      for (final rawPeriod in periods) {
        if (rawPeriod is! Map) continue;
        final period = Map<String, dynamic>.from(rawPeriod);

        if (period.containsKey('openDay') || period.containsKey('openTime')) {
          final openDay = period['openDay']?.toString().toUpperCase();
          if (openDay == null || !hoursByDay.containsKey(openDay)) continue;

          final openTime = _formatBusinessTime(period['openTime']);
          final closeTime = _formatBusinessTime(period['closeTime']);
          if (openTime == null || closeTime == null) continue;

          hoursByDay[openDay]!.add('$openTime - $closeTime');
          continue;
        }

        final open = period['open'] is Map
            ? Map<String, dynamic>.from(period['open'] as Map)
            : null;
        final close = period['close'] is Map
            ? Map<String, dynamic>.from(period['close'] as Map)
            : null;
        final openDay = _googlePlacesDayToBusinessDay(open?['day']);
        if (openDay == null || !hoursByDay.containsKey(openDay)) continue;

        final openTime = _formatPlacesTime(open?['time']);
        final closeTime = _formatPlacesTime(close?['time']);
        if (openTime == null || closeTime == null) continue;

        hoursByDay[openDay]!.add('$openTime - $closeTime');
      }

      final daySchedules = <String, String>{
        for (final day in dayOrder)
          day: hoursByDay[day]!.isEmpty
              ? 'Cerrado'
              : hoursByDay[day]!.join(' / '),
      };

      final rows = <_BusinessHourRowData>[];
      var start = 0;

      while (start < dayOrder.length) {
        final schedule = daySchedules[dayOrder[start]]!;
        var end = start;

        while (end + 1 < dayOrder.length &&
            daySchedules[dayOrder[end + 1]] == schedule) {
          end++;
        }

        rows.add(
          _BusinessHourRowData(
            dayLabel: _formatDayRange(
              dayLabels[dayOrder[start]]!,
              dayLabels[dayOrder[end]]!,
            ),
            hoursLabel: schedule,
            isOpen: schedule != 'Cerrado',
          ),
        );

        start = end + 1;
      }

      return rows;
    } catch (error) {
      debugPrint('Could not parse Google Business hours: $error');
      return const [];
    }
  }

  String _formatDayRange(String start, String end) {
    if (start == end) return start;
    if (start == 'Lunes' && end == 'Domingo') return 'Todos los días';
    return '$start a $end';
  }

  String? _googlePlacesDayToBusinessDay(dynamic rawDay) {
    final day = rawDay is num ? rawDay.toInt() : int.tryParse('$rawDay');
    return switch (day) {
      0 => 'SUNDAY',
      1 => 'MONDAY',
      2 => 'TUESDAY',
      3 => 'WEDNESDAY',
      4 => 'THURSDAY',
      5 => 'FRIDAY',
      6 => 'SATURDAY',
      _ => null,
    };
  }

  String? _formatBusinessTime(dynamic rawTime) {
    if (rawTime is String) return _formatPlacesTime(rawTime);
    if (rawTime is! Map) return null;

    final time = Map<String, dynamic>.from(rawTime);
    final hours = (time['hours'] as num?)?.toInt() ?? 0;
    final minutes = (time['minutes'] as num?)?.toInt() ?? 0;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  String? _formatPlacesTime(dynamic rawTime) {
    final digits = rawTime?.toString().trim();
    if (digits == null || digits.isEmpty) return null;
    if (digits.contains(':')) return digits;
    if (digits.length < 3) return null;

    final padded = digits.padLeft(4, '0');
    final hours = padded.substring(0, 2);
    final minutes = padded.substring(2, 4);
    return '$hours:$minutes';
  }

  Widget _buildHourRow(String day, String hours, bool isOpen) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            day,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PublicStoreTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isOpen
                      ? const Color(0xFF10B981)
                      : const Color(0xFF94A3B8),
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                hours,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isOpen
                      ? PublicStoreTheme.textPrimary
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactDetailRow(IconData icon, String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF64748B), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PublicStoreTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content.isNotEmpty ? content : 'No especificado',
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: PublicStoreTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: const BorderSide(color: PublicStoreTheme.divider),
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: Colors.white,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Color? _parseColor(String value) {
    if (value.isEmpty) return null;

    var cleaned = value.trim().toLowerCase();

    // Handle "color(0xFFXXXXXX)" format
    if (cleaned.startsWith('color(')) {
      final inside = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
      final intValue = int.tryParse(inside);
      if (intValue != null) return Color(intValue);
    }

    // Handle "0xFFXXXXXX" format
    if (cleaned.startsWith('0x')) {
      final intValue = int.tryParse(cleaned);
      if (intValue != null) return Color(intValue);
    }

    // Handle "#XXXXXX" format
    cleaned = cleaned.replaceAll('#', '');
    final intValue = int.tryParse(cleaned, radix: 16);
    if (intValue != null) {
      if (cleaned.length <= 6) {
        return Color(0xFF000000 | intValue);
      }
      return Color(intValue);
    }

    return null;
  }
}
