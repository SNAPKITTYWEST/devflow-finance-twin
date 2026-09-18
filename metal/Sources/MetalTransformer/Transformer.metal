#include <metal_stdlib>
using namespace metal;

struct ModelDims { uint hidden, intermediate, heads, kv_heads, head_dim, vocab, context; };
struct QuantMatrix { device const uchar *weights; device const half *scales; uint rows, cols; };

inline float deq_i4(device const uchar *w, device const half *s, uint row, uint col, uint cols) {
    uchar packed = w[row * ((cols + 1) >> 1) + (col >> 1)];
    int nibble = ((col & 1) ? (packed >> 4) : (packed & 15));
    int signed_nibble = nibble - (nibble >= 8 ? 16 : 0);
    return float(signed_nibble) * float(s[row]);
}

kernel void embedding(device const half *table [[buffer(0)]], device const uint *token [[buffer(1)]], device half *out [[buffer(2)]], constant ModelDims &d [[buffer(3)]], uint i [[thread_position_in_grid]]) {
    if (i >= d.hidden) return;
    out[i] = table[token[0] * d.hidden + i];
}

kernel void rmsnorm(device const half *x [[buffer(0)]], device const half *weight [[buffer(1)]], device half *y [[buffer(2)]], constant ModelDims &d [[buffer(3)]], float epsilon [[buffer(4)]], uint i [[thread_position_in_grid]]) {
    if (i >= d.hidden) return;
    threadgroup float partial[32]; uint lane = i & 31, group = i >> 5;
    float sum = 0.0f;
    for (uint j = i; j < d.hidden; j += 32) { float v = float(x[j]); sum += v * v; }
    partial[lane] = sum; threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane == 0) { float total = 0.0f; for (uint j=0;j<32;j++) total += partial[j]; partial[0] = rsqrt(total / float(d.hidden) + epsilon); }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    y[i] = half(float(x[i]) * partial[0] * float(weight[i]));
}

kernel void rope(device half *q [[buffer(0)]], device half *k [[buffer(1)]], constant ModelDims &d [[buffer(2)]], constant uint &position [[buffer(3)]], uint i [[thread_position_in_grid]]) {
    uint total = d.heads * d.head_dim; if (i >= total || (i & 1)) return;
    uint pair = i >> 1; float inv = pow(10000.0f, -float(2 * (pair % (d.head_dim/2))) / float(d.head_dim));
    float angle = float(position) * inv; float c = cos(angle), s = sin(angle);
    float qa=float(q[i]), qb=float(q[i+1]), ka=float(k[pair*2]), kb=float(k[pair*2+1]);
    q[i]=half(qa*c-qb*s); q[i+1]=half(qa*s+qb*c); k[pair*2]=half(ka*c-kb*s); k[pair*2+1]=half(ka*s+kb*c);
}

kernel void qmatvec_i4(device const uchar *weights [[buffer(0)]], device const half *scales [[buffer(1)]], device const half *x [[buffer(2)]], device half *y [[buffer(3)]], constant uint2 &shape [[buffer(4)]], uint row [[thread_position_in_grid]]) {
    if (row >= shape.x) return; float acc=0.0f; uint cols=shape.y;
    for (uint c=0;c<cols;c++) acc += deq_i4(weights, scales, row, c, cols) * float(x[c]);
    y[row]=half(acc);
}

kernel void qkv_projection_i4(device const uchar *weights [[buffer(0)]], device const half *scales [[buffer(1)]], device const half *x [[buffer(2)]], device half *qkv [[buffer(3)]], constant uint2 &shape [[buffer(4)]], uint row [[thread_position_in_grid]]) {
    if (row >= shape.x) return; float acc=0.0f;
    for (uint c=0;c<shape.y;c++) acc += deq_i4(weights, scales, row, c, shape.y) * float(x[c]);
    qkv[row]=half(acc);
}

