import 'dart:io';

/// Reads a Dart library's complete source: the main file plus every `part`
/// file it declares (recursively resolved relative to the main file).
///
/// Source-contract tests must keep asserting against the whole library so a
/// mechanical physical partition (`part`/`part of`) can never weaken them.
/// A file without `part` directives returns just its own content, so this is
/// a strict generalization of `File(path).readAsStringSync()`.
String readLibrarySource(String mainPath) {
  final mainFile = File(mainPath);
  final main = mainFile.readAsStringSync();
  final directory = mainFile.parent.path;
  final partDirective = RegExp(r"^part\s+'([^']+)';", multiLine: true);
  final buffer = StringBuffer(main);
  for (final match in partDirective.allMatches(main)) {
    buffer
      ..writeln()
      ..write(File('$directory/${match.group(1)}').readAsStringSync());
  }
  return buffer.toString();
}
