--
-- SIGSEGV issue when freeing gangs
--
DROP TABLE IF EXISTS foo;
CREATE TABLE foo (c1 int, c2 int) DISTRIBUTED BY (c1);

1: BEGIN;

! gpfaultinjector -f create_gang_in_progress -m async -y reset -o 0 -s 1;
! gpfaultinjector -f create_gang_in_progress -m async -y suspend -o 0 -s 1;

1&: SELECT * FROM foo a JOIN foo b USING (c2);

SELECT pg_terminate_backend(procpid) FROM pg_stat_activity WHERE current_query = 'SELECT * FROM foo a JOIN foo b USING (c2);';

! gpfaultinjector -f create_gang_in_progress -m async -y resume -o 0 -s 1;

1<:
1q
