# -*- coding: utf-8 -*-
# MegEngine is Licensed under the Apache License, Version 2.0 (the "License")
#
# Copyright (c) 2014-2021 Megvii Inc. All rights reserved.
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT ARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
import io
import os
import platform

import numpy as np
import pytest

import megengine as mge
import megengine.utils.comp_graph_tools as cgtools
from megengine import Tensor
from megengine.distributed.helper import get_device_count_by_fork
from megengine.jit import trace
from megengine.module import Module
from megengine.module.external import TensorrtRuntimeSubgraph


class MyModule(Module):
    def __init__(self, data):
        from megengine.module.external import CambriconSubgraph

        super().__init__()
        self.cambricon = CambriconSubgraph(data, "subnet0", True)

    def forward(self, inputs):
        out = self.cambricon(inputs)
        return out


@pytest.mark.skip(reason="cambricon unimplemented")
def test_cambricon_module():
    model = "CambriconRuntimeOprTest.MutableBatchSize.mlu"
    model = os.path.join(os.path.dirname(__file__), model)
    with open(model, "rb") as f:
        data = f.read()
        m = MyModule(data)
        inp = Tensor(
            np.random.normal((1, 64, 32, 32)).astype(np.float16), device="cambricon0"
        )

        def inference(inps):
            pred = m(inps)
            return pred

        pred = inference([inp])


