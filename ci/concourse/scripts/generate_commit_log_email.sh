#!/bin/bash

output_body_file=commit_log_email/body
output_subject_file=commit_log_email/subject

# This assumes that the pipeline is checking out the tag, not HEAD
PREV_TAG=$(cd gpdb_src && git describe --abbrev=0 --tags HEAD~1)
CURR_TAG=$(cd gpdb_src && git describe --abbrev=0 --tags HEAD)
NUM_COMMITS=$(cd gpdb_src && git log --pretty=oneline ${PREV_TAG}..HEAD | wc -l)

echo -e "ATTN: New Greenplum 4 release from ${PREV_TAG} to ${CURR_TAG} - Automated Email from 4.3-release pipeline" > $output_subject_file

cat <<EOF > $output_body_file
This is an automated email from the GPDB 4.3-release pipeline.  The link below
will take you to Github's pretty comparison page.  This page will show all of
the commits between the tag ${PREV_TAG} and ${CURR_TAG}.

https://github.com/greenplum-db/gpdb4/compare/${PREV_TAG}...${CURR_TAG}

EOF

if  [[ NUM_COMMITS -gt 250 ]]; then
cat <<EOF >> $output_body_file
This view is only valid for the first 250 commits.  There are ${NUM_COMMITS}
commits, and Github's website will not display them all, therefore we are
appending all of the commits and their messages to the end of this email.

If you have access to the repo, you can also access these messages on your own box.

    $ cd [your gpdb_src directory] && git fetch
    $ git checkout ${CURR_TAG}
    $ git log --pretty=oneline ${PREV_TAG}..${CURR_TAG}
    or
    $ git log ${PREV_TAG}..${CURR_TAG}

===== GIT LOG from ${PREV_TAG}..${CURR_TAG} below =====

EOF

(cd gpdb_src && git log ${PREV_TAG}..HEAD) >> $output_body_file

fi
