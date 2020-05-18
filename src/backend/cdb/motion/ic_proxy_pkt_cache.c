/*-------------------------------------------------------------------------
 *
 * ic_proxy_pkt_cache.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#define IC_PROXY_LOG_LEVEL WARNING
#include "ic_proxy.h"
#include "ic_proxy_pkt_cache.h"

#include <uv.h>

typedef struct ICProxyPktCache ICProxyPktCache;

struct ICProxyPktCache
{
	ICProxyPktCache *next;
};

static struct 
{
	ICProxyPktCache *freelist;
	uint32		pkt_size;
	uint32		n_free;
	uint32		n_total;
} ic_proxy_pkt_cache;

void
ic_proxy_pkt_cache_init(uint32 pkt_size)
{
	ic_proxy_pkt_cache.freelist = NULL;
	ic_proxy_pkt_cache.pkt_size = pkt_size;
	ic_proxy_pkt_cache.n_free = 0;
	ic_proxy_pkt_cache.n_total = 0;
}

void
ic_proxy_pkt_cache_uninit(void)
{
	while (ic_proxy_pkt_cache.freelist)
	{
		ICProxyPktCache *cpkt = ic_proxy_pkt_cache.freelist;

		ic_proxy_pkt_cache.freelist = cpkt->next;
		ic_proxy_free(cpkt);
	}
}

void *
ic_proxy_pkt_cache_alloc(size_t *pkt_size)
{
	ICProxyPktCache *cpkt;

	if (ic_proxy_pkt_cache.freelist)
	{
		cpkt = ic_proxy_pkt_cache.freelist;

		ic_proxy_pkt_cache.freelist = cpkt->next;
		ic_proxy_pkt_cache.n_free--;
	}
	else
	{
		cpkt = ic_proxy_alloc(ic_proxy_pkt_cache.pkt_size);
		ic_proxy_pkt_cache.n_total++;
	}

	if (pkt_size)
		*pkt_size = ic_proxy_pkt_cache.pkt_size;

#if 0
	/* for debug purpose */
	memset(cpkt, 0, ic_proxy_pkt_cache.pkt_size);
#endif

	ic_proxy_log(LOG, "pkt-cache: allocated, %d free, %d total",
				 ic_proxy_pkt_cache.n_free, ic_proxy_pkt_cache.n_total);
	return cpkt;
}

void
ic_proxy_pkt_cache_alloc_buffer(uv_handle_t *handle, size_t size, uv_buf_t *buf)
{
	buf->base = ic_proxy_pkt_cache_alloc(&buf->len);
}

void
ic_proxy_pkt_cache_free(void *pkt)
{
	ICProxyPktCache *cpkt = pkt;

#if 0
	/* for debug purpose */
	memset(cpkt, 0, ic_proxy_pkt_cache.pkt_size);

	for (ICProxyPktCache *iter = ic_proxy_pkt_cache.freelist;
		 iter; iter = iter->next)
		Assert(iter != cpkt);
#endif

	cpkt->next = ic_proxy_pkt_cache.freelist;
	ic_proxy_pkt_cache.freelist = cpkt;
	ic_proxy_pkt_cache.n_free++;

	ic_proxy_log(LOG, "pkt-cache: recycled, %d free, %d total",
				 ic_proxy_pkt_cache.n_free, ic_proxy_pkt_cache.n_total);
}
