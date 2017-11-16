CREATE EXTERNAL TABLE ext_lineitem (
                L_ORDERKEY INT8,
                L_PARTKEY INTEGER,
                L_SUPPKEY INTEGER,
                L_LINENUMBER integer,
                L_QUANTITY decimal,
                L_EXTENDEDPRICE decimal,
                L_DISCOUNT decimal,
                L_TAX decimal,
                L_RETURNFLAG CHAR(2),
                L_LINESTATUS CHAR(2),
                L_SHIPDATE date,
                L_COMMITDATE date,
                L_RECEIPTDATE date,
                L_SHIPINSTRUCT CHAR(2),
                L_SHIPMODE CHAR(1)
                )
LOCATION
(
        'gpfdist://10.1.2.12/gpfdist2/data/lineitem.tbl'
)
FORMAT 'text'
(
        DELIMITER AS '|'
)
;
SELECT count(*) FROM ext_lineitem;
DROP EXTERNAL TABLE ext_lineitem;

CREATE EXTERNAL TABLE ext_lineitem (
                L_ORDERKEY INT8,
                L_PARTKEY INTEGER,
                L_SUPPKEY INTEGER,
                L_LINENUMBER integer,
                L_QUANTITY decimal,
                L_EXTENDEDPRICE decimal,
                L_DISCOUNT decimal,
                L_TAX decimal,
                L_RETURNFLAG CHAR(2),
                L_LINESTATUS CHAR(2),
                L_SHIPDATE date,
                L_COMMITDATE date,
                L_RECEIPTDATE date,
                L_SHIPINSTRUCT CHAR(2),
                L_SHIPMODE CHAR(1),
		L_COMMENT VARCHAR(44),
		L_BLAH CHAR(1)
                )
LOCATION
(
        'gpfdist://10.1.2.12/gpfdist2/data/lineitem.tbl'
)
FORMAT 'text'
(
        DELIMITER AS '|'
)
;
SELECT count(*) FROM ext_lineitem;
DROP EXTERNAL TABLE ext_lineitem;
