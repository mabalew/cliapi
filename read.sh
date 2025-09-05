# ==== READ ====
list_apis()         { sql_query "SELECT * FROM api ORDER BY id;"; }
get_api()           { sql_query "SELECT * FROM api WHERE id=$1;"; }

list_headers()      { sql_query "SELECT * FROM headers WHERE api_id=$1 ORDER BY id;"; }
get_header()        { sql_query "SELECT * FROM headers WHERE id=$1;"; }

list_params()       { sql_query "SELECT * FROM params WHERE api_id=$1 ORDER BY id;"; }
get_param()         { sql_query "SELECT * FROM params WHERE id=$1;"; }

list_cookies()      { sql_query "SELECT * FROM cookies WHERE api_id=$1 ORDER BY id;"; }
get_cookie()        { sql_query "SELECT * FROM cookies WHERE id=$1;"; }

list_auth()         { sql_query "SELECT * FROM auth WHERE api_id=$1 ORDER BY id;"; }
get_auth()          { sql_query "SELECT * FROM auth WHERE id=$1;"; }

list_requests()     { sql_query "SELECT * FROM requests WHERE api_id=$1 ORDER BY id;"; }
get_request()       { sql_query "SELECT * FROM requests WHERE id=$1;"; }

list_responses()    { sql_query "SELECT * FROM responses WHERE request_id=$1 ORDER BY id;"; }
get_response()      { sql_query "SELECT * FROM responses WHERE id=$1;"; }

list_logs()         { sql_query "SELECT * FROM logs WHERE api_id=$1 ORDER BY id;"; }
get_log()           { sql_query "SELECT * FROM logs WHERE id=$1;"; }

list_test_cases()   { sql_query "SELECT * FROM test_cases WHERE api_id=$1 ORDER BY id;"; }
get_test_case()     { sql_query "SELECT * FROM test_cases WHERE id=$1;"; }

list_environments() { sql_query "SELECT * FROM environments WHERE api_id=$1 ORDER BY id;"; }
get_environment()   { sql_query "SELECT * FROM environments WHERE id=$1;"; }

