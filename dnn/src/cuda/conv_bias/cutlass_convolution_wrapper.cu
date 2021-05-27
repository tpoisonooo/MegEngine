/**
 * \file dnn/src/cuda/conv_bias/cutlass_convolution_wrapper.cu
 * MegEngine is Licensed under the Apache License, Version 2.0 (the "License")
 *
 * Copyright (c) 2014-2021 Megvii Inc. All rights reserved.
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT ARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied.
 */
// ignore warning of cutlass
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wstrict-aliasing"

#if !MEGDNN_TEGRA_X1
#include "cutlass/convolution/device/convolution.h"
#endif
#include "src/common/opr_param_defs_enumv.cuh"
#include "src/cuda/conv_bias/cutlass_convolution_wrapper.cuh"
#pragma GCC diagnostic pop

using namespace megdnn;
using namespace cuda;
using namespace cutlass_wrapper;

/* ================= cutlass kernel wrapper for nchw32 layout ================
 */
#if MEGDNN_TEGRA_X1
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_imma_ncdiv32hw32(
                const int8_t* /* d_src */, const int8_t* /* d_filter */,
                const int32_t* /* d_bias */, const int8_t* /* d_z */,
                int8_t* /* d_dst */, int* /* workspace */,
                const convolution::ConvParam& /* param */,
                uint32_t /* nonlinear_mode */, float /* alpha */,
                float /* beta */, float /* gamma */, float /* scale */,
                const GemmCoord& /* threadblock_shape */,
                const GemmCoord& /* warp_shape */, cudaStream_t /* stream */) {}
#else
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_imma_ncdiv32hw32(
                const int8_t* d_src, const int8_t* d_filter,
                const int32_t* d_bias, const int8_t* d_z, int8_t* d_dst,
                int* workspace, const convolution::ConvParam& param,
                uint32_t nonlinear_mode, float alpha, float beta, float gamma,
                float scale, const GemmCoord& threadblock_shape,
                const GemmCoord& warp_shape, cudaStream_t stream) {
#define DISPATCH_KERNEL_WITH_TILE_SHAPE(threadblock_m_, threadblock_n_,        \
                                        threadblock_k_, warp_m_, warp_n_,      \
                                        warp_k_)                               \
    if (threadblock_shape.m() == threadblock_m_ &&                             \
        threadblock_shape.n() == threadblock_n_ &&                             \
        threadblock_shape.k() == threadblock_k_ &&                             \
        warp_shape.m() == warp_m_ && warp_shape.n() == warp_n_ &&              \
        warp_shape.k() == warp_k_) {                                           \
        using ThreadBlockShape =                                               \
                cutlass::gemm::GemmShape<threadblock_m_, threadblock_n_,       \
                                         threadblock_k_>;                      \
        using WarpShape = cutlass::gemm::GemmShape<warp_m_, warp_n_, warp_k_>; \
        using InstructionShape = cutlass::gemm::GemmShape<8, 8, 16>;           \
        using Convolution = cutlass::conv::device::Convolution<                \
                int8_t, cutlass::layout::TensorNCxHWx<32>, int8_t,             \
                cutlass::layout::TensorCxRSKx<32>, ElementOutput,              \
                cutlass::layout::TensorNCxHWx<32>, int32_t,                    \
                cutlass::layout::TensorNCxHWx<32>, int32_t,                    \
                cutlass::conv::ConvType::kConvolution,                         \
                cutlass::arch::OpClassTensorOp, cutlass::arch::Sm75,           \
                ThreadBlockShape, WarpShape, InstructionShape, EpilogueOp,     \
                cutlass::conv::threadblock::                                   \
                        ConvolutionFpropNCxHWxThreadblockSwizzle,              \
                2, 16, 16, NeedLoadFromConstMem>;                              \
        typename Convolution::ConvolutionParameter conv_param(                 \
                param.n, param.hi, param.wi, param.ci, param.co, param.fh,     \
                param.fw, param.ho, param.wo, param.ph, param.pw, param.sh,    \
                param.sw, 1, 1, cutlass::conv::Mode::kCrossCorrelation);       \
        return cutlass_convolution_wrapper<Convolution>(                       \
                d_src, d_filter, d_bias, d_z, d_dst, workspace, conv_param,    \
                epilogue, stream);                                             \
    }
