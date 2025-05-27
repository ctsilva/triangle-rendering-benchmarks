cmake_minimum_required(VERSION 3.16)
project(TrianglesBench 
    VERSION 1.0.0
    DESCRIPTION "Triangle rendering benchmarks for OpenGL and Metal"
    LANGUAGES C CXX OBJC)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Enable debug symbols in debug builds
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
set(CMAKE_C_FLAGS_DEBUG "-g -O0")

# Optimization for release builds
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG")

# Platform detection
if(APPLE)
    set(MACOS TRUE)
    message(STATUS "Building for macOS")
elseif(UNIX)
    set(LINUX TRUE)
    message(STATUS "Building for Linux")
else()
    message(FATAL_ERROR "Unsupported platform")
endif()

# Find required packages
if(MACOS)
    # macOS-specific packages
    find_library(OPENGL_LIBRARY OpenGL REQUIRED)
    find_library(GLUT_LIBRARY GLUT REQUIRED)
    find_library(COCOA_LIBRARY Cocoa REQUIRED)
    find_library(METAL_LIBRARY Metal REQUIRED)
    find_library(METALKIT_LIBRARY MetalKit REQUIRED)
    find_library(FOUNDATION_LIBRARY Foundation REQUIRED)
    find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
    
    # Try to find GLFW using pkg-config first
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(GLFW3 glfw3)
        if(GLFW3_FOUND)
            message(STATUS "Found GLFW via pkg-config: ${GLFW3_LIBRARIES}")
        endif()
    endif()
    
    if(NOT GLFW3_FOUND)
        # Look for GLFW in common Homebrew locations
        find_library(GLFW_LIBRARY 
            NAMES glfw glfw3
            HINTS /opt/homebrew/lib /usr/local/lib /opt/homebrew/Cellar/glfw/*/lib
            PATH_SUFFIXES lib
            REQUIRED)
        find_path(GLFW_INCLUDE_DIR 
            NAMES GLFW/glfw3.h
            HINTS /opt/homebrew/include /usr/local/include /opt/homebrew/Cellar/glfw/*/include
            PATH_SUFFIXES include
            REQUIRED)
        set(GLFW3_LIBRARIES ${GLFW_LIBRARY})
        set(GLFW3_INCLUDE_DIRS ${GLFW_INCLUDE_DIR})
        set(GLFW3_FOUND TRUE)
        message(STATUS "Found GLFW manually: ${GLFW_LIBRARY}")
    endif()
    
    # Look for GLM
    find_path(GLM_INCLUDE_DIR glm/glm.hpp
        HINTS /opt/homebrew/include /usr/local/include
        REQUIRED)
    
    message(STATUS "Found OpenGL: ${OPENGL_LIBRARY}")
    message(STATUS "Found GLUT: ${GLUT_LIBRARY}")
    message(STATUS "Found GLFW: ${GLFW3_LIBRARIES}")
    message(STATUS "Found GLM: ${GLM_INCLUDE_DIR}")
    
elseif(LINUX)
    # Linux-specific packages
    find_package(OpenGL REQUIRED)
    find_package(GLUT REQUIRED)
    find_package(glfw3 REQUIRED)
    find_package(glm REQUIRED)
endif()

# =============================================================================
# Classic OpenGL/GLUT Benchmark (trispd)
# =============================================================================

add_executable(trispd trispd.c)

if(MACOS)
    target_link_libraries(trispd 
        ${OPENGL_LIBRARY} 
        ${GLUT_LIBRARY})
    # Suppress deprecation warnings for GLUT on macOS
    target_compile_options(trispd PRIVATE -Wno-deprecated-declarations)
elseif(LINUX)
    target_link_libraries(trispd 
        OpenGL::GL 
        OpenGL::GLU 
        GLUT::GLUT 
        m)
endif()

