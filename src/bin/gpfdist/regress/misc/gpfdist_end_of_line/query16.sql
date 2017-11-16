CREATE OR REPLACE FUNCTION fxwd_in() RETURNS record AS '$libdir/fixedwidth.so', 'fixedwidth_in' LANGUAGE C STABLE;
CREATE OR REPLACE FUNCTION fxwd_out(record) RETURNS bytea AS '$libdir/fixedwidth.so', 'fixedwidth_out' LANGUAGE C STABLE;
DROP EXTERNAL TABLE IF EXISTS tbl_ext_fixedwidth;
CREATE READABLE EXTERNAL TABLE tbl_ext_fixedwidth ( 
            s1 char(10), s2 varchar(10), s3 text, dt timestamp,   
            n1 smallint, n2 integer, n3 bigint, n4 decimal,       
            n5 numeric, n6 real, n7 double precision) 
        LOCATION ('gpfdist://10.110.120.137/gpfdist_end_of_line/data/fixedwidth_small_correct.tbl')   
        FORMAT 'CUSTOM' (formatter='fxwd_in', s1='10',             
            s2='10', s3='10', dt='20',n1='5', n2='10',                                                                                                                                      
            n3='10', n4='10', n5='10', n6='10', n7='15',line_delim=E'\n');
DROP EXTERNAL TABLE IF EXISTS tbl_out_fixedwidth; 
CREATE WRITABLE EXTERNAL TABLE tbl_out_fixedwidth (
            s1 char(10), s2 varchar(10), s3 text, dt timestamp, 
            n1 smallint, n2 integer, n3 bigint, n4 decimal, 
            n5 numeric, n6 real, n7 double precision)                                                              
        LOCATION ('gpfdist://10.110.120.137/gpfdist_end_of_line/data/fixedwidth_out.tbl')     
        FORMAT 'CUSTOM' (formatter='fxwd_out', s1='10', 
            s2='10', s3='10', dt='20', n1='5', n2='10', 
            n3='10', n4='10', n5='10', n6='10', n7='15',line_delim='xx');  
DROP TABLE IF EXISTS tbl_on_heap;
CREATE TABLE tbl_on_heap (
            s1 char(10), s2 varchar(10), s3 text, dt timestamp, 
            n1 smallint, n2 integer, n3 bigint, n4 decimal, 
            n5 numeric, n6 real, n7 double precision);
INSERT INTO tbl_on_heap SELECT * FROM tbl_ext_fixedwidth;
INSERT INTO tbl_out_fixedwidth SELECT * FROM tbl_on_heap ORDER BY s1;

DROP EXTERNAL TABLE IF EXISTS tbl_ext_fixedwidth;
CREATE READABLE EXTERNAL TABLE tbl_ext_fixedwidth (
            s1 char(10), s2 varchar(10), s3 text, dt timestamp,
            n1 smallint, n2 integer, n3 bigint, n4 decimal,
            n5 numeric, n6 real, n7 double precision)
        LOCATION ('gpfdist://10.110.120.137/gpfdist_end_of_line/data/fixedwidth_out.tbl')
        FORMAT 'CUSTOM' (formatter='fxwd_in', s1='10',
            s2='10', s3='10', dt='20',n1='5', n2='10',
            n3='10', n4='10', n5='10', n6='10', n7='15',line_delim='xx');
DROP TABLE IF EXISTS tbl_on_heap;
CREATE TABLE tbl_on_heap (
            s1 char(10), s2 varchar(10), s3 text, dt timestamp,
            n1 smallint, n2 integer, n3 bigint, n4 decimal,
            n5 numeric, n6 real, n7 double precision);
INSERT INTO tbl_on_heap SELECT * FROM tbl_ext_fixedwidth;
SELECT * FROM tbl_on_heap ORDER BY s1;