#define DISPATCH_KERNEL                                                      \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(256, 128, 64, 64, 64, 64);               \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 256, 64, 64, 64, 64);               \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 128, 64, 64, 64, 64);               \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 128, 64, 32, 64, 64);                \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 64, 64, 64, 32, 64);                \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 64, 64, 32, 32, 64);                 \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 64, 64, 32, 16, 64);                 \
    megdnn_assert(false,                                                     \
                  "unsupported threadblock shape (%dx%dx%d) and warp shape " \
                  "(%dx%dx%d)",                                              \
                  threadblock_shape.m(), threadblock_shape.n(),              \
                  threadblock_shape.k(), warp_shape.m(), warp_shape.n(),     \
                  warp_shape.k());
    using ElementOutput = int8_t;
    using ElementAccumulator = int32_t;
    using ElementBias = int32_t;
    using ElementCompute = float;
    using NonlineMode = megdnn::param_enumv::ConvBias::NonlineMode;
    switch (nonlinear_mode) {
        case NonlineMode::IDENTITY: {
            using EpilogueOp =
                    cutlass::epilogue::thread::BiasAddLinearCombinationClamp<
                            ElementOutput, 8, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma};
            DISPATCH_KERNEL;
        }
        case NonlineMode::RELU: {
            using EpilogueOp = cutlass::epilogue::thread::
                    BiasAddLinearCombinationReluClamp<
                            ElementOutput, 8, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, 0};
            DISPATCH_KERNEL;
        }
        case NonlineMode::H_SWISH: {
            using EpilogueOp = cutlass::epilogue::thread::
                    BiasAddLinearCombinationHSwishClamp<
                            ElementOutput, 8, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, scale};
            DISPATCH_KERNEL;
        }
        default:
            megdnn_assert(false,
                          "unsupported nonlinear mode for conv bias operator");
    }
#undef DISPATCH_KERNEL_WITH_TILE_SHAPE
#undef DISPATCH_KERNEL
}
#endif

#define INST(need_load_from_const_mem)                                       \
    template void megdnn::cuda::cutlass_wrapper::                            \
            do_conv_bias_int8_implicit_gemm_imma_ncdiv32hw32<                \
                    need_load_from_const_mem>(                               \
                    const int8_t* d_src, const int8_t* d_filter,             \
                    const int32_t* d_bias, const int8_t* d_z, int8_t* d_dst, \
                    int* workspace, const convolution::ConvParam& param,     \
                    uint32_t nonlinear_mode, float alpha, float beta,        \
                    float gamma, float scale,                                \
                    const GemmCoord& threadblock_shape,                      \
                    const GemmCoord& warp_shape, cudaStream_t stream);
INST(true);
INST(false);
#undef INST

/* ==== cutlass kernel wrapper for nchw32 layout and nchw4 output ===== */
#if MEGDNN_TEGRA_X1
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_imma_ncdiv32hw32_ncdiv4hw4(
                const int8_t* /* d_src */, const int8_t* /* d_filter */,
                const int32_t* /* d_bias */, const int8_t* /* d_z */,
                int8_t* /* d_dst */, int* /* workspace */,
                const convolution::ConvParam& /* param */,
                uint32_t /* nonlinear_mode */, float /* alpha */,
                float /* beta */, float /* gamma */, float /* scale */,
                const GemmCoord& /* threadblock_shape */,
                const GemmCoord& /* warp_shape */, cudaStream_t /* stream */) {}
