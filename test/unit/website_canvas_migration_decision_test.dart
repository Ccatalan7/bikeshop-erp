import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

/// 7B-3B — the legacy Canvas decision: visible, explicit and reversible.
///
/// Reading never migrates. A document that needs no judgement call can be
/// updated in one operation; an ambiguous one is only ever resolved by an
/// explicit "keep both layers" that chooses nothing; a document without unique
/// identities is not migrated at all. Every transition is one history entry and
/// every one of them is exactly reversible.

Map<String, dynamic> _twin(
  String id, {
  required bool mobile,
  String text = 'Campaña',
  double x = 120,
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'id': id,
    'type': 'text',
    'text': text,
    'x': x,
    'y': 190.0,
    'w': 620.0,
    'h': 130.0,
    'fontSize': mobile ? 42.0 : 58.0,
    'link': '/ofertas',
    'hideOnMobile': !mobile,
    'showOnMobile': mobile,
    ...?extra,
  };
}

/// Everything a safe migration can merge without asking anything.
Map<String, dynamic> _safeDocument() => <String, dynamic>{
      'blockHeight': 480.0,
      'designWidth': 1200.0,
      'mobileDesignWidth': 390.0,
      'elements': <Map<String, dynamic>>[
        _twin('hero_desktop', mobile: false),
        _twin('hero_mobile', mobile: true),
      ],
    };

/// A safe pair AND an ambiguous one, in the same document.
Map<String, dynamic> _ambiguousDocument() => <String, dynamic>{
      'blockHeight': 480.0,
      'designWidth': 1200.0,
      'elements': <Map<String, dynamic>>[
        _twin('hero_desktop', mobile: false),
        _twin('hero_mobile', mobile: true),
        _twin('cta_desktop', mobile: false, text: 'Ver ofertas'),
        _twin('cta_mobile', mobile: true, text: 'Ver'),
      ],
    };

/// Two layers that cannot be told apart.
Map<String, dynamic> _blockedDocument() => <String, dynamic>{
      'blockHeight': 480.0,
      'elements': <Map<String, dynamic>>[
        _twin('hero_desktop', mobile: false),
        _twin('hero_desktop', mobile: true),
      ],
    };

/// A pair of suffixed identities that never used the legacy flags.
///
/// It is still a legacy document — no marker, no canonical override, read with
/// the 640/1024 bands — and it is ambiguous, because nothing says how the two
/// layers split the devices.
Map<String, dynamic> _flaglessTwins({bool sameText = true}) {
  Map<String, dynamic> layer(String id, {required String text}) =>
      <String, dynamic>{
        'id': id,
        'type': 'text',
        'text': text,
        'x': 120.0,
        'y': 190.0,
        'w': 620.0,
        'h': 130.0,
        'link': '/ofertas',
      };

  return <String, dynamic>{
    'blockHeight': 480.0,
    'designWidth': 1200.0,
    'elements': <Map<String, dynamic>>[
      layer('hero_desktop', text: 'Campaña'),
      layer('hero_mobile', text: sameText ? 'Campaña' : 'Campaña móvil'),
    ],
  };
}

/// The shape a persisted PARTIAL migration would have: provenance stamped by
/// the merge of the safe pair, and the ambiguous layers still legacy.
Map<String, dynamic> _partiallyMigrated() =>
    WebsiteCanvasMigration.migrate(_ambiguousDocument()).document;

Map<String, dynamic> _canvasBlock(Map<String, dynamic> document) =>
    <String, dynamic>{
      'id': 'canvas-block',
      'block_type': 'canvas',
      'order_index': 0,
      'is_visible': true,
      'block_data': document,
    };

Map<String, dynamic> _carouselBlock(Map<String, dynamic> document) =>
    <String, dynamic>{
      'id': 'carousel-block',
      'block_type': 'carousel',
      'order_index': 0,
      'is_visible': true,
      'block_data': <String, dynamic>{
        'slides': <Map<String, dynamic>>[
          <String, dynamic>{'useComposition': true, ...document},
          <String, dynamic>{'useComposition': true, ..._safeDocument()},
        ],
      },
    };

