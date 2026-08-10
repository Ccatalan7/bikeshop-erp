import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/payroll_tokens.dart';
import 'payroll_accent_action.dart';
import 'payroll_person_avatar.dart';

/// Estado visible del lector de Asistencias.
///
/// [idle] es la selección todavía no consultada; los otros cuatro estados son
/// el contrato explícito de carga de la superficie.
enum PayrollGenerationLoadState { idle, loading, empty, error, success }

/// Composición desktop elegida por el host que abre la tarea secundaria.
///
/// En tablet y teléfono ambas opciones recomponen al mismo workspace de alto
/// completo. La elección nunca cambia callbacks, validación ni persistencia.
enum PayrollGenerationDesktopPresentation { sideSheet, dialog }

/// Semana civil que Payroll solicita al dueño de Asistencias.
@immutable
class PayrollGenerationWeek {
  PayrollGenerationWeek._(DateTime start)
      : start = DateTime(start.year, start.month, start.day);

  factory PayrollGenerationWeek.containing(DateTime date) {
    final civilDate = DateTime(date.year, date.month, date.day);
    return PayrollGenerationWeek._(
      civilDate.subtract(Duration(days: civilDate.weekday - DateTime.monday)),
    );
  }

  final DateTime start;

  DateTime get end => start.add(const Duration(days: 6));

  PayrollGenerationWeek shifted(int weeks) =>
      PayrollGenerationWeek._(start.add(Duration(days: weeks * 7)));

  String get id => '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';

  String get title => 'Semana ${_isoWeekNumber(start)}';

  String get rangeLabel {
    if (start.year != end.year) {
      return '${start.day.toString().padLeft(2, '0')} '
          '${_shortMonth(start.month)} ${start.year} – '
          '${end.day.toString().padLeft(2, '0')} '
          '${_shortMonth(end.month)} ${end.year}';
    }
    if (start.month != end.month) {
      return '${start.day.toString().padLeft(2, '0')} '
          '${_shortMonth(start.month)} – '
          '${end.day.toString().padLeft(2, '0')} '
          '${_shortMonth(end.month)}';
    }
    return '${start.day.toString().padLeft(2, '0')} – '
        '${end.day.toString().padLeft(2, '0')} '
        '${_shortMonth(end.month)}';
  }

  bool contains(DateTime date) {
    final civilDate = DateTime(date.year, date.month, date.day);
    return !civilDate.isBefore(start) && !civilDate.isAfter(end);
  }

  @override
  bool operator ==(Object other) =>
      other is PayrollGenerationWeek && other.start == start;

  @override
  int get hashCode => start.hashCode;

  static int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    final fourthOfJanuary = DateTime(thursday.year, 1, 4);
    final firstWeekMonday = fourthOfJanuary.subtract(
      Duration(days: fourthOfJanuary.weekday - DateTime.monday),
    );
    return 1 + thursday.difference(firstWeekMonday).inDays ~/ 7;
  }

  static String _shortMonth(int month) => const <String>[
        'ene',
        'feb',
        'mar',
        'abr',
        'may',
        'jun',
        'jul',
        'ago',
        'sept',
        'oct',
        'nov',
        'dic',
      ][month - 1];
}

/// Línea del snapshot de Asistencias que se puede ajustar mientras la nómina
/// siga en borrador. La confirmación vuelve inmutable el resultado persistido.
@immutable
class PayrollGenerationWorkerLine {
  const PayrollGenerationWorkerLine({
    required this.workerId,
    required this.name,
    required this.initials,
    required this.hours,
    required this.rateAmount,
    required this.totalAmount,
    this.overtimeHours = 0,
    this.overtimeRateAmount,
    this.isIncluded = true,
  })  : assert(hours >= 0),
        assert(overtimeHours >= 0),
        assert(rateAmount >= 0),
        assert(overtimeRateAmount == null || overtimeRateAmount >= 0),
        assert(totalAmount >= 0);

  final String workerId;
  final String name;
  final String initials;
  final double hours;
  final double overtimeHours;
  final int rateAmount;
  final int? overtimeRateAmount;
  final int totalAmount;
  final bool isIncluded;

  double get totalHours => hours + overtimeHours;
  int get resolvedOvertimeRateAmount =>
      overtimeRateAmount ?? (rateAmount * 1.5).round();
  bool get hasClosedHours => totalHours > 0;

  PayrollGenerationWorkerLine copyWith({
    double? hours,
    int? rateAmount,
    int? overtimeRateAmount,
    int? totalAmount,
    bool? isIncluded,
  }) {
    return PayrollGenerationWorkerLine(
      workerId: workerId,
      name: name,
      initials: initials,
      hours: hours ?? this.hours,
      overtimeHours: overtimeHours,
      rateAmount: rateAmount ?? this.rateAmount,
      overtimeRateAmount: overtimeRateAmount ?? this.overtimeRateAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      isIncluded: isIncluded ?? this.isIncluded,
    );
  }

  PayrollGenerationWorkerLine withDraftValues({
    required double hours,
    required int rateAmount,
    bool updateOvertimeRate = false,
  }) {
    final overtimeRate = overtimeHours <= 0 || !updateOvertimeRate
        ? resolvedOvertimeRateAmount
        : (rateAmount * 1.5).round();
    final amount = (hours * rateAmount + overtimeHours * overtimeRate).round();
    return copyWith(
      hours: hours,
      rateAmount: rateAmount,
      overtimeRateAmount: overtimeRate,
      totalAmount: amount,
    );
  }
}

/// Snapshot editable hasta que el borrador sea confirmado.
@immutable
class PayrollGenerationPreview {
  PayrollGenerationPreview({
    required this.week,
    required List<PayrollGenerationWorkerLine> workers,
    required this.totalAmount,
    required this.sourceSnapshotLabel,
  })  : workers = List<PayrollGenerationWorkerLine>.unmodifiable(workers),
        assert(totalAmount >= 0);

  final PayrollGenerationWeek week;
  final List<PayrollGenerationWorkerLine> workers;
  final int totalAmount;

