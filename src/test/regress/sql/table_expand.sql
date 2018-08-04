-- TODO: inherit tables
-- TODO: partition tables
-- TODO: ao tables
-- TODO: tables and temp tables

\set explain 'explain (analyze, costs off)'

set allow_system_table_mods to 'dml';

--
-- prepare kinds of tables
--

create temp table t1 (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
create temp table d1 (c1 int, c2 int, c3 int, c4 int) distributed replicated;
create temp table r1 (c1 int, c2 int, c3 int, c4 int) distributed randomly;

create temp table t2 (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
create temp table d2 (c1 int, c2 int, c3 int, c4 int) distributed replicated;
create temp table r2 (c1 int, c2 int, c3 int, c4 int) distributed randomly;

update gp_distribution_policy set numsegments=1
	where localoid in ('t1'::regclass, 'd1'::regclass, 'r1'::regclass);

update gp_distribution_policy set numsegments=2
	where localoid in ('t2'::regclass, 'd2'::regclass, 'r2'::regclass);

select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in (
		't1'::regclass, 'd1'::regclass, 'r1'::regclass,
		't2'::regclass, 'd2'::regclass, 'r2'::regclass);

--
-- create table
--

create temp table t (like t1);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create temp table t as table t1;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create temp table t as select * from t1;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create temp table t as select * from t1 distributed by (c1, c2);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create temp table t as select * from t1 distributed replicated;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create temp table t as select * from t1 distributed randomly;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

select * into temp table t from t1;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

--
-- alter table
--

create table t (like t1);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);

alter table t set distributed replicated;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);

alter table t set distributed randomly;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);

alter table t set distributed by (c1, c2);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);

alter table t add column c10 int;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);

alter table t alter column c10 type text;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);

drop table t;

--
-- join
--

:explain select * from t1 a join t1 b using (c1);
:explain select * from t1 a join t1 b using (c1, c2);
:explain select * from t1 a join d1 b using (c1);
:explain select * from t1 a join d1 b using (c1, c2);
:explain select * from t1 a join r1 b using (c1);
:explain select * from t1 a join r1 b using (c1, c2);

:explain select * from t1 a join t2 b using (c1);
:explain select * from t1 a join t2 b using (c1, c2);
:explain select * from t1 a join d2 b using (c1);
:explain select * from t1 a join d2 b using (c1, c2);
:explain select * from t1 a join r2 b using (c1);
:explain select * from t1 a join r2 b using (c1, c2);

:explain select * from d1 a join d1 b using (c1);
:explain select * from d1 a join r1 b using (c1);
:explain select * from r1 a join r1 b using (c1);

:explain select * from d1 a join d2 b using (c1);
:explain select * from d1 a join r2 b using (c1);
:explain select * from r1 a join r2 b using (c1);

:explain select * from t2 a join t1 b using (c1);
:explain select * from t2 a join t1 b using (c1, c2);
:explain select * from t2 a join d1 b using (c1);
:explain select * from t2 a join d1 b using (c1, c2);
:explain select * from t2 a join r1 b using (c1);
:explain select * from t2 a join r1 b using (c1, c2);

:explain select * from t2 a join t2 b using (c1);
:explain select * from t2 a join t2 b using (c1, c2);
:explain select * from t2 a join d2 b using (c1);
:explain select * from t2 a join d2 b using (c1, c2);
:explain select * from t2 a join r2 b using (c1);
:explain select * from t2 a join r2 b using (c1, c2);

:explain select * from d2 a join d1 b using (c1);
:explain select * from d2 a join r1 b using (c1);
:explain select * from r2 a join r1 b using (c1);

:explain select * from d2 a join d2 b using (c1);
:explain select * from d2 a join r2 b using (c1);
:explain select * from r2 a join r2 b using (c1);

--
-- left join
--

:explain select * from t1 a left join t1 b using (c1);
:explain select * from t1 a left join t1 b using (c1, c2);
:explain select * from t1 a left join d1 b using (c1);
:explain select * from t1 a left join d1 b using (c1, c2);
:explain select * from t1 a left join r1 b using (c1);
:explain select * from t1 a left join r1 b using (c1, c2);

:explain select * from t1 a left join t2 b using (c1);
:explain select * from t1 a left join t2 b using (c1, c2);
:explain select * from t1 a left join d2 b using (c1);
:explain select * from t1 a left join d2 b using (c1, c2);
:explain select * from t1 a left join r2 b using (c1);
:explain select * from t1 a left join r2 b using (c1, c2);

