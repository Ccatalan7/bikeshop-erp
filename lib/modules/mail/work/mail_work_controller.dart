import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mail_today_badge.dart';
import 'mail_work_models.dart';
import 'mail_work_service.dart';

/// El estado de la pantalla del correo: la vista, la búsqueda, la lista, el
/// correo abierto y sus conteos. Se refresca solo cada minuto mientras está
/// abierta, porque el estado de cada correo depende de otros registros (un
/// pago o una compra registrados por otra persona lo cambian sin tocar el
/// correo).
class MailWorkController extends ChangeNotifier {
  MailWorkController({MailWorkService? service, this.followsList = true})
      : _service = service ?? MailWorkService();

  final MailWorkService _service;

  /// Falso para leer un correo suelto encima de un registro (la historia de
  /// un trabajo, un cliente o una compra): no carga la bandeja ni salta al
  /// siguiente al archivar.
  final bool followsList;

  MailView _view = MailView.today;
  String _query = '';
  String? _mailbox;
  List<MailItem> _items = const [];
  MailCounts _counts = const MailCounts();
  bool _loading = false;
  Object? _error;
  bool _syncing = false;

  String? _selectedId;
  MailItem? _detail;
  bool _detailLoading = false;
  Object? _detailError;
  final Set<String> _busy = {};

  int _loadEpoch = 0;
  int _detailEpoch = 0;
  Timer? _refreshTimer;
  Timer? _queryDebounce;
  bool _disposed = false;

  MailView get view => _view;
  String get query => _query;

  /// La casilla elegida (su dirección), o null para la bandeja unida.
  String? get mailbox => _mailbox;
  List<MailItem> get items => _items;
  MailCounts get counts => _counts;
  bool get loading => _loading;
  Object? get error => _error;
  bool get syncing => _syncing;
  String? get selectedId => _selectedId;
  MailItem? get detail => _detail;
  bool get detailLoading => _detailLoading;
  Object? get detailError => _detailError;
  bool isBusy(String id) => _busy.contains(id);

  Future<void> start() async {
    await refresh();
    unawaited(syncNow());
    _refreshTimer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  Future<void> refresh({bool silent = false}) async {
    if (!followsList) {
      final selected = _selectedId;
      if (selected != null) await _loadDetail(selected, silent: true);
      return;
    }
    final epoch = ++_loadEpoch;
    if (!silent) {
      _loading = true;
      _notify();
    }
    try {
      final results = await Future.wait<Object>([
        _service.inbox(view: _view, query: _query, mailbox: _mailbox),
        _service.counts(mailbox: _mailbox),
      ]);
      if (epoch != _loadEpoch || _disposed) return;
      _items = results[0] as List<MailItem>;
      _counts = results[1] as MailCounts;
      _error = null;
      // El número del menú es siempre el de todas las casillas.
      if (_mailbox == null) MailTodayBadge.instance.set(_counts.today);
    } catch (error) {
      if (epoch != _loadEpoch || _disposed) return;
      _error = error;
    } finally {
      if (epoch == _loadEpoch && !_disposed) {
        _loading = false;
        _notify();
      }
    }
    final selected = _selectedId;
    if (selected != null && silent) await _loadDetail(selected, silent: true);
  }

  /// Pide al servidor traer lo nuevo de Gmail y Zoho ahora.
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    _notify();
    try {
      await _service.syncNow();
    } catch (_) {
      // El despacho de cada 2 minutos lo trae igual.
    } finally {
      _syncing = false;
      _notify();
    }
    await refresh(silent: true);
  }

  void setView(MailView view) {
    if (_view == view) return;
    _view = view;
    _items = const [];
    clearSelection(notify: false);
    _notify();
    unawaited(refresh());
  }

  void setMailbox(String? address) {
    if (address == _mailbox) return;
    _mailbox = address;
    _items = const [];
    clearSelection(notify: false);
    _notify();
    unawaited(refresh());
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(refresh());
    });
  }

  Future<void> select(String id) async {
    if (_selectedId == id && _detail?.id == id) return;
    _selectedId = id;
    _detail = _items.where((item) => item.id == id).firstOrNull;
    _detailError = null;
    _notify();
    await _loadDetail(id);
    final current = _detail;
    if (current != null && current.id == id && !current.read) {
      try {
        await _service.mark([id], 'read');
        _replace(current.copyWith(read: true));
      } catch (_) {}
    }
  }

  void clearSelection({bool notify = true}) {
    _selectedId = null;
    _detail = null;
    _detailError = null;
    _detailEpoch++;
    if (notify) _notify();
  }

  Future<void> _loadDetail(String id, {bool silent = false}) async {
    final epoch = ++_detailEpoch;
    if (!silent) {
      _detailLoading = true;
      _notify();
    }
    try {
      final item = await _service.message(id);
      if (epoch != _detailEpoch || _disposed) return;
      _detail = item;
      _detailError = null;
      _replace(item, keepBody: false);
    } catch (error) {
      if (epoch != _detailEpoch || _disposed) return;
      if (!silent) _detailError = error;
    } finally {
      if (epoch == _detailEpoch && !_disposed) {
        _detailLoading = false;
        _notify();
      }
    }
  }

  /// La versión fresca de un correo reemplaza la de la lista (sin el cuerpo).
  void _replace(MailItem fresh, {bool keepBody = true}) {
    _items = [
      for (final item in _items) item.id == fresh.id ? fresh : item,
    ];
    if (_detail?.id == fresh.id && keepBody) {
      _detail = fresh.bodyText == null && _detail?.bodyText != null
          ? _detail!.copyWith(
              state: fresh.state, read: fresh.read, archived: fresh.archived)
          : fresh;
    }
    _notify();
  }

  Future<void> mark(MailItem item, String op) async {
    if (_busy.contains(item.id)) return;
    _busy.add(item.id);
    _notify();
    try {
      await _service.mark([item.id], op);
      await _loadDetail(item.id, silent: true);
      await refresh(silent: true);
      if (followsList &&
          op == 'archive' &&
          _selectedId == item.id &&
          _view != MailView.archived) {
        _selectNextAfter(item.id);
      }
    } finally {
      _busy.remove(item.id);
      _notify();
    }
  }

  /// Marca el correo como ocupado mientras corre [task] (escribir un
  /// borrador con IA): su botón muestra que algo pasa.
  Future<T> whileBusy<T>(String id, Future<T> Function() task) async {
    _busy.add(id);
    _notify();
    try {
      return await task();
    } finally {
      _busy.remove(id);
      _notify();
    }
  }

  Future<void> setKind(MailItem item, String kind) async {
    await _service.setKind(item.id, kind);
    await _loadDetail(item.id, silent: true);
    await refresh(silent: true);
  }

  Future<void> link(MailItem item, String type, String recordId,
      {bool remove = false}) async {
    await _service.link(item.id, type, recordId, remove: remove);
    await _loadDetail(item.id, silent: true);
    await refresh(silent: true);
  }

  /// Después de una acción hecha en otra pantalla (registrar la compra, el
  /// pago): el estado se vuelve a leer del registro.
  Future<void> reloadAfterAction(String id) async {
    await _loadDetail(id, silent: true);
    await refresh(silent: true);
  }

  void _selectNextAfter(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    final candidates = [..._items]..removeWhere((item) => item.id == id);
    if (candidates.isEmpty) {
      clearSelection();
      return;
    }
    final next = candidates[(index.clamp(0, candidates.length - 1))];
    unawaited(select(next.id));
  }

  MailWorkService get service => _service;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _queryDebounce?.cancel();
    super.dispose();
  }
}
