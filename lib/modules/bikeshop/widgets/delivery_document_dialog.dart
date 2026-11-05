import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_public_core/public_store/documents/delivery_warranty_pdf.dart';
import 'package:vinabike_public_core/public_store/documents/store_document_style.dart';

import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/file_download.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../messaging/models/chat_attachment_draft.dart';
import '../../messaging/providers/chat_provider.dart';
import '../services/delivery_document_service.dart';

/// Dibuja la vista previa del PDF. Las pruebas la reemplazan: el raster de
/// `printing` necesita la plataforma.
typedef DeliveryDocumentPreviewBuilder = Widget Function(
  BuildContext context,
  Uint8List bytes,
  String fileName,
);

/// El comprobante de entrega y garantía de un trabajo entregado: la vista
/// previa del mismo PDF que el cliente ve en su cuenta y lo que el equipo
/// hace con él — mandarlo por WhatsApp, imprimirlo o guardarlo.
///
/// Si el cliente no tiene cuenta, el comprobante lleva el QR para crearla
/// (un código nuevo cada vez que se abre: de cada código se guarda sólo su
/// huella, así que no se puede volver a dibujar uno viejo).
Future<void> showDeliveryDocumentDialog(
  BuildContext context, {
  required String jobId,
  String? customerId,
  DeliveryDocumentService? service,
  DeliveryDocumentPreviewBuilder? previewBuilder,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => DeliveryDocumentDialog(
      jobId: jobId,
      customerId: customerId,
      service: service ?? DeliveryDocumentService(),
      previewBuilder: previewBuilder,
    ),
  );
}

class DeliveryDocumentDialog extends StatefulWidget {
  const DeliveryDocumentDialog({
    super.key,
    required this.jobId,
    required this.service,
    this.customerId,
    this.previewBuilder,
  });

  final String jobId;
  final String? customerId;
  final DeliveryDocumentService service;
  final DeliveryDocumentPreviewBuilder? previewBuilder;

  @override
  State<DeliveryDocumentDialog> createState() => _DeliveryDocumentDialogState();
}

class _LoadedDocument {
  const _LoadedDocument({
    required this.document,
    required this.input,
    required this.bytes,
    required this.claimUnavailable,
  });

  final DeliveryDocument document;
  final DeliveryWarrantyPdfInput input;
  final Uint8List bytes;

  /// El cliente no tiene cuenta pero no se pudo sacar el código del QR.
  final bool claimUnavailable;
}

enum _Busy { none, whatsapp, print, save }

class _DeliveryDocumentDialogState extends State<DeliveryDocumentDialog> {
  late Future<_LoadedDocument> _loading;
  _Busy _busy = _Busy.none;

  /// El resultado de la última acción, dentro del diálogo (no un SnackBar
  /// detrás de la barrera).
  String? _notice;
  bool _noticeIsError = false;

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<_LoadedDocument> _load() async {
    final document = await widget.service.ensure(widget.jobId);
    String? claimUrl;
    var claimUnavailable = false;
    final origin = document.storeOrigin;
    if (!document.customerHasAccount) {
      if (origin == null) {
        claimUnavailable = true;
      } else {
        try {
          final code = await widget.service.issueClaimCode(
            widget.jobId,
            purpose: CustomerClaimPurpose.delivery,
          );
          if (code.issued) {
            claimUrl = customerPortalClaimUrl(origin, code.code!);
          } else if (!code.alreadyLinked) {
            claimUnavailable = true;
          }
        } catch (error) {
          debugPrint('⚠️ [Comprobante] sin código para el QR: $error');
          claimUnavailable = true;
        }
      }
    }
    final input = document.pdfInput(claimUrl: claimUrl);
    final bytes = await buildDeliveryWarrantyPdfBytes(input);
    return _LoadedDocument(
      document: document,
      input: input,
      bytes: bytes,
      claimUnavailable: claimUnavailable,
    );
  }

