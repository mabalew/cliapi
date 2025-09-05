# ==== MODIFY (INSERT/CREATE) ====
add_api() {
  local base_url require_auth require_csrf require_cookies
  base_url="$(sql_escape "$1")"
  require_auth="${2:-0}"
  require_csrf="${3:-0}"
  require_cookies="${4:-0}"
  sql_exec "
INSERT INTO api (base_url, require_auth, require_csrf, require_cookies)
VALUES ('$base_url', $require_auth, $require_csrf, $require_cookies);
"
}

set_headers() {
  local api_id="$1"; shift || true
  (( $# > 0 && $# % 2 == 0 )) || { echo "ERROR: set_headers <api_id> <key val>..." >&2; exit 1; }
  while (( $# > 0 )); do
    local k v
    k="$(sql_escape "$1")"; v="$(sql_escape "$2")"
    sql_exec "
INSERT INTO headers (api_id, header_key, header_value)
VALUES ($api_id, '$k', '$v');
"
    shift 2
  done
}

set_params() {
  local api_id="$1"; shift || true
  (( $# > 0 && $# % 2 == 0 )) || { echo "ERROR: set_params <api_id> <key val>..." >&2; exit 1; }
  while (( $# > 0 )); do
    local k v
    k="$(sql_escape "$1")"; v="$(sql_escape "$2")"
    sql_exec "
INSERT INTO params (api_id, param_key, param_value)
VALUES ($api_id, '$k', '$v');
"
    shift 2
  done
}

set_cookies() {
  local api_id="$1"; shift || true
  (( $# > 0 && $# % 3 == 0 )) || { echo "ERROR: set_cookies <api_id> <key val csrf>..." >&2; exit 1; }
  while (( $# > 0 )); do
    local ck cv ct
    ck="$(sql_escape "$1")"; cv="$(sql_escape "$2")"; ct="$(sql_escape "$3")"
    sql_exec "
INSERT INTO cookies (api_id, cookie_key, cookie_value, csrf_token)
VALUES ($api_id, '$ck', '$cv', '$ct');
"
    shift 3
  done
}

set_auth() {
  local api_id="$1"
  local auth_type auth_value
  auth_type="$(sql_escape "$2")"
  auth_value="$(sql_escape "$3")"
  sql_exec "
INSERT INTO auth (api_id, auth_type, auth_value)
VALUES ($api_id, '$auth_type', '$auth_value');
"
}

set_request() {
  local api_id="$1"
  local method endpoint request_body
  method="$(sql_escape "$2")"
  endpoint="$(sql_escape "$3")"
  request_body="$(sql_escape "${4-}")"
  sql_exec "
INSERT INTO requests (api_id, method, endpoint, request_body)
VALUES ($api_id, '$method', '$endpoint', '$request_body');
"
}

set_response() {
  local request_id="$1"
  local response_body status_code
  response_body="$(sql_escape "$2")"
  status_code="${3:-0}"
  sql_exec "
INSERT INTO responses (request_id, response_body, status_code)
VALUES ($request_id, '$response_body', $status_code);
"
}

set_log() {
  local api_id="$1"
  local log_message log_level
  log_message="$(sql_escape "$2")"
  log_level="$(sql_escape "$3")"
  sql_exec "
INSERT INTO logs (api_id, log_message, log_level)
VALUES ($api_id, '$log_message', '$log_level');
"
}

set_test_case() {
  local api_id="$1"
  local test_name test_description expected_status_code expected_response_body
  test_name="$(sql_escape "$2")"
  test_description="$(sql_escape "${3-}")"
  expected_status_code="${4:-200}"
  expected_response_body="$(sql_escape "${5-}")"
  sql_exec "
INSERT INTO test_cases (api_id, test_name, test_description, expected_status_code, expected_response_body)
VALUES ($api_id, '$test_name', '$test_description', $expected_status_code, '$expected_response_body');
"
}

set_environment() {
  local api_id="$1"
  local env_name env_value
  env_name="$(sql_escape "$2")"
  env_value="$(sql_escape "$3")"
  sql_exec "
INSERT INTO environments (api_id, env_name, env_value)
VALUES ($api_id, '$env_name', '$env_value');
"
}

