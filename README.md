# CLIAPI — User Guide

This guide explains how to use your console / CLI-based API tester built on `sqlite3` + `curl`. It assumes you already have the scripts installed (e.g., `cliapi.sh` plus the included parts like `call.sh`) and a project database created (e.g., `cliapi.db`).

---

## Concepts & Data Model (quick)

- **api** – one row per API base URL plus flags that control behavior (auth / CSRF / cookies).
- **headers, params, cookies, auth** – things automatically attached to requests for a given API.
- **requests** – saved calls (method + endpoint + optional body).
- **responses** – historical responses linked to `requests`.
- **environments** – key–value settings used by the CLI (e.g., `CSRF_HEADER`, `LOGIN_ENDPOINT`, etc.).
- **logs** – execution logs with INFO/WARN/ERROR.

You can keep **one SQLite DB per project** (recommended).

---

## 1) Create / Update an API

```bash
# Add a new API
./cliapi.sh --add-api "http://localhost:8000" <require_auth 0/1> <require_csrf 0/1> <require_cookies 0/1>

# Update an existing API (id=1)
./cliapi.sh --update-api 1 "http://localhost:8000" 0 0 1
# meaning: require_auth=0 (no Authorization header automation),
#          require_csrf=0 (you’ll set the header manually or via cookies),
#          require_cookies=1 (send stored cookies)
```

List and inspect:
```bash
./cliapi.sh --list-apis
./cliapi.sh --get-api 1
```

---

## 2) Global Headers & Params

**Headers** are attached to **every** request for that API.
```bash
# Headers
./cliapi.sh --set-headers 1 Accept application/json
./cliapi.sh --set-headers 1 Content-Type application/json
./cliapi.sh --list-headers 1
./cliapi.sh --update-header <header_id> "X-Custom" "value"
./cliapi.sh --delete-header <header_id>
```

**Params** are appended to the URL query string for every request.
```bash
# Params (global)
./cliapi.sh --set-params 1 account_id bca2333f-a0a1-44ee-81bc-124f8d0fd7eb
./cliapi.sh --list-params 1
./cliapi.sh --update-param <param_id> account_id bca2333f-a0a1-44ee-81bc-124f8d0fd7eb
./cliapi.sh --delete-param <param_id>
```

> Tip: If an endpoint says `{"detail":"account_id is required"}` or you get `ValueError: badly formed hexadecimal UUID string`, set a valid UUID (e.g., from your JWT `sub` claim) using `--set-params` or include it directly in the URL (see §6).

---

## 3) Cookies & CSRF

You can manage cookies manually (Postman-like), or — if you enable `require_csrf=1` — the script can auto-attach a CSRF header from the stored cookie.

```bash
# Add cookies (triplets: key value csrf_token_column)
./cliapi.sh --set-cookies 1 \
  access_token '<JWT>' '' \
  csrf_token   '<CSRF_VALUE>' '<CSRF_VALUE>'

./cliapi.sh --list-cookies 1
./cliapi.sh --update-cookie <cookie_id> csrf_token '<NEW>' '<NEW>'
./cliapi.sh --delete-cookie <cookie_id>
```

**Two ways to send the CSRF token:**

- **Manual header (require_csrf=0)**  
  Add it as a normal header:
  ```bash
  ./cliapi.sh --set-headers 1 X-CSRF-Token '<CSRF_VALUE>'
  ```

- **Auto header (require_csrf=1)**  
  Set `require_csrf=1` and store the CSRF value in any cookie row’s `csrf_token` column; the script will send:
  `
  <CSRF_HEADER or "X-CSRF-Token">: <csrf_value>
  `
  Configure the header name if needed:
  ```bash
  ./cliapi.sh --set-environment 1 CSRF_HEADER X-CSRF-Token
  ```

> If your backend issues CSRF together with login cookies (e.g., `/token` sets `csrf_token` cookie), you can **skip** a dedicated `CSRF_ENDPOINT`.

---

## 4) Authorization (manual or automated)

### Manual (Postman-style)
Control everything yourself:

