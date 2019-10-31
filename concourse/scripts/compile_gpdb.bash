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

function prep_env() {
  case "${TARGET_OS}" in
  centos)
    case "${TARGET_OS_VERSION}" in
    6 | 7) BLD_ARCH=rhel${TARGET_OS_VERSION}_x86_64 ;;
    *)
      echo "TARGET_OS_VERSION not set or recognized for Centos/RHEL"
      exit 1
      ;;
    esac
    ;;
  ubuntu)
    case "${TARGET_OS_VERSION}" in
    18.04) BLD_ARCH=ubuntu18.04_x86_64 ;;
    *)
      echo "TARGET_OS_VERSION not set or recognized for Ubuntu"
      exit 1
      ;;
    esac
    ;;
  esac
}

function install_deps_for_centos() {
  rpm -i libquicklz-installer/libquicklz-*.rpm
  rpm -i libquicklz-devel-installer/libquicklz-*.rpm
}

function install_deps_for_ubuntu() {
  dpkg --install libquicklz-installer/libquicklz-*.deb
}

function install_deps() {
  case "${TARGET_OS}" in
    centos) install_deps_for_centos;;
    ubuntu) install_deps_for_ubuntu;;
  esac
}

function link_python() {
  tar xf python-tarball/python-*.tar.gz -C $(pwd)/${GPDB_SRC_PATH}/gpAux/ext
  ln -sf $(pwd)/${GPDB_SRC_PATH}/gpAux/ext/${BLD_ARCH}/python-2.7.12 /opt/python-2.7.12
}

function generate_build_number() {
  pushd ${GPDB_SRC_PATH}
    #Only if its git repro, add commit SHA as build number
    # BUILD_NUMBER file is used by getversion file in GPDB to append to version
    if [ -d .git ] ; then
      echo "commit:`git rev-parse HEAD`" > BUILD_NUMBER
    fi
  popd
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

function git_info() {
  pushd ${GPDB_SRC_PATH}

  "${CWDIR}/git_info.bash" | tee ${GREENPLUM_INSTALL_DIR}/etc/git-info.json

  PREV_TAG=$(git describe --tags --abbrev=0 HEAD^)

  cat > ${GREENPLUM_INSTALL_DIR}/etc/git-current-changelog.txt <<-EOF
	======================================================================
	Git log since previous release tag (${PREV_TAG})
	----------------------------------------------------------------------

	EOF

  git log --abbrev-commit --date=relative "${PREV_TAG}..HEAD" >> ${GREENPLUM_INSTALL_DIR}/etc/git-current-changelog.txt

  popd
}

function unittest_check_gpdb() {
  pushd ${GPDB_SRC_PATH}
    source ${GREENPLUM_INSTALL_DIR}/greenplum_path.sh
    make GPROOT=/usr/local -s unittest-check
  popd
}

function include_zstd() {
  local libdir
  case "${TARGET_OS}" in
    centos) libdir=/usr/lib64 ;;
    ubuntu) libdir=/usr/lib ;;
    *) return ;;
  esac
  pushd ${GREENPLUM_INSTALL_DIR}
    cp ${libdir}/pkgconfig/libzstd.pc lib/pkgconfig
    cp -d ${libdir}/libzstd.so* lib
    cp /usr/include/zstd*.h include
  popd
}

function include_quicklz() {
  local libdir
  case "${TARGET_OS}" in
    centos) libdir=/usr/lib64 ;;
    ubuntu) libdir=/usr/local/lib ;;
    *) return ;;
  esac
  pushd ${GREENPLUM_INSTALL_DIR}
    cp -d ${libdir}/libquicklz.so* lib
  popd
}

function include_libstdcxx() {
  if [ "${TARGET_OS}" == "centos" ] ; then
    pushd /opt/gcc-6*/lib64
      for libfile in libstdc++.so.*; do
        case $libfile in
          *.py)
            ;; # we don't vendor libstdc++.so.*-gdb.py
          *)
            cp -d "$libfile" ${GREENPLUM_INSTALL_DIR}/lib
            ;; # vendor everything else
        esac
      done
    popd
  fi

}

