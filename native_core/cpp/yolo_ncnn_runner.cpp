#include "yolo_ncnn_c_api.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <string>
#include <vector>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#endif

// Tencent NCNN headers
#include "net.h"
#include "mat.h"
#if NCNN_VULKAN
#include "gpu.h"
#endif

// Compatibility bridge for NDK 28 libc++ where __hash_memory was inlined
namespace std {
namespace __ndk1 {
    size_t __hash_memory(const void* __s, size_t __len) {
        return std::__murmur2_or_cityhash<size_t>()(__s, __len);
    }
}
}

// Rust C-ABI forward declaration linked via libyolo_rust.a
extern "C" {
    int yolo_rust_init(void);
    void yolo_rust_destroy(void);
    int yolo_rust_process_frame(
        const float* raw_tensor,
        float scale,
        float pad_w,
        float pad_h,
        uint32_t frame_id,
        YoloFrameResult* out_result
    );
}

namespace {

struct EngineContext {
    ncnn::Net net;
    std::string in_blob_name = "in0";
    std::string out_blob_name = "out0";
    int active_backend = 0; // 0=CPU, 1=Vulkan
    bool initialized = false;
    uint32_t frame_counter = 0;

    // Fixed static scratch buffers to guarantee ZERO heap allocation per frame
    // 640 x 640 x 3 = 1,228,800 bytes
    uint8_t rgb_letterbox_buf[640 * 640 * 3];
    // 84 * 8400 = 705,600 floats = 2,822,400 bytes
    float raw_output_tensor[84 * 8400];
};

static EngineContext g_ctx;

// Helper: parse model.ncnn.param to extract dynamic input and output blob names
void parse_param_blob_names(const char* param_path, std::string& in_name, std::string& out_name) {
    FILE* fp = fopen(param_path, "rb");
    if (!fp) return;

    char line[512];
    std::string last_blob;
    bool found_in = false;

    while (fgets(line, sizeof(line), fp)) {
        char layer_type[64];
        char layer_name[64];
        int num_in = 0;
        int num_out = 0;
        if (sscanf(line, "%63s %63s %d %d", layer_type, layer_name, &num_in, &num_out) >= 4) {
            if (strcmp(layer_type, "Input") == 0 && !found_in) {
                // The output blob of the Input layer is the input blob name
                char in_blob[64];
                if (sscanf(line, "%*s %*s %*d %*d %63s", in_blob) == 1) {
                    in_name = in_blob;
                    found_in = true;
                }
            }
            if (num_out > 0) {
                char out_blob[64];
                // Read the output blob name
                // Format: layer_type layer_name num_in num_out [in_blobs...] [out_blobs...]
                char* p = line;
                for (int i = 0; i < 4; ++i) {
                    while (*p && *p != ' ' && *p != '\t') p++;
                    while (*p == ' ' || *p == '\t') p++;
                }
                for (int i = 0; i < num_in; ++i) {
                    while (*p && *p != ' ' && *p != '\t') p++;
                    while (*p == ' ' || *p == '\t') p++;
                }
                if (sscanf(p, "%63s", out_blob) == 1) {
                    last_blob = out_blob;
                }
            }
        }
    }
    fclose(fp);
    if (!last_blob.empty()) {
        out_name = last_blob;
    }
}

// Clamp utility
inline uint8_t clamp_u8(int v) {
    return (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
}

// Convert single YUV pixel (BT.601) to RGB
inline void yuv_to_rgb(uint8_t y, uint8_t u, uint8_t v, uint8_t* r, uint8_t* g, uint8_t* b) {
    int c = (int)y - 16;
    int d = (int)u - 128;
    int e = (int)v - 128;
    if (c < 0) c = 0;

    int r_val = (298 * c + 409 * e + 128) >> 8;
    int g_val = (298 * c - 100 * d - 208 * e + 128) >> 8;
    int b_val = (298 * c + 516 * d + 128) >> 8;

    *r = clamp_u8(r_val);
    *g = clamp_u8(g_val);
    *b = clamp_u8(b_val);
}

} // namespace

extern "C" {

int yolo_engine_init(const char* param_path, const char* bin_path, int use_vulkan) {
    if (!param_path || !bin_path) return -1;

    g_ctx.net.clear();
    g_ctx.net.opt = ncnn::Option();
    g_ctx.net.opt.num_threads = 4;
    g_ctx.net.opt.use_fp16_packed = true;
    g_ctx.net.opt.use_fp16_storage = true;
    g_ctx.net.opt.use_fp16_arithmetic = true;

    g_ctx.active_backend = 0;
#if NCNN_VULKAN
    if (use_vulkan && ncnn::get_gpu_count() > 0) {
        g_ctx.net.opt.use_vulkan_compute = true;
        g_ctx.net.set_vulkan_device(0);
        g_ctx.active_backend = 1;
    } else {
        g_ctx.net.opt.use_vulkan_compute = false;
        g_ctx.active_backend = 0;
    }
#else
    g_ctx.net.opt.use_vulkan_compute = false;
    g_ctx.active_backend = 0;
#endif

    // Parse blob names dynamically from param
    parse_param_blob_names(param_path, g_ctx.in_blob_name, g_ctx.out_blob_name);

    int ret_param = g_ctx.net.load_param(param_path);
    if (ret_param != 0) return -2;

    int ret_bin = g_ctx.net.load_model(bin_path);
    if (ret_bin != 0) return -3;

    yolo_rust_init();

    g_ctx.initialized = true;
    g_ctx.frame_counter = 0;
    return 0;
}

int yolo_engine_set_backend(int use_vulkan) {
    if (!g_ctx.initialized) return -1;
#if NCNN_VULKAN
    if (use_vulkan && ncnn::get_gpu_count() > 0) {
        g_ctx.net.opt.use_vulkan_compute = true;
        g_ctx.active_backend = 1;
    } else {
        g_ctx.net.opt.use_vulkan_compute = false;
        g_ctx.active_backend = 0;
    }
    return g_ctx.active_backend;
#else
    (void)use_vulkan;
    g_ctx.active_backend = 0;
    return 0;
#endif
}

int yolo_engine_forward_yuv420(
    const uint8_t* y_plane,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int width,
    int height,
    int y_row_stride,
    int uv_row_stride,
    int uv_pixel_stride,
    int sensor_orientation,
    YoloFrameResult* out_result
) {
    if (!g_ctx.initialized || !out_result) return -1;
    if (!y_plane || !u_plane || !v_plane) return -2;
    if (width <= 0 || height <= 0) return -3;

    auto t0 = std::chrono::high_resolution_clock::now();

    // 1. Calculate letterbox scale and paddings for 640x640 target
    int target_w = 640;
    int target_h = 640;
    float scale = std::min((float)target_w / (float)width, (float)target_h / (float)height);
    int scaled_w = (int)(width * scale);
    int scaled_h = (int)(height * scale);
    int pad_w = (target_w - scaled_w) / 2;
    int pad_h = (target_h - scaled_h) / 2;

    // Fill letterbox canvas with 114 gray background (zero heap allocation)
    memset(g_ctx.rgb_letterbox_buf, 114, target_w * target_h * 3);

    // 2. Direct YUV420 to RGB with nearest/bilinear scaling into letterbox center
    // Handles both I420 (uv_pixel_stride=1) and NV21 (uv_pixel_stride=2, v before u)
    for (int dy = 0; dy < scaled_h; ++dy) {
        int sy = (int)(dy / scale);
        if (sy >= height) sy = height - 1;
        const uint8_t* y_row = y_plane + sy * y_row_stride;
        const uint8_t* u_row = u_plane + (sy / 2) * uv_row_stride;
        const uint8_t* v_row = v_plane + (sy / 2) * uv_row_stride;

        uint8_t* dst_row = g_ctx.rgb_letterbox_buf + ((pad_h + dy) * target_w + pad_w) * 3;

        for (int dx = 0; dx < scaled_w; ++dx) {
            int sx = (int)(dx / scale);
            if (sx >= width) sx = width - 1;

            uint8_t y = y_row[sx];
            uint8_t u = u_row[(sx / 2) * uv_pixel_stride];
            uint8_t v = v_row[(sx / 2) * uv_pixel_stride];

            yuv_to_rgb(y, u, v, &dst_row[dx * 3], &dst_row[dx * 3 + 1], &dst_row[dx * 3 + 2]);
        }
    }

    // 3. Create NCNN Mat from RGB letterbox buffer
    ncnn::Mat in_mat = ncnn::Mat::from_pixels(g_ctx.rgb_letterbox_buf, ncnn::Mat::PIXEL_RGB, target_w, target_h);
    const float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    in_mat.substract_mean_normalize(0, norm_vals);

    // 4. Run NCNN forward inference
    ncnn::Extractor ex = g_ctx.net.create_extractor();
    ex.input(g_ctx.in_blob_name.c_str(), in_mat);

    ncnn::Mat out_mat;
    int ret = ex.extract(g_ctx.out_blob_name.c_str(), out_mat);
    if (ret != 0) {
        out_result->status_code = ret;
        return -4;
    }

    // Copy raw output tensor [84, 8400] to pre-allocated float buffer
    // out_mat: w=8400, h=84
    memcpy(g_ctx.raw_output_tensor, (const float*)out_mat.data, 84 * 8400 * sizeof(float));

    auto t1 = std::chrono::high_resolution_clock::now();
    float inference_ms = std::chrono::duration<float, std::milli>(t1 - t0).count();

    // 5. Delegate Post-Processing, NMS, and Multi-Object Tracking to Rust Core
    auto t2 = std::chrono::high_resolution_clock::now();
    int rust_ret = yolo_rust_process_frame(
        g_ctx.raw_output_tensor,
        scale,
        (float)pad_w,
        (float)pad_h,
        g_ctx.frame_counter++,
        out_result
    );
    auto t3 = std::chrono::high_resolution_clock::now();
    float tracker_ms = std::chrono::duration<float, std::milli>(t3 - t2).count();

    out_result->frame_id = g_ctx.frame_counter;
    out_result->inference_time_ms = inference_ms;
    out_result->tracker_time_ms = tracker_ms;
    out_result->active_backend = g_ctx.active_backend;
    out_result->status_code = rust_ret;

    return 0;
}

int yolo_engine_forward_rgba(
    const uint8_t* rgba,
    int width,
    int height,
    int sensor_orientation,
    YoloFrameResult* out_result
) {
    if (!g_ctx.initialized || !out_result) return -1;
    if (!rgba || width <= 0 || height <= 0) return -2;

    auto t0 = std::chrono::high_resolution_clock::now();

    int target_w = 640;
    int target_h = 640;
    float scale = std::min((float)target_w / (float)width, (float)target_h / (float)height);
    int scaled_w = (int)(width * scale);
    int scaled_h = (int)(height * scale);
    int pad_w = (target_w - scaled_w) / 2;
    int pad_h = (target_h - scaled_h) / 2;

    memset(g_ctx.rgb_letterbox_buf, 114, target_w * target_h * 3);

    for (int dy = 0; dy < scaled_h; ++dy) {
        int sy = (int)(dy / scale);
        if (sy >= height) sy = height - 1;
        const uint8_t* src_row = rgba + sy * width * 4;
        uint8_t* dst_row = g_ctx.rgb_letterbox_buf + ((pad_h + dy) * target_w + pad_w) * 3;

        for (int dx = 0; dx < scaled_w; ++dx) {
            int sx = (int)(dx / scale);
            if (sx >= width) sx = width - 1;
            dst_row[dx * 3]     = src_row[sx * 4];     // R
            dst_row[dx * 3 + 1] = src_row[sx * 4 + 1]; // G
            dst_row[dx * 3 + 2] = src_row[sx * 4 + 2]; // B
        }
    }

    ncnn::Mat in_mat = ncnn::Mat::from_pixels(g_ctx.rgb_letterbox_buf, ncnn::Mat::PIXEL_RGB, target_w, target_h);
    const float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    in_mat.substract_mean_normalize(0, norm_vals);

    ncnn::Extractor ex = g_ctx.net.create_extractor();
    ex.input(g_ctx.in_blob_name.c_str(), in_mat);

    ncnn::Mat out_mat;
    int ret = ex.extract(g_ctx.out_blob_name.c_str(), out_mat);
    if (ret != 0) {
        out_result->status_code = ret;
        return -4;
    }

    memcpy(g_ctx.raw_output_tensor, (const float*)out_mat.data, 84 * 8400 * sizeof(float));

    auto t1 = std::chrono::high_resolution_clock::now();
    float inference_ms = std::chrono::duration<float, std::milli>(t1 - t0).count();

    auto t2 = std::chrono::high_resolution_clock::now();
    int rust_ret = yolo_rust_process_frame(
        g_ctx.raw_output_tensor,
        scale,
        (float)pad_w,
        (float)pad_h,
        g_ctx.frame_counter++,
        out_result
    );
    auto t3 = std::chrono::high_resolution_clock::now();
    float tracker_ms = std::chrono::duration<float, std::milli>(t3 - t2).count();

    out_result->frame_id = g_ctx.frame_counter;
    out_result->inference_time_ms = inference_ms;
    out_result->tracker_time_ms = tracker_ms;
    out_result->active_backend = g_ctx.active_backend;
    out_result->status_code = rust_ret;

    return 0;
}

void yolo_engine_destroy(void) {
    if (g_ctx.initialized) {
        g_ctx.net.clear();
        yolo_rust_destroy();
        g_ctx.initialized = false;
    }
}

} // extern "C"
