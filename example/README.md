# Luxand Liveness — example app

Runnable host app for manual testing on a physical device (camera required).

## Run

```bash
cd example
flutter pub get
flutter run
```

With your Luxand Cloud API key (for **Full verify**):

```bash
flutter run --dart-define=LUXAND_API_KEY=your_token_here
```

## What to try

| Button | What it does |
|--------|----------------|
| **Camera only (plugin)** | Opens the liveness camera UI and returns the image path. No cloud call. |
| **Full verify (plugin + Luxand Cloud)** | Same capture flow, then `POST` to Luxand Cloud liveness API. |

Use the switches to test **delayed face capture** (no blink/smile) and **manual snap fallback**.

## Requirements

- Physical device with front camera (simulators are unreliable for camera/liveness).
- Android: `minSdk` 23+, camera + internet permissions (already in this app).
- iOS: camera usage string in `Info.plist` (already set).
