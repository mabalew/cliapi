# ==== CALL / AUTH ENGINE (fixed) ====

# ZŁOŻENIE URL z globalnych params (api_id)
build_url_with_params() {
  local base_url="$1" endpoint="$2" api_id="$3"
  local query=""
  while IFS='|' read -r pkey pval; do
    [[ -z "$pkey" ]] && continue
    local ek="$(urlencode "$pkey")"
    local ev="$(urlencode "$pval")"
    if [[ -z "$query" ]]; then query="?${ek}=${ev}"; else query="${query}&${ek}=${ev}"; fi
  done < <(sql_query_raw "SELECT param_key, param_value FROM params WHERE api_id=$api_id ORDER BY id;")
  printf "%s%s%s" "$base_url" "$endpoint" "$query"
}

# ZBIERANIE nagłówków z bazy
collect_headers() {
  local api_id="$1" out=""
  while IFS='|' read -r hkey hval; do
    [[ -z "$hkey" ]] && continue
    out+=" -H '$(printf "%s: %s" "$hkey" "$hval")' "
  done < <(sql_query_raw "SELECT header_key, header_value FROM headers WHERE api_id=$api_id ORDER BY id;")
  printf "%s" "$out"
}

# ZBIERANIE cookies oraz pierwszego napotkanego csrf_token (z kolumny csrf_token)
collect_cookies_and_csrf() {
  local api_id="$1" cookie_str="" csrf_token=""
  while IFS='|' read -r ckey cval ctoken; do
    [[ -n "$ckey" ]] && cookie_str+="${ckey}=${cval}; "
    [[ -z "$csrf_token" && -n "$ctoken" ]] && csrf_token="$ctoken"
  done < <(sql_query_raw "SELECT cookie_key, cookie_value, IFNULL(csrf_token,'') FROM cookies WHERE api_id=$api_id ORDER BY id;")
  printf "%s|%s" "$cookie_str" "$csrf_token"
}

# POBRANIE wartości z environments
get_env_val() {
  local api_id="$1" key="$2"
  sql_query_raw "SELECT env_value FROM environments WHERE api_id=$api_id AND env_name='$key' ORDER BY id DESC LIMIT 1;"
}

# ZAPIS tokenu do auth (bearer)
store_token() {
  local api_id="$1" token="$2"
  local esc_tok="$(sql_escape "$token")"
  sql_exec "INSERT INTO auth (api_id, auth_type, auth_value) VALUES ($api_id, 'bearer', '$esc_tok');"
  local msg="authorize: token stored (provider)"
  local esc="$(sql_escape "$msg")"
  sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'INFO');"
}

