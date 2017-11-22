#!/bin/bash

set -xeu
set -o pipefail

function build_gpbackup() {
    pushd gpdb_src/depends
    conan remote add gpdb-oss  https://api.bintray.com/conan/greenplum-db/gpdb-oss
    conan install -f conanfile_gpbackup.txt --build=missing
    popd
}

function add_to_tarball() {
    local cwd=$(pwd)
    gunzip gpdb_artifacts/*.tar.gz
    mv gpdb_artifacts/*.tar gpdb_final
    pushd gpdb_src/depends/gpbackup
    tar -f ${cwd}/gpdb_final/*.tar -r bin/*
    popd
    pushd gpdb_final
    gzip *.tar
    popd
}

function main() {
    build_gpbackup
    add_to_tarball
}

main
