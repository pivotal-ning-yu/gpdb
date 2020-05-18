/*-------------------------------------------------------------------------
 *
 * ic_proxy_router.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */


#include "ic_proxy.h"
#include "ic_proxy_server.h"
#include "ic_proxy_router.h"
#include "ic_proxy_packet.h"
#include "ic_proxy_pkt_cache.h"
#include "ic_proxy_server.h"


typedef struct ICProxyWriteReq ICProxyWriteReq;
typedef struct ICProxyLoopback ICProxyLoopback;


struct ICProxyWriteReq
{
	uv_write_t	req;

	ic_proxy_sent_cb callback;
	void	   *opaque;
};

struct ICProxyLoopback
{
	uv_check_t	check;

	List	   *queue;					/* List<ICProxyWriteReq *> */
};


static ICProxyLoopback ic_proxy_router_loopback;


static void
ic_proxy_router_loopback_on_check(uv_check_t *handle)
{
	List	   *queue;
	ListCell   *cell;

	uv_check_stop(&ic_proxy_router_loopback.check);

	/*
	 * We must detach the queue before handling it, in case some new packets
	 * are queued during the process
	 */
	queue = ic_proxy_router_loopback.queue;
	ic_proxy_router_loopback.queue = NIL;

	foreach(cell, queue)
	{
		ICProxyDelay *delay = lfirst(cell);
		ICProxyClient *client;
		ICProxyKey	key;

		ic_proxy_key_from_p2c_pkt(&key, delay->pkt);
		client = ic_proxy_client_blessed_lookup(handle->loop, &key);

		ic_proxy_log(LOG, "ic-proxy-router: looped back %s to %s",
					 ic_proxy_pkt_to_str(delay->pkt),
					 ic_proxy_client_get_name(client));

		ic_proxy_client_on_p2c_data(client, delay->pkt,
									delay->callback, delay->opaque);

		/* do not forget to call the callback */
		if (delay->callback)
			delay->callback(delay->opaque, delay->pkt, 0);

		/* and do not forget to free the memory */
		ic_proxy_free(delay);
	}

	list_free(queue);
}

static void
ic_proxy_router_loopback_push(ICProxyPkt *pkt,
							  ic_proxy_sent_cb callback, void *opaque)
{
	ICProxyDelay *delay;

	ic_proxy_log(LOG, "ic-proxy-router: looping back %s",
				 ic_proxy_pkt_to_str(pkt));

	if (ic_proxy_router_loopback.queue == NIL)
		uv_check_start(&ic_proxy_router_loopback.check,
					   ic_proxy_router_loopback_on_check);

	delay = ic_proxy_peer_build_delay(NULL, pkt, callback, opaque);
	ic_proxy_router_loopback.queue = lappend(ic_proxy_router_loopback.queue, delay);
}

void
ic_proxy_router_init(uv_loop_t *loop)
{
	uv_check_init(loop, &ic_proxy_router_loopback.check);
	ic_proxy_router_loopback.queue = NIL;
}

void
ic_proxy_router_uninit(void)
{
	List	   *queue;
	ListCell   *cell;

	queue = ic_proxy_router_loopback.queue;
	ic_proxy_router_loopback.queue = NIL;

	uv_check_stop(&ic_proxy_router_loopback.check);

	foreach(cell, queue)
	{
		ICProxyDelay *delay = lfirst(cell);

		/*
		 * TODO: this function is only called on exiting, so it's better to
		 * drop the callbacks silently, right?
		 */
#if 0
		if (delay->callback)
			delay->callback(delay->opaque, pkt, UV_ECANCELED);
#endif

		ic_proxy_pkt_cache_free(delay->pkt);
		ic_proxy_free(delay);
	}

	list_free(queue);
}

void
ic_proxy_router_route(uv_loop_t *loop, ICProxyPkt *pkt,
					  ic_proxy_sent_cb callback, void *opaque)
{
	if (pkt->dstDbid == pkt->srcDbid)
	{
		/*
		 * For a loopback target, we do not need to send the packet via a peer,
		 * we could pass the packet to the target client via
		 * ic_proxy_client_on_p2c_data(), however that function is not
		 * reentrantable, which happens on PAUSE & RESUME messages, so we must
		 * schedule it in a libuv check callback.
		 *
		 * TODO: when callback is NULL, we could pass the packet immediately.
		 */
		ic_proxy_router_loopback_push(pkt, callback, opaque);
	}
	else if (pkt->dstDbid == GpIdentity.dbid)
	{
		ICProxyClient *client;
		ICProxyKey	key;

		ic_proxy_key_from_p2c_pkt(&key, pkt);
		client = ic_proxy_client_blessed_lookup(loop, &key);

		ic_proxy_log(LOG, "ic-proxy-router: routing %s to %s",
					 ic_proxy_pkt_to_str(pkt),
					 ic_proxy_client_get_name(client));

		ic_proxy_client_on_p2c_data(client, pkt, callback, opaque);
	}
	else
	{
		ICProxyPeer *peer;

		peer = ic_proxy_peer_blessed_lookup(loop,
											pkt->dstContentId, pkt->dstDbid);

		ic_proxy_log(LOG, "ic-proxy-router: routing %s to %s",
					 ic_proxy_pkt_to_str(pkt), peer->name);

		ic_proxy_peer_route_data(peer, pkt, callback, opaque);
	}
}

static void
ic_proxy_router_on_write(uv_write_t *req, int status)
{
	ICProxyWriteReq *wreq = (ICProxyWriteReq *) req;
	ICProxyPkt *pkt = uv_req_get_data((uv_req_t *) req);

	if (status < 0)
		ic_proxy_log(LOG, "ic-proxy-router: fail to send %s: %s",
					 ic_proxy_pkt_to_str(pkt), uv_strerror(status));
	else
		ic_proxy_log(LOG, "ic-proxy-router: sent %s",
					 ic_proxy_pkt_to_str(pkt));

	if (wreq->callback)
		wreq->callback(wreq->opaque, pkt, status);

	ic_proxy_pkt_cache_free(pkt);
	ic_proxy_free(req);
}

void
ic_proxy_router_write(uv_stream_t *stream, ICProxyPkt *pkt, int32 offset,
					  ic_proxy_sent_cb callback, void *opaque)
{
	ICProxyWriteReq *wreq;
	uv_buf_t	wbuf;

	ic_proxy_log(LOG, "ic-proxy-router: sending %s", ic_proxy_pkt_to_str(pkt));

	wreq = ic_proxy_new(ICProxyWriteReq);
	uv_req_set_data((uv_req_t *) wreq, pkt);

	wreq->callback = callback;
	wreq->opaque = opaque;

	wbuf.base = ((char *) pkt) + offset;
	wbuf.len = pkt->len - offset;

	uv_write(&wreq->req, stream, &wbuf, 1, ic_proxy_router_on_write);
}
