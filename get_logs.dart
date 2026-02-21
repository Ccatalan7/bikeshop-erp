import 'dart:io';

void main() async {
  final res = await Process.run('grep', ['-A 50', '-B 5', 'Exception', '.app_logs/flutter_run.log']);
  print(res.stdout);
}
