create external table xab_ext (
zdate int,
ztime int,
sid int,
uid int,
pid bigint,
hostname varchar(40),
details varchar(1000),
url varchar(500))
location ('gpfdist://10.1.2.10/gpfdist2/data/xab')
format 'text'
(delimiter as '' null as '');

\d+ xab_ext

select count(*) from xab_ext;

drop external table xab_ext;
