#!/bin/bash
set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SRCDIR=/home/gpadmin/gpdb_src

trap look4diffs ERR
function look4diffs() {

    diff_files=`find .. -name regression.diffs`

    for diff_file in ${diff_files}; do
	if [ -f "${diff_file}" ]; then
	    cat <<-FEOF

				======================================================================
				DIFF FILE: ${diff_file}
				----------------------------------------------------------------------

				$(cat "${diff_file}")

			FEOF
	fi
    done
    exit 1
}

source /usr/local/greenplum-db-devel/greenplum_path.sh
export PGPORT=5432
export MASTER_DATA_DIRECTORY=/data/gpdata/master/gpseg-1
gpstop -a
unset PGPORT
unset MASTER_DATA_DIRECTORY

NEW_SRC_DIR=/data/gpdata/gpdb_src
cp -r ${SRCDIR} ${NEW_SRC_DIR}

cd ${NEW_SRC_DIR}
./configure --prefix=/usr/local/greenplum-db-devel --with-python --disable-orca --without-readline --without-zlib --disable-gpfdist --without-libcurl --disable-pxf --without-libbz2

export DEFAULT_QD_MAX_CONNECT=150
export STATEMENT_MEM=250MB
pushd gpAux/gpdemo
make create-demo-cluster
popd
source gpAux/gpdemo/gpdemo-env.sh

make -C ${NEW_SRC_DIR}/src/test/regress

make PGOPTIONS="-c optimizer=${OPTIMIZER}" installcheck-world CC=gcc CXX=g++
