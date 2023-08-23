from sage.groups.perm_gps.permgroup_element cimport PermutationGroupElement
from sage.groups.perm_gps.permgroup_named import SymmetricGroup
from sage.matrix.matrix_integer_dense cimport Matrix_integer_dense


def _palp_PM_max(self, check=False):
    r"""
    Compute the permutation normal form of the vertex facet pairing
    matrix .

    The permutation normal form of a matrix is defined as the lexicographic
    maximum under all permutations of its rows and columns. For more
    more detail, see also
    :meth:`~sage.matrix.matrix2.Matrix.permutation_normal_form`.

    Instead of using the generic method for computing the permutation
    normal form, this method uses the PALP algorithm to compute
    the permutation normal form and its automorphisms concurrently.

    INPUT:

    - ``check`` -- Boolean (default: ``False``), whether to return
        the permutations leaving the maximal vertex-facet pairing
        matrix invariant.

    OUTPUT:

    A matrix or a tuple of a matrix and a dict whose values are the
    permutation group elements corresponding to the permutations
    that permute :meth:`vertices` such that the vertex-facet pairing
    matrix is maximal.

    EXAMPLES::

        sage: o = lattice_polytope.cross_polytope(2)
        sage: PM = o.vertex_facet_pairing_matrix()
        sage: PM_max = PM.permutation_normal_form()                                 # optional - sage.graphs
        sage: PM_max == o._palp_PM_max()                                            # optional - sage.graphs
        True
        sage: P2 = ReflexivePolytope(2, 0)
        sage: PM_max, permutations = P2._palp_PM_max(check=True)
        sage: PM_max
        [3 0 0]
        [0 3 0]
        [0 0 3]
        sage: list(permutations.values())
        [[(1,2,3), (1,2,3)],
         [(1,3,2), (1,3,2)],
         [(1,3), (1,3)],
         [(1,2), (1,2)],
         [(), ()],
         [(2,3), (2,3)]]
        sage: PM_max.automorphisms_of_rows_and_columns()
        [((), ()),
         ((1,2,3), (1,2,3)),
         ((1,3,2), (1,3,2)),
         ((2,3), (2,3)),
         ((1,2), (1,2)),
         ((1,3), (1,3))]
        sage: PMs = ( i._palp_PM_max(check=True)
        ....:         for i in ReflexivePolytopes(2) )
        sage: results = ( len(i) == len(j.automorphisms_of_rows_and_columns())
        ....:             for j, i in PMs )
        sage: all(results)  # long time
        True
    """
    cdef Matrix_integer_dense PM = self.vertex_facet_pairing_matrix()
    cdef int n_v = PM.ncols()
    cdef int n_f = PM.nrows()
    S_v = SymmetricGroup(n_v)
    S_f = SymmetricGroup(n_f)

    # and find all the ways of making the first row of PM_max
    def index_of_max(iterable):
        # returns the index of max of any iterable
        return max(enumerate(iterable), key=lambda x: x[1])[0]

    cdef int n_s = 1
    cdef dict permutations = {0: [S_f.one(), S_v.one()]}
    cdef int j, k, m, d
    cdef int element, max_element

    for j in range(n_v):
        m = index_of_max(PM[0, i] for i in range(j, n_v))
        if m > 0:
            permutations[0][1] = (<PermutationGroupElement> permutations[0][1])._transpose_left(j + 1, m + j + 1)
    first_row = list(PM[0])

    # Arrange other rows one by one and compare with first row
    for k in range(1, n_f):
        # Error for k == 1 already!
        permutations[n_s] = [S_f.one(), S_v.one()]
        m = index_of_max(PM[k, (<PermutationGroupElement> permutations[n_s][1])(j+1) - 1] for j in range(n_v))
        if m > 0:
            permutations[n_s][1] = (<PermutationGroupElement> permutations[n_s][1])._transpose_left(1, m + 1)
        d = PM[k, (<PermutationGroupElement> permutations[n_s][1])(1) - 1] - (<PermutationGroupElement> permutations[0][1])(first_row)[0]
        if d < 0:
            # The largest elt of this row is smaller than largest elt
            # in 1st row, so nothing to do
            continue
        # otherwise:
        for i in range(1, n_v):
            max_element = PM[k, (<PermutationGroupElement> permutations[n_s][1])(i + 1) - 1]
            m = i
            for j in range(i + 1, n_v):
                element = PM[k, (<PermutationGroupElement> permutations[n_s][1])(j + 1) - 1]
                if element > max_element:
                    max_element = element
                    m = j
            if m > i:
                permutations[n_s][1] = (<PermutationGroupElement> permutations[n_s][1])._transpose_left(i + 1, m + 1)
            if d == 0:
                d = (PM[k, (<PermutationGroupElement> permutations[n_s][1])(i+1) - 1]
                     - (<PermutationGroupElement> permutations[0][1])(first_row)[i])
                if d < 0:
                    break
        if d < 0:
            # This row is smaller than 1st row, so nothing to do
            del permutations[n_s]
            continue
        permutations[n_s][0] = (<PermutationGroupElement> permutations[n_s][0])._transpose_left(1, k + 1)
        if d == 0:
            # This row is the same, so we have a symmetry!
            n_s += 1
        else:
            # This row is larger, so it becomes the first row and
            # the symmetries reset.
            first_row = list(PM[k])
            permutations = {0: permutations[n_s]}
            n_s = 1
    permutations = {k: permutations[k] for k in permutations if k < n_s}

    cdef tuple b = tuple(PM[(<PermutationGroupElement> permutations[0][0])(1) - 1,
                            (<PermutationGroupElement> permutations[0][1])(j+1) - 1] for j in range(n_v))
    # Work out the restrictions the current permutations
    # place on other permutations as a automorphisms
    # of the first row
    # The array is such that:
    # S = [i, 1, ..., 1 (ith), j, i+1, ..., i+1 (jth), k ... ]
    # describes the "symmetry blocks"
    cdef list S = list(range(1, n_v + 1))
    for i in range(1, n_v):
        if b[i-1] == b[i]:
            S[i] = S[i-1]
            S[S[i]-1] += 1
        else:
            S[i] = i + 1

    cdef int l, np, cf, ccf, n_s_bar, d1, v0, vc, vj
    cdef list l_r

    # We determine the other rows of PM_max in turn by use of perms and
    # aut on previous rows.
    for l in range(1, n_f - 1):
        n_s = len(permutations)
        n_s_bar = n_s
        cf = 0
        l_r = [0]*n_v
        # Search for possible local permutations based off previous
        # global permutations.
        for k in range(n_s_bar - 1, -1, -1):
            # number of local permutations associated with current global
            n_p = 0
            ccf = cf
            permutations_bar = {0: list(permutations[k])}
            # We look for the line with the maximal entry in the first
            # subsymmetry block, i.e. we are allowed to swap elements
            # between 0 and S(0)
            for s in range(l, n_f):
                for j in range(1, S[0]):
                    v0 = PM[(<PermutationGroupElement> permutations_bar[n_p][0])(s+1) - 1,
                            (<PermutationGroupElement> permutations_bar[n_p][1])(1) - 1]
                    vj = PM[(<PermutationGroupElement> permutations_bar[n_p][0])(s+1) - 1,
                            (<PermutationGroupElement> permutations_bar[n_p][1])(j+1) - 1]
                    if v0 < vj:
                        permutations_bar[n_p][1] = (<PermutationGroupElement> permutations_bar[n_p][1])._transpose_left(1, j + 1)
                if ccf == 0:
                    l_r[0] = PM[(<PermutationGroupElement> permutations_bar[n_p][0])(s+1) - 1,
                                (<PermutationGroupElement> permutations_bar[n_p][1])(1) - 1]
                    if s != l:
                        permutations_bar[n_p][0] = (<PermutationGroupElement> permutations_bar[n_p][0])._transpose_left(l + 1, s + 1)
                    n_p += 1
                    ccf = 1
                    permutations_bar[n_p] = list(permutations[k])
                else:
                    d1 = PM[(<PermutationGroupElement> permutations_bar[n_p][0])(s+1) - 1,
                            (<PermutationGroupElement> permutations_bar[n_p][1])(1) - 1]
                    d = d1 - l_r[0]
                    if d < 0:
                        # We move to the next line
                        continue
                    elif d==0:
                        # Maximal values agree, so possible symmetry
                        if s != l:
                            permutations_bar[n_p][0] = (<PermutationGroupElement> permutations_bar[n_p][0])._transpose_left(l + 1, s + 1)
                        n_p += 1
                        permutations_bar[n_p] = list(permutations[k])
                    else:
                        # We found a greater maximal value for first entry.
                        # It becomes our new reference:
                        l_r[0] = d1
                        if s != l:
                            permutations_bar[n_p][0] = (<PermutationGroupElement> permutations_bar[n_p][0])._transpose_left(l + 1, s + 1)
                        # Forget previous work done
                        cf = 0
                        permutations_bar = {0: list(permutations_bar[n_p])}
                        n_p = 1
                        permutations_bar[n_p] = list(permutations[k])
                        n_s = k + 1
            # Check if the permutations found just now work
            # with other elements
            for c in range(1, n_v):
                h = S[c]
                ccf = cf
                # Now let us find out where the end of the
                # next symmetry block is:
                if h < c + 1:
                    h = S[h - 1]
                s = n_p
                # Check through this block for each possible permutation
                while s > 0:
                    s -= 1
                    # Find the largest value in this symmetry block
                    for j in range(c + 1, h):
                        vc = PM[(<PermutationGroupElement> permutations_bar[s][0])(l+1) - 1,
                                (<PermutationGroupElement> permutations_bar[s][1])(c+1) - 1]
                        vj = PM[(<PermutationGroupElement> permutations_bar[s][0])(l+1) - 1,
                                (<PermutationGroupElement> permutations_bar[s][1])(j+1) - 1]
                        if vc < vj:
                            permutations_bar[s][1] = (<PermutationGroupElement> permutations_bar[s][1])._transpose_left(c + 1, j + 1)
                    if ccf == 0:
                        # Set reference and carry on to next permutation
                        l_r[c] = PM[(<PermutationGroupElement> permutations_bar[s][0])(l+1) - 1,
                                    (<PermutationGroupElement> permutations_bar[s][1])(c+1) - 1]
                        ccf = 1
                    else:
                        d1 = PM[(<PermutationGroupElement> permutations_bar[s][0])(l+1) - 1,
                                (<PermutationGroupElement> permutations_bar[s][1])(c+1) - 1]
                        d = d1 - l_r[c]
                        if d < 0:
                            n_p -= 1
                            if s < n_p:
                                permutations_bar[s] = list(permutations_bar[n_p])
                        elif d > 0:
                            # The current case leads to a smaller matrix,
                            # hence this case becomes our new reference
                            l_r[c] = d1
                            cf = 0
                            n_p = s + 1
                            n_s = k + 1
            # Update permutations
            if (n_s - 1) > k:
                permutations[k] = list(permutations[n_s - 1])
            n_s -= 1
            for s in range(n_p):
                permutations[n_s] = list(permutations_bar[s])
                n_s += 1
            cf = n_s
        permutations = {k: permutations[k] for k in permutations if k < n_s}
        # If the automorphisms are not already completely restricted,
        # update them
        if S != list(range(1, n_v + 1)):
            # Take the old automorphisms and update by
            # the restrictions the last worked out
            # row imposes.
            c = 0
            M = tuple(PM[(<PermutationGroupElement> permutations[0][0])(l+1) - 1,
                         (<PermutationGroupElement> permutations[0][1])(j+1) - 1] for j in range(n_v))
            while c < n_v:
                s = S[c] + 1
                S[c] = c + 1
                c += 1
                while c < (s - 1):
                    if M[c] == M[c - 1]:
                        S[c] = S[c - 1]
                        S[S[c] - 1] += 1
                    else:
                        S[c] = c + 1
                    c += 1
    # Now we have the perms, we construct PM_max using one of them
    PM_max = PM.with_permuted_rows_and_columns(*permutations[0])
    if check:
        return (PM_max, permutations)
    else:
        return PM_max
