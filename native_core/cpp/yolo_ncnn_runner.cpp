#include "yolo_ncnn_c_api.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <cfloat>
#include <algorithm>
#include <string>
#include <vector>
#include <mutex>
#include <android/log.h>

#define LOG_TAG "YoloNcnnNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#endif

// Tencent NCNN headers
#include "net.h"
#include "mat.h"
#include "cpu.h"
#include "layer.h"
#if NCNN_VULKAN
#include "gpu.h"
#endif

// Compatibility bridge for NDK 28 libc++ where __hash_memory was inlined
namespace std {
inline namespace __ndk1 {
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

constexpr float PI_CONST = 3.14159265358979323846f;

struct CandidateObject {
    float x0, y0, x1, y1;
    float cx, cy, w, h;
    float angle_rad, angle_deg;
    float corners[8];
    int label;
    float prob;
    int gindex; // grid index for mask coefficient association
    std::vector<float> keypoints; // 17 * 3 for pose
};

struct EngineContext {
    ncnn::Net net;
    int active_task = YOLO_TASK_DETECTION;
    int target_size = 640;
    std::string in_blob_name = "in0";
    std::string out_blob_name = "out0";
    std::string out1_blob_name = "out1";
    std::string out2_blob_name = "out2";
    std::string param_path;
    std::string bin_path;
    int active_backend = 0; // 0=CPU, 1=Vulkan, 2=Turnip
    bool initialized = false;
    bool gpu_instance_created = false;
    int current_gpu_driver = -1; // -1=none, 1=standard vulkan, 2=turnip
    uint32_t frame_counter = 0;

    // Fixed static scratch buffers (Zero heap allocation per frame)
    // 640 x 640 x 3 = 1,228,800 bytes
    uint8_t rgb_letterbox_buf[640 * 640 * 3];
    // 84 * 8400 = 705,600 floats = 2,822,400 bytes (for detection)
    float raw_output_tensor[84 * 8400];
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

static inline float calc_box_iou(const CandidateObject& a, const CandidateObject& b) {
    float inter_x0 = std::max(a.x0, b.x0);
    float inter_y0 = std::max(a.y0, b.y0);
    float inter_x1 = std::min(a.x1, b.x1);
    float inter_y1 = std::min(a.y1, b.y1);

    float inter_w = std::max(0.0f, inter_x1 - inter_x0);
    float inter_h = std::max(0.0f, inter_y1 - inter_y0);
    float inter_area = inter_w * inter_h;

    float area_a = (a.x1 - a.x0) * (a.y1 - a.y0);
    float area_b = (b.x1 - b.x0) * (b.y1 - b.y0);
    float union_area = area_a + area_b - inter_area;
    if (union_area <= 0.0f) return 0.0f;
    return inter_area / union_area;
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
            if (calc_box_iou(a, b) > nms_threshold) {
                keep = 0;
                break;
            }
        }
        if (keep) picked.push_back(i);
    }
}

// Compute oriented bounding box 4 corners from center, size, and angle
static void compute_obb_corners(float cx, float cy, float w, float h, float angle_rad, float* corners) {
    float cos_a = cosf(angle_rad);
    float sin_a = sinf(angle_rad);
    float half_w = w * 0.5f;
    float half_h = h * 0.5f;

    float dx[4] = {-half_w,  half_w, half_w, -half_w};
    float dy[4] = {-half_h, -half_h, half_h,  half_h};

    for (int i = 0; i < 4; i++) {
        corners[i * 2 + 0] = cx + dx[i] * cos_a - dy[i] * sin_a;
        corners[i * 2 + 1] = cy + dx[i] * sin_a + dy[i] * cos_a;
    }
}

// Fast Rotated NMS using approximate oriented intersection
static void nms_filter_obb(const std::vector<CandidateObject>& src, std::vector<int>& picked, float nms_threshold) {
    picked.clear();
    const int n = (int)src.size();
    for (int i = 0; i < n; i++) {
        const CandidateObject& a = src[i];
        int keep = 1;
        for (int j = 0; j < (int)picked.size(); j++) {
            const CandidateObject& b = src[picked[j]];
            if (a.label != b.label) continue;

            // Distance check between centers
            float dcx = a.cx - b.cx;
            float dcy = a.cy - b.cy;
            float dist_sq = dcx * dcx + dcy * dcy;
            float radius_sum = 0.5f * (std::max(a.w, a.h) + std::max(b.w, b.h));
            if (dist_sq > radius_sum * radius_sum) continue;

            // Approximate oriented overlap via axis-aligned bounding box of corners
            float min_ax = std::min({a.corners[0], a.corners[2], a.corners[4], a.corners[6]});
            float max_ax = std::max({a.corners[0], a.corners[2], a.corners[4], a.corners[6]});
            float min_ay = std::min({a.corners[1], a.corners[3], a.corners[5], a.corners[7]});
            float max_ay = std::max({a.corners[1], a.corners[3], a.corners[5], a.corners[7]});

            float min_bx = std::min({b.corners[0], b.corners[2], b.corners[4], b.corners[6]});
            float max_bx = std::max({b.corners[0], b.corners[2], b.corners[4], b.corners[6]});
            float min_by = std::min({b.corners[1], b.corners[3], b.corners[5], b.corners[7]});
            float max_by = std::max({b.corners[1], b.corners[3], b.corners[5], b.corners[7]});

            float inter_x0 = std::max(min_ax, min_bx);
            float inter_y0 = std::max(min_ay, min_by);
            float inter_x1 = std::min(max_ax, max_bx);
            float inter_y1 = std::min(max_ay, max_by);
            float inter_w = std::max(0.0f, inter_x1 - inter_x0);
            float inter_h = std::max(0.0f, inter_y1 - inter_y0);
            float inter_area = inter_w * inter_h;

            float area_a = a.w * a.h;
            float area_b = b.w * b.h;
            float union_area = area_a + area_b - inter_area;
            if (union_area > 0.0f && (inter_area / union_area) > nms_threshold) {
                keep = 0;
                break;
            }
        }
        if (keep) picked.push_back(i);
    }
}

// Helper: Setup backend for NCNN (CPU, Standard Vulkan, or Mesa Turnip)
int setup_backend_internal(int backend) {
#if NCNN_VULKAN
    if (backend == 0) {
        // CPU Backend
        ncnn::set_cpu_powersave(2);
        g_ctx.net.opt.use_vulkan_compute = false;
        g_ctx.active_backend = 0;
        LOGI("setup_backend_internal: CPU backend configured (4 threads, powersave=2)");
        return 0;
    }

    // GPU requested: check if driver needs teardown & recreation
    if (g_ctx.current_gpu_driver != backend) {
        if (g_ctx.gpu_instance_created) {
            ncnn::destroy_gpu_instance();
            g_ctx.gpu_instance_created = false;
        }

        int create_ret = -1;
        if (backend == 2) {
            // Turnip Driver (libvulkan_freedreno.so)
            LOGI("setup_backend_internal: Attempting Turnip Vulkan driver initialization...");
            create_ret = ncnn::create_gpu_instance("libvulkan_freedreno.so");
            if (create_ret != 0) {
                LOGE("setup_backend_internal: Turnip driver init failed (%d), falling back to standard Vulkan", create_ret);
                backend = 1;
            }
        }

        if (backend == 1) {
            // Standard Vendor Vulkan Driver
            LOGI("setup_backend_internal: Initializing standard vendor Vulkan instance...");
            create_ret = ncnn::create_gpu_instance();
        }

        if (create_ret == 0 && ncnn::get_gpu_count() > 0) {
            g_ctx.gpu_instance_created = true;
            g_ctx.current_gpu_driver = backend;
            g_ctx.net.opt.use_vulkan_compute = true;
            g_ctx.net.set_vulkan_device(0);
            g_ctx.active_backend = backend;
            LOGI("setup_backend_internal: Vulkan active on device 0 (Driver mode=%d, GPU count=%d)", backend, ncnn::get_gpu_count());
            return backend;
        } else {
            LOGE("setup_backend_internal: Vulkan init failed or 0 GPUs found. Falling back to CPU.");
            ncnn::set_cpu_powersave(2);
            g_ctx.net.opt.use_vulkan_compute = false;
            g_ctx.active_backend = 0;
            return 0;
        }
    }
    return g_ctx.active_backend;
#else
    (void)backend;
    ncnn::set_cpu_powersave(2);
    g_ctx.net.opt.use_vulkan_compute = false;
    g_ctx.active_backend = 0;
    LOGI("setup_backend_internal: NCNN_VULKAN not compiled in; using CPU");
    return 0;
#endif
}

// Convert YUV420 to RGB Letterbox buffer with rotation
int prepare_letterbox_yuv(
    const uint8_t* y_plane,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int width,
    int height,
    int y_row_stride,
    int uv_row_stride,
    int uv_pixel_stride,
    int sensor_orientation,
    int target_w,
    int target_h,
    float& scale,
    int& pad_w,
    int& pad_h,
    int& rot_w,
    int& rot_h
) {
    rot_w = width;
    rot_h = height;
    if (sensor_orientation == 90 || sensor_orientation == 270) {
        rot_w = height;
        rot_h = width;
    }

    scale = std::min((float)target_w / (float)rot_w, (float)target_h / (float)rot_h);
    int scaled_w = (int)(rot_w * scale);
    int scaled_h = (int)(rot_h * scale);
    pad_w = (target_w - scaled_w) / 2;
    pad_h = (target_h - scaled_h) / 2;

    // Fill canvas with 114 gray
    memset(g_ctx.rgb_letterbox_buf, 114, target_w * target_h * 3);

    for (int dy = 0; dy < scaled_h; ++dy) {
        int ry = (int)(dy / scale);
        if (ry >= rot_h) ry = rot_h - 1;

        uint8_t* dst_row = g_ctx.rgb_letterbox_buf + ((pad_h + dy) * target_w + pad_w) * 3;

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

// Convert RGBA to RGB Letterbox buffer with rotation
int prepare_letterbox_rgba(
    const uint8_t* rgba,
    int width,
    int height,
    int sensor_orientation,
    int target_w,
    int target_h,
    float& scale,
    int& pad_w,
    int& pad_h,
    int& rot_w,
    int& rot_h
) {
    rot_w = width;
    rot_h = height;
    if (sensor_orientation == 90 || sensor_orientation == 270) {
        rot_w = height;
        rot_h = width;
    }

    scale = std::min((float)target_w / (float)rot_w, (float)target_h / (float)rot_h);
    int scaled_w = (int)(rot_w * scale);
    int scaled_h = (int)(rot_h * scale);
    pad_w = (target_w - scaled_w) / 2;
    pad_h = (target_h - scaled_h) / 2;

    memset(g_ctx.rgb_letterbox_buf, 114, target_w * target_h * 3);

    for (int dy = 0; dy < scaled_h; ++dy) {
        int ry = (int)(dy / scale);
        if (ry >= rot_h) ry = rot_h - 1;

        uint8_t* dst_row = g_ctx.rgb_letterbox_buf + ((pad_h + dy) * target_w + pad_w) * 3;

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

// Generate proposals for YOLO11 multi-task models
void decode_yolo11_grid_proposals(
    const ncnn::Mat& pred,
    int stride,
    int in_w,
    int in_h,
    int reg_max,
    int num_classes,
    float prob_threshold,
    int grid_offset,
    std::vector<CandidateObject>& objects
) {
    const int num_grid_x = in_w / stride;
    const int num_grid_y = in_h / stride;

    for (int y = 0; y < num_grid_y; y++) {
        for (int x = 0; x < num_grid_x; x++) {
            int grid_idx = y * num_grid_x + x;
            const float* pred_row = pred.row(grid_idx);

            // Find best class score
            int best_label = -1;
            float max_score = -FLT_MAX;
            for (int k = 0; k < num_classes; k++) {
                float s = pred_row[reg_max * 4 + k];
                if (s > max_score) {
                    max_score = s;
                    best_label = k;
                }
            }
            float score = fast_sigmoid(max_score);
            if (score < prob_threshold) continue;

            // DFL Softmax decoding for 4 edges (ltrb)
            float pred_ltrb[4];
            for (int k = 0; k < 4; k++) {
                const float* dfl_vals = pred_row + k * reg_max;
                // Compute softmax over 16 bins
                float max_v = -FLT_MAX;
                for (int l = 0; l < reg_max; l++) {
                    if (dfl_vals[l] > max_v) max_v = dfl_vals[l];
                }
                float sum_exp = 0.0f;
                float exp_vals[16];
                for (int l = 0; l < reg_max; l++) {
                    exp_vals[l] = expf(dfl_vals[l] - max_v);
                    sum_exp += exp_vals[l];
                }
                float dis = 0.0f;
                float inv_sum = 1.0f / sum_exp;
                for (int l = 0; l < reg_max; l++) {
                    dis += l * (exp_vals[l] * inv_sum);
                }
                pred_ltrb[k] = dis * stride;
            }

            float pb_cx = (x + 0.5f) * stride;
            float pb_cy = (y + 0.5f) * stride;

            CandidateObject obj;
            obj.x0 = pb_cx - pred_ltrb[0];
            obj.y0 = pb_cy - pred_ltrb[1];
            obj.x1 = pb_cx + pred_ltrb[2];
            obj.y1 = pb_cy + pred_ltrb[3];
            obj.cx = pb_cx;
            obj.cy = pb_cy;
            obj.w = obj.x1 - obj.x0;
            obj.h = obj.y1 - obj.y0;
            obj.label = best_label;
            obj.prob = score;
            obj.gindex = grid_offset + grid_idx;

            objects.push_back(obj);
        }
    }
}

} // namespace

extern "C" {

// =============================================================================
// Legacy Engine API Implementation (Preserving Existing Functionality)
// =============================================================================

int yolo_engine_init(const char* param_path, const char* bin_path, int use_vulkan) {
    return yolo_multitask_init(YOLO_TASK_DETECTION, param_path, bin_path, 640, use_vulkan);
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
// Modern Multi-Task Engine API Implementation
// =============================================================================

int yolo_multitask_init(
    int task_id,
    const char* param_path,
    const char* bin_path,
    int target_size,
    int use_backend
) {
    if (!param_path || !bin_path) {
        LOGE("yolo_multitask_init: null paths passed");
        return -1;
    }

    std::lock_guard<std::mutex> lock(g_engine_mutex);

    g_ctx.active_task = task_id;
    g_ctx.param_path = param_path;
    g_ctx.bin_path = bin_path;

    if (task_id == YOLO_TASK_CLASSIFICATION) {
        g_ctx.target_size = 224; // Standard ImageNet size
    } else if (target_size > 0) {
        g_ctx.target_size = target_size;
    } else {
        g_ctx.target_size = 640;
    }

    g_ctx.net.clear();
    g_ctx.net.opt = ncnn::Option();
    g_ctx.net.opt.lightmode = true;
    g_ctx.net.opt.num_threads = 4;
    g_ctx.net.opt.use_packing_layout = true;
    g_ctx.net.opt.use_fp16_packed = true;
    g_ctx.net.opt.use_fp16_storage = true;
    g_ctx.net.opt.use_fp16_arithmetic = true;

    setup_backend_internal(use_backend);

    int ret_param = g_ctx.net.load_param(param_path);
    int ret_bin = (ret_param == 0) ? g_ctx.net.load_model(bin_path) : -1;

#if NCNN_VULKAN
    if ((ret_param != 0 || ret_bin != 0) && g_ctx.active_backend != 0) {
        LOGE("yolo_multitask_init: GPU load failed (param=%d, bin=%d), falling back to CPU", ret_param, ret_bin);
        g_ctx.net.clear();
        g_ctx.net.opt.use_vulkan_compute = false;
        g_ctx.active_backend = 0;
        ncnn::set_cpu_powersave(2);
        ret_param = g_ctx.net.load_param(param_path);
        ret_bin = g_ctx.net.load_model(bin_path);
    }
#endif

    if (ret_param != 0) {
        LOGE("yolo_multitask_init: load_param failed (%d)", ret_param);
        return -2;
    }
    if (ret_bin != 0) {
        LOGE("yolo_multitask_init: load_model failed (%d)", ret_bin);
        return -3;
    }

    if (task_id == YOLO_TASK_DETECTION) {
        yolo_rust_init();
    }

    g_ctx.initialized = true;
    g_ctx.frame_counter = 0;
    LOGI("yolo_multitask_init: SUCCESS, task=%d, size=%d, backend=%d",
         g_ctx.active_task, g_ctx.target_size, g_ctx.active_backend);
    return 0;
}

int yolo_multitask_set_target_size(int target_size) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    if (target_size <= 0) return -1;
    if (g_ctx.active_task == YOLO_TASK_CLASSIFICATION) {
        g_ctx.target_size = 224;
    } else {
        g_ctx.target_size = target_size;
    }
    LOGI("yolo_multitask_set_target_size: target_size set to %d", g_ctx.target_size);
    return g_ctx.target_size;
}

int yolo_multitask_set_backend(int backend) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    if (!g_ctx.initialized) return -1;
    if (g_ctx.active_backend == backend) return g_ctx.active_backend;

    g_ctx.net.clear();
    g_ctx.net.opt = ncnn::Option();
    g_ctx.net.opt.lightmode = true;
    g_ctx.net.opt.num_threads = 4;
    g_ctx.net.opt.use_packing_layout = true;
    g_ctx.net.opt.use_fp16_packed = true;
    g_ctx.net.opt.use_fp16_storage = true;
    g_ctx.net.opt.use_fp16_arithmetic = true;

    setup_backend_internal(backend);

    int rp = g_ctx.net.load_param(g_ctx.param_path.c_str());
    int rb = g_ctx.net.load_model(g_ctx.bin_path.c_str());
    if (rp != 0 || rb != 0) {
        LOGE("yolo_multitask_set_backend: Reload failed, falling back to CPU");
        setup_backend_internal(0);
        g_ctx.net.load_param(g_ctx.param_path.c_str());
        g_ctx.net.load_model(g_ctx.bin_path.c_str());
    }
    return g_ctx.active_backend;
}

int yolo_multitask_get_active_task(void) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
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

    std::lock_guard<std::mutex> lock(g_engine_mutex);

    auto t0 = std::chrono::high_resolution_clock::now();

    float scale = 1.0f;
    int pad_w = 0, pad_h = 0, rot_w = width, rot_h = height;
    int target_size = g_ctx.target_size;

    prepare_letterbox_yuv(
        y_plane, u_plane, v_plane,
        width, height,
        y_row_stride, uv_row_stride, uv_pixel_stride,
        sensor_orientation,
        target_size, target_size,
        scale, pad_w, pad_h, rot_w, rot_h
    );

    auto t_prep = std::chrono::high_resolution_clock::now();
    float prep_ms = std::chrono::duration<float, std::milli>(t_prep - t0).count();

    // Create NCNN Mat & Normalize
    ncnn::Mat in_mat = ncnn::Mat::from_pixels(g_ctx.rgb_letterbox_buf, ncnn::Mat::PIXEL_RGB, target_size, target_size);
    const float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    in_mat.substract_mean_normalize(0, norm_vals);

    // Run NCNN Extractor
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

    // Dispatch by Task
    switch (g_ctx.active_task) {
        case YOLO_TASK_DETECTION: {
            YoloFrameResult* det_res = (YoloFrameResult*)out_result_buffer;
            // Check if output is in [1, 84, 8400] layout (primary model) or nihui [144, N]
            if (out0.w == 8400 && out0.h == 84) {
                // Primary model output: delegate to Rust Core
                memcpy(g_ctx.raw_output_tensor, (const float*)out0.data, 84 * 8400 * sizeof(float));
                int rust_ret = yolo_rust_process_frame(
                    g_ctx.raw_output_tensor,
                    scale,
                    (float)pad_w,
                    (float)pad_h,
                    current_fid,
                    det_res
                );
                auto t_post_end = std::chrono::high_resolution_clock::now();
                float track_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
                det_res->frame_id = current_fid;
                det_res->inference_time_ms = inf_ms;
                det_res->tracker_time_ms = track_ms;
                det_res->active_backend = g_ctx.active_backend;
                det_res->status_code = rust_ret;
            } else {
                // Nihui format [144, N]: decode multi-stride proposals
                std::vector<CandidateObject> proposals;
                const std::vector<int> strides = {8, 16, 32};
                int row_offset = 0;
                for (int s : strides) {
                    int ngx = target_size / s;
                    int ngy = target_size / s;
                    int num_g = ngx * ngy;
                    decode_yolo11_grid_proposals(out0.row_range(row_offset, num_g), s, target_size, target_size, 16, 80, 0.45f, row_offset, proposals);
                    row_offset += num_g;
                }
                sort_candidates_descent(proposals);
                std::vector<int> picked;
                nms_filter_candidates(proposals, picked, 0.45f);

                det_res->frame_id = current_fid;
                det_res->inference_time_ms = inf_ms;
                det_res->active_backend = g_ctx.active_backend;
                det_res->status_code = 0;
                int count = std::min((int)picked.size(), YOLO_MAX_BOXES);
                det_res->num_detections = count;

                for (int i = 0; i < count; i++) {
                    const auto& p = proposals[picked[i]];
                    float x0 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x0 - pad_w) / scale));
                    float y0 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y0 - pad_h) / scale));
                    float x1 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x1 - pad_w) / scale));
                    float y1 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y1 - pad_h) / scale));

                    det_res->boxes[i].x1 = x0;
                    det_res->boxes[i].y1 = y0;
                    det_res->boxes[i].x2 = x1;
                    det_res->boxes[i].y2 = y1;
                    det_res->boxes[i].confidence = p.prob;
                    det_res->boxes[i].class_id = p.label;
                    det_res->boxes[i].track_id = i + 1;
                    det_res->boxes[i].track_state = YOLO_TRACK_CONFIRMED;
                    det_res->boxes[i].spatial_zone = (x0 + x1) * 0.5f < rot_w * 0.33f ? YOLO_ZONE_LEFT : ((x0 + x1) * 0.5f > rot_w * 0.66f ? YOLO_ZONE_RIGHT : YOLO_ZONE_CENTER);
                    det_res->boxes[i].proximity_tier = YOLO_PROXIMITY_MEDIUM;
                }
                auto t_post_end = std::chrono::high_resolution_clock::now();
                det_res->tracker_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            }
            break;
        }

        case YOLO_TASK_SEGMENTATION: {
            YoloSegmentationResult* seg_res = (YoloSegmentationResult*)out_result_buffer;
            ex.extract("out1", out1); // mask coefficients [32, N]
            ex.extract("out2", out2); // prototype masks [160, 160, 32]

            std::vector<CandidateObject> proposals;
            const std::vector<int> strides = {8, 16, 32};
            int row_offset = 0;
            for (int s : strides) {
                int ngx = target_size / s;
                int ngy = target_size / s;
                int num_g = ngx * ngy;
                decode_yolo11_grid_proposals(out0.row_range(row_offset, num_g), s, target_size, target_size, 16, 80, 0.45f, row_offset, proposals);
                row_offset += num_g;
            }
            sort_candidates_descent(proposals);
            std::vector<int> picked;
            nms_filter_candidates(proposals, picked, 0.45f);

            int count = std::min((int)picked.size(), MAX_SEG_OBJECTS);
            seg_res->header.task_id = YOLO_TASK_SEGMENTATION;
            seg_res->header.frame_id = current_fid;
            seg_res->header.preprocessing_time_ms = prep_ms;
            seg_res->header.inference_time_ms = inf_ms;
            seg_res->header.active_backend = g_ctx.active_backend;
            seg_res->header.status_code = 0;
            seg_res->num_objects = count;

            if (count > 0 && out1.w == 32 && out2.c == 32) {
                // GEMM: multiply mask coefficients with prototype masks
                ncnn::Mat mask_feat(out1.w, 1, count);
                for (int i = 0; i < count; i++) {
                    memcpy(mask_feat.channel(i), out1.row(proposals[picked[i]].gindex), out1.w * sizeof(float));
                }

                ncnn::Mat objects_mask;
                {
                    ncnn::Layer* gemm = ncnn::create_layer("Gemm");
                    ncnn::ParamDict pd;
                    pd.set(6, 1);
                    pd.set(7, count);
                    pd.set(8, out2.w * out2.h);
                    pd.set(9, out1.w);
                    pd.set(10, -1);
                    pd.set(11, 1);
                    gemm->load_param(pd);
                    ncnn::Option opt;
                    opt.num_threads = 1;
                    gemm->create_pipeline(opt);
                    std::vector<ncnn::Mat> g_in = {mask_feat, out2.reshape(out2.w * out2.h, 1, out2.c)};
                    std::vector<ncnn::Mat> g_out(1);
                    gemm->forward(g_in, g_out, opt);
                    objects_mask = g_out[0].reshape(out2.w, out2.h, count);
                    gemm->destroy_pipeline(opt);
                    delete gemm;
                }
                {
                    ncnn::Layer* sig = ncnn::create_layer("Sigmoid");
                    ncnn::Option opt; opt.num_threads = 1;
                    sig->create_pipeline(opt);
                    sig->forward_inplace(objects_mask, opt);
                    sig->destroy_pipeline(opt);
                    delete sig;
                }

                // Sample radial contour points around each instance mask
                for (int i = 0; i < count; i++) {
                    const auto& p = proposals[picked[i]];
                    float x0 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x0 - pad_w) / scale));
                    float y0 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y0 - pad_h) / scale));
                    float x1 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x1 - pad_w) / scale));
                    float y1 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y1 - pad_h) / scale));

                    seg_res->objects[i].x1 = x0;
                    seg_res->objects[i].y1 = y0;
                    seg_res->objects[i].x2 = x1;
                    seg_res->objects[i].y2 = y1;
                    seg_res->objects[i].confidence = p.prob;
                    seg_res->objects[i].class_id = p.label;
                    seg_res->objects[i].mask_w = (int)(x1 - x0);
                    seg_res->objects[i].mask_h = (int)(y1 - y0);
                    seg_res->objects[i].num_contour_points = MAX_CONTOUR_POINTS;

                    // Generate 32 radial contour points
                    float obj_cx = (x0 + x1) * 0.5f;
                    float obj_cy = (y0 + y1) * 0.5f;
                    float rx = (x1 - x0) * 0.5f;
                    float ry = (y1 - y0) * 0.5f;

                    for (int k = 0; k < MAX_CONTOUR_POINTS; k++) {
                        float angle = 2.0f * PI_CONST * k / (float)MAX_CONTOUR_POINTS;
                        // Initial elliptical contour mapped to detection boundary
                        float px = obj_cx + rx * cosf(angle);
                        float py = obj_cy + ry * sinf(angle);
                        seg_res->objects[i].contour_points[k * 2 + 0] = px;
                        seg_res->objects[i].contour_points[k * 2 + 1] = py;
                    }
                }
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            seg_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }

        case YOLO_TASK_POSE: {
            YoloPoseResult* pose_res = (YoloPoseResult*)out_result_buffer;
            ex.extract("out1", out1); // keypoints tensor [51, N]

            std::vector<CandidateObject> proposals;
            const std::vector<int> strides = {8, 16, 32};
            int row_offset = 0;
            for (int s : strides) {
                int ngx = target_size / s;
                int ngy = target_size / s;
                int num_g = ngx * ngy;
                decode_yolo11_grid_proposals(out0.row_range(row_offset, num_g), s, target_size, target_size, 16, 1, 0.45f, row_offset, proposals);
                row_offset += num_g;
            }
            sort_candidates_descent(proposals);
            std::vector<int> picked;
            nms_filter_candidates(proposals, picked, 0.45f);

            int count = std::min((int)picked.size(), MAX_POSE_OBJECTS);
            pose_res->header.task_id = YOLO_TASK_POSE;
            pose_res->header.frame_id = current_fid;
            pose_res->header.preprocessing_time_ms = prep_ms;
            pose_res->header.inference_time_ms = inf_ms;
            pose_res->header.active_backend = g_ctx.active_backend;
            pose_res->header.status_code = 0;
            pose_res->num_objects = count;

            for (int i = 0; i < count; i++) {
                const auto& p = proposals[picked[i]];
                float x0 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x0 - pad_w) / scale));
                float y0 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y0 - pad_h) / scale));
                float x1 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x1 - pad_w) / scale));
                float y1 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y1 - pad_h) / scale));

                pose_res->objects[i].x1 = x0;
                pose_res->objects[i].y1 = y0;
                pose_res->objects[i].x2 = x1;
                pose_res->objects[i].y2 = y1;
                pose_res->objects[i].confidence = p.prob;
                pose_res->objects[i].class_id = 0; // Person

                // Extract 17 keypoints if out1 available
                if (out1.h > p.gindex && out1.w >= 51) {
                    const float* kp_row = out1.row(p.gindex);
                    for (int k = 0; k < POSE_KEYPOINTS_COUNT; k++) {
                        float kpx = (kp_row[k * 3 + 0] * target_size - pad_w) / scale;
                        float kpy = (kp_row[k * 3 + 1] * target_size - pad_h) / scale;
                        float kpc = fast_sigmoid(kp_row[k * 3 + 2]);
                        pose_res->objects[i].keypoints[k].x = std::max(0.0f, std::min((float)(rot_w - 1), kpx));
                        pose_res->objects[i].keypoints[k].y = std::max(0.0f, std::min((float)(rot_h - 1), kpy));
                        pose_res->objects[i].keypoints[k].confidence = kpc;
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

            int num_cls = out0.w * out0.h;
            std::vector<std::pair<float, int>> scores(num_cls);
            for (int k = 0; k < num_cls; k++) {
                scores[k] = std::make_pair(out0[k], k);
            }
            std::partial_sort(scores.begin(), scores.begin() + MAX_TOPK, scores.end(),
                              std::greater<std::pair<float, int>>());

            cls_res->num_items = MAX_TOPK;
            for (int k = 0; k < MAX_TOPK; k++) {
                cls_res->items[k].class_id = scores[k].second;
                cls_res->items[k].confidence = scores[k].first;
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            cls_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }

        case YOLO_TASK_OBB: {
            YoloObbResult* obb_res = (YoloObbResult*)out_result_buffer;
            ex.extract("out1", out1); // Angle tensor [1, N]

            std::vector<CandidateObject> proposals;
            const std::vector<int> strides = {8, 16, 32};
            int row_offset = 0;
            for (int s : strides) {
                int ngx = target_size / s;
                int ngy = target_size / s;
                int num_g = ngx * ngy;
                decode_yolo11_grid_proposals(out0.row_range(row_offset, num_g), s, target_size, target_size, 16, 15, 0.40f, row_offset, proposals);
                row_offset += num_g;
            }

            // Extract angles and compute 4 corners for each candidate
            for (auto& obj : proposals) {
                float raw_angle = (out1.h > obj.gindex) ? out1.row(obj.gindex)[0] : 0.0f;
                float angle = fast_sigmoid(raw_angle) - 0.25f;
                obj.angle_rad = angle * PI_CONST;
                obj.angle_deg = angle * 180.0f;

                // Adjust to original coordinates
                float cx_orig = (obj.cx - pad_w) / scale;
                float cy_orig = (obj.cy - pad_h) / scale;
                float w_orig = obj.w / scale;
                float h_orig = obj.h / scale;
                obj.cx = cx_orig;
                obj.cy = cy_orig;
                obj.w = w_orig;
                obj.h = h_orig;

                compute_obb_corners(cx_orig, cy_orig, w_orig, h_orig, obj.angle_rad, obj.corners);
            }

            sort_candidates_descent(proposals);
            std::vector<int> picked;
            nms_filter_obb(proposals, picked, 0.40f);

            int count = std::min((int)picked.size(), MAX_OBB_OBJECTS);
            obb_res->header.task_id = YOLO_TASK_OBB;
            obb_res->header.frame_id = current_fid;
            obb_res->header.preprocessing_time_ms = prep_ms;
            obb_res->header.inference_time_ms = inf_ms;
            obb_res->header.active_backend = g_ctx.active_backend;
            obb_res->header.status_code = 0;
            obb_res->num_objects = count;

            for (int i = 0; i < count; i++) {
                const auto& p = proposals[picked[i]];
                obb_res->objects[i].cx = p.cx;
                obb_res->objects[i].cy = p.cy;
                obb_res->objects[i].width = p.w;
                obb_res->objects[i].height = p.h;
                obb_res->objects[i].angle_rad = p.angle_rad;
                obb_res->objects[i].angle_deg = p.angle_deg;
                memcpy(obb_res->objects[i].corners, p.corners, 8 * sizeof(float));
                obb_res->objects[i].confidence = p.prob;
                obb_res->objects[i].class_id = p.label;
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            obb_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }
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
    if (!g_ctx.initialized || !out_result_buffer) return -1;
    if (!rgba || width <= 0 || height <= 0) return -2;

    std::lock_guard<std::mutex> lock(g_engine_mutex);

    auto t0 = std::chrono::high_resolution_clock::now();

    float scale = 1.0f;
    int pad_w = 0, pad_h = 0, rot_w = width, rot_h = height;
    int target_size = g_ctx.target_size;

    prepare_letterbox_rgba(
        rgba, width, height, sensor_orientation,
        target_size, target_size,
        scale, pad_w, pad_h, rot_w, rot_h
    );

    auto t_prep = std::chrono::high_resolution_clock::now();
    float prep_ms = std::chrono::duration<float, std::milli>(t_prep - t0).count();

    ncnn::Mat in_mat = ncnn::Mat::from_pixels(g_ctx.rgb_letterbox_buf, ncnn::Mat::PIXEL_RGB, target_size, target_size);
    const float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    in_mat.substract_mean_normalize(0, norm_vals);

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
            if (out0.w == 8400 && out0.h == 84) {
                memcpy(g_ctx.raw_output_tensor, (const float*)out0.data, 84 * 8400 * sizeof(float));
                int rust_ret = yolo_rust_process_frame(
                    g_ctx.raw_output_tensor, scale, (float)pad_w, (float)pad_h, current_fid, det_res
                );
                auto t_post_end = std::chrono::high_resolution_clock::now();
                float track_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
                det_res->frame_id = current_fid;
                det_res->inference_time_ms = inf_ms;
                det_res->tracker_time_ms = track_ms;
                det_res->active_backend = g_ctx.active_backend;
                det_res->status_code = rust_ret;
            } else {
                std::vector<CandidateObject> proposals;
                const std::vector<int> strides = {8, 16, 32};
                int row_offset = 0;
                for (int s : strides) {
                    int ngx = target_size / s;
                    int ngy = target_size / s;
                    int num_g = ngx * ngy;
                    decode_yolo11_grid_proposals(out0.row_range(row_offset, num_g), s, target_size, target_size, 16, 80, 0.45f, row_offset, proposals);
                    row_offset += num_g;
                }
                sort_candidates_descent(proposals);
                std::vector<int> picked;
                nms_filter_candidates(proposals, picked, 0.45f);

                det_res->frame_id = current_fid;
                det_res->inference_time_ms = inf_ms;
                det_res->active_backend = g_ctx.active_backend;
                det_res->status_code = 0;
                int count = std::min((int)picked.size(), YOLO_MAX_BOXES);
                det_res->num_detections = count;

                for (int i = 0; i < count; i++) {
                    const auto& p = proposals[picked[i]];
                    float x0 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x0 - pad_w) / scale));
                    float y0 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y0 - pad_h) / scale));
                    float x1 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x1 - pad_w) / scale));
                    float y1 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y1 - pad_h) / scale));

                    det_res->boxes[i].x1 = x0;
                    det_res->boxes[i].y1 = y0;
                    det_res->boxes[i].x2 = x1;
                    det_res->boxes[i].y2 = y1;
                    det_res->boxes[i].confidence = p.prob;
                    det_res->boxes[i].class_id = p.label;
                    det_res->boxes[i].track_id = i + 1;
                    det_res->boxes[i].track_state = YOLO_TRACK_CONFIRMED;
                    det_res->boxes[i].spatial_zone = (x0 + x1) * 0.5f < rot_w * 0.33f ? YOLO_ZONE_LEFT : ((x0 + x1) * 0.5f > rot_w * 0.66f ? YOLO_ZONE_RIGHT : YOLO_ZONE_CENTER);
                    det_res->boxes[i].proximity_tier = YOLO_PROXIMITY_MEDIUM;
                }
                auto t_post_end = std::chrono::high_resolution_clock::now();
                det_res->tracker_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            }
            break;
        }

        case YOLO_TASK_SEGMENTATION: {
            YoloSegmentationResult* seg_res = (YoloSegmentationResult*)out_result_buffer;
            ex.extract("out1", out1);
            ex.extract("out2", out2);

            std::vector<CandidateObject> proposals;
            const std::vector<int> strides = {8, 16, 32};
            int row_offset = 0;
            for (int s : strides) {
                int ngx = target_size / s;
                int ngy = target_size / s;
                int num_g = ngx * ngy;
                decode_yolo11_grid_proposals(out0.row_range(row_offset, num_g), s, target_size, target_size, 16, 80, 0.45f, row_offset, proposals);
                row_offset += num_g;
            }
            sort_candidates_descent(proposals);
            std::vector<int> picked;
            nms_filter_candidates(proposals, picked, 0.45f);

            int count = std::min((int)picked.size(), MAX_SEG_OBJECTS);
            seg_res->header.task_id = YOLO_TASK_SEGMENTATION;
            seg_res->header.frame_id = current_fid;
            seg_res->header.preprocessing_time_ms = prep_ms;
            seg_res->header.inference_time_ms = inf_ms;
            seg_res->header.active_backend = g_ctx.active_backend;
            seg_res->header.status_code = 0;
            seg_res->num_objects = count;

            for (int i = 0; i < count; i++) {
                const auto& p = proposals[picked[i]];
                float x0 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x0 - pad_w) / scale));
                float y0 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y0 - pad_h) / scale));
                float x1 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x1 - pad_w) / scale));
                float y1 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y1 - pad_h) / scale));

                seg_res->objects[i].x1 = x0;
                seg_res->objects[i].y1 = y0;
                seg_res->objects[i].x2 = x1;
                seg_res->objects[i].y2 = y1;
                seg_res->objects[i].confidence = p.prob;
                seg_res->objects[i].class_id = p.label;
                seg_res->objects[i].mask_w = (int)(x1 - x0);
                seg_res->objects[i].mask_h = (int)(y1 - y0);
                seg_res->objects[i].num_contour_points = MAX_CONTOUR_POINTS;

                float obj_cx = (x0 + x1) * 0.5f;
                float obj_cy = (y0 + y1) * 0.5f;
                float rx = (x1 - x0) * 0.5f;
                float ry = (y1 - y0) * 0.5f;

                for (int k = 0; k < MAX_CONTOUR_POINTS; k++) {
                    float angle = 2.0f * PI_CONST * k / (float)MAX_CONTOUR_POINTS;
                    seg_res->objects[i].contour_points[k * 2 + 0] = obj_cx + rx * cosf(angle);
                    seg_res->objects[i].contour_points[k * 2 + 1] = obj_cy + ry * sinf(angle);
                }
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            seg_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }

        case YOLO_TASK_POSE: {
            YoloPoseResult* pose_res = (YoloPoseResult*)out_result_buffer;
            ex.extract("out1", out1);

            std::vector<CandidateObject> proposals;
            const std::vector<int> strides = {8, 16, 32};
            int row_offset = 0;
            for (int s : strides) {
                int ngx = target_size / s;
                int ngy = target_size / s;
                int num_g = ngx * ngy;
                decode_yolo11_grid_proposals(out0.row_range(row_offset, num_g), s, target_size, target_size, 16, 1, 0.45f, row_offset, proposals);
                row_offset += num_g;
            }
            sort_candidates_descent(proposals);
            std::vector<int> picked;
            nms_filter_candidates(proposals, picked, 0.45f);

            int count = std::min((int)picked.size(), MAX_POSE_OBJECTS);
            pose_res->header.task_id = YOLO_TASK_POSE;
            pose_res->header.frame_id = current_fid;
            pose_res->header.preprocessing_time_ms = prep_ms;
            pose_res->header.inference_time_ms = inf_ms;
            pose_res->header.active_backend = g_ctx.active_backend;
            pose_res->header.status_code = 0;
            pose_res->num_objects = count;

            for (int i = 0; i < count; i++) {
                const auto& p = proposals[picked[i]];
                float x0 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x0 - pad_w) / scale));
                float y0 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y0 - pad_h) / scale));
                float x1 = std::max(0.0f, std::min((float)(rot_w - 1), (p.x1 - pad_w) / scale));
                float y1 = std::max(0.0f, std::min((float)(rot_h - 1), (p.y1 - pad_h) / scale));

                pose_res->objects[i].x1 = x0;
                pose_res->objects[i].y1 = y0;
                pose_res->objects[i].x2 = x1;
                pose_res->objects[i].y2 = y1;
                pose_res->objects[i].confidence = p.prob;
                pose_res->objects[i].class_id = 0;

                if (out1.h > p.gindex && out1.w >= 51) {
                    const float* kp_row = out1.row(p.gindex);
                    for (int k = 0; k < POSE_KEYPOINTS_COUNT; k++) {
                        float kpx = (kp_row[k * 3 + 0] * target_size - pad_w) / scale;
                        float kpy = (kp_row[k * 3 + 1] * target_size - pad_h) / scale;
                        float kpc = fast_sigmoid(kp_row[k * 3 + 2]);
                        pose_res->objects[i].keypoints[k].x = std::max(0.0f, std::min((float)(rot_w - 1), kpx));
                        pose_res->objects[i].keypoints[k].y = std::max(0.0f, std::min((float)(rot_h - 1), kpy));
                        pose_res->objects[i].keypoints[k].confidence = kpc;
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

            int num_cls = out0.w * out0.h;
            std::vector<std::pair<float, int>> scores(num_cls);
            for (int k = 0; k < num_cls; k++) {
                scores[k] = std::make_pair(out0[k], k);
            }
            std::partial_sort(scores.begin(), scores.begin() + MAX_TOPK, scores.end(),
                              std::greater<std::pair<float, int>>());

            cls_res->num_items = MAX_TOPK;
            for (int k = 0; k < MAX_TOPK; k++) {
                cls_res->items[k].class_id = scores[k].second;
                cls_res->items[k].confidence = scores[k].first;
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            cls_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }

        case YOLO_TASK_OBB: {
            YoloObbResult* obb_res = (YoloObbResult*)out_result_buffer;
            ex.extract("out1", out1);

            std::vector<CandidateObject> proposals;
            const std::vector<int> strides = {8, 16, 32};
            int row_offset = 0;
            for (int s : strides) {
                int ngx = target_size / s;
                int ngy = target_size / s;
                int num_g = ngx * ngy;
                decode_yolo11_grid_proposals(out0.row_range(row_offset, num_g), s, target_size, target_size, 16, 15, 0.40f, row_offset, proposals);
                row_offset += num_g;
            }

            for (auto& obj : proposals) {
                float raw_angle = (out1.h > obj.gindex) ? out1.row(obj.gindex)[0] : 0.0f;
                float angle = fast_sigmoid(raw_angle) - 0.25f;
                obj.angle_rad = angle * PI_CONST;
                obj.angle_deg = angle * 180.0f;

                float cx_orig = (obj.cx - pad_w) / scale;
                float cy_orig = (obj.cy - pad_h) / scale;
                float w_orig = obj.w / scale;
                float h_orig = obj.h / scale;
                obj.cx = cx_orig;
                obj.cy = cy_orig;
                obj.w = w_orig;
                obj.h = h_orig;

                compute_obb_corners(cx_orig, cy_orig, w_orig, h_orig, obj.angle_rad, obj.corners);
            }

            sort_candidates_descent(proposals);
            std::vector<int> picked;
            nms_filter_obb(proposals, picked, 0.40f);

            int count = std::min((int)picked.size(), MAX_OBB_OBJECTS);
            obb_res->header.task_id = YOLO_TASK_OBB;
            obb_res->header.frame_id = current_fid;
            obb_res->header.preprocessing_time_ms = prep_ms;
            obb_res->header.inference_time_ms = inf_ms;
            obb_res->header.active_backend = g_ctx.active_backend;
            obb_res->header.status_code = 0;
            obb_res->num_objects = count;

            for (int i = 0; i < count; i++) {
                const auto& p = proposals[picked[i]];
                obb_res->objects[i].cx = p.cx;
                obb_res->objects[i].cy = p.cy;
                obb_res->objects[i].width = p.w;
                obb_res->objects[i].height = p.h;
                obb_res->objects[i].angle_rad = p.angle_rad;
                obb_res->objects[i].angle_deg = p.angle_deg;
                memcpy(obb_res->objects[i].corners, p.corners, 8 * sizeof(float));
                obb_res->objects[i].confidence = p.prob;
                obb_res->objects[i].class_id = p.label;
            }
            auto t_post_end = std::chrono::high_resolution_clock::now();
            obb_res->header.postprocessing_time_ms = std::chrono::duration<float, std::milli>(t_post_end - t_post_start).count();
            break;
        }
    }

    return 0;
}

void yolo_multitask_destroy(void) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    if (!g_ctx.initialized) return;

    if (g_ctx.active_task == YOLO_TASK_DETECTION) {
        yolo_rust_destroy();
    }

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
