import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/payment_method.dart';
import '../../../shared/models/payment_terminal_profile.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/payment_terminal_profile_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../accounting/models/account.dart';
import '../../accounting/services/accounting_service.dart';
import '../../accounting/utils/bank_ledger_account_policy.dart';

class PaymentTerminalsSettingsPage extends StatefulWidget {
  const PaymentTerminalsSettingsPage({super.key});

  @override
  State<PaymentTerminalsSettingsPage> createState() =>
      _PaymentTerminalsSettingsPageState();
}

class _PaymentTerminalsSettingsPageState
    extends State<PaymentTerminalsSettingsPage> {
  PaymentTerminalProfileService? _service;
  String? _selectedId;
  PaymentTerminalProfile? _newDraft;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service != null) return;
    _service = PaymentTerminalProfileService(
      database: context.read<DatabaseService>(),
    )..addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([
        _service!.load(),
        context.read<AccountingService>().initialize(),
      ]);
      if (!mounted || _selectedId != null || _service!.profiles.isEmpty) return;
      setState(() => _selectedId = _service!.profiles.first.id);
    });
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    _service?.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final accounts = context
        .watch<AccountingService>()
        .accounts
        .where((account) => account.isActive)
        .toList(growable: false)
      ..sort((left, right) => left.code.compareTo(right.code));
    final bankAccounts = BankLedgerAccountPolicy.activeBankAccounts(accounts);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => ReturnNavigation.close(
            context,
            fallbackRoute: '/settings',
          ),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Terminales y abonos'),
        actions: [
          TextButton.icon(
            key: const Key('payment-terminal-add'),
            onPressed:
                bankAccounts.isEmpty ? null : () => _startNew(bankAccounts),
            icon: const Icon(Icons.add),
            label: const Text('Nuevo terminal'),
          ),
        ],
      ),
      body: service == null || service.isLoading
          ? const Center(child: BrandedLoading())
          : service.error != null && service.profiles.isEmpty
              ? _ErrorState(
                  message: service.error!,
                  onRetry: service.load,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final selected = _selectedProfile(service);
                    if (constraints.maxWidth < 800) {
                      return _CompactTerminalWorkspace(
                        profiles: service.profiles,
                        selectedId: _selectedId,
                        isCreating: _newDraft != null,
                        onSelected: _select,
                        editor: _buildEditor(selected, accounts),
                      );
                    }
                    return Row(
                      children: [
                        Flexible(
                          flex: 2,
                          child: _TerminalProfileList(
                            profiles: service.profiles,
                            selectedId: _selectedId,
                            onSelected: _select,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Flexible(
                          flex: 5,
                          child: _buildEditor(selected, accounts),
                        ),
                      ],
                    );
                  },
                ),
    );
  }

  PaymentTerminalProfile? _selectedProfile(
    PaymentTerminalProfileService service,
  ) {
    if (_newDraft != null) return _newDraft;
    for (final profile in service.profiles) {
      if (profile.id == _selectedId) return profile;
    }
    return service.profiles.firstOrNull;
  }

  Widget _buildEditor(
    PaymentTerminalProfile? selected,
    List<Account> accounts,
  ) {
    if (BankLedgerAccountPolicy.activeBankAccounts(accounts).isEmpty) {
      return const _EmptyEditor(
        icon: Icons.account_balance_outlined,
        message: 'Activa una cuenta bancaria antes de configurar terminales.',
      );
    }
    if (selected == null) {
      return const _EmptyEditor(
        icon: Icons.point_of_sale_outlined,
        message: 'Crea un terminal para configurar sus abonos.',
      );
    }
    return _PaymentTerminalEditor(
      key: ValueKey(selected.id ?? 'new-terminal'),
      profile: selected,
      accounts: accounts,
      isSaving: _service!.isSaving,
      errorMessage: _service!.error,
      onSave: (profile) async {
        final saved = await _service!.save(profile);
        if (!mounted || saved == null) return;
        await context.read<PaymentMethodService>().refresh();
        setState(() {
          _newDraft = null;
          _selectedId = saved.id;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Terminal y condiciones guardados.')),
          );
        }
      },
    );
  }

  void _select(String id) {
    setState(() {
      _newDraft = null;
      _selectedId = id;
    });
  }

  void _startNew(List<Account> accounts) {
    final today = DateTime.now();
    setState(() {
      _selectedId = null;
      _newDraft = PaymentTerminalProfile(
        providerCode: 'nuevo_proveedor',
        providerName: 'Nuevo proveedor',
        terminalName: 'Nuevo terminal',
        settlementAccountId: accounts.first.id!,
        descriptorPatterns: const ['descriptor cartola'],
        terms: [
          PaymentTerminalTerm(
            instrument: PaymentCardInstrument.debit,
            commissionRateBps: 0,
            settlementBusinessDays: 1,
            effectiveFrom: today,
          ),
          PaymentTerminalTerm(
            instrument: PaymentCardInstrument.credit,
            commissionRateBps: 0,
            settlementBusinessDays: 2,
            effectiveFrom: today,
          ),
        ],
      );
    });
  }
}