#else
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_imma_ncdiv32hw32_ncdiv4hw4(
                const int8_t* d_src, const int8_t* d_filter,
                const int32_t* d_bias, const int8_t* d_z, int8_t* d_dst,
                int* workspace, const convolution::ConvParam& param,
                uint32_t nonlinear_mode, float alpha, float beta, float gamma,
                float scale, const GemmCoord& threadblock_shape,
                const GemmCoord& warp_shape, cudaStream_t stream) {
#define DISPATCH_KERNEL_WITH_TILE_SHAPE(threadblock_m_, threadblock_n_,        \
                                        threadblock_k_, warp_m_, warp_n_,      \
                                        warp_k_)                               \
    if (threadblock_shape.m() == threadblock_m_ &&                             \
        threadblock_shape.n() == threadblock_n_ &&                             \
        threadblock_shape.k() == threadblock_k_ &&                             \
        warp_shape.m() == warp_m_ && warp_shape.n() == warp_n_ &&              \
        warp_shape.k() == warp_k_) {                                           \
        using ThreadBlockShape =                                               \
                cutlass::gemm::GemmShape<threadblock_m_, threadblock_n_,       \
                                         threadblock_k_>;                      \
        using WarpShape = cutlass::gemm::GemmShape<warp_m_, warp_n_, warp_k_>; \
        using InstructionShape = cutlass::gemm::GemmShape<8, 8, 16>;           \
        using Convolution = cutlass::conv::device::Convolution<                \
                int8_t, cutlass::layout::TensorNCxHWx<32>, int8_t,             \
                cutlass::layout::TensorCxRSKx<32>, ElementOutput,              \
                cutlass::layout::TensorNCxHWx<4>, int32_t,                     \
                cutlass::layout::TensorNCxHWx<4>, int32_t,                     \
                cutlass::conv::ConvType::kConvolution,                         \
                cutlass::arch::OpClassTensorOp, cutlass::arch::Sm75,           \
                ThreadBlockShape, WarpShape, InstructionShape, EpilogueOp,     \
                cutlass::conv::threadblock::                                   \
                        ConvolutionFpropNCxHWxThreadblockSwizzle,              \
                2, 16, 16, NeedLoadFromConstMem>;                              \
        typename Convolution::ConvolutionParameter conv_param(                 \
                param.n, param.hi, param.wi, param.ci, param.co, param.fh,     \
                param.fw, param.ho, param.wo, param.ph, param.pw, param.sh,    \
                param.sw, 1, 1, cutlass::conv::Mode::kCrossCorrelation);       \
        return cutlass_convolution_wrapper<Convolution>(                       \
                d_src, d_filter, d_bias, d_z, d_dst, workspace, conv_param,    \
                epilogue, stream);                                             \
    }
#define DISPATCH_KERNEL                                                      \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(256, 128, 64, 64, 64, 64);               \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 256, 64, 64, 64, 64);               \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 128, 64, 64, 64, 64);               \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 128, 64, 32, 64, 64);                \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 64, 64, 64, 32, 64);                \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 64, 64, 32, 32, 64);                 \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 64, 64, 16, 32, 64);                 \
    megdnn_assert(false,                                                     \
                  "unsupported threadblock shape (%dx%dx%d) and warp shape " \
                  "(%dx%dx%d)",                                              \
                  threadblock_shape.m(), threadblock_shape.n(),              \
                  threadblock_shape.k(), warp_shape.m(), warp_shape.n(),     \
                  warp_shape.k());
    using ElementOutput = int8_t;
    using ElementAccumulator = int32_t;
    using ElementBias = int32_t;
    using ElementCompute = float;
    using NonlineMode = megdnn::param_enumv::ConvBias::NonlineMode;
    switch (nonlinear_mode) {
        case NonlineMode::IDENTITY: {
            using EpilogueOp =
                    cutlass::epilogue::thread::BiasAddLinearCombinationClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma};
            DISPATCH_KERNEL;
        }
        case NonlineMode::RELU: {
            using EpilogueOp = cutlass::epilogue::thread::
                    BiasAddLinearCombinationReluClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, 0};
            DISPATCH_KERNEL;
        }
        case NonlineMode::H_SWISH: {
            using EpilogueOp = cutlass::epilogue::thread::
                    BiasAddLinearCombinationHSwishClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, scale};
            DISPATCH_KERNEL;
        }
        default:
            megdnn_assert(false,
                          "unsupported nonlinear mode for conv bias operator");
    }