# === WŁAŚCIWE WYWOŁANIE ZAPISANEGO REQUESTU ===
call_request() {
  local req_id="$1"
  local row
  row="$(sql_query_raw "
SELECT r.api_id, r.method, r.endpoint, IFNULL(r.request_body,''), a.base_url,
       IFNULL(a.require_auth,0), IFNULL(a.require_csrf,0), IFNULL(a.require_cookies,0)
FROM requests r JOIN api a ON a.id=r.api_id WHERE r.id=$req_id;")"
  if [[ -z "$row" ]]; then
    local msg="call_request: request $req_id not found"
    local esc="$(sql_escape "$msg")"
    sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES (0, '$esc', 'ERROR');"
    echo "ERROR: request id $req_id not found" >&2
    return 1
  fi

  IFS='|' read -r api_id method endpoint request_body base_url require_auth require_csrf require_cookies <<< "$row"

  local url; url="$(build_url_with_params "$base_url" "$endpoint" "$api_id")"
  local hdrs_str; hdrs_str="$(collect_headers "$api_id")"

  # Authorization (z tabeli auth), jeżeli require_auth=1
  if [[ "$require_auth" -eq 1 ]]; then
    local atype aval
    IFS='|' read -r atype aval < <(sql_query_raw "SELECT auth_type, auth_value FROM auth WHERE api_id=$api_id ORDER BY id DESC LIMIT 1;")
    atype="${atype:-}"; aval="${aval:-}"
    if [[ -n "$atype" && -n "$aval" ]]; then
      case "$atype" in
        bearer|Bearer) hdrs_str+=" -H 'Authorization: Bearer ${aval}' " ;;
        basic|Basic)   hdrs_str+=" -H 'Authorization: Basic ${aval}' " ;;
        header|Header) hdrs_str+=" -H '${aval}' " ;;
        *)             hdrs_str+=" -H 'Authorization: ${aval}' " ;;
      esac
    fi
  fi

  # Cookies + CSRF (jeśli wymagane)
  local cookie_and_csrf; cookie_and_csrf="$(collect_cookies_and_csrf "$api_id")"
  local cookie_str="${cookie_and_csrf%%|*}"; local csrf_token="${cookie_and_csrf#*|}"
  local cookie_opt=""
  [[ "$require_cookies" -eq 1 && -n "$cookie_str" ]] && cookie_opt=" -b '$cookie_str' "

  if [[ "$require_csrf" -eq 1 && -n "$csrf_token" ]]; then
    local csrf_header; csrf_header="$(get_env_val "$api_id" "CSRF_HEADER")"
    csrf_header="${csrf_header:-X-CSRF-Token}"
    hdrs_str+=" -H '${csrf_header}: ${csrf_token}' "
  fi

  # Content-Type domyślnie dla non-GET z body (jeśli brak w headers)
  if [[ "${method^^}" != "GET" && -n "$request_body" ]]; then
    if ! grep -qi "content-type:" <<< "$hdrs_str"; then
      hdrs_str+=" -H 'Content-Type: application/json' "
    fi
  fi

  # CURL
  local body_file header_file; body_file="$(mktemp)"; header_file="$(mktemp)"
  local curl_cmd="curl -sS -L -D '$header_file' -o '$body_file' -w '%{http_code}' -X '$method' $hdrs_str $cookie_opt"
  if [[ "${method^^}" != "GET" && -n "$request_body" ]]; then
    curl_cmd+=" --data-binary '$request_body'"
  fi
  curl_cmd+=" '$url'"

  local http_code rc
  set +e
  http_code=$(eval "$curl_cmd")
  rc=$?
  set -e

  # jeśli pusto/nie-liczba, spróbuj z nagłówków
  if [[ -z "$http_code" || ! "$http_code" =~ ^[0-9]{3}$ ]]; then
    http_code="$(awk 'BEGIN{c=0}/^HTTP\//{code=$2;c++}END{if(c>0)print code;}' "$header_file")"
    [[ -z "$http_code" ]] && http_code=0
  fi

  local resp_body hdr_dump
  resp_body="$(cat "$body_file")"
  hdr_dump="$(head -c 400 "$header_file" | sed 's/"/\\"/g')"

  rm -f "$body_file" "$header_file"

  local resp_body_sql; resp_body_sql="$(sql_escape "$resp_body")"

  # ZAWSZE zapisujemy odpowiedź i status
  sql_exec "
INSERT INTO responses (request_id, response_body, status_code) VALUES ($req_id, '$resp_body_sql', $http_code);
UPDATE requests SET response_body='$resp_body_sql', status_code=$http_code WHERE id=$req_id;
UPDATE api SET last_response='$resp_body_sql' WHERE id=$api_id;
"

  # LOGI – budujemy tekst w Bashu i escapujemy
  if (( rc != 0 )); then
    local msg="curl rc=$rc; HTTP $http_code; hdr=\"${hdr_dump}\""
    local esc="$(sql_escape "$msg")"
    sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'ERROR');"
  elif (( http_code >= 400 )); then
    local short="$(printf "%s" "$resp_body" | head -c 200)"
    local msg="HTTP $http_code; body=\"${short}\""
    local esc="$(sql_escape "$msg")"
    sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'ERROR');"
  else
    local msg="HTTP $http_code"
    local esc="$(sql_escape "$msg")"
    sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'INFO');"
  fi

  # output do konsoli
  if [[ -z "$resp_body" ]]; then
    echo "[HTTP $http_code] (empty body)"
  else
    printf "%s\n" "$resp_body"
  fi
  return $rc
}

# Szybkie utworzenie requestu ad-hoc i wykonanie
call_api() {
  local api_id="$1" method="$2" endpoint="$3" body="${4-}"
  local new_id
  new_id="$(sql_insert_and_return_id "
INSERT INTO requests (api_id, method, endpoint, request_body)
VALUES ($api_id, '$(sql_escape "$method")', '$(sql_escape "$endpoint")', '$(sql_escape "$body")');")"
  [[ -z "$new_id" ]] && { echo "ERROR: cannot create request for api_id=$api_id" >&2; return 1; }
  call_request "$new_id"
}

