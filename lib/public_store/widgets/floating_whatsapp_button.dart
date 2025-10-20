import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/public_store_theme.dart';

class FloatingWhatsAppButton extends StatelessWidget {
  const FloatingWhatsAppButton({super.key});

  Future<void> _openWhatsApp() async {
    final phone = '56912345678'; // Replace with your actual WhatsApp number
    final message = Uri.encodeComponent('Hola! Me gustaría consultar sobre sus productos.');
    final url = Uri.parse('https://wa.me/$phone?text=$message');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _openWhatsApp,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: PublicStoreTheme.accentGreen,
            shape: BoxShape.circle,
            boxShadow: PublicStoreTheme.floatingShadow,
          ),
          child: const Icon(
            Icons.chat_bubble,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }
}
