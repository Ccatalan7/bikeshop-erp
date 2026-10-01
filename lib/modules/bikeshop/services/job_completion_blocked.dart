import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'wheel_service_facts.dart';

/// A marked part needs correction before FINALIZADO or ENTREGADO can commit.
/// The database rolled back the status, ficha, receipt and any partial writes.
class JobCompletionBlockedException implements Exception {
  const JobCompletionBlockedException(this.problems);

  final List<String> problems;

  @override
  String toString() => 'El trabajo sigue abierto. Corrige las líneas indicadas '
      'y vuelve a finalizar o entregar.';
}

JobCompletionBlockedException? jobCompletionBlockFrom(Object? error) {
  if (error is! PostgrestException ||
      error.code != '23514' ||
      error.hint != 'job_completion_blocked') {
    return null;
  }

  Object? detail = error.details;
  if (detail is String) {
    try {
      detail = jsonDecode(detail);
    } on FormatException {
      detail = null;
    }
  }
  final messages = installedBikeFactProblemMessages(detail);
  return JobCompletionBlockedException(messages.isEmpty
      ? const [
          'Revisa la línea marcada, su bicicleta y su rueda; guarda la '
              'corrección y vuelve a cerrar el trabajo.'
        ]
      : messages);
}
