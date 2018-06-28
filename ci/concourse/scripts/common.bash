#!/bin/bash -l

## ----------------------------------------------------------------------
## General purpose functions
## ----------------------------------------------------------------------

function set_env() {
    export TERM=xterm-256color
    export TIMEFORMAT=$'\e[4;33mIt took %R seconds to complete this step\e[0m';
}

function print_ccache_stats() {
  case "$TARGET_OS" in
    centos|sles) ccache --show-stats ;;
  esac
}

function zero_ccache_stats() {
  case "$TARGET_OS" in
    centos|sles) ccache --zero-stats ;;
  esac
}

function prep_ccache() {
  export CCACHE_BASEDIR=$(pwd)/gpdb_src
  export CCACHE_DIR=$(pwd)/ccache
  if [ -d $(pwd)/ccache_snapshot ]; then
    tar -xf $(pwd)/ccache_snapshot/ccache_gpdb.tar.gz -C $(pwd)
  fi
  case "$TARGET_OS" in
    centos)
      export PATH="$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin:$PATH"
      ln -sf "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin/ccache" "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin/gcc"
      ln -sf "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin/ccache" "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin/g++"
      print_ccache_stats
      zero_ccache_stats
      ;;
    sles)
      export PATH="$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin:$PATH"
      ln -sf "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin/ccache" "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin/gcc"
      ln -sf "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin/ccache" "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/ccache/bin/g++"
      print_ccache_stats
      zero_ccache_stats
      ;;
    win32)
      echo "skipping ccache for win32"
      ;;
    *)
      echo "only centos and sles are supported TARGET_OS'es"
      false
      ;;
  esac
}

function prep_env_for_centos() {
  case "$TARGET_OS_VERSION" in
    5)
      BLDARCH=rhel5_x86_64
      export JAVA_HOME=/usr/lib/jvm/java-1.6.0-openjdk.x86_64
      source /opt/gcc_env.sh
      ;;

    6)
      BLDARCH=rhel6_x86_64
      export JAVA_HOME=/usr/lib/jvm/java-1.6.0-openjdk.x86_64
      ;;

    7)
      BLDARCH=rhel7_x86_64
      java7_packages=$(rpm -qa | grep -F java-1.7)
      java7_bin="$(rpm -ql $java7_packages | grep /jre/bin/java$)"
      alternatives --set java "$java7_bin"
      export JAVA_HOME="${java7_bin/jre\/bin\/java/}"
      ln -sf /usr/bin/xsubpp /usr/share/perl5/ExtUtils/xsubpp
      source /opt/gcc_env.sh
      ;;

    *)
    echo "TARGET_OS_VERSION not set or recognized for Centos/RHEL"
    exit 1
    ;;
  esac

  ln -sf "/$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/python-2.6.9" /opt/python-2.6.9
  export PATH=${JAVA_HOME}/bin:${PATH}
}

## ----------------------------------------------------------------------
## Test functions
## ----------------------------------------------------------------------

function install_gpdb() {
    [ ! -d /usr/local/greenplum-db-devel ] && mkdir -p /usr/local/greenplum-db-devel
    tar -xzf bin_gpdb/bin_gpdb.tar.gz -C /usr/local/greenplum-db-devel
}

function install_sync_tools() {
    tar -xzf sync_tools_gpdb/sync_tools_gpdb.tar.gz -C gpdb_src/gpAux
}

function tar_sync_tools() {
  pushd gpdb_src/gpAux
    tar -czf "$GPDB_ARTIFACTS_DIR/sync_tools_gpdb.tar.gz" ext
  popd
}

function configure() {
  source /opt/gcc_env.sh
  pushd gpdb_src/gpAux
      make INSTLOC=/usr/local/greenplum-db-devel $(cd .. && pwd)/GNUmakefile
  popd
}

function make_cluster() {
  source /usr/local/greenplum-db-devel/greenplum_path.sh
  workaround_before_concourse_stops_stripping_suid_bits
  pushd gpdb_src/gpAux/gpdemo
      su gpadmin -c make cluster
  popd
}

workaround_before_concourse_stops_stripping_suid_bits() {
  chmod u+s /bin/ping
}

function run_test() {
  ln -s "$(pwd)/gpdb_src/gpAux/ext/rhel5_x86_64/python-2.6.9" /opt
  su - gpadmin -c "bash /opt/run_test.sh $(pwd)"
}
