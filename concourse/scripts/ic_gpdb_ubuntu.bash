#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GREENPLUM_INSTALL_DIR=/usr/local/gpdb

function load_transfered_bits_into_install_dir() {
  mkdir -p $GREENPLUM_INSTALL_DIR
  tar xzf $TRANSFER_DIR/$COMPILED_BITS_FILENAME -C $GREENPLUM_INSTALL_DIR
}

function configure() {
  pushd gpdb_src
    ./configure --prefix=${GREENPLUM_INSTALL_DIR} --with-gssapi --with-perl --with-python --with-libxml --enable-mapreduce --enable-orafce --disable-orca ${CONFIGURE_FLAGS}
  popd
}

function setup_gpadmin_user() {
    ./gpdb_src/concourse/scripts/setup_gpadmin_user.bash ubuntu
}

function make_cluster() {
  source "${GREENPLUM_INSTALL_DIR}/greenplum_path.sh"
  export BLDWRAP_POSTGRES_CONF_ADDONS=${BLDWRAP_POSTGRES_CONF_ADDONS}
  # Currently, the max_concurrency tests in src/test/isolation2
  # require max_connections of at least 129.
  export DEFAULT_QD_MAX_CONNECT=150
  export STATEMENT_MEM=250MB
  su gpadmin -c bash <<EOF
    pushd gpdb_src/gpAux/gpdemo
    . ${GREENPLUM_INSTALL_DIR}/greenplum_path.sh
    make create-demo-cluster "$@"
    popd
EOF
}