  /// Evidencia humana del cierre leído, por ejemplo
  /// `Asistencias cerradas · actualización 29/07 10:42`.
  final String sourceSnapshotLabel;

  int get payableWorkerCount => workers
      .where((worker) => worker.isIncluded && worker.totalAmount > 0)
      .length;

  PayrollGenerationPreview copyWithWorkers(
    List<PayrollGenerationWorkerLine> nextWorkers,
  ) {
    return PayrollGenerationPreview(
      week: week,
      workers: nextWorkers,
      totalAmount: nextWorkers
          .where((worker) => worker.isIncluded)
          .fold<int>(0, (sum, worker) => sum + worker.totalAmount),
      sourceSnapshotLabel: sourceSnapshotLabel,
    );
  }
}

/// Intento de guardado. [operationKey] se crea una sola vez por preview y se
/// conserva en reintentos para que el callback pueda ejecutar un writer
/// idempotente.
@immutable
class PayrollGenerationSaveRequest {
  const PayrollGenerationSaveRequest({
    required this.operationKey,
    required this.preview,
  });

  final String operationKey;
  final PayrollGenerationPreview preview;
}

/// Acuse del writer inyectado. La superficie no conoce tablas ni RPCs.
@immutable
class PayrollGenerationSaveResult {
  const PayrollGenerationSaveResult({
    required this.draftId,
    this.replayed = false,
  });

  final String draftId;
  final bool replayed;
}

typedef PayrollGenerationPreviewLoader = Future<PayrollGenerationPreview>
    Function(PayrollGenerationWeek week);
typedef PayrollGenerationDraftSaver = Future<PayrollGenerationSaveResult>
    Function(PayrollGenerationSaveRequest request);

/// Superficie canónica, aislada y responsive para generar o editar un borrador
/// semanal.
///
/// Dirección visual: proyecto Claude Design `ERP Bikeshop UI Mockups`, página
/// `Nóminas - Rediseño`, conceptos 2a/3a (semana, lectura tabular y resumen) y
/// 2e (jerarquía compacta de una decisión). Se reutiliza su gramática mediante
/// [PayrollTokens]. Asistencias entrega el snapshot inicial; el borrador de
/// Nóminas conserva ajustes propios hasta que la semana se confirma.
///
/// El host decide si abre esta pieza como diálogo o side sheet, entrega todos
/// los callbacks y cierra el contenedor en [onClose]. La superficie no navega,
/// no consulta servicios ni escribe base de datos directamente.
class PayrollGenerationSurface extends StatefulWidget {
  const PayrollGenerationSurface({
    super.key,
    required this.initialWeek,
    required this.onGeneratePreview,
    required this.createOperationKey,
    required this.onSaveDraft,
    required this.onClose,
    this.onWeekChanged,
    this.onOpenAttendance,
    this.onSaved,
    this.onOpenSavedDraft,
    this.now,
    this.describePreviewError,
    this.describeSaveError,
    this.initialPreview,
    this.existingDraftId,
    this.desktopPresentation = PayrollGenerationDesktopPresentation.sideSheet,
  });

  final PayrollGenerationWeek initialWeek;
  final PayrollGenerationPreviewLoader onGeneratePreview;
  final String Function() createOperationKey;
  final PayrollGenerationDraftSaver onSaveDraft;
  final FutureOr<void> Function() onClose;
  final ValueChanged<PayrollGenerationWeek>? onWeekChanged;
  final VoidCallback? onOpenAttendance;
  final ValueChanged<PayrollGenerationSaveResult>? onSaved;
  final ValueChanged<PayrollGenerationSaveResult>? onOpenSavedDraft;
  final DateTime Function()? now;
  final String Function(Object error)? describePreviewError;
  final String Function(Object error)? describeSaveError;
  final PayrollGenerationPreview? initialPreview;
  final String? existingDraftId;
  final PayrollGenerationDesktopPresentation desktopPresentation;

  @override
  State<PayrollGenerationSurface> createState() =>
      _PayrollGenerationSurfaceState();
}

class _PayrollGenerationSurfaceState extends State<PayrollGenerationSurface> {
  late PayrollGenerationWeek _week;
  PayrollGenerationLoadState _loadState = PayrollGenerationLoadState.idle;
  PayrollGenerationPreview? _preview;
  PayrollGenerationSaveRequest? _saveRequest;
  PayrollGenerationSaveResult? _saveResult;
  String? _previewError;
  String? _saveError;
  bool _saving = false;
  bool _dirty = false;
  int _generationEpoch = 0;
  final Map<String, TextEditingController> _hoursControllers =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _rateControllers =
      <String, TextEditingController>{};
  final Map<String, String> _inputErrors = <String, String>{};

  bool get _busy => _saving || _loadState == PayrollGenerationLoadState.loading;

  bool get _editingExisting =>
      widget.existingDraftId?.trim().isNotEmpty == true;

  bool get _hasUnsavedPreview => _editingExisting
      ? _dirty && _saveResult == null
      : _preview != null && _saveResult == null;

