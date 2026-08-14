import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/mail/models/mail_folder.dart';
import 'package:vinabike_erp/modules/mail/providers/email_provider.dart';
import 'package:vinabike_erp/modules/mail/providers/mail_account_manager.dart';

/// El modelo de lectura unificado con carpetas tiene dos invariantes que no
/// pueden depender de qué carpeta esté mirando el usuario:
///
/// 1. El badge del sidebar (`unreadCount`) y el resumen del panel de
///    notificaciones (`briefingEmails`) son SIEMPRE de la bandeja de entrada.
/// 2. El refresco de bandeja de entrada que corre en segundo plano para las
///    notificaciones no puede tocar la carpeta que el usuario está viendo.
void main() {
  final manager = MailAccountManager.instance;
  late _ScriptedProvider provider;

  setUp(() {
    manager.debugResetInMemoryState();
    manager.debugAuthUserIdOverride = () => 'user-test';
    manager.debugCommitSessionScope('user-test');
    provider = _ScriptedProvider();
    manager.debugAttachProvider(provider);
  });

  tearDown(manager.debugResetInMemoryState);

  Email mail(
    String id, {
    MailFolder folder = MailFolder.inbox,
    bool isRead = false,
    String to = 'taller@vinabike.cl',
  }) {
    return Email(
      id: id,
      providerId: 'scripted',
      folderId: folder.name,
      subject: 'Asunto $id',
      fromAddress: 'Remitente <r@example.com>',
      toAddress: to,
      receivedTime: DateTime(2026, 8, 5, 12),
      isRead: isRead,
      hasAttachment: false,
    );
  }

  test('cambiar de carpeta lista esa carpeta y preserva la bandeja', () async {
    provider.script(MailFolder.inbox, [mail('in-1'), mail('in-2')]);
    provider.script(
      MailFolder.sent,
      [mail('sent-1', folder: MailFolder.sent, isRead: true)],
    );
    await manager.refreshInbox();

    await manager.setActiveFolder(MailFolder.sent);

    expect(manager.activeFolder, MailFolder.sent);
    expect(manager.emails.map((e) => e.id), ['sent-1']);
    expect(
      provider.listedFolders.last,
      MailFolder.sent,
      reason: 'la carpeta viaja hasta el proveedor',
    );

    // Invariantes de bandeja de entrada mientras se mira otra carpeta.
    expect(manager.unreadCount, 2);
    expect(manager.briefingEmails.map((e) => e.id), ['in-1', 'in-2']);
  });

  test('el refresco de bandeja en segundo plano no toca la carpeta activa',
      () async {
    provider.script(MailFolder.inbox, [mail('in-1')]);
    await manager.refreshInbox();
    provider.script(
      MailFolder.trash,
      [mail('trash-1', folder: MailFolder.trash, isRead: true)],
    );
    await manager.setActiveFolder(MailFolder.trash);

    provider.script(MailFolder.inbox, [mail('in-1'), mail('in-2')]);
    await manager.refreshInbox();

    expect(manager.activeFolder, MailFolder.trash);
    expect(manager.emails.map((e) => e.id), ['trash-1']);
    expect(manager.unreadCount, 2, reason: 'la bandeja sí se actualizó');
  });

  test('cargar más pagina la carpeta activa, no la bandeja', () async {
    provider.script(
      MailFolder.sent,
      List.generate(
        MailAccountManager.inboxPageSize,
        (i) => mail('sent-$i', folder: MailFolder.sent, isRead: true),
      ),
      hasMore: true,
    );
    await manager.setActiveFolder(MailFolder.sent);
    expect(manager.canLoadMore, isTrue);

    provider.script(
      MailFolder.sent,
      [mail('sent-extra', folder: MailFolder.sent, isRead: true)],
      hasMore: false,
    );
    await manager.loadMore();

    expect(
      manager.emails.map((e) => e.id),
      contains('sent-extra'),
    );
    expect(
      provider.listedStarts.last,
      MailAccountManager.inboxPageSize,
      reason: 'la página siguiente parte donde terminó la carpeta activa',
    );
    expect(manager.canLoadMore, isFalse);
  });

  test('restaurar desde papelera delega en el proveedor y limpia la vista',
      () async {
    final trashed = mail('trash-1', folder: MailFolder.trash, isRead: true);
    provider.script(MailFolder.trash, [trashed]);
    await manager.setActiveFolder(MailFolder.trash);
    await manager.selectEmail(trashed);

    final success = await manager.restoreSelectedEmail();

    expect(success, isTrue);
    expect(provider.restoredIds, ['trash-1']);
    expect(manager.emails, isEmpty);
    expect(manager.selectedEmail, isNull);
  });

  test('reportar spam saca el correo de la bandeja y del badge', () async {
    final suspicious = mail('in-spam');
    provider.script(MailFolder.inbox, [suspicious, mail('in-2')]);
    await manager.refreshInbox();
    await manager.selectEmail(suspicious);

    final success = await manager.markSelectedAsSpam();

    expect(success, isTrue);
    expect(provider.spamIds, ['in-spam']);
    expect(manager.briefingEmails.map((e) => e.id), ['in-2']);
    expect(manager.unreadCount, 1);
  });

  test('cambiar de carpeta limpia búsqueda y selección', () async {
    provider.script(MailFolder.inbox, [mail('in-1')]);
    provider.script(MailFolder.spam, const []);
    await manager.refreshInbox();
    await manager.selectEmail(manager.emails.single);
    await manager.searchInbox('asunto');
    expect(manager.isSearchActive, isTrue);

    await manager.setActiveFolder(MailFolder.spam);

    expect(manager.isSearchActive, isFalse);
    expect(manager.selectedEmail, isNull);
    expect(manager.emails, isEmpty);
  });

  test('abrir un correo revierte el leído local si el proveedor falla',
      () async {
    final unread = mail('in-1');
    provider.script(MailFolder.inbox, [unread]);
    await manager.refreshInbox();

    final remoteMutation = Completer<bool>();
    provider.markReadCompleters.add(remoteMutation);
    provider.providerError = 'El proveedor rechazó la actualización.';

    final selection = manager.selectEmail(unread);

    expect(
      manager.emails.single.isRead,
      isTrue,
      reason: 'la proyección optimista mantiene la interfaz inmediata',
    );
    expect(provider.markReadCalls, [(id: 'in-1', read: true)]);

    remoteMutation.complete(false);
    await selection;
    await pumpEventQueue();

    expect(manager.emails.single.isRead, isFalse);
    expect(manager.unreadCount, 1);
    expect(manager.error, contains('Se restauró el estado confirmado'));
  });

  test('serializa leído y no leído para no invertir el estado remoto',
      () async {
    final unread = mail('in-1');
    provider.script(MailFolder.inbox, [unread]);
    await manager.refreshInbox();

    final markRead = Completer<bool>();
    final markUnread = Completer<bool>();
    provider.markReadCompleters.addAll([markRead, markUnread]);

    final first = manager.markAsRead(unread);
    final second = manager.markAsRead(unread, read: false);

    expect(manager.emails.single.isRead, isFalse);
    expect(
      provider.markReadCalls,
      [(id: 'in-1', read: true)],
      reason: 'la segunda mutación espera la confirmación de la primera',
    );

    markRead.complete(true);
    expect(await first, isTrue);
    await pumpEventQueue();
    expect(
      provider.markReadCalls,
      [(id: 'in-1', read: true), (id: 'in-1', read: false)],
    );

    markUnread.complete(true);
    expect(await second, isTrue);
    await pumpEventQueue();

    expect(manager.emails.single.isRead, isFalse);
    expect(manager.unreadCount, 1);
  });

  test('un refresco vacío autoritativo elimina correos movidos en otro equipo',
      () async {
    provider.script(MailFolder.inbox, [mail('in-1')]);
    await manager.refreshInbox();
    expect(manager.emails, hasLength(1));

    provider.script(MailFolder.inbox, const []);
    await manager.refreshInbox();

    expect(manager.emails, isEmpty);
    expect(manager.unreadCount, 0);
  });

  test('responder usa la operación nativa y conserva la identidad del hilo',
      () async {
    final original = mail('in-1').copyWith(
      threadId: 'thread-1',
      rfcMessageId: '<message-1@example.com>',
      references: '<parent@example.com>',
    );

    final success = await manager.replyToEmail(
      originalEmail: original,
      content: '<p>Respuesta</p>',
      to: 'sender@example.com',
      subject: 'Re: Asunto in-1',
      fromAddress: 'scripted@example.com',
      cc: 'team@example.com',
      replyAll: true,
    );

    expect(success, isTrue);
    expect(provider.replyCalls, [
      {
        'emailId': 'in-1',
        'threadId': 'thread-1',
        'rfcMessageId': '<message-1@example.com>',
        'references': '<parent@example.com>',
        'to': 'sender@example.com',
        'subject': 'Re: Asunto in-1',
        'fromAddress': 'scripted@example.com',
        'cc': 'team@example.com',
        'replyAll': true,
      }
    ]);
  });
}

