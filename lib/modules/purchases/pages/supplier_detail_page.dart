import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../../shared/widgets/vb_sub_tabs.dart';
import '../../messaging/providers/chat_provider.dart';
import '../models/supplier_foundation.dart';
import '../services/supplier_credential_reveal_controller.dart';
import '../services/supplier_credential_service.dart';
import '../services/supplier_relationship_service.dart';
import '../widgets/purchase_visual_language.dart';

/// Read boundary for the routed supplier profile.
///
/// Production uses only the canonical relationship/economic projections and
/// the protected, secret-free credential status RPC. The interface is public
/// so the routed surface can be exercised without booting the whole workspace
/// shell; it is not an alternate persistence owner.
abstract interface class SupplierDetailDataSource {
  Future<SupplierProfile?> getProfile(String supplierId);

  Future<List<SupplierEconomicSummaryReadModel>> getEconomicSummary(
    String supplierId,
  );

  Future<SupplierEconomicTimelinePage> getEconomicTimeline(
    String supplierId,
  );

  Future<SupplierCredentialStatus> getCredentialStatus(String supplierId);

  Future<List<SupplierContact>> listContacts(String supplierId);

  Future<SupplierContactCommandResult> saveContact(
    SaveSupplierContactCommand command,
  );

  Future<SupplierContactCommandResult> setContactStatus(
    SetSupplierContactStatusCommand command,
  );

  /// Cambia (o quita, con `null`) la imagen del proveedor.
  Future<void> updateImage(String supplierId, String? imageUrl);

  bool get canReadCredentialMetadata;

  String get authorityFingerprint;

  Listenable? get profileAuthorityChanges;

  Stream<Object?>? get authAuthorityChanges;
}

class CanonicalSupplierDetailDataSource implements SupplierDetailDataSource {
  CanonicalSupplierDetailDataSource({
    required SupplierRelationshipService relationshipService,
    required CurrentUserProfileService profileService,
    SupplierCredentialService? credentialService,
  })  : _relationshipService = relationshipService,
        _profileService = profileService,
        _credentialService = credentialService ??
            SupplierCredentialService(profileService: profileService);

  final SupplierRelationshipService _relationshipService;
  final CurrentUserProfileService _profileService;
  final SupplierCredentialService _credentialService;

  @override
  Future<SupplierProfile?> getProfile(String supplierId) =>
      _relationshipService.getSupplierProfile(supplierId);

  @override
  Future<List<SupplierEconomicSummaryReadModel>> getEconomicSummary(
    String supplierId,
  ) =>
      _relationshipService.getEconomicSummary(supplierId);

  @override
  Future<SupplierEconomicTimelinePage> getEconomicTimeline(
    String supplierId,
  ) =>
      _relationshipService.getEconomicTimelinePage(supplierId, limit: 50);

  @override
  Future<SupplierCredentialStatus> getCredentialStatus(String supplierId) =>
      _credentialService.getStatus(supplierId: supplierId);

  @override
  Future<List<SupplierContact>> listContacts(String supplierId) =>
      _relationshipService.listSupplierContacts(supplierId);

  @override
  Future<SupplierContactCommandResult> saveContact(
    SaveSupplierContactCommand command,
  ) =>
      _relationshipService.saveSupplierContact(command);

  @override
  Future<SupplierContactCommandResult> setContactStatus(
    SetSupplierContactStatusCommand command,
  ) =>
      _relationshipService.setSupplierContactStatus(command);

  @override
  Future<void> updateImage(String supplierId, String? imageUrl) =>
      _relationshipService.updateSupplierImage(supplierId, imageUrl);

  @override
  bool get canReadCredentialMetadata =>
      _profileService.profile?.canManageSupplierCredentials == true;

  @override
  String get authorityFingerprint {
    final profile = _profileService.profile;
    return '${_credentialService.currentAuthUserId ?? ''}|'
        '${profile?.userId ?? ''}|${profile?.tenantId ?? ''}|'
        '${profile?.canManageSupplierCredentials ?? false}';
  }

  @override
  Listenable get profileAuthorityChanges => _profileService;

  @override
  Stream<Object?>? get authAuthorityChanges =>
      _credentialService.authorityEvents;
}

/// Routed supplier profile.
///
/// Route contract: `/purchases/suppliers/:id`. The only record action is the
/// header's `Editar`, which pushes `/purchases/suppliers/:id/edit`. Closing
/// always follows [ReturnNavigation].
///
/// **Composición 2026-09-03 (pedido del dueño: un perfil, no una ficha).**
/// Una sola hoja sobre el canvas: portada con degradado del acento, avatar
/// (imagen del proveedor o monograma) montado sobre la portada, nombre,
/// estado, línea de identidad y las acciones a la derecha; debajo las
/// pestañas `T-04` y, dentro de la misma hoja, el contenido. El Resumen es
/// una columna principal con las cifras en línea y los últimos movimientos, y
/// una columna lateral hundida con el contacto principal, los datos de
/// contacto y las cuentas. Nada flota en tarjetas sueltas: los grupos se
/// separan con hairlines y títulos. La lógica —lectura canónica, revelado
/// auditado de claves, comandos de contactos, retorno— no cambió. Los valores
/// visuales vienen de `GUÍA GENERAL Viñabike - Componentes` (F-02, F-04, F-05,
/// F-06, A-01, E-01, E-04, T-01, T-04, T-05) y los colores de [PurchaseTokens].
class SupplierDetailPage extends StatefulWidget {
  const SupplierDetailPage({
    super.key,
    required this.supplierId,
    this.dataSource,
    this.credentialRevealController,
    this.includeWorkspaceShell = true,
  });

  final String supplierId;
  final SupplierDetailDataSource? dataSource;

  /// Test seam for exercising the audited, short-lived reveal interaction.
  /// Production callers leave this null so this page creates the controller
  /// from the same credential service used by its metadata data source.
  @visibleForTesting
  final SupplierCredentialRevealController? credentialRevealController;

  /// Test seam for the record surface. Routed production callers leave this
  /// true; it does not create a second product surface.
  @visibleForTesting
  final bool includeWorkspaceShell;

  @override
  State<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

/// Las pestañas del perfil, en el orden en que el operador las necesita.
enum _SupplierDetailSection {
  summary('Resumen'),
  contacts('Contactos'),
  data('Datos'),
  movements('Movimientos'),
  access('Accesos'),
  relationships('Relaciones'),
  accounting('Criterios contables');

  const _SupplierDetailSection(this.label);

  final String label;
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  SupplierDetailDataSource? _dataSource;
  SupplierCredentialRevealController? _credentialRevealController;
  bool _ownsCredentialRevealController = false;
  Listenable? _profileAuthorityChanges;
  StreamSubscription<Object?>? _authAuthoritySubscription;
  String? _authorityFingerprint;
  SupplierProfile? _profile;
  List<SupplierContact> _contacts = const [];
  Object? _contactsError;
  bool _contactCommandRunning = false;
  bool _imageCommandRunning = false;
  List<SupplierEconomicSummaryReadModel> _economicSummaries = const [];
  SupplierEconomicTimelinePage? _economicTimeline;
  SupplierCredentialStatus? _credentialStatus;
  Object? _credentialStatusError;
  String? _credentialRevealErrorTarget;
  String? _credentialRevealErrorMessage;
  bool _credentialAccessDenied = false;
  Object? _loadError;
  bool _loading = true;
  int _loadGeneration = 0;
  _SupplierDetailSection _selectedSection = _SupplierDetailSection.summary;

  SupplierDetailDataSource get _source => _dataSource!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dataSource != null) return;
    late final SupplierDetailDataSource source;
    if (widget.dataSource case final injectedSource?) {
      source = injectedSource;
      _credentialRevealController = widget.credentialRevealController;
    } else {
      final profileService = context.read<CurrentUserProfileService>();
      final credentialService = SupplierCredentialService(
        profileService: profileService,
      );
      source = CanonicalSupplierDetailDataSource(
        relationshipService: context.read<SupplierRelationshipService>(),
        profileService: profileService,
        credentialService: credentialService,
      );
      _credentialRevealController = widget.credentialRevealController ??
          SupplierCredentialRevealController(
            credentialService: credentialService,
            profileService: profileService,
          );
      _ownsCredentialRevealController =
          widget.credentialRevealController == null;
    }
    _dataSource = source;
    _credentialRevealController?.addListener(_handleCredentialRevealChange);
    _authorityFingerprint = source.authorityFingerprint;
    _profileAuthorityChanges = source.profileAuthorityChanges
      ?..addListener(_handleAuthorityChange);
    _authAuthoritySubscription = source.authAuthorityChanges?.listen(
      (_) => _handleAuthorityChange(clearCredentialMetadataImmediately: true),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _profileAuthorityChanges?.removeListener(_handleAuthorityChange);
    unawaited(_authAuthoritySubscription?.cancel());
    final revealController = _credentialRevealController;
    revealController?.removeListener(_handleCredentialRevealChange);
    revealController?.clear();
    if (_ownsCredentialRevealController) revealController?.dispose();
    super.dispose();
  }

  void _handleCredentialRevealChange() {
    if (mounted) setState(() {});
  }

  void _handleAuthorityChange({
    bool clearCredentialMetadataImmediately = false,
  }) {
    if (!mounted) return;
    _credentialRevealController?.clear();
    final fingerprint = _source.authorityFingerprint;
    if (!clearCredentialMetadataImmediately &&
        fingerprint == _authorityFingerprint) {
      return;
    }
    _authorityFingerprint = fingerprint;
    setState(() {
      _credentialStatus = null;
      _credentialStatusError = null;
      _credentialRevealErrorTarget = null;
      _credentialRevealErrorMessage = null;
      _credentialAccessDenied = false;
    });
    unawaited(_load());
  }

