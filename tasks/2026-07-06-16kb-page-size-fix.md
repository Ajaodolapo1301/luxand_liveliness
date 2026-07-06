# 16 KB Page Size Fix Plan

**Date:** 2026-07-06  
**Status:** Implemented and verified  
**Issue:** Play Console / APK alignment flags `libmediapipe_tasks_vision_jni.so` and `libimage_processing_util_jni.so`

---

## Root cause (confirmed)

Two separate native dependencies ship **4 KB–aligned** `.so` files:

| Library | Source in this repo | Current version | Fix version |
|---------|-------------------|-----------------|-------------|
| `libmediapipe_tasks_vision_jni.so` | `packages/.../android/build.gradle` → `com.google.mediapipe:tasks-vision` | **0.10.14** | **≥ 0.10.29** |
| `libimage_processing_util_jni.so` | CameraX (Flutter `camera` + native CameraX preview) and transitively ML Kit | CameraX **1.3.4** | CameraX **≥ 1.4.2** |

### Why ML Kit shows up on Android

`google_mlkit_face_detection` is still in `pubspec.yaml` and bundles Android native libs even though Dart code only uses it on **iOS** (`_useMlKit => Platform.isIOS`). Android builds still ship ML Kit + its shared `libimage_processing_util_jni.so`.

### Why CameraX is stale

- Plugin pins `camera_android_camerax: 0.6.10+1` → CameraX **1.3.4** (4 KB)
- Native preview in plugin also uses CameraX **1.3.4**
- Note: `0.6.10+2` already bumped to 1.4.1, but the override pins the older patch

---

## Proposed fix (minimal, 3 changes)

### 1. Upgrade MediaPipe Tasks Vision (native Android path)

**File:** `packages/flutter_liveness_detection_randomized_plugin/android/build.gradle`

```gradle
implementation "com.google.mediapipe:tasks-vision:0.10.29"
```

Fixes `libmediapipe_tasks_vision_jni.so` alignment.

**Effort:** Low | **Risk:** Low (API-stable minor bump)

---

### 2. Upgrade CameraX in plugin + force resolution project-wide

**File:** `packages/flutter_liveness_detection_randomized_plugin/android/build.gradle`

```gradle
def cameraxVersion = "1.4.2"  // was 1.3.4
```

**File:** `android/build.gradle.kts` (root)

Add `resolutionStrategy.force` for all `androidx.camera:*` artifacts at **1.4.2** so Flutter's `camera_android_camerax` and ML Kit both resolve to the 16 KB–aligned `libimage_processing_util_jni.so`.

**Effort:** Low | **Risk:** Low–medium (test camera preview + capture on device)

---

### 3. Bump `camera_android_camerax` override

**File:** `packages/flutter_liveness_detection_randomized_plugin/pubspec.yaml`

```yaml
dependency_overrides:
  camera_android_camerax: 0.6.10+2  # was 0.6.10+1; uses CameraX 1.4.1
```

Or remove the override entirely and let transitive resolution pick the newest compatible version.

**Effort:** Low | **Risk:** Low (stays on camera 0.10.x)

---

## Optional follow-up (not in initial fix)

- **Remove ML Kit from Android APK entirely** — iOS-only today; aligns with `tasks/2026-05-29-luxand-replace-mlkit.md`. Requires platform-split dependency or finishing Luxand migration.
- **Upgrade `camera` package** to 0.11+ and `camera_android_camerax` to 0.6.21+ (CameraX 1.5+) for a more future-proof stack.

---

## Verification checklist

- [ ] Clean release build: `flutter clean && flutter build apk --release`
- [ ] Run `check_elf_alignment.sh` on the APK — both libs show `align 2**14`
- [ ] Play Console pre-launch report shows 16 KB support
- [ ] Smoke test: Android delayed-capture flow (native MediaPipe path)
- [ ] Smoke test: Android challenge flow (Dart camera + face_detection_tflite)
- [ ] Smoke test: iOS still works (ML Kit path unchanged)

---

## Tasks

- [x] Upgrade `tasks-vision` to 0.10.29 in plugin `build.gradle`
- [x] Upgrade plugin CameraX to 1.4.2
- [x] Add CameraX `resolutionStrategy.force` in root + example `android/build.gradle.kts`
- [x] Bump `camera_android_camerax` override to 0.6.10+2
- [x] Clean build + ELF alignment check
- [ ] Device smoke tests (Android native + Dart paths)

---

## Review

### Summary
Upgraded MediaPipe Tasks Vision (0.10.14 → 0.10.29) and CameraX (1.3.4 → 1.4.2), forced CameraX 1.4.2 project-wide, and bumped `camera_android_camerax` override to 0.6.10+2.

### Verification (2026-07-06)
Built `example/build/app/outputs/flutter-apk/app-release.apk` (195 MB) and ran Google's `check_elf_alignment.sh` on all `arm64-v8a` libs.

**Both previously-flagged libraries are now 16 KB aligned (`2**14`):**
- `libmediapipe_tasks_vision_jni.so` — **ALIGNED**
- `libimage_processing_util_jni.so` — **ALIGNED**

All 12 `arm64-v8a` native libs in the APK passed — zero unaligned.

### Remaining
- Device smoke test on a physical Android device (camera preview + delayed capture flow).
- Play Console will re-validate on next upload.
