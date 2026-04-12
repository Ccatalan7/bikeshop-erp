import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../modules/bikeshop/services/bikeshop_service.dart';
import '../shared/config/supabase_config.dart';
import '../shared/services/database_service.dart';
import '../shared/services/tenant_service.dart';

const _tenantId = String.fromEnvironment('BACKFILL_TENANT_ID');
const _email = String.fromEnvironment('BACKFILL_EMAIL');
const _password = String.fromEnvironment('BACKFILL_PASSWORD');
const _limitRaw = String.fromEnvironment('BACKFILL_LIMIT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_tenantId.isEmpty || _email.isEmpty || _password.isEmpty) {
    stderr.writeln(
      'Missing required dart-defines: BACKFILL_TENANT_ID, BACKFILL_EMAIL, BACKFILL_PASSWORD',
    );
    exit(64);
  }

  final limit = int.tryParse(_limitRaw);

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  final client = Supabase.instance.client;
  final tenantService = TenantService();
  final service = BikeshopService(DatabaseService());

  try {
    stdout.writeln('🔐 Signing in as $_email...');
    await client.auth.signInWithPassword(
      email: _email,
      password: _password,
    );

    final actorTenantId = await tenantService.getTenantId();
    if (actorTenantId == null) {
      throw StateError('Authenticated user has no tenant_id');
    }
    if (actorTenantId != _tenantId) {
      throw StateError(
        'Authenticated tenant mismatch. actor=$actorTenantId target=$_tenantId',
      );
    }

    final before = await _collectMetrics(client, _tenantId);
    _printMetrics('Before', before);

    final jobRows = await client
        .from('mechanic_jobs')
        .select('id,job_number,status,completed_at,delivered_at')
        .eq('tenant_id', _tenantId)
        .inFilter('status', ['FINALIZADO', 'ENTREGADO']).order('job_number');

    final jobs = (jobRows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    final targetJobs = limit == null ? jobs : jobs.take(limit).toList();

    stdout.writeln(
      '🚲 Rebuilding bike memory for ${targetJobs.length} completed jobs in tenant $_tenantId',
    );

    final failures = <String>[];
    for (var index = 0; index < targetJobs.length; index++) {
      final job = targetJobs[index];
      final jobId = job['id']?.toString();
      final jobNumber = job['job_number']?.toString() ?? '(sin número)';

      if (jobId == null || jobId.isEmpty) {
        failures.add('$jobNumber:missing-id');
        continue;
      }

      try {
        await service.syncBikeMemoryFromJob(jobId, swallowErrors: false);
      } catch (e) {
        failures.add('$jobNumber:$e');
      }

      final current = index + 1;
      if (current == 1 || current == targetJobs.length || current % 10 == 0) {
        stdout.writeln('   [$current/${targetJobs.length}] $jobNumber');
      }
    }

    final after = await _collectMetrics(client, _tenantId);
    _printMetrics('After', after);

    if (failures.isNotEmpty) {
      stdout.writeln('⚠️ Backfill finished with ${failures.length} failures');
      for (final failure in failures.take(20)) {
        stdout.writeln('   $failure');
      }
      if (failures.length > 20) {
        stdout.writeln('   ... ${failures.length - 20} more');
      }
      exitCode = 2;
    } else {
      stdout.writeln('✅ Backfill finished without per-job failures');
      exitCode = 0;
    }
  } catch (e, stackTrace) {
    stderr.writeln('❌ Bike memory backfill failed: $e');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    service.dispose();
    await client.auth.signOut();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    exit(exitCode);
  }
}

Future<Map<String, int>> _collectMetrics(
  SupabaseClient client,
  String tenantId,
) async {
  final observations = await client
      .from('bike_observations')
      .select('id')
      .eq('tenant_id', tenantId);
  final states = await client
      .from('bike_system_states')
      .select('id')
      .eq('tenant_id', tenantId);
  final interventions = await client
      .from('bike_interventions')
      .select('id')
      .eq('tenant_id', tenantId);
  final lifecycles = await client
      .from('bike_component_lifecycles')
      .select('id,status')
      .eq('tenant_id', tenantId);

  final lifecycleRows = (lifecycles as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  return {
    'observations': (observations as List).length,
    'states': (states as List).length,
    'interventions': (interventions as List).length,
    'lifecycles': lifecycleRows.length,
    'installed_lifecycles':
        lifecycleRows.where((row) => row['status'] == 'installed').length,
  };
}

void _printMetrics(String label, Map<String, int> metrics) {
  stdout.writeln(
    '📊 $label: '
    'observations=${metrics['observations']} '
    'states=${metrics['states']} '
    'interventions=${metrics['interventions']} '
    'lifecycles=${metrics['lifecycles']} '
    'installed=${metrics['installed_lifecycles']}',
  );
}
