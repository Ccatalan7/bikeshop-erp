import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../accounting/models/account.dart';
import '../../accounting/models/expense_category.dart';
import '../../accounting/services/accounting_service.dart';
import '../../accounting/services/expense_service.dart';
import '../models/supplier_foundation.dart';
import '../services/supplier_credential_service.dart';
import '../services/supplier_relationship_service.dart';

@visibleForTesting
class SupplierCredentialCommandOutcomeUnknown implements Exception {
  const SupplierCredentialCommandOutcomeUnknown();
}

@visibleForTesting
Future<T> replayAmbiguousSupplierCredentialCommand<T>(
  Future<T> Function() operation,
) async {
  try {
    return await operation();
  } catch (error) {
    if (_isDefinitiveCredentialCommandFailure(error)) rethrow;
  }

  try {
    return await operation();
  } catch (error) {
    if (_isDefinitiveCredentialCommandFailure(error)) rethrow;
    throw const SupplierCredentialCommandOutcomeUnknown();
  }
}

bool _isDefinitiveCredentialCommandFailure(Object error) {
  return error is PostgrestException ||
      error is ArgumentError ||
      error is FormatException ||
      error is SupplierCredentialAccessDenied;
}

/// Testable boundary for the adaptive supplier writer.
///
/// The production implementation below delegates every mutation to the
/// foundation RPC services. It deliberately has no legacy supplier write
/// path: when the foundation is unavailable this page fails closed.
abstract interface class SupplierEditorDataSource {
  Future<SupplierProfile?> getProfile(String supplierId);

  Future<SupplierClassificationCatalog> getClassificationCatalog();

  Future<SupplierProfileCommandResult> saveProfile(
    SaveSupplierRelationshipProfileCommand command,
  );

  Future<SupplierEngagementCommandResult> createEngagement(
    CreateSupplierEngagementCommand command,
  );

  Future<SupplierEngagementCommandResult> appendEngagementVersion(
    AppendSupplierEngagementVersionCommand command,
  );

  Future<SupplierAccountingPolicyCommandResult> createAccountingPolicy(
    CreateSupplierAccountingPolicyCommand command,
  );

  Future<SupplierAccountingPolicyCommandResult> appendAccountingPolicyVersion(
    AppendSupplierAccountingPolicyVersionCommand command,
  );

  Future<SupplierCredentialStatus> getCredentialStatus(String supplierId);

  Future<SupplierCredentialUpsertResult> upsertCredential(
    SupplierCredentialInput input,
  );

  Future<SupplierCredentialDeleteResult> deleteCredential({
    required String supplierId,
    required SupplierCredentialKind kind,
    required String credentialKey,
    required String operationId,
    required DateTime expectedUpdatedAt,
  });

  Future<List<Account>> getAccounts();

  Future<List<ExpenseCategory>> getExpenseCategories();

  bool get canManageAccounting;

  bool get canManageCredentials;

  String get authorityFingerprint;

  Listenable? get authorityChanges;

  Stream<Object?>? get authAuthorityChanges;
}

class CanonicalSupplierEditorDataSource implements SupplierEditorDataSource {
  CanonicalSupplierEditorDataSource({
    required SupplierRelationshipService relationshipService,
    required SupplierCredentialService credentialService,
    required CurrentUserProfileService profileService,
    required AccountingService accountingService,
    required ExpenseService expenseService,
  })  : _relationshipService = relationshipService,
        _credentialService = credentialService,
        _profileService = profileService,
        _accountingService = accountingService,
        _expenseService = expenseService;

  final SupplierRelationshipService _relationshipService;
  final SupplierCredentialService _credentialService;
  final CurrentUserProfileService _profileService;
  final AccountingService _accountingService;
  final ExpenseService _expenseService;

  @override
  Future<SupplierProfile?> getProfile(String supplierId) =>
      _relationshipService.getSupplierProfile(supplierId);

  @override
  Future<SupplierClassificationCatalog> getClassificationCatalog() =>
      _relationshipService.getClassificationCatalog(activeOnly: false);

  @override
  Future<SupplierProfileCommandResult> saveProfile(
    SaveSupplierRelationshipProfileCommand command,
  ) =>
      _relationshipService.saveProfile(command);

  @override
  Future<SupplierEngagementCommandResult> createEngagement(
    CreateSupplierEngagementCommand command,
  ) =>
      _relationshipService.createEngagement(command);

  @override
  Future<SupplierEngagementCommandResult> appendEngagementVersion(
    AppendSupplierEngagementVersionCommand command,
  ) =>
      _relationshipService.appendEngagementVersion(command);

  @override
  Future<SupplierAccountingPolicyCommandResult> createAccountingPolicy(
    CreateSupplierAccountingPolicyCommand command,
  ) =>
      _relationshipService.createAccountingPolicy(command);

  @override
  Future<SupplierAccountingPolicyCommandResult> appendAccountingPolicyVersion(
    AppendSupplierAccountingPolicyVersionCommand command,
  ) =>
      _relationshipService.appendAccountingPolicyVersion(command);

  @override
  Future<SupplierCredentialStatus> getCredentialStatus(String supplierId) =>
      _credentialService.getStatus(supplierId: supplierId);

  @override
  Future<SupplierCredentialUpsertResult> upsertCredential(
    SupplierCredentialInput input,
  ) =>
      _credentialService.upsert(input);

  @override
  Future<SupplierCredentialDeleteResult> deleteCredential({
    required String supplierId,
    required SupplierCredentialKind kind,
    required String credentialKey,
    required String operationId,
    required DateTime expectedUpdatedAt,
  }) =>
      _credentialService.delete(
        supplierId: supplierId,
        kind: kind,
        credentialKey: credentialKey,
        operationId: operationId,
        expectedUpdatedAt: expectedUpdatedAt,
      );

  @override
  Future<List<Account>> getAccounts() => _accountingService.getAccounts();

  @override
  Future<List<ExpenseCategory>> getExpenseCategories() =>
      _expenseService.fetchCategories();

  @override
  bool get canManageAccounting =>
      _profileService.profile?.canAccessAccounting == true;

  @override
  bool get canManageCredentials =>
      _profileService.profile?.canManageSupplierCredentials == true;

  @override
  String get authorityFingerprint {
    final profile = _profileService.profile;
    return '${_credentialService.currentAuthUserId ?? ''}|'
        '${profile?.userId ?? ''}|${profile?.tenantId ?? ''}|'
        '${profile?.canAccessAccounting ?? false}|'
        '${profile?.canManageSupplierCredentials ?? false}';
  }

  @override
  Listenable get authorityChanges => _profileService;

  @override
  Stream<Object?>? get authAuthorityChanges =>
      _credentialService.authorityEvents;
}

/// Adaptive supplier editor frozen in Claude Design turn T18.2.
///
/// Identity and relationship roles form the minimum viable record. Contacts,
/// tax identity, relationships, accounting criteria, and credentials remain
/// independent optional dimensions and can be added as the counterparty
/// evolves.
class SupplierFormPage extends StatefulWidget {
  const SupplierFormPage({
    super.key,
    this.supplierId,
    this.dataSource,
    this.includeWorkspaceShell = true,
  });

  final String? supplierId;

  @visibleForTesting
  final SupplierEditorDataSource? dataSource;

  @visibleForTesting
  final bool includeWorkspaceShell;

  @override
  State<SupplierFormPage> createState() => _SupplierFormPageState();
}

