#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ===== Config =====
DB="cliapi.db"

# ===== Helpers (common) =====
usage() {
  cat <<'USAGE'
Usage:

  # MODIFY (INSERT/CREATE)
  --add-api <base_url> <require_auth 0|1> <require_csrf 0|1> <require_cookies 0|1>
  --set-headers <api_id> <key1> <val1> [<key2> <val2> ...]
  --set-params  <api_id> <key1> <val1> [<key2> <val2> ...]
  --set-cookies <api_id> <cookie_key1> <cookie_val1> <csrf1> [<cookie_key2> <cookie_val2> <csrf2> ...]
  --set-auth    <api_id> <auth_type> <auth_value>
  --set-request <api_id> <method> <endpoint> <request_body>
  --set-response <request_id> <response_body> <status_code>
  --set-log      <api_id> <message> <INFO|WARN|ERROR>
  --set-test-case <api_id> <test_name> <test_desc> <expected_status_code> <expected_response_body>
  --set-environment <api_id> <env_name> <env_value>

  # UPDATE
  --update-api <id> <base_url> <require_auth 0|1> <require_csrf 0|1> <require_cookies 0|1>
  --update-header <id> <key> <value>
  --update-param <id> <key> <value>
  --update-cookie <id> <cookie_key> <cookie_value> <csrf_token>
  --update-auth <id> <auth_type> <auth_value>
  --update-request <id> <method> <endpoint> <request_body>
  --update-response <id> <response_body> <status_code>
  --update-log <id> <message> <INFO|WARN|ERROR>
  --update-test-case <id> <test_name> <test_desc> <expected_status_code> <expected_response_body>
  --update-environment <id> <env_name> <env_value>

  # DELETE
  --delete-api <id>
  --delete-header <id>
  --delete-param <id>
  --delete-cookie <id>
  --delete-auth <id>
  --delete-request <id>
  --delete-response <id>
  --delete-log <id>
  --delete-test-case <id>
  --delete-environment <id>

  # READ
  --list-apis | --get-api <id>
  --list-headers <api_id> | --get-header <id>
  --list-params <api_id>  | --get-param <id>
  --list-cookies <api_id> | --get-cookie <id>
  --list-auth <api_id>    | --get-auth <id>
  --list-requests <api_id>| --get-request <id>
  --list-responses <request_id> | --get-response <id>
  --list-logs <api_id>    | --get-log <id>
  --list-test-cases <api_id> | --get-test-case <id>
  --list-environments <api_id> | --get-environment <id>

  # CALL
  --call <request_id>
  --call-api <api_id> <method> <endpoint> [request_body]
  --authorize <api_id>   # sam sprawdza require_csrf/require_auth i pobiera tokeny

USAGE
}

# 
sql_escape() { printf "%s" "${1-}" | sed "s/'/''/g"; }

# Exec (INSERT/UPDATE/DELETE) z FK
sql_exec() {
  sqlite3 "$DB" <<-SQL
PRAGMA foreign_keys=ON;
$1
SQL
}

# Query
sql_query() {
  sqlite3 -header -column "$DB" <<-SQL
$1
SQL
}

# Raw query
sql_query_raw() {
  local q="$1"
  sqlite3 -separator '|' "$DB" "$q"
}

# INSERT + last_insert_rowid()
sql_insert_and_return_id() {
  sqlite3 "$DB" <<-SQL | tail -n1
PRAGMA foreign_keys=ON;
$1
SELECT last_insert_rowid();
SQL
}