  Future<void> _load({bool preserveProfile = false}) async {
    _credentialRevealController?.clear();
    final generation = ++_loadGeneration;
    if (!preserveProfile || _profile == null) {
      setState(() {
        _loading = true;
        _loadError = null;
        _credentialStatus = null;
        _credentialStatusError = null;
        _credentialRevealErrorTarget = null;
        _credentialRevealErrorMessage = null;
        _credentialAccessDenied = false;
      });
    } else {
      setState(() {
        _credentialRevealErrorTarget = null;
        _credentialRevealErrorMessage = null;
      });
    }

    try {
      final base = await Future.wait<Object?>([
        _source.getProfile(widget.supplierId),
        _source.getEconomicSummary(widget.supplierId),
        _source.getEconomicTimeline(widget.supplierId),
        // Los contactos no tumban la ficha si fallan: se avisa en su sección.
        _source
            .listContacts(widget.supplierId)
            .then<Object?>((contacts) => contacts)
            .catchError((Object error) => _ContactsLoadFailure(error)),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final profile = base[0] as SupplierProfile?;
      final summaries = base[1] as List<SupplierEconomicSummaryReadModel>;
      final timeline = base[2] as SupplierEconomicTimelinePage;
      final contactsResult = base[3];
      final contacts = contactsResult is List<SupplierContact>
          ? contactsResult
          : const <SupplierContact>[];
      final contactsError =
          contactsResult is _ContactsLoadFailure ? contactsResult.error : null;

      SupplierCredentialStatus? credentialStatus;
      Object? credentialStatusError;
      var credentialAccessDenied = false;
      if (profile != null && _source.canReadCredentialMetadata) {
        try {
          credentialStatus =
              await _source.getCredentialStatus(widget.supplierId);
        } catch (error) {
          if (_isCredentialPermissionError(error)) {
            credentialAccessDenied = true;
          } else {
            credentialStatusError = error;
          }
        }
      } else if (profile?.relationship.hasCredentialReference == true) {
        credentialAccessDenied = true;
      }
      if (!mounted || generation != _loadGeneration) return;

      final recognizedActivities = timeline.timeline.activities
          .where((activity) => activity.isRecognized)
          .toList(growable: false);
      final safeTimeline = SupplierEconomicTimelinePage(
        timeline: SupplierEconomicReadModel(
          tenantId: timeline.timeline.tenantId,
          supplierId: timeline.timeline.supplierId,
          activities: recognizedActivities,
        ),
        offset: timeline.offset,
        limit: timeline.limit,
        hasMore: timeline.hasMore,
      );

      setState(() {
        _profile = profile;
        _contacts = contacts;
        _contactsError = contactsError;
        _economicSummaries = summaries;
        _economicTimeline = safeTimeline;
        _credentialStatus = credentialStatus;
        _credentialStatusError = credentialStatusError;
        _credentialAccessDenied = credentialAccessDenied;
        _loadError = null;
        _loading = false;
        _coerceSelectedSection();
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _coerceSelectedSection() {
    final sections = _sections;
    if (!sections.contains(_selectedSection)) {
      _selectedSection = _SupplierDetailSection.summary;
    }
  }

  bool get _hasRecognizedEconomicActivity {
    final profileCount = _profile?.attentionSignals?.recognizedDocumentCount;
    return (profileCount != null && profileCount > 0) ||
        _economicSummaries.any((summary) => summary.totalDocumentCount > 0) ||
        (_economicTimeline?.timeline.activities.isNotEmpty ?? false);
  }

  bool get _hasAccountingSection {
    final status = _profile?.attentionSignals?.accountingPolicyStatus;
    if (status == SupplierProfileAccountingPolicyStatus.notApplicable) {
      return false;
    }
    if (status == SupplierProfileAccountingPolicyStatus.configured ||
        status == SupplierProfileAccountingPolicyStatus.missingPolicy) {
      return true;
    }
    return _profile?.accounting.policies.isNotEmpty == true;
  }

  bool get _hasAccessSection {
    if (_credentialAccessDenied) {
      return _profile?.relationship.hasCredentialReference == true;
    }
    final status = _credentialStatus;
    if (status != null) {
      return status.hasPortalCredential || status.credentials.isNotEmpty;
    }
    return _profile?.relationship.hasCredentialReference == true;
  }

  bool get _hasRelationshipsSection =>
      (_profile?.engagements.isNotEmpty ?? false) ||
      (_profile?.activeEngagementCount ?? 0) > 0 ||
      _profile?.serviceRelationshipSummary != null;

  List<_SupplierDetailSection> get _sections => [
        _SupplierDetailSection.summary,
        _SupplierDetailSection.contacts,
        _SupplierDetailSection.data,
        if (_hasRecognizedEconomicActivity) _SupplierDetailSection.movements,
        if (_hasAccessSection) _SupplierDetailSection.access,
        if (_hasRelationshipsSection) _SupplierDetailSection.relationships,
        if (_hasAccountingSection) _SupplierDetailSection.accounting,
      ];

  Future<void> _openEditor() async {
    _credentialRevealController?.clear();
    final changed = await context.push<bool>(
      '/purchases/suppliers/${widget.supplierId}/edit',
    );
    if (changed == true && mounted) await _load(preserveProfile: true);
  }

  Future<void> _addContact() => _editContact(null);

  Future<void> _editContact(SupplierContact? contact) async {
    final draft = await showDialog<_SupplierContactDraft>(
      context: context,
      builder: (_) => _SupplierContactEditorDialog(
        contact: contact,
        // El primero que se agrega es la principal: si no, ¿a quién le escribe?
        forcePrimary: contact == null && !_contacts.any((c) => c.isPrimary),
      ),
    );
    if (draft == null || !mounted) return;
    await _runContactCommand(
      () => _source.saveContact(
        SaveSupplierContactCommand(
          operationId: const Uuid().v4(),
          supplierId: widget.supplierId,
          contactId: contact?.id,
          expectedUpdatedAt: contact?.updatedAt,
          name: draft.name,
          role: draft.role,
          phone: draft.phone,
          email: draft.email,
          notes: contact?.notes,
          isPrimary: draft.isPrimary,
        ),
      ),
      success: contact == null ? 'Contacto agregado' : 'Contacto guardado',
    );
  }

  Future<void> _setPrimaryContact(SupplierContact contact) {
    return _runContactCommand(
      () => _source.saveContact(
        SaveSupplierContactCommand(
          operationId: const Uuid().v4(),
          supplierId: widget.supplierId,
          contactId: contact.id,
          expectedUpdatedAt: contact.updatedAt,
          name: contact.name,
          role: contact.role,
          phone: contact.phone,
          email: contact.email,
          notes: contact.notes,
          isPrimary: true,
        ),
      ),
      success: '${contact.name} es ahora el contacto principal',
    );
  }

  Future<void> _setContactActive(SupplierContact contact, bool isActive) {
    return _runContactCommand(
      () => _source.setContactStatus(
        SetSupplierContactStatusCommand(
          operationId: const Uuid().v4(),
          supplierId: widget.supplierId,
          contactId: contact.id,
          expectedUpdatedAt: contact.updatedAt,
          isActive: isActive,
        ),
      ),
      success: isActive
          ? '${contact.name} reactivado'
          : '${contact.name} desactivado. Sus chats se conservan.',
    );
  }

  Future<void> _runContactCommand(
    Future<SupplierContactCommandResult> Function() command, {
    required String success,
  }) async {
    if (_contactCommandRunning) return;
    final messenger = ScaffoldMessenger.of(context);
    final roles = VinabikeThemeRoles.of(context);
    setState(() => _contactCommandRunning = true);
    try {
      await command();
      if (!mounted) return;
      // El vendedor de la ficha es la proyección de la principal: se relee
      // todo el perfil, no sólo la lista.
      await _load(preserveProfile: true);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(success),
          backgroundColor: roles.success.accent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_contactErrorMessage(error)),
          backgroundColor: roles.danger.accent,
        ),
      );
    } finally {
      if (mounted) setState(() => _contactCommandRunning = false);
    }
  }

  String _contactErrorMessage(Object error) {
    if (error is PostgrestException) {
      return switch (error.code) {
        '23505' => 'Otro contacto de este proveedor ya tiene ese número.',
        '40001' => 'El contacto cambió mientras editabas. Vuelve a intentarlo.',
        '42501' => 'No tienes permiso para editar contactos.',
        _ => error.message.isEmpty
            ? 'No se pudo guardar el contacto.'
            : error.message,
      };
    }
    return 'No se pudo guardar el contacto: $error';
  }

  Future<void> _messageContact(SupplierContact contact) async {
    final phone = contact.phone;
    if (phone == null || phone.trim().isEmpty) return;
    final provider = context.read<ChatProvider>();
    final toolbar = context.read<RightToolbarService>();
    final messenger = ScaffoldMessenger.of(context);
    final roles = VinabikeThemeRoles.of(context);
    try {
      await provider.openWhatsAppCustomerChat(
        phoneNumber: phone,
        contactName: _profile?.party.displayName ?? contact.name,
        contextType: 'supplier',
        contextId: widget.supplierId,
      );
      if (!mounted) return;
      final conversationId = provider.activeConversationId;
      if (conversationId != null) {
        toolbar.openConversation(
          tool: ToolbarTool.supplierMessages,
          conversationId: conversationId,
        );
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir el chat: $error'),
          backgroundColor: roles.danger.accent,
        ),
      );
    }
  }

  /// Sube una imagen elegida en el equipo y la deja como logo del proveedor.
  /// Va al bucket público de activos, en la carpeta del tenant y del
  /// proveedor; la fila sólo guarda la URL.
  Future<void> _changeImage() async {
    if (_imageCommandRunning) return;
    final profile = _profile;
    if (profile == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty || !mounted) return;
    setState(() => _imageCommandRunning = true);
    try {
      final url = await ImageService.uploadBytes(
        bytes: bytes,
        fileName: file.name,
        bucket: 'vinabike-assets',
        folder:
            'suppliers/${profile.relationship.tenantId}/${widget.supplierId}',
      );
      if (url == null) {
        throw StateError('La imagen no se pudo subir.');
      }
      await _source.updateImage(widget.supplierId, url);
      if (!mounted) return;
      await _load(preserveProfile: true);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Imagen del proveedor actualizada'),
          backgroundColor: roles.success.accent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar la imagen: $error'),
          backgroundColor: roles.danger.accent,
        ),
      );
    } finally {
      if (mounted) setState(() => _imageCommandRunning = false);
    }
  }

