#include <cuda_runtime.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 900)
#define VSM_SM90 1
#else
#define VSM_SM90 0
#endif

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef int i32;
typedef float f32;

enum : u8 {
    VSM_NOP       = 0x00,
    VSM_LOAD      = 0x01,
    VSM_STORE     = 0x02,
    VSM_MOVE      = 0x03,
    VSM_AND       = 0x04,
    VSM_OR        = 0x05,
    VSM_XOR       = 0x06,
    VSM_NOT       = 0x07,
    VSM_EQ        = 0x08,
    VSM_NEQ       = 0x09,
    VSM_BIND      = 0x0A,
    VSM_UNBIND    = 0x0B,
    VSM_ASSERT    = 0x0C,
    VSM_REJECT    = 0x0D,
    VSM_PROVE     = 0x0E,
    VSM_VERIFY    = 0x0F,
    VSM_ROUTE     = 0x10,
    VSM_FORK      = 0x11,
    VSM_JOIN      = 0x12,
    VSM_SEED      = 0x13,
    VSM_SPRING    = 0x14,
    VSM_PROPAGATE = 0x15,
    VSM_COMMIT    = 0x16,
    VSM_ROLLBACK  = 0x17,
    VSM_HALT      = 0xFF
};

enum : u32 {
    VSM_OK                  = 0,
    VSM_INVALID_STATE       = 1,
    VSM_INVALID_PARAMETER   = 2,
    VSM_INVALID_OPCODE      = 3,
    VSM_MEMORY_FAILURE      = 4,
    VSM_CONSTRAINT_FAILURE  = 5,
    VSM_PROOF_FAILURE       = 6,
    VSM_PROPAGATION_FAILURE = 7,
    VSM_CONFLICT            = 8,
    VSM_HALTED              = 9
};

struct VSMParameter {
    u64 id;
    u64 semantic_id;
    u64 signature;
    u32 dimension;
    u32 element_type;
    u64 offset;
    u64 version;
    u64 provenance;
    u32 validity;
    u32 constraints;
};

struct VSMInstruction {
    u8  opcode;
    u8  rd;
    u8  rs1;
    u8  rs2;
    u32 immediate;
    u64 operand;
};

struct VSMRegisters {
    u64 r[16];
    u64 sem;
    u64 ctx;
    u64 bind;
    u64 proof;
    u64 state;
    u64 mem;
    u64 route;
    u64 seed;
    u64 valid;
    u64 error;
    u64 history;
};

struct VSMState {
    u64 state_id;
    u64 parent_id;
    u64 pc;
    u64 semantic;
    u64 seed;
    u64 flags;
    u32 validity;
    u32 status;
};

struct VSMSpringboard {
    u64 source;
    u64 seed;
    u64 constraints;
    u64 transition;
    u64 target;
    u64 validation;
    u64 provenance;
    u32 status;
    u32 reserved;
};

struct VSMConstraint {
    u64 id;
    u64 predicate;
    u64 scope;
    u64 priority;
    u64 dependencies;
    u32 validity;
    u32 failure;
};

struct VSMFeature {
    u64 feature_id;
    u64 source_id;
    u32 layer;
    u32 position;
    f32 value;
    u32 validity;
    u64 provenance;
    u32 constraints;
    u32 reserved;
};

__device__ __forceinline__
u64 vsm_mix(u64 x)
{
    x ^= x >> 30;
    x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27;
    x *= 0x94d049bb133111ebULL;
    x ^= x >> 31;
    return x;
}

__device__ __forceinline__
u64 vsm_rotl64(u64 x, u32 n)
{
    n &= 63;
    return (x << n) | (x >> ((64 - n) & 63));
}

__device__ __forceinline__
u64 vsm_rotr64(u64 x, u32 n)
{
    n &= 63;
    return (x >> n) | (x << ((64 - n) & 63));
}

