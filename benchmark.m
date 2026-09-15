#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

// Vertex structure
typedef struct {
    vector_float3 position;
    vector_float3 color;
} Vertex;

// Uniform buffer containing transformation matrices
typedef struct {
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
} Uniforms;

// Benchmark configuration
typedef struct {
    BOOL useTriangleStrips;
    BOOL wireframeMode;
    BOOL showStats;
    NSUInteger triangleCount;
    NSMutableArray *frameTimes;
    NSUInteger frameTimeWindowSize;
    double lastTime;
    NSUInteger frameCount;
    double trianglesPerSecond;
} BenchmarkConfig;

static NSLock *gGpuLock;
static double gGpuSeconds;
static unsigned gGpuFrames;

// Forward declarations
@interface MetalRenderer : NSObject <MTKViewDelegate>
- (instancetype)initWithMetalView:(MTKView *)mtkView;
- (void)increaseTriangleCount;
- (void)decreaseTriangleCount;
- (void)toggleTriangleStrips;
- (void)toggleWireframeMode;
- (void)toggleStatsDisplay;
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size;

@end

@interface MetalView : MTKView
@property (nonatomic, strong) MetalRenderer *renderer;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) MetalView *metalView;
@end

// MARK: - Matrix Math Utilities

static matrix_float4x4 matrix_identity(void) {
    vector_float4 columns[4] = {
        { 1, 0, 0, 0 },
        { 0, 1, 0, 0 },
        { 0, 0, 1, 0 },
        { 0, 0, 0, 1 }
    };
    return (matrix_float4x4){ columns[0], columns[1], columns[2], columns[3] };
}

static matrix_float4x4 matrix_perspective(float fovRadians, float aspect, float nearZ, float farZ) {
    float ys = 1 / tanf(fovRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    
    vector_float4 columns[4] = {
        { xs,  0,  0,                0 },
        { 0,  ys,  0,                0 },
        { 0,   0, zs, nearZ * zs },
        { 0,   0, -1,                0 }
    };
    
    return (matrix_float4x4){ columns[0], columns[1], columns[2], columns[3] };
}

static matrix_float4x4 matrix_translation(float x, float y, float z) {
    vector_float4 columns[4] = {
        {   1,   0,   0,   0 },
        {   0,   1,   0,   0 },
        {   0,   0,   1,   0 },
        {   x,   y,   z,   1 }
    };
    
    return (matrix_float4x4){ columns[0], columns[1], columns[2], columns[3] };
}

static matrix_float4x4 matrix_rotation(float radians, vector_float3 axis) {
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;
    
    vector_float4 columns[4] = {
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0 },
        { x * y * ci - z * st, ct + y * y * ci,     z * y * ci + x * st, 0 },
        { x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci,     0 },
        { 0,                   0,                   0,                   1 }
    };
    
    return (matrix_float4x4){ columns[0], columns[1], columns[2], columns[3] };
}

// MARK: - MetalRenderer Implementation

@implementation MetalRenderer {
    id<MTLDevice> _device;
    id<MTLLibrary> _defaultLibrary;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLDepthStencilState> _depthState;
    id<MTLCommandQueue> _commandQueue;
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _indexBuffer;
    id<MTLBuffer> _uniformBuffer;
    
    NSUInteger _vertexCount;
    NSUInteger _indexCount;
    NSUInteger _actualTriangleCount;
    
    BenchmarkConfig _config;
    MTLPrimitiveType _primitiveType;
    MTKView *_mtkView;
    
    // For drawable size tracking
    CGFloat _drawableWidth;
    CGFloat _drawableHeight;
    
    // For storing frame time history
    NSDate *_startTime;
}

