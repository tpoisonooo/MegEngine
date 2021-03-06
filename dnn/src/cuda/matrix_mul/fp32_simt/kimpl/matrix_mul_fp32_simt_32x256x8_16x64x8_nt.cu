#if __CUDACC_VER_MAJOR__ > 9 || (__CUDACC_VER_MAJOR__ == 9 && __CUDACC_VER_MINOR__ >= 2)
// generated by gen_cutlass_matrix_mul_kern_impls.py
// ignore warning of cutlass
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wstrict-aliasing"
#pragma GCC diagnostic ignored "-Wuninitialized"
#pragma GCC diagnostic ignored "-Wmaybe-uninitialized"
#include "src/cuda/matrix_mul/fp32_simt/matrix_mul_float_simt_cutlass_wrapper.cuinl"

using LayoutA = cutlass::layout::RowMajor;
using LayoutB = cutlass::layout::ColumnMajor;
using ThreadBlockShape = cutlass::gemm::GemmShape<32, 256, 8>;
using WarpShape = cutlass::gemm::GemmShape<16, 64, 8>;
using InstructionShape = cutlass::gemm::GemmShape<1, 1, 1>;
using EpilogueOp = cutlass::epilogue::thread::LinearCombination<float, 1, float, float>;
using Gemm = cutlass::gemm::device::Gemm<
    float, LayoutA, 
    float, LayoutB, 
    float, cutlass::layout::RowMajor, float, 
    cutlass::arch::OpClassSimt, cutlass::arch::Sm50, 
    ThreadBlockShape, WarpShape, InstructionShape, EpilogueOp, 
    cutlass::gemm::threadblock::GemmIdentityThreadblockSwizzle<>, 
    2>;
template void megdnn::cuda::cutlass_wrapper::cutlass_matrix_mul_wrapper<Gemm>(
        const typename Gemm::ElementA* d_A, size_t lda, 
        const typename Gemm::ElementB* d_B, size_t ldb,  
        typename Gemm::ElementC* d_C, size_t ldc,  
        int* workspace, 
        cutlass::gemm::GemmCoord const& problem_size,   
        typename Gemm::EpilogueOutputOp::Params const& epilogue, 
        cudaStream_t stream, int split_k_slices);

#pragma GCC diagnostic pop
#endif
