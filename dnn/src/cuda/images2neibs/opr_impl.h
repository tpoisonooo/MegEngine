/**
 * \file dnn/src/cuda/images2neibs/opr_impl.h
 * MegEngine is Licensed under the Apache License, Version 2.0 (the "License")
 *
 * Copyright (c) 2014-2021 Megvii Inc. All rights reserved.
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT ARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 */
#pragma once
#include "megdnn/oprs.h"

#include <cuda_runtime_api.h>

namespace megdnn {
namespace cuda {

class Images2NeibsForwardImpl: public Images2NeibsForward {
    public:
        using Images2NeibsForward::Images2NeibsForward;
        void exec(_megdnn_tensor_in src,
                _megdnn_tensor_out dst,
                _megdnn_workspace workspace) override;
        size_t get_workspace_in_bytes(const TensorLayout &,
                const TensorLayout &) override {
            return 0;
        }
};

class Images2NeibsBackwardImpl: public Images2NeibsBackward {
    public:
        using Images2NeibsBackward::Images2NeibsBackward;
        void exec(_megdnn_tensor_in diff,
                _megdnn_tensor_out grad,
                _megdnn_workspace workspace) override;
        size_t get_workspace_in_bytes(const TensorLayout &,
                const TensorLayout &) override {
            return 0;
        }
};

} // namespace cuda
} // namespace megdnn
// vim: syntax=cpp.doxygen
