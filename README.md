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