- **Bearer**:
  ```bash
  # Option A: via auth table (auto: "Authorization: Bearer <token>")
  ./cliapi.sh --set-auth 1 bearer '<JWT>'

  # Option B: explicit header (for a custom scheme)
  ./cliapi.sh --set-headers 1 Authorization "Bearer <JWT>"
  ```

- **Cookie-based**: just add cookies (see §3).

> In **manual** mode, do **not** use `--authorize` (no automatic login/CSRF fetching).

### Automated (optional)
If you want the CLI to try logging in:

- Set `environments` for login:
  ```bash
  # JSON body
  ./cliapi.sh --set-environment 1 LOGIN_ENDPOINT /auth/login
  ./cliapi.sh --set-environment 1 LOGIN_BODY '{"email":"user@example.com","password":"Secret"}'
  ./cliapi.sh --set-environment 1 TOKEN_JSON_KEY accessToken

  # or form-urlencoded (common for /token)
  ./cliapi.sh --set-headers 1 Content-Type application/x-www-form-urlencoded
  ./cliapi.sh --set-environment 1 LOGIN_ENDPOINT /token
  ./cliapi.sh --set-environment 1 LOGIN_BODY 'username=user@example.com&password=SecretPass1!'
  ./cliapi.sh --set-environment 1 TOKEN_JSON_KEY access_token
  ```

- (Optional) If you also need a **separate** CSRF GET:
  ```bash
  ./cliapi.sh --set-environment 1 CSRF_ENDPOINT /auth/csrf
  ./cliapi.sh --set-environment 1 CSRF_HEADER   X-CSRF-Token
  ```

- Run:
  ```bash
  ./cliapi.sh --authorize 1
  ./cliapi.sh --list-auth 1
  ./cliapi.sh --list-cookies 1
  ./cliapi.sh --list-logs 1
  ```

> The script follows redirects, saves all `Set-Cookie`, and stores the token if it finds it in the body or cookies. If `CSRF_ENDPOINT` is not set, it won’t fail — it will rely on cookies from login.

---

## 5) Save & Re-run Requests

### Save a request
```bash
./cliapi.sh --set-request 1 GET /subscriptions ""
./cliapi.sh --set-request 1 GET /payments ""
```

### List & inspect
```bash
./cliapi.sh --list-requests 1
./cliapi.sh --get-request <request_id>
```

### Update or delete
```bash
./cliapi.sh --update-request <request_id> method POST
./cliapi.sh --update-request <request_id> endpoint "/subscriptions?account_id=..."
./cliapi.sh --update-request <request_id> body '{"foo":"bar"}'
./cliapi.sh --delete-request <request_id>
```

### Execute by id
```bash
./cliapi.sh --call <request_id>
```

---

## 6) Ad-hoc Calls (no need to save first)

```bash
# GET with automatic query params from "params" table
./cliapi.sh --call-api 1 GET /subscriptions

# One-off query in URL:
./cliapi.sh --call-api 1 GET "/payments?account_id=bca2333f-a0a1-44ee-81bc-124f8d0fd7eb"

# POST JSON body (Content-Type is auto-added for non-GET if missing)
./cliapi.sh --call-api 1 POST /something '{"key":"value"}'
```

The CLI will:
- assemble URL = `base_url + endpoint + global params`,
- attach headers, cookies, (optional) Authorization, (optional) CSRF header,
- run `curl -L`,
- write `responses` + update `requests.status_code/response_body` + `api.last_response`,
- log to `logs`.

---

## 7) Environments (key–value settings)

Common keys:
- `CSRF_HEADER` – default `X-CSRF-Token` (override here).
- `CSRF_ENDPOINT` – optional GET endpoint to prefetch CSRF/cookies.
- `LOGIN_ENDPOINT`, `LOGIN_BODY`, `TOKEN_JSON_KEY` – automated login.
- (Optional fallbacks you may have added) `TOKEN_PROVIDER`, `AUTH_STATIC_TOKEN`, `AUTH_TOKEN_FILE`, `AUTH_TOKEN_CMD`.

