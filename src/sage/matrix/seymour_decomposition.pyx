# sage_setup: distribution = sagemath-cmr
r"""
Seymour's decomposition of totally unimodular matrices and regular matroids
"""

# ****************************************************************************
#       Copyright (C) 2023 Matthias Koeppe
#                     2023 Javier Santillan
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#                  https://www.gnu.org/licenses/
# ****************************************************************************

from libc.stdint cimport SIZE_MAX

from sage.libs.cmr.cmr cimport *
from sage.misc.cachefunc import cached_method
from sage.rings.integer cimport Integer
from sage.rings.integer_ring import ZZ
from sage.structure.sage_object cimport SageObject

from .matrix_cmr_sparse cimport Matrix_cmr_chr_sparse, _sage_edge, _sage_graph
from .matrix_space import MatrixSpace
from .args cimport MatrixArgs


cdef class DecompositionNode(SageObject):
    r"""
    Base class for nodes in Seymour's decomposition
    """

    def __cinit__(self):
        self._dec = NULL

    cdef _set_dec(self, CMR_MATROID_DEC *dec, root):
        if self._root is None or self._root is self:
            if self._dec != NULL:
                # We own it, so we have to free it.
                CMR_CALL(CMRmatroiddecFree(cmr, &self._dec))
        self._dec = dec
        self._root = root

    cdef _set_row_keys(self, row_keys):
        """
        Set the row keys with consistency checking: if the
        value was previously set, it must remain the same.
        """
        if self._row_keys is not None and self._row_keys != row_keys:
            raise ValueError(f"inconsistent row keys: should be {self._row_keys} "
                             f"but got {row_keys}")
        if row_keys is not None and self.nrows() != len(row_keys):
            raise ValueError(f"inconsistent row keys: should be of cardinality {self.nrows()} "
                             f"but got {row_keys}")
        self._row_keys = row_keys

    cdef _set_column_keys(self, column_keys):
        """
        Set the column keys with consistency checking: if the
        value was previously set, it must remain the same.
        """
        if self._column_keys is not None and self._column_keys != column_keys:
            raise ValueError(f"inconsistent column keys: should be {self._column_keys} "
                             f"but got {column_keys}")
        if column_keys is not None and self.ncols() != len(column_keys):
            raise ValueError(f"inconsistent column keys: should be of cardinality {self.ncols()} "
                             f"but got {column_keys}")
        self._column_keys = column_keys

    def __dealloc__(self):
        self._set_dec(NULL, None)

    def __hash__(self):
        return <int>self._dec

    def nrows(self):
        return CMRmatroiddecNumRows(self._dec)

    def ncols(self):
        return CMRmatroiddecNumColumns(self._dec)

    def dimensions(self):
        return self.nrows(), self.ncols()

    @cached_method
    def matrix(self):
        r"""
        Return a :class:`Matrix`.

        Use :meth:`ancestor_rows_and_columns` for the embedding of it
        into the matrix of ...

        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 3, 2, sparse=True),
            ....:                           [[1, 0], [-1, 1], [0, 1]]); M
            [ 1  0]
            [-1  1]
            [ 0  1]
            sage: result, certificate = M.is_totally_unimodular(certificate=True)
            sage: result, certificate
            (True, GraphicNode (3×2))
            sage: certificate.matrix()
            [ 1  0]
            [-1  1]
            [ 0  1]
        """
        cdef Matrix_cmr_chr_sparse result
        cdef CMR_CHRMAT *mat = CMRmatroiddecGetMatrix(self._dec)
        if mat == NULL:
            return None
        ms = MatrixSpace(ZZ, mat.numRows, mat.numColumns, sparse=True)
        result = Matrix_cmr_chr_sparse.__new__(Matrix_cmr_chr_sparse, ms)
        result._mat = mat
        result._root = self._root or self
        return result

    def row_keys(self):
        r"""
        OUTPUT: a tuple or ``None``
        """
        return self._row_keys

    def column_keys(self):
        r"""
        OUTPUT: a tuple or ``None``
        """
        return self._column_keys

    @cached_method
    def morphism(self):
        r"""

        """
        return MatrixArgs(self.matrix(), MatrixSpace(ZZ, self.row_keys(), self.column_keys())).element()

    @cached_method
    def parent_rows_and_columns(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 3, 2, sparse=True),
            ....:                           [[1, 0], [-1, 1], [0, 1]]); M
            [ 1  0]
            [-1  1]
            [ 0  1]
            sage: result, certificate = M.is_totally_unimodular(certificate=True)
            sage: certificate.parent_rows_and_columns()
            (None, None)

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = matrix([[1, 0], [-1, 1], [0, 1]], sparse=True)
            sage: M2 = block_diagonal_matrix([M, M], sparse=True)
            sage: M2cmr = Matrix_cmr_chr_sparse(M2.parent(), M2); M2cmr
            [ 1  0  0  0]
            [-1  1  0  0]
            [ 0  1  0  0]
            [ 0  0  1  0]
            [ 0  0 -1  1]
            [ 0  0  0  1]
            sage: result, certificate = M2cmr.is_totally_unimodular(certificate=True)
            sage: result, certificate
            (True, OneSumNode (6×4) with 2 children)
            sage: C = certificate.summands(); C
            (GraphicNode (3×2), GraphicNode (3×2))
            sage: C[0].parent_rows_and_columns()
            ((0, 1, 2), (0, 1))
            sage: C[1].parent_rows_and_columns()
            ((3, 4, 5), (2, 3))

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: R12 = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 9, 12, sparse=True),
            ....: [[1, -1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1],
            ....: [0, 0, 0, 1, -1, 0, 0, 0, 1 , 1, 1, 1],
            ....: [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1],
            ....: [ 1,  0,  1,  0,  0,  0,  0,  0,  1,  1,  0,  0],
            ....: [ 0,  1,  1,  0,  0,  0,  0,  0,  0,  0, -1, -1],
            ....: [ 0,  0,  0,  1,  0,  1,  0,  0,  1,  1,  0,  0],
            ....: [ 0,  0,  0,  0,  1,  1,  0,  0,  0,  0, -1, -1],
            ....: [ 0,  0,  0,  0,  0,  0,  1,  0,  1,  0,  1,  0],
            ....: [ 0,  0,  0,  0,  0,  0,  0,  1,  0,  1,  0,  1]])
            sage: result, certificate = R12.is_totally_unimodular(certificate=True,
            ....:                           row_keys=['r1', 'r2', 'r3', 'r4', 'r5',
            ....:                                     'r6', 'r7', 'r8', 'r9'],
            ....:                           column_keys=['a','b','c','d','e','f',
            ....:                                        'g','h','i','j','k','l'])
            sage: C = certificate._children()[0]; C
            ThreeSumNode (9×12) with 2 children
            sage: C.parent_rows_and_columns()
            ((r1, i, r3, r4, r5, r6, r7, r8, r9), (a, b, c, d, e, f, g, h, r2, j, k, l))
        """
        cdef CMR_ELEMENT *parent_rows = CMRmatroiddecRowsParent(self._dec)
        cdef CMR_ELEMENT *parent_columns = CMRmatroiddecColumnsParent(self._dec)
        if parent_rows == NULL or all(parent_rows[i] == 0 for i in range(self.nrows())):
            parent_rows_tuple = None
        else:
            if self.row_keys() is not None:
                parent_rows_tuple = tuple(self.row_keys())
            else:
                parent_rows_tuple = tuple(CMRelementToRowIndex(parent_rows[i])
                                          for i in range(self.nrows()))
        if parent_columns == NULL or all(parent_columns[i] == 0 for i in range(self.ncols())):
            parent_columns_tuple = None
        else:
            if self.column_keys() is not None:
                parent_columns_tuple = tuple(self.column_keys())
            else:
                parent_columns_tuple = tuple(CMRelementToColumnIndex(parent_columns[i])
                                             for i in range(self.ncols()))

        return parent_rows_tuple, parent_columns_tuple

    def as_ordered_tree(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = matrix([[1, 0], [-1, 1], [0, 1]], sparse=True)
            sage: M2 = block_diagonal_matrix([M, M], sparse=True)
            sage: M2cmr = Matrix_cmr_chr_sparse(M2.parent(), M2); M2cmr
            [ 1  0  0  0]
            [-1  1  0  0]
            [ 0  1  0  0]
            [ 0  0  1  0]
            [ 0  0 -1  1]
            [ 0  0  0  1]
            sage: result, certificate = M2cmr.is_totally_unimodular(certificate=True)
            sage: T = certificate.as_ordered_tree(); T
            OneSumNode (6×4) with 2 children[GraphicNode (3×2)[], GraphicNode (3×2)[]]
            sage: unicode_art(T)
            ╭───────────OneSumNode (6×4) with 2 children
            │                 │
            GraphicNode (3×2) GraphicNode (3×2)
        """
        from sage.combinat.ordered_tree import LabelledOrderedTree
        return LabelledOrderedTree([child.as_ordered_tree() for child in self._children()],
                                   label=self)

    def plot(self, **kwds):
        r"""
        Plot the decomposition tree rooted at ``self``.

        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = matrix([[1, 0], [-1, 1], [0, 1]], sparse=True)
            sage: M2MT = block_diagonal_matrix([M, M, M.T], sparse=True)
            sage: M2MTcmr = Matrix_cmr_chr_sparse(M2MT.parent(), M2MT)
            sage: result, certificate = M2MTcmr.is_totally_unimodular(certificate=True)
            sage: T = certificate.as_ordered_tree()
            sage: T.plot()                                                              # needs sage.plot
            Graphics object consisting of 8 graphics primitives
        """
        return self.as_ordered_tree().plot(**kwds)

    def is_ternary(self):
        r"""
        Returns true iff the decomposition is over `\mathbb{F}_3`.
        """
        return <bint> CMRmatroiddecIsTernary(self._dec)

    def nchildren(self):
        r"""
        Returns the number of children of the node.
        """
        return CMRmatroiddecNumChildren(self._dec)

    cdef _CMRelement_to_key(self, CMR_ELEMENT element):
        if not CMRelementIsValid(element):
            raise ValueError('CMRelement index not valid. Extra row or column is detected.')
        if self.row_keys() is None or self.column_keys() is None:
            raise ValueError('row_keys and column_keys are required')
        if CMRelementIsRow(element):
            return ElementKey(self.row_keys()[CMRelementToRowIndex(element)])
        else:
            return ElementKey(self.column_keys()[CMRelementToColumnIndex(element)])

    def _create_child_node(self, index):
        row_keys = self.row_keys()
        column_keys = self.column_keys()
        cdef CMR_MATROID_DEC *child_dec = CMRmatroiddecChild(self._dec, index)
        cdef CMR_ELEMENT *parent_rows = CMRmatroiddecRowsParent(child_dec)
        cdef CMR_ELEMENT *parent_columns = CMRmatroiddecColumnsParent(child_dec)

        if row_keys is not None and column_keys is not None:
            child_row_keys = tuple(self._CMRelement_to_key(parent_rows[i])
                                   for i in range(CMRmatroiddecNumRows(child_dec)))
            child_column_keys = tuple(self._CMRelement_to_key(parent_columns[i])
                                      for i in range(CMRmatroiddecNumColumns(child_dec)))
            child = create_DecompositionNode(child_dec, root=self._root or self,
                                             row_keys=child_row_keys,
                                             column_keys=child_column_keys)
        else:
            child = create_DecompositionNode(child_dec, root=self._root or self)
        return child

    @cached_method
    def _children(self):
        r"""
        Return a tuple of the children.

        The children are sorted by their :meth:`parent_rows_and_columns`.

        In the case of :class:`SumNode`, this is the same as :meth:`~SumNode.summands`.

        For graphic or leaf nodes, it returns the empty tuple.

        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse.one_sum([[1, 0], [-1, 1]],
            ....:                                   [[1, 1], [-1, 0]],
            ....:                                   [[1, 0], [0,1]]); M
            [ 1  0| 0  0| 0  0]
            [-1  1| 0  0| 0  0]
            [-----+-----+-----]
            [ 0  0| 1  1| 0  0]
            [ 0  0|-1  0| 0  0]
            [-----+-----+-----]
            [ 0  0| 0  0| 1  0]
            [ 0  0| 0  0| 0  1]
            sage: result, certificate = M.is_totally_unimodular(certificate=True); certificate
            OneSumNode (6×6) with 4 children
            sage: certificate._children()
            (GraphicNode (2×2), GraphicNode (2×2), GraphicNode (1×1), GraphicNode (1×1))

            sage: M2 = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 2, 2, sparse=True),
            ....:                            [[1, 1], [-1, 0]]); M2
            [ 1  1]
            [-1  0]
            sage: result, certificate = M2.is_totally_unimodular(certificate=True); certificate
            GraphicNode (2×2)
            sage: certificate._children()
            ()
        """
        return tuple(self._create_child_node(index)
                     for index in range(self.nchildren()))

    def _repr_(self):
        nrows, ncols = self.dimensions()
        return f'{self.__class__.__name__} ({nrows}×{ncols})'

    def _unicode_art_(self):
        return self.as_ordered_tree()._unicode_art_()

    def _ascii_art_(self):
        return self.as_ordered_tree()._ascii_art_()


