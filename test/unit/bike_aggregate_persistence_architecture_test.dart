import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';

void main() {
  test('bike aggregate response parses identity and optional profile together',
      () {
    final aggregate = BikeAggregate.fromJson({
      'bike': {
        'id': 'bike-1',
        'tenant_id': 'tenant-1',
        'customer_id': 'customer-1',
        'brand': 'Example',
        'model': 'Trail',
        'image_urls': <String>[],
        'created_at': '2026-07-14T12:00:00Z',
        'updated_at': '2026-07-14T12:00:00Z',
      },
      'profile': {
        'id': 'profile-1',
        'tenant_id': 'tenant-1',
        'bike_id': 'bike-1',
        'intake_profile': <String, dynamic>{},
        'technical_profile': {
          'values': {'brakeType': 'rim'},
          'sources': {'brakeType': 'mechanic'},
          'confirmed': {'brakeType': true},
        },
        'summary_snapshot': <String, dynamic>{},
        'created_at': '2026-07-14T12:00:00Z',
        'updated_at': '2026-07-14T12:00:00Z',
      },
    });

    expect(aggregate.bike.id, 'bike-1');
    expect(aggregate.profile?.technicalValues['brakeType'], 'rim');
    expect(aggregate.profile?.technicalConfirmed['brakeType'], isTrue);
  });

  test('malformed aggregate profile cannot masquerade as an absent ficha', () {
    expect(
      () => BikeAggregate.fromJson({
        'bike': {
          'id': 'bike-1',
          'tenant_id': 'tenant-1',
          'customer_id': 'customer-1',
          'image_urls': <String>[],
          'created_at': '2026-07-14T12:00:00Z',
          'updated_at': '2026-07-14T12:00:00Z',
        },
        'profile': <String>['invalid'],
      }),
      throwsFormatException,
    );
  });

  test('malformed profile maps force aggregate load failure', () {
    expect(
      () => BikeAggregate.fromJson({
        'bike': {
          'id': 'bike-1',
          'tenant_id': 'tenant-1',
          'customer_id': 'customer-1',
          'image_urls': <String>[],
          'created_at': '2026-07-14T12:00:00Z',
          'updated_at': '2026-07-14T12:00:00Z',
        },
        'profile': {
          'intake_profile': <String, dynamic>{},
          'technical_profile': <String>['invalid'],
          'summary_snapshot': <String, dynamic>{},
        },
      }),
      throwsFormatException,
    );
  });

  test('save response requires durable operation metadata', () {
    final response = {
      'bike': {
        'id': 'bike-1',
        'tenant_id': 'tenant-1',
        'customer_id': 'customer-1',
        'image_urls': <String>[],
        'created_at': '2026-07-14T12:00:00Z',
        'updated_at': '2026-07-14T12:00:00Z',
      },
      'profile': null,
      'replayed': false,
    };

    expect(
      () => BikeAggregateSaveResult.fromJson(response),
      throwsFormatException,
    );
  });

  test('canonical bike form consumes only the atomic aggregate command', () {
    final source = File(
      'lib/modules/bikeshop/pages/bike_form_dialog.dart',
    ).readAsStringSync();

    expect(source, contains('saveBikeAggregate('));
    expect(source, contains('getBikeAggregate('));
    // Lo pendiente de una sesión anterior se resuelve antes de leer la
    // ficha; el recibo tras una respuesta perdida lo busca la bandeja
    // (workshop_command_outbox.dart), no el formulario (ítem 3, 2026-09-27).
    expect(source, contains('resumePendingBikeCommands(bikeId:'));
    expect(source, contains('_hydrateBikeIdentity(aggregate.bike)'));
    expect(source, isNot(contains('bikeshopService.createBike(')));
    expect(source, isNot(contains('bikeshopService.updateBike(')));
    expect(source, isNot(contains('service.upsertBikeProfile(')));
  });

  test('failed aggregate reads cannot masquerade as an editable empty ficha',
      () {
    final source = File(
      'lib/modules/bikeshop/pages/bike_form_dialog.dart',
    ).readAsStringSync();

    expect(source, contains('_BikeAggregateLoadState.failed'));
    expect(source, contains('_BikeAggregateLoadState.outcomeUnknown'));
    expect(source, contains('_loadNewBikeReferences'));
    expect(source, contains('No se pudo cargar la ficha técnica'));
    expect(source, contains('absorbing: _aggregateLoadBlocksEditing'));
    expect(source, contains('_isSaving || _aggregateLoadBlocksEditing'));
    expect(source, contains('Reintentar'));
    expect(source, contains('Confirmar guardado'));
    // Cerrar ya no espera al guardado incierto de una bici que existe: queda
    // respaldado en la bandeja del equipo.
    // Un alta incierta no se cierra: otra alta duplicaría la bici.
    expect(source, contains('canPop: !_closingBlocked'));
    expect(source, contains('_confirmConflictReload'));
    // La decisión de crear lee la bandeja al guardar, no la lista cargada al
    // abrir, y un error de lectura no deja crear (revisión del 2026-09-28).
    final gate = source.substring(
      source.indexOf('Future<bool> _decideCreationAgainstPending()'),
      source.indexOf('bool get _closingBlocked'),
    );
    expect(gate, contains('.pendingBikeCreations(widget.customerId)'));
    expect(gate, contains('} catch (error) {'));
    expect(
      RegExp(r'catch \(error\) \{[^}]*?return false;', dotAll: true)
          .hasMatch(gate),
      isTrue,
    );
    expect(gate, contains('if (state.unreadable)'));
    expect(gate, isNot(contains('_pendingCreations.isEmpty')));
  });

  test('technical bike wizard isolates dropdowns and bounds its desktop map',
      () {
    final source = File(
      'lib/modules/bikeshop/pages/bike_form_dialog.dart',
    ).readAsStringSync();

    expect(source, contains("'code-dropdown:\$label:"));
    expect(source, contains("'string-dropdown:\$label:"));
    expect(source, contains("'int-dropdown:\$label:"));
    expect(source, contains('isExpanded: true'));
    expect(
      source,
      contains(
        'if (showTechnicalControls)\n'
        '            Expanded(\n'
        '              child: _buildTechnicalSchemaNavigator(',
      ),
    );
    expect(source, contains('fitControllerToAvailableHeight: true'));
    expect(source, contains('if (isCompact) ...['));
    expect(source, contains('_buildCompactTechnicalSystemSelector(theme)'));
    expect(source, contains('_buildCompactTechnicalMapDisclosure('));
  });

  test('database snapshot and service expose the shared atomic contract', () {
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();
    final schema = File('supabase/sql/core_schema.sql').readAsStringSync();
    final migration = File(
      'supabase/migrations/20260714120000_add_atomic_bike_aggregate_save.sql',
    ).readAsStringSync();

    final outbox = File(
      'lib/modules/bikeshop/services/workshop_command_outbox.dart',
    ).readAsStringSync();

    // El guardado pasa por la bandeja del equipo, que llama al RPC y, tras
    // una respuesta perdida, a su recibo.
    expect(service, contains('WorkshopCommandKind.bikeAggregateSave'));
    expect(outbox, contains("'save_bike_aggregate'"));
    expect(outbox, contains("'get_bike_aggregate_save_operation'"));
    expect(service, contains("'get_bike_aggregate'"));
    expect(
      schema,
      contains(
        r'\ir ../migrations/20260714120000_add_atomic_bike_aggregate_save.sql',
      ),
    );
    expect(migration, contains('bike_aggregate_save_operations'));
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains('p_expected_profile_updated_at'));
    expect(migration, contains('v_effective_model_id'));
    expect(migration, contains("'profile', p_profile_payload"));
    expect(migration, contains('v_operation.result_snapshot'));
    expect(
      migration,
      contains('Bicycle customer cannot be reassigned'),
    );
    expect(
      migration,
      contains("p_profile_payload ? 'intake_profile'"),
    );
    expect(
      migration,
      contains('Exactly one active employee tenant is required'),
    );
    expect(migration, contains("'replayed', true"));
    expect(
      File(
        'lib/modules/bikeshop/pages/bike_form_dialog.dart',
      ).readAsStringSync(),
      contains('_pendingSaveConfirmedAt'),
    );
  });

  test('every bicycle editor host is registered on the shared contract', () {
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(registry, contains('## Bicycle And Technical-Profile Surfaces'));
    expect(registry, contains('mechanic_job_form_page.dart'));
    expect(registry, contains('client_logbook_page.dart'));
    expect(registry, contains('pegas_table_page.dart'));
    expect(registry, contains('pegas_calendar_widget.dart'));
    expect(registry, contains('saveBikeAggregate'));
  });

  test('el trabajo escribe en la ficha dato por dato, nunca la fila completa',
      () {
    final jobForm = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();

    // La diferencia dato por dato vive en `bikeTechnicalFactsDiff`
    // (bike_technical_fact_patch.dart), con su prueba propia, y viaja con las
    // líneas en `save_mechanic_job_lines_v1` (lo envía la bandeja del
    // equipo), que llama al parche en el servidor.
    final outbox =
        File('lib/modules/bikeshop/services/workshop_command_outbox.dart')
            .readAsStringSync();
    expect(jobForm, contains('bikeTechnicalFactsDiff('));
    expect(outbox, contains("'save_mechanic_job_lines_v1'"));
    expect(outbox, contains("'get_mechanic_job_line_save_v1'"));
    expect(service, isNot(contains("'patch_bike_technical_facts_v1'")));
    expect(outbox, isNot(contains("'patch_bike_technical_facts_v1'")));
    // La reescritura de la fila completa pisaba cambios hechos en la ficha
    // mientras el trabajo estaba abierto (2026-09-27).
    expect(service, isNot(contains('upsertBikeProfile(')));
    // Lo instalado lo escribe el servidor al terminar el trabajo, en la misma
    // transacción (ítem 4, 2026-09-28): la app no lo calcula ni lo envía.
    expect(service, contains("'sync_job_installed_bike_facts_v1'"));
    expect(service, contains('result.installedBikeFacts'));
    expect(service, isNot(contains("source: 'job_completion'")));
    expect(service, isNot(contains('wheelInstalledFacts(')));
  });

  test('las líneas y lo de «Configurar» se guardan en un solo comando', () {
    final jobForm = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    final save = jobForm.substring(
      jobForm.indexOf('Future<void> _saveJob() async {'),
      jobForm.indexOf('Future<void> _openJobStatusConversation()'),
    );

    // Antes cada línea era su propia escritura y la ficha iba después: un
    // corte dejaba la mitad de las líneas, o las líneas sin su ficha
    // (2026-09-28).
    expect(save, isNot(contains('createJobItem(')));
    expect(save, isNot(contains('updateJobItem(')));
    expect(save, isNot(contains('deleteJobItem(')));
    expect(jobForm, isNot(contains('patchBikeTechnicalFacts(')));

    final lastStagedLine = save.lastIndexOf('stagePartItem(item,');
    // El comando de las líneas (antes puede ir uno de sólo cabecera, para
    // registrar una garantía contra la cabecera guardada).
    final command =
        save.indexOf('final lineSave = await _saveLinesWithBikeFacts(');
    expect(command, greaterThan(lastStagedLine));
    expect(command, greaterThan(save.indexOf("clientKey = 'labor-")));
    // Las bicis que salen del trabajo las quita el mismo comando, después de
    // las líneas (ver más abajo); el estado va después del comando.
    expect(save.indexOf('transitionJobStatus('), greaterThan(command));

    // La versión de cada línea sale de lo que se cargó y vuelve con el
    // recibo.
    expect(jobForm, contains('_seenLineVersions'));

    // El comando completo y su llave se respaldan en la bandeja del equipo
    // antes de enviarse: la llave en el formulario no sobrevive a cerrar la
    // app (revisión del 2026-09-28).
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();
    final saveLines = service.substring(
      service.indexOf('Future<JobLineSaveResult> saveJobLines({'),
      service.indexOf('Future<JobLineSaveResult?> settleJobLineSave('),
    );
    expect(saveLines, contains('WorkshopCommandOutbox.shared.submit('));
    expect(saveLines, contains('WorkshopCommandKind.jobLineSave'));
    expect(
      RegExp(r"rpc\(\s*'save_mechanic_job_lines_v1'").hasMatch(service),
      isFalse,
      reason: 'el comando sólo sale por la bandeja',
    );
    // La decisión de garantía también: sólo la bandeja la envía, desde la
    // tabla y desde el formulario (punto 2 del cierre, 2026-09-29).
    final decide = service.substring(
      service.indexOf('Future<Map<String, dynamic>> decideWarrantyClaim({'),
      service.indexOf('Future<Map<String, WarrantyOutcome>> '
          'pendingWarrantyDecisions()'),
    );
    expect(decide, contains('outbox.submit(scope, command)'));
    // La llave que vale es la de la corrida: la bandeja reusa, bajo su
    // candado, una decisión igual pendiente (revisión de Codex, 2026-09-29).
    expect(decide, contains('operationKey: run.command.operationKey,'));
    expect(decide, isNot(contains('warrantyDecisionKeyFor(')));
    final outboxSource = File(
      'lib/modules/bikeshop/services/workshop_command_outbox.dart',
    ).readAsStringSync();
    final enqueue = outboxSource.substring(
      outboxSource.indexOf('Future<String> enqueue('),
      outboxSource.indexOf('/// Respalda y envía.'),
    );
    expect(enqueue, contains('_locked(() async {'));
    expect(enqueue, contains('warrantyDecisionKeyFor(visible, command)'));
    expect(
      RegExp(r"rpc\(\s*'decide_mechanic_job_warranty_claim'").hasMatch(service),
      isFalse,
      reason: 'la decisión sólo sale por la bandeja',
    );
    expect(decide, isNot(contains('_executeWarrantyCommand(')));
    // Un guardado anterior sin respuesta se resuelve antes de escribir nada,
    // y después la decisión de garantía que quedó pendiente: las líneas de
    // este guardado no pueden adelantarse a ella.
    final settle = save.indexOf('await _settlePendingLineSave(');
    expect(settle, greaterThan(0));
    final settleDecision =
        save.indexOf('await _settlePendingWarrantyDecision(');
    expect(
      settleDecision,
      allOf(
        greaterThan(settle),
        lessThan(save.indexOf('await _saveLinesWithBikeFacts(')),
        lessThan(save.indexOf('bikeshopService.uploadJobAttachment(')),
      ),
    );
    expect(settle, lessThan(save.indexOf('await _saveLinesWithBikeFacts(')));
    // Un trabajo nuevo no se crea antes de respaldar nada: su alta va en la
    // bandeja con sus líneas y lo que las sigue, antes del primer envío, y
    // sale primero (cierre del Master Schema, 2026-09-29).
    expect(save, isNot(contains('createJobOnce(')));
    expect(
        settle, lessThan(save.indexOf('bikeshopService.jobCreationCommand(')));
    expect(save, contains('creation: creation,'));
    expect(
      save.indexOf('bikeshopService.jobCreationCommand('),
      lessThan(save.indexOf('await _saveLinesWithBikeFacts(')),
    );
    final createWithLines = service.substring(
      service.indexOf('createJobWithLines({'),
      service.indexOf('Future<MechanicJob?> settleJobCreation('),
    );
    expect(createWithLines, contains('followUps: [lines, ...followUps]'));
    expect(service, isNot(contains("insert('mechanic_jobs'")),
        reason: 'el alta sólo sale por su comando con llave');
    expect(service, isNot(contains('_logJobCreatedBikeEvent')),
        reason: '«Trabajo creado» lo anota el alta, una vez');
    expect(
        settle, lessThan(save.indexOf('bikeshopService.uploadJobAttachment(')));
    // Al abrir el trabajo, lo pendiente se reenvía antes de leer las líneas.
    final load = jobForm.substring(
      jobForm.indexOf('Future<void> _loadExistingJob() async {'),
      jobForm.indexOf('Future<void> _selectCustomer('),
    );
    expect(
      load.indexOf('_resumePendingLineSaves('),
      allOf(greaterThan(0), lessThan(load.indexOf('getJobItems('))),
    );
    // Si la ficha no toma el dato, esa promoción sale del formulario para que
    // el siguiente guardado pase.
    final helper = jobForm.substring(
      jobForm.indexOf('      _saveLinesWithBikeFacts({'),
      jobForm.indexOf('void _forgetWrittenPromotions('),
    );
    expect(helper, contains('on JobLineSaveBikeFactException catch (error)'));
    expect(
        helper, contains('_discardPendingBikeProfilePromotion(error.bikeId)'));
    // …y el trabajo no se guarda hasta reconfirmarla: la línea configurada no
    // queda diciendo otra cosa que la ficha (revisión de Codex, 2026-09-28).
    expect(helper, contains('_bikeFactsAwaitingReconfirmation[error.bikeId]'));
    final block = save.indexOf('_bikesAwaitingReconfirmation()');
    expect(block, greaterThan(0));
    expect(block, lessThan(save.indexOf('_isSaving = true')));
    expect(
      jobForm,
      contains('_bikeFactsAwaitingReconfirmation.remove(reconfirmedBikeId);'),
      reason: 'Configurar sobre la ficha vigente la libera, cambie o no la '
          'ficha',
    );

    // La mano de obra ya guardada se actualiza por su id: recrearla borraba
    // sus tareas.
    expect(save, contains('_laborLinePersistedIds[service.id]'));
    expect(helper, contains("clientKey.startsWith('labor-')"));

    // Una línea nueva no crea tareas desde la descripción de su producto: ni
    // la app (su copia duplicaba y faltaba tras un reinicio, revisiones del
    // 2026-09-28) ni la base (20260929040000: la descripción es instrucción).
    expect(jobForm, isNot(contains('generateAutoTasksFromDescription(')));
    expect(jobForm, isNot(contains('autoTaskDescription')));

    // La cabecera ya no se reescribe entera en una escritura aparte: lo que
    // cambió viaja en el mismo comando, cada campo con el valor que se vio
    // (revisión del 2026-09-28). El descuento va dentro, al final.
    expect(save, isNot(contains('bikeshopService.updateJob(')));
    expect(save, isNot(contains('updateJobDiscount(')));
    expect(save, contains('seen: _headerBaseline,'));
    // Un trabajo recién creado no reescribe su cabecera (los disparadores
    // pudieron normalizarla): sólo el descuento. Uno cuya alta llegó en un
    // intento anterior de este formulario ya es un trabajo guardado: lo
    // editado después viaja como cambio (cierre del Master Schema,
    // 2026-09-29).
    expect(save, contains('edited: savedJobId != null'));
    expect(save, contains('mechanicJobPaymentProtectedUpdatePayload('));
    expect(jobForm, contains('job.persistedHeader'));
    expect(jobForm, contains('void _adoptCreatedJob(MechanicJob job) {'));
    // El recibo adoptado en un guardado posterior mide lo editado contra lo
    // que se mandó, no contra lo que hoy está en pantalla.
    expect(jobForm, contains('_headerShown = save.headerShown ??'));
    expect(
        helper, contains('_headerBaseline = {..._headerBaseline, ...header}'));

    // La línea se carga y se arma con el mismo código que prueba
    // job_form_lines_test.dart (guardar → reabrir → guardar): 1,5 h volvía
    // como 1 h y el guardado siguiente cambiaba el importe.
    expect(jobForm, contains('JobPartItem.fromPersisted('));
    expect(save, contains('jobLineFromPart('));
    expect(save, contains('jobLineFromLabor('));
    expect(jobForm, isNot(contains('quantity.toInt()')));
    expect(jobForm, isNot(contains('class _JobPartItem')));

    // Una cantidad vacía queda como borrador y detiene el guardado antes de
    // escribir nada; antes se guardaba 1 (revisión de Codex, 2026-09-28).
    expect(jobForm, contains('item.withQuantityText(value)'));
    expect(jobForm, isNot(contains('parseJobLineQuantity(value) ?? 1')));

    // La cabecera que repite la primera bici se mide contra lo que se mostró
    // (al cargar y tras cada recibo); con la cabecera, un guardado sin tocar
    // el diagnóstico lo borraba o chocaba (revisión de Codex, 2026-09-28).
    expect('shown: _headerShown,'.allMatches(save).length, 2);
    expect('_headerShown = _headerMirror('.allMatches(jobForm).length, 1);
    // Tras cada recibo, lo que se mandó con él (o lo que está a la vista, si
    // se adopta al tiro).
    expect('_headerShown = save.headerShown ??'.allMatches(jobForm).length, 1);
    expect(save, contains("diagnosis: mirror['diagnosis'] as String?"));

    // Las bicis del trabajo van en el mismo comando: escritas aparte, antes,
    // un guardado rechazado dejaba el diagnóstico de la bici sin lo demás
    // (revisión de Codex, 2026-09-28).
    expect(save, isNot(contains('addBikeToJob(')));
    expect(save, isNot(contains('updateJobBike(')));
    expect(save, isNot(contains('removeBikeFromJob(')));
    expect(save, contains('jobBikes: jobBikesToSave,'));
    // De una bici que estaba viaja sólo lo que cambió, con lo visto al
    // cargar; sale sólo una que el formulario mostraba (una que otro agregó
    // no se toca). Segunda revisión de Codex.
    expect(save, contains('JobBikeToSave.changed('));
    expect(save, contains('seen: _jobBikeBaseline[existingJobBikeId]'));
    expect(save, contains('for (final shownId in _shownJobBikeIds)'));
    // Una bici que la pestaña no mostraba (otro la agregó) no se escribe con
    // la fila releída (tercera revisión de Codex).
    expect(save, contains('!_shownJobBikeIds.contains(existingJobBikeId)'));
    // Un alta que quedó pendiente se resuelve antes que sus líneas; si llegó,
    // el formulario adopta el trabajo creado y lo editado después viaja como
    // cambio, en vez de detenerse y pedir rehacerlo (cierre del Master
    // Schema, 2026-09-29).
    final settlePending = jobForm.substring(
      jobForm.indexOf('Future<void> _settlePendingLineSave('),
      jobForm.indexOf('Future<List<String>> _resumePendingLineSaves('),
    );
    expect(
      settlePending.indexOf('bikeshopService.settleJobCreation(creation)'),
      allOf(
        isNonNegative,
        lessThan(settlePending.indexOf('_adoptCreatedJob(created)')),
        lessThan(settlePending.indexOf('bikeshopService.settleJobLineSave(')),
      ),
    );
    expect(jobForm, isNot(contains('created.recovered')));

    // La factura queda al día en el mismo comando (`p_invoice`): llamada
    // aparte, después, no estaba en la bandeja y un comando confirmado tras
    // cerrar la app dejaba el trabajo sin factura o con la de antes. La
    // llamada del cliente queda sólo para cuando no hubo comando.
    // Salvo cuando la decisión de garantía del mismo guardado es la dueña del
    // documento: va respaldada en la misma escritura que las líneas, detrás
    // de ellas, y el cambio de estado detrás de ella; un cierre entre pasos
    // dejaba el trabajo sin decisión ni documento (punto 2 del cierre,
    // 2026-09-29).
    expect(save, contains('invoice: !warrantyDecisionInSave,'));
    // Con las líneas sin respuesta, el panel dice la decisión pendiente
    // desde ya, leída de la bandeja.
    final linesHelper = jobForm.substring(
      jobForm.indexOf('_saveLinesWithBikeFacts({'),
      jobForm.indexOf('class _JobLinesPendingWithFollowUps'),
    );
    expect(
      linesHelper.indexOf('bikeshopService.pendingWarrantyDecision(jobId)'),
      allOf(
        isNonNegative,
        lessThan(linesHelper.indexOf(
            'throw _JobLinesPendingWithFollowUps(pending, followUps)')),
      ),
    );
    expect(save, contains('followUps: followUps,'));
    expect(
      save.indexOf('followUps.add(bikeshopService.warrantyDecisionCommand('),
      allOf(
        isNonNegative,
        lessThan(save
            .indexOf('followUps.add(bikeshopService.statusTransitionCommand(')),
        lessThan(
            save.indexOf('final lineSave = await _saveLinesWithBikeFacts(')),
      ),
    );
    expect(save.indexOf('if (invoiceOutcome != null) {'),
        allOf(isNonNegative, lessThan(save.indexOf('createInvoiceFromJob('))));
    expect(save, contains('invoiceOutcome.failed'));
    // Con la factura confirmada, lo que se cobra se corrige desde ella: el
    // formulario lo bloquea como con pagos y lo vuelve a leer justo antes de
    // guardar (revisión del 2026-09-28; el comando lo rechaza igual).
    expect(jobForm, contains('linkedInvoiceIsPosted: _linkedInvoiceIsPosted,'));
    expect(
      save.indexOf('_linkedInvoiceIsPosted = linkedInvoiceState.isPosted;'),
      allOf(
        isNonNegative,
        lessThan(
            save.indexOf('final lineSave = await _saveLinesWithBikeFacts(')),
      ),
    );

    // El alta lleva un id elegido una vez por formulario, y ese id es la
    // llave de su comando: una respuesta perdida seguida de «Guardar»
    // devuelve el recibo del alta en vez de crear otro trabajo, y el recibo
    // se lee por llave y taller (cierre del Master Schema, 2026-09-29), con
    // el contenido del alta: la bandeja lo consulta y lo valida, también
    // cuando otra pestaña ya la sacó (revisión de Codex del alta).
    expect(save, contains('id: savedJobId ?? _newJobId,'));
    final creationCommand = service.substring(
      service.indexOf('PendingWorkshopCommand jobCreationCommand('),
      service.indexOf('PendingWorkshopCommand warrantyRegistrationCommand('),
    );
    expect(creationCommand, contains('operationKey: jobId,'));
    expect(creationCommand, contains("..remove('created_at')"));
    final settleCreation = service.substring(
      service.indexOf('Future<MechanicJob?> settleJobCreation('),
      service.indexOf('Future<void> settleWarrantyRegistration('),
    );
    expect(settleCreation,
        contains('WorkshopCommandOutbox.shared.runOrReconcile('));
    expect(settleCreation, isNot(contains("'get_mechanic_job_creation_v1'")));
    final outbox = File(
      'lib/modules/bikeshop/services/workshop_command_outbox.dart',
    ).readAsStringSync();
    final creationProbe = outbox.substring(
      outbox.indexOf("'get_mechanic_job_creation_v1',"),
      outbox.indexOf('case WorkshopCommandKind.jobWarrantyRegistration:',
          outbox.indexOf("'get_mechanic_job_creation_v1',")),
    );
    expect(creationProbe, contains("'p_job': command.params['p_job'],"));
    expect(outbox, contains("response['payload_matches'] == false"));
    // Un respaldo que falló a medias no olvida sus llaves: el próximo
    // Guardar resuelve primero lo que haya quedado de ellas (revisión de
    // Codex del alta, 2026-09-29).
    final lineSave = jobForm.substring(
      jobForm.indexOf('_saveLinesWithBikeFacts({'),
      jobForm.indexOf(
          '({String operationKey, String? statusId})? _plannedStatusTransition()'),
    );
    final keepsLink = lineSave.substring(
      lineSave.indexOf('} on WorkshopOutboxPersistenceException {'),
      lineSave.indexOf('} catch (_) {'),
    );
    expect(keepsLink, contains('rethrow;'));
    expect(keepsLink, isNot(contains('_pendingLineSave = null')));
    // Tampoco al resolverlas: un segundo fallo local no las olvida, ni la
    // del alta ni las de las líneas (segunda revisión de Codex).
    expect(
        'on WorkshopOutboxPersistenceException {\n'
            .allMatches(settlePending)
            .length,
        2);
    // Un borrado que la plataforma no hizo detiene los siguientes, como una
    // escritura: sin eso el orden de los borrados no protege la cadena.
    final store = outbox.substring(
      outbox.indexOf('Future<void> remove(String key) async {'),
      outbox.indexOf('/// Lo que la bandeja necesita del servidor.'),
    );
    expect(store, contains('removed = await preferences.remove(key);'));
    expect(store, contains('if (!removed) {'));
    expect(
        save.indexOf('_linesWithIncompleteQuantity()'),
        allOf(isNonNegative,
            lessThan(save.indexOf('_settlePendingLineSave(bikeshopService)'))));
  });

  test(
      'an attachment the sweep is deleting never enters a command, and the '
      'forms say so instead of an uncertain save', () {
    // Carrera del barrido de adjuntos (2026-09-29): el barrido marca lo que va
    // a borrar bajo el candado, antes de borrarlo en Storage, y el respaldo
    // rechaza un adjunto nuevo marcado o borrado antes de escribir nada.
    final outbox = File(
      'lib/modules/bikeshop/services/workshop_command_outbox.dart',
    ).readAsStringSync();
    final enqueue = outbox.substring(
      outbox.indexOf('Future<PendingWorkshopCommand> _enqueue('),
      outbox.indexOf('static void _refuseUnavailableImages('),
    );
    expect(
      enqueue.indexOf(
          '_refuseUnavailableImages(state, [requested, ...followUps]);'),
      allOf(isNonNegative, lessThan(enqueue.indexOf('await _save('))),
    );
    final remove = outbox.substring(
      outbox.indexOf('Future<void> _removeOrphans('),
      outbox.indexOf('Future<void> flushAttempts('),
    );
    expect(
      remove.indexOf('deletingAt: current.deletingAt ?? now,'),
      allOf(isNonNegative,
          lessThan(remove.indexOf('await _transport.removeImages('))),
    );
    expect(remove, contains('copyWith(deletedAt: now)'));

    final jobForm = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    final refused = jobForm.substring(
      jobForm.indexOf(
          '} on WorkshopImageUnavailableException catch (unavailable) {'),
      jobForm.indexOf('} on JobCreationPendingException catch (pending) {'),
    );
    expect(refused, contains('_imageUrls.removeWhere('));
    expect(refused, contains('unavailable.toString()'));

    final bikeForm = File(
      'lib/modules/bikeshop/pages/bike_form_dialog.dart',
    ).readAsStringSync();
    expect(bikeForm, contains('unavailable == null &&'));
    expect(bikeForm, contains('_pendingUploadedImageUrls.removeAll(gone);'));

    // La tabla: un dueño por intento de carga, para que el fallo de una no
    // suelte los adjuntos de otra que sigue en curso.
    final table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final attach = table.substring(
      table.indexOf('Future<void> _attachFilesToJob('),
      table.indexOf('Future<void> _releaseTableAttachments('),
    );
    expect(attach, contains('final attachmentOwner = const Uuid().v4();'));
    expect(attach, contains('ownerForm: attachmentOwner,'));
    expect(attach, contains('_releaseTableAttachments(attachmentOwner)'));
    expect(table, isNot(contains('_attachmentOwner')));
  });

  test('debug fixture cannot recreate the paired bike and profile write', () {
    final source = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();

    expect(source, contains('saveBikeAggregate('));
    expect(source, isNot(contains('_ensureDebugBikeProfile(')));
    expect(source, isNot(contains('_bikeshopService.createBike(desiredBike)')));
    expect(
      source,
      isNot(contains('_bikeshopService.upsertBikeProfile(profile)')),
    );
  });
}