#undef DISPATCH_KERNEL_WITH_TILE_SHAPE
#undef DISPATCH_KERNEL
}
#endif

#define INST(need_load_from_const_mem)                                       \
    template void megdnn::cuda::cutlass_wrapper::                            \
            do_conv_bias_int8_implicit_gemm_imma_ncdiv32hw32_ncdiv4hw4<      \
                    need_load_from_const_mem>(                               \
                    const int8_t* d_src, const int8_t* d_filter,             \
                    const int32_t* d_bias, const int8_t* d_z, int8_t* d_dst, \
                    int* workspace, const convolution::ConvParam& param,     \
                    uint32_t nonlinear_mode, float alpha, float beta,        \
                    float gamma, float scale,                                \
                    const GemmCoord& threadblock_shape,                      \
                    const GemmCoord& warp_shape, cudaStream_t stream);
INST(true);
INST(false);
#undef INST

/* ================ cutlass kernel wrapper for nchw4 layout ================= */
#if MEGDNN_TEGRA_X1
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4(
                const int8_t* /* d_src */, const int8_t* /* d_filter */,
                const int32_t* /* d_bias */, const int8_t* /* d_z */,
                int8_t* /* d_dst */, int* /* workspace */,
                const convolution::ConvParam& /* param */,
                uint32_t /* nonlinear_mode */, float /* alpha */,
                float /* beta */, float /* gamma */, float /* scale */,
                const GemmCoord& /* threadblock_shape */,
                const GemmCoord& /* warp_shape */, int /* stages */,
                cudaStream_t /* stream */) {}
#else
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4(
                const int8_t* d_src, const int8_t* d_filter,
                const int32_t* d_bias, const int8_t* d_z, int8_t* d_dst,
                int* workspace, const convolution::ConvParam& param,
                uint32_t nonlinear_mode, float alpha, float beta, float gamma,
                float scale, const GemmCoord& threadblock_shape,
                const GemmCoord& warp_shape, int stages, cudaStream_t stream) {
#define DISPATCH_KERNEL_WITH_TILE_SHAPE(threadblock_m_, threadblock_n_,        \
                                        threadblock_k_, warp_m_, warp_n_,      \
                                        warp_k_, stage_, aligned_)             \
    if (threadblock_shape.m() == threadblock_m_ &&                             \
        threadblock_shape.n() == threadblock_n_ &&                             \
        threadblock_shape.k() == threadblock_k_ &&                             \
        warp_shape.m() == warp_m_ && warp_shape.n() == warp_n_ &&              \
        warp_shape.k() == warp_k_ && stages == stage_) {                       \
        using ThreadBlockShape =                                               \
                cutlass::gemm::GemmShape<threadblock_m_, threadblock_n_,       \
                                         threadblock_k_>;                      \
        using WarpShape = cutlass::gemm::GemmShape<warp_m_, warp_n_, warp_k_>; \
        using InstructionShape = cutlass::gemm::GemmShape<1, 1, 4>;            \
        using Convolution = cutlass::conv::device::Convolution<                \
                int8_t, cutlass::layout::TensorNCxHWx<4>, int8_t,              \
                cutlass::layout::TensorCxRSKx<4>, ElementOutput,               \
                cutlass::layout::TensorNCxHWx<4>, int32_t,                     \
                cutlass::layout::TensorNCxHWx<4>, int32_t,                     \
                cutlass::conv::ConvType::kConvolution,                         \
                cutlass::arch::OpClassSimt, cutlass::arch::Sm61,               \
                ThreadBlockShape, WarpShape, InstructionShape, EpilogueOp,     \
                cutlass::conv::threadblock::                                   \
                        ConvolutionFpropNCxHWxThreadblockSwizzle,              \
                stage_, 4, aligned_, NeedLoadFromConstMem>;                    \
        typename Convolution::ConvolutionParameter conv_param(                 \
                param.n, param.hi, param.wi, param.ci, param.co, param.fh,     \
                param.fw, param.ho, param.wo, param.ph, param.pw, param.sh,    \
                param.sw, 1, 1, cutlass::conv::Mode::kCrossCorrelation);       \
        return cutlass_convolution_wrapper<Convolution>(                       \
                d_src, d_filter, d_bias, d_z, d_dst, workspace, conv_param,    \
                epilogue, stream);                                             \
    }
