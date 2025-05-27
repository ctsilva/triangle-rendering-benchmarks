#include <GLFW/glfw3.h>
#include <OpenGL/gl3.h>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <iostream>
#include <vector>
#include <sstream>
#include <iomanip>
#include <chrono>
#include <deque>
#include <numeric>

// Vertex shader source code
const char* vertexShaderSource = R"(
#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aColor;
out vec3 ourColor;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

void main() {
    gl_Position = projection * view * model * vec4(aPos, 1.0);
    ourColor = aColor;
}
)";

// Fragment shader source code
const char* fragmentShaderSource = R"(
#version 330 core
in vec3 ourColor;
out vec4 FragColor;
void main() {
    FragColor = vec4(ourColor, 1.0);
}
)";

// Function to check shader compilation/linking errors
void checkErrors(GLuint shader, const std::string& type) {
    GLint success;
    GLchar infoLog[1024];
    
    if (type != "PROGRAM") {
        glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
        if (!success) {
            glGetShaderInfoLog(shader, 1024, NULL, infoLog);
            std::cerr << "ERROR::SHADER::" << type << "::COMPILATION_FAILED\n" << infoLog << std::endl;
        }
    } else {
        glGetProgramiv(shader, GL_LINK_STATUS, &success);
        if (!success) {
            glGetProgramInfoLog(shader, 1024, NULL, infoLog);
            std::cerr << "ERROR::PROGRAM::LINKING_FAILED\n" << infoLog << std::endl;
        }
    }
}

// Global variables for benchmarking
struct BenchmarkConfig {
    int triangleCount = 1000;  // Start with 1000 triangles
    bool useTriangleStrips = true;
    bool wireframeMode = false;
    bool showStats = true;
    std::deque<double> frameTimes;
    double lastTime = 0.0;
    int frameCount = 0;
    int frameTimeWindow = 60;  // Average over 60 frames
} benchConfig;

// Callback for window resize
void framebuffer_size_callback(GLFWwindow* window, int width, int height) {
    glViewport(0, 0, width, height);
}

// Process keyboard input
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods) {
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
        glfwSetWindowShouldClose(window, true);
        
    // Toggle wireframe mode with 'W' key
    if (key == GLFW_KEY_W && action == GLFW_PRESS)
        benchConfig.wireframeMode = !benchConfig.wireframeMode;
        
    // Toggle between triangle strips and individual triangles with 'S' key
    if (key == GLFW_KEY_S && action == GLFW_PRESS)
        benchConfig.useTriangleStrips = !benchConfig.useTriangleStrips;
        
    // Increase triangle count with up arrow
    if (key == GLFW_KEY_UP && action == GLFW_PRESS) {
        benchConfig.triangleCount = static_cast<int>(benchConfig.triangleCount * 1.5);
        std::cout << "Triangle count: " << benchConfig.triangleCount << std::endl;
    }
    
    // Decrease triangle count with down arrow
    if (key == GLFW_KEY_DOWN && action == GLFW_PRESS) {
        benchConfig.triangleCount = std::max(100, static_cast<int>(benchConfig.triangleCount / 1.5));
        std::cout << "Triangle count: " << benchConfig.triangleCount << std::endl;
    }
    
    // Toggle stats display with 'D' key
    if (key == GLFW_KEY_D && action == GLFW_PRESS)
        benchConfig.showStats = !benchConfig.showStats;
}

// Generate vertices for a sphere of radius 1, centered at origin
std::vector<float> generateSphereVertices(int resolution) {
    std::vector<float> vertices;
    
    for (int i = 0; i < resolution; i++) {
        float phi1 = static_cast<float>(i) * M_PI / static_cast<float>(resolution);
        float phi2 = static_cast<float>(i + 1) * M_PI / static_cast<float>(resolution);
        
        for (int j = 0; j <= resolution * 2; j++) {
            float theta = static_cast<float>(j) * 2.0f * M_PI / static_cast<float>(resolution * 2);
            
            // First vertex (i, j)
            float x1 = sin(phi1) * cos(theta);
            float y1 = cos(phi1);
            float z1 = sin(phi1) * sin(theta);
            
            // Color based on position (normalized to 0-1)
            float r1 = (x1 + 1.0f) / 2.0f;
            float g1 = (y1 + 1.0f) / 2.0f;
            float b1 = (z1 + 1.0f) / 2.0f;
            
            // Second vertex (i+1, j)
            float x2 = sin(phi2) * cos(theta);
            float y2 = cos(phi2);
            float z2 = sin(phi2) * sin(theta);
            
            float r2 = (x2 + 1.0f) / 2.0f;
            float g2 = (y2 + 1.0f) / 2.0f;
            float b2 = (z2 + 1.0f) / 2.0f;
            
            // Add first vertex
            vertices.push_back(x1); vertices.push_back(y1); vertices.push_back(z1);  // Position
            vertices.push_back(r1); vertices.push_back(g1); vertices.push_back(b1);  // Color
            
            // Add second vertex
            vertices.push_back(x2); vertices.push_back(y2); vertices.push_back(z2);  // Position
            vertices.push_back(r2); vertices.push_back(g2); vertices.push_back(b2);  // Color
        }
    }
    
    return vertices;
}

