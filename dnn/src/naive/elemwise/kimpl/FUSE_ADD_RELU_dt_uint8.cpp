// generated by gen_elemwise_kern_impls.py
#define KERN_IMPL_MODE(cb) MEGDNN_ELEMWISE_MODE_ENABLE(FUSE_ADD_RELU, cb)
#define KERN_IMPL_ARITY 2
#define KERN_IMPL_CTYPE dt_uint8
#include "../kern_impl.inl"
