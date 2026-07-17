import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../modules/crm/models/crm_models.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../modules/crm/services/customer_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';
import '../widgets/bike_record_panel.dart';
import 'bike_form_dialog.dart';
import 'mechanic_job_form_page.dart';
import '../../messaging/models/conversation.dart';
import '../../messaging/services/messaging_service.dart';
import '../../messaging/widgets/chat_window.dart';

enum JobViewFilter { active, completed, all }

enum ClientBikePanelMode { none, record, creating, editing }

class ClientLogbookPage extends StatefulWidget {
  final String customerId;
  final String? initialTab;
  final String? initialBikeId;

  const ClientLogbookPage({
    super.key,
    required this.customerId,
    this.initialTab,
    this.initialBikeId,
  });

  @override
  State<ClientLogbookPage> createState() => _ClientLogbookPageState();
}

class _ClientLogbookPageState extends State<ClientLogbookPage>
    with SingleTickerProviderStateMixin {
  Customer? _customer;
  List<Bike> _bikes = [];
  List<MechanicJob> _jobs = [];
  List<MechanicJobTimeline> _timeline = [];
  List<Invoice> _invoices = [];
  Loyalty? _loyalty;
  bool _isLoading = true;
  bool _isLoadingInvoices = false;
  bool _hasLoadedInvoices = false;
  String? _error;
  String? _invoiceError;

  // Chats tab
  final MessagingService _messagingService = MessagingService();
  List<Conversation> _chats = [];
  Conversation? _selectedChat;
  bool _isLoadingChats = false;
  bool _hasLoadedChats = false;
  String? _chatError;

  String? _selectedJobId;
  String? _selectedBikeId;
  bool _isEditingJob = false;
  ClientBikePanelMode _bikePanelMode = ClientBikePanelMode.none;
  BikeRecordSnapshot? _selectedBikeRecordSnapshot;
  bool _isLoadingSelectedBikeRecordSnapshot = false;
  String? _bikeRecordLoadError;

  late TabController _tabController;

  final TextEditingController _bikeSearchController = TextEditingController();
  final TextEditingController _jobSearchController = TextEditingController();
  final TextEditingController _timelineSearchController =
      TextEditingController();
  final TextEditingController _invoiceSearchController =
      TextEditingController();
  String _bikeSearchTerm = '';
  String _jobSearchTerm = '';
  String _timelineSearchTerm = '';
  String _invoiceSearchTerm = '';
  String _bikeSortKey = 'recent';
  String _jobSortKey = 'arrival_desc';
  String _timelineSortKey = 'date_desc';
  String _invoiceSortKey = 'date_desc';
  JobViewFilter _jobViewFilter = JobViewFilter.completed;
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();

  // ── Column sort (column-header click) ──
  String?
      _bikeSortCol; // 'name' | 'serial' | 'registered' | 'last_delivery' | 'jobs'
  bool _bikeSortAsc = true;
  String?
      _jobSortCol; // 'number' | 'bike' | 'request' | 'status' | 'date' | 'total'
  bool _jobSortAsc = false;
  String? _timelineSortCol; // 'desc' | 'ref' | 'tech' | 'date'
  bool _timelineSortAsc = false;
  String?
      _invoiceSortCol; // 'number' | 'context' | 'date' | 'status' | 'total' | 'balance'
  bool _invoiceSortAsc = false;

  // ── Column widths (bikes) ──
  double _bikeColSerial = 150;
  double _bikeColRegistered = 100;
  double _bikeColDelivery = 120;
  double _bikeColJobs = 80;

  // ── Column widths (jobs) ──
  double _jobColNumber = 108;
  double _jobColBike = 140;
  double _jobColStatus = 110;
  double _jobColDate = 90;
  double _jobColTotal = 80;

  // ── Column widths (timeline) ──
  double _tlColRef = 150;
  double _tlColTech = 120;
  double _tlColDate = 130;
  double _invoiceColNumber = 130;
  double _invoiceColDate = 110;
  double _invoiceColStatus = 122;
  double _invoiceColTotal = 110;
  double _invoiceColBalance = 110;
  Map<String, Bike> _bikeIndex = {};
  Map<String?, List<MechanicJob>> _jobsByBike = {};
  Map<String, MechanicJob> _jobIndex = {};
  Set<TimelineEventType> _timelineTypeFilters =
      TimelineEventType.values.toSet();
  static const Map<String, String> _bikeSortLabels = {
    'recent': 'Más recientes',
    'name': 'Nombre (A-Z)',
    'jobs_desc': 'Más trabajos',
    'jobs_asc': 'Menos trabajos',
  };
  static const Map<String, String> _jobSortLabels = {
    'arrival_desc': 'Ingresadas recientes',
    'arrival_asc': 'Ingresadas antiguas',
    'cost_desc': 'Mayor costo',
    'cost_asc': 'Menor costo',
  };
  static const Map<String, String> _timelineSortLabels = {
    'date_desc': 'Más recientes',
    'date_asc': 'Más antiguas',
  };
  static const Map<String, String> _invoiceSortLabels = {
    'date_desc': 'Más recientes',
    'date_asc': 'Más antiguas',
    'total_desc': 'Mayor total',
    'total_asc': 'Menor total',
    'balance_desc': 'Mayor saldo',
    'balance_asc': 'Menor saldo',
  };

  @override
  void initState() {
    super.initState();
    final initialBikeId = widget.initialBikeId?.trim();
    final initialIndex = _resolveTabIndex(
      initialTab: widget.initialTab,
      initialBikeId: initialBikeId,
    );
    if (initialBikeId != null && initialBikeId.isNotEmpty) {
      _selectedBikeId = initialBikeId;
      _bikePanelMode = ClientBikePanelMode.record;
    }
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: initialIndex,
    )..addListener(_handleTabChanged);

    _bikeSearchController.addListener(_handleBikeSearchChanged);
    _jobSearchController.addListener(_handleJobSearchChanged);
    _timelineSearchController.addListener(_handleTimelineSearchChanged);
    _invoiceSearchController.addListener(_handleInvoiceSearchChanged);

    _headerScrollController.addListener(() {
      if (_bodyScrollController.hasClients &&
          _bodyScrollController.offset != _headerScrollController.offset) {
        _bodyScrollController.jumpTo(_headerScrollController.offset);
      }
    });

    _bodyScrollController.addListener(() {
      if (_headerScrollController.hasClients &&
          _headerScrollController.offset != _bodyScrollController.offset) {
        _headerScrollController.jumpTo(_bodyScrollController.offset);
      }
    });

    _loadData();
    if (initialIndex == 2) {
      unawaited(_loadInvoices());
    }
    if (initialIndex == 3) {
      unawaited(_loadChats());
    }
  }

  @override
  void didUpdateWidget(covariant ClientLogbookPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.customerId != oldWidget.customerId) {
      final nextBikeId = widget.initialBikeId?.trim();
      final nextIndex = _resolveTabIndex(
        initialTab: widget.initialTab,
        initialBikeId: nextBikeId,
      );

      setState(() {
        _customer = null;
        _bikes = [];
        _jobs = [];
        _timeline = [];
        _invoices = [];
        _loyalty = null;
        _selectedJobId = null;
        _selectedBikeId =
            nextBikeId != null && nextBikeId.isNotEmpty ? nextBikeId : null;
        _bikePanelMode = _selectedBikeId != null
            ? ClientBikePanelMode.record
            : ClientBikePanelMode.none;
        _selectedBikeRecordSnapshot = null;
        _isLoadingSelectedBikeRecordSnapshot = false;
        _bikeRecordLoadError = null;
        _isLoading = true;
        _isLoadingInvoices = false;
        _hasLoadedInvoices = false;
        _error = null;
        _invoiceError = null;
        _chats = [];
        _selectedChat = null;
        _isLoadingChats = false;
        _hasLoadedChats = false;
        _chatError = null;
        _tabController.index = nextIndex;
      });

      unawaited(_loadData());
      if (nextIndex == 3) {
        unawaited(_loadInvoices());
      }
      if (nextIndex == 4) {
        unawaited(_loadChats());
      }
      return;
    }

    final nextBikeId = widget.initialBikeId?.trim();
    final previousBikeId = oldWidget.initialBikeId?.trim();
    final nextTab = widget.initialTab;
    final previousTab = oldWidget.initialTab;

    if (nextBikeId != previousBikeId) {
      if (nextBikeId != null && nextBikeId.isNotEmpty) {
        setState(() {
          _selectedBikeId = nextBikeId;
          _bikePanelMode = ClientBikePanelMode.record;
          _tabController.index = 0;
        });
        if (_bikeIndex.containsKey(nextBikeId)) {
          unawaited(_loadSelectedBikeRecordSnapshot(nextBikeId));
        }
      } else if (previousBikeId != null && previousBikeId.isNotEmpty) {
        _closeBikePane();
      }
    } else if (nextTab != previousTab) {
      final nextIndex = _resolveTabIndex(
        initialTab: nextTab,
        initialBikeId: nextBikeId,
      );
      if (_tabController.index != nextIndex) {
        _tabController.index = nextIndex;
      }
      if (nextIndex == 3 && !_hasLoadedInvoices && !_isLoadingInvoices) {
        unawaited(_loadInvoices());
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    _bikeSearchController.removeListener(_handleBikeSearchChanged);
    _jobSearchController.removeListener(_handleJobSearchChanged);
    _timelineSearchController.removeListener(_handleTimelineSearchChanged);
    _invoiceSearchController.removeListener(_handleInvoiceSearchChanged);
    _bikeSearchController.dispose();
    _jobSearchController.dispose();
    _timelineSearchController.dispose();
    _invoiceSearchController.dispose();
    super.dispose();
  }

  int _resolveTabIndex({String? initialTab, String? initialBikeId}) {
    if (initialBikeId != null && initialBikeId.isNotEmpty) {
      return 0;
    }

    switch (initialTab) {
      case 'pegas':
        return 1;
      case 'facturas':
      case 'invoices':
        return 2;
      case 'chats':
        return 3;
      case 'historial':
        return 4;
      default:
        return 0;
    }
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }

    if (_tabController.index == 2 &&
        !_hasLoadedInvoices &&
        !_isLoadingInvoices) {
      unawaited(_loadInvoices());
    }
    if (_tabController.index == 3 && !_hasLoadedChats && !_isLoadingChats) {
      unawaited(_loadChats());
    }
  }

  void _handleInvoiceSearchChanged() {
    setState(() {
      _invoiceSearchTerm = _invoiceSearchController.text.trim();
    });
  }

  void _handleBikeSearchChanged() {
    setState(() {
      _bikeSearchTerm = _bikeSearchController.text.trim();
    });
  }

  void _handleJobSearchChanged() {
    setState(() {
      _jobSearchTerm = _jobSearchController.text.trim();
    });
  }

  void _handleTimelineSearchChanged() {
    setState(() {
      _timelineSearchTerm = _timelineSearchController.text.trim();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);

      // Load customer data
      final customer = await customerService.getCustomerById(widget.customerId);
      final loyalty =
          await customerService.getCustomerLoyalty(widget.customerId);

      if (customer == null) {
        setState(() {
          _error = 'Cliente no encontrado';
          _isLoading = false;
        });
        return;
      }

      // Load bikes for this customer
      final bikes =
          await bikeshopService.getBikes(customerId: widget.customerId);
      final bikeIndex = <String, Bike>{
        for (final bike in bikes)
          if (bike.id != null && bike.id!.isNotEmpty) bike.id!: bike,
      };

      // Load all jobs for this customer
      final jobs = await bikeshopService.getJobs(
        customerId: widget.customerId,
        includeCompleted: true,
      );
      final jobsByBike = <String?, List<MechanicJob>>{};
      final jobIndex = <String, MechanicJob>{};
      for (final job in jobs) {
        if (job.id != null && job.id!.isNotEmpty) {
          jobIndex[job.id!] = job;
        }
        jobsByBike.putIfAbsent(job.bikeId, () => []).add(job);
      }

      // Load combined timeline from all jobs
      final allTimeline = <MechanicJobTimeline>[];
      if (kDebugMode) {
        print('📋 Loading timeline for ${jobs.length} jobs...');
      }

      for (final job in jobs) {
        if (job.id == null) continue;

        try {
          final jobTimeline = await bikeshopService.getJobTimeline(job.id!);
          if (kDebugMode) {
            print(
                '📋 Job ${job.jobNumber}: ${jobTimeline.length} timeline events');
          }
          allTimeline.addAll(jobTimeline);
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error loading timeline for job ${job.id}: $e');
          }
        }
      }

      if (kDebugMode) {
        print('📋 Total timeline events loaded: ${allTimeline.length}');
      }

      // Sort timeline by date descending (most recent first)
      allTimeline.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final requestedBikeId = widget.initialBikeId?.trim();
      final requestedBikeExists = requestedBikeId != null &&
          requestedBikeId.isNotEmpty &&
          bikeIndex.containsKey(requestedBikeId);
      final selectedBikeStillExists = requestedBikeExists ||
          _selectedBikeId == null ||
          bikeIndex.containsKey(_selectedBikeId);

      setState(() {
        _customer = customer;
        _bikes = bikes;
        _jobs = jobs;
        _bikeIndex = bikeIndex;
        _jobsByBike = jobsByBike;
        _jobIndex = jobIndex;
        _timeline = allTimeline;
        _loyalty = loyalty;
        if (requestedBikeExists) {
          _selectedBikeId = requestedBikeId;
          _bikePanelMode = ClientBikePanelMode.record;
          _tabController.index = 0;
        } else if (!selectedBikeStillExists) {
          _selectedBikeId = null;
          _bikePanelMode = ClientBikePanelMode.none;
          _selectedBikeRecordSnapshot = null;
          _isLoadingSelectedBikeRecordSnapshot = false;
        }
        _isLoading = false;
      });

      if ((requestedBikeExists || selectedBikeStillExists) &&
          _selectedBikeId != null) {
        unawaited(_loadSelectedBikeRecordSnapshot(_selectedBikeId));
      }

      // Eagerly load invoices so totalSpent stat is accurate on first render
      unawaited(_loadInvoices());
    } catch (e) {
      setState(() {
        _error = 'Error al cargar datos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadInvoices({bool forceRefresh = false}) async {
    if (_isLoadingInvoices) {
      return;
    }

    final salesService = context.read<SalesService>();

    if (!forceRefresh && salesService.hasInvoicesCache) {
      final cachedInvoices = salesService.cachedInvoices
          .where((invoice) => invoice.customerId == widget.customerId)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (mounted) {
        setState(() {
          _invoices = cachedInvoices;
          _hasLoadedInvoices = true;
          _invoiceError = null;
        });
      }
    }

    setState(() {
      _isLoadingInvoices = true;
      _invoiceError = null;
    });

    try {
      final invoices = await salesService.getInvoicesForCustomer(
        customerId: widget.customerId,
        forceRefresh: forceRefresh,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _invoices = invoices;
        _hasLoadedInvoices = true;
        _isLoadingInvoices = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _invoiceError = 'No se pudieron cargar las facturas';
        _isLoadingInvoices = false;
        _hasLoadedInvoices = true;
      });
    }
  }

  Future<void> _loadChats({bool forceRefresh = false}) async {
    if (_isLoadingChats && !forceRefresh) return;

    setState(() {
      _isLoadingChats = true;
      _chatError = null;
    });

    try {
      final chats = await _messagingService
          .getConversationsForCustomer(widget.customerId);

      if (!mounted) return;

      setState(() {
        _chats = chats;
        _hasLoadedChats = true;
        _isLoadingChats = false;
        if (_selectedChat == null && chats.isNotEmpty) {
          _selectedChat = chats.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatError = 'No se pudieron cargar los chats';
        _isLoadingChats = false;
        _hasLoadedChats = true;
      });
    }
  }

  List<Bike> _getFilteredBikes() {
    final term = _bikeSearchTerm.toLowerCase();
    final filtered = _bikes.where((bike) {
      if (term.isEmpty) return true;
      final candidates = [
        bike.displayName,
        bike.brand,
        bike.model,
        bike.serialNumber,
        bike.color,
        bike.notes,
        bike.bikeType?.displayName,
      ];
      return candidates.any(
        (value) => value != null && value.toLowerCase().contains(term),
      );
    }).toList();

    if (_bikeSortCol != null) {
      filtered.sort((a, b) {
        int cmp;
        switch (_bikeSortCol!) {
          case 'name':
            cmp = a.displayName
                .toLowerCase()
                .compareTo(b.displayName.toLowerCase());
            break;
          case 'serial':
            cmp = (a.serialNumber ?? '').compareTo(b.serialNumber ?? '');
            break;
          case 'registered':
            cmp = a.createdAt.compareTo(b.createdAt);
            break;
          case 'last_delivery':
            final aD = _jobs
                .where((j) => j.bikeId == a.id && j.deliveredAt != null)
                .fold<DateTime?>(
                    null,
                    (p, j) => p == null || j.deliveredAt!.isAfter(p)
                        ? j.deliveredAt
                        : p);
            final bD = _jobs
                .where((j) => j.bikeId == b.id && j.deliveredAt != null)
                .fold<DateTime?>(
                    null,
                    (p, j) => p == null || j.deliveredAt!.isAfter(p)
                        ? j.deliveredAt
                        : p);
            cmp = (aD ?? DateTime(0)).compareTo(bD ?? DateTime(0));
            break;
          case 'jobs':
            cmp = _totalJobsForBike(a.id).compareTo(_totalJobsForBike(b.id));
            break;
          default:
            cmp = 0;
        }
        return _bikeSortAsc ? cmp : -cmp;
      });
    } else {
      filtered.sort((a, b) {
        switch (_bikeSortKey) {
          case 'name':
            return a.displayName.toLowerCase().compareTo(
                  b.displayName.toLowerCase(),
                );
          case 'jobs_desc':
            final aCount = _totalJobsForBike(a.id);
            final bCount = _totalJobsForBike(b.id);
            return bCount.compareTo(aCount);
          case 'jobs_asc':
            final aCount = _totalJobsForBike(a.id);
            final bCount = _totalJobsForBike(b.id);
            return aCount.compareTo(bCount);
          case 'recent':
          default:
            return b.updatedAt.compareTo(a.updatedAt);
        }
      });
    }

    return filtered;
  }

  List<MechanicJob> _getFilteredJobs() {
    Iterable<MechanicJob> filtered = _jobs;

    switch (_jobViewFilter) {
      case JobViewFilter.active:
        filtered = filtered.where((job) =>
            job.status != JobStatus.entregado &&
            job.status != JobStatus.cancelado);
        break;
      case JobViewFilter.completed:
        filtered = filtered.where((job) => job.status == JobStatus.entregado);
        break;
      case JobViewFilter.all:
        break;
    }

    final term = _jobSearchTerm.toLowerCase();
    if (term.isNotEmpty) {
      filtered = filtered.where((job) {
        final bikeName = _bikeIndex[job.bikeId]?.displayName;
        final candidates = [
          job.jobNumber,
          job.isQuotationWorkflow ? job.proposalDocumentLabel : null,
          job.isStandaloneQuotation ? 'Sin objeto recibido' : null,
          job.clientRequest,
          job.subjectNotes,
          job.diagnosis,
          job.workPerformed,
          job.notes,
          job.assignedTechnicianName,
          bikeName,
        ];
        return candidates.any(
          (value) => value != null && value.toLowerCase().contains(term),
        );
      });
    }

    final result = filtered.toList();
    if (_jobSortCol != null) {
      result.sort((a, b) {
        int cmp;
        switch (_jobSortCol!) {
          case 'number':
            cmp = (a.jobNumber ?? '').compareTo(b.jobNumber ?? '');
            break;
          case 'bike':
            final aBike = _bikeIndex[a.bikeId]?.displayName ?? '';
            final bBike = _bikeIndex[b.bikeId]?.displayName ?? '';
            cmp = aBike.compareTo(bBike);
            break;
          case 'request':
            cmp = (a.clientRequest ?? '').compareTo(b.clientRequest ?? '');
            break;
          case 'status':
            cmp = a.statusDisplayName.compareTo(b.statusDisplayName);
            break;
          case 'date':
            cmp = a.arrivalDate.compareTo(b.arrivalDate);
            break;
          case 'total':
            cmp = a.totalCost.compareTo(b.totalCost);
            break;
          default:
            cmp = 0;
        }
        return _jobSortAsc ? cmp : -cmp;
      });
    } else {
      result.sort((a, b) {
        switch (_jobSortKey) {
          case 'arrival_asc':
            return a.arrivalDate.compareTo(b.arrivalDate);
          case 'cost_desc':
            return b.totalCost.compareTo(a.totalCost);
          case 'cost_asc':
            return a.totalCost.compareTo(b.totalCost);
          case 'arrival_desc':
          default:
            return b.arrivalDate.compareTo(a.arrivalDate);
        }
      });
    }

    return result;
  }

  List<Invoice> _getFilteredInvoices() {
    final term = _invoiceSearchTerm.toLowerCase();
    final filtered = _invoices.where((invoice) {
      if (term.isEmpty) {
        return true;
      }

      final bikeName = _bikeIndex[invoice.bikeId]?.displayName;
      final candidates = [
        invoice.invoiceNumber,
        invoice.reference,
        invoice.jobNumber,
        bikeName,
        _invoiceStatusLabel(invoice.status),
        _invoiceTypeLabel(invoice),
      ];
      return candidates.any(
        (value) => value != null && value.toLowerCase().contains(term),
      );
    }).toList();

    if (_invoiceSortCol != null) {
      filtered.sort((a, b) {
        int cmp;
        switch (_invoiceSortCol!) {
          case 'number':
            cmp = a.invoiceNumber.compareTo(b.invoiceNumber);
            break;
          case 'context':
            cmp = _invoiceContextSortValue(a)
                .compareTo(_invoiceContextSortValue(b));
            break;
          case 'date':
            cmp = a.date.compareTo(b.date);
            break;
          case 'status':
            cmp = _invoiceStatusLabel(a.status)
                .compareTo(_invoiceStatusLabel(b.status));
            break;
          case 'total':
            cmp = a.total.compareTo(b.total);
            break;
          case 'balance':
            cmp = a.balance.compareTo(b.balance);
            break;
          default:
            cmp = 0;
        }
        return _invoiceSortAsc ? cmp : -cmp;
      });
      return filtered;
    }

    filtered.sort((a, b) {
      switch (_invoiceSortKey) {
        case 'date_asc':
          return a.date.compareTo(b.date);
        case 'total_desc':
          return b.total.compareTo(a.total);
        case 'total_asc':
          return a.total.compareTo(b.total);
        case 'balance_desc':
          return b.balance.compareTo(a.balance);
        case 'balance_asc':
          return a.balance.compareTo(b.balance);
        case 'date_desc':
        default:
          return b.date.compareTo(a.date);
      }
    });

    return filtered;
  }

  int _totalJobsForBike(String? bikeId) {
    if (bikeId == null) return 0;
    return _jobsByBike[bikeId]?.length ?? 0;
  }

  int _activeJobsForBike(String? bikeId) {
    if (bikeId == null) return 0;
    final jobs = _jobsByBike[bikeId];
    if (jobs == null) return 0;
    return jobs
        .where((job) =>
            job.status != JobStatus.entregado &&
            job.status != JobStatus.cancelado)
        .length;
  }

  double _tableViewportWidth(BoxConstraints constraints) {
    final viewportWidth = constraints.maxWidth;
    if (viewportWidth.isFinite && viewportWidth > 0) return viewportWidth;
    return MediaQuery.of(context).size.width - 32;
  }

  double _bikeTableWidth(double viewportWidth) {
    final fixedWidth = 52 +
        _bikeColSerial +
        _bikeColRegistered +
        _bikeColDelivery +
        _bikeColJobs +
        44;
    final desiredWidth = fixedWidth + 320;
    return desiredWidth > viewportWidth ? desiredWidth : viewportWidth;
  }

  double _jobTableWidth(double viewportWidth) {
    final fixedWidth = 4 +
        _jobColNumber +
        _jobColBike +
        _jobColStatus +
        _jobColDate +
        _jobColTotal +
        44;
    final desiredWidth = fixedWidth + 320;
    return desiredWidth > viewportWidth ? desiredWidth : viewportWidth;
  }

  double _timelineTableWidth(double viewportWidth) {
    final fixedWidth = 52 + _tlColRef + _tlColTech + _tlColDate;
    final desiredWidth = fixedWidth + 360;
    return desiredWidth > viewportWidth ? desiredWidth : viewportWidth;
  }

  double _invoiceTableWidth(double viewportWidth) {
    final fixedWidth = 4 +
        _invoiceColNumber +
        _invoiceColDate +
        _invoiceColStatus +
        _invoiceColTotal +
        _invoiceColBalance +
        44;
    final desiredWidth = fixedWidth + 320;
    return desiredWidth > viewportWidth ? desiredWidth : viewportWidth;
  }

  double _bikeNameColumnWidth(double tableWidth) {
    return tableWidth -
        (52 +
            _bikeColSerial +
            _bikeColRegistered +
            _bikeColDelivery +
            _bikeColJobs +
            44);
  }

  double _jobRequestColumnWidth(double tableWidth) {
    return tableWidth -
        (4 +
            _jobColNumber +
            _jobColBike +
            _jobColStatus +
            _jobColDate +
            _jobColTotal +
            44);
  }

  double _timelineDescriptionColumnWidth(double tableWidth) {
    return tableWidth - (52 + _tlColRef + _tlColTech + _tlColDate);
  }

  double _invoiceContextColumnWidth(double tableWidth) {
    return tableWidth -
        (4 +
            _invoiceColNumber +
            _invoiceColDate +
            _invoiceColStatus +
            _invoiceColTotal +
            _invoiceColBalance +
            44);
  }

  String _jobFilterLabel(JobViewFilter filter) {
    switch (filter) {
      case JobViewFilter.active:
        return 'Activas';
      case JobViewFilter.completed:
        return 'Entregadas';
      case JobViewFilter.all:
        return 'Todas';
    }
  }

  String _invoiceStatusLabel(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Borrador';
      case InvoiceStatus.sent:
        return 'Enviada';
      case InvoiceStatus.confirmed:
        return 'Confirmada';
      case InvoiceStatus.paid:
        return 'Pagada';
      case InvoiceStatus.overdue:
        return 'Vencida';
      case InvoiceStatus.cancelled:
        return 'Anulada';
    }
  }

  String _invoiceTypeLabel(Invoice invoice) {
    switch (invoice.invoiceType) {
      case 'pega':
        return 'Taller';
      case 'service':
        return 'Servicio';
      case 'sale':
      default:
        return 'Venta';
    }
  }

  String _invoiceContextSortValue(Invoice invoice) {
    final bikeName = _bikeIndex[invoice.bikeId]?.displayName;
    return [
      bikeName,
      invoice.jobNumber,
      invoice.reference,
      _invoiceTypeLabel(invoice),
    ].whereType<String>().join(' ').toLowerCase();
  }

  Bike _getBikeForJob(MechanicJob job) {
    if (job.bikeId == null || job.isComponentIntake) {
      // Display-only object label. A standalone quotation must never look like
      // a bicycle was received by the workshop.
      final subjectName = job.subjectData?.name.trim();
      final subjectNotes = job.subjectNotes?.trim();
      final label = job.isStandaloneQuotation
          ? 'Cotización'
          : job.isComponentIntake
              ? (subjectName?.isNotEmpty == true
                  ? subjectName!
                  : subjectNotes?.isNotEmpty == true
                      ? subjectNotes!
                      : 'Componente recibido')
              : job.subjectData?.name ?? job.jobType.displayName;
      return Bike(
        id: null,
        tenantId: '',
        customerId: job.customerId,
        brand: label,
        model: job.isStandaloneQuotation ? 'Sin objeto recibido' : null,
        createdAt: job.createdAt,
        updatedAt: job.updatedAt,
      );
    }
    final bike = _bikeIndex[job.bikeId];
    if (bike != null) return bike;
    // Fallback bike for display only (not saved to DB)
    return Bike(
      id: job.bikeId,
      tenantId: '', // Fallback only - this bike won't be saved
      customerId: job.customerId,
      brand: 'Bicicleta',
      model: 'sin datos',
      bikeType: BikeType.other,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
    );
  }

  List<MechanicJobTimeline> _getFilteredTimeline() {
    Iterable<MechanicJobTimeline> filtered = _timeline;

    if (_timelineTypeFilters.isNotEmpty &&
        _timelineTypeFilters.length < TimelineEventType.values.length) {
      filtered = filtered.where(
        (event) => _timelineTypeFilters.contains(event.eventType),
      );
    }

    final term = _timelineSearchTerm.toLowerCase();
    if (term.isNotEmpty) {
      filtered = filtered.where((event) {
        final job = event.jobId.isNotEmpty ? _jobIndex[event.jobId] : null;
        final bike = job != null ? _bikeIndex[job.bikeId] : null;
        final defaultDescription = _getDefaultDescription(event.eventType);
        final candidates = [
          event.description,
          defaultDescription,
          event.oldValue,
          event.newValue,
          event.createdByName,
          job?.jobNumber,
          bike?.displayName,
        ];
        return candidates.any(
          (value) => value != null && value.toLowerCase().contains(term),
        );
      });
    }

    final result = filtered.toList();
    if (_timelineSortCol != null) {
      result.sort((a, b) {
        int cmp;
        final aJob = a.jobId.isNotEmpty ? _jobIndex[a.jobId] : null;
        final bJob = b.jobId.isNotEmpty ? _jobIndex[b.jobId] : null;
        switch (_timelineSortCol!) {
          case 'desc':
            final aDesc = a.description ?? _getDefaultDescription(a.eventType);
            final bDesc = b.description ?? _getDefaultDescription(b.eventType);
            cmp = aDesc.compareTo(bDesc);
            break;
          case 'ref':
            cmp = (aJob?.jobNumber ?? '').compareTo(bJob?.jobNumber ?? '');
            break;
          case 'tech':
            cmp = (a.createdByName ?? '').compareTo(b.createdByName ?? '');
            break;
          case 'date':
            cmp = a.createdAt.compareTo(b.createdAt);
            break;
          default:
            cmp = 0;
        }
        return _timelineSortAsc ? cmp : -cmp;
      });
    } else {
      result.sort((a, b) {
        switch (_timelineSortKey) {
          case 'date_asc':
            return a.createdAt.compareTo(b.createdAt);
          case 'date_desc':
          default:
            return b.createdAt.compareTo(a.createdAt);
        }
      });
    }

    return result;
  }

  String _timelineEventLabel(TimelineEventType type) {
    return type.displayName;
  }

  IconData _timelineIcon(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.created:
        return Icons.add_circle;
      case TimelineEventType.statusChanged:
        return Icons.swap_horiz;
      case TimelineEventType.assigned:
        return Icons.person_add;
      case TimelineEventType.diagnosisAdded:
        return Icons.description;
      case TimelineEventType.partsAdded:
        return Icons.build_circle;
      case TimelineEventType.laborAdded:
        return Icons.work;
      case TimelineEventType.photoAdded:
        return Icons.photo_camera;
      case TimelineEventType.noteAdded:
        return Icons.note;
      case TimelineEventType.approved:
        return Icons.check_circle;
      case TimelineEventType.invoiced:
        return Icons.receipt;
      case TimelineEventType.paid:
        return Icons.attach_money;
      case TimelineEventType.completed:
        return Icons.done_all;
      case TimelineEventType.delivered:
        return Icons.local_shipping;
    }
  }

  Color _timelineColor(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.created:
        return Colors.blue;
      case TimelineEventType.statusChanged:
        return Colors.purple;
      case TimelineEventType.assigned:
        return Colors.teal;
      case TimelineEventType.diagnosisAdded:
        return Colors.orange;
      case TimelineEventType.partsAdded:
        return Colors.amber;
      case TimelineEventType.laborAdded:
        return Colors.indigo;
      case TimelineEventType.photoAdded:
        return Colors.pink;
      case TimelineEventType.noteAdded:
        return Colors.cyan;
      case TimelineEventType.approved:
        return Colors.green;
      case TimelineEventType.invoiced:
        return Colors.deepPurple;
      case TimelineEventType.paid:
        return Colors.green;
      case TimelineEventType.completed:
        return Colors.teal;
      case TimelineEventType.delivered:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: _customer?.name ?? 'Historial del Cliente',
      onBackPressed: () => context.pop(),
      body: _isLoading
          ? const Center(child: BrandedLoading())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _customer == null
                  ? const Center(child: Text('Cliente no encontrado'))
                  : _buildContent(),
    );
  }

  // ─────────────────────────────────────────────
  // MAIN LAYOUT
  // ─────────────────────────────────────────────

  Widget _buildContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Left panel: fixed identity column ──
        SizedBox(
          width: 256,
          child: _buildLeftPanel(),
        ),
        // ── Vertical divider ──
        const VerticalDivider(width: 1, thickness: 1),
        // ── Right panel: tabbed content area ──
        Expanded(
          child: _buildRightPanel(),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // LEFT PANEL  (compact identity card + stats)
  // ─────────────────────────────────────────────

  Widget _buildLeftPanel() {
    final theme = Theme.of(context);
    final c = _customer!;
    final totalJobs = _jobs.length;
    final activeJobs = _jobs
        .where((j) =>
            j.status != JobStatus.entregado && j.status != JobStatus.cancelado)
        .length;
    final completedJobs =
        _jobs.where((j) => j.status == JobStatus.entregado).length;
    // Use invoice paid amounts when loaded (accurate); fall back to job costs otherwise
    final totalSpent = _hasLoadedInvoices
        ? _invoices.fold(0.0, (sum, inv) => sum + inv.paidAmount)
        : _jobs
            .where((j) => j.status == JobStatus.entregado)
            .fold(0.0, (sum, j) => sum + j.totalCost);

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Back link ──
            GestureDetector(
              onTap: () => context.go('/clientes'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios_new_rounded,
                      size: 12, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Clientes',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Identity ──
            Center(
              child: CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  c.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              c.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (_loyalty != null) ...[
              const SizedBox(height: 6),
              Center(child: _buildLoyaltyBadge()),
            ],

            const SizedBox(height: 20),

            // ── Contact info ──
            if (c.phone != null && c.phone!.isNotEmpty)
              _buildInfoRow(Icons.phone_outlined, c.phone!),
            if (c.email != null && c.email!.isNotEmpty)
              _buildInfoRow(Icons.email_outlined, c.email!),
            if (c.rut.isNotEmpty) _buildInfoRow(Icons.badge_outlined, c.rut),
            if (c.address != null && c.address!.isNotEmpty)
              _buildInfoRow(Icons.place_outlined, c.address!),

            const SizedBox(height: 20),
            Divider(thickness: 1, color: theme.dividerColor),
            const SizedBox(height: 16),

            // ── Stats ──
            _buildStatRow('Bicicletas', _bikes.length.toString()),
            _buildStatRow('Total trabajos', totalJobs.toString()),
            _buildStatRow('En curso', activeJobs.toString(),
                highlight: activeJobs > 0),
            _buildStatRow('Entregadas', completedJobs.toString()),
            _buildStatRow(
              'Total ingresado',
              NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                  .format(totalSpent),
            ),
            _buildStatRow(
              'Cliente desde',
              DateFormat('MMM yyyy', 'es').format(c.createdAt),
            ),

            if (_loyalty != null) ...[
              const SizedBox(height: 16),
              Divider(thickness: 1, color: theme.dividerColor),
              const SizedBox(height: 16),
              _buildLoyaltySection(),
            ],

            const SizedBox(height: 24),
            Divider(thickness: 1, color: theme.dividerColor),
            const SizedBox(height: 16),

            // ── Actions ──
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  if (MediaQuery.of(context).size.width < 900) {
                    context.push('/taller/pegas/nueva?customer_id=${c.id}');
                  } else {
                    setState(() {
                      _selectedJobId = null;
                      _isEditingJob = true;
                      _tabController.index = 1; // Jobs tab
                    });
                  }
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nuevo Trabajo'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context
                    .push('/clientes/${c.id}/editar')
                    .then((_) => _loadData()),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar Cliente'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {bool highlight = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: highlight ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoyaltyBadge() {
    if (_loyalty == null) return const SizedBox.shrink();
    final color = _getLoyaltyColor(_loyalty!.tier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_getLoyaltyIcon(_loyalty!.tier), size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          _getLoyaltyTierName(_loyalty!.tier),
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildLoyaltySection() {
    if (_loyalty == null) return const SizedBox.shrink();
    final color = _getLoyaltyColor(_loyalty!.tier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_getLoyaltyIcon(_loyalty!.tier), size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              _getLoyaltyTierName(_loyalty!.tier),
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
            const Spacer(),
            Text(
              '${_loyalty!.points} pts',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey[500]),
              onSelected: (value) {
                if (value == 'add') _showAddPointsDialog();
                if (value == 'redeem') _showRedeemPointsDialog();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Agregar puntos')),
                PopupMenuItem(value: 'redeem', child: Text('Canjear puntos')),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // RIGHT PANEL  (tabbed content)
  // ─────────────────────────────────────────────

  Widget _buildRightPanel() {
    final theme = Theme.of(context);
    final activeJobs = _jobs
        .where((j) =>
            j.status != JobStatus.entregado && j.status != JobStatus.cancelado)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Tab bar row with context actions ──
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Bicicletas'),
                        if (_bikes.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildTabCount(_bikes.length),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Trabajos'),
                        if (_jobs.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildTabCount(
                            _jobs.length,
                            highlight: activeJobs > 0,
                            highlightValue: activeJobs,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Facturas'),
                        if (_invoices.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildTabCount(
                            _invoices.length,
                            highlight: _invoices.any(
                              (invoice) =>
                                  invoice.balance > 0.01 &&
                                  invoice.status != InvoiceStatus.cancelled,
                            ),
                            highlightValue: _invoices
                                .where((invoice) =>
                                    invoice.balance > 0.01 &&
                                    invoice.status != InvoiceStatus.cancelled)
                                .length,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Chats'),
                        if (_chats.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildTabCount(
                            _chats.length,
                            highlight: _chats.any((c) => c.unreadCount > 0),
                            highlightValue:
                                _chats.where((c) => c.unreadCount > 0).length,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Historial'),
                        if (_timeline.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _buildTabCount(_timeline.length),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Context-sensitive action button per tab
              AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  if (_tabController.index == 0) {
                    return TextButton.icon(
                      onPressed: () async {
                        if (MediaQuery.of(context).size.width < 900) {
                          final savedBike = await showDialog<Bike>(
                            context: context,
                            builder: (_) =>
                                BikeFormDialog(customerId: widget.customerId),
                          );
                          if (savedBike != null) _loadData();
                        } else {
                          _openNewBikePane();
                        }
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Agregar Bicicleta'),
                    );
                  }
                  if (_tabController.index == 1) {
                    return TextButton.icon(
                      onPressed: () {
                        if (MediaQuery.of(context).size.width < 900) {
                          context.push(
                              '/taller/pegas/nueva?customer_id=${_customer!.id}');
                        } else {
                          setState(() {
                            _selectedJobId = null;
                            _isEditingJob = true;
                          });
                        }
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Nuevo Trabajo'),
                    );
                  }
                  if (_tabController.index == 3) {
                    return TextButton.icon(
                      onPressed: () {
                        context
                            .push(
                                '/sales/invoices/new?customer_id=${widget.customerId}')
                            .then((_) {
                          if (!mounted) {
                            return;
                          }
                          unawaited(_loadInvoices(forceRefresh: true));
                        });
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Nueva Factura'),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),

        // ── Tab views ──
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildBikesTab(),
              _buildJobsTab(),
              _buildInvoicesTab(),
              _buildChatsTab(),
              _buildTimelineTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabCount(int count,
      {bool highlight = false, int? highlightValue}) {
    final theme = Theme.of(context);
    final display =
        (highlight && highlightValue != null) ? highlightValue : count;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        display.toString(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: highlight ? theme.colorScheme.primary : Colors.grey[600],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BIKES TAB
  // ─────────────────────────────────────────────

  Widget _buildBikesTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        if (!isDesktop && _bikePanelMode == ClientBikePanelMode.none) {
          return _buildBikesList();
        }

        final showRightPane =
            isDesktop && _bikePanelMode != ClientBikePanelMode.none;
        if (!isDesktop && _bikePanelMode != ClientBikePanelMode.none) {
          final selectedBike = _selectedBikeId != null
              ? _bikes.where((b) => b.id == _selectedBikeId).firstOrNull
              : null;
          return ColoredBox(
            color: Colors.white,
            child: Scaffold(
              backgroundColor: Colors.white,
              body: _buildBikePaneBody(selectedBike),
            ),
          );
        }

        if (!showRightPane) {
          return _buildBikesList();
        }

        final selectedBike = _selectedBikeId != null
            ? _bikes.where((b) => b.id == _selectedBikeId).firstOrNull
            : null;

        return ColoredBox(
          color: Colors.white,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: _buildBikePaneBody(selectedBike),
          ),
        );
      },
    );
  }

  Widget _buildBikesList() {
    final filteredBikes = _getFilteredBikes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Inline toolbar ──
        _buildTabToolbar(
          searchController: _bikeSearchController,
          searchHint: 'Buscar por marca, modelo o serie…',
          sortKey: _bikeSortKey,
          sortLabels: _bikeSortLabels,
          onSortChanged: (v) => setState(() => _bikeSortKey = v),
          statusText: filteredBikes.length == _bikes.length
              ? '${_bikes.length} bicicletas'
              : '${filteredBikes.length} de ${_bikes.length}',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = _tableViewportWidth(constraints);
            final tableWidth = _bikeTableWidth(viewportWidth);

            return Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: SingleChildScrollView(
                controller: _headerScrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: tableWidth,
                  child: Row(
                    children: [
                      const SizedBox(width: 52),
                      SizedBox(
                        width: _bikeNameColumnWidth(tableWidth),
                        child: _buildSortableHeader(
                          'MARCA / MODELO',
                          'name',
                          _bikeSortCol,
                          _bikeSortAsc,
                          (col, asc) => setState(() {
                            _bikeSortCol = col;
                            _bikeSortAsc = asc;
                          }),
                          leftPad: 12,
                        ),
                      ),
                      _buildResizableHeader(
                        label: 'SERIE',
                        colKey: 'serial',
                        width: _bikeColSerial,
                        sortCol: _bikeSortCol,
                        sortAsc: _bikeSortAsc,
                        onSort: (col, asc) => setState(() {
                          _bikeSortCol = col;
                          _bikeSortAsc = asc;
                        }),
                        onResize: (d) => setState(() => _bikeColSerial =
                            (_bikeColSerial + d).clamp(60, 300)),
                      ),
                      _buildResizableHeader(
                        label: 'REGISTRADA',
                        colKey: 'registered',
                        width: _bikeColRegistered,
                        sortCol: _bikeSortCol,
                        sortAsc: _bikeSortAsc,
                        onSort: (col, asc) => setState(() {
                          _bikeSortCol = col;
                          _bikeSortAsc = asc;
                        }),
                        onResize: (d) => setState(() => _bikeColRegistered =
                            (_bikeColRegistered + d).clamp(60, 200)),
                      ),
                      _buildResizableHeader(
                        label: 'ÚLT. ENTREGA',
                        colKey: 'last_delivery',
                        width: _bikeColDelivery,
                        sortCol: _bikeSortCol,
                        sortAsc: _bikeSortAsc,
                        onSort: (col, asc) => setState(() {
                          _bikeSortCol = col;
                          _bikeSortAsc = asc;
                        }),
                        onResize: (d) => setState(() => _bikeColDelivery =
                            (_bikeColDelivery + d).clamp(60, 200)),
                      ),
                      _buildResizableHeader(
                        label: 'TRABAJOS',
                        colKey: 'jobs',
                        width: _bikeColJobs,
                        sortCol: _bikeSortCol,
                        sortAsc: _bikeSortAsc,
                        onSort: (col, asc) => setState(() {
                          _bikeSortCol = col;
                          _bikeSortAsc = asc;
                        }),
                        onResize: (d) => setState(() =>
                            _bikeColJobs = (_bikeColJobs + d).clamp(50, 160)),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: filteredBikes.isEmpty
              ? _buildEmptyState(
                  _bikes.isEmpty
                      ? 'Sin bicicletas registradas'
                      : 'Ninguna bicicleta coincide',
                  Icons.pedal_bike_outlined,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportWidth = _tableViewportWidth(constraints);
                    final tableWidth = _bikeTableWidth(viewportWidth);

                    return SingleChildScrollView(
                      controller: _bodyScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: tableWidth,
                        child: ListView.builder(
                          itemCount: filteredBikes.length,
                          itemBuilder: (_, i) => _buildBikeTableRow(
                              filteredBikes[i], i.isEven, tableWidth),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // JOBS TAB
  // ─────────────────────────────────────────────

  Widget _buildJobsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        final showRightPane =
            isDesktop && (_selectedJobId != null || _isEditingJob);

        if (!showRightPane) {
          return _buildJobsList();
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 1,
              child: _buildJobsList(),
            ),
            Container(
              width: 1,
              color: Colors.grey[300],
            ),
            Expanded(
              flex: 1,
              child: ColoredBox(
                color: Colors.white,
                child: MechanicJobFormPage(
                  key: ValueKey(_selectedJobId ?? 'new_job'),
                  jobId: _selectedJobId,
                  customerId: widget.customerId,
                  isEmbedded: true,
                  onSaved: () {
                    setState(() {
                      _isEditingJob = false;
                    });
                    _loadData(); // Refresh list
                  },
                  onCanceled: () {
                    setState(() {
                      _isEditingJob = false;
                      _selectedJobId = null;
                    });
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildJobsList() {
    final filteredJobs = _getFilteredJobs();
    final activeCount = _jobs
        .where((j) =>
            j.status != JobStatus.entregado && j.status != JobStatus.cancelado)
        .length;
    final completedCount =
        _jobs.where((j) => j.status == JobStatus.entregado).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar with filter chips ──
        _buildTabToolbar(
          searchController: _jobSearchController,
          searchHint: 'Buscar por número, técnico o nota…',
          sortKey: _jobSortKey,
          sortLabels: _jobSortLabels,
          onSortChanged: (v) => setState(() => _jobSortKey = v),
          statusText: filteredJobs.length == _jobs.length
              ? '${_jobs.length} trabajos'
              : '${filteredJobs.length} de ${_jobs.length}',
          trailing: Row(
            children: JobViewFilter.values.map((filter) {
              final selected = _jobViewFilter == filter;
              int? count;
              if (filter == JobViewFilter.active) count = activeCount;
              if (filter == JobViewFilter.completed) count = completedCount;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildFilterToggle(
                  _jobFilterLabel(filter),
                  selected,
                  () => setState(() => _jobViewFilter = filter),
                  count: (count != null && count > 0) ? count : null,
                ),
              );
            }).toList(),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = _tableViewportWidth(constraints);
            final tableWidth = _jobTableWidth(viewportWidth);

            return Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: SingleChildScrollView(
                controller: _headerScrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: tableWidth,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      _buildResizableHeader(
                        label: 'N° TRABAJO',
                        colKey: 'number',
                        width: _jobColNumber,
                        sortCol: _jobSortCol,
                        sortAsc: _jobSortAsc,
                        onSort: (col, asc) => setState(() {
                          _jobSortCol = col;
                          _jobSortAsc = asc;
                        }),
                        onResize: (d) => setState(() =>
                            _jobColNumber = (_jobColNumber + d).clamp(60, 200)),
                      ),
                      _buildResizableHeader(
                        label: 'BICICLETA',
                        colKey: 'bike',
                        width: _jobColBike,
                        sortCol: _jobSortCol,
                        sortAsc: _jobSortAsc,
                        onSort: (col, asc) => setState(() {
                          _jobSortCol = col;
                          _jobSortAsc = asc;
                        }),
                        onResize: (d) => setState(() =>
                            _jobColBike = (_jobColBike + d).clamp(60, 300)),
                      ),
                      SizedBox(
                        width: _jobRequestColumnWidth(tableWidth),
                        child: _buildSortableHeader(
                          'SOLICITUD',
                          'request',
                          _jobSortCol,
                          _jobSortAsc,
                          (col, asc) => setState(() {
                            _jobSortCol = col;
                            _jobSortAsc = asc;
                          }),
                          leftPad: 12,
                        ),
                      ),
                      _buildResizableHeader(
                        label: 'ESTADO',
                        colKey: 'status',
                        width: _jobColStatus,
                        sortCol: _jobSortCol,
                        sortAsc: _jobSortAsc,
                        onSort: (col, asc) => setState(() {
                          _jobSortCol = col;
                          _jobSortAsc = asc;
                        }),
                        onResize: (d) => setState(() =>
                            _jobColStatus = (_jobColStatus + d).clamp(60, 220)),
                      ),
                      _buildResizableHeader(
                        label: 'FECHA',
                        colKey: 'date',
                        width: _jobColDate,
                        sortCol: _jobSortCol,
                        sortAsc: _jobSortAsc,
                        onSort: (col, asc) => setState(() {
                          _jobSortCol = col;
                          _jobSortAsc = asc;
                        }),
                        onResize: (d) => setState(() =>
                            _jobColDate = (_jobColDate + d).clamp(60, 180)),
                      ),
                      _buildResizableHeader(
                        label: 'TOTAL',
                        colKey: 'total',
                        width: _jobColTotal,
                        sortCol: _jobSortCol,
                        sortAsc: _jobSortAsc,
                        onSort: (col, asc) => setState(() {
                          _jobSortCol = col;
                          _jobSortAsc = asc;
                        }),
                        onResize: (d) => setState(() =>
                            _jobColTotal = (_jobColTotal + d).clamp(50, 160)),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: filteredJobs.isEmpty
              ? _buildEmptyState(
                  _jobs.isEmpty
                      ? 'Sin trabajos registrados'
                      : 'Ningún trabajo coincide',
                  Icons.build_outlined,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportWidth = _tableViewportWidth(constraints);
                    final tableWidth = _jobTableWidth(viewportWidth);

                    return SingleChildScrollView(
                      controller: _bodyScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: tableWidth,
                        child: ListView.builder(
                          itemCount: filteredJobs.length,
                          itemBuilder: (_, i) => _buildJobTableRow(
                              filteredJobs[i], i.isEven, tableWidth),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // TIMELINE TAB
  // ─────────────────────────────────────────────

  Widget _buildTimelineTab() {
    final filteredTimeline = _getFilteredTimeline();
    const allTypes = TimelineEventType.values;
    final allSelected = _timelineTypeFilters.length == allTypes.length;
    final filterSummary = allSelected
        ? 'Todos los tipos'
        : '${_timelineTypeFilters.length}/${allTypes.length} tipos';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTabToolbar(
          searchController: _timelineSearchController,
          searchHint: 'Buscar evento, técnico o bicicleta…',
          sortKey: _timelineSortKey,
          sortLabels: _timelineSortLabels,
          onSortChanged: (v) => setState(() => _timelineSortKey = v),
          statusText: filteredTimeline.length == _timeline.length
              ? '${_timeline.length} eventos'
              : '${filteredTimeline.length} de ${_timeline.length}',
          trailing: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _showTimelineFilterSheet,
                icon: Icon(
                  allSelected ? Icons.filter_list_off : Icons.filter_list,
                  size: 16,
                ),
                label: Text(filterSummary),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
              if (!allSelected) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Restablecer filtros',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => setState(() {
                    _timelineTypeFilters = allTypes.toSet();
                    _timelineSearchController.clear();
                    _timelineSortKey = 'date_desc';
                  }),
                ),
              ],
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = _tableViewportWidth(constraints);
            final tableWidth = _timelineTableWidth(viewportWidth);

            return Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: SingleChildScrollView(
                controller: _headerScrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: tableWidth,
                  child: Row(
                    children: [
                      const SizedBox(width: 52),
                      SizedBox(
                        width: _timelineDescriptionColumnWidth(tableWidth),
                        child: _buildSortableHeader(
                          'DESCRIPCIÓN',
                          'desc',
                          _timelineSortCol,
                          _timelineSortAsc,
                          (col, asc) => setState(() {
                            _timelineSortCol = col;
                            _timelineSortAsc = asc;
                          }),
                          leftPad: 12,
                        ),
                      ),
                      _buildResizableHeader(
                        label: 'TRABAJO / BICI',
                        colKey: 'ref',
                        width: _tlColRef,
                        sortCol: _timelineSortCol,
                        sortAsc: _timelineSortAsc,
                        onSort: (col, asc) => setState(() {
                          _timelineSortCol = col;
                          _timelineSortAsc = asc;
                        }),
                        onResize: (d) => setState(
                            () => _tlColRef = (_tlColRef + d).clamp(80, 300)),
                      ),
                      _buildResizableHeader(
                        label: 'TÉCNICO',
                        colKey: 'tech',
                        width: _tlColTech,
                        sortCol: _timelineSortCol,
                        sortAsc: _timelineSortAsc,
                        onSort: (col, asc) => setState(() {
                          _timelineSortCol = col;
                          _timelineSortAsc = asc;
                        }),
                        onResize: (d) => setState(
                            () => _tlColTech = (_tlColTech + d).clamp(60, 250)),
                      ),
                      _buildResizableHeader(
                        label: 'FECHA',
                        colKey: 'date',
                        width: _tlColDate,
                        sortCol: _timelineSortCol,
                        sortAsc: _timelineSortAsc,
                        onSort: (col, asc) => setState(() {
                          _timelineSortCol = col;
                          _timelineSortAsc = asc;
                        }),
                        onResize: (d) => setState(
                            () => _tlColDate = (_tlColDate + d).clamp(80, 220)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: filteredTimeline.isEmpty
              ? _buildEmptyState(
                  _timeline.isEmpty
                      ? 'Sin eventos registrados'
                      : 'Ningún evento coincide',
                  Icons.history_outlined,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportWidth = _tableViewportWidth(constraints);
                    final tableWidth = _timelineTableWidth(viewportWidth);

                    return SingleChildScrollView(
                      controller: _bodyScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: tableWidth,
                        child: ListView.builder(
                          itemCount: filteredTimeline.length,
                          itemBuilder: (_, i) => _buildTimelineTableRow(
                              filteredTimeline[i], i.isEven, tableWidth),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInvoicesTab() {
    final filteredInvoices = _getFilteredInvoices();
    final pendingCount = _invoices
        .where((invoice) =>
            invoice.balance > 0.01 && invoice.status != InvoiceStatus.cancelled)
        .length;
    final paidCount = _invoices
        .where((invoice) => invoice.status == InvoiceStatus.paid)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTabToolbar(
          searchController: _invoiceSearchController,
          searchHint: 'Buscar por número, referencia o bici…',
          sortKey: _invoiceSortKey,
          sortLabels: _invoiceSortLabels,
          onSortChanged: (v) => setState(() => _invoiceSortKey = v),
          statusText: !_hasLoadedInvoices
              ? 'Cargando facturas…'
              : filteredInvoices.length == _invoices.length
                  ? '${_invoices.length} facturas'
                  : '${filteredInvoices.length} de ${_invoices.length}',
          trailing: _invoices.isEmpty
              ? null
              : Row(
                  children: [
                    _buildInvoiceSummaryChip(
                      'Pendientes',
                      pendingCount,
                      Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    _buildInvoiceSummaryChip(
                      'Pagadas',
                      paidCount,
                      Colors.green,
                    ),
                  ],
                ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = _tableViewportWidth(constraints);
            final tableWidth = _invoiceTableWidth(viewportWidth);

            return Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: SingleChildScrollView(
                controller: _headerScrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: tableWidth,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      _buildResizableHeader(
                        label: 'N° FACTURA',
                        colKey: 'number',
                        width: _invoiceColNumber,
                        sortCol: _invoiceSortCol,
                        sortAsc: _invoiceSortAsc,
                        onSort: (col, asc) => setState(() {
                          _invoiceSortCol = col;
                          _invoiceSortAsc = asc;
                        }),
                        onResize: (d) => setState(() => _invoiceColNumber =
                            (_invoiceColNumber + d).clamp(90, 220)),
                      ),
                      SizedBox(
                        width: _invoiceContextColumnWidth(tableWidth),
                        child: _buildSortableHeader(
                          'ORIGEN / BICI',
                          'context',
                          _invoiceSortCol,
                          _invoiceSortAsc,
                          (col, asc) => setState(() {
                            _invoiceSortCol = col;
                            _invoiceSortAsc = asc;
                          }),
                          leftPad: 12,
                        ),
                      ),
                      _buildResizableHeader(
                        label: 'FECHA',
                        colKey: 'date',
                        width: _invoiceColDate,
                        sortCol: _invoiceSortCol,
                        sortAsc: _invoiceSortAsc,
                        onSort: (col, asc) => setState(() {
                          _invoiceSortCol = col;
                          _invoiceSortAsc = asc;
                        }),
                        onResize: (d) => setState(() => _invoiceColDate =
                            (_invoiceColDate + d).clamp(80, 180)),
                      ),
                      _buildResizableHeader(
                        label: 'ESTADO',
                        colKey: 'status',
                        width: _invoiceColStatus,
                        sortCol: _invoiceSortCol,
                        sortAsc: _invoiceSortAsc,
                        onSort: (col, asc) => setState(() {
                          _invoiceSortCol = col;
                          _invoiceSortAsc = asc;
                        }),
                        onResize: (d) => setState(() => _invoiceColStatus =
                            (_invoiceColStatus + d).clamp(90, 200)),
                      ),
                      _buildResizableHeader(
                        label: 'TOTAL',
                        colKey: 'total',
                        width: _invoiceColTotal,
                        sortCol: _invoiceSortCol,
                        sortAsc: _invoiceSortAsc,
                        onSort: (col, asc) => setState(() {
                          _invoiceSortCol = col;
                          _invoiceSortAsc = asc;
                        }),
                        onResize: (d) => setState(() => _invoiceColTotal =
                            (_invoiceColTotal + d).clamp(80, 180)),
                      ),
                      _buildResizableHeader(
                        label: 'SALDO',
                        colKey: 'balance',
                        width: _invoiceColBalance,
                        sortCol: _invoiceSortCol,
                        sortAsc: _invoiceSortAsc,
                        onSort: (col, asc) => setState(() {
                          _invoiceSortCol = col;
                          _invoiceSortAsc = asc;
                        }),
                        onResize: (d) => setState(() => _invoiceColBalance =
                            (_invoiceColBalance + d).clamp(80, 180)),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: _isLoadingInvoices && !_hasLoadedInvoices
              ? const Center(
                  child: BrandedLoading(
                    size: 120,
                    message: 'Cargando facturas…',
                  ),
                )
              : _invoiceError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 48, color: Colors.red[300]),
                          const SizedBox(height: 12),
                          Text(
                            _invoiceError!,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => _loadInvoices(forceRefresh: true),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    )
                  : filteredInvoices.isEmpty
                      ? _buildEmptyState(
                          _invoices.isEmpty
                              ? 'Sin facturas registradas'
                              : 'Ninguna factura coincide',
                          Icons.receipt_long_outlined,
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final viewportWidth =
                                _tableViewportWidth(constraints);
                            final tableWidth =
                                _invoiceTableWidth(viewportWidth);

                            return SingleChildScrollView(
                              controller: _bodyScrollController,
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              child: SizedBox(
                                width: tableWidth,
                                child: ListView.builder(
                                  itemCount: filteredInvoices.length,
                                  itemBuilder: (_, i) => _buildInvoiceTableRow(
                                    filteredInvoices[i],
                                    i.isEven,
                                    tableWidth,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // CHATS TAB
  // ─────────────────────────────────────────────

  Widget _buildChatsTab() {
    if (_isLoadingChats) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_chatError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              _chatError!,
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _loadChats(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_chats.isEmpty) {
      return _buildEmptyState(
        'Sin conversaciones registradas',
        Icons.chat_bubble_outline,
      );
    }

    final theme = Theme.of(context);

    // Single conversation: just show the chat directly, no list panel
    if (_chats.length == 1) {
      return ChatWindow(
        key: ValueKey(_chats.first.id),
        conversation: _chats.first,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;

        if (isWide) {
          // Split: list on left, ChatWindow on right
          return Row(
            children: [
              SizedBox(
                width: 220,
                child: ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (_, i) =>
                      _buildChatListItem(_chats[i], isWide: true),
                ),
              ),
              VerticalDivider(width: 1, color: theme.dividerColor),
              Expanded(
                child: _selectedChat != null
                    ? ChatWindow(
                        key: ValueKey(_selectedChat!.id),
                        conversation: _selectedChat!,
                      )
                    : Center(
                        child: Text(
                          'Selecciona una conversación',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      ),
              ),
            ],
          );
        }

        // Narrow: show selected chat or list
        if (_selectedChat != null) {
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: theme.cardColor,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: () => setState(() => _selectedChat = null),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedChat!.title ?? 'Conversación',
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ChatWindow(
                  key: ValueKey(_selectedChat!.id),
                  conversation: _selectedChat!,
                ),
              ),
            ],
          );
        }

        return ListView.builder(
          itemCount: _chats.length,
          itemBuilder: (_, i) => _buildChatListItem(_chats[i], isWide: false),
        );
      },
    );
  }

  Widget _buildChatListItem(Conversation chat, {required bool isWide}) {
    final theme = Theme.of(context);
    final isSelected = isWide && _selectedChat?.id == chat.id;
    final hasUnread = chat.unreadCount > 0;
    final lastAt = chat.lastMessageAt ?? chat.updatedAt;

    final String subtitle = switch (chat.contextType) {
      'job' => 'Trabajo técnico',
      'invoice' => 'Factura',
      'customer' => 'Cliente',
      _ => chat.type == 'support' ? 'Soporte' : 'Interno',
    };

    return InkWell(
      onTap: () => setState(() => _selectedChat = chat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: isSelected ? theme.colorScheme.primary.withOpacity(0.08) : null,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (hasUnread)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        chat.unreadCount > 9 ? '9+' : '${chat.unreadCount}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.title ?? 'Conversación',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            Text(
              _formatChatDate(lastAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  String _formatChatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Ayer';
    } else if (diff.inDays < 7) {
      const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      return days[date.weekday - 1];
    } else {
      return '${date.day}/${date.month}';
    }
  }

  // ─────────────────────────────────────────────
  // SHARED TAB TOOLBAR
  // ─────────────────────────────────────────────

  Widget _buildTabToolbar({
    required TextEditingController searchController,
    required String searchHint,
    required String sortKey,
    required Map<String, String> sortLabels,
    required ValueChanged<String> onSortChanged,
    required String statusText,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Search
              SizedBox(
                width: 300,
                height: 36,
                child: TextField(
                  controller: searchController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: searchHint,
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    filled: true,
                    fillColor: theme.scaffoldBackgroundColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Sort
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border.all(color: Colors.grey[350]!),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: sortKey,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
                    isDense: true,
                    icon: Icon(Icons.unfold_more,
                        size: 16, color: Colors.grey[500]),
                    items: sortLabels.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value,
                                style: TextStyle(
                                    fontSize: 12.5, color: Colors.grey[800]))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onSortChanged(v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(statusText,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResizableHeader({
    required String label,
    required String colKey,
    required double width,
    required String? sortCol,
    required bool sortAsc,
    required void Function(String col, bool asc) onSort,
    required void Function(double delta) onResize,
  }) {
    final isActive = sortCol == colKey;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onSort(colKey, isActive ? !sortAsc : true),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.blue[700] : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isActive)
                    Icon(
                      sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 11,
                      color: Colors.blue[700],
                    ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (d) => onResize(d.delta.dx),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 8,
                height: double.infinity,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey[300],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortableHeader(
    String label,
    String colKey,
    String? sortCol,
    bool sortAsc,
    void Function(String col, bool asc) onSort, {
    double leftPad = 0,
  }) {
    final isActive = sortCol == colKey;
    return InkWell(
      onTap: () => onSort(colKey, isActive ? !sortAsc : true),
      child: Container(
        height: 36,
        padding: EdgeInsets.only(left: leftPad, right: 12),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.blue[700] : const Color(0xFF9E9E9E),
                letterSpacing: 0.5,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 11,
                color: Colors.blue[700],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToggle(
    String label,
    bool selected,
    VoidCallback onTap, {
    int? count,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.blue[50] : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? Colors.blue[300]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.blue[700] : Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.blue[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.blue[700] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildInvoiceSummaryChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceTableRow(Invoice invoice, bool even, double tableWidth) {
    final bikeName = _bikeIndex[invoice.bikeId]?.displayName;
    final contextTitle =
        bikeName ?? invoice.reference ?? _invoiceTypeLabel(invoice);
    final detailParts = [
      if (invoice.jobNumber != null && invoice.jobNumber!.isNotEmpty)
        invoice.jobNumber!,
      _invoiceTypeLabel(invoice),
    ];
    final amountFormatter =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Material(
      color: even ? Colors.white : Colors.grey[50],
      child: InkWell(
        onTap: invoice.id == null ? null : () => _openInvoice(invoice),
        child: SizedBox(
          height: 56,
          width: tableWidth,
          child: Row(
            children: [
              const SizedBox(width: 4),
              SizedBox(
                width: _invoiceColNumber,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    invoice.invoiceNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _invoiceContextColumnWidth(tableWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contextTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detailParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: _invoiceColDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    DateFormat('dd/MM/yy').format(invoice.date),
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
                  ),
                ),
              ),
              SizedBox(
                width: _invoiceColStatus,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildInvoiceStatusChip(invoice.status),
                  ),
                ),
              ),
              SizedBox(
                width: _invoiceColTotal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    amountFormatter.format(invoice.total),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              SizedBox(
                width: _invoiceColBalance,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    amountFormatter.format(invoice.balance),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: invoice.balance > 0.01
                          ? Colors.orange[800]
                          : Colors.green[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Icon(
                  Icons.open_in_new,
                  size: 16,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceStatusChip(InvoiceStatus status) {
    late final Color bgColor;
    late final Color textColor;

    switch (status) {
      case InvoiceStatus.draft:
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[700]!;
        break;
      case InvoiceStatus.sent:
        bgColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        break;
      case InvoiceStatus.confirmed:
        bgColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        break;
      case InvoiceStatus.paid:
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case InvoiceStatus.overdue:
        bgColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      case InvoiceStatus.cancelled:
        bgColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        _invoiceStatusLabel(status).toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  void _openInvoice(Invoice invoice) {
    final invoiceId = invoice.id;
    if (invoiceId == null || invoiceId.isEmpty) {
      return;
    }

    context.push('/sales/invoices/$invoiceId/edit').then((_) {
      if (!mounted) {
        return;
      }
      unawaited(_loadInvoices(forceRefresh: true));
    });
  }

  Color _getLoyaltyColor(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
        return Colors.brown;
      case LoyaltyTier.silver:
        return Colors.grey;
      case LoyaltyTier.gold:
        return Colors.amber;
      case LoyaltyTier.platinum:
        return Colors.purple;
    }
  }

  IconData _getLoyaltyIcon(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
      case LoyaltyTier.silver:
      case LoyaltyTier.gold:
        return Icons.workspace_premium;
      case LoyaltyTier.platinum:
        return Icons.diamond;
    }
  }

  String _getLoyaltyTierName(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
        return 'Bronce';
      case LoyaltyTier.silver:
        return 'Plata';
      case LoyaltyTier.gold:
        return 'Oro';
      case LoyaltyTier.platinum:
        return 'Platino';
    }
  }

  void _showAddPointsDialog() {
    final controller = TextEditingController();
    final customerService =
        Provider.of<CustomerService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Agregar Puntos'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Cantidad de puntos',
            hintText: '100',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final points = int.tryParse(controller.text);
              if (points == null || points <= 0) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa una cantidad válida de puntos'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                await customerService.addLoyaltyPoints(
                    widget.customerId, points);
                if (mounted) {
                  Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Puntos agregados exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  await _loadData();
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error agregando puntos: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showRedeemPointsDialog() {
    final controller = TextEditingController();
    final customerService =
        Provider.of<CustomerService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final availablePoints = _loyalty?.points ?? 0;

    if (availablePoints <= 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('El cliente no tiene puntos disponibles para canjear'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Canjear Puntos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Puntos disponibles: $availablePoints'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Puntos a canjear',
                hintText: '100',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final points = int.tryParse(controller.text);
              if (points == null || points <= 0) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa una cantidad válida de puntos'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (points > availablePoints) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('No hay puntos suficientes para canjear'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                await customerService.redeemLoyaltyPoints(
                    widget.customerId, points);
                if (mounted) {
                  Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Puntos canjeados exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  await _loadData();
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error canjeando puntos: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Canjear'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Widget _buildBikeTableRow(Bike bike, bool isEven, double tableWidth) {
    final jobsForBike = _totalJobsForBike(bike.id);
    final activeJobsCount = _activeJobsForBike(bike.id);
    final theme = Theme.of(context);
    final lastDelivered = _jobs
        .where((j) =>
            j.bikeId == bike.id &&
            j.status == JobStatus.entregado &&
            j.deliveredAt != null)
        .fold<DateTime?>(
            null,
            (prev, j) => prev == null || j.deliveredAt!.isAfter(prev)
                ? j.deliveredAt
                : prev);

    return InkWell(
      onTap: () {
        if (MediaQuery.of(context).size.width < 900) {
          _editBike(bike);
        } else {
          _openBikeRecordPane(bike);
        }
      },
      hoverColor: Colors.blue[50]?.withValues(alpha: 0.5),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            SizedBox(
              width: 36,
              child: Icon(
                Icons.pedal_bike,
                size: 18,
                color: theme.colorScheme.primary.withValues(alpha: 0.65),
              ),
            ),
            SizedBox(
              width: _bikeNameColumnWidth(tableWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      bike.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (bike.bikeType != null)
                      Text(
                        bike.bikeType!.displayName,
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _bikeColSerial,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  bike.serialNumber?.isNotEmpty == true
                      ? bike.serialNumber!
                      : '—',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: _bikeColRegistered,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  DateFormat('dd MMM yyyy', 'es').format(bike.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: _bikeColDelivery,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  lastDelivered != null
                      ? DateFormat('dd MMM yyyy', 'es').format(lastDelivered)
                      : '—',
                  style: TextStyle(
                    fontSize: 12,
                    color: lastDelivered != null
                        ? Colors.grey[700]
                        : Colors.grey[400],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: _bikeColJobs,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: activeJobsCount > 0
                            ? Colors.orange[50]
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        jobsForBike.toString(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: activeJobsCount > 0
                              ? Colors.orange[700]
                              : Colors.grey[600],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (bike.isUnderWarranty) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified_user,
                          size: 14, color: Colors.green[600]),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey[500]),
                padding: EdgeInsets.zero,
                splashRadius: 16,
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'jobs') {
                    setState(() {
                      _jobViewFilter = JobViewFilter.all;
                      _jobSearchController.text = bike.displayName;
                      _jobSearchTerm = bike.displayName;
                    });
                    _tabController.animateTo(1);
                  }
                  if (value == 'edit') {
                    if (MediaQuery.of(context).size.width < 900) {
                      _editBike(bike);
                    } else {
                      _openBikeEditorPane(bike);
                    }
                  }
                  if (value == 'delete') _confirmDeleteBike(bike);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'jobs',
                      child: Row(children: [
                        Icon(Icons.build_circle_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Ver Trabajos'),
                      ])),
                  const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Editar'),
                      ])),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 10),
                        Text('Eliminar', style: TextStyle(color: Colors.red)),
                      ])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineTableRow(
      MechanicJobTimeline event, bool isEven, double tableWidth) {
    final icon = _timelineIcon(event.eventType);
    final color = _timelineColor(event.eventType);
    final job = event.jobId.isNotEmpty ? _jobIndex[event.jobId] : null;
    final bike = job != null ? _bikeIndex[job.bikeId] : null;
    final defaultDescription = _getDefaultDescription(event.eventType);

    return InkWell(
      hoverColor: Colors.blue[50]?.withValues(alpha: 0.5),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: _timelineDescriptionColumnWidth(tableWidth),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      event.description ?? defaultDescription,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (event.oldValue != null || event.newValue != null)
                      Text(
                        '${event.oldValue ?? ''} → ${event.newValue ?? ''}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _tlColRef,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (job != null)
                      Text(
                        (job.jobNumber?.isNotEmpty ?? false)
                            ? 'Trabajo ${job.jobNumber}'
                            : '—',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (bike != null)
                      Text(
                        bike.displayName,
                        style:
                            TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (job == null && bike == null)
                      Text('—',
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[400])),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _tlColTech,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  event.createdByName ?? '—',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: _tlColDate,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(event.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTimelineFilterSheet() async {
    const allTypes = TimelineEventType.values;
    final selected = Set<TimelineEventType>.from(_timelineTypeFilters);

    final result = await showModalBottomSheet<Set<TimelineEventType>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: StatefulBuilder(
              builder: (context, setStateModal) {
                void toggle(TimelineEventType type) {
                  setStateModal(() {
                    if (selected.contains(type)) {
                      selected.remove(type);
                    } else {
                      selected.add(type);
                    }
                  });
                }

                void selectAll() {
                  setStateModal(() {
                    selected
                      ..clear()
                      ..addAll(allTypes);
                  });
                }

                void clearAll() {
                  setStateModal(selected.clear);
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtrar tipos de evento',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: selectAll,
                          child: const Text('Seleccionar todo'),
                        ),
                        TextButton(
                          onPressed: clearAll,
                          child: const Text('Limpiar'),
                        ),
                        const Spacer(),
                        Text(
                          selected.length == allTypes.length
                              ? 'Todos seleccionados'
                              : '${selected.length} de ${allTypes.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: allTypes.length,
                        itemBuilder: (context, index) {
                          final type = allTypes[index];
                          return CheckboxListTile(
                            value: selected.contains(type),
                            onChanged: (_) => toggle(type),
                            title: Text(_timelineEventLabel(type)),
                            secondary: Icon(
                              _timelineIcon(type),
                              color: _timelineColor(type),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context)
                              .pop(Set<TimelineEventType>.from(selected)),
                          child: const Text('Aplicar filtros'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _timelineTypeFilters = result.isEmpty ? <TimelineEventType>{} : result;
      });
    }
  }

  Widget _buildJobTableRow(MechanicJob job, bool isEven, double tableWidth) {
    final bike = _getBikeForJob(job);
    final requestSummary = job.isStandaloneQuotation
        ? job.subjectNotes?.trim()
        : job.clientRequest?.trim();
    final Color priorityColor;
    switch (job.priority) {
      case JobPriority.urgente:
        priorityColor = Colors.red;
        break;
      case JobPriority.alta:
        priorityColor = Colors.orange;
        break;
      case JobPriority.baja:
        priorityColor = Colors.grey;
        break;
      default:
        priorityColor = Colors.blue;
    }

    return InkWell(
      onTap: () {
        if (MediaQuery.of(context).size.width < 900) {
          context.push('/taller/pegas/${job.id}');
        } else {
          setState(() {
            _selectedJobId = job.id;
            _isEditingJob = true;
          });
        }
      },
      hoverColor: Colors.blue[50]?.withValues(alpha: 0.5),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 52,
              color: priorityColor.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: _jobColNumber - 16,
              child: Text(
                job.jobNumber ?? '—',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: _jobColBike,
              child: Text(
                bike.displayName,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: _jobRequestColumnWidth(tableWidth),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  requestSummary?.isNotEmpty == true ? requestSummary! : '—',
                  style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: _jobColStatus,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildStatusBadge(job),
              ),
            ),
            SizedBox(
              width: _jobColDate,
              child: Text(
                DateFormat('dd/MM/yy').format(job.arrivalDate),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
            SizedBox(
              width: _jobColTotal,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Tooltip(
                  message: job.isQuotationWorkflow
                      ? '${job.isServiceBudget ? 'Total presupuestado' : 'Total cotizado'}; todavía no es una cuenta por cobrar.'
                      : 'Total del trabajo',
                  child: Text(
                    NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                        .format(_getJobDisplayTotal(job)),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: job.isQuotationWorkflow
                          ? Colors.orange.shade800
                          : null,
                    ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey[500]),
                padding: EdgeInsets.zero,
                splashRadius: 16,
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'open') {
                    context.push('/taller/pegas/${job.id}');
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'open',
                      child: Row(children: [
                        Icon(Icons.open_in_new, size: 18),
                        SizedBox(width: 10),
                        Text('Ver Detalle'),
                      ])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Calculate display total respecting tax treatment
  /// For noTax jobs, show partsCost + laborCost (net amount)
  /// For taxIncluded jobs, show totalCost (gross amount)
  double _getJobDisplayTotal(MechanicJob job) {
    // Quotation workflows are deliberately no-tax before an invoice exists;
    // totalCost is nevertheless their authoritative discounted proposal total.
    if (job.isQuotationWorkflow) {
      return job.totalCost;
    }
    if (job.taxTreatment == TaxTreatment.noTax) {
      return job.partsCost + job.laborCost;
    }
    return job.totalCost;
  }

  Widget _buildStatusBadge(MechanicJob job) {
    if (job.isStandaloneQuotation) {
      final color = switch (job.effectiveQuotationStatus) {
        QuotationStatus.pending => Colors.orange,
        QuotationStatus.approved => Colors.green,
        QuotationStatus.rejected => Colors.red,
        QuotationStatus.expired => Colors.grey,
      };
      return _statusBadgeContainer(job.statusDisplayName, color);
    }

    final status = job.status;
    final color =
        job.customStatus?.colorValue ?? _operationalStatusColor(status);

    if (job.isServiceBudget) {
      final proposalColor = switch (job.effectiveQuotationStatus) {
        QuotationStatus.pending => Colors.orange,
        QuotationStatus.approved => Colors.green,
        QuotationStatus.rejected => Colors.red,
        QuotationStatus.expired => Colors.grey,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusBadgeContainer(job.statusDisplayName, color),
          const SizedBox(height: 3),
          Text(
            job.proposalStatusDisplayName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: proposalColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    return _statusBadgeContainer(status.displayName, color);
  }

  Color _operationalStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return Colors.grey;
      case JobStatus.diagnostico:
        return Colors.blue;
      case JobStatus.esperandoAprobacion:
        return Colors.amber;
      case JobStatus.esperandoRepuestos:
        return Colors.orange;
      case JobStatus.enCurso:
        return Colors.green;
      case JobStatus.finalizado:
        return Colors.teal;
      case JobStatus.entregado:
        return Colors.purple;
      case JobStatus.cancelado:
        return Colors.red;
    }
  }

  Widget _statusBadgeContainer(String label, Color color) {
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _getDefaultDescription(TimelineEventType eventType) {
    var description = 'Evento';

    switch (eventType) {
      case TimelineEventType.created:
        description = 'Trabajo creado';
        break;
      case TimelineEventType.statusChanged:
        description = 'Estado cambiado';
        break;
      case TimelineEventType.assigned:
        description = 'Técnico asignado';
        break;
      case TimelineEventType.diagnosisAdded:
        description = 'Diagnóstico agregado';
        break;
      case TimelineEventType.partsAdded:
        description = 'Repuestos agregados';
        break;
      case TimelineEventType.laborAdded:
        description = 'Mano de obra registrada';
        break;
      case TimelineEventType.photoAdded:
        description = 'Foto agregada';
        break;
      case TimelineEventType.noteAdded:
        description = 'Nota agregada';
        break;
      case TimelineEventType.approved:
        description = 'Trabajo aprobado';
        break;
      case TimelineEventType.invoiced:
        description = 'Factura generada';
        break;
      case TimelineEventType.paid:
        description = 'Pago recibido';
        break;
      case TimelineEventType.completed:
        description = 'Trabajo completado';
        break;
      case TimelineEventType.delivered:
        description = 'Bicicleta entregada';
        break;
    }

    return description;
  }

  // ============================================================
  // BIKE MANAGEMENT
  // ============================================================

  void _openNewBikePane() {
    setState(() {
      _selectedBikeId = null;
      _bikePanelMode = ClientBikePanelMode.creating;
      _selectedBikeRecordSnapshot = null;
      _isLoadingSelectedBikeRecordSnapshot = false;
    });
  }

  void _openBikeRecordPane(Bike bike) {
    setState(() {
      _selectedBikeId = bike.id;
      _bikePanelMode = ClientBikePanelMode.record;
    });
    unawaited(_loadSelectedBikeRecordSnapshot(bike.id));
  }

  void _openBikeEditorPane(Bike bike) {
    setState(() {
      _selectedBikeId = bike.id;
      _bikePanelMode = ClientBikePanelMode.editing;
    });
    unawaited(_loadSelectedBikeRecordSnapshot(bike.id));
  }

  void _closeBikePane() {
    setState(() {
      _selectedBikeId = null;
      _bikePanelMode = ClientBikePanelMode.none;
      _selectedBikeRecordSnapshot = null;
      _isLoadingSelectedBikeRecordSnapshot = false;
    });
  }

  Future<void> _loadSelectedBikeRecordSnapshot(String? bikeId) async {
    if (bikeId == null || bikeId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _selectedBikeRecordSnapshot = null;
        _isLoadingSelectedBikeRecordSnapshot = false;
        _bikeRecordLoadError = null;
      });
      return;
    }

    setState(() {
      _isLoadingSelectedBikeRecordSnapshot = true;
      _bikeRecordLoadError = null;
    });

    try {
      final bikeshopService = context.read<BikeshopService>();
      final snapshot = await bikeshopService.getBikeRecordSnapshot(bikeId);
      if (!mounted || _selectedBikeId != bikeId) return;

      setState(() {
        _selectedBikeRecordSnapshot = snapshot;
        _isLoadingSelectedBikeRecordSnapshot = false;
        if (snapshot == null) {
          _bikeRecordLoadError =
              'La bicicleta no fue encontrada en la base de datos.';
        }
      });
    } catch (e) {
      debugPrint('Error loading bike record snapshot: $e');
      if (mounted && _selectedBikeId == bikeId) {
        setState(() {
          _bikeRecordLoadError = 'Error de conexión: $e';
        });
      }
    } finally {
      if (mounted && _selectedBikeId == bikeId) {
        setState(() => _isLoadingSelectedBikeRecordSnapshot = false);
      }
    }
  }

  Widget _buildBikePaneBody(Bike? selectedBike) {
    if (_bikePanelMode == ClientBikePanelMode.none) {
      return const SizedBox.shrink();
    }

    final recordSnapshot = _selectedBikeRecordSnapshot;
    final isLoadingRecordSnapshot = _isLoadingSelectedBikeRecordSnapshot;
    final bikeForDisplay = recordSnapshot?.bike ?? selectedBike;

    if ((_bikePanelMode == ClientBikePanelMode.record ||
            _bikePanelMode == ClientBikePanelMode.editing) &&
        bikeForDisplay == null) {
      return const Center(child: Text('Bicicleta no encontrada'));
    }

    final isCreatingNew = _bikePanelMode == ClientBikePanelMode.creating;

    if (_bikePanelMode == ClientBikePanelMode.record) {
      if (isLoadingRecordSnapshot) {
        return const ColoredBox(
          color: Colors.white,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (recordSnapshot == null) {
        // Fallback or error state
        return Container(
          color: Colors.white,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  _bikeRecordLoadError ??
                      'No se pudo cargar la vista de la bicicleta.',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _openBikeEditorPane(bikeForDisplay!),
                  child: const Text('Abrir Editor Principal'),
                ),
              ],
            ),
          ),
        );
      }
      return BikeRecordPanel(
        snapshot: recordSnapshot,
        ownerName: _customer?.name ?? 'Desconocido',
        isLoading: false,
        onEdit: () {
          setState(() {
            _bikePanelMode = ClientBikePanelMode.editing;
          });
        },
        onNewJob: () {
          if (MediaQuery.of(context).size.width < 900) {
            context.push(
                '/taller/pegas/nueva?customer_id=${widget.customerId}&bike_id=${bikeForDisplay!.id}');
          } else {
            setState(() {
              _selectedJobId = null;
              _isEditingJob = true;
              _tabController.index = 1; // Jobs tab
            });
          }
        },
        onClose: _closeBikePane,
      );
    }

    return BikeFormDialog(
      key: ValueKey(
        '${_bikePanelMode.name}_${_selectedBikeId ?? 'new_bike'}_${isLoadingRecordSnapshot ? 'loading' : 'ready'}',
      ),
      customerId: widget.customerId,
      bike: bikeForDisplay,
      isEmbedded: true,
      onSaved: (savedBike) {
        if (isCreatingNew) {
          _closeBikePane();
        } else {
          _openBikeRecordPane(savedBike);
        }
        _loadData();
      },
      onCanceled: () {
        if (_bikePanelMode == ClientBikePanelMode.editing &&
            selectedBike != null) {
          _openBikeRecordPane(selectedBike);
          return;
        }
        _closeBikePane();
      },
    );
  }

  void _editBike(Bike bike) async {
    final result = await showDialog<Bike?>(
      context: context,
      builder: (context) => BikeFormDialog(
        customerId: widget.customerId,
        bike: bike,
      ),
    );

    if (result != null) {
      // Reload data after editing bike
      _loadData();
    }
  }

  Future<void> _confirmDeleteBike(Bike bike) async {
    final bikeshopService =
        Provider.of<BikeshopService>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Está seguro de eliminar esta bicicleta?'),
            const SizedBox(height: 16),
            Text(
              bike.displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (bike.serialNumber != null && bike.serialNumber!.isNotEmpty)
              Text('N° Serie: ${bike.serialNumber}'),
            if (bike.bikeType != null)
              Text('Tipo: ${bike.bikeType!.displayName}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && bike.id != null) {
      try {
        await bikeshopService.deleteBike(bike.id!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bicicleta eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );

          // Refresh the bike list automatically
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error eliminando bicicleta: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
