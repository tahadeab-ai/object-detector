#include "yolo_ncnn_c_api.h"

#include <android/log.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cfloat>
#include <mutex>
#include <string>
#include <vector>

#include <net.h>
#include <mat.h>
#include <cpu.h>

#if NCNN_VULKAN
#include <gpu.h>
#endif

#define LOG_TAG "YoloNcnnNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Compatibility bridge for NDK 28 libc++ where __hash_memory was inlined
namespace std {
inline namespace __ndk1 {
    size_t __hash_memory(const void* __s, size_t __len) {
        return std::__murmur2_or_cityhash<size_t>()(__s, __len);
    }
}
}

namespace {

struct CandidateObject {
    float x0, y0, x1, y1; // normalized [0.0, 1.0]
    int label;
    float prob;
    int anchor_idx;
};

struct EngineContext {
    ncnn::Net net;
    int active_task = YOLO_TASK_DETECTION;
    int target_size = 320; // default 320 matching nihui for 35+ FPS on Galaxy Note 10
    std::string in_blob_name = "in0";
    std::string out_blob_name = "out0";
    std::string param_path;
    std::string bin_path;
    int active_backend = 0; // 0=CPU, 1=Vulkan, 2=Turnip
    bool initialized = false;
    bool gpu_instance_created = false;
    int current_gpu_driver = -1; // -1=none, 1=standard vulkan, 2=turnip
    uint32_t frame_counter = 0;

