package com.taha.yoloncnn

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.tencent.yolo11ncnn.YOLO11Ncnn
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"
    private val PERMISSION_CHANNEL = "com.taha.yoloncnn/permission"
    private val NIHUI_CONTROL_CHANNEL = "com.taha.yoloncnn/nihui_control"
    private val CAMERA_REQ_CODE = 1001

    private var pendingPermissionResult: MethodChannel.Result? = null

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

                    val ok = yolo11ncnn.loadModel(assets, taskid, modelid, cpugpu)
                    isModelLoaded = true
                    Log.i(TAG, "reloadModel(task=$taskid, model=$modelid, cpugpu=$cpugpu) -> $ok")
                    result.success(ok)
                }
                "switchCamera" -> {
                    stopCameraSafely()
                    currentFacing = if (currentFacing == 1) 0 else 1
                    if (!isPaused && currentSurface != null) {
                        startCameraSafely()
                    }
                    result.success(currentFacing)
                }
                "setPaused" -> {
                    val paused = call.argument<Boolean>("paused") ?: false
                    isPaused = paused
                    if (paused) {
                        stopCameraSafely()
                    } else {
                        startCameraSafely()
                    }
                    result.success(true)
                }
                "getState" -> {
                    val state = mapOf(
                        "taskid" to currentTask,
                        "modelid" to currentModel,
                        "cpugpu" to currentCpuGpu,
                        "facing" to currentFacing,
                        "isCameraOpen" to isCameraOpen,
                        "isPaused" to isPaused
                    )
                    result.success(state)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onSurfaceAvailable(surface: Surface) {
        currentSurface = surface
        yolo11ncnn.setOutputWindow(surface)

        // SAFEGUARD 1: Load default model (0, 0, 0) once during initialization
        if (!isModelLoaded) {
            val ok = yolo11ncnn.loadModel(assets, currentTask, currentModel, currentCpuGpu)
            isModelLoaded = true
            Log.i(TAG, "Initial loadModel (task=$currentTask, model=$currentModel, cpugpu=$currentCpuGpu) -> $ok")
        }

        if (!isPaused) {
            startCameraSafely()
        }
    }

    fun onSurfaceDestroyed() {
        stopCameraSafely()
        currentSurface = null
        yolo11ncnn.setOutputWindow(null)
    }

    // SAFEGUARD 2: Prevent double openCamera calls and verify camera permission
    fun startCameraSafely() {
        if (isCameraOpen) {
            Log.d(TAG, "startCameraSafely: camera already open")
            return
        }
        if (currentSurface == null) {
            Log.d(TAG, "startCameraSafely: surface is null, waiting")
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
        if (!isPaused && currentSurface != null) {
            startCameraSafely()
        }
    }

    override fun onPause() {
        super.onPause()
        stopCameraSafely()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_REQ_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            if (granted && !isPaused && currentSurface != null) {
                startCameraSafely()
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