class _ScriptedProvider extends EmailProvider {
  /// Cola de páginas por carpeta: cada fetch consume una y publica el
  /// `hasMore` que rige DESPUÉS de esa página, como un servidor real.
  final Map<MailFolder, List<({List<Email> emails, bool hasMoreAfter})>>
      _pageQueues = {};
  final Map<MailFolder, bool> _hasMore = {};
  final List<MailFolder> listedFolders = [];
  final List<int> listedStarts = [];
  final List<String> restoredIds = [];
  final List<String> spamIds = [];
  final List<String> notSpamIds = [];
  final List<String> trashedIds = [];
  final List<Completer<bool>> markReadCompleters = [];
  final List<({String id, bool read})> markReadCalls = [];
  final List<Map<String, Object?>> replyCalls = [];
  String? providerError;

  void script(MailFolder folder, List<Email> emails, {bool hasMore = false}) {
    _pageQueues
        .putIfAbsent(folder, () => [])
        .add((emails: emails, hasMoreAfter: hasMore));
  }

  @override
  String get providerId => 'scripted';

  @override
  String get displayName => 'Scripted';

  @override
  String get iconAsset => '';

  @override
  String? get accountEmail => 'scripted@example.com';

  @override
  bool get isAuthenticated => true;

  @override
  bool get isLoading => false;

