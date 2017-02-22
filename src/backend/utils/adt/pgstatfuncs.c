/*-------------------------------------------------------------------------
 *
 * pgstatfuncs.c
 *	  Functions for accessing the statistics collector data
 *
 * Portions Copyright (c) 1996-2010, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  $PostgreSQL: pgsql/src/backend/utils/adt/pgstatfuncs.c,v 1.48 2008/01/01 19:45:52 momjian Exp $
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "funcapi.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "catalog/pg_type.h"
#include "utils/builtins.h"
#include "utils/fmgroids.h"
#include "utils/guc.h"
#include "utils/inet.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"
#include "libpq/ip.h"

/* bogus ... these externs should be in a header file */
extern Datum pg_stat_get_numscans(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_tuples_returned(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_tuples_fetched(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_tuples_inserted(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_tuples_updated(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_tuples_deleted(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_tuples_hot_updated(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_live_tuples(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_dead_tuples(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_blocks_fetched(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_blocks_hit(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_last_vacuum_time(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_last_autovacuum_time(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_last_analyze_time(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_last_autoanalyze_time(PG_FUNCTION_ARGS);

extern Datum pg_stat_get_backend_idset(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_activity(PG_FUNCTION_ARGS);
extern Datum pg_backend_pid(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_pid(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_session_id(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_dbid(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_userid(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_activity(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_waiting(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_activity_start(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_xact_start(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_start(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_client_addr(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_client_port(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_backend_waiting_reason(PG_FUNCTION_ARGS);

extern Datum pg_stat_get_db_numbackends(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_xact_commit(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_xact_rollback(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_blocks_fetched(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_blocks_hit(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_tuples_returned(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_tuples_fetched(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_tuples_inserted(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_tuples_updated(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_db_tuples_deleted(PG_FUNCTION_ARGS);

extern Datum pg_stat_get_bgwriter_timed_checkpoints(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_bgwriter_requested_checkpoints(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_bgwriter_buf_written_checkpoints(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_bgwriter_buf_written_clean(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_bgwriter_maxwritten_clean(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_buf_written_backend(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_buf_alloc(PG_FUNCTION_ARGS);

extern Datum pg_stat_get_queue_num_exec(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_queue_num_wait(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_queue_elapsed_exec(PG_FUNCTION_ARGS);
extern Datum pg_stat_get_queue_elapsed_wait(PG_FUNCTION_ARGS);

extern Datum pg_renice_session(PG_FUNCTION_ARGS);

extern Datum pg_stat_clear_snapshot(PG_FUNCTION_ARGS);
extern Datum pg_stat_reset(PG_FUNCTION_ARGS);

/* Global bgwriter statistics, from bgwriter.c */
extern PgStat_MsgBgWriter bgwriterStats;

static char *
pgstat_waiting_string(char reason)
{
	switch(reason)
	{
		case PGBE_WAITING_LOCK:
			return "lock";
		case PGBE_WAITING_REPLICATION:
			return "replication";
		default:
			return NULL;
	}
}

Datum
pg_stat_get_numscans(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->numscans);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_tuples_returned(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->tuples_returned);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_tuples_fetched(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->tuples_fetched);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_tuples_inserted(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->tuples_inserted);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_tuples_updated(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->tuples_updated);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_tuples_deleted(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->tuples_deleted);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_tuples_hot_updated(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->tuples_hot_updated);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_live_tuples(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->n_live_tuples);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_dead_tuples(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->n_dead_tuples);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_blocks_fetched(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->blocks_fetched);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_blocks_hit(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = (int64) (tabentry->blocks_hit);

	PG_RETURN_INT64(result);
}

Datum
pg_stat_get_last_vacuum_time(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	TimestampTz result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = tabentry->vacuum_timestamp;

	if (result == 0)
		PG_RETURN_NULL();
	else
		PG_RETURN_TIMESTAMPTZ(result);
}

Datum
pg_stat_get_last_autovacuum_time(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	TimestampTz result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = tabentry->autovac_vacuum_timestamp;

	if (result == 0)
		PG_RETURN_NULL();
	else
		PG_RETURN_TIMESTAMPTZ(result);
}

Datum
pg_stat_get_last_analyze_time(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	TimestampTz result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = tabentry->analyze_timestamp;

	if (result == 0)
		PG_RETURN_NULL();
	else
		PG_RETURN_TIMESTAMPTZ(result);
}

Datum
pg_stat_get_last_autoanalyze_time(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	TimestampTz result;
	PgStat_StatTabEntry *tabentry;

	if ((tabentry = pgstat_fetch_stat_tabentry(relid)) == NULL)
		result = 0;
	else
		result = tabentry->autovac_analyze_timestamp;

	if (result == 0)
		PG_RETURN_NULL();
	else
		PG_RETURN_TIMESTAMPTZ(result);
}

Datum
pg_stat_get_backend_idset(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;
	int		   *fctx;
	int32		result;

	/* stuff done only on the first call of the function */
	if (SRF_IS_FIRSTCALL())
	{
		/* create a function context for cross-call persistence */
		funcctx = SRF_FIRSTCALL_INIT();

		fctx = MemoryContextAlloc(funcctx->multi_call_memory_ctx,
								  2 * sizeof(int));
		funcctx->user_fctx = fctx;

		fctx[0] = 0;
		fctx[1] = pgstat_fetch_stat_numbackends();
	}

	/* stuff done on every call of the function */
	funcctx = SRF_PERCALL_SETUP();
	fctx = funcctx->user_fctx;

	fctx[0] += 1;
	result = fctx[0];

	if (result <= fctx[1])
	{
		/* do when there is more left to send */
		SRF_RETURN_NEXT(funcctx, Int32GetDatum(result));
	}
	else
	{
		/* do when there is no more left */
		SRF_RETURN_DONE(funcctx);
	}
}

Datum
pg_stat_get_activity(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;
		TupleDesc	tupdesc;
		int			nattr = 13;

		funcctx = SRF_FIRSTCALL_INIT();

		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		tupdesc = CreateTemplateTupleDesc(nattr, false);
		TupleDescInitEntry(tupdesc, (AttrNumber) 1, "datid", OIDOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 2, "procpid", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 3, "usesysid", OIDOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 4, "application_name", TEXTOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 5, "current_query", TEXTOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 6, "waiting", BOOLOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 7, "act_start", TIMESTAMPTZOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 8, "query_start", TIMESTAMPTZOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 9, "backend_start", TIMESTAMPTZOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 10, "client_addr", INETOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 11, "client_port", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 12, "sess_id", INT4OID, -1, 0);  /* GPDB */

		if (nattr > 12)
			TupleDescInitEntry(tupdesc, (AttrNumber) 13, "waiting_for", TEXTOID, -1, 0);

		funcctx->tuple_desc = BlessTupleDesc(tupdesc);

		funcctx->user_fctx = palloc0(sizeof(int));
		if (PG_ARGISNULL(0))
		{
			/* Get all backends */
			funcctx->max_calls = pgstat_fetch_stat_numbackends();
		}
		else
		{
			/*
			 * Get one backend - locate by pid.
			 *
			 * We lookup the backend early, so we can return zero rows if it
			 * doesn't exist, instead of returning a single row full of NULLs.
			 */
			int			pid = PG_GETARG_INT32(0);
			int			i;
			int			n = pgstat_fetch_stat_numbackends();

			for (i = 1; i <= n; i++)
			{
				PgBackendStatus *be = pgstat_fetch_stat_beentry(i);

				if (be)
				{
					if (be->st_procpid == pid)
					{
						*(int *) (funcctx->user_fctx) = i;
						break;
					}
				}
			}

			if (*(int *) (funcctx->user_fctx) == 0)
				/* Pid not found, return zero rows */
				funcctx->max_calls = 0;
			else
				funcctx->max_calls = 1;
		}

		MemoryContextSwitchTo(oldcontext);
	}

	/* stuff done on every call of the function */
	funcctx = SRF_PERCALL_SETUP();

	if (funcctx->call_cntr < funcctx->max_calls)
	{
		/* for each row */
		Datum		values[13];
		bool		nulls[13];
		HeapTuple	tuple;
		PgBackendStatus *beentry;

		MemSet(values, 0, sizeof(values));
		MemSet(nulls, 0, sizeof(nulls));

		if (*(int *) (funcctx->user_fctx) > 0)
		{
			/* Get specific pid slot */
			beentry = pgstat_fetch_stat_beentry(*(int *) (funcctx->user_fctx));
		}
		else
		{
			/* Get the next one in the list */
			beentry = pgstat_fetch_stat_beentry(funcctx->call_cntr + 1);		/* 1-based index */
		}
		if (!beentry)
		{
			int			i;

			for (i = 0; i < sizeof(nulls) / sizeof(nulls[0]); i++)
				nulls[i] = true;

			nulls[4] = false;
			values[4] = CStringGetTextDatum("<backend information not available>");

			tuple = heap_form_tuple(funcctx->tuple_desc, values, nulls);
			SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(tuple));
		}

		/* Values available to all callers */
		values[0] = ObjectIdGetDatum(beentry->st_databaseid);
		values[1] = Int32GetDatum(beentry->st_procpid);
		values[2] = ObjectIdGetDatum(beentry->st_userid);
		if (beentry->st_appname)
			values[3] = CStringGetTextDatum(beentry->st_appname);
		else
			nulls[3] = true;

		/* Values only available to same user or superuser */
		if (superuser() || beentry->st_userid == GetUserId())
		{
			SockAddr	zero_clientaddr;
			bool		waiting;

			if (*(beentry->st_activity) == '\0')
			{
				values[4] = CStringGetTextDatum("<command string not enabled>");
			}
			else
			{
				values[4] = CStringGetTextDatum(beentry->st_activity);
			}

			waiting = beentry->st_waiting != PGBE_WAITING_NONE;
			values[5] = BoolGetDatum(beentry->st_waiting);

			if (beentry->st_xact_start_timestamp != 0)
				values[6] = TimestampTzGetDatum(beentry->st_xact_start_timestamp);
			else
				nulls[6] = true;

			if (beentry->st_activity_start_timestamp != 0)
				values[7] = TimestampTzGetDatum(beentry->st_activity_start_timestamp);
			else
				nulls[7] = true;

			if (beentry->st_proc_start_timestamp != 0)
				values[8] = TimestampTzGetDatum(beentry->st_proc_start_timestamp);
			else
				nulls[8] = true;

			/* A zeroed client addr means we don't know */
			memset(&zero_clientaddr, 0, sizeof(zero_clientaddr));
			if (memcmp(&(beentry->st_clientaddr), &zero_clientaddr,
					   sizeof(zero_clientaddr)) == 0)
			{
				nulls[9] = true;
				nulls[10] = true;
			}
			else
			{
				if (beentry->st_clientaddr.addr.ss_family == AF_INET
#ifdef HAVE_IPV6
					|| beentry->st_clientaddr.addr.ss_family == AF_INET6
#endif
					)
				{
					char		remote_host[NI_MAXHOST];
					char		remote_port[NI_MAXSERV];
					int			ret;

					remote_host[0] = '\0';
					remote_port[0] = '\0';
					ret = pg_getnameinfo_all(&beentry->st_clientaddr.addr,
											 beentry->st_clientaddr.salen,
											 remote_host, sizeof(remote_host),
											 remote_port, sizeof(remote_port),
											 NI_NUMERICHOST | NI_NUMERICSERV);
					if (ret)
					{
						nulls[9] = true;
						nulls[10] = true;
					}
					else
					{
						clean_ipv6_addr(beentry->st_clientaddr.addr.ss_family, remote_host);
						values[9] = DirectFunctionCall1(inet_in,
											   CStringGetDatum(remote_host));
						values[10] = Int32GetDatum(atoi(remote_port));
					}
				}
				else if (beentry->st_clientaddr.addr.ss_family == AF_UNIX)
				{
					/*
					 * Unix sockets always reports NULL for host and -1 for
					 * port, so it's possible to tell the difference to
					 * connections we have no permissions to view, or with
					 * errors.
					 */
					nulls[9] = true;
					values[10] = DatumGetInt32(-1);
				}
				else
				{
					/* Unknown address type, should never happen */
					nulls[9] = true;
					nulls[10] = true;
				}
			}
			values[11] = Int32GetDatum(beentry->st_session_id);  /* GPDB */

			if (funcctx->tuple_desc->natts > 12)
			{
				char	st_waiting = beentry->st_waiting;
				char   *reason;

				reason = pgstat_waiting_string(st_waiting);

				if (reason != NULL)
					values[12] = CStringGetTextDatum(reason);
				else
					nulls[12] = true;
			}

		}
		else
		{
			/* No permissions to view data about this session */
			values[4] = CStringGetTextDatum("<insufficient privilege>");
			nulls[5] = true;
			nulls[6] = true;
			nulls[7] = true;
			nulls[8] = true;
			nulls[9] = true;
			nulls[10] = true;
			values[11] = Int32GetDatum(beentry->st_session_id);
			if (funcctx->tuple_desc->natts > 12)
				nulls[12] = true;
		}

		tuple = heap_form_tuple(funcctx->tuple_desc, values, nulls);

		SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(tuple));
	}
	else
	{
		/* nothing left */
		SRF_RETURN_DONE(funcctx);
	}
}

Datum
pg_stat_get_resgroup_activity(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;
		TupleDesc	tupdesc;
		int			nattr = 6;

		funcctx = SRF_FIRSTCALL_INIT();

		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		tupdesc = CreateTemplateTupleDesc(nattr, false);
		TupleDescInitEntry(tupdesc, (AttrNumber) 1, "procpid", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 2, "groupid", OIDOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 3, "groupname", TEXTOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 4, "queueing", BOOLOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 5, "queuereason", TEXTOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 6, "queueduration", INTERVALOID, -1, 0);

		funcctx->tuple_desc = BlessTupleDesc(tupdesc);

		/* nothing to return for now */
		funcctx->max_calls = 0;

		MemoryContextSwitchTo(oldcontext);
	}

	/* stuff done on every call of the function */
	funcctx = SRF_PERCALL_SETUP();

	if (funcctx->call_cntr < funcctx->max_calls)
	{
		/* will never reach here for now */
	}
	else
	{
		/* nothing left */
		SRF_RETURN_DONE(funcctx);
	}
}

Datum
pg_stat_get_resgroup(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;
		TupleDesc	tupdesc;
		int			nattr = 15;

		funcctx = SRF_FIRSTCALL_INIT();

		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		tupdesc = CreateTemplateTupleDesc(nattr, false);
		TupleDescInitEntry(tupdesc, (AttrNumber) 1, "groupid", OIDOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 2, "max_concurrency", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 3, "proposed_max_concurrency", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 4, "num_running", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 5, "num_queueing", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 6, "cpu_limit", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 7, "cpu_actual", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 8, "memory_limit", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 9, "proposed_memory_limit", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 10, "memory_actual", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 11, "memory_redzone", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 12, "memory_limit_per_query", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 13, "proposed_memory_limit_per_query", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 14, "memory_actual_per_query", FLOAT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 15, "memory_redzone_per_query", FLOAT4OID, -1, 0);

		funcctx->tuple_desc = BlessTupleDesc(tupdesc);

		/* nothing to return for now */
		funcctx->max_calls = 0;

		MemoryContextSwitchTo(oldcontext);
	}

	/* stuff done on every call of the function */
	funcctx = SRF_PERCALL_SETUP();

	if (funcctx->call_cntr < funcctx->max_calls)
	{
		/* will never reach here for now */
	}
	else
	{
		/* nothing left */
		SRF_RETURN_DONE(funcctx);
	}
}


Datum
pg_backend_pid(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT32(MyProcPid);
}


Datum
pg_stat_get_backend_pid(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	PgBackendStatus *beentry;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	PG_RETURN_INT32(beentry->st_procpid);
}

Datum
pg_stat_get_backend_session_id(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	PgBackendStatus *beentry;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	PG_RETURN_INT32(beentry->st_session_id);
}



Datum
pg_stat_get_backend_dbid(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	PgBackendStatus *beentry;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	PG_RETURN_OID(beentry->st_databaseid);
}


Datum
pg_stat_get_backend_userid(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	PgBackendStatus *beentry;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	PG_RETURN_OID(beentry->st_userid);
}


Datum
pg_stat_get_backend_activity(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	PgBackendStatus *beentry;
	const char *activity;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		activity = "<backend information not available>";
	else if (!superuser() && beentry->st_userid != GetUserId())
		activity = "<insufficient privilege>";
	else if (*(beentry->st_activity) == '\0')
		activity = "<command string not enabled>";
	else
		activity = beentry->st_activity;

	PG_RETURN_TEXT_P(cstring_to_text(activity));
}


Datum
pg_stat_get_backend_waiting(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	bool		result;
	PgBackendStatus *beentry;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	if (!superuser() && beentry->st_userid != GetUserId())
		PG_RETURN_NULL();

	result = beentry->st_waiting != PGBE_WAITING_NONE;

	PG_RETURN_BOOL(result);
}

Datum
pg_stat_get_backend_activity_start(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	TimestampTz result;
	PgBackendStatus *beentry;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	if (!superuser() && beentry->st_userid != GetUserId())
		PG_RETURN_NULL();

	result = beentry->st_activity_start_timestamp;

	/*
	 * No time recorded for start of current query -- this is the case if the
	 * user hasn't enabled query-level stats collection.
	 */
	if (result == 0)
		PG_RETURN_NULL();

	PG_RETURN_TIMESTAMPTZ(result);
}


Datum
pg_stat_get_backend_xact_start(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	TimestampTz result;
	PgBackendStatus *beentry;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	if (!superuser() && beentry->st_userid != GetUserId())
		PG_RETURN_NULL();

	result = beentry->st_xact_start_timestamp;

	if (result == 0)			/* not in a transaction */
		PG_RETURN_NULL();

	PG_RETURN_TIMESTAMPTZ(result);
}


Datum
pg_stat_get_backend_start(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	TimestampTz result;
	PgBackendStatus *beentry;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	if (!superuser() && beentry->st_userid != GetUserId())
		PG_RETURN_NULL();

	result = beentry->st_proc_start_timestamp;

	if (result == 0)			/* probably can't happen? */
		PG_RETURN_NULL();

	PG_RETURN_TIMESTAMPTZ(result);
}


Datum
pg_stat_get_backend_client_addr(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	PgBackendStatus *beentry;
	SockAddr	zero_clientaddr;
	char		remote_host[NI_MAXHOST];
	int			ret;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	if (!superuser() && beentry->st_userid != GetUserId())
		PG_RETURN_NULL();

	/* A zeroed client addr means we don't know */
	memset(&zero_clientaddr, 0, sizeof(zero_clientaddr));
	if (memcmp(&(beentry->st_clientaddr), &zero_clientaddr,
			   sizeof(zero_clientaddr)) == 0)
		PG_RETURN_NULL();

	switch (beentry->st_clientaddr.addr.ss_family)
	{
		case AF_INET:
#ifdef HAVE_IPV6
		case AF_INET6:
#endif
			break;
		default:
			PG_RETURN_NULL();
	}

	remote_host[0] = '\0';
	ret = pg_getnameinfo_all(&beentry->st_clientaddr.addr,
							 beentry->st_clientaddr.salen,
							 remote_host, sizeof(remote_host),
							 NULL, 0,
							 NI_NUMERICHOST | NI_NUMERICSERV);
	if (ret)
		PG_RETURN_NULL();

	clean_ipv6_addr(beentry->st_clientaddr.addr.ss_family, remote_host);

	return DirectFunctionCall1(inet_in, CStringGetDatum(remote_host));
}

Datum
pg_stat_get_backend_client_port(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	PgBackendStatus *beentry;
	SockAddr	zero_clientaddr;
	char		remote_port[NI_MAXSERV];
	int			ret;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	if (!superuser() && beentry->st_userid != GetUserId())
		PG_RETURN_NULL();

	/* A zeroed client addr means we don't know */
	memset(&zero_clientaddr, 0, sizeof(zero_clientaddr));
	if (memcmp(&(beentry->st_clientaddr), &zero_clientaddr,
			   sizeof(zero_clientaddr)) == 0)
		PG_RETURN_NULL();

	switch (beentry->st_clientaddr.addr.ss_family)
	{
		case AF_INET:
#ifdef HAVE_IPV6
		case AF_INET6:
#endif
			break;
		case AF_UNIX:
			PG_RETURN_INT32(-1);
		default:
			PG_RETURN_NULL();
	}

	remote_port[0] = '\0';
	ret = pg_getnameinfo_all(&beentry->st_clientaddr.addr,
							 beentry->st_clientaddr.salen,
							 NULL, 0,
							 remote_port, sizeof(remote_port),
							 NI_NUMERICHOST | NI_NUMERICSERV);
	if (ret)
		PG_RETURN_NULL();

	PG_RETURN_DATUM(DirectFunctionCall1(int4in,
										CStringGetDatum(remote_port)));
}

Datum
pg_stat_get_backend_waiting_reason(PG_FUNCTION_ARGS)
{
	int32		beid = PG_GETARG_INT32(0);
	PgBackendStatus *beentry;
	char	   *result;

	if ((beentry = pgstat_fetch_stat_beentry(beid)) == NULL)
		PG_RETURN_NULL();

	if (!superuser() && beentry->st_userid != GetUserId())
		PG_RETURN_NULL();

	result = pgstat_waiting_string(beentry->st_waiting);

	/* waiting for nothing */
	if (result == NULL)
		PG_RETURN_NULL();

	PG_RETURN_DATUM(CStringGetTextDatum(result));
}

Datum
pg_stat_get_db_numbackends(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int32		result;
	int			tot_backends = pgstat_fetch_stat_numbackends();
	int			beid;

	result = 0;
	for (beid = 1; beid <= tot_backends; beid++)
	{
		PgBackendStatus *beentry = pgstat_fetch_stat_beentry(beid);

		if (beentry && beentry->st_databaseid == dbid)
			result++;
	}

	PG_RETURN_INT32(result);
}


Datum
pg_stat_get_db_xact_commit(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_xact_commit);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_db_xact_rollback(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_xact_rollback);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_db_blocks_fetched(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_blocks_fetched);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_db_blocks_hit(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_blocks_hit);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_db_tuples_returned(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_tuples_returned);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_db_tuples_fetched(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_tuples_fetched);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_db_tuples_inserted(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_tuples_inserted);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_db_tuples_updated(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_tuples_updated);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_db_tuples_deleted(PG_FUNCTION_ARGS)
{
	Oid			dbid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatDBEntry *dbentry;

	if ((dbentry = pgstat_fetch_stat_dbentry(dbid)) == NULL)
		result = 0;
	else
		result = (int64) (dbentry->n_tuples_deleted);

	PG_RETURN_INT64(result);
}

Datum
pg_stat_get_bgwriter_timed_checkpoints(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgstat_fetch_global()->timed_checkpoints);
}

Datum
pg_stat_get_bgwriter_requested_checkpoints(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgstat_fetch_global()->requested_checkpoints);
}

Datum
pg_stat_get_bgwriter_buf_written_checkpoints(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgstat_fetch_global()->buf_written_checkpoints);
}

Datum
pg_stat_get_bgwriter_buf_written_clean(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgstat_fetch_global()->buf_written_clean);
}

Datum
pg_stat_get_bgwriter_maxwritten_clean(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgstat_fetch_global()->maxwritten_clean);
}

Datum
pg_stat_get_buf_written_backend(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgstat_fetch_global()->buf_written_backend);
}

Datum
pg_stat_get_buf_alloc(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(pgstat_fetch_global()->buf_alloc);
}


/* Discard the active statistics snapshot */
Datum
pg_stat_clear_snapshot(PG_FUNCTION_ARGS)
{
	pgstat_clear_snapshot();

	PG_RETURN_VOID();
}


Datum
pg_stat_get_queue_num_exec(PG_FUNCTION_ARGS)
{
	Oid			queueid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatQueueEntry *queueentry;

	if ((queueentry = pgstat_fetch_stat_queueentry(queueid)) == NULL)
		result = 0;
	else
		result = (int64) (queueentry->n_queries_exec);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_queue_num_wait(PG_FUNCTION_ARGS)
{
	Oid			queueid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatQueueEntry *queueentry;

	if ((queueentry = pgstat_fetch_stat_queueentry(queueid)) == NULL)
		result = 0;
	else
		result = (int64) (queueentry->n_queries_wait);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_queue_elapsed_exec(PG_FUNCTION_ARGS)
{
	Oid			queueid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatQueueEntry *queueentry;

	if ((queueentry = pgstat_fetch_stat_queueentry(queueid)) == NULL)
		result = 0;
	else
		result = (int64) (queueentry->elapsed_exec);

	PG_RETURN_INT64(result);
}


Datum
pg_stat_get_queue_elapsed_wait(PG_FUNCTION_ARGS)
{
	Oid			queueid = PG_GETARG_OID(0);
	int64		result;
	PgStat_StatQueueEntry *queueentry;

	if ((queueentry = pgstat_fetch_stat_queueentry(queueid)) == NULL)
		result = 0;
	else
		result = (int64) (queueentry->elapsed_wait);

	PG_RETURN_INT64(result);
}


/*
 * This should probably be moved to it's own file, or at least some better place.
 * I put it here because it uses pgstat_fetch_stat_beentry
 */

#include <sys/time.h>
#ifndef WIN32
#include <sys/resource.h>
#endif
#include "lib/stringinfo.h"
#include "cdb/cdbvars.h"
#include "cdb/cdbdisp_query.h"

/**
 * We no longer support pg_renice_session. For the time being issue an error.
 */
Datum
pg_renice_session(PG_FUNCTION_ARGS)
{
	int prio_out = -1;  
	elog(NOTICE, "Renicing a session is not longer supported. Please use the Query Prioritization feature.");
	PG_RETURN_INT32(prio_out);
}

/* Reset all counters for the current database */
Datum
pg_stat_reset(PG_FUNCTION_ARGS)
{
	pgstat_reset_counters();

	PG_RETURN_VOID();
}
