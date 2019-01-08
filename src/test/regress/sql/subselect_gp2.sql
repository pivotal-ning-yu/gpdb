-- Planner test: constant folding in subplan testexpr  produces no error
create table subselect_t1 (a int, b int, c int) distributed by (a);
create table subselect_t2 (a int, b int, c int) distributed by (a);

insert into subselect_t1 values (1,1,1);
insert into subselect_t2 values (1,1,1);

select * from subselect_t1 where NULL in (select c from subselect_t2);
select * from subselect_t1 where NULL in (select c from subselect_t2) and exists (select generate_series(1,2));

-- Planner test to make sure initplan is removed when no param is used
select * from subselect_t2 where false and exists (select generate_series(1,2));

