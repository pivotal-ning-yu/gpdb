/*-------------------------------------------------------------------------
 *
 * ic_proxy_iobuf.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "cdb/ml_ipc.h"					/* for ic-tcp packet */

#include "ic_proxy.h"
#include "ic_proxy_iobuf.h"
#include "ic_proxy_packet.h"
#include "ic_proxy_pkt_cache.h"


void
ic_proxy_ibuf_init(ICProxyIBuf *ibuf, uint16 header_size,
				   uint16 (* get_packet_size) (const void *data))
{
	ibuf->len = 0;
	ibuf->buf = NULL;

	ibuf->header_size = header_size;
	ibuf->get_packet_size = get_packet_size;
}

void
ic_proxy_ibuf_uninit(ICProxyIBuf *ibuf)
{
	if (ibuf->buf)
	{
		ic_proxy_pkt_cache_free(ibuf->buf);
		ibuf->buf = NULL;
	}
}

void
ic_proxy_ibuf_clear(ICProxyIBuf *ibuf)
{
	if (ibuf->len > 0)
		ic_proxy_log(WARNING, "ic-proxy-ibuf: dropped %d bytes", ibuf->len);

	ibuf->len = 0;
}

bool
ic_proxy_ibuf_empty(const ICProxyIBuf *ibuf)
{
	return ibuf->len == 0;
}

void
ic_proxy_ibuf_push(ICProxyIBuf *ibuf,
				   const char *data, uint16 size,
				   ic_proxy_iobuf_data_callback callback,
				   void *opaque)
{
	uint16		packet_size;
	uint16		delta;

	if (unlikely(ibuf->buf == NULL))
		ibuf->buf = ic_proxy_pkt_cache_alloc(NULL);

	/* a force-flush */
	if (unlikely(size == 0))
	{
		/* TODO: do we need to flush if ibuf->len is 0? */
		callback(opaque, ibuf->buf, ibuf->len);
		ibuf->len = 0;
		return;
	}

	if (ibuf->len > 0)
	{
		if (ibuf->len < ibuf->header_size)
		{
			/* haven't got a complete header yet */

			delta = Min(ibuf->header_size - ibuf->len, size);

			memcpy(ibuf->buf + ibuf->len, data, delta);
			ibuf->len += delta;
			data += delta;
			size -= delta;

			if (ibuf->len < ibuf->header_size)
				/* still not having a complete header */
				return;
		}

		{
			/* have a complete header now */

			packet_size = ibuf->get_packet_size(ibuf->buf);
			delta = Min(packet_size - ibuf->len, size);

			memcpy(ibuf->buf + ibuf->len, data, delta);
			ibuf->len += delta;
			data += delta;
			size -= delta;

			if (ibuf->len < packet_size)
				/* still not having a complete packet */
				return;
		}

		{
			/* have a complete pkt now */

			callback(opaque, ibuf->buf, packet_size);
			ibuf->len = 0;
		}
	}

	while (size >= ibuf->header_size)
	{
		packet_size = ibuf->get_packet_size(data);

		if (packet_size <= size)
		{
			/* got a complete pkt */
			callback(opaque, data, packet_size);

			data += packet_size;
			size -= packet_size;
		}
		else
			/* got a incomplete pkt */
			break;
	}

	if (size > 0)
	{
		/* got a incomplete pkt */
		memcpy(ibuf->buf, data, size);
		ibuf->len = size;
	}
}

static uint16
ic_proxy_ibuf_get_packet_size_b2c(const void *data)
{
	return *(const uint32 *) data;
}

void
ic_proxy_ibuf_init_b2c(ICProxyIBuf *ibuf)
{
	ic_proxy_ibuf_init(ibuf, PACKET_HEADER_SIZE,
					   ic_proxy_ibuf_get_packet_size_b2c);
}

static uint16
ic_proxy_ibuf_get_packet_size_p2p(const void *data)
{
	const ICProxyPkt *pkt = data;

	return pkt->len;
}

void
ic_proxy_ibuf_init_p2p(ICProxyIBuf *ibuf)
{
	ic_proxy_ibuf_init(ibuf, sizeof(ICProxyPkt),
					   ic_proxy_ibuf_get_packet_size_p2p);
}


void
ic_proxy_obuf_init(ICProxyOBuf *obuf, uint16 header_size,
				   void (* set_packet_size) (void *data, uint16 size))
{
	obuf->len = 0;
	obuf->buf = NULL;

	obuf->header_size = header_size;
	obuf->set_packet_size = set_packet_size;
}

void
ic_proxy_obuf_uninit(ICProxyOBuf *obuf)
{
	if (obuf->buf)
	{
		ic_proxy_pkt_cache_free(obuf->buf);
		obuf->buf = NULL;
	}
}

void *
ic_proxy_obuf_ensure_buffer(ICProxyOBuf *obuf)
{
	if (unlikely(obuf->buf == NULL))
	{
		obuf->buf = ic_proxy_pkt_cache_alloc(NULL);
		obuf->len = obuf->header_size;
	}

	return obuf->buf;
}

void
ic_proxy_obuf_push(ICProxyOBuf *obuf,
				   const char *data, uint16 size,
				   ic_proxy_iobuf_data_callback callback,
				   void *opaque)
{
	if (unlikely(obuf->buf == NULL))
		ic_proxy_log(ERROR,
					 "ic-proxy-obuf: the caller must init the header before pushing data");

	/*
	 * Need a flush when:
	 * - size == 0 means a force flush;
	 * - or no enough space for the new data;
	 */
	if (unlikely(size == 0 || size + obuf->len > IC_PROXY_MAX_PKT_SIZE))
	{
		if (obuf->header_size + size > IC_PROXY_MAX_PKT_SIZE)
			ic_proxy_log(ERROR,
						 "ic-proxy-obuf: no enough buffer to store the data:"
						 " the data size is %d bytes,"
						 " but the buffer size is only %zd bytes,"
						 " including a %d bytes header",
						 size, IC_PROXY_MAX_PKT_SIZE, obuf->header_size);

		/* TODO: should we flush if no data in the packet? */
		if (obuf->len == obuf->header_size)
			ic_proxy_log(LOG, "ic-proxy-obuf: no data to flush");
		else
		{
			obuf->set_packet_size(obuf->buf, obuf->len);
			callback(opaque, obuf->buf, obuf->len);

			/* we will reuse the header */
			obuf->len = obuf->header_size;
		}
	}

	/* the trailing data will be sent later */
	if (size > 0)
	{
		memcpy(obuf->buf + obuf->len, data, size);
		obuf->len += size;
	}
}

static void
ic_proxy_obuf_set_packet_size_b2c(void *data, uint16 size)
{
	*(uint32 *) data = size;
}

void
ic_proxy_obuf_init_b2c(ICProxyOBuf *obuf)
{
	ic_proxy_obuf_init(obuf, PACKET_HEADER_SIZE,
					   ic_proxy_obuf_set_packet_size_b2c);
}

static void
ic_proxy_obuf_set_packet_size_p2p(void *data, uint16 size)
{
	ICProxyPkt *pkt = data;

	pkt->len = size;
}

void
ic_proxy_obuf_init_p2p(ICProxyOBuf *obuf)
{
	ic_proxy_obuf_init(obuf, sizeof(ICProxyPkt),
					   ic_proxy_obuf_set_packet_size_p2p);
}