class _TerminalProfileList extends StatelessWidget {
  const _TerminalProfileList({
    required this.profiles,
    required this.selectedId,
    required this.onSelected,
  });

  final List<PaymentTerminalProfile> profiles;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Perfiles de terminal',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Cada terminal publica sus propios métodos de débito y crédito.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        for (final profile in profiles)
          Card(
            child: ListTile(
              selected: profile.id == selectedId,
              onTap: () => onSelected(profile.id!),
              leading: const Icon(Icons.point_of_sale_outlined),
              title: Text(profile.terminalName),
              subtitle: Text(profile.providerName),
              trailing: VbStatusBadge(
                label: profile.isActive ? 'Activo' : 'Inactivo',
                tone: profile.isActive
                    ? VbStatusTone.success
                    : VbStatusTone.neutral,
              ),
            ),
          ),
      ],
    );
  }
}

class _CompactTerminalWorkspace extends StatelessWidget {
  const _CompactTerminalWorkspace({
    required this.profiles,
    required this.selectedId,
    required this.isCreating,
    required this.onSelected,
    required this.editor,
  });

  final List<PaymentTerminalProfile> profiles;
  final String? selectedId;
  final bool isCreating;
  final ValueChanged<String> onSelected;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (profiles.isNotEmpty && !isCreating)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: DropdownButtonFormField<String>(
              key: ValueKey(selectedId),
              initialValue: selectedId ?? profiles.first.id,
              decoration: const InputDecoration(labelText: 'Terminal'),
              items: profiles
                  .map((profile) => DropdownMenuItem(
                        value: profile.id,
                        child: Text(
                          '${profile.providerName} · ${profile.terminalName}',
                        ),
                      ))
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
            ),
          ),
        Expanded(child: editor),
      ],
    );
  }
}

class _PaymentTerminalEditor extends StatefulWidget {
  const _PaymentTerminalEditor({
    super.key,
    required this.profile,
    required this.accounts,
    required this.isSaving,
    required this.errorMessage,
    required this.onSave,
  });

  final PaymentTerminalProfile profile;
  final List<Account> accounts;
  final bool isSaving;
  final String? errorMessage;
  final Future<void> Function(PaymentTerminalProfile profile) onSave;

  @override
  State<_PaymentTerminalEditor> createState() => _PaymentTerminalEditorState();
}