  @override
  String? get error => providerError;

  @override
  List<Email> get emails => const [];

  @override
  Email? get selectedEmail => null;

  @override
  bool hasMoreIn(MailFolder folder) => _hasMore[folder] ?? false;

  @override
  Future<void> initialize() async {}

  @override
  Future<String> getAuthorizationUrl({
    required String redirectUri,
    String? state,
  }) async =>
      '';

  @override
  Future<bool> exchangeCodeForTokens({
    required String code,
    required String redirectUri,
  }) async =>
      false;

  @override
  Future<void> disconnect() async {}

  @override
  Future<String?> refreshAccessToken() async => null;

  @override
  Future<String?> getValidAccessToken() async => null;

  @override
  Future<List<Email>> getMessages({
    MailFolder folder = MailFolder.inbox,
    int limit = 50,
    int start = 0,
    String? pageToken,
    String? searchQuery,
    List<Email> knownEmails = const [],
  }) async {
    listedFolders.add(folder);
    listedStarts.add(start);
    final queue = _pageQueues[folder];
    if (queue == null || queue.isEmpty) return const [];
    final page = queue.removeAt(0);
    _hasMore[folder] = page.hasMoreAfter;
    return List<Email>.from(page.emails);
  }

  @override
  Future<Email> getEmailContent(Email email) async =>
      email.copyWith(content: '<p>contenido</p>');

  @override
  Future<Uint8List> downloadAttachment(
    Email email,
    EmailAttachment attachment,
  ) async =>
      Uint8List(0);

  @override
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String content,
    String? fromAddress,
    String? cc,
    String? bcc,
  }) async =>
      true;

  @override
  Future<bool> replyToEmail({
    required String emailId,
    required String content,
    required String to,
    required String subject,
    String? fromAddress,
    String? cc,
    String? bcc,
    String? threadId,
    String? rfcMessageId,
    String? references,
    bool replyAll = false,
  }) async {
    replyCalls.add({
      'emailId': emailId,
      'threadId': threadId,
      'rfcMessageId': rfcMessageId,
      'references': references,
      'to': to,
      'subject': subject,
      'fromAddress': fromAddress,
      'cc': cc,
      'replyAll': replyAll,
    });
    return true;
  }

  @override
  Future<bool> moveToTrash(String emailId) async {
    trashedIds.add(emailId);
    return true;
  }

  @override
  Future<bool> restoreFromTrash(String emailId) async {
    restoredIds.add(emailId);
    return true;
  }

  @override
  Future<bool> markAsSpam(String emailId) async {
    spamIds.add(emailId);
    return true;
  }

  @override
  Future<bool> markAsNotSpam(String emailId) async {
    notSpamIds.add(emailId);
    return true;
  }

  @override
  Future<bool> markAsRead(String emailId, {bool read = true}) async {
    markReadCalls.add((id: emailId, read: read));
    if (markReadCompleters.isEmpty) return true;
    return markReadCompleters.removeAt(0).future;
  }

  @override
  void clearError() {}

  @override
  void clearSelectedEmail() {}
}
