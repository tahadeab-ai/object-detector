package com.tencent.yolo11ncnn;

import android.content.res.AssetManager;
import android.view.Surface;

public class YOLO11Ncnn {
    public native boolean loadModel(AssetManager mgr, int taskid, int modelid, int cpugpu);
    public native boolean openCamera(int facing);
    public native boolean closeCamera();
    public native boolean setOutputWindow(Surface surface);
    public native boolean feedNv21(byte[] nv21, int width, int height, int orientation);
    public native boolean feedBitmap(android.graphics.Bitmap bitmap, int orientation);

    static {
        System.loadLibrary("yolo11ncnn");
        try {
            System.loadLibrary("yolo11ncnn_feed");
        } catch (Throwable t) {
            android.util.Log.w("YOLO11Ncnn", "Failed to load yolo11ncnn_feed: " + t.getMessage());
        }
    }
}
