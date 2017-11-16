CREATE EXTERNAL TABLE ext_lineitem (
                L_ORDERKEY INT8,
                L_PARTKEY INTEGER,
                L_SUPPKEY INTEGER,
                L_LINENUMBER integer,
                L_QUANTITY decimal,
                L_EXTENDEDPRICE decimal,
                L_DISCOUNT decimal,
                L_TAX decimal,
                L_RETURNFLAG CHAR(1),
                L_LINESTATUS CHAR(1),
                L_SHIPDATE date,
                L_COMMITDATE date,
                L_RECEIPTDATE date,
                L_SHIPINSTRUCT CHAR(25),
                L_SHIPMODE CHAR(10),
                L_COMMENT VARCHAR(44)
                )
LOCATION
(
        'gpfdist://10.1.2.12/gpfdist2/data/lineitem.tbl'
)
FORMAT 'text'
(
	DELIMITER '|'
)
;
SELECT DISTINCT L_ORDERKEY FROM ext_lineitem WHERE L_ORDERKEY > 10 GROUP BY L_ORDERKEY ORDER BY L_ORDERKEY LIMIT 10 OFFSET 2;
DROP EXTERNAL TABLE ext_lineitem;
