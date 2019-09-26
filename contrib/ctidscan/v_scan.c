/*-------------------------------------------------------------------------
 *
 * v_scan.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2019-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "cdb/cdbaocsam.h"
#include "cdb/cdbappendonlyam.h"
#include "commands/explain.h"
#include "executor/nodeCustom.h"
#include "executor/nodeSeqscan.h"
#include "optimizer/cost.h"
#include "optimizer/paths.h"
#include "optimizer/pathnode.h"
#include "optimizer/restrictinfo.h"
#include "utils/lsyscache.h"
#include "utils/snapmgr.h"
#include "utils/tqual.h"

#include "gpvector.h"

/*
 * VectorScanState - state object of vectorscan on executor.
 */
typedef struct {
	CustomScanState	css;

	/* Below are copied from SeqScanState */

	struct HeapScanDescData *ss_currentScanDesc_heap;
	struct AppendOnlyScanDescData *ss_currentScanDesc_ao;
	struct AOCSScanDescData *ss_currentScanDesc_aocs;

	/* extra state for AOCS scans */
	bool	   *ss_aocs_proj;
	int			ss_aocs_ncol;
} VectorScanState;

/* static variables */
static bool			enable_vectorscan;
static set_rel_pathlist_hook_type set_rel_pathlist_next = NULL;

/* function declarations */
void	_PG_init(void);

static void SetVectorScanPath(PlannerInfo *root,
							  RelOptInfo *rel,
							  Index rti,
							  RangeTblEntry *rte);
/* CustomPathMethods */
static Plan *PlanVectorScanPath(PlannerInfo *root,
								RelOptInfo *rel,
								CustomPath *best_path,
								List *tlist,
								List *clauses,
								List *custom_plans);

/* CustomScanMethods */
static Node *CreateVectorScanState(CustomScan *custom_plan);

/* CustomScanExecMethods */
static void BeginVectorScan(CustomScanState *node, EState *estate, int eflags);
static void ReScanVectorScan(CustomScanState *node);
static TupleTableSlot *ExecVectorScan(CustomScanState *node);
static void EndVectorScan(CustomScanState *node);
static void ExplainVectorScan(CustomScanState *node,
							  List *ancestors,
							  ExplainState *es);

/* static table of custom-scan callbacks */
static CustomPathMethods	vectorscan_path_methods = {
	"vectorscan",			/* CustomName */
	PlanVectorScanPath,		/* PlanCustomPath */
	NULL,					/* TextOutCustomPath */
};

static CustomScanMethods	vectorscan_scan_methods = {
	"vectorscan",			/* CustomName */
	CreateVectorScanState,	/* CreateCustomScanState */
	NULL,					/* TextOutCustomScan */
};

static CustomExecMethods	vectorscan_exec_methods = {
	"vectorscan",			/* CustomName */
	BeginVectorScan,		/* BeginCustomScan */
	ExecVectorScan,			/* ExecCustomScan */
	EndVectorScan,			/* EndCustomScan */
	ReScanVectorScan,		/* ReScanCustomScan */
	NULL,					/* MarkPosCustomScan */
	NULL,					/* RestrPosCustomScan */
	ExplainVectorScan,		/* ExplainCustomScan */
};

static void
vectorscan_to_seqscan(const VectorScanState *vss, SeqScanState *sss)
{
	sss->ss = vss->css.ss;

	sss->ss_currentScanDesc_heap = vss->ss_currentScanDesc_heap;
	sss->ss_currentScanDesc_ao   = vss->ss_currentScanDesc_ao;
	sss->ss_currentScanDesc_aocs = vss->ss_currentScanDesc_aocs;

	sss->ss_aocs_proj = vss->ss_aocs_proj;
	sss->ss_aocs_ncol = vss->ss_aocs_ncol;
}

static void
vectorscan_from_seqscan(VectorScanState *vss, const SeqScanState *sss)
{
	vss->css.ss = sss->ss;

	vss->ss_currentScanDesc_heap = sss->ss_currentScanDesc_heap;
	vss->ss_currentScanDesc_ao   = sss->ss_currentScanDesc_ao;
	vss->ss_currentScanDesc_aocs = sss->ss_currentScanDesc_aocs;

	vss->ss_aocs_proj = sss->ss_aocs_proj;
	vss->ss_aocs_ncol = sss->ss_aocs_ncol;
}

/*
 * SetVectorScanPath - entrypoint of the series of custom-scan execution.
 * It adds CustomPath if referenced relation has inequality expressions on
 * the ctid system column.
 */
