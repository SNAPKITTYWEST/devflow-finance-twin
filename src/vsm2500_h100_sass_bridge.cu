#ifndef VSM2500_H100_SASS_BRIDGE_CU
#define VSM2500_H100_SASS_BRIDGE_CU

#include <cuda.h>
#include <cuda_runtime.h>
#include <stdint.h>
#include <stddef.h>

#define VSM_VERSION 2500u
#define VSM_SM90 0x90u
#define VSM_WARP 32u
#define VSM_WORD_BITS 64u

typedef uint8_t vsm_u8;
typedef uint16_t vsm_u16;
typedef uint32_t vsm_u32;
typedef uint64_t vsm_u64;
typedef int32_t vsm_i32;
typedef float vsm_f32;

enum VSM_OPCODE : vsm_u8
{
    VSM_NOP = 0x00,
    VSM_LOAD = 0x01,
    VSM_STORE = 0x02,
    VSM_MOVE = 0x03,
    VSM_AND = 0x04,
    VSM_OR = 0x05,
    VSM_XOR = 0x06,
    VSM_NOT = 0x07,
    VSM_EQ = 0x08,
    VSM_NEQ = 0x09,
    VSM_MASK = 0x0A,
    VSM_SHL = 0x0B,
    VSM_SHR = 0x0C,
    VSM_ROL = 0x0D,
    VSM_ROR = 0x0E,
    VSM_BIND = 0x0F,
    VSM_UNBIND = 0x10,
    VSM_ASSERT = 0x11,
    VSM_REJECT = 0x12,
    VSM_PROVE = 0x13,
    VSM_VERIFY = 0x14,
    VSM_ROUTE = 0x15,
    VSM_FORK = 0x16,
    VSM_JOIN = 0x17,
    VSM_SEED = 0x18,
    VSM_SPRING = 0x19,
    VSM_PROPAGATE = 0x1A,
    VSM_COMMIT = 0x1B,
    VSM_ROLLBACK = 0x1C,
    VSM_COMPOSE = 0x1D,
    VSM_SPLIT = 0x1E,
    VSM_MERGE = 0x1F,
    VSM_HALT = 0xFF
};

enum VSM_STATUS : vsm_u32
{
    VSM_OK = 0,
    VSM_INVALID_STATE = 1,
    VSM_INVALID_PARAMETER = 2,
    VSM_INVALID_OPCODE = 3,
    VSM_MEMORY_FAILURE = 4,
    VSM_CONSTRAINT_FAILURE = 5,
    VSM_PROOF_FAILURE = 6,
    VSM_PROPAGATION_FAILURE = 7,
    VSM_CONFLICT = 8,
    VSM_RESOURCE_EXHAUSTION = 9,
    VSM_HALTED = 10
};

enum VSM_ELEMENT_TYPE : vsm_u32
{
    VSM_E_BINARY = 0,
    VSM_E_U8 = 1,
    VSM_E_U16 = 2,
    VSM_E_U32 = 3,
    VSM_E_U64 = 4,
    VSM_E_I32 = 5,
    VSM_E_F16 = 6,
    VSM_E_BF16 = 7,
    VSM_E_F32 = 8
};

struct alignas(16) VSMVirtualParameter
{
    vsm_u64 id;
    vsm_u64 semantic_id;
    vsm_u64 binary_signature;
    vsm_u32 dimension;
    vsm_u32 element_type;
    vsm_u64 memory_offset;
    vsm_u64 version;
    vsm_u64 provenance;
    vsm_u32 validity;
    vsm_u32 constraint_state;
    vsm_u64 value;
    vsm_u64 flags;
};

struct alignas(16) VSMEmbedding
{
    vsm_u64 embed_id;
    vsm_u64 semantic_id;
    vsm_u64 binary_signature;
    vsm_u32 dimension;
    vsm_u32 element_type;
    vsm_u64 memory_offset;
    vsm_u64 version;
    vsm_u64 provenance;
    vsm_u32 validity;
    vsm_u32 constraint_state;
};

struct alignas(16) VSMInstruction
{
    vsm_u8 opcode;
    vsm_u8 rd;
    vsm_u8 rs1;
    vsm_u8 rs2;
    vsm_u32 immediate;
    vsm_u64 operand;
};

