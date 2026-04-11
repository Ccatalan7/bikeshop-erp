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
        websiteService.getSetting('contact_email', 'vinabikechile@gmail.com');
    final contactPhone =
        websiteService.getSetting('contact_phone', '+56 9 9835 7797');
    final contactAddress = websiteService.getSetting(
        'contact_address', 'Álvarez 32, Local 17\nViña del Mar, Chile');
    final whatsappRaw = websiteService.getSetting('whatsapp', '+56998357797');
    final whatsappNumber = _sanitizePhone(whatsappRaw);
    final instagramHandle = websiteService.getSetting('instagram', '');
    final facebookHandle = websiteService.getSetting('facebook', '');

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
                  // Contact Cards - 3 column grid
                  _buildContactCards(
                    contactAddress: contactAddress,
                    contactPhone: contactPhone,
                    contactEmail: contactEmail,
                    primaryColor: primaryColor,
                    modeKey: modeKey,
                  ),

                  const SizedBox(height: 80),

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
                              child:
                                  _buildContactForm(contactEmail, primaryColor, modeKey),
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
                                primaryColor: primaryColor,
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _buildContactForm(contactEmail, primaryColor, modeKey),
                          const SizedBox(height: 48),
                          _buildInfoPanel(
                            storeName: storeName,
                            contactAddress: contactAddress,
                            contactPhone: contactPhone,
                            contactEmail: contactEmail,
                            whatsappNumber: whatsappNumber,
                            instagramHandle: instagramHandle,
                            facebookHandle: facebookHandle,
                            primaryColor: primaryColor,
                          ),
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

  Widget _buildHeroSection(Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            primaryColor.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.mail_outline_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Contáctanos',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Estamos aquí para ayudarte. Escríbenos y te responderemos lo antes posible.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: 0.9),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactCards({
    required String contactAddress,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required String modeKey,
  }) {
    return MediaQueryLayoutBuilder(
      key: ValueKey('contact_cards_layout_$modeKey'),
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final cardWidth =
            isWide ? (constraints.maxWidth - 48) / 3 : constraints.maxWidth;

        return Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: [
            _buildContactCard(
              icon: Icons.location_on_outlined,
              title: 'Visítanos',
              content: contactAddress.replaceAll('\\n', '\n'),
              actionLabel: 'Ver en mapa',
              onTap: () => _launchUrl(
                'https://maps.google.com/?q=${Uri.encodeComponent(contactAddress.replaceAll('\n', ', '))}',
              ),
              primaryColor: primaryColor,
              width: cardWidth,
            ),
            _buildContactCard(
              icon: Icons.phone_outlined,
              title: 'Llámanos',
              content: contactPhone,
              actionLabel: 'Llamar ahora',
              onTap: () => _launchUrl('tel:${_sanitizePhone(contactPhone)}'),
              primaryColor: primaryColor,
              width: cardWidth,
            ),
            _buildContactCard(
              icon: Icons.email_outlined,
              title: 'Escríbenos',
              content: contactEmail,
              actionLabel: 'Enviar email',
              onTap: () => _launchUrl('mailto:$contactEmail'),
              primaryColor: primaryColor,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String content,
    required String actionLabel,
    required VoidCallback onTap,
    required Color primaryColor,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 32, color: primaryColor),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactForm(String contactEmail, Color primaryColor, String modeKey) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
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
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Completa el formulario y te responderemos en menos de 24 horas.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),

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
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey.shade500),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
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
    required Color primaryColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Business Hours Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Icon(Icons.access_time, color: primaryColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Horario de Atención',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildHourRow('Lunes a Viernes', '10:00 - 19:00', true),
              _buildHourRow('Sábado', '10:00 - 14:00', true),
              _buildHourRow('Domingo', 'Cerrado', false),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // WhatsApp Quick Contact
        if (whatsappNumber.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF25D366), Color(0xFF128C7E)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.chat_bubble, color: Colors.white, size: 24),
                    SizedBox(width: 12),
                    Text(
                      '¿Necesitas ayuda rápida?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Escríbenos por WhatsApp y te responderemos al instante.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
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
                      foregroundColor: const Color(0xFF25D366),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Abrir WhatsApp',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Síguenos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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

  Widget _buildHourRow(String day, String hours, bool isOpen) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            day,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: isOpen ? Colors.green : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                hours,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isOpen ? Colors.black87 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
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
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
