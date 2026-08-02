import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/vb_notice.dart';
import '../../../../shared/widgets/vb_short_select.dart';
import '../../models/hr_models.dart';
import '../../services/payroll_employee_payment_method_command.dart';
import '../theme/payroll_tokens.dart';

/// **5g · Método de pago del trabajador.**
///
/// Frame `handoff-t5/frames/5g.png`, turno 5, `spec.json → frames[5g]`
/// (`geometry.all = "sheet 460"`). Se abre desde la fila (caret) o desde el
/// composer, y **vuelve a lo que se estaba haciendo**: el rótulo del CTA dice a
/// dónde vuelve, que es el punto del frame.
///
/// ### Qué se copió, qué se descartó y qué se adaptó
///
/// **Se copia:** el sheet de 460 con `CÓMO SE LE PAGA` (transferencia /
/// efectivo), los tres campos bancarios, el bloque de «cambio seguro» y el CTA
/// que nombra el retorno.
///
/// **Se descarta el bloque `TITULAR`** —«La cuenta es del propio trabajador» y
/// el titular de terceros—. `employees` no tiene dónde guardarlo:
/// `account_holder_name`/`account_holder_rut` existen sólo en
/// `company_bank_accounts`, que son las cuentas de la empresa. Y el propósito
/// que el frame le da —«permite entender un nombre distinto en la cartola»— ya
/// lo cumple `payroll_beneficiary_aliases`, el owner canónico de los alias del
/// conciliador: agregarlo acá duplicaría ese mecanismo. Marcar «la cuenta es
/// del propio trabajador» sin dónde guardarlo sería afirmar algo que el backend
/// no demuestra.
///
/// **Se descarta la casilla «Aplicar también a las semanas en cola sin
/// pagar»**, y la razón está medida, no supuesta: `_resolvedMethodForLine` es
/// `line.paymentMethodId ?? preferencia del trabajador`, y **las 20 líneas de
/// semanas abiertas de producción tienen `payment_method_id` nulo** (medido el
/// 2026-08-01), así que el cambio alcanza hoy al 100 % de ellas **sin que el
/// operador pueda declinarlo**. Una casilla diría que puede elegir algo que no
/// puede elegir. Lo que sí es cierto —y se conserva del frame— es que los pagos
/// ya registrados no se tocan: las 90 líneas pagadas guardan su propio método.
///
/// **`TIPO` es un select, como dibuja el frame — y acá Design tenía razón.**
/// Una versión anterior de esta hoja lo puso como texto libre «porque el
/// esquema no tiene catálogo». **Era falso**: `employees_bank_account_type_check`
/// admite exactamente `Cuenta Corriente`, `Cuenta Vista` y `Cuenta de Ahorro`.
/// El error de método fue mirar `information_schema.columns` —que dice `text`—
/// y no `pg_constraint`. Las opciones las publica `BankAccountType`, que las
/// toma del constraint; acá no se reescribe la lista.
///
/// **`Cuenta RUT` no puede aparecer**: el frame la usa de ejemplo y la base la
/// rechaza.
///
/// **`BANCO` sí queda como texto libre**, y eso sí está comprobado:
/// `bank_name` no tiene constraint ni catálogo, así que un desplegable
/// obligaría a inventar la lista de bancos.
///
/// **Se adapta el subtítulo.** El frame dice «aplica a todas las semanas
/// futuras», y eso deja fuera la mitad del efecto: también cambia cómo se
/// resuelven las semanas abiertas de hoy.
///
/// **Se adapta el aviso de permiso.** El frame manda a «pedir cambio a RR.HH.»,
/// un destinatario que el modelo no expone. La autoridad real es
/// `can_manage_tenant_users` —`employees_update_managers` exige
/// `can_manage_tenant_hr`, que es esa misma capacidad—, así que el aviso apunta
/// a quien administra trabajadores y usuarios.
@immutable
class PayrollMethodOption {
  const PayrollMethodOption({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  bool get isTransfer => code == 'transfer';
  bool get isCash => code == 'cash';
}

@immutable
class PayrollMethodDraft {
  const PayrollMethodDraft({
    required this.methodId,
    required this.methodCode,
    this.bankName,
    this.bankAccountType,
    this.bankAccountNumber,
  });

  final String methodId;
  final String methodCode;
  final String? bankName;
  final BankAccountType? bankAccountType;
  final String? bankAccountNumber;

  /// `false` con efectivo: la hoja no muestra los campos bancarios, así que
  /// **no tiene nada que decir sobre ellos** y no deben viajar en el UPDATE.
  bool get touchesBankAccount => methodCode == 'transfer';
}

/// Estado de autoridad que la hoja necesita, resuelto por el llamador con el
/// owner canónico (`evaluateErpAuthorization`), no re-derivado acá.
enum PayrollMethodAuthority {
  /// Puede editar y guardar.
  editable,

  /// Puede ver la ficha pero no cambiarla, o la autoridad aún no se resuelve.
  /// **El default conservador es éste**: sin permiso demostrado, sólo lectura.
  readOnly,
}

class PayrollMethodSheet extends StatefulWidget {
  const PayrollMethodSheet({
    super.key,
    required this.employeeName,
    required this.options,
    required this.authority,
    required this.returnLabel,
    required this.confirmLabel,
    this.selectedMethodId,
    this.currentMethodName,
    this.bankName,
    this.bankAccountType,
    this.bankAccountNumber,
    this.recordedPayments = const PayrollRecordedPaymentCount.unavailable(),
    this.showsPreferenceDisagreement = false,
  });

  final String employeeName;

  /// Sólo los métodos que Nóminas acepta. El catálogo del tenant tiene cinco
  /// (`cash`, `transfer`, `check`, `card`, `mercadopago`) pero el módulo sólo
  /// reconoce transferencia y efectivo, así que **las dos opciones del frame
  /// son las correctas** y no se amplían.
  final List<PayrollMethodOption> options;

  final PayrollMethodAuthority authority;

  /// «Vuelves al pago de la S28».
  final String returnLabel;

  /// «Guardar y seguir con el pago».
  final String confirmLabel;

  final String? selectedMethodId;

  /// Nombre del método guardado hoy **aunque Nóminas no lo acepte**.
  ///
  /// Existe porque en producción hay un trabajador cuyo método apunta a
  /// `Cheque`: preseleccionar en silencio una de las dos opciones le cambiaría
  /// el dato sin decírselo a nadie.
  final String? currentMethodName;

  final String? bankName;
  final BankAccountType? bankAccountType;
  final String? bankAccountNumber;

  /// Cuántos pagos ya registrados tiene, **o que no se pudo saber**.
  ///
  /// El default es `unavailable` y no `known(0)` a propósito: quien no pase el
  /// dato **no está afirmando que la persona nunca cobró**. Con `unavailable`
  /// el bloque simplemente no aparece; el aviso sólo se escribe cuando hay un
  /// número contado.
  final PayrollRecordedPaymentCount recordedPayments;

  /// Las dos columnas de preferencia de la ficha se contradicen.
  final bool showsPreferenceDisagreement;

  @override
  State<PayrollMethodSheet> createState() => _PayrollMethodSheetState();
}

class _PayrollMethodSheetState extends State<PayrollMethodSheet> {
  late String? _methodId = widget.selectedMethodId;
  late final TextEditingController _bank =
      TextEditingController(text: widget.bankName ?? '');
  late BankAccountType? _type = widget.bankAccountType;
  late final TextEditingController _number =
      TextEditingController(text: widget.bankAccountNumber ?? '');

  @override
  void dispose() {
    _bank.dispose();
    _number.dispose();
    super.dispose();
  }

  bool get _isReadOnly => widget.authority == PayrollMethodAuthority.readOnly;

  PayrollMethodOption? get _selected {
    for (final option in widget.options) {
      if (option.id == _methodId) return option;
    }
    return null;
  }

  bool get _canSave {
    if (_isReadOnly) return false;
    final selected = _selected;
    if (selected == null) return false;
    if (!selected.isTransfer) return true;
    // Una transferencia sin cuenta no se puede pagar: exigirlo acá evita que
    // el composer vuelva a mandar a esta misma hoja.
    return _bank.text.trim().isNotEmpty && _number.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final selected = _selected;

    // `spec.json → frames[5g].geometry.all` = «sheet 460». Y **460 de ancho
    // real, no un tope**: con sólo `maxWidth` el `Dialog` pasa restricciones
    // sueltas y la columna se encoge a su ancho intrínseco — medido en la app
    // viva: salía a **366**, con los dos campos de abajo apretados contra el
    // borde. Se fija el ancho, acotado por lo que haya disponible para que en
    // compacto no desborde.
    // `spec.json → frames[5g].geometry.all` = «sheet 460», y se declara igual
    // que el diálogo de 5d, que publica el mismo ancho.
    //
    // **Lo que mide la app viva hoy es 424, no 460** (leído del árbol de
    // widgets, no de un color: el diálogo va de x=468 a x=891 a 1360×757).
    // Probado y descartado: fijar `SizedBox(width: 460)` no lo mueve, así que
    // el recorte no está acá sino en el host del diálogo — el mismo que usa
    // 5d. Queda anotado con su número exacto en vez de simulado: subirlo a la
    // fuerza sin entender quién acota sería mover un síntoma.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Builder(
        builder: (context) => DecoratedBox(
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rSheet),
            border: Border.all(color: visual.borderStrong),
            boxShadow: visual.overlay,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Método de pago de ${widget.employeeName}',
                        // **`recordTitle` viene con `onShell`, la tinta del
                        // cromo navy**, y esta hoja se pinta sobre `surface`.
                        // En oscuro las dos son pálidas y no se nota; en claro
                        // el título sale casi invisible sobre blanco — visto en
                        // la app viva el 2026-08-01, no deducido. Se corrige acá
                        // con el mismo recurso que ya usa
                        // `payroll_advances_and_cash_surfaces.dart:1310`. La
                        // causa está en el token y alcanza a otros tres
                        // consumidores: ver §4 del handoff.
                        style: visual.recordTitle.copyWith(color: visual.ink),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        // Adaptado: el frame decía «aplica a todas las semanas
                        // futuras» y eso deja fuera la mitad del efecto.
                        'Se guarda en su ficha y rige desde ahora: alcanza las '
                        'semanas abiertas y las que vengan.',
                        style: visual.bodyS.copyWith(height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_isReadOnly) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: VbNotice(
                      key: ValueKey<String>('payroll-method-read-only'),
                      tone: VbNoticeTone.info,
                      title: 'Puedes ver esta ficha, no cambiarla',
                      body: 'Cambiar cómo se le paga a alguien lo hace quien '
                          'administra trabajadores y usuarios. Pídeselo con el '
                          'dato que falta y esto se resuelve en un minuto.',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (widget.showsPreferenceDisagreement) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: VbNotice(
                      key: ValueKey<String>('payroll-method-disagreement'),
                      tone: VbNoticeTone.warning,
                      title: 'La ficha guarda dos respuestas distintas',
                      body: 'Su método quedó anotado de dos formas que no '
                          'coinciden. Al guardar acá se dejan iguales.',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _section(visual, 'CÓMO SE LE PAGA'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      for (var index = 0;
                          index < widget.options.length;
                          index++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: index == 0 ? 0 : 10),
                            child: _MethodOptionCard(
                              option: widget.options[index],
                              selected: widget.options[index].id == _methodId,
                              enabled: !_isReadOnly,
                              onTap: () => setState(
                                () => _methodId = widget.options[index].id,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_methodId != null && selected == null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: VbNotice(
                      key: const ValueKey<String>('payroll-method-unsupported'),
                      tone: VbNoticeTone.warning,
                      title: 'Hoy tiene ${widget.currentMethodName ?? 'otro '
                          'método'}, que Nóminas no puede pagar',
                      body:
                          'Elige transferencia o efectivo para poder pagarle.',
                    ),
                  ),
                ],
                if (selected?.isTransfer ?? false) ...[
                  const SizedBox(height: 16),
                  _section(visual, 'BANCO'),
                  _field(visual, _bank, 'Nombre del banco'),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TIPO', style: visual.overline),
                              const SizedBox(height: 6),
                              _AccountTypeSelect(
                                value: _type,
                                enabled: !_isReadOnly,
                                onChanged: (value) =>
                                    setState(() => _type = value),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('NÚMERO DE CUENTA', style: visual.overline),
                              const SizedBox(height: 6),
                              _input(
                                visual,
                                _number,
                                'Sólo números',
                                digitsOnly: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.recordedPayments.hasRecordedPayments) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: VbNotice(
                      key: const ValueKey<String>('payroll-method-safe-change'),
                      tone: VbNoticeTone.neutral,
                      title: 'Los pagos ya hechos no se tocan',
                      body: 'Sus ${widget.recordedPayments.value} pagos '
                          'registrados conservan el método y la fecha con que se '
                          'hicieron. El cambio rige desde ahora, y alcanza a '
                          'todas las semanas que todavía no se pagan.',
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Divider(height: 1, color: visual.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.returnLabel,
                          style: visual.bodyS.copyWith(color: visual.inkFaint),
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(_isReadOnly ? 'Cerrar' : 'Cancelar'),
                      ),
                      if (!_isReadOnly) ...[
                        const SizedBox(width: 8),
                        // accent-fill: dialog-action (resolver-owned M3 dialog grammar)
                        FilledButton(
                          key: const ValueKey<String>('payroll-method-save'),
                          onPressed: _canSave
                              ? () => Navigator.of(context).pop(
                                    PayrollMethodDraft(
                                      methodId: selected!.id,
                                      methodCode: selected.code,
                                      bankName: selected.isTransfer
                                          ? _bank.text
                                          : null,
                                      bankAccountType:
                                          selected.isTransfer ? _type : null,
                                      bankAccountNumber: selected.isTransfer
                                          ? _number.text
                                          : null,
                                    ),
                                  )
                              : null,
                          child: Text(widget.confirmLabel),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(PayrollVisualTokens visual, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 7),
      child: Text(label, style: visual.overline),
    );
  }

  Widget _field(
    PayrollVisualTokens visual,
    TextEditingController controller,
    String hint,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: _input(visual, controller, hint),
    );
  }

  Widget _input(
    PayrollVisualTokens visual,
    TextEditingController controller,
    String hint, {
    bool digitsOnly = false,
  }) {
    // **`I-01` mide 34 de alto con `padding:0 11px`**, leído del archivo de la
    // guía — el mismo campo cerrado que S-05. Antes esto salía en ~40 por un
    // `contentPadding` vertical de 11, así que el TIPO y el NÚMERO quedaban a
    // distinta altura en la misma fila apenas el select pasó a ser S-05. Se
    // corrige el que no tenía fuente, no el que sí la tiene.
    return SizedBox(
      height: VbShortSelect.fieldHeight,
      child: TextField(
        controller: controller,
        enabled: !_isReadOnly,
        onChanged: (_) => setState(() {}),
        textAlignVertical: TextAlignVertical.center,
        inputFormatters: digitsOnly
            ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
            : null,
        keyboardType: digitsOnly ? TextInputType.number : TextInputType.text,
        style: visual.bodyM,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            borderSide: BorderSide(color: visual.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            borderSide: BorderSide(color: visual.border),
          ),
        ),
      ),
    );
  }
}

class _MethodOptionCard extends StatelessWidget {
  const _MethodOptionCard({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PayrollMethodOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  String get _caption =>
      option.isTransfer ? 'calza con la cartola' : 'confirmación manual';

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${option.name}, $_caption',
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
          decoration: BoxDecoration(
            color: selected ? visual.surfaceSelected : visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
            border: Border.all(
              color: selected ? visual.accent : visual.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 17,
                color: selected ? visual.accent : visual.inkFaint,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.name, style: visual.labelStrong),
                    const SizedBox(height: 2),
                    Text(
                      _caption,
                      style: visual.bodyS.copyWith(color: visual.inkFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Select del tipo de cuenta: **`S-05` a través de [VbShortSelect]**, con el
/// dominio que publica [BankAccountType].
///
/// Antes era un `DropdownButtonFormField` con su propio estilo. La guía cierra
/// esa deuda con nombre —*«Ninguno sobrevive con estilo propio»*— y el techo de
/// S-05 se cumple con holgura: **cuatro** opciones de un conjunto que sale de
/// un `CHECK` de la base, no del uso.
///
/// La lista **no se escribe acá**: sale del owner, que la toma del constraint
/// de producción. «Sin especificar» existe porque la columna es nullable y hoy
/// los 7 trabajadores la tienen en `NULL`; obligar a elegir inventaría un dato
/// que nadie dio.
class _AccountTypeSelect extends StatelessWidget {
  const _AccountTypeSelect({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final BankAccountType? value;
  final bool enabled;
  final ValueChanged<BankAccountType?> onChanged;

  @override
  Widget build(BuildContext context) {
    return VbShortSelect<BankAccountType?>(
      key: const ValueKey<String>('payroll-method-account-type'),
      value: value,
      semanticLabel: 'Tipo de cuenta',
      sheetTitle: 'Tipo de cuenta',
      options: <VbShortSelectOption<BankAccountType?>>[
        const VbShortSelectOption<BankAccountType?>(
          value: null,
          label: 'Sin especificar',
        ),
        for (final type in BankAccountType.values)
          VbShortSelectOption<BankAccountType?>(
            value: type,
            label: type.label,
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