struct alignas(16) VSMConstraint
{
    vsm_u64 id;
    vsm_u64 predicate;
    vsm_u64 scope;
    vsm_u64 dependencies;
    vsm_u64 priority;
    vsm_u32 result;
    vsm_u32 flags;
};

struct alignas(16) VSMProof
{
    vsm_u64 statement;
    vsm_u64 input_hash;
    vsm_u64 output_hash;
    vsm_u64 rule;
    vsm_u32 result;
    vsm_u32 flags;
};

struct alignas(16) VSMProvenance
{
    vsm_u64 state_id;
    vsm_u64 parent_id;
    vsm_u64 instruction_id;
    vsm_u64 input_hash;
    vsm_u64 output_hash;
    vsm_u64 branch_id;
    vsm_u32 validation;
    vsm_u32 status;
};

struct alignas(16) VSMSpringboard
{
    vsm_u64 source;
    vsm_u64 seed;
    vsm_u64 constraints;
    vsm_u64 transition;
    vsm_u64 target;
    vsm_u64 validation;
    vsm_u64 provenance;
    vsm_u32 state;
    vsm_u32 flags;
};

struct alignas(16) VSMState
{
    vsm_u64 state_id;
    vsm_u64 parent_id;
    vsm_u64 semantic;
    vsm_u64 seed;
    vsm_u64 route;
    vsm_u64 history;
    vsm_u64 proof;
    vsm_u64 flags;
    vsm_u32 validity;
    vsm_u32 status;
    vsm_u64 pc;
};

struct alignas(16) VSMRegisters
{
    vsm_u64 r[32];

    vsm_u64 sem;
    vsm_u64 ctx;
    vsm_u64 bind;
    vsm_u64 proof;
    vsm_u64 state;
    vsm_u64 mem;
    vsm_u64 route;
    vsm_u64 seed;
    vsm_u64 valid;
    vsm_u64 error;
    vsm_u64 history;
};

struct alignas(16) VSMFeature
{
    vsm_u64 feature_id;
    vsm_u64 source_id;
    vsm_u32 layer_id;
    vsm_u32 position;
    vsm_f32 value;
    vsm_u32 validity;
    vsm_u64 provenance;
    vsm_u32 constraint_state;
    vsm_u32 reserved;
};

struct alignas(16) VSMExecutionRecord
{
    vsm_u64 sequence;
    vsm_u64 state_before;
    vsm_u64 state_after;
    vsm_u64 instruction;
    vsm_u64 parameter;
    vsm_u64 input_hash;
    vsm_u64 output_hash;
    vsm_u32 constraint_result;
    vsm_u32 proof_result;
    vsm_u32 status;
    vsm_u32 lane;
};

__device__ __forceinline__
vsm_u64 vsm_rol64(vsm_u64 x, vsm_u32 n)
{
    n &= 63u;
    return (x << n) | (x >> ((64u - n) & 63u));
}

__device__ __forceinline__
vsm_u64 vsm_ror64(vsm_u64 x, vsm_u32 n)
{
    n &= 63u;
    return (x >> n) | (x << ((64u - n) & 63u));
}

__device__ __forceinline__
vsm_u64 vsm_mix(vsm_u64 x)
{
    x ^= x >> 30;
    x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27;
    x *= 0x94d049bb133111ebULL;
    x ^= x >> 31;
    return x;
}

__device__ __forceinline__
vsm_u64 vsm_semantic_hash(vsm_u64 x)
{
    return vsm_mix(x);
}

__device__ __forceinline__
vsm_u64 vsm_bind(vsm_u64 a, vsm_u64 b)
{
    return a ^ b;
}

__device__ __forceinline__
vsm_u64 vsm_unbind(vsm_u64 a, vsm_u64 b)
{
    return a ^ b;
}

__device__ __forceinline__
vsm_u64 vsm_compose(vsm_u64 a, vsm_u64 b)
{
    return vsm_mix(a ^ vsm_rol64(b, 17u));
}

__device__ __forceinline__
vsm_u64 vsm_merge(vsm_u64 a, vsm_u64 b)
{
    return vsm_mix(
        (a & b) ^
        vsm_rol64(a | b, 13u)
    );
}

