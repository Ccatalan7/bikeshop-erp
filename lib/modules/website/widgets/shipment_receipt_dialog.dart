import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/email_html_view.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/shop_time.dart';
import '../models/online_order_shipment.dart';
import '../models/website_models.dart';
import '../services/online_order_shipment_service.dart';
import 'shipment_expense_fields.dart';

/// A file the person picked or dropped: its bytes and its name.
typedef PickedReceipt = ({Uint8List bytes, String name});

/// Where the dialog gets a receipt: the camera on a phone, a file anywhere.
typedef ReceiptPicker = Future<PickedReceipt?> Function({required bool camera});

/// Registers an online order's shipment from the photo of the carrier's
/// receipt (owner, 2026-10-13: the coworker sends the Correos receipt and the
/// ERP should «procesar todo lo que sigue»). The AI reads the receipt, the
/// dialog shows it against the order, and one button records the shipment,
/// moves the order to «Despachado», emails the customer the tracking code
/// and, unless turned off, registers what the carrier charged as an expense.
/// Without a receipt the same fields are typed by hand.
Future<OnlineOrderShipment?> showShipmentReceiptDialog(
  BuildContext context, {
  required OnlineOrder order,
  required Future<String?> customerRut,
  OnlineOrderShipmentRecorder? service,
  ReceiptPicker? picker,
}) {
  final phone = MediaQuery.sizeOf(context).width < 600;
  return showDialog<OnlineOrderShipment>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      final content = ShipmentReceiptDialog(
        order: order,
        customerRut: customerRut,
        service: service ?? OnlineOrderShipmentService(),
        picker: picker ?? _defaultPicker,
        phone: phone,
      );
      if (phone) return Dialog.fullscreen(child: content);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 820,
            maxHeight:
                (MediaQuery.sizeOf(context).height - 48).clamp(480.0, 980.0),
          ),
          child: content,
        ),
      );
    },
  );
}

bool get _hasCamera =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

Future<PickedReceipt?> _defaultPicker({required bool camera}) async {
  if (camera) {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera);
    if (shot == null) return null;
    return (bytes: await shot.readAsBytes(), name: shot.name);
  }
  final result = await FilePicker.platform.pickFiles(
    withData: true,
    allowMultiple: false,
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
  );
  final file = result?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  return (bytes: bytes, name: file.name);
}

enum _Stage { pick, reading, review, preview }

class ShipmentReceiptDialog extends StatefulWidget {
  const ShipmentReceiptDialog({
    super.key,
    required this.order,
    required this.customerRut,
    required this.service,
    required this.picker,
    required this.phone,
  });

  final OnlineOrder order;
  final Future<String?> customerRut;
  final OnlineOrderShipmentRecorder service;
  final ReceiptPicker picker;
  final bool phone;

  @override
  State<ShipmentReceiptDialog> createState() => _ShipmentReceiptDialogState();
}

class _ShipmentReceiptDialogState extends State<ShipmentReceiptDialog> {
  // One operation per dialog: a retry after a lost answer replays it.
  final String _operationKey = 'shipment:${const Uuid().v4()}';
  final _tracking = TextEditingController();
  final _service = TextEditingController();
  final _cost = TextEditingController();
  final _carrierName = TextEditingController();
  final _documentNumber = TextEditingController();

  _Stage _stage = _Stage.pick;
  ShipmentReceiptFile? _file;
  String? _uploadedPath;
  ShipmentReceiptReading? _reading;
  List<ShipmentReceiptCheck> _checks = const [];
  ShippingCarrier _carrier = ShippingCarrier.correosChile;
  int _formVersion = 0;
  DateTime? _admittedAt;

  /// What the AI read when it could not be the admission (a year misread).
  DateTime? _admissionMisread;
  String? _branch;
  bool _acknowledged = false;
  bool _saving = false;
  bool _previewing = false;
  ShipmentEmailPreview? _preview;
  bool _dragging = false;
  String? _error;

  // The carrier's cost as an expense (owner, 2026-10-13), on by default.
  ShipmentExpenseOptions? _expenseOptions;
  bool _expenseLoading = false;
  String? _expenseError;
  bool _includeExpense = true;
  String? _paymentMethodId;
  String _documentType = 'receipt';
  bool _documentTypeChosen = false;
  int _expenseRequest = 0;
  Timer? _carrierNameDebounce;