__device__ __forceinline__
u64 vsm_binary_op(u8 opcode, u64 a, u64 b)
{
    switch (opcode) {
        case VSM_AND: return a & b;
        case VSM_OR:  return a | b;
        case VSM_XOR: return a ^ b;
        case VSM_NOT: return ~a;
        case VSM_EQ:  return a == b;
        case VSM_NEQ: return a != b;
        default:      return 0;
    }
}

__device__ __forceinline__
u32 vsm_instruction(
    const VSMInstruction& ins,
    VSMRegisters&         g)
{
    u64 a = g.r[ins.rs1];
    u64 b = g.r[ins.rs2];

    switch (ins.opcode) {

        case VSM_NOP:
            return VSM_OK;

        case VSM_LOAD:
            g.r[ins.rd] = g.r[ins.rs1] + ins.immediate;
            return VSM_OK;

        case VSM_STORE:
            g.r[ins.rd] = g.r[ins.rs1];
            return VSM_OK;

        case VSM_MOVE:
            g.r[ins.rd] = a;
            return VSM_OK;

        case VSM_AND:
        case VSM_OR:
        case VSM_XOR:
        case VSM_EQ:
        case VSM_NEQ:
            g.r[ins.rd] = vsm_binary_op(ins.opcode, a, b);
            return VSM_OK;

        case VSM_NOT:
            g.r[ins.rd] = ~a;
            return VSM_OK;

        case VSM_BIND:
            g.bind = a ^ b;
            g.r[ins.rd] = g.bind;
            return VSM_OK;

        case VSM_UNBIND:
            g.r[ins.rd] = a ^ g.bind;
            return VSM_OK;

        case VSM_ASSERT:
            return a ? VSM_OK : VSM_CONSTRAINT_FAILURE;

        case VSM_REJECT:
            return VSM_CONFLICT;

        case VSM_PROVE:
            g.proof = vsm_mix(a ^ b);
            g.r[ins.rd] = g.proof;
            return VSM_OK;

        case VSM_VERIFY:
            g.valid = g.proof == vsm_mix(a ^ b);
            g.r[ins.rd] = g.valid;
            return g.valid ? VSM_OK : VSM_PROOF_FAILURE;

        case VSM_ROUTE:
            g.route = vsm_mix(a ^ g.ctx ^ b);
            g.r[ins.rd] = g.route;
            return VSM_OK;

        case VSM_FORK:
            g.history = g.state;
            g.state = vsm_mix(g.state ^ a);
            g.r[ins.rd] = g.state;
            return VSM_OK;

        case VSM_JOIN:
            g.state = vsm_mix(g.state ^ a ^ b);
            g.r[ins.rd] = g.state;
            return VSM_OK;

        case VSM_SEED:
            g.seed = vsm_mix(a);
            g.r[ins.rd] = g.seed;
            return VSM_OK;

        case VSM_SPRING:
            g.state =
                vsm_mix(
                    g.state ^
                    g.seed  ^
                    a       ^
                    ins.operand);
            g.r[ins.rd] = g.state;
            return VSM_OK;

        case VSM_PROPAGATE:
            g.state =
                vsm_mix(
                    g.state ^
                    g.seed  ^
                    g.route);
            g.r[ins.rd] = g.state;
            return VSM_OK;

        case VSM_COMMIT:
            g.history = g.state;
            return VSM_OK;

        case VSM_ROLLBACK:
            g.state = g.history;
            return VSM_OK;

        case VSM_HALT:
            return VSM_HALTED;

        default:
            return VSM_INVALID_OPCODE;
    }
}

__global__
void vsm_isa_kernel(
    const VSMInstruction* __restrict__ program,
    u32                                program_count,
    VSMRegisters*         __restrict__ registers,
    u32*                  __restrict__ status,
    u32                                instances)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= instances)
        return;

    VSMRegisters g = registers[tid];
    u32 result = VSM_OK;

    for (u32 pc = 0; pc < program_count; ++pc) {
        result = vsm_instruction(program[pc], g);

        if (result != VSM_OK)
            break;
    }

    g.error = result;
    registers[tid] = g;
    status[tid] = result;
}