static void
SetVectorScanPath(PlannerInfo *root, RelOptInfo *baserel,
				Index rtindex, RangeTblEntry *rte)
{
	char			relkind;

	/* only plain relations are supported */
	if (rte->rtekind != RTE_RELATION)
		return;
	relkind = get_rel_relkind(rte->relid);
	if (relkind != RELKIND_RELATION &&
		relkind != RELKIND_MATVIEW &&
		relkind != RELKIND_TOASTVALUE)
		return;

	/*
	 * NOTE: Unlike built-in execution path, always we can have core path
	 * even though ctid scan is not available. So, simply, we don't add
	 * any paths, instead of adding disable_cost.
	 */
	if (!enable_vectorscan)
		return;

	/* FIXME: do not add vectorscan blindly */
	{
		CustomPath *cpath;
		Relids		required_outer;

		/*
		 * We don't support pushing join clauses into the quals of a vectorscan,
		 * but it could still have required parameterization due to LATERAL
		 * refs in its tlist.
		 */
		required_outer = baserel->lateral_relids;

		cpath = palloc0(sizeof(CustomPath));

		//cpath->flags = CUSTOMPATH_SUPPORT_BACKWARD_SCAN;
		//cpath->custom_private = ctid_quals;
		cpath->methods = &vectorscan_path_methods;

		cpath->path.type = T_CustomPath;
		cpath->path.pathtype = T_CustomScan;
		cpath->path.parent = baserel;
		cpath->path.param_info = get_baserel_parampathinfo(root, baserel,
														   required_outer);
		cpath->path.locus = cdbpathlocus_from_baserel(root, baserel);
		cpath->path.motionHazard = false;
		cpath->path.rescannable = true;
		cpath->path.pathkeys = NIL;		/* always unordered */
		cpath->path.sameslice_relids = baserel->relids;

		/* FIXME: real estimation */
		cost_seqscan(&cpath->path, root, baserel, cpath->path.param_info);
		/* HACK: force a lower cost */
		cpath->path.startup_cost = 0;
		cpath->path.total_cost = 0;

		add_path(baserel, &cpath->path);
	}

	/* calls secondary module if exists */
	if (set_rel_pathlist_next)
		set_rel_pathlist_next(root, baserel, rtindex, rte);
}

/*
 * PlanVectorScanPlan - A method of CustomPath; that populate a custom
 * object being delivered from CustomScan type, according to the supplied
 * CustomPath object.
 */
static Plan *
PlanVectorScanPath(PlannerInfo *root,
				 RelOptInfo *rel,
				 CustomPath *best_path,
				 List *tlist,
				 List *clauses,
				 List *custom_plans)
{
	List		   *ctid_quals = best_path->custom_private;
	CustomScan	   *cscan = makeNode(CustomScan);

	cscan->flags = best_path->flags;
	cscan->methods = &vectorscan_scan_methods;
	/* set ctid related quals */
	cscan->custom_exprs = ctid_quals;

	/* set scanrelid */
	cscan->scan.scanrelid = rel->relid;
	/* set targetlist as is  */
	cscan->scan.plan.targetlist = tlist;
	/* reduce RestrictInfo list to bare expressions */
	cscan->scan.plan.qual = extract_actual_clauses(clauses, false);
	cscan->scan.plan.lefttree = NULL;
	cscan->scan.plan.righttree = NULL;

	return &cscan->scan.plan;
}

/*
 * CreateVectorScanState - A method of CustomScan; that populate a custom
 * object being delivered from CustomScanState type, according to the
 * supplied CustomPath object.
 *
 * Derived from ExecInitSeqScanForPartition().
 */
static Node *
CreateVectorScanState(CustomScan *custom_plan)
{
	VectorScanState  *vss = palloc0(sizeof(VectorScanState));

	NodeSetTag(vss, T_CustomScanState);
	vss->css.methods = &vectorscan_exec_methods;

	return (Node *)&vss->css;
}

/*
 * BeginVectorScan - A method of CustomScanState; that initializes
 * the supplied VectorScanState object, at beginning of the executor.
 *
 * Derived from InitScanRelation().
 */
