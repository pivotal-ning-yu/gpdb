-- start_matchsubs
-- m/^.*-/
-- s/^.*-//
-- end_matchsubs

\! echo 'EXPANSION_PREPARE_STARTED:<path> to inputfile' > $MASTER_DATA_DIRECTORY/gpexpand.status
\! gpcheckcat
\! gpcheck -h `hostname`
\! gpconfig -c gp_resource_manager -v group
\! gppkg
\! rm $MASTER_DATA_DIRECTORY/gpexpand.status