class _SupplierFormPageState extends State<SupplierFormPage> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _legalName = TextEditingController();
  final _tradeName = TextEditingController();
  final _aliases = TextEditingController();
  final _taxIdentifier = TextEditingController();
  final _contactPerson = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _comuna = TextEditingController();
  final _city = TextEditingController();
  final _region = TextEditingController();
  final _notes = TextEditingController();

  SupplierEditorDataSource? _dataSource;
  Listenable? _authorityChanges;
  StreamSubscription<Object?>? _authAuthoritySubscription;
  String? _authorityFingerprint;
  SupplierProfile? _profile;
  SupplierClassificationCatalog? _catalog;
  SupplierCredentialStatus? _credentialStatus;
  List<Account> _accounts = const [];
  List<ExpenseCategory> _expenseCategories = const [];
  Object? _accountCatalogError;
  Object? _expenseCategoryCatalogError;
  bool _optionalCatalogsLoading = false;
  ExternalPartyKind _partyKind = ExternalPartyKind.organization;
  bool _isActive = true;
  bool _showOptionalDetails = false;
  final Set<String> _selectedRoleIds = {};
  final Set<String> _selectedCapabilityIds = {};
  final Set<String> _selectedTagIds = {};
  final Map<String, String> _roleAssignmentIds = {};
  final Map<String, String> _capabilityAssignmentIds = {};
  final Map<String, String> _tagAssignmentIds = {};
  bool _loading = true;
  bool _saving = false;
  Object? _loadError;
  String? _noticeTitle;
  String? _noticeBody;
  VbNoticeTone _noticeTone = VbNoticeTone.info;
  String? _noticeActionLabel;
  VoidCallback? _noticeAction;
  String? _profileOperationId;
  String? _profileOperationFingerprint;
  int _loadGeneration = 0;
  int _accountingCatalogGeneration = 0;
  int _credentialStatusGeneration = 0;

  SupplierEditorDataSource get _source => _dataSource!;
  bool get _editing => widget.supplierId != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dataSource != null) return;
    final source = widget.dataSource ??
        CanonicalSupplierEditorDataSource(
          relationshipService: context.read<SupplierRelationshipService>(),
          credentialService: SupplierCredentialService(
            profileService: context.read<CurrentUserProfileService>(),
          ),
          profileService: context.read<CurrentUserProfileService>(),
          accountingService: context.read<AccountingService>(),
          expenseService: context.read<ExpenseService>(),
        );
    _dataSource = source;
    _authorityFingerprint = source.authorityFingerprint;
    _authorityChanges = source.authorityChanges
      ?..addListener(_handleAuthorityChanged);
    _authAuthoritySubscription = source.authAuthorityChanges?.listen(
      (_) => _handleAuthAuthorityChanged(),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _authorityChanges?.removeListener(_handleAuthorityChanged);
    unawaited(_authAuthoritySubscription?.cancel());
    for (final controller in [
      _displayName,
      _legalName,
      _tradeName,
      _aliases,
      _taxIdentifier,
      _contactPerson,
      _email,
      _phone,
      _website,
      _address,
      _comuna,
      _city,
      _region,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleAuthorityChanged() {
    if (!mounted) return;
    final fingerprint = _source.authorityFingerprint;
    if (fingerprint == _authorityFingerprint) return;
    _authorityFingerprint = fingerprint;
    _invalidateAuthorityBoundEditorState();
    unawaited(_load());
  }

  void _handleAuthAuthorityChanged() {
    if (!mounted) return;
    final previousFingerprint = _authorityFingerprint;
    final nextFingerprint = _source.authorityFingerprint;
    // Auth can change before CurrentUserProfileService publishes its next
    // profile. Capability-scoped data disappears on that first signal and a
    // changed lease is not reloaded from the potentially stale profile.
    if (previousFingerprint != nextFingerprint) {
      _authorityFingerprint = nextFingerprint;
      _invalidateAuthorityBoundEditorState();
      unawaited(_load());
      return;
    }
    _clearAuthorityScopedData();
    final supplierId = widget.supplierId;
    if (supplierId != null && _profile != null) {
      // A token refresh retains the same authority lease. Revalidate its
      // capability-scoped reads without waiting for an unrelated profile
      // notification.
      if (_source.canManageAccounting) {
        unawaited(_loadAccountingCatalogs(supplierId));
      }
      if (_source.canManageCredentials) {
        unawaited(_loadCredentialStatus(supplierId));
      }
    }
  }

  void _invalidateAuthorityBoundEditorState() {
    _loadGeneration++;
    _accountingCatalogGeneration++;
    _credentialStatusGeneration++;
    for (final controller in [
      _displayName,
      _legalName,
      _tradeName,
      _aliases,
      _taxIdentifier,
      _contactPerson,
      _email,
      _phone,
      _website,
      _address,
      _comuna,
      _city,
      _region,
      _notes,
    ]) {
      controller.clear();
    }
    _selectedRoleIds.clear();
    _selectedCapabilityIds.clear();
    _selectedTagIds.clear();
    _roleAssignmentIds.clear();
    _capabilityAssignmentIds.clear();
    _tagAssignmentIds.clear();
    setState(() {
      _profile = null;
      _catalog = null;
      _credentialStatus = null;
      _accounts = const [];
      _expenseCategories = const [];
      _accountCatalogError = null;
      _expenseCategoryCatalogError = null;
      _optionalCatalogsLoading = false;
      _partyKind = ExternalPartyKind.organization;
      _isActive = true;
      _showOptionalDetails = false;
      _loading = true;
      _saving = false;
      _loadError = null;
      _noticeTitle = null;
      _noticeBody = null;
      _noticeActionLabel = null;
      _noticeAction = null;
      _profileOperationId = null;
      _profileOperationFingerprint = null;
    });
  }

  void _clearAuthorityScopedData() {
    _accountingCatalogGeneration++;
    _credentialStatusGeneration++;
    setState(() {
      _credentialStatus = null;
      _accounts = const [];
      _expenseCategories = const [];
      _accountCatalogError = null;
      _expenseCategoryCatalogError = null;
      _optionalCatalogsLoading = false;
    });
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final authorityFingerprint = _source.authorityFingerprint;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final supplierId = widget.supplierId;
      final values = await Future.wait<Object?>([
        _source.getClassificationCatalog(),
        if (supplierId != null) _source.getProfile(supplierId),
      ]);
      if (!mounted ||
          generation != _loadGeneration ||
          authorityFingerprint != _source.authorityFingerprint) {
        return;
      }
      final catalog = values[0] as SupplierClassificationCatalog;
      final profile = supplierId == null ? null : values[1] as SupplierProfile?;
      if (catalog.roles.isEmpty) {
        throw const SupplierFoundationUnavailable();
      }
      if (supplierId != null && profile == null) {
        throw StateError('No se encontró el proveedor solicitado.');
      }
      if (profile != null && !profile.classificationWritesAvailable) {
        throw const SupplierFoundationUnavailable();
      }
      _catalog = catalog;
      _profile = profile;
      if (profile != null) {
        _hydrate(profile, catalog);
        _showOptionalDetails = true;
      }
      setState(() => _loading = false);
      if (supplierId != null) {
        unawaited(_loadOptionalData(supplierId));
      }
    } catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          authorityFingerprint != _source.authorityFingerprint) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _loadOptionalData(String supplierId) async {
    if (_source.canManageAccounting) {
      await _loadAccountingCatalogs(supplierId);
    } else if (mounted) {
      _clearAccountingCatalogs();
    }
    if (_source.canManageCredentials) {
      await _loadCredentialStatus(supplierId);
    }
  }

  void _clearAccountingCatalogs() {
    _accountingCatalogGeneration++;
    setState(() {
      _accounts = const [];
      _expenseCategories = const [];
      _accountCatalogError = null;
      _expenseCategoryCatalogError = null;
      _optionalCatalogsLoading = false;
    });
  }

  Future<void> _loadAccountingCatalogs(String supplierId) async {
    if (!_source.canManageAccounting) return;
    final generation = ++_accountingCatalogGeneration;
    final authorityFingerprint = _source.authorityFingerprint;
    if (mounted) {
      setState(() {
        _optionalCatalogsLoading = true;
        _accountCatalogError = null;
        _expenseCategoryCatalogError = null;
      });
    }
    List<Account>? accounts;
    List<ExpenseCategory>? categories;
    Object? accountError;
    Object? categoryError;
    try {
      accounts = await _source.getAccounts();
    } catch (error) {
      accountError = error;
    }
    if (!_accountingCatalogLeaseIsCurrent(
      supplierId,
      generation,
      authorityFingerprint,
    )) {
      return;
    }
    try {
      categories = await _source.getExpenseCategories();
    } catch (error) {
      categoryError = error;
    }
    if (!_accountingCatalogLeaseIsCurrent(
      supplierId,
      generation,
      authorityFingerprint,
    )) {
      return;
    }
    setState(() {
      if (accounts != null) _accounts = accounts;
      if (categories != null) _expenseCategories = categories;
      _accountCatalogError = accountError;
      _expenseCategoryCatalogError = categoryError;
      _optionalCatalogsLoading = false;
    });
  }

  bool _accountingCatalogLeaseIsCurrent(
    String supplierId,
    int generation,
    String authorityFingerprint,
  ) =>
      mounted &&
      widget.supplierId == supplierId &&
      generation == _accountingCatalogGeneration &&
      _source.canManageAccounting &&
      authorityFingerprint == _source.authorityFingerprint;

  Future<void> _loadCredentialStatus(String supplierId) async {
    if (!_source.canManageCredentials) return;
    final generation = ++_credentialStatusGeneration;
    final authorityFingerprint = _source.authorityFingerprint;
    try {
      final status = await _source.getCredentialStatus(supplierId);
      if (!_credentialStatusLeaseIsCurrent(
        supplierId,
        generation,
        authorityFingerprint,
      )) {
        return;
      }
      setState(() => _credentialStatus = status);
    } on SupplierCredentialAccessDenied {
      if (!_credentialStatusLeaseIsCurrent(
        supplierId,
        generation,
        authorityFingerprint,
      )) {
        return;
      }
      setState(() => _credentialStatus = null);
    } catch (error) {
      if (!_credentialStatusLeaseIsCurrent(
        supplierId,
        generation,
        authorityFingerprint,
      )) {
        return;
      }
      _showNotice(
        'No se pudieron cargar los accesos',
        'Las demás secciones siguen disponibles. Puedes reintentar desde Accesos.',
        VbNoticeTone.warning,
      );
    }
  }

  bool _credentialStatusLeaseIsCurrent(
    String supplierId,
    int generation,
    String authorityFingerprint,
  ) =>
      mounted &&
      widget.supplierId == supplierId &&
      generation == _credentialStatusGeneration &&
      _source.canManageCredentials &&
      authorityFingerprint == _source.authorityFingerprint;

  void _hydrate(
    SupplierProfile profile,
    SupplierClassificationCatalog catalog,
  ) {
    final party = profile.party;
    final relationship = profile.relationship;
    _displayName.text = party.displayName;
    _legalName.text = party.legalName ?? '';
    _tradeName.text = party.tradeName ?? '';
    _aliases.text = party.aliases.join(', ');
    _taxIdentifier.text = party.identifiers
            .where((identifier) =>
                identifier.kind == 'tax_id' && identifier.validUntil == null)
            .map((identifier) => identifier.value)
            .firstOrNull ??
        '';
    _contactPerson.text = relationship.contactPerson ?? '';
    _email.text = relationship.email ?? '';
    _phone.text = relationship.phone ?? '';
    _website.text = relationship.website ?? '';
    _address.text = profile.legacyDetails.address ?? '';
    _comuna.text = profile.legacyDetails.comuna ?? '';
    _city.text = profile.legacyDetails.city ?? '';
    _region.text = profile.legacyDetails.region ?? '';
    _notes.text = relationship.notes ?? party.notes ?? '';
    _partyKind = party.kind;
    _isActive = relationship.isActive;

    void restoreAssignments<T>({
      required Iterable<T> active,
      required List<SupplierClassificationDefinition> definitions,
      required String? Function(T) definitionId,
      required String Function(T) code,
      required String Function(T) assignmentId,
      required Set<String> selected,
      required Map<String, String> assignmentIds,
    }) {
      for (final assignment in active) {
        final definition =
            definitions.cast<SupplierClassificationDefinition?>().firstWhere(
                  (item) =>
                      item?.id == definitionId(assignment) ||
                      item?.code == code(assignment),
                  orElse: () => null,
                );
        if (definition == null) continue;
        selected.add(definition.id);
        assignmentIds[definition.id] = assignmentId(assignment);
      }
    }

    restoreAssignments<SupplierRole>(
      active: relationship.roles,
      definitions: catalog.roles,
      definitionId: (item) => item.definitionId,
      code: (item) => item.code,
      assignmentId: (item) => item.id,
      selected: _selectedRoleIds,
      assignmentIds: _roleAssignmentIds,
    );
    restoreAssignments<SupplierCapability>(
      active: relationship.capabilities,
      definitions: catalog.capabilities,
      definitionId: (item) => item.definitionId,
      code: (item) => item.code,
      assignmentId: (item) => item.id,
      selected: _selectedCapabilityIds,
      assignmentIds: _capabilityAssignmentIds,
    );
    restoreAssignments<SupplierTag>(
      active: relationship.tags,
      definitions: catalog.tags,
      definitionId: (item) => item.definitionId,
      code: (item) => item.code,
      assignmentId: (item) => item.id,
      selected: _selectedTagIds,
      assignmentIds: _tagAssignmentIds,
    );
  }

  void _showNotice(
    String title,
    String body,
    VbNoticeTone tone, {
    String? actionLabel,
    VoidCallback? action,
  }) {
    if (!mounted) return;
    setState(() {
      _noticeTitle = title;
      _noticeBody = body;
      _noticeTone = tone;
      _noticeActionLabel = actionLabel;
      _noticeAction = action;
    });
  }

  void _close({bool saved = false}) {
    ReturnNavigation.close(
      context,
      fallbackRoute: '/purchases/suppliers',
      result: saved ? true : null,
    );
  }

  List<String> _aliasesValue() => _aliases.text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  String _profileFingerprint() => jsonEncode({
        'display_name': _displayName.text.trim(),
        'legal_name': _legalName.text.trim(),
        'trade_name': _tradeName.text.trim(),
        'aliases': _aliasesValue(),
        'tax_identifier': _taxIdentifier.text.trim(),
        'contact_person': _contactPerson.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'website': _website.text.trim(),
        'address': _address.text.trim(),
        'comuna': _comuna.text.trim(),
        'city': _city.text.trim(),
        'region': _region.text.trim(),
        'notes': _notes.text.trim(),
        'party_kind': _partyKind.name,
        'is_active': _isActive,
        'role_definition_ids': _selectedRoleIds.toList()..sort(),
        'capability_definition_ids': _selectedCapabilityIds.toList()..sort(),
        'tag_definition_ids': _selectedTagIds.toList()..sort(),
      });

  String _operationIdForProfile() {
    final fingerprint = _profileFingerprint();
    if (_profileOperationId == null ||
        _profileOperationFingerprint != fingerprint) {
      _profileOperationId = _uuid.v4();
      _profileOperationFingerprint = fingerprint;
    }
    return _profileOperationId!;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoleIds.isEmpty) {
      _showNotice(
        'Falta una forma de relación',
        'Selecciona al menos un rol. Un proveedor puede cumplir varios.',
        VbNoticeTone.warning,
      );
      return;
    }
    final catalog = _catalog;
    if (catalog == null || catalog.roles.isEmpty) {
      _showNotice(
        'La base de proveedores no está disponible',
        'No se guardó ningún dato. Reintenta cuando la fundación esté activa.',
        VbNoticeTone.danger,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = _profile;
      // New commands still carry the authority scope explicitly. The catalog
      // was read under the same authority lease and every definition was
      // scope-verified by SupplierRelationshipService.
      final tenantId =
          existing?.relationship.tenantId ?? catalog.roles.first.tenantId;
      final party = ExternalParty(
        id: existing?.party.id ?? '',
        tenantId: tenantId,
        kind: _partyKind,
        name: _displayName.text.trim(),
        legalName: _optional(_legalName),
        tradeName: _optional(_tradeName),
        aliases: _aliasesValue(),
        countryCode: existing?.party.countryCode ?? 'CL',
        notes: _optional(_notes),
        publicMetadata: existing?.party.publicMetadata ?? const {},
        isActive: _isActive,
      );
      final relationship = SupplierRelationship(
        id: existing?.relationship.id ?? '',
        tenantId: tenantId,
        externalPartyId: existing?.party.id ?? '',
        name: _displayName.text.trim(),
        status: _isActive
            ? SupplierRelationshipStatus.active
            : SupplierRelationshipStatus.inactive,
        email: _optional(_email),
        phone: _optional(_phone),
        contactPerson: _optional(_contactPerson),
        website: _optional(_website),
        notes: _optional(_notes),
        paymentTermsCode: existing?.relationship.paymentTermsCode,
      );
      List<SupplierClassificationSelection> selections(
        List<SupplierClassificationDefinition> definitions,
        Set<String> selected,
        Map<String, String> assignmentIds,
      ) =>
          definitions
              .where((definition) => selected.contains(definition.id))
              .map(
                (definition) => SupplierClassificationSelection(
                  definition: definition,
                  assignmentId: assignmentIds[definition.id],
                ),
              )
              .toList(growable: false);

      final result = await _source.saveProfile(
        SaveSupplierRelationshipProfileCommand(
          operationId: _operationIdForProfile(),
          supplierId: existing?.relationship.id,
          expectedUpdatedAt: existing?.relationship.updatedAt,
          party: party,
          relationship: relationship,
          roles: selections(
            catalog.roles,
            _selectedRoleIds,
            _roleAssignmentIds,
          ),
          capabilities: selections(
            catalog.capabilities,
            _selectedCapabilityIds,
            _capabilityAssignmentIds,
          ),
          tags: selections(
            catalog.tags,
            _selectedTagIds,
            _tagAssignmentIds,
          ),
          taxIdentifier: _optional(_taxIdentifier),
          taxCountryCode: _taxIdentifier.text.trim().isEmpty ? null : 'CL',
          address: _optional(_address),
          comuna: _optional(_comuna),
          city: _optional(_city),
          region: _optional(_region),
        ),
      );
      if (!mounted) return;
      _profileOperationId = null;
      _profileOperationFingerprint = null;
      _profile = result.profile;
      _close(saved: true);
    } on SupplierFoundationUnavailable {
      _showNotice(
        'La base de proveedores no está disponible',
        'No se guardó ni se creó un registro alternativo.',
        VbNoticeTone.danger,
      );
    } catch (error) {
      if (_isOptimisticConflict(error)) {
        _showNotice(
          'El proveedor cambió mientras lo editabas',
          'Conservamos tus datos. Revisa la ficha actual y vuelve a guardar; nunca se reescribe historia.',
          VbNoticeTone.warning,
        );
      } else {
        _showNotice(
          'No se pudo guardar el proveedor',
          'Conservamos tus datos. Revisa la conexión e inténtalo nuevamente.',
          VbNoticeTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = _buildSurface(context);
    if (!widget.includeWorkspaceShell) return surface;
    return MainLayout(
      title: 'Proveedores',
      onBackPressed: _close,
      child: surface,
    );
  }

  Widget _buildSurface(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: switch ((_loading, _loadError)) {
        (true, _) => const Center(
            child: BrandedLoading(
              size: 64,
              message: 'Preparando proveedor…',
            ),
          ),
        (false, final error?) => _EditorLoadFailure(
            foundationUnavailable: error is SupplierFoundationUnavailable,
            onRetry: _load,
            onClose: _close,
          ),
        _ => _buildEditor(context),
      },
    );
  }

  Widget _buildEditor(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    return Column(
      children: [
        _EditorHeader(
          editing: _editing,
          saving: _saving,
          onClose: _close,
          onSave: _save,
        ),
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 28,
                22,
                compact ? 16 : 28,
                40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_noticeTitle != null) ...[
                        VbNotice(
                          title: _noticeTitle!,
                          body: _noticeBody,
                          tone: _noticeTone,
                          action: _noticeAction == null
                              ? null
                              : TextButton(
                                  onPressed: _noticeAction,
                                  child: Text(_noticeActionLabel!),
                                ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _IdentitySection(
                        compact: compact,
                        displayName: _displayName,
                        legalName: _legalName,
                        tradeName: _tradeName,
                        aliases: _aliases,
                        taxIdentifier: _taxIdentifier,
                        partyKind: _partyKind,
                        isActive: _isActive,
                        onPartyKindChanged: (value) =>
                            setState(() => _partyKind = value),
                        onActiveChanged: (value) =>
                            setState(() => _isActive = value),
                      ),
                      const SizedBox(height: 16),
                      _ClassificationSection(
                        catalog: _catalog!,
                        selectedRoleIds: _selectedRoleIds,
                        selectedCapabilityIds: _selectedCapabilityIds,
                        selectedTagIds: _selectedTagIds,
                        onRoleChanged: (id, value) => setState(() => value
                            ? _selectedRoleIds.add(id)
                            : _selectedRoleIds.remove(id)),
                        onCapabilityChanged: (id, value) => setState(() => value
                            ? _selectedCapabilityIds.add(id)
                            : _selectedCapabilityIds.remove(id)),
                        onTagChanged: (id, value) => setState(() => value
                            ? _selectedTagIds.add(id)
                            : _selectedTagIds.remove(id)),
                      ),
                      const SizedBox(height: 16),
                      if (_showOptionalDetails || _profile != null)
                        _ContactSection(
                          compact: compact,
                          contactPerson: _contactPerson,
                          email: _email,
                          phone: _phone,
                          website: _website,
                          address: _address,
                          comuna: _comuna,
                          city: _city,
                          region: _region,
                          notes: _notes,
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey(
                              'supplier-show-optional-details',
                            ),
                            onPressed: () => setState(
                              () => _showOptionalDetails = true,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar contacto y ubicación'),
                          ),
                        ),
                      if (_profile != null) ...[
                        const SizedBox(height: 16),
                        _RelationshipSection(
                          engagements: _profile!.engagements,
                          onCreate: () => _editEngagement(),
                          onAppend: _editEngagement,
                        ),
                        const SizedBox(height: 16),
                        _AccountingSection(
                          policies: _profile!.accounting.policies,
                          accounts: _accounts,
                          canManageAccounting: _source.canManageAccounting,
                          catalogsLoading: _optionalCatalogsLoading,
                          accountCatalogUnavailable:
                              _accountCatalogError != null,
                          expenseCatalogUnavailable:
                              _expenseCategoryCatalogError != null,
                          onRetryCatalogs: () => _loadOptionalData(
                            _profile!.relationship.id,
                          ),
                          onCreate: () => _editAccountingPolicy(),
                          onAppend: _editAccountingPolicy,
                        ),
                        if (_source.canManageCredentials) ...[
                          const SizedBox(height: 16),
                          _CredentialsSection(
                            status: _credentialStatus,
                            onRetry: () => _loadCredentialStatus(
                              _profile!.relationship.id,
                            ),
                            onCreate: () => _editCredential(),
                            onRotate: _editCredential,
                            onDelete: _deleteCredential,
                          ),
                        ],
                      ] else ...[
                        const SizedBox(height: 16),
                        const VbNotice(
                          title: 'Primero crea la identidad',
                          body:
                              'Después podrás agregar relaciones versionadas, criterios contables y accesos. Ninguno es obligatorio para crear un proveedor.',
                          tone: VbNoticeTone.neutral,
                        ),
                      ],
                      const SizedBox(height: 22),
                      _EditorActions(
                        saving: _saving,
                        editing: _editing,
                        onCancel: _close,
                        onSave: _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editEngagement([
    SupplierEngagement? engagement,
    _EngagementDraft? retainedDraft,
  ]) async {
    final supplier = _profile;
    if (supplier == null) return;
    final effectiveBusinessDate = supplier.effectiveBusinessDate;
    if (effectiveBusinessDate == null) {
      _showNotice(
        'Falta la fecha operacional del negocio',
        'No se puede versionar una relación hasta que el servidor publique su fecha vigente.',
        VbNoticeTone.warning,
      );
      return;
    }
    final draft = await showDialog<_EngagementDraft>(
      context: context,
      builder: (_) => _EngagementDialog(
        existing: engagement,
        retainedDraft: retainedDraft,
        effectiveBusinessDate: effectiveBusinessDate,
      ),
    );
    if (draft == null) return;
    try {
      if (engagement == null) {
        await _source.createEngagement(
          CreateSupplierEngagementCommand(
            operationId: draft.operationId,
            supplierId: supplier.relationship.id,
            engagement: SupplierEngagementShellInput(
              kind: draft.kind,
              code: 'rel-${draft.operationId.substring(0, 8)}',
              name: draft.name,
              status: SupplierEngagementStatus.active,
            ),
            initialVersion: draft.version,
          ),
        );
      } else {
        await _source.appendEngagementVersion(
          AppendSupplierEngagementVersionCommand(
            operationId: draft.operationId,
            engagementId: engagement.id,
            version: draft.version,
          ),
        );
      }
      await _reloadProfileAfterChildWrite('Relación guardada');
    } catch (error) {
      final optimisticConflict = _isOptimisticConflict(error);
      final effectiveDateConflict = _isEffectiveDateConflict(error);
      _showNotice(
        optimisticConflict
            ? 'La relación cambió mientras la editabas'
            : effectiveDateConflict
                ? 'La fecha de vigencia ya no es válida'
                : 'No se pudo guardar la relación',
        optimisticConflict
            ? 'No se modificó la versión vigente. Conservamos tu propuesta para revisarla sobre la versión actual.'
            : effectiveDateConflict
                ? 'El servidor requiere una fecha posterior a la última versión. Conservamos tu propuesta para elegir otra fecha.'
                : 'Conservamos tu propuesta. Revisa la conexión e inténtalo nuevamente.',
        optimisticConflict || effectiveDateConflict
            ? VbNoticeTone.warning
            : VbNoticeTone.danger,
        actionLabel: 'Reabrir propuesta',
        action: () => _editEngagement(engagement, draft),
      );
    }
  }

  Future<void> _editAccountingPolicy(
      [SupplierAccountingPolicySummary? policy,
      _AccountingDraft? retainedDraft]) async {
    if (!_source.canManageAccounting) {
      _showNotice(
        'No tienes acceso para cambiar criterios contables',
        'La ficha y sus políticas existentes permanecen disponibles en modo lectura.',
        VbNoticeTone.warning,
      );
      return;
    }
    final supplier = _profile;
    final natures = _catalog?.operationalNatures ?? const [];
    if (supplier == null || natures.isEmpty) {
      _showNotice(
        'Falta el catálogo contable',
        'No se puede crear un criterio hasta que existan naturalezas operacionales publicadas.',
        VbNoticeTone.warning,
      );
      return;
    }
    final effectiveBusinessDate = supplier.effectiveBusinessDate;
    if (effectiveBusinessDate == null) {
      _showNotice(
        'Falta la fecha operacional del negocio',
        'No se puede versionar un criterio hasta que el servidor publique su fecha vigente.',
        VbNoticeTone.warning,
      );
      return;
    }
    final latestPolicyVersion = policy?.latestVersion;
    final latestRules = latestPolicyVersion == null
        ? const <SupplierAccountingRuleSummary>[]
        : supplier.accounting.rules
            .where(
              (rule) => rule.policyVersionId == latestPolicyVersion.id,
            )
            .toList(growable: false);
    final draft = await showDialog<_AccountingDraft>(
      context: context,
      builder: (_) => _AccountingDialog(
        existing: policy,
        retainedDraft: retainedDraft,
        engagements: supplier.engagements,
        existingRules: latestRules,
        effectiveBusinessDate: effectiveBusinessDate,
        natures: natures,
        accounts: _accounts,
        categories: _expenseCategories,
        accountCatalogUnavailable: _accountCatalogError != null,
        expenseCatalogUnavailable: _expenseCategoryCatalogError != null,
      ),
    );
    if (draft == null) return;
    try {
      if (policy == null) {
        await _source.createAccountingPolicy(
          CreateSupplierAccountingPolicyCommand(
            operationId: draft.operationId,
            supplierId: supplier.relationship.id,
            policy: SupplierAccountingPolicyShellInput(
              code: 'criteria-${draft.operationId.substring(0, 8)}',
              name: draft.name,
              status: SupplierAccountingPolicyStatus.active,
              engagementId: draft.engagementId,
            ),
            initialVersion: draft.version,
            rules: draft.rules,
          ),
        );
      } else {
        await _source.appendAccountingPolicyVersion(
          AppendSupplierAccountingPolicyVersionCommand(
            operationId: draft.operationId,
            policyId: policy.id,
            version: draft.version,
            rules: draft.rules,
          ),
        );
      }
      await _reloadProfileAfterChildWrite('Criterio contable guardado');
    } catch (error) {
      final optimisticConflict = _isOptimisticConflict(error);
      final effectiveDateConflict = _isEffectiveDateConflict(error);
      _showNotice(
        optimisticConflict
            ? 'El criterio cambió mientras lo editabas'
            : effectiveDateConflict
                ? 'La fecha de vigencia ya no es válida'
                : 'No se pudo guardar el criterio',
        optimisticConflict
            ? 'La historia no se reescribió. Conservamos esta propuesta para revisarla sobre la versión actual.'
            : effectiveDateConflict
                ? 'El servidor requiere una fecha posterior a la última versión. Conservamos tu propuesta para elegir otra fecha.'
                : 'Conservamos esta propuesta. Revisa la conexión e inténtalo nuevamente.',
        optimisticConflict || effectiveDateConflict
            ? VbNoticeTone.warning
            : VbNoticeTone.danger,
        actionLabel: 'Reabrir propuesta',
        action: () => _editAccountingPolicy(policy, draft),
      );
    }
  }

  Future<void> _editCredential([SupplierCredentialMetadata? existing]) async {
    final profile = _profile;
    if (profile == null || !_source.canManageCredentials) return;
    final draft = await showDialog<_CredentialDraft>(
      context: context,
      builder: (_) => _CredentialDialog(
        existing: existing,
        engagements: profile.engagements,
      ),
    );
    if (draft == null) return;
    final input = SupplierCredentialInput(
      operationId: draft.operationId,
      supplierId: profile.relationship.id,
      kind: draft.kind,
      credentialKey: draft.credentialKey,
      secret: draft.secret,
      expectedUpdatedAt: existing?.updatedAt,
      engagementId: draft.engagementId,
      originUrl: draft.origin,
      label: draft.label,
      username: draft.username,
      clearEngagement:
          existing?.engagementId != null && draft.engagementId == null,
      clearOrigin: existing?.originUrl != null && draft.origin == null,
    );
    try {
      await replayAmbiguousSupplierCredentialCommand(
        () => _source.upsertCredential(input),
      );
      await _loadCredentialStatus(profile.relationship.id);
      _showNotice(
        existing == null
            ? 'Acceso agregado'
            : existing.secretAvailable
                ? 'Acceso rotado'
                : 'Acceso completado',
        'La ficha conserva sólo metadatos; el secreto quedó en el Vault.',
        VbNoticeTone.success,
      );
    } on SupplierCredentialCommandOutcomeUnknown {
      await _loadCredentialStatus(profile.relationship.id);
      _showNotice(
        'Resultado del acceso no confirmado',
        'La operación pudo haberse aplicado y se reintentó con la misma clave de operación. Revisa el inventario actualizado antes de volver a ingresar el secreto.',
        VbNoticeTone.warning,
      );
    } catch (error) {
      _showNotice(
        _isOptimisticConflict(error)
            ? 'El acceso cambió mientras lo editabas'
            : 'El acceso fue rechazado',
        _isOptimisticConflict(error)
            ? 'El secreto fue descartado. Actualiza los metadatos antes de volver a escribirlo.'
            : 'El servidor rechazó la operación. Revisa el origen HTTPS exacto y los datos ingresados.',
        VbNoticeTone.warning,
      );
    }
  }

  Future<void> _deleteCredential(SupplierCredentialMetadata metadata) async {
    final profile = _profile;
    if (profile == null || metadata.updatedAt == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar acceso'),
        content: Text(
          'Se eliminará “${metadata.label ?? metadata.credentialKey}”. Esta acción no revela el secreto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final operationId = _uuid.v4();
    try {
      await replayAmbiguousSupplierCredentialCommand(
        () => _source.deleteCredential(
          supplierId: profile.relationship.id,
          kind: metadata.kind,
          credentialKey: metadata.credentialKey,
          operationId: operationId,
          expectedUpdatedAt: metadata.updatedAt!,
        ),
      );
      await _loadCredentialStatus(profile.relationship.id);
      _showNotice(
        'Acceso eliminado',
        'El inventario de accesos ya refleja el cambio.',
        VbNoticeTone.success,
      );
    } on SupplierCredentialCommandOutcomeUnknown {
      await _loadCredentialStatus(profile.relationship.id);
      _showNotice(
        'Resultado de eliminación no confirmado',
        'La operación se reintentó con la misma clave. Revisa el inventario actualizado antes de intentarlo otra vez.',
        VbNoticeTone.warning,
      );
    } catch (error) {
      _showNotice(
        _isOptimisticConflict(error)
            ? 'El acceso cambió antes de eliminarlo'
            : 'No se pudo eliminar el acceso',
        _isOptimisticConflict(error)
            ? 'Actualiza la sección y revisa la versión vigente.'
            : 'Revisa la conexión e inténtalo nuevamente.',
        _isOptimisticConflict(error)
            ? VbNoticeTone.warning
            : VbNoticeTone.danger,
      );
    }
  }

  Future<void> _reloadProfileAfterChildWrite(String title) async {
    final supplierId = widget.supplierId;
    if (supplierId == null) return;
    final profile = await _source.getProfile(supplierId);
    if (!mounted || profile == null) return;
    setState(() => _profile = profile);
    _showNotice(
      title,
      'Se agregó una versión nueva; la historia anterior permanece intacta.',
      VbNoticeTone.success,
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.editing,
    required this.saving,
    required this.onClose,
    required this.onSave,
  });

  final bool editing;
  final bool saving;
  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 900;
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: compact ? 16 : 28, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (!compact)
            IconButton(
              onPressed: onClose,
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing ? 'Editar proveedor' : 'Nuevo proveedor',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Identidad primero; agrega sólo las dimensiones que correspondan.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (!compact)
            FilledButton.icon(
              key: const ValueKey('supplier-save-header'),
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(editing ? 'Guardar cambios' : 'Crear proveedor'),
            ),
        ],
      ),
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.description,
    required this.child,
    this.trailing,
  });

  final String title;
  final String description;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final heading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
                if (trailing != null && constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: trailing!),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing!,
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({
    required this.compact,
    required this.displayName,
    required this.legalName,
    required this.tradeName,
    required this.aliases,
    required this.taxIdentifier,
    required this.partyKind,
    required this.isActive,
    required this.onPartyKindChanged,
    required this.onActiveChanged,
  });

  final bool compact;
  final TextEditingController displayName;
  final TextEditingController legalName;
  final TextEditingController tradeName;
  final TextEditingController aliases;
  final TextEditingController taxIdentifier;
  final ExternalPartyKind partyKind;
  final bool isActive;
  final ValueChanged<ExternalPartyKind> onPartyKindChanged;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final kind = DropdownButtonFormField<ExternalPartyKind>(
      key: const ValueKey('supplier-party-kind'),
      initialValue: partyKind,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Tipo de contraparte'),
      items: const [
        DropdownMenuItem(
            value: ExternalPartyKind.organization, child: Text('Organización')),
        DropdownMenuItem(
            value: ExternalPartyKind.person, child: Text('Persona')),
        DropdownMenuItem(
            value: ExternalPartyKind.publicAuthority,
            child: Text('Organismo público')),
        DropdownMenuItem(value: ExternalPartyKind.other, child: Text('Otro')),
      ],
      onChanged: (value) {
        if (value != null) onPartyKindChanged(value);
      },
    );
    return _EditorSection(
      title: 'Identidad',
      description:
          'Sólo el nombre, el tipo de contraparte y un rol son obligatorios.',
      child: Column(
        children: [
          _field(displayName, 'Nombre visible',
              required: true, key: const ValueKey('supplier-display-name')),
          const SizedBox(height: 12),
          _responsivePair(
              compact,
              kind,
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Proveedor activo'),
                subtitle:
                    const Text('Puede desactivarse sin borrar su historia.'),
                value: isActive,
                onChanged: onActiveChanged,
              )),
          const SizedBox(height: 12),
          _responsivePair(compact, _field(legalName, 'Razón social (opcional)'),
              _field(tradeName, 'Nombre comercial (opcional)')),
          const SizedBox(height: 12),
          _responsivePair(compact, _field(aliases, 'Alias, separados por coma'),
              _field(taxIdentifier, 'RUT u otro identificador fiscal')),
        ],
      ),
    );
  }
}

class _ClassificationSection extends StatelessWidget {
  const _ClassificationSection({
    required this.catalog,
    required this.selectedRoleIds,
    required this.selectedCapabilityIds,
    required this.selectedTagIds,
    required this.onRoleChanged,
    required this.onCapabilityChanged,
    required this.onTagChanged,
  });

  final SupplierClassificationCatalog catalog;
  final Set<String> selectedRoleIds;
  final Set<String> selectedCapabilityIds;
  final Set<String> selectedTagIds;
  final void Function(String, bool) onRoleChanged;
  final void Function(String, bool) onCapabilityChanged;
  final void Function(String, bool) onTagChanged;

  bool _allowed(SupplierClassificationDefinition definition) {
    final code = definition.code.toLowerCase();
    return code != 'free_service' && code != 'free-service' && code != 'free';
  }

  @override
  Widget build(BuildContext context) {
    return _EditorSection(
      title: 'Clasificación',
      description:
          'Son dimensiones independientes. Seleccionar una no borra ni deduce las otras.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ClassificationGroup(
            title: 'Roles',
            help: 'Cómo se relaciona con el taller. Elige al menos uno.',
            definitions: catalog.roles.where(_allowed).toList(),
            selectedIds: selectedRoleIds,
            onChanged: onRoleChanged,
          ),
          if (catalog.capabilities.where(_allowed).isNotEmpty) ...[
            const SizedBox(height: 18),
            _ClassificationGroup(
              title: 'Capacidades',
              help: 'Qué puede proveer o habilitar.',
              definitions: catalog.capabilities.where(_allowed).toList(),
              selectedIds: selectedCapabilityIds,
              onChanged: onCapabilityChanged,
            ),
          ],
          if (catalog.tags.where(_allowed).isNotEmpty) ...[
            const SizedBox(height: 18),
            _ClassificationGroup(
              title: 'Etiquetas internas',
              help:
                  'Contexto operativo del negocio; no reemplaza el criterio contable.',
              definitions: catalog.tags.where(_allowed).toList(),
              selectedIds: selectedTagIds,
              onChanged: onTagChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _ClassificationGroup extends StatelessWidget {
  const _ClassificationGroup(
      {required this.title,
      required this.help,
      required this.definitions,
      required this.selectedIds,
      required this.onChanged});
  final String title;
  final String help;
  final List<SupplierClassificationDefinition> definitions;
  final Set<String> selectedIds;
  final void Function(String, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(help,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              for (var index = 0; index < definitions.length; index++) ...[
                _ClassificationRow(
                  definition: definitions[index],
                  selected: selectedIds.contains(definitions[index].id),
                  onChanged: (value) => onChanged(definitions[index].id, value),
                ),
                if (index < definitions.length - 1)
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ClassificationRow extends StatelessWidget {
  const _ClassificationRow(
      {required this.definition,
      required this.selected,
      required this.onChanged});
  final SupplierClassificationDefinition definition;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = definition.isActive || selected;
    return Semantics(
      label: definition.label,
      checked: selected,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? () => onChanged(!selected) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Checkbox(
                    value: selected,
                    onChanged:
                        enabled ? (value) => onChanged(value ?? false) : null),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(definition.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        if (definition.description?.trim().isNotEmpty == true)
                          Text(definition.description!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                      ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactSection extends StatelessWidget {
  const _ContactSection(
      {required this.compact,
      required this.contactPerson,
      required this.email,
      required this.phone,
      required this.website,
      required this.address,
      required this.comuna,
      required this.city,
      required this.region,
      required this.notes});
  final bool compact;
  final TextEditingController contactPerson;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController website;
  final TextEditingController address;
  final TextEditingController comuna;
  final TextEditingController city;
  final TextEditingController region;
  final TextEditingController notes;

  @override
  Widget build(BuildContext context) => _EditorSection(
        title: 'Contacto y ubicación',
        description:
            'Información opcional de la relación; no condiciona la creación.',
        child: Column(children: [
          _responsivePair(compact, _field(contactPerson, 'Persona de contacto'),
              _field(email, 'Email', keyboardType: TextInputType.emailAddress)),
          const SizedBox(height: 12),
          _responsivePair(
              compact,
              _field(phone, 'Teléfono', keyboardType: TextInputType.phone),
              _field(website, 'Sitio web')),
          const SizedBox(height: 12),
          _field(address, 'Dirección'),
          const SizedBox(height: 12),
          _responsivePair(
              compact, _field(comuna, 'Comuna'), _field(city, 'Ciudad')),
          const SizedBox(height: 12),
          _field(region, 'Región'),
          const SizedBox(height: 12),
          TextFormField(
              controller: notes,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Notas internas')),
        ]),
      );
}

class _RelationshipSection extends StatelessWidget {
  const _RelationshipSection(
      {required this.engagements,
      required this.onCreate,
      required this.onAppend});
  final List<SupplierEngagement> engagements;
  final VoidCallback onCreate;
  final ValueChanged<SupplierEngagement> onAppend;

  @override
  Widget build(BuildContext context) => _EditorSection(
        title: 'Relaciones',
        description:
            'Contratos, planes y cuentas de servicio se guardan por versiones.',
        trailing: TextButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Nueva relación')),
        child: engagements.isEmpty
            ? const _EmptyLine(
                text:
                    'Todavía no hay relaciones. Este proveedor puede existir sólo como recurso.')
            : Column(children: [
                for (final item in engagements)
                  _VersionRow(
                      title: item.name,
                      subtitle: _engagementSummary(item),
                      actionLabel: 'Agregar versión',
                      onPressed: () => onAppend(item))
              ]),
      );

  static String _engagementSummary(SupplierEngagement item) {
    final version = item.currentVersion;
    final billing = switch (version?.billingCadence) {
      'free' => 'Sin costo',
      'monthly' => 'Mensual',
      'bimonthly' => 'Bimestral',
      'quarterly' => 'Trimestral',
      'semiannual' => 'Semestral',
      'annual' => 'Anual',
      'irregular' => 'Irregular',
      _ => 'Sin ciclo definido',
    };
    return version == null
        ? 'Sin versión vigente'
        : 'v${version.version} · $billing';
  }
}

class _AccountingSection extends StatelessWidget {
  const _AccountingSection(
      {required this.policies,
      required this.accounts,
      required this.canManageAccounting,
      required this.catalogsLoading,
      required this.accountCatalogUnavailable,
      required this.expenseCatalogUnavailable,
      required this.onRetryCatalogs,
      required this.onCreate,
      required this.onAppend});
  final List<SupplierAccountingPolicySummary> policies;
  final List<Account> accounts;
  final bool canManageAccounting;
  final bool catalogsLoading;
  final bool accountCatalogUnavailable;
  final bool expenseCatalogUnavailable;
  final VoidCallback onRetryCatalogs;
  final VoidCallback onCreate;
  final ValueChanged<SupplierAccountingPolicySummary> onAppend;

  @override
  Widget build(BuildContext context) => _EditorSection(
        title: 'Criterios contables',
        description:
            'Configuran tratamientos versionados por contexto; hoy no clasifican ni contabilizan por sí solos.',
        trailing: canManageAccounting
            ? TextButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Nuevo criterio'),
              )
            : null,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (canManageAccounting && catalogsLoading)
            const LinearProgressIndicator()
          else if (canManageAccounting &&
              (accountCatalogUnavailable || expenseCatalogUnavailable)) ...[
            VbNotice(
              title: 'Catálogos contables no disponibles',
              body: accountCatalogUnavailable && expenseCatalogUnavailable
                  ? 'No pudimos leer cuentas ni categorías. Esos selectores quedan deshabilitados; no se interpretan como listas vacías.'
                  : accountCatalogUnavailable
                      ? 'No pudimos leer las cuentas. Sus selectores quedan deshabilitados; no se interpreta como una lista vacía.'
                      : 'No pudimos leer las categorías. Su selector queda deshabilitado; no se interpreta como una lista vacía.',
              tone: VbNoticeTone.warning,
              action: TextButton(
                onPressed: onRetryCatalogs,
                child: const Text('Reintentar'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (policies.isEmpty)
            const _EmptyLine(
                text:
                    'Sin criterios. La clasificación del proveedor no determina por sí sola un asiento.')
          else
            for (final item in policies)
              _VersionRow(
                  title: item.name,
                  subtitle: _policySummary(item, accounts),
                  actionLabel: canManageAccounting ? 'Agregar versión' : null,
                  onPressed: canManageAccounting ? () => onAppend(item) : null),
        ]),
      );

  static String _policySummary(
      SupplierAccountingPolicySummary item, List<Account> accounts) {
    final version = item.currentVersion;
    if (version == null) return 'Sin versión vigente';
    final account = accounts.cast<Account?>().firstWhere(
        (candidate) => candidate?.id == version.debitAccountId,
        orElse: () => null);
    return 'v${version.version} · ${version.operationalNatureLabel ?? version.operationalNatureCode}'
        '${account == null ? '' : ' · ${account.code} ${account.name}'}';
  }
}

class _CredentialsSection extends StatelessWidget {
  const _CredentialsSection(
      {required this.status,
      required this.onRetry,
      required this.onCreate,
      required this.onRotate,
      required this.onDelete});
  final SupplierCredentialStatus? status;
  final VoidCallback onRetry;
  final VoidCallback onCreate;
  final ValueChanged<SupplierCredentialMetadata> onRotate;
  final ValueChanged<SupplierCredentialMetadata> onDelete;

  @override
  Widget build(BuildContext context) => _EditorSection(
        title: 'Accesos',
        description:
            'Inventario protegido por clave estable. Un origen HTTPS exacto habilita el acceso web; los secretos nunca forman parte de la ficha.',
        trailing: TextButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Agregar acceso')),
        child: status == null
            ? Row(children: [
                const Expanded(
                    child:
                        Text('No fue posible leer los metadatos protegidos.')),
                TextButton(onPressed: onRetry, child: const Text('Reintentar'))
              ])
            : status!.credentials.isEmpty
                ? const _EmptyLine(text: 'Sin accesos guardados.')
                : Column(children: [
                    for (final item in status!.credentials)
                      _CredentialRow(
                          metadata: item,
                          onRotate: () => onRotate(item),
                          onDelete: () => onDelete(item))
                  ]),
      );
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow(
      {required this.metadata, required this.onRotate, required this.onDelete});
  final SupplierCredentialMetadata metadata;
  final VoidCallback onRotate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
      child: Row(children: [
        const Icon(Icons.lock_outline),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(metadata.label ?? metadata.credentialKey,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
              '${_credentialInventoryKindLabel(metadata)} · ${metadata.originUrl ?? 'Sin origen autorizado'}${metadata.username == null ? '' : ' · Usuario registrado'}${metadata.secretAvailable ? '' : ' · Sin clave guardada'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ])),
        TextButton(
          onPressed: onRotate,
          child: Text(metadata.secretAvailable ? 'Rotar' : 'Completar'),
        ),
        IconButton(
            onPressed: onDelete,
            tooltip: 'Eliminar acceso',
            icon: const Icon(Icons.delete_outline)),
      ]),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow(
      {required this.title,
      required this.subtitle,
      required this.actionLabel,
      required this.onPressed});
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        ])),
        if (actionLabel != null && onPressed != null)
          TextButton(onPressed: onPressed, child: Text(actionLabel!)),
      ]),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _EditorActions extends StatelessWidget {
  const _EditorActions(
      {required this.saving,
      required this.editing,
      required this.onCancel,
      required this.onSave});
  final bool saving;
  final bool editing;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  @override
  Widget build(BuildContext context) {
    final cancel = TextButton(
      onPressed: saving ? null : onCancel,
      child: const Text('Cancelar'),
    );
    final save = FilledButton(
      key: const ValueKey('supplier-save'),
      onPressed: saving ? null : onSave,
      child: Text(
        saving
            ? 'Guardando…'
            : editing
                ? 'Guardar cambios'
                : 'Crear proveedor',
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 48, child: save),
              const SizedBox(height: 8),
              SizedBox(height: 48, child: cancel),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [cancel, const SizedBox(width: 10), save],
        );
      },
    );
  }
}

class _EditorLoadFailure extends StatelessWidget {
  const _EditorLoadFailure(
      {required this.foundationUnavailable,
      required this.onRetry,
      required this.onClose});
  final bool foundationUnavailable;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              VbNotice(
                title: foundationUnavailable
                    ? 'La base de proveedores no está disponible'
                    : 'No se pudo abrir el proveedor',
                body: foundationUnavailable
                    ? 'El editor no usará el formulario antiguo ni creará un registro incompleto.'
                    : 'No se insertará un proveedor nuevo para reemplazar una carga fallida.',
                tone: VbNoticeTone.danger,
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(onPressed: onClose, child: const Text('Volver')),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: onRetry, child: const Text('Reintentar'))
              ]),
            ]),
          ),
        ),
      );
}

class _EngagementDraft {
  const _EngagementDraft(
      {required this.operationId,
      required this.kind,
      required this.name,
      required this.version});
  final String operationId;
  final SupplierEngagementKind kind;
  final String name;
  final SupplierEngagementVersionInput version;
}

class _EngagementDialog extends StatefulWidget {
  const _EngagementDialog({
    required this.effectiveBusinessDate,
    this.existing,
    this.retainedDraft,
  });
  final SupplierEngagement? existing;
  final _EngagementDraft? retainedDraft;
  final DateTime effectiveBusinessDate;
  @override
  State<_EngagementDialog> createState() => _EngagementDialogState();
}

class _EngagementDialogState extends State<_EngagementDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _effectiveFromController = TextEditingController();
  final _reference = TextEditingController();
  final _serviceId = TextEditingController();
  final _amount = TextEditingController();
  final _dueDay = TextEditingController();
  final _portalUrl = TextEditingController();
  final String _operationId = const Uuid().v4();
  late SupplierEngagementKind _kind;
  late SupplierEngagementBillingCycle _billing;
  late DateTime _effectiveFrom;
  late DateTime _minimumEffectiveFrom;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final version = existing?.latestVersion;
    final retained = widget.retainedDraft;
    final businessDate = _civilDate(widget.effectiveBusinessDate);
    _minimumEffectiveFrom = existing == null || version == null
        ? businessDate
        : _laterCivilDate(
            businessDate,
            _nextCivilDate(version.validFrom),
          );
    final retainedEffectiveFrom = retained?.version.effectiveFrom;
    _effectiveFrom = retainedEffectiveFrom == null ||
            _civilDate(retainedEffectiveFrom).isBefore(_minimumEffectiveFrom)
        ? _minimumEffectiveFrom
        : _civilDate(retainedEffectiveFrom);
    _effectiveFromController.text = _formatCivilDate(_effectiveFrom);
    _kind = retained?.kind ?? existing?.kind ?? SupplierEngagementKind.contract;
    _billing = retained?.version.billingCycle ??
        SupplierEngagementBillingCycle.fromJson(version?.billingCadence);
    _name.text = retained?.name ?? existing?.name ?? '';
    _reference.text =
        retained?.version.externalReference ?? version?.externalReference ?? '';
    _serviceId.text =
        retained?.version.serviceIdentifier ?? version?.serviceIdentifier ?? '';
    _amount.text = retained?.version.expectedAmount?.toString() ??
        version?.expectedAmount?.toString() ??
        '';
    _dueDay.text = retained?.version.dueDay?.toString() ??
        version?.dueDay?.toString() ??
        '';
    _portalUrl.text = retained?.version.portalUrl ?? version?.portalUrl ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _effectiveFromController,
      _reference,
      _serviceId,
      _amount,
      _dueDay,
      _portalUrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.existing == null ? 'Nueva relación' : 'Agregar versión'),
        content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
                key: _form,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.existing == null) ...[
                    _field(_name, 'Nombre de la relación', required: true),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<SupplierEngagementKind>(
                        initialValue: _kind,
                        decoration: const InputDecoration(
                            labelText: 'Tipo de relación'),
                        items: SupplierEngagementKind.values
                            .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(_engagementKindLabel(value))))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _kind = value);
                        }),
                    const SizedBox(height: 12),
                  ] else
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(widget.existing!.name,
                            style: Theme.of(context).textTheme.titleSmall)),
                  if (widget.existing != null) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey(
                        'supplier-engagement-effective-from',
                      ),
                      controller: _effectiveFromController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Rige desde',
                        helperText:
                            'Debe ser posterior a la última versión guardada.',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      onTap: _pickEffectiveFrom,
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SupplierEngagementBillingCycle>(
                      initialValue: _billing,
                      decoration:
                          const InputDecoration(labelText: 'Ciclo de cobro'),
                      items: SupplierEngagementBillingCycle.values
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(_billingLabel(value))))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _billing = value);
                      }),
                  const SizedBox(height: 12),
                  _field(_reference, 'Referencia externa'),
                  const SizedBox(height: 12),
                  _field(_serviceId, 'Identificador del servicio'),
                  if (_billing != SupplierEngagementBillingCycle.free) ...[
                    const SizedBox(height: 12),
                    _field(_amount, 'Monto esperado',
                        keyboardType: TextInputType.number)
                  ],
                  const SizedBox(height: 12),
                  _field(_dueDay, 'Día de vencimiento',
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  _field(_portalUrl, 'URL del portal'),
                ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(onPressed: _submit, child: const Text('Guardar versión'))
        ],
      );

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final amount = double.tryParse(_amount.text.trim());
    final dueDay = int.tryParse(_dueDay.text.trim());
    Navigator.pop(
        context,
        _EngagementDraft(
          operationId: widget.retainedDraft?.operationId ?? _operationId,
          kind: _kind,
          name: widget.existing?.name ?? _name.text.trim(),
          version: SupplierEngagementVersionInput(
            effectiveFrom: _effectiveFrom,
            externalReference: _textOrNull(_reference.text),
            serviceIdentifier: _textOrNull(_serviceId.text),
            billingCycle: _billing,
            expectedAmount:
                _billing == SupplierEngagementBillingCycle.free ? null : amount,
            dueDay: dueDay,
            portalUrl: _textOrNull(_portalUrl.text),
          ),
        ));
  }

  Future<void> _pickEffectiveFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: _minimumEffectiveFrom,
      lastDate: DateTime(9999, 12, 31),
      currentDate: _civilDate(widget.effectiveBusinessDate),
      helpText: 'Rige desde',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      fieldLabelText: 'Rige desde',
      errorInvalidText:
          'Elige una fecha posterior a la última versión guardada',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _effectiveFrom = _civilDate(picked);
      _effectiveFromController.text = _formatCivilDate(_effectiveFrom);
    });
  }
}