  bool get _hasInputErrors => _inputErrors.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _week = widget.initialWeek;
    final initialPreview = widget.initialPreview;
    if (initialPreview != null) {
      assert(
        initialPreview.week == widget.initialWeek,
        'El borrador inicial debe corresponder a initialWeek.',
      );
      _loadState = PayrollGenerationLoadState.success;
      _preview = initialPreview;
      _installControllers(initialPreview);
    }
  }

  @override
  void didUpdateWidget(covariant PayrollGenerationSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWeek != widget.initialWeek &&
        !_hasUnsavedPreview &&
        !_busy &&
        _saveResult == null) {
      _week = widget.initialWeek;
      _clearPreviewState();
    }
  }

  @override
  void dispose() {
    _generationEpoch += 1;
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final controller in <TextEditingController>[
      ..._hoursControllers.values,
      ..._rateControllers.values,
    ]) {
      controller.dispose();
    }
    _hoursControllers.clear();
    _rateControllers.clear();
    _inputErrors.clear();
  }

  void _installControllers(PayrollGenerationPreview preview) {
    _disposeControllers();
    for (final worker in preview.workers) {
      _hoursControllers[worker.workerId] = TextEditingController(
        text: _editableHours(worker.hours),
      );
      _rateControllers[worker.workerId] = TextEditingController(
        text: worker.rateAmount.toString(),
      );
    }
  }

  void _clearPreviewState() {
    _loadState = PayrollGenerationLoadState.idle;
    _preview = null;
    _saveRequest = null;
    _saveResult = null;
    _previewError = null;
    _saveError = null;
    _dirty = false;
    _disposeControllers();
  }

  Future<void> _selectWeek(PayrollGenerationWeek next) async {
    if (next == _week || _busy || _saveResult != null) return;
    if (_hasUnsavedPreview) {
      final discard = await _confirmDiscard(
        title: '¿Cambiar de semana?',
        message: 'El preview todavía no está guardado. Si cambias de semana, '
            'tendrás que generarlo nuevamente.',
        confirmLabel: 'Cambiar semana',
      );
      if (!discard || !mounted) return;
    }

    setState(() {
      _week = next;
      _clearPreviewState();
    });
    widget.onWeekChanged?.call(next);
  }

  Future<void> _generatePreview() async {
    if (_busy || _saveResult != null) return;
    final requestedWeek = _week;
    final epoch = ++_generationEpoch;
    setState(() {
      _loadState = PayrollGenerationLoadState.loading;
      _preview = null;
      _saveRequest = null;
      _previewError = null;
      _saveError = null;
    });

    try {
      final preview = await widget.onGeneratePreview(requestedWeek);
      if (!mounted || epoch != _generationEpoch) return;
      if (preview.week != requestedWeek) {
        throw StateError(
          'El preview recibido no corresponde a la semana solicitada.',
        );
      }
      setState(() {
        if (preview.workers.isEmpty) {
          _loadState = PayrollGenerationLoadState.empty;
          _preview = null;
        } else {
          _loadState = PayrollGenerationLoadState.success;
          _preview = preview;
          _installControllers(preview);
        }
      });
    } catch (error) {
      if (!mounted || epoch != _generationEpoch) return;
      setState(() {
        _preview = null;
        _loadState = PayrollGenerationLoadState.error;
        _previewError = widget.describePreviewError?.call(error) ??
            'No pudimos leer el cierre de Asistencias para esta semana.';
      });
    }
  }

  Future<void> _saveDraft() async {
    final preview = _preview;
    if (preview == null || _busy || _saveResult != null || _hasInputErrors) {
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      var request = _saveRequest;
      if (request == null) {
        final operationKey = widget.createOperationKey().trim();
        if (operationKey.isEmpty) {
          throw StateError('La clave idempotente no puede estar vacía.');
        }
        request = PayrollGenerationSaveRequest(
          operationKey: operationKey,
          preview: preview,
        );
        _saveRequest = request;
      }

      final result = await widget.onSaveDraft(request);
      if (!mounted) return;
      setState(() {
        _saveResult = result;
        _saveError = null;
        _dirty = false;
      });
      widget.onSaved?.call(result);
    } catch (error) {
      debugPrint('❌ [PayrollGeneration] guardar borrador: $error');
      if (!mounted) return;
      setState(() {
        _saveError = widget.describeSaveError?.call(error) ??
            'No pudimos guardar el borrador. Puedes reintentar con la misma '
                'operación sin crear otra nómina.';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _requestClose() async {
    if (_busy) return;
    if (_hasUnsavedPreview) {
      final discard = await _confirmDiscard(
        title: _editingExisting
            ? '¿Descartar los cambios?'
            : '¿Descartar este preview?',
        message: _editingExisting
            ? 'Este borrador tiene cambios sin guardar.'
            : 'Todavía no se ha guardado ningún borrador. Puedes seguir '
                'revisándolo o salir sin crear la nómina.',
        confirmLabel:
            _editingExisting ? 'Descartar cambios' : 'Descartar preview',
      );
      if (!discard || !mounted) return;
    }
    await widget.onClose();
  }

  TextEditingController _hoursControllerFor(String workerId) =>
      _hoursControllers[workerId]!;

  TextEditingController _rateControllerFor(String workerId) =>
      _rateControllers[workerId]!;

  String? _inputErrorFor(String workerId, _DraftField field) =>
      _inputErrors['$workerId:${field.name}'];

  void _editWorker(String workerId, _DraftField field, String rawValue) {
    final preview = _preview;
    if (preview == null || _busy || _saveResult != null) return;
    final normalized = field == _DraftField.hours
        ? rawValue.trim().replaceAll(',', '.')
        : rawValue.trim();
    final value = double.tryParse(normalized);
    final key = '$workerId:${field.name}';
    final valid = value != null &&
        value >= 0 &&
        (field == _DraftField.hours || value == value.roundToDouble());

    setState(() {
      _saveRequest = null;
      _saveError = null;
      _dirty = true;
      if (!valid) {
        _inputErrors[key] = field == _DraftField.hours
            ? 'Ingresa horas válidas'
            : 'Ingresa una tarifa válida';
        return;
      }
      _inputErrors.remove(key);
      final nextWorkers = <PayrollGenerationWorkerLine>[
        for (final worker in preview.workers)
          if (worker.workerId != workerId)
            worker
          else
            worker
                .withDraftValues(
                  hours: field == _DraftField.hours ? value : worker.hours,
                  rateAmount: field == _DraftField.rate
                      ? value.round()
                      : worker.rateAmount,
                  updateOvertimeRate: field == _DraftField.rate,
                )
                .copyWith(
                  isIncluded:
                      (field == _DraftField.hours ? value : worker.hours) +
                              worker.overtimeHours >
                          0,
                ),
      ];
      _preview = preview.copyWithWorkers(nextWorkers);
    });
  }

  Future<bool> _confirmDiscard({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (dialogContext) => AlertDialog(
            key: const ValueKey('payroll-generation-discard-dialog'),
            surfaceTintColor: Colors.transparent,
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                key: const ValueKey('payroll-generation-keep-reviewing'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, PayrollTokens.touchMobile),
                ),
                child: const Text('Seguir revisando'),
              ),
              // accent-fill: dialog-action (resolver-owned M3 dialog grammar)
              FilledButton(
                key: const ValueKey('payroll-generation-confirm-discard'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, PayrollTokens.touchMobile),
                ),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= PayrollTokens.bpDesktop;
          final editing = _GenerationEditingBindings(
            hoursControllerFor: _hoursControllerFor,
            rateControllerFor: _rateControllerFor,
            errorFor: _inputErrorFor,
            onChanged: _editWorker,
            enabled: !_busy && _saveResult == null,
          );
          final panel = _GenerationPanel(
            compact: !desktop,
            floatingDialog: desktop &&
                widget.desktopPresentation ==
                    PayrollGenerationDesktopPresentation.dialog,
            week: _week,
            currentWeek: PayrollGenerationWeek.containing(
              widget.now?.call() ?? DateTime.now(),
            ),
            loadState: _loadState,
            preview: _preview,
            previewError: _previewError,
            saveError: _saveError,
            saveResult: _saveResult,
            saving: _saving,
            busy: _busy,
            editingExisting: _editingExisting,
            canSave: !_hasInputErrors,
            editing: editing,
            onPreviousWeek: () => _selectWeek(_week.shifted(-1)),
            onNextWeek: () => _selectWeek(_week.shifted(1)),
            onCurrentWeek: () => _selectWeek(
              PayrollGenerationWeek.containing(
                widget.now?.call() ?? DateTime.now(),
              ),
            ),
            onGeneratePreview: _generatePreview,
            onSaveDraft: _saveDraft,
            onClose: _requestClose,
            onOpenAttendance: widget.onOpenAttendance,
            onOpenSavedDraft: widget.onOpenSavedDraft,
          );

          if (!desktop) {
            return SizedBox.expand(child: panel);
          }

          final maxHeight =
              constraints.hasBoundedHeight ? constraints.maxHeight : 900.0;
          if (widget.desktopPresentation ==
              PayrollGenerationDesktopPresentation.dialog) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  key: const ValueKey('payroll-generation-dialog-host'),
                  width: math.min(720, constraints.maxWidth - 48),
                  height: math.min(820, maxHeight - 48),
                  child: panel,
                ),
              ),
            );
          }

          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              key: const ValueKey('payroll-generation-side-sheet-host'),
              width: math.min(760, constraints.maxWidth),
              height: maxHeight,
              child: panel,
            ),
          );
        },
      ),
    );
  }
}

