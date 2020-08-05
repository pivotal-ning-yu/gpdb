/*-------------------------------------------------------------------------
 *
 * ic_proxy_main.c
 *
 *	  The main loop of the ic-proxy, it listens for both new peers and new
 *	  clients, it also establish the peer connections.
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "postmaster/bgworker.h"
#include "utils/guc.h"
#include "utils/memutils.h"

#include "ic_proxy_server.h"
#include "ic_proxy_addr.h"
#include "ic_proxy_pkt_cache.h"

#include <uv.h>

#include <unistd.h>

static uv_loop_t	ic_proxy_server_loop;
static uv_signal_t	ic_proxy_server_signal_hup;
static uv_signal_t	ic_proxy_server_signal_int;
static uv_signal_t	ic_proxy_server_signal_term;
static uv_signal_t	ic_proxy_server_signal_stop;
static uv_timer_t	ic_proxy_server_timer;

static uv_tcp_t		ic_proxy_peer_listener;
static bool			ic_proxy_peer_listening;

static uv_pipe_t	ic_proxy_client_listener;
static bool			ic_proxy_client_listening;

static int			ic_proxy_server_exit_code = 1;

/*
 * The peer listener is closed.
 */
static void
ic_proxy_server_peer_listener_on_closed(uv_handle_t *handle)
{
	ic_proxy_log(LOG, "ic-proxy-server: peer listener: closed");

	/* A new peer listener will be created on the next timer callback */
	ic_proxy_peer_listening = false;
}

/*
 * New peer arrives.
 */
static void
ic_proxy_server_on_new_peer(uv_stream_t *server, int status)
{
	ICProxyPeer *peer;
	int			ret;

	if (status < 0)
	{
		ic_proxy_log(WARNING, "ic-proxy-server: new peer error: %s",
					 uv_strerror(status));

		uv_close((uv_handle_t *) server,
				 ic_proxy_server_peer_listener_on_closed);
		return;
	}

	ic_proxy_log(LOG, "ic-proxy-server: new peer to the server");

	peer = ic_proxy_peer_new(server->loop,
							 IC_PROXY_INVALID_CONTENT, IC_PROXY_INVALID_DBID);

	ret = uv_accept(server, (uv_stream_t *) &peer->tcp);
	if (ret < 0)
	{
		ic_proxy_log(WARNING, "ic-proxy-server: fail to accept new peer: %s",
					 uv_strerror(ret));
		ic_proxy_peer_free(peer);
		return;
	}

	/* TODO: it is better to only touch the states in peer.c */
	peer->state |= IC_PROXY_PEER_STATE_ACCEPTED;

	/* Dump some connection information, not very useful though */
	{
		struct sockaddr_storage peeraddr;
		int			addrlen = sizeof(peeraddr);
		char		name[HOST_NAME_MAX];

		uv_tcp_getpeername(&peer->tcp, (struct sockaddr *) &peeraddr, &addrlen);
		if (peeraddr.ss_family == AF_INET)
		{
			struct sockaddr_in *peeraddr4 = (struct sockaddr_in *) &peeraddr;

			uv_ip4_name(peeraddr4, name, sizeof(name));

			ic_proxy_log(LOG, "ic-proxy-server: the new peer is from %s:%d",
						 name, ntohs(peeraddr4->sin_port));
		}
		else if (peeraddr.ss_family == AF_INET6)
		{
			struct sockaddr_in6 *peeraddr6 = (struct sockaddr_in6 *) &peeraddr;

			uv_ip6_name(peeraddr6, name, sizeof(name));

			ic_proxy_log(LOG, "ic-proxy-server: the new peer is from %s:%d",
						 name, ntohs(peeraddr6->sin6_port));
		}
	}

	ic_proxy_peer_read_hello(peer);
}

/*
 * Setup the peer listener.
 *
 * The peer listener listens on a tcp socket, the peer connections will come
 * through it.
 */
