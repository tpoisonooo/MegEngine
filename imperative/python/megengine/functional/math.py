# -*- coding: utf-8 -*-
# MegEngine is Licensed under the Apache License, Version 2.0 (the "License")
#
# Copyright (c) 2014-2021 Megvii Inc. All rights reserved.
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT ARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
import collections
import math
from typing import Optional, Sequence, Tuple, Union

from ..core._imperative_rt.core2 import apply
from ..core._trace_option import use_symbolic_shape
from ..core.ops import builtin
from ..core.ops.special import Const
from ..core.tensor import utils
from ..tensor import Tensor
from .debug_param import get_execution_strategy
from .elemwise import clip, exp, log, log1p
from .tensor import broadcast_to, concat, expand_dims, reshape, squeeze

__all__ = [
    "argmax",
    "argmin",
    "argsort",
    "dot",
    "isinf",
    "isnan",
    "matinv",
    "matmul",
    "max",
    "mean",
    "min",
    "norm",
    "normalize",
    "prod",
    "sign",
    "sort",
    "std",
    "sum",
    "svd",
    "topk",
    "var",
]


def isnan(inp: Tensor) -> Tensor:
    r"""
    Returns a new tensor representing if each element is ``NaN`` or not.

    :param inp: input tensor.
    :return: result tensor.

    Examples:

    .. testcode::

        from megengine import tensor
        import megengine.functional as F

        x = tensor([1, float("nan"), 0])
        print(F.isnan(x).numpy())

    Outputs:

    .. testoutput::

        [False  True False]

    """
    return inp != inp


def isinf(inp: Tensor) -> Tensor:
    r"""
    Returns a new tensor representing if each element is ``Inf`` or not.

    :param inp: input tensor.
    :return: result tensor.

    Examples:

    .. testcode::

        from megengine import tensor
        import megengine.functional as F

        x = tensor([1, float("inf"), 0])
        print(F.isinf(x).numpy())

    Outputs:

    .. testoutput::

        [False  True False]

    """
    return abs(inp).astype("float32") == float("inf")


def sign(inp: Tensor):
    r"""
    Returns a new tensor representing the sign of each element in input tensor.

    :param: input tensor.
    :return: the sign of input tensor.

    Examples:

    .. testcode::

        from megengine import tensor
        import megengine.functional as F

        x = tensor([1, -1, 0])
        print(F.sign(x).numpy())

    Outputs:

    .. testoutput::

        [ 1 -1  0]

    """
    return (inp > 0).astype(inp.dtype) - (inp < 0).astype(inp.dtype)


def sum(
    inp: Tensor,
    axis: Optional[Union[int, Sequence[int]]] = None,
    keepdims: bool = False,
) -> Tensor:
    r"""
    Returns the sum of input tensor along given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced.
        Default: None
    :param keepdims: whether the output tensor has axis retained or not.
        Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(1, 7, dtype=np.int32).reshape(2, 3))
        out = F.sum(x)
        print(out.numpy())

    Outputs:

    .. testoutput::

        21

    """
    return inp.sum(axis=axis, keepdims=keepdims)


def prod(
    inp: Tensor, axis: Optional[Union[int, Sequence[int]]] = None, keepdims=False
) -> Tensor:
    r"""
    Returns the product of input tensor along given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(1, 7, dtype=np.int32).reshape(2, 3))
        out = F.prod(x)
        print(out.numpy())

    Outputs:

    .. testoutput::

        720

    """
    return inp.prod(axis=axis, keepdims=keepdims)


def mean(
    inp: Tensor,
    axis: Optional[Union[int, Sequence[int]]] = None,
    keepdims: bool = False,
) -> Tensor:
    """
    Returns the mean value of input tensor along
    given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(1, 7, dtype=np.int32).reshape(2, 3))
        out = F.mean(x)
        print(out.numpy())

    Outputs:

    .. testoutput::

        3.5

    """
    return inp.mean(axis=axis, keepdims=keepdims)