:explain select * from d1 a left join d1 b using (c1);
:explain select * from d1 a left join r1 b using (c1);
:explain select * from r1 a left join r1 b using (c1);

:explain select * from d1 a left join d2 b using (c1);
:explain select * from d1 a left join r2 b using (c1);
:explain select * from r1 a left join r2 b using (c1);

:explain select * from t2 a left join t1 b using (c1);
:explain select * from t2 a left join t1 b using (c1, c2);
:explain select * from t2 a left join d1 b using (c1);
:explain select * from t2 a left join d1 b using (c1, c2);
:explain select * from t2 a left join r1 b using (c1);
:explain select * from t2 a left join r1 b using (c1, c2);

:explain select * from t2 a left join t2 b using (c1);
:explain select * from t2 a left join t2 b using (c1, c2);
:explain select * from t2 a left join d2 b using (c1);
:explain select * from t2 a left join d2 b using (c1, c2);
:explain select * from t2 a left join r2 b using (c1);
:explain select * from t2 a left join r2 b using (c1, c2);

:explain select * from d2 a left join d1 b using (c1);
:explain select * from d2 a left join r1 b using (c1);
:explain select * from r2 a left join r1 b using (c1);

:explain select * from d2 a left join d2 b using (c1);
:explain select * from d2 a left join r2 b using (c1);
:explain select * from r2 a left join r2 b using (c1);

--
-- right join
--

:explain select * from t1 a right join t1 b using (c1);
:explain select * from t1 a right join t1 b using (c1, c2);
:explain select * from t1 a right join d1 b using (c1);
:explain select * from t1 a right join d1 b using (c1, c2);
:explain select * from t1 a right join r1 b using (c1);
:explain select * from t1 a right join r1 b using (c1, c2);

:explain select * from t1 a right join t2 b using (c1);
:explain select * from t1 a right join t2 b using (c1, c2);
:explain select * from t1 a right join d2 b using (c1);
:explain select * from t1 a right join d2 b using (c1, c2);
:explain select * from t1 a right join r2 b using (c1);
:explain select * from t1 a right join r2 b using (c1, c2);

:explain select * from d1 a right join d1 b using (c1);
:explain select * from d1 a right join r1 b using (c1);
:explain select * from r1 a right join r1 b using (c1);

:explain select * from d1 a right join d2 b using (c1);
:explain select * from d1 a right join r2 b using (c1);
:explain select * from r1 a right join r2 b using (c1);

:explain select * from t2 a right join t1 b using (c1);
:explain select * from t2 a right join t1 b using (c1, c2);
:explain select * from t2 a right join d1 b using (c1);
:explain select * from t2 a right join d1 b using (c1, c2);
:explain select * from t2 a right join r1 b using (c1);
:explain select * from t2 a right join r1 b using (c1, c2);

:explain select * from t2 a right join t2 b using (c1);
:explain select * from t2 a right join t2 b using (c1, c2);
:explain select * from t2 a right join d2 b using (c1);
:explain select * from t2 a right join d2 b using (c1, c2);
:explain select * from t2 a right join r2 b using (c1);
:explain select * from t2 a right join r2 b using (c1, c2);

:explain select * from d2 a right join d1 b using (c1);
:explain select * from d2 a right join r1 b using (c1);
:explain select * from r2 a right join r1 b using (c1);

:explain select * from d2 a right join d2 b using (c1);
:explain select * from d2 a right join r2 b using (c1);
:explain select * from r2 a right join r2 b using (c1);

--
-- insert
--

insert into t1 (c1, c2) values (1,1), (2,2), (3,3), (4,4), (5,5), (6,6)
	returning gp_segment_id, *;
insert into t2 (c1, c2) values (1,1), (2,2), (3,3), (4,4), (5,5), (6,6)
	returning gp_segment_id, *;

insert into d1 (c1, c2) values (1,1), (2,2), (3,3), (4,4), (5,5), (6,6)
	returning gp_segment_id, *;
insert into d2 (c1, c2) values (1,1), (2,2), (3,3), (4,4), (5,5), (6,6)
	returning gp_segment_id, *;

insert into r1 (c1, c2) values (1,1), (2,2), (3,3), (4,4), (5,5), (6,6)
	returning gp_segment_id, *;
