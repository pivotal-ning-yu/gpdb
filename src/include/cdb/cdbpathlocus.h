/*-------------------------------------------------------------------------
 *
 * cdbpathlocus.h
 *
 *
 * Portions Copyright (c) 2005-2008, Greenplum inc
 * Portions Copyright (c) 2012-Present Pivotal Software, Inc.
 *
 *
 * IDENTIFICATION
 *	    src/include/cdb/cdbpathlocus.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef CDBPATHLOCUS_H
#define CDBPATHLOCUS_H

#include "nodes/pg_list.h"      /* List */
#include "nodes/bitmapset.h"    /* Bitmapset */

struct Plan;                    /* defined in plannodes.h */
struct RelOptInfo;              /* defined in relation.h */
struct PlannerInfo;				/* defined in relation.h */


/*
 * This flag controls the policy type returned from
 * cdbpathlocus_from_baserel() for non-partitioned tables.
 * It's a kludge put in to allow us to do
 * distributed queries on catalog tables, like pg_class
 * and pg_statistic.
 * To use it, simply set it to true before running a catalog query, then set
 * it back to false.
 */
extern bool cdbpathlocus_querysegmentcatalogs;


/*
 * CdbLocusType
 */
typedef enum CdbLocusType
{
    CdbLocusType_Null,
    CdbLocusType_Entry,         /* a single backend process on the entry db:
                                 * usually the qDisp itself, but could be a
                                 * qExec started by the entry postmaster.
                                 */
    CdbLocusType_SingleQE,      /* a single backend process on any db: the
                                 * qDisp itself, or a qExec started by a
                                 * segment postmaster or the entry postmaster.
                                 */
    CdbLocusType_General,       /* compatible with any locus (data is
                                 * self-contained in the query plan or
                                 * generally available in any qExec or qDisp) */
    CdbLocusType_SegmentGeneral,/* generally available in any qExec, but not
				 * available in qDisp */
    CdbLocusType_Replicated,    /* replicated over all qExecs of an N-gang */
    CdbLocusType_Hashed,        /* hash partitioned over all qExecs of N-gang */
    CdbLocusType_HashedOJ,      /* result of hash partitioned outer join */
    CdbLocusType_Strewn,        /* partitioned on no known function */
    CdbLocusType_End            /* = last valid CdbLocusType + 1 */
} CdbLocusType;

#define CdbLocusType_IsValid(locustype)     \
    ((locustype) > CdbLocusType_Null &&     \
     (locustype) < CdbLocusType_End)

#define CdbLocusType_IsValidOrNull(locustype)   \
    ((locustype) >= CdbLocusType_Null &&        \
     (locustype) < CdbLocusType_End)

typedef struct CdbPartKey
{
	NodeTag		type;			/* T_CdbPartKey */
	int			numsegments;
    List	   *pathkeys;
} CdbPartKey;

#define CdbPartKey_Make(numsegments_, pathkeys_)\
	(CdbPartKey) { T_CdbPartKey, (numsegments_), (pathkeys_) }

#define CdbPartKey_Copy(partkey)				\
	CdbPartKey_Make((partkey).numsegments,		\
					copyObject((partkey).pathkeys))

#define CdbPartKey_NIL							\
	CdbPartKey_Make(0, NIL)

#define CdbPartKey_NumSegments(partkey)			\
	((partkey).numsegments)

#define CdbPartKey_PathKeys(partkey)			\
	((partkey).pathkeys)

#define CdbPartKey_Length(partkey)				\
	list_length((partkey).pathkeys)

#define CdbPartKey_IsEqualFast(a, b)				\
	((a).numsegments == (b).numsegments &&		\
	 (a).pathkeys == (b).pathkeys)

#define CdbPartKey_IsEqual(a, b)				\
	((a).numsegments == (b).numsegments &&		\
	 equal((a).pathkeys, (b).pathkeys))

