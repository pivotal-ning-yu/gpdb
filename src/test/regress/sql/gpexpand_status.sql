--
-- this test verifies the gp_expand_get_status() function with simulated
-- gpexpand status files and schema tables.
--

-- start_ignore
CREATE LANGUAGE plpythonu;
-- end_ignore

-- check that real world gpexpand is not in progress
\! test -e $MASTER_DATA_DIRECTORY/gpexpand.status; echo $?;
\! test -e $MASTER_DATA_DIRECTORY/gpexpand.phase2.status; echo $?;

-- prepare two databases, gpexpand1 contains the simulated gpexpand schema
DROP database IF EXISTS gpexpand1;
DROP database IF EXISTS gpexpand2;
CREATE DATABASE gpexpand1;
CREATE DATABASE gpexpand2;

-- execute query in gpexpand1
CREATE OR REPLACE FUNCTION query_gpexpand1(sql text) RETURNS void AS $$
    import pygresql.pg as pg
    db = pg.connect(dbname='gpexpand1')
    db.query(sql)
$$ LANGUAGE plpythonu VOLATILE;

-- get gpexpand status by connect to both gpexpand1 and gpexpand2
CREATE OR REPLACE FUNCTION get_all_status(out db text, out code integer, out status text, out detail text)
RETURNS setof record AS $$
    import pygresql.pg as pg
    db1 = pg.connect(dbname='gpexpand1')
    db2 = pg.connect(dbname='gpexpand2')
    sql1 = '''select 'gpexpand1' as db, * from gp_expand_get_status()'''
    sql2 = '''select 'gpexpand2' as db, * from gp_expand_get_status()'''
    return db1.query(sql1).getresult() + db2.query(sql2).getresult()
$$ LANGUAGE plpythonu VOLATILE;

-- get 'gpstate -x' output
CREATE OR REPLACE FUNCTION gpstate(
    out "timestamp" text,
    out command text,
    out hostname text,
    out username text,
    out level text,
    out message text)
RETURNS setof record AS $$
    import os
    import re
    pattern = ''.join([
        '^(?P<timestamp>.*)',
        ' (?P<command>.*)',
        ':(?P<hostname>.*)',
        ':(?P<username>.*)',
        '-\[(?P<level>.*)\]',
        ':-(?P<message>.*)',
        '\s*$',
        ])
    results = []
    for line in os.popen('gpstate -x').readlines():
        m = re.search(pattern, line)
        results.append((
            m.group('timestamp'),
            m.group('command'),
            m.group('hostname'),
            m.group('username'),
            m.group('level'),
            m.group('message'),
        ))
    return results
$$ LANGUAGE plpythonu VOLATILE;

-- the status can only be queried on master, so below query should fail
select gp_expand_get_status() from gp_dist_random('gp_id');

-- phase0: neither status file nor status schema exist
select * from get_all_status();
select level, message from gpstate() offset 5;

-- gpstate also output gpexpand status summary in default or detail modes.
-- output nothing in phase0.
\! gpstate    | grep 'Cluster Expansion' | cut -d= -f2-
\! gpstate -s | grep 'Cluster Expansion' | cut -d= -f2-

-- phase1: as long as status file exists it is phase1, even if it is empty
\! touch $MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- gpstate also output gpexpand status summary in default or detail modes.
-- output 'In Progress' in phase1 or phase2.
\! gpstate    | grep 'Cluster Expansion' | cut -d= -f2-
\! gpstate -s | grep 'Cluster Expansion' | cut -d= -f2-

-- phase1: tolerate syntax error
\! echo 'INVALID FORMAT' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- phase1: tolerate unknown status name
\! echo 'UNKNOWN PHASE1 STATUS:None' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- phase1: below are all known phase1 phase2 status names

