/*-------------------------------------------------------------------------
 *
 * resgroup.c
 *	  POSTGRES internals code for resource groups.
 *
 *
 * Copyright (c) 2006-2008, Greenplum inc.
 * Portions Copyright (c) 1996-2008, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <time.h>

#include "pgstat.h"
#include "access/heapam.h"
#include "access/twophase.h"
#include "access/twophase_rmgr.h"
#include "access/xact.h"
#include "catalog/pg_type.h"
#include "cdb/cdbgang.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "storage/lock.h"
#include "storage/lmgr.h"
#include "utils/builtins.h"
#include "utils/memutils.h"
#include "utils/portal.h"
#include "utils/ps_status.h"
#include "utils/resowner.h"
#include "utils/resscheduler.h"
#include "cdb/memquota.h"

Datum
pg_resgroup_get_status(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;
		TupleDesc	tupdesc;
		int			nattr = 9;

		funcctx = SRF_FIRSTCALL_INIT();

		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		tupdesc = CreateTemplateTupleDesc(nattr, false);
		TupleDescInitEntry(tupdesc, (AttrNumber) 1, "groupid", OIDOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 2, "num_running", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 3, "num_queueing", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 4, "cpu_usage", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 5, "memory_usage", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 6, "total_queue_duration", INTERVALOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 7, "total_execution_duration", INTERVALOID, -1, 0);

		funcctx->tuple_desc = BlessTupleDesc(tupdesc);

		funcctx->max_calls = 0;

		MemoryContextSwitchTo(oldcontext);
	}

	/* stuff done on every call of the function */
	funcctx = SRF_PERCALL_SETUP();

	if (funcctx->call_cntr < funcctx->max_calls)
	{
		/* for each row */
		Datum		values[8];
		bool		nulls[8];
		HeapTuple	tuple;
		Interval	interval;

		MemSet(values, 0, sizeof(values));
		MemSet(nulls, 0, sizeof(nulls));
		MemSet(&interval, 0, sizeof(interval));

		/* Fill with dummy values */
		values[0] = ObjectIdGetDatum(0);
		values[1] = Int32GetDatum(1);
		values[2] = Int32GetDatum(0);
		values[3] = Float4GetDatum(0.0);
		values[4] = Float4GetDatum(0.0);
		values[5] = IntervalPGetDatum(&interval);
		values[6] = IntervalPGetDatum(&interval);

		tuple = heap_form_tuple(funcctx->tuple_desc, values, nulls);

		SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(tuple));
	}
	else
	{
		/* nothing left */
		SRF_RETURN_DONE(funcctx);
	}
}

