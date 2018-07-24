/*-------------------------------------------------------------------------
 *
 * nodeResult.c
 *	  support for constant nodes needing special code.
 *
 * DESCRIPTION
 *
 *		Result nodes are used in queries where no relations are scanned.
 *		Examples of such queries are:
 *
 * Portions Copyright (c) 2005-2008, Greenplum inc.
 * Portions Copyright (c) 2012-Present Pivotal Software, Inc.
 * Portions Copyright (c) 1996-2011, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/backend/executor/nodeResult.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "executor/executor.h"
#include "executor/nodeReshuffle.h"
#include "utils/memutils.h"

#include "catalog/pg_type.h"
#include "utils/lsyscache.h"

#include "cdb/cdbhash.h"
#include "cdb/cdbvars.h"
#include "cdb/memquota.h"
#include "executor/spi.h"

//static TupleTableSlot *NextInputSlot(ResultState *node);
//static bool TupleMatchesHashFilter(Result *resultNode, TupleTableSlot *resultSlot);

///**
// * Returns the next valid input tuple from the left subtree
// */
//static TupleTableSlot *NextInputSlot(ResultState *node)
//{
//    Assert(outerPlanState(node));
//
//    TupleTableSlot *inputSlot = NULL;
//
//    while (!inputSlot)
//    {
//        PlanState  *outerPlan = outerPlanState(node);
//
//        TupleTableSlot *candidateInputSlot = ExecProcNode(outerPlan);
//
//        if (TupIsNull(candidateInputSlot))
//        {
//            /**
//             * No more input tuples.
//             */
//            break;
//        }
//
//        ExprContext *econtext = node->ps.ps_ExprContext;
//
//        /*
//         * Reset per-tuple memory context to free any expression evaluation
//         * storage allocated in the previous tuple cycle.  Note this can't happen
//         * until we're done projecting out tuples from a scan tuple.
//         */
//        ResetExprContext(econtext);
//
//        econtext->ecxt_outertuple = candidateInputSlot;
//
//        /**
//         * Extract out qual in case result node is also performing filtering.
//         */
//        List *qual = node->ps.qual;
//        bool passesFilter = !qual || ExecQual(qual, econtext, false);
//
//        if (passesFilter)
//        {
//            inputSlot = candidateInputSlot;
//        }
//    }
//
//    return inputSlot;
//
//}

static int
EvalHashSegID(Datum *values, bool *nulls, List *policyAttrs, List *targetlist, int nsegs)
{
    CdbHash *hnew = makeCdbHash(nsegs);
    uint32 newSeg;
    ListCell *lc;

    Assert(policyAttrs);
    Assert(targetlist);

    cdbhashinit(hnew);

    foreach(lc, policyAttrs)
    {
        AttrNumber attidx = lfirst_int(lc);

        if (nulls[attidx - 1])
        {
            cdbhashnull(hnew);
        }
        else
        {
            TargetEntry *entry = list_nth(targetlist, attidx - 1);
            cdbhash(hnew, values[attidx - 1], exprType((Node *) entry->expr));
        }
    }

    newSeg = cdbhashreduce(hnew);

    return newSeg;

}

/* ----------------------------------------------------------------
 *		ExecResult(node)
 *
 *		returns the tuples from the outer plan which satisfy the
 *		qualification clause.  Since result nodes with right
 *		subtrees are never planned, we ignore the right subtree
 *		entirely (for now).. -cim 10/7/89
 *
 *		The qualification containing only constant clauses are
 *		checked first before any processing is done. It always returns
 *		'nil' if the constant qualification is not satisfied.
 * ----------------------------------------------------------------
 */
