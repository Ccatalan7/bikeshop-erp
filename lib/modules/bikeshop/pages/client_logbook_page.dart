import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/services/user_management_navigation.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_edit_dock.dart';
import '../../../shared/widgets/vb_segmented.dart' show VbDensity;
import '../../../shared/widgets/vb_sub_tabs.dart';
import '../../crm/services/client_data_draft.dart';
import '../../crm/services/customer_service.dart';
import '../../crm/widgets/client_data_sheet.dart';
import '../../messaging/models/conversation.dart';
import '../../messaging/services/messaging_service.dart';
import '../../messaging/widgets/chat_window.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../models/bikeshop_models.dart';
import '../services/bike_directory_entries.dart';
import '../services/bike_visit_history.dart';
import '../services/bikeshop_service.dart';
import '../widgets/bike_module_style.dart';
import '../widgets/bike_silhouette.dart';
import '../widgets/job_visit_card.dart';
import 'bike_form_dialog.dart';

/// Las pestañas de la página del cliente. **Datos** va primero: es la
/// primera cara del cliente (dueño, 2026-10-03).
enum ClientPageTab { data, activity, invoices, messages }

/// La pestaña que pide un enlace (`?tab=`). Los nombres viejos (pegas,
/// historial, chats) siguen abriendo lo que hoy los reemplaza.
ClientPageTab clientPageTabFor(String? tab) =>
    switch (tab?.trim().toLowerCase()) {
      'actividad' ||
      'trabajos' ||
      'pegas' ||
      'historial' =>
        ClientPageTab.activity,
      'facturas' || 'invoices' => ClientPageTab.invoices,
      'mensajes' || 'chats' => ClientPageTab.messages,
      _ => ClientPageTab.data,
    };

final NumberFormat _money =
    NumberFormat.currency(symbol: r'$', decimalDigits: 0);

/// Una factura que todavía se debe: emitida, no anulada y con saldo.
bool invoiceIsOwed(Invoice invoice) =>
    invoice.status != InvoiceStatus.draft &&
    invoice.status != InvoiceStatus.cancelled &&
    invoice.balance > 0.5;

/// La página de un cliente (`/clientes/:id`), rediseñada el 2026-10-03 a
/// partir del lienzo que aprobó el dueño («sigue con la original con
/// cabecera arriba»).
///
/// Arriba, a todo el ancho, quién es (nombre, contacto, «Editar» y «Nuevo
/// trabajo»), lo que pide atención (la bici que está en el taller, lo que
/// debe) y cinco datos. Debajo, las pestañas **Datos** —sus datos a la vista
/// y editables en su lugar—, **Actividad** —cada trabajo como en la página
/// de la bici, con su factura—, **Facturas** y **Mensajes**, y a la derecha
/// sus bicicletas, que abren su propia página, y sus conversaciones. En
/// teléfono, el mismo orden en una columna.
class ClientLogbookPage extends StatefulWidget {
  const ClientLogbookPage({
    super.key,
    required this.customerId,
    this.initialTab,
    this.initialBikeId,
  });

  final String customerId;
  final String? initialTab;

  /// Un enlace viejo a la bici del cliente: la bici tiene su propia página
  /// y se abre encima.
  final String? initialBikeId;

  @override
  State<ClientLogbookPage> createState() => _ClientLogbookPageState();
}

class _ClientLogbookPageState extends State<ClientLogbookPage> {
  static const _fallbackRoute = '/clientes';

  final MessagingService _messaging = MessagingService();

  ClientRecord? _record;
  List<Bike> _bikes = const [];
  bool _loading = true;
  bool _notFound = false;
  String? _error;

  /// Sólo la carga más reciente publica.
  int _generation = 0;

  List<BikeVisit>? _visits;
  bool _visitsFailed = false;
  List<Invoice>? _invoices;
  bool _invoicesFailed = false;
  List<Conversation>? _chats;
  bool _chatsFailed = false;
  Conversation? _selectedChat;

  late ClientPageTab _tab = clientPageTabFor(widget.initialTab);
  String? _openedBikeId;

  // ── La hoja en edición ──
  ClientDataDraft? _draft;
  final Map<ClientDataField, TextEditingController> _text = {};
  final Map<ClientDataField, FocusNode> _focus = {
    for (final field in ClientDataField.values) field: FocusNode(),
  };
  bool _saving = false;

  /// Después de intentar guardar, cada regla que falta se dice en su dato.
  bool _showProblems = false;
  ({ClientDataField? field, String message})? _saveProblem;
  String? _dockNotice;

