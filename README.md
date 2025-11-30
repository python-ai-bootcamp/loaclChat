# localChat

Discover nearby peers over Bluetooth Low Energy (BLE) and display them in a simple Flutter UI. This project demonstrates cross‑platform BLE peer discovery with conditional implementations for mobile, Windows, and web stubs.

> Package name: `cool_project` (see `pubspec.yaml`), repo folder: `localChat`.

## Features

- Nearby peer discovery over BLE (custom service UUID).
- Broadcast minimal identity (user ID + nickname) as JSON in advertisement data.
- List of discovered users updates in real time; stale entries auto‑expire after 20s.
- Avatar selection on the welcome screen (via `image_picker`).
- Cross‑platform service abstraction with conditional imports:
  - Mobile (Android/iOS): scan and advertise via `flutter_blue_plus`.
  - Windows: scanning supported; advertising disabled due to plugin limitations.
  - Web: BLE discovery is not available; stubbed implementation with a helpful message.

## Tech stack

- Flutter SDK: >= 3.0.0 < 4.0.0
- Dart
- Packages:
  - `flutter_blue_plus` and `flutter_blue_plus_windows`
  - `image_picker`
  - `permission_handler`
  - `flutter_lints`

## Project structure

```
lib/
  main.dart                          # App bootstrap with Bluetooth pre-checks
  welcome_page.dart                  # Nickname + (optional) avatar picker
  chat_page.dart                     # Displays discovered nearby users
  models/
    discovered_user.dart             # Peer model
  pages/
    bluetooth_unavailable_page.dart  # Friendly error UI when BT is unavailable
  services/
    bluetooth_service.dart           # Platform-agnostic API + conditional import
    bluetooth_service_impl.dart      # Mobile impl (Android/iOS) using flutter_blue_plus
    bluetooth_service_windows.dart   # Windows impl (scan only; advertising disabled)
    bluetooth_service_stub.dart      # Web stub (no BLE)
  utils/
    user_id_generator.dart           # Short base62-ish ID generator
```

## How it works

- A custom BLE Service UUID (`12345678-1234-1234-1234-123456789abc`) is used for discovery.
- Each peer encodes `{ userId, nickname }` as JSON and advertises it in service/manufacturer data.
- Scanners decode advertisements and maintain an in‑memory map of `DiscoveredUser`s.
- A periodic cleanup removes users not seen in the last 20 seconds.

Platform specifics:
- Android/iOS: scan + advertise via `flutter_blue_plus`.
- Windows: scanning works; advertising is intentionally disabled to avoid a known DLL crash from advertising plugins on devices without Bluetooth hardware. The UI warns accordingly.
- Web: no BLE peer discovery; the UI presents a clear message.

## Requirements

- Flutter 3.x SDK
- Platform toolchains as applicable (Android Studio/Xcode/Visual Studio C++ build tools for desktop).
- Bluetooth hardware for platforms where scanning/advertising is used.

## Setup

1. Install Flutter and platform SDKs.
2. Get dependencies:
   ```bash
   flutter pub get
   ```
3. (Optional) Enable desktop support:
   ```bash
   flutter config --enable-windows-desktop --enable-macos-desktop --enable-linux-desktop
   ```

## Run

Choose a target device/platform and run:

```bash
flutter run -d windows   # Windows: scanning supported; advertising disabled
flutter run -d android   # Android
flutter run -d ios       # iOS
flutter run -d chrome    # Web: BLE scanning/advertising not supported (no discovery)
```

## Permissions and platform notes

- Android:
  - Recent Android versions require Bluetooth and nearby devices permissions to scan/advertise.
  - The `flutter_blue_plus` and `permission_handler` plugins facilitate this flow.
  - Consult plugin docs if you need additional manifest entries for your minSdk/targetSdk.
- iOS:
  - Add usage descriptions to `Info.plist` as required by Apple (e.g., `NSBluetoothAlwaysUsageDescription`).
- Windows:
  - Requires actual Bluetooth hardware to scan.
  - Advertising is disabled in the Windows implementation to avoid a known plugin DLL crash; the app handles lack of hardware gracefully and shows `BluetoothUnavailablePage`.
- Web:
  - BLE peer discovery isn’t supported; the app provides a helpful message.

## Scripts and linting

- Static analysis is configured via `analysis_options.yaml` with `flutter_lints`.
  ```bash
  flutter analyze
  flutter test
  ```

## Troubleshooting

- “Bluetooth Hardware Not Detected” on Windows:
  - Install a Bluetooth adapter (USB/internal), enable Bluetooth in Windows Settings, then restart the app.
- No users appear:
  - Ensure at least one advertising device is nearby (on Windows you’ll need a mobile device to advertise).
  - Check platform permissions and that Bluetooth is turned on.
- iOS/Android permission prompts:
  - Ensure you’ve included required permissions/usage descriptions per platform guidelines.

## Roadmap ideas

- Enable safe advertising on Windows if/when a stable plugin is available.
- Add actual chat/messaging over a data transport (currently this is discovery-only).
- Persist avatars and profiles locally.

## License

TBD. Add your preferred license here (e.g., MIT/Apache-2.0).
