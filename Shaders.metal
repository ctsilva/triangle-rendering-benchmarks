#include <metal_stdlib>
using namespace metal;

// Structures shared between Metal shaders and C code
struct Vertex {
    float3 position [[attribute(0)]];
    float3 color [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 color;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

// Vertex shader
vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                             constant Vertex *vertices [[buffer(0)]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    
    float4 position = float4(vertices[vertexID].position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    out.color = vertices[vertexID].color;
    
    return out;
}

// Fragment shader
fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}
