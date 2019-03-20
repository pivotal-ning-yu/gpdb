#!/bin/bash -l
set -exo pipefail

GREENPLUM_INSTALL_DIR=/usr/local/greenplum-db-devel
export GPDB_ARTIFACTS_DIR=$(pwd)/${OUTPUT_ARTIFACT_DIR}
CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GPDB_SRC_PATH=${GPDB_SRC_PATH:=gpdb_src}

GPDB_BIN_FILENAME=${GPDB_BIN_FILENAME:="bin_gpdb.tar.gz"}
GREENPLUM_CL_INSTALL_DIR=/usr/local/greenplum-clients-devel
GPDB_CL_FILENAME=${GPDB_CL_FILENAME:="gpdb-clients-${TARGET_OS}${TARGET_OS_VERSION}.tar.gz"}

function expand_glob_ensure_exists() {
  local -a glob=($*)
  [ -e "${glob[0]}" ]
  echo "${glob[0]}"
}

function prep_env_for_centos() {
  case "${TARGET_OS_VERSION}" in
    6|7) BLD_ARCH=rhel${TARGET_OS_VERSION}_x86_64 ;;
    *) echo "TARGET_OS_VERSION not set or recognized for Centos/RHEL" ; exit 1 ;;
  esac
}

function install_deps_for_centos() {
  # quicklz is proprietary code that we cannot put in our public Docker images.
  rpm -i libquicklz-installer/libquicklz-*.rpm
  rpm -i libquicklz-devel-installer/libquicklz-*.rpm
  # install libsigar from tar.gz
  tar zxf libsigar-installer/sigar-*.targz -C gpdb_src/gpAux/ext
}

function link_tools_for_centos() {
  tar xf python-tarball/python-*.tar.gz -C $(pwd)/${GPDB_SRC_PATH}/gpAux/ext
  ln -sf $(pwd)/${GPDB_SRC_PATH}/gpAux/ext/${BLD_ARCH}/python-2.7.12 /opt/python-2.7.12
}

function prep_env_for_sles() {
  export JAVA_HOME=$(expand_glob_ensure_exists /usr/java/jdk1.7*)
  export PATH=${JAVA_HOME}/bin:${PATH}
  source /opt/gcc_env.sh
}

function rebase_master_branch() {
  pushd ${GPDB_SRC_PATH}
    git config user.email "gpdb@localhost"
    git config user.name "Gpdb Hackers"
    git remote add upstream https://github.com/greenplum-db/gpdb.git
    git fetch upstream
    git rebase upstream/master
  popd
}

function generate_build_number() {
  pushd ${GPDB_SRC_PATH}
    #Only if its git repro, add commit SHA as build number
    # BUILD_NUMBER file is used by getversion file in GPDB to append to version
    if [ -d .git ] ; then
      echo "commit:`git rev-parse upstream/master`" > BUILD_NUMBER
    fi
  popd
}

function link_tools_for_sles() {
  ln -sf "$(expand_glob_ensure_exists $(pwd)/${GPDB_SRC_PATH}/gpAux/ext/*/python-2.7.12 )" /opt
}

function build_gpdb() {
  pushd ${GPDB_SRC_PATH}/gpAux
    # Use -j4 to speed up the build. (Doesn't seem worth trying to guess a better
    # value based on number of CPUs or anything like that. Going above -j4 wouldn't
    # make it much faster, and -j4 is small enough to not hurt too badly even on
    # a single-CPU system
    if [ -n "$1" ]; then
      make "$1" GPROOT=/usr/local PARALLEL_MAKE_OPTS=-j4 -s dist
    else
      make GPROOT=/usr/local PARALLEL_MAKE_OPTS=-j4 -s dist
    fi
  popd
}

function build_gppkg() {
  pushd ${GPDB_SRC_PATH}/gpAux
    make gppkg BLD_TARGETS="gppkg" INSTLOC="${GREENPLUM_INSTALL_DIR}" GPPKGINSTLOC="${GPDB_ARTIFACTS_DIR}" RELENGTOOLS=/opt/releng/tools
  popd
}

function git_info() {
  pushd ${GPDB_SRC_PATH}

  "${CWDIR}/git_info.bash" | tee ${GREENPLUM_INSTALL_DIR}/etc/git-info.json

  PREV_TAG=$(git describe --tags --abbrev=0 upstream/master^)

  cat > ${GREENPLUM_INSTALL_DIR}/etc/git-current-changelog.txt <<-EOF
	======================================================================
	Git log since previous release tag (${PREV_TAG})
	----------------------------------------------------------------------

	EOF

  git log --abbrev-commit --date=relative "${PREV_TAG}..upstream/master" >> ${GREENPLUM_INSTALL_DIR}/etc/git-current-changelog.txt

  popd
}