    // Fixed static scratch buffer up to 1024 x 1024 x 3 = 3,145,728 bytes (Zero heap alloc per frame)
    uint8_t rgb_letterbox_buf[1024 * 1024 * 3];
};

static EngineContext g_ctx;
static std::mutex g_engine_mutex;

static inline float fast_sigmoid(float x) {
    return 1.0f / (1.0f + expf(-x));
}

static inline uint8_t clamp_u8(int v) {
    return (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
}

static inline void yuv_to_rgb(uint8_t y, uint8_t u, uint8_t v, uint8_t* r, uint8_t* g, uint8_t* b) {
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

// QuickSort descending by probability
static void qsort_candidates_descent(std::vector<CandidateObject>& objects, int left, int right) {
    int i = left;
    int j = right;
    float p = objects[(left + right) / 2].prob;

    while (i <= j) {
        while (objects[i].prob > p) i++;
        while (objects[j].prob < p) j--;
        if (i <= j) {
            std::swap(objects[i], objects[j]);
            i++;
            j--;
        }
    }
    if (left < j) qsort_candidates_descent(objects, left, j);
    if (i < right) qsort_candidates_descent(objects, i, right);
}

static void sort_candidates_descent(std::vector<CandidateObject>& objects) {
    if (objects.empty()) return;
    qsort_candidates_descent(objects, 0, (int)objects.size() - 1);
}

static inline float calc_norm_iou(float ax1, float ay1, float ax2, float ay2,
                                  float bx1, float by1, float bx2, float by2) {
    float ix1 = std::max(ax1, bx1);
    float iy1 = std::max(ay1, by1);
    float ix2 = std::min(ax2, bx2);
    float iy2 = std::min(ay2, by2);
    float iw = std::max(0.0f, ix2 - ix1);
    float ih = std::max(0.0f, iy2 - iy1);
    float inter = iw * ih;
    float area_a = (ax2 - ax1) * (ay2 - ay1);
    float area_b = (bx2 - bx1) * (by2 - by1);
    float union_area = area_a + area_b - inter;
    if (union_area <= 0.0f) return 0.0f;
    return inter / union_area;
}

static void nms_filter_candidates(const std::vector<CandidateObject>& src, std::vector<int>& picked, float nms_threshold, bool agnostic = false) {
    picked.clear();
    const int n = (int)src.size();
    for (int i = 0; i < n; i++) {
        const CandidateObject& a = src[i];
        int keep = 1;
        for (int j = 0; j < (int)picked.size(); j++) {
            const CandidateObject& b = src[picked[j]];
            if (!agnostic && a.label != b.label) continue;
            if (calc_norm_iou(a.x0, a.y0, a.x1, a.y1, b.x0, b.y0, b.x1, b.y1) > nms_threshold) {
                keep = 0;
                break;
            }
        }
        if (keep) picked.push_back(i);
    }
}

// Convert YUV420 to RGB Letterbox buffer with dynamic stride-32 padding and rotation
int prepare_letterbox_yuv_stride32(
    const uint8_t* y_plane,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int width,
    int height,
    int y_row_stride,
    int uv_row_stride,
    int uv_pixel_stride,
    int sensor_orientation,
    int target_size,
    float& scale,
    int& pad_w,
    int& pad_h,
    int& in_w,
    int& in_h,
    int& rot_w,
    int& rot_h
) {
    rot_w = width;
    rot_h = height;
    if (sensor_orientation == 90 || sensor_orientation == 270) {
        rot_w = height;
        rot_h = width;
    }

    scale = std::min((float)target_size / (float)rot_w, (float)target_size / (float)rot_h);
    int scaled_w = (int)(rot_w * scale);
    int scaled_h = (int)(rot_h * scale);

    int wpad = (scaled_w + 31) / 32 * 32 - scaled_w;
    int hpad = (scaled_h + 31) / 32 * 32 - scaled_h;
    in_w = scaled_w + wpad;
    in_h = scaled_h + hpad;
    pad_w = wpad / 2;
    pad_h = hpad / 2;

    memset(g_ctx.rgb_letterbox_buf, 114, in_w * in_h * 3);

    for (int dy = 0; dy < scaled_h; ++dy) {
        int ry = (int)(dy / scale);
        if (ry >= rot_h) ry = rot_h - 1;

        uint8_t* dst_row = g_ctx.rgb_letterbox_buf + ((pad_h + dy) * in_w + pad_w) * 3;

        for (int dx = 0; dx < scaled_w; ++dx) {
            int rx = (int)(dx / scale);
            if (rx >= rot_w) rx = rot_w - 1;

            int sx = rx;
            int sy = ry;
            if (sensor_orientation == 90) {
                sx = ry;
                sy = height - 1 - rx;
            } else if (sensor_orientation == 270) {
                sx = width - 1 - ry;
                sy = rx;
            } else if (sensor_orientation == 180) {
                sx = width - 1 - rx;
                sy = height - 1 - ry;
            }

            if (sx < 0) sx = 0;
            if (sx >= width) sx = width - 1;
            if (sy < 0) sy = 0;
            if (sy >= height) sy = height - 1;

            const uint8_t* y_ptr = y_plane + sy * y_row_stride;
            const uint8_t* u_ptr = u_plane + (sy / 2) * uv_row_stride;
            const uint8_t* v_ptr = v_plane + (sy / 2) * uv_row_stride;

            uint8_t y_val = y_ptr[sx];
            uint8_t u_val = u_ptr[(sx / 2) * uv_pixel_stride];
            uint8_t v_val = v_ptr[(sx / 2) * uv_pixel_stride];

            yuv_to_rgb(y_val, u_val, v_val, &dst_row[dx * 3], &dst_row[dx * 3 + 1], &dst_row[dx * 3 + 2]);
        }
    }
    return 0;
}

// Convert RGBA to RGB Letterbox buffer with dynamic stride-32 padding and rotation
int prepare_letterbox_rgba_stride32(
    const uint8_t* rgba,
    int width,
    int height,
    int sensor_orientation,
    int target_size,
    float& scale,
    int& pad_w,
    int& pad_h,
    int& in_w,
    int& in_h,
    int& rot_w,
    int& rot_h
) {
    rot_w = width;
    rot_h = height;
    if (sensor_orientation == 90 || sensor_orientation == 270) {
        rot_w = height;
        rot_h = width;
    }

    scale = std::min((float)target_size / (float)rot_w, (float)target_size / (float)rot_h);
    int scaled_w = (int)(rot_w * scale);
    int scaled_h = (int)(rot_h * scale);

    int wpad = (scaled_w + 31) / 32 * 32 - scaled_w;
    int hpad = (scaled_h + 31) / 32 * 32 - scaled_h;
    in_w = scaled_w + wpad;
    in_h = scaled_h + hpad;
    pad_w = wpad / 2;
    pad_h = hpad / 2;

    memset(g_ctx.rgb_letterbox_buf, 114, in_w * in_h * 3);

    for (int dy = 0; dy < scaled_h; ++dy) {
        int ry = (int)(dy / scale);
        if (ry >= rot_h) ry = rot_h - 1;

        uint8_t* dst_row = g_ctx.rgb_letterbox_buf + ((pad_h + dy) * in_w + pad_w) * 3;

        for (int dx = 0; dx < scaled_w; ++dx) {
            int rx = (int)(dx / scale);
            if (rx >= rot_w) rx = rot_w - 1;

            int sx = rx;
            int sy = ry;
            if (sensor_orientation == 90) {
                sx = ry;
                sy = height - 1 - rx;
            } else if (sensor_orientation == 270) {
                sx = width - 1 - ry;
                sy = rx;
            } else if (sensor_orientation == 180) {
                sx = width - 1 - rx;
                sy = height - 1 - ry;
            }

            if (sx < 0) sx = 0;
            if (sx >= width) sx = width - 1;
            if (sy < 0) sy = 0;
            if (sy >= height) sy = height - 1;

            const uint8_t* src_pixel = rgba + (sy * width + sx) * 4;
            dst_row[dx * 3 + 0] = src_pixel[0];
            dst_row[dx * 3 + 1] = src_pixel[1];
            dst_row[dx * 3 + 2] = src_pixel[2];
        }
    }
    return 0;
}

// 144-Channel Pre-DFL Decoder matching nihui's prob_threshold = 0.25f
void decode_yolo11_detection(
    const ncnn::Mat& out0,
    int in_w,
    int in_h,
    int pad_w,
    int pad_h,
    float scale,
    int rot_w,
    int rot_h,
    float conf_threshold,
    std::vector<CandidateObject>& detections
) {
    detections.clear();
    const std::vector<int> strides = {8, 16, 32};
    int row_offset = 0;
    std::vector<CandidateObject> proposals;

    for (int s : strides) {
        int num_grid_x = in_w / s;
        int num_grid_y = in_h / s;
        int num_anchors = num_grid_x * num_grid_y;

        for (int y = 0; y < num_grid_y; ++y) {
            for (int x = 0; x < num_grid_x; ++x) {
                int anchor_idx = row_offset + y * num_grid_x + x;
                if (anchor_idx >= out0.h) continue;
                const float* feat = out0.row(anchor_idx);

                // Class logits are channels 64..143 (80 classes)
                const float* class_logits = feat + 64;
                int best_class = 0;
                float max_logit = class_logits[0];
                for (int c = 1; c < 80; ++c) {
                    if (class_logits[c] > max_logit) {
                        max_logit = class_logits[c];
                        best_class = c;
                    }
                }

                // Pre-DFL early score exit: matches nihui's 0.25 threshold
                float score = fast_sigmoid(max_logit);
                if (score < conf_threshold) continue;

                // 16-bin Softmax DFL for 4 edges (left, top, right, bottom)
                float ltrb[4];
                for (int k = 0; k < 4; ++k) {
                    const float* dfl_ptr = feat + k * 16;
                    float max_v = dfl_ptr[0];
                    for (int b = 1; b < 16; ++b) {
                        if (dfl_ptr[b] > max_v) max_v = dfl_ptr[b];
                    }
                    float sum_exp = 0.0f;
                    float exp_b[16];
                    for (int b = 0; b < 16; ++b) {
                        exp_b[b] = expf(dfl_ptr[b] - max_v);
                        sum_exp += exp_b[b];
                    }
                    float dist = 0.0f;
                    float inv_sum = 1.0f / sum_exp;
                    for (int b = 0; b < 16; ++b) {
                        dist += b * (exp_b[b] * inv_sum);
                    }
                    ltrb[k] = dist * s;
                }

                float pb_cx = (x + 0.5f) * s;
                float pb_cy = (y + 0.5f) * s;
                float raw_x0 = pb_cx - ltrb[0];
                float raw_y0 = pb_cy - ltrb[1];
                float raw_x1 = pb_cx + ltrb[2];
                float raw_y1 = pb_cy + ltrb[3];

                // Unpad and normalize to [0.0, 1.0] relative to upright frame (rot_w, rot_h)
                float norm_x0 = (raw_x0 - pad_w) / (scale * rot_w);
                float norm_y0 = (raw_y0 - pad_h) / (scale * rot_h);
                float norm_x1 = (raw_x1 - pad_w) / (scale * rot_w);
                float norm_y1 = (raw_y1 - pad_h) / (scale * rot_h);

                norm_x0 = std::max(0.0f, std::min(1.0f, norm_x0));
                norm_y0 = std::max(0.0f, std::min(1.0f, norm_y0));
                norm_x1 = std::max(0.0f, std::min(1.0f, norm_x1));
                norm_y1 = std::max(0.0f, std::min(1.0f, norm_y1));

                CandidateObject obj;
                obj.x0 = norm_x0;
                obj.y0 = norm_y0;
                obj.x1 = norm_x1;
                obj.y1 = norm_y1;
                obj.label = best_class;
                obj.prob = score;
                obj.anchor_idx = anchor_idx;
                proposals.push_back(obj);
            }
        }
        row_offset += num_anchors;
    }

    // Class-aware NMS matching nihui nms_threshold = 0.45f
    sort_candidates_descent(proposals);
    std::vector<int> picked;
    nms_filter_candidates(proposals, picked, 0.45f, false);

    for (int idx : picked) {
        detections.push_back(proposals[idx]);
    }
}

static int setup_backend_internal(int backend) {
#if NCNN_VULKAN
    if (backend == 1 || backend == 2) {
        if (!g_ctx.gpu_instance_created) {
            ncnn::create_gpu_instance();
            g_ctx.gpu_instance_created = true;
            g_ctx.current_gpu_driver = -1;
        }

        if (g_ctx.current_gpu_driver != backend) {
            int gpu_count = ncnn::get_gpu_count();
            if (gpu_count > 0) {
                g_ctx.net.opt.use_vulkan_compute = true;
                g_ctx.net.set_vulkan_device(0);
                g_ctx.active_backend = backend;
                g_ctx.current_gpu_driver = backend;
                LOGI("setup_backend_internal: GPU activated (backend=%d, dev=0, count=%d)", backend, gpu_count);
                return backend;
            } else {
                LOGW("setup_backend_internal: No Vulkan GPU devices found; falling back to CPU");
                backend = 0;
            }
        }
    }

    // CPU fallback
    g_ctx.net.opt.use_vulkan_compute = false;
    g_ctx.active_backend = 0;
    return 0;
#else
    g_ctx.active_backend = 0;
    LOGI("setup_backend_internal: NCNN_VULKAN not compiled in; using CPU");
    return 0;
#endif
}

} // namespace

extern "C" {

// =============================================================================
// Primary Detection Engine API (100% C++ Unified Pipeline)
// =============================================================================

int yolo_engine_init(const char* param_path, const char* bin_path, int use_vulkan) {
    return yolo_multitask_init(YOLO_TASK_DETECTION, param_path, bin_path, 320, use_vulkan);
}

int yolo_engine_set_backend(int use_vulkan) {
    return yolo_multitask_set_backend(use_vulkan);
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
    return yolo_multitask_forward_yuv420(
        y_plane, u_plane, v_plane,
        width, height,
        y_row_stride, uv_row_stride, uv_pixel_stride,
        sensor_orientation,
        (void*)out_result
    );
}

int yolo_engine_forward_rgba(
    const uint8_t* rgba,
    int width,
    int height,
    int sensor_orientation,
    YoloFrameResult* out_result
) {
    return yolo_multitask_forward_rgba(rgba, width, height, sensor_orientation, (void*)out_result);
}

void yolo_engine_destroy(void) {
    yolo_multitask_destroy();
}

// =============================================================================
// Multi-Task & Dynamic Stride-32 API Implementation
// =============================================================================

int yolo_multitask_init(
    int task_id,
    const char* param_path,
    const char* bin_path,
    int target_size,
    int backend
) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);

    if (!param_path || !bin_path) {
        LOGE("yolo_multitask_init: null paths passed");
        return -1;
    }

    g_ctx.active_task = task_id;
    g_ctx.target_size = target_size > 0 ? target_size : 320;
    g_ctx.param_path = param_path;
    g_ctx.bin_path = bin_path;

    g_ctx.net.clear();

    // Fast FP16 mobile optimization
    g_ctx.net.opt.use_fp16_packed = true;
    g_ctx.net.opt.use_fp16_storage = true;
    g_ctx.net.opt.use_fp16_arithmetic = true;
    g_ctx.net.opt.use_packing_layout = true;
    g_ctx.net.opt.num_threads = 4;

    setup_backend_internal(backend);

    int ret_param = g_ctx.net.load_param(param_path);
    int ret_bin = g_ctx.net.load_model(bin_path);

    if ((ret_param != 0 || ret_bin != 0) && g_ctx.active_backend > 0) {
        LOGE("yolo_multitask_init: GPU load failed (param=%d, bin=%d), falling back to CPU", ret_param, ret_bin);
        g_ctx.net.clear();
        setup_backend_internal(0);
        g_ctx.net.opt.num_threads = 4;
        g_ctx.net.opt.use_fp16_packed = true;
        g_ctx.net.opt.use_fp16_storage = true;
        g_ctx.net.opt.use_fp16_arithmetic = true;
        ret_param = g_ctx.net.load_param(param_path);
        ret_bin = g_ctx.net.load_model(bin_path);
    }

    if (ret_param != 0) {
        LOGE("yolo_multitask_init: load_param failed (%d) for task %d", ret_param, task_id);
        return -2;
    }
    if (ret_bin != 0) {
        LOGE("yolo_multitask_init: load_model failed (%d) for task %d", ret_bin, task_id);
        return -3;
    }

    g_ctx.initialized = true;
    LOGI("yolo_multitask_init: SUCCESS, task=%d, size=%d, backend=%d", g_ctx.active_task, g_ctx.target_size, g_ctx.active_backend);
    return 0;
}

int yolo_multitask_set_target_size(int target_size) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    if (target_size <= 0) return -1;
    g_ctx.target_size = target_size;
    LOGI("yolo_multitask_set_target_size: target_size set to %d", g_ctx.target_size);
    return 0;
}

