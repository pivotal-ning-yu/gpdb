-- start_ignore
! rmdir /sys/fs/cgroup/cpu/gpdb;
! rmdir /sys/fs/cgroup/cpuacct/gpdb;
! mkdir /sys/fs/cgroup/cpu/gpdb;
! mkdir /sys/fs/cgroup/cpuacct/gpdb;
-- end_ignore

-- enable resource group and restart cluster.
-- start_ignore
! gpconfig -c gp_resource_manager -v group;
! gpstop -rai;
-- end_ignore
