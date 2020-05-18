/*-------------------------------------------------------------------------
 *
 * ic_proxy_key.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#include "ic_proxy_key.h"

bool
ic_proxy_key_equal(const ICProxyKey *key1, const ICProxyKey *key2)
{
	return key1->localDbid       == key2->localDbid
		&& key1->localPid        == key2->localPid
		&& key1->remoteDbid      == key2->remoteDbid
		&& key1->remotePid       == key2->remotePid
		&& key1->commandId       == key2->commandId
		&& key1->sendSliceIndex  == key2->sendSliceIndex
		&& key1->recvSliceIndex  == key2->recvSliceIndex
		;
}

uint32
ic_proxy_key_hash(const ICProxyKey *key, Size keysize)
{
	/* derived from CONN_HASH_VALUE() */
	return (key->localPid ^ key->remotePid) + key->remoteDbid + key->commandId;
}

/*
 * Return 0 for match, otherwise for no match
 */
int
ic_proxy_key_equal_for_hash(const ICProxyKey *key1,
							const ICProxyKey *key2, Size keysize)
{
	return !ic_proxy_key_equal(key1, key2);
}

void
ic_proxy_key_from_pid(ICProxyKey *key,
					  int32 sessionId, uint32 commandId,
					  int16 sendSliceIndex, int16 recvSliceIndex,
					  int16 localContentId, uint16 localDbid, int32 localPid,
					  int16 remoteContentId, uint16 remoteDbid, int32 remotePid)
{
	key->sessionId = sessionId;
	key->commandId = commandId;
	key->sendSliceIndex = sendSliceIndex;
	key->recvSliceIndex = recvSliceIndex;

	key->localContentId = localContentId;
	key->localDbid = localDbid;
	key->localPid = localPid;

	key->remoteContentId = remoteContentId;
	key->remoteDbid = remoteDbid;
	key->remotePid = remotePid;
}

void
ic_proxy_key_from_p2c_pkt(ICProxyKey *key, const ICProxyPkt *pkt)
{
	ic_proxy_key_from_pid(key, pkt->sessionId, pkt->commandId,
						  pkt->sendSliceIndex, pkt->recvSliceIndex,
						  pkt->dstContentId, pkt->dstDbid, pkt->dstPid,
						  pkt->srcContentId, pkt->srcDbid, pkt->srcPid);
}

void
ic_proxy_key_from_c2p_pkt(ICProxyKey *key, const ICProxyPkt *pkt)
{
	ic_proxy_key_from_pid(key, pkt->sessionId, pkt->commandId,
						  pkt->sendSliceIndex, pkt->recvSliceIndex,
						  pkt->srcContentId, pkt->srcDbid, pkt->srcPid,
						  pkt->dstContentId, pkt->dstDbid, pkt->dstPid);
}

void
ic_proxy_key_reverse(ICProxyKey *key)
{
#define __swap(a, b) do { tmp = (a); (a) = (b); (b) = tmp; } while (0)

	int32		tmp;

	__swap(key->localContentId, key->remoteContentId);
	__swap(key->localDbid,      key->remoteDbid);
	__swap(key->localPid,       key->remotePid);

#undef __swap
}

const char *
ic_proxy_key_to_str(const ICProxyKey *key)
{
	static char	buf[256];

	snprintf(buf, sizeof(buf),
			 "[con%d,cmd%d,slice[%hd->%hd] seg%hd:dbid%hu:p%d->seg%hd:dbid%hu:p%d]",
			 key->sessionId, key->commandId,
			 key->sendSliceIndex, key->recvSliceIndex,
			 key->localContentId, key->localDbid, key->localPid,
			 key->remoteContentId, key->remoteDbid, key->remotePid);

	return buf;
}