__device__ __forceinline__
vsm_u64 vsm_split(vsm_u64 x)
{
    return x ^ vsm_ror64(x, 29u);
}

__device__ __forceinline__
vsm_u32 vsm_constraint_eval(
    const VSMConstraint* constraints,
    vsm_u32 count,
    vsm_u64 state)
{
    vsm_u32 result = VSM_OK;

    for (vsm_u32 i = 0; i < count; ++i)
    {
        const VSMConstraint c = constraints[i];

        if ((state & c.scope) !=
            (c.predicate & c.scope))
        {
            result = VSM_CONSTRAINT_FAILURE;
            break;
        }
    }

    return result;
}

__device__ __forceinline__
vsm_u32 vsm_proof_eval(
    const VSMProof* proof,
    vsm_u64 input,
    vsm_u64 output)
{
    if (proof == nullptr)
        return VSM_PROOF_FAILURE;

    const vsm_u64 input_hash =
        vsm_semantic_hash(input);

    const vsm_u64 output_hash =
        vsm_semantic_hash(output);

    if (proof->input_hash != 0 &&
        proof->input_hash != input_hash)
        return VSM_PROOF_FAILURE;

    if (proof->output_hash != 0 &&
        proof->output_hash != output_hash)
        return VSM_PROOF_FAILURE;

    return VSM_OK;
}

__device__ __forceinline__
vsm_u64 vsm_warp_xor(vsm_u64 x)
{
    unsigned mask = 0xffffffffu;

    x ^= __shfl_xor_sync(mask, x, 16);
    x ^= __shfl_xor_sync(mask, x, 8);
    x ^= __shfl_xor_sync(mask, x, 4);
    x ^= __shfl_xor_sync(mask, x, 2);
    x ^= __shfl_xor_sync(mask, x, 1);

    return x;
}

__device__ __forceinline__
vsm_u64 vsm_lane_mask(vsm_u32 lane)
{
    return 1ULL << (lane & 63u);
}

__global__
void vsm_binary_semantics_kernel(
    const vsm_u64* __restrict__ input_a,
    const vsm_u64* __restrict__ input_b,
    vsm_u64* __restrict__ output,
    vsm_u32* __restrict__ status,
    vsm_u32 count)
{
    const vsm_u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    const vsm_u64 a = input_a[tid];
    const vsm_u64 b = input_b[tid];

    const vsm_u64 x =
        a ^
        b ^
        (a & b) ^
        (a | b);

    output[tid] = vsm_mix(x);
    status[tid] = VSM_OK;
}

__global__
void vsm_embedding_lookup_kernel(
    const vsm_u64* __restrict__ semantic_ids,
    const vsm_f32* __restrict__ table,
    vsm_f32* __restrict__ output,
    vsm_u32 count,
    vsm_u32 table_rows,
    vsm_u32 dimension)
{
    const vsm_u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    const vsm_u64 semantic_id =
        semantic_ids[tid];

    const vsm_u32 row =
        (vsm_u32)(semantic_id %
                  (vsm_u64)table_rows);

    const vsm_f32* src =
        table +
        (vsm_u64)row *
        dimension;

    vsm_f32* dst =
        output +
        (vsm_u64)tid *
        dimension;

    for (vsm_u32 d = 0;
         d < dimension;
         ++d)
    {
        dst[d] = src[d];
    }
}

__global__
void vsm_embedding_binary_kernel(
    const vsm_u64* __restrict__ input,
    vsm_u64* __restrict__ output,
    vsm_u32 count)
{
    const vsm_u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    if (tid >= count)
        return;

    vsm_u64 x = input[tid];

    x ^= vsm_rol64(x, 7u);
    x ^= vsm_ror64(x, 11u);
    x = vsm_mix(x);

    output[tid] = x;
}

__global__
void vsm_embedding_transform_kernel(
    const vsm_f32* __restrict__ input,
    vsm_f32* __restrict__ output,
    vsm_u32 count,
    vsm_u32 dimension)
{
    const vsm_u32 tid =
        blockIdx.x * blockDim.x + threadIdx.x;

    const vsm_u64 total =
        (vsm_u64)count * dimension;

    if ((vsm_u64)tid >= total)
        return;

    const vsm_f32 x =
        input[tid];

    const vsm_f32 y =
        x * 0.7071067811865475f;

    output[tid] = y;
}

