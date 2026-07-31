import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/services/tenant_service.dart';
import '../models/stock_movement.dart';

const String stockMovementsDefaultStoreTimezone = 'America/Santiago';

typedef StockMovementsTenantIdLoader = Future<String?> Function();
typedef StockMovementsStoreTimezoneLoader = Future<String?> Function(
  String tenantId,
);

/// Half-open UTC bounds for inclusive dates on the store's calendar.
@immutable
class StockMovementUtcDateBounds {
  const StockMovementUtcDateBounds({
    required this.startInclusive,
    required this.endExclusive,
    required this.timezone,
  });

  final DateTime? startInclusive;
  final DateTime? endExclusive;
  final String timezone;
}

/// Converts inclusive calendar dates in [storeTimezone] into UTC instants.
///
/// Constructing the following local midnight in the IANA location (instead of
/// adding 24 hours) keeps the range exact on 23- and 25-hour DST days.
StockMovementUtcDateBounds stockMovementUtcDateBounds({
  DateTime? startDate,
  DateTime? endDate,
  String? storeTimezone,
}) {
  final location = _stockMovementLocation(storeTimezone);
  final startInclusive = startDate == null
      ? null
      : tz.TZDateTime(
          location,
          startDate.year,
          startDate.month,
          startDate.day,
        ).toUtc();
  final endExclusive = endDate == null
      ? null
      : tz.TZDateTime(
          location,
          endDate.year,
          endDate.month,
          endDate.day + 1,
        ).toUtc();
  return StockMovementUtcDateBounds(
    startInclusive: startInclusive,
    endExclusive: endExclusive,
    timezone: location.name,
  );
}

/// Presents a persisted instant on the same store calendar used by filters.
DateTime stockMovementStoreTime(
  DateTime instant, {
  String? storeTimezone,
}) {
  return tz.TZDateTime.from(
    instant.toUtc(),
    _stockMovementLocation(storeTimezone),
  );
}

bool _stockMovementTimeZonesInitialized = false;

tz.Location _stockMovementLocation(String? requestedTimezone) {
  if (!_stockMovementTimeZonesInitialized) {
    tzdata.initializeTimeZones();
    _stockMovementTimeZonesInitialized = true;
  }

  final timezone = requestedTimezone?.trim();
  if (timezone != null && timezone.isNotEmpty) {
    try {
      return tz.getLocation(timezone);
    } catch (_) {
      // Tenant rows are expected to contain an IANA name. A malformed legacy
      // value must not make the stock ledger unavailable.
    }
  }
  return tz.getLocation(stockMovementsDefaultStoreTimezone);
}

enum StockMovementsViewMode {
  recent,
  byProduct,
}

/// The two orderings a stock ledger can meaningfully carry.
///
/// Only these two exist on purpose. Ordering by product or by reference is
/// what the facets are for, and ordering by running balance is meaningless:
/// a balance is a consequence of the chronological order, so re-sorting by it
/// would print a column that no longer describes anything.
enum MovementSortKey {
  /// Chronological. The ledger reads as a statement and the balance runs.
  date,

  /// By magnitude of the change. The ledger becomes a ranked list, day
  /// grouping dissolves and the balance stops implying continuity.
  change,
}

extension StockMovementsViewModeX on StockMovementsViewMode {
  String get key {
    switch (this) {
      case StockMovementsViewMode.recent:
        return 'recent';
      case StockMovementsViewMode.byProduct:
        return 'by_product';
    }
  }
}

