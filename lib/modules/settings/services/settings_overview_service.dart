import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_profile.dart';
import 'company_profile_service.dart';
import 'meta_settings_service.dart';

/// What the settings start page says about the shop's setup: the company,
/// who has access, the last backup and the messaging channels.
///
/// Each part is read on its own and is null when it could not be read, so a
/// table the operator cannot see blanks one figure, never the page.
@immutable
class SettingsOverview {
  const SettingsOverview({
    this.company,
    this.users,
    this.backup,
    this.channels,
  });

  final CompanyProfile? company;
  final SettingsUsersOverview? users;
  final SettingsBackupOverview? backup;
  final SettingsChannelsOverview? channels;
}

@immutable
class SettingsUsersOverview {
  const SettingsUsersOverview({required this.active, required this.roles});

  final int active;
  final Set<String> roles;
}

@immutable
class SettingsBackupOverview {
  const SettingsBackupOverview({
    required this.lastBackupAt,
    required this.scheduled,
  });

  /// The newest copy that finished (completed or later restored).
  final DateTime? lastBackupAt;

  /// Whether an automatic backup schedule is on.
  final bool scheduled;

  /// A month without a copy, or no copy at all, needs the owner's eye.
  bool isStale(DateTime now) =>
      lastBackupAt == null || now.difference(lastBackupAt!).inDays > 30;
}

@immutable
class SettingsChannelsOverview {
  const SettingsChannelsOverview({
    required this.whatsappConnected,
    required this.meta,
  });

  final bool whatsappConnected;
  final List<MetaChannelStatus> meta;

  /// WhatsApp, Instagram and Messenger: the three the shop answers on.
  int get total => 3;

  int connectedAt(DateTime now) =>
      (whatsappConnected ? 1 : 0) +
      MetaChannelProvider.values
          .where((provider) => _connected(provider, now))
          .length;

  /// The Meta channels whose authorization ran out.
  List<MetaChannelProvider> expiredAt(DateTime now) => [
        for (final provider in MetaChannelProvider.values)
          if (meta.any(
            (channel) =>
                channel.provider == provider &&
                channel.isActive &&
                channel.authorizationExpiredAt(now),
          ))
            provider,
      ];

  bool _connected(MetaChannelProvider provider, DateTime now) => meta.any(
        (channel) =>
            channel.provider == provider &&
            channel.isActive &&
            !channel.authorizationExpiredAt(now),
      );
}

class SettingsOverviewService {
  SettingsOverviewService({
    SupabaseClient? client,
    CompanyProfileService? companies,
    MetaSettingsGateway? meta,
  })  : _client = client ?? Supabase.instance.client,
        _companies = companies ?? CompanyProfileService(),
        _meta = meta;

  final SupabaseClient _client;
  final CompanyProfileService _companies;
  final MetaSettingsGateway? _meta;

  Future<SettingsOverview> load(String tenantId) async {
    final results = await Future.wait<Object?>([
      _guard(_companies.loadDefaultCompany),
      _guard(() => _users(tenantId)),
      _guard(() => _backup(tenantId)),
      _guard(() => _channels(tenantId)),
    ]);
    return SettingsOverview(
      company: results[0] as CompanyProfile?,
      users: results[1] as SettingsUsersOverview?,
      backup: results[2] as SettingsBackupOverview?,
      channels: results[3] as SettingsChannelsOverview?,
    );
  }

  Future<SettingsUsersOverview> _users(String tenantId) async {
    final rows = await _client
        .from('user_profiles')
        .select('role, is_active')
        .eq('tenant_id', tenantId);
    final active = rows.where((row) => row['is_active'] == true).toList();
    return SettingsUsersOverview(
      active: active.length,
      roles: {
        for (final row in active)
          if ('${row['role'] ?? ''}'.trim().isNotEmpty) '${row['role']}'.trim(),
      },
    );
  }

  Future<SettingsBackupOverview> _backup(String tenantId) async {
    final last = await _client
        .from('database_backups')
        .select('created_at')
        .eq('tenant_id', tenantId)
        .inFilter('status', const ['completed', 'restored'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final schedules = await _client
        .from('backup_schedules')
        .select('enabled')
        .eq('tenant_id', tenantId);
    return SettingsBackupOverview(
      lastBackupAt: DateTime.tryParse('${last?['created_at'] ?? ''}'),
      scheduled: schedules.any((row) => row['enabled'] == true),
    );
  }

  Future<SettingsChannelsOverview> _channels(String tenantId) async {
    final whatsapp = await _client
        .from('whatsapp_channels')
        .select('is_active')
        .eq('tenant_id', tenantId);
    // The same read and rules as Instagram y Messenger's own page.
    final meta = await (_meta ?? MetaSettingsService()).loadSnapshot();
    return SettingsChannelsOverview(
      whatsappConnected: whatsapp.any((row) => row['is_active'] == true),
      meta: meta.channels,
    );
  }

  static Future<Object?> _guard(Future<Object?> Function() read) async {
    try {
      return await read().timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('[SettingsOverview] read failed: ${error.runtimeType}');
      return null;
    }
  }
}
