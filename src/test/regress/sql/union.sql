--
-- UNION (also INTERSECT, EXCEPT)
--

-- Simple UNION constructs

SELECT 1 AS two UNION SELECT 2;

SELECT 1 AS one UNION SELECT 1;

SELECT 1 AS two UNION ALL SELECT 2;

SELECT 1 AS two UNION ALL SELECT 1;

SELECT 1 AS three UNION SELECT 2 UNION SELECT 3;

SELECT 1 AS two UNION SELECT 2 UNION SELECT 2;

SELECT 1 AS three UNION SELECT 2 UNION ALL SELECT 2;

SELECT 1.1 AS two UNION SELECT 2.2;

-- Mixed types

SELECT 1.1 AS two UNION SELECT 2;

SELECT 1 AS two UNION SELECT 2.2;

SELECT 1 AS one UNION SELECT 1.0::float8;

SELECT 1.1 AS two UNION ALL SELECT 2;

SELECT 1.0::float8 AS two UNION ALL SELECT 1;

SELECT 1.1 AS three UNION SELECT 2 UNION SELECT 3;

SELECT 1.1::float8 AS two UNION SELECT 2 UNION SELECT 2.0::float8;

SELECT 1.1 AS three UNION SELECT 2 UNION ALL SELECT 2;

SELECT 1.1 AS two UNION (SELECT 2 UNION ALL SELECT 2);

--
-- Try testing from tables...
--

SELECT f1 AS five FROM FLOAT8_TBL
UNION
SELECT f1 FROM FLOAT8_TBL ORDER BY 1;

SELECT f1 AS ten FROM FLOAT8_TBL
UNION ALL
SELECT f1 FROM FLOAT8_TBL ORDER BY 1;

SELECT f1 AS nine FROM FLOAT8_TBL
UNION
SELECT f1 FROM INT4_TBL ORDER BY 1;

SELECT f1 AS ten FROM FLOAT8_TBL
UNION ALL
SELECT f1 FROM INT4_TBL ORDER BY 1;

SELECT f1 AS five FROM FLOAT8_TBL
  WHERE f1 BETWEEN -1e6 AND 1e6
UNION
SELECT f1 FROM INT4_TBL
  WHERE f1 BETWEEN 0 AND 1000000 ORDER BY 1;

SELECT CAST(f1 AS char(4)) AS three FROM VARCHAR_TBL
UNION
SELECT f1 FROM CHAR_TBL ORDER BY 1;

SELECT f1 AS three FROM VARCHAR_TBL
UNION
SELECT CAST(f1 AS varchar) FROM CHAR_TBL ORDER BY 1;

SELECT f1 AS eight FROM VARCHAR_TBL
UNION ALL
SELECT f1 FROM CHAR_TBL ORDER BY 1;

SELECT f1 AS five FROM TEXT_TBL
UNION
SELECT f1 FROM VARCHAR_TBL
UNION
SELECT TRIM(TRAILING FROM f1) FROM CHAR_TBL ORDER BY 1;

--
-- INTERSECT and EXCEPT
--

SELECT q2 FROM int8_tbl INTERSECT SELECT q1 FROM int8_tbl ORDER BY 1;

SELECT q2 FROM int8_tbl INTERSECT ALL SELECT q1 FROM int8_tbl ORDER BY 1;

SELECT q2 FROM int8_tbl EXCEPT SELECT q1 FROM int8_tbl ORDER BY 1;

SELECT q2 FROM int8_tbl EXCEPT ALL SELECT q1 FROM int8_tbl ORDER BY 1;

SELECT q2 FROM int8_tbl EXCEPT ALL SELECT DISTINCT q1 FROM int8_tbl ORDER BY 1;

SELECT q1 FROM int8_tbl EXCEPT SELECT q2 FROM int8_tbl ORDER BY 1;

SELECT q1 FROM int8_tbl EXCEPT ALL SELECT q2 FROM int8_tbl ORDER BY 1;

SELECT q1 FROM int8_tbl EXCEPT ALL SELECT DISTINCT q2 FROM int8_tbl ORDER BY 1;

--
-- Mixed types
--

SELECT f1 FROM float8_tbl INTERSECT SELECT f1 FROM int4_tbl ORDER BY 1;

SELECT f1 FROM float8_tbl EXCEPT SELECT f1 FROM int4_tbl ORDER BY 1;

--
-- Operator precedence and (((((extra))))) parentheses
--

SELECT q1 FROM int8_tbl INTERSECT SELECT q2 FROM int8_tbl UNION ALL SELECT q2 FROM int8_tbl ORDER BY 1;

