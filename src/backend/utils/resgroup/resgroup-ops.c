/*-------------------------------------------------------------------------
 *
 * resgroup-ops.c
 *	  OS independent resource group operations.
 *
 *
 * Copyright (c) 2006-2017, Greenplum inc.
 *
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "postmaster/backoff.h"
#include "utils/resgroup.h"

#include "cgroup.h"

/*
 * Interfaces for OS dependent operations.
 *
 * Resource group replies on OS dependent group implementation to manage
 * resources like cpu usage, such as cgroup on Linux system.
 * We call it OS group in below function description.
 *
 * So far these operations are mainly for CPU rate limitation and accounting.
 */

#define unsupported_system() \
	elog(ERROR, "cpu rate limitation for resource group is unsupported on this system")

/* Return the name for the OS group implementation, such as cgroup */
const char *
ResGroupOps_Name(void)
{
	return "cgroup";
}

/* Check whether the OS group implementation is available and useable */
void
ResGroupOps_CheckPermission(void)
{
	CGroupCheckPermission(0);
}

/* Initialize the OS group */
void
ResGroupOps_Init(void)
{
	CGroupInitTop();
}

/*
 * Create the OS group for group.
 */
void
ResGroupOps_CreateGroup(Oid group)
{
	CGroupCreateSub(group);
}

/*
 * Destroy the OS group for group.
 *
 * Fail if any process is running under it.
 */
void
ResGroupOps_DestroyGroup(Oid group)
{
	CGroupDestroySub(group);
}

/*
 * Assign a process to the OS group. A process can only be assigned to one
 * OS group, if it's already running under other OS group then it'll be moved
 * out that OS group.
 *
 * pid is the process id.
 */
void
ResGroupOps_AssignGroup(Oid group, int pid)
{
	CGroupAssignGroup(group, pid);
}

/*
 * Set the cpu rate limit for the OS group.
 *
 * cpu_rate_limit should be within (0.0, 1.0].
 */
void
ResGroupOps_SetCpuRateLimit(Oid group, float cpu_rate_limit)
{
	CGroupSetCpuRateLimit(group, cpu_rate_limit);
}

/*
 * Get the cpu usage of the OS group, that is the total cpu time obtained
 * by this OS group, in nano seconds.
 */
int64
ResGroupOps_GetCpuUsage(Oid group)
{
	return CGroupGetCpuUsage(group);
}

/*
 * Get the count of cpu cores on the system.
 */
int
ResGroupOps_GetCpuCores(void)
{
	return CGroupGetCpuCores();
}
