# Triangle Rendering Benchmarks

A comprehensive collection of triangle rendering performance benchmarks across different graphics APIs and rendering techniques. This project allows you to compare the performance of legacy OpenGL, modern OpenGL, and Metal implementations on the same hardware.

## Overview

This benchmark suite includes three distinct implementations:

- **Classic OpenGL/GLUT** (`trispd`) - Brian Paul's original 1997 triangle speed test using deprecated OpenGL immediate mode
- **Modern OpenGL/GLFW** (`opengl_benchmark`) - Contemporary OpenGL 3.3 Core Profile with programmable shaders
- **Metal** (`metal_benchmark`) - Native macOS Metal API implementation for optimal Apple hardware performance

Each implementation measures triangle throughput, frame rates, and fill rates under various rendering conditions.

## Features

### Performance Metrics
- **Triangle Rate**: Millions of triangles rendered per second
- **Frame Rate**: Frames per second (FPS)
- **Fill Rate**: Millions of pixels rendered per second
- **Frame Time**: Average frame duration with moving averages

### Rendering Modes
- Triangle strips vs individual triangles
- Wireframe vs solid rendering
- Texture mapping (classic implementation)
- Display lists vs immediate mode (classic implementation)
- Real-time adjustable triangle counts

### Interactive Controls
- **ESC**: Exit program
- **W**: Toggle wireframe/solid rendering
- **S**: Toggle triangle strips/individual triangles
- **↑/↓**: Increase/decrease triangle count
- **D**: Toggle performance statistics display

## Requirements

### macOS
- **Operating System**: macOS 10.15+ (for Metal support)
- **Build Tools**: Xcode Command Line Tools
- **Package Manager**: Homebrew

### Linux
- **Operating System**: Ubuntu 18.04+ or equivalent
- **Build Tools**: GCC/Clang, Make
- **Display**: X11 with OpenGL support

## Installation

### macOS Setup
```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install cmake glfw glm

# Optional: Install legacy GLUT for classic implementation
brew install freeglut
```

### Linux Setup
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install cmake build-essential libglfw3-dev libglm-dev libgl1-mesa-dev libglu1-mesa-dev freeglut3-dev

# Fedora/RHEL
sudo dnf install cmake gcc-c++ glfw-devel glm-devel mesa-libGL-devel mesa-libGLU-devel freeglut-devel

# Arch Linux
sudo pacman -S cmake gcc glfw glm mesa glu freeglut
```

## Building

### Quick Start
```bash
# Clone and build
git clone <your-repo-url>
cd triangles_bench
mkdir build && cd build
cmake ..
cmake --build .
```

### Build Specific Targets
```bash
# Build individual benchmarks
cmake --build . --target trispd                    # Classic OpenGL
cmake --build . --target opengl_benchmark          # Modern OpenGL
cmake --build . --target metal_benchmark           # Metal (macOS only)
cmake --build . --target trispd-wtc-display-list   # Classic with display lists
```

### Available CMake Targets
| Target | Description |
|--------|-------------|
| `all` | Build all available benchmarks |
| `trispd` | Classic OpenGL immediate mode benchmark |
| `trispd-wtc-display-list` | Classic OpenGL with display lists |
| `opengl_benchmark` | Modern OpenGL with shaders |
| `metal_benchmark` | Metal API benchmark (macOS only) |
| `show-help` | Display available targets and commands |

## Usage

### Running Benchmarks

#### Quick Run Commands
```bash
# Run all benchmarks
cmake --build . --target run-all

# Run individual benchmarks
cmake --build . --target run-classic      # Classic OpenGL
cmake --build . --target run-opengl       # Modern OpenGL
cmake --build . --target run-metal        # Metal (macOS only)
```

#### Direct Execution
```bash
# From build directory
./trispd                    # Classic OpenGL
./opengl_benchmark          # Modern OpenGL
./metal_benchmark           # Metal (macOS only)
```

### Classic OpenGL Options
The classic `trispd` benchmark supports various command-line options:

```bash
# Basic usage
./trispd

# With texture mapping
./trispd +texture +linear -size 100

# With display lists
./trispd +dl

# Combined options
./trispd +texture +linear +dl -size 50 +smooth
```

#### Command-Line Parameters
| Option | Description |
|--------|-------------|
| `+/-texture` | Enable/disable texture mapping |
| `+/-linear` | Bilinear texture filtering |
| `+/-dl` | Enable/disable display lists |
| `+/-dither` | Enable/disable dithering |
| `+/-depth` | Enable/disable depth testing |
| `+smooth/+flat` | Smooth/flat shading |
| `-size N` | Triangle size in pixels |
| `-comp N` | Texture format components |
| `+/-persp` | Perspective correction hint |

### Benchmark Scenarios

#### Performance Comparison
```bash
# Compare immediate mode vs display lists
cmake --build . --target run-classic
cmake --build . --target run-classic-dl

# Compare with texture mapping
cmake --build . --target run-classic-texture
cmake --build . --target run-classic-texture-dl

