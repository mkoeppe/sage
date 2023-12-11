from sage.libs.cmr.cmr cimport *

from .matrix_sparse cimport Matrix_sparse

cdef class Matrix_cmr_sparse(Matrix_sparse):
    pass

# cdef class Matrix_cmr_double_sparse(Matrix_cmr_sparse):
#     pass

# cdef class Matrix_cmr_int_sparse(Matrix_cmr_sparse):
#     pass

cdef class Matrix_cmr_chr_sparse(Matrix_cmr_sparse):

    cdef CMR_CHRMAT *_mat

    cdef _init_from_dict(self, dict d, int nrows, int ncols)