#define DISPATCH_KERNEL                                                      \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 128, 32, 64, 32, 32, 2, 16);        \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 64, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 128, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 32, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 128, 32, 32, 64, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 64, 32, 64, 32, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 64, 32, 32, 64, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 32, 32, 64, 32, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 32, 32, 32, 32, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(16, 128, 16, 16, 128, 16, 1, 8);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(16, 64, 8, 16, 64, 8, 2, 4);             \
    megdnn_assert(false,                                                     \
                  "unsupported threadblock shape (%dx%dx%d) and warp shape " \
                  "(%dx%dx%d)",                                              \
                  threadblock_shape.m(), threadblock_shape.n(),              \
                  threadblock_shape.k(), warp_shape.m(), warp_shape.n(),     \
                  warp_shape.k());
    using ElementOutput = int8_t;
    using ElementAccumulator = int32_t;
    using ElementBias = int32_t;
    using ElementCompute = float;
    using NonlineMode = megdnn::param_enumv::ConvBias::NonlineMode;
    switch (nonlinear_mode) {
        case NonlineMode::IDENTITY: {
            using EpilogueOp =
                    cutlass::epilogue::thread::BiasAddLinearCombinationClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma};
            DISPATCH_KERNEL;
        }
        case NonlineMode::RELU: {
            using EpilogueOp = cutlass::epilogue::thread::
                    BiasAddLinearCombinationReluClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, 0};
            DISPATCH_KERNEL;
        }
        case NonlineMode::H_SWISH: {
            using EpilogueOp = cutlass::epilogue::thread::
                    BiasAddLinearCombinationHSwishClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, scale};
            DISPATCH_KERNEL;
        }
        default:
            megdnn_assert(false,
                          "unsupported nonlinear mode for conv bias operator");
    }
#undef DISPATCH_KERNEL_WITH_TILE_SHAPE
#undef DISPATCH_KERNEL
}
#endif

#define INST(need_load_from_const_mem)                                       \
    template void megdnn::cuda::cutlass_wrapper::                            \
            do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4<                  \
                    need_load_from_const_mem>(                               \
                    const int8_t* d_src, const int8_t* d_filter,             \
                    const int32_t* d_bias, const int8_t* d_z, int8_t* d_dst, \
                    int* workspace, const convolution::ConvParam& param,     \
                    uint32_t nonlinear_mode, float alpha, float beta,        \
                    float gamma, float scale,                                \
                    const GemmCoord& threadblock_shape,                      \
                    const GemmCoord& warp_shape, int stages,                 \
                    cudaStream_t stream);
INST(true);
INST(false);
#undef INST

/* ===== cutlass kernel wrapper for nchw4 layout and nchw output ===== */
#if MEGDNN_TEGRA_X1
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4_nchw(
                const int8_t* /* d_src */, const int8_t* /* d_filter */,
                const float* /* d_bias */, const float* /* d_z */,
                float* /* d_dst */, int* /* workspace */,
                const convolution::ConvParam& /* param */,
                uint32_t /* nonlinear_mode */, float /* alpha */,
                float /* beta */, float /* gamma */, float /* scale */,
                const GemmCoord& /* threadblock_shape */,
                const GemmCoord& /* warp_shape */, int /* stages */,
                cudaStream_t /* stream */) {}
