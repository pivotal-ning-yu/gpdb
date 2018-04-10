show gp_resource_manager;

select * from pg_resgroup
  order by oid;
select min(reslimittype)
  from pg_resgroupcapability
  group by resgroupid
  order by resgroupid;
select groupname from gp_toolkit.gp_resgroup_config
  order by groupid;
select rsgname from gp_toolkit.gp_resgroup_status
  order by groupid;

alter resource group rg1 set memory_limit 20;
alter resource group rg1 set memory_limit 10;
drop resource group rg1;
create resource group rg1 with (cpu_rate_limit=10, memory_limit=10);

alter resource group rg2 set memory_limit 20;
alter resource group rg2 set memory_limit 10;
