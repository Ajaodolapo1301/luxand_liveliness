package com.bagussubagja.flutter_liveness_detection_randomized_plugin.flutter_liveness_detection_randomized_plugin

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.mediapipe.framework.image.BitmapImageBuilder
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

/**
 * Owns a CameraX preview (rendered into a Flutter texture) plus a MediaPipe
 * face-detection analysis stream.
 *
 * Detection runs on a downscaled, upright, non-mirrored bitmap so the emitted
 * box lines up with the upright/non-mirrored Flutter preview. Frames never
 * cross into Dart — only the resulting face box does (via [onDetection]).
 */
class NativeCameraController(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val maxDim: Int,
    private val onDetection: (Map<String, Any?>) -> Unit,
) {
    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    private var cameraProvider: ProcessCameraProvider? = null
    private var surfaceEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var faceDetector: NativeFaceDetector? = null
    private var imageCapture: ImageCapture? = null

    private var lastTimestampMs = 0L

    private val lifecycleOwner =
        object : LifecycleOwner {
            val registry = LifecycleRegistry(this)
            override val lifecycle: Lifecycle get() = registry
        }

    fun initialize(useFrontCamera: Boolean, result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        fun fail(code: String, message: String) {
            if (replied.compareAndSet(false, true)) result.error(code, message, null)
        }

        val entry = textureRegistry.createSurfaceTexture()
        surfaceEntry = entry
        val surfaceTexture = entry.surfaceTexture()

        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            try {
                val provider = providerFuture.get()
                cameraProvider = provider

                val preview = Preview.Builder().build()
                preview.setSurfaceProvider(mainExecutor) { request ->
                    val res = request.resolution
                    surfaceTexture.setDefaultBufferSize(res.width, res.height)
                    val newSurface = Surface(surfaceTexture)
                    surface = newSurface
                    request.provideSurface(newSurface, mainExecutor) { newSurface.release() }
                    request.setTransformationInfoListener(mainExecutor) { info ->
                        if (replied.compareAndSet(false, true)) {
                            result.success(
                                mapOf(
                                    "textureId" to entry.id(),
                                    "width" to res.width,
                                    "height" to res.height,
                                    "rotationDegrees" to info.rotationDegrees,
                                    "mirror" to useFrontCamera,
                                ),
                            )
                        }
                    }
                }

                val detector = NativeFaceDetector(context) { face -> emit(face) }
                faceDetector = detector

                val analysis = ImageAnalysis.Builder()
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(analysisExecutor) { proxy -> analyze(proxy, detector) }

                // Cap capture resolution (~1.5MP) so the JPEG is fast to encode
                // on low-end phones — the screen can pop almost immediately —
                // and the upload is lighter. Full sensor res (often 12MP) added
                // several seconds of latency.
                val captureResolution = ResolutionSelector.Builder()
                    .setResolutionStrategy(
                        ResolutionStrategy(
                            Size(1440, 1080),
                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                        ),
                    )
                    .build()
                val capture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setResolutionSelector(captureResolution)
                    .setTargetRotation(Surface.ROTATION_0)
                    .build()
                imageCapture = capture

                val selector =
                    if (useFrontCamera) CameraSelector.DEFAULT_FRONT_CAMERA
                    else CameraSelector.DEFAULT_BACK_CAMERA

                lifecycleOwner.registry.currentState = Lifecycle.State.RESUMED
                provider.unbindAll()
                provider.bindToLifecycle(lifecycleOwner, selector, preview, analysis, capture)
            } catch (e: Exception) {
                fail("camera_init_failed", e.message ?: e.toString())
            }
        }, mainExecutor)
    }

    private fun analyze(proxy: ImageProxy, detector: NativeFaceDetector) {
        try {
            val upright = proxy.toUprightBitmap(maxDim)
            val image = BitmapImageBuilder(upright).build()
            // MediaPipe LIVE_STREAM requires strictly-increasing timestamps.
            val ts = max(SystemClock.uptimeMillis(), lastTimestampMs + 1)
            lastTimestampMs = ts
            detector.detect(image, ts)
        } catch (_: Exception) {
        } finally {
            proxy.close()
        }
    }

    fun capture(result: MethodChannel.Result) {
        val capture = imageCapture
        if (capture == null) {
            result.error("not_ready", "Camera is not initialized.", null)
            return
        }
        val file = File(context.cacheDir, "native_capture_${SystemClock.uptimeMillis()}.jpg")
        val options = ImageCapture.OutputFileOptions.Builder(file).build()
        capture.takePicture(
            options,
            ContextCompat.getMainExecutor(context),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    result.success(file.absolutePath)
                }

                override fun onError(exception: ImageCaptureException) {
                    result.error("capture_failed", exception.message ?: "capture failed", null)
                }
            },
        )
    }

    private fun emit(face: NativeFaceDetector.FaceResult?) {
        val map = if (face == null) {
            mapOf("hasFace" to false)
        } else {
            mapOf(
                "hasFace" to true,
                "left" to face.left,
                "top" to face.top,
                "width" to face.width,
                "height" to face.height,
                "imageWidth" to face.imageWidth,
                "imageHeight" to face.imageHeight,
                // Detection runs on the upright, non-mirrored buffer, matching
                // the preview, so no mirror flip is needed on the Dart side.
                "mirror" to false,
            )
        }
        mainExecutor.execute { onDetection(map) }
    }

    fun dispose() {
        try {
            cameraProvider?.unbindAll()
        } catch (_: Exception) {
        }
        lifecycleOwner.registry.currentState = Lifecycle.State.DESTROYED
        cameraProvider = null
        imageCapture = null
        faceDetector?.close()
        faceDetector = null
        surface?.release()
        surface = null
        surfaceEntry?.release()
        surfaceEntry = null
        analysisExecutor.shutdown()
    }
}

/**
 * Converts an RGBA_8888 [ImageProxy] to an upright, downscaled [Bitmap]
 * (longest side == [maxDim]). Handles row-stride padding and applies the
 * sensor rotation so the result is upright. Front-camera frames are left
 * non-mirrored to match the preview.
 */
private fun ImageProxy.toUprightBitmap(maxDim: Int): Bitmap {
    val plane = planes[0]
    val pixelStride = plane.pixelStride
    val rowStride = plane.rowStride
    val rowPadding = rowStride - pixelStride * width

    val bitmap = Bitmap.createBitmap(
        width + rowPadding / pixelStride,
        height,
        Bitmap.Config.ARGB_8888,
    )
    plane.buffer.rewind()
    bitmap.copyPixelsFromBuffer(plane.buffer)
    val cropped =
        if (rowPadding == 0) bitmap else Bitmap.createBitmap(bitmap, 0, 0, width, height)

    val longest = max(cropped.width, cropped.height)
    val scale = if (longest > maxDim) maxDim.toFloat() / longest else 1f

    val matrix = Matrix()
    if (scale != 1f) matrix.postScale(scale, scale)
    val rotation = imageInfo.rotationDegrees
    if (rotation != 0) matrix.postRotate(rotation.toFloat())

    return Bitmap.createBitmap(cropped, 0, 0, cropped.width, cropped.height, matrix, true)
}