class StockMovementsService extends ChangeNotifier {
  StockMovementsService({
    SupabaseClient? supabase,
    TenantService? tenantService,
    StockMovementsTenantIdLoader? tenantIdLoader,
    StockMovementsStoreTimezoneLoader? storeTimezoneLoader,
    bool enableRealtime = true,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService(),
        _tenantIdLoader = tenantIdLoader,
        _storeTimezoneLoader = storeTimezoneLoader {
    if (enableRealtime) {
      _setupRealtime();
    }
  }

  final SupabaseClient _supabase;
  final TenantService _tenantService;
  final StockMovementsTenantIdLoader? _tenantIdLoader;
  final StockMovementsStoreTimezoneLoader? _storeTimezoneLoader;

  static const String _movementSelect =
      'id,product_id,product_name,product_sku,transaction_date,movement_type,'
      'source,reference_id,reference_number,quantity,stock_before,stock_after,'
      'notes,adjustment_origin,created_by,created_at,tenant_id,raw_quantity,'
      'actual_stock_delta,reconciled_quantity,balance_provenance,'
      'integrity_status,is_summary_excluded,linked_adjustment_id,'
      'canonical_movement_id,operation_id,source_document_type,'
      'source_document_id,evidence_stock_before,evidence_stock_after,'
      'evidence_balance_provenance,evidence_integrity_status,'
      'trigger_operation_id,trigger_action,trigger_source_channel,'
      'trigger_actor_id,trigger_reason';
  static const int _pageSize = 1000;

  /// How many of the newest movements a period-less view loads.
  ///
  /// Only reachable now by explicitly choosing "Todo el período": the module
  /// opens on [defaultPeriod] instead, so the normal case has an exact total
  /// rather than one describing a transport detail.
  static const recentWindow = 100;

  /// The scope the module opens on.
  ///
  /// A period is something an operator can reason about; "the newest 100 rows"
  /// is not, and any total computed over it describes the window rather than
  /// the business.
  static const defaultPeriod = Duration(days: 30);

  static DateTimeRange defaultRange() {
    return defaultRangeForStore(nowUtc: DateTime.now().toUtc());
  }

  @visibleForTesting
  static DateTimeRange defaultRangeForStore({
    required DateTime nowUtc,
    String? storeTimezone,
  }) {
    final storeNow = stockMovementStoreTime(
      nowUtc,
      storeTimezone: storeTimezone,
    );
    final end = DateTime(storeNow.year, storeNow.month, storeNow.day);
    final normalizedStart = DateTime.utc(
      end.year,
      end.month,
      end.day - defaultPeriod.inDays,
    );
    return DateTimeRange(
      start: DateTime(
        normalizedStart.year,
        normalizedStart.month,
        normalizedStart.day,
      ),
      end: end,
    );
  }

  List<StockMovement> _movements = [];
  // The page schedules its first load after the initial frame. Start in the
  // honest state so that frame cannot render zero totals and an empty ledger
  // before the request even exists.
  bool _isLoading = true;
  String? _error;
  String? _selectedProductId;
  String? _typeFilter;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _windowTruncated = false;
  bool _periodExplicitlyCleared = false;
  MovementSortKey _sortKey = MovementSortKey.date;
  bool _ascending = false;
  bool _disposed = false;
  int _loadGeneration = 0;
  _StockMovementQueryScope? _loadedScope;

  // View mode: 'recent' (all products) or 'by_product' (single product)
  StockMovementsViewMode _viewMode = StockMovementsViewMode.recent;

  // Realtime channels
  RealtimeChannel? _movementsChannel;
  RealtimeChannel? _adjustmentsChannel;
  String? _storeLocationTenantId;
  tz.Location? _storeLocation;

  List<StockMovement> get movements => _movements;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get selectedProductId => _selectedProductId;
  String get viewMode => _viewMode.key;
  bool get isRecentMode => _viewMode == StockMovementsViewMode.recent;
  String get storeTimezone =>
      _storeLocation?.name ?? stockMovementsDefaultStoreTimezone;
  String? get typeFilter => _typeFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  MovementSortKey get sortKey => _sortKey;
  bool get ascending => _ascending;

  /// True while the ledger reads as a statement: chronological, so the balance
  /// column runs and day grouping is meaningful. Ranked order dissolves both.
  bool get isChronological => _sortKey == MovementSortKey.date;

  /// The rows a summary may legitimately be computed over.
  ///
  /// Filters compose here instead of at the call site. They used to be applied
  /// as two independent projections of the full list, so the second silently
  /// discarded the first and the movement-type filter never had any effect.
  List<StockMovement> get visibleMovements {
    final type = _typeFilter;
    if (type == null || type == 'all') return _movements;
    return _movements
        .where((movement) => movement.matchesCategoryKey(type))
        .toList(growable: false);
  }

  /// True when the loaded set is the newest [recentWindow] rows rather than a
  /// complete period, so any total derived from it describes the window and not
  /// the business. A date range removes the cap, which is why selecting one is
  /// the honest way to read a period total.
  bool get isWindowTruncated => _windowTruncated;
  bool get isAllPeriodScope =>
      _periodExplicitlyCleared && _startDate == null && _endDate == null;

  /// Setup realtime subscriptions for multi-user collaboration
  Future<void> _setupRealtime() async {
    try {
      final tenantId = await _getTenantId();
      // The constructor starts this task without awaiting it. The provider can
      // be disposed while tenant resolution is still in flight; in that case
      // creating channels afterwards leaks subscriptions owned by a dead
      // service.
      if (_disposed) return;
      if (tenantId == null) {
        debugPrint(
            '⚠️ [StockMovementsService] Cannot setup realtime: no tenant_id');
        return;
      }

      debugPrint(
          '🔔 [StockMovementsService] Setting up realtime for tenant: $tenantId');

      // Subscribe to stock_movements table changes
      _movementsChannel = _supabase
          .channel('stock_movements_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'stock_movements',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              if (_disposed) return;
              debugPrint(
                  '🔔 [StockMovementsService] Stock movement changed: ${payload.eventType}');
              _reloadCurrentView();
            },
          )
          .subscribe();

      // Subscribe to stock_adjustments table changes
      _adjustmentsChannel = _supabase
          .channel('stock_adjustments_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'stock_adjustments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              if (_disposed) return;
              debugPrint(
                  '🔔 [StockMovementsService] Stock adjustment changed: ${payload.eventType}');
              _reloadCurrentView();
            },
          )
          .subscribe();

      debugPrint('✅ [StockMovementsService] Realtime subscriptions active');
    } catch (e) {
      debugPrint('❌ [StockMovementsService] Realtime setup error: $e');
    }
  }

