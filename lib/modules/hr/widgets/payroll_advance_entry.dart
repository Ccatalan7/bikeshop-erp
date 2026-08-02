import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../../storage/services/app_file_storage_service.dart';
import '../payroll/theme/payroll_tokens.dart';
import '../models/payroll_audit_read_models.dart';
import '../models/payroll_voucher.dart';
import 'payroll_format.dart';
import 'payroll_money_bar.dart';
import 'payroll_payment_sheet.dart' show ClpAmountInputFormatter;

/// El comprobante original tal como lo eligió el operador: **bytes en
/// memoria**, sin subir.
///
/// Elegir un archivo no es registrarlo. La subida ocurre dentro de
/// `PayrollAdvanceRegistrationService.register`, y **sólo después** de que el
/// backend confirmó que el bundle `v3` existe: así nunca queda un comprobante
/// inmutable colgado en Storage por un anticipo que no llegó a registrarse.
@immutable
class PayrollAdvanceReceiptDraft {
  const PayrollAdvanceReceiptDraft({
    required this.bytes,
    required this.fileName,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
}

/// A request to register money handed to a worker outside a voucher payment.
@immutable
class PayrollAdvanceIntent {
  const PayrollAdvanceIntent({
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    required this.paymentMethodId,
    required this.paymentAccountId,
    required this.paidAt,
    required this.operationKey,
    required this.reasonCode,
    required this.reasonExplanation,
    this.workEndedOn,
    this.originalReceipt,
    this.reference,
    this.notes,
  });

  final String employeeId;
  final String employeeName;
  final double amount;
  final String paymentMethodId;
  final String paymentAccountId;
  final DateTime paidAt;
  final String operationKey;

  /// Qué clase de anticipo es, en el vocabulario del backend auditado.
  final PayrollAdvanceReasonCode reasonCode;

  /// Por qué se entrega, en palabras del operador. **Siempre obligatoria**:
  /// el código dice la familia, no el caso, y un anticipo sin motivo escrito
  /// es exactamente lo que la auditoría no puede reconstruir después.
  final String reasonExplanation;

  /// Último día trabajado. **Sólo** existe —y sólo es obligatorio— cuando el
  /// motivo es `shortWorkweek`: es el dato que define la semana corta.
  final DateTime? workEndedOn;

  /// Respaldo en papel, opcional, todavía en memoria.
  final PayrollAdvanceReceiptDraft? originalReceipt;

  /// Referencia bancaria del movimiento. Es un dato del pago, no del motivo.
  final String? reference;

  /// Notas de ORIGEN, separadas del motivo a propósito: `notes` cuenta desde
  /// dónde se registró y `reasonExplanation` cuenta por qué se entregó. Antes
  /// viajaban mezcladas en un solo texto y la auditoría no podía separarlas.
  final String? notes;
}

/// Opens advance entry either from a worker/week shortcut or from the global
/// payroll command, where choosing the worker is mandatory.
Future<PayrollAdvanceIntent?> showPayrollAdvanceEntry({
  required BuildContext context,
  required List<Map<String, dynamic>> paymentMethods,
  PayrollVoucher? voucher,
  PayrollVoucherLine? line,
  List<Map<String, dynamic>> employees = const [],
  String? initialEmployeeId,
}) {
  assert(
    (voucher == null && line == null) || (voucher != null && line != null),
  );
  final isCompact = ResponsiveViewport.widthOf(context) <
      ResponsiveViewport.phoneMaxExclusive;
  final content = PayrollAdvanceEntry(
    voucher: voucher,
    line: line,
    paymentMethods: paymentMethods,
    employees: employees,
    initialEmployeeId: initialEmployeeId,
  );

  if (isCompact) {
    return showModalBottomSheet<PayrollAdvanceIntent>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: content,
      ),
    );
  }

  return showDialog<PayrollAdvanceIntent>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        // 680, no 580. El contrato `v3` sumó dos campos OBLIGATORIOS —tipo y
        // explicación— y con el techo anterior quedaban **bajo el pliegue**:
        // el formulario se veía completo, el primario estaba habilitado, y al
        // pulsarlo reclamaba un campo que nunca se mostró. Medido en la app
        // viva a 1360×768, donde sobraban 140 px de pantalla sin usar.
        //
        // `ConstrainedBox` respeta primero la restricción que baja del
        // `Dialog`, así que en una ventana baja sigue acotado y el scroll
        // interno hace su trabajo; acá sólo deja de desperdiciar el alto que
        // había.
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: content,
      ),
    ),
  );
}