SELECT q1 FROM int8_tbl INTERSECT (((SELECT q2 FROM int8_tbl UNION ALL SELECT q2 FROM int8_tbl))) ORDER BY 1;

(((SELECT q1 FROM int8_tbl INTERSECT SELECT q2 FROM int8_tbl))) UNION ALL SELECT q2 FROM int8_tbl ORDER BY 1;

SELECT q1 FROM int8_tbl UNION ALL SELECT q2 FROM int8_tbl EXCEPT SELECT q1 FROM int8_tbl ORDER BY 1;

SELECT q1 FROM int8_tbl UNION ALL (((SELECT q2 FROM int8_tbl EXCEPT SELECT q1 FROM int8_tbl))) ORDER BY 1;

(((SELECT q1 FROM int8_tbl UNION ALL SELECT q2 FROM int8_tbl))) EXCEPT SELECT q1 FROM int8_tbl ORDER BY 1;

--
-- Subqueries with ORDER BY & LIMIT clauses
--

-- In this syntax, ORDER BY/LIMIT apply to the result of the EXCEPT
SELECT q1,q2 FROM int8_tbl EXCEPT SELECT q2,q1 FROM int8_tbl
ORDER BY q2,q1;

-- This should fail, because q2 isn't a name of an EXCEPT output column
SELECT q1 FROM int8_tbl EXCEPT SELECT q2 FROM int8_tbl ORDER BY q2 LIMIT 1;

-- But this should work:
SELECT q1 FROM int8_tbl EXCEPT (((SELECT q2 FROM int8_tbl ORDER BY q2 LIMIT 1))) ORDER BY 1;

--
-- New syntaxes (7.1) permit new tests
--

(((((select * from int8_tbl))))) ORDER BY 1,2;

create temp table t_union1 (a int, b int);
select distinct a, null as c from t_union1 union select a, b from t_union1;
drop table t_union1;

select null union select distinct null;

select 1 union select distinct null;

select 1 a, NULL b, NULL c UNION SELECT 2, 3, NULL UNION SELECT 3, NULL, 4;

select ARRAY[1, 2, 3] union select distinct null;

select 1 intersect (select 1, 2 union all select 3, 4);
select 1 a, row_number() over (partition by 'a') union all (select 1 a , 2 b);

-- This can preserve domain types, but we keep compatibility for now
-- See MPP-7509
select pg_typeof(a) from (select 'a'::information_schema.sql_identifier a union all
select 'b'::information_schema.sql_identifier)a;

(select * from (
     (select '1' as a union select null)
     union
     (select 1 union select distinct null)
   )s)
  union
  (select * from (
     (select '1' union select null)
     union
     (select 1 union select distinct null)
  )s2);

-- Yet, we keep behaviors on text-like columns
select pg_typeof(a) from(select 'foo' a union select 'foo'::name)s;
select pg_typeof(a) from(select 1 x, 'foo' a union
    select 1, 'foo' union select 1, 'foo'::name)s;
select pg_typeof(a) from(select 1 x, 'foo' a union
    (select 1, 'foo' union select 1, 'foo'::name))s;

CREATE TABLE union_ctas (a, b) AS SELECT 1, 2 UNION SELECT 1, 1 UNION SELECT 1, 1;
SELECT * FROM union_ctas;
DROP TABLE union_ctas;

-- MPP-21075: push quals below union
CREATE TABLE union_quals1 (a, b) AS SELECT i, i%2 from generate_series(1,10) i;
CREATE TABLE union_quals2 (a, b) AS SELECT i%2, i from generate_series(1,10) i;
SELECT * FROM (SELECT a, b from union_quals1 UNION SELECT b, a from union_quals2) as foo(a,b) where a > b order by a;
SELECT * FROM (SELECT a, max(b) over() from union_quals1 UNION SELECT * from union_quals2) as foo(a,b) where b > 6 order by a,b;

-- MPP-22266: different combinations of set operations and distinct
select * from ((select 1, 'A' from (select distinct 'B') as foo) union (select 1, 'C')) as bar;
select 1 union (select distinct null union select '10');
select 1 union (select 2 from (select distinct null union select 1) as x);
select 1 union (select distinct '10' from (select 1, 3.0 union select distinct 2, null) as foo);
select distinct a from (select 'A' union select 'B') as foo(a);
select distinct a from (select distinct 'A' union select 'B') as foo(a);
select distinct a from (select distinct 'A' union select distinct 'B') as foo(a);
select distinct a from (select  'A' from (select distinct 'C' ) as bar union select distinct 'B') as foo(a);
select distinct a from (select  distinct 'A' from (select distinct 'C' ) as bar union select distinct 'B') as foo(a);
select distinct a from (select  distinct 'A' from (select 'C' from (select distinct 'D') as bar1 ) as bar union select distinct 'B') as foo(a);