  Future<void> _removeImage() async {
    if (_imageCommandRunning) return;
    final messenger = ScaffoldMessenger.of(context);
    final roles = VinabikeThemeRoles.of(context);
    setState(() => _imageCommandRunning = true);
    try {
      await _source.updateImage(widget.supplierId, null);
      if (!mounted) return;
      await _load(preserveProfile: true);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo quitar la imagen: $error'),
          backgroundColor: roles.danger.accent,
        ),
      );
    } finally {
      if (mounted) setState(() => _imageCommandRunning = false);
    }
  }

  void _openWebsite(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    final target =
        normalized.contains('://') ? normalized : 'https://$normalized';
    context.read<WorkspaceManager>().openBrowserWorkspace(target);
  }

  void _close() {
    _credentialRevealController?.clear();
    ReturnNavigation.close(
      context,
      fallbackRoute: '/purchases/suppliers',
    );
  }

  void _selectSection(_SupplierDetailSection section) {
    if (section != _SupplierDetailSection.access) {
      _credentialRevealController?.clear();
    }
    setState(() {
      _credentialRevealErrorTarget = null;
      _credentialRevealErrorMessage = null;
      _selectedSection = section;
    });
  }

  Future<void> _revealCredential(SupplierCredentialMetadata metadata) async {
    final controller = _credentialRevealController;
    if (controller == null ||
        !_source.canReadCredentialMetadata ||
        !metadata.secretAvailable) {
      return;
    }
    final target = SupplierCredentialRevealTarget(
      supplierId: metadata.supplierId,
      kind: metadata.kind,
      credentialKey: metadata.credentialKey,
    );
    final targetKey = _credentialTargetKey(target);
    setState(() {
      _credentialRevealErrorTarget = null;
      _credentialRevealErrorMessage = null;
    });
    try {
      final revealed = await controller.reveal(target);
      if (!mounted) return;
      if (!revealed) {
        setState(() {
          _credentialRevealErrorTarget = targetKey;
          _credentialRevealErrorMessage =
              'La clave ya no está disponible. Recarga los accesos e inténtalo de nuevo.';
        });
        return;
      }
      if (!_sameCredentialMetadataBinding(controller.metadata, metadata)) {
        controller.hide();
        setState(() {
          _credentialRevealErrorTarget = targetKey;
          _credentialRevealErrorMessage =
              'Este acceso cambió mientras lo abrías. Recarga antes de volver a intentarlo.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      controller.hide();
      if (error is SupplierCredentialAccessDenied ||
          _isCredentialPermissionError(error)) {
        setState(() {
          _credentialStatus = null;
          _credentialAccessDenied = true;
          _credentialRevealErrorTarget = null;
          _credentialRevealErrorMessage = null;
        });
      } else {
        setState(() {
          _credentialRevealErrorTarget = targetKey;
          _credentialRevealErrorMessage =
              'No pudimos abrir esta clave. El resto del perfil sigue disponible.';
        });
      }
    }
  }

  void _hideCredential() {
    _credentialRevealController?.hide();
    if (!mounted) return;
    setState(() {
      _credentialRevealErrorTarget = null;
      _credentialRevealErrorMessage = null;
    });
  }

  Future<void> _copyCredential(
    SupplierCredentialMetadata metadata,
  ) async {
    final controller = _credentialRevealController;
    if (controller == null ||
        !controller.isVisible ||
        !_sameCredentialMetadataBinding(controller.metadata, metadata)) {
      return;
    }
    final secret = controller.revealedSecret;
    if (secret == null || secret.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: secret));
  }

  SupplierContact? get _primaryContact {
    for (final contact in _contacts) {
      if (contact.isPrimary && contact.isActive) return contact;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final surface = _buildSurface(context);
    if (!widget.includeWorkspaceShell) {
      return Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: surface,
      );
    }
    return MainLayout(
      title: 'Proveedores',
      child: surface,
    );
  }

  Widget _buildSurface(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: switch ((_loading, _loadError, _profile)) {
        (true, _, null) => const Center(
            child: BrandedLoading(
              size: 64,
              message: 'Cargando proveedor…',
            ),
          ),
        (false, final Object error, null) => _SupplierDetailError(
            error: error,
            onRetry: _load,
            onClose: _close,
          ),
        (false, null, null) => _SupplierDetailNotFound(
            onClose: _close,
          ),
        _ => LayoutBuilder(
            builder: (context, constraints) => _buildProfile(
              context,
              compact: constraints.maxWidth < 900,
            ),
          ),
      },
    );
  }

  Widget _buildProfile(BuildContext context, {required bool compact}) {
    final profile = _profile!;
    final sections = _sections;
    final selectedIndex = sections.indexOf(_selectedSection);
    final stage =
        compact ? _SupplierMetrics.spacing10 : PurchaseMetrics.stagePadding;
    return SingleChildScrollView(
      key: const PageStorageKey('supplier-detail-scroll'),
      padding: EdgeInsets.fromLTRB(
        stage,
        stage,
        stage,
        _SupplierMetrics.spacing24,
      ),
      child: _SupplierSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SupplierProfileHeader(
              profile: profile,
              primaryContact: _primaryContact,
              compact: compact,
              imageBusy: _imageCommandRunning,
              onBack: _close,
              onEdit: _openEditor,
              onMessage: _messageContact,
              onChangeImage: _changeImage,
              onRemoveImage: _removeImage,
              onOpenWebsite: _openWebsite,
            ),
            if (compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: VbShortSelect<_SupplierDetailSection>(
                  key: const ValueKey('supplier-detail-section-select'),
                  value: _selectedSection,
                  options: sections
                      .map(
                        (section) => VbShortSelectOption(
                          value: section,
                          label: section.label,
                        ),
                      )
                      .toList(growable: false),
                  label: 'Sección · ${selectedIndex + 1} de ${sections.length}',
                  semanticLabel:
                      'Sección ${selectedIndex + 1} de ${sections.length}',
                  sheetTitle: 'Ir a una sección',
                  onChanged: _selectSection,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _SupplierMetrics.spacing18,
                ),
                child: VbSubTabs<_SupplierDetailSection>(
                  tabs: [
                    for (final section in sections)
                      VbSubTab(value: section, label: section.label),
                  ],
                  value: _selectedSection,
                  onChanged: _selectSection,
                ),
              ),
            const _SupplierHairline(),
            _buildSelectedSection(context, compact: compact),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedSection(BuildContext context, {required bool compact}) {
    return KeyedSubtree(
      key: ValueKey('supplier-section-${_selectedSection.name}'),
      child: switch (_selectedSection) {
        _SupplierDetailSection.summary => _SupplierSummarySection(
            profile: _profile!,
            summaries: _economicSummaries,
            timeline: _economicTimeline!,
            credentialStatus: _credentialStatus,
            primaryContact: _primaryContact,
            contactsError: _contactsError,
            showEconomicActivity: _hasRecognizedEconomicActivity,
            compact: compact,
            onMessage: _messageContact,
            onAddContact: _addContact,
            onOpenSection: _selectSection,
            onOpenWebsite: _openWebsite,
          ),
        _SupplierDetailSection.contacts => _SupplierContactsSection(
            contacts: _contacts,
            loadError: _contactsError,
            busy: _contactCommandRunning,
            compact: compact,
            onAdd: _addContact,
            onEdit: _editContact,
            onSetPrimary: _setPrimaryContact,
            onSetActive: _setContactActive,
            onMessage: _messageContact,
            onRetry: () => _load(preserveProfile: true),
          ),
        _SupplierDetailSection.data => _SupplierDataSection(
            profile: _profile!,
            onOpenWebsite: _openWebsite,
          ),
        _SupplierDetailSection.relationships =>
          _SupplierRelationshipsSection(profile: _profile!),
        _SupplierDetailSection.accounting =>
          _SupplierAccountingSection(profile: _profile!),
        _SupplierDetailSection.access => _SupplierAccessSection(
            profile: _profile!,
            status: _credentialStatus,
            accessDenied: _credentialAccessDenied,
            loadError: _credentialStatusError,
            revealController: _credentialRevealController,
            canReveal: _source.canReadCredentialMetadata &&
                !_credentialAccessDenied &&
                _credentialStatusError == null,
            revealErrorTarget: _credentialRevealErrorTarget,
            revealErrorMessage: _credentialRevealErrorMessage,
            onReveal: _revealCredential,
            onCopy: _copyCredential,
            onHide: _hideCredential,
            onRetry: () => _load(preserveProfile: true),
          ),
        _SupplierDetailSection.movements => _SupplierMovementsSection(
            summaries: _economicSummaries,
            timeline: _economicTimeline!,
            compact: compact,
          ),
      },
    );
  }
}

bool _isCredentialPermissionError(Object error) {
  return error is SupplierCredentialAccessDenied ||
      (error is PostgrestException && error.code == '42501');
}

String _credentialTargetKey(SupplierCredentialRevealTarget target) =>
    '${target.supplierId}|${target.kind.dbValue}|${target.credentialKey}';

bool _sameCredentialMetadataBinding(
  SupplierCredentialMetadata? current,
  SupplierCredentialMetadata expected,
) {
  final currentVersion = current?.updatedAt?.toUtc();
  final expectedVersion = expected.updatedAt?.toUtc();
  return current != null &&
      current.tenantId == expected.tenantId &&
      current.supplierId == expected.supplierId &&
      current.kind == expected.kind &&
      current.credentialKey == expected.credentialKey &&
      current.engagementId == expected.engagementId &&
      current.originUrl == expected.originUrl &&
      current.secretAvailable == expected.secretAvailable &&
      currentVersion != null &&
      expectedVersion != null &&
      currentVersion.isAtSameMomentAs(expectedVersion);
}

// -----------------------------------------------------------------------------
// Gramática visual
//
// Cada número está leído de `GUÍA GENERAL Viñabike - Componentes` (proyecto
// `a0fa3196-6315-4b96-bde7-7cc801e7a74e`); el bloque que lo publica va en el
// comentario. Los colores nunca se escriben: se toman de [PurchaseTokens].

abstract final class _SupplierMetrics {
  /// `F-04` escala.
  static const double spacing4 = 4;
  static const double spacing6 = 6;
  static const double spacing8 = 8;
  static const double spacing10 = 10;
  static const double spacing12 = 12;
  static const double spacing14 = 14;
  static const double spacing16 = 16;
  static const double spacing18 = 18;
  static const double spacing24 = 24;

  /// Portada del perfil: el alto del bloque del shell (`F-01`: «el bloque de
  /// 84 px del shell»), la única banda de cabecera que la guía publica. Es la
  /// misma en compacto: con 42 el avatar montado tapaba el botón de volver.
  static const double coverHeight = 84;

  /// Avatar del registro: `image_contract` · inspector 76, radio 8. La mitad
  /// monta sobre la portada.
  static const double avatar = PurchaseMetrics.mediaInspector;
  static const double avatarRadius = PurchaseMetrics.mediaRadius;
  static const double avatarCompact = PurchaseMetrics.mediaStockPhoneCard;

  /// Avatar de persona: `image_contract` · fila de tabla 38.
  static const double personAvatar = PurchaseMetrics.mediaTableRow;

  /// Cuerpo de la hoja: `padding:16px 18px` del panel canónico.
  static const EdgeInsets bodyPadding = EdgeInsets.fromLTRB(18, 16, 18, 16);

  /// Columna lateral del Resumen: `T-05` pane 212–320; se toma el máximo.
  static const double asideWidth = 320;

  /// Fila rótulo-valor (F-02): rótulo 190, `gap:12`, `padding:9px 0`.
  static const double kvLabelWidth = 190;
  static const double kvGap = 12;
  static const EdgeInsets kvPadding = EdgeInsets.symmetric(vertical: 9);

  /// `T-01` · header 30 sobre sunken con borde fuerte; fila 48 con hairline;
  /// identidad `padding-left:16`; celdas `padding:0 10px`.
  static const double tableHeaderHeight = 30;
  static const double tableRowHeight = 48;
  static const double tableEdgePadding = 16;
  static const double tableCellPadding = 10;

  /// `A-01` · alto 38 (48 touch), `padding-h 16`, radio 8, icono 15 gap 7.
  static const double buttonHeight = 38;
  static const double buttonHeightTouch = 48;
  static const double buttonPaddingH = 16;
  static const double buttonRadius = 8;
  static const double buttonIcon = 15;
  static const double buttonIconGap = 7;

  /// Nota dentro de la hoja: `padding:11px 12px; radius 8; sunken + border`.
  static const EdgeInsets notePadding = EdgeInsets.fromLTRB(12, 11, 12, 11);
  static const double noteRadius = 8;

  /// Cuántos movimientos muestra el Resumen antes de mandar a la pestaña.
  static const int recentMovements = 5;
}

/// `F-02 Tipografía` con los colores de rol. Poppins titula, Plex Sans lee,
/// Plex Mono cuenta.
class _SupplierType {
  _SupplierType(PurchaseTokens tokens)
      : recordTitle = GoogleFonts.poppins(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: tokens.ink,
        ),
        // Cabecera de panel del ejemplo canónico: `600 14.5px Poppins`.
        panelTitle = GoogleFonts.poppins(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: tokens.ink,
        ),
        sectionTitle = GoogleFonts.ibmPlexSans(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: tokens.ink,
        ),
        body = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: tokens.ink,
        ),
        bodyMuted = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: tokens.inkMuted,
        ),
        bodyStrong = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.45,
          color: tokens.ink,
        ),
        link = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.45,
          color: tokens.act,
        ),
        label = GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: tokens.inkMuted,
        ),
        // Ayuda al pie: `400 11px/1.5 Plex Sans` inkMuted.
        note = GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: tokens.inkMuted,
        ),
        overline = GoogleFonts.ibmPlexMono(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: tokens.inkFaint,
        ),
        // Meta `500 10.5px Plex Mono` inkFaint.
        meta = GoogleFonts.ibmPlexMono(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: tokens.inkFaint,
        ),
        mono = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: tokens.ink,
        ).copyWith(fontFeatures: PurchaseType.tabular),
        monoMuted = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: tokens.inkMuted,
        ).copyWith(fontFeatures: PurchaseType.tabular),
        monoLink = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: tokens.act,
        ).copyWith(fontFeatures: PurchaseType.tabular),
        // F-02 · numCard 19 mono 700; numRow 14 mono 700.
        numCard = GoogleFonts.ibmPlexMono(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: tokens.ink,
        ).copyWith(fontFeatures: PurchaseType.tabular),
        numRow = GoogleFonts.ibmPlexMono(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: tokens.ink,
        ).copyWith(fontFeatures: PurchaseType.tabular),
        // Monograma: metricMedium (15 mono 700) y metricSmall (13) de la
        // escala publicada.
        monogram = GoogleFonts.ibmPlexMono(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        monogramSmall = GoogleFonts.ibmPlexMono(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        // A-01 · label `12/600 Plex Sans`.
        button = GoogleFonts.ibmPlexSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        );

  final TextStyle recordTitle;
  final TextStyle panelTitle;
  final TextStyle sectionTitle;
  final TextStyle body;
  final TextStyle bodyMuted;
  final TextStyle bodyStrong;
  final TextStyle link;
  final TextStyle label;
  final TextStyle note;
  final TextStyle overline;
  final TextStyle meta;
  final TextStyle mono;
  final TextStyle monoMuted;
  final TextStyle monoLink;
  final TextStyle numCard;
  final TextStyle numRow;
  final TextStyle monogram;
  final TextStyle monogramSmall;
  final TextStyle button;
}

/// La hoja del perfil: una sola superficie con borde 1 px, radio 10 y sombra
/// `raised` (`F-05`). Todo lo demás vive adentro.
class _SupplierSheet extends StatelessWidget {
  const _SupplierSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(PurchaseMetrics.panelRadius),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow.withValues(alpha: .06),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Separador de 1 px dentro de la hoja.
class _SupplierHairline extends StatelessWidget {
  const _SupplierHairline({this.strong = false});

  final bool strong;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Divider(
      height: 1,
      thickness: 1,
      color: strong ? tokens.border : tokens.hair,
    );
  }
}

/// Un grupo dentro de la hoja: título Poppins 14.5 con meta mono y acción a
/// la derecha, y el contenido debajo. Sin caja: la hoja es el contenedor.
class _SupplierGroup extends StatelessWidget {
  const _SupplierGroup({
    required this.title,
    required this.child,
    this.meta,
    this.trailing,
    this.small = false,
  });

  final String title;
  final String? meta;
  final Widget? trailing;
  final Widget child;

  /// Título de la columna lateral: `sectionTitle` en vez de Poppins.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final type = _SupplierType(PurchaseTokens.of(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: _SupplierMetrics.spacing10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    style: small ? type.sectionTitle : type.panelTitle,
                  ),
                  if (meta != null) Text(meta!, style: type.meta),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: _SupplierMetrics.spacing10),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: _SupplierMetrics.spacing10),
        child,
      ],
    );
  }
}

/// Rótulo de bloque en versalitas mono; se publica en mayúsculas para que la
/// semántica y las pruebas lean lo que se ve.
class _SupplierOverline extends StatelessWidget {
  const _SupplierOverline(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final type = _SupplierType(PurchaseTokens.of(context));
    return Text(label.toUpperCase(), style: type.overline);
  }
}

/// Fila rótulo-valor (ejemplo canónico de F-02): rótulo en 190 a la
/// izquierda, valor flexible, `padding:9px 0`, hairline entre filas. `mono`
/// para RUT, teléfonos, URLs y referencias; `onTap` la vuelve enlace.
/// `stacked` apila el rótulo sobre el valor (columna lateral y compacto).
class _SupplierKvRow extends StatelessWidget {
  const _SupplierKvRow({
    required this.label,
    required this.value,
    this.first = false,
    this.mono = false,
    this.stacked,
    this.onTap,
  });

  final String label;
  final String value;
  final bool first;
  final bool mono;
  final bool? stacked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    final style = onTap != null
        ? (mono ? type.monoLink : type.link)
        : (mono ? type.mono : type.body);
    final valueText = Text(value, style: style);
    final valueWidget = onTap == null
        ? valueText
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(_SupplierMetrics.spacing4),
            child: valueText,
          );
    Widget row(bool stack) {
      return Container(
        padding: _SupplierMetrics.kvPadding,
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: tokens.hair)),
        ),
        child: stack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: type.label),
                  const SizedBox(height: PurchaseMetrics.labelGap),
                  valueWidget,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: _SupplierMetrics.kvLabelWidth,
                    child: Text(label, style: type.label),
                  ),
                  const SizedBox(width: _SupplierMetrics.kvGap),
                  Expanded(child: valueWidget),
                ],
              ),
      );
    }

    // Dentro del Resumen la fila vive bajo un IntrinsicHeight, que no admite
    // LayoutBuilder: ahí el caller decide `stacked` y se salta la medición.
    if (stacked case final decided?) return row(decided);
    return LayoutBuilder(
      builder: (context, constraints) => row(constraints.maxWidth < 420),
    );
  }
}

/// Una cifra en línea: overline, número `numCard` y su base. Sin caja: las
/// cifras se separan entre sí con hairlines verticales dentro de la fila.
class _SupplierStat {
  const _SupplierStat({
    required this.label,
    required this.value,
    this.caption,
    this.tone,
  });

  final String label;
  final String value;
  final String? caption;
  final VinabikeSemanticTone? tone;
}

class _SupplierStatRow extends StatelessWidget {
  const _SupplierStatRow({required this.stats, required this.inline});

  final List<_SupplierStat> stats;

  /// En línea con hairlines verticales (escritorio) o en Wrap (compacto). Lo
  /// decide el caller: el Resumen mide la fila con IntrinsicHeight.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    Widget cell(_SupplierStat stat) {
      final zero = _isZeroOrBlank(stat.value);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stat.label.toUpperCase(), style: type.overline),
          const SizedBox(height: _SupplierMetrics.spacing6),
          // `F-03`: un cero real va en inkFaint; el tono sólo tiñe el número.
          Text(
            stat.value,
            style: stat.tone != null
                ? type.numCard.copyWith(color: stat.tone!.accent)
                : (zero
                    ? type.numCard.copyWith(color: tokens.inkFaint)
                    : type.numCard),
            maxLines: 1,
            softWrap: false,
          ),
          if (stat.caption != null) ...[
            const SizedBox(height: _SupplierMetrics.spacing4),
            Text(stat.caption!, style: type.meta),
          ],
        ],
      );
    }

    if (!inline) {
      return Wrap(
        spacing: _SupplierMetrics.spacing24,
        runSpacing: _SupplierMetrics.spacing14,
        children: [for (final stat in stats) cell(stat)],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _SupplierMetrics.spacing18,
                ),
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: tokens.hair,
                ),
              ),
            Expanded(child: cell(stats[i])),
          ],
        ],
      ),
    );
  }
}

bool _isZeroOrBlank(String value) =>
    value == '—' || RegExp(r'^[^0-9]*0(?:[.,]0+)?$').hasMatch(value);

/// Nota dentro de la hoja: caja hundida con borde, texto 11/1.5.
class _SupplierNote extends StatelessWidget {
  const _SupplierNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    return Container(
      padding: _SupplierMetrics.notePadding,
      decoration: BoxDecoration(
        color: tokens.sunken,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(_SupplierMetrics.noteRadius),
      ),
      child: Text(text, style: type.note),
    );
  }
}

/// Avatar del proveedor: su imagen, o un monograma de dos letras sobre el
/// tono de avatar del tema. Radio 8 (`image_contract`).
class _SupplierAvatar extends StatelessWidget {
  const _SupplierAvatar({
    required this.name,
    required this.size,
    this.imageUrl,
    this.person = false,
  });

