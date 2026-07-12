"""
QuickBooks Online Connector Microservice
OneWish OS — Power Connection AI
Provides OAuth 2.0 + REST API bridge between QBO and agent ecosystem.
"""

import json
import hashlib
import os
import subprocess
import time
from datetime import datetime, timedelta
from urllib.parse import urlencode, parse_qs, urlparse
from http.server import HTTPServer, BaseHTTPRequestHandler

import requests
from requests.auth import HTTPBasicAuth

# ─── Config ───────────────────────────────────────────────────────────────────
PORT = 8085
REDIRECT_URI = f"http://localhost:{PORT}/callback"
AUTH_BASE = "https://appcenter.intuit.com/connect/oauth2"
TOKEN_URL = "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
API_BASE = "https://quickbooks.api.intuit.com/v3/company"
DISCOVERY_URL = "https://developer.api.intuit.com/.well-known/openid_sandbox_configuration"
SCOPES = "com.intuit.quickbooks.accounting"

ENTITIES = {
    "power_connection": {
        "name": "Power Connection.AI LLC",
        "op_token_item": "QuickBooks-OAuth-Tokens-PC",
    },
    "connected_energy": {
        "name": "Connected Energy Services LLC",
        "op_token_item": "QuickBooks-OAuth-Tokens-CE",
    },
    "connected_ai": {
        "name": "Connected AI Investments QOF",
        "op_token_item": "QuickBooks-OAuth-Tokens-CA",
    },
}

# ─── 1Password Helpers ─────────────────────────────────────────────────────────

def op_read(path: str) -> str:
    """Read a secret from 1Password."""
    result = subprocess.run(
        ["op", "read", path], capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"1Password read failed: {result.stderr}")
    return result.stdout.strip()

def op_store_token(entity: str, access_token: str, refresh_token: str, realm_id: str, expires_in: int):
    """Store tokens in 1Password."""
    item_name = ENTITIES[entity]["op_token_item"]
    expires_at = (datetime.utcnow() + timedelta(seconds=expires_in)).isoformat()
    subprocess.run([
        "op", "item", "edit", item_name,
        "--vault", "powerconnection-ai",
        f"Access Token[password]={access_token}",
        f"Refresh Token[password]={refresh_token}",
        f"Realm ID[text]={realm_id}",
        f"Expires At[text]={expires_at}",
    ], capture_output=True)

def get_credentials():
    """Load QB app credentials from 1Password."""
    client_id = op_read("op://powerconnection-ai/QuickBooks-OAuth-App/Client ID")
    client_secret = op_read("op://powerconnection-ai/QuickBooks-OAuth-App/Client Secret")
    return client_id, client_secret