enum _DraftField { hours, rate }

class _GenerationEditingBindings {
  const _GenerationEditingBindings({
    required this.hoursControllerFor,
    required this.rateControllerFor,
    required this.errorFor,
    required this.onChanged,
    required this.enabled,
  });

  final TextEditingController Function(String workerId) hoursControllerFor;
  final TextEditingController Function(String workerId) rateControllerFor;
  final String? Function(String workerId, _DraftField field) errorFor;
  final void Function(String workerId, _DraftField field, String value)
      onChanged;
  final bool enabled;
}

class _GenerationPanel extends StatelessWidget {
  const _GenerationPanel({
    required this.compact,
    required this.floatingDialog,
    required this.week,
    required this.currentWeek,
    required this.loadState,
    required this.preview,
    required this.previewError,
    required this.saveError,
    required this.saveResult,
    required this.saving,
    required this.busy,
    required this.editingExisting,
    required this.canSave,
    required this.editing,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onCurrentWeek,
    required this.onGeneratePreview,
    required this.onSaveDraft,
    required this.onClose,
    required this.onOpenAttendance,
    required this.onOpenSavedDraft,
  });

  final bool compact;
  final bool floatingDialog;
  final PayrollGenerationWeek week;
  final PayrollGenerationWeek currentWeek;
  final PayrollGenerationLoadState loadState;
  final PayrollGenerationPreview? preview;
  final String? previewError;
  final String? saveError;
  final PayrollGenerationSaveResult? saveResult;
  final bool saving;
  final bool busy;
  final bool editingExisting;
  final bool canSave;
  final _GenerationEditingBindings editing;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onCurrentWeek;
  final VoidCallback onGeneratePreview;
  final VoidCallback onSaveDraft;
  final VoidCallback onClose;
  final VoidCallback? onOpenAttendance;
  final ValueChanged<PayrollGenerationSaveResult>? onOpenSavedDraft;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final radius = compact
        ? BorderRadius.zero
        : floatingDialog
            ? BorderRadius.circular(PayrollTokens.rSheet)
            : const BorderRadius.only(
                topLeft: Radius.circular(PayrollTokens.rSheet),
                bottomLeft: Radius.circular(PayrollTokens.rSheet),
              );
    return Material(
      key: const ValueKey('payroll-generation-panel'),
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visual.surface,
          borderRadius: radius,
          border: compact
              ? null
              : floatingDialog
                  ? Border.all(color: visual.borderStrong)
                  : Border(
                      left: BorderSide(color: visual.borderStrong),
                    ),
          boxShadow: compact ? null : visual.overlay,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _GenerationHeader(
                  busy: busy,
                  editingExisting: editingExisting,
                  onClose: onClose,
                ),
                _WeekSelector(
                  compact: compact,
                  week: week,
                  currentWeek: currentWeek,
                  enabled: !editingExisting && !busy && saveResult == null,
                  onPrevious: onPreviousWeek,
                  onNext: onNextWeek,
                  onCurrent: onCurrentWeek,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('payroll-generation-scroll'),
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 20,
                      16,
                      compact ? 16 : 20,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _AttendanceSourceNotice(
                          onOpenAttendance: onOpenAttendance,
                          editingExisting: editingExisting,
                        ),
                        const SizedBox(height: 16),
                        _GenerationBody(
                          loadState: loadState,
                          preview: preview,
                          errorMessage: previewError,
                          onRetry: onGeneratePreview,
                          onOpenAttendance: onOpenAttendance,
                          editing: editing,
                        ),
                      ],
                    ),
                  ),
                ),
                _GenerationFooter(
                  loadState: loadState,
                  hasPreview: preview != null,
                  saveError: saveError,
                  saveResult: saveResult,
                  saving: saving,
                  editingExisting: editingExisting,
                  canSave: canSave,
                  onGeneratePreview: onGeneratePreview,
                  onSaveDraft: onSaveDraft,
                  onClose: onClose,
                  onOpenSavedDraft: onOpenSavedDraft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenerationHeader extends StatelessWidget {
  const _GenerationHeader({
    required this.busy,
    required this.editingExisting,
    required this.onClose,
  });

  final bool busy;
  final bool editingExisting;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      decoration: BoxDecoration(
        color: visual.surface,
        border: Border(bottom: BorderSide(color: visual.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    editingExisting
                        ? 'Editar borrador de nómina'
                        : 'Generar borrador de nómina',
                    style: visual.sectionTitle.copyWith(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  editingExisting
                      ? 'Ajusta horas y tarifa antes de confirmar la semana.'
                      : 'Revisa y ajusta el cierre antes de guardar el borrador.',
                  style: visual.bodyS,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            key: const ValueKey('payroll-generation-close'),
            onPressed: busy ? null : onClose,
            tooltip: 'Cerrar generación de nómina',
            icon: const Icon(Icons.close_rounded),
            color: visual.inkMuted,
            disabledColor: visual.inkDisabled,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(PayrollTokens.touchMobile),
              maximumSize: const Size.square(PayrollTokens.touchMobile),
              hoverColor: visual.accentSoft,
              focusColor: visual.accentSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector({
    required this.compact,
    required this.week,
    required this.currentWeek,
    required this.enabled,
    required this.onPrevious,
    required this.onNext,
    required this.onCurrent,
  });

  final bool compact;
  final PayrollGenerationWeek week;
  final PayrollGenerationWeek currentWeek;
  final bool enabled;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onCurrent;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final isCurrent = week == currentWeek;
    final weekControl = Row(
      children: <Widget>[
        _WeekArrowButton(
          key: const ValueKey('payroll-generation-previous-week'),
          tooltip: 'Semana anterior',
          icon: Icons.chevron_left_rounded,
          enabled: enabled,
          onPressed: onPrevious,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            label: '${week.title}, ${week.rangeLabel}',
            child: Column(
              children: <Widget>[
                Text(
                  week.title,
                  textAlign: TextAlign.center,
                  style: visual.cardTitle,
                ),
                const SizedBox(height: 2),
                Text(
                  week.rangeLabel,
                  textAlign: TextAlign.center,
                  style: visual.monoS,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _WeekArrowButton(
          key: const ValueKey('payroll-generation-next-week'),
          tooltip: 'Semana siguiente',
          icon: Icons.chevron_right_rounded,
          enabled: enabled,
          onPressed: onNext,
        ),
      ],
    );

    return Container(
      key: const ValueKey('payroll-generation-week-selector'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: visual.surfaceSunken,
        border: Border(bottom: BorderSide(color: visual.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackToday = constraints.maxWidth < 500;
          if (stackToday) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                weekControl,
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('payroll-generation-current-week'),
                  onPressed: enabled && !isCurrent ? onCurrent : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, PayrollTokens.touchMobile),
                    foregroundColor: visual.accent,
                    disabledForegroundColor: visual.inkDisabled,
                    side: BorderSide(
                      color: enabled && !isCurrent
                          ? visual.accentBorder
                          : visual.border,
                    ),
                  ),
                  child: const Text('Hoy'),
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: weekControl),
              const SizedBox(width: 12),
              OutlinedButton(
                key: const ValueKey('payroll-generation-current-week'),
                onPressed: enabled && !isCurrent ? onCurrent : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, PayrollTokens.touchMobile),
                  foregroundColor: visual.accent,
                  disabledForegroundColor: visual.inkDisabled,
                  side: BorderSide(
                    color: enabled && !isCurrent
                        ? visual.accentBorder
                        : visual.border,
                  ),
                ),
                child: const Text('Hoy'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WeekArrowButton extends StatelessWidget {
  const _WeekArrowButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return IconButton.outlined(
      onPressed: enabled ? onPressed : null,
      tooltip: tooltip,
      icon: Icon(icon),
      color: visual.inkMuted,
      disabledColor: visual.inkDisabled,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(PayrollTokens.touchMobile),
        maximumSize: const Size.square(PayrollTokens.touchMobile),
        side: BorderSide(
          color: enabled ? visual.borderStrong : visual.border,
        ),
        hoverColor: visual.accentSoft,
        focusColor: visual.accentSoft,
      ),
    );
  }
}

class _AttendanceSourceNotice extends StatelessWidget {
  const _AttendanceSourceNotice({
    required this.onOpenAttendance,
    required this.editingExisting,
  });

  final VoidCallback? onOpenAttendance;
  final bool editingExisting;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey('payroll-generation-source'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: visual.accentSoft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.accentBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.schedule_rounded,
              size: 19,
              color: visual.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: visual.bodyS.copyWith(
                  color: visual.inkMuted,
                ),
                children: <InlineSpan>[
                  const TextSpan(
                    text: 'Asistencias es la fuente. ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: editingExisting
                        ? 'Este borrador se puede ajustar aquí hasta confirmar '
                            'la semana; no cambia la asistencia original.'
                        : 'Puedes ajustar horas y tarifa en este borrador antes '
                            'de guardarlo; no cambia la asistencia original.',
                  ),
                ],
              ),
            ),
          ),
          if (onOpenAttendance != null) ...<Widget>[
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('payroll-generation-open-attendance'),
              onPressed: onOpenAttendance,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, PayrollTokens.touchMobile),
                foregroundColor: visual.accent,
              ),
              child: const Text('Abrir'),
            ),
          ],
        ],
      ),
    );
  }
}