TupleTableSlot *
ExecReshuffle(ReshuffleState *node)
{
    PlanState *outerNode = outerPlanState(node);
    Reshuffle *reshuffle = (Reshuffle *) node->ps.plan;
    SplitUpdate *splitUpdate;

    TupleTableSlot *slot = NULL;
    TupleTableSlot *result = NULL;

    Datum *values;
    bool *nulls;

    int dmlAction;

    Assert(outerNode != NULL);
    Assert(IsA(outerNode->plan, SplitUpdate));

    splitUpdate = (SplitUpdate*)outerNode->plan;

    Assert(splitUpdate->actionColIdx > 0);

    /* Creates both TupleTableSlots. Returns DELETE TupleTableSlots.*/
    slot = ExecProcNode(outerNode);

    if (TupIsNull(slot))
    {
        return NULL;
    }

    slot_getallattrs(slot);
    values = slot_get_values(slot);
    nulls = slot_get_isnull(slot);

    dmlAction = DatumGetInt32(values[splitUpdate->actionColIdx - 1]);

    Assert(dmlAction == DML_INSERT || dmlAction == DML_DELETE);

    if (DML_INSERT == dmlAction)
    {
        values[reshuffle->tupleSegIdx - 1] =
                Int32GetDatum(EvalHashSegID(values, nulls, reshuffle->policyAttrs, reshuffle->plan.targetlist, getgpsegmentCount()));
    }
    else
    {
#ifdef USE_ASSERT_CHECKING

        Datum oldSegID = values[reshuffle->tupleSegIdx - 1];
        Datum newSegID = Int32GetDatum(EvalHashSegID(values, nulls, reshuffle->policyAttrs, reshuffle->plan.targetlist, reshuffle->oldSegs));

        Assert(oldSegID == newSegID);
#endif /* USE_ASSERT_CHECKING */
    }

    if (DatumGetInt32(values[reshuffle->tupleSegIdx - 1]) >= getgpsegmentCount())
        elog(ERROR, "ERROR SEGMENT ID : %d", DatumGetInt32(values[reshuffle->tupleSegIdx - 1]));


//    originalDelSegID = delete_values[plannode->tupleSegIdx - 1];
//
//    insert_values[plannode->tupleSegIdx - 1] =
//            Int32GetDatum(EvalHashSegID(insert_values, insert_nulls, 3, targetlist, getgpsegmentCount()));
//
//    delete_values[plannode->tupleSegIdx - 1] =
//            Int32GetDatum(EvalHashSegID(delete_values, delete_nulls, 3, targetlist, plannode->oldSegs));
//
//    Assert(deleteSegs == delete_values[plannode->tupleSegIdx - 1]);
//    if(DatumGetInt32(insert_values[plannode->tupleSegIdx - 1]) >= getgpsegmentCount())
//        elog(ERROR, "ERROR SEGMENT ID : %d, %d", DatumGetInt32(deleteSegs), DatumGetInt32(insert_values[plannode->tupleSegIdx - 1]));


    return result;
}

///**
// * Returns true if tuple matches hash filter.
// */
//static bool TupleMatchesHashFilter(Result *resultNode, TupleTableSlot *resultSlot)
//{
//    bool res = true;
//
//    Assert(resultNode);
//    Assert(!TupIsNull(resultSlot));
//
//    if (resultNode->hashFilter)
//    {
//        Assert(resultNode->hashFilter);
//        ListCell	*cell = NULL;
//
//        CdbHash *hash = makeCdbHash(GpIdentity.numsegments);
//        cdbhashinit(hash);
//        foreach(cell, resultNode->hashList)
//        {
//            /**
//             * Note that a table may be randomly distributed. The hashList will be empty.
//             */
//            Datum		hAttr;
//            bool		isnull;
//            Oid			att_type;
//
//            int attnum = lfirst_int(cell);
//
//            Assert(attnum > 0);
//            hAttr = slot_getattr(resultSlot, attnum, &isnull);
//            if (!isnull)
//            {
//                att_type = resultSlot->tts_tupleDescriptor->attrs[attnum - 1]->atttypid;
//
//                if (get_typtype(att_type) == 'd')
//                    att_type = getBaseType(att_type);
//
//                /* CdbHash treats all array-types as ANYARRAYOID, it doesn't know how to hash
//                 * the individual types (why is this ?) */
//                if (typeIsArrayType(att_type))
//                    att_type = ANYARRAYOID;
//
//                cdbhash(hash, hAttr, att_type);
//            }
//            else
//                cdbhashnull(hash);
//        }
//        int targetSeg = cdbhashreduce(hash);
//
//        pfree(hash);
//
//        res = (targetSeg == GpIdentity.segindex);
//    }
//
//    return res;
//}
//
///* ----------------------------------------------------------------
// *		ExecResultMarkPos
// * ----------------------------------------------------------------
// */
//void
//ExecResultMarkPos(ResultState *node)
//{
//    PlanState  *outerPlan = outerPlanState(node);
//
//    if (outerPlan != NULL)
//        ExecMarkPos(outerPlan);
//    else
//        elog(DEBUG2, "Result nodes do not support mark/restore");
//}
//
///* ----------------------------------------------------------------
// *		ExecResultRestrPos
// * ----------------------------------------------------------------
// */
//void
//ExecResultRestrPos(ResultState *node)
//{
//    PlanState  *outerPlan = outerPlanState(node);
//
//    if (outerPlan != NULL)
//        ExecRestrPos(outerPlan);
//    else
//        elog(ERROR, "Result nodes do not support mark/restore");
//}