__global__
void vsm_relu_kernel(
    vsm_f32* __restrict__ data,
    vsm_u64 count)
{
    const vsm_u64 tid =
        (vsm_u64)blockIdx.x *
        blockDim.x +
        threadIdx.x;

    if (tid >= count)
        return;

    vsm_f32 x = data[tid];

    data[tid] =
        x > 0.0f ? x : 0.0f;
}

__global__
void vsm_maxpool2d_kernel(
    const vsm_f32* __restrict__ input,
    vsm_f32* __restrict__ output,
    vsm_u32 channels,
    vsm_u32 height,
    vsm_u32 width,
    vsm_u32 window,
    vsm_u32 stride)
{
    const vsm_u64 tid =
        (vsm_u64)blockIdx.x *
        blockDim.x +
        threadIdx.x;

    const vsm_u32 out_h =
        (height - window) /
        stride + 1u;

    const vsm_u32 out_w =
        (width - window) /
        stride + 1u;

    const vsm_u64 total =
        (vsm_u64)channels *
        out_h *
        out_w;

    if (tid >= total)
        return;

    const vsm_u32 ox =
        tid % out_w;

    const vsm_u32 oy =
        (tid / out_w) % out_h;

    const vsm_u32 c =
        tid / ((vsm_u64)out_w * out_h);

    vsm_f32 maximum =
        -3.402823466e+38F;

    for (vsm_u32 ky = 0;
         ky < window;
         ++ky)
    {
        for (vsm_u32 kx = 0;
             kx < window;
             ++kx)
        {
            const vsm_u32 ix =
                ox * stride + kx;

            const vsm_u32 iy =
                oy * stride + ky;

            const vsm_u64 p =
                ((vsm_u64)c *
                 height +
                 iy) *
                 width +
                 ix;

            const vsm_f32 value =
                input[p];

            maximum =
                value > maximum ?
                value :
                maximum;
        }
    }

    output[tid] = maximum;
}

__global__
void vsm_conv2d_kernel(
    const vsm_f32* __restrict__ input,
    const vsm_f32* __restrict__ kernel,
    const vsm_f32* __restrict__ bias,
    vsm_f32* __restrict__ output,
    vsm_u32 in_channels,
    vsm_u32 out_channels,
    vsm_u32 height,
    vsm_u32 width,
    vsm_u32 kernel_size,
    vsm_u32 stride)
{
    const vsm_u64 tid =
        (vsm_u64)blockIdx.x *
        blockDim.x +
        threadIdx.x;

    const vsm_u32 out_h =
        (height - kernel_size) /
        stride + 1u;

    const vsm_u32 out_w =
        (width - kernel_size) /
        stride + 1u;

    const vsm_u64 total =
        (vsm_u64)out_channels *
        out_h *
        out_w;

    if (tid >= total)
        return;

    const vsm_u32 ox =
        tid % out_w;

    const vsm_u32 oy =
        (tid / out_w) % out_h;

    const vsm_u32 oc =
        tid /
        ((vsm_u64)out_w * out_h);

    vsm_f32 accumulator =
        bias != nullptr ?
        bias[oc] :
        0.0f;

    for (vsm_u32 ic = 0;
         ic < in_channels;
         ++ic)
    {
        for (vsm_u32 ky = 0;
             ky < kernel_size;
             ++ky)
        {
            for (vsm_u32 kx = 0;
                 kx < kernel_size;
                 ++kx)
            {
                const vsm_u32 ix =
                    ox * stride + kx;

                const vsm_u32 iy =
                    oy * stride + ky;

                const vsm_u64 input_index =
                    ((vsm_u64)ic *
                     height +
                     iy) *
                     width +
                     ix;

                const vsm_u64 kernel_index =
                    (((vsm_u64)oc *
                      in_channels +
                      ic) *
                      kernel_size +
                      ky) *
                      kernel_size +
                      kx;

                accumulator +=
                    input[input_index] *
                    kernel[kernel_index];
            }
        }
    }

    output[tid] =
        accumulator > 0.0f ?
        accumulator :
        0.0f;
}

