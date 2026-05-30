# 1.2.0 🚀

## BREAKING CHANGES
- Removed **Google ML Kit** (`google_mlkit_face_detection`).
- On-device face detection now uses **MediaPipe BlazeFace** via [`face_detection_tflite`](https://pub.dev/packages/face_detection_tflite).
- Replaced ML Kit `Face` with plugin `DetectedFace`.

## New
- `MediaPipeFaceDetectorHelper` for live camera frames.
- `LivenessDetectionConfig.faceDetectionMaxDim` and `faceDetectionFastMode`.
- Android camera stream uses `ImageFormatGroup.yuv420` (recommended by `face_detection_tflite`).

## Migration
- Remove `google_mlkit_face_detection` from your app if you depended on it only through this plugin.
- Run `flutter clean && flutter pub get` after upgrading (native deps changed).
- Blink/smile challenges require `faceDetectionFastMode: false` (default).

# 1.1.0 🚀

## BREAKING CHANGES
- 🔄 **API Refactor**: All parameters now consolidated into `LivenessDetectionConfig`
- 📦 **Simplified API**: `livenessDetection()` method now only requires `context` and `config`
- 🛠️ **Migration Required**: Update your implementation to use the new unified config approach

## New Features
- ⏱️ **NEW**: Automatic cooldown feature after 3 failed verification attempts. 10-minute waiting period with persistent countdown (survives app restarts). `enableCooldownOnFailure` parameter to control cooldown feature

## Bug Fixes
- 🛠️ **Fixed customizedLabel logic**: Corrected skip challenge behavior (empty string now properly skips)
- ✅ **Added validation**: `customizedLabel` must not be null when `useCustomizedLabel` is true
- 🔄 **Improved consistency**: Unified steps handling logic across the codebase

## Other Changes
- ✅ Moved `isEnableSnackBar` to config
- ✅ Moved `shuffleListWithSmileLast` to config  
- ✅ Moved `showCurrentStep` to config
- ✅ Moved `isDarkMode` to config
- Update compile sdk and Gradle version for example & change deprecated .withOpacity(0.2) to .withAlpha(51) (Thanks to https://github.com/erikwibowo)

### Migration Guide:
**Before (v1.0.x):**
```dart
await plugin.livenessDetection(
  context: context,
  config: LivenessDetectionConfig(...),
  isEnableSnackBar: true,
  shuffleListWithSmileLast: true,
  showCurrentStep: true,
  isDarkMode: false,
);
```

**After (v1.1.0+):**
```dart
await plugin.livenessDetection(
  context: context,
  config: LivenessDetectionConfig(
    isEnableSnackBar: true,
    shuffleListWithSmileLast: true,
    showCurrentStep: true,
    isDarkMode: false,
    // ... other parameters
  ),
);
```


## 1.0.8 🚀

- 📦 Add packagingOptions with useLegacyPackaging for Android compatibility
- 🛠️ Fix InputImageConverterError for unsupported image formats
- 📷 Add configurable camera resolution preset (cameraResolution parameter)
- ⚡ Improved error handling for ML Kit face detection
- 🔧 Platform-specific image format optimization (NV21 for Android, BGRA8888 for iOS)

## 1.0.7 🚀

- ⚡ Update google_mlkit_face_detection for better compability to newest flutter version

## 1.0.6 🚀
- 🛠️ Fix issue camera preview freeze while start liveness detection
- 🎨 Face preview now looks better, no longer stretching
- 🎨 Add parameter to adjust image quality liveness result

## 1.0.5 🚀

- 🛠️ Improve security liveness challenge
- 🎨 Add set to max brightness option
- 🛠️ Update readme.md

## 1.0.4 🚀

- ⚡ Improved performance during liveness challenge verification
- 🎭 Customizable liveness challenge labels
- ⏳ Flexible security verification duration
- 🎲 Adjustable number of liveness challenges

## 1.0.3 🚀

- 🛠️ Adjust to compatible camera dependency to prevent face not found
- 🔐 Ajdust threshold for smile and look down challenge
- 🎨 Add showCurrentStep parameter (default : false)
- 🎨 Add Light and Dark mode

## 1.0.2 🚀

### Update README.md

- 🛠️ Update readme.md file

## 1.0.1 🚀

### Update dependencies 🛠️

- 🛠️ Update camera dependencies and also add camera_android_camerax for better experience while using liveness detection

## 1.0.0 🚀

### Introducing Flutter Liveness Detection Randomized Plugin! 

✨ First Major Release Highlights:
- 🎯 Smart Liveness Detection System
- 🎲 Dynamic Random Challenge Generator
- 🔐 Enhanced Security Protocols
- 📱 Cross-Platform Support (iOS & Android)
- ⚡ Real-time Processing
- 🎨 Sleek & Modern UI
- 🛠️ Developer-Friendly Integration

Ready to revolutionize your biometric authentication? Let's make your app more secure! 💪