- (instancetype)initWithMetalView:(MTKView *)mtkView {
    self = [super init];
    if (self) {
        _mtkView = mtkView;
        _device = mtkView.device;
        
        // Initialize drawable size
        _drawableWidth = mtkView.drawableSize.width;
        _drawableHeight = mtkView.drawableSize.height;
        
        NSLog(@"Initial drawable size: %.1f x %.1f", _drawableWidth, _drawableHeight);
        
        // Initialize benchmark configuration
        _config.triangleCount = 1000;
        _config.useTriangleStrips = YES;
        if (getenv("TRIANGLES")) {
            _config.triangleCount = strtoul(getenv("TRIANGLES"), NULL, 10);
        }
        if (getenv("MODE") && strcmp(getenv("MODE"), "triangles") == 0) {
            _config.useTriangleStrips = NO;
        }
        _config.wireframeMode = NO;
        _config.showStats = YES;
        _config.frameTimes = [NSMutableArray arrayWithCapacity:60];
        _config.frameTimeWindowSize = 60; // Average over 60 frames
        _config.lastTime = CACurrentMediaTime();
        _config.frameCount = 0;
        _config.trianglesPerSecond = 0.0;
        
        // Set primitive type
        _primitiveType = _config.useTriangleStrips ? MTLPrimitiveTypeTriangleStrip : MTLPrimitiveTypeTriangle;
        
        _startTime = [NSDate date];
        
        [self _setupMetal];
        [self _createBuffers];
        
        // Print usage instructions
        NSLog(@"Metal Performance Benchmark");
        NSLog(@"----------------------------");
        NSLog(@"Controls:");
        NSLog(@"  ESC - Exit program");
        NSLog(@"  W   - Toggle wireframe mode");
        NSLog(@"  S   - Toggle between triangle strips and individual triangles");
        NSLog(@"  Up  - Increase triangle count");
        NSLog(@"  Down- Decrease triangle count");
        NSLog(@"  D   - Toggle stats display");
        NSLog(@"");
        NSLog(@"Benchmark statistics will be printed to this console.");
        NSLog(@"----------------------------");
    }
    return self;
}

