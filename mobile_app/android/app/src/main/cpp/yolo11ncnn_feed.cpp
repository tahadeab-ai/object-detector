#include <jni.h>
#include <dlfcn.h>
#include <android/log.h>
#include <android/bitmap.h>
#include <stdint.h>
#include <vector>

#define TAG "YOLO11NcnnFeed"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

typedef void (*on_image_fn)(void* thiz, const unsigned char* nv21, int width, int height);

static void* g_camera_ptr = nullptr;
static on_image_fn s_on_image = nullptr;

static bool init_symbols() {
    void* handle = dlopen("libyolo11ncnn.so", RTLD_NOW);
    if (!handle) {
        LOGE("Failed to dlopen libyolo11ncnn.so: %s", dlerror());
        return false;
    }

    if (!s_on_image) {
        s_on_image = (on_image_fn)dlsym(handle, "_ZNK15NdkCameraWindow8on_imageEPKhii");
        if (!s_on_image) {
            LOGE("Failed to find _ZNK15NdkCameraWindow8on_imageEPKhii");
            return false;
        }
    }

    // In libyolo11ncnn.so, g_camera is stored at offset 0x00c574d0
    Dl_info info;
    if (dladdr((void*)s_on_image, &info) && info.dli_fbase) {
        uintptr_t base = (uintptr_t)info.dli_fbase;
        void** g_camera_slot = (void**)(base + 0x00c574d0);
        g_camera_ptr = *g_camera_slot;
        return g_camera_ptr != nullptr;
    }
    return false;
}

static bool is_surface_window_ready() {
    if (!init_symbols() || !g_camera_ptr || !s_on_image) {
        return false;
    }
    // NdkCameraWindow::win is stored at offset 120 (0x78)
    void* win = *(void**)((uintptr_t)g_camera_ptr + 120);
    return win != nullptr;
}

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_tencent_yolo11ncnn_YOLO11Ncnn_feedNv21(JNIEnv* env, jobject thiz, jbyteArray nv21Array, jint width, jint height, jint orientation) {
    if (!is_surface_window_ready()) {
        LOGI("feedNv21: Surface window not ready or ANativeWindow is null");
        return JNI_FALSE;
    }

    int* p_facing = (int*)((uintptr_t)g_camera_ptr + 8);
    int* p_orientation = (int*)((uintptr_t)g_camera_ptr + 12);

    int old_facing = *p_facing;
    int old_orientation = *p_orientation;

    *p_facing = 0;
    *p_orientation = orientation;

    jbyte* bytes = env->GetByteArrayElements(nv21Array, nullptr);
    if (bytes) {
        try {
            s_on_image(g_camera_ptr, (const unsigned char*)bytes, width, height);
        } catch (...) {
            LOGE("feedNv21: Exception inside s_on_image");
        }
        env->ReleaseByteArrayElements(nv21Array, bytes, JNI_ABORT);
    }

    *p_facing = old_facing;
    *p_orientation = old_orientation;

    return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_com_tencent_yolo11ncnn_YOLO11Ncnn_feedBitmap(JNIEnv* env, jobject thiz, jobject bitmap, jint orientation) {
    if (!is_surface_window_ready()) {
        LOGI("feedBitmap: Surface window not ready or ANativeWindow is null");
        return JNI_FALSE;
    }

    AndroidBitmapInfo info;
    if (AndroidBitmap_getInfo(env, bitmap, &info) < 0) {
        LOGE("AndroidBitmap_getInfo failed");
        return JNI_FALSE;
    }

    void* pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, &pixels) < 0 || !pixels) {
        LOGE("AndroidBitmap_lockPixels failed");
        return JNI_FALSE;
    }

    int width = info.width;
    int height = info.height;
    int stride = info.stride;

    int y_size = width * height;
    int nv21_size = y_size * 3 / 2;
    std::vector<unsigned char> nv21(nv21_size);
    unsigned char* y_plane = nv21.data();
    unsigned char* uv_plane = y_plane + y_size;

    const uint8_t* src = (const uint8_t*)pixels;
    for (int y = 0; y < height; y++) {
        const uint32_t* row = (const uint32_t*)(src + y * stride);
        for (int x = 0; x < width; x++) {
            uint32_t c = row[x];
            int r = c & 0xff;
            int g = (c >> 8) & 0xff;
            int b = (c >> 16) & 0xff;

            int y_val = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
            y_plane[y * width + x] = (unsigned char)(y_val < 0 ? 0 : (y_val > 255 ? 255 : y_val));

            if ((y % 2 == 0) && (x % 2 == 0)) {
                int u_val = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                int v_val = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                int uv_idx = (y / 2) * width + x;
                uv_plane[uv_idx] = (unsigned char)(v_val < 0 ? 0 : (v_val > 255 ? 255 : v_val));
                uv_plane[uv_idx + 1] = (unsigned char)(u_val < 0 ? 0 : (u_val > 255 ? 255 : u_val));
            }
        }
    }

    AndroidBitmap_unlockPixels(env, bitmap);

    int* p_facing = (int*)((uintptr_t)g_camera_ptr + 8);
    int* p_orientation = (int*)((uintptr_t)g_camera_ptr + 12);

    int old_facing = *p_facing;
    int old_orientation = *p_orientation;

    *p_facing = 0;
    *p_orientation = orientation;

    try {
        s_on_image(g_camera_ptr, nv21.data(), width, height);
    } catch (...) {
        LOGE("feedBitmap: Exception inside s_on_image");
    }

    *p_facing = old_facing;
    *p_orientation = old_orientation;

    return JNI_TRUE;
}

}
