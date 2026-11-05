import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../messaging/providers/chat_provider.dart';
import '../services/delivery_document_service.dart';

/// El QR de la recepción: se le muestra al cliente en la pantalla del taller
/// para que cree su cuenta en segundos y siga su bici desde el teléfono.
///
/// Cada vez que se abre saca un código nuevo (sólo se guarda su huella). Si el
/// cliente ya tiene cuenta, lo dice y no saca nada.
Future<void> showCustomerAccountQrDialog(
  BuildContext context, {
  required String jobId,
  required String customerName,
  String? customerId,
  String? customerPhone,
  DeliveryDocumentService? service,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => CustomerAccountQrDialog(
      jobId: jobId,
      customerName: customerName,
      customerId: customerId,
      customerPhone: customerPhone,
      service: service ?? DeliveryDocumentService(),
    ),
  );
}

class CustomerAccountQrDialog extends StatefulWidget {
  const CustomerAccountQrDialog({
    super.key,
    required this.jobId,
    required this.customerName,
    required this.service,
    this.customerId,
    this.customerPhone,
  });

  final String jobId;
  final String customerName;
  final String? customerId;
  final String? customerPhone;
  final DeliveryDocumentService service;

  @override
  State<CustomerAccountQrDialog> createState() =>
      _CustomerAccountQrDialogState();
}

class _CustomerAccountQrDialogState extends State<CustomerAccountQrDialog> {
  late Future<CustomerClaimCode> _loading;
  bool _sending = false;
  String? _notice;
  bool _noticeIsError = false;

  @override
  void initState() {
    super.initState();
    _loading = _issue();
  }

  Future<CustomerClaimCode> _issue() => widget.service.issueClaimCode(
        widget.jobId,
        purpose: CustomerClaimPurpose.reception,
      );

  String get _firstName {
    final name = widget.customerName.trim().split(RegExp(r'\s+')).first;
    return name.isEmpty ? 'el cliente' : name;
  }

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _noticeIsError = error;
    });
  }

  Future<void> _copy(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      _say('Enlace copiado.');
    } catch (_) {
      _say('No se pudo copiar el enlace.', error: true);
    }
  }

  /// El chat del cliente con el enlace listo en el compositor: el operador
  /// lo lee y lo manda.
  Future<void> _sendLink(String url) async {
    final phone = widget.customerPhone?.trim();
    if (_sending || phone == null || phone.isEmpty) return;
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      final chat = context.read<ChatProvider>();
      final toolbar = context.read<RightToolbarService>();
      final navigator = Navigator.of(context);
      final conversationId = await chat.openWhatsAppConversationForHandoff(
        phoneNumber: phone,
        contactName: widget.customerName,
        customerId: widget.customerId,
        contextType: 'job',
        contextId: widget.jobId,
      );
      chat.offerComposerAttachments(
        conversationId,
        const [],
        text: customerAccountLinkText(_firstName, url),
      );
      if (!mounted) return;
      navigator.pop();
      toolbar.openConversation(
        tool: ToolbarTool.messages,
        conversationId: conversationId,
      );
    } catch (error) {
      debugPrint('⚠️ [QR de cuenta] no se abrió el chat: $error');
      _say(
        'No se pudo abrir el chat del cliente. Revisa la conexión e intenta '
        'de nuevo.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.widthOf(context) < 600;
    final content = FutureBuilder<CustomerClaimCode>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          );
        }
        final code = snapshot.data;
        if (snapshot.hasError || code == null) {
          final error = snapshot.error;
          return _Message(
            icon: Icons.wifi_off_rounded,
            text: error is DeliveryDocumentFailure
                ? error.message
                : 'No se pudo sacar el código. Revisa la conexión e intenta '
                    'de nuevo.',
            action: VbButton(
              label: 'Reintentar',
              icon: Icons.refresh_rounded,
              variant: VbButtonVariant.secondary,
              onPressed: () => setState(() => _loading = _issue()),
            ),
          );
        }
        if (code.alreadyLinked) {
          return _Message(
            icon: Icons.verified_user_outlined,
            text: '${_capitalized(_firstName)} ya tiene cuenta: sigue su bici '
                'y su garantía en el portal.',
          );
        }
        final url = code.claimUrl;
        if (url == null) {
          return _Message(
            icon: Icons.link_off_rounded,
            text: code.status == 'no_customer'
                ? 'El trabajo no tiene un cliente activo.'
                : 'La tienda no tiene su dirección web guardada (Sitio web › '
                    'Ajustes): sin ella el QR no tiene adónde llevar.',
          );
        }
        return _QrBody(
          url: url,
          firstName: _capitalized(_firstName),
          canSend: (widget.customerPhone ?? '').trim().isNotEmpty,
          sending: _sending,
          notice: _notice,
          noticeIsError: _noticeIsError,
          onSend: () => _sendLink(url),
          onCopy: () => _copy(url),
        );
      },
    );

    final header = _QrHeader(onClose: () => Navigator.of(context).pop());
    if (compact) {
      return Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              header,
              Expanded(child: SingleChildScrollView(child: content)),
            ],
          ),
        ),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [header, content],
          ),
        ),
      ),
    );
  }
}

/// «DORA» → «Dora» (el taller a veces escribe en mayúsculas); el resto, como
/// está.
String _capitalized(String value) {
  if (value.isEmpty) return value;
  final shouting = value == value.toUpperCase() && value.length > 1;
  final rest = shouting ? value.substring(1).toLowerCase() : value.substring(1);
  return '${value[0].toUpperCase()}$rest';
}

/// Lo que va en el chat con el enlace: corto, con la voz de la marca.
String customerAccountLinkText(String firstName, String url) {
  final name = firstName.trim();
  final greeting = name.isEmpty || name == 'el cliente'
      ? 'Hola'
      : 'Hola ${_capitalized(name)}';
  return '$greeting, este es el enlace para crear tu cuenta y seguir el '
      'estado de tu bici:\n$url';
}

class _QrHeader extends StatelessWidget {
  const _QrHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Cuenta del cliente',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Lo que mira el cliente: el QR grande, blanco aunque la app esté oscura
/// (la cámara necesita el contraste), y qué gana con la cuenta.
class _QrBody extends StatelessWidget {
  const _QrBody({
    required this.url,
    required this.firstName,
    required this.canSend,
    required this.sending,
    required this.notice,
    required this.noticeIsError,
    required this.onSend,
    required this.onCopy,
  });

  final String url;
  final String firstName;
  final bool canSend;
  final bool sending;
  final String? notice;
  final bool noticeIsError;
  final VoidCallback onSend;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Crea tu cuenta',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$firstName, escanea el código para seguir el estado de tu bici '
            'y revisar tu garantía.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Semantics(
              image: true,
              label: 'Código QR para crear la cuenta',
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  // Blanco a propósito: un QR claro sobre oscuro no lo leen
                  // todas las cámaras.
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: roles.hairline),
                ),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 260,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF17242C),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF17242C),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          VbButton(
            label: 'Mandarle el enlace por WhatsApp',
            icon: Icons.chat_outlined,
            expand: true,
            busy: sending,
            onPressed: canSend && !sending ? onSend : null,
            disabledReason: canSend ? null : 'El cliente no tiene teléfono.',
          ),
          const SizedBox(height: 8),
          VbButton(
            label: 'Copiar enlace',
            icon: Icons.link_rounded,
            variant: VbButtonVariant.secondary,
            expand: true,
            onPressed: onCopy,
          ),
          if (notice != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                notice!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: noticeIsError
                      ? roles.danger.accent
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}