class _GenerationBody extends StatelessWidget {
  const _GenerationBody({
    required this.loadState,
    required this.preview,
    required this.errorMessage,
    required this.onRetry,
    required this.onOpenAttendance,
    required this.editing,
  });

  final PayrollGenerationLoadState loadState;
  final PayrollGenerationPreview? preview;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback? onOpenAttendance;
  final _GenerationEditingBindings editing;

  @override
  Widget build(BuildContext context) {
    return switch (loadState) {
      PayrollGenerationLoadState.idle => const _GenerationMessage(
          key: ValueKey('payroll-generation-idle'),
          icon: Icons.calendar_month_outlined,
          title: 'Elige la semana que quieres revisar',
          message: 'Generaremos un preview con todas las personas del cierre, '
              'incluidas aquellas que tengan cero horas.',
        ),
      PayrollGenerationLoadState.loading => const _GenerationLoading(),
      PayrollGenerationLoadState.empty => _GenerationMessage(
          key: const ValueKey('payroll-generation-empty'),
          icon: Icons.event_busy_outlined,
          title: 'No hay un cierre disponible para esta semana',
          message: 'No encontramos trabajadores en el cierre de Asistencias. '
              'Revisa la semana o termina su cierre antes de reintentar.',
          actionLabel: onOpenAttendance == null ? null : 'Abrir Asistencias',
          onAction: onOpenAttendance,
        ),
      PayrollGenerationLoadState.error => _GenerationMessage(
          key: const ValueKey('payroll-generation-error'),
          icon: Icons.error_outline_rounded,
          title: 'No pudimos generar el preview',
          message: errorMessage ??
              'La lectura de Asistencias falló. Intenta nuevamente.',
          actionLabel: 'Reintentar',
          onAction: onRetry,
          danger: true,
        ),
      PayrollGenerationLoadState.success => _PreviewContent(
          preview: preview!,
          editing: editing,
        ),
    };
  }
}

