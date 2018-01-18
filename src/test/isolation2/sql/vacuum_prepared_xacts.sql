SET debug_dtm_action = "fail_begin_command";
SET debug_dtm_action_target = "protocol";
SET debug_dtm_action_protocol = "commit_prepared";
set debug_dtm_action_segment = 0;
vacuum pg_depend;
RESET debug_dtm_action;
RESET debug_dtm_action_target;
RESET debug_dtm_action_protocol;
2U: select * from pg_prepared_xacts;