# =============================================================================
# Classic OpenGL with Display Lists (trispd-wtc-display-list)
# =============================================================================

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/trispd-wtc-display-list.c")
    add_executable(trispd-wtc-display-list trispd-wtc-display-list.c)
    
    if(MACOS)
        target_link_libraries(trispd-wtc-display-list 
            ${OPENGL_LIBRARY} 
            ${GLUT_LIBRARY})
        target_compile_options(trispd-wtc-display-list PRIVATE -Wno-deprecated-declarations)
    elseif(LINUX)
        target_link_libraries(trispd-wtc-display-list 
            OpenGL::GL 
            OpenGL::GLU 
            GLUT::GLUT 
            m)
    endif()
endif()

# =============================================================================
# Modern OpenGL/GLFW Benchmark (opengl_benchmark)
# =============================================================================

add_executable(opengl_benchmark benchmark.cpp)

if(MACOS)
    target_include_directories(opengl_benchmark PRIVATE 
        ${GLFW3_INCLUDE_DIRS}
        ${GLM_INCLUDE_DIR})
    target_link_directories(opengl_benchmark PRIVATE 
        ${GLFW3_LIBRARY_DIRS})
    target_link_libraries(opengl_benchmark 
        ${OPENGL_LIBRARY}
        ${GLFW3_LIBRARIES})
    target_compile_options(opengl_benchmark PRIVATE -Wno-deprecated-declarations)
elseif(LINUX)
    target_link_libraries(opengl_benchmark 
        OpenGL::GL 
        glfw 
        glm::glm)
endif()

# =============================================================================
# Metal Benchmark (macOS only)
# =============================================================================

if(MACOS)
    add_executable(metal_benchmark benchmark.m)
    
    target_link_libraries(metal_benchmark
        ${METAL_LIBRARY}
        ${METALKIT_LIBRARY}
        ${COCOA_LIBRARY}
        ${FOUNDATION_LIBRARY}
        ${QUARTZCORE_LIBRARY})
    
    # Enable ARC for Objective-C
    target_compile_options(metal_benchmark PRIVATE -fobjc-arc)
    
    # Custom command to compile Metal shaders
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/default.metallib
        COMMAND xcrun -sdk macosx metal -c ${CMAKE_CURRENT_SOURCE_DIR}/Shaders.metal -o ${CMAKE_CURRENT_BINARY_DIR}/Shaders.air
        COMMAND xcrun -sdk macosx metallib ${CMAKE_CURRENT_BINARY_DIR}/Shaders.air -o ${CMAKE_CURRENT_BINARY_DIR}/default.metallib
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/Shaders.metal
        COMMENT "Compiling Metal shaders"
        VERBATIM)
    
    add_custom_target(metal_shaders 
        DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/default.metallib)
    
    add_dependencies(metal_benchmark metal_shaders)
    
    # Copy the metallib to the output directory
    add_custom_command(TARGET metal_benchmark POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_BINARY_DIR}/default.metallib
        $<TARGET_FILE_DIR:metal_benchmark>/default.metallib)
endif()

# =============================================================================
# Custom targets for running benchmarks
# =============================================================================

# Classic OpenGL runs
add_custom_target(run-classic
    COMMAND $<TARGET_FILE:trispd>
    DEPENDS trispd
    COMMENT "Running classic OpenGL benchmark")

add_custom_target(run-classic-dl
    COMMAND $<TARGET_FILE:trispd> +dl
    DEPENDS trispd
    COMMENT "Running classic OpenGL benchmark with display lists")

add_custom_target(run-classic-texture
    COMMAND $<TARGET_FILE:trispd> +texture +linear -size 100
    DEPENDS trispd
    COMMENT "Running classic OpenGL benchmark with texture")

add_custom_target(run-classic-texture-dl
    COMMAND $<TARGET_FILE:trispd> +texture +linear -size 100 +dl
    DEPENDS trispd
    COMMENT "Running classic OpenGL benchmark with texture and display lists")

