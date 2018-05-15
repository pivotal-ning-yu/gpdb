#!/bin/bash

output_body_file=staged_on_pivnet_email/body
output_subject_file=staged_on_pivnet_email/subject

CURR_TAG=$(cd gpdb_src && git describe --abbrev=0 --tags HEAD)

echo -e "ATTN: Greenplum ${CURR_TAG} is staged on PivNet" > $output_subject_file

cat <<EOF > $output_body_file
Howdy Folks,

Greenplum ${CURR_TAG} is now on PivNet as Admin Only.

Please check to make sure that your components are part of the release and if
they are missing please manually add them into the release.

@PM's When you're satisfied the release is ready, please make it public.
EOF
