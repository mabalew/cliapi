# ==== UPDATE ====
update_api() {
  local id="$1"
  local base_url require_auth require_csrf require_cookies
  base_url="$(sql_escape "$2")"
  require_auth="${3:-0}"
  require_csrf="${4:-0}"
  require_cookies="${5:-0}"
  sql_exec "
UPDATE api
SET base_url='$base_url',
    require_auth=$require_auth,
    require_csrf=$require_csrf,
    require_cookies=$require_cookies
WHERE id=$id;
"
}

update_header() {
  local id="$1"; local key value
  key="$(sql_escape "$2")"; value="$(sql_escape "$3")"
  sql_exec "
UPDATE headers
SET header_key='$key', header_value='$value'
WHERE id=$id;
"
}

update_param() {
  local id="$1"; local key value
  key="$(sql_escape "$2")"; value="$(sql_escape "$3")"
  sql_exec "
UPDATE params
SET param_key='$key', param_value='$value'
WHERE id=$id;
"
}

update_cookie() {
  local id="$1"; local ck cv ct
  ck="$(sql_escape "$2")"; cv="$(sql_escape "$3")"; ct="$(sql_escape "$4")"
  sql_exec "
UPDATE cookies
SET cookie_key='$ck', cookie_value='$cv', csrf_token='$ct'
WHERE id=$id;
"
}

update_auth() {
  local id="$1"; local t v
  t="$(sql_escape "$2")"; v="$(sql_escape "$3")"
  sql_exec "
UPDATE auth
SET auth_type='$t', auth_value='$v'
WHERE id=$id;
"
}

update_request() {
  local id="$1"; local m e b
  m="$(sql_escape "$2")"; e="$(sql_escape "$3")"; b="$(sql_escape "$4")"
  sql_exec "
UPDATE requests
SET method='$m', endpoint='$e', request_body='$b'
WHERE id=$id;
"
}

update_response() {
  local id="$1"; local body code
  body="$(sql_escape "$2")"; code="${3:-0}"
  sql_exec "
UPDATE responses
SET response_body='$body', status_code=$code
WHERE id=$id;
"
}

update_log() {
  local id="$1"; local msg lvl
  msg="$(sql_escape "$2")"; lvl="$(sql_escape "$3")"
  sql_exec "
UPDATE logs
SET log_message='$msg', log_level='$lvl'
WHERE id=$id;
"
}

update_test_case() {
  local id="$1"; local name desc code body
  name="$(sql_escape "$2")"
  desc="$(sql_escape "$3")"
  code="${4:-200}"
  body="$(sql_escape "$5")"
  sql_exec "
UPDATE test_cases
SET test_name='$name', test_description='$desc', expected_status_code=$code, expected_response_body='$body'
WHERE id=$id;
"
}

update_environment() {
  local id="$1"; local name val
  name="$(sql_escape "$2")"; val="$(sql_escape "$3")"
  sql_exec "
UPDATE environments
SET env_name='$name', env_value='$val'
WHERE id=$id;
"
}

