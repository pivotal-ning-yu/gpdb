-- start_ignore
create extension if not exists gp_debug_numsegments;
create language plpythonu;
-- end_ignore

drop schema if exists test_reshuffle_regression cascade;
create schema test_reshuffle_regression;
set search_path=test_reshuffle_regression,public;

--
-- derived from src/pl/plpython/sql/plpython_trigger.sql
--
-- with some hacks we could insert data into incorrect segments, reshuffle node
-- should tolerant this.
--

-- with this trigger the inserted data is always hacked to '12345'
create function trig12345() returns trigger language plpythonu as $$
    TD["new"]["data"] = '12345'
    return 'modify'
$$;

select gp_debug_set_create_table_default_numsegments(2);
create table b(data int);
select gp_debug_reset_create_table_default_numsegments();

-- by default '12345' should be inserted on seg0
insert into b values ('12345');
select gp_segment_id, * from b;

truncate b;

create trigger b_t before insert on b for each row execute procedure trig12345();

-- however with the trigger it is inserted on seg1
insert into b select i from generate_series(1, 10) i;
select gp_segment_id, * from b;

-- reshuffle node should tolerant it
alter table b expand table;
select gp_segment_id, * from b;
