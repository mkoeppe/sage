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

from sage.libs.cmr.cmr cimport *
from sage.misc.cachefunc import cached_method
from sage.rings.integer_ring import ZZ
from sage.structure.sage_object cimport SageObject

from .matrix_cmr_sparse cimport Matrix_cmr_chr_sparse, _sage_edge, _sage_graph
from .matrix_space import MatrixSpace


cdef class DecompositionNode(SageObject):
    r"""
    Base class for nodes in Seymour's decomposition
    """

    def __cinit__(self):
        self._dec = NULL

    cdef _set_dec(self, CMR_DEC *dec, root):
        if self._root is None or self._root is self:
            if self._dec != NULL:
                # We own it, so we have to free it.
                CMR_CALL(CMRdecFree(cmr, &self._dec))
        self._dec = dec
        self._root = root

    def __dealloc__(self):
        self._set_dec(NULL, None)

    def __hash__(self):
        return <int>self._dec

    def nrows(self):
        return CMRdecNumRows(self._dec)

    def ncols(self):
        return CMRdecNumColumns(self._dec)

    def dimensions(self):
        return self.nrows(), self.ncols()

    @cached_method
    def matrix(self):
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
            sage: certificate.matrix() is None
            True

            sage: result, certificate = M.is_totally_unimodular(certificate=True,
            ....:                                               construct_matrices=True)
            sage: result, certificate
            (True, GraphicNode (3×2))
            sage: certificate.matrix()
            [ 1  0]
            [-1  1]
            [ 0  1]
        """
        cdef Matrix_cmr_chr_sparse result
        cdef CMR_CHRMAT *mat = CMRdecGetMatrix(self._dec)
        if mat == NULL:
            return None
        ms = MatrixSpace(ZZ, mat.numRows, mat.numColumns, sparse=True)
        result = Matrix_cmr_chr_sparse.__new__(Matrix_cmr_chr_sparse, ms)
        result._mat = mat
        result._root = self._root or self
        return result

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
            sage: result, certificate = M2cmr.is_totally_unimodular(certificate=True,
            ....:                                                   construct_matrices=True)
            sage: result, certificate
            (True, OneSumNode (6×4) with 2 children)
            sage: C = certificate.summands(); C
            (GraphicNode (3×2), GraphicNode (3×2))
            sage: C[0].parent_rows_and_columns()
            ((0, 1, 2), (0, 1))
            sage: C[1].parent_rows_and_columns()
            ((3, 4, 5), (2, 3))
        """
        cdef size_t *parent_rows = CMRdecRowsParent(self._dec)
        cdef size_t *parent_columns = CMRdecColumnsParent(self._dec)
        if parent_rows == NULL:
            parent_rows_tuple = None
        else:
            parent_rows_tuple = tuple(parent_rows[i] for i in range(CMRdecNumRows(self._dec)))
        if parent_columns == NULL:
            parent_columns_tuple = None
        else:
            parent_columns_tuple = tuple(parent_columns[i] for i in range(CMRdecNumColumns(self._dec)))

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
            sage: result, certificate = M2cmr.is_totally_unimodular(certificate=True,
            ....:                                                   construct_matrices=True)
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
            sage: result, certificate = M2MTcmr.is_totally_unimodular(certificate=True,
            ....:                                                     construct_matrices=True)
            sage: T = certificate.as_ordered_tree()
            sage: T.plot()                                                              # needs sage.plot
            Graphics object consisting of 8 graphics primitives
        """
        return self.as_ordered_tree().plot(**kwds)

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
        return tuple(sorted((create_DecompositionNode(CMRdecChild(self._dec, index),
                                                self._root or self)
                             for index in range(CMRdecNumChildren(self._dec))),
                            key=lambda node: node.parent_rows_and_columns()))

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


cdef class TwoSumNode(SumNode):
    r"""
        EXAMPLES::

            sage: from sage.matrix.matrix_cmr_sparse import Matrix_cmr_chr_sparse
            sage: M2 = Matrix_cmr_chr_sparse(MatrixSpace(ZZ, 5, 5, sparse=True),
            ....:                       [[1, 1, 1, 1, 1], [1, 1, 1, 0, 0], [1, 0, 1, 1, 0],
            ....:                        [1, 0, 0, 1, 1], [1, 1, 0, 0, 1]]); M2
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
    """
    def block_matrix_form(self):
        M1, M2 = self.summand_matrices()
        x, y= len(M1.columns()), len(M2.rows())
        return Matrix_cmr_chr_sparse.two_sum(M1, M2, x - 1, y - 1)

cdef class ThreeSumNode(SumNode):

    def block_matrix_form(self):
        M1, M2 = self.summand_matrices()
        x, y= len(M1.columns()), len(M2.columns())
        return Matrix_cmr_chr_sparse.two_sum(M1, M2, x - 1, x-2, y - 1, y - 2)


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
        return _sage_graph(CMRdecGraph(self._dec))

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
            ((1, 2), (7, 1))
        """
        cdef CMR_GRAPH *graph = CMRdecGraph(self._dec)
        cdef size_t num_edges = CMRdecGraphSizeForest(self._dec)
        cdef CMR_GRAPH_EDGE *edges = CMRdecGraphForest(self._dec)
        return tuple(_sage_edge(graph, edges[i]) for i in range(num_edges))

    @cached_method
    def coforest_edges(self):
        cdef CMR_GRAPH *graph = CMRdecGraph(self._dec)
        cdef size_t num_edges = CMRdecGraphSizeCoforest(self._dec)
        cdef CMR_GRAPH_EDGE *edges = CMRdecGraphCoforest(self._dec)
        return tuple(_sage_edge(graph, edges[i]) for i in range(num_edges))