def var(
    inp: Tensor,
    axis: Optional[Union[int, Sequence[int]]] = None,
    keepdims: bool = False,
) -> Tensor:
    """
    Returns the variance value of input tensor along
    given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        data = tensor(np.arange(1, 7, dtype=np.float32).reshape(2, 3))
        out = F.var(data)
        print(out.numpy().round(decimals=4))

    Outputs:

    .. testoutput::

        2.9167
    """
    if axis is None:
        m = mean(inp, axis=axis, keepdims=False)
    else:
        m = mean(inp, axis=axis, keepdims=True)
    v = inp - m
    return mean(v ** 2, axis=axis, keepdims=keepdims)


def std(
    inp: Tensor,
    axis: Optional[Union[int, Sequence[int]]] = None,
    keepdims: bool = False,
) -> Tensor:
    """
    Returns the standard deviation of input tensor along
    given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        data = tensor(np.arange(1, 7, dtype=np.float32).reshape(2, 3))
        out = F.std(data, axis=1)
        print(out.numpy().round(decimals=4))

    Outputs:

    .. testoutput::

        [0.8165 0.8165]
    """
    return var(inp, axis=axis, keepdims=keepdims) ** 0.5


def min(
    inp: Tensor,
    axis: Optional[Union[int, Sequence[int]]] = None,
    keepdims: bool = False,
) -> Tensor:
    r"""
    Returns the min value of input tensor along
    given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(1, 7, dtype=np.int32).reshape(2,3))
        out = F.min(x)
        print(out.numpy())

    Outputs:

    .. testoutput::

        1

    """
    return inp.min(axis=axis, keepdims=keepdims)


def max(
    inp: Tensor,
    axis: Optional[Union[int, Sequence[int]]] = None,
    keepdims: bool = False,
) -> Tensor:
    r"""
    Returns the max value of the input tensor along
    given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(1, 7, dtype=np.int32).reshape(2,3))
        out = F.max(x)
        print(out.numpy())

    Outputs:

    .. testoutput::

        6

    """
    return inp.max(axis=axis, keepdims=keepdims)


def norm(
    inp: Tensor, ord: float = None, axis: int = None, keepdims=False,
):
    """
    Calculates ``p``-norm of input tensor along
    given axis.

    :param inp: input tensor.
    :param ord: power of value applied to inp. Default: 2
    :param axis: dimension to reduce. If None, input must be a vector. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(-3, 3, dtype=np.float32))
        out = F.norm(x)
        print(out.numpy().round(decimals=4))

    Outputs:

    .. testoutput::

        4.3589

    """
    if axis is None:
        if inp.ndim != 1:
            raise TypeError("axis is required unless input is a vector")
    if ord is None:
        ord = 2
    if ord == 0:
        return sum(inp != 0, axis=axis, keepdims=keepdims)
    if ord == math.inf:
        return max(abs(inp))
    if ord == -math.inf:
        return min(abs(inp))
    return sum(abs(inp) ** ord, axis=axis, keepdims=keepdims) ** (1.0 / ord)


def argmin(
    inp: Tensor,
    axis: Optional[Union[int, Sequence[int]]] = None,
    keepdims: bool = False,
) -> Tensor:
    r"""
    Returns the indices of the minimum values along
    given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(1, 7, dtype=np.int32).reshape(2,3))
        out = F.argmin(x)
        print(out.numpy())

    Outputs:

    .. testoutput::

        0

    """
    if isinstance(axis, collections.abc.Iterable):
        axis = list(axis)
        axis.sort(reverse=True)

        for ai in axis:
            op = builtin.Argmin(axis=ai)
            (inp,) = apply(op, inp)

            if not keepdims:
                inp = squeeze(inp, ai)

        return inp

    if axis is None:
        assert not keepdims, "can not set axis=None and keepdims=True"
        inp = inp.flatten()
        axis = 0

    op = builtin.Argmin(axis=axis)
    (result,) = apply(op, inp)
    if not keepdims:
        result = squeeze(result, axis)
    return result


