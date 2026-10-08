import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/public_store/models/customer_auth_forms.dart';
import 'package:vinabike_public_core/public_store/models/customer_chat_words.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_forms.dart';
import 'package:vinabike_public_core/shared/utils/auth_input_validation.dart';
import 'package:vinabike_public_core/shared/utils/self_password_rules.dart';

import 'portal_page_view.dart';
import 'public_reads.dart';

/// `POST /cuenta/vista` with `{path, query}` and the customer's session as
/// `authorization: Bearer <token>`: the portal page, read from Supabase as
/// that customer (row security decides what they see; every read filters
/// the tenant too) and drawn by [portalView].
///
/// Answers `{html}`, or `{state}`: `expired` when Supabase refused the token
/// (the page renews it and asks again), `not-customer` when the session is
/// not a customer of this store or the reads failed (Flutter's «No pudimos
/// abrir esta cuenta»). The token is never kept nor written to a log; the
/// answer is `no-store`. `pending: true` says this browser still has to
/// close the other sessions after a password change.
Future<Response> portalViewResponse(
  Request request, {
  required PublicReads reads,
}) async {
  final watch = Stopwatch()..start();
  final token = requestBearer(request);
  final body = await requestJsonBody(request);
  final path = body?['path']?.toString() ?? '';
  final page = PortalPage.ofPath(path);
  final query = body?['query']?.toString() ?? '';
  if (token == null || page == null || query.length > 512) {
    return _json(request, 400, {'state': 'invalid'});
  }
  final drawn = await _drawn(
    request,
    reads,
    token,
    page,
    query,
    pending: body?['pending'] == true,
    chatId: portalChatId(path),
    chatWindow: _chatWindow(body?['window']),
  );
  return _json(
    request,
    200,
    drawn.answer,
    timing:
        'data;dur=${drawn.dataMs}, '
        'render;dur=${watch.elapsedMilliseconds - drawn.dataMs}',
  );
}

/// The page read as the customer and drawn: `{html}`, or `{state}` when it
/// cannot be.
Future<({Map<String, Object?> answer, int dataMs})> _drawn(
  Request request,
  PublicReads reads,
  String token,
  PortalPage page,
  String query, {
  bool pending = false,
  String? chatId,
  int chatWindow = portalChatPage,
}) async {
  final watch = Stopwatch()..start();
  final CustomerPortalReads read;
  CustomerChatReads? chat;
  try {
    if (page == PortalPage.chats) {
      // The account (its jobs, for the one a conversation is about) and the
      // conversations, at once.
      final both = await Future.wait<Object>([
        reads.customerPortal(token, files: false),
        reads.customerChats(token, conversationId: chatId, window: chatWindow),
      ]);
      read = both[0] as CustomerPortalReads;
      chat = both[1] as CustomerChatReads;
    } else {
      // Only the summary and the workshop open a job's files.
      read = await reads.customerPortal(
        token,
        files: page == PortalPage.dashboard || page == PortalPage.workshop,
      );
    }
  } on CustomerSessionRefused {
    return (answer: const {'state': 'expired'}, dataMs: 0);
  } on Object catch (error) {
    // A connection error can carry the address (with the customer's ids):
    // only the read that failed, or the kind of error.
    stderr.writeln(
      'portal read failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    return (
      answer: {'state': _passing(error) ? 'unavailable' : 'not-customer'},
      dataMs: 0,
    );
  }
  if (read.profile == null) {
    return (answer: const {'state': 'not-customer'}, dataMs: 0);
  }
  final dataMs = watch.elapsedMilliseconds;
  final rendered = await renderComponent(
    portalView(
      PortalViewData.fromReads(
        page,
        query,
        read,
        pendingRevocation: pending,
        chat: chat == null
            ? null
            : PortalChatData(
                conversations: chat.conversations,
                messages: chat.messages,
                more: chat.more,
                files: chat.files,
                open: chatId,
                window: chatWindow,
                userId: customerSessionClaims(token)['sub']?.toString(),
              ),
      ),
    ),
    request: request,
    standalone: true,
  );
  return (
    answer: <String, Object?>{'html': utf8.decode(rendered.body)},
    dataMs: dataMs,
  );
}

