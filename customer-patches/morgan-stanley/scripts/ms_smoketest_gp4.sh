#!/bin/bash -l

set -exo pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TOP_DIR=${CWDIR}/../../../..
source "${TOP_DIR}/gpdb_src/ci/concourse/scripts/common.bash"

function create_gpdb_bin() {
  mkdir bin_gpdb
  pushd ms_installer_rhel5_gpdb_rc

  unzip *.zip
  SKIP=$(awk '/^__END_HEADER__/ {print NR + 1; exit 0; }'  *.bin)

  ## Extract installer payload (compressed tarball)
  tail -n +${SKIP} *.bin > ../bin_gpdb/bin_gpdb.tar.gz
  popd
}


function prepare_test(){

  cat > /home/gpadmin/mad_test.sql <<- EOF_MAD
drop table if exists public.test_madlib;

CREATE TABLE public.test_madlib (trans_id integer,category varchar);

CREATE SCHEMA test_madlib;
INSERT INTO public.test_madlib
SELECT 1, 'television' as category UNION ALL
SELECT 2, 'hardware' UNION ALL
SELECT 3, 'plants' UNION ALL
SELECT 4, 'books' UNION ALL
SELECT 5, 'electronics';

SELECT madlib.assoc_rules (.01, .1, 'trans_id', 'category', 'test_madlib', 'test_madlib', true);
EOF_MAD


  cat > /home/gpadmin/plr_test.sql <<- EOF_PLR
CREATE LANGUAGE plr;
\i /usr/local/greenplum-db-devel/share/postgresql/contrib/plr.sql
SELECT * FROM plr_environ();
SELECT * FROM load_r_typenames();
SELECT * FROM r_typenames();
SELECT plr_array_accum('{23,35}', 42);
EOF_PLR

  # Create a minimal subset of example.sql to test pljava
  #  The complete example.sql file provided by pljava
  #  currently has many issues
  cat > /home/gpadmin/pljava_test.sql <<- EOF_PLJAVA
DROP SCHEMA IF EXISTS javatest CASCADE;
CREATE SCHEMA javatest;
set search_path=javatest,public;
set pljava_classpath='examples.jar';
set log_min_messages=info;  -- XXX

CREATE TABLE javatest.test AS SELECT 1 as i distributed by (i);

CREATE FUNCTION javatest.java_getTimestamp()
  RETURNS timestamp
  AS 'org.postgresql.example.Parameters.getTimestamp'
  LANGUAGE java;

  SELECT javatest.java_getTimestamp();
  SELECT javatest.java_getTimestamp() FROM javatest.test;
  SELECT * FROM javatest.java_getTimestamp();

CREATE FUNCTION javatest.java_getTimestamptz()
  RETURNS timestamptz
  AS 'org.postgresql.example.Parameters.getTimestamp'
  LANGUAGE java;

  SELECT javatest.java_getTimestamptz();
  SELECT javatest.java_getTimestamptz() FROM javatest.test;
  SELECT * FROM javatest.java_getTimestamptz();

CREATE FUNCTION javatest.print(date)
  RETURNS void
  AS 'org.postgresql.example.Parameters.print'
  LANGUAGE java;

  SELECT javatest.print('10-10-2010'::date);
  SELECT javatest.print('10-10-2010'::date) FROM javatest.test;
  SELECT * FROM javatest.print('10-10-2010'::date);

CREATE FUNCTION javatest.print(timetz)
  RETURNS void
  AS 'org.postgresql.example.Parameters.print'
  LANGUAGE java;

  SELECT javatest.print('12:00 PST'::timetz);
  SELECT javatest.print('12:00 PST'::timetz) FROM javatest.test;
  SELECT * FROM javatest.print('12:00 PST'::timetz);
EOF_PLJAVA

  cat > /home/gpadmin/pljava_test.sh <<- EOF_JAVA
psql -f $GPHOME/share/postgresql/pljava/install.sql testdb
gpconfig -c pljava_classpath -v \'examples.jar\'
gpstop -u
psql -P pager=off -f /home/gpadmin/pljava_test.sql testdb
psql -c "select * from javatest.java_getTimestamp();" testdb
EOF_JAVA

  chmod a+rx /home/gpadmin/pljava_test.sh

  cat > /home/gpadmin/pgcrypto_test.sql <<- EOF_CRYPT
\i /usr/local/greenplum-db-devel/share/postgresql/contrib/pgcrypto.sql
SELECT encode(digest('fluffy bunnies with big teeth', 'md5'), 'hex');
EOF_CRYPT


  cat > /home/gpadmin/test.sh <<- EOF
set -exo pipefail

source ${TOP_DIR}/gpdb_src/gpAux/gpdemo/gpdemo-env.sh
source /usr/local/greenplum-db-devel/greenplum_path.sh

createdb testdb
/usr/local/greenplum-db-devel/madlib/Current/bin/madpack -p greenplum -c gpadmin@localhost:15432/testdb install
psql -P pager -f ~/mad_test.sql testdb 
psql -P pager -f ~/plr_test.sql testdb 
psql -P pager -f ~/pgcrypto_test.sql testdb 
~/pljava_test.sh
gpcopy --version || exit 1

EOF

  chown -R gpadmin:gpadmin $(pwd)
  chown gpadmin:gpadmin /home/gpadmin/test.sh
  chmod a+x /home/gpadmin/test.sh
  mkdir -p /usr/lib64/R/lib64
  ln -s /usr/local/greenplum-db-devel/ext/R-3.3.3 /usr/lib64/R/lib64/R
  chown -R gpadmin:gpadmin /usr/lib64/R/

}

function test() {
  su gpadmin -c "bash /home/gpadmin/test.sh $(pwd)"
}

function test_gpdb4() {
  su gpadmin -c "bash /home/gpadmin/test.sh $(pwd)"
}

function setup_gpadmin_user() {
  case "$OSVER" in
    suse*)
    ${TOP_DIR}/gpdb_src/ci/concourse/scripts/setup_gpadmin_user.bash "sles"
    ;;
    centos*)
    ${TOP_DIR}/gpdb_src/ci/concourse/scripts/setup_gpadmin_user.bash "centos"
    ;;
    *) echo "Unknown OS: $OSVER"; exit 1 ;;
  esac
}

function _main() {
  pushd $TOP_DIR
    create_gpdb_bin

    time install_gpdb
    time setup_gpadmin_user

    if [ "$OSVER" == "centos5" ]; then
      rm /home/gpadmin/.ssh/config
    fi

    time make_cluster
    time prepare_test
    time test
  popd
}

_main "$@"
