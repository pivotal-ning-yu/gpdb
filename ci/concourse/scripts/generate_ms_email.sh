#!/bin/bash

output_body_file=ms_email/body
output_subject_file=ms_email/subject

CURR_TAG=$(cd gpdb_src && git describe --abbrev=0 --tags HEAD)

echo -e "ATTN: Greenplum ${CURR_TAG} is staged for MorganStanley on the EMC FTP drop site" > $output_subject_file

cat <<EOF > $output_body_file
Howdy Folks,

Greenplum ${CURR_TAG} has been pushed to the EMC FTP drop site.

ftp://ftp.emc.com/patches/${CURR_TAG}

EOF