  final String name;
  final double size;
  final String? imageUrl;

  /// Una persona usa el segundo tono de avatar, para que no se confunda con
  /// la empresa.
  final bool person;

  static String lettersFor(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    return switch (words.length) {
      0 => '?',
      1 => words.first.length >= 2
          ? words.first.substring(0, 2).toUpperCase()
          : words.first.toUpperCase(),
      _ => '${words[0][0]}${words[1][0]}'.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final type = _SupplierType(tokens);
    final background = person ? roles.avatarB : roles.avatarA;
    final foreground = person ? roles.onAvatarB : roles.onAvatarA;
    final url = imageUrl?.trim();
    final radius = BorderRadius.circular(_SupplierMetrics.avatarRadius);
    final letters = Text(
      lettersFor(name),
      style:
          (size >= _SupplierMetrics.avatar ? type.monogram : type.monogramSmall)
              .copyWith(color: foreground),
    );
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: url == null || url.isEmpty
            ? letters
            : Image.network(
                url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => letters,
              ),
      ),
    );
  }
}

/// `A-01` · botón primario: acento del preset, alto 38 (48 touch), radio 8,
/// label 12/600. Uno por superficie.
class _SupplierPrimaryButton extends StatelessWidget {
  const _SupplierPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.touch,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool touch;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final type = _SupplierType(tokens);
    final height = touch
        ? _SupplierMetrics.buttonHeightTouch
        : _SupplierMetrics.buttonHeight;
    final style = FilledButton.styleFrom(
      backgroundColor: tokens.act,
      foregroundColor: tokens.onAct,
      disabledBackgroundColor: roles.neutral.container,
      disabledForegroundColor: tokens.inkDisabled,
      minimumSize: Size(0, height),
      padding: const EdgeInsets.symmetric(
        horizontal: _SupplierMetrics.buttonPaddingH,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_SupplierMetrics.buttonRadius),
      ),
      textStyle: type.button,
    );
    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: _buttonChild(label, icon),
    );
  }
}

/// `A-01` · botón secundario: superficie con borde fuerte, misma geometría.
class _SupplierSecondaryButton extends StatelessWidget {
  const _SupplierSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.touch,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool touch;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    final height = touch
        ? _SupplierMetrics.buttonHeightTouch
        : _SupplierMetrics.buttonHeight;
    final style = OutlinedButton.styleFrom(
      backgroundColor: tokens.surface,
      foregroundColor: tokens.ink,
      disabledForegroundColor: tokens.inkDisabled,
      side: BorderSide(color: tokens.borderStrong),
      minimumSize: Size(expand ? double.infinity : 0, height),
      padding: const EdgeInsets.symmetric(
        horizontal: _SupplierMetrics.buttonPaddingH,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_SupplierMetrics.buttonRadius),
      ),
      textStyle: type.button,
    );
    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: _buttonChild(label, icon),
    );
  }
}

/// El rótulo cede antes que desbordar: un botón expandido en la columna
/// lateral (284 px útiles) recorta con elipsis si la fuente crece.
Widget _buttonChild(String label, IconData? icon) {
  final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
  if (icon == null) return text;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: _SupplierMetrics.buttonIcon),
      const SizedBox(width: _SupplierMetrics.buttonIconGap),
      Flexible(child: text),
    ],
  );
}

/// Acción de texto dentro de la hoja (`600 11` del color de acción).
class _SupplierInlineAction extends StatelessWidget {
  const _SupplierInlineAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      PurchaseInlineAction(label: label, onPressed: onPressed);
}

// -----------------------------------------------------------------------------
// Cabecera del perfil

enum _SupplierHeaderAction { changeImage, removeImage, openWebsite }

/// Portada, avatar montado sobre ella, nombre con estado, línea de identidad
/// y las acciones. Es la primera lectura del registro y no lleva panel: la
/// hoja es el contenedor.
class _SupplierProfileHeader extends StatelessWidget {
  const _SupplierProfileHeader({
    required this.profile,
    required this.primaryContact,
    required this.compact,
    required this.imageBusy,
    required this.onBack,
    required this.onEdit,
    required this.onMessage,
    required this.onChangeImage,
    required this.onRemoveImage,
    required this.onOpenWebsite,
  });

  final SupplierProfile profile;
  final SupplierContact? primaryContact;
  final bool compact;
  final bool imageBusy;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final ValueChanged<SupplierContact> onMessage;
  final VoidCallback onChangeImage;
  final VoidCallback onRemoveImage;
  final ValueChanged<String> onOpenWebsite;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    final party = profile.party;
    final relationship = profile.relationship;
    final identifier = _primaryIdentifier(party);
    final imageUrl = profile.legacyDetails.imageUrl;
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;
    final website = relationship.website?.trim();
    final hasWebsite = website != null && website.isNotEmpty;
    final purposes = relationship.roles
        .map(
          (role) => _relationshipPurposeLabel(
            role.code,
            _classificationLabel(role.label, 'Relación vigente'),
          ),
        )
        .toList(growable: false);
    final contact = primaryContact;
    const coverHeight = _SupplierMetrics.coverHeight;
    final avatarSize =
        compact ? _SupplierMetrics.avatarCompact : _SupplierMetrics.avatar;
    final overlap = avatarSize / 2;

    final cover = Container(
      height: coverHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [tokens.actSoft, tokens.sunken],
        ),
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: TextButton.icon(
        key: const ValueKey('supplier-detail-back'),
        onPressed: onBack,
        icon: const Icon(Icons.chevron_left, size: 18),
        label: const Text('Volver al directorio'),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: tokens.inkMuted,
          textStyle: type.button,
        ),
      ),
    );

    // La mitad del avatar sube sobre la portada: en el layout ocupa la mitad
    // de su alto y el resto se dibuja hacia arriba.
    final avatar = SizedBox(
      width: avatarSize,
      height: overlap,
      child: OverflowBox(
        maxHeight: avatarSize,
        minHeight: avatarSize,
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(
              _SupplierMetrics.avatarRadius + 3,
            ),
          ),
          child: _SupplierAvatar(
            name: party.displayName,
            size: avatarSize - 6,
            imageUrl: imageUrl,
          ),
        ),
      ),
    );

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: _SupplierMetrics.spacing10,
          runSpacing: _SupplierMetrics.spacing4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(party.displayName, style: type.recordTitle),
            VbStatusBadge(
              label: relationship.isActive ? 'Activo' : 'Inactivo',
              tone: relationship.isActive
                  ? VbStatusTone.success
                  : VbStatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: _SupplierMetrics.spacing4),
        Wrap(
          spacing: _SupplierMetrics.spacing8,
          runSpacing: _SupplierMetrics.spacing4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_partyKindLabel(party.kind), style: type.bodyMuted),
            if (identifier != null) ...[
              Text('·', style: type.bodyMuted),
              Text(identifier.value, style: type.monoMuted),
            ],
            for (final purpose in purposes) ...[
              Text('·', style: type.bodyMuted),
              Text(purpose, style: type.bodyMuted),
            ],
            if (hasWebsite) ...[
              Text('·', style: type.bodyMuted),
              InkWell(
                onTap: () => onOpenWebsite(website),
                borderRadius: BorderRadius.circular(_SupplierMetrics.spacing4),
                child: Text(_websiteLabel(website), style: type.link),
              ),
            ],
          ],
        ),
      ],
    );

    final moreMenu = PopupMenuButton<_SupplierHeaderAction>(
      key: const ValueKey('supplier-detail-more'),
      tooltip: 'Más acciones',
      enabled: !imageBusy,
      icon: Icon(Icons.more_horiz, color: tokens.inkMuted),
      onSelected: (action) => switch (action) {
        _SupplierHeaderAction.changeImage => onChangeImage(),
        _SupplierHeaderAction.removeImage => onRemoveImage(),
        _SupplierHeaderAction.openWebsite => onOpenWebsite(website ?? ''),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _SupplierHeaderAction.changeImage,
          child: Text(hasImage ? 'Cambiar imagen…' : 'Agregar imagen…'),
        ),
        if (hasImage)
          const PopupMenuItem(
            value: _SupplierHeaderAction.removeImage,
            child: Text('Quitar imagen'),
          ),
        if (hasWebsite)
          const PopupMenuItem(
            value: _SupplierHeaderAction.openWebsite,
            child: Text('Abrir sitio web'),
          ),
      ],
    );

    final actions = Wrap(
      spacing: _SupplierMetrics.spacing8,
      runSpacing: _SupplierMetrics.spacing8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (contact != null && contact.hasPhone)
          _SupplierPrimaryButton(
            key: const ValueKey('supplier-detail-message'),
            label: 'Escribir a ${_firstName(contact.name)}',
            icon: Icons.chat_bubble_outline,
            touch: compact,
            onPressed: () => onMessage(contact),
          ),
        _SupplierSecondaryButton(
          key: const ValueKey('supplier-detail-edit'),
          label: 'Editar',
          touch: compact,
          onPressed: onEdit,
        ),
        moreMenu,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cover,
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(height: _SupplierMetrics.spacing10),
                    identity,
                    const SizedBox(height: _SupplierMetrics.spacing12),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: _SupplierMetrics.spacing14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: _SupplierMetrics.spacing8,
                        ),
                        child: identity,
                      ),
                    ),
                    const SizedBox(width: _SupplierMetrics.spacing14),
                    Padding(
                      padding: const EdgeInsets.only(
                        top: _SupplierMetrics.spacing8,
                      ),
                      child: actions,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

String _firstName(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  return words.isEmpty ? name.trim() : words.first;
}

String _websiteLabel(String url) {
  final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
  final host = uri?.host ?? url;
  return host.startsWith('www.') ? host.substring(4) : host;
}

String _partyKindLabel(ExternalPartyKind kind) => switch (kind) {
      ExternalPartyKind.organization => 'Organización',
      ExternalPartyKind.person => 'Persona',
      ExternalPartyKind.publicAuthority => 'Organismo público',
      ExternalPartyKind.other => 'Sin especificar',
    };

// -----------------------------------------------------------------------------
// Resumen

/// Columna principal (cifras, últimos movimientos, avisos) y columna lateral
/// hundida (contacto principal, datos de contacto, cuentas, relaciones). En
/// compacto la lateral baja debajo de la principal.
class _SupplierSummarySection extends StatelessWidget {
  const _SupplierSummarySection({
    required this.profile,
    required this.summaries,
    required this.timeline,
    required this.credentialStatus,
    required this.primaryContact,
    required this.contactsError,
    required this.showEconomicActivity,
    required this.compact,
    required this.onMessage,
    required this.onAddContact,
    required this.onOpenSection,
    required this.onOpenWebsite,
  });

  final SupplierProfile profile;
  final List<SupplierEconomicSummaryReadModel> summaries;
  final SupplierEconomicTimelinePage timeline;
  final SupplierCredentialStatus? credentialStatus;
  final SupplierContact? primaryContact;
  final Object? contactsError;
  final bool showEconomicActivity;
  final bool compact;
  final ValueChanged<SupplierContact> onMessage;
  final VoidCallback onAddContact;
  final ValueChanged<_SupplierDetailSection> onOpenSection;
  final ValueChanged<String> onOpenWebsite;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final main = _buildMain(context);
    final aside = _buildAside(context);
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: _SupplierMetrics.bodyPadding, child: main),
          const _SupplierHairline(strong: true),
          Container(
            color: tokens.sunken,
            padding: _SupplierMetrics.bodyPadding,
            child: aside,
          ),
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(padding: _SupplierMetrics.bodyPadding, child: main),
          ),
          VerticalDivider(width: 1, thickness: 1, color: tokens.border),
          Container(
            width: _SupplierMetrics.asideWidth,
            color: tokens.sunken,
            padding: _SupplierMetrics.bodyPadding,
            child: aside,
          ),
        ],
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    final type = _SupplierType(PurchaseTokens.of(context));
    final activeEngagements = profile.engagements
        .where((item) => item.status == SupplierEngagementStatus.active)
        .toList(growable: false);
    final pendingIncidents = profile.attentionSignals?.validationIncidents
            .where(
              (incident) =>
                  incident.status == SupplierValidationIncidentStatus.pending,
            )
            .toList(growable: false) ??
        const <SupplierValidationIncident>[];
    final recent = [...timeline.timeline.activities]
      ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final shown = recent.take(_SupplierMetrics.recentMovements).toList();
    final children = <Widget>[];

    void addBlock(Widget block) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: _SupplierMetrics.spacing18));
        children.add(const _SupplierHairline());
        children.add(const SizedBox(height: _SupplierMetrics.spacing18));
      }
      children.add(block);
    }

    for (final incident in pendingIncidents) {
      children.add(_SupplierIncidentNotice(incident: incident));
      children.add(const SizedBox(height: _SupplierMetrics.spacing12));
    }

    if (showEconomicActivity) {
      for (final summary in summaries) {
        addBlock(
          _SupplierGroup(
            title: 'Compras y pagos',
            meta: summary.currencyCode,
            trailing: _SupplierInlineAction(
              label: 'Ver movimientos',
              onPressed: () => onOpenSection(_SupplierDetailSection.movements),
            ),
            child:
                _SupplierEconomicOverview(summary: summary, compact: compact),
          ),
        );
      }
      if (shown.isNotEmpty) {
        addBlock(
          _SupplierGroup(
            title: 'Últimos movimientos',
            meta: recent.length > shown.length
                ? '${shown.length} de ${recent.length}'
                : null,
            trailing: _SupplierInlineAction(
              label: 'Ver todos',
              onPressed: () => onOpenSection(_SupplierDetailSection.movements),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < shown.length; index++)
                  _SupplierRecentActivityRow(
                    activity: shown[index],
                    first: index == 0,
                  ),
              ],
            ),
          ),
        );
      }
    } else if (_hasFreeCurrentEngagement(activeEngagements)) {
      addBlock(
        const VbNotice(
          title: 'Relación vigente sin cobro',
          body: 'El ciclo de cobro publicado para esta relación es Sin costo.',
          tone: VbNoticeTone.success,
        ),
      );
    } else {
      addBlock(
        _SupplierGroup(
          title: 'Compras y pagos',
          child: Text(
            'Todavía no hay documentos ni pagos registrados con este proveedor.',
            style: type.bodyMuted,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildAside(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    final relationship = profile.relationship;
    final party = profile.party;
    final legacy = profile.legacyDetails;
    final identifier = _primaryIdentifier(party);
    final activeEngagements = profile.engagements
        .where((item) => item.status == SupplierEngagementStatus.active)
        .toList(growable: false);
    final credentials = credentialStatus?.credentials ?? const [];
    final hasStoredSecret = credentials.any(
      (credential) => credential.secretAvailable,
    );
    final address = [
      legacy.address,
      legacy.comuna,
      legacy.city,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ');
    final quick = <_KvSpec>[
      if (identifier != null) _KvSpec('RUT', identifier.value, mono: true),
      if (_present(relationship.phone))
        _KvSpec('Teléfono', relationship.phone!, mono: true),
      if (_present(relationship.email)) _KvSpec('Correo', relationship.email!),
      if (_present(relationship.website))
        _KvSpec(
          'Sitio web',
          _websiteLabel(relationship.website!),
          mono: true,
          onTap: () => onOpenWebsite(relationship.website!),
        ),
      if (address.isNotEmpty) _KvSpec('Dirección', address),
    ];
    final children = <Widget>[];

    void addBlock(Widget block) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: _SupplierMetrics.spacing16));
        children.add(const _SupplierHairline(strong: true));
        children.add(const SizedBox(height: _SupplierMetrics.spacing16));
      }
      children.add(block);
    }

    final contact = primaryContact;
    addBlock(
      _SupplierGroup(
        small: true,
        title: 'Contacto principal',
        trailing: _SupplierInlineAction(
          label: contact == null ? 'Agregar' : 'Ver personas',
          onPressed: contact == null
              ? onAddContact
              : () => onOpenSection(_SupplierDetailSection.contacts),
        ),
        child: contact == null
            ? Text(
                contactsError != null
                    ? 'No pudimos cargar las personas de este proveedor.'
                    : 'Nadie registrado todavía. Agrega a la persona a la que le escribes.',
                style: type.bodyMuted,
              )
            : _SupplierPrimaryContactBody(
                contact: contact,
                compact: compact,
                onMessage: () => onMessage(contact),
              ),
      ),
    );

    if (quick.isNotEmpty) {
      addBlock(
        _SupplierGroup(
          small: true,
          title: 'Datos',
          trailing: _SupplierInlineAction(
            label: 'Ver todo',
            onPressed: () => onOpenSection(_SupplierDetailSection.data),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < quick.length; index++)
                _SupplierKvRow(
                  first: index == 0,
                  stacked: true,
                  label: quick[index].label,
                  value: quick[index].value,
                  mono: quick[index].mono,
                  onTap: quick[index].onTap,
                ),
            ],
          ),
        ),
      );
    }

    if (credentials.isNotEmpty) {
      addBlock(
        _SupplierGroup(
          small: true,
          title: 'Cuentas y portales',
          meta: '${credentials.length}',
          trailing: _SupplierInlineAction(
            label: 'Ver accesos',
            onPressed: () => onOpenSection(_SupplierDetailSection.access),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < credentials.length; index++)
                _SupplierKvRow(
                  first: index == 0,
                  stacked: true,
                  label: credentials[index].label ?? 'Acceso',
                  value: credentials[index].originUrl ??
                      credentials[index].username ??
                      'Cuenta protegida',
                  mono: credentials[index].originUrl != null,
                ),
              const SizedBox(height: _SupplierMetrics.spacing10),
              Text(
                hasStoredSecret
                    ? 'Las claves disponibles se piden aparte, una por una.'
                    : 'Estos accesos conservan la cuenta, pero no tienen una clave guardada.',
                style: type.note,
              ),
            ],
          ),
        ),
      );
    }

    if (activeEngagements.isNotEmpty ||
        profile.serviceRelationshipSummary != null) {
      addBlock(
        _SupplierGroup(
          small: true,
          title: 'Relaciones vigentes',
          trailing: _SupplierInlineAction(
            label: 'Ver detalle',
            onPressed: () =>
                onOpenSection(_SupplierDetailSection.relationships),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (activeEngagements.isNotEmpty)
                for (var index = 0; index < activeEngagements.length; index++)
                  _SupplierKvRow(
                    first: index == 0,
                    stacked: true,
                    label: activeEngagements[index].name,
                    value: _engagementCurrentTerms(activeEngagements[index]),
                  )
              else
                _SupplierKvRow(
                  first: true,
                  stacked: true,
                  label: 'Relación',
                  value: profile.serviceRelationshipSummary!,
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// El contacto principal en la columna lateral: avatar de persona, nombre,
/// cargo, cómo ubicarlo y el botón de WhatsApp.
class _SupplierPrimaryContactBody extends StatelessWidget {
  const _SupplierPrimaryContactBody({
    required this.contact,
    required this.compact,
    required this.onMessage,
  });

  final SupplierContact contact;
  final bool compact;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SupplierAvatar(
              name: contact.name,
              size: _SupplierMetrics.personAvatar,
              person: true,
            ),
            const SizedBox(width: _SupplierMetrics.spacing12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name, style: type.bodyStrong),
                  if (_present(contact.role))
                    Text(contact.role!, style: type.label),
                ],
              ),
            ),
          ],
        ),
        if (contact.hasPhone || _present(contact.email)) ...[
          const SizedBox(height: _SupplierMetrics.spacing10),
          if (contact.hasPhone) Text(contact.phone!, style: type.mono),
          if (_present(contact.email))
            Text(contact.email!, style: type.bodyMuted),
        ],
        if (contact.hasPhone) ...[
          const SizedBox(height: _SupplierMetrics.spacing12),
          _SupplierSecondaryButton(
            label: 'Escribir por WhatsApp',
            icon: Icons.chat_bubble_outline,
            touch: compact,
            expand: true,
            onPressed: onMessage,
          ),
        ],
      ],
    );
  }
}