class _AccountingDraft {
  const _AccountingDraft({
    required this.operationId,
    required this.name,
    required this.engagementId,
    required this.version,
    required this.ruleDrafts,
    required this.supplierFallbackConfirmed,
    required this.unconditionalConfirmed,
  });
  final String operationId;
  final String name;
  final String? engagementId;
  final SupplierAccountingPolicyVersionInput version;
  final List<_AccountingRuleDraft> ruleDrafts;
  final bool supplierFallbackConfirmed;
  final bool unconditionalConfirmed;

  List<SupplierAccountingRuleInput> get rules =>
      ruleDrafts.map((rule) => rule.toInput()).toList(growable: false);
}

enum _AccountingScope { engagement, supplierFallback }

class _AccountingRuleDraft {
  const _AccountingRuleDraft({
    required this.localId,
    required this.kind,
    required this.operator,
    required this.value,
    required this.operand,
    required this.priority,
    required this.isActive,
  });

  factory _AccountingRuleDraft.fromSummary(
    SupplierAccountingRuleSummary summary,
  ) {
    final kind = SupplierAccountingRuleKind.values.firstWhere(
      (candidate) => candidate.dbValue == summary.ruleKind,
    );
    final operator = SupplierAccountingRuleOperator.values.firstWhere(
      (candidate) => candidate.name == summary.operatorCode,
    );
    return _AccountingRuleDraft(
      localId: summary.id,
      kind: kind,
      operator: operator,
      value: _ruleOperandText(kind, summary.operand) ?? '',
      operand: summary.operand,
      priority: summary.priority,
      isActive: summary.isActive,
    );
  }