- (void)_setupMetal {
    // Load Metal shaders from the precompiled metallib
    NSError *error = nil;
    // First try to load from the bundle
    NSString *metallibPath = [[NSBundle mainBundle] pathForResource:@"default" ofType:@"metallib"];
    
    // If not found in bundle, try the current directory
    if (!metallibPath) {
        // Get the absolute path to the metallib in the current directory
        NSString *currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        metallibPath = [currentDir stringByAppendingPathComponent:@"default.metallib"];
        NSLog(@"Looking for metallib at: %@", metallibPath);
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:metallibPath]) {
            // As a last resort, try using the path relative to the executable directory
            NSString *executablePath = [[[NSProcessInfo processInfo] arguments] objectAtIndex:0];
            NSString *execDir = [executablePath stringByDeletingLastPathComponent];
            metallibPath = [execDir stringByAppendingPathComponent:@"default.metallib"];
            NSLog(@"Looking for metallib at: %@", metallibPath);
        }
    }
    
    _defaultLibrary = [_device newLibraryWithFile:metallibPath error:&error];
    if (!_defaultLibrary) {
        NSLog(@"Failed to load Metal library from %@: %@", metallibPath, error);
        
        // Fall back to compiling Shaders.metal at runtime when no metallib could be built.
        NSLog(@"Falling back to compiling Shaders.metal at runtime...");
        // SHADER_SOURCE, else Shaders.metal in the working directory, else next to the binary.
        NSString *sourcePath = getenv("SHADER_SOURCE") ? @(getenv("SHADER_SOURCE")) : @"Shaders.metal";
        if (![[NSFileManager defaultManager] fileExistsAtPath:sourcePath]) {
            NSString *executablePath = [[[NSProcessInfo processInfo] arguments] objectAtIndex:0];
            sourcePath = [[executablePath stringByDeletingLastPathComponent]
                          stringByAppendingPathComponent:@"Shaders.metal"];
        }
        NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:&error];
        _defaultLibrary = source ? [_device newLibraryWithSource:source options:nil error:&error] : nil;
        if (!_defaultLibrary) {
            NSLog(@"Failed to create default library: %@", error);
            exit(1);
        } else {
            NSLog(@"Successfully loaded default library");
            // Check if the shader functions are available
            id<MTLFunction> vertexFunction = [_defaultLibrary newFunctionWithName:@"vertexShader"];
            id<MTLFunction> fragmentFunction = [_defaultLibrary newFunctionWithName:@"fragmentShader"];
            if (!vertexFunction || !fragmentFunction) {
                NSLog(@"Warning: Could not find required shader functions in default library");
                NSLog(@"vertexShader found: %@", vertexFunction ? @"YES" : @"NO");
                NSLog(@"fragmentShader found: %@", fragmentFunction ? @"YES" : @"NO");
            }
        }
    } else {
        NSLog(@"Successfully loaded Metal library from: %@", metallibPath);
    }
    
    // Create pipeline state
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"Triangle Pipeline";
    pipelineStateDescriptor.vertexFunction = [_defaultLibrary newFunctionWithName:@"vertexShader"];
    pipelineStateDescriptor.fragmentFunction = [_defaultLibrary newFunctionWithName:@"fragmentShader"];
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = _mtkView.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    
    // Set up vertex descriptor to match our Vertex struct
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor new];
    
    // Position attribute
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[0].offset = offsetof(Vertex, position);
    vertexDescriptor.attributes[0].bufferIndex = 0;
    
    // Color attribute
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[1].offset = offsetof(Vertex, color);
    vertexDescriptor.attributes[1].bufferIndex = 0;
    
    // Define the layout of the vertex buffer
    vertexDescriptor.layouts[0].stride = sizeof(Vertex);
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    NSLog(@"Vertex struct size: %lu, Position offset: %lu, Color offset: %lu", 
          sizeof(Vertex), 
          offsetof(Vertex, position), 
          offsetof(Vertex, color));
    
    pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;
    
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline state: %@", error);
        exit(1);
    }
    
    // Create depth stencil state
    MTLDepthStencilDescriptor *depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    depthDescriptor.depthWriteEnabled = YES;
    _depthState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
    
    // Create command queue
    _commandQueue = [_device newCommandQueue];
}

- (void)_createBuffers {
    [self _generateGeometry];
    
    // Create uniform buffer
    _uniformBuffer = [_device newBufferWithLength:sizeof(Uniforms) options:MTLResourceStorageModeShared];
    _uniformBuffer.label = @"Uniforms";
}

- (void)_generateGeometry {
    if (_config.useTriangleStrips) {
        [self _generateTriangleStripGeometry];
    } else {
        [self _generateTriangleGeometry];
    }
}

- (void)_generateTriangleGeometry {
    // Generate a grid of triangles for benchmarking
    int gridSize = (int)sqrt(_config.triangleCount) + 1;
    float cellSize = 2.0f / (float)gridSize;
    
    NSMutableData *vertexData = [NSMutableData data];
    
    for (int i = 0; i < gridSize; i++) {
        for (int j = 0; j < gridSize; j++) {
            float x = -1.0f + j * cellSize;
            float z = -1.0f + i * cellSize;
            float y = 0.0f;
            
            // Triangle 1
            Vertex v1 = { { x, y, z }, { 0.0f, 0.0f, 1.0f } };
            Vertex v2 = { { x + cellSize, y, z }, { 1.0f, 0.0f, 0.0f } };
            Vertex v3 = { { x, y, z + cellSize }, { 0.0f, 1.0f, 0.0f } };
            
            [vertexData appendBytes:&v1 length:sizeof(Vertex)];
            [vertexData appendBytes:&v2 length:sizeof(Vertex)];
            [vertexData appendBytes:&v3 length:sizeof(Vertex)];
            
            // Triangle 2
            Vertex v4 = { { x + cellSize, y, z }, { 1.0f, 0.0f, 0.0f } };
            Vertex v5 = { { x + cellSize, y, z + cellSize }, { 1.0f, 1.0f, 0.0f } };
            Vertex v6 = { { x, y, z + cellSize }, { 0.0f, 1.0f, 0.0f } };
            
            [vertexData appendBytes:&v4 length:sizeof(Vertex)];
            [vertexData appendBytes:&v5 length:sizeof(Vertex)];
            [vertexData appendBytes:&v6 length:sizeof(Vertex)];
        }
    }
    
    _vertexBuffer = [_device newBufferWithLength:vertexData.length options:MTLResourceStorageModeShared];
    _vertexBuffer.label = @"Triangle Vertices";
    memcpy(_vertexBuffer.contents, vertexData.bytes, vertexData.length);
    
    _vertexCount = vertexData.length / sizeof(Vertex);
    _actualTriangleCount = _vertexCount / 3;
    _primitiveType = MTLPrimitiveTypeTriangle;
}

