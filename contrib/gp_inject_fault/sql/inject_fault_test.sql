-- Install a helper function to inject faults, using the fault injection
-- mechanism built into the server.
CREATE FUNCTION gp_inject_fault(
  faultname text,
  type text,
  ddl text,
  database text,
  tablename text,
  numoccurrences int4,
  sleeptime int4,
  db_id smallint)
RETURNS boolean
AS '$libdir/gp_inject_fault'
LANGUAGE C VOLATILE STRICT NO SQL;

begin;
-- inject fault of type sleep on all primaries
select gp_inject_fault('finish_prepared_after_record_commit_prepared',
       'sleep', '', '', '', 1, 2, dbid) from gp_segment_configuration
       where role = 'p' and content > -1;
-- check fault status
select gp_inject_fault('finish_prepared_after_record_commit_prepared',
       'status', '', '', '', 1, 2, dbid) from gp_segment_configuration
       where role = 'p' and content > -1;
-- commit transaction should trigger the fault
end;
-- fault status should indicate it's triggered
select gp_inject_fault('finish_prepared_after_record_commit_prepared',
       'status', '', '', '', 1, 2, dbid) from gp_segment_configuration
       where role = 'p' and content > -1;
-- reset the fault on all primaries
select gp_inject_fault('finish_prepared_after_record_commit_prepared',
       'reset', '', '', '', 1, 2, dbid) from gp_segment_configuration
       where role = 'p' and content > -1;