/// Las cifras de un resumen económico: compras y, aparte, gastos. No se
/// suman entre sí: son dos filas de cifras, y se dice.
class _SupplierEconomicOverview extends StatelessWidget {
  const _SupplierEconomicOverview({
    required this.summary,
    required this.compact,
  });

  final SupplierEconomicSummaryReadModel summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final type = _SupplierType(tokens);
    final currency = summary.currencyCode;
    final coverage = _provenanceLabel(summary);
    final children = <Widget>[];

    void addGroup(String label, SupplierEconomicAmountBreakdown breakdown) {
      if (breakdown.documentCount == 0) return;
      final balance = breakdown.balanceAmount ?? 0;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: _SupplierMetrics.spacing14));
      }
      children.add(Text(label, style: type.bodyStrong));
      children.add(const SizedBox(height: _SupplierMetrics.spacing8));
      children.add(
        _SupplierStatRow(
          inline: !compact,
          stats: [
            _SupplierStat(
              label: 'Registrado',
              value: _money(breakdown.grossAmount, currency),
              caption: _countLabel(
                breakdown.documentCount,
                'documento',
                'documentos',
              ),
            ),
            _SupplierStat(
              label: 'Pagado',
              value: _money(breakdown.paidAmount, currency),
              caption: _countLabel(breakdown.paymentCount, 'pago', 'pagos'),
            ),
            _SupplierStat(
              label: 'Pendiente',
              value: _money(breakdown.balanceAmount, currency),
              caption: balance > 0 ? 'por pagar' : 'al día',
              tone: balance > 0 ? roles.warning : null,
            ),
          ],
        ),
      );
    }

    addGroup('Compras', summary.purchases);
    addGroup('Gastos', summary.expenses);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        if (summary.purchases.documentCount > 0 &&
            summary.expenses.documentCount > 0) ...[
          const SizedBox(height: _SupplierMetrics.spacing8),
          Text('compras y gastos no se suman entre sí', style: type.note),
        ],
        if (coverage != null) ...[
          const SizedBox(height: _SupplierMetrics.spacing12),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _economicStatusColor(context, summary),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: _SupplierMetrics.spacing8),
              Expanded(child: Text(coverage, style: type.note)),
              if (summary.lastActivityAt != null)
                Text(
                  'último ${_formatDate(summary.lastActivityAt!.toLocal())}',
                  style: type.meta,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Un movimiento reciente en el Resumen: fecha en mono, qué fue, referencia
/// y el monto a la derecha.
class _SupplierRecentActivityRow extends StatelessWidget {
  const _SupplierRecentActivityRow({
    required this.activity,
    required this.first,
  });

  final SupplierEconomicActivity activity;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    final amount =
        activity.grossAmount != 0 ? activity.grossAmount : activity.paidAmount;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(vertical: _SupplierMetrics.spacing8),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        children: [
          Text(_formatDate(activity.occurredAt), style: type.monoMuted),
          const SizedBox(width: _SupplierMetrics.spacing12),
          Expanded(
            child: Text(
              _present(activity.documentNumber)
                  ? '${_economicActivityLabel(activity.kind)} · ${activity.documentNumber}'
                  : _economicActivityLabel(activity.kind),
              style: type.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: _SupplierMetrics.spacing12),
          Text(_money(amount, activity.currencyCode), style: type.numRow),
        ],
      ),
    );
  }
}

class _SupplierIncidentNotice extends StatelessWidget {
  const _SupplierIncidentNotice({required this.incident});

  final SupplierValidationIncident incident;

  @override
  Widget build(BuildContext context) {
    final tone = switch (incident.severity) {
      SupplierValidationIncidentSeverity.error => VbNoticeTone.danger,
      SupplierValidationIncidentSeverity.warning => VbNoticeTone.warning,
      SupplierValidationIncidentSeverity.info => VbNoticeTone.info,
      SupplierValidationIncidentSeverity.unknown => VbNoticeTone.neutral,
    };
    return VbNotice(
      title: incident.displayReason,
      tone: tone,
    );
  }
}

String _engagementCurrentTerms(SupplierEngagement engagement) {
  final version = engagement.currentVersion;
  if (version == null) return _engagementStatusLabel(engagement.status);
  final parts = <String>[_billingCadenceLabel(version.billingCadence)];
  if (version.dueDay != null) parts.add('vence el ${version.dueDay}');
  return parts.join(' · ');
}

bool _hasFreeCurrentEngagement(List<SupplierEngagement> engagements) =>
    engagements.any((engagement) => engagement.currentVersion?.isFree == true);

String _billingCadenceLabel(String value) => switch (value) {
      'free' => 'Sin costo',
      'monthly' => 'Mensual',
      'bimonthly' => 'Bimensual',
      'quarterly' => 'Trimestral',
      'semiannual' => 'Semestral',
      'annual' => 'Anual',
      'irregular' => 'Cobro irregular',
      _ => 'Condición vigente',
    };

String _engagementStatusLabel(SupplierEngagementStatus value) =>
    switch (value) {
      SupplierEngagementStatus.draft => 'Borrador',
      SupplierEngagementStatus.active => 'Rige hoy',
      SupplierEngagementStatus.suspended => 'Suspendida',
      SupplierEngagementStatus.ended => 'Finalizada',
    };

String _countLabel(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

String? _provenanceLabel(SupplierEconomicSummaryReadModel summary) {
  return switch (summary.provenanceStatus) {
    'complete' =>
      'Cobertura completa · ${summary.tracedDocumentCount} movimientos trazables',
    'partial' =>
      'Cobertura parcial · ${summary.tracedDocumentCount} movimientos trazables',
    'none' => 'Cobertura pendiente de trazabilidad',
    'not_applicable' => null,
    _ => null,
  };
}

Color _economicStatusColor(
  BuildContext context,
  SupplierEconomicSummaryReadModel summary,
) {
  final roles = VinabikeThemeRoles.of(context);
  return switch (summary.provenanceStatus) {
    'complete' => roles.success.accent,
    'partial' => roles.warning.accent,
    _ => roles.neutral.accent,
  };
}

/// `F-03`: CLP con `VbMoneyText.formatClp`; otra moneda con su código. `null`
/// es «no aplica» y se dice con la raya.
String _money(double? amount, String currencyCode) =>
    PurchaseMoney.format(amount, currencyCode);

// -----------------------------------------------------------------------------
// Datos

/// Identidad legal, cómo ubicar a la empresa y para qué la usamos: grupos con
/// filas rótulo-valor, separados por hairlines dentro de la hoja.
class _SupplierDataSection extends StatelessWidget {
  const _SupplierDataSection({
    required this.profile,
    required this.onOpenWebsite,
  });

  final SupplierProfile profile;
  final ValueChanged<String> onOpenWebsite;

  @override
  Widget build(BuildContext context) {
    final type = _SupplierType(PurchaseTokens.of(context));
    final party = profile.party;
    final relationship = profile.relationship;
    final legacy = profile.legacyDetails;
    final identifier = _primaryIdentifier(party);
    final address = [
      legacy.address,
      legacy.comuna,
      legacy.city,
      legacy.region,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ');

    final identity = <_KvSpec>[
      _KvSpec('Nombre visible', party.displayName),
      if (_present(party.legalName)) _KvSpec('Razón social', party.legalName!),
      if (_present(party.tradeName))
        _KvSpec('Nombre comercial', party.tradeName!),
      _KvSpec('Tipo de entidad', _partyKindLabel(party.kind)),
      if (identifier != null)
        _KvSpec('Identificador tributario', identifier.value, mono: true),
      if (_present(party.countryCode)) _KvSpec('País', party.countryCode!),
    ];
    final reach = <_KvSpec>[
      if (_present(relationship.contactPerson))
        _KvSpec('Contacto', relationship.contactPerson!),
      if (_present(relationship.email)) _KvSpec('Correo', relationship.email!),
      if (_present(relationship.phone))
        _KvSpec('Teléfono', relationship.phone!, mono: true),
      if (_present(relationship.website))
        _KvSpec(
          'Sitio web',
          relationship.website!,
          mono: true,
          onTap: () => onOpenWebsite(relationship.website!),
        ),
      if (address.isNotEmpty) _KvSpec('Dirección', address),
    ];

    return _SupplierSectionBody(
      groups: [
        _SupplierKvGroup(title: 'Identidad', rows: identity),
        if (reach.isNotEmpty)
          _SupplierKvGroup(title: 'Cómo ubicarlos', rows: reach),
        _SupplierClassificationGroup(profile: profile),
        if (_present(relationship.notes))
          _SupplierGroup(
            title: 'Notas',
            child: Text(relationship.notes!, style: type.body),
          ),
      ],
    );
  }
}

/// Cuerpo de una pestaña: grupos apilados con hairline entre ellos, dentro
/// del padding de la hoja.
class _SupplierSectionBody extends StatelessWidget {
  const _SupplierSectionBody({required this.groups});

  final List<Widget> groups;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _SupplierMetrics.bodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < groups.length; index++) ...[
            if (index > 0) ...[
              const SizedBox(height: _SupplierMetrics.spacing18),
              const _SupplierHairline(),
              const SizedBox(height: _SupplierMetrics.spacing18),
            ],
            groups[index],
          ],
        ],
      ),
    );
  }
}