  DateTime get _today => DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClientLogbookPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customerId != oldWidget.customerId) {
      // La ruta cambió de cliente debajo de la página (un `go` del buscador):
      // no hay cómo preguntar antes, así que se dice qué se perdió.
      final lost = _hasUnsavedChanges ? _record?.name : null;
      _leaveEdit();
      if (lost != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Los cambios sin guardar de $lost se descartaron.'),
          ));
        });
      }
      setState(() {
        _record = null;
        _bikes = const [];
        _visits = null;
        _invoices = null;
        _chats = null;
        _selectedChat = null;
        _openedBikeId = null;
        _loading = true;
        _tab = clientPageTabFor(widget.initialTab);
      });
      _load();
      return;
    }
    if (widget.initialTab != oldWidget.initialTab) {
      setState(() => _tab = clientPageTabFor(widget.initialTab));
    }
    if (widget.initialBikeId != oldWidget.initialBikeId) {
      _openInitialBike();
    }
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  // ── Lectura ──────────────────────────────────────────────────────────────

  /// [refresh] pide las facturas sin caché: al volver de una factura o de
  /// un pago, lo guardado allá tiene que verse acá.
  Future<void> _load({bool refresh = false}) async {
    final generation = ++_generation;
    bool isCurrent() => mounted && generation == _generation;
    final customers = context.read<CustomerService>();
    final bikeshop = context.read<BikeshopService>();
    setState(() {
      _loading = _record == null;
      _error = null;
    });
    try {
      final record = await customers.getClientRecord(widget.customerId);
      if (!isCurrent()) return;
      if (record == null) {
        setState(() {
          _notFound = true;
          _loading = false;
        });
        return;
      }
      final bikes = await bikeshop.getBikes(customerId: widget.customerId);
      if (!isCurrent()) return;
      setState(() {
        _record = record;
        _bikes = [
          for (final bike in bikes)
            if (bike.customerId == widget.customerId) bike,
        ];
        _notFound = false;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Client page load failed: $error');
      if (!isCurrent()) return;
      setState(() {
        _error = 'No pudimos abrir este cliente.';
        _loading = false;
      });
      return;
    }
    unawaited(_loadVisits(generation));
    unawaited(_loadInvoices(generation, force: refresh));
    unawaited(_loadChats(generation));
    _openInitialBike();
  }

  Map<String, Bike> get _bikesById => {
        for (final bike in _bikes)
          if (bike.id != null) bike.id!: bike,
      };

  Future<void> _loadVisits(int generation) async {
    final record = _record;
    if (record == null || !mounted) return;
    setState(() => _visitsFailed = false);
    try {
      final visits = await loadCustomerVisits(
        context,
        widget.customerId,
        bikesById: _bikesById,
        ownerName: record.name,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _visits = visits);
    } catch (error) {
      debugPrint('Client activity load failed: $error');
      if (!mounted || generation != _generation) return;
      setState(() => _visitsFailed = true);
    }
  }

  Future<void> _loadInvoices(int generation, {bool force = false}) async {
    if (!mounted) return;
    final sales = context.read<SalesService>();
    setState(() => _invoicesFailed = false);
    try {
      final invoices = await sales.getInvoicesForCustomer(
        customerId: widget.customerId,
        forceRefresh: force,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _invoices = [...invoices]..sort((a, b) => b.date.compareTo(a.date));
      });
    } catch (error) {
      debugPrint('Client invoices load failed: $error');
      if (!mounted || generation != _generation) return;
      setState(() => _invoicesFailed = true);
    }
  }

  Future<void> _loadChats(int generation) async {
    if (!mounted) return;
    setState(() => _chatsFailed = false);
    try {
      final chats =
          await _messaging.getConversationsForCustomer(widget.customerId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _chats = chats;
        final selected = _selectedChat;
        _selectedChat = selected == null
            ? null
            : chats.where((chat) => chat.id == selected.id).firstOrNull;
      });
    } catch (error) {
      debugPrint('Client chats load failed: $error');
      if (!mounted || generation != _generation) return;
      setState(() => _chatsFailed = true);
    }
  }

  /// Al volver de otra página (un trabajo, una factura, una bici) se lee
  /// todo de nuevo: lo que se hizo allá cambia lo de acá.
  void _reloadAfterReturn() {
    if (!mounted) return;
    unawaited(_load(refresh: true));
  }

  void _openInitialBike() {
    final bikeId = widget.initialBikeId?.trim();
    if (bikeId == null || bikeId.isEmpty || bikeId == _openedBikeId) return;
    if (!_bikes.any((bike) => bike.id == bikeId)) return;
    _openedBikeId = bikeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openBike(bikeId);
    });
  }

  // ── Navegación ───────────────────────────────────────────────────────────

  Future<void> _close() async {
    if (_saving) return;
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    _leaveEdit();
    ReturnNavigation.close(context, fallbackRoute: _fallbackRoute);
  }

  void _openJob(String jobId) {
    context.push('/taller/pegas/$jobId').then((_) => _reloadAfterReturn());
  }

  void _newJob() {
    final route = Uri(
      path: '/taller/pegas/nueva',
      queryParameters: {'customer_id': widget.customerId},
    ).toString();
    context.push(route).then((_) => _reloadAfterReturn());
  }

  void _openBike(String bikeId) {
    context
        .push('/taller/bicicletas/$bikeId')
        .then((_) => _reloadAfterReturn());
  }

  Future<void> _addBike() async {
    final saved = await showDialog<Bike?>(
      context: context,
      builder: (_) => BikeFormDialog(customerId: widget.customerId),
    );
    if (saved != null && mounted) _reloadAfterReturn();
  }

  void _openInvoice(Invoice invoice) {
    final id = invoice.id;
    if (id == null || id.isEmpty) return;
    context.push('/sales/invoices/$id/edit').then((_) => _reloadAfterReturn());
  }

  void _registerPayment(Invoice invoice) {
    final id = invoice.id;
    if (id == null || id.isEmpty) return;
    context
        .push('/sales/invoices/$id/payment')
        .then((_) => _reloadAfterReturn());
  }

  void _manageAccess() {
    UserManagementNavigation.open(
      context,
      audience: UserManagementAudience.customers,
      target: UserManagementTarget.customer,
      targetId: widget.customerId,
    );
  }

  void _showTab(ClientPageTab tab) => setState(() => _tab = tab);

  void _openChat(Conversation chat) {
    setState(() {
      _selectedChat = chat;
      _tab = ClientPageTab.messages;
    });
  }

  // ── Edición en su lugar ──────────────────────────────────────────────────

  bool get _hasUnsavedChanges => (_draft?.changeCount ?? 0) > 0;

  void _startEdit([ClientDataField? focus]) {
    final record = _record;
    if (record == null || _saving) return;
    if (_draft == null) {
      final draft = ClientDataDraft(record);
      _resetControllers(draft);
      setState(() {
        _draft = draft;
        _tab = ClientPageTab.data;
        _showProblems = false;
        _saveProblem = null;
        _dockNotice = null;
      });
    } else if (_tab != ClientPageTab.data) {
      setState(() => _tab = ClientPageTab.data);
    }
    if (focus != null && focus != ClientDataField.region) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus[focus]?.requestFocus();
      });
    }
  }

  void _resetControllers(ClientDataDraft draft) {
    for (final field in ClientDataField.values) {
      final text = draft.value(field) ?? '';
      final controller = _text[field];
      if (controller == null) {
        _text[field] = TextEditingController(text: text);
      } else if (controller.text != text) {
        controller.text = text;
      }
    }
  }

  void _leaveEdit() {
    _draft = null;
    _saving = false;
    _showProblems = false;
    _saveProblem = null;
    _dockNotice = null;
  }

  void _onFieldChanged(ClientDataField field, String value) {
    final draft = _draft;
    if (draft == null) return;
    draft.set(field, value);
    setState(() {
      if (_saveProblem?.field == field) _saveProblem = null;
    });
  }

  void _onRegionChanged(String? region) {
    final draft = _draft;
    if (draft == null) return;
    draft.set(ClientDataField.region, region);
    setState(() {});
  }

  void _undo(ClientDataField field) {
    final draft = _draft;
    if (draft == null) return;
    draft.revert(field);
    _text[field]?.text = draft.value(field) ?? '';
    setState(() {
      if (_saveProblem?.field == field) _saveProblem = null;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar los cambios?'),
        content: const Text('Los datos del cliente quedan como estaban.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _cancelEdit() async {
    if (_saving) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(_leaveEdit);
  }

  Map<ClientDataField, String> get _problems {
    final draft = _draft;
    if (draft == null) return const {};
    final problems = <ClientDataField, String>{
      if (_showProblems) ...draft.problems,
    };
    final saveProblem = _saveProblem;
    if (saveProblem?.field case final field?) {
      problems[field] = saveProblem!.message;
    }
    return problems;
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final problems = draft.problems;
    if (problems.isNotEmpty) {
      setState(() {
        _showProblems = true;
        _saveProblem = null;
        _dockNotice = 'Revisa ${_joinNames(problems.keys)} antes de guardar.';
      });
      final first = problems.keys.first;
      if (first != ClientDataField.region) _focus[first]?.requestFocus();
      return;
    }
    final customers = context.read<CustomerService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _saveProblem = null;
      _dockNotice = null;
    });
    try {
      final saved = await customers.saveClientData(draft);
      if (!_stillEditing(draft)) return;
      setState(() {
        _record = saved;
        _leaveEdit();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Datos del cliente guardados.')),
      );
    } on ClientDataSaveException catch (error) {
      if (!_stillEditing(draft)) return;
      setState(() {
        _saving = false;
        _saveProblem = (field: error.field, message: error.message);
        _dockNotice = error.message;
      });
    } on ClientDataStaleException {
      if (!_stillEditing(draft)) return;
      await _rebaseAfterStale(draft, customers);
    } catch (error) {
      debugPrint('Client data save failed: $error');
      if (!_stillEditing(draft)) return;
      setState(() {
        _saving = false;
        _dockNotice = 'No se pudo guardar. Revisa la conexión y vuelve a '
            'intentar; tus cambios siguen aquí.';
      });
    }
  }

  /// Lo que vuelve de un guardado sólo vale para la edición que lo pidió: si
  /// entre medio la página pasó a otro cliente, se ignora (Codex,
  /// 2026-10-03: un rechazo tardío ponía los cambios de uno sobre el otro).
  bool _stillEditing(ClientDataDraft draft) =>
      mounted &&
      identical(_draft, draft) &&
      widget.customerId == draft.record.id;

  /// Otro guardó el cliente mientras se editaba: se lee lo suyo y se ponen
  /// encima los cambios de esta edición, marcados, para revisarlos.
  Future<void> _rebaseAfterStale(
    ClientDataDraft draft,
    CustomerService customers,
  ) async {
    ClientRecord? newer;
    try {
      newer = await customers.getClientRecord(draft.record.id);
    } catch (error) {
      debugPrint('Client data reread failed: $error');
    }
    if (!_stillEditing(draft)) return;
    if (newer == null || newer.id != draft.record.id) {
      setState(() {
        _saving = false;
        _dockNotice = 'Otro guardó este cliente mientras editabas y no '
            'pudimos leer su versión. Vuelve a intentar.';
      });
      return;
    }
    final next = draft.rebasedOn(newer);
    _resetControllers(next);
    final overlap = next.changedByOthers;
    setState(() {
      _record = newer;
      _draft = next;
      _saving = false;
      _dockNotice = overlap.isEmpty
          ? 'Otro guardó este cliente mientras editabas. Tus cambios siguen '
              'aquí, encima de lo suyo: guarda de nuevo.'
          : 'Otro guardó este cliente mientras editabas y también cambió '
              '${_joinNames(overlap)}. Quedó lo tuyo: revísalo y guarda de '
              'nuevo.';
    });
  }

  /// «el correo», «el correo y el RUT», «el nombre, el correo y el RUT».
  static String _joinNames(Iterable<ClientDataField> fields) {
    final names = [for (final field in fields) field.phrase];
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  }

  // ── Lo que se calcula de la actividad ────────────────────────────────────

  Map<String, Invoice> get _invoiceById => {
        for (final invoice in _invoices ?? const <Invoice>[])
          if (invoice.id != null) invoice.id!: invoice,
      };

  Map<String, MechanicJob> get _jobByInvoiceId => {
        for (final visit in _visits ?? const <BikeVisit>[])
          if (visit.job.invoiceId case final id?) id: visit.job,
      };

  List<BikeVisit> get _countedVisits => [
        for (final visit in _visits ?? const <BikeVisit>[])
          if (!isCancelledJob(visit.job)) visit,
      ];

  List<Invoice> get _owedInvoices => [
        for (final invoice in _invoices ?? const <Invoice>[])
          if (invoiceIsOwed(invoice)) invoice,
      ]..sort((a, b) => a.date.compareTo(b.date));

  double get _paidTotal => (_invoices ?? const <Invoice>[])
      .where((invoice) => invoice.status != InvoiceStatus.cancelled)
      .fold(0.0, (sum, invoice) => sum + invoice.paidAmount);

  double get _owedTotal =>
      _owedInvoices.fold(0.0, (sum, invoice) => sum + invoice.balance);

  String _bikeName(Bike bike) {
    final parts = [bike.brand, bike.model]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'Bicicleta sin nombre' : parts.join(' ');
  }

  /// Lo que entró al taller: la bici (que abre su página), el componente o
  /// nada, si es una cotización.
  List<JobVisitSubject> _subjectsFor(BikeVisit visit) {
    final job = visit.job;
    if (job.isStandaloneQuotation) {
      return const [JobVisitSubject(label: 'Sin objeto recibido')];
    }
    if (job.isComponentIntake) {
      final subjectName = job.subjectData?.name.trim();
      final subjectNotes = job.subjectNotes?.trim();
      return [
        JobVisitSubject(
          label: subjectName?.isNotEmpty == true
              ? subjectName!
              : subjectNotes?.isNotEmpty == true
                  ? subjectNotes!
                  : 'Componente recibido',
        ),
      ];
    }
    if (job.isSaleWorkflow) return const [JobVisitSubject(label: 'Venta')];
    final bikes = _bikesById;
    return [
      for (final bikeId in visit.bikeIds)
        if (bikes[bikeId] case final bike?)
          JobVisitSubject(
              label: _bikeName(bike), onTap: () => _openBike(bikeId))
        else
          const JobVisitSubject(label: 'Bicicleta sin datos'),
    ];
  }

  String _subjectLabel(BikeVisit visit) =>
      _subjectsFor(visit).map((subject) => subject.label).join(', ');

  // ── Página ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.usesCompactShell(context);
    final record = _record;
    final title =
        record == null || record.name.isEmpty ? 'Cliente' : record.name;
    final phone = record?.phone;
    return MainLayout(
      title: title,
      onBackPressed: compact ? _close : null,
      compactHeader: compact
          ? MainLayoutCompactHeader(
              title: title,
              contextLine:
                  phone == null ? null : ChileanUtils.formatPhone(phone),
              actions: [
                if (record != null && _draft == null)
                  IconButton(
                    tooltip: 'Editar datos del cliente',
                    onPressed: () => _startEdit(),
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            )
          : null,
      body: PopScope(
        canPop: !_hasUnsavedChanges && !_saving,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop || _saving) return;
          if (!await _confirmDiscard() || !mounted) return;
          setState(_leaveEdit);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ReturnNavigation.close(context, fallbackRoute: _fallbackRoute);
            }
          });
        },
        child: BikeModuleTheme(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: _buildBody(context, compactShell: compact),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, {required bool compactShell}) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: BrandedLoading());
    final record = _record;
    if (record == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _notFound
                    ? 'Este cliente no existe o ya no está registrado.'
                    : (_error ?? 'No pudimos abrir este cliente.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (!_notFound)
                    VbButton(
                      label: 'Reintentar',
                      icon: Icons.refresh,
                      onPressed: _load,
                    ),
                  VbButton(
                    label: 'Volver a clientes',
                    variant: VbButtonVariant.secondary,
                    onPressed: _close,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final canManageUsers =
        context.watch<CurrentUserProfileService>().profile?.canManageUsers ==
            true;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final phone = width < 680;
        final gutter = phone ? 16.0 : 28.0;
        final contentWidth = width - gutter * 2;
        final twoColumns = contentWidth >= 1000;
        final mainWidth = twoColumns ? contentWidth - 380 : contentWidth;
        final dock = _draft == null ? null : _buildDock();
        return VbEditDockLayer(
          dock: dock,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              phone ? 8 : 16,
              gutter,
              dock == null ? 48 : (_dockNotice == null ? 120 : 190),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compactShell) ...[
                  _buildBackRow(context),
                  const SizedBox(height: 8),
                ],
                if (phone)
                  _buildPhoneHeader(context, record)
                else
                  _buildWideHeader(context, record, width: contentWidth),
                const SizedBox(height: 18),
                if (!twoColumns) ...[
                  _buildBikesCard(context, phone: phone),
                  const SizedBox(height: 18),
                ],
                _buildTabs(),
                const SizedBox(height: 18),
                if (twoColumns)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildTabContent(context, record,
                            width: mainWidth, canManageUsers: canManageUsers),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 360,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildBikesCard(context, phone: false),
                            const SizedBox(height: 14),
                            _buildMessagesCard(context),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  _buildTabContent(context, record,
                      width: mainWidth, canManageUsers: canManageUsers),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackRow(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _close,
        icon: const Icon(Icons.chevron_left, size: 22),
        label: const Text(
          'Clientes',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.only(left: 2, right: 10),
        ),
      ),
    );
  }

  Widget _buildDock() {
    return VbEditDock(
      changeCount: _draft?.changeCount ?? 0,
      saveLabel: 'Guardar datos',
      saveSemanticLabel: 'Guardar datos del cliente',
      busy: _saving,
      notice: _dockNotice,
      onCancel: _cancelEdit,
      onSave: _save,
    );
  }

  // ── Cabecera ─────────────────────────────────────────────────────────────

  String _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    final second = words.length > 1 ? words[1].characters.first : '';
    return (first + second).toUpperCase();
  }

  Widget _avatar(BuildContext context, String name, {required double size}) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          // En teléfono va sobre el fondo de la página, no sobre la tarjeta.
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          _initials(name),
          style: TextStyle(
            fontFamily: BikeModuleText.display,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.35,
            letterSpacing: 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// «+56 9 8121 0019 · nombre@correo.cl», o lo que falta con su atajo.
  Widget _contactLine(BuildContext context, ClientRecord record) {
    final theme = Theme.of(context);
    final phone =
        record.phone == null ? null : ChileanUtils.formatPhone(record.phone);
    final email = record.email;
    final parts = [phone, email].whereType<String>().toList();
    final style =
        TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant);
    final add = phone == null
        ? (email == null ? 'Agregar contacto' : 'Agregar teléfono')
        : null;
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SelectableText(
          parts.isEmpty ? 'Sin teléfono ni correo' : parts.join(' · '),
          style: style,
        ),
        if (add != null)
          TextButton(
            onPressed: _saving ? null : () => _startEdit(ClientDataField.phone),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 36),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Text(add),
          ),
      ],
    );
  }

  Widget _buildWideHeader(BuildContext context, ClientRecord record,
      {required double width}) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final alerts = _alerts(context, narrow: false);
    final facts = _facts(record);
    final columns = width >= 820 ? facts.length : 3;
    final cellWidth = (width - 2) / columns;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Row(
              children: [
                _avatar(context, record.name, size: 68),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          record.name.isEmpty
                              ? 'Cliente sin nombre'
                              : record.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BikeModuleText.title(context, size: 38),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _contactLine(context, record),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    VbButton(
                      label: 'Editar',
                      icon: Icons.edit_outlined,
                      variant: VbButtonVariant.secondary,
                      density: VbDensity.comfortable,
                      semanticLabel: 'Editar datos del cliente',
                      onPressed:
                          _draft != null || _saving ? null : () => _startEdit(),
                    ),
                    VbButton(
                      label: 'Nuevo trabajo',
                      icon: Icons.add,
                      density: VbDensity.comfortable,
                      onPressed: _newJob,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (alerts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pair = alerts.length > 1 && constraints.maxWidth >= 720;
                  final bandWidth = pair
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final alert in alerts)
                        SizedBox(width: bandWidth, child: alert),
                    ],
                  );
                },
              ),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: Wrap(
              children: [
                for (var index = 0; index < facts.length; index++)
                  Container(
                    width: cellWidth,
                    padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
                    decoration: BoxDecoration(
                      border: Border(
                        left: index % columns == 0
                            ? BorderSide.none
                            : BorderSide(color: roles.hairline),
                        top: index >= columns
                            ? BorderSide(color: roles.hairline)
                            : BorderSide.none,
                      ),
                    ),
                    child: _factCell(context, facts[index]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneHeader(BuildContext context, ClientRecord record) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final alerts = _alerts(context, narrow: true);
    final facts = _facts(record);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _avatar(context, record.name, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  record.name.isEmpty ? 'Cliente sin nombre' : record.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BikeModuleText.title(context, size: 30),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _contactLine(context, record),
        for (final alert in alerts) ...[
          const SizedBox(height: 12),
          alert,
        ],
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final half = (constraints.maxWidth - 2) / 2;
              return Wrap(
                children: [
                  for (var index = 0; index < facts.length; index++)
                    Container(
                      width: half,
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      decoration: BoxDecoration(
                        border: Border(
                          right: index.isEven
                              ? BorderSide(color: roles.hairline)
                              : BorderSide.none,
                          top: index >= 2
                              ? BorderSide(color: roles.hairline)
                              : BorderSide.none,
                        ),
                      ),
                      child: _factCell(context, facts[index]),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        VbButton(
          label: 'Nuevo trabajo',
          icon: Icons.add,
          expand: true,
          onPressed: _newJob,
        ),
      ],
    );
  }

  List<({String label, String? value, bool warn})> _facts(ClientRecord record) {
    final visits = _visits == null ? null : _countedVisits;
    final last = visits == null || visits.isEmpty
        ? null
        : visits
            .map((visit) => visit.date)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final invoicesReady = _invoices != null;
    final owed = _owedTotal;
    return [
      (label: 'Visitas', value: visits?.length.toString(), warn: false),
      (
        label: 'Pagado',
        value: invoicesReady ? _money.format(_paidTotal) : null,
        warn: false
      ),
      (
        label: 'Por cobrar',
        value: invoicesReady ? _money.format(owed) : null,
        warn: owed > 0.5
      ),
      (
        label: 'Última visita',
        value: last == null ? null : bikeFullDate(last),
        warn: false
      ),
      (
        label: 'Cliente desde',
        value: bikeMonthYear(record.createdAt),
        warn: false
      ),
    ];
  }

  Widget _factCell(
      BuildContext context, ({String label, String? value, bool warn}) fact) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      container: true,
      label: '${fact.label}: ${fact.value ?? 'sin dato'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(fact.label.toUpperCase(), style: BikeModuleText.label(context)),
          const SizedBox(height: 3),
          Text(
            fact.value ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight:
                  fact.value == null ? FontWeight.w500 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: fact.value == null
                  ? roles.faintForeground
                  : fact.warn
                      ? roles.warning.onContainer
                      : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ── Lo que pide atención ─────────────────────────────────────────────────

  List<Widget> _alerts(BuildContext context, {required bool narrow}) {
    final inWorkshop = [
      for (final visit in _visits ?? const <BikeVisit>[])
        if (visit.inWorkshop) visit,
    ];
    return [
      for (final visit in inWorkshop.take(2))
        _workshopBand(context, visit, narrow: narrow),
      if (_owedInvoices.isNotEmpty) _debtBand(context, narrow: narrow),
    ];
  }

  Widget _band(
    BuildContext context, {
    required String title,
    required Widget details,
    required Widget action,
    required Color background,
    required Color border,
    required Color titleColor,
    required bool narrow,
  }) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: titleColor,
          ),
        ),
        const SizedBox(height: 4),
        details,
      ],
    );
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [text, const SizedBox(height: 10), action],
              )
            : Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 12),
                  action,
                ],
              ),
      ),
    );
  }

  Widget _workshopBand(BuildContext context, BikeVisit visit,
      {required bool narrow}) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final job = visit.job;
    final days = calendarDaysBetween(job.arrivalDate, _today);
    final title = days == 0
        ? 'En el taller desde hoy'
        : 'En el taller hace ${days == 1 ? '1 día' : '$days días'}';
    final jobId = job.id;
    return _band(
      context,
      title: title,
      titleColor: roles.onSelectionContainer,
      background: roles.selectionContainer,
      border: roles.accentBorder,
      narrow: narrow,
      details: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _subjectLabel(visit),
            style: TextStyle(
                fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
          ),
          if (job.jobNumber != null)
            Text(job.jobNumber!, style: BikeModuleText.code(context)),
          BikeJobStatusDot(
            label: jobVisitStatusLabel(job),
            color: jobVisitStatusColor(job),
            fontSize: 14,
          ),
        ],
      ),
      action: VbButton(
        label: 'Abrir trabajo',
        icon: Icons.arrow_forward,
        variant: VbButtonVariant.secondary,
        density: narrow ? null : VbDensity.comfortable,
        expand: narrow,
        semanticLabel: job.jobNumber == null
            ? 'Abrir trabajo'
            : 'Abrir trabajo ${job.jobNumber}',
        onPressed: jobId == null ? null : () => _openJob(jobId),
      ),
    );
  }

  Widget _debtBand(BuildContext context, {required bool narrow}) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final owed = _owedInvoices;
    final single = owed.length == 1 ? owed.first : null;
    final today = _today;
    final String detail;
    if (single != null) {
      final date = bikeShortDate(single.date, today: today);
      detail = single.paidAmount > 0.5
          ? '${single.invoiceNumber} del $date · abonó '
              '${_money.format(single.paidAmount)} de '
              '${_money.format(single.total)}'
          : '${single.invoiceNumber} del $date · sin abonos';
    } else {
      detail = '${owed.length} facturas con saldo · la más antigua del '
          '${bikeShortDate(owed.first.date, today: today)}';
    }
    return _band(
      context,
      title: 'Debe ${_money.format(_owedTotal)}',
      titleColor: roles.warning.onContainer,
      background: roles.warning.container,
      border: roles.warning.border,
      narrow: narrow,
      details: Text(
        detail,
        style:
            TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
      ),
      action: single != null
          ? VbButton(
              label: 'Registrar pago',
              variant: VbButtonVariant.secondary,
              density: narrow ? null : VbDensity.comfortable,
              expand: narrow,
              semanticLabel: 'Registrar pago de ${single.invoiceNumber}',
              onPressed: () => _registerPayment(single),
            )
          : VbButton(
              label: 'Ver facturas',
              variant: VbButtonVariant.secondary,
              density: narrow ? null : VbDensity.comfortable,
              expand: narrow,
              onPressed: () => _showTab(ClientPageTab.invoices),
            ),
    );
  }

  // ── Pestañas ─────────────────────────────────────────────────────────────

  Widget _buildTabs() {
    String counted(String label, int? count) =>
        count == null || count == 0 ? label : '$label · $count';
    return VbSubTabs<ClientPageTab>(
      density: VbSubTabsDensity.comfortable,
      value: _tab,
      onChanged: _showTab,
      tabs: [
        const VbSubTab(value: ClientPageTab.data, label: 'Datos'),
        VbSubTab(
          value: ClientPageTab.activity,
          label: counted('Actividad', _visits?.length),
        ),
        VbSubTab(
          value: ClientPageTab.invoices,
          label: counted('Facturas', _invoices?.length),
        ),
        VbSubTab(
          value: ClientPageTab.messages,
          label: counted('Mensajes', _chats?.length),
        ),
      ],
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    ClientRecord record, {
    required double width,
    required bool canManageUsers,
  }) {
    return switch (_tab) {
      ClientPageTab.data => ClientDataSheet(
          record: record,
          draft: _draft,
          controllers: _text,
          focusNodes: _focus,
          problems: _problems,
          busy: _saving,
          onAdd: _startEdit,
          onChanged: _onFieldChanged,
          onRegionChanged: _onRegionChanged,
          onUndo: _undo,
          onManageAccess: canManageUsers ? _manageAccess : null,
        ),
      ClientPageTab.activity => _buildActivity(context, width: width),
      ClientPageTab.invoices => _buildInvoices(context, width: width),
      ClientPageTab.messages => _buildMessages(context, width: width),
    };
  }

  Widget _stateBlock(
    BuildContext context, {
    required String title,
    String? body,
    IconData? icon,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 30, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
            ],
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _loadingBlock() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );

  // ── Actividad ────────────────────────────────────────────────────────────

  Widget _buildActivity(BuildContext context, {required double width}) {
    final visits = _visits;
    if (_visitsFailed && visits == null) {
      return _stateBlock(
        context,
        icon: Icons.cloud_off_outlined,
        title: 'No pudimos cargar la actividad.',
        body: 'Revisa la conexión y vuelve a intentar.',
        action: VbButton(
          label: 'Reintentar',
          icon: Icons.refresh,
          variant: VbButtonVariant.secondary,
          onPressed: () => _loadVisits(_generation),
        ),
      );
    }
    if (visits == null) return _loadingBlock();
    if (visits.isEmpty) {
      return _stateBlock(
        context,
        title: 'Todavía no tiene trabajos.',
        body: 'Cuando traiga su bici, cada trabajo queda aquí con lo que se '
            'le hizo y su factura.',
        action: VbButton(
          label: 'Nuevo trabajo',
          icon: Icons.add,
          onPressed: _newJob,
        ),
      );
    }
    final narrow = width < 640;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final visit in visits)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: JobVisitCard(
              visit: visit,
              today: _today,
              narrow: narrow,
              onOpenJob: _openJob,
              subjects: _subjectsFor(visit),
              footer: _visitFooter(context, visit),
            ),
          ),
      ],
    );
  }

  /// La factura del trabajo y cuánto se pagó; o por qué todavía no tiene.
  Widget? _visitFooter(BuildContext context, BikeVisit visit) {
    if (_invoices == null) return null;
    final roles = VinabikeThemeRoles.of(context);
    final job = visit.job;
    final invoice = job.invoiceId == null ? null : _invoiceById[job.invoiceId];
    if (invoice == null) {
      if (isCancelledJob(job)) return null;
      return Text(
        job.isQuotationWorkflow
            ? (job.isServiceBudget
                ? 'Este presupuesto aún no ha generado una factura.'
                : 'Esta cotización aún no ha generado una factura.')
            : 'Sin factura todavía.',
        style: TextStyle(fontSize: 13, color: roles.faintForeground),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _invoiceNumber(context, invoice),
        _payChip(invoice),
      ],
    );
  }

  Widget _invoiceNumber(BuildContext context, Invoice invoice) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Abrir factura ${invoice.invoiceNumber}',
      excludeSemantics: true,
      onTap: () => _openInvoice(invoice),
      child: InkWell(
        onTap: () => _openInvoice(invoice),
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              invoice.invoiceNumber,
              style: BikeModuleText.code(context,
                  color: theme.colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }

  /// «Pagada», «Debe $45.000 de $90.000», «Anulada», «Borrador».
  (String, SheetStatusTone) _payState(Invoice invoice) {
    if (invoice.status == InvoiceStatus.cancelled) {
      return ('Anulada', SheetStatusTone.neutral);
    }
    if (invoice.status == InvoiceStatus.draft) {
      return ('Borrador', SheetStatusTone.neutral);
    }
    if (invoice.balance <= 0.5) return ('Pagada', SheetStatusTone.success);
    final owed = _money.format(invoice.balance);
    return invoice.paidAmount > 0.5
        ? (
            'Debe $owed de ${_money.format(invoice.total)}',
            SheetStatusTone.warning
          )
        : ('Debe $owed', SheetStatusTone.warning);
  }

  Widget _payChip(Invoice invoice) {
    final (label, tone) = _payState(invoice);
    return SheetStatusChip(label: label, tone: tone);
  }

  // ── Facturas ─────────────────────────────────────────────────────────────

  Widget _buildInvoices(BuildContext context, {required double width}) {
    final invoices = _invoices;
    if (_invoicesFailed && invoices == null) {
      return _stateBlock(
        context,
        icon: Icons.cloud_off_outlined,
        title: 'No pudimos cargar las facturas.',
        body: 'Revisa la conexión y vuelve a intentar.',
        action: VbButton(
          label: 'Reintentar',
          icon: Icons.refresh,
          variant: VbButtonVariant.secondary,
          onPressed: () => _loadInvoices(_generation, force: true),
        ),
      );
    }
    if (invoices == null) return _loadingBlock();
    if (invoices.isEmpty) {
      return _stateBlock(context, title: 'Todavía no tiene facturas.');
    }
    final theme = Theme.of(context);
    final narrow = width < 720;
    final jobs = _jobByInvoiceId;
    final bikes = _bikesById;
    String contextOf(Invoice invoice) {
      final job = invoice.id == null ? null : jobs[invoice.id];
      if (job != null) {
        final visit =
            _visits?.where((visit) => visit.job.id == job.id).firstOrNull;
        final subject = visit == null ? null : _subjectLabel(visit);
        return [job.jobNumber, subject]
            .whereType<String>()
            .where((part) => part.isNotEmpty)
            .join(' · ');
      }
      final bike = invoice.bikeId == null ? null : bikes[invoice.bikeId];
      if (bike != null) return _bikeName(bike);
      final reference = invoice.reference?.trim();
      if (reference != null && reference.isNotEmpty) return reference;
      return invoice.invoiceType == 'sale' ? 'Venta' : 'Taller';
    }

    final rows = <Widget>[
      if (!narrow)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Row(
            children: [
              SizedBox(
                  width: 120,
                  child: Text('FACTURA', style: BikeModuleText.label(context))),
              SizedBox(
                  width: 110,
                  child: Text('FECHA', style: BikeModuleText.label(context))),
              Expanded(
                  child:
                      Text('DE QUÉ ES', style: BikeModuleText.label(context))),
              SizedBox(
                  width: 190,
                  child: Text('ESTADO', style: BikeModuleText.label(context))),
              SizedBox(
                width: 110,
                child: Text('TOTAL',
                    textAlign: TextAlign.end,
                    style: BikeModuleText.label(context)),
              ),
            ],
          ),
        ),
      for (var index = 0; index < invoices.length; index++)
        _invoiceRow(context, invoices[index],
            contextLabel: contextOf(invoices[index]),
            narrow: narrow,
            divider: index > 0 || !narrow),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }

  Widget _invoiceRow(
    BuildContext context,
    Invoice invoice, {
    required String contextLabel,
    required bool narrow,
    required bool divider,
  }) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final (status, tone) = _payState(invoice);
    final date = bikeFullDate(invoice.date);
    final total = Text(
      _money.format(invoice.total),
      textAlign: TextAlign.end,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        decoration: invoice.status == InvoiceStatus.cancelled
            ? TextDecoration.lineThrough
            : null,
        color: invoice.status == InvoiceStatus.cancelled
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onSurface,
      ),
    );
    final number = Text(
      invoice.invoiceNumber,
      style: BikeModuleText.code(context, color: theme.colorScheme.primary),
    );
    final Widget content;
    if (narrow) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              number,
              const SizedBox(width: 10),
              Expanded(
                  child: Text(date,
                      style: TextStyle(
                          fontSize: 13, color: roles.faintForeground))),
              total,
            ],
          ),
          const SizedBox(height: 4),
          Text(contextLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SheetStatusChip(label: status, tone: tone),
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          SizedBox(width: 120, child: number),
          SizedBox(
            width: 110,
            child: Text(date,
                style: TextStyle(
                    fontSize: 13.5, color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(contextLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14)),
          ),
          SizedBox(
            width: 190,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SheetStatusChip(label: status, tone: tone),
            ),
          ),
          SizedBox(width: 110, child: total),
        ],
      );
    }
    return Semantics(
      button: true,
      label: 'Factura ${invoice.invoiceNumber}, $date, $contextLabel, '
          '$status, ${_money.format(invoice.total)}',
      excludeSemantics: true,
      onTap: () => _openInvoice(invoice),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openInvoice(invoice),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding:
                EdgeInsets.fromLTRB(20, narrow ? 12 : 10, 20, narrow ? 12 : 10),
            decoration: BoxDecoration(
              border: divider
                  ? Border(top: BorderSide(color: roles.hairline))
                  : null,
            ),
            alignment: Alignment.centerLeft,
            child: content,
          ),
        ),
      ),
    );
  }

  // ── Mensajes ─────────────────────────────────────────────────────────────

  Widget _buildMessages(BuildContext context, {required double width}) {
    final chats = _chats;
    if (_chatsFailed && chats == null) {
      return _stateBlock(
        context,
        icon: Icons.cloud_off_outlined,
        title: 'No pudimos cargar los mensajes.',
        body: 'Revisa la conexión y vuelve a intentar.',
        action: VbButton(
          label: 'Reintentar',
          icon: Icons.refresh,
          variant: VbButtonVariant.secondary,
          onPressed: () => _loadChats(_generation),
        ),
      );
    }
    if (chats == null) return _loadingBlock();
    if (chats.isEmpty) {
      return _stateBlock(
        context,
        icon: Icons.chat_bubble_outline,
        title: 'Sin conversaciones con este cliente.',
        body: 'Aquí aparecen sus chats de WhatsApp y del portal, y los de sus '
            'trabajos y facturas.',
      );
    }
    final theme = Theme.of(context);
    final height =
        (MediaQuery.sizeOf(context).height * 0.72).clamp(420.0, 780.0);
    final selected = chats.length == 1 ? chats.first : _selectedChat;
    final wide = width >= 640;
    Widget chatWindow(Conversation chat) => ChatWindow(
          key: ValueKey(chat.id),
          conversation: chat,
          compact: !wide,
        );

    final Widget body;
    if (chats.length == 1) {
      body = chatWindow(chats.first);
    } else if (wide) {
      body = Row(
        children: [
          SizedBox(
            width: 250,
            child: ListView(
              children: [
                for (final chat in chats)
                  _chatRow(context, chat, selected: chat.id == selected?.id),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: selected == null
                ? Center(
                    child: Text(
                      'Elige una conversación.',
                      style:
                          TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : chatWindow(selected),
          ),
        ],
      );
    } else if (selected != null) {
      body = Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedChat = null),
              icon: const Icon(Icons.chevron_left),
              label: const Text('Conversaciones'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
          Expanded(child: chatWindow(selected)),
        ],
      );
    } else {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            for (final chat in chats) _chatRow(context, chat, selected: false),
          ],
        ),
      );
    }
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }

  String _chatKind(Conversation chat) => switch (chat.contextType) {
        'job' => 'Trabajo',
        'invoice' => 'Factura',
        _ => chat.channel == 'whatsapp'
            ? 'WhatsApp'
            : chat.type == 'support'
                ? 'Portal'
                : 'Interno',
      };

  String _chatDate(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return DateFormat('HH:mm').format(local);
    }
    return bikeShortDate(local, today: now);
  }

  Widget _chatRow(BuildContext context, Conversation chat,
      {required bool selected}) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final unread = chat.unreadCount > 0;
    final preview = chat.lastMessageContent?.trim();
    return Material(
      color: selected ? roles.selectionContainer : Colors.transparent,
      child: InkWell(
        onTap: () => _openChat(chat),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chat.title?.trim().isNotEmpty == true
                            ? chat.title!.trim()
                            : 'Conversación',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview == null || preview.isEmpty
                            ? _chatKind(chat)
                            : '${_chatKind(chat)} · $preview',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _chatDate(chat.lastMessageAt ?? chat.updatedAt),
                      style:
                          TextStyle(fontSize: 12, color: roles.faintForeground),
                    ),
                    if (unread) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          chat.unreadCount > 9 ? '9+' : '${chat.unreadCount}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Riel: bicis y mensajes ───────────────────────────────────────────────

  Widget _railCard(BuildContext context, {required List<Widget> children}) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _railTitle(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Semantics(
          header: true,
          child:
              Text(title.toUpperCase(), style: BikeModuleText.label(context)),
        ),
      );

  Widget _buildBikesCard(BuildContext context, {required bool phone}) {
    final roles = VinabikeThemeRoles.of(context);
    final active = [
      for (final bike in _bikes)
        if (bike.isActive) bike,
    ];
    final archived = [
      for (final bike in _bikes)
        if (!bike.isActive) bike,
    ];
    final visits = _visits;
    ({int count, BikeVisit? workshop, DateTime? last}) statsOf(Bike bike) {
      var count = 0;
      BikeVisit? workshop;
      DateTime? last;
      for (final visit in visits ?? const <BikeVisit>[]) {
        if (!visit.bikeIds.contains(bike.id)) continue;
        if (visit.inWorkshop) workshop ??= visit;
        if (isCancelledJob(visit.job)) continue;
        count++;
        if (last == null || visit.date.isAfter(last)) last = visit.date;
      }
      return (count: count, workshop: workshop, last: last);
    }

    final ordered = [...active]..sort((a, b) {
        final left = statsOf(a);
        final right = statsOf(b);
        if ((left.workshop != null) != (right.workshop != null)) {
          return left.workshop != null ? -1 : 1;
        }
        final leftLast = left.last ?? a.createdAt;
        final rightLast = right.last ?? b.createdAt;
        return rightLast.compareTo(leftLast);
      });
    final all = [...ordered, ...archived];
    return _railCard(
      context,
      children: [
        _railTitle(
            context, all.isEmpty ? 'Bicicletas' : 'Bicicletas · ${all.length}'),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
            child: Text(
              'Todavía no tiene bicicletas registradas.',
              style: TextStyle(fontSize: 14, color: roles.faintForeground),
            ),
          ),
        for (final bike in all) _bikeRow(context, bike, statsOf(bike)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
          child: VbButton(
            label: 'Agregar bicicleta',
            icon: Icons.add,
            variant: VbButtonVariant.secondary,
            expand: true,
            onPressed: _addBike,
          ),
        ),
      ],
    );
  }

  Widget _bikeRow(BuildContext context, Bike bike,
      ({int count, BikeVisit? workshop, DateTime? last}) stats) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final brand = bike.brand?.trim() ?? '';
    final model = bike.model?.trim() ?? '';
    final color = bike.color?.trim();
    final meta = [
      bike.bikeType?.displayName ?? 'Tipo sin registrar',
      color == null || color.isEmpty
          ? 'sin color registrado'
          : color[0].toUpperCase() + color.substring(1),
    ].join(' · ');
    final visitsText = stats.count == 1 ? '1 visita' : '${stats.count} visitas';
    final (String status, Color statusColor) = !bike.isActive
        ? ('Archivada', roles.faintForeground)
        : stats.workshop != null
            ? ('En el taller · $visitsText', roles.warning.onContainer)
            : stats.last != null
                ? (
                    '$visitsText · última ${bikeShortDate(stats.last!, today: _today)}',
                    theme.colorScheme.onSurfaceVariant
                  )
                : ('Sin visitas', roles.faintForeground);
    final name = brand.isEmpty && model.isEmpty
        ? const TextSpan(text: 'Bicicleta sin nombre')
        : TextSpan(children: [
            if (brand.isNotEmpty)
              TextSpan(
                text: model.isEmpty ? brand : '$brand ',
                style: TextStyle(
                  fontWeight: model.isEmpty ? FontWeight.w600 : FontWeight.w500,
                  color: model.isEmpty
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (model.isNotEmpty) TextSpan(text: model),
          ]);
    final bikeId = bike.id;
    return Semantics(
      button: bikeId != null,
      label: '${_bikeName(bike)}, $meta, $status',
      excludeSemantics: true,
      onTap: bikeId == null ? null : () => _openBike(bikeId),
      child: InkWell(
        onTap: bikeId == null ? null : () => _openBike(bikeId),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 14, 10),
          child: Row(
            children: [
              Container(
                width: 96,
                height: 62,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: BikeSilhouette(
                    bikeType: bike.bikeType, colorText: bike.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, color: roles.faintForeground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesCard(BuildContext context) {
    final theme = Theme.of(context);
    final chats = _chats;
    final Widget body;
    if (_chatsFailed && chats == null) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'No pudimos cargar los mensajes.',
                style: TextStyle(
                    fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () => _loadChats(_generation),
              style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    } else if (chats == null) {
      body = const Padding(
        padding: EdgeInsets.fromLTRB(18, 4, 18, 18),
        child: LinearProgressIndicator(),
      );
    } else if (chats.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Text(
          'Sin conversaciones con este cliente.',
          style: TextStyle(
              fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final chat in chats.take(3))
            _chatRow(context, chat, selected: false),
          if (chats.length > 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showTab(ClientPageTab.messages),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                  child: Text('Ver las ${chats.length} conversaciones'),
                ),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      );
    }
    return _railCard(
      context,
      children: [_railTitle(context, 'Mensajes'), body],
    );
  }
}