__global__
void vsm_embedding_lookup_u64(
    const u64* __restrict__ semantic_ids,
    const u64* __restrict__ table,
    u64*       __restrict__ output,
    u32                     vocabulary,
    u32                     width)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    u32 element_count =
        vocabulary * width;

    if (tid >= element_count)
        return;

    u32 token   = tid / width;
    u32 element = tid % width;

    u64 semantic = semantic_ids[token];
    u64 row      = semantic % vocabulary;

    output[tid] = table[row * width + element];
}

__global__
void vsm_embedding_xor(
    const u64* __restrict__ input,
    const u64* __restrict__ mask,
    u64*       __restrict__ output,
    u32                     count)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    output[tid] = input[tid] ^ mask[tid];
}

__global__
void vsm_embedding_rotate(
    const u64* __restrict__ input,
    u64*       __restrict__ output,
    u32                     count,
    u32                     rotation)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    output[tid] = vsm_rotl64(input[tid], rotation);
}

__global__
void vsm_embedding_mix(
    const u64* __restrict__ input,
    u64*       __restrict__ output,
    u32                     count)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    output[tid] = vsm_mix(input[tid]);
}

__global__
void vsm_binary_feature_map(
    const u64*   __restrict__ semantic,
    VSMFeature*  __restrict__ feature,
    u32                       count,
    u32                       layer)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    u64 x = semantic[tid];

    VSMFeature f{};
    f.feature_id  = ((u64)layer << 32) | tid;
    f.source_id   = x;
    f.layer       = layer;
    f.position    = tid;
    f.value       = (f32)((x >> 32) & 0xffffffffULL);
    f.validity    = 1;
    f.provenance  = vsm_mix(x);
    f.constraints = 0;

    feature[tid] = f;
}

__global__
void vsm_relu(
    f32* __restrict__ data,
    u32               count)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    f32 x = data[tid];
    data[tid] = x > 0.0f ? x : 0.0f;
}

__global__
void vsm_maxpool2x2(
    const f32* __restrict__ input,
    f32*       __restrict__ output,
    u32                     channels,
    u32                     height,
    u32                     width)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    u32 out_h = height >> 1;
    u32 out_w = width  >> 1;

    u64 total = (u64)channels * out_h * out_w;

    if ((u64)tid >= total)
        return;

    u32 ox = tid % out_w;
    u32 oy = (tid / out_w) % out_h;
    u32 c  = tid / (out_w * out_h);

    u32 ix = ox << 1;
    u32 iy = oy << 1;

    u64 p0 = ((u64)c * height + iy) * width + ix;
    u64 p1 = p0 + 1;
    u64 p2 = p0 + width;
    u64 p3 = p2 + 1;

    f32 a = input[p0];
    f32 b = input[p1];
    f32 d = input[p2];
    f32 e = input[p3];

    f32 m = a > b ? a : b;
    m = m > d ? m : d;
    m = m > e ? m : e;

    output[tid] = m;
}

__global__
void vsm_conv2d(
    const f32* __restrict__ input,
    const f32* __restrict__ kernel,
    const f32* __restrict__ bias,
    f32*       __restrict__ output,
    u32                     in_channels,
    u32                     out_channels,
    u32                     height,
    u32                     width,
    u32                     kernel_size,
    u32                     stride)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    u32 out_h = (height - kernel_size) / stride + 1;
    u32 out_w = (width  - kernel_size) / stride + 1;

    u64 total = (u64)out_channels * out_h * out_w;

    if ((u64)tid >= total)
        return;

    u32 ox = tid % out_w;
    u32 oy = (tid / out_w) % out_h;
    u32 oc = tid / (out_w * out_h);

    f32 acc = bias ? bias[oc] : 0.0f;

    for (u32 ic = 0; ic < in_channels; ++ic) {
        for (u32 ky = 0; ky < kernel_size; ++ky) {
            for (u32 kx = 0; kx < kernel_size; ++kx) {
                u64 input_index =
                    ((u64)ic * height + oy * stride + ky)
                    * width + ox * stride + kx;

                u64 kernel_index =
                    (((u64)oc * in_channels + ic)
                    * kernel_size + ky)
                    * kernel_size + kx;

                acc += input[input_index] * kernel[kernel_index];
            }
        }
    }

    output[tid] = acc > 0.0f ? acc : 0.0f;
}