class _KvSpec {
  const _KvSpec(this.label, this.value, {this.mono = false, this.onTap});

  final String label;
  final String value;
  final bool mono;
  final VoidCallback? onTap;
}

/// Un grupo con título y filas rótulo-valor.
class _SupplierKvGroup extends StatelessWidget {
  const _SupplierKvGroup({
    required this.title,
    required this.rows,
    this.trailing,
    this.footer,
  });

  final String title;
  final Widget? trailing;
  final List<_KvSpec> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return _SupplierGroup(
      title: title,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++)
            _SupplierKvRow(
              first: index == 0,
              label: rows[index].label,
              value: rows[index].value,
              mono: rows[index].mono,
              onTap: rows[index].onTap,
            ),
          if (footer != null) ...[
            const SizedBox(height: _SupplierMetrics.spacing10),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// «Para qué lo usamos»: la clasificación como una sola relación operativa.
class _SupplierClassificationGroup extends StatelessWidget {
  const _SupplierClassificationGroup({required this.profile});

  final SupplierProfile profile;

  @override
  Widget build(BuildContext context) {
    final relationship = profile.relationship;
    final signal = profile.attentionSignals?.classificationStatus;
    final purposes = relationship.roles
        .map(
          (role) => _relationshipPurposeLabel(
            role.code,
            _classificationLabel(role.label, 'Relación vigente'),
          ),
        )
        .toList(growable: false);
    final details = relationship.capabilities
        .map(
          (capability) => _relationshipDetailLabel(
            capability.code,
            _classificationLabel(capability.label, 'Detalle vigente'),
          ),
        )
        .toList(growable: false);
    final internalTags = relationship.tags
        .where((tag) => !_systemRelationshipTagCodes.contains(tag.code))
        .map((tag) => _classificationLabel(tag.label, 'Etiqueta interna'))
        .toList(growable: false);
    final rows = <_KvSpec>[
      if (purposes.isNotEmpty) _KvSpec('Relación', purposes.join(' · ')),
      if (details.isNotEmpty)
        _KvSpec('Detalles operativos', details.join(' · ')),
      if (internalTags.isNotEmpty)
        _KvSpec('Organización interna', internalTags.join(' · ')),
    ];
    final notice = switch (signal) {
      SupplierProfileClassificationStatus.unclassified => const VbNotice(
          title: 'Clasificación pendiente',
          body:
              'El servidor publicó este proveedor como pendiente de clasificar.',
          tone: VbNoticeTone.warning,
        ),
      SupplierProfileClassificationStatus.notApplicable when rows.isEmpty =>
        const VbNotice(
          title: 'Clasificación no aplicable',
          tone: VbNoticeTone.neutral,
        ),
      _ => null,
    };
    return _SupplierKvGroup(
      title: 'Para qué lo usamos',
      rows: rows,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice != null) ...[
            notice,
            const SizedBox(height: _SupplierMetrics.spacing10),
          ],
          const _SupplierNote(
            'Define dónde aparece este proveedor y qué se puede configurar. No contabiliza ni automatiza por sí sola; la naturaleza de cada compra la fija su criterio contable.',
          ),
        ],
      ),
    );
  }
}

const _systemRelationshipTagCodes = <String>{
  'digital',
  'transport',
  'government',
  'facility',
  'recurring',
  'essential_service',
};

String _relationshipPurposeLabel(String code, String fallback) =>
    switch (code) {
      'goods_vendor' => 'Bienes y repuestos',
      'service_provider' => 'Servicios',
      'digital_platform' => 'Servicios digitales',
      'logistics_provider' => 'Transporte y logística',
      'utility_provider' => 'Servicios básicos',
      'landlord' => 'Arrendamiento',
      'government_authority' => 'Impuestos y obligaciones públicas',
      'operational_resource' => 'Recurso o portal operativo',
      _ => fallback,
    };

String _relationshipDetailLabel(String code, String fallback) => switch (code) {
      'inventory_goods' => 'Inventario y reventa',
      'workshop_consumables' => 'Insumos de taller',
      'freight_transport' => 'Flete o despacho',
      'digital_services' => 'Software, dominio, red o publicidad',
      'utilities' => 'Luz, agua u otro suministro',
      'rent_lease' => 'Arriendo de local, inmueble o activo',
      'tax_payments' => 'Impuestos, tasas o permisos',
      'credential_portal' => 'Acceso, enlace o cuenta operativa',
      'purchase_invoices' => 'Documentos de compra',
      _ => fallback,
    };

ExternalPartyIdentifier? _primaryIdentifier(ExternalParty party) {
  for (final identifier in party.identifiers) {
    if (identifier.isPrimary) return identifier;
  }
  return party.identifiers.isEmpty ? null : party.identifiers.first;
}

bool _present(String? value) => value?.trim().isNotEmpty == true;

String _classificationLabel(String? publishedLabel, String fallback) {
  final value = publishedLabel?.trim();
  return value == null || value.isEmpty ? fallback : value;
}

// -----------------------------------------------------------------------------
// Relaciones

class _SupplierRelationshipsSection extends StatelessWidget {
  const _SupplierRelationshipsSection({required this.profile});

  final SupplierProfile profile;

  @override
  Widget build(BuildContext context) {
    final engagements = [...profile.engagements]..sort((left, right) {
        final activeOrder = _engagementStatusOrder(left.status)
            .compareTo(_engagementStatusOrder(right.status));
        if (activeOrder != 0) return activeOrder;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
    return _SupplierSectionBody(
      groups: [
        if (engagements.isEmpty && profile.serviceRelationshipSummary != null)
          _SupplierKvGroup(
            title: 'Relación',
            rows: [_KvSpec('Vigente', profile.serviceRelationshipSummary!)],
          ),
        for (final engagement in engagements)
          _SupplierEngagementGroup(
            engagement: engagement,
            site: _siteFor(profile.sites, engagement.businessSiteId),
          ),
      ],
    );
  }
}

class _SupplierEngagementGroup extends StatelessWidget {
  const _SupplierEngagementGroup({
    required this.engagement,
    required this.site,
  });

  final SupplierEngagement engagement;
  final BusinessSite? site;

  @override
  Widget build(BuildContext context) {
    final version = engagement.currentVersion;
    final rows = <_KvSpec>[
      _KvSpec('Tipo', _engagementKindLabel(engagement.kind)),
      if (engagement.startsOn != null)
        _KvSpec('Desde', _formatMonthYear(engagement.startsOn!), mono: true),
      if (version != null)
        _KvSpec(
          'Versión vigente',
          'v${version.version} · ${_billingCadenceLabel(version.billingCadence)}',
        ),
      if (version?.expectedAmount != null)
        _KvSpec(
          'Monto esperado',
          _money(version!.expectedAmount, version.currencyCode),
          mono: true,
        ),
      if (version?.dueDay != null)
        _KvSpec('Vencimiento', 'día ${version!.dueDay}'),
      if (site != null) _KvSpec('Sede', site!.name),
      if (_present(version?.serviceIdentifier))
        _KvSpec('Referencia', version!.serviceIdentifier!, mono: true),
      if (_present(engagement.portalUrl))
        _KvSpec('Portal', engagement.portalUrl!, mono: true),
    ];
    return _SupplierKvGroup(
      title: engagement.name,
      trailing: VbStatusBadge(
        label: _engagementStatusLabel(engagement.status),
        tone: _engagementStatusTone(engagement.status),
      ),
      rows: rows,
    );
  }
}

BusinessSite? _siteFor(List<BusinessSite> sites, String? siteId) {
  if (siteId == null) return null;
  for (final site in sites) {
    if (site.id == siteId) return site;
  }
  return null;
}

int _engagementStatusOrder(SupplierEngagementStatus status) => switch (status) {
      SupplierEngagementStatus.active => 0,
      SupplierEngagementStatus.draft => 1,
      SupplierEngagementStatus.suspended => 2,
      SupplierEngagementStatus.ended => 3,
    };

String _engagementKindLabel(SupplierEngagementKind kind) => switch (kind) {
      SupplierEngagementKind.contract => 'Contrato',
      SupplierEngagementKind.serviceAccount => 'Cuenta de servicio',
      SupplierEngagementKind.subscription => 'Suscripción',
      SupplierEngagementKind.lease => 'Arriendo',
      SupplierEngagementKind.utility => 'Servicio básico',
      SupplierEngagementKind.taxObligation => 'Obligación tributaria',
      SupplierEngagementKind.portal => 'Portal',
      SupplierEngagementKind.other => 'Otra relación',
    };

VbStatusTone _engagementStatusTone(SupplierEngagementStatus status) =>
    switch (status) {
      SupplierEngagementStatus.active => VbStatusTone.success,
      SupplierEngagementStatus.draft => VbStatusTone.info,
      SupplierEngagementStatus.suspended => VbStatusTone.warning,
      SupplierEngagementStatus.ended => VbStatusTone.neutral,
    };

// -----------------------------------------------------------------------------
// Criterios contables

class _SupplierAccountingSection extends StatelessWidget {
  const _SupplierAccountingSection({required this.profile});

  final SupplierProfile profile;

  @override
  Widget build(BuildContext context) {
    final signal = profile.attentionSignals?.accountingPolicyStatus;
    final policies = [...profile.accounting.policies]
      ..sort((left, right) => left.priority.compareTo(right.priority));
    return _SupplierSectionBody(
      groups: [
        if (signal == SupplierProfileAccountingPolicyStatus.missingPolicy)
          const VbNotice(
            title: 'Falta configurar un criterio contable',
            body: 'Este estado fue publicado por la proyección del proveedor.',
            tone: VbNoticeTone.warning,
          ),
        for (final policy in policies)
          _SupplierAccountingPolicyGroup(
            policy: policy,
            rules: profile.accounting.rules,
          ),
      ],
    );
  }
}

class _SupplierAccountingPolicyGroup extends StatelessWidget {
  const _SupplierAccountingPolicyGroup({
    required this.policy,
    required this.rules,
  });

  final SupplierAccountingPolicySummary policy;
  final List<SupplierAccountingRuleSummary> rules;

  @override
  Widget build(BuildContext context) {
    final version = policy.currentVersion;
    final activeRules = version == null
        ? const <SupplierAccountingRuleSummary>[]
        : rules
            .where(
              (rule) => rule.policyVersionId == version.id && rule.isActive,
            )
            .toList(growable: false);
    final rows = <_KvSpec>[
      if (version != null)
        _KvSpec(
          'Versión vigente',
          'v${version.version} · desde ${_formatDate(version.effectiveFrom)}',
        ),
      if (_present(version?.operationalNatureLabel))
        _KvSpec('Naturaleza operacional', version!.operationalNatureLabel!),
      if (version != null)
        _KvSpec(
          'Tratamiento tributario',
          _taxTreatmentLabel(version.taxTreatmentCode),
        ),
      if (version != null) _KvSpec('Moneda', version.currencyCode, mono: true),
      if (_present(version?.expectedDocumentType))
        _KvSpec('Documento esperado', version!.expectedDocumentType!),
      _KvSpec('Reglas vigentes', activeRules.length.toString(), mono: true),
    ];
    return _SupplierKvGroup(
      title: policy.name,
      trailing: VbStatusBadge(
        label: _accountingPolicyStatusLabel(policy.status),
        tone: _accountingPolicyStatusTone(policy.status),
      ),
      rows: rows,
    );
  }
}

String _accountingPolicyStatusLabel(SupplierAccountingPolicyStatus status) =>
    switch (status) {
      SupplierAccountingPolicyStatus.draft => 'Borrador',
      SupplierAccountingPolicyStatus.active => 'Rige hoy',
      SupplierAccountingPolicyStatus.retired => 'Retirado',
    };

VbStatusTone _accountingPolicyStatusTone(
        SupplierAccountingPolicyStatus status) =>
    switch (status) {
      SupplierAccountingPolicyStatus.draft => VbStatusTone.info,
      SupplierAccountingPolicyStatus.active => VbStatusTone.success,
      SupplierAccountingPolicyStatus.retired => VbStatusTone.neutral,
    };

String _taxTreatmentLabel(String value) => switch (value) {
      'no_tax' => 'Sin impuesto',
      'tax_included' => 'Impuesto incluido',
      'exempt' => 'Exento',
      'not_applicable' => 'No aplica',
      _ => 'Tratamiento publicado',
    };

/// `D-01`: es-CL, `dd/mm/aaaa`.
String _formatDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year}';
}

String _formatMonthYear(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  return '$month/${value.year}';
}

// -----------------------------------------------------------------------------
// Accesos

