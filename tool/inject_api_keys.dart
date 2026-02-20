// Run from project root: dart run tool/inject_api_keys.dart
// Requires api_keys.env with MAPS_API_KEY=your_key

import 'dart:io';

void main() {
  final root = _findProjectRoot();
  if (root == null) {
    print('Error: Run from project root (where pubspec.yaml is).');
    exit(1);
  }

  final envFile = File('$root/api_keys.env');
  if (!envFile.existsSync()) {
    print('Error: api_keys.env not found. Copy api_keys.env.example to api_keys.env and add your MAPS_API_KEY.');
    exit(1);
  }

  final key = _parseEnv(envFile)['MAPS_API_KEY']?.trim();
  if (key == null || key.isEmpty) {
    print('Error: MAPS_API_KEY is missing or empty in api_keys.env.');
    exit(1);
  }

  // Web: replace placeholder in index.html (do not commit after running)
  final indexPath = '$root/web/index.html';
  final indexFile = File(indexPath);
  if (!indexFile.existsSync()) {
    print('Error: web/index.html not found.');
    exit(1);
  }
  final content = indexFile.readAsStringSync().replaceAll('MAPS_API_KEY_PLACEHOLDER', key);
  indexFile.writeAsStringSync(content);
  print('Injected API key into web/index.html.');

  // Android: ensure local.properties has MAPS_API_KEY
  final localPropsPath = '$root/android/local.properties';
  final localProps = File(localPropsPath);
  final lines = localProps.existsSync()
      ? localProps.readAsStringSync().split('\n')
      : <String>[];
  final keyLine = 'MAPS_API_KEY=$key';
  final newLines = lines.where((l) => !l.startsWith('MAPS_API_KEY=')).toList()..add(keyLine);
  localProps.writeAsStringSync('${newLines.join('\n')}\n');
  print('Updated android/local.properties with MAPS_API_KEY.');

  // iOS: write xcconfig so Debug/Release can include it
  final iosXcconfigPath = '$root/ios/Flutter/GoogleMapsKey.xcconfig';
  File(iosXcconfigPath).writeAsStringSync('MAPS_API_KEY=$key\n');
  print('Updated ios/Flutter/GoogleMapsKey.xcconfig.');

  print('Done. You can run: flutter run -d chrome');
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