/// `POST /cuenta/accion` with `{path, query, action, values}` and the
/// customer's session: what «Perfil y seguridad» and «Direcciones» save.
/// The forms' rules and words are `customer_portal_forms.dart`'s; every
/// write goes to Supabase as the customer (row security) and names the
/// store; the password goes to Supabase Auth with the same session. Neither
/// the session nor anything typed is kept or written to a log.
///
/// Answers `{errors}` (a field's message), `{html}` (the page drawn again
/// after a save, with a `toast` when Flutter shows one), `{toast}` (a save
/// that failed), the password steps (`{step, notice, error, done}`) or
/// `{state: expired}` when the session must be renewed first.
///
/// The login (4c) asks two things: `check` (`form`: `login`, `register` or
/// `reset`; no session) answers `{errors}` with what each field lacks, by
/// `customer_auth_forms.dart`, before the browser sends anything to Supabase
/// Auth; `enter`, with the session Auth just gave, answers
/// `{state: entered}` or `{state: not-customer}`. Auth itself is called from
/// the browser: it counts attempts by address, and through this server every
/// customer would share one.
Future<Response> portalActionResponse(
  Request request, {
  required PublicReads reads,
}) async {
  final token = requestBearer(request);
  // A chat message can be a few thousand characters (4h).
  final body = await requestJsonBody(request, limit: 32 * 1024);
  final page = PortalPage.ofPath(body?['path']?.toString() ?? '');
  final query = body?['query']?.toString() ?? '';
  final action = body?['action']?.toString() ?? '';
  final rawValues = body?['values'];
  final values = <String, String>{
    if (rawValues is Map)
      for (final entry in rawValues.entries)
        if (entry.value is String || entry.value is bool)
          entry.key.toString(): entry.value.toString(),
  };
  if (action.startsWith('chat-')) {
    if (token == null) return _json(request, 400, {'state': 'invalid'});
    return _json(request, 200, await _chatAction(reads, token, action, values));
  }
  if (values.values.any((value) => value.length > 1024)) {
    return _json(request, 400, {'state': 'invalid'});
  }
  if (action == 'check') {
    final errors = _authCheck(body?['form']?.toString(), values);
    if (errors == null) return _json(request, 400, {'state': 'invalid'});
    return _json(request, 200, {'errors': errors});
  }
  if (action == 'enter' && token != null) {
    try {
      return _json(request, 200, await _enter(reads, token));
    } on CustomerSessionRefused {
      return _json(request, 200, {'state': 'expired'});
    } on Object catch (error) {
      stderr.writeln(
        'portal enter failed: '
        '${error is PublicReadException ? error.message : error.runtimeType}',
      );
      return _json(request, 200, {
        'state': _passing(error) ? 'unavailable' : 'not-customer',
      });
    }
  }
  if (action == 'set-password' && token != null) {
    try {
      return _json(
        request,
        200,
        await _setPassword(
          reads,
          token,
          values,
          invitation: body?['kind'] == 'invitation',
        ),
      );
    } on CustomerSessionRefused {
      return _json(request, 200, {'state': 'expired'});
    } on Object catch (error) {
      stderr.writeln(
        'login set-password failed: '
        '${error is PublicReadException ? error.message : error.runtimeType}',
      );
      return _json(request, 200, {
        'error': _passing(error)
            ? customerAuthStoreBusy
            : customerPasswordUpdateFailed,
      });
    }
  }
  if (token == null || page == null || query.length > 512) {
    return _json(request, 400, {'state': 'invalid'});
  }
  // The redraw keeps this browser's «Quedó pendiente…» (`pending`).
  final pending = body?['pending'] == true;
  Future<Map<String, Object?>> drawn([String? toast]) async {
    final answer = (await _drawn(
      request,
      reads,
      token,
      page,
      query,
      pending: pending,
    )).answer;
    return {...answer, 'toast': ?toast};
  }

  try {
    final answer = switch (action) {
      'profile' => await _saveProfile(reads, token, values, drawn),
      'address-save' => await _saveAddress(reads, token, values, drawn),
      'address-default' => await _addressChange(
        reads,
        token,
        values['id'],
        drawn,
        failed: customerAddressDefaultFailed,
        method: 'PATCH',
        body: const {'is_default': true},
      ),
      'address-delete' => await _addressChange(
        reads,
        token,
        values['id'],
        drawn,
        failed: customerAddressDeleteFailed,
        method: 'DELETE',
      ),
      'password' => await _changePassword(reads, token, values),
      'password-resend' => await _requestCode(reads, token, resend: true),
      'revoke-others' => await _revokeOthers(reads, token),
      _ => null,
    };
    if (answer == null) return _json(request, 400, {'state': 'invalid'});
    return _json(request, 200, answer);
  } on CustomerSessionRefused {
    return _json(request, 200, {'state': 'expired'});
  } on Object catch (error) {
    // A read before the write failed (only its kind is logged): the page
    // says what Flutter says when that save fails.
    stderr.writeln(
      'portal $action failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    return _json(request, 200, {
      'toast': switch (action) {
        'address-save' => customerAddressSaveFailed,
        'address-default' => customerAddressDefaultFailed,
        'address-delete' => customerAddressDeleteFailed,
        _ => customerProfileSaveFailed,
      },
    });
  }
}

