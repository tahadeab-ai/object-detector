package com.taha.yoloncnn

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.tencent.yolo11ncnn.YOLO11Ncnn
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"
    private val PERMISSION_CHANNEL = "com.taha.yoloncnn/permission"
    private val NIHUI_CONTROL_CHANNEL = "com.taha.yoloncnn/nihui_control"
    private val CAMERA_REQ_CODE = 1001
    private val PICK_IMAGE_REQ = 2001
    private val PICK_VIDEO_REQ = 2002
    private val CAPTURE_IMAGE_REQ = 2003

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingMediaPickerResult: MethodChannel.Result? = null
    private var cameraPhotoFile: File? = null

    // Native synchronizer & Surface readiness
    val nativeLock = Any()
    @Volatile var isSurfaceReady = false

    // Singleton YOLO11Ncnn instance
    val yolo11ncnn = YOLO11Ncnn()

    // Tracking state
    var currentTask = 0      // 0=coco, 1=seg, 2=pose, 3=cls, 4=obb
    var currentModel = 0     // 0=n-320, 1=s-320, 2=m-320, 3=n-480, 4=s-480, 5=m-480, 6=n-640, 7=s-640, 8=m-640
    var currentCpuGpu = 0    // 0=CPU, 1=GPU, 2=turnip
    var currentFacing = 1    // 1=back camera, 0=front camera in nihui NdkCamera
    var isModelLoaded = false
    var isCameraOpen = false
    var isPaused = false
    var currentSurface: Surface? = null

    // Media Studio state
    var isMediaMode = false
    var currentMediaBitmap: Bitmap? = null
    @Volatile
    var isVideoPlaying = false
    var videoPlaybackThread: Thread? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register native SurfaceView platform view
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "nihui_camera_surface",
            NihuiCameraPlatformViewFactory(this)
        )

        // Permission channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkCameraPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "requestCameraPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                    if (granted) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_REQ_CODE)
                    }
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Nihui control channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NIHUI_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "reloadModel" -> {
                    val taskid = call.argument<Int>("taskid") ?: currentTask
                    val modelid = call.argument<Int>("modelid") ?: currentModel
                    val cpugpu = call.argument<Int>("cpugpu") ?: currentCpuGpu

                    currentTask = taskid
                    currentModel = modelid
                    currentCpuGpu = cpugpu

                    var ok = false
                    synchronized(nativeLock) {
                        ok = yolo11ncnn.loadModel(assets, taskid, modelid, cpugpu)
                        isModelLoaded = true
                        Log.i(TAG, "reloadModel(task=$taskid, model=$modelid, cpugpu=$cpugpu) -> $ok")

                        // If in Media Studio with an active photo, re-feed immediately
                        if (isSurfaceReady && isMediaMode && currentMediaBitmap != null && !isVideoPlaying) {
                            try {
                                yolo11ncnn.feedBitmap(currentMediaBitmap, 0)
                            } catch (t: Throwable) {
                                Log.e(TAG, "Re-feed media error: ${t.message}")
                            }
                        }
                    }
                    result.success(ok)
                }
                "switchCamera" -> {
                    synchronized(nativeLock) {
                        stopCameraSafely()
                        currentFacing = if (currentFacing == 1) 0 else 1
                        if (!isPaused && !isMediaMode && isSurfaceReady) {
                            startCameraSafely()
                        }
                    }
                    result.success(currentFacing)
                }
                "setPaused" -> {
                    val paused = call.argument<Boolean>("paused") ?: false
                    isPaused = paused
                    synchronized(nativeLock) {
                        if (paused) {
                            stopCameraSafely()
                        } else if (!isMediaMode && isSurfaceReady) {
                            startCameraSafely()
                        }
                    }
                    result.success(true)
                }
                "setMediaMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isMediaMode = enabled
                    synchronized(nativeLock) {
                        if (enabled) {
                            stopCameraSafely()
                        } else {
                            stopVideoSafely()
                            currentMediaBitmap = null
                            if (!isPaused && isSurfaceReady) {
                                startCameraSafely()
                            }
                        }
                    }
                    result.success(true)
                }
                "feedPhoto" -> {
                    val path = call.argument<String>("path") ?: ""
                    val isAsset = call.argument<Boolean>("isAsset") ?: false
                    Log.i(TAG, "feedPhoto called with path=$path, isAsset=$isAsset")

                    synchronized(nativeLock) {
                        stopCameraSafely()
                        stopVideoSafely()
                        isMediaMode = true
                    }

                    // Decode with 2-pass downsampling and Exif rotation
                    val decoded = decodeAndOrientImage(path, isAsset)
                    if (decoded != null) {
                        val prepared = prepareMediaBitmap(decoded, 480, 640)
                        if (prepared != decoded) {
                            decoded.recycle()
                        }
                        currentMediaBitmap = prepared

                        // Wait up to 2000ms if surface is not ready yet after intent picker
                        waitForSurfaceReady(2000L)

                        var ok = false
                        synchronized(nativeLock) {
                            if (isSurfaceReady) {
                                try {
                                    ok = yolo11ncnn.feedBitmap(prepared, 0)
                                    Log.i(TAG, "feedBitmap succeeded on ready surface: $ok")
                                } catch (t: Throwable) {
                                    Log.e(TAG, "feedBitmap native exception: ${t.message}")
                                }
                            } else {
                                Log.w(TAG, "feedPhoto: surface not ready yet, bitmap cached for surfaceChanged")
                                ok = true
                            }
                        }
                        result.success(ok)
                    } else {
                        Log.e(TAG, "feedPhoto decode failed for $path")
                        result.error("DECODE_FAILED", "Could not decode photo from $path", null)
                    }
                }
                "startVideo" -> {
                    val path = call.argument<String>("path") ?: ""
                    val isAsset = call.argument<Boolean>("isAsset") ?: false
                    Log.i(TAG, "startVideo called with path=$path, isAsset=$isAsset")

                    synchronized(nativeLock) {
                        stopCameraSafely()
                        stopVideoSafely()
                        isMediaMode = true
                        isVideoPlaying = true
                    }

                    waitForSurfaceReady(2000L)

                    videoPlaybackThread = Thread {
                        val retriever = MediaMetadataRetriever()
                        try {
                            if (isAsset) {
                                val fd = try {
                                    assets.openFd("flutter_assets/$path")
                                } catch (_: Exception) {
                                    assets.openFd(path)
                                }
                                retriever.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                            } else {
                                retriever.setDataSource(path)
                            }

                            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            val durationMs = durationStr?.toLongOrNull() ?: 10000L
                            val frameIntervalMs = 50L // ~20 FPS

                            var currentPositionMs = 0L
                            while (isVideoPlaying) {
                                if (!isPaused && isSurfaceReady && isMediaMode) {
                                    val frame = retriever.getFrameAtTime(
                                        currentPositionMs * 1000L,
                                        MediaMetadataRetriever.OPTION_CLOSEST
                                    )
                                    if (frame != null) {
                                        val prepared = prepareMediaBitmap(frame, 480, 640)
                                        if (prepared != frame) {
                                            frame.recycle()
                                        }
                                        currentMediaBitmap = prepared
                                        synchronized(nativeLock) {
                                            if (isSurfaceReady && isMediaMode && isVideoPlaying) {
                                                yolo11ncnn.feedBitmap(prepared, 0)
                                            }
                                        }
                                    }

                                    currentPositionMs += frameIntervalMs
                                    if (currentPositionMs >= durationMs) {
                                        currentPositionMs = 0L
                                    }
                                }
                                Thread.sleep(frameIntervalMs)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Video playback error: ${e.message}")
                        } finally {
                            try {
                                retriever.release()
                            } catch (_: Exception) {}
                        }
                    }.apply {
                        isDaemon = true
                        start()
                    }
                    result.success(true)
                }
                "stopVideo" -> {
                    synchronized(nativeLock) {
                        stopVideoSafely()
                    }
                    result.success(true)
                }
                "pickMedia" -> {
                    val type = call.argument<String>("type") ?: "image"
                    pendingMediaPickerResult = result

                    when (type) {
                        "camera" -> {
                            val photoFile = File(cacheDir, "camera_snap_${System.currentTimeMillis()}.jpg")
                            cameraPhotoFile = photoFile
                            val photoUri = FileProvider.getUriForFile(
                                this,
                                "${packageName}.fileprovider",
                                photoFile
                            )
                            val takePictureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            try {
                                startActivityForResult(takePictureIntent, CAPTURE_IMAGE_REQ)
                            } catch (e: Exception) {
                                pendingMediaPickerResult?.error("CAMERA_ERROR", e.message, null)
                                pendingMediaPickerResult = null
                            }
                        }
                        "video" -> {
                            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                                this.type = "video/*"
                                addCategory(Intent.CATEGORY_OPENABLE)
                            }
                            try {
                                startActivityForResult(
                                    Intent.createChooser(intent, "Select Video"),
                                    PICK_VIDEO_REQ
                                )
                            } catch (e: Exception) {
                                pendingMediaPickerResult?.error("PICKER_ERROR", e.message, null)
                                pendingMediaPickerResult = null
                            }
                        }
                        else -> {
                            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                                this.type = "image/*"
                                addCategory(Intent.CATEGORY_OPENABLE)
                            }
                            try {
                                startActivityForResult(
                                    Intent.createChooser(intent, "Select Photo"),
                                    PICK_IMAGE_REQ
                                )
                            } catch (e: Exception) {
                                pendingMediaPickerResult?.error("PICKER_ERROR", e.message, null)
                                pendingMediaPickerResult = null
                            }
                        }
                    }
                }
                "getState" -> {
                    val state = mapOf(
                        "taskid" to currentTask,
                        "modelid" to currentModel,
                        "cpugpu" to currentCpuGpu,
                        "facing" to currentFacing,
                        "isCameraOpen" to isCameraOpen,
                        "isPaused" to isPaused,
                        "isMediaMode" to isMediaMode,
                        "isSurfaceReady" to isSurfaceReady
                    )
                    result.success(state)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun waitForSurfaceReady(timeoutMs: Long = 2000L): Boolean {
        val start = System.currentTimeMillis()
        while (!isSurfaceReady && (System.currentTimeMillis() - start) < timeoutMs) {
            try {
                Thread.sleep(30)
            } catch (_: Exception) {}
        }
        return isSurfaceReady
    }

    private fun decodeAndOrientImage(path: String, isAsset: Boolean): Bitmap? {
        return try {
            if (isAsset) {
                val stream = try {
                    assets.open("flutter_assets/$path")
                } catch (_: Exception) {
                    assets.open(path)
                }
                return BitmapFactory.decodeStream(stream)
            }

            // 1. Check dimensions with inJustDecodeBounds
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            val origW = bounds.outWidth
            val origH = bounds.outHeight
            if (origW <= 0 || origH <= 0) {
                Log.e(TAG, "Invalid image dimensions: ${origW}x${origH}")
                return null
            }

            // Target ~960x1280
            var sampleSize = 1
            while ((origW / sampleSize) > 1440 || (origH / sampleSize) > 1920) {
                sampleSize *= 2
            }

            val decodeOptions = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val decoded = BitmapFactory.decodeFile(path, decodeOptions) ?: return null

            // 2. Read Exif orientation
            var rotationDegrees = 0
            try {
                val exif = ExifInterface(path)
                rotationDegrees = when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270
                    else -> 0
                }
            } catch (e: Exception) {
                Log.w(TAG, "ExifInterface read error: ${e.message}")
            }

            if (rotationDegrees != 0) {
                val matrix = Matrix().apply { postRotate(rotationDegrees.toFloat()) }
                val rotated = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
                if (rotated != decoded) {
                    decoded.recycle()
                }
                rotated
            } else {
                decoded
            }
        } catch (e: Exception) {
            Log.e(TAG, "decodeAndOrientImage error: ${e.message}")
            null
        }
    }

    private fun prepareMediaBitmap(src: Bitmap, targetWidth: Int = 480, targetHeight: Int = 640): Bitmap {
        val result = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(result)
        canvas.drawColor(android.graphics.Color.BLACK)

        val srcWidth = src.width.toFloat()
        val srcHeight = src.height.toFloat()
        val scale = Math.min(targetWidth / srcWidth, targetHeight / srcHeight)
        val scaledWidth = srcWidth * scale
        val scaledHeight = srcHeight * scale
        val left = (targetWidth - scaledWidth) / 2f
        val top = (targetHeight - scaledHeight) / 2f

        val dstRect = android.graphics.RectF(left, top, left + scaledWidth, top + scaledHeight)
        val paint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(src, null, dstRect, paint)
        return result
    }

    fun stopVideoSafely() {
        isVideoPlaying = false
        videoPlaybackThread?.interrupt()
        videoPlaybackThread = null
    }

    fun onSurfaceAvailable(surface: Surface) {
        synchronized(nativeLock) {
            currentSurface = surface
            try {
                yolo11ncnn.setOutputWindow(surface)
                isSurfaceReady = true
                Log.i(TAG, "onSurfaceAvailable: setOutputWindow ok, isSurfaceReady = true")
            } catch (t: Throwable) {
                Log.e(TAG, "setOutputWindow failed: ${t.message}")
                isSurfaceReady = false
                return
            }

            if (!isModelLoaded) {
                val ok = yolo11ncnn.loadModel(assets, currentTask, currentModel, currentCpuGpu)
                isModelLoaded = true
                Log.i(TAG, "Initial loadModel (task=$currentTask, model=$currentModel, cpugpu=$currentCpuGpu) -> $ok")
            }

            if (!isPaused && !isMediaMode) {
                startCameraSafely()
            } else if (isMediaMode && currentMediaBitmap != null && !isVideoPlaying) {
                try {
                    yolo11ncnn.feedBitmap(currentMediaBitmap, 0)
                    Log.i(TAG, "onSurfaceAvailable re-fed active media bitmap")
                } catch (t: Throwable) {
                    Log.e(TAG, "onSurfaceAvailable re-feed error: ${t.message}")
                }
            }
        }
    }

    fun onSurfaceDestroyed() {
        synchronized(nativeLock) {
            isSurfaceReady = false
            stopCameraSafely()
            stopVideoSafely()
            currentSurface = null
            try {
                yolo11ncnn.setOutputWindow(null)
                Log.i(TAG, "onSurfaceDestroyed: setOutputWindow(null) done")
            } catch (t: Throwable) {
                Log.e(TAG, "onSurfaceDestroyed setOutputWindow error: ${t.message}")
            }
        }
    }

    fun startCameraSafely() {
        if (isMediaMode) {
            Log.d(TAG, "startCameraSafely: in media mode, ignoring camera start")
            return
        }
        if (isCameraOpen) {
            Log.d(TAG, "startCameraSafely: camera already open")
            return
        }
        if (!isSurfaceReady || currentSurface == null) {
            Log.d(TAG, "startCameraSafely: surface not ready, waiting")
            return
        }
        val hasPerm = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        if (!hasPerm) {
            Log.w(TAG, "startCameraSafely: camera permission not granted yet")
            return
        }
        val ok = yolo11ncnn.openCamera(currentFacing)
        Log.i(TAG, "yolo11ncnn.openCamera(facing=$currentFacing) -> $ok")
        if (ok) {
            isCameraOpen = true
        }
    }

    fun stopCameraSafely() {
        if (isCameraOpen) {
            yolo11ncnn.closeCamera()
            isCameraOpen = false
            Log.i(TAG, "yolo11ncnn.closeCamera() done")
        }
    }

    override fun onResume() {
        super.onResume()
        synchronized(nativeLock) {
            if (!isPaused && !isMediaMode && isSurfaceReady) {
                startCameraSafely()
            } else if (isMediaMode && isSurfaceReady && currentMediaBitmap != null && !isVideoPlaying) {
                try {
                    yolo11ncnn.feedBitmap(currentMediaBitmap, 0)
                } catch (t: Throwable) {
                    Log.e(TAG, "onResume feedBitmap error: ${t.message}")
                }
            }
        }
    }

    override fun onPause() {
        super.onPause()
        synchronized(nativeLock) {
            stopVideoSafely()
            stopCameraSafely()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_IMAGE_REQ || requestCode == PICK_VIDEO_REQ) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    val extension = if (requestCode == PICK_VIDEO_REQ) ".mp4" else ".jpg"
                    val tempFile = File(cacheDir, "picked_media_${System.currentTimeMillis()}$extension")
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(tempFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                    pendingMediaPickerResult?.success(mapOf(
                        "path" to tempFile.absolutePath,
                        "type" to if (requestCode == PICK_VIDEO_REQ) "video" else "image"
                    ))
                } catch (e: Exception) {
                    pendingMediaPickerResult?.error("FILE_ERROR", e.message, null)
                }
            } else {
                pendingMediaPickerResult?.success(null)
            }
            pendingMediaPickerResult = null
        } else if (requestCode == CAPTURE_IMAGE_REQ) {
            if (resultCode == Activity.RESULT_OK && cameraPhotoFile != null && cameraPhotoFile!!.exists() && cameraPhotoFile!!.length() > 0) {
                pendingMediaPickerResult?.success(mapOf(
                    "path" to cameraPhotoFile!!.absolutePath,
                    "type" to "image"
                ))
            } else {
                pendingMediaPickerResult?.success(null)
            }
            pendingMediaPickerResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_REQ_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            if (granted && !isPaused && isSurfaceReady) {
                synchronized(nativeLock) {
                    startCameraSafely()
                }
            }
        }
    }
}

class NihuiCameraPlatformView(
    context: Context,
    private val activity: MainActivity
) : PlatformView, SurfaceHolder.Callback {

    private val surfaceView: SurfaceView = SurfaceView(context).apply {
        keepScreenOn = true
        holder.addCallback(this@NihuiCameraPlatformView)
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        activity.onSurfaceDestroyed()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        activity.onSurfaceAvailable(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        activity.onSurfaceAvailable(holder.surface)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        activity.onSurfaceDestroyed()
    }
}

class NihuiCameraPlatformViewFactory(
    private val activity: MainActivity
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NihuiCameraPlatformView(context, activity)
    }
}
