/*-------------------------------------------------------------------------
 *
 * ic_proxy.h
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#ifndef IC_PROXY_H
#define IC_PROXY_H

#include "postgres.h"

#include "cdb/cdbinterconnect.h"
#include "cdb/cdbvars.h"
#include "nodes/pg_list.h"
#include "postmaster/postmaster.h"

#define IC_PROXY_BACKLOG 1024
#define IC_PROXY_INVALID_CONTENT ((uint16) -2)
#define IC_PROXY_INVALID_DBID ((int16) 0)
#define IC_PROXY_TRESHOLD_PAUSE 4
#define IC_PROXY_TRESHOLD_RESUME 2

#ifndef IC_PROXY_LOG_LEVEL
#define IC_PROXY_LOG_LEVEL LOG
#endif

//#define ic_proxy_alloc(size) MemoryContextAlloc(CurrentMemoryContext, size)
//#define ic_proxy_free(ptr) pfree(ptr)
//#define ic_proxy_new(type) ic_proxy_alloc(sizeof(type))

#define ic_proxy_alloc(size) MemoryContextAlloc(TopMemoryContext, size)
#define ic_proxy_free(ptr) pfree(ptr)
#define ic_proxy_new(type) ic_proxy_alloc(sizeof(type))

//#define ic_proxy_alloc(size) malloc(size)
//#define ic_proxy_free(ptr) free(ptr)
//#define ic_proxy_new(type) ic_proxy_alloc(sizeof(type))

#define ic_proxy_log(elevel, msg...) do { \
	if (elevel >= IC_PROXY_LOG_LEVEL) \
	{ \
		elog(elevel, msg); \
	} \
} while (0)

static inline void
ic_proxy_build_server_sock_path(char *buf, size_t bufsize)
{
	snprintf(buf, bufsize, "/tmp/.s.proxy.%d", PostPortNumber);
}

#endif   /* IC_PROXY_H */