static void
ic_proxy_server_peer_listener_init(uv_loop_t *loop)
{
	struct sockaddr_in addr;
	uv_tcp_t   *listener = &ic_proxy_peer_listener;
	int			port;
	int			fd = -1;
	int			ret;

	if (ic_proxy_addrs == NIL)
		return;

	if (ic_proxy_peer_listening)
		return;

	/* Get the ip from the gp_interconnect_proxy_addresses */
	port = ic_proxy_get_my_port();
	if (port < 0)
		/* Cannot get my port, maybe the setting is invalid */
		return;

	/*
	 * TODO: listen on the ip specified in gp_interconnect_proxy_addresses for
	 * better security.
	 */
	uv_ip4_addr("0.0.0.0", port, &addr);

	ic_proxy_log(LOG, "ic-proxy-server: setting up peer listener on port %d",
				 port);

	/*
	 * It is important to set TCP_NODELAY, otherwise we will suffer from
	 * significant latency and get very bad OLTP performance.
	 */
	uv_tcp_init(loop, listener);
	uv_tcp_nodelay(listener, true);

	ret = uv_tcp_bind(listener, (struct sockaddr *) &addr, 0);
	if (ret < 0)
	{
		ic_proxy_log(WARNING, "ic-proxy-server: tcp: fail to bind: %s",
					 uv_strerror(ret));
		return;
	}

	ret = uv_listen((uv_stream_t *) listener,
					IC_PROXY_BACKLOG, ic_proxy_server_on_new_peer);
	if (ret < 0)
	{
		ic_proxy_log(WARNING, "ic-proxy-server: tcp: fail to listen: %s",
					 uv_strerror(ret));
		return;
	}

	uv_fileno((uv_handle_t *) listener, &fd);
	ic_proxy_log(LOG, "ic-proxy-server: tcp: listening on socket %d", fd);

	ic_proxy_peer_listening = true;
}

/*
 * The client listener is closed.
 */
static void
ic_proxy_server_client_listener_on_closed(uv_handle_t *handle)
{
	ic_proxy_log(LOG, "ic-proxy-server: client listener: closed");

	/* A new client listener will be created on the next timer callback */
	ic_proxy_client_listening = false;
}

/*
 * New client arrives.
 */
static void
ic_proxy_server_on_new_client(uv_stream_t *server, int status)
{
	ICProxyClient *client;
	int			ret;

	if (status < 0)
	{
		ic_proxy_log(WARNING, "ic-proxy-server: new client error: %s",
					 uv_strerror(status));

		uv_close((uv_handle_t *) server,
				 ic_proxy_server_client_listener_on_closed);
		return;
	}

	ic_proxy_log(LOG, "ic-proxy-server: new client to the server");

	client = ic_proxy_client_new(server->loop, false);

	ret = uv_accept(server, ic_proxy_client_get_stream(client));
	if (ret < 0)
	{
		ic_proxy_log(WARNING, "ic-proxy-server: fail to accept new client: %s",
					 uv_strerror(ret));
		return;
	}

	ic_proxy_client_read_hello(client);
}

/*
 * Setup the client listener.
 *
 * The client listener listens on a domain socket, the client connections will
 * come through it.
 */
static void
ic_proxy_server_client_listener_init(uv_loop_t *loop)
{
	uv_pipe_t  *listener = &ic_proxy_client_listener;
	char		path[MAXPGPATH];
	int			fd = -1;
	int			ret;

	if (ic_proxy_client_listening)
		return;

	ic_proxy_build_server_sock_path(path, sizeof(path));

	/* FIXME: do not unlink here */
	ic_proxy_log(LOG, "unlink(%s) ...", path);
	unlink(path);

	ic_proxy_log(LOG, "ic-proxy-server: setting up client listener on address %s",
				 path);

	ret = uv_pipe_init(loop, listener, false);
	if (ret < 0)
	{
		ic_proxy_log(WARNING,
					 "ic-proxy-server: fail to init a client listener: %s",
					 uv_strerror(ret));
		return;
	}

	ret = uv_pipe_bind(listener, path);
	if (ret < 0)
	{
		ic_proxy_log(WARNING, "ic-proxy-server: pipe: fail to bind(%s): %s",
					 path, uv_strerror(ret));
		return;
	}

	ret = uv_listen((uv_stream_t *) listener,
					IC_PROXY_BACKLOG, ic_proxy_server_on_new_client);
	if (ret < 0)
	{
		ic_proxy_log(WARNING, "ic-proxy-server: pipe: fail to listen on path %s: %s",
					 path, uv_strerror(ret));
		return;
	}

	uv_fileno((uv_handle_t *) listener, &fd);
	ic_proxy_log(LOG, "ic-proxy-server: pipe: listening on socket %d", fd);

	/*
	 * Dump the inode of the domain socket file, this helps us to know that the
	 * file is replaced by someone.  This is not likely to happen, we have
	 * carefully choosen the file path to not conflict with each other.
	 */
	{
		struct stat	st;

		stat(path, &st);
		ic_proxy_log(LOG, "ic-proxy-server: dev=%lu, inode=%lu, path=%s",
					 st.st_dev, st.st_ino, path);
	}

	ic_proxy_client_listening = true;
}

/*
 * Timer handler.
 *
 * This is used to maintain the proxy-proxy network, as well as the client and
 * peer listeners.
 */
static void
ic_proxy_server_on_timer(uv_timer_t *timer)
{
	ic_proxy_server_peer_listener_init(timer->loop);
	ic_proxy_server_client_listener_init(timer->loop);
}

/*
 * Signal handler.
 *
 * Signals are handled via the signalfd() call in libuv, so this is a normal
 * callback as others, nothing special, errors can be raised, too.
 */