/*
 * CdbPathLocus
 *
 * Specifies a distribution of tuples across processes.
 *
 * If the distribution is a hashed one (locustype == CdbLocusType_Hashed
 *      or CdbLocusType_HashedOJ), then the tuples are distributed based on
 *      values of a partitioning key.
 *
 *      A tuple's partitioning key is an m-tuple of values (v1, v2, ..., vm)
 *      computed by evaluating an m-tuple of expressions (e1, e2, ..., em)
 *      on the columns of the tuple.  Each expression 'ei' is drawn from
 *      the corresponding set of expressions Ei = {expr, expr, ... }
 *      in the i'th position of the m-List (E1, E2, ..., Em) that hangs
 *      from the 'partkey' field.  (The data structure used to represent
 *      these sets depends upon the locustype, as described below.)
 *      The CdbPathLocus_Degree() macro returns 'm'.
 *
 *      All choices of the 'ei' from the 'Ei' lead to an equivalent
 *      distribution of rows; thus the set of possible m-tuples of
 *      expressions (e1, e2, ..., em) forms an equivalence class
 *      with respect to the partitioning function.
 *
 *      We use this information primarily to optimize joins for which we
 *      have an equijoin predicate on every column of the partitioning key.
 *      In such a join, a row in which any partitioning key column is NULL
 *      cannot join with other rows.  So for our purposes here, equivalence
 *      with respect to partitioning pertains only to rows in which no
 *      partitioning key column is NULL.  In particular, we can disregard
 *      the distribution of null-augmented rows generated by outer join.
 *
 * If locustype == CdbLocusType_Hashed:
 *      Rows are distributed on a hash function of the partitioning key.
 *      The 'partkey' field points to a pathkey list (see pathkeys.c).
 *      Each of the sets 'Ei' is represented as a PathKey, and in particular
 *      its equivalence class, which is a List of expressions that are
 *      constrained by equality predicates to be equal to one another.
 *
 * If locustype == CdbLocusType_HashedOJ:
 *      Rows are distributed on a hash function of the partitioning key,
 *      the same as CdbLocusType_Hashed.  Each of the sets 'Ei' in the
 *      'partkey' list is represented as a List of PathKeys, where again,
 *      each pathkey represents an equivalence class. All the equivalence
 *      classes can be considered as equal for the purposes of the locus in
 *      a join relation. This case arises in the result of outer join.
 *
 * If locustype == CdbLocusType_Strewn:
 *      Rows are distributed according to a criterion that is unknown or
 *      may depend on inputs that are unknown or unavailable in the present
 *      context.  The 'partkey' field is NIL and the CdbPathLocus_Degree()
 *      macro returns 0.
 *
 * If the distribution is not partitioned, then the 'partkey' field is NIL
 *      and the CdbPathLocus_Degree() macro returns 0.
 */
typedef struct CdbPathLocus
{
    CdbLocusType    locustype;
    CdbPartKey		partkey_h;
    CdbPartKey		partkey_oj;
} CdbPathLocus;

#define CdbPathLocus_Degree(locus)          \
	(CdbPathLocus_IsHashed(locus) ? CdbPartKey_Length((locus).partkey_h) :	\
	 (CdbPathLocus_IsHashedOJ(locus) ? CdbPartKey_Length((locus).partkey_oj) : 0))

#define CdbPathLocus_NumSegments(locus)     \
	(CdbPathLocus_IsHashed(locus) ? CdbPartKey_NumSegments((locus).partkey_h) :	\
	 (CdbPathLocus_IsHashedOJ(locus) ? CdbPartKey_NumSegments((locus).partkey_oj) : 0))

#define CdbPathLocus_PathKeys(locus)     \
	(CdbPathLocus_IsHashed(locus) ? CdbPartKey_PathKeys((locus).partkey_h) :	\
	 (CdbPathLocus_IsHashedOJ(locus) ? CdbPartKey_PathKeys((locus).partkey_oj) : NIL))

/*
 * CdbPathLocus_IsEqual
 *
 * Returns true if one CdbPathLocus is exactly the same as the other.
 * To test for logical equivalence, use cdbpathlocus_compare() instead.
 */
#define CdbPathLocus_IsEqual(a, b)              \
            ((a).locustype == (b).locustype &&  \
			 CdbPartKey_IsEqualFast((a).partkey_h, (b).partkey_oj) &&	\
			 CdbPartKey_IsEqualFast((a).partkey_oj, (b).partkey_oj))

/*
 * CdbPathLocus_IsBottleneck
 *
 * Returns true if the locus indicates confinement to a single process:
 * either a singleton qExec (1-gang) on a segment db or the entry db, or
 * the qDisp process.
 */
