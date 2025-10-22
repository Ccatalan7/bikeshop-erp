import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/public_store_theme.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  Future<void> _launchPhone(String phone) async {
    await _launchUrl('tel:$phone');
  }

  Future<void> _launchEmail(String email) async {
    await _launchUrl('mailto:$email');
  }

  Future<void> _launchWhatsApp() async {
    const phone = '56912345678'; // Replace with actual WhatsApp number
    const message =
        '¡Hola! Me gustaría obtener más información sobre sus productos.';
    final url = 'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
    await _launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Section
            _buildHeroSection(),

            // Contact Information Section
            Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
              child: Column(
                children: [
                  // Contact Cards Grid
                  _buildContactCardsGrid(),
                  const SizedBox(height: 64),

                  // Store Location & Map Section
                  _buildStoreLocationSection(),
                  const SizedBox(height: 64),

                  // Contact Form
                  _buildContactForm(context),
                  const SizedBox(height: 64),

                  // Business Hours
                  _buildBusinessHours(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      height: 300,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PublicStoreTheme.primaryBlue,
            PublicStoreTheme.primaryBlue.withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.contact_support_outlined,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 16),
            Text(
              'Contáctanos',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Estamos aquí para ayudarte',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCardsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        return Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _buildContactCard(
              icon: Icons.location_on_outlined,
              title: 'Dirección',
              subtitle: 'Viña del Mar, Chile',
              details: 'Av. Libertad 1234\nViña del Mar, Región de Valparaíso',
              color: PublicStoreTheme.primaryBlue,
              onTap: () =>
                  _launchUrl('https://maps.google.com/?q=Viña+del+Mar'),
              width: isWide
                  ? (constraints.maxWidth - 48) / 3
                  : constraints.maxWidth,
            ),
            _buildContactCard(
              icon: Icons.phone_outlined,
              title: 'Teléfono',
              subtitle: '+56 9 1234 5678',
              details: 'Lunes a Viernes: 9:00 - 19:00\nSábado: 10:00 - 14:00',
              color: const Color(0xFF10B981),
              onTap: () => _launchPhone('+56912345678'),
              width: isWide
                  ? (constraints.maxWidth - 48) / 3
                  : constraints.maxWidth,
            ),
            _buildContactCard(
              icon: Icons.email_outlined,
              title: 'Email',
              subtitle: 'contacto@vinabike.cl',
              details: 'Respondemos en 24 horas\nventas@vinabike.cl',
              color: const Color(0xFFF59E0B),
              onTap: () => _launchEmail('contacto@vinabike.cl'),
              width: isWide
                  ? (constraints.maxWidth - 48) / 3
                  : constraints.maxWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String details,
    required Color color,
    required VoidCallback onTap,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 40, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  details,
                  style: const TextStyle(
                    fontSize: 14,
                    color: PublicStoreTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreLocationSection() {
    return Column(
      children: [
        const Text(
          'Nuestra Tienda',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Visítanos en nuestra tienda física',
          style: TextStyle(
            fontSize: 16,
            color: PublicStoreTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 32),

        // Map Placeholder (replace with actual Google Maps embed)
        Container(
          height: 400,
          decoration: BoxDecoration(
            color: PublicStoreTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: PublicStoreTheme.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                // Placeholder for map
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        size: 64,
                        color: PublicStoreTheme.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Viña del Mar, Chile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: PublicStoreTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _launchUrl(
                            'https://maps.google.com/?q=Viña+del+Mar'),
                        icon: const Icon(Icons.directions),
                        label: const Text('Ver en Google Maps'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactForm(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final messageController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return Column(
      children: [
        const Text(
          'Envíanos un Mensaje',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Completa el formulario y te responderemos pronto',
          style: TextStyle(
            fontSize: 16,
            color: PublicStoreTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      hintText: 'Juan Pérez',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa tu nombre';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'juan@ejemplo.cl',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Por favor ingresa tu email';
                      }
                      if (!value.contains('@')) {
                        return 'Por favor ingresa un email válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      labelText: 'Mensaje',
                      hintText: 'Escribe tu mensaje aquí...',
                      prefixIcon: Icon(Icons.message_outlined),
                      border: OutlineInputBorder(),
                    ),
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
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        // For now, open email client with pre-filled message
                        final subject = 'Contacto desde sitio web';
                        final body =
                            'Nombre: ${nameController.text}\n\n${messageController.text}';
                        _launchUrl(
                            'mailto:contacto@vinabike.cl?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Abriendo cliente de correo...'),
                            backgroundColor: PublicStoreTheme.successGreen,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PublicStoreTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Enviar Mensaje',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // WhatsApp Alternative
                  OutlinedButton.icon(
                    onPressed: _launchWhatsApp,
                    icon: const Icon(Icons.chat_bubble_outline,
                        color: Color(0xFF25D366)),
                    label: const Text(
                      'O escríbenos por WhatsApp',
                      style: TextStyle(color: Color(0xFF25D366)),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFF25D366)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessHours() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.access_time,
                    size: 32, color: PublicStoreTheme.primaryBlue),
                SizedBox(width: 12),
                Text(
                  'Horario de Atención',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildHourRow('Lunes a Viernes', '9:00 - 19:00', true),
            _buildHourRow('Sábado', '10:00 - 14:00', true),
            _buildHourRow('Domingo', 'Cerrado', false),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PublicStoreTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: PublicStoreTheme.primaryBlue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Atención online 24/7 - Respondemos emails en menos de 24 horas',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHourRow(String day, String hours, bool isOpen) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            day,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              if (isOpen)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: PublicStoreTheme.successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                hours,
                style: TextStyle(
                  fontSize: 16,
                  color: isOpen
                      ? PublicStoreTheme.textPrimary
                      : PublicStoreTheme.textSecondary,
                  fontWeight: isOpen ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