/// Elige un archivo y lo devuelve **en memoria**. Inyectable para que las
/// pruebas ejerzan el recorrido completo sin abrir el panel del sistema.
typedef PayrollAdvanceReceiptPicker = Future<PayrollAdvanceReceiptDraft?>
    Function();

class PayrollAdvanceEntry extends StatefulWidget {
  const PayrollAdvanceEntry({
    super.key,
    required this.paymentMethods,
    this.voucher,
    this.line,
    this.employees = const [],
    this.initialEmployeeId,
    this.pickReceipt,
  });

  final PayrollVoucher? voucher;
  final PayrollVoucherLine? line;
  final List<Map<String, dynamic>> paymentMethods;
  final List<Map<String, dynamic>> employees;
  final String? initialEmployeeId;

  /// Nulo en producción: usa el selector del sistema.
  final PayrollAdvanceReceiptPicker? pickReceipt;

  @override
  State<PayrollAdvanceEntry> createState() => _PayrollAdvanceEntryState();
}

class _PayrollAdvanceEntryState extends State<PayrollAdvanceEntry> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  String? _employeeId;
  String? _methodId;
  DateTime _paidAt = DateTime.now();
  String? _validationError;
  bool _isDirty = false;
  bool _allowPop = false;

  /// `5h` · qué clase de anticipo es. Arranca en el caso corriente para que el
  /// formulario no exija una decisión antes de la primera cifra.
  PayrollAdvanceReasonCode _reasonCode =
      PayrollAdvanceReasonCode.requestedAdvance;

  /// Último día trabajado. Sólo vive con `shortWorkweek`.
  DateTime? _workEndedOn;

  /// Comprobante elegido y todavía **no** subido.
  PayrollAdvanceReceiptDraft? _receipt;
  bool _pickingReceipt = false;

  /// Estable por instancia del formulario: el mismo intento reintentado no
  /// puede convertirse en dos anticipos. Sobrevive a cada `setState`, que es
  /// justo lo que un `Uuid()` recalculado en `build` no haría.
  final String _operationKey = const Uuid().v4();

  bool get _needsWorkEndedOn =>
      _reasonCode == PayrollAdvanceReasonCode.shortWorkweek;

  /// Sólo para pruebas: deja comprobar que la clave **no** cambia entre
  /// reconstrucciones, que es lo que impide registrar dos veces el mismo
  /// anticipo al reintentar.
  @visibleForTesting
  String get operationKeyForTest => _operationKey;

  double get _amount =>
      double.tryParse(_amountController.text.replaceAll('.', '').trim()) ?? 0;

  List<Map<String, dynamic>> get _eligiblePaymentMethods =>
      widget.paymentMethods
          .where(
            (method) =>
                method['is_active'] == true &&
                (method['id']?.toString().trim().isNotEmpty ?? false) &&
                (method['account_id']?.toString().trim().isNotEmpty ?? false),
          )
          .toList(growable: false);

  List<Map<String, dynamic>> get _activePaymentMethods {
    final methods = _eligiblePaymentMethods;
    methods.sort(
      (a, b) => _paymentMethodOptionLabel(a, methods)
          .toLowerCase()
          .compareTo(_paymentMethodOptionLabel(b, methods).toLowerCase()),
    );
    return methods;
  }

  String _paymentMethodName(Map<String, dynamic> method) {
    final name = method['name']?.toString().trim();
    return name == null || name.isEmpty ? 'Sin nombre' : name;
  }

  String _paymentMethodOptionLabel(
    Map<String, dynamic> method,
    List<Map<String, dynamic>> candidates,
  ) {
    final name = _paymentMethodName(method);
    final accountCode = method['account_code']?.toString().trim();
    final accountName = method['account_name']?.toString().trim();
    final accountParts = <String>[
      if (accountCode != null && accountCode.isNotEmpty) accountCode,
      if (accountName != null &&
          accountName.isNotEmpty &&
          accountName.toLowerCase() != accountCode?.toLowerCase())
        accountName,
    ];
    if (accountParts.isNotEmpty) {
      return '$name · ${accountParts.join(' · ')}';
    }

    final sameName = candidates
        .where(
          (candidate) =>
              _paymentMethodName(candidate).toLowerCase() == name.toLowerCase(),
        )
        .toList(growable: false);
    if (sameName.length <= 1) return name;

    sameName.sort(
      (a, b) => (a['account_id']?.toString() ?? '')
          .compareTo(b['account_id']?.toString() ?? ''),
    );
    final position = sameName.indexWhere(
      (candidate) => candidate['id']?.toString() == method['id']?.toString(),
    );
    return '$name · cuenta contable ${position < 0 ? 1 : position + 1}';
  }

  List<Map<String, dynamic>> get _selectableEmployees {
    final byId = <String, Map<String, dynamic>>{};
    for (final employee in widget.employees) {
      final id = employee['id']?.toString().trim();
      if (id == null || id.isEmpty) continue;
      final status = employee['status']?.toString().trim().toLowerCase();
      if (status != null && status.isNotEmpty && status != 'active') continue;
      if (employee['is_active'] == false) continue;
      byId.putIfAbsent(id, () => employee);
    }
    final employees = byId.values.toList(growable: false);
    employees.sort(
      (a, b) => _employeeOptionLabel(a)
          .toLowerCase()
          .compareTo(_employeeOptionLabel(b).toLowerCase()),
    );
    return employees;
  }

  Map<String, dynamic>? get _selectedMethod {
    for (final method in _activePaymentMethods) {
      if (method['id']?.toString() == _methodId) return method;
    }
    return null;
  }

  bool get _selectedMethodRequiresReference =>
      _selectedMethod?['requires_reference'] == true;

  Map<String, dynamic>? get _selectedEmployee {
    final employeeId = _employeeId;
    if (employeeId == null) return null;
    for (final employee in _selectableEmployees) {
      if (employee['id']?.toString() == employeeId) return employee;
    }
    return null;
  }

  String _employeeDisplayName(Map<String, dynamic> employee) {
    final displayName = employee['display_name']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final name = [
      employee['first_name']?.toString().trim() ?? '',
      employee['last_name']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    return name.isEmpty ? 'Persona sin nombre' : name;
  }

  String _employeeOptionLabel(Map<String, dynamic> employee) {
    final rut = employee['rut']?.toString().trim();
    return [
      _employeeDisplayName(employee),
      if (rut != null && rut.isNotEmpty) rut,
    ].join(' · ');
  }

  String get _employeeName {
    final line = widget.line;
    if (line != null) return line.employeeName;
    final row = _selectedEmployee;
    if (row == null) return 'una persona';
    return _employeeDisplayName(row);
  }

  String? _preferredMethodIdFor(Map<String, dynamic>? employee) {
    final preferred =
        employee?['preferred_payment_method_id']?.toString().trim();
    if (preferred == null || preferred.isEmpty) return null;
    return _activePaymentMethods.any(
      (method) => method['id']?.toString() == preferred,
    )
        ? preferred
        : null;
  }

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    final requestedEmployeeId =
        line?.employeeId ?? widget.initialEmployeeId?.trim();
    _employeeId = line != null
        ? line.employeeId
        : _selectableEmployees.any(
            (employee) => employee['id']?.toString() == requestedEmployeeId,
          )
            ? requestedEmployeeId
            : null;
    final lineMethodId = line?.paymentMethodId?.trim();
    _methodId = _activePaymentMethods.any(
      (method) => method['id']?.toString() == lineMethodId,
    )
        ? lineMethodId
        : _preferredMethodIdFor(_selectedEmployee);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(_paidAt.year - 1),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _paidAt = picked;
        _isDirty = true;
      });
    }
  }

  Future<void> _pickWorkEndedOn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _workEndedOn ?? _paidAt,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _workEndedOn = picked;
        _validationError = null;
        _isDirty = true;
      });
    }
  }

  /// Elige el comprobante y lo deja **en memoria**. No sube nada: la subida
  /// vive en el coordinador y sólo ocurre después de confirmar la capability,
  /// para que cancelar acá no deje un archivo inmutable huérfano en Storage.
  Future<void> _pickReceipt() async {
    if (_pickingReceipt) return;
    setState(() => _pickingReceipt = true);
    try {
      final picked = await (widget.pickReceipt ?? _defaultReceiptPicker)();
      if (!mounted) return;
      PayrollAdvanceReceiptValidation? validated;
      if (picked != null) {
        validated = PayrollAdvanceReceiptPolicyV1.validate(
          bytes: picked.bytes,
          fileName: picked.fileName,
          mimeType: picked.mimeType,
        );
      }
      setState(() {
        if (picked != null && validated != null) {
          _receipt = PayrollAdvanceReceiptDraft(
            bytes: picked.bytes,
            fileName: validated.fileName,
            mimeType: validated.mimeType,
          );
          _isDirty = true;
          _validationError = null;
        }
      });
    } on ArgumentError catch (error) {
      if (!mounted) return;
      final message = error.message?.toString().trim();
      setState(() {
        _validationError = message == null || message.isEmpty
            ? 'El comprobante no es válido.'
            : message;
      });
    } catch (error) {
      // Nunca se interpola el error: puede traer rutas o nombres del negocio.
      debugPrint('❌ [PayrollAdvance] selector (${error.runtimeType})');
      if (!mounted) return;
      setState(() => _validationError =
          'No pudimos abrir el selector de archivos. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _pickingReceipt = false);
    }
  }

  Future<PayrollAdvanceReceiptDraft?> _defaultReceiptPicker() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) return null;
    return PayrollAdvanceReceiptDraft(
      bytes: bytes,
      fileName: file.name,
      mimeType: _mimeForExtension(file.extension),
    );
  }

  static String? _mimeForExtension(String? extension) =>
      switch (extension?.toLowerCase()) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        _ => null,
      };

  Future<void> _requestClose() async {
    if (!_isDirty) {
      _pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Descartar este anticipo?'),
        content: const Text(
          'El dinero todavía no se ha registrado en el libro de anticipos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _pop();
  }

  void _pop([PayrollAdvanceIntent? result]) {
    _allowPop = true;
    Navigator.of(context).pop(result);
  }

  void _selectEmployee(String? value) {
    setState(() {
      _employeeId = value;
      _methodId = _preferredMethodIdFor(_selectedEmployee);
      _validationError = null;
      _isDirty = true;
    });
  }

  void _submit() {
    final employeeId = widget.line?.employeeId ?? _employeeId;
    if (employeeId == null || employeeId.isEmpty) {
      setState(() => _validationError = 'Elige quién recibe el anticipo.');
      return;
    }
    if (_amount <= 0) {
      setState(() => _validationError = 'Ingresa un monto mayor que cero.');
      return;
    }
    final method = _selectedMethod;
    final methodId = method?['id']?.toString().trim();
    if (methodId == null || methodId.isEmpty) {
      setState(() {
        _validationError = _activePaymentMethods.isEmpty
            ? 'No hay métodos de pago activos con una cuenta contable '
                'disponible.'
            : 'Elige con qué método entregaste el anticipo.';
      });
      return;
    }
    final paymentAccountId = method?['account_id']?.toString().trim() ?? '';
    if (paymentAccountId.isEmpty) {
      setState(() {
        _validationError =
            'El método elegido no tiene una cuenta contable activa.';
      });
      return;
    }
    if (_selectedMethodRequiresReference &&
        _referenceController.text.trim().isEmpty) {
      setState(() {
        _validationError =
            'Este método exige una referencia antes de registrar el anticipo.';
      });
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final paidAt = DateTime(_paidAt.year, _paidAt.month, _paidAt.day);
    if (paidAt.isAfter(today)) {
      setState(
          () => _validationError = 'La fecha no puede estar en el futuro.');
      return;
    }
    // El motivo escrito es OBLIGATORIO, no una glosa opcional: el código dice
    // la familia («semana corta») y la explicación dice el caso. Sin ella la
    // auditoría no puede reconstruir por qué salió ese dinero.
    final explanation = _reasonController.text.trim();
    if (explanation.isEmpty) {
      setState(() => _validationError = 'Explica en una línea por qué se '
          'entrega este anticipo.');
      return;
    }
    if (explanation.length > 1000) {
      setState(() => _validationError = 'La explicación es demasiado larga: '
          'resúmela en menos de 1.000 caracteres.');
      return;
    }
    // El último día trabajado define la semana corta. Va exactamente con ese
    // motivo: exigirlo en los otros dos inventaría un dato, y omitirlo acá
    // dejaría al backend sin lo único que distingue el caso.
    final workEndedOn = _needsWorkEndedOn ? _workEndedOn : null;
    if (_needsWorkEndedOn && workEndedOn == null) {
      setState(() => _validationError = 'Indica el último día trabajado de '
          'esta semana corta.');
      return;
    }
    if (workEndedOn != null &&
        DateTime(workEndedOn.year, workEndedOn.month, workEndedOn.day)
            .isAfter(today)) {
      setState(() => _validationError = 'El último día trabajado no puede '
          'estar en el futuro.');
      return;
    }
    final voucher = widget.voucher;
    _pop(
      PayrollAdvanceIntent(
        employeeId: employeeId,
        employeeName: _employeeName,
        amount: _amount,
        paymentMethodId: methodId,
        paymentAccountId: paymentAccountId,
        paidAt: _paidAt,
        operationKey: _operationKey,
        reasonCode: _reasonCode,
        reasonExplanation: explanation,
        workEndedOn: workEndedOn,
        originalReceipt: _receipt,
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        // `notes` ya NO lleva el motivo: éste viaja tipado en
        // `reasonExplanation` y el backend lo guarda aparte. Acá queda sólo el
        // ORIGEN, que es lo que la nota siempre quiso decir.
        notes: _originNote(voucher),
      ),
    );
  }

  /// `Registrado desde la semana 07 – 13 jul.`
  ///
  /// **Sólo el origen.** Antes esta nota concatenaba motivo y origen en un
  /// texto libre porque el backend no tenía dónde poner el motivo; con `v3` sí
  /// lo tiene, y mezclarlos volvía a hacer imposible separarlos después.
  String _originNote(PayrollVoucher? voucher) {
    final origin = voucher == null
        ? 'registrado desde el centro de nóminas'
        : 'registrado desde la semana '
            '${formatPayrollWeekRange(voucher.periodStart, voucher.periodEnd)}';
    return '${_capitalize(origin)}.';
  }

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  @override
  Widget build(BuildContext context) {
    // 5h se implementa con el vocabulario montado de Nóminas, no con
    // `theme.textTheme`/`colorScheme` crudos: los tokens claros del turno 4
    // —ratificados por el turno 8— viven en `PayrollVisualTokens`, y usarlos
    // directamente es lo que hace que este formulario se lea como el resto del
    // módulo en los seis presets y en los dos brillos.
    final visual = PayrollVisualTokens.of(context);

    return PopScope(
      canPop: _allowPop || !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _requestClose();
      },
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.line == null
                          ? 'Registrar anticipo'
                          : 'Anticipo para $_employeeName',
                      style: visual.sectionTitle,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.voucher == null
                          ? _employeeId == null
                              ? 'Elige una persona y registra dinero entregado '
                                  'antes de liquidar una semana.'
                              : 'Registra dinero entregado a $_employeeName '
                                  'antes de liquidar una semana.'
                          : 'Semana '
                              '${formatPayrollWeekRange(widget.voucher!.periodStart, widget.voucher!.periodEnd)}',
                      style: visual.monoS.copyWith(fontSize: 10.5),
                    ),
                    const SizedBox(height: 14),
                    // `E-04 · VbNotice`, el owner compartido del aviso. Antes
                    // era un `Container` con `surfaceContainerHighest` y radio
                    // 10 a mano — una variante local de un control que ya
                    // existe bajo su id.
                    const VbNotice(
                      title: 'El anticipo queda en el registro de la persona',
                      body: 'Podrá aplicarse a una nómina posterior. No cambia '
                          'horas, tarifas ni totales para hacerlos cuadrar.',
                    ),
                    if (widget.line == null) ...[
                      const SizedBox(height: 18),
                      _buildEmployeeSelector(),
                    ],
                    const SizedBox(height: 18),
                    TextField(
                      key: const Key('payroll-advance-amount'),
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      autofocus: widget.line != null || _employeeId != null,
                      inputFormatters: const [ClpAmountInputFormatter()],
                      onChanged: (_) => setState(() {
                        _validationError = null;
                        _isDirty = true;
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Monto entregado',
                        prefixText: '\$ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'payroll-advance-method-${_methodId ?? 'none'}',
                      ),
                      initialValue: _methodId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Método y cuenta de entrega',
                      ),
                      items: [
                        for (final method in _activePaymentMethods)
                          DropdownMenuItem<String>(
                            value: method['id']?.toString(),
                            child: Text(
                              _paymentMethodOptionLabel(
                                method,
                                _activePaymentMethods,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _activePaymentMethods.isEmpty
                          ? null
                          : (value) => setState(() {
                                _methodId = value;
                                _validationError = null;
                                _isDirty = true;
                              }),
                    ),
                    if (_activePaymentMethods.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'No hay métodos de pago activos con una cuenta '
                        'contable disponible. Configura uno antes de registrar '
                        'el anticipo.',
                        key: const Key(
                          'payroll-advance-no-valid-payment-method',
                        ),
                        style: visual.bodyS.copyWith(
                          color: visual.dangerFg,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de entrega',
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(formatPayrollDate(_paidAt))),
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 17,
                              color: visual.inkMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // `5h` · **qué clase de anticipo es**, antes de por qué.
                    // El frame propone una lista corta de motivos y ahora sí
                    // existe dominio detrás: `v3` guarda un `reason_code`
                    // tipado con exactamente estos tres valores. Hasta `v2`
                    // esto era texto libre porque el esquema no tenía dónde
                    // ponerlo; ya no.
                    VbShortSelect<PayrollAdvanceReasonCode>(
                      key: const Key('payroll-advance-reason-code'),
                      label: 'Tipo de anticipo',
                      sheetTitle: 'Tipo de anticipo',
                      value: _reasonCode,
                      options: const <VbShortSelectOption<
                          PayrollAdvanceReasonCode>>[
                        VbShortSelectOption(
                          value: PayrollAdvanceReasonCode.requestedAdvance,
                          label: 'Solicitud de anticipo',
                        ),
                        VbShortSelectOption(
                          value: PayrollAdvanceReasonCode.shortWorkweek,
                          label: 'Semana corta',
                        ),
                        VbShortSelectOption(
                          value: PayrollAdvanceReasonCode.other,
                          label: 'Otro',
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _reasonCode = value;
                        _validationError = null;
                        _isDirty = true;
                        // Cambiar de motivo no deja colgado un dato que ya no
                        // aplica: la fecha de término es de la semana corta.
                        if (!_needsWorkEndedOn) _workEndedOn = null;
                      }),
                    ),
                    if (_needsWorkEndedOn) ...[
                      const SizedBox(height: 12),
                      // «Último día trabajado», no «fecha de término»: lo que
                      // el operador sabe es hasta cuándo vino la persona, y la
                      // semana no termina — se liquida corta.
                      InkWell(
                        key: const Key('payroll-advance-work-ended-on'),
                        onTap: _pickWorkEndedOn,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Último día trabajado',
                            helperText: 'La semana se liquida hasta este día.',
                            helperMaxLines: 2,
                            errorText: _isDirty && _workEndedOn == null
                                ? 'Falta indicarlo'
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _workEndedOn == null
                                      ? 'Elegir día'
                                      : formatPayrollDate(_workEndedOn!),
                                  style: _workEndedOn == null
                                      ? visual.bodyM
                                          .copyWith(color: visual.inkFaint)
                                      : null,
                                ),
                              ),
                              Icon(
                                Icons.event_busy_rounded,
                                size: 17,
                                color: visual.inkMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // La explicación es OBLIGATORIA: el código de arriba dice
                    // la familia, esto dice el caso. El ledger ya tenía columna
                    // `MOTIVO` y el formulario no tenía dónde escribirla —
                    // mandaba siempre la misma frase de relleno y todos los
                    // anticipos se veían iguales en el historial.
                    TextField(
                      key: const Key('payroll-advance-reason'),
                      controller: _reasonController,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {
                        _validationError = null;
                        _isDirty = true;
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Explicación',
                        helperText:
                            'Se ve en el historial de la persona y en el '
                            'detalle del pago.',
                        // `helperText` es de UNA línea por defecto y a 430 se
                        // cortaba con puntos suspensivos: la frase moría justo
                        // donde explicaba para qué sirve el campo.
                        helperMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReceiptRow(
                      receipt: _receipt,
                      busy: _pickingReceipt,
                      onPick: _pickReceipt,
                      onRemove: () => setState(() {
                        _receipt = null;
                        _isDirty = true;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _referenceController,
                      onChanged: (_) => setState(() {
                        _validationError = null;
                        _isDirty = true;
                      }),
                      decoration: InputDecoration(
                        labelText: _selectedMethodRequiresReference
                            ? 'Referencia (obligatoria)'
                            : 'Referencia (opcional)',
                      ),
                    ),
                    if (_validationError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _validationError!,
                        style: visual.bodyS.copyWith(color: visual.dangerFg),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            PayrollMoneyBar(
              figures: [
                PayrollMoneyFigure(
                  label: 'Anticipo',
                  amount: _amount,
                  emphasis: true,
                  isPrimary: true,
                ),
              ],
              primaryAction: PayrollPrimaryAction(
                label: 'Registrar anticipo',
                icon: Icons.savings_outlined,
                onPressed: _activePaymentMethods.isEmpty ? null : _submit,
              ),
              secondaryAction: PayrollSecondaryAction(
                label: 'Cancelar',
                icon: Icons.close_rounded,
                onPressed: _requestClose,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeSelector() {
    final employees = _selectableEmployees;
    if (employees.length <= 7) {
      return DropdownButtonFormField<String>(
        key: const Key('payroll-advance-employee-select'),
        initialValue: _employeeId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Persona',
          helperText: employees.isEmpty
              ? 'No hay trabajadores activos disponibles.'
              : null,
        ),
        items: [
          for (final employee in employees)
            DropdownMenuItem<String>(
              value: employee['id']?.toString(),
              child: Text(
                _employeeOptionLabel(employee),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: employees.isEmpty ? null : _selectEmployee,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return DropdownMenu<String>(
          key: const Key('payroll-advance-employee-search'),
          width: constraints.maxWidth,
          menuHeight: 320,
          initialSelection: _employeeId,
          label: const Text('Persona'),
          hintText: 'Buscar por nombre o RUT',
          enableFilter: true,
          enableSearch: true,
          requestFocusOnTap: true,
          dropdownMenuEntries: [
            for (final employee in employees)
              DropdownMenuEntry<String>(
                value: employee['id']!.toString(),
                label: _employeeOptionLabel(employee),
              ),
          ],
          onSelected: _selectEmployee,
        );
      },
    );
  }
}

/// `5h` · el comprobante original: elegir, ver, quitar o reemplazar **antes**
/// de enviar. Nada se sube acá.
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.receipt,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final PayrollAdvanceReceiptDraft? receipt;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final current = receipt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Comprobante original (opcional)',
          style: visual.label.copyWith(fontSize: 11.5),
        ),
        const SizedBox(height: 6),
        if (current == null)
          OutlinedButton.icon(
            key: const Key('payroll-advance-pick-receipt'),
            onPressed: busy ? null : onPick,
            icon: const Icon(Icons.attach_file_rounded, size: 17),
            label: const Text('Adjuntar comprobante'),
          )
        else
          Container(
            key: const Key('payroll-advance-receipt-chip'),
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: BoxDecoration(
              color: visual.surfaceSunken,
              borderRadius: BorderRadius.circular(PayrollTokens.rField),
              border: Border.all(color: visual.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: visual.inkMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        current.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.bodyM.copyWith(fontSize: 12),
                      ),
                      // El peso es la única prueba en pantalla de que el
                      // archivo se leyó de verdad y no quedó en el nombre.
                      Text(
                        _weightLabel(current.bytes.length),
                        style: visual.monoS.copyWith(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const Key('payroll-advance-replace-receipt'),
                  onPressed: busy ? null : onPick,
                  child: const Text('Reemplazar'),
                ),
                IconButton(
                  key: const Key('payroll-advance-remove-receipt'),
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  color: visual.inkMuted,
                  constraints: const BoxConstraints.tightFor(
                    width: PayrollTokens.touchMin,
                    height: PayrollTokens.touchMin,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Se guarda como respaldo inmutable sólo si el anticipo se registra.',
          style: visual.bodyS.copyWith(fontSize: 10.5, color: visual.inkFaint),
        ),
      ],
    );
  }

  static String _weightLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