class _GenerationMessage extends StatelessWidget {
  const _GenerationMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = danger ? visual.danger : visual.neutral;
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tone.soft,
                borderRadius: BorderRadius.circular(PayrollTokens.rField),
                border: Border.all(color: tone.border),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 21, color: tone.fg),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: visual.sectionTitle,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: visual.bodyS,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, PayrollTokens.touchMobile),
                  foregroundColor: danger ? tone.fg : visual.accent,
                  side: BorderSide(
                    color: danger ? tone.border : visual.accentBorder,
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GenerationLoading extends StatelessWidget {
  const _GenerationLoading();

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey('payroll-generation-loading'),
      constraints: const BoxConstraints(minHeight: 220),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            LinearProgressIndicator(
              minHeight: 3,
              color: visual.accent,
              backgroundColor: visual.accentSoft,
            ),
            const SizedBox(height: 16),
            Text(
              'Leyendo el cierre de Asistencias…',
              textAlign: TextAlign.center,
              style: visual.bodyM,
            ),
            const SizedBox(height: 4),
            Text(
              'La semana y la fuente permanecen visibles mientras cargamos.',
              textAlign: TextAlign.center,
              style: visual.bodyS,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.preview, required this.editing});

  final PayrollGenerationPreview preview;
  final _GenerationEditingBindings editing;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('payroll-generation-success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PreviewSummary(preview: preview),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 650) {
              return _DesktopWorkerPreview(
                workers: preview.workers,
                editing: editing,
              );
            }
            return _CompactWorkerPreview(
              workers: preview.workers,
              editing: editing,
            );
          },
        ),
      ],
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.preview});

  final PayrollGenerationPreview preview;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final peopleLabel = preview.workers.length == 1
        ? '1 trabajador'
        : '${preview.workers.length} trabajadores';
    final payableLabel = preview.payableWorkerCount == 1
        ? '1 con monto'
        : '${preview.payableWorkerCount} con monto';

    return Container(
      key: const ValueKey('payroll-generation-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: visual.surfaceSunken,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 430;
          final description = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('PREVIEW DE LA SEMANA', style: visual.overline),
              const SizedBox(height: 4),
              Text(
                '$peopleLabel · $payableLabel',
                style: visual.labelStrong,
              ),
              const SizedBox(height: 3),
              Text(
                preview.sourceSnapshotLabel,
                style: visual.bodyS.copyWith(fontSize: 10.5),
              ),
            ],
          );
          final total = Column(
            crossAxisAlignment:
                stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: <Widget>[
              Text('TOTAL', style: visual.overline),
              const SizedBox(height: 2),
              Text(
                _formatClp(preview.totalAmount),
                style: visual.numCard,
              ),
            ],
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                description,
                const SizedBox(height: 12),
                total,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: description),
              const SizedBox(width: 16),
              total,
            ],
          );
        },
      ),
    );
  }
}

class _DesktopWorkerPreview extends StatelessWidget {
  const _DesktopWorkerPreview({
    required this.workers,
    required this.editing,
  });

  final List<PayrollGenerationWorkerLine> workers;
  final _GenerationEditingBindings editing;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey('payroll-generation-desktop-table'),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: visual.surfaceSunken,
            child: const _DesktopWorkerGrid(
              identity: _ColumnLabel('PERSONA'),
              hours: _ColumnLabel('HORAS', alignEnd: true),
              rate: _ColumnLabel('TARIFA', alignEnd: true),
              total: _ColumnLabel('TOTAL', alignEnd: true),
            ),
          ),
          for (int index = 0; index < workers.length; index++) ...<Widget>[
            _DesktopWorkerRow(worker: workers[index], editing: editing),
            if (index != workers.length - 1)
              Divider(height: 1, color: visual.border),
          ],
        ],
      ),
    );
  }
}

class _DesktopWorkerRow extends StatelessWidget {
  const _DesktopWorkerRow({required this.worker, required this.editing});

