#!/bin/bash -l
set -exo pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

move_artifacts() {
  mkdir -p artifacts
  cp -v bin_gpdb_db_ms/*.zip artifacts/
  cp -v bin_gpdb_clients_ms/*.zip artifacts/
}

generate_md5_checksums() {
  pushd artifacts
  md5sum * > checksums.md5
  cat checksums.md5
  popd
}

determine_version() {
  pushd artifacts
  FTP_DIRECTORY=$(ls -c1 greenplum-db-*.zip |  sed 's/greenplum-db-\(.*\)-rhel.*/\1/')
  export FTP_DIRECTORY
  popd
}

upload_to_ftp() {
  pushd artifacts
  $CWDIR/ftp_directory.exp
  $CWDIR/ftp.exp
  sed 's/$/.fetched/g' checksums.md5 > checksums.md5.fetched
  md5sum -c checksums.md5.fetched
  popd
}

function _main() {
  yum -y install expect ftp
  move_artifacts
  generate_md5_checksums
  determine_version
  upload_to_ftp
}

_main "$@"