kernel void attention_scores(device const half *q [[buffer(0)]], device const half *kcache [[buffer(1)]], device half *scores [[buffer(2)]], constant uint4 &p [[buffer(3)]], uint i [[thread_position_in_grid]]) {
    uint query=p.x, key=p.y, head=p.z, dim=p.w; if (i >= query * p.z) return;
    uint h=i % head, t=i / head; if (t > query) { scores[i]=half(-INFINITY); return; }
    float dot=0.0f; for(uint j=0;j<dim;j++) dot += float(q[h*dim+j]) * float(kcache[(t*head+h)*dim+j]);
    scores[i]=half(dot * rsqrt(float(dim)));
}

kernel void causal_softmax(device half *scores [[buffer(0)]], constant uint2 &shape [[buffer(1)]], uint row [[thread_position_in_grid]]) {
    if(row>=shape.x) return; uint n=shape.y; float mx=-INFINITY;
    for(uint j=0;j<n;j++) mx=max(mx,float(scores[row*n+j])); float z=0.0f;
    for(uint j=0;j<n;j++) { float v=exp(float(scores[row*n+j])-mx); scores[row*n+j]=half(v); z+=v; }
    float inv=1.0f/max(z,1.0e-20f); for(uint j=0;j<n;j++) scores[row*n+j]=half(float(scores[row*n+j])*inv);
}

kernel void attention_times_v(device const half *scores [[buffer(0)]], device const half *vcache [[buffer(1)]], device half *out [[buffer(2)]], constant uint4 &p [[buffer(3)]], uint i [[thread_position_in_grid]]) {
    uint head=p.x, dim=p.y, length=p.z; if(i>=head*dim) return; uint h=i/dim, d=i%dim; float acc=0.0f;
    for(uint t=0;t<length;t++) acc += float(scores[h*length+t]) * float(vcache[(t*head+h)*dim+d]); out[i]=half(acc);
}

kernel void swiglu(device const half *x [[buffer(0)]], device const half *gate [[buffer(1)]], device half *y [[buffer(2)]], uint n [[buffer(3)]], uint i [[thread_position_in_grid]]) {
    if(i>=n) return; float g=float(gate[i]); float silu=g/(1.0f+exp(-g)); y[i]=half(silu*float(x[i]));
}

kernel void residual_add(device const half *a [[buffer(0)]], device const half *b [[buffer(1)]], device half *out [[buffer(2)]], uint n [[buffer(3)]], uint i [[thread_position_in_grid]]) {
    if(i<n) out[i]=half(float(a[i])+float(b[i]));
}

kernel void output_projection_i4(device const uchar *weights [[buffer(0)]], device const half *scales [[buffer(1)]], device const half *x [[buffer(2)]], device half *logits [[buffer(3)]], constant uint2 &shape [[buffer(4)]], uint row [[thread_position_in_grid]]) {
    if(row>=shape.x) return; float acc=0.0f; for(uint c=0;c<shape.y;c++) acc+=deq_i4(weights,scales,row,c,shape.y)*float(x[c]); logits[row]=half(acc);
}

kernel void copy_kv(device const half *k [[buffer(0)]], device const half *v [[buffer(1)]], device half *kcache [[buffer(2)]], device half *vcache [[buffer(3)]], constant uint4 &p [[buffer(4)]], uint i [[thread_position_in_grid]]) {
    uint n=p.x*p.y; if(i>=n) return; kcache[p.z*n+i]=k[i]; vcache[p.z*n+i]=v[i];
}

kernel void final_normalization(device const half *x [[buffer(0)]], device const half *weight [[buffer(1)]], device half *y [[buffer(2)]], constant ModelDims &d [[buffer(3)]], float eps [[buffer(4)]], uint i [[thread_position_in_grid]]) {
    if(i>=d.hidden) return; float sum=0.0f; for(uint j=0;j<d.hidden;j++){float v=float(x[j]);sum+=v*v;} y[i]=half(float(x[i])*rsqrt(sum/float(d.hidden)+eps)*float(weight[i]));
}
