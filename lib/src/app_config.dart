// API key for server-side style calls (e.g. Geocoding).
// Set via: flutter run --dart-define=MAPS_API_KEY=your_key
// Or run tool/inject_api_keys.dart which writes this file (gitignored copy).
const String kMapsApiKey = String.fromEnvironment(
  'MAPS_API_KEY',
  defaultValue: '',
);

/// Firebase Cloud Function proxy URL (fixes wrong-country geocode on web).
/// Set via: --dart-define=FIREBASE_PROXY_URL=https://us-central1-YOUR_PROJECT.cloudfunctions.net/mapsProxy
const String kFirebaseProxyUrl = String.fromEnvironment(
  'FIREBASE_PROXY_URL',
  defaultValue: '',
);