// Generate a simple grid of triangles for benchmarking
std::vector<float> generateBenchmarkVertices(int triangleCount) {
    std::vector<float> vertices;
    int gridSize = static_cast<int>(sqrt(triangleCount)) + 1;
    float cellSize = 2.0f / static_cast<float>(gridSize);
    
    for (int i = 0; i < gridSize; i++) {
        for (int j = 0; j < gridSize; j++) {
            float x = -1.0f + j * cellSize;
            float z = -1.0f + i * cellSize;
            float y = 0.0f;
            
            // Create two triangles per grid cell
            // Triangle 1
            vertices.push_back(x); vertices.push_back(y); vertices.push_back(z);  // Position
            vertices.push_back(0.0f); vertices.push_back(0.0f); vertices.push_back(1.0f);  // Color (blue)
            
            vertices.push_back(x + cellSize); vertices.push_back(y); vertices.push_back(z);  // Position
            vertices.push_back(1.0f); vertices.push_back(0.0f); vertices.push_back(0.0f);  // Color (red)
            
            vertices.push_back(x); vertices.push_back(y); vertices.push_back(z + cellSize);  // Position
            vertices.push_back(0.0f); vertices.push_back(1.0f); vertices.push_back(0.0f);  // Color (green)
            
            // Triangle 2
            vertices.push_back(x + cellSize); vertices.push_back(y); vertices.push_back(z);  // Position
            vertices.push_back(1.0f); vertices.push_back(0.0f); vertices.push_back(0.0f);  // Color (red)
            
            vertices.push_back(x + cellSize); vertices.push_back(y); vertices.push_back(z + cellSize);  // Position
            vertices.push_back(1.0f); vertices.push_back(1.0f); vertices.push_back(0.0f);  // Color (yellow)
            
            vertices.push_back(x); vertices.push_back(y); vertices.push_back(z + cellSize);  // Position
            vertices.push_back(0.0f); vertices.push_back(1.0f); vertices.push_back(0.0f);  // Color (green)
        }
    }
    
    return vertices;
}

// Generate triangle strip vertices
std::vector<float> generateTriangleStripVertices(int triangleCount) {
    std::vector<float> vertices;
    int gridWidth = static_cast<int>(sqrt(triangleCount * 2)) + 1;
    int gridHeight = gridWidth;
    float cellWidth = 2.0f / static_cast<float>(gridWidth);
    float cellHeight = 2.0f / static_cast<float>(gridHeight);
    
    for (int row = 0; row < gridHeight - 1; row++) {
        for (int col = 0; col < gridWidth; col++) {
            // Calculate positions
            float x = -1.0f + col * cellWidth;
            float z1 = -1.0f + row * cellHeight;
            float z2 = -1.0f + (row + 1) * cellHeight;
            float y = 0.0f;
            
            // Top vertex
            vertices.push_back(x); vertices.push_back(y); vertices.push_back(z1);
            vertices.push_back(col / static_cast<float>(gridWidth)); 
            vertices.push_back(row / static_cast<float>(gridHeight));
            vertices.push_back(1.0f - row / static_cast<float>(gridHeight));
            
            // Bottom vertex
            vertices.push_back(x); vertices.push_back(y); vertices.push_back(z2);
            vertices.push_back(col / static_cast<float>(gridWidth)); 
            vertices.push_back((row + 1) / static_cast<float>(gridHeight));
            vertices.push_back(1.0f - (row + 1) / static_cast<float>(gridHeight));
        }
        
        // Add a degenerate triangle if this is not the last row
        // This creates a "bridge" to the next row
        if (row < gridHeight - 2) {
            // Last vertex of current row
            float x1 = -1.0f + (gridWidth - 1) * cellWidth;
            float z1 = -1.0f + (row + 1) * cellHeight;
            
            // First vertex of next row
            float x2 = -1.0f;
            float z2 = -1.0f + (row + 1) * cellHeight;
            
            float y = 0.0f;
            
            // Repeat last vertex
            vertices.push_back(x1); vertices.push_back(y); vertices.push_back(z1);
            vertices.push_back((gridWidth - 1) / static_cast<float>(gridWidth));
            vertices.push_back((row + 1) / static_cast<float>(gridHeight));
            vertices.push_back(1.0f - (row + 1) / static_cast<float>(gridHeight));
            
            // Add first vertex of next row
            vertices.push_back(x2); vertices.push_back(y); vertices.push_back(z2);
            vertices.push_back(0.0f);
            vertices.push_back((row + 1) / static_cast<float>(gridHeight));
            vertices.push_back(1.0f - (row + 1) / static_cast<float>(gridHeight));
        }
    }
    
    return vertices;
}

