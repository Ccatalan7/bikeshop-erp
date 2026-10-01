import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../models/bikeshop_models.dart' show WarrantyOutcome;
import 'wheel_service_facts.dart';
import 'job_completion_blocked.dart';
import 'workshop_command_outbox.dart';

/// Lo que se le dice al mecánico de un cambio que estaba pendiente en la
/// bandeja del equipo y se volvió a enviar. Sin red no se dice nada salvo que
/// [includeOffline]: la reanudación periódica no repite el mismo aviso cada
/// pocos minutos; la pantalla que se abre sí lo dice una vez.
String? workshopCommandNotice(
  WorkshopCommandRun run, {
  bool includeOffline = false,
}) {
  final notice =
      _orphanNotice(run) ?? _commandNotice(run, includeOffline: includeOffline);
  // Lo que seguía al comando y salió con él sin enviarse se dice en el mismo
  // aviso: quien guardó tiene que volver a pedirlo.
  final dropped = run.droppedFollowUps;
  if (notice == null || dropped.isEmpty) return notice;
  final names = [
    for (final follower in dropped)
      switch (follower.kind) {
        WorkshopCommandKind.jobLineSave => 'las líneas',
        WorkshopCommandKind.jobWarrantyRegistration =>
          'el registro de la garantía',
        WorkshopCommandKind.jobWarrantyDecision => 'la decisión de garantía',
        WorkshopCommandKind.jobStatusTransition => 'el cambio de estado',
        _ => 'otro cambio',
      },
  ];
  return '$notice ${_capitalized(names.join(' y '))} que '
      '${names.length == 1 ? 'lo seguía no se envió' : 'lo seguían no se enviaron'}'
      ': vuelve a pedirlo al guardar de nuevo.';
}

/// Lo que salió sin enviarse porque el comando que iba antes ya no estaba en
/// la bandeja (un corte a mitad de respaldar o de sacar la cadena).
String? _orphanNotice(WorkshopCommandRun run) {
  if (run.outcome != WorkshopCommandOutcome.discarded ||
      run.error is! WorkshopCommandPrerequisiteNotWrittenException) {
    return null;
  }
  final command = run.command;
  final label = command.label?.trim();
  final subject = label?.isNotEmpty == true ? label! : 'Trabajo';
  final what = switch (command.kind) {
    WorkshopCommandKind.jobWarrantyDecision =>
      'la decisión de garantía «${WarrantyOutcome.fromDbValue('${command.params['p_outcome']}').displayName}»',
    WorkshopCommandKind.jobStatusTransition => 'el cambio de estado',
    WorkshopCommandKind.jobLineSave => 'el guardado de las líneas',
    WorkshopCommandKind.jobWarrantyRegistration => 'el registro de la garantía',
    _ => 'un cambio',
  };
  return '$subject: $what no se envió porque lo que iba antes no quedó '
      'guardado en este equipo; vuelve a pedirlo.';
}

String _capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