- (void)_generateTriangleStripGeometry {
    // Generate a grid of triangle strips
    int gridWidth = (int)sqrt(_config.triangleCount * 2) + 1;
    int gridHeight = gridWidth;
    float cellWidth = 2.0f / (float)gridWidth;
    float cellHeight = 2.0f / (float)gridHeight;
    
    NSMutableData *vertexData = [NSMutableData data];
    NSMutableData *indexData = [NSMutableData data];
    
    // Create vertices
    for (int row = 0; row <= gridHeight; row++) {
        for (int col = 0; col <= gridWidth; col++) {
            float x = -1.0f + col * cellWidth;
            float z = -1.0f + row * cellHeight;
            float y = 0.0f;
            
            float r = col / (float)gridWidth;
            float g = row / (float)gridHeight;
            float b = 1.0f - g;
            
            Vertex vertex = { { x, y, z }, { r, g, b } };
            [vertexData appendBytes:&vertex length:sizeof(Vertex)];
        }
    }
    
    // Create indices for triangle strips
    for (int row = 0; row < gridHeight; row++) {
        // For each row, create one triangle strip
        if (row > 0) {
            // Degenerate triangle to connect strips - repeat last vertex of previous row
            uint32_t degenIndex = row * (gridWidth + 1) + gridWidth;
            [indexData appendBytes:&degenIndex length:sizeof(uint32_t)];
        }
        
        for (int col = 0; col <= gridWidth; col++) {
            // For even rows, go left to right, for odd rows go right to left
            uint32_t topIndex = row * (gridWidth + 1) + col;
            uint32_t bottomIndex = (row + 1) * (gridWidth + 1) + col;
            
            [indexData appendBytes:&bottomIndex length:sizeof(uint32_t)];
            [indexData appendBytes:&topIndex length:sizeof(uint32_t)];
        }
    }
    
    _vertexBuffer = [_device newBufferWithLength:vertexData.length options:MTLResourceStorageModeShared];
    _vertexBuffer.label = @"Strip Vertices";
    memcpy(_vertexBuffer.contents, vertexData.bytes, vertexData.length);
    
    _indexBuffer = [_device newBufferWithLength:indexData.length options:MTLResourceStorageModeShared];
    _indexBuffer.label = @"Strip Indices";
    memcpy(_indexBuffer.contents, indexData.bytes, indexData.length);
    
    _vertexCount = vertexData.length / sizeof(Vertex);
    _indexCount = indexData.length / sizeof(uint32_t);
    
    // For triangle strips with n vertices, we get n-2 triangles per strip
    // For a grid with h rows, we have h strips
    // The formula is [(i-2) + 2*(s-1)] where i is total indices and s is number of strips
    _actualTriangleCount = _indexCount - 2 * gridHeight - (gridHeight - 1) * 2;
    _primitiveType = MTLPrimitiveTypeTriangleStrip;
}