function gen_icw_test_script(){
  cat > /opt/run_test.sh <<-EOF
  SRC_DIR="\${1}/gpdb_src"
  trap look4diffs ERR
  function look4diffs() {
    diff_files=\`find .. -name regression.diffs\`
    for diff_file in \${diff_files}; do
      if [ -f "\${diff_file}" ]; then
        cat <<-FEOF
          ======================================================================
          DIFF FILE: \${diff_file}
          ----------------------------------------------------------------------
          \$(cat "\${diff_file}")
FEOF
      fi
    done
  exit 1
  }
  source ${GREENPLUM_INSTALL_DIR}/greenplum_path.sh
  source \${SRC_DIR}/gpAux/gpdemo/gpdemo-env.sh
  cd \${SRC_DIR}
  make ${MAKE_TEST_COMMAND}

EOF

	chmod a+x /opt/run_test.sh
}

function gen_unit_test_script(){
  cat > /opt/run_unit_test.sh <<-EOF
    SRC_DIR="\${1}/gpdb_src"
    RESULT_FILE="\${SRC_DIR}/gpMgmt/gpMgmt_testunit_results.log"
    trap look4results ERR
    function look4results() {
      cat "\${RESULT_FILE}"
      exit 1
    }
    source ${GREENPLUM_INSTALL_DIR}/greenplum_path.sh
    source \${SRC_DIR}/gpAux/gpdemo/gpdemo-env.sh
    cd \${SRC_DIR}/gpMgmt/bin
    make check
    # show results into concourse
    cat \${RESULT_FILE}
EOF

	chmod a+x /opt/run_unit_test.sh
}

function run_icw_test() {
  su - gpadmin -c "bash /opt/run_test.sh $(pwd)"
}

function run_unit_test() {
  su - gpadmin -c "bash /opt/run_unit_test.sh $(pwd)"
}

# usage: gen_gpexpand_input <old_size> <new_size>
function gen_gpexpand_input() {
  local old="$1"
  local new="$2"
  local inputfile="/tmp/inputfile.${old}-${new}"
  local i

  for ((i=old; i<new; i++)); do
    cat <<EOF
$HOSTNAME:$HOSTNAME:$((25432+i*2)):$PWD/datadirs/expand/primary${i}:$((3+i*2)):${i}:p
$HOSTNAME:$HOSTNAME:$((25433+i*2)):$PWD/datadirs/expand/mirror${i}:$((4+i*2)):${i}:m
EOF
  done | tee $inputfile

  chmod a+r $inputfile
}

# extract PGOPTIONS from MAKE_TEST_COMMAND
function get_pgoptions() {
  #echo "-c gp_expand_method=rebuild -c optimizer=off"
  #return
  local pgoptions

  cat >/tmp/get_pgoptions.mk <<"EOF"
$(info $(PGOPTIONS))
EOF

  pgoptions="$(eval make $MAKE_TEST_COMMAND --no-print-directory -nqf /tmp/get_pgoptions.mk 2>/dev/null)"
  echo "$pgoptions"
}

function bypass_known_expand_failures() {
  local pgoptions="$(get_pgoptions)"

  PGOPTIONS="$pgoptions" \
  runuser -pu gpadmin -- \
  /usr/local/gpdb/bin/psql -a -d regression -h localhost -p 15432 <<"EOF"
\pset pager off
set allow_system_table_mods to true;

-- created by gp_upgrade_cornercases.sql, a column is dropped on a partition
-- table only on the parent, so children have more columns than parent,
-- UPDATE will raise an error on this, so the reshuffle method will also fail
-- as it is based on UPDATE.  There is a plan to prohibit dropping columns
-- only on parent, so we will not fix the issue, we will simply skip it.
drop table if exists upgrade_cornercases.part cascade;

-- created by gp_rules.sql and oid_consistency.sql, the tables are converted
-- to views by setting _RETURN rules on them, they no longer accept operations
-- for tables, such as ALTER/DROP TABLE, however gpexpand still consider them
-- as tables and attempt to expand them.  Hack the catalog to make them views
-- entirely, it is enough to hack only on master.
update pg_class set relstorage='v' where relname in
  ( 'table_to_view_test1'
  , 'oid_consistency_tt1'
  );
delete from gp_distribution_policy where localoid in
  ( 'table_to_view_test1'::regclass
  , 'oid_consistency_tt1'::regclass
  );

-- created by gpcopy.source, gpexpand does not handle db names with special
-- characters correctly, so their tables can not be expanded.
\connect "funny copy""db'with\\quotes"
drop table if exists public.foo cascade;
EOF
}

# usage: expand_cluster <old_size> <new_size>
function expand_cluster() {
  local old="$1"
  local new="$2"
  local inputfile="/tmp/inputfile.${old}-${new}"
  local pidfile="/tmp/postmaster.pid.${old}-${new}"
  local dbname="gpstatus"
  local pgoptions="$(get_pgoptions)"
  local uncompleted
  local partial

  pushd gpdb_src/gpAux/gpdemo

  gen_gpexpand_input "$old" "$new"

  su gpadmin -c bash <<EOF
    set -ex

    . ${GREENPLUM_INSTALL_DIR}/greenplum_path.sh
    . gpdemo-env.sh
    export PGOPTIONS="$pgoptions"

    # Backup master pid, by checking it later we can know whether the cluster is
    # restarted during the tests.
    head -n 1 \$MASTER_DATA_DIRECTORY/postmaster.pid >$pidfile
    createdb $dbname 2>/dev/null || : # ignore failure

    # begin expansion
    yes | gpexpand -D $dbname -s -i $inputfile

    # redistribute tables
    yes | gpexpand -D $dbname -s

    # check the result
    psql -Aqtd $dbname -c "select count(*) from gpexpand.status_detail where status <> 'COMPLETED'" >/tmp/uncompleted.count
    # double check gp_distribution_policy.numsegments
    psql -Aqtd $dbname -c "select count(*) from gp_distribution_policy where numsegments <> $new" >/tmp/partial.count

    # cleanup
    yes | gpexpand -D $dbname -s -c
EOF

  popd

  uncompleted=$(cat /tmp/uncompleted.count)
  if [ "$uncompleted" -ne 0 ]; then
	  echo "error: some tables are not successfully expanded"
	  return 1
  fi

  # double check gp_distribution_policy.numsegments
  partial=$(cat /tmp/partial.count)
  if [ "$partial" -ne 0 ]; then
	  echo "error: not all the tables are expanded by gpexpand"
	  return 1
  fi

  echo "all the tables are successfully expanded"
  return 0
}

function _main() {
    if [ -z "${MAKE_TEST_COMMAND}" ]; then
        echo "FATAL: MAKE_TEST_COMMAND is not set"
        exit 1
    fi

    time load_transfered_bits_into_install_dir
    time configure
    time setup_gpadmin_user
    # If $TEST_EXPAND is set, the job is to run ICW after expansion to see
    # whether all the cases have been passed without restarting cluster.
    # So it will create a cluster with two segments and execute gpexpand to
    # expand the cluster to three segments
    if [ "$TEST_EXPAND" = "true" ]; then
        time make_cluster NUM_PRIMARY_MIRROR_PAIRS=2
        time expand_cluster 2 3
    else
        time make_cluster
    fi
    time gen_unit_test_script
    time gen_icw_test_script
    time run_unit_test
    time run_icw_test
    # If $TEST_EXPAND is set, the job is to run ICW after expansion to see
    # whether all the cases have been passed without restarting cluster.
    # Here is to check whether the cluster has been restarted by master pid.
    # We wanna to be sure all the test cases have been passed after expansion
    # without restarting the cluster. So any restarting is not expected.
    if [ "$TEST_EXPAND" = "true" ]; then
      OLD_MASTER_PID=`cat /tmp/postmaster.pid.2-3`
      NEW_MASTER_PID=`head -n 1 gpdb_src/gpAux/gpdemo/datadirs/qddir/demoDataDir-1/postmaster.pid`
      if [ "$OLD_MASTER_PID" != "$NEW_MASTER_PID" ]; then
        echo "Error: Master pid has changed, so the cluster has been restarted."
        exit 1
      fi
      # Trigger gpexpand again after ICW.
      # Some fixups are needed to bypass known failures.
      time bypass_known_expand_failures
      time expand_cluster 3 4
    fi
}

_main "$@"