__global__
void vsm_fc(
    const f32* __restrict__ input,
    const f32* __restrict__ weights,
    const f32* __restrict__ bias,
    f32*       __restrict__ output,
    u32                     input_dim,
    u32                     output_dim)
{
    u32 o =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (o >= output_dim)
        return;

    f32 acc = bias ? bias[o] : 0.0f;

    const f32* w = weights + (u64)o * input_dim;

    for (u32 i = 0; i < input_dim; ++i)
        acc += input[i] * w[i];

    output[o] = acc;
}

__global__
void vsm_springboard(
    const VSMSpringboard* __restrict__ input,
    u64*                  __restrict__ output,
    u32*                  __restrict__ status,
    u32                               count)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    VSMSpringboard s = input[tid];

    if (s.source == 0 ||
        s.seed == 0   ||
        s.transition == 0) {

        output[tid] = 0;
        status[tid] = VSM_PROPAGATION_FAILURE;
        return;
    }

    u64 state =
        s.source      ^
        s.seed        ^
        s.constraints ^
        s.transition;

    state = vsm_mix(state);

    output[tid] = state;
    status[tid] = VSM_OK;
}

__global__
void vsm_constraint_kernel(
    const VSMConstraint* __restrict__ constraints,
    const u64*           __restrict__ states,
    u32*                 __restrict__ results,
    u32                               constraint_count,
    u32                               state_count)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= state_count)
        return;

    u64 state  = states[tid];
    u32 result = VSM_OK;

    for (u32 i = 0; i < constraint_count; ++i) {
        VSMConstraint c = constraints[i];

        if (c.validity == 0) {
            result = VSM_CONSTRAINT_FAILURE;
            break;
        }

        if ((state & c.predicate) !=
            (c.scope & c.predicate)) {
            result = VSM_CONSTRAINT_FAILURE;
            break;
        }
    }

    results[tid] = result;
}

__global__
void vsm_provenance(
    const u64* __restrict__ states,
    u64*       __restrict__ provenance,
    u32                     count)
{
    u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    provenance[tid] =
        vsm_mix(states[tid] ^ ((u64)tid << 32));
}

__global__
void vsm_semantic_reduce(
    const u64* __restrict__ input,
    u64*       __restrict__ output,
    u32                     count)
{
    u32 tid  = blockIdx.x * blockDim.x + threadIdx.x;
    u32 lane = threadIdx.x & 31;

    u64 value = tid < count ? input[tid] : 0;

    for (u32 offset = 16; offset != 0; offset >>= 1)
        value ^= __shfl_xor_sync(0xffffffff, value, offset);

    if (lane == 0)
        output[blockIdx.x] = value;
}

