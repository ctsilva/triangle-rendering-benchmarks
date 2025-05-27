# CLAUDE.md for Triangles Project

## Build Commands

### CMake Build System (Recommended)
```bash
# Install required dependencies on macOS
brew install cmake glfw glm

# Create build directory and configure
mkdir build && cd build
cmake ..

# Build all targets
cmake --build .

# Or build specific targets
cmake --build . --target trispd
cmake --build . --target opengl_benchmark
cmake --build . --target metal_benchmark  # macOS only

# Run benchmarks
cmake --build . --target run-classic
cmake --build . --target run-opengl
cmake --build . --target run-metal  # macOS only

# See all available targets
cmake --build . --target show-help
```

### Legacy Makefile (Deprecated)
```bash
# Install required dependencies on macOS
brew install freeglut

# Compile the program on macOS
gcc -o trispd trispd.c -I/opt/homebrew/include -L/opt/homebrew/lib -framework OpenGL -framework GLUT -Wno-deprecated-declarations

# Run the program
./trispd

# Run with specific options
./trispd -size 100 +texture +linear

# Run with display lists enabled
./trispd +dl
```

## macOS GLUT Compatibility Note
This project uses GLUT, which is deprecated on macOS. The "-Wno-deprecated-declarations" flag silences deprecation warnings. For modern development, consider using alternatives like GLFW or SDL2.

## Code Style Guidelines

### Formatting
- Use 3-space indentation for blocks
- Place opening braces on the same line as control statements
- Place else statements on their own line
- Keep line length under 80 characters

### Naming Conventions
- Use PascalCase for function names (e.g., `Display`, `Reshape`)
- Use capitalized first letter for global variables (e.g., `Size`, `Width`)
- Use lowercase for local variables (e.g., `x`, `y`, `triCount`)

### Error Handling
- Use appropriate error checking when calling GLUT/OpenGL functions
- Print descriptive error messages to stderr
- Exit with non-zero status code on critical errors

### Documentation
- Include descriptive comments at the beginning of each function
- Document each command-line parameter in the Help function
- Maintain the revision history in the file header