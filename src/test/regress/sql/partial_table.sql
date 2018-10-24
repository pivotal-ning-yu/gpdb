-- TODO: inherit tables
-- TODO: partition tables
-- TODO: ao tables
-- TODO: tables and temp tables

\set explain 'explain analyze'

drop schema if exists test_partial_table;
create schema test_partial_table;
set search_path='test_partial_table';

--
-- verify the debugging GUCs
--

set gp_create_table_default_numsegments to full;
create table t (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

set gp_create_table_default_numsegments to minimal;
create table t (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

set gp_create_table_default_numsegments to 'any';

set gp_create_table_any_numsegments to 1;
create table t (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

set gp_create_table_any_numsegments to 2;
create table t (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

set gp_create_table_any_numsegments to 3;
create table t (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

-- error: out of range [1, 3]
set gp_create_table_any_numsegments to -1;
set gp_create_table_any_numsegments to 0;
set gp_create_table_any_numsegments to 4;

reset gp_create_table_default_numsegments;

--
-- prepare kinds of tables
--

set gp_create_table_default_numsegments to 'any';

set gp_create_table_any_numsegments to 1;
create table t1 (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
create table d1 (c1 int, c2 int, c3 int, c4 int) distributed replicated;
create table r1 (c1 int, c2 int, c3 int, c4 int) distributed randomly;

set gp_create_table_any_numsegments to 2;
create table t2 (c1 int, c2 int, c3 int, c4 int) distributed by (c1, c2);
create table d2 (c1 int, c2 int, c3 int, c4 int) distributed replicated;
create table r2 (c1 int, c2 int, c3 int, c4 int) distributed randomly;

reset gp_create_table_default_numsegments;

select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in (
		't1'::regclass, 'd1'::regclass, 'r1'::regclass,
		't2'::regclass, 'd2'::regclass, 'r2'::regclass);

analyze t1;
analyze d1;
analyze r1;
analyze t2;
analyze d2;
analyze r2;

--
-- regression tests
--

-- a temp table is created during reorganization, its numsegments should be
-- the same with original table, otherwise some data will be lost after the
-- reorganization.
begin;
	insert into t1 select i, i from generate_series(1,10) i;
	select gp_segment_id, * from t1;
	alter table t1 set with (reorganize=true) distributed by (c1);
	select gp_segment_id, * from t1;
abort;
-- restore the analyze information
analyze t1;

--
-- regression tests
--

--
-- create table
--

-- like.numsegments = t1.numsegments = 1
-- t.numsegments should equal to like.numsegments
create table t (like t1);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

-- CTAS set numsegments with DEFAULT,
-- let it be a fixed value to get stable output
set gp_create_table_default_numsegments to 'any';
set gp_create_table_any_numsegments to 2;

-- like.numsegments = t1.numsegments = 1
-- distributedBy.numsegments = default.numsegments = 3
-- t.numsegments should equal to like.numsegments
create table t (like t1) distributed randomly;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

-- like.numsegments = t1.numsegments = 1
-- inherits.numsegments = t1.numsegments = 1
-- distributedBy.numsegments = default.numsegments = 3
-- t.numsegments should equal to like.numsegments
create table t (like t1) inherits (t1) distributed randomly;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

-- like.numsegments = t1.numsegments = 1
-- inherits.numsegments = t2.numsegments = 2
-- it should fail as like.numsegments != inherits.numsegments
create table t (like t1) inherits (t2);
-- drop anyway, otherwise following CREATEs will fail if above one does not fail
drop table if exists t;

create table t as table t1;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create table t as select * from t1;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create table t as select * from t1 distributed by (c1, c2);
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create table t as select * from t1 distributed replicated;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

create table t as select * from t1 distributed randomly;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

select * into table t from t1;
select localoid::regclass, attrnums, policytype, numsegments
	from gp_distribution_policy where localoid in ('t'::regclass);
drop table t;

reset gp_create_table_default_numsegments;

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

-- below join cases cover all the combinations of
--
--     select * from {t,d,r}{1,2} a
--      {left,} join {t,d,r}{1,2} b
--      using (c1{',c2',});
--
-- there might be some duplicated ones, like 't1 join d1' and 'd1 join t1',
-- or 'd1 join r1 using (c1)' and 'd1 join r1 using (c1, c2)', this is because
-- we generate them via scripts and do not clean them up manually.
--
-- please do not remove the duplicated ones as we care about the motion
-- direction of different join orders, e.g. 't2 join t1' and 't1 join t2'
-- should both distribute t2 to t1.

--
-- JOIN
--

-- x1 join y1
:explain select * from t1 a join t1 b using (c1);
:explain select * from t1 a join t1 b using (c1, c2);
:explain select * from t1 a join d1 b using (c1);
:explain select * from t1 a join d1 b using (c1, c2);
:explain select * from t1 a join r1 b using (c1);
:explain select * from t1 a join r1 b using (c1, c2);
:explain select * from d1 a join t1 b using (c1);
:explain select * from d1 a join t1 b using (c1, c2);
:explain select * from d1 a join d1 b using (c1);
:explain select * from d1 a join d1 b using (c1, c2);
:explain select * from d1 a join r1 b using (c1);
:explain select * from d1 a join r1 b using (c1, c2);
:explain select * from r1 a join t1 b using (c1);
:explain select * from r1 a join t1 b using (c1, c2);
:explain select * from r1 a join d1 b using (c1);
:explain select * from r1 a join d1 b using (c1, c2);
:explain select * from r1 a join r1 b using (c1);
:explain select * from r1 a join r1 b using (c1, c2);

-- x1 join y2
:explain select * from t1 a join t2 b using (c1);
:explain select * from t1 a join t2 b using (c1, c2);
:explain select * from t1 a join d2 b using (c1);
:explain select * from t1 a join d2 b using (c1, c2);
:explain select * from t1 a join r2 b using (c1);
:explain select * from t1 a join r2 b using (c1, c2);
:explain select * from d1 a join t2 b using (c1);
:explain select * from d1 a join t2 b using (c1, c2);
:explain select * from d1 a join d2 b using (c1);
:explain select * from d1 a join d2 b using (c1, c2);
:explain select * from d1 a join r2 b using (c1);
:explain select * from d1 a join r2 b using (c1, c2);
:explain select * from r1 a join t2 b using (c1);
:explain select * from r1 a join t2 b using (c1, c2);
:explain select * from r1 a join d2 b using (c1);
:explain select * from r1 a join d2 b using (c1, c2);
:explain select * from r1 a join r2 b using (c1);
:explain select * from r1 a join r2 b using (c1, c2);

-- x2 join y1
:explain select * from t2 a join t1 b using (c1);
:explain select * from t2 a join t1 b using (c1, c2);
:explain select * from t2 a join d1 b using (c1);
:explain select * from t2 a join d1 b using (c1, c2);
:explain select * from t2 a join r1 b using (c1);
:explain select * from t2 a join r1 b using (c1, c2);
:explain select * from d2 a join t1 b using (c1);
:explain select * from d2 a join t1 b using (c1, c2);
:explain select * from d2 a join d1 b using (c1);
:explain select * from d2 a join d1 b using (c1, c2);
:explain select * from d2 a join r1 b using (c1);
:explain select * from d2 a join r1 b using (c1, c2);
:explain select * from r2 a join t1 b using (c1);
:explain select * from r2 a join t1 b using (c1, c2);
:explain select * from r2 a join d1 b using (c1);
:explain select * from r2 a join d1 b using (c1, c2);
:explain select * from r2 a join r1 b using (c1);
:explain select * from r2 a join r1 b using (c1, c2);

-- x2 join y2
:explain select * from t2 a join t2 b using (c1);
:explain select * from t2 a join t2 b using (c1, c2);
:explain select * from t2 a join d2 b using (c1);
:explain select * from t2 a join d2 b using (c1, c2);
:explain select * from t2 a join r2 b using (c1);
:explain select * from t2 a join r2 b using (c1, c2);
:explain select * from d2 a join t2 b using (c1);
:explain select * from d2 a join t2 b using (c1, c2);
:explain select * from d2 a join d2 b using (c1);
:explain select * from d2 a join d2 b using (c1, c2);
:explain select * from d2 a join r2 b using (c1);
:explain select * from d2 a join r2 b using (c1, c2);
:explain select * from r2 a join t2 b using (c1);
:explain select * from r2 a join t2 b using (c1, c2);
:explain select * from r2 a join d2 b using (c1);
:explain select * from r2 a join d2 b using (c1, c2);
:explain select * from r2 a join r2 b using (c1);
:explain select * from r2 a join r2 b using (c1, c2);

-- x1 left join y1
:explain select * from t1 a left join t1 b using (c1);
:explain select * from t1 a left join t1 b using (c1, c2);
:explain select * from t1 a left join d1 b using (c1);
:explain select * from t1 a left join d1 b using (c1, c2);
:explain select * from t1 a left join r1 b using (c1);
:explain select * from t1 a left join r1 b using (c1, c2);
:explain select * from d1 a left join t1 b using (c1);
:explain select * from d1 a left join t1 b using (c1, c2);
:explain select * from d1 a left join d1 b using (c1);
:explain select * from d1 a left join d1 b using (c1, c2);
:explain select * from d1 a left join r1 b using (c1);
:explain select * from d1 a left join r1 b using (c1, c2);
:explain select * from r1 a left join t1 b using (c1);
:explain select * from r1 a left join t1 b using (c1, c2);
:explain select * from r1 a left join d1 b using (c1);
:explain select * from r1 a left join d1 b using (c1, c2);
:explain select * from r1 a left join r1 b using (c1);
:explain select * from r1 a left join r1 b using (c1, c2);

-- x1 left join y2
:explain select * from t1 a left join t2 b using (c1);
:explain select * from t1 a left join t2 b using (c1, c2);
:explain select * from t1 a left join d2 b using (c1);
:explain select * from t1 a left join d2 b using (c1, c2);
:explain select * from t1 a left join r2 b using (c1);
:explain select * from t1 a left join r2 b using (c1, c2);
:explain select * from d1 a left join t2 b using (c1);
:explain select * from d1 a left join t2 b using (c1, c2);
:explain select * from d1 a left join d2 b using (c1);
:explain select * from d1 a left join d2 b using (c1, c2);
:explain select * from d1 a left join r2 b using (c1);
:explain select * from d1 a left join r2 b using (c1, c2);
:explain select * from r1 a left join t2 b using (c1);
:explain select * from r1 a left join t2 b using (c1, c2);
:explain select * from r1 a left join d2 b using (c1);
:explain select * from r1 a left join d2 b using (c1, c2);
:explain select * from r1 a left join r2 b using (c1);
:explain select * from r1 a left join r2 b using (c1, c2);

-- x2 left join y1
:explain select * from t2 a left join t1 b using (c1);
:explain select * from t2 a left join t1 b using (c1, c2);
:explain select * from t2 a left join d1 b using (c1);
:explain select * from t2 a left join d1 b using (c1, c2);
:explain select * from t2 a left join r1 b using (c1);
:explain select * from t2 a left join r1 b using (c1, c2);
:explain select * from d2 a left join t1 b using (c1);
:explain select * from d2 a left join t1 b using (c1, c2);
:explain select * from d2 a left join d1 b using (c1);
:explain select * from d2 a left join d1 b using (c1, c2);
:explain select * from d2 a left join r1 b using (c1);
:explain select * from d2 a left join r1 b using (c1, c2);
:explain select * from r2 a left join t1 b using (c1);
:explain select * from r2 a left join t1 b using (c1, c2);
:explain select * from r2 a left join d1 b using (c1);
:explain select * from r2 a left join d1 b using (c1, c2);
:explain select * from r2 a left join r1 b using (c1);
:explain select * from r2 a left join r1 b using (c1, c2);

-- x2 left join y2
:explain select * from t2 a left join t2 b using (c1);
:explain select * from t2 a left join t2 b using (c1, c2);
:explain select * from t2 a left join d2 b using (c1);
:explain select * from t2 a left join d2 b using (c1, c2);
:explain select * from t2 a left join r2 b using (c1);
:explain select * from t2 a left join r2 b using (c1, c2);
:explain select * from d2 a left join t2 b using (c1);
:explain select * from d2 a left join t2 b using (c1, c2);
:explain select * from d2 a left join d2 b using (c1);
:explain select * from d2 a left join d2 b using (c1, c2);
:explain select * from d2 a left join r2 b using (c1);
:explain select * from d2 a left join r2 b using (c1, c2);
:explain select * from r2 a left join t2 b using (c1);
:explain select * from r2 a left join t2 b using (c1, c2);
:explain select * from r2 a left join d2 b using (c1);
:explain select * from r2 a left join d2 b using (c1, c2);
:explain select * from r2 a left join r2 b using (c1);
:explain select * from r2 a left join r2 b using (c1, c2);
:explain select * from t1, t2 where t1.c1 > any (select max(t2.c1) from t2 where t2.c2 = t1.c2) and t2.c1 > any(select max(c1) from t1 where t1.c2 = t2.c2);

--
-- insert
--

insert into t1 (c1) values (1), (2), (3), (4), (5), (6)
	returning c1, c2;
insert into t2 (c1) values (1), (2), (3), (4), (5), (6)
	returning c1, c2;

insert into d1 (c1) values (1), (2), (3), (4), (5), (6)
	returning c1, c2;
insert into d2 (c1) values (1), (2), (3), (4), (5), (6)
	returning c1, c2;

insert into r1 (c1) values (1), (2), (3), (4), (5), (6)
	returning c1, c2;
insert into r2 (c1) values (1), (2), (3), (4), (5), (6)
	returning c1, c2;

begin;
insert into t1 (c1) values (1) returning c1, c2;
insert into d1 (c1) values (1) returning c1, c2;
insert into r1 (c1) values (1) returning c1, c2;
insert into t2 (c1) values (1) returning c1, c2;
insert into d2 (c1) values (1) returning c1, c2;
insert into r2 (c1) values (1) returning c1, c2;
rollback;

begin;
insert into t1 (c1) select i from generate_series(1, 20) i
	returning c1, c2;
insert into d1 (c1) select i from generate_series(1, 20) i
	returning c1, c2;
insert into r1 (c1) select i from generate_series(1, 20) i
	returning c1, c2;
insert into t2 (c1) select i from generate_series(1, 20) i
	returning c1, c2;
insert into d2 (c1) select i from generate_series(1, 20) i
	returning c1, c2;
insert into r2 (c1) select i from generate_series(1, 20) i
	returning c1, c2;
rollback;

begin;
insert into t1 (c1, c2) select c1, c2 from t1 returning c1, c2;
insert into t1 (c1, c2) select c2, c1 from t1 returning c1, c2;
insert into t1 (c1, c2) select c1, c2 from t2 returning c1, c2;
insert into t1 (c1, c2) select c2, c1 from t2 returning c1, c2;
insert into t1 (c1, c2) select c1, c2 from d1 returning c1, c2;
insert into t1 (c1, c2) select c1, c2 from d2 returning c1, c2;
insert into t1 (c1, c2) select c1, c2 from r1 returning c1, c2;
insert into t1 (c1, c2) select c1, c2 from r2 returning c1, c2;
rollback;

begin;
insert into t2 (c1, c2) select c1, c2 from t1 returning c1, c2;
insert into t2 (c1, c2) select c2, c1 from t1 returning c1, c2;
insert into t2 (c1, c2) select c1, c2 from d1 returning c1, c2;
insert into t2 (c1, c2) select c1, c2 from d2 returning c1, c2;
insert into t2 (c1, c2) select c1, c2 from r1 returning c1, c2;
insert into t2 (c1, c2) select c1, c2 from r2 returning c1, c2;
rollback;

begin;
insert into d1 (c1, c2) select c1, c2 from t1 returning c1, c2;
insert into d1 (c1, c2) select c2, c1 from t1 returning c1, c2;
insert into d1 (c1, c2) select c1, c2 from t2 returning c1, c2;
insert into d1 (c1, c2) select c2, c1 from t2 returning c1, c2;
insert into d1 (c1, c2) select c1, c2 from d1 returning c1, c2;
insert into d1 (c1, c2) select c1, c2 from d2 returning c1, c2;
insert into d1 (c1, c2) select c1, c2 from r1 returning c1, c2;
insert into d1 (c1, c2) select c1, c2 from r2 returning c1, c2;
rollback;

begin;
insert into d2 (c1, c2) select c1, c2 from t1 returning c1, c2;
insert into d2 (c1, c2) select c2, c1 from t1 returning c1, c2;
insert into d2 (c1, c2) select c1, c2 from d1 returning c1, c2;
insert into d2 (c1, c2) select c1, c2 from d2 returning c1, c2;
insert into d2 (c1, c2) select c1, c2 from r1 returning c1, c2;
insert into d2 (c1, c2) select c1, c2 from r2 returning c1, c2;
rollback;

begin;
insert into r1 (c1, c2) select c1, c2 from t1 returning c1, c2;
insert into r1 (c1, c2) select c2, c1 from t1 returning c1, c2;
insert into r1 (c1, c2) select c1, c2 from t2 returning c1, c2;
insert into r1 (c1, c2) select c2, c1 from t2 returning c1, c2;
insert into r1 (c1, c2) select c1, c2 from d1 returning c1, c2;
insert into r1 (c1, c2) select c1, c2 from d2 returning c1, c2;
insert into r1 (c1, c2) select c1, c2 from r1 returning c1, c2;
insert into r1 (c1, c2) select c1, c2 from r2 returning c1, c2;
rollback;

begin;
insert into r2 (c1, c2) select c1, c2 from t1 returning c1, c2;
insert into r2 (c1, c2) select c2, c1 from t1 returning c1, c2;
insert into r2 (c1, c2) select c1, c2 from d1 returning c1, c2;
insert into r2 (c1, c2) select c1, c2 from d2 returning c1, c2;
insert into r2 (c1, c2) select c1, c2 from r1 returning c1, c2;
insert into r2 (c1, c2) select c1, c2 from r2 returning c1, c2;
rollback;

--
-- pg_relation_size() dispatches an internal query, to fetch the relation's
-- size on each segment. The internal query doesn't need to be part of the
-- distributed transactin. Test that we correctly issue two-phase commit in
-- those segments that are affected by the INSERT, and that we don't try
-- to perform distributed commit on the other segments.
--
insert into r1 (c4) values (pg_relation_size('r2'));
