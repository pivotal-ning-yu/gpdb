/*-------------------------------------------------------------------------
 *
 * cdboidsync.c
 *
 * Make sure we don't re-use oids already used on the segment databases
 *
 * Copyright (c) 2007-2008, Greenplum inc
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <sys/types.h>
#include <sys/stat.h>

#include "access/heapam.h"
#include "access/transam.h"
#include "catalog/catalog.h"
#include "catalog/namespace.h"
#include "catalog/pg_tablespace.h"
#include "commands/tablespace.h"
#include "miscadmin.h"
#include "storage/fd.h"
#include "utils/builtins.h"
#include "utils/syscache.h"
#include "utils/relcache.h"
#include "access/subtrans.h"
#include "access/transam.h"
#include "miscadmin.h"
#include "storage/proc.h"
#include "utils/builtins.h"

#include "gp-libpq-fe.h"
#include "lib/stringinfo.h"
#include "cdb/cdbvars.h"
#include "cdb/cdbdisp.h"
#include "utils/int8.h"
#include "utils/lsyscache.h"
#include "cdb/cdboidsync.h"

static Oid
get_max_oid_from_segDBs(void)
{

	Oid	oid = 0;
	int		i;
	int 	resultCount = 0;
	struct pg_result **results = NULL;
	StringInfoData buffer;
	StringInfoData errbuf;
		
	initStringInfo(&buffer);
	
	appendStringInfo(&buffer, "select pg_highest_oid()");
	Assert(Gp_role == GP_ROLE_DISPATCH);
	
	initStringInfo(&errbuf);

	results = cdbdisp_dispatchRMCommand(buffer.data, true, &errbuf, &resultCount);

	if (errbuf.len > 0)
		ereport(ERROR, (errmsg("pg_highest_oid error (gathered %d results from cmd '%s')", resultCount, buffer.data),
						errdetail("%s", errbuf.data)));
										
	for (i = 0; i < resultCount; i++)
	{
		if (PQresultStatus(results[i]) != PGRES_TUPLES_OK)
		{
			elog(ERROR,"dboid: resultStatus not tuples_Ok");
		}
		else
		{
			/*
			 * Due to funkyness in the current dispatch agent code, instead of 1 result 
			 * per QE with 1 row each, we can get back 1 result per dispatch agent, with
			 * one row per QE controlled by that agent.
			 */
			int j;
			for (j = 0; j < PQntuples(results[i]); j++)
			{
				Oid tempoid = 0;
				tempoid =  atol(PQgetvalue(results[i], j, 0));
	
				/*
				 * We take the *numerically* maximum OID among the primaries.
				 *
				 * It might be tempting to find the "logically highest" OID among the
				 * primaries because we do pair-wise OID logical comparison
				 * elsewhere. However, that "logically maximum" of N Oids is undefined
				 * for N > 2 primaries. This is because "logically precedes" is not a
				 * transitive relationship.
				 *
				 * For example, take into consideration this set of four Oids:
				 * {0, 1<<30, 1<<31, 3 * (1 << 30)}.
				 */
				if (tempoid > oid)
					oid = tempoid;
			}
		}
	}

	pfree(errbuf.data);

	for (i = 0; i < resultCount; i++)
		PQclear(results[i]);

	free(results);
	
	return oid;
}

Datum
pg_highest_oid(PG_FUNCTION_ARGS __attribute__((unused)) )
{
	Oid			result;
	Oid			max_from_segdbs;

	result = ShmemVariableCache->nextOid;
	
	if (Gp_role == GP_ROLE_DISPATCH)
	{
		
		max_from_segdbs = get_max_oid_from_segDBs();

		/*
		 * Return the logically larger Oid between the numeric maximum of the
		 * primaries and the master's Oid counter. This is not 100% accurate
		 * because the primaries can be in a wide range of Oids... but this is
		 * good enough for the majority of production clusters.
		 */
		if (OidFollowsNextOid(max_from_segdbs))
			result = max_from_segdbs;
		
	}


	PG_RETURN_OID(result);

}

void
cdb_sync_oid_to_segments(void)
{
	if (Gp_role == GP_ROLE_DISPATCH && IsNormalProcessingMode())
	{
		Oid max_oid_from_primaries = get_max_oid_from_segDBs();

		AdvanceObjectId(max_oid_from_primaries + 1);
	}
	
}

