import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/file_download.dart';
import '../../../shared/utils/shop_time.dart';
import '../../settings/models/company_profile.dart';
import '../../settings/services/appearance_service.dart';
import '../../settings/services/company_profile_service.dart';
import '../models/website_models.dart';
import '../services/online_order_shipping_label_pdf.dart';
import '../services/website_service.dart';

/// The order's shipping label, ready to print or download (2026-10-13: the
/// shop wrote each box by hand). It opens over the order, previews the real
/// PDF and lets the operator pick the paper and the number of packages.
Future<void> showOnlineOrderShippingLabelDialog(
  BuildContext context,
  OnlineOrder order,
) {
  final phone = MediaQuery.sizeOf(context).width < 600;
  return showDialog<void>(
    context: context,
    builder: (_) {
      final content = _ShippingLabelDialog(order: order, phone: phone);
      if (phone) return Dialog.fullscreen(child: content);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight:
                (MediaQuery.sizeOf(context).height - 48).clamp(480.0, 1100.0),
          ),
          child: content,
        ),
      );
    },
  );
}

class _LabelSources {
  const _LabelSources({
    required this.data,
    required this.fonts,
    required this.logo,
  });

  final ShippingLabelData data;
  final ShippingLabelFonts fonts;
  final Uint8List? logo;
}

class _ShippingLabelDialog extends StatefulWidget {
  const _ShippingLabelDialog({required this.order, required this.phone});

  final OnlineOrder order;
  final bool phone;

  @override
  State<_ShippingLabelDialog> createState() => _ShippingLabelDialogState();
}

class _ShippingLabelDialogState extends State<_ShippingLabelDialog> {
  late final Future<_LabelSources> _sources;
  ShippingLabelPaper _paper = ShippingLabelPaper.label10x15;
  int _packages = 1;
  bool _busy = false;
  final Map<String, Future<Uint8List>> _pdfs = {};

  String get _fileName => 'Etiqueta ${widget.order.orderNumber}.pdf';

  @override
  void initState() {
    super.initState();
    WebsiteService? website;
    String? logoUrl;
    try {
      website = context.read<WebsiteService>();
    } on ProviderNotFoundException {
      website = null;
    }
    try {
      logoUrl = context.read<AppearanceService>().companyLogoUrl;
    } on ProviderNotFoundException {
      logoUrl = null;
    }
    _sources = _loadSources(website, logoUrl);
  }

  Future<_LabelSources> _loadSources(
    WebsiteService? website,
    String? logoUrl,
  ) async {
    // The sender and the RUT make the label complete, but a label without
    // them still ships: a failed read leaves the line to write by hand.
    CompanyProfile? company;
    try {
      company = await CompanyProfileService().loadDefaultCompany();
    } catch (error) {
      debugPrint('Shipping label: company profile unavailable: $error');
    }
    String? rut;
    try {
      rut = await website?.customerRutForOrder(widget.order);
    } catch (error) {
      debugPrint('Shipping label: customer RUT unavailable: $error');
    }
    Uint8List? logo;
    try {
      if (logoUrl != null && logoUrl.isNotEmpty) {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode == 200) logo = response.bodyBytes;
      }
    } catch (error) {
      debugPrint('Shipping label: logo unavailable: $error');
    }
    final fonts = ShippingLabelFonts(
      regular: await rootBundle.load('assets/fonts/Barlow-Regular.ttf'),
      medium: await rootBundle.load('assets/fonts/Barlow-Medium.ttf'),
      semiBold: await rootBundle.load('assets/fonts/Barlow-SemiBold.ttf'),
      bold: await rootBundle.load('assets/fonts/Barlow-Bold.ttf'),
      extraBold: await rootBundle.load('assets/fonts/Barlow-ExtraBold.ttf'),
    );
    return _LabelSources(
      data: ShippingLabelData.fromOrder(
        widget.order,
        company: company,
        recipientRut: rut,
        shipDate: shopTime(DateTime.now()),
      ),
      fonts: fonts,
      logo: logo,
    );
  }

  Future<Uint8List> _pdf(_LabelSources sources) {
    return _pdfs.putIfAbsent(
      '${_paper.name}-$_packages',
      () => buildShippingLabelPdf(
        sources.data,
        packages: _packages,
        paper: _paper,
        fonts: sources.fonts,
        logo: sources.logo,
      ),
    );
  }

  Future<void> _download(_LabelSources sources) => _run(() async {
        final result = await downloadFile(
          bytes: await _pdf(sources),
          fileName: _fileName,
          mimeType: 'application/pdf',
          promptForLocation: true,
        );
        if (!mounted || result.cancelled) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.path == null
                  ? 'Etiqueta descargada.'
                  : 'Etiqueta guardada en ${result.path}',
            ),
          ),
        );
      });

  Future<void> _print(_LabelSources sources) => _run(() async {
        final bytes = await _pdf(sources);
        await Printing.layoutPdf(
          name: _fileName,
          format: _paper == ShippingLabelPaper.label10x15
              ? shippingLabelFormat
              : PdfPageFormat.letter,
          onLayout: (_) async => bytes,
        );
      });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo completar la etiqueta: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = widget.phone;
    final insets = phone ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: FutureBuilder<_LabelSources>(
        future: _sources,
        builder: (context, snapshot) {
          final sources = snapshot.data;
          final download = OutlinedButton.icon(
            onPressed:
                sources == null || _busy ? null : () => _download(sources),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text('Descargar'),
          );
          final print = FilledButton.icon(
            onPressed: sources == null || _busy ? null : () => _print(sources),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 22),
            ),
            icon: const Icon(Icons.print_outlined, size: 20),
            label: const Text('Imprimir'),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  phone ? 4 : 24,
                  insets.top + (phone ? 4 : 14),
                  phone ? 12 : 12,
                  4,
                ),
                child: Row(
                  children: [
                    if (phone)
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Volver al pedido',
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Etiqueta de despacho',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${widget.order.orderNumber} · ${widget.order.customerName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!phone)
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(phone ? 16 : 24, 6, 16, 10),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (paper, label) in const [
                          (ShippingLabelPaper.label10x15, '10 × 15 cm'),
                          (ShippingLabelPaper.letter, 'Carta, para recortar'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _paper == paper,
                            onSelected: (_) => setState(() => _paper = paper),
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Bultos',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          onPressed: _packages > 1
                              ? () => setState(() => _packages--)
                              : null,
                          tooltip: 'Un bulto menos',
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        Text(
                          '$_packages',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          onPressed: _packages < 20
                              ? () => setState(() => _packages++)
                              : null,
                          tooltip: 'Un bulto más',
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: sources == null
                      ? Center(
                          child: snapshot.hasError
                              ? Text(
                                  'No se pudo preparar la etiqueta: ${snapshot.error}',
                                )
                              : const CircularProgressIndicator(),
                        )
                      : PdfPreview(
                          key: ValueKey('${_paper.name}-$_packages'),
                          build: (_) => _pdf(sources),
                          useActions: false,
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                          canDebug: false,
                          pdfFileName: _fileName,
                          maxPageWidth: _paper == ShippingLabelPaper.label10x15
                              ? 380
                              : 640,
                          scrollViewDecoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                          ),
                        ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  12 + insets.bottom,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: phone
                      ? [
                          Expanded(child: download),
                          const SizedBox(width: 10),
                          Expanded(child: print),
                        ]
                      : [
                          const Spacer(),
                          download,
                          const SizedBox(width: 10),
                          print,
                        ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
