/**
 * \file dnn/src/cuda/indexing_multi_axis_vec/kern.cuh
 * MegEngine is Licensed under the Apache License, Version 2.0 (the "License")
 *
 * Copyright (c) 2014-2021 Megvii Inc. All rights reserved.
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT ARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 */

#pragma once

#include "megdnn/arch.h"
#include "src/cuda/utils.cuh"
#include "src/cuda/int_fastdiv.cuh"
#include "src/cuda/error_info.cuh"

namespace megdnn {
namespace cuda {
namespace indexing_multi_axis_vec {

    //! AxisIndexer equiv in kernel
    struct KAxisIndexer {
        int stride;
        const int *ptr;
    };

    //! param for gen_offset_base
    template<int nidx>
    struct GenOffsetBaseParam {
        uint32_t size;  //!< number of outputs; also size of each index
        int *output;    //!< output ptr
        KAxisIndexer indexer[nidx];
        uint32_t data_shape[nidx];
        int data_stride[nidx];

        void* error_tracker;
        megcore::AsyncErrorInfo* error_info;
    };

    //! tensor layout for fast offset computing
    template<int ndim>
    struct FastLayout {
        int stride[ndim];
#ifdef WIN32
        Uint32Fastdiv shape[ndim];
#else
        Uint32Fastdiv shape[ndim - 1];
#endif
    };

    //! param for apply_opr
    template<typename ctype, int ndim>
    struct ApplyOprParam {
        uint32_t tot_size;    //!< total output size

        //! offset array generated by gen_offset_base for first output axis
        const int *offset_base;
        ctype *data, *value;

        int idx_axis;

        int value_stride;

        //! iterate on value, with strides from corresponding axes on data
        FastLayout<ndim> value_ly_on_data;
    };

    //! generate offset bases for first axis in the output
    template<int nidx>
    void gen_offset_base(const GenOffsetBaseParam<nidx> &param,
            cudaStream_t stream);

    struct OprAtomicIncr {
#if MEGDNN_CC_CUDA
        template<typename ctype>
        __device__ static void apply(ctype &data, ctype value) {
            atomicAdd(&data, value);
        }
#endif
    };

    /*!
     * \brief forward kernel: copy data to value
     * \tparam ndim numer of axes except axis_0 in data,
     *      range from 0 to max_ndim - 1
     */
    template<typename ctype, int ndim, class Opr>
    void apply_opr(const ApplyOprParam<ctype, ndim> &param,
            cudaStream_t stream);

} // namespace indexing_multi_axis_vec
} // namespace cuda
} // namespace megdnn

// vim: ft=cpp syntax=cpp.doxygen