class _SupplierAccessSection extends StatelessWidget {
  const _SupplierAccessSection({
    required this.profile,
    required this.status,
    required this.accessDenied,
    required this.loadError,
    required this.revealController,
    required this.canReveal,
    required this.revealErrorTarget,
    required this.revealErrorMessage,
    required this.onReveal,
    required this.onCopy,
    required this.onHide,
    required this.onRetry,
  });

  final SupplierProfile profile;
  final SupplierCredentialStatus? status;
  final bool accessDenied;
  final Object? loadError;
  final SupplierCredentialRevealController? revealController;
  final bool canReveal;
  final String? revealErrorTarget;
  final String? revealErrorMessage;
  final ValueChanged<SupplierCredentialMetadata> onReveal;
  final ValueChanged<SupplierCredentialMetadata> onCopy;
  final VoidCallback onHide;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final type = _SupplierType(PurchaseTokens.of(context));
    final credentials = status?.credentials ?? const [];
    final hasOriginBoundSecret = credentials.any(
      (credential) =>
          credential.secretAvailable && credential.originUrl != null,
    );
    final groups = <Widget>[
      Text(
        credentials.any((credential) => credential.secretAvailable)
            ? 'Dónde entra y con qué cuenta. Las claves disponibles se piden aparte.'
            : 'Dónde entra y con qué cuenta. Puedes completar una clave desde el editor.',
        style: type.bodyMuted,
      ),
    ];
    if (accessDenied) {
      groups.add(
        const VbNotice(
          title: 'No tienes permiso para ver los accesos',
          body:
              'Esta sección no se cargó. Pídele el permiso a quien administra el taller.',
          tone: VbNoticeTone.warning,
        ),
      );
    } else if (loadError != null) {
      groups.add(
        VbNotice(
          title: 'No pudimos cargar los accesos',
          body: 'El resto del perfil sigue disponible.',
          tone: VbNoticeTone.warning,
          action: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Reintentar'),
          ),
        ),
      );
    } else {
      for (final credential in credentials) {
        groups.add(
          _SupplierCredentialGroup(
            metadata: credential,
            engagement: _engagementFor(
              profile.engagements,
              credential.engagementId,
            ),
            revealController: revealController,
            canReveal: canReveal,
            revealError: revealErrorTarget ==
                    _credentialTargetKey(
                      SupplierCredentialRevealTarget(
                        supplierId: credential.supplierId,
                        kind: credential.kind,
                        credentialKey: credential.credentialKey,
                      ),
                    )
                ? revealErrorMessage
                : null,
            onReveal: onReveal,
            onCopy: onCopy,
            onHide: onHide,
          ),
        );
      }
      if (hasOriginBoundSecret) {
        groups.add(
          const VbNotice(
            title: 'Origen HTTPS exacto',
            body:
                'La clave se usa sólo en el origen autorizado. No se prueban variantes como www ni el sitio general del proveedor.',
            tone: VbNoticeTone.info,
          ),
        );
      }
    }
    return _SupplierSectionBody(groups: groups);
  }
}

/// Una cuenta: título con el estado de la clave a la derecha, filas de dónde
/// entra y con qué usuario y —sólo mientras está revelada— la clave en una
/// caja warning con sus dos acciones. Las claves de prueba son parte del
/// contrato auditado y no cambian.
class _SupplierCredentialGroup extends StatelessWidget {
  const _SupplierCredentialGroup({
    required this.metadata,
    required this.engagement,
    required this.revealController,
    required this.canReveal,
    required this.revealError,
    required this.onReveal,
    required this.onCopy,
    required this.onHide,
  });

  final SupplierCredentialMetadata metadata;
  final SupplierEngagement? engagement;
  final SupplierCredentialRevealController? revealController;
  final bool canReveal;
  final String? revealError;
  final ValueChanged<SupplierCredentialMetadata> onReveal;
  final ValueChanged<SupplierCredentialMetadata> onCopy;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final type = _SupplierType(tokens);
    final target = SupplierCredentialRevealTarget(
      supplierId: metadata.supplierId,
      kind: metadata.kind,
      credentialKey: metadata.credentialKey,
    );
    final controller = revealController;
    final ownsTarget = controller != null &&
        controller.target != null &&
        _credentialTargetKey(controller.target!) ==
            _credentialTargetKey(target);
    final revealing = ownsTarget && controller.isRevealing;
    final visible = ownsTarget &&
        controller.isVisible &&
        _sameCredentialMetadataBinding(controller.metadata, metadata);
    final revealedSecret = visible ? controller.revealedSecret : null;
    final keySuffix = '${metadata.kind.dbValue}-${metadata.credentialKey}';
    final rows = <_KvSpec>[
      if (_present(metadata.originUrl))
        _KvSpec('Entra en', metadata.originUrl!, mono: true),
      if (_present(metadata.username))
        _KvSpec('Usuario', metadata.username!, mono: true),
      if (engagement != null) _KvSpec('Relación', engagement!.name),
      if (metadata.updatedAt != null)
        _KvSpec(
          'Actualizado',
          _formatDate(metadata.updatedAt!.toLocal()),
          mono: true,
        ),
    ];

    final Widget? headerAction;
    if (!metadata.secretAvailable) {
      headerAction = Text(
        'Sin clave guardada',
        key: ValueKey('supplier-credential-no-secret-$keySuffix'),
        style: type.label,
      );
    } else if (visible) {
      headerAction = const VbStatusBadge(
        label: 'Visible ahora',
        tone: VbStatusTone.warning,
      );
    } else if (canReveal && controller != null) {
      headerAction = TextButton(
        key: ValueKey('supplier-credential-reveal-$keySuffix'),
        onPressed: revealing ? null : () => onReveal(metadata),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 38),
          textStyle: type.button,
        ),
        child: Text(revealing ? 'Abriendo…' : 'Ver la clave'),
      );
    } else {
      headerAction = null;
    }

    return _SupplierKvGroup(
      title: metadata.label ?? 'Acceso protegido',
      trailing: headerAction,
      rows: rows,
      footer: revealedSecret == null && revealError == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (revealedSecret != null) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: roles.warning.container,
                      border: Border.all(color: roles.warning.border),
                      borderRadius:
                          BorderRadius.circular(_SupplierMetrics.noteRadius),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                revealedSecret,
                                key: ValueKey(
                                  'supplier-credential-secret-$keySuffix',
                                ),
                                style: type.numRow.copyWith(
                                  color: roles.warning.onContainer,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'se oculta sola',
                                style: type.label.copyWith(
                                  color: roles.warning.onContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: _SupplierMetrics.spacing8),
                        Wrap(
                          children: [
                            TextButton(
                              key: ValueKey(
                                'supplier-credential-copy-$keySuffix',
                              ),
                              onPressed: () => onCopy(metadata),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 38),
                                foregroundColor: roles.warning.onContainer,
                                textStyle: type.button,
                              ),
                              child: const Text('Copiar'),
                            ),
                            TextButton(
                              key: ValueKey(
                                'supplier-credential-hide-$keySuffix',
                              ),
                              onPressed: onHide,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 38),
                                foregroundColor: roles.warning.onContainer,
                                textStyle: type.button,
                              ),
                              child: const Text('Ocultar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _SupplierMetrics.spacing6),
                  Text(
                    'Queda registrado quién lo vio y cuándo.',
                    style: type.note,
                  ),
                ],
                if (revealError != null) ...[
                  if (revealedSecret != null)
                    const SizedBox(height: _SupplierMetrics.spacing8),
                  Text(
                    revealError!,
                    key: ValueKey(
                      'supplier-credential-reveal-error-$keySuffix',
                    ),
                    style: type.label.copyWith(
                      color: roles.warning.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

SupplierEngagement? _engagementFor(
  List<SupplierEngagement> engagements,
  String? engagementId,
) {
  if (engagementId == null) return null;
  for (final engagement in engagements) {
    if (engagement.id == engagementId) return engagement;
  }
  return null;
}

// -----------------------------------------------------------------------------
// Movimientos

/// Las cifras arriba y, debajo, la tabla `T-01` con cada documento y pago. En
/// compacto la fila es una tarjeta; nunca una tabla encogida.
class _SupplierMovementsSection extends StatelessWidget {
  const _SupplierMovementsSection({
    required this.summaries,
    required this.timeline,
    required this.compact,
  });

  final List<SupplierEconomicSummaryReadModel> summaries;
  final SupplierEconomicTimelinePage timeline;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final type = _SupplierType(PurchaseTokens.of(context));
    final activities = [...timeline.timeline.activities]
      ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _SupplierMetrics.bodyPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < summaries.length; index++) ...[
                if (index > 0) ...[
                  const SizedBox(height: _SupplierMetrics.spacing18),
                  const _SupplierHairline(),
                  const SizedBox(height: _SupplierMetrics.spacing18),
                ],
                _SupplierGroup(
                  title: 'Compras y pagos',
                  meta: summaries[index].currencyCode,
                  child: _SupplierEconomicOverview(
                    summary: summaries[index],
                    compact: compact,
                  ),
                ),
              ],
              if (activities.isNotEmpty) ...[
                const SizedBox(height: _SupplierMetrics.spacing18),
                const _SupplierOverline('Actividad reconocida'),
                const SizedBox(height: _SupplierMetrics.spacing8),
              ],
            ],
          ),
        ),
        if (activities.isNotEmpty) ...[
          _SupplierActivityTable(activities: activities, compact: compact),
          if (timeline.hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Text(
                'Hay más actividad disponible en la proyección.',
                style: type.note,
              ),
            )
          else
            const SizedBox(height: _SupplierMetrics.spacing8),
        ],
      ],
    );
  }
}

/// `T-01`: cabecera 30 sobre hundido con borde fuerte y overlines; filas de
/// 48 con hairline; identidad flexible, monto fijo a la derecha en mono. Va a
/// sangre dentro de la hoja.
class _SupplierActivityTable extends StatelessWidget {
  const _SupplierActivityTable({
    required this.activities,
    required this.compact,
  });

  final List<SupplierEconomicActivity> activities;
  final bool compact;

  static const double _dateWidth = 112;
  static const double _referenceWidth = 168;
  static const double _amountWidth = 124;
  static const double _statusWidth = 118;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final asTable = !compact && constraints.maxWidth >= 640;
        if (!asTable) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Divider(height: 1, thickness: 1, color: tokens.borderStrong),
              for (var index = 0; index < activities.length; index++)
                _SupplierActivityCard(
                  activity: activities[index],
                  first: index == 0,
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SupplierActivityHeader(
              dateWidth: _dateWidth,
              referenceWidth: _referenceWidth,
              amountWidth: _amountWidth,
              statusWidth: _statusWidth,
            ),
            for (final activity in activities)
              _SupplierActivityRow(
                activity: activity,
                dateWidth: _dateWidth,
                referenceWidth: _referenceWidth,
                amountWidth: _amountWidth,
                statusWidth: _statusWidth,
              ),
          ],
        );
      },
    );
  }
}

class _SupplierActivityHeader extends StatelessWidget {
  const _SupplierActivityHeader({
    required this.dateWidth,
    required this.referenceWidth,
    required this.amountWidth,
    required this.statusWidth,
  });

  final double dateWidth;
  final double referenceWidth;
  final double amountWidth;
  final double statusWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    Widget cell(
      String label,
      double? width, {
      TextAlign align = TextAlign.left,
    }) {
      final padded = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _SupplierMetrics.tableCellPadding,
        ),
        child: Text(
          label.toUpperCase(),
          style: type.overline,
          textAlign: align,
        ),
      );
      return width == null
          ? Expanded(child: padded)
          : SizedBox(width: width, child: padded);
    }

    return Container(
      height: _SupplierMetrics.tableHeaderHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: _SupplierMetrics.tableEdgePadding -
            _SupplierMetrics.tableCellPadding,
      ),
      decoration: BoxDecoration(
        color: tokens.sunken,
        border: Border(
          top: BorderSide(color: tokens.border),
          bottom: BorderSide(color: tokens.borderStrong),
        ),
      ),
      child: Row(
        children: [
          cell('Fecha', dateWidth),
          cell('Movimiento', null),
          cell('Referencia', referenceWidth),
          cell('Monto', amountWidth, align: TextAlign.right),
          cell('Estado', statusWidth, align: TextAlign.right),
        ],
      ),
    );
  }
}

class _SupplierActivityRow extends StatelessWidget {
  const _SupplierActivityRow({
    required this.activity,
    required this.dateWidth,
    required this.referenceWidth,
    required this.amountWidth,
    required this.statusWidth,
  });