def argmax(
    inp: Tensor,
    axis: Optional[Union[int, Sequence[int]]] = None,
    keepdims: bool = False,
) -> Tensor:
    r"""
    Returns the indices of the maximum values along
    given axis. If axis is a list of dimensions,
    reduce over all of them.

    :param inp: input tensor.
    :param axis: dimension to reduce. If None, all dimensions will be reduced. Default: None
    :param keepdims: whether the output tensor has axis retained or not. Default: False
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(1, 7, dtype=np.int32).reshape(2,3))
        out = F.argmax(x)
        print(out.numpy())

    Outputs:

    .. testoutput::

        5

    """
    if isinstance(axis, collections.abc.Iterable):
        axis = list(axis)
        axis.sort(reverse=True)

        for ai in axis:
            op = builtin.Argmax(axis=ai)
            (inp,) = apply(op, inp)

            if not keepdims:
                inp = squeeze(inp, ai)

        return inp

    if axis is None:
        assert not keepdims, "can not set axis=None and keepdims=True"
        inp = inp.flatten()
        axis = 0

    op = builtin.Argmax(axis=axis)
    (result,) = apply(op, inp)
    if not keepdims:
        result = squeeze(result, axis)
    return result


def normalize(
    inp: Tensor, ord: float = None, axis: int = None, eps: float = 1e-12,
) -> Tensor:
    r"""
    Performs :math:`L_p` normalization of input tensor along
    given axis.

    For a tensor of shape :math:`(n_0, ..., n_{dim}, ..., n_k)`, each
    :math:`n_{dim}` -element vector :math:`v` along dimension :attr:`axis` is transformed as:

    .. math::
        v = \frac{v}{\max(\lVert v \rVert_p, \epsilon)}.

    :param inp: input tensor.
    :param ord: power of value applied to input tensor. Default: 2
    :param axis: dimension to reduce.If None, input must be a vector. Default: None
    :param eps: a small value to avoid division by zero. Default: 1e-12
    :return: normalized output tensor.
    """
    if axis is None:
        return inp / clip(norm(inp, ord, axis), lower=eps)
    else:
        return inp / clip(norm(inp, ord, axis, keepdims=True), lower=eps)


def argsort(inp: Tensor, descending: bool = False) -> Tensor:
    r"""
    Returns the indices that would sort the input tensor.

    :param inp: input tensor. If it's 2d, the result would be array of indices show how to sort each row in the input tensor.
    :param descending: sort in descending order, where the largest comes first. Default: False
    :return: indices of int32 indicates how to sort the input.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.array([1,2], dtype=np.float32))
        indices = F.argsort(x)
        print(indices.numpy())

    Outputs:

    .. testoutput::

        [0 1]

    """
    assert len(inp.shape) <= 2, "Input should be 1d or 2d"
    if descending:
        order = "descending"
    else:
        order = "ascending"

    op = builtin.Argsort(order=order)
    if len(inp.shape) == 1:
        inp = inp.reshape(1, -1)
        _, result = apply(op, inp)
        return result[0]
    _, result = apply(op, inp)
    return result


def sort(inp: Tensor, descending: bool = False) -> Tuple[Tensor, Tensor]:
    r"""
    Returns sorted tensor and the indices would sort the input tensor.

    :param inp: input tensor. If it's 2d, the result would be sorted by row.
    :param descending: sort in descending order, where the largest comes first. Default: False
    :return: tuple of two tensors `(sorted_tensor, indices_of_int32)`.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.array([1,2], dtype=np.float32))
        out, indices = F.sort(x)
        print(out.numpy())

    Outputs:

    .. testoutput::

        [1. 2.]

    """
    assert len(inp.shape) <= 2, "Input should be 1d or 2d"
    if descending:
        order = "descending"
    else:
        order = "ascending"

    op = builtin.Argsort(order=order)
    if len(inp.shape) == 1:
        inp = inp.reshape(1, -1)
        tns, ind = apply(op, inp)
        return tns[0], ind[0]
    tns, ind = apply(op, inp)
    return tns, ind


