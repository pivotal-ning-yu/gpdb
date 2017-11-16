CREATE EXTERNAL TABLE mpp5993_ext (
                id text,
                stuff text
                )
LOCATION
(
      'gpfdist://10.0.0.240/gpfdist2/data/longline.txt'
)
FORMAT 'text'
(
        DELIMITER AS ','
)
;

CREATE TABLE mpp5993 (
                id text,
                stuff text
                );

SELECT count(*) FROM mpp5993_ext;
insert into mpp5993 select * from mpp5993_ext;
SELECT count(*) FROM mpp5993;

drop external table mpp5993_ext;
drop table mpp5993;
