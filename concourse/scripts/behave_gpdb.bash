#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"

function gen_env(){
    cat > /opt/run_test.sh <<-EOF
		set -ex

		source /usr/local/greenplum-db-devel/greenplum_path.sh

		cd "\${1}/gpdb_src/gpAux"
		source gpdemo/gpdemo-env.sh

		cd "\${1}/gpdb_src/gpMgmt/"
		BEHAVE_TAGS="${BEHAVE_TAGS}"
		BEHAVE_FLAGS="${BEHAVE_FLAGS}"
		if [ ! -z "\${BEHAVE_TAGS}" ]; then
		    make -f Makefile.behave behave tags=\${BEHAVE_TAGS}
		else
		    flags="\${BEHAVE_FLAGS}" make -f Makefile.behave behave
		fi
	EOF

    chmod a+x /opt/run_test.sh
}

function _main() {

    if [ -z "${BEHAVE_TAGS}" ] && [ -z "${BEHAVE_FLAGS}" ]; then
        echo "FATAL: BEHAVE_TAGS or BEHAVE_FLAGS not set"
        exit 1
    fi

    time install_gpdb
    time ./gpdb_src/concourse/scripts/setup_gpadmin_user.bash

	# TEST_OS might not be set for this script, load it from os-release
	: ${TEST_OS:=$(. /etc/os-release; echo $ID)}

    # install libuv for ic-proxy
    case "${TEST_OS}" in
      centos)
        yum install -y epel-release
        yum install -y libuv-devel
        ;;
      ubuntu)
        apt-get update
        apt-get install -y libuv1-dev

        # set it to y to install the debug symbols of libuv
        install_dbgsym=

        if [ "$install_dbgsym" = y ]; then
          apt-get install -y ubuntu-dbgsym-keyring

          . /etc/os-release
          cat >/etc/apt/sources.list.d/ddebs.list <<EOF
deb http://ddebs.ubuntu.com $UBUNTU_CODENAME main restricted universe multiverse
deb http://ddebs.ubuntu.com $UBUNTU_CODENAME-updates main restricted universe multiverse
deb http://ddebs.ubuntu.com $UBUNTU_CODENAME-proposed main restricted universe multiverse
EOF

          apt-get update
          apt-get install -y libuv1-dbgsym
        fi
        ;;
    esac

    # Run inside a subshell so it does not pollute the environment after
    # sourcing greenplum_path
    time (make_cluster)

    time install_python_requirements_on_single_host ./gpdb_src/gpMgmt/requirements-dev.txt

    time gen_env

    # need to run setup_coverage as gpadmin due to scp and ssh commands
    time su gpadmin -c "
        source ./gpdb_src/concourse/scripts/common.bash
        # setup hostfile_all for demo_cluster tests
        echo localhost > /tmp/hostfile_all
        setup_coverage ./gpdb_src
    "

    time run_test

    # collect coverage
    cp -r /tmp/coverage/* ./coverage/
    time tar_coverage "${TEST_NAME}_demo"
}

_main "$@"
