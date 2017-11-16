CREATE EXTERNAL TABLE ext_test (
                id text,
                stuff text
                )
LOCATION
(
      'gpfdist://10.1.2.12/gpfdist2/data/10lines.txt'
)
FORMAT 'text'
(
        DELIMITER AS ','
)
;
SELECT count(*) FROM ext_test;
DROP EXTERNAL TABLE ext_test;

CREATE EXTERNAL TABLE ext_test1 (
                id text,
                stuff text
                )
LOCATION
(
      'gpfdist://10.1.2.12/gpfdist2/data/10lines.csv'
)
FORMAT 'csv'
(
        DELIMITER AS ','
)
;
SELECT count(*) FROM ext_test1;
DROP EXTERNAL TABLE ext_test1;