__global__
void vsm_fc_kernel(
    const vsm_f32* __restrict__ input,
    const vsm_f32* __restrict__ weights,
    const vsm_f32* __restrict__ bias,
    vsm_f32* __restrict__ output,
    vsm_u32 input_dim,
    vsm_u32 output_dim)
{
    const vsm_u32 o =
        blockIdx.x * blockDim.x +
        threadIdx.x;

    if (o >= output_dim)
        return;

    vsm_f32 accumulator =
        bias != nullptr ?
        bias[o] :
        0.0f;

    const vsm_f32* row =
        weights +
        (vsm_u64)o *
        input_dim;

    for (vsm_u32 i = 0;
         i < input_dim;
         ++i)
    {
        accumulator +=
            row[i] *
            input[i];
    }

    output[o] = accumulator;
}

__global__
void vsm_semantic_feature_kernel(
    const vsm_f32* __restrict__ input,
    VSMFeature* __restrict__ output,
    vsm_u32 count,
    vsm_u32 layer,
    vsm_u64 source)
{
    const vsm_u32 tid =
        blockIdx.x * blockDim.x +
        threadIdx.x;

    if (tid >= count)
        return;

    VSMFeature f{};

    f.feature_id =
        ((vsm_u64)layer << 32) |
        tid;

    f.source_id =
        source;

    f.layer_id =
        layer;

    f.position =
        tid;

    f.value =
        input[tid];

    f.validity =
        1;

    f.provenance =
        vsm_semantic_hash(
            source ^ tid);

    f.constraint_state =
        VSM_OK;

    output[tid] = f;
}

__global__
void vsm_springboard_kernel(
    const VSMSpringboard* __restrict__ input,
    VSMSpringboard* __restrict__ output,
    vsm_u32* __restrict__ status,
    vsm_u32 count)
{
    const vsm_u32 tid =
        blockIdx.x * blockDim.x +
        threadIdx.x;

    if (tid >= count)
        return;

    VSMSpringboard s =
        input[tid];

    if (s.source == 0 ||
        s.seed == 0 ||
        s.transition == 0)
    {
        s.state = VSM_PROPAGATION_FAILURE;
        status[tid] =
            VSM_PROPAGATION_FAILURE;
        output[tid] = s;
        return;
    }

    const vsm_u64 target =
        vsm_compose(
            s.source ^ s.seed,
            s.transition);

    s.target =
        target;

    s.validation =
        vsm_semantic_hash(target);

    s.state =
        VSM_OK;

    output[tid] =
        s;

    status[tid] =
        VSM_OK;
}

__global__
void vsm_springboard_propagate_kernel(
    const VSMSpringboard* __restrict__ springboards,
    const vsm_u64* __restrict__ states,
    vsm_u64* __restrict__ outputs,
    vsm_u32* __restrict__ status,
    vsm_u32 count)
{
    const vsm_u32 tid =
        blockIdx.x * blockDim.x +
        threadIdx.x;

    if (tid >= count)
        return;

    const VSMSpringboard s =
        springboards[tid];

    if (s.state != VSM_OK)
    {
        outputs[tid] = 0;
        status[tid] =
            VSM_PROPAGATION_FAILURE;
        return;
    }

    vsm_u64 x =
        states[tid];

    x ^= s.source;
    x ^= s.seed;
    x ^= s.constraints;
    x ^= s.transition;

    x =
        vsm_mix(x);

    outputs[tid] =
        x;

    status[tid] =
        VSM_OK;
}