  /// Set view mode and load appropriate data
  void setViewMode(String mode) {
    final nextMode = mode == StockMovementsViewMode.byProduct.key
        ? StockMovementsViewMode.byProduct
        : StockMovementsViewMode.recent;
    if (nextMode == _viewMode) return;
    _viewMode = nextMode;
    _selectedProductId = null;
    _movements = [];
    _isLoading = nextMode == StockMovementsViewMode.recent;
    notifyListeners();

    if (nextMode == StockMovementsViewMode.recent) {
      loadRecentMovements();
    }
  }

  /// Load recent movements across ALL products (for 'recent' view mode)
  ///
  /// Opens on [defaultPeriod] unless a range is already chosen, so the figures
  /// on screen describe a period the operator can name instead of the newest
  /// [recentWindow] rows.
  Future<void> loadRecentMovements({int limit = recentWindow}) async {
    _selectedProductId = null;
    _viewMode = StockMovementsViewMode.recent;
    await _loadMovements(limit: limit);
  }

  /// Widens the scope to the whole history, accepting the row cap.
  Future<void> clearPeriod() async {
    _periodExplicitlyCleared = true;
    _startDate = null;
    _endDate = null;
    await _loadMovements(limit: recentWindow);
  }

  /// Reorders the ledger. Always refetches: ordering a loaded page would sort
  /// the window rather than the ledger.
  Future<void> applySort(MovementSortKey key, {required bool ascending}) async {
    if (_sortKey == key && _ascending == ascending) return;
    _sortKey = key;
    _ascending = ascending;
    await _loadMovements(
      limit: _viewMode == StockMovementsViewMode.recent ? recentWindow : null,
    );
  }

  /// Load movements for a specific product
  Future<void> loadMovementsForProduct(String productId) async {
    _selectedProductId = productId;
    _viewMode = StockMovementsViewMode.byProduct;
    await _loadMovements();
  }

