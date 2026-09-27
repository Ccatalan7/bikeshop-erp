import 'package:flutter/material.dart';

/// Acciones rápidas del buscador: se escriben con «/» adelante (dueño,
/// 2026-09-26).
///
/// **Por qué existen.** El buscador llega a cualquier cosa escribiendo; las
/// acciones llevan esa misma entrada a *hacer* algo sin ir a buscar dónde.
/// Empezaron por Tareas porque nadie las usaba: el 2026-09-26 llevaban cero
/// tareas en 30 días, y en toda la historia sólo 2 anexadas a un trabajo. El
/// dueño quiere que «a cualquiera que se le ocurra una tarea, ya que está en
/// la aplicación, apriete /t y al tiro».
///
/// **Cómo se agrega una.** Un [GlobalSearchCommand] más en
/// [kGlobalSearchCommands] y su flujo en el panel. El nombre es la palabra que
/// la gente dice, no un código; los alias son las otras formas de decirlo.
@immutable
class GlobalSearchCommand {
  const GlobalSearchCommand({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.aliases = const [],
  });

  /// Identidad estable (el flujo se elige por ella).
  final String id;

  /// Lo que se escribe después de «/» y lo que se lee en la fila.
  final String name;

  /// Qué hace, en una frase del operador.
  final String description;
  final IconData icon;

  /// Otras palabras que la encuentran.
  final List<String> aliases;
}

/// `/tarea`.
const kGlobalSearchTaskCommand = GlobalSearchCommand(
  id: 'tarea',
  name: 'Tarea',
  description: 'Encárgale algo a alguien del equipo',
  icon: Icons.add_task_rounded,
  aliases: ['tareas', 'task', 'encargo', 'pendiente'],
);

/// Todas las acciones, en el orden en que se muestran sin filtro.
const List<GlobalSearchCommand> kGlobalSearchCommands = [
  kGlobalSearchTaskCommand,
];

/// Lo escrito en el buscador, leído como acción rápida.
@immutable
class GlobalSearchCommandInput {
  const GlobalSearchCommandInput._(this.command, this.argument);

  /// Lo escrito después de «/» y antes del primer espacio, normalizado.
  final String command;

  /// Lo que viene después del primer espacio, tal como se escribió. Es el
  /// comienzo del flujo: `/tarea vic` abre Tarea buscando «vic».
  final String argument;

  /// `null` si el texto no empieza con «/».
  static GlobalSearchCommandInput? parse(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('/')) return null;
    final rest = trimmed.substring(1);
    final space = rest.indexOf(' ');
    final head = space < 0 ? rest : rest.substring(0, space);
    final argument = space < 0 ? '' : rest.substring(space + 1).trimLeft();
    return GlobalSearchCommandInput._(normalizeCommandText(head), argument);
  }

  /// Si ya se escribió un espacio, la acción quedó elegida: lo que sigue es
  /// su argumento, no parte del nombre.
  bool get hasArgument => argument.isNotEmpty;
}

/// Minúsculas y sin tildes: «/Tárea» y «/tarea» son lo mismo.
String normalizeCommandText(String value) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final lower = value.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index < 0 ? char : to[index]);
  }
  return buffer.toString();
}

/// Las acciones que calzan con lo escrito, la mejor primero.
///
/// Sin texto, todas. Primero las que *empiezan* con lo escrito (por nombre y
/// después por alias), después las que lo *contienen*. Así `/t` encuentra
/// Tarea aunque mañana exista «Traspaso»: gana la que empieza, y entre dos que
/// empiezan, el orden del catálogo.
List<GlobalSearchCommand> matchGlobalSearchCommands(
  String query, {
  List<GlobalSearchCommand> commands = kGlobalSearchCommands,
}) {
  final needle = normalizeCommandText(query);
  if (needle.isEmpty) return List.unmodifiable(commands);

  int? rank(GlobalSearchCommand command) {
    final name = normalizeCommandText(command.name);
    final aliases = command.aliases.map(normalizeCommandText);
    if (name.startsWith(needle)) return 0;
    if (aliases.any((alias) => alias.startsWith(needle))) return 1;
    if (name.contains(needle)) return 2;
    if (aliases.any((alias) => alias.contains(needle))) return 3;
    return null;
  }

  final ranked = <(int, int, GlobalSearchCommand)>[];
  for (var i = 0; i < commands.length; i++) {
    final score = rank(commands[i]);
    if (score != null) ranked.add((score, i, commands[i]));
  }
  ranked.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
  });
  return List.unmodifiable(ranked.map((entry) => entry.$3));
}