__device__
vsm_u32 vsm_execute_instruction(
    const VSMInstruction& ins,
    VSMRegisters& r)
{
    if (ins.rd >= 32 ||
        ins.rs1 >= 32 ||
        ins.rs2 >= 32)
        return VSM_INVALID_PARAMETER;

    const vsm_u64 a =
        r.r[ins.rs1];

    const vsm_u64 b =
        r.r[ins.rs2];

    switch (ins.opcode)
    {
        case VSM_NOP:
            return VSM_OK;

        case VSM_LOAD:
            r.r[ins.rd] =
                ins.operand;
            return VSM_OK;

        case VSM_STORE:
            r.mem =
                r.r[ins.rs1];
            return VSM_OK;

        case VSM_MOVE:
            r.r[ins.rd] =
                a;
            return VSM_OK;

        case VSM_AND:
            r.r[ins.rd] =
                a & b;
            return VSM_OK;

        case VSM_OR:
            r.r[ins.rd] =
                a | b;
            return VSM_OK;

        case VSM_XOR:
            r.r[ins.rd] =
                a ^ b;
            return VSM_OK;

        case VSM_NOT:
            r.r[ins.rd] =
                ~a;
            return VSM_OK;

        case VSM_EQ:
            r.r[ins.rd] =
                a == b;
            return VSM_OK;

        case VSM_NEQ:
            r.r[ins.rd] =
                a != b;
            return VSM_OK;

        case VSM_MASK:
            r.r[ins.rd] =
                a & ins.operand;
            return VSM_OK;

        case VSM_SHL:
            r.r[ins.rd] =
                a << (ins.immediate & 63u);
            return VSM_OK;

        case VSM_SHR:
            r.r[ins.rd] =
                a >> (ins.immediate & 63u);
            return VSM_OK;

        case VSM_ROL:
            r.r[ins.rd] =
                vsm_rol64(
                    a,
                    ins.immediate);
            return VSM_OK;

        case VSM_ROR:
            r.r[ins.rd] =
                vsm_ror64(
                    a,
                    ins.immediate);
            return VSM_OK;

        case VSM_BIND:
            r.bind =
                vsm_bind(a, b);

            r.r[ins.rd] =
                r.bind;

            return VSM_OK;

        case VSM_UNBIND:
            r.r[ins.rd] =
                vsm_unbind(
                    a,
                    r.bind);

            return VSM_OK;

        case VSM_ASSERT:
            return a != 0 ?
                VSM_OK :
                VSM_CONSTRAINT_FAILURE;

        case VSM_REJECT:
            return VSM_CONFLICT;

        case VSM_PROVE:
            r.proof =
                vsm_semantic_hash(
                    r.state ^
                    a ^
                    b);

            r.r[ins.rd] =
                r.proof;

            return VSM_OK;

        case VSM_VERIFY:
        {
            const vsm_u64 expected =
                vsm_semantic_hash(
                    r.state ^
                    a ^
                    b);

            return expected ==
                    r.proof ?
                    VSM_OK :
                    VSM_PROOF_FAILURE;
        }

        case VSM_ROUTE:
            r.route =
                vsm_semantic_hash(
                    a ^
                    r.ctx ^
                    r.state);

            r.r[ins.rd] =
                r.route;

            return VSM_OK;

        case VSM_FORK:
            r.history =
                r.state;

            r.state =
                vsm_mix(
                    r.state ^
                    a ^
                    ins.operand);

            r.r[ins.rd] =
                r.state;

            return VSM_OK;

        case VSM_JOIN:
            r.state =
                vsm_merge(
                    r.state,
                    a);

            r.r[ins.rd] =
                r.state;

            return VSM_OK;

        case VSM_SEED:
            r.seed =
                vsm_mix(
                    a ^
                    ins.operand);

            r.r[ins.rd] =
                r.seed;

            return VSM_OK;

        case VSM_SPRING:
            r.state =
                vsm_compose(
                    r.state,
                    r.seed ^
                    a ^
                    ins.operand);

            r.r[ins.rd] =
                r.state;

            return VSM_OK;

        case VSM_PROPAGATE:
            r.state =
                vsm_mix(
                    r.state ^
                    r.seed ^
                    r.route ^
                    a);

            r.r[ins.rd] =
                r.state;

            return VSM_OK;

        case VSM_COMMIT:
            r.history =
                r.state;
            return VSM_OK;

        case VSM_ROLLBACK:
            r.state =
                r.history;
            return VSM_OK;

        case VSM_COMPOSE:
            r.r[ins.rd] =
                vsm_compose(a, b);
            return VSM_OK;

        case VSM_SPLIT:
            r.r[ins.rd] =
                vsm_split(a);
            return VSM_OK;

        case VSM_MERGE:
            r.r[ins.rd] =
                vsm_merge(a, b);
            return VSM_OK;

        case VSM_HALT:
            return VSM_HALTED;

        default:
            return VSM_INVALID_OPCODE;
    }
}

