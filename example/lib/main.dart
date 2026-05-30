import 'package:flutter_liveness_detection_randomized_plugin/index.dart';
import 'package:luxand_liveness/luxand_liveness.dart';

/// Pass at run time: `--dart-define=LUXAND_API_KEY=your_token`
const _apiKeyFromDefine = String.fromEnvironment('LUXAND_API_KEY');

void main() {
  runApp(const LuxandLivenessExampleApp());
}

class LuxandLivenessExampleApp extends StatelessWidget {
  const LuxandLivenessExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luxand Liveness Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  final _apiKeyController = TextEditingController(text: _apiKeyFromDefine);
  bool _enableManualSnap = false;
  bool _enableDelayedCapture = false;
  bool _manualSnapRequireFace = true;
  bool _busy = false;
  String? _lastMessage;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  LivenessDetectionConfig _buildConfig() {
    return LivenessDetectionConfig(
      cameraResolution: ResolutionPreset.high,
      imageQuality: 90,
      isEnableMaxBrightness: true,
      durationLivenessVerify: 45,
      shuffleListWithSmileLast: false,
      useCustomizedLabel: true,
      customizedLabel: LivenessDetectionLabelModel(
        blink: 'Blink 2-3 times',
        smile: 'Smile',
        lookLeft: '',
        lookRight: '',
        lookUp: '',
        lookDown: '',
      ),
      showDurationUiText: true,
      showCurrentStep: true,
      enableManualSnapFallback: _enableManualSnap,
      manualSnapAfterSeconds: 10,
      manualSnapRequireFaceDetected: _manualSnapRequireFace,
      enableDelayedFaceCapture: _enableDelayedCapture,
      delayedFaceCaptureAfterSeconds: 3,
      delayedFaceCaptureStableFrames: 2,
      delayedFaceCaptureInstruction: 'Keep your head in the frame',
    );
  }

  Future<void> _runPluginOnly() async {
    setState(() {
      _busy = true;
      _lastMessage = null;
    });

    final path = await FlutterLivenessDetectionRandomizedPlugin.instance
        .livenessDetection(
      context: context,
      config: _buildConfig(),
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastMessage = path == null
          ? 'Cancelled'
          : 'Captured (plugin only):\n$path';
    });
  }

  Future<void> _runFullVerify() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _lastMessage = 'Enter your Luxand Cloud API key or use '
            '--dart-define=LUXAND_API_KEY=...';
      });
      return;
    }

    setState(() {
      _busy = true;
      _lastMessage = null;
    });

    final result = await LuxandLiveness.verify(
      context: context,
      apiKey: apiKey,
      enableManualSnapFallback: _enableManualSnap,
      manualSnapRequireFaceDetected: _manualSnapRequireFace,
      enableDelayedFaceCapture: _enableDelayedCapture,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result == null) {
        _lastMessage = 'Cancelled';
      } else if (!result.isSuccess) {
        _lastMessage = 'Error: ${result.error}';
      } else {
        _lastMessage =
            'Luxand Cloud\nisReal: ${result.isReal}\nscore: ${result.score}\n'
            'image: ${result.imageFile?.path}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Luxand Liveness Example'),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Test camera + face detection without calling the cloud, '
                  'or run the full flow (capture + Luxand Cloud liveness).',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Luxand Cloud API key',
                    border: OutlineInputBorder(),
                    helperText:
                        'Required for full verify. Optional for plugin-only.',
                  ),
                  obscureText: true,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Delayed face capture'),
                  subtitle: const Text(
                    'Skip challenges; capture after face is stable in oval',
                  ),
                  value: _enableDelayedCapture,
                  onChanged: (v) =>
                      setState(() => _enableDelayedCapture = v),
                ),
                SwitchListTile(
                  title: const Text('Manual snap fallback'),
                  subtitle: const Text('Show Snap button after timeout'),
                  value: _enableManualSnap,
                  onChanged: (v) => setState(() => _enableManualSnap = v),
                ),
                SwitchListTile(
                  title: const Text('Manual snap requires face'),
                  value: _manualSnapRequireFace,
                  onChanged: _enableManualSnap
                      ? (v) => setState(() => _manualSnapRequireFace = v)
                      : null,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _runPluginOnly,
                  child: const Text('Camera only (plugin)'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _runFullVerify,
                  child: const Text('Full verify (plugin + Luxand Cloud)'),
                ),
                if (_lastMessage != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    _lastMessage!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
    );
  }
}