\! echo 'UNINITIALIZED:None' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'EXPANSION_PREPARE_STARTED:<path> to inputfile' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'BUILD_SEGMENT_TEMPLATE_STARTED:<path> to template dir' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'BUILD_SEGMENT_TEMPLATE_DONE:None' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'BUILD_SEGMENTS_STARTED:<path> to schema tarball' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'BUILD_SEGMENTS_DONE:1' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'UPDATE_CATALOG_STARTED:<path> to gp_segment_configuration backup' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'UPDATE_CATALOG_DONE:None' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'SETUP_EXPANSION_SCHEMA_STARTED:None' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- phase1: it is still phase1 even if phase2 schema is created
select query_gpexpand1('
    create schema gpexpand;
    create table gpexpand.status (status text, updated timestamp);
    create table gpexpand.status_detail (
        dbname text,
        fq_name text,
        schema_oid oid,
        table_oid oid,
        distribution_policy smallint[],
        distribution_policy_names text,
        distribution_policy_coloids text,
        distribution_policy_type text,
        root_partition_name text,
        storage_options text,
        rank int,
        status text,
        expansion_started timestamp,
        expansion_finished timestamp,
        source_bytes numeric
    );
');
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'SETUP_EXPANSION_SCHEMA_DONE:None' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'PREPARE_EXPANSION_SCHEMA_STARTED:None' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- phase1: it is still phase1 even if phase2 schema is filled
select query_gpexpand1('
    insert into gpexpand.status values ( ''SETUP'', ''01-01-01'' );
    insert into gpexpand.status_detail (dbname, fq_name, rank, status) values
      (''gpexpand1'', ''public.t1'', 2, ''NOT STARTED''),
      (''gpexpand1'', ''public.t2'', 2, ''NOT STARTED'');
    insert into gpexpand.status values ( ''SETUP DONE'', ''01-01-02'' );
');
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'PREPARE_EXPANSION_SCHEMA_DONE:None' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

\! echo 'EXPANSION_PREPARE_DONE:gpexpand1' >>$MASTER_DATA_DIRECTORY/gpexpand.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- phase1: it is still phase1 even if phase2 status file exists
\! echo 'FAKE PHASE2 STATUS:still phase1' >>$MASTER_DATA_DIRECTORY/gpexpand.phase2.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- phase2: no longer phase1 as long as phase1 status file is removed
-- - when connected to gpexpand1 the progress information is available
-- - when connected to other databases we can still know it is phase2
\! rm $MASTER_DATA_DIRECTORY/gpexpand.status
\! echo -n 'gpexpand1' > $MASTER_DATA_DIRECTORY/gpexpand.phase2.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- gpstate also output gpexpand status summary in default or detail modes.
-- output 'In Progress' in phase1 or phase2.
\! gpstate    | grep 'Cluster Expansion' | cut -d= -f2-
\! gpstate -s | grep 'Cluster Expansion' | cut -d= -f2-

select query_gpexpand1('
    insert into gpexpand.status values ( ''EXPANSION STARTED'', ''01-01-03'' );
');
select * from get_all_status();
select level, message from gpstate() offset 5;

select query_gpexpand1('
    update gpexpand.status_detail set status=''IN PROGRESS''
     where fq_name=''public.t1'';
');
select * from get_all_status();
select level, message from gpstate() offset 5;

select query_gpexpand1('
    update gpexpand.status_detail set status=''COMPLETED''
     where fq_name=''public.t1'';
');
select * from get_all_status();
select level, message from gpstate() offset 5;

select query_gpexpand1('
    insert into gpexpand.status values ( ''EXPANSION STOPPED'', ''01-01-04'' );
');
select * from get_all_status();
select level, message from gpstate() offset 5;

select query_gpexpand1('
    insert into gpexpand.status values ( ''EXPANSION STARTED'', ''01-01-05'' );
    update gpexpand.status_detail set status=''COMPLETED''
     where fq_name=''public.t2'';
    insert into gpexpand.status values ( ''EXPANSION COMPLETE'', ''01-01-06'' );
');
select * from get_all_status();
select level, message from gpstate() offset 5;

-- phase2: it is still phase2 even if the schema is dropped
select query_gpexpand1('
    drop schema gpexpand cascade;
');
select * from get_all_status();
select level, message from gpstate() offset 5;

-- phase0: it is phase0 again after phase2 status file is also removed
\! rm $MASTER_DATA_DIRECTORY/gpexpand.phase2.status
select * from get_all_status();
select level, message from gpstate() offset 5;

-- gpstate also output gpexpand status summary in default or detail modes.
-- output nothing in phase0.
\! gpstate    | grep 'Cluster Expansion' | cut -d= -f2-
\! gpstate -s | grep 'Cluster Expansion' | cut -d= -f2-