__global__
void vsm_machine_kernel(
    const VSMInstruction* __restrict__ program,
    vsm_u32 instruction_count,
    VSMRegisters* __restrict__ register_file,
    VSMExecutionRecord* __restrict__ trace,
    vsm_u32* __restrict__ status,
    vsm_u32 instances)
{
    const vsm_u32 tid =
        blockIdx.x * blockDim.x +
        threadIdx.x;

    if (tid >= instances)
        return;

    VSMRegisters r =
        register_file[tid];

    vsm_u32 result =
        VSM_OK;

    for (vsm_u32 pc = 0;
         pc < instruction_count;
         ++pc)
    {
        const VSMInstruction ins =
            program[pc];

        const vsm_u64 before =
            r.state;

        result =
            vsm_execute_instruction(
                ins,
                r);

        const vsm_u64 after =
            r.state;

        if (trace != nullptr)
        {
            VSMExecutionRecord record{};

            record.sequence =
                (vsm_u64)pc;

            record.state_before =
                before;

            record.state_after =
                after;

            record.instruction =
                ((vsm_u64)ins.opcode << 56) |
                ((vsm_u64)ins.rd << 48) |
                ((vsm_u64)ins.rs1 << 40) |
                ((vsm_u64)ins.rs2 << 32) |
                ins.immediate;

            record.parameter =
                ins.operand;

            record.input_hash =
                vsm_semantic_hash(
                    before);

            record.output_hash =
                vsm_semantic_hash(
                    after);

            record.constraint_result =
                result ==
                VSM_CONSTRAINT_FAILURE ?
                result :
                VSM_OK;

            record.proof_result =
                result ==
                VSM_PROOF_FAILURE ?
                result :
                VSM_OK;

            record.status =
                result;

            record.lane =
                threadIdx.x &
                31u;

            trace[
                (vsm_u64)tid *
                instruction_count +
                pc
            ] = record;
        }

        if (result != VSM_OK)
            break;
    }

    register_file[tid] =
        r;

    status[tid] =
        result;
}

__global__
void vsm_warp_semantic_reduce_kernel(
    const vsm_u64* __restrict__ input,
    vsm_u64* __restrict__ output,
    vsm_u32 count)
{
    const vsm_u32 tid =
        blockIdx.x *
        blockDim.x +
        threadIdx.x;

    if (tid >= count)
        return;

    vsm_u64 x =
        input[tid];

    x =
        vsm_warp_xor(x);

    if ((threadIdx.x & 31u) == 0)
    {
        output[
            blockIdx.x
        ] = x;
    }
}

__global__
void vsm_binary_feature_kernel(
    const vsm_f32* __restrict__ input,
    vsm_u64* __restrict__ output,
    vsm_u32 count)
{
    const vsm_u32 tid =
        blockIdx.x *
        blockDim.x +
        threadIdx.x;

    if (tid >= count)
        return;

    const vsm_f32 x =
        input[tid];

    const vsm_u64 bit =
        x >= 0.0f ?
        1ULL :
        0ULL;

    const unsigned mask =
        __ballot_sync(
            0xffffffffu,
            bit != 0);

    if ((threadIdx.x & 31u) == 0)
    {
        output[
            tid >> 5
        ] =
            (vsm_u64)mask;
    }
}