#else
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4_nchw(
                const int8_t* d_src, const int8_t* d_filter,
                const float* d_bias, const float* d_z, float* d_dst,
                int* workspace, const convolution::ConvParam& param,
                uint32_t nonlinear_mode, float alpha, float beta, float gamma,
                float scale, const GemmCoord& threadblock_shape,
                const GemmCoord& warp_shape, int stages, cudaStream_t stream) {
#define DISPATCH_KERNEL_WITH_TILE_SHAPE(threadblock_m_, threadblock_n_,        \
                                        threadblock_k_, warp_m_, warp_n_,      \
                                        warp_k_, stages_, aligned_)            \
    if (threadblock_shape.m() == threadblock_m_ &&                             \
        threadblock_shape.n() == threadblock_n_ &&                             \
        threadblock_shape.k() == threadblock_k_ &&                             \
        warp_shape.m() == warp_m_ && warp_shape.n() == warp_n_ &&              \
        warp_shape.k() == warp_k_ && stages == stages_) {                      \
        using ThreadBlockShape =                                               \
                cutlass::gemm::GemmShape<threadblock_m_, threadblock_n_,       \
                                         threadblock_k_>;                      \
        using WarpShape = cutlass::gemm::GemmShape<warp_m_, warp_n_, warp_k_>; \
        using InstructionShape = cutlass::gemm::GemmShape<1, 1, 4>;            \
        using Convolution = cutlass::conv::device::Convolution<                \
                int8_t, cutlass::layout::TensorNCxHWx<4>, int8_t,              \
                cutlass::layout::TensorCxRSKx<4>, ElementOutput,               \
                cutlass::layout::TensorNCHW, float,                            \
                cutlass::layout::TensorNCHW, int32_t,                          \
                cutlass::conv::ConvType::kConvolution,                         \
                cutlass::arch::OpClassSimt, cutlass::arch::Sm61,               \
                ThreadBlockShape, WarpShape, InstructionShape, EpilogueOp,     \
                cutlass::conv::threadblock::                                   \
                        ConvolutionFpropNCxHWxThreadblockSwizzle,              \
                stages_, 4, aligned_, NeedLoadFromConstMem,                    \
                cutlass::arch::OpMultiplyAdd>;                                 \
        typename Convolution::ConvolutionParameter conv_param(                 \
                param.n, param.hi, param.wi, param.ci, param.co, param.fh,     \
                param.fw, param.ho, param.wo, param.ph, param.pw, param.sh,    \
                param.sw, 1, 1, cutlass::conv::Mode::kCrossCorrelation);       \
        return cutlass_convolution_wrapper<Convolution>(                       \
                d_src, d_filter, d_bias, d_z, d_dst, workspace, conv_param,    \
                epilogue, stream);                                             \
    }
#define DISPATCH_KERNEL                                                      \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 128, 32, 64, 32, 32, 2, 16);        \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 64, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 128, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 32, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 128, 32, 32, 64, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 64, 32, 64, 32, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 64, 32, 32, 64, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 32, 32, 64, 32, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 32, 32, 32, 32, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(16, 128, 16, 16, 128, 16, 1, 8);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(16, 64, 8, 16, 64, 8, 2, 4);             \
    megdnn_assert(false,                                                     \
                  "unsupported threadblock shape (%dx%dx%d) and warp shape " \
                  "(%dx%dx%d)",                                              \
                  threadblock_shape.m(), threadblock_shape.n(),              \
                  threadblock_shape.k(), warp_shape.m(), warp_shape.n(),     \
                  warp_shape.k());
    using ElementOutput = float;
    using ElementAccumulator = int32_t;
    using ElementBias = float;
    using ElementCompute = float;
    using NonlineMode = megdnn::param_enumv::ConvBias::NonlineMode;
    switch (nonlinear_mode) {
        case NonlineMode::IDENTITY: {
            using EpilogueOp =
                    cutlass::epilogue::thread::BiasAddLinearCombination<
                            ElementOutput, 1, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma};
            DISPATCH_KERNEL;
        }
        case NonlineMode::RELU: {
            using EpilogueOp =
                    cutlass::epilogue::thread::BiasAddLinearCombinationRelu<
                            ElementOutput, 1, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, 0};
            DISPATCH_KERNEL;
        }
        case NonlineMode::H_SWISH: {
            using EpilogueOp =
                    cutlass::epilogue::thread::BiasAddLinearCombinationHSwish<
                            ElementOutput, 1, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, scale};
            DISPATCH_KERNEL;
        }
        default:
            megdnn_assert(false,
                          "unsupported nonlinear mode for conv bias operator");
    }