String? _commandNotice(
  WorkshopCommandRun run, {
  required bool includeOffline,
}) {
  final command = run.command;
  if (command.kind == WorkshopCommandKind.jobCreate) {
    return _jobCreateNotice(run, includeOffline: includeOffline);
  }
  if (command.kind == WorkshopCommandKind.jobWarrantyRegistration) {
    return _warrantyRegistrationNotice(run, includeOffline: includeOffline);
  }
  if (command.kind == WorkshopCommandKind.jobInvoiceContinuation) {
    return _invoiceContinuationNotice(run, includeOffline: includeOffline);
  }
  if (command.kind == WorkshopCommandKind.jobStatusTransition) {
    return _statusTransitionNotice(run, includeOffline: includeOffline);
  }
  if (command.kind == WorkshopCommandKind.jobWarrantyDecision) {
    return _warrantyDecisionNotice(run, includeOffline: includeOffline);
  }
  final isJobLines = command.kind == WorkshopCommandKind.jobLineSave;
  final label = command.label?.trim();
  final subject = label?.isNotEmpty == true
      ? label!
      : (isJobLines ? 'Trabajo' : 'Bicicleta');
  final change = isJobLines ? 'el guardado de las líneas' : 'el cambio';
  final kept =
      isJobLines ? 'Las líneas quedaron guardadas' : 'El cambio quedó guardado';

  // La factura va en el mismo comando: si no se pudo, el guardado igual
  // quedó y su continuación quedó en la bandeja; hay que decirlo.
  final response = run.response;
  final invoice = isJobLines && response != null ? response['invoice'] : null;
  final invoiceError =
      invoice is Map && invoice['action'] == 'failed' ? invoice['error'] : null;
  final invoiceNote = invoiceError != null
      ? ' Su factura no se pudo hacer'
          '${invoiceError is Map && invoiceError['message'] != null ? ' (${_reason(invoiceError['message'])})' : ''}'
          '; quedó pendiente en este equipo y se vuelve a intentar sola.'
      : '';

  switch (run.outcome) {
    case WorkshopCommandOutcome.committed:
      return isJobLines
          ? '$subject: se guardaron las líneas que habían quedado '
              'pendientes.$invoiceNote'
          : '$subject: se guardó el cambio que había quedado pendiente.';
    case WorkshopCommandOutcome.reconciled:
      return '$subject: $change pendiente ya estaba en el servidor; quedó '
          'confirmado.$invoiceNote';
    case WorkshopCommandOutcome.stale:
      return isJobLines
          ? '$subject: las líneas pendientes no se guardaron porque el '
              'trabajo o la ficha de la bici cambió mientras tanto. Ábrelo, '
              'revisa y vuelve a guardar.'
          : '$subject: el cambio pendiente no se guardó porque la bici cambió '
              'mientras tanto. Ábrela, revisa y vuelve a guardar.';
    case WorkshopCommandOutcome.rejected:
      final reason = _reason(run.error);
      return '$subject: el servidor rechazó $change pendiente y no aplicó '
          'nada.${reason == null ? '' : ' $reason'}';
    case WorkshopCommandOutcome.offline:
      if (!includeOffline) return null;
      if (run.error is WorkshopCommandBusyException) {
        return '$subject: otra pestaña abierta lo está enviando; su resultado '
            'se verá al terminar.';
      }
      if (run.error is WorkshopCommandQueuedException) {
        return '$subject: $change quedó en este equipo detrás de uno '
            'anterior sin respuesta que escribe lo mismo; se envía cuando ése '
            'se resuelva.';
      }
      // Sin red o sin respuesta del servidor (un 504): no se sabe si llegó.
      return '$subject: sigue sin respuesta del servidor. $kept en este '
          'equipo; el envío se reintenta solo.';
    case WorkshopCommandOutcome.discarded:
      return null;
  }
}

/// La continuación de la factura: se dice cuando quedó hecha, cuando ya no
/// hacía falta tocarla y cuando el servidor no la acepta. Mientras sigue en
/// `failed`, sólo quien abre el trabajo lo ve ([includeOffline]): la
/// reanudación periódica no repite el mismo aviso.
String? _invoiceContinuationNotice(
  WorkshopCommandRun run, {
  required bool includeOffline,
}) {
  final label = run.command.label?.trim();
  final subject = label?.isNotEmpty == true ? label! : 'Trabajo';
  final invoice = run.response?['invoice'];
  final action = invoice is Map ? invoice['action'] : null;
  switch (run.outcome) {
    case WorkshopCommandOutcome.committed:
    case WorkshopCommandOutcome.reconciled:
      switch (action) {
        case 'created':
        case 'synced':
          return '$subject: su factura, que había quedado pendiente, quedó '
              'al día.';
        case 'posted':
          return '$subject: su factura ya estaba confirmada cuando se pudo '
              'volver a intentar y no se tocó. Revisa que cobre lo mismo que '
              'el trabajo; si no, corrígela desde la factura.';
        default:
          return null;
      }
    case WorkshopCommandOutcome.rejected:
    case WorkshopCommandOutcome.stale:
      final reason = _reason(run.error);
      return '$subject: su factura sigue pendiente y no se pudo volver a '
          'intentar${reason == null ? '' : ' ($reason)'}. Ábrelo y guarda de '
          'nuevo.';
    case WorkshopCommandOutcome.offline:
      if (!includeOffline) return null;
      final error = run.error;
      if (error is WorkshopInvoicePendingException) {
        return '$subject: su factura sigue pendiente (${_reason(error)}). Se '
            'vuelve a intentar sola; resuelve eso y se hará.';
      }
      return '$subject: su factura sigue pendiente; se vuelve a intentar '
          'sola cuando haya conexión.';
    case WorkshopCommandOutcome.discarded:
      return null;
  }
}