# AUTORYZACJA: CSRF (opcjonalnie) + LOGIN; zapis cookies, tokenu
authorize_api() {
  local api_id="$1"
  local row
  row="$(sql_query_raw "SELECT base_url, IFNULL(require_auth,0), IFNULL(require_csrf,0) FROM api WHERE id=$api_id;")"
  [[ -z "$row" ]] && { echo "ERROR: API id $api_id not found" >&2; return 1; }
  IFS='|' read -r base_url require_auth require_csrf <<< "$row"

  local hdrs; hdrs="$(collect_headers "$api_id")"

  # ===== CSRF (opcjonalny – JEŚLI ustawiony CSRF_ENDPOINT) =====
  if [[ "$require_csrf" -eq 1 ]]; then
    local csrf_ep; csrf_ep="$(get_env_val "$api_id" "CSRF_ENDPOINT")"
    if [[ -n "$csrf_ep" ]]; then
      local csrf_hdr_name; csrf_hdr_name="$(get_env_val "$api_id" "CSRF_HEADER")"
      csrf_hdr_name="${csrf_hdr_name:-X-CSRF-Token}"
      local url_csrf="${base_url}${csrf_ep}"
      local hf bf; hf="$(mktemp)"; bf="$(mktemp)"

      local code rc
      set +e
      code=$(eval "curl -sS -L -D '$hf' -o '$bf' -w '%{http_code}' -X GET $hdrs '$url_csrf'")
      rc=$?
      set -e

      if (( rc != 0 )); then
        local msg="authorize CSRF curl rc=$rc"
        local esc="$(sql_escape "$msg")"
        sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'ERROR')"
        rm -f "$hf" "$bf"
        return 1
      fi

      # nagłówek CSRF (opcjonalnie)
      local csrf_token_hdr=""
      csrf_token_hdr="$(awk -v key="$csrf_hdr_name" 'BEGIN{IGNORECASE=1}toupper($0)~"^"toupper(key)": "{sub(/^[^:]*:[ ]*/,"");gsub(/\r/,"");print;exit}' "$hf")"

      # zapisz cookies z odpowiedzi CSRF
      while IFS= read -r line; do
        local kv="${line#Set-Cookie: }"; kv="${kv%%;*}"
        local ckey="${kv%%=*}"; local cval="${kv#*=}"
        ckey="$(echo -n "$ckey" | tr -d '\r\n')"; cval="$(echo -n "$cval" | tr -d '\r\n')"
        local ctoken=""
        if [[ -z "$csrf_token_hdr" && "$ckey" =~ [Cc][SsXx][Rr][Ff] ]]; then
          ctoken="$cval"
        fi
        sql_exec "
INSERT INTO cookies (api_id, cookie_key, cookie_value, csrf_token)
VALUES ($api_id, '$(sql_escape "$ckey")', '$(sql_escape "$cval")', '$(sql_escape "$ctoken")');
"
      done < <(grep -i '^Set-Cookie:' "$hf")

      # jeśli token tylko w nagłówku — zapisz wiersz techniczny, by był dostępny
      if [[ -n "$csrf_token_hdr" ]]; then
        sql_exec "
