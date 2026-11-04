import 'package:http/http.dart' as http;

import 'connection_status.dart';
import 'resilient_http_client.dart';
import 'stage_aware_sender_stub.dart'
    if (dart.library.io) 'stage_aware_sender_io.dart' as platform;
import 'transport_failure.dart';

export 'connection_status.dart';
export 'request_safety.dart';
export 'resilient_http_client.dart';
export 'transport_failure.dart';
export 'unsaved_changes_journal.dart';

/// El emisor de esta plataforma: el de escritorio y teléfono distingue «no
/// salió» de «se cortó»; el del navegador no puede.
StageAwareSender createPlatformStageAwareSender() =>
    platform.createStageAwareSender();

/// Arma el cliente HTTP del ERP y le da al estado de conexión su sonda.
///
/// La sonda pide `/auth/v1/health`: no toca la base, responde en milisegundos
/// y basta para saber que el servidor volvió a estar al alcance.
ResilientHttpClient createErpHttpClient({
  required String supabaseUrl,
  required String apiKey,
  ConnectionStatus? status,
}) {
  final sender = createPlatformStageAwareSender();
  final connection = status ?? ConnectionStatus.instance;
  final healthUrl = Uri.parse('$supabaseUrl/auth/v1/health');
  connection.probe = () async {
    if (ResilientHttpClient.debugSimulatingOffline) return false;
    try {
      final request = http.Request('GET', healthUrl)
        ..headers['apikey'] = apiKey;
      final response = await sender.send(
        request,
        headerTimeout: const Duration(seconds: 8),
        idleTimeout: const Duration(seconds: 8),
      );
      await response.stream.drain<void>();
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  };
  return ResilientHttpClient(sender: sender, status: connection);
}
