#include "../Common/types.h"

kernel void quantized_matmul_i4(
    device const uchar* weights [[buffer(0)]],
    device const half* scales [[buffer(1)]],
    device const half* input [[buffer(2)]],
    device half* output [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weights, scales, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matmul_i4_bias(
    device const uchar* weights [[buffer(0)]],
    device const half* scales [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device const half* input [[buffer(3)]],
    device half* output [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weights, scales, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matmul_i8(
    device const uchar* weights [[buffer(0)]],
    device const half* scales [[buffer(1)]],
    device const half* input [[buffer(2)]],
    device half* output [[buffer(3)]],
    constant LinearShape& shape [[buffer(4)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = 0.0f;
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i8(weights, scales, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void quantized_matmul_i8_bias(
    device const uchar* weights [[buffer(0)]],
    device const half* scales [[buffer(1)]],
    device const half* bias [[buffer(2)]],
    device const half* input [[buffer(3)]],
    device half* output [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i8(weights, scales, row, col, shape.cols) * float(input[col]);
    }
    output[row] = half(acc);
}

kernel void qkv_projection(
    device const uchar* wq [[buffer(0)]],
    device const half* sq [[buffer(1)]],
    device const uchar* wk [[buffer(2)]],
    device const half* sk [[buffer(3)]],
    device const uchar* wv [[buffer(4)]],
    device const half* sv [[buffer(5)]],
    device const half* x [[buffer(6)]],
    device half* q_out [[buffer(7)]],
    device half* k_out [[buffer(8)]],
    device half* v_out [[buffer(9)]],
    constant LinearShape& q_shape [[buffer(10)]],
    constant LinearShape& k_shape [[buffer(11)]],
    constant LinearShape& v_shape [[buffer(12)]],
    uint row [[thread_position_in_grid]])
{
    if (row < q_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < q_shape.cols; ++col) {
            acc += dequant_i4(wq, sq, row, col, q_shape.cols) * float(x[col]);
        }
        q_out[row] = half(acc);
    }
    if (row < k_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < k_shape.cols; ++col) {
            acc += dequant_i4(wk, sk, row, col, k_shape.cols) * float(x[col]);
        }
        k_out[row] = half(acc);
    }
    if (row < v_shape.rows) {
        float acc = 0.0f;
        for (uint col = 0u; col < v_shape.cols; ++col) {
            acc += dequant_i4(wv, sv, row, col, v_shape.cols) * float(x[col]);
        }
        v_out[row] = half(acc);
    }
}

kernel void qkv_projection_bias(
    device const uchar* wq [[buffer(0)]],
    device const half* sq [[buffer(1)]],
    device const half* bq [[buffer(2)]],
    device const uchar* wk [[buffer(3)]],
    device const half* sk [[buffer(4)]],
    device const half* bk [[buffer(5)]],
    device const uchar* wv [[buffer(6)]],
    device const half* sv [[buffer(7)]],
    device const half* bv [[buffer(8)]],
    device const half* x [[buffer(9)]],
    device half* q_out [[buffer(10)]],
    device half* k_out [[buffer(11)]],
    device half* v_out [[buffer(12)]],
    constant LinearShape& q_shape [[buffer(13)]],
    constant LinearShape& k_shape [[buffer(14)]],
    constant LinearShape& v_shape [[buffer(15)]],
    uint row [[thread_position_in_grid]])
{
    if (row < q_shape.rows) {
        float acc = float(bq[row]);
        for (uint col = 0u; col < q_shape.cols; ++col) {
            acc += dequant_i4(wq, sq, row, col, q_shape.cols) * float(x[col]);
        }
        q_out[row] = half(acc);
    }
    if (row < k_shape.rows) {
        float acc = float(bk[row]);
        for (uint col = 0u; col < k_shape.cols; ++col) {
            acc += dequant_i4(wk, sk, row, col, k_shape.cols) * float(x[col]);
        }
        k_out[row] = half(acc);
    }
    if (row < v_shape.rows) {
        float acc = float(bv[row]);
        for (uint col = 0u; col < v_shape.cols; ++col) {
            acc += dequant_i4(wv, sv, row, col, v_shape.cols) * float(x[col]);
        }
        v_out[row] = half(acc);
    }
}

kernel void output_projection(
    device const half* x [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device const half* bias [[buffer(3)]],
    device half* output [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i4(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    output[row] = half(acc);
}

kernel void output_projection_i8(
    device const half* x [[buffer(0)]],
    device const uchar* weight [[buffer(1)]],
    device const half* scale [[buffer(2)]],
    device const half* bias [[buffer(3)]],
    device half* output [[buffer(4)]],
    constant LinearShape& shape [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= shape.rows) {
        return;
    }
    float acc = float(bias[row]);
    for (uint col = 0u; col < shape.cols; ++col) {
        acc += dequant_i8(weight, scale, row, col, shape.cols) * float(x[col]);
    }
    output[row] = half(acc);
}