# Cross-API comparison
cmake --build . --target run-classic
cmake --build . --target run-opengl
cmake --build . --target run-metal  # macOS only
```

#### Stress Testing
```bash
# High triangle count testing
./opengl_benchmark          # Use ↑ key to increase triangles
./metal_benchmark           # Use ↑ key to increase triangles

# Different rendering modes
./trispd +texture +linear -size 10    # Small textured triangles
./trispd -size 200                    # Large triangles
```

## Performance Analysis

### Understanding the Output

Each benchmark outputs performance metrics in this format:
```
Triangle Rate: 145.67 million triangles/sec | FPS: 156.3 | Triangles per frame: 931523 | Mode: STRIPS
```

- **Triangle Rate**: Primary performance metric - higher is better
- **FPS**: Frame rate - should be monitored for consistency
- **Triangles per frame**: Current workload per frame
- **Mode**: Current rendering mode (STRIPS/TRIANGLES, WIREFRAME/SOLID)

### Factors Affecting Performance

1. **Triangle Count**: More triangles = lower frame rate
2. **Rendering Mode**: Triangle strips are generally faster than individual triangles
3. **Fill Rate**: Large triangles stress pixel throughput
4. **GPU Architecture**: Modern GPUs favor different approaches
5. **Driver Overhead**: Varies between OpenGL and Metal

### Expected Performance Ranges

| API | Typical Range (M triangles/sec) | Notes |
|-----|--------------------------------|-------|
| Classic OpenGL | 10-100 | Depends heavily on driver and immediate mode overhead |
| Modern OpenGL | 100-500 | Better batching and reduced driver overhead |
| Metal | 200-800 | Optimized for Apple hardware, lower CPU overhead |

*Performance varies significantly based on hardware, resolution, and triangle size.*

## Troubleshooting

### Common Build Issues

#### GLFW Not Found (macOS)
```bash
# Ensure GLFW is installed
brew install glfw

# Check installation
brew list glfw
pkg-config --modversion glfw3
```

#### Metal Compilation Errors (macOS)
```bash
# Ensure Xcode Command Line Tools are installed
xcode-select --install

# Verify Metal tools
xcrun -sdk macosx metal --version
```

#### OpenGL Context Issues (Linux)
```bash
# Install Mesa drivers
sudo apt install mesa-utils

# Test OpenGL
glxinfo | grep "OpenGL version"
```

### Runtime Issues

#### No Display (Headless Systems)
- These benchmarks require a display/window system
- Use SSH with X11 forwarding: `ssh -X username@hostname`
- Consider VNC or virtual display for remote testing

#### Poor Performance
- Check GPU drivers are properly installed
- Verify hardware acceleration: `glxinfo | grep "direct rendering"`
- Monitor system resources during benchmarking
- Close other GPU-intensive applications

#### Shader Compilation Errors
- Ensure your GPU supports the required OpenGL version (3.3+)
- Update graphics drivers
- Check system OpenGL version: `glxinfo | grep "OpenGL version"`

## Project Structure

```
triangles_bench/
├── CMakeLists.txt              # Main build configuration
├── README.md                   # This file
├── CLAUDE.md                   # Project-specific build instructions
├── Makefile                    # Legacy build system (deprecated)
├── trispd.c                    # Classic OpenGL benchmark
├── trispd-wtc-display-list.c   # Classic with display lists
├── benchmark.cpp               # Modern OpenGL benchmark
├── benchmark.m                 # Metal benchmark (macOS)
├── Shaders.metal               # Metal shader source
└── build/                      # Build output directory
    ├── trispd
    ├── opengl_benchmark
    ├── metal_benchmark
    └── default.metallib        # Compiled Metal shaders
```

## Contributing

### Adding New Benchmarks
1. Create new source files following existing patterns
2. Add CMake targets in `CMakeLists.txt`
3. Update this README with new options
4. Test on multiple platforms

### Performance Optimizations
- Focus on cross-platform compatibility
- Document any platform-specific optimizations
- Include before/after performance measurements
- Consider both CPU and GPU bottlenecks

## Platform-Specific Notes

### macOS
- GLUT is deprecated but still functional with warnings
- Metal provides the best performance on Apple Silicon
- Use `brew` for dependency management
- Requires macOS 10.15+ for Metal features

### Linux
- Mesa drivers recommended for open-source GPU support
- Proprietary drivers (NVIDIA/AMD) may offer better performance
- X11 required for window creation
- Wayland support varies by distribution

### Windows
- Not currently supported but could be added
- Would require DirectX implementation for native performance
- GLFW/OpenGL portions should work with minimal changes

## Acknowledgments

- **Brian Paul**: Original triangle speed test implementation
- **Wagner Correa**: Display list optimization variant (trispd-wtc)
- **OpenGL Community**: Modern OpenGL techniques and best practices
- **Apple**: Metal API and development tools
- **GLFW/GLM Projects**: Cross-platform windowing and mathematics libraries

## References

- [OpenGL Programming Guide](https://www.opengl.org/documentation/)
- [Metal Programming Guide](https://developer.apple.com/metal/)
- [GLFW Documentation](https://www.glfw.org/documentation.html)
- [Original Mesa Demos](https://gitlab.freedesktop.org/mesa/demos)