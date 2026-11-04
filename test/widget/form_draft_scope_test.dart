import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/form_drafts/form_draft_store.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/form_draft_scope.dart';

class _MemoryDrafts implements FormDraftStore {
  final Map<String, FormDraft> drafts = {};

  @override
  Future<FormDraft?> read(String userId, String key) async =>
      drafts['$userId|$key'];

  @override
  Future<void> remove(String userId, String key) async =>
      drafts.remove('$userId|$key');

  @override
  Future<void> write(FormDraft draft) async =>
      drafts['${draft.userId}|${draft.key}'] = draft;
}

/// Un formulario como los del ERP: el nombre en una variable que se llena
/// por `onChanged`, el teléfono con su controlador y una región.
class _CustomerForm extends StatefulWidget {
  const _CustomerForm({
    super.key,
    required this.scopeKey,
    required this.store,
    required this.user,
    this.phone = '',
    this.region,
    this.onName,
  });

  final GlobalKey<FormDraftScopeState> scopeKey;
  final FormDraftStore store;
  final String user;
  final String phone;
  final String? region;
  final ValueChanged<String>? onName;

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  late final TextEditingController _phone =
      TextEditingController(text: widget.phone);
  late String? _region = widget.region;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDraftScope(
      key: widget.scopeKey,
      draftKey: 'cliente:7',
      store: widget.store,
      currentUserId: () => widget.user,
      child: ListView(
        children: [
          TextFormField(
            decoration: const InputDecoration(labelText: 'Nombre'),
            onChanged: widget.onName,
          ),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Teléfono'),
          ),
          const TextField(
            obscureText: true,
            decoration: InputDecoration(labelText: 'Clave del portal'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _region,
            decoration: const InputDecoration(labelText: 'Región'),
            items: const [
              DropdownMenuItem(value: 'Valparaíso', child: Text('Valparaíso')),
              DropdownMenuItem(value: 'Biobío', child: Text('Biobío')),
            ],
            onChanged: (value) => setState(() => _region = value),
          ),
          Text('región elegida: ${_region ?? '-'}'),
        ],
      ),
    );
  }
}

/// Un documento con líneas: dos «Precio» iguales y unas horas que el
/// formulario llena solo.
class _LinesForm extends StatefulWidget {
  const _LinesForm({super.key, required this.store});

  final FormDraftStore store;

  @override
  State<_LinesForm> createState() => _LinesFormState();
}

class _LinesFormState extends State<_LinesForm> {
  final _hours = TextEditingController();

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDraftScope(
      draftKey: 'trabajo:nuevo',
      store: widget.store,
      currentUserId: () => 'usuario-1',
      child: ListView(
        children: [
          const TextField(decoration: InputDecoration(labelText: 'Precio')),
          const TextField(decoration: InputDecoration(labelText: 'Precio')),
          const TextField(decoration: InputDecoration(labelText: 'Notas')),
          const TextField(
              decoration: InputDecoration(hintText: 'Buscar producto')),
          TextField(
            controller: _hours,
            decoration: const InputDecoration(labelText: 'Horas'),
          ),
          TextButton(
            onPressed: () => _hours.text = '2',
            child: const Text('Elegir mantención'),
          ),
        ],
      ),
    );
  }
}

/// Un trabajo con su diagnóstico en otra pestaña y las líneas aparte.
class _TabbedForm extends StatefulWidget {
  const _TabbedForm(
      {super.key, required this.store, this.showDiagnosis = true});

  final FormDraftStore store;
  final bool showDiagnosis;

  @override
  State<_TabbedForm> createState() => _TabbedFormState();
}

class _TabbedFormState extends State<_TabbedForm> {
  late bool _diagnosis = widget.showDiagnosis;

  @override
  Widget build(BuildContext context) {
    return FormDraftScope(
      draftKey: 'trabajo:9',
      store: widget.store,
      currentUserId: () => 'usuario-1',
      child: ListView(
        children: [
          TextButton(
            onPressed: () => setState(() => _diagnosis = true),
            child: const Text('Abrir diagnóstico'),
          ),
          if (_diagnosis)
            const TextField(
              decoration: InputDecoration(labelText: 'Diagnóstico'),
            ),
          const FormDraftSkip(
            child:
                TextField(decoration: InputDecoration(labelText: 'Repuesto')),
          ),
        ],
      ),
    );
  }
}

