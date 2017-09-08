#!/bin/bash

TINC_TARGET=$@

cat > ~/gpdb-env.sh << EOF
  source /usr/local/greenplum-db-devel/greenplum_path.sh
  export PGPORT=5432
  export MASTER_DATA_DIRECTORY=/data/gpdata/master/gpseg-1
  export PGDATABASE=gptest

  alias mdd='cd \$MASTER_DATA_DIRECTORY'
EOF
source ~/gpdb-env.sh

createdb gptest
createdb gpadmin
cd /home/gpadmin/gpdb_src/src/test/tinc
source tinc_env.sh
make $@
