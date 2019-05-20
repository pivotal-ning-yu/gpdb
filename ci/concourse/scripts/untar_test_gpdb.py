#!/usr/bin/env python
import subprocess
import sys
import os

test_failed = 0;

def exec_command(cmd, ignore):
  global test_failed
  print "Executing command: %s" %(cmd)
  retcode = subprocess.call(cmd, shell=True)
  if retcode != 0:
    test_failed = retcode
    if not ignore:
      sys.exit(retcode)

untar_gpdb_cmd = "mkdir -p gpdb_src && tar -xf gpdb_tarball/gpdb_src.tar.gz -C gpdb_src --strip 1"
exec_command(untar_gpdb_cmd, False)

run_ic_tests_cmd = "gpdb_src/ci/concourse/scripts/ic_gpdb.bash"
exec_command(run_ic_tests_cmd, True)

if os.path.exists("gpdb_src/src/test/regress/regression.out") and os.path.exists("gpdb_src/src/test/regress/regression.diffs"):
  copy_diff_cmd = "cp gpdb_src/src/test/regress/regression.diffs icg_output/regression.diffs"
  exec_command(copy_diff_cmd, False)
  copy_out_cmd = "cp gpdb_src/src/test/regress/regression.out icg_output/regression.out"
  exec_command(copy_out_cmd, False)

if test_failed != 0:
  sys.exit(test_failed)