class _PaymentTerminalEditorState extends State<_PaymentTerminalEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _providerCode;
  late final TextEditingController _providerName;
  late final TextEditingController _terminalName;
  late final TextEditingController _merchantReference;
  late final TextEditingController _descriptors;
  late String _accountId;
  late bool _isActive;
  late PaymentTerminalTerm _debit;
  late PaymentTerminalTerm _credit;

  List<Account> get _bankAccounts => widget.accounts
      .where(
        (account) => BankLedgerAccountPolicy.isBankAccount(
          account,
          widget.accounts,
        ),
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _providerCode = TextEditingController(text: profile.providerCode);
    _providerName = TextEditingController(text: profile.providerName);
    _terminalName = TextEditingController(text: profile.terminalName);
    _merchantReference = TextEditingController(text: profile.merchantReference);
    _descriptors = TextEditingController(
      text: profile.descriptorPatterns.join(', '),
    );
    _accountId = profile.settlementAccountId;
    _isActive = profile.isActive;
    final today = DateTime.now();
    _debit = profile.termFor(PaymentCardInstrument.debit) ??
        PaymentTerminalTerm(
          instrument: PaymentCardInstrument.debit,
          commissionRateBps: 0,
          settlementBusinessDays: 1,
          effectiveFrom: today,
        );
    _credit = profile.termFor(PaymentCardInstrument.credit) ??
        PaymentTerminalTerm(
          instrument: PaymentCardInstrument.credit,
          commissionRateBps: 0,
          settlementBusinessDays: 2,
          effectiveFrom: today,
        );
  }

  @override
  void dispose() {
    _providerCode.dispose();
    _providerName.dispose();
    _terminalName.dispose();
    _merchantReference.dispose();
    _descriptors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.profile.id == null
                ? 'Nuevo terminal'
                : widget.profile.terminalName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'El método elegido en una venta identifica el terminal y la regla '
            'de abono que usará la conciliación bancaria.',
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 12),
            VbNotice(
              title: 'No se guardó la configuración',
              body: widget.errorMessage,
              tone: VbNoticeTone.danger,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FieldBox(
                child: TextFormField(
                  controller: _providerName,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                  validator: (value) => _boundedRequired(value, 2, 80),
                ),
              ),
              _FieldBox(
                child: TextFormField(
                  controller: _providerCode,
                  enabled: widget.profile.id == null,
                  decoration: const InputDecoration(
                    labelText: 'Código interno',
                    helperText: 'Ej.: transbank o mercadopago_point',
                  ),
                  validator: (value) => RegExp(r'^[a-z][a-z0-9_]{1,39}$')
                          .hasMatch(value?.trim().toLowerCase() ?? '')
                      ? null
                      : 'Usa minúsculas, números y guion bajo',
                ),
              ),
              _FieldBox(
                child: TextFormField(
                  controller: _terminalName,
                  decoration:
                      const InputDecoration(labelText: 'Nombre del terminal'),
                  validator: (value) => _boundedRequired(value, 2, 100),
                ),
              ),
              _FieldBox(
                child: TextFormField(
                  controller: _merchantReference,
                  decoration: const InputDecoration(
                    labelText: 'Código de comercio (opcional)',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) > 120
                      ? 'Máximo 120 caracteres'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(
              labelText: 'Cuenta bancaria de destino',
              helperText:
                  'Cuenta real donde este recaudador deposita sus abonos netos',
            ),
            items: _bankAccounts
                .map((account) => DropdownMenuItem(
                      value: account.id,
                      child: Text('${account.code} · ${account.name}'),
                    ))
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) setState(() => _accountId = value);
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Separación contable del recaudador',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Débito y crédito comparten una cuenta puente exclusiva '
                    'de este perfil. El abono neto se mueve desde esa cuenta '
                    'al banco; las comisiones documentadas usan su propia '
                    'cuenta de gasto.',
                  ),
                  const SizedBox(height: 12),
                  _accountFact(
                    context,
                    'Fondos por recibir',
                    widget.profile.clearingAccountId,
                    'Se creará automáticamente al guardar',
                  ),
                  const Divider(),
                  _accountFact(
                    context,
                    'Comisiones del recaudador',
                    widget.profile.commissionExpenseAccountId,
                    'Se creará automáticamente al guardar',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptors,
            decoration: const InputDecoration(
              labelText: 'Textos que aparecen en la cartola',
              helperText:
                  'Sepáralos por coma. Ej.: Transbank, Abonos débito y crédito',
            ),
            validator: _validatePatterns,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isActive,
            onChanged: (value) => setState(() => _isActive = value),
            title: const Text('Terminal activo'),
            subtitle: const Text(
              'Al desactivarlo deja de ofrecer sus métodos en ventas nuevas.',
            ),
          ),
          const Divider(),
          Text('Condiciones por tipo de tarjeta',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Las revisiones tienen vigencia: los pagos históricos conservan '
            'la condición que regía en la fecha de la venta.',
          ),
          const SizedBox(height: 12),
          _TermEditor(
            label: 'Débito',
            term: _debit,
            onChanged: (term) => _debit = term,
          ),
          const SizedBox(height: 12),
          _TermEditor(
            label: 'Crédito',
            term: _credit,
            onChanged: (term) => _credit = term,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('payment-terminal-save'),
              onPressed: widget.isSaving ? null : _save,
              icon: widget.isSaving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar configuración'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.onSave(
      PaymentTerminalProfile(
        id: widget.profile.id,
        updatedAt: widget.profile.updatedAt,
        providerCode: _providerCode.text.trim().toLowerCase(),
        providerName: _providerName.text.trim(),
        terminalName: _terminalName.text.trim(),
        merchantReference: _merchantReference.text.trim().isEmpty
            ? null
            : _merchantReference.text.trim(),
        clearingAccountId: widget.profile.clearingAccountId,
        commissionExpenseAccountId: widget.profile.commissionExpenseAccountId,
        settlementAccountId: _accountId,
        descriptorPatterns: _patterns(_descriptors.text),
        isActive: _isActive,
        terms: [_debit, _credit],
      ),
    );
  }

  List<String> _patterns(String? value) => (value ?? '')
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.length >= 2)
      .toSet()
      .toList(growable: false);

  String? _boundedRequired(String? value, int minimum, int maximum) {
    final length = value?.trim().length ?? 0;
    if (length < minimum) return 'Ingresa al menos $minimum caracteres';
    return length > maximum ? 'Máximo $maximum caracteres' : null;
  }

  String? _validatePatterns(String? value) {
    final raw = (value ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (raw.isEmpty) return 'Agrega al menos un descriptor de cartola';
    if (raw.length > 20) return 'Usa como máximo 20 descriptores';
    if (raw.any((item) => item.length < 2 || item.length > 120)) {
      return 'Cada descriptor debe tener entre 2 y 120 caracteres';
    }
    return null;
  }

  Widget _accountFact(
    BuildContext context,
    String label,
    String? accountId,
    String fallback,
  ) {
    final account = widget.accounts
        .where((candidate) => candidate.id == accountId)
        .firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.account_tree_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              Text(
                account == null
                    ? fallback
                    : '${account.code} · ${account.name}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TermEditor extends StatefulWidget {
  const _TermEditor({
    required this.label,
    required this.term,
    required this.onChanged,
  });

  final String label;
  final PaymentTerminalTerm term;
  final ValueChanged<PaymentTerminalTerm> onChanged;

  @override
  State<_TermEditor> createState() => _TermEditorState();
}

class _TermEditorState extends State<_TermEditor> {
  late final TextEditingController _commission;
  late final TextEditingController _vat;
  late final TextEditingController _minimumUf;
  late final TextEditingController _settlementDays;
  late final TextEditingController _graceDays;
  late final TextEditingController _tolerance;
  late final TextEditingController _sourceNote;
  late final TextEditingController _sourceUrl;
  late DateTime _effectiveFrom;

  @override
  void initState() {
    super.initState();
    _commission =
        TextEditingController(text: widget.term.commissionPercent.toString());
    _vat = TextEditingController(
        text: widget.term.commissionVatPercent.toString());
    _minimumUf =
        TextEditingController(text: widget.term.minimumCommissionUf.toString());
    _settlementDays = TextEditingController(
      text: widget.term.settlementBusinessDays.toString(),
    );
    _graceDays = TextEditingController(
      text: widget.term.bookingGraceBusinessDays.toString(),
    );
    _tolerance =
        TextEditingController(text: widget.term.amountToleranceClp.toString());
    _sourceNote = TextEditingController(text: widget.term.sourceNote);
    _sourceUrl = TextEditingController(text: widget.term.sourceUrl);
    _effectiveFrom = widget.term.effectiveFrom;
  }

  @override
  void dispose() {
    _commission.dispose();
    _vat.dispose();
    _minimumUf.dispose();
    _settlementDays.dispose();
    _graceDays.dispose();
    _tolerance.dispose();
    _sourceNote.dispose();
    _sourceUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.label,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Vigente desde ${_civil(_effectiveFrom)}'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _numberField(_commission, 'Comisión', '%',
                    decimal: true, maximum: 100),
                _numberField(_vat, 'IVA sobre comisión', '%',
                    decimal: true, maximum: 100),
                _numberField(_minimumUf, 'Comisión mínima', 'UF',
                    decimal: true),
                _numberField(_settlementDays, 'Liberación', 'días hábiles',
                    maximum: 30),
                _numberField(_graceDays, 'Gracia fecha banco', 'días hábiles',
                    maximum: 30),
                _numberField(_tolerance, 'Tolerancia de calce', 'CLP',
                    maximum: 1000000),
              ],
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Fuente y notas contractuales'),
              children: [
                TextFormField(
                  controller: _sourceNote,
                  decoration: const InputDecoration(
                    labelText: 'Nota de la condición',
                    helperText: 'Ej.: contrato particular o tarifa pública',
                  ),
                  maxLength: 500,
                  onChanged: (_) => _publish(),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _sourceUrl,
                  decoration: const InputDecoration(
                    labelText: 'URL de respaldo (opcional)',
                  ),
                  maxLength: 500,
                  validator: _validateSourceUrl,
                  onChanged: (_) => _publish(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    String suffix, {
    bool decimal = false,
    double? maximum,
  }) {
    return _FieldBox(
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        validator: (value) {
          final parsed = double.tryParse((value ?? '').replaceAll(',', '.'));
          if (parsed == null || parsed < 0) return 'Valor inválido';
          return maximum != null && parsed > maximum
              ? 'Máximo ${maximum.toStringAsFixed(0)}'
              : null;
        },
        onChanged: (_) => _publish(),
      ),
    );
  }

  void _publish() {
    widget.onChanged(
      widget.term.copyWith(
        commissionRateBps: (_double(_commission.text) * 100).round(),
        commissionVatBps: (_double(_vat.text) * 100).round(),
        minimumCommissionUf: _double(_minimumUf.text),
        settlementBusinessDays: _integer(_settlementDays.text),
        bookingGraceBusinessDays: _integer(_graceDays.text),
        amountToleranceClp: _integer(_tolerance.text),
        effectiveFrom: _effectiveFrom,
        sourceNote: _sourceNote.text.trim(),
        sourceUrl: _sourceUrl.text.trim(),
      ),
    );
  }

  String? _validateSourceUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? null
        : 'Usa una URL http(s) válida';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() => _effectiveFrom = selected);
    _publish();
  }

  double _double(String value) =>
      double.tryParse(value.replaceAll(',', '.')) ?? 0;
  int _integer(String value) => int.tryParse(value) ?? 0;
  String _civil(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 280,
        child: child,
      );
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
}