/// El cambio de estado que había quedado en la bandeja. Si al terminar el
/// trabajo la ficha no tomó lo instalado, se dice igual que cuando se cambia
/// el estado con la pantalla abierta.
String? _statusTransitionNotice(
  WorkshopCommandRun run, {
  required bool includeOffline,
}) {
  final label = run.command.label?.trim();
  final subject = label?.isNotEmpty == true ? label! : 'Trabajo';
  switch (run.outcome) {
    case WorkshopCommandOutcome.committed:
    case WorkshopCommandOutcome.reconciled:
      final response = run.response;
      final nested = response?['response_snapshot'];
      final snapshot = nested is Map ? nested : response;
      final problems = installedBikeFactProblemMessages(
        snapshot is Map ? snapshot['installed_bike_facts'] : null,
      );
      return '$subject: se aplicó el cambio de estado que había quedado '
          'pendiente.${problems.isEmpty ? '' : ' ${problems.join(' ')}'}';
    case WorkshopCommandOutcome.rejected:
    case WorkshopCommandOutcome.stale:
      final blocked = jobCompletionBlockFrom(run.error);
      if (blocked != null) {
        return '$subject: sigue abierto. Corrige estas líneas y vuelve a '
            'Finalizar o Entregar. ${blocked.problems.join(' ')}';
      }
      final reason = _reason(run.error);
      return '$subject: el cambio de estado pendiente no se aplicó'
          '${reason == null ? '' : ' ($reason)'}. Ábrelo y cámbialo de nuevo.';
    case WorkshopCommandOutcome.offline:
      if (!includeOffline) return null;
      if (run.error is WorkshopCommandQueuedException) {
        return '$subject: el cambio de estado quedó en este equipo detrás de '
            'otro cambio del mismo trabajo que sigue sin respuesta (un '
            'guardado o la decisión de garantía); se aplica cuando ése se '
            'resuelva.';
      }
      return '$subject: el cambio de estado sigue sin respuesta del servidor. '
          'Quedó en este equipo y se envía solo.';
    case WorkshopCommandOutcome.discarded:
      return null;
  }
}

/// La decisión de garantía que había quedado en la bandeja: se dice cuando
/// quedó aplicada (con lo que hizo con el documento), cuando el servidor no la
/// acepta y, al abrir el trabajo, mientras sigue esperando.
String? _warrantyDecisionNotice(
  WorkshopCommandRun run, {
  required bool includeOffline,
}) {
  final label = run.command.label?.trim();
  final subject = label?.isNotEmpty == true ? label! : 'Trabajo';
  final outcome =
      WarrantyOutcome.fromDbValue('${run.command.params['p_outcome']}');
  final decision = '«${outcome.displayName}»';
  switch (run.outcome) {
    case WorkshopCommandOutcome.committed:
    case WorkshopCommandOutcome.reconciled:
      final document = switch (outcome) {
        WarrantyOutcome.covered => ' Su respaldo interno quedó al día.',
        WarrantyOutcome.notCovered =>
          ' Su factura cobrable quedó al día (una factura con pagos no se '
              'toca).',
        WarrantyOutcome.pending => '',
      };
      return '$subject: se aplicó la decisión de garantía $decision que '
          'había quedado pendiente.$document';
    case WorkshopCommandOutcome.rejected:
    case WorkshopCommandOutcome.stale:
      final reason = _reason(run.error);
      return '$subject: la decisión de garantía $decision pendiente no se '
          'aplicó${reason == null ? '' : ' ($reason)'}. Ábrelo y decide de '
          'nuevo.';
    case WorkshopCommandOutcome.offline:
      if (!includeOffline) return null;
      if (run.error is WorkshopCommandQueuedException) {
        return '$subject: la decisión de garantía $decision quedó en este '
            'equipo detrás de otro cambio del mismo trabajo que sigue sin '
            'respuesta; se aplica cuando ése se resuelva.';
      }
      if (run.error is WorkshopCommandBusyException) {
        return '$subject: otra pestaña abierta está enviando la decisión de '
            'garantía; su resultado se verá al terminar.';
      }
      return '$subject: la decisión de garantía $decision sigue sin '
          'respuesta del servidor. Quedó en este equipo con su llave y se '
          'aplica sola.';
    case WorkshopCommandOutcome.discarded:
      return null;
  }
}

