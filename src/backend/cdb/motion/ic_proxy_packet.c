/*-------------------------------------------------------------------------
 *
 * ic_proxy_message.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "ic_proxy.h"
#include "ic_proxy_packet.h"
#include "ic_proxy_pkt_cache.h"

const char *
ic_proxy_message_type_to_str(ICProxyMessageType type)
{
	switch (type)
	{
		case IC_PROXY_MESSAGE_DATA:
			return "DATA";
		case IC_PROXY_MESSAGE_HELLO:
			return "HELLO";
		case IC_PROXY_MESSAGE_HELLO_ACK:
			return "HELLO ACK";
		case IC_PROXY_MESSAGE_PEER_QUIT:
			return "PEER QUIT";
		case IC_PROXY_MESSAGE_BYE:
			return "BYE";
		case IC_PROXY_MESSAGE_PAUSE:
			return "PAUSE";
		case IC_PROXY_MESSAGE_RESUME:
			return "RESUME";
		default:
			return "UNKNOWN";
	}
}

ICProxyPkt *
ic_proxy_message_new(ICProxyMessageType type, const ICProxyKey *key)
{
	ICProxyPkt *pkt = ic_proxy_pkt_cache_alloc(NULL);

	ic_proxy_message_init(pkt, type, key);

	return pkt;
}

void
ic_proxy_message_init(ICProxyPkt *pkt, ICProxyMessageType type,
					  const ICProxyKey *key)
{
	pkt->type = type;
	pkt->len = sizeof(*pkt);

	pkt->sessionId      = key->sessionId;
	pkt->commandId      = key->commandId;
	pkt->sendSliceIndex = key->sendSliceIndex;
	pkt->recvSliceIndex = key->recvSliceIndex;

	pkt->srcContentId   = key->localContentId;
	pkt->srcDbid        = key->localDbid;
	pkt->srcPid         = key->localPid;

	pkt->dstContentId   = key->remoteContentId;
	pkt->dstDbid        = key->remoteDbid;
	pkt->dstPid         = key->remotePid;
}

ICProxyPkt *
ic_proxy_pkt_new(const ICProxyKey *key, void *data, uint16 size)
{
	ICProxyPkt *pkt;

	Assert(size + sizeof(*pkt) <= IC_PROXY_MAX_PKT_SIZE);

	pkt = ic_proxy_pkt_cache_alloc(NULL);
	ic_proxy_message_init(pkt, IC_PROXY_MESSAGE_DATA, key);

	memcpy(((char *) pkt) + sizeof(*pkt), data, size);
	pkt->len = sizeof(*pkt) + size;


	return pkt;
}

ICProxyPkt *
ic_proxy_pkt_dup(const ICProxyPkt *pkt)
{
	ICProxyPkt *newpkt;

	newpkt = ic_proxy_pkt_cache_alloc(NULL);
	memcpy(newpkt, pkt, pkt->len);

	return newpkt;
}

void *
ic_proxy_pkt_dup_data(const ICProxyPkt *pkt)
{
	void	   *data;

	data = ic_proxy_pkt_cache_alloc(NULL);

	if (pkt->len > sizeof(*pkt))
		memcpy(data, ((char *) pkt) + sizeof(*pkt), pkt->len - sizeof(*pkt));

	return data;
}

const char *
ic_proxy_pkt_to_str(const ICProxyPkt *pkt)
{
	static char	buf[256];

	snprintf(buf, sizeof(buf),
			 "%s [con%d,cmd%d,slice[%hd->%hd] %hu bytes seg%hd:dbid%hu:p%d->seg%hd:dbid%hu:p%d]",
			 ic_proxy_message_type_to_str(pkt->type),
			 pkt->sessionId, pkt->commandId,
			 pkt->sendSliceIndex, pkt->recvSliceIndex,
			 pkt->len,
			 pkt->srcContentId, pkt->srcDbid, pkt->srcPid,
			 pkt->dstContentId, pkt->dstDbid, pkt->dstPid);

	return buf;
}

bool
ic_proxy_pkt_is_from_client(const ICProxyPkt *pkt, const ICProxyKey *key)
{
	return pkt->srcDbid        == key->localDbid
		&& pkt->srcPid         == key->localPid
		&& pkt->dstDbid        == key->remoteDbid
		&& pkt->dstPid         == key->remotePid
		&& pkt->sendSliceIndex == key->sendSliceIndex
		&& pkt->recvSliceIndex == key->recvSliceIndex
		;
}

bool
ic_proxy_pkt_is_to_client(const ICProxyPkt *pkt, const ICProxyKey *key)
{
	return pkt->dstDbid        == key->localDbid
		&& pkt->dstPid         == key->localPid
		&& pkt->srcDbid        == key->remoteDbid
		&& pkt->srcPid         == key->remotePid
		&& pkt->sendSliceIndex == key->sendSliceIndex
		&& pkt->recvSliceIndex == key->recvSliceIndex
		;
}

bool
ic_proxy_pkt_is_live(const ICProxyPkt *pkt, const ICProxyKey *key)
{
	return pkt->sessionId == key->sessionId
		&& pkt->commandId == key->commandId
		;
}

bool
ic_proxy_pkt_is_out_of_date(const ICProxyPkt *pkt, const ICProxyKey *key)
{
	return ((pkt->sessionId <  key->sessionId) ||
			(pkt->sessionId == key->sessionId &&
			 pkt->commandId <  key->commandId));
}

bool
ic_proxy_pkt_is_in_the_future(const ICProxyPkt *pkt, const ICProxyKey *key)
{
	return ((pkt->sessionId >  key->sessionId) ||
			(pkt->sessionId == key->sessionId &&
			 pkt->commandId >  key->commandId));
}
