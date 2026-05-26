cmake_minimum_required(VERSION 3.20)
project(MandelbrotAsm LANGUAGES C CXX ASM_MASM)

add_executable(MandelbrotAsm
    MandelbrotAsm.cpp
    core.asm
)
target_compile_options(MandelbrotAsm PRIVATE $<$<CONFIG:Release>:/O2>)
target_compile_features(MandelbrotAsm PRIVATE cxx_std_17)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/opencv/opencv/build)
find_package(OpenCV REQUIRED)
target_link_libraries(MandelbrotAsm PRIVATE ${OpenCV_LIBS} "${CMAKE_CURRENT_LIST_DIR}/opencv/opencv/build/x64/vc16/lib")

target_include_directories(MandelbrotAsm PRIVATE ${OpenCV_INCLUDE_DIRS})
find_path(GMP_INCLUDE_DIR gmp.h)
find_library(GMP_LIBRARY gmp)

target_include_directories(MandelbrotAsm PRIVATE ${GMP_INCLUDE_DIR})
target_link_libraries(MandelbrotAsm PRIVATE ${GMP_LIBRARY})

add_custom_command(TARGET MandelbrotAsm POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_SOURCE_DIR}/deepfortran/mandelbrotfortran.dll"
        "$<TARGET_FILE_DIR:MandelbrotAsm>/mandelbrotfortran.dll"
    COMMAND ${CMAKE_COMMAND} -E make_directory "output"

    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "$<TARGET_FILE_DIR:MandelbrotAsm>"
        "${CMAKE_SOURCE_DIR}/output"
)