function unittest_check_gpdb() {
  pushd ${GPDB_SRC_PATH}
    source ${GREENPLUM_INSTALL_DIR}/greenplum_path.sh
    make GPROOT=/usr/local -s unittest-check
  popd
}

function include_zstd() {
  pushd ${GREENPLUM_INSTALL_DIR}
    if [ "${TARGET_OS}" == "centos" ] ; then
      cp /usr/lib64/pkgconfig/libzstd.pc lib/pkgconfig
      cp /usr/lib64/libzstd.so* lib
      cp /usr/include/zstd*.h include
    fi
  popd
}

function include_quicklz() {
  pushd ${GREENPLUM_INSTALL_DIR}
    if [ "${TARGET_OS}" == "centos" ] ; then
      cp /usr/lib64/libquicklz.so* lib
    fi
  popd
}

function include_libstdcxx() {
  pushd /opt/gcc-6*/lib64
    if [ "${TARGET_OS}" == "centos" ] ; then
      for libfile in libstdc++.so.*; do
        case $libfile in
          *.py)
            ;; # we don't vendor libstdc++.so.*-gdb.py
          *)
            cp "$libfile" ${GREENPLUM_INSTALL_DIR}/lib
            ;; # vendor everything else
        esac
      done
    fi
  popd
}

function export_gpdb() {
  TARBALL="${GPDB_ARTIFACTS_DIR}/${GPDB_BIN_FILENAME}"
  pushd ${GREENPLUM_INSTALL_DIR}
    source greenplum_path.sh
    python -m compileall -q -x test .
    chmod -R 755 .
    tar -czf "${TARBALL}" ./*
  popd
}

function export_gpdb_extensions() {
  pushd ${GPDB_SRC_PATH}/gpAux
    if ls greenplum-*zip* 1>/dev/null 2>&1; then
      chmod 755 greenplum-*zip*
      cp greenplum-*zip* "${GPDB_ARTIFACTS_DIR}/"
    fi
    if ls "$GPDB_ARTIFACTS_DIR"/*.gppkg 1>/dev/null 2>&1; then
      chmod 755 "$GPDB_ARTIFACTS_DIR"/*.gppkg
    fi
  popd
}

function export_gpdb_win32_ccl() {
    pushd ${GPDB_SRC_PATH}/gpAux
    if [ -f "$(find . -maxdepth 1 -name 'greenplum-*.msi' -print -quit)" ] ; then
        cp greenplum-*.msi "${GPDB_ARTIFACTS_DIR}/"
    fi
    popd
}

function export_gpdb_clients() {
  TARBALL="${GPDB_ARTIFACTS_DIR}/${GPDB_CL_FILENAME}"
  pushd ${GREENPLUM_CL_INSTALL_DIR}
    source ./greenplum_clients_path.sh
    python -m compileall -q -x test .
    chmod -R 755 .
    tar -czf "${TARBALL}" ./*
  popd
}

function _main() {
  # Copy input ext dir; assuming ext doesnt exist
  mv gpAux_ext/ext ${GPDB_SRC_PATH}/gpAux

  case "${TARGET_OS}" in
    centos)
      prep_env_for_centos
      install_deps_for_centos
      link_tools_for_centos
      ;;
    sles)
      prep_env_for_sles
      link_tools_for_sles
      ;;
    win32)
        export BLD_ARCH=win32
        CONFIGURE_FLAGS="${CONFIGURE_FLAGS} --disable-pxf"
        ;;
    *)
        echo "only centos, sles and win32 are supported TARGET_OS'es"
        false
        ;;
  esac

  rebase_master_branch
  generate_build_number

  # By default, only GPDB Server binary is build.
  # Use BLD_TARGETS flag with appropriate value string to generate client, loaders
  # connectors binaries
  if [ -n "${BLD_TARGETS}" ]; then
    BLD_TARGET_OPTION=("BLD_TARGETS=\"$BLD_TARGETS\"")
  else
    BLD_TARGET_OPTION=("")
  fi

  export CONFIGURE_FLAGS=${CONFIGURE_FLAGS}

  build_gpdb "${BLD_TARGET_OPTION[@]}"
  git_info
  build_gppkg
  if [ "${TARGET_OS}" != "win32" ] ; then
      # Don't unit test when cross compiling. Tests don't build because they
      # require `./configure --with-zlib`.
      unittest_check_gpdb
  fi
  include_zstd
  include_quicklz
  include_libstdcxx
  export_gpdb
  export_gpdb_extensions
  export_gpdb_win32_ccl

  if echo "${BLD_TARGETS}" | grep -qwi "clients"
  then
      export_gpdb_clients
  fi
}

_main "$@"