typedef _Drawn = Future<Map<String, Object?>> Function([String? toast]);

/// How many messages a conversation draws: what the page asks, in pages of
/// [portalChatPage], up to 500.
int _chatWindow(Object? raw) {
  final value = raw is num ? raw.toInt() : portalChatPage;
  return value.clamp(portalChatPage, 500);
}

/// The longest message the chat sends.
const _chatMessageLimit = 4000;

final _chatKey = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

/// «Soporte»'s actions (4h), each as the customer through the base's own
/// rules: `chat-new` (`create_customer_support_request`, keyed by the
/// browser so a lost answer does not open two), `chat-send` (the message,
/// marked so it is not written twice), `chat-read`
/// (`mark_conversation_read`), `chat-answer` (`respond_to_action_request`)
/// and `chat-file` (a fresh link to a message's file). Answers what the page
/// does next, or the `toast` Flutter shows.
Future<Map<String, Object?>> _chatAction(
  PublicReads reads,
  String token,
  String action,
  Map<String, String> values,
) async {
  String? id(String key) {
    final value = values[key]?.trim().toLowerCase() ?? '';
    return _uuid.hasMatch(value) ? value : null;
  }

  final conversation = id('conversation');
  final message = id('message');
  try {
    switch (action) {
      case 'chat-new':
        final text = values['message']?.trim() ?? '';
        final key = values['key'] ?? '';
        if (text.isEmpty ||
            text.length > _chatMessageLimit ||
            !_chatKey.hasMatch(key)) {
          return const {'state': 'invalid'};
        }
        final answer = await reads
            .customerChatCommand(token, 'create_customer_support_request', {
              'p_initial_message': text,
              'p_context_type': null,
              'p_context_id': null,
              'p_idempotency_key': 'web:$key',
            });
        final created = answer is Map
            ? answer['conversation_id']?.toString()
            : null;
        if (created == null || !_uuid.hasMatch(created)) {
          return const {'toast': customerChatNewFailed};
        }
        return {'conversation': created};
      case 'chat-send':
        final text = values['text']?.trim() ?? '';
        final client = values['client'] ?? '';
        if (conversation == null ||
            text.isEmpty ||
            text.length > _chatMessageLimit ||
            !_chatKey.hasMatch(client)) {
          return const {'state': 'invalid'};
        }
        final sent = await reads.customerChatMessage(
          token,
          conversationId: conversation,
          text: text,
          clientId: client,
        );
        return sent
            ? const {'sent': true}
            : const {'toast': customerChatSendFailed};
      case 'chat-read':
        if (conversation == null || message == null) {
          return const {'state': 'invalid'};
        }
        await reads.customerChatCommand(token, 'mark_conversation_read', {
          'p_conversation_id': conversation,
          'p_read_through_message_id': message,
        });
        return const {'read': true};
      case 'chat-answer':
        final status = values['status'];
        final type = values['type'];
        final note = values['note']?.trim() ?? '';
        if (message == null ||
            (status != 'accepted' && status != 'declined') ||
            (type != 'approve_quote' && type != 'confirm_delivery') ||
            (status == 'declined' &&
                (type != 'approve_quote' || note.isEmpty)) ||
            note.length > 1000) {
          return const {'state': 'invalid'};
        }
        await reads.customerChatCommand(token, 'respond_to_action_request', {
          'p_message_id': message,
          'p_action_type': type,
          'p_status': status,
          'p_metadata_updates': {if (note.isNotEmpty) 'response_note': note},
        });
        return {
          'toast': status == 'accepted'
              ? customerChatAccepted
              : customerChatDeclined,
        };
      case 'chat-file':
        if (conversation == null || message == null) {
          return const {'state': 'invalid'};
        }
        final url = await reads.customerChatFile(
          token,
          conversationId: conversation,
          messageId: message,
        );
        return url == null
            ? const {'toast': customerChatFileRenewFailed}
            : {'url': url};
    }
    return const {'state': 'invalid'};
  } on CustomerSessionRefused {
    return const {'state': 'expired'};
  } on Object catch (error) {
    stderr.writeln(
      'portal $action failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    // A refusal said something about the request; anything else may have
    // been written (Flutter's «Puede haberse guardado»).
    final refused =
        error is PublicReadException &&
        !error.retryable &&
        error.statusCode != null;
    return switch (action) {
      'chat-new' => {
        'toast': customerChatNewFailed,
        if (!refused) 'uncertain': true,
      },
      'chat-send' => {
        'toast': customerChatSendFailed,
        if (!refused) 'uncertain': true,
      },
      'chat-answer' => {
        'toast': !refused
            ? customerChatAnswerUncertain
            : error.code == '23514' && (error.reason ?? '').trim().isNotEmpty
            ? customerChatAnswerRefused(error.reason!)
            : customerChatAnswerFailed,
      },
      'chat-file' => const {'toast': customerChatFileRenewFailed},
      _ => const {'read': false},
    };
  }
}

/// The login's fields that do not pass, by name, or null for a form the
/// login does not have.
Map<String, String>? _authCheck(String? form, Map<String, String> values) =>
    switch (form) {
      'login' => customerAuthErrors(CustomerAuthMode.login, values),
      'register' => customerAuthErrors(CustomerAuthMode.register, values),
      'reset' => {'email': ?customerAuthEmailError(values['email'])},
      _ => null,
    };

/// After Supabase Auth gave a session: the store's customer behind it
/// (created when missing), and the phone typed when the account was opened
/// kept in it when it has none ([customerSignupPhone]); entering never fails
/// for the phone.
Future<Map<String, Object?>> _enter(PublicReads reads, String token) async {
  final profile = await reads.customerEnter(token);
  if (profile == null) return const {'state': 'not-customer'};
  final phone = customerSignupPhone(
    profilePhone: profile['phone'],
    userMetadata: customerSessionClaims(token)['user_metadata'],
  );
  if (phone != null) {
    await _written(
      () => reads
          .customerWrite(
            token,
            method: 'PATCH',
            table: 'customers',
            filters: {
              'id': 'eq.${profile['id']}',
              'tenant_id': 'eq.${profile['tenant_id']}',
            },
            body: {
              'phone': phone,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
          )
          // The customer entered: a refusal here only leaves the phone.
          .catchError(
            (Object _) => false,
            test: (e) => e is CustomerSessionRefused,
          ),
      'signup phone',
    );
  }
  return const {'state': 'entered'};
}

Future<Map<String, Object?>> _saveProfile(
  PublicReads reads,
  String token,
  Map<String, String> values,
  _Drawn drawn,
) async {
  final name = values['name'] ?? '';
  final error = customerProfileNameError(name);
  if (error != null) {
    return {
      'errors': {'name': error},
    };
  }
  final profile = await reads.customerProfile(token);
  if (profile == null) return const {'state': 'not-customer'};
  final saved = await _written(
    () => reads.customerWrite(
      token,
      method: 'PATCH',
      table: 'customers',
      filters: {
        'id': 'eq.${profile['id']}',
        'tenant_id': 'eq.${profile['tenant_id']}',
      },
      body: customerProfileChanges(
        name: name,
        phone: values['phone'] ?? '',
        rut: values['rut'] ?? '',
        now: DateTime.now(),
      ),
    ),
    'profile',
  );
  return saved
      ? drawn(customerProfileSaved)
      : {'toast': customerProfileSaveFailed};
}

Future<Map<String, Object?>> _saveAddress(
  PublicReads reads,
  String token,
  Map<String, String> values,
  _Drawn drawn,
) async {
  final errors = customerAddressErrors(values);
  if (errors.isNotEmpty) return {'errors': errors};
  final id = values['id'] ?? '';
  if (id.isNotEmpty && !_uuid.hasMatch(id)) return const {'state': 'invalid'};
  final profile = await reads.customerProfile(token);
  if (profile == null) return const {'state': 'not-customer'};
  final changes = customerAddressChanges(
    values,
    isDefault: values['is_default'] == 'true',
    postalCode: values['postal_code'],
    now: DateTime.now(),
  );
  final customer = '${profile['id']}';
  final tenant = '${profile['tenant_id']}';
  final saved = await _written(
    () => id.isEmpty
        ? reads.customerWrite(
            token,
            method: 'POST',
            table: 'customer_addresses',
            body: {...changes, 'customer_id': customer, 'tenant_id': tenant},
          )
        : reads.customerWrite(
            token,
            method: 'PATCH',
            table: 'customer_addresses',
            filters: {
              'id': 'eq.$id',
              'customer_id': 'eq.$customer',
              'tenant_id': 'eq.$tenant',
            },
            body: changes,
          ),
    'address',
  );
  return saved ? drawn() : {'toast': customerAddressSaveFailed};
}

/// «Usar como principal» (the database clears the others:
/// `ensure_single_default_address`) or «Eliminar».
Future<Map<String, Object?>> _addressChange(
  PublicReads reads,
  String token,
  String? id,
  _Drawn drawn, {
  required String failed,
  required String method,
  Map<String, Object?>? body,
}) async {
  if (id == null || !_uuid.hasMatch(id)) return const {'state': 'invalid'};
  final profile = await reads.customerProfile(token);
  if (profile == null) return const {'state': 'not-customer'};
  final done = await _written(
    () => reads.customerWrite(
      token,
      method: method,
      table: 'customer_addresses',
      filters: {
        'id': 'eq.$id',
        'customer_id': 'eq.${profile['id']}',
        'tenant_id': 'eq.${profile['tenant_id']}',
      },
      body: body,
    ),
    'address',
  );
  return done ? drawn() : {'toast': failed};
}

/// A write that failed on its way is a failed save (only its kind is
/// logged); a refused session is renewed by the page.
Future<bool> _written(Future<bool> Function() write, String what) async {
  try {
    return await write();
  } on CustomerSessionRefused {
    rethrow;
  } on Object catch (error) {
    stderr.writeln(
      'portal $what write failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    return false;
  }
}

/// The login's link that sets a password (`completePasswordRecovery`,
/// `completeInvitedFirstPassword`), with the session the link itself gave
/// (the page keeps it in memory, never as the browser's session): an
/// invitation first makes the account this store's customer, then the
/// password changes and every session closes, the link's too (Flutter closed
/// the others, then its own, and stopped if that failed). No verification
/// code: a session the link just opened needs none.
Future<Map<String, Object?>> _setPassword(
  PublicReads reads,
  String token,
  Map<String, String> values, {
  required bool invitation,
}) async {
  if (invitation) {
    final entered = await _enter(reads, token);
    if (entered['state'] != 'entered') {
      return {
        'error': entered['state'] == 'unavailable'
            ? customerAuthStoreBusy
            : customerInvitationPrepareFailed,
      };
    }
  }
  return _changePassword(
    reads,
    token,
    values,
    verification: false,
    everywhere: true,
  );
}

/// The password step, or the verification step when the dialog sends the
/// code: `SelfPasswordService.updatePassword` and the dialog's answers.
/// Without [verification] (the login's link) Auth asking for a code is an
/// answer like any other refusal.
///
/// [everywhere] closes this session as well as the others once it changed.
Future<Map<String, Object?>> _changePassword(
  PublicReads reads,
  String token,
  Map<String, String> values, {
  bool verification = true,
  bool everywhere = false,
}) async {
  final password = values['password'] ?? '';
  final code = values['code'];
  final verifying = code != null;
  final passwordError = AuthInputValidation.validatePassword(
    password,
    isNewPassword: true,
  );
  if (!verifying) {
    final confirmError = AuthInputValidation.validatePasswordConfirmation(
      values['confirm'],
      password: password,
    );
    if (passwordError != null || confirmError != null) {
      return {
        'errors': {'password': ?passwordError, 'confirm': ?confirmError},
      };
    }
  } else {
    final codeError = customerVerificationCodeError(code);
    if (codeError != null) {
      return {
        'errors': {'code': codeError},
      };
    }
    if (passwordError != null) {
      return {'error': customerVerificationCheckFailed};
    }
  }
  final CustomerAuthAnswer answer;
  try {
    answer = await reads.customerAuth(
      token,
      CustomerAuthCall.updatePassword,
      body: {'password': password, if (verifying) 'nonce': code.trim()},
    );
  } on CustomerSessionRefused {
    rethrow;
  } on Object catch (error) {
    // Auth may have changed it before the answer was lost: the page marks
    // the outcome unknown, and a «same password» next time means it did.
    stderr.writeln('portal password change failed: ${error.runtimeType}');
    return {
      'error': verifying
          ? customerVerificationCheckFailed
          : customerPasswordUpdateFailed,
      'uncertain': true,
    };
  }
  if (answer.status < 300) {
    // The password is already changed: whatever happens next never asks
    // for it again, only for closing the other sessions.
    return _afterPasswordChange(reads, token, everywhere: everywhere);
  }
  final issue = selfPasswordIssueOf(code: answer.code, message: answer.message);
  if (issue == SelfPasswordUpdateIssue.samePassword &&
      values['uncertain'] == 'true') {
    // The attempt whose answer was lost did change it: only the other
    // sessions are left.
    return _afterPasswordChange(reads, token, everywhere: everywhere);
  }
  if (verifying) return {'error': customerVerificationIssueMessage(issue)};
  if (verification &&
      issue == SelfPasswordUpdateIssue.reauthenticationRequired) {
    return _requestCode(reads, token);
  }
  return {'error': customerPasswordIssueMessage(issue)};
}

Future<Map<String, Object?>> _afterPasswordChange(
  PublicReads reads,
  String token, {
  bool everywhere = false,
}) async {
  final revoked = await _signOutOthers(reads, token, everywhere: everywhere);
  return revoked == true
      ? const {'done': true, 'toast': customerPasswordUpdated}
      : const {'step': 'revocation', 'pending': true};
}

/// True when the other sessions closed, false when Auth refused, null when
/// it could not be asked.
Future<bool?> _signOutOthers(
  PublicReads reads,
  String token, {
  bool everywhere = false,
}) async {
  try {
    final answer = await reads.customerAuth(
      token,
      everywhere
          ? CustomerAuthCall.signOutEverywhere
          : CustomerAuthCall.signOutOthers,
    );
    return answer.status < 300;
  } on Object catch (error) {
    stderr.writeln('portal sign-out of others failed: ${error.runtimeType}');
    return null;
  }
}

/// Asks Auth to mail the code (`reauthenticate`): the verification step.
Future<Map<String, Object?>> _requestCode(
  PublicReads reads,
  String token, {
  bool resend = false,
}) async {
  try {
    final answer = await reads.customerAuth(
      token,
      CustomerAuthCall.reauthenticate,
    );
    if (answer.status < 300) {
      return {
        'step': 'verification',
        'notice': resend
            ? customerVerificationResent
            : customerVerificationSent,
      };
    }
    return {
      'step': 'verification',
      'error': customerReauthenticationRequestMessage(answer.code),
    };
  } on CustomerSessionRefused {
    rethrow;
  } on Object catch (error) {
    stderr.writeln('portal code request failed: ${error.runtimeType}');
    return const {
      'step': 'verification',
      'error': customerVerificationSendFailedOffline,
    };
  }
}

/// «Reintentar cierre»: only the other sessions, never the password again.
Future<Map<String, Object?>> _revokeOthers(
  PublicReads reads,
  String token,
) async => switch (await _signOutOthers(reads, token)) {
  true => const {'done': true, 'toast': customerPasswordUpdated},
  false => const {'error': customerRevocationRetryFailed},
  null => const {'error': customerRevocationRetryBroken},
};

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// `POST /cuenta/archivo` with `{reference}` and the session: a fresh link
/// to one of a job's files (`WorkshopAssetService.resolve`), `{url}`.
Future<Response> portalFileResponse(
  Request request, {
  required PublicReads reads,
}) async {
  final token = requestBearer(request);
  final reference =
      (await requestJsonBody(request))?['reference']?.toString() ?? '';
  if (token == null || reference.isEmpty || reference.length > 1024) {
    return _json(request, 400, {'state': 'invalid'});
  }
  try {
    final url = await reads.customerJobFile(token, reference);
    return url == null
        ? _json(request, 404, {'state': 'unavailable'})
        : _json(request, 200, {'url': url});
  } on CustomerSessionRefused {
    return _json(request, 401, {'state': 'expired'});
  } on Object catch (error) {
    stderr.writeln('portal file failed: ${error.runtimeType}');
    return _json(request, 503, {'state': 'unavailable'});
  }
}

/// The session in the `authorization` header, or null when there is none
/// or it cannot be one.
String? requestBearer(Request request) {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return null;
  final token = header.substring(7).trim();
  return token.length < 40 || token.length > 4096 ? null : token;
}

/// The JSON object a request sends, read up to [limit] bytes and never
/// further: a larger body is dropped while it arrives.
Future<Map<String, Object?>?> requestJsonBody(
  Request request, {
  int limit = 4096,
}) async {
  try {
    final raw = await request
        .read()
        .fold<List<int>>([], (all, chunk) {
          if (all.length + chunk.length > limit) throw const FormatException();
          return all..addAll(chunk);
        })
        .timeout(const Duration(seconds: 10));
    final decoded = jsonDecode(utf8.decode(raw));
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } on Object {
    return null;
  }
}

Response _json(
  Request request,
  int status,
  Map<String, Object?> value, {
  String? timing,
}) {
  final body = utf8.encode(jsonEncode(value));
  final accepts = (request.headers['accept-encoding'] ?? '').contains('gzip');
  final gzipped = accepts && body.length > 1024 ? gzip.encode(body) : null;
  return Response(
    status,
    body: gzipped ?? body,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-robots-tag': 'noindex',
      'vary': 'accept-encoding',
      'content-encoding': ?(gzipped == null ? null : 'gzip'),
      'server-timing': ?timing,
    },
  );
}

/// A failure that says nothing about the customer: the database busy or
/// failing, or no connection to it. The page says «try again in a moment»,
/// never «this session is not a customer here».
bool _passing(Object error) =>
    (error is PublicReadException && error.retryable) ||
    error is TimeoutException ||
    error is SocketException ||
    error is HttpException;
