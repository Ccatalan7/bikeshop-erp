import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/widgets/vb_notice.dart';

/// **E-04 · `VbNotice`** — contrato del aviso compartido.
///
/// Existe porque el aviso es el componente que más se ha reinventado en este
/// repositorio: había uno en `public_store`, uno en `mail` y uno en `website`,
/// y Nóminas estaba por escribir el cuarto dentro de su diálogo de
/// confirmación. Lo que este contrato fija no es el aspecto sino la
/// **procedencia del color**: cada tono resuelve al rol semántico del tema
/// montado, en los seis presets y en los dos brillos.
///
/// Si alguien pega un hex dentro del widget, aunque se vea idéntico en claro,
/// una de las doce celdas se pone roja.
void main() {
  const tones = <VbNoticeTone, String>{
    VbNoticeTone.info: 'info',
    VbNoticeTone.success: 'success',
    VbNoticeTone.warning: 'warning',
    VbNoticeTone.danger: 'danger',
    VbNoticeTone.neutral: 'neutral',
  };

  VinabikeSemanticTone expected(VinabikeThemeRoles roles, VbNoticeTone tone) {
    switch (tone) {
      case VbNoticeTone.info:
        return roles.info;
      case VbNoticeTone.success:
        return roles.success;
      case VbNoticeTone.warning:
        return roles.warning;
      case VbNoticeTone.danger:
        return roles.danger;
      case VbNoticeTone.neutral:
        return roles.neutral;
    }
  }

  testWidgets(
      'cada tono toma su color del rol semántico, en los 6 presets × 2 brillos',
      (tester) async {
    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.resolve(preset: preset, brightness: brightness);

        for (final entry in tones.entries) {
          final cell = '${preset.code}/${brightness.name}/${entry.value}';

          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: VbNotice(
                    tone: entry.key,
                    title: 'Un título de aviso',
                    body: 'Un cuerpo que explica el aviso.',
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final context = tester.element(find.byType(VbNotice));
          final want = expected(VinabikeThemeRoles.of(context), entry.key);

          // El contenedor externo del aviso: primero en orden de árbol.
          final box = tester
              .widgetList<Container>(
                find.descendant(
                  of: find.byType(VbNotice),
                  matching: find.byType(Container),
                ),
              )
              .first;
          final decoration = box.decoration! as BoxDecoration;

          expect(decoration.color, want.container,
              reason: '$cell: el fondo no viene del rol');
          expect(
            (decoration.border! as Border).top.color,
            want.border,
            reason: '$cell: el borde no viene del rol',
          );

          final title = tester.widget<Text>(
            find.text('Un título de aviso'),
          );
          expect(title.style?.color, want.onContainer,
              reason: '$cell: la tinta del título no viene del rol');
        }
      }
    }
  });

  testWidgets('la geometría es la que publica E-04, no una inventada',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: const Scaffold(
          body: Center(child: VbNotice(title: 'Un aviso')),
        ),
      ),
    );
    await tester.pump();

    final box = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(VbNotice),
            matching: find.byType(Container),
          ),
        )
        .first;
    final decoration = box.decoration! as BoxDecoration;

    // Leídos del archivo de Design: contenedor radius 8, padding 12/13.
    expect(
      decoration.borderRadius,
      BorderRadius.circular(8),
      reason: 'E-04 publica radius 8',
    );
    expect(
      box.padding,
      const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      reason: 'E-04 publica padding 12/13',
    );
  });

  testWidgets(
      'un aviso se anuncia entero: el título sin su cuerpo deja al lector con la alarma y sin la salida',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: const Scaffold(
          body: Center(
            child: VbNotice(
              tone: VbNoticeTone.warning,
              title: '2 pagos pendientes bloquean el cierre',
              body: 'Regístralos o quítalos de la semana.',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel(
        '2 pagos pendientes bloquean el cierre. '
        'Regístralos o quítalos de la semana.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets(
      'el bloque de texto no se anuncia dos veces, y la acción sigue siendo alcanzable',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: Center(
            child: VbNotice(
              title: 'Las horas se editan en Asistencias',
              body: 'Nóminas solo liquida lo que Asistencias cerró.',
              action: TextButton(
                onPressed: () {},
                child: const Text('Abrir Asistencias'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // El nodo padre pone la etiqueta compuesta y EXCLUYE la de sus hijos: si
    // los conservara, un lector de pantalla anunciaría el título dos veces —
    // una dentro del nodo compuesto y otra por su propio Text.
    expect(find.bySemanticsLabel('Las horas se editan en Asistencias'),
        findsNothing);
    expect(
      find.bySemanticsLabel(
        'Las horas se editan en Asistencias. '
        'Nóminas solo liquida lo que Asistencias cerró.',
      ),
      findsOneWidget,
    );

    // Y la acción queda FUERA de ese bloque: excluir la semántica del texto no
    // puede costar la única salida que el aviso ofrece.
    expect(find.bySemanticsLabel('Abrir Asistencias'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('el glifo es decorativo y no se anuncia', (tester) async {
    final handle = tester.ensureSemantics();
    for (final entry in const <VbNoticeTone, String>{
      VbNoticeTone.info: 'i',
      VbNoticeTone.success: '✓',
      VbNoticeTone.warning: '!',
    }.entries) {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: Center(
              child: VbNotice(tone: entry.key, title: 'Un aviso'),
            ),
          ),
        ),
      );
      await tester.pump();

      // Está dibujado…
      expect(find.text(entry.value), findsOneWidget);
      // …y no se anuncia: repite en un carácter lo que el tono ya dice, y
      // «i» suelto antes del aviso no significa nada dicho en voz alta.
      expect(
        find.bySemanticsLabel(entry.value),
        findsNothing,
        reason: 'el glifo de ${entry.key.name} no debe llegar al lector',
      );
    }
    handle.dispose();
  });
}
