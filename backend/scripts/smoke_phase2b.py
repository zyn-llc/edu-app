#!/usr/bin/env python3
"""
Live smoke test for Phase-2b/2c (profile / coins / analysis). Stdlib only.
    python scripts/smoke_phase2b.py [http://127.0.0.1:8000]
Hardened: never crashes on a non-JSON error body — it reports status + raw text.
"""
import json
import sys
import urllib.error
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
PHONE = "+998900000001"
ok = True


def call(method, path, body=None, token=None):
    """Return (status, parsed_json_or_raw_text). Never raises on bad JSON."""
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            raw = r.read().decode("utf-8", "replace")
            status = r.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        status = e.code
    except Exception as e:                      # connection refused, timeout, etc.
        return 0, f"<no response: {e}>"
    try:
        return status, json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        return status, raw                       # non-JSON (e.g. 500 plain text)


def check(name, cond, detail=""):
    global ok
    print(f"  [{'PASS' if cond else 'FAIL'}] {name}" + (f"  {detail}" if detail else ""))
    if not cond:
        ok = False


def js(r):
    return r if isinstance(r, dict) else {}


print(f"== Phase-2b/2c smoke against {BASE} ==")

st, r = call("POST", "/v1/auth/otp/request", {"phone": PHONE, "role": "student"})
code = js(r).get("debug_code")
check("otp/request returns dev code", bool(code), f"status={st} code={code} body={r if not code else ''}")
if not code:
    print("  (stack up? OTP_DEBUG_RETURN=true?) — aborting"); sys.exit(1)

st, r = call("POST", "/v1/auth/otp/verify", {"phone": PHONE, "code": code})
token = js(r).get("access_token")
check("otp/verify returns token", bool(token), f"status={st}")
if not token:
    print("  body:", r); sys.exit(1)

st, r = call("PATCH", "/v1/auth/me",
             {"display_name": "Smoke Test", "region_code": "toshkent_shahri",
              "grade": 10}, token)
check("profile update -> 200", st == 200, f"status={st} body={r}")
check("profile persists name", js(r).get("display_name") == "Smoke Test")
check("profile persists region", js(r).get("region_code") == "toshkent_shahri")

st, r = call("PATCH", "/v1/auth/me", {"region_code": "nope"}, token)
check("invalid region rejected (400)", st == 400, f"status={st}")
st, r = call("PATCH", "/v1/auth/me", {"grade": 99}, token)
check("invalid grade rejected (400)", st == 400, f"status={st}")

st, subs = call("GET", "/v1/subjects")
sid = js(subs).get("items", [{}])[0].get("id")
check("got subjects", bool(sid), f"status={st}")
if not sid:
    sys.exit(1)
st, qs = call("GET", f"/v1/questions?subject_id={sid}&limit=1")
items = js(qs).get("items") or []
check("got a question", bool(items), f"status={st}")
if not items:
    sys.exit(1)
qid = items[0]["id"]
opt0 = items[0].get("options", [{}])[0].get("id")

st, res = call("POST", "/v1/submissions",
               {"question_id": qid, "payload": {"option_ids": [opt0]}}, token)
correct = js(res).get("correct_option_ids") or []
check("submit returns correct ids", bool(correct), f"status={st} body={res if not correct else ''}")
if not correct:
    sys.exit(1)

_, c = call("GET", "/v1/me/coins", token=token); bal0 = js(c).get("balance", 0)
call("POST", "/v1/submissions", {"question_id": qid, "payload": {"option_ids": correct}}, token)
_, c = call("GET", "/v1/me/coins", token=token); bal1 = js(c).get("balance", 0)
call("POST", "/v1/submissions", {"question_id": qid, "payload": {"option_ids": correct}}, token)
_, c = call("GET", "/v1/me/coins", token=token); bal2 = js(c).get("balance", 0)
check("re-answering does NOT double-award coins (anti-farm)", bal1 == bal2,
      f"before={bal0} firstCorrect={bal1} reAnswered={bal2}")

st, a = call("GET", "/v1/me/analysis", token=token)
check("analysis has topics/activity/recent", all(k in js(a) for k in ("topics", "activity", "recent")), f"status={st}")
st, rg = call("GET", "/v1/regions")
check("regions returns 14", len(js(rg).get("regions", [])) == 14, f"status={st}")

print("== RESULT:", "ALL PASS ==" if ok else "FAILURES ABOVE ==")
sys.exit(0 if ok else 1)