#define CdbPathLocus_IsBottleneck(locus)        \
            (CdbPathLocus_IsEntry(locus) ||     \
             CdbPathLocus_IsSingleQE(locus))

/*
 * CdbPathLocus_IsPartitioned
 *
 * Returns true if the locus indicates partitioning across an N-gang, such
 * that each qExec has a disjoint subset of the rows.
 */
#define CdbPathLocus_IsPartitioned(locus)       \
            (CdbPathLocus_IsHashed(locus) ||    \
             CdbPathLocus_IsHashedOJ(locus) ||  \
             CdbPathLocus_IsStrewn(locus))

#define CdbPathLocus_IsNull(locus)          \
            ((locus).locustype == CdbLocusType_Null)
#define CdbPathLocus_IsEntry(locus)         \
            ((locus).locustype == CdbLocusType_Entry)
#define CdbPathLocus_IsSingleQE(locus)      \
            ((locus).locustype == CdbLocusType_SingleQE)
#define CdbPathLocus_IsGeneral(locus)       \
            ((locus).locustype == CdbLocusType_General)
#define CdbPathLocus_IsReplicated(locus)    \
            ((locus).locustype == CdbLocusType_Replicated)
#define CdbPathLocus_IsHashed(locus)        \
            ((locus).locustype == CdbLocusType_Hashed)
#define CdbPathLocus_IsHashedOJ(locus)      \
            ((locus).locustype == CdbLocusType_HashedOJ)
#define CdbPathLocus_IsStrewn(locus)        \
            ((locus).locustype == CdbLocusType_Strewn)
#define CdbPathLocus_IsSegmentGeneral(locus)        \
            ((locus).locustype == CdbLocusType_SegmentGeneral)

#define CdbPathLocus_MakeSimple(plocus, _locustype) \
    do {                                                \
        CdbPathLocus *_locus = (plocus);                \
        _locus->locustype = (_locustype);               \
        _locus->partkey_h = CdbPartKey_NIL;             \
        _locus->partkey_oj = CdbPartKey_NIL;            \
    } while (0)

#define CdbPathLocus_MakeNull(plocus)                   \
            CdbPathLocus_MakeSimple((plocus), CdbLocusType_Null)
#define CdbPathLocus_MakeEntry(plocus)                  \
            CdbPathLocus_MakeSimple((plocus), CdbLocusType_Entry)
#define CdbPathLocus_MakeSingleQE(plocus)               \
            CdbPathLocus_MakeSimple((plocus), CdbLocusType_SingleQE)
#define CdbPathLocus_MakeGeneral(plocus)                \
            CdbPathLocus_MakeSimple((plocus), CdbLocusType_General)
#define CdbPathLocus_MakeSegmentGeneral(plocus)                \
            CdbPathLocus_MakeSimple((plocus), CdbLocusType_SegmentGeneral)
#define CdbPathLocus_MakeReplicated(plocus)             \
            CdbPathLocus_MakeSimple((plocus), CdbLocusType_Replicated)
#define CdbPathLocus_MakeHashed(plocus, partkey_)       \
    do {                                                \
        CdbPathLocus *_locus = (plocus);                \
        _locus->locustype = CdbLocusType_Hashed;		\
        _locus->partkey_h = (partkey_);					\
        _locus->partkey_oj = CdbPartKey_NIL;            \
        Assert(cdbpathlocus_is_valid(*_locus));         \
        Assert(CdbPartKey_NumSegments(partkey_) > 0);   \
    } while (0)
#define CdbPathLocus_MakeHashedOJ(plocus, partkey_)     \
    do {                                                \
        CdbPathLocus *_locus = (plocus);                \
        _locus->locustype = CdbLocusType_HashedOJ;		\
        _locus->partkey_h = CdbPartKey_NIL;             \
        _locus->partkey_oj = (partkey_);				\
        Assert(cdbpathlocus_is_valid(*_locus));         \
        Assert(CdbPartKey_NumSegments(partkey_) > 0);   \
    } while (0)
#define CdbPathLocus_MakeStrewn(plocus)                 \
            CdbPathLocus_MakeSimple((plocus), CdbLocusType_Strewn)

/************************************************************************/

typedef enum
{
    CdbPathLocus_Comparison_Equal,
    CdbPathLocus_Comparison_Contains
} CdbPathLocus_Comparison;