# WTC display list variant (if available)
if(TARGET trispd-wtc-display-list)
    add_custom_target(run-wtc
        COMMAND $<TARGET_FILE:trispd-wtc-display-list>
        DEPENDS trispd-wtc-display-list
        COMMENT "Running WTC display list benchmark")
    
    add_custom_target(run-wtc-texture
        COMMAND $<TARGET_FILE:trispd-wtc-display-list> +texture +linear -size 100
        DEPENDS trispd-wtc-display-list
        COMMENT "Running WTC display list benchmark with texture")
endif()

# Modern OpenGL runs
add_custom_target(run-opengl
    COMMAND $<TARGET_FILE:opengl_benchmark>
    DEPENDS opengl_benchmark
    COMMENT "Running modern OpenGL benchmark")

# Metal runs (macOS only)
if(MACOS AND TARGET metal_benchmark)
    add_custom_target(run-metal
        COMMAND $<TARGET_FILE:metal_benchmark>
        DEPENDS metal_benchmark
        COMMENT "Running Metal benchmark")
endif()

# Convenience target to run all benchmarks
set(ALL_BENCHMARK_TARGETS run-classic run-opengl)
if(TARGET trispd-wtc-display-list)
    list(APPEND ALL_BENCHMARK_TARGETS run-wtc)
endif()
if(MACOS AND TARGET metal_benchmark)
    list(APPEND ALL_BENCHMARK_TARGETS run-metal)
endif()

add_custom_target(run-all
    COMMENT "Running all available benchmarks")

foreach(target ${ALL_BENCHMARK_TARGETS})
    add_dependencies(run-all ${target})
endforeach()

# =============================================================================
# Help target
# =============================================================================

add_custom_target(show-help
    COMMAND ${CMAKE_COMMAND} -E echo ""
    COMMAND ${CMAKE_COMMAND} -E echo "Triangle Benchmarks Build System"
    COMMAND ${CMAKE_COMMAND} -E echo "================================"
    COMMAND ${CMAKE_COMMAND} -E echo ""
    COMMAND ${CMAKE_COMMAND} -E echo "Build targets:"
    COMMAND ${CMAKE_COMMAND} -E echo "  all                    - Build all benchmarks"
    COMMAND ${CMAKE_COMMAND} -E echo "  trispd                 - Build classic OpenGL benchmark"
    COMMAND ${CMAKE_COMMAND} -E echo "  opengl_benchmark       - Build modern OpenGL benchmark"
    COMMAND ${CMAKE_COMMAND} -E echo "  metal_benchmark        - Build Metal benchmark (macOS only)"
    COMMAND ${CMAKE_COMMAND} -E echo ""
    COMMAND ${CMAKE_COMMAND} -E echo "Run targets:"
    COMMAND ${CMAKE_COMMAND} -E echo "  run-classic            - Run classic OpenGL (immediate mode)"
    COMMAND ${CMAKE_COMMAND} -E echo "  run-classic-dl         - Run classic OpenGL with display lists"
    COMMAND ${CMAKE_COMMAND} -E echo "  run-classic-texture    - Run classic OpenGL with texture"
    COMMAND ${CMAKE_COMMAND} -E echo "  run-classic-texture-dl - Run classic OpenGL with texture + display lists"
    COMMAND ${CMAKE_COMMAND} -E echo "  run-opengl             - Run modern OpenGL benchmark"
    COMMAND ${CMAKE_COMMAND} -E echo "  run-metal              - Run Metal benchmark (macOS only)"
    COMMAND ${CMAKE_COMMAND} -E echo "  run-all                - Run all available benchmarks"
    COMMAND ${CMAKE_COMMAND} -E echo ""
    COMMENT "Displaying help information")

# =============================================================================
# Installation (optional)
# =============================================================================

install(TARGETS trispd opengl_benchmark
    RUNTIME DESTINATION bin)

if(TARGET trispd-wtc-display-list)
    install(TARGETS trispd-wtc-display-list
        RUNTIME DESTINATION bin)
endif()

if(MACOS AND TARGET metal_benchmark)
    install(TARGETS metal_benchmark
        RUNTIME DESTINATION bin)
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/default.metallib
        DESTINATION bin)
endif()