--
-- Setup
--

--start_ignore
DROP TABLE IF EXISTS T_a1 CASCADE;
DROP TABLE IF EXISTS T_b2 CASCADE;
DROP TABLE IF EXISTS T_random CASCADE;
--end_ignore

CREATE TABLE T_a1 (a1 int, a2 int) DISTRIBUTED BY(a1);
INSERT INTO T_a1 SELECT i, i%5 from generate_series(1,10) i;

CREATE TABLE T_b2 (b1 int, b2 int) DISTRIBUTED BY(b2);
INSERT INTO T_b2 SELECT i, i%5 from generate_series(1,20) i;

CREATE TABLE T_random (c1 int, c2 int);
INSERT INTO T_random SELECT i, i%5 from generate_series(1,30) i;

create language plpythonu;

create or replace function count_operator(explain_query text, operator text) returns int as
$$
rv = plpy.execute(explain_query)
search_text = operator
result = 0
for i in range(len(rv)):
    cur_line = rv[i]['QUERY PLAN']
    if search_text.lower() in cur_line.lower():
        result = result+1
return result
$$
language plpythonu;

set optimizer = on;

--
-- N-ary UNION ALL results
-- @optimizer_mode on

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
UNION ALL
(select c1 from T_random)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select b1 from T_b2)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select c1 from T_random)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select c1 from T_random)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant)
UNION ALL
(select c1 from T_random)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
order by 1;

--
-- N-ary UNION ALL explain
-- @optimizer_mode on

select count_operator('
explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
UNION ALL
(select c1 from T_random)
UNION ALL
(select d1 from T_constant)
order by 1;'
, 'APPEND');

select count_operator('
explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select b1 from T_b2)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select c1 from T_random)
UNION ALL
(select d1 from T_constant)
order by 1;'
, 'APPEND');

select count_operator('
explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select c1 from T_random)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
UNION ALL
(select d1 from T_constant)
order by 1;'
, 'APPEND');

select count_operator('
explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant)
UNION ALL
(select c1 from T_random)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
order by 1;'
, 'APPEND');

--
-- N-ary UNION results
-- @optimizer_mode on

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select a1 from T_a1)
UNION
(select b1 from T_b2)
UNION
(select c1 from T_random)
UNION
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select b1 from T_b2)
UNION
(select a1 from T_a1)
UNION
(select c1 from T_random)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select c1 from T_random)
UNION
(select a1 from T_a1)
UNION
(select b1 from T_b2)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant)
UNION ALL
(select c1 from T_random)
UNION
(select a1 from T_a1)
UNION
(select b1 from T_b2)
order by 1;

--
-- N-ary UNION explain
-- @optimizer_mode on

select count_operator('
explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select a1 from T_a1)
UNION
(select b1 from T_b2)
UNION
(select c1 from T_random)
UNION
(select d1 from T_constant)
order by 1;'
, 'APPEND');

select count_operator('
explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select b1 from T_b2)
UNION
(select a1 from T_a1)
UNION
(select c1 from T_random)
UNION
(select d1 from T_constant)
order by 1;'
, 'APPEND');

select count_operator('
explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select c1 from T_random)
UNION
(select a1 from T_a1)
UNION
(select b1 from T_b2)
UNION
(select d1 from T_constant)
order by 1;'
, 'APPEND');

select count_operator('
explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant)
UNION
(select c1 from T_random)
UNION
(select a1 from T_a1)
UNION
(select b1 from T_b2)
order by 1;'
, 'APPEND');

--
-- Binary UNION ALL results
-- @optimizer_mode on

(select a1 from T_a1) UNION ALL (select b1 from T_b2) order by 1;

(select b1 from T_b2) UNION ALL (select a1 from T_a1) order by 1;

(select a1 from T_a1) UNION ALL (select c1 from T_random) order by 1;

(select c1 from T_random) UNION ALL (select a1 from T_a1) order by 1;

(select * from T_a1) UNION ALL (select * from T_b2) order by 1;

(select * from T_a1) UNION ALL (select * from T_random) order by 1;

(select * from T_b2) UNION ALL (select * from T_random) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select a1 from T_a1) UNION ALL (select d1 from T_constant) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant) UNION ALL (select a1 from T_a1) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select c1 from T_random) UNION ALL (select d1 from T_constant) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant) UNION ALL (select c1 from T_random) order by 1;

