\set scale @scale@

\set naccounts 100000 * :scale
\setrandom aid 1 :naccounts

BEGIN;
	SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
END;