extern "C"
cudaError_t vsm_launch_isa(
    const VSMInstruction* program,
    u32                   program_count,
    VSMRegisters*         registers,
    u32*                  status,
    u32                   instances,
    cudaStream_t          stream)
{
    dim3 block(128);
    dim3 grid((instances + block.x - 1) / block.x);

    vsm_isa_kernel<<<grid, block, 0, stream>>>(
        program, program_count, registers, status, instances);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_embedding(
    const u64*   semantic_ids,
    const u64*   table,
    u64*         output,
    u32          vocabulary,
    u32          width,
    cudaStream_t stream)
{
    u32 elements = vocabulary * width;
    dim3 block(256);
    dim3 grid((elements + 255) / 256);

    vsm_embedding_lookup_u64<<<grid, block, 0, stream>>>(
        semantic_ids, table, output, vocabulary, width);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_conv(
    const f32*   input,
    const f32*   kernel,
    const f32*   bias,
    f32*         output,
    u32          in_channels,
    u32          out_channels,
    u32          height,
    u32          width,
    u32          kernel_size,
    u32          stride,
    cudaStream_t stream)
{
    u32 out_h = (height - kernel_size) / stride + 1;
    u32 out_w = (width  - kernel_size) / stride + 1;
    u64 total = (u64)out_channels * out_h * out_w;

    dim3 block(256);
    dim3 grid((u32)((total + 255) / 256));

    vsm_conv2d<<<grid, block, 0, stream>>>(
        input, kernel, bias, output,
        in_channels, out_channels,
        height, width, kernel_size, stride);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_pool(
    const f32*   input,
    f32*         output,
    u32          channels,
    u32          height,
    u32          width,
    cudaStream_t stream)
{
    u64 total = (u64)channels * (height >> 1) * (width >> 1);
    dim3 block(256);
    dim3 grid((u32)((total + 255) / 256));

    vsm_maxpool2x2<<<grid, block, 0, stream>>>(
        input, output, channels, height, width);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_springboard(
    const VSMSpringboard* springboards,
    u64*                  output,
    u32*                  status,
    u32                   count,
    cudaStream_t          stream)
{
    dim3 block(256);
    dim3 grid((count + 255) / 256);

    vsm_springboard<<<grid, block, 0, stream>>>(
        springboards, output, status, count);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_constraints(
    const VSMConstraint* constraints,
    const u64*           states,
    u32*                 results,
    u32                  constraint_count,
    u32                  state_count,
    cudaStream_t         stream)
{
    dim3 block(256);
    dim3 grid((state_count + 255) / 256);

    vsm_constraint_kernel<<<grid, block, 0, stream>>>(
        constraints, states, results,
        constraint_count, state_count);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_provenance(
    const u64*   states,
    u64*         provenance,
    u32          count,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid((count + 255) / 256);

    vsm_provenance<<<grid, block, 0, stream>>>(
        states, provenance, count);

    return cudaGetLastError();
}

int main()
{
    int device = 0;

    cudaDeviceProp prop{};

    cudaError_t e =
        cudaGetDeviceProperties(&prop, device);

    if (e != cudaSuccess)
        return 1;

    printf(
        "device=%s\n"
        "compute_capability=%d.%d\n"
        "global_memory=%llu\n"
        "multiprocessors=%d\n"
        "warp_size=%d\n",
        prop.name,
        prop.major,
        prop.minor,
        (unsigned long long)prop.totalGlobalMem,
        prop.multiProcessorCount,
        prop.warpSize);

    cudaSetDevice(device);

    cudaStream_t stream{};

    e = cudaStreamCreate(&stream);

    if (e != cudaSuccess)
        return 1;

    e = cudaStreamSynchronize(stream);

    cudaStreamDestroy(stream);

    return e == cudaSuccess ? 0 : 1;
}

/*
nvcc -O3 -arch=sm_90 -Xptxas=-v -o vsm2500 vsm2500_isa_kernel.cu

nvcc -O3 -arch=sm_90 -ptx \
    vsm2500_isa_kernel.cu \
    -o vsm2500.ptx

nvcc -O3 -arch=sm_90 -cubin \
    vsm2500_isa_kernel.cu \
    -o vsm2500.cubin

cuobjdump --dump-ptx  vsm2500.cubin
cuobjdump --dump-sass vsm2500.cubin
nvdisasm vsm2500.cubin > vsm2500.sass

nvcc -O3 -arch=sm_90 -Xptxas=-v \
    -cubin vsm2500_isa_kernel.cu \
    -o vsm2500.cubin

nvidia-smi
./vsm2500
*/
