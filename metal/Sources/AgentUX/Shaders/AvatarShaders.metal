#include <metal_stdlib>
using namespace metal;

struct AvatarParticle {
    float2 position;
    float2 velocity;
    float4 color;
    float life;
};

struct DylanDirective {
    float2 target;
    float2 frame_origin;
    float2 frame_size;
    float glass;
    uint op;
    uint agent_count;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float point_size [[point_size]];
};

kernel void update_avatar_particles(
    device AvatarParticle* particles [[buffer(0)]],
    constant DylanDirective& d [[buffer(1)]],
    constant float& dt [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    AvatarParticle p = particles[id];
    float2 dir = d.target - p.position;
    float dist = length(dir);
    if (dist > 0.001f) {
        p.velocity += (dir / (dist + 0.08f)) * 0.045f;
    }
    if (d.op == 0x0Du) {
        float2 c = d.frame_origin + d.frame_size * 0.5f;
        float2 to = c - p.position;
        p.velocity += to * 0.01f;
    }
    p.velocity *= 0.91f;
    p.position += p.velocity * (dt * 60.0f);
    p.life -= 0.004f;
    if (p.life <= 0.0f) {
        float rnd = fract(sin(float(id) * 43758.5453f));
        p.life = 1.0f;
        p.position = d.target + float2(rnd - 0.5f, fract(rnd * 13.0f) - 0.5f) * 0.12f;
        p.velocity = float2(0.0f);
    }
    float glow = saturate(d.glass);
    p.color = float4(0.35f + glow * 0.4f, 0.85f, 1.0f, 0.35f + p.life * 0.5f);
    particles[id] = p;
}

vertex VertexOut avatar_vertex(
    const device AvatarParticle* particles [[buffer(0)]],
    uint vid [[vertex_id]]
) {
    AvatarParticle p = particles[vid];
    VertexOut o;
    o.position = float4(p.position * 2.0f - 1.0f, 0.0f, 1.0f);
    o.color = p.color;
    o.point_size = 3.0f + p.life * 4.0f;
    return o;
}

fragment float4 avatar_fragment(VertexOut in [[stage_in]], float2 pc [[point_coord]]) {
    float2 d = pc - float2(0.5f);
    float r = length(d);
    if (r > 0.5f) discard_fragment();
    float a = smoothstep(0.5f, 0.15f, r) * in.color.a;
    return float4(in.color.rgb, a);
}

fragment float4 glass_fragment(
    VertexOut in [[stage_in]],
    constant DylanDirective& d [[buffer(1)]],
    float2 pc [[point_coord]]
) {
    float2 uv = pc;
    float ripple = sin(length(uv - float2(0.5f)) * 24.0f - d.glass * 6.0f) * 0.04f;
    float3 tint = float3(0.72f, 0.84f, 0.95f) + ripple;
    return float4(tint, 0.22f + d.glass * 0.25f);
}