void main() {
  late _MemoryDrafts store;
  late GlobalKey<FormDraftScopeState> scopeKey;

  setUp(() {
    store = _MemoryDrafts();
    scopeKey = GlobalKey<FormDraftScopeState>();
  });

  Future<void> open(
    WidgetTester tester, {
    String user = 'usuario-1',
    String phone = '',
    String? region,
    ValueChanged<String>? onName,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: _CustomerForm(
          // Una llave nueva por apertura: es otro formulario, como al volver.
          key: UniqueKey(),
          scopeKey: scopeKey,
          store: store,
          user: user,
          phone: phone,
          region: region,
          onName: onName,
        ),
      ),
    ));
    await tester.pump(); // el primer cuadro: «lo que había»
    await tester.pump(); // la lectura del borrador
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('lo escrito vuelve solo al abrir otra vez, y se puede deshacer',
      (tester) async {
    await open(tester);
    await tester.enterText(field('Nombre'), 'Dora Pérez');
    await tester.pump(const Duration(seconds: 1));
    expect(store.drafts['usuario-1|cliente:7']?.changes['Nombre']?.after,
        'Dora Pérez');

    await close(tester); // se fue la luz, «atrás», la app se cerró…
    String? heard;
    await open(tester, onName: (value) => heard = value);
    expect(find.text('Dora Pérez'), findsOneWidget);
    expect(heard, 'Dora Pérez',
        reason: 'el formulario se entera como si se hubiera escrito');
    expect(
        find.textContaining('Recuperamos lo que escribiste',
            findRichText: true),
        findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(find.text('Dora Pérez'), findsNothing);
    expect(store.drafts, isEmpty);
  });

  testWidgets('lo que otra persona cambió entretanto no se pisa',
      (tester) async {
    await open(tester, phone: '+56 9 1111 1111');
    await tester.enterText(field('Teléfono'), '+56 9 2222 2222');
    await tester.enterText(field('Nombre'), 'Dora');
    await tester.pump(const Duration(seconds: 1));
    await close(tester);

    // Al volver, el registro trae otro teléfono: alguien lo cambió.
    await open(tester, phone: '+56 9 3333 3333');
    expect(find.text('+56 9 3333 3333'), findsOneWidget);
    expect(find.text('Dora'), findsOneWidget);
    expect(
      find.textContaining('no tocamos Teléfono', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('guardar borra el borrador: no se vuelve a ofrecer',
      (tester) async {
    await open(tester);
    await tester.enterText(field('Nombre'), 'Dora');
    await tester.pump(const Duration(seconds: 1));
    scopeKey.currentState!.markSaved();
    await tester.pump();
    expect(store.drafts, isEmpty);

    await close(tester);
    await open(tester);
    expect(find.text('Dora'), findsNothing);
    expect(
        find.textContaining('Recuperamos', findRichText: true), findsNothing);
  });

  testWidgets('una clave nunca queda en el borrador', (tester) async {
    await open(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Clave del portal'), 'secreta');
    await tester.enterText(field('Nombre'), 'Dora');
    await tester.pump(const Duration(seconds: 1));
    final changes = store.drafts['usuario-1|cliente:7']!.changes;
    expect(changes.keys, ['Nombre']);
  });

  testWidgets('lo de otra persona no se le ofrece a quien está conectado',
      (tester) async {
    await open(tester);
    await tester.enterText(field('Nombre'), 'Dora');
    await tester.pump(const Duration(seconds: 1));
    await close(tester);

    await open(tester, user: 'usuario-2');
    expect(find.text('Dora'), findsNothing);
  });

  testWidgets('el selector de región también vuelve', (tester) async {
    await open(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biobío').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await close(tester);

    await open(tester);
    expect(find.text('región elegida: Biobío'), findsOneWidget);
  });

  testWidgets('volver a dejar lo que había borra el borrador', (tester) async {
    await open(tester, phone: '123');
    await tester.enterText(field('Teléfono'), '1234');
    await tester.pump(const Duration(seconds: 1));
    expect(store.drafts, isNotEmpty);
    await tester.enterText(field('Teléfono'), '123');
    await tester.pump(const Duration(seconds: 1));
    expect(store.drafts, isEmpty);
  });

  testWidgets(
      'dos campos con la misma etiqueta, un buscador o lo que el formulario '
      'llena solo no van al borrador', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(body: _LinesForm(store: store)),
    ));
    await tester.pump();
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Precio').first, '5000');
    await tester.enterText(
        find.widgetWithText(TextField, 'Buscar producto'), 'cadena');
    await tester.enterText(
        find.widgetWithText(TextField, 'Notas'), 'Frenos con ruido');
    await tester.tap(find.text('Elegir mantención'));
    await tester.pump(const Duration(seconds: 1));

    final changes = store.drafts['usuario-1|trabajo:nuevo']!.changes;
    expect(changes.keys, ['Notas']);
    expect(changes['Notas']!.after, 'Frenos con ruido');
  });

  testWidgets('lo de una pestaña cerrada vuelve al abrirla; las líneas no',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(body: _TabbedForm(key: UniqueKey(), store: store)),
    ));
    await tester.pump();
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Diagnóstico'), 'Pastillas gastadas');
    await tester.enterText(
        find.widgetWithText(TextField, 'Repuesto'), 'Shimano');
    await tester.pump(const Duration(seconds: 1));
    expect(store.drafts['usuario-1|trabajo:9']!.changes.keys, ['Diagnóstico']);
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: _TabbedForm(key: UniqueKey(), store: store, showDiagnosis: false),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(store.drafts['usuario-1|trabajo:9'], isNotNull,
        reason: 'sigue guardado mientras su pestaña está cerrada');

    await tester.tap(find.text('Abrir diagnóstico'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Pastillas gastadas'), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
  });

  testWidgets('forget borra lo de un formulario que ya se cerró',
      (tester) async {
    FormDrafts.store = store;
    FormDrafts.currentUserId = () => 'usuario-1';
    addTearDown(() {
      FormDrafts.store = SharedPreferencesFormDraftStore();
      FormDrafts.currentUserId = () => null;
    });
    await open(tester);
    await tester.enterText(field('Nombre'), 'Dora');
    await tester.pump(const Duration(seconds: 1));
    await close(tester);
    expect(store.drafts, isNotEmpty);
    await FormDraftScope.forget('cliente:7');
    expect(store.drafts, isEmpty);
  });

  for (final brightness in Brightness.values) {
    testWidgets('el aviso de recuperado se lee (${brightness.name})',
        (tester) async {
      await open(tester, brightness: brightness);
      await tester.enterText(field('Nombre'), 'Dora');
      await tester.pump(const Duration(seconds: 1));
      await close(tester);
      await open(tester, brightness: brightness);
      expect(find.text('Deshacer'), findsOneWidget);
      expect(find.byTooltip('Cerrar aviso'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Queda mientras la persona lee; seguir escribiendo es aceptarlo.
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Deshacer'), findsOneWidget);
      await tester.enterText(field('Nombre'), 'Dora Pérez');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Deshacer'), findsNothing);
    });
  }
}