  /// Applies the module filters and refetches.
  ///
  /// The date range is pushed into the query rather than applied to whatever
  /// happened to be loaded. Filtering the newest 100 rows client-side answered
  /// a different question than the one asked: selecting a past month returned
  /// only the rows of that month that survived inside the global tail, and the
  /// summary reported those as the period's totals.
  Future<void> applyFilters({
    String? type,
    DateTime? startDate,
    DateTime? endDate,
    bool refetch = true,
  }) async {
    final rangeChanged = _startDate != startDate || _endDate != endDate;
    _typeFilter = type;
    _startDate = startDate;
    _endDate = endDate;
    if (startDate != null || endDate != null) _periodExplicitlyCleared = false;

    if (!refetch || !rangeChanged) {
      // A type change re-projects the loaded rows; no round trip needed.
      notifyListeners();
      return;
    }
    await _loadMovements(
      limit: _viewMode == StockMovementsViewMode.recent ? recentWindow : null,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _movementsChannel?.unsubscribe();
    _adjustmentsChannel?.unsubscribe();
    super.dispose();
  }

  /// Clear selection
  void clearSelection() {
    _selectedProductId = null;
    _movements = [];
    _isLoading = false;
    notifyListeners();
  }

  /// Get movements list without modifying state (Pure Async)
  Future<List<StockMovement>> getMovementsList(String productId) async {
    final result = await _fetchMovements(productId: productId);
    return result.rows;
  }

  /// Filter movements by date range
  // The former `filterByType` / `filterByDateRange` projections were removed on
  // purpose. Each returned a fresh projection of the complete list, so callers
  // chaining them kept only the last one, and both operated on a set that had
  // already been truncated to the newest rows. Date filtering now happens in
  // the query and type filtering in `visibleMovements`, where it composes.

  /// Get summary statistics
  Map<String, int> getSummary() {
    int totalIncrease = 0;
    int totalDecrease = 0;

    for (var movement in _movements) {
      final quantity = movement.summaryQuantity;
      if (quantity > 0) {
        totalIncrease += quantity;
      } else {
        totalDecrease += quantity.abs();
      }
    }

    return {
      'total_increase': totalIncrease,
      'total_decrease': totalDecrease,
      'net_change': totalIncrease - totalDecrease,
      'transaction_count': _movements.length,
    };
  }

  Future<void> _reloadCurrentView() async {
    if (_viewMode == StockMovementsViewMode.recent) {
      await loadRecentMovements();
      return;
    }

    final selectedProductId = _selectedProductId;
    if (selectedProductId != null) {
      await loadMovementsForProduct(selectedProductId);
    }
  }

  Future<void> _loadMovements({int? limit}) async {
    final generation = ++_loadGeneration;
    _StockMovementQueryScope? requestedScope;
    _isLoading = true;
    _error = null;
    _notifyIfActive();

    try {
      final tenantId = await _requireTenantId();
      if (!_ownsLoad(generation)) return;

      if (_viewMode == StockMovementsViewMode.recent &&
          _startDate == null &&
          _endDate == null &&
          !_periodExplicitlyCleared) {
        final location = await _storeLocationForTenant(tenantId);
        if (!_ownsLoad(generation)) return;
        final range = defaultRangeForStore(
          nowUtc: DateTime.now().toUtc(),
          storeTimezone: location.name,
        );
        _startDate = range.start;
        _endDate = range.end;
      }

      // A date range already bounds the result set, so the window cap would
      // only truncate the period the user explicitly asked for.
      final requestViewMode = _viewMode;
      final requestProductId =
          requestViewMode == StockMovementsViewMode.byProduct
              ? _selectedProductId
              : null;
      final requestStartDate = _startDate;
      final requestEndDate = _endDate;
      final requestSortKey = _sortKey;
      final requestAscending = _ascending;
      requestedScope = _StockMovementQueryScope(
        tenantId: tenantId,
        viewMode: requestViewMode,
        productId: requestProductId,
        startDate: requestStartDate,
        endDate: requestEndDate,
        sortKey: requestSortKey,
        ascending: requestAscending,
      );
      final bounded = requestStartDate != null || requestEndDate != null;
      final effectiveLimit =
          requestViewMode == StockMovementsViewMode.recent && !bounded
              ? limit
              : null;

      final result = await _fetchMovements(
        tenantId: tenantId,
        productId: requestProductId,
        limit: effectiveLimit,
        startDate: requestStartDate,
        endDate: requestEndDate,
        sortKey: requestSortKey,
        ascending: requestAscending,
      );
      if (!_ownsLoad(generation)) return;

      _windowTruncated = result.hasMore;
      // The ledger identifies a product by name and SKU, not by picture, so it
      // no longer pays for a second round trip per load to decorate rows.
      _movements = result.rows;
      _loadedScope = requestedScope;
      _error = null;
      debugPrint(
        '✅ [StockMovementsService] Loaded ${_movements.length} movements in ${requestViewMode.key} mode',
      );
    } catch (e) {
      if (!_ownsLoad(generation)) return;
      _error = e.toString();
      // Keep rows only when they provably belong to the exact same tenant,
      // product, period and ordering. Showing scope A under controls for a
      // failed scope B is worse than an explicit unavailable state.
      if (requestedScope == null || requestedScope != _loadedScope) {
        _movements = const [];
        _windowTruncated = false;
      }
      debugPrint('❌ [StockMovementsService] Error loading stock movements: $e');
    } finally {
      if (_ownsLoad(generation)) {
        _isLoading = false;
        _notifyIfActive();
      }
    }
  }

  bool _ownsLoad(int generation) => !_disposed && generation == _loadGeneration;

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  Future<_StockMovementFetchResult> _fetchMovements({
    String? tenantId,
    String? productId,
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
    MovementSortKey sortKey = MovementSortKey.date,
    bool ascending = false,
  }) async {
    if (limit != null && limit < 0) {
      throw RangeError.value(limit, 'limit', 'Must not be negative');
    }
    final resolvedTenantId = tenantId ?? await _requireTenantId();
    final location = await _storeLocationForTenant(resolvedTenantId);
    final utcBounds = stockMovementUtcDateBounds(
      startDate: startDate,
      endDate: endDate,
      storeTimezone: location.name,
    );

    var query = _supabase
        .from('stock_movements_operational_view')
        .select(_movementSelect)
        .eq('tenant_id', resolvedTenantId);

    if (productId != null && productId.isNotEmpty) {
      query = query.eq('product_id', productId);
    }
    if (utcBounds.startInclusive != null) {
      query = query.gte(
        'created_at',
        utcBounds.startInclusive!.toIso8601String(),
      );
    }
    if (utcBounds.endExclusive != null) {
      // Exclusive upper bound on the next day. Comparing against the end date
      // at 00:00 dropped every movement recorded during that last day.
      query = query.lt(
        'created_at',
        utcBounds.endExclusive!.toIso8601String(),
      );
    }

    // Ordering belongs to the query. Sorting the loaded page client-side would
    // reorder a window rather than the ledger — the same shape of defect the
    // date filter had, and just as invisible.
    //
    // The key is `created_at`, the order the ledger was written in, and that
    // is not a detail: only a handful of rows carry a persisted balance. Every
    // legacy row's `stock_before`/`stock_after` is RECONSTRUCTED by walking
    // backwards from today's stock in insertion order, so presenting the rows
    // in any other order breaks the one invariant a ledger has — each row's
    // closing balance is the next row's opening balance.
    //
    // `date` is the business date of the source document and often differs by
    // days (an invoice entered on 8 July dated 30 June). It is a fact about
    // the document, not the ledger's sequence, so it belongs in the row's
    // detail rather than in its ordering.
    final orderedQuery = switch (sortKey) {
      MovementSortKey.date => query
          .order('created_at', ascending: ascending)
          .order('id', ascending: ascending),
      MovementSortKey.change => query
          .order('reconciled_quantity', ascending: ascending)
          .order('created_at', ascending: false)
          .order('id', ascending: false),
    };
    final targetRowCount = limit == null ? null : limit + 1;
    final fetchedRows = <StockMovement>[];

    while (targetRowCount == null || fetchedRows.length < targetRowCount) {
      final remaining = targetRowCount == null
          ? _pageSize
          : targetRowCount - fetchedRows.length;
      final pageLength = remaining < _pageSize ? remaining : _pageSize;
      final from = fetchedRows.length;
      final to = from + pageLength - 1;
      final response = await orderedQuery.range(from, to);
      final page = (response as List)
          .map(
            (json) => StockMovement.fromJson(
              Map<String, dynamic>.from(json as Map),
            ),
          )
          .toList(growable: false);
      fetchedRows.addAll(page);

      if (page.length < pageLength) {
        break;
      }
    }

    final hasMore = limit != null && fetchedRows.length > limit;
    final visibleRows = hasMore
        ? fetchedRows.take(limit).toList(growable: false)
        : List<StockMovement>.unmodifiable(fetchedRows);
    return _StockMovementFetchResult(rows: visibleRows, hasMore: hasMore);
  }

  Future<String?> _getTenantId() {
    final loader = _tenantIdLoader;
    return loader == null ? _tenantService.getTenantId() : loader();
  }

  Future<String> _requireTenantId() async {
    final tenantId = (await _getTenantId())?.trim();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No tenant_id found');
    }
    return tenantId;
  }

