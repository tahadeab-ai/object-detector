cmake_minimum_required(VERSION 3.22.1)
project(yolo_ncnn C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NCNN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/ncnn-android-vulkan/${ANDROID_ABI}")

set(ncnn_DIR "${NCNN_DIR}/lib/cmake/ncnn")
find_package(ncnn REQUIRED)

include_directories(
    "${CMAKE_CURRENT_SOURCE_DIR}/cpp"
    "${NCNN_DIR}/include/ncnn"
)

find_library(VULKAN_LIB vulkan)
find_library(LOG_LIB log)
find_library(ANDROID_LIB android)
find_library(JNIGRAPHICS_LIB jnigraphics)

# Link OpenMP statically (-fopenmp -static-openmp) into this ONE library only
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fopenmp -static-openmp")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fopenmp -static-openmp")

add_library(yolo_ncnn SHARED
    cpp/yolo_ncnn_runner.cpp
)

target_link_libraries(yolo_ncnn
    PRIVATE
    ncnn
    ${VULKAN_LIB}
    ${LOG_LIB}
    ${ANDROID_LIB}
    ${JNIGRAPHICS_LIB}
)