bool
cdbpathlocus_compare(CdbPathLocus_Comparison    op,
                     CdbPathLocus               a,
                     CdbPathLocus               b);

/************************************************************************/

CdbPathLocus
cdbpathlocus_from_baserel(struct PlannerInfo   *root,
                          struct RelOptInfo    *rel);
CdbPathLocus
cdbpathlocus_from_exprs(struct PlannerInfo     *root,
                        List                   *hash_on_exprs);
CdbPathLocus
cdbpathlocus_from_subquery(struct PlannerInfo  *root,
                           struct Plan         *subqplan,
                           Index                subqrelid);

CdbPathLocus
cdbpathlocus_join(CdbPathLocus a, CdbPathLocus b);

/************************************************************************/

/*
 * cdbpathlocus_get_partkey_exprs
 *
 * Returns a List with one Expr for each partkey column.  Each item either is
 * in the given targetlist, or has no Var nodes that are not in the targetlist;
 * and uses only rels in the given set of relids.  Returns NIL if the
 * partkey cannot be expressed in terms of the given relids and targetlist.
 */
List *
cdbpathlocus_get_partkey_exprs(CdbPathLocus     locus,
                               Bitmapset       *relids,
                               List            *targetlist);

/*
 * cdbpathlocus_pull_above_projection
 *
 * Given a targetlist, and a locus evaluable before the projection is
 * applied, returns an equivalent locus evaluable after the projection.
 * Returns a strewn locus if the necessary inputs are not projected.
 *
 * 'relids' is the set of relids that may occur in the targetlist exprs.
 * 'targetlist' specifies the projection.  It is a List of TargetEntry
 *      or merely a List of Expr.
 * 'newvarlist' is an optional List of Expr, in 1-1 correspondence with
 *      'targetlist'.  If specified, instead of creating a Var node to
 *      reference a targetlist item, we plug in a copy of the corresponding
 *      newvarlist item.
 * 'newrelid' is the RTE index of the projected result, for finding or
 *      building Var nodes that reference the projected columns.
 *      Ignored if 'newvarlist' is specified.
 */
CdbPathLocus
cdbpathlocus_pull_above_projection(struct PlannerInfo  *root,
                                   CdbPathLocus         locus,
                                   Bitmapset           *relids,
                                   List                *targetlist,
                                   List                *newvarlist,
                                   Index                newrelid);

/************************************************************************/

/*
 * cdbpathlocus_is_hashed_on_exprs
 *
 * This function tests whether grouping on a given set of exprs can be done
 * in place without motion.
 *
 * For a hashed locus, returns false if the partkey has a column whose
 * equivalence class contains no expr belonging to the given list.
 */
bool
cdbpathlocus_is_hashed_on_exprs(CdbPathLocus locus, List *exprlist);

/*
 * cdbpathlocus_is_hashed_on_eclasses
 *
 * This function tests whether grouping on a given set of exprs can be done
 * in place without motion.
 *
 * For a hashed locus, returns false if the partkey has any column whose
 * equivalence class is not in 'eclasses' list.
 *
 * If 'ignore_constants' is true, any constants in the locus are ignored.
 */
bool
cdbpathlocus_is_hashed_on_eclasses(CdbPathLocus locus, List *eclasses, bool ignore_constants);

/*
 * cdbpathlocus_is_hashed_on_relids
 *
 * Used when a subquery predicate (such as "x IN (SELECT ...)") has been
 * flattened into a join with the tables of the current query.  A row of
 * the cross-product of the current query's tables might join with more
 * than one row from the subquery and thus be duplicated.  Removing such
 * duplicates after the join is called deduping.  If a row's duplicates
 * might occur in more than one partition, a Motion operator will be
 * needed to bring them together.  This function tests whether the join
 * result (whose locus is given) can be deduped in place without motion.
 *
 * For a hashed locus, returns false if the partkey has a column whose
 * equivalence class contains no Var node belonging to the given set of
 * relids.  Caller should specify the relids of the non-subquery tables.
 */
bool
cdbpathlocus_is_hashed_on_relids(CdbPathLocus locus, Bitmapset *relids);

/*
 * cdbpathlocus_is_valid
 *
 * Returns true if locus appears structurally valid.
 */
bool
cdbpathlocus_is_valid(CdbPathLocus locus);

#endif   /* CDBPATHLOCUS_H */