  final SupplierEconomicActivity activity;
  final double dateWidth;
  final double referenceWidth;
  final double amountWidth;
  final double statusWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    final amount =
        activity.grossAmount != 0 ? activity.grossAmount : activity.paidAmount;
    Widget cell(Widget child, double? width, {Alignment? align}) {
      final padded = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _SupplierMetrics.tableCellPadding,
        ),
        child: align == null ? child : Align(alignment: align, child: child),
      );
      return width == null
          ? Expanded(child: padded)
          : SizedBox(width: width, child: padded);
    }

    return Container(
      constraints: const BoxConstraints(
        minHeight: _SupplierMetrics.tableRowHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: _SupplierMetrics.tableEdgePadding -
            _SupplierMetrics.tableCellPadding,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        children: [
          cell(
            Text(
              _formatDate(activity.occurredAt),
              style: type.mono,
              maxLines: 1,
              softWrap: false,
            ),
            dateWidth,
          ),
          cell(
            Text(
              _economicActivityLabel(activity.kind),
              style: type.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            null,
          ),
          cell(
            Text(
              _present(activity.documentNumber)
                  ? activity.documentNumber!
                  : '—',
              style: _present(activity.documentNumber)
                  ? type.mono
                  : type.mono.copyWith(color: tokens.inkFaint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            referenceWidth,
          ),
          cell(
            Text(
              _money(amount, activity.currencyCode),
              style: type.numRow,
              textAlign: TextAlign.right,
            ),
            amountWidth,
            align: Alignment.centerRight,
          ),
          cell(
            VbStatusBadge(
              label: _economicQualityLabel(activity.dataQualityStatus),
              tone: _economicQualityTone(activity.dataQualityStatus),
              dense: true,
            ),
            statusWidth,
            align: Alignment.centerRight,
          ),
        ],
      ),
    );
  }
}

/// La misma fila en compacto: identidad arriba, fecha y referencia debajo,
/// monto y estado a la derecha.
class _SupplierActivityCard extends StatelessWidget {
  const _SupplierActivityCard({required this.activity, required this.first});

  final SupplierEconomicActivity activity;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    final amount =
        activity.grossAmount != 0 ? activity.grossAmount : activity.paidAmount;
    final meta = [
      _formatDate(activity.occurredAt),
      if (_present(activity.documentNumber)) activity.documentNumber!,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _economicActivityLabel(activity.kind),
                  style: type.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(meta, style: type.meta),
              ],
            ),
          ),
          const SizedBox(width: _SupplierMetrics.spacing12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_money(amount, activity.currencyCode), style: type.numRow),
              const SizedBox(height: 3),
              VbStatusBadge(
                label: _economicQualityLabel(activity.dataQualityStatus),
                tone: _economicQualityTone(activity.dataQualityStatus),
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _economicActivityLabel(SupplierEconomicActivityKind kind) =>
    switch (kind) {
      SupplierEconomicActivityKind.purchaseInvoice => 'Documento de compra',
      SupplierEconomicActivityKind.expense => 'Gasto',
      SupplierEconomicActivityKind.purchasePayment => 'Pago de compra',
      SupplierEconomicActivityKind.expensePayment => 'Pago de gasto',
      SupplierEconomicActivityKind.purchaseCreditNote =>
        'Nota de crédito de compra',
      SupplierEconomicActivityKind.purchaseSupplierRefund =>
        'Devolución del proveedor',
      SupplierEconomicActivityKind.creditNote => 'Nota de crédito',
      SupplierEconomicActivityKind.suppliedProduct => 'Producto suministrado',
      SupplierEconomicActivityKind.other => 'Movimiento reconocido',
    };

String _economicQualityLabel(SupplierEconomicDataQualityStatus status) =>
    switch (status) {
      SupplierEconomicDataQualityStatus.complete => 'completo',
      SupplierEconomicDataQualityStatus.needsReview => 'revisar',
      SupplierEconomicDataQualityStatus.notRecognized => 'no reconocido',
      SupplierEconomicDataQualityStatus.notApplicable => 'no aplica',
      SupplierEconomicDataQualityStatus.lifecycleOnly => 'ciclo de vida',
      SupplierEconomicDataQualityStatus.unknown => 'estado publicado',
    };

VbStatusTone _economicQualityTone(SupplierEconomicDataQualityStatus status) =>
    switch (status) {
      SupplierEconomicDataQualityStatus.complete => VbStatusTone.success,
      SupplierEconomicDataQualityStatus.needsReview => VbStatusTone.warning,
      SupplierEconomicDataQualityStatus.notRecognized => VbStatusTone.danger,
      SupplierEconomicDataQualityStatus.notApplicable ||
      SupplierEconomicDataQualityStatus.lifecycleOnly ||
      SupplierEconomicDataQualityStatus.unknown =>
        VbStatusTone.neutral,
    };

// -----------------------------------------------------------------------------
// Error y no encontrado

class _SupplierDetailError extends StatelessWidget {
  const _SupplierDetailError({
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const VbNotice(
                title: 'No pudimos cargar este proveedor',
                body: 'Puedes reintentar o volver al directorio.',
                tone: VbNoticeTone.danger,
              ),
              const SizedBox(height: _SupplierMetrics.spacing12),
              Wrap(
                spacing: _SupplierMetrics.spacing8,
                runSpacing: _SupplierMetrics.spacing8,
                alignment: WrapAlignment.end,
                children: [
                  _SupplierSecondaryButton(
                    label: 'Volver',
                    touch: true,
                    onPressed: onClose,
                  ),
                  _SupplierPrimaryButton(
                    label: 'Reintentar',
                    touch: true,
                    onPressed: onRetry,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierDetailNotFound extends StatelessWidget {
  const _SupplierDetailNotFound({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const VbNotice(
                title: 'Proveedor no encontrado',
                body: 'El registro ya no está disponible en este taller.',
                tone: VbNoticeTone.neutral,
              ),
              const SizedBox(height: _SupplierMetrics.spacing12),
              Align(
                alignment: Alignment.centerRight,
                child: _SupplierSecondaryButton(
                  label: 'Volver al directorio',
                  touch: true,
                  onPressed: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Contactos

class _ContactsLoadFailure {
  const _ContactsLoadFailure(this.error);

  final Object error;
}

enum _SupplierContactAction {
  edit,
  message,
  makePrimary,
  deactivate,
  reactivate
}

/// Las personas del proveedor. Una es la principal (a ella le escribe el
/// ERP); una desactivada conserva sus chats y archivos, sólo deja de ser
/// candidata. Nunca se borra.
class _SupplierContactsSection extends StatelessWidget {
  const _SupplierContactsSection({
    required this.contacts,
    required this.loadError,
    required this.busy,
    required this.compact,
    required this.onAdd,
    required this.onEdit,
    required this.onSetPrimary,
    required this.onSetActive,
    required this.onMessage,
    required this.onRetry,
  });

  final List<SupplierContact> contacts;
  final Object? loadError;
  final bool busy;
  final bool compact;
  final VoidCallback onAdd;
  final ValueChanged<SupplierContact> onEdit;
  final ValueChanged<SupplierContact> onSetPrimary;
  final void Function(SupplierContact contact, bool isActive) onSetActive;
  final ValueChanged<SupplierContact> onMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final type = _SupplierType(PurchaseTokens.of(context));
    final active = contacts.where((c) => c.isActive).toList(growable: false);
    final inactive = contacts.where((c) => !c.isActive).toList(growable: false);
    final addButton = _SupplierSecondaryButton(
      key: const ValueKey('supplier-contacts-add'),
      label: 'Agregar contacto',
      icon: Icons.person_add_alt_1_outlined,
      touch: compact,
      onPressed: busy ? null : onAdd,
    );

    Widget rows(List<SupplierContact> people) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < people.length; index++)
            _SupplierContactRow(
              contact: people[index],
              first: index == 0,
              busy: busy,
              onAction: (action) => switch (action) {
                _SupplierContactAction.edit => onEdit(people[index]),
                _SupplierContactAction.message => onMessage(people[index]),
                _SupplierContactAction.makePrimary =>
                  onSetPrimary(people[index]),
                _SupplierContactAction.deactivate =>
                  onSetActive(people[index], false),
                _SupplierContactAction.reactivate =>
                  onSetActive(people[index], true),
              },
            ),
        ],
      );
    }

    final groups = <Widget>[];
    if (loadError != null) {
      groups.add(
        _SupplierGroup(
          title: 'Personas',
          trailing: addButton,
          child: VbNotice(
            title: 'No pudimos cargar los contactos',
            body: 'El resto del perfil sigue disponible.',
            tone: VbNoticeTone.warning,
            action: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Reintentar'),
            ),
          ),
        ),
      );
    } else if (contacts.isEmpty) {
      groups.add(
        _SupplierGroup(
          title: 'Personas',
          trailing: addButton,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sin contactos todavía', style: type.bodyStrong),
              const SizedBox(height: 3),
              Text(
                'Agrega a la persona a la que le escribes. Será la principal.',
                style: type.bodyMuted,
              ),
            ],
          ),
        ),
      );
    } else {
      groups.add(
        _SupplierGroup(
          title: 'Personas',
          meta: _countLabel(active.length, 'activa', 'activas'),
          trailing: addButton,
          child: active.isEmpty
              ? Text(
                  'Nadie activo. Reactiva a alguien o agrega una persona nueva.',
                  style: type.bodyMuted,
                )
              : rows(active),
        ),
      );
      if (inactive.isNotEmpty) {
        groups.add(
          _SupplierGroup(
            title: 'Ya no atienden',
            meta: 'sus chats se conservan',
            child: rows(inactive),
          ),
        );
      }
    }
    return _SupplierSectionBody(groups: groups);
  }
}

class _SupplierContactRow extends StatelessWidget {
  const _SupplierContactRow({
    required this.contact,
    required this.first,
    required this.busy,
    required this.onAction,
  });

  final SupplierContact contact;
  final bool first;
  final bool busy;
  final ValueChanged<_SupplierContactAction> onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _SupplierType(tokens);
    final muted = !contact.isActive;
    final details = <String>[
      if (_present(contact.role)) contact.role!,
      if (_present(contact.phone)) contact.phone!,
      if (_present(contact.email)) contact.email!,
    ];
    final deactivatedAt = contact.deactivatedAt;
    return Container(
      constraints: const BoxConstraints(
        minHeight: _SupplierMetrics.tableRowHeight,
      ),
      padding: const EdgeInsets.symmetric(vertical: _SupplierMetrics.spacing8),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SupplierAvatar(
            name: contact.name,
            size: _SupplierMetrics.personAvatar,
            person: true,
          ),
          const SizedBox(width: _SupplierMetrics.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: _SupplierMetrics.spacing8,
                  runSpacing: _SupplierMetrics.spacing4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      contact.name,
                      style: muted
                          ? type.bodyStrong.copyWith(color: tokens.inkMuted)
                          : type.bodyStrong,
                    ),
                    if (contact.isPrimary)
                      const VbStatusBadge(
                        label: 'Principal',
                        tone: VbStatusTone.success,
                        dense: true,
                      ),
                    if (muted)
                      const VbStatusBadge(
                        label: 'Inactivo',
                        tone: VbStatusTone.neutral,
                        dense: true,
                      ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(details.join(' · '), style: type.bodyMuted),
                ],
                if (muted && deactivatedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Desactivado el ${_formatDate(deactivatedAt.toLocal())} · sus chats se conservan',
                    style: type.meta,
                  ),
                ] else if (contact.wasDiscoveredFromWhatsApp) ...[
                  const SizedBox(height: 2),
                  Text('Conocido por un chat de WhatsApp', style: type.meta),
                ],
              ],
            ),
          ),
          const SizedBox(width: _SupplierMetrics.spacing8),
          if (contact.hasPhone && contact.isActive)
            _SupplierInlineAction(
              key: ValueKey('supplier-contact-message-${contact.id}'),
              label: 'Escribir',
              onPressed:
                  busy ? null : () => onAction(_SupplierContactAction.message),
            ),
          PopupMenuButton<_SupplierContactAction>(
            key: ValueKey('supplier-contact-menu-${contact.id}'),
            enabled: !busy,
            tooltip: 'Acciones de ${contact.name}',
            icon: Icon(Icons.more_horiz, color: tokens.inkMuted),
            onSelected: onAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _SupplierContactAction.edit,
                child: Text('Editar'),
              ),
              if (contact.hasPhone)
                const PopupMenuItem(
                  value: _SupplierContactAction.message,
                  child: Text('Escribir por WhatsApp'),
                ),
              if (contact.isActive && !contact.isPrimary)
                const PopupMenuItem(
                  value: _SupplierContactAction.makePrimary,
                  child: Text('Marcar como principal'),
                ),
              if (contact.isActive)
                const PopupMenuItem(
                  value: _SupplierContactAction.deactivate,
                  child: Text('Desactivar'),
                )
              else
                const PopupMenuItem(
                  value: _SupplierContactAction.reactivate,
                  child: Text('Reactivar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierContactDraft {
  const _SupplierContactDraft({
    required this.name,
    required this.role,
    required this.phone,
    required this.email,
    required this.isPrimary,
  });

  final String name;
  final String? role;
  final String? phone;
  final String? email;
  final bool? isPrimary;
}

class _SupplierContactEditorDialog extends StatefulWidget {
  const _SupplierContactEditorDialog({
    required this.contact,
    required this.forcePrimary,
  });

  final SupplierContact? contact;
  final bool forcePrimary;

  @override
  State<_SupplierContactEditorDialog> createState() =>
      _SupplierContactEditorDialogState();
}

class _SupplierContactEditorDialogState
    extends State<_SupplierContactEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _role;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late bool _isPrimary;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    _name = TextEditingController(text: contact?.name ?? '');
    _role = TextEditingController(text: contact?.role ?? '');
    _phone = TextEditingController(text: contact?.phone ?? '');
    _email = TextEditingController(text: contact?.email ?? '');
    _isPrimary = contact?.isPrimary ?? widget.forcePrimary;
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _SupplierContactDraft(
        name: _name.text.trim(),
        role: _optional(_role.text),
        phone: _optional(_phone.text),
        email: _optional(_email.text),
        // La marca se manda sólo cuando cambia; la principal actual no se
        // puede bajar desde aquí, se sube a otra.
        isPrimary: _isPrimary == (widget.contact?.isPrimary ?? false)
            ? null
            : _isPrimary,
      ),
    );
  }

  static String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final lockedPrimary = contact?.isPrimary == true || widget.forcePrimary;
    return AlertDialog(
      title: Text(contact == null ? 'Nuevo contacto' : 'Editar contacto'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('supplier-contact-name'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Escribe el nombre de la persona'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('supplier-contact-role'),
                controller: _role,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Cargo',
                  hintText: 'Vendedor, despacho, cobranza…',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('supplier-contact-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp',
                  hintText: '+56 9 1234 5678',
                ),
                validator: (value) {
                  final digits =
                      (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                  if ((value ?? '').trim().isEmpty) return null;
                  return digits.length < 8
                      ? 'Un número necesita al menos 8 dígitos'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('supplier-contact-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo'),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  return text.indexOf('@') < 1 ? 'No parece un correo' : null;
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                key: const ValueKey('supplier-contact-primary'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Contacto principal'),
                subtitle: const Text('El ERP le escribe a esta persona'),
                value: _isPrimary,
                onChanged: lockedPrimary
                    ? null
                    : (value) => setState(() => _isPrimary = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('supplier-contact-save'),
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