- (void)updateUniforms {
    Uniforms uniforms;
    
    // Model matrix (rotate over time)
    float rotationAngle = CACurrentMediaTime();
    uniforms.modelMatrix = matrix_multiply(
        matrix_rotation(rotationAngle * 0.5, (vector_float3){ 0.0f, 1.0f, 0.0f }),
        matrix_rotation(rotationAngle * 0.3, (vector_float3){ 1.0f, 0.0f, 0.0f })
    );
    
    // View matrix (camera position)
    uniforms.viewMatrix = matrix_translation(0.0f, 0.0f, -2.5f);
    
    // Projection matrix
    float aspect = 1.0f;
    if (_drawableHeight > 0) {  // Avoid division by zero
        aspect = _drawableWidth / _drawableHeight;
    } else {
        // Fallback to view size if drawable size isn't set yet
        aspect = _mtkView.bounds.size.width / MAX(_mtkView.bounds.size.height, 1.0f);
    }
    
    uniforms.projectionMatrix = matrix_perspective(45.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
    
    // Copy to uniform buffer
    memcpy(_uniformBuffer.contents, &uniforms, sizeof(uniforms));
}

- (void)_updateStats {
    double currentTime = CACurrentMediaTime();
    double frameTime = currentTime - _config.lastTime;
    _config.lastTime = currentTime;
    
    // Add frame time to the queue
    [_config.frameTimes addObject:@(frameTime)];
    if (_config.frameTimes.count > _config.frameTimeWindowSize) {
        [_config.frameTimes removeObjectAtIndex:0];
    }
    
    _config.frameCount++;
    
    // Update the stats every half second
    static double lastOutputTime = 0;
    if (currentTime - lastOutputTime >= 0.5) {
        double elapsedTime = currentTime - lastOutputTime;
        double fps = _config.frameCount / elapsedTime;
        
        // Calculate average frame time
        double avgFrameTime = 0.0;
        for (NSNumber *time in _config.frameTimes) {
            avgFrameTime += [time doubleValue];
        }
        avgFrameTime /= _config.frameTimes.count;
        
        // Calculate triangles per second
        _config.trianglesPerSecond = _actualTriangleCount * fps;
        
        {
            static double runFrames = 0, runSeconds = 0, sinceStart = 0;
            sinceStart = -[_startTime timeIntervalSinceNow];
            if (sinceStart > 1.0 && lastOutputTime > 0) {
                runFrames += _config.frameCount;
                runSeconds += elapsedTime;
            }
            double limit = getenv("SECONDS") ? atof(getenv("SECONDS")) : 0;
            if (limit > 0 && sinceStart >= limit && runSeconds > 0) {
                double rate = _actualTriangleCount * runFrames / runSeconds;
                [gGpuLock lock];
                double gpuSeconds = gGpuSeconds;
                unsigned gpuFrames = gGpuFrames;
                [gGpuLock unlock];
                double gpuRate = gpuSeconds > 0 ? _actualTriangleCount * gpuFrames / gpuSeconds : 0;
                printf("RESULT mode=%s triangles_per_frame=%lu fps=%.1f wall_million_tri_per_s=%.0f "
                       "gpu_ms_per_frame=%.2f gpu_million_tri_per_s=%.0f drawable=%.0fx%.0f device=%s\n",
                       _config.useTriangleStrips ? "strips" : "triangles",
                       (unsigned long)_actualTriangleCount, runFrames / runSeconds, rate / 1e6,
                       gpuFrames ? gpuSeconds * 1000.0 / gpuFrames : 0, gpuRate / 1e6,
                       _drawableWidth, _drawableHeight, [_device.name UTF8String]);
                fflush(stdout);
                exit(0);
            }
        }
        // Log stats to console
        NSLog(@"Triangle Rate: %.2f million triangles/sec | FPS: %.1f | Triangles per frame: %lu | Mode: %@",
              _config.trianglesPerSecond / 1000000.0,
              fps,
              (unsigned long)_actualTriangleCount,
              (_config.useTriangleStrips ? @"STRIPS" : @"TRIANGLES"));
        
        // Update window title if stats are enabled
        if (_config.showStats) {
            NSString *title = [NSString stringWithFormat:@"Metal Benchmark | FPS: %.1f | Frame Time: %.2fms | Triangles: %lu | Tri Rate: %.2fM/s | Mode: %@ | Render: %@",
                               fps,
                               avgFrameTime * 1000.0,
                               (unsigned long)_actualTriangleCount,
                               _config.trianglesPerSecond / 1000000.0,
                               (_config.useTriangleStrips ? @"STRIPS" : @"TRIANGLES"),
                               (_config.wireframeMode ? @"WIREFRAME" : @"SOLID")];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [_mtkView.window setTitle:title];
            });
        }
        
        lastOutputTime = currentTime;
        _config.frameCount = 0;
    }
}