#undef DISPATCH_KERNEL_WITH_TILE_SHAPE
#undef DISPATCH_KERNEL
}
#endif

#define INST(need_load_from_const_mem)                                   \
    template void megdnn::cuda::cutlass_wrapper::                        \
            do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4_nchw<         \
                    need_load_from_const_mem>(                           \
                    const int8_t* d_src, const int8_t* d_filter,         \
                    const float* d_bias, const float* d_z, float* d_dst, \
                    int* workspace, const convolution::ConvParam& param, \
                    uint32_t nonlinear_mode, float alpha, float beta,    \
                    float gamma, float scale,                            \
                    const GemmCoord& threadblock_shape,                  \
                    const GemmCoord& warp_shape, int stages,             \
                    cudaStream_t stream);
INST(true);
INST(false);
#undef INST

/* ====== cutlass kernel wrapper for nchw4 layout and nchw32 output ====== */
#if MEGDNN_TEGRA_X1
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4_ncdiv32hw32(
                const int8_t* /* d_src */, const int8_t* /* d_filter */,
                const int32_t* /* d_bias */, const int8_t* /* d_z */,
                int8_t* /* d_dst */, int* /* workspace */,
                const convolution::ConvParam& /* param */,
                uint32_t /* nonlinear_mode */, float /* alpha */,
                float /* beta */, float /* gamma */, float /* scale */,
                const GemmCoord& /* threadblock_shape */,
                const GemmCoord& /* warp_shape */, int /* stages */,
                cudaStream_t /* stream */) {}
#else
template <bool NeedLoadFromConstMem>
void megdnn::cuda::cutlass_wrapper::
        do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4_ncdiv32hw32(
                const int8_t* d_src, const int8_t* d_filter,
                const int32_t* d_bias, const int8_t* d_z, int8_t* d_dst,
                int* workspace, const convolution::ConvParam& param,
                uint32_t nonlinear_mode, float alpha, float beta, float gamma,
                float scale, const GemmCoord& threadblock_shape,
                const GemmCoord& warp_shape, int stages, cudaStream_t stream) {
#define DISPATCH_KERNEL_WITH_TILE_SHAPE(threadblock_m_, threadblock_n_,        \
                                        threadblock_k_, warp_m_, warp_n_,      \
                                        warp_k_, stages_, aligned_)            \
    if (threadblock_shape.m() == threadblock_m_ &&                             \
        threadblock_shape.n() == threadblock_n_ &&                             \
        threadblock_shape.k() == threadblock_k_ &&                             \
        warp_shape.m() == warp_m_ && warp_shape.n() == warp_n_ &&              \
        warp_shape.k() == warp_k_ && stages == stages_) {                      \
        using ThreadBlockShape =                                               \
                cutlass::gemm::GemmShape<threadblock_m_, threadblock_n_,       \
                                         threadblock_k_>;                      \
        using WarpShape = cutlass::gemm::GemmShape<warp_m_, warp_n_, warp_k_>; \
        using InstructionShape = cutlass::gemm::GemmShape<1, 1, 4>;            \
        using Convolution = cutlass::conv::device::Convolution<                \
                int8_t, cutlass::layout::TensorNCxHWx<4>, int8_t,              \
                cutlass::layout::TensorCxRSKx<4>, ElementOutput,               \
                cutlass::layout::TensorNCxHWx<32>, int32_t,                    \
                cutlass::layout::TensorNCxHWx<32>, int32_t,                    \
                cutlass::conv::ConvType::kConvolution,                         \
                cutlass::arch::OpClassSimt, cutlass::arch::Sm61,               \
                ThreadBlockShape, WarpShape, InstructionShape, EpilogueOp,     \
                cutlass::conv::threadblock::                                   \
                        ConvolutionFpropNCxHWxThreadblockSwizzle,              \
                stages_, 4, aligned_, NeedLoadFromConstMem>;                   \
        typename Convolution::ConvolutionParameter conv_param(                 \
                param.n, param.hi, param.wi, param.ci, param.co, param.fh,     \
                param.fw, param.ho, param.wo, param.ph, param.pw, param.sh,    \
                param.sw, 1, 1, cutlass::conv::Mode::kCrossCorrelation);       \
        return cutlass_convolution_wrapper<Convolution>(                       \
                d_src, d_filter, d_bias, d_z, d_dst, workspace, conv_param,    \
                epilogue, stream);                                             \
    }