def topk(
    inp: Tensor,
    k: int,
    descending: bool = False,
    kth_only: bool = False,
    no_sort: bool = False,
) -> Tuple[Tensor, Tensor]:
    r"""
    Selects the ``Top-K`` (by default) smallest elements of 2d matrix by row.

    :param inp: input tensor. If input tensor is 2d, each row will be sorted.
    :param k: number of elements needed.
    :param descending: if True, return the largest elements instead. Default: False
    :param kth_only: if True, only the k-th element will be returned. Default: False
    :param no_sort: if True, the returned elements can be unordered. Default: False
    :return: tuple of two tensors `(topk_tensor, indices_of_int32)`.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import  megengine.functional as F

        x = tensor(np.array([2, 4, 6, 8, 7, 5, 3, 1], dtype=np.float32))
        top, indices = F.topk(x, 5)
        print(top.numpy(), indices.numpy())

    Outputs:

    .. testoutput::

        [1. 2. 3. 4. 5.] [7 0 6 1 5]

    """
    if descending:
        inp = -inp

    if kth_only:
        mode = "kth_only"
    elif no_sort:
        mode = "value_idx_nosort"
    else:
        mode = "value_idx_sorted"
    op = builtin.TopK(mode=mode)

    if not isinstance(k, Tensor):
        (k,) = Const(k, dtype="int32", device=inp.device)()

    if len(inp.shape) == 1:
        inp = inp.reshape(1, -1)
        res = apply(op, inp, k)
        if kth_only:
            tns = res[0]
        else:
            tns, ind = res[0][0], res[1][0]
    else:
        res = apply(op, inp, k)
        if kth_only:
            tns = res
        else:
            tns, ind = res[0], res[1]

    if descending:
        tns = -tns
    return tns, ind


def matinv(inp: Tensor) -> Tensor:
    """
    Computes the inverse of a batch of matrices; input must has shape [..., n, n].

    :param inp: input tensor.
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        data = tensor([[1.0, 0.0], [1.0, 1.0]])
        out = F.matinv(data)
        print(out.numpy())

    Outputs:

    .. testoutput::

        [[ 1.  0.]
         [-1.  1.]]

    """

    (result,) = apply(builtin.MatrixInverse(), inp)
    return result