WebsiteEditModeProvider _provider(List<Map<String, dynamic>> blocks) {
  return WebsiteEditModeProvider()
    ..enterEditMode(
      blocks,
      const <String, dynamic>{},
      pageId: 'canvas-page',
      pageSlug: 'canvas-page',
    );
}

List<String> _visibleIds(Map<String, dynamic> document, WebsiteViewport view) {
  return WebsiteCanvasResponsiveDocument.visibleLayers(
    data: document,
    viewport: view,
  ).map((layer) => layer.id).toList();
}

List<String> _orderedIds(Map<String, dynamic> document) {
  final raw = document['elements'] as List;
  return raw.map((layer) => (layer as Map)['id'].toString()).toList();
}

Map<String, dynamic> _layerById(Map<String, dynamic> document, String id) {
  final raw = document['elements'] as List;
  return Map<String, dynamic>.from(
    raw.firstWhere((layer) => (layer as Map)['id'] == id) as Map,
  );
}

/// Deep equality that ignores the order of the keys in a JSON object.
///
/// The approved rollback contract already compares documents as maps: a
/// restored alias is the same value whether it is written before or after the
/// layer list, and pinning the byte order would test `jsonEncode`, not the
/// migration.
Matcher _sameDraftAs(String encoded) => equals(jsonDecode(encoded));

Object? _draft(WebsiteEditModeProvider provider) =>
    jsonDecode(jsonEncode(provider.blocks));

