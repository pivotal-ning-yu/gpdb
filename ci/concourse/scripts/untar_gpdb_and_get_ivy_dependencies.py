#!/usr/bin/env python
import subprocess
import sys

def exec_command(cmd):
  print "Executing command: %s" %(cmd)
  retcode = subprocess.call(cmd, shell=True)
  if retcode != 0:
    sys.exit(retcode)


untar_gpdb_cmd = "mkdir -p gpdb_src && tar -xf gpdb_tarball/gpdb_src.tar.gz -C gpdb_src --strip 1"
exec_command(untar_gpdb_cmd)

get_ivy_dependencies_cmd = "gpdb_src/ci/concourse/scripts/get_ivy_dependencies.bash"
exec_command(get_ivy_dependencies_cmd)