def get_entity_tokens(entity: str):
    """Get stored tokens for an entity from 1Password."""
    item_name = ENTITIES[entity]["op_token_item"]
    result = subprocess.run(
        ["op", "item", "get", item_name, "--vault", "powerconnection-ai", "--format=json"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return None, None, None
    data = json.loads(result.stdout)
    fields = {f["label"]: f.get("value", "") for f in data.get("fields", [])}
    return (
        fields.get("Access Token"),
        fields.get("Refresh Token"),
        fields.get("Realm ID"),
    )

# ─── Token Management ──────────────────────────────────────────────────────────

def refresh_access_token(entity: str) -> str:
    """Refresh the access token using the refresh token."""
    client_id, client_secret = get_credentials()
    _, refresh_token, realm_id = get_entity_tokens(entity)
    if not refresh_token:
        raise RuntimeError(f"No refresh token for entity: {entity}")
    resp = requests.post(
        TOKEN_URL,
        auth=HTTPBasicAuth(client_id, client_secret),
        data={"grant_type": "refresh_token", "refresh_token": refresh_token},
        headers={"Accept": "application/json"},
    )
    resp.raise_for_status()
    tokens = resp.json()
    op_store_token(
        entity,
        tokens["access_token"],
        tokens.get("refresh_token", refresh_token),
        realm_id,
        tokens.get("expires_in", 3600),
    )
    return tokens["access_token"]

def qbo_get(path: str, entity: str, params: dict = None) -> dict:
    """Make an authenticated GET request to the QBO API."""
    access_token, _, realm_id = get_entity_tokens(entity)
    if not access_token or not realm_id:
        raise RuntimeError(f"No QB credentials for entity: {entity}. Run /authorize first.")
    url = f"{API_BASE}/{realm_id}/{path}"
    headers = {"Authorization": f"Bearer {access_token}", "Accept": "application/json"}
    resp = requests.get(url, headers=headers, params=params or {})
    if resp.status_code == 401:
        access_token = refresh_access_token(entity)
        headers["Authorization"] = f"Bearer {access_token}"
        resp = requests.get(url, headers=headers, params=params or {})
    resp.raise_for_status()
    return resp.json()

def qbo_query(sql: str, entity: str) -> dict:
    """Run a QBO SQL-style query."""
    return qbo_get("query", entity, params={"query": sql, "minorversion": "75"})

# ─── Data Extractors ───────────────────────────────────────────────────────────

def get_transactions(entity: str, start: str, end: str) -> list:
    data = qbo_query(
        f"SELECT * FROM Transaction WHERE TxnDate >= '{start}' AND TxnDate <= '{end}'",
        entity
    )
    rows = data.get("QueryResponse", {})
    txns = []
    for k, v in rows.items():
        if isinstance(v, list):
            txns.extend(v)
    result = []
    for t in txns:
        row = {
            "id": t.get("Id"),
            "type": t.get("type", k),
            "date": t.get("TxnDate"),
            "amount": t.get("TotalAmt", 0),
            "memo": t.get("PrivateNote", ""),
            "doc_number": t.get("DocNumber", ""),
        }
        raw = json.dumps(row, sort_keys=True).encode()
        row["sha256"] = hashlib.sha256(raw).hexdigest()
        result.append(row)
    return result

def get_invoices(entity: str, status: str = "open") -> list:
    where = "WHERE Balance > '0'" if status == "open" else ""
    data = qbo_query(f"SELECT * FROM Invoice {where} MAXRESULTS 1000", entity)
    return data.get("QueryResponse", {}).get("Invoice", [])

def get_bills(entity: str, status: str = "open") -> list:
    where = "WHERE Balance > '0'" if status == "open" else ""
    data = qbo_query(f"SELECT * FROM Bill {where} MAXRESULTS 1000", entity)
    return data.get("QueryResponse", {}).get("Bill", [])

def get_accounts(entity: str) -> list:
    data = qbo_query("SELECT * FROM Account MAXRESULTS 1000", entity)
    return data.get("QueryResponse", {}).get("Account", [])

def get_customers(entity: str) -> list:
    data = qbo_query("SELECT * FROM Customer MAXRESULTS 1000", entity)
    return data.get("QueryResponse", {}).get("Customer", [])

def get_vendors(entity: str) -> list:
    data = qbo_query("SELECT * FROM Vendor MAXRESULTS 1000", entity)
    return data.get("QueryResponse", {}).get("Vendor", [])

def get_report(report_type: str, entity: str, start: str, end: str) -> dict:
    path = f"reports/{report_type}"
    return qbo_get(path, entity, params={
        "start_date": start,
        "end_date": end,
        "minorversion": "75",
    })

# ─── HTTP Handler ─────────────────────────────────────────────────────────────

class QBHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        ts = datetime.utcnow().isoformat()
        print(f"[{ts}] {format % args}")

    def send_json(self, data: dict, code: int = 200):
        body = json.dumps(data, indent=2, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, msg: str, code: int = 500):
        self.send_json({"error": msg}, code)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)
        get = lambda k, d=None: qs.get(k, [d])[0]

        try:
            if path == "/health":
                entities_status = {}
                for e in ENTITIES:
                    at, rt, rid = get_entity_tokens(e)
                    entities_status[e] = {
                        "connected": bool(at and rid),
                        "realm_id": rid or "not_set",
                    }
                self.send_json({
                    "status": "healthy",
                    "service": "qb-connector",
                    "timestamp": datetime.utcnow().isoformat(),
                    "entities": entities_status,
                })

            elif path == "/authorize":
                entity = get("entity", "power_connection")
                client_id, _ = get_credentials()
                params = {
                    "client_id": client_id,
                    "scope": SCOPES,
                    "redirect_uri": REDIRECT_URI,
                    "response_type": "code",
                    "state": entity,
                }
                url = f"{AUTH_BASE}?{urlencode(params)}"
                self.send_response(302)
                self.send_header("Location", url)
                self.end_headers()

            elif path == "/callback":
                code = get("code")
                realm_id = get("realmId")
                entity = get("state", "power_connection")
                client_id, client_secret = get_credentials()
                resp = requests.post(
                    TOKEN_URL,
                    auth=HTTPBasicAuth(client_id, client_secret),
                    data={
                        "grant_type": "authorization_code",
                        "code": code,
                        "redirect_uri": REDIRECT_URI,
                    },
                    headers={"Accept": "application/json"},
                )
                resp.raise_for_status()
                tokens = resp.json()
                op_store_token(
                    entity,
                    tokens["access_token"],
                    tokens["refresh_token"],
                    realm_id,
                    tokens.get("expires_in", 3600),
                )
                self.send_json({
                    "status": "authorized",
                    "entity": entity,
                    "realm_id": realm_id,
                    "message": "Tokens stored in 1Password. Connection ready.",
                })

            elif path == "/transactions":
                entity = get("entity", "power_connection")
                start = get("start", str((datetime.utcnow() - timedelta(days=30)).date()))
                end = get("end", str(datetime.utcnow().date()))
                txns = get_transactions(entity, start, end)
                self.send_json({
                    "entity": entity,
                    "period": {"start": start, "end": end},
                    "count": len(txns),
                    "transactions": txns,
                })

            elif path == "/invoices":
                entity = get("entity", "power_connection")
                status = get("status", "open")
                invoices = get_invoices(entity, status)
                self.send_json({"entity": entity, "status": status, "count": len(invoices), "invoices": invoices})

            elif path == "/bills":
                entity = get("entity", "power_connection")
                status = get("status", "open")
                bills = get_bills(entity, status)
                self.send_json({"entity": entity, "status": status, "count": len(bills), "bills": bills})

            elif path == "/accounts":
                entity = get("entity", "power_connection")
                accounts = get_accounts(entity)
                self.send_json({"entity": entity, "count": len(accounts), "accounts": accounts})

            elif path == "/customers":
                entity = get("entity", "power_connection")
                customers = get_customers(entity)
                self.send_json({"entity": entity, "count": len(customers), "customers": customers})

            elif path == "/vendors":
                entity = get("entity", "power_connection")
                vendors = get_vendors(entity)
                self.send_json({"entity": entity, "count": len(vendors), "vendors": vendors})

            elif path == "/reports/pl":
                entity = get("entity", "power_connection")
                start = get("start", f"{datetime.utcnow().year}-01-01")
                end = get("end", str(datetime.utcnow().date()))
                report = get_report("ProfitAndLoss", entity, start, end)
                self.send_json({"entity": entity, "period": {"start": start, "end": end}, "report": report})

            elif path == "/reports/bs":
                entity = get("entity", "power_connection")
                start = get("start", f"{datetime.utcnow().year}-01-01")
                end = get("end", str(datetime.utcnow().date()))
                report = get_report("BalanceSheet", entity, start, end)
                self.send_json({"entity": entity, "report": report})

            elif path == "/reports/ar-aging":
                entity = get("entity", "power_connection")
                report = qbo_get("reports/AgedReceivables", entity)
                self.send_json({"entity": entity, "report": report})

            elif path == "/reports/ap-aging":
                entity = get("entity", "power_connection")
                report = qbo_get("reports/AgedPayables", entity)
                self.send_json({"entity": entity, "report": report})

            else:
                self.send_error_json(f"Unknown path: {path}", 404)

        except Exception as e:
            self.send_error_json(str(e), 500)


def main():
    print(f"[QB Connector] Starting on port {PORT}")
    print(f"[QB Connector] OAuth flow: http://localhost:{PORT}/authorize")
    print(f"[QB Connector] Health:     http://localhost:{PORT}/health")
    server = HTTPServer(("0.0.0.0", PORT), QBHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