Manage:
```bash
./cliapi.sh --set-environment 1 CSRF_HEADER X-CSRF-Token
./cliapi.sh --list-environments 1
./cliapi.sh --update-environment <env_id> CSRF_HEADER X-XSRF-TOKEN
./cliapi.sh --delete-environment <env_id>
```

---

## 8) Reading Responses & Logs

```bash
# All requests for an API
./cliapi.sh --list-requests 1

# Responses for a specific request
./cliapi.sh --list-responses <request_id>

# Last response body is also copied to "api.last_response"
./cliapi.sh --get-api 1

# Logs
./cliapi.sh --list-logs 1
```

---

## 9) Typical Flows

### A) Cookie + CSRF (manual, like Postman)
```bash
# Update API flags
./cliapi.sh --update-api 1 http://localhost:8000 0 0 1

# Headers
./cliapi.sh --set-headers 1 Accept application/json
./cliapi.sh --set-headers 1 X-CSRF-Token 561KfSZRsLv0TjH4oOYAxZMGraLKC_zSzK6sgwuBGmw

# Cookies
./cliapi.sh --set-cookies 1 \
  access_token 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' '' \
  csrf_token   '561KfSZRsLv0TjH4oOYAxZMGraLKC_zSzK6sgwuBGmw' '561KfSZRsLv0TjH4oOYAxZMGraLKC_zSzK6sgwuBGmw'

# Global query param (required by backend)
./cliapi.sh --set-params 1 account_id bca2333f-a0a1-44ee-81bc-124f8d0fd7eb

# Calls
./cliapi.sh --call-api 1 GET /subscriptions
./cliapi.sh --call-api 1 GET /payments
```

### B) Bearer (manual)
```bash
./cliapi.sh --update-api 1 http://localhost:8000 1 0 0
./cliapi.sh --set-auth 1 bearer '<JWT>'
./cliapi.sh --set-headers 1 Accept application/json
./cliapi.sh --call-api 1 GET /subscriptions
```

### C) Automated login (optional)
```bash
./cliapi.sh --update-api 1 http://localhost:8000 1 1 1
./cliapi.sh --set-headers 1 Accept application/json
./cliapi.sh --set-headers 1 Content-Type application/x-www-form-urlencoded
./cliapi.sh --set-environment 1 LOGIN_ENDPOINT /token
./cliapi.sh --set-environment 1 LOGIN_BODY 'username=admin@example.com&password=SecretPass1!'
./cliapi.sh --set-environment 1 TOKEN_JSON_KEY access_token
./cliapi.sh --set-environment 1 CSRF_HEADER X-CSRF-Token   # if your server expects this name

./cliapi.sh --authorize 1
./cliapi.sh --call-api 1 GET /subscriptions
```

---

## 10) Troubleshooting

- **Empty console output**  
  The script still stores the HTTP status and body (even if empty). Check:
  ```bash
  ./cliapi.sh --list-requests 1
  ./cliapi.sh --list-responses <request_id>
  ./cliapi.sh --list-logs 1
  ```
- **`{"detail":"account_id is required"}`**  
  Add `account_id` parameter (`--set-params 1 account_id <UUID>`).
- **`ValueError: badly formed hexadecimal UUID string`**  
  Use a valid UUID (format `8-4-4-4-12`, hex).
- **Unsupported Media Type (415)**  
  Add the right `Content-Type` header (e.g., `application/json` or `application/x-www-form-urlencoded`).
- **CSRF Forbidden (403)**  
  Ensure the CSRF header name matches the backend (`CSRF_HEADER`) and the value is present (from cookie or header).
- **Redirects/302**  
  The script uses `curl -L`, so redirects are followed automatically.
- **Quoting issues**  
  Bodies are passed via `--data-binary`. If your JSON contains quotes, ensure shell quoting is correct, or store the body in the `requests` table and call it by id.

---

## 11) Safety & Tips

- Keep separate databases per project to avoid leaking headers/cookies across environments.
- Rotate tokens by updating `headers`, `cookies`, or `auth` rows — you don’t need to recreate the API.
- Use `--list-logs` frequently: the script writes clear INFO/WARN/ERROR messages for each call and authorization step.

