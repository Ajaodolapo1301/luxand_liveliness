package com.bagussubagja.flutter_liveness_detection_randomized_plugin.flutter_liveness_detection_randomized_plugin

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

/** FlutterLivenessDetectionRandomizedPlugin */
class FlutterLivenessDetectionRandomizedPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var nativeCaptureChannel: MethodChannel
    private lateinit var nativeCaptureEvents: EventChannel

    private lateinit var applicationContext: Context
    private lateinit var textureRegistry: TextureRegistry
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var cameraController: NativeCameraController? = null
    private var detectionSink: EventChannel.EventSink? = null

    // Pending initialize() awaiting a camera-permission grant.
    private var pendingUseFront = true
    private var pendingMaxDim = 320
    private var pendingResult: Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        textureRegistry = binding.textureRegistry

        channel = MethodChannel(binding.binaryMessenger, "flutter_liveness_detection_randomized_plugin")
        channel.setMethodCallHandler(this)

        nativeCaptureChannel = MethodChannel(
            binding.binaryMessenger,
            "flutter_liveness_detection_randomized_plugin/native_capture",
        )
        nativeCaptureChannel.setMethodCallHandler { call, result -> onNativeCaptureCall(call, result) }

        nativeCaptureEvents = EventChannel(
            binding.binaryMessenger,
            "flutter_liveness_detection_randomized_plugin/native_capture/events",
        )
        nativeCaptureEvents.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    detectionSink = events
                }

                override fun onCancel(arguments: Any?) {
                    detectionSink = null
                }
            },
        )
    }

    private fun onNativeCaptureCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                val useFront = call.argument<Boolean>("useFrontCamera") ?: true
                val maxDim = call.argument<Int>("faceDetectionMaxDim") ?: 320
                val granted = ContextCompat.checkSelfPermission(
                    applicationContext,
                    Manifest.permission.CAMERA,
                ) == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    startCamera(useFront, maxDim, result)
                } else {
                    val act = activity
                    if (act == null) {
                        result.error("no_activity", "No activity to request camera permission.", null)
                        return
                    }
                    pendingUseFront = useFront
                    pendingMaxDim = maxDim
                    pendingResult = result
                    ActivityCompat.requestPermissions(
                        act,
                        arrayOf(Manifest.permission.CAMERA),
                        CAMERA_PERMISSION_REQUEST_CODE,
                    )
                }
            }
            "capture" -> {
                val controller = cameraController
                if (controller == null) {
                    result.error("not_ready", "Camera is not initialized.", null)
                } else {
                    controller.capture(result)
                }
            }
            "dispose" -> {
                cameraController?.dispose()
                cameraController = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startCamera(useFront: Boolean, maxDim: Int, result: Result) {
        val controller = NativeCameraController(
            applicationContext,
            textureRegistry,
            maxDim,
        ) { detection ->
            detectionSink?.success(detection)
        }
        cameraController = controller
        controller.initialize(useFront, result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST_CODE) return false
        val result = pendingResult ?: return true
        pendingResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startCamera(pendingUseFront, pendingMaxDim, result)
        } else {
            result.error("camera_permission_denied", "Camera permission was denied.", null)
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        nativeCaptureChannel.setMethodCallHandler(null)
        nativeCaptureEvents.setStreamHandler(null)
        cameraController?.dispose()
        cameraController = null
    }

    // --- ActivityAware ---

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    companion object {
        private const val CAMERA_PERMISSION_REQUEST_CODE = 5001
    }
}
