package com.bagussubagja.flutter_liveness_detection_randomized_plugin.flutter_liveness_detection_randomized_plugin

import android.content.Context
import android.util.Log
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector

/**
 * Thin wrapper over MediaPipe Tasks [FaceDetector] (BlazeFace short-range) in
 * LIVE_STREAM mode. Bounding box only — no mesh/landmarks (the product has no
 * blink/smile/turn challenges).
 *
 * Callers must feed UPRIGHT, non-mirrored images (rotation handled before this
 * layer), so the returned box is already in upright image space and lines up
 * with the upright, non-mirrored preview.
 */
class NativeFaceDetector(
    context: Context,
    private val onFace: (FaceResult?) -> Unit,
) {
    data class FaceResult(
        val left: Float,
        val top: Float,
        val width: Float,
        val height: Float,
        val imageWidth: Int,
        val imageHeight: Int,
    )

    private val detector: FaceDetector

    init {
        val base = BaseOptions.builder()
            .setModelAssetPath("blaze_face_short_range.tflite")
            .build()
        val options = FaceDetector.FaceDetectorOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setMinDetectionConfidence(0.5f)
            .setResultListener { result, input ->
                val det = result.detections().firstOrNull()
                if (det == null) {
                    onFace(null)
                } else {
                    val box = det.boundingBox()
                    onFace(
                        FaceResult(
                            left = box.left,
                            top = box.top,
                            width = box.width(),
                            height = box.height(),
                            imageWidth = input.width,
                            imageHeight = input.height,
                        ),
                    )
                }
            }
            .setErrorListener { e -> Log.e(TAG, "FaceDetector error", e) }
            .build()
        detector = FaceDetector.createFromOptions(context, options)
    }

    /** [timestampMs] must be monotonically increasing across calls. */
    fun detect(image: MPImage, timestampMs: Long) {
        detector.detectAsync(image, timestampMs)
    }

    fun close() {
        try {
            detector.close()
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val TAG = "NativeFaceDetector"
    }
}
