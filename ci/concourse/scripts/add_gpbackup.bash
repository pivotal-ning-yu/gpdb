#!/bin/bash

set -xeu
set -o pipefail

function build_gpbackup() {
    pushd gpdb_src/depends
    conan remote add gpdb-oss  https://api.bintray.com/conan/greenplum-db/gpdb-oss
    conan install --build=missing conanfile_gpbackup.txt 
    popd
}

function add_to_tarball() {
    local cwd=$(pwd)
    gunzip gpdb_artifacts/*.tar.gz
    mv gpdb_artifacts/bin_gpdb.tar gpdb_final
    pushd gpdb_src/depends/gpbackup
    tar -f ${cwd}/gpdb_final/bin_gpdb.tar -r bin/*
    popd
    pushd gpdb_final
    gzip bin_gpdb.tar
    popd
}

function main() {
    build_gpbackup
    add_to_tarball
}

main