static void
ic_proxy_server_on_signal(uv_signal_t *handle, int signum)
{
	ic_proxy_log(WARNING, "ic-proxy-server: received signal %d", signum);

	if (signum == SIGHUP)
	{
		ProcessConfigFile(PGC_SIGHUP);

		ic_proxy_reload_addresses();

		ic_proxy_server_peer_listener_init(handle->loop);
		ic_proxy_server_client_listener_init(handle->loop);
	}
	else
	{
		uv_stop(handle->loop);
	}
}

/*
 * The main loop of the ic-proxy.
 */
int
ic_proxy_server_main(void)
{
	char		path[MAXPGPATH];

	ic_proxy_log(LOG, "ic-proxy-server: setting up");

	ic_proxy_pkt_cache_init(IC_PROXY_MAX_PKT_SIZE);

	ic_proxy_reload_addresses();

	uv_loop_init(&ic_proxy_server_loop);

	ic_proxy_router_init(&ic_proxy_server_loop);
	ic_proxy_peer_table_init();
	ic_proxy_client_table_init();

	ic_proxy_peer_listening = false;
	ic_proxy_client_listening = false;

	uv_signal_init(&ic_proxy_server_loop, &ic_proxy_server_signal_hup);
	uv_signal_start(&ic_proxy_server_signal_hup, ic_proxy_server_on_signal, SIGHUP);

	uv_signal_init(&ic_proxy_server_loop, &ic_proxy_server_signal_int);
	uv_signal_start(&ic_proxy_server_signal_int, ic_proxy_server_on_signal, SIGINT);

	/* on master */
	uv_signal_init(&ic_proxy_server_loop, &ic_proxy_server_signal_term);
	uv_signal_start(&ic_proxy_server_signal_term, ic_proxy_server_on_signal, SIGTERM);

	/* on segments */
	uv_signal_init(&ic_proxy_server_loop, &ic_proxy_server_signal_stop);
	uv_signal_start(&ic_proxy_server_signal_stop, ic_proxy_server_on_signal, SIGQUIT);

	/* TODO: we could stop the timer if all the peers are connected */
	uv_timer_init(&ic_proxy_server_loop, &ic_proxy_server_timer);
	uv_timer_start(&ic_proxy_server_timer, ic_proxy_server_on_timer, 100, 1000);

	ic_proxy_log(LOG, "ic-proxy-server: running");

	/* We're now ready to receive signals */
	BackgroundWorkerUnblockSignals();

	/*
	 * return non-zero value so we are restarted by the postmaster, but this
	 * behavior can be controled by calling ic_proxy_server_quit()
	 */
	ic_proxy_server_exit_code = 1;
	uv_run(&ic_proxy_server_loop, UV_RUN_DEFAULT);
	uv_loop_close(&ic_proxy_server_loop);

	ic_proxy_log(LOG, "ic-proxy-server: closing");

	ic_proxy_client_table_uninit();
	ic_proxy_peer_table_uninit();
	ic_proxy_router_uninit();

	ic_proxy_build_server_sock_path(path, sizeof(path));
#if 0
	ic_proxy_log(LOG, "unlink(%s) ...", path);
	unlink(path);
#endif

	ic_proxy_pkt_cache_uninit();

	ic_proxy_log(LOG, "ic-proxy-server: closed with code %d",
				 ic_proxy_server_exit_code);

	return ic_proxy_server_exit_code;
}

void
ic_proxy_server_quit(uv_loop_t *loop, bool relaunch)
{
	ic_proxy_log(LOG, "ic-proxy-server: quiting");

	if (relaunch)
		/* return non-zero value so we are restarted by the postmaster */
		ic_proxy_server_exit_code = 1;
	else
		ic_proxy_server_exit_code = 0;

	/*
	 * we can't close the loop directly, we need to properly shutdown all the
	 * clients first.
	 */
	if (ic_proxy_peer_listening)
	{
		uv_unref((uv_handle_t *) &ic_proxy_peer_listener);
		uv_close((uv_handle_t *) &ic_proxy_peer_listener, NULL);
	}
	if (ic_proxy_client_listening)
	{
		uv_unref((uv_handle_t *) &ic_proxy_client_listener);
		uv_close((uv_handle_t *) &ic_proxy_client_listener, NULL);
	}
	uv_timer_stop(&ic_proxy_server_timer);
	uv_unref((uv_handle_t *) &ic_proxy_server_signal_hup);
	uv_unref((uv_handle_t *) &ic_proxy_server_signal_term);
	uv_unref((uv_handle_t *) &ic_proxy_server_signal_stop);

#if 0
	uv_client_table_disconnect_all();
#endif

	/*
	 * do not close the loop directly, it will quit automatically after all the
	 * clients are closed.
	 */
#if 0
	uv_loop_close(loop);
#endif
}
