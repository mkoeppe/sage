r"""
Sparse Matrices with CMR
"""

from libc.stdint cimport SIZE_MAX

from cysignals.signals cimport sig_on, sig_off

from sage.rings.integer cimport Integer

from .args cimport MatrixArgs_init


cdef class Matrix_cmr_sparse(Matrix_sparse):
    pass


cdef class Matrix_cmr_chr_sparse(Matrix_cmr_sparse):
    r"""
    EXAMPLES::

        sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
        sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 2, 3, sparse=True),
        ....:                           [[1, 2, 3], [4, 0, 6]]); M
        [1 2 3]
        [4 0 6]
        sage: M.dict()
        {(0, 0): 1, (0, 1): 2, (0, 2): 3, (1, 0): 4, (1, 2): 6}

    Matrices of this class are always immutable::

        sage: M.is_immutable()
        True
        sage: copy(M) is M
        True
        sage: deepcopy(M) is M
        True

    This matrix class can only store very small integers::

        sage: Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 1, 3, sparse=True), [-128, 0, 127])
        [-128    0  127]
        sage: Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 1, 3, sparse=True), [126, 127, 128])
        Traceback (most recent call last):
        ...
        OverflowError: value too large to convert to char

    Arithmetic does not preserve the implementation class (even if the numbers would fit)::

        sage: M2 = M + M; M2
        [ 2  4  6]
        [ 8  0 12]
        sage: type(M2)
        <class 'sage.matrix.matrix_integer_sparse.Matrix_integer_sparse'>
        sage: M * 100
        [100 200 300]
        [400   0 600]
    """
    def __init__(self, parent, entries=None, copy=None, bint coerce=True):
        r"""
        TESTS::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 2, 3, sparse=True),
            ....:                           [[1, 2, 3], [4, 0, 6]]); M
            [1 2 3]
            [4 0 6]
            sage: TestSuite(M).run()
        """
        cdef dict d
        ma = MatrixArgs_init(parent, entries)
        d = ma.dict(coerce)
        self._init_from_dict(d, ma.nrows, ma.ncols)

    cdef _init_from_dict(self, dict d, int nrows, int ncols):
        if cmr == NULL:
            CMRcreateEnvironment(&cmr)
        CMR_CALL(CMRchrmatCreate(cmr, &self._mat, nrows, ncols, len(d)))
        for row in range(nrows):
            self._mat.rowSlice[row] = 0
        for (row, col), coeff in d.items():
            if coeff:
                self._mat.rowSlice[row + 1] += 1
        for row in range(nrows):
            self._mat.rowSlice[row + 1] += self._mat.rowSlice[row]
        for (row, col), coeff in d.items():
            if coeff:
                index = self._mat.rowSlice[row]
                self._mat.entryColumns[index] = col
                self._mat.entryValues[index] = coeff
                self._mat.rowSlice[row] = index + 1
        for row in reversed(range(nrows)):
            self._mat.rowSlice[row + 1] = self._mat.rowSlice[row]
        self._mat.rowSlice[0] = 0
        CMR_CALL(CMRchrmatSortNonzeros(cmr, self._mat))
        self.set_immutable()

    cdef get_unsafe(self, Py_ssize_t i, Py_ssize_t j):
        cdef size_t index
        CMR_CALL(CMRchrmatFindEntry(self._mat, i, j, &index))
        if index == SIZE_MAX:
            return Integer(0)
        return Integer(self._mat.entryValues[index])

    def _dict(self):
        """
        Return the underlying dictionary of ``self``.
        """
        cdef dict d
        d = {}
        for row in range(self._mat.numRows):
            for index in range(self._mat.rowSlice[row], self._mat.rowSlice[row + 1]):
                d[(row, self._mat.entryColumns[index])] = Integer(self._mat.entryValues[index])
        return d

    def __copy__(self):
        return self

    def __deepcopy__(self, memo):
        return self

    def __dealloc__(self):
        CMRchrmatFree(cmr, &self._mat)

    def _test_change_ring(self, **options):
        return

    def _pickle(self):
        version = 0
        return self._dict(), version

    def _unpickle(self, data, int version):
        if version != 0:
            raise RuntimeError("unknown matrix version (=%s)"%version)
        self._init_from_dict(data, self._nrows, self._ncols)

    # CMR-specific methods. Other classes that want to provide these methods should create
    # a copy of themselves as an instance of this class and delegate to it.

    def is_unimodular(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 2, 3, sparse=True),
            ....:                           [[1, 0, 0], [0, 1, 0]]); M
            [1 0 0]
            [0 1 0]
            sage: M.is_unimodular()
            True
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 2, 3, sparse=True),
            ....:                           [[1, 1, 0], [-1, 1, 1]]); M
            [ 1  1  0]
            [-1  1  1]
            sage: M.is_unimodular()
            False
        """
        cdef bint result

        sig_on()
        CMR_CALL(CMRtestUnimodularity(cmr, self._mat, &result))
        sig_off()

        return result

    def is_strongly_unimodular(self):
        cdef bint result

        sig_on()
        CMR_CALL(CMRtestStrongUnimodularity(cmr, self._mat, &result))
        sig_off()

        return result

    def modulus(self):
        cdef bint result
        cdef size_t k

        sig_on()
        CMR_CALL(CMRtestKmodularity(cmr, self._mat, &result, &k))
        sig_off()

        if result:
            return Integer(k)
        else:
            return None

    def strong_modulus(self):
        cdef bint result
        cdef size_t k

        sig_on()
        CMR_CALL(CMRtestStrongKmodularity(cmr, self._mat, &result, &k))
        sig_off()

        if result:
            return Integer(k)
        else:
            return None

    def is_k_modular(self, k):
        return self.modulus() <= k

    def is_strongly_k_modular(self, k):
        return self.strong_modulus() <= k

    def is_graphic(self, *, time_limit=60.0, certificate=False):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 3, 2, sparse=True),
            ....:                           [[1, 0], [-1, 1], [0, -1]]); M
            [ 1  0]
            [-1  1]
            [ 0 -1]
            sage: M.is_graphic()
            True

        TESTS::

            sage: M.is_graphic(time_limit=0.0)
            Traceback (most recent call last):
            ...
            RuntimeError: Time limit exceeded
        """
        cdef bint result
        cdef CMR_GRAPH *graph
        cdef CMR_GRAPH_EDGE* forest_edges
        cdef CMR_GRAPH_EDGE* coforest_edges
        cdef CMR_SUBMAT* submatrix
        cdef CMR_GRAPHIC_STATISTICS stats

        if certificate:
            sig_on()
            CMR_CALL(CMRtestGraphicMatrix(cmr, self._mat, &result, &graph, &forest_edges,
                                        &coforest_edges, &submatrix, &stats, time_limit))
            sig_off()
            # FIXME: this segfaults despite the sig_on/sig_off
        else:
            sig_on()
            CMR_CALL(CMRtestGraphicMatrix(cmr, self._mat, &result, NULL, NULL,
                                          NULL, NULL, &stats, time_limit))
            sig_off()

        if certificate:
            raise NotImplementedError
        return result

    def is_cographic(self, certificate=False):
         raise NotImplementedError