int main() {
    // Initialize GLFW
    if (!glfwInit()) {
        std::cerr << "Failed to initialize GLFW" << std::endl;
        return -1;
    }
    
    // Configure GLFW
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE); // Required for Mac OS X
    
    // Create a window
    GLFWwindow* window = glfwCreateWindow(800, 600, "OpenGL Performance Benchmark", NULL, NULL);
    if (window == NULL) {
        std::cerr << "Failed to create GLFW window" << std::endl;
        glfwTerminate();
        return -1;
    }
    
    // Make the window's context current
    glfwMakeContextCurrent(window);
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
    glfwSetKeyCallback(window, key_callback);
    
    // Build and compile shaders
    // Vertex Shader
    GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertexShader, 1, &vertexShaderSource, NULL);
    glCompileShader(vertexShader);
    checkErrors(vertexShader, "VERTEX");
    
    // Fragment Shader
    GLuint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragmentShader, 1, &fragmentShaderSource, NULL);
    glCompileShader(fragmentShader);
    checkErrors(fragmentShader, "FRAGMENT");
    
    // Shader Program
    GLuint shaderProgram = glCreateProgram();
    glAttachShader(shaderProgram, vertexShader);
    glAttachShader(shaderProgram, fragmentShader);
    glLinkProgram(shaderProgram);
    checkErrors(shaderProgram, "PROGRAM");
    
    // Delete shaders as they're linked into our program and no longer needed
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);
    
    // Create a Vertex Array Object (VAO)
    GLuint VAO;
    glGenVertexArrays(1, &VAO);
    glBindVertexArray(VAO);
    
    // Create a Vertex Buffer Object (VBO)
    GLuint VBO;
    glGenBuffers(1, &VBO);
    
    // Enable depth testing
    glEnable(GL_DEPTH_TEST);
    
    // Get shader uniform locations
    GLuint modelLoc = glGetUniformLocation(shaderProgram, "model");
    GLuint viewLoc = glGetUniformLocation(shaderProgram, "view");
    GLuint projectionLoc = glGetUniformLocation(shaderProgram, "projection");
    
    // Print instructions
    std::cout << "OpenGL Performance Benchmark\n"
              << "----------------------------\n"
              << "Controls:\n"
              << "  ESC - Exit program\n"
              << "  W   - Toggle wireframe mode\n"
              << "  S   - Toggle between triangle strips and individual triangles\n"
              << "  Up  - Increase triangle count\n"
              << "  Down- Decrease triangle count\n"
              << "  D   - Toggle stats display\n"
              << "\nBenchmark statistics will be printed to this console.\n"
              << "----------------------------\n"
              << std::endl;
    
    // Start time for FPS calculation
    double lastTime = glfwGetTime();
    int frameCount = 0;
    double trianglesPerSecond = 0.0;
    
    // Render loop
    while (!glfwWindowShouldClose(window)) {
        // Measure frame time
        double currentTime = glfwGetTime();
        double deltaTime = currentTime - benchConfig.lastTime;
        benchConfig.lastTime = currentTime;
        
        // Update FPS stats
        frameCount++;
        benchConfig.frameCount++;
        
        // Add current frame time to the queue
        benchConfig.frameTimes.push_back(deltaTime);
        if (benchConfig.frameTimes.size() > benchConfig.frameTimeWindow) {
            benchConfig.frameTimes.pop_front();
        }
        
        // Generate new vertices based on current config
        std::vector<float> vertices;
        int actualTriangleCount = 0;
        
        if (benchConfig.useTriangleStrips) {
            vertices = generateTriangleStripVertices(benchConfig.triangleCount);
            actualTriangleCount = vertices.size() / 6 - 2; // For a strip, n vertices produce n-2 triangles
        } else {
            vertices = generateBenchmarkVertices(benchConfig.triangleCount);
            actualTriangleCount = vertices.size() / 18; // Each triangle has 3 vertices with 6 components each
        }
        
        // Update the VBO
        glBindBuffer(GL_ARRAY_BUFFER, VBO);
        glBufferData(GL_ARRAY_BUFFER, vertices.size() * sizeof(float), vertices.data(), GL_STATIC_DRAW);
        
        // Position attribute
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float), (void*)0);
        glEnableVertexAttribArray(0);
        
        // Color attribute
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(float), (void*)(3 * sizeof(float)));
        glEnableVertexAttribArray(1);
        
        // Render
        glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        // Set wireframe mode if enabled
        if (benchConfig.wireframeMode) {
            glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
        } else {
            glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
        }
        
        // Activate shader
        glUseProgram(shaderProgram);
        
        // Create transformations
        glm::mat4 model = glm::mat4(1.0f);
        glm::mat4 view = glm::mat4(1.0f);
        glm::mat4 projection = glm::mat4(1.0f);
        
        // Rotate the model
        model = glm::rotate(model, (float)currentTime * 0.5f, glm::vec3(0.0f, 1.0f, 0.0f));
        model = glm::rotate(model, (float)currentTime * 0.3f, glm::vec3(1.0f, 0.0f, 0.0f));
        
        // Camera position
        view = glm::translate(view, glm::vec3(0.0f, 0.0f, -2.5f));
        
        // Projection
        projection = glm::perspective(glm::radians(45.0f), 800.0f / 600.0f, 0.1f, 100.0f);
        
        // Pass transformations to shader
        glUniformMatrix4fv(modelLoc, 1, GL_FALSE, glm::value_ptr(model));
        glUniformMatrix4fv(viewLoc, 1, GL_FALSE, glm::value_ptr(view));
        glUniformMatrix4fv(projectionLoc, 1, GL_FALSE, glm::value_ptr(projection));
        
        // Draw the triangles
        glBindVertexArray(VAO);
        if (benchConfig.useTriangleStrips) {
            // Draw as triangle strip
            glDrawArrays(GL_TRIANGLE_STRIP, 0, vertices.size() / 6);
        } else {
            // Draw as individual triangles
            glDrawArrays(GL_TRIANGLES, 0, vertices.size() / 6);
        }
        
        // Calculate FPS and display it in the window title if showing stats
        if (currentTime - lastTime >= 0.5) { // Update every half second
            double fps = frameCount / (currentTime - lastTime);
            double avgFrameTime = 0.0;
            
            if (!benchConfig.frameTimes.empty()) {
                avgFrameTime = std::accumulate(benchConfig.frameTimes.begin(), benchConfig.frameTimes.end(), 0.0) / 
                               benchConfig.frameTimes.size();
            }
            
            // Calculate triangles per second
            trianglesPerSecond = actualTriangleCount * fps;
            
            // Output triangle rendering rate to standard output
            std::cout << "Triangle Rate: " << std::fixed << std::setprecision(2) 
                      << trianglesPerSecond / 1000000.0 << " million triangles/sec | "
                      << "FPS: " << std::fixed << std::setprecision(1) << fps << " | "
                      << "Triangles per frame: " << actualTriangleCount << " | "
                      << "Mode: " << (benchConfig.useTriangleStrips ? "STRIPS" : "TRIANGLES")
                      << std::endl;
            
            if (benchConfig.showStats) {
                std::stringstream ss;
                ss << "OpenGL Benchmark | " 
                   << "FPS: " << std::fixed << std::setprecision(1) << fps << " | "
                   << "Frame Time: " << std::fixed << std::setprecision(2) << (avgFrameTime * 1000.0) << "ms | "
                   << "Triangles: " << actualTriangleCount << " | "
                   << "Tri Rate: " << std::fixed << std::setprecision(2) << trianglesPerSecond / 1000000.0 << "M/s | "
                   << "Mode: " << (benchConfig.useTriangleStrips ? "STRIPS" : "TRIANGLES") << " | "
                   << "Render: " << (benchConfig.wireframeMode ? "WIREFRAME" : "SOLID");
                glfwSetWindowTitle(window, ss.str().c_str());
            } else {
                glfwSetWindowTitle(window, "OpenGL Performance Benchmark");
            }
            
            lastTime = currentTime;
            frameCount = 0;
        }
        
        // Swap buffers and poll IO events
        glfwSwapBuffers(window);
        glfwPollEvents();
    }
    
    // Deallocate resources
    glDeleteVertexArrays(1, &VAO);
    glDeleteBuffers(1, &VBO);
    glDeleteProgram(shaderProgram);
    
    // Terminate GLFW
    glfwTerminate();
    return 0;
}
