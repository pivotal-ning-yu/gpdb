create table t_freegang_initplan(c int);

create or replace function f_freegang_initplan() returns int as
$$
begin
  insert into t_freegang_initplan select * from generate_series(1, 10);
  return 1;
end;
$$
language plpgsql;

\! gpfaultinjector -f free_gang_initplan -y reset -s 1
\! gpfaultinjector -f free_gang_initplan -y skip -s 1

-- the following query will generate initplan, and initplan should not
-- cleanup gang allocated to parent plan.
create table t_freegang_initplan_test as select f_freegang_initplan();

select * from t_freegang_initplan_test;

drop function f_freegang_initplan();
drop table t_freegang_initplan;
drop table t_freegang_initplan_test;
