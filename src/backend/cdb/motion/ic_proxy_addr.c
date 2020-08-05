/*-------------------------------------------------------------------------
 *
 * ic_proxy_addr.c
 *
 *    Interconnect Proxy Addresses
 *
 * Maintain the address information of all the proxies, which is set by the GUC
 * gp_interconnect_proxy_addresses.
 *
 * FIXME: currently that GUC can not be reloaded with "gpstop -u", so we must
 * restart the cluster to update the setting.  This causes problems during
 * online expansion, when new segments are added to the cluster, we must update
 * this GUC to include their information, so until the cluster is restarted all
 * the ic-proxy mode queries will hang.
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
 * List<ICProxyAddr *>, the addresses list.
 */
List	   *ic_proxy_addrs;

/*
 * Reload the addresses from the GUC gp_interconnect_proxy_addresses.
 *
 * The caller is responsible to load the up-to-date setting of that GUC by
 * calling ProcessConfigFile().
 */
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
		}

		fclose(f);
		ic_proxy_free(buf);
	}
}

/*
 * Get the address of the specified content:dbid.
 *
 * Return NULL if not found.
 */
const ICProxyAddr *
ic_proxy_get_addr(int16 content, uint16 dbid)
{
	ListCell   *cell;

	foreach(cell, ic_proxy_addrs)
	{
		ICProxyAddr *addr = lfirst(cell);

		if (addr->dbid == dbid)
			return addr;
	}

	return NULL;
}

/*
 * Get the port of current segment.
 *
 * Return -1 if cannot find the port.
 */
int
ic_proxy_get_my_port(void)
{
	const ICProxyAddr *addr;

	addr = ic_proxy_get_addr(GpIdentity.segindex, GpIdentity.dbid);
	if (addr)
		return ic_proxy_addr_get_port(addr);

	ic_proxy_log(WARNING, "ic-proxy-addr: cannot get my port");
	return -1;
}

/*
 * Get the port from an address.
 *
 * Return -1 if cannot find the port.
 */
int
ic_proxy_addr_get_port(const ICProxyAddr *addr)
{
	if (addr->addr.ss_family == AF_INET)
		return ntohs(((struct sockaddr_in *) addr)->sin_port);
	else if (addr->addr.ss_family == AF_INET6)
		return ntohs(((struct sockaddr_in6 *) addr)->sin6_port);

	ic_proxy_log(WARNING,
				 "ic-proxy-addr: invalid address family %d for seg%d,dbid%d",
				 addr->addr.ss_family, addr->content, addr->dbid);
	return -1;
}