extern "C"
cudaError_t vsm_launch_machine(
    const VSMInstruction* program,
    vsm_u32 instruction_count,
    VSMRegisters* registers,
    VSMExecutionRecord* trace,
    vsm_u32* status,
    vsm_u32 instances,
    cudaStream_t stream)
{
    dim3 block(128);
    dim3 grid(
        (instances + block.x - 1u) /
        block.x);

    vsm_machine_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            program,
            instruction_count,
            registers,
            trace,
            status,
            instances);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_embedding(
    const vsm_u64* semantic_ids,
    const vsm_f32* table,
    vsm_f32* output,
    vsm_u32 count,
    vsm_u32 rows,
    vsm_u32 dimension,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (count + 255u) /
        256u);

    vsm_embedding_lookup_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            semantic_ids,
            table,
            output,
            count,
            rows,
            dimension);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_binary(
    const vsm_u64* a,
    const vsm_u64* b,
    vsm_u64* output,
    vsm_u32* status,
    vsm_u32 count,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (count + 255u) /
        256u);

    vsm_binary_semantics_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            a,
            b,
            output,
            status,
            count);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_conv(
    const vsm_f32* input,
    const vsm_f32* kernel,
    const vsm_f32* bias,
    vsm_f32* output,
    vsm_u32 in_channels,
    vsm_u32 out_channels,
    vsm_u32 height,
    vsm_u32 width,
    vsm_u32 kernel_size,
    vsm_u32 stride,
    cudaStream_t stream)
{
    const vsm_u32 out_h =
        (height - kernel_size) /
        stride + 1u;

    const vsm_u32 out_w =
        (width - kernel_size) /
        stride + 1u;

    const vsm_u64 count =
        (vsm_u64)out_channels *
        out_h *
        out_w;

    dim3 block(256);
    dim3 grid(
        (vsm_u32)((count + 255u) /
                  256u));

    vsm_conv2d_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            input,
            kernel,
            bias,
            output,
            in_channels,
            out_channels,
            height,
            width,
            kernel_size,
            stride);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_pool(
    const vsm_f32* input,
    vsm_f32* output,
    vsm_u32 channels,
    vsm_u32 height,
    vsm_u32 width,
    vsm_u32 window,
    vsm_u32 stride,
    cudaStream_t stream)
{
    const vsm_u32 out_h =
        (height - window) /
        stride + 1u;

    const vsm_u32 out_w =
        (width - window) /
        stride + 1u;

    const vsm_u64 count =
        (vsm_u64)channels *
        out_h *
        out_w;

    dim3 block(256);
    dim3 grid(
        (vsm_u32)((count + 255u) /
                  256u));

    vsm_maxpool2d_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            input,
            output,
            channels,
            height,
            width,
            window,
            stride);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_fc(
    const vsm_f32* input,
    const vsm_f32* weights,
    const vsm_f32* bias,
    vsm_f32* output,
    vsm_u32 input_dim,
    vsm_u32 output_dim,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (output_dim + 255u) /
        256u);

    vsm_fc_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            input,
            weights,
            bias,
            output,
            input_dim,
            output_dim);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_springboard(
    const VSMSpringboard* input,
    VSMSpringboard* output,
    vsm_u32* status,
    vsm_u32 count,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (count + 255u) /
        256u);

    vsm_springboard_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            input,
            output,
            status,
            count);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_propagation(
    const VSMSpringboard* springboards,
    const vsm_u64* states,
    vsm_u64* outputs,
    vsm_u32* status,
    vsm_u32 count,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (count + 255u) /
        256u);

    vsm_springboard_propagate_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            springboards,
            states,
            outputs,
            status,
            count);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_features(
    const vsm_f32* input,
    VSMFeature* output,
    vsm_u32 count,
    vsm_u32 layer,
    vsm_u64 source,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (count + 255u) /
        256u);

    vsm_semantic_feature_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            input,
            output,
            count,
            layer,
            source);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_binary_features(
    const vsm_f32* input,
    vsm_u64* output,
    vsm_u32 count,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (count + 255u) /
        256u);

    vsm_binary_feature_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            input,
            output,
            count);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_relu(
    vsm_f32* data,
    vsm_u64 count,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (vsm_u32)((count + 255u) /
                  256u));

    vsm_relu_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            data,
            count);

    return cudaGetLastError();
}

extern "C"
cudaError_t vsm_launch_warp_reduce(
    const vsm_u64* input,
    vsm_u64* output,
    vsm_u32 count,
    cudaStream_t stream)
{
    dim3 block(256);
    dim3 grid(
        (count + 255u) /
        256u);

    vsm_warp_semantic_reduce_kernel<<<
        grid,
        block,
        0,
        stream>>>(
            input,
            output,
            count);

    return cudaGetLastError();
}

extern "C"
int vsm_runtime_architecture()
{
    int device = 0;

    cudaDeviceProp prop{};

    if (cudaGetDeviceProperties(
            &prop,
            device) != cudaSuccess)
        return -1;

    return prop.major * 10 +
           prop.minor;
}

extern "C"
int vsm_runtime_is_sm90()
{
    return
        vsm_runtime_architecture() ==
        (int)VSM_SM90;
}

extern "C"
cudaError_t vsm_synchronize()
{
    return cudaDeviceSynchronize();
}

#endif /* VSM2500_H100_SASS_BRIDGE_CU */