#define DISPATCH_KERNEL                                                      \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 128, 32, 64, 32, 32, 2, 16);        \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 64, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 128, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(128, 32, 32, 64, 32, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 128, 32, 32, 64, 32, 2, 16);         \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 64, 32, 64, 32, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 64, 32, 32, 64, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(64, 32, 32, 64, 32, 32, 2, 16);          \
    DISPATCH_KERNEL_WITH_TILE_SHAPE(32, 32, 32, 32, 32, 32, 2, 16);          \
    megdnn_assert(false,                                                     \
                  "unsupported threadblock shape (%dx%dx%d) and warp shape " \
                  "(%dx%dx%d)",                                              \
                  threadblock_shape.m(), threadblock_shape.n(),              \
                  threadblock_shape.k(), warp_shape.m(), warp_shape.n(),     \
                  warp_shape.k());
    using ElementOutput = int8_t;
    using ElementAccumulator = int32_t;
    using ElementBias = int32_t;
    using ElementCompute = float;
    using NonlineMode = megdnn::param_enumv::ConvBias::NonlineMode;
    switch (nonlinear_mode) {
        case NonlineMode::IDENTITY: {
            using EpilogueOp =
                    cutlass::epilogue::thread::BiasAddLinearCombinationClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma};
            DISPATCH_KERNEL;
        }
        case NonlineMode::RELU: {
            using EpilogueOp = cutlass::epilogue::thread::
                    BiasAddLinearCombinationReluClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, 0};
            DISPATCH_KERNEL;
        }
        case NonlineMode::H_SWISH: {
            using EpilogueOp = cutlass::epilogue::thread::
                    BiasAddLinearCombinationHSwishClamp<
                            ElementOutput, 4, ElementAccumulator, ElementBias,
                            ElementCompute>;
            typename EpilogueOp::Params epilogue{alpha, beta, gamma, scale};
            DISPATCH_KERNEL;
        }
        default:
            megdnn_assert(false,
                          "unsupported nonlinear mode for conv bias operator");
    }
#undef DISPATCH_KERNEL_WITH_TILE_SHAPE
#undef DISPATCH_KERNEL
}
#endif

#define INST(need_load_from_const_mem)                                       \
    template void megdnn::cuda::cutlass_wrapper::                            \
            do_conv_bias_int8_implicit_gemm_dp4a_ncdiv4hw4_ncdiv32hw32<      \
                    need_load_from_const_mem>(                               \
                    const int8_t* d_src, const int8_t* d_filter,             \
                    const int32_t* d_bias, const int8_t* d_z, int8_t* d_dst, \
                    int* workspace, const convolution::ConvParam& param,     \
                    uint32_t nonlinear_mode, float alpha, float beta,        \
                    float gamma, float scale,                                \
                    const GemmCoord& threadblock_shape,                      \
                    const GemmCoord& warp_shape, int stages,                 \
                    cudaStream_t stream);
INST(true);
INST(false);
#undef INST

// vim: syntax=cuda.doxygen
