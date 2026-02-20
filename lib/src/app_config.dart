// API key for server-side style calls (e.g. Geocoding).
// Set via: flutter run --dart-define=MAPS_API_KEY=your_key
// Or run tool/inject_api_keys.dart which writes this file (gitignored copy).
const String kMapsApiKey = String.fromEnvironment(
  'MAPS_API_KEY',
  defaultValue: '',
);