cdef class ThreeConnectedIrregularNode(DecompositionNode):

    pass

cdef class UnknownNode(DecompositionNode):

    pass


cdef class SumNode(DecompositionNode):
    r"""
    Base class for 1-sum, 2-sum, and 3-sum nodes in Seympur's decomposition
    """

    def _repr_(self):
        result = super()._repr_()
        children = self._children()
        result += f' with {len(children)} children'
        return result

    def permuted_block_matrix(self):
        r"Return (Prow, BlockMatrix, Pcolumn) so that self.matrix() == Prow * BlockMatrix * Pcolumn ????"
        raise NotImplementedError

    summands = DecompositionNode._children

    def summand_matrices(self):
        return tuple(s.matrix() for s in self.summands())


cdef class OneSumNode(SumNode):

    def block_matrix_form(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse.one_sum([[1, 0], [-1, 1]], [[1, 1], [-1, 0]])
            sage: result, certificate = M.is_totally_unimodular(certificate=True); certificate
            OneSumNode (4×4) with 2 children
            sage: certificate.summand_matrices()
            (
            [ 1  0]  [ 1  1]
            [-1  1], [-1  0]
            )
            sage: certificate.block_matrix_form()
            [ 1  0| 0  0]
            [-1  1| 0  0]
            [-----+-----]
            [ 0  0| 1  1]
            [ 0  0|-1  0]

            sage: M3 = Matrix_cmr_chr_sparse.one_sum([[1, 0], [-1, 1]],
            ....:                                    [[1, 1], [-1, 0]],
            ....:                                    [[1, 0], [0, 1]]); M3
            [ 1  0| 0  0| 0  0]
            [-1  1| 0  0| 0  0]
            [-----+-----+-----]
            [ 0  0| 1  1| 0  0]
            [ 0  0|-1  0| 0  0]
            [-----+-----+-----]
            [ 0  0| 0  0| 1  0]
            [ 0  0| 0  0| 0  1]
            sage: result, certificate = M3.is_totally_unimodular(certificate=True); certificate
            OneSumNode (6×6) with 4 children
            sage: certificate.summand_matrices()
            (
            [ 1  0]  [ 1  1]
            [-1  1], [-1  0], [1], [1]
            )
            sage: certificate.block_matrix_form()
            [ 1  0| 0  0| 0| 0]
            [-1  1| 0  0| 0| 0]
            [-----+-----+--+--]
            [ 0  0| 1  1| 0| 0]
            [ 0  0|-1  0| 0| 0]
            [-----+-----+--+--]
            [ 0  0| 0  0| 1| 0]
            [-----+-----+--+--]
            [ 0  0| 0  0| 0| 1]
        """
        return Matrix_cmr_chr_sparse.one_sum(*self.summand_matrices())

    @staticmethod
    def check(result_matrix, summand_matrices, summand_parent_rows_and_columns):
        r"""
        Check that ``result_matrix`` is a 1-sum of ``summand_matrices``.

        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: from sage.matrix.seymour_decomposition import OneSumNode

            sage: M2 = Matrix_cmr_chr_sparse.one_sum([[1, 0], [-1, 1]],
            ....:                                    [[1, 1], [-1, 0]])
            sage: result, certificate = M2.is_totally_unimodular(certificate=True); certificate
            OneSumNode (4×4) with 2 children
            sage: OneSumNode.check(M2,
            ....:                  certificate.summand_matrices(),
            ....:                  [summand.parent_rows_and_columns()
            ....:                   for summand in certificate.summands()])

        Symbolic identities::

            sage: from sage.matrix.seymour_decomposition import OneSumNode
            sage: R.<x,y> = QQ[]
            sage: A = matrix([[x, 0], [-x, 1]])
            sage: B = matrix([[x, y], [-x, 0]])
            sage: A1B = block_diagonal_matrix([A, B])
            sage: OneSumNode.check(A1B, [A, B], [([0, 1], [0, 1]),
            ....:                                ([2, 3], [2, 3])])

        Using program analysis::

            sage: # optional - cutgeneratingfunctionology
            sage: R.<x,y,z> = ParametricRealField({x: 1}, {y: -1}, {z: 0})  # true example
            sage: A = matrix([[x, 0], [-x, 1]])
            sage: B = matrix([[x, y], [-x, 0]])
            sage: A1B = matrix([[z, 0, 0, 0], [-x, z, 0, 0], [], []])
            sage: OneSumNode.check(A1B, [A, B], [([0, 1], [0, 1]),
            ....:                                ([2, 3], [2, 3])])
            sage: # side-effect: R stores polynomial identities
        """
        # TODO: Check that summand_parent_rows_and_columns form partitions of rows and columns
        for matrix, rows_and_columns in zip(summand_matrices, summand_parent_rows_and_columns):
            assert result_matrix.matrix_from_rows_and_columns(*rows_and_columns) == matrix
        # TODO: Check zero blocks


cdef class TwoSumNode(SumNode):

    def block_matrix_form(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M2 = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 5, 5, sparse=True),
            ....:                            [[1, 1, 1, 1, 1], [1, 1, 1, 0, 0],
            ....:                             [1, 0, 1, 1, 0], [1, 0, 0, 1, 1],
            ....:                             [1, 1, 0, 0, 1]]); M2
            [1 1 1 1 1]
            [1 1 1 0 0]
            [1 0 1 1 0]
            [1 0 0 1 1]
            [1 1 0 0 1]
            sage: M3 = Matrix_cmr_chr_sparse.two_sum(M2, M2, 0, 1); M3
            [1 1 1 1|1 1 1 0 0]
            [1 1 0 0|1 1 1 0 0]
            [0 1 1 0|1 1 1 0 0]
            [0 0 1 1|1 1 1 0 0]
            [1 0 0 1|1 1 1 0 0]
            [-------+---------]
            [0 0 0 0|1 1 1 1 1]
            [0 0 0 0|1 0 1 1 0]
            [0 0 0 0|1 0 0 1 1]
            [0 0 0 0|1 1 0 0 1]
            sage: result, certificate = M3.is_totally_unimodular(certificate=True); certificate
            TwoSumNode (9×9) with 2 children

            sage: K33 = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 5, 4, sparse=True),
            ....:                            [[1, 1, 0, 0], [1, 1, 1, 0],
            ....:                             [1, 0, 0,-1], [0, 1, 1, 1],
            ....:                             [0, 0, 1, 1]]); K33
            [ 1  1  0  0]
            [ 1  1  1  0]
            [ 1  0  0 -1]
            [ 0  1  1  1]
            [ 0  0  1  1]
            sage: K33_dual = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 4, 5, sparse=True),
            ....:                            [[1, 1, 1, 0, 0], [1, 1, 0, 1, 0],
            ....:                             [0, 1, 0, 1, 1], [0, 0,-1, 1, 1]]); K33_dual
            [ 1  1  1  0  0]
            [ 1  1  0  1  0]
            [ 0  1  0  1  1]
            [ 0  0 -1  1  1]
            sage: M = Matrix_cmr_chr_sparse.two_sum(K33, K33_dual, 0, 0,
            ....:                                   nonzero_block="bottom_left"); M
            [ 1  1  1  0| 0  0  0  0]
            [ 1  0  0 -1| 0  0  0  0]
            [ 0  1  1  1| 0  0  0  0]
            [ 0  0  1  1| 0  0  0  0]
            [-----------+-----------]
            [ 1  1  0  0| 1  1  0  0]
            [ 1  1  0  0| 1  0  1  0]
            [ 0  0  0  0| 1  0  1  1]
            [ 0  0  0  0| 0 -1  1  1]
            sage: result1, certificate1 = M.is_totally_unimodular(certificate=True); certificate1
            TwoSumNode (8×8) with 2 children
            sage: certificate1.summand_matrices()
            (
            [ 1  1  1  0]
            [ 1  0  0 -1]  [ 1  1  1  0  0]
            [ 0  1  1  1]  [ 1  1  0  1  0]
            [ 0  0  1  1]  [ 0  1  0  1  1]
            [ 1  1  0  0], [ 0  0 -1  1  1]
            )
            sage: certificate1.block_matrix_form()
            [ 1  1  1  0| 0  0  0  0]
            [ 1  0  0 -1| 0  0  0  0]
            [ 0  1  1  1| 0  0  0  0]
            [ 0  0  1  1| 0  0  0  0]
            [-----------+-----------]
            [ 1  1  0  0| 1  1  0  0]
            [ 1  1  0  0| 1  0  1  0]
            [ 0  0  0  0| 1  0  1  1]
            [ 0  0  0  0| 0 -1  1  1]
            sage: [M.parent_rows_and_columns() for M in certificate1._children()]
            [((0, 1, 2, 3, 4), (0, 1, 2, 3)), ((4, 5, 6, 7), (0, 4, 5, 6, 7))]
            sage: M_perm = M.matrix_from_rows_and_columns([4, 6, 5, 7, 0, 1, 2, 3], range(M.ncols()))
            sage: M_perm
            [ 1  1  0  0  1  1  0  0]
            [ 0  0  0  0  1  0  1  1]
            [ 1  1  0  0  1  0  1  0]
            [ 0  0  0  0  0 -1  1  1]
            [ 1  1  1  0  0  0  0  0]
            [ 1  0  0 -1  0  0  0  0]
            [ 0  1  1  1  0  0  0  0]
            [ 0  0  1  1  0  0  0  0]
            sage: result2, certificate2 = M_perm.is_totally_unimodular(certificate=True)
            sage: certificate2.summand_matrices()
            (
            [ 1  1  1  0]
            [ 1  0  0 -1]  [ 1  1  1  0  0]
            [ 0  1  1  1]  [ 0  1  0  1  1]
            [ 0  0  1  1]  [ 1  1  0  1  0]
            [ 1  1  0  0], [ 0  0 -1  1  1]
            )
            sage: certificate2.block_matrix_form()
            [ 1  1  1  0| 0  0  0  0]
            [ 1  0  0 -1| 0  0  0  0]
            [ 0  1  1  1| 0  0  0  0]
            [ 0  0  1  1| 0  0  0  0]
            [-----------+-----------]
            [ 1  1  0  0| 1  1  0  0]
            [ 0  0  0  0| 1  0  1  1]
            [ 1  1  0  0| 1  0  1  0]
            [ 0  0  0  0| 0 -1  1  1]
            sage: [M.parent_rows_and_columns() for M in certificate2._children()]
            [((4, 5, 6, 7, 0), (0, 1, 2, 3)), ((0, 1, 2, 3), (0, 4, 5, 6, 7))]
        """
        M1, M2 = self.summand_matrices()
        return Matrix_cmr_chr_sparse.two_sum(M1, M2, M1.nrows() - 1, 0, "bottom_left")

cdef class ThreeSumNode(SumNode):

    @cached_method
    def _children(self):
        r"""
        TESTS:

        This is test ``WideWideR12`` and ``MixedMixedR12`` in CMR's ``test_tu.cpp``::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: R12 = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 6, 6, sparse=True),
            ....: [[1,0,1,1,0,0],[0,1,1,1,0,0],[1,0,1,0,1,1],
            ....: [0,-1,0,-1,1,1],[1,0,1,0,1,0],[0,-1,0,-1,0,1]])
            sage: result, certificate = R12.is_totally_unimodular(certificate=True,
            ....:                           three_sum_strategy="Wide_Wide",
            ....:                           row_keys=range(6),
            ....:                           column_keys='abcdef')
            sage: C = certificate._children()[0]
            sage: C.parent_rows_and_columns()
            ((0, 1, 2, 3, a, 5), (4, b, c, d, e, f))
            sage: C1, C2 = C._children()
            sage: C1.matrix()
            [ 0  0  1 -1 -1]
            [ 1  1  1  0  0]
            [ 0  1  0  1  1]
            [-1  0 -1  0  1]
            sage: C2.matrix()
            [ 1  0  1 -1  0]
            [ 0  0  1  0  1]
            [-1 -1  0  1  1]
            [-1 -1  0  0  1]
            sage: C1.parent_rows_and_columns()
            ((0, 1, a, 3), (b, c, d, e, +3+e))
            sage: C2.parent_rows_and_columns()
            ((0, 2, 3, 5), (+b+0, d, 4, e, f))

            sage: result, certificate = R12.is_totally_unimodular(certificate=True,
            ....:                           three_sum_strategy="Mixed_Mixed",
            ....:                           row_keys=range(6),
            ....:                           column_keys='abcdef')
            sage: C1, C2 = certificate._children()
            sage: C1.matrix()
            [ 1  0  1  1  0]
            [ 0  1  1  1  0]
            [ 1  0  1  0  1]
            [ 0 -1  0 -1  1]
            sage: C2.matrix()
            [ 1  1  0  0]
            [ 1  0  1  1]
            [ 0 -1  1  1]
            [ 1  0  1  0]
            [ 0 -1  0  1]
            sage: C1.parent_rows_and_columns()
            ((0, 1, 2, 3), (a, b, c, d, +2+3))
            sage: C2.parent_rows_and_columns()
            ((+a+b, 2, 3, 4, 5), (a, d, e, f))
        """
        if self.nchildren() != 2:
            raise ValueError("ThreeSumNode has exactly two children")

        cdef CMR_MATROID_DEC *child1_dec = CMRmatroiddecChild(self._dec, 0)
        cdef CMR_ELEMENT *parent_rows1 = CMRmatroiddecRowsParent(child1_dec)
        cdef CMR_ELEMENT *parent_columns1 = CMRmatroiddecColumnsParent(child1_dec)
        cdef CMR_CHRMAT *mat1 = CMRmatroiddecGetMatrix(child1_dec)

        cdef CMR_MATROID_DEC *child2_dec = CMRmatroiddecChild(self._dec, 1)
        cdef CMR_ELEMENT *parent_rows2 = CMRmatroiddecRowsParent(child2_dec)
        cdef CMR_ELEMENT *parent_columns2 = CMRmatroiddecColumnsParent(child2_dec)
        cdef CMR_CHRMAT *mat2 = CMRmatroiddecGetMatrix(child2_dec)

        cdef size_t index1, index2

        row_keys = self.row_keys()
        column_keys = self.column_keys()

        if row_keys is not None and column_keys is not None:
            child1_nrows = CMRmatroiddecNumRows(child1_dec)
            child1_ncols = CMRmatroiddecNumColumns(child1_dec)

            if self.is_concentrated_rank(): # Mixed_Mixed
                child1_row_keys = tuple(self._CMRelement_to_key(parent_rows1[i])
                                        for i in range(child1_nrows))
                child1_column_keys = tuple(self._CMRelement_to_key(parent_columns1[i])
                                        for i in range(child1_ncols - 1))

                CMR_CALL(CMRchrmatFindEntry(mat1, child1_nrows-2, child1_ncols-1, &index1))
                if index1 == SIZE_MAX:
                    epsilon1 = Integer(0)
                else:
                    epsilon1 = Integer(mat1.entryValues[index1])

                CMR_CALL(CMRchrmatFindEntry(mat1, child1_nrows-1, child1_ncols-1, &index2))
                if index2 == SIZE_MAX:
                    epsilon2 = Integer(0)
                else:
                    epsilon2 = Integer(mat1.entryValues[index2])

                child1_column_keys += (ElementKey((epsilon1, row_keys[child1_nrows-2], epsilon2, row_keys[child1_nrows-1]), composition=True),)
            else: # Wide_Wide
                child1_row_keys = tuple(self._CMRelement_to_key(parent_rows1[i])
                                        for i in range(child1_nrows))
                child1_column_keys = tuple(self._CMRelement_to_key(parent_columns1[i])
                                        for i in range(child1_ncols - 1))

                CMR_CALL(CMRchrmatFindEntry(mat1, child1_nrows-1, child1_ncols-1, &index1))
                if index1 == SIZE_MAX:
                    epsilon1 = Integer(0)
                else:
                    epsilon1 = Integer(mat1.entryValues[index1])

                child1_column_keys += (ElementKey((1, column_keys[child1_ncols-1], epsilon1,
                                        row_keys[child1_nrows-1]), composition=True),)

            child1 = create_DecompositionNode(child1_dec, root=self._root or self,
                                              row_keys=child1_row_keys,
                                              column_keys=child1_column_keys)

            child2_nrows = CMRmatroiddecNumRows(child2_dec)
            child2_ncols = CMRmatroiddecNumColumns(child2_dec)

            if self.is_concentrated_rank(): # Mixed_Mixed
                child2_row_keys = tuple(self._CMRelement_to_key(parent_rows2[i])
                                        for i in range(1, child2_nrows))

                CMR_CALL(CMRchrmatFindEntry(mat2, 0, 0, &index1))
                if index1 == SIZE_MAX:
                    epsilon1 = Integer(0)
                else:
                    epsilon1 = Integer(mat1.entryValues[index1])

                CMR_CALL(CMRchrmatFindEntry(mat2, 0, 1, &index2))
                if index2 == SIZE_MAX:
                    epsilon2 = Integer(0)
                else:
                    epsilon2 = Integer(mat1.entryValues[index2])

                child2_row_keys = (ElementKey((epsilon1, column_keys[0], epsilon2, column_keys[1]), composition=True), ) + child2_row_keys
                child2_column_keys = tuple(self._CMRelement_to_key(parent_columns2[i])
                                           for i in range(child2_ncols))
            else: # Wide_Wide
                child2_row_keys = tuple(self._CMRelement_to_key(parent_rows2[i])
                                        for i in range(child2_nrows))

                CMR_CALL(CMRchrmatFindEntry(mat2, 0, 0, &index1))
                if index1 == SIZE_MAX:
                    epsilon1 = Integer(0)
                else:
                    epsilon1 = Integer(mat1.entryValues[index1])

                child2_column_keys = tuple(self._CMRelement_to_key(parent_columns2[i])
                                           for i in range(1, child2_ncols))
                child2_column_keys = (ElementKey((1, column_keys[1], epsilon1, row_keys[0]), composition=True),) + child2_column_keys

            child2 = create_DecompositionNode(child2_dec, root=self._root or self,
                                              row_keys=child2_row_keys,
                                              column_keys=child2_column_keys)
        else:
            child1 = create_DecompositionNode(child1_dec, root=self._root or self)
            child2 = create_DecompositionNode(child2_dec, root=self._root or self)
        return (child1, child2)

    def is_distributed_ranks(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: R12_large = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 9, 12, sparse=True),
            ....: [[1, -1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1],
            ....: [0, 0, 0, 1, -1, 0, 0, 0, 1 , 1, 1, 1],
            ....: [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1],
            ....: [ 1,  0,  1,  0,  0,  0,  0,  0,  1,  1,  0,  0],
            ....: [ 0,  1,  1,  0,  0,  0,  0,  0,  0,  0, -1, -1],
            ....: [ 0,  0,  0,  1,  0,  1,  0,  0,  1,  1,  0,  0],
            ....: [ 0,  0,  0,  0,  1,  1,  0,  0,  0,  0, -1, -1],
            ....: [ 0,  0,  0,  0,  0,  0,  1,  0,  1,  0,  1,  0],
            ....: [ 0,  0,  0,  0,  0,  0,  0,  1,  0,  1,  0,  1]])
            sage: result, certificate = R12_large.is_totally_unimodular(certificate=True)
            sage: C = certificate._children()[0]; C
            ThreeSumNode (9×12) with 2 children
            sage: C.is_distributed_ranks()
            True
            sage: C.is_concentrated_rank()
            False
        """
        return <bint> CMRmatroiddecThreeSumDistributedRanks(self._dec)

    def is_concentrated_rank(self):
        return <bint> CMRmatroiddecThreeSumConcentratedRank(self._dec)

    def block_matrix_form(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: R12 = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 6, 6, sparse=True),
            ....: [[1,0,1,1,0,0],[0,1,1,1,0,0],[1,0,1,0,1,1],
            ....: [0,-1,0,-1,1,1],[1,0,1,0,1,0],[0,-1,0,-1,0,1]])
            sage: R12
            [ 1  0  1  1  0  0]
            [ 0  1  1  1  0  0]
            [ 1  0  1  0  1  1]
            [ 0 -1  0 -1  1  1]
            [ 1  0  1  0  1  0]
            [ 0 -1  0 -1  0  1]
            sage: result, certificate = R12.is_totally_unimodular(certificate=True)
            sage: C = certificate._children()[0]; C
            ThreeSumNode (6×6) with 2 children
            sage: C.matrix()
            [ 1  0  0  1 -1  0]
            [ 0  1  1  1  0  0]
            [ 1  0  0  0  0  1]
            [ 0 -1  0 -1  1  1]
            [-1  0  1  0  1  0]
            [ 0 -1  0 -1  0  1]
            sage: C.summand_matrices()
            (
            [ 0  0  1 -1 -1]  [ 1  0  1 -1  0]
            [ 1  1  1  0  0]  [ 0  0  1  0  1]
            [ 0  1  0  1  1]  [-1 -1  0  1  1]
            [-1  0 -1  0  1], [-1 -1  0  0  1]
            )
            sage: C.block_matrix_form()
            [ 0  0  1 -1  1  0]
            [ 1  1  1  0  0  0]
            [ 0  1  0  1 -1  0]
            [ 0  0  0  1  0  1]
            [ 1  0  1  0  1  1]
            [ 1  0  1  0  0  1]
        """
        M1, M2 = self.summand_matrices()
        x = M1.ncols()
        # return Matrix_cmr_chr_sparse.three_sum(M1, M2, x - 2, x - 1, 0, 1)
        return Matrix_cmr_chr_sparse.three_sum_wide_wide(M1, M2)