function export_gpdb() {
  TARBALL="${GPDB_ARTIFACTS_DIR}/${GPDB_BIN_FILENAME}"
  local server_version
  server_version="$("${GPDB_SRC_PATH}"/getversion --short)"

  local server_build
  server_build="${GPDB_ARTIFACTS_DIR}/server-build-${server_version}-${BLD_ARCH}${RC_BUILD_TYPE_GCS}.tar.gz"

  pushd ${GREENPLUM_INSTALL_DIR}
    source greenplum_path.sh
    python -m compileall -q -x test .
    chmod -R 755 .
    tar -czf "${TARBALL}" ./*
  popd

  cp "${TARBALL}" "${server_build}"
}

function export_gpdb_extensions() {
  pushd ${GPDB_SRC_PATH}/gpAux
    if ls greenplum-*zip* 1>/dev/null 2>&1; then
      chmod 755 greenplum-*zip*
      cp greenplum-*zip* "${GPDB_ARTIFACTS_DIR}/"
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
    mkdir -p bin/ext/gppylib
    cp ${GREENPLUM_INSTALL_DIR}/lib/python/gppylib/__init__.py ./bin/ext/gppylib
    cp  ${GREENPLUM_INSTALL_DIR}/lib/python/gppylib/gpversion.py ./bin/ext/gppylib
    chmod -R 755 .
    tar -czf "${TARBALL}" ./*
  popd
}

function fetch_orca_src {
  local orca_tag="${1}"

  mkdir orca_src
  wget --quiet --output-document=- "https://github.com/greenplum-db/gporca/archive/${orca_tag}.tar.gz" \
    | tar xzf - --strip-components=1 --directory=orca_src
}

function build_xerces()
{
    OUTPUT_DIR="gpdb_src/gpAux/ext/${BLD_ARCH}"
    mkdir -p xerces_patch/concourse
    cp -r orca_src/concourse/xerces-c xerces_patch/concourse
    cp -r orca_src/patches/ xerces_patch
    /usr/bin/python xerces_patch/concourse/xerces-c/build_xerces.py --output_dir=${OUTPUT_DIR}
    rm -rf build
}

function build_and_test_orca()
{
    OUTPUT_DIR="gpdb_src/gpAux/ext/${BLD_ARCH}"
    orca_src/concourse/build_and_test.py --build_type=RelWithDebInfo --output_dir=${OUTPUT_DIR}
}

function dump_coverage_html()
{
  sed -r \
      -e '\,<img src="(amber|emerald|snow|ruby).png"[^>]*>,d' \
      -e '\,^ {6}(<td class="coverBar"|</td>),d' \
      -e 's,alt="[^"]*",,g' \
      -e 's,(class="tableHead" colspan)=3,\1=2,' \
  | w3m -T text/html -cols 160 -dump
}

#function report_coverage()
#{
#  local name="$1"
#  local detail="$2"
#  local filename="${name//\//.}"
#
#  #if [ -z "$COVERAGE_FLAGS" ]; then
#  #  return 0
#  #fi
#
#  mkdir -p /tmp/coverage/
#
#  # TODO: make coverage-html, then generate report
#  pushd ${GPDB_SRC_PATH}
#    echo "[coverage] generating coverage report after $name..."
#    #make coverage-clean
#    make coverage-html >/tmp/coverage/"$filename".log 2>&1
#
#    echo "[coverage] brief coverage after test $name:"
#    tail -n3 /tmp/coverage/"$filename".log
#
#    if [ "$detail" = "detail" ]; then
#      echo "[coverage] detailed coverage report after $name:"
#      dump_coverage_html \
#        < coverage/index-sort-l.html \
#        | tee /tmp/coverage/"$filename".html
#    fi
#  popd
#}

function report_coverage()
{
  local name="$1"
  local detail="$2"
  local testname="${name//\//.}"

  mkdir -p /tmp/coverage/

  set +x
  pushd ${GPDB_SRC_PATH}
    echo "[coverage] generating coverage report after $name ..."
    make coverage-html >/tmp/coverage/"$testname".log 2>&1
    tail -n3 /tmp/coverage/"$testname".log

    echo "[coverage] sorting coverage report after $name ..."
    find */ -name '*.gcov.out' \
    | while read -r fullname; do
        dirname="$(dirname "$fullname")"
        # TODO: filter out the dirs that are not interesting
        # srcname can be name.c or name_srv.c, both refer to name.c
        srcname="$(basename "$fullname" .gcov.out)"
        # find out the real srcname by removing the _srv part
        srcname="${srcname/_srv\./.}"
        # covline: Lines executed:100.00% of 242
        covline="$(grep -F -x -m1 -A1 "File '$srcname'" "$fullname" \
                   | tail -n+2)" || continue
        coverage="${covline#*:}"
        coverage="${coverage%\%*}"
        [ -n "$coverage" ] || continue
        nlines="${covline##* }"
        printf "%6.2f %% of %6d lines of %s/%s\n" \
               "$coverage" "$nlines" "$dirname" "$srcname"
      done \
    | sort -u -k1n,1 -k4nr,4
  popd
  set -x
}

function report_regression_diffs()
{
  find "$1" -name regression.diffs \
  | while read -r diff_file; do
      cat <<EOF

======================================================================
DIFF FILE: ${diff_file}
----------------------------------------------------------------------

EOF
      cat "${diff_file}"
    done
}