# URL-encode
urlencode() {
  local LC_ALL=C i c s="$1"
  for (( i=0; i<${#s}; i++ )); do
    c=${s:$i:1}
    case "$c" in
      [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
      ' ') printf '%%20' ;;
      *) printf '%%%02X' "'$c" ;;
    esac
  done
}

# ===== Includes =====
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# pliki: read.sh, update.sh, delete.sh, modify.sh, call.sh
source "$SCRIPT_DIR/read.sh"
source "$SCRIPT_DIR/update.sh"
source "$SCRIPT_DIR/delete.sh"
source "$SCRIPT_DIR/modify.sh"
source "$SCRIPT_DIR/call.sh"

# ===== CLI =====
(( $# > 0 )) || { usage; exit 1; }

while (( $# > 0 )); do
  case "${1:-}" in
    # MODIFY (INSERT/CREATE)
    --add-api)           shift; (( $#>=4 )) || { echo "ERR --add-api"; usage; exit 1; }; add_api "$1" "$2" "$3" "$4"; shift 4 ;;
    --set-headers)       shift; (( $#>=3 )) || { echo "ERR --set-headers"; usage; exit 1; }; api_id="$1"; shift; set_headers "$api_id" "$@"; break ;;
    --set-params)        shift; (( $#>=3 )) || { echo "ERR --set-params"; usage; exit 1; }; api_id="$1"; shift; set_params "$api_id" "$@"; break ;;
    --set-cookies)       shift; (( $#>=4 )) || { echo "ERR --set-cookies"; usage; exit 1; }; api_id="$1"; shift; set_cookies "$api_id" "$@"; break ;;
    --set-auth)          shift; (( $#>=3 )) || { echo "ERR --set-auth"; usage; exit 1; }; set_auth "$1" "$2" "$3"; shift 3 ;;
    --set-request)       shift; (( $#>=4 )) || { echo "ERR --set-request"; usage; exit 1; }; set_request "$1" "$2" "$3" "$4"; shift 4 ;;
    --set-response)      shift; (( $#>=3 )) || { echo "ERR --set-response"; usage; exit 1; }; set_response "$1" "$2" "$3"; shift 3 ;;
    --set-log)           shift; (( $#>=3 )) || { echo "ERR --set-log"; usage; exit 1; }; set_log "$1" "$2" "$3"; shift 3 ;;
    --set-test-case)     shift; (( $#>=5 )) || { echo "ERR --set-test-case"; usage; exit 1; }; set_test_case "$1" "$2" "$3" "$4" "$5"; shift 5 ;;
    --set-environment)   shift; (( $#>=3 )) || { echo "ERR --set-environment"; usage; exit 1; }; set_environment "$1" "$2" "$3"; shift 3 ;;

    # UPDATE
    --update-api)        shift; (( $#>=5 )) || { echo "ERR --update-api"; usage; exit 1; }; update_api "$1" "$2" "$3" "$4" "$5"; shift 5 ;;
    --update-header)     shift; (( $#>=3 )) || { echo "ERR --update-header"; usage; exit 1; }; update_header "$1" "$2" "$3"; shift 3 ;;
    --update-param)      shift; (( $#>=3 )) || { echo "ERR --update-param"; usage; exit 1; }; update_param "$1" "$2" "$3"; shift 3 ;;
    --update-cookie)     shift; (( $#>=4 )) || { echo "ERR --update-cookie"; usage; exit 1; }; update_cookie "$1" "$2" "$3" "$4"; shift 4 ;;
    --update-auth)       shift; (( $#>=3 )) || { echo "ERR --update-auth"; usage; exit 1; }; update_auth "$1" "$2" "$3"; shift 3 ;;
    --update-request)    shift; (( $#>=4 )) || { echo "ERR --update-request"; usage; exit 1; }; update_request "$1" "$2" "$3" "$4"; shift 4 ;;
    --update-response)   shift; (( $#>=3 )) || { echo "ERR --update-response"; usage; exit 1; }; update_response "$1" "$2" "$3"; shift 3 ;;
    --update-log)        shift; (( $#>=3 )) || { echo "ERR --update-log"; usage; exit 1; }; update_log "$1" "$2" "$3"; shift 3 ;;
    --update-test-case)  shift; (( $#>=5 )) || { echo "ERR --update-test-case"; usage; exit 1; }; update_test_case "$1" "$2" "$3" "$4" "$5"; shift 5 ;;
    --update-environment) shift; (( $#>=3 )) || { echo "ERR --update-environment"; usage; exit 1; }; update_environment "$1" "$2" "$3"; shift 3 ;;

    # DELETE
    --delete-api)        shift; (( $#>=1 )) || { echo "ERR --delete-api"; usage; exit 1; }; delete_api "$1"; shift 1 ;;
    --delete-header)     shift; (( $#>=1 )) || { echo "ERR --delete-header"; usage; exit 1; }; delete_header "$1"; shift 1 ;;
    --delete-param)      shift; (( $#>=1 )) || { echo "ERR --delete-param"; usage; exit 1; }; delete_param "$1"; shift 1 ;;
    --delete-cookie)     shift; (( $#>=1 )) || { echo "ERR --delete-cookie"; usage; exit 1; }; delete_cookie "$1"; shift 1 ;;
    --delete-auth)       shift; (( $#>=1 )) || { echo "ERR --delete-auth"; usage; exit 1; }; delete_auth "$1"; shift 1 ;;
    --delete-request)    shift; (( $#>=1 )) || { echo "ERR --delete-request"; usage; exit 1; }; delete_request "$1"; shift 1 ;;
    --delete-response)   shift; (( $#>=1 )) || { echo "ERR --delete-response"; usage; exit 1; }; delete_response "$1"; shift 1 ;;
    --delete-log)        shift; (( $#>=1 )) || { echo "ERR --delete-log"; usage; exit 1; }; delete_log "$1"; shift 1 ;;
    --delete-test-case)  shift; (( $#>=1 )) || { echo "ERR --delete-test-case"; usage; exit 1; }; delete_test_case "$1"; shift 1 ;;
    --delete-environment) shift; (( $#>=1 )) || { echo "ERR --delete-environment"; usage; exit 1; }; delete_environment "$1"; shift 1 ;;

    # READ
    --list-apis)           shift; list_apis ;;
    --get-api)             shift; (( $#>=1 )) || { echo "ERR --get-api <id>"; exit 1; }; get_api "$1"; shift 1 ;;

    --list-headers)        shift; (( $#>=1 )) || { echo "ERR --list-headers <api_id>"; exit 1; }; list_headers "$1"; shift 1 ;;
    --get-header)          shift; (( $#>=1 )) || { echo "ERR --get-header <id>"; exit 1; }; get_header "$1"; shift 1 ;;

    --list-params)         shift; (( $#>=1 )) || { echo "ERR --list-params <api_id>"; exit 1; }; list_params "$1"; shift 1 ;;
    --get-param)           shift; (( $#>=1 )) || { echo "ERR --get-param <id>"; exit 1; }; get_param "$1"; shift 1 ;;

    --list-cookies)        shift; (( $#>=1 )) || { echo "ERR --list-cookies <api_id>"; exit 1; }; list_cookies "$1"; shift 1 ;;
    --get-cookie)          shift; (( $#>=1 )) || { echo "ERR --get-cookie <id>"; exit 1; }; get_cookie "$1"; shift 1 ;;

    --list-auth)           shift; (( $#>=1 )) || { echo "ERR --list-auth <api_id>"; exit 1; }; list_auth "$1"; shift 1 ;;
    --get-auth)            shift; (( $#>=1 )) || { echo "ERR --get-auth <id>"; exit 1; }; get_auth "$1"; shift 1 ;;

    --list-requests)       shift; (( $#>=1 )) || { echo "ERR --list-requests <api_id>"; exit 1; }; list_requests "$1"; shift 1 ;;
    --get-request)         shift; (( $#>=1 )) || { echo "ERR --get-request <id>"; exit 1; }; get_request "$1"; shift 1 ;;

    --list-responses)      shift; (( $#>=1 )) || { echo "ERR --list-responses <request_id>"; exit 1; }; list_responses "$1"; shift 1 ;;
    --get-response)        shift; (( $#>=1 )) || { echo "ERR --get-response <id>"; exit 1; }; get_response "$1"; shift 1 ;;

    --list-logs)           shift; (( $#>=1 )) || { echo "ERR --list-logs <api_id>"; exit 1; }; list_logs "$1"; shift 1 ;;
    --get-log)             shift; (( $#>=1 )) || { echo "ERR --get-log <id>"; exit 1; }; get_log "$1"; shift 1 ;;

    --list-test-cases)     shift; (( $#>=1 )) || { echo "ERR --list-test-cases <api_id>"; exit 1; }; list_test_cases "$1"; shift 1 ;;
    --get-test-case)       shift; (( $#>=1 )) || { echo "ERR --get-test-case <id>"; exit 1; }; get_test_case "$1"; shift 1 ;;

    --list-environments)   shift; (( $#>=1 )) || { echo "ERR --list-environments <api_id>"; exit 1; }; list_environments "$1"; shift 1 ;;
    --get-environment)     shift; (( $#>=1 )) || { echo "ERR --get-environment <id>"; exit 1; }; get_environment "$1"; shift 1 ;;

    # CALL
    --call)                shift; (( $#>=1 )) || { echo "ERR --call <request_id>"; exit 1; }; call_request "$1"; shift 1 ;;
    --call-api)            shift; (( $#>=3 )) || { echo "ERR --call-api <api_id> <method> <endpoint> [body]"; exit 1; }; api_id="$1"; method="$2"; endpoint="$3"; shift 3; body="${1-}"; [[ $# -gt 0 ]] && shift 1; call_api "$api_id" "$method" "$endpoint" "${body-}" ;;
    --authorize)           shift; (( $#>=1 )) || { echo "ERR --authorize <api_id>"; exit 1; }; authorize_api "$1"; shift 1 ;;

    *) echo "Unknown parameter: $1" >&2; usage; exit 1 ;;
  esac
done