cdef class BaseGraphicNode(DecompositionNode):

    @cached_method
    def graph(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 3, 2, sparse=True),
            ....:                           [[1, 0], [-1, 1], [0, 1]]); M
            [ 1  0]
            [-1  1]
            [ 0  1]
            sage: result, certificate = M.is_totally_unimodular(certificate=True)
            sage: result, certificate
            (True, GraphicNode (3×2))
            sage: G = certificate.graph(); G
            Graph on 4 vertices
            sage: G.vertices(sort=True)
            [1, 2, 7, 12]
            sage: G.edges(sort=True)
            [(1, 2, None), (1, 7, None), (1, 12, None), (2, 7, None), (7, 12, None)]
        """
        return _sage_graph(CMRmatroiddecGraph(self._dec))

    @cached_method
    def forest_edges(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 3, 2, sparse=True),
            ....:                           [[1, 0], [-1, 1], [0, 1]]); M
            [ 1  0]
            [-1  1]
            [ 0  1]
            sage: result, certificate = M.is_totally_unimodular(certificate=True)
            sage: result, certificate
            (True, GraphicNode (3×2))
            sage: certificate.forest_edges()
            ((1, 2), (7, 1), (12, 7))
        """
        cdef CMR_GRAPH *graph = CMRmatroiddecGraph(self._dec)
        cdef size_t num_edges = CMRmatroiddecGraphSizeForest(self._dec)
        cdef CMR_GRAPH_EDGE *edges = CMRmatroiddecGraphForest(self._dec)
        return tuple(_sage_edge(graph, edges[i]) for i in range(num_edges))

    @cached_method
    def coforest_edges(self):
        cdef CMR_GRAPH *graph = CMRmatroiddecGraph(self._dec)
        cdef size_t num_edges = CMRmatroiddecGraphSizeCoforest(self._dec)
        cdef CMR_GRAPH_EDGE *edges = CMRmatroiddecGraphCoforest(self._dec)
        return tuple(_sage_edge(graph, edges[i]) for i in range(num_edges))