  factory _AccountingRuleDraft.empty(int index) => _AccountingRuleDraft(
        localId: const Uuid().v4(),
        kind: SupplierAccountingRuleKind.documentType,
        operator: SupplierAccountingRuleOperator.equals,
        value: '',
        operand: const {},
        priority: (index + 1) * 10,
        isActive: true,
      );

  final String localId;
  final SupplierAccountingRuleKind kind;
  final SupplierAccountingRuleOperator operator;
  final String value;
  final Map<String, dynamic> operand;
  final int priority;
  final bool isActive;

  bool get isEditable =>
      isActive &&
      _editableAccountingRuleKinds.contains(kind) &&
      _operatorsForAccountingRule(kind).contains(operator);

  _AccountingRuleDraft copyWith({
    SupplierAccountingRuleKind? kind,
    SupplierAccountingRuleOperator? operator,
    String? value,
  }) =>
      _AccountingRuleDraft(
        localId: localId,
        kind: kind ?? this.kind,
        operator: operator ?? this.operator,
        value: value ?? this.value,
        operand: operand,
        priority: priority,
        isActive: isActive,
      );

  SupplierAccountingRuleInput toInput() {
    final nextOperand = <String, dynamic>{...operand};
    if (isEditable) {
      nextOperand
        ..remove('document_type')
        ..remove('text')
        ..[_operandKeyForAccountingRule(kind)] = value.trim();
    }
    return SupplierAccountingRuleInput(
      kind: kind,
      operator: operator,
      operand: nextOperand,
      priority: priority,
      isActive: isActive,
    );
  }
}

