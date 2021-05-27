#if __CUDACC_VER_MAJOR__ > 9 || (__CUDACC_VER_MAJOR__ == 9 && __CUDACC_VER_MINOR__ >= 2)
// generated by gen_cutlass_gemv_batched_strided_kern_impls.py
// ignore warning of cutlass
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wstrict-aliasing"
#include "src/cuda/matrix_mul/fp32_simt_gemv/matrix_mul_float_simt_gemv_batched_strided_cutlass_wrapper.cuinl"

using ThreadBlockShape = cutlass::gemm::GemmShape<1, 32, 64>;
using ThreadShape = cutlass::gemm::GemmShape<1, 4, 2>;
using GemvKernel = cutlass::gemm::kernel::DefaultGemv<
    ThreadBlockShape, 
    ThreadShape, 
    float, cutlass::layout::RowMajor, 
    float, cutlass::layout::RowMajor, 
    float, cutlass::layout::RowMajor>;
template void megdnn::cuda::cutlass_wrapper::
    cutlass_vector_matrix_mul_batched_strided_wrapper<GemvKernel>(
        BatchedGemmCoord const& problem_size,
        const typename GemvKernel::ElementA* d_A, size_t lda, size_t batch_stride_a, 
        const typename GemvKernel::ElementB* d_B, size_t ldb, size_t batch_stride_b, 
        typename GemvKernel::ElementCD* d_C, size_t ldc, size_t batch_stride_c,
        cudaStream_t stream);

#pragma GCC diagnostic pop
#endif