  Future<tz.Location> _storeLocationForTenant(String tenantId) async {
    final cached = _storeLocation;
    if (_storeLocationTenantId == tenantId && cached != null) {
      return cached;
    }

    final injectedLoader = _storeTimezoneLoader;
    String? requestedTimezone;
    if (injectedLoader != null) {
      requestedTimezone = await injectedLoader(tenantId);
    } else {
      final tenant = await _tenantService.getCurrentTenant();
      final resolvedTenantId = tenant?['id']?.toString().trim();
      if (resolvedTenantId == null ||
          resolvedTenantId.isEmpty ||
          resolvedTenantId == tenantId) {
        requestedTimezone = tenant?['timezone']?.toString();
      } else {
        debugPrint(
          '⚠️ [StockMovementsService] Ignoring timezone from a different tenant',
        );
      }
    }

    final resolved = _stockMovementLocation(requestedTimezone);
    _storeLocationTenantId = tenantId;
    _storeLocation = resolved;
    return resolved;
  }

  Future<Map<String, dynamic>?> getOperationTrace(String? operationId) async {
    if (operationId == null || operationId.isEmpty) return null;

    final tenantId = await _requireTenantId();

    final response = await _supabase
        .from('inventory_accounting_operation_trace_enriched_view')
        .select(
          'operation_id,source_channel,action,document_type,document_id,'
          'actor_id,executor,old_status,new_status,outcome,started_at,'
          'completed_at,checkpoints,context,parent_operation_id,parent_action,'
          'parent_source_channel,parent_actor_id,parent_outcome,parent_context',
        )
        .eq('tenant_id', tenantId)
        .eq('operation_id', operationId)
        .maybeSingle();
    return response;
  }
}

class _StockMovementFetchResult {
  const _StockMovementFetchResult({
    required this.rows,
    required this.hasMore,
  });

  final List<StockMovement> rows;
  final bool hasMore;
}

@immutable
class _StockMovementQueryScope {
  const _StockMovementQueryScope({
    required this.tenantId,
    required this.viewMode,
    required this.productId,
    required this.startDate,
    required this.endDate,
    required this.sortKey,
    required this.ascending,
  });

  final String tenantId;
  final StockMovementsViewMode viewMode;
  final String? productId;
  final DateTime? startDate;
  final DateTime? endDate;
  final MovementSortKey sortKey;
  final bool ascending;

  @override
  bool operator ==(Object other) {
    return other is _StockMovementQueryScope &&
        tenantId == other.tenantId &&
        viewMode == other.viewMode &&
        productId == other.productId &&
        startDate == other.startDate &&
        endDate == other.endDate &&
        sortKey == other.sortKey &&
        ascending == other.ascending;
  }

  @override
  int get hashCode => Object.hash(
        tenantId,
        viewMode,
        productId,
        startDate,
        endDate,
        sortKey,
        ascending,
      );
}