--
-- Binary UNION ALL explain
-- @optimizer_mode on

select count_operator('explain (select a1 from T_a1) UNION ALL (select b1 from T_b2) order by 1;', 'APPEND');

select count_operator('explain (select b1 from T_b2) UNION ALL (select a1 from T_a1) order by 1;', 'APPEND');

select count_operator('explain (select a1 from T_a1) UNION ALL (select c1 from T_random) order by 1;', 'APPEND');

select count_operator('explain (select c1 from T_random) UNION ALL (select a1 from T_a1) order by 1;', 'APPEND');

select count_operator('explain (select * from T_a1) UNION ALL (select * from T_b2) order by 1;', 'APPEND');

select count_operator('explain (select * from T_a1) UNION ALL (select * from T_random) order by 1;', 'APPEND');

select count_operator('explain (select * from T_b2) UNION ALL (select * from T_random) order by 1;', 'APPEND');

select count_operator('explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select a1 from T_a1) UNION ALL (select d1 from T_constant) order by 1;', 'APPEND');

select count_operator('explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant) UNION ALL (select a1 from T_a1) order by 1;', 'APPEND');

select count_operator('explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select c1 from T_random) UNION ALL (select d1 from T_constant) order by 1;', 'APPEND');

select count_operator('explain with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant) UNION ALL (select c1 from T_random) order by 1;', 'APPEND');

--
-- Binary UNION results
-- @optimizer_mode on

(select a1 from T_a1) UNION (select b1 from T_b2) order by 1;

(select b1 from T_b2) UNION (select a1 from T_a1) order by 1;

(select a1 from T_a1) UNION (select c1 from T_random) order by 1;

(select c1 from T_random) UNION (select a1 from T_a1) order by 1;

(select * from T_a1) UNION (select * from T_b2) order by 1;

(select * from T_a1) UNION (select * from T_random) order by 1;

(select * from T_b2) UNION (select * from T_random) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select a1 from T_a1) UNION (select d1 from T_constant) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant) UNION (select a1 from T_a1) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select c1 from T_random) UNION (select d1 from T_constant) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant) UNION (select c1 from T_random) order by 1;

--
-- Binary UNION explain
-- @optimizer_mode on

select count_operator('explain (select a1 from T_a1) UNION (select b1 from T_b2) order by 1;', 'APPEND');

select count_operator('explain (select b1 from T_b2) UNION (select a1 from T_a1) order by 1;', 'APPEND');

select count_operator('explain (select a1 from T_a1) UNION (select c1 from T_random) order by 1;', 'APPEND');

select count_operator('explain (select c1 from T_random) UNION (select a1 from T_a1) order by 1;', 'APPEND');

select count_operator('explain (select * from T_a1) UNION (select * from T_b2) order by 1;', 'APPEND');

select count_operator('explain (select * from T_a1) UNION (select * from T_random) order by 1;', 'APPEND');

select count_operator('explain (select * from T_b2) UNION (select * from T_random) order by 1;', 'APPEND');

select count_operator('explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select a1 from T_a1) UNION (select d1 from T_constant) order by 1;', 'APPEND');

select count_operator('explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant) UNION (select a1 from T_a1) order by 1;', 'APPEND');

select count_operator('explain
with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select c1 from T_random) UNION (select d1 from T_constant) order by 1;', 'APPEND');

select count_operator('explain with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant) UNION (select c1 from T_random) order by 1;', 'APPEND');

-- Test that we push quals into UNION sub-selects only when it's safe
-- @optimizer_mode on
explain
SELECT * FROM
  (SELECT 1 AS t, 2 AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x < 4;

SELECT * FROM
  (SELECT 1 AS t, 2 AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x < 4;

explain
SELECT * FROM
  (SELECT 1 AS t, generate_series(1,10) AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x < 4
ORDER BY x;

SELECT * FROM
  (SELECT 1 AS t, generate_series(1,10) AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x < 4
ORDER BY x;

explain
SELECT * FROM
  (SELECT 1 AS t, (random()*3)::int AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x > 3;

SELECT * FROM
  (SELECT 1 AS t, (random()*3)::int AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x > 3;

set optimizer = off;

--
-- N-ary UNION ALL results
-- @optimizer_mode off

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
UNION ALL
(select c1 from T_random)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select b1 from T_b2)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select c1 from T_random)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select c1 from T_random)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant)
UNION ALL
(select c1 from T_random)
UNION ALL
(select a1 from T_a1)
UNION ALL
(select b1 from T_b2)
order by 1;

--
-- N-ary UNION results
-- @optimizer_mode off

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select a1 from T_a1)
UNION
(select b1 from T_b2)
UNION
(select c1 from T_random)
UNION
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select b1 from T_b2)
UNION
(select a1 from T_a1)
UNION
(select c1 from T_random)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select c1 from T_random)
UNION
(select a1 from T_a1)
UNION
(select b1 from T_b2)
UNION ALL
(select d1 from T_constant)
order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant)
UNION ALL
(select c1 from T_random)
UNION
(select a1 from T_a1)
UNION
(select b1 from T_b2)
order by 1;

