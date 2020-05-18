/*-------------------------------------------------------------------------
 *
 * ic_proxy_addr.c
 *	  TODO file description
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */


#include <uv.h>

#include "ic_proxy.h"
#include "ic_proxy_addr.h"


/*
 * List<ICProxyAddr *>
 */
List	   *ic_proxy_addrs;

int			ic_proxy_content_count;

void
ic_proxy_reload_addresses(void)
{
	/* reset the old addresses */
	{
		ListCell   *cell;

		foreach(cell, ic_proxy_addrs)
		{
			ic_proxy_free(lfirst(cell));
		}

		list_free(ic_proxy_addrs);
		ic_proxy_addrs = NIL;
	}

	ic_proxy_content_count = -2;

	/* parse the new addresses */
	{
		int			size = strlen(gp_interconnect_proxy_addresses) + 1;
		char	   *buf;
		FILE	   *f;
		int			dbid;
		int			content;
		int			port;
		char		ip[HOST_NAME_MAX];

		buf = ic_proxy_alloc(size);
		memcpy(buf, gp_interconnect_proxy_addresses, size);

		f = fmemopen(buf, size, "r");

		/*
		 * format: dbid:segid:ip:port
		 */
		while (fscanf(f, "%d:%d:%[0-9.]:%d,", &dbid, &content, ip, &port) == 4)
		{
			ICProxyAddr *addr = ic_proxy_new(ICProxyAddr);
			int			ret;

			addr->dbid = dbid;
			addr->content = content;

			ic_proxy_log(LOG, "ic-proxy-server: addr: seg%d,dbid%d: %s:%d",
						 content, dbid, ip, port);

			ret = uv_ip4_addr(ip, port, (struct sockaddr_in *) addr);
			if (ret < 0)
				ic_proxy_log(WARNING,
							 "ic-proxy-server: invalid address: seg%d,dbid%d: %s:%d: %s",
							 content, dbid, ip, port, uv_strerror(ret));

			ic_proxy_addrs = lappend(ic_proxy_addrs, addr);

			ic_proxy_content_count = Max(ic_proxy_content_count, content);
		}

		fclose(f);
		ic_proxy_free(buf);
	}

	ic_proxy_content_count += 2;
	ic_proxy_log(LOG, "ic-proxy-server: %d unique content ids",
				 ic_proxy_content_count);
}

int
ic_proxy_get_my_port(void)
{
	ListCell   *cell;
	int			dbid = GpIdentity.dbid;

	foreach(cell, ic_proxy_addrs)
	{
		ICProxyAddr *addr = lfirst(cell);

		if (addr->dbid == dbid)
			return ic_proxy_addr_get_port(addr);
	}

	ic_proxy_log(ERROR, "ic-proxy-addr: cannot get my port");
	return 0;
}

int
ic_proxy_addr_get_port(const ICProxyAddr *addr)
{
	if (addr->addr.ss_family == AF_INET)
		return ntohs(((struct sockaddr_in *) addr)->sin_port);
	else if (addr->addr.ss_family == AF_INET6)
		return ntohs(((struct sockaddr_in6 *) addr)->sin6_port);

	ic_proxy_log(ERROR,
				 "ic-proxy-addr: invalid address family %d for seg%d,dbid%d",
				 addr->addr.ss_family, addr->content, addr->dbid);
}
