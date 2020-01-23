#!/bin/bash -l
set -exo pipefail

CONCURRENCY="--jobs=8 --load-average=16"
GREENPLUM_INSTALL_DIR=/usr/local/greenplum-db-devel
export GPDB_ARTIFACTS_DIR
GPDB_ARTIFACTS_DIR=$(pwd)/$OUTPUT_ARTIFACT_DIR
GPDB_SRC_PATH=${GPDB_SRC_PATH:=gpdb_src}

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"

function prep_env_for_sles() {
  BLDARCH=sles11_x86_64
  ln -sf "$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/python-2.6.9" /opt
  export JAVA_HOME=/usr/lib64/jvm/java-1.6.0-openjdk-1.6.0
  export PATH=${JAVA_HOME}/bin:${PATH}
  source /opt/gcc_env.sh
}

function build_gpdb() {
  pushd gpdb_src/gpAux
    if [ -n "$1" ]; then
      make $CONCURRENCY "$1" GPROOT=/usr/local dist
    else
      make $CONCURRENCY GPROOT=/usr/local dist
    fi
  popd
}

function build_gppkg() {
  pushd gpdb_src/gpAux
    make $CONCURRENCY gppkg BLD_TARGETS="gppkg" INSTLOC="$GREENPLUM_INSTALL_DIR" GPPKGINSTLOC="$GPDB_ARTIFACTS_DIR" RELENGTOOLS=/opt/releng/tools
  popd
}

function unittest_check_gpdb() {
  pushd gpdb_src/gpAux
    source $GREENPLUM_INSTALL_DIR/greenplum_path.sh
    make $CONCURRENCY GPROOT=/usr/local unittest-check
  popd
}

function export_gpdb() {
  TARBALL="$GPDB_ARTIFACTS_DIR"/bin_gpdb.tar.gz
  pushd $GREENPLUM_INSTALL_DIR
    source greenplum_path.sh
    python -m compileall -x test .
    chmod -R 755 .
    tar -czf "${TARBALL}" ./*
  popd
}

function export_gpdb_extensions() {
  pushd gpdb_src/gpAux
    if ls greenplum-*zip* >/dev/null 2>&1 ; then
      chmod 755 greenplum-*zip*
      cp greenplum-*zip* "$GPDB_ARTIFACTS_DIR"/
    fi
    if ls "$GPDB_ARTIFACTS_DIR"/*.gppkg >/dev/null 2>&1 ; then
      chmod 755 "$GPDB_ARTIFACTS_DIR"/*.gppkg
    fi
  popd
}

function export_gpdb_win32_ccl() {
  pushd gpdb_src/gpAux
    if [ -f "$(find . -maxdepth 1 -name 'greenplum-*.msi' -print -quit)" ] ; then
      cp greenplum-*.msi "$GPDB_ARTIFACTS_DIR"/
    fi
  popd
}

function export_ccache() {
  [ -d ccache ] || return 0
  TARBALL="$GPDB_ARTIFACTS_DIR"/ccache_gpdb.tar.gz
  print_ccache_stats
  tar -czf $TARBALL ccache
}

function _main() {
  case "$TARGET_OS" in
    centos)
      prep_env_for_centos
      ;;
    sles)
      prep_env_for_sles
      ;;
    win32)
      export BLD_ARCH=win32
      ;;
    *)
      echo "only centos, sles and win32 are supported TARGET_OS'es"
      false
      ;;
  esac

  # Copy input ext dir; assuming ext doesnt exist
  mv gpAux_ext/ext ${GPDB_SRC_PATH}/gpAux
  tar_sync_tools

  # Copy .ant dir
  mv gphdfs_dist/.ant /root/
  mkdir -p ${GPDB_SRC_PATH}/gpAux/extensions/gphdfs/dist
  mv gphdfs_dist/dist/*.jar ${GPDB_SRC_PATH}/gpAux/extensions/gphdfs/dist/
  mv gphdfs_dist/dist/*.tar ${GPDB_SRC_PATH}/gpAux/extensions/gphdfs/

  prep_ccache

  # By default, only GPDB Server binary is build.
  # Use BLD_TARGETS flag with appropriate value string to generate client, loaders
  # connectors binaries
  if [ -n "$BLD_TARGETS" ]; then
    BLD_TARGET_OPTION=("BLD_TARGETS=\"$BLD_TARGETS\"")
  else
    BLD_TARGET_OPTION=("")
  fi
  build_gpdb "${BLD_TARGET_OPTION[@]}"
  build_gppkg
  if [ "$TARGET_OS" != "win32" ] ; then
    # Don't unit test when cross compiling. Tests don't build because they
    # require `./configure --with-zlib`.
    unittest_check_gpdb
  fi
  export_gpdb
  export_gpdb_extensions
  export_gpdb_win32_ccl
  export_ccache
}

_main "$@"
