import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/public_store_theme.dart';

class FloatingWhatsAppButton extends StatelessWidget {
  final String phoneNumber;
  final String message;
  final Color backgroundColor;

  const FloatingWhatsAppButton({
    super.key,
    required this.phoneNumber,
    this.message = 'Hola! Me gustaría consultar sobre sus productos.',
    this.backgroundColor = PublicStoreTheme.accentGreen,
  });

  Future<void> _openWhatsApp() async {
    if (phoneNumber.isEmpty) return;
    final encodedMessage = Uri.encodeComponent(message);
    final url = Uri.parse('https://wa.me/$phoneNumber?text=$encodedMessage');

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
            color: backgroundColor,
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
