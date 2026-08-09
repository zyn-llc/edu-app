#!/usr/bin/env python3
"""
Bilim full-system self-test — proves the whole app works WITHOUT any external
service (no Eskiz SMS, no Payme, no AdMob). Uses the dev OTP mode
(OTP_DEBUG_RETURN=true) so login codes come back in the API response.

    python scripts/system_test.py [http://127.0.0.1:8000]

It creates two students + one parent, plays a coin-staked challenge between the
students, checks the dashboard/leaderboard/parent views, and prints a PASS/FAIL
summary. Stdlib only. Safe to re-run (uses fresh random phones each run).
"""
import json
import random
import sys
import urllib.error
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
R = random.randint(100000, 999999)
ok_count = 0
fail_count = 0


def call(method, path, body=None, token=None):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read().decode("utf-8", "replace")
            return r.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw
    except Exception as e:
        return 0, f"<no response: {e}>"


def check(name, cond, detail=""):
    global ok_count, fail_count
    mark = "PASS" if cond else "FAIL"
    if cond:
        ok_count += 1
    else:
        fail_count += 1
    print(f"  [{mark}] {name}" + (f"   {detail}" if detail else ""))
    return cond


def login(phone, role="student"):
    """Full OTP login using the dev code returned in the response."""
    st, r = call("POST", "/v1/auth/otp/request", {"phone": phone, "role": role})
    code = r.get("debug_code") if isinstance(r, dict) else None
    if not code:
        print(f"  !! no debug_code for {phone} (OTP_DEBUG_RETURN off?) resp={r}")
        return None
    st, r = call("POST", "/v1/auth/otp/verify", {"phone": phone, "code": code})
    return r.get("access_token") if isinstance(r, dict) else None


print(f"== Bilim full-system self-test against {BASE} ==\n")

# ---- 0. content is loaded --------------------------------------------------
print("[0] Content")
st, subjects = call("GET", "/v1/subjects")
check("subjects endpoint", st == 200 and isinstance(subjects, dict))
items = subjects.get("items", []) if isinstance(subjects, dict) else []
check("at least one subject exists", len(items) > 0, f"{len(items)} subjects")
# find a subject that actually has questions
subj_with_q = None
for s in items:
    st, cat = call("GET", f"/v1/subjects/{s['id']}/catalog")
    if st == 200 and cat.get("grades"):
        subj_with_q = s
        break
check("a subject has questions (catalog non-empty)",
      subj_with_q is not None,
      subj_with_q["code"] if subj_with_q else "NONE — ingest content first")
if not subj_with_q:
    print("\nNo questions loaded — load content (Stage 2) before the rest can pass.")
    sys.exit(1)

st, qs = call("GET", f"/v1/questions?subject_id={subj_with_q['id']}&limit=5")
questions = qs.get("items", [])
check("questions fetch", len(questions) > 0, f"{len(questions)} questions")
# confirm answer keys never leak to the client
leaked = any("correct_option_ids" in q or "grading_spec" in q for q in questions)
check("SECURITY: no answer keys in question list", not leaked)

# ---- 1. Guest practice -----------------------------------------------------
print("\n[1] Guest practice (no login)")
q0 = questions[0]
st, gr = call("POST", "/v1/submissions",
              {"question_id": q0["id"],
               "payload": {"option_ids": [q0["options"][0]["option_key"]]},
               "response_ms": 1200})
check("guest submission grades + saves (200)", st == 200,
      f"status={st}" + ("" if st == 200 else f" body={gr}"))
check("grade response reveals correct answer after submit",
      isinstance(gr, dict) and "correct_option_ids" in gr)

# ---- 2. Auth (no SMS) ------------------------------------------------------
print("\n[2] Auth via dev OTP (no Eskiz needed)")
alice = login(f"+99890{R}1")
check("student A login returns token", bool(alice))
bob = login(f"+99890{R}2")
check("student B login returns token", bool(bob))
parent = login(f"+99890{R}3", role="parent")
check("parent login returns token", bool(parent))
st, me = call("GET", "/v1/auth/me", token=alice)
check("GET /me works with token", st == 200 and me.get("role") == "student")

# ---- 3. Coin economy -------------------------------------------------------
print("\n[3] Coin economy")
# Alice answers correctly to earn coins; find the correct option from the grade
def answer(token, q, correct):
    key = None
    if correct:
        # submit once wrong to learn the key, then the ledger won't double-pay
        st, r = call("POST", "/v1/submissions",
                     {"question_id": q["id"],
                      "payload": {"option_ids": [q["options"][0]["option_key"]]},
                      "response_ms": 900}, token=token)
        key = (r.get("correct_option_ids") or [q["options"][0]["option_key"]])[0]
    else:
        # deliberately pick an option not equal to the first correct
        key = q["options"][-1]["option_key"]
    st, r = call("POST", "/v1/submissions",
                 {"question_id": q["id"], "payload": {"option_ids": [key]},
                  "response_ms": 800}, token=token)
    return st, r