def matmul(
    inp1: Tensor,
    inp2: Tensor,
    transpose_a=False,
    transpose_b=False,
    compute_mode="default",
    format="default",
) -> Tensor:
    """
    Performs a matrix multiplication of the matrices ``inp1`` and ``inp2``.

    With different inputs dim, this function behaves differently:

    - Both 1-D tensor, simply forward to ``dot``.
    - Both 2-D tensor, normal matrix multiplication.
    - If one input tensor is 1-D, matrix vector multiplication.
    - If at least one tensor are 3-dimensional or >3-dimensional, the other tensor should have dim >= 2,
         the batched matrix-matrix is returned, and the tensor with smaller dimension will be broadcasted.
         For example:

      - inp1: `(n, k, m)`, inp2: `(n, m, p)`, return: `(n, k, p)`
      - inp1: `(n, k, m)`, inp2: `(m, p)`, return: `(n, k, p)`
      - inp1: `(n, j, k, m)`, inp2: `(n, j, m, p)`, return: `(n, j, k, p)`

    :param inp1: first matrix to be multiplied.
    :param inp2: second matrix to be multiplied.
    :return: output tensor.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        data1 = tensor(np.arange(0, 6, dtype=np.float32).reshape(2, 3))
        data2 = tensor(np.arange(0, 6, dtype=np.float32).reshape(3, 2))
        out = F.matmul(data1, data2)
        print(out.numpy())

    Outputs:

    .. testoutput::

        [[10. 13.]
         [28. 40.]]

    """
    remove_row, remove_col = False, False
    inp1, inp2 = utils.convert_inputs(inp1, inp2)

    dim1, dim2 = inp1.ndim, inp2.ndim
    # handle dim=1 cases, dot and matrix-vector multiplication
    if dim1 == 1 and dim2 == 1:
        return dot(inp1, inp2)
    # the underlying matmul op requires input dims to be at least 2
    if dim1 == 1:
        inp1 = expand_dims(inp1, 0)
        dim1 = 2
        remove_row = True
    if dim2 == 1:
        inp2 = expand_dims(inp2, 1)
        dim2 = 2
        remove_col = True

    batch_shape = None
    shape1 = inp1.shape
    shape2 = inp2.shape

    maxdim = dim1 if dim1 > dim2 else dim2
    if dim1 >= 3 or dim2 >= 3:
        if use_symbolic_shape():
            if dim1 > dim2:
                shape2 = concat([shape1[:-2], shape2[-2:]])
                inp2 = broadcast_to(inp2, shape2)
            if dim1 < dim2:
                shape1 = concat([shape2[:-2], shape1[-2:]])
                inp1 = broadcast_to(inp1, shape1)
            if maxdim > 3:
                batch_shape = shape1[:-2]
                # compress inputs to 3d
                (inp1,) = apply(
                    builtin.Reshape(), inp1, concat([prod(shape1[:-2]), shape1[-2:]])
                )
                (inp2,) = apply(
                    builtin.Reshape(), inp2, concat([prod(shape2[:-2]), shape2[-2:]])
                )
        else:
            if dim1 > dim2:
                shape2 = shape1[:-2] + shape2[-2:]
                inp2 = broadcast_to(inp2, shape2)
            if dim1 < dim2:
                shape1 = shape2[:-2] + shape1[-2:]
                inp1 = broadcast_to(inp1, shape1)
            if maxdim > 3:
                batch_shape = shape1[:-2]
                # compress inputs to 3d
                inp1 = inp1.reshape((-1, shape1[-2], shape1[-1]))
                inp2 = inp2.reshape((-1, shape2[-2], shape2[-1]))

        op = builtin.BatchedMatrixMul(
            transposeA=transpose_a,
            transposeB=transpose_b,
            compute_mode=compute_mode,
            format=format,
            strategy=get_execution_strategy(),
        )
    else:
        op = builtin.MatrixMul(
            transposeA=transpose_a,
            transposeB=transpose_b,
            compute_mode=compute_mode,
            format=format,
            strategy=get_execution_strategy(),
        )

    (result,) = apply(op, inp1, inp2)
    if maxdim > 3:
        if use_symbolic_shape():
            (result,) = apply(
                builtin.Reshape(), result, concat([batch_shape, result.shape[-2:]])
            )
        else:
            result = result.reshape(batch_shape + result.shape[-2:])
    if remove_row:
        result = squeeze(result, axis=-2)
    if remove_col:
        result = squeeze(result, axis=-1)
    return result


def dot(inp1: Tensor, inp2: Tensor) -> Tensor:
    """
    Computes dot-product of two vectors ``inp1`` and ``inp2``.
    inputs must be 1-dimensional or scalar. A scalar input is automatically broadcasted.
    Refer to :func:`~.matmul` for more general usage.

    :param inp1: first vector.
    :param inp2: second vector.
    :return: output value.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        data1 = tensor(np.arange(0, 6, dtype=np.float32))
        data2 = tensor(np.arange(0, 6, dtype=np.float32))
        out = F.dot(data1, data2)
        print(out.numpy())

    Outputs:

    .. testoutput::

        55.

    """
    op = builtin.Dot()
    inp1, inp2 = utils.convert_inputs(inp1, inp2)
    assert (
        inp1.ndim <= 1 and inp2.ndim <= 1
    ), "Input tensors for dot must be 1-dimensional or scalar"
    (result,) = apply(op, inp1, inp2)
    utils.setscalar(result)
    return result


def svd(inp: Tensor, full_matrices=False, compute_uv=True) -> Tensor:
    """
    Computes the singular value decompositions of input matrix.

    :param inp: input matrix, must has shape `[..., M, N]`.
    :return: output matrices, `(U, sigma, V)`.

    Examples:

    .. testcode::

        import numpy as np
        from megengine import tensor
        import megengine.functional as F

        x = tensor(np.arange(0, 6, dtype=np.float32).reshape(2,3))
        _, y, _ = F.svd(x)
        print(y.numpy().round(decimals=3))

    Outputs:

    .. testoutput::

        [7.348 1.   ]

    """
    op = builtin.SVD(full_matrices=full_matrices, compute_uv=compute_uv)
    U, sigma, V = apply(op, inp)
    return U, sigma, V
