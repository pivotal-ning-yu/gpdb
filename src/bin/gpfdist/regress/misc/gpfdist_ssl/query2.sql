DROP TABLE tbl_on_heap;
CREATE TABLE tbl_on_heap (
            s1 text, s2 text, s3 text, dt timestamp,
            n1 smallint, n2 integer, n3 bigint, n4 decimal,
            n5 numeric, n6 real, n7 double precision);
INSERT INTO tbl_on_heap VALUES
('aaa','twoa','shpits','2011-06-01 12:30:30',23,732,834567,45.67,789.123,7.12345,123.456789),
('bbb','twob','shpits','2011-06-01 12:30:30',23,732,834567,45.67,789.123,7.12345,123.456789),
('ccc','twoc','shpits','2011-06-01 12:30:30',23,732,834567,45.67,789.123,7.12345,123.456789 );
DROP EXTERNAL TABLE IF EXISTS tbl;
CREATE WRITABLE EXTERNAL TABLE tbl (s1 text, s2 text, s3 text, dt timestamp,n1 smallint, n2 integer, n3 bigint, n4 decimal, n5 numeric, n6 real, n7 double precision)
LOCATION ('gpfdists://127.0.0.1:8080/gpfdist_ssl/data/tbl2.tbl')
FORMAT 'TEXT' (DELIMITER '|' );
INSERT INTO tbl SELECT * FROM tbl_on_heap;
SELECT * FROM tbl_on_heap ORDER BY s1;
DROP TABLE IF EXISTS tbl_on_heap2;
CREATE TABLE tbl_on_heap2 (
            s1 text, s2 text, s3 text, dt timestamp,
            n1 smallint, n2 integer, n3 bigint, n4 decimal,
            n5 numeric, n6 real, n7 double precision);
DROP EXTERNAL TABLE IF EXISTS tbl2;
CREATE EXTERNAL TABLE tbl2 (s1 text, s2 text, s3 text, dt timestamp,n1 smallint, n2 integer, n3 bigint, n4 decimal, n5 numeric, n6 real, n7 double precision)
LOCATION ('gpfdists://127.0.0.1:8080/gpfdist_ssl/data/tbl2.tbl')
FORMAT 'TEXT' (DELIMITER '|' );
INSERT INTO tbl_on_heap2 SELECT * FROM tbl2;
SELECT * FROM tbl_on_heap2 ORDER BY s1;
