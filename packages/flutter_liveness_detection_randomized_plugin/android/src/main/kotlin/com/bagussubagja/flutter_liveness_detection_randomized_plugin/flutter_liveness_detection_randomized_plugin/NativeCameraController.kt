package com.bagussubagja.flutter_liveness_detection_randomized_plugin.flutter_liveness_detection_randomized_plugin

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
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
 *
 * Lifetime: the user can leave the screen at any point, including mid-startup,
 * so every asynchronous callback here checks [disposed] and carries its own
 * catch — a throw on the main looper from a CameraX callback would otherwise
 * take the process down with nothing for Dart to report.
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
    private var imageAnalysis: ImageAnalysis? = null

    /** Set once, at the top of [dispose]. Every async callback bails out on it. */
    private val disposed = AtomicBoolean(false)

    private var lastTimestampMs = 0L

    private val lifecycleOwner =
        object : LifecycleOwner {
            val registry = LifecycleRegistry(this)
            override val lifecycle: Lifecycle get() = registry
        }

    fun initialize(useFrontCamera: Boolean, result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())

        fun reply(send: () -> Unit) {
            if (replied.compareAndSet(false, true)) {
                handler.removeCallbacksAndMessages(null)
                send()
            }
        }
        fun fail(code: String, message: String) = reply { result.error(code, message, null) }

        if (disposed.get()) {
            fail("disposed", "Controller was disposed before initialize.")
            return
        }

        // Binding can succeed without the surface/transform callbacks ever
        // firing (no surface requested, camera never opens). Without this the
        // Dart future never completes and the user sits on a spinner until the
        // app-level timeout.
        handler.postDelayed(
            { fail("camera_init_timeout", "Camera did not start within ${INIT_TIMEOUT_MS}ms.") },
            INIT_TIMEOUT_MS,
        )

        val entry = textureRegistry.createSurfaceTexture()
        surfaceEntry = entry
        val surfaceTexture = entry.surfaceTexture()

        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            // dispose() may have run while the provider future was pending, in
            // which case surfaceTexture is already released.
            if (disposed.get()) {
                fail("disposed", "Controller was disposed during initialize.")
                return@addListener
            }
            try {
                val provider = providerFuture.get()
                cameraProvider = provider

                val preview = Preview.Builder().build()
                preview.setSurfaceProvider(mainExecutor) { request ->
                    // Runs later, posted to mainExecutor, long after the
                    // try/catch below has returned — it needs its own guard and
                    // its own catch.
                    if (disposed.get()) {
                        try {
                            request.willNotProvideSurface()
                        } catch (_: Throwable) {
                        }
                        return@setSurfaceProvider
                    }
                    try {
                        val res = request.resolution
                        surfaceTexture.setDefaultBufferSize(res.width, res.height)
                        val newSurface = Surface(surfaceTexture)
                        surface = newSurface
                        request.provideSurface(newSurface, mainExecutor) { newSurface.release() }
                        request.setTransformationInfoListener(mainExecutor) { info ->
                            reply {
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
                    } catch (t: Throwable) {
                        Log.e(TAG, "surface request failed", t)
                        try {
                            request.willNotProvideSurface()
                        } catch (_: Throwable) {
                        }
                        fail("camera_surface_failed", t.message ?: t.toString())
                    }
                }

                val detector = NativeFaceDetector(context) { face -> emit(face) }
                faceDetector = detector

                val analysis = ImageAnalysis.Builder()
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(analysisExecutor) { proxy -> analyze(proxy, detector) }
                imageAnalysis = analysis

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
            } catch (t: Throwable) {
                Log.e(TAG, "camera init failed", t)
                fail("camera_init_failed", t.message ?: t.toString())
            }
        }, mainExecutor)
    }

    private fun analyze(proxy: ImageProxy, detector: NativeFaceDetector) {
        try {
            // The detector's native graph is freed in dispose(); feeding it
            // after that is a use-after-free. dispose() also queues the close
            // behind this task on the same single-threaded executor, so this
            // check plus that ordering is what keeps the two apart.
            if (disposed.get()) return
            val upright = proxy.toUprightBitmap(maxDim)
            val image = BitmapImageBuilder(upright).build()
            // MediaPipe LIVE_STREAM requires strictly-increasing timestamps.
            val ts = max(SystemClock.uptimeMillis(), lastTimestampMs + 1)
            lastTimestampMs = ts
            detector.detect(image, ts)
        } catch (t: Throwable) {
            // Throwable, not Exception: toUprightBitmap allocates several
            // full-frame bitmaps, and an OutOfMemoryError escaping here would
            // kill the analysis thread and take the app with it.
            Log.e(TAG, "frame analysis failed", t)
        } finally {
            proxy.close()
        }
    }

    fun capture(result: MethodChannel.Result) {
        val capture = imageCapture
        if (capture == null || disposed.get()) {
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
        if (disposed.get()) return
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
        mainExecutor.execute { if (!disposed.get()) onDetection(map) }
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return

        // Order matters. Stop new frames first, then free the MediaPipe graph
        // only once the analysis thread is past any frame it is holding —
        // closing it while a frame is inside detectAsync is a native
        // use-after-free (SIGSEGV with no Java or Dart frames).
        try {
            imageAnalysis?.clearAnalyzer()
        } catch (_: Throwable) {
        }
        try {
            cameraProvider?.unbindAll()
        } catch (_: Throwable) {
        }
        imageAnalysis = null

        // analysisExecutor is single-threaded, so this close runs strictly
        // after any analyze() already queued or in flight. Submitting it
        // before shutdown() keeps it from being rejected, and it means the
        // main thread never has to block waiting for the camera to drain.
        val detector = faceDetector
        faceDetector = null
        try {
            analysisExecutor.execute {
                try {
                    detector?.close()
                } catch (t: Throwable) {
                    Log.e(TAG, "detector close failed", t)
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "could not queue detector close", t)
        }
        analysisExecutor.shutdown()

        lifecycleOwner.registry.currentState = Lifecycle.State.DESTROYED
        cameraProvider = null
        imageCapture = null
        surface?.release()
        surface = null
        surfaceEntry?.release()
        surfaceEntry = null
    }

    companion object {
        private const val TAG = "NativeCameraController"
        private const val INIT_TIMEOUT_MS = 8_000L
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

    val padded = Bitmap.createBitmap(
        width + rowPadding / pixelStride,
        height,
        Bitmap.Config.ARGB_8888,
    )
    plane.buffer.rewind()
    padded.copyPixelsFromBuffer(plane.buffer)
    val cropped =
        if (rowPadding == 0) padded else Bitmap.createBitmap(padded, 0, 0, width, height)

    val longest = max(cropped.width, cropped.height)
    val scale = if (longest > maxDim) maxDim.toFloat() / longest else 1f

    val matrix = Matrix()
    if (scale != 1f) matrix.postScale(scale, scale)
    val rotation = imageInfo.rotationDegrees
    if (rotation != 0) matrix.postRotate(rotation.toFloat())

    val upright =
        Bitmap.createBitmap(cropped, 0, 0, cropped.width, cropped.height, matrix, true)

    // Free the intermediates now rather than leaving them to the GC: at a
    // full-frame ARGB_8888 each, per frame, that churn is what pushes low-RAM
    // devices into OutOfMemoryError.
    if (upright !== cropped && cropped !== padded) cropped.recycle()
    if (upright !== padded) padded.recycle()
    return upright
}