/// El alta de un trabajo nuevo que había quedado en la bandeja. Sólo se dice
/// «creado» con el recibo en la mano, con el número que le dio la base.
String? _jobCreateNotice(
  WorkshopCommandRun run, {
  required bool includeOffline,
}) {
  final label = run.command.label?.trim();
  final subject = label?.isNotEmpty == true ? label! : 'Trabajo nuevo';
  switch (run.outcome) {
    case WorkshopCommandOutcome.committed:
    case WorkshopCommandOutcome.reconciled:
      final job = run.response?['job'];
      final number = job is Map ? '${job['job_number'] ?? ''}'.trim() : '';
      return '$subject: se creó el trabajo${number.isEmpty ? '' : ' $number'} '
          'que había quedado pendiente en este equipo; sus líneas van '
          'detrás.';
    case WorkshopCommandOutcome.rejected:
    case WorkshopCommandOutcome.stale:
      final reason = _reason(run.error);
      return '$subject: el trabajo nuevo no se creó'
          '${reason == null ? '' : ' ($reason)'}.';
    case WorkshopCommandOutcome.offline:
      if (!includeOffline) return null;
      return '$subject: el trabajo nuevo sigue sin respuesta del servidor; '
          'todavía no está creado. Quedó en este equipo, con sus líneas, y se '
          'envía solo.';
    case WorkshopCommandOutcome.discarded:
      return null;
  }
}

/// El registro de la garantía de un trabajo nuevo que había quedado en la
/// bandeja.
String? _warrantyRegistrationNotice(
  WorkshopCommandRun run, {
  required bool includeOffline,
}) {
  final label = run.command.label?.trim();
  final subject = label?.isNotEmpty == true ? label! : 'Trabajo';
  switch (run.outcome) {
    case WorkshopCommandOutcome.committed:
    case WorkshopCommandOutcome.reconciled:
      return '$subject: se vinculó la garantía con su trabajo original, que '
          'había quedado pendiente.';
    case WorkshopCommandOutcome.rejected:
    case WorkshopCommandOutcome.stale:
      final reason = _reason(run.error);
      return '$subject: la garantía no se vinculó con su trabajo original'
          '${reason == null ? '' : ' ($reason)'}. Ábrelo y elige de nuevo el '
          'trabajo original.';
    case WorkshopCommandOutcome.offline:
      if (!includeOffline) return null;
      return '$subject: el registro de la garantía sigue sin respuesta del '
          'servidor. Quedó en este equipo y se envía solo.';
    case WorkshopCommandOutcome.discarded:
      return null;
  }
}

/// El motivo en palabras del servidor: de un error de la base, su mensaje, no
/// la forma de depuración con código y detalles vacíos.
String? _reason(Object? error) {
  if (error == null) return null;
  final text =
      (error is PostgrestException ? error.message : error.toString()).trim();
  if (text.isEmpty) return null;
  return text.length <= 160 ? text : '${text.substring(0, 160)}…';
}