  OnlineOrder get _order => widget.order;

  @override
  void initState() {
    super.initState();
    for (final controller in [_tracking, _service, _cost, _carrierName]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _tracking.dispose();
    _service.dispose();
    _cost.dispose();
    _carrierName.dispose();
    _documentNumber.dispose();
    _carrierNameDebounce?.cancel();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _pick({required bool camera}) async {
    setState(() => _error = null);
    try {
      final picked = await widget.picker(camera: camera);
      if (picked == null || !mounted) return;
      await _read(picked);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _describe(error));
    }
  }

  Future<void> _read(PickedReceipt picked) async {
    setState(() {
      _stage = _Stage.reading;
      _error = null;
      _uploadedPath = null;
    });
    try {
      final file = await ShipmentReceiptFile.prepare(picked.bytes, picked.name);
      if (!mounted) return;
      setState(() => _file = file);
      final results = await Future.wait([
        widget.service.readReceipt(file),
        widget.customerRut.catchError((_) => null),
      ]);
      if (!mounted) return;
      final reading = results[0] as ShipmentReceiptReading;
      final rut = results[1] as String?;
      _apply(reading, rut);
    } catch (error) {
      if (!mounted) return;
      // The photo stays: the person types what the AI could not read.
      setState(() {
        _stage = _file == null ? _Stage.pick : _Stage.review;
        _error = _file == null
            ? _describe(error)
            : 'La IA no pudo leer la boleta (${_describe(error)}). '
                'Completa los datos mirando la foto.';
      });
    }
  }

  void _apply(ShipmentReceiptReading reading, String? rut) {
    setState(() {
      _reading = reading;
      _checks = checkReceiptAgainstOrder(
        order: _order,
        reading: reading,
        customerRut: rut,
      );
      _carrier = reading.carrier;
      _carrierName.text = reading.carrier == ShippingCarrier.other
          ? _titleCase(reading.carrierName ?? '')
          : '';
      _formVersion++;
      _tracking.text = reading.trackingNumber ?? '';
      _service.text = _titleCase(reading.service ?? '');
      _cost.text = reading.cost == null ? '' : reading.cost!.round().toString();
      final admission = plausibleAdmission(
        reading.admittedAt,
        orderCreatedAt: _order.createdAt,
      );
      _admittedAt = admission.at;
      _admissionMisread = admission.misread;
      _branch = reading.branch;
      _documentTypeChosen = reading.documentType != null;
      if (reading.documentType != null) _documentType = reading.documentType!;
      _documentNumber.text = reading.documentNumber ?? '';
      _acknowledged = false;
      _stage = _Stage.review;
    });
    _loadExpenseOptions();
  }

  void _manual() {
    setState(() {
      _file = null;
      _reading = null;
      _checks = const [];
      _uploadedPath = null;
      _acknowledged = false;
      _error = null;
      _admittedAt = null;
      _admissionMisread = null;
      _branch = null;
      _documentTypeChosen = false;
      _documentNumber.clear();
      _tracking.text = _order.trackingNumber ?? '';
      _formVersion++;
      _stage = _Stage.review;
    });
    _loadExpenseOptions();
  }

  void _restart() {
    setState(() {
      _stage = _Stage.pick;
      _file = null;
      _reading = null;
      _checks = const [];
      _uploadedPath = null;
      _acknowledged = false;
      _error = null;
    });
  }

  bool get _notAReceipt => _reading != null && !_reading!.isShippingReceipt;

  List<ShipmentReceiptCheck> get _mismatches => _checks
      .where((check) => check.status == ShipmentCheckStatus.mismatch)
      .toList(growable: false);

  /// The two readings of the code disagreed, or there was one only.
  bool get _trackingUncertain =>
      _reading != null && !_reading!.trackingVerified;

  bool get _needsAcknowledgement =>
      _notAReceipt || _mismatches.isNotEmpty || _trackingUncertain;

  bool get _notifies => _order.customerEmail.trim().isNotEmpty;

  String get _carrierLabel {
    final typed = _carrierName.text.trim();
    return _carrier == ShippingCarrier.other ? typed : _carrier.label;
  }

  int? get _costValue =>
      int.tryParse(_cost.text.replaceAll(RegExp(r'[^0-9]'), ''));

  /// The expense can be registered: a cost, an account, a way to pay.
  bool get _expenseAvailable =>
      !_expenseLoading &&
      _expenseError == null &&
      (_costValue ?? 0) > 0 &&
      (_expenseOptions?.canRecord ?? false);

  bool get _registersExpense =>
      !_order.isTest &&
      _includeExpense &&
      _expenseAvailable &&
      _paymentMethodId != null;

  /// Where the carrier's expense goes, asked again when the carrier changes.
  Future<void> _loadExpenseOptions() async {
    final carrier = _carrierLabel;
    final request = ++_expenseRequest;
    // A test order's shipment is never an expense (20261014020000).
    if (_order.isTest) return;
    if (carrier.isEmpty) {
      setState(() {
        _expenseOptions = null;
        _expenseLoading = false;
        _expenseError = null;
      });
      return;
    }
    setState(() {
      _expenseLoading = true;
      _expenseError = null;
    });
    try {
      final options = await widget.service.expenseOptions(carrier);
      if (!mounted || request != _expenseRequest) return;
      setState(() {
        _expenseLoading = false;
        _expenseOptions = options;
        final known = options.paymentMethods
            .any((method) => method.id == _paymentMethodId);
        if (!known) {
          _paymentMethodId =
              options.paymentMethodId ?? options.paymentMethods.firstOrNull?.id;
        }
        if (!_documentTypeChosen) _documentType = options.documentType;
      });
    } catch (error) {
      if (!mounted || request != _expenseRequest) return;
      setState(() {
        _expenseLoading = false;
        _expenseError = 'No se pudo preparar el gasto: ${_describe(error)}';
      });
    }
  }

  void _carrierNameChanged(String _) {
    _carrierNameDebounce?.cancel();
    _carrierNameDebounce =
        Timer(const Duration(milliseconds: 500), _loadExpenseOptions);
  }

  ShipmentExpenseDraft? _expenseDraft() => _registersExpense
      ? ShipmentExpenseDraft(
          paymentMethodId: _paymentMethodId!,
          documentType: _documentType,
          documentNumber: _documentNumber.text,
        )
      : null;

  /// The review is complete: a plausible code, a carrier, and what needed a
  /// look was looked at.
  bool get _reviewComplete =>
      isPlausibleTrackingNumber(_tracking.text) &&
      (_carrier != ShippingCarrier.other ||
          _carrierName.text.trim().isNotEmpty) &&
      (!_needsAcknowledgement || _acknowledged);

  /// With a customer email, registering happens from the email preview
  /// (owner, 2026-10-13: see it before it goes, like a WhatsApp template).
  bool get _canSave =>
      !_saving &&
      !_previewing &&
      _reviewComplete &&
      !(_includeExpense && _expenseLoading) &&
      (_stage == _Stage.preview || (_stage == _Stage.review && !_notifies));

  bool get _canPreview =>
      !_saving &&
      !_previewing &&
      _stage == _Stage.review &&
      _reviewComplete &&
      !(_includeExpense && _expenseLoading);

  ShipmentDraft _draft() {
    final cost = _costValue;
    return ShipmentDraft(
      carrier: _carrier,
      carrierName: _carrierName.text,
      trackingNumber: normalizeTrackingNumber(_tracking.text)!,
      service: _service.text,
      admittedAt: _admittedAt,
      branch: _branch,
      cost: cost?.toDouble(),
    );
  }

  Future<void> _openPreview() async {
    if (!_canPreview) return;
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final preview = await widget.service.previewEmail(
        order: _order,
        draft: _draft(),
      );
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _preview = preview;
        _stage = _Stage.preview;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewing = false;
        _error = _describe(error);
      });
    }
  }

  void _backToReview() {
    setState(() {
      _preview = null;
      _stage = _Stage.review;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final file = _file;
      if (file != null && _uploadedPath == null) {
        _uploadedPath = await widget.service.uploadReceipt(
          orderId: _order.id,
          file: file,
        );
      }
      final shipment = await widget.service.record(
        order: _order,
        operationKey: _operationKey,
        // The fields cannot change while the preview is open: what is
        // registered is what was previewed.
        draft: _draft(),
        receiptPath: _uploadedPath,
        reading: _reading,
        checks: _checks,
        expense: _expenseDraft(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(shipment);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _describe(error);
      });
    }
  }

  String _describe(Object error) {
    if (error is ShipmentReceiptException) return error.message;
    if (error is PostgrestException) {
      if (error.code == '40001') {
        return 'El pedido cambió mientras lo registrabas. Ciérralo y vuelve a abrirlo.';
      }
      return error.message;
    }
    if (error is StorageException) {
      return 'No se pudo guardar la foto: ${error.message}';
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final body = switch (_stage) {
      _Stage.pick => _buildPick(context, roles),
      _Stage.reading => _buildReading(context, roles),
      _Stage.review => _buildReview(context, roles),
      _Stage.preview => _buildPreview(context, roles),
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        // As tall as what it shows; it scrolls when the screen is shorter.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            order: _order,
            onClose: _saving ? null : _close,
            topInset: widget.phone ? MediaQuery.paddingOf(context).top : 0,
          ),
          Divider(height: 1, color: roles.hairline),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                widget.phone ? 16 : 24,
                20,
                widget.phone ? 16 : 24,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    _Banner(
                      tone: roles.danger,
                      icon: Icons.error_outline_rounded,
                      title: _error!,
                    ),
                    const SizedBox(height: 16),
                  ],
                  body,
                ],
              ),
            ),
          ),
          if (_stage == _Stage.review || _stage == _Stage.preview) ...[
            Divider(height: 1, color: roles.hairline),
            _buildFooter(context, roles),
          ],
        ],
      ),
    );
  }

  void _close() => Navigator.of(context).pop();

  Widget _buildPick(BuildContext context, VinabikeThemeRoles roles) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final zone = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: _dragging
            ? roles.selectionContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _dragging ? theme.colorScheme.primary : roles.hairline,
          width: _dragging ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: roles.info.container,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 30,
              color: roles.info.accent,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Sube la foto de la boleta del envío',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              'La IA lee el transportista, el código de seguimiento, el servicio '
              'y el valor, y revisa que el destinatario sea el de este pedido.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_hasCamera)
                FilledButton.icon(
                  onPressed: () => _pick(camera: true),
                  style: _buttonStyle,
                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                  label: const Text('Tomar foto'),
                ),
              if (_hasCamera)
                OutlinedButton.icon(
                  onPressed: () => _pick(camera: false),
                  style: _buttonStyle,
                  icon: const Icon(Icons.upload_file_rounded, size: 20),
                  label: const Text('Elegir foto o PDF'),
                )
              else
                FilledButton.icon(
                  onPressed: () => _pick(camera: false),
                  style: _buttonStyle,
                  icon: const Icon(Icons.upload_file_rounded, size: 20),
                  label: const Text('Elegir foto o PDF'),
                ),
            ],
          ),
          if (!_hasCamera) ...[
            const SizedBox(height: 12),
            Text(
              'o arrástrala aquí',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) async {
            setState(() => _dragging = false);
            final file = details.files.firstOrNull;
            if (file == null) return;
            await _read((bytes: await file.readAsBytes(), name: file.name));
          },
          child: zone,
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: _manual,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('No tengo la boleta: escribir los datos'),
          ),
        ),
      ],
    );
  }

  ButtonStyle get _buttonStyle => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _buildReading(BuildContext context, VinabikeThemeRoles roles) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (_file != null)
          _ReceiptPreview(file: _file!, height: 260, roles: roles),
        const SizedBox(height: 22),
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 14),
        Text(
          'Leyendo la boleta…',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Transportista, código, servicio y destinatario.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// «Así le llegará»: the email itself, drawn from the HTML the worker
  /// would send, with to whom, from whom and the subject above it.
  Widget _buildPreview(BuildContext context, VinabikeThemeRoles roles) {
    final preview = _preview!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final screen = MediaQuery.sizeOf(context).height;
    final height = widget.phone
        ? (screen - 330).clamp(360.0, 900.0)
        : (screen - 380).clamp(420.0, 640.0);
    String person(String? name, String? email) {
      if (email == null) return name ?? '—';
      return name == null ? email : '$name <$email>';
    }

    Widget line(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  style: (strong
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.bodySmall)
                      ?.copyWith(
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

    final String? notSent = preview.recipient == null
        ? 'El pedido no tiene un correo válido: el cliente no recibirá aviso.'
        : preview.suppressed != null
            ? 'Este correo está bloqueado (rebotó o el cliente pidió no '
                'recibir más): el despacho se registra, pero el correo no sale.'
            : preview.deliveryMode != 'send'
                ? 'Los correos del sitio están en modo de prueba: el despacho '
                    'se registra, pero el correo no sale.'
                : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Así le llegará',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line('Para', person(preview.recipientName, preview.recipient)),
              line('De', person(preview.senderName, preview.senderEmail)),
              line('Asunto', preview.subject, strong: true),
              if (_registersExpense) line('Gasto', _expenseSummary()),
            ],
          ),
        ),
        if (notSent != null) ...[
          const SizedBox(height: 12),
          _Banner(
            tone: roles.warning,
            icon: Icons.unsubscribe_outlined,
            title: notSent,
          ),
        ],
        const SizedBox(height: 14),
        Semantics(
          label: 'Vista previa del correo al cliente',
          child: Container(
            key: const ValueKey('shipment-email-preview'),
            height: height,
            // The browser view is a native view: Flutter cannot round or
            // clip it, so it sits inside the border instead of under it.
            padding: const EdgeInsets.all(1),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: roles.hairline),
            ),
            child: EmailHtmlView(html: preview.html),
          ),
        ),
      ],
    );
  }

  /// «$6.240 · Efectivo · boleta 0004581940», for the preview.
  String _expenseSummary() {
    final method = _expenseOptions?.paymentMethods
        .where((option) => option.id == _paymentMethodId)
        .firstOrNull;
    final number = _documentNumber.text.trim();
    return [
      ChileanUtils.formatCurrency((_costValue ?? 0).toDouble()),
      if (method != null) method.name,
      [
        _documentType == 'invoice' ? 'factura' : 'boleta',
        if (number.isNotEmpty) number
      ].join(' '),
    ].join(' · ');
  }

  Widget _buildReview(BuildContext context, VinabikeThemeRoles roles) {
    final form = _buildForm(context, roles);
    final file = _file;
    if (file == null) return form;
    final preview = _ReceiptPreview(
      file: file,
      height: widget.phone ? 200 : 360,
      roles: roles,
      onReplace: _saving ? null : _restart,
    );
    if (widget.phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [preview, const SizedBox(height: 20), form],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 250, child: preview),
        const SizedBox(width: 24),
        Expanded(child: form),
      ],
    );
  }

  Widget _buildForm(BuildContext context, VinabikeThemeRoles roles) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final charged = _order.shippingCost;
    final trackingText = _tracking.text.trim();
    final trackingInvalid =
        trackingText.isNotEmpty && !isPlausibleTrackingNumber(trackingText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_reading != null) ...[
          _CheckSummary(
            checks: _checks,
            notAReceipt: _notAReceipt,
            roles: roles,
          ),
          const SizedBox(height: 20),
        ] else if (_file == null) ...[
          _Banner(
            tone: roles.neutral,
            icon: Icons.edit_note_rounded,
            title:
                'Sin boleta: escribe el transportista y el código de seguimiento.',
          ),
          const SizedBox(height: 20),
        ],
        DropdownMenu<ShippingCarrier>(
          key: ValueKey('shipment-carrier-$_formVersion'),
          initialSelection: _carrier,
          expandedInsets: EdgeInsets.zero,
          label: const Text('Transportista'),
          leadingIcon: const Icon(Icons.local_shipping_outlined),
          onSelected: (carrier) {
            if (carrier == null || carrier == _carrier) return;
            setState(() => _carrier = carrier);
            _loadExpenseOptions();
          },
          dropdownMenuEntries: [
            for (final carrier in ShippingCarrier.all)
              DropdownMenuEntry(value: carrier, label: carrier.label),
          ],
        ),
        if (_carrier == ShippingCarrier.other) ...[
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('shipment-carrier-name'),
            controller: _carrierName,
            onChanged: _carrierNameChanged,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del transportista',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('shipment-tracking'),
          controller: _tracking,
          textCapitalization: TextCapitalization.characters,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
          ],
          decoration: InputDecoration(
            labelText: 'Número de seguimiento',
            prefixIcon: const Icon(Icons.qr_code_2_rounded),
            errorText: trackingInvalid
                ? 'Letras, números o guiones; al menos 6.'
                : null,
            helperText: _trackingUncertain
                ? 'Compáralo con la foto, carácter por carácter: la lectura no fue segura.'
                : null,
            helperMaxLines: 2,
          ),
        ),
        if (_reading?.trackingCloseUp != null) ...[
          const SizedBox(height: 8),
          _CloseUp(
            bytes: _reading!.trackingCloseUp!,
            verified: _reading!.trackingVerified,
            roles: roles,
          ),
        ],
        if ((_reading?.trackingCandidates.length ?? 0) > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Las lecturas no coinciden. ¿Cuál es?',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              for (final candidate in _reading!.trackingCandidates)
                ChoiceChip(
                  label: Text(
                    candidate,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  selected:
                      normalizeTrackingNumber(_tracking.text) == candidate,
                  onSelected: (_) => _tracking.text = candidate,
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('shipment-service'),
          controller: _service,
          decoration: const InputDecoration(
            labelText: 'Servicio',
            hintText: 'Ej.: Paquete Express AM',
            prefixIcon: Icon(Icons.bolt_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('shipment-cost'),
          controller: _cost,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Pagado al transportista',
            prefixText: r'$ ',
            prefixIcon: const Icon(Icons.payments_outlined),
            helperText: charged > 0
                ? 'Cobrado al cliente por el despacho: '
                    '${ChileanUtils.formatCurrency(charged)}'
                : null,
          ),
        ),
        if (_admittedAt != null || _branch != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (_admittedAt != null)
                      'Admitido el ${ChileanUtils.formatDateTime(shopTime(_admittedAt!))}',
                    if (_branch != null) _titleCase(_branch!),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ],
        if (_admissionMisread != null) ...[
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('shipment-admission-misread'),
            _admittedAt != null
                ? 'La IA leyó ${ChileanUtils.formatDate(shopTime(_admissionMisread!))}, '
                    'antes del pedido: se corrigió el año.'
                : 'La fecha leída (${ChileanUtils.formatDate(shopTime(_admissionMisread!))}) '
                    'no calza con el pedido y no se guarda.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: roles.warning.onContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_needsAcknowledgement) ...[
          const SizedBox(height: 16),
          CheckboxListTile(
            key: const ValueKey('shipment-acknowledge'),
            value: _acknowledged,
            onChanged: (value) => setState(() => _acknowledged = value == true),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              _notAReceipt
                  ? 'Revisé la imagen y los datos son de este envío'
                  : _mismatches.isNotEmpty && _trackingUncertain
                      ? 'Revisé la boleta: es de este pedido y el número está bien'
                      : _mismatches.isNotEmpty
                          ? 'Revisé la boleta y es de este pedido'
                          : 'Revisé el número de seguimiento en la foto',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (_order.isTest)
          Text(
            key: const ValueKey('shipment-expense-test-order'),
            'Pedido de prueba: el envío no se registra como gasto.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          )
        else
          ShipmentExpenseFields(
            amount: _costValue?.toDouble(),
            options: _expenseOptions,
            loading: _expenseLoading,
            error: _expenseError,
            include: _includeExpense,
            onInclude: (value) => setState(() => _includeExpense = value),
            paymentMethodId: _paymentMethodId,
            documentType: _documentType,
            documentNumber: _documentNumber,
            onPaymentMethod: (id) => setState(() => _paymentMethodId = id),
            onDocumentType: (type) => setState(() {
              _documentType = type;
              _documentTypeChosen = true;
            }),
            compact: widget.phone,
          ),
        const SizedBox(height: 12),
        _CustomerNotice(order: _order, roles: roles),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, VinabikeThemeRoles roles) {
    const spinner = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2.4),
    );
    final Widget save;
    final Widget back;
    if (_stage == _Stage.preview) {
      final sends = _preview?.willSend ?? false;
      save = FilledButton.icon(
        key: const ValueKey('shipment-save'),
        onPressed: _canSave ? _save : null,
        style: _buttonStyle,
        icon: _saving ? spinner : const Icon(Icons.send_rounded, size: 20),
        label: Text(
          sends
              ? 'Registrar despacho y enviar correo'
              : 'Registrar despacho sin correo',
        ),
      );
      back = TextButton(
        key: const ValueKey('shipment-preview-back'),
        onPressed: _saving ? null : _backToReview,
        child: const Text('Volver'),
      );
    } else if (_notifies) {
      save = FilledButton.icon(
        key: const ValueKey('shipment-preview'),
        onPressed: _canPreview ? _openPreview : null,
        style: _buttonStyle,
        icon: _previewing
            ? spinner
            : const Icon(Icons.mark_email_unread_outlined, size: 20),
        label: const Text('Ver el correo antes de enviar'),
      );
      back = TextButton(
        onPressed: _previewing ? null : _restart,
        child: Text(_file == null ? 'Subir boleta' : 'Cambiar foto'),
      );
    } else {
      save = FilledButton.icon(
        key: const ValueKey('shipment-save'),
        onPressed: _canSave ? _save : null,
        style: _buttonStyle,
        icon: _saving
            ? spinner
            : const Icon(Icons.local_shipping_rounded, size: 20),
        label: const Text('Registrar despacho'),
      );
      back = TextButton(
        onPressed: _saving ? null : _restart,
        child: Text(_file == null ? 'Subir boleta' : 'Cambiar foto'),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.phone ? 16 : 24,
        12,
        widget.phone ? 16 : 24,
        12 + (widget.phone ? MediaQuery.paddingOf(context).bottom : 0),
      ),
      child: widget.phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [save, const SizedBox(height: 4), back],
            )
          : Row(
              children: [
                back,
                const SizedBox(width: 12),
                // The label shrinks before it pushes out of the bar (large
                // text, a tablet in portrait).
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: save),
                ),
              ],
            ),
    );
  }
}