const _editableAccountingRuleKinds = <SupplierAccountingRuleKind>{
  SupplierAccountingRuleKind.documentType,
  SupplierAccountingRuleKind.description,
  SupplierAccountingRuleKind.lineDescription,
};

List<SupplierAccountingRuleOperator> _operatorsForAccountingRule(
  SupplierAccountingRuleKind kind,
) =>
    kind == SupplierAccountingRuleKind.documentType
        ? const [SupplierAccountingRuleOperator.equals]
        : const [
            SupplierAccountingRuleOperator.contains,
            SupplierAccountingRuleOperator.prefix,
            SupplierAccountingRuleOperator.equals,
          ];

String _operandKeyForAccountingRule(SupplierAccountingRuleKind kind) =>
    kind == SupplierAccountingRuleKind.documentType ? 'document_type' : 'text';

String? _ruleOperandText(
  SupplierAccountingRuleKind kind,
  Map<String, dynamic> operand,
) {
  final value = operand[_operandKeyForAccountingRule(kind)]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

class _AccountingDialog extends StatefulWidget {
  const _AccountingDialog({
    required this.existing,
    required this.retainedDraft,
    required this.engagements,
    required this.existingRules,
    required this.effectiveBusinessDate,
    required this.natures,
    required this.accounts,
    required this.categories,
    required this.accountCatalogUnavailable,
    required this.expenseCatalogUnavailable,
  });
  final SupplierAccountingPolicySummary? existing;
  final _AccountingDraft? retainedDraft;
  final List<SupplierEngagement> engagements;
  final List<SupplierAccountingRuleSummary> existingRules;
  final DateTime effectiveBusinessDate;
  final List<SupplierClassificationDefinition> natures;
  final List<Account> accounts;
  final List<ExpenseCategory> categories;
  final bool accountCatalogUnavailable;
  final bool expenseCatalogUnavailable;
  @override
  State<_AccountingDialog> createState() => _AccountingDialogState();
}

class _AccountingDialogState extends State<_AccountingDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _effectiveFromController = TextEditingController();
  final String _operationId = const Uuid().v4();
  late SupplierClassificationDefinition _nature;
  String? _debitAccountId;
  String? _liabilityAccountId;
  String? _categoryId;
  late _AccountingScope _scope;
  String? _engagementId;
  late List<_AccountingRuleDraft> _rules;
  bool _supplierFallbackConfirmed = false;
  bool _unconditionalConfirmed = false;
  String? _scopeError;
  String? _rulesError;
  late DateTime _effectiveFrom;
  late DateTime _minimumEffectiveFrom;
  SupplierAccountingTaxTreatment _tax =
      SupplierAccountingTaxTreatment.notApplicable;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final version = existing?.latestVersion;
    final retained = widget.retainedDraft;
    final businessDate = _civilDate(widget.effectiveBusinessDate);
    _minimumEffectiveFrom = existing == null || version == null
        ? businessDate
        : _laterCivilDate(
            businessDate,
            _nextCivilDate(version.effectiveFrom),
          );
    final retainedEffectiveFrom = retained?.version.effectiveFrom;
    _effectiveFrom = retainedEffectiveFrom == null ||
            _civilDate(retainedEffectiveFrom).isBefore(_minimumEffectiveFrom)
        ? _minimumEffectiveFrom
        : _civilDate(retainedEffectiveFrom);
    _effectiveFromController.text = _formatCivilDate(_effectiveFrom);
    _name.text = retained?.name ?? existing?.name ?? '';
    _engagementId = retained?.engagementId ?? existing?.engagementId;
    _scope = _engagementId == null
        ? _AccountingScope.supplierFallback
        : _AccountingScope.engagement;
    if (existing == null && retained == null && widget.engagements.isNotEmpty) {
      _scope = _AccountingScope.engagement;
    }
    _supplierFallbackConfirmed = retained?.supplierFallbackConfirmed ?? false;
    _unconditionalConfirmed = retained?.unconditionalConfirmed ?? false;
    _rules = retained?.ruleDrafts
            .map((rule) => rule.copyWith())
            .toList(growable: true) ??
        widget.existingRules
            .map(_AccountingRuleDraft.fromSummary)
            .toList(growable: true);
    _nature = widget.natures.firstWhere(
      (item) =>
          item.id == retained?.version.operationalNature.id ||
          item.id == version?.operationalNatureDefinitionId ||
          item.code == version?.operationalNatureCode,
      orElse: () => widget.natures.first,
    );
    _debitAccountId =
        retained?.version.debitAccountId ?? version?.debitAccountId;
    _liabilityAccountId =
        retained?.version.liabilityAccountId ?? version?.liabilityAccountId;
    _categoryId = retained?.version.legacyExpenseCategoryId ??
        version?.legacyExpenseCategoryId;
    _tax = retained?.version.taxTreatment ??
        SupplierAccountingTaxTreatment.fromJson(version?.taxTreatmentCode);
  }

  @override
  void dispose() {
    _name.dispose();
    _effectiveFromController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null
          ? 'Nuevo criterio contable'
          : 'Agregar versión de criterio'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (existing == null) ...[
                  _field(_name, 'Nombre del criterio', required: true),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_AccountingScope>(
                    key: const ValueKey('supplier-accounting-scope'),
                    initialValue: _scope,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Alcance del criterio',
                      errorText: _scopeError,
                    ),
                    items: [
                      if (widget.engagements.isNotEmpty)
                        const DropdownMenuItem(
                          value: _AccountingScope.engagement,
                          child: Text('Una relación específica'),
                        ),
                      const DropdownMenuItem(
                        value: _AccountingScope.supplierFallback,
                        child: Text('Proveedor completo (respaldo)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _scope = value;
                        _engagementId = null;
                        _supplierFallbackConfirmed = false;
                        _scopeError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Text(
                    existing.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _AccountingScopeSummary(
                    engagementId: existing.engagementId,
                    engagements: widget.engagements,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey(
                      'supplier-accounting-effective-from',
                    ),
                    controller: _effectiveFromController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Rige desde',
                      helperText:
                          'Debe ser posterior a la última versión guardada.',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    onTap: _pickEffectiveFrom,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_scope == _AccountingScope.engagement && existing == null)
                  DropdownButtonFormField<String>(
                    key: const ValueKey('supplier-accounting-engagement'),
                    initialValue: _engagementId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Relación específica',
                      helperText:
                          'Guarda esta relación como contexto exacto; ningún asiento se genera aquí.',
                    ),
                    items: widget.engagements
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    validator: (value) => value == null
                        ? 'Selecciona la relación que define el contexto'
                        : null,
                    onChanged: (value) => setState(() {
                      _engagementId = value;
                      _scopeError = null;
                    }),
                  ),
                if (_scope == _AccountingScope.supplierFallback &&
                    existing == null) ...[
                  const VbNotice(
                    title: 'Criterio de último recurso',
                    body:
                        'Se guarda como respaldo para todo el proveedor. Este módulo no lo aplica ni completa asientos.',
                    tone: VbNoticeTone.warning,
                  ),
                  CheckboxListTile(
                    key: const ValueKey(
                      'supplier-accounting-confirm-fallback',
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Confirmo el alcance para todo el proveedor',
                    ),
                    value: _supplierFallbackConfirmed,
                    onChanged: (value) => setState(() {
                      _supplierFallbackConfirmed = value ?? false;
                      _scopeError = null;
                    }),
                  ),
                  if (_scopeError != null)
                    Text(
                      _scopeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<SupplierClassificationDefinition>(
                  initialValue: _nature,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Naturaleza operacional',
                  ),
                  items: widget.natures
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _nature = value);
                  },
                ),
                if (widget.accountCatalogUnavailable ||
                    widget.expenseCatalogUnavailable) ...[
                  const SizedBox(height: 12),
                  VbNotice(
                    title: 'Selectores contables temporalmente deshabilitados',
                    body: widget.accountCatalogUnavailable &&
                            widget.expenseCatalogUnavailable
                        ? 'Cuentas y categorías no pudieron leerse. Puedes guardar sólo la naturaleza o cancelar y reintentar desde la ficha.'
                        : widget.accountCatalogUnavailable
                            ? 'Las cuentas no pudieron leerse. Puedes guardar sin cuentas o cancelar y reintentar desde la ficha.'
                            : 'Las categorías no pudieron leerse. Puedes guardar sin categoría o cancelar y reintentar desde la ficha.',
                    tone: VbNoticeTone.warning,
                  ),
                ],
                if (!widget.expenseCatalogUnavailable &&
                    widget.categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Categoría de gasto (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sin categoría predeterminada'),
                      ),
                      ...widget.categories.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                ],
                if (!widget.accountCatalogUnavailable &&
                    widget.accounts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _debitAccountId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cuenta de cargo (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sin cuenta predeterminada'),
                      ),
                      ...widget.accounts
                          .where((account) =>
                              account.id != null && account.isActive)
                          .map(
                            (account) => DropdownMenuItem<String?>(
                              value: account.id,
                              child: Text('${account.code} · ${account.name}'),
                            ),
                          ),
                    ],
                    onChanged: (value) =>
                        setState(() => _debitAccountId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _liabilityAccountId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cuenta por pagar (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sin cuenta predeterminada'),
                      ),
                      ...widget.accounts
                          .where((account) =>
                              account.id != null && account.isActive)
                          .map(
                            (account) => DropdownMenuItem<String?>(
                              value: account.id,
                              child: Text('${account.code} · ${account.name}'),
                            ),
                          ),
                    ],
                    onChanged: (value) =>
                        setState(() => _liabilityAccountId = value),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<SupplierAccountingTaxTreatment>(
                  initialValue: _tax,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tratamiento tributario',
                  ),
                  items: SupplierAccountingTaxTreatment.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_taxLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _tax = value);
                  },
                ),
                const SizedBox(height: 20),
                _buildRuleEditor(context),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('supplier-accounting-save-version'),
          onPressed: _submit,
          child: const Text('Guardar versión'),
        ),
      ],
    );
  }

  Widget _buildRuleEditor(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Señales de contexto',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Estas señales documentan la evidencia que deberá exigir un consumidor contable; este editor sólo las versiona.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < _rules.length; index++) ...[
          _AccountingRuleEditor(
            key: ValueKey(_rules[index].localId),
            index: index,
            rule: _rules[index],
            onChanged: (rule) => setState(() {
              _rules[index] = rule;
              _rulesError = null;
            }),
            onRemove: () => setState(() {
              _rules.removeAt(index);
              _unconditionalConfirmed = false;
              _rulesError = null;
            }),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('supplier-accounting-add-rule'),
            onPressed: () => setState(() {
              _rules.add(_AccountingRuleDraft.empty(_rules.length));
              _unconditionalConfirmed = false;
              _rulesError = null;
            }),
            icon: const Icon(Icons.add),
            label: const Text('Agregar condición'),
          ),
        ),
        if (_rules.isEmpty) ...[
          const VbNotice(
            title: 'Sin condiciones adicionales',
            body:
                'La versión quedará sin señales documentales adicionales dentro del alcance definido arriba.',
            tone: VbNoticeTone.warning,
          ),
          CheckboxListTile(
            key: const ValueKey(
              'supplier-accounting-confirm-unconditional',
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Confirmo que este criterio no necesita condiciones adicionales',
            ),
            value: _unconditionalConfirmed,
            onChanged: (value) => setState(() {
              _unconditionalConfirmed = value ?? false;
              _rulesError = null;
            }),
          ),
        ],
        if (_rulesError != null)
          Text(
            _rulesError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
      ],
    );
  }

  void _submit() {
    final formValid = _form.currentState!.validate();
    final newSupplierFallback =
        widget.existing == null && _scope == _AccountingScope.supplierFallback;
    final scopeValid = !newSupplierFallback || _supplierFallbackConfirmed;
    final rulesValid = _rules.isNotEmpty || _unconditionalConfirmed;
    if (!formValid || !scopeValid || !rulesValid) {
      setState(() {
        _scopeError = scopeValid
            ? null
            : 'Confirma que este criterio será un respaldo general';
        _rulesError = rulesValid
            ? null
            : 'Agrega una condición o confirma la versión sin condiciones';
      });
      return;
    }
    final existingVersion = widget.existing?.latestVersion;
    Navigator.pop(
        context,
        _AccountingDraft(
          operationId: widget.retainedDraft?.operationId ?? _operationId,
          name: widget.existing?.name ?? _name.text.trim(),
          engagementId: widget.existing?.engagementId ??
              (_scope == _AccountingScope.engagement ? _engagementId : null),
          version: SupplierAccountingPolicyVersionInput(
            effectiveFrom: _effectiveFrom,
            operationalNature: _nature,
            legacyExpenseCategoryId: _categoryId,
            debitAccountId: _debitAccountId,
            liabilityAccountId: _liabilityAccountId,
            taxTreatment: _tax,
            expectedDocumentType:
                widget.retainedDraft?.version.expectedDocumentType ??
                    existingVersion?.expectedDocumentType,
            currencyCode: widget.retainedDraft?.version.currencyCode ??
                existingVersion?.currencyCode ??
                'CLP',
            lineNature: widget.retainedDraft?.version.lineNature ??
                (existingVersion?.lineNature == null
                    ? null
                    : SupplierAccountingLineNature.fromJson(
                        existingVersion!.lineNature,
                      )),
            publicPosture: widget.retainedDraft?.version.publicPosture ??
                existingVersion?.posture ??
                const {},
          ),
          ruleDrafts: List.unmodifiable(_rules),
          supplierFallbackConfirmed: _supplierFallbackConfirmed,
          unconditionalConfirmed: _unconditionalConfirmed,
        ));
  }

  Future<void> _pickEffectiveFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: _minimumEffectiveFrom,
      lastDate: DateTime(9999, 12, 31),
      currentDate: _civilDate(widget.effectiveBusinessDate),
      helpText: 'Rige desde',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      fieldLabelText: 'Rige desde',
      errorInvalidText:
          'Elige una fecha posterior a la última versión guardada',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _effectiveFrom = _civilDate(picked);
      _effectiveFromController.text = _formatCivilDate(_effectiveFrom);
    });
  }
}

