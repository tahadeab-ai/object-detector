cmake_minimum_required(VERSION 3.22.1)
project(yolo11ncnn_feed)

add_library(yolo11ncnn_feed SHARED yolo11ncnn_feed.cpp)

find_library(log-lib log)
find_library(jnigraphics-lib jnigraphics)

target_link_libraries(yolo11ncnn_feed
    ${log-lib}
    ${jnigraphics-lib}
    dl
)