function install_coverage_depends()
{
  if [ -z "$COVERAGE_FLAGS" ]; then
    return 0
  fi

  case "${TARGET_OS}" in
    centos)
      yum install -y epel-release
      yum install -y lcov \
        openssh-server net-tools iproute w3m \
        perl-Env
      ;;
    ubuntu)
      apt-get update
      apt-get install -y lcov \
        openssh-server iputils-ping net-tools iproute2 locales locales-all w3m
      ;;
    *)
      echo "only centos and ubuntu are supported TARGET_OS'es"
      return 1
      ;;
  esac

  return 0
}

function gen_env()
{
  cat > /opt/run_test.sh <<EOF
    export PGOPTIONS="$PGOPTIONS"
    MAKE_TEST_COMMAND="$MAKE_TEST_COMMAND"

EOF

  cat >> /opt/run_test.sh <<"EOF"
#    trap look4diffs ERR
#
#    function look4diffs()
#    {
#      find .. -name regression.diffs \
#      | while read -r diff_file; do
#          cat <<FEOF
#
#======================================================================
#DIFF FILE: ${diff_file}
#----------------------------------------------------------------------
#
#FEOF
#          cat "${diff_file}"
#        done
#
#      exit 1
#    }

    source /usr/local/greenplum-db-devel/greenplum_path.sh

    if [ -f /opt/gcc_env.sh ]; then
      source /opt/gcc_env.sh
    fi

    cd "${1}/gpdb_src"
    source gpAux/gpdemo/gpdemo-env.sh
    make ${MAKE_TEST_COMMAND}
EOF

  chmod a+x /opt/run_test.sh
}

function run_coverage_tests()
{
  if [ -z "$COVERAGE_FLAGS" ]; then
    return 0
  fi
  if [[ "${TARGET_OS}" != @(ubuntu|centos) ]] ; then
    return 0
  fi

  source "${CWDIR}/common.bash"

  ./gpdb_src/concourse/scripts/setup_gpadmin_user.bash "$TEST_OS"

  chown -R gpadmin:gpadmin gpdb_src

  time make_cluster

  # report directly after compilation and unit tests
  report_coverage unittest

  # to generate coverage report we run ICW tests directly after the compilation
  # FIXME: for testing purpose we only run a small subset of tests
  #export PGOPTIONS='-c optimizer=off'
  #for dir in src/test/regress src/test/isolation2 src/test/walrep; do
  #  export MAKE_TEST_COMMAND="-C $dir installcheck"
  #  time gen_env
  #  time run_test || : #|| ( report_coverage $dir detail; exit 0 )
  #done

  export PGOPTIONS='-c optimizer=off'
  export MAKE_TEST_COMMAND="installcheck-world"
  time gen_env
  time run_test || : #|| ( report_coverage $dir detail; exit 0 )

  # dump regression.diffs
  report_regression_diffs gpdb_src

  # generate coverage report
  report_coverage ICW detail

  # TODO: how to run tests with other PGOPTIONS?
  #export PGOPTIONS='-c gp_interconnect_type=tcp -c optimizer=off'

  # XXX: below is the command to run replication_slots behave tests
  #make -C gpMgmt -f Makefile.behave behave flags="--tags=replication_slots --tags=~concourse_cluster,demo_cluster"

  # FIXME: only fail on low-coverage files
  exit 1
}

function _main() {
  mkdir gpdb_src/gpAux/ext

  case "${TARGET_OS}" in
    centos|ubuntu)
      prep_env
      fetch_orca_src "${ORCA_TAG}"
      build_xerces
      build_and_test_orca
      install_deps
      link_python
      ;;
    win32)
        export BLD_ARCH=win32
        CONFIGURE_FLAGS="${CONFIGURE_FLAGS} ${COVERAGE_FLAGS} --disable-pxf"
        ;;
    *)
        echo "only centos, ubuntu, and win32 are supported TARGET_OS'es"
        false
        ;;
  esac

  generate_build_number

  # By default, only GPDB Server binary is build.
  # Use BLD_TARGETS flag with appropriate value string to generate client, loaders
  # connectors binaries
  if [ -n "${BLD_TARGETS}" ]; then
    BLD_TARGET_OPTION=("BLD_TARGETS=\"$BLD_TARGETS\"")
  else
    BLD_TARGET_OPTION=("")
  fi

  export CONFIGURE_FLAGS
  export COVERAGE_FLAGS

  install_coverage_depends

  build_gpdb "${BLD_TARGET_OPTION[@]}"
  git_info

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

  run_coverage_tests
}

_main "$@"
