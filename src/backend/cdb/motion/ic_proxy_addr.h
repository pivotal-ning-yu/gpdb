/*-------------------------------------------------------------------------
 *
 * ic_proxy_addr.h
 *
 *
 * Copyright (c) 2020-Present Pivotal Software, Inc.
 *
 *
 *-------------------------------------------------------------------------
 */

#ifndef IC_PROXY_ADDR_H
#define IC_PROXY_ADDR_H


typedef struct ICProxyAddr ICProxyAddr;


struct ICProxyAddr
{
	struct sockaddr_storage addr;

	int			dbid;
	int			content;

	char		hostname[HOST_NAME_MAX];
	char		service[32];

	uv_getaddrinfo_t req;
};


/*
 * List<ICProxyAddr *>
 */
extern List		   *ic_proxy_addrs;


extern void ic_proxy_reload_addresses(uv_loop_t *loop);
extern const ICProxyAddr *ic_proxy_get_my_addr(void);
extern int ic_proxy_addr_get_port(const ICProxyAddr *addr);
extern int ic_proxy_extract_addr(const struct sockaddr *addr,
								 char *name, size_t namelen,
								 int *port, int *family);


#endif   /* IC_PROXY_ADDR_H */