// MARK: - MTKViewDelegate methods
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // Handle drawable size change
    NSLog(@"Drawable size changed to: %.1f x %.1f", size.width, size.height);
    
    // Store current drawable size for aspect ratio calculation
    _drawableWidth = size.width;
    _drawableHeight = size.height;
}

- (void)drawInMTKView:(MTKView *)view {
    // Update uniform buffer with new transformation matrices
    [self updateUniforms];
    
    // Create a command buffer
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Render Command";
    
    // Print debug stats every few frames
    static int frameCounter = 0;
    if (frameCounter++ % 60 == 0) {  // Print once every ~60 frames
        NSLog(@"Debug info - Frame %d", frameCounter);
        NSLog(@"  Vertex count: %lu, Triangle count: %lu, Strip mode: %@",
              (unsigned long)_vertexCount,
              (unsigned long)_actualTriangleCount,
              _config.useTriangleStrips ? @"YES" : @"NO");
        
        NSLog(@"  Vertex buffer: %@, length: %lu", _vertexBuffer, (unsigned long)_vertexBuffer.length);
        if (_config.useTriangleStrips) {
            NSLog(@"  Index buffer: %@, length: %lu", _indexBuffer, (unsigned long)_indexBuffer.length);
        }
        
        NSLog(@"  View drawable: %@, size: %.1f x %.1f", 
              view.currentDrawable, 
              view.drawableSize.width, 
              view.drawableSize.height);
        
        // Check if the Metal device is operating properly
        NSLog(@"  Metal device: %@, name: %@", _device, _device.name);
    }
    
    // Set up the render pass
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor != nil) {
        // Set background color (dark teal)
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.2, 0.2, 1.0);
        
        // Create encoder
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"Triangle Render Encoder";
        
        // Set render states
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setDepthStencilState:_depthState];
        
        // Set wireframe mode if enabled
        if (_config.wireframeMode) {
            [renderEncoder setTriangleFillMode:MTLTriangleFillModeLines];
        } else {
            [renderEncoder setTriangleFillMode:MTLTriangleFillModeFill];
        }
        
        // Set vertex buffers
        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
        [renderEncoder setVertexBuffer:_uniformBuffer offset:0 atIndex:1];
        
        // Draw triangles
        if (_config.useTriangleStrips) {
            // Make sure we have indices before trying to draw
            if (_indexBuffer && _indexCount > 0) {
                [renderEncoder drawIndexedPrimitives:_primitiveType
                                         indexCount:_indexCount
                                          indexType:MTLIndexTypeUInt32
                                        indexBuffer:_indexBuffer
                                  indexBufferOffset:0];
            } else {
                NSLog(@"Warning: Attempted to draw indexed primitives but no index buffer or count is set");
            }
        } else {
            // Make sure we have vertices before trying to draw
            if (_vertexBuffer && _vertexCount > 0) {
                [renderEncoder drawPrimitives:_primitiveType vertexStart:0 vertexCount:_vertexCount];
            } else {
                NSLog(@"Warning: Attempted to draw primitives but no vertex buffer or count is set");
            }
        }
        
        // End encoding
        [renderEncoder endEncoding];
        
        // Present drawable
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    // Commit the command buffer
    if (-[_startTime timeIntervalSinceNow] > 1.0) {
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> finished) {
            [gGpuLock lock];
            gGpuSeconds += finished.GPUEndTime - finished.GPUStartTime;
            gGpuFrames += 1;
            [gGpuLock unlock];
        }];
    }
    [commandBuffer commit];
    
    // Update benchmark stats after command is scheduled
    [self _updateStats];
}