  void _retry() {
    setState(() {
      _notice = null;
      _loading = _load();
    });
  }

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _noticeIsError = error;
    });
  }

  Future<void> _run(_Busy kind, Future<void> Function() action) async {
    if (_busy != _Busy.none) return;
    setState(() {
      _busy = kind;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      debugPrint('⚠️ [Comprobante] $kind: $error');
      _say(
        switch (kind) {
          _Busy.whatsapp => 'No se pudo abrir el chat del cliente. Revisa la '
              'conexión e intenta de nuevo.',
          _Busy.print => 'No se pudo abrir la impresión.',
          _ => 'No se pudo guardar el PDF.',
        },
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  /// El chat del cliente, ligado al trabajo, con el PDF y un texto listos en
  /// el compositor. Elegir no envía: el operador lo lee y lo manda, y fuera de
  /// las 24 h el chat ofrece la plantilla de documento.
  Future<void> _sendByWhatsApp(_LoadedDocument loaded) => _run(
        _Busy.whatsapp,
        () async {
          final phone = loaded.document.customerPhone;
          if (phone == null) return;
          final chat = context.read<ChatProvider>();
          final toolbar = context.read<RightToolbarService>();
          final navigator = Navigator.of(context);
          final conversationId = await chat.openWhatsAppConversationForHandoff(
            phoneNumber: phone,
            contactName: loaded.document.customerName ?? phone,
            customerId: widget.customerId,
            contextType: 'job',
            contextId: loaded.document.jobId,
          );
          chat.offerComposerAttachments(
            conversationId,
            [
              PendingChatAttachment(
                id: 'delivery-document-${loaded.document.jobId}-'
                    '${DateTime.now().microsecondsSinceEpoch}',
                fileName: loaded.input.fileName,
                bytes: loaded.bytes,
                extension: 'pdf',
                isImage: false,
              ),
            ],
            text: deliveryDocumentWhatsAppText(loaded.input),
          );
          if (!mounted) return;
          navigator.pop();
          toolbar.openConversation(
            tool: ToolbarTool.messages,
            conversationId: conversationId,
          );
        },
      );

  Future<void> _print(_LoadedDocument loaded) => _run(
        _Busy.print,
        () => Printing.layoutPdf(
          onLayout: (_) async => loaded.bytes,
          name: loaded.input.fileName,
        ),
      );

  Future<void> _save(_LoadedDocument loaded, {required bool share}) => _run(
        _Busy.save,
        () async {
          if (share) {
            await Printing.sharePdf(
              bytes: loaded.bytes,
              filename: loaded.input.fileName,
            );
            return;
          }
          final result = await downloadFile(
            bytes: loaded.bytes,
            fileName: loaded.input.fileName,
            mimeType: 'application/pdf',
          );
          if (result.cancelled) return;
          _say(result.path == null
              ? 'El PDF quedó en tus descargas.'
              : 'Guardado en ${result.path}.');
        },
      );

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.widthOf(context) < 760;
    final body = FutureBuilder<_LoadedDocument>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Loading();
        }
        if (snapshot.hasError || snapshot.data == null) {
          final error = snapshot.error;
          return _LoadError(
            message: error is DeliveryDocumentFailure
                ? error.message
                : 'No se pudo armar el comprobante. Revisa la conexión e '
                    'intenta de nuevo.',
            onRetry: _retry,
          );
        }
        final loaded = snapshot.data!;
        final preview = widget.previewBuilder?.call(
              context,
              loaded.bytes,
              loaded.input.fileName,
            ) ??
            _PdfPagePreview(
                bytes: loaded.bytes, fileName: loaded.input.fileName);
        final panel = _SidePanel(
          loaded: loaded,
          busy: _busy,
          notice: _notice,
          noticeIsError: _noticeIsError,
          compact: compact,
          onWhatsApp: () => _sendByWhatsApp(loaded),
          onPrint: () => _print(loaded),
          onSave: () => _save(loaded, share: compact || _isMobilePlatform),
        );
        if (compact) {
          return Column(
            children: [
              _CompactWarrantyStrip(document: loaded.document),
              Expanded(child: preview),
              panel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: preview),
            SizedBox(width: 340, child: panel),
          ],
        );
      },
    );

    final header = _Header(jobId: widget.jobId, loading: _loading);
    if (compact) {
      return Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              header,
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: (screen.width - 32).clamp(0.0, 1120.0).toDouble(),
        height: (screen.height - 32).clamp(0.0, 900.0).toDouble(),
        child: Column(
          children: [
            header,
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

bool get _isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// El texto que acompaña el PDF en el chat: lo que el cliente tiene que
/// saber sin abrirlo, con la voz de la marca (tuteo, corto; ni frases de app
/// ni de notaría — dueño, 2026-11-04).
String deliveryDocumentWhatsAppText(DeliveryWarrantyPdfInput document) {
  final name = document.customerName?.trim().split(RegExp(r'\s+')).first;
  final greeting = name == null || name.isEmpty ? 'Hola' : 'Hola $name';
  final service = document.serviceWarrantyDays > 0
      ? 'La garantía del servicio es válida hasta el '
          '${storeDocumentLongDate(document.serviceWarrantyExpiresAt)}'
      : null;
  final parts = document.partsWarrantyMonths > 0 && document.showsPartsWarranty
      ? 'la de repuestos hasta el '
          '${storeDocumentLongDate(document.partsWarrantyExpiresAt)}'
      : null;
  final warranty = [
    if (service != null) service,
    if (parts != null) parts,
  ].join(' y ');
  return '$greeting, te adjuntamos el comprobante de entrega y garantía de tu '
      'servicio ${document.jobNumber}.'
      '${warranty.isEmpty ? '' : ' $warranty.'} ${document.thanksLine}';
}

class _Header extends StatelessWidget {
  const _Header({required this.jobId, required this.loading});

  final String jobId;
  final Future<_LoadedDocument> loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: roles.hairline)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_outlined,
            size: 22,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FutureBuilder<_LoadedDocument>(
              future: loading,
              builder: (context, snapshot) {
                final document = snapshot.data?.document;
                final subtitle = document == null
                    ? null
                    : [
                        document.jobNumber,
                        if (document.customerName != null)
                          document.customerName!,
                      ].join(' · ');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Comprobante de entrega',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Cerrar comprobante',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _PdfPagePreview extends StatelessWidget {
  const _PdfPagePreview({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      label: 'Vista previa del comprobante en PDF',
      child: PdfPreview(
        build: (PdfPageFormat _) async => bytes,
        useActions: false,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: fileName,
        scrollViewDecoration: BoxDecoration(color: roles.shell.canvas),
      ),
    );
  }
}

/// La garantía y la cuenta del cliente al lado de la vista previa, y lo que
/// se hace con el comprobante.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.loaded,
    required this.busy,
    required this.notice,
    required this.noticeIsError,
    required this.compact,
    required this.onWhatsApp,
    required this.onPrint,
    required this.onSave,
  });

  final _LoadedDocument loaded;
  final _Busy busy;
  final String? notice;
  final bool noticeIsError;
  final bool compact;
  final VoidCallback onWhatsApp;
  final VoidCallback onPrint;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final document = loaded.document;
    final hasPhone = document.customerPhone != null;
    final idle = busy == _Busy.none;

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VbButton(
          label: 'Enviar por WhatsApp',
          icon: Icons.chat_outlined,
          expand: true,
          busy: busy == _Busy.whatsapp,
          onPressed: hasPhone && idle ? onWhatsApp : null,
          disabledReason: hasPhone ? null : 'El cliente no tiene teléfono.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: VbButton(
                label: 'Imprimir',
                icon: Icons.print_outlined,
                variant: VbButtonVariant.secondary,
                expand: true,
                busy: busy == _Busy.print,
                onPressed: idle ? onPrint : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: VbButton(
                label: compact || _isMobilePlatform
                    ? 'Compartir PDF'
                    : 'Guardar PDF',
                icon: compact || _isMobilePlatform
                    ? Icons.ios_share_rounded
                    : Icons.download_rounded,
                variant: VbButtonVariant.secondary,
                expand: true,
                busy: busy == _Busy.save,
                onPressed: idle ? onSave : null,
              ),
            ),
          ],
        ),
        if (notice != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              notice!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: noticeIsError
                    ? roles.danger.accent
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );

    if (compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: roles.hairline)),
        ),
        child: actions,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: roles.hairline)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        children: [
          const _PanelLabel('Garantía'),
          const SizedBox(height: 10),
          _WarrantyRow(
            label: 'Servicio',
            covered: document.serviceWarrantyDays > 0,
            daysRemaining: document.serviceDaysRemaining,
            until: document.serviceWarrantyExpiresAt,
          ),
          if (document.showsPartsWarranty) ...[
            const SizedBox(height: 10),
            _WarrantyRow(
              label: 'Repuestos',
              covered: document.partsWarrantyMonths > 0,
              daysRemaining: document.partsDaysRemaining,
              until: document.partsWarrantyExpiresAt,
            ),
          ],
          const SizedBox(height: 22),
          const _PanelLabel('Cuenta del cliente'),
          const SizedBox(height: 8),
          Text(
            _accountSentence(loaded),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 24),
          actions,
        ],
      ),
    );
  }

  static String _accountSentence(_LoadedDocument loaded) {
    final name = loaded.document.customerName?.split(RegExp(r'\s+')).first;
    final who = name == null || name.isEmpty ? 'El cliente' : name;
    if (loaded.document.customerHasAccount) {
      return '$who ya tiene cuenta: el comprobante también queda en su portal.';
    }
    if (loaded.input.claimUrl != null) {
      return '$who no tiene cuenta. El comprobante incluye el QR para crearla.';
    }
    return '$who no tiene cuenta y esta vez el comprobante va sin QR: falta '
        'la dirección de la tienda o no hubo conexión.';
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _WarrantyRow extends StatelessWidget {
  const _WarrantyRow({
    required this.label,
    required this.covered,
    required this.daysRemaining,
    required this.until,
  });

  final String label;
  final bool covered;
  final int daysRemaining;
  final DateTime until;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final active = covered && daysRemaining > 0;
    final tone = active ? roles.success : roles.neutral;
    final remaining = !covered
        ? 'Sin garantía'
        : daysRemaining <= 0
            ? 'Venció'
            : daysRemaining == 1
                ? 'Queda 1 día'
                : 'Quedan $daysRemaining días';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: tone.onContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remaining,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tone.onContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (covered)
                  Text(
                    '${daysRemaining <= 0 ? 'Terminó el' : 'Hasta el'} '
                    '${storeDocumentLongDate(until)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tone.onContainer,
                    ),
                  ),
              ],
            ),
          ),
          VbStatusBadge(
            label: active ? 'Vigente' : (covered ? 'Vencida' : 'No aplica'),
            tone: active ? VbStatusTone.success : VbStatusTone.neutral,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// En el teléfono, la garantía en una línea arriba de la vista previa.
class _CompactWarrantyStrip extends StatelessWidget {
  const _CompactWarrantyStrip({required this.document});

  final DeliveryDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    String piece(String label, bool covered, int days) => !covered
        ? '$label: sin garantía'
        : days <= 0
            ? '$label: venció'
            : '$label: ${days == 1 ? 'queda 1 día' : 'quedan $days días'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: roles.success.container,
      child: Text(
        [
          piece('Servicio', document.serviceWarrantyDays > 0,
              document.serviceDaysRemaining),
          if (document.showsPartsWarranty)
            piece('Repuestos', document.partsWarrantyMonths > 0,
                document.partsDaysRemaining),
        ].join('  ·  '),
        style: theme.textTheme.labelLarge?.copyWith(
          color: roles.success.onContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 14),
          Text(
            'Armando el comprobante…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              VbButton(
                label: 'Reintentar',
                icon: Icons.refresh_rounded,
                variant: VbButtonVariant.secondary,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