/* ----------------------------------------------------------------
 *		ExecInitResult
 *
 *		Creates the run-time state information for the result node
 *		produced by the planner and initializes outer relations
 *		(child nodes).
 * ----------------------------------------------------------------
 */

ReshuffleState *
ExecInitReshuffle(Reshuffle *node, EState *estate, int eflags)
{
    ReshuffleState *reshufflestate;

    /* check for unsupported flags */
    Assert(!(eflags & (EXEC_FLAG_MARK | EXEC_FLAG_BACKWARD)) ||
           outerPlan(node) != NULL);

    /*
     * create state structure
     */
    reshufflestate = makeNode(ReshuffleState);
    reshufflestate->ps.plan = (Plan *) node;
    reshufflestate->ps.state = estate;

    //resstate->inputFullyConsumed = false;
    //resstate->rs_checkqual = (node->resconstantqual == NULL) ? false : true;

    /*
     * Miscellaneous initialization
     *
     * create expression context for node
     */
    ExecAssignExprContext(estate, &reshufflestate->ps);

    //resstate->isSRF = false;

    /*resstate->ps.ps_TupFromTlist = false;*/

    /*
     * tuple table initialization
     */
    ExecInitResultTupleSlot(estate, &reshufflestate->ps);

    /*
     * initialize child expressions
     */
    //reshufflestate->ps.targetlist = (List *)
    //        ExecInitExpr((Expr *) node->plan.targetlist,
    //                     (PlanState *) reshufflestate);
    reshufflestate->ps.qual = (List *)
            ExecInitExpr((Expr *) node->plan.qual,
                         (PlanState *) reshufflestate);
    //reshufflestate->resconstantqual = ExecInitExpr((Expr *) node->resconstantqual,
     //                                        (PlanState *) resstate);

    /*
     * initialize child nodes
     */
    outerPlanState(reshufflestate) = ExecInitNode(outerPlan(node), estate, eflags);

    /*
     * we don't use inner plan
     */
    Assert(innerPlan(node) == NULL);

    /*
     * initialize tuple type and projection info
     */
    ExecAssignResultTypeFromTL(&reshufflestate->ps);
    ExecAssignProjectionInfo(&reshufflestate->ps, NULL);

#if 0
    if (!IsResManagerMemoryPolicyNone()
        && IsResultMemoryIntensive(node))
    {
        SPI_ReserveMemory(((Plan *)node)->operatorMemKB * 1024L);
    }
#endif

    return reshufflestate;
}

/* ----------------------------------------------------------------
 *		ExecEndResult
 *
 *		frees up storage allocated through C routines
 * ----------------------------------------------------------------
 */
void
ExecEndReshuffle(ReshuffleState *node)
{
    /*
     * Free the exprcontext
     */
    ExecFreeExprContext(&node->ps);

    /*
     * clean out the tuple table
     */
    ExecClearTuple(node->ps.ps_ResultTupleSlot);

    /*
     * shut down subplans
     */
    ExecEndNode(outerPlanState(node));

    EndPlanStateGpmonPkt(&node->ps);

}

void
ExecReScanReshuffle(ReshuffleState *node)
{
    //node->inputFullyConsumed = false;
    //node->isSRF = false;
    //node->rs_checkqual = (node->resconstantqual == NULL) ? false : true;

    /*
     * If chgParam of subnode is not null then plan will be re-scanned by
     * first ExecProcNode.
     */
    if (node->ps.lefttree &&
        node->ps.lefttree->chgParam == NULL)
        ExecReScan(node->ps.lefttree);
}