class _AccountingScopeSummary extends StatelessWidget {
  const _AccountingScopeSummary({
    required this.engagementId,
    required this.engagements,
  });

  final String? engagementId;
  final List<SupplierEngagement> engagements;

  @override
  Widget build(BuildContext context) {
    final engagement = engagements.cast<SupplierEngagement?>().firstWhere(
          (item) => item?.id == engagementId,
          orElse: () => null,
        );
    return VbNotice(
      title: engagementId == null
          ? 'Alcance: proveedor completo'
          : 'Alcance: relación específica',
      body: engagementId == null
          ? 'Esta versión conserva el criterio como respaldo general. El alcance no se cambia al agregar una versión.'
          : 'Esta versión seguirá asociada a ${engagement?.name ?? 'la relación registrada'}. El alcance no se cambia al agregar una versión.',
      tone: engagementId == null ? VbNoticeTone.warning : VbNoticeTone.neutral,
    );
  }
}

class _AccountingRuleEditor extends StatelessWidget {
  const _AccountingRuleEditor({
    super.key,
    required this.index,
    required this.rule,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _AccountingRuleDraft rule;
  final ValueChanged<_AccountingRuleDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rule.isEditable
                        ? 'Condición ${index + 1}'
                        : 'Condición existente conservada',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Eliminar condición',
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (!rule.isEditable)
              Text(
                '${_accountingRuleKindLabel(rule.kind)} · ${_accountingRuleOperatorLabel(rule.operator)}. Se copiará intacta a la nueva versión salvo que la elimines.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              DropdownButtonFormField<SupplierAccountingRuleKind>(
                key: ValueKey('supplier-accounting-rule-kind-${rule.localId}'),
                initialValue: rule.kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Dato a evaluar'),
                items: _editableAccountingRuleKinds
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(_accountingRuleKindLabel(kind)),
                      ),
                    )
                    .toList(),
                onChanged: (kind) {
                  if (kind == null) return;
                  onChanged(
                    rule.copyWith(
                      kind: kind,
                      operator: _operatorsForAccountingRule(kind).first,
                      value: '',
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<SupplierAccountingRuleOperator>(
                key: ValueKey(
                  'supplier-accounting-rule-operator-${rule.localId}-${rule.kind.name}',
                ),
                initialValue: rule.operator,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Comparación'),
                items: _operatorsForAccountingRule(rule.kind)
                    .map(
                      (operator) => DropdownMenuItem(
                        value: operator,
                        child: Text(
                          _accountingRuleOperatorLabel(operator),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (operator) {
                  if (operator != null) {
                    onChanged(rule.copyWith(operator: operator));
                  }
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: ValueKey(
                  'supplier-accounting-rule-value-${rule.localId}-${rule.kind.name}',
                ),
                initialValue: rule.value,
                maxLength: rule.kind == SupplierAccountingRuleKind.documentType
                    ? 64
                    : 500,
                decoration: InputDecoration(
                  labelText: _accountingRuleValueLabel(rule.kind),
                  helperText: _accountingRuleValueHelp(rule.kind),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'Ingresa el valor que debe reconocer';
                  }
                  final limit =
                      rule.kind == SupplierAccountingRuleKind.documentType
                          ? 64
                          : 500;
                  return text.length > limit
                      ? 'Usa un valor de hasta $limit caracteres'
                      : null;
                },
                onChanged: (value) => onChanged(rule.copyWith(value: value)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CredentialDraft {
  const _CredentialDraft(
      {required this.operationId,
      required this.kind,
      required this.credentialKey,
      required this.origin,
      required this.secret,
      this.engagementId,
      this.label,
      this.username});
  final String operationId;
  final SupplierCredentialKind kind;
  final String credentialKey;
  final String? origin;
  final String secret;
  final String? engagementId;
  final String? label;
  final String? username;
}

class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog({required this.existing, required this.engagements});
  final SupplierCredentialMetadata? existing;
  final List<SupplierEngagement> engagements;
  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController();
  final _origin = TextEditingController();
  final _label = TextEditingController();
  final _username = TextEditingController();
  final _secret = TextEditingController();
  final String _operationId = const Uuid().v4();
  late SupplierCredentialKind _kind;
  String? _engagementId;

  bool get _completingExisting =>
      widget.existing != null && !widget.existing!.secretAvailable;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing?.kind ?? SupplierCredentialKind.portalPassword;
    _key.text = existing?.credentialKey ?? '';
    _origin.text = existing?.originUrl ?? '';
    _label.text = existing?.label ?? '';
    _username.text = existing?.username ?? '';
    _engagementId = existing?.engagementId;
  }

  @override
  void dispose() {
    _secret.clear();
    for (final c in [_key, _origin, _label, _username, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null
            ? 'Agregar acceso'
            : _completingExisting
                ? 'Completar acceso'
                : 'Rotar acceso'),
        content: SizedBox(
            width: 560,
            child: Form(
                key: _form,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<SupplierCredentialKind>(
                      initialValue: _kind,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Tipo de acceso'),
                      items: SupplierCredentialKind.values
                          .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_credentialKindLabel(value))))
                          .toList(),
                      onChanged: widget.existing == null
                          ? (value) {
                              if (value != null) setState(() => _kind = value);
                            }
                          : null),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _key,
                      enabled: widget.existing == null,
                      decoration: const InputDecoration(
                          labelText: 'Clave estable',
                          helperText:
                              'Minúsculas, números, punto, guion o guion bajo.'),
                      validator: (value) => RegExp(r'^[a-z][a-z0-9_.-]*$')
                              .hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Usa una clave estable válida'),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _origin,
                      decoration: const InputDecoration(
                          labelText: 'Origen HTTPS autorizado (opcional)',
                          helperText:
                              'Sólo para acceso web: https://portal.proveedor.cl (sin ruta)'),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return null;
                        final canonical =
                            canonicalSupplierCredentialOrigin(text);
                        return canonical == null ||
                                canonical != text.toLowerCase()
                            ? 'Ingresa el origen HTTPS exacto, sin ruta ni parámetros'
                            : null;
                      }),
                  const SizedBox(height: 12),
                  _field(_label, 'Nombre visible'),
                  const SizedBox(height: 12),
                  _field(_username, 'Usuario (protegido)'),
                  if (widget.engagements.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                        initialValue: _engagementId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Relación asociada (opcional)'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Sin relación asociada')),
                          ...widget.engagements.map((item) =>
                              DropdownMenuItem<String?>(
                                  value: item.id, child: Text(item.name)))
                        ],
                        onChanged: (value) =>
                            setState(() => _engagementId = value))
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _secret,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                          labelText: widget.existing == null
                              ? 'Secreto'
                              : _completingExisting
                                  ? 'Guardar una clave'
                                  : 'Nuevo secreto'),
                      validator: (value) => (value?.isEmpty ?? true)
                          ? _completingExisting
                              ? 'Ingresa una clave para completar este acceso'
                              : 'El secreto es obligatorio'
                          : null),
                  const SizedBox(height: 10),
                  VbNotice(
                      title: _completingExisting
                          ? 'Aún no hay una clave guardada'
                          : 'El secreto no entra a la ficha',
                      body: _completingExisting
                          ? 'La cuenta y sus metadatos ya están protegidos. La nueva clave se enviará directamente al Vault.'
                          : 'Se envía directamente al Vault y este formulario lo descarta al cerrarse.',
                      tone: VbNoticeTone.info),
                ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _submit,
              child: Text(widget.existing == null
                  ? 'Agregar'
                  : _completingExisting
                      ? 'Completar'
                      : 'Rotar'))
        ],
      );

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final originText = _origin.text.trim();
    Navigator.pop(
        context,
        _CredentialDraft(
          operationId: _operationId,
          kind: _kind,
          credentialKey: _key.text.trim(),
          origin: originText.isEmpty
              ? null
              : canonicalSupplierCredentialOrigin(originText),
          secret: _secret.text,
          engagementId: _engagementId,
          label: _textOrNull(_label.text),
          username: _textOrNull(_username.text),
        ));
    _secret.clear();
  }
}

