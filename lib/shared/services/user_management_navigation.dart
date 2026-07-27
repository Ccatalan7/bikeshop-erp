import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../utils/responsive_viewport.dart';
import 'workspace_manager.dart';

enum UserManagementAudience { staff, customers, invitations }

enum UserManagementTarget { user, customer, invitation, employee }

@immutable
class UserManagementOpenRequest {
  const UserManagementOpenRequest({
    required this.audience,
    this.target,
    this.targetId,
    this.requestId,
  });

  final UserManagementAudience audience;
  final UserManagementTarget? target;
  final String? targetId;
  final String? requestId;

  String encode() {
    return jsonEncode(<String, Object?>{
      'v': 1,
      'audience': audience.name,
      if (target != null) 'target': target!.name,
      if (targetId?.trim().isNotEmpty == true) 'id': targetId!.trim(),
      if (requestId?.trim().isNotEmpty == true) 'requestId': requestId!.trim(),
    });
  }

  static UserManagementOpenRequest? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) return null;
      final audience = UserManagementAudience.values
          .where((candidate) => candidate.name == decoded['audience'])
          .firstOrNull;
      if (audience == null) return null;

      final targetName = decoded['target'];
      final target = targetName is String
          ? UserManagementTarget.values
              .where((candidate) => candidate.name == targetName)
              .firstOrNull
          : null;
      final targetId =
          decoded['id'] is String ? (decoded['id'] as String).trim() : null;
      if ((target == null) != (targetId == null || targetId.isEmpty)) {
        return null;
      }

      return UserManagementOpenRequest(
        audience: audience,
        target: target,
        targetId: targetId,
        requestId: decoded['requestId'] is String
            ? (decoded['requestId'] as String).trim()
            : null,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Opens the canonical tenant identity workspace with an optional one-use
/// selection request.
///
/// The request lives entirely inside `openRequest`, so WorkspaceManager strips
/// it from the durable workspace identity and never creates one tab per user.
abstract final class UserManagementNavigation {
  static const String route = '/settings/users';

  static String destination({
    UserManagementAudience audience = UserManagementAudience.staff,
    UserManagementTarget? target,
    String? targetId,
    String? requestId,
  }) {
    final request = UserManagementOpenRequest(
      audience: audience,
      target: target,
      targetId: targetId,
      requestId: requestId ?? DateTime.now().microsecondsSinceEpoch.toString(),
    );
    return Uri(
      path: route,
      queryParameters: <String, String>{'openRequest': request.encode()},
    ).toString();
  }

  static void open(
    BuildContext context, {
    UserManagementAudience audience = UserManagementAudience.staff,
    UserManagementTarget? target,
    String? targetId,
  }) {
    final destinationRoute = destination(
      audience: audience,
      target: target,
      targetId: targetId,
    );

    if (ResponsiveViewport.usesCompactShell(context)) {
      context.push(destinationRoute);
      return;
    }

    try {
      context
          .read<WorkspaceManager>()
          .navigateActiveWorkspaceFromSharedLink(destinationRoute);
    } on ProviderNotFoundException {
      context.push(destinationRoute);
    }
  }
}