static void
BeginVectorScan(CustomScanState *node, EState *estate, int eflags)
{
	VectorScanState  *vss = (VectorScanState *) node;
	Relation		currentRelation = node->ss.ss_currentRelation;

	Assert(currentRelation);

	/* initialize a heapscan */
	if (RelationIsAoRows(currentRelation))
	{
		Snapshot appendOnlyMetaDataSnapshot;

		appendOnlyMetaDataSnapshot = node->ss.ps.state->es_snapshot;
		if (appendOnlyMetaDataSnapshot == SnapshotAny)
		{
			/*
			 * the append-only meta data should never be fetched with
			 * SnapshotAny as bogus results are returned.
			 */
			appendOnlyMetaDataSnapshot = GetTransactionSnapshot();
		}

		vss->ss_currentScanDesc_ao =
			appendonly_beginscan(currentRelation,
								 node->ss.ps.state->es_snapshot,
								 appendOnlyMetaDataSnapshot,
								 0, NULL);
	}
	else if (RelationIsAoCols(currentRelation))
	{
		Snapshot appendOnlyMetaDataSnapshot;
		SeqScanState sss;

		vectorscan_to_seqscan(vss, &sss);

		InitAOCSScanOpaque(&sss, currentRelation);

		vectorscan_from_seqscan(vss, &sss);

		appendOnlyMetaDataSnapshot = node->ss.ps.state->es_snapshot;
		if (appendOnlyMetaDataSnapshot == SnapshotAny)
		{
			/*
			 * the append-only meta data should never be fetched with
			 * SnapshotAny as bogus results are returned.
			 */
			appendOnlyMetaDataSnapshot = GetTransactionSnapshot();
		}

		vss->ss_currentScanDesc_aocs =
			aocs_beginscan(currentRelation,
						   node->ss.ps.state->es_snapshot,
						   appendOnlyMetaDataSnapshot,
						   NULL /* relationTupleDesc */,
						   vss->ss_aocs_proj);
	}
	else
	{
		vss->ss_currentScanDesc_heap =
			heap_beginscan(currentRelation,
						   estate->es_snapshot,
						   0,
						   NULL);
	}
}

/*
 * ReScanVectorScan - A method of CustomScanState; that rewind the current
 * seek position.
 */
static void
ReScanVectorScan(CustomScanState *node)
{
	VectorScanState  *vss = (VectorScanState *)node;
	SeqScanState sss;

	vectorscan_to_seqscan(vss, &sss);

	ExecReScanSeqScan(&sss);

	vectorscan_from_seqscan(vss, &sss);
}

/*
 * ExecVectorScan - A method of CustomScanState; that fetches a tuple
 * from the relation, if exist anymore.
 */
static TupleTableSlot *
ExecVectorScan(CustomScanState *node)
{
	VectorScanState  *vss = (VectorScanState *)node;
	SeqScanState sss;
	TupleTableSlot *tuple;

	vectorscan_to_seqscan(vss, &sss);

	tuple = ExecSeqScan(&sss);

	vectorscan_from_seqscan(vss, &sss);

	return tuple;
}

/*
 * CTidEndCustomScan - A method of CustomScanState; that closes heap and
 * scan descriptor, and release other related resources.
 *
 * Derived from ExecEndSeqScan().
 */
static void
EndVectorScan(CustomScanState *node)
{
	VectorScanState *vss = (VectorScanState *)node;

	/*
	 * close heap scan
	 */
	if (vss->ss_currentScanDesc_heap)
	{
		heap_endscan(vss->ss_currentScanDesc_heap);
		vss->ss_currentScanDesc_heap = NULL;
	}
	if (vss->ss_currentScanDesc_ao)
	{
		appendonly_endscan(vss->ss_currentScanDesc_ao);
		vss->ss_currentScanDesc_ao = NULL;
	}
	if (vss->ss_currentScanDesc_aocs)
	{
		aocs_endscan(vss->ss_currentScanDesc_aocs);
		vss->ss_currentScanDesc_aocs = NULL;
	}
}

/*
 * ExplainVectorScan - A method of CustomScanState; that shows extra info
 * on EXPLAIN command.
 */
static void
ExplainVectorScan(CustomScanState *node, List *ancestors, ExplainState *es)
{
}

/*
 * Entrypoint of this extension
 */
void
init_vectorscan(void)
{
	extern void my_register(const char *name, void *obj);

	my_register("vectorscan", &vectorscan_scan_methods);

	DefineCustomBoolVariable("enable_vectorscan",
							 "Enables the planner's use of vector-scan plans.",
							 NULL,
							 &enable_vectorscan,
							 true,
							 PGC_USERSET,
							 GUC_NOT_IN_SAMPLE,
							 NULL, NULL, NULL);

	/* registration of the hook to add alternative path */
	set_rel_pathlist_next = set_rel_pathlist_hook;
	set_rel_pathlist_hook = SetVectorScanPath;
}