void main() {
  group('A · el owner puro clasifica sin tocar el documento', () {
    test('canonical, safe, ambiguous, blocked y migrated', () {
      expect(
        WebsiteCanvasMigration.inspect(<String, dynamic>{
          'canvasResponsiveVersion': 2,
          'elements': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'a', 'type': 'text', 'visible': true},
          ],
        }).state,
        WebsiteCanvasMigrationState.canonical,
      );

      final safe = WebsiteCanvasMigration.inspect(_safeDocument());
      expect(safe.state, WebsiteCanvasMigrationState.safe);
      expect(safe.canMigrateSafely, isTrue);
      expect(safe.issues, isEmpty);
      expect(safe.mergedStems, <String>['hero']);

      final ambiguous = WebsiteCanvasMigration.inspect(_ambiguousDocument());
      expect(ambiguous.state, WebsiteCanvasMigrationState.ambiguous);
      expect(ambiguous.canMigrateSafely, isFalse);
      expect(ambiguous.canMigrateKeepingLayers, isTrue);
      expect(ambiguous.issues.single.code,
          WebsiteCanvasMigrationIssueCode.differingSharedValue);
      expect(ambiguous.issues.single.propertyKey, 'text');

      final blocked = WebsiteCanvasMigration.inspect(_blockedDocument());
      expect(blocked.state, WebsiteCanvasMigrationState.blocked);
      expect(blocked.canMigrateSafely, isFalse);
      expect(blocked.canMigrateKeepingLayers, isFalse);
      expect(blocked.canRestore, isFalse);

      final migrated = WebsiteCanvasMigration.migrate(_safeDocument()).document;
      expect(
        WebsiteCanvasMigration.inspect(migrated).state,
        WebsiteCanvasMigrationState.migrated,
      );
      expect(WebsiteCanvasMigration.inspect(migrated).canRestore, isTrue);
    });

    test('inspeccionar no muta la entrada', () {
      final document = _ambiguousDocument();
      final before = jsonEncode(document);
      WebsiteCanvasMigration.inspect(document);
      WebsiteCanvasMigration.analyze(document);
      expect(jsonEncode(document), before);
    });
  });

  group('B · conservar capas separadas resuelve sin elegir', () {
    test('une lo seguro y convierte lo ambiguo por separado', () {
      final source = _ambiguousDocument();
      final result = WebsiteCanvasMigration.migrateKeepDistinct(source);

      expect(result.changed, isTrue);
      expect(result.mergedStems, <String>['hero'],
          reason: 'el par seguro del mismo documento sí se une');

      final ids = _orderedIds(result.document);
      expect(
        ids,
        <String>['hero', 'cta_desktop', 'cta_mobile'],
        reason: 'las dos identidades ambiguas sobreviven, y en su lugar',
      );

      final cta = (result.document['elements'] as List)
          .map((layer) => Map<String, dynamic>.from(layer as Map))
          .where((layer) => layer['id'].toString().startsWith('cta'))
          .toList();
      expect(cta.first['text'], 'Ver ofertas');
      expect(cta.last['text'], 'Ver');
      for (final layer in cta) {
        expect(layer['link'], '/ofertas', reason: 'el destino viaja intacto');
        expect(layer.containsKey('hideOnMobile'), isFalse);
        expect(layer.containsKey('showOnMobile'), isFalse);
        expect(layer['visible'], isNotNull, reason: 'visibilidad tipada');
      }
      expect(
        WebsiteCanvasMigration.carriesLegacyLayerFlags(result.document),
        isFalse,
      );
    });

    test('la visibilidad efectiva es idéntica en los tres viewports', () {
      final source = _ambiguousDocument();
      final migrated =
          WebsiteCanvasMigration.migrateKeepDistinct(source).document;

      for (final viewport in WebsiteViewport.values) {
        final before = _visibleIds(source, viewport);
        final after = _visibleIds(migrated, viewport);
        expect(
          after.where((id) => id.startsWith('cta')).toList(),
          before.where((id) => id.startsWith('cta')).toList(),
          reason: 'lo que se ve en ${viewport.name} no cambia',
        );
        // El par seguro se unió: una identidad reemplaza a las dos, y sigue
        // siendo visible exactamente en los mismos viewports.
        expect(
          after.contains('hero'),
          before.any((id) => id.startsWith('hero')),
          reason: 'la capa unida se ve donde se veía alguna de las dos',
        );
      }
    });

    test('idempotente, con analyze limpio y rollback exacto', () {
      final source = _ambiguousDocument();
      final migrated =
          WebsiteCanvasMigration.migrateKeepDistinct(source).document;

      final again = WebsiteCanvasMigration.migrateKeepDistinct(migrated);
      expect(again.changed, isFalse);
      expect(jsonEncode(again.document), jsonEncode(migrated));

      final analysis = WebsiteCanvasMigration.analyze(migrated);
      expect(analysis.issues, isEmpty);
      expect(analysis.changed, isFalse);

      expect(
        WebsiteCanvasMigration.expandToLegacy(migrated),
        source,
        reason: 'la vuelta devuelve el documento heredado exacto',
      );
    });

    test('una identidad en conflicto falla cerrado y sin provenance', () {
      final source = _blockedDocument();
      final before = jsonEncode(source);
      final result = WebsiteCanvasMigration.migrateKeepDistinct(source);

      expect(result.changed, isFalse);
      expect(jsonEncode(result.document), before);
      expect(result.document.containsKey(WebsiteCanvasMigration.provenanceKey),
          isFalse);
      expect(
        result.issues.single.code,
        WebsiteCanvasMigrationIssueCode.conflictingIdentity,
      );
    });
  });

  group('C · los comandos del provider', () {
    test('leer el estado no escribe, no ensucia y no notifica', () {
      final provider = _provider(<Map<String, dynamic>>[
        _canvasBlock(_ambiguousDocument()),
      ]);
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);
      var notifications = 0;
      provider.addListener(() => notifications++);

      // Leer el estado, por sí solo, no notifica siquiera.
      for (var read = 0; read < 3; read++) {
        expect(
          provider.canvasMigrationStatus('canvas-block')!.state,
          WebsiteCanvasMigrationState.ambiguous,
        );
      }
      expect(notifications, 0);

      for (final mode in DevicePreviewMode.values) {
        provider.setDevicePreviewMode(mode);
        expect(
          provider.canvasMigrationStatus('canvas-block')!.state,
          WebsiteCanvasMigrationState.ambiguous,
          reason: 'cambiar de viewport no migra ni reclasifica el documento',
        );
      }

      expect(jsonEncode(provider.blocks), before,
          reason: 'ni una sola escritura');
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
    });

    test('seguro: una operación, un deshacer exacto y rollback exacto', () {
      final provider = _provider(<Map<String, dynamic>>[
        _canvasBlock(_safeDocument()),
      ]);
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(provider.migrateCanvasDocument('canvas-block'), isTrue);
      expect(notifications, 1);
      expect(provider.canUndo, isTrue);

      final document = provider.canvasDocument('canvas-block')!;
      expect(_orderedIds(document), <String>['hero']);
      expect(WebsiteCanvasMigration.carriesLegacyLayerFlags(document), isFalse);
      expect(document.containsKey('mobileDesignWidth'), isFalse);
      expect(
        provider.canvasMigrationStatus('canvas-block')!.state,
        WebsiteCanvasMigrationState.migrated,
      );

      // Idempotencia: el segundo intento no crea history ni notificación.
      final settled = jsonEncode(provider.blocks);
      final settledNotifications = notifications;
      expect(provider.migrateCanvasDocument('canvas-block'), isFalse);
      expect(jsonEncode(provider.blocks), settled);
      expect(notifications, settledNotifications);

      expect(provider.restoreCanvasLegacyDocument('canvas-block'), isTrue);
      expect(_draft(provider), _sameDraftAs(before),
          reason: 'restaurar devuelve el documento original');
      expect(provider.restoreCanvasLegacyDocument('canvas-block'), isFalse,
          reason: 'un segundo rollback no tiene nada que hacer');

      provider.undo();
      provider.undo();
      expect(_draft(provider), _sameDraftAs(before));
    });

    test('seguro anidado: sólo el slide direccionado cambia', () {
      final provider = _provider(<Map<String, dynamic>>[
        _carouselBlock(_safeDocument()),
      ]);
      addTearDown(provider.dispose);
      final sibling = jsonEncode(
        provider.canvasDocument('carousel-block', slideIndex: 1),
      );
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(
        provider.migrateCanvasDocument('carousel-block', slideIndex: 0),
        isTrue,
      );
      expect(notifications, 1);
      expect(
        _orderedIds(provider.canvasDocument('carousel-block', slideIndex: 0)!),
        <String>['hero'],
      );
      expect(
        jsonEncode(provider.canvasDocument('carousel-block', slideIndex: 1)),
        sibling,
        reason: 'el slide hermano queda byte a byte',
      );
      expect(
        provider.canvasMigrationStatus('carousel-block', slideIndex: 1)!.state,
        WebsiteCanvasMigrationState.safe,
      );
    });

    test('ambiguo: el migrate seguro falla cerrado y no deja rastro', () {
      final provider = _provider(<Map<String, dynamic>>[
        _canvasBlock(_ambiguousDocument()),
      ]);
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(provider.migrateCanvasDocument('canvas-block'), isFalse);
      expect(jsonEncode(provider.blocks), before);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(notifications, 0);
      expect(
        provider.canvasMigrationStatus('canvas-block')!.state,
        WebsiteCanvasMigrationState.ambiguous,
        reason: 'el rechazo no esconde la ambigüedad tras un marcador',
      );
    });

    test('ambiguo: conservar separadas es una operación y vuelve exacta', () {
      final provider = _provider(<Map<String, dynamic>>[
        _canvasBlock(_ambiguousDocument()),
      ]);
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(
        provider.migrateCanvasDocumentKeepingLayers('canvas-block'),
        isTrue,
      );
      expect(notifications, 1);

      final document = provider.canvasDocument('canvas-block')!;
      expect(
          _orderedIds(document), <String>['hero', 'cta_desktop', 'cta_mobile']);
      expect(WebsiteCanvasMigration.analyze(document).issues, isEmpty);
      expect(
        provider.canvasMigrationStatus('canvas-block')!.state,
        WebsiteCanvasMigrationState.migrated,
      );

      expect(
        provider.migrateCanvasDocumentKeepingLayers('canvas-block'),
        isFalse,
        reason: 'no hay una segunda migración que aplicar',
      );

      provider.undo();
      expect(_draft(provider), _sameDraftAs(before));
    });

    test('identidad en conflicto: ningún comando de migración avanza', () {
      final provider = _provider(<Map<String, dynamic>>[
        _canvasBlock(_blockedDocument()),
      ]);
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(provider.migrateCanvasDocument('canvas-block'), isFalse);
      expect(
        provider.migrateCanvasDocumentKeepingLayers('canvas-block'),
        isFalse,
      );
      expect(provider.restoreCanvasLegacyDocument('canvas-block'), isFalse);

      expect(jsonEncode(provider.blocks), before);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(notifications, 0);
    });
  });

  group('E · una CTA ofrecida siempre puede completarse', () {
    for (final sameText in const <bool>[true, false]) {
      test('gemelos sin banderas (texto ${sameText ? 'igual' : 'distinto'})',
          () {
        final source = _flaglessTwins(sameText: sameText);
        final status = WebsiteCanvasMigration.inspect(source);
        expect(status.state, WebsiteCanvasMigrationState.ambiguous);
        expect(status.canMigrateKeepingLayers, isTrue);

        final result = WebsiteCanvasMigration.migrateKeepDistinct(source);
        expect(
          result.changed,
          isTrue,
          reason: 'la acción que el estado ofrece no puede quedar muerta',
        );

        final document = result.document;
        expect(_orderedIds(document), <String>['hero_desktop', 'hero_mobile'],
            reason: 'ambas identidades y su orden se conservan');
        expect(
          WebsiteCanvasMigration.inspect(document).state,
          WebsiteCanvasMigrationState.migrated,
        );
        expect(
          WebsiteCanvasMigration.carriesLegacyLayerFlags(document),
          isFalse,
        );

        final layers = (document['elements'] as List)
            .map((layer) => Map<String, dynamic>.from(layer as Map))
            .toList();
        expect(layers.first['text'], 'Campaña');
        expect(layers.last['text'], sameText ? 'Campaña' : 'Campaña móvil');
        for (final layer in layers) {
          expect(layer['link'], '/ofertas');
          expect(layer['visible'], isTrue, reason: 'visibilidad tipada');
        }

        for (final viewport in WebsiteViewport.values) {
          expect(
            _visibleIds(document, viewport),
            _visibleIds(source, viewport),
            reason: 'lo visible en ${viewport.name} no cambia',
          );
        }

        expect(
          WebsiteCanvasMigration.migrateKeepDistinct(document).changed,
          isFalse,
          reason: 'idempotente',
        );
        expect(
          WebsiteCanvasMigration.expandToLegacy(document),
          source,
          reason: 'la vuelta devuelve el JSON exacto',
        );
      });
    }

    test('un documento genuinamente canónico no se ofrece por su sufijo', () {
      final canonical = <String, dynamic>{
        ..._flaglessTwins(),
        'canvasResponsiveVersion': 2,
      };
      final status = WebsiteCanvasMigration.inspect(canonical);
      expect(status.state, WebsiteCanvasMigrationState.canonical);
      expect(status.canMigrateKeepingLayers, isFalse);
      expect(status.canMigrateSafely, isFalse);
      expect(status.canRestore, isFalse);
    });
  });

  group('F · la procedencia no tapa un legado residual', () {
    test('provenance con banderas vivas no es «migrado»', () {
      final partial = _partiallyMigrated();
      expect(
        WebsiteCanvasMigration.carriesLegacyLayerFlags(partial),
        isTrue,
        reason: 'el migrate parcial deja las capas ambiguas como estaban',
      );

      final status = WebsiteCanvasMigration.inspect(partial);
      expect(
        status.state,
        WebsiteCanvasMigrationState.ambiguous,
        reason: 'la ambigüedad sigue siendo visible pese al marcador',
      );
      expect(status.canRestore, isFalse);
      expect(status.issues.single.code,
          WebsiteCanvasMigrationIssueCode.differingSharedValue);
    });

    test('conservar separadas sana el parcial y vuelve al original exacto', () {
      final original = _ambiguousDocument();
      final partial = _partiallyMigrated();

      final healed = WebsiteCanvasMigration.migrateKeepDistinct(partial);
      expect(healed.changed, isTrue);
      expect(
        WebsiteCanvasMigration.carriesLegacyLayerFlags(healed.document),
        isFalse,
      );
      expect(
        WebsiteCanvasMigration.inspect(healed.document).state,
        WebsiteCanvasMigrationState.migrated,
      );
      expect(
        _orderedIds(healed.document),
        <String>['hero', 'cta_desktop', 'cta_mobile'],
      );
      expect(
        WebsiteCanvasMigration.expandToLegacy(healed.document),
        original,
        reason: 'el rollback devuelve el documento heredado ORIGINAL, '
            'no el parcial a medio migrar',
      );
    });

    test('el provider nunca persiste un parcial', () {
      final provider = _provider(<Map<String, dynamic>>[
        _canvasBlock(_ambiguousDocument()),
      ]);
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);

      expect(provider.migrateCanvasDocument('canvas-block'), isFalse);
      expect(jsonEncode(provider.blocks), before);

      // Y si un documento parcial llegara de otra parte, el estado lo delata
      // y la decisión deliberada lo sana en una operación.
      final withPartial = _provider(<Map<String, dynamic>>[
        _canvasBlock(_partiallyMigrated()),
      ]);
      addTearDown(withPartial.dispose);

      expect(
        withPartial.canvasMigrationStatus('canvas-block')!.state,
        WebsiteCanvasMigrationState.ambiguous,
      );
      expect(withPartial.migrateCanvasDocument('canvas-block'), isFalse,
          reason: 'el migrate seguro sigue fallando cerrado');
      expect(
        withPartial.migrateCanvasDocumentKeepingLayers('canvas-block'),
        isTrue,
      );
      expect(
        WebsiteCanvasMigration.carriesLegacyLayerFlags(
          withPartial.canvasDocument('canvas-block')!,
        ),
        isFalse,
      );
      expect(withPartial.restoreCanvasLegacyDocument('canvas-block'), isTrue);
      expect(
        withPartial.canvasDocument('canvas-block'),
        _ambiguousDocument(),
        reason: 'restaurar devuelve el heredado original',
      );
    });
  });

  // Durante el rollout una capa heredada puede llevar ya `visible` tipado,
  // escrito por el inspector canónico. La lectura dice «typed primero», así
  // que la migración tiene que medir lo que la capa MUESTRA, no sus banderas.
  group('G · visibilidad mixta: tipada manda, la bandera es respaldo', () {
    Map<String, dynamic> mixed(
      String id, {
      required bool mobile,
      Object? visible,
      Map<String, dynamic>? responsive,
      String text = 'Campaña',
    }) {
      final layer = _twin(id, mobile: mobile, text: text);
      if (visible != null) layer['visible'] = visible;
      if (responsive != null) layer['responsive'] = responsive;
      return layer;
    }

    Map<String, dynamic> documentOf(List<Map<String, dynamic>> layers) =>
        <String, dynamic>{
          'blockHeight': 480.0,
          'designWidth': 1200.0,
          'elements': layers,
        };

    /// Lo que se ve por viewport, con el par fusionado contando como su raíz.
    Map<String, Set<String>> visibleByViewport(Map<String, dynamic> document) {
      return <String, Set<String>>{
        for (final viewport in WebsiteViewport.values)
          viewport.name: _visibleIds(document, viewport)
              .map((id) => id.split('_').first)
              .toSet(),
      };
    }

    test('un gemelo de escritorio oculto por valor tipado sigue oculto', () {
      final source = documentOf(<Map<String, dynamic>>[
        mixed('hero_desktop', mobile: false, visible: false),
        mixed('hero_mobile', mobile: true),
      ]);
      final before = visibleByViewport(source);
      expect(before['desktop'], isEmpty, reason: 'hoy no se ve en escritorio');
      expect(before['mobile'], <String>{'hero'});

      final status = WebsiteCanvasMigration.inspect(source);
      expect(status.state, WebsiteCanvasMigrationState.safe,
          reason: 'oculto no es lo mismo que solapado: se puede fusionar');

      final result = WebsiteCanvasMigration.migrate(source);
      final merged = _layerById(result.document, 'hero');
      expect(merged['visible'], isFalse,
          reason: 'la base es lo que MUESTRA el gemelo de escritorio');
      expect(
        visibleByViewport(result.document),
        before,
        reason: 'ni un píxel cambia en los tres viewports',
      );
      expect(WebsiteCanvasMigration.expandToLegacy(result.document), source);
    });

    test('un gemelo móvil visible en escritorio es solapamiento, no par', () {
      final source = documentOf(<Map<String, dynamic>>[
        mixed('hero_desktop', mobile: false),
        mixed('hero_mobile', mobile: true, visible: true),
      ]);
      final before = visibleByViewport(source);
      expect(
        before['desktop'],
        <String>{'hero'},
        reason: 'el gemelo móvil ya se ve en escritorio por su valor tipado',
      );

      final status = WebsiteCanvasMigration.inspect(source);
      expect(status.state, WebsiteCanvasMigrationState.ambiguous);
      expect(status.issues.single.code,
          WebsiteCanvasMigrationIssueCode.nonComplementaryVisibility);
      expect(status.canMigrateSafely, isFalse,
          reason: 'fusionar borraría una capa que el visitante ve');

      final kept = WebsiteCanvasMigration.migrateKeepDistinct(source);
      expect(kept.changed, isTrue);
      expect(
        _orderedIds(kept.document),
        <String>['hero_desktop', 'hero_mobile'],
      );
      for (final viewport in WebsiteViewport.values) {
        expect(
          _visibleIds(kept.document, viewport),
          _visibleIds(source, viewport),
          reason: 'cada capa sigue exactamente donde estaba en '
              '${viewport.name}',
        );
      }
      expect(WebsiteCanvasMigration.expandToLegacy(kept.document), source);
    });

    test('una capa suelta no pierde ninguna autoridad tipada', () {
      final source = documentOf(<Map<String, dynamic>>[
        mixed(
          'banner_desktop',
          mobile: false,
          visible: true,
          responsive: <String, dynamic>{
            'version': 2,
            'tablet': <String, dynamic>{'visible': false},
            'mobile': <String, dynamic>{'visible': true, 'fontSize': 21.0},
          },
        ),
      ]);
      final before = visibleByViewport(source);
      expect(before['desktop'], <String>{'banner'});
      expect(before['tablet'], isEmpty);
      expect(before['mobile'], <String>{'banner'},
          reason: 'el override tipado gana sobre hideOnMobile');

      final status = WebsiteCanvasMigration.inspect(source);
      expect(status.state, WebsiteCanvasMigrationState.ambiguous);
      expect(status.issues.single.code,
          WebsiteCanvasMigrationIssueCode.missingPair);

      final kept = WebsiteCanvasMigration.migrateKeepDistinct(source);
      final layer = _layerById(kept.document, 'banner_desktop');
      expect(layer['visible'], isTrue);
      expect(
        (layer['responsive'] as Map)['tablet'],
        <String, dynamic>{'visible': false},
        reason: 'el override authored no se pisa',
      );
      expect(
        (layer['responsive'] as Map)['mobile'],
        containsPair('fontSize', 21.0),
        reason: 'ni el resto del contenedor responsive',
      );
      // El `visible: true` de móvil era redundante con la base, y el
      // normalizador canónico lo retira: lo que se dibuja no cambia, y la
      // procedencia guarda el contenedor original para la vuelta.
      expect(
        WebsiteCanvasResponsiveDocument.visibleLayers(
          data: kept.document,
          viewport: WebsiteViewport.mobile,
        ).map((entry) => entry.id),
        <String>['banner_desktop'],
      );
      expect(layer.containsKey('hideOnMobile'), isFalse);
      expect(visibleByViewport(kept.document), before);
      expect(WebsiteCanvasMigration.expandToLegacy(kept.document), source,
          reason: 'la vuelta devuelve el contenedor original exacto');
    });

    test('un alias de raíz residual tampoco se esconde tras la procedencia',
        () {
      final migrated = WebsiteCanvasMigration.migrate(_safeDocument()).document;
      final withAlias = <String, dynamic>{
        ...migrated,
        'mobileFocalPointX': 0.25,
      };

      expect(
        WebsiteCanvasMigration.inspect(withAlias).state,
        isNot(WebsiteCanvasMigrationState.migrated),
        reason: 'queda algo del modelo anterior en la raíz',
      );

      final healed = WebsiteCanvasMigration.migrate(withAlias);
      expect(healed.changed, isTrue);
      expect(healed.document.containsKey('mobileFocalPointX'), isFalse);
      expect(
        WebsiteCanvasMigration.inspect(healed.document).state,
        WebsiteCanvasMigrationState.migrated,
      );
      expect(
        WebsiteCanvasMigration.expandToLegacy(healed.document),
        <String, dynamic>{..._safeDocument(), 'mobileFocalPointX': 0.25},
        reason: 'la vuelta restaura también el alias que había de más',
      );
    });
  });

  test('E · ningún comando de migración guarda: sólo tocan el borrador', () {
    final source = File(
      'lib/modules/website/providers/website_edit_mode_provider.dart',
    ).readAsStringSync();
    final section = source.substring(
      source.indexOf('WebsiteCanvasMigrationStatus? canvasMigrationStatus('),
      source.indexOf('/// Turns a Carousel slide into a CANONICAL'),
    );

    // Los tres pasan por el mismo ejecutor transaccional…
    expect(
      "_runCanvasCommand(".allMatches(section).length,
      3,
      reason: 'migrar, conservar separadas y restaurar son comandos Canvas',
    );
    // …y ninguno llama a persistencia.
    for (final forbidden in const <String>[
      'savePage',
      'saveChanges',
      'WebsiteService',
      'publish',
      'supabase',
    ]) {
      expect(
        section.contains(forbidden),
        isFalse,
        reason: 'un comando de migración nunca guarda ni publica',
      );
    }

    // El estado es una lectura pura: no pasa por el ejecutor de escritura.
    final statusReader = section.substring(
      0,
      section.indexOf('/// Merges the legacy twins'),
    );
    expect(statusReader.contains('_runCanvasCommand('), isFalse);
    expect(statusReader, contains('WebsiteCanvasMigration.inspect('));
  });

  group('D · las bandas del lienzo cambian sólo con la acción explícita', () {
    test('legacy usa 640/1024 y el resultado canónico usa 600/900', () {
      final provider = _provider(<Map<String, dynamic>>[
        _canvasBlock(_safeDocument()),
      ]);
      addTearDown(provider.dispose);

      final legacy = provider.canvasDocument('canvas-block')!;
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(legacy, 620),
        WebsiteViewport.mobile,
        reason: 'un documento heredado conserva la banda de 640',
      );

      provider.migrateCanvasDocument('canvas-block');
      final canonical = provider.canvasDocument('canvas-block')!;
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(canonical, 620),
        WebsiteViewport.tablet,
        reason: 'ya migrado, 620 es tablet por el contrato 600/900',
      );

      provider.restoreCanvasLegacyDocument('canvas-block');
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(
          provider.canvasDocument('canvas-block')!,
          620,
        ),
        WebsiteViewport.mobile,
        reason: 'restaurar devuelve también la clasificación anterior',
      );
    });
  });
}
