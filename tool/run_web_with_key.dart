// Run from project root: dart run tool/run_web_with_key.dart
// Reads MAPS_API_KEY from api_keys.env and runs Flutter web (so search works).

import 'dart:io';

void main() async {
  final root = _findProjectRoot();
  if (root == null) {
    print('Error: Run from project root.');
    exit(1);
  }
  final envFile = File('$root/api_keys.env');
  if (!envFile.existsSync()) {
    print('Error: api_keys.env not found. Copy api_keys.env.example to api_keys.env.');
    exit(1);
  }
  final key = _parseEnv(envFile)['MAPS_API_KEY']?.trim();
  if (key == null || key.isEmpty) {
    print('Error: MAPS_API_KEY is missing in api_keys.env.');
    exit(1);
  }
  final process = await Process.start(
    'flutter',
    ['run', '-d', 'chrome', '--dart-define=MAPS_API_KEY=$key'],
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: root,
    runInShell: true,
  );
  exit(await process.exitCode);
}

String? _findProjectRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return null;
}

Map<String, String> _parseEnv(File file) {
  final out = <String, String>{};
  for (final line in file.readAsStringSync().split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final eq = t.indexOf('=');
    if (eq > 0) out[t.substring(0, eq).trim()] = t.substring(eq + 1).trim();
  }
  return out;
}