  final PayrollGenerationWorkerLine worker;
  final _GenerationEditingBindings editing;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return ConstrainedBox(
      key: ValueKey('payroll-generation-worker-${worker.workerId}'),
      constraints: const BoxConstraints(minHeight: 62),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: _DesktopWorkerGrid(
          identity: Row(
            children: <Widget>[
              PayrollPersonAvatar(
                personId: worker.workerId,
                initials: worker.initials,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      worker.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: visual.cardTitle,
                    ),
                    if (!worker.hasClosedHours)
                      Text(
                        'Sin horas cerradas',
                        style: visual.bodyS.copyWith(
                          fontSize: 10.5,
                          color: visual.warningFg,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          hours: _WorkerNumberField(
            fieldKey: ValueKey('payroll-generation-hours-${worker.workerId}'),
            semanticsLabel: 'Horas de ${worker.name}',
            controller: editing.hoursControllerFor(worker.workerId),
            unitSuffix: 'h',
            detail: worker.overtimeHours > 0
                ? '+ ${_formatHours(worker.overtimeHours)} HE'
                : null,
            errorText: editing.errorFor(worker.workerId, _DraftField.hours),
            enabled: editing.enabled,
            decimal: true,
            onChanged: (value) =>
                editing.onChanged(worker.workerId, _DraftField.hours, value),
          ),
          rate: _WorkerNumberField(
            fieldKey: ValueKey('payroll-generation-rate-${worker.workerId}'),
            semanticsLabel: 'Tarifa por hora de ${worker.name}',
            controller: editing.rateControllerFor(worker.workerId),
            unitSuffix: '/h',
            detail: worker.overtimeHours > 0
                ? '${_formatClp(worker.resolvedOvertimeRateAmount)}/HE'
                : null,
            errorText: editing.errorFor(worker.workerId, _DraftField.rate),
            enabled: editing.enabled,
            decimal: false,
            onChanged: (value) =>
                editing.onChanged(worker.workerId, _DraftField.rate, value),
          ),
          total: _RightValue(
            _formatClp(worker.totalAmount),
            strong: true,
            muted: !worker.hasClosedHours,
          ),
        ),
      ),
    );
  }
}

class _DesktopWorkerGrid extends StatelessWidget {
  const _DesktopWorkerGrid({
    required this.identity,
    required this.hours,
    required this.rate,
    required this.total,
  });

  final Widget identity;
  final Widget hours;
  final Widget rate;
  final Widget total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(flex: 5, child: identity),
        const SizedBox(width: 12),
        SizedBox(width: 100, child: hours),
        const SizedBox(width: 12),
        SizedBox(width: 135, child: rate),
        const SizedBox(width: 12),
        SizedBox(width: 112, child: total),
      ],
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.label, {this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(label, style: visual.overline),
    );
  }
}

class _RightValue extends StatelessWidget {
  const _RightValue(
    this.value, {
    this.strong = false,
    this.muted = false,
  });

  final String value;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        value,
        maxLines: 1,
        textAlign: TextAlign.right,
        style: (strong ? visual.numRow : visual.monoM).copyWith(
          color: muted ? visual.inkFaint : visual.ink,
        ),
      ),
    );
  }
}

class _WorkerNumberField extends StatelessWidget {
  const _WorkerNumberField({
    required this.fieldKey,
    required this.semanticsLabel,
    required this.controller,
    required this.errorText,
    required this.enabled,
    required this.decimal,
    required this.onChanged,
    required this.unitSuffix,
    this.label,
    this.detail,
  });

  final Key fieldKey;
  final String semanticsLabel;
  final TextEditingController controller;
  final String? label;
  final String unitSuffix;
  final String? detail;
  final String? errorText;
  final bool enabled;
  final bool decimal;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final pattern =
        decimal ? RegExp(r'^\d*(?:[\.,]\d{0,2})?$') : RegExp(r'^\d*$');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          textField: true,
          label: semanticsLabel,
          child: TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            inputFormatters: <TextInputFormatter>[
              TextInputFormatter.withFunction((oldValue, newValue) =>
                  pattern.hasMatch(newValue.text) ? newValue : oldValue),
            ],
            onChanged: onChanged,
            style: visual.monoM.copyWith(color: visual.ink),
            decoration: InputDecoration(
              isDense: true,
              labelText: label,
              prefixText: decimal ? null : r'$ ',
              suffixText: ' $unitSuffix',
              suffixStyle: visual.monoS.copyWith(color: visual.inkMuted),
              errorText: errorText,
              errorMaxLines: 2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PayrollTokens.rField),
              ),
            ),
          ),
        ),
        if (detail != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            detail!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: visual.monoS.copyWith(color: visual.inkMuted),
          ),
        ],
      ],
    );
  }
}

class _CompactWorkerPreview extends StatelessWidget {
  const _CompactWorkerPreview({
    required this.workers,
    required this.editing,
  });

  final List<PayrollGenerationWorkerLine> workers;
  final _GenerationEditingBindings editing;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey('payroll-generation-compact-list'),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int index = 0; index < workers.length; index++) ...<Widget>[
            _CompactWorkerRow(worker: workers[index], editing: editing),
            if (index != workers.length - 1)
              Divider(height: 1, color: visual.border),
          ],
        ],
      ),
    );
  }
}

class _CompactWorkerRow extends StatelessWidget {
  const _CompactWorkerRow({required this.worker, required this.editing});

