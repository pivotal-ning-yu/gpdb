/*-------------------------------------------------------------------------
 *
 * gpvector.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2019-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "gpvector.h"

#include "fmgr.h"

PG_MODULE_MAGIC;

void
_PG_init(void)
{
	//init_ctidscan();
	init_vectorscan();
}