insert into r2 (c1, c2) values (1,1), (2,2), (3,3), (4,4), (5,5), (6,6)
	returning gp_segment_id, *;

begin;
insert into t1 (c1, c2) select i, i from generate_series(1, 20) i
	returning gp_segment_id, *;
rollback;

begin;
insert into t1 (c1, c2) select c1, c2 from t1 returning gp_segment_id, *;
insert into t1 (c1, c2) select c2, c1 from t1 returning gp_segment_id, *;
insert into t1 (c1, c2) select c1, c2 from t2 returning gp_segment_id, *;
insert into t1 (c1, c2) select c2, c1 from t2 returning gp_segment_id, *;
insert into t1 (c1, c2) select c1, c2 from d1 returning gp_segment_id, *;
insert into t1 (c1, c2) select c1, c2 from d2 returning gp_segment_id, *;
insert into t1 (c1, c2) select c1, c2 from r1 returning gp_segment_id, *;
insert into t1 (c1, c2) select c1, c2 from r2 returning gp_segment_id, *;
rollback;

begin;
insert into t2 (c1, c2) select c1, c2 from t1 returning gp_segment_id, *;
insert into t2 (c1, c2) select c2, c1 from t1 returning gp_segment_id, *;
insert into t2 (c1, c2) select c1, c2 from d1 returning gp_segment_id, *;
insert into t2 (c1, c2) select c1, c2 from d2 returning gp_segment_id, *;
insert into t2 (c1, c2) select c1, c2 from r1 returning gp_segment_id, *;
insert into t2 (c1, c2) select c1, c2 from r2 returning gp_segment_id, *;
rollback;

begin;
insert into d1 (c1, c2) select c1, c2 from t1 returning gp_segment_id, *;
insert into d1 (c1, c2) select c2, c1 from t1 returning gp_segment_id, *;
insert into d1 (c1, c2) select c1, c2 from t2 returning gp_segment_id, *;
insert into d1 (c1, c2) select c2, c1 from t2 returning gp_segment_id, *;
insert into d1 (c1, c2) select c1, c2 from d1 returning gp_segment_id, *;
insert into d1 (c1, c2) select c1, c2 from d2 returning gp_segment_id, *;
insert into d1 (c1, c2) select c1, c2 from r1 returning gp_segment_id, *;
insert into d1 (c1, c2) select c1, c2 from r2 returning gp_segment_id, *;
rollback;

begin;
insert into d2 (c1, c2) select c1, c2 from t1 returning gp_segment_id, *;
insert into d2 (c1, c2) select c2, c1 from t1 returning gp_segment_id, *;
insert into d2 (c1, c2) select c1, c2 from d1 returning gp_segment_id, *;
insert into d2 (c1, c2) select c1, c2 from d2 returning gp_segment_id, *;
insert into d2 (c1, c2) select c1, c2 from r1 returning gp_segment_id, *;
insert into d2 (c1, c2) select c1, c2 from r2 returning gp_segment_id, *;
rollback;

begin;
insert into r1 (c1, c2) select c1, c2 from t1 returning gp_segment_id, *;
insert into r1 (c1, c2) select c2, c1 from t1 returning gp_segment_id, *;
insert into r1 (c1, c2) select c1, c2 from t2 returning gp_segment_id, *;
insert into r1 (c1, c2) select c2, c1 from t2 returning gp_segment_id, *;
insert into r1 (c1, c2) select c1, c2 from d1 returning gp_segment_id, *;
insert into r1 (c1, c2) select c1, c2 from d2 returning gp_segment_id, *;
insert into r1 (c1, c2) select c1, c2 from r1 returning gp_segment_id, *;
insert into r1 (c1, c2) select c1, c2 from r2 returning gp_segment_id, *;
rollback;

begin;
insert into r2 (c1, c2) select c1, c2 from t1 returning gp_segment_id, *;
insert into r2 (c1, c2) select c2, c1 from t1 returning gp_segment_id, *;
insert into r2 (c1, c2) select c1, c2 from d1 returning gp_segment_id, *;
insert into r2 (c1, c2) select c1, c2 from d2 returning gp_segment_id, *;
insert into r2 (c1, c2) select c1, c2 from r1 returning gp_segment_id, *;
insert into r2 (c1, c2) select c1, c2 from r2 returning gp_segment_id, *;
rollback;
