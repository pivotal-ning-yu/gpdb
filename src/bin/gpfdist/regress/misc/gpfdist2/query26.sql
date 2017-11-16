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
        'gpfdist://10.1.2.12/gpfdist2/data/more_data/lineitem.tbl.space'
)
FORMAT 'text'
(
	DELIMITER ' '
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
        'gpfdist://10.1.2.12/gpfdist2/data/more_data/lineitem.tbl.comma'
)
FORMAT 'text'
(
        DELIMITER ','
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
        'gpfdist://10.1.2.12/gpfdist2/data/more_data/lineitem.tbl.carrot'
)
FORMAT 'text'
(
        DELIMITER '^'
)
;
SELECT count(*) FROM ext_lineitem;
DROP EXTERNAL TABLE ext_lineitem;