/// «PAQUETE EXPRESS AM» as «Paquete Express AM»; short words stay upper.
String _titleCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed != trimmed.toUpperCase()) return trimmed;
  return trimmed.split(RegExp(r'\s+')).map((word) {
    if (word.length <= 2) return word;
    return word[0] + word.substring(1).toLowerCase();
  }).join(' ');
}

class _Header extends StatelessWidget {
  const _Header({
    required this.order,
    required this.onClose,
    required this.topInset,
  });

  final OnlineOrder order;
  final VoidCallback? onClose;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = [order.shippingCity, order.shippingState]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(', ');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14 + topInset,
        8,
        14,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrar despacho',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [order.orderNumber, order.customerName, place]
                      .where((part) => part.trim().isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({
    required this.file,
    required this.height,
    required this.roles,
    this.onReplace,
  });

  final ShipmentReceiptFile file;
  final double height;
  final VinabikeThemeRoles roles;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canShow = file.isImage &&
        file.mimeType != 'image/heic' &&
        file.mimeType != 'image/heif';
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: height,
        color: theme.colorScheme.surfaceContainerHigh,
        alignment: Alignment.center,
        child: canShow
            ? Image.memory(file.bytes, fit: BoxFit.contain, height: height)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    file.mimeType == 'application/pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    size: 40,
                    color: roles.faintForeground,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    file.mimeType == 'application/pdf'
                        ? 'Boleta en PDF'
                        : 'Foto',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
      ),
    );
    return Semantics(
      label: 'Foto de la boleta del envío',
      image: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canShow ? () => _zoom(context) : null,
            child: picture,
          ),
          if (onReplace != null && canShow)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Toca la foto para verla grande',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _zoom(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Image.memory(file.bytes, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(dialogContext),
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.icon,
    required this.title,
    this.child,
  });

  final VinabikeSemanticTone tone;
  final IconData icon;
  final String title;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tone.onContainer,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (child != null) ...[const SizedBox(height: 8), child!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The receipt against the order, at a glance: green when it is this
/// order's, amber with the differences when something does not match.
class _CheckSummary extends StatelessWidget {
  const _CheckSummary({
    required this.checks,
    required this.notAReceipt,
    required this.roles,
  });

  final List<ShipmentReceiptCheck> checks;
  final bool notAReceipt;
  final VinabikeThemeRoles roles;

  @override
  Widget build(BuildContext context) {
    final mismatches = checks
        .where((check) => check.status == ShipmentCheckStatus.mismatch)
        .toList();
    final matches = checks
        .where((check) => check.status == ShipmentCheckStatus.match)
        .toList();
    final VinabikeSemanticTone tone;
    final IconData icon;
    final String title;
    if (notAReceipt) {
      tone = roles.danger;
      icon = Icons.report_gmailerrorred_rounded;
      title = 'Esto no parece una boleta de envío.';
    } else if (mismatches.isNotEmpty) {
      tone = roles.warning;
      icon = Icons.warning_amber_rounded;
      title = 'Revisa: la boleta no coincide con el pedido en '
          '${_list(mismatches.map((check) => check.label.toLowerCase()))}.';
    } else if (matches.isNotEmpty) {
      tone = roles.success;
      icon = Icons.verified_rounded;
      title = 'La boleta es de este pedido: coinciden '
          '${_list(matches.map((check) => check.label.toLowerCase()))}.';
    } else {
      tone = roles.neutral;
      icon = Icons.info_outline_rounded;
      title = 'La boleta no trae datos del destinatario para comparar.';
    }
    return _Banner(
      tone: tone,
      icon: icon,
      title: title,
      child: checks.isEmpty
          ? null
          : Column(
              children: [
                for (final check in checks) _CheckRow(check: check, tone: tone),
              ],
            ),
    );
  }

  static String _list(Iterable<String> items) {
    final values = items.toList();
    if (values.length <= 1) return values.join();
    return '${values.sublist(0, values.length - 1).join(', ')} y ${values.last}';
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, required this.tone});

  final ShipmentReceiptCheck check;
  final VinabikeSemanticTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (check.status) {
      ShipmentCheckStatus.match => Icons.check_rounded,
      ShipmentCheckStatus.mismatch => Icons.close_rounded,
      ShipmentCheckStatus.unknown => Icons.remove_rounded,
    };
    final detail =
        check.status == ShipmentCheckStatus.mismatch && check.onOrder != null
            ? '${check.onReceipt}  ·  pedido: ${check.onOrder}'
            : check.status == ShipmentCheckStatus.unknown
                ? '${check.onReceipt}  ·  sin dato en el pedido'
                : check.onReceipt;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: tone.onContainer,
      height: 1.3,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone.accent),
          const SizedBox(width: 6),
          SizedBox(
            width: 82,
            child: Text(
              check.label,
              style: style?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(detail, style: style)),
        ],
      ),
    );
  }
}

