cmake_minimum_required(VERSION 3.31.6)

project(monga_native LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -O2")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -O2")

set_property(GLOBAL PROPERTY JOB_POOLS compile_pool=1)
set(CMAKE_JOB_POOL_COMPILE compile_pool)

set(LLAMA_SRC ${CMAKE_CURRENT_LIST_DIR}/third_party/llama.cpp)

add_subdirectory(
        ${LLAMA_SRC}
        build-llama
)

add_library(
        monga_native
        SHARED
        monga_native.cpp
)

target_include_directories(
        monga_native
        PRIVATE
        ${LLAMA_SRC}
        ${LLAMA_SRC}/include
        ${LLAMA_SRC}/ggml/include
        ${LLAMA_SRC}/ggml/src
)

target_link_libraries(
        monga_native
        PRIVATE
        llama
        android
        log
)
