package com.tencent.yolo11ncnn;

import android.content.res.AssetManager;
import android.view.Surface;

public class YOLO11Ncnn {
    public native boolean loadModel(AssetManager mgr, int taskid, int modelid, int cpugpu);
    public native boolean openCamera(int facing);
    public native boolean closeCamera();
    public native boolean setOutputWindow(Surface surface);

    static {
        System.loadLibrary("yolo11ncnn");
    }
}