/// The code as printed, enlarged from the photo, under the field that holds
/// what was read: the person compares the two at a glance.
class _CloseUp extends StatelessWidget {
  const _CloseUp({
    required this.bytes,
    required this.verified,
    required this.roles,
  });

  final Uint8List bytes;
  final bool verified;
  final VinabikeThemeRoles roles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = verified ? roles.success : roles.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: roles.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              image: true,
              label: 'Número de seguimiento en la boleta',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  color: Colors.white,
                  height: 56,
                  alignment: Alignment.centerLeft,
                  child: Image.memory(bytes, height: 56, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            verified ? Icons.verified_rounded : Icons.visibility_outlined,
            size: 18,
            color: tone.accent,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 112,
            child: Text(
              verified ? 'Confirmado de cerca' : 'Compáralo con el campo',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerNotice extends StatelessWidget {
  const _CustomerNotice({required this.order, required this.roles});

  final OnlineOrder order;
  final VinabikeThemeRoles roles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = order.customerEmail.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            email.isEmpty
                ? Icons.unsubscribe_outlined
                : Icons.mark_email_read_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              email.isEmpty
                  ? 'El pedido no tiene correo: el cliente no recibirá aviso.'
                  : 'El pedido pasa a Despachado y $email recibe el correo '
                      '«Tu pedido va en camino» con el número de seguimiento. '
                      'Antes de enviarlo verás cómo le llega.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