Widget _field(TextEditingController controller, String label,
        {bool required = false, Key? key, TextInputType? keyboardType}) =>
    TextFormField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (value) => (value?.trim().isEmpty ?? true)
              ? 'Este dato es obligatorio'
              : null
          : null,
    );

Widget _responsivePair(bool compact, Widget first, Widget second) {
  if (compact) {
    return Column(children: [first, const SizedBox(height: 12), second]);
  }
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: first),
    const SizedBox(width: 14),
    Expanded(child: second)
  ]);
}

String? _textOrNull(String value) => value.trim().isEmpty ? null : value.trim();

DateTime _civilDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _nextCivilDate(DateTime value) {
  final civil = _civilDate(value);
  return DateTime(civil.year, civil.month, civil.day + 1);
}

DateTime _laterCivilDate(DateTime first, DateTime second) {
  final firstCivil = _civilDate(first);
  final secondCivil = _civilDate(second);
  return firstCivil.isAfter(secondCivil) ? firstCivil : secondCivil;
}

String _formatCivilDate(DateTime value) {
  final civil = _civilDate(value);
  return '${civil.day.toString().padLeft(2, '0')}-'
      '${civil.month.toString().padLeft(2, '0')}-${civil.year}';
}

bool _isOptimisticConflict(Object error) =>
    error is PostgrestException && error.code == '40001';