cdef class GraphicNode(BaseGraphicNode):

    pass


cdef class CographicNode(BaseGraphicNode):
    @cached_method
    def graph(self):
        r"""
        Actually the cograph of matrix, in the case where it is not graphic.
        """
        return _sage_graph(CMRdecCograph(self._dec))


cdef class PlanarNode(BaseGraphicNode):
    @cached_method
    def cograph(self):
        return _sage_graph(CMRdecCograph(self._dec))


cdef class SeriesParallelReductionNode(DecompositionNode):

    pass


cdef class SpecialLeafNode(DecompositionNode):

    @cached_method
    def _matroid(self):
        r"""

        """
        cdef int representation_matrix
        cdef CMR_DEC_TYPE typ = CMRdecIsSpecialLeaf(self._dec, &representation_matrix)
        import sage.matroids.matroids_catalog as matroids
        from sage.graphs.graph_generators import graphs
        from sage.matroids.matroid import Matroid

        if typ == CMR_DEC_SPECIAL_R10:
            return matroids.named_matroids.R10()
        if typ == CMR_DEC_SPECIAL_FANO:
            return matroids.named_matroids.Fano()
        if typ == CMR_DEC_SPECIAL_FANO_DUAL:
            return matroids.named_matroids.Fano().dual()
        if typ == CMR_DEC_SPECIAL_K_5:
            return matroids.CompleteGraphic(5)
        if typ == CMR_DEC_SPECIAL_K_5_DUAL:
            return matroids.CompleteGraphic(5).dual()
        if typ == CMR_DEC_SPECIAL_K_3_3:
            E = 'abcdefghi'
            G = graphs.CompleteBipartiteGraph(3, 3)
            return Matroid(groundset=E, graph=G, regular=True)
        if typ == CMR_DEC_SPECIAL_K_3_3_DUAL:
            return matroids.named_matroids.K33dual()
        assert False, 'special leaf node with unknown type'

    def _repr_(self):
        return f'Minor isomorphic to {self._matroid()}'


cdef _class(CMR_DEC *dec):
    k = CMRdecIsSum(dec, NULL, NULL)
    if k == 1:
        return OneSumNode
    if k == 2:
        return TwoSumNode
    if k == 3:
        return ThreeSumNode
    if CMRdecIsGraphicLeaf(dec):
        if CMRdecIsCographicLeaf(dec):
            return PlanarNode
        return GraphicNode
    if CMRdecIsCographicLeaf(dec):
        return CographicNode
    if CMRdecIsSpecialLeaf(dec, NULL):
        return SpecialLeafNode
    if CMRdecIsSeriesParallelReduction(dec):
        return SeriesParallelReductionNode
    if CMRdecIsUnknown(dec):
        return UnknownNode
    return ThreeConnectedIrregularNode


cdef create_DecompositionNode(CMR_DEC *dec, root=None):
    r"""
    Create an instance of a subclass of :class:`DecompositionNode`.

    INPUT:

    - ``dec`` -- a ``CMR_DEC``
    - ``root`` -- a :class:`DecompositionNode` or ``None``.
      If ``None``, ``dec`` will be owned by the returned instance.
      If non-``None``, ``dec`` is owned by that instance.
    """
    if dec == NULL:
        return None
    cdef DecompositionNode result = <DecompositionNode> _class(dec)()
    result._set_dec(dec, root)
    return result