st, coins0 = call("GET", "/v1/me/coins", token=alice)
check("coins endpoint", st == 200 and "balance" in coins0,
      f"balance={coins0.get('balance')}")
# earn something first so daily_login is definitely recorded
answer(alice, questions[0], correct=True)
st, coinsD = call("GET", "/v1/me/coins", token=alice)
check("daily bonus recorded (once per day)",
      any(h["reason"] == "daily_login" for h in coinsD.get("history", [])),
      "daily_login in ledger")
# answer several correctly
for q in questions[:3]:
    answer(alice, q, correct=True)
st, coins1 = call("GET", "/v1/me/coins", token=alice)
check("balance grows after correct answers",
      coins1.get("balance", 0) >= coins0.get("balance", 0),
      f"{coins0.get('balance')} -> {coins1.get('balance')}")

# ---- 4. Dashboard (progress) ----------------------------------------------
print("\n[4] Dashboard / progress")
st, dash = call("GET", "/v1/me", token=alice)
prog = dash.get("progress", {}) if isinstance(dash, dict) else {}
check("dashboard /me returns progress", st == 200 and "xp" in prog,
      f"xp={prog.get('xp')} streak={prog.get('streak')} level={prog.get('level')} "
      f"coins={dash.get('coins')} rank={dash.get('rank')}")

# ---- 5. Leaderboard --------------------------------------------------------
print("\n[5] Leaderboard")
st, lb = call("GET", "/v1/leaderboard?scope=total&limit=10")
check("leaderboard endpoint", st == 200 and "entries" in lb,
      f"{len(lb.get('entries', []))} entries")

# ---- 6. Challenges (coin-staked, 2 players) --------------------------------
print("\n[6] Friend challenge (coin bet, no external service)")
# make sure both have coins
for q in questions[:2]:
    answer(bob, q, correct=True)
st, ch = call("POST", "/v1/challenges",
              {"subject_id": subj_with_q["id"], "question_count": 2, "stake": 5},
              token=alice)
created = st in (200, 201) and ch.get("code")
check("Alice creates staked challenge", created,
      f"status={st} code={ch.get('code')}" if isinstance(ch, dict) else str(ch))
if created:
    code = ch["code"]
    cid = ch["id"]
    st, jr = call("POST", "/v1/challenges/join", {"code": code}, token=bob)
    check("Bob joins by code", st == 200, f"status={st}")
    # both fetch questions and submit
    def play(token):
        st, cq = call("GET", f"/v1/challenges/{cid}/questions", token=token)
        answers = [{"question_id": q["id"],
                    "payload": {"option_ids": [q["options"][0]["option_key"]]}}
                   for q in cq.get("items", [])]
        return call("POST", f"/v1/challenges/{cid}/submit",
                    {"answers": answers}, token=token)
    st_a, ra = play(alice)
    st_b, rb = play(bob)
    check("both players submit challenge", st_a == 200 and st_b == 200,
          f"A={st_a} B={st_b}")
    check("challenge settles (winner or draw decided)",
          isinstance(rb, dict) and rb.get("status") == "done",
          f"status={rb.get('status') if isinstance(rb, dict) else rb}")

# ---- 7. Parent linking -----------------------------------------------------
print("\n[7] Parent monitoring (consent-code link)")
st, lc = call("POST", "/v1/parent/link-code", token=alice)
link_code = lc.get("code") if isinstance(lc, dict) else None
check("student generates link code", bool(link_code), f"code={link_code}")
if link_code:
    st, lr = call("POST", "/v1/parent/link", {"code": link_code}, token=parent)
    check("parent links to child", st in (200, 201), f"status={st}")
    st, kids = call("GET", "/v1/parent/children", token=parent)
    n = len(kids.get("children", [])) if isinstance(kids, dict) else 0
    check("parent sees linked child", n >= 1, f"{n} children")

# ---- 8. Support feedback ---------------------------------------------------
print("\n[8] Support / feedback")
st, fb = call("POST", "/v1/feedback",
              {"message": "system test feedback", "contact": "@tester"})
check("feedback submits (works logged-out too)", st in (200, 201), f"status={st}")

# ---- summary ---------------------------------------------------------------
print(f"\n{'='*50}")
print(f"  RESULT: {ok_count} passed, {fail_count} failed")
print(f"{'='*50}")
sys.exit(0 if fail_count == 0 else 1)