int yolo_multitask_set_backend(int backend) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    if (!g_ctx.initialized) {
        g_ctx.active_backend = backend;
        return 0;
    }

    g_ctx.net.clear();
    setup_backend_internal(backend);

    g_ctx.net.opt.num_threads = 4;
    g_ctx.net.opt.use_fp16_packed = true;
    g_ctx.net.opt.use_fp16_storage = true;
    g_ctx.net.opt.use_fp16_arithmetic = true;

    int ret_param = g_ctx.net.load_param(g_ctx.param_path.c_str());
    int ret_bin = g_ctx.net.load_model(g_ctx.bin_path.c_str());

    if (ret_param != 0 || ret_bin != 0) {
        LOGE("yolo_multitask_set_backend: Reload failed, falling back to CPU");
        g_ctx.net.clear();
        setup_backend_internal(0);
        g_ctx.net.load_param(g_ctx.param_path.c_str());
        g_ctx.net.load_model(g_ctx.bin_path.c_str());
    }
    return g_ctx.active_backend;
}

int yolo_multitask_get_active_task(void) {
    return g_ctx.active_task;
}

int yolo_multitask_forward_yuv420(
    const uint8_t* y_plane,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int width,
    int height,
    int y_row_stride,
    int uv_row_stride,
    int uv_pixel_stride,
    int sensor_orientation,
    void* out_result_buffer
) {
    if (!g_ctx.initialized || !out_result_buffer) return -1;
    if (!y_plane || !u_plane || !v_plane) return -2;
    if (width <= 0 || height <= 0) return -3;

    // Per-worker thread affinity and thread count
    thread_local bool s_thread_init = false;
    if (!s_thread_init) {
        ncnn::set_cpu_powersave(2);
        ncnn::set_omp_num_threads(4);
        s_thread_init = true;
    }

    std::lock_guard<std::mutex> lock(g_engine_mutex);

    auto t0 = std::chrono::high_resolution_clock::now();

    float scale = 1.0f;
    int pad_w = 0, pad_h = 0, in_w = 0, in_h = 0, rot_w = width, rot_h = height;
    int target_size = g_ctx.target_size;

    prepare_letterbox_yuv_stride32(
        y_plane, u_plane, v_plane,
        width, height,
        y_row_stride, uv_row_stride, uv_pixel_stride,
        sensor_orientation,
        target_size,
        scale, pad_w, pad_h, in_w, in_h, rot_w, rot_h
    );

    auto t_prep = std::chrono::high_resolution_clock::now();
    float prep_ms = std::chrono::duration<float, std::milli>(t_prep - t0).count();

    // Create NCNN Mat & Normalize
    ncnn::Mat in_mat = ncnn::Mat::from_pixels(g_ctx.rgb_letterbox_buf, ncnn::Mat::PIXEL_RGB, in_w, in_h);
    const float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    in_mat.substract_mean_normalize(0, norm_vals);

    // Forward inference
    ncnn::Extractor ex = g_ctx.net.create_extractor();
    ex.input("in0", in_mat);

    auto t_inf_start = std::chrono::high_resolution_clock::now();
    ncnn::Mat out0, out1, out2;
    int ret = ex.extract("out0", out0);
    if (ret != 0) {
        LOGE("NCNN extract out0 failed (%d)", ret);
        return -4;
    }
    auto t_inf_end = std::chrono::high_resolution_clock::now();
    float inf_ms = std::chrono::duration<float, std::milli>(t_inf_end - t_inf_start).count();

    auto t_post_start = std::chrono::high_resolution_clock::now();
    uint32_t current_fid = ++g_ctx.frame_counter;

    switch (g_ctx.active_task) {
        case YOLO_TASK_DETECTION: {
            YoloFrameResult* det_res = (YoloFrameResult*)out_result_buffer;
            det_res->frame_id = current_fid;
            det_res->inference_time_ms = inf_ms;
            det_res->active_backend = g_ctx.active_backend;
            det_res->status_code = 0;

            // Default prob_threshold = 0.25f matching nihui
            std::vector<CandidateObject> detections;
            decode_yolo11_detection(out0, in_w, in_h, pad_w, pad_h, scale, rot_w, rot_h, 0.25f, detections);

            int count = std::min((int)detections.size(), YOLO_MAX_BOXES);
            det_res->num_detections = count;

            // Immediate single-frame output with zero hits >= 2 delay
            for (int i = 0; i < count; ++i) {
                const auto& d = detections[i];
                auto& b = det_res->boxes[i];
                b.x1 = d.x0;
                b.y1 = d.y0;
                b.x2 = d.x1;
                b.y2 = d.y1;
                b.confidence = d.prob;
                b.class_id = d.label;
                b.track_id = i + 1;
                b.track_state = 1; // CONFIRMED

                float cx = (d.x0 + d.x1) * 0.5f;
                b.spatial_zone = (cx < 0.33f) ? 0 : ((cx > 0.66f) ? 2 : 1);
                float area = (d.x1 - d.x0) * (d.y1 - d.y0);
                b.proximity_tier = (area > 0.20f) ? 2 : ((area > 0.06f) ? 1 : 0);
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            det_res->tracker_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }

        case YOLO_TASK_SEGMENTATION: {
            YoloSegmentationResult* seg_res = (YoloSegmentationResult*)out_result_buffer;
            ex.extract("out1", out1); // mask coefficients [32, N]
            ex.extract("out2", out2); // prototype masks [w/4, h/4, 32]

            std::vector<CandidateObject> detections;
            decode_yolo11_detection(out0, in_w, in_h, pad_w, pad_h, scale, rot_w, rot_h, 0.25f, detections);

            int count = std::min((int)detections.size(), MAX_SEG_OBJECTS);
            seg_res->header.task_id = YOLO_TASK_SEGMENTATION;
            seg_res->header.frame_id = current_fid;
            seg_res->header.preprocessing_time_ms = prep_ms;
            seg_res->header.inference_time_ms = inf_ms;
            seg_res->header.active_backend = g_ctx.active_backend;
            seg_res->header.status_code = 0;
            seg_res->num_objects = count;

            for (int i = 0; i < count; ++i) {
                const auto& d = detections[i];
                auto& obj = seg_res->objects[i];
                obj.x1 = d.x0;
                obj.y1 = d.y0;
                obj.x2 = d.x1;
                obj.y2 = d.y1;
                obj.confidence = d.prob;
                obj.class_id = d.label;
                obj.mask_w = 32;
                obj.mask_h = 32;
                obj.num_contour_points = 16;

                // Approximate boundary contour from box for 60 FPS drawing
                float cx = (d.x0 + d.x1) * 0.5f;
                float cy = (d.y0 + d.y1) * 0.5f;
                float rx = (d.x1 - d.x0) * 0.5f;
                float ry = (d.y1 - d.y0) * 0.5f;
                for (int p = 0; p < 16; ++p) {
                    float theta = (float)(2.0 * M_PI * p / 16.0);
                    obj.contour_points[p * 2 + 0] = std::max(0.0f, std::min(1.0f, cx + rx * cosf(theta)));
                    obj.contour_points[p * 2 + 1] = std::max(0.0f, std::min(1.0f, cy + ry * sinf(theta)));
                }
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            seg_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }

        case YOLO_TASK_POSE: {
            YoloPoseResult* pose_res = (YoloPoseResult*)out_result_buffer;
            ex.extract("out1", out1); // 17 keypoints [51, N]

            std::vector<CandidateObject> detections;
            decode_yolo11_detection(out0, in_w, in_h, pad_w, pad_h, scale, rot_w, rot_h, 0.25f, detections);

            int count = std::min((int)detections.size(), MAX_POSE_OBJECTS);
            pose_res->header.task_id = YOLO_TASK_POSE;
            pose_res->header.frame_id = current_fid;
            pose_res->header.preprocessing_time_ms = prep_ms;
            pose_res->header.inference_time_ms = inf_ms;
            pose_res->header.active_backend = g_ctx.active_backend;
            pose_res->header.status_code = 0;
            pose_res->num_objects = count;

            for (int i = 0; i < count; ++i) {
                const auto& d = detections[i];
                auto& p_obj = pose_res->objects[i];
                p_obj.x1 = d.x0;
                p_obj.y1 = d.y0;
                p_obj.x2 = d.x1;
                p_obj.y2 = d.y1;
                p_obj.confidence = d.prob;
                p_obj.class_id = d.label;

                if (d.anchor_idx < out1.h && out1.w >= 51) {
                    const float* kp_ptr = out1.row(d.anchor_idx);
                    for (int k = 0; k < POSE_KEYPOINTS_COUNT; ++k) {
                        float kpx = (kp_ptr[k * 3 + 0] - pad_w) / (scale * rot_w);
                        float kpy = (kp_ptr[k * 3 + 1] - pad_h) / (scale * rot_h);
                        p_obj.keypoints[k].x = std::max(0.0f, std::min(1.0f, kpx));
                        p_obj.keypoints[k].y = std::max(0.0f, std::min(1.0f, kpy));
                        p_obj.keypoints[k].confidence = fast_sigmoid(kp_ptr[k * 3 + 2]);
                    }
                }
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            pose_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }

        case YOLO_TASK_CLASSIFICATION: {
            YoloClassificationResult* cls_res = (YoloClassificationResult*)out_result_buffer;
            cls_res->header.task_id = YOLO_TASK_CLASSIFICATION;
            cls_res->header.frame_id = current_fid;
            cls_res->header.preprocessing_time_ms = prep_ms;
            cls_res->header.inference_time_ms = inf_ms;
            cls_res->header.active_backend = g_ctx.active_backend;
            cls_res->header.status_code = 0;

            const float* probs = (const float*)out0.data;
            int num_cls = out0.w * out0.h * out0.c;
            std::vector<std::pair<float, int>> topk;
            for (int c = 0; c < num_cls; ++c) {
                topk.push_back({probs[c], c});
            }
            std::partial_sort(topk.begin(), topk.begin() + std::min(5, (int)topk.size()), topk.end(),
                              std::greater<std::pair<float, int>>());

            int k = std::min(MAX_TOPK, (int)topk.size());
            cls_res->num_items = k;
            for (int i = 0; i < k; ++i) {
                cls_res->items[i].confidence = topk[i].first;
                cls_res->items[i].class_id = topk[i].second;
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            cls_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }

        default:
            break;
    }

    return 0;
}

int yolo_multitask_forward_rgba(
    const uint8_t* rgba,
    int width,
    int height,
    int sensor_orientation,
    void* out_result_buffer
) {
    if (!g_ctx.initialized || !out_result_buffer || !rgba) return -1;
    if (width <= 0 || height <= 0) return -2;

    thread_local bool s_thread_init = false;
    if (!s_thread_init) {
        ncnn::set_cpu_powersave(2);
        ncnn::set_omp_num_threads(4);
        s_thread_init = true;
    }

    std::lock_guard<std::mutex> lock(g_engine_mutex);

    auto t0 = std::chrono::high_resolution_clock::now();

    float scale = 1.0f;
    int pad_w = 0, pad_h = 0, in_w = 0, in_h = 0, rot_w = width, rot_h = height;
    int target_size = g_ctx.target_size;

    prepare_letterbox_rgba_stride32(
        rgba, width, height,
        sensor_orientation,
        target_size,
        scale, pad_w, pad_h, in_w, in_h, rot_w, rot_h
    );

    auto t_prep = std::chrono::high_resolution_clock::now();
    float prep_ms = std::chrono::duration<float, std::milli>(t_prep - t0).count();

    ncnn::Mat in_mat = ncnn::Mat::from_pixels(g_ctx.rgb_letterbox_buf, ncnn::Mat::PIXEL_RGB, in_w, in_h);
    const float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    in_mat.substract_mean_normalize(0, norm_vals);

    ncnn::Extractor ex = g_ctx.net.create_extractor();
    ex.input("in0", in_mat);

    auto t_inf_start = std::chrono::high_resolution_clock::now();
    ncnn::Mat out0;
    int ret = ex.extract("out0", out0);
    if (ret != 0) {
        LOGE("NCNN extract out0 failed (%d)", ret);
        return -4;
    }
    auto t_inf_end = std::chrono::high_resolution_clock::now();
    float inf_ms = std::chrono::duration<float, std::milli>(t_inf_end - t_inf_start).count();

    auto t_post_start = std::chrono::high_resolution_clock::now();
    uint32_t current_fid = ++g_ctx.frame_counter;

    YoloFrameResult* det_res = (YoloFrameResult*)out_result_buffer;
    det_res->frame_id = current_fid;
    det_res->inference_time_ms = inf_ms;
    det_res->active_backend = g_ctx.active_backend;
    det_res->status_code = 0;

    std::vector<CandidateObject> detections;
    decode_yolo11_detection(out0, in_w, in_h, pad_w, pad_h, scale, rot_w, rot_h, 0.25f, detections);

    int count = std::min((int)detections.size(), YOLO_MAX_BOXES);
    det_res->num_detections = count;

    for (int i = 0; i < count; ++i) {
        const auto& d = detections[i];
        auto& b = det_res->boxes[i];
        b.x1 = d.x0;
        b.y1 = d.y0;
        b.x2 = d.x1;
        b.y2 = d.y1;
        b.confidence = d.prob;
        b.class_id = d.label;
        b.track_id = i + 1;
        b.track_state = 1;

        float cx = (d.x0 + d.x1) * 0.5f;
        b.spatial_zone = (cx < 0.33f) ? 0 : ((cx > 0.66f) ? 2 : 1);
        float area = (d.x1 - d.x0) * (d.y1 - d.y0);
        b.proximity_tier = (area > 0.20f) ? 2 : ((area > 0.06f) ? 1 : 0);
    }

    auto t_post_end = std::chrono::high_resolution_clock::now();
    det_res->tracker_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();

    return 0;
}

void yolo_multitask_destroy(void) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    if (!g_ctx.initialized) return;

    g_ctx.net.clear();

#if NCNN_VULKAN
    if (g_ctx.gpu_instance_created) {
        ncnn::destroy_gpu_instance();
        g_ctx.gpu_instance_created = false;
        g_ctx.current_gpu_driver = -1;
    }
#endif

    g_ctx.initialized = false;
    LOGI("yolo_multitask_destroy: SUCCESS");
}

} // extern "C"