bool _isEffectiveDateConflict(Object error) {
  if (error is! PostgrestException || error.code != '23514') return false;
  return error.message.contains(
        'Next engagement version must start after current version',
      ) ||
      error.message.contains(
        'Next policy version must start after current version',
      );
}

String _engagementKindLabel(SupplierEngagementKind value) => switch (value) {
      SupplierEngagementKind.contract => 'Contrato',
      SupplierEngagementKind.serviceAccount => 'Cuenta de servicio',
      SupplierEngagementKind.subscription => 'Suscripción',
      SupplierEngagementKind.lease => 'Arriendo',
      SupplierEngagementKind.utility => 'Servicio básico',
      SupplierEngagementKind.taxObligation => 'Obligación tributaria',
      SupplierEngagementKind.portal => 'Portal o recurso',
      SupplierEngagementKind.other => 'Otra relación',
    };

String _billingLabel(SupplierEngagementBillingCycle value) => switch (value) {
      SupplierEngagementBillingCycle.free => 'Sin costo',
      SupplierEngagementBillingCycle.monthly => 'Mensual',
      SupplierEngagementBillingCycle.bimonthly => 'Bimestral',
      SupplierEngagementBillingCycle.quarterly => 'Trimestral',
      SupplierEngagementBillingCycle.semiannual => 'Semestral',
      SupplierEngagementBillingCycle.annual => 'Anual',
      SupplierEngagementBillingCycle.irregular => 'Irregular',
      SupplierEngagementBillingCycle.none => 'Sin ciclo',
    };

String _taxLabel(SupplierAccountingTaxTreatment value) => switch (value) {
      SupplierAccountingTaxTreatment.noTax => 'Sin impuesto',
      SupplierAccountingTaxTreatment.taxIncluded => 'Impuesto incluido',
      SupplierAccountingTaxTreatment.exempt => 'Exento',
      SupplierAccountingTaxTreatment.notApplicable => 'No aplica',
    };

String _accountingRuleKindLabel(SupplierAccountingRuleKind value) =>
    switch (value) {
      SupplierAccountingRuleKind.documentType => 'Tipo de documento',
      SupplierAccountingRuleKind.issuerIdentifier => 'Identificador del emisor',
      SupplierAccountingRuleKind.description => 'Descripción del documento',
      SupplierAccountingRuleKind.lineDescription => 'Descripción de la línea',
      SupplierAccountingRuleKind.engagement => 'Relación asociada',
      SupplierAccountingRuleKind.amountRange => 'Rango de monto',
      SupplierAccountingRuleKind.manual => 'Validación manual',
    };

String _accountingRuleOperatorLabel(
  SupplierAccountingRuleOperator value,
) =>
    switch (value) {
      SupplierAccountingRuleOperator.equals => 'Es igual a',
      SupplierAccountingRuleOperator.contains => 'Contiene',
      SupplierAccountingRuleOperator.prefix => 'Comienza con',
      SupplierAccountingRuleOperator.regex => 'Coincide con patrón',
      SupplierAccountingRuleOperator.between => 'Está entre',
      SupplierAccountingRuleOperator.present => 'Está presente',
    };

String _accountingRuleValueLabel(SupplierAccountingRuleKind value) =>
    value == SupplierAccountingRuleKind.documentType
        ? 'Código de documento'
        : 'Texto a reconocer';

String _accountingRuleValueHelp(SupplierAccountingRuleKind value) =>
    value == SupplierAccountingRuleKind.documentType
        ? 'Ejemplo: 33 para una factura electrónica.'
        : 'Usa un fragmento estable que distinga este gasto.';

String _credentialKindLabel(SupplierCredentialKind value) => switch (value) {
      SupplierCredentialKind.portalPassword => 'Contraseña de portal',
      SupplierCredentialKind.apiToken => 'Token de API',
      SupplierCredentialKind.other => 'Otro acceso',
    };

String _credentialInventoryKindLabel(SupplierCredentialMetadata metadata) {
  if (!metadata.secretAvailable &&
      metadata.kind == SupplierCredentialKind.portalPassword) {
    return 'Acceso de portal';
  }
  return _credentialKindLabel(metadata.kind);
}
