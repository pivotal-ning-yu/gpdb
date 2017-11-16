CREATE OR REPLACE FUNCTION fxwd_in() RETURNS record AS '$libdir/fixedwidth.so', 'fixedwidth_in' LANGUAGE C STABLE;
CREATE OR REPLACE FUNCTION fxwd_out(record) RETURNS bytea AS '$libdir/fixedwidth.so', 'fixedwidth_out' LANGUAGE C STABLE;
DROP EXTERNAL TABLE IF EXISTS tbl_ext_fixedwidth;
CREATE READABLE EXTERNAL TABLE tbl_ext_fixedwidth (
            s1 char(10))                                                              
LOCATION ('gpfdist://10.110.120.137/gpfdist_end_of_line/data/fixedwidth_small_correct1.tbl')       
        FORMAT 'CUSTOM' (formatter='fxwd_in', s1='10');
DROP EXTERNAL TABLE IF EXISTS tbl_out_fixedwidth; 
CREATE WRITABLE EXTERNAL TABLE tbl_out_fixedwidth (
            s1 char(10))                                                              
        LOCATION ('gpfdist://10.110.120.137/gpfdist_end_of_line/data/fixedwidth_out.tbl')     
        FORMAT 'CUSTOM' (formatter='fxwd_out', s1='10',line_delim=' ');  
INSERT INTO tbl_out_fixedwidth 
SELECT * FROM tbl_ext_fixedwidth ORDER BY s1; 

DROP EXTERNAL TABLE IF EXISTS tbl_ext_fixedwidth;
CREATE READABLE EXTERNAL TABLE tbl_ext_fixedwidth (
            s1 char(10))
       LOCATION ('gpfdist://10.110.120.137/gpfdist_end_of_line/data/fixedwidth_out.tbl')
       FORMAT 'CUSTOM' (formatter='fxwd_in', s1='10',line_delim=' ');
DROP TABLE IF EXISTS tbl_on_heap;
CREATE TABLE tbl_on_heap (
            s1 char(10));
INSERT INTO tbl_on_heap SELECT * FROM tbl_ext_fixedwidth;
SELECT * FROM tbl_on_heap ORDER BY s1;
