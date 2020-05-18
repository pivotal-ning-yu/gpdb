/*-------------------------------------------------------------------------
 *
 * ic_proxy_bgworker.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "postmaster/bgworker.h"
#include "storage/ipc.h"

#include "cdb/ic_proxy_bgworker.h"
#include "ic_proxy_server.h"

bool
ICProxyStartRule(Datum main_arg)
{
#if 0
	/* we only start fts probe on master when -E is specified */
	if (IsUnderMasterDispatchMode())
		return true;

	return false;
#endif

	return true;
}

/*
 * FtsProbeMain
 */
void
ICProxyMain(Datum main_arg)
{
#if 0
	/*
	 * reread postgresql.conf if requested
	 */
	pqsignal(SIGHUP, sigHupHandler);
	pqsignal(SIGINT, sigIntHandler);
#endif

	/* We're now ready to receive signals */
	BackgroundWorkerUnblockSignals();

#if 0
	/* Connect to our database */
	BackgroundWorkerInitializeConnection(DB_FOR_COMMON_ACCESS, NULL);
#endif

	/* main loop */
	proc_exit(ic_proxy_server_main());
}