- (void)increaseTriangleCount {
    _config.triangleCount = (NSUInteger)(_config.triangleCount * 1.5);
    NSLog(@"Triangle count: %lu", (unsigned long)_config.triangleCount);
    [self _generateGeometry];
}

- (void)decreaseTriangleCount {
    _config.triangleCount = MAX(100, (NSUInteger)(_config.triangleCount / 1.5));
    NSLog(@"Triangle count: %lu", (unsigned long)_config.triangleCount);
    [self _generateGeometry];
}

- (void)toggleTriangleStrips {
    _config.useTriangleStrips = !_config.useTriangleStrips;
    NSLog(@"Mode: %@", (_config.useTriangleStrips ? @"STRIPS" : @"TRIANGLES"));
    [self _generateGeometry];
}

- (void)toggleWireframeMode {
    _config.wireframeMode = !_config.wireframeMode;
    NSLog(@"Render mode: %@", (_config.wireframeMode ? @"WIREFRAME" : @"SOLID"));
}

- (void)toggleStatsDisplay {
    _config.showStats = !_config.showStats;
    if (!_config.showStats) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_mtkView.window setTitle:@"Metal Performance Benchmark"];
        });
    }
}

@end

// MARK: - MetalView Implementation

@implementation MetalView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    switch ([event.characters characterAtIndex:0]) {
        case 27: // ESC
            [NSApp terminate:self];
            break;
        case 'w':
        case 'W':
            [self.renderer toggleWireframeMode];
            break;
        case 's':
        case 'S':
            [self.renderer toggleTriangleStrips];
            break;
        case 'd':
        case 'D':
            [self.renderer toggleStatsDisplay];
            break;
        case NSUpArrowFunctionKey:
            [self.renderer increaseTriangleCount];
            break;
        case NSDownArrowFunctionKey:
            [self.renderer decreaseTriangleCount];
            break;
    }
}

@end

// MARK: - AppDelegate Implementation

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Create window
    NSRect frame = NSMakeRect(0, 0, 800, 600);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
    
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Metal Performance Benchmark";
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    
    // Create Metal view
    self.metalView = [[MetalView alloc] initWithFrame:frame];
    self.metalView.device = MTLCreateSystemDefaultDevice();
    self.metalView.clearColor = MTLClearColorMake(0.1, 0.2, 0.2, 1.0);
    self.metalView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    self.metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalView.sampleCount = 1;
    
    // Configure drawing settings
    self.metalView.enableSetNeedsDisplay = NO;
    self.metalView.paused = NO; // Make sure view is not paused
    self.metalView.framebufferOnly = YES; // Optimize performance
    if (getenv("NOVSYNC")) {
        self.metalView.preferredFramesPerSecond = 1000;
        ((CAMetalLayer *)self.metalView.layer).displaySyncEnabled = NO;
    }
    
    // Create renderer
    self.metalView.renderer = [[MetalRenderer alloc] initWithMetalView:self.metalView];
    self.metalView.delegate = (id<MTKViewDelegate>)self.metalView.renderer;
    
    // Set window content
    self.window.contentView = self.metalView;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

@end

// MARK: - Main

int main(int argc, const char * argv[]) {
    gGpuLock = [[NSLock alloc] init];
    @autoreleasepool {
        AppDelegate *appDelegate = [[AppDelegate alloc] init];
        [NSApplication sharedApplication].delegate = appDelegate;
        [NSApp run];
    }
    return 0;
}