INSERT INTO cookies (api_id, cookie_key, cookie_value, csrf_token)
VALUES ($api_id, 'csrf-token', '', '$(sql_escape "$csrf_token_hdr")');
"
      fi

      local msg="authorize: CSRF fetched (HTTP $code)"
      local esc="$(sql_escape "$msg")"
      sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'INFO')"
      rm -f "$hf" "$bf"
    else
      local msg="authorize: CSRF_ENDPOINT not set; will rely on login Set-Cookie"
      local esc="$(sql_escape "$msg")"
      sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'WARN')"
    fi
  fi

  # ===== LOGIN (jeżeli skonfigurowany) =====
  local login_ep; login_ep="$(get_env_val "$api_id" "LOGIN_ENDPOINT")"
  local login_body; login_body="$(get_env_val "$api_id" "LOGIN_BODY")"
  local token_key; token_key="$(get_env_val "$api_id" "TOKEN_JSON_KEY")"

  if [[ -n "$login_ep" ]]; then
    local url_login="${base_url}${login_ep}"
    local hf bf; hf="$(mktemp)"; bf="$(mktemp)"

    # Content-Type — jeśli nie jest zdefiniowany globalnie, dobierz na podstawie kształtu body
    local ct_header=""
    if ! grep -qi "Content-Type:" <<< "$hdrs"; then
      if [[ -n "$login_body" && "$login_body" == *"="* && "$login_body" == *"&"* ]]; then
        ct_header=" -H 'Content-Type: application/x-www-form-urlencoded' "
      elif [[ -n "$login_body" && "$login_body" == "{"* ]]; then
        ct_header=" -H 'Content-Type: application/json' "
      else
        ct_header=" -H 'Content-Type: application/json' "
      fi
    fi

    local curl_cmd="curl -sS -L -D '$hf' -o '$bf' -w '%{http_code}' -X POST $hdrs $ct_header '$url_login'"
    [[ -n "$login_body" ]] && curl_cmd+=" --data-binary '$(printf "%s" "$login_body")'"

    local code rc
    set +e
    code=$(eval "$curl_cmd")
    rc=$?
    set -e

    local body; body="$(cat "$bf")"

    # token z body (jq -> fallback sed)
    local token=""
    if command -v jq >/dev/null 2>&1; then
      if [[ -n "$token_key" ]]; then
        token="$(printf "%s" "$body" | jq -r --arg k "$token_key" '.[$k] // .access_token // .accessToken // .id_token // .token // .data.accessToken // empty')"
      else
        token="$(printf "%s" "$body" | jq -r '.access_token // .accessToken // .id_token // .token // .data.accessToken // empty')"
      fi
      [[ "$token" == "null" ]] && token=""
    else
      if [[ -n "$token_key" ]]; then
        token="$(printf "%s" "$body" | sed -nE "s/.*\"${token_key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p")"
      fi
      [[ -z "$token" ]] && token="$(printf "%s" "$body" | sed -nE 's/.*"access_token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      [[ -z "$token" ]] && token="$(printf "%s" "$body" | sed -nE 's/.*"accessToken"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      [[ -z "$token" ]] && token="$(printf "%s" "$body" | sed -nE 's/.*"id_token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      [[ -z "$token" ]] && token="$(printf "%s" "$body" | sed -nE 's/.*"token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
      [[ -z "$token" ]] && token="$(printf "%s" "$body" | sed -nE 's/.*"data"[[:space:]]*:[[:space:]]*\{[^}]*"accessToken"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
    fi

    # ZAPISZ WSZYSTKIE Set-Cookie z loginu (w tym csrf_token/access_token)
    while IFS= read -r line; do
      local kv="${line#Set-Cookie: }"; kv="${kv%%;*}"
      local ckey="${kv%%=*}"; local cval="${kv#*=}"
      ckey="$(echo -n "$ckey" | tr -d '\r\n')"; cval="$(echo -n "$cval" | tr -d '\r\n')"
      local ctoken=""
      if [[ "$ckey" =~ [Cc][SsXx][Rr][Ff] ]]; then
        ctoken="$cval"
      fi
      sql_exec "
INSERT INTO cookies (api_id, cookie_key, cookie_value, csrf_token)
VALUES ($api_id, '$(sql_escape "$ckey")', '$(sql_escape "$cval")', '$(sql_escape "$ctoken")');
"
    done < <(grep -i '^Set-Cookie:' "$hf")

    if (( rc != 0 )); then
      local msg="authorize LOGIN curl rc=$rc"
      local esc="$(sql_escape "$msg")"
      sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'ERROR')"
      rm -f "$hf" "$bf"
      return 1
    fi

    if [[ -n "$token" ]]; then
      store_token "$api_id" "$token"
      local msg="authorize: token via LOGIN (HTTP $code)"
      local esc="$(sql_escape "$msg")"
      sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'INFO')"
    else
      local body_short="$(printf "%s" "$body" | head -c 200)"
      local msg="authorize LOGIN failed; HTTP $code; body=\"${body_short}\""
      local esc="$(sql_escape "$msg")"
      sql_exec "INSERT INTO logs(api_id, log_message, log_level) VALUES ($api_id, '$esc', 'WARN')"
    fi

    rm -f "$hf" "$bf"
  fi

  return 0
}