cdef class GraphicNode(BaseGraphicNode):

    pass


cdef class CographicNode(BaseGraphicNode):
    @cached_method
    def graph(self):
        r"""
        Actually the cograph of matrix, in the case where it is not graphic.
        """
        return _sage_graph(CMRmatroiddecCograph(self._dec))


cdef class PlanarNode(BaseGraphicNode):
    @cached_method
    def cograph(self):
        return _sage_graph(CMRmatroiddecCograph(self._dec))


cdef class SeriesParallelReductionNode(DecompositionNode):

    def core(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 5, 6, sparse=True),
            ....:                           [[1, 1, 1, 1, 1, 0], [1, 1, 1, 0, 0, 0],
            ....:                            [1, 0, 1, 1, 0, 1] ,[1, 0, 0, 1, 1, 0],
            ....:                            [1, 1, 0, 0, 1, 0]]); M
            [1 1 1 1 1 0]
            [1 1 1 0 0 0]
            [1 0 1 1 0 1]
            [1 0 0 1 1 0]
            [1 1 0 0 1 0]
            sage: result, certificate = M.is_totally_unimodular(certificate=True)
            sage: result, certificate
            (True, SeriesParallelReductionNode (5×6))
            sage: certificate.core()
            [1 1 1 1 1]
            [1 1 1 0 0]
            [1 0 1 1 0]
            [1 0 0 1 1]
            [1 1 0 0 1]
        """
        return self._children()[0].matrix()


cdef class SpecialLeafNode(DecompositionNode):

    @cached_method
    def _matroid(self):
        r"""

        """
        cdef CMR_MATROID_DEC_TYPE typ = CMRmatroiddecType(self._dec)
        import sage.matroids.matroids_catalog as matroids
        from sage.graphs.graph_generators import graphs
        from sage.matroids.matroid import Matroid

        if typ == CMR_MATROID_DEC_TYPE_R10:
            return matroids.catalog.R10()
        if typ == CMR_MATROID_DEC_TYPE_FANO:
            return matroids.catalog.Fano()
        if typ == CMR_MATROID_DEC_TYPE_FANO_DUAL:
            return matroids.catalog.Fano().dual()
        if typ == CMR_MATROID_DEC_TYPE_K5:
            return matroids.CompleteGraphic(5)
        if typ == CMR_MATROID_DEC_TYPE_K5_DUAL:
            return matroids.CompleteGraphic(5).dual()
        if typ == CMR_MATROID_DEC_TYPE_K33:
            E = 'abcdefghi'
            G = graphs.CompleteBipartiteGraph(3, 3)
            return Matroid(groundset=E, graph=G, regular=True)
        if typ == CMR_MATROID_DEC_TYPE_K33_DUAL:
            return matroids.catalog.K33dual()
        if typ == CMR_MATROID_DEC_TYPE_DETERMINANT:
            return '|det| = 2 submatrix'
        assert False, 'special leaf node with unknown type'

    def _repr_(self):
        return f'Isomorphic to a minor of {self._matroid()}'

    def rep_matrix(self):
        r"""
        WIP
        """
        assert NotImplementedError

        # cdef int representation_matrix
        # cdef CMR_MATROID_DEC_TYPE typ = CMRdecIsSpecialLeaf(self._dec, &representation_matrix)
        # return Matrix_cmr_chr_sparse._from_data(representation_matrix, immutable=False)


cdef class PivotsNode(DecompositionNode):

    def npivots(self):
        return CMRmatroiddecNumPivots(self._dec)

    @cached_method
    def pivot_rows_and_columns(self):
        r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: R12 = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 9, 12, sparse=True),
            ....: [[1, -1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1],
            ....: [0, 0, 0, 1, -1, 0, 0, 0, 1 , 1, 1, 1],
            ....: [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1],
            ....: [ 1,  0,  1,  0,  0,  0,  0,  0,  1,  1,  0,  0],
            ....: [ 0,  1,  1,  0,  0,  0,  0,  0,  0,  0, -1, -1],
            ....: [ 0,  0,  0,  1,  0,  1,  0,  0,  1,  1,  0,  0],
            ....: [ 0,  0,  0,  0,  1,  1,  0,  0,  0,  0, -1, -1],
            ....: [ 0,  0,  0,  0,  0,  0,  1,  0,  1,  0,  1,  0],
            ....: [ 0,  0,  0,  0,  0,  0,  0,  1,  0,  1,  0,  1]])
            sage: result, certificate = R12.is_totally_unimodular(certificate=True)
            sage: certificate
            PivotsNode (9×12)
            sage: certificate.pivot_rows_and_columns()
            ((1, 8),)
        """
        cdef size_t *pivot_rows = CMRmatroiddecPivotRows(self._dec)
        cdef size_t *pivot_columns = CMRmatroiddecPivotColumns(self._dec)

        return tuple((pivot_rows[i], pivot_columns[i]) for i in range(self.npivots()))


