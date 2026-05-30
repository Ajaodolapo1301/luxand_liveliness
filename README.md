# luxand_liveness

Flutter package: randomized on-device face challenges (blink/smile) plus [Luxand Cloud](https://luxand.cloud/) liveness verification on the captured photo.

## Example app

The **`example/`** app is the supported way to test on a device:

```bash
cd example
flutter run --dart-define=LUXAND_API_KEY=your_luxand_cloud_token
```

See [example/README.md](example/README.md) for details.

## Use in your app

```dart
import 'package:luxand_liveness/luxand_liveness.dart';

final result = await LuxandLiveness.verify(
  context: context,
  apiKey: 'your_luxand_cloud_token',
);

if (result != null && result.isSuccess) {
  print('isReal: ${result.isReal}, score: ${result.score}');
}
```

Platform setup (camera permission, iOS `NSCameraUsageDescription`) matches the underlying [flutter_liveness_detection_randomized_plugin](packages/flutter_liveness_detection_randomized_plugin/README.md).
