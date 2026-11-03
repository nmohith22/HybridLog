cmake_minimum_required(VERSION 3.18.1)
project(needle_bridge)

if(NOT ANDROID_ABI STREQUAL "arm64-v8a" AND NOT ANDROID_ABI STREQUAL "armeabi-v7a")
    add_library(needle_bridge SHARED needle_bridge_stub.cpp)
    target_link_libraries(needle_bridge log)
    return()
endif()

add_library(needle_runtime STATIC IMPORTED)
set_target_properties(needle_runtime PROPERTIES IMPORTED_LOCATION
    "${CMAKE_CURRENT_SOURCE_DIR}/vendor/${ANDROID_ABI}/libneedle.a")

add_library(needle_bridge SHARED needle_bridge.cpp)
target_include_directories(needle_bridge PRIVATE vendor)
target_link_libraries(needle_bridge needle_runtime log)