  final PayrollGenerationWorkerLine worker;
  final _GenerationEditingBindings editing;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return ConstrainedBox(
      key: ValueKey('payroll-generation-worker-${worker.workerId}'),
      constraints: const BoxConstraints(minHeight: 82),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PayrollPersonAvatar(
              personId: worker.workerId,
              initials: worker.initials,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          worker.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: visual.cardTitle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatClp(worker.totalAmount),
                        textAlign: TextAlign.right,
                        style: visual.numRow.copyWith(
                          color: worker.hasClosedHours
                              ? visual.ink
                              : visual.inkFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _WorkerNumberField(
                          fieldKey: ValueKey(
                            'payroll-generation-hours-${worker.workerId}',
                          ),
                          semanticsLabel: 'Horas de ${worker.name}',
                          controller:
                              editing.hoursControllerFor(worker.workerId),
                          label: 'Horas',
                          unitSuffix: 'h',
                          detail: worker.overtimeHours > 0
                              ? '+ ${_formatHours(worker.overtimeHours)} HE'
                              : null,
                          errorText: editing.errorFor(
                            worker.workerId,
                            _DraftField.hours,
                          ),
                          enabled: editing.enabled,
                          decimal: true,
                          onChanged: (value) => editing.onChanged(
                            worker.workerId,
                            _DraftField.hours,
                            value,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _WorkerNumberField(
                          fieldKey: ValueKey(
                            'payroll-generation-rate-${worker.workerId}',
                          ),
                          semanticsLabel: 'Tarifa por hora de ${worker.name}',
                          controller:
                              editing.rateControllerFor(worker.workerId),
                          label: 'Tarifa',
                          unitSuffix: '/h',
                          detail: worker.overtimeHours > 0
                              ? '${_formatClp(worker.resolvedOvertimeRateAmount)}/HE'
                              : null,
                          errorText: editing.errorFor(
                            worker.workerId,
                            _DraftField.rate,
                          ),
                          enabled: editing.enabled,
                          decimal: false,
                          onChanged: (value) => editing.onChanged(
                            worker.workerId,
                            _DraftField.rate,
                            value,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _formatWorkerEquation(worker),
                    style: visual.monoS.copyWith(
                      color: visual.inkMuted,
                    ),
                  ),
                  if (!worker.hasClosedHours) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      'Sin horas cerradas · se incluye como \$0',
                      style: visual.bodyS.copyWith(
                        fontSize: 10.5,
                        color: visual.warningFg,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenerationFooter extends StatelessWidget {
  const _GenerationFooter({
    required this.loadState,
    required this.hasPreview,
    required this.saveError,
    required this.saveResult,
    required this.saving,
    required this.editingExisting,
    required this.canSave,
    required this.onGeneratePreview,
    required this.onSaveDraft,
    required this.onClose,
    required this.onOpenSavedDraft,
  });

  final PayrollGenerationLoadState loadState;
  final bool hasPreview;
  final String? saveError;
  final PayrollGenerationSaveResult? saveResult;
  final bool saving;
  final bool editingExisting;
  final bool canSave;
  final VoidCallback onGeneratePreview;
  final VoidCallback onSaveDraft;
  final VoidCallback onClose;
  final ValueChanged<PayrollGenerationSaveResult>? onOpenSavedDraft;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final saved = saveResult != null;
    final primaryLabel = saved
        ? onOpenSavedDraft == null
            ? 'Cerrar'
            : 'Revisar en Nóminas'
        : saving
            ? 'Guardando borrador…'
            : hasPreview
                ? editingExisting
                    ? 'Guardar cambios'
                    : 'Guardar borrador'
                : loadState == PayrollGenerationLoadState.loading
                    ? 'Generando preview…'
                    : loadState == PayrollGenerationLoadState.idle
                        ? 'Generar preview'
                        : 'Reintentar preview';
    final primaryAction = saved
        ? onOpenSavedDraft == null
            ? onClose
            : () => onOpenSavedDraft!(saveResult!)
        : saving || loadState == PayrollGenerationLoadState.loading
            ? null
            : hasPreview && canSave
                ? onSaveDraft
                : hasPreview
                    ? null
                    : onGeneratePreview;

    return Container(
      key: const ValueKey('payroll-generation-footer'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: visual.surface,
        border: Border(top: BorderSide(color: visual.borderStrong)),
        boxShadow: visual.moneyBar,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Tablet/compact hosts can inherit generous global button padding.
          // Stack before the two intrinsic labels compete instead of forcing
          // either action through an overflow or a FittedBox.
          final stackActions = constraints.maxWidth < 640;
          final primary = PayrollAccentAction(
            actionKey: const ValueKey('payroll-generation-primary-action'),
            label: primaryLabel,
            onTap: primaryAction,
            enabled: primaryAction != null,
            height: PayrollTokens.touchMobile,
            fontSize: 13,
            horizontalPadding: 24,
            disabledStyle: PayrollAccentDisabledStyle.neutral,
          );
          final regenerate = hasPreview && !editingExisting && !saving && !saved
              ? OutlinedButton(
                  key: const ValueKey('payroll-generation-regenerate'),
                  onPressed: onGeneratePreview,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, PayrollTokens.touchMobile),
                    foregroundColor: visual.inkMuted,
                    side: BorderSide(color: visual.borderStrong),
                  ),
                  child: const Text('Actualizar preview'),
                )
              : null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (saveError != null) ...<Widget>[
                _FooterNotice(
                  message: saveError!,
                  tone: visual.danger,
                ),
                const SizedBox(height: 8),
              ],
              if (saved) ...<Widget>[
                _FooterNotice(
                  message: saveResult!.replayed
                      ? 'El borrador ya estaba guardado; recuperamos el mismo '
                          'resultado sin duplicarlo.'
                      : 'Borrador guardado. Nóminas todavía no ha registrado '
                          'ningún pago.',
                  tone: visual.success,
                ),
                const SizedBox(height: 8),
              ],
              if (stackActions)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (regenerate != null) ...<Widget>[
                      regenerate,
                      const SizedBox(height: 8),
                    ],
                    primary,
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (regenerate != null) ...<Widget>[
                      regenerate,
                      const SizedBox(width: 8),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 170),
                      child: primary,
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FooterNotice extends StatelessWidget {
  const _FooterNotice({
    required this.message,
    required this.tone,
  });

  final String message;
  final PayrollStateTone tone;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: visual.bodyS.copyWith(color: tone.fg),
      ),
    );
  }
}

String _formatHours(double hours) {
  if (hours == hours.roundToDouble()) return '${hours.toInt()} h';
  return '${hours.toStringAsFixed(1).replaceAll('.', ',')} h';
}

String _editableHours(double hours) {
  if (hours == hours.roundToDouble()) return hours.toInt().toString();
  return hours.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceAll(
        '.',
        ',',
      );
}

String _formatWorkerEquation(PayrollGenerationWorkerLine worker) {
  final regular =
      '${_formatHours(worker.hours)} × ${_formatClp(worker.rateAmount)}/h';
  if (worker.overtimeHours <= 0) return regular;
  return '$regular + ${_formatHours(worker.overtimeHours)} HE × '
      '${_formatClp(worker.resolvedOvertimeRateAmount)}/h';
}

String _formatClp(int amount) {
  final digits = amount.abs().toString();
  final parts = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = math.max(0, end - 3);
    parts.add(digits.substring(start, end));
  }
  final grouped = parts.reversed.join('.');
  return '${amount < 0 ? '−' : ''}\$$grouped';
}
