/*-------------------------------------------------------------------------
 *
 * ic_proxy_server.h
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#ifndef IC_PROXY_SERVER_H
#define IC_PROXY_SERVER_H

#include "postgres.h"

#include <uv.h>

#include "ic_proxy.h"
#include "ic_proxy_iobuf.h"
#include "ic_proxy_packet.h"
#include "ic_proxy_router.h"

#if UV_VERSION_HEX < 0x011300
static inline void
uv_req_set_data(uv_req_t *req, void* data)
{
	req->data = data;
}

static inline void *
uv_req_get_data(const uv_req_t *req)
{
	return req->data;
}

static inline uv_loop_t *
uv_handle_get_loop(const uv_handle_t* handle)
{
	return handle->loop;
}
#endif

typedef struct ICProxyPeer ICProxyPeer;
typedef struct ICProxyClient ICProxyClient;
typedef struct ICProxyDelay ICProxyDelay;

#define IC_PROXY_PEER_STATE_CONNECTING                  0x00000001
#define IC_PROXY_PEER_STATE_CONNECTED                   0x00000002
#define IC_PROXY_PEER_STATE_ACCEPTED                    0x00000004
#define IC_PROXY_PEER_STATE_LEGACY                      0x00000008
#define IC_PROXY_PEER_STATE_SENDING_HELLO               0x00000010
#define IC_PROXY_PEER_STATE_SENT_HELLO                  0x00000020
#define IC_PROXY_PEER_STATE_RECEIVING_HELLO_ACK         0x00000040
#define IC_PROXY_PEER_STATE_RECEIVED_HELLO_ACK          0x00000080
#define IC_PROXY_PEER_STATE_RECEIVING_HELLO             0x00000100
#define IC_PROXY_PEER_STATE_RECEIVED_HELLO              0x00000200
#define IC_PROXY_PEER_STATE_SENDING_HELLO_ACK           0x00000400
#define IC_PROXY_PEER_STATE_SENT_HELLO_ACK              0x00000800
#define IC_PROXY_PEER_STATE_SHUTTING                    0x00001000
#define IC_PROXY_PEER_STATE_SHUTTED                     0x00002000
#define IC_PROXY_PEER_STATE_CLOSING                     0x00004000
#define IC_PROXY_PEER_STATE_CLOSED                      0x00008000

#define IC_PROXY_PEER_STATE_READY_FOR_MESSAGE \
	(IC_PROXY_PEER_STATE_CONNECTED | \
	 IC_PROXY_PEER_STATE_ACCEPTED)

#define IC_PROXY_PEER_STATE_READY_FOR_DATA \
	(IC_PROXY_PEER_STATE_SENT_HELLO_ACK | \
	 IC_PROXY_PEER_STATE_RECEIVED_HELLO_ACK)

/* TODO: track the connecting status in a variable to ease debugging */
struct ICProxyPeer
{
	uv_tcp_t	tcp;

	int16		content;
	uint16		dbid;				/* dbid is peerid */

	uint32		state;

	/* outgoing queue for data that can't be sent immediately */
	List	   *reqs;

	ICProxyIBuf	ibuf;

	char		name[128];
};

struct ICProxyDelay
{
	/*
	 * note that a delay can be transferred from a legacy peer to a new one,
	 * so we must record the peer id instead of the peer pointer
	 */
	int16		content;
	uint16		dbid;

	ICProxyPkt *pkt;

	ic_proxy_sent_cb callback;
	void	   *opaque;
};


extern int ic_proxy_server_main(void);
extern void ic_proxy_server_quit(uv_loop_t *loop, bool relaunch);

extern ICProxyClient *ic_proxy_client_new(uv_loop_t *loop, bool placeholder);
extern const char *ic_proxy_client_get_name(ICProxyClient *client);
extern uv_stream_t *ic_proxy_client_get_stream(ICProxyClient *client);
extern int ic_proxy_client_read_hello(ICProxyClient *client);
extern void ic_proxy_client_on_p2c_data(ICProxyClient *client, ICProxyPkt *pkt,
										ic_proxy_sent_cb callback,
										void *opaque);
extern ICProxyClient *ic_proxy_client_blessed_lookup(uv_loop_t *loop,
													 const ICProxyKey *key);
extern void ic_proxy_client_table_init(void);
extern void ic_proxy_client_table_uninit(void);
extern void ic_proxy_client_table_shutdown_by_dbid(uint16 dbid);

extern void ic_proxy_peer_table_init(void);
extern void ic_proxy_peer_table_uninit(void);

extern ICProxyPeer *ic_proxy_peer_new(uv_loop_t *loop,
									  int16 content, uint16 dbid);
extern void ic_proxy_peer_free(ICProxyPeer *peer);
extern void ic_proxy_peer_read_hello(ICProxyPeer *peer);
extern void ic_proxy_peer_connect(ICProxyPeer *peer, struct sockaddr_in *dest);
extern void ic_proxy_peer_route_data(ICProxyPeer *peer, ICProxyPkt *pkt,
									 ic_proxy_sent_cb callback, void *opaque);
extern ICProxyPeer *ic_proxy_peer_lookup(int16 content, uint16 dbid);
extern ICProxyPeer *ic_proxy_peer_blessed_lookup(uv_loop_t *loop,
												 int16 content, uint16 dbid);
extern ICProxyDelay *ic_proxy_peer_build_delay(ICProxyPeer *peer,
											   ICProxyPkt *pkt,
											   ic_proxy_sent_cb callback,
											   void *opaque);

#endif   /* IC_PROXY_SERVER_H */