cdef class SubmatrixNode(DecompositionNode):
    pass


cdef class ElementKey:

    cdef frozenset _key
    cdef bint _composition

    def __init__(self, keys, composition=False):
        """
        Return the index key.

        frozenset((1,'a'), (-1,'7'))
        """
        if composition:
            sign1, key1, sign2, key2 = keys
            self._key = frozenset([(sign1, key1), (sign2, key2)])
            self._composition = True
        else:
            self._key = frozenset((keys,))
            self._composition = False

    @property
    def key(self):
        return self._key

    def __hash__(self):
        return hash(self._key)

    def __eq__(self, other):
        if isinstance(other, ElementKey):
            return self._key == other._key
        return False

    def __repr__(self):
        if self._composition:
            return "".join(['+'+str(a[1]) if a[0] == 1 else '-'+str(a[1]) for a in self._key])
        else:
            return "".join([str(a) for a in self._key])


cdef _class(CMR_MATROID_DEC *dec):
    cdef CMR_MATROID_DEC_TYPE typ = CMRmatroiddecType(dec)

    if typ == CMR_MATROID_DEC_TYPE_ONE_SUM:
        return OneSumNode
    if typ == CMR_MATROID_DEC_TYPE_TWO_SUM:
        return TwoSumNode
    if typ == CMR_MATROID_DEC_TYPE_THREE_SUM:
        return ThreeSumNode
    if typ == CMR_MATROID_DEC_TYPE_GRAPH:
        if typ == CMR_MATROID_DEC_TYPE_COGRAPH:
            return PlanarNode
        return GraphicNode
    if typ == CMR_MATROID_DEC_TYPE_COGRAPH:
        return CographicNode
    if typ < -1:
        return SpecialLeafNode
    if typ == CMR_MATROID_DEC_TYPE_SERIES_PARALLEL:
        return SeriesParallelReductionNode
    if typ == CMR_MATROID_DEC_TYPE_PIVOTS:
        return PivotsNode
    if typ == CMR_MATROID_DEC_TYPE_SUBMATRIX:
        return SubmatrixNode
    if typ == CMR_MATROID_DEC_TYPE_IRREGULAR:
        return ThreeConnectedIrregularNode
    if typ == CMR_MATROID_DEC_TYPE_UNKNOWN:
        return UnknownNode
    assert NotImplementedError


cdef create_DecompositionNode(CMR_MATROID_DEC *dec, root=None, row_keys=None, column_keys=None):
    r"""
    Create an instance of a subclass of :class:`DecompositionNode`.

    INPUT:

    - ``dec`` -- a ``CMR_MATROID_DEC``
    - ``root`` -- a :class:`DecompositionNode` or ``None``.
      If ``None``, ``dec`` will be owned by the returned instance.
      If non-``None``, ``dec`` is owned by that instance.
    """
    if dec == NULL:
        return None
    cdef DecompositionNode result = <DecompositionNode> _class(dec)()
    result._set_dec(dec, root)
    if row_keys is not None:
        result._set_row_keys(row_keys)
    if column_keys is not None:
        result._set_column_keys(column_keys)
    return result
