/*-------------------------------------------------------------------------
 *
 * gpexpand.c
 *	  Helper functions for gpexpand.
 *
 *
 * Copyright (c) 2018-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"


#include "catalog/gp_configuration_history.h"
#include "catalog/pg_auth_time_constraint.h"
#include "catalog/pg_description.h"
#include "catalog/pg_namespace.h"
#include "catalog/pg_partition.h"
#include "catalog/pg_partition_encoding.h"
#include "catalog/pg_partition_rule.h"
#include "catalog/pg_shdescription.h"
#include "catalog/pg_stat_last_operation.h"
#include "catalog/pg_stat_last_shoperation.h"
#include "catalog/pg_statistic.h"
#include "cdb/cdbutil.h"
#include "cdb/cdbvars.h"
#include "storage/lock.h"
#include "utils/rel.h"
#include "utils/relcache.h"
#include "utils/gpexpand.h"


extern uint32 FtsGetTotalSegments(void);

/*
 * Catalog lock.
 */
static LOCKTAG gp_expand_locktag =
{
	/* FIXME: how to fill the locktag? */
	.locktag_field1 = 0xdead,
	.locktag_field2 = 0xdead,
	.locktag_field3 = 0xdead,
	.locktag_field4 = 0xdd,
	.locktag_type = LOCKTAG_USERLOCK,
	.locktag_lockmethodid = USER_LOCKMETHOD,
};

/*
 * Lock the catalog lock in exclusive mode.
 *
 * This should only be called by gpexpand.
 */
Datum
gp_expand_lock_catalog(PG_FUNCTION_ARGS)
{
	LockAcquire(&gp_expand_locktag, AccessExclusiveLock, false, false);

	PG_RETURN_VOID();
}

/*
 * Prevent catalog being changed during gpexpand.
 *
 * This should be called before any catalog changes.
 *
 * Will raise an error if gpexpand already in progress or complete.
 */
void
gp_expand_protect_catalog_changes(Relation relation)
{
	LockAcquireResult	acquired;

	if (Gp_role != GP_ROLE_DISPATCH)
		/* only lock catalog updates on qd */
		return;

	if (RelationGetNamespace(relation) != PG_CATALOG_NAMESPACE)
		/* not catalog relations */
		return;

	switch (RelationGetRelid(relation))
	{
		case GpSegmentConfigRelationId:
		case GpConfigHistoryRelationId:
		case DescriptionRelationId:
		case PartitionRelationId:
		case PartitionRuleRelationId:
		case SharedDescriptionRelationId:
		case StatLastOpRelationId:
		case StatLastShOpRelationId:
		case StatisticRelationId:
		case PartitionEncodingRelationId:
		case AuthTimeConstraintRelationId:
			/* these catalog tables are only meaningful on qd */
			return;
	}

	/*
	 * The online expand util will hold this lwlock in LW_EXCLUSIVE mode.
	 * Acquire expand lock in dontWait mode. If the lock is not available,
	 * report error. Because online expand must be running, after that, the
	 * cluster size has been changed, and the catalog data has been copied
	 * to new segments, but this transaction gangs are still running on old
	 * segments. Any catalog changes won't be copied to new segment.
	 */
	/* FIXME: do not re-acquire the lock */
	acquired = LockAcquire(&gp_expand_locktag, AccessShareLock, false, true);
	if (acquired == LOCKACQUIRE_NOT_AVAIL)
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("gpexpand in progress, catalog changes are disallowed.")));

	/* FIXME: use a timestamp instead of size */
	if (getgpsegmentCount() != FtsGetTotalSegments())
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("cluster size is changed from %d to %d, "
						"catalog changes are disallowed",
						getgpsegmentCount(), FtsGetTotalSegments())));
}
