# ==== DELETE ====
delete_api()         { sql_exec "DELETE FROM api WHERE id=$1;"; }
delete_header()      { sql_exec "DELETE FROM headers WHERE id=$1;"; }
delete_param()       { sql_exec "DELETE FROM params WHERE id=$1;"; }
delete_cookie()      { sql_exec "DELETE FROM cookies WHERE id=$1;"; }
delete_auth()        { sql_exec "DELETE FROM auth WHERE id=$1;"; }
delete_request()     { sql_exec "DELETE FROM requests WHERE id=$1;"; }
delete_response()    { sql_exec "DELETE FROM responses WHERE id=$1;"; }
delete_log()         { sql_exec "DELETE FROM logs WHERE id=$1;"; }
delete_test_case()   { sql_exec "DELETE FROM test_cases WHERE id=$1;"; }
delete_environment() { sql_exec "DELETE FROM environments WHERE id=$1;"; }