--
-- Binary UNION ALL results
-- @optimizer_mode off

(select a1 from T_a1) UNION ALL (select b1 from T_b2) order by 1;

(select b1 from T_b2) UNION ALL (select a1 from T_a1) order by 1;

(select a1 from T_a1) UNION ALL (select c1 from T_random) order by 1;

(select c1 from T_random) UNION ALL (select a1 from T_a1) order by 1;

(select * from T_a1) UNION ALL (select * from T_b2) order by 1;

(select * from T_a1) UNION ALL (select * from T_random) order by 1;

(select * from T_b2) UNION ALL (select * from T_random) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select a1 from T_a1) UNION ALL (select d1 from T_constant) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant) UNION ALL (select a1 from T_a1) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select c1 from T_random) UNION ALL (select d1 from T_constant) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION ALL SELECT 200, 200
UNION ALL SELECT 300, 300)
(select d1 from T_constant) UNION ALL (select c1 from T_random) order by 1;

--
-- Binary UNION results
-- @optimizer_mode off

(select a1 from T_a1) UNION (select b1 from T_b2) order by 1;

(select b1 from T_b2) UNION (select a1 from T_a1) order by 1;

(select a1 from T_a1) UNION (select c1 from T_random) order by 1;

(select c1 from T_random) UNION (select a1 from T_a1) order by 1;

(select * from T_a1) UNION (select * from T_b2) order by 1;

(select * from T_a1) UNION (select * from T_random) order by 1;

(select * from T_b2) UNION (select * from T_random) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select a1 from T_a1) UNION (select d1 from T_constant) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant) UNION (select a1 from T_a1) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select c1 from T_random) UNION (select d1 from T_constant) order by 1;

with T_constant (d1, d2) as(
SELECT 100, 100
UNION SELECT 200, 200
UNION SELECT 300, 300)
(select d1 from T_constant) UNION (select c1 from T_random) order by 1;

-- Test that we push quals into UNION sub-selects only when it's safe
-- @optimizer_mode off
explain
SELECT * FROM
  (SELECT 1 AS t, 2 AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x < 4;

SELECT * FROM
  (SELECT 1 AS t, 2 AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x < 4;

explain
SELECT * FROM
  (SELECT 1 AS t, generate_series(1,10) AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x < 4
ORDER BY x;

SELECT * FROM
  (SELECT 1 AS t, generate_series(1,10) AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x < 4
ORDER BY x;

explain
SELECT * FROM
  (SELECT 1 AS t, (random()*3)::int AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x > 3;

SELECT * FROM
  (SELECT 1 AS t, (random()*3)::int AS x
   UNION
   SELECT 2 AS t, 4 AS x) ss
WHERE x > 3;

CREATE TABLE foo_union (a int, b int);
CREATE TABLE bar_union (c int, d int);
INSERT INTO foo_union VALUES (1,1), (5,5);
INSERT INTO bar_union VALUES (5,5), (2,2);
EXPLAIN SELECT *
from
    (
    SELECT 1 AS ss
    UNION
    SELECT DISTINCT
        (
           SELECT bar_union.c FROM bar_union WHERE bar_union.c = foo_union.b 
        ) AS ss
        FROM foo_union
) ABC
where ABC.ss = 5;
SELECT *
from
    (
    SELECT 1 AS ss
    UNION
    SELECT DISTINCT
        (
           SELECT bar_union.c FROM bar_union WHERE bar_union.c = foo_union.b 
        ) AS ss
        FROM foo_union
) ABC
where ABC.ss = 5;

--
-- Clean up
--

DROP TABLE IF EXISTS T_a1 CASCADE;
DROP TABLE IF EXISTS T_b2 CASCADE;
DROP TABLE IF EXISTS T_random CASCADE;
DROP TABLE IF EXISTS foo_union;
DROP TABLE IF EXISTS bar_union;


reset optimizer;
-- EOF
