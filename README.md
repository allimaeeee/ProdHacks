# prodhacks

Parking recommendations on Google Maps (Flutter — web + Android).

## Running the app

**Prerequisites:** [Flutter SDK](https://docs.flutter.dev/get-started/install) installed and `flutter` on your PATH.

From the project root:

```bash
flutter pub get
```

### Web

```bash
flutter run -d chrome
```

**Search bar:** The map has a search field that uses the Google Geocoding API. To make search work, the app needs your API key at run time. Either:

- **Option A:** `dart run tool/run_web_with_key.dart` (reads key from `api_keys.env` and runs Chrome), or on Windows: `run_web.bat`
- **Option B:** `flutter run -d chrome --dart-define=MAPS_API_KEY=your_key`

Enable these APIs for your key in [Google Cloud Console](https://console.cloud.google.com/apis/library) (APIs & Services → Library):

- **Geocoding API** – search and directions
- **Places API (New)** or **Places API** – address/place autocomplete (search and directions)
- **Directions API** – driving route and polyline

Or to serve and get a URL (e.g. for another device):

```bash
flutter run -d web-server
```

### Android

With one device or emulator connected:

```bash
flutter run
```

With multiple devices, pick one by ID:

```bash
flutter devices
flutter run -d <device_id>
```

Example: `flutter run -d emulator-5554` or `flutter run -d chrome` for web.

### Driving directions

1. Tap the **car icon** in the app bar (or tap "Use as destination" on a search suggestion).
2. **From:** Use "My location" or type a start address.
3. **To:** Type a destination address (or it may be pre-filled).
4. Tap **Get directions** – the driving route appears on the map as a blue line with start (green) and end (red) markers.

## Hiding API keys

The app uses a Google Maps API key. To keep it out of the repo:

1. Copy the example env file and add your key:
   ```bash
   copy api_keys.env.example api_keys.env
   ```
   Edit `api_keys.env` and set `MAPS_API_KEY=your_actual_key`.

2. Run the inject script (from the project root) before building or running:
   ```bash
   dart run tool/inject_api_keys.dart
   ```
   This writes the key into `web/index.html`, `android/local.properties`, and `ios/Flutter/GoogleMapsKey.xcconfig`.

3. **Do not commit** `api_keys.env` or the injected key in `web/index.html`. If you run the script, avoid committing `web/index.html` until you’ve reverted the key back to `MAPS_API_KEY_PLACEHOLDER` (or use a key that’s safe to expose and restrict it in Google Cloud Console).

**Restrict your key** in [Google Cloud Console](https://console.cloud.google.com/apis/credentials): limit by HTTP referrer (web), package name (Android), and bundle ID (iOS) so it can’t be reused from other apps or sites.

## Proxy (fixes wrong-country geocode on web)

If addresses resolve to the wrong country (e.g. Turkey instead of Pittsburgh), use your own proxy. The app reads `FIREBASE_PROXY_URL` from `api_keys.env` — it works with any proxy (Firebase or Vercel).

### Vercel (free, no credit card)

1. **Install Vercel CLI:** `npm install -g vercel`
2. **Deploy:** From project root, run `vercel` and follow the prompts (link to existing project or create new)
3. **Add to api_keys.env:** `FIREBASE_PROXY_URL=https://YOUR_PROJECT.vercel.app/api/maps-proxy`
4. Run with `dart run tool/run_web_with_key.dart`

### Firebase (requires Blaze / billing)

1. **Install Firebase CLI:** `npm install -g firebase-tools` and `firebase login`
2. **Create a Firebase project** and upgrade to Blaze at [console.firebase.google.com](https://console.firebase.google.com)
3. **Configure:** Edit `.firebaserc` with your project ID
4. **Deploy:** `cd functions && npm install && cd .. && firebase deploy --only functions`
5. **Add to api_keys.env:** `FIREBASE_PROXY_URL=https://us-central1-YOUR_PROJECT.cloudfunctions.net/mapsProxy`

---

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
